-- ============================================================================
-- BATTERY v5.4.2-13 — A-2 backbilling caps, re-drafted to Kyle R-32…R-39
-- Run: psql -U tally -d <db-with-patch> -v ON_ERROR_STOP=1 -f battery-13.sql
-- One transaction, rolled back. Negative cases inside DO blocks that check
-- the SQLSTATE and contain no setup of their own. Written as tally_app
-- except fixtures (the owner) and the owner-level checks a group names.
-- TWO tenants throughout.
--
-- NOTE ON THE ENVIRONMENT (A-23 1g): the clone HOLDS TEMP, which the deployed
-- database revokes, so the pg_temp helpers work here and would not there.
-- Fixture bills are issued by the owner under session_replication_role =
-- replica (the migration path); group D issues through the real triggers.
--
--   A  tenant settings and supervisors            (sections 1-2)
--   B  deployments are evidence                   (section 4)
--   C  the cap table is platform-held             (section 5)
--   D  the void-and-reissue path, narrowed        (section 6; R-33, R-39)
--   E  the case: derivation, gates, log           (section 8; R-38, R-39)
--   F  the evaluation: window, periods, evidence  (section 9; R-32…R-37)
--   G  the R-36 approval                          (section 10)
--   H  holds                                      (section 11; R-37(c))
--   I  the freeze and the test couplings          (sections 12-13; R-38, D-5)
--   J  standing surfaces                          (section 14)
--   K  tenancy
--   L  AC-32 raises on planted drift
-- ============================================================================
BEGIN;
SET CONSTRAINTS ALL IMMEDIATE;

-- ------------------------------------------------------------------ fixtures
-- T1 cut over 2026-01-15: an anchor of 2026-06-15 reaches back to 2025-12-15,
-- before cutover (R-36 gate live); an anchor of 2026-08-20 reaches 2026-02-20,
-- after it (gate lapsed).
INSERT INTO public.tenants (id, name, slug, cutover_date) VALUES
  ('00000000-0000-4000-8000-0000000013a1', 'T1 Gasco', 'bat13-t1', DATE '2026-01-15'),
  ('00000000-0000-4000-8000-0000000013a2', 'T2 Gasco', 'bat13-t2', DATE '2026-01-15');
INSERT INTO public.users (id, tenant_id, display_name, email, role) VALUES
  ('00000000-0000-4000-8000-0000000013b1', '00000000-0000-4000-8000-0000000013a1', 'Op1', 'op1@bat13.test', 'operator'),
  ('00000000-0000-4000-8000-0000000013b2', '00000000-0000-4000-8000-0000000013a2', 'Op2', 'op2@bat13.test', 'operator'),
  ('00000000-0000-4000-8000-0000000013b3', '00000000-0000-4000-8000-0000000013a1', 'Sup1', 'sup1@bat13.test', 'tenant_admin'),
  ('00000000-0000-4000-8000-0000000013b4', '00000000-0000-4000-8000-0000000013a1', 'Sup2', 'sup2@bat13.test', 'tenant_admin'),
  ('00000000-0000-4000-8000-0000000013b9', '00000000-0000-4000-8000-0000000013a1', 'Platform', 'pa@bat13.test', 'platform_admin');
INSERT INTO public.customers (id, tenant_id, customer_number, customer_type) VALUES
  ('00000000-0000-4000-8000-0000000013c1', '00000000-0000-4000-8000-0000000013a1', 'B13-C1', 'residential'),
  ('00000000-0000-4000-8000-0000000013c2', '00000000-0000-4000-8000-0000000013a1', 'B13-C2', 'residential'),
  ('00000000-0000-4000-8000-0000000013c3', '00000000-0000-4000-8000-0000000013a1', 'B13-C3', 'large_commercial'),
  ('00000000-0000-4000-8000-0000000013c4', '00000000-0000-4000-8000-0000000013a1', 'B13-C4', 'commercial'),
  ('00000000-0000-4000-8000-0000000013c9', '00000000-0000-4000-8000-0000000013a2', 'B13-C9', 'residential');
INSERT INTO public.jurisdictions (id, tenant_id, jurisdiction_code, jurisdiction_name) VALUES
  ('00000000-0000-4000-8000-0000000013f1', '00000000-0000-4000-8000-0000000013a1', 'CITYA', 'City A'),
  ('00000000-0000-4000-8000-0000000013f2', '00000000-0000-4000-8000-0000000013a1', 'CITYB', 'City B');
INSERT INTO public.service_locations (id, tenant_id, customer_id, location_number, address_line1, city, state, zip) VALUES
  ('00000000-0000-4000-8000-0000000013d1', '00000000-0000-4000-8000-0000000013a1', '00000000-0000-4000-8000-0000000013c1', 'L1', '1 Main', 'Austin', 'TX', '78701'),
  ('00000000-0000-4000-8000-0000000013d2', '00000000-0000-4000-8000-0000000013a1', '00000000-0000-4000-8000-0000000013c2', 'L2', '2 Main', 'Austin', 'TX', '78702'),
  ('00000000-0000-4000-8000-0000000013d3', '00000000-0000-4000-8000-0000000013a1', '00000000-0000-4000-8000-0000000013c1', 'L3', '3 Main', 'Austin', 'TX', '78703'),
  ('00000000-0000-4000-8000-0000000013d6', '00000000-0000-4000-8000-0000000013a1', '00000000-0000-4000-8000-0000000013c1', 'L6', '6 Main', 'Austin', 'TX', '78706'),
  ('00000000-0000-4000-8000-0000000013d9', '00000000-0000-4000-8000-0000000013a2', '00000000-0000-4000-8000-0000000013c9', 'L9', '9 Main', 'Austin', 'TX', '78709');
-- Meters, by scenario:
--   e1 FAST  (legacy hold)            e2 SLOW  (prior accurate test)
--   e3 GATE  (slow, no prior test)    e4 DEPLOY (fast, deployment bound)
--   e5 LATE  (fast, late deployment)  e6 LAPSE (slow 08-20, gate lapsed)
--   e7 NONREG                         e8 DISC  (discovery cause)
--   e9 PRED  (predecessor hold, L6)   ea TAMPER
--   ec date-only migrated slow        ed rebill scenarios (L3)
--   e0 T2's meter
-- Every meter's first deployment is created by sync_meter_deployments() from
-- meters.start_date. e1's start is its ONBOARDING date (after cutover, no
-- predecessor meter) — the case R-37(a) must not honour for a refund.
-- e4 went in on 2026-03-01 replacing eP; e7 (adverse) started 2026-03-20;
-- e5 and eb start inactive, so their deployments are written by hand.
INSERT INTO public.meters (id, tenant_id, meter_number, location_id, service_type, start_date, status) VALUES
  ('00000000-0000-4000-8000-0000000013e1', '00000000-0000-4000-8000-0000000013a1', 'M-FAST',   '00000000-0000-4000-8000-0000000013d1', 'gas', DATE '2026-01-20', 'active'),
  ('00000000-0000-4000-8000-0000000013e2', '00000000-0000-4000-8000-0000000013a1', 'M-SLOW',   '00000000-0000-4000-8000-0000000013d1', 'gas', DATE '2024-01-01', 'active'),
  ('00000000-0000-4000-8000-0000000013e3', '00000000-0000-4000-8000-0000000013a1', 'M-GATE',   '00000000-0000-4000-8000-0000000013d1', 'gas', DATE '2024-01-01', 'active'),
  ('00000000-0000-4000-8000-0000000013e4', '00000000-0000-4000-8000-0000000013a1', 'M-DEPLOY', '00000000-0000-4000-8000-0000000013d1', 'gas', DATE '2026-03-01', 'active'),
  ('00000000-0000-4000-8000-0000000013e5', '00000000-0000-4000-8000-0000000013a1', 'M-LATE',   '00000000-0000-4000-8000-0000000013d1', 'gas', DATE '2024-01-01', 'inactive'),
  ('00000000-0000-4000-8000-0000000013e6', '00000000-0000-4000-8000-0000000013a1', 'M-LAPSE',  '00000000-0000-4000-8000-0000000013d1', 'gas', DATE '2024-01-01', 'active'),
  ('00000000-0000-4000-8000-0000000013e7', '00000000-0000-4000-8000-0000000013a1', 'M-NONREG', '00000000-0000-4000-8000-0000000013d1', 'gas', DATE '2026-03-20', 'active'),
  ('00000000-0000-4000-8000-0000000013e8', '00000000-0000-4000-8000-0000000013a1', 'M-DISC',   '00000000-0000-4000-8000-0000000013d1', 'gas', DATE '2024-01-01', 'active'),
  ('00000000-0000-4000-8000-0000000013e9', '00000000-0000-4000-8000-0000000013a1', 'M-PRED',   '00000000-0000-4000-8000-0000000013d6', 'gas', DATE '2024-01-01', 'active'),
  ('00000000-0000-4000-8000-0000000013ea', '00000000-0000-4000-8000-0000000013a1', 'M-TAMPER', '00000000-0000-4000-8000-0000000013d1', 'gas', DATE '2024-01-01', 'active'),
  ('00000000-0000-4000-8000-0000000013eb', '00000000-0000-4000-8000-0000000013a1', 'M-BLANK',  '00000000-0000-4000-8000-0000000013d1', 'gas', DATE '2024-01-01', 'inactive'),
  ('00000000-0000-4000-8000-0000000013ec', '00000000-0000-4000-8000-0000000013a1', 'M-DATEONLY','00000000-0000-4000-8000-0000000013d1', 'gas', DATE '2024-01-01', 'active'),
  ('00000000-0000-4000-8000-0000000013ed', '00000000-0000-4000-8000-0000000013a1', 'M-REBILL', '00000000-0000-4000-8000-0000000013d3', 'gas', DATE '2024-01-01', 'active'),
  ('00000000-0000-4000-8000-0000000013ee', '00000000-0000-4000-8000-0000000013a1', 'M-PRE-E4', '00000000-0000-4000-8000-0000000013d1', 'gas', DATE '2024-01-01', 'active'),
  ('00000000-0000-4000-8000-0000000013ef', '00000000-0000-4000-8000-0000000013a1', 'M-PRE-E5', '00000000-0000-4000-8000-0000000013d1', 'gas', DATE '2024-01-01', 'active'),
  ('00000000-0000-4000-8000-0000000013e0', '00000000-0000-4000-8000-0000000013a2', 'M-T2',     '00000000-0000-4000-8000-0000000013d9', 'gas', DATE '2024-01-01', 'active');

SELECT public.seed_backbilling_cap_defaults('00000000-0000-4000-8000-0000000013a1');
SELECT public.seed_backbilling_cap_defaults('00000000-0000-4000-8000-0000000013a2');

-- The predecessor meters came out when e4 (03-01) and e5 (04-01) went in;
-- ea was removed for tamper. Owner writes (the migration path).
UPDATE public.meter_deployments SET removal_date = DATE '2026-03-01', removal_reason = 'tamper'
 WHERE meter_id = '00000000-0000-4000-8000-0000000013ee';
UPDATE public.meter_deployments SET removal_date = DATE '2026-04-01', removal_reason = 'upgrade_size'
 WHERE meter_id = '00000000-0000-4000-8000-0000000013ef';
UPDATE public.meter_deployments SET removal_date = DATE '2026-05-01', removal_reason = 'tamper'
 WHERE meter_id = '00000000-0000-4000-8000-0000000013ea';
-- L6 was acquired from a neighbouring system on 2026-03-01.
INSERT INTO public.service_location_acquisitions (tenant_id, location_id, predecessor_name, acquired_on, evidence_ref) VALUES
  ('00000000-0000-4000-8000-0000000013a1', '00000000-0000-4000-8000-0000000013d6', 'Old Creek Gas Co', DATE '2026-03-01', 'Deed 2026-114');

