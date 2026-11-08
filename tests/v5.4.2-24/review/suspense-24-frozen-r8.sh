#!/usr/bin/env bash
# v5.4.2-24: what one transaction cannot show — two writers on one receipt,
# one pledge, one agency or one provider transaction; a receipt read as known
# before a reversal; the READ COMMITTED pin.
#   SU1  A makes 60 of R1 (100) a payment and holds; B makes 50 more a
#        payment: waits on R1's lock, then is refused (the receipt holds).
#   SU2  A returns 70 of R2 (100) to its sender and holds; B makes 40 a
#        payment: waits, then is refused.
#   SU2b A makes 70 of R3 (100) a payment and holds; B escheats 40: waits,
#        then is refused.
#   SU3  A inserts a pending agency payment naming pledge L1 and holds; B records L1
#        in error: waits on L1's lock, then is refused (a payment names it).
#   SU3b A records L2 in error and holds; B inserts a payment naming L2: waits,
#        then is refused (recorded in error).
#   SU4  A retires agency G2 and holds; B records a pledge from G2: waits on
#        G2's lock, then is refused (retired).
#   SU5  A records receipt R4 of provider transaction X and holds; B records
#        a payment of X: waits, then is refused (recorded once).
#   SU5b the same with a payment first and a receipt second.
#   SU6  R5 (100) made a payment of C1 and committed; the payment reversed
#        (posted to the wrong customer) and committed; then its misposting
#        return committed (r2). Read as known before the return, R5 held 0
#        (the reversal alone gives nothing back); now it holds 100.
#   SU7  a payment from a receipt under REPEATABLE READ is refused (25000).
#   SU8  (r2, Codex B5, Opus B3, Fable B1) a receipt with a provider id, and
#        a payment with one, under REPEATABLE READ are refused (25000).
#   SU9  (r2) R8's payment (100, C1) reversed and committed. A records its
#        misposting return and holds; B makes 100 of R8 C2's payment: waits
#        on R8's lock, then is admitted (the money came back).
#   SU10 (r2, Codex B4) A's transaction begins; B returns 50 of R9 to its
#        sender and commits; A makes 60 of R9 a payment: refused for retry
#        (40001: recorded before a row of the receipt); the retry is refused
#        by the cap, a retry of 50 admitted.
#   SU11 (r3, Opus B1) A's transaction begins; B returns R10's 100 to its
#        sender and commits; A undoes that return: refused for retry (40001).
#   SU12 (r3, Fable B1) R11's payment (100, C1) posted and committed. A's
#        transaction begins; B reverses the payment as misposted and commits;
#        A records its misposting return: refused for retry (40001); the
#        retry is admitted.
# Every two() leg checks that session B was SEEN BLOCKED BY SESSION A.
# Every session runs under a statement timeout. Setup failures exit 2.
# Runs against a THROWAWAY clone (it commits rows).
#   usage: suspense-24.sh <db>      (default: r24)
set -uo pipefail
DB="${1:-r24}"
PSQL=(docker exec -i -e PGOPTIONS=-c\ statement_timeout=30s tally-pg psql -U tally -d "$DB" -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -q -At)
MON=(docker exec -i -e PGOPTIONS=-c\ statement_timeout=5s -e PGCONNECT_TIMEOUT=5 tally-pg psql -U tally -d "$DB" -At)
P=00000000-0000-4000-8000-0000000b24
T=${P}f0; OP=${P}f1; C1=${P}f2; C2=${P}f3
A_OUT=$(mktemp); B_OUT=$(mktemp)
trap 'rm -f "$A_OUT" "$B_OUT"' EXIT
fail=0

