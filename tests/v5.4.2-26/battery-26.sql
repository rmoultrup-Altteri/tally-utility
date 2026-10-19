-- ============================================================================
-- BATTERY v5.4.2-26 — collections decisions and field verification (2026-10-19)
-- Run: psql -U tally -d <db-with-23-25-26> -v ON_ERROR_STOP=1 -f battery-26.sql
-- One transaction, rolled back. Fixtures as the owner; every guard the
-- application meets is exercised as tally_app under app.user_id.
-- Each check names its requirement in
-- application/wave3-build-2026-10-18/v5.4.2-26-design.md.
--
--   V  vocabulary, grants, columns           C  the decision record (C2-C5)
--   A  acts cite their decision (C7)         E  dunning keys, stage, projections (E1-E4)
--   F  field visits, approvals, orders (F1-F4)
--   H  history, grants, tenancy, invariants
--
-- Written before the patch: it fails first, at the first object -26 creates.
--
-- Contract the patch must meet (names fixed here):
--   tables  collections_conditions (condition_code, kind, description)
--           collections_decisions (tenant_id, customer_id, act, invoice_id, location_id, meter_id,
--             evaluation_date, outcome, active_conditions, unevaluable_conditions, governing_condition,
--             valid_until, supersedes_id, inputs, inputs_fingerprint, calculated_by, record_seq,
--             recorded_txid, created_at, created_by)
--           service_order_field_visits (tenant_id, service_order_id, arrived_at, captured_meter_serial,
--             captured_location_number, expected_location_id, expected_location_number, expected_meter_id,
--             expected_meter_serial, matched, outcome, abort_reason, collections_decision_id,
--             mismatch_approval_id, no_evidence_approval_id, evidence_refs, record_seq, created_at, created_by)
--           service_order_field_approvals (tenant_id, service_order_id, kind, visit_id, reason_code,
--             evidence_ref, approved_by, created_at)
--   columns dunning_events.collections_decision_id, adhoc_charges.collections_decision_id,
--           service_orders.collections_decision_id
--   Every refusal the patch raises itself names its requirement in brackets,
--   e.g. "[C3f]"; the checks below match on that tag. Constraint refusals
--   match on the constraint's name.
-- What one transaction cannot show (one live decision under two writers, an
-- act against a concurrent supersession, two acts on one decision, two
-- executed visits) is in races/collections-26.sh.
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
CREATE FUNCTION pg_temp.admits_undone(p_label text, p_sql text) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  BEGIN
    EXECUTE p_sql;
    RAISE EXCEPTION 'undo' USING ERRCODE = 'P0098';
  EXCEPTION WHEN SQLSTATE 'P0098' THEN
    RAISE NOTICE 'PASS %', p_label;
    RETURN;
  WHEN OTHERS THEN
    RAISE EXCEPTION 'FAIL %: refused with % (%)', p_label, SQLSTATE, SQLERRM;
  END;
END $$;
-- u('c1') is the fixture uuid ending 26c1; id('name') a named record's uuid.
CREATE FUNCTION pg_temp.u(p_code text) RETURNS uuid LANGUAGE sql IMMUTABLE AS $$ SELECT ('00000000-0000-4000-8000-00000000' || '26' || p_code)::uuid $$;
CREATE FUNCTION pg_temp.id(p_name text) RETURNS uuid LANGUAGE sql IMMUTABLE AS $$ SELECT CASE WHEN p_name IS NULL THEN NULL ELSE md5('b26/' || p_name)::uuid END $$;
-- The database's current date, as -26 reads it (UTC).
CREATE FUNCTION pg_temp.today() RETURNS date LANGUAGE sql STABLE AS $$ SELECT (now() AT TIME ZONE 'UTC')::date $$;
CREATE FUNCTION pg_temp.as_user(p_code text) RETURNS void LANGUAGE sql AS $$ SELECT set_config('app.user_id', pg_temp.u(p_code)::text, true) $$;

-- dec(): a decision, as SQL. p_sup names the decision it supersedes.
CREATE FUNCTION pg_temp.dec(p_name text, p_act text, p_customer text, p_invoice text, p_loc text, p_meter text,
                            p_eval date, p_outcome text, p_active text[], p_uneval text[], p_gov text, p_until date,
                            p_sup text, p_fp text, p_tenant text DEFAULT 'a1') RETURNS text LANGUAGE sql STABLE AS $$
  SELECT format($q$INSERT INTO public.collections_decisions (id, tenant_id, customer_id, act, invoice_id, location_id, meter_id,
                     evaluation_date, outcome, active_conditions, unevaluable_conditions, governing_condition, valid_until,
                     supersedes_id, inputs, inputs_fingerprint, calculated_by)
                   VALUES (%L, %L, %L, %L, %L, %L, %L, %L, %L, %L::text[], %L::text[], %L, %L, %L, '{"bat26": true}', %L, 'core bat26')$q$,
                pg_temp.id(p_name), pg_temp.u(p_tenant), pg_temp.u(p_customer), p_act,
                CASE WHEN p_invoice IS NULL THEN NULL ELSE pg_temp.u(p_invoice) END,
                CASE WHEN p_loc IS NULL THEN NULL ELSE pg_temp.u(p_loc) END,
                CASE WHEN p_meter IS NULL THEN NULL ELSE pg_temp.u(p_meter) END,
                p_eval, p_outcome, coalesce(p_active, '{}'), coalesce(p_uneval, '{}'), p_gov, p_until, pg_temp.id(p_sup), p_fp)
$$;
-- ev(): a dunning event, as SQL.
CREATE FUNCTION pg_temp.ev(p_name text, p_invoice text, p_customer text, p_type text, p_at timestamptz, p_dec text,
                           p_new text DEFAULT NULL, p_prev text DEFAULT NULL) RETURNS text LANGUAGE sql STABLE AS $$
  SELECT format($q$INSERT INTO public.dunning_events (id, tenant_id, invoice_id, customer_id, event_type, event_date, collections_decision_id, new_stage, previous_stage)
                   VALUES (%L, %L, %L, %L, %L, %L, %L, %L, %L)$q$,
                pg_temp.id(p_name), pg_temp.u('a1'), pg_temp.u(p_invoice), pg_temp.u(p_customer), p_type, p_at, pg_temp.id(p_dec), p_new, p_prev)
$$;
-- chg(): an adhoc charge, as SQL.
CREATE FUNCTION pg_temp.chg(p_name text, p_customer text, p_invoice text, p_eff date, p_dec text, p_type text DEFAULT 'late_fee') RETURNS text LANGUAGE sql STABLE AS $$
  SELECT format($q$INSERT INTO public.adhoc_charges (id, tenant_id, charge_number, customer_id, charge_type, description, amount, regulatory_class,
                     effective_date, triggered_by_invoice_id, collections_decision_id)
                   VALUES (%L, %L, %L, %L, %L, 'bat26 charge', 5.00, 'regulated', %L, %L, %L)$q$,
                pg_temp.id(p_name), pg_temp.u('a1'), 'B26-' || p_name, pg_temp.u(p_customer), p_type, p_eff,
                CASE WHEN p_invoice IS NULL THEN NULL ELSE pg_temp.u(p_invoice) END, pg_temp.id(p_dec))
$$;
-- so(): a service order, as SQL.
CREATE FUNCTION pg_temp.so(p_name text, p_customer text, p_loc text, p_meter text, p_dec text,
                           p_type text DEFAULT 'disconnect', p_status text DEFAULT 'open') RETURNS text LANGUAGE sql STABLE AS $$
  SELECT format($q$INSERT INTO public.service_orders (id, tenant_id, order_number, order_type, status, description, customer_id, location_id, meter_id, collections_decision_id)
                   VALUES (%L, %L, %L, %L, %L, 'bat26 order', %L, %L, %L, %L)$q$,
                pg_temp.id(p_name), pg_temp.u('a1'), 'B26-' || p_name, p_type, p_status, pg_temp.u(p_customer), pg_temp.u(p_loc),
                CASE WHEN p_meter IS NULL THEN NULL ELSE pg_temp.u(p_meter) END, pg_temp.id(p_dec))
$$;
-- visit(): a field visit, as SQL.
CREATE FUNCTION pg_temp.visit(p_name text, p_order text, p_at timestamptz, p_serial text, p_locnum text, p_outcome text,
                              p_reason text, p_dec text, p_mm text, p_ne text, p_evidence text[], p_tenant text DEFAULT 'a1') RETURNS text LANGUAGE sql STABLE AS $$
  SELECT format($q$INSERT INTO public.service_order_field_visits (id, tenant_id, service_order_id, arrived_at, captured_meter_serial, captured_location_number,
                     outcome, abort_reason, collections_decision_id, mismatch_approval_id, no_evidence_approval_id, evidence_refs)
                   VALUES (%L, %L, %L, %L, %L, %L, %L, %L, %L, %L, %L, %L::text[])$q$,
                pg_temp.id(p_name), pg_temp.u(p_tenant), pg_temp.id(p_order), p_at, p_serial, p_locnum, p_outcome, p_reason,
                pg_temp.id(p_dec), pg_temp.id(p_mm), pg_temp.id(p_ne), coalesce(p_evidence, '{}'))
$$;
-- appr(): a supervisor's approval, as SQL.
CREATE FUNCTION pg_temp.appr(p_name text, p_order text, p_kind text, p_visit text, p_reason text, p_evidence text,
                             p_approved_by text DEFAULT NULL, p_tenant text DEFAULT 'a1') RETURNS text LANGUAGE sql STABLE AS $$
  SELECT format($q$INSERT INTO public.service_order_field_approvals (id, tenant_id, service_order_id, kind, visit_id, reason_code, evidence_ref, approved_by)
                   VALUES (%L, %L, %L, %L, %L, %L, %L, %L)$q$,
                pg_temp.id(p_name), pg_temp.u(p_tenant), pg_temp.id(p_order), p_kind, pg_temp.id(p_visit), p_reason, p_evidence,
                CASE WHEN p_approved_by IS NULL THEN NULL ELSE pg_temp.u(p_approved_by) END)
