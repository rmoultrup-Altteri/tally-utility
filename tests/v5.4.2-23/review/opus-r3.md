# Opus review: v5.4.2-23 r3

**Date:** 2026-10-21. **Reviewer:** Opus. **Verdict: not yet.**

## Setup

- **Frozen files.** All six md5s match the brief (`md5 -r`).
- **Clone.** I made `rv23opus` from `tally` (TEMPLATE). Right after, I revoked TEMP from PUBLIC, tally_app and tally_core, and checked that neither role has TEMP.
- **Strict apply, twice.** The frozen r3 patch applied cleanly with `search_path=''` and `check_function_bodies=on`. The second run skipped on its marker.
- **Battery.** The frozen battery passes 216/216 on the clone.
- **Probes.** Each probe is the frozen battery with its final `ROLLBACK` removed, followed by my probe statements and a `ROLLBACK`. The probes reuse the battery's fixtures: K4 escheated, the S7 overpayment credit KO, and customer C3. I added customer C4 and bill I9. Unless a probe says otherwise, it runs as tally_app under `app.user_id`. The probe files are in my scratchpad, not in the repo.
- **Not run.** I did not run `cash-23.sh`, `ci.sh` or `mutations-23.py`. I only read the mutation list.
- **Clone dropped.** The clone is gone, and so are my files in the container.

Every claim is marked **executed** (run on the clone) or **predicted** (from reading the code).

---

## Round-2 findings (mine)

| r2 | Status |
|---|---|
| B1: a posting entry labelled `refund` escapes the bounce guard | **Closed.** The arrival-row check forces `reference_type = 'payment'`, and the bounce guard keys on that one label (battery S6c, executed). |
| B2: the refund exemption keyed on a caller-chosen reference | **Closed.** The exemption is deleted (K-10 1 = A). Neither the guard nor the arrival read has an exemption left (predicted, from code). |
| B3: K2 stated but not implemented | **Closed.** A row undoing the posting entry is refused while a refund is pending (battery S4/S4a). -19 P-4 is cancelled first. The status move itself does not repeat the check, but it cannot be reached with a pending refund: the move needs a full undo, and the cap refuses any refund after one (predicted). |
| B4: a refund undone on the ledger while both statuses stand | **Closed by the status decision.** `refunded` is gone. R12 states the residual (battery R8e–R8h). |
| B5: a credit refund names any entry | **Closed.** A credit refund posts as its own root, naming nothing (battery S7, S7c). |
| S1: one arrival entry per source | **Closed** for duplicates (the unique indexes; battery S6, S6e). **New gap:** an arrival row is still accepted for a source that has ended (B2 below). |
| S2: the refund exemption untested | **Closed.** Refund posting is tested (S1, S7, S7c, R8f). |
| N1: posted by an entry already undone | **Closed** (battery S13). |
| N2: R17 with a tally_app void between two reads | **Not done, as stated in the plan.** CR13b covers the ordering. |
| N3, N4 | **Closed** (reader comments, header). |
| K1-A1 to A6 | **Applied.** The X1 CHECKs are changed, the refund sign CHECK is added, the exemptions are gone, Kyle's example holds (S1–S1e), and K2 is the source check A5 asked for. |

I also checked the plan's mapping of Fable's and Codex's round-2 items (Codex B6/B7, Fable S3/S4/S5/S7) against the code and the S section. Each fix is present.

---

## Blocking

### B1. An escheated credit gets money back: three paths, none guarded (executed)

The header says "escheated means nothing is left (guard the act)". R12j says an undo does not bring money back to an escheated credit. That rule is enforced only for application undos, through `check_cash_source('undo')`. Three other ways of freeing money run no source check at all.

- **O1. A donation's undo.** K4 is escheated (battery R12i), with a donation of 1. An `adjustment` of −1 naming that donation is **accepted**. K4 then reads escheated with remaining **1.00**. The undo's root is the donation, so `enforce_ledger_reversal`'s source legs (posting entry, credit_issued) never run.
- **O2. A pending refund cancelled after the escheat.**
  1. KX (20) is issued.
  2. Refund RX (5) is inserted, pending.
  3. 15 is remitted.
  4. KX moves to escheated: **accepted**, because the pending refund counts as a draw.
  5. RX moves to voided: **accepted**.
  - KX then reads escheated with remaining **5.00**. The refund's leaving move takes KX's lock but never reads KX.
- **O3. A posted refund comes back after the escheat.** The same shape with RY posted. An nsf row of −5 goes under RY's posting row, and RY moves to nsf. Both are **accepted**. KY reads escheated with remaining **5.00**.

A voided credit cannot reach this state, because a void needs every draw to net to 0. Payments are fine too: an nsf payment whose refund then fails reads 0, which is correct.

