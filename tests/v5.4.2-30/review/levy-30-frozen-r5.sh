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
#   R8  a bill's transaction begun between two overlapping corrections (from one
#       district to another), reading once both are committed: the
#       three-argument form answers the second district alone (r5).
# Legs R1-R3 and R5 each check that the second session ITSELF was seen waiting
# on a lock (pg_stat_activity, by application_name) before the first
# committed (sampled ten times), so a leg cannot pass by running in order.
# A leg prints one line (r4, r5; Codex S1, Opus S3):
#   PASS
#   FAIL <leg> [waited|nowait:damage]      B committed, and the wrong row was
#                                          read back (the damage)
#   FAIL <leg> [waited|nowait:<SQLSTATE>]  B was refused otherwise
#   FAIL <leg> [read:<what>]               the read answered wrongly
#   BROKEN <leg>      a session or a read failed for its own reasons
#   SEQUENTIAL <leg>  right, but the wait was never seen
# mutations-30.sh names the whole bracket; all but PASS fail the run. Setup
# failures exit 2. `levy-30.sh selftest` checks the verdicts on literal outputs
# (no database).
# Runs against a THROWAWAY clone (it commits rows).
#   usage: levy-30.sh <db>      (default: r30race)
set -uo pipefail
DB="${1:-r30race}"
PSQL=(docker exec -i tally-pg psql -U tally -d "$DB" -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -q -At)

# verdict(): $1 leg, $2 0 when the result is the right one, $3 what it proves,
# $4 SQL that is true when the damage is in the database (asked only when B
# committed on a wrong result).
verdict() {
local how=nowait state dmg
[ "$WAITED" -eq 1 ] && how=waited
if [ "${AST:-0}" -ne 0 ]; then echo "BROKEN $1: session A itself failed: $(cat "$A_OUT")"; fail=1; return; fi
if [ "$2" -eq 0 ]; then
  if [ "$WAITED" -eq 1 ]; then echo "PASS $1: $3"; else echo "SEQUENTIAL $1: right, but the second session was never seen waiting"; fail=1; fi
  return
fi
fail=1
if [ "$BST" -eq 0 ]; then
  dmg=$(ask "$4")
  if [ "$dmg" = t ]; then echo "FAIL $1 [$how:damage]: session B committed"; else echo "BROKEN $1: session B committed, no damage read back ($dmg): $OUT"; fi
elif [ "$BST" -eq 3 ]; then
  state=$(grep -m1 -oE 'ERROR:  [0-9A-Z]{5}' <<<"$OUT" | cut -c9-)
  if [ -n "$state" ]; then echo "FAIL $1 [$how:$state]: $OUT"; else echo "BROKEN $1: session B failed with no SQLSTATE: $OUT"; fi
else echo "BROKEN $1: session B itself failed (exit $BST): $OUT"; fi
}
# read_verdict(): $1 leg, $2 the read's exit status (a SQL error is 1 from
# psql -c, 3 from a script), $3 its output, $4 the right
# one: an answer, or a SQLSTATE as "ERROR:nnnnn:message", $5 what it proves.
read_verdict() {
local state
if [ "$2" -eq 0 ]; then
  if [ "$3" = "$4" ]; then echo "PASS $1: $5"; else echo "FAIL $1 [read:$3]"; fail=1; fi
elif [ "$2" -eq 3 ] || [ "$2" -eq 1 ]; then
  state=$(grep -m1 -oE 'ERROR:  [0-9A-Z]{5}' <<<"$3" | cut -c9-)
  if [ "ERROR:$state" = "${4:0:11}" ] && grep -qF "${4:12}" <<<"$3"; then echo "PASS $1: $5"
  elif [ "$state" = 21000 ]; then echo "FAIL $1 [read:21000]: $3"; fail=1
  else echo "BROKEN $1: the read failed: $3"; fail=1; fi
else echo "BROKEN $1: the read failed (exit $2): $3"; fail=1; fi
}
ask() { "${PSQL[@]}" -c "SELECT $1" 2>&1; }
# refused(): session B failed with SQLSTATE $1 and a message holding $2.
refused() { [ "$BST" -eq 3 ] && grep -q "ERROR:  $1" <<<"$OUT" && grep -q "$2" <<<"$OUT"; }

