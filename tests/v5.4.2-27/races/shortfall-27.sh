#!/usr/bin/env bash
# v5.4.2-27: what one transaction cannot show — two writers on one shortfall,
# a shortfall application against a draw or a bounce of its source, Ryan's
# call against a repayment in flight, the recorded order, the READ COMMITTED
# pin. Each bounced payment X pays 50, is refunded 30 and bounces: 30 short.
#   SR1  A repays 20 of X1's 30 from credit G1 and holds; B repays 20 more
#        from G2: waits on X1's lock, then is refused (X1 would hold money).
#   SR2  A refunds G3's 20 and holds; B applies G3's 20 to X2's shortfall:
#        waits on G3's lock, then is refused (G3's cap).
#   SR2b A applies G4's 20 to X3's shortfall and holds; B refunds G4's 20:
#        waits, then is refused (the cap: its money paid the debt).
#   SR3  A applies payment Q1's 20 to X4's shortfall and holds; B writes the
#        nsf row returning Q1: waits on Q1's lock, then is refused (R15).
#   SR4  Ryan's call (2026-11-05): A repays X5's shortfall from G5 and holds;
#        B moves X5's returned refund to nsf: waits on X5's lock, then is
#        refused (X5 would hold the repayment).
#   SR5  A's transaction begins; B repays 10 of X6's shortfall from G6 and
#        commits; A repays 10 from G7: refused for retry (40001: recorded
#        before a repayment already counted); the retry is admitted.
#   SR6  A's transaction begins; B bounces X7 and commits; A repays X7's
#        shortfall: refused for retry (40001: recorded before the bounce);
#        the retry is admitted.
#   SR7  A shortfall application under REPEATABLE READ is refused (25000).
#   SR8  X8 pays 100, held whole as credit K8, which refunds 60; X8 bounces
#        (60 short, on K8). A's transaction begins; B records K8's refund
#        check coming back (K8 has its 60 again) and commits; A repays X8:
#        refused for retry (40001: recorded before a draw that has left
#        K8); the retry is refused (X8 now owes nothing).
#   SR9  (r2, Opus S3, Fable S2) X9 pays 100, held whole as credit K9, which
#        refunds 60; X9 bounces (60 short, on K9). A repays 10 of X9's
#        shortfall and holds; B moves K9's returned refund to nsf: waits on
#        X9's lock, then is refused (the family would hold the 10).
# r2 (Codex S2): every session runs under a statement timeout, every
# handshake has a deadline, B's exit is checked before A is waited for, and
# A is ended and reaped when anything fails.
# Every two() leg checks that session B was SEEN BLOCKED BY SESSION A.
# Setup failures exit 2. Runs against a THROWAWAY clone (it commits rows).
#   usage: shortfall-27.sh <db>      (default: r27)
set -uo pipefail
DB="${1:-r27}"
PSQL=(docker exec -i -e PGOPTIONS=-c\ statement_timeout=30s tally-pg psql -U tally -d "$DB" -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -q -At)
P=00000000-0000-4000-8000-0000000028
T=${P}f0; OP=${P}f1; C=${P}f2
A_OUT=$(mktemp); B_OUT=$(mktemp)
trap 'rm -f "$A_OUT" "$B_OUT"' EXIT
fail=0

