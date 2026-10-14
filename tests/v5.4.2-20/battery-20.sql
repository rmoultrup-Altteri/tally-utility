-- ============================================================================
-- BATTERY v5.4.2-20 — the version-check and void seals (2026-10-14)
-- Run: psql -U tally -d <db-with-patch> -v ON_ERROR_STOP=1 -f battery-20.sql
-- One transaction, rolled back. Fixtures as the owner; every guard the
-- application meets is exercised as tally_app under app.user_id.
-- pg_temp.refuses_at() runs one statement and requires the named SQLSTATE
-- AND the named guard (a constraint name or a fragment of its message);
-- anything else, or success, is a FAIL.
--
--   G  the catalog: roles, owners, grants, invariants
--   S  the version check: no write around it (S1-S12)
--   V  the void: its role, its exact writes, its tenant, its lock (V1-V12)
-- What one transaction cannot show (a receipt from another transaction,
-- autocommit between the check and the write, a dump-and-restore id, two
-- sessions) is in txn-20.sh and races/seal-20.sh.
-- ============================================================================
BEGIN;
SET CONSTRAINTS ALL IMMEDIATE;

CREATE FUNCTION pg_temp.refuses_at(p_label text, p_sql text, p_state text, p_guard text) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE v_con text;
BEGIN
  BEGIN
    EXECUTE p_sql;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_con = CONSTRAINT_NAME;
    IF SQLSTATE = p_state AND (v_con = p_guard OR strpos(SQLERRM, p_guard) > 0) THEN
      RAISE NOTICE 'PASS %: refused by % (%)', p_label, p_guard, left(SQLERRM, 120);
      RETURN;
    END IF;
    RAISE EXCEPTION 'FAIL %: refused with % [%] (%), expected % by %', p_label, SQLSTATE, v_con, SQLERRM, p_state, p_guard;
  END;
  RAISE EXCEPTION 'FAIL %: accepted', p_label;
END $$;
GRANT EXECUTE ON FUNCTION pg_temp.refuses_at(text, text, text, text) TO tally_app, tally_core, tally_void;
CREATE FUNCTION pg_temp.ok(p_label text, p_cond boolean) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  IF p_cond IS DISTINCT FROM true THEN RAISE EXCEPTION 'FAIL %', p_label; END IF;
  RAISE NOTICE 'PASS %', p_label;
END $$;
GRANT EXECUTE ON FUNCTION pg_temp.ok(text, boolean) TO tally_app, tally_core, tally_void;
-- admits(): a write that must succeed; any error is that check's FAIL.
CREATE FUNCTION pg_temp.admits(p_label text, p_sql text) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE p_sql;
  RAISE NOTICE 'PASS %', p_label;
EXCEPTION WHEN OTHERS THEN
  RAISE EXCEPTION 'FAIL %: refused with % (%)', p_label, SQLSTATE, SQLERRM;
END $$;
GRANT EXECUTE ON FUNCTION pg_temp.admits(text, text) TO tally_app, tally_core, tally_void;

-- ------------------------------------------------------------------ fixtures
INSERT INTO public.tenants (id, name, slug) VALUES
  ('00000000-0000-4000-8000-0000000020a1', 'T1 City Gas', 'bat20-t1'),
  ('00000000-0000-4000-8000-0000000020a2', 'T2 Gasco', 'bat20-t2');
INSERT INTO public.users (id, tenant_id, display_name, email, role) VALUES
  ('00000000-0000-4000-8000-0000000020b1', '00000000-0000-4000-8000-0000000020a1', 'Op1', 'op1@bat20.test', 'operator'),
  ('00000000-0000-4000-8000-0000000020b2', '00000000-0000-4000-8000-0000000020a2', 'Op2', 'op2@bat20.test', 'operator'),
  ('00000000-0000-4000-8000-0000000020b9', '00000000-0000-4000-8000-0000000020a1', 'Admin', 'admin@bat20.test', 'platform_admin');
INSERT INTO public.customers (id, tenant_id, customer_number, customer_type) VALUES
  ('00000000-0000-4000-8000-0000000020c1', '00000000-0000-4000-8000-0000000020a1', 'B20-C1', 'residential'),
  ('00000000-0000-4000-8000-0000000020c2', '00000000-0000-4000-8000-0000000020a2', 'B20-C2', 'residential');
INSERT INTO public.service_locations (id, tenant_id, customer_id, location_number, address_line1, city, state, zip) VALUES
  ('00000000-0000-4000-8000-0000000020d1', '00000000-0000-4000-8000-0000000020a1', '00000000-0000-4000-8000-0000000020c1', 'L1', '1 Main', 'Austin', 'TX', '78701'),
  ('00000000-0000-4000-8000-0000000020d2', '00000000-0000-4000-8000-0000000020a2', '00000000-0000-4000-8000-0000000020c2', 'L2', '2 Main', 'Austin', 'TX', '78702');
INSERT INTO public.meters (id, tenant_id, meter_number, location_id, service_type) VALUES
  ('00000000-0000-4000-8000-0000000020e1', '00000000-0000-4000-8000-0000000020a1', 'M1', '00000000-0000-4000-8000-0000000020d1', 'gas'),
  ('00000000-0000-4000-8000-0000000020e2', '00000000-0000-4000-8000-0000000020a1', 'M2', '00000000-0000-4000-8000-0000000020d1', 'gas'),
  ('00000000-0000-4000-8000-0000000020e3', '00000000-0000-4000-8000-0000000020a1', 'M3', '00000000-0000-4000-8000-0000000020d1', 'gas'),
  ('00000000-0000-4000-8000-0000000020e9', '00000000-0000-4000-8000-0000000020a2', 'M9', '00000000-0000-4000-8000-0000000020d2', 'gas');
