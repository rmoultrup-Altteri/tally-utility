# Handoff: Phase 1 COMPLETE (v5.4.0-06 landed) + Phase 4 sequenced — next is Phase 2

**Generated**: 2026-08-19 (late evening)
**Branch**: tally-utility `main` (pushed, `c5f3c68`) · gas-billing-memory working branch **`ryan`** (pushed, `14f1728`; **`origin/main` is now 13 commits behind `ryan`** — see Warnings)
**Status**: In Progress — Phase 1 fully landed; Phase 4 sequenced (Ryan's decision, in the plan); next work is Phase 2's six factual-defect items

## Goal

Bring `sql/tu.sql` (the only enforcement artifact — no application code exists) to parity with the spec corpus per `gas-billing-memory/application/schema-parity-plan.md`. Target: vanilla PostgreSQL on AWS. Ryan owns the schema.

## Completed (this session, 2026-08-19 evening)

- [x] **v5.4.0-06 — PGA set (item 14, D3D-1). Phase 1 is fully landed.** Two new tables in `sql/v5.4.0-06-pga.sql`:
  - `pga_monthly_reconciliations` — one immutable row per tenant per month (supplier gas cost, billed PGA revenue, variance, running signed deferred balance, thresholds in effect at posting). Drafting calls (all in the patch header): immutability **trigger-enforced** (`enforce_pga_reconciliation_immutable`, UPDATE+DELETE raise — D3D-1's workpaper language is stronger than T-4's, and convention-only would grade requires-application-discipline); row stores `threshold_band` (none/low/medium), NOT an alert flag — crossing detection/re-alerting stay app logic over consecutive immutable rows; two self-verifying CHECKs (variance = cost − revenue; band must match the row's own snapshotted numbers, boundary `>=`, zero trailing revenue disables); tenant-level, no jurisdiction key, no per-class rows, no carrying cost (all annual-settlement = A-6 territory).
  - `pga_monitoring_settings` — one row per tenant (UNIQUE), 10.00/20.00 column defaults, optional `re_alert_interval_days` (NULL = off), mutable (`set_updated_at`).
  - Full loop done: pure-append mirror (12,138 → **12,279** lines; anchors 337/3600/3679 verified), rebuild zero errors, 16 constraint/trigger tests + 4 RLS smokes green, DEPLOY-VERIFICATION §, CI-036 re-graded `unenforced-gap` → `partially-structurally-enforced (as of v5.4.0-06)`, CI-033 re-checked (token unchanged), Appendix A-6 status-updated, ingestion Section **AJ**, CHANGELOGs both repos, both pushed.
- [x] **Phase 4 sequenced — the first non-preliminary parity-plan revision (Ryan approved 2026-08-19).** Written into `schema-parity-plan.md` Phase 4, committed (`14f1728`), ingestion Section **AK**, GBM CHANGELOG `decision` entry. The order: Phase 2 first → Wave 1 **A-4 → A-1 → A-3** (A-4 promoted: immutability triggers proven in -04/-05/-06, role/GRANT layer since -01 make it cheap) → Wave 2 **A-20 → A-21 + A-7 promoted in** (PSF is on every Texas bill) → Wave 3 A-2 (rider on `jurisdictions`) → A-9 → A-10, **A-8 HELD pending a Kyle brief** (unruled date-effective shape, D3-2 lesson) → Wave 4 A-14 → A-16+A-17 → A-13 → A-15 → A-18 → A-19, finance gate carried over (A-15 ledger-partition/GL parts + A-6 remainder behind the coda brief's finance reader).

**Verified current state**: **65 tables / 64 policies / 63 FORCE-RLS / 217 CHECKs / 61 triggers / 471 indexes / 271 FKs**; tu.sql **12,279 lines**. GBM ingestion queue through **AK**.

## Not Yet Done

- [ ] **NEXT: Phase 2 — six factual-defect items (plan §2.1–2.6), likely one or two `v5.4.1-*` patches.** Low-controversy but "flag each in a brief line rather than land silently." Items: 2.1 `final_read` in `service_orders` CHECK coverage; 2.2 `import_jobs.idempotency_key` NOT NULL + default; 2.3 cycle guards (`customers.landlord_customer_id`, `service_orders.parent_order_id`, `import_staging.depends_on_row_numbers`) — closes the 50-link cap on -05's depth walk; 2.4 `tenant_configuration_history` + date-parameterised `get_partial_period_policy()`; 2.5 `account_ledger` reversal lineage FK + reason; 2.6 `meter_readings` service-point premise or EXCLUDE on `meter_deployments` (schema has zero EXCLUDE constraints today).
- [ ] Then Phase 4 Wave 1 (A-4 → A-1 → A-3) per the now-sequenced plan.
- [ ] Kyle briefs outstanding: the 8 open briefs; NEW candidate brief needed for A-8 (tax_jurisdictions date-effective shape) before its DDL; CI-029's Fp=1.0 CHECK still parked with Kyle.
- [ ] Phase 0.4 (non-blocking): Kyle's Opus-session patch archive.
- [ ] GBM `origin/main` catch-up — Ryan's call, never unprompted.

## Failed Approaches (Don't Repeat These)

None new this session — the -06 test battery passed on the first run. All prior-session traps still apply:

- **Non-hex characters in test UUIDs** → invalid uuid syntax; use digit-only suffixes.
- **Guessing enum/column values in fixtures** → query `pg_get_constraintdef` / `information_schema.columns` BEFORE writing fixture INSERTs (a wrong sibling value masks the constraint under test).
- **Invoices without location**: `invoices_check` requires `location_id IS NOT NULL OR is_consolidated`.
- **`meter_deployments.deployment_number` is an integer** and creating a meter auto-creates deployment row #1 → fixture deployments start at 2.
- **Docker host-port bind**: run with no `-p`; use `docker exec tally-pg psql -U tally -d tally`.
- **zsh trap (new, minor)**: a bare `echo ===` in a compound command is parsed as a glob qualifier (`== not found`) — quote it (`echo '---'`).

## Key Decisions

| Decision | Rationale |
|----------|-----------|
| **Phase 4 wave order (Ryan, 2026-08-19)** — Phase 2 first; A-4 → A-1 → A-3; A-7 into the Texas wave; A-8 held | A-4 became cheap (patterns proven in Phase 1); PSF is on every Texas bill = launch-blocking; A-8's date-effective shape is unruled — drafting it would decide by inertia (D3-2 lesson). |
| PGA reconciliation immutability trigger-enforced (vs. wna_clamp_events' convention) | D3D-1 names the rows the annual true-up workpapers; no app layer exists, so convention grades requires-application-discipline. Corrections flow through next month's variance (cluster 21 row 5), never row edits. |
| Band stored, alert derived | D3D-1's alerts fire on band CROSSING — derivable from consecutive immutable rows; storing "alert fired" would bake app behavior into the snapshot. |
| Band boundary `>=`; trailing revenue 0 disables band CHECK | At the exact boundary the balance is in-band; a 0 denominator has no ruled semantics — inventing one would be a ruling. |
| Settings one-row-per-tenant, no jurisdiction key; column defaults carry 10/20 | D3D-1 says tenant-overridable; PGA under 16 TAC §7.5519 is one Texas-wide mechanism per tenant. No row = job applies same platform defaults, re-alert off. |
| CI-036 → `partially-structurally-enforced`, NOT closed | Only the monitoring slice landed; gas_purchases / per-class ledger / carrying cost / annual true-up workflow stay open under A-6 (behind the finance reader per the Phase 4 revision). |
| Pure-append mirrors; split-role model; regulatory_class NOT NULL; etc. | Carried from previous sessions — see CHANGELOG entries -01…-05. |

## Current State

**Working**: tu.sql v5.2.1+v5.4.0-00→-06 deploys clean; container `tally-pg` running (ephemeral, schema-fresh each start, has -06 test fixtures); both repos fully committed and pushed.
**Broken**: Nothing.
**Uncommitted changes**: None (GBM `Clippings/` untracked on purpose — never commit it).

## Code Context

```sql
-- Per-patch skeleton: see sql/v5.4.0-06-pga.sql (header: Authority / CI
-- entries / Drafting decisions / Idempotent / Line count; body idempotent DDL).

-- Mirror ritual (pure append; HDR_END = 3rd '^-- ====' line of the patch):
--   { banner; tail -n +$((HDR_END+1)) sql/v5.4.0-NN-slug.sql; } >> sql/tu.sql
-- Rebuild + verify:
--   docker rm -f tally-pg; docker build -q -t tally-postgres -f postgres/Dockerfile .
--   docker run -d --name tally-pg -e POSTGRES_PASSWORD=tally tally-postgres; sleep 16
--   docker logs tally-pg 2>&1 | grep -ci 'error\|fatal'   -- must be 0

-- RLS smoke context (in one txn):
--   SET LOCAL app.user_id = '<users.id>'; SET LOCAL ROLE tally_app;
-- New tables need: RLS ENABLE + FORCE + policy tenant_isolation
--   USING (public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id()));
-- Grants arrive automatically via v5.4.0-01's ALTER DEFAULT PRIVILEGES.

-- Immutability-trigger idiom (now 3x proven; A-4 will generalize it):
--   CREATE OR REPLACE FUNCTION public.enforce_<x>_immutable() RETURNS trigger ...
--   CREATE TRIGGER ... BEFORE UPDATE OR DELETE ON <t> FOR EACH ROW EXECUTE FUNCTION ...
```

Non-obvious: `check_function_bodies = off` preamble still required. Trigger firing order is alphabetical by name. `users` fixture NOT NULLs: id, tenant_id, display_name, email (+role); `tenants` needs only name+slug. No generated columns anywhere in the schema — consistency rules go in CHECKs.

## Resume Instructions

1. Read plan §2.1–2.6 in `gas-billing-memory/application/schema-parity-plan.md` plus each item's cited source (3M items, CI-118, cluster 60, CI-004/006/093, the 2026-08-13 re-grade findings, CI-027).
2. Decide the patch split (candidate: 2.1+2.2+2.3+2.5+2.6 as `v5.4.1-01`, 2.4 as its own patch since it adds a table + changes a function signature) — surface the split as a drafting note, per the plan's "flag each in a brief line" rule.
   - Expected: each item is a small diff; 2.3's cycle guards should also lift the 50-link cap comment in the -05 depth-walk function.
   - If 2.6 goes the EXCLUDE route: it's the schema's FIRST exclusion constraint — needs btree_gist; check the Dockerfile preamble supports it.
3. Full per-patch loop (unchanged): draft → mirror (pure append; verify anchors 337/3600/3679) → rebuild zero errors → runtime tests positive AND negative → re-grade exactly the CI entries in the header → DEPLOY-VERIFICATION § + counts → ingestion Section **AL** (queue is through AK) → CHANGELOGs both repos → commit both → GBM pushes to `origin ryan` (`git -C`, never cd-chains).
4. After Phase 2: Wave 1 begins with **A-4** (generalize the immutability pattern to issued invoices / posted ledger rows / operational rows — CI-012/013/014).

## Setup Required

Docker only: `docker build -t tally-postgres -f postgres/Dockerfile . && docker run -d --name tally-pg -e POSTGRES_PASSWORD=tally tally-postgres` (no `-p`, host 5432 taken).

## Warnings

- **GBM `origin/main` is 13 commits behind `ryan`** — Kyle reads `main`. Catch-up is Ryan's explicit call only.
- **tu.sql edits are APPEND-ONLY** (12,279 lines now). Never edit the body; appends win at execution. Verify anchors 337/3600/3679 after every append.
- **Never `git add -A` in GBM** (`Clippings/` trap).
- Every GBM canonical-data change needs a `wiki-ingestion-pending.md` section (through **AK**) + both CHANGELOGs.
- Phase 3 judgment-gated items still wait on their named questions — **do not draft DDL for them**. A-8 is now explicitly in that class (needs a Kyle brief). CI-029's structural CHECK stays parked with Kyle.
- The finance gate: A-15's ledger-partition/GL parts and A-6's remainder wait on the coda brief's finance reader.
- The 77 untested `requires-application-discipline`/`unenforced-gap` entries stay untested without cause.
- `regulatory_class` NOT NULL means any future *populated* database needs a backfill before -03 applies. Fresh deploys unaffected.
- Texas-only launch remains the scope discipline. PGA ≠ WNA settlement models (annual-deferred vs. monthly-settled).
