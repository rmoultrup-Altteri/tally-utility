# Opus review — v5.4.2-26 r1 (collections decisions and field verification)

**Date:** 2026-11-27. **Reviewer:** Opus. **Verdict: not yet.**

## Integrity and reproduction

- md5s checked, all five frozen files match the brief; the brief matches `review-brief-26-r1.md5` (`43019dc4a3826fef1fac7b34d18b2e90`). **Executed.**
- Clone `rv26opus` from `tally`, TEMP revoked from PUBLIC, tally_app, tally_core; frozen patch strict-applied (`search_path=''`, `check_function_bodies=on`): rc 0; second run prints "already applied … nothing to do", rc 0. **Executed.**
- `battery-26-frozen-r1.sql` on the clone: "battery-26: all checks passed". **Executed.**
- Not run, by the brief: mutations, ci.sh, collections-26.sh (I ran my own two-session race instead, below).
- With -26 applied, the three earlier invariant functions the patch's closing block does not call (`assert_dispute_guard_invariants`, `assert_shortfall_guard_invariants`, `assert_suspense_pledge_guard_invariants`) all pass. **Executed.**
- tally: `has_database_privilege(tally_app|tally_core, 'tally', 'TEMP')` = f, CREATE on public = f, so R5's depth fences hold today. **Executed.**

Probes ran as tally_app under `app.user_id` = the battery's operator b1 unless stated, on the battery's own fixtures (prelude lines 1–224), in a rolled-back transaction except the race. Clone dropped at the end.

---

## B — blocking

### B1. A disconnection can be carried out under another customer's execute decision (A5 / F2 "for the order's customer"). Executed.

The design (F2) requires "an eligible, live `disconnect_execute` decision for the **order's customer** and location". The visit's key to its decision is `(collections_decision_id, tenant_id)`: it has no customer. `collections_act_check` compares only location and meter for a disconnect act. So once a location changes hands, the outgoing customer's execute decision cuts off the incoming customer.

Probe (tally_app can move a location: `UPDATE service_locations SET customer_id = c2 WHERE id = L1` was admitted as tally_app, executed):
1. eligible `disconnect_execute` decision for **c1** at L1, today: admitted;
2. L1 moves to c2;
3. eligible `disconnect_order` decision for **c2** at L1; disconnect order for c2 at L1, meter e1: admitted;
4. executed visit on c2's order citing **c1's** execute decision (serial and service point match, one photo): **ADMITTED**.

c2, with no execute decision of their own, is disconnected on c1's. Fix: pass the order's customer into `collections_act_check` and refuse `d.customer_id <> o.customer_id`, or give the visit a `customer_id` filled from the order and key the decision `(collections_decision_id, tenant_id, customer_id)`, as the other three act tables are. Add a battery check (the A5b/A5g pattern) and a mutation.

### B2. A blocked decision for a whole service location does not stop a disconnection: a meter-level eligible decision sits beside it, and both are live (C4, fail toward protection). Executed.

The subject key includes the optional meter, so `(L1, no meter)` and `(L1, meter e1)` are separate subjects, each with its own live decision. An act at L1/e1 may cite a decision with no meter (it covers any meter) **or** one naming e1. Nothing makes a location-wide blocked answer bind the meter-level subject.

Probe, all **ADMITTED**:
- blocked `disconnect_order` for L1 (no meter), `medical_hold` active and credited;
- eligible `disconnect_order` for L1/e1, the same day; disconnect order at L1/e1 citing it;
- blocked `disconnect_execute` for L1 (no meter), `medical_hold`; eligible `disconnect_execute` for L1/e1; the visit executed under the eligible one;
- the same for a notice: blocked notice for bill 01 at L1 (dispute), eligible notice for bill 01 at L1/e1, `shutoff_notice_sent` citing the eligible one.

A customer under a medical hold the core recorded is disconnected anyway. The battery's O7 treats "subjects that differ only by meter" as independent by design; under K-CCK (fail toward protection) that is the wrong reading. Options: refuse an act while any live non-eligible decision covers its subject (the location-wide one covers every meter), checked under both subjects' locks in a fixed order; or make the meter-level subject legal only when no location-wide decision exists for that act and location (and the reverse). The lock order then needs a rule for taking two subject locks (location-wide first).

### B3. Under REPEATABLE READ an order can be cancelled after a field visit executed it (F4d). Executed (two sessions).

The order's status update is not pinned to READ COMMITTED ("An order's status update takes only its own row"). The visit's `FOR SHARE` lock is lock-only, so a REPEATABLE READ updater whose snapshot predates the visit is not refused when the visit commits, and `enforce_disconnect_order`'s `EXISTS (… outcome = 'executed')` reads that old snapshot.

