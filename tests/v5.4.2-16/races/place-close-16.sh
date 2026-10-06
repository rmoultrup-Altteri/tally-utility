#!/usr/bin/env bash
# v5.4.2-16: a place's close floor counts memberships and profiles that the
# application writes at run time, so it races them. Both sides take the
# place's advisory lock (memberships and profiles shared, the close
# exclusive) and the close runs only under READ COMMITTED.
#   R1  A records a membership in a city and holds; B's close of the city
#       before the membership's end waits, then sees it and is refused.
#   R2  the same with a utility profile owned by the city.
#   R3  a close under REPEATABLE READ is refused.
#   R4  a membership recorded under REPEATABLE READ is refused (review r1 B1:
#       its snapshot could predate a close it waited for).
#   R5  the same for a utility profile.
#   R6  the same for a jurisdiction pointed at a place.
#   R7  A records a membership and holds; B's change of the premise's state
#       waits on A's share lock, then sees it and is refused (review r1 B2).
#   R8  a change of a premise's state under REPEATABLE READ is refused.
#   R9  a respelling of the same state (' tx ' for TX) under REPEATABLE READ
#       is no change, and is allowed.
#   R10 A points a jurisdiction at a place and holds; B's close waits, then
#       sees the pointer and is refused (review r2: the pointer's lock).
#   R11 A closes a place and holds; B's pointer at it waits, then sees the
#       close and is refused.
#   R12 A closes a place and holds; B's membership in it waits, then sees the
#       close and is refused (R1 in the other order).
# Every two-session leg also checks that the second session was SEEN WAITING
# (pg_stat_activity, wait_event_type Lock) before the first committed, so a
# leg cannot pass by running sequentially (review r2, Codex).
# Runs against a THROWAWAY clone (it commits rows).
#   usage: place-close-16.sh <db>      (default: s16)
set -uo pipefail
DB="${1:-s16}"
PSQL=(docker exec -i tally-pg psql -U tally -d "$DB" -v ON_ERROR_STOP=1 -q -At)

T=00000000-0000-4000-8000-0000000016e1
U=00000000-0000-4000-8000-0000000016e2
C=00000000-0000-4000-8000-0000000016e3
L=00000000-0000-4000-8000-0000000016e4
L2=00000000-0000-4000-8000-0000000016e5
P1=00000000-0000-4000-8000-0000000016f1
P2=00000000-0000-4000-8000-0000000016f2
P3=00000000-0000-4000-8000-0000000016f3
P4=00000000-0000-4000-8000-0000000016f4
P5=00000000-0000-4000-8000-0000000016f5
P6=00000000-0000-4000-8000-0000000016f6

"${PSQL[@]}" <<SQL >/dev/null
INSERT INTO public.tenants (id, name, slug) VALUES ('$T', 'Race City Gas', 'race16-$RANDOM$RANDOM');
INSERT INTO public.users (id, tenant_id, display_name, email, role) VALUES ('$U', '$T', 'OpR', 'opr$RANDOM@race16.test', 'operator');
INSERT INTO public.customers (id, tenant_id, customer_number, customer_type) VALUES ('$C', '$T', 'RACE-C', 'residential');
INSERT INTO public.service_locations (id, tenant_id, customer_id, location_number, address_line1, city, state, zip)
  VALUES ('$L', '$T', '$C', 'L', '1 Main', 'Raceville', 'TX', '78701'),
         ('$L2', '$T', '$C', 'L2', '2 Main', 'Raceville', 'TX', '78701');
INSERT INTO public.places (id, kind_code, state_code, place_code, name, parent_place_id, effective_from, source_note)
SELECT v.id, 'municipality', 'TX', v.code, v.code, s.id, DATE '1950-01-01', 'race fixture'
  FROM (VALUES ('$P1'::uuid, 'RACE1'), ('$P2'::uuid, 'RACE2'), ('$P3'::uuid, 'RACE3'),
               ('$P4'::uuid, 'RACE4'), ('$P5'::uuid, 'RACE5'), ('$P6'::uuid, 'RACE6')) v(id, code),
       (SELECT id FROM public.places WHERE kind_code = 'state' AND place_code = 'TX') s;
SQL

fail=0
A_OUT=$(mktemp); B_OUT=$(mktemp); trap 'rm -f "$A_OUT" "$B_OUT"' EXIT

waiting() {  # sessions of this database blocked on a lock right now
docker exec -i tally-pg psql -U tally -d "$DB" -At -c "SELECT count(*) FROM pg_stat_activity WHERE datname = current_database() AND wait_event_type = 'Lock'"
}

