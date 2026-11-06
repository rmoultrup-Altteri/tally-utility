#!/usr/bin/env bash
# v5.4.2-30 races (r3; review r2: Opus S2 and B1, Fable B1, Opus's note).
#   R1  A records a levy on a city and holds; B's close of the city (no
#       successor) waits on the place lock, then is refused at its commit:
#       the coverage check sees A's levy.
#   R2  A closes a city and holds; B's levy over the closed dates waits on
#       the shared lock, then re-reads the city's rows and is refused.
#   R3  two overlapping corrections of one premise's state: B begins first,
#       A changes the state and holds, B's change waits on the premise's row
#       lock, then is refused (40001): A's row is stamped after B began. The
#       history ends on A's state, the premise's own.
#   R4  control: a correction that begins after A committed is recorded, and
#       the history ends on it.
#   R5  A closes a city's row and adds its successor, and holds; B's levy
#       waits on the row it found, then — though the successor now covers it
#       — is refused (40001): a row committed while it waited is never
#       trusted unlocked (-16's rule, its race R19).
# Every two-session leg checks that the second session ITSELF was seen waiting
# on a lock (pg_stat_activity, by application_name) before the first
# committed, so a leg cannot pass by running in order. Setup failures exit 2;
# a leg whose first session failed is a FAIL.
# Runs against a THROWAWAY clone (it commits rows).
#   usage: levy-30.sh <db>      (default: r30race)
set -uo pipefail
DB="${1:-r30race}"
PSQL=(docker exec -i tally-pg psql -U tally -d "$DB" -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -q -At)

T=00000000-0000-4000-8000-0000000030f9
U=00000000-0000-4000-8000-0000000030f8
C=00000000-0000-4000-8000-0000000030f7
L=00000000-0000-4000-8000-0000000030f6
PA=00000000-0000-4000-8000-0000000030fa
PB=00000000-0000-4000-8000-0000000030fb
PC=00000000-0000-4000-8000-0000000030fc
PC2=00000000-0000-4000-8000-0000000030fd
APP="SET LOCAL app.user_id = '$U'; SET ROLE tally_app;"
TERMS='{"rate_percent": 1, "stacking_position": 2, "computed_on": [], "source_kind": "ordinance", "citation": "Race Ord. 1", "reaches_residential": true}'
levy() {  # $1 city code: a levy from 2026-01-01, open
echo "INSERT INTO public.tax_levies (tenant_id, state_code, service_type, system_kind, place_kind, place_code, tax_kind, effective_from,
        tariff_reference, terms_kind, terms_version, terms_source)
      VALUES ('$T', 'TX', 'gas', 'distribution', 'municipality', '$1', 'sales_tax', DATE '2026-01-01', 'Race tariff', 'tax_levy', 1, '$TERMS');"
}

"${PSQL[@]}" >/dev/null <<SQL || { echo "SETUP FAIL: fixtures"; exit 2; }
INSERT INTO public.tenants (id, name, slug) VALUES ('$T', 'Race30', 'race30-$RANDOM$RANDOM');
INSERT INTO public.users (id, tenant_id, display_name, email, role) VALUES ('$U', '$T', 'Op', 'op$RANDOM@race30.test', 'operator');
INSERT INTO public.customers (id, tenant_id, customer_number, customer_type) VALUES ('$C', '$T', 'R30-C', 'residential');
INSERT INTO public.service_locations (id, tenant_id, customer_id, location_number, address_line1, city, state, zip)
  VALUES ('$L', '$T', '$C', 'L', '1 Main', 'Raceville', 'TX', '78701');
INSERT INTO public.places (id, kind_code, state_code, place_code, name, parent_place_id, effective_from, source_note)
SELECT v.id, 'municipality', 'TX', v.code, v.code, s.id, DATE '1950-01-01', 'race fixture'
  FROM (VALUES ('$PA'::uuid, 'R30-A'), ('$PB'::uuid, 'R30-B'), ('$PC'::uuid, 'R30-C')) v(id, code),
       (SELECT id FROM public.places WHERE kind_code = 'state' AND place_code = 'TX' AND effective_to IS NULL) s;
SQL

