# v5.4.2-25 r1 — Fable's review (disputes and the dispute rule family)

**Date:** 2026-11-07. **Reviewer:** Fable (claude-fable-5-1). **Verdict: not yet** (one blocking item, B1).

**Frozen files:** all six md5s and the brief's md5 match the brief's table. Reviewed only those copies.

**Reproduced on `rv25fable`** (clone of `tally`, TEMP revoked from PUBLIC/tally_app/tally_core, frozen patch applied strictly with `search_path=''`, `check_function_bodies=on`): the strict apply succeeded; a second run said "already applied (disputes exists); nothing to do". `battery-25-frozen-r1.sql`: 201 PASS, rolled back. `disputes-25-frozen-r1.sh rv25fable`: DR1–DR9, 12 PASS. `terms-25.py` (the live copy, same md5 as the frozen one; the frozen copy's `ROOT` resolves to `tests/`, so it only runs in place) with `tools/law/.venv`: 0 failures. Not run (per the brief): `migration-25.py`, `mutations-25.py`, `ci.sh`. The clone was dropped at the end.

Probes were run as `tally_app` under `app.user_id` on the battery's fixtures, inside the battery's own rolled-back transaction (its last two lines replaced by the probe block), except the isolation probe, which used a committed fixture of its own.

---

## B — blocking

### B1. "Nothing after the resolution" is read from a projection and is bypassed inside one statement — executed

The guards D2e (`enforce_dispute_amount`), D4k (`enforce_dispute_determination`) and D5f (`enforce_dispute_event`) decide "is the dispute still open" from `disputes.status`, which `dispute_move_status` writes in an AFTER ROW trigger. AFTER triggers of a data-modifying CTE fire at the end of the whole statement, so within one statement the status is still `open` when the next record's BEFORE guard reads it (PATCH-LESSONS `projection-checks-lag-in-one-statement`). The brief asks for exactly this path ("a determination or amount after the resolution", "writable CTE").

Executed, dispute 35 (T2, live determination 555) and dispute 36:

```
P1  WITH e AS (INSERT INTO dispute_events … 'resolved' … RETURNING id)
    INSERT INTO dispute_determinations … supersedes 555 … FROM e        -> ACCEPTED
    after: disputes.status = resolved, status_cause_id set;
           record_seq: opened 86, resolved 121, determination 122  (a determination AFTER the resolution)
P1b resolved + 'escalated' event in one statement                      -> ACCEPTED (escalated record_seq 124 > resolved 123)
P1c resolved + a new dispute_amounts row in one statement              -> ACCEPTED (status resolved, 2 amount rows)
P1d control: the same two writes as two statements                     -> REFUSED 23514 [D2e]
```

So the rule the header states ("one resolution or withdrawal, and nothing after it", D4k/D2e/D5f) holds only across statements. The readers are not misled (the shelter still ends at the resolution's `occurred_on`), but the record's claim is false, `dispute_live_determination()` returns a determination recorded after the resolution, and the close floors read it. Multi-row INSERT and COPY have the same lag (predicted: BEFORE per row, AFTER at statement end).

**Fix (measure it):** judge openness from the events, not the status — in `dispute_lock` (or in each guard after it) refuse when `EXISTS (SELECT 1 FROM dispute_events e WHERE e.dispute_id = d.id AND e.event_type IN ('resolved','withdrawn'))`. A row inserted earlier in the same statement is visible to the trigger's query (the command counter advances between SPI statements; P2b/P2c below show the opened-event branch already seeing in-statement rows). Keep the status check too, or drop it as a piece another check always beats. Add a battery check in the CTE shape for an amount, a determination and an event, and a mutation that removes the events read. `enforce_reading_dispute_status` reads `x.status = 'open'` the same way; there the lag fails safe (a CTE withdrawing the dispute and unmarking the reading in one statement was refused [T2]), but the same change is cheap.

---

## S — should fix

### S1. `shelter_ends_on` is not tied to the cited document's `shelter_ends` — executed

D4h ties `blocks` to the cited document "so a record can't claim a different shelter than its rule", but the end of the shelter is unchecked beyond `>= received_on` (D4o). Under 16 TAC 7.45 (`earlier_of_resolution_and_days`, 60 from issue):

```
P3a sheltered, shelter_ends_on NULL (until resolution)     -> ACCEPTED; dispute_shelter_as_of(I5, 2026-12-01, now()) = 30 sheltered, blocks {disconnect_order,disconnect_execute,late_fee}
P3b sheltered, shelter_ends_on 2030-01-01                   -> ACCEPTED
P3c not_sheltered with an end date                          -> REFUSED [D4n]  (the shape check exists for that outcome only)
```

A record can claim more shelter than the law gives — the mirror image of L6, which the brief asks about. Fix: for `sheltered`, check the shape by the cited document's kind: `resolution` and `through_regulator_close` require NULL; `earlier_of_resolution_and_days` requires NOT NULL and, for a bill dispute, `<= invoice_date + days - 1` (the only anchor is `issue`; contract 4 says the end is inclusive: April 29 for a March 1 bill). Test both sides of the boundary; add the mutation.

### S2. L6 compares neither duties nor stages — executed

The brief lists "subjects, shelter, must-pay, end, stages, blocks and duties"; the design's L6 bullets and the function comment ("Stages and duties are not compared") omit the last two. For T2 (investor-owned; the law requires `investigate, report_result, inform_complaint_route` and a final regulator stage):

```
P4 tariff 2025-01-01..2026-01-01 with duties [] and stages [], every other section equal to the law -> ACCEPTED
```

A determination citing such a tariff reads the tariff's document (`dispute_determination_terms`), so its stage events and the core's duty evaluation see fewer duties and no regulator stage than the law gives. Duties are a superset check identical to blocks (one query). Stages are harder; at least require that a law stage with `decider = regulator` (or `governing_body`) has a counterpart, or record in the design and the header that stages are deliberately not compared and why. Battery N-group has no case for either; add both sides.

### S3. `dispute_move_status` is a SECURITY DEFINER owned by the superuser — executed (catalog); not blocking

`pg_proc.proowner` = `tally`, `prosecdef` = t (`void_invoice` is owned by `tally_void`). PATCH-LESSONS `seal-pattern-owner-roles`: a definer is owned by a dedicated NOLOGIN, non-BYPASSRLS role with an exact column grant, never by `tally`, and the role is added to `assert_seal_role_invariants`. Exposure today is nil — I checked what the definer's UPDATE fires: only `b_enforce_dispute_update` (no rolsuper carve-out) and the FK; the UPDATE is keyed by `id` and `tenant_id`, both from an event row RLS has already checked — so R7 is not blocking. But every future trigger on `disputes` would run as the superuser from this path. Fix: a role `tally_dispute` with `UPDATE (status, status_cause_id, status_recorded_at), SELECT ON disputes`, owning the function; add it to the seal invariant. The guard admitting the move stays as it is (it keys on the event, not on `current_user`, which is right here).

### S4. -25 adds no guard invariant — executed (catalog)

-23 (`assert_cash_guard_invariants`, `assert_periods_guard_invariants`), -24 (`assert_suspense_pledge_guard_invariants`), -27 and -28 each pin their triggers (`pg_get_triggerdef` text, `ENABLE ALWAYS`), constraints and grants. -25 pins nothing: section 9 only calls the existing invariants, none of which knows the five dispute tables' triggers. A dropped `ENABLE ALWAYS`, a disabled `z_dispute_move_status`, or an `UPDATE` grant on `disputes` would pass CI. The brief's question 5 ("the invariant functions -25 adds or extends") has no object. Add `assert_dispute_guard_invariants()` in -24's shape (triggers, the two unique partial indexes, `disputes_status_cause_fkey`, the exact grants, `dispute_record_seq`), and call it in section 9 and from `ci.sh`.

### S5. Four links between tenant tables are single-column keys — executed (catalog)

`dispute_events.correction_ledger_entry_id → account_ledger(id)`, `correction_credit_id → customer_credits(id)`, `correction_invoice_id → invoices(id)`, and `dispute_determinations.tariff_id → dispute_tariffs(id)`. The first three targets already carry `UNIQUE (id, tenant_id)`; `dispute_tariffs` would need one. The guards cover the gap for now (D5e checks the correction's customer under RLS, D4f the tariff's tenant), and the decision log (2026-11-05, R-12) says the last patch recounts and ties every untied link — so not blocking — but a new patch should not add to the 273 when the two-column form costs one word per key. `created_by → users(id)` on the five tables follows the schema's present convention and belongs to R-12's 117 user links.

---

## N — notes

- **N1 (executed).** Record order: a dispute and its first amount in one statement (P2) give the amount `record_seq` 128 and the database's opened event 129 — "opened, exactly one, first" holds by `created_at` (equal) and by type, not by `record_seq`. Forging the opened event in the dispute's statement (P2b) and writing a withdrawal in it (P2c) are both refused [D5a]. Harmless; say so in the comment, or have `enforce_dispute_insert` reserve the opened event's sequence number.
- **N2 (executed).** `sheltered` with `sheltered_amount = 0` is accepted (P3d). If the core's answer "sheltered class, but the cap leaves nothing above average usage" should read `not_sheltered`, D4n should say so; otherwise fine.
- **N3 (executed).** A reading's move into or out of `disputed` under REPEATABLE READ raises 25000 (`dispute_lock`) whenever any dispute names the reading — a withdrawn one included (P5 took the lock; the RR probe was refused; a move between two non-disputed statuses under RR passed). A new contract on `meter_readings` writers; record it in APPLICATION-CONTRACTS.
- **N4 (predicted).** Boundary wording: the design D6 says the sheltered amount is zero "once `on` is past … the resolution or withdrawal event's date", but the patch and R5 end the shelter **on** the resolution day (`e.occurred_on <= p_on` excludes the dispute), while `shelter_ends_on` is inclusive. The patch's choice agrees with Kyle ("while the dispute is open"); fix the design text and say both boundaries in the reader's comment.
- **N5 (predicted).** Kyle 2026-11-03/-05 ("no late penalty on a bill while the customer's dispute of it is open"): the record carries what the core needs — `dispute_shelter_as_of` returns a row for every open dispute of the bill as of (date, recorded instant) even before any determination (R4), with `received_on` as the start and the closing event's `occurred_on` as the end; the law row's `late_fee` block is the TX reading. Kyle's flag 1 (start/end default) is the core's rule, not a schema change.
- **N6 (predicted).** D4a takes `state_code`, `service_type`, `system_kind` from the determination row and checks them against the tenant's profile, not against the disputed bill. With only TX gas rows today the wrong service finds no law row; once a tenant has two services a determination could cite the other service's law. A check that the bill's lines (or the reading's meter) are of `NEW.service_type` would close it; note it in the design if left to the core.
- **N7 (executed).** T2's re-created `enforce_reading_validation_workflow` differs from the mirrored body only in the six column names removed from Block 2's list and the hint (diff of tu.sql:38317ff against the patch). `idx_readings_disputed` kept, comment only. `program_types.pending_dispute` flipped and described; the enrollment refusal fires on INSERT and on a move into the type.
- **N8 (executed).** `dispute_rules` has no row security, as the other law tables (`deposit_rules`, `backbilling_rules`, `payment_allocation_rules`); `dispute_tariffs` has RLS, FORCE and the canonical policy; `tally_app` holds table UPDATE on it as on `payment_allocation_tariffs` (the template's close). Grants on the five record tables are SELECT, INSERT for `tally_app`, SELECT for `tally_core`; PUBLIC holds nothing.
- **N9 (executed).** Cross-tenant writes with the writer's own `tenant_id` on another tenant's dispute are refused as "not found" 23503 (P11, P11b); with the other tenant's `tenant_id`, as row security 42501 (battery D2n, D4z2, D5w). Owner moves of a resolved dispute back to open or a re-stamp are refused [D1g] (P7, P7b). A history load with an amount recorded before its dispute is refused [D2d] (P8). A reading born `disputed` is refused [T2] (P9).
- **N10 (predicted).** Locks: every writer takes the dispute's advisory lock first, then (determinations only) the law row and tariff row shared via `rule_law_row_cite`/`rule_row_cite`; the tariff insert takes law rows shared with no dispute lock; the closes take their own row exclusive and read citations under it. No cycle; two writers on two disputes in opposite order deadlock and retry (40P01), as the rule says. `rule_law_row_as_of` takes no lock, so D4a's "is the one in force" is read before the cite locks it — the cite re-checks under the lock, so the pair is sound.
- **N11.** Tests: the D-group refusals are tagged and tight; the boundaries pinned on both sides (D1j/D1j2, N4b/N4c, R7/R7b, R5/R5b). Missing: the one-statement shapes (B1), the end-date shape (S1), duties and stages (S2), COPY (predicted equal to multi-row INSERT). The race script's barrier (`pg_blocking_pids`, polled) is sound. Residuals R1–R6 are not blocking; R7 is answered in S3.
