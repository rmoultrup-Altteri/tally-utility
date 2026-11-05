# Opus review — v5.4.2-27 r1 (shortfall applications)

**Verdict: not yet.** Two blocking findings, both executed. The rest of the patch is sound: the re-issued -23 functions add only, the caps hold for multi-row, writable-CTE and COPY shapes, and the battery and races reproduce.

## Hashes and reproduction (executed)

- All five frozen md5s match the brief (patch f1fbdf15…, battery 5db82bc7…, races babf6406…, mutations c8be8e11…, ci diff bb7f2e5f…).
- Scratch DB `rv27opus`: `CREATE DATABASE … TEMPLATE tally`, then `REVOKE TEMP … FROM PUBLIC, tally_app, tally_core`. The frozen patch was strict-applied twice (`search_path=`, `check_function_bodies=on`): the first run rc=0, the second skipped by its marker.
- `battery-27-frozen-r1.sql`: 80 PASS, no FAIL.
- `shortfall-27-frozen-r1.sh rv27opus`: 14 PASS (SR1–SR8).
- I did not run the mutations or ci.sh, as the brief says.

Probes are below. Each one is the battery's own prelude (everything above `-- === D the freeze`) followed by the probe, in one transaction, rolled back.

---

## B1 (executed). Money comes back to a repaid family with no undo: the leaving check reads from the latest shortfall row's date, so earlier dates go unchecked

`check_shortfall_repaid(p, NULL)` checks from `max(applied_on)` over the target's shortfall rows. It is called after a refund of the family leaves (`enforce_shortfall_source_moves`) and after an undo in `check_cash_source`. A returned refund stops counting on **every** date (-23 reads it by status). Section 8 accepts that, between a repayment's date and its undo's date, the money "briefly reads back" and the undo settles it. But nothing requires an undo at all, or any money at the latest date. When the family's debt grows with its dates (a later-dated refund still standing), a refund can leave and the family holds money on every date between the first repayment and the latest row. Nothing is undone, and nothing re-checks those dates.

The battery's own H fixture (C6, after H2b) shows it. PH (6f) pays 50, all of it held as credit KH. KH refunds 10 dated 03-10 (7b) and 30 dated 03-18 (7c). PH bounces on 03-12. Repayments: 10 dated 03-13 (GH2) and 20 dated 03-18 (GH1). Then refund 7b's check comes back:

```sql
SET ROLE tally_app; SELECT set_config('app.user_id','…27b1',true);
INSERT INTO account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reverses_ledger_entry_id)
VALUES (k('f9'), T1, C6, DATE '2026-03-19', 'nsf', 'refund check 7b returned', -10, k('aa'));
UPDATE payments SET status='nsf', nsf_date=DATE '2026-03-19', status_cause_id=k('f9') WHERE id=k('7b');   -- ADMITTED
```

PH's position (remaining/repaid), before and after:

| date | before | after |
|---|---|---|
| 03-13 … 03-17 | 0.00/10.00 | **10.00/10.00** |
| 03-18, 03-19 | 0.00/30.00 | 0.00/30.00 |

On 03-13 to 03-17 the bounced payment now reads +10 of money, for good. No undo was recorded, and Ryan's option 1 refusal never fired: the check started at 03-18, where the family is square. The patch's own repayment check refuses the same state built directly. In the same transaction, a 0.01 repayment dated 03-13 is refused with "on 2026-03-13 … holding 10.01". So the end state is one the patch would never admit row by row. The table comment's claim ("from the first repayment's date on, the target and its overpayment family never hold money") is broken, and the core would read an ended payment holding customer money on those dates (statements, aging, the pot).

The money cannot be spent through this path: every draw cap is cumulative, so a family draw dated in the window is refused at the later dates. The damage is to what the positions read on past dates. It still breaks the stated rule, and it is the ruling's own case (a refund comes back after its shortfall was repaid), admitted without the undo.

