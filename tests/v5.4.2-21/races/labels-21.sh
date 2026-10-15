#!/usr/bin/env bash
# v5.4.2-21: what one transaction cannot show — two sessions.
#   LR1  A writes a customer using label K and holds; B deletes K, waits on
#        A (the SHARE lock), then is refused: K is in use (L3).
#   LR2  A deletes label K2 and holds; B writes a customer using K2, waits
#        for A's commit (L3: no write slips in while the delete is open).
#   LR3  A label delete at REPEATABLE READ is refused (L3).
#   LR4  A retires A-on-B and holds; B adds B-on-A, waits on the schedule
#        header, then passes: it sees the retirement (K5).
#   LR5  After LR4 commits, re-adding A-on-B is refused: B-on-A is live.
#   LR6  A writes customers and holds 8 s; B's label delete gives up after
#        the guard's 5 s lock wait (55P03) instead of stalling every writer.
#   LR7  The same for a location type, against a writer of service_locations.
#   AR1  Two instants (r3, Fable r2 B1): a rider fixed at T0 is retracted and
#        corrected to per unit at T1; a bill drafted at T0 and snapshotted at
#        its creation instant cannot issue it without its figures — the
#        check reads current knowledge, not the snapshot's recorded_at.
# Every race leg checks that session B ITSELF was SEEN BLOCKED BY SESSION A
# (pg_blocking_pids, polled while A holds). Setup failures exit 2.
# Runs against a THROWAWAY clone (it commits rows).
set -uo pipefail
DB="${1:-r21}"
PSQL=(docker exec -i tally-pg psql -U tally -d "$DB" -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -q -At)

T=00000000-0000-4000-8000-0000000021e1
U=00000000-0000-4000-8000-0000000021e2
C=00000000-0000-4000-8000-0000000021e3
S=00000000-0000-4000-8000-0000000021e4
IA=00000000-0000-4000-8000-0000000021e5
IB=00000000-0000-4000-8000-0000000021e6
K1=00000000-0000-4000-8000-0000000021e7
K2=00000000-0000-4000-8000-0000000021e8
K3=00000000-0000-4000-8000-0000000021e9
K4=00000000-0000-4000-8000-0000000021eb
K5=00000000-0000-4000-8000-0000000021ec
C=00000000-0000-4000-8000-0000000021ed
L=00000000-0000-4000-8000-0000000021ee
IF=00000000-0000-4000-8000-0000000021ef
B=00000000-0000-4000-8000-0000000021f0
D1=00000000-0000-4000-8000-0000000021ea
A_OUT=$(mktemp); B_OUT=$(mktemp)
trap 'rm -f "$A_OUT" "$B_OUT"' EXIT
fail=0

"${PSQL[@]}" >/dev/null <<SQL || { echo "SETUP FAIL: fixtures"; exit 2; }
INSERT INTO public.tenants (id, name, slug) VALUES ('$T', 'Race21', 'race21');
INSERT INTO public.users (id, tenant_id, display_name, email, role) VALUES ('$U', '$T', 'Op', 'op@race21.test', 'operator');
INSERT INTO public.rate_schedules (id, tenant_id, code) VALUES ('$S', '$T', 'RS-R21');
INSERT INTO public.rate_items (id, tenant_id, item_code) VALUES ('$IA', '$T', 'R21-A'), ('$IB', '$T', 'R21-B'), ('$IF', '$T', 'R21-FLIP');
INSERT INTO public.custom_location_types (id, tenant_id, type_key, type_label) VALUES ('$K5', '$T', 'r21_unused', 'Unused');
INSERT INTO public.customers (id, tenant_id, customer_number) VALUES ('$C', '$T', 'R21-AR');
INSERT INTO public.service_locations (id, tenant_id, customer_id, location_number, address_line1, city, state, zip) VALUES ('$L', '$T', '$C', 'R21-L', '1 Main', 'Austin', 'TX', '78701');
INSERT INTO public.custom_field_definitions (id, tenant_id, entity_type, field_key, field_label, field_type) VALUES
  ('$K1', '$T', 'customers', 'k_one', 'One', 'text'),
  ('$K2', '$T', 'customers', 'k_two', 'Two', 'text'),
  ('$K3', '$T', 'customers', 'k_three', 'Three', 'text'),
  ('$K4', '$T', 'customers', 'k_four', 'Four', 'text');
INSERT INTO public.rate_item_dependencies (id, tenant_id, rate_schedule_id, dependent_rate_item_id, base_rate_item_id) VALUES ('$D1', '$T', '$S', '$IA', '$IB');
SQL

waiting() {
local n i
for i in 1 2 3 4 5 6 7 8 9 10; do
  n=$(docker exec -i tally-pg psql -U tally -d "$DB" -At -c "SELECT count(*) FROM pg_stat_activity b JOIN pg_stat_activity a ON a.datname = b.datname AND a.application_name = 'race21_a' WHERE b.datname = current_database() AND b.application_name = 'race21_b' AND a.pid = ANY (pg_blocking_pids(b.pid))" 2>/dev/null)
  if [[ "$n" =~ ^[0-9]+$ ]] && [ "$n" -ge 1 ]; then echo 1; return; fi
  sleep 0.15
done
echo 0
}
APP="SET LOCAL app.user_id = '$U'; SET ROLE tally_app;"

