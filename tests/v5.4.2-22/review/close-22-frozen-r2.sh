#!/usr/bin/env bash
# v5.4.2-22: what one transaction cannot show — two sessions, committed
# transactions, isolation levels, recorded time.
#   CR1  A posts into January and holds; B closes January: waits on A (the
#        head), then closes, and the snapshot counts A's row (P3).
#   CR2  A closes February and holds; B posts into February: waits on A,
#        then is refused (P2).
#   CR3  B, at REPEATABLE READ, reads before A closes March; A commits; B
#        then posts into March: a serialisation failure, not a silent post.
#   CR4  The close, a period insert and a recovery refuse REPEATABLE READ.
#   CR5  A recovers 30 of a 50 write-off and holds; B recovers 30 more:
#        waits on A, then is refused by the cap (W3).
#   CR6  Two inserts of the same next period: the second waits, then is
#        refused (no gaps).
#   CR7  Reproducible: after later postings and a backdated change of the
#        bucket setting, January's snapshot lines equal the aging (with the
#        snapshot's stored edges) and ledger sums at its recorded instant.
#   CR8  GL mapping in recorded time: a close recorded later does not end
#        the row for a lookup at an earlier instant (G1).
#   CR9  A closes April and holds; B inserts a GL mapping in force in April:
#        waits on A, then is refused (G4).
#   CR10 The latest period, once closed, is not withdrawn.
# Every race leg checks that session B ITSELF was SEEN BLOCKED BY SESSION A
# (pg_blocking_pids, polled while A holds). Setup failures exit 2.
# Runs against a THROWAWAY clone (it commits rows).
set -uo pipefail
DB="${1:-r22}"
PSQL=(docker exec -i tally-pg psql -U tally -d "$DB" -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -q -At)

T=00000000-0000-4000-8000-0000000022f0
OP=00000000-0000-4000-8000-0000000022f2
SUP=00000000-0000-4000-8000-0000000022f3
C=00000000-0000-4000-8000-0000000022f4
JAN=00000000-0000-4000-8000-0000000022f5
FEB=00000000-0000-4000-8000-0000000022f6
MAR=00000000-0000-4000-8000-0000000022f7
WO=00000000-0000-4000-8000-0000000022f8
M=00000000-0000-4000-8000-0000000022f9
A_OUT=$(mktemp); B_OUT=$(mktemp)
trap 'rm -f "$A_OUT" "$B_OUT"' EXIT
fail=0

"${PSQL[@]}" >/dev/null <<SQL || { echo "SETUP FAIL: fixtures"; exit 2; }
INSERT INTO public.tenants (id, name, slug) VALUES ('$T', 'Race22', 'race22');
INSERT INTO public.users (id, tenant_id, display_name, email, role) VALUES
  ('$OP', '$T', 'Op', 'op@race22.test', 'operator'),
  ('$SUP', '$T', 'Sup', 'sup@race22.test', 'tenant_admin');
INSERT INTO public.customers (id, tenant_id, customer_number) VALUES ('$C', '$T', 'R22-C');
INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount) VALUES
  (gen_random_uuid(), '$T', '$C', DATE '2025-12-01', 'charge', 'Dec', 100.00),
  ('$WO', '$T', '$C', DATE '2025-12-15', 'write_off', 'written off', -50.00);
INSERT INTO public.accounting_periods (id, tenant_id, period_start, period_end) VALUES ('$JAN', '$T', DATE '2026-01-01', DATE '2026-01-31');
INSERT INTO public.accounting_periods (id, tenant_id, period_start, period_end) VALUES ('$FEB', '$T', DATE '2026-02-01', DATE '2026-02-28');
INSERT INTO public.accounting_periods (id, tenant_id, period_start, period_end) VALUES ('$MAR', '$T', DATE '2026-03-01', DATE '2026-03-31');
SQL

waiting() {
local n i
for i in 1 2 3 4 5 6 7 8 9 10; do
  n=$(docker exec -i tally-pg psql -U tally -d "$DB" -At -c "SELECT count(*) FROM pg_stat_activity b JOIN pg_stat_activity a ON a.datname = b.datname AND a.application_name = 'race22_a' WHERE b.datname = current_database() AND b.application_name = 'race22_b' AND a.pid = ANY (pg_blocking_pids(b.pid))" 2>/dev/null)
  if [[ "$n" =~ ^[0-9]+$ ]] && [ "$n" -ge 1 ]; then echo 1; return; fi
  sleep 0.15
done
echo 0
}
AS_OP="SET LOCAL app.user_id = '$OP'; SET ROLE tally_app;"
AS_SUP="SET LOCAL app.user_id = '$SUP'; SET ROLE tally_app;"
post() {  # $1 date, $2 amount, $3 description
echo "INSERT INTO public.account_ledger (tenant_id, customer_id, transaction_date, transaction_type, description, amount) VALUES ('$T', '$C', DATE '$1', 'adjustment', '$3', $2);"
}