**Fix options (not measured).** The obvious one is checking from `min(applied_on)`, but that breaks the S4 flow (undo dated 03-14 after a repayment dated 03-13), which mutation M17 deliberately defends. Two options that keep the operator able to act:
1. Check leaving moves from the first repayment's date, or from the first open day if that is later, and require the operator's undo to be dated on the repayment's date while that date is open. Frozen dates stay as the close left them. S4 changes: its undo would be dated 03-13.
2. Keep the latest-row start date, but also refuse any date from the first repayment on where the family holds more after the move than before it. That refuses what the move newly frees, and leaves the accepted repayment-to-undo window alone. This costs a second sum (before and after) inside the same lock.

Either way, add H-shaped battery checks (refund 7b leaving with no undo must be refused) and a mutation for them.

## B2 (executed). Once a source credit is escheated, its repayment can never be undone, so the refund's return can never be recorded

Option 1 says the operator undoes the repayment first. The undo goes through `check_cash_source(…, 'undo')`, which admits a source only while it has not ended (`v_status IN ('posted','active')`). A credit that applied part of itself to a shortfall can still be escheated for the rest. Escheating needs remaining = 0 and a remittance more than 0, and the shortfall application counts in applied. After that the undo is refused, so the refund's move to nsf is refused for good. The bank's news cannot be recorded. This is the same trap as the `append-only-vs-unique-deadlock` lesson.

```sql
-- C5: PE (e9) pays 50, refunded 30 (ea, posting entry eb), bounces: 30 short. GE (ec), goodwill 30.
SELECT pg_temp.sa(k('b9'), C5, k('e9'), NULL, k('ec'), 20, DATE '2026-03-13');            -- admitted
INSERT INTO escheatment_events (id, tenant_id, customer_credit_id, customer_id, event_type, amount_related, event_date)
VALUES (k('ba'), T1, k('ec'), C5, 'escheated_to_state', 10, '2026-03-14 12:00+00');         -- admitted
UPDATE customer_credits SET status='escheated', status_cause_id=k('ba'), escheated_at=now() WHERE id=k('ec');  -- admitted
INSERT INTO account_ledger (…) VALUES (k('bb'), …, DATE '2026-03-15', 'nsf', 'refund check returned', -30, k('eb'));  -- admitted
UPDATE payments SET status='nsf', … status_cause_id=k('bb') WHERE id=k('ea');
--   ERROR 23514: on 2026-03-13 … holding 20.00 … undo the shortfall application first
SELECT pg_temp.sa(NULL, C5, k('e9'), NULL, k('ec'), -20, DATE '2026-03-15', 'undo', k('b9'));
--   ERROR 23514: a row drawing on credit …ec (escheated) for undo: … an undo only while its source has not ended
```

Nothing else unblocks it. An undo must name its own source, and the family is already square. The same dead end applies to the other moves option 1 gates: a donation or application undo on a family credit, or a family credit's refund leaving.

**This needs a call from Ryan; the fix is a design choice.**
- (a) An undo whose source has ended carries the money into a new credit. That is -23's rule for a credit's refund that came back after an escheat (Ryan, 2026-10-21: carried into a refund_reissue credit).
- (b) A credit is not escheated while any of its money is applied to a shortfall. That is simple, but it strands the remainder, which can never be remitted.
- (c) The escheat is refused only while the target could still shrink (it or its family has a refund that could come back, or a donation or application that could be undone). That is narrower, but it is a check on another family's state.

I recommend (a). It reuses an existing ruling and keeps escheat working. Add the probe above as a battery check either way.

---

## S1 (executed). A bounced deposit is admitted as a target; neither the design nor the patch says it should be

