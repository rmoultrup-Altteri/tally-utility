# Opus review — v5.4.2-24 r2 (unmatched cash and agency pledges)

**Date:** 2026-11-07. **Reviewer:** Opus. **Brief:** `review-brief-24-r2.md` (md5 `de4fcfe90ac651ae07079d50e7ed974e`, matches its `.md5`). I read the r2 plan and my own r1 review, and no other reviewer's file.

**Verdict: not yet.** One blocking item. The recorded-order fix covers rows that spend a receipt's money, but not rows that give money back to it: an undo, and a misposting return. Either can be recorded before the row it gives back, so at a past recorded instant a receipt of 100 reads as holding 200. That happened at READ COMMITTED as `tally_app`, with two sessions. It is the r1 recorded-order finding (Codex B4) on its other side, and the fix is a few lines. One should-fix item: the invariant's list of function bodies leaves out the shared READ COMMITTED pin and four other functions the guards depend on. Every other round-1 finding I can judge is closed.

## Hashes and reproduction (executed)

- The six frozen md5s match the brief: patch `9b440cd1…`, battery `46d5e076…`, races `f0cd45f0…`, mutations `e366080d…`, ci diff `c343828b…`, r1-to-r2 diff `259bc084…`. The live patch and battery are identical to the frozen copies.
- Clone `rv24opus` (`TEMPLATE tally`; TEMP revoked from PUBLIC, `tally_app` and `tally_core`). Strict apply (`search_path=`, `check_function_bodies=on`): rc 0. Second run: `NOTICE: v5.4.2-24: already applied (suspense_receipts exists); nothing to do`, rc 0.
- `battery-24-frozen-r2.sql`: 234 PASS, 0 FAIL.
- `suspense-24-frozen-r2.sh rv24opus`: 21 PASS, rc 0 (SU1–SU10).
- I did not run `ci.sh` or the mutation runner, as the brief says. I created, dropped or altered no role and did not touch `tally`. The clone is dropped and `/tmp/rv24opus-*` is removed from the container.
- The probes used the battery's helpers and fixtures (battery lines 1–178) as a prefix, in one transaction that was rolled back. The exception is O3 below, which committed rows in its own tenant on the clone. The probe scripts were scratch files and are not in the repo.

## Round-1 findings: are they closed?

