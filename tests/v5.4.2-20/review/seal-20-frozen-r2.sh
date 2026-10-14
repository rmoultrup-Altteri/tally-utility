#!/usr/bin/env bash
# v5.4.2-20: what one transaction cannot show — two sessions, and the
# boundaries of a transaction.
#   RC1  READ COMMITTED: A checks schedule S at version 1 and holds; B checks
#        it at version 1, waits on the header row, then gets 40001 once A
#        commits: two editors holding one token cannot both write.
#   RC2  the same, A rolls back: B waits, then succeeds (version 2).
#   RC3  A voids bill H1 and holds; B bills a charge onto H1, waits on the
#        bill (FOR SHARE behind the void's FOR UPDATE), then is refused.
#   RC4  A bills a charge onto H2 and holds; B voids H2, waits, then voids it
#        AND disposes of the charge A attached: nothing is stranded.
#   RC5  A voids H3 and holds; B voids H3, waits, then is refused before any
#        side effect: one reversal.
#   RC3b (r2) A voids H4 and holds; B, at REPEATABLE READ, bills a charge onto
#        H4, waits, then fails to serialise.
#   RC6  (r2) A edits a charge already billed on H5, then attaches another to
#        H5; B voids H5 between the two. They deadlock; PostgreSQL aborts one
#        and no charge is left billed on a void bill.
#   T1   a receipt from a committed transaction admits nothing later.
#   T2   autocommit: the check and the write as two statements are refused.
#   T3   a session that never set app.user_id (Opus B1): the void and the
#        check both answer "not found" for another tenant's rows; nothing is
#        voided.
#   T4   a read-only transaction holds no receipt and the test raises nothing.
#   T5   a committed version row is closed in a later transaction with no
#        check: refused (the guard fires on UPDATE as on INSERT).
#   T6   (r2) COPY by the application into a version table: refused.
#   T7   (r2) a void at REPEATABLE READ: refused before it locks anything.
# Every race leg checks that session B ITSELF was SEEN BLOCKED BY SESSION A
# (pg_blocking_pids, polled while A holds). Setup failures exit 2.
# Runs against a THROWAWAY clone (it commits rows).
#   usage: seal-20.sh <db>      (default: r20)
set -uo pipefail
DB="${1:-r20}"
PSQL=(docker exec -i tally-pg psql -U tally -d "$DB" -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -q -At)

T=00000000-0000-4000-8000-0000000020e1
T2=00000000-0000-4000-8000-0000000020e2
U=00000000-0000-4000-8000-0000000020e3
C=00000000-0000-4000-8000-0000000020e4
C2=00000000-0000-4000-8000-0000000020e5
L=00000000-0000-4000-8000-0000000020e6
L2=00000000-0000-4000-8000-0000000020e7
S=00000000-0000-4000-8000-0000000020e8
S2=00000000-0000-4000-8000-0000000020e9
Z=00000000-0000-4000-8000-0000000020ea
H1=00000000-0000-4000-8000-0000000020f1
H2=00000000-0000-4000-8000-0000000020f2
H3=00000000-0000-4000-8000-0000000020f3
H4=00000000-0000-4000-8000-0000000020f4
H5=00000000-0000-4000-8000-0000000020f5
H9=00000000-0000-4000-8000-0000000020f9
A3=00000000-0000-4000-8000-0000000020c3
C5=00000000-0000-4000-8000-0000000020c5
D5=00000000-0000-4000-8000-0000000020c6
A1=00000000-0000-4000-8000-0000000020c1
A2=00000000-0000-4000-8000-0000000020c2
A_OUT=$(mktemp); B_OUT=$(mktemp)
trap 'rm -f "$A_OUT" "$B_OUT"' EXIT
fail=0

