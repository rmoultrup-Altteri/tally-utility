#!/usr/bin/env bash
# v5.4.2-25: what one transaction cannot show — two writers on one dispute;
# a determination against a resolution; a close against a citation; the
# READ COMMITTED pin.
#   DR1  A writes a dispute's first determination and holds; B writes another
#        first one: waits on the dispute's lock, then is refused (one live; D4m).
#   DR2  A supersedes the live determination and holds; B supersedes the same
#        one: waits, then is refused (D4m).
#   DR3  A resolves the dispute and holds; B writes a determination: waits,
#        then is refused (none after the resolution; D4k).
#   DR4  A writes a determination and holds; B resolves the dispute: waits,
#        then is admitted, and the status is resolved (the other order is fine).
#   DR5  A resolves the dispute and holds; B withdraws it: waits, then is
#        refused (one resolution; D5f).
#   DR6  A writes a determination citing the utility's tariff and holds; B
#        closes the tariff on the day the dispute was received: waits on the
#        citation's lock, then is refused (the close floor; rule_row_cite).
#   DR6b A writes a determination citing the city's law row and holds; B
#        closes that law row on the day the dispute was received: waits on
#        the citation's lock, then is refused (rule_law_row_cite).
#   DR7  A determination and a resolution under REPEATABLE READ are refused
#        (25000: the dispute row is the mutex only at READ COMMITTED).
#   DR8  A resolves the dispute and holds; B records an amount on it: waits,
#        then is refused (nothing after the resolution; D2e).
#   DR9  An amount's lines are written in its own transaction: a line added
#        to an amount committed earlier is refused (D2f).
# Every two() leg checks that session B ITSELF was SEEN BLOCKED BY SESSION A
# (pg_blocking_pids, polled while A holds).
# Setup failures exit 2. Runs against a THROWAWAY clone (it commits rows).
#   usage: disputes-25.sh <db>      (default: r25)
set -uo pipefail
DB="${1:-r25}"
PSQL=(docker exec -i tally-pg psql -U tally -d "$DB" -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -q -At)

T=00000000-0000-4000-8000-0000000025f0
OP=00000000-0000-4000-8000-0000000025f1
C=00000000-0000-4000-8000-0000000025f2
LOC=00000000-0000-4000-8000-0000000025f3
CITY=00000000-0000-4000-8000-0000000025f4
TAR=00000000-0000-4000-8000-0000000025f5
I1=00000000-0000-4000-8000-000000002601
L11=00000000-0000-4000-8000-000000002611
L12=00000000-0000-4000-8000-000000002612
# disputes 31-3a, their amounts 41-4a
D=(x 00000000-0000-4000-8000-000000002631 00000000-0000-4000-8000-000000002632 00000000-0000-4000-8000-000000002633
     00000000-0000-4000-8000-000000002634 00000000-0000-4000-8000-000000002635 00000000-0000-4000-8000-000000002636
     00000000-0000-4000-8000-000000002637 00000000-0000-4000-8000-000000002638 00000000-0000-4000-8000-000000002639
     00000000-0000-4000-8000-00000000263a)
A=(x 00000000-0000-4000-8000-000000002641 00000000-0000-4000-8000-000000002642 00000000-0000-4000-8000-000000002643
     00000000-0000-4000-8000-000000002644 00000000-0000-4000-8000-000000002645 00000000-0000-4000-8000-000000002646
     00000000-0000-4000-8000-000000002647 00000000-0000-4000-8000-000000002648 00000000-0000-4000-8000-000000002649
     00000000-0000-4000-8000-00000000264a)
DET2=00000000-0000-4000-8000-000000002652
A_OUT=$(mktemp); B_OUT=$(mktemp)
trap 'rm -f "$A_OUT" "$B_OUT"' EXIT
fail=0

