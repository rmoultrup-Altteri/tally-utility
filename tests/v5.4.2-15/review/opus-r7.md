# Review round 7: v5.4.2-15 (rewrite), Opus

**Verdict: READY.** My round-6 B1 (refund guards fooled by several events in one INSERT) is closed, and so is N1 (a payment dated before its refund notice). I searched for other checks that read a projected column. One more lags, in `enforce_deposit_return_due_record`; I record it as **S1 (should-fix)**. It lets a due row be recorded beside a refund that has already started. No money amount or money movement can go wrong through it, so it does not block. The fix is small and I would take it this round if the lead agrees.

## What I checked

- **Hashes match.**
  - Patch: `44a4d2b1a6cbe135c6744c40331bf1f9`
  - Battery: `ebe98c8751838d53031ecf020eac8ba8`
- **Clone `opus17`.** It was made from `tally`, with TEMP revoked from PUBLIC, tally_app and tally_core. The patch applied strictly (`search_path=''`, `check_function_bodies=on`, ON_ERROR_STOP). The battery passed **352/352**. The clone is dropped.
- **The delta.** `diff r6 r7` shows changes only inside `enforce_deposit_event`:
  - "closed" and "notice date" are now read from `deposit_events`;
  - five status checks now use them;
  - a new check refuses a payment dated before its notice.
- **Probes.** My round-6 probe set ran again after block r29. The new probes are in `opus-r7-probes/`. Everything ran as tally_app and was rolled back.

## The delta

**B1 is closed.** Every multi-row probe that frozen r6 accepted is now refused, each by the intended guard:

| Probe | What it tried | Result |
|---|---|---|
| MS1 | Refund notice, then an instalment | Refused: "refund is pending" |
| MS4 | Refunded, then an instalment | Refused: "is refunded: no further events" |
| MS5 | Refund notice, then a partial return | Refused: "refund is pending" |
| MS7 | Two refunds | Refused: "is refunded" |
| MS2 | Refunded, then an instalment, then an application | Refused, now by the intended guard rather than by the status-dates CHECK |

All the round-6 single-statement probes behave as before: ties, several receipts, backdated debits, the status after a late receipt, and the refund date.

The approach also holds across a writable CTE. Whichever part of the statement runs second sees the first part's event rows, so event-against-event checks are order-proof.

**Your decision to treat "pending" as "a `refund_initiated` exists" is sound.** The ledger cannot cancel a notice, so once a notice exists the deposit stays pending.

**Legacy refunded deposits.** -06 backfilled these with synthetic `refunded` events (D-2026-08-28-42), and the migration refuses non-legacy rows. Reading from events therefore loses nothing that `d.status` used to hold.

**N1 is closed.** Probe R3 (a `refunded` dated 15 Feb against a notice dated 20 Feb) is now refused with "precedes the refund notice".

## Search: other checks that read a projected column

Columns written by AFTER triggers: `deposits.status`, `refunded_on` and `released_on`. All of them are written only by `project_deposit_status`.

| Reader | Verdict |
|---|---|
| `enforce_deposit_event` | Clean now |
| `enforce_deposit` on INSERT ("born held") and UPDATE ("status only from events") | Guards the projection itself; fine |
| `deposit_balance.days_held` | Uses refunded_on/released_on; it is a read, not a guard |
| `deposits_return_owed` view | Filters on status; a read |
| `UPDATE deposits SET status = status` (lines 4649, 4830) | Writes a new row version as a mutex; reads nothing |
| Evidence, withdrawal and instalment triggers | Read no projected column |
| **`enforce_deposit_return_due_record`, patch:4674** | **Lags: S1** |

## S1 (should-fix): a due row recorded in the same statement as a refund event

The check at patch:4674 is `IF d.status IN ('refund_pending','refunded','released')`. A separate statement is refused correctly: probe DUE2 got "already refund_pending — its return has started". A single statement built as a writable CTE gets through in both orders. Both runs were tally_app, with evidence written and the constraints checked:

- **DUE1.** The CTE inserted a `refund_initiated` of 60 dated 1 Mar; the main statement inserted a due row dated 1 Apr. **Accepted.** The deposit ended `refund_pending` with a live due row.
- **DUE3.** The CTE inserted the due row; the main statement inserted the `refund_initiated` of 100. **Accepted.**

**Why reading events in the BEFORE trigger is not enough.** I added a diagnostic BEFORE trigger on `deposit_return_due` inside the rolled-back transaction. In DUE1 it saw **0** refund events, because the main statement ran before the CTE. In DUE3 it saw 1. Which part runs first is not fixed. A BEFORE-row check, whether it reads status or events, would therefore still miss DUE1.

**Impact.** No money is affected:
- The owed list filters on status, so this deposit drops out of it.
- A refund may still cite the due row.

What it breaks is the record: a return "fell due" after its refund had already started, which is the thing this guard exists to refuse.

**Suggested fix (measure first).**
1. Move the check into a non-deferred `AFTER INSERT … FOR EACH ROW` constraint trigger on `deposit_return_due`. It fires at statement end, when both rows exist.
2. Refuse when a `refund_initiated`/`refunded`/`released` event of the deposit exists whose `return_due_id IS DISTINCT FROM NEW.id`. A refund that cites this due row is the legitimate path and stays allowed.
3. Battery cases: DUE1 and DUE3, plus a mutation back to the BEFORE-row status read.