Run: open order at L5 (c1, meter e7) with eligible order and execute decisions, committed. Session A (tally_app): `BEGIN ISOLATION LEVEL REPEATABLE READ; SELECT status …; pg_sleep(4); UPDATE service_orders SET status = 'cancelled' …; COMMIT`. Session B starts 1.5 s later (READ COMMITTED) and inserts the executed visit, which commits at once. A: `UPDATE 1`, `COMMIT`. Final state: **order `cancelled`, visit `executed`, matched**. That is exactly the state the design's "Built" note says cannot happen ("never as a cancelled order with an execution on it", CR8/CR8b), and CR8b only runs at READ COMMITTED.

Fix: in `enforce_disconnect_order`, refuse a disconnect order's status change outside READ COMMITTED (25000, as `collections_subject_lock` does), or take the subject lock of the order's decision there too. Add CR8c at REPEATABLE READ.

### B4. A supervisor's approval can be stamped with a user of another utility, against R-12 and the impersonation ruling. Executed.

Ryan's 2026-11-05 ruling (R-12): every link between two utility tables is a two-column key with `tenant_id`. Ryan's 2026-11-07 ruling: Tally staff act in a utility **as that utility's Tally User**, never as their own user row ("the keys would refuse their stamps"). -24 and -25 key every "by" column as `(x_by, tenant_id) → users (id, tenant_id)`. -26 keys `service_order_field_approvals.approved_by`, `collections_decisions.created_by` and `service_order_field_visits.created_by` as `→ users (id)` only.

Probe: a `platform_admin` user belonging to tenant a2; session `app.user_id` set to them; a `no_evidence` approval of tenant a1's disconnect order: **ADMITTED**, `approved_by` = the a2 user (`approver_tenant` a2, `approval_tenant` a1). `session_is_supervisor()` passes any platform admin without asking which utility they belong to.

D9-1's override then names someone who is not a supervisor of the utility. Fix: composite keys `(approved_by, tenant_id)` and `(created_by, tenant_id)`; make `approved_by` NOT NULL (it is stamped, so the null leg is never legitimate). Whether `session_is_supervisor()`'s platform-admin branch should still pass here once the Tally User exists belongs to the 11-07 ruling's implementation. With the composite key, a platform admin's own row is refused anyway.

---

## S — should fix

### S1. A second late fee on a bill (Pecan Flat, every month) moves the bill's stage backwards. Executed.

Ryan 2026-11-22: a city may take the penalty every month a bill stays unpaid. -26 records the second fee correctly (a new late_fee decision superseding the first, a second charge, a second `late_fee_applied`). But the fixed mapping moves the stage regardless of where the bill is:

```
late_fee_applied     current           -> late_fee_assessed
shutoff_notice_sent  late_fee_assessed -> shutoff_warning
late_fee_applied     shutoff_warning   -> late_fee_assessed
```

A bill whose shutoff notice was sent then reads as though it had not been, for every reader of `dunning_stage` (`idx_invoices_dunning`, the delinquency check near tu.sql:18290) and for the core's own inputs. Settle it by rule, recorded: a step moves the stage only forward in the progression the column's own comment states, so a repeat late fee after `shutoff_warning` logs with `new_stage = previous_stage`. Or `late_fee_applied` moves the stage only from `current` or `reminder_sent`. Add the repeat to the battery.

### S2. The gate is keyed on one label of a late fee (guard-the-act-not-the-label). Executed.

