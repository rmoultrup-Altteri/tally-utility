-- ATTACK A: correction target pointing at an invoice that is NOT void (still 'sent'/live).
-- Nothing in the schema or this patch requires correction_run_targets.voided_invoice_id to
-- actually be status='void'. Does the binding happily accept a snapshot for a "correction"
-- of a still-live invoice?
BEGIN;
SET CONSTRAINTS ALL IMMEDIATE;

INSERT INTO public.billing_runs (id, tenant_id, run_number, billing_period, period_start, period_end, run_type, status, started_at, correction_rate_mode)
VALUES ('10000000-0000-4000-8000-00000000b101', '10000000-0000-4000-8000-00000000aa01', 'CDX-CORR-A', '2025-06', '2025-06-01', '2025-06-30', 'correction', 'in_progress', now() - interval '2 hours', 'historical');

-- The "original" invoice we will falsely target: fully live, sent, paid, no void.
INSERT INTO public.invoices (id, tenant_id, invoice_number, customer_id, location_id, invoice_type, invoice_date, billing_period, period_start, period_end, due_date, status)
VALUES ('10000000-0000-4000-8000-00000000c101', '10000000-0000-4000-8000-00000000aa01', 'T1-LIVE', '10000000-0000-4000-8000-00000000ac01', '10000000-0000-4000-8000-00000000ad01', 'regular', '2025-07-01', '2025-06', '2025-06-01', '2025-06-30', '2025-07-21', 'draft');
INSERT INTO public.invoice_line_items (tenant_id, invoice_id, service_type, charge_type, description, amount)
VALUES ('10000000-0000-4000-8000-00000000aa01', '10000000-0000-4000-8000-00000000c101', 'gas', 'base_charge', 'Customer charge', 12.50);

CREATE FUNCTION pg_temp.snap(p_inv uuid, p_valid date, p_rec timestamptz) RETURNS void LANGUAGE plpgsql AS $$
DECLARE i public.invoices%ROWTYPE;
BEGIN
  SELECT * INTO i FROM public.invoices WHERE id = p_inv;
  INSERT INTO public.invoice_calculation_snapshots
    (tenant_id, invoice_id, billing_run_id, valid_at, recorded_at, snapshot_schema_version, formula_version,
     rate_inputs, gas_factors, wna_inputs, tax_inputs, read_inputs, customer_inputs, period_inputs, line_items)
  VALUES (i.tenant_id, i.id, i.billing_run_id, p_valid, p_rec, 'v1', 'cdx10',
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

-- Now flip the "original" to 'sent' (fully live, never voided) -- this requires a snapshot first
-- because enforce_invoice_has_snapshot gates any transition INTO an issued status.
SELECT pg_temp.snap('10000000-0000-4000-8000-00000000c101', '2025-06-30', now());
UPDATE public.invoices SET status = 'sent' WHERE id = '10000000-0000-4000-8000-00000000c101';
DO $$ BEGIN RAISE NOTICE 'setup: T1-LIVE is status=sent, never voided'; END $$;

-- As tally_app operator, create a correction_run_targets row pointing at this LIVE (non-void) invoice.
SET LOCAL app.user_id = '10000000-0000-4000-8000-00000000ab01';
SET ROLE tally_app;

INSERT INTO public.correction_run_targets (id, tenant_id, billing_run_id, voided_invoice_id, meter_id, customer_id, rate_date_mode)
VALUES ('10000000-0000-4000-8000-00000000d101', '10000000-0000-4000-8000-00000000aa01', '10000000-0000-4000-8000-00000000b101', '10000000-0000-4000-8000-00000000c101', '10000000-0000-4000-8000-00000000ae01', '10000000-0000-4000-8000-00000000ac01', 'historical');
DO $$ BEGIN RAISE NOTICE 'PASS/FAIL check: target row created against a non-void invoice (no status guard exists to stop this)'; END $$;

-- Now write a "correction" invoice replacing the still-live invoice.
SELECT pg_temp.inv('10000000-0000-4000-8000-00000000c102', 'T1-CORR-OF-LIVE', '10000000-0000-4000-8000-00000000b101', 'correction', '10000000-0000-4000-8000-00000000c101', '2025-06-01', '2025-06-30');

DO $$
BEGIN
  PERFORM pg_temp.snap('10000000-0000-4000-8000-00000000c102', '2025-06-30', now());
  RAISE NOTICE 'ATTACK A RESULT: snapshot for a "correction" of a NEVER-VOIDED, still-live (sent) invoice was ACCEPTED — no check that voided_invoice_id/replaces_invoice_id actually points to a void invoice';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'attack A blocked: %', SQLERRM;
END $$;

-- Can the correction even be ISSUED while the "original" it replaces is still live and unvoided?
UPDATE public.invoices SET status = 'pending' WHERE id = '10000000-0000-4000-8000-00000000c102';
DO $$
DECLARE v_orig_status text; v_corr_status text;
BEGIN
  SELECT status INTO v_orig_status FROM public.invoices WHERE id = '10000000-0000-4000-8000-00000000c101';
  SELECT status INTO v_corr_status FROM public.invoices WHERE id = '10000000-0000-4000-8000-00000000c102';
  RAISE NOTICE 'ATTACK A FOLLOW-UP: after issuing the "correction", original status=% (expect still sent/live, never voided) and correction status=%', v_orig_status, v_corr_status;
END $$;

ROLLBACK;
