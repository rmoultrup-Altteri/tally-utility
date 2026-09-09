-- ============================================================================
-- BATTERY v5.4.2-11 — definer hygiene, the two RLS-bypassing views, the
--                      blanket EXECUTE grant, anomalies.entity_type domain
-- Run: psql -U tally -d <db-with-patch> -v ON_ERROR_STOP=1 -f battery-11.sql
-- One transaction, rolled back. Negative cases inside DO exception handlers.
-- TWO tenants throughout: every headline check in this patch is cross-tenant,
-- so a single-tenant fixture would pass against the unpatched build.
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
-- Everything below runs as tally_app in TENANT 1.
-- ============================================================================
SET LOCAL app.user_id = '00000000-0000-4000-8000-0000000011b1';
SET ROLE tally_app;

-- ---------------------------------------------------------------------------
-- A. THE LEAK: the two views must not show tenant 2's rows to tenant 1
-- ---------------------------------------------------------------------------

DO $$
DECLARE n int; leaked text;
BEGIN
  SELECT count(*), coalesce(string_agg(description, '; '), '') INTO n, leaked
    FROM public.adhoc_void_pending_review;
  IF n <> 1 OR leaked LIKE '%T2 SECRET%' THEN
    RAISE EXCEPTION 'A1 FAILED: adhoc_void_pending_review returned % row(s) to tenant 1 [%] — the view still runs with owner (BYPASSRLS) rights', n, leaked;
  END IF;
  RAISE NOTICE 'PASS A1: adhoc_void_pending_review shows tenant 1 exactly its own parked charge (1 of 2)';
END $$;

DO $$
DECLARE n int; own boolean;
BEGIN
  SELECT count(*), coalesce(bool_and(tenant_id = '00000000-0000-4000-8000-0000000011a1'), false)
    INTO n, own FROM public.void_released_read_alerts;
  IF n <> 1 OR NOT own THEN
    RAISE EXCEPTION 'A2 FAILED: void_released_read_alerts returned % row(s) to tenant 1 (all own-tenant: %) — the view still runs with owner rights', n, own;
  END IF;
  RAISE NOTICE 'PASS A2: void_released_read_alerts shows tenant 1 exactly its own released read (1 of 2)';
END $$;

DO $$
DECLARE bad text;
BEGIN
  SELECT string_agg(c.relname, ', ' ORDER BY c.relname) INTO bad
    FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'public' AND c.relkind = 'v'
     AND coalesce((SELECT o FROM unnest(c.reloptions) o WHERE o LIKE 'security_invoker=%'), '') <> 'security_invoker=true';
  IF bad IS NOT NULL THEN RAISE EXCEPTION 'A3 FAILED: view(s) without security_invoker: %', bad; END IF;
  RAISE NOTICE 'PASS A3: every view in public carries security_invoker = true';
END $$;

-- A4 control: security_invoker did not simply break the views — a platform
-- admin still sees both tenants through them (the policy admits them).
SET LOCAL app.user_id = '00000000-0000-4000-8000-0000000011b9';
DO $$
DECLARE a int; r int;
BEGIN
  SELECT count(*) INTO a FROM public.adhoc_void_pending_review;
  SELECT count(*) INTO r FROM public.void_released_read_alerts;
  IF a <> 2 OR r <> 2 THEN
    RAISE EXCEPTION 'A4 FAILED: platform admin sees % charge(s) / % read(s), expected 2 and 2 — security_invoker broke legitimate cross-tenant access', a, r;
  END IF;
  RAISE NOTICE 'PASS A4: a platform admin still reads both tenants through both views (the option scopes, it does not break)';
END $$;
SET LOCAL app.user_id = '00000000-0000-4000-8000-0000000011b1';

-- A5/A6: the MATERIALIZED views. A3 above filters relkind = 'v' and therefore
-- cannot see relkind = 'm' — that blind spot let four leaking matviews stand
-- behind a passing self-check through round 1. A matview takes neither
-- security_invoker nor a policy, so the assertion is on the grant.
DO $$
DECLARE bad text;
BEGIN
  SELECT string_agg(c.relname, ', ' ORDER BY c.relname) INTO bad
    FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'public' AND c.relkind = 'm'
     AND (has_any_column_privilege('tally_app', c.oid, 'SELECT') OR has_any_column_privilege('public', c.oid, 'SELECT'));
  IF bad IS NOT NULL THEN
    RAISE EXCEPTION 'A5 FAILED: materialized view(s) readable by tally_app or PUBLIC: %', bad;
  END IF;
  RAISE NOTICE 'PASS A5: no materialized view is reachable by tally_app or PUBLIC (column grants included — has_table_privilege alone is blind to them)';
