# Review round 4: v5.4.2-19 — hardening batch 1 (close the holes in what is already built)

You are one of three independent reviewers (Opus, Fable, Codex). Round 3 verdicts: Opus ready, Fable ready, Codex not yet. All three found one shared item: a cited pending payment could move to another customer. This round checks r4.

**Frozen artefacts** (repo `/Users/ryanscomputer/code/tally-utility`; check the hashes and say if they differ):
- patch `tests/v5.4.2-19/review/patch-19-frozen-r4.sql` — md5 `f1d234f0d3b882fbd10ce9bfee39d4c4` (1,561 lines)
- battery `tests/v5.4.2-19/review/battery-19-frozen-r4.sql` — md5 `9a80d4a7e52ce732e69917874d514f44` (171 checks)
- race script `tests/v5.4.2-19/races/cycle-19.sh` — md5 `b7367898c6f8b84fd4733a663e566213` (C1–C8; C8 is new)
- CI `tests/ci.sh` — md5 `a5e640c0a0ae45e04a0e21fc04e9bc51` (unchanged)
- round 3: `patch-19-frozen-r3.sql`, `battery-19-frozen-r3.sql`, and the reviews `opus-r3.md`, `fable-r3.md`, `codex-r3.md` in the same folder
- the live schema: `sql/tu.sql`

**State at freeze:**
- Strict application twice; the second run is skipped by the gate.
- 171/171 battery checks, C1–C8, and the full CI suite (25 steps) pass.
- Mutation runs, each on a fresh clone:
  - restoring the single-column lineage FKs fails P9c;
  - dropping `meter_readings_consumed_flag_check` fails RF2.

**What changed since r3** (header "Revision r4" paragraph):
- **Codex B1 / Opus S1 / Fable S1:** refund and replacement lineage are now composite FKs `(pointer, tenant_id, customer_id) → payments (id, tenant_id, customer_id)`, backed by a new `UNIQUE (id, tenant_id, customer_id)`.
  - The cited row's customer cannot change while anything cites it (NO ACTION), and a citation and a move serialise on the key lock (race C8).
  - `payments_lineage_not_self_check` stops a row citing itself.
  - The r3 lineage trigger stays for its visibility check (RLS).
- **Opus r3 N3 / Fable XS2:** `meter_readings_consumed_flag_check`: locked or void_released requires `billing_period_locked`, for every role, history loads included.
- **Fable r3 S3 / Opus N4:** a finished import job also freezes `import_summary`, `validation_errors` and `completed_at`, as a snapshot at finish. Codex r3 S2: more import tests (J10c–h).
- **Fable r3 S2 / Opus N1:** the money-out index comment covers every negative row (chargebacks included). R17 states intake's duty on a refund-index unique_violation and on ACH re-presentment ids.
- **Opus N5:** `trg_populate_reading_location` is ENABLE ALWAYS.
- **Opus N6:** RW3 uses the valid value `'other'`.
- **RF2's fixture:** an estimated read, to avoid the pre-existing -05 meters-pointer defect (Fable r1 N6, which will be fixed separately).

## What to do
1. **Round-3 closure.** For every blocking and should-fix item in the three r3 reviews: closed / not closed / accepted as a residual, with the r4 line or a reproduction.
2. **New code.**
   - Do the composite FKs break any legitimate flow? Check correcting a pending refund's own customer together with its pointer; a payment that has both pointers; superuser loads; and every writer of `payments` in tu.sql.
   - Is dropping and replacing the two named FKs safe for anything that references them by name?
   - The new CHECK against every writer of `meter_readings.validation_status` in tu.sql, including void_invoice, the exception gate and correction flows.
   - The import freeze, including `completed_at`: does any path set `completed_at` after the terminal status?
3. **Tests.** Does each new case fail without its guard? Does C8 prove that B was blocked by A?
4. Verdict: **ready** / **not yet** (list blocking items). Separate findings: blocking, should-fix, note. Ground every claim in file:line or a reproduction.

## How to probe (Opus and Fable)
Never touch the `tally` or `postgres` databases or the repo files (except your own report file). Make your own clones, prefixed with your name:
```
docker exec tally-pg psql -U tally -d postgres -c "CREATE DATABASE <you>19 TEMPLATE tally"
docker exec tally-pg psql -U tally -d <you>19 -c "REVOKE TEMP ON DATABASE <you>19 FROM PUBLIC, tally_app, tally_core"
(echo "SET search_path = ''; SET check_function_bodies = on;"; cat tests/v5.4.2-19/review/patch-19-frozen-r4.sql) | docker exec -i tally-pg psql -U tally -d <you>19 -v ON_ERROR_STOP=1 -q -f -
docker cp tests/v5.4.2-19/review/battery-19-frozen-r4.sql tally-pg:/tmp/<you>b.sql && docker exec tally-pg psql -U tally -d <you>19 -v ON_ERROR_STOP=1 -q -f /tmp/<you>b.sql
```
`CREATE DATABASE … TEMPLATE` drops the database ACL, hence the REVOKE. Write probes as `tally_app` with `SET LOCAL app.user_id`. For races, run `tests/v5.4.2-19/races/cycle-19.sh` against your own throwaway clone with the patch applied. Drop your databases when done.

## Output
Write the full review to `OUTPUT_PATH`. Final reply SHORT (under 2,500 characters): verdict, blocking items (one line each with file:line), top should-fix.
