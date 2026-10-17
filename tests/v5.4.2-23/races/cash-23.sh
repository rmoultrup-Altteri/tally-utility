#!/usr/bin/env bash
# v5.4.2-23: what one transaction cannot show — two writers on one source of
# money, one bill line, one ledger tree; a status move against a draw; the
# recorded order; the READ COMMITTED pins.
#   CR1  A applies 60 of a 70 payment and holds; B applies 40 more of it to
#        another line: waits on the source's lock, then is refused (cap).
#   CR2  A applies 40 to a 60 line and holds; B applies 30 more to it from
#        another payment: waits on the line's lock, then is refused (cap).
#   CR3  A applies a payment and holds; B moves it to nsf: waits on the
#        source's lock, then is refused (bounced money still paying a bill).
#   CR4  A's transaction begins, B applies to a line and commits, then A
#        applies to the same line: refused for retry (40001); the retry is
#        admitted.
#   CR5  A reverses 60 of a 100 charge and holds; B reverses 50 more: waits
#        on the tree's lock, then is refused (R-02 cap).
#   CR6  A reverses 30 of a bill's charge and holds; B voids the bill: waits
#        on the tree's lock, then reverses the 60 left (X3), not 90.
#   CR7  An application and a reversal under REPEATABLE READ are refused.
#   CR8  A refunds 30 of a 50 payment and holds; B applies 30 of it: waits,
#        then is refused (the payment's money goes three ways, never past it).
# Every two() leg checks that session B ITSELF was SEEN BLOCKED BY SESSION A
# (pg_blocking_pids, polled while A holds). CR4 orders its sessions by
# barriers (application_name, polled with pg_stat_clear_snapshot()).
# Setup failures exit 2. Runs against a THROWAWAY clone (it commits rows).
#   usage: cash-23.sh <db>      (default: r23)
set -uo pipefail
DB="${1:-r23}"
PSQL=(docker exec -i tally-pg psql -U tally -d "$DB" -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -q -At)

T=00000000-0000-4000-8000-0000000023f0
OP=00000000-0000-4000-8000-0000000023f1
C=00000000-0000-4000-8000-0000000023f2
LOC=00000000-0000-4000-8000-0000000023f3
CITY=00000000-0000-4000-8000-0000000023f4
TAR=00000000-0000-4000-8000-0000000023f5
I1=00000000-0000-4000-8000-000000002401
I2=00000000-0000-4000-8000-000000002402
I3=00000000-0000-4000-8000-000000002403
L11=00000000-0000-4000-8000-000000002411
L12=00000000-0000-4000-8000-000000002412
L21=00000000-0000-4000-8000-000000002421
L22=00000000-0000-4000-8000-000000002422
L31=00000000-0000-4000-8000-000000002431
L32=00000000-0000-4000-8000-000000002432
P3=00000000-0000-4000-8000-000000002463
P4=00000000-0000-4000-8000-000000002464
P5=00000000-0000-4000-8000-000000002465
P6=00000000-0000-4000-8000-000000002466
P7=00000000-0000-4000-8000-000000002467
P8=00000000-0000-4000-8000-000000002468
E6=00000000-0000-4000-8000-000000002486
E6N=00000000-0000-4000-8000-000000002487
CH=00000000-0000-4000-8000-000000002488
CHI2=00000000-0000-4000-8000-000000002489
A_OUT=$(mktemp); B_OUT=$(mktemp)
trap 'rm -f "$A_OUT" "$B_OUT"' EXIT
fail=0

