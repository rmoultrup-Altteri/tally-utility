-- ============================================================================
-- BATTERY v5.4.2-13 — A-2 at parity (2026-09-28)
-- Run: psql -U tally -d <db-with-patch> -v ON_ERROR_STOP=1 -f battery-13.sql
-- One transaction, rolled back. Negative cases inside DO blocks that check
-- the SQLSTATE. Written as tally_app except fixtures and the owner-level
-- checks a group names. TWO tenants.
--
-- What it proves: the schema REPRESENTS the backbilling invariant for any
-- state (group Z seeds a fictional state, ZZ, with rules Texas does not have,
-- using no DDL) and PROTECTS the correction records. It does not test law —
-- the database no longer evaluates it (application/a2-rules-for-the-core.md).
-- The r7 battery that did is in r7/ as scenario material for the core.
--
--   A  tenant settings and supervisors        (sections 1-2)
--   B  deployment history is evidence         (section 4)
--   C  the law tables are platform-held       (section 5)
--   Z  a second state fits without DDL        (section 5)
--   D  the reissue cause                      (section 6)
--   E  the case record                        (section 8)
--   F  evaluations and evidence               (section 9)
--   G  approvals                              (section 10)
--   H  freeze, unfreeze, withdraw             (section 8)
--   I  holds                                  (section 11)
--   J  a frozen case's tests                  (section 13)
--   K  surfaces and tenancy                   (sections 14, 16)
-- The "evidence only in its evaluation's transaction" guard needs two
-- transactions: evidence-txn-13.sh.
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


-- ============================================================ A. settings
SET LOCAL app.user_id = '00000000-0000-4000-8000-0000000013b1';
SET ROLE tally_app;
DO $$ BEGIN
  UPDATE public.tenants SET regulatory_class_mode = 'explicit_class' WHERE id = '00000000-0000-4000-8000-0000000013a1';
  RAISE EXCEPTION 'FAIL A1: a tenant session moved regulatory_class_mode';
EXCEPTION WHEN insufficient_privilege THEN
  RAISE NOTICE 'PASS A1: a tenant session cannot move regulatory_class_mode (platform-set, CCK-14)'; END $$;
DO $$ BEGIN
  UPDATE public.tenants SET backbilling_adverse_limit_months = 4 WHERE id = '00000000-0000-4000-8000-0000000013a1';
  IF NOT EXISTS (SELECT 1 FROM public.tenant_configuration_history
                  WHERE tenant_id = '00000000-0000-4000-8000-0000000013a1'
                    AND config_key = 'backbilling_adverse_limit_months' AND new_value = '4'::jsonb) THEN
    RAISE EXCEPTION 'FAIL A2: the adverse limit change was not recorded';
  END IF;
  RAISE NOTICE 'PASS A2: the utility sets its own adverse limit (R-37(d)) and the change is recorded';
END $$;
DO $$ BEGIN
  UPDATE public.users SET role = 'tenant_admin' WHERE id = '00000000-0000-4000-8000-0000000013b1';
  RAISE EXCEPTION 'FAIL A3: an operator promoted itself';
EXCEPTION WHEN insufficient_privilege THEN
  RAISE NOTICE 'PASS A3: an operator cannot make itself a supervisor'; END $$;
RESET ROLE;
SET LOCAL app.user_id = '00000000-0000-4000-8000-0000000013b9';
SET ROLE tally_app;
DO $$ BEGIN
  UPDATE public.tenants SET regulatory_class_mode = 'explicit_class' WHERE id = '00000000-0000-4000-8000-0000000013a1';
  UPDATE public.tenants SET regulatory_class_mode = 'all_non_residential_protected' WHERE id = '00000000-0000-4000-8000-0000000013a1';
  RAISE NOTICE 'PASS A4: a platform administrator may move regulatory_class_mode';
END $$;
RESET ROLE;


-- ============================================================ B. deployments
SET LOCAL app.user_id = '00000000-0000-4000-8000-0000000013b1';
SET ROLE tally_app;
DO $$ BEGIN
  INSERT INTO public.meter_deployments (tenant_id, meter_id, location_id, install_date, removal_date, removal_reason)
  VALUES ('00000000-0000-4000-8000-0000000013a1', '00000000-0000-4000-8000-0000000013e2', '00000000-0000-4000-8000-0000000013d6',
          DATE '2023-01-01', DATE '2023-06-01', 'upgrade_size');
  RAISE EXCEPTION 'FAIL B1: the application inserted a deployment already removed';
EXCEPTION WHEN restrict_violation THEN
  RAISE NOTICE 'PASS B1: a deployment entered already removed (a history load) is refused to the application'; END $$;
DO $$ BEGIN
  UPDATE public.meter_deployments SET install_date = DATE '2025-06-01' WHERE id = pg_temp.id('dep_e2');
  RAISE EXCEPTION 'FAIL B2: install_date moved';
EXCEPTION WHEN restrict_violation THEN
  RAISE NOTICE 'PASS B2: a deployment''s install date never changes'; END $$;
DO $$ BEGIN
  UPDATE public.meter_deployments SET removal_date = DATE '2026-05-01', removal_reason = 'damage' WHERE id = pg_temp.id('dep_e8');
  IF (SELECT removal_recorded_at FROM public.meter_deployments WHERE id = pg_temp.id('dep_e8')) IS NULL THEN
    RAISE EXCEPTION 'FAIL B3: removal_recorded_at not stamped';
  END IF;
  RAISE NOTICE 'PASS B3: the moment a removal is recorded is stamped by the database';
END $$;
DO $$ BEGIN
  UPDATE public.meter_deployments SET removal_date = DATE '2026-04-01' WHERE id = pg_temp.id('dep_e8');
  RAISE EXCEPTION 'FAIL B4: a removal date was rewritten';
EXCEPTION WHEN restrict_violation THEN
  RAISE NOTICE 'PASS B4: a removal is written once'; END $$;
RESET ROLE;


-- ============================================================ C. law tables
SET LOCAL app.user_id = '00000000-0000-4000-8000-0000000013b1';
SET ROLE tally_app;
DO $$ DECLARE n int; BEGIN
  SELECT count(*) INTO n FROM public.backbilling_rules WHERE state_code = 'TX' AND service_type = 'gas';
  IF n <> 16 THEN RAISE EXCEPTION 'FAIL C1: expected 16 TX gas rules, read %', n; END IF;
  RAISE NOTICE 'PASS C1: the application reads the law (16 TX gas rows: 8 causes x 2 classes)';
END $$;
DO $$ BEGIN
  INSERT INTO public.backbilling_causes (cause_code, description) VALUES ('x_cause', 'x');
  RAISE EXCEPTION 'FAIL C2a: the application wrote a cause';
EXCEPTION WHEN insufficient_privilege THEN NULL; END $$;
DO $$ BEGIN
  INSERT INTO public.backbilling_customer_classes (state_code, service_type, class_code, description, source_note)
  VALUES ('TX', 'gas', 'x_class', 'x', 'x');
  RAISE EXCEPTION 'FAIL C2b: the application wrote a class';