SNAP_INPUTS="'{\"rate_schedule_id\":null,\"rate_schedule_version_id\":null,\"rate_schedule_code\":null,\"customer_type\":null,\"partial_period_policy\":null,\"items\":[]}', '{\"pga_factor\":null,\"btu_factor\":null,\"pressure_factor\":null,\"temperature_factor\":null,\"meter_multiplier\":null,\"factor_stack_intermediates\":{}}', '{\"applied\":false}', '{\"jurisdictions\":[],\"exemptions\":[],\"franchise_fees\":[]}', '{\"reads\":[]}'"
LAW="(SELECT id FROM public.dispute_rules WHERE state_code = 'TX' AND service_type = 'gas' AND customer_class = 'protected' AND 'municipal' = ANY (owner_types) AND closed_at IS NULL)"
BLOCKS="'{disconnect_order,disconnect_execute,credit_reporting}'"

dispute() {  # $1 n: dispute n on I1, received March 12, with its amount of 40
echo "INSERT INTO public.disputes (id, tenant_id, customer_id, invoice_id, subject, received_on, channel) VALUES ('${D[$1]}', '$T', '$C', '$I1', 'calculation', DATE '2026-03-12', 'written');"
echo "INSERT INTO public.dispute_amounts (id, tenant_id, dispute_id, amount, determined_by, effective_on) VALUES ('${A[$1]}', '$T', '${D[$1]}', 40, 'customer_claim', DATE '2026-03-12');"
}
det() {  # $1 n, $2 sheltered, $3 supersedes (or empty), $4 id (or empty)
local sup="NULL" id="DEFAULT"
[ -n "${3:-}" ] && sup="'$3'"
[ -n "${4:-}" ] && id="'$4'"
echo "INSERT INTO public.dispute_determinations (id, tenant_id, dispute_id, dispute_amount_id, state_code, service_type, system_kind, customer_class, rule_id, tariff_id, outcome, sheltered_amount, must_pay_amount, must_pay_component, shelter_ends_on, blocks, supersedes_id, inputs, inputs_fingerprint, calculated_by) VALUES ($id, '$T', '${D[$1]}', '${A[$1]}', 'TX', 'gas', 'distribution', 'protected', $LAW, '$TAR', 'sheltered', $2, 100, 'm1', NULL, $BLOCKS, $sup, '{}', 'fp-$1-$2', 'race-25');"
}
ev() {  # $1 n, $2 type, $3 outcome (or empty)
local out="NULL"
[ -n "${3:-}" ] && out="'$3'"
echo "INSERT INTO public.dispute_events (tenant_id, dispute_id, event_type, occurred_on, outcome) VALUES ('$T', '${D[$1]}', '$2', DATE '2026-04-10', $out);"
}

"${PSQL[@]}" >/dev/null <<SQL || { echo "SETUP FAIL: fixtures"; exit 2; }
BEGIN;
INSERT INTO public.tenants (id, name, slug) VALUES ('$T', 'Race25', 'race25');
INSERT INTO public.users (id, tenant_id, display_name, email, role) VALUES ('$OP', '$T', 'Op', 'op@race25.test', 'operator');
INSERT INTO public.customers (id, tenant_id, customer_number, customer_type) VALUES ('$C', '$T', 'R25-C', 'residential');
INSERT INTO public.service_locations (id, tenant_id, customer_id, location_number, address_line1, city, state, zip) VALUES ('$LOC', '$T', '$C', 'L', '1 Main', 'Brenham', 'TX', '77833');
INSERT INTO public.places (id, kind_code, state_code, place_code, name, parent_place_id, effective_from, source_note)
SELECT '$CITY', 'municipality', 'TX', 'TX-R25-CITY', 'Race City 25', s.id, DATE '2000-01-01', 'race-25 fixture' FROM public.places s WHERE s.kind_code = 'state' AND s.state_code = 'TX';
INSERT INTO public.utility_service_profiles (tenant_id, service_type, system_kind, state_code, owner_type, commission_jurisdiction, owning_place_id, effective_from, evidence_reference, evidence_date)
VALUES ('$T', 'gas', 'distribution', 'TX', 'municipal', false, '$CITY', DATE '2000-01-01', 'charter', DATE '2000-01-01');
INSERT INTO public.dispute_tariffs (id, tenant_id, state_code, service_type, system_kind, effective_from, tariff_reference, terms_kind, terms_version, terms_source)
VALUES ('$TAR', '$T', 'TX', 'gas', 'distribution', DATE '2026-01-01', 'City tariff', 'dispute_tariff', 1,
        '{"citation": "City tariff", "subjects": {"kind": "any", "excluded": []}, "shelter_earned": {"kind": "any_time"}, "must_pay": {"strategy": "full_bill", "version": 1, "id": "m1"}, "shelter_ends": {"kind": "resolution"}, "stages": [{"id": "s1", "decider": "designated_employee", "file_within": {"kind": "none"}, "decide_within": {"kind": "none"}, "final": true}], "blocks": {"codes": ["disconnect_order", "disconnect_execute", "credit_reporting"]}, "duties": {"codes": ["investigate"]}}');
