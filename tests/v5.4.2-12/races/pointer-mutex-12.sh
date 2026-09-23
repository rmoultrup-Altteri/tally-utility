#!/usr/bin/env bash
# v5.4.2-12 — the pointer's row-version mutex (review rounds 4-5).
# Two sessions: A (READ COMMITTED) records a test that does NOT change the
# pointer; B (REPEATABLE READ, snapshot taken before A commits) records a
# same-date row. B must fail with a serialisation error, and the pointer must
# agree with meter_governing_test(). Without the unconditional pointer write,
# B commits and the pointer disagrees with the history.
# Usage: tests/v5.4.2-12/races/pointer-mutex-12.sh [patch-file]
set -euo pipefail
PATCH=${1:-sql/v5.4.2-12-meter-test-history.sql}
DB=race12_ptr
docker cp "$PATCH" tally-pg:/tmp/race12_patch.sql
docker exec tally-pg psql -U tally -d tally -qtA -c "DROP DATABASE IF EXISTS $DB" -c "CREATE DATABASE $DB TEMPLATE tally" >/dev/null
docker exec -e PGOPTIONS="-c search_path= -c check_function_bodies=on" tally-pg psql -U tally -d $DB -q -v ON_ERROR_STOP=1 -f /tmp/race12_patch.sql >/dev/null 2>&1
docker exec -i tally-pg psql -U tally -d $DB -q -v ON_ERROR_STOP=1 <<'SQL'
INSERT INTO public.tenants (id, name, slug, cutover_date) VALUES ('00000000-0000-4000-8000-00000000dd01','RR','race12', DATE '2026-01-15');
INSERT INTO public.users (id, tenant_id, display_name, email, role) VALUES ('00000000-0000-4000-8000-00000000dd02','00000000-0000-4000-8000-00000000dd01','U','u@race12','operator');
INSERT INTO public.customers (id, tenant_id, customer_number) VALUES ('00000000-0000-4000-8000-00000000dd03','00000000-0000-4000-8000-00000000dd01','RR-1');
INSERT INTO public.service_locations (id, tenant_id, customer_id, location_number, address_line1, city, state, zip) VALUES ('00000000-0000-4000-8000-00000000dd04','00000000-0000-4000-8000-00000000dd01','00000000-0000-4000-8000-00000000dd03','L','1','A','TX','7');
INSERT INTO public.meters (id, tenant_id, meter_number, location_id, service_type) VALUES ('00000000-0000-4000-8000-00000000dd11','00000000-0000-4000-8000-00000000dd01','M1','00000000-0000-4000-8000-00000000dd04','gas');
INSERT INTO public.meter_tests (tenant_id, meter_id, test_date, test_kind, record_basis, outcome) VALUES ('00000000-0000-4000-8000-00000000dd01','00000000-0000-4000-8000-00000000dd11', DATE '2026-01-10','periodic','migrated_date_only','accurate');
SQL
H="SET app.user_id='00000000-0000-4000-8000-00000000dd02'; SET ROLE tally_app;"
OUT=$(mktemp)
( docker exec tally-pg psql -U tally -d $DB -qtA -c "BEGIN ISOLATION LEVEL REPEATABLE READ; $H SELECT count(*) FROM public.meter_tests; SELECT pg_sleep(1.5); INSERT INTO public.meter_tests (tenant_id, meter_id, test_date, test_kind, record_basis) VALUES ('00000000-0000-4000-8000-00000000dd01','00000000-0000-4000-8000-00000000dd11', DATE '2026-01-10','periodic','migrated_date_only'); COMMIT;" >"$OUT" 2>&1 || true ) &
sleep 0.4
docker exec tally-pg psql -U tally -d $DB -qtA -c "BEGIN; $H INSERT INTO public.meter_tests (tenant_id, meter_id, test_date, test_kind, record_basis, performed_by_name, test_equipment, meter_serial_at_test, multiplier_at_test, load_results) VALUES ('00000000-0000-4000-8000-00000000dd01','00000000-0000-4000-8000-00000000dd11', DATE '2026-01-10','periodic','migrated_full','T','p','S',1.0,'[{\"load_point\":\"c\",\"standard_volume\":100,\"meter_volume\":100.5}]'); SELECT pg_sleep(2.5); COMMIT;" >/dev/null
wait
PTR=$(docker exec tally-pg psql -U tally -d $DB -qtA -c "SELECT last_test_result FROM public.meters WHERE meter_number='M1'")
GOV=$(docker exec tally-pg psql -U tally -d $DB -qtA -c "SELECT CASE outcome WHEN 'accurate' THEN 'passed' ELSE outcome END FROM public.meter_governing_test('00000000-0000-4000-8000-00000000dd11', DATE '2026-01-11')")
docker exec tally-pg psql -U tally -d tally -qtA -c "DROP DATABASE $DB" >/dev/null
if grep -q 'could not serialize access' "$OUT" && [ "$PTR" = "$GOV" ]; then
  echo "PASS R1: the snapshot session fails with a serialisation error; pointer ($PTR) agrees with the governing test"
else
  echo "FAIL R1: B output: $(tr '\n' ' ' < "$OUT") | pointer=$PTR governing=$GOV"; rm -f "$OUT"; exit 1
fi
rm -f "$OUT"
