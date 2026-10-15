-- ============================================================================
-- BATTERY v5.4.2-21 — wave 1 built: retention, bill-line arithmetic, lineage,
-- the void's reversal, identity (2026-10-14)
-- Run: psql -U tally -d <db-with-patch> -v ON_ERROR_STOP=1 -f battery-21.sql
-- One transaction, rolled back. Fixtures as the owner; every guard the
-- application meets is exercised as tally_app under app.user_id.
-- Each row names its requirement in
-- application/wave1-build-2026-10-14/source-inventory-21.md.
--
--   D  retention (CI-014)            L  the custom labels in use
--   K  rate dependencies retired     A  bill-line arithmetic at issue (CI-016)
--   G  lineage (CI-017)              V  the void's reversal
--   U  identity (R1)                 N  the -20 notes
-- What one transaction cannot show (two sessions; READ COMMITTED against an
-- older snapshot) is in races/labels-21.sh.
-- ============================================================================
BEGIN;

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
CREATE FUNCTION pg_temp.ok(p_label text, p_cond boolean) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  IF p_cond IS DISTINCT FROM true THEN RAISE EXCEPTION 'FAIL %', p_label; END IF;
  RAISE NOTICE 'PASS %', p_label;
END $$;
CREATE FUNCTION pg_temp.admits(p_label text, p_sql text) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE p_sql;
  RAISE NOTICE 'PASS %', p_label;
EXCEPTION WHEN OTHERS THEN
  RAISE EXCEPTION 'FAIL %: refused with % (%)', p_label, SQLSTATE, SQLERRM;
END $$;
-- issue(): move a draft into an issued status and run ONLY the arithmetic
-- check now (the snapshot and surcharge checks stay deferred, and are
-- discarded with the subtransaction). p_state NULL means it must pass.
CREATE FUNCTION pg_temp.issue(p_label text, p_inv uuid, p_state text, p_guard text) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE v_state text; v_msg text;
BEGIN
  BEGIN
    UPDATE public.invoices SET status = 'pending' WHERE id = p_inv;
    SET CONSTRAINTS enforce_invoice_line_arithmetic IMMEDIATE;
    RAISE EXCEPTION USING ERRCODE = 'P0099', MESSAGE = 'issued';
  EXCEPTION WHEN OTHERS THEN
    v_state := SQLSTATE; v_msg := SQLERRM;
  END;
  SET CONSTRAINTS enforce_invoice_line_arithmetic DEFERRED;
  IF p_state IS NULL THEN
    IF v_state = 'P0099' THEN RAISE NOTICE 'PASS %', p_label; RETURN; END IF;
    RAISE EXCEPTION 'FAIL %: refused with % (%)', p_label, v_state, v_msg;
  END IF;
  IF v_state = p_state AND strpos(v_msg, p_guard) > 0 THEN
    RAISE NOTICE 'PASS %: refused (%)', p_label, left(v_msg, 160);
    RETURN;
  END IF;
  RAISE EXCEPTION 'FAIL %: got % (%), expected % with %', p_label, v_state, v_msg, p_state, p_guard;
END $$;
GRANT EXECUTE ON FUNCTION pg_temp.refuses_at(text, text, text, text), pg_temp.ok(text, boolean),
                          pg_temp.admits(text, text), pg_temp.issue(text, uuid, text, text) TO tally_app;

-- ------------------------------------------------------------------ fixtures
INSERT INTO public.tenants (id, name, slug) VALUES
  ('00000000-0000-4000-8000-0000000021a1', 'T1 City Gas', 'bat21-t1'),
  ('00000000-0000-4000-8000-0000000021a2', 'T2 Gasco', 'bat21-t2');
INSERT INTO public.users (id, tenant_id, display_name, email, role, is_active, cognito_sub) VALUES
  ('00000000-0000-4000-8000-0000000021b1', '00000000-0000-4000-8000-0000000021a1', 'Op1', 'op1@bat21.test', 'operator', true, 'sub-op1'),
  ('00000000-0000-4000-8000-0000000021b2', '00000000-0000-4000-8000-0000000021a2', 'Op2', 'op2@bat21.test', 'operator', true, 'sub-op2'),
  ('00000000-0000-4000-8000-0000000021b3', '00000000-0000-4000-8000-0000000021a1', 'Svc', 'svc@bat21.test', 'operator', true, NULL),
  ('00000000-0000-4000-8000-0000000021b8', '00000000-0000-4000-8000-0000000021a1', 'Gone', 'gone@bat21.test', 'operator', false, 'sub-gone'),
  ('00000000-0000-4000-8000-0000000021ba', '00000000-0000-4000-8000-0000000021a1', 'OldAdmin', 'oldadmin@bat21.test', 'platform_admin', false, NULL);
INSERT INTO public.customers (id, tenant_id, customer_number, customer_type, metadata) VALUES
  ('00000000-0000-4000-8000-0000000021c1', '00000000-0000-4000-8000-0000000021a1', 'B21-C1', 'residential', '{"acct_color": "blue"}'),
  ('00000000-0000-4000-8000-0000000021c2', '00000000-0000-4000-8000-0000000021a1', 'B21-C2', 'residential', '{}'),
  ('00000000-0000-4000-8000-0000000021c9', '00000000-0000-4000-8000-0000000021a2', 'B21-C9', 'residential', '{"t2_only": 1}');
INSERT INTO public.service_locations (id, tenant_id, customer_id, location_number, address_line1, city, state, zip, location_type) VALUES
  ('00000000-0000-4000-8000-0000000021d1', '00000000-0000-4000-8000-0000000021a1', '00000000-0000-4000-8000-0000000021c1', 'L1', '1 Main', 'Austin', 'TX', '78701', 'kiosk'),
  ('00000000-0000-4000-8000-0000000021d9', '00000000-0000-4000-8000-0000000021a2', '00000000-0000-4000-8000-0000000021c9', 'L9', '9 Main', 'Austin', 'TX', '78709', 'shed');
INSERT INTO public.rate_schedules (id, tenant_id, code) VALUES
  ('00000000-0000-4000-8000-000000002141', '00000000-0000-4000-8000-0000000021a1', 'RS21');
