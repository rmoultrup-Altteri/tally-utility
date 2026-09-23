-- ============================================================================
-- BATTERY v5.4.2-12 — the meter test history (CI-091; Kyle R-31, R-34…R-36)
-- Run: psql -U tally -d <db-with-patch> -v ON_ERROR_STOP=1 -f battery-12.sql
-- One transaction, rolled back. Negative cases inside DO exception handlers
-- that check the SQLSTATE, so a setup failure is never mistaken for the
-- refusal under test. Written end-to-end as tally_app except where a group
-- says otherwise (owner-level checks of the append-only triggers; planted
-- drift for the AC-32 assertion). TWO tenants throughout.
--
-- Groups map to brief §6 as rewritten by Kyle's 2026-09-22 record §8:
--   A  outcome derived from readings, both sides of the 2.0% boundary (§6.2)
--   B  append-only, including an UPDATE to a column's own value (§6.1)
--   C  the meters pointer: late entry, supersession, direct writes (§6.3-4)
--   D  tenancy on every link (§6.6)
--   E  migration, record_basis and the cutover invariant (§6.5, R-35/36)
--   F  the governing test — R-34's reading, not the brief's (§6.7)
--   G  the gap report (R-35 refinement 1)
--   H  the threshold table is platform-fixed (F-3)
--   J  AC-32 raises on planted drift (§6.8)
-- ============================================================================
BEGIN;
SET CONSTRAINTS ALL IMMEDIATE;

-- ---------------------------------------------------------------- fixtures
-- T1 cut over 2026-01-15, so R-36's gate runs to 2026-07-15. T2 not cut over.
INSERT INTO public.tenants (id, name, slug, cutover_date) VALUES
  ('00000000-0000-4000-8000-0000000012a1', 'T1 Gasco', 'bat12-t1', DATE '2026-01-15'),
  ('00000000-0000-4000-8000-0000000012a2', 'T2 Gasco', 'bat12-t2', NULL);
INSERT INTO public.users (id, tenant_id, display_name, email, role) VALUES
  ('00000000-0000-4000-8000-0000000012b1', '00000000-0000-4000-8000-0000000012a1', 'U1', 'u1@bat12.test', 'operator'),
  ('00000000-0000-4000-8000-0000000012b2', '00000000-0000-4000-8000-0000000012a2', 'U2', 'u2@bat12.test', 'operator');
INSERT INTO public.customers (id, tenant_id, customer_number) VALUES
  ('00000000-0000-4000-8000-0000000012c1', '00000000-0000-4000-8000-0000000012a1', 'BAT12-C1'),
  ('00000000-0000-4000-8000-0000000012c2', '00000000-0000-4000-8000-0000000012a2', 'BAT12-C2');
INSERT INTO public.service_locations (id, tenant_id, customer_id, location_number, address_line1, city, state, zip) VALUES
  ('00000000-0000-4000-8000-0000000012d1', '00000000-0000-4000-8000-0000000012a1', '00000000-0000-4000-8000-0000000012c1', 'LOC-1', '1 Main', 'Austin', 'TX', '78701'),
  ('00000000-0000-4000-8000-0000000012d3', '00000000-0000-4000-8000-0000000012a1', '00000000-0000-4000-8000-0000000012c1', 'LOC-3', '3 Main', 'Austin', ' tx ', '78703'),
  ('00000000-0000-4000-8000-0000000012d4', '00000000-0000-4000-8000-0000000012a1', '00000000-0000-4000-8000-0000000012c1', 'LOC-4', '4 Main', 'Austin', 'Texas', '78704'),
  ('00000000-0000-4000-8000-0000000012d5', '00000000-0000-4000-8000-0000000012a1', '00000000-0000-4000-8000-0000000012c1', 'LOC-5', '5 Main', 'Tulsa', 'OK', '74101'),
  ('00000000-0000-4000-8000-0000000012d2', '00000000-0000-4000-8000-0000000012a2', '00000000-0000-4000-8000-0000000012c2', 'LOC-2', '2 Main', 'Austin', 'TX', '78702');
-- M1 gas at LOC-1 (pointer scenarios), M3 gas at LOC-3 (governing scenarios;
-- state stored lower-case and padded), M4 gas at LOC-4 (state "Texas"),
-- M5 date-only gate, M6 no history, M7 a sibling of M3 at the same premise,
-- M8 water, M2 gas of T2.
INSERT INTO public.meters (id, tenant_id, meter_number, location_id, service_type) VALUES
  ('00000000-0000-4000-8000-0000000012e1', '00000000-0000-4000-8000-0000000012a1', 'M-1', '00000000-0000-4000-8000-0000000012d1', 'gas'),
  ('00000000-0000-4000-8000-0000000012e3', '00000000-0000-4000-8000-0000000012a1', 'M-3', '00000000-0000-4000-8000-0000000012d3', 'gas'),
  ('00000000-0000-4000-8000-0000000012e4', '00000000-0000-4000-8000-0000000012a1', 'M-4', '00000000-0000-4000-8000-0000000012d4', 'gas'),
  ('00000000-0000-4000-8000-0000000012e5', '00000000-0000-4000-8000-0000000012a1', 'M-5', '00000000-0000-4000-8000-0000000012d1', 'gas'),
  ('00000000-0000-4000-8000-0000000012e6', '00000000-0000-4000-8000-0000000012a1', 'M-6', '00000000-0000-4000-8000-0000000012d1', 'gas'),
  ('00000000-0000-4000-8000-0000000012e7', '00000000-0000-4000-8000-0000000012a1', 'M-7', '00000000-0000-4000-8000-0000000012d3', 'gas'),
  ('00000000-0000-4000-8000-0000000012e8', '00000000-0000-4000-8000-0000000012a1', 'M-8', '00000000-0000-4000-8000-0000000012d1', 'water'),
  ('00000000-0000-4000-8000-0000000012e2', '00000000-0000-4000-8000-0000000012a2', 'M-2', '00000000-0000-4000-8000-0000000012d2', 'gas');
INSERT INTO public.service_orders (id, tenant_id, order_number, order_type, description, meter_id) VALUES
  ('00000000-0000-4000-8000-0000000012f1', '00000000-0000-4000-8000-0000000012a1', 'SO-1', 'meter_test', 'test M-1', '00000000-0000-4000-8000-0000000012e1'),
  ('00000000-0000-4000-8000-0000000012f2', '00000000-0000-4000-8000-0000000012a1', 'SO-2', 'meter_install', 'install M-1', '00000000-0000-4000-8000-0000000012e1'),
  ('00000000-0000-4000-8000-0000000012f3', '00000000-0000-4000-8000-0000000012a1', 'SO-3', 'meter_test', 'test M-3', '00000000-0000-4000-8000-0000000012e3'),
  ('00000000-0000-4000-8000-0000000012f9', '00000000-0000-4000-8000-0000000012a2', 'SO-9', 'meter_test', 'test M-2', '00000000-0000-4000-8000-0000000012e2');

-- M-1 was once deployed at LOC-5, in Oklahoma — a past deployment in another
-- state, for D3b.
INSERT INTO public.meter_deployments (tenant_id, meter_id, deployment_number, location_id, install_date, removal_date)
VALUES ('00000000-0000-4000-8000-0000000012a1', '00000000-0000-4000-8000-0000000012e1', 0,
        '00000000-0000-4000-8000-0000000012d5', DATE '2020-01-01', DATE '2021-01-01');

-- Helpers. rec(): a full recorded test with the (7)(B)(ii) fields filled in.
-- ld(): one load point as JSON. Explicit EXECUTE grants: v5.4.2-11 revoked
-- PUBLIC's default on new functions, pg_temp ones included.
CREATE FUNCTION pg_temp.ld(p_point text, p_std numeric, p_met numeric) RETURNS jsonb LANGUAGE sql IMMUTABLE AS $$
  SELECT jsonb_build_object('load_point', p_point, 'standard_volume', p_std, 'meter_volume', p_met);
$$;
CREATE FUNCTION pg_temp.rec(p_meter uuid, p_date date, p_loads jsonb,
                            p_kind text DEFAULT 'periodic', p_supersedes uuid DEFAULT NULL,
                            p_reason text DEFAULT NULL,
                            p_tenant uuid DEFAULT '00000000-0000-4000-8000-0000000012a1') RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE v_id uuid;
