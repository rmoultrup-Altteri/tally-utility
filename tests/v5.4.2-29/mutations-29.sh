#!/usr/bin/env bash
# Mutation run for v5.4.2-29: each mutation breaks one rule of the load and
# must be caught where it names:
#   a battery label (C1, Z2 …)   the mutated patch applies; battery-29 fails there
#   APPLY:<fragment>             the mutated patch itself refuses, naming it
#   RE:<case>                    reapply-29.sh, run on the mutated patch, fails that case
#   SRC:<case>                   source-check-29.sh fails that case
# A catch elsewhere fails the run. EXTRA: a JSON list of further [old, new]
# edits, each matching exactly once.
#   tests/v5.4.2-29/mutations-29.sh [patch]    (uses m29 and r29re; one run at a time)
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
P=${1:-$ROOT/sql/v5.4.2-29-texas-counties.sql}
B=$ROOT/tests/v5.4.2-29/battery-29.sql
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"; docker exec tally-pg psql -U tally -d postgres -qc "DROP DATABASE IF EXISTS m29" >/dev/null 2>&1' EXIT
docker cp "$B" tally-pg:/tmp/b29m.sql >/dev/null
fail=0; n=0; caught=0

mut() {  # $1 label, $2 expected, $3 old text (exactly once), $4 new text
  n=$((n + 1)); local exp=$2 got=""
  if ! python3 -c 'import sys, os, json
s = open(sys.argv[1]).read()
edits = [(sys.argv[2], sys.argv[3])] + [tuple(e) for e in json.loads(os.environ.get("EXTRA") or "[]")]
for o, w in edits:
    k = s.count(o)
    if k != 1: sys.exit("anchor matched %d times" % k)
    s = s.replace(o, w)
open(sys.argv[4], "w").write(s)' "$P" "$3" "$4" "$TMP/m.sql"; then
    echo "SETUP $1: anchor not found exactly once"; fail=1; return
  fi
  case $exp in
    RE:*)  got="RE:$(tests/v5.4.2-29/reapply-29.sh "$TMP/m.sql" 2>&1 | grep -m1 -o '^FAIL P[0-9]*' | cut -d' ' -f2)" ;;
    SRC:*) got="SRC:$(tests/v5.4.2-29/source-check-29.sh "$TMP/m.sql" 2>&1 | grep -m1 -o '^FAIL S[0-9a-z]*' | cut -d' ' -f2)" ;;
    *)
      docker exec tally-pg psql -U tally -d postgres -qc "DROP DATABASE IF EXISTS m29" -qc "CREATE DATABASE m29 TEMPLATE tally" >/dev/null 2>&1
      docker exec tally-pg psql -U tally -d m29 -qc "REVOKE TEMP ON DATABASE m29 FROM PUBLIC" -qc "REVOKE TEMP ON DATABASE m29 FROM tally_app" -qc "REVOKE TEMP ON DATABASE m29 FROM tally_core" >/dev/null
      docker cp "$TMP/m.sql" tally-pg:/tmp/m29.sql >/dev/null
      aout=$(docker exec -e PGOPTIONS="-c search_path= -c check_function_bodies=on" tally-pg psql -U tally -d m29 -v ON_ERROR_STOP=1 -q -o /dev/null -f /tmp/m29.sql 2>&1); ast=$?
      if [ $ast -ne 0 ]; then
        if [ "${exp#APPLY:}" != "$exp" ] && echo "$aout" | grep -q -- "${exp#APPLY:}"; then got=$exp
        else got="APPLY ($(echo "$aout" | grep -m1 ERROR | cut -c1-160))"; fi
      else
        bout=$(docker exec tally-pg psql -U tally -d m29 -v ON_ERROR_STOP=1 -q -o /dev/null -f /tmp/b29m.sql 2>&1); bst=$?
        got=$(echo "$bout" | grep -m1 -o "FAIL [A-Za-z0-9]*" | cut -d' ' -f2)
        [ -z "$got" ] && [ $bst -ne 0 ] && got="UNLABELLED ($(echo "$bout" | grep -m1 ERROR | cut -c1-160))"
      fi ;;
  esac
  if [ "$got" = "$exp" ]; then echo "caught $1 at $got"; caught=$((caught + 1))
  elif [ -z "$got" ] || [ "$got" = "RE:" ] || [ "$got" = "SRC:" ]; then echo "MISSED $1 (named $exp)"; fail=1
  else echo "WRONG CHECK $1: caught at $got, named $exp"; fail=1; fi
}