INSERT INTO public.rate_items (id, tenant_id, item_code) VALUES
  ('00000000-0000-4000-8000-000000002151', '00000000-0000-4000-8000-0000000021a1', 'A'),
  ('00000000-0000-4000-8000-000000002152', '00000000-0000-4000-8000-0000000021a1', 'B'),
  ('00000000-0000-4000-8000-000000002153', '00000000-0000-4000-8000-0000000021a1', 'PU'),
  ('00000000-0000-4000-8000-000000002154', '00000000-0000-4000-8000-0000000021a1', 'TU'),
  ('00000000-0000-4000-8000-000000002155', '00000000-0000-4000-8000-0000000021a1', 'FX');
INSERT INTO public.customer_credits (id, tenant_id, customer_id, origin_type, original_amount, remaining_amount) VALUES
  ('00000000-0000-4000-8000-000000002161', '00000000-0000-4000-8000-0000000021a1', '00000000-0000-4000-8000-0000000021c1', 'overpayment', 40, 40),
  ('00000000-0000-4000-8000-000000002162', '00000000-0000-4000-8000-0000000021a1', '00000000-0000-4000-8000-0000000021c1', 'goodwill', 5, 5),
  ('00000000-0000-4000-8000-000000002163', '00000000-0000-4000-8000-0000000021a1', '00000000-0000-4000-8000-0000000021c2', 'overpayment', 9, 9),
  ('00000000-0000-4000-8000-000000002169', '00000000-0000-4000-8000-0000000021a2', '00000000-0000-4000-8000-0000000021c9', 'overpayment', 7, 7);
INSERT INTO public.payments (id, tenant_id, payment_number, customer_id, payment_date, amount, payment_method, effective_date, effective_date_method) VALUES
  ('00000000-0000-4000-8000-000000002181', '00000000-0000-4000-8000-0000000021a1', 'B21-P1', '00000000-0000-4000-8000-0000000021c1', DATE '2026-02-05', 40, 'check', DATE '2026-02-05', 'other');
INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount) VALUES
  ('00000000-0000-4000-8000-000000002171', '00000000-0000-4000-8000-0000000021a1', '00000000-0000-4000-8000-0000000021c1', DATE '2026-02-01', 'charge', 'a T1 charge', 30.00),
  ('00000000-0000-4000-8000-000000002179', '00000000-0000-4000-8000-0000000021a2', '00000000-0000-4000-8000-0000000021c9', DATE '2026-02-01', 'charge', 'a T2 charge', 70.00);
-- Rate item versions: PU per unit, TU tiered, FX fixed (a version is written
-- after the version check, in this transaction).
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000021b1', true);
SELECT public.assert_reference_version('rate_items', i, 1)
  FROM unnest(ARRAY['00000000-0000-4000-8000-000000002153', '00000000-0000-4000-8000-000000002154', '00000000-0000-4000-8000-000000002155']::uuid[]) i;
INSERT INTO public.rate_item_versions (tenant_id, rate_item_id, item_name, service_type, calculation_type, regulatory_class, effective_date, change_type, tier_config) VALUES
  ('00000000-0000-4000-8000-0000000021a1', '00000000-0000-4000-8000-000000002153', 'Per unit', 'gas', 'per_unit_usage', 'regulated', DATE '2026-01-01', 'initial', NULL),
  ('00000000-0000-4000-8000-0000000021a1', '00000000-0000-4000-8000-000000002154', 'Tiered', 'gas', 'tiered_usage', 'regulated', DATE '2026-01-01', 'initial', '{"tiers": []}'),
  ('00000000-0000-4000-8000-0000000021a1', '00000000-0000-4000-8000-000000002155', 'Fixed', 'gas', 'fixed_monthly', 'regulated', DATE '2026-01-01', 'initial', NULL);

-- draft(): a draft bill of tenant 1 for January.
CREATE FUNCTION pg_temp.draft(p_id uuid, p_num text) RETURNS void LANGUAGE sql AS $$
  INSERT INTO public.invoices (id, tenant_id, invoice_number, customer_id, location_id, invoice_date, billing_period, period_start, period_end, due_date, amount_due)
  VALUES (p_id, '00000000-0000-4000-8000-0000000021a1', p_num, '00000000-0000-4000-8000-0000000021c1', '00000000-0000-4000-8000-0000000021d1',
          DATE '2026-02-01', '2026-01', DATE '2026-01-01', DATE '2026-01-31', DATE '2026-02-20', 30.00);
$$;
-- line(): one line on a bill, the arithmetic columns given as jsonb.
CREATE FUNCTION pg_temp.line(p_inv uuid, p_service text, p_kind text, p_cols jsonb) RETURNS void LANGUAGE sql AS $$
  INSERT INTO public.invoice_line_items (tenant_id, invoice_id, line_order, service_type, charge_type, description, amount, rate_item_id,
         usage_quantity, usage_unit, rate, coverage_start, coverage_end, days_covered, days_in_period, partial_period_policy_applied,
         gas_meter_factor, gas_ccf_used, gas_therms_billed, gas_commodity_rate)
  SELECT '00000000-0000-4000-8000-0000000021a1', p_inv, coalesce((SELECT max(line_order) + 1 FROM public.invoice_line_items WHERE invoice_id = p_inv), 0),
         p_service, p_kind, p_kind || ' line', 10.00, (p_cols ->> 'rate_item_id')::uuid,
         (p_cols ->> 'usage_quantity')::numeric, p_cols ->> 'usage_unit', (p_cols ->> 'rate')::numeric,
         (p_cols ->> 'coverage_start')::date, (p_cols ->> 'coverage_end')::date, (p_cols ->> 'days_covered')::int, (p_cols ->> 'days_in_period')::int,
         p_cols ->> 'partial_period_policy_applied',
         (p_cols ->> 'gas_meter_factor')::numeric, (p_cols ->> 'gas_ccf_used')::numeric, (p_cols ->> 'gas_therms_billed')::numeric, (p_cols ->> 'gas_commodity_rate')::numeric;
$$;
GRANT EXECUTE ON FUNCTION pg_temp.draft(uuid, text), pg_temp.line(uuid, text, text, jsonb) TO tally_app;