two() {  # $1 A's prelude, $2 A's statement, $3 B's prelude, $4 B's statement
"${PSQL[@]}" >"$A_OUT" 2>&1 <<SQL &
SET application_name = 'race22_a';
BEGIN;
$1
$2
SELECT pg_sleep(3);
COMMIT;
SQL
APID=$!
sleep 1
"${PSQL[@]}" >"$B_OUT" 2>&1 <<SQL &
SET application_name = 'race22_b';
BEGIN;
$3
$4
COMMIT;
SQL
BPID=$!
sleep 1
WAITED=$(waiting)
wait $APID; AST=$?
wait $BPID; BST=$?
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

# CR1
two "$AS_OP" "$(post 2026-01-15 7.00 'CR1 in flight')" \
    "$AS_SUP" "SELECT public.close_accounting_period('$JAN');"
verdict "CR1 a close waits for a posting in flight, then closes" 0
expect "CR1b the snapshot counts the row it waited for" \
  "$("${PSQL[@]}" -c "SELECT ledger_entry_count || '/' || closing_balance FROM public.accounting_period_snapshots WHERE period_id = '$JAN'")" "1/57.00"

# CR2
two "$AS_SUP" "SELECT public.close_accounting_period('$FEB');" \
    "$AS_OP" "$(post 2026-02-10 3.00 'CR2 late')"
verdict "CR2 a posting into a period being closed waits, then is refused" 1 "a closed period is frozen"

# CR3
"${PSQL[@]}" >"$B_OUT" 2>&1 <<SQL &
BEGIN ISOLATION LEVEL REPEATABLE READ;
$AS_OP
SELECT count(*) FROM public.accounting_close_heads;
SELECT pg_sleep(3);
$(post 2026-03-05 4.00 'CR3 stale')
COMMIT;
SQL
BPID=$!
sleep 1
OUT=$("${PSQL[@]}" 2>&1 <<SQL
BEGIN;
$AS_SUP
SELECT public.close_accounting_period('$MAR');
COMMIT;
SQL
)
AST=$?
wait $BPID; BST=$?
if [ $AST -eq 0 ] && [ $BST -ne 0 ] && grep -q "40001" "$B_OUT"; then echo "PASS CR3 a posting under a snapshot older than the close fails to serialise"
else echo "FAIL CR3: close=$AST ($OUT) poster=$BST: $(cat "$B_OUT")"; fail=1; fi

# CR4
iso() {  # $1 label, $2 prelude, $3 statement
OUT=$("${PSQL[@]}" 2>&1 <<SQL
BEGIN ISOLATION LEVEL REPEATABLE READ;
$2
$3
COMMIT;
SQL
)
if echo "$OUT" | grep -q "25000" && echo "$OUT" | grep -q "READ COMMITTED"; then echo "PASS $1"; else echo "FAIL $1: $OUT"; fail=1; fi
}
"${PSQL[@]}" >/dev/null -c "INSERT INTO public.accounting_periods (tenant_id, period_start, period_end) VALUES ('$T', DATE '2026-04-01', DATE '2026-04-30')" \
  || { echo "SETUP FAIL: April"; exit 2; }
APR=$("${PSQL[@]}" -c "SELECT id FROM public.accounting_periods WHERE tenant_id = '$T' AND period_start = DATE '2026-04-01'")
iso "CR4 the close refuses REPEATABLE READ" "$AS_SUP" "SELECT public.close_accounting_period('$APR');"
iso "CR4b a period insert refuses REPEATABLE READ" "$AS_OP" "INSERT INTO public.accounting_periods (tenant_id, period_start, period_end) VALUES ('$T', DATE '2026-05-01', DATE '2026-05-31');"
iso "CR4c a recovery refuses REPEATABLE READ" "$AS_OP" "INSERT INTO public.account_ledger (tenant_id, customer_id, transaction_date, transaction_type, description, amount, reverses_ledger_entry_id, reversal_reason) VALUES ('$T', '$C', DATE '2026-05-02', 'write_off_recovery', 'r', 1, '$WO', 'paid');"

# CR5
REC="INSERT INTO public.account_ledger (tenant_id, customer_id, transaction_date, transaction_type, description, amount, reverses_ledger_entry_id, reversal_reason) VALUES ('$T', '$C', DATE '2026-05-02', 'write_off_recovery', 'r', 30, '$WO', 'agency');"
two "$AS_OP" "$REC" "$AS_OP" "$REC"
verdict "CR5 a second recovery past the cap waits for the first, then is refused" 1 "R-02 cap"

# CR6
INS="INSERT INTO public.accounting_periods (tenant_id, period_start, period_end) VALUES ('$T', DATE '2026-05-01', DATE '2026-05-31');"
two "$AS_OP" "$INS" "$AS_OP" "$INS"
verdict "CR6 two inserts of the next period: the second waits, then is refused" 1 "no gaps"

# CR7: later postings (May) and a backdated setting change (a direct
# history row recorded before January's instant) leave January's figures
# reproducible from its stored edges.
"${PSQL[@]}" >/dev/null <<SQL || { echo "SETUP FAIL: CR7 postings"; exit 2; }
BEGIN; $AS_OP $(post 2026-05-03 11.00 'CR7 later') COMMIT;
BEGIN; $AS_SUP
INSERT INTO public.tenant_configuration_history (tenant_id, config_key, new_value, effective_from, change_source)
SELECT '$T', 'receivables_aging_bucket_days', '[10, 20]', s.recorded_at - interval '1 millisecond', 'manual'
  FROM public.accounting_period_snapshots s WHERE s.period_id = '$JAN';
COMMIT;
SQL
expect "CR7 January's aging lines are the aging at its recorded instant" \
  "$("${PSQL[@]}" -c "SELECT (SELECT jsonb_object_agg(code, amount) FROM public.accounting_period_snapshot_lines WHERE period_id = '$JAN' AND section = 'aging')
     = (SELECT jsonb_object_agg(CASE WHEN bucket_index IS NULL THEN 'credit_balance' WHEN bucket_to_days IS NULL THEN bucket_from_days || '+' ELSE bucket_from_days || '-' || bucket_to_days END, s)
          FROM (SELECT bucket_index, bucket_from_days, bucket_to_days, sum(amount) s
                  FROM public.accounting_period_snapshots s,
                       public.receivables_aging_as_of('$T', DATE '2026-01-31', s.recorded_at, s.aging_bucket_days)
                 WHERE s.period_id = '$JAN'
                 GROUP BY 1, 2, 3) x)")" "t"
expect "CR7b and its closing balance is the ledger through January 31, then and now" \
  "$("${PSQL[@]}" -c "SELECT s.closing_balance = (SELECT sum(amount) FROM public.account_ledger WHERE tenant_id = '$T' AND transaction_date <= s.period_end AND created_at <= s.recorded_at)
                         AND s.closing_balance = (SELECT sum(amount) FROM public.account_ledger WHERE tenant_id = '$T' AND transaction_date <= s.period_end)
                        FROM public.accounting_period_snapshots s WHERE s.period_id = '$JAN'")" "t"

# CR8
"${PSQL[@]}" >/dev/null <<SQL || { echo "SETUP FAIL: CR8 mapping"; exit 2; }
BEGIN; $AS_OP
INSERT INTO public.gl_account_mappings (id, tenant_id, charge_source, charge_code, gl_account, effective_from)
VALUES ('$M', '$T', 'ledger_entry', 'adjustment', '4900', DATE '2026-05-01');
COMMIT;
SQL
T1=$("${PSQL[@]}" -c "SELECT clock_timestamp()")
"${PSQL[@]}" >/dev/null <<SQL || { echo "SETUP FAIL: CR8 close"; exit 2; }
BEGIN; $AS_OP
UPDATE public.gl_account_mappings SET effective_to = DATE '2026-06-01' WHERE id = '$M';
COMMIT;
SQL
expect "CR8 a lookup at an instant before the mapping's close still finds it on a later date" \
  "$("${PSQL[@]}" -c "SELECT public.gl_mapping_as_of('$T', 'ledger_entry', 'adjustment', NULL, NULL, NULL, DATE '2026-07-01', '$T1')")" "$M"
expect "CR8b after the close it does not" \
  "$("${PSQL[@]}" -c "SELECT coalesce(public.gl_mapping_as_of('$T', 'ledger_entry', 'adjustment', NULL, NULL, NULL, DATE '2026-07-01', clock_timestamp())::text, 'none')")" "none"
expect "CR8c and before it was recorded there is none" \
  "$("${PSQL[@]}" -c "SELECT coalesce(public.gl_mapping_as_of('$T', 'ledger_entry', 'adjustment', NULL, NULL, NULL, DATE '2026-05-15', (SELECT created_at - interval '1 microsecond' FROM public.gl_account_mappings WHERE id = '$M'))::text, 'none')")" "none"

# CR9
GL="INSERT INTO public.gl_account_mappings (tenant_id, charge_source, charge_code, gl_account, effective_from) VALUES ('$T', 'ledger_entry', 'payment', '1100', DATE '2026-04-15');"
two "$AS_SUP" "SELECT public.close_accounting_period('$APR');" "$AS_OP" "$GL"
verdict "CR9 a GL mapping in force in a period being closed waits, then is refused" 1 "closed period's export"

# CR10
MAY=$("${PSQL[@]}" -c "SELECT id FROM public.accounting_periods WHERE tenant_id = '$T' AND period_start = DATE '2026-05-01'")
OUT=$("${PSQL[@]}" 2>&1 <<SQL
BEGIN; $AS_SUP SELECT public.close_accounting_period('$MAY'); COMMIT;
BEGIN; $AS_OP UPDATE public.accounting_periods SET status = 'withdrawn' WHERE id = '$MAY'; COMMIT;
SQL
)
if echo "$OUT" | grep -q "never edited"; then echo "PASS CR10 the latest period, once closed, is not withdrawn"
else echo "FAIL CR10: $OUT"; fail=1; fi

exit $fail
