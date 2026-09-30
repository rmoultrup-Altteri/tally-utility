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
-- Probes for review P1 (Fable). Run after 00-fixtures.sql inside the same
-- transaction; everything rolls back. Each probe prints OBSERVED lines.
-- Setup: the battery's own fast case + evaluation (E1/F2 shape).
SET LOCAL app.user_id = '00000000-0000-4000-8000-0000000013b1';
SET ROLE tally_app;
DO $$ DECLARE c uuid; e uuid; BEGIN
  INSERT INTO b13 VALUES ('t_fast', pg_temp.rec('00000000-0000-4000-8000-0000000013e1', DATE '2026-05-15', 104));
  INSERT INTO b13 VALUES ('t_slow', pg_temp.rec('00000000-0000-4000-8000-0000000013e2', DATE '2026-05-15', 96));
  INSERT INTO public.meter_correction_cases (tenant_id, meter_id, cause, discovering_test_id, anchor_date, anchor_basis, direction)
  VALUES ('00000000-0000-4000-8000-0000000013a1', '00000000-0000-4000-8000-0000000013e1', 'meter_error', pg_temp.id('t_fast'),
          DATE '2026-05-15', 'test_date', 'customer_owed') RETURNING id INTO c;
  INSERT INTO b13 VALUES ('case_fast', c);
  INSERT INTO public.meter_correction_evaluations (tenant_id, case_id, cause, anchor_date, anchor_basis, direction, rule_id,
         adverse_window_start, favourable_window_start, approval_required, inputs, inputs_fingerprint, calculated_by)
  VALUES ('00000000-0000-4000-8000-0000000013a1', c, 'meter_error', DATE '2026-05-15', 'test_date',
          'customer_owed', pg_temp.r('protected', 'meter_error'), DATE '2025-11-15', DATE '2025-11-15', false,
          '{"periods":2}', 'fp-1', 'core-0.0.0') RETURNING id INTO e;
  INSERT INTO b13 VALUES ('ev1', e);
  INSERT INTO public.meter_correction_period_evidence (tenant_id, evaluation_id, invoice_id, customer_id, location_id,
         period_start, period_end, customer_class, rule_id, window_start, direction, correction_amount, disposition, days_in_window)
  VALUES ('00000000-0000-4000-8000-0000000013a1', e, pg_temp.id('inv_f1'), '00000000-0000-4000-8000-0000000013c1',
          '00000000-0000-4000-8000-0000000013d1', DATE '2026-03-01', DATE '2026-03-31', 'protected',
          pg_temp.r('protected', 'meter_error'), DATE '2025-11-15', 'customer_owed', -2.00, 'included', 31);
  RAISE NOTICE 'SETUP: case_fast % with evaluation % citing TX protected/meter_error rule %', c, e, pg_temp.r('protected', 'meter_error');
END $$;
RESET ROLE;

-- ---------------------------------------------------------------- P1 (Q2)
-- A cited law row's WINDOW can still grow: the owner inserts a new term on
-- the TX meter_error rule that the evaluation above already cites.
DO $$ DECLARE n0 int; n1 int; BEGIN
  SELECT count(*) INTO n0 FROM public.backbilling_rule_window_terms WHERE rule_id = pg_temp.r('protected', 'meter_error');
  INSERT INTO public.backbilling_rule_window_terms (rule_id, direction, term_kind, months)
  VALUES (pg_temp.r('protected', 'meter_error'), 'favourable', 'last_test_accurate', NULL);
  SELECT count(*) INTO n1 FROM public.backbilling_rule_window_terms WHERE rule_id = pg_temp.r('protected', 'meter_error');
  RAISE NOTICE 'P1 OBSERVED: owner added a window term to a CITED rule row (terms % -> %); the evaluation''s rule_id now names a different window', n0, n1;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'P1 OBSERVED: refused % %', SQLSTATE, SQLERRM;
END $$;
-- Same thing on a direction that had NO terms (uncapped): a term added later
-- turns "uncapped" into "capped" under the same rule id.
DO $$ BEGIN
  INSERT INTO public.backbilling_rule_window_terms (rule_id, direction, term_kind, months)
  VALUES (pg_temp.r('protected', 'rate_misapplication'), 'adverse', 'months_before_anchor', 6);
  RAISE NOTICE 'P1b OBSERVED: an uncapped direction of an in-force rule became capped by a later INSERT (rate_misapplication adverse: 0 -> 1 terms)';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'P1b OBSERVED: refused % %', SQLSTATE, SQLERRM;
END $$;