EXCEPTION WHEN insufficient_privilege THEN NULL; END $$;
DO $$ BEGIN
  UPDATE public.backbilling_rules SET enforce_scope = 'uncapped' WHERE id = pg_temp.r('protected', 'meter_error');
  RAISE EXCEPTION 'FAIL C2c: the application edited a rule';
EXCEPTION WHEN insufficient_privilege THEN NULL; END $$;
DO $$ BEGIN
  DELETE FROM public.backbilling_rule_window_terms WHERE rule_id = pg_temp.r('protected', 'meter_error');
  RAISE EXCEPTION 'FAIL C2d: the application deleted window terms';
EXCEPTION WHEN insufficient_privilege THEN
  RAISE NOTICE 'PASS C2: the application cannot write any of the four law tables'; END $$;
RESET ROLE;
-- Owner-level: law rows are closed, never edited or deleted.
DO $$ BEGIN
  UPDATE public.backbilling_rules SET enforce_scope = 'uncapped' WHERE id = pg_temp.r('protected', 'meter_error');
  RAISE EXCEPTION 'FAIL C3: the owner edited a law row';
EXCEPTION WHEN restrict_violation THEN
  RAISE NOTICE 'PASS C3: not even the owner edits a law row (evaluations cite it)'; END $$;
DO $$ BEGIN
  DELETE FROM public.backbilling_rules WHERE id = pg_temp.r('unprotected', 'unbilled_service');
  RAISE EXCEPTION 'FAIL C4: the owner deleted a law row';
EXCEPTION WHEN restrict_violation THEN
  RAISE NOTICE 'PASS C4: a law row is never deleted'; END $$;
DO $$ BEGIN
  UPDATE public.backbilling_rule_window_terms SET months = 12
   WHERE rule_id = pg_temp.r('protected', 'meter_error') AND term_kind = 'months_before_anchor';
  RAISE EXCEPTION 'FAIL C5: a window term changed';
EXCEPTION WHEN restrict_violation THEN
  RAISE NOTICE 'PASS C5: window terms never change'; END $$;
DO $$ BEGIN
  UPDATE public.backbilling_rules SET effective_to = DATE '2030-01-01', source_note = 'edited'
   WHERE id = pg_temp.r('protected', 'crossed_meters');
  RAISE EXCEPTION 'FAIL C6: a close carried another change';
EXCEPTION WHEN restrict_violation THEN
  RAISE NOTICE 'PASS C6: closing a row changes nothing else'; END $$;
DO $$ BEGIN
  INSERT INTO public.backbilling_rules (state_code, service_type, customer_class, cause, anchor_basis, qualifying_test_outcomes, favourable_duty,
     adverse_straddle, favourable_straddle, delivery_path, requires_supervisor_evidence, units_invariant,
     enforce_scope, effective_from, source_note)
  VALUES ('TX', 'gas', 'protected', 'meter_error', 'test_date', ARRAY['fast','slow'], 'permitted', 'include_whole', 'include_whole',
          'adjustment', false, false, 'uncapped', DATE '2020-01-01', 'overlapping row');
  RAISE EXCEPTION 'FAIL C7: an overlapping rule row was accepted';
EXCEPTION WHEN exclusion_violation THEN
  RAISE NOTICE 'PASS C7: two rows for one key cannot be in force on the same day'; END $$;
DO $$ BEGIN
  INSERT INTO public.backbilling_rules (state_code, service_type, customer_class, cause, anchor_basis, qualifying_test_outcomes, favourable_duty,
     adverse_straddle, favourable_straddle, delivery_path, requires_supervisor_evidence, units_invariant,
     enforce_scope, effective_from, source_note)
  VALUES ('TX', 'water', 'protected', 'meter_error', 'test_date', ARRAY['fast','slow'], 'permitted', 'include_whole', 'include_whole',
          'adjustment', false, false, 'uncapped', DATE '2020-01-01', 'TX water has no such class seeded');
  RAISE EXCEPTION 'FAIL C8: a rule for a class the state does not have was accepted';
EXCEPTION WHEN foreign_key_violation THEN
  RAISE NOTICE 'PASS C8: a rule''s class must be one of that state''s classes for that service'; END $$;
DO $$ BEGIN
  INSERT INTO public.backbilling_rules (state_code, service_type, customer_class, cause, anchor_basis, qualifying_test_outcomes, favourable_duty,
     adverse_straddle, favourable_straddle, delivery_path, requires_supervisor_evidence, units_invariant,
     enforce_scope, effective_from, source_note)
  VALUES ('TX', 'gas', 'protected', 'no_such_cause', 'test_date', ARRAY['fast'], 'permitted', 'include_whole', 'include_whole',
          'adjustment', false, false, 'uncapped', DATE '2020-01-01', 'x');
  RAISE EXCEPTION 'FAIL C9: a rule for an unknown cause was accepted';
EXCEPTION WHEN foreign_key_violation THEN
  RAISE NOTICE 'PASS C9: a rule''s cause must be a known cause'; END $$;
DO $$ BEGIN
  INSERT INTO public.backbilling_rules (state_code, service_type, customer_class, cause, anchor_basis, qualifying_test_outcomes, favourable_duty,
     adverse_straddle, favourable_straddle, delivery_path, requires_supervisor_evidence, units_invariant,
     enforce_scope, effective_from, source_note)
  VALUES ('TX', 'gas', 'protected', 'meter_error', 'test_date', ARRAY['fast','slow'], 'permitted', 'include_whole', 'include_whole',
          'adjustment', false, false, 'uncapped', DATE '1990-01-01', '   ');
  RAISE EXCEPTION 'FAIL C10: an uncited rule was accepted';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'PASS C10: every law row cites its source'; END $$;
DO $$ BEGIN
  INSERT INTO public.backbilling_rules (state_code, service_type, customer_class, cause, anchor_basis, qualifying_test_outcomes, favourable_duty,
     adverse_straddle, favourable_straddle, delivery_path, requires_supervisor_evidence, units_invariant,
     enforce_scope, enforce_months, effective_from, source_note)
  VALUES ('TX', 'gas', 'protected', 'meter_error', 'test_date', ARRAY['fast','slow'], 'permitted', 'include_whole', 'include_whole',
          'adjustment', false, false, 'never', 6, DATE '1990-01-01', 'stray month count');
  RAISE EXCEPTION 'FAIL C11: a month count under a non-month scope was accepted';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'PASS C11: a month count appears exactly under enforce_scope = months'; END $$;
DO $$ BEGIN
  INSERT INTO public.backbilling_rule_window_terms (rule_id, direction, term_kind, months)
  VALUES (pg_temp.r('protected', 'crossed_meters'), 'adverse', 'last_test_any_outcome', 6);
  RAISE EXCEPTION 'FAIL C12: a month count on a non-month term was accepted';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'PASS C12: a month count appears exactly on months_before_anchor terms'; END $$;
