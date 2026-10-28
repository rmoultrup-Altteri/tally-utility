# Opus review: v5.4.2-23 r5

**Date:** 2026-10-28. **Reviewer:** Opus. **Verdict: not yet.**

## Setup

- **Frozen files.** All six md5s match the brief (`md5 -r`, executed).
- **Clone.** I made `rv23opus` from `tally` (TEMPLATE) and revoked TEMP from PUBLIC, tally_app and tally_core right after. Both roles read `f|f` (executed).
- **Strict apply, twice.** The frozen r5 patch applied cleanly with `search_path=''` and `check_function_bodies=on`. The second run skipped on its marker (executed).
- **Battery.** The frozen battery passes 293/293 and rolls back (executed).
- **Probes.** The probes need instants of their own, because the split reads rows by recorded instant and one transaction is one instant. So I committed the frozen battery's fixtures into my clone: the battery with its ROLLBACK replaced by COMMIT. Each probe step then ran as its own autocommit transaction, as tally_app under `app.user_id` (customer C5, tenant 23a1), unless the probe says otherwise. P3 uses two sessions. The probe files are in my scratchpad, not in the repo.
- **Races.** I dropped the clone, re-cloned it (TEMP revoked again, `f|f`) and re-applied the patch strictly. `cash-23-frozen-r5.sh rv23opus` then gave 33 PASS, no FAIL, rc 0 (CR1–CR22, executed).
- **Not run.** `ci.sh` and `mutations-23.py`. I read the mutation list N171–N191.
- **Cleanup.** The clone is dropped and my files are removed from the container.

Each claim is marked **executed** (run on the clone) or **predicted** (read from the code).

---

## Round-4 findings

| r4 item | Status |
|---|---|
| Opus B1, Fable B1, Codex S1: the payment and its credit read a take-back differently | **Partly closed.** W2–W4 and W12 hold (executed, battery). P1 and P2 of r4 read correctly when each act is its own transaction. **Two paths remain**, both ending in the r4 P2 state (a payment shows money its cap will not give, and its credit shows a debt): B1, a deficit fixed on the credit at the take-back's instant; B2, a take-back whose transaction began before a draw it is read ahead of. |
| Opus B2, Fable S1, Codex B1: a refund that came back is paid out again under its own row | **Closed** (W1 and W1c executed, battery; CR21 executed, races). The guard covers both signs, under the refund's lock. |
| Fable B2, Codex B2: a give-back onto an escheated overpayment credit | **Closed** (W5a executed). **Too broad:** it also refuses a give-back that the split assigns to the payment (S2). |
| Fable B3: an arrival row at REPEATABLE READ | **Closed** (CR20 and CR20b executed). The one pin at the top covers arrival rows, donations and reversals (predicted, read). |
| Codex B3: a reissue after the payment also bounced | **Closed** (W6–W7b executed). |
| Codex B4: a future status time hides the commit check | **Closed for `status_recorded_at`** at a move, on a later correction and at birth (W10–W10e executed). **The same class is open for `created_at`** (S1). |
| Opus S1: a reissue dated before its refund came back | **Closed** (W8 and W8a executed). |
| Fable S2 (R15 text), Fable S3 ("either order"), Codex S3 (pending reader), Fable N1 (history-load order), Opus N1 (R16) | **Closed** (comments, read). |
| Codex S2: tests; N170's label | **Closed.** W9 is the behavioural case, N190 is its mutation, and N170 is relabelled (read). |

**Rulings.**
- **K-10's refund cap** (payment less refunds less reversals) is applied exactly by the cap on the two together. In P1 it admits 30 = 60 − 20 − 10, and in P2 it admits 10 = 60 − 20 − 30 (executed). I found no case where it is stricter than K-10.
- **Kyle's example through the credit** (V1, V2): unchanged (executed, battery).
- **Ryan's reissue decision, as refined for B4:** applied, and consistent with K-10 (W6 and W7 executed). See N3 for how it depends on B1.

---

## Blocking

### B1. A shortfall is fixed on the credit at the take-back's instant. When the payment later gets its own money back, the payment shows money that only the cap on the two together refuses (executed, P1 and P2)

`overpayment_split` assigns what neither side held (`v_short`) to the credit, up to its amount, at the take-back's instant, and that assignment never changes. If money later comes back to the payment's own part, for example its refund's check returns, the payment's position and its own cap both count that money as free. The credit keeps the deficit, and only the cap on the two together sees that the money is already gone.

**P1 (executed).**

| Step | Payment | Credit |
|---|---|---|
| Payment 60 posted. Overpayment credit K 20. K refunds 20 (posted). The payment refunds 40 (posted). | 0 | 0 |
| +10 taken back under the payment's entry. Split: absorbed 10, a shortfall on K. | 0 | −10 |
| The payment's refund of 40 comes back (nsf). | **40** | −10 |