END $$;

DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM public.compliance_statistics;
  RAISE EXCEPTION 'A6 FAILED: tally_app read % row(s) from compliance_statistics — the matview leak is open', n;
EXCEPTION WHEN insufficient_privilege THEN
  RAISE NOTICE 'PASS A6: a direct read of compliance_statistics as tally_app is refused (%)', left(SQLERRM, 55);
END $$;

-- ---------------------------------------------------------------------------
-- B. A-23 (1c): a session pinned to an empty search_path can now read RLS
--    tables at all. Before this patch this raised
--    'relation "users" does not exist' from inside get_user_tenant_id.
-- ---------------------------------------------------------------------------

SET LOCAL search_path = '';
DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM public.customers;
  IF n <> 1 THEN RAISE EXCEPTION 'B1 FAILED: search_path='''' session saw % customer(s), expected tenant 1''s single row', n; END IF;
  RAISE NOTICE 'PASS B1: a tally_app session pinned to search_path = '''' reads an RLS table, and is still tenant-scoped (1 of 2 customers)';
END $$;
SET LOCAL search_path = "$user", public;

-- ---------------------------------------------------------------------------
-- C. Grants: PUBLIC lost EXECUTE; tally_app kept what it needs
-- ---------------------------------------------------------------------------

DO $$
DECLARE bad text;
BEGIN
  SELECT string_agg(x.sig, ', ' ORDER BY x.sig) INTO bad
    FROM (VALUES ('public.get_user_tenant_id()'), ('public.is_platform_admin()'),
                 ('public.validate_custom_fields(uuid, text, jsonb)'),
                 ('public.get_correction_rate_date(uuid, uuid)'),
                 ('public.void_invoice(uuid, uuid, text, text, boolean)')) AS x(sig)
   WHERE has_function_privilege('public', x.sig, 'EXECUTE');
  IF bad IS NOT NULL THEN RAISE EXCEPTION 'C1 FAILED: PUBLIC still holds EXECUTE on: %', bad; END IF;
  RAISE NOTICE 'PASS C1: PUBLIC holds EXECUTE on none of the five tightened functions';
END $$;

DO $$
BEGIN
  PERFORM public.get_user_tenant_id();
  PERFORM public.is_platform_admin();
  RAISE NOTICE 'PASS C2: tally_app still executes both tenant_isolation policy helpers (without these, every RLS read fails)';
END $$;

-- C3: void_invoice() actually CALLED by tally_app after the PUBLIC revoke.
-- Round 1 (Fable) noted the fixture voids as superuser, so the explicit grant
-- at section 5a was asserted by catalog only and never exercised.
SELECT pg_temp.inv('00000000-0000-4000-8000-000000001104', 'T1-INV-2', '00000000-0000-4000-8000-0000000011a1',
                   '00000000-0000-4000-8000-0000000011f1', '00000000-0000-4000-8000-0000000011c1',
                   '00000000-0000-4000-8000-0000000011d1', 'regular', NULL, '2026-03-01', '2026-03-31');
SELECT pg_temp.snap('00000000-0000-4000-8000-000000001104', '2026-03-31', now());
UPDATE public.invoices SET status = 'pending' WHERE id = '00000000-0000-4000-8000-000000001104';
DO $$
DECLARE r jsonb;
BEGIN
  r := public.void_invoice('00000000-0000-4000-8000-000000001104', '00000000-0000-4000-8000-0000000011b1',
                           'wrong_rate', 'battery-11 C3: called as tally_app', true);
  IF r ->> 'invoice_number' <> 'T1-INV-2' THEN RAISE EXCEPTION 'C3 FAILED: void_invoice returned %', r; END IF;
  RAISE NOTICE 'PASS C3: tally_app can still CALL void_invoice() after the PUBLIC revoke (the explicit grant is live, not just catalogued)';
END $$;

-- ---------------------------------------------------------------------------
-- D. validate_custom_fields: invoker rights plus an explicit tenant refusal
-- ---------------------------------------------------------------------------