$$;
-- snap(), bill(): an issued bill (as battery-25).
CREATE FUNCTION pg_temp.snap(p_inv uuid, p_valid date, p_rec timestamptz) RETURNS void LANGUAGE plpgsql AS $$
DECLARE i public.invoices%ROWTYPE;
BEGIN
  SELECT * INTO i FROM public.invoices WHERE id = p_inv;
  INSERT INTO public.invoice_calculation_snapshots
    (tenant_id, invoice_id, billing_run_id, valid_at, recorded_at, snapshot_schema_version, formula_version,
     rate_inputs, gas_factors, wna_inputs, tax_inputs, read_inputs, customer_inputs, period_inputs, line_items)
  VALUES (i.tenant_id, i.id, i.billing_run_id, p_valid, p_rec, 'v1', 'bat26',
     '{"rate_schedule_id":null,"rate_schedule_version_id":null,"rate_schedule_code":null,"customer_type":null,"partial_period_policy":null,"items":[]}',
     '{"pga_factor":null,"btu_factor":null,"pressure_factor":null,"temperature_factor":null,"meter_multiplier":null,"factor_stack_intermediates":{}}',
     '{"applied":false}', '{"jurisdictions":[],"exemptions":[],"franchise_fees":[]}', '{"reads":[]}',
     jsonb_build_object('customer_id', i.customer_id, 'customer_class', null, 'location_id', i.location_id, 'premise_zones', '{}'::jsonb),
     jsonb_build_object('period_start', i.period_start, 'period_end', i.period_end, 'days_in_period', i.period_end - i.period_start + 1, 'proration_policy', null),
     (SELECT coalesce(jsonb_agg(jsonb_build_object('invoice_line_item_id', l.id, 'charge_type', l.charge_type, 'amount', l.amount)), '[]'::jsonb)
        FROM public.invoice_line_items l WHERE l.invoice_id = i.id));
END $$;
CREATE FUNCTION pg_temp.bill(p_tenant uuid, p_id uuid, p_num text, p_customer uuid, p_loc uuid, p_issue boolean) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO public.invoices (id, tenant_id, invoice_number, customer_id, location_id, is_consolidated, invoice_date, billing_period, period_start, period_end, due_date, amount_due)
  VALUES (p_id, p_tenant, p_num, p_customer, p_loc, p_loc IS NULL, DATE '2026-03-01', '2026-02', DATE '2026-02-01', DATE '2026-02-28', DATE '2026-03-20', 60.00);
  INSERT INTO public.invoice_line_items (tenant_id, invoice_id, line_order, service_type, charge_type, description, amount, rate, regulatory_class)
  VALUES (p_tenant, p_id, 0, 'gas', 'base_charge', 'Gas service', 60.00, 60.00, 'regulated');
  IF p_issue THEN
    PERFORM pg_temp.snap(p_id, DATE '2026-02-28', now());
    UPDATE public.invoices SET status = 'pending' WHERE id = p_id;
  END IF;
END $$;
DO $$
DECLARE f regprocedure;
BEGIN
  FOR f IN SELECT p.oid::regprocedure FROM pg_proc p WHERE p.pronamespace = pg_my_temp_schema() LOOP
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO tally_app', f);
  END LOOP;
END $$;