DO $$ BEGIN
  INSERT INTO public.backbilling_rules (state_code, service_type, customer_class, cause, anchor_basis, qualifying_test_outcomes, favourable_duty,
     adverse_straddle, favourable_straddle, delivery_path, requires_supervisor_evidence, units_invariant,
     enforce_scope, effective_from, source_note)
  VALUES ('TX', 'gas', 'protected', 'meter_error', 'test_date', NULL, 'permitted', 'include_whole', 'include_whole',
          'adjustment', false, false, 'uncapped', DATE '1990-01-01', 'test-anchored with no outcomes');
  RAISE EXCEPTION 'FAIL C14: a test-anchored rule named no qualifying outcomes';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'PASS C14: a test-anchored rule names the test outcomes that make a finding its cause (R-39); a discovery rule names none'; END $$;
DO $$ DECLARE t text; BEGIN
  SELECT string_agg(direction || ':' || term_kind || coalesce(' ' || months, ''), ', ' ORDER BY direction, term_kind) INTO t
    FROM public.backbilling_rule_window_terms WHERE rule_id = pg_temp.r('protected', 'meter_error');
  IF t IS DISTINCT FROM 'adverse:deployment_start, adverse:last_test_any_outcome, adverse:months_before_anchor 6, favourable:deployment_start, favourable:last_test_any_outcome, favourable:months_before_anchor 6' THEN
    RAISE EXCEPTION 'FAIL C13: meter_error terms are %', t;
  END IF;
  IF (SELECT favourable_duty FROM public.backbilling_rules WHERE id = pg_temp.r('protected', 'meter_error')) <> 'mandatory'
     OR (SELECT adverse_straddle FROM public.backbilling_rules WHERE id = pg_temp.r('protected', 'meter_error')) <> 'forfeit_whole'
     OR NOT (SELECT units_invariant FROM public.backbilling_rules WHERE id = pg_temp.r('protected', 'rate_misapplication'))
     OR NOT (SELECT requires_supervisor_evidence FROM public.backbilling_rules WHERE id = pg_temp.r('protected', 'tampering_bypass'))
     OR (SELECT enforce_months FROM public.backbilling_rules WHERE id = pg_temp.r('protected', 'rate_misapplication')) <> 6
     OR (SELECT qualifying_test_outcomes FROM public.backbilling_rules WHERE id = pg_temp.r('protected', 'meter_error')) <> ARRAY['fast','slow']
     OR (SELECT qualifying_test_outcomes FROM public.backbilling_rules WHERE id = pg_temp.r('protected', 'non_registering_meter')) <> ARRAY['non_registering'] THEN
    RAISE EXCEPTION 'FAIL C13: a Texas attribute is not as ruled';
  END IF;
  RAISE NOTICE 'PASS C13: Texas meter_error qualifies on fast/slow, non_registering_meter on non_registering; meter_error = the later of 6 months, the last test and the deployment start, both directions; refund mandatory; straddle forfeited whole; rate misapplication keeps units, enforce 6 months; tampering gated';
END $$;


-- ============================================================ Z. a second state
-- ZZ is fictional and deliberately unlike Texas: three classes, a new cause,
-- a 12-month adverse window bounded by half the time since the last test, a
-- 36-month refund reach, proration of straddling periods, a refund duty on a
-- cause Texas leaves permitted, and a conditional enforcement. No DDL.
DO $$ DECLARE v_rule uuid; BEGIN
  INSERT INTO public.backbilling_causes (cause_code, description)
  VALUES ('customer_culpable_conduct', 'ZZ: the customer''s own conduct caused the under-billing.');
  INSERT INTO public.backbilling_customer_classes (state_code, service_type, class_code, description, source_note) VALUES
    ('ZZ', 'gas', 'residential',      'ZZ residential',      'ZZ Admin. Code 1.1 (fictional)'),
    ('ZZ', 'gas', 'small_business',   'ZZ small business',   'ZZ Admin. Code 1.2 (fictional)'),
    ('ZZ', 'gas', 'large_commercial', 'ZZ large commercial', 'ZZ Admin. Code 1.3 (fictional)');
  INSERT INTO public.backbilling_rules (state_code, service_type, customer_class, cause, anchor_basis, qualifying_test_outcomes, favourable_duty,
     adverse_straddle, favourable_straddle, delivery_path, requires_supervisor_evidence, units_invariant,
     enforce_scope, enforce_months, enforce_condition, effective_from, source_note)
  VALUES ('ZZ', 'gas', 'residential', 'meter_error', 'test_date', ARRAY['fast','slow'], 'mandatory', 'prorate_days', 'prorate_days',
          'adjustment', false, false, 'conditional', NULL, 'read_beyond_utility_control', DATE '2020-01-01',
          'ZZ Admin. Code 4.7 (fictional): 12 months or half the time since the last test; refunds 36 months; prorate.')
  RETURNING id INTO v_rule;
  INSERT INTO public.backbilling_rule_window_terms (rule_id, direction, term_kind, months) VALUES
    (v_rule, 'adverse',    'months_before_anchor', 12),
    (v_rule, 'adverse',    'half_since_last_test', NULL),
    (v_rule, 'favourable', 'months_before_anchor', 36);
  INSERT INTO public.backbilling_rules (state_code, service_type, customer_class, cause, anchor_basis, qualifying_test_outcomes, favourable_duty,
     adverse_straddle, favourable_straddle, delivery_path, requires_supervisor_evidence, units_invariant,
     enforce_scope, effective_from, source_note)
  VALUES ('ZZ', 'gas', 'small_business', 'customer_culpable_conduct', 'discovery_date', NULL, 'mandatory', 'include_whole', 'include_whole',
          'reissue', true, false, 'uncapped', DATE '2020-01-01', 'ZZ Admin. Code 4.9 (fictional).');
  RAISE NOTICE 'PASS Z1: a second state with other classes, a new cause, a 12-month + half-interval window, a 36-month refund reach, proration and a conditional enforcement is stored as rows, no DDL';
END $$;
DO $$ DECLARE v_old uuid := pg_temp.r('protected', 'estimation_catchup'); v_new uuid; BEGIN
  -- A law change: close the Texas row and add its successor.
  UPDATE public.backbilling_rules SET effective_to = DATE '2027-01-01' WHERE id = v_old;
  INSERT INTO public.backbilling_rules (state_code, service_type, customer_class, cause, anchor_basis, qualifying_test_outcomes, favourable_duty,
     adverse_straddle, favourable_straddle, delivery_path, requires_supervisor_evidence, units_invariant,
     enforce_scope, enforce_months, effective_from, source_note)
  VALUES ('TX', 'gas', 'protected', 'estimation_catchup', 'discovery_date', NULL, 'permitted', 'include_whole', 'include_whole',
          'unruled', false, false, 'months', 12, DATE '2027-01-01', 'hypothetical amendment, battery only')
  RETURNING id INTO v_new;
  IF (SELECT effective_to FROM public.backbilling_rules WHERE id = v_old) <> DATE '2027-01-01' THEN
    RAISE EXCEPTION 'FAIL Z2: the close did not take';
  END IF;
  RAISE NOTICE 'PASS Z2: a law change is a close plus a successor; both stay citable';
END $$;
SET LOCAL app.user_id = '00000000-0000-4000-8000-0000000013b1';
SET ROLE tally_app;
DO $$ BEGIN
  IF (SELECT count(*) FROM public.backbilling_rule_window_terms t
        JOIN public.backbilling_rules b ON b.id = t.rule_id WHERE b.state_code = 'ZZ') <> 3 THEN
    RAISE EXCEPTION 'FAIL Z3: the application cannot read ZZ''s terms';
  END IF;
  RAISE NOTICE 'PASS Z3: the application reads ZZ''s rows exactly as Texas''s';
