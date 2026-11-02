# Review brief: v5.4.2-28 r1 — rates small fixes (the state-agency time zone, dated rider dependencies, four-decimal rates)

**Date:** 2026-11-02. **Kind:** patch review, round 1.
**Reviewers:** Opus, Fable and Codex, independently. Do not read each other's round-1 files.
**Stream:** rates (`~/code/tally-utility-rates`). Read the repo at that path: the frozen files below are there. The other stream's clone (`~/code/tally-utility`) may be at a different commit.

## Frozen files

Review exactly these files. Check the hashes first; if one differs, stop and report it.

| File | md5 |
|---|---|
| `tests/v5.4.2-28/review/patch-28-frozen-r1.sql` | `54271dccc92c10057625be74c85c0b33` |
| `tests/v5.4.2-28/review/battery-28-frozen-r1.sql` | `93b6aa3dc354f5af28811be055264232` |
| `tests/v5.4.2-28/review/mutations-28-frozen-r1.sh` | `c2eb5a80bf073330897bbd9ad6d0a2c0` |
| `tests/v5.4.2-28/review/older-tests-28-frozen-r1.diff` | `4cb633eaf9cddde75bf0388f8c41401a` |

Today the live copies (`sql/v5.4.2-28-rates-small-fixes.sql`, `tests/v5.4.2-28/`) are identical to the frozen ones. `older-tests-28-frozen-r1.diff` is every change -28 makes to earlier tests: batteries -19 and -21, races `cycle-19.sh` and `labels-21.sh`, and `tests/ci.sh` (-28 joins PENDING).

## What the patch does

Three independent sections; the patch header explains each, with its residual consequences.

