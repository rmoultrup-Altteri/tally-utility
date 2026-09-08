\set ON_ERROR_STOP on
BEGIN;
SET LOCAL app.user_id = '00000000-0000-4000-8000-00000000fb01';
SET ROLE tally_app;
INSERT INTO public.invoice_calculation_snapshots (tenant_id, invoice_id, billing_run_id, valid_at, recorded_at, snapshot_schema_version, formula_version, rate_inputs, gas_factors, wna_inputs, tax_inputs, read_inputs, customer_inputs, period_inputs, line_items)
VALUES ('00000000-0000-4000-8000-00000000fa01','00000000-0000-4000-8000-00000000f103','00000000-0000-4000-8000-00000000f002','2025-06-30',now(),'v1','race',
 '{"rate_schedule_id":null,"rate_schedule_version_id":null,"rate_schedule_code":null,"customer_type":null,"partial_period_policy":null,"items":[]}',
 '{"pga_factor":null,"btu_factor":null,"pressure_factor":null,"temperature_factor":null,"meter_multiplier":null,"factor_stack_intermediates":{}}',
 '{"applied":false}','{"jurisdictions":[],"exemptions":[],"franchise_fees":[]}','{"reads":[]}',
 '{"customer_id":"00000000-0000-4000-8000-00000000fc01","customer_class":null,"location_id":"00000000-0000-4000-8000-00000000fd01","premise_zones":{}}',
 '{"period_start":"2025-06-01","period_end":"2025-06-30","days_in_period":30,"proration_policy":null}',
 '[{"invoice_line_item_id":"00000000-0000-4000-8000-00000000f203","charge_type":"base_charge","amount":12.50}]');
SELECT 'B: snapshot inserted, holding run + target FOR SHARE for 5s' AS a, clock_timestamp();
SELECT pg_sleep(0);
COMMIT;
SELECT 'B: committed' AS a, clock_timestamp();