`enforce_shortfall_application` checks only `status IN ('nsf','reversed')`. A deposit of 40, refunded 40 and then bounced, reads -40/0, and a goodwill credit's 20 repaid it (-20.00/20.00, credit 0.00). The brief and the design keep deposits out of the pot as sources (-15 settles them). Netting general credits against a deposit's shortfall is a deposit-policy question (state deposit rules, -15's machinery). The design should state it either way. If it is not intended, refuse `is_deposit` targets. If it is, say so and check -15's deposit readers, which I did not trace (predicted: they read deposit events, not `repaid`).

## S2 (executed). A refund payment is refused as a target only by accident, with a misleading message

Target = refund 67 (nsf) is refused by `check_shortfall_repaid`'s arithmetic ("would leave it … holding 5.00"), not by a rule. A refund has no shortfall. Refuse targets with `refunds_payment_id` or `refunds_customer_credit_id` set, and add a battery check. As things stand, a mutation that changed the cap's sign handling could open this path, and no test would notice.

## S3 (predicted). Test gaps

- B1's shape and B2's shape, as above.
- The undo of an **invoice application** on a repaid family's credit (`enforce_invoice_application` → `check_cash_source` undo). The battery has no bills, so only the donation-undo path (U2) is exercised. The code path is shared, so I predict it is refused correctly, but untested.
- No race for a **family credit's** refund leaving against a repayment under the target's lock. SR4 covers a refund of the payment itself; SR8 covers recorded order, not the lock. The lock comes from -23 (`enforce_payment_immutable` locks `overpayment_root`'s payment), so I predict it holds.
- No mutation on `check_shortfall_repaid`'s family-credits leg or its arrival-entry legs. F4/F5 would probably catch them, but nothing names them.

---

## Notes

- **N1 (executed). Re-issued functions differ from -23's by additions only.** I diffed `prosrc`, `proconfig`, volatility and ACL for all six against `tally`: the only differences are the added shortfall terms, the two new purposes, the `shortfall_within_family` exemption and the undo call. The two dropped and re-created functions (`payment_draws_as_of`, `payment_position_as_of`) have no callers outside -23's own readers, and no view depends on them.
- **N2 (executed). Statement shapes hold.** Two rows of 6+5 against 10 owed are refused as one multi-row INSERT and as a writable CTE (AFTER ROW triggers see both rows). A repayment and its undo in one INSERT net to nothing. COPY as tally_app is refused by row-level security, and the owner's COPY meets the same ENABLE ALWAYS triggers.
- **N3 (read). The header's `cash_drawn_at` claim holds.** Its only reader is `overpayment_shares`, which reads it at a take-back row's instant on a posting tree. On a target's tree every row is recorded before any repayment (`check_cash_order`). On a source's tree, a take-back is refused while its shortfall applications net to more than 0, and a chosen time before an existing shortfall row is refused (23514).
- **N4 (read). Locks.** Every reader of `check_shortfall_repaid` and `shortfall_applied_from` runs under the target payment's lock, which every writer on the family takes: draws via `check_cash_source`'s pool lock, refunds leaving via `enforce_payment_immutable`, ledger rows via `enforce_ledger_reversal`. Each check is its own statement in a volatile caller, so it gets a fresh snapshot after the lock. I found no lock cycle beyond the stated cross-family one (40P01, retried).
- **N5 (executed). The within-family exemption** is reached only when `overpayment_root(source).source_payment_id = target`. The source's own cap still applies (F1). In `check_shortfall_repaid` the move nets to 0 (the source's draw counts outside the family, and the target's repaid counts negative). A voided root with an active reissue, which would drop the family's draws, cannot arise: the root's void needs its draws, reissues included, to net to 0.
- **N6 (read). The invariant `assert_shortfall_guard_invariants`** checks tally_core for INSERT, UPDATE, DELETE and TRUNCATE but not REFERENCES or TRIGGER, which its comment implies ("tally_core only read it"). It is narrower than its claim, though harmless today. The design (section 5) said the table would join `assert_periods_guard_invariants`' freeze list and `assert_cash_guard_invariants`. It is pinned in its own invariant instead; record that in section 8.
- **N7 (read). Battery K3b** looks for a ledger row only with `reference_type = 'customer_credit'`. A stray row with `reference_type 'payment'` would slip past it. The balance equality beside it would catch one, so this is only a label weaker than its check.
- **N8 (executed). Add-up property.** At 12-31 every battery customer's payment and credit positions sum to minus the ledger balance, both before and after my B1 probe. Gaps on earlier dates exist before -27 as well: they are -23's convention that a returned refund stops counting on every date while its ledger row is dated.
- **N9. Residuals R1–R4:** none is blocking. R3 (a partly reversed posted payment is not a target) is stated and consistent with the target rule.