1. **The state-agency check's day boundary (CI-010).** The pipeline safety fee check (`assert_surcharge_line`, -07/-08) asked whether the account was a state agency at midnight `America/Chicago`. It now asks at midnight in the bill's own zone: new `invoice_time_zone_as_of(invoice, date)` (the premise's zone via -16's `premise_time_zone_as_of`; a consolidated parent's live children must all answer and agree, else it refuses). `customer_is_state_agency_as_of` takes the zone as a required third argument; the two-argument form is dropped. The zone is read only for an exempting rule and a non-zero line.
2. **Rider dependencies dated in place (CI-101).** `rate_item_dependencies` joins A-1 group 2 (the `rate_schedule_items` pattern): in-force dates, recorded-at / recorded-until, frozen once written by the shared `enforce_bitemporal_assertion`, correction = close as superseded + successor, retraction = close as retracted. -21's `retired_*` columns are dropped. `changed_by` / `closed_by` are stamped from the session. One open row per link per valid day (exclusion). The cycle walk reads open rows whose dates overlap the new row's (conservative, stated). New read `rate_item_dependencies_as_of(schedule, day, recorded_at)`. `assert_wave1_guard_invariants` learns the two new triggers.
3. **Rates carry at most four decimals (CI-109).** CHECKs on `rate_item_versions.rate_value`, each tier's rate in `rate_item_versions.tier_config` (jsonpath), and `rate_schedule_items.rate_override`. Columns stay `numeric(14,6)`.

## The rulings behind it

- `application/DECISION-LOG.md`, the four 2026-11-02 (-28) entries (Ryan): option 1 for the time zone (bill's premise; parent's children must agree), the meter test fee moved out (CI-091 is not in this patch), option 1 for dated dependencies, option 2 for four-decimal rates.
- Kyle K-06 (four decimals, cent half-up; no early-pay discounts) and K-02/K-03 context: `/Users/ryanscomputer/code/gas-billing-memory/application/kyle-decisions-2026-10-15-waves-1-to-7-and-texas-first.md`.
- The parity rows: `application/invariant-parity-measurement-2026-10-13.md`, `grep -n "^| CI-010 \|^| CI-101 \|^| CI-109 "`, and the 2026-10-15 update's CI-101 line.
- Read the index of `sql/PATCH-LESSONS.md` and the sections it points to for what you check.

## Known limits (accepted; listed so you can judge them, not as findings to rediscover)

- **L1. Unloaded counties refuse.** Texas is not one zone, and only El Paso and Hudspeth counties are seeded with a zone (-16). A non-zero fee line on a premise whose county lacks a `time_zone` fact is refused where -07 assumed Central. By design ("refuse, never assume").
- **L2. The cycle check is conservative across dates.** It can refuse links that never all apply on one day (battery D6). It never admits a real cycle. An exact check is a later tightening with no shape change.
- **L3. Transaction time in the battery** is read only at `now()` and just before: inside one transaction every stamp is `now()`.
- **L4. Not covered by the four-decimal check:** `invoice_line_items.rate` / `gas_commodity_rate` (the money stream's table; a board note), deposit interest rates (an annual percentage), `rate_item_history` (retired, read-only).
- **L5. `customer_is_state_agency_as_of` keeps -07's fallback:** a date before the account's first recorded value answers with that first value. Unchanged here.

## Drafting calls to check in particular

- **The consolidated parent.** Is "live child" the right set (status `<> 'void'`, same tenant)? Can a parent's children change between the zone read and the line write in a way that matters? Is a nested parent always refused?
- **The dropped two-argument function.** Does anything else (functions, views, app contracts) still call `customer_is_state_agency_as_of(uuid, date)`?
- **Trigger order on `rate_item_dependencies`.** The shared row guard (`a_enforce_bitemporal_assertion`) runs before `a_enforce_rate_item_dependency` by name. Does every path rely on that correctly (the close stamps, the frozen check, the predecessor check)? Can a caller set `closed_by` or `changed_by` and keep it?
- **The meaning change.** -21's retire becomes close-as-retracted. Is anything in -21's guarantees (no hard delete, the mutex on a retirement, the stamped closer) lost? Are the ported tests in `older-tests-28-frozen-r1.diff` still testing what they claimed?
- **The cycle walk with dates.** Is the overlap filter right with `expiry_date` inclusive (`'[]'`)? Does a successor's insert (same link, the predecessor already closed) ever see its predecessor? Is the lock order intact for a close followed by a successor in one transaction?
- **The jsonpath tier check.** Exact on `numeric`? Any shape of `tier_config` that slips past (rates nested elsewhere, a missing `tiers` key, `null` rates)?
- **Re-apply.** Each statement is meant to re-apply cleanly; section 2's precondition runs only while `retired_at` exists. Is the patch safe on a database with dependency rows?

## Results so far (reproduce them)

- **Strict apply, twice:** clean.
- **`battery-28.sql`:** all pass (77 PASS lines: Z time zone, D dated dependencies, R four decimals) on `tally` + -28 and on `tally` + -23/-25/-26 + -28.
- **`mutations-28.sh`:** 11 of 11 caught, each at its named check.
- **Batteries -19 and -21 (ported) and races `cycle-19.sh`, `labels-21.sh`:** pass on `tally` + -23/-25/-26 + -28.
- **`tests/ci.sh`:** every step passes except battery -15 case V23. That case fails identically without -28: it dates a deposit return due `2026-11-01` against a closure stamped `now()`, so it started failing on 2026-11-02 (the money stream's; a board note). Not a -28 finding.

## What to answer

1. **Does each section do what its ruling says,** and nothing the ruling did not ask for?
2. **Is there a path around any rule?** Every role (`tally_app`, `tally_core`, the owner), isolation level and statement shape.
3. **Did -28 break or weaken anything earlier** (-07/-08 surcharge rules, -16 places, -19/-21 dependencies, -20 version checks, the invariants)?
4. **Concurrency.** The dependency mutex and lock order; the zone read against concurrent child-invoice writes.
5. **The tests.** Is any claim narrower than its check, or any mutation caught for the wrong reason? What is missing?
6. **Known limits L1–L5.** Is any of them blocking?

## How to probe

**Opus and Fable** may query the running `tally-pg` read-only. For experiments, clone into your own scratch database (Opus `rv28opus`, Fable `rv28fable`):
1. `CREATE DATABASE <name> TEMPLATE tally`.
2. Revoke TEMP on the clone from PUBLIC, `tally_app` and `tally_core` right after creating it.
3. `docker cp` the frozen patch into the container and apply it strictly:

```
docker exec -e PGOPTIONS="-c search_path= -c check_function_bodies=on" tally-pg psql -U tally -d <name> -v ON_ERROR_STOP=1 -q -f <patch>
```

-23, -25 and -26 are not needed for this review (the ported -19/-21 batteries need them only for unrelated sections; run those sections' dependency parts by hand if you want them).

**Codex reviews source only.** Do not run docker, psql, `ci.sh`, the races or the mutation runner. Every database claim must be a probe file in `tests/v5.4.2-28/review/codex-r1-probes/`. Each probe runs as the owner on a fresh clone of `tally` with frozen r1 applied, ends in ROLLBACK, and prints SQLSTATE and message for each caught error with RAISE NOTICE. Keep each probe to what runs in minutes.

**Restrictions (everyone):**
- Roles are cluster-wide: do not create, drop or alter any role.
- Do not run `mutations-28.sh`; it uses the fixed name `m28`.
- Run the race scripts only against your own clone; they commit rows.
- Never modify `tally`, `sql/tu.sql` or any repo file except your output file (and Codex's probes).
- Drop your clone when done.
- Other sessions share this container (the money stream runs `m23`): do not run `tests/ci.sh`, and keep to your own clone.

## Output

Write your full review to `tests/v5.4.2-28/review/<reviewer>-r1.md` (`opus`, `fable` or `codex`). It should contain:
- a verdict: "ready" or "not yet";
- blocking items (B1…), each with the concrete path or repro;
- should-fix items (S1…);
- notes (N1…).

Mark each claim as **executed** or **predicted**. Your final message gives the verdict, the blocking items in one line each, and the file path, in several messages, each under 3 KB.
