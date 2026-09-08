BEGIN;
SET CONSTRAINTS ALL IMMEDIATE;
SET LOCAL app.user_id = '10000000-0000-4000-8000-00000000ab01';
SET ROLE tally_app;

INSERT INTO public.billing_runs (id, tenant_id, run_number, billing_period, period_start, period_end, run_type, status, started_at, correction_rate_mode)
VALUES ('10000000-0000-4000-8000-00000000bb01', '10000000-0000-4000-8000-00000000aa01', 'CDX-R4', '2025-08', '2025-08-01', '2025-08-31', 'correction', 'in_progress', now(), 'historical');

CREATE FUNCTION pg_temp.snap(p_inv uuid, p_valid date, p_rec timestamptz) RETURNS void LANGUAGE plpgsql AS $$
DECLARE i public.invoices%ROWTYPE;
BEGIN
  SELECT * INTO i FROM public.invoices WHERE id = p_inv;
  INSERT INTO public.invoice_calculation_snapshots
    (tenant_id, invoice_id, billing_run_id, valid_at, recorded_at, snapshot_schema_version, formula_version,
     rate_inputs, gas_factors, wna_inputs, tax_inputs, read_inputs, customer_inputs, period_inputs, line_items)
  VALUES (i.tenant_id, i.id, i.billing_run_id, p_valid, p_rec, 'v1', 'cdx10r4',
     '{"rate_schedule_id":null,"rate_schedule_version_id":null,"rate_schedule_code":null,"customer_type":null,"partial_period_policy":null,"items":[]}',
     '{"pga_factor":null,"btu_factor":null,"pressure_factor":null,"temperature_factor":null,"meter_multiplier":null,"factor_stack_intermediates":{}}',
     '{"applied":false}', '{"jurisdictions":[],"exemptions":[],"franchise_fees":[]}', '{"reads":[]}',
     jsonb_build_object('customer_id', i.customer_id, 'customer_class', null, 'location_id', i.location_id, 'premise_zones', '{}'::jsonb),
     jsonb_build_object('period_start', i.period_start, 'period_end', i.period_end, 'days_in_period', i.period_end - i.period_start + 1, 'proration_policy', null),
     (SELECT coalesce(jsonb_agg(jsonb_build_object('invoice_line_item_id', l.id, 'charge_type', l.charge_type, 'amount', l.amount)), '[]'::jsonb)
        FROM public.invoice_line_items l WHERE l.invoice_id = i.id));
END $$;
GRANT EXECUTE ON FUNCTION pg_temp.snap(uuid, date, timestamptz) TO tally_app;
CREATE FUNCTION pg_temp.inv(p_id uuid, p_num text, p_run uuid, p_type text, p_replaces uuid, p_ps date, p_pe date) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO public.invoices (id, tenant_id, invoice_number, billing_run_id, customer_id, location_id, invoice_type, replaces_invoice_id,
                               invoice_date, billing_period, period_start, period_end, due_date)
  VALUES (p_id, '10000000-0000-4000-8000-00000000aa01', p_num, p_run, '10000000-0000-4000-8000-00000000ac01', '10000000-0000-4000-8000-00000000ad01',
          p_type, p_replaces, p_pe + 1, to_char(p_pe, 'YYYY-MM'), p_ps, p_pe, p_pe + 21);
  INSERT INTO public.invoice_line_items (tenant_id, invoice_id, service_type, charge_type, description, amount)
  VALUES ('10000000-0000-4000-8000-00000000aa01', p_id, 'gas', 'base_charge', 'Customer charge', 12.50);
END $$;
GRANT EXECUTE ON FUNCTION pg_temp.inv(uuid, text, uuid, text, uuid, date, date) TO tally_app;
CREATE FUNCTION pg_temp.mktarget(p_id uuid, p_voided uuid) RETURNS void LANGUAGE sql AS $$
  INSERT INTO public.correction_run_targets (id, tenant_id, billing_run_id, voided_invoice_id, meter_id, customer_id, rate_date_mode)
  VALUES (p_id, '10000000-0000-4000-8000-00000000aa01', '10000000-0000-4000-8000-00000000bb01', p_voided, '10000000-0000-4000-8000-00000000ae01', '10000000-0000-4000-8000-00000000ac01', 'historical');
$$;
GRANT EXECUTE ON FUNCTION pg_temp.mktarget(uuid, uuid) TO tally_app;