END $$;


-- ============================================================ D. reissue cause
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'correction_run_targets_backbill_cause_fkey') THEN
    RAISE EXCEPTION 'FAIL D1: backbill_cause is not a foreign key to causes';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'correction_run_targets_backbill_cause_check') THEN
    RAISE EXCEPTION 'FAIL D1: the rate_misapplication-only CHECK survived';
  END IF;
  RAISE NOTICE 'PASS D1: a reissue records any known cause; which may travel by reissue is backbilling_rules.delivery_path';
END $$;


-- ============================================================ E. the case record
-- Tests: a fast finding on M-FAST, a slow one on M-SLOW.
DO $$ BEGIN
  INSERT INTO b13 VALUES ('t_fast', pg_temp.rec('00000000-0000-4000-8000-0000000013e1', DATE '2026-05-15', 104));
  INSERT INTO b13 VALUES ('t_slow', pg_temp.rec('00000000-0000-4000-8000-0000000013e2', DATE '2026-05-15', 96));
END $$;
DO $$ DECLARE c public.meter_correction_cases%ROWTYPE; BEGIN
  INSERT INTO public.meter_correction_cases (tenant_id, meter_id, cause, discovering_test_id, anchor_date, anchor_basis,
         direction, opened_at, opened_by)
  VALUES ('00000000-0000-4000-8000-0000000013a1', '00000000-0000-4000-8000-0000000013e1', 'meter_error', pg_temp.id('t_fast'),
          DATE '2026-05-15', 'test_date', 'customer_owed', TIMESTAMPTZ '2000-01-01', '00000000-0000-4000-8000-0000000013b9')
  RETURNING * INTO c;
  INSERT INTO b13 VALUES ('case_fast', c.id);
  IF c.opened_by IS DISTINCT FROM '00000000-0000-4000-8000-0000000013b1'::uuid OR c.opened_at < now() - interval '1 minute' THEN
    RAISE EXCEPTION 'FAIL E1: the caller chose the opening stamps (% / %)', c.opened_by, c.opened_at;
  END IF;
  RAISE NOTICE 'PASS E1: a case opens with opened_at / opened_by stamped from the session, whatever the caller sent';
END $$;
DO $$ BEGIN
  INSERT INTO public.meter_correction_cases (tenant_id, meter_id, cause, anchor_date, anchor_basis)
  VALUES ('00000000-0000-4000-8000-0000000013a1', '00000000-0000-4000-8000-0000000013e2', 'meter_error', DATE '2026-05-15', 'test_date');
  RAISE EXCEPTION 'FAIL E2: a test-anchored case with no test was accepted';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'PASS E2: a test-anchored case names its test'; END $$;
DO $$ BEGIN
  INSERT INTO public.meter_correction_cases (tenant_id, meter_id, cause, anchor_date, anchor_basis)
  VALUES ('00000000-0000-4000-8000-0000000013a1', '00000000-0000-4000-8000-0000000013e8', 'crossed_meters', DATE '2026-05-01', 'discovery_date');
  RAISE EXCEPTION 'FAIL E3: a discovery case with no claimed start was accepted';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'PASS E3: a discovery case records how far back the fault is claimed to reach'; END $$;
DO $$ BEGIN
  INSERT INTO public.meter_correction_cases (tenant_id, meter_id, cause, anchor_date, anchor_basis, claimed_from, status, withdrawn_reason)
  VALUES ('00000000-0000-4000-8000-0000000013a1', '00000000-0000-4000-8000-0000000013e8', 'crossed_meters', DATE '2026-05-01',
          'discovery_date', DATE '2026-01-01', 'withdrawn', 'born withdrawn');
  RAISE EXCEPTION 'FAIL E4: a case was opened withdrawn';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'PASS E4: a case opens open'; END $$;
DO $$ BEGIN
  INSERT INTO public.meter_correction_cases (tenant_id, meter_id, cause, anchor_date, anchor_basis, claimed_from)
  VALUES ('00000000-0000-4000-8000-0000000013a1', '00000000-0000-4000-8000-0000000013e8', 'no_such_cause', DATE '2026-05-01',
          'discovery_date', DATE '2026-01-01');
  RAISE EXCEPTION 'FAIL E5: an unknown cause was accepted';
EXCEPTION WHEN foreign_key_violation THEN
  RAISE NOTICE 'PASS E5: a case''s cause is a known cause'; END $$;
DO $$ DECLARE v uuid; BEGIN
  INSERT INTO public.meter_correction_cases (tenant_id, meter_id, cause, anchor_date, anchor_basis, claimed_from)
  VALUES ('00000000-0000-4000-8000-0000000013a1', '00000000-0000-4000-8000-0000000013e8', 'crossed_meters', DATE '2026-05-01',
          'discovery_date', DATE '2026-01-01')
  RETURNING id INTO v;
  INSERT INTO b13 VALUES ('case_disc', v);
  RAISE NOTICE 'PASS E6: a discovery case opens with its claimed start';
END $$;
DO $$ BEGIN
  UPDATE public.meter_correction_cases SET cause = 'billing_constant_error' WHERE id = pg_temp.id('case_disc');
  RAISE EXCEPTION 'FAIL E7: a cause change with no reason was accepted';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'PASS E7: a cause change carries a reason (R-19)'; END $$;
DO $$ BEGIN
  UPDATE public.meter_correction_cases SET cause = 'billing_constant_error', cause_change_reason = 'multiplier was 10, not 1'
   WHERE id = pg_temp.id('case_disc');
  UPDATE public.meter_correction_cases SET cause = 'crossed_meters' WHERE id = pg_temp.id('case_disc');
  RAISE EXCEPTION 'FAIL E8: a second cause change reused the first reason';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'PASS E8: each cause change needs its own reason'; END $$;
DO $$ BEGIN
  UPDATE public.meter_correction_cases SET cause = 'billing_constant_error', cause_change_reason = 'multiplier was 10, not 1'
   WHERE id = pg_temp.id('case_disc');
  IF NOT EXISTS (SELECT 1 FROM public.meter_correction_case_events
                  WHERE case_id = pg_temp.id('case_disc') AND event_type = 'cause_changed'
                    AND to_cause = 'billing_constant_error' AND reason = 'multiplier was 10, not 1'
                    AND actor_id = '00000000-0000-4000-8000-0000000013b1') THEN
    RAISE EXCEPTION 'FAIL E9: the cause change was not logged by the database';
  END IF;
  RAISE NOTICE 'PASS E9: the database logs the cause change, its reason and its actor';
END $$;
DO $$ BEGIN
  UPDATE public.meter_correction_cases SET evidence_kind = 'field_report' WHERE id = pg_temp.id('case_disc');
  RAISE EXCEPTION 'FAIL E10: evidence with no reference was accepted';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'PASS E10: evidence is one kind with exactly its reference'; END $$;
