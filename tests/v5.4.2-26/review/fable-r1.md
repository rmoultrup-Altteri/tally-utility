# Fable review: v5.4.2-26 r1 (collections decisions and field verification)

**Date:** 2026-11-27. **Verdict: not yet.**

One blocking item (B1), found by running it: under REPEATABLE READ a disconnect order that a crew has already executed can be cancelled. The rest of the patch does what its design says. Seven should-fix items follow, three of them consequences of rulings made after the draft (the monthly late penalty, the same-utility keys, the Tally User).

## What I checked and how

- **Hashes:** the five frozen files and the brief match their md5s.
- **Clone:** `rv26fable` from `tally`, TEMP revoked from PUBLIC, `tally_app`, `tally_core`; the frozen patch applied strictly (`search_path=''`, `check_function_bodies=on`), twice (second run: "already applied"). Dropped at the end; `/tmp/rv26fable-patch.sql` removed from the container. No repo file touched but this one.
- **Reproduced:** `battery-26` 202 PASS, 0 FAIL, rolled back. `collections-26.sh rv26fable` 11 PASS (CR1 to CR8b).
- **Not re-run:** `migration-26.py` (it clones `ci_base`), `mutations-26.py`, `ci.sh` (forbidden or out of scope). I read the migration's stop conditions against the patch's precondition block; they agree.
- **Probes:** the battery's own fixtures (its first 226 lines) followed by my statements, as `tally_app` under `app.user_id`, in one rolled-back transaction, except B1, which needs two committed sessions. Every item says **executed** or **predicted**.
- **Lessons read:** the index of `sql/PATCH-LESSONS.md` and the eight sections the brief names.

---

## B — blocking

### B1. Under REPEATABLE READ, an executed disconnect order can be cancelled (executed)

**What it does.** The design promises that cancelling an order while a crew records its execution "resolves one way or the other, never as a cancelled order with an execution on it" (design, "Built"; the patch's [F4d]). That holds only at READ COMMITTED. An order's status update takes no subject lock, so nothing pins its isolation level, and `enforce_disconnect_order` decides "has a visit executed this order?" with a plain read. In a REPEATABLE READ (or SERIALIZABLE) transaction that read uses the transaction's old snapshot and does not see a visit committed since.

**Run (two sessions, committed, on the clone):**

```
A (tally_app): BEGIN ISOLATION LEVEL REPEATABLE READ;
A:             SELECT count(*) FROM service_order_field_visits WHERE outcome='executed';   -- 0, snapshot taken
B (tally_app): INSERT executed visit of SO1 (matched, evidence, eligible execute decision); -- commits
A:             UPDATE service_orders SET status='cancelled' WHERE id = SO1;                 -- UPDATE 1
A:             COMMIT;
result:        order_status = cancelled, executed_visits = 1
```

No lock wait is even needed: B's `FOR SHARE` does not change the order's row, so A gets no serialization failure. The record then says the service was cut on an order the utility cancelled.

**Why the tests miss it.** CR8b races the same pair at READ COMMITTED only. CR7 proves the isolation pin for a decision and for an act, not for an order's status update, which the header's lock rule exempts ("An order's status update takes only its own row").

**Suggested fix (predicted, not measured).** In `enforce_disconnect_order`'s UPDATE branch, when a disconnect order's status changes, refuse outside READ COMMITTED with 25000, as `collections_subject_lock` does. The row lock the UPDATE already holds then orders it against the visit's `FOR SHARE`, and the read that follows is fresh. Add the leg to the races (CR8c: the snapshot taken before the visit commits) and a mutation that removes the pin. The completion direction ([F4b]) is safe as it is: a stale read can only refuse.

---

## S — should fix

### S1. A repeated late fee, or any later reminder, moves a bill's stage backwards (executed) — needs Ryan's call before the mirror

**What it does.** The stage is "the latest stage-moving event's", by a fixed mapping with no order. Ryan's ruling of 2026-11-22 makes a late penalty every month normal for a city on the full-amount base (Pecan Flat). The patch can record the second and third fee: a new decision supersedes the last, each takes one charge and one `late_fee_applied` line. But each one resets the bill's stage to `late_fee_assessed`, whatever it was.

**Run:** bill 01 taken to `shutoff_warning`, then `shutoff_scheduled`; a late fee applied: stage is `late_fee_assessed`. A second fee the same day (new facts): admitted, two late-fee charges on the bill. Then a plain `reminder_sent`: stage `reminder_sent`. Then `resolved`: stage `resolved`. A reminder dated 2020-01-01 also moves the stage (the stage follows insertion, not `event_date`).

**Why it matters.** A bill whose service is disconnected shows `late_fee_assessed` the next month. `idx_invoices_dunning`, the column's old comment ("progresses: current → … → disconnected") and `deposit_refund_trigger_state` all read the stage as a position. The 2026-11-22 ruling notes the monthly penalty "mostly reaches customers whose cut-off is held back", so this is the common case, not a corner.

**Options, briefly.** (a) Keep "latest event" and say so in the column comment and an application contract: readers who want "was it ever disconnected" read the events. Cheapest; nothing to change but words and a test that pins the behaviour. (b) A late fee and a reminder move the stage only forwards (a rank per stage; a repeat fee on a bill past `late_fee_assessed` logs and moves nothing). Small change to `collections_dunning_stage`'s use; changes what the column means. I lean to (b), because the patch's purpose for this column is that the database's answer can be trusted, and a regressing answer cannot be. Either way the battery needs the repeated-fee fixture (the brief's own question has no test: `every-branch-and-stated-default-tested`).

