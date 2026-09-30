-- ============================================================================
BEGIN;
SET CONSTRAINTS ALL IMMEDIATE;

-- ------------------------------------------------------------------ fixtures
INSERT INTO public.tenants (id, name, slug, cutover_date) VALUES
  ('00000000-0000-4000-8000-0000000013a1', 'T1 Gasco', 'bat13p-t1', DATE '2026-01-15'),
  ('00000000-0000-4000-8000-0000000013a2', 'T2 Gasco', 'bat13p-t2', DATE '2026-01-15');
INSERT INTO public.users (id, tenant_id, display_name, email, role) VALUES
  ('00000000-0000-4000-8000-0000000013b1', '00000000-0000-4000-8000-0000000013a1', 'Op1', 'op1@bat13p.test', 'operator'),
  ('00000000-0000-4000-8000-0000000013b2', '00000000-0000-4000-8000-0000000013a2', 'Op2', 'op2@bat13p.test', 'operator'),
  ('00000000-0000-4000-8000-0000000013b3', '00000000-0000-4000-8000-0000000013a1', 'Sup1', 'sup1@bat13p.test', 'tenant_admin'),
  ('00000000-0000-4000-8000-0000000013b9', '00000000-0000-4000-8000-0000000013a1', 'Platform', 'pa@bat13p.test', 'platform_admin');
INSERT INTO public.customers (id, tenant_id, customer_number, customer_type) VALUES
  ('00000000-0000-4000-8000-0000000013c1', '00000000-0000-4000-8000-0000000013a1', 'B13P-C1', 'residential'),
  ('00000000-0000-4000-8000-0000000013c9', '00000000-0000-4000-8000-0000000013a2', 'B13P-C9', 'residential');
INSERT INTO public.service_locations (id, tenant_id, customer_id, location_number, address_line1, city, state, zip) VALUES
  ('00000000-0000-4000-8000-0000000013d1', '00000000-0000-4000-8000-0000000013a1', '00000000-0000-4000-8000-0000000013c1', 'L1', '1 Main', 'Austin', 'TX', '78701'),
  ('00000000-0000-4000-8000-0000000013d6', '00000000-0000-4000-8000-0000000013a1', '00000000-0000-4000-8000-0000000013c1', 'L6', '6 Main', 'Austin', 'TX', '78706'),
  ('00000000-0000-4000-8000-0000000013d9', '00000000-0000-4000-8000-0000000013a2', '00000000-0000-4000-8000-0000000013c9', 'L9', '9 Main', 'Austin', 'TX', '78709');
INSERT INTO public.meters (id, tenant_id, meter_number, location_id, service_type, start_date, status) VALUES
  ('00000000-0000-4000-8000-0000000013e1', '00000000-0000-4000-8000-0000000013a1', 'M-FAST',  '00000000-0000-4000-8000-0000000013d1', 'gas', DATE '2024-01-01', 'active'),
  ('00000000-0000-4000-8000-0000000013e2', '00000000-0000-4000-8000-0000000013a1', 'M-SLOW',  '00000000-0000-4000-8000-0000000013d1', 'gas', DATE '2024-01-01', 'active'),
  ('00000000-0000-4000-8000-0000000013e8', '00000000-0000-4000-8000-0000000013a1', 'M-DISC',  '00000000-0000-4000-8000-0000000013d1', 'gas', DATE '2024-01-01', 'active'),
  ('00000000-0000-4000-8000-0000000013e9', '00000000-0000-4000-8000-0000000013a1', 'M-PRED',  '00000000-0000-4000-8000-0000000013d6', 'gas', DATE '2024-01-01', 'active'),
  ('00000000-0000-4000-8000-0000000013ee', '00000000-0000-4000-8000-0000000013a1', 'M-OLD',   '00000000-0000-4000-8000-0000000013d1', 'gas', DATE '2024-01-01', 'active'),
  ('00000000-0000-4000-8000-0000000013e0', '00000000-0000-4000-8000-0000000013a2', 'M-T2',    '00000000-0000-4000-8000-0000000013d9', 'gas', DATE '2024-01-01', 'active');
