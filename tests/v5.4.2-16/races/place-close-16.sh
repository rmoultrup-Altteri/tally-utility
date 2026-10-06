#!/usr/bin/env bash
# v5.4.2-16: a place's close floor counts memberships and profiles that the
# application writes at run time, so it races them. Both sides take the
# place's advisory lock (memberships and profiles shared, the close
# exclusive) and the close runs only under READ COMMITTED.
#   R1  A records a membership in a city and holds; B's close of the city
#       before the membership's end waits, then sees it and is refused.
#   R2  the same with a utility profile owned by the city.
#   R3  a close under REPEATABLE READ is refused.
# Runs against a THROWAWAY clone (it commits rows).
#   usage: place-close-16.sh <db>      (default: s16)
set -uo pipefail
DB="${1:-s16}"
PSQL=(docker exec -i tally-pg psql -U tally -d "$DB" -v ON_ERROR_STOP=1 -q -At)

T=00000000-0000-4000-8000-0000000016e1
U=00000000-0000-4000-8000-0000000016e2
C=00000000-0000-4000-8000-0000000016e3
L=00000000-0000-4000-8000-0000000016e4
P1=00000000-0000-4000-8000-0000000016f1
P2=00000000-0000-4000-8000-0000000016f2
P3=00000000-0000-4000-8000-0000000016f3

"${PSQL[@]}" <<SQL >/dev/null
INSERT INTO public.tenants (id, name, slug) VALUES ('$T', 'Race City Gas', 'race16-$RANDOM$RANDOM');
INSERT INTO public.users (id, tenant_id, display_name, email, role) VALUES ('$U', '$T', 'OpR', 'opr$RANDOM@race16.test', 'operator');
INSERT INTO public.customers (id, tenant_id, customer_number, customer_type) VALUES ('$C', '$T', 'RACE-C', 'residential');
INSERT INTO public.service_locations (id, tenant_id, customer_id, location_number, address_line1, city, state, zip)
  VALUES ('$L', '$T', '$C', 'L', '1 Main', 'Raceville', 'TX', '78701');
INSERT INTO public.places (id, kind_code, state_code, place_code, name, parent_place_id, effective_from, source_note)
SELECT v.id, 'municipality', 'TX', v.code, v.code, s.id, DATE '1950-01-01', 'race fixture'
  FROM (VALUES ('$P1'::uuid, 'RACE1'), ('$P2'::uuid, 'RACE2'), ('$P3'::uuid, 'RACE3')) v(id, code),
       (SELECT id FROM public.places WHERE kind_code = 'state' AND place_code = 'TX') s;
SQL

fail=0
A_OUT=$(mktemp); trap 'rm -f "$A_OUT"' EXIT

race() {  # $1 label, $2 A's insert, $3 place to close
"${PSQL[@]}" >"$A_OUT" 2>&1 <<SQL &
BEGIN;
SET LOCAL app.user_id = '$U';
SET ROLE tally_app;
$2
SELECT pg_sleep(3);
COMMIT;
SQL
sleep 1
OUT=$("${PSQL[@]}" 2>&1 <<SQL
UPDATE public.places SET effective_to = DATE '2030-01-01' WHERE id = '$3';
SQL
)
wait
}

# R1
race R1 "INSERT INTO public.premise_place_memberships (tenant_id, service_location_id, place_id, axis, place_kind, single_per_premise,
          valid_from, evidence_kind, evidence_reference) VALUES ('$T', '$L', '$P1', 'regulatory', 'x', true, DATE '2026-01-01', 'ordinance', 'Ord. 1');" "$P1"
if grep -q "a premise membership" <<<"$OUT"; then
  echo "PASS R1: a place closed while a membership in it is in flight waits on the place lock, then sees it and is refused"
else
  echo "FAIL R1: the close said: $OUT (A: $(cat "$A_OUT"))"; fail=1
fi

# R2
race R2 "INSERT INTO public.utility_service_profiles (tenant_id, service_type, state_code, owner_type, commission_jurisdiction, owning_place_id,
          effective_from, evidence_reference) VALUES ('$T', 'gas', 'TX', 'municipal', false, '$P2', DATE '2026-01-01', 'Charter');" "$P2"
if grep -q "a utility profile" <<<"$OUT"; then
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
if grep -q "a close runs only under READ COMMITTED" <<<"$OUT"; then
  echo "PASS R3: a place is closed only under READ COMMITTED"
else
  echo "FAIL R3: $OUT"; fail=1
fi
exit $fail
