# =============================================================================
# TallyUtility — PostgreSQL Schema Development Container
# =============================================================================
# PURPOSE
#   Spin up a fresh Postgres instance with the TallyUtility schema pre-loaded.
#   Use this to iterate on schema design without a full application stack.
#
# BUILD & RUN (from the project root — tally-utility/)
#   docker build -t tally-postgres -f postgres/Dockerfile .
#   docker run -d --name tally-pg -e POSTGRES_PASSWORD=tally tally-postgres
#
#   Do NOT publish a host port (-p 5432:5432): host 5432 belongs to another
#   project. Wait for "PostgreSQL init process complete" in `docker logs
#   tally-pg` before connecting — a probe earlier hits the temporary init
#   server.
#
# CONNECT (inside the container; there is no `postgres` role — use tally)
#   docker exec -it tally-pg psql -U tally -d tally
#
# ITERATE ON SCHEMA
#   tu.sql is APPEND-ONLY. A change is a new sql/v5.4.x-NN-*.sql patch, applied
#   first to a clone (CREATE DATABASE x TEMPLATE tally) with search_path=''
#   and check_function_bodies=on — this image's preamble turns body checking
#   OFF, so a Docker build alone cannot catch unqualified function bodies.
#   Only after review is the patch body mirrored into tu.sql and the image
#   rebuilt. Full loop: tests/README.md.
#
# PSQL ONE-LINER (run a query without an interactive session)
#   docker exec tally-pg psql -U tally -d tally -c "\dt"
#
# NOTES
#   - The schema uses uuid-ossp, pgcrypto, and pg_trgm — all bundled with the
#     official postgres image, no extra installation needed.
#   - SET check_function_bodies = off is prepended automatically via the
#     00_preamble.sql init file to work around forward-reference issues
#     documented at the top of tu.sql (no Supabase auth substrate here).
#   - Data does NOT persist between container runs (no volume). That is
#     intentional — each run is a clean schema test.
#     To persist data across runs, add:  -v tally-pgdata:/var/lib/postgresql/data
# =============================================================================

FROM postgres:16

# ---------------------------------------------------------------------------
# Database credentials
# POSTGRES_USER and POSTGRES_DB are not sensitive — fine to bake in.
# POSTGRES_PASSWORD is passed at runtime via -e to avoid the Docker
# "secrets in ENV" warning. For this local dev container, any value works.
# ---------------------------------------------------------------------------
ENV POSTGRES_USER=tally
ENV POSTGRES_DB=tally

# ---------------------------------------------------------------------------
# Init scripts
# Docker executes everything in /docker-entrypoint-initdb.d/ in filename
# order on first startup. We use two files:
#   00_preamble.sql  — session-level settings required by the schema
#   01_schema.sql    — the full TallyUtility schema (copied from sql/tu.sql)
# ---------------------------------------------------------------------------

# Preamble: disable function-body checking so forward-references in the
# schema (documented in tu.sql header) don't abort the init run.
COPY postgres/00_preamble.sql /docker-entrypoint-initdb.d/00_preamble.sql

# Schema: the current snapshot. Rebuild the image to pick up any edits.
COPY sql/tu.sql /docker-entrypoint-initdb.d/01_schema.sql
