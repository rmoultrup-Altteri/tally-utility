-- ============================================================================
-- PRE-PATCH PROBE v5.4.2-11 (round 2) — the same fixtures as battery-11.sql,
-- every discriminating check in its own SAVEPOINT so one failure does not
-- abort the rest. Run against a build WITHOUT the patch: each line printed as
-- "PRE-PATCH HOLE" is a hole only this patch closes. Run it again against the
-- patched build and every line must read "as expected".
-- Run: psql -U tally -d <db> -f probe-pre-11.sql
-- ============================================================================
BEGIN;
SET CONSTRAINTS ALL IMMEDIATE;

-- ---------------------------------------------------------------- fixtures
INSERT INTO public.tenants (id, name, slug) VALUES
  ('00000000-0000-4000-8000-0000000011a1', 'T1 Gasco', 'bat11-t1'),
  ('00000000-0000-4000-8000-0000000011a2', 'T2 Gasco', 'bat11-t2');
INSERT INTO public.users (id, tenant_id, display_name, email, role) VALUES
  ('00000000-0000-4000-8000-0000000011b1', '00000000-0000-4000-8000-0000000011a1', 'U1', 'u1@bat11.test', 'operator'),
  ('00000000-0000-4000-8000-0000000011b2', '00000000-0000-4000-8000-0000000011a2', 'U2', 'u2@bat11.test', 'operator'),
  ('00000000-0000-4000-8000-0000000011b9', '00000000-0000-4000-8000-0000000011a1', 'Platform', 'pa@bat11.test', 'platform_admin');
INSERT INTO public.customers (id, tenant_id, customer_number) VALUES
  ('00000000-0000-4000-8000-0000000011c1', '00000000-0000-4000-8000-0000000011a1', 'BAT11-C1'),
  ('00000000-0000-4000-8000-0000000011c2', '00000000-0000-4000-8000-0000000011a2', 'BAT11-C2');
INSERT INTO public.service_locations (id, tenant_id, customer_id, location_number, address_line1, city, state, zip) VALUES
  ('00000000-0000-4000-8000-0000000011d1', '00000000-0000-4000-8000-0000000011a1', '00000000-0000-4000-8000-0000000011c1', 'LOC-1', '1 Main', 'Austin', 'TX', '78701'),
  ('00000000-0000-4000-8000-0000000011d2', '00000000-0000-4000-8000-0000000011a2', '00000000-0000-4000-8000-0000000011c2', 'LOC-2', '2 Main', 'Austin', 'TX', '78702');
INSERT INTO public.meters (id, tenant_id, meter_number, location_id, service_type) VALUES
  ('00000000-0000-4000-8000-0000000011e1', '00000000-0000-4000-8000-0000000011a1', 'M-1', '00000000-0000-4000-8000-0000000011d1', 'gas'),
  ('00000000-0000-4000-8000-0000000011e2', '00000000-0000-4000-8000-0000000011a2', 'M-2', '00000000-0000-4000-8000-0000000011d2', 'gas');
INSERT INTO public.billing_runs (id, tenant_id, run_number, billing_period, period_start, period_end, run_type, status, started_at) VALUES
  ('00000000-0000-4000-8000-0000000011f1', '00000000-0000-4000-8000-0000000011a1', 'RUN-T1', '2026-03', '2026-03-01', '2026-03-31', 'regular', 'in_progress', now()),
  ('00000000-0000-4000-8000-0000000011f2', '00000000-0000-4000-8000-0000000011a2', 'RUN-T2', '2026-03', '2026-03-01', '2026-03-31', 'regular', 'in_progress', now());

-- helper: a minimal v1 snapshot for an invoice (p_ prefix — the shadowing lesson)
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

CREATE FUNCTION pg_temp.inv(p_id uuid, p_num text, p_tenant uuid, p_run uuid, p_cust uuid, p_loc uuid,
                            p_type text, p_replaces uuid, p_ps date, p_pe date) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO public.invoices (id, tenant_id, invoice_number, billing_run_id, customer_id, location_id, invoice_type,
                               replaces_invoice_id, invoice_date, billing_period, period_start, period_end, due_date)
  VALUES (p_id, p_tenant, p_num, p_run, p_cust, p_loc, p_type, p_replaces, p_pe + 1, to_char(p_pe, 'YYYY-MM'), p_ps, p_pe, p_pe + 21);
  INSERT INTO public.invoice_line_items (tenant_id, invoice_id, service_type, charge_type, description, amount)
  VALUES (p_tenant, p_id, 'gas', 'base_charge', 'Customer charge', 12.50);