-- Helpers. ld()/rec(): a recorded test with readings (battery-12's shape).
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
  VALUES (i.tenant_id, i.id, i.billing_run_id, p_valid, p_rec, 'v1', 'bat13',
     '{"rate_schedule_id":null,"rate_schedule_version_id":null,"rate_schedule_code":null,"customer_type":null,"partial_period_policy":null,"items":[]}',
     '{"pga_factor":null,"btu_factor":null,"pressure_factor":null,"temperature_factor":null,"meter_multiplier":null,"factor_stack_intermediates":{}}',
     '{"applied":false}', '{"jurisdictions":[],"exemptions":[],"franchise_fees":[]}', '{"reads":[]}',
     jsonb_build_object('customer_id', i.customer_id, 'customer_class', null, 'location_id', i.location_id, 'premise_zones', '{}'::jsonb),
     jsonb_build_object('period_start', i.period_start, 'period_end', i.period_end, 'days_in_period', i.period_end - i.period_start + 1, 'proration_policy', null),
     (SELECT coalesce(jsonb_agg(jsonb_build_object('invoice_line_item_id', l.id, 'charge_type', l.charge_type, 'amount', l.amount)), '[]'::jsonb)
        FROM public.invoice_line_items l WHERE l.invoice_id = i.id));
END $$;
GRANT EXECUTE ON FUNCTION pg_temp.snap(uuid, date, timestamptz) TO tally_app;
INSERT INTO public.billing_runs (id, tenant_id, run_number, billing_period, period_start, period_end, run_type, status, started_at) VALUES
  ('00000000-0000-4000-8000-0000000013ff', '00000000-0000-4000-8000-0000000013a1', 'R-FIXTURE', '2025-12', '2025-12-01', '2026-08-31', 'regular', 'in_progress', '2024-01-01 09:00-05');
-- bill(): an ISSUED fixture bill with one usage line on a meter. Owner only.
CREATE FUNCTION pg_temp.bill(p_meter uuid, p_customer uuid, p_location uuid, p_ps date, p_pe date,
                             p_units numeric DEFAULT 100) RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE v_id uuid := public.uuid_generate_v4(); v_t uuid;
BEGIN
  SELECT tenant_id INTO v_t FROM public.meters WHERE id = p_meter;
  INSERT INTO public.invoices (id, tenant_id, invoice_number, billing_run_id, customer_id, location_id, invoice_type,
                               invoice_date, billing_period, period_start, period_end, due_date, amount_due)
  VALUES (v_id, v_t, 'B13-' || left(v_id::text, 8), '00000000-0000-4000-8000-0000000013ff', p_customer, p_location, 'regular',
          p_pe + 1, to_char(p_pe, 'YYYY-MM'), p_ps, p_pe, p_pe + 21, 50);
  INSERT INTO public.invoice_line_items (tenant_id, invoice_id, service_type, charge_type, description, amount, meter_id, usage_quantity)
  VALUES (v_t, v_id, 'gas', 'usage_charge', 'Gas', 50, p_meter, p_units);
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
INSERT INTO b13 SELECT 'dep_' || right(meter_id::text, 2), id FROM public.meter_deployments
 WHERE tenant_id = '00000000-0000-4000-8000-0000000013a1';
-- amounts(): {invoice_id: amount} for a case's billed periods, in period
-- order, from an array of amounts.
CREATE FUNCTION pg_temp.amounts(p_case uuid, p_vals numeric[]) RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE r jsonb := '{}'::jsonb; i int := 0; x jsonb;
BEGIN
  FOR x IN SELECT p FROM jsonb_array_elements(public.meter_correction_inputs(p_case) -> 'periods') AS p
            ORDER BY (p ->> 'period_start')::date, p ->> 'invoice_id' LOOP
    i := i + 1;
    r := r || jsonb_build_object(x ->> 'invoice_id', p_vals[i]);
  END LOOP;
  RETURN r;
END $$;
GRANT EXECUTE ON FUNCTION pg_temp.amounts(uuid, numeric[]) TO tally_app;
-- ev(): evaluate a case, return the evaluation id.
CREATE FUNCTION pg_temp.ev(p_case uuid, p_vals numeric[]) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v uuid;
BEGIN
  INSERT INTO public.meter_correction_evaluations (tenant_id, case_id, submitted_amounts)
  SELECT tenant_id, p_case, pg_temp.amounts(p_case, p_vals) FROM public.meter_correction_cases WHERE id = p_case
  RETURNING id INTO v;
  RETURN v;
END $$;
GRANT EXECUTE ON FUNCTION pg_temp.ev(uuid, numeric[]) TO tally_app;

-- Fixture bills (owner). e1 FAST: Tally billed it from cutover (01-15) on;
-- February was billed to ANOTHER customer at ANOTHER premise (R-37(b)).
SELECT pg_temp.bill('00000000-0000-4000-8000-0000000013e1', '00000000-0000-4000-8000-0000000013c1', '00000000-0000-4000-8000-0000000013d1', '2026-01-15', '2026-01-31');
INSERT INTO b13 VALUES ('e1_feb', pg_temp.bill('00000000-0000-4000-8000-0000000013e1', '00000000-0000-4000-8000-0000000013c2', '00000000-0000-4000-8000-0000000013d2', '2026-02-01', '2026-02-28'));
SELECT pg_temp.bill('00000000-0000-4000-8000-0000000013e1', '00000000-0000-4000-8000-0000000013c1', '00000000-0000-4000-8000-0000000013d1', ps, (ps + interval '1 month' - interval '1 day')::date)
  FROM (VALUES (DATE '2026-03-01'), (DATE '2026-04-01'), (DATE '2026-05-01'), (DATE '2026-06-01')) v(ps);
-- e2 SLOW, e4 DEPLOY: Jan15 (e4 only) and Feb..Jun.
SELECT pg_temp.bill(m, '00000000-0000-4000-8000-0000000013c1', '00000000-0000-4000-8000-0000000013d1', ps, (ps + interval '1 month' - interval '1 day')::date)
  FROM (VALUES ('00000000-0000-4000-8000-0000000013e2'::uuid), ('00000000-0000-4000-8000-0000000013e4'::uuid)) mm(m),
       (VALUES (DATE '2026-02-01'), (DATE '2026-03-01'), (DATE '2026-04-01'), (DATE '2026-05-01'), (DATE '2026-06-01')) v(ps);
-- e3 GATE: Apr..Jun. e7 NONREG: Mar..Jun. e9 PRED at L6: a loaded legacy
-- bill for 2025-12-15..12-31, then Apr..Jun — so January to March is unbilled.
SELECT pg_temp.bill('00000000-0000-4000-8000-0000000013e3', '00000000-0000-4000-8000-0000000013c1', '00000000-0000-4000-8000-0000000013d1', ps, (ps + interval '1 month' - interval '1 day')::date)
  FROM (VALUES (DATE '2026-04-01'), (DATE '2026-05-01'), (DATE '2026-06-01')) v(ps);
SELECT pg_temp.bill('00000000-0000-4000-8000-0000000013e7', '00000000-0000-4000-8000-0000000013c1', '00000000-0000-4000-8000-0000000013d1', ps, (ps + interval '1 month' - interval '1 day')::date)
  FROM (VALUES (DATE '2026-03-01'), (DATE '2026-04-01'), (DATE '2026-05-01'), (DATE '2026-06-01')) v(ps);
SELECT pg_temp.bill('00000000-0000-4000-8000-0000000013e9', '00000000-0000-4000-8000-0000000013c1', '00000000-0000-4000-8000-0000000013d6', '2025-12-15', '2025-12-31');
SELECT pg_temp.bill('00000000-0000-4000-8000-0000000013e9', '00000000-0000-4000-8000-0000000013c1', '00000000-0000-4000-8000-0000000013d6', ps, (ps + interval '1 month' - interval '1 day')::date)
  FROM (VALUES (DATE '2026-04-01'), (DATE '2026-05-01'), (DATE '2026-06-01')) v(ps);
-- e5 LATE: one December bill, straddling the 2025-12-15 window.
SELECT pg_temp.bill('00000000-0000-4000-8000-0000000013e5', '00000000-0000-4000-8000-0000000013c1', '00000000-0000-4000-8000-0000000013d1', '2025-12-01', '2025-12-31');
-- e6 LAPSE: Jul, Aug. e8 DISC: Feb..May.
SELECT pg_temp.bill('00000000-0000-4000-8000-0000000013e6', '00000000-0000-4000-8000-0000000013c1', '00000000-0000-4000-8000-0000000013d1', ps, (ps + interval '1 month' - interval '1 day')::date)
  FROM (VALUES (DATE '2026-07-01'), (DATE '2026-08-01')) v(ps);
SELECT pg_temp.bill('00000000-0000-4000-8000-0000000013e8', '00000000-0000-4000-8000-0000000013c1', '00000000-0000-4000-8000-0000000013d1', ps, (ps + interval '1 month' - interval '1 day')::date)
  FROM (VALUES (DATE '2026-02-01'), (DATE '2026-03-01'), (DATE '2026-04-01'), (DATE '2026-05-01')) v(ps);

SET LOCAL app.user_id = '00000000-0000-4000-8000-0000000013b1';
SET ROLE tally_app;

-- Tests (as tally_app, via the -12 path).
INSERT INTO b13 VALUES
  ('t_e1',  pg_temp.rec('00000000-0000-4000-8000-0000000013e1', DATE '2026-06-15', 103)),
  ('t_e2p', pg_temp.rec('00000000-0000-4000-8000-0000000013e2', DATE '2026-03-10', 100.5)),
  ('t_e2',  pg_temp.rec('00000000-0000-4000-8000-0000000013e2', DATE '2026-06-15', 97)),
  ('t_e3',  pg_temp.rec('00000000-0000-4000-8000-0000000013e3', DATE '2026-06-15', 97)),
  ('t_e4',  pg_temp.rec('00000000-0000-4000-8000-0000000013e4', DATE '2026-06-15', 103)),
  ('t_e5',  pg_temp.rec('00000000-0000-4000-8000-0000000013e5', DATE '2026-06-15', 103)),
  ('t_e6',  pg_temp.rec('00000000-0000-4000-8000-0000000013e6', DATE '2026-08-20', 97)),
  ('t_e7',  pg_temp.rec('00000000-0000-4000-8000-0000000013e7', DATE '2026-06-15', 0)),
  ('t_e9',  pg_temp.rec('00000000-0000-4000-8000-0000000013e9', DATE '2026-06-15', 103));
-- ec: a date-only migrated "slow" (asserted, no readings), before cutover.
INSERT INTO public.meter_tests (id, tenant_id, meter_id, test_date, test_kind, record_basis, outcome)
VALUES ('00000000-0000-4000-8000-0000000013fc', '00000000-0000-4000-8000-0000000013a1', '00000000-0000-4000-8000-0000000013ec',
        DATE '2026-01-10', 'periodic', 'migrated_date_only', 'slow');

RESET ROLE;
-- e5's deployment is entered an hour AFTER the finding (the owner supplies
-- the clock — one transaction has one now()).
INSERT INTO public.meter_deployments (tenant_id, meter_id, deployment_number, location_id, install_date, created_at)
VALUES ('00000000-0000-4000-8000-0000000013a1', '00000000-0000-4000-8000-0000000013e5', 1,
        '00000000-0000-4000-8000-0000000013d1', DATE '2026-04-01', now() + interval '1 hour');
SET ROLE tally_app;

-- ======================================================================== A
DO $$ BEGIN
  UPDATE public.tenants SET regulatory_class_mode = 'explicit_class' WHERE id = '00000000-0000-4000-8000-0000000013a1';
  RAISE EXCEPTION 'A1 FAILED: an operator moved the protection mode';
EXCEPTION WHEN insufficient_privilege THEN
  RAISE NOTICE 'PASS A1: a tenant session cannot move regulatory_class_mode (leaving the default removes §7.45 protection)'; END $$;

DO $$ DECLARE n int; BEGIN
  PERFORM set_config('app.user_id', '00000000-0000-4000-8000-0000000013b9', true);
  UPDATE public.tenants SET regulatory_class_mode = 'explicit_class' WHERE id = '00000000-0000-4000-8000-0000000013a1';
  UPDATE public.tenants SET regulatory_class_mode = 'all_non_residential_protected' WHERE id = '00000000-0000-4000-8000-0000000013a1';
  PERFORM set_config('app.user_id', '00000000-0000-4000-8000-0000000013b1', true);
  SELECT count(*) INTO n FROM public.tenant_configuration_history
   WHERE tenant_id = '00000000-0000-4000-8000-0000000013a1' AND config_key = 'regulatory_class_mode' AND change_source = 'trigger';
  IF n <> 2 THEN RAISE EXCEPTION 'A2 FAILED: % history rows', n; END IF;
  RAISE NOTICE 'PASS A2: a platform administrator may move it, and each change is recorded in tenant_configuration_history';
END $$;

DO $$ DECLARE v jsonb; BEGIN
  UPDATE public.tenants SET backbilling_adverse_limit_months = 4 WHERE id = '00000000-0000-4000-8000-0000000013a1';
  SELECT new_value INTO v FROM public.tenant_configuration_history
   WHERE tenant_id = '00000000-0000-4000-8000-0000000013a1' AND config_key = 'backbilling_adverse_limit_months' AND change_source = 'trigger';
  IF v <> '4'::jsonb THEN RAISE EXCEPTION 'A3 FAILED: history %', v; END IF;
  UPDATE public.tenants SET backbilling_adverse_limit_months = NULL WHERE id = '00000000-0000-4000-8000-0000000013a1';
  RAISE NOTICE 'PASS A3: the tenant sets its own adverse limit (R-37(d)) and the change is recorded';
END $$;
DO $$ BEGIN
  UPDATE public.tenants SET backbilling_adverse_limit_months = 0 WHERE id = '00000000-0000-4000-8000-0000000013a1';
  RAISE EXCEPTION 'A4 FAILED';
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'PASS A4: a zero-month limit is refused'; END $$;

DO $$ BEGIN
  UPDATE public.users SET role = 'tenant_admin' WHERE id = '00000000-0000-4000-8000-0000000013b1';
  RAISE EXCEPTION 'A5 FAILED: an operator promoted itself';
EXCEPTION WHEN insufficient_privilege THEN
  RAISE NOTICE 'PASS A5: an operator cannot make itself a supervisor (it could then approve its own charge)'; END $$;
DO $$ BEGIN
  INSERT INTO public.users (tenant_id, display_name, email, role)
  VALUES ('00000000-0000-4000-8000-0000000013a1', 'Sock', 'sock@bat13.test', 'tenant_admin');
  RAISE EXCEPTION 'A6 FAILED: an operator created a supervisor';
EXCEPTION WHEN insufficient_privilege THEN RAISE NOTICE 'PASS A6: nor create a new supervisor'; END $$;
DO $$ DECLARE r text; BEGIN
  PERFORM set_config('app.user_id', '00000000-0000-4000-8000-0000000013b3', true);
  INSERT INTO public.users (id, tenant_id, display_name, email, role)
  VALUES ('00000000-0000-4000-8000-0000000013b5', '00000000-0000-4000-8000-0000000013a1', 'Sup3', 'sup3@bat13.test', 'tenant_admin');
  PERFORM set_config('app.user_id', '00000000-0000-4000-8000-0000000013b1', true);
  SELECT role INTO r FROM public.users WHERE id = '00000000-0000-4000-8000-0000000013b5';
  IF r <> 'tenant_admin' THEN RAISE EXCEPTION 'A7 FAILED'; END IF;
  RAISE NOTICE 'PASS A7: a supervisor may make a supervisor';
END $$;
DO $$ BEGIN
  IF public.session_is_supervisor() THEN RAISE EXCEPTION 'A8 FAILED: operator is a supervisor'; END IF;
  PERFORM set_config('app.user_id', '00000000-0000-4000-8000-0000000013b3', true);
  IF NOT public.session_is_supervisor() THEN RAISE EXCEPTION 'A8b FAILED: tenant_admin is not'; END IF;
  PERFORM set_config('app.user_id', '00000000-0000-4000-8000-0000000013b9', true);
  IF NOT public.session_is_supervisor() THEN RAISE EXCEPTION 'A8c FAILED: platform admin is not'; END IF;
  PERFORM set_config('app.user_id', '00000000-0000-4000-8000-0000000013b1', true);
  RAISE NOTICE 'PASS A8: session_is_supervisor() — operator no, tenant_admin yes, platform administrator yes';
END $$;

-- ======================================================================== B
DO $$ BEGIN
  UPDATE public.meter_deployments SET install_date = DATE '2026-04-15' WHERE id = pg_temp.id('dep_e4');
  RAISE EXCEPTION 'B1 FAILED: an install date moved';
EXCEPTION WHEN restrict_violation THEN
  RAISE NOTICE 'PASS B1: a deployment''s install date is fixed (moving it later would shorten a refund, R-37(a))'; END $$;
DO $$ BEGIN
  UPDATE public.meter_deployments SET location_id = '00000000-0000-4000-8000-0000000013d2' WHERE id = pg_temp.id('dep_e4');
  RAISE EXCEPTION 'B2 FAILED';
EXCEPTION WHEN restrict_violation THEN RAISE NOTICE 'PASS B2: and so is its location'; END $$;
DO $$ BEGIN
  UPDATE public.meter_deployments SET removal_reason = 'other' WHERE id = pg_temp.id('dep_ea');
  RAISE EXCEPTION 'B3 FAILED: a tamper removal was relabelled';
EXCEPTION WHEN restrict_violation THEN
  RAISE NOTICE 'PASS B3: a removal reason is written once — a tamper removal is evidence (R-38 attachment 2)'; END $$;
DO $$ DECLARE c timestamptz; BEGIN
  INSERT INTO public.meter_deployments (id, tenant_id, meter_id, deployment_number, location_id, install_date, created_at)
  VALUES ('00000000-0000-4000-8000-0000000013fd', '00000000-0000-4000-8000-0000000013a1', '00000000-0000-4000-8000-0000000013eb', 1,
          '00000000-0000-4000-8000-0000000013d1', DATE '2025-06-01', '2020-01-01');
  SELECT created_at INTO c FROM public.meter_deployments WHERE id = '00000000-0000-4000-8000-0000000013fd';
  IF c <> now() THEN RAISE EXCEPTION 'B4 FAILED: created_at %', c; END IF;
  UPDATE public.meter_deployments SET removal_date = DATE '2026-02-01', removal_reason = 'end_of_life' WHERE id = '00000000-0000-4000-8000-0000000013fd';
  RAISE NOTICE 'PASS B4: a deployment''s recorded time is the database''s (a backdated created_at would make a late deployment bound an earlier finding); a removal is written once from NULL';
END $$;
DO $$ BEGIN
  UPDATE public.meter_deployments SET removal_date = DATE '2026-03-01' WHERE id = '00000000-0000-4000-8000-0000000013fd';
  RAISE EXCEPTION 'B5 FAILED';
EXCEPTION WHEN restrict_violation THEN RAISE NOTICE 'PASS B5: and does not move afterwards'; END $$;

-- ======================================================================== C
DO $$ BEGIN
  INSERT INTO public.backbilling_cap_rules (tenant_id, service_type, customer_class, cause, billable_scope, enforceable_scope, source_note)
  VALUES ('00000000-0000-4000-8000-0000000013a1', 'water', 'protected', 'meter_error', 'uncapped', 'uncapped', 'mine');
  RAISE EXCEPTION 'C1 FAILED: a tenant wrote a cap row';
EXCEPTION WHEN insufficient_privilege THEN RAISE NOTICE 'PASS C1: a tenant cannot write a cap row (the table is a reading of the statute)'; END $$;
DO $$ BEGIN
  UPDATE public.backbilling_cap_rules SET billable_scope = 'uncapped', billable_months = NULL
   WHERE tenant_id = '00000000-0000-4000-8000-0000000013a1' AND cause = 'meter_error' AND customer_class = 'protected';
  RAISE EXCEPTION 'C2 FAILED: a tenant uncapped its own meter_error row';
EXCEPTION WHEN insufficient_privilege THEN RAISE NOTICE 'PASS C2: nor uncap its own six-month meter_error row (the round-1 draft allowed it)'; END $$;
DO $$ BEGIN
  PERFORM public.seed_backbilling_cap_defaults('00000000-0000-4000-8000-0000000013a1');
  RAISE EXCEPTION 'C3 FAILED';
