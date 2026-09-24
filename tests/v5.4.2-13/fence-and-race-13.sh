#!/bin/sh
# ============================================================================
# v5.4.2-13 — checks that need SEPARATE TRANSACTIONS (the battery is one
# transaction, where now() never moves):
#   A  the evidence fence survives re-pointing a case at a fresh copy of its
#      test: a predecessor meter entered AFTER the finding does not
#      corroborate a shorter refund (review round 1, Opus F3 / Fable F4)
#   B  an acquisition recorded after the finding cannot validate a
#      predecessor hold (Opus F3c)
#   C  a correction of the discovering test racing a freeze: whichever
#      commits first, the other is refused (Opus F4 / Fable F2), both orders
#   D  the fast meter pulled AFTER its test with a backdated removal (through
#      meters.status) does not excuse the unbilled stretch (round 2, both)
#   E  "lock a case, then record a test on its meter" racing a correction of
#      a test on that meter: both commit, no deadlock (round 2, both)
# Usage: sh tests/v5.4.2-13/fence-and-race-13.sh   (needs the tally-pg container)
# Prints PASS / FAIL lines; drops its database.
# ============================================================================
set -u
DB=fr13x
HERE=$(cd "$(dirname "$0")" && pwd)
PATCH="${PATCH13:-$HERE/../../sql/v5.4.2-13-backbilling-caps.sql}"
X() { docker exec -i tally-pg psql -U tally -d $DB -v ON_ERROR_STOP=1 -qtA "$@"; }
T='00000000-0000-4000-8000-0000000019a1'
U='00000000-0000-4000-8000-0000000019b1'
S="SET app.user_id = '$U'; SET ROLE tally_app;"

docker exec tally-pg psql -U tally -d tally -qtA -c "DROP DATABASE IF EXISTS $DB" >/dev/null 2>&1
docker exec tally-pg psql -U tally -d tally -qtA -c "CREATE DATABASE $DB TEMPLATE tally"
docker cp "$PATCH" tally-pg:/tmp/$DB.sql
docker exec -e PGOPTIONS="-c search_path= -c check_function_bodies=on" tally-pg \
  psql -U tally -d $DB -v ON_ERROR_STOP=1 -q -f /tmp/$DB.sql >/dev/null 2>&1 || { echo "FAIL: patch did not apply"; exit 1; }

# ---- owner fixtures, committed
X <<SQL >/dev/null
INSERT INTO public.tenants (id, name, slug, cutover_date) VALUES ('$T', 'FR Gas', 'fr13', DATE '2026-01-15');
INSERT INTO public.users (id, tenant_id, display_name, email, role) VALUES
  ('$U', '$T', 'Op', 'op@fr13.test', 'operator'),
  ('00000000-0000-4000-8000-0000000019b3', '$T', 'Sup', 'sup@fr13.test', 'tenant_admin');
INSERT INTO public.customers (id, tenant_id, customer_number) VALUES ('00000000-0000-4000-8000-0000000019c1', '$T', 'FR-C1');
INSERT INTO public.service_locations (id, tenant_id, customer_id, location_number, address_line1, city, state, zip) VALUES
  ('00000000-0000-4000-8000-0000000019d1', '$T', '00000000-0000-4000-8000-0000000019c1', 'FR-L1', '1 Elm', 'Austin', 'TX', '78701'),
  ('00000000-0000-4000-8000-0000000019d2', '$T', '00000000-0000-4000-8000-0000000019c1', 'FR-L2', '2 Elm', 'Austin', 'TX', '78702'),
  ('00000000-0000-4000-8000-0000000019d3', '$T', '00000000-0000-4000-8000-0000000019c1', 'FR-L3', '3 Elm', 'Austin', 'TX', '78703'),
  ('00000000-0000-4000-8000-0000000019d4', '$T', '00000000-0000-4000-8000-0000000019c1', 'FR-L4', '4 Elm', 'Austin', 'TX', '78704'),
  ('00000000-0000-4000-8000-0000000019d5', '$T', '00000000-0000-4000-8000-0000000019c1', 'FR-L5', '5 Elm', 'Austin', 'TX', '78705');