-- ====================================================================== D. retention
INSERT INTO public.alerts (id, tenant_id, alert_type, title, message) VALUES
  ('00000000-0000-4000-8000-0000000021e1', '00000000-0000-4000-8000-0000000021a1', 'system', 'hello', 'a T1 alert');
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['ai_sessions', 'ai_suggestions', 'ai_tool_calls',
                           'billing_cycles', 'read_routes', 'jurisdictions', 'communities', 'deposit_utility_categories',
                           'bill_messages', 'auto_pay_settings', 'tenant_sequences',
                           'read_cycle_meters', 'alerts', 'service_location_acquisitions',
                           'rate_item_dependencies', 'pga_monitoring_settings'] LOOP
    PERFORM pg_temp.refuses_at('D1 the owner empties ' || t, format('TRUNCATE public.%I CASCADE', t), '23001', 'never hard-deleted');
    IF has_table_privilege('tally_app', ('public.' || t)::regclass, 'DELETE') OR has_table_privilege('tally_app', ('public.' || t)::regclass, 'TRUNCATE') THEN
      RAISE EXCEPTION 'FAIL D2: tally_app may still delete from %', t;
    END IF;
  END LOOP;
  RAISE NOTICE 'PASS D2: tally_app holds neither DELETE nor TRUNCATE on the sixteen';
END $$;
SELECT pg_temp.refuses_at('D1b the owner deletes an alert row',
  $q$DELETE FROM public.alerts WHERE id = '00000000-0000-4000-8000-0000000021e1'$q$, '23001', 'never hard-deleted');
SET ROLE tally_app;
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000021b1', true);
SELECT pg_temp.refuses_at('D2b the application deletes an alert',
  $q$DELETE FROM public.alerts WHERE id = '00000000-0000-4000-8000-0000000021e1'$q$, '42501', 'permission denied');
RESET ROLE;
SELECT pg_temp.ok('D3 the twelve stay deletable by the application',
  (SELECT bool_and(has_table_privilege('tally_app', ('public.' || t)::regclass, 'DELETE'))
     FROM unnest(ARRAY['invoices', 'invoice_line_items', 'invoice_events', 'invoice_calculation_snapshots', 'invoice_line_item_bases',
                       'invoice_snapshot_references', 'import_staging', 'import_column_mappings', 'import_mapping_templates',
                       'materialized_view_refresh_log', 'custom_field_definitions', 'custom_location_types']) t));
SELECT public.assert_no_hard_delete_invariants();
DO $$ BEGIN RAISE NOTICE 'PASS D4: the retention invariant holds'; END $$;

-- ====================================================================== L. the labels
INSERT INTO public.custom_field_definitions (id, tenant_id, entity_type, field_key, field_label, field_type) VALUES
  ('00000000-0000-4000-8000-0000000021f1', '00000000-0000-4000-8000-0000000021a1', 'customers', 'acct_color', 'Colour', 'text'),
  ('00000000-0000-4000-8000-0000000021f2', '00000000-0000-4000-8000-0000000021a1', 'meter_readings', 'read_note', 'Note', 'text'),
  ('00000000-0000-4000-8000-0000000021f3', '00000000-0000-4000-8000-0000000021a1', 'customers', 't2_only', 'T2 key', 'text'),
  ('00000000-0000-4000-8000-0000000021f9', '00000000-0000-4000-8000-0000000021a2', 'customers', 't2_only', 'T2 key', 'text');
INSERT INTO public.custom_location_types (id, tenant_id, type_key, type_label) VALUES
  ('00000000-0000-4000-8000-0000000021f4', '00000000-0000-4000-8000-0000000021a1', 'kiosk', 'Kiosk'),
  ('00000000-0000-4000-8000-0000000021f5', '00000000-0000-4000-8000-0000000021a1', 'shed', 'Shed');
SET ROLE tally_app;
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000021b1', true);
SELECT pg_temp.refuses_at('L1 a field label in use on a customer',
  $q$DELETE FROM public.custom_field_definitions WHERE id = '00000000-0000-4000-8000-0000000021f1'$q$, '23001', 'is in use');
SELECT pg_temp.admits('L1b a label of an entity with no metadata is deletable',
  $q$DELETE FROM public.custom_field_definitions WHERE id = '00000000-0000-4000-8000-0000000021f2'$q$);
SELECT pg_temp.admits('L1c only this tenant''s rows count: the key is used by tenant 2 only',
  $q$DELETE FROM public.custom_field_definitions WHERE id = '00000000-0000-4000-8000-0000000021f3'$q$);
UPDATE public.customers SET metadata = '{}' WHERE id = '00000000-0000-4000-8000-0000000021c1';
SELECT pg_temp.admits('L1d cleared from the rows, the label is deletable',
  $q$DELETE FROM public.custom_field_definitions WHERE id = '00000000-0000-4000-8000-0000000021f1'$q$);
SELECT pg_temp.refuses_at('L2 a location type in use',
  $q$DELETE FROM public.custom_location_types WHERE id = '00000000-0000-4000-8000-0000000021f4'$q$, '23001', 'is in use');
SELECT pg_temp.admits('L2b a location type used only by tenant 2 is deletable',
  $q$DELETE FROM public.custom_location_types WHERE id = '00000000-0000-4000-8000-0000000021f5'$q$);
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000021b2', true);
DELETE FROM public.custom_location_types WHERE id = '00000000-0000-4000-8000-0000000021f4';
RESET ROLE;
SELECT pg_temp.ok('L4 another tenant''s caller cannot reach the label (RLS)',
  EXISTS (SELECT 1 FROM public.custom_location_types WHERE id = '00000000-0000-4000-8000-0000000021f4'));
SELECT pg_temp.refuses_at('L1e the owner meets the in-use guard too',
  $q$DELETE FROM public.custom_field_definitions WHERE id = '00000000-0000-4000-8000-0000000021f9'$q$, '23001', 'is in use');