DO $$
DECLARE r jsonb;
BEGIN
  r := public.validate_custom_fields('00000000-0000-4000-8000-0000000011a1', 'customers', '{"t1_badge":"ABC"}');
  IF r <> '[]'::jsonb THEN RAISE EXCEPTION 'D1 FAILED: own-tenant valid metadata returned %', r; END IF;
  RAISE NOTICE 'PASS D1: own tenant, satisfied required field -> [] (valid)';
END $$;

DO $$
DECLARE r jsonb;
BEGIN
  r := public.validate_custom_fields('00000000-0000-4000-8000-0000000011a1', 'customers', '{}');
  IF jsonb_array_length(r) <> 1 OR r -> 0 ->> 'field' <> 't1_badge' THEN
    RAISE EXCEPTION 'D2 FAILED: own-tenant missing required field returned %', r;
  END IF;
  RAISE NOTICE 'PASS D2: own tenant, missing required field -> one error naming t1_badge (the function still works)';
END $$;

DO $$
DECLARE r jsonb;
BEGIN
  r := public.validate_custom_fields('00000000-0000-4000-8000-0000000011a2', 'customers', '{}');
  RAISE EXCEPTION 'D3 FAILED: foreign tenant id accepted and returned % — a false VALID', r;
EXCEPTION WHEN insufficient_privilege THEN
  RAISE NOTICE 'PASS D3: a foreign p_tenant_id is REFUSED, not silently answered "[]" (%)', left(SQLERRM, 60);
END $$;

DO $$
BEGIN
  PERFORM public.validate_custom_fields(NULL, 'customers', '{}');
  RAISE EXCEPTION 'D4 FAILED: NULL p_tenant_id accepted';
EXCEPTION WHEN null_value_not_allowed THEN
  RAISE NOTICE 'PASS D4: NULL p_tenant_id refused';
END $$;

-- D5: the NULL leg. app.user_id names no user, so get_user_tenant_id() is
-- NULL; `p_tenant_id <> NULL` would be NULL and IF would treat it as false.
SET LOCAL app.user_id = '00000000-0000-4000-8000-00000000dead';
DO $$
BEGIN
  PERFORM public.validate_custom_fields('00000000-0000-4000-8000-0000000011a1', 'customers', '{}');
  RAISE EXCEPTION 'D5 FAILED: caller with no resolvable tenant walked through the refusal (the NULL leg)';
EXCEPTION WHEN insufficient_privilege THEN
  RAISE NOTICE 'PASS D5: a caller whose app.user_id resolves to no tenant is refused (IS DISTINCT FROM, not <>)';
END $$;
SET LOCAL app.user_id = '00000000-0000-4000-8000-0000000011b1';

DO $$
DECLARE r jsonb;
BEGIN
  PERFORM set_config('app.user_id', '00000000-0000-4000-8000-0000000011b9', true);
  r := public.validate_custom_fields('00000000-0000-4000-8000-0000000011a2', 'customers', '{}');
  IF jsonb_array_length(r) <> 1 THEN RAISE EXCEPTION 'D6 FAILED: platform admin got % for tenant 2', r; END IF;
  PERFORM set_config('app.user_id', '00000000-0000-4000-8000-0000000011b1', true);
  RAISE NOTICE 'PASS D6: a platform admin may validate another tenant''s definitions (the exemption works)';
END $$;

DO $$
BEGIN
  IF (SELECT p.prosecdef FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
       WHERE n.nspname='public' AND p.proname='validate_custom_fields') THEN
    RAISE EXCEPTION 'D7 FAILED: validate_custom_fields is still SECURITY DEFINER';
  END IF;
  RAISE NOTICE 'PASS D7: validate_custom_fields runs with invoker rights';
END $$;

-- ---------------------------------------------------------------------------
-- E. get_correction_rate_date: invoker rights, and the -10 binding still works
-- ---------------------------------------------------------------------------

DO $$
DECLARE d date;
BEGIN
  d := public.get_correction_rate_date('00000000-0000-4000-8000-0000000011f3', '00000000-0000-4000-8000-000000001102');
  IF d IS NOT NULL THEN
    RAISE EXCEPTION 'E1 FAILED: tenant 1 resolved tenant 2''s recorded rate-date election (%) — the resolver still runs as definer', d;
  END IF;
  RAISE NOTICE 'PASS E1: tenant 2''s (run, invoice) election resolves to NULL for tenant 1, not to its date (2026-02-14)';
