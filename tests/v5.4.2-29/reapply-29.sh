#!/usr/bin/env bash
# v5.4.2-29: the load's own rules, which the battery cannot reach (they act
# when the patch applies). Each case plants a state on a fresh clone of
# `tally` (TEMP revoked), applies the patch, and checks the outcome.
#   P1  a county already present under another name          refused
#   P2  a county already present in the other zone           refused
#   P3  a county already present with no zone fact           refused
#   P4  an open Texas county not on the Census list          refused
#   P5  under REPEATABLE READ                                refused
#   P6  as tally_app (TEMP granted, so it reaches places)    refused at places
#   P6b as tally_core (the same)                             refused at places
#   P7  applied twice: the second is a no-op (254 counties, 254 zone facts)
#   P8  r2: after a later migration corrects counties (a zone fact closed
#       and superseded, a county closed and succeeded, a county added from
#       2027), the load re-applies as a no-op (review r1, Opus S1, Fable S1)
#   P9  r2: a code with a row, but none in force on 1900-01-01  refused
#   P10 r3: after Texas itself is closed and succeeded (its counties and
#       facts with it), the load re-applies as a no-op (review r2, Codex B1)
#   P10b r3: on a base without the counties, Texas succeeded from 2027: the
#       252 inserts under the 1900 Texas, now closed, are refused by the
#       parent rule, not by the load's precondition
# P7, P8 and P10 compare every places and place_facts row before and after
# the re-apply (r3; review r2, Codex S3), not only the load's notice.
# A failing case says how it failed, for mutations-29.sh (r3; Codex S1):
#   FAIL Pn [admitted]          a refusal was expected and the load applied
#   FAIL Pn [refused otherwise] it refused, but not with the expected message
#   FAIL Pn [refused]           a no-op was expected and the load refused
#   FAIL Pn [changed]           a no-op was expected and a row changed
# Each refusal is checked by its message: the in-loop comparison's message
# where it fires first (the diagnostic layer); mutations-29.sh shows that the
# postcondition still refuses without it (the guard).
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
  elif [ "$4" -eq 0 ]; then echo "FAIL ${1%% *} [admitted] ${1#* }: expected a refusal naming '$2'"; fail=1
  else echo "FAIL ${1%% *} [refused otherwise] ${1#* }: expected '$2', got: $(echo "$3" | grep -m1 ERROR)"; fail=1; fi
}
fp() {  # every places and place_facts row, as one digest; fails on no answer
  local d; d=$(docker exec tally-pg psql -U tally -d $DB -Atc "SELECT md5(string_agg(t, E'\n' ORDER BY t)) FROM (
    SELECT 'p:' || to_jsonb(p)::text AS t FROM public.places p UNION ALL SELECT 'f:' || to_jsonb(f)::text FROM public.place_facts f) s") || return 1
  [ -n "$d" ] && echo "$d"
}
noop() {  # $1 label, $2 output, $3 exit, $4 digest before, $5 digest after
  if [ "$3" -ne 0 ]; then echo "FAIL ${1%% *} [refused] ${1#* }: $(echo "$2" | grep -m1 ERROR)"; fail=1
  elif ! echo "$2" | grep -q "0 counties loaded, 254 already present" || [ -z "$4" ] || [ "$4" != "$5" ]; then
    echo "FAIL ${1%% *} [changed] ${1#* }: digests $4 / $5: $(echo "$2" | grep -m1 NOTICE)"; fail=1
  else echo "PASS $1"; fi
}
TRAVIS="INSERT INTO public.places (kind_code, state_code, place_code, name, parent_place_id, effective_from, source_note)
        SELECT 'county', 'TX', '48453', %s, id, DATE '1900-01-01', 'planted' FROM public.places WHERE kind_code = 'state' AND place_code = 'TX' AND effective_to IS NULL RETURNING id"

fresh || { echo "SETUP FAIL: clone"; exit 2; }
plant "$(printf "$TRAVIS" "'Travis Co.'");
INSERT INTO public.place_facts (place_id, fact_code, value, effective_from, source_note)
  SELECT id, 'time_zone', '\"America/Chicago\"', DATE '1900-01-01', 'planted' FROM public.places WHERE place_code = '48453';" || { echo "SETUP FAIL P1"; exit 2; }
out=$(apply); refused "P1 a county present under another name is refused, not overwritten" "county 48453 is already present on 1900-01-01 as Travis Co." "$out" $?

fresh || exit 2
plant "$(printf "$TRAVIS" "'Travis County'");
INSERT INTO public.place_facts (place_id, fact_code, value, effective_from, source_note)
  SELECT id, 'time_zone', '\"America/Denver\"', DATE '1900-01-01', 'planted' FROM public.places WHERE place_code = '48453';" || { echo "SETUP FAIL P2"; exit 2; }
out=$(apply); refused "P2 a county present in the other zone is refused" "as Travis County (zone America/Denver), not as the load has it" "$out" $?

