# Opus review: v5.4.2-23 r4

**Date:** 2026-10-21. **Reviewer:** Opus. **Verdict: not yet.**

## Setup

- **Frozen files.** All six md5s match the brief (`md5 -r`).
- **Clone.** I made `rv23opus` from `tally` (TEMPLATE). Right after, I revoked TEMP from PUBLIC, tally_app and tally_core, and checked that neither role has TEMP (`f|f`).
- **Strict apply, twice.** The frozen r4 patch applied cleanly with `search_path=''` and `check_function_bodies=on`. The second run skipped on its marker.
- **Battery.** The frozen battery passes 252/252 on the clone (executed).
- **Races.** `cash-23.sh rv23opus`: 29 PASS, no FAIL, rc 0 (CR1–CR19), executed.
- **Probes.** Each probe is the frozen battery with its final `ROLLBACK` removed, then a few helpers, then my statements, then `ROLLBACK`. They reuse the battery's fixtures: customer C4, bills I9 and I10. Unless a probe says otherwise, it runs as tally_app under `app.user_id`. The probe files are in my scratchpad, not in the repo.
- **Not run.** I did not run `ci.sh` or `mutations-23.py`. I only read the mutation list.
- **Clone dropped** at the end, along with my files in the container.

Every claim is marked **executed** (run on the clone) or **predicted** (read from the code).

---

## Round-3 findings

These are the plan's merged items. Each one cites the reviewer who raised it.

| r3 item | Status |
|---|---|
| B1: a payment held as an overpayment credit that paid out can never bounce (Opus B3, Fable B1) | **Closed for the bounce** (V1–V3 and V16, executed; P7 below, executed: an escheated overpayment credit no longer blocks the bounce). **The model opens B1 below:** the payment's cap and its position disagree about the credit after a partial take-back. |
| B2: an escheated credit gets money back (Opus B1, Codex B1/B2) | **Partly closed.** The donation undo is refused (V5). Escheat waits for a pending refund (V6). A returned refund is forced into a reissue at commit (V7–V7i). All three executed. **Still open:** the returned refund's nsf row can itself be undone, and the money then goes out a second time while the reissue still holds it (B2 below, P3e). |
| B3: a donation's correction skips the cap (Codex B1) | **Closed** (V8, executed). The give-back leg goes through `check_cash_source(..., 'undo')`, so it is also refused on an ended credit (predicted, from code). |
| B4: a posting row for a payment or refund that has ended (Opus B2, Fable S1) | **Closed for the posting row** (V9 and V9b, executed; CR19). **The same class remains under a refund's posting row** (B2 below). |
| B5: a draw dated before the source's arrival entry (Codex B3) | **Closed for payments and credits** (V10, V10a and V10b, executed). The `-infinity`/entry-date pair in the cap is right: before the entry's date, `used` already includes the whole amount. **Open for a reissue** (S1 below). |
| S1: recorded order misses rows under the arrival entry (Opus S1) | **Closed** (V14, executed). For an overpayment credit, `v_entry` is the payment's posting entry, so the leg covers the rows the credit's cap reads (predicted). |
| S2: an old K-10 deficit vetoes a later draw (Codex S1) | **Closed** (V11, executed). |
| S3: give-back rows held up (Fable S2) | **Closed for payment, credit and donation trees** (V12, V15 and V15b, executed). **Not covered for refund trees** (B2). |
| S4: a credit never issued has no exit (Fable S3) | **Closed** (V13 and V13b, executed). |
| S5: tests | **Present** for every item above. None reaches B1 or B2 below. |

**Rulings.**
- **K-10 1 = A** is applied to the bounce through the credit, and Kyle's arithmetic holds:
  - In full: V1c, owes 60 (executed).
  - In part: V2c, owes 40 (executed).
- **K-10 2** (a pending refund blocks the bounce) is applied through the credit (V3, executed).
- **Ryan's status decision** still holds: no status names refunded or donated (predicted, from the diff).
- **Ryan's reissue ruling** is applied: a new credit in the same transaction, checked at commit, that is never voided back onto an escheated credit (V7a–V7f, executed). Two gaps remain (B2, S1).

---

## Blocking

### B1. After a partial take-back under the payment's posting entry, the payment's cap counts the overpayment credit at its full amount while its position counts it net (executed)