SNAP_INPUTS="'{\"rate_schedule_id\":null,\"rate_schedule_version_id\":null,\"rate_schedule_code\":null,\"customer_type\":null,\"partial_period_policy\":null,\"items\":[]}', '{\"pga_factor\":null,\"btu_factor\":null,\"pressure_factor\":null,\"temperature_factor\":null,\"meter_multiplier\":null,\"factor_stack_intermediates\":{}}', '{\"applied\":false}', '{\"jurisdictions\":[],\"exemptions\":[],\"franchise_fees\":[]}', '{\"reads\":[]}'"
bill() {  # $1 bill, $2 number, $3 line 1 (gas 60), $4 line 2 (add-on 40)
cat <<SQL
INSERT INTO public.invoices (id, tenant_id, invoice_number, customer_id, location_id, invoice_date, billing_period, period_start, period_end, due_date, amount_due)
VALUES ('$1', '$T', '$2', '$C', '$LOC', DATE '2026-03-01', '2026-02', DATE '2026-02-01', DATE '2026-02-28', DATE '2026-03-20', 100.00);
INSERT INTO public.invoice_line_items (id, tenant_id, invoice_id, line_order, service_type, charge_type, description, amount, rate, regulatory_class) VALUES
  ('$3', '$T', '$1', 0, 'gas', 'base_charge', 'Gas service', 60.00, 60.00, 'regulated'),
  ('$4', '$T', '$1', 1, 'general', 'misc', 'Add-on', 40.00, NULL, 'unregulated');
INSERT INTO public.invoice_calculation_snapshots
  (tenant_id, invoice_id, valid_at, recorded_at, snapshot_schema_version, formula_version,
   rate_inputs, gas_factors, wna_inputs, tax_inputs, read_inputs, customer_inputs, period_inputs, line_items)
VALUES ('$T', '$1', DATE '2026-02-28', now(), 'v1', 'race23', $SNAP_INPUTS,
   jsonb_build_object('customer_id', '$C'::uuid, 'customer_class', null, 'location_id', '$LOC'::uuid, 'premise_zones', '{}'::jsonb),
   jsonb_build_object('period_start', DATE '2026-02-01', 'period_end', DATE '2026-02-28', 'days_in_period', 28, 'proration_policy', null),
   (SELECT jsonb_agg(jsonb_build_object('invoice_line_item_id', l.id, 'charge_type', l.charge_type, 'amount', l.amount)) FROM public.invoice_line_items l WHERE l.invoice_id = '$1'));
UPDATE public.invoices SET status = 'pending' WHERE id = '$1';
SQL
}
pay() {  # $1 id, $2 number, $3 amount
echo "('$1', '$T', '$2', '$C', DATE '2026-03-05', $3, 'check', DATE '2026-03-05', 'postmark')"
}

"${PSQL[@]}" >/dev/null <<SQL || { echo "SETUP FAIL: fixtures"; exit 2; }
BEGIN;
INSERT INTO public.tenants (id, name, slug) VALUES ('$T', 'Race23', 'race23');
INSERT INTO public.users (id, tenant_id, display_name, email, role) VALUES ('$OP', '$T', 'Op', 'op@race23.test', 'operator');
INSERT INTO public.customers (id, tenant_id, customer_number, customer_type) VALUES ('$C', '$T', 'R23-C', 'residential');
INSERT INTO public.service_locations (id, tenant_id, customer_id, location_number, address_line1, city, state, zip) VALUES ('$LOC', '$T', '$C', 'L', '1 Main', 'Austin', 'TX', '78701');
INSERT INTO public.places (id, kind_code, state_code, place_code, name, parent_place_id, effective_from, source_note)
SELECT '$CITY', 'municipality', 'TX', 'TX-R23-CITY', 'Race City 23', s.id, DATE '2000-01-01', 'race-23 fixture' FROM public.places s WHERE s.kind_code = 'state' AND s.state_code = 'TX';
INSERT INTO public.utility_service_profiles (tenant_id, service_type, system_kind, state_code, owner_type, commission_jurisdiction, owning_place_id, effective_from, evidence_reference, evidence_date)
VALUES ('$T', 'gas', 'distribution', 'TX', 'municipal', false, '$CITY', DATE '2000-01-01', 'charter', DATE '2000-01-01');
INSERT INTO public.payment_allocation_tariffs (id, tenant_id, state_code, service_type, system_kind, effective_from, tariff_reference, terms_kind, terms_version, terms_source)
VALUES ('$TAR', '$T', 'TX', 'gas', 'distribution', DATE '2026-01-01', 'City tariff', 'payment_allocation_tariff', 1,
        '{"citation": "City tariff", "within_bill": {"strategy": "charge_type_order", "version": 1, "regulated": ["base_charge", "usage_charge", "surcharge", "minimum_bill_adjustment", "tax", "late_fee", "penalty", "deposit", "adjustment", "credit", "consolidated_summary"], "unregulated": ["adhoc", "misc"]}}');
