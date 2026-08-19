# Deploy verification — tu.sql

**Current: v5.2.1 + v5.4.0-00 + v5.4.0-01, verified 2026-08-19.** Deploys **clean, zero errors** on fresh PostgreSQL via the repo harness (`postgres/Dockerfile`, base `postgres:16`, `check_function_bodies = off` preamble). Counts after v5.4.0-01: 59 tables / 59 policies / **58 FORCE-RLS tables (was 0)** / role `tally_app` present. tu.sql is now **11,455 lines** (was 11,351; the v5.4.0-01 mirror is a pure append at EOF, so every pre-existing line number — including anchors 337/3600/3679 — is unchanged and all register citations remain valid).

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
