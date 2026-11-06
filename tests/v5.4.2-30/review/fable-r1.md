# v5.4.2-30 r1 — Fable's review

**Date:** 2026-11-06. **Reviewer:** Fable (Claude Fable 5.1), independent; `opus-r1.md` and `codex-r1.md` not read.
**Frozen files:** all five md5s match the brief (executed, `md5 -q`).
**Scratch:** `rv30fable` cloned from `tally`, TEMP revoked from PUBLIC / tally_app / tally_core, the frozen patch strict-applied twice (search_path empty, function bodies checked): both clean, the second a no-op with the expected "already exists" notices (executed). Dropped at the end.

## Verdict: ready

No blocking item. Every rule in the header holds on the paths I tried, including as `tally_app` under row-level security, and the as-known reads answer what was known at the instant in every case the battery and my probes cover. Six should-fix items, none of which changes a stored meaning; the first (a place can be closed from under an open levy) is the one I would fold before mirroring if r2 happens for any reason.

## Answers to the brief

1. **Does each rule hold; a path around any?** Yes, none found. Another tenant's row is refused twice over (the insert check, then the policy's WITH CHECK); the writer's own rows only are read (L18b, and `tax_levy_as_of` as `tally_app` returns only its tenant's row — executed). NULL arguments raise on every lookup (Q6, Q6b, Q6c, G4, M5). A re-apply is clean. The one hole is not in a rule but in a rule's upkeep: the place a levy names can be closed without the levy (S1).
2. **Anything read as known too early or too late?** Not on any single-session path. Across two sessions the template's `now()` stamps can put a successor's `created_at` before the predecessor's `closed_at`; a read in that window raises rather than mis-answers (S5, executed).
3. **Does the patch or the older-test change break anything earlier patches had right?** No. The re-issued `log_customer_attribute_changes()` and the attribute CHECK are the live -07 versions plus `state_agency_basis` (live: nine attributes, eight compare branches; patch: ten and nine — executed against `tally`). `should_charge_tax()` and the three-argument `premise_places_as_of()` have no later definition in `tu.sql` than the ones re-issued. The three-argument read at `now()` is the old read exactly (a `voided_at > now()` or `created_at > now()` row cannot exist). The older-tests diff is mechanical: every version insert writes the four answers with the old defaults, the pipeline safety fee false in the penalty base; -09's exemptions name gas; -16's N12 and T7 move to percent with the same open upper bound.
4. **Tests narrower than their claim, or a mutation caught for the wrong reason?** Seven L checks use the fragment `tax_levy`, which matches every message that names the table (S4a); P4's fixture is invalid apart from the thing it tests (S4b); the header's succession rule has no positive test (S4c). The 33 mutations are each caught where named; none for the wrong reason that I can see (N14's "2 rows" catch at Q3 is a legitimate symptom of the dropped filter).
5. **Do L1–L5 block?** No. L2 is -07's accepted shape. L1 has a gap worth naming (S6).

## Should-fix

### S1. A place can be closed from under an open levy, and the levy keeps answering — executed

The insert check requires the place's rows to cover the levy's dates; nothing maintains that afterwards. `enforce_place()`'s conflict list (memberships, profiles, facts, child places, jurisdictions) does not include `tax_levies`. Probe (owner, rolled back): an open levy on city X from 2026-01-01; the profile voided so only the levy cites X; `UPDATE places SET effective_to = '2026-03-01'` on X — **admitted**; the levy still has `effective_to` NULL and `tax_levy_as_of(... '2026-08-01', now())` still returns it.

Why it matters: no premise can reach the levy after the close (its memberships in X must be closed first, so `premise_places_as_of` stops returning X), so no bill is mis-taxed today. But the levy is keyed by code, not row: if a successor place with the same code is later loaded (a re-incorporation, or a reused code), the dangling open levy covers it from its first day with no approval — exactly the approval L1 says is the insert. And `tax_levy_reference_gaps()` is silent about it (the join to a place in force on the date finds none).

Fix: add to `enforce_place()`'s conflict query a leg over `tax_levies` of the same kind, state and code whose range runs past the close and is not still covered by the other rows of that code (the same `range_agg` test as the insert check, with the closing row cut to `NEW.effective_to`), so a succession stays allowed and a dissolution waits for the utility's close. That is -16's function (places); whether -30 re-issues it is Ryan's call on stream boundaries. If deferred, say so in the header as a known limit.

### S2. Exemption service types are not checked against the service vocabulary — executed

The new constraint requires a non-empty list with no NULL, but any text passes. Probe: an active, verified exemption with `service_types = '{Gas}'` is admitted; `should_charge_tax(customer, true, 'gas', ...)` then returns **true** (taxed). The clerk who meant gas gets a customer taxed in silence — the "misspelled code silently reaches no one" case the rule-table lessons name. `rate_item_versions` has the service list (`water, sewer, electric, gas, stormwater, trash, reclaimed_water`, plus `all`); add `service_types <@ ARRAY[...]` to the constraint (the precondition should count such rows too). Whether `all` is a valid exemption service is a design call: I would exclude it ("every service" is the list written out, as the constraint comment already says).

### S3. The fact-kind repair refuses a re-apply once any percent fact exists — executed

`$repair30$` raises whenever a `sales_tax_rate` fact exists, regardless of whether the kind is already in percent. After -32 loads the published rates, the -30 file no longer applies twice (the mirrored body in `tu.sql` is unaffected on a fresh build because -32's facts come after it). Guard the raise with the kind still being a fraction: `AND EXISTS (SELECT 1 FROM place_fact_kinds WHERE fact_code = 'sales_tax_rate' AND value_max IS DISTINCT FROM 100)`. Then the UPDATE's own WHERE already makes the repair a no-op.

### S4. Tests

- **S4a** L7, L7b, L8, L11, L12, L13, L14b refuse on fragment `tax_levy`, which `strpos` finds in any message naming `tax_levies` — the schema message (`tax_levies: the document is not a valid tax_levy v1: /rate_percent: must be at most 100`), but also `new row for relation "tax_levies" violates check constraint "tax_levies_rule_reference_check"` (executed with a blank `tariff_reference`). Use the schema's own reason: `must be at most 100`, `must be at least 1`, `not a valid tax_levy v1: /source_kind`, and so on.
- **S4b** P4's row has `change_type = 'rate_change'`, which `rate_item_versions_change_type_check` does not allow (executed: not in `initial, succession, correction, backfill`), and its valid range overlaps P3's open version. The BEFORE trigger fires before the CHECK, so the test passes for the right reason today (mutation N24 still lands on P4 because the fallback refusal carries no `late-penalty base`), but the fixture should be a row refused for one reason only: `succession` with `supersedes_id`, or a different rate item.
- **S4c** The header's rule "its successive rows may cover them together" has no battery test. Executed on the clone: a levy from 2026-01-01, open, over a city whose first row ends 2026-07-01 and whose successor row of the same code starts there — **admitted**; the same over a code whose rows leave June 2026 uncovered — refused, naming both rows. Add both (and a mutation that replaces `range_agg` coverage with "any row of that code in force on `effective_from`").
- **S4d** The Q section runs as the owner (after `RESET ROLE` at L21b), so the battery never reads a levy as `tally_app`. It works (executed, N3 below); a one-line Q1 as `tally_app` would pin it.

### S5. Two sessions can record a successor "before" the close it follows — executed; the template's

`enforce_rule_row_insert()` stamps `created_at = now()` (transaction start) and the close stamps `closed_at = now()`. Session 2 opens a transaction (T0), session 1 later closes levy A on 2026-07-01 (`closed_at` = T1 > T0) and holds, session 2 inserts successor B from 2026-07-01 — it waits on the exclusion for session 1's commit, then succeeds with `created_at` = T0. Executed: A `closed_at 17:33:17.66`, B `created_at 17:33:16.63`; `tax_levy_as_of(... '2026-08-01', 17:33:17.15)` raises `21000: 2 rows ... in force`. The read refuses rather than mis-answers, the window is seconds wide and needs two operators on the same key, and the same stamps govern places and memberships (-16) and every rule table (-17), so this is the template's property, not -30's. Options: stamp `created_at` with `clock_timestamp()` in the template (the insert then post-dates any commit it waited on), or state it beside L2. I would not hold -30 for it.

### S6. L1's gap: a published rate with no levy at all is never reported — predicted

`tax_levy_reference_gaps()` starts from the utility's levies, so it reports a published rate that *differs* from a levy, never a place the utility's premises are in (tax axis) that carries a published `sales_tax_rate` and has no levy. A new transit authority or district that starts taxing is the case L1 describes ("a published change nobody approved") and the report is silent on it. A second leg — places reached by the tenant's open tax-axis memberships on `p_on`, with a published rate in force and no levy of that kind in force — closes it; `levy_id` NULL and `levy_rate_percent` NULL would mark the row.

## Notes

- **N1** The published rate's range is half-open (`value_min <= v < value_max`, so 100 is refused — executed, and -16's T7 keeps that) while the levy schema's `maximum` is 100 inclusive. Immaterial; mention in the fact kind's description if anyone cares.
- **N2** `tax_levy_as_of()` as `tally_app` with `app.user_id` set returns the tenant's own row (executed); the invoker-rights read under FORCE RLS works as the comment says.
- **N3** Mutations: nothing mutates the G section (dropping `IS DISTINCT FROM` in `tax_levy_reference_gaps` would land on G2) or the state place's `created_at` leg in `premise_places_as_of` (would land on M3). Two cheap additions.
- **N4** L17's 42501 comes from the revoked DELETE privilege, with the template's "never deleted" trigger behind it; the label is right either way.
- **N5** The `rate_item_versions` backfill at `tu.sql` 15456 (the -03 migration from `rate_items.current_rate`) does not name `in_late_penalty_base`; it runs before -30 in a fresh build and on an empty table, and on a real database with versions the -30 precondition refuses first, as intended.
- **N6** The repair's `DISABLE TRIGGER` / `ENABLE ALWAYS TRIGGER` pair is inside the one transaction, so a failure anywhere rolls the lift back with everything else; F1b verifies `tgenabled = 'A'` afterwards (executed via the clone's catalog after apply).
- **N7** `end_as_known()` is `IMMUTABLE` and `LANGUAGE sql`, a pure function of its arguments, inlined into both readers; the "born with an end" case (county L19 / Q5) reads as known from the start, as the comment says.
- **N8** Known limits: L1 see S6; L2 is -07's accepted shape; L3, L4, L5 do not block.

## Probes (all rolled back or on `rv30fable`, dropped)

| # | What | Result |
|---|---|---|
| 1 | L7 / L12 / blank `tariff_reference` messages | schema reasons `/rate_percent: must be at most 100`, `/stacking_position: must be at least 1`; the reference CHECK message also contains `tax_levy` |
| 2 | close a place under an open levy | admitted; the levy still answers `tax_levy_as_of` |
| 3 | levy across a succession / across a gap / on the closed row only | admitted / refused / refused |
| 4 | exemption `{Gas}`, then `should_charge_tax(..., 'gas', ...)` | admitted; returns true |
| 5 | `'rate_change'` in the change-type list | false |
| 6 | published rate 100 | refused by -16's range |
| 7 | the repair block with a percent fact present | raises |
| 8 | two-session close / successor race, read between the stamps | `21000` two rows |
| 9 | `tax_levy_as_of` as `tally_app` at `now()` | the successor only |