**Fix.**
- O1: refuse a row under a credit's donation unless the credit is active. This is the application undo's rule, keyed on the act.
- O2: refuse the move to escheated while a refund of the credit is pending (K2's shape). Alternatively, refuse a refund's void while its source credit has ended.
- O3 is a real-world event: the bank returns the check whatever the schema says. The money has to go somewhere, either a further remittance or a new credit. **This needs a ruling (Ryan/Kyle).** Until then, refuse RY's move to nsf/reversed while its credit is escheated. The refund then stays posted and counted (as in R12), and the record is still consistent.
- Tests: a negative test for each path.

### B2. An arrival row is accepted for a source that has ended: the ledger pays out money twice (executed)

r3 checks a posting row's label, kind, amount and account, but not the state of its payment.

- **O4.** PV (40) is pending, then voided. A `payment` row of −40 referencing PV is then **accepted**.
  - `payment_position_as_of(PV)` reads voided, received 40.00, remaining 40.00.
  - The customer's ledger is credited 40 for money that never arrived.
- **O5.** PW (50) is posted. Refund RW (30) is pending, then cancelled (voided).
  1. RW's `refund` row (+30) is posted anyway: **accepted**.
  2. A second refund of PW for 50 is **accepted** and posts: the cap counts only refunds that are pending or posted.
  - PW's position says 50 refunded and nothing left. The ledger shows 80 paid out against a 50 payment (−50 + 30 + 50).
- **Race (predicted).** The move to voided checks "no ledger row references it" under the payment's lock. The arrival row takes no lock. A posting row that is not yet committed and a void running at the same time can both commit, which gives O4 by timing alone.

**Fix.**
- At the arrival row, take the source's lock. Then require the payment to be pending (the row it will post by), or the credit to be active.
- The same check covers a refund: once it is voided, nothing posts it.
- Tests: O4 and O5, plus a race leg (void against posting).

### B3. A payment whose overpayment credit was refunded can never bounce (executed)

Battery fixture: S7 (60) is posted. KO (20) is an overpayment credit from it. KO's refund (20) is posted (battery S7c). S7 has no applications. The bank returns the 60:
- **O9a.** The nsf row of +60 is **refused** (23001: "held as a credit").
- **O9b.** KO cannot be voided first. It is **refused** (23001: 20.00 is drawn on, the posted refund).

Nothing undoes a posted refund, so the bank's return can never be recorded. This is the same act as Kyle's K-10 example. His point was that recording both movements as they happened keeps the ledger tied to the bank statement. The only difference here is that the refund went out through the payment's overpayment credit.

- **Escheat (predicted).** An escheated overpayment credit blocks the bounce in the same way, because escheated is not voided.

**Fix.** In the bounce guard's credit leg and in the nsf/reversed move's credit check, treat an overpayment credit whose only draws are posted refunds (or escheat) as a posted refund of the payment: it stands at the bounce. Kyle's arithmetic then gives −60 + 20 + 60 = 20 owed. This needs no new ruling; it is K-10 1 applied to the derived credit. Add a test with this example.

---

## Should fix

### S1. The recorded-order leg misses money given back under the arrival entry (executed for a chosen time; predicted for READ COMMITTED)

r3's new leg retries a draw begun before a refund left, or before an overpayment credit was voided. It does not do the same for a row under the arrival entry that gives money back: the re-reversal of a partial reversal.

- **Repro.** This is an owner history load, with times chosen by the probe.
  1. PQ (50) is posted two hours ago.
  2. +5 is taken back 110 minutes ago.
  3. −5 is given back, stamped now.
  4. An application of 50 is recorded at a chosen time one hour ago: **accepted**.
- **What it reads.** `payment_position_as_of(PQ, …, now() − 30 min)` reads received 45, applied 50, remaining **−5.00**.
- **Control.** The same shape with a cancelled refund in place of the give-back is **refused** (23514, "before … left it").
- **Under READ COMMITTED (predicted).** The give-back takes PQ's lock, through the bounce guard's source leg. A draw whose transaction began before the give-back waits on that lock, sees the freed money, and commits with an earlier `created_at`. That is the r2 problem the leg was added to fix.
- **Credits (predicted).** The same holds for a withdrawal undone under a credit's credit_issued entry.
- **Fix.** Add to the leg the rows under `v_entry` that have the source's sign: rows below 0 for a payment's posting entry, and likewise for a credit's.

### S2. Tests for the items above

No battery check, race or mutation reaches B1, B2, B3 or S1. All three blocking items are reached by tally_app with ordinary single acts, so the 140/140 mutation score says nothing about them.

---

## Notes

- **N1 (predicted).** A give-back under the arrival entry is refused while the payment or credit is drawn on: the bounce guard applies to every row under the root, including the rows that add money back. Correcting a mistaken partial reversal therefore means undoing the applications first. This is safe, and R15 already says it for credits. Say it for payments too, or exempt rows that add money back.
- **N2 (predicted).** A `payment`, `deposit` or `refund` row with `reference_type` NULL (or `invoice`) is a credit on the ledger that no check, reader or cap sees. It is app discipline, as before. The readers and the arrival check use the same predicate, so nothing reads such a row as an arrival.
- **N3 (executed).** Status vocabularies:
  - No function, constraint, index, view or policy on payments or credits is keyed on `refunded` or `donated`.
  - The remaining hits are deposits (-15), `escheatment_events.event_type`, and the matview's position column named `refunded`.
  - Only the two position functions read a payment or credit position. Nothing in the database reads a payment's negative remaining. Its consumers are the app and the core.
- **N4 (predicted).** Can anything count twice in the cap? I found nothing. A refund's own posting row names nothing and is not in the draws. A donation's undo is counted once, through the donation's tree. The trees are disjoint, because each row has one parent. Skipping the cap for an undo is safe: an undo only lowers the running total at its date and after.
- **N5 (predicted).** Lock order: I found no cycle for single acts.
  - A refund's leaving move: its own row, its own lock, then its source's lock.
  - An overpayment credit's void: the credit's lock, then its payment's lock.
  - Nothing takes a source's lock and then a refund's or credit's.
  - The escheat freeze takes the head in a BEFORE trigger, before `enforce_cash_draw` takes the credit's lock.
- **N6.** Residuals R12–R15 are not blocking. R12 is the state that B1-O3's interim fix would rely on.
- **N7.** The mutation list for N111–N140 matches the new guards. N112 (K2) is caught at S4, and N128 and N129 by the races. I did not run it.