held() {  # $1 id, $2 tenant, $3 customer, $4 location, $5 number
echo "INSERT INTO public.invoices (id, tenant_id, invoice_number, customer_id, location_id, invoice_date, billing_period, period_start, period_end, due_date, status, hold_reason, amount_due)
      VALUES ('$1', '$2', '$5', '$3', '$4', '2026-02-01', '2026-01', '2026-01-01', '2026-01-31', '2026-02-20', 'held', 'race-20', 10.00);"
}
"${PSQL[@]}" >/dev/null <<SQL || { echo "SETUP FAIL: fixtures"; exit 2; }
INSERT INTO public.tenants (id, name, slug) VALUES ('$T', 'Race20', 'race20'), ('$T2', 'Race20b', 'race20b');
INSERT INTO public.users (id, tenant_id, display_name, email, role) VALUES ('$U', '$T', 'Op', 'op@race20.test', 'operator');
INSERT INTO public.customers (id, tenant_id, customer_number, customer_type) VALUES ('$C', '$T', 'R20-C1', 'residential'), ('$C2', '$T2', 'R20-C2', 'residential');
INSERT INTO public.service_locations (id, tenant_id, customer_id, location_number, address_line1, city, state, zip) VALUES
  ('$L', '$T', '$C', 'L1', '1 Main', 'Austin', 'TX', '78701'), ('$L2', '$T2', '$C2', 'L2', '2 Main', 'Austin', 'TX', '78702');
INSERT INTO public.rate_schedules (id, tenant_id, code) VALUES ('$S', '$T', 'RS-R20'), ('$S2', '$T', 'RS-R20b');
INSERT INTO public.wna_zones (id, tenant_id, zone_code) VALUES ('$Z', '$T', 'Z-R20');
$(held "$H1" "$T" "$C" "$L" R20-H1)
$(held "$H2" "$T" "$C" "$L" R20-H2)
$(held "$H3" "$T" "$C" "$L" R20-H3)
$(held "$H4" "$T" "$C" "$L" R20-H4)
$(held "$H5" "$T" "$C" "$L" R20-H5)
$(held "$H9" "$T2" "$C2" "$L2" R20-H9)
INSERT INTO public.adhoc_charges (id, tenant_id, charge_number, customer_id, charge_type, description, amount, regulatory_class, service_type) VALUES
  ('$A1', '$T', 'R20-A1', '$C', 'tap_fee', 'tap', 5.00, 'regulated', 'gas'),
  ('$A2', '$T', 'R20-A2', '$C', 'tap_fee', 'tap', 6.00, 'regulated', 'gas'),
  ('$A3', '$T', 'R20-A3', '$C', 'tap_fee', 'tap', 7.00, 'regulated', 'gas'),
  ('$C5', '$T', 'R20-C5', '$C', 'tap_fee', 'tap', 8.00, 'regulated', 'gas'),
  ('$D5', '$T', 'R20-D5', '$C', 'tap_fee', 'tap', 9.00, 'regulated', 'gas');
UPDATE public.adhoc_charges SET status = 'billed', billed_on_invoice_id = '$H5', billed_at = now() WHERE id = '$C5';
SQL

waiting() {
local n i
for i in 1 2 3 4 5 6 7 8 9 10; do
  n=$(docker exec -i tally-pg psql -U tally -d "$DB" -At -c "SELECT count(*) FROM pg_stat_activity b JOIN pg_stat_activity a ON a.datname = b.datname AND a.application_name = 'race20_a' WHERE b.datname = current_database() AND b.application_name = 'race20_b' AND a.pid = ANY (pg_blocking_pids(b.pid))" 2>/dev/null)
  if [[ "$n" =~ ^[0-9]+$ ]] && [ "$n" -ge 1 ]; then echo 1; return; fi
  sleep 0.15
done
echo 0
}
APP="SET LOCAL app.user_id = '$U'; SET ROLE tally_app;"

two() {  # $1 A's statement, $2 B's statement, $3 A's end (default COMMIT), $4 B's isolation (default READ COMMITTED)
"${PSQL[@]}" >"$A_OUT" 2>&1 <<SQL &
SET application_name = 'race20_a';
BEGIN;
$APP
$1
SELECT pg_sleep(3);
${3:-COMMIT};
SQL
APID=$!
sleep 1
"${PSQL[@]}" >"$B_OUT" 2>&1 <<SQL &
SET application_name = 'race20_b';
BEGIN ISOLATION LEVEL ${4:-READ COMMITTED};
$APP
$2
COMMIT;
SQL
sleep 1
WAITED=$(waiting)
wait $APID; AST=$?
wait
OUT=$(cat "$B_OUT")
}

