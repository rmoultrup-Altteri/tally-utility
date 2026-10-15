\set ON_ERROR_STOP on
-- Run as superuser tally on a fresh throwaway clone with frozen r3 applied.
-- COMMITTED SEQUENCE: T0 creates/ issues/voids an original fixed rider;
-- T1 retracts its classification and replaces it with per-unit usage.
-- T2 tests a historical correction, then ROLLBACK. T0/T1 fixtures remain:
-- discard the clone afterwards; retention guards deliberately forbid cleanup.
BEGIN;
SET LOCAL search_path = public, pg_temp;
SET LOCAL transaction_isolation = 'read committed';
INSERT INTO public.tenants (id,name,slug) VALUES
 ('cd232000-0000-4000-8000-000000000001','Codex probe','codex-r3-history-probe');
INSERT INTO public.users (id,tenant_id,display_name,email,role,is_active) VALUES
 ('cd232000-0000-4000-8000-000000000002','cd232000-0000-4000-8000-000000000001','Probe','codex-r3-history@example.test','operator',true);
INSERT INTO public.customers (id,tenant_id,customer_number) VALUES
 ('cd232000-0000-4000-8000-000000000003','cd232000-0000-4000-8000-000000000001','CODEX-R3-HISTORY');
INSERT INTO public.service_locations (id,tenant_id,customer_id,location_number,address_line1,city,state,zip) VALUES
 ('cd232000-0000-4000-8000-000000000004','cd232000-0000-4000-8000-000000000001','cd232000-0000-4000-8000-000000000003','CODEX-LOC','1 Main','Austin','TX','78701');
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
 ('cd232000-0000-4000-8000-000000000008','cd232000-0000-4000-8000-000000000001','CODEX-METER','cd232000-0000-4000-8000-000000000004','gas');
SET ROLE tally_app;
SELECT set_config('app.user_id','cd232000-0000-4000-8000-000000000002',true);

INSERT INTO public.rate_items (id,tenant_id,item_code) VALUES
 ('cd232000-0000-4000-8000-000000000005','cd232000-0000-4000-8000-000000000001','CODEX-CLASSIFICATION');
SELECT public.assert_reference_version('rate_items','cd232000-0000-4000-8000-000000000005',1);
INSERT INTO public.rate_item_versions (tenant_id,rate_item_id,item_name,service_type,calculation_type,regulatory_class,effective_date,change_type) VALUES
 ('cd232000-0000-4000-8000-000000000001','cd232000-0000-4000-8000-000000000005','Original fixed','gas','fixed_monthly','regulated','2026-01-01','initial');
INSERT INTO public.invoices (id,tenant_id,invoice_number,customer_id,location_id,invoice_date,billing_period,period_start,period_end,due_date,amount_due) VALUES
 ('cd232000-0000-4000-8000-000000000006','cd232000-0000-4000-8000-000000000001','CODEX-ORIGINAL','cd232000-0000-4000-8000-000000000003','cd232000-0000-4000-8000-000000000004','2026-02-01','2026-01','2026-01-01','2026-01-31','2026-02-20',10);
INSERT INTO public.invoice_line_items(tenant_id,invoice_id,service_type,charge_type,description,amount,rate_item_id) VALUES
 ('cd232000-0000-4000-8000-000000000001','cd232000-0000-4000-8000-000000000006','gas','surcharge','Original fixed rider',10,'cd232000-0000-4000-8000-000000000005');
SELECT pg_temp.snap('cd232000-0000-4000-8000-000000000006','2026-01-31',now());
UPDATE public.invoices SET status='pending' WHERE id='cd232000-0000-4000-8000-000000000006';
SET CONSTRAINTS ALL IMMEDIATE;
INSERT INTO public.account_ledger (tenant_id,customer_id,transaction_date,transaction_type,description,amount,reference_type,reference_id) VALUES
 ('cd232000-0000-4000-8000-000000000001','cd232000-0000-4000-8000-000000000003',CURRENT_DATE,'charge','Original charge',10,'invoice','cd232000-0000-4000-8000-000000000006');
SELECT public.void_invoice('cd232000-0000-4000-8000-000000000006','cd232000-0000-4000-8000-000000000002','wrong_rate');
DO $$ BEGIN RAISE NOTICE 'PROBE 02 T0 original fixed rider issued with ALL checks and voided'; END $$;
COMMIT;
SELECT pg_sleep(0.02);
BEGIN;
SET ROLE tally_app;
SELECT set_config('app.user_id','cd232000-0000-4000-8000-000000000002',true);
SELECT public.assert_reference_version('rate_items','cd232000-0000-4000-8000-000000000005',2);
UPDATE public.rate_item_versions SET recorded_until=now(),closed_type='retracted',closed_reason='Probe reclassification'
 WHERE rate_item_id='cd232000-0000-4000-8000-000000000005' AND recorded_until IS NULL;
INSERT INTO public.rate_item_versions(tenant_id,rate_item_id,item_name,service_type,calculation_type,regulatory_class,effective_date,change_type,change_reason) VALUES
 ('cd232000-0000-4000-8000-000000000001','cd232000-0000-4000-8000-000000000005','Corrected per unit','gas','per_unit_usage','regulated','2026-01-01','correction','Probe reclassification');
