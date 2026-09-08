BEGIN;
SET CONSTRAINTS ALL IMMEDIATE;
SET LOCAL app.user_id = '10000000-0000-4000-8000-00000000ab01';
SET ROLE tally_app;

INSERT INTO public.invoices (id, tenant_id, invoice_number, customer_id, location_id, invoice_type, invoice_date, billing_period, period_start, period_end, due_date, status)
VALUES ('10000000-0000-4000-8000-00000000ea01', '10000000-0000-4000-8000-00000000aa01', 'A-R5', '10000000-0000-4000-8000-00000000ac01', '10000000-0000-4000-8000-00000000ad01', 'regular', '2025-08-01', '2025-08', '2025-08-01', '2025-08-31', '2025-08-21', 'draft');

-- Item 1: cross-tenant credit_memo, as T2, should now fail at the FK itself.
RESET ROLE;
SET LOCAL app.user_id = '10000000-0000-4000-8000-00000000ab02';
SET ROLE tally_app;
DO $$
BEGIN
  INSERT INTO public.invoices (id, tenant_id, invoice_number, customer_id, location_id, invoice_type, replaces_invoice_id, invoice_date, billing_period, period_start, period_end, due_date, status)
  VALUES ('10000000-0000-4000-8000-00000000eb01', '10000000-0000-4000-8000-00000000aa02', 'T2-CM-R5', '10000000-0000-4000-8000-00000000ac02', '10000000-0000-4000-8000-00000000ad02', 'credit_memo', '10000000-0000-4000-8000-00000000ea01', '2025-08-01', '2025-08', '2025-08-01', '2025-08-31', '2025-08-21', 'draft');
  RAISE NOTICE 'R5 XTENANT: cross-tenant credit_memo INSERT succeeded (gap NOT closed)';
EXCEPTION WHEN foreign_key_violation THEN
  RAISE NOTICE 'R5 XTENANT RESULT: correctly refused at the FK -- %', SQLERRM;
END $$;

-- Item 2: final / prebill / consolidated carrying replaces_invoice_id should now be refused.
RESET ROLE;
SET LOCAL app.user_id = '10000000-0000-4000-8000-00000000ab01';
SET ROLE tally_app;
DO $$
BEGIN
  INSERT INTO public.invoices (id, tenant_id, invoice_number, customer_id, location_id, invoice_type, replaces_invoice_id, invoice_date, billing_period, period_start, period_end, due_date, status)
  VALUES ('10000000-0000-4000-8000-00000000ec01', '10000000-0000-4000-8000-00000000aa01', 'FINAL-R5', '10000000-0000-4000-8000-00000000ac01', '10000000-0000-4000-8000-00000000ad01', 'final', '10000000-0000-4000-8000-00000000ea01', '2025-08-01', '2025-08', '2025-08-01', '2025-08-31', '2025-08-21', 'draft');
  INSERT INTO public.invoice_line_items (tenant_id, invoice_id, service_type, charge_type, description, amount)
  VALUES ('10000000-0000-4000-8000-00000000aa01', '10000000-0000-4000-8000-00000000ec01', 'gas', 'base_charge', 'x', 1.00);
  PERFORM 1;
  INSERT INTO public.invoice_calculation_snapshots
    (tenant_id, invoice_id, billing_run_id, valid_at, recorded_at, snapshot_schema_version, formula_version,
     rate_inputs, gas_factors, wna_inputs, tax_inputs, read_inputs, customer_inputs, period_inputs, line_items)
  VALUES ('10000000-0000-4000-8000-00000000aa01', '10000000-0000-4000-8000-00000000ec01', NULL, '2025-08-31', now(), 'v1', 'cdx10r5',
     '{"rate_schedule_id":null,"rate_schedule_version_id":null,"rate_schedule_code":null,"customer_type":null,"partial_period_policy":null,"items":[]}',
     '{"pga_factor":null,"btu_factor":null,"pressure_factor":null,"temperature_factor":null,"meter_multiplier":null,"factor_stack_intermediates":{}}',
     '{"applied":false}', '{"jurisdictions":[],"exemptions":[],"franchise_fees":[]}', '{"reads":[]}',
     jsonb_build_object('customer_id', '10000000-0000-4000-8000-00000000ac01'::uuid, 'customer_class', null, 'location_id', '10000000-0000-4000-8000-00000000ad01'::uuid, 'premise_zones', '{}'::jsonb),
     jsonb_build_object('period_start', '2025-08-01'::date, 'period_end', '2025-08-31'::date, 'days_in_period', 31, 'proration_policy', null),
     (SELECT jsonb_build_array(jsonb_build_object('invoice_line_item_id', id, 'charge_type', 'base_charge', 'amount', 1.00)) FROM public.invoice_line_items WHERE invoice_id = '10000000-0000-4000-8000-00000000ec01'));
  RAISE NOTICE 'R5 FINAL: snapshot for final-type carrying replaces_invoice_id SUCCEEDED (gap)';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'R5 FINAL RESULT: correctly refused -- %', SQLERRM;
END $$;

ROLLBACK;
