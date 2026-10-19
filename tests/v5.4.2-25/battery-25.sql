-- ============================================================================
-- BATTERY v5.4.2-25 — disputes and the dispute rule family (2026-10-18)
-- Run: psql -U tally -d <db-with-23-and-25> -v ON_ERROR_STOP=1 -f battery-25.sql
-- One transaction, rolled back. Fixtures as the owner (whose stamps are kept,
-- so the reader can be tested across recorded instants); every guard the
-- application meets is exercised as tally_app under app.user_id.
-- Each check names its requirement in
-- application/wave3-build-2026-10-18/v5.4.2-25-design.md.
--
--   S  kinds, facets, vocabularies (L1-L3)   K  the Texas rows (L4)
--   X  the law table's insert check          U  the utility's tariff (L5)
--   N  never looser than the law (L6)        D  the dispute record (D1-D5)
--   R  the reader (D6)                       T  the two meaning changes (T1, T2)
--   H  history, grants, tenancy, invariants
--
-- Written before the patch: it fails first, at the first object -25 creates.
--
-- Contract the patch must meet (names fixed here):
--   tables  dispute_customer_classes (state_code, service_type, class_code, description, source_note)
--           dispute_subjects (subject_code), dispute_blocks (block_code), dispute_duties (duty_code)
--           dispute_rules (law; key customer_class; facets subject_codes, excluded_subject_codes,
--                          block_codes, stage_ids, must_pay_ids)
--           dispute_tariffs (tariff; key []; the same facets; tariff_reference)
--           disputes, dispute_amounts, dispute_amount_lines, dispute_determinations, dispute_events
--   readers dispute_shelter_as_of(invoice, on, recorded)
--           dispute_line_shelter_as_of(line, on, recorded)
--   Every refusal the patch raises itself names its requirement in brackets,
--   e.g. "[D4h]"; the checks below match on that tag.
-- Recorded time: each record's created_at is stamped by the database
-- (now() for tally_app; the owner's value is kept, as -19's stamp).
-- What one transaction cannot show (one live determination under two
-- writers, a determination against a resolution) is in races/disputes-25.sh.
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
-- admits_undone(): the statement is admitted, then undone (an exception rolls back its subtransaction),
-- so one side of a boundary can be shown without its row staying.
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
-- deferred(): run a statement, then check the deferred constraints at once
-- (a guard checked at commit is tested inside the one transaction).
CREATE FUNCTION pg_temp.deferred(p_sql text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  SET CONSTRAINTS ALL DEFERRED;
  EXECUTE p_sql;
  SET CONSTRAINTS ALL IMMEDIATE;
END $$;
-- snap(): a calculation snapshot of a bill at (p_valid, p_rec), its lines as they are.
CREATE FUNCTION pg_temp.snap(p_inv uuid, p_valid date, p_rec timestamptz) RETURNS void LANGUAGE plpgsql AS $$
DECLARE i public.invoices%ROWTYPE;
BEGIN
  SELECT * INTO i FROM public.invoices WHERE id = p_inv;
  INSERT INTO public.invoice_calculation_snapshots
    (tenant_id, invoice_id, billing_run_id, valid_at, recorded_at, snapshot_schema_version, formula_version,
     rate_inputs, gas_factors, wna_inputs, tax_inputs, read_inputs, customer_inputs, period_inputs, line_items)
  VALUES (i.tenant_id, i.id, i.billing_run_id, p_valid, p_rec, 'v1', 'bat25',
     '{"rate_schedule_id":null,"rate_schedule_version_id":null,"rate_schedule_code":null,"customer_type":null,"partial_period_policy":null,"items":[]}',
     '{"pga_factor":null,"btu_factor":null,"pressure_factor":null,"temperature_factor":null,"meter_multiplier":null,"factor_stack_intermediates":{}}',
     '{"applied":false}', '{"jurisdictions":[],"exemptions":[],"franchise_fees":[]}', '{"reads":[]}',
     jsonb_build_object('customer_id', i.customer_id, 'customer_class', null, 'location_id', i.location_id, 'premise_zones', '{}'::jsonb),
     jsonb_build_object('period_start', i.period_start, 'period_end', i.period_end, 'days_in_period', i.period_end - i.period_start + 1, 'proration_policy', null),
     (SELECT coalesce(jsonb_agg(jsonb_build_object('invoice_line_item_id', l.id, 'charge_type', l.charge_type, 'amount', l.amount)), '[]'::jsonb)
        FROM public.invoice_line_items l WHERE l.invoice_id = i.id));
END $$;
GRANT EXECUTE ON FUNCTION pg_temp.refuses_at(text, text, text, text), pg_temp.ok(text, boolean), pg_temp.admits(text, text),
                          pg_temp.admits_undone(text, text), pg_temp.deferred(text) TO tally_app;

-- ------------------------------------------------------------------ fixtures
-- T1 (…25a1) a city-owned Texas gas system with its own dispute tariff;
-- T2 (…25a2) an investor-owned Texas gas system (16 TAC 7.45 binds it);
-- T3 (…25a3) a city-owned system with no dispute tariff.
-- Ids: b users, c customers, d locations, e meters, 01-09 bills, 11-1f and
-- 21-2f lines, 31-3f disputes, 41-4f amounts, 51-5f determinations, 61-6f
-- events, 71 readings, 81-8f ledger, ab/ac/ad tariffs.
INSERT INTO public.tenants (id, name, slug) VALUES
  ('00000000-0000-4000-8000-0000000025a1', 'T1 City Gas', 'bat25-t1'),
  ('00000000-0000-4000-8000-0000000025a2', 'T2 Gasco', 'bat25-t2'),
  ('00000000-0000-4000-8000-0000000025a3', 'T3 Town Gas', 'bat25-t3');
INSERT INTO public.users (id, tenant_id, display_name, email, role, is_active) VALUES
  ('00000000-0000-4000-8000-0000000025b1', '00000000-0000-4000-8000-0000000025a1', 'Op1', 'op1@bat25.test', 'operator', true),
  ('00000000-0000-4000-8000-0000000025b2', '00000000-0000-4000-8000-0000000025a2', 'Op2', 'op2@bat25.test', 'operator', true),
  ('00000000-0000-4000-8000-0000000025b3', '00000000-0000-4000-8000-0000000025a3', 'Op3', 'op3@bat25.test', 'operator', true),
  ('00000000-0000-4000-8000-0000000025b4', '00000000-0000-4000-8000-0000000025a1', 'Admin1', 'ad1@bat25.test', 'tenant_admin', true);
INSERT INTO public.customers (id, tenant_id, customer_number, customer_type) VALUES
  ('00000000-0000-4000-8000-0000000025c1', '00000000-0000-4000-8000-0000000025a1', 'B25-C1', 'residential'),
  ('00000000-0000-4000-8000-0000000025c2', '00000000-0000-4000-8000-0000000025a1', 'B25-C2', 'residential'),
  ('00000000-0000-4000-8000-0000000025c5', '00000000-0000-4000-8000-0000000025a2', 'B25-C5', 'residential'),
  ('00000000-0000-4000-8000-0000000025c6', '00000000-0000-4000-8000-0000000025a2', 'B25-C6', 'large_commercial'),
  ('00000000-0000-4000-8000-0000000025c7', '00000000-0000-4000-8000-0000000025a3', 'B25-C7', 'residential');
INSERT INTO public.service_locations (id, tenant_id, customer_id, location_number, address_line1, city, state, zip) VALUES
  ('00000000-0000-4000-8000-0000000025d1', '00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-0000000025c1', 'L1', '1 Main', 'Brenham', 'TX', '77833'),
  ('00000000-0000-4000-8000-0000000025d2', '00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-0000000025c2', 'L2', '2 Main', 'Brenham', 'TX', '77833'),
  ('00000000-0000-4000-8000-0000000025d5', '00000000-0000-4000-8000-0000000025a2', '00000000-0000-4000-8000-0000000025c5', 'L5', '5 Main', 'Austin', 'TX', '78701'),
  ('00000000-0000-4000-8000-0000000025d6', '00000000-0000-4000-8000-0000000025a2', '00000000-0000-4000-8000-0000000025c6', 'L6', '6 Main', 'Austin', 'TX', '78701'),
  ('00000000-0000-4000-8000-0000000025d7', '00000000-0000-4000-8000-0000000025a3', '00000000-0000-4000-8000-0000000025c7', 'L7', '7 Main', 'Smalltown', 'TX', '75001');
INSERT INTO public.places (id, kind_code, state_code, place_code, name, parent_place_id, effective_from, source_note)
SELECT v.id::uuid, 'municipality', 'TX', v.code, v.name, s.id, DATE '2000-01-01', 'battery-25 fixture'
  FROM public.places s,
       (VALUES ('00000000-0000-4000-8000-0000000025a7', 'TX-B25-CITY', 'Battery City 25'),
               ('00000000-0000-4000-8000-0000000025a8', 'TX-B25-TOWN', 'Battery Town 25')) v(id, code, name)
 WHERE s.kind_code = 'state' AND s.state_code = 'TX';
INSERT INTO public.utility_service_profiles (tenant_id, service_type, system_kind, state_code, owner_type, commission_jurisdiction,
                                             owning_place_id, effective_from, evidence_reference, evidence_date) VALUES
  ('00000000-0000-4000-8000-0000000025a1', 'gas', 'distribution', 'TX', 'municipal', false, '00000000-0000-4000-8000-0000000025a7', DATE '2000-01-01', 'Battery City charter', DATE '2000-01-01'),
  ('00000000-0000-4000-8000-0000000025a2', 'gas', 'distribution', 'TX', 'investor_owned', true, NULL, DATE '2000-01-01', 'RRC certificate bat25', DATE '2000-01-01'),
  ('00000000-0000-4000-8000-0000000025a3', 'gas', 'distribution', 'TX', 'municipal', false, '00000000-0000-4000-8000-0000000025a8', DATE '2000-01-01', 'Battery Town charter', DATE '2000-01-01');
INSERT INTO public.meters (id, tenant_id, meter_number, location_id, service_type) VALUES
  ('00000000-0000-4000-8000-0000000025e1', '00000000-0000-4000-8000-0000000025a1', 'B25-M1', '00000000-0000-4000-8000-0000000025d1', 'gas'),
  ('00000000-0000-4000-8000-0000000025e2', '00000000-0000-4000-8000-0000000025a1', 'B25-M2', '00000000-0000-4000-8000-0000000025d2', 'gas');
INSERT INTO public.meter_readings (id, tenant_id, meter_id, reading_date, reading_value) VALUES
  ('00000000-0000-4000-8000-000000002571', '00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-0000000025e1', DATE '2026-02-28', 50),
  ('00000000-0000-4000-8000-000000002572', '00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-0000000025e2', DATE '2026-02-28', 60);

-- bill(): an issued bill dated March 1 (due March 20) with three lines: gas
-- service 60 (regulated), an add-on 40 (unregulated), a credit -10. Issued a
-- day ago as a history load (the owner's stamp is kept).
CREATE FUNCTION pg_temp.bill(p_tenant uuid, p_id uuid, p_num text, p_customer uuid, p_loc uuid, p_l1 uuid, p_l2 uuid, p_l3 uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO public.invoices (id, tenant_id, invoice_number, customer_id, location_id, invoice_date, billing_period, period_start, period_end, due_date, amount_due)
  VALUES (p_id, p_tenant, p_num, p_customer, p_loc, DATE '2026-03-01', '2026-02', DATE '2026-02-01', DATE '2026-02-28', DATE '2026-03-20', 90.00);
  INSERT INTO public.invoice_line_items (id, tenant_id, invoice_id, line_order, service_type, charge_type, description, amount, rate, regulatory_class) VALUES
    (p_l1, p_tenant, p_id, 0, 'gas', 'base_charge', 'Gas service', 60.00, 60.00, 'regulated'),
    (p_l2, p_tenant, p_id, 1, 'general', 'misc', 'Appliance plan', 40.00, NULL, 'unregulated'),
    (p_l3, p_tenant, p_id, 2, 'gas', 'credit', 'Goodwill', -10.00, NULL, 'regulated');
  PERFORM pg_temp.snap(p_id, DATE '2026-02-28', now());
  UPDATE public.invoices SET status = 'pending' WHERE id = p_id;
  UPDATE public.invoices SET first_issued_at = now() - interval '1 day' WHERE id = p_id;
END $$;
SELECT pg_temp.bill('00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-000000002501', 'B25-I1', '00000000-0000-4000-8000-0000000025c1', '00000000-0000-4000-8000-0000000025d1',
                    '00000000-0000-4000-8000-000000002511', '00000000-0000-4000-8000-000000002512', '00000000-0000-4000-8000-000000002513');
SELECT pg_temp.bill('00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-000000002502', 'B25-I2', '00000000-0000-4000-8000-0000000025c1', '00000000-0000-4000-8000-0000000025d1',
                    '00000000-0000-4000-8000-000000002514', '00000000-0000-4000-8000-000000002515', '00000000-0000-4000-8000-000000002516');
SELECT pg_temp.bill('00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-000000002503', 'B25-I3', '00000000-0000-4000-8000-0000000025c2', '00000000-0000-4000-8000-0000000025d2',
                    '00000000-0000-4000-8000-000000002517', '00000000-0000-4000-8000-000000002518', '00000000-0000-4000-8000-000000002519');
SELECT pg_temp.bill('00000000-0000-4000-8000-0000000025a2', '00000000-0000-4000-8000-000000002505', 'B25-I5', '00000000-0000-4000-8000-0000000025c5', '00000000-0000-4000-8000-0000000025d5',
                    '00000000-0000-4000-8000-000000002521', '00000000-0000-4000-8000-000000002522', '00000000-0000-4000-8000-000000002523');
SELECT pg_temp.bill('00000000-0000-4000-8000-0000000025a2', '00000000-0000-4000-8000-000000002506', 'B25-I6', '00000000-0000-4000-8000-0000000025c6', '00000000-0000-4000-8000-0000000025d6',
                    '00000000-0000-4000-8000-000000002524', '00000000-0000-4000-8000-000000002525', '00000000-0000-4000-8000-000000002526');
SELECT pg_temp.bill('00000000-0000-4000-8000-0000000025a3', '00000000-0000-4000-8000-000000002507', 'B25-I7', '00000000-0000-4000-8000-0000000025c7', '00000000-0000-4000-8000-0000000025d7',
                    '00000000-0000-4000-8000-000000002527', '00000000-0000-4000-8000-000000002528', '00000000-0000-4000-8000-000000002529');
-- A draft bill of C1 (never issued).
INSERT INTO public.invoices (id, tenant_id, invoice_number, customer_id, location_id, invoice_date, billing_period, period_start, period_end, due_date, amount_due)
VALUES ('00000000-0000-4000-8000-000000002504', '00000000-0000-4000-8000-0000000025a1', 'B25-I4', '00000000-0000-4000-8000-0000000025c1', '00000000-0000-4000-8000-0000000025d1',
        DATE '2026-03-01', '2026-02', DATE '2026-02-01', DATE '2026-02-28', DATE '2026-03-20', 25.00);
INSERT INTO public.invoice_line_items (id, tenant_id, invoice_id, service_type, charge_type, description, amount, rate, regulatory_class) VALUES
  ('00000000-0000-4000-8000-00000000251a', '00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-000000002504', 'gas', 'base_charge', 'Draft line', 25.00, 25.00, 'regulated');
-- A goodwill credit of C1 (an adjusted dispute may name it; origin dispute_resolution).
INSERT INTO public.customer_credits (id, tenant_id, customer_id, origin_type, original_amount, issued_date)
VALUES ('00000000-0000-4000-8000-000000002581', '00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-0000000025c1', 'dispute_resolution', 40, DATE '2026-04-10');
-- An adjustment entry of C1 and one of C2.
INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reference_type, reference_id) VALUES
  ('00000000-0000-4000-8000-000000002582', '00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-0000000025c1', DATE '2026-04-10', 'adjustment', 'I2 dispute adjusted', -40, 'invoice', '00000000-0000-4000-8000-000000002502'),
  ('00000000-0000-4000-8000-000000002583', '00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-0000000025c2', DATE '2026-04-10', 'adjustment', 'I3 adjusted', -40, 'invoice', '00000000-0000-4000-8000-000000002503');
--@fixtures-end

-- law(owner, class): the Texas gas dispute law row binding an owner type for a class.
CREATE FUNCTION pg_temp.law(p_owner text, p_class text) RETURNS uuid LANGUAGE sql STABLE AS $$
  SELECT id FROM public.dispute_rules
   WHERE state_code = 'TX' AND service_type = 'gas' AND customer_class = p_class AND p_owner = ANY (owner_types) AND closed_at IS NULL
$$;
GRANT EXECUTE ON FUNCTION pg_temp.law(text, text) TO tally_app;
-- tariff_sql(id, tenant, from, document): a dispute tariff row of a TX gas distribution system.
CREATE FUNCTION pg_temp.tariff_sql(p_id text, p_tenant text, p_from date, p_doc jsonb) RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT format($q$INSERT INTO public.dispute_tariffs (id, tenant_id, state_code, service_type, system_kind, effective_from, tariff_reference, terms_kind, terms_version, terms_source)
                   VALUES (%s, %L, 'TX', 'gas', 'distribution', %L, 'battery tariff', 'dispute_tariff', 1, %L)$q$,
                CASE WHEN p_id IS NULL THEN 'DEFAULT' ELSE quote_literal(p_id) END, p_tenant, p_from, p_doc::text)
$$;
-- tdoc(overrides): a dispute tariff document (CPS-shaped), with top-level sections replaced.
CREATE FUNCTION pg_temp.tdoc(p_over jsonb DEFAULT '{}') RETURNS jsonb LANGUAGE sql IMMUTABLE AS $$
  SELECT '{"citation": "Battery tariff, disputes",
           "subjects": {"kind": "any", "excluded": []},
           "shelter_earned": {"kind": "before_termination"},
           "must_pay": {"strategy": "undisputed_charges", "version": 1, "id": "m1"},
           "shelter_ends": {"kind": "resolution"},
           "stages": [{"id": "s1", "decider": "manager", "file_within": {"kind": "none"}, "decide_within": {"kind": "none"}, "final": false},
                      {"id": "s2", "decider": "executive", "file_within": {"kind": "days", "days": 30, "from": "prior_decision"}, "decide_within": {"kind": "days", "days": 90}, "final": true}],
           "blocks": {"codes": ["notice_issue", "disconnect_order", "disconnect_execute", "late_fee"]},
           "duties": {"codes": ["investigate", "report_result"]}}'::jsonb || p_over
$$;
GRANT EXECUTE ON FUNCTION pg_temp.tariff_sql(text, text, date, jsonb), pg_temp.tdoc(jsonb) TO tally_app;

-- ============================================================== S kinds, facets, vocabularies (L1-L3)
SELECT pg_temp.ok('S1 dispute v1 is a registered, unfrozen law kind; dispute_tariff v1 a tariff kind',
  (SELECT rule_role = 'law' AND accepts_new_rows FROM public.rule_term_schemas WHERE terms_kind = 'dispute' AND terms_version = 1)
  AND (SELECT rule_role = 'tariff' AND accepts_new_rows FROM public.rule_term_schemas WHERE terms_kind = 'dispute_tariff' AND terms_version = 1));
SELECT pg_temp.ok('S2 the registered schemas are the committed files (their ids and hashes)',
  (SELECT bool_and(schema_hash ~ '^sha256:[0-9a-f]{64}$') AND count(*) = 2
          AND bool_or(json_schema ->> '$id' = 'https://tally-utility/law/dispute/dispute.v1.schema.json')
          AND bool_or(json_schema ->> '$id' = 'https://tally-utility/law/dispute/dispute_tariff.v1.schema.json')
     FROM public.rule_term_schemas WHERE terms_kind IN ('dispute', 'dispute_tariff') AND terms_version = 1));
SELECT pg_temp.ok('S3 both kinds have the same five facets (L3)',
  (SELECT count(*) = 10 AND bool_and(facet_type = 'text[]')
          AND count(DISTINCT facet_name) = 5
          AND array_agg(DISTINCT facet_name ORDER BY facet_name) = ARRAY['block_codes', 'excluded_subject_codes', 'must_pay_ids', 'stage_ids', 'subject_codes']
     FROM public.rule_term_facets WHERE terms_kind IN ('dispute', 'dispute_tariff') AND terms_version = 1));
SELECT pg_temp.ok('S4 subject and block codes are checked against their vocabularies; stage and must_pay ids are not (a record cites one)',
  (SELECT bool_and(CASE facet_name
            WHEN 'subject_codes'          THEN vocabulary_table = 'dispute_subjects' AND json_path = '$.subjects.codes[*]'
            WHEN 'excluded_subject_codes' THEN vocabulary_table = 'dispute_subjects' AND json_path = '$.subjects.excluded[*]'
            WHEN 'block_codes'            THEN vocabulary_table = 'dispute_blocks'   AND json_path = '$.blocks.codes[*]'
            WHEN 'stage_ids'              THEN vocabulary_table IS NULL              AND json_path = '$.stages[*].id'
            WHEN 'must_pay_ids'           THEN vocabulary_table IS NULL              AND json_path = '$.must_pay.id' END)
     FROM public.rule_term_facets WHERE terms_kind IN ('dispute', 'dispute_tariff') AND terms_version = 1));
SELECT pg_temp.ok('S5 the vocabularies hold every code the design names',
  (SELECT count(*) = 12 FROM public.dispute_subjects WHERE subject_code = ANY (ARRAY['meter_accuracy', 'rate_application', 'calculation',
     'service_not_rendered', 'identity_theft', 'responsible_party', 'deposit', 'credit', 'ability_to_pay', 'tamper_finding',
     'consumption_on_accurate_meter', 'other']))
  AND (SELECT count(*) = 6 FROM public.dispute_blocks WHERE block_code = ANY (ARRAY['notice_issue', 'disconnect_order', 'disconnect_execute',
     'late_fee', 'collections_referral', 'credit_reporting']))
  AND (SELECT count(*) = 4 FROM public.dispute_duties WHERE duty_code = ANY (ARRAY['investigate', 'report_result', 'inform_complaint_route',
     'offer_payment_arrangement'])));
SELECT pg_temp.ok('S6 the Texas gas dispute classes are 16 TAC 7.45''s reach: protected (residential and small commercial) and unprotected',
  (SELECT array_agg(class_code ORDER BY class_code) = ARRAY['protected', 'unprotected']
     FROM public.dispute_customer_classes WHERE state_code = 'TX' AND service_type = 'gas'));
SELECT pg_temp.ok('S7 the vocabularies are the platform''s: the application reads them and writes none',
  (SELECT bool_and(has_table_privilege('tally_app', t, 'SELECT') AND NOT has_table_privilege('tally_app', t, 'INSERT')
                   AND NOT has_table_privilege('tally_app', t, 'UPDATE') AND NOT has_table_privilege('tally_app', t, 'DELETE'))
     FROM unnest(ARRAY['public.dispute_subjects', 'public.dispute_blocks', 'public.dispute_duties', 'public.dispute_customer_classes',
                       'public.dispute_rules']) t));

-- ============================================================== M the two tables are on the template (L1, L5)
SELECT pg_temp.ok('M1 dispute_rules: a registered law table on the dispute kind, keyed by customer class, five facets, a close floor and an insert check',
  (SELECT rule_role = 'law' AND terms_kind = 'dispute' AND area_key = '{customer_class}'
          AND facet_columns = '{block_codes,excluded_subject_codes,must_pay_ids,stage_ids,subject_codes}'
          AND NOT adopts_legacy_rows AND insert_check IS NOT NULL AND close_floor IS NOT NULL
          AND law_table IS NULL AND compare_function IS NULL
     FROM public.rule_tables WHERE table_name = 'public.dispute_rules'::regclass));
SELECT pg_temp.ok('M2 dispute_tariffs: a registered tariff table on dispute_tariff, key [] (one policy per utility, state, service, system), measured against dispute_rules',
  (SELECT rule_role = 'tariff' AND terms_kind = 'dispute_tariff' AND area_key = '{}'
          AND facet_columns = '{block_codes,excluded_subject_codes,must_pay_ids,stage_ids,subject_codes}'
          AND law_table = 'public.dispute_rules'::regclass AND compare_function IS NOT NULL
          AND close_floor IS NOT NULL AND insert_check IS NOT NULL
     FROM public.rule_tables WHERE table_name = 'public.dispute_tariffs'::regclass));
SELECT pg_temp.ok('M3 the customer class is a foreign key into dispute_customer_classes, scoped by state and service',
  EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public.dispute_rules'::regclass AND contype = 'f'
             AND confrelid = 'public.dispute_customer_classes'::regclass));
