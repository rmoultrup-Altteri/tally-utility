# Opus review — v5.4.2-26 r2 (collections decisions and field verification)

**Date:** 2026-11-27 (UTC 2026-11-28 on the clone). **Reviewer:** Opus. **Verdict: not yet.**

Two blocking items. B1: a disconnection the field tool syncs after the core has re-evaluated can never be recorded. B2: an order can still be carried out at premises that have passed to another customer. Five should-fix items. Most of round 1 is fixed, and the new lock (item 2) holds under a real race.

## Integrity and reproduction

- All seven frozen md5s match the brief. The brief matches `review-brief-26-r2.md5` (`206906fbd83e9b51edadf959afc2bb05`). The live patch `sql/v5.4.2-26-collections-decisions.sql` has the same md5 as the frozen copy. **Executed.**
- I cloned `rv26opus` from `tally` and revoked TEMP from PUBLIC, tally_app and tally_core. The frozen r2 patch strict-applied (`search_path=''`, `check_function_bodies=on`) with rc 0. A second run printed "already applied … nothing to do", rc 0. **Executed.**
- `battery-26-frozen-r2.sql`: "battery-26: all checks passed". `battery-21-for-26-frozen-r2.sql` with -26 applied: "battery-21: complete", W1 passes. **Executed.**
- `collections-26-frozen-r2.sh rv26opus`: CR1–CR8d, 13 PASS (CR8c and CR8d included). **Executed.**
- Not run: mutations, fill-manifest and ci.sh (the brief forbids them), and `migration-26.py` (it creates fixed-name databases). I read migration P5b, P5c and P7b; the P7b fixture closes my round-1 N6.
- Probes ran as tally_app under `app.user_id` = b1 (the battery's operator) unless stated, on the battery's prelude fixtures. Single-transaction probes ended in ROLLBACK. The late-sync probe (B1) and the two races committed rows on my clone, so I rebuilt the clone between probe sets. Clone dropped at the end, container temp files removed.

## Round-1 findings, item by item (plan items 1–15)

| # | Finding | Status |
|---|---|---|
| 1 | Execution under another customer's decision | **Partly fixed.** The decision must now be the order's customer's (A5; battery R1c). But the order's own customer can still be cut off at a location that has passed to someone else: **B2**. |
| 2 | Location-wide block vs meter-level eligible | **Fixed.** Battery R2b/d/e/g pass. I added an execution case (E2 refused at A10, E4 admitted when only another meter is blocked) and a two-session race (below, N1). Side effect: **S3**. |
| 3 | Cancel after execution under REPEATABLE READ | **Fixed** (F4f). CR8c and CR8d reproduced. |
| 4 | Multi-row dunning inserts | **Fixed.** R4a–d pass. Concurrency is sound: N2. |
| 5 | Actor links not tied to the utility | **Fixed.** Composite keys on `created_by` and `approved_by`. A platform administrator approving as themselves is refused 42501 `[F3a]` (P8, executed). Forward note: N4. |
| 6 | Repeat late fee or reminder moves the stage back | **Partly fixed.** Fixed on the ladder. Off the ladder, a reminder dated 2020 still takes a written-off bill back into collections: **S4**. |
| 7 | Gate keyed on one label | **Partly fixed.** `penalty` charges and `late_fee`/`penalty` lines are gated. The ledger and repeat billing of one charge are not: **S1**. |
| 8 | Surplus approval links | **Fixed** (F3e; battery R8a, R8b). An approval is still checked for its own order and kind (F3d). I found no way round. Predicted. |
| 9 | Execution backdated before its order | **Partly fixed.** The decision leg holds. The order leg reads a `created_at` the caller writes: **S5**. The new bound also makes a late sync unrecordable: **B1**. |
| 10 | Replica-mode load leaves `do_not_disconnect` behind | **Fixed** (battery R10). N8. |
| 11 | No invariant function | **Fixed.** It also calls all twelve earlier invariant functions. Remaining gaps: N5. |
| 12 | Void bill counts as issued | **Fixed** (C3b, A11; battery R12a–c). |
| 13 | Blank captured values | **Fixed** (F2e alnum; battery R13). |
| 14 | Disconnection logged on one bill only | **Fixed** (unique per decision and bill; R14a/b). It also reaches a draft bill: N3. |
| 15 | Race and mutation verdicts | Read only (the brief forbids running the runner). The runner now checks for a lock wait and session A's success before counting a catch. Predicted fixed. |

My own round-1 items map as follows. B1→1, B2→2, B3→3, B4→5, S1→6, S2→7, S3→9, S4→10, S5→11, S6→12, N1→14. N2–N5 are now R7 and are fine as residuals. N6 is closed by migration P7b. N7 is tested.

---

## B — blocking

### B1. A disconnection the field tool syncs after the core has re-evaluated can never be recorded. Executed (committed, three transactions with real time gaps).

An execution must cite a decision that is **live now** (A4: nothing supersedes it). Since r2 it must also cite one **recorded before the arrival** (F2f). The core writes a fresh execute decision every day (C3h: an execute decision holds for its own day only) and re-evaluates when facts change. So when the crew acts at 10:00 under decision X and the core supersedes X at 11:00, a sync at 12:00 has no decision it can cite:

```
L3 morning execute decision LX (eligible, today)          ADMITTED   created 01:33:41.23
   crew arrives                                                       arrived 01:33:42.74
L4 the core re-evaluates the same day, still eligible LX2 ADMITTED   created 01:33:44.25
L5 sync citing LX   REFUSED 23514 … decision … is superseded — the act cites the live decision for its subject [A4]
L6 sync citing LX2  REFUSED 23514 … arrived 01:33:42.74, before … its decision (01:33:44.25) was recorded … [F2f]
```

Nothing can repair this. Any new decision is recorded after the arrival, so F2f refuses it. In r1 the same-day case could cite LX2; F2f removed that. The next-day case was already blocked in r1 by A4 plus A6 (the decision's window). So a field tool that syncs after the next daily evaluation, which D3A-1's external tool will often do, leaves gas off with an open order and no execution. No `disconnected` step can be logged either, because A8 needs the visit. The record shows a connected customer whose gas is off. That is the opposite of failing toward protection: reconnection, billing and the customer's protections all read that record.

Fix: judge an execution **as of its arrival**, which F2f already bounds to the window between the decision's recording and now:
- A4 for an execution: no decision superseding the cited one was **recorded at or before `arrived_at`**.
- A10 likewise reads the decisions live at `arrived_at`.

A block recorded after the crew acted then does not erase the record of what they did. The cost is that the caller's arrival time decides whether a later block applies. The arrival is already the caller's fact, bounded below by the decision's stamped `created_at`, and that is the same trust F2f extends. Add a race: X live, the crew arrives, X superseded, then sync. Two cases: the successor eligible, and the successor blocked. The blocked case should still be recorded, because the act happened before the block.

### B2. An order is carried out at premises that have passed to another customer, under the old customer's own decisions. Executed.

Item 1's fix compares the decision's customer with the order's. Both can belong to the outgoing customer while the premises now belong to someone else:

```
T1 c1's order decision and execute decision at L1, c1's disconnect order (L1, meter E1)   ADMITTED
T2 L1 passes to c2 (UPDATE service_locations SET customer_id = c2, as tally_app)       ADMITTED
T3 c1's order executed at L1 (SN-E1 / L1 matched, photo)                                ADMITTED
```

At an unmetered location (L4) the same run went through a supervisor's mismatch approval and was ADMITTED too. The new occupant c2 is cut off for c1's debt. The visit guard reads the order but never checks that the order's location still belongs to the order's customer. C3c checks that fact only when the decision is written.

Fix: in `enforce_field_visit`, for an execution, refuse when `service_locations.customer_id` for `o.location_id` is not `o.customer_id`. Read that row FOR SHARE (lock order step 2, after the order's row), so a concurrent transfer either waits for the visit or is seen by it. A battery check and a race (a transfer against an execution) go with it. Requiring the open disconnect order to be cancelled at transfer is an alternative; it belongs to whoever owns `service_locations`.

---

## S — should fix

### S1. A late fee still reaches the customer without a decision, or more than once under one. Executed.

The gate covers `adhoc_charges` (late_fee, penalty) and `invoice_line_items` (late_fee, penalty). Three paths remain, all ADMITTED as tally_app:

- **P1, the ledger.** `account_ledger` rows with `transaction_type = 'late_fee'`: one with `reference_type 'invoice'` and bill 01, one with `reference_type 'manual'`, no decision, $25. tally_app holds INSERT on `account_ledger`, and nothing in -26 reads that table.
- **P2c, the same charge billed twice.** One gated $5 charge (CLF) billed as a `late_fee` line on draft bill 04 ($5) and again as a `penalty` line on draft bill 06 at **$500**. `invoice_line_items` has no uniqueness on `adhoc_charge_id`, and the trigger checks neither the amount nor whether the charge was already billed.
- **P2e, a void charge billed.** A third line billed CLF after CLF was voided (`status = 'void'`). The A8 log line refuses a void charge (R15); the bill line does not.

On which roles write these tables (`triggers-run-as-every-writer`): only tally_app and the owner write `invoice_line_items`. No mirrored function inserts into it, and no earlier owner role holds a grant on it. tally_app and tally_void write `account_ledger`. Fix:
- A `late_fee` ledger row must reference (`reference_type 'adhoc_charge'`) a standing gated charge, or be refused.
- A late-fee or penalty line must bill a standing charge (not void, waived or void-pending-rebill), at the charge's amount, with at most one such line on a bill that is not void.
- Check -23's `billed_on_line_item_id` link. Using it (one line per charge) may be the cheapest way to enforce "once".

### S2. The order's own decision turns blocked, and the order is executed anyway. Executed.

```
P4a order decision O1 for L1 (eligible); disconnect order SO1 at L1/E1                 ADMITTED
P5a O1 superseded: blocked, medical_hold                                               ADMITTED
P5b execute decision X1 for L1 today (eligible)                                        ADMITTED
P5c SO1 executed under X1 while the live order decision is blocked                     ADMITTED
```

A10 binds only decisions for the same act. The record then holds a live, blocked `disconnect_order` decision for the location (a medical hold), and an execution of an order resting on the decision it replaced. Item 2 rests on the principle that a block on the record binds acts that contradict it. By that principle, the order's live decision being blocked should stop its execution, or else the order should be cancelled, and the database should hold that. Fix:
- At execution, refuse while the live `disconnect_order` decision covering the order's location and meter is not eligible.
- That decision's subject lock (act `disconnect_order`) is a second lock. Take it before the execute decision's, and add that to the lock-order rule.
- If this is judged the core's alone (the execute decision is the fresh evaluation), say so in R7.

### S3. A removed meter's last block binds its location forever, and the core can lift it only by writing a backdated decision. Executed.

At L5, meter E5 came out on April 1:

```
P7a E5 at L5 blocked, evaluated 2026-03-30 (medical_hold)                ADMITTED
P7b L5 location-wide eligible today; P7c E7 (the meter there now) eligible today   ADMITTED
P7d an order naming no meter at L5     REFUSED [A10] (E5's block)
P7e the core lifts E5's block today    REFUSED [C3e] meter E5 is not deployed at L5 on 2026-11-28
P7f … by an eligible decision dated 2026-03-31, already expired          ADMITTED
P7g then the order goes through                                          ADMITTED
```

A10 counts every meter's latest decision at the location. A location-wide act (an order or decision naming no meter) therefore stays blocked by a meter that is no longer there. C3e lets the core write a successor only for a day the meter was deployed, so the only way out is an "eligible" record for a past day the core never evaluated. Fix:
- A10 counts a meter-level decision only for a meter deployed at the location on the act's date.
- Or, the less good option, C3e lets a successor for a removed meter carry today's date.

### S4. Off the ladder, an ungated reminder still moves a bill back into collections. Executed.

```
P3a bill 07 written off                                   current > written_off
P3b a reminder dated 2020-01-01 on the written-off bill   written_off > reminder_sent   (bill now at reminder_sent)
```

Item 6 named "even a reminder dated 2020" as the harm. On the ladder it is fixed. From `written_off`, `resolved` or `payment_plan`, any escalation step moves the bill to its own stage, including `reminder_sent`, which needs no decision. Battery R6f does this deliberately (resolved, then a reminder). A resolved or written-off bill then reads as in active collections to every reader of `dunning_stage`, on the strength of a step no decision stands behind. A late-recorded step does the same (R6). The brief asks what an escalation step should do from these stages. My answer:
- Only a **gated** step (a decision stands behind it) moves a bill off `payment_plan`, `resolved` or `written_off`.
- An ungated reminder logs with `new_stage = previous_stage`.
- A broken plan resuming collections is R3's (`payment_plan_broken` moves nothing today).

This is a rule of the same kind as item 6, settled by rule and reversible.

### S5. The order leg of F2f reads a timestamp the caller writes. Executed.

```
P4b disconnect order SO1 inserted with created_at = 2020-01-01   ADMITTED
P4c UPDATE service_orders SET created_at = 2019-01-01            ADMITTED (created_at now 2019-01-01)
```

`service_orders` has no stamp trigger. tally_app holds UPDATE on every column, and F4a does not freeze `created_at`. So "no earlier than its order was recorded" is the caller's word. Only the decision leg (stamped by `stamp_log_created_at`) binds, and the check is weaker than its label and its mutation M147 suggest. Fix: for a disconnect order, stamp `created_at` at insert (except for a superuser, as -19 does) and add it to F4a's written-once list.

---

## N — notes

- **N1. The item 2 lock holds under a real race. Executed.** Session A inserted a blocked location-wide `disconnect_order` decision at L6 and held for 4 s. Session B, 1.5 s later, inserted an order for meter E8 under E8's eligible decision. B waited until A committed (B 46.93 to 49.43; A committed 49.42), then was refused `[A10]` naming A's decision. A decision written concurrently with an act does not escape it: both take the same location lock. The races file has no leg across two meter subjects; this one is worth adding as CR9.
- **N2. Ordering by `record_seq` is sound under concurrency. Executed.**
  - At READ COMMITTED, the second writer waits on the bill's row lock, then reads the first writer's event under a fresh snapshot, and its `nextval` comes after (CR6 and CR6b).
  - Ungated steps take no subject lock, so no READ COMMITTED pin applies to them. I ran A at REPEATABLE READ (snapshot taken, sleep, `reminder_sent`) against B (`payment_plan_created`, committed meanwhile). A got 40001 at the bill's `FOR NO KEY UPDATE`, because `dunning_move_stage` rewrote the bill, even for a repeat step with an unchanged stage. Final chain: `payment_plan_created: current>payment_plan` only.
  - A step that moves no stage leaves the bill untouched, and the stage read ignores such steps. Safe.
- **N3. Dunning steps reach a draft bill. Executed.** A `reminder_sent` on draft bill 04 moved it to `reminder_sent` (P3c). A `disconnected` step under an execute decision was logged on draft 04 and moved it to `disconnected` (P6a). Requiring an issued bill for any dunning step (`is_invoice_issued`, not void, for a live act) is cheap and matches C3b.
- **N4. The approver (item 5). Predicted, plus P8 executed.** Nothing in -26 relied on a platform administrator approving. Until the Tally User exists (2026-11-07 ruling, "not built"), Tally staff cannot approve at all. A utility with no active tenant_admin cannot approve a mismatch or no-evidence execution, which fails closed. Two forward constraints for whoever builds `users`:
  - F3a requires `role = 'tenant_admin'`. The Tally User must carry that role, or F3a must name its marker. Condition 4 of that ruling (it does not count as the utility's own staff) then applies to every count of supervisors.
  - `session_is_supervisor()` still passes any platform administrator for the other gates that call it. The two supervisor tests now disagree.
- **N5. The invariant (item 11). Read, predicted.**
  - It pins what -26 built: its triggers (ALWAYS), constraints, unique indexes, table and sequence grants, row-security flags, and function bodies by md5. The policy text is covered generically by `assert_tenant_isolation_invariants`.
  - It does not pin the earlier objects -26 now depends on. Chief among them: `dunning_events`' append-only trigger and its lack of UPDATE for tally_app, which matter now that the events are the stage's authority. Also `recompute_do_not_disconnect`'s body (the flag's only writer), `stamp_log_created_at` and `is_invoice_issued`.
  - The mutation runner drops the closing call only for behavioural mutations, and the battery's R11a still runs the invariant after the named checks. So a behavioural mutation that only the invariant catches still shows as missed. Dropping the call hides nothing.
- **N6. "Decision recorded before the act" for executions only. Agree.** A decision may carry a past evaluation date (C3j bounds only the future), so for a charge or a step the bound would add little. What is left: a `shutoff_notice_sent` dated before its decision was recorded is admitted. That is worth one sentence in the core's contract (a notice is recorded after its decision).
- **N7. battery-21 now needs -26.** Acceptable: ci.sh runs it with -26 pending, and after the mirror -26 is in the base. The cost is that -21 can no longer be re-verified alone on a pre-26 base. Say so in battery-21's header.
- **N8. `enrollment_recompute_dnd` ENABLE ALWAYS. Predicted.** I found no load path that now misbehaves. A replica-mode load recomputes, and a logical-replication subscriber recomputes from the enrollment, so the replicated customer row then agrees with it. A data-only restore with triggers disabled bypasses both, as before.
- **N9. `penalty` now means a late fee.** Every `penalty` charge needs a late_fee decision. That is fine if the vocabulary means a late penalty only (`damage_fee` and others exist for the rest). Put one sentence in the column comment or an application contract, so a utility's tampering penalty is not filed under it.
- **N10. A late penalty under a neutral label passes** (P2f: an `adhoc` line described "Late payment penalty", ADMITTED). The schema cannot close a label it does not know. It needs a contract sentence: a late penalty is recorded only as a gated charge.
- **N11. Residuals.** R1 (extended), R6 and R7 are not blocking as written. R6 is narrower than S4: S4 is about ungated steps moving a bill off a closing stage, not about recording order. R7 stands, with S2 if that is judged the core's.

## Tests the r2 battery should add

- B1: a late sync after a same-day and after a next-day supersession, with an eligible and with a blocked successor.
- B2: an execution after a location transfer, plus its race.
- S1: a ledger late fee; one charge on two lines; a line at another amount; a line for a void charge.
- S2: an execution while the order decision is blocked.
- S3: a removed meter's block.
- S4: a reminder after written-off or resolved.
- S5: an order's `created_at` written at insert and by update.
- N1 as race CR9.
- N3: a step on a draft bill.