if [ "$DB" = selftest ]; then
  bad=0; fail=0; A_OUT=/dev/null; DMG=t
  ask() { echo "$DMG"; }
  want() { local got; got=$(eval "$2" | cut -d: -f1-2 | sed -E 's/\].*/]/'); case $got in "$1"*) ;; *) echo "SELFTEST: wanted $1, got: $got"; bad=1 ;; esac; }
  E='ERROR:  57014: canceling statement due to statement timeout'
  for leg in R1 R3 R5; do for w in 0 1; do
    AST=0 BST=3 WAITED=$w OUT=$E; how=nowait; [ $w -eq 1 ] && how=waited
    want "FAIL $leg [$how:57014]" "verdict $leg 1 x true"
    BST=0 OUT=; DMG=t; want "FAIL $leg [$how:damage]" "verdict $leg 1 x true"
    DMG=f; want "BROKEN $leg" "verdict $leg 1 x true"
    DMG='psql: error: connection to server was lost'; want "BROKEN $leg" "verdict $leg 1 x true"
    BST=2 OUT='psql: error: connection to server was lost'; want "BROKEN $leg" "verdict $leg 1 x true"
    BST=3 OUT='no error text'; want "BROKEN $leg" "verdict $leg 1 x true"
    AST=2 BST=0; want "BROKEN $leg" "verdict $leg 0 x true"
  done; done
  AST=0 BST=3 WAITED=0 OUT='ERROR:  40001: x'; want "SEQUENTIAL R5" "verdict R5 0 x true"
  WAITED=1; want "PASS R5" "verdict R5 0 x true"
  want "BROKEN R6" "read_verdict R6 2 'psql: error: connection to server was lost' within x"
  want "BROKEN R6" "read_verdict R6 3 'ERROR:  42883: function does not exist' within x"
  want "FAIL R6 [read:21000]" "read_verdict R6 3 'ERROR:  21000: more' within x"
  want "FAIL R6 [read:within,within]" "read_verdict R6 0 within,within within x"
  want "PASS R6" "read_verdict R6 0 within within x"
  want "PASS R7" "read_verdict R7 1 'ERROR:  21000: more than one answer' 'ERROR:21000:more than one answer' x"
  want "BROKEN R6" "read_verdict R6 1 'ERROR:  42883: function does not exist' within x"
  want "PASS R7" "read_verdict R7 3 'ERROR:  21000: more than one answer' 'ERROR:21000:more than one answer' x"
  want "FAIL R7 [read:21000]" "read_verdict R7 3 'ERROR:  21000: another refusal' 'ERROR:21000:more than one answer' x"
  want "FAIL R7 [read:outside,within]" "read_verdict R7 0 outside,within 'ERROR:21000:more than one answer' x"
  [ $bad -eq 0 ] && echo "levy-30 selftest: all pass"
  exit $bad
fi

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
L8=00000000-0000-4000-8000-000000003081
PD2=00000000-0000-4000-8000-000000003082
M8=00000000-0000-4000-8000-000000003083
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
# R1
two "$APP $(levy R30-A)" "UPDATE public.places SET effective_to = DATE '2026-06-01' WHERE id = '$PA';"
refused 23001 "a tax levy"; verdict R1 $? "a city closed while a levy on it is in flight waits, then is refused at commit" "EXISTS (SELECT 1 FROM public.tax_levies WHERE place_code = 'R30-A' AND effective_to IS NULL) AND EXISTS (SELECT 1 FROM public.places WHERE id = '$PA' AND effective_to IS NOT NULL)"

# R2
two "UPDATE public.places SET effective_to = DATE '2026-06-01' WHERE id = '$PB';" "BEGIN; $APP $(levy R30-B) COMMIT;"
refused 23514 "in force over the whole"; verdict R2 $? "a levy recorded while its city is being closed waits, then is refused" "EXISTS (SELECT 1 FROM public.tax_levies WHERE place_code = 'R30-B' AND effective_to IS NULL)"

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
refused 40001 "began after this one" && [ "$LAST" = "OK/OK" ]; verdict R3 $? "a correction begun before an overlapping one committed is refused (40001); the history ends on the premise's state" "'$LAST' ~ '^[A-Z]+/[A-Z]+\$' AND split_part('$LAST', '/', 1) <> split_part('$LAST', '/', 2)"

# R4
OUT=$("${PSQL[@]}" 2>&1 <<SQL
BEGIN; $APP UPDATE public.service_locations SET state = 'NM' WHERE id = '$L'; COMMIT;
SQL
); ST=$?
if [ $ST -ne 0 ]; then
  ST4=$(grep -m1 -oE 'ERROR:  [0-9A-Z]{5}' <<<"$OUT" | cut -c9-)
  if [ "$ST4" = 40001 ]; then echo "FAIL R4 [read:40001]: $OUT"; else echo "BROKEN R4: the correction failed: $OUT"; fi; fail=1
else
  OUT=$("${PSQL[@]}" -c "SELECT state FROM public.service_location_state_history WHERE service_location_id = '$L' ORDER BY recorded_at DESC, seq DESC LIMIT 1" 2>&1); ST=$?
  read_verdict R4 $ST "$OUT" NM "a correction begun after the other committed is recorded, last"
fi

# R5
two "UPDATE public.places SET effective_to = DATE '2026-07-01' WHERE id = '$PC';
INSERT INTO public.places (id, kind_code, state_code, place_code, name, parent_place_id, effective_from, source_note)
SELECT '$PC2', 'municipality', 'TX', 'R30-C', 'R30-C (successor)', id, DATE '2026-07-01', 'race fixture'
  FROM public.places WHERE kind_code = 'state' AND place_code = 'TX' AND effective_to IS NULL;" \
    "BEGIN; $APP $(levy R30-C) COMMIT;"
