#!/usr/bin/env bash
# v5.4.2-26: what one transaction cannot show — two writers on one decision
# subject; an act against a concurrent supersession; two acts on one
# decision; two executions under one decision; two stage moves on one bill;
# the READ COMMITTED pin.
#   CR1  A writes the first decision for a subject and holds; B writes another
#        first one: waits on the subject's lock, then is refused (one live; C4a).
#   CR2  A supersedes the live late-fee decision and holds; B charges a late
#        fee citing the decision A supersedes: waits, then is refused (the act
#        sees the newer decision; A4).
#   CR3  A charges a late fee citing the live decision and holds; B supersedes
#        it: waits, then is admitted (an act before a newer decision is fine).
#   CR4  A records a shutoff notice under a decision and holds; B records a
#        second one under it: waits, then is refused (one act per decision).
#   CR5  A executes one disconnect order under an execute decision and holds;
#        B executes another order at the same location under the same
#        decision: waits, then is refused (one act per decision).
#   CR6  A logs a reminder on a bill and holds; B logs a payment plan on the
#        same bill: waits on the bill, then is admitted with the stage A moved
#        to as its previous stage (E2).
#   CR7  A decision and an act under REPEATABLE READ are refused (25000: the
#        subject's lock serializes only at READ COMMITTED).
# Every two() leg checks that session B ITSELF was SEEN BLOCKED BY SESSION A
# (pg_blocking_pids, polled while A holds).
# Setup failures exit 2. Runs against a THROWAWAY clone (it commits rows).
#   usage: collections-26.sh <db>      (default: r26)
set -uo pipefail
DB="${1:-r26}"
PSQL=(docker exec -i tally-pg psql -U tally -d "$DB" -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -q -At)

T=00000000-0000-4000-8000-0000000026f0
OP=00000000-0000-4000-8000-0000000026f1
C=00000000-0000-4000-8000-0000000026f2
LOC=00000000-0000-4000-8000-0000000026f3
MTR=00000000-0000-4000-8000-0000000026f4
I=(x 00000000-0000-4000-8000-000000002691 00000000-0000-4000-8000-000000002692 00000000-0000-4000-8000-000000002693
     00000000-0000-4000-8000-000000002694 00000000-0000-4000-8000-000000002695 00000000-0000-4000-8000-000000002696)
DL2=00000000-0000-4000-8000-0000000026e2
DL3=00000000-0000-4000-8000-0000000026e3
DN4=00000000-0000-4000-8000-0000000026e4
DO1=00000000-0000-4000-8000-0000000026e5
DO2=00000000-0000-4000-8000-0000000026e6
DX=00000000-0000-4000-8000-0000000026e7
SO1=00000000-0000-4000-8000-0000000026e8
SO2=00000000-0000-4000-8000-0000000026e9
A_OUT=$(mktemp); B_OUT=$(mktemp)
trap 'rm -f "$A_OUT" "$B_OUT"' EXIT
fail=0
TODAY="(now() AT TIME ZONE 'UTC')::date"

SNAP_INPUTS="'{\"rate_schedule_id\":null,\"rate_schedule_version_id\":null,\"rate_schedule_code\":null,\"customer_type\":null,\"partial_period_policy\":null,\"items\":[]}', '{\"pga_factor\":null,\"btu_factor\":null,\"pressure_factor\":null,\"temperature_factor\":null,\"meter_multiplier\":null,\"factor_stack_intermediates\":{}}', '{\"applied\":false}', '{\"jurisdictions\":[],\"exemptions\":[],\"franchise_fees\":[]}', '{\"reads\":[]}'"