rcpt() {  # $1 id, $2 number, $3 amount, $4 provider transaction or empty
local txn="NULL" src="bank_lockbox" chan="lockbox" chk="'CHK-$2'"
if [ -n "${4:-}" ]; then txn="'$4'"; src="stripe_webhook"; chan="api"; chk="NULL"; fi
echo "INSERT INTO public.suspense_receipts (id, tenant_id, receipt_number, amount, received_on, channel, source_system, check_number, provider_transaction_id, payer_name, recorded_by) VALUES ('$1', '$T', '$2', $3, DATE '2026-03-02', '$chan', '$src', $chk, $txn, 'J. Smith', '$OP');"
}
fromr() {  # $1 receipt, $2 customer, $3 amount, $4 payment id (optional)
local id="${4:-}"; [ -n "$id" ] && id="'$id'" || id="gen_random_uuid()"
echo "INSERT INTO public.payments (id, tenant_id, payment_number, customer_id, payment_date, effective_date, effective_date_method, amount, payment_method, channel, source_system, check_number, suspense_receipt_id, suspense_resolution_reason, suspense_resolved_by)
SELECT $id, '$T', 'SU-' || left(gen_random_uuid()::text, 8), '$2', r.received_on, r.received_on, 'lockbox_receipt', $3, 'check', r.channel, r.source_system, r.check_number, r.id, 'identified', '$OP' FROM public.suspense_receipts r WHERE r.id = '$1';"
}
disp() {  # $1 receipt, $2 kind, $3 amount
echo "INSERT INTO public.suspense_receipt_dispositions (tenant_id, suspense_receipt_id, kind, amount, disposed_on, instrument_reference, jurisdiction, report_reference, reason, recorded_by)
VALUES ('$T', '$1', '$2', $3, DATE '2026-04-01', CASE WHEN '$2' = 'returned_to_sender' THEN 'RCHK-1' END, CASE WHEN '$2' = 'escheated' THEN 'TX' END, CASE WHEN '$2' = 'escheated' THEN 'UP-1' END, 'race', '$OP');"
}
apay() {  # $1 pledge, $2 amount
echo "INSERT INTO public.payments (tenant_id, payment_number, customer_id, payment_date, amount, payment_method, payer_class, agency_id, agency_pledge_id) VALUES ('$T', 'SA-' || left(gen_random_uuid()::text, 8), '$C1', DATE '2026-03-20', $2, 'check', 'agency', '${P}a1', '$1');"
}
inerror() {  # $1 pledge
echo "INSERT INTO public.agency_pledge_events (tenant_id, agency_pledge_id, event, reason, recorded_by) VALUES ('$T', '$1', 'recorded_in_error', 'race', '$OP');"
}

"${PSQL[@]}" >/tmp/r24setup.out 2>&1 <<SQL || { echo "SETUP FAIL: fixtures"; cat /tmp/r24setup.out; exit 2; }
BEGIN;
INSERT INTO public.tenants (id, name, slug) VALUES ('$T', 'Race24', 'race24');
INSERT INTO public.users (id, tenant_id, display_name, email, role) VALUES ('$OP', '$T', 'Op', 'op@race24.test', 'operator');
INSERT INTO public.customers (id, tenant_id, customer_number, customer_type) VALUES ('$C1', '$T', 'R24-C1', 'residential'), ('$C2', '$T', 'R24-C2', 'residential');
SET LOCAL app.user_id = '$OP'; SET ROLE tally_app;
$(rcpt ${P}01 R24-1 100)
$(rcpt ${P}02 R24-2 100)
$(rcpt ${P}03 R24-3 100)
$(rcpt ${P}05 R24-5 100)
$(rcpt ${P}07 R24-7 100)
$(rcpt ${P}08 R24-8 100)
$(rcpt ${P}09 R24-9 100)
$(rcpt ${P}0b R24-10 100)
$(rcpt ${P}0c R24-11 100)
INSERT INTO public.assistance_agencies (id, tenant_id, name, program_kind, recorded_by) VALUES ('${P}a1', '$T', 'CEAP', 'liheap_ceap', '$OP'), ('${P}a2', '$T', 'Charity', 'charity', '$OP');
INSERT INTO public.agency_pledges (id, tenant_id, customer_id, agency_id, amount, pledged_on, form, recorded_by) VALUES
  ('${P}11', '$T', '$C1', '${P}a1', 100, DATE '2026-03-10', 'written', '$OP'),
  ('${P}12', '$T', '$C1', '${P}a1', 100, DATE '2026-03-10', 'written', '$OP');
COMMIT;
SQL