EXCEPTION WHEN insufficient_privilege THEN RAISE NOTICE 'PASS C3: nor run the seed'; END $$;
DO $$ DECLARE n int; BEGIN
  SELECT count(*) INTO n FROM public.backbilling_cap_rules WHERE tenant_id = '00000000-0000-4000-8000-0000000013a1';
  IF n <> 16 THEN RAISE EXCEPTION 'C4 FAILED: % rows visible', n; END IF;
  SELECT count(*) INTO n FROM public.backbilling_cap_rules WHERE cause = 'tampering_theft';
  RAISE NOTICE 'PASS C4: the tenant reads its 16 seeded rows (8 causes x 2 classes, R-39)';
END $$;

RESET ROLE;
DO $$ BEGIN
  BEGIN
    INSERT INTO public.backbilling_cap_rules (tenant_id,service_type,customer_class,cause,billable_scope,billable_months,enforceable_scope,source_note)
    VALUES ('00000000-0000-4000-8000-0000000013a1','gas','protected','meter_error','months_from_anchor',9,'never','dup');
    RAISE EXCEPTION 'C5 FAILED: a second state default';
  EXCEPTION WHEN unique_violation THEN NULL; END;
  BEGIN
    INSERT INTO public.backbilling_cap_rules (tenant_id,service_type,customer_class,cause,billable_scope,billable_months,enforceable_scope,source_note)
    VALUES ('00000000-0000-4000-8000-0000000013a1','water','protected','meter_error','uncapped',6,'never','x');
    RAISE EXCEPTION 'C5b FAILED: uncapped with months';
  EXCEPTION WHEN check_violation THEN NULL; END;
  BEGIN
    INSERT INTO public.backbilling_cap_rules (tenant_id,service_type,customer_class,cause,billable_scope,enforceable_scope,source_note)
    VALUES ('00000000-0000-4000-8000-0000000013a1','water','protected','meter_error','months_from_anchor','never','x');
    RAISE EXCEPTION 'C5c FAILED: counted scope with NULL months';
  EXCEPTION WHEN check_violation THEN NULL; END;
  BEGIN
    INSERT INTO public.backbilling_cap_rules (tenant_id,service_type,customer_class,cause,billable_scope,enforceable_scope,source_note)
    VALUES ('00000000-0000-4000-8000-0000000013a1','water','protected','other','uncapped','never','x');
    RAISE EXCEPTION 'C5d FAILED: cause other';
  EXCEPTION WHEN check_violation THEN NULL; END;
  BEGIN
    INSERT INTO public.backbilling_cap_rules (tenant_id,service_type,customer_class,cause,billable_scope,enforceable_scope,source_note)
    VALUES ('00000000-0000-4000-8000-0000000013a1','water','protected','meter_error','uncapped','never','   ');
    RAISE EXCEPTION 'C5e FAILED: blank source';
  EXCEPTION WHEN check_violation THEN NULL; END;
  RAISE NOTICE 'PASS C5: (owner) one state default per key; uncapped carries no months, a counted scope must; no cause "other" (R-39); every row cites its source';
END $$;
-- a municipal row, written by the platform (R-26)
INSERT INTO public.backbilling_cap_rules (tenant_id,jurisdiction_id,service_type,customer_class,cause,billable_scope,billable_months,enforceable_scope,source_note)
VALUES ('00000000-0000-4000-8000-0000000013a1','00000000-0000-4000-8000-0000000013f1','gas','protected','meter_error','shorter_of_months_or_last_test',4,'never','City A ordinance 12-3');
SET ROLE tally_app;
DO $$ DECLARE r public.backbilling_cap_rules; BEGIN
  r := public.backbilling_resolve_cap('00000000-0000-4000-8000-0000000013a1', '00000000-0000-4000-8000-0000000013f1', 'gas', 'protected', 'meter_error');
  IF r.billable_months <> 4 THEN RAISE EXCEPTION 'C6 FAILED: municipal %', r.billable_months; END IF;
  r := public.backbilling_resolve_cap('00000000-0000-4000-8000-0000000013a1', '00000000-0000-4000-8000-0000000013f2', 'gas', 'protected', 'meter_error');
  IF r.billable_months <> 6 THEN RAISE EXCEPTION 'C6b FAILED: other city %', r.billable_months; END IF;
  r := public.backbilling_resolve_cap('00000000-0000-4000-8000-0000000013a1', NULL, 'gas', 'protected', 'tampering_bypass');
  IF r.billable_scope <> 'uncapped' OR r.enforceable_scope <> 'uncapped' THEN RAISE EXCEPTION 'C6c FAILED'; END IF;
  r := public.backbilling_resolve_cap('00000000-0000-4000-8000-0000000013a1', NULL, 'gas', 'protected', 'crossed_meters');
  IF r.enforceable_scope <> 'never' THEN RAISE EXCEPTION 'C6d FAILED'; END IF;
  RAISE NOTICE 'PASS C6: most-specific-wins over two levels; tampering_bypass uncapped both ways; R-39''s additions enforceable never';
END $$;
DO $$ BEGIN
  PERFORM public.backbilling_resolve_cap('00000000-0000-4000-8000-0000000013a1', NULL, 'water', 'protected', 'meter_error');
  RAISE EXCEPTION 'C7 FAILED';
EXCEPTION WHEN no_data_found THEN RAISE NOTICE 'PASS C7: an unseeded service resolves to an error, never a permission'; END $$;
DO $$ BEGIN
  IF public.backbilling_customer_class('00000000-0000-4000-8000-0000000013c3') <> 'protected' THEN RAISE EXCEPTION 'C8 FAILED'; END IF;
  PERFORM set_config('app.user_id', '00000000-0000-4000-8000-0000000013b9', true);
  UPDATE public.tenants SET regulatory_class_mode = 'explicit_class' WHERE id = '00000000-0000-4000-8000-0000000013a1';
  IF public.backbilling_customer_class('00000000-0000-4000-8000-0000000013c3') <> 'unprotected' THEN RAISE EXCEPTION 'C8b FAILED'; END IF;
  IF public.backbilling_customer_class('00000000-0000-4000-8000-0000000013c4') <> 'protected' THEN RAISE EXCEPTION 'C8c FAILED'; END IF;
  UPDATE public.tenants SET regulatory_class_mode = 'volumetric_threshold' WHERE id = '00000000-0000-4000-8000-0000000013a1';
  BEGIN
    PERFORM public.backbilling_customer_class('00000000-0000-4000-8000-0000000013c1');
    RAISE EXCEPTION 'C8d FAILED';
  EXCEPTION WHEN feature_not_supported THEN NULL; END;
  UPDATE public.tenants SET regulatory_class_mode = 'all_non_residential_protected' WHERE id = '00000000-0000-4000-8000-0000000013a1';
  PERFORM set_config('app.user_id', '00000000-0000-4000-8000-0000000013b1', true);
  RAISE NOTICE 'PASS C8: default mode protects large commercial; explicit_class unprotects it and reads a bare commercial as protected; volumetric_threshold refuses';
END $$;

-- ======================================================================== D
-- The void-and-reissue path, through the REAL issuance triggers.
RESET ROLE;
CREATE FUNCTION pg_temp.inv(p_id uuid, p_num text, p_run uuid, p_type text, p_replaces uuid, p_ps date, p_pe date,
                            p_amount numeric, p_units numeric) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO public.invoices (id, tenant_id, invoice_number, billing_run_id, customer_id, location_id, invoice_type, replaces_invoice_id,
                               invoice_date, billing_period, period_start, period_end, due_date, amount_due)
  VALUES (p_id, '00000000-0000-4000-8000-0000000013a1', p_num, p_run, '00000000-0000-4000-8000-0000000013c1', '00000000-0000-4000-8000-0000000013d3',
          p_type, p_replaces, p_pe + 1, to_char(p_pe, 'YYYY-MM'), p_ps, p_pe, p_pe + 21, p_amount);
  INSERT INTO public.invoice_line_items (tenant_id, invoice_id, service_type, charge_type, description, amount, meter_id, usage_quantity)
  VALUES ('00000000-0000-4000-8000-0000000013a1', p_id, 'gas', 'usage_charge', 'Gas', p_amount,
          '00000000-0000-4000-8000-0000000013ed', p_units);
END $$;
GRANT EXECUTE ON FUNCTION pg_temp.inv(uuid, text, uuid, text, uuid, date, date, numeric, numeric) TO tally_app;

INSERT INTO public.billing_runs (id, tenant_id, run_number, billing_period, period_start, period_end, run_type, status, started_at) VALUES
  ('00000000-0000-4000-8000-000000001300', '00000000-0000-4000-8000-0000000013a1', 'R-2026-05', '2026-05', '2026-05-01', '2026-05-31', 'regular', 'in_progress', '2026-06-01 09:00-05'),
  ('00000000-0000-4000-8000-000000001301', '00000000-0000-4000-8000-0000000013a1', 'R-2026-04', '2026-04', '2026-04-01', '2026-04-30', 'regular', 'in_progress', '2026-05-01 09:00-05');
SELECT pg_temp.inv('00000000-0000-4000-8000-000000001310', 'O-MAY', '00000000-0000-4000-8000-000000001300', 'regular', NULL, '2026-05-01', '2026-05-31', 100.00, 50);
SELECT pg_temp.snap('00000000-0000-4000-8000-000000001310', '2026-05-31', '2026-06-01 09:10-05');
UPDATE public.invoices SET status = 'pending' WHERE id = '00000000-0000-4000-8000-000000001310';
SELECT pg_temp.inv('00000000-0000-4000-8000-000000001311', 'O-APR', '00000000-0000-4000-8000-000000001301', 'regular', NULL, '2026-04-01', '2026-04-30', 100.00, 50);
SELECT pg_temp.snap('00000000-0000-4000-8000-000000001311', '2026-04-30', '2026-05-01 09:10-05');
UPDATE public.invoices SET status = 'pending' WHERE id = '00000000-0000-4000-8000-000000001311';
SET LOCAL app.user_id = '00000000-0000-4000-8000-0000000013b1';
SELECT public.void_invoice('00000000-0000-4000-8000-000000001310', '00000000-0000-4000-8000-0000000013b1', 'wrong_rate', 'battery', true);
SELECT public.void_invoice('00000000-0000-4000-8000-000000001311', '00000000-0000-4000-8000-0000000013b1', 'wrong_rate', 'battery', true);
INSERT INTO public.billing_runs (id, tenant_id, run_number, billing_period, period_start, period_end, run_type, status, correction_rate_mode, started_at) VALUES
  ('00000000-0000-4000-8000-000000001304', '00000000-0000-4000-8000-0000000013a1', 'RC-A', '2026-06', '2026-06-01', '2026-06-30', 'correction', 'in_progress', 'historical', now()),
  ('00000000-0000-4000-8000-000000001305', '00000000-0000-4000-8000-0000000013a1', 'RC-B', '2026-06', '2026-06-01', '2026-06-30', 'correction', 'in_progress', 'historical', now()),
  ('00000000-0000-4000-8000-000000001306', '00000000-0000-4000-8000-0000000013a1', 'RR-C', '2026-06', '2026-06-01', '2026-06-30', 'regular', 'in_progress', 'historical', now());
SET ROLE tally_app;

INSERT INTO public.correction_run_targets (id, tenant_id, billing_run_id, voided_invoice_id, meter_id, customer_id, location_id, rate_date_mode) VALUES
  ('00000000-0000-4000-8000-000000001320', '00000000-0000-4000-8000-0000000013a1', '00000000-0000-4000-8000-000000001304', '00000000-0000-4000-8000-000000001310',
   '00000000-0000-4000-8000-0000000013ed', '00000000-0000-4000-8000-0000000013c1', '00000000-0000-4000-8000-0000000013d3', 'historical'),
  ('00000000-0000-4000-8000-000000001321', '00000000-0000-4000-8000-0000000013a1', '00000000-0000-4000-8000-000000001304', '00000000-0000-4000-8000-000000001311',
   '00000000-0000-4000-8000-0000000013ed', '00000000-0000-4000-8000-0000000013c1', '00000000-0000-4000-8000-0000000013d3', 'historical');
DO $$ BEGIN
  INSERT INTO public.correction_run_targets (tenant_id, billing_run_id, voided_invoice_id, meter_id, customer_id, location_id, rate_date_mode, backbill_cause)
  VALUES ('00000000-0000-4000-8000-0000000013a1', '00000000-0000-4000-8000-000000001305', '00000000-0000-4000-8000-000000001310',
          '00000000-0000-4000-8000-0000000013ed', '00000000-0000-4000-8000-0000000013c1', '00000000-0000-4000-8000-0000000013d3', 'historical', 'meter_error');
  RAISE EXCEPTION 'D1 FAILED: a meter error was put on the reissue path';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'PASS D1: a meter_error cannot travel the void-and-reissue path (R-33) — the target admits rate_misapplication only'; END $$;
INSERT INTO public.correction_run_targets (id, tenant_id, billing_run_id, voided_invoice_id, meter_id, customer_id, location_id, rate_date_mode, backbill_cause) VALUES
  ('00000000-0000-4000-8000-000000001322', '00000000-0000-4000-8000-0000000013a1', '00000000-0000-4000-8000-000000001305', '00000000-0000-4000-8000-000000001310',
   '00000000-0000-4000-8000-0000000013ed', '00000000-0000-4000-8000-0000000013c1', '00000000-0000-4000-8000-0000000013d3', 'historical', 'rate_misapplication');

-- D2: a plain REGULAR bill for the voided period, charging more.
SELECT pg_temp.inv('00000000-0000-4000-8000-000000001330', 'R-MAY', '00000000-0000-4000-8000-000000001306', 'regular', NULL, '2026-05-01', '2026-05-31', 150.00, 50);
SELECT pg_temp.snap('00000000-0000-4000-8000-000000001330', '2026-05-31', now());
DO $$ BEGIN
  UPDATE public.invoices SET status = 'pending' WHERE id = '00000000-0000-4000-8000-000000001330';
  RAISE EXCEPTION 'D2 FAILED: a regular rebill charged more for a voided period';
EXCEPTION WHEN restrict_violation THEN
  RAISE NOTICE 'PASS D2: a "regular" bill charging more for a period already billed is refused — the gate reads the act, not the invoice_type'; END $$;

-- D3: a correction whose target records no cause, charging more.
SELECT pg_temp.inv('00000000-0000-4000-8000-000000001331', 'C-A', '00000000-0000-4000-8000-000000001304', 'correction', '00000000-0000-4000-8000-000000001310', '2026-05-01', '2026-05-31', 150.00, 50);
SELECT pg_temp.snap('00000000-0000-4000-8000-000000001331', '2026-05-31', now());
DO $$ BEGIN
  UPDATE public.invoices SET status = 'pending' WHERE id = '00000000-0000-4000-8000-000000001331';
  RAISE EXCEPTION 'D3 FAILED';
EXCEPTION WHEN restrict_violation THEN
  RAISE NOTICE 'PASS D3: an increase whose target records no statutory cause is refused'; END $$;

-- One live correction per bill lineage (v5.4.2-10): discard D3's refused
-- draft's snapshot before the next correction of O-MAY.
DELETE FROM public.invoice_calculation_snapshots WHERE invoice_id = '00000000-0000-4000-8000-000000001331';
-- D4: rate_misapplication that bills DIFFERENT units.
SELECT pg_temp.inv('00000000-0000-4000-8000-000000001332', 'C-B1', '00000000-0000-4000-8000-000000001305', 'correction', '00000000-0000-4000-8000-000000001310', '2026-05-01', '2026-05-31', 150.00, 60);
SELECT pg_temp.snap('00000000-0000-4000-8000-000000001332', '2026-05-31', now());
DO $$ BEGIN
  UPDATE public.invoices SET status = 'pending' WHERE id = '00000000-0000-4000-8000-000000001332';
  RAISE EXCEPTION 'D4 FAILED: a units change passed as a rate misapplication';
EXCEPTION WHEN restrict_violation THEN
  RAISE NOTICE 'PASS D4: a "rate_misapplication" that bills different units is refused (R-39: correct units, wrong price — the label cannot carry a metering correction past its window)'; END $$;