# two(): A's SQL holds 3s; B's SQL starts 1s later in the background; we
# sample whether B is blocked, then collect both. Sets OUT (B) and WAITED.
two() {  # $1 A's SQL (owner or app), $2 B's SQL
"${PSQL[@]}" >"$A_OUT" 2>&1 <<SQL &
BEGIN;
$1
SELECT pg_sleep(3);
COMMIT;
SQL
sleep 1
"${PSQL[@]}" >"$B_OUT" 2>&1 <<SQL &
$2
SQL
sleep 1
WAITED=$(waiting)
wait
OUT=$(cat "$B_OUT")
}

race() {  # $1 label, $2 A's insert (as the app), $3 place B closes (owner)
two "SET LOCAL app.user_id = '$U'; SET ROLE tally_app; $2" \
    "UPDATE public.places SET effective_to = DATE '2030-01-01' WHERE id = '$3';"
}
seen() {  # $1 label: the second session must have been seen waiting
if [ "${WAITED:-0}" -lt 1 ]; then echo "FAIL $1: the second session was never seen waiting (sequential, not a race)"; fail=1; return 1; fi
}

# R1
race R1 "INSERT INTO public.premise_place_memberships (tenant_id, service_location_id, place_id, axis, place_kind, exclusivity_group,
          valid_from, evidence_kind, evidence_reference, evidence_date) VALUES ('$T', '$L', '$P1', 'regulatory', 'x', NULL, DATE '2026-01-01', 'ordinance', 'Ord. 1', DATE '2025-12-01');" "$P1"
if seen R1 && grep -q "a premise membership" <<<"$OUT"; then
  echo "PASS R1: a place closed while a membership in it is in flight waits on the place lock, then sees it and is refused"
else
  echo "FAIL R1: the close said: $OUT (A: $(cat "$A_OUT"))"; fail=1
fi

# R2
race R2 "INSERT INTO public.utility_service_profiles (tenant_id, service_type, state_code, owner_type, commission_jurisdiction, owning_place_id,
          effective_from, evidence_reference, evidence_date) VALUES ('$T', 'gas', 'TX', 'municipal', false, '$P2', DATE '2026-01-01', 'Charter', DATE '2025-01-01');" "$P2"
if seen R2 && grep -q "a utility profile" <<<"$OUT"; then
  echo "PASS R2: a place closed while a profile it owns is in flight waits, then sees it and is refused"
else
  echo "FAIL R2: the close said: $OUT (A: $(cat "$A_OUT"))"; fail=1
fi

# R3
OUT=$("${PSQL[@]}" 2>&1 <<SQL
BEGIN ISOLATION LEVEL REPEATABLE READ;
UPDATE public.places SET effective_to = DATE '2030-01-01' WHERE id = '$P3';
COMMIT;
SQL
)
if grep -q "closing place .* runs only under READ COMMITTED" <<<"$OUT"; then
  echo "PASS R3: a place is closed only under READ COMMITTED"
else
  echo "FAIL R3: $OUT"; fail=1
fi
rr() {  # $1 label, $2 statement, $3 expected message fragment
OUT=$("${PSQL[@]}" 2>&1 <<SQL
BEGIN ISOLATION LEVEL REPEATABLE READ;
SET LOCAL app.user_id = '$U';
SET ROLE tally_app;
$2
COMMIT;
SQL
)
if grep -q "$3" <<<"$OUT"; then echo "PASS $1"; else echo "FAIL $1: $OUT"; fail=1; fi
}
rr "R4: a membership is recorded only under READ COMMITTED" \
   "INSERT INTO public.premise_place_memberships (tenant_id, service_location_id, place_id, axis, place_kind, valid_from, evidence_kind, evidence_reference, evidence_date)
    VALUES ('$T', '$L', '$P3', 'regulatory', 'x', DATE '2026-01-01', 'ordinance', 'Ord. 2', DATE '2025-12-01');" \
   "recording a premise place membership runs only under READ COMMITTED"
rr "R5: a profile is recorded only under READ COMMITTED" \
   "INSERT INTO public.utility_service_profiles (tenant_id, service_type, state_code, owner_type, commission_jurisdiction, owning_place_id, effective_from, evidence_reference, evidence_date)
    VALUES ('$T', 'water', 'TX', 'municipal', false, '$P3', DATE '2026-01-01', 'Charter', DATE '2025-01-01');" \
   "recording a utility service profile runs only under READ COMMITTED"
