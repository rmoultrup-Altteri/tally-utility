Folder: `~/code/tally-utility-rates`. If your working directory is not this folder, stop: this is not your stream's file (see the board, `HANDOFF.md`).

# Handoff: schema stream "rates" — tax, gas cost, zones, reads, dated history

**Generated**: 2026-11-05, end of this stream's third session
**Branch**: `main`. Run `git pull --ff-only` first.
**Status**:
- v5.4.2-29 (every Texas county and its time zone) is **mirrored**: 2026-11-05, all three reviewers ready on round 3.
- **v5.4.2-30** (tax levies and taxability fixes) is **drafted at round 0**. Its battery passes 80 of 80. Seven older tests must be ported before it can join CI or go to review.
- Kyle has the franchise-fee base question (roadmap K-15).

## Goal

Close the rates half of the open invariants, beside the money stream (`~/code/tally-utility`). Parity stands at 85 of 135.

## How this stream differs from working alone

- **The board** (`HANDOFF.md`): read it at session start and before every mirror. Edit only this stream's lines.
- **Next free patch number:** -31. Claim a number on the board before creating its file.
- **`tests/ci.sh`:** a patch joins `PENDING` only once its battery passes and the older tests it breaks are ported. CI holds a lock across all clones.
- **Law runners:** this clone has no `tools/law/.venv`. `ci.sh` finds the main checkout's venv by itself.

## Completed this session

- [x] **-29:**
  - Codex reviewed round 2 and said not yet (B1): re-applying refused after Texas itself was closed and succeeded.
  - Round 3 fixed it: Texas is looked up as in force on 1900-01-01.
  - All three reviewers said ready on round 3.
  - Mirrored, with the build verified identical to the expectation.
  - Records: `ci.sh --build` 55/55, DEPLOY-VERIFICATION, DECISION-LOG, parity update, GBM Section BX.
- [x] **Tax work:**
  - `application/rates-build-2026-11-05/`:
    - `tax-inventory.md`: 17 gaps, 18 open points.
    - `tax-triage.md`: 16 points settled, 1 question sent to Kyle.
    - `tax-design.md`: the three-patch split and -30's interface in section 2.8.
  - -30 claimed on the board.
  - `tests/v5.4.2-30/battery-30.sql` written tests-first (80 checks).
  - `sql/v5.4.2-30-tax-levies-and-taxability.sql` drafted (r0, about 700 lines). It applies strictly twice, and the battery passes 80/80.
- [x] Kyle's batch 2 (2026-11-05) read and folded into the design. Answer 3a gives the per-charge late-penalty base; answer 20 the state-agency basis.
- [x] Roadmap: K-15 added and phase 1's text updated; dashboard data uploaded.

## Not Yet Done

