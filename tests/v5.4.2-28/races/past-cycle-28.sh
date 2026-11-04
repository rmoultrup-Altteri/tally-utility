#!/usr/bin/env bash
# v5.4.2-28 r2 (Opus S1): a dependency's recorded_at is its transaction's
# start, so the cycle walk must count a link that another session closed
# AFTER that start: the two were known together at an instant in between.
#   P1  B on A is committed. Session 1 begins and sleeps. Session 2 retracts
#       B on A and commits. Session 1 then inserts A on B: refused (a cycle
#       as known at session 1's recorded_at).
#   P2  the as-of read, sampled at 41 instants 100 ms apart from session 1's
#       start, never holds both A on B and B on A.
#   P3  control: a transaction that begins after the retraction committed
#       records A on B (the walk does not over-refuse).
# Ordering (r2 review, Codex S1): session 1 takes its start, then waits
# (bounded, polling with fresh snapshots) until it SEES session 2's close
# committed, and only then inserts; it reports both stages. Its start is
# checked to be before the close, so the leg can pass neither by running in
# order nor by inserting before the close. Setup failures exit 2.
# Runs against a THROWAWAY clone (it commits rows).
#   usage: past-cycle-28.sh <db>      (default: r28race)
set -uo pipefail
DB="${1:-r28race}"
PSQL=(docker exec -i tally-pg psql -U tally -d "$DB" -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -q -At)

T=00000000-0000-4000-8000-0000000028e1
U=00000000-0000-4000-8000-0000000028e2
S=00000000-0000-4000-8000-0000000028e4
A=00000000-0000-4000-8000-0000000028e5
B=00000000-0000-4000-8000-0000000028e6
BA=00000000-0000-4000-8000-0000000028e7
S1_OUT=$(mktemp); S2_OUT=$(mktemp)
trap 'rm -f "$S1_OUT" "$S2_OUT"' EXIT
fail=0
APP="SET LOCAL app.user_id = '$U'; SET ROLE tally_app;"

"${PSQL[@]}" >/dev/null <<SQL || { echo "SETUP FAIL: fixtures"; exit 2; }
INSERT INTO public.tenants (id, name, slug) VALUES ('$T', 'Race28', 'race28');
INSERT INTO public.users (id, tenant_id, display_name, email, role) VALUES ('$U', '$T', 'Op', 'op@race28.test', 'operator');
INSERT INTO public.rate_schedules (id, tenant_id, code) VALUES ('$S', '$T', 'RS-R28');
INSERT INTO public.rate_items (id, tenant_id, item_code) VALUES ('$A', '$T', 'A'), ('$B', '$T', 'B');
BEGIN;
$APP
INSERT INTO public.rate_item_dependencies (id, tenant_id, rate_schedule_id, dependent_rate_item_id, base_rate_item_id, effective_date)
VALUES ('$BA', '$T', '$S', '$B', '$A', '2026-01-01');
COMMIT;
SQL

# P1: session 1 starts first, inserts after session 2's retraction commits.
"${PSQL[@]}" >"$S1_OUT" 2>&1 <<SQL &
BEGIN ISOLATION LEVEL READ COMMITTED;
$APP
SELECT 'START ' || to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US');
DO \$w\$ BEGIN
  FOR i IN 1..200 LOOP   -- up to 10 s; under READ COMMITTED each query takes a fresh snapshot
    IF EXISTS (SELECT 1 FROM public.rate_item_dependencies WHERE id = '$BA' AND recorded_until IS NOT NULL) THEN
      RAISE NOTICE 'SAW_CLOSE'; RETURN;
    END IF;
    PERFORM pg_sleep(0.05);
  END LOOP;
  RAISE EXCEPTION 'NEVER_SAW_CLOSE';
END \$w\$;
INSERT INTO public.rate_item_dependencies (tenant_id, rate_schedule_id, dependent_rate_item_id, base_rate_item_id, effective_date)
VALUES ('$T', '$S', '$A', '$B', '2026-01-01');
COMMIT;
SQL
S1PID=$!
sleep 0.8
"${PSQL[@]}" >"$S2_OUT" 2>&1 <<SQL
BEGIN;
$APP
UPDATE public.rate_item_dependencies SET recorded_until = now(), closed_type = 'retracted', closed_reason = 'race 28: keyed in error' WHERE id = '$BA';
COMMIT;
SQL
S2ST=$?
wait $S1PID
OUT=$(cat "$S1_OUT")
START=$(echo "$OUT" | sed -n 's/^START //p')
CLOSED=$("${PSQL[@]}" -c "SELECT to_char(recorded_until AT TIME ZONE 'UTC', 'YYYY-MM-DD\"T\"HH24:MI:SS.US') FROM public.rate_item_dependencies WHERE id = '$BA'")
if [ "$S2ST" -ne 0 ]; then echo "FAIL P1: session 2's retraction failed: $(cat "$S2_OUT")"; fail=1
elif ! echo "$OUT" | grep -q "SAW_CLOSE"; then
  echo "FAIL P1: session 1 never saw the retraction committed before its insert: $OUT"; fail=1
elif [ -z "$START" ] || [ -z "$CLOSED" ] || [ ! "$START" \< "$CLOSED" ]; then
  echo "FAIL P1: session 1 did not start before the retraction (start '$START', closed '$CLOSED'); the leg ran in order"; fail=1
elif echo "$OUT" | grep -q "23514" && echo "$OUT" | grep -q "closes a cycle"; then
  echo "PASS P1 a transaction begun before a concurrent retraction cannot record the reverse link (start $START < close $CLOSED)"
else
  echo "FAIL P1: expected 23514 / 'closes a cycle', got: $OUT"; fail=1
fi

# P2: no instant at which both links were known.
N=$("${PSQL[@]}" -c "SELECT count(*) FROM generate_series(0, 40) g,
      LATERAL (SELECT array_agg(d.dependent_rate_item_id::text || '>' || d.base_rate_item_id::text) AS links
                 FROM public.rate_item_dependencies_as_of('$S', DATE '2026-06-01', TIMESTAMPTZ '$START+00' + g * interval '100 milliseconds') d) x
     WHERE x.links @> ARRAY['$A>$B', '$B>$A']")
if [ "$N" = "0" ]; then echo "PASS P2 none of 41 instants sampled from session 1's start holds both A on B and B on A"; else echo "FAIL P2: $N instants hold a cycle"; fail=1; fi

# P3: control, begun after the retraction: admitted.
OUT=$("${PSQL[@]}" 2>&1 <<SQL
BEGIN;
$APP
INSERT INTO public.rate_item_dependencies (tenant_id, rate_schedule_id, dependent_rate_item_id, base_rate_item_id, effective_date)
VALUES ('$T', '$S', '$A', '$B', '2026-01-01');
COMMIT;
SQL
)
if [ $? -eq 0 ]; then echo "PASS P3 begun after the retraction committed, A on B is recorded"; else echo "FAIL P3: $OUT"; fail=1; fi

exit $fail