$(bill "$I1" R23-I1 "$L11" "$L12")
$(bill "$I2" R23-I2 "$L21" "$L22")
$(bill "$I3" R23-I3 "$L31" "$L32")
INSERT INTO public.payments (id, tenant_id, payment_number, customer_id, payment_date, amount, payment_method, effective_date, effective_date_method) VALUES
  $(pay "$P3" R23-P3 70), $(pay "$P4" R23-P4 100), $(pay "$P5" R23-P5 100), $(pay "$P6" R23-P6 50), $(pay "$P7" R23-P7 50), $(pay "$P8" R23-P8 100);
INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reference_type, reference_id) VALUES
  ('$E6', '$T', '$C', DATE '2026-03-05', 'payment', 'P6 posted', -50, 'payment', '$P6'),
  ('$CH', '$T', '$C', DATE '2026-03-01', 'charge', 'a charge', 100, NULL, NULL),
  ('$CHI2', '$T', '$C', DATE '2026-03-01', 'charge', 'I2', 90, 'invoice', '$I2');
INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reference_type, reference_id, reverses_ledger_entry_id) VALUES
  ('$E6N', '$T', '$C', DATE '2026-03-09', 'nsf', 'P6 returned', 50, 'payment', '$P6', '$E6');
COMMIT;
SQL

waiting() {
local n i
for i in 1 2 3 4 5 6 7 8 9 10; do
  n=$(docker exec -i tally-pg psql -U tally -d "$DB" -At -c "SELECT count(*) FROM pg_stat_activity b JOIN pg_stat_activity a ON a.datname = b.datname AND a.application_name = 'race23_a' WHERE b.datname = current_database() AND b.application_name = 'race23_b' AND a.pid = ANY (pg_blocking_pids(b.pid))" 2>/dev/null)
  if [[ "$n" =~ ^[0-9]+$ ]] && [ "$n" -ge 1 ]; then echo 1; return; fi
  sleep 0.15
done
echo 0
}
AS_OP="SET LOCAL app.user_id = '$OP'; SET ROLE tally_app;"
apply() {  # $1 payment, $2 line, $3 bill, $4 amount, $5 date
echo "INSERT INTO public.invoice_applications (tenant_id, customer_id, invoice_id, invoice_line_item_id, payment_id, amount, applied_on, basis, allocation_tariff_id) VALUES ('$T', '$C', '$3', '$2', '$1', $4, DATE '${5:-2026-03-07}', 'oldest_first', '$TAR');"
}
reverse() {  # $1 entry, $2 amount, $3 description
echo "INSERT INTO public.account_ledger (tenant_id, customer_id, transaction_date, transaction_type, description, amount, reverses_ledger_entry_id, reversal_reason) VALUES ('$T', '$C', DATE '2026-03-07', 'adjustment', '$3', $2, '$1', 'race');"
}

