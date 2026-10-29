# Opus review: v5.4.2-23 r6

**Date:** 2026-10-29. **Reviewer:** Opus. **Verdict: not yet.**

## Setup

- **Frozen files.** All six md5s match the brief (`md5 -r`, executed). The live patch and battery are identical to the frozen copies (executed).
- **Clone.** `rv23opus` from `tally` (TEMPLATE), TEMP revoked from PUBLIC, tally_app and tally_core right after; both read `f|f` (executed). Rebuilt once the same way after the race script's committed rows collided with the battery's ids.
- **Strict apply, twice.** Clean; the second run skipped on its marker (executed).
- **Battery.** 344 PASS, no FAIL, rolled back (executed). The brief says 343; the plan's As-built says 344. 344 `NOTICE: PASS` lines, no duplicates.
- **Races.** `cash-23-frozen-r6.sh rv23opus`: 38 PASS, rc 0 (CR1–CR24, executed).
- **Probes.** Two kinds:
  - History loads: the frozen battery with my probes appended before its ROLLBACK, as the owner at chosen past times, with its helpers (`hpay`, `hcredit`, `hrow`, `hback`, `agree`). Each read and draw attempt ran as tally_app under `app.user_id`.
  - App path: the battery's fixtures committed into the clone, then each act its own committed transaction as tally_app (E, D).
  - The probe files are in my scratchpad, not the repo.
- **Not run.** `ci.sh` and `mutations-23.py`, per the brief. I read N192–N211.
- **Cleanup.** The clone is dropped and my files are removed from the container (executed).
- **Container note.** `docker ps` shows 7 `crystaldba/postgres-mcp` containers running. I did not touch them.

Each claim is marked **executed** (run on the clone) or **predicted** (read from the code).

---

## Round-5 findings

| r5 finding | Status |
|---|---|
| **Opus B1.** A shortfall was fixed on the credit at the take-back. | **Closed between the payment and its credits** (Y1, Y1a, Y2 executed). **Not closed inside the family:** a deficit on the overpayment credit sits beside money on its reissue (B2 below). The cover also opened B1 below. |
| **Opus B2, Fable B1.** A take-back was not ordered against the draws. | **Closed** (Y5, Y5a, CR23, CR23a–c executed). `check_cash_order` runs on the payment and on every live family credit, under the payment's lock, and every family draw takes that lock first. |
| **Opus S1.** A future `created_at`. | **Closed** for payments, credits, applications and remittances (Y9–Y9d executed). |
| **Opus S2, Fable S2.** The escheated give-back guard was too broad. | **Closed for the r5 shapes** (Y8, Y8c executed). After B1 it refuses a give-back of the payment's own money (Ec below). |
| **Opus S3, Fable S3.** The agree() helper. | **Closed, with a gap.** agree() skips an escheated credit, so it does not see B1's state (E5 executed: agree() passes there). |
| **Fable S1.** The return, move and reissue deadlock. | **Closed** (CR24 executed). A different cycle on the reissue's void is open (S1 below). |
| **Fable N1, N3, N4.** | **Closed** in comments: R17, R18 and R19 (read). |
| **Codex B1.** A reissue before the bounce. | **Closed** (Y7–Y7h, Y7m executed). The reissue takes the payment's lock, is in the pool, and holds up the bounce and the move to nsf. |
| **Codex B2.** A give-back to the credit left a surplus beside a deficit. | **Closed between the sides** (Y3 executed). Open inside the family (B2). |
| **Codex B3.** Tied rows were split in uuid order. | **Closed** (Y4–Y4d executed): rows are ordered by `created_at`, then depth, then id. |
| **Codex B4.** A status-time correction rewrote the split. | **Closed** (Y6–Y6d executed). A same-status change of `status_recorded_at` or `status_cause_id` is refused for every role. `cash_lineage_recorded` bounds a history move. |
| **Codex S1.** Stale comments. | **Not closed** (read). These still say the old thing: the reissue column comment (patch line 1464, "Its amount is the refund's"); `enforce_cash_draw`'s inline comment (3278) and COMMENT (3345, "carries exactly"); and `enforce_ledger_reversal`'s COMMENT (919, "held as a credit"). The r6 plan dropped the item. |
| **Codex S2.** Coverage. | **Partly closed.** Y and CR23–24 cover the r5 compositions. The runner's APPLY branch still matches `phrase in a.stderr` (line 614, read). |

**Rulings.**
- **K-10.** The cap on the two together, now including the reissues by their draws, never let out more than K-10 in any shape I ran (E, F and V executed). Whenever a per-side cap admitted too much, the pool refused the excess.
- **Ryan's rulings on status, the reissue and escheat** are applied, except where B1 breaks "nothing comes back to an escheated credit".

