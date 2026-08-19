# Deploy verification — tu.sql

**Current: v5.2.1 + v5.4.0-00 through v5.4.0-04, verified 2026-08-19.** Deploys **clean, zero errors** on fresh PostgreSQL via the repo harness (`postgres/Dockerfile`, base `postgres:16`, `check_function_bodies = off` preamble). Counts after v5.4.0-04: **63 tables** / **62 policies** / 61 FORCE-RLS / role `tally_app` present / 11 seeded `program_types` rows / 4 `customers.disconnect_protection_*` columns dropped / `compliance_statistics` rebuilt. tu.sql is now **11,966 lines** (11,351 baseline; all patch mirrors are pure appends at EOF, so every pre-existing line number — including anchors 337/3600/3679 — is unchanged and all register citations remain valid).

## v5.4.0-04 — programs & lifecycle: A-11 substrate + item 10 (D8-2)

`program_types` (platform-global, no RLS, **app-role read-only** — DML revoked from `tally_app`) and `customer_program_enrollments` (RLS + FORCE, full A-11 index set incl. the one-active-per-type partial UNIQUE and GIN on `enrollment_data`), three guard triggers, the `do_not_disconnect` denormalization, single-slot column drop, matview rebuild with `LEFT JOIN LATERAL`. Behavioral suite, all green:

| test | result |
|---|---|
| pending enrollment | `do_not_disconnect` stays false; flips true on activation |
| second active enrollment, same type | rejected (`idx_cpe_one_active_per_type`) |
| supersede flow (superseded → new active with lineage link) | works; flag stays true |
| supersede link crossing program_type | rejected (`validate_enrollment_supersedes_chain`) |
| `customer_id` UPDATE | rejected (`enforce_enrollment_customer_immutable`) |
| cancel last protective enrollment | flag flips false |
| active `budget_billing` (non-protective) | flag stays false |
| `enrollment_data` array / end<start / bad expiry_type | each rejected on its named CHECK |
| D8-2: bankruptcy, `expiry_type='event'`, NULL end date | inserted; flag true |
| matview refresh | shows `bankruptcy_automatic_stay` / `permanent` (surface preserved) |
| RLS as `tally_app` | enrollments tenant-scoped; `program_types` readable (11 rows) but INSERT → permission denied |

## v5.4.0-03 — rating & WNA set (backlog items 4, 5, 6, 7; Kyle rulings D7-2, D5-2, T-4, T-3)

New objects: `jurisdictions` and `wna_clamp_events` tables (both RLS + FORCE + `tenant_isolation` policy; grants arrive via v5.4.0-01's default privileges), `regulatory_class` NOT NULL on `rate_items` + `adhoc_charges`, floor/ceiling/basis on `wna_zones`, `service_locations.jurisdiction_id` FK, `prorate_tier_breakpoints` default → true. Runtime-tested:

| test | result |
|---|---|
| rate_item / adhoc_charge without `regulatory_class` | rejected (NOT NULL, both tables) |
| `regulatory_class = 'sorta'` | rejected (`rate_items_regulatory_class_check`) |
| valid `regulated` rate_item / `unregulated` adhoc charge | inserted |
| duplicate `(tenant_id, jurisdiction_code)` | rejected (UNIQUE) |
| jurisdiction → wna_zone pointer + service_location → jurisdiction link | both resolve |
| WNA floor set without `wna_clamp_basis` | rejected (`wna_zones_clamp_basis_required_check`) |
| floor > ceiling | rejected (`wna_zones_floor_le_ceiling_check`) |
| clamp event `bound_hit = 'middle'` | rejected; `'floor'` with snapshot bounds inserted |
| new rate_schedule | `prorate_tier_breakpoints = true` by default |
| RLS on both new tables as `tally_app` | no context → 0 rows; operator context → own rows |

## v5.4.0-02 — meters & reads set (backlog items 1, 2, 8, 9; Kyle rulings D3-1, D3A-3, D3A-4)

Six columns on `meters` (`rollover_point`, `meter_pressure_class`, `tamper_flag` + `tamper_reported_at`/`tamper_signal_source`/`tamper_reason`) and two constraints on `read_cycle_meters.skip_reason` (ruled enum; `other` requires `notes`). All six new CHECKs runtime-tested on the deployed instance:

| test | result |
|---|---|
| `meter_pressure_class = 'medium'` | rejected (`meters_meter_pressure_class_check`) |
| `rollover_point = -5` | rejected (`meters_rollover_point_check`) |
| `tamper_flag = true` without reported_at/source | rejected (`meters_tamper_flag_consistency_check`) |
| valid meter: elevated / 1,000,000 / tamper fully recorded | inserted |
| `skip_reason = 'poodle'` | rejected (`read_cycle_meters_skip_reason_check`) |
| `skip_reason = 'other'` without notes | rejected (`read_cycle_meters_skip_other_notes_check`) |
| `skip_reason = 'dog'`; `'other'` + notes | both inserted |

Incidental confirmation: `read_cycle_meters` UNIQUE (instance, meter) fired correctly during testing. Fixture note: the FK chain for these tests is tenant → customer → service_location → meter and billing_cycle → read_cycle_instance.

## v5.4.0-01 — app role, GRANTs, FORCE RLS (decision: Ryan, 2026-08-19 — split-role model)

Role `tally_app` (NOLOGIN privilege bundle; production LOGIN users get membership) with full DML GRANTs + default privileges for future objects; `FORCE ROW LEVEL SECURITY` on all 58 RLS tables (`materialized_view_refresh_log` stays non-RLS by design). Migrations remain the owner's job. **This is the moment the 59 policies bind anyone at all** — and the first true end-to-end RLS test (v5.4.0-00's caveat is closed):