END $$;

GRANT EXECUTE ON FUNCTION pg_temp.inv(uuid, text, uuid, uuid, uuid, uuid, text, uuid, date, date) TO tally_app;

-- NOTE: these explicit grants are REQUIRED since v5.4.2-11 section 5b revoked
-- PUBLIC's default EXECUTE on new functions — a pg_temp helper is a new
-- function like any other. A battery written before this patch got them free.

-- One issued-then-voided bill per tenant, each carrying a parked adhoc charge
-- and a released read — the two rows the leaking views expose.
SELECT pg_temp.inv('00000000-0000-4000-8000-000000001101', 'T1-INV-1', '00000000-0000-4000-8000-0000000011a1',
                   '00000000-0000-4000-8000-0000000011f1', '00000000-0000-4000-8000-0000000011c1',
                   '00000000-0000-4000-8000-0000000011d1', 'regular', NULL, '2026-03-01', '2026-03-31');
SELECT pg_temp.inv('00000000-0000-4000-8000-000000001102', 'T2-INV-1', '00000000-0000-4000-8000-0000000011a2',
                   '00000000-0000-4000-8000-0000000011f2', '00000000-0000-4000-8000-0000000011c2',
                   '00000000-0000-4000-8000-0000000011d2', 'regular', NULL, '2026-03-01', '2026-03-31');
SELECT pg_temp.snap('00000000-0000-4000-8000-000000001101', '2026-03-31', now());
SELECT pg_temp.snap('00000000-0000-4000-8000-000000001102', '2026-03-31', now());

-- adhoc charges, billed onto those invoices
INSERT INTO public.adhoc_charges (id, tenant_id, charge_number, customer_id, charge_type, description, amount,
                                  regulatory_class, status, billed_on_invoice_id, billed_at) VALUES
  ('00000000-0000-4000-8000-000000001201', '00000000-0000-4000-8000-0000000011a1', 'T1-AC-1', '00000000-0000-4000-8000-0000000011c1',
   'reconnection_fee', 'T1 SECRET reconnect fee', 45.00, 'unregulated', 'billed', '00000000-0000-4000-8000-000000001101', now()),
  ('00000000-0000-4000-8000-000000001202', '00000000-0000-4000-8000-0000000011a2', 'T2-AC-1', '00000000-0000-4000-8000-0000000011c2',
   'reconnection_fee', 'T2 SECRET reconnect fee', 55.00, 'unregulated', 'billed', '00000000-0000-4000-8000-000000001102', now());

-- reads, walked to locked so the void can release them
INSERT INTO public.meter_readings (id, tenant_id, meter_id, reading_date, reading_value) VALUES
  ('00000000-0000-4000-8000-000000001301', '00000000-0000-4000-8000-0000000011a1', '00000000-0000-4000-8000-0000000011e1', '2026-03-31', 1000),
  ('00000000-0000-4000-8000-000000001302', '00000000-0000-4000-8000-0000000011a2', '00000000-0000-4000-8000-0000000011e2', '2026-03-31', 2000);
UPDATE public.meter_readings SET validation_status = 'approved' WHERE id IN ('00000000-0000-4000-8000-000000001301','00000000-0000-4000-8000-000000001302');
UPDATE public.meter_readings SET validation_status = 'released_to_billing' WHERE id IN ('00000000-0000-4000-8000-000000001301','00000000-0000-4000-8000-000000001302');
UPDATE public.meter_readings SET validation_status = 'locked', billing_period_locked = true, locked_by_billing_run_id = '00000000-0000-4000-8000-0000000011f1', locked_by_invoice_id = '00000000-0000-4000-8000-000000001101' WHERE id = '00000000-0000-4000-8000-000000001301';
UPDATE public.meter_readings SET validation_status = 'locked', billing_period_locked = true, locked_by_billing_run_id = '00000000-0000-4000-8000-0000000011f2', locked_by_invoice_id = '00000000-0000-4000-8000-000000001102' WHERE id = '00000000-0000-4000-8000-000000001302';

-- issue, then void with a non-auto-revert reason so the charge parks
UPDATE public.invoices SET status = 'pending' WHERE id IN ('00000000-0000-4000-8000-000000001101','00000000-0000-4000-8000-000000001102');
SELECT public.void_invoice('00000000-0000-4000-8000-000000001101', '00000000-0000-4000-8000-0000000011b1', 'wrong_customer', 'battery-11 T1', true);
SELECT public.void_invoice('00000000-0000-4000-8000-000000001102', '00000000-0000-4000-8000-0000000011b2', 'wrong_customer', 'battery-11 T2', true);