---

## Blocking

### B1. An escheat admitted on the cover leaves money on the escheated credit once the payment's deficit goes away (executed, app path and history load)

**What happens.**
- The escheat check (`enforce_customer_credit_immutable`, around patch line 2409) reads the credit's position with the cover.
- A credit that holds money on its own side while covering the payment's deficit therefore reads 0, and it may be escheated.
- When the payment's deficit later goes away, for example when the payment's own refund check comes back, the cover lifts. The escheated credit then reads its money again.
- Nothing refuses that return. `enforce_escheated_credit_settled` fires only for a refund of a credit.

**E (tally_app, each act its own transaction, executed).**

| Step | Payment | Credit |
|---|---|---|
| Payment 60 posted; overpayment credit 20; the payment's own 40 refunded (posted) | | |
| The bank takes back 30, then gives back 20 (the credit is restored first) | 0 | 10 (its own side holds 20 and covers the payment's −10) |
| 10 remitted to the state; the credit moves to escheated (reads 0) | 0 | 0 |
| The payment's refund check of 40 comes back (nsf) | **30** | **10, escheated** |

- A refund of 40 from the payment is refused, and so is 30.01. A refund of 30 is admitted. The escheated credit can draw nothing.
- **The customer's money.** Paid 60; 30 taken back and 20 given back, so 50 arrived; 40 sent and returned; 10 remitted. The utility holds 40 of the customer's money and can refund only 30. The other 10 sits on a credit already sent to the state, for good.
- agree() passes on this state (E5), because it skips escheated credits.
- The history-load run gives the same figures (E1–E4).

**Ec (executed).** Instead of the refund coming back, the bank gives back the other 10 of its take-back.
- By the shares that is the payment's own money.
- The S2 guard refuses it (23001, "10.00 of it would come back to credit … escheated"), because the payment's money lifts the cover.
- So once such an escheat exists, the bank's correction cannot be recorded.

**Why it matters.**
- This is "nothing comes back to an escheated credit" (Ryan, 2026-10-21), broken by r6's cover.
- Under r5 the escheat was refused: the credit's own remainder of 10 was not 0.
- It is the escheat case itself: an uncashed refund check is the usual way money ends up unclaimed.

**Fix (direction).**
- The escheat check should require the credit's own side, read without the cover (`p_cover false`), to hold nothing positive, as well as its covered position to be 0.
- A credit covering the payment's deficit then stays active and reads 0. It becomes drawable again when the deficit goes.
- **Tests:** E as a battery check. agree() should also check every escheated family credit for "remaining ≤ 0, and stays so".

### B2. Inside the family a deficit on the overpayment credit sits beside money on its reissue (executed, history load)

**What happens.**
- The cover nets only the payment against the family's total. It never nets one credit against another.
- What no side held at a take-back falls on the overpayment credit (i = 1).
- If a reissue later gets money back, the overpayment credit keeps its deficit, and the reissue shows money only the pool refuses.

**F (executed).** Steps:
1. Payment 100; overpayment credit K 100.
2. K refunds 30. The check comes back, and reissue K2 of 30 is made.
3. K refunds its other 70, and K2 refunds its 30, both posted. Nothing is held anywhere.
4. 10 is taken back under the payment: K reads −10, K2 0, the payment 0.
5. K2's refund check of 30 comes back.

Result:
- **K reads −10, K2 reads 30**, the payment 0.
- A refund of 30 from K2 is refused by the pool (110 > 100), 20.01 is refused, and 20 is admitted.
- agree() fails: "credit …b6 reads 30.00, and a refund of 30.00 got 23514".
- After the 20, K2 reads 10 that it can never give and K reads −10. This is r4 P2's end state, inside the family.

**Fix (direction).** The cover should net across every member: a member in deficit is covered by any member, or the payment, that holds money. Add F to the Y checks.

### B3. A reissue that took a share and is then voided leaves its share in the payment's cap but not in the positions (executed, history load)

**What happens.**
- `overpayment_shares` keeps a voided reissue's share. `overpayment_split`, which the payment's cap reads, counts that share as the family's.
- `overpayment_absorbed_as_of` drops voided members. The payment's position then carries the share itself.
- The void also gives the predecessor credit back the reissue's whole amount (`carried` counts only reissues that are not voided), not what the reissue still held.

**V (executed).** Steps:
1. Payment 100; overpayment credit K 50.
2. K refunds 20 (posted). K's refund of 30 comes back, and reissue K2 of 30 is made.
3. 10 is taken back: K held 0, so K2 absorbs 10. Positions: payment 50, K 0, K2 20; agree() passes (V1a).
4. K2 is voided.

Result:
- **The payment reads 40** and K reads 30.
- A refund of 50 from the payment is admitted (50.01 refused), so the payment's cap is 50 while its position is 40.
- K admits 30. The pool holds the total at 70, so no money escapes.
- agree() fails: "payment reads 40.00, and a refund of 40.01 got admitted".

**Severity.** This is the least severe of the three. It is an attribution error, and it heals once the payment draws its 50. I list it as blocking because it breaks the invariant r6 rests on: each position equals what its cap admits. It answers the brief's question "is there any reading in which the shares and the pool cap disagree about the money?" with yes.

**Fix (direction).**
- On a reissue's void, its share passes to the credit it came from.
- Alternatively, refuse the void while the reissue holds a share.
- Either way, the cap and the positions should read voided members alike.

---

## Should fix

### S1. A lock-order cycle between a reissue's void and a give-back under the payment (executed, race D)

**The two lock orders.**
- A reissue's void takes the credit its refund came from (K), then itself (K2). It takes no payment lock (As-built point 4).
- A give-back under the payment takes the payment, then every live family credit in **uuid order** (patch around line 826).
- When K2's id sorts before K's, the give-back holds K2 and waits on K, while the void holds K and waits on K2.

**Race D (tally_app, executed).**
1. Setup, committed: payment 100, credit K 100, K's refund of 30 back, reissue K2 (id …9776 < K's …9777), 10 taken back.
2. A takes the void's first lock, on K (the same key the void takes first), and sleeps. Then A voids K2.
3. B writes the give-back of −10 in between.