-- The owner sees every tenant: the guard itself must keep to the label's tenant.
INSERT INTO public.custom_field_definitions (id, tenant_id, entity_type, field_key, field_label, field_type) VALUES
  ('00000000-0000-4000-8000-0000000021f6', '00000000-0000-4000-8000-0000000021a1', 'customers', 't2_only', 'T2 key', 'text');
INSERT INTO public.custom_location_types (id, tenant_id, type_key, type_label) VALUES
  ('00000000-0000-4000-8000-0000000021f7', '00000000-0000-4000-8000-0000000021a1', 'shed', 'Shed');
SELECT pg_temp.admits('L1f the owner deletes a field label used only by another tenant',
  $q$DELETE FROM public.custom_field_definitions WHERE id = '00000000-0000-4000-8000-0000000021f6'$q$);
SELECT pg_temp.admits('L2c the owner deletes a location type used only by another tenant',
  $q$DELETE FROM public.custom_location_types WHERE id = '00000000-0000-4000-8000-0000000021f7'$q$);
SELECT pg_temp.refuses_at('L5 the owner empties the labels',
  $q$TRUNCATE public.custom_location_types$q$, '23001', 'never hard-deleted');
SELECT pg_temp.ok('L3 the in-use check holds SHARE on the entity table until commit',
  EXISTS (SELECT 1 FROM pg_locks l WHERE l.relation = 'public.customers'::regclass AND l.mode = 'ShareLock' AND l.pid = pg_backend_pid()));

-- ====================================================================== K. dependencies retired
SET ROLE tally_app;
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000021b1', true);
INSERT INTO public.rate_item_dependencies (id, tenant_id, rate_schedule_id, dependent_rate_item_id, base_rate_item_id) VALUES
  ('00000000-0000-4000-8000-000000002191', '00000000-0000-4000-8000-0000000021a1', '00000000-0000-4000-8000-000000002141',
   '00000000-0000-4000-8000-000000002151', '00000000-0000-4000-8000-000000002152');
SELECT pg_temp.refuses_at('K2 a dependency born retired',
  $q$INSERT INTO public.rate_item_dependencies (tenant_id, rate_schedule_id, dependent_rate_item_id, base_rate_item_id, retired_reason)
     VALUES ('00000000-0000-4000-8000-0000000021a1', '00000000-0000-4000-8000-000000002141', '00000000-0000-4000-8000-000000002152', '00000000-0000-4000-8000-000000002153', 'why')$q$,
  '23514', 'born live');
SELECT pg_temp.refuses_at('K3a a live dependency edited',
  $q$UPDATE public.rate_item_dependencies SET notes = 'edited' WHERE id = '00000000-0000-4000-8000-000000002191'$q$, '23001', 'write-once');
SELECT pg_temp.refuses_at('K3b an update that is not a retirement',
  $q$UPDATE public.rate_item_dependencies SET retired_by = '00000000-0000-4000-8000-0000000021b1' WHERE id = '00000000-0000-4000-8000-000000002191'$q$, '23001', 'only change');
SELECT pg_temp.refuses_at('K1 a retirement with a blank reason',
  $q$UPDATE public.rate_item_dependencies SET retired_reason = '   ' WHERE id = '00000000-0000-4000-8000-000000002191'$q$, '23514', 'rate_item_dependencies_retired_reason_check');
SELECT pg_temp.refuses_at('K-del the application deletes a dependency',
  $q$DELETE FROM public.rate_item_dependencies WHERE id = '00000000-0000-4000-8000-000000002191'$q$, '42501', 'permission denied');
RESET ROLE;
-- (Back-date the header past its own updated_at trigger, so K5a can see the bump.)
SET LOCAL session_replication_role = replica;
UPDATE public.rate_schedules SET updated_at = '2000-01-01' WHERE id = '00000000-0000-4000-8000-000000002141';
SET LOCAL session_replication_role = origin;
SELECT pg_temp.ok('K5-fixture the header is back-dated', (SELECT updated_at < now() FROM public.rate_schedules WHERE id = '00000000-0000-4000-8000-000000002141'));
SET ROLE tally_app;
UPDATE public.rate_item_dependencies SET retired_reason = 'battery-21 K3', retired_at = '2000-01-01', retired_by = '00000000-0000-4000-8000-0000000021b1'
 WHERE id = '00000000-0000-4000-8000-000000002191';
SELECT pg_temp.ok('K3c a retirement is stamped by the database, whatever is supplied',
  (SELECT retired_at = now() FROM public.rate_item_dependencies WHERE id = '00000000-0000-4000-8000-000000002191'));
SELECT pg_temp.ok('K5a a retirement takes the schedule header (the mutex)',
  (SELECT updated_at = now() FROM public.rate_schedules WHERE id = '00000000-0000-4000-8000-000000002141'));
SELECT pg_temp.refuses_at('K3d a retirement is permanent',
  $q$UPDATE public.rate_item_dependencies SET retired_at = NULL, retired_reason = NULL WHERE id = '00000000-0000-4000-8000-000000002191'$q$, '23001', 'permanent');
SELECT pg_temp.admits('K4 the retired dependency is added again (live rows are unique)',
  $q$INSERT INTO public.rate_item_dependencies (id, tenant_id, rate_schedule_id, dependent_rate_item_id, base_rate_item_id)
     VALUES ('00000000-0000-4000-8000-000000002192', '00000000-0000-4000-8000-0000000021a1', '00000000-0000-4000-8000-000000002141', '00000000-0000-4000-8000-000000002151', '00000000-0000-4000-8000-000000002152')$q$);
SELECT pg_temp.refuses_at('K4b a second live copy',
  $q$INSERT INTO public.rate_item_dependencies (tenant_id, rate_schedule_id, dependent_rate_item_id, base_rate_item_id)
     VALUES ('00000000-0000-4000-8000-0000000021a1', '00000000-0000-4000-8000-000000002141', '00000000-0000-4000-8000-000000002151', '00000000-0000-4000-8000-000000002152')$q$,
  '23505', 'rate_item_dependencies_live_key');