DELETE FROM public.invoice_calculation_snapshots WHERE invoice_id = '00000000-0000-4000-8000-000000001332';
-- D5: rate_misapplication at the SAME units issues.
SELECT pg_temp.inv('00000000-0000-4000-8000-000000001333', 'C-B2', '00000000-0000-4000-8000-000000001305', 'correction', '00000000-0000-4000-8000-000000001310', '2026-05-01', '2026-05-31', 150.00, 50);
SELECT pg_temp.snap('00000000-0000-4000-8000-000000001333', '2026-05-31', now());
DO $$ DECLARE s text; BEGIN
  UPDATE public.invoices SET status = 'pending' WHERE id = '00000000-0000-4000-8000-000000001333';
  SELECT status INTO s FROM public.invoices WHERE id = '00000000-0000-4000-8000-000000001333';
  IF s <> 'pending' THEN RAISE EXCEPTION 'D5 FAILED'; END IF;
  RAISE NOTICE 'PASS D5: a rate_misapplication reissue at the original''s units issues';
END $$;

-- D6: a DOWNWARD reissue with no cause issues.
SELECT pg_temp.inv('00000000-0000-4000-8000-000000001334', 'C-A2', '00000000-0000-4000-8000-000000001304', 'correction', '00000000-0000-4000-8000-000000001311', '2026-04-01', '2026-04-30', 80.00, 40);
SELECT pg_temp.snap('00000000-0000-4000-8000-000000001334', '2026-04-30', now());
DO $$ DECLARE s text; BEGIN
  UPDATE public.invoices SET status = 'pending' WHERE id = '00000000-0000-4000-8000-000000001334';
  SELECT status INTO s FROM public.invoices WHERE id = '00000000-0000-4000-8000-000000001334';
  IF s <> 'pending' THEN RAISE EXCEPTION 'D6 FAILED'; END IF;
  RAISE NOTICE 'PASS D6: a reissue that reduces the charge needs no cause (§7.45 caps the increase)';
END $$;

-- D7: the cause is frozen under a snapshot (R-38 on the reissue path).
DO $$ BEGIN
  UPDATE public.correction_run_targets SET backbill_cause = NULL WHERE id = '00000000-0000-4000-8000-000000001322';
  RAISE EXCEPTION 'D7 FAILED';
EXCEPTION WHEN restrict_violation THEN
  RAISE NOTICE 'PASS D7: backbill_cause is frozen once a calculation snapshot exists (R-38)'; END $$;
DO $$ BEGIN
  UPDATE public.correction_run_targets SET updated_at = now() WHERE id = '00000000-0000-4000-8000-000000001322';
  RAISE NOTICE 'PASS D8: an update touching no frozen column still passes (column list and early return agree)';
END $$;
DO $$ BEGIN
  IF public.backbilling_units_match('00000000-0000-4000-8000-000000001310', '00000000-0000-4000-8000-000000001332') THEN RAISE EXCEPTION 'D9 FAILED'; END IF;
  IF NOT public.backbilling_units_match('00000000-0000-4000-8000-000000001310', '00000000-0000-4000-8000-000000001333') THEN RAISE EXCEPTION 'D9b FAILED'; END IF;
  RAISE NOTICE 'PASS D9: backbilling_units_match — 60 vs 50 differs, 50 vs 50 matches';
END $$;

-- ======================================================================== E
DO $$ DECLARE c record; BEGIN
  INSERT INTO public.meter_correction_cases (id, tenant_id, meter_id, cause, discovering_test_id)
  VALUES ('00000000-0000-4000-8000-0000000013a0', '00000000-0000-4000-8000-0000000013a1', '00000000-0000-4000-8000-0000000013e1', 'meter_error', pg_temp.id('t_e1'));
  INSERT INTO b13 VALUES ('c_e1', '00000000-0000-4000-8000-0000000013a0');
  SELECT * INTO c FROM public.meter_correction_cases WHERE id = pg_temp.id('c_e1');
  IF c.anchor_date <> DATE '2026-06-15' OR c.anchor_basis <> 'test_date' OR c.direction <> 'customer_owed'
     OR c.opened_by <> '00000000-0000-4000-8000-0000000013b1' OR c.status <> 'open' THEN
    RAISE EXCEPTION 'E1 FAILED: % % % % %', c.anchor_date, c.anchor_basis, c.direction, c.opened_by, c.status; END IF;
  RAISE NOTICE 'PASS E1: a fast test opens a meter_error case: anchor = the test date, basis test_date, direction customer_owed — all derived; opener stamped';
END $$;
DO $$ BEGIN
  INSERT INTO public.meter_correction_cases (tenant_id, meter_id, cause, discovering_test_id, anchor_date)
  VALUES ('00000000-0000-4000-8000-0000000013a1', '00000000-0000-4000-8000-0000000013e4', 'meter_error', pg_temp.id('t_e4'), DATE '2026-06-01');
  RAISE EXCEPTION 'E2 FAILED: a caller anchor was accepted';
EXCEPTION WHEN restrict_violation THEN
  RAISE NOTICE 'PASS E2: a caller-chosen anchor that is not the test date is refused (moving the anchor moves the window)'; END $$;
DO $$ BEGIN
  INSERT INTO public.meter_correction_cases (tenant_id, meter_id, cause, discovering_test_id)
  VALUES ('00000000-0000-4000-8000-0000000013a1', '00000000-0000-4000-8000-0000000013e2', 'meter_error', pg_temp.id('t_e2p'));
  RAISE EXCEPTION 'E3 FAILED';
EXCEPTION WHEN restrict_violation THEN RAISE NOTICE 'PASS E3: meter_error on a test that found the meter accurate is refused'; END $$;
DO $$ BEGIN
  INSERT INTO public.meter_correction_cases (tenant_id, meter_id, cause, discovering_test_id)
  VALUES ('00000000-0000-4000-8000-0000000013a1', '00000000-0000-4000-8000-0000000013e7', 'meter_error', pg_temp.id('t_e7'));
  RAISE EXCEPTION 'E4 FAILED';
EXCEPTION WHEN restrict_violation THEN RAISE NOTICE 'PASS E4: meter_error on a non-registering test is refused (R-39: the outcome decides the cause)'; END $$;
DO $$ BEGIN
  INSERT INTO public.meter_correction_cases (tenant_id, meter_id, cause, discovering_test_id)
  VALUES ('00000000-0000-4000-8000-0000000013a1', '00000000-0000-4000-8000-0000000013e3', 'non_registering_meter', pg_temp.id('t_e3'));
  RAISE EXCEPTION 'E5 FAILED';
EXCEPTION WHEN restrict_violation THEN RAISE NOTICE 'PASS E5: non_registering_meter on a slow (registering) test is refused (R-39: zero registration only)'; END $$;
DO $$ BEGIN
  INSERT INTO public.meter_correction_cases (tenant_id, meter_id, cause, discovering_test_id)
  VALUES ('00000000-0000-4000-8000-0000000013a1', '00000000-0000-4000-8000-0000000013ec', 'meter_error', '00000000-0000-4000-8000-0000000013fc');
  RAISE EXCEPTION 'E6 FAILED: an asserted date-only slow result billed a customer';
EXCEPTION WHEN restrict_violation THEN
  RAISE NOTICE 'PASS E6: an adverse case on a date-only asserted "slow" is refused — an asserted result does not bill a customer'; END $$;
DO $$ BEGIN
  INSERT INTO public.meter_correction_cases (tenant_id, meter_id, cause, discovering_test_id, direction)
  VALUES ('00000000-0000-4000-8000-0000000013a1', '00000000-0000-4000-8000-0000000013e4', 'meter_error', pg_temp.id('t_e4'), 'customer_owes');
  RAISE EXCEPTION 'E7 FAILED';
EXCEPTION WHEN restrict_violation THEN RAISE NOTICE 'PASS E7: a caller-supplied direction is refused (a fast meter cannot be declared a charge)'; END $$;
DO $$ BEGIN
  INSERT INTO public.meter_correction_cases (tenant_id, meter_id, cause, anchor_date)
  VALUES ('00000000-0000-4000-8000-0000000013a1', '00000000-0000-4000-8000-0000000013e8', 'billing_constant_error', DATE '2026-06-10');
  RAISE EXCEPTION 'E8 FAILED';
EXCEPTION WHEN restrict_violation THEN RAISE NOTICE 'PASS E8: a discovery cause needs claimed_from'; END $$;
DO $$ BEGIN
  INSERT INTO public.meter_correction_cases (tenant_id, meter_id, cause, anchor_date, claimed_from)
  VALUES ('00000000-0000-4000-8000-0000000013a1', '00000000-0000-4000-8000-0000000013e8', 'billing_constant_error', CURRENT_DATE + 5, DATE '2026-02-15');
  RAISE EXCEPTION 'E9 FAILED';
EXCEPTION WHEN restrict_violation THEN RAISE NOTICE 'PASS E9: a discovery date in the future is refused'; END $$;
DO $$ BEGIN
  INSERT INTO public.meter_correction_cases (tenant_id, meter_id, cause, discovering_test_id)
  VALUES ('00000000-0000-4000-8000-0000000013a1', '00000000-0000-4000-8000-0000000013e4', 'meter_error', pg_temp.id('t_e1'));
  RAISE EXCEPTION 'E10 FAILED';
EXCEPTION WHEN restrict_violation THEN RAISE NOTICE 'PASS E10: another meter''s test cannot discover this meter''s fault'; END $$;
DO $$ BEGIN
  INSERT INTO public.meter_correction_cases (tenant_id, meter_id, cause, anchor_date, claimed_from, tamper_evidence_kind, tamper_deployment_id)
  VALUES ('00000000-0000-4000-8000-0000000013a1', '00000000-0000-4000-8000-0000000013ea', 'tampering_bypass', DATE '2026-05-01', DATE '2026-01-01',
          'deployment_removal', pg_temp.id('dep_ea'));
  RAISE EXCEPTION 'E11 FAILED: an operator opened a tampering case';
EXCEPTION WHEN insufficient_privilege THEN
  RAISE NOTICE 'PASS E11: an operator cannot open a tampering_bypass case (R-38 attachment 2: it lifts the disconnection bar and uncaps the bill)'; END $$;
DO $$ DECLARE c record; BEGIN
  PERFORM set_config('app.user_id', '00000000-0000-4000-8000-0000000013b3', true);
  BEGIN
    INSERT INTO public.meter_correction_cases (tenant_id, meter_id, cause, anchor_date, claimed_from, tamper_evidence_kind, tamper_deployment_id)
    VALUES ('00000000-0000-4000-8000-0000000013a1', '00000000-0000-4000-8000-0000000013ea', 'tampering_bypass', DATE '2026-05-01', DATE '2026-01-01',
            'deployment_removal', pg_temp.id('dep_ee'));
    RAISE EXCEPTION 'E12 FAILED: another meter''s tamper removal was accepted as evidence';
  EXCEPTION WHEN restrict_violation THEN NULL; END;
  BEGIN
    INSERT INTO public.meter_correction_cases (tenant_id, meter_id, cause, anchor_date, claimed_from)
    VALUES ('00000000-0000-4000-8000-0000000013a1', '00000000-0000-4000-8000-0000000013ea', 'tampering_bypass', DATE '2026-05-01', DATE '2026-01-01');
    RAISE EXCEPTION 'E12b FAILED: tampering with no evidence';
  EXCEPTION WHEN restrict_violation THEN NULL; END;
  INSERT INTO public.meter_correction_cases (id, tenant_id, meter_id, cause, anchor_date, claimed_from, tamper_evidence_kind, tamper_deployment_id)
  VALUES ('00000000-0000-4000-8000-0000000013a9', '00000000-0000-4000-8000-0000000013a1', '00000000-0000-4000-8000-0000000013ea', 'tampering_bypass',
          DATE '2026-05-01', DATE '2026-01-01', 'deployment_removal', pg_temp.id('dep_ea'));
  SELECT * INTO c FROM public.meter_correction_cases WHERE id = '00000000-0000-4000-8000-0000000013a9';
  IF c.tamper_approved_by <> '00000000-0000-4000-8000-0000000013b3' OR c.tamper_approved_at IS NULL OR c.anchor_basis <> 'discovery_date' THEN
    RAISE EXCEPTION 'E12c FAILED'; END IF;
  PERFORM set_config('app.user_id', '00000000-0000-4000-8000-0000000013b1', true);
  RAISE NOTICE 'PASS E12: a supervisor opens a tampering case on evidence of THIS meter (a deployment removed for tamper) — refused on another meter''s deployment or none; approval stamped';
END $$;

-- a discovery case for E13-E16 (and F)
INSERT INTO public.meter_correction_cases (id, tenant_id, meter_id, cause, anchor_date, claimed_from)
VALUES ('00000000-0000-4000-8000-0000000013a8', '00000000-0000-4000-8000-0000000013a1', '00000000-0000-4000-8000-0000000013e8',
        'billing_constant_error', DATE '2026-06-10', DATE '2026-02-15');
DO $$ BEGIN
  UPDATE public.meter_correction_cases SET cause = 'crossed_meters' WHERE id = '00000000-0000-4000-8000-0000000013a8';
  RAISE EXCEPTION 'E13 FAILED';
EXCEPTION WHEN restrict_violation THEN RAISE NOTICE 'PASS E13: a cause change without a reason is refused (R-19, R-38)'; END $$;
DO $$ BEGIN
  UPDATE public.meter_correction_cases SET cause = 'tampering_bypass', cause_change_reason = 'bypass found',
         tamper_evidence_kind = 'field_report', tamper_field_report_ref = 'FR-77'
   WHERE id = '00000000-0000-4000-8000-0000000013a8';
  RAISE EXCEPTION 'E14 FAILED';
EXCEPTION WHEN insufficient_privilege THEN RAISE NOTICE 'PASS E14: an operator cannot move a case INTO tampering_bypass'; END $$;
DO $$ DECLARE c record; n int; BEGIN
  PERFORM set_config('app.user_id', '00000000-0000-4000-8000-0000000013b3', true);
  UPDATE public.meter_correction_cases SET cause = 'tampering_bypass', cause_change_reason = 'bypass found on site',
         tamper_evidence_kind = 'field_report', tamper_field_report_ref = 'FR-77'
   WHERE id = '00000000-0000-4000-8000-0000000013a8';
  PERFORM set_config('app.user_id', '00000000-0000-4000-8000-0000000013b1', true);
  BEGIN
    UPDATE public.meter_correction_cases SET tamper_field_report_ref = 'FR-78' WHERE id = '00000000-0000-4000-8000-0000000013a8';
    RAISE EXCEPTION 'E15b FAILED: approved evidence moved';
  EXCEPTION WHEN restrict_violation THEN NULL; END;
  UPDATE public.meter_correction_cases SET cause = 'billing_constant_error', cause_change_reason = 'report withdrawn; multiplier was wrong'
   WHERE id = '00000000-0000-4000-8000-0000000013a8';
  SELECT * INTO c FROM public.meter_correction_cases WHERE id = '00000000-0000-4000-8000-0000000013a8';
  IF c.tamper_approved_at IS NOT NULL OR c.tamper_field_report_ref IS NOT NULL THEN RAISE EXCEPTION 'E15 FAILED: approval survived leaving tampering'; END IF;
  SELECT count(*) INTO n FROM public.meter_correction_case_events WHERE case_id = c.id;
  IF n <> 3 THEN RAISE EXCEPTION 'E15c FAILED: % events', n; END IF;
  SELECT count(*) INTO n FROM public.meter_correction_case_events
   WHERE case_id = c.id AND event_type = 'cause_changed' AND from_cause = 'tampering_bypass' AND reason LIKE 'report withdrawn%'
     AND actor_id = '00000000-0000-4000-8000-0000000013b1';
  IF n <> 1 THEN RAISE EXCEPTION 'E15d FAILED'; END IF;
  RAISE NOTICE 'PASS E15: a supervisor moves it into tampering on a field report; the approved evidence cannot move; an operator moves it back out (toward protection) with a reason, which clears the approval; opened + two cause changes logged with reason and actor';
END $$;
DO $$ BEGIN
  INSERT INTO public.meter_correction_case_events (tenant_id, case_id, event_type)
  VALUES ('00000000-0000-4000-8000-0000000013a1', '00000000-0000-4000-8000-0000000013a8', 'gate_approved');
  RAISE EXCEPTION 'E16 FAILED';
