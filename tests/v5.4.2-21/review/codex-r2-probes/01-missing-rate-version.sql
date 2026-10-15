\set ON_ERROR_STOP on
-- Run as tally against a throwaway clone with patch-21-frozen-r2.sql already applied.
BEGIN;
SET LOCAL search_path = public, pg_temp;
SET LOCAL transaction_isolation = 'read committed';
INSERT INTO public.tenants (id,name,slug) VALUES
 ('cd210000-0000-4000-8000-000000000001','Codex probe','codex-r2-probe');
INSERT INTO public.users (id,tenant_id,display_name,email,role,is_active) VALUES
 ('cd210000-0000-4000-8000-000000000002','cd210000-0000-4000-8000-000000000001','Probe','codex-r2@example.test','operator',true);
INSERT INTO public.customers (id,tenant_id,customer_number) VALUES
 ('cd210000-0000-4000-8000-000000000003','cd210000-0000-4000-8000-000000000001','CODEX-R2');
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

SET ROLE tally_app;
SELECT set_config('app.user_id','cd210000-0000-4000-8000-000000000002',true);

INSERT INTO public.rate_items (id,tenant_id,item_code) VALUES
 ('cd210000-0000-4000-8000-000000000005','cd210000-0000-4000-8000-000000000001','CODEX-NO-VERSION');
INSERT INTO public.invoices (id,tenant_id,invoice_number,customer_id,location_id,invoice_date,billing_period,period_start,period_end,due_date,amount_due) VALUES
 ('cd210000-0000-4000-8000-000000000006','cd210000-0000-4000-8000-000000000001','CODEX-ISSUE','cd210000-0000-4000-8000-000000000003','cd210000-0000-4000-8000-000000000004','2026-02-01','2026-01','2026-01-01','2026-01-31','2026-02-20',10);
INSERT INTO public.invoice_line_items (tenant_id,invoice_id,service_type,charge_type,description,amount,rate_item_id) VALUES
 ('cd210000-0000-4000-8000-000000000001','cd210000-0000-4000-8000-000000000006','gas','surcharge','Unclassifiable surcharge',10,'cd210000-0000-4000-8000-000000000005');
SELECT pg_temp.snap('cd210000-0000-4000-8000-000000000006','2026-01-31',now());
DO $$
DECLARE v_gap text; v_stamp timestamptz;
BEGIN
 SELECT public.invoice_line_arithmetic_gap(l,DATE '2026-01-31',now()) INTO v_gap
 FROM public.invoice_line_items l WHERE invoice_id='cd210000-0000-4000-8000-000000000006';
 RAISE NOTICE 'PROBE 01 helper gap for absent version = % (NULL means admitted)',v_gap;
 BEGIN
  UPDATE public.invoices SET status='pending' WHERE id='cd210000-0000-4000-8000-000000000006';
  SET CONSTRAINTS ALL IMMEDIATE;
  SELECT first_issued_at INTO v_stamp FROM public.invoices WHERE id='cd210000-0000-4000-8000-000000000006';
  RAISE NOTICE 'PROBE 01 ISSUE ACCEPTED after ALL deferred checks; first_issued_at=%',v_stamp;
 EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'PROBE 01 ISSUE REFUSED [%] %',SQLSTATE,SQLERRM;
 END;
END $$;
ROLLBACK;