INSERT INTO public.billing_runs (id, tenant_id, run_number, billing_period, period_start, period_end) VALUES
  ('00000000-0000-4000-8000-0000000020f1', '00000000-0000-4000-8000-0000000020a1', 'R1', '2026-01', '2026-01-01', '2026-01-31'),
  ('00000000-0000-4000-8000-0000000020f9', '00000000-0000-4000-8000-0000000020a2', 'R9', '2026-01', '2026-01-01', '2026-01-31');
-- Headers, as the owner (a header is born at version 1).
INSERT INTO public.rate_schedules (id, tenant_id, code) VALUES
  ('00000000-0000-4000-8000-000000002041', '00000000-0000-4000-8000-0000000020a1', 'RS1'),
  ('00000000-0000-4000-8000-000000002042', '00000000-0000-4000-8000-0000000020a1', 'RS2'),
  ('00000000-0000-4000-8000-000000002049', '00000000-0000-4000-8000-0000000020a2', 'RS9');
INSERT INTO public.rate_items (id, tenant_id, item_code) VALUES
  ('00000000-0000-4000-8000-000000002051', '00000000-0000-4000-8000-0000000020a1', 'IT1');
INSERT INTO public.wna_zones (id, tenant_id, zone_code) VALUES
  ('00000000-0000-4000-8000-000000002061', '00000000-0000-4000-8000-0000000020a1', 'Z1'),
  ('00000000-0000-4000-8000-000000002062', '00000000-0000-4000-8000-0000000020a1', 'Z2');

SET LOCAL app.user_id = '00000000-0000-4000-8000-0000000020b1';


-- ===================================================================== G. the catalog
DO $$ BEGIN
  PERFORM public.assert_seal_role_invariants();
  PERFORM public.assert_core_role_invariants();
  PERFORM public.assert_tenant_isolation_invariants();
  RAISE NOTICE 'PASS G1: seal-role, core-role and tenant-isolation invariants hold';
END $$;
SELECT pg_temp.ok('G2 the owners: tally_seal owns the check and the receipt test, tally_void the void',
  (SELECT proowner::regrole::text FROM pg_proc WHERE oid = 'public.assert_reference_version(text,uuid,integer)'::regprocedure) = 'tally_seal'
  AND (SELECT proowner::regrole::text FROM pg_proc WHERE oid = 'public.reference_version_receipt_held(text,uuid)'::regprocedure) = 'tally_seal'
  AND (SELECT proowner::regrole::text FROM pg_proc WHERE oid = 'public.void_invoice(uuid,uuid,text,text,boolean)'::regprocedure) = 'tally_void'
  AND (SELECT bool_and(prosecdef) FROM pg_proc WHERE proname IN ('assert_reference_version', 'reference_version_receipt_held', 'void_invoice')));
SELECT pg_temp.ok('G3 neither seal role bypasses RLS, logs in, or is a superuser; nobody can become one',
  NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname IN ('tally_seal', 'tally_void') AND (rolsuper OR rolbypassrls OR rolcanlogin))
  AND NOT pg_has_role('tally_app', 'tally_void', 'MEMBER') AND NOT pg_has_role('tally_app', 'tally_seal', 'MEMBER')
  AND NOT EXISTS (SELECT 1 FROM pg_auth_members WHERE roleid IN ('tally_seal'::regrole, 'tally_void'::regrole)));
SELECT pg_temp.ok('G4 tally_app: no UPDATE on a header version; UPDATE on the sanctioned columns',
  NOT has_column_privilege('tally_app', 'public.rate_schedules', 'version', 'UPDATE')
  AND NOT has_column_privilege('tally_app', 'public.rate_items', 'version', 'UPDATE')
  AND NOT has_column_privilege('tally_app', 'public.wna_zones', 'version', 'UPDATE')
  AND has_column_privilege('tally_app', 'public.rate_schedules', 'updated_at', 'UPDATE')
  AND has_column_privilege('tally_app', 'public.rate_schedules', 'status', 'UPDATE')
  AND has_column_privilege('tally_app', 'public.rate_schedules', 'archive_reason', 'UPDATE')
  AND has_column_privilege('tally_app', 'public.rate_items', 'status', 'UPDATE')
  AND has_column_privilege('tally_app', 'public.wna_zones', 'updated_at', 'UPDATE'));
