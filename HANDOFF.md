# Handoff: PostgreSQL Schema Dev Container

**Generated**: 2026-05-13
**Branch**: N/A
**Status**: In Progress

## Goal

Stand up a local PostgreSQL Docker container for TallyUtility schema development — iterate on `sql/tu.sql` without a full application stack. No application code yet; this is pure schema design/validation work.

## Completed

- [x] Created `postgres/Dockerfile` — builds `postgres:16`, copies schema + preamble into `/docker-entrypoint-initdb.d/`, runs schema on first start
- [x] Created `postgres/00_preamble.sql` — sets `check_function_bodies = off` before schema runs (required for forward-reference workaround documented in `tu.sql` header)
- [x] Resolved Docker build warning: moved `POSTGRES_PASSWORD` out of `ENV` in Dockerfile; now passed at runtime via `-e` flag
- [x] Connected WebStorm Database tool window to the running container

## Not Yet Done

- [ ] Validate that the full schema (`sql/tu.sql` v5.2.1) applies cleanly with no errors — container builds but schema load success against vanilla Postgres hasn't been confirmed yet
- [ ] Assess whether a Supabase shim is needed — `tu.sql` targets Supabase (`auth.uid()`, `auth.users`); RLS policies or functions that *call* `auth.uid()` at runtime (not just DDL time) may fail on vanilla Postgres
- [ ] Begin schema iteration work

## Failed Approaches (Don't Repeat These)

- **`POSTGRES_PASSWORD` in `ENV`**: Baking the password into the image with `ENV POSTGRES_PASSWORD=tally` triggers Docker's "SecretsUsedInArgOrEnv" warning (line 41). Not a build failure, but noisy. → Fixed: pass at runtime with `-e POSTGRES_PASSWORD=tally` on `docker run`.

## Key Decisions

| Decision | Rationale |
|----------|-----------|
| `postgres:16` base image | Includes `uuid-ossp`, `pgcrypto`, `pg_trgm` without extra installation — all three are required by `tu.sql` |
| No volume mount | Each container run is a clean schema test; intentional for iteration. Add `-v tally-pgdata:/var/lib/postgresql/data` to `docker run` if persistence is ever needed |
| `00_preamble.sql` as separate init file | `SET check_function_bodies = off` must run before the schema SQL; init files execute in filename order, so `00_` prefix guarantees ordering |
| Build context is project root | `COPY sql/tu.sql` requires the Dockerfile to be built from `tally-utility/` root, not from inside `postgres/` — `docker build -f postgres/Dockerfile .` |

## Current State

**Working**: Container builds and starts. WebStorm connects via `localhost:5432`, user `tally`, db `tally`, password `tally`.
**Broken**: Unknown — schema load against vanilla Postgres not yet verified end-to-end. Watch for Supabase auth errors (see Warnings below).
**Uncommitted changes**: `postgres/Dockerfile`, `postgres/00_preamble.sql` are new files, not yet committed.

## Resume Instructions

1. Start the container from the project root:
   ```bash
   docker run --rm -p 5432:5432 --name tally-pg \
     -e POSTGRES_PASSWORD=tally \
     tally-postgres
   ```
   - Expected: Postgres starts, init scripts run, logs show schema DDL executing
   - If it fails: Check container logs with `docker logs tally-pg` — look for the first ERROR line

2. In WebStorm Database tool window, verify the `tally` data source connects and `public` schema is visible with tables populated

3. If you see errors like `function auth.uid() does not exist` during container init, a Supabase shim is needed:
   - Create `postgres/01_supabase_shim.sql` with stubs for `auth.uid()` and `auth.users`
   - Rename current init files to maintain order: `00_preamble.sql`, `01_supabase_shim.sql`, `02_schema.sql`
   - Rebuild: `docker build -t tally-postgres -f postgres/Dockerfile .`

4. Schema iteration loop:
   - Edit `sql/tu.sql`
   - `docker build -t tally-postgres -f postgres/Dockerfile .`
   - `docker run --rm -p 5432:5432 --name tally-pg -e POSTGRES_PASSWORD=tally tally-postgres`

## Setup Required

- Docker must be running
- Build always from project root (`tally-utility/`), not from inside `postgres/`

## Warnings

- **Supabase auth substrate**: `tu.sql` was generated from a Supabase project. The `00_preamble.sql` handles `check_function_bodies = off` (DDL-time forward references), but any function that *calls* `auth.uid()` at runtime will fail on vanilla Postgres. The shim path is documented in Resume step 3.
- **Schema is auto-generated**: `sql/tu.sql` header says "DO NOT EDIT — AUTO-GENERATED". Edits here will be clobbered on next build. The intention for iteration is currently to edit this file directly since there's no patch pipeline yet — clarify with Ryan how he wants to manage schema versions going forward.
- **No app code yet**: This repo has only `sql/` and `postgres/` directories. All work so far is infra for schema validation only.