INSERT INTO public.service_location_acquisitions (tenant_id, location_id, predecessor_name, acquired_on, evidence_ref) VALUES
  ('00000000-0000-4000-8000-0000000013a1', '00000000-0000-4000-8000-0000000013d6', 'Old Creek Gas Co', DATE '2026-03-01', 'Deed 2026-114');

CREATE FUNCTION pg_temp.ld(p_point text, p_std numeric, p_met numeric) RETURNS jsonb LANGUAGE sql IMMUTABLE AS $$
  SELECT jsonb_build_object('load_point', p_point, 'standard_volume', p_std, 'meter_volume', p_met);
$$;
CREATE FUNCTION pg_temp.rec(p_meter uuid, p_date date, p_met numeric, p_supersedes uuid DEFAULT NULL) RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE v_id uuid;
BEGIN
  INSERT INTO public.meter_tests (tenant_id, meter_id, test_date, test_kind, record_basis,
        performed_by_name, test_equipment, meter_serial_at_test, multiplier_at_test,
        load_results, supersedes_test_id, supersede_reason)
  SELECT m.tenant_id, p_meter, p_date, 'periodic', 'recorded',
        'A. Tester', 'Bell prover BP-7', 'SN-' || left(p_meter::text, 4), 1.0,
        jsonb_build_array(pg_temp.ld('check', 100, p_met)), p_supersedes,
        CASE WHEN p_supersedes IS NOT NULL THEN 'battery correction' END
    FROM public.meters m WHERE m.id = p_meter
  RETURNING id INTO v_id;
  RETURN v_id;
END $$;
CREATE FUNCTION pg_temp.snap(p_inv uuid, p_valid date, p_rec timestamptz) RETURNS void LANGUAGE plpgsql AS $$
DECLARE i public.invoices%ROWTYPE;
BEGIN
  SELECT * INTO i FROM public.invoices WHERE id = p_inv;
  INSERT INTO public.invoice_calculation_snapshots
    (tenant_id, invoice_id, billing_run_id, valid_at, recorded_at, snapshot_schema_version, formula_version,
     rate_inputs, gas_factors, wna_inputs, tax_inputs, read_inputs, customer_inputs, period_inputs, line_items)
  VALUES (i.tenant_id, i.id, i.billing_run_id, p_valid, p_rec, 'v1', 'bat13p',
     '{"rate_schedule_id":null,"rate_schedule_version_id":null,"rate_schedule_code":null,"customer_type":null,"partial_period_policy":null,"items":[]}',
     '{"pga_factor":null,"btu_factor":null,"pressure_factor":null,"temperature_factor":null,"meter_multiplier":null,"factor_stack_intermediates":{}}',
     '{"applied":false}', '{"jurisdictions":[],"exemptions":[],"franchise_fees":[]}', '{"reads":[]}',
     jsonb_build_object('customer_id', i.customer_id, 'customer_class', null, 'location_id', i.location_id, 'premise_zones', '{}'::jsonb),
     jsonb_build_object('period_start', i.period_start, 'period_end', i.period_end, 'days_in_period', i.period_end - i.period_start + 1, 'proration_policy', null),
     (SELECT coalesce(jsonb_agg(jsonb_build_object('invoice_line_item_id', l.id, 'charge_type', l.charge_type, 'amount', l.amount)), '[]'::jsonb)
        FROM public.invoice_line_items l WHERE l.invoice_id = i.id));
END $$;
INSERT INTO public.billing_runs (id, tenant_id, run_number, billing_period, period_start, period_end, run_type, status, started_at) VALUES
  ('00000000-0000-4000-8000-0000000013ff', '00000000-0000-4000-8000-0000000013a1', 'R-FIXTURE', '2026-01', '2026-01-01', '2026-08-31', 'regular', 'in_progress', '2025-01-01 09:00-05');