### S2. One disconnection can be logged on one bill only (executed)

**What it does.** `dunning_events_one_per_decision` allows one dunning line per decision. A disconnect order's and an execution's decisions name a location, not a bill, and there is one live decision per location and one executed visit per order. So when a customer owing three bills is disconnected, exactly one of the three bills can receive `shutoff_scheduled` and `disconnected`; the others can never reach those stages.

**Run:** execution of SO1 logged as `disconnected` on bill 01: admitted. The same on bill 02 (same customer, same execution): refused, 23505 `dunning_events_one_per_decision`. `shutoff_scheduled` on bill 02 under the same order decision: refused likewise.

Nothing ties the one bill chosen to the debt the disconnection rested on either (any bill of the customer passes). **Suggested:** for the three log lines (`late_fee_applied` excepted, since a late fee has one bill), make the key one line per decision *and bill*; or state that a disconnection is logged on one bill by design and what the other bills' stages mean.

### S3. An execution can "capture" blanks, and a supervisor can approve a blank visit (executed)

**What it does.** [F2e] requires only that the two captured values are not NULL. CI-071's failure is "captured-versus-expected pair not recorded". With `upper(btrim(…))` on both sides, an empty string equals a string of spaces.

**Run:** an aborted visit on SO5 capturing `''` and `''`: admitted. A supervisor's mismatch approval naming it: admitted. An execution capturing `''` and `' '`, no evidence, under that approval and a no-evidence approval: admitted. The disconnection is executed with nothing captured and no photo.

**Suggested:** [F2e] requires at least one alphanumeric character in each captured value (lesson `blank-checks-whitelist-alnum`), and [F3b] requires the approved visit to have captured both.

### S4. The user links are not tied to the utility, and a platform administrator approves as themselves (executed)

**What it does.** The brief says "composite keys with `tenant_id` throughout (R-12)". Three links are single-column: `collections_decisions.created_by`, `service_order_field_visits.created_by`, `service_order_field_approvals.approved_by`, each `REFERENCES users (id)`. -24 and -25, mirrored after the 2026-11-05 ruling, tie theirs (`disputes_created_by_fkey (created_by, tenant_id)`, `agency_pledges_recorded_by_fkey`, and so on).

