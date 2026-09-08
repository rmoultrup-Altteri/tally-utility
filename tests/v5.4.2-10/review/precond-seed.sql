-- Runs on a PRE-patch clone. Seeds a snapshot the -10 binding would refuse
-- (valid_at != period_end, recorded_at before the run started) and a run
-- carrying snapshots with started_at NULL, so the patch's report NOTICEs fire.
INSERT INTO public.tenants (id, name, slug) VALUES ('00000000-0000-4000-8000-00000000aa09','T1 Gasco','pre10-t1');
INSERT INTO public.users (id, tenant_id, display_name, email, role) VALUES ('00000000-0000-4000-8000-00000000ab09','00000000-0000-4000-8000-00000000aa09','U1','u1@pre10.test','operator');
INSERT INTO public.customers (id, tenant_id, customer_number) VALUES ('00000000-0000-4000-8000-00000000ac09','00000000-0000-4000-8000-00000000aa09','PRE10-C1');
INSERT INTO public.service_locations (id, tenant_id, customer_id, location_number, address_line1, city, state, zip) VALUES ('00000000-0000-4000-8000-00000000ad09','00000000-0000-4000-8000-00000000aa09','00000000-0000-4000-8000-00000000ac09','LOC-1','1 Main','Austin','TX','78701');
INSERT INTO public.billing_runs (id, tenant_id, run_number, billing_period, period_start, period_end, run_type, status) VALUES ('00000000-0000-4000-8000-00000000b109','00000000-0000-4000-8000-00000000aa09','RUN-PRE','2026-03','2026-03-01','2026-03-31','regular','in_progress');
INSERT INTO public.invoices (id, tenant_id, invoice_number, billing_run_id, customer_id, location_id, invoice_date, billing_period, period_start, period_end, due_date)
VALUES ('00000000-0000-4000-8000-00000000c109','00000000-0000-4000-8000-00000000aa09','INV-PRE','00000000-0000-4000-8000-00000000b109','00000000-0000-4000-8000-00000000ac09','00000000-0000-4000-8000-00000000ad09','2026-04-01','2026-03','2026-03-01','2026-03-31','2026-04-22');
INSERT INTO public.invoice_line_items (id, tenant_id, invoice_id, service_type, charge_type, description, amount)
VALUES ('00000000-0000-4000-8000-00000000e109','00000000-0000-4000-8000-00000000aa09','00000000-0000-4000-8000-00000000c109','gas','base_charge','Customer charge',12.50);
INSERT INTO public.invoice_calculation_snapshots (tenant_id, invoice_id, billing_run_id, valid_at, recorded_at, snapshot_schema_version, formula_version, rate_inputs, gas_factors, wna_inputs, tax_inputs, read_inputs, customer_inputs, period_inputs, line_items)
VALUES ('00000000-0000-4000-8000-00000000aa09','00000000-0000-4000-8000-00000000c109','00000000-0000-4000-8000-00000000b109','2025-01-15','2020-01-01','v1','pre10',
 '{"rate_schedule_id":null,"rate_schedule_version_id":null,"rate_schedule_code":null,"customer_type":null,"partial_period_policy":null,"items":[]}',
 '{"pga_factor":null,"btu_factor":null,"pressure_factor":null,"temperature_factor":null,"meter_multiplier":null,"factor_stack_intermediates":{}}',
 '{"applied":false}','{"jurisdictions":[],"exemptions":[],"franchise_fees":[]}','{"reads":[]}',
 '{"customer_id":"00000000-0000-4000-8000-00000000ac09","customer_class":null,"location_id":"00000000-0000-4000-8000-00000000ad09","premise_zones":{}}',
 '{"period_start":"2026-03-01","period_end":"2026-03-31","days_in_period":31,"proration_policy":null}',
 '[{"invoice_line_item_id":"00000000-0000-4000-8000-00000000e109","charge_type":"base_charge","amount":12.50}]');
UPDATE public.invoices SET status = 'pending' WHERE id = '00000000-0000-4000-8000-00000000c109';
