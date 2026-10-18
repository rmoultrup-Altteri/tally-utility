# Fable review: v5.4.2-23 r1 — cash

**Date:** 2026-10-17. **Frozen hashes:** all five match the brief (executed, `md5 -r`).
**Clone:** `rv23fable` from `tally`, TEMP revoked from PUBLIC, tally_app, tally_core; frozen patch strict-applied (`search_path=''`, `check_function_bodies=on`) cleanly (executed). Dropped at the end.

**Reproduced (executed):** battery-23 frozen: 107 PASS, rolled back. `cash-23-frozen-r1.sh rv23fable`: CR1–CR8, 11 PASS. Mutation runner not run (brief). Seal and periods invariant bodies diffed against `sql/tu.sql`: the seal is exactly -22's plus tally_void's four `ledger_*` EXECUTEs; the periods body is -22's with the trigger name, the three-column FK and the five-function plan-settings list (executed, `diff`).

## Verdict: not yet

Three concrete paths around new rules, each reproduced on the clone. None is in the mutation set, so the "71/71" says nothing about them.

## Blocking

### B1. A credit draws on a payment by label: any origin but `overpayment` naming a payment is uncounted and unapproved (executed)

`cash_source_draws` counts a credit only `WHERE c.origin_type = 'overpayment'`; `enforce_cash_draw` on customer_credits fires only `WHEN (NEW.origin_type = 'overpayment')`; the approval CHECK keys on `origin_type = 'overpayment'`. Nothing ties `source_payment_id` to the origin. So (memory "guard the act, not the label"):

```
P1 posted 100, applied 100 (60 + 40)                      -> position remaining 0
INSERT customer_credits (origin_type 'goodwill', original_amount 100, source_payment_id = P1)  -> admitted, no approval
INSERT invoice_applications from that credit, 60 to I2's gas line                               -> admitted
payment_position_as_of(P1): applied 100, credited 0, remaining 0; cash_source_draws(P1): 2 rows, 100
```

The payment's money is spent twice; C1 (approval) and the A3 cap are both bypassed by choosing another origin. Fix: key the draw, the trigger WHEN and the approval rule on `source_payment_id IS NOT NULL` (the act), and either forbid `source_payment_id` on other origins or treat every credit naming a payment as drawing on it.

### B2. An application lands on a bounced payment: the source's status is read before the source's lock (executed, three sessions)

`enforce_invoice_application` reads `v_pay.status = 'posted'` at its top, then calls `rule_row_cite` (a shared advisory lock on the tariff row, which can wait), then `check_cash_source` (the source lock, cap, recorded order). `check_cash_source` never re-reads the status. The payment's move to nsf takes the source lock and checks applications under it, so the two serialise only if the application holds the lock first (CR3 tests that side only).