# short(): payment X ($1, number $2) pays 50 on 03-10, is refunded 30 (refund
# $3, posted by entry $4) on 03-11; X's posting entry $5; then bounces (row
# $6) on 03-12 unless $7 = keep.
short() {
cat <<SQL
INSERT INTO public.payments (id, tenant_id, payment_number, customer_id, payment_date, amount, payment_method) VALUES ('$1', '$T', '$2', '$C', DATE '2026-03-10', 50, 'check');
INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reference_type, reference_id) VALUES ('$5', '$T', '$C', DATE '2026-03-10', 'payment', 'posted', -50, 'payment', '$1');
UPDATE public.payments SET status = 'posted', status_cause_id = '$5', effective_date = payment_date, effective_date_method = 'other' WHERE id = '$1';
INSERT INTO public.payments (id, tenant_id, payment_number, customer_id, payment_date, amount, payment_method, refunds_payment_id) VALUES ('$3', '$T', '$2R', '$C', DATE '2026-03-11', -30, 'refund', '$1');
INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reference_type, reference_id) VALUES ('$4', '$T', '$C', DATE '2026-03-11', 'refund', 'refund out', 30, 'payment', '$3');
UPDATE public.payments SET status = 'posted', status_cause_id = '$4', effective_date = payment_date, effective_date_method = 'other' WHERE id = '$3';
$( [ "${7:-}" = keep ] || bounce "$1" "$5" "$6" )
SQL
}
bounce() {  # $1 payment, $2 its posting entry, $3 the nsf row
cat <<SQL
INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reference_type, reference_id, reverses_ledger_entry_id) VALUES ('$3', '$T', '$C', DATE '2026-03-12', 'nsf', 'returned', 50, 'payment', '$1', '$2');
UPDATE public.payments SET status = 'nsf', nsf_date = DATE '2026-03-12', status_cause_id = '$3' WHERE id = '$1';
SQL
}
credit() {  # $1 credit, $2 its credit_issued entry, $3 amount
cat <<SQL
INSERT INTO public.customer_credits (id, tenant_id, customer_id, origin_type, original_amount, issued_date) VALUES ('$1', '$T', '$C', 'goodwill', $3, DATE '2026-03-02');
INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reference_type, reference_id) VALUES ('$2', '$T', '$C', DATE '2026-03-02', 'credit_issued', 'goodwill', -$3, 'customer_credit', '$1');
SQL
}
sa() {  # $1 target, $2 payment source or NULL, $3 credit source or NULL, $4 amount
echo "INSERT INTO public.shortfall_applications (tenant_id, customer_id, target_payment_id, payment_id, customer_credit_id, amount, applied_on, basis) VALUES ('$T', '$C', '$1', $2, $3, $4, DATE '2026-03-13', 'customer_pot');"
}
crefund() {  # $1 credit, $2 amount
echo "INSERT INTO public.payments (tenant_id, payment_number, customer_id, payment_date, amount, payment_method, refunds_customer_credit_id) VALUES ('$T', 'SR-' || left(gen_random_uuid()::text, 8), '$C', DATE '2026-03-13', -$2, 'refund', '$1');"
}

