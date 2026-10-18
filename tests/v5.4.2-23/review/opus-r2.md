# Opus review: v5.4.2-23 r2

**Date:** 2026-10-18. **Reviewer:** Opus. **Verdict: not yet.**

## Setup

- **Frozen files.** All six md5s match the brief (`md5 -r`).
- **Clone.** `rv23opus` was made with TEMPLATE tally. TEMP was revoked from PUBLIC, tally_app and tally_core right after.
- **Strict apply, twice.** The frozen r2 patch went in with `search_path=''` and `check_function_bodies=on`. The second run skipped on its marker. The three invariant functions pass.
- **Battery.** The frozen battery passes 168/168 on the clone.
- **Probes.** Fixture: battery-23 lines 1–200 (helpers, T1/C1, bills I1–I3, tariff `…23ab`, P61–P65, K71). Every probe runs as tally_app in one transaction, then rolls back. The probe files are in my scratchpad, not in the repo.
- **Not run.** I did not re-run `cash-23.sh` or `mutations-23.py`.
- **Clone dropped.** At the end I mutated two functions on the clone for the test-gap check (T1 below). The clone is now dropped.

Every claim is marked **executed** (run on the clone) or **predicted** (from reading the code).

---

## Round-1 findings

| Finding | Status |
|---|---|
| Opus B1: source read before its lock | **Closed** (predicted, from code). `check_cash_source` takes the lock first. Every read follows it in a later statement: plpgsql statements, and STABLE SQL helpers called from them, take a fresh RC snapshot. The triggers keep only reads of fixed-from-insert columns before the lock. |
| Opus B2 O1: born posted | **Closed** for every role except a superuser (executed via battery R1/R1b). The superuser exception is stated in `enforce_cash_birth`'s comment. |
| Opus B2 O2: bounced money still applied | **Partly closed.** Two paths remain, both executed: B1 and B2 below. |
| Opus B2 O3: a 1.00 row ends a 30.00 payment | **Closed** (battery R3; code: remaining = 0). |
| Opus B2 O6: a reversed credit still applied | **Closed** for applications (predicted, from code). The credit branch of the bounce guard opens a new problem, B5. |
| Opus B3 O4b/O4c | **Closed** (battery R8c, R8d). |
| Opus B3 O5: nsf with a refund pending | **Not closed, and misstated.** See B3. |
| Opus S1: positions inside an open transaction | **Closed by statement.** The model is in the section comment and in the payment and credit readers' comments. The line and bill readers' own comments do not repeat it (N3). |
| Opus S2 / Fable N11: future-dated rows | **Closed** (code, line 438). |
| Opus S3: history row recorded before its source or bill | **Closed** (battery R18; code). |
| Opus S4: cross-tenant approver | **Closed** (composite FK). |
| Opus S5: column grants | **Closed** (executed). `GRANT UPDATE (reason) ON invoice_applications TO tally_app` is caught. A default of `posted` is caught too. |
| Fable B1 / Codex B1: every way money leaves a source is a draw | **Closed** (CHECK, draws set, R11/R12). |
| Fable S7: a payment row names a charge | **Closed** (battery line 836). |
| Codex B3: R2 | **Closed** (stamp plus reader). R17 tests it only through a superuser's chosen stamp (N2). |
| Codex B4: a cause names the act | **Partly closed.** The posting entry's kind is checked, but its `reference_type` may be either label, and the bounce guard keys on one of them (B1). A refund's posting row may name any entry (B5). |
| Lock order restated | **Accurate for single-act transactions** (N4). |

---

## Blocking

### B1. A posting entry labelled `reference_type = 'refund'` escapes the bounce guard (executed)

- **The mismatch.**
  - The move to `posted` accepts a posting row with `reference_type IN ('payment','refund')` (patch line 1406).
  - The bounce guard looks for a payment root only when `v_root.reference_type = 'payment'` (line 538).
- **Repro (all accepted).**
  1. Pending payment PA (50) gets a `payment` row of −50 with `reference_type 'refund'`, `reference_id` PA.
  2. PA moves to posted naming that row.
  3. 50 of PA is applied to I2's gas line.
  4. The full nsf row (+50) reversing the posting row goes in while PA is applied.