END $$;

DO $$
BEGIN
  IF (SELECT p.prosecdef FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
       WHERE n.nspname='public' AND p.proname='get_correction_rate_date') THEN
    RAISE EXCEPTION 'E2 FAILED: get_correction_rate_date is still SECURITY DEFINER';
  END IF;
  RAISE NOTICE 'PASS E2: get_correction_rate_date runs with invoker rights';
END $$;

-- E3/E4: the v5.4.2-10 coordinate binding still works end to end with the
-- resolver on invoker rights — the regression that matters most here.
INSERT INTO public.billing_runs (id, tenant_id, run_number, billing_period, period_start, period_end, run_type, status, correction_rate_mode) VALUES
  ('00000000-0000-4000-8000-0000000011f4', '00000000-0000-4000-8000-0000000011a1', 'RUN-T1-CORR', '2026-03', '2026-03-01', '2026-03-31', 'correction', 'in_progress', 'historical');
INSERT INTO public.correction_run_targets (tenant_id, billing_run_id, voided_invoice_id, meter_id, customer_id, rate_date_mode) VALUES
  ('00000000-0000-4000-8000-0000000011a1', '00000000-0000-4000-8000-0000000011f4', '00000000-0000-4000-8000-000000001101',
   '00000000-0000-4000-8000-0000000011e1', '00000000-0000-4000-8000-0000000011c1', 'historical');

DO $$
DECLARE d date;
BEGIN
  d := public.get_correction_rate_date('00000000-0000-4000-8000-0000000011f4', '00000000-0000-4000-8000-000000001101');
  IF d <> '2026-03-31' THEN
    RAISE EXCEPTION 'E3 FAILED: own-tenant election resolved %, expected the voided bill''s period_end 2026-03-31', d;
  END IF;
  RAISE NOTICE 'PASS E3: own tenant resolves its recorded election under invoker rights (historical -> 2026-03-31)';
END $$;

SELECT pg_temp.inv('00000000-0000-4000-8000-000000001103', 'T1-CORR-1', '00000000-0000-4000-8000-0000000011a1',
                   '00000000-0000-4000-8000-0000000011f4', '00000000-0000-4000-8000-0000000011c1',
                   '00000000-0000-4000-8000-0000000011d1', 'correction', '00000000-0000-4000-8000-000000001101',
                   '2026-03-01', '2026-03-31');
SELECT pg_temp.snap('00000000-0000-4000-8000-000000001103', '2026-03-31', now());
DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM public.invoice_calculation_snapshots WHERE invoice_id = '00000000-0000-4000-8000-000000001103';
  IF n <> 1 THEN RAISE EXCEPTION 'E4 FAILED: correction snapshot not written'; END IF;
  RAISE NOTICE 'PASS E4: a correction snapshot still passes the v5.4.2-10 binding with the resolver on invoker rights';
END $$;

DO $$
BEGIN
  PERFORM pg_temp.snap('00000000-0000-4000-8000-000000001103', '2026-02-14', now());
  RAISE EXCEPTION 'E5 FAILED: a correction snapshot was accepted at tenant 2''s election date';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'PASS E5: the binding still refuses a valid_at that is not this target''s election (%)', left(SQLERRM, 70);
END $$;

-- ---------------------------------------------------------------------------
-- F. anomalies.entity_type: the fifteen-value domain
-- ---------------------------------------------------------------------------

DO $$
DECLARE v text; n int := 0;
BEGIN
  FOREACH v IN ARRAY ARRAY['customer','service_location','meter','meter_reading','invoice',
                           'invoice_line_item','billing_run','rate_schedule','payment','payment_method',
                           'customer_credit','deposit','customer_tax_exemption','escheatment_event','import_job']
  LOOP
    INSERT INTO public.anomalies (tenant_id, anomaly_type, entity_type, entity_id, description)
    VALUES ('00000000-0000-4000-8000-0000000011a1', 'other', v, gen_random_uuid(), 'battery-11 domain probe: ' || v);
    n := n + 1;
  END LOOP;
  IF n <> 15 THEN RAISE EXCEPTION 'F1 FAILED: only % of 15 domain values accepted', n; END IF;
  RAISE NOTICE 'PASS F1: all fifteen domain values are accepted';
