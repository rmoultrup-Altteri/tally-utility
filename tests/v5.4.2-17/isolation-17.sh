#!/bin/bash
# The v5.4.2-17 refusals that need separate transactions or another isolation
# level (X1-X5). Builds its own scratch clone of a -17 database.
# usage: tests/v5.4.2-17/isolation-17.sh <db-with-17> [scratch-db]
set -uo pipefail
SRC=${1:?db with v5.4.2-17}
DB=${2:-iso17}
HERE=$(cd "$(dirname "$0")" && pwd)
q() { docker exec -i tally-pg psql -U tally -d "$DB" -v ON_ERROR_STOP=1 -qAt "$@"; }
docker exec tally-pg psql -U tally -d postgres -qc "DROP DATABASE IF EXISTS $DB" -qc "CREATE DATABASE $DB TEMPLATE $SRC" >/dev/null
docker exec tally-pg psql -U tally -d "$DB" -qc "REVOKE TEMP ON DATABASE $DB FROM PUBLIC" -qc "REVOKE TEMP ON DATABASE $DB FROM tally_app" >/dev/null
q < "$HERE/fixture-iso-17.sql" >/dev/null || { echo "FAIL: fixture"; exit 1; }
FAILS=0
# expect <label> <sqlstate> <phrase> <sql>: one session; the SQL must fail so.
expect() {
  local out
  out=$(q 2>&1 <<SQL
\set VERBOSITY verbose
$4
SQL
)
  if grep -q "ERROR:  $2:" <<<"$out" && grep -qF "$3" <<<"$out"; then echo "PASS $1"; else echo "FAIL $1: $out"; FAILS=$((FAILS+1)); fi
}
ROW=00000000-0000-4000-8000-0000000017f9
expect "X1: a facet declared after its schema's transaction" 23514 "in their schema's own transaction" \
  "INSERT INTO public.rule_term_facets (terms_kind, terms_version, facet_name, facet_type, json_path, description) VALUES ('zz_iso', 1, 'cap', 'number', '\$.cap', 'late');"
expect "X2: a rule row written under REPEATABLE READ" 25000 "runs only under READ COMMITTED" \
  "BEGIN ISOLATION LEVEL REPEATABLE READ; INSERT INTO public.zz_iso_rules (state_code, service_type, customer_class, effective_from, source_note, terms_kind, terms_version, terms_source) VALUES ('ZZ', 'gas', 'commercial', DATE '2000-01-01', 'x', 'zz_iso', 1, '{\"governs\": \"law\", \"citation\": \"ZZ 1\", \"cap\": 5}'); COMMIT;"
expect "X3: a citation under REPEATABLE READ" 25000 "citing a row of" \
  "BEGIN ISOLATION LEVEL REPEATABLE READ; SET LOCAL app.user_id = '00000000-0000-4000-8000-0000000017f2'; SET LOCAL ROLE tally_app; INSERT INTO public.zz_iso_charges (tenant_id, rule_id, charged_on) VALUES ('00000000-0000-4000-8000-0000000017f1', '$ROW', DATE '2020-01-01'); COMMIT;"
expect "X4: a close under SERIALIZABLE" 25000 "closing a row of" \
  "BEGIN ISOLATION LEVEL SERIALIZABLE; UPDATE public.zz_iso_rules SET effective_to = DATE '2090-01-01' WHERE id = '$ROW'; COMMIT;"
expect "X5: a freeze under REPEATABLE READ" 25000 "freezing a term schema" \
  "BEGIN ISOLATION LEVEL REPEATABLE READ; UPDATE public.rule_term_schemas SET accepts_new_rows = false WHERE terms_kind = 'zz_iso' AND terms_version = 2; COMMIT;"
echo "isolation-17: $FAILS failure(s)"
exit $FAILS