fail=0
A_OUT=$(mktemp); B_OUT=$(mktemp); trap 'rm -f "$A_OUT" "$B_OUT"' EXIT
waiting() {
docker exec -i tally-pg psql -U tally -d "$DB" -At -c "SELECT count(*) FROM pg_stat_activity WHERE datname = current_database() AND application_name = 'race30_b' AND wait_event_type = 'Lock'"
}
# two(): A's SQL holds 3s; B's SQL starts 1s later; B is sampled while A holds.
two() {  # $1 A's SQL, $2 B's SQL
"${PSQL[@]}" >"$A_OUT" 2>&1 <<SQL &
BEGIN;
$1
SELECT pg_sleep(3);
COMMIT;
SQL
APID=$!
sleep 1
"${PSQL[@]}" >"$B_OUT" 2>&1 <<SQL &
SET application_name = 'race30_b';
$2
SQL
sleep 1
WAITED=$(waiting)
wait $APID; AST=$?
wait
OUT=$(cat "$B_OUT")
}
seen() {
if [ "${AST:-0}" -ne 0 ]; then echo "FAIL $1: session A itself failed: $(cat "$A_OUT")"; fail=1; return 1; fi
if [ "${WAITED:-0}" -lt 1 ]; then echo "FAIL $1: the second session was never seen waiting (sequential, not a race)"; fail=1; return 1; fi
}

# R1
two "$APP $(levy R30-A)" "UPDATE public.places SET effective_to = DATE '2026-06-01' WHERE id = '$PA';"
if seen R1 && grep -q "a tax levy" <<<"$OUT"; then
  echo "PASS R1: a city closed while a levy on it is in flight waits, then is refused at commit"
else echo "FAIL R1: the close said: $OUT"; fail=1; fi

# R2
two "UPDATE public.places SET effective_to = DATE '2026-06-01' WHERE id = '$PB';" "BEGIN; $APP $(levy R30-B) COMMIT;"
if seen R2 && grep -q "in force over the whole" <<<"$OUT"; then
  echo "PASS R2: a levy recorded while its city is being closed waits, then is refused"
else echo "FAIL R2: the levy said: $OUT"; fail=1; fi

# R3: B begins first, then A; B's change reaches the premise after A holds it.
"${PSQL[@]}" >"$B_OUT" 2>&1 <<SQL &
SET application_name = 'race30_b';
BEGIN;
$APP
SELECT pg_sleep(1.5);
UPDATE public.service_locations SET state = 'NM' WHERE id = '$L';
COMMIT;
SQL
BPID=$!
sleep 0.5
"${PSQL[@]}" >"$A_OUT" 2>&1 <<SQL &
BEGIN;
$APP
UPDATE public.service_locations SET state = 'OK' WHERE id = '$L';
SELECT pg_sleep(3);
COMMIT;
SQL
APID=$!
sleep 2
WAITED=$(waiting)
wait $APID; AST=$?
wait $BPID
OUT=$(cat "$B_OUT")
LAST=$("${PSQL[@]}" -c "SELECT (SELECT state FROM public.service_location_state_history WHERE service_location_id = '$L' ORDER BY recorded_at DESC, seq DESC LIMIT 1) || '/' || (SELECT upper(btrim(state)) FROM public.service_locations WHERE id = '$L')")
if seen R3 && grep -q "ERROR:  40001" <<<"$OUT" && grep -q "began after this one" <<<"$OUT" && [ "$LAST" = "OK/OK" ]; then
  echo "PASS R3: a correction begun before an overlapping one committed is refused (40001); the history ends on the premise's state"
else echo "FAIL R3: B said: $OUT; history/premise: $LAST"; fail=1; fi

# R4
OUT=$("${PSQL[@]}" 2>&1 <<SQL
BEGIN; $APP UPDATE public.service_locations SET state = 'NM' WHERE id = '$L'; COMMIT;
SQL
)
OUT="$OUT$("${PSQL[@]}" -c "SELECT state FROM public.service_location_state_history WHERE service_location_id = '$L' ORDER BY recorded_at DESC, seq DESC LIMIT 1" 2>&1)"
if [ "$OUT" = "NM" ]; then
  echo "PASS R4: a correction begun after the other committed is recorded, last"
else echo "FAIL R4: $OUT"; fail=1; fi

# R5
two "UPDATE public.places SET effective_to = DATE '2026-07-01' WHERE id = '$PC';
INSERT INTO public.places (id, kind_code, state_code, place_code, name, parent_place_id, effective_from, source_note)
SELECT '$PC2', 'municipality', 'TX', 'R30-C', 'R30-C (successor)', id, DATE '2026-07-01', 'race fixture'
  FROM public.places WHERE kind_code = 'state' AND place_code = 'TX' AND effective_to IS NULL;" \
    "BEGIN; $APP $(levy R30-C) COMMIT;"
if seen R5 && grep -q "ERROR:  40001" <<<"$OUT" && grep -q "changed while this waited" <<<"$OUT"; then
  echo "PASS R5: a levy that waited on a city's row is refused when a successor row was committed meanwhile (retry)"
else echo "FAIL R5: the levy said: $OUT"; fail=1; fi
exit $fail