BEGIN
  INSERT INTO public.meter_tests (tenant_id, meter_id, test_date, test_kind, record_basis,
        performed_by_name, test_equipment, meter_serial_at_test, multiplier_at_test,
        load_results, supersedes_test_id, supersede_reason)
  VALUES (p_tenant, p_meter, p_date, p_kind, 'recorded',
        'A. Tester', 'Bell prover BP-7', 'SN-' || left(p_meter::text, 4), 1.0,
        p_loads, p_supersedes, p_reason)
  RETURNING id INTO v_id;
  RETURN v_id;
END $$;
GRANT EXECUTE ON FUNCTION pg_temp.ld(text, numeric, numeric) TO tally_app;
GRANT EXECUTE ON FUNCTION pg_temp.rec(uuid, date, jsonb, text, uuid, text, uuid) TO tally_app;

-- A result table the DO blocks can write ids into across statements.
CREATE TEMP TABLE bat12_ids (k text PRIMARY KEY, id uuid);
GRANT SELECT, INSERT ON bat12_ids TO tally_app;

SET LOCAL app.user_id = '00000000-0000-4000-8000-0000000012b1';
SET ROLE tally_app;

-- ======================================================================= A
-- A1/A2: both sides of the boundary. "More than 2.0%": exactly 2 is accurate,
-- 2.01 is fast. The comparison is exact — no rounding before it.
DO $$
DECLARE v uuid; r record;
BEGIN
  v := pg_temp.rec('00000000-0000-4000-8000-0000000012e7', DATE '2026-02-01',
         jsonb_build_array(pg_temp.ld('check', 100, 102), pg_temp.ld('open', 100, 101)));
  SELECT outcome, max_abs_error_pct INTO r FROM public.meter_tests WHERE id = v;
  IF r.outcome <> 'accurate' OR r.max_abs_error_pct <> 2 THEN
    RAISE EXCEPTION 'A1 FAILED: 2.00%% deviation gave %, max %', r.outcome, r.max_abs_error_pct; END IF;
  RAISE NOTICE 'PASS A1: a deviation of exactly 2.00%% is accurate (the rule says MORE than 2.0%%)';

  v := pg_temp.rec('00000000-0000-4000-8000-0000000012e7', DATE '2026-02-02',
         jsonb_build_array(pg_temp.ld('check', 100, 102.01), pg_temp.ld('open', 100, 100)));
  SELECT outcome, max_abs_error_pct INTO r FROM public.meter_tests WHERE id = v;
  IF r.outcome <> 'fast' OR r.max_abs_error_pct <> 2.01 THEN
    RAISE EXCEPTION 'A2 FAILED: 2.01%% fast gave %, max %', r.outcome, r.max_abs_error_pct; END IF;
  RAISE NOTICE 'PASS A2: 2.01%% over-registration is fast';

  v := pg_temp.rec('00000000-0000-4000-8000-0000000012e7', DATE '2026-02-03',
         jsonb_build_array(pg_temp.ld('check', 100, 97.99)));
  SELECT outcome INTO r FROM public.meter_tests WHERE id = v;
  IF r.outcome <> 'slow' THEN RAISE EXCEPTION 'A3 FAILED: -2.01%% gave %', r.outcome; END IF;
  RAISE NOTICE 'PASS A3: 2.01%% under-registration is slow';

  v := pg_temp.rec('00000000-0000-4000-8000-0000000012e7', DATE '2026-02-04',
         jsonb_build_array(pg_temp.ld('check', 100, 100.0001)));
  SELECT outcome INTO r FROM public.meter_tests WHERE id = v;
  IF r.outcome <> 'accurate' THEN RAISE EXCEPTION 'A3b FAILED: 0.0001%% gave %', r.outcome; END IF;
  -- and a deviation a hair past the threshold is not rounded back into it
  v := pg_temp.rec('00000000-0000-4000-8000-0000000012e7', DATE '2026-02-05',
         jsonb_build_array(pg_temp.ld('check', 10000, 10200.0001)));
  SELECT outcome INTO r FROM public.meter_tests WHERE id = v;
  IF r.outcome <> 'fast' THEN RAISE EXCEPTION 'A3c FAILED: 2.000001%% gave %', r.outcome; END IF;
  RAISE NOTICE 'PASS A3b: 2.000001%% is fast — the comparison is exact, not rounded into "accurate"';

  v := pg_temp.rec('00000000-0000-4000-8000-0000000012e7', DATE '2026-02-06',
         jsonb_build_array(pg_temp.ld('check', 100, 0), pg_temp.ld('open', 250, 0)));
  SELECT outcome INTO r FROM public.meter_tests WHERE id = v;
  IF r.outcome <> 'non_registering' THEN RAISE EXCEPTION 'A4 FAILED: all-zero gave %', r.outcome; END IF;
  RAISE NOTICE 'PASS A4: zero registration at every load is non_registering — the (v)(II) bound';

  v := pg_temp.rec('00000000-0000-4000-8000-0000000012e7', DATE '2026-02-07',
         jsonb_build_array(pg_temp.ld('check', 100, 0), pg_temp.ld('open', 250, 250)));
  SELECT outcome INTO r FROM public.meter_tests WHERE id = v;
  IF r.outcome <> 'slow' THEN RAISE EXCEPTION 'A5 FAILED: dead-at-one-load gave %', r.outcome; END IF;
  RAISE NOTICE 'PASS A5: dead at one load but registering at another is slow, not non_registering (R-39: zero registration only)';

  v := pg_temp.rec('00000000-0000-4000-8000-0000000012e7', DATE '2026-02-08',
         jsonb_build_array(pg_temp.ld('check', 100, 103), pg_temp.ld('open', 100, 97)));
  SELECT outcome INTO r FROM public.meter_tests WHERE id = v;
  IF r.outcome <> 'inconclusive' THEN RAISE EXCEPTION 'A6 FAILED: +3/-3 gave %', r.outcome; END IF;
  RAISE NOTICE 'PASS A6: equal and opposite deviations beyond the threshold are inconclusive, not guessed';
END $$;

-- A7: a caller-supplied outcome is REFUSED on a full record — even one that
-- agrees with the readings. The negative has no setup of its own.
DO $$
BEGIN
  INSERT INTO public.meter_tests (tenant_id, meter_id, test_date, test_kind, record_basis,
        performed_by_name, test_equipment, meter_serial_at_test, multiplier_at_test, load_results, outcome)
  VALUES ('00000000-0000-4000-8000-0000000012a1', '00000000-0000-4000-8000-0000000012e7', DATE '2026-02-09', 'periodic', 'recorded',
        'A. Tester', 'prover', 'SN-1', 1.0, jsonb_build_array(pg_temp.ld('check', 100, 110)), 'accurate');
  RAISE EXCEPTION 'A7 FAILED: a caller-set outcome was accepted';
EXCEPTION WHEN restrict_violation THEN
  RAISE NOTICE 'PASS A7: a caller-supplied outcome on a recorded test is refused (a 10%% fast meter could otherwise be filed as accurate)';
END $$;
DO $$
BEGIN
  INSERT INTO public.meter_tests (tenant_id, meter_id, test_date, test_kind, record_basis,
        performed_by_name, test_equipment, meter_serial_at_test, multiplier_at_test, load_results, threshold_pct)
  VALUES ('00000000-0000-4000-8000-0000000012a1', '00000000-0000-4000-8000-0000000012e7', DATE '2026-02-09', 'periodic', 'recorded',
        'A. Tester', 'prover', 'SN-1', 1.0, jsonb_build_array(pg_temp.ld('check', 100, 104)), 5.0);
  RAISE EXCEPTION 'A8 FAILED: a caller-set threshold was accepted';
EXCEPTION WHEN restrict_violation THEN
  RAISE NOTICE 'PASS A8: a caller-supplied threshold is refused (a 4%% fast meter judged against 5%% would pass)';
END $$;

-- A9: the load rows are the readings, typed, with the error the outcome used.
DO $$
DECLARE n int; e numeric; t record;
BEGIN
  SELECT id INTO t FROM public.meter_tests WHERE meter_id = '00000000-0000-4000-8000-0000000012e7' AND test_date = DATE '2026-02-02';
  SELECT count(*), max(error_pct) INTO n, e FROM public.meter_test_load_results WHERE meter_test_id = t.id;
  IF n <> 2 OR e <> 2.01 THEN RAISE EXCEPTION 'A9 FAILED: % load rows, max error %', n, e; END IF;
  SELECT threshold_pct, threshold_state, threshold_id, recorded_by INTO t FROM public.meter_tests WHERE id = t.id;
  IF t.threshold_pct <> 2.000 OR t.threshold_state <> 'TX' OR t.threshold_id IS NULL
     OR t.recorded_by <> '00000000-0000-4000-8000-0000000012b1' THEN
    RAISE EXCEPTION 'A9 FAILED: threshold % / state % / id % / recorded_by %', t.threshold_pct, t.threshold_state, t.threshold_id, t.recorded_by; END IF;
  RAISE NOTICE 'PASS A9: two typed load rows written by the database (error 2.01 generated), threshold 2.000 TX snapshotted, recorded_by stamped from the session — M-3''s lower-case padded " tx " also resolved (see F)';