**Run:** a `platform_admin` user whose row belongs to tenant T2 approves a T1 order: admitted; `approver tenant = order tenant: false`.

**Why it matters now.** Ryan's 2026-11-07 ruling: Tally staff act in a utility through its Tally User, so every "who did it" names a user of that utility. [F3a]'s "tenant_admin or platform administrator" (the -13 meaning) lets a Tally employee approve a disconnection directly under their own row, which is the thing that ruling replaces. **Suggested:** tie the three links with `tenant_id` now (additive, the tables are new and empty; later it is part of the 273-key patch). That makes the direct platform-admin approval fail on the key, which is the ruled behaviour; if that is unwanted until the Tally User exists, say so as a residual. The Tally User itself is not built and is not -26's to build.

### S5. A history load leaves a protected customer unprotected, with no way to set the flag (executed)

**What it does.** -26 makes its fence on `customers.do_not_disconnect` `ENABLE ALWAYS`, but the trigger that is now the flag's only writer, `enrollment_recompute_dnd`, is an ordinary trigger (fires in origin sessions only).

**Run (owner, `session_replication_role = replica`):** an active `regulatory_moratorium` enrollment inserted: `do_not_disconnect` stays false. The direct correction, `UPDATE customers SET do_not_disconnect = true`: refused [E4], for the superuser too.

The brief asks about a superuser history load; this is the one place it fails away from protection. **Suggested:** `ALTER TABLE customer_program_enrollments ENABLE ALWAYS TRIGGER enrollment_recompute_dnd` in -26. Related, **executed**: flipping `program_types.is_disconnect_protective` (owner only) leaves existing customers' flags stale, again with no direct repair; a note in DEPLOY-VERIFICATION is enough (touch the enrollments).

### S6. An execution can cite approvals that are not its own (executed)

**What it does.** [F3d] ("each of its own order and kind") is checked only when the approval is needed. A matched execution with evidence may name any mismatch approval and any no-evidence approval of the utility.

**Run:** a matched, evidenced execution of SO1 citing SO5's mismatch approval and SO5's no-evidence approval: admitted; the row shows `matched = t` with both approval ids set.

The record then claims a supervisor's approval that was given for another order. **Suggested:** an approval id that is not needed is refused (matched: no mismatch approval; evidence present: no no-evidence approval), or checked for order and kind whenever given. A check narrower than its claim.

### S7. The UTC day lets the evening's decision authorize the next working day's disconnections (predicted) — residual R1 is larger than stated

**What it does.** [C3h] exists so that an execution never relies on an older evaluation, and [C3j] so that "a core could [not] pre-authorize tomorrow's execution on today's facts" (design C3). Both are measured on the UTC date. From 6 pm Central (7 pm in summer) the UTC date is already tomorrow's, so an execute decision written Monday at 6:05 pm is "for" Tuesday (UTC) and covers visits until Tuesday 5:59 pm Central: Tuesday's whole working day on Monday evening's facts, before Tuesday's weather determination exists. R1 describes only the other half ("an act late on a Texas evening falls on the next day's date"). The schema holds no time zone for a utility (`tenants` has none), so I do not propose a fix in -26. **Suggested:** state this in R1 and give the core its rule in an application contract (an execute decision is written on the utility's local day of the visit, after that day's weather check). Not blocking: the database cannot do better without a time zone, and the core must evaluate that day regardless.