bill() {  # $1 n: an issued bill of C at LOC
echo "INSERT INTO public.invoices (id, tenant_id, invoice_number, customer_id, location_id, invoice_date, billing_period, period_start, period_end, due_date, amount_due) VALUES ('${I[$1]}', '$T', 'R26-I$1', '$C', '$LOC', DATE '2026-03-01', '2026-02', DATE '2026-02-01', DATE '2026-02-28', DATE '2026-03-20', 60.00);"
echo "INSERT INTO public.invoice_line_items (tenant_id, invoice_id, line_order, service_type, charge_type, description, amount, rate, regulatory_class) VALUES ('$T', '${I[$1]}', 0, 'gas', 'base_charge', 'Gas service', 60.00, 60.00, 'regulated');"
echo "INSERT INTO public.invoice_calculation_snapshots (tenant_id, invoice_id, valid_at, recorded_at, snapshot_schema_version, formula_version, rate_inputs, gas_factors, wna_inputs, tax_inputs, read_inputs, customer_inputs, period_inputs, line_items) VALUES ('$T', '${I[$1]}', DATE '2026-02-28', now(), 'v1', 'race26', $SNAP_INPUTS, jsonb_build_object('customer_id', '$C'::uuid, 'customer_class', null, 'location_id', '$LOC'::uuid, 'premise_zones', '{}'::jsonb), jsonb_build_object('period_start', DATE '2026-02-01', 'period_end', DATE '2026-02-28', 'days_in_period', 28, 'proration_policy', null), (SELECT jsonb_agg(jsonb_build_object('invoice_line_item_id', l.id, 'charge_type', l.charge_type, 'amount', l.amount)) FROM public.invoice_line_items l WHERE l.invoice_id = '${I[$1]}'));"
echo "UPDATE public.invoices SET status = 'pending' WHERE id = '${I[$1]}';"
}
dec() {  # $1 id (or DEFAULT), $2 act, $3 invoice (or NULL), $4 location (or NULL), $5 eval, $6 until, $7 supersedes (or NULL), $8 fingerprint
local id="DEFAULT" inv="NULL" loc="NULL" sup="NULL"
[ "$1" != DEFAULT ] && id="'$1'"
[ "$3" != NULL ] && inv="'$3'"
[ "$4" != NULL ] && loc="'$4'"
[ "$7" != NULL ] && sup="'$7'"
echo "INSERT INTO public.collections_decisions (id, tenant_id, customer_id, act, invoice_id, location_id, evaluation_date, outcome, valid_until, supersedes_id, inputs, inputs_fingerprint, calculated_by) VALUES ($id, '$T', '$C', '$2', $inv, $loc, $5, 'eligible', $6, $sup, '{}', '$8', 'race-26');"
}
latefee() {  # $1 invoice, $2 decision, $3 number
echo "INSERT INTO public.adhoc_charges (tenant_id, charge_number, customer_id, charge_type, description, amount, regulatory_class, effective_date, triggered_by_invoice_id, collections_decision_id) VALUES ('$T', 'R26-$3', '$C', 'late_fee', 'late fee', 5.00, 'regulated', DATE '2026-04-06', '$1', '$2');"
}
dunning() {  # $1 invoice, $2 type, $3 decision (or NULL), $4 date
local d="NULL"
[ "$3" != NULL ] && d="'$3'"
echo "INSERT INTO public.dunning_events (tenant_id, invoice_id, customer_id, event_type, event_date, collections_decision_id) VALUES ('$T', '$1', '$C', '$2', TIMESTAMPTZ '$4', $d);"
}
execute() {  # $1 order
echo "INSERT INTO public.service_order_field_visits (tenant_id, service_order_id, arrived_at, captured_meter_serial, captured_location_number, outcome, collections_decision_id, evidence_refs) VALUES ('$T', '$1', TIMESTAMPTZ '2026-04-10 15:00Z', 'SN-R', 'L', 'executed', '$DX', '{photo-1}');"
}

"${PSQL[@]}" >/dev/null <<SQL || { echo "SETUP FAIL: fixtures"; exit 2; }
BEGIN;
INSERT INTO public.tenants (id, name, slug) VALUES ('$T', 'Race26', 'race26');
INSERT INTO public.users (id, tenant_id, display_name, email, role) VALUES ('$OP', '$T', 'Op', 'op@race26.test', 'operator');
INSERT INTO public.customers (id, tenant_id, customer_number, customer_type) VALUES ('$C', '$T', 'R26-C', 'residential');
INSERT INTO public.service_locations (id, tenant_id, customer_id, location_number, address_line1, city, state, zip) VALUES ('$LOC', '$T', '$C', 'L', '1 Main', 'Brenham', 'TX', '77833');
INSERT INTO public.meters (id, tenant_id, meter_number, serial_number, location_id, service_type, start_date) VALUES ('$MTR', '$T', 'R26-M', 'SN-R', '$LOC', 'gas', DATE '2020-01-01');
$(for n in 1 2 3 4 5 6; do bill $n; done)
SET LOCAL app.user_id = '$OP';
SET LOCAL ROLE tally_app;
$(dec $DL2 late_fee "${I[2]}" NULL "DATE '2026-04-05'" "DATE '2026-04-10'" NULL l2)
$(dec $DL3 late_fee "${I[3]}" NULL "DATE '2026-04-05'" "DATE '2026-04-10'" NULL l3)
$(dec $DN4 notice "${I[4]}" "$LOC" "DATE '2026-04-05'" "DATE '2026-04-20'" NULL n4)
$(dec $DO1 disconnect_order NULL "$LOC" "$TODAY" "$TODAY + 7" NULL o1)
INSERT INTO public.service_orders (id, tenant_id, order_number, order_type, description, customer_id, location_id, collections_decision_id) VALUES ('$SO1', '$T', 'R26-SO1', 'disconnect', 'race', '$C', '$LOC', '$DO1');
$(dec $DO2 disconnect_order NULL "$LOC" "$TODAY" "$TODAY + 7" $DO1 o2)
INSERT INTO public.service_orders (id, tenant_id, order_number, order_type, description, customer_id, location_id, collections_decision_id) VALUES ('$SO2', '$T', 'R26-SO2', 'disconnect', 'race', '$C', '$LOC', '$DO2');
$(dec $DX disconnect_execute NULL "$LOC" "DATE '2026-04-10'" "DATE '2026-04-10'" NULL x)
COMMIT;
SQL