END $$;

-- A10: malformed readings. Each block's only statement is the refused insert.
DO $$ BEGIN
  PERFORM pg_temp.rec('00000000-0000-4000-8000-0000000012e7', DATE '2026-02-10', jsonb_build_array(pg_temp.ld('check', 100, 102.00001)));
  RAISE EXCEPTION 'A10a FAILED';
EXCEPTION WHEN invalid_parameter_value THEN RAISE NOTICE 'PASS A10a: a fifth decimal place is refused (the derived value must be the stored value)'; END $$;
DO $$ BEGIN
  PERFORM pg_temp.rec('00000000-0000-4000-8000-0000000012e7', DATE '2026-02-10', '[{"load_point":"check","standard_volume":100,"meter_volume":101,"error_pct":0}]'::jsonb);
  RAISE EXCEPTION 'A10b FAILED';
EXCEPTION WHEN invalid_parameter_value THEN RAISE NOTICE 'PASS A10b: an unknown key (a caller-supplied error_pct) is refused'; END $$;
DO $$ BEGIN
  PERFORM pg_temp.rec('00000000-0000-4000-8000-0000000012e7', DATE '2026-02-10', jsonb_build_array(pg_temp.ld('check', 0, 1)));
  RAISE EXCEPTION 'A10c FAILED';
EXCEPTION WHEN invalid_parameter_value THEN RAISE NOTICE 'PASS A10c: a zero standard volume is refused'; END $$;
DO $$ BEGIN
  PERFORM pg_temp.rec('00000000-0000-4000-8000-0000000012e7', DATE '2026-02-10', '[{"load_point":"check","standard_volume":"100","meter_volume":101}]'::jsonb);
  RAISE EXCEPTION 'A10d FAILED';
EXCEPTION WHEN invalid_parameter_value THEN RAISE NOTICE 'PASS A10d: a volume given as a string is refused'; END $$;
DO $$ BEGIN
  PERFORM pg_temp.rec('00000000-0000-4000-8000-0000000012e7', DATE '2026-02-10', '[]'::jsonb);
  RAISE EXCEPTION 'A10e FAILED';
EXCEPTION WHEN invalid_parameter_value THEN RAISE NOTICE 'PASS A10e: an empty readings array is refused'; END $$;
DO $$ BEGIN
  PERFORM pg_temp.rec('00000000-0000-4000-8000-0000000012e7', DATE '2026-02-10',
          jsonb_build_array(pg_temp.ld('check', 100, 101), pg_temp.ld('check', 100, 109)));
  RAISE EXCEPTION 'A10f FAILED';
EXCEPTION WHEN unique_violation THEN RAISE NOTICE 'PASS A10f: two readings for one load point are refused'; END $$;

-- A11: inconclusive is for a test with no valid measurement — and only then.
DO $$
DECLARE v uuid; o text;
BEGIN
  INSERT INTO public.meter_tests (tenant_id, meter_id, test_date, test_kind, record_basis,
        performed_by_name, test_equipment, meter_serial_at_test, multiplier_at_test, inconclusive_reason)
  VALUES ('00000000-0000-4000-8000-0000000012a1', '00000000-0000-4000-8000-0000000012e7', DATE '2026-02-11', 'periodic', 'recorded',
        'A. Tester', 'prover', 'SN-1', 1.0, 'prover lost pressure mid-run')
  RETURNING id, outcome INTO v, o;
  IF o <> 'inconclusive' THEN RAISE EXCEPTION 'A11 FAILED: %', o; END IF;
  RAISE NOTICE 'PASS A11: a test with no valid measurement and a reason is recorded inconclusive';
END $$;
DO $$ BEGIN
  INSERT INTO public.meter_tests (tenant_id, meter_id, test_date, test_kind, record_basis,
        performed_by_name, test_equipment, meter_serial_at_test, multiplier_at_test, inconclusive_reason, load_results)
  VALUES ('00000000-0000-4000-8000-0000000012a1', '00000000-0000-4000-8000-0000000012e7', DATE '2026-02-11', 'periodic', 'recorded',
        'A. Tester', 'prover', 'SN-1', 1.0, 'said so', jsonb_build_array(pg_temp.ld('check', 100, 110)));
  RAISE EXCEPTION 'A11b FAILED';
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'PASS A11b: an inconclusive_reason beside readings is refused — readings are judged, not labelled'; END $$;
DO $$ BEGIN
  INSERT INTO public.meter_tests (tenant_id, meter_id, test_date, test_kind, record_basis,
        performed_by_name, test_equipment, meter_serial_at_test, multiplier_at_test)
  VALUES ('00000000-0000-4000-8000-0000000012a1', '00000000-0000-4000-8000-0000000012e7', DATE '2026-02-11', 'periodic', 'recorded',
        'A. Tester', 'prover', 'SN-1', 1.0);
  RAISE EXCEPTION 'A11c FAILED';
EXCEPTION WHEN invalid_parameter_value THEN RAISE NOTICE 'PASS A11c: a full record with neither readings nor a reason is refused'; END $$;

-- A12 (§6.5): a recorded row missing a field-list column is refused; the
-- same bare row as migrated_date_only is accepted.
DO $$ BEGIN
  INSERT INTO public.meter_tests (tenant_id, meter_id, test_date, test_kind, record_basis,
        performed_by_name, meter_serial_at_test, multiplier_at_test, load_results)
  VALUES ('00000000-0000-4000-8000-0000000012a1', '00000000-0000-4000-8000-0000000012e7', DATE '2026-02-12', 'periodic', 'recorded',
        'A. Tester', 'SN-1', 1.0, jsonb_build_array(pg_temp.ld('check', 100, 100)));
  RAISE EXCEPTION 'A12 FAILED';
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'PASS A12: a recorded test with no test equipment is refused'; END $$;
DO $$ BEGIN
  INSERT INTO public.meter_tests (tenant_id, meter_id, test_date, test_kind, record_basis,
        performed_by_name, test_equipment, meter_serial_at_test, multiplier_at_test, load_results)
  VALUES ('00000000-0000-4000-8000-0000000012a1', '00000000-0000-4000-8000-0000000012e7', DATE '2026-02-12', 'periodic', 'recorded',
        ' ', 'prover', 'SN-1', 1.0, jsonb_build_array(pg_temp.ld('check', 100, 100)));
  RAISE EXCEPTION 'A12b FAILED';
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'PASS A12b: a blank tester name is refused (alphanumeric required)'; END $$;
DO $$
DECLARE v uuid;
BEGIN
  INSERT INTO public.meter_tests (tenant_id, meter_id, test_date, test_kind, record_basis)
  VALUES ('00000000-0000-4000-8000-0000000012a1', '00000000-0000-4000-8000-0000000012e7', DATE '2025-12-01', 'other', 'migrated_date_only')
  RETURNING id INTO v;
  RAISE NOTICE 'PASS A12c: the same bare row as migrated_date_only is accepted — a date is the whole (7)(B)(i) requirement (F-2)';
END $$;

-- A13 (R5, R6): no threshold, no outcome — refused, never defaulted.
DO $$ BEGIN
  PERFORM pg_temp.rec('00000000-0000-4000-8000-0000000012e4', DATE '2026-02-13', jsonb_build_array(pg_temp.ld('check', 100, 100)));
  RAISE EXCEPTION 'A13 FAILED';
EXCEPTION WHEN no_data_found THEN RAISE NOTICE 'PASS A13: a premise whose state reads "Texas" finds no threshold and the test refuses (R5)'; END $$;
DO $$ BEGIN
  PERFORM pg_temp.rec('00000000-0000-4000-8000-0000000012e8', DATE '2026-02-13', jsonb_build_array(pg_temp.ld('check', 100, 100)));
  RAISE EXCEPTION 'A13b FAILED';
EXCEPTION WHEN no_data_found THEN RAISE NOTICE 'PASS A13b: a water meter finds no threshold — 2.0%% is the gas figure (F-3, R6)'; END $$;