waiting() {
local n i
for i in 1 2 3 4 5 6 7 8 9 10; do
  n=$("${MON[@]}" -c "SELECT count(*) FROM pg_stat_activity b JOIN pg_stat_activity a ON a.datname = b.datname AND a.application_name = 'race24_a' WHERE b.datname = current_database() AND b.application_name = 'race24_b' AND a.pid = ANY (pg_blocking_pids(b.pid))" 2>/dev/null)
  if [[ "$n" =~ ^[0-9]+$ ]] && [ "$n" -ge 1 ]; then echo 1; return; fi
  sleep 0.15
done
echo 0
}
AS_OP="SET LOCAL app.user_id = '$OP'; SET ROLE tally_app;"
two() {  # $1 A's statement, $2 B's statement
"${PSQL[@]}" >"$A_OUT" 2>&1 <<SQL &
SET application_name = 'race24_a';
BEGIN;
$AS_OP
$1
SELECT pg_sleep(3);
COMMIT;
SQL
APID=$!
sleep 1
"${PSQL[@]}" >"$B_OUT" 2>&1 <<SQL &
SET application_name = 'race24_b';
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
verdict() {  # $1 label, $2 expected fragment of B's refusal
if [ "${AST:-0}" -ne 0 ]; then echo "FAIL $1: session A itself failed: $(cat "$A_OUT")"; fail=1; return; fi
if [ "${WAITED:-0}" -lt 1 ]; then echo "FAIL $1: session B was never seen waiting on a lock"; fail=1; return; fi
if [ "$BST" -ne 0 ] && echo "$OUT" | grep -q "$2"; then echo "PASS $1"; else echo "FAIL $1: expected B refused with '$2', got ($BST): $OUT"; fail=1; fi
}
expect() {  # $1 label, $2 actual, $3 expected
if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: got [$2], expected [$3]"; fail=1; fi
}
held() {  # $1 receipt, $2 recorded instant (SQL)
"${PSQL[@]}" -c "SELECT held FROM public.suspense_receipt_position_as_of('$1', DATE '2026-12-31', $2)"
}

two "$(fromr ${P}01 $C1 60)" "$(fromr ${P}01 $C2 50)"
verdict "SU1 two payments race R1's last 40: the second waits, then is refused" "the receipt holds"
expect "SU1b R1 holds 40" "$(held ${P}01 'clock_timestamp()')" "40.00"

two "$(disp ${P}02 returned_to_sender 70)" "$(fromr ${P}02 $C2 40)"
verdict "SU2 a return and a payment race R2: the payment waits, then is refused" "the receipt holds"

two "$(fromr ${P}03 $C1 70)" "$(disp ${P}03 escheated 40)"
verdict "SU2b a payment and an escheat race R3: the escheat waits, then is refused" "the receipt holds"

two "$(apay ${P}11 50)" "$(inerror ${P}11)"
verdict "SU3 a payment naming L1 and L1 recorded in error: the event waits, then is refused" "a payment names it"

two "$(inerror ${P}12)" "$(apay ${P}12 50)"
verdict "SU3b L2 recorded in error and a payment naming it: the payment waits, then is refused" "recorded in error"

two "UPDATE public.assistance_agencies SET status = 'retired', retired_by = '$OP', retired_reason = 'race' WHERE id = '${P}a2';" \
    "INSERT INTO public.agency_pledges (tenant_id, customer_id, agency_id, amount, pledged_on, form, recorded_by) VALUES ('$T', '$C1', '${P}a2', 10, DATE '2026-03-10', 'written', '$OP');"
verdict "SU4 an agency retired and a pledge from it: the pledge waits, then is refused" "is retired"

two "$(rcpt ${P}04 R24-4 25 pi_race_1)" \
    "INSERT INTO public.payments (tenant_id, payment_number, customer_id, payment_date, amount, payment_method, channel, source_system, provider_transaction_id) VALUES ('$T', 'SU5', '$C1', DATE '2026-03-02', 25, 'online', 'api', 'stripe_webhook', 'pi_race_1');"
verdict "SU5 a receipt and a payment of one provider transaction: the payment waits, then is refused" "already recorded"

two "INSERT INTO public.payments (tenant_id, payment_number, customer_id, payment_date, amount, payment_method, channel, source_system, provider_transaction_id) VALUES ('$T', 'SU5b', '$C1', DATE '2026-03-02', 25, 'online', 'api', 'stripe_webhook', 'pi_race_2');" \
    "$(rcpt ${P}06 R24-6 25 pi_race_2)"
verdict "SU5b a payment and a receipt of one provider transaction: the receipt waits, then is refused" "already recorded"

# SU6: posted, committed; reversed, committed; read in between.
"${PSQL[@]}" >/tmp/r24su6.out 2>&1 <<SQL || { echo "FAIL SU6 setup: $(cat /tmp/r24su6.out)"; fail=1; }
BEGIN;
$AS_OP
$(fromr ${P}05 $C1 100 ${P}21)
INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reference_type, reference_id) VALUES ('${P}31', '$T', '$C1', DATE '2026-03-02', 'payment', 'posted', -100, 'payment', '${P}21');
UPDATE public.payments SET status = 'posted', status_cause_id = '${P}31' WHERE id = '${P}21';
COMMIT;
SQL
T0=$("${PSQL[@]}" -c "SELECT clock_timestamp()")
"${PSQL[@]}" >/tmp/r24su6b.out 2>&1 <<SQL || { echo "FAIL SU6 reversal: $(cat /tmp/r24su6b.out)"; fail=1; }
BEGIN;
$AS_OP
INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reference_type, reference_id, reverses_ledger_entry_id, reversal_reason) VALUES ('${P}32', '$T', '$C1', DATE '2026-03-05', 'adjustment', 'posted to the wrong customer', 100, 'payment', '${P}21', '${P}31', 'posted to the wrong customer');
UPDATE public.payments SET status = 'reversed', reversed_at = now(), reversed_by = '$OP', reversed_reason = 'posted to the wrong customer', status_cause_id = '${P}32' WHERE id = '${P}21';
COMMIT;
SQL
T1=$("${PSQL[@]}" -c "SELECT clock_timestamp()")
"${PSQL[@]}" >/tmp/r24su6c.out 2>&1 <<SQL || { echo "FAIL SU6 return: $(cat /tmp/r24su6c.out)"; fail=1; }
BEGIN;
$AS_OP
INSERT INTO public.suspense_receipt_dispositions (tenant_id, suspense_receipt_id, kind, amount, disposed_on, reason, recorded_by, returned_payment_id)
VALUES ('$T', '${P}05', 'misposting_returned', -100, DATE '2026-03-05', 'posted to the wrong customer', '$OP', '${P}21');
COMMIT;
SQL
expect "SU6 as known before the payment was reversed, R5 held 0" "$(held ${P}05 "'$T0'::timestamptz")" "0.00"
expect "SU6a as known after the reversal, before its misposting return, R5 still held 0" "$(held ${P}05 "'$T1'::timestamptz")" "0.00"
expect "SU6b now it holds 100 again" "$(held ${P}05 'clock_timestamp()')" "100.00"