UPDATE public.rate_item_dependencies SET retired_reason = 'battery-21 K5' WHERE id = '00000000-0000-4000-8000-000000002192';
SELECT pg_temp.admits('K5 with A on B retired, B on A is no cycle',
  $q$INSERT INTO public.rate_item_dependencies (tenant_id, rate_schedule_id, dependent_rate_item_id, base_rate_item_id)
     VALUES ('00000000-0000-4000-8000-0000000021a1', '00000000-0000-4000-8000-000000002141', '00000000-0000-4000-8000-000000002152', '00000000-0000-4000-8000-000000002151')$q$);
SELECT pg_temp.refuses_at('K5b a live cycle is still refused (A on B while B on A)',
  $q$INSERT INTO public.rate_item_dependencies (tenant_id, rate_schedule_id, dependent_rate_item_id, base_rate_item_id)
     VALUES ('00000000-0000-4000-8000-0000000021a1', '00000000-0000-4000-8000-000000002141', '00000000-0000-4000-8000-000000002151', '00000000-0000-4000-8000-000000002152')$q$,
  '23514', 'closes a cycle');
RESET ROLE;

-- ====================================================================== A. arithmetic at issue
-- Each case: a draft with one line, then the move to pending as tally_app.
SET ROLE tally_app;
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000021b1', true);
DO $$
DECLARE
  c record;
  n int := 0;
  v_id uuid;
BEGIN
  FOR c IN SELECT * FROM (VALUES
    ('A2a a usage line with no rate',                 'water', 'usage_charge', '{"usage_quantity": 5, "usage_unit": "kgal"}'::jsonb,                                   'missing rate'),
    ('A2b a gas usage line with no therms',           'gas',   'usage_charge', '{"usage_quantity": 5, "usage_unit": "ccf", "rate": 1, "gas_meter_factor": 1.02, "gas_ccf_used": 5, "gas_commodity_rate": 0.4}', 'missing gas_therms_billed'),
    ('A2c a water usage line, complete',              'water', 'usage_charge', '{"usage_quantity": 5, "usage_unit": "kgal", "rate": 2}',                               NULL),
    ('A2d a usage line with a blank unit',            'water', 'usage_charge', '{"usage_quantity": 5, "usage_unit": "  ", "rate": 2}',                                 'missing usage_unit'),
    ('A2e a usage line with no quantity',             'water', 'usage_charge', '{"usage_unit": "kgal", "rate": 2}',                                                    'missing usage_quantity'),
    ('A2f a gas usage line, complete',                'gas',   'usage_charge', '{"usage_quantity": 5, "usage_unit": "ccf", "rate": 1, "gas_meter_factor": 1.02, "gas_ccf_used": 5, "gas_therms_billed": 5.1, "gas_commodity_rate": 0.4}', NULL),
    ('A6 rate and commodity rate are two figures',   'gas',   'usage_charge', '{"usage_quantity": 5, "usage_unit": "ccf", "rate": 9, "gas_meter_factor": 1, "gas_ccf_used": 5, "gas_therms_billed": 5, "gas_commodity_rate": 0.4}', NULL),
    ('A3a a base line with no rate',                  'gas',   'base_charge',  '{}'::jsonb,                                                                             'missing rate'),
    ('A3b a base line, half its coverage',            'gas',   'base_charge',  '{"rate": 10, "coverage_start": "2026-01-10"}',                                         'all or none'),
    ('A3c a base line, full period (no coverage)',    'gas',   'base_charge',  '{"rate": 10}',                                                                          NULL),
    ('A3d a partial-period base line, complete',      'gas',   'base_charge',  '{"rate": 10, "coverage_start": "2026-01-10", "coverage_end": "2026-01-31", "days_covered": 22, "days_in_period": 31, "partial_period_policy_applied": "prorated"}', NULL),
    ('A4a a surcharge with no rate item',             'gas',   'surcharge',    '{}'::jsonb,                                                                             'missing rate_item_id'),
    ('A4b a fixed surcharge carries its amount only', 'gas',   'surcharge',    '{"rate_item_id": "00000000-0000-4000-8000-000000002155"}',                              NULL),
    ('A4c a per-unit surcharge with no quantity',     'water', 'surcharge',    '{"rate_item_id": "00000000-0000-4000-8000-000000002153", "usage_unit": "kgal", "rate": 0.1}', 'missing usage_quantity'),
    ('A4d a tiered surcharge with no rate',           'water', 'surcharge',    '{"rate_item_id": "00000000-0000-4000-8000-000000002154", "usage_quantity": 5, "usage_unit": "kgal"}', 'missing rate'),
    ('A4e a gas per-unit surcharge needs the gas figures', 'gas', 'surcharge', '{"rate_item_id": "00000000-0000-4000-8000-000000002153", "usage_quantity": 5, "usage_unit": "ccf", "rate": 0.1}', 'missing gas_meter_factor'),
    ('A4f a per-unit surcharge, complete',            'water', 'surcharge',    '{"rate_item_id": "00000000-0000-4000-8000-000000002153", "usage_quantity": 5, "usage_unit": "kgal", "rate": 0.1}', NULL),
    ('A5 a late fee carries its amount only',         'gas',   'late_fee',     '{}'::jsonb,                                                                             NULL)
  ) AS x(label, service, kind, cols, guard) LOOP
    n := n + 1;
    v_id := md5('b21-a' || n)::uuid;
    PERFORM pg_temp.draft(v_id, 'B21-A' || n);
    PERFORM pg_temp.line(v_id, c.service, c.kind, c.cols);
    PERFORM pg_temp.issue(c.label, v_id, CASE WHEN c.guard IS NULL THEN NULL ELSE '23514' END, c.guard);
  END LOOP;
END $$;
-- A1: the gate. A draft edited stays a draft: no refusal; a held bill
-- voided is a discard (V2 below); an incomplete line on an issued bill
-- cannot appear (A-4 freezes it).
SELECT pg_temp.draft('00000000-0000-4000-8000-0000000021aa', 'B21-GATE');
SELECT pg_temp.line('00000000-0000-4000-8000-0000000021aa', 'gas', 'base_charge', '{}');
SELECT pg_temp.admits('A1a a draft with an incomplete line is no issuance',
  $q$UPDATE public.invoices SET amount_due = 31 WHERE id = '00000000-0000-4000-8000-0000000021aa'$q$);
