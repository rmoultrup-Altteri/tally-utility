# =============================================================================
# TallyUtility — PostgreSQL Schema Development Container
# =============================================================================
# PURPOSE
#   Spin up a fresh Postgres instance with the TallyUtility schema pre-loaded.
#   Use this to iterate on schema design without a full application stack.
#
# BUILD & RUN (from the project root — tally-utility/)
#   docker build -t tally-postgres -f postgres/Dockerfile .
#   docker run --rm -p 5432:5432 --name tally-pg \
#     -e POSTGRES_PASSWORD=tally \
#     tally-postgres
#
# CONNECT
#   psql postgresql://tally:tally@localhost:5432/tally
#
# ITERATE ON SCHEMA
#   1. Edit sql/tu.sql (or add a new patch file alongside it)
#   2. Rebuild the image:  docker build -t tally-postgres -f postgres/Dockerfile .
#   3. Re-run the container — the schema is applied fresh on every start
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