A smaller mix, **predicted:** `adhoc_charges.effective_date` defaults to `CURRENT_DATE` (the session's zone) while a decision's window is in UTC dates; an application that relies on the default in a Central-time session gets a charge dated the day before the decision after 6 pm, refused [A6]. Fail-safe; worth one sentence in the contract.

---

## N — notes

- **N1. Only `adhoc_charges` typed `late_fee` are gated (executed).** A charge typed `penalty` with no decision is admitted, and so is an `invoice_line_items` row typed `late_fee` on a draft bill with no charge behind it. Ryan and Kyle call the thing "the late penalty", and both type names exist. The design scopes the gate to `late_fee` charges deliberately; the contract should say which type the penalty engine writes and that a late fee reaches a bill only through its charge (lesson `guard-the-act-not-the-label`).
- **N2. Subjects that differ only by meter are separate (executed; designed, test A0/O7).** With an eligible decision live for (L1, no meter), a second eligible decision for (L1, meter E1) is admitted and a second disconnect order at L1 under it; after the first is superseded by a *blocked* decision (medical hold), a fresh eligible one for (L1, E1) is still admitted. "One live decision per subject" does not mean one per service location. The core must pick one grain per location; worth an application contract line.
- **N3. A log line needs its act's record to exist, not to stand (executed).** `late_fee_applied` is admitted after its late-fee charge was voided.
- **N4. Ungated events move the stage freely (executed).** `resolved` and `written_off` need no decision and no backing fact; [E2] claims only that the database does the moving. `deposit_refund_trigger_state` treats `resolved` as clean.
- **N5. Statement shapes (executed).** Two first decisions for one subject in one multi-row INSERT: the second refused [C4a]. A writable CTE inserting a blocked decision and a charge citing it: refused [A3]. Direct writes of `dunning_stage` and `do_not_disconnect` as `tally_app` and as the owner: refused. No function in `tu.sql` reads the two dropped invoice columns or writes `dunning_stage` or `do_not_disconnect` (grep), so no mirrored code assumes one late fee per bill.
- **N6. Earlier roles (predicted from the catalog).** The triggers -26 adds to mirrored tables read nothing on the paths `tally_void`, `tally_seal`, `tally_close` and `tally_dispute` take: the two projection fences read no table; the charge trigger fires on INSERT and on updates of two columns outside `tally_void`'s grants; only `tally_app` writes `service_orders`, `dunning_events` and `customers`. The author's `ci.sh --build` 56/56 covers the earlier batteries; I did not re-run it.
- **N7. E1's wording.** The design says dunning events bind the customer by `(customer_id, tenant_id)`; the patch leaves `dunning_events_customer_id_fkey` single-column. The customer is still tied through the bill's three-column key, so nothing leaks; the sentence is wrong, not the patch.
- **N8. Lock order.** Followed everywhere I traced: decision (subject lock); charge, order, notice (the cited decision's lock); dunning line (lock, then the bill's row); executed visit (lock, then the order's row, `FOR SHARE`; the design text still says `FOR KEY SHARE`). The one read made without the lock that orders it is B1's.
- **N9. Residuals.** R2, R3, R4, R5: not blocking. R1: see S7. R5 should name the dunning-stage fence's dependence too (it does in the header, not in the design).
- **N10. Tests missing,** beyond those named above: a second late fee on one bill (S1); a second bill for one disconnection (S2); a blank capture (S3); a platform-admin approver (S4); a replication-role session (S5; the design says the `ENABLE ALWAYS` flags are not mutated because "the battery runs none"); an unneeded approval id (S6); REPEATABLE READ on an order's status (B1).

## Answers to the brief's six questions

1. **Design and rulings:** implemented as designed. Now wrong or half-done against later rulings: S1 (monthly penalty and the stage), S4 (same-utility keys; Tally User). Dispute, pledge, suspense and meter-error conditions are in the vocabulary; which act each stops is the core's and wave 7's.
2. **A path around a rule:** B1 (isolation level); S3, S6 (field verification); S5 (history load). No act without a decision, or on a blocked, unevaluable, superseded, expired or other-subject decision, in any shape I tried.
3. **Earlier patches:** no refusal found or predicted (N6).
4. **Concurrency:** the lock order is followed; B1 is the one unordered read.
5. **Tests:** sound where they look; gaps in N10. I did not audit the 127 mutations one by one.
6. **Residuals:** none blocking; R1 understated (S7).