OUT=$("${PSQL[@]}" 2>&1 <<SQL
BEGIN ISOLATION LEVEL REPEATABLE READ;
$AS_OP
$(fromr ${P}07 $C1 10)
COMMIT;
SQL
)
if [ $? -ne 0 ] && echo "$OUT" | grep -q "25000"; then echo "PASS SU7 a payment from a receipt under REPEATABLE READ is refused"; else echo "FAIL SU7: $OUT"; fail=1; fi

for lvl in "REPEATABLE READ" "SERIALIZABLE"; do
OUT=$("${PSQL[@]}" 2>&1 <<SQL
BEGIN ISOLATION LEVEL $lvl;
$AS_OP
$(rcpt ${P}0a R24-A-$RANDOM 5 pi_iso_$RANDOM)
COMMIT;
SQL
)
if [ $? -ne 0 ] && echo "$OUT" | grep -q "25000"; then echo "PASS SU8 a receipt with a provider id under $lvl is refused"; else echo "FAIL SU8 ($lvl): $OUT"; fail=1; fi
OUT=$("${PSQL[@]}" 2>&1 <<SQL
BEGIN ISOLATION LEVEL $lvl;
$AS_OP
INSERT INTO public.payments (tenant_id, payment_number, customer_id, payment_date, amount, payment_method, channel, source_system, provider_transaction_id) VALUES ('$T', 'SU8-' || left(gen_random_uuid()::text, 8), '$C1', DATE '2026-03-02', 5, 'online', 'api', 'stripe_webhook', 'pi_iso_p$RANDOM');
COMMIT;
SQL
)
if [ $? -ne 0 ] && echo "$OUT" | grep -q "25000"; then echo "PASS SU8b a payment with a provider id under $lvl is refused"; else echo "FAIL SU8b ($lvl): $OUT"; fail=1; fi
done

