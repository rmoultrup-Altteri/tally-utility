# v5.4.2-30 r1 — Opus review

**Date:** 2026-11-06. **Reviewer:** Opus. **Verdict: not yet** (one blocking item).

Frozen md5s checked first; all five match the brief, and the live patch is byte-identical to the frozen copy (**executed**). Strict apply on a fresh clone of `tally` (`rv30opus`, TEMP revoked from PUBLIC, `tally_app`, `tally_core`): clean, twice (**executed**). I did not run the battery, `ci.sh`, the mutations or the preconditions (the brief's restrictions); I read them. `rv30opus` is dropped.

PATCH-LESSONS sections read: guard-the-act-not-the-label, temporal-helper-no-live-fallback, date-from-snapshot-knowledge-from-now, checks-narrower-than-their-claim, every-branch-and-stated-default-tested, rule-table-keys-are-text-codes, depth-fence-needs-no-temp, strict-apply-before-mirror.

---

## Blocking

### B1. The as-known read of a premise's places reads the premise's state live, so an app-reachable correction rewrites what a past instant "knew"

`premise_places_as_of(…, p_recorded_at)` (patch lines 572–598) takes `v_state` from `service_locations.state` **as it is now**, then (a) picks the state place by that state and (b) keeps only memberships whose place has `p.state_code = v_state`. The -16 guard on a state change (`enforce_service_location_state_vs_places`) refuses only while a **non-voided** membership in another state exists. So the app can void the memberships and then change the state, and the past read changes.

Repro (**executed**, rolled back): a TX premise with a city membership, membership and city planted as recorded two days ago, plus an `OK` state place. Read at `now() - 1 minute`: `municipality:TX-OP-M, state:TX`. Then, as `tally_app`: void the membership ("premise keyed in the wrong state"), `UPDATE service_locations SET state = 'OK'`. The same read at the same past instant now returns `state:OK` only: the city is gone and the state is wrong.

Why it blocks: the function's comment and the header make the promise this breaks ("A rebill reads the jurisdictions the original bill saw"). The answer is silently wrong, not a refusal, and it is wrong in the direction that drops a city levy from a rebill. Both steps are ordinary `tally_app` writes. The -16 hint ("a premise wrongly placed is a new premise, or a reviewed repair; its memberships are never rewritten") says what was intended, but the schema does not hold it once the memberships are voided.

Fix options (the second is the smaller one):
1. Read the state as known at `p_recorded_at`. That needs a dated record of `service_locations.state`, which does not exist today.
2. Make `enforce_service_location_state_vs_places` refuse a state change while **any** membership exists, voided ones included. This is the hint made true: a premise that ever had places in a state keeps that state, and a wrongly placed premise becomes a new premise. One predicate change (`m.voided_at IS NULL` dropped), plus a battery check that voids and then tries the state change.

---

## Should fix

### S1. The two new guards fire on origin only; -07's twin fires always
`b_enforce_late_penalty_base` and `c_enforce_surcharge_rule_late_penalty_base` are `tgenabled = 'O'`; `b_enforce_surcharge_rider_not_taxable` (-07, the same shape on the same tables) is `'A'`, set by -07's "ENABLE ALWAYS on every guard this patch created" block (**executed**, catalogue read). Under `session_replication_role = replica` the -30 guards are skipped and -07's still fire (**predicted**; only a superuser can set it, so this is about the convention, not about `tally_app`). Fix: two `ENABLE ALWAYS TRIGGER` lines, and add both to F1b (or a new check) so a mutation back to `ENABLE TRIGGER` is caught.

### S2. A place can close under an open levy; the coverage rule holds only at insert
`enforce_place`'s close check counts memberships, profiles, facts, child places and jurisdictions in force after the close. It does not count `tax_levies`. Repro (**executed**): an open-ended levy on `TX-OP-DIES` from 2026-01-01 is accepted; the platform then closes that place at 2027-01-01, also accepted; the open levy stays in force past its place's end. The same levy written afterwards is refused ("no municipality … in force over the whole of [2026-01-02,)"). Billing is not hurt, because no membership can outlive the place, so the levy is never read past the end. But the header states the rule ("a place … is in force over the whole of the row's dates") without saying it is insert-only. A close-time refusal would break succession by code: the old row closes before its successor can be inserted. So I recommend stating it as a known limit (L6: checked at insert; a place's later close or gap is not re-checked), and optionally having `tax_levy_reference_gaps` (or a sibling report) list levies whose place no longer covers them.

### S3. Re-applying the patch fails once any sales-tax-rate fact exists
The `$repair30$` precondition refuses whenever **any** `sales_tax_rate` fact exists, even after the kind is already in percent. Repro (**executed**): with -30 applied, insert a percent fact (`2.0`) and re-apply the patch. It stops at line 539: "sales_tax_rate facts exist; their values are fractions". The other three preconditions are scoped so they fire only while the change is still pending (the column is missing). This one should be scoped the same way: `IF EXISTS (SELECT 1 FROM place_fact_kinds WHERE fact_code = 'sales_tax_rate' AND value_max IS DISTINCT FROM 100) AND EXISTS (… facts …)`.

### S4. The exemption comments still say an empty service list means every service
`COMMENT ON COLUMN customer_tax_exemptions.service_types` still reads "NULL or empty array = ALL services (blanket exemption)", and the table comment still says the function treats "ANY active exemption" as covering (**executed**, read on the patched clone). -30 makes both statements false. Re-issue the column comment ("every service is the list written out") and adjust the table comment.

### S5. Test gaps on the two drafting calls the brief names (narrower claim than check)
- **Coverage across successive place rows** (`range_agg`): no battery check writes a levy across a place's closed row and its successor. A mutation that requires one place row to cover the levy alone would survive (**predicted**). The behaviour itself is right: a levy across `[2000,2026-07-01)` + `[2026-07-01,)` is accepted, and one across a month's gap is refused (**executed**, P1a/P1b). Add both cases.
- **Places' ends as known** in `premise_places_as_of`: the state-place lookup (line 575) and the membership join (line 593) both use `end_as_known(p.effective_to, p.closed_at, …)`, but no battery place is ever closed. Mutating either back to `p.effective_to` survives (**predicted**: M1–M5 never close a place). One fixture fixes it: a city whose membership was closed and whose place was later closed, read at an instant before the membership's close.

---

## Notes

**N1. A long-running writer can make `tax_levy_as_of` raise for a short window** (**executed**, two sessions). Session 2 begins (`now()` = t0) and session 1 closes levy A (`closed_at` = t1 > t0) and commits. Session 2 then inserts successor B (`created_at` = t0); the exclusion constraint passes because A is already closed. As known at any instant in [t0, t1), both rows are in force: "2 rows of municipality TX-OP-RACE … (cardinality_violation)". The failure is loud, not wrong, and it is the template's `created_at = now()` shape, the same as `gl_mapping_as_of` and the date-from-snapshot lesson. It does not block -30. Worth a sentence in the template's limits, or stamping `created_at` from `clock_timestamp()` on rule rows in a later template patch.

**N2. Pre-onboarding instants cannot be read.** Places are stamped with when they were loaded (TX: 2026-11-05 20:17 on this build). So `premise_places_as_of(…, p_recorded_at)` before the load raises "no state known" (M3 proves it), and `tax_levy_as_of` returns nothing. A rebill of an imported legacy bill "as known when it was issued" therefore cannot use the bill's own issue instant. Migration needs a stated policy (read at the onboarding instant). The scenarios stream should know.

**N3. The three-argument form changed meaning slightly inside long transactions** (**predicted**). It now filters `created_at <= now()`. A membership committed by a transaction that **started after** the reader's transaction is visible under READ COMMITTED but now excluded; before -30 it was returned. This is harmless and arguably more consistent. `premise_time_zone_as_of` still reads through the three-argument form (as known now); that is out of -30's scope.

**N4. A reused code is indistinguishable from succession** (**predicted**). `places_no_overlap` allows one row per (kind, state, code) at a time, so `range_agg` can only ever join rows that follow each other. A dissolved city whose code is later given to a different city would satisfy one levy spanning both. Keying by code makes this unavoidable, and Texas Comptroller codes are not reused in practice. It is acceptable as stated; one clause in the table comment would cover it.

**N5. Insert-time tenant check, RLS, created_by: all hold** (**executed/read**). `get_user_tenant_id()` needs an active `app.user_id`, so a `tally_app` writer always stamps `created_by` (L1's "the approval is the insert, which records its approver" holds for the app). RLS `tenant_isolation` (USING, applied as WITH CHECK) duplicates the check. `tally_core` has SELECT only on `tax_levies` and has no EXECUTE on the insert check.

**N6. The fact-kind repair is safe and fully restored** (**executed**). `ALTER TABLE … DISABLE TRIGGER` takes an AccessExclusive lock on `place_fact_kinds` until COMMIT, so no other session can write the table while the guard is off. In `tally` the trigger was `'A'` before the patch and is `'A'` after it. The UPDATE's WHERE makes it idempotent. Only `value_max`, `description` and `source_note` change; `value_min` stays 0.

**N7. `log_customer_attribute_changes` diff is exactly the new attribute** (**executed**, function bodies diffed against `tally`): one CASE arm, one array element, one UPDATE branch. `new_value` is nullable, so a non-agency customer's initial NULL basis logs cleanly.

**N8. `should_charge_tax` change is right.** Before -30, a NULL `p_service_type` or an exemption with NULL or empty `service_types` matched every exemption. Both are now impossible: the call raises, and the CHECK refuses the rows. No other function in `tu.sql` calls it. The money stream should know that a one-off charge or line with no service type now raises rather than being treated as exempt (this belongs to L5).

**N9. Precondition C2 on a real database.** It counts every exemption row, superseded and retracted ones included, and those rows are frozen by the bitemporal guard. A database with historical NULL-service rows could not apply -30 without a reviewed repair. That is moot while nothing is live; noted for completeness.

**N10. `stacking_position`** is not unique across a premise's levies. Two levies at position 2 would both be admitted. Ordering is the core's job (L5), so this is not a schema gap now.

**N11. L1–L5 do not block.** L2 is -07's known shape, unchanged. L5 is correctly the money stream's (see N8).

**Mutations read for catching for the wrong reason:** none found. N14 is explained (Q3 raises before Q4 is reached), and N21 turns into "always true" because the column is NOT NULL, so T6 is the right catch. S5 lists the two places where a mutation would survive.
