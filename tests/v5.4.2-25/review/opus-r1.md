# Opus review: v5.4.2-25 r1 (disputes and the dispute rule family)

**Date:** 2026-11-07. **Reviewer:** Opus. **Round:** 1.
**Verdict: not yet** (one blocking item, B1).

## Hashes

All six frozen files and the brief match `review-brief-25-r1.md` / `.md5`:
patch `6fe77611…`, battery `58a94b36…`, races `5f019c70…`, mutations `8a7f860a…`, terms `83d14843…`, migration `55d80759…`, brief `21060d64…`.

## What I ran (scratch `rv25opus`, TEMPLATE tally, TEMP revoked from PUBLIC, tally_app, tally_core; dropped at the end)

- **Strict apply, twice** (`search_path=`, `check_function_bodies=on`): first run clean (four law rows seeded); second run prints "already applied" and does nothing. Reproduced.
- **battery-25 (frozen):** 201 PASS, rc 0. Reproduced.
- **races (frozen) on my clone:** DR1–DR9, 12 PASS. Reproduced.
- **T2's re-created `enforce_reading_validation_workflow`:** `pg_get_functiondef` on `tally` against the clone. The only differences are the six `dispute_*` names removed from the whitelist and from the HINT. Nothing else changed.
- **Probes:** two probe files, each the battery's fixtures and helpers (lines 1–540) followed by my statements, run as tally_app under `app.user_id` and ending in ROLLBACK. Results are quoted below.
- Not run: `mutations-25.py`, `ci.sh`, `terms-25.py`, `migration-25.py` (the brief forbids the first two; I read the other two only).

---

## B — blocking

### B1. Nothing stops a record being written after the resolution if it goes in the same statement as the resolution (executed)

The status move (`z_dispute_move_status`) is an AFTER ROW trigger, so it runs at the end of the statement. Every "nothing after the resolution" check reads `disputes.status` through `dispute_lock()`, and that column is still `open` for the rest of the statement. The checks are D2e (amounts), D4k (determinations) and D5f (events). This is the known lesson `projection-checks-lag-in-one-statement`: a check reads a column that an AFTER trigger fills in, and the value is stale inside a multi-row or WITH statement.

All of the following were run as tally_app, investor-owned tenant T2, on bill I5:

| Probe | Statement | Result |
|---|---|---|
| P1 | one `INSERT … VALUES (resolved sustained), (escalated regulator)` | ACCEPTED. Events by record_seq: resolved 91, escalated 92. The dispute is `resolved`. |
| Q3 | one `INSERT … VALUES (withdrawn), (stage_entered s1 manager)` | ACCEPTED. Seq: opened 103, withdrawn 110, stage_entered 111. |
| P2 | `WITH e AS (INSERT resolved) INSERT INTO dispute_determinations … supersedes the live row, sheltered 25` | ACCEPTED. The dispute is resolved, has 2 determinations, and the newer one's record_seq is above the resolution's. |
| P2b | `WITH e AS (INSERT resolved/waived) INSERT INTO dispute_amounts … 999` | ACCEPTED. The resolved dispute has 2 amounts. |

**Effect on the reader:** `dispute_shelter_as_of(I5, 2026-03-15, now())` returns 25.00 for P2's dispute. That is the figure from the determination written after the resolution, so the record of what was sheltered between receipt and resolution was rewritten by a row the brief says is refused.

COPY is not a path: tally_app gets `COPY FROM not supported with row-level security` (executed). Two first determinations in one statement are refused correctly at D4m (Q2, executed).

**Fix (suggested, measure first):** every dispute record already takes a number from one sequence (`dispute_record_seq`), in the order the rows are actually written. Add an AFTER INSERT row trigger, ENABLE ALWAYS, on `dispute_amounts`, `dispute_determinations` and `dispute_events`, and on `dispute_amount_lines` if wanted. It refuses a row of a dispute whose resolution or withdrawal event has a lower record_seq than the row. AFTER ROW triggers fire after every part of the statement, so either order inside a WITH is judged by the order it really ran in. Keep the BEFORE checks for their messages. Also add event-against-event in the BEFORE guard, read from `dispute_events` rather than from `disputes.status` (a BEFORE ROW query sees earlier rows of the same statement). Battery: P1, Q3, P2 and P2b as refusals, written first and seen red on r1, plus the legitimate order (a determination, then the resolution, in one WITH) as an admit. Mutations: one per table that removes the new check.

---

## S — should fix

### S1. A tariff may drop the law's duties and review stages; the brief says they are compared (executed, by the battery's own fixture)

`dispute_tariff_compare` compares blocks, subjects, start, end and must-pay. Its comment says "Stages and duties are not compared". The brief says a tariff is compared on "subjects, shelter, must-pay, end, stages, blocks and duties".