Result: **B: deadlock detected (40P01).** A's void commits.

- The window without the emulated hold is the gap between the void's two locks. It is small, but nothing closes it.
- The header's own rule says "a source is locked before what draws on it". The give-back's uuid order breaks that rule.

**Fix.** Either:
- the void of a reissue in a payment's family takes the payment's lock first (the first build did this, and it serialises the void with every give-back); or
- the give-back locks the family in lineage order: the overpayment credit, then each reissue by recorded order.

Add D as a race.

### S2. Stale comments (Codex r5 S1, not closed)
See the table: patch lines 1464, 3278, 3345 and 919.

### S3. Tests
- agree() should check escheated family credits (B1).
- Add E, Ec, F, V and D.
- None of N192–N211 reaches B1–B3 or S1 (read).

---

## Notes

- **N1 (executed). The take-back's recorded-order legs.** I found nothing legitimate refused.
  - A take-back begun before an unrelated draw on the credit gets 40001, and the retry then meets the bounce's hold-up if the draw holds the payment.
  - A same-transaction draw is not "later" (equal instants).
  - Every family draw takes the payment's lock, including draws on reissues and a credit's refund that leaves, so the take-back's check under that lock sees them.
- **N2 (predicted). `cash_lineage_recorded` is complete for the moves it guards:** the payment, its live credit's family, their arrival trees, draws and leaving moves. For a refund, its own posting tree plus its source's lineage. A history load written in order (Y6b, Y6d, W10d) passes. It refuses only a move chosen before a row already recorded, which is its purpose.
- **N3 (predicted). One instant (R17).** The pool cap still holds every reading in one transaction (W12 and Y0c executed). R17's corrected text is right.
- **N4 (predicted). The cover never lets a draw use the other side's money.** Each per-side cap reads its own side as recorded, and the pool holds the total (E4, F3 and V3 executed). The defects are in the readers (B1–B3), not the money.
- **N5 (executed).** A voided reissue's own position reads its amount (V2: K2 voided, 30). That was already true in r5 and is harmless, but a reader may want 0 for a voided credit.
- **N6.** Residuals R1–R21 are not blocking. R20 ("an attribution, not a ruling") is right about the money, but B3 shows the attribution must still be the same in the cap and the positions.
- **N7.** The brief's battery count (343) is one short of what the battery prints (344) and what the As-built note says.

## Probe record (executed)

- **E (app path):** after the return, payment 30 and credit escheated 10. Refunds of 40 and 30.01 refused (23514), 30 admitted. At the escheat instant both read 0.
- **E (history), Ec:** the same figures. The give-back of the payment's 10 is refused (23001).
- **F:** K −10, K2 30. 30 and 20.01 refused by the pool, 20 admitted. agree() FAIL.
- **V:** before the void, 50 / 0 / 20 and agree() passes. After, 40 / 30. 50 admitted from the payment, 50.01 refused. agree() FAIL.
- **D:** 40P01 on the give-back; the void commits.
- **Battery** 344/344. **Races** 38 PASS.