"${PSQL[@]}" >/tmp/r27setup.out 2>&1 <<SQL || { echo "SETUP FAIL: fixtures"; cat /tmp/r27setup.out; exit 2; }
BEGIN;
INSERT INTO public.tenants (id, name, slug) VALUES ('$T', 'Race27', 'race27');
INSERT INTO public.users (id, tenant_id, display_name, email, role) VALUES ('$OP', '$T', 'Op', 'op@race27.test', 'operator');
INSERT INTO public.customers (id, tenant_id, customer_number, customer_type) VALUES ('$C', '$T', 'R27-C', 'residential');
SET LOCAL app.user_id = '$OP'; SET ROLE tally_app;
$(short ${P}01 R27-X1 ${P}21 ${P}41 ${P}61 ${P}81)
$(short ${P}02 R27-X2 ${P}22 ${P}42 ${P}62 ${P}82)
$(short ${P}03 R27-X3 ${P}23 ${P}43 ${P}63 ${P}83)
$(short ${P}04 R27-X4 ${P}24 ${P}44 ${P}64 ${P}84)
$(short ${P}05 R27-X5 ${P}25 ${P}45 ${P}65 ${P}85)
$(short ${P}06 R27-X6 ${P}26 ${P}46 ${P}66 ${P}86)
$(short ${P}07 R27-X7 ${P}27 ${P}47 ${P}67 ${P}87 keep)
$(credit ${P}a1 ${P}b1 20)
$(credit ${P}a2 ${P}b2 20)
$(credit ${P}a3 ${P}b3 20)
$(credit ${P}a4 ${P}b4 20)
$(credit ${P}a5 ${P}b5 20)
$(credit ${P}a6 ${P}b6 10)
$(credit ${P}a7 ${P}b7 10)
$(credit ${P}a8 ${P}b8 10)
$(credit ${P}a9 ${P}b9 10)
INSERT INTO public.payments (id, tenant_id, payment_number, customer_id, payment_date, amount, payment_method) VALUES ('${P}11', '$T', 'R27-Q1', '$C', DATE '2026-03-10', 40, 'check');
INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reference_type, reference_id) VALUES ('${P}12', '$T', '$C', DATE '2026-03-10', 'payment', 'posted', -40, 'payment', '${P}11');
UPDATE public.payments SET status = 'posted', status_cause_id = '${P}12', effective_date = payment_date, effective_date_method = 'other' WHERE id = '${P}11';
INSERT INTO public.payments (id, tenant_id, payment_number, customer_id, payment_date, amount, payment_method) VALUES ('${P}08', '$T', 'R27-X8', '$C', DATE '2026-03-10', 100, 'check');
INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reference_type, reference_id) VALUES ('${P}68', '$T', '$C', DATE '2026-03-10', 'payment', 'posted', -100, 'payment', '${P}08');
UPDATE public.payments SET status = 'posted', status_cause_id = '${P}68', effective_date = payment_date, effective_date_method = 'other' WHERE id = '${P}08';
INSERT INTO public.customer_credit_approvals (id, tenant_id, customer_id, payment_id, amount, approved_by) VALUES ('${P}d8', '$T', '$C', '${P}08', 100, '$OP');
INSERT INTO public.customer_credits (id, tenant_id, customer_id, origin_type, original_amount, issued_date, source_payment_id, approval_id) VALUES ('${P}e8', '$T', '$C', 'overpayment', 100, DATE '2026-03-11', '${P}08', '${P}d8');
INSERT INTO public.payments (id, tenant_id, payment_number, customer_id, payment_date, amount, payment_method, refunds_customer_credit_id) VALUES ('${P}28', '$T', 'R27-X8R', '$C', DATE '2026-03-11', -60, 'refund', '${P}e8');
INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reference_type, reference_id) VALUES ('${P}48', '$T', '$C', DATE '2026-03-11', 'refund', 'refund out', 60, 'payment', '${P}28');
UPDATE public.payments SET status = 'posted', status_cause_id = '${P}48', effective_date = payment_date, effective_date_method = 'other' WHERE id = '${P}28';
INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reference_type, reference_id, reverses_ledger_entry_id) VALUES ('${P}88', '$T', '$C', DATE '2026-03-12', 'nsf', 'returned', 100, 'payment', '${P}08', '${P}68');
UPDATE public.payments SET status = 'nsf', nsf_date = DATE '2026-03-12', status_cause_id = '${P}88' WHERE id = '${P}08';
$(credit ${P}aa ${P}ba 10)
INSERT INTO public.payments (id, tenant_id, payment_number, customer_id, payment_date, amount, payment_method) VALUES ('${P}09', '$T', 'R27-X9', '$C', DATE '2026-03-10', 100, 'check');
INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reference_type, reference_id) VALUES ('${P}69', '$T', '$C', DATE '2026-03-10', 'payment', 'posted', -100, 'payment', '${P}09');
UPDATE public.payments SET status = 'posted', status_cause_id = '${P}69', effective_date = payment_date, effective_date_method = 'other' WHERE id = '${P}09';
INSERT INTO public.customer_credit_approvals (id, tenant_id, customer_id, payment_id, amount, approved_by) VALUES ('${P}d9', '$T', '$C', '${P}09', 100, '$OP');
INSERT INTO public.customer_credits (id, tenant_id, customer_id, origin_type, original_amount, issued_date, source_payment_id, approval_id) VALUES ('${P}e9', '$T', '$C', 'overpayment', 100, DATE '2026-03-11', '${P}09', '${P}d9');
INSERT INTO public.payments (id, tenant_id, payment_number, customer_id, payment_date, amount, payment_method, refunds_customer_credit_id) VALUES ('${P}29', '$T', 'R27-X9R', '$C', DATE '2026-03-11', -60, 'refund', '${P}e9');
INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reference_type, reference_id) VALUES ('${P}49', '$T', '$C', DATE '2026-03-11', 'refund', 'refund out', 60, 'payment', '${P}29');
UPDATE public.payments SET status = 'posted', status_cause_id = '${P}49', effective_date = payment_date, effective_date_method = 'other' WHERE id = '${P}29';
INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reference_type, reference_id, reverses_ledger_entry_id) VALUES ('${P}89', '$T', '$C', DATE '2026-03-12', 'nsf', 'returned', 100, 'payment', '${P}09', '${P}69');
UPDATE public.payments SET status = 'nsf', nsf_date = DATE '2026-03-12', status_cause_id = '${P}89' WHERE id = '${P}09';
$(credit ${P}ab ${P}bb 10)
INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reverses_ledger_entry_id) VALUES ('${P}c9', '$T', '$C', DATE '2026-03-14', 'nsf', 'refund check returned', -60, '${P}49');
-- X5's refund check comes back (its row, recorded ahead; the move is the race).
INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reverses_ledger_entry_id) VALUES ('${P}c5', '$T', '$C', DATE '2026-03-14', 'nsf', 'refund check returned', -30, '${P}45');
COMMIT;
SQL