INSERT INTO public.invoices (id, tenant_id, invoice_number, customer_id, location_id, invoice_date, billing_period, period_start, period_end, due_date, amount_due)
VALUES ('$I1', '$T', 'R25-I1', '$C', '$LOC', DATE '2026-03-01', '2026-02', DATE '2026-02-01', DATE '2026-02-28', DATE '2026-03-20', 100.00);
INSERT INTO public.invoice_line_items (id, tenant_id, invoice_id, line_order, service_type, charge_type, description, amount, rate, regulatory_class) VALUES
  ('$L11', '$T', '$I1', 0, 'gas', 'base_charge', 'Gas service', 60.00, 60.00, 'regulated'),
  ('$L12', '$T', '$I1', 1, 'general', 'misc', 'Add-on', 40.00, NULL, 'unregulated');
INSERT INTO public.invoice_calculation_snapshots
  (tenant_id, invoice_id, valid_at, recorded_at, snapshot_schema_version, formula_version,
   rate_inputs, gas_factors, wna_inputs, tax_inputs, read_inputs, customer_inputs, period_inputs, line_items)
VALUES ('$T', '$I1', DATE '2026-02-28', now(), 'v1', 'race25', $SNAP_INPUTS,
   jsonb_build_object('customer_id', '$C'::uuid, 'customer_class', null, 'location_id', '$LOC'::uuid, 'premise_zones', '{}'::jsonb),
   jsonb_build_object('period_start', DATE '2026-02-01', 'period_end', DATE '2026-02-28', 'days_in_period', 28, 'proration_policy', null),
   (SELECT jsonb_agg(jsonb_build_object('invoice_line_item_id', l.id, 'charge_type', l.charge_type, 'amount', l.amount)) FROM public.invoice_line_items l WHERE l.invoice_id = '$I1'));
UPDATE public.invoices SET status = 'pending' WHERE id = '$I1';
SET LOCAL app.user_id = '$OP';
SET LOCAL ROLE tally_app;
$(for n in 1 2 3 4 5 6 7 8 9 10; do dispute $n; done)
$(det 2 40 '' 00000000-0000-4000-8000-000000002651)
COMMIT;
SQL

waiting() {
local n i
for i in 1 2 3 4 5 6 7 8 9 10; do
  n=$(docker exec -i tally-pg psql -U tally -d "$DB" -At -c "SELECT count(*) FROM pg_stat_activity b JOIN pg_stat_activity a ON a.datname = b.datname AND a.application_name = 'race25_a' WHERE b.datname = current_database() AND b.application_name = 'race25_b' AND a.pid = ANY (pg_blocking_pids(b.pid))" 2>/dev/null)
  if [[ "$n" =~ ^[0-9]+$ ]] && [ "$n" -ge 1 ]; then echo 1; return; fi
  sleep 0.15
done
echo 0
}
AS_OP="SET LOCAL app.user_id = '$OP'; SET ROLE tally_app;"