| context (as `tally_app` via SET ROLE) | result |
|---|---|
| no `app.user_id` set | 0 users, 0 tenants visible — fail-closed |
| operator (tenant A) | only tenant-A rows (2 users, 1 tenant) |
| operator (tenant A), INSERT into tenant B | **denied** — `new row violates row-level security policy for table "customers"` |
| operator (tenant A), INSERT into own tenant | succeeds (grants + WITH CHECK both verified live) |
| platform_admin | all rows (3 users, 2 tenants) — policy branch, not role bypass |

**Caveat that remains:** the container owner (`tally`) is a superuser, and superusers bypass RLS regardless of FORCE — so FORCE's binding of the *owner* is only observable on AWS, where the owner won't be superuser. Fixture note: `customers.customer_number` is NOT NULL with no default (app-assigned).

## v5.4.0-00 — Supabase substrate removed (decision: Ryan, 2026-08-18 — PostgreSQL on AWS)

`get_user_tenant_id()` / `is_platform_admin()` now read the `app.user_id` session GUC instead of Supabase's `auth.uid()`; no `auth.*` references remain. **Runtime-tested for the first time** (impossible pre-patch — the old bodies would have raised `auth.uid() does not exist`):

| context | `get_user_tenant_id()` | `is_platform_admin()` |
|---|---|---|
| none set | NULL (all tenant policies deny — fail-closed) | false |
| operator user | their tenant uuid | false |
| platform_admin user | — | true |

**Caveat:** these were run as the `tally` superuser, which owns the tables — RLS never applies to owners (and no table sets FORCE). A true end-to-end policy test requires the app role, which is the open Phase 0.5 item (roles/GRANTs + the FORCE-RLS decision).

---

## Original baseline verification — v5.2.1 (2026-08-18)

## Provenance (why this file exists)

The schema was authored by Kyle Shaffer with Claude Opus and never run by Kyle. Ryan ran a version on a local PostgreSQL in May 2026 and exported a tables-only listing (`application/database/schema.sql`); that machine has since died and **no database with data exists anywhere**. This verification re-establishes the executable baseline from what is in the repo. `tu.sql` is the canonical schema; `schema.sql` is a column-reference document only.

## Deployed object counts (queried from the running instance)

| object | count | expected (from tu.sql) | note |
|---|---|---|---|
| tables | 59 | 59 | |
| triggers (non-internal) | 49 | 49 | |
| RLS policies | 59 | 59 | |
| functions (non-extension) | 23 | 23 | |
| CHECK constraints | 188 | — | grep of tu.sql says 191; 188 is the real count (grep hits include comments) |
| plain indexes | 352 | ~348 | grep undercounts; DB is authoritative |
| foreign keys | 252 | 252 | confirms the corpus finding: all single-column |
| RLS-enabled tables | 58 of 59 | — | |
| **FORCE ROW LEVEL SECURITY tables** | **0** | — | **independently confirms CI-116's read-isolation gap** |
| views + materialized views | 2 + 4 | 6 | the corpus's "six views" = both kinds |

## Method

```bash
docker build -t tally-postgres -f postgres/Dockerfile .
docker run -d --name tally-pg -e POSTGRES_PASSWORD=tally tally-postgres
docker logs tally-pg   # zero error/fatal lines
docker exec tally-pg psql -U tally -d tally -c "<catalog queries>"
```

No host port is required (5432 was occupied locally); use `docker exec`. Each container start applies the schema fresh — this is the standing deployability test. **Re-run this verification after every patch set and update this file's counts.**