END $$;

DO $$
BEGIN
  INSERT INTO public.anomalies (tenant_id, anomaly_type, entity_type, entity_id, description)
  VALUES ('00000000-0000-4000-8000-0000000011a1', 'billing_run_exception', 'billing_runs', gen_random_uuid(), 'plural drift');
  RAISE EXCEPTION 'F2 FAILED: the plural ''billing_runs'' was accepted — the exact drift the routing table warned about';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'PASS F2: ''billing_runs'' (plural drift) is refused — routing keys on this column';
END $$;

DO $$
BEGIN
  INSERT INTO public.anomalies (tenant_id, anomaly_type, entity_type, entity_id, description)
  VALUES ('00000000-0000-4000-8000-0000000011a1', 'other', 'adhoc_charge', gen_random_uuid(), 'deliberately out of domain');
  RAISE EXCEPTION 'F3 FAILED: ''adhoc_charge'' was accepted — it is deliberately NOT seeded';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'PASS F3: ''adhoc_charge'' is refused (not seeded; widening the CHECK is a decision, not a migration)';
END $$;

DO $$
BEGIN
  INSERT INTO public.anomalies (tenant_id, anomaly_type, entity_type, entity_id, description, detection_method, detector_name, dedup_key)
  VALUES ('00000000-0000-4000-8000-0000000011a1', 'reference_correction_review', 'rate_schedule', gen_random_uuid(),
          'shape written by enforce_service_type_change (v5.4.2-03)', 'rule_based', 'battery-11', 'reference_correction_review:rate_schedule:probe');
  RAISE NOTICE 'PASS F4: the only live writer''s row shape (reference_correction_review / rate_schedule) passes the new domain';
END $$;

-- ---------------------------------------------------------------------------
RESET ROLE;

-- C4 (superuser): the DEFAULT that would hand the NEXT definer to PUBLIC.
-- tally_app cannot CREATE FUNCTION, so this one runs as the owner.
DO $$
DECLARE pub boolean;
BEGIN
  CREATE FUNCTION pg_temp.zz_probe() RETURNS int LANGUAGE sql SECURITY DEFINER SET search_path = '' AS 'SELECT 1';
  EXECUTE $q$SELECT has_function_privilege('public', 'pg_temp.zz_probe()', 'EXECUTE')$q$ INTO pub;
  IF pub THEN
    RAISE EXCEPTION 'C4 FAILED: a newly created SECURITY DEFINER function is PUBLIC-executable — section 5b did not take';
  END IF;
  RAISE NOTICE 'PASS C4: a newly created SECURITY DEFINER function is NOT PUBLIC-executable (the default privilege is revoked)';
END $$;

-- Not a pass/fail: report the TEMP state this run is ACTUALLY under. tu.sql
-- revokes TEMP with current_database(), and CREATE DATABASE ... TEMPLATE does
-- not copy datacl — so a battery on a clone runs WITH TEMP held, unlike the
-- deployed database. Printed so the discrepancy is visible, never assumed.
DO $$
DECLARE t boolean;
BEGIN
  t := has_database_privilege('tally_app', current_database(), 'TEMP');
  RAISE NOTICE 'CONTEXT: tally_app TEMP on %  = %  (deployed tally = false; a TEMPLATE clone = true — datacl is not copied)',
        current_database(), t;
END $$;

-- ---------------------------------------------------------------------------
-- G. assert_tenant_isolation_invariants(): it must CATCH drift, not just pass.
--    These run as the owner — tally_app cannot CREATE, and must not be able to
--    execute the assertion either (G1).
-- ---------------------------------------------------------------------------

DO $$
BEGIN
  IF has_function_privilege('tally_app', 'public.assert_tenant_isolation_invariants()', 'EXECUTE')
     OR has_function_privilege('public', 'public.assert_tenant_isolation_invariants()', 'EXECUTE') THEN
    RAISE EXCEPTION 'G1 FAILED: the invariant assertion is executable by tally_app or PUBLIC (the per-schema default grants it at creation unless revoked)';
  END IF;
  PERFORM public.assert_tenant_isolation_invariants();
  RAISE NOTICE 'PASS G1: assert_tenant_isolation_invariants() is owner-only and passes on this build';
END $$;