SELECT pg_temp.ok('M4 the template''s three triggers stand on both, enabled always',
  (SELECT count(*) = 6 FROM pg_trigger WHERE tgrelid IN ('public.dispute_rules'::regclass, 'public.dispute_tariffs'::regclass) AND NOT tgisinternal
      AND tgname = ANY (ARRAY['rule_row_insert', 'rule_row_history', 'rule_row_no_truncate']) AND tgenabled = 'A'));
SELECT pg_temp.admits('M5 the template''s invariants hold over the registered tables', $q$SELECT public.assert_rule_table_invariants()$q$);

-- ============================================================== K the Texas rows (L4)
CREATE TEMP TABLE k25 (owner text, class text, doc jsonb);
INSERT INTO k25 VALUES
  ('investor_owned', 'protected', '{"governs": "law", "citation": "16 TAC 7.45(6)(D)", "subjects": {"kind": "any", "excluded": [], "citation": "16 TAC 7.45(6)(D)(i)"}, "shelter_earned": {"kind": "before_delinquency", "citation": "16 TAC 7.45(6)(D)(i)"}, "must_pay": {"strategy": "average_usage_cap", "version": 1, "id": "m1", "history_years": 2, "no_history": "similar_customers", "citation": "16 TAC 7.45(6)(D)(ii)"}, "shelter_ends": {"kind": "earlier_of_resolution_and_days", "days": 60, "from": "issue", "citation": "16 TAC 7.45(6)(D)(ii)"}, "stages": [{"id": "s1", "decider": "designated_employee", "file_within": {"kind": "none"}, "decide_within": {"kind": "none"}, "final": false, "citation": "16 TAC 7.45(6)(D)(i)"}, {"id": "s2", "decider": "regulator", "file_within": {"kind": "none"}, "decide_within": {"kind": "days", "days": 15}, "final": true, "citation": "16 TAC 7.45(2)(C)"}], "blocks": {"codes": ["disconnect_order", "disconnect_execute", "late_fee"], "citation": "16 TAC 7.45(6)(D)(ii)"}, "duties": {"codes": ["investigate", "report_result", "inform_complaint_route"], "citation": "16 TAC 7.45(6)(D)(i)"}}'),
  ('investor_owned', 'unprotected', '{"governs": "law", "citation": "16 TAC 7.45(1)", "subjects": {"kind": "any", "excluded": [], "citation": "16 TAC 7.45(1)"}, "shelter_earned": {"kind": "unruled"}, "must_pay": {"strategy": "full_bill", "version": 1, "id": "m1", "citation": "16 TAC 7.45(1)"}, "shelter_ends": {"kind": "unruled"}, "stages": [], "blocks": {"codes": [], "citation": "16 TAC 7.45(1)"}, "duties": {"codes": [], "citation": "16 TAC 7.45(1)"}}'),
  ('municipal', 'protected', '{"governs": "delegated_to_utility", "citation": "Tex. Util. Code 101.003(7)", "note": "A municipal corporation is not a gas utility under GURA; its own tariff sets its dispute policy."}'),
  ('municipal', 'unprotected', '{"governs": "delegated_to_utility", "citation": "Tex. Util. Code 101.003(7)", "note": "A municipal corporation is not a gas utility under GURA; its own tariff sets its dispute policy."}');