two() {  # $1 A's statement, $2 B's statement
"${PSQL[@]}" >"$A_OUT" 2>&1 <<SQL &
SET application_name = 'race23_a';
BEGIN;
$AS_OP
$1
SELECT pg_sleep(3);
COMMIT;
SQL
APID=$!
sleep 1
"${PSQL[@]}" >"$B_OUT" 2>&1 <<SQL &
SET application_name = 'race23_b';
BEGIN;
$AS_OP
$2
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
two "$(apply "$P3" "$L11" "$I1" 60)" "$(apply "$P3" "$L12" "$I1" 40)"
verdict "CR1 two draws on one payment: the second waits on the source, then is refused by its cap" 1 "more than its 70"

# CR2
two "$(apply "$P4" "$L21" "$I2" 40)" "$(apply "$P5" "$L21" "$I2" 30)"
verdict "CR2 two applications to one line: the second waits on the line, then is refused by its cap" 1 "more than the line"

# CR3
two "$(apply "$P6" "$L22" "$I2" 10)" "UPDATE public.payments SET status = 'nsf', nsf_date = DATE '2026-03-09', status_cause_id = '$E6N' WHERE id = '$P6';"
verdict "CR3 a payment applied while it bounces: the move waits on the source, then is refused" 1 "while it is applied to bills"

# CR4: A's transaction begins before B's application and applies after it.
"${PSQL[@]}" >"$A_OUT" 2>&1 <<SQL &
SET application_name = 'race23_a_begun';
BEGIN;
$AS_OP
SELECT now();
DO \$\$ BEGIN
  LOOP
    PERFORM pg_stat_clear_snapshot();
    EXIT WHEN EXISTS (SELECT 1 FROM pg_stat_activity WHERE application_name = 'race23_b_done');
    PERFORM pg_sleep(0.1);
  END LOOP;
END \$\$;
$(apply "$P8" "$L31" "$I3" 10)
COMMIT;
SQL
APID=$!
for _ in $(seq 1 100); do
  [ "$(docker exec -i tally-pg psql -U tally -d "$DB" -At -c "SELECT count(*) FROM pg_stat_activity WHERE application_name = 'race23_a_begun'")" = "1" ] && break; sleep 0.1
done
"${PSQL[@]}" >"$B_OUT" 2>&1 <<SQL
BEGIN;
$AS_OP
$(apply "$P5" "$L31" "$I3" 10)
COMMIT;
SET application_name = 'race23_b_done';
SELECT pg_sleep(2);
SQL
wait $APID; AST=$?
if [ "$AST" -ne 0 ] && grep -q "40001" "$A_OUT" && grep -q "retry it" "$A_OUT"; then echo "PASS CR4 a writer that began before an application now on the line is refused for retry"
else echo "FAIL CR4: A ($AST): $(cat "$A_OUT")"; fail=1; fi
OUT=$("${PSQL[@]}" 2>&1 <<SQL
BEGIN;
$AS_OP
$(apply "$P8" "$L31" "$I3" 10)
COMMIT;
SQL
)
if [ $? -eq 0 ]; then echo "PASS CR4b the retry is admitted"; else echo "FAIL CR4b: $OUT"; fail=1; fi

# CR5
two "$(reverse "$CH" -60 'R1')" "$(reverse "$CH" -50 'R2')"
verdict "CR5 two reversals of one charge: the second waits on the tree, then is refused by the cap" 1 "R-02 cap"

# CR6
two "$(reverse "$CHI2" -30 'I2 less 30')" "SELECT public.void_invoice('$I2', '$OP', 'wrong_rate', NULL, true);"
verdict "CR6 a void while a reversal of its charge is in flight waits on the tree, then reverses what is left" 0
expect "CR6b the void reversed 60, not 90" \
  "$("${PSQL[@]}" -c "SELECT amount FROM public.account_ledger WHERE reverses_ledger_entry_id = '$CHI2' AND transaction_type = 'void_reversal'")" "-60.00"

# CR7
OUT=$("${PSQL[@]}" 2>&1 <<SQL
BEGIN ISOLATION LEVEL REPEATABLE READ;
$AS_OP
$(apply "$P8" "$L32" "$I3" 1)
COMMIT;
SQL
)
if echo "$OUT" | grep -q "25000" && echo "$OUT" | grep -q "READ COMMITTED"; then echo "PASS CR7 an application under REPEATABLE READ is refused"; else echo "FAIL CR7: $OUT"; fail=1; fi
OUT=$("${PSQL[@]}" 2>&1 <<SQL
BEGIN ISOLATION LEVEL REPEATABLE READ;
$AS_OP
$(reverse "$CH" -1 'RR')
COMMIT;
SQL
)
if echo "$OUT" | grep -q "25000" && echo "$OUT" | grep -q "READ COMMITTED"; then echo "PASS CR7b a reversal under REPEATABLE READ is refused"; else echo "FAIL CR7b: $OUT"; fail=1; fi

# CR8
REFUND="INSERT INTO public.payments (tenant_id, payment_number, customer_id, payment_date, amount, payment_method, effective_date, effective_date_method, refunds_payment_id) VALUES ('$T', 'R23-REF', '$C', DATE '2026-03-06', -30, 'refund', DATE '2026-03-06', 'other', '$P7');"
two "$REFUND" "$(apply "$P7" "$L32" "$I3" 30)"
verdict "CR8 a refund in flight and an application of the same payment: the application waits, then is refused" 1 "more than its 50"

exit $fail