- A refund of the payment's 40 is refused: "payment … and its overpayment credit … would come to 70.00, more than the payment's 60.00". A refund of 31 is refused the same way. A refund of 30 is admitted.
- The payment then reads **remaining 10** and K reads **−10**. A refund of 1 from the payment is refused (61 > 60).
- The customer's ledger nets 0 over the probe, so the two positions add up to the ledger. Each one is still wrong.

**P2 (executed).** The same setup, but 30 is taken back.
- K absorbs 20 (its amount) and the payment 10, so K reads −20 and the payment −10.
- The payment's refund of 40 comes back: the payment reads **30** and K reads **−20**.
- 11 is refused and 10 is admitted. The payment then reads **20** that it can never give.

**Why it matters.**
- The end state is permanent. The payment shows unapplied cash that can never be applied or refunded, and the credit shows a receivable of the same size.
- K cannot be voided (its refund is posted) and cannot be escheated (`v_left <> 0`).
- This is r4 P2's end state, and the brief's own test ("does each position's remainder equal what its cap admits") fails.
- The cap on the two together keeps the money right. The readers do not.
- It also matters for the reissue: its amount is read from the credit's position (N3).

**Fix (direction).**
- Keep "what the credit still held at the take-back's instant" for the part either side held. That is what r4 P2 and W3 need.
- Do not fix the **shortfall** on a side when it is recorded. Read it at the position's instant instead: net it first against whatever either side then holds, and only what neither holds falls on the credit up to its amount, then on the payment (K-10's debt).
- With that rule, P1 ends payment 30 / credit 0 after the return, P2 ends 10 / 0, and V1/V2 are unchanged, because at a full bounce neither side holds anything (predicted).
- Each side's position should then equal the lesser of its own cap and the cap on the two together.
- **Tests:** P1 and P2 as battery checks. Add an invariant over every payment with a live credit: each side's remaining equals the largest draw admitted on it, and the two add up to what the cap on the two together admits. P1 shows the second half holds and the first does not.

### B2. A take-back whose transaction began before a draw is read as if it came before that draw. r4 P2 comes back with two ordinary sessions (executed, P3)