-- A -> void; B replaces A -> issue -> void; C replaces B -> issue (live).
SELECT pg_temp.inv('10000000-0000-4000-8000-00000000e001', 'A-R4', NULL, 'regular', NULL, '2025-08-01', '2025-08-31');
SELECT pg_temp.snap('10000000-0000-4000-8000-00000000e001', '2025-08-31', now());
UPDATE public.invoices SET status='pending' WHERE id='10000000-0000-4000-8000-00000000e001';
SELECT public.void_invoice('10000000-0000-4000-8000-00000000e001','10000000-0000-4000-8000-00000000ab01','system_error',NULL,true);
SELECT pg_temp.mktarget('10000000-0000-4000-8000-00000000f001', '10000000-0000-4000-8000-00000000e001');
SELECT pg_temp.inv('10000000-0000-4000-8000-00000000e002', 'B-R4', '10000000-0000-4000-8000-00000000bb01', 'correction', '10000000-0000-4000-8000-00000000e001', '2025-08-01', '2025-08-31');
SELECT pg_temp.snap('10000000-0000-4000-8000-00000000e002', '2025-08-31', now());
UPDATE public.invoices SET status='pending' WHERE id='10000000-0000-4000-8000-00000000e002';
SELECT public.void_invoice('10000000-0000-4000-8000-00000000e002','10000000-0000-4000-8000-00000000ab01','system_error',NULL,true);
SELECT pg_temp.mktarget('10000000-0000-4000-8000-00000000f002', '10000000-0000-4000-8000-00000000e002');
SELECT pg_temp.inv('10000000-0000-4000-8000-00000000e003', 'C-R4', '10000000-0000-4000-8000-00000000bb01', 'correction', '10000000-0000-4000-8000-00000000e002', '2025-08-01', '2025-08-31');
SELECT pg_temp.snap('10000000-0000-4000-8000-00000000e003', '2025-08-31', now());
UPDATE public.invoices SET status='pending' WHERE id='10000000-0000-4000-8000-00000000e003';
DO $$ BEGIN RAISE NOTICE 'R4 setup: C is live, replacing void B, which replaces void A'; END $$;

-- D replaces A directly, while C (replacing B) is live: must be REFUSED now (lineage-wide).
SELECT pg_temp.inv('10000000-0000-4000-8000-00000000e004', 'D-R4', '10000000-0000-4000-8000-00000000bb01', 'correction', '10000000-0000-4000-8000-00000000e001', '2025-08-01', '2025-08-31');
DO $$
BEGIN
  PERFORM pg_temp.snap('10000000-0000-4000-8000-00000000e004', '2025-08-31', now());
  RAISE NOTICE 'R4 D-1 RESULT: D (replacing A while C, replacing B, is live) SUCCEEDED -- gap NOT fixed';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'R4 D-1 RESULT: correctly refused -- %', SQLERRM;
END $$;

-- Now void C; D should land (legal continuation).
SELECT public.void_invoice('10000000-0000-4000-8000-00000000e003','10000000-0000-4000-8000-00000000ab01','system_error',NULL,true);
DO $$
BEGIN
  PERFORM pg_temp.snap('10000000-0000-4000-8000-00000000e004', '2025-08-31', now());
  RAISE NOTICE 'R4 D-2 RESULT: after voiding C, D snapshots OK (expected)';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'R4 D-2 RESULT: still refused (unexpected) -- %', SQLERRM;
END $$;