DO $$ DECLARE c public.meter_correction_cases%ROWTYPE; BEGIN
  UPDATE public.meter_correction_cases
     SET cause = 'tampering_bypass', cause_change_reason = 'seal broken, bypass pipe found',
         evidence_kind = 'deployment_removal', evidence_deployment_id = pg_temp.id('dep_ee'),
         evidence_recorded_at = TIMESTAMPTZ '2000-01-01'
   WHERE id = pg_temp.id('case_disc') RETURNING * INTO c;
  IF c.evidence_recorded_by IS DISTINCT FROM '00000000-0000-4000-8000-0000000013b1'::uuid
     OR c.evidence_recorded_at < now() - interval '1 minute' THEN
    RAISE EXCEPTION 'FAIL E11: evidence stamps were the caller''s';
  END IF;
  -- An operator (not a supervisor) moved the case into tampering: the
  -- database no longer refuses that — the core does (requires_supervisor_evidence).
  RAISE NOTICE 'PASS E11: evidence is stamped with who recorded it and when; whether this session could make the move is the core''s (R-38)';
END $$;
DO $$ BEGIN
  UPDATE public.meter_correction_cases SET meter_id = '00000000-0000-4000-8000-0000000013e2' WHERE id = pg_temp.id('case_fast');
  RAISE EXCEPTION 'FAIL E12: a case moved to another meter';
EXCEPTION WHEN restrict_violation THEN
  RAISE NOTICE 'PASS E12: a case never changes meter'; END $$;
DO $$ BEGIN
  INSERT INTO public.meter_correction_cases (tenant_id, meter_id, cause, discovering_test_id, anchor_date, anchor_basis, direction)
  VALUES ('00000000-0000-4000-8000-0000000013a1', '00000000-0000-4000-8000-0000000013e1', 'meter_error', pg_temp.id('t_fast'),
          DATE '2026-05-15', 'test_date', 'customer_owed');
  RAISE EXCEPTION 'FAIL E13: two live cases rest on one test';
EXCEPTION WHEN unique_violation THEN
  RAISE NOTICE 'PASS E13: one live case per discovering test (it would be posted twice)'; END $$;
DO $$ BEGIN
  DELETE FROM public.meter_correction_cases WHERE id = pg_temp.id('case_disc');
  RAISE EXCEPTION 'FAIL E14: a case was deleted';
EXCEPTION WHEN insufficient_privilege OR restrict_violation OR raise_exception THEN
  IF SQLERRM LIKE 'FAIL%' THEN RAISE; END IF;
  RAISE NOTICE 'PASS E14: a case is never deleted'; END $$;
DO $$ BEGIN
  INSERT INTO public.meter_correction_case_events (tenant_id, case_id, event_type)
  VALUES ('00000000-0000-4000-8000-0000000013a1', pg_temp.id('case_fast'), 'gate_approved');
  RAISE EXCEPTION 'FAIL E15: the application wrote an event';
EXCEPTION WHEN restrict_violation THEN
  RAISE NOTICE 'PASS E15: only the database writes case events'; END $$;


-- ============================================================ F. evaluations
DO $$ DECLARE v uuid; BEGIN
  INSERT INTO public.meter_correction_evaluations (tenant_id, case_id, cause, anchor_date, anchor_basis, direction, rule_id,
         approval_required, inputs, inputs_fingerprint, calculated_by)
  VALUES ('00000000-0000-4000-8000-0000000013a1', pg_temp.id('case_fast'), 'meter_error', DATE '2026-05-15', 'test_date',
          'customer_owed', pg_temp.r('protected', 'non_registering_meter'), false, '{"k":1}', 'fp', 'core-0.0.0');
  RAISE EXCEPTION 'FAIL F1: an evaluation cited a rule for another cause';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'PASS F1: an evaluation''s rule row must be a rule for the evaluated cause'; END $$;
DO $$ DECLARE e public.meter_correction_evaluations%ROWTYPE; BEGIN
  INSERT INTO public.meter_correction_evaluations (tenant_id, case_id, cause, anchor_date, anchor_basis, direction, rule_id,
         adverse_window_start, favourable_window_start, approval_required, inputs, inputs_fingerprint, calculated_by,
         evaluated_at, evaluated_by)
  VALUES ('00000000-0000-4000-8000-0000000013a1', pg_temp.id('case_fast'), 'meter_error', DATE '2026-05-15', 'test_date',
          'customer_owed', pg_temp.r('protected', 'meter_error'), DATE '2025-11-15', DATE '2025-11-15', true,
          '{"periods":2}', 'fp-1', 'core-0.0.0', TIMESTAMPTZ '2000-01-01', '00000000-0000-4000-8000-0000000013b9')
  RETURNING * INTO e;
  INSERT INTO b13 VALUES ('ev1', e.id);
  IF e.evaluated_by IS DISTINCT FROM '00000000-0000-4000-8000-0000000013b1'::uuid OR e.evaluated_at < now() - interval '1 minute' THEN
    RAISE EXCEPTION 'FAIL F2: evaluation stamps were the caller''s';
  END IF;
  -- Evidence in the same transaction: a refund per period (fast meter).
  INSERT INTO public.meter_correction_period_evidence (tenant_id, evaluation_id, invoice_id, customer_id, location_id,
         period_start, period_end, customer_class, rule_id, window_start, direction, correction_amount, disposition, days_in_window)
  VALUES ('00000000-0000-4000-8000-0000000013a1', e.id, pg_temp.id('inv_f1'), '00000000-0000-4000-8000-0000000013c1',
          '00000000-0000-4000-8000-0000000013d1', DATE '2026-03-01', DATE '2026-03-31', 'protected',
          pg_temp.r('protected', 'meter_error'), DATE '2025-11-15', 'customer_owed', -2.00, 'included', 31),
         ('00000000-0000-4000-8000-0000000013a1', e.id, pg_temp.id('inv_f2'), '00000000-0000-4000-8000-0000000013c1',
          '00000000-0000-4000-8000-0000000013d1', DATE '2026-04-01', DATE '2026-04-30', 'protected',
          pg_temp.r('protected', 'meter_error'), DATE '2025-11-15', 'customer_owed', -2.00, 'included', 30);
  RAISE NOTICE 'PASS F2: the core records an evaluation (stamped from the session) and its per-period evidence in one transaction';
END $$;
DO $$ BEGIN
  INSERT INTO public.meter_correction_period_evidence (tenant_id, evaluation_id, invoice_id, customer_id,
         period_start, period_end, customer_class, rule_id, direction, correction_amount, disposition, days_in_window)
  VALUES ('00000000-0000-4000-8000-0000000013a1', pg_temp.id('ev1'), pg_temp.id('inv_d1'), '00000000-0000-4000-8000-0000000013c1',
          DATE '2026-04-01', DATE '2026-04-30', 'protected', pg_temp.r('protected', 'meter_error'),
          'customer_owed', 2.00, 'included', 30);
  RAISE EXCEPTION 'FAIL F3: a refund with a positive amount was accepted';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'PASS F3: an evidence row''s sign matches its direction'; END $$;
