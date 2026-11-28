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
#   CR8  A cancels a disconnect order and holds; B executes it: waits on the
#        order's row, then is refused (the order is closed; F1b).
#   CR8b A executes a disconnect order and holds; B cancels it: waits, then is
#        refused (an executed order can only be completed; F4d).
#   CR8c (r2, Fable B1, Opus B3) as CR8b with B at REPEATABLE READ: waits,
#        then is refused (25000, F4f) — not admitted on a snapshot that
#        predates the execution.
#   CR8e as CR8c at SERIALIZABLE.
#   CR9  (r3) A records a blocked location-wide order decision and holds; B
#        records an order under an eligible decision for the location's meter:
#        waits on the location's lock, then is refused (A10).
#   CR10, CR10b (r3, Opus r2 B1) the crew arrives under the live execute
#        decision; the core then supersedes it (eligible, CR10; blocked,
#        CR10b), committed; the late sync citing the decision the crew acted
#        under is recorded (judged as of its arrival).
#   CR11 (r3, Opus r2 B2) A executes an order and holds; B transfers the
#        location to another customer: waits on the location's row, then is
#        admitted (the transfer follows the act).
#   CR11b A transfers the location and holds; B executes the order: waits,
#        then is refused (F2g).
# r2: executions arrive at now() under a decision for today, since an
# execution is never dated before its order and decision were recorded (F2f).
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
LOC3=00000000-0000-4000-8000-0000000026f5
LOC4=00000000-0000-4000-8000-0000000026f6
DO3=00000000-0000-4000-8000-0000000026ea
DO4=00000000-0000-4000-8000-0000000026eb
DX3=00000000-0000-4000-8000-0000000026ec
DX4=00000000-0000-4000-8000-0000000026ed
SO3=00000000-0000-4000-8000-0000000026ee
SO4=00000000-0000-4000-8000-0000000026ef
LOC5=00000000-0000-4000-8000-0000000026d1
DO5=00000000-0000-4000-8000-0000000026d2
DX5=00000000-0000-4000-8000-0000000026d3
SO5=00000000-0000-4000-8000-0000000026d4
LOC6=00000000-0000-4000-8000-0000000026d5
MTR6=00000000-0000-4000-8000-0000000026d6
DO6=00000000-0000-4000-8000-0000000026d7
SO6=00000000-0000-4000-8000-0000000026d8
LOC7=00000000-0000-4000-8000-0000000026d9
DO7=00000000-0000-4000-8000-0000000026da
DX7=00000000-0000-4000-8000-0000000026db
SO7=00000000-0000-4000-8000-0000000026dc
LOC8=00000000-0000-4000-8000-0000000026dd
DO8=00000000-0000-4000-8000-0000000026de
DX8=00000000-0000-4000-8000-0000000026df
SO8=00000000-0000-4000-8000-0000000026c1
LOCA=00000000-0000-4000-8000-0000000026c8
DOA=00000000-0000-4000-8000-0000000026c9
DXA=00000000-0000-4000-8000-0000000026ca
SOA=00000000-0000-4000-8000-0000000026cb
LOCB=00000000-0000-4000-8000-0000000026cc
DOB=00000000-0000-4000-8000-0000000026cd
DXB=00000000-0000-4000-8000-0000000026ce
SOB=00000000-0000-4000-8000-0000000026cf
C2=00000000-0000-4000-8000-0000000026c3
LOC9=00000000-0000-4000-8000-0000000026c4
DO9=00000000-0000-4000-8000-0000000026c5
DX9=00000000-0000-4000-8000-0000000026c6
SO9=00000000-0000-4000-8000-0000000026c7
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
execute() {  # $1 order, $2 decision (default DX), $3 serial, $4 location number
echo "INSERT INTO public.service_order_field_visits (tenant_id, service_order_id, arrived_at, captured_meter_serial, captured_location_number, outcome, collections_decision_id, evidence_refs) VALUES ('$T', '$1', now(), '${3:-SN-R}', '${4:-L}', 'executed', '${2:-$DX}', '{photo-1}');"
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
$(dec $DX disconnect_execute NULL "$LOC" "$TODAY" "$TODAY" NULL x)
RESET ROLE;
INSERT INTO public.service_locations (id, tenant_id, customer_id, location_number, address_line1, city, state, zip) VALUES
  ('$LOC3', '$T', '$C', 'L3', '3 Main', 'Brenham', 'TX', '77833'), ('$LOC4', '$T', '$C', 'L4', '4 Main', 'Brenham', 'TX', '77833'),
  ('$LOC5', '$T', '$C', 'L5', '5 Main', 'Brenham', 'TX', '77833'), ('$LOC6', '$T', '$C', 'L6', '6 Main', 'Brenham', 'TX', '77833'),
  ('$LOC7', '$T', '$C', 'L7', '7 Main', 'Brenham', 'TX', '77833'), ('$LOC8', '$T', '$C', 'L8', '8 Main', 'Brenham', 'TX', '77833'),
  ('$LOC9', '$T', '$C', 'L9', '9 Main', 'Brenham', 'TX', '77833'), ('$LOCA', '$T', '$C', 'LA', '10 Main', 'Brenham', 'TX', '77833'),
  ('$LOCB', '$T', '$C', 'LB', '11 Main', 'Brenham', 'TX', '77833');
INSERT INTO public.customers (id, tenant_id, customer_number, customer_type) VALUES ('$C2', '$T', 'R26-C2', 'residential');
INSERT INTO public.meters (tenant_id, meter_number, serial_number, location_id, service_type, start_date) VALUES
  ('$T', 'R26-M3', 'SN-3', '$LOC3', 'gas', DATE '2020-01-01'), ('$T', 'R26-M4', 'SN-4', '$LOC4', 'gas', DATE '2020-01-01'),
  ('$T', 'R26-M5', 'SN-5', '$LOC5', 'gas', DATE '2020-01-01'), ('$T', 'R26-M7', 'SN-7', '$LOC7', 'gas', DATE '2020-01-01'),
  ('$T', 'R26-M8', 'SN-8', '$LOC8', 'gas', DATE '2020-01-01'), ('$T', 'R26-M9', 'SN-9', '$LOC9', 'gas', DATE '2020-01-01'),
  ('$T', 'R26-MA', 'SN-A', '$LOCA', 'gas', DATE '2020-01-01'), ('$T', 'R26-MB', 'SN-B', '$LOCB', 'gas', DATE '2020-01-01');
INSERT INTO public.meters (id, tenant_id, meter_number, serial_number, location_id, service_type, start_date) VALUES
  ('$MTR6', '$T', 'R26-M6', 'SN-6', '$LOC6', 'gas', DATE '2020-01-01');
SET LOCAL ROLE tally_app;
$(dec $DO3 disconnect_order NULL "$LOC3" "$TODAY" "$TODAY + 7" NULL o3)
$(dec $DO4 disconnect_order NULL "$LOC4" "$TODAY" "$TODAY + 7" NULL o4)
$(dec $DO5 disconnect_order NULL "$LOC5" "$TODAY" "$TODAY + 7" NULL o5)
$(dec $DO6 disconnect_order NULL "$LOC6" "$TODAY" "$TODAY + 7" NULL o6)
$(dec $DO7 disconnect_order NULL "$LOC7" "$TODAY" "$TODAY + 7" NULL o7)
$(dec $DO8 disconnect_order NULL "$LOC8" "$TODAY" "$TODAY + 7" NULL o8)
$(dec $DO9 disconnect_order NULL "$LOC9" "$TODAY" "$TODAY + 7" NULL o9)
$(dec $DOA disconnect_order NULL "$LOCA" "$TODAY" "$TODAY + 7" NULL oa)
$(dec $DOB disconnect_order NULL "$LOCB" "$TODAY" "$TODAY + 7" NULL ob)
INSERT INTO public.service_orders (id, tenant_id, order_number, order_type, description, customer_id, location_id, collections_decision_id) VALUES
  ('$SO3', '$T', 'R26-SO3', 'disconnect', 'race', '$C', '$LOC3', '$DO3'), ('$SO4', '$T', 'R26-SO4', 'disconnect', 'race', '$C', '$LOC4', '$DO4'),
  ('$SO5', '$T', 'R26-SO5', 'disconnect', 'race', '$C', '$LOC5', '$DO5'),
  ('$SO7', '$T', 'R26-SO7', 'disconnect', 'race', '$C', '$LOC7', '$DO7'), ('$SO8', '$T', 'R26-SO8', 'disconnect', 'race', '$C', '$LOC8', '$DO8'),
  ('$SO9', '$T', 'R26-SO9', 'disconnect', 'race', '$C', '$LOC9', '$DO9'),
  ('$SOA', '$T', 'R26-SOA', 'disconnect', 'race', '$C', '$LOCA', '$DOA'), ('$SOB', '$T', 'R26-SOB', 'disconnect', 'race', '$C', '$LOCB', '$DOB');
$(dec $DX3 disconnect_execute NULL "$LOC3" "$TODAY" "$TODAY" NULL x3)
$(dec $DX4 disconnect_execute NULL "$LOC4" "$TODAY" "$TODAY" NULL x4)
$(dec $DX5 disconnect_execute NULL "$LOC5" "$TODAY" "$TODAY" NULL x5)
$(dec $DX7 disconnect_execute NULL "$LOC7" "$TODAY" "$TODAY" NULL x7)
$(dec $DX8 disconnect_execute NULL "$LOC8" "$TODAY" "$TODAY" NULL x8)
$(dec $DX9 disconnect_execute NULL "$LOC9" "$TODAY" "$TODAY" NULL x9)
$(dec $DXA disconnect_execute NULL "$LOCA" "$TODAY" "$TODAY" NULL xa)
$(dec $DXB disconnect_execute NULL "$LOCB" "$TODAY" "$TODAY" NULL xb)
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

two() {  # $1 A's statement, $2 B's statement, $3 B's isolation (optional, e.g. "ISOLATION LEVEL REPEATABLE READ")
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
BEGIN ${3:-};
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
# r3 (Codex r2 S2, race-catch-names-its-damage): a FAIL carries its damage —
# B admitted where it must be refused, or refused by a guard (SQLSTATE class
# 23) where it must pass. Anything else (A failed, a timeout, a lost
# connection, a permission error, or the right outcome with no wait seen) is
# BROKEN: not a catch.
local damage="" broken=""
if [ "${AST:-0}" -ne 0 ]; then echo "BROKEN $1: session A itself failed: $(cat "$A_OUT")"; fail=1; return; fi
if [ "$2" = 1 ]; then
  if [ "$BST" -ne 0 ] && echo "$OUT" | grep -qF "$3"; then :
  elif [ "$BST" -eq 0 ]; then damage="B was admitted, not refused with '$3'"
  else broken="B failed for another reason: $OUT"; fi
else
  if [ "$BST" -eq 0 ]; then :
  elif echo "$OUT" | grep -qE 'ERROR:  23[0-9A-Z]{3}'; then damage="B was refused by a guard: $OUT"
  else broken="B failed for another reason: $OUT"; fi
fi
if [ -n "$broken" ]; then echo "BROKEN $1: $broken"; fail=1; return; fi
if [ "${WAITED:-0}" -lt 1 ]; then
  if [ -n "$damage" ]; then echo "FAIL $1: no lock wait, and the damage: $damage"
  else echo "BROKEN $1: B was never seen waiting on a lock (outcome as expected: sequential, inconclusive)"; fi
  fail=1; return
fi
if [ -n "$damage" ]; then echo "FAIL $1: damage: $damage"; fail=1; else echo "PASS $1"; fi
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
if echo "$OUT" | grep -q "25000"; then echo "PASS CR7 a decision under REPEATABLE READ is refused"; elif ! echo "$OUT" | grep -q "ERROR"; then echo "FAIL CR7: damage: the decision was admitted"; fail=1; else echo "BROKEN CR7: $OUT"; fail=1; fi
OUT=$("${PSQL[@]}" 2>&1 <<SQL
BEGIN ISOLATION LEVEL REPEATABLE READ;
$AS_OP
$(dunning "${I[4]}" shutoff_notice_sent $DN4 '2026-04-12 12:00Z')
COMMIT;
SQL
)
if echo "$OUT" | grep -q "25000"; then echo "PASS CR7b an act under REPEATABLE READ is refused"; elif ! echo "$OUT" | grep -q "ERROR"; then echo "FAIL CR7b: damage: the act was admitted"; fail=1; else echo "BROKEN CR7b: $OUT"; fail=1; fi

# CR8
two "UPDATE public.service_orders SET status = 'cancelled', cancellation_reason = 'race' WHERE id = '$SO3';" "$(execute $SO3 $DX3 SN-3 L3)"
verdict "CR8 an execution while the order is being cancelled: it waits on the order, then is refused" 1 "[F1b]"

# CR8b
two "$(execute $SO4 $DX4 SN-4 L4)" "UPDATE public.service_orders SET status = 'cancelled', cancellation_reason = 'race' WHERE id = '$SO4';"
verdict "CR8b a cancellation while the order is being executed: it waits, then is refused" 1 "[F4d]"

# CR8c
two "$(execute $SO5 $DX5 SN-5 L5)" "UPDATE public.service_orders SET status = 'cancelled', cancellation_reason = 'race' WHERE id = '$SO5';" "ISOLATION LEVEL REPEATABLE READ"
verdict "CR8c a cancellation at REPEATABLE READ while the order is being executed: it waits, then is refused (25000)" 1 "[F4f]"
# CR8e
two "$(execute $SOA $DXA SN-A LA)" "UPDATE public.service_orders SET status = 'cancelled', cancellation_reason = 'race' WHERE id = '$SOA';" "ISOLATION LEVEL SERIALIZABLE"
verdict "CR8e a cancellation at SERIALIZABLE while the order is being executed: it waits, then is refused (25000)" 1 "[F4f]"

expect "CR8d … the order stays open with its execution" \
  "$("${PSQL[@]}" -c "SELECT o.status || '/' || count(v.*) FROM public.service_orders o LEFT JOIN public.service_order_field_visits v ON v.service_order_id = o.id AND v.outcome = 'executed' WHERE o.id = '$SO5' GROUP BY o.status")" \
  "open/1"

# CR9
two "INSERT INTO public.collections_decisions (tenant_id, customer_id, act, location_id, evaluation_date, outcome, active_conditions, governing_condition, supersedes_id, inputs, inputs_fingerprint, calculated_by) VALUES ('$T', '$C', 'disconnect_order', '$LOC6', $TODAY, 'blocked', '{medical_hold}', 'medical_hold', '$DO6', '{}', 'o6b', 'race-26');" \
    "INSERT INTO public.collections_decisions (tenant_id, customer_id, act, location_id, meter_id, evaluation_date, outcome, valid_until, inputs, inputs_fingerprint, calculated_by) VALUES ('$T', '$C', 'disconnect_order', '$LOC6', '$MTR6', $TODAY, 'eligible', $TODAY + 7, '{}', 'o6m', 'race-26');
     INSERT INTO public.service_orders (tenant_id, order_number, order_type, description, customer_id, location_id, meter_id, collections_decision_id)
     SELECT '$T', 'R26-SO6M', 'disconnect', 'race', '$C', '$LOC6', '$MTR6', id FROM public.collections_decisions WHERE inputs_fingerprint = 'o6m';"
verdict "CR9 an order under a meter's eligible decision while the location's decision turns blocked: it waits, then is refused" 1 "[A10]"

# CR10, CR10b: three committed transactions, real time between them.
late_sync() {  # $1 label, $2 location, $3 order, $4 execute decision, $5 serial, $6 location number, $7 successor outcome
local at succ
at=$("${PSQL[@]}" -c "SELECT now()")
sleep 1
if [ "$7" = blocked ]; then
  succ="INSERT INTO public.collections_decisions (tenant_id, customer_id, act, location_id, evaluation_date, outcome, active_conditions, governing_condition, supersedes_id, inputs, inputs_fingerprint, calculated_by) VALUES ('$T', '$C', 'disconnect_execute', '$2', $TODAY, 'blocked', '{payment_pending}', 'payment_pending', '$4', '{}', 's$4', 'race-26');"
else
  succ="INSERT INTO public.collections_decisions (tenant_id, customer_id, act, location_id, evaluation_date, outcome, valid_until, supersedes_id, inputs, inputs_fingerprint, calculated_by) VALUES ('$T', '$C', 'disconnect_execute', '$2', $TODAY, 'eligible', $TODAY, '$4', '{}', 's$4', 'race-26');"
fi
OUT=$("${PSQL[@]}" 2>&1 <<SQL
BEGIN;
$AS_OP
$succ
COMMIT;
SQL
)
if echo "$OUT" | grep -q "ERROR"; then echo "BROKEN $1: setup (the successor): $OUT"; fail=1; return; fi
OUT=$("${PSQL[@]}" 2>&1 <<SQL
BEGIN;
$AS_OP
INSERT INTO public.service_order_field_visits (tenant_id, service_order_id, arrived_at, captured_meter_serial, captured_location_number, outcome, collections_decision_id, evidence_refs) VALUES ('$T', '$3', TIMESTAMPTZ '$at', '$5', '$6', 'executed', '$4', '{photo-1}');
COMMIT;
SQL
)
if ! echo "$OUT" | grep -q "ERROR"; then echo "PASS $1";
elif echo "$OUT" | grep -qE 'ERROR:  23[0-9A-Z]{3}'; then echo "FAIL $1: damage: the late sync was refused: $OUT"; fail=1;
else echo "BROKEN $1: $OUT"; fail=1; fi
}
late_sync "CR10 the crew acted under X; the core re-evaluated (eligible) before the sync: the sync citing X is recorded" "$LOC7" "$SO7" "$DX7" SN-7 L7 eligible
late_sync "CR10b … the core blocked it before the sync: the sync citing X is still recorded (the act came first)" "$LOC9" "$SO9" "$DX9" SN-9 L9 blocked

# CR11, CR11b
two "UPDATE public.service_locations SET customer_id = '$C2' WHERE id = '$LOCB';" "$(execute $SOB $DXB SN-B LB)"
verdict "CR11b an execution while the premises are being transferred: it waits, then is refused" 1 "[F2g]"
two "$(execute $SO8 $DX8 SN-8 L8)" "UPDATE public.service_locations SET customer_id = '$C2' WHERE id = '$LOC8';"
verdict "CR11 a transfer while the premises are being disconnected: it waits on the location's row, then is admitted" 0

exit $fail