- **End state.** PA is `posted`, 50 applied, posting entry remaining 0.00, `cash_arrival_stands` false. This is round 1's O2 again, through a label the caller chooses.
- **The same path for deposits** (predicted).
- **Fix.** Take one label in both places (`'payment'` only), or key the guard on `payments.status_cause_id = v_root.id`, which is the act.

### B2. The K1 refund exemption is keyed on a caller-chosen `reference_id`, not on the refund's posting act (executed)

Both the bounce guard (line 541) and `cash_arrival_stands` (lines 1852–1855) exempt any row whose `reference_id` is a refund of the payment, whatever its type and amount. `cash_arrival_stands` also exempts that row's whole subtree.

- **Repro (all accepted).**
  1. PB (50) is posted, and 10 of it is applied.
  2. Refund RB of PB is inserted at −1.00, pending.
  3. An `adjustment` of +49 goes under PB's posting entry, citing RB.
  4. `cash_arrival_stands(PB)` is still **true**, with remaining −1.00.
  5. 39 more of PB is applied.
- **End state.** 49 of PB is applied and 1 refunded, while 49 of its money has left the ledger.
- **Fix.** Exempt only a `refund`-type row at minus the refund's amount, one per refund, for a refund that is pending or posted. In the arrival test, exempt only that row (the posted refund's `status_cause_id`), not its subtree.

### B3. K2's stated behaviour is not implemented, and nothing tests it (executed)

- **What the patch says.** The header says a payment with a pending refund moving to nsf or reversed is "refused until the refund is voided (now)".
- **What the code does.** Neither the bounce guard nor the move checks refunds (lines 544–545, 1441–1448).
- **Repro (all accepted).**
  1. PC (50) is posted.
  2. Refund RC (−15) is inserted, pending.
  3. The nsf row +50 goes in.
  4. PC moves to `nsf`.
- **End state.** PC is `nsf`, RC is `pending`.
- **-19 depends on acceptance.** -19's fixture (battery-19 lines 384–395) moves P-2 to nsf with its full refund P-4 pending. Implementing the header's sentence would break -19 P5c.
- **Fix.** Either make the header say "accepted (r1)", or implement the refusal and change -19. Then add a test either way.

### B4. A refunded payment's refund is undone on the ledger; only the status move is guarded (executed)

- **Repro (all accepted except where marked).**
  1. PD (40) is posted.
  2. Refund RD (−40) is inserted, its refund row (+40) goes under PD's posting entry, and RD is posted.
  3. PD moves to `refunded`.
  4. An `adjustment` of −40 goes under RD's posting row: the refund check was never cashed.
  5. RD's move to `reversed` is **refused**, by R8d's guard.
- **End state.** PD is `refunded`, RD is `posted`, and PD's position shows remaining 0. But PD's posting entry has remaining −40.00: the customer holds the 40 on the ledger, and it is also counted as refunded.
- **Why the guard misses it.** The guard is on the status move, not on the act (the ledger row). For this row the bounce guard sees root PD with nothing applied, so it passes.
- **Fix.** Refuse a row under a counted refund's posting entry while the refund's source is refunded. The analogue for credits is predicted.

### B5. A credit's refund cannot be posted correctly, and a refund's posting row may name any entry (executed)

- **The credit's own entry is refused.** K71-like credit KA (25) has its `credit_issued` entry (−25). Its refund RK (−10) is pending. RK's `refund` row naming KA's `credit_issued` entry is **refused** (23001): the credit bounce guard counts RK itself as a draw. No exemption exists for a credit's own refunds.
- **Another payment's entry is accepted.** The same row naming P61's posting entry is **accepted**, and RK's move to `posted` naming it is accepted. The move checks only the type, the reference and the amount (line 1402).
- **Result.** P61 (unrelated, unapplied) now has `cash_arrival_stands` = **false**. KA still stands.
- **The same for payment refunds.** A payment's refund may name another payment's entry (predicted, same check).
- **Coverage.** Nothing in battery-23, the races, -21 or -22 posts any refund on the ledger.
- **Fix.** The move of a refund to `posted` requires its row to reverse its source's arrival entry: the payment's `status_cause_id`, or the credit's `credit_issued` entry at minus its amount. The credit guard exempts the credit's own refund rows, bound as in B2 (under K1 as it stands).

---

## Should fix