SELECT pg_temp.ok('G5 the receipts: no privilege for tally_app, tally_core or PUBLIC',
  NOT has_table_privilege('tally_app', 'public.reference_version_receipts', 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE')
  AND NOT has_table_privilege('tally_core', 'public.reference_version_receipts', 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE')
  AND NOT has_table_privilege('public', 'public.reference_version_receipts', 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE'));
SELECT pg_temp.ok('G6 tally_core executes neither the check nor the receipt test nor the void',
  NOT has_function_privilege('tally_core', 'public.assert_reference_version(text,uuid,integer)', 'EXECUTE')
  AND NOT has_function_privilege('tally_core', 'public.reference_version_receipt_held(text,uuid)', 'EXECUTE')
  AND NOT has_function_privilege('tally_core', 'public.void_invoice(uuid,uuid,text,text,boolean)', 'EXECUTE')
  AND NOT has_function_privilege('public', 'public.assert_reference_version(text,uuid,integer)', 'EXECUTE'));
SELECT pg_temp.ok('G7 no function reads the old caller-settable void setting',
  NOT EXISTS (SELECT 1 FROM pg_proc WHERE pronamespace = 'public'::regnamespace AND strpos(prosrc, 'app.' || 'void_operation') > 0));


-- ===================================================================== S. the version check
SET ROLE tally_app;
-- S1: the raw bump, the old bypass.
SELECT pg_temp.refuses_at('S1 a raw version bump',
  $q$UPDATE public.rate_schedules SET version = version + 1 WHERE id = '00000000-0000-4000-8000-000000002041'$q$, '42501', 'permission denied');
-- S2: a version row with no check, on each of the three tables.
SELECT pg_temp.refuses_at('S2a a schedule version with no check',
  $q$INSERT INTO public.rate_schedule_versions (tenant_id, rate_schedule_id, name, service_type, customer_type, effective_date, change_type)
     VALUES ('00000000-0000-4000-8000-0000000020a1', '00000000-0000-4000-8000-000000002041', 'RS1', 'gas', 'residential', DATE '2026-01-01', 'initial')$q$,
  '23001', 'only after the version check');
SELECT pg_temp.refuses_at('S2b a zone version with no check',
  $q$INSERT INTO public.wna_zone_versions (tenant_id, wna_zone_id, zone_name, effective_date, change_type)
     VALUES ('00000000-0000-4000-8000-0000000020a1', '00000000-0000-4000-8000-000000002061', 'Z1', DATE '2026-01-01', 'initial')$q$,
  '23001', 'only after the version check');
SELECT pg_temp.refuses_at('S2c an item version with no check',
  $q$INSERT INTO public.rate_item_versions (tenant_id, rate_item_id, item_name, service_type, calculation_type, regulatory_class, effective_date, change_type)
     VALUES ('00000000-0000-4000-8000-0000000020a1', '00000000-0000-4000-8000-000000002051', 'IT1', 'gas', 'fixed_monthly', 'regulated', DATE '2026-01-01', 'initial')$q$,
  '23001', 'only after the version check');
-- S3: a lifecycle move with no check; an updated_at touch (the dependency mutex) needs none.
SELECT pg_temp.refuses_at('S3a archiving a zone with no check',
  $q$UPDATE public.wna_zones SET status = 'archived' WHERE id = '00000000-0000-4000-8000-000000002062'$q$, '23001', 'lifecycle change needs the version check');
SELECT pg_temp.admits('S3b an updated_at touch needs no check (the rate_item_dependencies mutex)',
  $q$UPDATE public.rate_schedules SET updated_at = clock_timestamp() WHERE id = '00000000-0000-4000-8000-000000002041'$q$);
-- S4: a stale token; an entity the caller cannot see is P0002, not a retryable 40001.
SELECT pg_temp.refuses_at('S4a a stale token',
  $q$SELECT public.assert_reference_version('rate_schedules', '00000000-0000-4000-8000-000000002041', 7)$q$, '40001', 'modified since it was read');
SELECT pg_temp.refuses_at('S4b another tenant''s schedule',
  $q$SELECT public.assert_reference_version('rate_schedules', '00000000-0000-4000-8000-000000002049', 1)$q$, 'P0002', 'not found');
SELECT pg_temp.refuses_at('S4c an unknown id',
  $q$SELECT public.assert_reference_version('rate_schedules', '00000000-0000-4000-8000-0000000020ff', 1)$q$, 'P0002', 'not found');
SELECT set_config('app.user_id', '', true);
-- An empty app.user_id fails in the RLS helper's cast (fail closed); a
-- session that never set it is in txn-20.sh (T3), as one transaction cannot unset it.
SELECT pg_temp.refuses_at('S4d an empty user',
  $q$SELECT public.assert_reference_version('rate_schedules', '00000000-0000-4000-8000-000000002041', 1)$q$, '22P02', 'invalid input syntax for type uuid');
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000020b1', true);
SELECT pg_temp.ok('S4e a refused check leaves the version and writes no receipt',
  (SELECT version FROM public.rate_schedules WHERE id = '00000000-0000-4000-8000-000000002041') = 1);
-- S5: the check, then the writes: a first version, a close and successor, activation.
SELECT pg_temp.ok('S5a the check returns the bumped version',
  public.assert_reference_version('rate_schedules', '00000000-0000-4000-8000-000000002041', 1) = 2);
SELECT pg_temp.admits('S5b after the check: a first version is admitted',
  $q$INSERT INTO public.rate_schedule_versions (id, tenant_id, rate_schedule_id, name, service_type, customer_type, effective_date, change_type)
     VALUES ('00000000-0000-4000-8000-000000002071', '00000000-0000-4000-8000-0000000020a1', '00000000-0000-4000-8000-000000002041', 'RS1', 'gas', 'residential', DATE '2026-01-01', 'initial')$q$);
SELECT pg_temp.admits('S5c after the check: the activation is admitted',
  $q$UPDATE public.rate_schedules SET status = 'active' WHERE id = '00000000-0000-4000-8000-000000002041'$q$);
-- S6: a second check in the same transaction moves the generation on; the latest receipt admits.
SELECT pg_temp.ok('S6a a second check in the transaction', public.assert_reference_version('rate_schedules', '00000000-0000-4000-8000-000000002041', 2) = 3);
SET CONSTRAINTS ALL DEFERRED;  -- a close and its successor are checked together
SELECT pg_temp.admits('S6b a close after the second check (the latest receipt admits)',
  $q$UPDATE public.rate_schedule_versions SET recorded_until = now(), closed_type = 'superseded', closed_reason = 'battery-20 S6' WHERE id = '00000000-0000-4000-8000-000000002071'$q$);
SELECT pg_temp.admits('S6c its successor after the second check',
  $q$INSERT INTO public.rate_schedule_versions (tenant_id, rate_schedule_id, name, service_type, customer_type, effective_date, change_type, change_reason, supersedes_id)
     VALUES ('00000000-0000-4000-8000-0000000020a1', '00000000-0000-4000-8000-000000002041', 'RS1 corrected', 'gas', 'residential', DATE '2026-01-01', 'correction', 'battery-20 S6', '00000000-0000-4000-8000-000000002071')$q$);
SET CONSTRAINTS ALL IMMEDIATE;
-- S7: a receipt is for one entity: RS1's does not admit RS2, in a multi-row statement or alone.
SELECT pg_temp.refuses_at('S7a a two-entity insert with a receipt for one',
  $q$INSERT INTO public.rate_schedule_versions (tenant_id, rate_schedule_id, name, service_type, customer_type, effective_date, change_type) VALUES
     ('00000000-0000-4000-8000-0000000020a1', '00000000-0000-4000-8000-000000002042', 'RS2', 'gas', 'residential', DATE '2026-01-01', 'initial'),
     ('00000000-0000-4000-8000-0000000020a1', '00000000-0000-4000-8000-000000002041', 'RS1 b', 'gas', 'residential', DATE '2027-01-01', 'succession')$q$,
  '23001', 'only after the version check');
SELECT pg_temp.ok('S7b the refused statement wrote neither row',
  NOT EXISTS (SELECT 1 FROM public.rate_schedule_versions WHERE name IN ('RS1 b', 'RS2')));
SELECT pg_temp.refuses_at('S7c a writable CTE that writes before it checks',
  $q$WITH w AS (INSERT INTO public.rate_schedule_versions (tenant_id, rate_schedule_id, name, service_type, customer_type, effective_date, change_type)
                VALUES ('00000000-0000-4000-8000-0000000020a1', '00000000-0000-4000-8000-000000002042', 'RS2', 'gas', 'residential', DATE '2026-01-01', 'initial') RETURNING 1)
     SELECT public.assert_reference_version('rate_schedules', '00000000-0000-4000-8000-000000002042', 1) FROM w$q$,
  '23001', 'only after the version check');
-- S8: a check inside a savepoint that is rolled back leaves nothing to admit.
SAVEPOINT s8;
SELECT public.assert_reference_version('wna_zones', '00000000-0000-4000-8000-000000002061', 1);
ROLLBACK TO SAVEPOINT s8;
SELECT pg_temp.ok('S8a the rolled-back check took the bump with it',
  (SELECT version FROM public.wna_zones WHERE id = '00000000-0000-4000-8000-000000002061') = 1);
SELECT pg_temp.refuses_at('S8b a zone version after the check was rolled back',
  $q$INSERT INTO public.wna_zone_versions (tenant_id, wna_zone_id, zone_name, effective_date, change_type)
     VALUES ('00000000-0000-4000-8000-0000000020a1', '00000000-0000-4000-8000-000000002061', 'Z1', DATE '2026-01-01', 'initial')$q$,
  '23001', 'only after the version check');
-- S9: a check before a savepoint admits a write inside it (one transaction).
SELECT public.assert_reference_version('wna_zones', '00000000-0000-4000-8000-000000002061', 1);
SAVEPOINT s9;
SELECT pg_temp.admits('S9 a check before a savepoint admits a write inside it',
  $q$INSERT INTO public.wna_zone_versions (tenant_id, wna_zone_id, zone_name, effective_date, change_type)
     VALUES ('00000000-0000-4000-8000-0000000020a1', '00000000-0000-4000-8000-000000002061', 'Z1', DATE '2026-01-01', 'initial')$q$);
RELEASE SAVEPOINT s9;
-- S10: the receipts cannot be forged, read, edited or emptied by the application.
SELECT pg_temp.refuses_at('S10a a forged receipt',
  $q$INSERT INTO public.reference_version_receipts (xact, header_table, entity_id, version, tenant_id, at)
     VALUES (pg_current_xact_id(), 'rate_schedules', '00000000-0000-4000-8000-000000002042', 1, '00000000-0000-4000-8000-0000000020a1', now())$q$, '42501', 'permission denied');
SELECT pg_temp.refuses_at('S10b reading the receipts', $q$SELECT count(*) FROM public.reference_version_receipts$q$, '42501', 'permission denied');
SELECT pg_temp.refuses_at('S10c emptying the receipts', $q$TRUNCATE public.reference_version_receipts$q$, '42501', 'permission denied');
SELECT pg_temp.ok('S10d the receipt test answers false for an entity never checked',
  NOT public.reference_version_receipt_held('rate_schedules', '00000000-0000-4000-8000-000000002042'));
RESET ROLE;
SELECT pg_temp.refuses_at('S10e the owner edits a receipt',
  $q$UPDATE public.reference_version_receipts SET version = 99$q$, '23001', 'append-only');
SELECT pg_temp.refuses_at('S10f the owner deletes a receipt',
  $q$DELETE FROM public.reference_version_receipts$q$, '23001', 'never hard-deleted');
SELECT pg_temp.ok('S10g the database stamps the receipt''s transaction and time',
  (SELECT bool_and(xact = pg_current_xact_id() AND at = now()) FROM public.reference_version_receipts));
-- S11: no role is exempt: the owner (a superuser) meets the guard too.
SELECT pg_temp.refuses_at('S11 the owner writes a version with no check',
  $q$INSERT INTO public.rate_item_versions (tenant_id, rate_item_id, item_name, service_type, calculation_type, regulatory_class, effective_date, change_type)
     VALUES ('00000000-0000-4000-8000-0000000020a1', '00000000-0000-4000-8000-000000002051', 'IT1', 'gas', 'fixed_monthly', 'regulated', DATE '2026-01-01', 'initial')$q$,
  '23001', 'only after the version check');
-- S13: each part of the receipt test binds. The owner plants receipts with
-- triggers off (session_replication_role = replica skips the stamp), each
-- wrong in exactly one part, for entities no check has touched; the
-- application's write must still be refused.
SET LOCAL session_replication_role = replica;
INSERT INTO public.reference_version_receipts (xact, header_table, entity_id, version, tenant_id, at) VALUES
  (pg_current_xact_id(), 'wna_zones', '00000000-0000-4000-8000-000000002062', 1, '00000000-0000-4000-8000-0000000020a1', now() - interval '1 day'),
  ((pg_current_xact_id()::text::bigint + 1000)::text::xid8, 'rate_schedules', '00000000-0000-4000-8000-000000002042', 1, '00000000-0000-4000-8000-0000000020a1', now()),
  (pg_current_xact_id(), 'rate_items', '00000000-0000-4000-8000-000000002051', 6, '00000000-0000-4000-8000-0000000020a1', now());
SET LOCAL session_replication_role = origin;
SET ROLE tally_app;
SELECT pg_temp.refuses_at('S13a a receipt of this transaction''s id but another start time (a restored id)',
  $q$INSERT INTO public.wna_zone_versions (tenant_id, wna_zone_id, zone_name, effective_date, change_type)
     VALUES ('00000000-0000-4000-8000-0000000020a1', '00000000-0000-4000-8000-000000002062', 'Z2', DATE '2026-01-01', 'initial')$q$,
  '23001', 'only after the version check');
SELECT pg_temp.refuses_at('S13b a receipt of this start time but another transaction',
  $q$INSERT INTO public.rate_schedule_versions (tenant_id, rate_schedule_id, name, service_type, customer_type, effective_date, change_type)
     VALUES ('00000000-0000-4000-8000-0000000020a1', '00000000-0000-4000-8000-000000002042', 'RS2', 'gas', 'residential', DATE '2026-01-01', 'initial')$q$,
  '23001', 'only after the version check');
SELECT pg_temp.refuses_at('S13c a receipt of this transaction for another version of the entity',
  $q$INSERT INTO public.rate_item_versions (tenant_id, rate_item_id, item_name, service_type, calculation_type, regulatory_class, effective_date, change_type)
     VALUES ('00000000-0000-4000-8000-0000000020a1', '00000000-0000-4000-8000-000000002051', 'IT1', 'gas', 'fixed_monthly', 'regulated', DATE '2026-01-01', 'initial')$q$,
  '23001', 'only after the version check');
-- Z2 is at version 1; plant a receipt right in every part but the entity.
RESET ROLE;
SET LOCAL session_replication_role = replica;
INSERT INTO public.reference_version_receipts (xact, header_table, entity_id, version, tenant_id, at) VALUES
  (pg_current_xact_id(), 'wna_zones', '00000000-0000-4000-8000-0000000020ff', 1, '00000000-0000-4000-8000-0000000020a1', now());
SET LOCAL session_replication_role = origin;
SET ROLE tally_app;
SELECT pg_temp.refuses_at('S13d a receipt of this transaction and version for another entity',
  $q$UPDATE public.wna_zones SET status = 'archived' WHERE id = '00000000-0000-4000-8000-000000002062'$q$,
  '23001', 'lifecycle change needs the version check');
RESET ROLE;

-- S12: a header is born at version 1; the core cannot bump a token.
SELECT pg_temp.refuses_at('S12a a header born at version 5',
  $q$INSERT INTO public.wna_zones (tenant_id, zone_code, version) VALUES ('00000000-0000-4000-8000-0000000020a1', 'Z5', 5)$q$, '23514', 'created at version 1');
SET ROLE tally_core;
SELECT pg_temp.refuses_at('S12b the core calls the check',
  $q$SELECT public.assert_reference_version('wna_zones', '00000000-0000-4000-8000-000000002062', 1)$q$, '42501', 'permission denied');
RESET ROLE;


-- ===================================================================== V. the void
-- Fixture: three issued bills of tenant 1 (I1 voided by the function, I2 left
-- for the direct-write cases, I3 for a second void), one of tenant 2; a read
-- locked to each of I1 and I2, a charge billed on each. The issued bills have
-- no calculation snapshot: they exist while the snapshot check is deferred.
SET CONSTRAINTS ALL DEFERRED;
INSERT INTO public.invoices (id, tenant_id, invoice_number, customer_id, location_id, invoice_date, billing_period, period_start, period_end, due_date, status, amount_due) VALUES
  ('00000000-0000-4000-8000-000000002001', '00000000-0000-4000-8000-0000000020a1', 'I1', '00000000-0000-4000-8000-0000000020c1', '00000000-0000-4000-8000-0000000020d1', '2026-02-01', '2026-01', '2026-01-01', '2026-01-31', '2026-02-20', 'draft', 100.00),
  ('00000000-0000-4000-8000-000000002002', '00000000-0000-4000-8000-0000000020a1', 'I2', '00000000-0000-4000-8000-0000000020c1', '00000000-0000-4000-8000-0000000020d1', '2026-02-01', '2026-01', '2026-01-01', '2026-01-31', '2026-02-20', 'pending', 50.00),
  ('00000000-0000-4000-8000-000000002003', '00000000-0000-4000-8000-0000000020a1', 'I3', '00000000-0000-4000-8000-0000000020c1', '00000000-0000-4000-8000-0000000020d1', '2026-02-01', '2026-01', '2026-01-01', '2026-01-31', '2026-02-20', 'pending', 20.00),
  ('00000000-0000-4000-8000-000000002009', '00000000-0000-4000-8000-0000000020a2', 'I9', '00000000-0000-4000-8000-0000000020c2', '00000000-0000-4000-8000-0000000020d2', '2026-02-01', '2026-01', '2026-01-01', '2026-01-31', '2026-02-20', 'pending', 70.00);
-- I1 carries a line, so the void meets the line and base guards too.
INSERT INTO public.invoice_line_items (tenant_id, invoice_id, service_type, charge_type, description, amount) VALUES
  ('00000000-0000-4000-8000-0000000020a1', '00000000-0000-4000-8000-000000002001', 'gas', 'base_charge', 'customer charge', 100.00);
UPDATE public.invoices SET status = 'pending' WHERE id = '00000000-0000-4000-8000-000000002001';
INSERT INTO public.meter_readings (id, tenant_id, meter_id, reading_date, reading_value) VALUES
  ('00000000-0000-4000-8000-000000002011', '00000000-0000-4000-8000-0000000020a1', '00000000-0000-4000-8000-0000000020e1', DATE '2026-01-31', 50),
  ('00000000-0000-4000-8000-000000002012', '00000000-0000-4000-8000-0000000020a1', '00000000-0000-4000-8000-0000000020e2', DATE '2026-01-31', 60),
  ('00000000-0000-4000-8000-000000002013', '00000000-0000-4000-8000-0000000020a1', '00000000-0000-4000-8000-0000000020e3', DATE '2026-01-31', 70),
  ('00000000-0000-4000-8000-000000002019', '00000000-0000-4000-8000-0000000020a2', '00000000-0000-4000-8000-0000000020e9', DATE '2026-01-31', 90);
UPDATE public.meter_readings SET validation_status = 'approved', consumption = 10 WHERE id::text LIKE '00000000-0000-4000-8000-00000000201%';
UPDATE public.meter_readings SET validation_status = 'released_to_billing' WHERE id::text LIKE '00000000-0000-4000-8000-00000000201%';
UPDATE public.meter_readings SET validation_status = 'locked', billing_period_locked = true, locked_by_billing_run_id = '00000000-0000-4000-8000-0000000020f1', locked_by_invoice_id = '00000000-0000-4000-8000-000000002001'
 WHERE id = '00000000-0000-4000-8000-000000002011';
UPDATE public.meter_readings SET validation_status = 'locked', billing_period_locked = true, locked_by_billing_run_id = '00000000-0000-4000-8000-0000000020f1', locked_by_invoice_id = '00000000-0000-4000-8000-000000002002'
 WHERE id = '00000000-0000-4000-8000-000000002012';
-- A read locked by a run with no bill pointer (V8).
UPDATE public.meter_readings SET validation_status = 'locked', billing_period_locked = true, locked_by_billing_run_id = '00000000-0000-4000-8000-0000000020f1'
 WHERE id = '00000000-0000-4000-8000-000000002013';
UPDATE public.meter_readings SET validation_status = 'locked', billing_period_locked = true, locked_by_billing_run_id = '00000000-0000-4000-8000-0000000020f9', locked_by_invoice_id = '00000000-0000-4000-8000-000000002009'
 WHERE id = '00000000-0000-4000-8000-000000002019';
INSERT INTO public.adhoc_charges (id, tenant_id, charge_number, customer_id, charge_type, description, amount, regulatory_class, service_type) VALUES
  ('00000000-0000-4000-8000-000000002021', '00000000-0000-4000-8000-0000000020a1', 'A1', '00000000-0000-4000-8000-0000000020c1', 'tap_fee', 'tap', 25.00, 'regulated', 'gas'),
  ('00000000-0000-4000-8000-000000002022', '00000000-0000-4000-8000-0000000020a1', 'A2', '00000000-0000-4000-8000-0000000020c1', 'tap_fee', 'tap', 15.00, 'regulated', 'gas'),
  ('00000000-0000-4000-8000-000000002023', '00000000-0000-4000-8000-0000000020a1', 'A3', '00000000-0000-4000-8000-0000000020c1', 'tap_fee', 'tap', 5.00, 'regulated', 'gas'),
  ('00000000-0000-4000-8000-000000002024', '00000000-0000-4000-8000-0000000020a1', 'A4', '00000000-0000-4000-8000-0000000020c1', 'tap_fee', 'tap', 7.00, 'regulated', 'gas');
UPDATE public.adhoc_charges SET status = 'billed', billed_on_invoice_id = '00000000-0000-4000-8000-000000002001', billed_at = now(), billed_by_billing_run_id = '00000000-0000-4000-8000-0000000020f1'
 WHERE id = '00000000-0000-4000-8000-000000002021';
UPDATE public.adhoc_charges SET status = 'billed', billed_on_invoice_id = '00000000-0000-4000-8000-000000002002', billed_at = now(), billed_by_billing_run_id = '00000000-0000-4000-8000-0000000020f1'
 WHERE id = '00000000-0000-4000-8000-000000002022';

SET ROLE tally_app;
-- V1: the void, end to end, as the application: reads released, charges
-- disposed, the reversal posted, the event logged, the bill voided.
DO $$
DECLARE v jsonb;
BEGIN
  BEGIN
    v := public.void_invoice('00000000-0000-4000-8000-000000002001', '00000000-0000-4000-8000-0000000020b1', 'wrong_rate', 'battery-20 V1', true);
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'FAIL V1: void_invoice() refused with % (%)', SQLSTATE, SQLERRM;
  END;
  IF (v ->> 'reads_released')::int IS DISTINCT FROM 1 OR (v ->> 'charges_auto_reverted')::int IS DISTINCT FROM 1
     OR (v ->> 'reversal_amount')::numeric IS DISTINCT FROM -100.00 THEN
    RAISE EXCEPTION 'FAIL V1: void_invoice() returned %', v;
  END IF;
  RAISE NOTICE 'PASS V1: void_invoice() runs end to end as tally_app through tally_void (%)', v ->> 'invoice_number';
END $$;
SELECT pg_temp.ok('V1b the read is void_released, naming the voided bill',
  (SELECT validation_status = 'void_released' AND locked_by_invoice_id IS NULL AND voided_from_invoice_id = '00000000-0000-4000-8000-000000002001'
     FROM public.meter_readings WHERE id = '00000000-0000-4000-8000-000000002011'));
SELECT pg_temp.ok('V1c the charge is pending again, naming the voided bill, its run kept',
  (SELECT status = 'pending' AND billed_on_invoice_id IS NULL AND billed_at IS NULL AND voided_from_invoice_id = '00000000-0000-4000-8000-000000002001'
          AND billed_by_billing_run_id = '00000000-0000-4000-8000-0000000020f1'
     FROM public.adhoc_charges WHERE id = '00000000-0000-4000-8000-000000002021'));
SELECT pg_temp.ok('V1d the bill is void; one reversal and one event, stamped by the database',
  (SELECT status = 'void' AND voided_at IS NOT NULL FROM public.invoices WHERE id = '00000000-0000-4000-8000-000000002001')
  AND (SELECT count(*) = 1 AND bool_and(amount = -100.00 AND created_at = now()) FROM public.account_ledger WHERE reference_id = '00000000-0000-4000-8000-000000002001' AND transaction_type = 'void_reversal')
  AND (SELECT count(*) = 1 FROM public.invoice_events WHERE invoice_id = '00000000-0000-4000-8000-000000002001' AND event_type = 'voided'));
-- V2: the old setting admits nothing now.
SET LOCAL app.void_operation = 'true';
SELECT pg_temp.refuses_at('V2a a direct release of a locked read, under the old setting',
  $q$UPDATE public.meter_readings SET voided_from_invoice_id = locked_by_invoice_id, locked_by_invoice_id = NULL, validation_status = 'void_released' WHERE id = '00000000-0000-4000-8000-000000002012'$q$,
  'P0001', 'Cannot change validation_status from locked');
SELECT pg_temp.refuses_at('V2b a direct un-billing of a charge, under the old setting',
  $q$UPDATE public.adhoc_charges SET status = 'pending', voided_from_invoice_id = billed_on_invoice_id, billed_on_invoice_id = NULL, billed_at = NULL WHERE id = '00000000-0000-4000-8000-000000002022'$q$,
  '23001', 'undone only by voiding that invoice');
SELECT pg_temp.refuses_at('V2c a direct write of void, under the old setting',
  $q$UPDATE public.invoices SET status = 'void', voided_at = now() WHERE id = '00000000-0000-4000-8000-000000002002'$q$,
  '23001', 'set by void_invoice() only');
SELECT pg_temp.refuses_at('V2d an invoice inserted void by the application',
  $q$INSERT INTO public.invoices (tenant_id, invoice_number, customer_id, location_id, invoice_date, billing_period, period_start, period_end, due_date, status, voided_at)
     VALUES ('00000000-0000-4000-8000-0000000020a1', 'IV', '00000000-0000-4000-8000-0000000020c1', '00000000-0000-4000-8000-0000000020d1', '2026-02-01', '2026-01', '2026-01-01', '2026-01-31', '2026-02-20', 'void', now())$q$,
  '23001', 'set by void_invoice() only');
SET LOCAL app.void_operation = '';
-- V3: after the void returns, the same transaction gets nothing from it.
SELECT pg_temp.refuses_at('V3a after the void, a release of another bill''s read',
  $q$UPDATE public.meter_readings SET voided_from_invoice_id = locked_by_invoice_id, locked_by_invoice_id = NULL, validation_status = 'void_released' WHERE id = '00000000-0000-4000-8000-000000002012'$q$,
  'P0001', 'Cannot change validation_status from locked');
SELECT pg_temp.refuses_at('V3b after the void, a voided_from_invoice_id written on a pending charge',
  $q$UPDATE public.adhoc_charges SET voided_from_invoice_id = '00000000-0000-4000-8000-000000002002' WHERE id = '00000000-0000-4000-8000-000000002023'$q$,
  '23001', 'written only by void_invoice()');
-- V4: a voided bill takes no new reads or charges (the attach guard).
SELECT pg_temp.refuses_at('V4a a charge billed onto the void bill',
  $q$UPDATE public.adhoc_charges SET status = 'billed', billed_on_invoice_id = '00000000-0000-4000-8000-000000002001', billed_at = now() WHERE id = '00000000-0000-4000-8000-000000002023'$q$,
  '23001', 'names a void invoice');
SELECT pg_temp.refuses_at('V4b a read re-locked onto the void bill',
  $q$UPDATE public.meter_readings SET validation_status = 'released_to_billing' WHERE id = '00000000-0000-4000-8000-000000002011';
     UPDATE public.meter_readings SET validation_status = 'locked', locked_by_billing_run_id = '00000000-0000-4000-8000-0000000020f1', locked_by_invoice_id = '00000000-0000-4000-8000-000000002001' WHERE id = '00000000-0000-4000-8000-000000002011'$q$,
  '23001', 'names a void invoice');
SELECT pg_temp.refuses_at('V4d a charge inserted already billed onto the void bill',
  $q$INSERT INTO public.adhoc_charges (tenant_id, charge_number, customer_id, charge_type, description, amount, regulatory_class, service_type, status, billed_on_invoice_id, billed_at)
     VALUES ('00000000-0000-4000-8000-0000000020a1', 'A9', '00000000-0000-4000-8000-0000000020c1', 'tap_fee', 'tap', 1.00, 'regulated', 'gas', 'billed', '00000000-0000-4000-8000-000000002001', now())$q$,
  '23001', 'names a void invoice');
SELECT pg_temp.admits('V4c a charge billed onto a live bill is admitted',
  $q$UPDATE public.adhoc_charges SET status = 'billed', billed_on_invoice_id = '00000000-0000-4000-8000-000000002003', billed_at = now() WHERE id = '00000000-0000-4000-8000-000000002023'$q$);
-- V5: the void, by another tenant's user, by no user, by a user that does not exist: not found, nothing written.
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000020b2', true);
SELECT pg_temp.refuses_at('V5a another tenant''s user voids I2',
  $q$SELECT public.void_invoice('00000000-0000-4000-8000-000000002002', NULL, 'system_error')$q$, 'P0002', 'Invoice not found');
SELECT set_config('app.user_id', '', true);
SELECT pg_temp.refuses_at('V5b an empty user voids I2 (an unset one, Opus B1''s case, is txn-20.sh T3)',
  $q$SELECT public.void_invoice('00000000-0000-4000-8000-000000002002', NULL, 'system_error')$q$, '22P02', 'invalid input syntax for type uuid');
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000020ee', true);
SELECT pg_temp.refuses_at('V5c a user that does not exist voids I2',
  $q$SELECT public.void_invoice('00000000-0000-4000-8000-000000002002', NULL, 'system_error')$q$, 'P0002', 'Invoice not found');
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000020b1', true);
SELECT pg_temp.refuses_at('V5d tenant 1''s user voids tenant 2''s I9',
  $q$SELECT public.void_invoice('00000000-0000-4000-8000-000000002009', NULL, 'system_error')$q$, 'P0002', 'Invoice not found');
RESET ROLE;
SELECT pg_temp.ok('V5e none of them voided a bill or posted a reversal',
  (SELECT status FROM public.invoices WHERE id = '00000000-0000-4000-8000-000000002002') = 'pending'
  AND (SELECT status FROM public.invoices WHERE id = '00000000-0000-4000-8000-000000002009') = 'pending'
  AND NOT EXISTS (SELECT 1 FROM public.account_ledger WHERE reference_id IN ('00000000-0000-4000-8000-000000002002', '00000000-0000-4000-8000-000000002009')));
-- V6: a platform administrator voids another tenant's bill, as the policy admits.
SET ROLE tally_app;
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000020b9', true);
SELECT pg_temp.admits('V6 a platform administrator voids tenant 2''s bill',
  $q$SELECT public.void_invoice('00000000-0000-4000-8000-000000002009', '00000000-0000-4000-8000-0000000020b9', 'system_error', 'battery-20 V6', true)$q$);
SELECT pg_temp.ok('V6b it is void', (SELECT status FROM public.invoices WHERE id = '00000000-0000-4000-8000-000000002009') = 'void');
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000020b1', true);
-- V7: a second void of a void bill is refused before any side effect.
SELECT pg_temp.refuses_at('V7 a second void of I1',
  $q$SELECT public.void_invoice('00000000-0000-4000-8000-000000002001', NULL, 'system_error')$q$, 'P0001', 'is not voidable');
RESET ROLE;
-- V8-V11: as tally_void itself (the owner session takes the role to write as
-- the void does), only the void's exact writes pass.
SET ROLE tally_void;
SELECT pg_temp.refuses_at('V8 the void role releases a read that names no bill',
  $q$UPDATE public.meter_readings SET validation_status = 'void_released' WHERE id = '00000000-0000-4000-8000-000000002013'$q$,
  'P0001', 'Cannot change validation_status from locked');
SELECT pg_temp.refuses_at('V9a the void role un-bills a charge but keeps billed_at',
  $q$UPDATE public.adhoc_charges SET status = 'pending', voided_from_invoice_id = billed_on_invoice_id, billed_on_invoice_id = NULL WHERE id = '00000000-0000-4000-8000-000000002022'$q$,
  '23001', 'a void clears billed_on_invoice_id');
SELECT pg_temp.refuses_at('V9b the void role points a charge at another bill',
  $q$UPDATE public.adhoc_charges SET status = 'pending', voided_from_invoice_id = '00000000-0000-4000-8000-000000002003', billed_on_invoice_id = NULL, billed_at = NULL WHERE id = '00000000-0000-4000-8000-000000002022'$q$,
  '23001', 'a void clears billed_on_invoice_id');
SELECT pg_temp.refuses_at('V9c the void role moves a charge''s run',
  $q$UPDATE public.adhoc_charges SET status = 'void_pending_rebill', voided_from_invoice_id = billed_on_invoice_id, billed_on_invoice_id = NULL, billed_at = NULL, billed_by_billing_run_id = NULL WHERE id = '00000000-0000-4000-8000-000000002022'$q$,
  '23001', 'a void clears billed_on_invoice_id');
SELECT pg_temp.refuses_at('V10 the void role edits a billed charge''s amount',
  $q$UPDATE public.adhoc_charges SET amount = 1 WHERE id = '00000000-0000-4000-8000-000000002022'$q$, '23001', 'identity is immutable');
SELECT pg_temp.refuses_at('V11 the void role inserts an invoice born void',
  $q$INSERT INTO public.invoices (tenant_id, invoice_number, customer_id, location_id, invoice_date, billing_period, period_start, period_end, due_date, status, voided_at)
     VALUES ('00000000-0000-4000-8000-0000000020a1', 'IW', '00000000-0000-4000-8000-0000000020c1', '00000000-0000-4000-8000-0000000020d1', '2026-02-01', '2026-01', '2026-01-01', '2026-01-31', '2026-02-20', 'void', now())$q$,
  '42501', 'permission denied');
RESET ROLE;
-- V12: a superuser's history load may still store a void bill.
SELECT pg_temp.admits('V12 a superuser''s history load stores a void bill',
  $q$INSERT INTO public.invoices (tenant_id, invoice_number, customer_id, location_id, invoice_date, billing_period, period_start, period_end, due_date, status, voided_at)
     VALUES ('00000000-0000-4000-8000-0000000020a1', 'IH', '00000000-0000-4000-8000-0000000020c1', '00000000-0000-4000-8000-0000000020d1', '2025-02-01', '2025-01', '2025-01-01', '2025-01-31', '2025-02-20', 'void', now())$q$);

DO $$ BEGIN
  PERFORM public.assert_seal_role_invariants();
  RAISE NOTICE 'PASS G8: the invariants still hold at the end';
END $$;
DO $$ BEGIN RAISE NOTICE 'battery-20: complete'; END $$;
ROLLBACK;
