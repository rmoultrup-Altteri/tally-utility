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
#   R6  a district membership voided by a transaction that began after the one
#       that records it again: read between the two, the district answers once.
#   R7  the same, recorded again as outside: the read refuses (21000).
# Every two-session leg checks that the second session ITSELF was seen waiting
# on a lock (pg_stat_activity, by application_name) before the first
# committed (sampled until seen, up to 1.5s), so a leg cannot pass by running in
# order. A leg prints one line (r4, Codex S1): PASS; FAIL <leg> [waited|nowait|
# read] for a wrong result; BROKEN when a session failed for its own reasons;
# SEQUENTIAL when the result was right but the wait was never seen. Only FAIL
# is a catch for mutations-30.sh; all three fail the run. Setup failures exit 2.
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
PD=00000000-0000-4000-8000-0000000030fe
L6=00000000-0000-4000-8000-000000003061
L7=00000000-0000-4000-8000-000000003071
M6=00000000-0000-4000-8000-000000003062
M7=00000000-0000-4000-8000-000000003072
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
BPID=$!
sample
wait $APID; AST=$?
wait $BPID; BST=$?
OUT=$(cat "$B_OUT")
}
# sample(): WAITED=1 once session B is seen waiting on a lock, within 1.5s.
sample() {
WAITED=0
for _ in 1 2 3 4 5 6 7 8 9 10; do
  if [ "$(waiting)" -ge 1 ]; then WAITED=1; return; fi
  sleep 0.1
done
}
# verdict(): $1 leg, $2 0 when the result is the right one, $3 what it proves.
# A connection-level failure of either session (psql exit 2) is never a result.
verdict() {
if [ "${AST:-0}" -ne 0 ]; then echo "BROKEN $1: session A itself failed: $(cat "$A_OUT")"; fail=1
elif [ "${BST:-0}" -ne 0 ] && [ "${BST:-0}" -ne 3 ]; then echo "BROKEN $1: session B itself failed (exit $BST): $OUT"; fail=1
elif [ "$BST" -eq 3 ] && ! grep -q "ERROR:" <<<"$OUT"; then echo "BROKEN $1: session B failed with no error: $OUT"; fail=1
elif [ "$2" -eq 0 ] && [ "$WAITED" -eq 1 ]; then echo "PASS $1: $3"
elif [ "$2" -eq 0 ]; then echo "SEQUENTIAL $1: right, but the second session was never seen waiting"; fail=1
elif [ "$WAITED" -eq 1 ]; then echo "FAIL $1 [waited]: ${4:-} session B said (exit $BST): $OUT"; fail=1
else echo "FAIL $1 [nowait]: ${4:-} session B said (exit $BST): $OUT"; fail=1; fi
}
# refused(): session B failed with SQLSTATE $1 and a message holding $2.
refused() { [ "$BST" -eq 3 ] && grep -q "ERROR:  $1" <<<"$OUT" && grep -q "$2" <<<"$OUT"; }

# R1
two "$APP $(levy R30-A)" "UPDATE public.places SET effective_to = DATE '2026-06-01' WHERE id = '$PA';"
refused 23001 "a tax levy"; verdict R1 $? "a city closed while a levy on it is in flight waits, then is refused at commit"

# R2
two "UPDATE public.places SET effective_to = DATE '2026-06-01' WHERE id = '$PB';" "BEGIN; $APP $(levy R30-B) COMMIT;"
refused 23514 "in force over the whole"; verdict R2 $? "a levy recorded while its city is being closed waits, then is refused"

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
sleep 1.2
sample
wait $APID; AST=$?
wait $BPID; BST=$?
OUT=$(cat "$B_OUT")
LAST=$("${PSQL[@]}" -c "SELECT (SELECT state FROM public.service_location_state_history WHERE service_location_id = '$L' ORDER BY recorded_at DESC, seq DESC LIMIT 1) || '/' || (SELECT upper(btrim(state)) FROM public.service_locations WHERE id = '$L')")
refused 40001 "began after this one" && [ "$LAST" = "OK/OK" ]; verdict R3 $? "a correction begun before an overlapping one committed is refused (40001); the history ends on the premise's state"

# R4
OUT=$("${PSQL[@]}" 2>&1 <<SQL
BEGIN; $APP UPDATE public.service_locations SET state = 'NM' WHERE id = '$L'; COMMIT;
SQL
)
OUT="$OUT$("${PSQL[@]}" -c "SELECT state FROM public.service_location_state_history WHERE service_location_id = '$L' ORDER BY recorded_at DESC, seq DESC LIMIT 1" 2>&1)"
if [ "$OUT" = "NM" ]; then
  echo "PASS R4: a correction begun after the other committed is recorded, last"