r4 says that what is taken back comes first out of what the credit holds. The positions apply this through `least(original_amount, taken back)`. The payment's cap does not apply it: `cash_source_draws('payment')` still counts the credit at `original_amount`, and `check_cash_source` adds the take-back on top. The credit's own cap also counts the take-back, because its `v_entry` is the payment's entry. So the take-back is counted twice against one payment.

**P1: the credit has not been spent.**
1. Payment P1 (60) is posted.
2. Overpayment credit K1 (20) is created from it.
3. +10 is taken back under P1's posting entry: **accepted**. The guard only checks whether the credit is applied or has a refund pending.

What the positions then say:
- P1: received 50, credited 10, remaining **40**.
- K1: issued 10, remaining **10**.
- Together that is 50, which matches the ledger.

What the caps admit:
- Applying 40 of P1 is **refused**: 23514, "would come to 70.00, more than its 60.00".
- Applying 30 of P1 is accepted, and so is applying 10 of K1.
- After that, applying 1 more of P1 is **refused**, and so is a refund of 1 (61 > 60).
- P1 still reads remaining **10.00**, and the ledger still shows the customer 10 in credit.

That 10 can never be applied or refunded. A guard refuses a legitimate act, and money is stranded.

**P2: the credit was refunded in full first.**
1. Payment P2 (60) is posted, credit K2 (20) is created from it, and K2's refund of 20 is posted.
2. Then +10 is taken back: **accepted**.

What the positions then say:
- P2: remaining **40**.
- K2: issued 10, refunded 20, remaining **−10**.

What the caps admit:
- Applying 35 of P2 is refused, and so is a refund of 40.
- A refund of 30 is accepted.
- After it, P2 reads remaining **10**, K2 reads **−10**, and the ledger nets to 0. The readers no longer agree on whose money the 10 is: P2 offers 10 that its cap will not give, and K2 says the customer owes 10.

**Why no single-line fix works.** P1 alone would point to counting the credit net in the payment's draws. P2 shows why that is wrong: K2 had already paid out its 20, so nothing of the take-back was left in it to absorb. The payment would then admit 40 more, and 60 would go out of the 50 that stands, which is exactly what Kyle's refund cap forbids.

**Fix.**
- The take-back comes first out of what the credit **still holds** at that point, that is its amount less its draws, not its `original_amount`. The rest comes out of the payment's own portion.
- The two positions, the payment's cap and the credit's cap must all read the same split. One helper should compute what the credit takes from the payment at a date, and all four should call it.
- In V1 and V2 (the full bounce) the answers stay the same: whatever the credit no longer holds falls on whichever of the two still has a draw.
- R15's text ("not taken back … while anything draws on it") no longer matches r4: a live overpayment credit is a draw, and the take-back is now admitted while it lives. Restate R15.
- **Tests:** P1 and P2 as battery checks. Add an invariant-style check: for a payment or credit, its position's remaining equals what its cap admits at a far date.

### B2. A row under a refund's posting entry is not guarded: a refund that came back can be paid out again (executed)

The bounce guard's source legs cover a payment's posting entry (`payment` or `deposit`), a credit's credit_issued entry and a donation. A refund's posting row (`refund`, under reference_type `payment`) has no leg, so nothing reads the refund's status for rows under it.

**P3a/b: a refund of a payment.**
1. P3 (50) is posted.
2. Refund R (30) is posted.
3. The −30 nsf row goes under R's posting row, and R moves to nsf. P3 reads remaining 50, which is right.
4. Then +30 is written under the nsf row ("re-sent"): **accepted**.

P3 still reads remaining 50. A second refund of 50 is then **accepted and posted**. The ledger nets +30: 80 has gone out against 50 received, and no position or cap sees the first 30.

**P3e: the same through an escheated credit after its reissue.**
1. K (100) is refunded 30 and escheated with 70.
2. The refund's check comes back, the refund moves to nsf, and reissue K′ (30) is created.
3. Then +30 is written under the refund's nsf row: **accepted**.

K′ still reads 30, and a refund of K′'s 30 is **accepted**. That is the same 30 paid out twice, and it is Ryan's ruling turned around.

r3's B2 was blocking for the same reason: the ledger moves money for a source that has ended.