refused 40001 "changed while this waited"; verdict R5 $? "a levy that waited on a city's row is refused when a successor row was committed meanwhile (retry)" "EXISTS (SELECT 1 FROM public.tax_levies WHERE place_code = 'R30-C' AND effective_to IS NULL)"
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
OUT=$("${PSQL[@]}" -c "SELECT string_agg(r.relation, ',' ORDER BY r.relation) FROM public.premise_place_memberships o, LATERAL public.premise_places_as_of('$2', DATE '2026-06-01', 'tax', o.voided_at - interval '1 millisecond') r WHERE o.id = '$3' AND r.place_id = '$PD'" 2>&1); ST=$?
read_verdict "$1" $ST "$OUT" "$5" "$6"
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
rerecord R6 "$L6" "$M6" within within "a district recorded again while its first record is being voided answers once at an instant between the two"
rerecord R7 "$L7" "$M7" outside 'ERROR:21000:more than one answer for one place' "the same recorded again as outside is refused at an instant between the two"
# R8: A begins (and will record the second district), then the bill's
# transaction, then B voids the first and commits, then A commits; the bill,
# still open, reads.
"${PSQL[@]}" >/dev/null <<SQL || { echo "SETUP FAIL: R8 fixtures"; exit 2; }
INSERT INTO public.service_locations (id, tenant_id, customer_id, location_number, address_line1, city, state, zip) VALUES
  ('$L8', '$T', '$C', 'L8', '8 Main', 'Raceville', 'TX', '78701');
INSERT INTO public.places (id, kind_code, state_code, place_code, name, parent_place_id, effective_from, source_note)
SELECT '$PD2', 'special_purpose_district', 'TX', 'R30-D2', 'R30-D2', id, DATE '1950-01-01', 'race fixture'
  FROM public.places WHERE kind_code = 'state' AND place_code = 'TX' AND effective_to IS NULL;
INSERT INTO public.premise_place_memberships (id, tenant_id, service_location_id, place_id, axis, place_kind, valid_from, evidence_kind, evidence_reference, evidence_date) VALUES
  ('$M8', '$T', '$L8', '$PD', 'tax', 'special_purpose_district', DATE '2020-01-01', 'address_lookup', 'Race file', DATE '2020-01-01');
SQL
"${PSQL[@]}" >"$A_OUT" 2>&1 <<SQL &
BEGIN;
$APP
SELECT now();
SELECT pg_sleep(2.5);
INSERT INTO public.premise_place_memberships (tenant_id, service_location_id, place_id, axis, place_kind, valid_from, evidence_kind, evidence_reference, evidence_date)
VALUES ('$T', '$L8', '$PD2', 'tax', 'special_purpose_district', DATE '2020-01-01', 'address_lookup', 'Race file, corrected', DATE '2020-01-01');
COMMIT;
SQL
APID=$!
sleep 0.6
BILL_OUT=$(mktemp); trap 'rm -f "$A_OUT" "$B_OUT" "$BILL_OUT"' EXIT
"${PSQL[@]}" >"$BILL_OUT" 2>&1 <<SQL &
\\o /dev/null
BEGIN;
$APP
SELECT pg_sleep(4);
\\o
SELECT now() > (SELECT n.created_at FROM public.premise_place_memberships n WHERE n.service_location_id = '$L8' AND n.place_id = '$PD2')
   AND now() < (SELECT o.voided_at FROM public.premise_place_memberships o WHERE o.id = '$M8');
SELECT string_agg(place_code, ',' ORDER BY place_code) FROM public.premise_places_as_of('$L8', DATE '2026-06-01', 'tax') WHERE kind_code <> 'state';
COMMIT;
SQL
CPID=$!
sleep 0.6
"${PSQL[@]}" >"$B_OUT" 2>&1 <<SQL
BEGIN; $APP UPDATE public.premise_place_memberships SET void_reason = 'wrong district keyed' WHERE id = '$M8'; COMMIT;
SQL
BST=$?
wait $APID; AST=$?
wait $CPID; CST=$?
if [ $AST -ne 0 ] || [ $BST -ne 0 ] || { [ $CST -eq 0 ] && [ "$(head -1 "$BILL_OUT")" != t ]; }; then
  echo "BROKEN R8: the three did not overlap: $(cat "$A_OUT" "$B_OUT" "$BILL_OUT")"; fail=1
else
  OUT=$(cat "$BILL_OUT"); [ $CST -eq 0 ] && OUT=$(sed -n 2p "$BILL_OUT")
  read_verdict R8 $CST "$OUT" R30-D2 "a bill begun between two overlapping corrections reads the corrected district alone once both are committed"
fi
exit $fail
