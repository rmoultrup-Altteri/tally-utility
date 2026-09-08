-- Confirm "one snapshotted correction per (run, replaced bill)" new guard.
BEGIN;
SET CONSTRAINTS ALL IMMEDIATE;
SET LOCAL app.user_id = '10000000-0000-4000-8000-00000000ab01';
SET ROLE tally_app;

INSERT INTO public.invoices (id, tenant_id, invoice_number, billing_run_id, customer_id, location_id, invoice_type, replaces_invoice_id, invoice_date, billing_period, period_start, period_end, due_date, status)
VALUES ('10000000-0000-4000-8000-00000000c703', '10000000-0000-4000-8000-00000000aa01', 'T1-R2-DUP-CORR', '10000000-0000-4000-8000-00000000b701', '10000000-0000-4000-8000-00000000ac01', '10000000-0000-4000-8000-00000000ad01', 'correction', '10000000-0000-4000-8000-00000000c701', '2025-08-01', '2025-08', '2025-08-01', '2025-08-31', '2025-08-21', 'draft');
INSERT INTO public.invoice_line_items (tenant_id, invoice_id, service_type, charge_type, description, amount)
VALUES ('10000000-0000-4000-8000-00000000aa01', '10000000-0000-4000-8000-00000000c703', 'gas', 'base_charge', 'Customer charge', 12.50);

DO $$
BEGIN
  INSERT INTO public.invoice_calculation_snapshots
    (tenant_id, invoice_id, billing_run_id, valid_at, recorded_at, snapshot_schema_version, formula_version,
     rate_inputs, gas_factors, wna_inputs, tax_inputs, read_inputs, customer_inputs, period_inputs, line_items)
  VALUES ('10000000-0000-4000-8000-00000000aa01', '10000000-0000-4000-8000-00000000c703', '10000000-0000-4000-8000-00000000b701',
     '2025-08-31', now(), 'v1', 'cdx10r2',
     '{"rate_schedule_id":null,"rate_schedule_version_id":null,"rate_schedule_code":null,"customer_type":null,"partial_period_policy":null,"items":[]}',
     '{"pga_factor":null,"btu_factor":null,"pressure_factor":null,"temperature_factor":null,"meter_multiplier":null,"factor_stack_intermediates":{}}',
     '{"applied":false}', '{"jurisdictions":[],"exemptions":[],"franchise_fees":[]}', '{"reads":[]}',
     jsonb_build_object('customer_id', '10000000-0000-4000-8000-00000000ac01'::uuid, 'customer_class', null, 'location_id', '10000000-0000-4000-8000-00000000ad01'::uuid, 'premise_zones', '{}'::jsonb),
     jsonb_build_object('period_start', '2025-08-01'::date, 'period_end', '2025-08-31'::date, 'days_in_period', 31, 'proration_policy', null),
     (SELECT jsonb_build_array(jsonb_build_object('invoice_line_item_id', id, 'charge_type', 'base_charge', 'amount', 12.50)) FROM public.invoice_line_items WHERE invoice_id = '10000000-0000-4000-8000-00000000c703'));
  RAISE NOTICE 'DUP CORRECTION: second snapshotted correction for the SAME (run, replaced bill) ACCEPTED -- guard failed';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'DUP CORRECTION RESULT: correctly refused -- %', SQLERRM;
END $$;
ROLLBACK;