waiting() {
local n i
for i in 1 2 3 4 5 6 7 8 9 10; do
  n=$(docker exec -i tally-pg psql -U tally -d "$DB" -At -c "SELECT count(*) FROM pg_stat_activity b JOIN pg_stat_activity a ON a.datname = b.datname AND a.application_name = 'race27_a' WHERE b.datname = current_database() AND b.application_name = 'race27_b' AND a.pid = ANY (pg_blocking_pids(b.pid))" 2>/dev/null)
  if [[ "$n" =~ ^[0-9]+$ ]] && [ "$n" -ge 1 ]; then echo 1; return; fi
  sleep 0.15
done
echo 0
}
AS_OP="SET LOCAL app.user_id = '$OP'; SET ROLE tally_app;"
two() {  # $1 A's statement, $2 B's statement
"${PSQL[@]}" >"$A_OUT" 2>&1 <<SQL &
SET application_name = 'race27_a';
BEGIN;
$AS_OP
$1
SELECT pg_sleep(3);
COMMIT;
SQL
APID=$!
sleep 1
"${PSQL[@]}" >"$B_OUT" 2>&1 <<SQL &
SET application_name = 'race27_b';
BEGIN;
$AS_OP
$2
COMMIT;
SQL
BPID=$!
sleep 1
WAITED=$(waiting)
wait $BPID; BST=$?
wait $APID; AST=$?
OUT=$(cat "$B_OUT")
}
verdict() {  # $1 label, $2 want B to fail (1) or pass (0), $3 expected fragment when it fails
if [ "${AST:-0}" -ne 0 ]; then echo "FAIL $1: session A itself failed: $(cat "$A_OUT")"; fail=1; return; fi
if [ "${WAITED:-0}" -lt 1 ]; then echo "FAIL $1: session B was never seen waiting on a lock"; fail=1; return; fi
if [ "$2" = 1 ]; then
  if [ "$BST" -ne 0 ] && echo "$OUT" | grep -q "$3"; then echo "PASS $1"; else echo "FAIL $1: expected B refused with '$3', got ($BST): $OUT"; fail=1; fi
else
  if [ "$BST" -eq 0 ]; then echo "PASS $1"; else echo "FAIL $1: expected B to pass, got: $OUT"; fail=1; fi
fi
}
expect() {  # $1 label, $2 actual, $3 expected
if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: got [$2], expected [$3]"; fail=1; fi
}
begun() {  # $1 tag, $2 A's statement (after its transaction began), $3 B's statements
"${PSQL[@]}" >"$A_OUT" 2>&1 <<SQL &
SET application_name = 'race27_a_begun$1';
BEGIN;
$AS_OP
SELECT now();
DO \$\$ DECLARE v_until timestamptz := clock_timestamp() + interval '20 seconds'; BEGIN
  LOOP
    PERFORM pg_stat_clear_snapshot();
    EXIT WHEN EXISTS (SELECT 1 FROM pg_stat_activity WHERE application_name = 'race27_b_done$1');
    IF clock_timestamp() > v_until THEN RAISE EXCEPTION 'race27 handshake: B never reported done within 20s'; END IF;
    PERFORM pg_sleep(0.1);
  END LOOP;
END \$\$;
$2
COMMIT;
SQL
APID=$!
local seen=0
for _ in $(seq 1 100); do
  [ "$(docker exec -i tally-pg psql -U tally -d "$DB" -At -c "SELECT count(*) FROM pg_stat_activity WHERE application_name = 'race27_a_begun$1'")" = "1" ] && { seen=1; break; }; sleep 0.1
done
if [ "$seen" -ne 1 ]; then reap "$1"; AST=99; echo "session A never began" >"$A_OUT"; return; fi
# B stays marked done until A has finished (or 20s), so A cannot miss it.
"${PSQL[@]}" >"$B_OUT" 2>&1 <<SQL
BEGIN;
$AS_OP
$3
COMMIT;
SET application_name = 'race27_b_done$1';
DO \$\$ DECLARE v_until timestamptz := clock_timestamp() + interval '20 seconds'; BEGIN
  LOOP
    PERFORM pg_stat_clear_snapshot();
    EXIT WHEN NOT EXISTS (SELECT 1 FROM pg_stat_activity WHERE application_name = 'race27_a_begun$1') OR clock_timestamp() > v_until;
    PERFORM pg_sleep(0.1);
  END LOOP;
END \$\$;
SQL
BST=$?
if [ "$BST" -ne 0 ]; then reap "$1"; AST=98; echo "session B failed: $(cat "$B_OUT")" >>"$A_OUT"; return; fi
wait $APID; AST=$?
}
reap() {  # end session A of begun() $1 and reap its client
docker exec -i tally-pg psql -U tally -d "$DB" -Atq -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE application_name = 'race27_a_begun$1'" >/dev/null 2>&1
wait $APID 2>/dev/null
}
retry() {  # $1 label, $2 statement
OUT=$("${PSQL[@]}" 2>&1 <<SQL
BEGIN;
$AS_OP
$2
COMMIT;
SQL
)
if [ $? -eq 0 ]; then echo "PASS $1"; else echo "FAIL $1: $OUT"; fail=1; fi
}
pos() {  # $1 payment: remaining/repaid
"${PSQL[@]}" -c "SELECT remaining || '/' || repaid FROM public.payment_position_as_of('$1', DATE '2026-12-31', clock_timestamp())"
}