-- ---------------------------------------------------------------- P2 (Q2)
-- Closing has no floor and no stamp: a row cited for 2026 periods is closed
-- as of 2005, and nothing records when or by whom.
DO $$ BEGIN
  UPDATE public.backbilling_rules SET effective_to = DATE '2005-01-01' WHERE id = pg_temp.r('protected', 'meter_error');
  RAISE NOTICE 'P2 OBSERVED: the TX meter_error row (cited by an evaluation for 2026 periods) was closed effective 2005-01-01; the table has no closed_at / closed_by';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'P2 OBSERVED: refused % %', SQLSTATE, SQLERRM;
END $$;
-- Now a successor covering 2005-> with different attributes fits; two rows
-- have been "in force" for 2026 at different times.
DO $$ BEGIN
  INSERT INTO public.backbilling_rules (state_code, service_type, customer_class, cause, anchor_basis, qualifying_test_outcomes, favourable_duty,
     adverse_straddle, favourable_straddle, delivery_path, requires_supervisor_evidence, units_invariant,
     enforce_scope, effective_from, source_note)
  VALUES ('TX', 'gas', 'protected', 'meter_error', 'test_date', ARRAY['fast','slow'], 'permitted', 'include_whole', 'include_whole',
          'adjustment', false, false, 'uncapped', DATE '2005-01-01', 'P2 successor');
  RAISE NOTICE 'P2b OBSERVED: a successor row with favourable_duty=permitted now covers 2026 while the frozen-able evaluation cites the closed mandatory row';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'P2b OBSERVED: refused % %', SQLSTATE, SQLERRM;
END $$;

-- ---------------------------------------------------------------- P8 (Q2)
-- The two vocabulary law tables have no history guard for the owner.
DO $$ BEGIN
  UPDATE public.backbilling_customer_classes SET description = 'rewritten', source_note = 'rewritten'
   WHERE state_code = 'TX' AND service_type = 'gas' AND class_code = 'protected';
  UPDATE public.backbilling_causes SET description = 'rewritten' WHERE cause_code = 'meter_error';
  RAISE NOTICE 'P8 OBSERVED: owner rewrote description/source_note on a class row and a cause row (no law-history trigger on these two tables)';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'P8 OBSERVED: refused % %', SQLSTATE, SQLERRM;
END $$;
DO $$ BEGIN
  INSERT INTO public.backbilling_customer_classes VALUES ('TX', 'gas', 'tmp_class', 'x', 'x', now());
  DELETE FROM public.backbilling_customer_classes WHERE class_code = 'tmp_class';
  RAISE NOTICE 'P8b OBSERVED: an unreferenced class row can be deleted by the owner';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'P8b OBSERVED: refused % %', SQLSTATE, SQLERRM;
END $$;

-- ---------------------------------------------------------------- P3 (Q2)
-- A case about meter M-SLOW citing a discovering test of M-FAST (same tenant).
SET LOCAL app.user_id = '00000000-0000-4000-8000-0000000013b1';
SET ROLE tally_app;
DO $$ DECLARE c uuid; BEGIN
  -- t_fast is already the live test of case_fast; use t_slow's meter mismatch:
  -- case on M-DISC (e8) citing t_slow (a test of M-SLOW e2).
  INSERT INTO public.meter_correction_cases (tenant_id, meter_id, cause, discovering_test_id, anchor_date, anchor_basis, direction)
  VALUES ('00000000-0000-4000-8000-0000000013a1', '00000000-0000-4000-8000-0000000013e8', 'meter_error', pg_temp.id('t_slow'),
          DATE '2026-05-15', 'test_date', 'customer_owes') RETURNING id INTO c;
  INSERT INTO b13 VALUES ('case_xmeter', c);
  RAISE NOTICE 'P3 OBSERVED: case % on meter M-DISC opened citing a discovering test of meter M-SLOW', c;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'P3 OBSERVED: refused % %', SQLSTATE, SQLERRM;
END $$;
-- Evaluation of case_fast (meter e1) naming a governing test and deployment
-- of other meters.
DO $$ DECLARE e uuid; BEGIN
  INSERT INTO public.meter_correction_evaluations (tenant_id, case_id, cause, anchor_date, anchor_basis, direction, rule_id,
         governing_test_id, governing_test_date, deployment_id, deployment_bound,
         approval_required, inputs, inputs_fingerprint, calculated_by)
  VALUES ('00000000-0000-4000-8000-0000000013a1', pg_temp.id('case_fast'), 'meter_error', DATE '2026-05-15', 'test_date',
          'customer_owed', pg_temp.r('protected', 'meter_error'),
          pg_temp.id('t_slow'), DATE '2026-05-15', pg_temp.id('dep_e9'), DATE '2024-01-01',
          false, '{}', 'fp-x', 'core-0.0.0') RETURNING id INTO e;
  RAISE NOTICE 'P3b OBSERVED: evaluation % of the M-FAST case records governing_test of M-SLOW and deployment of M-PRED', e;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'P3b OBSERVED: refused % %', SQLSTATE, SQLERRM;