check() {  # $1 label, $2 expected fragment, $3 a second expected fragment
if [ "${AST:-0}" -ne 0 ]; then echo "FAIL $1: session A itself failed: $(cat "$A_OUT")"; fail=1; return; fi
if [ "${WAITED:-0}" -lt 1 ]; then echo "FAIL $1: session B was never seen waiting on a lock"; fail=1; return; fi
if echo "$OUT" | grep -q "$2" && echo "$OUT" | grep -q "$3"; then
  echo "PASS $1"
else
  echo "FAIL $1: expected '$2' / '$3', got: $OUT"; fail=1
fi
}
one() {  # $1 label, $2 expected fragment, rest: the script (stdin)
local label=$1 want=$2 out
out=$("${PSQL[@]}" 2>&1)
if echo "$out" | grep -q "$want"; then echo "PASS $label"; else echo "FAIL $label: expected '$want', got: $out"; fail=1; fi
}

chk() { echo "SELECT public.assert_reference_version('rate_schedules', '$S', $1);"; }
two "$(chk 1)" "$(chk 1)"
check "RC1 two editors with one token: the second waits on the header, then is told to retry" "40001" "modified since it was read"
two "$(chk 2)" "$(chk 2)" "ROLLBACK"
if [ "$AST" -eq 0 ] && [ "$WAITED" -ge 1 ] && [ "$OUT" = "3" ]; then echo "PASS RC2 the first editor rolls back: the second waits, then checks (version 3)"
else echo "FAIL RC2: waited=$WAITED, B got: $OUT"; fail=1; fi

bill() { echo "UPDATE public.adhoc_charges SET status = 'billed', billed_on_invoice_id = '$2', billed_at = now() WHERE id = '$1';"; }
void() { echo "SELECT public.void_invoice('$1', '$U', 'wrong_rate', 'race-20', true);"; }
two "$(void "$H1")" "$(bill "$A1" "$H1")"
check "RC3 a charge billed onto a bill being voided: waits, then is refused" "23001" "names a void invoice"
two "$(bill "$A2" "$H2")" "$(void "$H2")"
N=$("${PSQL[@]}" -c "SELECT status || '/' || coalesce(voided_from_invoice_id::text, '-') FROM public.adhoc_charges WHERE id = '$A2'")
if [ "$AST" -eq 0 ] && [ "$WAITED" -ge 1 ] && echo "$OUT" | grep -q '"charges_auto_reverted": 1' && [ "$N" = "pending/$H2" ]; then
  echo "PASS RC4 a void racing an attach: waits, then voids the bill and disposes of the attached charge"
else echo "FAIL RC4: waited=$WAITED, charge=$N, B got: $OUT"; fail=1; fi
two "$(void "$H3")" "$(void "$H3")"
check "RC5 two voids of one bill: the second waits, then is refused" "P0001" "is not voidable"
N=$("${PSQL[@]}" -c "SELECT count(*) FROM public.account_ledger WHERE reference_id = '$H3' AND transaction_type = 'void_reversal'")
if [ "$N" = "1" ]; then echo "PASS RC5b one reversal"; else echo "FAIL RC5b: $N reversals"; fail=1; fi

two "$(void "$H4")" "$(bill "$A3" "$H4")" "COMMIT" "REPEATABLE READ"
check "RC3b a charge billed at REPEATABLE READ onto a bill being voided: waits, then fails to serialise" "40001" "could not serialize"

