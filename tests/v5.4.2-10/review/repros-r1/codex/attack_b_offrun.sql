-- ATTACK B: off-run invoice where pricing was computed in an earlier transaction than the
-- invoice draft row itself was inserted. recorded_at (captured at compute time) predates
-- invoices.created_at (stamped at INSERT time) -- is this refused even though it may be a
-- legitimate "price now, materialize the draft later" flow?
BEGIN;
SET CONSTRAINTS ALL IMMEDIATE;
SET LOCAL app.user_id = '10000000-0000-4000-8000-00000000ab01';
SET ROLE tally_app;

-- Off-run prebill invoice, inserted "now"
INSERT INTO public.invoices (id, tenant_id, invoice_number, customer_id, location_id, invoice_type, invoice_date, billing_period, period_start, period_end, due_date, status)
VALUES ('10000000-0000-4000-8000-00000000c301', '10000000-0000-4000-8000-00000000aa01', 'T1-PREBILL', '10000000-0000-4000-8000-00000000ac01', '10000000-0000-4000-8000-00000000ad01', 'prebill', now()::date, '2025-09', '2025-09-01', '2025-09-30', now()::date + 21, 'draft');
INSERT INTO public.invoice_line_items (tenant_id, invoice_id, service_type, charge_type, description, amount)
VALUES ('10000000-0000-4000-8000-00000000aa01', '10000000-0000-4000-8000-00000000c301', 'gas', 'base_charge', 'Deposit', 50.00);

DO $$
DECLARE v_created timestamptz; v_earlier timestamptz;
BEGIN
  SELECT created_at INTO v_created FROM public.invoices WHERE id = '10000000-0000-4000-8000-00000000c301';
  v_earlier := v_created - interval '10 minutes';  -- represents "when the engine actually priced this, in an earlier transaction"
  BEGIN
    INSERT INTO public.invoice_calculation_snapshots
      (tenant_id, invoice_id, billing_run_id, valid_at, recorded_at, snapshot_schema_version, formula_version,
       rate_inputs, gas_factors, wna_inputs, tax_inputs, read_inputs, customer_inputs, period_inputs, line_items)
    VALUES ('10000000-0000-4000-8000-00000000aa01', '10000000-0000-4000-8000-00000000c301', NULL, '2025-09-30', v_earlier, 'v1', 'cdx10',
       '{"rate_schedule_id":null,"rate_schedule_version_id":null,"rate_schedule_code":null,"customer_type":null,"partial_period_policy":null,"items":[]}',
       '{"pga_factor":null,"btu_factor":null,"pressure_factor":null,"temperature_factor":null,"meter_multiplier":null,"factor_stack_intermediates":{}}',
       '{"applied":false}',
       '{"jurisdictions":[],"exemptions":[],"franchise_fees":[]}',
       '{"reads":[]}',
       jsonb_build_object('customer_id', '10000000-0000-4000-8000-00000000ac01'::uuid, 'customer_class', null, 'location_id', '10000000-0000-4000-8000-00000000ad01'::uuid, 'premise_zones', '{}'::jsonb),
       jsonb_build_object('period_start', '2025-09-01'::date, 'period_end', '2025-09-30'::date, 'days_in_period', 30, 'proration_policy', null),
       (SELECT jsonb_build_array(jsonb_build_object('invoice_line_item_id', id, 'charge_type', 'base_charge', 'amount', 50.00)) FROM public.invoice_line_items WHERE invoice_id = '10000000-0000-4000-8000-00000000c301'));
    RAISE NOTICE 'ATTACK B: unexpected success (recorded_at predating created_at was accepted)';
  EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'ATTACK B RESULT: off-run snapshot with recorded_at (pricing time, %) before invoices.created_at (draft-insert time, %) was REFUSED -- a legitimate "price in txn 1, materialize draft in txn 2" flow cannot land its true pricing instant: %', v_earlier, v_created, SQLERRM;
  END;
END $$;

ROLLBACK;