-- A14 (D-4 / F-5): a customer-requested test names the customer and premise.
DO $$ BEGIN
  PERFORM pg_temp.rec('00000000-0000-4000-8000-0000000012e7', DATE '2026-02-14', jsonb_build_array(pg_temp.ld('check', 100, 100)), 'customer_requested');
  RAISE EXCEPTION 'A14 FAILED';
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'PASS A14: a customer-requested test without customer and location is refused'; END $$;
DO $$
DECLARE cr boolean;
BEGIN
  INSERT INTO public.meter_tests (tenant_id, meter_id, test_date, test_kind, record_basis, location_id, customer_id,
        performed_by_user_id, performed_by_name, test_equipment, meter_serial_at_test, multiplier_at_test, load_results)
  VALUES ('00000000-0000-4000-8000-0000000012a1', '00000000-0000-4000-8000-0000000012e7', DATE '2026-02-14', 'customer_requested', 'recorded',
        '00000000-0000-4000-8000-0000000012d3', '00000000-0000-4000-8000-0000000012c1', '00000000-0000-4000-8000-0000000012b1',
        'U1', 'prover', 'SN-7', 1.0, jsonb_build_array(pg_temp.ld('check', 100, 100)))
  RETURNING customer_requested INTO cr;
  IF NOT cr THEN RAISE EXCEPTION 'A14b FAILED: customer_requested not generated true'; END IF;
  RAISE NOTICE 'PASS A14b: with both named it is accepted, and customer_requested is generated from test_kind';
END $$;

-- A15: a future test date is refused.
DO $$ BEGIN
  PERFORM pg_temp.rec('00000000-0000-4000-8000-0000000012e7', CURRENT_DATE + 1, jsonb_build_array(pg_temp.ld('check', 100, 100)));
  RAISE EXCEPTION 'A15 FAILED';
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'PASS A15: a test dated tomorrow is refused'; END $$;

-- ======================================================================= C
-- M-1: record out of date order and supersede, reading the pointer each time.
DO $$
DECLARE v uuid; m record; ooo boolean;
BEGIN
  v := pg_temp.rec('00000000-0000-4000-8000-0000000012e1', DATE '2026-05-10', jsonb_build_array(pg_temp.ld('check', 100, 100.5)));
  INSERT INTO bat12_ids VALUES ('m1_0510', v);
  SELECT last_test_date, last_test_result INTO m FROM public.meters WHERE id = '00000000-0000-4000-8000-0000000012e1';
  IF m.last_test_date <> DATE '2026-05-10' OR m.last_test_result <> 'passed' THEN
    RAISE EXCEPTION 'C1 FAILED: pointer %/%', m.last_test_date, m.last_test_result; END IF;
  RAISE NOTICE 'PASS C1: the first test sets the pointer (2026-05-10, passed)';

  v := pg_temp.rec('00000000-0000-4000-8000-0000000012e1', DATE '2026-01-10', jsonb_build_array(pg_temp.ld('check', 100, 104)));
  INSERT INTO bat12_ids VALUES ('m1_0110', v);
  SELECT last_test_date, last_test_result INTO m FROM public.meters WHERE id = '00000000-0000-4000-8000-0000000012e1';
  SELECT entered_out_of_order INTO ooo FROM public.meter_tests WHERE id = v;
  IF m.last_test_date <> DATE '2026-05-10' OR m.last_test_result <> 'passed' OR NOT ooo THEN
    RAISE EXCEPTION 'C2 FAILED: pointer %/%, out_of_order %', m.last_test_date, m.last_test_result, ooo; END IF;
  RAISE NOTICE 'PASS C2: a late entry dated earlier does not move the pointer back, and is flagged entered_out_of_order (D-5)';

  v := pg_temp.rec('00000000-0000-4000-8000-0000000012e1', DATE '2026-06-01', jsonb_build_array(pg_temp.ld('check', 100, 96)));
  INSERT INTO bat12_ids VALUES ('m1_0601', v);
  SELECT last_test_date, last_test_result INTO m FROM public.meters WHERE id = '00000000-0000-4000-8000-0000000012e1';
  IF m.last_test_date <> DATE '2026-06-01' OR m.last_test_result <> 'failed' THEN
    RAISE EXCEPTION 'C3 FAILED: pointer %/%', m.last_test_date, m.last_test_result; END IF;
  RAISE NOTICE 'PASS C3: a later test moves the pointer (2026-06-01, failed)';

  v := pg_temp.rec('00000000-0000-4000-8000-0000000012e1', DATE '2026-06-02', jsonb_build_array(pg_temp.ld('check', 100, 96)),
                   'periodic', (SELECT id FROM bat12_ids WHERE k = 'm1_0601'), 'test date keyed a day early');
  INSERT INTO bat12_ids VALUES ('m1_0602', v);
  SELECT last_test_date INTO m FROM public.meters WHERE id = '00000000-0000-4000-8000-0000000012e1';
  IF m.last_test_date <> DATE '2026-06-02' THEN RAISE EXCEPTION 'C4 FAILED: pointer %', m.last_test_date; END IF;
  RAISE NOTICE 'PASS C4: a superseding row moves the pointer to the corrected date';

  -- supersede the latest with a row dated EARLIER than 05-10: the pointer
  -- must fall back to 05-10 (latest non-superseded by date), not stay on the
  -- last inserted row.
  v := pg_temp.rec('00000000-0000-4000-8000-0000000012e1', DATE '2026-04-01', jsonb_build_array(pg_temp.ld('check', 100, 96)),
                   'periodic', (SELECT id FROM bat12_ids WHERE k = 'm1_0602'), 'it was the April test, re-keyed');
  SELECT last_test_date, last_test_result INTO m FROM public.meters WHERE id = '00000000-0000-4000-8000-0000000012e1';
  IF m.last_test_date <> DATE '2026-05-10' OR m.last_test_result <> 'passed' THEN
    RAISE EXCEPTION 'C5 FAILED: pointer %/%', m.last_test_date, m.last_test_result; END IF;
  RAISE NOTICE 'PASS C5: superseding the latest test with an earlier-dated row returns the pointer to 2026-05-10 — latest by test date, not last inserted';
END $$;
DO $$ BEGIN
  PERFORM pg_temp.rec('00000000-0000-4000-8000-0000000012e1', DATE '2026-06-03', jsonb_build_array(pg_temp.ld('check', 100, 96)),
                      'periodic', (SELECT id FROM bat12_ids WHERE k = 'm1_0601'), 'again');
  RAISE EXCEPTION 'C6 FAILED';
EXCEPTION WHEN unique_violation THEN RAISE NOTICE 'PASS C6: a row already superseded cannot be superseded again'; END $$;
DO $$ BEGIN
  PERFORM pg_temp.rec('00000000-0000-4000-8000-0000000012e7', DATE '2026-06-03', jsonb_build_array(pg_temp.ld('check', 100, 96)),
                      'periodic', (SELECT id FROM bat12_ids WHERE k = 'm1_0510'), 'wrong meter');
  RAISE EXCEPTION 'C6b FAILED';
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'PASS C6b: a test may not supersede another meter''s test'; END $$;
DO $$ BEGIN
  PERFORM pg_temp.rec('00000000-0000-4000-8000-0000000012e1', DATE '2026-06-03', jsonb_build_array(pg_temp.ld('check', 100, 96)),
                      'periodic', (SELECT id FROM bat12_ids WHERE k = 'm1_0510'), '  ');
  RAISE EXCEPTION 'C6c FAILED';
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'PASS C6c: a supersession needs a non-blank reason'; END $$;