Evidence: battery N1b admits T2's tariff `ac` (from `pg_temp.tdoc()`). It is measured against the 16 TAC 7.45 protected row, which has duties `investigate, report_result, inform_complaint_route` and a final regulator stage `s2` (7.45(2)(C)). The tariff's duties are only `investigate, report_result`, and its stages are manager then executive, with no regulator stage. The tariff therefore drops the duty to tell the customer how to complain to the Commission, and drops the Commission stage.

A determination that cites the tariff then takes its stages and its must-pay from the tariff (D4g, D5b). So the dropped stage cannot be recorded as a stage event: `stage_entered s2 regulator` is refused because s2 is not in the cited document.

Fix: compare duties (the tariff's duties include the law's) and stages (every law stage's decider appears in the tariff, and no tariff deadline is longer than the law's), or state the narrower rule in the header and design and correct the brief. N1b's fixture then needs `inform_complaint_route` and the regulator stage.

### S2. Where the law governs, a determination may leave out the utility's own tariff and record the law's narrower shelter (executed)

D4e makes a city cite its policy when one is in force, but only under a delegation. Under a governing law row nothing requires the tariff in force to be cited. P3: a T2 determination with `tariff_id` NULL and the law's three blocks was ACCEPTED, while T2's tariff `ac` was in force on the received date. That tariff blocks `notice_issue` as well, ends at resolution rather than at day 60, and asks only undisputed charges. So the record shows a narrower shelter than the utility's own tariff gives (Kyle's standing rule: always follow the tariff).

P3b, the same determination citing the tariff, is also admitted. Both are allowed.

Fix: extend D4e to every law row. When `rule_tariff_row_as_of(...)` finds a tariff in force on the received date, `tariff_id` must be that row. A determination may cite only the law when no tariff is in force.

### S3. The amount in dispute has no upper bound when it names no lines, so the per-line reader returns more than a line charges (executed)

`dispute_amounts.amount` is checked only to be > 0, and the bill is checked only when lines are given. P4: an amount of 1000 on bill I5 (amount due 90; positive lines 60 and 40), a determination sheltering 1000, and then `dispute_line_shelter_as_of(line 21, …)` returns **600.00 on a 60.00 line** (basis `pro_rata`). `dispute_shelter_as_of` returns 1000.00 sheltered on a 90.00 bill. The brief lists "a line amount past its charge" as a path.

Fix: for a dispute that names a bill, refuse an amount above the sum of the bill's positive lines (the same base the pro-rata reading spreads over). Or refuse it in the determination: `sheltered_amount` is at most that sum. Add a boundary test at the sum and one cent above it.

### S4. A reading stays `disputed` after its dispute ends, which the header says cannot happen (executed)

Header line 79 says "A reading's status 'disputed' needs an open dispute naming it". P5 (T1, reading 71): dispute → reading set to `disputed` (accepted) → withdrawal (accepted). Afterwards the reading's status is `disputed`, the dispute is `withdrawn`, and no open dispute names the reading. Nothing moves the reading back, and nothing lists it.

This matters because `populate_reading_calculations` takes the previous reading only from `status = 'active'` (tu.sql 36741), and the consumption-statistics view filters on `active` (tu.sql 4826). The next reading on that meter skips this one, so its consumption is figured from an older reading, for as long as the status stays put.

Fix: either (a) the status move (`dispute_move_status`) also returns the reading to `active` when no other open dispute names it, keeping a reading that is `replaced` or `voided` as it is; or (b) narrow the header to "enters only under an open dispute, leaves only when none is open" and make the reading an invariant or queue finding. (a) matches "nothing has to be reset" (CI-074).

### S5. Eleven new links between utility tables are not tied to the utility (executed, catalogue query)

The board's rule (R-12, 2026-11-05) is that every key between tenant tables carries `tenant_id`. The query was: foreign keys on the six new tables whose target has `tenant_id` and whose own columns do not include it. Leaving out the three that are tied through `dispute_id`, these remain:
- `created_by` → users, on disputes, dispute_amounts, dispute_determinations and dispute_events, plus tariffs' `created_by` and `closed_by` (from the template);
- `dispute_determinations.tariff_id` → dispute_tariffs(id);
- `dispute_events` `correction_credit_id`, `correction_invoice_id` and `correction_ledger_entry_id`;
- `dispute_amount_lines (invoice_line_item_id, invoice_id)` → invoice_line_items.