SAVEPOINT g2;
DO $$
BEGIN
  CREATE MATERIALIZED VIEW public.zz_drift_mv AS SELECT tenant_id FROM public.customers;
  PERFORM public.assert_tenant_isolation_invariants();
  RAISE EXCEPTION 'G2 FAILED: a newly created materialized view passed the assertion — it is born tally_app-readable via the ALL TABLES default grant';
EXCEPTION WHEN insufficient_privilege THEN
  RAISE NOTICE 'PASS G2: a newly created matview makes the assertion RAISE (%)', left(SQLERRM, 60);
END $$;
ROLLBACK TO SAVEPOINT g2;

SAVEPOINT g3;
DO $$
BEGIN
  CREATE VIEW public.zz_drift_v AS SELECT tenant_id FROM public.customers;
  PERFORM public.assert_tenant_isolation_invariants();
  RAISE EXCEPTION 'G3 FAILED: a newly created view passed — CREATE VIEW has no security_invoker by default';
EXCEPTION WHEN insufficient_privilege THEN
  RAISE NOTICE 'PASS G3: a newly created (owner-rights) view makes the assertion RAISE (%)', left(SQLERRM, 55);
END $$;
ROLLBACK TO SAVEPOINT g3;

SAVEPOINT g4;
DO $$
BEGIN
  ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO PUBLIC;
  PERFORM public.assert_tenant_isolation_invariants();
  RAISE EXCEPTION 'G4 FAILED: a per-schema PUBLIC EXECUTE default passed — it reopens section 5b for every new function';
EXCEPTION WHEN insufficient_privilege THEN
  RAISE NOTICE 'PASS G4: a per-schema PUBLIC EXECUTE default makes the assertion RAISE (%)', left(SQLERRM, 60);
END $$;
ROLLBACK TO SAVEPOINT g4;

SAVEPOINT g5;
DO $$
BEGIN
  GRANT SELECT (tenant_id) ON public.compliance_statistics TO tally_app;
  PERFORM public.assert_tenant_isolation_invariants();
  RAISE EXCEPTION 'G5 FAILED: a COLUMN-level grant on a matview passed — has_table_privilege is blind to column grants';
EXCEPTION WHEN insufficient_privilege THEN
  RAISE NOTICE 'PASS G5: a column-level grant on a matview makes the assertion RAISE (%)', left(SQLERRM, 60);
END $$;
ROLLBACK TO SAVEPOINT g5;

-- G6-G9: the TABLE drift shapes (round 3 — the surface the assertion is named
-- for, found independently by both reviewers). Each ROLLBACKs to its savepoint.

SAVEPOINT g6;
DO $$
BEGIN
  CREATE TABLE public.zz_drift_t (id uuid PRIMARY KEY, tenant_id uuid NOT NULL, secret text);
  PERFORM public.assert_tenant_isolation_invariants();
  RAISE EXCEPTION 'G6 FAILED: a new table with a tenant_id column and no RLS passed — the ALL TABLES default grant makes it tally_app-readable at birth';
EXCEPTION WHEN insufficient_privilege THEN
  RAISE NOTICE 'PASS G6: a new tenant table with no RLS makes the assertion RAISE (%)', left(SQLERRM, 60);
END $$;
ROLLBACK TO SAVEPOINT g6;

SAVEPOINT g7;
DO $$
BEGIN
  ALTER TABLE public.customers DISABLE ROW LEVEL SECURITY;
  PERFORM public.assert_tenant_isolation_invariants();
  RAISE EXCEPTION 'G7 FAILED: RLS disabled on customers passed';
EXCEPTION WHEN insufficient_privilege THEN
  RAISE NOTICE 'PASS G7: DISABLE ROW LEVEL SECURITY on an existing table makes the assertion RAISE';
END $$;
ROLLBACK TO SAVEPOINT g7;

SAVEPOINT g8;
DO $$
BEGIN
  CREATE POLICY zz_open ON public.customers USING (true);
  PERFORM public.assert_tenant_isolation_invariants();
  RAISE EXCEPTION 'G8 FAILED: a second permissive USING (true) policy passed — policies are OR-ed, so it opens the table to every tenant';
EXCEPTION WHEN insufficient_privilege THEN
  RAISE NOTICE 'PASS G8: an added permissive policy makes the assertion RAISE (existence of a policy is not enough)';
END $$;
ROLLBACK TO SAVEPOINT g8;