-- C7 (§6.4): direct writes to the pointer are refused, as tally_app.
DO $$ BEGIN
  UPDATE public.meters SET last_test_date = DATE '2026-09-01' WHERE id = '00000000-0000-4000-8000-0000000012e1';
  RAISE EXCEPTION 'C7 FAILED';
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'PASS C7: a direct write to meters.last_test_date is refused'; END $$;
DO $$ BEGIN
  UPDATE public.meters SET last_test_result = 'passed' WHERE id = '00000000-0000-4000-8000-0000000012e3';
  RAISE EXCEPTION 'C7b FAILED';
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'PASS C7b: a direct write to meters.last_test_result is refused'; END $$;
DO $$ BEGIN
  UPDATE public.meters SET test_history_absence = 'attested_none' WHERE id = '00000000-0000-4000-8000-0000000012e6';
  RAISE EXCEPTION 'C7c FAILED';
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'PASS C7c: a direct write to meters.test_history_absence is refused'; END $$;
DO $$ BEGIN
  INSERT INTO public.meters (tenant_id, meter_number, location_id, service_type, last_test_date)
  VALUES ('00000000-0000-4000-8000-0000000012a1', 'M-NEW', '00000000-0000-4000-8000-0000000012d1', 'gas', DATE '2025-01-01');
  RAISE EXCEPTION 'C7d FAILED';
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'PASS C7d: a new meter cannot arrive carrying a last test date'; END $$;
DO $$
DECLARE n date;
BEGIN
  UPDATE public.meters SET next_test_due_date = DATE '2027-01-01', test_interval_months = 120
   WHERE id = '00000000-0000-4000-8000-0000000012e1' RETURNING next_test_due_date INTO n;
  IF n IS DISTINCT FROM DATE '2027-01-01' THEN RAISE EXCEPTION 'C8 FAILED'; END IF;
  RAISE NOTICE 'PASS C8: next_test_due_date and test_interval_months stay writable — scheduling, excluded by R-31';
END $$;

-- ======================================================================= D
DO $$ BEGIN
  PERFORM pg_temp.rec('00000000-0000-4000-8000-0000000012e2', DATE '2026-03-01', jsonb_build_array(pg_temp.ld('check', 100, 100)));
  RAISE EXCEPTION 'D1 FAILED';
EXCEPTION WHEN foreign_key_violation THEN RAISE NOTICE 'PASS D1: a test on another tenant''s meter is refused'; END $$;
DO $$ BEGIN
  PERFORM pg_temp.rec('00000000-0000-4000-8000-0000000012e2', DATE '2026-03-01', jsonb_build_array(pg_temp.ld('check', 100, 100)),
                      'periodic', NULL, NULL, '00000000-0000-4000-8000-0000000012a2');
  RAISE EXCEPTION 'D1b FAILED';
EXCEPTION WHEN foreign_key_violation OR insufficient_privilege THEN RAISE NOTICE 'PASS D1b: writing a test under another tenant''s id is refused'; END $$;
DO $$ BEGIN
  INSERT INTO public.meter_tests (tenant_id, meter_id, test_date, test_kind, record_basis, location_id, customer_id,
        performed_by_name, test_equipment, meter_serial_at_test, multiplier_at_test, load_results)
  VALUES ('00000000-0000-4000-8000-0000000012a1', '00000000-0000-4000-8000-0000000012e1', DATE '2026-03-02', 'customer_requested', 'recorded',
        '00000000-0000-4000-8000-0000000012d1', '00000000-0000-4000-8000-0000000012c2',
        'U1', 'prover', 'SN-1', 1.0, jsonb_build_array(pg_temp.ld('check', 100, 100)));
  RAISE EXCEPTION 'D2 FAILED';
EXCEPTION WHEN foreign_key_violation THEN RAISE NOTICE 'PASS D2: another tenant''s customer is refused (composite key)'; END $$;
DO $$ BEGIN
  INSERT INTO public.meter_tests (tenant_id, meter_id, test_date, test_kind, record_basis, performed_by_user_id,
        performed_by_name, test_equipment, meter_serial_at_test, multiplier_at_test, load_results)
  VALUES ('00000000-0000-4000-8000-0000000012a1', '00000000-0000-4000-8000-0000000012e1', DATE '2026-03-02', 'periodic', 'recorded',
        '00000000-0000-4000-8000-0000000012b2', 'U2', 'prover', 'SN-1', 1.0, jsonb_build_array(pg_temp.ld('check', 100, 100)));
  RAISE EXCEPTION 'D2b FAILED';
EXCEPTION WHEN foreign_key_violation THEN RAISE NOTICE 'PASS D2b: another tenant''s user as the tester is refused (users UNIQUE (id, tenant_id), D-6)'; END $$;
DO $$ BEGIN
  INSERT INTO public.meter_tests (tenant_id, meter_id, test_date, test_kind, record_basis, location_id,
        performed_by_name, test_equipment, meter_serial_at_test, multiplier_at_test, load_results)
  VALUES ('00000000-0000-4000-8000-0000000012a1', '00000000-0000-4000-8000-0000000012e1', DATE '2026-03-02', 'periodic', 'recorded',
        '00000000-0000-4000-8000-0000000012d2', 'U1', 'prover', 'SN-1', 1.0, jsonb_build_array(pg_temp.ld('check', 100, 100)));
  RAISE EXCEPTION 'D2c FAILED';
EXCEPTION WHEN check_violation OR foreign_key_violation THEN RAISE NOTICE 'PASS D2c: another tenant''s location is refused'; END $$;
DO $$ BEGIN
  INSERT INTO public.meter_tests (tenant_id, meter_id, test_date, test_kind, record_basis, location_id,
        performed_by_name, test_equipment, meter_serial_at_test, multiplier_at_test, load_results)
  VALUES ('00000000-0000-4000-8000-0000000012a1', '00000000-0000-4000-8000-0000000012e1', DATE '2026-03-02', 'periodic', 'recorded',
        '00000000-0000-4000-8000-0000000012d3', 'U1', 'prover', 'SN-1', 1.0, jsonb_build_array(pg_temp.ld('check', 100, 100)));
  RAISE EXCEPTION 'D3 FAILED';
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'PASS D3: a same-tenant location the meter was never deployed at is refused'; END $$;
DO $$ BEGIN
  INSERT INTO public.meter_tests (tenant_id, meter_id, test_date, test_kind, record_basis, service_order_id,
        performed_by_name, test_equipment, meter_serial_at_test, multiplier_at_test, load_results)
  VALUES ('00000000-0000-4000-8000-0000000012a1', '00000000-0000-4000-8000-0000000012e1', DATE '2026-03-02', 'periodic', 'recorded',
        '00000000-0000-4000-8000-0000000012f2', 'U1', 'prover', 'SN-1', 1.0, jsonb_build_array(pg_temp.ld('check', 100, 100)));
  RAISE EXCEPTION 'D4 FAILED';
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'PASS D4: a service order that is not a meter test (meter_install) is refused'; END $$;
DO $$ BEGIN
  INSERT INTO public.meter_tests (tenant_id, meter_id, test_date, test_kind, record_basis, service_order_id,
        performed_by_name, test_equipment, meter_serial_at_test, multiplier_at_test, load_results)
  VALUES ('00000000-0000-4000-8000-0000000012a1', '00000000-0000-4000-8000-0000000012e1', DATE '2026-03-02', 'periodic', 'recorded',
        '00000000-0000-4000-8000-0000000012f3', 'U1', 'prover', 'SN-1', 1.0, jsonb_build_array(pg_temp.ld('check', 100, 100)));
  RAISE EXCEPTION 'D4b FAILED';
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'PASS D4b: a meter-test order for a different meter is refused'; END $$;
DO $$ BEGIN
  INSERT INTO public.meter_tests (tenant_id, meter_id, test_date, test_kind, record_basis, service_order_id,
        performed_by_name, test_equipment, meter_serial_at_test, multiplier_at_test, load_results)
  VALUES ('00000000-0000-4000-8000-0000000012a1', '00000000-0000-4000-8000-0000000012e1', DATE '2026-03-02', 'periodic', 'recorded',
        '00000000-0000-4000-8000-0000000012f9', 'U1', 'prover', 'SN-1', 1.0, jsonb_build_array(pg_temp.ld('check', 100, 100)));
  RAISE EXCEPTION 'D4c FAILED';
EXCEPTION WHEN check_violation OR foreign_key_violation THEN RAISE NOTICE 'PASS D4c: another tenant''s service order is refused'; END $$;
DO $$
DECLARE v uuid;
BEGIN
  INSERT INTO public.meter_tests (tenant_id, meter_id, test_date, test_kind, record_basis, service_order_id,
        performed_by_name, test_equipment, meter_serial_at_test, multiplier_at_test, load_results)
  VALUES ('00000000-0000-4000-8000-0000000012a1', '00000000-0000-4000-8000-0000000012e1', DATE '2026-03-02', 'periodic', 'recorded',
        '00000000-0000-4000-8000-0000000012f1', 'U1', 'prover', 'SN-1', 1.0, jsonb_build_array(pg_temp.ld('check', 100, 100)))
  RETURNING id INTO v;
  RAISE NOTICE 'PASS D4d: the meter''s own meter-test order is accepted';
END $$;

