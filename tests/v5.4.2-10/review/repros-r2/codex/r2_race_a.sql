-- Session A: inserts the correction's snapshot (mutex-UPDATEs the target row), holds briefly.
SET LOCAL app.user_id = '10000000-0000-4000-8000-00000000ab01';
SET ROLE tally_app;
BEGIN;
SET LOCAL app.user_id = '10000000-0000-4000-8000-00000000ab01';
SET ROLE tally_app;

INSERT INTO public.invoice_calculation_snapshots
  (tenant_id, invoice_id, billing_run_id, valid_at, recorded_at, snapshot_schema_version, formula_version,
   rate_inputs, gas_factors, wna_inputs, tax_inputs, read_inputs, customer_inputs, period_inputs, line_items)
VALUES ('10000000-0000-4000-8000-00000000aa01', '10000000-0000-4000-8000-00000000c702', '10000000-0000-4000-8000-00000000b701',
   '2025-08-31', now(), 'v1', 'cdx10r2',
   '{"rate_schedule_id":null,"rate_schedule_version_id":null,"rate_schedule_code":null,"customer_type":null,"partial_period_policy":null,"items":[]}',
   '{"pga_factor":null,"btu_factor":null,"pressure_factor":null,"temperature_factor":null,"meter_multiplier":null,"factor_stack_intermediates":{}}',
   '{"applied":false}', '{"jurisdictions":[],"exemptions":[],"franchise_fees":[]}', '{"reads":[]}',
   jsonb_build_object('customer_id', '10000000-0000-4000-8000-00000000ac01'::uuid, 'customer_class', null, 'location_id', '10000000-0000-4000-8000-00000000ad01'::uuid, 'premise_zones', '{}'::jsonb),
   jsonb_build_object('period_start', '2025-08-01'::date, 'period_end', '2025-08-31'::date, 'days_in_period', 31, 'proration_policy', null),
   (SELECT jsonb_build_array(jsonb_build_object('invoice_line_item_id', id, 'charge_type', 'base_charge', 'amount', 12.50)) FROM public.invoice_line_items WHERE invoice_id = '10000000-0000-4000-8000-00000000c702'));

\echo SESSION_A: snapshot inserted (mutex UPDATE on target row done), holding 6s
SELECT pg_sleep(6);
COMMIT;
\echo SESSION_A: committed
