-- R3: correction-of-a-correction chain (C replaces B replaces A), plus the
-- "duplicate chain" question: once B is void, can a NEW correction D ALSO
-- directly replace A (the root), running alongside C (which replaces B) --
-- two live corrections for what was originally one bill?
BEGIN;
SET CONSTRAINTS ALL IMMEDIATE;
SET LOCAL app.user_id = '10000000-0000-4000-8000-00000000ab01';
SET ROLE tally_app;

INSERT INTO public.billing_runs (id, tenant_id, run_number, billing_period, period_start, period_end, run_type, status, started_at, correction_rate_mode)
VALUES ('10000000-0000-4000-8000-00000000b801', '10000000-0000-4000-8000-00000000aa01', 'CDX-R3-CHAIN', '2025-08', '2025-08-01', '2025-08-31', 'correction', 'in_progress', now(), 'historical');

CREATE FUNCTION pg_temp.snap(p_inv uuid, p_valid date, p_rec timestamptz) RETURNS void LANGUAGE plpgsql AS $$
DECLARE i public.invoices%ROWTYPE;
BEGIN
  SELECT * INTO i FROM public.invoices WHERE id = p_inv;
  INSERT INTO public.invoice_calculation_snapshots
    (tenant_id, invoice_id, billing_run_id, valid_at, recorded_at, snapshot_schema_version, formula_version,
     rate_inputs, gas_factors, wna_inputs, tax_inputs, read_inputs, customer_inputs, period_inputs, line_items)
  VALUES (i.tenant_id, i.id, i.billing_run_id, p_valid, p_rec, 'v1', 'cdx10r3',
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

-- A: original regular bill, issued.
SELECT pg_temp.inv('10000000-0000-4000-8000-00000000c801', 'A-R3', NULL, 'regular', NULL, '2025-08-01', '2025-08-31');
SELECT pg_temp.snap('10000000-0000-4000-8000-00000000c801', '2025-08-31', now());
UPDATE public.invoices SET status='pending' WHERE id='10000000-0000-4000-8000-00000000c801';
SELECT public.void_invoice('10000000-0000-4000-8000-00000000c801', '10000000-0000-4000-8000-00000000ab01', 'system_error', NULL, true);

-- Target for A on run R.
INSERT INTO public.correction_run_targets (id, tenant_id, billing_run_id, voided_invoice_id, meter_id, customer_id, rate_date_mode)
VALUES ('10000000-0000-4000-8000-00000000d801', '10000000-0000-4000-8000-00000000aa01', '10000000-0000-4000-8000-00000000b801', '10000000-0000-4000-8000-00000000c801', '10000000-0000-4000-8000-00000000ae01', '10000000-0000-4000-8000-00000000ac01', 'historical');

-- B: correction replacing A, issued.
SELECT pg_temp.inv('10000000-0000-4000-8000-00000000c802', 'B-R3', '10000000-0000-4000-8000-00000000b801', 'correction', '10000000-0000-4000-8000-00000000c801', '2025-08-01', '2025-08-31');
SELECT pg_temp.snap('10000000-0000-4000-8000-00000000c802', '2025-08-31', now());
UPDATE public.invoices SET status='pending' WHERE id='10000000-0000-4000-8000-00000000c802';
DO $$ BEGIN RAISE NOTICE 'B issued as the live correction of A'; END $$;

-- Void B.
SELECT public.void_invoice('10000000-0000-4000-8000-00000000c802', '10000000-0000-4000-8000-00000000ab01', 'system_error', NULL, true);

-- Target for B on run R (a second correction, of B this time).
INSERT INTO public.correction_run_targets (id, tenant_id, billing_run_id, voided_invoice_id, meter_id, customer_id, rate_date_mode)
VALUES ('10000000-0000-4000-8000-00000000d802', '10000000-0000-4000-8000-00000000aa01', '10000000-0000-4000-8000-00000000b801', '10000000-0000-4000-8000-00000000c802', '10000000-0000-4000-8000-00000000ae01', '10000000-0000-4000-8000-00000000ac01', 'historical');

-- C: correction replacing B (chain: C -> B -> A). Should succeed -- the binding only checks B.
SELECT pg_temp.inv('10000000-0000-4000-8000-00000000c803', 'C-R3', '10000000-0000-4000-8000-00000000b801', 'correction', '10000000-0000-4000-8000-00000000c802', '2025-08-01', '2025-08-31');
DO $$
BEGIN
  PERFORM pg_temp.snap('10000000-0000-4000-8000-00000000c803', '2025-08-31', now());
  RAISE NOTICE 'R3 CHAIN: C (replacing void B, which replaced void A) snapshotted OK -- one-hop binding confirmed';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'R3 CHAIN RESULT: C refused -- %', SQLERRM;
END $$;
UPDATE public.invoices SET status='pending' WHERE id='10000000-0000-4000-8000-00000000c803';

-- D: a SEPARATE correction directly replacing A (the ROOT), while C (replacing B, not A) is
-- ALREADY live. B is void, so "one live correction of A" sees nothing blocking D. Does the
-- DB let two live corrections (C replacing B, D replacing A) both stand for the same lineage?
SELECT pg_temp.inv('10000000-0000-4000-8000-00000000c804', 'D-R3', '10000000-0000-4000-8000-00000000b801', 'correction', '10000000-0000-4000-8000-00000000c801', '2025-08-01', '2025-08-31');
DO $$
BEGIN
  PERFORM pg_temp.snap('10000000-0000-4000-8000-00000000c804', '2025-08-31', now());
  RAISE NOTICE 'R3 DUP-CHAIN RESULT: D (replacing A directly) snapshotted OK WHILE C (replacing B, live) also stands -- TWO live corrections for one lineage root, if true';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'R3 DUP-CHAIN: D refused -- %', SQLERRM;
END $$;

-- Confirm final live state: which corrections are non-void and what they replace.
SELECT invoice_number, status, replaces_invoice_id FROM public.invoices WHERE tenant_id='10000000-0000-4000-8000-00000000aa01' ORDER BY invoice_number;

ROLLBACK;