Today the guards check the customer or tenant behind each data link (D4f, D5e, and the line's bill copied from the dispute), so I found no cross-utility write as tally_app. But the CI-116 patch must recount and convert all eleven. They cost nothing to tie now (`dispute_tariffs` would need `UNIQUE (id, tenant_id)`).

### S6. Kyle's 11-05 penalty rule cannot be stated in the record; the core must read it from open disputes, against what the determination says (predicted)

Kyle (2026-11-05, Q1): "no late penalty at all on a bill while the customer's dispute of it is open". His standing rule is that platform defaults apply where the tariff is silent. In -25:
- the reader returns a row for every open dispute of a bill, with or without a determination. That is enough for the core to hold penalties on the whole bill;
- but the `late_fee` block means "no late fee on the sheltered amount" (the `dispute_blocks` description), not the whole bill;
- D4h requires a sheltered determination's blocks to equal the cited tariff's, so under a Brenham-shaped tariff (silent on late fees) the record cannot say late fees are held;
- a `no_terms` determination blocks nothing.

So the core would hold penalties while the determination says no late-fee block applies. Kyle also flagged that the start and end are not yet ruled (proposed: raised before the due date, until resolved).

This is a rule conflict for Ryan: K-07 says a city has no default, while Kyle's standing rule allows a platform default where the tariff is silent. My recommendation: say in the header that the penalty hold is read from the open disputes the reader returns, not from `blocks`, and record the conflict in the decision log.

---

## N — notes

- **N1. History load in replica mode (executed).** As the superuser with `session_replication_role = replica`, a T1/C1 dispute naming T2's bill I5 (customer C5) was ACCEPTED (P7). PostgreSQL skips foreign-key checks in replica mode, and the dispute guard leaves the bill's tenant and customer to the composite key ("the composite FK's to refuse"). This applies across the whole schema, not just -25. If replica-mode loads are supported, the guard could compare `invoices.tenant_id` and `customer_id` itself at almost no cost.
- **N2. The status move, residual R7 (read + catalogue).** `dispute_move_status` is SECURITY DEFINER and owned by `tally`, a superuser. I found no other way to reach it. It is a trigger function, tally_app has no TRIGGER, CREATE or TEMP, and `enforce_dispute_update` admits only a move to the type of an existing closing event of the same dispute at its stamp. As the owner, a move with no event and a move back to `open` are both refused by that guard. The seal lesson (`seal-pattern-owner-roles`) says never own a definer by the superuser. No superuser-only exemption fires on a `disputes` UPDATE today, so not blocking, but a dedicated NOLOGIN owner with UPDATE on just the three status columns would follow the rule.
- **N3. The state, service and system of a determination are the caller's (predicted).** D4a resolves the law from `NEW.state_code/service_type/system_kind`, not from the dispute's bill or the customer's location. Today only one family exists (TX gas distribution), so another choice finds no law and is refused. Once a second state or service is seeded, tie these columns to the bill's service and the location's state.
- **N4. A determination may cite an amount row that has been superseded (executed).** Q1: amounts 80 (claim, March 12) then 20 (agreed, March 13); a determination citing the 80 row and sheltering 80 was accepted. D4j checks only that the row is the dispute's and was recorded first. This is the core's evaluation, but "the amount in force as of the determination" could be checked cheaply.
- **N5. The shelter start over-refuses.** A law of `within_days` or `on_regulator_complaint` refuses a tariff of `any_time`, which is wider than either. This leans toward protection, so it is not a hole, but a small city could be refused a policy more generous than the law.
- **N6. The resolution day itself is not sheltered.** The reader drops the dispute when `occurred_on <= p_on`, so the resolution date is not sheltered. The design (D6) says "past the resolution … date". The code and its comment ("no row from its resolution date") agree with each other and R5 tests them. One of the two texts should change so they say the same thing.
- **N7. Locks.** I read the order and it is followed: the dispute's lock; then, for a determination, the law row (shared) and the tariff (shared). A reading's move takes the dispute locks in id order. The lines and the sum check run inside the amount's own transaction, which already holds the lock. D4e's `rule_tariff_row_as_of` read takes no lock (residual R6). The locks on the reading move protect nothing beyond S4's state: without them, the worst outcome is again "disputed with no open dispute", which the normal path already reaches. This matches the design's note that no race exercises them.
- **N8. Tests.** No battery case uses a multi-row or WITH shape against D2e, D4k or D5f (B1), and no case moves a reading back after its dispute ends (S4). Mutations M-for-D4k/D2e/D5f pass, but only because each is exercised in its own statement.
- **N9. Residuals R1–R7.** None is blocking on its own. R6 (a back-dated tariff makes an earlier "no terms" wrong) is acceptable as the core's audit finding. R7: see N2.
- **N10. The rule template and T1.** `assert_rule_table_invariants` and the other invariants pass at the patch's end. The template's tariff check passes every overlapping law row to the comparator. Precondition P0–P4 read only (migration-25.py).
