-- fixtures for the race, committed
INSERT INTO public.billing_runs (id, tenant_id, run_number, billing_period, period_start, period_end, run_type, status, started_at, correction_rate_mode)
VALUES ('10000000-0000-4000-8000-00000000b301', '10000000-0000-4000-8000-00000000aa01', 'CDX-RACE', '2025-08', '2025-08-01', '2025-08-31', 'correction', 'in_progress', now(), 'historical')
ON CONFLICT DO NOTHING;

INSERT INTO public.invoices (id, tenant_id, invoice_number, customer_id, location_id, invoice_type, invoice_date, billing_period, period_start, period_end, due_date, status)
VALUES ('10000000-0000-4000-8000-00000000c401', '10000000-0000-4000-8000-00000000aa01', 'T1-RACE-ORIG', '10000000-0000-4000-8000-00000000ac01', '10000000-0000-4000-8000-00000000ad01', 'regular', '2025-08-01', '2025-08', '2025-08-01', '2025-08-31', '2025-08-21', 'draft')
ON CONFLICT DO NOTHING;
INSERT INTO public.invoice_line_items (tenant_id, invoice_id, service_type, charge_type, description, amount)
SELECT '10000000-0000-4000-8000-00000000aa01', '10000000-0000-4000-8000-00000000c401', 'gas', 'base_charge', 'Customer charge', 12.50
WHERE NOT EXISTS (SELECT 1 FROM public.invoice_line_items WHERE invoice_id = '10000000-0000-4000-8000-00000000c401');

INSERT INTO public.correction_run_targets (id, tenant_id, billing_run_id, voided_invoice_id, meter_id, customer_id, rate_date_mode)
VALUES ('10000000-0000-4000-8000-00000000d401', '10000000-0000-4000-8000-00000000aa01', '10000000-0000-4000-8000-00000000b301', '10000000-0000-4000-8000-00000000c401', '10000000-0000-4000-8000-00000000ae01', '10000000-0000-4000-8000-00000000ac01', 'historical')
ON CONFLICT DO NOTHING;

INSERT INTO public.invoices (id, tenant_id, invoice_number, billing_run_id, customer_id, location_id, invoice_type, replaces_invoice_id, invoice_date, billing_period, period_start, period_end, due_date, status)
VALUES ('10000000-0000-4000-8000-00000000c402', '10000000-0000-4000-8000-00000000aa01', 'T1-RACE-CORR', '10000000-0000-4000-8000-00000000b301', '10000000-0000-4000-8000-00000000ac01', '10000000-0000-4000-8000-00000000ad01', 'correction', '10000000-0000-4000-8000-00000000c401', '2025-08-01', '2025-08', '2025-08-01', '2025-08-31', '2025-08-21', 'draft')
ON CONFLICT DO NOTHING;
INSERT INTO public.invoice_line_items (tenant_id, invoice_id, service_type, charge_type, description, amount)
SELECT '10000000-0000-4000-8000-00000000aa01', '10000000-0000-4000-8000-00000000c402', 'gas', 'base_charge', 'Customer charge', 12.50
WHERE NOT EXISTS (SELECT 1 FROM public.invoice_line_items WHERE invoice_id = '10000000-0000-4000-8000-00000000c402');