1. [ ] **Port the older tests -30 breaks.** CI run with -30 pending: 51 pass, 7 fail.
   - **Battery -09:** exemptions are inserted without `service_types`. Error: `new row for relation "customer_tax_exemptions" violates check constraint "customer_tax_exemptions_service_types_check"`. Add `service_types` (`'{gas}'`) to each insert.
   - **Battery -16 N12a:** `pg_temp.fact('austin', 'sales_tax_rate', '5', …)` expects a refusal, but under percent 5 is a valid 5%. Change it to `'101'` and update its message (over 100 percent).
   - **Batteries -21, -23 (the money stream's: board note), -28, -29, and race `tests/v5.4.2-21/races/labels-21.sh`:** rate item version inserts lack the new required columns. Error: `null value in column "applies_to_customer_types" of relation "rate_item_versions" violates not-null constraint`. Add `is_taxable_default, is_a_tax, in_late_penalty_base, applies_to_customer_types` with explicit values. Keep each test's meaning: a pipeline safety fee rider is `false, false, false`.
   - **Race -21's second error** (`40001 rate_items … was modified since it was read`) follows from its first. Re-check it after the port.
   - **Battery -20 passed** although expected to break; check whether it inserts versions at all.
2. [ ] **Add -30 to `ci.sh`.** Put `sql/v5.4.2-30-tax-levies-and-taxability.sql:tax_levies` in `PENDING`, and add `30` to the battery loop (line 140). Run `tests/ci.sh`. **Expected: all pass.**
3. [ ] **Board note to money:**
   - Battery -23's fixture was ported, and why.
   - The money-side items from `tax-design.md` section 1: a bill line naming its levy and place; no tax on tax unless the levy's `computed_on` names it; an exempt $0.00 line keeps its would-be base; no defaults on `adhoc_charges.is_taxable` and `invoice_line_items.is_taxable`; a one-off charge's service type required; snapshots citing places, memberships and levies; the liability by jurisdiction and accounting period.
   - The new `in_late_penalty_base` column, which their penalty engine reads.
4. [ ] **Write the mutation runner `tests/v5.4.2-30/mutations-30.sh`.** Model it on `mutations-29.sh`. One mutation per guard: the insert check's six refusals, `end_as_known`, the as-of filters (`created_at`, `voided_at`), the two penalty-base triggers, the exemption check, `should_charge_tax`'s NULL refusal, the basis check, and the fact-kind repair's precondition. Each must be caught at its named battery check.
5. [ ] Freeze round 1 and write the review brief, then run all three reviewers: Codex source-only, probes run by us.
6. [ ] -31 (franchise fees) after Kyle answers K-15; -32 (Texas cities and districts, with the Comptroller's rates). Then handoff items 3–8 from before:
   - the gas-cost billing side;
   - zones and factor tables;
   - read ownership and replacement reads (Kyle batch 2, answer 15: keying errors);
   - dated history and the meter test fee;
   - the backbilling tariff table (Kyle batch 2, answers 10–14);
   - retiring the `decimal` rate unit;
   - retiring the old customer exempt columns (moved out of -30).

## Failed Approaches (Don't Repeat These)

- **A `place_id uuid` as the levy's area key:** `rule_table_register` requires area-key columns to be `text NOT NULL`. Use `place_kind` and `place_code` (text) within the row's `state_code`. That also survives place succession.
- **`UPDATE place_fact_kinds` directly:** refused by `a_enforce_place_vocabulary_immutable` ("vocabulary rows are never edited"). -30 does a reviewed repair: precondition no `sales_tax_rate` fact, guard disabled for the one UPDATE, then `ENABLE ALWAYS`.
- **Terms written as `1.0`:** the template refuses non-canonical numbers ("numbers must be written canonically, without trailing fractional zeros"). Write `1`, `2`.
- **Levy test with state `'OK'`:** the template refuses an unknown state first ("OK is not a known state"). Use a code with no place instead (county `48994`).
- **"As known three days ago" expecting an empty answer:** Texas was recorded when `tally` was built, so before that the read refuses with `P0002` ("is no state known"). Use "a moment ago" (`now() - interval '1 second'`) for the open-then case.
- **`premise_places_as_of` results compared whole:** they always include the state row. Filter with `kind_code <> 'state'`.

## Key Decisions (all in DECISION-LOG 2026-11-05)

| Decision | Rationale |
|---|---|
| Ryan: Codex on -29 round 2, then all three reviewers on round 3, then the mirror | Codex found the Texas succession defect the other two missed |
| Ryan: send the franchise base to Kyle (K-15) | Kyle ruled the fixed list; only he knows whether ordinances exclude a charge for some classes only |
| Tax work split into -30, -31 and -32 | -30 does not wait on Kyle, and the other two build on it |
| A levy is keyed by place kind and code, not row id | The template requires text keys, and a code key survives succession |
| No draft levy rows | A proposal bills nothing; approval is the insert, which records its approver |
| One column per base (`is_taxable_default` = sales tax, `in_late_penalty_base` new) | A NOT NULL column with no default is required by itself |
| `sales_tax_rate` moved to percent by a platform repair | No fact exists yet; AC-45 |

## Current State

**Working:**
- `tally` holds -23, -28 and -29 (rebuilt 2026-11-05). CI on `tally` without -30: 55/55.
- -30 r0 applies strictly twice. Battery -30: 80/80.

**Broken:** with -30 pending, the 7 older tests listed under Not Yet Done fail. -30 is **not** in `ci.sh`'s PENDING list (taken back out at wrap-up), so CI stays green for the other streams.

**Uncommitted changes:** none after the wrap-up commit.

## Code Context

```sql
-- sql/v5.4.2-30-tax-levies-and-taxability.sql (r0)
public.end_as_known(p_end date, p_closed_at timestamptz, p_at timestamptz) RETURNS date
public.tax_kinds (tax_kind text PK, place_kinds text[], description, source_note)    -- seeded: sales_tax
public.tax_levies                                     -- rule-terms tariff; area key (place_kind, place_code, tax_kind)
  terms tax_levy v1: {rate_percent 0..100 (4 dp in insert check), stacking_position int >=1,
                      computed_on [tax_kind] (required; [] = none), source_kind statute|ordinance|tariff,
                      citation (has alnum), reaches_residential bool}
public.tax_levy_insert_check(jsonb)                   -- own tenant; kind levies tax; place covers dates; 4 dp; computed_on
public.tax_levy_as_of(tenant uuid, state text, place_kind text, place_code text, tax_kind text,
                      service_type text, system_kind text, on date, recorded_at timestamptz) RETURNS SETOF tax_levies
public.tax_levy_reference_gaps(tenant uuid, on date)
  RETURNS TABLE (levy_id, place_kind, place_code, levy_rate_percent, reference_rate_percent, reference_source)
rate_item_versions: in_late_penalty_base NOT NULL (new); no defaults on is_taxable_default, is_a_tax, applies_to_customer_types;
  CHECK rate_item_versions_customer_types_check; trigger b_enforce_late_penalty_base
regulatory_surcharge_rules: trigger c_enforce_surcharge_rule_late_penalty_base
customer_tax_exemptions_service_types_check; should_charge_tax raises 22004 on a NULL service type
public.premise_places_as_of(location uuid, on date, axis text, recorded_at timestamptz)  -- 3-arg form = 4-arg at now()
customers.state_agency_basis + customers_state_agency_basis_check; logger attribute 'state_agency_basis'
```

The battery plants "recorded earlier" rows by disabling a table's guard (owner only, rolled back): `rule_row_history` on `tax_levies`, `a_enforce_premise_place_membership`, `a_enforce_place`. The insert check runs after the template validates the document, so a malformed document is refused with "the document is not a valid tax_levy v1".

## Resume Instructions

1. Port the seven tests (Not Yet Done, item 1).
   - Then put -30 in `ci.sh` (`PENDING` and the battery loop) and run `tests/ci.sh`.
   - Expected: `ci: all pass` (56 steps or so).
   - If a battery fails on `customer_attribute_history` counts, it's the logger's new tenth attribute: each customer insert now logs one more initial row.
2. Commit the ports and the `ci.sh` change; post the board note to money.
3. Write `mutations-30.sh` and run it (database names `m30`, `r30`). Expected: every mutation caught at its named check.
4. Freeze round 1 under `tests/v5.4.2-30/review/`, write the brief and Codex prompt (copy -29's shape), and run Opus, Fable and Codex.

## Warnings

- Revoke TEMP after every TEMPLATE clone. At most two mutation runs at once.
- Never edit frozen review copies or `tu.sql`'s mirrored bodies.
- Don't put -30 in `PENDING` before the ports: it breaks CI for the other streams.
- Kyle's batch 2 answer 3b (late-charge tax depends on the tariff's form) and the penalty engine are the money stream's.
- Before writing or reviewing patch code, read the index at the top of `sql/PATCH-LESSONS.md`.
- Ryan wants plain language with no shorthand codes in what he reads, and one decision per message.
