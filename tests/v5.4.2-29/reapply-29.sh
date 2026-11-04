#!/usr/bin/env bash
# v5.4.2-29: the load's own rules, which the battery cannot reach (they act
# when the patch applies). Each case plants a state on a fresh clone of
# `tally` (TEMP revoked), applies the patch, and checks the outcome.
#   P1  a county already present under another name          refused
#   P2  a county already present in the other zone           refused
#   P3  a county already present with no zone fact           refused
#   P4  an open Texas county not on the Census list          refused
#   P5  under REPEATABLE READ                                refused
#   P6  as tally_app                                         refused
#   P7  applied twice: the second is a no-op (254 counties, 254 zone facts)
#   usage: reapply-29.sh [patch]       (uses database r29re; one run at a time)
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
P=${1:-$ROOT/sql/v5.4.2-29-texas-counties.sql}
DB=r29re
trap 'docker exec tally-pg psql -U tally -d postgres -qc "DROP DATABASE IF EXISTS $DB" >/dev/null 2>&1' EXIT
docker cp "$P" tally-pg:/tmp/p29re.sql >/dev/null || { echo "SETUP FAIL: copy"; exit 2; }
fail=0

fresh() {
  docker exec tally-pg psql -U tally -d postgres -qc "DROP DATABASE IF EXISTS $DB" -qc "CREATE DATABASE $DB TEMPLATE tally" >/dev/null 2>&1 &&
  docker exec tally-pg psql -U tally -d $DB -qc "REVOKE TEMP ON DATABASE $DB FROM PUBLIC" -qc "REVOKE TEMP ON DATABASE $DB FROM tally_app" -qc "REVOKE TEMP ON DATABASE $DB FROM tally_core" >/dev/null
}
plant() {  # $1 SQL, run as the owner and committed
  docker exec -i tally-pg psql -U tally -d $DB -v ON_ERROR_STOP=1 -q >/dev/null <<<"$1"
}
apply() {  # [$1 SQL run first in the same session]
  docker exec -e PGOPTIONS="-c search_path= -c check_function_bodies=on" tally-pg \
    psql -U tally -d $DB -v ON_ERROR_STOP=1 -q ${1:+-c "$1"} -f /tmp/p29re.sql 2>&1
}
refused() {  # $1 label, $2 fragment, $3 output, $4 exit
  if [ "$4" -ne 0 ] && echo "$3" | grep -q -- "$2"; then echo "PASS $1"
  else echo "FAIL $1: exit $4, expected a refusal naming '$2': $(echo "$3" | grep -m1 -E 'ERROR|NOTICE')"; fail=1; fi
}
TRAVIS="INSERT INTO public.places (kind_code, state_code, place_code, name, parent_place_id, effective_from, source_note)
        SELECT 'county', 'TX', '48453', %s, id, DATE '1900-01-01', 'planted' FROM public.places WHERE kind_code = 'state' AND place_code = 'TX' AND effective_to IS NULL RETURNING id"

fresh || { echo "SETUP FAIL: clone"; exit 2; }
plant "$(printf "$TRAVIS" "'Travis Co.'");
INSERT INTO public.place_facts (place_id, fact_code, value, effective_from, source_note)
  SELECT id, 'time_zone', '\"America/Chicago\"', DATE '1900-01-01', 'planted' FROM public.places WHERE place_code = '48453';" || { echo "SETUP FAIL P1"; exit 2; }
out=$(apply); refused "P1 a county present under another name is refused, not overwritten" "county 48453 is already present as Travis Co." "$out" $?

fresh || exit 2
plant "$(printf "$TRAVIS" "'Travis County'");
INSERT INTO public.place_facts (place_id, fact_code, value, effective_from, source_note)
  SELECT id, 'time_zone', '\"America/Denver\"', DATE '1900-01-01', 'planted' FROM public.places WHERE place_code = '48453';" || { echo "SETUP FAIL P2"; exit 2; }
out=$(apply); refused "P2 a county present in the other zone is refused" "zone America/Denver), not as the load has it" "$out" $?

fresh || exit 2
plant "$(printf "$TRAVIS" "'Travis County'");" || { echo "SETUP FAIL P3"; exit 2; }
out=$(apply); refused "P3 a county present with no zone fact is refused" "0 open zone fact(s), zone none" "$out" $?

fresh || exit 2
plant "INSERT INTO public.places (kind_code, state_code, place_code, name, parent_place_id, effective_from, source_note)
       SELECT 'county', 'TX', '48990', 'Not A County', id, DATE '1900-01-01', 'planted' FROM public.places WHERE kind_code = 'state' AND place_code = 'TX' AND effective_to IS NULL;" || { echo "SETUP FAIL P4"; exit 2; }
out=$(apply); refused "P4 an open Texas county not on the Census list is refused" "county 48990 is not on the Census list" "$out" $?

fresh || exit 2
out=$(apply "SET default_transaction_isolation = 'repeatable read'"); refused "P5 under REPEATABLE READ the load refuses" "run under READ COMMITTED" "$out" $?

fresh || exit 2
out=$(apply "SET ROLE tally_app"); refused "P6 as tally_app the load refuses" "permission denied" "$out" $?

fresh || exit 2
out1=$(apply); s1=$?; out2=$(apply); s2=$?
n=$(docker exec tally-pg psql -U tally -d $DB -Atc "SELECT count(DISTINCT p.id) || '/' || count(f.id) FROM public.places p JOIN public.place_facts f ON f.place_id = p.id AND f.fact_code = 'time_zone' WHERE p.kind_code = 'county' AND p.state_code = 'TX'")
if [ $s1 -eq 0 ] && [ $s2 -eq 0 ] && echo "$out1" | grep -q "252 counties loaded, 2 already present" \
   && echo "$out2" | grep -q "0 counties loaded, 254 already present" && [ "$n" = "254/254" ]; then
  echo "PASS P7 applied twice: 252 loaded, then none; 254 counties, 254 zone facts"
else echo "FAIL P7: exits $s1/$s2, counts $n: $out1 / $out2"; fail=1; fi

exit $fail
