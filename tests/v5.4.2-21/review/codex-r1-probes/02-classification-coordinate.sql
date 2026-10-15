\set ON_ERROR_STOP on
-- Run as tally against a throwaway clone with frozen -21 already applied.
BEGIN;
SET LOCAL search_path = public, pg_temp;
SET LOCAL transaction_isolation = 'read committed';
INSERT INTO public.tenants (id,name,slug) VALUES
 ('cd210000-0000-4000-8000-000000000001','Codex probe','codex-r1-probe');
INSERT INTO public.users (id,tenant_id,display_name,email,role,is_active) VALUES
 ('cd210000-0000-4000-8000-000000000002','cd210000-0000-4000-8000-000000000001','Probe','codex-r1@example.test','operator',true);
INSERT INTO public.customers (id,tenant_id,customer_number) VALUES
 ('cd210000-0000-4000-8000-000000000003','cd210000-0000-4000-8000-000000000001','CODEX-R1');
INSERT INTO public.service_locations (id,tenant_id,customer_id,location_number,address_line1,city,state,zip) VALUES
 ('cd210000-0000-4000-8000-000000000004','cd210000-0000-4000-8000-000000000001','cd210000-0000-4000-8000-000000000003','CODEX-LOC','1 Main','Austin','TX','78701');
CREATE FUNCTION pg_temp.snap(p_inv uuid, p_valid date, p_rec timestamptz) RETURNS void LANGUAGE plpgsql AS $$
DECLARE i public.invoices%ROWTYPE;
BEGIN
  SELECT * INTO i FROM public.invoices WHERE id = p_inv;
  INSERT INTO public.invoice_calculation_snapshots
    (tenant_id, invoice_id, billing_run_id, valid_at, recorded_at, snapshot_schema_version, formula_version,
     rate_inputs, gas_factors, wna_inputs, tax_inputs, read_inputs, customer_inputs, period_inputs, line_items)
  VALUES (i.tenant_id, i.id, i.billing_run_id, p_valid, p_rec, 'v1', 'bat11',
     '{"rate_schedule_id":null,"rate_schedule_version_id":null,"rate_schedule_code":null,"customer_type":null,"partial_period_policy":null,"items":[]}',
     '{"pga_factor":null,"btu_factor":null,"pressure_factor":null,"temperature_factor":null,"meter_multiplier":null,"factor_stack_intermediates":{}}',
     '{"applied":false}',
     '{"jurisdictions":[],"exemptions":[],"franchise_fees":[]}',
     '{"reads":[]}',
     jsonb_build_object('customer_id', i.customer_id, 'customer_class', null, 'location_id', i.location_id, 'premise_zones', '{}'::jsonb),
     jsonb_build_object('period_start', i.period_start, 'period_end', i.period_end, 'days_in_period', i.period_end - i.period_start + 1, 'proration_policy', null),
     (SELECT coalesce(jsonb_agg(jsonb_build_object('invoice_line_item_id', l.id, 'charge_type', l.charge_type, 'amount', l.amount)), '[]'::jsonb)
        FROM public.invoice_line_items l WHERE l.invoice_id = i.id));
END $$;

GRANT EXECUTE ON FUNCTION pg_temp.snap(uuid, date, timestamptz) TO tally_app;

INSERT INTO public.meters (id,tenant_id,meter_number,location_id,service_type) VALUES
 ('cd210000-0000-4000-8000-000000000008','cd210000-0000-4000-8000-000000000001','CODEX-METER','cd210000-0000-4000-8000-000000000004','gas');
SET ROLE tally_app;
SELECT set_config('app.user_id','cd210000-0000-4000-8000-000000000002',true);

INSERT INTO public.rate_items (id,tenant_id,item_code) VALUES
 ('cd210000-0000-4000-8000-000000000005','cd210000-0000-4000-8000-000000000001','CODEX-CLASSIFICATION');
SELECT public.assert_reference_version('rate_items','cd210000-0000-4000-8000-000000000005',1);
INSERT INTO public.rate_item_versions (tenant_id,rate_item_id,item_name,service_type,calculation_type,regulatory_class,effective_date,expiry_date,change_type) VALUES
 ('cd210000-0000-4000-8000-000000000001','cd210000-0000-4000-8000-000000000005','January fixed','gas','fixed_monthly','regulated','2026-01-01','2026-01-31','initial'),
 ('cd210000-0000-4000-8000-000000000001','cd210000-0000-4000-8000-000000000005','February per unit','gas','per_unit_usage','regulated','2026-02-01',NULL,'initial');