DO $$
DECLARE a int; r int;
BEGIN
  SELECT count(*) INTO a FROM public.adhoc_void_pending_review;
  SELECT count(*) INTO r FROM public.void_released_read_alerts;
  IF a <> 2 OR r <> 2 THEN
     RAISE EXCEPTION 'F0 FAILED: fixture did not produce one parked charge and one released read per tenant (charges=%, reads=%)', a, r;
  END IF;
  RAISE NOTICE 'PASS F0: fixture holds 2 tenants x (1 parked adhoc charge + 1 void-released read); superuser sees all 4';
END $$;

-- populate a statistics matview with BOTH tenants' rows (superuser; REFRESH
-- requires ownership). This is the payload the pre-patch grant handed out.
REFRESH MATERIALIZED VIEW public.compliance_statistics;
DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM public.compliance_statistics WHERE customer_number LIKE 'BAT11-%';
  IF n <> 2 THEN RAISE EXCEPTION 'F0b FAILED: matview holds % of the 2 fixture customers', n; END IF;
  RAISE NOTICE 'PASS F0b: compliance_statistics materialised both tenants'' customers (the payload the old grant exposed)';
END $$;

-- custom field definitions, one per tenant
INSERT INTO public.custom_field_definitions (tenant_id, entity_type, field_key, field_label, field_type, is_required, status) VALUES
  ('00000000-0000-4000-8000-0000000011a1', 'customers', 't1_badge', 'T1 Badge', 'text', true, 'active'),
  ('00000000-0000-4000-8000-0000000011a2', 'customers', 't2_badge', 'T2 Badge', 'text', true, 'active');

-- a correction run + target in T2 only: T1 must not be able to resolve its election
INSERT INTO public.billing_runs (id, tenant_id, run_number, billing_period, period_start, period_end, run_type, status, correction_rate_mode, started_at) VALUES
  ('00000000-0000-4000-8000-0000000011f3', '00000000-0000-4000-8000-0000000011a2', 'RUN-T2-CORR', '2026-03', '2026-03-01', '2026-03-31', 'correction', 'in_progress', 'historical', now());
INSERT INTO public.correction_run_targets (tenant_id, billing_run_id, voided_invoice_id, meter_id, customer_id, rate_date_mode, rate_date_override) VALUES
  ('00000000-0000-4000-8000-0000000011a2', '00000000-0000-4000-8000-0000000011f3', '00000000-0000-4000-8000-000000001102',
   '00000000-0000-4000-8000-0000000011e2', '00000000-0000-4000-8000-0000000011c2', 'custom', '2026-02-14');


-- ============================================================================
SET LOCAL app.user_id = '00000000-0000-4000-8000-0000000011b1';
SET ROLE tally_app;

CREATE OR REPLACE FUNCTION pg_temp.probe(p_label text, p_sql text, p_expect text) RETURNS void
LANGUAGE plpgsql AS $fn$
DECLARE v text;
BEGIN
  EXECUTE p_sql INTO v;
  IF v IS DISTINCT FROM p_expect THEN
    RAISE NOTICE 'PRE-PATCH HOLE  %  -> got % (patched build gives %)', p_label, coalesce(v,'NULL'), p_expect;
  ELSE
    RAISE NOTICE 'as expected     %  -> %', p_label, coalesce(v,'NULL');
  END IF;
END $fn$;
GRANT EXECUTE ON FUNCTION pg_temp.probe(text, text, text) TO tally_app;

SELECT pg_temp.probe('A1 adhoc_void_pending_review rows visible to tenant 1',
  'SELECT count(*)::text FROM public.adhoc_void_pending_review', '1');
SELECT pg_temp.probe('A2 void_released_read_alerts rows visible to tenant 1',
  'SELECT count(*)::text FROM public.void_released_read_alerts', '1');
SELECT pg_temp.probe('A3 views WITHOUT security_invoker',
  $q$SELECT count(*)::text FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
     WHERE n.nspname='public' AND c.relkind='v'
       AND coalesce((SELECT o FROM unnest(c.reloptions) o WHERE o LIKE 'security_invoker=%'),'') <> 'security_invoker=true'$q$, '0');
SELECT pg_temp.probe('A5 MATERIALIZED views readable by tally_app',
  $q$SELECT count(*)::text FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
     WHERE n.nspname='public' AND c.relkind='m' AND has_table_privilege('tally_app', c.oid, 'SELECT')$q$, '0');
