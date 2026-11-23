# Fable review — v5.4.2-24 r10 (unmatched cash and agency pledges)

**Date:** 2026-11-22. **Reviewer:** Fable (claude-fable-5-1). **Brief:** `review-brief-24-r10.md` (md5 `2c1baad89f2410260629edbf17621471`, matched its `.md5`).

**Frozen hashes checked, all matched:** patch `72fdcfdc…`, battery `e7bbce6f…`, races `55c63199…` (unchanged from r6), mutations `b15bec4e…`, ci diff `c343828b…` (unchanged from r1), r9-to-r10 `31b5de18…`. I reviewed the frozen copies only.

**Verdict: ready.** Every round-9 finding is closed as the plan states it, and every earlier one still holds (the whole battery, the races and three of the new mutations re-ran here). No blocking item. Two should-fix items, both executed: one on a test's reach (S4c's list of seven receipts is a consequence of its own bank term; with the term right it holds for every receipt of the tenant), and one on a superuser history load (a receipt's payment born `reversed` with no return code and no rows uses up its receipt with its money nowhere, and nothing can ever read or return it). The second is a six-line refusal at insert; I recommend taking it before the mirror, which would make r11 a narrow re-review. That is the author's and Ryan's call; the patch as frozen is sound for every role the application runs as.

**Scratch database:** `rv24fable` (TEMPLATE `tally`; TEMP revoked from PUBLIC, `tally_app`, `tally_core` right after creation; frozen r10 patch applied strictly twice; the battery; my probes spliced into a copy of the battery and rolled back with it; the races; three mutations and the proposed S2 rule applied by hand to the clone's functions and reverted, the invariants clean after each restore; dropped at the end). I did not run `ci.sh` or `mutations-24.py`; created, dropped or altered no role; read no `opus-*` or `codex-*` file. Two `crystaldba/postgres-mcp` containers were running at my start; I did not touch them.

## Reproduced (executed)

- Strict apply (`search_path=''`, `check_function_bodies=on`): clean; the second run is skipped by its marker ("already applied (suspense_receipts exists)").
- `battery-24-frozen-r10.sql`: **309 PASS**, 0 FAIL (rolled back).
- `suspense-24-frozen-r10.sh rv24fable`: **24 PASS**.
- `assert_suspense_pledge_guard_invariants()` on the clone: clean after the battery, after the races, and after each hand-applied mutation was reverted. The four re-pinned bodies (`check_suspense_recorded_order`, `enforce_payment_suspense_pledge`, `enforce_suspense_disposition`, `suspense_misposting_returns_due_as_of`) and the new one (`suspense_misposted_share_as_of`) hash to the pinned values.
- **M142, M131, M125 by hand** (the mutation's exact text applied to the clone's function, battery run, body restored): first failure `FAIL S8j`, `FAIL S8r`, `FAIL P12a` respectively, each the check the runner names.
- Trigger order on `payments` unchanged from r9 (-23's `a_*` first, then `enforce_cash_draw`, `enforce_escheated_credit_settled`, `enforce_payment_effective_date`, `enforce_payment_immutable`, `enforce_payment_suspense_cap`, `enforce_payment_suspense_pledge`, `enforce_shortfall_source_moves`; all ENABLE ALWAYS but `set_updated_at`).
- The reader as `tally_app`, `tally_core` and the owner gives the same five rows, 340.00 owed (probe FJ); `suspense_misposted_share_as_of` runs as `tally_app` (b3: 100 since 03-13). The list at 12-31 (FK): Rb4's payment, posted and partly reversed, 60 since 03-11; Rb3's, reversed with no code, 60 since 03-12; b3, 100 since 03-13; the O1i payment, nsf, 60 since 04-03; and a payment of my own.

## Round-9 findings — closed as written (executed)

- **The reader at past coordinates** (Codex B1, Opus S1, my S1). `suspense_misposted_share_as_of` is the guard's walk with every row held to the money date and the recorded instant, and the payment itself to its date and its recorded time; the reader lists by the share there. My r9 FD/FX/FI fixtures are now the battery's S8j (b3: 100 on 03-11, none on 03-12, 100 since 03-13), S8k (9b not listed at its status instant), S8l (payment 20 not before its own date), S8m (1d listed between its reversal and its undo where the bank took all later); S4b adds the amount due. My r9 recommendation differed in one point (keep `status = 'reversed'`); the plan took Opus's, because item 2's payments must be listed, and that is right: a payment partly reversed and still posted is money on no account and not on the receipt.
  - `since` (probes FC1–FC3, dated in May, an open period): a same-day undo and re-reversal leave `since` at the first reversal (the day's net never reaches 0); a second undo and a third reversal move it to the third (none on the undo's day); 60 reversed, undone, 40 reversed again, the rest bounced: 60 since the 11th, none on the 12th, 40 since the 13th, and the return takes exactly 40 (60 refused "40.00 of its 100.00"), the receipt then holds 40.
- **The stranded share** (Opus S2). P15–P15h, P16, P16b pass. The rule taken (reversed takes a code only where the share is 0 or the whole; a bounce gives back its share, its code notwithstanding) is the sound one of the two: Opus's would return money a coded reversal had taken. Attacked:
  - *Writable CTE* (FB, FB2): the last reversal row and the coded end in one statement, and both rows and the end in one statement, are refused — by -23, 23503 ("the move to reversed names the row behind it … which then has nothing left"): the trigger does not see the rows the same statement inserted. The plan credits the refusal to the new rule; the SQLSTATE says it is -23's status-cause check that fires first. Same outcome, no change needed.
  - *Multi-row UPDATE* (FE): a code written on a mixed tree and on a whole bounce in one statement is refused by the mixed one (23514, the new message); the whole bounce alone is admitted.
  - *The tree after an nsf ending* (FD, Rb1's payment after its return): a give-back under the reversal row 23001 ("which has ended"), a further take-back under the posting entry 23514 (the R-02 cap), a redeposit under the nsf row 23001. So the share the nsf return gives back is final, as the reversed case's is.
  - *The code's lock order*: the receipt lock is taken in the same branch as before (payment lock by -23's `a_` trigger first, then the receipt), and the share is read after it. The tree is already whole when the status moves (-23 needs the posting entry's remaining at 0), so the share the check reads cannot change under it.
  - *A history load*: see S2 and question 2.
- **Tests** (Opus S3, Codex S1, Fable): S4b includes the amount due; S4c runs; S8f–S8s, O1i, P12a, P15–P16b present and passing; M120–M144 present, three re-run by hand. On S4c's seven receipts, see S1.

Rounds 1–8 (my r1 B1, B2, S1, S2; r2 B1, S1; r3 B1, S1; r4 B1; r5 S1, S2; r6 S1 = S4b; r7, r8, r9 as above; and the brief's list for Opus's and Codex's) are still closed by the same battery checks, which all ran again here.

## S — should fix

### S1 (executed). S4c's seven receipts are picked around its own bank term; with the term right, conservation holds for every receipt of the tenant.

S4c's fifth term sums every positive nsf row dated by the day. That over-counts a take-back the bank later paid after all (the undo beneath the nsf row is not subtracted: R19/k('14') reads 200 and R22/k('17') 140 from 03-12 on) and misses a take-back recorded as `reversed` with a code (R9/k('09'): 0, the whole receipt in no term). Probe FA ran S4c's own formula over every T1 receipt: exactly those three fail, and nothing else. So the seven were the receipts the formula happens to fit, not a principled sample.

With the bank term as the net of each positive nsf row's subtree, plus, for a payment reversed with a code, its amount less its nsf net (the bank took all of it), probe FA3 finds **no receipt off by a cent on any day 03-10 to 03-20, over all 21 receipts of T1 with payments**: held + on accounts + left + due + the bank's = the receipt everywhere. That is the strongest statement the round can make, and it should be the check. Proposed S4c body (executed against the frozen patch, 0 rows):

```sql
SELECT pg_temp.ok('S4c conservation, the other way: no receipt''s money is in no place (every receipt of T1, every day; the bank''s is the net of each nsf tree, and a payment reversed with a code is the bank''s whole)',
  NOT EXISTS (
    WITH RECURSIVE nsfroot AS (
        SELECT l.id, p.suspense_receipt_id AS rid, p.id AS pid, l.transaction_date, l.amount
          FROM public.payments p JOIN public.account_ledger l ON l.reference_type = 'payment' AND l.reference_id = p.id
         WHERE p.suspense_receipt_id IS NOT NULL AND l.transaction_type = 'nsf' AND l.amount > 0
        UNION ALL
        SELECT l.id, n.rid, n.pid, l.transaction_date, l.amount
          FROM nsfroot n JOIN public.account_ledger l ON l.reverses_ledger_entry_id = n.id)
    SELECT 1 FROM public.suspense_receipts r
      CROSS JOIN generate_series(DATE '2026-03-10', DATE '2026-03-20', '1 day') g(d)
      CROSS JOIN LATERAL (SELECT coalesce((SELECT x.held FROM public.suspense_receipt_position_as_of(r.id, g.d::date, clock_timestamp()) x), 0)
             + coalesce((SELECT sum(y.received) FROM public.payments p CROSS JOIN LATERAL public.payment_position_as_of(p.id, g.d::date, clock_timestamp()) y WHERE p.suspense_receipt_id = r.id), 0)
             + coalesce((SELECT sum(x.amount) FROM public.suspense_receipt_dispositions x WHERE x.suspense_receipt_id = r.id AND x.kind <> 'misposting_returned' AND x.disposed_on <= g.d), 0)
             + coalesce((SELECT sum(z.owed) FROM public.suspense_misposting_returns_due_as_of(pg_temp.t1(), g.d::date, clock_timestamp()) z WHERE z.receipt_id = r.id), 0)
             + coalesce((SELECT sum(n.amount) FROM nsfroot n WHERE n.rid = r.id AND n.transaction_date <= g.d), 0)
             + coalesce((SELECT sum(p.amount - coalesce((SELECT sum(n.amount) FROM nsfroot n WHERE n.pid = p.id AND n.transaction_date <= g.d), 0))
                           FROM public.payments p WHERE p.suspense_receipt_id = r.id AND p.status = 'reversed' AND p.return_code IS NOT NULL
                            AND EXISTS (SELECT 1 FROM public.account_ledger l WHERE l.id = p.status_cause_id AND l.transaction_date <= g.d)), 0) AS total) t
     WHERE r.tenant_id = pg_temp.t1() AND r.received_on <= g.d AND t.total <> r.amount));
```

(The payment's own date is not a term here because every payment of these receipts is dated on its receipt's day; a receipt whose payment is dated later, R20, is held by S4b's "never more" direction.) The mutations that name S4c keep their anchors; none is lost.

### S2 (executed). A superuser's history load can bear a receipt's payment `reversed` with no return code and no rows: the receipt is spent, nothing lists the money, nothing can return it, and no row can ever follow.

Probe FG, as the owner: a payment born `reversed`, no code, no `status_cause_id`, naming a receipt of 100, is admitted (-23's born-pending rule exempts a superuser). Then: the receipt holds 0 (FG3: the cap counts it as spent); the reader lists nothing (its share is 0, there is no tree); a misposting return is refused (FG4: "0 of its 100.00"); and a posting entry can no longer be loaded for it (FG5, -23: "a posting row is written for a payment still pending, before its move to posted"). The same payment born with a code (FG1) is coherent: the bank took all of it, and the receipt is rightly spent. Born `nsf` is coherent for the same reason. Born `reversed` with no code is the one shape whose meaning ("its misposted share comes back") can never be made true, and CI-053 is "held, never dropped" for every role.

The application cannot do it (question 2 below). The fix is a refusal at insert, for every role, in `enforce_payment_suspense_pledge`'s INSERT branch, after the provider check. Applied to the clone: the battery's 289 checks before the invariant pins still pass (the pins change, as every body change does); FG2 is refused 23514 with the message below; FG1 is still admitted; the receipt then still holds its 100.

```sql
    -- A receipt's payment born reversed with no bank return code has no tree
    -- and can never get one (-23 refuses a posting row for an ended payment),
    -- so its share is 0 for good: it would use up the receipt with its money
    -- nowhere (CI-053). A load walks it through its moves, as R25's and Rb7's do.
    IF NEW.suspense_receipt_id IS NOT NULL AND NEW.status = 'reversed' AND NEW.return_code IS NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('payment %s is born reversed with no return code from receipt %s: nothing could ever read or return its misposted share; load it pending and move it through its rows (CI-053, v5.4.2-24)', NEW.payment_number, NEW.suspense_receipt_id),
            ERRCODE = 'check_violation';
    END IF;
```

A check beside the r6 history-load block (owner role), and its mutation:

```sql
SELECT pg_temp.refuses_at('O7 a load''s payment of a receipt born reversed with no code (its share could never come back)',
  $q$INSERT INTO public.payments (id, tenant_id, payment_number, customer_id, payment_date, effective_date, effective_date_method, amount, payment_method, channel, source_system, check_number,
                                suspense_receipt_id, suspense_resolution_reason, suspense_resolved_by, created_at, status, status_recorded_at, reversed_at, reversed_by, reversed_reason)
     VALUES (pg_temp.n('e7'), pg_temp.t1(), 'P24-25e7', :c1, DATE '2026-04-02', DATE '2026-04-02', 'lockbox_receipt', 100, 'check', 'mail', 'internal', 'CHK-25b7',
             pg_temp.n('b7'), 'identified', pg_temp.op(), '2026-04-03 12:00+00', 'reversed', '2026-04-04 12:00+00', '2026-04-04 12:00+00', pg_temp.op(), 'load')$q$,
  '23514', 'born reversed with no return code');
-- (the same insert with return_code = 'R01' is admitted: O7b with pg_temp.admits, on a receipt of its own)
```

```python
    ("M145", "a load's payment of a receipt may be born reversed with no code", "O7",
     rep("    IF NEW.suspense_receipt_id IS NOT NULL AND NEW.status = 'reversed' AND NEW.return_code IS NULL THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('payment %s is born reversed with no return code",
         "    IF false THEN\n        RAISE EXCEPTION USING\n            MESSAGE = format('payment %s is born reversed with no return code")),
```

If the author would rather state it than refuse it, it is a limit for the design's section 6 and a line in the load contract; I would refuse it, since the check is cheap and the loss is silent.

## N — notes

- **N1 (executed).** The writable-CTE shapes (FB, FB2) are refused by -23's status-cause check (23503), not by r10's rule as the plan says. The outcome the plan claims holds; the attribution in the plan is off by one guard.
- **N2 (read).** The reader calls `suspense_misposted_share_as_of` for every payment of the tenant that names a receipt before `s.share > 0` filters; each call is a recursive walk with sequential scans off. For a reporting read at a tenant's scale (hundreds to a few thousand receipt payments a year) this is fine; if it ever matters, the join can first keep payments with any row under their posting entry.
- **N3 (read).** A payment of which only part was misposted, the rest rightly the customer's, has no way back to the receipt while it stays posted: the reader lists the part (S8f), and it returns only once the payment ends, which needs the rest reversed too (the posting entry wholly undone) and re-posted. That is coherent and conserving, and it is the flow the plan describes ("it returns once it ends"); it belongs in the design's section 6 as a stated limit, since an operator will meet it.
- **N4 (executed).** The `since` date is per day: an undo and a re-reversal on one day leave the run unbroken (FC1). CI-056 needs no finer grain; the comment could say "by day".
- **N5 (read).** M119 and M124 dropped for the reasons the plan gives; both hold (the status row's filter is gone; `payments_return_code_check` admits a code only on an ended payment, so the code check's "with the status move" mutation M123 is the one that matters, and it is caught at P16b).
- **N6 (executed).** The races reproduce (24). The nsf ending adds no new writer path: the return of a bounced payment goes through the same disposition trigger and the same receipt lock as a reversed one's.
- **N7 (read).** Known limits L1–L6: none blocking, as before.

## Answers to the three questions put to me

1. **L7 (both parts as plain reversals, ended with the bank's code).** Acceptable, and I would record it as L7 with its contract: *a bank's take-back is an nsf row; `reversed` with a return code means the bank took the whole payment.* The database cannot tell two plain reversals apart, and the only stricter rule — a receipt's payment `reversed` never takes a code — would undo r2 (P12a, the ACH return recorded as reversed R10) and sit oddly beside -23's `payments_return_code_check`, which admits a code on `reversed`. The clerk who records the bank's part as a plain reversal has made the same kind of entry as one who records a misposting as nsf; r10's rule closes the case where the database *can* tell (an nsf row beside other reversals), and the reader's comment already states the other side (a bank's take-back entered as a plain reversal with no code is listed).
2. **Inserts.** `tally_app` cannot: -23's `enforce_cash_birth` lets a non-superuser bear a payment only `pending`, with no cause and no status time (read in `tu.sql`; the superuser exemption executed as the owner, FG1, FG2). So it matters only for a history load, and there for exactly one shape: born `reversed` with no code and no rows (S2). Born with a code, or born `nsf`, is coherent (the bank took all, the receipt is spent); born `reversed` with no code says "its share comes back" and the share is 0 for good, because -23 refuses a posting row for an ended payment (FG5). The receipt is used up with the money nowhere. A load that bears the payment pending and moves it through its rows (the battery's own R25 and Rb7) is right, and the refusal in S2 makes that the only way.
3. **A return code with no recorded time.** Acceptable, stated as it is. The window exists only when the code is written after the end (P12a's shape, the common one, writes both in one UPDATE and has no window). In it, a read at an instant between the end and the code lists nothing for a payment that was then listed, and an S4c-style sum at that instant is short by its amount; after the code, the money is the bank's for good, so no present figure is wrong. The cure would be a recorded time for the code, which is a -23 column, not -24's; the comment's statement is the right weight.

## Answers to the brief's questions

1. **Round 9 and earlier.** All closed as the plan states them (executed); rounds 1–8 still closed. The patch implements the design and the rulings (CI-053, CI-056, Ryan's 11-07 refund rule within L5 and L6), with S2 the one shape, superuser-only, where CI-053's "never dropped" is not yet held.
2. **Paths around a rule.** None found for any application role: the brief's list is held by the rounds 1–9 checks that re-ran here, the races (24), FB/FB2 (writable CTE), FE (multi-row UPDATE), FD (the tree after an nsf ending). For a superuser history load: S2.
3. **-23 and -27.** -24 reads -23's tree by type, sign and link alone and calls none of -23's helpers; r10 adds a read-only walk at coordinates and widens the recorded-order check to a bounce's recorded time (the time -23 stamps). Nothing -23 or -27 reads changes. The `payments` trigger order is unchanged; the new code check runs after -23's status check, which has already required the tree whole.
4. **Concurrency.** Lock order unchanged (payment, then receipt, as since r2); the code check reads the share under the receipt lock after the status check has fixed the tree; the reader takes none. The races reproduce.
5. **Invariants.** Clean on the clone after battery, races and each reverted change; the five pins match. No claim narrower than its check found.
6. **Tests.** Battery 309, races 24, M142/M131/M125 caught by hand at their named checks. S4c's list is the formula's, not a principled sample (S1); with the right bank term the check covers every receipt of the tenant, and it passes. Missing: the born-reversed load (S2's O7, M145).
7. **L1–L6.** None blocking. Candidates for the list: L7 as above (question 1), and N3's partial-misposting flow.