**S1. One arrival entry per source (executed).** These were all accepted:
- credit KB (20) with two `credit_issued` rows, −20 and −200 (`cash_arrival_stands` true);
- a second `payment` row of −100 for P61.

The ledger then credits the customer 220 for a 20 credit, or 200 for a 100 payment. A credit's void reverses one of the rows and leaves the other. Suggested fix: a partial unique index, or a check at the arrival row's insert.

**S2. The K1 exemption is untested (executed).** On the clone I removed the exemption from `cash_arrival_stands` (mutation A), then also from the bounce guard (mutation B). The battery still passes 168/168. Add:
- a positive test: a payment's own refund row is admitted while the payment is applied, and the payment still stands;
- negative tests: B2, B4 and B5.

---

## Notes

- **N1 (executed).** A pending payment can be posted naming an entry already fully reversed (PE: −30, nsf +30, then posted). It gives no money, because the arrival test fails, and it can still reach nsf. This is harmless, but `posted` then names money that is not there.
- **N2.** R17 proves R2 closed only through a superuser's chosen `status_recorded_at`. Add one leg where tally_app voids a refund, so the database stamps it, and the position is read at an instant between the two moves.
- **N3.** The "fixed once R is older than every open transaction" sentence is in the section comment and in the payment and credit readers' comments. The comments of `invoice_line_position_as_of` and `invoice_position_as_of` omit it.
- **N4 (predicted).** "Tree, then source; nothing takes them the other way" holds only for one act per transaction. A donation of credit K takes K's source lock; a later `credit_issued` reversal in the same transaction then takes tree, then K. A status move followed by a ledger row behaves the same way. Each is a 40P01 that a retry resolves, consistent with "post each act in a transaction of its own". The sentence should say so.
- **N5.** The older-test edits (-19 P1, P-2, R4-PARENT, B1 balance; -21 credit 2161, payment 2181) each follow the birth or arrival rule. None loosens an outcome. -19 P-2/P-4 is the K2 state (B3).
- **N6.** The residuals R1 and R3–R11 are acceptable as stated. R2 is closed.

---

## K1-A: if Kyle answers K1 "a refund is its own movement of money" (not counted against the patch)

- **K1-A1. X1.**
  - `refund` leaves `account_ledger_reversal_types_name_check` and `_only_check`.
  - A refund row then names nothing, so X2 no longer gives it a sign: add a CHECK that `refund` is greater than 0.
  - The `reversed` cause's `NOT IN ('nsf','refund')` becomes moot.
- **K1-A2. The exemptions go.** Drop the exemption from `cash_arrival_stands` and from the bounce guard. B2 disappears.
- **K1-A3. A refund's posting row becomes a root.** It needs its own bounce branch: a row under it is refused while its source is refunded. That is B4's fix, needed under either answer.
- **K1-A4. The nsf row can carry the bank's full return (executed under K1 as it stands).**
  - Repro: PF (50) has a posted refund of 15. The bank returns 50.
  - The nsf row of +50 is refused (cap 65 > 50). Only +35 fits.
  - PF's tree then nets 0.00, so the customer is not shown owing the 15 refunded from money that never arrived.
  - Under K1-A the +50 fits, and the ledger shows the 15 owed.
- **K1-A5. K2 becomes load-bearing.**
  - Today, a pending refund of an nsf payment can post only by naming some other entry (the cap blocks its own payment's entry; see B5).
  - Under K1-A its row names nothing, so nothing stops it.
  - Either answer to K2 then needs a check at the refund's move to `posted` that its source is still posted or active. Today no source check runs at that move; `check_cash_source` runs only at the refund's insert.
- **K1-A6. B5 eases.** A credit refund posts as its own root, and the credit guard needs no exemption. The posted check should still pin the type and amount. B5's "names any entry" goes away, because it names none.
- **K1-A7. Tests that change.**
  - battery-23: none today. No test posts a refund row; the X1 test uses nsf.
  - New tests: the K1-A1 sign CHECK and the K1-A3 refund-root guard.
  - The S2 tests would be rewritten for roots.
  - -19 P-2/P-4 and -21's refund rows (B21-R1…R3, payment refunds that are never posted) are unaffected unless K2 changes.
  - Mutations N83/N84 are unaffected. Any new mutation of the exemption is dropped.
