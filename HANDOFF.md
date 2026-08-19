# Handoff: Phase 1 nearly complete — five patches landed in one session (v5.4.0-01 → -05)

**Generated**: 2026-08-19 (evening)
**Branch**: tally-utility `main` (pushed) · gas-billing-memory working branch **`ryan`** (pushed; **`origin/main` is now 11 commits behind `ryan`** — see Warnings)
**Status**: In Progress — four of five Phase 1 migration sets landed; next is the PGA set (item 14), the last Phase 1 item, then Phase 2

## Goal

Bring `sql/tu.sql` (the only enforcement artifact — no application code exists) to parity with the spec corpus per `gas-billing-memory/application/schema-parity-plan.md`. Target: vanilla PostgreSQL on AWS. Ryan owns the schema.

## Completed (this session, 2026-08-19)

Five patches, each following the full per-patch loop (draft → mirror → rebuild → runtime-test → re-grade → CHANGELOGs both repos → commit+push both). All deploy clean, zero error lines, on postgres:16 via `postgres/Dockerfile`. Every mirror is a **pure append at EOF** — no pre-existing line number ever shifted; anchors 337/3600/3679 verified each time.

- [x] **v5.4.0-01 — app role, GRANTs, FORCE RLS.** Ryan's decision: split-role model. `tally_app` (NOLOGIN privilege bundle; production LOGIN users get membership), full DML/EXECUTE GRANTs + `ALTER DEFAULT PRIVILEGES` (future tables inherit grants automatically — proven working in -03/-04), FORCE ROW LEVEL SECURITY on all 58 RLS tables. **First end-to-end RLS test ever**: fail-closed (no GUC → 0 rows), tenant-scoped, cross-tenant INSERT rejected, platform_admin via policy branch. CI-116 re-graded `structurally-enforced (as of v5.4.0-01)`. Closed parity-plan Phase 0.5.
- [x] **v5.4.0-02 — meters & reads (items 1, 2, 8, 9; D3-1/D3A-3/D3A-4).** `meters.rollover_point` (NULL → 10^`dial_count` fallback), `meters.meter_pressure_class` (`residential_base`/`elevated`), D3A-3 skip-reason enum CHECK on `read_cycle_meters.skip_reason` (`other` requires `notes`), tamper columns on `meters` (`tamper_flag` + required-when-set `tamper_reported_at`/`tamper_signal_source` + `tamper_reason`). CI-023 re-checked, token stays `unenforced-gap` (completeness = A-20's job; `temperature_compensated` unruled, still absent).
- [x] **v5.4.0-03 — rating & WNA (items 4–7; D7-2/D5-2/T-4/T-3).** `regulatory_class` **NOT NULL** on `rate_items` AND `adhoc_charges`; new `jurisdictions` table (WNA flag + variant pointer → `wna_zones`) + `service_locations.jurisdiction_id` (first premise jurisdiction FK, A-5); WNA clamp config on `wna_zones` (floor/ceiling/basis, basis-required + floor≤ceiling CHECKs) + append-only `wna_clamp_events` (bounds snapshotted at clamp); `prorate_tier_breakpoints` default → `true` (existing-row review vacuous — no data exists anywhere). CI-050/CI-108/CI-020 re-checked, tokens unchanged.
- [x] **v5.4.0-04 — A-11 program-enrollment substrate + item 10 (D8-2).** The locked design executed verbatim: `program_types` (platform-global, 11 seeds, NO RLS, **read-only for tally_app** via REVOKE), `customer_program_enrollments` (lifecycle enum, attestation columns, supersede lineage, jsonb payloads with object-shape CHECK only, full A-11 index set incl. one-active-per-type partial UNIQUE), three guard triggers (`enforce_enrollment_customer_immutable`, `validate_enrollment_supersedes_chain`, `recompute_do_not_disconnect`), **D8-2 `expiry_type` calendar|event** (bankruptcy = event-terminated, NULL end date), **dropped `customers.disconnect_protection_*` (4 columns)**, `compliance_statistics` rebuilt with LEFT JOIN LATERAL (surface preserved). Nine CI entries updated: CI-059 → `requires-application-discipline`; CI-061/064/065/066 → `partially-structurally-enforced`; CI-060/062/063/082 re-checked. A-11 marked LANDED.
- [x] **v5.4.0-05 — pipeline & events (items 11–13; D3C-6/D1-3/D3B-1/2).** Dry-run isolation now DB-enforced: guards on `invoices`, `account_ledger`, read-lock transition, `billing_runs` status (no `approved`/`posted` for dry runs); `dry_run` dropped from `run_type` enum; `is_dry_run` immutable. Reversal-chain depth >3 auto-emits `invoice_events` row (`reversal_chain_depth_exceeded`, `{depth, severity: medium}`) via trigger — depth 3 verified silent. D3B-2 gate columns `meters.zone_/pressure_class_confirmed_at/by` (pair CHECKs); D3B-1 `meter_deployments.fp_mismatch_confirmed_at/by/reason` (all-or-nothing CHECK). No register re-grades (no CI grades these directly); three workflow docs' catalog refs flipped to landed.

**Verified current state**: 63 tables / 62 policies / 61 FORCE-RLS / 207 CHECKs / tu.sql **12,138 lines**. GBM ingestion sections **AE–AI** added (queue now through AI).

## Not Yet Done

- [ ] **NEXT: PGA set (item 14, D3D-1)** — monthly reconciliation table (immutable input-snapshot rows) + threshold config. Last Phase 1 item. Read D3D-1 in `wu5-wu6-kyle-decisions-2026-07-10.md` and the `pga-application.md` / `pga-deferred-account-and-trueup.md` decision tables first. Remember: PGA = annual deferred-account settlement, WNA = monthly-settled (D5-1) — do not conflate.
- [ ] Phase 2 factual-defect hardening (six items, plan §2.1–2.6). Note 2.5 (ledger reversal lineage FK) and 2.3 (cycle guards, incl. lineage columns) interact with -05's depth-event walk (currently capped at 50 links, no cycle guard).
- [ ] Phase 0.4 (non-blocking): Kyle's Opus-session patch archive.
- [ ] Kyle's answers to the 8 open briefs; correction queue still parked behind them.
- [ ] GBM `origin/main` catch-up — Ryan's call, never unprompted.

## Failed Approaches (Don't Repeat These)

All were fixture/test errors, not schema errors — each cost one retry:

- **Non-hex characters in test UUIDs**: `'...00000000rea1'` → `invalid input syntax for type uuid` → use digit-only suffixes.
- **Guessing enum values in fixtures**: `calculation_type='per_unit'` (real: `per_unit_usage`), `charge_type='nsf_fee'` (real list has `returned_payment_fee`, `tap_fee`, …), `rate_schedules.schedule_code` (real: `code`/`name`) → **query `pg_get_constraintdef` / `information_schema.columns` BEFORE writing fixture INSERTs**; a wrong sibling value masks the constraint under test (the first `regulatory_class` test failed on `calculation_type`'s CHECK instead).
- **Invoices without location**: `invoices_check` requires `location_id IS NOT NULL OR is_consolidated` → always supply `location_id` in invoice fixtures.
- **`meter_deployments.deployment_number` is an integer**, and **creating a meter auto-creates deployment row #1** (existing trigger) → fixture deployments start at 2.
- **Docker host-port bind** (carried forward): run with no `-p`; use `docker exec tally-pg psql -U tally -d tally`.

## Key Decisions

| Decision | Rationale |
|----------|-----------|
| **Pure-append mirrors** (supersedes "preserve 11,351 lines") | Appends run last and win; zero pre-existing line numbers shift, so all register citations stay valid with no recount ritual. Even column DROPs work as appends. |
| Split-role model: `tally_app` runtime + owner-as-migrator; FORCE RLS everywhere (Ryan) | Role boundary beats session-variable-only admin path; FORCE closes CI-116. No BYPASSRLS role exists — cross-tenant tooling uses the `is_platform_admin()` policy branch. |
| `regulatory_class` on BOTH `rate_items` and `adhoc_charges`, NOT NULL no default | One-off charges are classic unregulated debt; classifying only rate_items reproduces CI-050's failure mode. NOT NULL is safe only because no populated DB exists — a populated DB would need a backfill step first. |
| `jurisdictions` is the D5-2 WNA record, NOT A-8's tax_jurisdictions | A-8 needs date-effective history nobody ruled on; building it now would decide open questions by inertia (the D3-2 lesson). Two jurisdiction-ish tables will eventually exist — deliberate. |
| WNA variant pointer targets `wna_zones` | A variant's mechanics (factors, window, clamp) live in a wna_zones row; Atmos's four variants = four zone rows. |
| Tamper columns on `meters`, not the read record | Life-of-meter investigation state feeds the Critical portlet; per-read signals already have `meter_readings.has_anomaly`/`anomaly_types`. `tamper_confirmed` deliberately NOT a column (investigation outcome). |
| `program_types` read-only for `tally_app`; protective flag seeded from the old CHECK list (8 true, 3 new false) | Global RLS-less table must not be writable via runtime credential. Flag is ops-editable reference data by design — if `elderly_disabled` proves deposit-waiver-only, it's a row update. |
| `is_dry_run` immutable (extension beyond ruling) | Blocking approved/posted alone leaves the flip-to-real laundering hole; CI-119 already says a re-run is a new run row. |
| Depth event as DB trigger though D1-3 allowed app-layer-only | Belt-and-braces philosophy; never blocking. Walk capped at 50 links pending Phase 2.3 cycle guards. |
| CI-029's Fp=1.0 structural CHECK NOT drafted | Still an open flag to Kyle (gas-conversion table row 3); drafting it would become the ruling. |
| All new master-data columns nullable | CI-023's completeness rule belongs to A-20's exception queue, not NOT NULLs. |

## Current State

**Working**: tu.sql v5.2.1+v5.4.0-00→-05 deploys clean; container `tally-pg` running (ephemeral, schema-fresh each start, has test fixtures from -05 testing); both repos fully committed and pushed.
**Broken**: Nothing.
**Uncommitted changes**: None (GBM `Clippings/` untracked on purpose — never commit it).

## Code Context

```sql
-- Per-patch skeleton (see any of sql/v5.4.0-0{1..5}-*.sql for the format):
-- header: Authority / CI entries / Drafting decisions / Idempotent / Line count
-- body: idempotent DDL (ADD COLUMN IF NOT EXISTS; DROP CONSTRAINT IF EXISTS + ADD;
--        CREATE OR REPLACE FUNCTION; DROP TRIGGER/POLICY IF EXISTS + CREATE)

-- Mirror ritual (pure append; HDR_END = 3rd '^-- ====' line of the patch):
--   { banner; tail -n +$((HDR_END+1)) sql/v5.4.0-NN-slug.sql; } >> sql/tu.sql
-- Rebuild + verify:
--   docker rm -f tally-pg; docker build -q -t tally-postgres -f postgres/Dockerfile .
--   docker run -d --name tally-pg -e POSTGRES_PASSWORD=tally tally-postgres; sleep 14
--   docker logs tally-pg 2>&1 | grep -ci 'error\|fatal'   -- must be 0

-- RLS smoke context:
--   SET app.user_id = '<users.id>'; SET ROLE tally_app;   -- superuser tally bypasses RLS
-- New tables need: RLS ENABLE + FORCE + policy tenant_isolation
--   USING (public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id()));
-- Grants arrive automatically via v5.4.0-01's ALTER DEFAULT PRIVILEGES.
```

Non-obvious: `check_function_bodies = off` preamble still required. Trigger firing order is alphabetical by name (relied on: `dry_run_no_read_locks` < `enforce_reading_validation_workflow`). `users` fixture NOT NULLs: id, tenant_id, display_name, email (+role).

## Resume Instructions

1. Read `gas-billing-memory/application/schema-parity-plan.md` (current through v5.4.0-05) and the D3D-1 ruling + both PGA decision tables.
2. Draft `sql/v5.4.0-06-pga.sql`: monthly reconciliation table (immutable input-snapshot rows — consider the `wna_clamp_events` append-only pattern and whether an UPDATE-blocking trigger is warranted for "immutable"; that's a drafting call to surface) + threshold config. New table checklist: PK, `UNIQUE (tenant_id, …)` per CI-117, FKs, indexes, `set_updated_at` only if mutable, RLS ENABLE+FORCE+policy.
   - Expected: rebuild zero errors; runtime tests for every new CHECK/trigger, positive AND negative cases; RLS smoke as `tally_app`.
3. Full bookkeeping loop: DEPLOY-VERIFICATION.md § + counts; re-grade exactly the CI entries named in the patch header; ingestion Section **AJ** (queue is through AI); CHANGELOG entries in BOTH repos; commit both; GBM pushes to `origin ryan` (`git -C`, never cd-chains).
4. Then the first non-preliminary parity-plan revision: sequence Phase 4 (the plan says nothing in Phase 4 starts before Phase 1 lands — after item 14, Phase 1 IS landed).

## Setup Required

Docker only: `docker build -t tally-postgres -f postgres/Dockerfile . && docker run -d --name tally-pg -e POSTGRES_PASSWORD=tally tally-postgres` (no `-p`, host 5432 taken).

## Warnings

- **GBM `origin/main` is 11 commits behind `ryan`** — Kyle reads `main`. Catch-up is Ryan's explicit call only.
- **tu.sql edits are APPEND-ONLY** (12,138 lines now). Never edit the body — the original CREATE TABLE text of since-dropped columns (e.g., `disconnect_protection_*`) remains in the body as history; the appends win at execution. Verify anchors 337/3600/3679 after every append.
- **Never `git add -A` in GBM** (`Clippings/` trap).
- Every GBM canonical-data change needs a `wiki-ingestion-pending.md` section (through **AI**) + both CHANGELOGs.
- Judgment-gated items (plan Phase 3) still wait on their named questions — **do not draft DDL for them**. CI-029's structural CHECK is explicitly parked with Kyle.
- The 77 untested `requires-application-discipline`/`unenforced-gap` entries stay untested without cause (nine were legitimately touched this session because patches named them).
- `regulatory_class` NOT NULL means any future *populated* database needs a backfill before -03 applies. Fresh deploys unaffected.
- Texas-only launch remains the scope discipline. PGA ≠ WNA settlement models (annual-deferred vs. monthly-settled).