**Fix.**
- Give `enforce_ledger_reversal` a refund leg. When the root is a refund's posting row (`transaction_type = 'refund'`, `reference_type = 'payment'`), take the refund's lock.
- A row giving money back to the account (the bounce of the refund) is admitted only while the refund is posted.
- A row paying it out again is refused once the refund is nsf or reversed. A re-sent refund is a new refund, as a re-presented check is a new payment.
- Say it in the "nothing back to an ended source" bullet and in R12.
- **Tests:** P3b and P3e.

---

## Should fix

### S1. A reissue can be dated before its refund existed and spent before the money came back (executed)

**P6.**
1. Refund R of K is dated 03-20.
2. K is escheated, and R comes back on 03-25.
3. Reissue K′ is inserted with `issued_date` 03-11: **accepted**.
4. K′ is applied to a bill on 03-12: **accepted**.

K's position as of 03-15 reads carried 30 and remaining 70, with no refund of K on that date yet. This is the arrival-date question (Codex B3) for the one source r4 adds.

**Why it gets through.** `check_cash_source('credit', K, …, 'reissue', issued_date)` checks the reissue only against K's own date. A refund's draw is read by status, not by date, so nothing ties the reissue to the return.

**Fix:** the reissue's `issued_date` must be on or after the return, that is, the date of the ledger row named in R's `status_cause_id`. Test it.

### S2. Tests

No battery check, race or mutation reaches B1, B2 or S1. Each one is reached by tally_app through ordinary single acts. The 170/170 mutation score says nothing about them.

---

## Notes

- **N1 (executed).** One live overpayment credit per payment refuses one legitimate shape. A payment of 100 has a credit of 20 that is refunded and posted. Holding 50 more of the payment as a credit is then refused (23505), and voiding the first credit is refused because it is drawn on.
  - The payment's own remainder can still be applied or refunded directly, so nothing is lost.
  - R16 should say this case.
  - If B1's fix introduces a per-date split helper, two credits would only need an order, by `created_at`.
- **N2 (predicted).** The commit-time check (`enforce_escheated_credit_settled`) is not reachable around, as far as I can find:
  - The refund moves to nsf while the credit is active, and the credit is escheated later in the same transaction: the escheat needs nothing left. So the returned money is either remitted with it or reissued first, and at commit the trigger sees escheated with 0 left.
  - A refund pending at the escheat is refused (V6).
  - A new refund of an escheated credit fails `'refund'`'s active check.
  - A reissue's void onto an escheated credit is refused (V7f).
  - The trigger is a deferred constraint trigger, ENABLE ALWAYS, so `session_replication_role` does not skip it. A superuser who disables triggers is outside the model, as before.
  - The one real gap is B2: the ledger row, not the status.
- **N3 (predicted). Lock order: I found no cycle for single acts.**
  - Payment before credit:
    - the bounce guard and the move to nsf take the payment, then each live credit;
    - an overpayment credit's void takes the payment, then the credit;
    - an overpayment credit's draw takes the credit only and reads the payment's tree without the payment's lock.
  - A reissue:
    - its void takes the from-credit, then itself;
    - its insert takes the from-credit;
    - a draw on it takes itself;
    - a refund of it leaving takes the refund, then the reissue.
  - Nothing takes a credit's lock and then its payment's, or a reissue's and then its from-credit's.
  - One asymmetry is safe: a give-back under the payment's entry (amount < 0) takes the payment's lock but not the credit's, even though it frees money for the overpayment credit. A concurrent draw on the credit either misses it (and is stricter) or sees it and meets the new recorded-order leg (40001).
- **N4 (executed). The arrival date is used everywhere I checked.**
  - `payment_position_as_of.received` and the credit's `issued` read the entry's own date.
  - An overpayment credit is dated on or after its payment's entry, because the payment's cap and its `-infinity` row refuse an earlier date.
  - The exception is the reissue (S1).
- **N5 (executed).** P7: an escheated overpayment credit (20 of a 60 payment) no longer holds up the bounce. Afterwards the credit reads given_up 20, remaining −20, and the payment reads 0. This is K-10's shape: remitted money that never arrived is owed.
- **N6.** Residuals: R1–R14 are not blocking. R12 (a refund's posting row undone while the refund stays posted) is the opposite direction of B2 and stays app discipline. B2 is not covered by any residual. R15 needs restating (B1). R16 is fine apart from N1.
- **N7.** The mutation list N141–N170 matches the new guards as far as I read it. I did not run it.