-- MF: onboarded 2026-01-20 at L1, no predecessor. MQ: at L2 since 2024.
-- MR: at L3, for the race.
INSERT INTO public.meters (id, tenant_id, meter_number, location_id, service_type, start_date) VALUES
  ('00000000-0000-4000-8000-0000000019e1', '$T', 'MF', '00000000-0000-4000-8000-0000000019d1', 'gas', DATE '2026-01-20'),
  ('00000000-0000-4000-8000-0000000019e2', '$T', 'MQ', '00000000-0000-4000-8000-0000000019d2', 'gas', DATE '2024-01-01'),
  ('00000000-0000-4000-8000-0000000019e3', '$T', 'MR', '00000000-0000-4000-8000-0000000019d3', 'gas', DATE '2024-01-01'),
  ('00000000-0000-4000-8000-0000000019e4', '$T', 'MS', '00000000-0000-4000-8000-0000000019d4', 'gas', DATE '2024-01-01'),
  ('00000000-0000-4000-8000-0000000019e5', '$T', 'MX', '00000000-0000-4000-8000-0000000019d5', 'gas', DATE '2024-01-01');
-- MS: billed by Tally from cutover (01-15) to June — so 2025-12-15..2026-01-14
-- is the unbilled in-window stretch a fast finding must hold.
INSERT INTO public.billing_runs (id, tenant_id, run_number, billing_period, period_start, period_end, run_type, status, started_at) VALUES
  ('00000000-0000-4000-8000-0000000019ff', '$T', 'FR-RUN', '2026-01', '2026-01-15', '2026-06-30', 'regular', 'in_progress', '2025-01-01 09:00-06');
DO \$\$
DECLARE v_id uuid; ps date; pe date;
BEGIN
  FOR ps, pe IN SELECT * FROM (VALUES (DATE '2026-01-15', DATE '2026-01-31'), (DATE '2026-02-01', DATE '2026-02-28'), (DATE '2026-03-01', DATE '2026-03-31'),
                                      (DATE '2026-04-01', DATE '2026-04-30'), (DATE '2026-05-01', DATE '2026-05-31'), (DATE '2026-06-01', DATE '2026-06-30')) v LOOP
    v_id := public.uuid_generate_v4();
    INSERT INTO public.invoices (id, tenant_id, invoice_number, billing_run_id, customer_id, location_id, invoice_type, invoice_date, billing_period, period_start, period_end, due_date, amount_due)
    VALUES (v_id, '$T', 'FR-MS-' || to_char(ps, 'MMDD'), '00000000-0000-4000-8000-0000000019ff', '00000000-0000-4000-8000-0000000019c1', '00000000-0000-4000-8000-0000000019d4', 'regular',
            pe + 1, to_char(pe, 'YYYY-MM'), ps, pe, pe + 21, 50);
    INSERT INTO public.invoice_line_items (tenant_id, invoice_id, service_type, charge_type, description, amount, meter_id, usage_quantity)
    VALUES ('$T', v_id, 'gas', 'usage_charge', 'Gas', 50, '00000000-0000-4000-8000-0000000019e4', 100);
    INSERT INTO public.invoice_calculation_snapshots
      (tenant_id, invoice_id, billing_run_id, valid_at, recorded_at, snapshot_schema_version, formula_version,
       rate_inputs, gas_factors, wna_inputs, tax_inputs, read_inputs, customer_inputs, period_inputs, line_items)
    SELECT '$T', v_id, '00000000-0000-4000-8000-0000000019ff', pe, now(), 'v1', 'fr13',
       '{"rate_schedule_id":null,"rate_schedule_version_id":null,"rate_schedule_code":null,"customer_type":null,"partial_period_policy":null,"items":[]}',
       '{"pga_factor":null,"btu_factor":null,"pressure_factor":null,"temperature_factor":null,"meter_multiplier":null,"factor_stack_intermediates":{}}',
       '{"applied":false}', '{"jurisdictions":[],"exemptions":[],"franchise_fees":[]}', '{"reads":[]}',
       jsonb_build_object('customer_id', '00000000-0000-4000-8000-0000000019c1', 'customer_class', null, 'location_id', '00000000-0000-4000-8000-0000000019d4', 'premise_zones', '{}'::jsonb),
       jsonb_build_object('period_start', ps, 'period_end', pe, 'days_in_period', pe - ps + 1, 'proration_policy', null),
       (SELECT jsonb_agg(jsonb_build_object('invoice_line_item_id', l.id, 'charge_type', l.charge_type, 'amount', l.amount)) FROM public.invoice_line_items l WHERE l.invoice_id = v_id);
    SET LOCAL session_replication_role = replica;
    UPDATE public.invoices SET status = 'sent', first_issued_at = now() WHERE id = v_id;
    SET LOCAL session_replication_role = origin;
  END LOOP;