DO $$ BEGIN
  INSERT INTO public.meter_correction_period_evidence (tenant_id, evaluation_id, invoice_id, customer_id,
         period_start, period_end, customer_class, rule_id, direction, correction_amount, disposition, forfeit_reason,
         forfeited_amount, days_in_window)
  VALUES ('00000000-0000-4000-8000-0000000013a1', pg_temp.id('ev1'), pg_temp.id('inv_d1'), '00000000-0000-4000-8000-0000000013c1',
          DATE '2026-04-01', DATE '2026-04-30', 'protected', pg_temp.r('protected', 'meter_error'),
          'customer_owes', 30.00, 'forfeited', 'straddles_window', 10.00, 12);
  RAISE EXCEPTION 'FAIL F4: a whole forfeiture gave up less than the whole';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'PASS F4: "forfeited" gives up the whole amount'; END $$;
DO $$ BEGIN
  INSERT INTO public.meter_correction_period_evidence (tenant_id, evaluation_id, invoice_id, customer_id,
         period_start, period_end, customer_class, rule_id, direction, correction_amount, disposition, forfeit_reason,
         forfeited_amount, days_in_window)
  VALUES ('00000000-0000-4000-8000-0000000013a1', pg_temp.id('ev1'), pg_temp.id('inv_d1'), '00000000-0000-4000-8000-0000000013c1',
          DATE '2026-04-01', DATE '2026-04-30', 'protected', pg_temp.r('protected', 'meter_error'),
          'customer_owes', 30.00, 'partly_forfeited', 'straddles_window', 30.00, 12);
  RAISE EXCEPTION 'FAIL F5: a partial forfeiture gave up the whole';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'PASS F5: "partly_forfeited" gives up some, not none or all'; END $$;
DO $$ BEGIN
  INSERT INTO public.meter_correction_period_evidence (tenant_id, evaluation_id, invoice_id, customer_id,
         period_start, period_end, customer_class, rule_id, direction, correction_amount, disposition, days_in_window)
  VALUES ('00000000-0000-4000-8000-0000000013a1', pg_temp.id('ev1'), pg_temp.id('inv_d1'), '00000000-0000-4000-8000-0000000013c1',
          DATE '2026-04-01', DATE '2026-04-30', 'unprotected', pg_temp.r('protected', 'meter_error'),
          'customer_owed', -2.00, 'included', 30);
  RAISE EXCEPTION 'FAIL F6: evidence cited a rule for another class';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'PASS F6: an evidence row''s rule is for its own class and the evaluation''s cause'; END $$;
DO $$ BEGIN
  INSERT INTO public.meter_correction_period_evidence (tenant_id, evaluation_id, invoice_id, customer_id,
         period_start, period_end, customer_class, rule_id, direction, correction_amount, disposition, forfeit_reason,
         forfeited_amount, days_in_window)
  VALUES ('00000000-0000-4000-8000-0000000013a1', pg_temp.id('ev1'), pg_temp.id('inv_d1'), '00000000-0000-4000-8000-0000000013c1',
          DATE '2026-04-01', DATE '2026-04-30', 'protected', pg_temp.r('protected', 'meter_error'),
          'customer_owes', 30.00, 'partly_forfeited', 'straddles_window', 18.00, 12);
  RAISE NOTICE 'PASS F7: a prorated period records what was billable and what was given up (a state that prorates fits)';
END $$;
DO $$ BEGIN
  UPDATE public.meter_correction_evaluations SET adverse_window_start = DATE '2025-01-01' WHERE id = pg_temp.id('ev1');
  RAISE EXCEPTION 'FAIL F8: an evaluation was edited';
EXCEPTION WHEN insufficient_privilege OR restrict_violation OR raise_exception THEN
  IF SQLERRM LIKE 'FAIL%' THEN RAISE; END IF;
  RAISE NOTICE 'PASS F8: an evaluation is never edited'; END $$;
DO $$ BEGIN
  UPDATE public.meter_correction_period_evidence SET correction_amount = -9.00 WHERE evaluation_id = pg_temp.id('ev1');
  RAISE EXCEPTION 'FAIL F9: evidence was edited';
EXCEPTION WHEN insufficient_privilege OR restrict_violation OR raise_exception THEN
  IF SQLERRM LIKE 'FAIL%' THEN RAISE; END IF;
  RAISE NOTICE 'PASS F9: evidence is never edited'; END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.meter_correction_case_events
                  WHERE case_id = pg_temp.id('case_fast') AND event_type = 'evaluated' AND evaluation_id = pg_temp.id('ev1')) THEN
    RAISE EXCEPTION 'FAIL F10: the evaluation was not logged';
  END IF;
  RAISE NOTICE 'PASS F10: the database logs each evaluation on the case';
END $$;


-- ============================================================ G. approvals
DO $$ BEGIN
  INSERT INTO public.meter_correction_approvals (tenant_id, case_id, evaluation_id, note)
  VALUES ('00000000-0000-4000-8000-0000000013a1', pg_temp.id('case_disc'), pg_temp.id('ev1'), 'wrong case');
  RAISE EXCEPTION 'FAIL G1: an approval tied an evaluation to another case';
EXCEPTION WHEN foreign_key_violation THEN
  RAISE NOTICE 'PASS G1: an approval is of an evaluation of the same case'; END $$;
RESET ROLE;
SET LOCAL app.user_id = '00000000-0000-4000-8000-0000000013b3';
SET ROLE tally_app;
DO $$ DECLARE a public.meter_correction_approvals%ROWTYPE; BEGIN
  INSERT INTO public.meter_correction_approvals (tenant_id, case_id, evaluation_id, note, approved_by, approved_at)
  VALUES ('00000000-0000-4000-8000-0000000013a1', pg_temp.id('case_fast'), pg_temp.id('ev1'), 'window checked',
          '00000000-0000-4000-8000-0000000013b9', TIMESTAMPTZ '2000-01-01')
  RETURNING * INTO a;
  IF a.approved_by IS DISTINCT FROM '00000000-0000-4000-8000-0000000013b3'::uuid OR a.approved_at < now() - interval '1 minute' THEN
    RAISE EXCEPTION 'FAIL G2: the caller chose who approved';
  END IF;
  RAISE NOTICE 'PASS G2: approved_by is the session''s user and approved_at the database clock';
END $$;
DO $$ BEGIN
  INSERT INTO public.meter_correction_approvals (tenant_id, case_id, evaluation_id, note)
  VALUES ('00000000-0000-4000-8000-0000000013a1', pg_temp.id('case_fast'), pg_temp.id('ev1'), 'again');
  RAISE EXCEPTION 'FAIL G3: two approvals of one evaluation';
EXCEPTION WHEN unique_violation THEN
  RAISE NOTICE 'PASS G3: one approval per evaluation'; END $$;
DO $$ BEGIN
  UPDATE public.meter_correction_approvals SET note = 'edited' WHERE evaluation_id = pg_temp.id('ev1');
  RAISE EXCEPTION 'FAIL G4: an approval was edited';
EXCEPTION WHEN insufficient_privilege OR restrict_violation OR raise_exception THEN
  IF SQLERRM LIKE 'FAIL%' THEN RAISE; END IF;
  RAISE NOTICE 'PASS G4: an approval is never edited'; END $$;
RESET ROLE;
SET LOCAL app.user_id = '00000000-0000-4000-8000-0000000013b1';
SET ROLE tally_app;