Repro (owner holds the tariff row's advisory lock exclusively for 7 s, as a tariff close would):
```
X: pg_advisory_xact_lock(rule_row_lock_key('public.payment_allocation_tariffs', TAR))   -- holds
A: INSERT application 10 of P2 (posted 50) citing TAR   -> reads status posted, blocks in rule_row_cite (seen in pg_blocking_pids)
B: INSERT nsf ledger row +50 naming P2's posting entry; UPDATE P2 status='nsf', status_cause_id=...  -> source lock free, applications 0, commits
X: commits. A: check_cash_source: cap 10 of 50, commits.
Result: P2 status=nsf, applications=10.00
```
The same shape holds for a credit (`v_cred.status` read before the lock), for `enforce_cash_draw` (status read, then lock) and for the invoice (`v_inv.status`, though there the FK's KEY SHARE on the invoice row serialises against the void's FOR UPDATE, so it holds). Fix: re-read source status and amount inside `check_cash_source` after the lock (or take the source lock before any read of it); the stated lock order (head, tariff, source, line) is kept if the re-read happens after the tariff lock.

### B3. A payment with a refund outstanding moves to nsf, reversed or voided; the refund stands (executed)

The "guard the act" on nsf/reversed/voided checks applications net to 0 and no live overpayment credit — not refunds. Note `payments.status` defaults to `'posted'`, so a refund inserted without a status is posted at once (executed: the fixture refund's status reads `posted`).
```
P2 posted 50; INSERT refund -30 refunds_payment_id = P2 (born posted)
INSERT nsf row +50 naming P2's posting entry; UPDATE P2 status='nsf', status_cause_id=... -> admitted
P2 nsf, refund posted -30
```
Money that never arrived is being returned to the customer. Fix: the nsf/reversed/voided guard also requires no pending or posted refund of the payment (or the refund moved first), and the same for a credit's void (its guard does check `refunded`, correctly).

## Should fix

### S1. A voided overpayment credit still draws on its payment; the payment's money is stuck and its position reads 0 (executed)
`cash_source_draws` and `payment_position_as_of` count overpayment credits whatever their status, while the nsf guard excludes `status = 'voided'` credits ("void its credit first"). P3 50 → approval 50 → credit 50 → issuing entry reversed → credit voided (admitted). Then: `payment_position_as_of(P3)`: credited 50, remaining 0. A refund of 50 is refused ("would come to 100.00, more than its 50.00"); an application of 1 is refused (51 of 50); the nsf move is admitted. The 50 can never be returned or applied, and the position says nothing is owed. Exclude voided credits from the draws and the position, as voided refunds are excluded.

### S2. A payment refunded in part and then returned cannot post its nsf (executed) — a design question
X1 makes every `refund` and `nsf` row name an entry; X2 caps the entry. P3 -50 posted; refund +30 naming it; nsf +50 naming it → refused ("would come to 80.00, outside 0 to 50.00"). The nsf cannot name the refund row either (same sign). With B3, a check refunded before it bounces has no lawful record: the payment stays posted and the 30 is recovered only by an adjustment naming nothing. Either a refund is not a reversal of the payment entry (its own movement, `reference_type refund`, naming nothing) or the nsf nets refunds already out. For Kyle/Ryan; the patch should not freeze X1's list before this is settled.

### S3. Births skip the move rule (executed)
As tally_app, a payment born `refunded` or `nsf` with no cause and no ledger row is admitted; born `posted` is the default and needs no posting entry (the battery's own fixtures rely on it). Q1 (a) binds moves only. A payment born posted with no ledger row "moved money" nowhere. Restrict births to pending or posted, and require a posted birth to be followed by... or at least refuse births in the terminal statuses.

### S4. `refunded` accepts a voided (or bounced) refund as its cause (executed)
Cause check for `refunded` is `r.refunds_payment_id = NEW.id` with no status. P1 100: refund -100 pending → voided; P1 applied 100 to I1; `UPDATE P1 status='refunded', status_cause_id = the voided refund` → admitted (remaining is 0 through the applications). Require the cause refund pending or posted.

### S5. Source checks fail open on an unknown or invisible source (executed for unknown; invisible predicted)
`check_cash_source('payment', <no such id>, now())` returns without error: `v_amount` NULL makes `x.drawn > v_amount` never true. In `enforce_invoice_application`, a NULL `v_pay` makes `NOT (v_pay.status = 'posted' AND ...)` NULL, so the IF does not fire. Today RLS WITH CHECK on invoice_applications keeps the application in the writer's tenant and the FKs keep the source in it, so the invisible case is unreachable; write the guards fail-closed anyway (`IF NOT FOUND THEN RAISE`), as the ledger trigger does.

### S6. Tests weaker than their coverage claims
- The credit refund leg (`refunds_customer_credit_id`: `enforce_cash_draw`'s ELSE branch, the credit leg of `cash_source_draws`, the credit's `refunded` move) has no battery row; mutations N40/N61 mutate only shared lines. I executed it (cap and move work), but a mutation of the ELSE branch would pass.
- `invoice_line_class_gap`'s rate-item branch (`rate_item_as_of`) has no test (LC1 is the one-off charge branch; N36 likewise).
- A restricted payment claiming `restriction` on a line outside its target is untested (A4e is the unrestricted case); executed: refused.
- No test of a payment's `reversed` or `voided` move, of a credit's `escheated` or `donated` move, or of the "on the ledger: reversed, not voided" check.
- No multi-row, writable-CTE or COPY shape for applications or reversals in -23 (executed: two reversals of one charge in one VALUES, and in a writable CTE, are both refused by the cap).

### S7. Any row type may name an entry, so a payment entry naming a charge "reverses" it (executed)
A `payment` row (-100, reference payment P1) with `reverses_ledger_entry_id` = I3's charge is admitted; `ledger_entry_remaining(charge)` = 0, so a void of I3 would post nothing. X1 lets every type name an entry; the void and the cap then read a payment as a reversal. Either limit naming to the reversal-natured types plus `adjustment`, or have the void net only reversal-natured rows.

## Notes

**N1. The general cap (X2) is the same check as netting each path ancestor's subtree (argued).** `m` for a row is the number of path entries above it; rows under `v_down[j]` are exactly those with `m >= j` (a branch off the path at `v_down[j]` inherits `m = j` from `CASE WHEN t.onpath ... ELSE t.m`; `onpath` becomes NULL past the path's end, which the CASE treats as false). `generate_series(1, m)` pairs each row with its path ancestors and the window `PARTITION BY j ORDER BY on_date` (RANGE frame) nets one date's rows together. Siblings and off-path branches: their subtrees are unchanged by the new row, so only path entries need checking. An earlier-dated row under a later one cannot arise (the date rule, by induction) except by an owner's planted history. Executed: X2e, X2f, R11e, and the multi-row/CTE shapes.

**N2. Positions and the recorded instant.** The recorded-order rule holds per tree, per source and per line, so a position at `(d, R)` is fixed once any row recorded after R is in. Until then a transaction that began before R can still commit a row with `created_at < R` (a payment with no draws has no handshake at all), so a reader choosing R = now sees rows appear. That is -22's model and acceptable, but say so in the position comments. R2 (refund status read live) is a real retroactive hole: when a counted refund moves to nsf, every past `(d, R)` loses `refunded`; the nsf row naming the refund's posting entry has a `created_at`, so the refund's state at R could be derived from the ledger instead.

**N3. Lock order.** The void takes the invoice FOR UPDATE before the head FOR SHARE; an application takes the head (freeze) then the invoice's KEY SHARE (FK). With a close queued on the head FOR UPDATE, void→close→application→void can cycle; PostgreSQL aborts one and a retry resolves it. State it in the rule ("the void's invoice row first"). No cap is a bare count: every cap runs under its lock after the row is in (executed CR1, CR2, CR5, CR8; B2 is a status read outside the lock, not a count).

**N4. floor_over_restriction** needs an unregulated target line with `amount > 0`, not an open one: once the target is fully paid (40 of 40, basis restriction), a further `floor_over_restriction` on I1's gas line is admitted (executed). Both answers are recorded faithfully for Kyle; whether the floor should require an *open* target is part of his question.

**N5. The seal.** The four grants are the least the void needs (`ledger_entry_remaining` calls `ledger_tree_ids` with invoker rights; the reversal trigger fired by the void's insert calls `ledger_tree_lock_key`). tally_core is also granted `ledger_tree_lock_key`, which a read-only role never needs. `is_invoice_issued` and the other helpers reach tally_void through PUBLIC EXECUTE, as before.

**N6. Older tests (R8).** Every change follows a -23 rule (X1b: R3, R10f, R12o, W13; X2 sign: R10, R12n, CR11; date: W14/W14b; recorded time: W8, C19, X2g; M2: P9c–P9g, C8/C9). Two are narrower than before, justified by R1: R10g 300→200 deep in one statement, and R11b/R11c plant the first 998/1000 entries with both chain guards off, so the lineage walk is exercised only at the last one or two links. -21's fixtures turned `overpayment` credits into `adjustment` (C1), fine. P9e flips from admitted to refused under R-05: correct, not a loosening.

**N7. Depth bound.** `ledger_tree_root` and the trigger's walks are bounded at 1000 and fail closed; `ledger_tree_ids` is unbounded but uses UNION (deduplicating), so a planted loop terminates. All five pinned functions carry the plan settings (invariant executed in the tail). Edge: when `ledger_tree_root` returns NULL (a planted chain past 1000), `pg_advisory_xact_lock(ledger_tree_lock_key(NULL))` is a strict-NULL no-op and the void reads `ledger_entry_remaining` unlocked; owner-planted only.

**N8. `enforce_invoice_line_class` is gated exactly as `enforce_invoice_line_arithmetic`** (executed: body comparison — same three early returns, same snapshot lookup, FOR SHARE on the lines, `now()` knowledge).

**N9. Invariants.** 28 trigger and 34 constraint strings counted; the approval index, the eight absent columns, the four functions' plan settings and tally_app's reach are checked as claimed. Narrower than its name: it pins the `WHEN (origin_type = 'overpayment')` clause, i.e. the label-keyed guard of B1; it does not pin `payments.status`'s default (`'posted'`, see B3), the RLS policies of the new tables (tenant isolation does), or the EXECUTE grants of `check_cash_source`.

**N10. K-07.** `payments.payer_class DEFAULT 'customer'` is an assumed default; harmless, but the restriction columns are what carry the act.

**N11. The void and future-dated reversals.** The void posts at CURRENT_DATE for `ledger_entry_remaining` (all dates); a reversal under the charge dated after today would make the void's row exceed the cap at today and be refused. Edge.

**N12. Residuals R1–R8.** None blocking. R2 is a hole (N2) worth closing from the ledger. R4 means `invoice_position_as_of` of a void bill still shows money applied — say so in its comment.

## Probe record
All probes ran as tally_app under `app.user_id` unless noted, each in a transaction ended by ROLLBACK (B2's race committed three rows in the clone). Fixtures: tenant `…fab0`, customer `…fab2`, bills I1–I3 (60 regulated + 40 unregulated), payments P1 100, P2 50, P3 50, P4 100 agency restricted to I2's add-on, posting entries for P2 and P3, a 100 charge for I3, one tariff row. Files: scratchpad `probes1.sql`, `race-h.sh`.