SELECT pg_temp.ok('K1 Texas gas has exactly four dispute law rows',
  (SELECT count(*) = 4 FROM public.dispute_rules WHERE state_code = 'TX' AND service_type = 'gas'));
SELECT pg_temp.ok('K2 the investor-owned and cooperative rows hold exactly the 16 TAC 7.45 documents, per class',
  (SELECT bool_and(r.terms = k.doc) AND count(*) = 2 FROM k25 k JOIN public.dispute_rules r
      ON r.state_code = 'TX' AND r.service_type = 'gas' AND r.customer_class = k.class AND k.owner = ANY (r.owner_types)
   WHERE k.owner = 'investor_owned'));
SELECT pg_temp.ok('K3 they bind what 16 TAC 7.45 binds: investor-owned and cooperative owners, distribution systems, either jurisdiction status, from 2004-07-12, open-ended',
  (SELECT bool_and(owner_types = '{investor_owned,cooperative}' AND system_kinds = '{distribution}' AND commission_jurisdiction IS NULL
                   AND effective_from = DATE '2004-07-12' AND effective_to IS NULL)
     FROM public.dispute_rules WHERE state_code = 'TX' AND service_type = 'gas' AND terms ->> 'governs' = 'law'));
SELECT pg_temp.ok('K4 a city-owned system gets a delegation for each class (K-07; Util. Code 101.003(7))',
  (SELECT bool_and(r.terms = k.doc) AND count(*) = 2 AND bool_and(r.owner_types = '{municipal}')
     FROM k25 k JOIN public.dispute_rules r
      ON r.state_code = 'TX' AND r.service_type = 'gas' AND r.customer_class = k.class AND k.owner = ANY (r.owner_types)
   WHERE k.owner = 'municipal'));
SELECT pg_temp.ok('K5 the facets are derived from the documents',
  (SELECT block_codes = '{disconnect_order,disconnect_execute,late_fee}' AND stage_ids = '{s1,s2}' AND must_pay_ids = '{m1}'
          AND subject_codes = '{}' AND excluded_subject_codes = '{}'
     FROM public.dispute_rules WHERE id = pg_temp.law('investor_owned', 'protected'))
  AND (SELECT block_codes = '{}' AND stage_ids = '{}' AND must_pay_ids = '{}'
     FROM public.dispute_rules WHERE id = pg_temp.law('municipal', 'protected')));
SELECT pg_temp.ok('K6 the protected row''s source note says late_fee is our reading (fail toward protection)',
  (SELECT source_note ~* 'late.fee' AND source_note ~* 'reading' FROM public.dispute_rules WHERE id = pg_temp.law('investor_owned', 'protected')));
SELECT pg_temp.ok('K7 another state, service or owner type finds no row: unknown law is not permission',
  NOT EXISTS (SELECT 1 FROM public.dispute_rules WHERE state_code <> 'TX' OR service_type <> 'gas')
  AND pg_temp.law('special_district', 'protected') IS NULL);

-- ============================================================== X the law table's insert check
-- A law row as the owner: the vocabulary facets and the document's own consistency.
CREATE FUNCTION pg_temp.law_sql(p_class text, p_doc jsonb) RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT format($q$INSERT INTO public.dispute_rules (state_code, service_type, owner_types, system_kinds, commission_jurisdiction, customer_class,
                     effective_from, source_note, terms_kind, terms_version, terms_source)
                   VALUES ('TX', 'gas', '{special_district}', '{distribution}', NULL, %L, DATE '2026-01-01', 'battery rule', 'dispute', 1, %L)$q$,
                p_class, p_doc::text)
$$;
SELECT pg_temp.refuses_at('X1 a subject code the vocabulary lacks',
  pg_temp.law_sql('protected', (SELECT doc FROM k25 WHERE owner = 'investor_owned' AND class = 'protected')
     || '{"subjects": {"kind": "listed", "codes": ["meter_accuracy", "weather"], "excluded": [], "citation": "x"}}'), '23503', 'weather');
SELECT pg_temp.refuses_at('X2 a block code the vocabulary lacks',
  pg_temp.law_sql('protected', (SELECT doc FROM k25 WHERE owner = 'investor_owned' AND class = 'protected')
     || '{"blocks": {"codes": ["shutoff"], "citation": "x"}}'), '23503', 'shutoff');
SELECT pg_temp.refuses_at('X3 a subject both listed and excluded',
  pg_temp.law_sql('protected', (SELECT doc FROM k25 WHERE owner = 'investor_owned' AND class = 'protected')
     || '{"subjects": {"kind": "listed", "codes": ["meter_accuracy", "deposit"], "excluded": ["deposit"], "citation": "x"}}'), '23514', '[L2a]');
SELECT pg_temp.refuses_at('X4 a block code listed twice',
  pg_temp.law_sql('protected', (SELECT doc FROM k25 WHERE owner = 'investor_owned' AND class = 'protected')
     || '{"blocks": {"codes": ["late_fee", "late_fee"], "citation": "x"}}'), '23514', '[L2b]');
SELECT pg_temp.refuses_at('X5 a stage filed "from the prior decision" that has no prior stage',
  pg_temp.law_sql('protected', (SELECT doc FROM k25 WHERE owner = 'investor_owned' AND class = 'protected')
     || '{"stages": [{"id": "s1", "decider": "manager", "file_within": {"kind": "days", "days": 30, "from": "prior_decision"}, "decide_within": {"kind": "none"}, "final": true, "citation": "x"}]}'),
  '23514', '[L2c]');
SELECT pg_temp.refuses_at('X6 a final stage that is not the last',
  pg_temp.law_sql('protected', (SELECT doc FROM k25 WHERE owner = 'investor_owned' AND class = 'protected')
     || '{"stages": [{"id": "s1", "decider": "manager", "file_within": {"kind": "none"}, "decide_within": {"kind": "none"}, "final": true, "citation": "x"},
                     {"id": "s2", "decider": "executive", "file_within": {"kind": "none"}, "decide_within": {"kind": "none"}, "final": false, "citation": "x"}]}'),
  '23514', '[L2d]');
SELECT pg_temp.refuses_at('X7 a customer class the state''s vocabulary lacks',
  pg_temp.law_sql('governmental', (SELECT doc FROM k25 WHERE owner = 'investor_owned' AND class = 'protected')), '23503', 'dispute_customer_classes');
SELECT pg_temp.admits('X8 a well-formed law row of another owner type is admitted (the owner writes law)',
  pg_temp.law_sql('protected', (SELECT doc FROM k25 WHERE owner = 'investor_owned' AND class = 'protected')));