# RC6: A holds a child of H5 (an edit of billed C5), B's void of H5 waits on
# it, then A's attach of D5 waits on B: a deadlock. Either may be aborted.
"${PSQL[@]}" >"$A_OUT" 2>&1 <<SQL &
SET application_name = 'race20_a';
BEGIN;
$APP
UPDATE public.adhoc_charges SET updated_at = clock_timestamp() WHERE id = '$C5';
SELECT pg_sleep(2);
$(bill "$D5" "$H5")
COMMIT;
SQL
APID=$!
sleep 1
"${PSQL[@]}" >"$B_OUT" 2>&1 <<SQL
SET application_name = 'race20_b';
BEGIN;
$APP
$(void "$H5")
COMMIT;
SQL
wait $APID
DL=$(cat "$A_OUT" "$B_OUT" | grep -c "40P01")
N=$("${PSQL[@]}" -c "SELECT count(*) FROM public.adhoc_charges c JOIN public.invoices i ON i.id = c.billed_on_invoice_id WHERE c.status = 'billed' AND i.status = 'void'")
if [ "$DL" -ge 1 ] && [ "$N" = "0" ]; then echo "PASS RC6 an attach after a child edit deadlocks with a void: one is aborted, nothing is left on a void bill"
else echo "FAIL RC6: deadlocks=$DL, charges billed on a void bill=$N; A: $(cat "$A_OUT") B: $(cat "$B_OUT")"; fail=1; fi

ver() { echo "INSERT INTO public.wna_zone_versions (tenant_id, wna_zone_id, zone_name, effective_date, change_type) VALUES ('$T', '$Z', 'Z', DATE '2026-01-01', 'initial');"; }
"${PSQL[@]}" >/dev/null <<SQL || { echo "SETUP FAIL: T1 check"; exit 2; }
BEGIN; $APP SELECT public.assert_reference_version('wna_zones', '$Z', 1); COMMIT;
SQL
one "T1 a committed check admits nothing in a later transaction" "only after the version check" <<SQL
BEGIN; $APP $(ver) COMMIT;
SQL
one "T2 autocommit: the check and the write as two statements" "only after the version check" <<SQL
SET app.user_id = '$U'; SET ROLE tally_app;
SELECT public.assert_reference_version('wna_zones', '$Z', 2);
$(ver)
SQL
one "T3a a session that never named a user voids another tenant's bill" "Invoice not found" <<SQL
SET ROLE tally_app;
SELECT public.void_invoice('$H9', NULL, 'system_error');
SQL
one "T3b a session that never named a user checks a schedule" "not found" <<SQL
SET ROLE tally_app;
SELECT public.assert_reference_version('rate_schedules', '$S2', 1);
SQL
N=$("${PSQL[@]}" -c "SELECT status FROM public.invoices WHERE id = '$H9'")
if [ "$N" = "held" ]; then echo "PASS T3c nothing was voided"; else echo "FAIL T3c: H9 is $N"; fail=1; fi
one "T4 a read-only transaction holds no receipt" "^f$" <<SQL
BEGIN READ ONLY; $APP SELECT public.reference_version_receipt_held('wna_zones', '$Z'); COMMIT;
SQL
"${PSQL[@]}" >/dev/null <<SQL || { echo "SETUP FAIL: T5 version"; exit 2; }
BEGIN; SET LOCAL app.user_id = '$U'; SET ROLE tally_app;
SELECT public.assert_reference_version('rate_schedules', '$S2', 1);
INSERT INTO public.rate_schedule_versions (tenant_id, rate_schedule_id, name, service_type, customer_type, effective_date, change_type)
VALUES ('$T', '$S2', 'RS-R20b', 'gas', 'residential', DATE '2026-01-01', 'initial');
COMMIT;
SQL
one "T5 a committed version closed later with no check" "only after the version check" <<SQL
BEGIN; $APP
UPDATE public.rate_schedule_versions SET recorded_until = now(), closed_type = 'retracted', closed_reason = 'race-20 T5' WHERE rate_schedule_id = '$S2';
COMMIT;
SQL

one "T6 COPY by the application into a version table" "COPY FROM not supported with row-level security" <<SQL
SET app.user_id = '$U'; SET ROLE tally_app;
COPY public.wna_zone_versions (tenant_id, wna_zone_id, zone_name, effective_date, change_type) FROM STDIN;
$T	$Z	Z	2026-01-01	initial
\.
SQL
one "T7 a void at REPEATABLE READ" "runs at READ COMMITTED" <<SQL
BEGIN ISOLATION LEVEL REPEATABLE READ; $APP $(void "$H2") COMMIT;
SQL

exit $fail