| r1 item | State | Evidence |
|---|---|---|
| Opus B1 (a bank's take-back recorded as reversed gave the money back) | closed | Reversal alone keeps the payment counted. The misposting return is refused when the payment has a return code, and a return code written later is refused under the receipt's lock. Battery P12b, P9b9 and mutations M71 and M77 cover it (executed: battery). -23 also refuses a ledger row that re-posts an ended payment, so the return cannot be followed by re-posting the money to the first customer: `O4 => REFUSED 23001 … gives money back to payment …, which has ended` (executed). |
| Opus B2 (the reversed share came back on every date) | closed | The payment counts on every date, and the return counts from its own date, which is on or after the reversal's ledger date. P9b2 and M74 cover it (executed: battery). |
| Opus B3 (one provider id as a receipt and a payment under REPEATABLE READ) | closed | The pin is inside `check_provider_transaction_once`. SU8 passed (executed). |
| Opus S1 (the invariant checks no constraint) | closed for constraints and indexes; narrower for bodies | See S1 below. |
| Opus S2 (settings forged through the history table) | closed | `tenant_configuration_history_suspense_days_check`, and the reader raises on an unreadable value. Battery S5b (executed). |
| Opus S3 (gaps in Ryan's 11-07 rule) | closed | Stated as limits L5 and L6, and Ryan ruled on 11-07 that they stay known limits. |
| Opus S4 (missing tests) | closed | The shortfall-reissue trace, a return-coded reversal, the provider id under REPEATABLE READ, and constraint, index and body mutations (M89–M93) are all present. |
| Opus N1, N2, N4 | closed | The name index is partial. The pledge checks its customer's tenant. The header states "every writer retries 40P01 and 40001". |
| Codex B4 (recorded order) | **closed for spending rows only** | See B1. |
| Codex B1, B2, B5; Fable B1, B2 (provider ids), as the plan states them | closed (read) | All four of the plan's points are in `check_provider_transaction_once` and `enforce_payment_suspense_pledge`. |
| Codex B6 (clocks) | closed (read and executed) | `b_enforce_recorded_at` is on all seven tables and the invariant requires it. The finite-date CHECKs are present. |

The patch implements the design, CI-053, CI-056's record side, and Ryan's 11-07 rule within L5 and L6, apart from B1.

---

## B — blocking

### B1. A row that gives money back to a receipt is not ordered after the row it gives back, so a receipt can read as holding more than it ever received (executed)

`enforce_suspense_disposition` calls `check_suspense_recorded_order` only when `NEW.amount > 0`. A negative row (an `undo` or a `misposting_returned`) is never ordered, and nothing compares it with the row it releases:
- an undo is not compared with the `created_at` of the disposition it undoes;
- a misposting return is not compared with the `status_recorded_at` of the payment's reversal, which `check_suspense_recorded_order` never reads.

That is lesson `history-stamped-at-xact-start`, and -23's tree check refuses it for every row, not only for draws.

**O3: as `tally_app`, at READ COMMITTED, two sessions (executed).** The receipt is O3-R1 for 100, committed. Session A begins, reads `now()`, and sleeps 4 s. Session B records `returned_to_sender` 100 and commits. A then records an `undo` of B's row and commits. Both were accepted:

```
        kind        | amount  |          created_at
 undo               | -100.00 | 2026-11-07 21:29:05.39119+00
 returned_to_sender |  100.00 | 2026-11-07 21:29:06.911521+00
-- suspense_receipt_position_as_of(R, 2026-03-10, the instant between):
 amount 100.00 | to_payments 0.00 | disposed -100.00 | held 200.00
```

**O1: a superuser history load with chosen times (executed).** The receipt is recorded at 11-01 10:00, and its payment of 100 at 11:00. The payment is posted and then reversed; the reversal is recorded at `now()`. A misposting return is then given `created_at` 11-01 12:00, before the reversal, and is accepted: `O1 misposting return recorded before the reversal => ACCEPTED`. Read at 11-01 13:00, the payment is live (its reversal is not yet recorded) and counts 100 in `to_payments`, yet the receipt also holds 100 (`held 100.00`). The same 100 is shown as both spent and held. **O2** is the chosen-time undo, recorded before what it undoes: `held 200.00` on a receipt of 100, and `suspense_held_as_of` for the tenant reads 300 where 200 was held.

**Why it blocks.** `suspense_held_as_of` at a recorded instant is the figure L4 says reconciles the subledger to the bank, and `suspense_receipts_aged_as_of` (-26's `aged_suspense`) reads the same positions. This is the defect class r1 judged blocking (Codex B4), now on the release side. The brief asks "any release that should be ordered?": these two should be.

**Fix (small; measure it).** In `enforce_suspense_disposition`, call `check_suspense_recorded_order` for every row, not only positive ones. In that function's union, add `p.status_recorded_at` for payments of the receipt in status `reversed`, beside the voided ones. An undo then waits for, or retries after, its original. A misposting return waits for, or retries after, the reversal. Both get 40001 at `now()` and 23514 for a chosen time. A narrower alternative is two direct comparisons (`u.created_at` and `v_pay.status_recorded_at` against `NEW.created_at`) with the same two error codes. Tests: a battery case for a chosen-time undo and a chosen-time misposting return, a race in SU10's shape for an undo begun before its original committed, and a mutation that restores the `amount > 0` gate.

---

## S — should fix

### S1. The invariant's body list is narrower than "the guards and readers" it claims (executed)

`c_bodies` holds 19 functions. It leaves out functions that every guard calls or that decide the outcome:
- `suspense_require_read_committed`: every READ COMMITTED pin in the patch, including the r2 provider pin;
- `suspense_today_earliest` and `suspense_today_latest`: the "a lapse waits until pay_by has passed everywhere" rule, and every "no later than today" rule;
- `assistance_agreement_in_force`: it chooses the agreement and so `pay_by`;
- `suspense_receipts_aged_as_of`, `suspense_held_as_of` and `agency_pledges_open_as_of`: the readers -26 and L4 rely on;
- `suspense_service_level_days_as_of` and `suspense_retention_days_as_of`.

Each probe below was run as the owner, one at a time under a savepoint, and the invariant passed every time:

```
O5a READ COMMITTED pin made a no-op (RETURN)              : invariant => PASSES
O5b suspense_today_earliest() returns 9999-01-01           : invariant => PASSES
O5b2 assistance_agreement_in_force returns NULL            : invariant => PASSES
O5e suspense_receipts_aged_as_of returns no rows           : invariant => PASSES
```

O5a alone would reopen r1's B3 (Opus), and every other pinned lock-read, with the invariant still passing (lesson `checks-narrower-than-their-claim`). **Fix:** add these nine functions to `c_bodies` (`fill-body-md5.py` fills them), and add one APPLY mutation that makes the pin a no-op. The function's comment then matches what it checks.

---

## N — notes

- **N1 (read). Comments that still describe r1.** The table comment on `suspense_receipt_dispositions` lists four kinds, leaves out `misposting_returned`, and says the cap counts "payments (not voided or reversed)". The comment on `suspense_receipt_position_as_of` says "not voided or reversed as recorded then". The code now counts a reversed payment. The comment on `enforce_suspense_disposition` mentions neither the misposting return nor the recorded order. The comment on `enforce_payment_suspense_pledge` leaves out the instrument rule on update and the return-code refusal. The invariant's grant message names two functions and checks three.
- **N2 (executed). The provider pin binds every payment that has a provider id, not only those from receipts.** An ordinary webhook card payment of a customer, inserted at SERIALIZABLE, is now refused: `a provider transaction id is written at READ COMMITTED (this transaction is serializable)` (O6). The design says "READ COMMITTED only", so this is intended. It is still a new obligation on every payment writer, and so on -23's intake, and it should be an APPLICATION-CONTRACTS entry. The same holds when a provider id is first written on an UPDATE.
- **N3 (executed). The invariant reads neither NOT NULL nor function settings.** Dropping NOT NULL on `suspense_receipts.amount` and `suspense_receipt_dispositions.disposed_on` passes it (O5c). A CHECK then passes NULL (lesson `check-passes-null`). So does `ALTER FUNCTION check_suspense_receipt_cap SECURITY DEFINER` together with `ALTER FUNCTION enforce_suspense_disposition() RESET search_path` (O5d). -27 and -23 have the same gap. This is optional here, but worth a line in PATCH-LESSONS.
- **N4 (read; predicted). A load with foreign keys off.** Under `session_replication_role = replica`, a superuser could write a disposition, a candidate or a pledge event whose tenant differs from that of its receipt or pledge. The ALWAYS triggers read the parent by id only, unlike the payment and pledge triggers, which r2 fixed. The fix is one `AND x.tenant_id = NEW.tenant_id` per trigger, or a statement that a history load runs with foreign keys on.
- **N5 (read; predicted).** An agency can be inserted already retired, with any `retired_at` (the trigger is BEFORE UPDATE only). It is harmless, because nothing reads `retired_at` and a retired agency takes nothing new. The agreement trigger refuses the equivalent at insert. For symmetry, one line in `enforce_assistance_agency_retire` on INSERT would close it.
- **N6 (read).** -23 allows reversing a payment whose overpayment credit was already refunded ("what the credit paid out stands"). The misposting return then gives back the whole payment, so the sender can be repaid while the wrong customer owes the refund back. That is coherent with -23's model (a receivable from that customer), but it is a case worth a scenario.
- **N7 (read). -23's and -27's properties.** `enforce_payment_suspense_pledge` fires after every `a_*` BEFORE trigger and after `enforce_payment_immutable`, and never assigns to NEW. The return-code path takes the receipt's lock after -23's payment lock, the stated order. The cap's AFTER trigger fires after `enforce_cash_draw` and only reads. Nothing in -24 changes what -23's positions, caps or recorded-order rules see. The receipt now counts a reversed payment as -23 does, so the r1 disagreement between the two readers is gone.
- **N8 (judgement). Known limits.** L1 and L3 are fine. L2 fails toward protection. L4 is fine once B1 is fixed. L5 and L6 stand by Ryan's 11-07 ruling. None is blocking.
- **N9 (predicted; executed in r1). COPY and writable CTEs.** I did not re-probe them in r2. The cap's statement shape is unchanged since r1 (AFTER ROW, under the receipt's lock), where I found them safe.