# SU9: R8's payment posted and reversed, committed; then the race.
"${PSQL[@]}" >/tmp/r24su9.out 2>&1 <<SQL || { echo "FAIL SU9 setup: $(cat /tmp/r24su9.out)"; fail=1; }
BEGIN;
$AS_OP
$(fromr ${P}08 $C1 100 ${P}22)
INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reference_type, reference_id) VALUES ('${P}33', '$T', '$C1', DATE '2026-03-02', 'payment', 'posted', -100, 'payment', '${P}22');
UPDATE public.payments SET status = 'posted', status_cause_id = '${P}33' WHERE id = '${P}22';
INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reference_type, reference_id, reverses_ledger_entry_id, reversal_reason) VALUES ('${P}34', '$T', '$C1', DATE '2026-03-05', 'adjustment', 'misposted', 100, 'payment', '${P}22', '${P}33', 'misposted');
UPDATE public.payments SET status = 'reversed', reversed_at = now(), reversed_by = '$OP', reversed_reason = 'misposted', status_cause_id = '${P}34' WHERE id = '${P}22';
COMMIT;
SQL
two "INSERT INTO public.suspense_receipt_dispositions (tenant_id, suspense_receipt_id, kind, amount, disposed_on, reason, recorded_by, returned_payment_id) VALUES ('$T', '${P}08', 'misposting_returned', -100, DATE '2026-03-05', 'misposted', '$OP', '${P}22');" \
    "INSERT INTO public.payments (tenant_id, payment_number, customer_id, payment_date, effective_date, effective_date_method, amount, payment_method, channel, source_system, check_number, suspense_receipt_id, suspense_resolution_reason, suspense_resolved_by) SELECT '$T', 'SU9', '$C2', DATE '2026-03-05', r.received_on, 'lockbox_receipt', 100, 'check', r.channel, r.source_system, r.check_number, r.id, 'identified', '$OP' FROM public.suspense_receipts r WHERE r.id = '${P}08';"
if [ "${AST:-0}" -eq 0 ] && [ "${WAITED:-0}" -ge 1 ] && [ "$BST" -eq 0 ]; then echo "PASS SU9 a payment waits on R8's misposting return, then is admitted"; else echo "FAIL SU9: A=$AST waited=$WAITED B=$BST: $OUT $(cat "$A_OUT")"; fail=1; fi

# SU10: A begins; B returns 50 of R9 and commits; A pays 60 from R9.
"${PSQL[@]}" >"$A_OUT" 2>&1 <<SQL &
BEGIN;
$AS_OP
SELECT now();
SELECT pg_sleep(3);
$(fromr ${P}09 $C1 60)
COMMIT;
SQL
APID=$!
sleep 1
OUT=$("${PSQL[@]}" 2>&1 <<SQL
BEGIN;
$AS_OP
$(disp ${P}09 returned_to_sender 50)
COMMIT;
SQL
) || { echo "FAIL SU10 B: $OUT"; fail=1; }
wait $APID; AST=$?
if [ "$AST" -ne 0 ] && grep -q "40001" "$A_OUT"; then echo "PASS SU10 a payment begun before a committed return is refused for retry (40001)"; else echo "FAIL SU10: A=$AST: $(cat "$A_OUT")"; fail=1; fi
OUT=$("${PSQL[@]}" 2>&1 <<SQL
BEGIN;
$AS_OP
$(fromr ${P}09 $C1 60)
COMMIT;
SQL
)
if [ $? -ne 0 ] && echo "$OUT" | grep -q "the receipt holds"; then echo "PASS SU10b the retry of 60 is refused by the cap"; else echo "FAIL SU10b: $OUT"; fail=1; fi
OUT=$("${PSQL[@]}" 2>&1 <<SQL
BEGIN;
$AS_OP
$(fromr ${P}09 $C1 50)
COMMIT;
SQL
)
if [ $? -eq 0 ]; then echo "PASS SU10c a retry of 50 is admitted"; else echo "FAIL SU10c: $OUT"; fail=1; fi