END \$\$;
SELECT public.seed_backbilling_cap_defaults('$T');
SQL

rec() {  # rec <meter> <date> <meter_volume> [supersedes]
  SUP=${4:-}
  if [ -n "$SUP" ]; then SUPV="'$SUP'"; RS="'fr correction'"; else SUPV=NULL; RS=NULL; fi
  X -c "$S INSERT INTO public.meter_tests (tenant_id, meter_id, test_date, test_kind, record_basis, performed_by_name, test_equipment, meter_serial_at_test, multiplier_at_test, load_results, supersedes_test_id, supersede_reason)
        VALUES ('$T', '$1', DATE '$2', 'periodic', 'recorded', 'A. Tester', 'prover', 'SN-X', 1.0,
                jsonb_build_array(jsonb_build_object('load_point','check','standard_volume',100,'meter_volume',$3)), $SUPV, $RS) RETURNING id" | head -1
}

# ======================================================================== A
TA=$(rec 00000000-0000-4000-8000-0000000019e1 2026-06-15 103)
X -c "$S INSERT INTO public.meter_correction_cases (id, tenant_id, meter_id, cause, discovering_test_id) VALUES ('00000000-0000-4000-8000-0000000019f1', '$T', '00000000-0000-4000-8000-0000000019e1', 'meter_error', '$TA')" >/dev/null
sleep 1
# after the finding: a phantom predecessor meter at L1, installed 2020, and later "removed" 2026-01-20
X -c "$S INSERT INTO public.meters (id, tenant_id, meter_number, location_id, service_type, start_date) VALUES ('00000000-0000-4000-8000-0000000019e9', '$T', 'PHANTOM', '00000000-0000-4000-8000-0000000019d1', 'gas', DATE '2020-01-01')" >/dev/null
X -c "$S UPDATE public.meter_deployments SET removal_date = DATE '2026-01-20', removal_reason = 'upgrade_size' WHERE meter_id = '00000000-0000-4000-8000-0000000019e9'" >/dev/null
sleep 1
# re-point the case at a fresh, identical copy of its test
TA2=$(rec 00000000-0000-4000-8000-0000000019e1 2026-06-15 103 "$TA")
X -c "$S UPDATE public.meter_correction_cases SET discovering_test_id = '$TA2' WHERE id = '00000000-0000-4000-8000-0000000019f1'" >/dev/null
OUT=$(X -c "$S INSERT INTO public.meter_correction_evaluations (tenant_id, case_id, submitted_amounts) VALUES ('$T', '00000000-0000-4000-8000-0000000019f1', '{}'::jsonb) RETURNING window_start || ' ' || (inputs ->> 'deployment_corroborated')" | head -1)
if [ "$OUT" = "2025-12-15 false" ]; then
  echo "PASS A: re-pointed at a fresh copy of its test, the case still ignores a predecessor meter entered after the finding (window 2025-12-15, uncorroborated)"
else
  echo "FAIL A: window/corroborated = $OUT"
fi

# ======================================================================== B
TB=$(rec 00000000-0000-4000-8000-0000000019e2 2026-06-15 103)
X -c "$S INSERT INTO public.meter_correction_cases (id, tenant_id, meter_id, cause, discovering_test_id) VALUES ('00000000-0000-4000-8000-0000000019f2', '$T', '00000000-0000-4000-8000-0000000019e2', 'meter_error', '$TB')" >/dev/null
X -c "$S INSERT INTO public.meter_correction_evaluations (tenant_id, case_id, submitted_amounts) VALUES ('$T', '00000000-0000-4000-8000-0000000019f2', '{}'::jsonb)" >/dev/null
sleep 1
X -c "$S INSERT INTO public.service_location_acquisitions (tenant_id, location_id, predecessor_name, acquired_on, evidence_ref) VALUES ('$T', '00000000-0000-4000-8000-0000000019d2', 'Late Co', DATE '2026-03-01', 'entered late')" >/dev/null
ERR=$(X -c "$S INSERT INTO public.meter_correction_holds (tenant_id, case_id, range_start, range_end, hold_code) VALUES ('$T', '00000000-0000-4000-8000-0000000019f2', DATE '2025-12-15', DATE '2026-02-28', 'predecessor_records_unavailable')" 2>&1)
case "$ERR" in
  *"none is recorded"*) echo "PASS B: an acquisition recorded after the finding does not validate a predecessor hold" ;;
  *) echo "FAIL B: $ERR" ;;
esac