END $$;
-- Case evidence: a deployment removal of a different meter as tamper evidence.
DO $$ BEGIN
  UPDATE public.meter_correction_cases
     SET cause = 'tampering_bypass', cause_change_reason = 'p3c',
         evidence_kind = 'deployment_removal', evidence_deployment_id = pg_temp.id('dep_ee')
   WHERE id = pg_temp.id('case_xmeter');
  RAISE NOTICE 'P3c OBSERVED: the case on M-DISC cites M-OLD''s deployment removal as its tamper evidence';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'P3c OBSERVED: refused % %', SQLSTATE, SQLERRM;
END $$;

-- ---------------------------------------------------------------- P4 (Q2)
-- Freeze onto an evaluation whose direction / basis differ from the case's.
DO $$ BEGIN
  UPDATE public.meter_correction_cases SET direction = 'customer_owes' WHERE id = pg_temp.id('case_fast');
  UPDATE public.meter_correction_cases SET status = 'frozen', frozen_evaluation_id = pg_temp.id('ev1')
   WHERE id = pg_temp.id('case_fast');
  RAISE NOTICE 'P4 OBSERVED: case_fast (direction now customer_owes) froze on ev1 (direction customer_owed); only cause and anchor_date are compared';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'P4 OBSERVED: refused % %', SQLSTATE, SQLERRM;
END $$;

-- ---------------------------------------------------------------- P6 (Q2)
-- The frozen case's satellites still move: new evaluation, approval, hold.
DO $$ DECLARE e uuid; h uuid; BEGIN
  INSERT INTO public.meter_correction_evaluations (tenant_id, case_id, cause, anchor_date, anchor_basis, direction, rule_id,
         approval_required, inputs, inputs_fingerprint, calculated_by)
  VALUES ('00000000-0000-4000-8000-0000000013a1', pg_temp.id('case_fast'), 'meter_error', DATE '2026-05-15', 'test_date',
          'customer_owed', pg_temp.r('protected', 'meter_error'), false, '{}', 'fp-after-freeze', 'core-0.0.0') RETURNING id INTO e;
  INSERT INTO public.meter_correction_holds (tenant_id, case_id, range_start, range_end, hold_code)
  VALUES ('00000000-0000-4000-8000-0000000013a1', pg_temp.id('case_fast'), DATE '2025-12-01', DATE '2026-01-14', 'legacy_records_not_loaded')
  RETURNING id INTO h;
  RAISE NOTICE 'P6 OBSERVED: on the FROZEN case_fast a new evaluation % and a new hold % were accepted (status still %)', e, h,
    (SELECT status FROM public.meter_correction_cases WHERE id = pg_temp.id('case_fast'));
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'P6 OBSERVED: refused % %', SQLSTATE, SQLERRM;
END $$;
-- unfreeze for later probes
UPDATE public.meter_correction_cases SET status = 'open', frozen_evaluation_id = NULL, frozen_at = NULL, frozen_by = NULL
 WHERE id = pg_temp.id('case_fast');

-- ---------------------------------------------------------------- P10 (Q2)
-- Withdrawal carrying other changes into the terminal record.
DO $$ DECLARE c public.meter_correction_cases%ROWTYPE; BEGIN
  UPDATE public.meter_correction_cases
     SET status = 'withdrawn', withdrawn_reason = 'p10', anchor_date = DATE '1999-01-01', direction = 'customer_owes', notes = 'rewritten on the way out'
   WHERE id = pg_temp.id('case_xmeter') RETURNING * INTO c;
  RAISE NOTICE 'P10 OBSERVED: withdrawal statement also moved anchor_date to % and direction to %; the row is now terminal', c.anchor_date, c.direction;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'P10 OBSERVED: refused % %', SQLSTATE, SQLERRM;
END $$;

-- ---------------------------------------------------------------- P7 (Q2)
-- Approval with no session user.
RESET ROLE;
SET LOCAL app.user_id = '';
SET ROLE tally_app;
DO $$ DECLARE a public.meter_correction_approvals%ROWTYPE; BEGIN
  INSERT INTO public.meter_correction_approvals (tenant_id, case_id, evaluation_id, note)
  VALUES ('00000000-0000-4000-8000-0000000013a1', pg_temp.id('case_fast'), pg_temp.id('ev1'), 'nobody here')
  RETURNING * INTO a;
  RAISE NOTICE 'P7 OBSERVED: approval % accepted with approved_by = %', a.id, coalesce(a.approved_by::text, 'NULL');
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'P7 OBSERVED: refused % %', SQLSTATE, SQLERRM;
END $$;
RESET ROLE;