Only `adhoc_charges.charge_type = 'late_fee'` needs a decision. Both of these were **ADMITTED** with no decision:
- `adhoc_charges` with `charge_type = 'penalty'`, `triggered_by_invoice_id` = bill 01;
- an `invoice_line_items` row with `charge_type = 'late_fee'` on a draft bill (the "penalty on the next bill" shape that -30's `in_late_penalty_base` is computed for).

Changing a charge's type after insert is closed: -23's `enforce_adhoc_charge_immutable` freezes `charge_type`. Either gate every late-penalty representation (a `late_fee` bill line and a `penalty` charge triggered by a bill cite a late_fee decision), or state in the patch and in an application contract that a late fee is recorded only as an `adhoc_charges` `late_fee`, and refuse the other shapes.

### S3. An execution can be dated before its order existed, under an old decision (C3h's purpose). Executed.

`arrived_at` and `evaluation_date` are both the caller's, and C3j bounds only the future. Probe, all **ADMITTED**: an eligible execute decision for L2 evaluated today−5 (valid today−5 only); an order decision and the order recorded today; an executed visit with `arrived_at = now() − 5 days`. The order did not exist on the day its execution claims. C3h says an execute decision holds for its own day because "no relying on an older evaluation at execution". Backdating the arrival defeats that.

Fix, without needing the true arrival time (the field tool syncs late): refuse an arrival before the order's `created_at` or after `now()`, and refuse an execution whose decision was recorded after the arrival (`d.created_at > arrived_at`: the decision must exist before the crew acts). The same "decision recorded before the act" bound fits a charge's `effective_date` and an event's `event_date`.

### S4. A superuser history load in replica mode leaves `do_not_disconnect` false under an active protective enrollment, and nothing can repair it. Executed.

`enrollment_recompute_dnd` is enabled ORIGIN only (`tgenabled = 'O'`), while -26's fence is ALWAYS. As the owner with `session_replication_role = replica`, inserting an active `military_deployment_scra` enrollment left `do_not_disconnect = false`; a direct `UPDATE customers SET do_not_disconnect = true` as superuser was then refused by `[E4]`. The flag disagrees with the enrollments, the state the precondition forbids, and the only way out is to touch the enrollment again outside replica mode. Since -26 makes the flag "the enrollments' alone", `ALTER TABLE customer_program_enrollments ENABLE ALWAYS TRIGGER enrollment_recompute_dnd` belongs in this patch, with a battery check.

### S5. -26 adds no invariant function, and its closing block skips three that exist. Executed (the three pass today).

-23, -24 and -25 each add an `assert_*_guard_invariants()` that pins their triggers (ALWAYS), grants and fences, so a later patch that drops or loosens them fails at apply time. -26 has none: nothing outside its battery would notice a later patch granting UPDATE on `collections_decisions`, disabling `b_enforce_field_visit` or `a_enforce_dunning_stage_projection`, or re-adding a writer of `dunning_stage`. Its closing DO block also omits `assert_dispute_guard_invariants`, `assert_shortfall_guard_invariants` and `assert_suspense_pledge_guard_invariants`. Add `assert_collections_guard_invariants()` (ALWAYS flags, grants, the RLS policies, the composite keys, the unique indexes) and call all eleven or twelve.

### S6. A voided bill counts as "issued" for a decision, and an act never rechecks its bill. Executed (the helper) / predicted (the void path).

C3b uses `is_invoice_issued()`, which is true for every status except draft and held: `is_invoice_issued('void') = t`. A notice, late-fee or referral decision on a voided bill passes C3b, and the act check never reads the bill's status, so a bill voided after its decision can still take a late fee or a shutoff notice. I could not void a fixture bill outside `void_invoice()` (CI-012 refused the direct write), so the end-to-end path is predicted. Refuse `void` in C3b, and in the act check for a bill act.

---

## N — notes

- **N1. A logged disconnection or scheduled shutoff can sit on any bill of the customer.** Executed: `disconnected` and `shutoff_scheduled` events for an L1 execution and order were admitted on bill 02 (consolidated, no location). The design's "Open for the build" 3 accepts the tie through the decision. With B1 fixed it stays within one customer. If a bill names a location, requiring it to equal the decision's would be cheap.
- **N2. An eligible disconnect decision and order are admitted for a customer whose `do_not_disconnect` is true.** Executed (SCRA enrollment, flag true, eligible order decision and order admitted). This is consistent with "the database checks the record, never the evaluation", since protective programs are not all absolute. It is worth one sentence in the decision table's comment or an application contract, because the flag is now the database's own fact.
- **N3. Lifting a protection is still an operator's act.** Battery E4e shows the operator b1 cancelling an SCRA enrollment, which clears `do_not_disconnect`. R-38 attachment 2 (cited by -26 for approvals) says lifting a protection needs a supervisor and evidence. The enrollment table is earlier work, but E4 makes it the only path to the flag. Flag for the board.
- **N4. `credit_reporting` has no gate.** -25's `dispute_blocks` lists it as an act a dispute stops. -26's acts do not include it, and no table records it today. When one does, it needs a decision act. Residual-worthy.
- **N5. An eligible window has no upper bound** (a ten-year `disconnect_order` window was admitted). That is the core's (R4). Noted only because C3h bounds execute decisions and nothing bounds orders.
- **N6. Migration P7 tests one direction only** ("protected with no enrollment"). The precondition's `IS DISTINCT FROM` also catches "enrolled but not flagged", which has no fixture (every-branch-and-stated-default-tested).
- **N7. Writable CTE and multi-row inserts of two first decisions for one subject are refused at `[C4a]`.** Executed. Good; worth keeping as a battery check, since it rests on the trigger seeing the earlier row of the same statement.
- **N8. Earlier roles.** No mirrored function inserts `adhoc_charges`, `service_orders` or `dunning_events` or writes `dunning_stage` (grep of tu.sql). tally_void's void path updates `adhoc_charges` without touching `collections_decision_id` or `triggered_by_invoice_id`, so -26's column-scoped trigger does not fire for it. The invoice fence fires only on `UPDATE OF dunning_stage` and on insert. I found no path of tally_seal, tally_close, tally_void or tally_dispute that -26 refuses. Predicted from code and grants.
- **N9. Residuals.** R1–R5 are not blocking as written. R5 holds (TEMP and CREATE revoked on tally). B2 and S3 are not residuals: they are paths around C4 and C3h.
- **N10. Tests missing for the above:** another customer's execute decision (B1), location-wide blocked against meter-level eligible (B2), CR8c at REPEATABLE READ (B3), an approver from another tenant (B4), the repeat late fee's stage (S1), the replica-mode enrollment (S4).