-- D3b: a past deployment in another state cannot be named to choose the rule.
DO $$ BEGIN
  INSERT INTO public.meter_tests (tenant_id, meter_id, test_date, test_kind, record_basis, location_id,
        performed_by_name, test_equipment, meter_serial_at_test, multiplier_at_test, load_results)
  VALUES ('00000000-0000-4000-8000-0000000012a1', '00000000-0000-4000-8000-0000000012e1', DATE '2026-03-03', 'periodic', 'recorded',
        '00000000-0000-4000-8000-0000000012d5', 'U1', 'prover', 'SN-1', 1.0, jsonb_build_array(pg_temp.ld('check', 100, 100)));
  RAISE EXCEPTION 'D3b FAILED';
EXCEPTION WHEN check_violation THEN
  IF SQLERRM NOT LIKE '%different state%' THEN RAISE; END IF;
  RAISE NOTICE 'PASS D3b: a past deployment in another state is refused as the test''s location — the caller cannot choose which state''s threshold judges the test';
END $$;

-- ======================================================================= E
-- E1-E3 on T2 (not cut over), as T2's user.
SET LOCAL app.user_id = '00000000-0000-4000-8000-0000000012b2';
DO $$ BEGIN
  INSERT INTO public.meter_tests (tenant_id, meter_id, test_date, test_kind, record_basis)
  VALUES ('00000000-0000-4000-8000-0000000012a2', '00000000-0000-4000-8000-0000000012e2', DATE '2025-06-01', 'periodic', 'migrated_date_only');
  RAISE EXCEPTION 'E1 FAILED';
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'PASS E1: a migrated test for a tenant with no cutover_date is refused'; END $$;
UPDATE public.tenants SET cutover_date = DATE '2026-02-01' WHERE id = '00000000-0000-4000-8000-0000000012a2';
DO $$ BEGIN
  INSERT INTO public.meter_tests (tenant_id, meter_id, test_date, test_kind, record_basis)
  VALUES ('00000000-0000-4000-8000-0000000012a2', '00000000-0000-4000-8000-0000000012e2', DATE '2026-02-02', 'periodic', 'migrated_date_only');
  RAISE EXCEPTION 'E2 FAILED';
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'PASS E2: a migrated test dated after cutover is refused'; END $$;
DO $$
DECLARE m record;
BEGIN
  INSERT INTO public.meter_tests (tenant_id, meter_id, test_date, test_kind, record_basis, outcome)
  VALUES ('00000000-0000-4000-8000-0000000012a2', '00000000-0000-4000-8000-0000000012e2', DATE '2026-01-20', 'periodic', 'migrated_date_only', 'accurate');
  SELECT last_test_date, last_test_result INTO m FROM public.meters WHERE id = '00000000-0000-4000-8000-0000000012e2';
  IF m.last_test_date <> DATE '2026-01-20' OR m.last_test_result <> 'passed' THEN RAISE EXCEPTION 'E2b FAILED: %/%', m.last_test_date, m.last_test_result; END IF;
  RAISE NOTICE 'PASS E2b: a migrated date-only test on the cutover side is accepted with the result the utility''s records show, and sets the pointer';
END $$;
DO $$ BEGIN
  UPDATE public.tenants SET cutover_date = DATE '2026-01-19' WHERE id = '00000000-0000-4000-8000-0000000012a2';
  RAISE EXCEPTION 'E3 FAILED';
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'PASS E3: cutover cannot move before a migrated test already loaded'; END $$;
DO $$ BEGIN
  UPDATE public.tenants SET cutover_date = NULL WHERE id = '00000000-0000-4000-8000-0000000012a2';
  RAISE EXCEPTION 'E3b FAILED';
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'PASS E3b: cutover cannot be cleared once migrated history exists'; END $$;
DO $$
DECLARE c date;
BEGIN
  UPDATE public.tenants SET cutover_date = DATE '2026-03-01' WHERE id = '00000000-0000-4000-8000-0000000012a2' RETURNING cutover_date INTO c;
  UPDATE public.tenants SET cutover_date = DATE '2026-01-20' WHERE id = '00000000-0000-4000-8000-0000000012a2' RETURNING cutover_date INTO c;
  IF c <> DATE '2026-01-20' THEN RAISE EXCEPTION 'E3c FAILED'; END IF;
  RAISE NOTICE 'PASS E3c: cutover may slip later, and back down to exactly the latest migrated date';
END $$;
DO $$ BEGIN
  INSERT INTO public.meter_tests (tenant_id, meter_id, test_date, test_kind, record_basis, load_results)
  VALUES ('00000000-0000-4000-8000-0000000012a2', '00000000-0000-4000-8000-0000000012e2', DATE '2026-01-05', 'periodic', 'migrated_date_only',
          jsonb_build_array(pg_temp.ld('check', 100, 110)));
  RAISE EXCEPTION 'E4 FAILED';
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'PASS E4: a date-only row carrying readings is refused — readings make it a full record'; END $$;
DO $$ BEGIN
  INSERT INTO public.meter_tests (tenant_id, meter_id, test_date, test_kind, record_basis,
        performed_by_name, test_equipment, meter_serial_at_test, multiplier_at_test, load_results)
  VALUES ('00000000-0000-4000-8000-0000000012a2', '00000000-0000-4000-8000-0000000012e2', DATE '2003-05-01', 'periodic', 'migrated_full',
          'Old Tester', 'prover', 'SN-2', 1.0, jsonb_build_array(pg_temp.ld('check', 100, 101)));
  RAISE EXCEPTION 'E5 FAILED';
EXCEPTION WHEN no_data_found THEN RAISE NOTICE 'PASS E5: a migrated_full test before the seeded threshold''s effective date refuses (R6) — it may load as date-only'; END $$;
SET LOCAL app.user_id = '00000000-0000-4000-8000-0000000012b1';

-- ======================================================================= F
-- M-3 history (T1, cutover 2026-01-15, so the gate runs to 2026-07-15):
--   2025-10-01 migrated_date_only, no result
--   2026-03-01 recorded, inconclusive (no valid measurement)
--   2026-05-01 recorded, fast — the discovering test
-- M-7, a sibling at the same premise, was tested 2026-02-01…14 in group A.
INSERT INTO public.meter_tests (tenant_id, meter_id, test_date, test_kind, record_basis)
VALUES ('00000000-0000-4000-8000-0000000012a1', '00000000-0000-4000-8000-0000000012e3', DATE '2025-10-01', 'periodic', 'migrated_date_only');
INSERT INTO public.meter_tests (tenant_id, meter_id, test_date, test_kind, record_basis,
      performed_by_name, test_equipment, meter_serial_at_test, multiplier_at_test, inconclusive_reason)
VALUES ('00000000-0000-4000-8000-0000000012a1', '00000000-0000-4000-8000-0000000012e3', DATE '2026-03-01', 'complaint', 'recorded',
      'A. Tester', 'prover', 'SN-3', 1.0, 'meter iced; no stable reading');
INSERT INTO public.meter_tests (tenant_id, meter_id, test_date, test_kind, record_basis, location_id, customer_id,
      performed_by_name, test_equipment, meter_serial_at_test, multiplier_at_test, load_results)
VALUES ('00000000-0000-4000-8000-0000000012a1', '00000000-0000-4000-8000-0000000012e3', DATE '2026-05-01', 'customer_requested', 'recorded',
      '00000000-0000-4000-8000-0000000012d3', '00000000-0000-4000-8000-0000000012c1',
      'A. Tester', 'prover', 'SN-3', 1.0, jsonb_build_array(pg_temp.ld('check', 100, 106)));