EXCEPTION WHEN restrict_violation THEN RAISE NOTICE 'PASS E16: the application cannot write the case log (a forged "gate_approved")'; END $$;
DO $$ BEGIN
  UPDATE public.meter_correction_cases SET meter_id = '00000000-0000-4000-8000-0000000013e2' WHERE id = '00000000-0000-4000-8000-0000000013a8';
  RAISE EXCEPTION 'E17 FAILED';
EXCEPTION WHEN restrict_violation THEN RAISE NOTICE 'PASS E17: a case''s meter is fixed'; END $$;
DO $$ BEGIN
  INSERT INTO public.meter_correction_cases (tenant_id, meter_id, cause, anchor_date, claimed_from, tamper_approved_at)
  VALUES ('00000000-0000-4000-8000-0000000013a1', '00000000-0000-4000-8000-0000000013e8', 'crossed_meters', DATE '2026-06-10', DATE '2026-02-15', now());
  RAISE EXCEPTION 'E18 FAILED';
EXCEPTION WHEN restrict_violation THEN RAISE NOTICE 'PASS E18: a caller-supplied approval stamp is refused'; END $$;
DO $$ BEGIN
  UPDATE public.meter_correction_case_events SET reason = 'x' WHERE case_id = '00000000-0000-4000-8000-0000000013a8';
  RAISE EXCEPTION 'E19 FAILED';
EXCEPTION WHEN insufficient_privilege OR restrict_violation THEN RAISE NOTICE 'PASS E19: the case log is append-only'; END $$;