SELECT pg_temp.probe('C1 of the five, still executable by PUBLIC',
  $q$SELECT count(*)::text FROM (VALUES ('public.get_user_tenant_id()'),('public.is_platform_admin()'),
        ('public.validate_custom_fields(uuid, text, jsonb)'),('public.get_correction_rate_date(uuid, uuid)'),
        ('public.void_invoice(uuid, uuid, text, text, boolean)')) x(sig)
     WHERE has_function_privilege('public', x.sig, 'EXECUTE')$q$, '0');
SELECT pg_temp.probe('E1 tenant 2 election leaked to tenant 1',
  $q$SELECT coalesce(public.get_correction_rate_date('00000000-0000-4000-8000-0000000011f3',
        '00000000-0000-4000-8000-000000001102')::text, 'NULL-refused')$q$, 'NULL-refused');

-- A6: the matview payload itself, read cross-tenant
SAVEPOINT s_a6;
DO $$ DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM public.compliance_statistics WHERE customer_number LIKE 'BAT11-%';
  RAISE NOTICE 'PRE-PATCH HOLE  A6 compliance_statistics read as tally_app -> % of 2 tenants'' customers (patched build REFUSES)', n;
EXCEPTION WHEN insufficient_privilege THEN
  RAISE NOTICE 'as expected     A6 compliance_statistics read as tally_app -> refused';
END $$;
ROLLBACK TO SAVEPOINT s_a6;

-- D3: does a foreign tenant id come back as a false VALID (with the other tenant's field metadata)?
SAVEPOINT s_d3;
DO $$ DECLARE r jsonb;
BEGIN
  r := public.validate_custom_fields('00000000-0000-4000-8000-0000000011a2', 'customers', '{}');
  RAISE NOTICE 'PRE-PATCH HOLE  D3 foreign tenant validate_custom_fields -> % (patched build REFUSES)', r;
EXCEPTION WHEN insufficient_privilege THEN
  RAISE NOTICE 'as expected     D3 foreign tenant validate_custom_fields -> refused';
END $$;
ROLLBACK TO SAVEPOINT s_d3;

-- B1: can a search_path='' session read an RLS table at all?
SAVEPOINT s_b1;
DO $$ DECLARE n int;
BEGIN
  SET LOCAL search_path = '';
  SELECT count(*) INTO n FROM public.customers;
  RAISE NOTICE 'as expected     B1 search_path='''' read of an RLS table -> % row(s)', n;
EXCEPTION WHEN undefined_table THEN
  RAISE NOTICE 'PRE-PATCH HOLE  B1 search_path='''' read of an RLS table -> %  (patched build succeeds)', left(SQLERRM, 45);
END $$;
ROLLBACK TO SAVEPOINT s_b1;
SET LOCAL search_path = "$user", public;

-- F2: does the discriminator accept the plural drift?
SAVEPOINT s_f;
DO $$ BEGIN
  INSERT INTO public.anomalies (tenant_id, anomaly_type, entity_type, entity_id, description)
  VALUES ('00000000-0000-4000-8000-0000000011a1', 'billing_run_exception', 'billing_runs', gen_random_uuid(), 'plural drift');
  RAISE NOTICE 'PRE-PATCH HOLE  F2 anomalies.entity_type accepted ''billing_runs'' (patched build REFUSES)';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'as expected     F2 anomalies.entity_type refused ''billing_runs''';
END $$;
ROLLBACK TO SAVEPOINT s_f;

-- C4 (superuser): is the NEXT definer function PUBLIC-executable?
RESET ROLE;
SAVEPOINT s_c4;
DO $$ DECLARE pub boolean;
BEGIN
  CREATE FUNCTION pg_temp.zz_probe() RETURNS int LANGUAGE sql SECURITY DEFINER SET search_path='' AS 'SELECT 1';
  EXECUTE $q$SELECT has_function_privilege('public','pg_temp.zz_probe()','EXECUTE')$q$ INTO pub;
  IF pub THEN
    RAISE NOTICE 'PRE-PATCH HOLE  C4 a newly created SECURITY DEFINER function is PUBLIC-executable (patched build: not)';
  ELSE
    RAISE NOTICE 'as expected     C4 a newly created SECURITY DEFINER function is NOT PUBLIC-executable';
  END IF;
END $$;
ROLLBACK TO SAVEPOINT s_c4;

ROLLBACK;