begun_then() {  # $1 A's statement after its transaction began and B committed, $2 B's statement
"${PSQL[@]}" >"$A_OUT" 2>&1 <<SQL &
BEGIN;
$AS_OP
SELECT now();
SELECT pg_sleep(3);
$1
COMMIT;
SQL
APID=$!
sleep 1
OUT=$("${PSQL[@]}" 2>&1 <<SQL
BEGIN;
$AS_OP
$2
COMMIT;
SQL
) || { echo "FAIL B of a begun leg: $OUT"; fail=1; }
wait $APID; AST=$?
}
begun_then "INSERT INTO public.suspense_receipt_dispositions (tenant_id, suspense_receipt_id, kind, amount, disposed_on, reason, recorded_by, undoes_disposition_id) VALUES ('$T', '${P}0b', 'undo', -100, DATE '2026-04-02', 'check came back', '$OP', '${P}2b');" \
           "INSERT INTO public.suspense_receipt_dispositions (id, tenant_id, suspense_receipt_id, kind, amount, disposed_on, instrument_reference, reason, recorded_by) VALUES ('${P}2b', '$T', '${P}0b', 'returned_to_sender', 100, DATE '2026-04-01', 'RCHK-2b', 'returned', '$OP');"
if [ "$AST" -ne 0 ] && grep -q "40001" "$A_OUT"; then echo "PASS SU11 an undo begun before its original committed is refused for retry (40001)"; else echo "FAIL SU11: A=$AST: $(cat "$A_OUT")"; fail=1; fi

"${PSQL[@]}" >/tmp/r24su12.out 2>&1 <<SQL || { echo "FAIL SU12 setup: $(cat /tmp/r24su12.out)"; fail=1; }
BEGIN;
$AS_OP
$(fromr ${P}0c $C1 100 ${P}23)
INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reference_type, reference_id) VALUES ('${P}35', '$T', '$C1', DATE '2026-03-02', 'payment', 'posted', -100, 'payment', '${P}23');
UPDATE public.payments SET status = 'posted', status_cause_id = '${P}35' WHERE id = '${P}23';
COMMIT;
SQL
MRET="INSERT INTO public.suspense_receipt_dispositions (tenant_id, suspense_receipt_id, kind, amount, disposed_on, reason, recorded_by, returned_payment_id) VALUES ('$T', '${P}0c', 'misposting_returned', -100, DATE '2026-03-05', 'misposted', '$OP', '${P}23');"
begun_then "$MRET" \
           "INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reference_type, reference_id, reverses_ledger_entry_id, reversal_reason) VALUES ('${P}36', '$T', '$C1', DATE '2026-03-05', 'adjustment', 'misposted', 100, 'payment', '${P}23', '${P}35', 'misposted');
UPDATE public.payments SET status = 'reversed', reversed_at = now(), reversed_by = '$OP', reversed_reason = 'misposted', status_cause_id = '${P}36' WHERE id = '${P}23';"
if [ "$AST" -ne 0 ] && grep -q "40001" "$A_OUT"; then echo "PASS SU12 a misposting return begun before the reversal committed is refused for retry (40001)"; else echo "FAIL SU12: A=$AST: $(cat "$A_OUT")"; fail=1; fi
OUT=$("${PSQL[@]}" 2>&1 <<SQL
BEGIN;
$AS_OP
$MRET
COMMIT;
SQL
)
if [ $? -eq 0 ]; then echo "PASS SU12b the retry is admitted"; else echo "FAIL SU12b: $OUT"; fail=1; fi

exit $fail