SET CONSTRAINTS enforce_invoice_line_arithmetic IMMEDIATE;
SET CONSTRAINTS enforce_invoice_line_arithmetic DEFERRED;
DO $$ BEGIN RAISE NOTICE 'PASS A1b: the queued check of a draft edit fires and passes'; END $$;
-- A1c: two lines, the second incomplete: the whole bill is refused.
SELECT pg_temp.draft('00000000-0000-4000-8000-0000000021ab', 'B21-TWO');
SELECT pg_temp.line('00000000-0000-4000-8000-0000000021ab', 'gas', 'base_charge', '{"rate": 10}');
SELECT pg_temp.line('00000000-0000-4000-8000-0000000021ab', 'gas', 'usage_charge', '{"usage_quantity": 5}');
SELECT pg_temp.issue('A1c any one incomplete line refuses the bill', '00000000-0000-4000-8000-0000000021ab', '23514', 'line 1 (usage_charge');
RESET ROLE;

-- ====================================================================== G. lineage
SET ROLE tally_app;
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000021b1', true);
SELECT pg_temp.refuses_at('G1 a correction that names no bill',
  $q$INSERT INTO public.invoices (tenant_id, invoice_number, customer_id, location_id, invoice_type, invoice_date, billing_period, period_start, period_end, due_date)
     VALUES ('00000000-0000-4000-8000-0000000021a1', 'B21-G1', '00000000-0000-4000-8000-0000000021c1', '00000000-0000-4000-8000-0000000021d1', 'correction',
             DATE '2026-02-01', '2026-01', DATE '2026-01-01', DATE '2026-01-31', DATE '2026-02-20')$q$,
  '23514', 'invoices_correction_names_replaced_check');
SELECT pg_temp.refuses_at('G2a a void_reversal that names nothing',
  $q$INSERT INTO public.account_ledger (tenant_id, customer_id, transaction_date, transaction_type, description, amount, reversal_reason)
     VALUES ('00000000-0000-4000-8000-0000000021a1', '00000000-0000-4000-8000-0000000021c1', DATE '2026-02-02', 'void_reversal', 'x', -30, 'wrong_rate')$q$,
  '23514', 'account_ledger_void_reversal_lineage_check');
SELECT pg_temp.refuses_at('G2b a void_reversal with a blank reason',
  $q$INSERT INTO public.account_ledger (tenant_id, customer_id, transaction_date, transaction_type, description, amount, reverses_ledger_entry_id, reversal_reason)
     VALUES ('00000000-0000-4000-8000-0000000021a1', '00000000-0000-4000-8000-0000000021c1', DATE '2026-02-02', 'void_reversal', 'x', -30, '00000000-0000-4000-8000-000000002171', ' - ')$q$,
  '23514', 'account_ledger_void_reversal_lineage_check');
SELECT pg_temp.refuses_at('G2c a void_reversal with no reason',
  $q$INSERT INTO public.account_ledger (tenant_id, customer_id, transaction_date, transaction_type, description, amount, reverses_ledger_entry_id)
     VALUES ('00000000-0000-4000-8000-0000000021a1', '00000000-0000-4000-8000-0000000021c1', DATE '2026-02-02', 'void_reversal', 'x', -30, '00000000-0000-4000-8000-000000002171')$q$,
  '23514', 'account_ledger_void_reversal_lineage_check');
SELECT pg_temp.refuses_at('G3 a reversal of another tenant''s entry',
  $q$INSERT INTO public.account_ledger (tenant_id, customer_id, transaction_date, transaction_type, description, amount, reverses_ledger_entry_id, reversal_reason)
     VALUES ('00000000-0000-4000-8000-0000000021a1', '00000000-0000-4000-8000-0000000021c1', DATE '2026-02-02', 'void_reversal', 'x', -70, '00000000-0000-4000-8000-000000002179', 'wrong_rate')$q$,
  '23503', 'account_ledger_reverses_ledger_entry_fkey');
SELECT pg_temp.admits('G2d a void_reversal that names its entry and a reason',
  $q$INSERT INTO public.account_ledger (tenant_id, customer_id, transaction_date, transaction_type, description, amount, reverses_ledger_entry_id, reversal_reason)
     VALUES ('00000000-0000-4000-8000-0000000021a1', '00000000-0000-4000-8000-0000000021c1', DATE '2026-02-02', 'void_reversal', 'x', -30, '00000000-0000-4000-8000-000000002171', 'wrong_rate')$q$);
-- Refunds.
SELECT pg_temp.refuses_at('G4a a refund that names no source',
  $q$INSERT INTO public.payments (tenant_id, payment_number, customer_id, payment_date, amount, payment_method, effective_date, effective_date_method)
     VALUES ('00000000-0000-4000-8000-0000000021a1', 'B21-R1', '00000000-0000-4000-8000-0000000021c1', DATE '2026-02-10', -5, 'refund', DATE '2026-02-10', 'other')$q$,
  '23514', 'payments_refund_names_one_source_check');
SELECT pg_temp.refuses_at('G4b a refund that names both sources',
  $q$INSERT INTO public.payments (tenant_id, payment_number, customer_id, payment_date, amount, payment_method, effective_date, effective_date_method, refunds_payment_id, refunds_customer_credit_id)
     VALUES ('00000000-0000-4000-8000-0000000021a1', 'B21-R1', '00000000-0000-4000-8000-0000000021c1', DATE '2026-02-10', -5, 'refund', DATE '2026-02-10', 'other',
             '00000000-0000-4000-8000-000000002181', '00000000-0000-4000-8000-000000002161')$q$,
  '23514', 'payments_refund_names_one_source_check');
SELECT pg_temp.refuses_at('G4c a refund of another customer''s credit',
  $q$INSERT INTO public.payments (tenant_id, payment_number, customer_id, payment_date, amount, payment_method, effective_date, effective_date_method, refunds_customer_credit_id)
     VALUES ('00000000-0000-4000-8000-0000000021a1', 'B21-R1', '00000000-0000-4000-8000-0000000021c1', DATE '2026-02-10', -5, 'refund', DATE '2026-02-10', 'other',
             '00000000-0000-4000-8000-000000002163')$q$,
  '23503', 'payments_refunds_customer_credit_fkey');