-- ---------------------------------------------------------------- P21 (Q1)
-- Vocabularies the design expects to grow are CHECK-bound.
DO $$ BEGIN
  INSERT INTO public.backbilling_customer_classes (state_code, service_type, class_code, description, source_note)
  VALUES ('YY', 'gas', 'residential', 'YY residential', 'YY code (fictional)');
  INSERT INTO public.backbilling_rules (state_code, service_type, customer_class, cause, anchor_basis, qualifying_test_outcomes, favourable_duty,
     adverse_straddle, favourable_straddle, delivery_path, requires_supervisor_evidence, units_invariant,
     enforce_scope, effective_from, source_note)
  VALUES ('YY', 'gas', 'residential', 'estimation_catchup', 'notice_date', NULL, 'permitted', 'include_whole', 'include_whole',
          'adjustment', false, false, 'uncapped', DATE '2020-01-01', 'YY: window counts back from written notice to the customer');
  RAISE NOTICE 'P21 OBSERVED: anchor_basis = notice_date accepted';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'P21 OBSERVED: anchor_basis=notice_date refused % %', SQLSTATE, SQLERRM;
END $$;
DO $$ BEGIN
  INSERT INTO public.backbilling_rules (state_code, service_type, customer_class, cause, anchor_basis, qualifying_test_outcomes, favourable_duty,
     adverse_straddle, favourable_straddle, delivery_path, requires_supervisor_evidence, units_invariant,
     enforce_scope, enforce_condition, effective_from, source_note)
  VALUES ('YY', 'gas', 'residential', 'estimation_catchup', 'discovery_date', NULL, 'permitted', 'include_whole', 'include_whole',
          'adjustment', false, false, 'conditional', 'customer_denied_access', DATE '2020-01-01', 'YY: enforceable only if the customer denied meter access');
  RAISE NOTICE 'P21b OBSERVED: enforce_condition = customer_denied_access accepted';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'P21b OBSERVED: enforce_condition=customer_denied_access refused % %', SQLSTATE, SQLERRM;
END $$;
-- A window stated in days (not months).
DO $$ BEGIN
  INSERT INTO public.backbilling_rule_window_terms (rule_id, direction, term_kind, months)
  SELECT id, 'adverse', 'months_before_anchor', 0 FROM public.backbilling_rules WHERE state_code = 'ZZ' LIMIT 1;
  RAISE NOTICE 'P22 OBSERVED: months=0 accepted';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'P22 OBSERVED: no way to state a window in days or billing periods; months integer > 0 only (% %)', SQLSTATE, SQLERRM;
END $$;

-- ---------------------------------------------------------------- P23 (Q1)
-- Columns the law rows / evidence lack (checked by catalogue, no DDL).
DO $$ DECLARE missing text[]; BEGIN
  SELECT array_agg(c) INTO missing FROM unnest(ARRAY['refund_interest_required','interest_rate_basis','repayment_period_terms','notice_required','de_minimis_amount']) c
   WHERE NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'backbilling_rules' AND column_name = c);
  RAISE NOTICE 'P23 OBSERVED: backbilling_rules has no column for: %', missing;
  SELECT array_agg(c) INTO missing FROM unnest(ARRAY['interest_amount','estimation_basis']) c
   WHERE NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'meter_correction_period_evidence' AND column_name = c);
  RAISE NOTICE 'P23b OBSERVED: meter_correction_period_evidence has no column for: %', missing;
END $$;

-- ---------------------------------------------------------------- P12 (Q2)
-- caller-supplied updated_at on case INSERT
SET LOCAL app.user_id = '00000000-0000-4000-8000-0000000013b1';
SET ROLE tally_app;
DO $$ DECLARE c public.meter_correction_cases%ROWTYPE; BEGIN
  INSERT INTO public.meter_correction_cases (tenant_id, meter_id, cause, anchor_date, anchor_basis, claimed_from, updated_at)
  VALUES ('00000000-0000-4000-8000-0000000013a1', '00000000-0000-4000-8000-0000000013e9', 'crossed_meters', DATE '2026-05-01',
          'discovery_date', DATE '2026-01-01', TIMESTAMPTZ '2000-01-01') RETURNING * INTO c;
  RAISE NOTICE 'P12 OBSERVED: case inserted with caller updated_at = %', c.updated_at;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'P12 OBSERVED: refused % %', SQLSTATE, SQLERRM;
END $$;
RESET ROLE;
ROLLBACK;
