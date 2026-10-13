#!/usr/bin/env bash
# v5.4.2-19: the rider-dependency cycle check reads the schedule's other
# dependencies, so two halves of a cycle written at once race it. Both
# writers bump the schedule's header row (a row-version mutex), so:
#   C1  READ COMMITTED: A writes X on Y and holds; B's Y on X waits on the
#       header, then sees A's row and is refused (check_violation, a cycle).
#   C2  REPEATABLE READ: the same, B is refused with serialization_failure
#       (its snapshot predates A's row; the header write detects it).
#   C3  two successors of one payment method at once: the second waits on
#       the predecessor's lock, then is refused (unique_violation).
# Every leg checks that session B ITSELF was SEEN WAITING (pg_stat_activity,
# by application_name, wait_event_type Lock) before A committed, so a leg
# cannot pass by running sequentially. Setup failures exit 2.
# Runs against a THROWAWAY clone (it commits rows).
#   usage: cycle-19.sh <db>      (default: r19)
set -uo pipefail
DB="${1:-r19}"
PSQL=(docker exec -i tally-pg psql -U tally -d "$DB" -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -q -At)

T=00000000-0000-4000-8000-0000000019e1
U=00000000-0000-4000-8000-0000000019e2
C=00000000-0000-4000-8000-0000000019e3
S=00000000-0000-4000-8000-0000000019e4
I1=00000000-0000-4000-8000-0000000019e5
I2=00000000-0000-4000-8000-0000000019e6
I3=00000000-0000-4000-8000-0000000019e7
I4=00000000-0000-4000-8000-0000000019e8
PM=00000000-0000-4000-8000-0000000019e9
A_OUT=$(mktemp); B_OUT=$(mktemp)
trap 'rm -f "$A_OUT" "$B_OUT"' EXIT
fail=0

"${PSQL[@]}" >/dev/null <<SQL || { echo "SETUP FAIL: fixtures"; exit 2; }
INSERT INTO public.tenants (id, name, slug) VALUES ('$T', 'Race19', 'race19');
INSERT INTO public.users (id, tenant_id, display_name, email, role) VALUES ('$U', '$T', 'Op', 'op@race19.test', 'operator');
INSERT INTO public.customers (id, tenant_id, customer_number, customer_type) VALUES ('$C', '$T', 'R19-C1', 'residential');
INSERT INTO public.rate_schedules (id, tenant_id, code) VALUES ('$S', '$T', 'RS-R19');
INSERT INTO public.rate_items (id, tenant_id, item_code) VALUES ('$I1', '$T', 'X1'), ('$I2', '$T', 'Y1'), ('$I3', '$T', 'X2'), ('$I4', '$T', 'Y2');
INSERT INTO public.payment_methods (id, tenant_id, customer_id, provider, provider_token, method_type, last_four)
VALUES ('$PM', '$T', '$C', 'paymentus', 'race19-tok', 'ach', '1111');
SQL

waiting() {
docker exec -i tally-pg psql -U tally -d "$DB" -At -c "SELECT count(*) FROM pg_stat_activity WHERE datname = current_database() AND application_name = 'race19_b' AND wait_event_type = 'Lock'"
}
APP="SET LOCAL app.user_id = '$U'; SET ROLE tally_app;"

two() {  # $1 A's statement, $2 B's isolation level, $3 B's statement
"${PSQL[@]}" >"$A_OUT" 2>&1 <<SQL &
BEGIN;
$APP
$1
SELECT pg_sleep(3);
COMMIT;
SQL
APID=$!
sleep 1
"${PSQL[@]}" >"$B_OUT" 2>&1 <<SQL &
SET application_name = 'race19_b';
BEGIN ISOLATION LEVEL $2;
$APP
$3
COMMIT;
SQL
sleep 1
WAITED=$(waiting)
wait $APID; AST=$?
wait
OUT=$(cat "$B_OUT")
}

check() {  # $1 label, $2 expected SQLSTATE, $3 expected message fragment
if [ "${AST:-0}" -ne 0 ]; then echo "FAIL $1: session A itself failed: $(cat "$A_OUT")"; fail=1; return; fi
if [ "${WAITED:-0}" -lt 1 ]; then echo "FAIL $1: session B was never seen waiting on a lock"; fail=1; return; fi
if echo "$OUT" | grep -q "$2" && echo "$OUT" | grep -q "$3"; then
  echo "PASS $1"
else
  echo "FAIL $1: expected $2 / '$3', got: $OUT"; fail=1
fi
}

dep() { echo "INSERT INTO public.rate_item_dependencies (tenant_id, rate_schedule_id, dependent_rate_item_id, base_rate_item_id) VALUES ('$T', '$S', '$1', '$2');"; }

two "$(dep "$I1" "$I2")" "READ COMMITTED" "$(dep "$I2" "$I1")"
check "C1 READ COMMITTED: the second half of a cycle waits, then is refused" "23514" "closes a cycle"

two "$(dep "$I3" "$I4")" "REPEATABLE READ" "$(dep "$I4" "$I3")"
check "C2 REPEATABLE READ: the second half of a cycle waits, then fails to serialise" "40001" "could not serialize"

succ() { echo "INSERT INTO public.payment_methods (tenant_id, customer_id, provider, provider_token, method_type, last_four, supersedes_payment_method_id, supersede_reason) VALUES ('$T', '$C', 'paymentus', '$1', 'ach', '2222', '$PM', 'customer_update');"; }
two "$(succ race19-a)" "READ COMMITTED" "$(succ race19-b)"
check "C3 two successors of one payment method at once: the second waits, then is refused" "23505" "payment_methods_supersedes_once_key"

N=$("${PSQL[@]}" -c "SELECT count(*) FROM public.rate_item_dependencies WHERE rate_schedule_id = '$S'")
if [ "$N" = "2" ]; then echo "PASS C4: exactly one half of each cycle was stored"; else echo "FAIL C4: $N dependencies stored, expected 2"; fail=1; fi

exit $fail