else echo "FAIL R4 [read]: $OUT"; fail=1; fi

# R5
two "UPDATE public.places SET effective_to = DATE '2026-07-01' WHERE id = '$PC';
INSERT INTO public.places (id, kind_code, state_code, place_code, name, parent_place_id, effective_from, source_note)
SELECT '$PC2', 'municipality', 'TX', 'R30-C', 'R30-C (successor)', id, DATE '2026-07-01', 'race fixture'
  FROM public.places WHERE kind_code = 'state' AND place_code = 'TX' AND effective_to IS NULL;" \
    "BEGIN; $APP $(levy R30-C) COMMIT;"
refused 40001 "changed while this waited"; verdict R5 $? "a levy that waited on a city's row is refused when a successor row was committed meanwhile (retry)"
# R6, R7: A begins, then B voids and commits, then A records the place again
# (stamped before the void); the read is at an instant between the two.
rerecord() {  # $1 leg, $2 premise, $3 the membership voided, $4 A's relation, $5 right result, $6 what it proves
"${PSQL[@]}" >"$A_OUT" 2>&1 <<SQL &
BEGIN;
$APP
SELECT now();
SELECT pg_sleep(1.5);
INSERT INTO public.premise_place_memberships (tenant_id, service_location_id, place_id, axis, relation, place_kind, valid_from, evidence_kind, evidence_reference, evidence_date)
VALUES ('$T', '$2', '$PD', 'tax', '$4', 'special_purpose_district', DATE '2020-01-01', 'address_lookup', 'Race file, again', DATE '2020-01-01');
COMMIT;
SQL
APID=$!
sleep 0.7
"${PSQL[@]}" >"$B_OUT" 2>&1 <<SQL
BEGIN; $APP UPDATE public.premise_place_memberships SET void_reason = 're-recorded' WHERE id = '$3'; COMMIT;
SQL
BST=$?
wait $APID; AST=$?
local order
order=$("${PSQL[@]}" -c "SELECT count(*) FROM public.premise_place_memberships o JOIN public.premise_place_memberships n ON n.service_location_id = o.service_location_id AND n.id <> o.id WHERE o.id = '$3' AND n.created_at < o.voided_at AND o.created_at < n.created_at" 2>&1)
if [ $AST -ne 0 ] || [ $BST -ne 0 ] || [ "$order" != 1 ]; then echo "BROKEN $1: the two writers did not overlap: $(cat "$A_OUT" "$B_OUT") (order $order)"; fail=1; return; fi
OUT=$("${PSQL[@]}" -c "SELECT string_agg(r.relation, ',' ORDER BY r.relation) FROM public.premise_place_memberships o, LATERAL public.premise_places_as_of('$2', DATE '2026-06-01', 'tax', o.voided_at - interval '1 millisecond') r WHERE o.id = '$3' AND r.place_id = '$PD'" 2>&1)
if grep -q "$5" <<<"$OUT"; then echo "PASS $1: $6"; else echo "FAIL $1 [read]: $OUT"; fail=1; fi
}
"${PSQL[@]}" >/dev/null <<SQL || { echo "SETUP FAIL: R6, R7 fixtures"; exit 2; }
INSERT INTO public.service_locations (id, tenant_id, customer_id, location_number, address_line1, city, state, zip) VALUES
  ('$L6', '$T', '$C', 'L6', '6 Main', 'Raceville', 'TX', '78701'), ('$L7', '$T', '$C', 'L7', '7 Main', 'Raceville', 'TX', '78701');
INSERT INTO public.places (id, kind_code, state_code, place_code, name, parent_place_id, effective_from, source_note)
SELECT '$PD', 'special_purpose_district', 'TX', 'R30-D', 'R30-D', id, DATE '1950-01-01', 'race fixture'
  FROM public.places WHERE kind_code = 'state' AND place_code = 'TX' AND effective_to IS NULL;
INSERT INTO public.premise_place_memberships (id, tenant_id, service_location_id, place_id, axis, place_kind, valid_from, evidence_kind, evidence_reference, evidence_date) VALUES
  ('$M6', '$T', '$L6', '$PD', 'tax', 'special_purpose_district', DATE '2020-01-01', 'address_lookup', 'Race file', DATE '2020-01-01'),
  ('$M7', '$T', '$L7', '$PD', 'tax', 'special_purpose_district', DATE '2020-01-01', 'address_lookup', 'Race file', DATE '2020-01-01');
SQL
rerecord R6 "$L6" "$M6" within '^within$' "a district recorded again while its first record is being voided answers once at an instant between the two"
rerecord R7 "$L7" "$M7" outside 'ERROR:  21000.*more than one answer for one place' "the same recorded again as outside is refused at an instant between the two"
exit $fail
