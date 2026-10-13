# Review round 6: v5.4.2-15 (rewrite), Opus

**Verdict: NOT YET.** The new timeline guard is correct for every event written in its own statement. One blocking finding (B1) remains. It is older than this round, but it defeats the guard's stated rule and allows worse outcomes: when several deposit events go in as one multi-row INSERT, every check in `enforce_deposit_event` that reads `deposits.status` sees a stale status. A deposit can then be refunded twice, or take money after it was refunded.

## What I checked

- **Hashes match.** Patch `cb770fbafb02e17b6bfb049805439a6d`, battery `46e7c36e12436204a5a33b87580ff3df`.
- **Clone `opus16`.** Made from `tally`, with TEMP revoked from PUBLIC, tally_app and tally_core. The patch applied strictly (`search_path=''`, `check_function_bodies=on`, ON_ERROR_STOP). The battery passed **343/343**. I dropped the clone afterwards.
- **The delta.** `diff r5 r6` shows the guard at patch:5181-5203, a new `v_least` declaration, and three comments. Nothing else changed.
- **Probes.** They ran after battery block r29 (lines 1-1386), in the same transaction, as tally_app, and were rolled back. The files are in `opus-r6-probes/`.

## The delta

**Codex r5 B1 is closed for single-row writes.** The guard is sound. `deposit_principal_in_force` is a step function that changes only on event days. Taking the minimum over NEW's own day plus every later recorded event day therefore covers every day from NEW onward. NEW is not yet in the table, so the test `amount > least` is exactly "held minus amount stays at or above zero". All of these behaved correctly:

| Probe | Case | Result |
|---|---|---|
| T2 / T3 | Ties: an application of 175 on 13 Feb, when 87.50 was held | Refused |
| T2 / T3 | Ties: 100 on 14 Feb, the same day as the instalment | Accepted |
| T7 | A backdated 0.01 on the posting day, leaving 14 Feb at exactly 0 | Accepted |
| S1-S6 | Several receipts (40 on 14 Feb, 47.50 on 1 Mar): a return of 127.51 on 20 Feb | Refused |
| S1-S6 | The same: 127.50 on 20 Feb | Accepted |
| S1-S6 | The same: 0.01 on 25 Feb, when 0 was held | Refused |
| S1-S6 | The same: 47.50 on 1 Mar | Accepted |
| S7 / S8 | A zero refund on 28 Feb | Refused |
| S7 / S8 | A zero refund on 1 Mar | Accepted |
| B1 / L1 | A debit or a receipt dated before posting | Refused by the posted_on check |
| B2 / L2-L4 | Status after a late receipt: full application on 15 Jan (status applied), then an instalment backdated to 16 Jan | Status becomes partial_applied, remainder 87.50 |
| B2 / L2-L4 | Then a re-application on 15 Jan, when 0 was held | Refused |
| B2 / L2-L4 | Then a re-application on 16 Jan | Accepted, status applied, exhausted_on 16 Jan |
| MS3 / MS6 | One statement, earlier row seen: the timeline guard does see earlier rows of the same statement | Correct |

**Codex r5 S1 is closed.** The comparator comment, the stored comment, the rate-floor comment and the `tariff_id` comment now match the code.

## B1 (blocking): status-based checks are stale inside a multi-row INSERT

`z_project_deposit_status` is an AFTER INSERT FOR EACH ROW trigger, so it is queued until the end of the statement. Inside one `INSERT … SELECT/VALUES` with several rows, each row's BEFORE trigger reads `d.status` as it stood before the statement began. Every status guard is therefore blind to earlier rows of the same statement:

- `nothing after refunded/released`
- `a refund is pending` (on instalments, applications and returns)
- `a refund is already pending`

Results, all accepted as tally_app under `SET CONSTRAINTS ALL IMMEDIATE`:

- **MS7.** Two `refunded` events of 87.50 on a deposit that received 87.50 were accepted. The money is paid out twice, and the deposit ends `refunded`.
- **MS4.** `refunded` on 1 Feb, then `instalment_received` on 14 Feb, was accepted. The deposit is `refunded` and holds 175.
- **MS1.** `refund_initiated` of 87.50 on 1 Feb, then an instalment on 14 Feb, was accepted. The deposit ends `refund_pending` with a remainder of 175 against a refund notice of 87.50. This is exactly what the new rule is meant to stop: "a refund notice is dated on or after every receipt". The refund branch checks only events already recorded, and leaves later inserts to the refund-pending status check, which is stale here.
- **MS5.** A refund notice for 87.50, then a partial return of 50, was accepted. The remainder ends at 37.50 while the notice says 87.50.
- **MS2.** This one was refused only by accident, by `deposits_status_dates_check`, because an application after the refund made the projection leave `refunded`.

The cause is in the -06 design, which -15 re-issues. It is not new in r6. The round-6 guard still depends on it.

**Suggested fix (measure first):** in `enforce_deposit_event`, derive the three status facts from `deposit_events` rather than from `d.status`. A BEFORE ROW query sees earlier rows of the same statement, which MS3 and MS6 confirm. For example:

- refuse any event if a `refunded`/`released` event exists for the deposit;
- treat "pending" as `EXISTS refund_initiated`.

Battery cases: MS1, MS4, MS5 and MS7 as single statements. A mutation that restores `d.status` should be caught.

## Note (not blocking)

**N1.** In probe R3, a `refunded` dated 15 Feb was accepted after a `refund_initiated` dated 20 Feb: the payment is dated before its notice. No money is wrong, but the order of the dates is. A one-line check on the refunded/released branch (`effective_on >= the refund_initiated date`) would close it if wanted.
