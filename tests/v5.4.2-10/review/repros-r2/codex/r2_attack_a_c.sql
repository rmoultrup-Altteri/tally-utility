-- R2 ATTACK A: re-run — correction against a NEVER-VOIDED (still 'sent') invoice.
-- R2 ATTACK C: re-run — cross-tenant oracle through get_correction_rate_date.
BEGIN;
SET CONSTRAINTS ALL IMMEDIATE;

INSERT INTO public.billing_runs (id, tenant_id, run_number, billing_period, period_start, period_end, run_type, status, started_at, correction_rate_mode)
VALUES ('10000000-0000-4000-8000-00000000b501', '10000000-0000-4000-8000-00000000aa01', 'CDX-R2-A', '2025-06', '2025-06-01', '2025-06-30', 'correction', 'in_progress', now(), 'historical');

INSERT INTO public.invoices (id, tenant_id, invoice_number, customer_id, location_id, invoice_type, invoice_date, billing_period, period_start, period_end, due_date, status)
VALUES ('10000000-0000-4000-8000-00000000c501', '10000000-0000-4000-8000-00000000aa01', 'T1-LIVE-R2', '10000000-0000-4000-8000-00000000ac01', '10000000-0000-4000-8000-00000000ad01', 'regular', '2025-07-01', '2025-06', '2025-06-01', '2025-06-30', '2025-07-21', 'draft');
INSERT INTO public.invoice_line_items (tenant_id, invoice_id, service_type, charge_type, description, amount)
VALUES ('10000000-0000-4000-8000-00000000aa01', '10000000-0000-4000-8000-00000000c501', 'gas', 'base_charge', 'Customer charge', 12.50);

CREATE FUNCTION pg_temp.snap(p_inv uuid, p_valid date, p_rec timestamptz) RETURNS void LANGUAGE plpgsql AS $$
DECLARE i public.invoices%ROWTYPE;
BEGIN
  SELECT * INTO i FROM public.invoices WHERE id = p_inv;
  INSERT INTO public.invoice_calculation_snapshots
    (tenant_id, invoice_id, billing_run_id, valid_at, recorded_at, snapshot_schema_version, formula_version,
     rate_inputs, gas_factors, wna_inputs, tax_inputs, read_inputs, customer_inputs, period_inputs, line_items)
  VALUES (i.tenant_id, i.id, i.billing_run_id, p_valid, p_rec, 'v1', 'cdx10r2',
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

SELECT pg_temp.snap('10000000-0000-4000-8000-00000000c501', '2025-06-30', now());
UPDATE public.invoices SET status = 'sent' WHERE id = '10000000-0000-4000-8000-00000000c501';

SET LOCAL app.user_id = '10000000-0000-4000-8000-00000000ab01';
SET ROLE tally_app;

INSERT INTO public.correction_run_targets (id, tenant_id, billing_run_id, voided_invoice_id, meter_id, customer_id, rate_date_mode)
VALUES ('10000000-0000-4000-8000-00000000d501', '10000000-0000-4000-8000-00000000aa01', '10000000-0000-4000-8000-00000000b501', '10000000-0000-4000-8000-00000000c501', '10000000-0000-4000-8000-00000000ae01', '10000000-0000-4000-8000-00000000ac01', 'historical');

SELECT pg_temp.inv('10000000-0000-4000-8000-00000000c502', 'T1-CORR-OF-LIVE-R2', '10000000-0000-4000-8000-00000000b501', 'correction', '10000000-0000-4000-8000-00000000c501', '2025-06-01', '2025-06-30');

DO $$
BEGIN
  PERFORM pg_temp.snap('10000000-0000-4000-8000-00000000c502', '2025-06-30', now());
  RAISE NOTICE 'R2 ATTACK A: snapshot for correction of a NEVER-VOIDED invoice ACCEPTED -- fix did NOT close this';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'R2 ATTACK A RESULT: correctly REFUSED -- %', SQLERRM;
END $$;

RESET ROLE;

-- ---- R2 ATTACK C: cross-tenant oracle ----
SET LOCAL app.user_id = '10000000-0000-4000-8000-00000000ab02';
SET ROLE tally_app;
DO $$
DECLARE v_date date;
BEGIN
  v_date := public.get_correction_rate_date('10000000-0000-4000-8000-00000000b501', '10000000-0000-4000-8000-00000000c501');
  RAISE NOTICE 'R2 ATTACK C: direct EXECUTE of get_correction_rate_date still returns %, still a leak by itself (declared pre-existing, A-23 item, not this patch''s job)', v_date;
END $$;

ROLLBACK;