rr "R6: a jurisdiction is pointed at a place only under READ COMMITTED" \
   "INSERT INTO public.jurisdictions (tenant_id, jurisdiction_code, jurisdiction_name, place_id) VALUES ('$T', 'R6', 'R6', '$P3');" \
   "at a place runs only under READ COMMITTED"

# R7: A records a membership (in P3) and holds; B moves the premise to OK.
two "SET LOCAL app.user_id = '$U'; SET ROLE tally_app;
INSERT INTO public.premise_place_memberships (tenant_id, service_location_id, place_id, axis, place_kind, valid_from, evidence_kind, evidence_reference, evidence_date)
VALUES ('$T', '$L2', '$P3', 'tax', 'x', DATE '2026-01-01', 'ordinance', 'Ord. 3', DATE '2025-12-01');" \
    "UPDATE public.service_locations SET state = 'OK' WHERE id = '$L2';"
if seen R7 && grep -q "it has memberships of places in TX" <<<"$OUT"; then
  echo "PASS R7: a premise's state change racing a membership waits on its share lock, then sees it and is refused"
else
  echo "FAIL R7: the change said: $OUT (A: $(cat "$A_OUT"))"; fail=1
fi
OUT=$("${PSQL[@]}" 2>&1 <<SQL
BEGIN ISOLATION LEVEL REPEATABLE READ;
UPDATE public.service_locations SET state = 'OK' WHERE id = '$L';
COMMIT;
SQL
)
if grep -q "runs only under READ COMMITTED" <<<"$OUT"; then
  echo "PASS R8: a premise's state is changed only under READ COMMITTED"
else
  echo "FAIL R8: $OUT"; fail=1
fi
OUT=$("${PSQL[@]}" 2>&1 <<SQL
BEGIN ISOLATION LEVEL REPEATABLE READ;
UPDATE public.service_locations SET state = ' tx ' WHERE id = '$L';
COMMIT;
SQL
)
if [ -z "$(grep -i error <<<"$OUT")" ]; then
  echo "PASS R9: respelling a premise's state is no change of state, under any isolation"
else
  echo "FAIL R9: $OUT"; fail=1
fi

# R10: A points a jurisdiction at P4 and holds; B closes P4.
two "SET LOCAL app.user_id = '$U'; SET ROLE tally_app;
INSERT INTO public.jurisdictions (tenant_id, jurisdiction_code, jurisdiction_name, place_id) VALUES ('$T', 'R10', 'R10', '$P4');" \
    "UPDATE public.places SET effective_to = DATE '2030-01-01' WHERE id = '$P4';"
if seen R10 && grep -q "a utility jurisdiction" <<<"$OUT"; then
  echo "PASS R10: a place closed while a jurisdiction pointer at it is in flight waits, then sees it and is refused"
else
  echo "FAIL R10: the close said: $OUT (A: $(cat "$A_OUT"))"; fail=1
fi
# R11: A (owner) closes P5 and holds; B points a jurisdiction at P5.
two "UPDATE public.places SET effective_to = DATE '2030-01-01' WHERE id = '$P5';" \
    "BEGIN; SET LOCAL app.user_id = '$U'; SET ROLE tally_app;
INSERT INTO public.jurisdictions (tenant_id, jurisdiction_code, jurisdiction_name, place_id) VALUES ('$T', 'R11', 'R11', '$P5'); COMMIT;"
if seen R11 && grep -q "has a close date" <<<"$OUT"; then
  echo "PASS R11: a jurisdiction pointed at a place while its close is in flight waits, then sees the close and is refused"
else
  echo "FAIL R11: the pointer said: $OUT (A: $(cat "$A_OUT"))"; fail=1
fi
# R12: A (owner) closes P6 from 2026-01-01 and holds; B records a membership in P6 from 2026-06-01.
two "UPDATE public.places SET effective_to = DATE '2026-01-01' WHERE id = '$P6';" \
    "BEGIN; SET LOCAL app.user_id = '$U'; SET ROLE tally_app;
INSERT INTO public.premise_place_memberships (tenant_id, service_location_id, place_id, axis, place_kind, valid_from, evidence_kind, evidence_reference, evidence_date)
VALUES ('$T', '$L2', '$P6', 'regulatory', 'x', DATE '2026-06-01', 'ordinance', 'Ord. 12', DATE '2025-12-01'); COMMIT;"
if seen R12 && grep -q "not over the whole membership" <<<"$OUT"; then
  echo "PASS R12: a membership recorded while its place's close is in flight waits, then sees the close and is refused"
else
  echo "FAIL R12: the membership said: $OUT (A: $(cat "$A_OUT"))"; fail=1
fi
exit $fail
