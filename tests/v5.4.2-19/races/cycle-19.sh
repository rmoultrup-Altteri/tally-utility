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
#   C5  REPEATABLE READ (r2, Codex B4): A supersedes an ALREADY-INACTIVE
#       method; B reactivates it, waits on A, then fails to serialise — the
#       supersession rewrites the predecessor even when nothing changes.
#   C6  READ COMMITTED: the same; B re-reads, sees the successor, is refused.
#   C7  both inactive predecessors stayed inactive.
#   C8  (r4, Codex B1) A cites a pending payment in a refund and holds; B
#       moves that payment to another customer, waits on A's key lock, then
#       is refused (foreign_key_violation): a citation and a move serialise.
#   C9  the reverse: A moves a pending payment and holds; B cites it for the
#       old customer, waits on A, then is refused (foreign_key_violation).
# Every leg checks that session B ITSELF was SEEN BLOCKED BY SESSION A
# (pg_blocking_pids of B's backend contains A's, polled while A holds), so a
# leg cannot pass by running sequentially. Setup failures exit 2.
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
PM2=00000000-0000-4000-8000-0000000019ea
PM3=00000000-0000-4000-8000-0000000019eb
C2=00000000-0000-4000-8000-0000000019ec
PAY=00000000-0000-4000-8000-0000000019ed
PAY2=00000000-0000-4000-8000-0000000019ee
A_OUT=$(mktemp); B_OUT=$(mktemp)
trap 'rm -f "$A_OUT" "$B_OUT"' EXIT
fail=0

"${PSQL[@]}" >/dev/null <<SQL || { echo "SETUP FAIL: fixtures"; exit 2; }
INSERT INTO public.tenants (id, name, slug) VALUES ('$T', 'Race19', 'race19');
INSERT INTO public.users (id, tenant_id, display_name, email, role) VALUES ('$U', '$T', 'Op', 'op@race19.test', 'operator');
INSERT INTO public.customers (id, tenant_id, customer_number, customer_type) VALUES ('$C', '$T', 'R19-C1', 'residential');
INSERT INTO public.customers (id, tenant_id, customer_number, customer_type) VALUES ('$C2', '$T', 'R19-C2', 'residential');
INSERT INTO public.payments (id, tenant_id, payment_number, customer_id, payment_date, amount, payment_method, status)
VALUES ('$PAY', '$T', 'R19-PAY', '$C', DATE '2026-02-01', 20, 'check', 'pending'),
       ('$PAY2', '$T', 'R19-PAY2', '$C', DATE '2026-02-01', 20, 'check', 'pending');
INSERT INTO public.rate_schedules (id, tenant_id, code) VALUES ('$S', '$T', 'RS-R19');
INSERT INTO public.rate_items (id, tenant_id, item_code) VALUES ('$I1', '$T', 'X1'), ('$I2', '$T', 'Y1'), ('$I3', '$T', 'X2'), ('$I4', '$T', 'Y2');
INSERT INTO public.payment_methods (id, tenant_id, customer_id, provider, provider_token, method_type, last_four)
VALUES ('$PM', '$T', '$C', 'paymentus', 'race19-tok', 'ach', '1111');
INSERT INTO public.payment_methods (id, tenant_id, customer_id, provider, provider_token, method_type, last_four, is_active, is_default)
VALUES ('$PM2', '$T', '$C', 'paymentus', 'race19-tok2', 'ach', '3333', false, false),
       ('$PM3', '$T', '$C', 'paymentus', 'race19-tok3', 'ach', '4444', false, false);
SQL

waiting() {  # 1 once B's backend is seen blocked by A's; polled while A holds
local n i
for i in 1 2 3 4 5 6 7 8 9 10; do
  n=$(docker exec -i tally-pg psql -U tally -d "$DB" -At -c "SELECT count(*) FROM pg_stat_activity b JOIN pg_stat_activity a ON a.datname = b.datname AND a.application_name = 'race19_a' WHERE b.datname = current_database() AND b.application_name = 'race19_b' AND a.pid = ANY (pg_blocking_pids(b.pid))" 2>/dev/null)
  if [[ "$n" =~ ^[0-9]+$ ]] && [ "$n" -ge 1 ]; then echo 1; return; fi
  sleep 0.15
done
echo 0
}
APP="SET LOCAL app.user_id = '$U'; SET ROLE tally_app;"

two() {  # $1 A's statement, $2 B's isolation level, $3 B's statement
"${PSQL[@]}" >"$A_OUT" 2>&1 <<SQL &
SET application_name = 'race19_a';
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

succ_of() { echo "INSERT INTO public.payment_methods (tenant_id, customer_id, provider, provider_token, method_type, last_four, supersedes_payment_method_id, supersede_reason) VALUES ('$T', '$C', 'paymentus', '$2', 'ach', '5555', '$1', 'customer_update');"; }
react() { echo "UPDATE public.payment_methods SET is_active = true WHERE id = '$1';"; }
two "$(succ_of "$PM2" race19-c5)" "REPEATABLE READ" "$(react "$PM2")"
check "C5 REPEATABLE READ: reactivating an inactive method being superseded waits, then fails to serialise" "40001" "could not serialize"
two "$(succ_of "$PM3" race19-c6)" "READ COMMITTED" "$(react "$PM3")"
check "C6 READ COMMITTED: reactivating an inactive method being superseded waits, then is refused" "23514" "was superseded"
N=$("${PSQL[@]}" -c "SELECT count(*) FROM public.payment_methods WHERE id IN ('$PM2', '$PM3') AND NOT is_active AND NOT is_default")
if [ "$N" = "2" ]; then echo "PASS C7: both superseded methods stayed inactive"; else echo "FAIL C7: $N of 2 superseded methods inactive"; fail=1; fi

refund="INSERT INTO public.payments (tenant_id, payment_number, customer_id, payment_date, amount, payment_method, effective_date, effective_date_method, refunds_payment_id) VALUES ('$T', 'R19-REF', '$C', DATE '2026-02-02', -5, 'refund', DATE '2026-02-02', 'other', '$PAY');"
two "$refund" "READ COMMITTED" "UPDATE public.payments SET customer_id = '$C2' WHERE id = '$PAY';"
check "C8 a payment moved to another customer while a refund cites it: the move waits, then is refused" "23503" "payments_refunds_payment_id_fkey"
refund2="INSERT INTO public.payments (tenant_id, payment_number, customer_id, payment_date, amount, payment_method, effective_date, effective_date_method, refunds_payment_id) VALUES ('$T', 'R19-REF2', '$C', DATE '2026-02-02', -5, 'refund', DATE '2026-02-02', 'other', '$PAY2');"
two "UPDATE public.payments SET customer_id = '$C2' WHERE id = '$PAY2';" "READ COMMITTED" "$refund2"
check "C9 a refund citing a payment being moved: the citation waits, then is refused" "23503" "payments_refunds_payment_id_fkey"

N=$("${PSQL[@]}" -c "SELECT count(*) FROM public.rate_item_dependencies WHERE rate_schedule_id = '$S'")
if [ "$N" = "2" ]; then echo "PASS C4: exactly one half of each cycle was stored"; else echo "FAIL C4: $N dependencies stored, expected 2"; fail=1; fi

exit $fail