-- ============================================================== U the utility's tariff (L5)
SET ROLE tally_app;
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000025b1', true);
SELECT pg_temp.admits('U1 a city writes its own Brenham-shaped tariff from March 10 (its law row delegates: nothing to compare)',
  pg_temp.tariff_sql('00000000-0000-4000-8000-0000000025ab', '00000000-0000-4000-8000-0000000025a1', DATE '2026-03-10',
    '{"citation": "City of Brenham gas tariff Sheet 511", "subjects": {"kind": "any", "excluded": []}, "shelter_earned": {"kind": "any_time"},
      "must_pay": {"strategy": "full_bill", "version": 1, "id": "m1"}, "shelter_ends": {"kind": "resolution"},
      "stages": [{"id": "s1", "decider": "designated_employee", "file_within": {"kind": "none"}, "decide_within": {"kind": "none"}, "final": true}],
      "blocks": {"codes": ["disconnect_order", "disconnect_execute", "credit_reporting"]}, "duties": {"codes": ["investigate"]}}'));
SELECT pg_temp.ok('U2 its facets are derived from its document',
  (SELECT block_codes = '{disconnect_order,disconnect_execute,credit_reporting}' AND stage_ids = '{s1}' AND must_pay_ids = '{m1}'
     FROM public.dispute_tariffs WHERE id = '00000000-0000-4000-8000-0000000025ab'));
SELECT pg_temp.refuses_at('U3 a second tariff over the same dates',
  pg_temp.tariff_sql(NULL, '00000000-0000-4000-8000-0000000025a1', DATE '2026-05-01', pg_temp.tdoc()), '23P01', 'dispute_tariffs');
SELECT pg_temp.refuses_at('U4 an excluded subject the vocabulary lacks',
  pg_temp.tariff_sql(NULL, '00000000-0000-4000-8000-0000000025a1', DATE '2025-01-01', pg_temp.tdoc('{"subjects": {"kind": "any", "excluded": ["weather"]}}')),
  '23503', 'weather');
SELECT pg_temp.refuses_at('U5 a tariff is never edited (its document is what determinations cite)',
  $q$UPDATE public.dispute_tariffs SET tariff_reference = 'changed' WHERE id = '00000000-0000-4000-8000-0000000025ab'$q$, '23001', 'dispute_tariffs');
SELECT pg_temp.refuses_at('U6 nor deleted',
  $q$DELETE FROM public.dispute_tariffs WHERE id = '00000000-0000-4000-8000-0000000025ab'$q$, '42501', 'dispute_tariffs');
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000025b2', true);
SELECT pg_temp.refuses_at('U7 another utility writes no tariff for T1',
  pg_temp.tariff_sql(NULL, '00000000-0000-4000-8000-0000000025a1', DATE '2027-01-01', pg_temp.tdoc()), '42501', 'row-level security');
SELECT pg_temp.ok('U8 the lookup finds T1''s tariff in force on March 12 and none on March 5',
  public.rule_tariff_row_as_of('public.dispute_tariffs', '00000000-0000-4000-8000-0000000025a1', 'gas', 'distribution', 'TX', '{}', DATE '2026-03-12') IS NULL);
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000025b1', true);
SELECT pg_temp.ok('U8b … (as T1 itself: T2 sees none of it)',
  public.rule_tariff_row_as_of('public.dispute_tariffs', '00000000-0000-4000-8000-0000000025a1', 'gas', 'distribution', 'TX', '{}', DATE '2026-03-12')
    = '00000000-0000-4000-8000-0000000025ab'
  AND public.rule_tariff_row_as_of('public.dispute_tariffs', '00000000-0000-4000-8000-0000000025a1', 'gas', 'distribution', 'TX', '{}', DATE '2026-03-05') IS NULL);
RESET ROLE;

-- ============================================================== N never looser than the law (L6)
-- T2 is investor-owned: its tariff is measured against both 16 TAC 7.45 rows in force (protected: blocks
-- disconnects and late fees, before delinquency, average-usage cap, 60 days from issue). Each boundary is
-- tested on both sides.
SET ROLE tally_app;
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000025b2', true);
SELECT pg_temp.refuses_at('N1a blocks that lack one of the law''s (late_fee)',
  pg_temp.tariff_sql(NULL, '00000000-0000-4000-8000-0000000025a2', DATE '2026-01-01', pg_temp.tdoc('{"blocks": {"codes": ["disconnect_order", "disconnect_execute"]}}')),
  '23514', 'late_fee');
SELECT pg_temp.refuses_at('N2a a subject the law admits, excluded',
  pg_temp.tariff_sql(NULL, '00000000-0000-4000-8000-0000000025a2', DATE '2026-01-01', pg_temp.tdoc('{"subjects": {"kind": "any", "excluded": ["deposit"]}}')),
  '23514', 'deposit');
SELECT pg_temp.refuses_at('N2b a listed subject set where the law admits any',
  pg_temp.tariff_sql(NULL, '00000000-0000-4000-8000-0000000025a2', DATE '2026-01-01', pg_temp.tdoc('{"subjects": {"kind": "listed", "codes": ["meter_accuracy"], "excluded": []}}')),
  '23514', 'subjects');
SELECT pg_temp.refuses_at('N3a a narrower start: within 21 days of receipt against before delinquency (not comparable: refused)',
  pg_temp.tariff_sql(NULL, '00000000-0000-4000-8000-0000000025a2', DATE '2026-01-01', pg_temp.tdoc('{"shelter_earned": {"kind": "within_days", "days": 21, "from": "receipt"}}')),
  '23514', 'shelter_earned');
SELECT pg_temp.refuses_at('N3b a narrower start: only on a regulator complaint',
  pg_temp.tariff_sql(NULL, '00000000-0000-4000-8000-0000000025a2', DATE '2026-01-01', pg_temp.tdoc('{"shelter_earned": {"kind": "on_regulator_complaint"}}')),
  '23514', 'shelter_earned');
SELECT pg_temp.refuses_at('N4a a sooner end: 30 days from issue against the law''s 60',
  pg_temp.tariff_sql(NULL, '00000000-0000-4000-8000-0000000025a2', DATE '2026-01-01', pg_temp.tdoc('{"shelter_ends": {"kind": "earlier_of_resolution_and_days", "days": 30, "from": "issue"}}')),
  '23514', 'shelter_ends');
SELECT pg_temp.refuses_at('N4b a sooner end: 59 days',
  pg_temp.tariff_sql(NULL, '00000000-0000-4000-8000-0000000025a2', DATE '2026-01-01', pg_temp.tdoc('{"shelter_ends": {"kind": "earlier_of_resolution_and_days", "days": 59, "from": "issue"}}')),
  '23514', 'shelter_ends');
SELECT pg_temp.refuses_at('N5a a must-pay that asks for more: the full bill',
  pg_temp.tariff_sql(NULL, '00000000-0000-4000-8000-0000000025a2', DATE '2026-01-01', pg_temp.tdoc('{"must_pay": {"strategy": "full_bill", "version": 1, "id": "m1"}}')),
  '23514', 'must_pay');
SELECT pg_temp.refuses_at('N5b the same strategy with other figures: three years of history (not comparable: refused)',
  pg_temp.tariff_sql(NULL, '00000000-0000-4000-8000-0000000025a2', DATE '2026-01-01',
    pg_temp.tdoc('{"must_pay": {"strategy": "average_usage_cap", "version": 1, "id": "m1", "history_years": 3, "no_history": "similar_customers"}}')),
  '23514', 'must_pay');
SELECT pg_temp.refuses_at('N5c a withholding cap against an average-usage cap (not comparable: refused)',
  pg_temp.tariff_sql(NULL, '00000000-0000-4000-8000-0000000025a2', DATE '2026-01-01',
    pg_temp.tdoc('{"must_pay": {"strategy": "withhold_cap", "version": 1, "id": "m1", "fraction": 1.1}}')),
  '23514', 'must_pay');
-- the other side of each boundary
SELECT pg_temp.admits_undone('N4c the law''s own 60 days, and the law''s own cap and start (equal is not looser)',
  pg_temp.tariff_sql(NULL, '00000000-0000-4000-8000-0000000025a2', DATE '2026-01-01', pg_temp.tdoc(
    '{"shelter_earned": {"kind": "before_delinquency"}, "shelter_ends": {"kind": "earlier_of_resolution_and_days", "days": 60, "from": "issue"},
      "must_pay": {"strategy": "average_usage_cap", "version": 1, "id": "m1", "history_years": 2, "no_history": "similar_customers"},
      "blocks": {"codes": ["disconnect_order", "disconnect_execute", "late_fee"]}}')));
SELECT pg_temp.admits('N1b … and every block plus more, a wider start (before termination), a later end (resolution), undisputed charges only',
  pg_temp.tariff_sql('00000000-0000-4000-8000-0000000025ac', '00000000-0000-4000-8000-0000000025a2', DATE '2026-01-01', pg_temp.tdoc()));
SELECT pg_temp.ok('N6 the admitted tariff is the one in force for T2',
  public.rule_tariff_row_as_of('public.dispute_tariffs', '00000000-0000-4000-8000-0000000025a2', 'gas', 'distribution', 'TX', '{}', DATE '2026-03-15')
    = '00000000-0000-4000-8000-0000000025ac');
RESET ROLE;

-- dispute_sql(id, tenant, customer, invoice, reading, subject, received, channel)
CREATE FUNCTION pg_temp.dispute_sql(p_id text, p_tenant text, p_customer text, p_invoice text, p_reading text, p_subject text, p_on date, p_channel text DEFAULT 'written') RETURNS text
LANGUAGE sql IMMUTABLE AS $$
  SELECT format($q$INSERT INTO public.disputes (id, tenant_id, customer_id, invoice_id, reading_id, subject, received_on, channel)
                   VALUES (%L, %L, %L, %L, %L, %L, %L, %L)$q$, p_id, p_tenant, p_customer, p_invoice, p_reading, p_subject, p_on, p_channel)
$$;
-- amount_sql(id, tenant, dispute, amount, determined_by, effective_on)
CREATE FUNCTION pg_temp.amount_sql(p_id text, p_tenant text, p_dispute text, p_amount numeric, p_by text, p_on date) RETURNS text
LANGUAGE sql IMMUTABLE AS $$
  SELECT format($q$INSERT INTO public.dispute_amounts (id, tenant_id, dispute_id, amount, determined_by, effective_on)
                   VALUES (%L, %L, %L, %s, %L, %L)$q$, p_id, p_tenant, p_dispute, p_amount, p_by, p_on)
$$;
CREATE FUNCTION pg_temp.line_sql(p_tenant text, p_amount_row text, p_line text, p_amount numeric) RETURNS text
LANGUAGE sql IMMUTABLE AS $$
  SELECT format($q$INSERT INTO public.dispute_amount_lines (tenant_id, dispute_amount_id, invoice_line_item_id, amount)
                   VALUES (%L, %L, %L, %s)$q$, p_tenant, p_amount_row, p_line, p_amount)
$$;
-- det_sql(id, tenant, dispute, amount row, class, rule, tariff, outcome, sheltered, must pay, component, ends, blocks, supersedes)
CREATE FUNCTION pg_temp.det_sql(p_id text, p_tenant text, p_dispute text, p_amount_row text, p_class text, p_rule uuid, p_tariff text,
                                p_outcome text, p_sheltered numeric, p_must numeric, p_component text, p_ends date, p_blocks text[],
                                p_supersedes text DEFAULT NULL) RETURNS text
LANGUAGE sql IMMUTABLE AS $$
  SELECT format($q$INSERT INTO public.dispute_determinations (id, tenant_id, dispute_id, dispute_amount_id, state_code, service_type, system_kind,
                     customer_class, rule_id, tariff_id, outcome, sheltered_amount, must_pay_amount, must_pay_component, shelter_ends_on, blocks,
                     supersedes_id, inputs, inputs_fingerprint, calculated_by)
                   VALUES (%L, %L, %L, %L, 'TX', 'gas', 'distribution', %L, %L, %L, %L, %s, %s, %L, %L, %L, %L, '{"battery": true}', %L, 'core-battery-25')$q$,
                p_id, p_tenant, p_dispute, p_amount_row, p_class, p_rule, p_tariff, p_outcome,
                coalesce(p_sheltered::text, 'NULL'), coalesce(p_must::text, 'NULL'), p_component, p_ends, p_blocks, p_supersedes,
                'fp-' || left(p_id, 8) || coalesce(p_sheltered::text, ''))
$$;
-- ev_sql(tenant, dispute, type, occurred, stage, decider role, escalated to, outcome, ledger, credit, invoice)
CREATE FUNCTION pg_temp.ev_sql(p_tenant text, p_dispute text, p_type text, p_on date, p_stage text DEFAULT NULL, p_role text DEFAULT NULL,
                               p_to text DEFAULT NULL, p_outcome text DEFAULT NULL, p_ledger text DEFAULT NULL, p_credit text DEFAULT NULL,
                               p_invoice text DEFAULT NULL, p_id text DEFAULT NULL) RETURNS text
LANGUAGE sql IMMUTABLE AS $$
  SELECT format($q$INSERT INTO public.dispute_events (id, tenant_id, dispute_id, event_type, occurred_on, stage_id, decider_user_id, decider_role,
                     escalated_to, outcome, correction_ledger_entry_id, correction_credit_id, correction_invoice_id)
                   VALUES (%s, %L, %L, %L, %L, %L, CASE WHEN %L IS NULL THEN NULL ELSE current_setting('app.user_id')::uuid END, %L, %L, %L, %L, %L, %L)$q$,
                CASE WHEN p_id IS NULL THEN 'DEFAULT' ELSE quote_literal(p_id) END,
                p_tenant, p_dispute, p_type, p_on, p_stage, p_stage, p_role, p_to, p_outcome, p_ledger, p_credit, p_invoice)
$$;
GRANT EXECUTE ON FUNCTION pg_temp.dispute_sql(text, text, text, text, text, text, date, text), pg_temp.amount_sql(text, text, text, numeric, text, date),
  pg_temp.line_sql(text, text, text, numeric),
  pg_temp.det_sql(text, text, text, text, text, uuid, text, text, numeric, numeric, text, date, text[], text),
  pg_temp.ev_sql(text, text, text, date, text, text, text, text, text, text, text, text) TO tally_app;

-- ============================================================== D1 the dispute (CI-074; CRAFT)
SET ROLE tally_app;
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000025b1', true);
SELECT pg_temp.admits('D1 T1''s customer C1 disputes bill I1 in writing on March 12 (a calculation)',
  pg_temp.dispute_sql('00000000-0000-4000-8000-000000002531', '00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-0000000025c1',
                      '00000000-0000-4000-8000-000000002501', NULL, 'calculation', DATE '2026-03-12'));
SELECT pg_temp.ok('D1a it is born open, with no cause and no status time; its created_at is the database''s',
  (SELECT status = 'open' AND status_cause_id IS NULL AND status_recorded_at IS NULL AND created_at = now()
     FROM public.disputes WHERE id = '00000000-0000-4000-8000-000000002531'));
SELECT pg_temp.ok('D1b the database wrote its opened event, the only event (D5)',
  (SELECT count(*) = 1 AND bool_and(event_type = 'opened' AND occurred_on = DATE '2026-03-12')
     FROM public.dispute_events WHERE dispute_id = '00000000-0000-4000-8000-000000002531'));
SELECT pg_temp.admits('D1c a dispute received before T1''s tariff took effect (C1, bill I2, March 5)',
  pg_temp.dispute_sql('00000000-0000-4000-8000-000000002532', '00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-0000000025c1',
                      '00000000-0000-4000-8000-000000002502', NULL, 'meter_accuracy', DATE '2026-03-05', 'oral'));
SELECT pg_temp.admits('D1d a read dispute before any bill: C2''s reading of March 1 (a dispute may name a reading alone)',
  pg_temp.dispute_sql('00000000-0000-4000-8000-000000002533', '00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-0000000025c2',
                      NULL, '00000000-0000-4000-8000-000000002572', 'meter_accuracy', DATE '2026-03-02', 'portal'));
SELECT pg_temp.admits('D1e a read dispute of C1''s reading (for T2 below)',
  pg_temp.dispute_sql('00000000-0000-4000-8000-000000002534', '00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-0000000025c1',
                      NULL, '00000000-0000-4000-8000-000000002571', 'meter_accuracy', DATE '2026-03-02'));
SELECT pg_temp.refuses_at('D1f a dispute that names neither a bill nor a reading',
  pg_temp.dispute_sql(gen_random_uuid()::text, '00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-0000000025c1', NULL, NULL, 'calculation', DATE '2026-03-12'),
  '23514', '[D1a]');
SELECT pg_temp.refuses_at('D1g a bill of another customer (C2''s I3 for C1)',
  pg_temp.dispute_sql(gen_random_uuid()::text, '00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-0000000025c1',
                      '00000000-0000-4000-8000-000000002503', NULL, 'calculation', DATE '2026-03-12'), '23503', 'disputes');
SELECT pg_temp.refuses_at('D1h a bill never issued (the draft I4)',
  pg_temp.dispute_sql(gen_random_uuid()::text, '00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-0000000025c1',
                      '00000000-0000-4000-8000-000000002504', NULL, 'calculation', DATE '2026-03-12'), '23514', '[D1b]');
SELECT pg_temp.refuses_at('D1i a reading at another customer''s location (C2''s reading for C1)',
  pg_temp.dispute_sql(gen_random_uuid()::text, '00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-0000000025c1',
                      NULL, '00000000-0000-4000-8000-000000002572', 'meter_accuracy', DATE '2026-03-02'), '23514', '[D1c]');
SELECT pg_temp.refuses_at('D1j received before the bill was dated (February 28, bill of March 1)',
  pg_temp.dispute_sql(gen_random_uuid()::text, '00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-0000000025c1',
                      '00000000-0000-4000-8000-000000002501', NULL, 'calculation', DATE '2026-02-28'), '23514', '[D1d]');
SELECT pg_temp.admits_undone('D1j2 … received on the bill''s own date is fine',
  pg_temp.dispute_sql(gen_random_uuid()::text, '00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-0000000025c1',
                      '00000000-0000-4000-8000-000000002501', NULL, 'calculation', DATE '2026-03-01'));
SELECT pg_temp.refuses_at('D1k received before the reading was taken',
  pg_temp.dispute_sql(gen_random_uuid()::text, '00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-0000000025c1',
                      NULL, '00000000-0000-4000-8000-000000002571', 'meter_accuracy', DATE '2026-02-27'), '23514', '[D1d]');
SELECT pg_temp.refuses_at('D1l received after today (a date not yet come)',
  pg_temp.dispute_sql(gen_random_uuid()::text, '00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-0000000025c1',
                      '00000000-0000-4000-8000-000000002501', NULL, 'calculation', current_date + 1), '23514', '[D1e]');
SELECT pg_temp.refuses_at('D1m a subject the vocabulary lacks',
  pg_temp.dispute_sql(gen_random_uuid()::text, '00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-0000000025c1',
                      '00000000-0000-4000-8000-000000002501', NULL, 'weather', DATE '2026-03-12'), '23503', 'dispute_subjects');
SELECT pg_temp.refuses_at('D1n a channel that is not written, oral, portal or a regulator referral',
  pg_temp.dispute_sql(gen_random_uuid()::text, '00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-0000000025c1',
                      '00000000-0000-4000-8000-000000002501', NULL, 'calculation', DATE '2026-03-12', 'fax'), '23514', 'disputes_channel_check');
SELECT pg_temp.refuses_at('D1o born resolved',
  $q$INSERT INTO public.disputes (tenant_id, customer_id, invoice_id, subject, received_on, channel, status)
     VALUES ('00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-0000000025c1', '00000000-0000-4000-8000-000000002501', 'calculation', DATE '2026-03-12', 'written', 'resolved')$q$,
  '23514', '[D1h]');
SELECT pg_temp.refuses_at('D1p the application never updates a dispute: not its subject',
  $q$UPDATE public.disputes SET subject = 'other' WHERE id = '00000000-0000-4000-8000-000000002531'$q$, '42501', 'disputes');
SELECT pg_temp.refuses_at('D1q … not its status (the database moves it, from the events)',
  $q$UPDATE public.disputes SET status = 'withdrawn' WHERE id = '00000000-0000-4000-8000-000000002531'$q$, '42501', 'disputes');
SELECT pg_temp.refuses_at('D1r a dispute is never deleted',
  $q$DELETE FROM public.disputes WHERE id = '00000000-0000-4000-8000-000000002531'$q$, '42501', 'disputes');
RESET ROLE;
SELECT pg_temp.refuses_at('D1s even the owner does not edit a dispute''s identity (write-once from insert)',
  $q$UPDATE public.disputes SET invoice_id = '00000000-0000-4000-8000-000000002502' WHERE id = '00000000-0000-4000-8000-000000002531'$q$, '23514', '[D1f]');
SELECT pg_temp.refuses_at('D1t … nor its status directly',
  $q$UPDATE public.disputes SET status = 'resolved' WHERE id = '00000000-0000-4000-8000-000000002531'$q$, '23514', '[D1g]');
SET ROLE tally_app;
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000025b2', true);
SELECT pg_temp.admits('D1u T2''s residential customer C5 disputes I5 on March 15, before it went delinquent (March 20)',
  pg_temp.dispute_sql('00000000-0000-4000-8000-000000002535', '00000000-0000-4000-8000-0000000025a2', '00000000-0000-4000-8000-0000000025c5',
                      '00000000-0000-4000-8000-000000002505', NULL, 'meter_accuracy', DATE '2026-03-15'));
SELECT pg_temp.admits('D1v T2''s large commercial customer C6 disputes I6',
  pg_temp.dispute_sql('00000000-0000-4000-8000-000000002536', '00000000-0000-4000-8000-0000000025a2', '00000000-0000-4000-8000-0000000025c6',
                      '00000000-0000-4000-8000-000000002506', NULL, 'calculation', DATE '2026-03-15'));
SELECT pg_temp.refuses_at('D1w T2 cannot open a dispute in T1''s name',
  pg_temp.dispute_sql(gen_random_uuid()::text, '00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-0000000025c1',
                      '00000000-0000-4000-8000-000000002501', NULL, 'calculation', DATE '2026-03-12'), '42501', 'row-level security');
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000025b3', true);
SELECT pg_temp.admits('D1x T3''s customer C7 disputes I7',
  pg_temp.dispute_sql('00000000-0000-4000-8000-000000002537', '00000000-0000-4000-8000-0000000025a3', '00000000-0000-4000-8000-0000000025c7',
                      '00000000-0000-4000-8000-000000002507', NULL, 'calculation', DATE '2026-03-15'));
RESET ROLE;

-- ============================================================== D2 the disputed amount
SET ROLE tally_app;
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000025b1', true);
SELECT pg_temp.admits('D2 C1 claims 40 on I1, all of it the add-on line',
  'SELECT pg_temp.deferred(' || quote_literal(
     pg_temp.amount_sql('00000000-0000-4000-8000-000000002541', '00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-000000002531', 40, 'customer_claim', DATE '2026-03-12')
     || '; ' || pg_temp.line_sql('00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-000000002541', '00000000-0000-4000-8000-000000002512', 40)) || ')');
SELECT pg_temp.refuses_at('D2a lines that do not add up to the amount (30 of 40), checked at commit',
  'SELECT pg_temp.deferred(' || quote_literal(
     pg_temp.amount_sql('00000000-0000-4000-8000-000000002549', '00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-000000002531', 40, 'agreed', DATE '2026-03-13')
     || '; ' || pg_temp.line_sql('00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-000000002549', '00000000-0000-4000-8000-000000002511', 30)) || ')',
  '23514', '[D2a]');
SELECT pg_temp.refuses_at('D2b a line of another bill (I2''s line on I1''s dispute)',
  'SELECT pg_temp.deferred(' || quote_literal(
     pg_temp.amount_sql('00000000-0000-4000-8000-000000002549', '00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-000000002531', 40, 'agreed', DATE '2026-03-13')
     || '; ' || pg_temp.line_sql('00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-000000002549', '00000000-0000-4000-8000-000000002515', 40)) || ')',
  '23503', 'dispute_amount_lines');
SELECT pg_temp.refuses_at('D2c a line amount above what the line charges (45 on the 40 add-on)',
  'SELECT pg_temp.deferred(' || quote_literal(
     pg_temp.amount_sql('00000000-0000-4000-8000-000000002549', '00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-000000002531', 45, 'agreed', DATE '2026-03-13')
     || '; ' || pg_temp.line_sql('00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-000000002549', '00000000-0000-4000-8000-000000002512', 45)) || ')',
  '23514', '[D2c]');
SELECT pg_temp.refuses_at('D2c2 … a credit line is not a charge to dispute',
  'SELECT pg_temp.deferred(' || quote_literal(
     pg_temp.amount_sql('00000000-0000-4000-8000-000000002549', '00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-000000002531', 5, 'agreed', DATE '2026-03-13')
     || '; ' || pg_temp.line_sql('00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-000000002549', '00000000-0000-4000-8000-000000002513', 5)) || ')',
  '23514', '[D2c]');
SELECT pg_temp.refuses_at('D2d an amount of zero',
  pg_temp.amount_sql(gen_random_uuid()::text, '00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-000000002531', 0, 'customer_claim', DATE '2026-03-12'),
  '23514', 'dispute_amounts_amount_check');
SELECT pg_temp.refuses_at('D2e a determiner that is not the customer, an agreement, the utility or a regulator''s interim estimate',
  pg_temp.amount_sql(gen_random_uuid()::text, '00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-000000002531', 10, 'court', DATE '2026-03-12'),
  '23514', 'dispute_amounts_determined_by_check');
SELECT pg_temp.refuses_at('D2f an amount effective before the dispute was received',
  pg_temp.amount_sql(gen_random_uuid()::text, '00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-000000002531', 10, 'customer_claim', DATE '2026-03-11'),
  '23514', '[D2d]');
SELECT pg_temp.admits('D2g a revision is a new row: the regulator''s interim estimate of 35 (FL''s shape), no lines',
  pg_temp.amount_sql('00000000-0000-4000-8000-000000002542', '00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-000000002531', 35, 'regulator_interim', DATE '2026-03-14'));
SELECT pg_temp.refuses_at('D2h an amount row is never edited',
  $q$UPDATE public.dispute_amounts SET amount = 1 WHERE id = '00000000-0000-4000-8000-000000002541'$q$, '42501', 'dispute_amounts');
SELECT pg_temp.admits('D2i C1''s I2 dispute: 20; C2''s reading dispute: 10; C1''s reading dispute: 15',
  pg_temp.amount_sql('00000000-0000-4000-8000-000000002543', '00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-000000002532', 20, 'customer_claim', DATE '2026-03-05')
  || '; ' || pg_temp.amount_sql('00000000-0000-4000-8000-000000002544', '00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-000000002533', 10, 'customer_claim', DATE '2026-03-02')
  || '; ' || pg_temp.amount_sql('00000000-0000-4000-8000-00000000254b', '00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-000000002534', 15, 'customer_claim', DATE '2026-03-02'));
SELECT pg_temp.refuses_at('D2j a reading dispute''s amount has no bill lines to name',
  'SELECT pg_temp.deferred(' || quote_literal(
     pg_temp.line_sql('00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-000000002544', '00000000-0000-4000-8000-000000002517', 10)) || ')',
  '23503', 'dispute_amount_lines');
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000025b2', true);
SELECT pg_temp.admits('D2k T2: C5 disputes 40 of I5, all on its add-on line; C6 disputes 90 of I6',
  'SELECT pg_temp.deferred(' || quote_literal(
     pg_temp.amount_sql('00000000-0000-4000-8000-000000002545', '00000000-0000-4000-8000-0000000025a2', '00000000-0000-4000-8000-000000002535', 40, 'customer_claim', DATE '2026-03-15')
     || '; ' || pg_temp.line_sql('00000000-0000-4000-8000-0000000025a2', '00000000-0000-4000-8000-000000002545', '00000000-0000-4000-8000-000000002522', 40)) || ')'
  || '; ' || pg_temp.amount_sql('00000000-0000-4000-8000-000000002546', '00000000-0000-4000-8000-0000000025a2', '00000000-0000-4000-8000-000000002536', 90, 'customer_claim', DATE '2026-03-15'));
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000025b3', true);
SELECT pg_temp.admits('D2l T3: C7 disputes 40 of I7',
  pg_temp.amount_sql('00000000-0000-4000-8000-000000002547', '00000000-0000-4000-8000-0000000025a3', '00000000-0000-4000-8000-000000002537', 40, 'customer_claim', DATE '2026-03-15'));
RESET ROLE;

-- ============================================================== D3/D4 the determination
SET ROLE tally_app;
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000025b1', true);
SELECT pg_temp.admits('D3 T1''s determination on C1''s I1 dispute: under the city''s delegation and its own tariff, 40 sheltered, the full 90 still to pay, until resolution',
  pg_temp.det_sql('00000000-0000-4000-8000-000000002551', '00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-000000002531', '00000000-0000-4000-8000-000000002541',
                  'protected', pg_temp.law('municipal', 'protected'), '00000000-0000-4000-8000-0000000025ab', 'sheltered', 40, 90, 'm1', NULL,
                  '{disconnect_order,disconnect_execute,credit_reporting}'));
SELECT pg_temp.ok('D3a its created_at is the database''s',
  (SELECT created_at = now() FROM public.dispute_determinations WHERE id = '00000000-0000-4000-8000-000000002551'));
SELECT pg_temp.refuses_at('D4a a law row of another class than the class recorded (protected recorded, the unprotected row cited)',
  pg_temp.det_sql(gen_random_uuid()::text, '00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-000000002531', '00000000-0000-4000-8000-000000002541',
                  'protected', pg_temp.law('municipal', 'unprotected'), '00000000-0000-4000-8000-0000000025ab', 'sheltered', 40, 90, 'm1', NULL,
                  '{disconnect_order,disconnect_execute,credit_reporting}', '00000000-0000-4000-8000-000000002551'), '23514', '[D4a]');
SELECT pg_temp.refuses_at('D4b a law row that does not bind the utility''s owner type (the investor-owned row for a city)',
  pg_temp.det_sql(gen_random_uuid()::text, '00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-000000002531', '00000000-0000-4000-8000-000000002541',
                  'protected', pg_temp.law('investor_owned', 'protected'), NULL, 'sheltered', 40, 50, 'm1', DATE '2026-04-29',
                  '{disconnect_order,disconnect_execute,late_fee}', '00000000-0000-4000-8000-000000002551'), '23514', '[D4a]');
SELECT pg_temp.refuses_at('D4c a tariff not in force on the day the dispute was received (I2''s dispute of March 5; the tariff from March 10)',
  pg_temp.det_sql(gen_random_uuid()::text, '00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-000000002532', '00000000-0000-4000-8000-000000002543',
                  'protected', pg_temp.law('municipal', 'protected'), '00000000-0000-4000-8000-0000000025ab', 'sheltered', 20, 90, 'm1', NULL,
                  '{disconnect_order,disconnect_execute,credit_reporting}'), '23514', '[D4c]');
SELECT pg_temp.refuses_at('D4d under a delegation, a shelter with no tariff behind it (K-07: no assumed default)',
  pg_temp.det_sql(gen_random_uuid()::text, '00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-000000002532', '00000000-0000-4000-8000-000000002543',
                  'protected', pg_temp.law('municipal', 'protected'), NULL, 'sheltered', 20, 0, 'm1', NULL, '{disconnect_order}'), '23514', '[D4d]');
SELECT pg_temp.refuses_at('D4e "no terms" while the utility''s tariff is in force (March 12)',
  pg_temp.det_sql(gen_random_uuid()::text, '00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-000000002531', '00000000-0000-4000-8000-000000002541',
                  'protected', pg_temp.law('municipal', 'protected'), NULL, 'no_terms', 0, NULL, NULL, NULL, '{}', '00000000-0000-4000-8000-000000002551'), '23514', '[D4e]');
SELECT pg_temp.refuses_at('D4f another utility''s tariff (T2''s, which T1 cannot see)',
  pg_temp.det_sql(gen_random_uuid()::text, '00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-000000002531', '00000000-0000-4000-8000-000000002541',
                  'protected', pg_temp.law('municipal', 'protected'), '00000000-0000-4000-8000-0000000025ac', 'sheltered', 40, 50, 'm1', NULL,
                  '{notice_issue,disconnect_order,disconnect_execute,late_fee}', '00000000-0000-4000-8000-000000002551'), '23514', '[D4f]');
SELECT pg_temp.refuses_at('D4g a must-pay component the cited document does not have',
  pg_temp.det_sql(gen_random_uuid()::text, '00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-000000002531', '00000000-0000-4000-8000-000000002541',
                  'protected', pg_temp.law('municipal', 'protected'), '00000000-0000-4000-8000-0000000025ab', 'sheltered', 40, 90, 'm9', NULL,
                  '{disconnect_order,disconnect_execute,credit_reporting}', '00000000-0000-4000-8000-000000002551'), '23514', '[D4g]');
SELECT pg_temp.refuses_at('D4h blocks other than the cited document''s (late_fee claimed; the tariff blocks credit reporting instead)',
  pg_temp.det_sql(gen_random_uuid()::text, '00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-000000002531', '00000000-0000-4000-8000-000000002541',
                  'protected', pg_temp.law('municipal', 'protected'), '00000000-0000-4000-8000-0000000025ab', 'sheltered', 40, 90, 'm1', NULL,
                  '{disconnect_order,disconnect_execute,late_fee}', '00000000-0000-4000-8000-000000002551'), '23514', '[D4h]');
SELECT pg_temp.refuses_at('D4i more sheltered than the amount row it read (41 of 40)',
  pg_temp.det_sql(gen_random_uuid()::text, '00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-000000002531', '00000000-0000-4000-8000-000000002541',
                  'protected', pg_temp.law('municipal', 'protected'), '00000000-0000-4000-8000-0000000025ab', 'sheltered', 41, 90, 'm1', NULL,
                  '{disconnect_order,disconnect_execute,credit_reporting}', '00000000-0000-4000-8000-000000002551'), '23514', '[D4i]');
SELECT pg_temp.refuses_at('D4i2 a negative amount to pay',
  pg_temp.det_sql(gen_random_uuid()::text, '00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-000000002531', '00000000-0000-4000-8000-000000002541',
                  'protected', pg_temp.law('municipal', 'protected'), '00000000-0000-4000-8000-0000000025ab', 'sheltered', 40, -1, 'm1', NULL,
                  '{disconnect_order,disconnect_execute,credit_reporting}', '00000000-0000-4000-8000-000000002551'), '23514', '[D4i]');
SELECT pg_temp.refuses_at('D4j an amount row of another dispute',
  pg_temp.det_sql(gen_random_uuid()::text, '00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-000000002531', '00000000-0000-4000-8000-000000002543',
                  'protected', pg_temp.law('municipal', 'protected'), '00000000-0000-4000-8000-0000000025ab', 'sheltered', 20, 90, 'm1', NULL,
                  '{disconnect_order,disconnect_execute,credit_reporting}', '00000000-0000-4000-8000-000000002551'), '23514', '[D4j]');
SELECT pg_temp.refuses_at('D4m a second live determination for one dispute (it must name the one it supersedes)',
  pg_temp.det_sql(gen_random_uuid()::text, '00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-000000002531', '00000000-0000-4000-8000-000000002542',
                  'protected', pg_temp.law('municipal', 'protected'), '00000000-0000-4000-8000-0000000025ab', 'sheltered', 35, 90, 'm1', NULL,
                  '{disconnect_order,disconnect_execute,credit_reporting}'), '23514', '[D4m]');
SELECT pg_temp.refuses_at('D4o a shelter that ends before the dispute was received',
  pg_temp.det_sql(gen_random_uuid()::text, '00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-000000002531', '00000000-0000-4000-8000-000000002542',
                  'protected', pg_temp.law('municipal', 'protected'), '00000000-0000-4000-8000-0000000025ab', 'sheltered', 35, 90, 'm1', DATE '2026-03-11',
                  '{disconnect_order,disconnect_execute,credit_reporting}', '00000000-0000-4000-8000-000000002551'), '23514', '[D4o]');
SELECT pg_temp.refuses_at('D4p a class the state''s vocabulary lacks',
  pg_temp.det_sql(gen_random_uuid()::text, '00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-000000002531', '00000000-0000-4000-8000-000000002542',
                  'governmental', pg_temp.law('municipal', 'protected'), '00000000-0000-4000-8000-0000000025ab', 'sheltered', 35, 90, 'm1', NULL,
                  '{disconnect_order,disconnect_execute,credit_reporting}', '00000000-0000-4000-8000-000000002551'), '23503', 'dispute_customer_classes');
SELECT pg_temp.refuses_at('D4q an outcome that is not sheltered, not sheltered, or no terms',
  pg_temp.det_sql(gen_random_uuid()::text, '00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-000000002531', '00000000-0000-4000-8000-000000002542',
                  'protected', pg_temp.law('municipal', 'protected'), '00000000-0000-4000-8000-0000000025ab', 'pending', 35, 90, 'm1', NULL,
                  '{disconnect_order,disconnect_execute,credit_reporting}', '00000000-0000-4000-8000-000000002551'), '23514', 'dispute_determinations_outcome_check');
SELECT pg_temp.admits('D4r the interim estimate supersedes: 35 sheltered, naming the row it replaces',
  pg_temp.det_sql('00000000-0000-4000-8000-000000002552', '00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-000000002531', '00000000-0000-4000-8000-000000002542',
                  'protected', pg_temp.law('municipal', 'protected'), '00000000-0000-4000-8000-0000000025ab', 'sheltered', 35, 90, 'm1', NULL,
                  '{disconnect_order,disconnect_execute,credit_reporting}', '00000000-0000-4000-8000-000000002551'));
SELECT pg_temp.refuses_at('D4s superseding a row already superseded',
  pg_temp.det_sql(gen_random_uuid()::text, '00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-000000002531', '00000000-0000-4000-8000-000000002542',
                  'protected', pg_temp.law('municipal', 'protected'), '00000000-0000-4000-8000-0000000025ab', 'sheltered', 30, 90, 'm1', NULL,
                  '{disconnect_order,disconnect_execute,credit_reporting}', '00000000-0000-4000-8000-000000002551'), '23514', '[D4m]');
SELECT pg_temp.refuses_at('D4t superseding another dispute''s determination',
  pg_temp.det_sql(gen_random_uuid()::text, '00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-000000002532', '00000000-0000-4000-8000-000000002543',
                  'protected', pg_temp.law('municipal', 'protected'), NULL, 'no_terms', 0, NULL, NULL, NULL, '{}', '00000000-0000-4000-8000-000000002552'), '23514', '[D4m]');
SELECT pg_temp.admits('D4u I2''s dispute, received before the tariff: no terms (a city with no policy in force; the delegation cited, no tariff)',
  pg_temp.det_sql('00000000-0000-4000-8000-000000002553', '00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-000000002532', '00000000-0000-4000-8000-000000002543',
                  'protected', pg_temp.law('municipal', 'protected'), NULL, 'no_terms', 0, NULL, NULL, NULL, '{}'));
SELECT pg_temp.refuses_at('D4n no terms that still shelters something',
  pg_temp.det_sql(gen_random_uuid()::text, '00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-000000002532', '00000000-0000-4000-8000-000000002543',
                  'protected', pg_temp.law('municipal', 'protected'), NULL, 'no_terms', 10, NULL, NULL, NULL, '{}', '00000000-0000-4000-8000-000000002553'), '23514', '[D4n]');
SELECT pg_temp.refuses_at('D4n2 no terms that names a must-pay component',
  pg_temp.det_sql(gen_random_uuid()::text, '00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-000000002532', '00000000-0000-4000-8000-000000002543',
                  'protected', pg_temp.law('municipal', 'protected'), NULL, 'no_terms', 0, 20, 'm1', NULL, '{}', '00000000-0000-4000-8000-000000002553'), '23514', '[D4n]');
SELECT pg_temp.refuses_at('D4v a determination is never edited',
  $q$UPDATE public.dispute_determinations SET sheltered_amount = 1 WHERE id = '00000000-0000-4000-8000-000000002552'$q$, '42501', 'dispute_determinations');
SELECT pg_temp.refuses_at('D4w nor deleted',
  $q$DELETE FROM public.dispute_determinations WHERE id = '00000000-0000-4000-8000-000000002551'$q$, '42501', 'dispute_determinations');
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000025b2', true);
SELECT pg_temp.admits('D4x T2: C5''s dispute is sheltered by 16 TAC 7.45 (protected class): 40 sheltered, 50 to pay (the average cap), until April 29 (60 days from issue)',
  pg_temp.det_sql('00000000-0000-4000-8000-000000002555', '00000000-0000-4000-8000-0000000025a2', '00000000-0000-4000-8000-000000002535', '00000000-0000-4000-8000-000000002545',
                  'protected', pg_temp.law('investor_owned', 'protected'), NULL, 'sheltered', 40, 50, 'm1', DATE '2026-04-29',
                  '{disconnect_order,disconnect_execute,late_fee}'));
SELECT pg_temp.admits('D4y T2: C6 is outside 7.45''s reach (unprotected): not sheltered, the full 90 to pay, nothing blocked',
  pg_temp.det_sql('00000000-0000-4000-8000-000000002556', '00000000-0000-4000-8000-0000000025a2', '00000000-0000-4000-8000-000000002536', '00000000-0000-4000-8000-000000002546',
                  'unprotected', pg_temp.law('investor_owned', 'unprotected'), NULL, 'not_sheltered', 0, 90, 'm1', NULL, '{}'));
SELECT pg_temp.refuses_at('D4z not sheltered that still shelters something',
  pg_temp.det_sql(gen_random_uuid()::text, '00000000-0000-4000-8000-0000000025a2', '00000000-0000-4000-8000-000000002536', '00000000-0000-4000-8000-000000002546',
                  'unprotected', pg_temp.law('investor_owned', 'unprotected'), NULL, 'not_sheltered', 5, 85, 'm1', NULL, '{}', '00000000-0000-4000-8000-000000002556'), '23514', '[D4n]');
SELECT pg_temp.refuses_at('D4z2 T2 cannot write a determination on T1''s dispute',
  pg_temp.det_sql(gen_random_uuid()::text, '00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-000000002531', '00000000-0000-4000-8000-000000002542',
                  'protected', pg_temp.law('municipal', 'protected'), '00000000-0000-4000-8000-0000000025ab', 'sheltered', 35, 90, 'm1', NULL,
                  '{disconnect_order,disconnect_execute,credit_reporting}', '00000000-0000-4000-8000-000000002552'), '42501', 'row-level security');
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000025b3', true);
SELECT pg_temp.admits('D4z3 T3 (a city with no dispute tariff): no terms',
  pg_temp.det_sql('00000000-0000-4000-8000-000000002557', '00000000-0000-4000-8000-0000000025a3', '00000000-0000-4000-8000-000000002537', '00000000-0000-4000-8000-000000002547',
                  'protected', pg_temp.law('municipal', 'protected'), NULL, 'no_terms', 0, NULL, NULL, NULL, '{}'));
RESET ROLE;

-- ============================================================== D5 the events
SET ROLE tally_app;
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000025b1', true);
SELECT pg_temp.refuses_at('D5a the application writes no opened event (the database wrote it)',
  pg_temp.ev_sql('00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-000000002531', 'opened', DATE '2026-03-12'), '23514', '[D5a]');
SELECT pg_temp.admits('D5b stage s1 of the tariff the live determination cites, before a designated employee',
  pg_temp.ev_sql('00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-000000002531', 'stage_entered', DATE '2026-03-13', 's1', 'designated_employee'));
SELECT pg_temp.refuses_at('D5c a stage the document does not have',
  pg_temp.ev_sql('00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-000000002531', 'stage_entered', DATE '2026-03-13', 's2', 'executive'), '23514', '[D5b]');
SELECT pg_temp.refuses_at('D5d a decider other than the stage''s',
  pg_temp.ev_sql('00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-000000002531', 'decided', DATE '2026-03-20', 's1', 'manager'), '23514', '[D5b]');
SELECT pg_temp.refuses_at('D5e a stage event with no live determination to name the stage (C2''s reading dispute)',
  pg_temp.ev_sql('00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-000000002533', 'stage_entered', DATE '2026-03-03', 's1', 'designated_employee'), '23514', '[D5c]');
SELECT pg_temp.refuses_at('D5f an escalation to someone other than the regulator or the governing body',
  pg_temp.ev_sql('00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-000000002531', 'escalated', DATE '2026-03-20', NULL, NULL, 'mayor'), '23514', 'dispute_events_escalated_to_check');
SELECT pg_temp.refuses_at('D5g an event dated before the dispute was received',
  pg_temp.ev_sql('00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-000000002531', 'escalated', DATE '2026-03-11', NULL, NULL, 'regulator'), '23514', '[D5g]');
SELECT pg_temp.refuses_at('D5h a resolution with no outcome',
  pg_temp.ev_sql('00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-000000002531', 'resolved', DATE '2026-04-10'), '23514', '[D5d]');
SELECT pg_temp.refuses_at('D5i an adjusted resolution that names nothing it produced',
  pg_temp.ev_sql('00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-000000002531', 'resolved', DATE '2026-04-10', NULL, NULL, NULL, 'adjusted'), '23514', '[D5d]');
SELECT pg_temp.refuses_at('D5j … or names two things',
  pg_temp.ev_sql('00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-000000002531', 'resolved', DATE '2026-04-10', NULL, NULL, NULL, 'adjusted',
                 '00000000-0000-4000-8000-000000002582', '00000000-0000-4000-8000-000000002581'), '23514', '[D5d]');
SELECT pg_temp.refuses_at('D5k a sustained resolution that names a correction',
  pg_temp.ev_sql('00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-000000002531', 'resolved', DATE '2026-04-10', NULL, NULL, NULL, 'sustained',
                 '00000000-0000-4000-8000-000000002582'), '23514', '[D5d]');
SELECT pg_temp.refuses_at('D5l an adjustment of another customer (C2''s entry for C1''s dispute)',
  pg_temp.ev_sql('00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-000000002531', 'resolved', DATE '2026-04-10', NULL, NULL, NULL, 'adjusted',
                 '00000000-0000-4000-8000-000000002583'), '23514', '[D5e]');
SELECT pg_temp.admits('D5m C1''s I1 dispute is resolved: the bill is sustained, April 10',
  pg_temp.ev_sql('00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-000000002531', 'resolved', DATE '2026-04-10', NULL, NULL, NULL, 'sustained',
                 NULL, NULL, NULL, '00000000-0000-4000-8000-000000002561'));
SELECT pg_temp.ok('D5n the database moved the status: resolved, naming the event, at its stamp',
  (SELECT d.status = 'resolved' AND d.status_cause_id = '00000000-0000-4000-8000-000000002561' AND d.status_recorded_at = e.created_at
     FROM public.disputes d JOIN public.dispute_events e ON e.id = d.status_cause_id
    WHERE d.id = '00000000-0000-4000-8000-000000002531'));
SELECT pg_temp.refuses_at('D5o a second resolution',
  pg_temp.ev_sql('00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-000000002531', 'withdrawn', DATE '2026-04-11'), '23514', '[D5f]');
SELECT pg_temp.refuses_at('D5p any event after the resolution',
  pg_temp.ev_sql('00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-000000002531', 'escalated', DATE '2026-04-11', NULL, NULL, 'regulator'), '23514', '[D5f]');
SELECT pg_temp.refuses_at('D4k a determination after the resolution',
  pg_temp.det_sql(gen_random_uuid()::text, '00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-000000002531', '00000000-0000-4000-8000-000000002542',
                  'protected', pg_temp.law('municipal', 'protected'), '00000000-0000-4000-8000-0000000025ab', 'sheltered', 30, 90, 'm1', NULL,
                  '{disconnect_order,disconnect_execute,credit_reporting}', '00000000-0000-4000-8000-000000002552'), '23514', '[D4k]');
SELECT pg_temp.refuses_at('D2m an amount after the resolution',
  pg_temp.amount_sql(gen_random_uuid()::text, '00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-000000002531', 10, 'agreed', DATE '2026-04-12'), '23514', '[D2e]');
SELECT pg_temp.admits('D5q C1''s I2 dispute is resolved adjusted, naming the adjustment entry that produced',
  pg_temp.ev_sql('00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-000000002532', 'resolved', DATE '2026-04-10', NULL, NULL, NULL, 'adjusted',
                 '00000000-0000-4000-8000-000000002582'));
SELECT pg_temp.admits('D5r C2''s reading dispute is withdrawn',
  pg_temp.ev_sql('00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-000000002533', 'withdrawn', DATE '2026-03-20', NULL, NULL, NULL, NULL,
                 NULL, NULL, NULL, '00000000-0000-4000-8000-000000002563'));
SELECT pg_temp.ok('D5s … and its status is withdrawn, naming the event',
  (SELECT status = 'withdrawn' AND status_cause_id = '00000000-0000-4000-8000-000000002563' FROM public.disputes WHERE id = '00000000-0000-4000-8000-000000002533'));
SELECT pg_temp.refuses_at('D5t a withdrawal with an outcome',
  pg_temp.ev_sql('00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-000000002534', 'withdrawn', DATE '2026-03-20', NULL, NULL, NULL, 'waived'), '23514', '[D5d]');
SELECT pg_temp.refuses_at('D5u an event is never edited',
  $q$UPDATE public.dispute_events SET occurred_on = DATE '2026-04-01' WHERE id = '00000000-0000-4000-8000-000000002561'$q$, '42501', 'dispute_events');
RESET ROLE;
SELECT pg_temp.refuses_at('D5v … not even by the owner (append-only)',
  $q$UPDATE public.dispute_events SET occurred_on = DATE '2026-04-01' WHERE id = '00000000-0000-4000-8000-000000002561'$q$, '23001', 'append-only');

-- ============================================================== R the reader (D6)
-- Dispute 38 (T1, C2, bill I3) is a history load written by the owner at chosen recorded instants:
-- received March 12; amount 40 (no lines) recorded 5 h ago; determination 58 (40 sheltered) 4 h ago;
-- 59 supersedes it (20 sheltered) 3 h ago; resolved on April 10, recorded 1 h ago.
INSERT INTO public.disputes (id, tenant_id, customer_id, invoice_id, subject, received_on, channel, created_at)
VALUES ('00000000-0000-4000-8000-000000002538', '00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-0000000025c2', '00000000-0000-4000-8000-000000002503',
        'calculation', DATE '2026-03-12', 'written', now() - interval '5 hours');
INSERT INTO public.dispute_amounts (id, tenant_id, dispute_id, amount, determined_by, effective_on, created_at)
VALUES ('00000000-0000-4000-8000-000000002548', '00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-000000002538', 40, 'customer_claim', DATE '2026-03-12', now() - interval '5 hours');
INSERT INTO public.dispute_determinations (id, tenant_id, dispute_id, dispute_amount_id, state_code, service_type, system_kind, customer_class, rule_id, tariff_id,
                                           outcome, sheltered_amount, must_pay_amount, must_pay_component, shelter_ends_on, blocks, supersedes_id, inputs, inputs_fingerprint, calculated_by, created_at)
VALUES ('00000000-0000-4000-8000-000000002558', '00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-000000002538', '00000000-0000-4000-8000-000000002548',
        'TX', 'gas', 'distribution', 'protected', pg_temp.law('municipal', 'protected'), '00000000-0000-4000-8000-0000000025ab',
        'sheltered', 40, 90, 'm1', NULL, '{disconnect_order,disconnect_execute,credit_reporting}', NULL, '{}', 'fp-58', 'core-battery-25', now() - interval '4 hours'),
       ('00000000-0000-4000-8000-000000002559', '00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-000000002538', '00000000-0000-4000-8000-000000002548',
        'TX', 'gas', 'distribution', 'protected', pg_temp.law('municipal', 'protected'), '00000000-0000-4000-8000-0000000025ab',
        'sheltered', 20, 90, 'm1', NULL, '{disconnect_order,disconnect_execute,credit_reporting}', '00000000-0000-4000-8000-000000002558', '{}', 'fp-59', 'core-battery-25', now() - interval '3 hours');
INSERT INTO public.dispute_events (tenant_id, dispute_id, event_type, occurred_on, outcome, created_at)
VALUES ('00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-000000002538', 'resolved', DATE '2026-04-10', 'waived', now() - interval '1 hour');
SET ROLE tally_app;
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000025b1', true);
SELECT pg_temp.refuses_at('R1 the date is required (no fallback to today)',
  $q$SELECT * FROM public.dispute_shelter_as_of('00000000-0000-4000-8000-000000002503', NULL, now())$q$, '22004', 'dispute_shelter_as_of');
SELECT pg_temp.refuses_at('R1b the recorded instant is required',
  $q$SELECT * FROM public.dispute_shelter_as_of('00000000-0000-4000-8000-000000002503', DATE '2026-04-01', NULL)$q$, '22004', 'dispute_shelter_as_of');
SELECT pg_temp.ok('R2 as recorded now, on April 9: the live determination, 20 sheltered, its blocks',
  (SELECT count(*) = 1 AND bool_and(determination_id = '00000000-0000-4000-8000-000000002559' AND outcome = 'sheltered' AND sheltered_amount = 20
                                    AND must_pay_amount = 90 AND blocks = '{disconnect_order,disconnect_execute,credit_reporting}')
     FROM public.dispute_shelter_as_of('00000000-0000-4000-8000-000000002503', DATE '2026-04-09', now())));
SELECT pg_temp.ok('R3 as recorded 3.5 h ago: the determination then live, 40 sheltered',
  (SELECT count(*) = 1 AND bool_and(determination_id = '00000000-0000-4000-8000-000000002558' AND sheltered_amount = 40)
     FROM public.dispute_shelter_as_of('00000000-0000-4000-8000-000000002503', DATE '2026-04-09', now() - interval '210 minutes')));
SELECT pg_temp.ok('R4 as recorded 4.5 h ago: the dispute is open with no determination yet: a row with no outcome and nothing sheltered',
  (SELECT count(*) = 1 AND bool_and(determination_id IS NULL AND outcome IS NULL AND sheltered_amount = 0 AND blocks = '{}')
     FROM public.dispute_shelter_as_of('00000000-0000-4000-8000-000000002503', DATE '2026-04-09', now() - interval '270 minutes')));
SELECT pg_temp.ok('R4b as recorded 6 h ago: no dispute at all',
  NOT EXISTS (SELECT 1 FROM public.dispute_shelter_as_of('00000000-0000-4000-8000-000000002503', DATE '2026-04-09', now() - interval '6 hours')));
SELECT pg_temp.ok('R5 on the resolution date, as recorded now: the shelter has ended (nothing to reset: CI-074''s "suspension persists" failure)',
  NOT EXISTS (SELECT 1 FROM public.dispute_shelter_as_of('00000000-0000-4000-8000-000000002503', DATE '2026-04-10', now())));
SELECT pg_temp.ok('R5b on the resolution date, as recorded before the resolution was: still 20',
  (SELECT bool_and(sheltered_amount = 20) AND count(*) = 1
     FROM public.dispute_shelter_as_of('00000000-0000-4000-8000-000000002503', DATE '2026-04-10', now() - interval '2 hours')));
SELECT pg_temp.ok('R6 before the dispute was received (March 11): nothing',
  NOT EXISTS (SELECT 1 FROM public.dispute_shelter_as_of('00000000-0000-4000-8000-000000002503', DATE '2026-03-11', now())));
SELECT pg_temp.ok('R8 per line, with no lines on the amount: pro rata over the bill''s charges (60 and 40), the credit line none, and it says so',
  (SELECT sheltered_amount = 12 AND basis = 'pro_rata' FROM public.dispute_line_shelter_as_of('00000000-0000-4000-8000-000000002517', DATE '2026-04-09', now()))
  AND (SELECT sheltered_amount = 8 AND basis = 'pro_rata' FROM public.dispute_line_shelter_as_of('00000000-0000-4000-8000-000000002518', DATE '2026-04-09', now()))
  AND (SELECT coalesce(sum(sheltered_amount), 0) = 0 FROM public.dispute_line_shelter_as_of('00000000-0000-4000-8000-000000002519', DATE '2026-04-09', now())));
SELECT pg_temp.ok('R11 a no-terms dispute reads as no terms, nothing sheltered, nothing blocked',
  NOT EXISTS (SELECT 1 FROM public.dispute_shelter_as_of('00000000-0000-4000-8000-000000002502', DATE '2026-04-11', now()))
  AND (SELECT bool_and(outcome = 'no_terms' AND sheltered_amount = 0 AND blocks = '{}') AND count(*) = 1
         FROM public.dispute_shelter_as_of('00000000-0000-4000-8000-000000002502', DATE '2026-03-20', now())));
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000025b2', true);
SELECT pg_temp.ok('R7 T2, 16 TAC 7.45: sheltered on April 29 (day 60 from issue)',
  (SELECT bool_and(sheltered_amount = 40 AND blocks = '{disconnect_order,disconnect_execute,late_fee}') AND count(*) = 1
     FROM public.dispute_shelter_as_of('00000000-0000-4000-8000-000000002505', DATE '2026-04-29', now())));
SELECT pg_temp.ok('R7b … and not on April 30',
  (SELECT coalesce(sum(sheltered_amount), 0) = 0 FROM public.dispute_shelter_as_of('00000000-0000-4000-8000-000000002505', DATE '2026-04-30', now())));
SELECT pg_temp.ok('R8b per line, with lines: I5''s add-on line carries the 40 sheltered; its gas service line nothing',
  (SELECT sheltered_amount = 40 AND basis = 'lines'
     FROM public.dispute_line_shelter_as_of('00000000-0000-4000-8000-000000002522', DATE '2026-04-01', now()))
  AND (SELECT coalesce(sum(sheltered_amount), 0) = 0
         FROM public.dispute_line_shelter_as_of('00000000-0000-4000-8000-000000002521', DATE '2026-04-01', now())));
SELECT pg_temp.ok('R10 T2 reads nothing of T1''s disputes',
  NOT EXISTS (SELECT 1 FROM public.dispute_shelter_as_of('00000000-0000-4000-8000-000000002503', DATE '2026-04-09', now())));
RESET ROLE;

-- ============================================================== T the two meaning changes
SELECT pg_temp.ok('T1a pending_dispute no longer protects the account, and points at disputes (CI-074)',
  (SELECT NOT is_disconnect_protective AND description ~* 'disputes' FROM public.program_types WHERE code = 'pending_dispute'));
SELECT pg_temp.ok('T1b no other program type''s protection changed',
  (SELECT bool_and(is_disconnect_protective = (code <> ALL (ARRAY['agency_pledge', 'budget_billing', 'third_party_notification'])))
     FROM public.program_types WHERE code <> 'pending_dispute'));
SET ROLE tally_app;
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000025b1', true);
SELECT pg_temp.refuses_at('T1c a new pending_dispute enrollment is refused (a dispute is a disputes row)',
  $q$INSERT INTO public.customer_program_enrollments (tenant_id, customer_id, program_type, effective_start_date, status)
     VALUES ('00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-0000000025c1', 'pending_dispute', DATE '2026-03-12', 'active')$q$,
  '23514', '[T1]');
RESET ROLE;
SELECT pg_temp.ok('T2a the reading''s six dispute columns are gone',
  NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'meter_readings' AND column_name LIKE 'dispute%'));
SET ROLE tally_app;
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000025b1', true);
SELECT pg_temp.refuses_at('T2b a reading marked disputed with no open dispute naming it (C2''s, whose dispute was withdrawn)',
  $q$UPDATE public.meter_readings SET status = 'disputed' WHERE id = '00000000-0000-4000-8000-000000002572'$q$, '23514', '[T2]');
SELECT pg_temp.admits('T2c a reading marked disputed under its open dispute (C1''s)',
  $q$UPDATE public.meter_readings SET status = 'disputed' WHERE id = '00000000-0000-4000-8000-000000002571'$q$);
SELECT pg_temp.refuses_at('T2d … and not unmarked while that dispute is open',
  $q$UPDATE public.meter_readings SET status = 'active' WHERE id = '00000000-0000-4000-8000-000000002571'$q$, '23514', '[T2]');
SELECT pg_temp.admits('T2e the dispute is withdrawn …',
  pg_temp.ev_sql('00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-000000002534', 'withdrawn', DATE '2026-03-21'));
SELECT pg_temp.admits('T2f … and the reading may be unmarked',
  $q$UPDATE public.meter_readings SET status = 'active' WHERE id = '00000000-0000-4000-8000-000000002571'$q$);
RESET ROLE;
SELECT pg_temp.ok('T2g the disputed-reading index stands, on the status',
  EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND indexname = 'idx_readings_disputed' AND indexdef ~ 'status'
             AND indexdef !~ 'dispute_'));

-- ============================================================== H history, grants, tenancy, invariants
SELECT pg_temp.refuses_at('H1 a law row is never edited',
  format($q$UPDATE public.dispute_rules SET source_note = 'x' WHERE id = %L$q$, pg_temp.law('investor_owned', 'protected')), '23001', 'dispute_rules');
SELECT pg_temp.refuses_at('H2 a law row cited by a determination cannot close on or before the day that dispute was received (March 15)',
  format($q$UPDATE public.dispute_rules SET effective_to = DATE '2026-03-15' WHERE id = %L$q$, pg_temp.law('investor_owned', 'protected')), '23514', 'cannot close on');
SELECT pg_temp.admits_undone('H3 … the day after is fine',
  format($q$UPDATE public.dispute_rules SET effective_to = DATE '2026-03-16' WHERE id = %L$q$, pg_temp.law('investor_owned', 'protected')));
SELECT pg_temp.refuses_at('H4 T1''s tariff, cited for a dispute received March 12, cannot close on March 12',
  $q$UPDATE public.dispute_tariffs SET effective_to = DATE '2026-03-12' WHERE id = '00000000-0000-4000-8000-0000000025ab'$q$, '23514', 'cannot close on');
SELECT pg_temp.admits_undone('H5 … March 13 is fine',
  $q$UPDATE public.dispute_tariffs SET effective_to = DATE '2026-03-13' WHERE id = '00000000-0000-4000-8000-0000000025ab'$q$);
SELECT pg_temp.ok('H6 the application writes disputes, amounts, lines, determinations and events, and updates or deletes none of them',
  (SELECT bool_and(has_table_privilege('tally_app', t, 'INSERT') AND has_table_privilege('tally_app', t, 'SELECT')
                   AND NOT has_table_privilege('tally_app', t, 'UPDATE') AND NOT has_table_privilege('tally_app', t, 'DELETE')
                   AND NOT has_table_privilege('tally_app', t, 'TRUNCATE'))
     FROM unnest(ARRAY['public.disputes', 'public.dispute_amounts', 'public.dispute_amount_lines', 'public.dispute_determinations', 'public.dispute_events']) t));
SELECT pg_temp.ok('H7 tally_core reads the dispute records and writes none',
  (SELECT bool_and(has_table_privilege('tally_core', t, 'SELECT') AND NOT has_table_privilege('tally_core', t, 'INSERT'))
     FROM unnest(ARRAY['public.disputes', 'public.dispute_amounts', 'public.dispute_determinations', 'public.dispute_events', 'public.dispute_rules']) t));
SET ROLE tally_app;
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000025b2', true);
SELECT pg_temp.ok('H8 each utility sees its own dispute records only: T2 sees its two disputes and none of T1''s or T3''s',
  (SELECT count(*) = 2 FROM public.disputes) AND (SELECT count(*) = 2 FROM public.dispute_determinations)
  AND NOT EXISTS (SELECT 1 FROM public.dispute_events WHERE tenant_id <> '00000000-0000-4000-8000-0000000025a2')
  AND NOT EXISTS (SELECT 1 FROM public.dispute_amounts WHERE tenant_id <> '00000000-0000-4000-8000-0000000025a2')
  AND NOT EXISTS (SELECT 1 FROM public.dispute_tariffs WHERE tenant_id <> '00000000-0000-4000-8000-0000000025a2'));
SELECT pg_temp.ok('H9 the law is the platform''s and every utility reads it',
  (SELECT count(*) >= 4 FROM public.dispute_rules));
RESET ROLE;
SELECT pg_temp.refuses_at('H10 a dispute record is never truncated', 'TRUNCATE public.dispute_events', '23001', 'dispute_events');
SELECT pg_temp.admits('H11 the template''s invariants hold over both rule tables', $q$SELECT public.assert_rule_table_invariants()$q$);
SELECT pg_temp.admits('H12 tenant isolation holds over the new tables and readers', $q$SELECT public.assert_tenant_isolation_invariants()$q$);
SELECT pg_temp.admits('H13 the retention invariants hold: no new table can be deleted from', $q$SELECT public.assert_no_hard_delete_invariants()$q$);
SELECT pg_temp.admits('H14 the core role invariants still hold', $q$SELECT public.assert_core_role_invariants()$q$);
SELECT pg_temp.ok('H15 the comments say the core decides, not the database',
  (SELECT bool_and(obj_description(t, 'pg_class') ~* 'core')
     FROM unnest(ARRAY['public.dispute_rules'::regclass, 'public.dispute_tariffs'::regclass, 'public.dispute_determinations'::regclass]) t));

SELECT 'battery-25: all checks passed' AS result;
ROLLBACK;