# SR1
two "$(sa ${P}01 NULL "'${P}a1'" 20)" "$(sa ${P}01 NULL "'${P}a2'" 20)"
verdict "SR1 two credits repay one 30 shortfall at once: the second waits on the payment, then is refused (it would hold money)" 1 "a payment that has ended holds no money"
expect "SR1b X1 reads 10 short, 20 repaid" "$(pos ${P}01)" "-10.00/20.00"

# SR2, SR2b
two "$(crefund ${P}a3 20)" "$(sa ${P}02 NULL "'${P}a3'" 20)"
verdict "SR2 a credit refunded in full while it is applied to a shortfall: the application waits on the credit, then is refused (its cap)" 1 "R-06 cap"
two "$(sa ${P}03 NULL "'${P}a4'" 20)" "$(crefund ${P}a4 20)"
verdict "SR2b and the other way round: the refund waits, then is refused (its money paid the debt)" 1 "R-06 cap"

# SR3
two "$(sa ${P}04 "'${P}11'" NULL 20)" \
    "INSERT INTO public.account_ledger (tenant_id, customer_id, transaction_date, transaction_type, description, amount, reference_type, reference_id, reverses_ledger_entry_id) VALUES ('$T', '$C', DATE '2026-03-14', 'nsf', 'Q1 returned', 40, 'payment', '${P}11', '${P}12');"
verdict "SR3 a payment applied to a shortfall while it bounces: the nsf row waits on the payment, then is refused (R15)" 1 "applied to a bounced payment's shortfall"

# SR4 (Ryan, 2026-11-05, option 1)
two "$(sa ${P}05 NULL "'${P}a5'" 20)" \
    "UPDATE public.payments SET status = 'nsf', nsf_date = DATE '2026-03-14', status_cause_id = '${P}c5' WHERE id = '${P}25';"