-- ------------------------------------------------------------------ fixtures
-- T1 (a1) a Texas city gas system; T2 (a2) another utility.
-- b1 an operator (the field tech's and the core's session), b2 a tenant_admin
-- (a supervisor), b3 T2's operator. c1, c2 T1's customers; c3 T2's.
-- Locations: d1 L1 (c1, meter e1), d2 L2 (c2, meter e2), d4 L4 (c1, no meter),
-- d5 L5 (c1: e5 until April 1, e7 from April 1), d6 L6 (c1: two meters, e8
-- and e9), d3 L3 (T2's). Bills 01 (c1 at d1), 02 (c1, no location), 03 (c2
-- at d2), 04 (c1, a draft), 05 (T2's). A bill with no location is a
-- consolidated one (invoices_check).
INSERT INTO public.tenants (id, name, slug) VALUES
  (pg_temp.u('a1'), 'T1 City Gas 26', 'bat26-t1'),
  (pg_temp.u('a2'), 'T2 Gas 26', 'bat26-t2');
INSERT INTO public.users (id, tenant_id, display_name, email, role, is_active) VALUES
  (pg_temp.u('b1'), pg_temp.u('a1'), 'Op1', 'op1@bat26.test', 'operator', true),
  (pg_temp.u('b2'), pg_temp.u('a1'), 'Sup1', 'sup1@bat26.test', 'tenant_admin', true),
  (pg_temp.u('b3'), pg_temp.u('a2'), 'Op3', 'op3@bat26.test', 'operator', true);
INSERT INTO public.customers (id, tenant_id, customer_number, customer_type) VALUES
  (pg_temp.u('c1'), pg_temp.u('a1'), 'B26-C1', 'residential'),
  (pg_temp.u('c2'), pg_temp.u('a1'), 'B26-C2', 'residential'),
  (pg_temp.u('c3'), pg_temp.u('a2'), 'B26-C3', 'residential');
INSERT INTO public.service_locations (id, tenant_id, customer_id, location_number, address_line1, city, state, zip) VALUES
  (pg_temp.u('d1'), pg_temp.u('a1'), pg_temp.u('c1'), 'L1', '1 Main', 'Brenham', 'TX', '77833'),
  (pg_temp.u('d2'), pg_temp.u('a1'), pg_temp.u('c2'), 'L2', '2 Main', 'Brenham', 'TX', '77833'),
  (pg_temp.u('d4'), pg_temp.u('a1'), pg_temp.u('c1'), 'L4', '4 Main', 'Brenham', 'TX', '77833'),
  (pg_temp.u('d5'), pg_temp.u('a1'), pg_temp.u('c1'), 'L5', '5 Main', 'Brenham', 'TX', '77833'),
  (pg_temp.u('d6'), pg_temp.u('a1'), pg_temp.u('c1'), 'L6', '6 Main', 'Brenham', 'TX', '77833'),
  (pg_temp.u('d3'), pg_temp.u('a2'), pg_temp.u('c3'), 'L3', '3 Main', 'Austin', 'TX', '78701');
INSERT INTO public.meters (id, tenant_id, meter_number, serial_number, location_id, service_type, start_date) VALUES
  (pg_temp.u('e1'), pg_temp.u('a1'), 'B26-M1', 'SN-E1', pg_temp.u('d1'), 'gas', DATE '2020-01-01'),
  (pg_temp.u('e2'), pg_temp.u('a1'), 'B26-M2', 'SN-E2', pg_temp.u('d2'), 'gas', DATE '2020-01-01'),
  (pg_temp.u('e5'), pg_temp.u('a1'), 'B26-M5', 'SN-E5', pg_temp.u('d5'), 'gas', DATE '2020-01-01'),
  (pg_temp.u('e8'), pg_temp.u('a1'), 'B26-M8', 'SN-E8', pg_temp.u('d6'), 'gas', DATE '2020-01-01'),
  (pg_temp.u('e9'), pg_temp.u('a1'), 'B26-M9', 'SN-E9', pg_temp.u('d6'), 'gas', DATE '2020-01-01'),
  (pg_temp.u('e3'), pg_temp.u('a2'), 'B26-M3', 'SN-E3', pg_temp.u('d3'), 'gas', DATE '2020-01-01');
-- e5 came out of L5 on April 1 (the owner's history path) and e7 went in.
UPDATE public.meter_deployments SET removal_date = DATE '2026-04-01', removal_reason = 'upgrade_size' WHERE meter_id = pg_temp.u('e5');
INSERT INTO public.meters (id, tenant_id, meter_number, serial_number, location_id, service_type, start_date) VALUES
  (pg_temp.u('e7'), pg_temp.u('a1'), 'B26-M7', 'SN-E7', pg_temp.u('d5'), 'gas', DATE '2026-04-01');
SELECT pg_temp.bill(pg_temp.u('a1'), pg_temp.u('01'), 'B26-I1', pg_temp.u('c1'), pg_temp.u('d1'), true);
SELECT pg_temp.bill(pg_temp.u('a1'), pg_temp.u('02'), 'B26-I2', pg_temp.u('c1'), NULL, true);
SELECT pg_temp.bill(pg_temp.u('a1'), pg_temp.u('03'), 'B26-I3', pg_temp.u('c2'), pg_temp.u('d2'), true);
SELECT pg_temp.bill(pg_temp.u('a1'), pg_temp.u('04'), 'B26-I4', pg_temp.u('c1'), pg_temp.u('d1'), false);
SELECT pg_temp.bill(pg_temp.u('a2'), pg_temp.u('05'), 'B26-I5', pg_temp.u('c3'), pg_temp.u('d3'), true);


-- ============================================================== V vocabulary, grants, columns
SELECT pg_temp.ok('V1 the conditions vocabulary names the protections, the bars and the missing rule (C1)',
  (SELECT array_agg(condition_code ORDER BY condition_code) FROM public.collections_conditions)
  = ARRAY['agency_pledge', 'aged_suspense', 'arrears_below_floor', 'bankruptcy_stay', 'closed_day', 'deceased_hold', 'dispute',
          'elderly_due_date_delay', 'medical_hold', 'military_scra', 'no_rule_in_force', 'non_disconnectable_debt',
          'notice_sequence_incomplete', 'payment_arrangement', 'payment_pending', 'protected_status', 'regulatory_moratorium',
          'tariff_protection', 'third_party_notice_pending', 'weather_moratorium']);
SELECT pg_temp.ok('V2 each condition has its kind: a protection, a bar or a missing rule',
  NOT EXISTS (SELECT 1 FROM public.collections_conditions WHERE kind NOT IN ('protection', 'bar', 'rule'))
  AND (SELECT kind FROM public.collections_conditions WHERE condition_code = 'no_rule_in_force') = 'rule'
  AND (SELECT kind FROM public.collections_conditions WHERE condition_code = 'dispute') = 'protection'
  AND (SELECT kind FROM public.collections_conditions WHERE condition_code = 'closed_day') = 'bar');
SELECT pg_temp.refuses_at('V3 the vocabulary is never edited', $q$UPDATE public.collections_conditions SET description = 'x' WHERE condition_code = 'dispute'$q$, '23001', 'collections_conditions');
SELECT pg_temp.ok('V4 the application writes decisions, visits and approvals, and updates or deletes none of them',
  (SELECT bool_and(has_table_privilege('tally_app', t, 'INSERT') AND has_table_privilege('tally_app', t, 'SELECT')
                   AND NOT has_table_privilege('tally_app', t, 'UPDATE') AND NOT has_table_privilege('tally_app', t, 'DELETE')
                   AND NOT has_table_privilege('tally_app', t, 'TRUNCATE'))
     FROM unnest(ARRAY['public.collections_decisions', 'public.service_order_field_visits', 'public.service_order_field_approvals']) t));
SELECT pg_temp.ok('V5 tally_core reads them and writes none',
  (SELECT bool_and(has_table_privilege('tally_core', t, 'SELECT') AND NOT has_table_privilege('tally_core', t, 'INSERT'))
     FROM unnest(ARRAY['public.collections_decisions', 'public.service_order_field_visits', 'public.service_order_field_approvals',
                       'public.collections_conditions']) t));
SELECT pg_temp.ok('V6 the bill''s late-fee counters are gone (E3: derive, do not store)',
  NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'invoices'
                 AND column_name IN ('late_fee_assessed', 'late_fee_amount')));
SELECT pg_temp.ok('V7 dunning events, charges and service orders can cite a decision (C7)',
  (SELECT count(*) = 3 FROM information_schema.columns WHERE table_schema = 'public' AND column_name = 'collections_decision_id'
      AND table_name IN ('dunning_events', 'adhoc_charges', 'service_orders')));


-- ============================================================== C the decision record (C2-C5)
SET ROLE tally_app;
SELECT pg_temp.as_user('b1');
SELECT pg_temp.admits('C0 a notice decision: bill 01 at its location L1, eligible April 2 to 20',
  pg_temp.dec('D1', 'notice', 'c1', '01', 'd1', NULL, DATE '2026-04-02', 'eligible', NULL, NULL, NULL, DATE '2026-04-20', NULL, 'f1'));
SELECT pg_temp.ok('C0b the database stamps who and when, the transaction and the order',
  (SELECT created_by = pg_temp.u('b1') AND created_at = now() AND recorded_txid = txid_current() AND record_seq IS NOT NULL
     FROM public.collections_decisions WHERE id = pg_temp.id('D1')));
-- C3a the subject's shape, act by act.
SELECT pg_temp.refuses_at('C3a1 a notice names the service it threatens (CCK-7)',
  pg_temp.dec('x', 'notice', 'c1', '01', NULL, NULL, DATE '2026-04-02', 'eligible', NULL, NULL, NULL, DATE '2026-04-20', NULL, 'x'), '23514', '[C3a]');
SELECT pg_temp.refuses_at('C3a2 a late fee is the bill''s alone: no location',
  pg_temp.dec('x', 'late_fee', 'c1', '01', 'd1', NULL, DATE '2026-04-02', 'eligible', NULL, NULL, NULL, DATE '2026-04-20', NULL, 'x'), '23514', '[C3a]');
SELECT pg_temp.refuses_at('C3a3 a disconnect order names no bill',
  pg_temp.dec('x', 'disconnect_order', 'c1', '01', 'd1', NULL, DATE '2026-04-02', 'eligible', NULL, NULL, NULL, DATE '2026-04-20', NULL, 'x'), '23514', '[C3a]');
SELECT pg_temp.refuses_at('C3a4 a late fee names its bill',
  pg_temp.dec('x', 'late_fee', 'c1', NULL, NULL, NULL, DATE '2026-04-02', 'eligible', NULL, NULL, NULL, DATE '2026-04-20', NULL, 'x'), '23514', '[C3a]');
SELECT pg_temp.refuses_at('C3a5 an execute decision names its location',
  pg_temp.dec('x', 'disconnect_execute', 'c1', NULL, NULL, NULL, DATE '2026-04-02', 'eligible', NULL, NULL, NULL, DATE '2026-04-02', NULL, 'x'), '23514', '[C3a]');
SELECT pg_temp.refuses_at('C3a6 a referral names no meter',
  pg_temp.dec('x', 'collections_referral', 'c1', '01', NULL, 'e1', DATE '2026-04-02', 'eligible', NULL, NULL, NULL, DATE '2026-04-20', NULL, 'x'), '23514', '[C3a]');
SELECT pg_temp.refuses_at('C3b1 a decision about a bill never issued (04, a draft)',
  pg_temp.dec('x', 'late_fee', 'c1', '04', NULL, NULL, DATE '2026-04-02', 'eligible', NULL, NULL, NULL, DATE '2026-04-20', NULL, 'x'), '23514', '[C3b]');
SELECT pg_temp.refuses_at('C3b2 a decision about another customer''s bill (03 is C2''s)',
  pg_temp.dec('x', 'late_fee', 'c1', '03', NULL, NULL, DATE '2026-04-02', 'eligible', NULL, NULL, NULL, DATE '2026-04-20', NULL, 'x'), '23503', 'collections_decisions_invoice_fkey');
SELECT pg_temp.refuses_at('C3c a disconnect at another customer''s location (L2 is C2''s)',
  pg_temp.dec('x', 'disconnect_order', 'c1', NULL, 'd2', NULL, DATE '2026-04-02', 'eligible', NULL, NULL, NULL, DATE '2026-04-20', NULL, 'x'), '23514', '[C3c]');
SELECT pg_temp.refuses_at('C3d1 a notice for bill 01 threatening L4, not the bill''s own L1',
  pg_temp.dec('x', 'notice', 'c1', '01', 'd4', NULL, DATE '2026-04-02', 'eligible', NULL, NULL, NULL, DATE '2026-04-20', NULL, 'x'), '23514', '[C3d]');
SELECT pg_temp.admits_undone('C3d2 … a bill that names no location (02) may threaten any of the customer''s',
  pg_temp.dec('x', 'notice', 'c1', '02', 'd4', NULL, DATE '2026-04-02', 'eligible', NULL, NULL, NULL, DATE '2026-04-20', NULL, 'x'));
SELECT pg_temp.refuses_at('C3e1 a meter not deployed at the location (E2 is at L2)',
  pg_temp.dec('x', 'disconnect_order', 'c1', NULL, 'd1', 'e2', DATE '2026-04-02', 'eligible', NULL, NULL, NULL, DATE '2026-04-20', NULL, 'x'), '23514', '[C3e]');
SELECT pg_temp.admits_undone('C3e2 E5 at L5 on March 31, its last day there',
  pg_temp.dec('x', 'disconnect_order', 'c1', NULL, 'd5', 'e5', DATE '2026-03-31', 'eligible', NULL, NULL, NULL, DATE '2026-04-05', NULL, 'x'));
SELECT pg_temp.refuses_at('C3e3 … not on April 1, the day it came out',
  pg_temp.dec('x', 'disconnect_order', 'c1', NULL, 'd5', 'e5', DATE '2026-04-01', 'eligible', NULL, NULL, NULL, DATE '2026-04-05', NULL, 'x'), '23514', '[C3e]');
-- C3f the outcome's shape.
SELECT pg_temp.refuses_at('C3f1 eligible with an active condition',
  pg_temp.dec('x', 'late_fee', 'c1', '01', NULL, NULL, DATE '2026-04-02', 'eligible', '{dispute}', NULL, NULL, DATE '2026-04-20', NULL, 'x'), '23514', '[C3f]');
SELECT pg_temp.refuses_at('C3f2 eligible with a condition it could not evaluate',
  pg_temp.dec('x', 'late_fee', 'c1', '01', NULL, NULL, DATE '2026-04-02', 'eligible', NULL, '{weather_moratorium}', NULL, DATE '2026-04-20', NULL, 'x'), '23514', '[C3f]');
SELECT pg_temp.refuses_at('C3f3 eligible with no last day',
  pg_temp.dec('x', 'late_fee', 'c1', '01', NULL, NULL, DATE '2026-04-02', 'eligible', NULL, NULL, NULL, NULL, NULL, 'x'), '23514', '[C3f]');
SELECT pg_temp.refuses_at('C3f4 eligible until the day before it was evaluated',
  pg_temp.dec('x', 'late_fee', 'c1', '01', NULL, NULL, DATE '2026-04-02', 'eligible', NULL, NULL, NULL, DATE '2026-04-01', NULL, 'x'), '23514', '[C3f]');
SELECT pg_temp.admits_undone('C3f5 … until the day it was evaluated is fine',
  pg_temp.dec('x', 'late_fee', 'c1', '01', NULL, NULL, DATE '2026-04-02', 'eligible', NULL, NULL, NULL, DATE '2026-04-02', NULL, 'x'));
SELECT pg_temp.refuses_at('C3f6 blocked with nothing active',
  pg_temp.dec('x', 'late_fee', 'c1', '01', NULL, NULL, DATE '2026-04-02', 'blocked', NULL, NULL, NULL, NULL, NULL, 'x'), '23514', '[C3f]');
SELECT pg_temp.refuses_at('C3f7 blocked, crediting a condition that is not active',
  pg_temp.dec('x', 'late_fee', 'c1', '01', NULL, NULL, DATE '2026-04-02', 'blocked', '{dispute}', NULL, 'medical_hold', NULL, NULL, 'x'), '23514', '[C3f]');
SELECT pg_temp.refuses_at('C3f8 blocked, crediting nothing',
  pg_temp.dec('x', 'late_fee', 'c1', '01', NULL, NULL, DATE '2026-04-02', 'blocked', '{dispute}', NULL, NULL, NULL, NULL, 'x'), '23514', '[C3f]');
SELECT pg_temp.refuses_at('C3f9 blocked, with a last day (a block holds until the next decision)',
  pg_temp.dec('x', 'late_fee', 'c1', '01', NULL, NULL, DATE '2026-04-02', 'blocked', '{dispute}', NULL, 'dispute', DATE '2026-04-20', NULL, 'x'), '23514', '[C3f]');
SELECT pg_temp.refuses_at('C3f10 unevaluable with an active condition (a known bar is blocked)',
  pg_temp.dec('x', 'late_fee', 'c1', '01', NULL, NULL, DATE '2026-04-02', 'unevaluable', '{dispute}', '{weather_moratorium}', NULL, NULL, NULL, 'x'), '23514', '[C3f]');
SELECT pg_temp.refuses_at('C3f11 unevaluable with nothing it could not evaluate',
  pg_temp.dec('x', 'late_fee', 'c1', '01', NULL, NULL, DATE '2026-04-02', 'unevaluable', NULL, NULL, NULL, NULL, NULL, 'x'), '23514', '[C3f]');
SELECT pg_temp.refuses_at('C3f12 unevaluable, crediting a condition',
  pg_temp.dec('x', 'late_fee', 'c1', '01', NULL, NULL, DATE '2026-04-02', 'unevaluable', NULL, '{weather_moratorium}', 'weather_moratorium', NULL, NULL, 'x'), '23514', '[C3f]');
SELECT pg_temp.admits_undone('C3f13 blocked by a known bar while another is unknown',
  pg_temp.dec('x', 'late_fee', 'c1', '01', NULL, NULL, DATE '2026-04-02', 'blocked', '{dispute}', '{weather_moratorium}', 'dispute', NULL, NULL, 'x'));
SELECT pg_temp.admits_undone('C3f14 unevaluable: nothing known active, one unknown',
  pg_temp.dec('x', 'late_fee', 'c1', '01', NULL, NULL, DATE '2026-04-02', 'unevaluable', NULL, '{weather_moratorium}', NULL, NULL, NULL, 'x'));
SELECT pg_temp.refuses_at('C3g1 an active condition outside the vocabulary',
  pg_temp.dec('x', 'late_fee', 'c1', '01', NULL, NULL, DATE '2026-04-02', 'blocked', '{sunspots}', NULL, 'sunspots', NULL, NULL, 'x'), '23514', '[C3g]');
SELECT pg_temp.refuses_at('C3g2 a condition named twice',
  pg_temp.dec('x', 'late_fee', 'c1', '01', NULL, NULL, DATE '2026-04-02', 'blocked', '{dispute,dispute}', NULL, 'dispute', NULL, NULL, 'x'), '23514', '[C3g]');
SELECT pg_temp.refuses_at('C3g3 an unevaluable condition outside the vocabulary',
  pg_temp.dec('x', 'late_fee', 'c1', '01', NULL, NULL, DATE '2026-04-02', 'unevaluable', NULL, '{sunspots}', NULL, NULL, NULL, 'x'), '23514', '[C3g]');
SELECT pg_temp.refuses_at('C3h1 an execute decision holding past its own day',
  pg_temp.dec('x', 'disconnect_execute', 'c1', NULL, 'd5', NULL, DATE '2026-04-12', 'eligible', NULL, NULL, NULL, DATE '2026-04-13', NULL, 'x'), '23514', '[C3h]');
SELECT pg_temp.admits_undone('C3h2 … holding for its own day',
  pg_temp.dec('x', 'disconnect_execute', 'c1', NULL, 'd5', NULL, DATE '2026-04-12', 'eligible', NULL, NULL, NULL, DATE '2026-04-12', NULL, 'x'));
SELECT pg_temp.refuses_at('C3j1 a decision evaluated for tomorrow',
  pg_temp.dec('x', 'late_fee', 'c1', '01', NULL, NULL, pg_temp.today() + 1, 'eligible', NULL, NULL, NULL, pg_temp.today() + 2, NULL, 'x'), '23514', '[C3j]');
SELECT pg_temp.admits_undone('C3j2 … for today',
  pg_temp.dec('x', 'late_fee', 'c1', '01', NULL, NULL, pg_temp.today(), 'eligible', NULL, NULL, NULL, pg_temp.today() + 1, NULL, 'x'));
SELECT pg_temp.refuses_at('C3k a decision''s inputs are an object',
  $q$INSERT INTO public.collections_decisions (tenant_id, customer_id, act, invoice_id, evaluation_date, outcome, valid_until, inputs, inputs_fingerprint, calculated_by)
     VALUES ('00000000-0000-4000-8000-0000000026a1', '00000000-0000-4000-8000-0000000026c1', 'late_fee', '00000000-0000-4000-8000-000000002601',
             DATE '2026-04-02', 'eligible', DATE '2026-04-20', '[]', 'x', 'core')$q$, '23514', 'collections_decisions_inputs_check');
-- C4, C5 one live decision per act and subject; idempotent against it.
SELECT pg_temp.refuses_at('C4a1 a second decision for the notice on 01 at L1 that names no live row',
  pg_temp.dec('x', 'notice', 'c1', '01', 'd1', NULL, DATE '2026-04-03', 'eligible', NULL, NULL, NULL, DATE '2026-04-20', NULL, 'x'), '23514', '[C4a]');
SELECT pg_temp.refuses_at('C4a2 a first decision for another subject superseding D1',
  pg_temp.dec('x', 'notice', 'c1', '02', 'd4', NULL, DATE '2026-04-03', 'eligible', NULL, NULL, NULL, DATE '2026-04-20', 'D1', 'x'), '23514', '[C4a]');
SELECT pg_temp.admits('C4 D2 supersedes D1: on April 2 a dispute arrived (facts f2), so the notice is blocked',
  pg_temp.dec('D2', 'notice', 'c1', '01', 'd1', NULL, DATE '2026-04-02', 'blocked', '{dispute}', NULL, 'dispute', NULL, 'D1', 'f2'));
SELECT pg_temp.refuses_at('C4a3 superseding D1 again (no longer live)',
  pg_temp.dec('x', 'notice', 'c1', '01', 'd1', NULL, DATE '2026-04-02', 'eligible', NULL, NULL, NULL, DATE '2026-04-20', 'D1', 'x'), '23514', '[C4a]');
SELECT pg_temp.admits('C5b D3: the same day the facts return to f1 (the dispute withdrawn); A to B to A is recorded, not wedged',
  pg_temp.dec('D3', 'notice', 'c1', '01', 'd1', NULL, DATE '2026-04-02', 'eligible', NULL, NULL, NULL, DATE '2026-04-20', 'D2', 'f1'));
SELECT pg_temp.refuses_at('C5a the engine re-runs April 2 on the same facts (f1): refused, nothing changed',
  pg_temp.dec('x', 'notice', 'c1', '01', 'd1', NULL, DATE '2026-04-02', 'eligible', NULL, NULL, NULL, DATE '2026-04-20', 'D3', 'f1'), '23514', '[C5]');
SELECT pg_temp.admits_undone('C5c … April 3 on the same facts is a new evaluation',
  pg_temp.dec('x', 'notice', 'c1', '01', 'd1', NULL, DATE '2026-04-03', 'eligible', NULL, NULL, NULL, DATE '2026-04-20', 'D3', 'f1'));
SELECT pg_temp.refuses_at('C4b a successor evaluated before the live decision (April 1 after April 2)',
  pg_temp.dec('x', 'notice', 'c1', '01', 'd1', NULL, DATE '2026-04-01', 'eligible', NULL, NULL, NULL, DATE '2026-04-20', 'D3', 'f9'), '23514', '[C4b]');
SELECT pg_temp.admits('C4c a late fee on the same bill is another subject: its first decision names nothing (L1, April 5 to 10)',
  pg_temp.dec('L1', 'late_fee', 'c1', '01', NULL, NULL, DATE '2026-04-05', 'eligible', NULL, NULL, NULL, DATE '2026-04-10', NULL, 'l1'));


-- ============================================================== A acts cite their decision (C7)
SELECT pg_temp.admits('A0 decisions for the acts below', $q$SELECT 1$q$);
DO $$ BEGIN
  EXECUTE pg_temp.dec('R1', 'collections_referral', 'c1', '01', NULL, NULL, DATE '2026-04-05', 'blocked', '{bankruptcy_stay}', NULL, 'bankruptcy_stay', NULL, NULL, 'r1');
  EXECUTE pg_temp.dec('R2', 'collections_referral', 'c1', '02', NULL, NULL, DATE '2026-04-05', 'unevaluable', NULL, '{no_rule_in_force}', NULL, NULL, NULL, 'r2');
  EXECUTE pg_temp.dec('R3', 'collections_referral', 'c2', '03', NULL, NULL, DATE '2026-04-05', 'eligible', NULL, NULL, NULL, DATE '2026-04-30', NULL, 'r3');
  EXECUTE pg_temp.dec('O1', 'disconnect_order', 'c2', NULL, 'd2', 'e2', pg_temp.today(), 'eligible', NULL, NULL, NULL, pg_temp.today() + 7, NULL, 'o1');
  EXECUTE pg_temp.dec('O1b', 'disconnect_order', 'c1', NULL, 'd5', NULL, pg_temp.today(), 'eligible', NULL, NULL, NULL, pg_temp.today() + 7, NULL, 'o1b');
  EXECUTE pg_temp.dec('O2', 'disconnect_order', 'c1', NULL, 'd4', NULL, pg_temp.today(), 'eligible', NULL, NULL, NULL, pg_temp.today() + 7, NULL, 'o2');
  EXECUTE pg_temp.dec('O3', 'disconnect_order', 'c1', NULL, 'd6', NULL, pg_temp.today() - 10, 'eligible', NULL, NULL, NULL, pg_temp.today() - 1, NULL, 'o3');
  EXECUTE pg_temp.dec('X0', 'disconnect_execute', 'c2', NULL, 'd2', NULL, DATE '2026-04-09', 'blocked', '{payment_pending}', NULL, 'payment_pending', NULL, NULL, 'x0');
  EXECUTE pg_temp.dec('X1', 'disconnect_execute', 'c2', NULL, 'd2', NULL, DATE '2026-04-10', 'eligible', NULL, NULL, NULL, DATE '2026-04-10', 'X0', 'x1');
  EXECUTE pg_temp.dec('X2', 'disconnect_execute', 'c1', NULL, 'd5', NULL, DATE '2026-04-12', 'eligible', NULL, NULL, NULL, DATE '2026-04-12', NULL, 'x2');
END $$;
-- The notice (the event is the act: the live decision).
SELECT pg_temp.refuses_at('A1a a shutoff notice with no decision',
  pg_temp.ev('x', '01', 'c1', 'shutoff_notice_sent', TIMESTAMPTZ '2026-04-10 12:00Z', NULL), '23514', '[A1]');
SELECT pg_temp.refuses_at('A1b a reminder citing a decision (reminders are not gated)',
  pg_temp.ev('x', '01', 'c1', 'reminder_sent', TIMESTAMPTZ '2026-04-10 12:00Z', 'D3'), '23514', '[A1]');
SELECT pg_temp.refuses_at('A2a a shutoff notice citing a late-fee decision',
  pg_temp.ev('x', '01', 'c1', 'shutoff_notice_sent', TIMESTAMPTZ '2026-04-06 12:00Z', 'L1'), '23514', '[A2]');
SELECT pg_temp.refuses_at('A3a a referral citing a blocked decision',
  pg_temp.ev('x', '01', 'c1', 'sent_to_collections', TIMESTAMPTZ '2026-04-06 12:00Z', 'R1'), '23514', '[A3]');
SELECT pg_temp.refuses_at('A3b a referral citing an unevaluable decision (unevaluable blocks, C6)',
  pg_temp.ev('x', '02', 'c1', 'sent_to_collections', TIMESTAMPTZ '2026-04-06 12:00Z', 'R2'), '23514', '[A3]');
SELECT pg_temp.refuses_at('A4a a shutoff notice citing D1, which D2 superseded',
  pg_temp.ev('x', '01', 'c1', 'shutoff_notice_sent', TIMESTAMPTZ '2026-04-10 12:00Z', 'D1'), '23514', '[A4]');
SELECT pg_temp.refuses_at('A5a a notice for bill 02 citing the decision for bill 01',
  pg_temp.ev('x', '02', 'c1', 'shutoff_notice_sent', TIMESTAMPTZ '2026-04-10 12:00Z', 'D3'), '23514', '[A5]');
SELECT pg_temp.refuses_at('A6a a notice the day after the decision''s last day (April 21)',
  pg_temp.ev('x', '01', 'c1', 'shutoff_notice_sent', TIMESTAMPTZ '2026-04-21 00:00Z', 'D3'), '23514', '[A6]');
SELECT pg_temp.refuses_at('A6b a notice the day before the decision was evaluated (April 1)',
  pg_temp.ev('x', '01', 'c1', 'shutoff_notice_sent', TIMESTAMPTZ '2026-04-01 23:59Z', 'D3'), '23514', '[A6]');
SELECT pg_temp.admits('A6c the notice on April 20, the decision''s last day',
  pg_temp.ev('N1', '01', 'c1', 'shutoff_notice_sent', TIMESTAMPTZ '2026-04-20 23:59Z', 'D3'));
SELECT pg_temp.ok('A6d the database moved bill 01 to shutoff_warning and wrote both stages on the event (E2)',
  (SELECT dunning_stage FROM public.invoices WHERE id = pg_temp.u('01')) = 'shutoff_warning'
  AND (SELECT previous_stage = 'current' AND new_stage = 'shutoff_warning' FROM public.dunning_events WHERE id = pg_temp.id('N1')));
SELECT pg_temp.refuses_at('A7a a second notice on the same decision',
  pg_temp.ev('x', '01', 'c1', 'shutoff_notice_sent', TIMESTAMPTZ '2026-04-12 12:00Z', 'D3'), '23505', 'dunning_events_one_per_decision');
-- The late fee: the charge is the act; the event logs it.
SELECT pg_temp.refuses_at('A8a a late fee logged before any late-fee charge cites its decision',
  pg_temp.ev('x', '01', 'c1', 'late_fee_applied', TIMESTAMPTZ '2026-04-06 12:00Z', 'L1'), '23514', '[A8]');
SELECT pg_temp.refuses_at('A1c a late-fee charge with no decision',
  pg_temp.chg('x', 'c1', '01', DATE '2026-04-06', NULL), '23514', '[A1]');
SELECT pg_temp.refuses_at('A1d another kind of charge citing a decision',
  pg_temp.chg('x', 'c1', '01', DATE '2026-04-06', 'L1', 'miscellaneous'), '23514', '[A1]');
SELECT pg_temp.admits('A1e … another kind of charge, with no decision, as before',
  pg_temp.chg('misc', 'c1', '01', DATE '2026-04-06', NULL, 'miscellaneous'));
SELECT pg_temp.refuses_at('A2b a late-fee charge citing the notice decision',
  pg_temp.chg('x', 'c1', '01', DATE '2026-04-06', 'D3'), '23514', '[A2]');
SELECT pg_temp.refuses_at('A5c a late-fee charge on bill 02 citing bill 01''s decision',
  pg_temp.chg('x', 'c1', '02', DATE '2026-04-06', 'L1'), '23514', '[A5]');
SELECT pg_temp.refuses_at('A5d a late-fee charge that names no bill',
  pg_temp.chg('x', 'c1', NULL, DATE '2026-04-06', 'L1'), '23514', '[A5]');
SELECT pg_temp.refuses_at('A6e a late-fee charge dated April 11, after its decision''s last day',
  pg_temp.chg('x', 'c1', '01', DATE '2026-04-11', 'L1'), '23514', '[A6]');
SELECT pg_temp.admits('A6f the late-fee charge dated April 10',
  pg_temp.chg('LF1', 'c1', '01', DATE '2026-04-10', 'L1'));
SELECT pg_temp.refuses_at('A7b a second late fee on the same decision',
  pg_temp.chg('x', 'c1', '01', DATE '2026-04-10', 'L1'), '23505', 'adhoc_charges_one_per_decision');
SELECT pg_temp.admits('A4b the next day''s sweep supersedes L1 (a dispute: blocked)',
  pg_temp.dec('L2', 'late_fee', 'c1', '01', NULL, NULL, DATE '2026-04-06', 'blocked', '{dispute}', NULL, 'dispute', NULL, 'L1', 'l2'));
SELECT pg_temp.refuses_at('A4c a late-fee charge citing L1 now (the charge is the act: the live decision)',
  pg_temp.chg('x', 'c1', '01', DATE '2026-04-06', 'L1'), '23514', '[A4]');
SELECT pg_temp.admits('A8b … but the charge already made is logged against L1 (its log needs the charge, not a live decision)',
  pg_temp.ev('LE1', '01', 'c1', 'late_fee_applied', TIMESTAMPTZ '2026-04-06 12:00Z', 'L1'));
SELECT pg_temp.ok('A8c bill 01 is at late_fee_assessed',
  (SELECT dunning_stage FROM public.invoices WHERE id = pg_temp.u('01')) = 'late_fee_assessed');
-- The disconnect order: the order is the act; shutoff_scheduled logs it.
SELECT pg_temp.refuses_at('A1f a disconnect order with no decision',
  pg_temp.so('x', 'c2', 'd2', 'e2', NULL), '23514', '[A1]');
SELECT pg_temp.refuses_at('A1g another kind of order citing a decision',
  pg_temp.so('x', 'c2', 'd2', 'e2', 'O1', 'meter_test'), '23514', '[A1]');
SELECT pg_temp.refuses_at('A2c a disconnect order citing an execute decision',
  pg_temp.so('x', 'c2', 'd2', NULL, 'X1'), '23514', '[A2]');
SELECT pg_temp.refuses_at('A5e an order at L1 citing the decision for L5',
  pg_temp.so('x', 'c1', 'd1', NULL, 'O1b'), '23514', '[A5]');
SELECT pg_temp.refuses_at('A5f an order naming no meter, under a decision that names E2',
  pg_temp.so('x', 'c2', 'd2', NULL, 'O1'), '23514', '[A5]');
SELECT pg_temp.refuses_at('A5g C1''s order at C2''s location citing C2''s decision (the customer is the key''s)',
  pg_temp.so('x', 'c1', 'd2', 'e2', 'O1'), '23503', 'service_orders_decision_fkey');
SELECT pg_temp.refuses_at('A6g an order today under a decision whose window ended yesterday',
  pg_temp.so('x', 'c1', 'd6', NULL, 'O3'), '23514', '[A6]');
SELECT pg_temp.refuses_at('F4e a disconnect order born completed',
  pg_temp.so('x', 'c1', 'd4', NULL, 'O2', 'disconnect', 'completed'), '23514', '[F4e]');
SELECT pg_temp.admits('A6h SO1: C2''s disconnect at L2, meter E2, under O1',
  pg_temp.so('SO1', 'c2', 'd2', 'e2', 'O1'));
SELECT pg_temp.refuses_at('A7c a second order on the same decision',
  pg_temp.so('x', 'c2', 'd2', 'e2', 'O1'), '23505', 'service_orders_one_per_decision');
SELECT pg_temp.refuses_at('A8d a shutoff scheduled under a decision no order cites (O2)',
  pg_temp.ev('x', '01', 'c1', 'shutoff_scheduled', now(), 'O2'), '23514', '[A8]');
SELECT pg_temp.admits('A8e SO1''s shutoff logged on bill 03',
  pg_temp.ev('SE1', '03', 'c2', 'shutoff_scheduled', now(), 'O1'));
SELECT pg_temp.admits('A9 C2''s bill 03 referred to collections under R3',
  pg_temp.ev('RE1', '03', 'c2', 'sent_to_collections', TIMESTAMPTZ '2026-04-15 12:00Z', 'R3'));
SELECT pg_temp.ok('A9b bill 03 is at collections',
  (SELECT dunning_stage FROM public.invoices WHERE id = pg_temp.u('03')) = 'collections');


-- ============================================================== E dunning keys, stage, projections
SELECT pg_temp.refuses_at('E1a a dunning event naming C1 on C2''s bill',
  pg_temp.ev('x', '03', 'c1', 'reminder_sent', TIMESTAMPTZ '2026-04-10 12:00Z', NULL), '23503', 'dunning_events_invoice_id_fkey');
RESET ROLE;
SELECT pg_temp.refuses_at('E1b a T1 dunning event on T2''s bill and customer (the owner, past row security)',
  format($q$INSERT INTO public.dunning_events (tenant_id, invoice_id, customer_id, event_type) VALUES (%L, %L, %L, 'reminder_sent')$q$,
         pg_temp.u('a1'), pg_temp.u('05'), pg_temp.u('c3')), '23503', 'dunning_events_invoice_id_fkey');
SET ROLE tally_app;
SELECT pg_temp.as_user('b1');
SELECT pg_temp.admits('E2-1 reminder on bill 02', pg_temp.ev('S1', '02', 'c1', 'reminder_sent', TIMESTAMPTZ '2026-04-01 12:00Z', NULL));
SELECT pg_temp.admits('E2-2 a payment plan', pg_temp.ev('S2', '02', 'c1', 'payment_plan_created', TIMESTAMPTZ '2026-04-02 12:00Z', NULL));
SELECT pg_temp.admits('E2-3 the plan broken', pg_temp.ev('S3', '02', 'c1', 'payment_plan_broken', TIMESTAMPTZ '2026-04-03 12:00Z', NULL));
SELECT pg_temp.admits('E2-4 reconnected', pg_temp.ev('S4', '02', 'c1', 'reconnected', TIMESTAMPTZ '2026-04-04 12:00Z', NULL));
SELECT pg_temp.ok('E2-5 a broken plan and a reconnection move no stage: bill 02 stays at payment_plan, and those events carry no stages',
  (SELECT dunning_stage FROM public.invoices WHERE id = pg_temp.u('02')) = 'payment_plan'
  AND (SELECT bool_and(previous_stage IS NULL AND new_stage IS NULL) FROM public.dunning_events WHERE id IN (pg_temp.id('S3'), pg_temp.id('S4'))));
SELECT pg_temp.admits('E2-6 written off', pg_temp.ev('S5', '02', 'c1', 'written_off', TIMESTAMPTZ '2026-04-05 12:00Z', NULL));
SELECT pg_temp.admits('E2-7 resolved', pg_temp.ev('S6', '02', 'c1', 'resolved', TIMESTAMPTZ '2026-04-06 12:00Z', NULL));
SELECT pg_temp.ok('E2-8 each event moved bill 02 by the fixed mapping, the previous stage written by the database',
  (SELECT array_agg(previous_stage || '>' || new_stage ORDER BY event_date) FROM public.dunning_events
    WHERE invoice_id = pg_temp.u('02') AND new_stage IS NOT NULL)
  = ARRAY['current>reminder_sent', 'reminder_sent>payment_plan', 'payment_plan>written_off', 'written_off>resolved']
  AND (SELECT dunning_stage FROM public.invoices WHERE id = pg_temp.u('02')) = 'resolved');
SELECT pg_temp.refuses_at('E2a1 the application writes a bill''s stage directly',
  format($q$UPDATE public.invoices SET dunning_stage = 'current' WHERE id = %L$q$, pg_temp.u('02')), '23514', '[E2a]');
SELECT pg_temp.refuses_at('E2a2 a new bill born past current',
  format($q$INSERT INTO public.invoices (tenant_id, invoice_number, customer_id, location_id, invoice_date, billing_period, period_start, period_end, due_date, dunning_stage)
            VALUES (%L, 'B26-X', %L, %L, DATE '2026-03-01', '2026-02', DATE '2026-02-01', DATE '2026-02-28', DATE '2026-03-20', 'collections')$q$,
         pg_temp.u('a1'), pg_temp.u('c1'), pg_temp.u('d1')), '23514', '[E2a]');
SELECT pg_temp.refuses_at('E2b1 a reminder that claims to move the bill to disconnected',
  pg_temp.ev('x', '02', 'c1', 'reminder_sent', TIMESTAMPTZ '2026-04-07 12:00Z', NULL, 'disconnected'), '23514', '[E2b]');
SELECT pg_temp.refuses_at('E2b2 an event claiming the bill was at current (it is at resolved)',
  pg_temp.ev('x', '02', 'c1', 'reminder_sent', TIMESTAMPTZ '2026-04-07 12:00Z', NULL, 'reminder_sent', 'current'), '23514', '[E2b]');
SELECT pg_temp.refuses_at('E2b3 a reconnection that names a stage',
  pg_temp.ev('x', '02', 'c1', 'reconnected', TIMESTAMPTZ '2026-04-07 12:00Z', NULL, 'resolved'), '23514', '[E2b]');
SELECT pg_temp.admits('E2b4 … stages the caller gives that agree are kept',
  pg_temp.ev('S7', '02', 'c1', 'reminder_sent', TIMESTAMPTZ '2026-04-07 12:00Z', NULL, 'reminder_sent', 'resolved'));
RESET ROLE;
SELECT pg_temp.refuses_at('E2a3 the owner writes a bill''s stage directly too',
  format($q$UPDATE public.invoices SET dunning_stage = 'current' WHERE id = %L$q$, pg_temp.u('02')), '23514', '[E2a]');
SET ROLE tally_app;
SELECT pg_temp.as_user('b1');
-- E4 do_not_disconnect follows the enrollments.
SELECT pg_temp.refuses_at('E4a the application sets do_not_disconnect directly',
  format($q$UPDATE public.customers SET do_not_disconnect = true WHERE id = %L$q$, pg_temp.u('c1')), '23514', '[E4]');
SELECT pg_temp.refuses_at('E4b a customer born protected with no enrollment',
  format($q$INSERT INTO public.customers (tenant_id, customer_number, customer_type, do_not_disconnect) VALUES (%L, 'B26-CX', 'residential', true)$q$,
         pg_temp.u('a1')), '23514', '[E4]');
SELECT pg_temp.admits('E4c C2 enrolled in a protective program (SCRA) …',
  format($q$INSERT INTO public.customer_program_enrollments (id, tenant_id, customer_id, program_type, effective_start_date, status)
            VALUES (%L, %L, %L, 'military_deployment_scra', DATE '2026-04-01', 'active')$q$, pg_temp.id('EN1'), pg_temp.u('a1'), pg_temp.u('c2')));
SELECT pg_temp.ok('E4d … is protected, by the enrollment trigger',
  (SELECT do_not_disconnect FROM public.customers WHERE id = pg_temp.u('c2')));
SELECT pg_temp.admits('E4e the enrollment canceled …',
  format($q$UPDATE public.customer_program_enrollments SET status = 'canceled' WHERE id = %L$q$, pg_temp.id('EN1')));
SELECT pg_temp.ok('E4f … and the protection is gone',
  NOT (SELECT do_not_disconnect FROM public.customers WHERE id = pg_temp.u('c2')));
SELECT pg_temp.admits('E4g a write to another column leaves the flag alone',
  format($q$UPDATE public.customers SET notes = 'bat26' WHERE id = %L$q$, pg_temp.u('c1')));
RESET ROLE;
SELECT pg_temp.refuses_at('E4h the owner sets do_not_disconnect directly too',
  format($q$UPDATE public.customers SET do_not_disconnect = true WHERE id = %L$q$, pg_temp.u('c1')), '23514', '[E4]');


-- ============================================================== F field visits, approvals, orders
SET ROLE tally_app;
SELECT pg_temp.as_user('b1');
DO $$ BEGIN
  EXECUTE pg_temp.so('SOX', 'c1', 'd1', 'e1', NULL, 'meter_test');
  EXECUTE pg_temp.so('SO3', 'c1', 'd5', NULL, 'O1b');
  EXECUTE pg_temp.dec('O5', 'disconnect_order', 'c1', NULL, 'd5', NULL, pg_temp.today(), 'eligible', NULL, NULL, NULL, pg_temp.today() + 7, 'O1b', 'o5');
  EXECUTE pg_temp.so('SO5', 'c1', 'd5', 'e5', 'O5');
  EXECUTE pg_temp.dec('O6', 'disconnect_order', 'c1', NULL, 'd6', NULL, pg_temp.today(), 'eligible', NULL, NULL, NULL, pg_temp.today() + 7, 'O3', 'o6');
  EXECUTE pg_temp.so('SO6', 'c1', 'd6', NULL, 'O6');
  EXECUTE pg_temp.dec('O4', 'disconnect_order', 'c2', NULL, 'd2', 'e2', pg_temp.today(), 'eligible', NULL, NULL, NULL, pg_temp.today() + 7, 'O1', 'o4');
  EXECUTE pg_temp.so('SO4', 'c2', 'd2', 'e2', 'O4');
END $$;
SELECT pg_temp.refuses_at('F1a a field visit to an order that is not a disconnect',
  pg_temp.visit('x', 'SOX', TIMESTAMPTZ '2026-04-09 10:00Z', 'SN-E1', 'L1', 'aborted', 'no_access', NULL, NULL, NULL, NULL), '23514', '[F1a]');
SELECT pg_temp.admits('F1 V1: SO1 visited April 9, " sn-e2 " and "l2" captured, aborted (payment shown)',
  pg_temp.visit('V1', 'SO1', TIMESTAMPTZ '2026-04-09 10:00Z', ' sn-e2 ', 'l2', 'aborted', 'payment_shown', NULL, NULL, NULL, NULL));
SELECT pg_temp.ok('F1b the database filled what was expected (L2, E2, SN-E2) and found a match, case and blanks aside',
  (SELECT matched AND expected_location_id = pg_temp.u('d2') AND expected_location_number = 'L2' AND expected_meter_id = pg_temp.u('e2')
          AND expected_meter_serial = 'SN-E2' AND created_by = pg_temp.u('b1')
     FROM public.service_order_field_visits WHERE id = pg_temp.id('V1')));
SELECT pg_temp.refuses_at('F1c1 an abort with no reason',
  pg_temp.visit('x', 'SO1', TIMESTAMPTZ '2026-04-09 11:00Z', 'SN-E2', 'L2', 'aborted', NULL, NULL, NULL, NULL, NULL), '23514', 'service_order_field_visits_outcome_check');
SELECT pg_temp.refuses_at('F1c2 an execution with an abort reason',
  pg_temp.visit('x', 'SO1', TIMESTAMPTZ '2026-04-10 11:00Z', 'SN-E2', 'L2', 'executed', 'safety', 'X1', NULL, NULL, '{photo-1}'), '23514', 'service_order_field_visits_outcome_check');
SELECT pg_temp.refuses_at('F1e an evidence reference that is blank',
  pg_temp.visit('x', 'SO1', TIMESTAMPTZ '2026-04-09 11:00Z', 'SN-E2', 'L2', 'aborted', 'no_access', NULL, NULL, NULL, '{photo-1," "}'), '23514', '[F1e]');
SELECT pg_temp.admits('F1f V2: SO1 visited April 10, "SN-E9" captured at L2 — the caller claims a match and an expected SN-E9',
  format($q$INSERT INTO public.service_order_field_visits (id, tenant_id, service_order_id, arrived_at, captured_meter_serial, captured_location_number,
                     outcome, abort_reason, matched, expected_meter_serial)
            VALUES (%L, %L, %L, TIMESTAMPTZ '2026-04-10 10:00Z', 'SN-E9', 'L2', 'aborted', 'meter_mismatch', true, 'SN-E9')$q$,
         pg_temp.id('V2'), pg_temp.u('a1'), pg_temp.id('SO1')));
SELECT pg_temp.ok('F1g … the database''s expectation and its finding stand: SN-E2 expected, no match',
  (SELECT NOT matched AND expected_meter_serial = 'SN-E2' FROM public.service_order_field_visits WHERE id = pg_temp.id('V2')));
SELECT pg_temp.admits('F1h VD: SO5 names E5 at L5; on April 12 E5 is no longer there and the tech reads SN-E5 at L5',
  pg_temp.visit('VD', 'SO5', TIMESTAMPTZ '2026-04-12 10:00Z', 'SN-E5', 'L5', 'aborted', 'meter_mismatch', NULL, NULL, NULL, NULL));
SELECT pg_temp.ok('F1j … the address matches but the meter drifted: a mismatch (axis A14)',
  (SELECT NOT matched AND expected_meter_id = pg_temp.u('e5') FROM public.service_order_field_visits WHERE id = pg_temp.id('VD')));
SELECT pg_temp.admits('F1k V6: SO6 names no meter and L6 has two',
  pg_temp.visit('V6', 'SO6', TIMESTAMPTZ '2026-04-12 10:00Z', 'SN-E8', 'L6', 'aborted', 'meter_mismatch', NULL, NULL, NULL, NULL));
SELECT pg_temp.ok('F1m … nothing single to expect, so nothing can match',
  (SELECT NOT matched AND expected_meter_id IS NULL AND expected_location_number = 'L6' FROM public.service_order_field_visits WHERE id = pg_temp.id('V6')));
-- F2 an executed visit.
SELECT pg_temp.refuses_at('F2a1 an execution with no decision',
  pg_temp.visit('x', 'SO1', TIMESTAMPTZ '2026-04-10 11:00Z', 'SN-E2', 'L2', 'executed', NULL, NULL, NULL, NULL, '{photo-1}'), '23514', '[A1]');
SELECT pg_temp.refuses_at('F2a2 an execution citing the order decision',
  pg_temp.visit('x', 'SO1', TIMESTAMPTZ '2026-04-10 11:00Z', 'SN-E2', 'L2', 'executed', NULL, 'O1', NULL, NULL, '{photo-1}'), '23514', '[A2]');
SELECT pg_temp.refuses_at('F2a3 an execution citing a blocked decision (X0)',
  pg_temp.visit('x', 'SO1', TIMESTAMPTZ '2026-04-09 11:00Z', 'SN-E2', 'L2', 'executed', NULL, 'X0', NULL, NULL, '{photo-1}'), '23514', '[A3]');
SELECT pg_temp.refuses_at('F2a4 an execution on April 11 under X1, which holds for April 10 only',
  pg_temp.visit('x', 'SO1', TIMESTAMPTZ '2026-04-11 11:00Z', 'SN-E2', 'L2', 'executed', NULL, 'X1', NULL, NULL, '{photo-1}'), '23514', '[A6]');
SELECT pg_temp.refuses_at('F2a5 an execution at L2 citing the decision for L5',
  pg_temp.visit('x', 'SO1', TIMESTAMPTZ '2026-04-12 11:00Z', 'SN-E2', 'L2', 'executed', NULL, 'X2', NULL, NULL, '{photo-1}'), '23514', '[A5]');
SELECT pg_temp.refuses_at('F2b an execution on a mismatch with no supervisor''s approval',
  pg_temp.visit('x', 'SO1', TIMESTAMPTZ '2026-04-10 11:00Z', 'SN-E9', 'L2', 'executed', NULL, 'X1', NULL, NULL, '{photo-1}'), '23514', '[F2b]');
SELECT pg_temp.refuses_at('F2c an execution with no evidence and no supervisor''s approval (D9-1)',
  pg_temp.visit('x', 'SO1', TIMESTAMPTZ '2026-04-10 11:00Z', 'SN-E2', 'L2', 'executed', NULL, 'X1', NULL, NULL, NULL), '23514', '[F2c]');
-- F3 approvals.
SELECT pg_temp.refuses_at('F3a an operator approves',
  pg_temp.appr('x', 'SO1', 'no_evidence', NULL, 'camera_failure', NULL), '42501', '[F3a]');
SELECT pg_temp.as_user('b2');
SELECT pg_temp.refuses_at('F3b1 a mismatch approval naming no visit',
  pg_temp.appr('x', 'SO1', 'meter_mismatch', NULL, 'dispatch_confirmed', 'ticket-77'), '23514', '[F3b]');
SELECT pg_temp.refuses_at('F3b2 a mismatch approval naming a visit that matched',
  pg_temp.appr('x', 'SO1', 'meter_mismatch', 'V1', 'dispatch_confirmed', 'ticket-77'), '23514', '[F3b]');
SELECT pg_temp.refuses_at('F3b3 a mismatch approval with no evidence reference (R-38)',
  pg_temp.appr('x', 'SO1', 'meter_mismatch', 'V2', 'dispatch_confirmed', NULL), '23514', '[F3b]');
SELECT pg_temp.refuses_at('F3b4 a mismatch approval for SO3 naming SO1''s visit',
  pg_temp.appr('x', 'SO3', 'meter_mismatch', 'V2', 'dispatch_confirmed', 'ticket-77'), '23514', '[F3b]');
SELECT pg_temp.refuses_at('F3b5 a no-evidence approval naming a visit',
  pg_temp.appr('x', 'SO1', 'no_evidence', 'V2', 'camera_failure', NULL), '23514', '[F3b]');
SELECT pg_temp.refuses_at('F3b6 an approval for an order that is not a disconnect',
  pg_temp.appr('x', 'SOX', 'no_evidence', NULL, 'camera_failure', NULL), '23514', '[F3b]');
SELECT pg_temp.refuses_at('F3b7 a reason code that is not a code',
  pg_temp.appr('x', 'SO1', 'no_evidence', NULL, 'Bad Code', NULL), '23514', 'service_order_field_approvals_reason_code_check');
SELECT pg_temp.admits('F3 AM: the supervisor approves SO1''s mismatch seen on V2 (naming the operator as approver)',
  pg_temp.appr('AM', 'SO1', 'meter_mismatch', 'V2', 'dispatch_confirmed', 'ticket-77', 'b1'));
SELECT pg_temp.ok('F3c the approver is the session''s supervisor, not the name given',
  (SELECT approved_by = pg_temp.u('b2') FROM public.service_order_field_approvals WHERE id = pg_temp.id('AM')));
SELECT pg_temp.admits('F3d AN: a no-evidence approval for SO1', pg_temp.appr('AN', 'SO1', 'no_evidence', NULL, 'camera_failure', NULL));
SELECT pg_temp.admits('F3d2 AX: a no-evidence approval for SO3', pg_temp.appr('AX', 'SO3', 'no_evidence', NULL, 'camera_failure', NULL));
SELECT pg_temp.as_user('b1');
SELECT pg_temp.refuses_at('F3e an execution under AM capturing other values than V2 did',
  pg_temp.visit('x', 'SO1', TIMESTAMPTZ '2026-04-10 11:00Z', 'SN-E8', 'L2', 'executed', NULL, 'X1', 'AM', 'AN', NULL), '23514', '[F3c]');
SELECT pg_temp.refuses_at('F3f an execution on SO1 citing SO3''s approval',
  pg_temp.visit('x', 'SO1', TIMESTAMPTZ '2026-04-10 11:00Z', 'SN-E2', 'L2', 'executed', NULL, 'X1', NULL, 'AX', NULL), '23514', '[F3d]');
SELECT pg_temp.refuses_at('F3g an execution citing a no-evidence approval as a mismatch approval',
  pg_temp.visit('x', 'SO1', TIMESTAMPTZ '2026-04-10 11:00Z', 'SN-E9', 'L2', 'executed', NULL, 'X1', 'AN', NULL, '{photo-1}'), '23514', '[F3d]');
SELECT pg_temp.admits('F2 VX: SO1 executed April 10 against SN-E9 at L2, under X1, AM and AN',
  pg_temp.visit('VX', 'SO1', TIMESTAMPTZ '2026-04-10 15:00Z', 'SN-E9', 'L2', 'executed', NULL, 'X1', 'AM', 'AN', NULL));
SELECT pg_temp.refuses_at('F2d an execution on SO4 citing X1, which VX used',
  pg_temp.visit('x', 'SO4', TIMESTAMPTZ '2026-04-10 16:00Z', 'SN-E2', 'L2', 'executed', NULL, 'X1', NULL, NULL, '{photo-1}'), '23505', 'service_order_field_visits_one_per_decision');
SELECT pg_temp.admits('F2e X3: the next day''s execute decision for L2 supersedes X1',
  pg_temp.dec('X3', 'disconnect_execute', 'c2', NULL, 'd2', NULL, DATE '2026-04-11', 'eligible', NULL, NULL, NULL, DATE '2026-04-11', 'X1', 'x3'));
SELECT pg_temp.refuses_at('F2f a second execution of SO1',
  pg_temp.visit('x', 'SO1', TIMESTAMPTZ '2026-04-11 11:00Z', 'SN-E2', 'L2', 'executed', NULL, 'X3', NULL, NULL, '{photo-1}'), '23505', 'service_order_field_visits_one_executed');
SELECT pg_temp.admits('A8f the disconnection logged on bill 03 against X1 (the visit is the act; X1 is no longer live)',
  pg_temp.ev('DE1', '03', 'c2', 'disconnected', TIMESTAMPTZ '2026-04-10 16:00Z', 'X1'));
SELECT pg_temp.refuses_at('A8g a disconnection logged against X3, which no executed visit cites',
  pg_temp.ev('x', '03', 'c2', 'disconnected', TIMESTAMPTZ '2026-04-11 16:00Z', 'X3'), '23514', '[A8]');
SELECT pg_temp.ok('A8h bill 03 is at disconnected',
  (SELECT dunning_stage FROM public.invoices WHERE id = pg_temp.u('03')) = 'disconnected');
-- F4 the order guard.
SELECT pg_temp.refuses_at('F4a1 SO1''s meter changed after its approval',
  format($q$UPDATE public.service_orders SET meter_id = NULL WHERE id = %L$q$, pg_temp.id('SO1')), '23514', '[F4a]');
SELECT pg_temp.refuses_at('F4a2 SO1 turned into a reconnect',
  format($q$UPDATE public.service_orders SET order_type = 'reconnect' WHERE id = %L$q$, pg_temp.id('SO1')), '23514', '[F4a]');
SELECT pg_temp.refuses_at('F4a3 a meter test turned into a disconnect',
  format($q$UPDATE public.service_orders SET order_type = 'disconnect' WHERE id = %L$q$, pg_temp.id('SOX')), '23514', '[F4a]');
SELECT pg_temp.refuses_at('F4a4 SO1 re-pointed at another decision',
  format($q$UPDATE public.service_orders SET collections_decision_id = %L WHERE id = %L$q$, pg_temp.id('O4'), pg_temp.id('SO1')), '23514', '[F4a]');
SELECT pg_temp.refuses_at('F4b SO4 completed with no executed visit',
  format($q$UPDATE public.service_orders SET status = 'completed' WHERE id = %L$q$, pg_temp.id('SO4')), '23514', '[F4b]');
SELECT pg_temp.admits('F4b2 SO4 scheduled (dispatch bookkeeping is free)',
  format($q$UPDATE public.service_orders SET status = 'scheduled' WHERE id = %L$q$, pg_temp.id('SO4')));
SELECT pg_temp.refuses_at('F4d1 SO1, executed, put on hold',
  format($q$UPDATE public.service_orders SET status = 'on_hold' WHERE id = %L$q$, pg_temp.id('SO1')), '23514', '[F4d]');
SELECT pg_temp.refuses_at('F4d2 SO1, executed, cancelled',
  format($q$UPDATE public.service_orders SET status = 'cancelled', cancellation_reason = 'x' WHERE id = %L$q$, pg_temp.id('SO1')), '23514', '[F4d]');
SELECT pg_temp.admits('F4 SO1 completed',
  format($q$UPDATE public.service_orders SET status = 'completed' WHERE id = %L$q$, pg_temp.id('SO1')));
SELECT pg_temp.refuses_at('F4c SO1 reopened',
  format($q$UPDATE public.service_orders SET status = 'in_progress' WHERE id = %L$q$, pg_temp.id('SO1')), '23514', '[F4c]');
SELECT pg_temp.refuses_at('F1n a visit to a completed order',
  pg_temp.visit('x', 'SO1', TIMESTAMPTZ '2026-04-11 10:00Z', 'SN-E2', 'L2', 'aborted', 'no_access', NULL, NULL, NULL, NULL), '23514', '[F1b]');
SELECT pg_temp.admits('F2g VX3: SO3 executed April 12, SN-E7 read at L5 (E7 is the meter there), a photo, under X2',
  pg_temp.visit('VX3', 'SO3', TIMESTAMPTZ '2026-04-12 15:00Z', 'SN-E7', 'L5', 'executed', NULL, 'X2', NULL, NULL, '{photo-3}'));
SELECT pg_temp.ok('F2h … a match: the order named no meter and E7 was the one deployed',
  (SELECT matched AND expected_meter_id = pg_temp.u('e7') FROM public.service_order_field_visits WHERE id = pg_temp.id('VX3')));
SELECT pg_temp.refuses_at('A5b a disconnection logged for C2 under C1''s execute decision (the customer is the key''s)',
  pg_temp.ev('x', '03', 'c2', 'disconnected', TIMESTAMPTZ '2026-04-12 16:00Z', 'X2'), '23503', 'dunning_events_decision_fkey');
SELECT pg_temp.refuses_at('F4d3 SO3, executed, cancelled',
  format($q$UPDATE public.service_orders SET status = 'cancelled', cancellation_reason = 'x' WHERE id = %L$q$, pg_temp.id('SO3')), '23514', '[F4d]');
SELECT pg_temp.admits('F4f other order types are as before: the meter test completed with no visit',
  format($q$UPDATE public.service_orders SET status = 'completed' WHERE id = %L$q$, pg_temp.id('SOX')));


-- ============================================================== H history, grants, tenancy, invariants
SELECT pg_temp.refuses_at('H1 T1''s session writes a decision for T2',
  pg_temp.dec('x', 'late_fee', 'c3', '05', NULL, NULL, DATE '2026-04-02', 'eligible', NULL, NULL, NULL, DATE '2026-04-20', NULL, 'x', 'a2'), '42501', 'row-level security');
SELECT pg_temp.refuses_at('H2 T1''s session writes a visit for T2',
  pg_temp.visit('x', 'SO1', TIMESTAMPTZ '2026-04-10 11:00Z', 'SN-E2', 'L2', 'aborted', 'no_access', NULL, NULL, NULL, NULL, 'a2'), '42501', 'row-level security');
SELECT pg_temp.as_user('b2');
SELECT pg_temp.refuses_at('H3 T1''s supervisor writes an approval for T2',
  pg_temp.appr('x', 'SO1', 'no_evidence', NULL, 'camera_failure', NULL, NULL, 'a2'), '42501', 'row-level security');
SELECT pg_temp.refuses_at('H4 the application edits a decision',
  format($q$UPDATE public.collections_decisions SET calculated_by = 'x' WHERE id = %L$q$, pg_temp.id('D3')), '42501', 'permission denied');
SELECT pg_temp.as_user('b3');
SELECT pg_temp.ok('H5 T2 sees none of T1''s decisions, visits or approvals',
  NOT EXISTS (SELECT 1 FROM public.collections_decisions) AND NOT EXISTS (SELECT 1 FROM public.service_order_field_visits)
  AND NOT EXISTS (SELECT 1 FROM public.service_order_field_approvals));
RESET ROLE;
SELECT pg_temp.refuses_at('H6 the owner edits a decision', format($q$UPDATE public.collections_decisions SET calculated_by = 'x' WHERE id = %L$q$, pg_temp.id('D3')), '23001', 'collections_decisions');
SELECT pg_temp.refuses_at('H7 the owner deletes a visit', format($q$DELETE FROM public.service_order_field_visits WHERE id = %L$q$, pg_temp.id('V1')), '23001', 'service_order_field_visits');
SELECT pg_temp.refuses_at('H8 the owner deletes an approval', format($q$DELETE FROM public.service_order_field_approvals WHERE id = %L$q$, pg_temp.id('AN')), '23001', 'service_order_field_approvals');
SELECT pg_temp.refuses_at('H9 a decision is never truncated, even with CASCADE', 'TRUNCATE public.collections_decisions CASCADE', '23001', 'collections_decisions');
SELECT pg_temp.admits('H10 tenant isolation holds over the new tables', $q$SELECT public.assert_tenant_isolation_invariants()$q$);
SELECT pg_temp.admits('H11 the retention invariants hold: no new table can be deleted from', $q$SELECT public.assert_no_hard_delete_invariants()$q$);
SELECT pg_temp.admits('H12 the core role invariants still hold', $q$SELECT public.assert_core_role_invariants()$q$);
SELECT pg_temp.ok('H13 the decision table''s comment says the core decides, and that unevaluable blocks',
  obj_description('public.collections_decisions'::regclass, 'pg_class') ~* 'core'
  AND obj_description('public.collections_conditions'::regclass, 'pg_class') ~* 'unevaluable');

SELECT 'battery-26: all checks passed' AS result;
ROLLBACK;