waiting() {
local n i
for i in 1 2 3 4 5 6 7 8 9 10; do
  n=$(docker exec -i tally-pg psql -U tally -d "$DB" -At -c "SELECT pg_stat_clear_snapshot(); SELECT count(*) FROM pg_stat_activity b JOIN pg_stat_activity a ON a.datname = b.datname AND a.application_name = 'race26_a' WHERE b.datname = current_database() AND b.application_name = 'race26_b' AND a.pid = ANY (pg_blocking_pids(b.pid))" 2>/dev/null | tail -1)
  if [[ "$n" =~ ^[0-9]+$ ]] && [ "$n" -ge 1 ]; then echo 1; return; fi
  sleep 0.15
done
echo 0
}
AS_OP="SET LOCAL app.user_id = '$OP'; SET ROLE tally_app;"

two() {  # $1 A's statement, $2 B's statement
"${PSQL[@]}" >"$A_OUT" 2>&1 <<SQL &
SET application_name = 'race26_a';
BEGIN;
$AS_OP
$1
SELECT pg_sleep(3);
COMMIT;
SQL
APID=$!
sleep 1
"${PSQL[@]}" >"$B_OUT" 2>&1 <<SQL &
SET application_name = 'race26_b';
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
  if [ "$BST" -ne 0 ] && echo "$OUT" | grep -qF "$3"; then echo "PASS $1"; else echo "FAIL $1: expected B refused with '$3', got ($BST): $OUT"; fail=1; fi
else
  if [ "$BST" -eq 0 ]; then echo "PASS $1"; else echo "FAIL $1: expected B to pass, got: $OUT"; fail=1; fi
fi
}
expect() {  # $1 label, $2 actual, $3 expected
if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: got [$2], expected [$3]"; fail=1; fi
}

# CR1
two "$(dec DEFAULT late_fee "${I[1]}" NULL "DATE '2026-04-05'" "DATE '2026-04-10'" NULL a)" \
    "$(dec DEFAULT late_fee "${I[1]}" NULL "DATE '2026-04-05'" "DATE '2026-04-10'" NULL b)"
verdict "CR1 two first decisions for one subject: the second waits on the subject, then is refused (one live)" 1 "[C4a]"

# CR2
two "$(dec DEFAULT late_fee "${I[2]}" NULL "DATE '2026-04-06'" "DATE '2026-04-10'" $DL2 l2b)" "$(latefee "${I[2]}" $DL2 cr2)"
verdict "CR2 a late fee citing a decision being superseded: it waits, then is refused (the newer decision is live)" 1 "[A4]"

# CR3
two "$(latefee "${I[3]}" $DL3 cr3)" "$(dec DEFAULT late_fee "${I[3]}" NULL "DATE '2026-04-06'" "DATE '2026-04-10'" $DL3 l3b)"
verdict "CR3 a supersession while an act cites the live decision: it waits, then is admitted" 0

# CR4
two "$(dunning "${I[4]}" shutoff_notice_sent $DN4 '2026-04-10 12:00Z')" "$(dunning "${I[4]}" shutoff_notice_sent $DN4 '2026-04-11 12:00Z')"
verdict "CR4 two shutoff notices under one decision: the second waits, then is refused" 1 "dunning_events_one_per_decision"

# CR5
two "$(execute $SO1)" "$(execute $SO2)"
verdict "CR5 two executions under one execute decision: the second waits, then is refused" 1 "service_order_field_visits_one_per_decision"

# CR6
two "$(dunning "${I[5]}" reminder_sent NULL '2026-04-10 12:00Z')" "$(dunning "${I[5]}" payment_plan_created NULL '2026-04-11 12:00Z')"
verdict "CR6 two events on one bill: the second waits on the bill, then is admitted" 0
expect "CR6b … its previous stage is the one the first moved the bill to, and the bill follows the second" \
  "$("${PSQL[@]}" -c "SELECT (SELECT previous_stage FROM public.dunning_events WHERE invoice_id = '${I[5]}' AND event_type = 'payment_plan_created') || '/' || (SELECT dunning_stage FROM public.invoices WHERE id = '${I[5]}')")" \
  "reminder_sent/payment_plan"

# CR7
OUT=$("${PSQL[@]}" 2>&1 <<SQL
BEGIN ISOLATION LEVEL REPEATABLE READ;
$AS_OP
$(dec DEFAULT late_fee "${I[6]}" NULL "DATE '2026-04-05'" "DATE '2026-04-10'" NULL rr)
COMMIT;
SQL
)
if echo "$OUT" | grep -q "25000"; then echo "PASS CR7 a decision under REPEATABLE READ is refused"; else echo "FAIL CR7: $OUT"; fail=1; fi
OUT=$("${PSQL[@]}" 2>&1 <<SQL
BEGIN ISOLATION LEVEL REPEATABLE READ;
$AS_OP
$(dunning "${I[4]}" shutoff_notice_sent $DN4 '2026-04-12 12:00Z')
COMMIT;
SQL
)
if echo "$OUT" | grep -q "25000"; then echo "PASS CR7b an act under REPEATABLE READ is refused"; else echo "FAIL CR7b: $OUT"; fail=1; fi

exit $fail