verdict "SR4 a refund's return recorded while its shortfall is being repaid: the move waits on the payment, then is refused (undo first)" 1 "undo the shortfall application first"

# SR5
begun 5 "$(sa ${P}06 NULL "'${P}a7'" 10)" "$(sa ${P}06 NULL "'${P}a6'" 10)"
if [ "$AST" -ne 0 ] && grep -q "40001" "$A_OUT" && grep -q "a repayment of its shortfall" "$A_OUT"; then echo "PASS SR5 a repayment begun before another repayment of the same payment committed is refused for retry"
else echo "FAIL SR5: A ($AST): $(cat "$A_OUT") / B: $(cat "$B_OUT")"; fail=1; fi
retry "SR5a the retry is admitted" "$(sa ${P}06 NULL "'${P}a7'" 10)"
expect "SR5b X6 reads 10 short, 20 repaid" "$(pos ${P}06)" "-10.00/20.00"

# SR6
begun 6 "$(sa ${P}07 NULL "'${P}a8'" 10)" "$(bounce ${P}07 ${P}67 ${P}87)"
if [ "$AST" -ne 0 ] && grep -q "40001" "$A_OUT" && grep -q "before payment R27-X7 moved to nsf" "$A_OUT"; then echo "PASS SR6 a repayment begun before its payment bounced is refused for retry"
else echo "FAIL SR6: A ($AST): $(cat "$A_OUT") / B: $(cat "$B_OUT")"; fail=1; fi
retry "SR6a the retry is admitted" "$(sa ${P}07 NULL "'${P}a8'" 10)"

# SR7
OUT=$("${PSQL[@]}" 2>&1 <<SQL
BEGIN ISOLATION LEVEL REPEATABLE READ;
$AS_OP
$(sa ${P}07 NULL "'${P}a9'" 10)
COMMIT;
SQL
)
if echo "$OUT" | grep -q "25000" && echo "$OUT" | grep -q "is written at READ COMMITTED"; then echo "PASS SR7 a shortfall application under REPEATABLE READ is refused (25000)"; else echo "FAIL SR7: $OUT"; fail=1; fi

# SR8
begun 8 "$(sa ${P}08 NULL "'${P}aa'" 10)" \
  "INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reverses_ledger_entry_id) VALUES ('${P}c8', '$T', '$C', DATE '2026-03-14', 'nsf', 'refund check returned', -60, '${P}48');
UPDATE public.payments SET status = 'nsf', nsf_date = DATE '2026-03-14', status_cause_id = '${P}c8' WHERE id = '${P}28';"
if [ "$AST" -ne 0 ] && grep -q "40001" "$A_OUT" && grep -q "a repayment of its payment's shortfall" "$A_OUT"; then echo "PASS SR8 a repayment begun before a refund of the payment's credit came back is refused for retry"
else echo "FAIL SR8: A ($AST): $(cat "$A_OUT") / B: $(cat "$B_OUT")"; fail=1; fi
OUT=$("${PSQL[@]}" 2>&1 <<SQL
BEGIN;
$AS_OP
$(sa ${P}08 NULL "'${P}aa'" 10)
COMMIT;
SQL
)
if [ $? -ne 0 ] && echo "$OUT" | grep -q "a payment that has ended holds no money"; then echo "PASS SR8a the retry is refused: X8 owes nothing now"; else echo "FAIL SR8a: $OUT"; fail=1; fi

# SR9 (r2)
two "$(sa ${P}09 NULL "'${P}ab'" 10)" \
    "UPDATE public.payments SET status = 'nsf', nsf_date = DATE '2026-03-14', status_cause_id = '${P}c9' WHERE id = '${P}29';"
verdict "SR9 a family credit's returned refund recorded while the family's shortfall is being repaid: the move waits on the payment, then is refused (undo first)" 1 "undo the shortfall application first"
expect "SR9b X9 reads 0 of its own (the deficit is on K9), 10 repaid; K9's refund still posted" "$(pos ${P}09)/$("${PSQL[@]}" -c "SELECT status FROM public.payments WHERE id = '${P}29'")" "0.00/10.00/posted"

exit $fail
