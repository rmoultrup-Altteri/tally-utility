# Review brief — v5.4.2-12, the meter test history (round 1, frozen)

| Artefact | Lines | md5 |
|---|---|---|
| `sql/v5.4.2-12-meter-test-history.sql` (= `review/patch-12-frozen-r1.sql`) | 1337 | `75e332119ad537692d61323d1c35ff78` |
| `tests/v5.4.2-12/battery-12.sql` (= `review/battery-12-frozen-r1.sql`) | 776 | `5a48b974c2742b503a96f8c27edd639b` |

The patch is **frozen** for this round. Review the frozen copy. If you believe
the file changed under you, stop and say so. **Do not edit any file in the
repo** — write repros to your own scratch space and put them in your report.

## What this patch is

16 TAC §7.45(7)(B)(v)(I) lets a Texas gas utility correct a defective meter's
readings back to "the shorter of the last six months or the last test of the
meter". Until this patch the schema kept ONE test date per meter
(`meters.last_test_date`), overwritten by each test, so the test that
DISCOVERS an error erased the one that bounds the correction. This patch is
the permanent, append-only record of every meter test, from which the
backbilling patch (A-2, renumbered v5.4.2-13, not yet re-drafted) will read
"the last test".

There is no application code in this project; `sql/tu.sql` (through v5.4.2-11)
is the only artefact, so every rule is a constraint, trigger or function.
The app connects as `tally_app` (non-owner, RLS forced, no TEMP/CREATE).

**Authority:** Kyle's rulings R-31 and R-34…R-36 with findings F-2…F-5 and
erratum E-1 — `gas-billing-memory/application/kyle-decisions-2026-09-22-a2-straddle-and-meter-test-anchor.md`
(and E-1 in `kyle-decisions-2026-09-23-a2-override-and-cause-freeze.md`).
Drafting spec: `gas-billing-memory/application/ci091-meter-test-history-implementation-brief-2026-09-22.md`.
Ryan chose the test_kind list (D-2) on 2026-09-23. Read Kyle's 09-22 record
§1 (the MAX() arithmetic) and R-34–R-36 before judging the governing-test
function and the cutover gate.

## What lands (sections of the patch)

1. `UNIQUE (id, tenant_id)` on `service_locations` and `users`.
2. Precondition: refuses to apply if any meter carries `last_test_date` /
   `last_test_result` with no history behind it.
3. `tenants.cutover_date` — migrated tests must be dated on or before it; it
   may move but never below a migrated test already loaded.
4. `meter_accuracy_thresholds` — platform-fixed (no tenant_id, tally_app
   SELECT only), date-effective, keyed (state, service_type). Seeded TX gas 2.0%.
5. `meter_test_error_pct()` — the ONE error formula.
6. `meter_tests` — append-only. The caller submits raw readings in
   `load_results` (jsonb); the database derives the outcome. Caller-supplied
   derived columns are REFUSED.
7. `meter_test_load_results` — written only by meter_tests' AFTER INSERT
   trigger (trigger-depth fence), append-only, `error_pct` generated.
8. The BEFORE INSERT guard (`enforce_meter_test_record`) and AFTER INSERT
   (`meter_test_after_record`).
9. The pointer: `meters.last_test_date` / `last_test_result` /
   `test_history_absence` maintained from history; direct writes refused.
10. `meter_test_absence_declarations` — append-only attested_none / unknown.
11. `meter_governing_test(meter, anchor)` — R-34's governing test + R-36 gate flag.
12. `meter_test_history_gaps` — invoker-rights gap report view.
13. Residuals R1–R12 (read them — they are what I already know).
14. AC-32 tail.

## Verification already done (re-run it; do not take my word)

- Strict apply ×2 (`search_path=''`, `check_function_bodies=on`) on a fresh
  `TEMPLATE tally` clone — clean and idempotent; the AC-32 assertion passes.
- `battery-12.sql`: **91 PASS**, zero failures.
- Regressions on the patched clone: battery-09 **28**, battery-10 **58**,
  battery-11 **41** — each at its recorded count.
- **Mutation check** — five guards broken one at a time, each caught by the
  check written for it: threshold `<=`→`<` (A1), load-row fence removed (B4),
  pointer ordered by insertion (C2), governing test `<`→`<=` (F1), caller
  outcome allowed (A7).
- Catalog delta: +4 tables, +1 view, +13 functions, +13 triggers,
  +3 policies, +12 FKs.

```sh
docker exec tally-pg psql -U tally -d tally -c "CREATE DATABASE r12x TEMPLATE tally"   # pick your own name
docker cp tests/v5.4.2-12/review/patch-12-frozen-r1.sql tally-pg:/tmp/r12x.sql
docker exec -e PGOPTIONS="-c search_path= -c check_function_bodies=on" tally-pg \
  psql -U tally -d r12x -v ON_ERROR_STOP=1 -q -f /tmp/r12x.sql
docker cp tests/v5.4.2-12/review/battery-12-frozen-r1.sql tally-pg:/tmp/b12x.sql
docker exec tally-pg psql -U tally -d r12x -v ON_ERROR_STOP=1 -f /tmp/b12x.sql 2>&1 | grep -E 'PASS|FAIL|ERROR'
```