two() {  # $1 A's statement, $2 B's statement, $3 B's role prefix (default: the operator)
local b_as="${3:-$AS_OP}"
"${PSQL[@]}" >"$A_OUT" 2>&1 <<SQL &
SET application_name = 'race25_a';
BEGIN;
$AS_OP
$1
SELECT pg_sleep(3);
COMMIT;
SQL
APID=$!
sleep 1
"${PSQL[@]}" >"$B_OUT" 2>&1 <<SQL &
SET application_name = 'race25_b';
BEGIN;
$b_as
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

# DR1
two "$(det 1 40)" "$(det 1 30)"
verdict "DR1 two first determinations for one dispute: the second waits on the dispute, then is refused (one live)" 1 "[D4m]"

# DR2
two "$(det 2 30 00000000-0000-4000-8000-000000002651)" "$(det 2 20 00000000-0000-4000-8000-000000002651)"
verdict "DR2 two supersessions of one determination: the second waits, then is refused" 1 "[D4m]"

# DR3
two "$(ev 3 resolved sustained)" "$(det 3 40)"
verdict "DR3 a determination while the dispute is being resolved: it waits, then is refused" 1 "[D4k]"

# DR4
two "$(det 4 40)" "$(ev 4 resolved sustained)"
verdict "DR4 a resolution while a determination is being written: it waits, then is admitted" 0
expect "DR4b … and the dispute is resolved" "$("${PSQL[@]}" -c "SELECT status FROM public.disputes WHERE id = '${D[4]}'")" "resolved"

# DR5
two "$(ev 5 resolved waived)" "$(ev 5 withdrawn)"
verdict "DR5 a withdrawal while the dispute is being resolved: it waits, then is refused (one resolution)" 1 "[D5f]"

# DR6: the close runs as the owner (a tariff closes by its utility; the owner sees every citation).
two "$(det 6 40)" "UPDATE public.dispute_tariffs SET effective_to = DATE '2026-03-12' WHERE id = '$TAR';" "SET LOCAL app.user_id = '$OP';"
verdict "DR6 a close of the tariff while a determination cites it for March 12: the close waits, then is refused" 1 "cannot close on"

# DR6b: the law row's close runs as the owner (the platform closes law).
two "$(det 10 40)" "UPDATE public.dispute_rules SET effective_to = DATE '2026-03-12' WHERE id = $LAW;" "SET LOCAL app.user_id = '$OP';"
verdict "DR6b a close of the law row while a determination cites it for March 12: the close waits, then is refused" 1 "cannot close on"

# DR7
OUT=$("${PSQL[@]}" 2>&1 <<SQL
BEGIN ISOLATION LEVEL REPEATABLE READ;
$AS_OP
$(det 7 40)
COMMIT;
SQL
)
if echo "$OUT" | grep -q "25000"; then echo "PASS DR7 a determination under REPEATABLE READ is refused"; else echo "FAIL DR7: $OUT"; fail=1; fi
OUT=$("${PSQL[@]}" 2>&1 <<SQL
BEGIN ISOLATION LEVEL REPEATABLE READ;
$AS_OP
$(ev 7 withdrawn)
COMMIT;
SQL
)
if echo "$OUT" | grep -q "25000"; then echo "PASS DR7b a resolution under REPEATABLE READ is refused"; else echo "FAIL DR7b: $OUT"; fail=1; fi

# DR8
two "$(ev 8 resolved sustained)" "INSERT INTO public.dispute_amounts (tenant_id, dispute_id, amount, determined_by, effective_on) VALUES ('$T', '${D[8]}', 30, 'agreed', DATE '2026-04-10');"
verdict "DR8 an amount while the dispute is being resolved: it waits, then is refused" 1 "[D2e]"

# DR9 (not a race: two transactions in turn)
OUT=$("${PSQL[@]}" 2>&1 <<SQL
BEGIN;
$AS_OP
INSERT INTO public.dispute_amount_lines (tenant_id, dispute_amount_id, invoice_line_item_id, amount) VALUES ('$T', '${A[9]}', '$L12', 40);
COMMIT;
SQL
)
if echo "$OUT" | grep -qF "[D2f]"; then echo "PASS DR9 a line added to an amount of an earlier transaction is refused"; else echo "FAIL DR9: $OUT"; fail=1; fi

exit $fail
