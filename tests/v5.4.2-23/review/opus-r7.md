# Opus review: v5.4.2-23 r7

**Date:** 2026-11-01. **Reviewer:** Opus. **Verdict: not yet.**

r7 closes what round 6 found, in the shapes round 6 found it. Two blockers remain:
- **B1.** The escheat defect from round 6 (my r6 B1) is still reachable in a different order. Escheat the credit first. Then the bank's give-back restores the credit's share while that share covers the payment's deficit. r7 moved the escheat move's check to the credit's own side, but not the give-back guard's.
- **B2.** When the payment and a reissue both hold money beside a deficit, one of them reads less than its cap admits. Money is safe: the pool refuses every excess. The claim "each position equals what its cap admits" is false, though. No order of the cover fixes it, because the per-side caps ignore the cover.

## Setup

- **Frozen files.** All six md5s match the brief (executed).
- **Clone.** `rv23opus` from `tally` (TEMPLATE). TEMP revoked from PUBLIC, tally_app and tally_core right after; both read `f|f` (executed).
- **Strict apply, twice.** Clean; the second run skipped on its marker, "already applied" (executed).
- **Battery.** 372 PASS, no FAIL, rolled back; 51 s (executed). That matches the brief.
- **Races.** `cash-23-frozen-r7.sh rv23opus`: 39 PASS, rc 0 (CR1–CR25, executed).
- **Probes** (the probe files are in my scratchpad, not the repo):
  - History loads: the frozen battery with my probes appended before its ROLLBACK, as the owner at chosen past times, with its helpers. Reads and draws ran as tally_app under `app.user_id`.
  - One two-session race (D2) on the race script's committed tenant.