SELECT pg_temp.refuses_at('G4d a credit link on a payment that is not a refund',
  $q$INSERT INTO public.payments (tenant_id, payment_number, customer_id, payment_date, amount, payment_method, effective_date, effective_date_method, refunds_customer_credit_id)
     VALUES ('00000000-0000-4000-8000-0000000021a1', 'B21-R1', '00000000-0000-4000-8000-0000000021c1', DATE '2026-02-10', 5, 'check', DATE '2026-02-10', 'other',
             '00000000-0000-4000-8000-000000002161')$q$,
  '23514', 'payments_refund_is_refund_check');
SELECT pg_temp.admits('G4e a refund of a customer credit',
  $q$INSERT INTO public.payments (id, tenant_id, payment_number, customer_id, payment_date, amount, payment_method, effective_date, effective_date_method, refunds_customer_credit_id)
     VALUES ('00000000-0000-4000-8000-000000002182', '00000000-0000-4000-8000-0000000021a1', 'B21-R2', '00000000-0000-4000-8000-0000000021c1', DATE '2026-02-10', -5, 'refund', DATE '2026-02-10', 'other',
             '00000000-0000-4000-8000-000000002161')$q$);
SELECT pg_temp.admits('G4f a refund of a payment',
  $q$INSERT INTO public.payments (tenant_id, payment_number, customer_id, payment_date, amount, payment_method, effective_date, effective_date_method, refunds_payment_id)
     VALUES ('00000000-0000-4000-8000-0000000021a1', 'B21-R3', '00000000-0000-4000-8000-0000000021c1', DATE '2026-02-10', -5, 'refund', DATE '2026-02-10', 'other',
             '00000000-0000-4000-8000-000000002181')$q$);
SELECT pg_temp.refuses_at('G4g a posted refund''s credit link is frozen',
  $q$UPDATE public.payments SET refunds_customer_credit_id = '00000000-0000-4000-8000-000000002162' WHERE id = '00000000-0000-4000-8000-000000002182'$q$,
  '23001', 'refunds_customer_credit_id');
SELECT pg_temp.refuses_at('G6 a charge born with a void''s pointer',
  $q$INSERT INTO public.adhoc_charges (tenant_id, charge_number, customer_id, charge_type, description, amount, regulatory_class, service_type, voided_from_invoice_id)
     VALUES ('00000000-0000-4000-8000-0000000021a1', 'B21-X1', '00000000-0000-4000-8000-0000000021c1', 'tap_fee', 'tap', 5, 'regulated', 'gas', '00000000-0000-4000-8000-0000000021aa')$q$,
  '23514', 'only void_invoice() writes it');
RESET ROLE;
SELECT pg_temp.admits('G6b a superuser''s history load may carry it',
  $q$INSERT INTO public.adhoc_charges (tenant_id, charge_number, customer_id, charge_type, description, amount, regulatory_class, service_type, voided_from_invoice_id)
     VALUES ('00000000-0000-4000-8000-0000000021a1', 'B21-X2', '00000000-0000-4000-8000-0000000021c1', 'tap_fee', 'tap', 5, 'regulated', 'gas', '00000000-0000-4000-8000-0000000021aa')$q$);
SELECT pg_temp.ok('G7 every lineage column is indexed',
  (SELECT count(*) = 5 FROM pg_indexes WHERE schemaname = 'public' AND indexname IN
     ('idx_invoices_replaces_invoice', 'idx_account_ledger_reverses', 'idx_payments_refunds_payment', 'idx_payments_nsf_original', 'idx_payments_refunds_credit')));

-- ====================================================================== V. the void's reversal
-- VP posted with its charge; VN posted with none; VH held, never posted.
SELECT pg_temp.draft('00000000-0000-4000-8000-0000000021c5', 'B21-VP');
SELECT pg_temp.draft('00000000-0000-4000-8000-0000000021c6', 'B21-VN');
UPDATE public.invoices SET status = 'pending' WHERE id IN ('00000000-0000-4000-8000-0000000021c5', '00000000-0000-4000-8000-0000000021c6');
SELECT pg_temp.draft('00000000-0000-4000-8000-0000000021c7', 'B21-VH');
UPDATE public.invoices SET status = 'held', hold_reason = 'battery-21' WHERE id = '00000000-0000-4000-8000-0000000021c7';
-- The held bill carries a line without its arithmetic: a discard is no issuance (A1).
SELECT pg_temp.line('00000000-0000-4000-8000-0000000021c7', 'gas', 'base_charge', '{}');
INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reference_type, reference_id) VALUES
  ('00000000-0000-4000-8000-000000002175', '00000000-0000-4000-8000-0000000021a1', '00000000-0000-4000-8000-0000000021c1', DATE '2026-02-01', 'charge', 'B21-VP', 30.00, 'invoice', '00000000-0000-4000-8000-0000000021c5');
SELECT pg_temp.ok('V0 the fixture: two posted bills and one never posted',
  (SELECT count(*) FILTER (WHERE first_issued_at IS NOT NULL) = 2 AND count(*) FILTER (WHERE first_issued_at IS NULL) = 1
     FROM public.invoices WHERE id IN ('00000000-0000-4000-8000-0000000021c5', '00000000-0000-4000-8000-0000000021c6', '00000000-0000-4000-8000-0000000021c7')));
SET ROLE tally_app;
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000021b1', true);
DO $$
DECLARE v jsonb;
BEGIN
  v := public.void_invoice('00000000-0000-4000-8000-0000000021c5', '00000000-0000-4000-8000-0000000021b1', 'wrong_rate', 'battery-21 V1', true);
  IF v ->> 'reverses_ledger_entry_id' IS DISTINCT FROM '00000000-0000-4000-8000-000000002175'
     OR (v ->> 'reversal_amount')::numeric IS DISTINCT FROM -30.00 OR v ->> 'ledger_entry_id' IS NULL THEN
    RAISE EXCEPTION 'FAIL V1: void_invoice() returned %', v;
  END IF;
  RAISE NOTICE 'PASS V1: a posted bill''s void reverses its charge and names it';