`tally-pg` has NO host port — use `docker exec` only; connect as `-U tally`
(there is no `postgres` role). Only database `tally` exists; clone it, never
write to it. Drop your clone when done. To act as the app inside a
transaction: `SET LOCAL app.user_id = '<users.id>'; SET ROLE tally_app;`.
Note: clones HOLD TEMP for tally_app (CREATE DATABASE … TEMPLATE does not copy
datacl) — the deployed DB revokes it; do not report "tally_app can create a
temp function" as a finding (R10 records it).

## One defect I found and fixed before freezing

**The caller could choose the threshold its own test is judged by.** The
first draft resolved the threshold state from `coalesce(location_id,
meter.location_id)`, and `location_id` may be any location in the meter's
deployment history — including one in another state with a looser figure.
Now the state is always the meter's current location's, and a named location
in a different state is refused (battery D3b). This is the shape I most want
you hunting: **anything the caller supplies that decides which rule applies,
or what the result is.**

## Where I most want an adversarial read

1. **Can a result be recorded that the readings do not support?** The outcome
   is derived from `load_results`. What can the caller still steer? Omitting
   the failing load point and submitting only passing ones? Choosing
   `inconclusive_reason` to avoid a failing result (it is refused beside
   readings — but a tester can simply not submit readings)? Recording a
   failing test as `migrated_date_only` with `outcome = 'accurate'` after
   cutover (should be refused — is it)? Tell me which of these the schema can
   and cannot close, and whether any closable one is open.
2. **Supersession as a rewrite.** A failing recorded test can be superseded
   by a row that says anything — including a weaker `record_basis`, a
   different date, an accurate result. The pointer and `meter_governing_test`
   then forget the original. The evidence-citation guard is deferred to -13
   (R7). Is supersession without any constraint on what may supersede what a
   hole NOW, before -13 exists? What is the narrowest rule that closes it?
3. **The trigger-depth fences** (load rows; the meters pointer). Enumerate
   every existing trigger in tu.sql that runs at depth ≥ 2 on `meters` or
   could INSERT into `meter_test_load_results`. Is there any path by which
   tally_app gets a depth-2 write of `last_test_date`, `last_test_result` or
   `test_history_absence` other than this patch's own triggers?
4. **Concurrency.** (a) Two tests for one meter concurrently — pointer and
   `entered_out_of_order` (the meter row is locked FOR UPDATE in the BEFORE
   trigger). (b) A migrated insert racing a `cutover_date` change (tenant row
   FOR SHARE vs the UPDATE). (c) Deadlock against ordinary meter updates
   (AMI sync writes `ami_last_sync_at` often) or against the existing
   `sync_meter_deployments` trigger. Two-session repros please.
5. **`meter_governing_test`.** Strictly-before semantics; supersession;
   invisible meters; the R-36 gate boundary (`anchor < cutover + 6 months`,
   month-end arithmetic — e.g. cutover 2026-08-31); undeclared absence gating
   like unknown. Is it truly impossible for it to return a date derived from
   anything but `meter_tests`?
6. **The cutover invariant.** R-36's gate lapses at cutover + 6 months because
   every migrated date is ≤ cutover. Can a migrated-provenance date reach the
   window after the gate lapses by any route — a `recorded` row back-dated
   before cutover, supersession of a migrated row by a recorded one with the
   same date, a cutover moved later after the gate lapsed? Does that break
   Kyle's §1 argument?
7. **Numeric exactness.** The derivation and the stored `error_pct` must agree
   bit for bit. The intake refuses >4 decimals and ≥1e10. Is there any input
   (exponent notation in JSON, `-0`, very small standard volumes) where they
   diverge, or where the derivation errors instead of refusing cleanly?
8. **Precondition and idempotency.** Apply on a clone that already has test
   rows and pointer values; apply twice; any path where the precondition
   passes but leaves an unbacked pointer.

## Rules of engagement

- Severity CRITICAL / HIGH / MEDIUM / LOW, each with a reproduction I can run.
- For every finding, separate the **finding** from your **proposed fix**, and
  say whether you measured the fix.
- "This is fine but undocumented" is LOW; name the line.
- **Out of scope by ruling:** the fee rule (R1), scheduling/alerting (R-31),
  test disputes, the migration loader, enforcement of the R-36 gate and the
  evidence-citation guard (both A-2's, -13). A finding that these are missing
  is not news; a finding that this patch's FACTS for them are wrong is.
- Do not propose reading `install_date`, `test_interval_months` or
  `next_test_due_date` for any purpose — R-31 / R-35 forbid deriving a test
  date from them.