-- Sideways: A void, B1 (corrects A) void, B2 (corrects A) live, then B3 corrects B1 (dead branch).
SELECT pg_temp.inv('10000000-0000-4000-8000-00000000e011', 'A2-R4', NULL, 'regular', NULL, '2025-09-01', '2025-09-30');
SELECT pg_temp.snap('10000000-0000-4000-8000-00000000e011', '2025-09-30', now());
UPDATE public.invoices SET status='pending' WHERE id='10000000-0000-4000-8000-00000000e011';
SELECT public.void_invoice('10000000-0000-4000-8000-00000000e011','10000000-0000-4000-8000-00000000ab01','system_error',NULL,true);
SELECT pg_temp.mktarget('10000000-0000-4000-8000-00000000f011', '10000000-0000-4000-8000-00000000e011');
SELECT pg_temp.inv('10000000-0000-4000-8000-00000000e012', 'B1-R4', '10000000-0000-4000-8000-00000000bb01', 'correction', '10000000-0000-4000-8000-00000000e011', '2025-09-01', '2025-09-30');
SELECT pg_temp.snap('10000000-0000-4000-8000-00000000e012', '2025-09-30', now());
UPDATE public.invoices SET status='pending' WHERE id='10000000-0000-4000-8000-00000000e012';
SELECT public.void_invoice('10000000-0000-4000-8000-00000000e012','10000000-0000-4000-8000-00000000ab01','system_error',NULL,true);
-- new target for A2 again (B1's target row is done, need a fresh target row for A2 -> B2)
INSERT INTO public.correction_run_targets (id, tenant_id, billing_run_id, voided_invoice_id, meter_id, customer_id, rate_date_mode)
SELECT '10000000-0000-4000-8000-00000000f012', tenant_id, billing_run_id, voided_invoice_id, meter_id, customer_id, rate_date_mode FROM public.correction_run_targets WHERE id='10000000-0000-4000-8000-00000000f011'
ON CONFLICT DO NOTHING;
DO $$ BEGIN RAISE NOTICE 'note: reusing target row f011 for B2 too (unique on run+voided_invoice_id already covers A2)'; END $$;
SELECT pg_temp.inv('10000000-0000-4000-8000-00000000e013', 'B2-R4', '10000000-0000-4000-8000-00000000bb01', 'correction', '10000000-0000-4000-8000-00000000e011', '2025-09-01', '2025-09-30');
SELECT pg_temp.snap('10000000-0000-4000-8000-00000000e013', '2025-09-30', now());
UPDATE public.invoices SET status='pending' WHERE id='10000000-0000-4000-8000-00000000e013';
DO $$ BEGIN RAISE NOTICE 'R4 sideways: B2 live, replacing A2 (B1 dead branch, void)'; END $$;
SELECT pg_temp.mktarget('10000000-0000-4000-8000-00000000f013', '10000000-0000-4000-8000-00000000e012');
SELECT pg_temp.inv('10000000-0000-4000-8000-00000000e014', 'B3-R4', '10000000-0000-4000-8000-00000000bb01', 'correction', '10000000-0000-4000-8000-00000000e012', '2025-09-01', '2025-09-30');
DO $$
BEGIN
  PERFORM pg_temp.snap('10000000-0000-4000-8000-00000000e014', '2025-09-30', now());
  RAISE NOTICE 'R4 SIDEWAYS RESULT: B3 (correcting dead branch B1) SUCCEEDED while B2 is live -- gap';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'R4 SIDEWAYS RESULT: correctly refused -- %', SQLERRM;
END $$;

-- Cross-tenant / non-correction chain: T2 credit_memo replaces T1's void bill A (cross-tenant FK, no RLS/tenant check for non-correction types).
SET LOCAL app.user_id = '10000000-0000-4000-8000-00000000ab02';
SET ROLE tally_app;
INSERT INTO public.invoices (id, tenant_id, invoice_number, customer_id, location_id, invoice_type, replaces_invoice_id, invoice_date, billing_period, period_start, period_end, due_date, status)
VALUES ('10000000-0000-4000-8000-00000000e021', '10000000-0000-4000-8000-00000000aa02', 'T2-CM-R4', '10000000-0000-4000-8000-00000000ac02', '10000000-0000-4000-8000-00000000ad02', 'credit_memo', '10000000-0000-4000-8000-00000000e001', '2025-08-01', '2025-08', '2025-08-01', '2025-08-31', '2025-08-21', 'draft');
DO $$ BEGIN RAISE NOTICE 'R4 XTENANT: T2 credit_memo with replaces_invoice_id = T1''s void bill A inserted (FK has no tenant check) -- id exists cross-tenant in the invoices table now'; END $$;
INSERT INTO public.invoice_line_items (tenant_id, invoice_id, service_type, charge_type, description, amount)
VALUES ('10000000-0000-4000-8000-00000000aa02', '10000000-0000-4000-8000-00000000e021', 'gas', 'base_charge', 'x', -5.00);
DO $$
BEGIN
  PERFORM public.invoice_lineage_root('10000000-0000-4000-8000-00000000e021');
END $$;
SELECT public.invoice_lineage_root('10000000-0000-4000-8000-00000000e021') AS root_seen_by_t2;

ROLLBACK;
