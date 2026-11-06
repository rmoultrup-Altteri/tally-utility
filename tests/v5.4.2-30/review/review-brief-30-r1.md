# Review brief: v5.4.2-30 r1 — tax rows keyed to places, and the taxability fixes

**Date:** 2026-11-06. **Kind:** patch review, round 1.
**Reviewers:** Opus, Fable and Codex, independently. Do not read the other reviewers' files.
**Stream:** rates (`~/code/tally-utility-rates`). Read the repo at that path.

## Frozen files

Check the hashes first; if one differs, stop and report it.

| File | md5 |
|---|---|
| `tests/v5.4.2-30/review/patch-30-frozen-r1.sql` | `9076fced7e04fc4f4fbc7eadce8b61c6` |
| `tests/v5.4.2-30/review/battery-30-frozen-r1.sql` | `f44fe54786b24633294d9877b1c826e1` |
| `tests/v5.4.2-30/review/mutations-30-frozen-r1.sh` | `db66f01041abd5849bdded08186cb0f5` |
| `tests/v5.4.2-30/review/preconditions-30-frozen-r1.sh` | `785186e33388dc98d1571f6d1571952e` |
| `tests/v5.4.2-30/review/older-tests-30-frozen-r1.diff` | `bfaa7b62019e5ef4d68883b627e1fad1` |

The live copies (`sql/v5.4.2-30-tax-levies-and-taxability.sql`, `tests/v5.4.2-30/`) are identical to these today. `older-tests-30-frozen-r1.diff` is the change to earlier tests and to `tests/ci.sh` that -30 needs: every rate item version insert now gives the four required answers (the old defaults written out; the pipeline safety fee out of the late-penalty base); battery -09's exemptions name gas; battery -16's sales-tax rate checks read percent.

## What the patch does

Design: `application/rates-build-2026-11-05/tax-design.md` (sections 2.1–2.8); the open points it settles: `tax-triage.md`; the sources: `tax-inventory.md`. The patch header lists its eight parts, its rules and its known limits. In short:

1. **`tax_kinds`** (platform-held): which kinds of place levy each kind of tax. Seeded: sales tax.
2. **`tax_levies`**: the utility's own record of each tax a place levies on its bills, on the rule-terms template (role tariff), keyed by the place's kind and code within the row's state and by the tax kind. Document `tax_levy` v1: rate in percent, stacking position, `computed_on` (the levies it is charged on top of; empty means none), source kind and citation, whether it reaches residential gas. An insert check: the writer's own utility; the place kind levies the tax; a place of that kind and code is in force over the whole of the row's dates (its successive rows may cover them together); four decimals; `computed_on` names known kinds, never its own.
3. **`tax_levy_as_of()`**: the row in force on a date as known at an instant. **`tax_levy_reference_gaps()`**: where the utility's sales-tax levy differs from the published rate (a place fact). The published rate never bills.
4. **`rate_item_versions`**: `is_taxable_default`, `is_a_tax` and `applies_to_customer_types` lose their defaults (the customer types are checked against the known list, which closes the old default's omission of small and large commercial). `in_late_penalty_base` is new, required, no default. A tax, or a rider with an open surcharge rule excluded from tax bases, is never in the late-penalty base, in either order of writing.
5. Exemptions name their service types; `should_charge_tax()` refuses a NULL service type.
6. The published `sales_tax_rate` fact kind moves to percent (0 to 100) by a reviewed platform repair: the vocabulary guard is lifted for one UPDATE and set back to ALWAYS; refused if any such fact exists.
7. **`premise_places_as_of()`** gains a recorded-at instant: memberships and places as known then (recorded by then, not voided by then, an end only if its close was recorded by then). The three-argument form reads at now().
8. **`customers.state_agency_basis`**: required while `is_state_agency` is true; logged in the attribute history.

Authority: Kyle 2026-10-14 (answers 1, 2, 5), 2026-11-03 (batch 1, answer 4), 2026-11-05 (batch 2, answers 3a and 20), 2026-09-02 (the size-tier defect); Ryan 2026-09-30 (a value the utility answers for stays its own row) and 2026-11-02 (rates in percent). Kyle's files are in `../gas-billing-memory/application/`.

## Drafting calls to check in particular

- **The levy's key is the place's kind and code, not its row id** (the template requires text keys; a code survives the place's succession). Can a levy name a place it should not, or lose its place?
- **Coverage across successive place rows** (`range_agg` over every row of that kind, state and code). Can rows of different places that share a code (a reused code) satisfy it wrongly?
- **No draft levies.** A proposed rate is not a row; the insert is the approval (known limit L1).
- **`end_as_known()`** and the as-of reads: is anything read as known earlier than it was, or later? Compare `tax_levy_as_of`'s filters with `premise_places_as_of`'s.
- **The late-penalty guard in both orders**, and known limit L2 (two sessions writing at once, as -07's taxability guard).
- **The fact-kind repair**: lifting `a_enforce_place_vocabulary_immutable` inside the patch's transaction. Is it safe, and fully restored?
- **The preconditions** (existing versions, exemptions without services, state agencies without a basis, an existing fraction fact): right for a real database? `preconditions-30.sh` plants each.
- **The tests:** `ok_q` (Q1–Q5) reports an error in a read under its check's label; F1b checks the guard is back on as ALWAYS.

## Known limits (in the patch header)

- **L1.** The Comptroller's quarterly files are staged and approved in the application; the approval is the insert.
- **L2.** The late-penalty guard reads the other table's committed rows (concurrent writers), as -07.
- **L3.** No place below the state carries a sales-tax rate yet (a later data patch).
- **L4.** The old customer-level exempt columns stay, read by no tax path.
- **L5.** The bill-line side (a line naming its levy and place, no tax on tax across a line's bases, an exempt $0.00 line keeping its base, defaults on one-off charges and bill lines) is the money stream's.

Franchise fees are not in this patch: Kyle answered their base question on 2026-11-06 and they come in -31.

## Results so far (reproduce them)

- **Strict apply, twice:** clean.
- **`battery-30.sql`:** 81 PASS on `tally` + -30.
- **`preconditions-30.sh`:** 5 of 5 (a clean apply; each of the four preconditions refuses its planted row).
- **`mutations-30.sh`:** 33 of 33, each at its named check.
- **`tests/ci.sh`:** 58 of 58, with -30 pending after the money stream's -25, -26 and -27.

## What to answer

1. Does each rule hold, and is there a path around any (roles, row-level security, the as-of instants, NULLs, a re-apply)?
2. Is anything read as known at an instant wrong (too early, too late)?
3. Does the patch or the older-test change break anything earlier patches had right?
4. The tests: is any claim narrower than its check, or any mutation caught for the wrong reason?
5. Do L1–L5 block?

## How to probe

**Opus and Fable** may query the running `tally-pg` read-only. For experiments, clone into your own scratch database (Opus `rv30opus`, Fable `rv30fable`):
1. `CREATE DATABASE <name> TEMPLATE tally`.
2. Right after creating it, revoke TEMP on the clone from PUBLIC, `tally_app` and `tally_core`.
3. `docker cp` the frozen patch into the container and apply it strictly:

```
docker exec -e PGOPTIONS="-c search_path= -c check_function_bodies=on" tally-pg psql -U tally -d <name> -v ON_ERROR_STOP=1 -q -f <patch>
```

**Codex reviews source only.** Do not run docker, psql, `ci.sh` or the scripts. Every database claim must be a probe file in `tests/v5.4.2-30/review/codex-r1-probes/`. Each probe runs as the owner on a fresh clone of `tally` with frozen r1 applied, ends in ROLLBACK, and prints the SQLSTATE and message of each caught error with RAISE NOTICE. The author runs them and appends the output.

**Restrictions (everyone):**
- Do not create, drop or alter any role.
- Do not run `mutations-30.sh` or `preconditions-30.sh`; they use fixed database names.
- Never modify `tally`, `sql/tu.sql` or any repo file except your output file (and Codex's probes).
- Drop your clone when done. Do not run `tests/ci.sh`.

## Output

Write your full review to `tests/v5.4.2-30/review/<reviewer>-r1.md` (`opus`, `fable` or `codex`): a verdict ("ready" or "not yet"); blocking items (B1…) with the concrete path or repro; should-fix items (S1…); notes (N1…). Mark each claim **executed** or **predicted**. If you cannot write the file, send the review to main as several messages, each under 3 KB. Your final message gives the verdict, the blocking items in one line each, and the file path.