The split reads each row at its `created_at`, and for tally_app that is its transaction's start (`now()`). r4 S1 added the leg "no draw recorded before a row under the arrival entry" (check_cash_source). Nothing checks the other direction: a row under the payment's posting entry recorded before a draw already counted on the payment or its credit. In r4 the order did not change any reading. In r5 the split is order-dependent (`cash_drawn_at` at the row's instant), so it does.

**P3 (two sessions, tally_app, executed).**

| Step | Payment | Credit |
|---|---|---|
| Setup: payment 60 posted, overpayment credit K 20. | 40 | 20 |
| Session A: `BEGIN` (now() = 16:54:36.70), then sleeps. | | |
| Session B: refunds K's 20 and posts it, commits at 16:54:38.27. | | |
| Session A: +10 under the payment's entry at 16:54:40.71, admitted (stamped 16:54:36.70). Commits. | | |

- **Split:** K absorbed 10, because at 36.70 its refund "did not exist yet".
- **After:** the payment reads **40** and K reads **−10**. The refund of 40 is refused (70 > 60) and a refund of 30 is admitted. The payment then reads **10** that it can never give, and K reads −10.

This is exactly r4 P2, which the As-built note says r5 fixes. R17's sentence "Post each act in a transaction of its own and the split follows the order they happened in" is not true: the order the split follows is the order the transactions **began**.

The same shape applies to a superuser history row under the payment's entry with a chosen `created_at` before a draw: the tree's recorded-order leg checks only rows of the tree (predicted).

**Fix.** In `enforce_ledger_reversal`'s payment-root branch, both signs, after the payment's lock: refuse a row recorded before any draw already counted on the payment or its live overpayment credit, or before any leaving move on them.
- Use `cash_source_draws` for both, plus the moves check_cash_source already reads.
- Return 40001 for a row stamped at its transaction's start and 23514 for a chosen time, as check_cash_source does.
- Every draw on the credit already takes the payment's lock (r5), so the payment's lock is enough to see them.
- Correct R17.
- **Tests:** P3 as a race (CR23); a battery case for the chosen-time leg; a mutation per leg.

---

## Should fix

### S1. A superuser's `created_at` in the future is still kept on payments, credits, applications and escheatment events (executed, P4)

r5 refuses a future `status_recorded_at` for every role, and the ledger refuses a future `created_at` (-22 r5). `stamp_log_created_at` keeps any superuser value on the other four tables.

**P4 (executed).** As the owner:
1. Payment 60 posted, overpayment credit K 20.
2. A refund of K for 5 is inserted with `created_at = now() + 1 day`: **accepted**.

Then:
- K's position now reads **remaining 20**: the refund is not counted, but the cap counts it.
- tally_app's refund of 5 from K is refused with **40001**, "a transaction that began earlier is writing later; retry it". No retry can succeed until tomorrow. This is the reason -22 r5 gave for the ledger.

I found no way to pass the commit-time check this way: a future row only raises `remaining`, which is stricter (predicted). It is still Codex r4 B4's class, and the rule "every row is recorded at a time already reached" should cover it. **Fix:** refuse a non-finite or future `created_at` in `stamp_log_created_at` for these tables (or in `enforce_cash_birth` and the draw triggers). Test it, with a mutation.

### S2. The escheated give-back guard keys on the credit's status, not on where the split puts the money (executed, P5)

**P5 (executed).**
1. Payment 100, overpayment credit K 50. K remits 50 and is escheated.
2. +10 is taken back under the payment. Split: absorbed **0**, because K held nothing, so the payment's own part takes it. The payment reads 40.
3. The bank says the 10 cleared after all, so a −10 is written under the +10: **refused**, "nothing comes back to an escheated credit".

By the split, all 10 goes to the payment, not to K. Telling the operator to "post a new payment" here records a payment for money that never arrived twice.

**Fix:** refuse only when the give-back would reach the credit, that is when K has absorbed anything (`sum(absorbed) > 0` over its split). Better still, admit the part beyond what K absorbed. Guard the act, not the label. Test P5 as a control beside W5a.

### S3. Tests

No battery check, race or mutation reaches B1, B2, S1 or S2. W3 runs inside the battery's single transaction, so it shows the one-instant reading, not the recorded order that P3 breaks.

---

## Notes

- **N1 (predicted). Lock order: I found no cycle.**
  - Payment before credit: a credit draw, a credit's void, a give-back under a payment, and a reissue's read (the payment if overpayment, then the from-credit).
  - Tree, then refund: a row under a refund's posting row.
  - A refund's move: its own row, its advisory lock, then its source.
  - Posting a refund in the same transaction as its insert takes credit, then refund. A return takes refund, then credit. Both cannot hold for one refund: the return cannot see the refund before the insert commits.
  - Removing the bounce's credit lock (N145) is sound: every credit draw now waits on the payment's lock (CR18 and CR22 executed).
  - An escheat **move** takes only the credit's lock while it reads the split. A concurrent take-back can only add a K-10 deficit, which is allowed.
- **N2 (predicted). Later moves.** A refund's leaving move is stamped with its own transaction's start, so it can be read as earlier than a take-back already committed and re-split it. Every case I worked moves the split toward "held" and stays consistent: a leaving move only frees money. The stale-instant problem is the take-back itself (B2).
- **N3 (predicted). The reissue's amount is read through the split.** `least(refund, credit's remaining)` uses the credit's position at the instant. Under B1 the shortfall's side changes what the reissue carries (the total is the same), and a reissue is a permanent row. Settle B1 before relying on W6's amounts.
- **N4 (predicted). One instant.** The split re-reads with the draw under check included at the same instant, so within one transaction the per-side caps admit whatever the pool leaves: N181 is caught at W3a. The cap on the two together is load-bearing there, and it holds K-10 for every reading I tried. R17 says so. Its last sentence is wrong (B2).
- **N5 (predicted). The refund-tree guard.** No legitimate act is refused: a mistaken nsf is answered with a new refund, which the cap reads.
- **N6 (predicted). Cost.** `overpayment_split` calls `cash_drawn_at` twice per tree row, and the positions call it once per credit. That is fine for realistic trees. I did not time it.
- **N7.** Residuals R1–R16 are not blocking. R17 needs its last sentence corrected (B2).
- **N8.** Mutations N171–N191 (read, not run): each new leg has one, at a named check. None would reach B1, B2, S1 or S2.

## Probe record (executed)

- **P1:** stuck at payment 10 / credit −10, the ledger delta 0. The 40 and 31 refunds were refused by the cap on the two together.
- **P2:** stuck at 20 / −20.
- **P3:** the take-back stamped 16:54:36.70 and inserted at 16:54:40.71, after B's refund (16:54:38.27). Absorbed 10. The 40 refund was refused, then stuck at 10 / −10.
- **P4:** the future refund was accepted. The credit reads 20, and tally_app gets 40001.
- **P5:** the give-back was refused with absorbed 0.
- **Battery:** 293/293.
- **Races:** 33 PASS.
