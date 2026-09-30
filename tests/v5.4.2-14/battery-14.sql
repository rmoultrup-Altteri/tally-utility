-- ============================================================================
-- BATTERY v5.4.2-14 — meter_governing_test() without R-36's gate (2026-09-30)
-- Run: psql -U tally -d <db-with-patch> -v ON_ERROR_STOP=1 -f battery-14.sql
-- One transaction, rolled back. What -12's function still answers is
-- battery-12's (group F, restated for -14); this battery pins what -14
-- changed: the gate is gone from the result, the body holds no law, the
-- grants are exact, and the catalog no longer says the database gates.
-- ============================================================================
BEGIN;

DO $$ DECLARE r text; BEGIN
  SELECT pg_get_function_result('public.meter_governing_test(uuid, date)'::regprocedure) INTO r;
  IF r IS DISTINCT FROM 'TABLE(meter_test_id uuid, test_date date, test_kind text, outcome text, record_basis text, entered_out_of_order boolean, prior_test_failed boolean, absence text, weak_provenance boolean)' THEN
    RAISE EXCEPTION 'FAIL A1: meter_governing_test returns %', r;
  END IF;
  RAISE NOTICE 'PASS A1: meter_governing_test returns the governing test and its facts, and no supervisor_gate';
END $$;

DO $$ DECLARE src text; BEGIN
  SELECT prosrc INTO src FROM pg_proc WHERE oid = 'public.meter_governing_test(uuid, date)'::regprocedure;
  IF src ~* 'month|interval|cutover' THEN
    RAISE EXCEPTION 'FAIL A2: the body still reads a month count, an interval or the cutover';
  END IF;
  RAISE NOTICE 'PASS A2: the body holds no month count and does not read the cutover — it computes no law';
END $$;

DO $$ BEGIN
  IF NOT has_function_privilege('tally_app', 'public.meter_governing_test(uuid, date)', 'EXECUTE') THEN
    RAISE EXCEPTION 'FAIL A3: tally_app cannot execute meter_governing_test';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_proc p, aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
              WHERE p.oid = 'public.meter_governing_test(uuid, date)'::regprocedure
                AND a.grantee = 0 AND a.privilege_type = 'EXECUTE') THEN
    RAISE EXCEPTION 'FAIL A3: PUBLIC can execute meter_governing_test';
  END IF;
  RAISE NOTICE 'PASS A3: EXECUTE for tally_app, not for PUBLIC — the grants re-issued exactly';
END $$;

-- A4: the function still answers as tally_app (fixture as owner).
INSERT INTO public.tenants (id, name, slug, cutover_date) VALUES
  ('00000000-0000-4000-8000-0000000014a1', 'T1 Gasco', 'bat14-t1', DATE '2026-01-15');
INSERT INTO public.users (id, tenant_id, display_name, email, role) VALUES
  ('00000000-0000-4000-8000-0000000014b1', '00000000-0000-4000-8000-0000000014a1', 'U1', 'u1@bat14.test', 'operator');
INSERT INTO public.customers (id, tenant_id, customer_number) VALUES
  ('00000000-0000-4000-8000-0000000014c1', '00000000-0000-4000-8000-0000000014a1', 'BAT14-C1');
INSERT INTO public.service_locations (id, tenant_id, customer_id, location_number, address_line1, city, state, zip) VALUES
  ('00000000-0000-4000-8000-0000000014d1', '00000000-0000-4000-8000-0000000014a1', '00000000-0000-4000-8000-0000000014c1', 'L1', '1 Main', 'Austin', 'TX', '78701');
INSERT INTO public.meters (id, tenant_id, meter_number, location_id, service_type) VALUES
  ('00000000-0000-4000-8000-0000000014e1', '00000000-0000-4000-8000-0000000014a1', 'M-1', '00000000-0000-4000-8000-0000000014d1', 'gas');
INSERT INTO public.meter_tests (tenant_id, meter_id, test_date, test_kind, record_basis) VALUES
  ('00000000-0000-4000-8000-0000000014a1', '00000000-0000-4000-8000-0000000014e1', DATE '2025-12-01', 'periodic', 'migrated_date_only');
SET LOCAL app.user_id = '00000000-0000-4000-8000-0000000014b1';
SET ROLE tally_app;
DO $$ DECLARE g record; BEGIN
  SELECT * INTO g FROM public.meter_governing_test('00000000-0000-4000-8000-0000000014e1', DATE '2026-03-01');
  IF g.test_date IS DISTINCT FROM DATE '2025-12-01' OR g.record_basis <> 'migrated_date_only' OR NOT g.weak_provenance THEN
    RAISE EXCEPTION 'FAIL A4: % % weak=%', g.test_date, g.record_basis, g.weak_provenance;
  END IF;
  SELECT * INTO g FROM public.meter_governing_test('00000000-0000-4000-8000-0000000014e1', DATE '2025-12-01');
  IF g.meter_test_id IS NOT NULL OR g.absence <> 'undeclared' OR NOT g.weak_provenance THEN
    RAISE EXCEPTION 'FAIL A4: no-test anchor read % % %', g.meter_test_id, g.absence, g.weak_provenance;
  END IF;
  RAISE NOTICE 'PASS A4: as tally_app it still returns the governing date-only test marked weak, and no test with the absence where none precedes';
END $$;
RESET ROLE;

DO $$ BEGIN
  IF obj_description('public.meter_governing_test(uuid, date)'::regprocedure, 'pg_proc') ~* 'supervisor_gate|anchor − 6 months'
     OR col_description('public.tenants'::regclass, (SELECT attnum FROM pg_attribute WHERE attrelid = 'public.tenants'::regclass AND attname = 'cutover_date')) ~* 'runs for six months|the gate applies'
     OR col_description('public.meter_tests'::regclass, (SELECT attnum FROM pg_attribute WHERE attrelid = 'public.meter_tests'::regclass AND attname = 'record_basis')) ~* 'gate meter_governing_test\(\) computes'
     OR obj_description('public.meter_test_absence_declarations'::regclass, 'pg_class') ~* 'six-month cap' THEN
    RAISE EXCEPTION 'FAIL A5: a comment still says the database computes the gate';
  END IF;
  RAISE NOTICE 'PASS A5: the catalog no longer says the database computes R-36''s gate; it names the core';
END $$;

DO $$ BEGIN
  PERFORM public.assert_tenant_isolation_invariants();
  RAISE NOTICE 'PASS A6: the AC-32 tenant-isolation assertion holds';
END $$;

ROLLBACK;