fresh || exit 2
plant "$(printf "$TRAVIS" "'Travis County'");" || { echo "SETUP FAIL P3"; exit 2; }
out=$(apply); refused "P3 a county present with no zone fact is refused" "as Travis County (zone none), not as the load has it" "$out" $?

fresh || exit 2
plant "INSERT INTO public.places (kind_code, state_code, place_code, name, parent_place_id, effective_from, source_note)
       SELECT 'county', 'TX', '48990', 'Not A County', id, DATE '1900-01-01', 'planted' FROM public.places WHERE kind_code = 'state' AND place_code = 'TX' AND effective_to IS NULL;" || { echo "SETUP FAIL P4"; exit 2; }
out=$(apply); refused "P4 an open Texas county not on the Census list is refused" "county 48990 is not on the Census list" "$out" $?

fresh || exit 2
out=$(apply "SET default_transaction_isolation = 'repeatable read'"); refused "P5 under REPEATABLE READ the load refuses" "run under READ COMMITTED" "$out" $?

fresh || exit 2
docker exec tally-pg psql -U tally -d $DB -qc "GRANT TEMP ON DATABASE $DB TO tally_app, tally_core" >/dev/null || exit 2
out=$(apply "SET ROLE tally_app"); refused "P6 as tally_app the load refuses at places, not at the temp table" "permission denied for table places" "$out" $?
out=$(apply "SET ROLE tally_core"); refused "P6b as tally_core the load refuses at places" "permission denied for table places" "$out" $?

fresh || exit 2
out1=$(apply); s1=$?; d1=$(fp) || d1=""; out2=$(apply); s2=$?; d2=$(fp) || d2=""
n=$(docker exec tally-pg psql -U tally -d $DB -Atc "SELECT count(DISTINCT p.id) || '/' || count(f.id) FROM public.places p JOIN public.place_facts f ON f.place_id = p.id AND f.fact_code = 'time_zone' WHERE p.kind_code = 'county' AND p.state_code = 'TX'")
if [ $s1 -eq 0 ] && [ $s2 -eq 0 ] && echo "$out1" | grep -q "252 counties loaded, 2 already present" \
   && echo "$out2" | grep -q "0 counties loaded, 254 already present" && [ "$n" = "254/254" ] && [ -n "$d1" ] && [ "$d1" = "$d2" ]; then
  echo "PASS P7 applied twice: 252 loaded, then none, no row changed; 254 counties, 254 zone facts"
elif [ $s1 -ne 0 ] || [ $s2 -ne 0 ]; then echo "FAIL P7 [refused]: exits $s1/$s2: $(echo "$out1 $out2" | grep -m1 ERROR)"; fail=1
else echo "FAIL P7 [changed]: counts $n, digests '$d1' / '$d2': $out1 / $out2"; fail=1; fi

# P8: later corrections, committed on top of the load, then a re-apply. Each
# successor differs from what it replaced (r3; Codex S3), so a re-apply that
# wrote would show in the digest.
fresh || exit 2
out=$(apply); [ $? -eq 0 ] || { echo "SETUP FAIL P8: first apply: $out"; exit 2; }
plant "
-- Culberson's zone fact closed at 2027 and succeeded by Mountain
UPDATE public.place_facts SET effective_to = DATE '2027-01-01'
 WHERE fact_code = 'time_zone' AND place_id = (SELECT id FROM public.places WHERE kind_code = 'county' AND place_code = '48109');
INSERT INTO public.place_facts (place_id, fact_code, value, effective_from, source_note)
  SELECT id, 'time_zone', '\"America/Denver\"', DATE '2027-01-01', 'reapply-29 P8' FROM public.places WHERE kind_code = 'county' AND place_code = '48109';
-- Harris closed at 2027 (its fact first) and succeeded under another name, in Mountain time
UPDATE public.place_facts SET effective_to = DATE '2027-01-01'
 WHERE fact_code = 'time_zone' AND place_id = (SELECT id FROM public.places WHERE kind_code = 'county' AND place_code = '48201');
UPDATE public.places SET effective_to = DATE '2027-01-01' WHERE kind_code = 'county' AND place_code = '48201';
WITH n AS (INSERT INTO public.places (kind_code, state_code, place_code, name, parent_place_id, effective_from, source_note)
           SELECT 'county', 'TX', '48201', 'Harris County (renamed)', id, DATE '2027-01-01', 'reapply-29 P8' FROM public.places WHERE kind_code = 'state' AND place_code = 'TX' AND effective_to IS NULL
           RETURNING id)
INSERT INTO public.place_facts (place_id, fact_code, value, effective_from, source_note) SELECT id, 'time_zone', '\"America/Denver\"', DATE '2027-01-01', 'reapply-29 P8' FROM n;
-- Loving closed at 2026-06-01 (before today) with no successor
UPDATE public.place_facts SET effective_to = DATE '2026-06-01'
 WHERE fact_code = 'time_zone' AND place_id = (SELECT id FROM public.places WHERE kind_code = 'county' AND place_code = '48301');