mut "N1 a county left out of the list" "APPLY:the list is not 254" \
  "    ('48505', 'Zapata County', 'America/Chicago'),
" ""
EXTRA='[["IF (SELECT count(*) FROM p29_counties) <> 254\n       OR", "IF false\n       OR"]]' \
mut "N2 a county left out, and the count check gone" C1 \
  "    ('48505', 'Zapata County', 'America/Chicago'),
" ""
mut "N2b a county left out: the source check" SRC:S2 \
  "    ('48505', 'Zapata County', 'America/Chicago'),
" ""
mut "N3 Culberson in Mountain time" "APPLY:Mountain exactly at 48141 and 48229" \
  "('48109', 'Culberson County', 'America/Chicago')" "('48109', 'Culberson County', 'America/Denver')"
EXTRA='[["IS DISTINCT FROM ARRAY['"'"'48141'"'"', '"'"'48229'"'"'] THEN", "IS DISTINCT FROM (SELECT array_agg(fips ORDER BY fips) FROM p29_counties WHERE zone = '"'"'America/Denver'"'"') THEN"]]' \
mut "N4 Culberson in Mountain time, and the list's zone check gone" C3 \
  "('48109', 'Culberson County', 'America/Chicago')" "('48109', 'Culberson County', 'America/Denver')"
mut "N5 a county misnamed" C1b \
  "('48201', 'Harris County'," "('48201', 'Haris County',"
mut "N5b a county misnamed: the source check" SRC:S2b \
  "('48201', 'Harris County'," "('48201', 'Haris County',"
mut "N6 a present county's name not compared" RE:P1 \
  "IF v_place.name IS DISTINCT FROM r.name OR v_zone" "IF false AND v_place.name IS DISTINCT FROM r.name OR v_zone"
mut "N7 a present county's zone not compared" RE:P2 \
  " OR v_zone IS DISTINCT FROM r.zone THEN" " THEN"
mut "N8 a present county's missing zone read as agreeing" RE:P3 \
  "OR v_zone IS DISTINCT FROM r.zone THEN" "OR coalesce(v_zone, r.zone) IS DISTINCT FROM r.zone THEN"
mut "N9 a county not on the list not refused" RE:P4 \
  "AND NOT EXISTS (SELECT 1 FROM p29_counties c WHERE c.fips = p.place_code)" "AND false"
mut "N10 the isolation check gone" RE:P5 \
  "IF current_setting('transaction_isolation') <> 'read committed' THEN" "IF false THEN"
mut "N11 a loaded county's zone dated from 1950" "APPLY:does not carry exactly one open time_zone fact" \
  "VALUES (v_place.id, 'time_zone', to_jsonb(r.zone), c_from," "VALUES (v_place.id, 'time_zone', to_jsonb(r.zone), DATE '1950-01-01',"
mut "N12 a present county skipped without a look (always CONTINUE)" RE:P1 \
  "        IF FOUND THEN
" "        IF FOUND THEN CONTINUE;
"
# every case fails under N13; the first is P1, because seeded El Paso (48141) is reloaded before Travis is reached
mut "N13 a present county reloaded rather than skipped" RE:P1 \
  "            CONTINUE;
        END IF;" "        END IF;"

echo "mutations-29: $caught of $n caught"
[ $fail -eq 0 ] && [ $caught -eq $n ]