DO $$ BEGIN RAISE NOTICE 'PROBE 02 T1 reclassification committed next'; END $$;
COMMIT;
SELECT pg_sleep(0.02);
BEGIN;
SET ROLE tally_app;
SELECT set_config('app.user_id','cd232000-0000-4000-8000-000000000002',true);
SET CONSTRAINTS ALL DEFERRED;
INSERT INTO public.billing_runs (id,tenant_id,run_number,billing_period,period_start,period_end,run_type,status,started_at,correction_rate_mode) VALUES
 ('cd232000-0000-4000-8000-000000000009','cd232000-0000-4000-8000-000000000001','CODEX-CORRECTION','2026-01','2026-01-01','2026-01-31','correction','in_progress',now(),'historical');
INSERT INTO public.correction_run_targets (tenant_id,billing_run_id,voided_invoice_id,meter_id,customer_id,rate_date_mode,rate_date_override) VALUES
 ('cd232000-0000-4000-8000-000000000001','cd232000-0000-4000-8000-000000000009','cd232000-0000-4000-8000-000000000006','cd232000-0000-4000-8000-000000000008','cd232000-0000-4000-8000-000000000003','custom','2026-01-31');
INSERT INTO public.invoices (id,tenant_id,invoice_number,customer_id,location_id,invoice_date,billing_period,period_start,period_end,due_date,amount_due,billing_run_id,invoice_type,replaces_invoice_id) VALUES
 ('cd232000-0000-4000-8000-000000000010','cd232000-0000-4000-8000-000000000001','CODEX-CORRECTED','cd232000-0000-4000-8000-000000000003','cd232000-0000-4000-8000-000000000004','2026-02-01','2026-01','2026-01-01','2026-01-31','2026-02-20',10,'cd232000-0000-4000-8000-000000000009','correction','cd232000-0000-4000-8000-000000000006');
INSERT INTO public.invoice_line_items(tenant_id,invoice_id,service_type,charge_type,description,amount,rate_item_id) VALUES
 ('cd232000-0000-4000-8000-000000000001','cd232000-0000-4000-8000-000000000010','gas','surcharge','Historical fixed rider',10,'cd232000-0000-4000-8000-000000000005');
SELECT pg_temp.snap('cd232000-0000-4000-8000-000000000010','2026-01-31',
 (SELECT recorded_at FROM public.invoice_calculation_snapshots WHERE invoice_id='cd232000-0000-4000-8000-000000000006'));
DO $$
DECLARE l public.invoice_line_items; s public.invoice_calculation_snapshots;
BEGIN
 SELECT * INTO STRICT l FROM public.invoice_line_items WHERE invoice_id='cd232000-0000-4000-8000-000000000010';
 SELECT * INTO STRICT s FROM public.invoice_calculation_snapshots WHERE invoice_id=l.invoice_id;
 RAISE NOTICE 'PROBE 02 snapshot accepted; historical gap=%, current gap=%',
   public.invoice_line_arithmetic_gap(l,s.valid_at,s.recorded_at),
   public.invoice_line_arithmetic_gap(l,s.valid_at,now());
 BEGIN
  UPDATE public.invoices SET status='pending' WHERE id=l.invoice_id;
  SET CONSTRAINTS ALL IMMEDIATE;
  RAISE EXCEPTION USING ERRCODE='P0099',MESSAGE='accepted';
 EXCEPTION WHEN SQLSTATE 'P0099' THEN
  RAISE NOTICE 'PROBE 02 historical amount-only correction ACCEPTED (unexpected)';
 WHEN OTHERS THEN
  RAISE NOTICE 'PROBE 02 historical amount-only correction REFUSED [%] %',SQLSTATE,SQLERRM;
 END;
END $$;
-- Positive control: carry current-required figures, keep historical coordinates.
DELETE FROM public.invoice_calculation_snapshots WHERE invoice_id='cd232000-0000-4000-8000-000000000010';
UPDATE public.invoice_line_items SET usage_quantity=5,usage_unit='ccf',rate=2,gas_meter_factor=1.02,gas_ccf_used=5,gas_therms_billed=5.1
 WHERE invoice_id='cd232000-0000-4000-8000-000000000010';
SELECT pg_temp.snap('cd232000-0000-4000-8000-000000000010','2026-01-31',
 (SELECT recorded_at FROM public.invoice_calculation_snapshots WHERE invoice_id='cd232000-0000-4000-8000-000000000006'));
DO $$ BEGIN
 BEGIN
  UPDATE public.invoices SET status='pending' WHERE id='cd232000-0000-4000-8000-000000000010';
  SET CONSTRAINTS ALL IMMEDIATE;
  RAISE NOTICE 'PROBE 02 populated historical correction ACCEPTED after ALL checks';
 EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'PROBE 02 populated historical correction REFUSED [%] %',SQLSTATE,SQLERRM;
 END;
END $$;
ROLLBACK;