two() {  # $1 A's statement, $2 B's statement
"${PSQL[@]}" >"$A_OUT" 2>&1 <<SQL &
SET application_name = 'race21_a';
BEGIN;
$APP
$1
SELECT pg_sleep(3);
COMMIT;
SQL
APID=$!
sleep 1
"${PSQL[@]}" >"$B_OUT" 2>&1 <<SQL &
SET application_name = 'race21_b';
BEGIN;
$APP
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

two "INSERT INTO public.customers (tenant_id, customer_number, metadata) VALUES ('$T', 'R21-C1', '{\"k_one\": 1}');" \
    "DELETE FROM public.custom_field_definitions WHERE id = '$K1';"
verdict "LR1 a label deleted while a writer using it is open: waits, then is refused" 1 "is in use"

two "DELETE FROM public.custom_field_definitions WHERE id = '$K2';" \
    "INSERT INTO public.customers (tenant_id, customer_number, metadata) VALUES ('$T', 'R21-C2', '{\"k_two\": 1}');"
verdict "LR2 a write while a label delete is open waits for its commit" 0
# By design (a deletion-time check, not referential integrity): the write
# landed after the delete, and its key now has no definition.
N=$("${PSQL[@]}" -c "SELECT count(*) FROM public.customers WHERE metadata ? 'k_two'")/$("${PSQL[@]}" -c "SELECT count(*) FROM public.custom_field_definitions WHERE id = '$K2'")
if [ "$N" = "1/0" ]; then echo "PASS LR2b the late write keeps a key whose label is gone (the stated scope)"; else echo "FAIL LR2b: customers/labels = $N"; fail=1; fi

OUT=$("${PSQL[@]}" 2>&1 <<SQL
BEGIN ISOLATION LEVEL REPEATABLE READ;
$APP
DELETE FROM public.custom_field_definitions WHERE id = '$K3';
COMMIT;
SQL
)
if echo "$OUT" | grep -q "25000" && echo "$OUT" | grep -q "READ COMMITTED"; then echo "PASS LR3 a label delete at REPEATABLE READ"
else echo "FAIL LR3: $OUT"; fail=1; fi

two "UPDATE public.rate_item_dependencies SET retired_reason = 'race-21 LR4' WHERE id = '$D1';" \
    "INSERT INTO public.rate_item_dependencies (tenant_id, rate_schedule_id, dependent_rate_item_id, base_rate_item_id) VALUES ('$T', '$S', '$IB', '$IA');"
verdict "LR4 B on A while A on B is being retired: waits on the header, then passes" 0

OUT=$("${PSQL[@]}" 2>&1 <<SQL
BEGIN;
$APP
INSERT INTO public.rate_item_dependencies (tenant_id, rate_schedule_id, dependent_rate_item_id, base_rate_item_id) VALUES ('$T', '$S', '$IA', '$IB');
COMMIT;
SQL
)
if echo "$OUT" | grep -q "closes a cycle"; then echo "PASS LR5 A on B re-added while B on A is live: refused"
else echo "FAIL LR5: $OUT"; fail=1; fi

# LR6: A holds a customers write longer than the guard waits.
"${PSQL[@]}" >"$A_OUT" 2>&1 <<SQL &
SET application_name = 'race21_a';
BEGIN;
$APP
INSERT INTO public.customers (tenant_id, customer_number) VALUES ('$T', 'R21-C6');
SELECT pg_sleep(8);
COMMIT;
SQL
APID=$!
sleep 1
T0=$(date +%s)
OUT=$("${PSQL[@]}" 2>&1 <<SQL
SET application_name = 'race21_b';
BEGIN;
$APP
DELETE FROM public.custom_field_definitions WHERE id = '$K4';
COMMIT;
SQL
)
EL=$(( $(date +%s) - T0 ))
wait $APID
if echo "$OUT" | grep -q "55P03" && [ "$EL" -ge 4 ] && [ "$EL" -le 7 ]; then echo "PASS LR6 a label delete gives up after its lock wait (${EL}s)"
else echo "FAIL LR6: after ${EL}s: $OUT"; fail=1; fi

# LR7: the location-type branch.
"${PSQL[@]}" >"$A_OUT" 2>&1 <<SQL &
SET application_name = 'race21_a';
BEGIN;
$APP
INSERT INTO public.service_locations (tenant_id, customer_id, location_number, address_line1, city, state, zip) VALUES ('$T', '$C', 'R21-L7', '7 Main', 'Austin', 'TX', '78701');
SELECT pg_sleep(8);
COMMIT;
SQL
APID=$!
sleep 1
T0=$(date +%s)
OUT=$("${PSQL[@]}" 2>&1 <<SQL
SET application_name = 'race21_b';
BEGIN;
$APP
DELETE FROM public.custom_location_types WHERE id = '$K5';
COMMIT;
SQL
)
EL=$(( $(date +%s) - T0 ))
wait $APID
if echo "$OUT" | grep -q "55P03" && [ "$EL" -ge 4 ] && [ "$EL" -le 7 ]; then echo "PASS LR7 a location-type delete gives up after its lock wait (${EL}s)"
else echo "FAIL LR7: after ${EL}s: $OUT"; fail=1; fi

# AR1: T0 — the rider is fixed; a bill is drafted with a rider line and no figures.
"${PSQL[@]}" >/dev/null <<SQL || { echo "FAIL AR1: setup T0"; fail=1; }
BEGIN;
$APP
SELECT public.assert_reference_version('rate_items', '$IF', 1);
INSERT INTO public.rate_item_versions (tenant_id, rate_item_id, item_name, service_type, calculation_type, regulatory_class, effective_date, change_type)
  VALUES ('$T', '$IF', 'fixed', 'gas', 'fixed_monthly', 'regulated', DATE '2026-01-01', 'initial');
INSERT INTO public.invoices (id, tenant_id, invoice_number, customer_id, location_id, invoice_date, billing_period, period_start, period_end, due_date, amount_due)
  VALUES ('$B', '$T', 'R21-AR1', '$C', '$L', DATE '2026-02-01', '2026-01', DATE '2026-01-01', DATE '2026-01-31', DATE '2026-02-20', 10);
INSERT INTO public.invoice_line_items (tenant_id, invoice_id, service_type, charge_type, description, amount, rate_item_id)
  VALUES ('$T', '$B', 'gas', 'surcharge', 'rider', 10, '$IF');
COMMIT;
SQL
sleep 1.2
# T1 — the classification is retracted and corrected to per unit.
"${PSQL[@]}" >/dev/null <<SQL || { echo "FAIL AR1: setup T1"; fail=1; }
BEGIN;
$APP
SELECT public.assert_reference_version('rate_items', '$IF', 2);
UPDATE public.rate_item_versions SET recorded_until = now(), closed_type = 'retracted', closed_reason = 'race-21 AR1: misclassified'
 WHERE rate_item_id = '$IF' AND recorded_until IS NULL;
INSERT INTO public.rate_item_versions (tenant_id, rate_item_id, item_name, service_type, calculation_type, regulatory_class, effective_date, change_type, change_reason)
  VALUES ('$T', '$IF', 'per unit', 'gas', 'per_unit_usage', 'regulated', DATE '2026-01-01', 'correction', 'race-21 AR1: misclassified');
COMMIT;
SQL
# Snapshot at the bill's creation instant (admissible), then issue with every deferred check.
OUT=$("${PSQL[@]}" 2>&1 <<SQL
BEGIN;
$APP
INSERT INTO public.invoice_calculation_snapshots (tenant_id, invoice_id, billing_run_id, valid_at, recorded_at, snapshot_schema_version, formula_version, rate_inputs, gas_factors, wna_inputs, tax_inputs, read_inputs, customer_inputs, period_inputs, line_items)
SELECT i.tenant_id, i.id, NULL, i.period_end, i.created_at, 'v1', 'race21',
  '{"rate_schedule_id":null,"rate_schedule_version_id":null,"rate_schedule_code":null,"customer_type":null,"partial_period_policy":null,"items":[]}',
  '{"pga_factor":null,"btu_factor":null,"pressure_factor":null,"temperature_factor":null,"meter_multiplier":null,"factor_stack_intermediates":{}}',
  '{"applied":false}', '{"jurisdictions":[],"exemptions":[],"franchise_fees":[]}', '{"reads":[]}',
  jsonb_build_object('customer_id', i.customer_id, 'customer_class', null, 'location_id', i.location_id, 'premise_zones', '{}'::jsonb),
  jsonb_build_object('period_start', i.period_start, 'period_end', i.period_end, 'days_in_period', i.period_end - i.period_start + 1, 'proration_policy', null),
  (SELECT jsonb_agg(jsonb_build_object('invoice_line_item_id', l.id, 'charge_type', l.charge_type, 'amount', l.amount)) FROM public.invoice_line_items l WHERE l.invoice_id = i.id)
FROM public.invoices i WHERE i.id = '$B';
SELECT 'snapshot recorded_at is the creation instant: ' || (s.recorded_at = i.created_at) FROM public.invoice_calculation_snapshots s JOIN public.invoices i ON i.id = s.invoice_id WHERE s.invoice_id = '$B';
UPDATE public.invoices SET status = 'pending' WHERE id = '$B';
SET CONSTRAINTS ALL IMMEDIATE;
ROLLBACK;
SQL
)
if echo "$OUT" | grep -q "recorded_at is the creation instant: true" && echo "$OUT" | grep -q "missing usage_quantity"; then
  echo "PASS AR1 a classification retracted after the snapshot's instant still decides the figures"
else echo "FAIL AR1: $OUT"; fail=1; fi

exit $fail