-- First isolate the classification difference; then exercise a real correction.
-- A January correction using a custom February valid_at has the latter type.
DO $$
DECLARE l public.invoice_line_items; a text; b text;
BEGIN
 l.charge_type:='surcharge'; l.service_type:='gas';
 l.rate_item_id:='cd210000-0000-4000-8000-000000000005';
 a:=public.invoice_line_arithmetic_gap(l,DATE '2026-01-31',now());
 b:=public.invoice_line_arithmetic_gap(l,DATE '2026-02-28',now());
 RAISE NOTICE 'PROBE 02 same amount-only line: period_end gap=%, correction valid_at gap=%',a,b;
 RAISE NOTICE 'PROBE 02 January classification=%, February classification=%',
  (SELECT calculation_type FROM public.rate_item_as_of(l.rate_item_id,DATE '2026-01-31',now())),
  (SELECT calculation_type FROM public.rate_item_as_of(l.rate_item_id,DATE '2026-02-28',now()));
END $$;

INSERT INTO public.invoices (id,tenant_id,invoice_number,customer_id,location_id,invoice_date,billing_period,period_start,period_end,due_date,amount_due) VALUES
 ('cd210000-0000-4000-8000-000000000006','cd210000-0000-4000-8000-000000000001','CODEX-ORIGINAL','cd210000-0000-4000-8000-000000000003','cd210000-0000-4000-8000-000000000004','2026-02-01','2026-01','2026-01-01','2026-01-31','2026-02-20',10);
SELECT pg_temp.snap('cd210000-0000-4000-8000-000000000006','2026-01-31',now());
UPDATE public.invoices SET status='pending' WHERE id='cd210000-0000-4000-8000-000000000006';
SET CONSTRAINTS ALL IMMEDIATE;
INSERT INTO public.account_ledger (tenant_id,customer_id,transaction_date,transaction_type,description,amount,reference_type,reference_id) VALUES
 ('cd210000-0000-4000-8000-000000000001','cd210000-0000-4000-8000-000000000003',CURRENT_DATE,'charge','Original charge',10,'invoice','cd210000-0000-4000-8000-000000000006');
SELECT public.void_invoice('cd210000-0000-4000-8000-000000000006','cd210000-0000-4000-8000-000000000002','wrong_rate');
SET CONSTRAINTS ALL DEFERRED;
INSERT INTO public.billing_runs (id,tenant_id,run_number,billing_period,period_start,period_end,run_type,status,started_at,correction_rate_mode) VALUES
 ('cd210000-0000-4000-8000-000000000009','cd210000-0000-4000-8000-000000000001','CODEX-CORRECTION','2026-01','2026-01-01','2026-01-31','correction','in_progress',now(),'historical');
INSERT INTO public.correction_run_targets (tenant_id,billing_run_id,voided_invoice_id,meter_id,customer_id,rate_date_mode,rate_date_override) VALUES
 ('cd210000-0000-4000-8000-000000000001','cd210000-0000-4000-8000-000000000009','cd210000-0000-4000-8000-000000000006','cd210000-0000-4000-8000-000000000008','cd210000-0000-4000-8000-000000000003','custom','2026-02-28');
INSERT INTO public.invoices (id,tenant_id,invoice_number,customer_id,location_id,invoice_date,billing_period,period_start,period_end,due_date,amount_due,billing_run_id,invoice_type,replaces_invoice_id) VALUES
 ('cd210000-0000-4000-8000-000000000010','cd210000-0000-4000-8000-000000000001','CODEX-CORRECTED','cd210000-0000-4000-8000-000000000003','cd210000-0000-4000-8000-000000000004','2026-02-01','2026-01','2026-01-01','2026-01-31','2026-02-20',10,'cd210000-0000-4000-8000-000000000009','correction','cd210000-0000-4000-8000-000000000006');
INSERT INTO public.invoice_line_items (tenant_id,invoice_id,service_type,charge_type,description,amount,rate_item_id) VALUES
 ('cd210000-0000-4000-8000-000000000001','cd210000-0000-4000-8000-000000000010','gas','surcharge','February per-unit price for January correction',10,'cd210000-0000-4000-8000-000000000005');
SELECT pg_temp.snap('cd210000-0000-4000-8000-000000000010','2026-02-28',now());
DO $$ BEGIN
 BEGIN
  UPDATE public.invoices SET status='pending' WHERE id='cd210000-0000-4000-8000-000000000010';
  SET CONSTRAINTS ALL IMMEDIATE;
  RAISE NOTICE 'PROBE 02 CORRECTION ACCEPTED after ALL checks: bound February per-unit version, no arithmetic';
 EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'PROBE 02 CORRECTION REFUSED [%] %',SQLSTATE,SQLERRM;
 END;
END $$;
ROLLBACK;