DO $$
DECLARE g record;
BEGIN
  SELECT * INTO g FROM public.meter_governing_test('00000000-0000-4000-8000-0000000012e3', DATE '2026-05-01');
  IF g.test_date <> DATE '2026-03-01' OR g.outcome <> 'inconclusive' OR g.weak_provenance OR g.supervisor_gate OR g.absence IS NOT NULL THEN
    RAISE EXCEPTION 'F1 FAILED: % % weak=% gate=% absence=%', g.test_date, g.outcome, g.weak_provenance, g.supervisor_gate, g.absence; END IF;
  RAISE NOTICE 'PASS F1: anchored on the 05-01 discovery, the governing test is 03-01 — strictly before, and RETURNED although inconclusive (R-34: whatever its outcome); the sibling meter''s February tests are ignored (same meter only)';

  SELECT * INTO g FROM public.meter_governing_test('00000000-0000-4000-8000-0000000012e3', DATE '2026-05-02');
  IF g.test_date <> DATE '2026-05-01' OR NOT g.prior_test_failed THEN
    RAISE EXCEPTION 'F2 FAILED: % failed=%', g.test_date, g.prior_test_failed; END IF;
  RAISE NOTICE 'PASS F2: a day later the fast 05-01 test governs, flagged prior_test_failed for the operator (R-34) — not skipped';

  SELECT * INTO g FROM public.meter_governing_test('00000000-0000-4000-8000-0000000012e3', DATE '2026-03-01');
  IF g.test_date <> DATE '2025-10-01' OR g.record_basis <> 'migrated_date_only' OR NOT g.weak_provenance OR NOT g.supervisor_gate THEN
    RAISE EXCEPTION 'F3 FAILED: % % weak=% gate=%', g.test_date, g.record_basis, g.weak_provenance, g.supervisor_gate; END IF;
  RAISE NOTICE 'PASS F3: a date-only migrated test anchors the window (R-36), marked weak, and gated inside cutover + 6 months';

  SELECT * INTO g FROM public.meter_governing_test('00000000-0000-4000-8000-0000000012e3', DATE '2025-10-01');
  IF g.meter_test_id IS NOT NULL OR g.absence <> 'undeclared' OR NOT g.supervisor_gate THEN
    RAISE EXCEPTION 'F4 FAILED: % absence=% gate=%', g.meter_test_id, g.absence, g.supervisor_gate; END IF;
  RAISE NOTICE 'PASS F4: anchored ON the earliest test, nothing qualifies — no test returned, absence undeclared, gated';
END $$;

-- F5: the gate lapses at cutover + 6 months (2026-07-15), both sides.
INSERT INTO public.meter_tests (tenant_id, meter_id, test_date, test_kind, record_basis)
VALUES ('00000000-0000-4000-8000-0000000012a1', '00000000-0000-4000-8000-0000000012e5', DATE '2025-12-01', 'periodic', 'migrated_date_only');
DO $$
DECLARE g record;
BEGIN
  SELECT * INTO g FROM public.meter_governing_test('00000000-0000-4000-8000-0000000012e5', DATE '2026-07-14');
  IF NOT g.supervisor_gate THEN RAISE EXCEPTION 'F5 FAILED: 07-14 not gated'; END IF;
  SELECT * INTO g FROM public.meter_governing_test('00000000-0000-4000-8000-0000000012e5', DATE '2026-07-15');
  IF g.supervisor_gate OR NOT g.weak_provenance THEN RAISE EXCEPTION 'F5 FAILED: 07-15 gate=% weak=%', g.supervisor_gate, g.weak_provenance; END IF;
  RAISE NOTICE 'PASS F5: the R-36 gate applies on 2026-07-14 and has lapsed on 2026-07-15 (cutover 01-15 + 6 months) — still marked weak';
END $$;

-- F6: no history, and scheduling columns that WOULD produce a date if read.
-- install_date 2025-11-01; next_test_due_date − test_interval_months = 2025-12-01.
RESET ROLE;
UPDATE public.meters SET install_date = DATE '2025-11-01', test_interval_months = 12, next_test_due_date = DATE '2026-12-01'
 WHERE id = '00000000-0000-4000-8000-0000000012e6';
SET ROLE tally_app;
DO $$
DECLARE g record;
BEGIN
  SELECT * INTO g FROM public.meter_governing_test('00000000-0000-4000-8000-0000000012e6', DATE '2026-06-01');
  IF g.meter_test_id IS NOT NULL OR g.test_date IS NOT NULL OR g.absence <> 'undeclared' THEN
    RAISE EXCEPTION 'F6 FAILED: % % %', g.meter_test_id, g.test_date, g.absence; END IF;
  RAISE NOTICE 'PASS F6: a meter with install_date and a test schedule but no history gets NO test date — none derived from install_date or next_due − interval (R-31, R-35 ref. 3)';
END $$;

-- F7: the absence declarations, append-only, and the pointer following them.
INSERT INTO public.meter_test_absence_declarations (tenant_id, meter_id, absence, basis_note)
VALUES ('00000000-0000-4000-8000-0000000012a1', '00000000-0000-4000-8000-0000000012e6', 'unknown', 'legacy CIS export has no test fields');
INSERT INTO public.meter_test_absence_declarations (tenant_id, meter_id, absence, basis_note)
VALUES ('00000000-0000-4000-8000-0000000012a1', '00000000-0000-4000-8000-0000000012e6', 'attested_none', 'utility GM letter 2026-01-10: never tested since install');
DO $$
DECLARE g record; n int; p text;
BEGIN
  SELECT * INTO g FROM public.meter_governing_test('00000000-0000-4000-8000-0000000012e6', DATE '2026-06-01');
  SELECT count(*) INTO n FROM public.meter_test_absence_declarations WHERE meter_id = '00000000-0000-4000-8000-0000000012e6';
  SELECT test_history_absence INTO p FROM public.meters WHERE id = '00000000-0000-4000-8000-0000000012e6';
  IF g.absence <> 'attested_none' OR NOT g.supervisor_gate OR n <> 2 OR p <> 'attested_none' THEN
    RAISE EXCEPTION 'F7 FAILED: absence % gate % rows % pointer %', g.absence, g.supervisor_gate, n, p; END IF;
  RAISE NOTICE 'PASS F7: unknown → attested_none leaves both declarations (R-35 ref. 4), the pointer follows the latest, and the gate still applies';
END $$;
DO $$ BEGIN
  INSERT INTO public.meter_test_absence_declarations (tenant_id, meter_id, absence, basis_note)
  VALUES ('00000000-0000-4000-8000-0000000012a1', '00000000-0000-4000-8000-0000000012e2', 'unknown', 'x');
  RAISE EXCEPTION 'F7b FAILED';
EXCEPTION WHEN foreign_key_violation THEN RAISE NOTICE 'PASS F7b: an absence declaration on another tenant''s meter is refused'; END $$;

-- F8: supersession — on M-1 the 06-01 and 06-02 rows are superseded, so an
-- anchor of 06-15 governs from 05-10.
DO $$
DECLARE g record;
BEGIN
  SELECT * INTO g FROM public.meter_governing_test('00000000-0000-4000-8000-0000000012e1', DATE '2026-06-15');
  IF g.test_date <> DATE '2026-05-10' THEN RAISE EXCEPTION 'F8 FAILED: %', g.test_date; END IF;
  RAISE NOTICE 'PASS F8: superseded rows are excluded — the governing test for 06-15 is 05-10, not the superseded 06-01 / 06-02';
END $$;

-- F9: required coordinates, and an invisible meter.
DO $$ BEGIN
  PERFORM public.meter_governing_test('00000000-0000-4000-8000-0000000012e3', NULL);
  RAISE EXCEPTION 'F9 FAILED';
EXCEPTION WHEN null_value_not_allowed THEN RAISE NOTICE 'PASS F9: a NULL anchor raises — there is no default anchor'; END $$;
DO $$ BEGIN
  PERFORM public.meter_governing_test('00000000-0000-4000-8000-0000000012e2', DATE '2026-06-01');
  RAISE EXCEPTION 'F9b FAILED';
EXCEPTION WHEN no_data_found THEN RAISE NOTICE 'PASS F9b: another tenant''s meter raises rather than reporting "no history"'; END $$;

-- ======================================================================= G
DO $$
DECLARE r record; n int;
BEGIN
  SELECT count(*) INTO n FROM public.meter_test_history_gaps WHERE tenant_id <> '00000000-0000-4000-8000-0000000012a1';
  IF n <> 0 THEN RAISE EXCEPTION 'G1 FAILED: % other-tenant rows visible', n; END IF;
  SELECT * INTO r FROM public.meter_test_history_gaps WHERE meter_id = '00000000-0000-4000-8000-0000000012e6';
  IF r.absence <> 'attested_none' OR r.absence_basis_note NOT LIKE 'utility GM letter%' THEN RAISE EXCEPTION 'G1 FAILED: %', r; END IF;
  IF EXISTS (SELECT 1 FROM public.meter_test_history_gaps WHERE meter_id = '00000000-0000-4000-8000-0000000012e3') THEN
    RAISE EXCEPTION 'G1 FAILED: M-3 has history but is listed'; END IF;
  SELECT count(*) INTO n FROM public.meter_test_history_gaps WHERE meter_id = '00000000-0000-4000-8000-0000000012e4' AND absence = 'undeclared';
  IF n <> 1 THEN RAISE EXCEPTION 'G1 FAILED: M-4 undeclared gap missing'; END IF;
  RAISE NOTICE 'PASS G1: the gap report lists this tenant''s meters with no history (M-6 attested_none with its basis, M-4 undeclared), omits tested meters and other tenants';