-- bill(): an ISSUED fixture bill with one usage line on a meter. Owner only.
CREATE FUNCTION pg_temp.bill(p_meter uuid, p_customer uuid, p_location uuid, p_ps date, p_pe date,
                             p_units numeric DEFAULT 100, p_amount numeric DEFAULT 50) RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE v_id uuid := public.uuid_generate_v4(); v_t uuid;
BEGIN
  SELECT tenant_id INTO v_t FROM public.meters WHERE id = p_meter;
  INSERT INTO public.invoices (id, tenant_id, invoice_number, billing_run_id, customer_id, location_id, invoice_type,
                               invoice_date, billing_period, period_start, period_end, due_date, amount_due)
  VALUES (v_id, v_t, 'B13P-' || left(v_id::text, 8), '00000000-0000-4000-8000-0000000013ff', p_customer, p_location, 'regular',
          p_pe + 1, to_char(p_pe, 'YYYY-MM'), p_ps, p_pe, p_pe + 21, p_amount);
  INSERT INTO public.invoice_line_items (tenant_id, invoice_id, service_type, charge_type, description, amount, meter_id, usage_quantity)
  VALUES (v_t, v_id, 'gas', 'usage_charge', 'Gas', p_amount, p_meter, p_units);
  PERFORM pg_temp.snap(v_id, p_pe, now());
  SET LOCAL session_replication_role = replica;
  UPDATE public.invoices SET status = 'sent', first_issued_at = now() WHERE id = v_id;
  SET LOCAL session_replication_role = origin;
  RETURN v_id;
END $$;
GRANT EXECUTE ON FUNCTION pg_temp.ld(text, numeric, numeric) TO tally_app;
GRANT EXECUTE ON FUNCTION pg_temp.rec(uuid, date, numeric, uuid) TO tally_app;

CREATE TEMP TABLE b13 (k text PRIMARY KEY, id uuid);
GRANT SELECT, INSERT, UPDATE ON b13 TO tally_app;
CREATE FUNCTION pg_temp.id(p_k text) RETURNS uuid LANGUAGE sql STABLE AS $$ SELECT id FROM b13 WHERE k = p_k $$;
GRANT EXECUTE ON FUNCTION pg_temp.id(text) TO tally_app;
-- r(): the TX gas rule row for a class and cause.
CREATE FUNCTION pg_temp.r(p_class text, p_cause text) RETURNS uuid LANGUAGE sql STABLE AS $$
  SELECT id FROM public.backbilling_rules
   WHERE state_code = 'TX' AND service_type = 'gas' AND customer_class = p_class AND cause = p_cause
     AND effective_to IS NULL
$$;
GRANT EXECUTE ON FUNCTION pg_temp.r(text, text) TO tally_app;

-- Two issued bills on M-FAST (for evidence rows), one on M-DISC.
INSERT INTO b13 VALUES
  ('inv_f1', pg_temp.bill('00000000-0000-4000-8000-0000000013e1', '00000000-0000-4000-8000-0000000013c1', '00000000-0000-4000-8000-0000000013d1', DATE '2026-03-01', DATE '2026-03-31')),
  ('inv_f2', pg_temp.bill('00000000-0000-4000-8000-0000000013e1', '00000000-0000-4000-8000-0000000013c1', '00000000-0000-4000-8000-0000000013d1', DATE '2026-04-01', DATE '2026-04-30')),
  ('inv_d1', pg_temp.bill('00000000-0000-4000-8000-0000000013e8', '00000000-0000-4000-8000-0000000013c1', '00000000-0000-4000-8000-0000000013d1', DATE '2026-04-01', DATE '2026-04-30'));
INSERT INTO b13 SELECT 'dep_' || right(meter_id::text, 2), id FROM public.meter_deployments
 WHERE tenant_id = '00000000-0000-4000-8000-0000000013a1';
-- The old meter came out for tamper (owner, the migration path).
UPDATE public.meter_deployments SET removal_date = DATE '2026-03-01', removal_reason = 'tamper'
 WHERE meter_id = '00000000-0000-4000-8000-0000000013ee';