-- the rest of the scenario cases (as the operator; e3's by a supervisor)
INSERT INTO b13 SELECT k, id FROM (VALUES ('c_e2', '00000000-0000-4000-8000-0000000013a2'::uuid), ('c_e4', '00000000-0000-4000-8000-0000000013a4'::uuid),
  ('c_e5', '00000000-0000-4000-8000-0000000013a5'::uuid), ('c_e6', '00000000-0000-4000-8000-0000000013a6'::uuid),
  ('c_e7', '00000000-0000-4000-8000-0000000013a7'::uuid), ('c_e9', '00000000-0000-4000-8000-0000000013aa'::uuid),
  ('c_e3', '00000000-0000-4000-8000-0000000013ab'::uuid), ('c_e8', '00000000-0000-4000-8000-0000000013a8'::uuid)) v(k, id);
INSERT INTO public.meter_correction_cases (id, tenant_id, meter_id, cause, discovering_test_id)
SELECT pg_temp.id('c_' || m), '00000000-0000-4000-8000-0000000013a1', mt.meter_id, cz, pg_temp.id('t_' || m)
  FROM (VALUES ('e2', 'meter_error'), ('e4', 'meter_error'), ('e5', 'meter_error'), ('e6', 'meter_error'),
               ('e7', 'non_registering_meter'), ('e9', 'meter_error')) v(m, cz)
  JOIN public.meter_tests mt ON mt.id = pg_temp.id('t_' || m);
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000013b3', true);
INSERT INTO public.meter_correction_cases (id, tenant_id, meter_id, cause, discovering_test_id)
VALUES (pg_temp.id('c_e3'), '00000000-0000-4000-8000-0000000013a1', '00000000-0000-4000-8000-0000000013e3', 'meter_error', pg_temp.id('t_e3'));
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000013b1', true);

DO $$ BEGIN
  UPDATE public.meter_correction_cases SET cause = 'billing_constant_error', cause_change_reason = 'really a multiplier',
         claimed_from = DATE '2026-01-01', discovering_test_id = NULL, anchor_date = DATE '2026-06-15'
   WHERE id = pg_temp.id('c_e1');
  RAISE EXCEPTION 'E20 FAILED: a fast finding was relabelled as a discovery cause';
EXCEPTION WHEN restrict_violation THEN
  RAISE NOTICE 'PASS E20: a fast meter_error cannot be relabelled billing_constant_error — the test decided it, and the relabel would drop the mandatory refund'; END $$;

-- ======================================================================== F
DO $$ DECLARE e record; n int; BEGIN
  INSERT INTO b13 VALUES ('v_e3', pg_temp.ev(pg_temp.id('c_e3'), ARRAY[10, 11, 12]));
  SELECT * INTO e FROM public.meter_correction_evaluations WHERE id = pg_temp.id('v_e3');
  IF e.window_start <> DATE '2025-12-15' OR e.governing_test_id IS NOT NULL OR e.absence <> 'undeclared'
     OR e.statutory_start <> DATE '2025-12-15' THEN
    RAISE EXCEPTION 'F1 FAILED: window % governing % absence %', e.window_start, e.governing_test_id, e.absence; END IF;
  SELECT count(*) INTO n FROM public.meter_correction_period_evidence WHERE evaluation_id = e.id AND disposition = 'included';
  IF n <> 3 THEN RAISE EXCEPTION 'F1b FAILED: % included', n; END IF;
  RAISE NOTICE 'PASS F1: no prior test — the six-month cap governs alone (R-35 refinement 5: the round-1 refusal is gone); three adverse periods included';
END $$;

DO $$ DECLARE e record; p record; BEGIN
  INSERT INTO b13 VALUES ('v_e2', pg_temp.ev(pg_temp.id('c_e2'), ARRAY[20, 21, 22, 23]));
  SELECT * INTO e FROM public.meter_correction_evaluations WHERE id = pg_temp.id('v_e2');
  IF e.window_start <> DATE '2026-03-10' OR e.governing_test_id <> pg_temp.id('t_e2p') THEN
    RAISE EXCEPTION 'F2 FAILED: window % governing %', e.window_start, e.governing_test_id; END IF;
  RAISE NOTICE 'PASS F2: a prior test inside six months moves the window to its date (2026-03-10) — R-34''s governing test, whatever its outcome';
  SELECT * INTO p FROM public.meter_correction_period_evidence WHERE evaluation_id = e.id AND period_start = DATE '2026-03-01';
  IF p.disposition <> 'forfeited' OR p.forfeit_reason <> 'straddles_window' OR p.days_in_window <> 22 OR p.forfeited_amount <> 20 THEN
    RAISE EXCEPTION 'F3 FAILED: % % % %', p.disposition, p.forfeit_reason, p.days_in_window, p.forfeited_amount; END IF;
  RAISE NOTICE 'PASS F3: an ADVERSE period straddling the window is forfeited WHOLE (R-32) — 22 days inside, 20.00 given up, on the record';
  IF (SELECT count(*) FROM public.meter_correction_period_evidence WHERE evaluation_id = e.id AND period_start = DATE '2026-02-01') <> 0 THEN
    RAISE EXCEPTION 'F3b FAILED: a period wholly before the window was evaluated'; END IF;
END $$;

DO $$ DECLARE e record; BEGIN
  INSERT INTO b13 VALUES ('v_e4', pg_temp.ev(pg_temp.id('c_e4'), ARRAY[-1, -2, -3, -4]));
  SELECT * INTO e FROM public.meter_correction_evaluations WHERE id = pg_temp.id('v_e4');
  IF e.window_start <> DATE '2026-03-01' OR e.deployment_bound <> DATE '2026-03-01' OR e.deployment_id <> pg_temp.id('dep_e4')
     OR NOT (e.inputs ->> 'deployment_corroborated')::boolean THEN
    RAISE EXCEPTION 'F4 FAILED: window % bound %', e.window_start, e.deployment_bound; END IF;
  RAISE NOTICE 'PASS F4: a corroborated service start bounds a refund (R-37(a)): e4 went in 2026-03-01 as eP came out — earlier readings were eP''s';
END $$;

DO $$ DECLARE e record; p record; BEGIN
  INSERT INTO b13 VALUES ('v_e5', pg_temp.ev(pg_temp.id('c_e5'), ARRAY[-7]));
  SELECT * INTO e FROM public.meter_correction_evaluations WHERE id = pg_temp.id('v_e5');
  IF e.window_start <> DATE '2025-12-15' OR e.deployment_bound IS NOT NULL THEN
    RAISE EXCEPTION 'F5 FAILED: window % bound %', e.window_start, e.deployment_bound; END IF;
  RAISE NOTICE 'PASS F5: a deployment entered AFTER the finding does not bound its window — a refund cannot be shortened after the fact';
  SELECT * INTO p FROM public.meter_correction_period_evidence WHERE evaluation_id = e.id;
  IF p.disposition <> 'included' OR p.direction <> 'customer_owed' OR p.days_in_window <> 17 THEN
    RAISE EXCEPTION 'F6 FAILED: % % %', p.disposition, p.direction, p.days_in_window; END IF;
  RAISE NOTICE 'PASS F6: a FAVOURABLE straddler (Dec 1-31 against a Dec 15 window) is included whole (R-25, R-32)';
END $$;

DO $$ DECLARE e record; n int; BEGIN
  INSERT INTO b13 VALUES ('v_e1', pg_temp.ev(pg_temp.id('c_e1'), ARRAY[-5, -6, -7, -8, -9, -10]));
  SELECT count(*) INTO n FROM public.meter_correction_period_evidence
   WHERE evaluation_id = pg_temp.id('v_e1') AND customer_id = '00000000-0000-4000-8000-0000000013c2'
     AND location_id = '00000000-0000-4000-8000-0000000013d2' AND disposition = 'included';
  IF n <> 1 THEN RAISE EXCEPTION 'F7 FAILED'; END IF;
  RAISE NOTICE 'PASS F7: the case follows the METER — February, billed to another customer at another premise, is in scope (R-37(b))';
  SELECT * INTO e FROM public.meter_correction_evaluations WHERE id = pg_temp.id('v_e1');
  IF e.deployment_bound IS NOT NULL OR e.window_start <> DATE '2025-12-15' THEN
    RAISE EXCEPTION 'F7c FAILED: an onboarding-date start shortened a refund (bound %, window %)', e.deployment_bound, e.window_start; END IF;
  RAISE NOTICE 'PASS F7c: e1''s only deployment starts on its onboarding date (2026-01-20) with no predecessor meter — it does NOT shorten the refund; the window stays 2025-12-15';
  SELECT * INTO e FROM public.meter_correction_evaluations WHERE id = pg_temp.id('v_e1');
  IF e.supervisor_gate_required THEN RAISE EXCEPTION 'F7b FAILED: a refund carries the R-36 gate'; END IF;
END $$;

-- F8: the tenant's adverse limit — forfeits adverse periods, never touches refunds
UPDATE public.tenants SET backbilling_adverse_limit_months = 2 WHERE id = '00000000-0000-4000-8000-0000000013a1';
DO $$ DECLARE v uuid; p record; n int; BEGIN
  v := pg_temp.ev(pg_temp.id('c_e2'), ARRAY[20, 21, 22, 23]);
  SELECT * INTO p FROM public.meter_correction_period_evidence WHERE evaluation_id = v AND period_start = DATE '2026-04-01';
  IF p.disposition <> 'forfeited' OR p.forfeit_reason <> 'tenant_limit' OR p.forfeited_amount <> 21 THEN
    RAISE EXCEPTION 'F8 FAILED: % %', p.disposition, p.forfeit_reason; END IF;
  SELECT count(*) INTO n FROM public.meter_correction_period_evidence WHERE evaluation_id = v AND disposition = 'included';
  IF n <> 2 THEN RAISE EXCEPTION 'F8b FAILED: % included', n; END IF;
  v := pg_temp.ev(pg_temp.id('c_e1'), ARRAY[-5, -6, -7, -8, -9, -10]);
  SELECT count(*) INTO n FROM public.meter_correction_period_evidence WHERE evaluation_id = v AND disposition = 'included';
  IF n <> 6 THEN RAISE EXCEPTION 'F8c FAILED: the tenant limit shortened a refund (% included)', n; END IF;
  RAISE NOTICE 'PASS F8: a 2-month tenant limit forfeits April (tenant_limit, R-37(d)) on the adverse case and leaves every refund period on the fast case';
END $$;
UPDATE public.tenants SET backbilling_adverse_limit_months = NULL WHERE id = '00000000-0000-4000-8000-0000000013a1';
-- re-evaluate e1 and e2 without the limit, so their latest evaluations are current
SELECT pg_temp.ev(pg_temp.id('c_e1'), ARRAY[-5, -6, -7, -8, -9, -10]);
SELECT pg_temp.ev(pg_temp.id('c_e2'), ARRAY[20, 21, 22, 23]);

DO $$ DECLARE e record; p record; BEGIN
  INSERT INTO b13 VALUES ('v_e7', pg_temp.ev(pg_temp.id('c_e7'), ARRAY[30, 31, 32, 33]));
  SELECT * INTO e FROM public.meter_correction_evaluations WHERE id = pg_temp.id('v_e7');
  IF e.window_start <> DATE '2026-03-20' OR e.statutory_start <> DATE '2026-03-15' OR e.supervisor_gate_required THEN RAISE EXCEPTION 'F9 FAILED: %', e.window_start; END IF;
  SELECT * INTO p FROM public.meter_correction_period_evidence WHERE evaluation_id = e.id AND period_start = DATE '2026-03-01';
  IF p.forfeit_reason <> 'straddles_window' OR p.enforceable_scope <> 'never' THEN RAISE EXCEPTION 'F9b FAILED'; END IF;
  RAISE NOTICE 'PASS F9: non-registering — three months from the test ((v)(II)) = 03-15, shortened to the meter''s start 03-20 without corroboration (a CHARGE may be shortened by any recorded start); March forfeited whole; enforceable never (F-1)';
END $$;

DO $$ DECLARE e record; r record; BEGIN
  INSERT INTO b13 VALUES ('v_e8', pg_temp.ev(pg_temp.id('c_e8'), ARRAY[10, -5, 10, 0]));
  SELECT * INTO e FROM public.meter_correction_evaluations WHERE id = pg_temp.id('v_e8');
  IF e.window_start IS NOT NULL THEN RAISE EXCEPTION 'F10 FAILED: an uncapped cause has a window'; END IF;
  SELECT string_agg(to_char(period_start, 'MM') || ':' || direction || ':' || disposition || ':' || coalesce(forfeit_reason, '-'), ' ' ORDER BY period_start)
    INTO r FROM public.meter_correction_period_evidence WHERE evaluation_id = e.id;
  IF r.string_agg <> '02:customer_owes:forfeited:straddles_claimed_start 03:customer_owed:included:- 04:customer_owes:included:- 05:neutral:included:-' THEN
    RAISE EXCEPTION 'F10b FAILED: %', r.string_agg; END IF;
  RAISE NOTICE 'PASS F10: a discovery cause — no statutory window; direction per period from the amount (R-25); the adverse period straddling the claimed start is forfeited';
END $$;

DO $$ BEGIN
  INSERT INTO public.meter_correction_evaluations (tenant_id, case_id, submitted_amounts)
  VALUES ('00000000-0000-4000-8000-0000000013a1', pg_temp.id('c_e3'), pg_temp.amounts(pg_temp.id('c_e3'), ARRAY[10, 11, 12]) - (SELECT min(k) FROM jsonb_object_keys(pg_temp.amounts(pg_temp.id('c_e3'), ARRAY[10, 11, 12])) k));
  RAISE EXCEPTION 'F11 FAILED: a period was left out';
EXCEPTION WHEN invalid_parameter_value THEN RAISE NOTICE 'PASS F11: leaving a billed period out of the amounts is refused'; END $$;
DO $$ BEGIN
  INSERT INTO public.meter_correction_evaluations (tenant_id, case_id, submitted_amounts)
  VALUES ('00000000-0000-4000-8000-0000000013a1', pg_temp.id('c_e3'), pg_temp.amounts(pg_temp.id('c_e3'), ARRAY[10, 11, 12]) || jsonb_build_object(pg_temp.id('e1_feb')::text, 5));
  RAISE EXCEPTION 'F12 FAILED: a period was added';
EXCEPTION WHEN invalid_parameter_value THEN RAISE NOTICE 'PASS F12: adding a period the database did not find is refused'; END $$;
DO $$ BEGIN
  PERFORM pg_temp.ev(pg_temp.id('c_e1'), ARRAY[-5, -6, 7, -8, -9, -10]);
  RAISE EXCEPTION 'F13 FAILED: a fast meter yielded a charge';
EXCEPTION WHEN invalid_parameter_value THEN RAISE NOTICE 'PASS F13: a charge on a fast-meter case is refused (the sign must agree with the test)'; END $$;
DO $$ BEGIN
  PERFORM pg_temp.ev(pg_temp.id('c_e3'), ARRAY[10.001, 11, 12]);
  RAISE EXCEPTION 'F14 FAILED';
EXCEPTION WHEN invalid_parameter_value THEN RAISE NOTICE 'PASS F14: an amount with three decimals is refused'; END $$;
DO $$ BEGIN
  INSERT INTO public.meter_correction_evaluations (tenant_id, case_id, submitted_amounts, window_start)
  VALUES ('00000000-0000-4000-8000-0000000013a1', pg_temp.id('c_e3'), pg_temp.amounts(pg_temp.id('c_e3'), ARRAY[10, 11, 12]), DATE '2025-06-01');
  RAISE EXCEPTION 'F15 FAILED: a caller-supplied window';
EXCEPTION WHEN restrict_violation THEN RAISE NOTICE 'PASS F15: a caller-supplied window (or any derived column) is refused'; END $$;
DO $$ BEGIN
  INSERT INTO public.meter_correction_period_evidence (tenant_id, evaluation_id, invoice_id, customer_id, period_start, period_end,
        customer_class, cap_rule_id, jurisdiction_level, billable_scope, enforceable_scope, direction, correction_amount, disposition, days_in_window)
  SELECT tenant_id, evaluation_id, pg_temp.id('e1_feb'), customer_id, period_start, period_end, customer_class, cap_rule_id, jurisdiction_level,
         billable_scope, enforceable_scope, 'customer_owes', 99, 'included', 1
    FROM public.meter_correction_period_evidence WHERE evaluation_id = pg_temp.id('v_e3') LIMIT 1;
  RAISE EXCEPTION 'F16 FAILED: an evidence row the evaluation never computed was written';
EXCEPTION WHEN restrict_violation THEN RAISE NOTICE 'PASS F16: the application cannot write an evidence row'; END $$;
DO $$ BEGIN
  UPDATE public.meter_correction_period_evidence SET disposition = 'included', forfeit_reason = NULL, forfeited_amount = 0
   WHERE evaluation_id = pg_temp.id('v_e2') AND disposition = 'forfeited';
  RAISE EXCEPTION 'F17 FAILED';
EXCEPTION WHEN insufficient_privilege OR restrict_violation THEN RAISE NOTICE 'PASS F17: a forfeiture cannot be edited into an inclusion (append-only)'; END $$;

-- e9 is evaluated so its holds can be checked against a window (group H)
INSERT INTO b13 VALUES ('v_e9', pg_temp.ev(pg_temp.id('c_e9'), ARRAY[-1, -2, -3, -4]));

-- ======================================================================== G
DO $$ DECLARE e record; BEGIN
  SELECT * INTO e FROM public.meter_correction_evaluations WHERE id = pg_temp.id('v_e3');
  IF NOT e.supervisor_gate_required THEN RAISE EXCEPTION 'G1 FAILED'; END IF;
  RAISE NOTICE 'PASS G1: an adverse meter_error with no prior test inside the transitional period carries the R-36 gate';
END $$;
DO $$ BEGIN
  UPDATE public.meter_correction_cases SET status = 'frozen' WHERE id = pg_temp.id('c_e3');
  RAISE EXCEPTION 'G2 FAILED: froze without approval';
EXCEPTION WHEN restrict_violation THEN RAISE NOTICE 'PASS G2: the case cannot freeze until a supervisor approves (the gate is ENFORCED, not just computed)'; END $$;
DO $$ BEGIN
  INSERT INTO public.meter_correction_approvals (tenant_id, case_id, evaluation_id, note)
  VALUES ('00000000-0000-4000-8000-0000000013a1', pg_temp.id('c_e3'), pg_temp.id('v_e3'), 'ok');
  RAISE EXCEPTION 'G3 FAILED';
EXCEPTION WHEN insufficient_privilege THEN RAISE NOTICE 'PASS G3: an operator cannot approve'; END $$;
DO $$ BEGIN
  PERFORM set_config('app.user_id', '00000000-0000-4000-8000-0000000013b3', true);
  INSERT INTO public.meter_correction_approvals (tenant_id, case_id, evaluation_id, note)
  VALUES ('00000000-0000-4000-8000-0000000013a1', pg_temp.id('c_e3'), pg_temp.id('v_e3'), 'ok');
  RAISE EXCEPTION 'G4 FAILED: the opener approved their own case';
EXCEPTION WHEN insufficient_privilege THEN
  PERFORM set_config('app.user_id', '00000000-0000-4000-8000-0000000013b1', true);
  RAISE NOTICE 'PASS G4: the supervisor who opened the case cannot approve it'; END $$;
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000013b1', true);
DO $$ DECLARE a record; s text; BEGIN
  PERFORM set_config('app.user_id', '00000000-0000-4000-8000-0000000013b4', true);
  INSERT INTO public.meter_correction_approvals (tenant_id, case_id, evaluation_id, note, approved_by)
  VALUES ('00000000-0000-4000-8000-0000000013a1', pg_temp.id('c_e3'), pg_temp.id('v_e3'), 'migrated history reviewed', '00000000-0000-4000-8000-0000000013b3');
  SELECT * INTO a FROM public.meter_correction_approvals WHERE evaluation_id = pg_temp.id('v_e3');
  IF a.approved_by <> '00000000-0000-4000-8000-0000000013b4' THEN RAISE EXCEPTION 'G5 FAILED: approver %', a.approved_by; END IF;
  PERFORM set_config('app.user_id', '00000000-0000-4000-8000-0000000013b1', true);
  UPDATE public.meter_correction_cases SET status = 'frozen' WHERE id = pg_temp.id('c_e3');
  SELECT status INTO s FROM public.meter_correction_cases WHERE id = pg_temp.id('c_e3');
  IF s <> 'frozen' THEN RAISE EXCEPTION 'G5b FAILED'; END IF;
  RAISE NOTICE 'PASS G5: a second supervisor approves (the approver is stamped — a caller-named approver is ignored) and the case freezes';
END $$;
DO $$ BEGIN
  UPDATE public.meter_correction_cases SET status = 'open' WHERE id = pg_temp.id('c_e3');
  INSERT INTO b13 VALUES ('v_e3b', pg_temp.ev(pg_temp.id('c_e3'), ARRAY[10, 11, 12]));
  BEGIN
    UPDATE public.meter_correction_cases SET status = 'frozen' WHERE id = pg_temp.id('c_e3');
    RAISE EXCEPTION 'G6 FAILED: the approval carried over';
  EXCEPTION WHEN restrict_violation THEN NULL; END;
  RAISE NOTICE 'PASS G6: an approval is for ONE evaluation — re-evaluate and the gate stands again';
END $$;
SELECT pg_temp.ev(pg_temp.id('c_e3'), ARRAY[10, 11, 12]);   -- supersedes v_e3b, which no one approved
DO $$ BEGIN
  PERFORM set_config('app.user_id', '00000000-0000-4000-8000-0000000013b4', true);
  INSERT INTO public.meter_correction_approvals (tenant_id, case_id, evaluation_id, note)
  VALUES ('00000000-0000-4000-8000-0000000013a1', pg_temp.id('c_e3'), pg_temp.id('v_e3b'), 'stale');
  RAISE EXCEPTION 'G7 FAILED';
EXCEPTION WHEN restrict_violation THEN
  PERFORM set_config('app.user_id', '00000000-0000-4000-8000-0000000013b1', true);
  RAISE NOTICE 'PASS G7: a superseded evaluation cannot be approved'; END $$;
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000013b1', true);
DO $$ DECLARE v uuid; e record; BEGIN
  v := pg_temp.ev(pg_temp.id('c_e6'), ARRAY[40, 41]);
  SELECT * INTO e FROM public.meter_correction_evaluations WHERE id = v;
  IF e.supervisor_gate_required OR e.window_start <> DATE '2026-02-20' THEN RAISE EXCEPTION 'G8 FAILED: % %', e.supervisor_gate_required, e.window_start; END IF;
  RAISE NOTICE 'PASS G8: anchored 2026-08-20, the six-month reach (2026-02-20) is after cutover — the gate has lapsed on its own';
END $$;

-- ======================================================================== H
DO $$ BEGIN
  INSERT INTO public.meter_correction_holds (tenant_id, case_id, range_start, range_end, hold_code)
  VALUES ('00000000-0000-4000-8000-0000000013a1', pg_temp.id('c_e3'), DATE '2026-01-01', DATE '2026-01-10', 'legacy_records_not_loaded');
  RAISE EXCEPTION 'H1 FAILED';
EXCEPTION WHEN restrict_violation THEN RAISE NOTICE 'PASS H1: a hold on an ADVERSE case is refused (a hold defers a refund duty, nothing else)'; END $$;
DO $$ BEGIN
  UPDATE public.meter_correction_cases SET status = 'frozen' WHERE id = pg_temp.id('c_e1');
  RAISE EXCEPTION 'H2 FAILED: froze with uncovered in-window days';
EXCEPTION WHEN restrict_violation THEN
  RAISE NOTICE 'PASS H2: a fast meter with 31 in-window days Tally never billed cannot freeze — under-reach, no override (R-37)'; END $$;
DO $$ BEGIN
  INSERT INTO public.meter_correction_holds (tenant_id, case_id, range_start, range_end, hold_code)
  VALUES ('00000000-0000-4000-8000-0000000013a1', pg_temp.id('c_e1'), DATE '2025-12-15', DATE '2025-12-20', 'predecessor_records_unavailable');
  RAISE EXCEPTION 'H3 FAILED';
EXCEPTION WHEN restrict_violation THEN RAISE NOTICE 'PASS H3: a predecessor hold where no acquisition is recorded is refused'; END $$;
DO $$ BEGIN
  INSERT INTO public.meter_correction_holds (tenant_id, case_id, range_start, range_end, hold_code)
  VALUES ('00000000-0000-4000-8000-0000000013a1', pg_temp.id('c_e9'), DATE '2026-03-02', DATE '2026-03-10', 'predecessor_records_unavailable');
  RAISE EXCEPTION 'H3b FAILED: a predecessor hold after the acquisition';
EXCEPTION WHEN restrict_violation THEN RAISE NOTICE 'PASS H3b: a predecessor hold for days AFTER the premise was acquired (2026-03-01) is refused — the tenant billed those'; END $$;
DO $$ BEGIN
  INSERT INTO public.meter_correction_holds (tenant_id, case_id, range_start, range_end, hold_code)
  VALUES ('00000000-0000-4000-8000-0000000013a1', pg_temp.id('c_e9'), DATE '2025-12-20', DATE '2025-12-25', 'legacy_records_not_loaded');
  RAISE EXCEPTION 'H4b FAILED: a hold over a loaded legacy bill';
EXCEPTION WHEN restrict_violation THEN RAISE NOTICE 'PASS H4b: a pre-cutover stretch whose legacy bill IS in Tally cannot be held — it is corrected from the bill'; END $$;
DO $$ BEGIN
  INSERT INTO public.meter_correction_holds (tenant_id, case_id, range_start, range_end, hold_code)
  VALUES ('00000000-0000-4000-8000-0000000013a1', pg_temp.id('c_e1'), DATE '2026-02-01', DATE '2026-02-10', 'legacy_records_not_loaded');
  RAISE EXCEPTION 'H4 FAILED';
EXCEPTION WHEN restrict_violation THEN RAISE NOTICE 'PASS H4: a hold over days Tally billed is refused — a billed period is corrected from its bill'; END $$;
DO $$ BEGIN
  INSERT INTO public.meter_correction_holds (tenant_id, case_id, range_start, range_end, hold_code)
  VALUES ('00000000-0000-4000-8000-0000000013a1', pg_temp.id('c_e1'), DATE '2025-12-01', DATE '2025-12-10', 'legacy_records_not_loaded');
  RAISE EXCEPTION 'H5 FAILED';
EXCEPTION WHEN restrict_violation THEN RAISE NOTICE 'PASS H5: a hold outside the window is refused'; END $$;
DO $$ BEGIN
  INSERT INTO public.meter_correction_holds (tenant_id, case_id, range_start, range_end, hold_code)
  VALUES ('00000000-0000-4000-8000-0000000013a1', pg_temp.id('c_e9'), DATE '2026-01-20', DATE '2026-02-28', 'legacy_records_not_loaded');
  RAISE EXCEPTION 'H6 FAILED';
EXCEPTION WHEN restrict_violation THEN RAISE NOTICE 'PASS H6: a legacy hold must end before cutover (otherwise Tally was billing)'; END $$;
INSERT INTO b13 VALUES ('h_e1', NULL);
DO $$ DECLARE h uuid; s text; BEGIN
  INSERT INTO public.meter_correction_holds (tenant_id, case_id, range_start, range_end, hold_code)
  VALUES ('00000000-0000-4000-8000-0000000013a1', pg_temp.id('c_e1'), DATE '2025-12-15', DATE '2026-01-14', 'legacy_records_not_loaded')
  RETURNING id INTO h;
  UPDATE b13 SET id = h WHERE k = 'h_e1';
  UPDATE public.meter_correction_cases SET status = 'frozen' WHERE id = pg_temp.id('c_e1');
  SELECT status INTO s FROM public.meter_correction_cases WHERE id = pg_temp.id('c_e1');
  IF s <> 'frozen' THEN RAISE EXCEPTION 'H7 FAILED'; END IF;
  RAISE NOTICE 'PASS H7: a legacy hold on the pre-cutover stretch covers it, and the rest of the correction freezes at once (the hold does not block it)';
END $$;
DO $$ BEGIN
  INSERT INTO public.meter_correction_holds (tenant_id, case_id, range_start, range_end, hold_code)
  VALUES ('00000000-0000-4000-8000-0000000013a1', pg_temp.id('c_e9'), DATE '2026-01-01', DATE '2026-01-05', 'legacy_records_not_loaded');
  INSERT INTO public.meter_correction_holds (tenant_id, case_id, range_start, range_end, hold_code)
  VALUES ('00000000-0000-4000-8000-0000000013a1', pg_temp.id('c_e9'), DATE '2026-01-03', DATE '2026-02-28', 'predecessor_records_unavailable');
  RAISE EXCEPTION 'H8 FAILED';
EXCEPTION WHEN exclusion_violation THEN RAISE NOTICE 'PASS H8: overlapping holds on one case are refused'; END $$;
DO $$ DECLARE h record; BEGIN
  INSERT INTO public.meter_correction_holds (tenant_id, case_id, range_start, range_end, hold_code, acquisition_id)
  VALUES ('00000000-0000-4000-8000-0000000013a1', pg_temp.id('c_e9'), DATE '2026-01-01', DATE '2026-02-28', 'predecessor_records_unavailable', NULL)
  RETURNING * INTO h;
  INSERT INTO b13 VALUES ('h_e9', h.id);
  IF h.acquisition_id IS NULL OR h.opened_by <> '00000000-0000-4000-8000-0000000013b1' THEN RAISE EXCEPTION 'H9 FAILED'; END IF;
  RAISE NOTICE 'PASS H9: a predecessor hold where the meter served a premise acquired after the stretch — the acquisition is found by the database, not named by the caller';
END $$;
DO $$ BEGIN
  UPDATE public.meter_correction_holds SET status = 'unrecoverable', closure_artifact_ref = 'letter', counsel_referral = true WHERE id = pg_temp.id('h_e1');
  RAISE EXCEPTION 'H10 FAILED';
EXCEPTION WHEN restrict_violation OR check_violation THEN RAISE NOTICE 'PASS H10: a legacy hold cannot close as unrecoverable (the tenant holds those records)'; END $$;
DO $$ BEGIN
  UPDATE public.meter_correction_holds SET status = 'unrecoverable', closure_artifact_ref = 'Seller letter 7', counsel_referral = true WHERE id = pg_temp.id('h_e9');
  RAISE EXCEPTION 'H11 FAILED';
EXCEPTION WHEN insufficient_privilege THEN RAISE NOTICE 'PASS H11: an operator cannot close a hold as unrecoverable'; END $$;
DO $$ BEGIN
  PERFORM set_config('app.user_id', '00000000-0000-4000-8000-0000000013b3', true);
  UPDATE public.meter_correction_holds SET status = 'unrecoverable', closure_artifact_ref = 'Seller letter 7' WHERE id = pg_temp.id('h_e9');
  RAISE EXCEPTION 'H12 FAILED';
EXCEPTION WHEN check_violation THEN
  PERFORM set_config('app.user_id', '00000000-0000-4000-8000-0000000013b1', true);
  RAISE NOTICE 'PASS H12: nor a supervisor without the counsel-referral flag'; END $$;
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000013b1', true);
DO $$ BEGIN
  UPDATE public.meter_correction_holds SET status = 'completed' WHERE id = pg_temp.id('h_e1');
  RAISE EXCEPTION 'H13 FAILED';
EXCEPTION WHEN restrict_violation THEN RAISE NOTICE 'PASS H13: a hold does not complete while the stretch is still unbilled'; END $$;
DO $$ DECLARE n int; BEGIN
  SELECT count(*) INTO n FROM public.meter_correction_open_holds WHERE tenant_id = '00000000-0000-4000-8000-0000000013a1';
  IF n <> 2 THEN RAISE EXCEPTION 'J1 FAILED: % open holds', n; END IF;
  RAISE NOTICE 'PASS J1: both open holds are on the standing surface';
END $$;
DO $$ DECLARE h record; BEGIN
  PERFORM set_config('app.user_id', '00000000-0000-4000-8000-0000000013b3', true);
  UPDATE public.meter_correction_holds SET status = 'unrecoverable', closure_artifact_ref = 'Seller letter 7', counsel_referral = true WHERE id = pg_temp.id('h_e9');
  PERFORM set_config('app.user_id', '00000000-0000-4000-8000-0000000013b1', true);
  SELECT * INTO h FROM public.meter_correction_holds WHERE id = pg_temp.id('h_e9');
  IF h.status <> 'unrecoverable' OR h.closed_by <> '00000000-0000-4000-8000-0000000013b3' THEN RAISE EXCEPTION 'H14 FAILED'; END IF;
  BEGIN
    UPDATE public.meter_correction_holds SET closure_artifact_ref = 'changed' WHERE id = pg_temp.id('h_e9');
    RAISE EXCEPTION 'H14b FAILED: a closed hold changed';
  EXCEPTION WHEN restrict_violation THEN NULL; END;
  RAISE NOTICE 'PASS H14: a supervisor closes the predecessor hold unrecoverable with an artifact and the counsel flag; the closure is stamped and final';
END $$;

-- ======================================================================== I
DO $$ BEGIN
  UPDATE public.meter_correction_cases SET status = 'frozen' WHERE id = '00000000-0000-4000-8000-0000000013a9';
  RAISE EXCEPTION 'I1 FAILED';
EXCEPTION WHEN restrict_violation THEN RAISE NOTICE 'PASS I1: a case never evaluated cannot freeze'; END $$;
DO $$ BEGIN
  UPDATE public.meter_correction_cases SET status = 'open', anchor_date = DATE '2026-06-01' WHERE id = pg_temp.id('c_e1');
  RAISE EXCEPTION 'I2 FAILED: unfroze and moved the anchor in one statement';
EXCEPTION WHEN restrict_violation THEN NULL; END $$;
DO $$ BEGIN
  UPDATE public.meter_correction_cases SET cause_change_reason = 'x' WHERE id = pg_temp.id('c_e1');
  RAISE EXCEPTION 'I2 FAILED: a frozen case changed';
EXCEPTION WHEN restrict_violation THEN RAISE NOTICE 'PASS I2: a frozen case does not change, and unfreezing cannot carry a change to what it froze (R-38)'; END $$;
DO $$ BEGIN
  UPDATE public.meter_correction_cases SET frozen_evaluation_id = pg_temp.id('v_e3') WHERE id = pg_temp.id('c_e2');
  RAISE EXCEPTION 'I3 FAILED';
EXCEPTION WHEN restrict_violation THEN RAISE NOTICE 'PASS I3: the frozen evaluation is the database''s to set — a caller cannot point a case at another case''s evidence'; END $$;

-- I4: a bill loaded after the freeze makes the frozen evidence stale.
RESET ROLE;
INSERT INTO b13 VALUES ('e1_legacy', pg_temp.bill('00000000-0000-4000-8000-0000000013e1', '00000000-0000-4000-8000-0000000013c1', '00000000-0000-4000-8000-0000000013d1', '2025-12-15', '2026-01-14'));
SET ROLE tally_app;
DO $$ DECLARE s record; BEGIN
  SELECT * INTO s FROM public.meter_correction_case_status WHERE case_id = pg_temp.id('c_e1');
  IF s.evaluation_current IS DISTINCT FROM false OR s.status <> 'frozen' THEN RAISE EXCEPTION 'I4 FAILED: current=%', s.evaluation_current; END IF;
  RAISE NOTICE 'PASS I4: a legacy bill loaded after the freeze shows the frozen case as stale on the status surface';
END $$;
DO $$ DECLARE s text; BEGIN
  UPDATE public.meter_correction_cases SET status = 'open' WHERE id = pg_temp.id('c_e1');
  BEGIN
    UPDATE public.meter_correction_cases SET status = 'frozen' WHERE id = pg_temp.id('c_e1');
    RAISE EXCEPTION 'I5 FAILED: froze on stale evidence';
  EXCEPTION WHEN restrict_violation THEN NULL; END;
  PERFORM pg_temp.ev(pg_temp.id('c_e1'), ARRAY[-4, -5, -6, -7, -8, -9, -10]);
  UPDATE public.meter_correction_holds SET status = 'completed' WHERE id = pg_temp.id('h_e1');
  UPDATE public.meter_correction_cases SET status = 'frozen' WHERE id = pg_temp.id('c_e1');
  SELECT status INTO s FROM public.meter_correction_cases WHERE id = pg_temp.id('c_e1');
  IF s <> 'frozen' THEN RAISE EXCEPTION 'I5b FAILED'; END IF;
  RAISE NOTICE 'PASS I5: unfreeze, the stale evaluation refuses to freeze; re-evaluate over the loaded bill, the hold completes, the case freezes again';
END $$;

-- I6: D-5 — a test entered late changes the governing test.
DO $$ DECLARE s text; e record; BEGIN
  UPDATE public.meter_correction_cases SET status = 'frozen' WHERE id = pg_temp.id('c_e6');
  INSERT INTO b13 VALUES ('t_e6late', pg_temp.rec('00000000-0000-4000-8000-0000000013e6', DATE '2026-05-01', 100.5));
  UPDATE public.meter_correction_cases SET status = 'open' WHERE id = pg_temp.id('c_e6');
  BEGIN
    UPDATE public.meter_correction_cases SET status = 'frozen' WHERE id = pg_temp.id('c_e6');
    RAISE EXCEPTION 'I6 FAILED: froze past a late-entered test';
  EXCEPTION WHEN restrict_violation THEN NULL; END;
  INSERT INTO b13 VALUES ('v_e6b', pg_temp.ev(pg_temp.id('c_e6'), ARRAY[40, 41]));
  SELECT * INTO e FROM public.meter_correction_evaluations WHERE id = pg_temp.id('v_e6b');
  IF e.governing_test_id <> pg_temp.id('t_e6late') OR e.window_start <> DATE '2026-05-01' OR NOT e.governing_entered_out_of_order THEN
    RAISE EXCEPTION 'I6b FAILED: governing % window % ooo %', e.governing_test_id, e.window_start, e.governing_entered_out_of_order; END IF;
  UPDATE public.meter_correction_cases SET status = 'frozen' WHERE id = pg_temp.id('c_e6');
  RAISE NOTICE 'PASS I6: a test entered late (D-5) is accepted, flagged, and stops a freeze on the old evidence; re-evaluated, its date sets the window and the evidence carries entered_out_of_order';
END $$;
DO $$ BEGIN
  PERFORM pg_temp.rec('00000000-0000-4000-8000-0000000013e6', DATE '2026-05-01', 100.4, pg_temp.id('t_e6late'));
  RAISE EXCEPTION 'I7 FAILED: a test a frozen case rests on was superseded';
EXCEPTION WHEN restrict_violation THEN
  RAISE NOTICE 'PASS I7: the governing test of a frozen case cannot be superseded until the case is unfrozen (CI-091 §3.6)'; END $$;
DO $$ BEGIN
  PERFORM pg_temp.rec('00000000-0000-4000-8000-0000000013e1', DATE '2026-06-15', 103.5, pg_temp.id('t_e1'));
  RAISE EXCEPTION 'I8 FAILED';
EXCEPTION WHEN restrict_violation THEN RAISE NOTICE 'PASS I8: nor its discovering test'; END $$;
DO $$ BEGIN
  UPDATE public.meter_correction_cases SET status = 'open' WHERE id = pg_temp.id('c_e6');
  PERFORM pg_temp.rec('00000000-0000-4000-8000-0000000013e6', DATE '2026-05-01', 100.4, pg_temp.id('t_e6late'));
  RAISE NOTICE 'PASS I9: once unfrozen, the test may be corrected';
END $$;
UPDATE public.meter_correction_cases SET status = 'open' WHERE id = pg_temp.id('c_e1');
DO $$ BEGIN
  UPDATE public.meter_correction_cases SET status = 'withdrawn', withdrawn_reason = 'no longer wanted' WHERE id = pg_temp.id('c_e1');
  RAISE EXCEPTION 'I10 FAILED: a refund duty was withdrawn';
EXCEPTION WHEN restrict_violation THEN
  RAISE NOTICE 'PASS I10: a fast-meter case cannot be withdrawn while its test stands — that would be the decline R-37 forbids'; END $$;
DO $$ DECLARE s text; BEGIN
  PERFORM pg_temp.rec('00000000-0000-4000-8000-0000000013e5', DATE '2026-06-15', 101, pg_temp.id('t_e5'));
  UPDATE public.meter_correction_cases SET status = 'withdrawn', withdrawn_reason = 'test corrected: meter within tolerance' WHERE id = pg_temp.id('c_e5');
  SELECT status INTO s FROM public.meter_correction_cases WHERE id = pg_temp.id('c_e5');
  IF s <> 'withdrawn' THEN RAISE EXCEPTION 'I11 FAILED'; END IF;
  BEGIN
    UPDATE public.meter_correction_cases SET notes = 'x' WHERE id = pg_temp.id('c_e5');
    RAISE EXCEPTION 'I11b FAILED: a withdrawn case changed';
  EXCEPTION WHEN restrict_violation THEN NULL; END;
  RAISE NOTICE 'PASS I11: once the test is corrected the case may be withdrawn, and a withdrawn case is closed';
END $$;
DO $$ BEGIN
  INSERT INTO public.meter_correction_cases (tenant_id, meter_id, cause, discovering_test_id)
  VALUES ('00000000-0000-4000-8000-0000000013a1', '00000000-0000-4000-8000-0000000013e5', 'meter_error', pg_temp.id('t_e5'));
  RAISE EXCEPTION 'I12 FAILED';
EXCEPTION WHEN restrict_violation THEN RAISE NOTICE 'PASS I12: a superseded test cannot discover a new case'; END $$;
DO $$ BEGIN
  PERFORM pg_temp.ev(pg_temp.id('c_e3'), ARRAY[10, 11, 12]);
  UPDATE public.meter_correction_cases SET status = 'frozen', cause_change_reason = 'x', cause = 'non_registering_meter' WHERE id = pg_temp.id('c_e3');
  RAISE EXCEPTION 'I13 FAILED';
EXCEPTION WHEN restrict_violation THEN RAISE NOTICE 'PASS I13: freezing and changing the cause in one statement is refused'; END $$;
DO $$ DECLARE n int; BEGIN
  SELECT count(*) INTO n FROM public.meter_correction_case_events
   WHERE case_id = pg_temp.id('c_e1') AND event_type IN ('frozen', 'unfrozen', 'hold_opened', 'hold_completed', 'evaluated');
  IF n < 8 THEN RAISE EXCEPTION 'I14 FAILED: % events', n; END IF;
  RAISE NOTICE 'PASS I14: evaluations, freezes, unfreezes and hold events are on the case log (% rows)', n;
END $$;

-- ======================================================================== J
DO $$ DECLARE f record; BEGIN
  SELECT * INTO f FROM public.backbilling_forfeitures WHERE case_id = pg_temp.id('c_e2');
  IF f.forfeit_reason <> 'straddles_window' OR f.forfeited_amount <> 20 OR f.days_in_window <> 22 THEN RAISE EXCEPTION 'J2 FAILED'; END IF;
  IF (SELECT count(*) FROM public.backbilling_forfeitures WHERE case_id = pg_temp.id('c_e2')) <> 1 THEN
    RAISE EXCEPTION 'J2b FAILED: the superseded tenant-limit evaluation leaked onto the surface'; END IF;
  RAISE NOTICE 'PASS J2: backbilling_forfeitures shows the governing evaluation''s forfeiture only — the superseded one stays in the evaluations, off the surface';
END $$;
DO $$ DECLARE s record; BEGIN
  SELECT * INTO s FROM public.meter_correction_case_status WHERE case_id = pg_temp.id('c_e1');
  IF s.status <> 'open' OR s.evaluation_current IS NOT TRUE OR s.uncovered_days <> 0 OR s.open_holds <> 0 THEN
    RAISE EXCEPTION 'J3 FAILED: % % % %', s.status, s.evaluation_current, s.uncovered_days, s.open_holds; END IF;
  SELECT * INTO s FROM public.meter_correction_case_status WHERE case_id = pg_temp.id('c_e3');
  IF NOT s.gate_pending THEN RAISE EXCEPTION 'J3b FAILED'; END IF;
  RAISE NOTICE 'PASS J3: meter_correction_case_status reports currency, uncovered days, open holds and a pending R-36 approval';
END $$;


-- ======================================================================== M
-- Review round 1 (Fable + Opus, frozen a00683c5): one discriminating check
-- per finding, each proved by a planted mutation (mutations-13.py M50+).
RESET ROLE;
INSERT INTO public.service_locations (id, tenant_id, customer_id, location_number, address_line1, city, state, zip) VALUES
  ('00000000-0000-4000-8000-0000000013d8', '00000000-0000-4000-8000-0000000013a1', '00000000-0000-4000-8000-0000000013c1', 'L8', '8 Main', 'Austin', 'TX', '78708');
-- L8: an OLD meter removed in 2015 (ordinary migrated history), and a new
-- meter whose only deployment is its onboarding date.
INSERT INTO public.meters (id, tenant_id, meter_number, location_id, service_type, start_date, status) VALUES
  ('00000000-0000-4000-8000-000000001390', '00000000-0000-4000-8000-0000000013a1', 'M-OLD', '00000000-0000-4000-8000-0000000013d8', 'gas', DATE '2014-01-01', 'active'),
  ('00000000-0000-4000-8000-000000001391', '00000000-0000-4000-8000-0000000013a1', 'M-NEW', '00000000-0000-4000-8000-0000000013d8', 'gas', DATE '2026-01-20', 'active'),
  ('00000000-0000-4000-8000-000000001392', '00000000-0000-4000-8000-0000000013a1', 'M-2WAY', '00000000-0000-4000-8000-0000000013d1', 'gas', DATE '2024-01-01', 'active'),
  ('00000000-0000-4000-8000-000000001393', '00000000-0000-4000-8000-0000000013a1', 'M-OPEN', '00000000-0000-4000-8000-0000000013d1', 'gas', DATE '2024-01-01', 'inactive');
UPDATE public.meter_deployments SET removal_date = DATE '2015-06-01', removal_reason = 'end_of_life'
 WHERE meter_id = '00000000-0000-4000-8000-000000001390';
SET ROLE tally_app;

-- M1 (both, CRITICAL/HIGH): the direction cannot ride a status change.
DO $$ BEGIN
  UPDATE public.meter_correction_cases SET status = 'frozen' WHERE id = pg_temp.id('c_e4');
  BEGIN
    UPDATE public.meter_correction_cases SET status = 'open', direction = 'customer_owes' WHERE id = pg_temp.id('c_e4');
    RAISE EXCEPTION 'M1 FAILED: unfroze a fast case as a charge';
  EXCEPTION WHEN restrict_violation THEN NULL; END;
  UPDATE public.meter_correction_cases SET status = 'open' WHERE id = pg_temp.id('c_e4');
  BEGIN
    UPDATE public.meter_correction_cases SET status = 'frozen', direction = 'customer_owes' WHERE id = pg_temp.id('c_e4');
    RAISE EXCEPTION 'M1b FAILED: froze a fast case as a charge';
  EXCEPTION WHEN restrict_violation THEN NULL; END;
  BEGIN
    UPDATE public.meter_correction_cases SET direction = 'customer_owes' WHERE id = pg_temp.id('c_e4');
    RAISE EXCEPTION 'M1c FAILED: flipped an open fast case''s direction';
  EXCEPTION WHEN restrict_violation THEN NULL; END;
  RAISE NOTICE 'PASS M1: a fast case''s direction cannot be flipped — not with the statement that unfreezes or freezes it, and not on its own (round 1, both reviewers)';
END $$;
-- M2 (Opus F2): a status change carries nothing else — approved tamper evidence stays put.
DO $$ BEGIN
  PERFORM set_config('app.user_id', '00000000-0000-4000-8000-0000000013b3', true);
  UPDATE public.meter_correction_cases SET status = 'withdrawn', withdrawn_reason = 'swap',
         tamper_evidence_kind = 'field_report', tamper_deployment_id = NULL, tamper_field_report_ref = 'anything'
   WHERE id = '00000000-0000-4000-8000-0000000013a9';
  RAISE EXCEPTION 'M2 FAILED: a status change carried an evidence swap';
EXCEPTION WHEN restrict_violation THEN
  PERFORM set_config('app.user_id', '00000000-0000-4000-8000-0000000013b1', true);
  IF SQLERRM NOT LIKE '%cannot carry a change%' THEN RAISE EXCEPTION 'M2 FAILED for the wrong reason: %', SQLERRM; END IF;
  RAISE NOTICE 'PASS M2: a change of status cannot carry a change to the case (the approved tamper evidence stays)'; END $$;
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000013b1', true);
-- M3 (Opus F1): withdrawal keys on what the test NOW finds.
INSERT INTO b13 VALUES ('t_e4b', pg_temp.rec('00000000-0000-4000-8000-0000000013e4', DATE '2026-06-15', 104, pg_temp.id('t_e4')));
DO $$ BEGIN
  UPDATE public.meter_correction_cases SET status = 'withdrawn', withdrawn_reason = 'test corrected' WHERE id = pg_temp.id('c_e4');
  RAISE EXCEPTION 'M3 FAILED: withdrew while the corrected test still finds the meter fast';
EXCEPTION WHEN restrict_violation THEN
  RAISE NOTICE 'PASS M3: a fast test "corrected" to a faster reading does not free the case for withdrawal'; END $$;
-- M4 (both, HIGH): a case resting on a corrected test neither evaluates nor freezes.
DO $$ DECLARE s record; BEGIN
  BEGIN
    PERFORM pg_temp.ev(pg_temp.id('c_e4'), ARRAY[-1, -2, -3, -4]);
    RAISE EXCEPTION 'M4 FAILED: evaluated on a corrected test';
  EXCEPTION WHEN restrict_violation THEN NULL; END;
  BEGIN
    UPDATE public.meter_correction_cases SET status = 'frozen' WHERE id = pg_temp.id('c_e4');
    RAISE EXCEPTION 'M4b FAILED: froze on a corrected test';
  EXCEPTION WHEN restrict_violation THEN NULL; END;
  SELECT * INTO s FROM public.meter_correction_case_status WHERE case_id = pg_temp.id('c_e4');
  IF NOT s.discovering_test_superseded OR s.evaluation_current IS NOT FALSE THEN
    RAISE EXCEPTION 'M4c FAILED: surface % %', s.discovering_test_superseded, s.evaluation_current; END IF;
  RAISE NOTICE 'PASS M4: a case whose discovering test was corrected cannot evaluate or freeze, and the status surface says so';
END $$;
-- M5 (Fable F4a/c): the application cannot insert a deployment already over.
DO $$ BEGIN
  INSERT INTO public.meter_deployments (tenant_id, meter_id, deployment_number, location_id, install_date, removal_date, removal_reason)
  VALUES ('00000000-0000-4000-8000-0000000013a1', '00000000-0000-4000-8000-000000001393', 1,
          '00000000-0000-4000-8000-0000000013d1', DATE '2020-01-01', DATE '2025-12-15', 'relocation');
  RAISE EXCEPTION 'M5 FAILED: a closed history row was written by the application';
EXCEPTION WHEN restrict_violation THEN
  RAISE NOTICE 'PASS M5: a deployment entered already removed is refused — history loads are the owner''s'; END $$;
-- M6 (Fable F4b): a predecessor removed years before the window corroborates nothing.
DO $$ DECLARE v uuid; e record; BEGIN
  INSERT INTO b13 VALUES ('t_new', pg_temp.rec('00000000-0000-4000-8000-000000001391', DATE '2026-06-15', 103));
  INSERT INTO public.meter_correction_cases (id, tenant_id, meter_id, cause, discovering_test_id)
  VALUES ('00000000-0000-4000-8000-0000000013ac', '00000000-0000-4000-8000-0000000013a1', '00000000-0000-4000-8000-000000001391', 'meter_error', pg_temp.id('t_new'));
  INSERT INTO public.meter_correction_evaluations (tenant_id, case_id, submitted_amounts)
  VALUES ('00000000-0000-4000-8000-0000000013a1', '00000000-0000-4000-8000-0000000013ac', '{}'::jsonb) RETURNING id INTO v;
  SELECT * INTO e FROM public.meter_correction_evaluations WHERE id = v;
  IF e.window_start <> DATE '2025-12-15' OR e.deployment_bound IS NOT NULL OR (e.inputs ->> 'deployment_corroborated')::boolean THEN
    RAISE EXCEPTION 'M6 FAILED: window % bound % corroborated %', e.window_start, e.deployment_bound, e.inputs ->> 'deployment_corroborated'; END IF;
  RAISE NOTICE 'PASS M6: a meter removed from the premise in 2015 does not corroborate a 2026 onboarding-date start — the refund window stays 2025-12-15';
END $$;
-- M7 (Opus F5): a completed hold covers nothing once its bills are voided,
-- and does not block holding those days again.
DO $$ DECLARE n int; s text; BEGIN
  PERFORM public.void_invoice(pg_temp.id('e1_legacy'), '00000000-0000-4000-8000-0000000013b1', 'wrong_read', 'battery M7', false);
  PERFORM pg_temp.ev(pg_temp.id('c_e1'), ARRAY[-5, -6, -7, -8, -9, -10]);
  BEGIN
    UPDATE public.meter_correction_cases SET status = 'frozen' WHERE id = pg_temp.id('c_e1');
    RAISE EXCEPTION 'M7 FAILED: froze on a completed hold whose bill was voided';
  EXCEPTION WHEN restrict_violation THEN NULL; END;
  INSERT INTO public.meter_correction_holds (tenant_id, case_id, range_start, range_end, hold_code)
  VALUES ('00000000-0000-4000-8000-0000000013a1', pg_temp.id('c_e1'), DATE '2025-12-15', DATE '2026-01-14', 'legacy_records_not_loaded');
  UPDATE public.meter_correction_cases SET status = 'frozen' WHERE id = pg_temp.id('c_e1');
  SELECT status INTO s FROM public.meter_correction_cases WHERE id = pg_temp.id('c_e1');
  IF s <> 'frozen' THEN RAISE EXCEPTION 'M7b FAILED'; END IF;
  RAISE NOTICE 'PASS M7: voiding the bills that completed a hold reopens the gap — the freeze refuses until the days are held again, and the completed hold does not block the new one';
END $$;
-- M8 (both): the reissue gate matches overlapping days by premise or meter.
SELECT pg_temp.inv('00000000-0000-4000-8000-000000001340', 'R-SHIFT', '00000000-0000-4000-8000-000000001306', 'regular', NULL, '2026-05-02', '2026-05-31', 150.00, 50);
SELECT pg_temp.snap('00000000-0000-4000-8000-000000001340', '2026-05-31', now());
SELECT pg_temp.inv('00000000-0000-4000-8000-000000001341', 'R-SPAN', '00000000-0000-4000-8000-000000001306', 'regular', NULL, '2026-04-01', '2026-05-31', 900.00, 300);
SELECT pg_temp.snap('00000000-0000-4000-8000-000000001341', '2026-05-31', now());
SELECT pg_temp.inv('00000000-0000-4000-8000-000000001342', 'R-ELSEWHERE', '00000000-0000-4000-8000-000000001306', 'regular', NULL, '2026-05-01', '2026-05-31', 150.00, 50);
UPDATE public.invoices SET location_id = '00000000-0000-4000-8000-0000000013d1' WHERE id = '00000000-0000-4000-8000-000000001342';
SELECT pg_temp.snap('00000000-0000-4000-8000-000000001342', '2026-05-31', now());
DO $$ DECLARE k text; n int := 0; BEGIN
  FOREACH k IN ARRAY ARRAY['00000000-0000-4000-8000-000000001340', '00000000-0000-4000-8000-000000001341', '00000000-0000-4000-8000-000000001342'] LOOP
    BEGIN
      UPDATE public.invoices SET status = 'pending' WHERE id = k::uuid;
      RAISE EXCEPTION 'M8 FAILED: % issued', k;
    EXCEPTION WHEN restrict_violation THEN n := n + 1; END;
  END LOOP;
  RAISE NOTICE 'PASS M8: a rebill of voided days shifted by a day, spanning two voided months, or addressed to another premise on the same meter is refused (% of 3)', n;
END $$;
-- M9 (Opus F7): opposite findings on one day cannot be cited.
INSERT INTO b13 VALUES ('t_2f', pg_temp.rec('00000000-0000-4000-8000-000000001392', DATE '2026-06-15', 103));
INSERT INTO b13 VALUES ('t_2s', pg_temp.rec('00000000-0000-4000-8000-000000001392', DATE '2026-06-15', 97));
DO $$ BEGIN
  INSERT INTO public.meter_correction_cases (tenant_id, meter_id, cause, discovering_test_id)
  VALUES ('00000000-0000-4000-8000-0000000013a1', '00000000-0000-4000-8000-000000001392', 'meter_error', pg_temp.id('t_2s'));
  RAISE EXCEPTION 'M9 FAILED: a slow finding was cited beside a same-day fast one';
EXCEPTION WHEN restrict_violation THEN
  RAISE NOTICE 'PASS M9: a meter found fast and slow on the same day cannot carry a case until the history is corrected'; END $$;
-- M10 (both): a fast meter's billed period cannot be refunded at zero.
DO $$ BEGIN
  PERFORM pg_temp.ev(pg_temp.id('c_e9'), ARRAY[0, -2, -3, -4]);
  RAISE EXCEPTION 'M10 FAILED: a zero refund on a billed period';
EXCEPTION WHEN invalid_parameter_value THEN
  RAISE NOTICE 'PASS M10: a zero correction on a period that billed usage is refused on a test-anchored case'; END $$;
-- M11 (Fable F6): one live case per finding.
DO $$ BEGIN
  INSERT INTO public.meter_correction_cases (tenant_id, meter_id, cause, discovering_test_id)
  VALUES ('00000000-0000-4000-8000-0000000013a1', '00000000-0000-4000-8000-0000000013e2', 'meter_error', pg_temp.id('t_e2'));
  RAISE EXCEPTION 'M11 FAILED: a second live case on one test';
EXCEPTION WHEN unique_violation THEN RAISE NOTICE 'PASS M11: a second live case on the same discovering test is refused (it would post twice)'; END $$;
-- M12 (Opus): a fast finding with no case is on a standing surface.
DO $$ DECLARE n int; BEGIN
  SELECT count(*) INTO n FROM public.meter_fast_findings_without_case WHERE meter_test_id = pg_temp.id('t_2f');
  IF n <> 1 THEN RAISE EXCEPTION 'M12 FAILED'; END IF;
  SELECT count(*) INTO n FROM public.meter_fast_findings_without_case WHERE meter_test_id IN (pg_temp.id('t_e1'), pg_temp.id('t_e4'), pg_temp.id('t_e5'));
  IF n <> 0 THEN RAISE EXCEPTION 'M12b FAILED: % listed', n; END IF;
  RAISE NOTICE 'PASS M12: meter_fast_findings_without_case lists a fast test no case rests on, and neither one that has a case nor one since corrected';
END $$;

-- ======================================================================== K
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000013b2', true);
DO $$ DECLARE n int; BEGIN
  SELECT (SELECT count(*) FROM public.meter_correction_cases) + (SELECT count(*) FROM public.meter_correction_evaluations)
       + (SELECT count(*) FROM public.meter_correction_period_evidence) + (SELECT count(*) FROM public.meter_correction_holds)
       + (SELECT count(*) FROM public.meter_correction_case_events) + (SELECT count(*) FROM public.backbilling_forfeitures)
       + (SELECT count(*) FROM public.meter_correction_case_status) + (SELECT count(*) FROM public.service_location_acquisitions)
       + (SELECT count(*) FROM public.meter_correction_approvals)
    INTO n;
  IF n <> 0 THEN RAISE EXCEPTION 'K1 FAILED: T2 sees % T1 rows', n; END IF;
  SELECT count(*) INTO n FROM public.backbilling_cap_rules;
  IF n <> 16 THEN RAISE EXCEPTION 'K1b FAILED: T2 sees % cap rows', n; END IF;
  RAISE NOTICE 'PASS K1: tenant 2 sees none of tenant 1''s cases, evaluations, evidence, holds, log, approvals, acquisitions or surfaces — and only its own 16 cap rows';
END $$;
DO $$ BEGIN
  INSERT INTO public.meter_correction_evaluations (tenant_id, case_id, submitted_amounts)
  VALUES ('00000000-0000-4000-8000-0000000013a2', pg_temp.id('c_e3'), '{}'::jsonb);
  RAISE EXCEPTION 'K2 FAILED';
EXCEPTION WHEN no_data_found THEN RAISE NOTICE 'PASS K2: tenant 2 cannot evaluate tenant 1''s case'; END $$;
DO $$ BEGIN
  INSERT INTO public.meter_correction_cases (tenant_id, meter_id, cause, anchor_date, claimed_from)
  VALUES ('00000000-0000-4000-8000-0000000013a2', '00000000-0000-4000-8000-0000000013e8', 'crossed_meters', DATE '2026-06-01', DATE '2026-01-01');
  RAISE EXCEPTION 'K3 FAILED: a case on another tenant''s meter';
EXCEPTION WHEN foreign_key_violation THEN RAISE NOTICE 'PASS K3: tenant 2 cannot open a case on tenant 1''s meter (composite key)'; END $$;
DO $$ BEGIN
  UPDATE public.meter_correction_cases SET notes = 'x' WHERE id = pg_temp.id('c_e3');
  IF FOUND THEN RAISE EXCEPTION 'K4 FAILED'; END IF;
  RAISE NOTICE 'PASS K4: nor touch tenant 1''s case';
END $$;
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000013b1', true);

-- ======================================================================== L
RESET ROLE;
DO $$ BEGIN
  ALTER TABLE public.meter_correction_holds NO FORCE ROW LEVEL SECURITY;
  PERFORM public.assert_tenant_isolation_invariants();
  RAISE EXCEPTION 'L1 FAILED: the assertion passed with FORCE off';
EXCEPTION WHEN others THEN
  IF SQLERRM LIKE 'L1 FAILED%' THEN RAISE; END IF;
  RAISE NOTICE 'PASS L1: AC-32 raises when a new table loses FORCE RLS (%)', left(SQLERRM, 60); END $$;
DO $$ BEGIN
  EXECUTE 'CREATE VIEW public.bat13_leak AS SELECT * FROM public.meter_correction_cases';
  PERFORM public.assert_tenant_isolation_invariants();
  RAISE EXCEPTION 'L2 FAILED: the assertion passed an owner-rights view';
EXCEPTION WHEN others THEN
  IF SQLERRM LIKE 'L2 FAILED%' THEN RAISE; END IF;
  RAISE NOTICE 'PASS L2: AC-32 raises on an owner-rights view over the cases (%)', left(SQLERRM, 60); END $$;
DO $$ BEGIN
  PERFORM public.assert_tenant_isolation_invariants();
  RAISE NOTICE 'PASS L3: and holds on the patch as applied';
END $$;

ROLLBACK;