UPDATE public.places SET effective_to = DATE '2026-06-01' WHERE kind_code = 'county' AND place_code = '48301';
-- a county created in 2027 (not on the 2020 list)
WITH n AS (INSERT INTO public.places (kind_code, state_code, place_code, name, parent_place_id, effective_from, source_note)
           SELECT 'county', 'TX', '48509', 'New County', id, DATE '2027-01-01', 'reapply-29 P8' FROM public.places WHERE kind_code = 'state' AND place_code = 'TX' AND effective_to IS NULL
           RETURNING id)
INSERT INTO public.place_facts (place_id, fact_code, value, effective_from, source_note) SELECT id, 'time_zone', '\"America/Chicago\"', DATE '2027-01-01', 'reapply-29 P8' FROM n;" || { echo "SETUP FAIL P8: the corrections"; exit 2; }
d1=$(fp) || d1=""; out=$(apply); s8=$?; d2=$(fp) || d2=""
noop "P8 after later corrections (a zone superseded by another, a county succeeded under another name, one dissolved, one added) the load re-applies and changes no row" "$out" $s8 "$d1" "$d2"

# P9: Travis present only from 1950.
fresh || exit 2
plant "INSERT INTO public.places (kind_code, state_code, place_code, name, parent_place_id, effective_from, source_note)
       SELECT 'county', 'TX', '48453', 'Travis County', id, DATE '1950-01-01', 'planted' FROM public.places WHERE kind_code = 'state' AND place_code = 'TX' AND effective_to IS NULL;" || { echo "SETUP FAIL P9"; exit 2; }
out=$(apply); refused "P9 a code with a row but none in force on 1900-01-01 is refused by the load, not by the overlap rule" "county 48453 has 1 row(s), none in force on 1900-01-01" "$out" $?

# P10 and P10b: Texas closed at 2027 and succeeded, with every place under it
# and their open facts (the closes child first, through the ordinary rules;
# the shape of review r2, Codex probe 02).
SUCCEED_TX="DO \$s\$
DECLARE r record; v_parent uuid;
BEGIN
  CREATE TEMP TABLE old_tree ON COMMIT DROP AS
  WITH RECURSIVE tree AS (
    SELECT p.id, 0 AS depth FROM public.places p WHERE kind_code = 'state' AND state_code = 'TX' AND place_code = 'TX' AND effective_to IS NULL
    UNION ALL SELECT p.id, t.depth + 1 FROM public.places p JOIN tree t ON p.parent_place_id = t.id)
  SELECT p.*, t.depth, public.uuid_generate_v4() AS successor FROM tree t JOIN public.places p ON p.id = t.id;
  UPDATE public.place_facts f SET effective_to = DATE '2027-01-01' FROM old_tree t WHERE f.place_id = t.id AND f.effective_to IS NULL;
  CREATE TEMP TABLE old_facts ON COMMIT DROP AS SELECT f.* FROM public.place_facts f JOIN old_tree t ON t.id = f.place_id WHERE f.effective_to = DATE '2027-01-01';
  FOR r IN SELECT * FROM old_tree WHERE effective_to IS NULL ORDER BY depth DESC, id LOOP
    UPDATE public.places SET effective_to = DATE '2027-01-01' WHERE id = r.id;
  END LOOP;
  FOR r IN SELECT * FROM old_tree WHERE effective_to IS NULL ORDER BY depth, id LOOP
    SELECT successor INTO v_parent FROM old_tree WHERE id = r.parent_place_id;
    INSERT INTO public.places (id, kind_code, state_code, place_code, name, parent_place_id, effective_from, source_note)
    VALUES (r.successor, r.kind_code, r.state_code, r.place_code, r.name, v_parent, DATE '2027-01-01', 'reapply-29 P10');
  END LOOP;
  INSERT INTO public.place_facts (place_id, fact_code, fact_key, value, effective_from, source_note)
  SELECT t.successor, f.fact_code, f.fact_key, f.value, DATE '2027-01-01', 'reapply-29 P10'
    FROM old_facts f JOIN old_tree t ON t.id = f.place_id;
END \$s\$;"
fresh || exit 2
out=$(apply); [ $? -eq 0 ] || { echo "SETUP FAIL P10: first apply: $out"; exit 2; }
plant "BEGIN; $SUCCEED_TX COMMIT;" || { echo "SETUP FAIL P10: the succession"; exit 2; }
d1=$(fp) || d1=""; out=$(apply); s10=$?; d2=$(fp) || d2=""
noop "P10 after Texas itself is succeeded, the load re-applies and changes no row" "$out" $s10 "$d1" "$d2"

fresh || exit 2
plant "BEGIN; $SUCCEED_TX COMMIT;" || { echo "SETUP FAIL P10b: the succession"; exit 2; }
out=$(apply); refused "P10b a county to insert under the 1900 Texas, closed since, is refused by the parent rule" "is not a state of state TX in force over 1900-01-01..open" "$out" $?

exit $fail