-- ============================================================ H. freeze / withdraw
-- An evaluation of case_disc under its old cause, then a cause change: an
-- evaluation for the wrong cause cannot be frozen.
DO $$ DECLARE v uuid; BEGIN
  INSERT INTO public.meter_correction_evaluations (tenant_id, case_id, cause, anchor_date, anchor_basis, claimed_from, rule_id,
         approval_required, inputs, inputs_fingerprint, calculated_by)
  VALUES ('00000000-0000-4000-8000-0000000013a1', pg_temp.id('case_disc'), 'tampering_bypass', DATE '2026-05-01', 'discovery_date',
          DATE '2026-01-01', pg_temp.r('protected', 'tampering_bypass'), false, '{}', 'fp-d1', 'core-0.0.0')
  RETURNING id INTO v;
  INSERT INTO b13 VALUES ('ev_disc_tamper', v);
  UPDATE public.meter_correction_cases
     SET cause = 'crossed_meters', cause_change_reason = 'bypass was the neighbour''s line',
         evidence_kind = NULL, evidence_deployment_id = NULL
   WHERE id = pg_temp.id('case_disc');
END $$;
DO $$ BEGIN
  UPDATE public.meter_correction_cases SET status = 'frozen', frozen_evaluation_id = pg_temp.id('ev_disc_tamper')
   WHERE id = pg_temp.id('case_disc');
  RAISE EXCEPTION 'FAIL H1: a case froze on an evaluation of another cause';
EXCEPTION WHEN restrict_violation THEN
  RAISE NOTICE 'PASS H1: a freeze pins an evaluation computed for the case''s current cause and anchor'; END $$;
DO $$ BEGIN
  UPDATE public.meter_correction_cases SET status = 'frozen', frozen_evaluation_id = pg_temp.id('ev1')
   WHERE id = pg_temp.id('case_disc');
  RAISE EXCEPTION 'FAIL H2: a case froze on another case''s evaluation';
EXCEPTION WHEN restrict_violation OR foreign_key_violation THEN
  RAISE NOTICE 'PASS H2: a freeze pins an evaluation of THIS case'; END $$;
DO $$ BEGIN
  UPDATE public.meter_correction_cases SET status = 'frozen', frozen_evaluation_id = pg_temp.id('ev1'), notes = 'sneak'
   WHERE id = pg_temp.id('case_fast');
  RAISE EXCEPTION 'FAIL H3: a freeze carried another change';
EXCEPTION WHEN restrict_violation THEN
  RAISE NOTICE 'PASS H3: a freeze changes nothing but the freeze'; END $$;
DO $$ DECLARE c public.meter_correction_cases%ROWTYPE; BEGIN
  UPDATE public.meter_correction_cases SET status = 'frozen', frozen_evaluation_id = pg_temp.id('ev1'),
         frozen_at = TIMESTAMPTZ '2000-01-01', frozen_by = '00000000-0000-4000-8000-0000000013b9'
   WHERE id = pg_temp.id('case_fast') RETURNING * INTO c;
  IF c.frozen_by IS DISTINCT FROM '00000000-0000-4000-8000-0000000013b1'::uuid OR c.frozen_at < now() - interval '1 minute' THEN
    RAISE EXCEPTION 'FAIL H4: freeze stamps were the caller''s';
  END IF;
  RAISE NOTICE 'PASS H4: a case freezes on its own evaluation; frozen_at / frozen_by stamped';
END $$;
DO $$ BEGIN
  UPDATE public.meter_correction_cases SET notes = 'edit while frozen' WHERE id = pg_temp.id('case_fast');
  RAISE EXCEPTION 'FAIL H5: a frozen case was edited';
EXCEPTION WHEN restrict_violation THEN
  RAISE NOTICE 'PASS H5: a frozen case changes only by unfreezing'; END $$;
DO $$ BEGIN
  UPDATE public.meter_correction_cases SET status = 'withdrawn', frozen_evaluation_id = NULL, frozen_at = NULL, withdrawn_reason = 'x'
   WHERE id = pg_temp.id('case_fast');
  RAISE EXCEPTION 'FAIL H6: a frozen case went straight to withdrawn';
EXCEPTION WHEN restrict_violation THEN
  RAISE NOTICE 'PASS H6: a frozen case cannot be withdrawn without unfreezing'; END $$;


-- ============================================================ J. a frozen case's tests
DO $$ BEGIN
  PERFORM pg_temp.rec('00000000-0000-4000-8000-0000000013e1', DATE '2026-05-15', 100, pg_temp.id('t_fast'));
  RAISE EXCEPTION 'FAIL J1: a test a frozen case rests on was superseded';
EXCEPTION WHEN restrict_violation THEN
  RAISE NOTICE 'PASS J1: a test a frozen case rests on cannot be superseded'; END $$;

-- (K1 runs here, while the case is frozen and its approval exists.)
DO $$ DECLARE s public.meter_correction_case_status%ROWTYPE; BEGIN
  SELECT * INTO s FROM public.meter_correction_case_status WHERE case_id = pg_temp.id('case_fast');
  IF s.status <> 'frozen' OR s.governing_evaluation_id IS DISTINCT FROM pg_temp.id('ev1') OR s.approval_pending
     OR s.rule_id IS DISTINCT FROM pg_temp.r('protected', 'meter_error') THEN
    RAISE EXCEPTION 'FAIL K1: case status reads %', row_to_json(s);
  END IF;
  RAISE NOTICE 'PASS K1: case status reads the frozen evaluation, its rule row and its approval';
END $$;

DO $$ DECLARE c public.meter_correction_cases%ROWTYPE; BEGIN
  UPDATE public.meter_correction_cases SET status = 'open', frozen_evaluation_id = NULL, frozen_at = NULL, frozen_by = NULL
   WHERE id = pg_temp.id('case_fast') RETURNING * INTO c;
  IF c.frozen_at IS NOT NULL OR c.frozen_by IS NOT NULL THEN RAISE EXCEPTION 'FAIL H7: freeze stamps survived'; END IF;
  IF (SELECT count(*) FROM public.meter_correction_case_events
       WHERE case_id = pg_temp.id('case_fast') AND event_type IN ('frozen', 'unfrozen')) <> 2 THEN
    RAISE EXCEPTION 'FAIL H7: freeze / unfreeze not logged';
  END IF;
  RAISE NOTICE 'PASS H7: unfreezing alone reopens the case; freeze and unfreeze are logged';
END $$;
DO $$ BEGIN
  PERFORM pg_temp.rec('00000000-0000-4000-8000-0000000013e1', DATE '2026-05-15', 101, pg_temp.id('t_fast'));
  RAISE NOTICE 'PASS J2: once unfrozen, the test can be corrected';
END $$;
DO $$ BEGIN
  UPDATE public.meter_correction_cases SET status = 'withdrawn', withdrawn_reason = 'test corrected to within tolerance'
   WHERE id = pg_temp.id('case_fast');
  UPDATE public.meter_correction_cases SET status = 'open', withdrawn_reason = NULL WHERE id = pg_temp.id('case_fast');
  RAISE EXCEPTION 'FAIL H8: a withdrawn case reopened';