- **Not run.** `ci.sh` and `mutations-23.py`, per the brief. I read N212–N219 and the APPLY branch.
- **Cleanup.** The clone is dropped and my files are removed from the container (executed).
- **Container note.** `docker ps` shows 9 `crystaldba/postgres-mcp` containers running, 7 of them for 5 days. I did not touch them. `rv23fable` exists (Fable's clone).

Each claim is marked **executed** (run on the clone) or **predicted** (read from the code).

---

## Round-6 findings, item by item

| Round-6 finding | Status |
|---|---|
| **Fable B1, Opus B2, Codex B1.** The cover netted the payment against the family's total, never one credit against another. | **Closed** for every shape found (Z1–Z3, Z1a–Z3a executed). After the pass among the credits, they read all money or all deficit (predicted, from the loop: a deficit left uncovered means every other member is at or below 0). **New gap:** see B2. |
| **Opus B1.** An escheat admitted on the cover left money on the escheated credit. | **Partly closed.** The escheat move now reads the credit's own side (Z4a, Z4c executed), and agree() checks escheated credits. **Still reachable** by escheating first and giving back later: B1 below. |
| **Opus B3.** A voided reissue kept its share in the payment's cap but not in the positions. | **Closed** by refusing the void (Z5a, Z5b, Z5c executed). The void reads the shares as recorded, summed over every row. After the give-back, the reissue holds a zero share and nothing drawn, so the void returns exactly its amount (predicted). The accepted limit is R22. |
| **Codex B2.** The 1,000th reissue lost its payment. | **Closed** (Z6–Z6d executed). All four walks and the make read `reissue_line_bound()`: 999 passes, and the 1000th is refused at the make (23514). A planted 1000th raises 22000 in the root walk and in the family walk. Every guard is ENABLE ALWAYS, so a history load or a chosen time cannot get past it. Only a superuser's `DISABLE TRIGGER` can, and then every walk raises: it fails closed (predicted). |
| **Fable S1, Opus S1, Codex S1.** The reissue's void against a give-back. | **Closed** (CR25 executed). One other writer still takes a credit's lock without the payment's: S1 below. |
| **Opus S2, Codex S3.** Stale comments. | **Closed** (read): the column comment on `reissues_refund_id`, `enforce_cash_draw`'s inline comment and COMMENT, `enforce_ledger_reversal`'s COMMENT, R15 and R20. |
| **Opus S3, Fable S2, Codex S2.** Tests. | **Closed** for the round-6 shapes: E, Ec, F, V, D, P1 and P1c, and Codex 01, in Z, CR25 and N212–N219. Not one of them has the payment and a reissue both holding money beside a deficit (B2), or a give-back after an escheat (B1). |
| **Codex S2 (runner, walk-plan list, count).** | **Closed** (read). The APPLY branch now compares against the first error (line 640). `overpayment_shares` is in the walk-plan list. The counts are right: 372, 39, 218. Codex's point that the two traversal bounds were not tied together is closed by construction: there is one function. |
| **Fable N1** (a refund's return stamped at its start). | **Closed** as a note under R17 (read). |
| **Fable N7, N8.** | **Closed**: N212 covers the new leg, and R20 names the cover among the credits (read). |

**Rulings.**
- **K-10.** The pool refused every excess I tried (G5, G6 and H6 executed). After K2 drew its 30 in G, the payment's 40.01 was refused by the pool cap.
- **Kyle, 2026-10-30.** Applied within one payment: siblings first, then the payment. Across payments the netting is left to the core (R23); see N3.
- **Ryan, 2026-10-21 ("nothing comes back to an escheated credit").** Broken by B1.
- **Ryan's status and reissue decisions.** Applied. R22 is the accepted cost of refusing the void.

---

## Blocking

### B1. A give-back is admitted onto an escheated credit while the credit's restored money covers the payment's deficit (executed, history load)

**What happens.**
- r7 made the escheat move read the credit's own side, without the cover.
- The give-back guard in `enforce_ledger_reversal` (patch around line 864) still reads the covered position: `customer_credit_position_as_of(...).remaining > 0`.
- So escheat the credit while its own side is 0. Then let a take-back leave the payment in deficit, and let a give-back restore the credit's share.
- The credit's own side now holds money, but it reads 0 because that money covers the payment's deficit. The guard admits the give-back.
- When the payment's deficit goes away, the escheated credit reads its money again. This is the end state of my r6 B1, reached in the other order.

**H (executed).**

| Step | Payment | Credit K |
|---|---|---|
| Payment 100; overpayment credit K 50; the payment's own 50 refunded (posted) | | |
| 20 taken back; K held 50, so K absorbs it | 0 | 30 |
| K's 30 remitted to the state; K moved to escheated (admitted: own side 0) | 0 | 0 |
| 40 more taken back; nothing held, so K absorbs 30 (its amount) and the payment carries 10 | −10 | −30 |
| The bank gives back 40 under that take-back; the shares give it to K first. **Admitted.** K's own side is +10 and covers the payment's −10 | 0 | 0 |
| The payment's refund check of 50 comes back | **40** | **10, escheated** |

- A refund of 50 from the payment is refused, and so is 40.01. A refund of 40 is admitted. The escheated K can draw nothing (H6).
- agree() fails: "escheated credit 3421 reads 10.00" (H7).
- **The customer's money.** 80 arrived (100, less 60 taken back, plus 40 given back) and 30 went to the state. Once the refund check came back, the utility holds 50 of the customer's money and can refund only 40. The other 10 sits on a credit already remitted, for good.

**Fix (direction).**
- The give-back guard should read each escheated family credit's **own side** (shares as recorded, `p_cover false`), the same expression r7 added to the escheat move. It should refuse as far as that own side would be positive.
- The round-6 shapes still pass under that reading (predicted):
  - Y8: the give-back goes to the payment and K's own side stays 0.
  - Y8c and Z4d: the give-back only cancels a deficit on K.
- **Tests:** H as a battery check, and a mutation on the guard's reading.
- The same check belongs anywhere else an escheated credit's own side can rise. I found no other path: a refund of an escheated credit is refused, the void of a reissue needs its predecessor active, and an undo needs an active source (predicted). The retroactive stamping in Fable N1 (R17) shifts shares and is the one path I did not probe.

### B2. With the payment and a reissue both holding money beside a deficit, the reissue reads less than its cap admits (executed, history load)

**What happens.**
- The per-side caps in `check_cash_source` count each side's shares as recorded, without the cover. The pool holds the total.
- With one money holder beside a deficit, the pool binds that holder exactly, so its position equals its cap.
- With two money holders (the payment and a reissue), the pool only binds their sum, and each per-side cap admits its own side in full.
- The cover hands the deficit to one of them, which then reads less than it can draw:
  - r7 covers from the sibling, so the reissue under-reads.
  - r6's order covered from the payment, so the payment under-read. This shape existed in r6 too, unfound.

**G (executed).** Steps:
1. Payment 100; K 50.
2. K's refund of 30 comes back and is reissued as K2.
3. K refunds its other 20, K2 refunds its 30 and the payment refunds its 50, all posted. Nothing is held anywhere.
4. 10 is taken back, and it falls on K: K reads −10 (G1).
5. The payment's refund comes back: payment 40, K 0 (G2).
6. K2's refund comes back: **payment 50, K 0, K2 20** (G3).

Result:
- **K2 admits a refund of 30** (30.01 refused). The payment admits 50.
- agree() fails: "credit 3423 reads 20.00, and a refund of 20.01 got admitted" (G4).
- After K2's 30, the payment reads 40 and admits 40. The pool refuses 40.01 (G6).
- The money is held whole. Only the attribution, and what each line shows, is wrong.

**Why it is blocking.** On the same ground as r6's B3: the brief asks "does every position still equal what its cap admits?", and the header and `overpayment_absorbed_as_of`'s comment say it does. In G, staff would see a credit of 20 that pays out 30, and a payment of 50 that then drops to 40 without being touched.

**Fix (direction).**
- No order of the cover fixes it: positions sum to 70, while the two per-side caps admit 50 and 30.
- The per-side caps of the payment and each family credit should count the cover as the position does. That means reading `overpayment_absorbed_as_of` (with the cover) at the draw's date, instead of the shares as recorded.
- Then K2's cap admits 20, the payment's 50, and the pool 70.
- That reverses r6's "a draw uses only its own side's money" between the members. Kyle's 10-30 answer allows it: the order is ours.
- Alternatively, Ryan could accept it as a residual. Then the comments should drop "a position equals what its cap admits" for this case, and agree() should allow it.
- **Tests:** G in Z, through agree().

---

## Should fix

### S1. The escheat move takes the credit's lock without the payment's, so a transaction that escheats and then draws on the family deadlocks with a give-back (executed, race D2)

- **The two lock orders.**
  - `enforce_customer_credit_immutable` takes only `credit K` for a move to escheated.
  - A give-back under the payment takes `payment`, then every live family credit.
  - A transaction that escheats K and then draws on the payment (or on any family credit) therefore takes K, then the payment. The give-back takes them in the other order.
- **D2 (tally_app, executed).**
  - Setup: payment 100, K 20 remitted in full, 10 taken back.
  - A: escheat K, sleep 3 s, then refund 5 from the payment.
  - B (1 s later): a give-back of 5 under the take-back. B was seen blocked by A.
  - Result: **A: deadlock detected (40P01)**; B commits.
- The money is not at risk; the transaction is retried. But the header's r7 sentence says "the payment, then its credits, for every writer on the family", and the escheat move is a writer on the family. Fable r6 N4 noted that this move takes only its own row.
- **Fix.** A move to escheated of a credit with `overpayment_root` not null takes the payment's lock first, as the void now does. Add D2 as CR26, and a mutation in N215's style.

### S2. Tests
- Add H (B1) and G (B2), both through agree().
- Add D2 (S1).

---

## Notes

- **N1 (executed). Performance on the 999-deep line, one act at a time.**
  - The 999th reissue's position, the root's and the payment's each read in 0.4–0.5 s.
  - A refund of 1 from the 999th reissue was admitted in **25–27 s**, holding the payment's lock throughout.
  - So the line is usable but slow, and every family writer waits behind each act.
  - Item 7 of the brief works: Codex's probe on r6 ran for over 50 minutes.
  - Real lines are 1–3 deep, so I would not lower the bound on this alone (the rule is to measure the realistic shape). R21's text should record the 999 figures beside its 10-reissue ones.
- **N2 (predicted). The escheat check on the credit's own side refuses nothing legitimate,** but it can leave a credit active and reading 0 for good:
  - This happens when its own money covers a sibling's or the payment's deficit that is never repaid.
  - The credit cannot be voided either, since it is drawn on.
  - That is harmless (there is nothing to remit), but the core's escheat run should expect active credits at 0 that never close.
  - A credit that truly holds nothing is still escheated (Z4f executed).
- **N3. R23, and the escheat report in particular.** Leaving netting across payments to the core is right for the database. Two points for AC-44:
  - **Netting may not be lawful everywhere (predicted).** Within one payment the netting is the same money coming back, so the database is right to net it. Across payments, netting a credit against a separate debt before reporting it as unclaimed property is a setoff. Whether a holder may make that setoff depends on the state's unclaimed-property law. AC-44 states it as unconditional. It should be a per-jurisdiction rule the core reads, not a fixed step. That follows the standing rule that a Texas launch never justifies Texas-only design.
  - **"An ordinary application" has no target (executed catalog read).** Every application names an invoice (`invoice_id` is required). A payment's deficit after a bounce (K-10's "the customer owes what was paid out") is not an invoice line. So AC-44's ordinary application has nothing to point at unless the core first bills the deficit as a charge. AC-44 should say how the netting is recorded.
- **N4 (predicted). Lock order otherwise.** Every other family writer takes the payment first:
  - the void of a reissue or of the overpayment credit;
  - each draw (application, refund, donation, remittance);
  - a credit's refund that leaves, and its return;
  - the reissue;
  - the give-back.

  The take-back takes the payment only. S1 is the one exception I found.
- **N5 (predicted). Is every cap behind its lock?**
  - The escheat move reads the own side and the covered position under the credit's lock only.
  - Its own side changes only through the shares and the credit's own draws.
  - A give-back takes the credit's lock, so it waits or is seen.
  - A take-back can only lower the own side.
  - A payment draw changes the cover, not the own side.
  - So the escheat move's checks are sound without the payment's lock. S1 is about the order the locks are taken in, not about a cap.
- **N6.** Residuals R1–R23 are not blocking. R22 is a fair price for not re-splitting shares at the void. R20's "the money is the same either way" is right about the money, but B2 shows that the order does decide what one line shows against what it pays.

## Probe record (executed)

- **H:** 0/30 after the first take-back; escheat admitted; −10/−30 after the second; the give-back of 40 admitted (0/0); after the payment's refund came back, **40 / 10 escheated**. Own side +10. Refunds from the payment: 50 and 40.01 refused, 40 admitted. Refund of 10 from K refused (escheated). agree() FAIL.
- **G:** 0/−10/0, then 40/0/0, then **50/0/20**. agree() FAIL at K2 (20.01 admitted). From K2: 30.01 refused, 30 admitted. From the payment: 50.01 refused, 50 admitted. After K2's 30: 40/0/0, payment 40.01 refused by the pool, 40 admitted.
- **D2:** B seen blocked by A; A 40P01; B committed.
- **T:** positions 0.40–0.51 s; refund on the 999th reissue 24.8 s and 27.0 s.
- **Battery** 372/372. **Races** 39 PASS.