END $$;
SELECT pg_temp.ok('V1b exactly one reversal, naming the charge, with the reason',
  (SELECT count(*) = 1 AND bool_and(reverses_ledger_entry_id = '00000000-0000-4000-8000-000000002175' AND reversal_reason LIKE 'wrong_rate%')
     FROM public.account_ledger WHERE reference_id = '00000000-0000-4000-8000-0000000021c5' AND transaction_type = 'void_reversal'));
SELECT pg_temp.refuses_at('V1c a posted bill with no charge on the ledger',
  $q$SELECT public.void_invoice('00000000-0000-4000-8000-0000000021c6', '00000000-0000-4000-8000-0000000021b1', 'wrong_rate', 'battery-21 V1c', true)$q$,
  'P0002', 'has no charge entry');
SELECT pg_temp.ok('V1d the refused void wrote nothing',
  (SELECT status = 'pending' FROM public.invoices WHERE id = '00000000-0000-4000-8000-0000000021c6')
  AND NOT EXISTS (SELECT 1 FROM public.account_ledger WHERE reference_id = '00000000-0000-4000-8000-0000000021c6'));
DO $$
DECLARE v jsonb;
BEGIN
  BEGIN
    v := public.void_invoice('00000000-0000-4000-8000-0000000021c7', '00000000-0000-4000-8000-0000000021b1', 'wrong_rate', 'battery-21 V2', false);
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'FAIL V2: void_invoice() refused with % (%)', SQLSTATE, SQLERRM;
  END;
  IF v ->> 'ledger_entry_id' IS NOT NULL OR v ->> 'reverses_ledger_entry_id' IS NOT NULL OR v ->> 'reversal_amount' IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL V2: void_invoice() returned %', v;
  END IF;
  RAISE NOTICE 'PASS V2: a held bill''s void is a discard: no ledger entry';
END $$;
SELECT pg_temp.ok('V2b the held bill is void, with no ledger row, and its event records no reversal',
  (SELECT status = 'void' FROM public.invoices WHERE id = '00000000-0000-4000-8000-0000000021c7')
  AND NOT EXISTS (SELECT 1 FROM public.account_ledger WHERE reference_id = '00000000-0000-4000-8000-0000000021c7')
  AND (SELECT bool_and(metadata -> 'reversal_amount' = 'null'::jsonb) FROM public.invoice_events
        WHERE invoice_id = '00000000-0000-4000-8000-0000000021c7' AND event_type = 'voided'));
-- V2c: every queued arithmetic check fires now; the held bill's discard
-- (with its incomplete line) is not an issuance.
DO $$ BEGIN
  SET CONSTRAINTS enforce_invoice_line_arithmetic IMMEDIATE;
  SET CONSTRAINTS enforce_invoice_line_arithmetic DEFERRED;
  RAISE NOTICE 'PASS V2c: voiding a held bill with an incomplete line is no issuance (A1)';
EXCEPTION WHEN OTHERS THEN
  RAISE EXCEPTION 'FAIL V2c: % (%)', SQLSTATE, SQLERRM;
END $$;
RESET ROLE;
SELECT public.assert_seal_role_invariants();
DO $$ BEGIN RAISE NOTICE 'PASS V3: the void''s seal invariant holds after the replacement'; END $$;

-- ====================================================================== U. identity
SET ROLE tally_app;
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000021b1', true);
SELECT pg_temp.refuses_at('U1a a Cognito identity bound twice',
  $q$UPDATE public.users SET cognito_sub = 'sub-op1' WHERE id = '00000000-0000-4000-8000-0000000021b3'$q$, '23505', 'users_cognito_sub_key');
SELECT pg_temp.refuses_at('U1b a subject that is not one',
  $q$UPDATE public.users SET cognito_sub = 'two words' WHERE id = '00000000-0000-4000-8000-0000000021b3'$q$, '23514', 'users_cognito_sub_format_check');
SELECT pg_temp.admits('U1c a user is bound once',
  $q$UPDATE public.users SET cognito_sub = '3f1c9a7e-0000-4000-8000-00000000abcd' WHERE id = '00000000-0000-4000-8000-0000000021b3'$q$);
SELECT pg_temp.refuses_at('U1d a binding is never changed',
  $q$UPDATE public.users SET cognito_sub = 'sub-other' WHERE id = '00000000-0000-4000-8000-0000000021b1'$q$, '23001', 'write-once');
SELECT pg_temp.refuses_at('U1e a binding is never cleared',
  $q$UPDATE public.users SET cognito_sub = NULL WHERE id = '00000000-0000-4000-8000-0000000021b1'$q$, '23001', 'write-once');
SELECT pg_temp.ok('U2a an active user has a tenant and sees its customers',
  public.get_user_tenant_id() = '00000000-0000-4000-8000-0000000021a1' AND EXISTS (SELECT 1 FROM public.customers));
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000021b8', true);
SELECT pg_temp.ok('U2b a deactivated user has no tenant and sees no customer',
  public.get_user_tenant_id() IS NULL AND NOT EXISTS (SELECT 1 FROM public.customers));
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000021ba', true);
SELECT pg_temp.ok('U2c a deactivated platform administrator is none',
  NOT public.is_platform_admin() AND NOT EXISTS (SELECT 1 FROM public.customers));
RESET ROLE;

-- ====================================================================== N. the -20 notes
SELECT pg_temp.ok('N1 PUBLIC holds no TEMP on this database',
  NOT has_database_privilege('public', current_database(), 'TEMP'));
GRANT SELECT ON public.alerts TO PUBLIC;
SELECT pg_temp.refuses_at('N2 the PUBLIC clause names a relation',
  $q$SELECT public.assert_seal_role_invariants()$q$, '0LP01', 'privilege on relation alerts');
REVOKE SELECT ON public.alerts FROM PUBLIC;
SELECT pg_temp.ok('N3 the invariant says its trigger strings are PostgreSQL 16''s rendering',
  strpos(pg_get_functiondef('public.assert_seal_role_invariants()'::regprocedure), 'PostgreSQL 16''s rendering') > 0);

DO $$ BEGIN RAISE NOTICE 'battery-21: complete'; END $$;
ROLLBACK;