# ======================================================================== C
race() {  # race <label> <first: freeze|supersede>
  # a SLOW finding dated after the transitional period: no under-reach check
  # and no R-36 gate, so the freeze genuinely succeeds when it goes first
  TC=$(rec 00000000-0000-4000-8000-0000000019e3 2026-08-20 97)
  CASE=$(X -c "$S INSERT INTO public.meter_correction_cases (tenant_id, meter_id, cause, discovering_test_id) VALUES ('$T', '00000000-0000-4000-8000-0000000019e3', 'meter_error', '$TC') RETURNING id" | head -1)
  X -c "$S INSERT INTO public.meter_correction_evaluations (tenant_id, case_id, submitted_amounts) VALUES ('$T', '$CASE', '{}'::jsonb)" >/dev/null
  PRE=$(X -c "BEGIN; $S UPDATE public.meter_correction_cases SET status = 'frozen' WHERE id = '$CASE'; ROLLBACK;" 2>&1)
  [ -z "$PRE" ] || { echo "FAIL $1: the freeze does not succeed on its own, so the race proves nothing: $PRE"; return; }
  FREEZE="BEGIN; $S UPDATE public.meter_correction_cases SET status = 'frozen' WHERE id = '$CASE'; SELECT pg_sleep(3); COMMIT;"
  SUPER="BEGIN; $S INSERT INTO public.meter_tests (tenant_id, meter_id, test_date, test_kind, record_basis, performed_by_name, test_equipment, meter_serial_at_test, multiplier_at_test, load_results, supersedes_test_id, supersede_reason) VALUES ('$T', '00000000-0000-4000-8000-0000000019e3', DATE '2026-08-20', 'periodic', 'recorded', 'A. Tester', 'prover', 'SN-X', 1.0, jsonb_build_array(jsonb_build_object('load_point','check','standard_volume',100,'meter_volume',100.2)), '$TC', 'race'); SELECT pg_sleep(3); COMMIT;"
  if [ "$2" = freeze ]; then FIRST=$FREEZE; SECOND=$SUPER; else FIRST=$SUPER; SECOND=$FREEZE; fi
  echo "$FIRST"  | docker exec -i tally-pg psql -U tally -d $DB -qtA > /tmp/fr13_first.out 2>&1 &
  sleep 1
  echo "$SECOND" | docker exec -i tally-pg psql -U tally -d $DB -qtA > /tmp/fr13_second.out 2>&1
  wait
  ST=$(X -c "SELECT status || ' ' || EXISTS (SELECT 1 FROM public.meter_tests s WHERE s.supersedes_test_id = '$TC') FROM public.meter_correction_cases WHERE id = '$CASE'")
  # exactly one of the two may have happened
  case "$ST" in
    "frozen false"|"open true") echo "PASS $1: $2 first — final state '$ST' (the second act was refused: $(grep -ho 'ERROR: .*' /tmp/fr13_second.out | head -1 | cut -c1-110))" ;;
    *) echo "FAIL $1: $2 first — final state '$ST' (frozen on a corrected test)" ;;
  esac
  # clean up so the next race starts fresh: unfreeze, correct the test to
  # accurate (a fast case cannot be withdrawn while its test stands), withdraw
  X -c "$S UPDATE public.meter_correction_cases SET status = 'open' WHERE id = '$CASE' AND status = 'frozen'" >/dev/null 2>&1
  X -c "$S INSERT INTO public.meter_tests (tenant_id, meter_id, test_date, test_kind, record_basis, performed_by_name, test_equipment, meter_serial_at_test, multiplier_at_test, load_results, supersedes_test_id, supersede_reason)
        SELECT '$T', '00000000-0000-4000-8000-0000000019e3', DATE '2026-08-20', 'periodic', 'recorded', 'A. Tester', 'prover', 'SN-X', 1.0,
               jsonb_build_array(jsonb_build_object('load_point','check','standard_volume',100,'meter_volume',100.1)), t.id, 'race cleanup'
          FROM public.meter_tests t WHERE t.meter_id = '00000000-0000-4000-8000-0000000019e3' AND t.outcome = 'slow'
           AND NOT EXISTS (SELECT 1 FROM public.meter_tests s WHERE s.supersedes_test_id = t.id)" >/dev/null 2>&1
  X -c "$S UPDATE public.meter_correction_cases SET status = 'withdrawn', withdrawn_reason = 'race done' WHERE id = '$CASE'" >/dev/null 2>&1
}
race C1 freeze
race C2 supersede