SAVEPOINT g9;
DO $$
BEGIN
  CREATE TABLE public.zz_drift_p (tenant_id uuid NOT NULL, d date NOT NULL, secret text) PARTITION BY RANGE (d);
  ALTER TABLE public.zz_drift_p ENABLE ROW LEVEL SECURITY;
  ALTER TABLE public.zz_drift_p FORCE ROW LEVEL SECURITY;
  CREATE POLICY tenant_isolation ON public.zz_drift_p USING (public.is_platform_admin() OR tenant_id = public.get_user_tenant_id());
  CREATE TABLE public.zz_drift_p_2026 PARTITION OF public.zz_drift_p FOR VALUES FROM ('2026-01-01') TO ('2027-01-01');
  PERFORM public.assert_tenant_isolation_invariants();
  RAISE EXCEPTION 'G9 FAILED: a partition child passed — it inherits the column but NOT the parent''s row security, and a direct read of the child bypasses the parent policy';
EXCEPTION WHEN insufficient_privilege THEN
  RAISE NOTICE 'PASS G9: a partition child without its own row security makes the assertion RAISE';
END $$;
ROLLBACK TO SAVEPOINT g9;

-- G10: the WRITE-side inverse of G8, found independently by both reviewers in
-- round 4. A canonical USING with a permissive WITH CHECK is read-isolated and
-- write-open. Proved as a real cross-tenant WRITE first, then as a raise.
-- NOTE: the INSERT must carry NO RETURNING clause — RETURNING re-applies the
-- SELECT policy to the returned row and fails with an RLS error that looks
-- like the write was blocked, masking the hole (Fable, round 4).
SAVEPOINT g10;
CREATE TABLE public.zz_wc (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), tenant_id uuid NOT NULL, note text);
ALTER TABLE public.zz_wc ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.zz_wc FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON public.zz_wc
  USING (public.is_platform_admin() OR tenant_id = public.get_user_tenant_id())
  WITH CHECK (true);
GRANT SELECT, INSERT ON public.zz_wc TO tally_app;

SET LOCAL app.user_id = '00000000-0000-4000-8000-0000000011b1';
SET ROLE tally_app;
INSERT INTO public.zz_wc (tenant_id, note)
  VALUES ('00000000-0000-4000-8000-0000000011a2', 'PLANTED BY TENANT 1');
RESET ROLE;
DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM public.zz_wc
   WHERE tenant_id = '00000000-0000-4000-8000-0000000011a2' AND note = 'PLANTED BY TENANT 1';
  IF n <> 1 THEN RAISE EXCEPTION 'G10 setup FAILED: the cross-tenant write did not land, so the case under test is not the case being tested'; END IF;
  RAISE NOTICE 'PASS G10a: a permissive WITH CHECK really does let tenant 1 plant a row in tenant 2 (the hole is real, not hypothetical)';
END $$;
DO $$
BEGIN
  PERFORM public.assert_tenant_isolation_invariants();
  RAISE EXCEPTION 'G10b FAILED: canonical USING + permissive WITH CHECK passed the assertion — polqual and polwithcheck must be checked INDEPENDENTLY, not coalesced';
EXCEPTION WHEN insufficient_privilege THEN
  RAISE NOTICE 'PASS G10b: a permissive WITH CHECK makes the assertion RAISE (write-side isolation is checked, not just read-side)';
END $$;
ROLLBACK TO SAVEPOINT g10;

-- G11: the false positive the round-4 draft had. A RESTRICTIVE policy is
-- AND-ed and can only narrow access, so it must NOT be refused (Codex).
SAVEPOINT g11;
DO $$
BEGIN
  CREATE POLICY zz_guard ON public.customers AS RESTRICTIVE USING (customer_number IS NOT NULL);
  PERFORM public.assert_tenant_isolation_invariants();
  RAISE NOTICE 'PASS G11: an added RESTRICTIVE policy is accepted (it can only narrow — refusing it blocked a legitimate extra guard)';
EXCEPTION WHEN insufficient_privilege THEN
  RAISE EXCEPTION 'G11 FAILED: a RESTRICTIVE policy was refused — the canonical-string test must apply to PERMISSIVE policies only';
END $$;
ROLLBACK TO SAVEPOINT g11;

DO $$ BEGIN RAISE NOTICE '--- battery v5.4.2-11 complete: 41 checks ---'; END $$;
ROLLBACK;