EXCEPTION WHEN restrict_violation THEN
  RAISE NOTICE 'PASS H8: a withdrawn case never changes'; END $$;


-- ============================================================ I. holds
DO $$ BEGIN
  INSERT INTO public.meter_correction_holds (tenant_id, case_id, range_start, range_end, hold_code, status, closed_at)
  VALUES ('00000000-0000-4000-8000-0000000013a1', pg_temp.id('case_disc'), DATE '2026-01-01', DATE '2026-01-14',
          'legacy_records_not_loaded', 'completed', now());
  RAISE EXCEPTION 'FAIL I1: a hold was opened closed';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'PASS I1: a hold opens open'; END $$;
DO $$ BEGIN
  INSERT INTO public.meter_correction_holds (tenant_id, case_id, range_start, range_end, hold_code)
  VALUES ('00000000-0000-4000-8000-0000000013a1', pg_temp.id('case_disc'), DATE '2026-01-01', DATE '2026-01-14',
          'predecessor_records_unavailable');
  RAISE EXCEPTION 'FAIL I2: a predecessor hold without its acquisition';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'PASS I2: a predecessor hold names its acquisition'; END $$;
DO $$ DECLARE h public.meter_correction_holds%ROWTYPE; BEGIN
  INSERT INTO public.meter_correction_holds (tenant_id, case_id, range_start, range_end, hold_code, opened_by)
  VALUES ('00000000-0000-4000-8000-0000000013a1', pg_temp.id('case_disc'), DATE '2026-01-01', DATE '2026-01-14',
          'legacy_records_not_loaded', '00000000-0000-4000-8000-0000000013b9')
  RETURNING * INTO h;
  INSERT INTO b13 VALUES ('hold1', h.id);
  IF h.opened_by IS DISTINCT FROM '00000000-0000-4000-8000-0000000013b1'::uuid THEN RAISE EXCEPTION 'FAIL I3: opened_by was the caller''s'; END IF;
  RAISE NOTICE 'PASS I3: a hold opens stamped from the session';
END $$;
DO $$ BEGIN
  INSERT INTO public.meter_correction_holds (tenant_id, case_id, range_start, range_end, hold_code)
  VALUES ('00000000-0000-4000-8000-0000000013a1', pg_temp.id('case_disc'), DATE '2026-01-10', DATE '2026-01-20',
          'legacy_records_not_loaded');
  RAISE EXCEPTION 'FAIL I4: overlapping open holds';
EXCEPTION WHEN exclusion_violation THEN
  RAISE NOTICE 'PASS I4: no two open holds of a case cover the same day'; END $$;
DO $$ BEGIN
  UPDATE public.meter_correction_holds SET status = 'unrecoverable' WHERE id = pg_temp.id('hold1');
  RAISE EXCEPTION 'FAIL I5: an unrecoverable closure with no artifact';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'PASS I5: an unrecoverable closure names its artifact'; END $$;
DO $$ BEGIN
  UPDATE public.meter_correction_holds SET status = 'completed', range_end = DATE '2026-01-31' WHERE id = pg_temp.id('hold1');
  RAISE EXCEPTION 'FAIL I6: a closure moved the range';
EXCEPTION WHEN restrict_violation THEN
  RAISE NOTICE 'PASS I6: a closure changes nothing else'; END $$;
DO $$ DECLARE h public.meter_correction_holds%ROWTYPE; BEGIN
  UPDATE public.meter_correction_holds SET status = 'completed' WHERE id = pg_temp.id('hold1') RETURNING * INTO h;
  IF h.closed_by IS DISTINCT FROM '00000000-0000-4000-8000-0000000013b1'::uuid OR h.closed_at IS NULL THEN
    RAISE EXCEPTION 'FAIL I7: closure not stamped';
  END IF;
  RAISE NOTICE 'PASS I7: a hold closes once, stamped';
END $$;
DO $$ BEGIN
  UPDATE public.meter_correction_holds SET status = 'unrecoverable', closure_artifact_ref = 'x' WHERE id = pg_temp.id('hold1');
  RAISE EXCEPTION 'FAIL I8: a closed hold changed';
EXCEPTION WHEN restrict_violation THEN
  RAISE NOTICE 'PASS I8: a closed hold never changes'; END $$;
DO $$ BEGIN
  IF (SELECT count(*) FROM public.meter_correction_case_events
       WHERE case_id = pg_temp.id('case_disc') AND event_type IN ('hold_opened', 'hold_completed')) <> 2 THEN
    RAISE EXCEPTION 'FAIL I9: hold events missing';
  END IF;
  RAISE NOTICE 'PASS I9: hold opening and closing are logged';
END $$;


-- ============================================================ K. surfaces, tenancy
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.backbilling_forfeitures
                  WHERE evaluation_id = pg_temp.id('ev1') AND disposition = 'partly_forfeited' AND forfeited_amount = 18.00) THEN
    RAISE EXCEPTION 'FAIL K2: the partial forfeiture is not on the surface';
  END IF;
  RAISE NOTICE 'PASS K2: forfeitures, whole and partial, are on a standing surface';
END $$;
RESET ROLE;
SET LOCAL app.user_id = '00000000-0000-4000-8000-0000000013b2';
SET ROLE tally_app;
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM public.meter_correction_cases)
     OR EXISTS (SELECT 1 FROM public.meter_correction_evaluations)
     OR EXISTS (SELECT 1 FROM public.meter_correction_period_evidence)
     OR EXISTS (SELECT 1 FROM public.meter_correction_case_events)
     OR EXISTS (SELECT 1 FROM public.meter_correction_holds)
     OR EXISTS (SELECT 1 FROM public.meter_correction_approvals)
     OR EXISTS (SELECT 1 FROM public.meter_correction_case_status)
     OR EXISTS (SELECT 1 FROM public.backbilling_forfeitures) THEN
    RAISE EXCEPTION 'FAIL K3: tenant 2 sees tenant 1''s correction records';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.backbilling_rules WHERE state_code = 'TX') THEN
    RAISE EXCEPTION 'FAIL K3: tenant 2 cannot read the law';
  END IF;
  RAISE NOTICE 'PASS K3: tenant 2 sees none of tenant 1''s records, and reads the same law';
END $$;
DO $$ BEGIN
  INSERT INTO public.meter_correction_cases (tenant_id, meter_id, cause, anchor_date, anchor_basis, claimed_from)
  VALUES ('00000000-0000-4000-8000-0000000013a1', '00000000-0000-4000-8000-0000000013e8', 'crossed_meters', DATE '2026-05-01',
          'discovery_date', DATE '2026-01-01');
  RAISE EXCEPTION 'FAIL K4: tenant 2 wrote a case into tenant 1';
EXCEPTION WHEN insufficient_privilege OR foreign_key_violation THEN
  RAISE NOTICE 'PASS K4: tenant 2 cannot write into tenant 1'; END $$;
RESET ROLE;
DO $$ BEGIN
  PERFORM public.assert_tenant_isolation_invariants();
  RAISE NOTICE 'PASS K5: the AC-32 tenant-isolation assertion holds over every new table and view';
END $$;

ROLLBACK;