# ======================================================================== D
TD=$(rec 00000000-0000-4000-8000-0000000019e4 2026-06-15 103)
X -c "$S INSERT INTO public.meter_correction_cases (id, tenant_id, meter_id, cause, discovering_test_id) VALUES ('00000000-0000-4000-8000-0000000019f4', '$T', '00000000-0000-4000-8000-0000000019e4', 'meter_error', '$TD')" >/dev/null
X -c "$S INSERT INTO public.meter_correction_evaluations (tenant_id, case_id, submitted_amounts)
      SELECT '$T', '00000000-0000-4000-8000-0000000019f4', jsonb_object_agg(b.invoice_id::text, -1)
        FROM public.meter_correction_billed_periods('$T', '00000000-0000-4000-8000-0000000019e4', DATE '2025-12-15', DATE '2026-06-15') b" >/dev/null
sleep 1
# after the finding: the failed meter is pulled, its removal backdated to the window start
X -c "$S UPDATE public.meters SET status = 'inactive', removal_date = DATE '2025-12-15' WHERE id = '00000000-0000-4000-8000-0000000019e4'" >/dev/null
ERR=$(X -c "$S UPDATE public.meter_correction_cases SET status = 'frozen' WHERE id = '00000000-0000-4000-8000-0000000019f4'" 2>&1)
case "$ERR" in
  *"31 in-window day"*) echo "PASS D: pulling the fast meter after its test, removal backdated to the window start, does not excuse the 31 unbilled days — the freeze still refuses" ;;
  *) echo "FAIL D: freeze returned '$ERR'" ;;
esac

# ======================================================================== E
TE=$(rec 00000000-0000-4000-8000-0000000019e5 2026-08-20 97)
X -c "$S INSERT INTO public.meter_correction_cases (id, tenant_id, meter_id, cause, discovering_test_id) VALUES ('00000000-0000-4000-8000-0000000019f5', '$T', '00000000-0000-4000-8000-0000000019e5', 'meter_error', '$TE')" >/dev/null
X -c "$S INSERT INTO public.meter_correction_evaluations (tenant_id, case_id, submitted_amounts) VALUES ('$T', '00000000-0000-4000-8000-0000000019f5', '{}'::jsonb)" >/dev/null
EA="BEGIN; $S INSERT INTO public.meter_correction_evaluations (tenant_id, case_id, submitted_amounts) VALUES ('$T', '00000000-0000-4000-8000-0000000019f5', '{}'::jsonb); SELECT pg_sleep(3);
    INSERT INTO public.meter_tests (tenant_id, meter_id, test_date, test_kind, record_basis, performed_by_name, test_equipment, meter_serial_at_test, multiplier_at_test, load_results)
    VALUES ('$T', '00000000-0000-4000-8000-0000000019e5', DATE '2026-09-01', 'periodic', 'recorded', 'A. Tester', 'prover', 'SN-X', 1.0, jsonb_build_array(jsonb_build_object('load_point','check','standard_volume',100,'meter_volume',100.1))); COMMIT;"
EB="BEGIN; $S INSERT INTO public.meter_tests (tenant_id, meter_id, test_date, test_kind, record_basis, performed_by_name, test_equipment, meter_serial_at_test, multiplier_at_test, load_results, supersedes_test_id, supersede_reason)
    VALUES ('$T', '00000000-0000-4000-8000-0000000019e5', DATE '2026-08-20', 'periodic', 'recorded', 'A. Tester', 'prover', 'SN-X', 1.0, jsonb_build_array(jsonb_build_object('load_point','check','standard_volume',100,'meter_volume',97.5)), '$TE', 'race E'); COMMIT;"
echo "$EA" | docker exec -i tally-pg psql -U tally -d $DB -qtA > /tmp/fr13_ea.out 2>&1 &
sleep 1
echo "$EB" | docker exec -i tally-pg psql -U tally -d $DB -qtA > /tmp/fr13_eb.out 2>&1
wait
if grep -qi "deadlock\|ERROR" /tmp/fr13_ea.out /tmp/fr13_eb.out; then
  echo "FAIL E: $(grep -hi 'ERROR.*' /tmp/fr13_ea.out /tmp/fr13_eb.out | head -1 | cut -c1-120)"
else
  echo "PASS E: a transaction that locks a case and then records a test on its meter, racing a correction of that meter's test, commits — no deadlock (cases are locked before the meter on every path)"
fi

docker exec tally-pg psql -U tally -d tally -qtA -c "DROP DATABASE $DB"
