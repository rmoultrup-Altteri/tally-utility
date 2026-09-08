BEGIN;
SET LOCAL app.user_id = '10000000-0000-4000-8000-00000000ab01';
SET ROLE tally_app;

INSERT INTO public.billing_runs (id, tenant_id, run_number, billing_period, period_start, period_end, run_type, status, started_at, correction_rate_mode)
VALUES ('10000000-0000-4000-8000-00000000b701', '10000000-0000-4000-8000-00000000aa01', 'CDX-R2-RACE', '2025-08', '2025-08-01', '2025-08-31', 'correction', 'in_progress', now(), 'historical')
ON CONFLICT DO NOTHING;

INSERT INTO public.invoices (id, tenant_id, invoice_number, customer_id, location_id, invoice_type, invoice_date, billing_period, period_start, period_end, due_date, status)
VALUES ('10000000-0000-4000-8000-00000000c701', '10000000-0000-4000-8000-00000000aa01', 'T1-R2-RACE-ORIG', '10000000-0000-4000-8000-00000000ac01', '10000000-0000-4000-8000-00000000ad01', 'regular', '2025-08-01', '2025-08', '2025-08-01', '2025-08-31', '2025-08-21', 'draft')
ON CONFLICT DO NOTHING;
INSERT INTO public.invoice_line_items (tenant_id, invoice_id, service_type, charge_type, description, amount)
SELECT '10000000-0000-4000-8000-00000000aa01', '10000000-0000-4000-8000-00000000c701', 'gas', 'base_charge', 'Customer charge', 12.50
WHERE NOT EXISTS (SELECT 1 FROM public.invoice_line_items WHERE invoice_id = '10000000-0000-4000-8000-00000000c701');

INSERT INTO public.invoice_calculation_snapshots
  (tenant_id, invoice_id, billing_run_id, valid_at, recorded_at, snapshot_schema_version, formula_version,
   rate_inputs, gas_factors, wna_inputs, tax_inputs, read_inputs, customer_inputs, period_inputs, line_items)
SELECT '10000000-0000-4000-8000-00000000aa01', '10000000-0000-4000-8000-00000000c701', NULL, '2025-08-31', now(), 'v1', 'cdx10r2',
   '{"rate_schedule_id":null,"rate_schedule_version_id":null,"rate_schedule_code":null,"customer_type":null,"partial_period_policy":null,"items":[]}',
   '{"pga_factor":null,"btu_factor":null,"pressure_factor":null,"temperature_factor":null,"meter_multiplier":null,"factor_stack_intermediates":{}}',
   '{"applied":false}', '{"jurisdictions":[],"exemptions":[],"franchise_fees":[]}', '{"reads":[]}',
   jsonb_build_object('customer_id', '10000000-0000-4000-8000-00000000ac01'::uuid, 'customer_class', null, 'location_id', '10000000-0000-4000-8000-00000000ad01'::uuid, 'premise_zones', '{}'::jsonb),
   jsonb_build_object('period_start', '2025-08-01'::date, 'period_end', '2025-08-31'::date, 'days_in_period', 31, 'proration_policy', null),
   (SELECT jsonb_build_array(jsonb_build_object('invoice_line_item_id', id, 'charge_type', 'base_charge', 'amount', 12.50)) FROM public.invoice_line_items WHERE invoice_id = '10000000-0000-4000-8000-00000000c701')
WHERE NOT EXISTS (SELECT 1 FROM public.invoice_calculation_snapshots WHERE invoice_id = '10000000-0000-4000-8000-00000000c701');

UPDATE public.invoices SET status = 'pending' WHERE id = '10000000-0000-4000-8000-00000000c701' AND status = 'draft';

SELECT public.void_invoice('10000000-0000-4000-8000-00000000c701', '10000000-0000-4000-8000-00000000ab01', 'system_error', NULL, true)
WHERE (SELECT status FROM public.invoices WHERE id = '10000000-0000-4000-8000-00000000c701') <> 'void';

INSERT INTO public.correction_run_targets (id, tenant_id, billing_run_id, voided_invoice_id, meter_id, customer_id, rate_date_mode)
VALUES ('10000000-0000-4000-8000-00000000d701', '10000000-0000-4000-8000-00000000aa01', '10000000-0000-4000-8000-00000000b701', '10000000-0000-4000-8000-00000000c701', '10000000-0000-4000-8000-00000000ae01', '10000000-0000-4000-8000-00000000ac01', 'historical')
ON CONFLICT DO NOTHING;

INSERT INTO public.invoices (id, tenant_id, invoice_number, billing_run_id, customer_id, location_id, invoice_type, replaces_invoice_id, invoice_date, billing_period, period_start, period_end, due_date, status)
VALUES ('10000000-0000-4000-8000-00000000c702', '10000000-0000-4000-8000-00000000aa01', 'T1-R2-RACE-CORR', '10000000-0000-4000-8000-00000000b701', '10000000-0000-4000-8000-00000000ac01', '10000000-0000-4000-8000-00000000ad01', 'correction', '10000000-0000-4000-8000-00000000c701', '2025-08-01', '2025-08', '2025-08-01', '2025-08-31', '2025-08-21', 'draft')
ON CONFLICT DO NOTHING;
INSERT INTO public.invoice_line_items (tenant_id, invoice_id, service_type, charge_type, description, amount)
SELECT '10000000-0000-4000-8000-00000000aa01', '10000000-0000-4000-8000-00000000c702', 'gas', 'base_charge', 'Customer charge', 12.50
WHERE NOT EXISTS (SELECT 1 FROM public.invoice_line_items WHERE invoice_id = '10000000-0000-4000-8000-00000000c702');

SELECT status FROM public.invoices WHERE id = '10000000-0000-4000-8000-00000000c701';
COMMIT;