END $$;
DO $$ BEGIN
  UPDATE public.meter_test_history_gaps SET meter_number = 'X' WHERE meter_id = '00000000-0000-4000-8000-0000000012e6';
  RAISE EXCEPTION 'G2 FAILED';
EXCEPTION WHEN insufficient_privilege THEN RAISE NOTICE 'PASS G2: the gap report is read-only for tally_app'; END $$;

-- ======================================================================= B
-- As tally_app: the grants refuse. Including an UPDATE to a column's own value.
DO $$ BEGIN
  UPDATE public.meter_tests SET notes = notes WHERE meter_id = '00000000-0000-4000-8000-0000000012e1';
  RAISE EXCEPTION 'B1 FAILED';
EXCEPTION WHEN insufficient_privilege THEN RAISE NOTICE 'PASS B1: tally_app cannot UPDATE meter_tests, not even a column to its own value'; END $$;
DO $$ BEGIN
  DELETE FROM public.meter_tests WHERE meter_id = '00000000-0000-4000-8000-0000000012e1';
  RAISE EXCEPTION 'B2 FAILED';
EXCEPTION WHEN insufficient_privilege THEN RAISE NOTICE 'PASS B2: tally_app cannot DELETE meter_tests'; END $$;
DO $$ BEGIN
  UPDATE public.meter_test_load_results SET meter_volume = meter_volume;
  RAISE EXCEPTION 'B3 FAILED';
EXCEPTION WHEN insufficient_privilege THEN RAISE NOTICE 'PASS B3: tally_app cannot UPDATE load rows'; END $$;
DO $$ BEGIN
  INSERT INTO public.meter_test_load_results (tenant_id, meter_test_id, load_point, standard_volume, meter_volume)
  VALUES ('00000000-0000-4000-8000-0000000012a1', (SELECT id FROM bat12_ids WHERE k = 'm1_0510'), 'late', 100, 150);
  RAISE EXCEPTION 'B4 FAILED';
EXCEPTION WHEN restrict_violation THEN RAISE NOTICE 'PASS B4: a load row added to a recorded test is refused (it would turn a passed test into a failed one)'; END $$;
DO $$ BEGIN
  UPDATE public.meter_test_absence_declarations SET absence = absence;
  RAISE EXCEPTION 'B5 FAILED';
EXCEPTION WHEN insufficient_privilege THEN RAISE NOTICE 'PASS B5: tally_app cannot UPDATE absence declarations'; END $$;

-- As the owner: the triggers refuse where the grants do not reach.
RESET ROLE;
DO $$ BEGIN
  UPDATE public.meter_tests SET notes = notes WHERE meter_id = '00000000-0000-4000-8000-0000000012e1';
  RAISE EXCEPTION 'B6 FAILED';
EXCEPTION WHEN restrict_violation THEN RAISE NOTICE 'PASS B6: even the owner cannot UPDATE a recorded test (trigger, ENABLE ALWAYS)'; END $$;
DO $$ BEGIN
  DELETE FROM public.meter_test_load_results;
  RAISE EXCEPTION 'B7 FAILED';
EXCEPTION WHEN restrict_violation THEN RAISE NOTICE 'PASS B7: even the owner cannot DELETE load rows'; END $$;
DO $$ BEGIN
  INSERT INTO public.meter_test_load_results (tenant_id, meter_test_id, load_point, standard_volume, meter_volume)
  VALUES ('00000000-0000-4000-8000-0000000012a1', (SELECT id FROM bat12_ids WHERE k = 'm1_0510'), 'late', 100, 150);
  RAISE EXCEPTION 'B8 FAILED';
EXCEPTION WHEN restrict_violation THEN RAISE NOTICE 'PASS B8: even the owner cannot add a load row to a recorded test'; END $$;
DO $$ BEGIN
  TRUNCATE public.meter_test_absence_declarations;
  RAISE EXCEPTION 'B9 FAILED';
EXCEPTION WHEN restrict_violation THEN RAISE NOTICE 'PASS B9: TRUNCATE is refused'; END $$;
DO $$ BEGIN
  UPDATE public.meters SET last_test_date = DATE '2026-09-01' WHERE id = '00000000-0000-4000-8000-0000000012e1';
  RAISE EXCEPTION 'B10 FAILED';
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'PASS B10: even the owner cannot write the pointer directly'; END $$;

-- ======================================================================= H
SET ROLE tally_app;
DO $$ BEGIN
  INSERT INTO public.meter_accuracy_thresholds (state_code, service_type, threshold_pct, effective_from, source_note)
  VALUES ('OK', 'gas', 9.0, DATE '2026-01-01', 'mine');
  RAISE EXCEPTION 'H1 FAILED';
EXCEPTION WHEN insufficient_privilege THEN RAISE NOTICE 'PASS H1: tally_app cannot add a threshold'; END $$;
DO $$ BEGIN
  UPDATE public.meter_accuracy_thresholds SET threshold_pct = 9.0;
  RAISE EXCEPTION 'H1b FAILED';
EXCEPTION WHEN insufficient_privilege THEN RAISE NOTICE 'PASS H1b: tally_app cannot widen the threshold'; END $$;
RESET ROLE;
DO $$ BEGIN
  INSERT INTO public.meter_accuracy_thresholds (state_code, service_type, threshold_pct, effective_from, source_note)
  VALUES ('TX', 'gas', 3.0, DATE '2020-01-01', 'overlapping row');
  RAISE EXCEPTION 'H2 FAILED';
EXCEPTION WHEN exclusion_violation THEN RAISE NOTICE 'PASS H2: two TX gas thresholds cannot overlap in time'; END $$;

-- ======================================================================= J
-- The assertion must RAISE on planted drift, not merely pass.
SAVEPOINT j;
DO $$ BEGIN
  PERFORM public.assert_tenant_isolation_invariants();
  RAISE NOTICE 'PASS J0: the assertion passes on the patched build';
END $$;
ALTER TABLE public.meter_tests NO FORCE ROW LEVEL SECURITY;
DO $$ BEGIN
  PERFORM public.assert_tenant_isolation_invariants();
  RAISE EXCEPTION 'J1 FAILED: unforced RLS on meter_tests passed';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM LIKE 'J1 FAILED%' THEN RAISE; END IF;
  RAISE NOTICE 'PASS J1: meter_tests without FORCE RLS makes the assertion raise (%)', left(SQLERRM, 60);
END $$;
ROLLBACK TO SAVEPOINT j;
CREATE POLICY bat12_leak ON public.meter_test_load_results USING (true);
DO $$ BEGIN
  PERFORM public.assert_tenant_isolation_invariants();
  RAISE EXCEPTION 'J2 FAILED: a permissive policy on load rows passed';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM LIKE 'J2 FAILED%' THEN RAISE; END IF;
  RAISE NOTICE 'PASS J2: a second permissive policy on meter_test_load_results makes the assertion raise (%)', left(SQLERRM, 60);
END $$;
ROLLBACK TO SAVEPOINT j;
ALTER VIEW public.meter_test_history_gaps SET (security_invoker = false);
DO $$ BEGIN
  PERFORM public.assert_tenant_isolation_invariants();
  RAISE EXCEPTION 'J3 FAILED: an owner-rights gap view passed';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM LIKE 'J3 FAILED%' THEN RAISE; END IF;
  RAISE NOTICE 'PASS J3: the gap view without security_invoker makes the assertion raise (%)', left(SQLERRM, 60);
END $$;
ROLLBACK TO SAVEPOINT j;
ALTER TABLE public.meter_test_absence_declarations DISABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  PERFORM public.assert_tenant_isolation_invariants();
  RAISE EXCEPTION 'J4 FAILED: RLS disabled on absence declarations passed';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM LIKE 'J4 FAILED%' THEN RAISE; END IF;
  RAISE NOTICE 'PASS J4: absence declarations without RLS make the assertion raise (%)', left(SQLERRM, 60);
END $$;
ROLLBACK TO SAVEPOINT j;

-- I: the composite keys this patch added exist.
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'users_id_tenant_id_key')
     OR NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'service_locations_id_tenant_id_key') THEN
    RAISE EXCEPTION 'I1 FAILED'; END IF;
  RAISE NOTICE 'PASS I1: users and service_locations carry UNIQUE (id, tenant_id)';
END $$;

ROLLBACK;
