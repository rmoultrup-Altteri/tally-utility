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
--   P  the platform default (r2, item 9)     D7 the platform default cited
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
--           r2: dispute_platform_defaults (law template; kind dispute; key customer_class; the same facets);
--               dispute_determinations.platform_default_id
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
-- T3 (…25a3) a city-owned system with no dispute tariff (r2: until November 24, D7j).
-- Ids: b users, c customers, d locations, e meters, 01-09 bills, 11-1f and
-- 21-2f lines, 31-3f disputes, 41-4f amounts, 51-5f determinations, 61-6f
-- events, 71 readings, 81-8f ledger, ab/ac/ad tariffs.
INSERT INTO public.tenants (id, name, slug) VALUES
  ('00000000-0000-4000-8000-0000000025a1', 'T1 City Gas', 'bat25-t1'),
  ('00000000-0000-4000-8000-0000000025a2', 'T2 Gasco', 'bat25-t2'),
  ('00000000-0000-4000-8000-0000000025a3', 'T3 Town Gas', 'bat25-t3'),
  ('00000000-0000-4000-8000-0000000025a4', 'T4 District Gas', 'bat25-t4'),
  ('00000000-0000-4000-8000-0000000025a5', 'T5 County Gas', 'bat25-t5');
INSERT INTO public.users (id, tenant_id, display_name, email, role, is_active) VALUES
  ('00000000-0000-4000-8000-0000000025b1', '00000000-0000-4000-8000-0000000025a1', 'Op1', 'op1@bat25.test', 'operator', true),
  ('00000000-0000-4000-8000-0000000025b2', '00000000-0000-4000-8000-0000000025a2', 'Op2', 'op2@bat25.test', 'operator', true),
  ('00000000-0000-4000-8000-0000000025b3', '00000000-0000-4000-8000-0000000025a3', 'Op3', 'op3@bat25.test', 'operator', true),
  ('00000000-0000-4000-8000-0000000025b4', '00000000-0000-4000-8000-0000000025a1', 'Admin1', 'ad1@bat25.test', 'tenant_admin', true),
  ('00000000-0000-4000-8000-0000000025b5', '00000000-0000-4000-8000-0000000025a4', 'Op4', 'op4@bat25.test', 'operator', true),
  ('00000000-0000-4000-8000-0000000025b6', '00000000-0000-4000-8000-0000000025a5', 'Op5', 'op5@bat25.test', 'operator', true);
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
INSERT INTO public.places (id, kind_code, state_code, place_code, name, parent_place_id, effective_from, source_note)
SELECT '00000000-0000-4000-8000-0000000025a9', 'special_purpose_district', 'TX', 'TX-B25-DIST', 'Battery District 25', s.id, DATE '2000-01-01', 'battery-25 fixture'
  FROM public.places s WHERE s.kind_code = 'state' AND s.state_code = 'TX';
INSERT INTO public.places (id, kind_code, state_code, place_code, name, parent_place_id, effective_from, source_note)
SELECT '00000000-0000-4000-8000-0000000025aa', 'county', 'TX', '48925', 'Battery County 25', s.id, DATE '2000-01-01', 'battery-25 fixture'
  FROM public.places s WHERE s.kind_code = 'state' AND s.state_code = 'TX';
INSERT INTO public.utility_service_profiles (tenant_id, service_type, system_kind, state_code, owner_type, commission_jurisdiction,
                                             owning_place_id, effective_from, evidence_reference, evidence_date) VALUES
  ('00000000-0000-4000-8000-0000000025a1', 'gas', 'distribution', 'TX', 'municipal', false, '00000000-0000-4000-8000-0000000025a7', DATE '2000-01-01', 'Battery City charter', DATE '2000-01-01'),
  ('00000000-0000-4000-8000-0000000025a2', 'gas', 'distribution', 'TX', 'investor_owned', true, NULL, DATE '2000-01-01', 'RRC certificate bat25', DATE '2000-01-01'),
  ('00000000-0000-4000-8000-0000000025a3', 'gas', 'distribution', 'TX', 'municipal', false, '00000000-0000-4000-8000-0000000025a8', DATE '2000-01-01', 'Battery Town charter', DATE '2000-01-01'),
  ('00000000-0000-4000-8000-0000000025a4', 'gas', 'distribution', 'TX', 'special_district', false, '00000000-0000-4000-8000-0000000025a9', DATE '2000-01-01', 'Battery district order', DATE '2000-01-01'),
  ('00000000-0000-4000-8000-0000000025a5', 'gas', 'distribution', 'TX', 'political_subdivision', false, '00000000-0000-4000-8000-0000000025aa', DATE '2000-01-01', 'Battery county order', DATE '2000-01-01');
INSERT INTO public.meters (id, tenant_id, meter_number, location_id, service_type) VALUES
  ('00000000-0000-4000-8000-0000000025e1', '00000000-0000-4000-8000-0000000025a1', 'B25-M1', '00000000-0000-4000-8000-0000000025d1', 'gas'),
  ('00000000-0000-4000-8000-0000000025e2', '00000000-0000-4000-8000-0000000025a1', 'B25-M2', '00000000-0000-4000-8000-0000000025d2', 'gas');
INSERT INTO public.meter_readings (id, tenant_id, meter_id, reading_date, reading_value) VALUES
  ('00000000-0000-4000-8000-000000002571', '00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-0000000025e1', DATE '2026-02-28', 50),
  ('00000000-0000-4000-8000-000000002572', '00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-0000000025e2', DATE '2026-02-28', 60);

-- bill(): an issued bill dated March 1 (due March 20) with three lines: gas
-- service 60 (regulated), an add-on 40 (unregulated), a credit -10. Issued a
-- day ago as a history load (the owner's stamp is kept). r2 (item 9): another
-- date may be given; the bill covers the month before it and is due 19 days
-- after it.
CREATE FUNCTION pg_temp.bill(p_tenant uuid, p_id uuid, p_num text, p_customer uuid, p_loc uuid, p_l1 uuid, p_l2 uuid, p_l3 uuid,
                             p_date date DEFAULT DATE '2026-03-01') RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO public.invoices (id, tenant_id, invoice_number, customer_id, location_id, invoice_date, billing_period, period_start, period_end, due_date, amount_due)
  VALUES (p_id, p_tenant, p_num, p_customer, p_loc, p_date, to_char(p_date - 1, 'YYYY-MM'), date_trunc('month', p_date - 1)::date, p_date - 1, p_date + 19, 90.00);
  INSERT INTO public.invoice_line_items (id, tenant_id, invoice_id, line_order, service_type, charge_type, description, amount, rate, regulatory_class) VALUES
    (p_l1, p_tenant, p_id, 0, 'gas', 'base_charge', 'Gas service', 60.00, 60.00, 'regulated'),
    (p_l2, p_tenant, p_id, 1, 'general', 'misc', 'Appliance plan', 40.00, NULL, 'unregulated'),
    (p_l3, p_tenant, p_id, 2, 'gas', 'credit', 'Goodwill', -10.00, NULL, 'regulated');
  PERFORM pg_temp.snap(p_id, p_date - 1, now());
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
-- r2 (item 9): T3's bills either side of the platform default's first day (2026-11-22): I9 dated
-- November 20, I8 November 23.
SELECT pg_temp.bill('00000000-0000-4000-8000-0000000025a3', '00000000-0000-4000-8000-000000002509', 'B25-I9', '00000000-0000-4000-8000-0000000025c7', '00000000-0000-4000-8000-0000000025d7',
                    '00000000-0000-4000-8000-00000000252d', '00000000-0000-4000-8000-00000000252e', '00000000-0000-4000-8000-00000000252f', DATE '2026-11-20');
SELECT pg_temp.bill('00000000-0000-4000-8000-0000000025a3', '00000000-0000-4000-8000-000000002508', 'B25-I8', '00000000-0000-4000-8000-0000000025c7', '00000000-0000-4000-8000-0000000025d7',
                    '00000000-0000-4000-8000-00000000252a', '00000000-0000-4000-8000-00000000252b', '00000000-0000-4000-8000-00000000252c', DATE '2026-11-23');
-- A draft bill of C1 (never issued).
INSERT INTO public.invoices (id, tenant_id, invoice_number, customer_id, location_id, invoice_date, billing_period, period_start, period_end, due_date, amount_due)
VALUES ('00000000-0000-4000-8000-000000002504', '00000000-0000-4000-8000-0000000025a1', 'B25-I4', '00000000-0000-4000-8000-0000000025c1', '00000000-0000-4000-8000-0000000025d1',
        DATE '2026-03-01', '2026-02', DATE '2026-02-01', DATE '2026-02-28', DATE '2026-03-20', 25.00);
INSERT INTO public.invoice_line_items (id, tenant_id, invoice_id, service_type, charge_type, description, amount, rate, regulatory_class) VALUES
  ('00000000-0000-4000-8000-00000000251a', '00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-000000002504', 'gas', 'base_charge', 'Draft line', 25.00, 25.00, 'regulated');
-- A goodwill credit of C1 (an adjusted dispute may name it; origin dispute_resolution).
INSERT INTO public.customer_credits (id, tenant_id, customer_id, origin_type, original_amount, issued_date)
VALUES ('00000000-0000-4000-8000-000000002581', '00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-0000000025c1', 'dispute_resolution', 40, DATE '2026-04-10'),
       ('00000000-0000-4000-8000-000000002584', '00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-0000000025c1', 'goodwill', 10, DATE '2026-04-10');
-- An adjustment entry of C1 and one of C2.
INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reference_type, reference_id) VALUES
  ('00000000-0000-4000-8000-000000002582', '00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-0000000025c1', DATE '2026-04-10', 'adjustment', 'I2 dispute adjusted', -40, 'invoice', '00000000-0000-4000-8000-000000002502'),
  ('00000000-0000-4000-8000-000000002583', '00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-0000000025c2', DATE '2026-04-10', 'adjustment', 'I3 adjusted', -40, 'invoice', '00000000-0000-4000-8000-000000002503');
--@fixtures-end
-- The fixtures' deferred checks (CI-015's snapshot at issue, -21's line arithmetic) run here, as the owner:
-- pg_temp.deferred() below fires every pending check, and as one tenant's operator it could not see
-- another tenant's snapshot. Immediate from here on (no check below relies on deferral but deferred()'s).
SET CONSTRAINTS ALL IMMEDIATE;

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
-- tdoc(overrides): a dispute tariff document (CPS-shaped), with top-level sections replaced. r4: its stages
-- are 7.45's own (the law's stages come first, with nothing between; Opus S3, Fable S2).
CREATE FUNCTION pg_temp.tdoc(p_over jsonb DEFAULT '{}') RETURNS jsonb LANGUAGE sql IMMUTABLE AS $$
  SELECT '{"citation": "Battery tariff, disputes",
           "subjects": {"kind": "any", "excluded": []},
           "shelter_earned": {"kind": "before_termination"},
           "must_pay": {"strategy": "undisputed_charges", "version": 1, "id": "m1"},
           "shelter_ends": {"kind": "resolution"},
           "stages": [{"id": "s1", "decider": "designated_employee", "file_within": {"kind": "none"}, "decide_within": {"kind": "none"}, "final": false},
                      {"id": "s2", "decider": "regulator", "file_within": {"kind": "none"}, "decide_within": {"kind": "days", "days": 15}, "final": true}],
           "blocks": {"codes": ["notice_issue", "disconnect_order", "disconnect_execute", "late_fee"]},
           "duties": {"codes": ["investigate", "report_result", "inform_complaint_route"]}}'::jsonb || p_over
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
                       'public.dispute_rules', 'public.dispute_platform_defaults']) t));

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
  (SELECT bool_and(owner_types = '{cooperative,investor_owned}' AND system_kinds = '{distribution}' AND commission_jurisdiction IS NULL
                   AND effective_from = DATE '2004-07-12' AND effective_to IS NULL)
     FROM public.dispute_rules WHERE state_code = 'TX' AND service_type = 'gas' AND terms ->> 'governs' = 'law'));
SELECT pg_temp.ok('K4 a city-owned system gets a delegation for each class (K-07; Util. Code 101.003(7))',
  (SELECT bool_and(r.terms = k.doc) AND count(*) = 2 AND bool_and(r.owner_types = '{municipal}')
     FROM k25 k JOIN public.dispute_rules r
      ON r.state_code = 'TX' AND r.service_type = 'gas' AND r.customer_class = k.class AND k.owner = ANY (r.owner_types)
   WHERE k.owner = 'municipal'));
SELECT pg_temp.ok('K5 the facets are derived from the documents (a text[] facet is distinct and sorted, -17)',
  (SELECT block_codes = '{disconnect_execute,disconnect_order,late_fee}' AND stage_ids = '{s1,s2}' AND must_pay_ids = '{m1}'
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
SELECT pg_temp.refuses_at('X9 a duty code the vocabulary lacks',
  pg_temp.law_sql('protected', (SELECT doc FROM k25 WHERE owner = 'investor_owned' AND class = 'protected')
     || '{"duties": {"codes": ["apologize"], "citation": "x"}}'), '23503', 'dispute_duties');
-- X8's row is the special districts' law below (N7): the Gov't Code 2251 shape (within 21 days of receipt,
-- withhold up to 1.1 of the disputed amount), used here as a test shape only.
SELECT pg_temp.admits('X8 a well-formed law row of another owner type is admitted (the owner writes law)',
  pg_temp.law_sql('protected', '{"governs": "law", "citation": "Tex. Gov''t Code 2251.042", "subjects": {"kind": "any", "excluded": [], "citation": "Tex. Gov''t Code 2251.042(a)"}, "shelter_earned": {"kind": "within_days", "days": 21, "from": "receipt", "citation": "Tex. Gov''t Code 2251.042(a)"}, "must_pay": {"strategy": "withhold_cap", "version": 1, "id": "m1", "fraction": 1.1, "citation": "Tex. Gov''t Code 2251.042(d)"}, "shelter_ends": {"kind": "resolution", "citation": "Tex. Gov''t Code 2251.042(b)"}, "stages": [{"id": "s1", "decider": "designated_employee", "file_within": {"kind": "none"}, "decide_within": {"kind": "none"}, "final": true, "citation": "Tex. Gov''t Code 2251.042"}], "blocks": {"codes": ["late_fee"], "citation": "Tex. Gov''t Code 2251.002(a)(1)"}, "duties": {"codes": [], "citation": "Tex. Gov''t Code 2251.042"}}'));

-- X10: T5's law (a county system; a test shape, PA/CA-like): shelter before termination (N8).
INSERT INTO public.dispute_rules (state_code, service_type, owner_types, system_kinds, commission_jurisdiction, customer_class,
                                  effective_from, source_note, terms_kind, terms_version, terms_source)
VALUES ('TX', 'gas', '{political_subdivision}', '{distribution}', NULL, 'protected', DATE '2026-01-01', 'battery rule', 'dispute', 1, '{"governs": "law", "citation": "Battery county rule", "subjects": {"kind": "any", "excluded": [], "citation": "x"}, "shelter_earned": {"kind": "before_termination", "citation": "x"}, "must_pay": {"strategy": "undisputed_charges", "version": 1, "id": "m1", "citation": "x"}, "shelter_ends": {"kind": "resolution", "citation": "x"}, "stages": [], "blocks": {"codes": ["disconnect_order", "disconnect_execute"], "citation": "x"}, "duties": {"codes": [], "citation": "x"}}');

-- ============================================================== P the platform default (r2, item 9; Ryan 2026-11-22)
-- A city-owned system with no dispute policy of its own is under the platform's default: its own law-template
-- table, kind dispute, keyed by customer class (law/dispute/dispute_platform_defaults.yaml).
CREATE TEMP TABLE p25 (doc jsonb);
INSERT INTO p25 VALUES ('{"governs": "law", "citation": "Platform dispute default (2026-11-22)",
  "subjects": {"kind": "any", "excluded": [], "citation": "Platform dispute default (2026-11-22)"},
  "shelter_earned": {"kind": "before_delinquency", "citation": "Platform dispute default (2026-11-22); after 16 TAC 7.45(6)(D)(i)"},
  "must_pay": {"strategy": "undisputed_charges", "version": 1, "id": "m1", "citation": "Platform dispute default (2026-11-07, 2026-11-22)"},
  "shelter_ends": {"kind": "earlier_of_resolution_and_days", "days": 60, "from": "issue", "citation": "Platform dispute default (2026-11-22); after 16 TAC 7.45(6)(D)(ii)"},
  "stages": [],
  "blocks": {"codes": ["late_fee", "disconnect_order", "disconnect_execute"], "citation": "Platform dispute default (2026-11-22)"},
  "duties": {"codes": [], "citation": "Platform dispute default (2026-11-22)"}}');
-- pdef(class): the platform default in force for a Texas city-owned gas system's class (open rows only).
CREATE FUNCTION pg_temp.pdef(p_class text) RETURNS uuid LANGUAGE sql STABLE AS $$
  SELECT id FROM public.dispute_platform_defaults
   WHERE state_code = 'TX' AND service_type = 'gas' AND customer_class = p_class AND 'municipal' = ANY (owner_types) AND closed_at IS NULL
$$;
GRANT EXECUTE ON FUNCTION pg_temp.pdef(text) TO tally_app;
GRANT SELECT ON p25 TO tally_app;
SELECT pg_temp.ok('P1 dispute_platform_defaults: a registered law table on the dispute kind, keyed by customer class, the five facets, a close floor and an insert check',
  (SELECT rule_role = 'law' AND terms_kind = 'dispute' AND area_key = '{customer_class}'
          AND facet_columns = '{block_codes,excluded_subject_codes,must_pay_ids,stage_ids,subject_codes}'
          AND NOT adopts_legacy_rows AND insert_check IS NOT NULL AND close_floor IS NOT NULL
          AND law_table IS NULL AND compare_function IS NULL
     FROM public.rule_tables WHERE table_name = 'public.dispute_platform_defaults'::regclass));
SELECT pg_temp.ok('P2 two rows: Texas gas, city-owned distribution systems, either jurisdiction status, one per class (every class: Ryan 2026-11-22), from 2026-11-22, open-ended',
  (SELECT count(*) = 2 AND array_agg(customer_class ORDER BY customer_class) = ARRAY['protected', 'unprotected']
          AND bool_and(owner_types = '{municipal}' AND system_kinds = '{distribution}' AND commission_jurisdiction IS NULL
                       AND effective_from = DATE '2026-11-22' AND effective_to IS NULL AND closed_at IS NULL)
     FROM public.dispute_platform_defaults WHERE state_code = 'TX' AND service_type = 'gas')
  AND NOT EXISTS (SELECT 1 FROM public.dispute_platform_defaults WHERE state_code <> 'TX' OR service_type <> 'gas'));
SELECT pg_temp.ok('P3 both hold exactly the ruled document: any subject, before delinquency, the undisputed charges to pay, the earlier of resolution and 60 days from issue, the late fee and both disconnection steps stopped, no stages, no duties',
  (SELECT bool_and(d.terms = p.doc) AND count(*) = 2 FROM public.dispute_platform_defaults d, p25 p));
SELECT pg_temp.ok('P4 its facets are derived from the document',
  (SELECT bool_and(block_codes = '{disconnect_execute,disconnect_order,late_fee}' AND stage_ids = '{}' AND must_pay_ids = '{m1}'
                   AND subject_codes = '{}' AND excluded_subject_codes = '{}')
     FROM public.dispute_platform_defaults));
SELECT pg_temp.ok('P5 its source notes say it is the platform''s ruling, not law, and that a city''s own tariff replaces it',
  (SELECT bool_and(source_note ~* 'not law' AND source_note ~* 'tariff') FROM public.dispute_platform_defaults));
SELECT pg_temp.ok('P6 the template''s three triggers stand on it, enabled always; the customer class is a foreign key into the state''s classes',
  (SELECT count(*) = 3 FROM pg_trigger WHERE tgrelid = 'public.dispute_platform_defaults'::regclass AND NOT tgisinternal
      AND tgname = ANY (ARRAY['rule_row_insert', 'rule_row_history', 'rule_row_no_truncate']) AND tgenabled = 'A')
  AND EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public.dispute_platform_defaults'::regclass AND contype = 'f'
                 AND confrelid = 'public.dispute_customer_classes'::regclass));
-- default_sql(owner, class, from, document): a default row as the owner.
CREATE FUNCTION pg_temp.default_sql(p_owner text, p_class text, p_from date, p_doc jsonb) RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT format($q$INSERT INTO public.dispute_platform_defaults (state_code, service_type, owner_types, system_kinds, commission_jurisdiction, customer_class,
                     effective_from, source_note, terms_kind, terms_version, terms_source)
                   VALUES ('TX', 'gas', ARRAY[%L], '{distribution}', NULL, %L, %L, 'battery default', 'dispute', 1, %L)$q$,
                p_owner, p_class, p_from, p_doc::text)
$$;
GRANT EXECUTE ON FUNCTION pg_temp.default_sql(text, text, date, jsonb) TO tally_app;
SELECT pg_temp.refuses_at('P7 a default that delegates: the platform''s default says what it does',
  pg_temp.default_sql('special_district', 'protected', DATE '2026-01-01',
    '{"governs": "delegated_to_utility", "citation": "x", "note": "left to the utility"}'), '23514', '[L8a]');
SELECT pg_temp.refuses_at('P8 a default whose start is unruled',
  pg_temp.default_sql('special_district', 'protected', DATE '2026-01-01', (SELECT doc FROM p25) || '{"shelter_earned": {"kind": "unruled"}}'), '23514', '[L8b]');
SELECT pg_temp.refuses_at('P8b … whose must-pay is unruled',
  pg_temp.default_sql('special_district', 'protected', DATE '2026-01-01',
    (SELECT doc FROM p25) || '{"must_pay": {"strategy": "unruled", "version": 1, "id": "m1"}}'), '23514', '[L8b]');
SELECT pg_temp.refuses_at('P8c … whose end is unruled',
  pg_temp.default_sql('special_district', 'protected', DATE '2026-01-01', (SELECT doc FROM p25) || '{"shelter_ends": {"kind": "unruled"}}'), '23514', '[L8b]');
SELECT pg_temp.refuses_at('P9 a default passes the dispute documents'' own checks (a subject both listed and excluded)',
  pg_temp.default_sql('special_district', 'protected', DATE '2026-01-01',
    (SELECT doc FROM p25) || '{"subjects": {"kind": "listed", "codes": ["meter_accuracy", "deposit"], "excluded": ["deposit"], "citation": "x"}}'), '23514', '[L2a]');
SELECT pg_temp.refuses_at('P10 a default for a class the state''s vocabulary lacks',
  pg_temp.default_sql('special_district', 'governmental', DATE '2026-01-01', (SELECT doc FROM p25)), '23503', 'dispute_customer_classes');
SELECT pg_temp.refuses_at('P11 a second default for a city''s protected class over the same dates',
  pg_temp.default_sql('municipal', 'protected', DATE '2027-01-01', (SELECT doc FROM p25)), '23P01', 'dispute_platform_defaults');
SELECT pg_temp.admits_undone('P12 a well-formed default of another owner type is admitted (the platform writes its defaults)',
  pg_temp.default_sql('special_district', 'protected', DATE '2026-01-01', (SELECT doc FROM p25)));
SELECT pg_temp.refuses_at('P13 a default is never edited (determinations cite its document)',
  format($q$UPDATE public.dispute_platform_defaults SET source_note = 'changed' WHERE id = %L$q$, pg_temp.pdef('protected')), '23001', 'dispute_platform_defaults');
SELECT pg_temp.refuses_at('P13b nor deleted',
  format($q$DELETE FROM public.dispute_platform_defaults WHERE id = %L$q$, pg_temp.pdef('protected')), '23001', 'dispute_platform_defaults');
SET ROLE tally_app;
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000025b3', true);
SELECT pg_temp.refuses_at('P14 the application writes no default',
  pg_temp.default_sql('special_district', 'protected', DATE '2026-01-01', (SELECT doc FROM p25)), '42501', 'dispute_platform_defaults');
SELECT pg_temp.ok('P15 … and every utility reads them; the lookup finds T3''s protected default on 2026-11-22 and none on 2026-11-21',
  (SELECT count(*) = 2 FROM public.dispute_platform_defaults)
  AND public.rule_law_row_as_of('public.dispute_platform_defaults', '00000000-0000-4000-8000-0000000025a3', 'gas', 'distribution', 'TX',
                                '{"customer_class": "protected"}', DATE '2026-11-22') = pg_temp.pdef('protected'));
SELECT pg_temp.refuses_at('P15b … (none on 2026-11-21: unknown is not permission)',
  $q$SELECT public.rule_law_row_as_of('public.dispute_platform_defaults', '00000000-0000-4000-8000-0000000025a3', 'gas', 'distribution', 'TX',
                                      '{"customer_class": "protected"}', DATE '2026-11-21')$q$, 'P0002', 'no law');
RESET ROLE;

-- ============================================================== U the utility's tariff (L5)
SET ROLE tally_app;
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000025b1', true);
SELECT pg_temp.admits('U1 a city writes its own Brenham-shaped tariff from March 10 (its law row delegates: nothing to compare)',
  pg_temp.tariff_sql('00000000-0000-4000-8000-0000000025ab', '00000000-0000-4000-8000-0000000025a1', DATE '2026-03-10',
    '{"citation": "City of Brenham gas tariff Sheet 511", "subjects": {"kind": "any", "excluded": []}, "shelter_earned": {"kind": "any_time"},
      "must_pay": {"strategy": "full_bill", "version": 1, "id": "m1"}, "shelter_ends": {"kind": "resolution"},
      "stages": [{"id": "s1", "decider": "designated_employee", "file_within": {"kind": "none"}, "decide_within": {"kind": "none"}, "final": true}],
      "blocks": {"codes": ["disconnect_order", "disconnect_execute", "credit_reporting"]}, "duties": {"codes": ["investigate"]}}'));
SELECT pg_temp.ok('U2 its facets are derived from its document (distinct and sorted)',
  (SELECT block_codes = '{credit_reporting,disconnect_execute,disconnect_order}' AND stage_ids = '{s1}' AND must_pay_ids = '{m1}'
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
SELECT pg_temp.refuses_at('N4d a different end: through the regulator''s close against earlier-of-resolution-and-60-days (not comparable: refused)',
  pg_temp.tariff_sql(NULL, '00000000-0000-4000-8000-0000000025a2', DATE '2026-01-01', pg_temp.tdoc('{"shelter_ends": {"kind": "through_regulator_close"}}')),
  '23514', 'shelter_ends');
SELECT pg_temp.refuses_at('N5a a must-pay that asks for more: the full bill',
  pg_temp.tariff_sql(NULL, '00000000-0000-4000-8000-0000000025a2', DATE '2026-01-01', pg_temp.tdoc('{"must_pay": {"strategy": "full_bill", "version": 1, "id": "m1"}}')),
  '23514', 'must_pay');
SELECT pg_temp.refuses_at('N5b the same strategy with other figures: three years of history (not comparable: refused)',
  pg_temp.tariff_sql(NULL, '00000000-0000-4000-8000-0000000025a2', DATE '2026-01-01',
    pg_temp.tdoc('{"must_pay": {"strategy": "average_usage_cap", "version": 1, "id": "m1", "history_years": 3, "no_history": "similar_customers"}}')),
  '23514', 'must_pay');
SELECT pg_temp.admits_undone('N5c a withholding cap of 1.1 against an average-usage cap asks no more (r7, Fable S1: as undisputed charges)',
  pg_temp.tariff_sql(NULL, '00000000-0000-4000-8000-0000000025a2', DATE '2026-01-01',
    pg_temp.tdoc('{"must_pay": {"strategy": "withhold_cap", "version": 1, "id": "m1", "fraction": 1.1}}')));
SELECT pg_temp.admits_undone('N5d … a cap of 1 too',
  pg_temp.tariff_sql(NULL, '00000000-0000-4000-8000-0000000025a2', DATE '2026-01-01',
    pg_temp.tdoc('{"must_pay": {"strategy": "withhold_cap", "version": 1, "id": "m1", "fraction": 1}}')));
SELECT pg_temp.refuses_at('N5e … a cap of 0.9 against an average-usage cap is not comparable: refused',
  pg_temp.tariff_sql(NULL, '00000000-0000-4000-8000-0000000025a2', DATE '2026-01-01',
    pg_temp.tdoc('{"must_pay": {"strategy": "withhold_cap", "version": 1, "id": "m1", "fraction": 0.9}}')),
  '23514', 'must_pay');
-- r2 (Opus S1, Fable S2): duties and stages are compared too.
SELECT pg_temp.refuses_at('N9a a tariff without a duty the law requires (telling the customer the complaint route)',
  pg_temp.tariff_sql(NULL, '00000000-0000-4000-8000-0000000025a2', DATE '2026-01-01', pg_temp.tdoc('{"duties": {"codes": ["investigate", "report_result"]}}')),
  '23514', 'duties');
SELECT pg_temp.refuses_at('N9b a tariff without the regulator''s review stage',
  pg_temp.tariff_sql(NULL, '00000000-0000-4000-8000-0000000025a2', DATE '2026-01-01', pg_temp.tdoc(
    '{"stages": [{"id": "s1", "decider": "designated_employee", "file_within": {"kind": "none"}, "decide_within": {"kind": "none"}, "final": false},
                 {"id": "s2", "decider": "executive", "file_within": {"kind": "days", "days": 30, "from": "prior_decision"}, "decide_within": {"kind": "days", "days": 90}, "final": true}]}')),
  '23514', 'stages');
-- the other side of each boundary
SELECT pg_temp.admits_undone('N4c the law''s own 60 days, and the law''s own cap and start (equal is not looser)',
  pg_temp.tariff_sql(NULL, '00000000-0000-4000-8000-0000000025a2', DATE '2026-01-01', pg_temp.tdoc(
    '{"shelter_earned": {"kind": "before_delinquency"}, "shelter_ends": {"kind": "earlier_of_resolution_and_days", "days": 60, "from": "issue"},
      "must_pay": {"strategy": "average_usage_cap", "version": 1, "id": "m1", "history_years": 2, "no_history": "similar_customers"},
      "blocks": {"codes": ["disconnect_order", "disconnect_execute", "late_fee"]}}')));
-- r2: undone, so T2 later shelters under its law alone (D4x; D4q needs a
-- policy in force to be cited).
SELECT pg_temp.admits_undone('N1b … and every block plus more, a wider start (before termination), a later end (resolution), undisputed charges only; N6 it is then the one in force for T2',
  pg_temp.tariff_sql('00000000-0000-4000-8000-0000000025ac', '00000000-0000-4000-8000-0000000025a2', DATE '2026-01-01', pg_temp.tdoc())
  || $q$; DO $d$ BEGIN
       IF public.rule_tariff_row_as_of('public.dispute_tariffs', '00000000-0000-4000-8000-0000000025a2', 'gas', 'distribution', 'TX', '{}', DATE '2026-03-15')
          IS DISTINCT FROM '00000000-0000-4000-8000-0000000025ac' THEN RAISE EXCEPTION 'N6: not the tariff in force'; END IF;
     END $d$$q$);
-- r3 (Codex S1, Opus N4; never looser): each law stage is matched, in the law's order, by a tariff stage of
-- its decider whose filing window is no shorter and whose decision window no longer (7.45: the
-- designated employee, then the regulator within 15 days).
SELECT pg_temp.refuses_at('N9c a tariff that stretches the regulator''s decision from 15 days to 3,650',
  pg_temp.tariff_sql(NULL, '00000000-0000-4000-8000-0000000025a2', DATE '2026-01-01', pg_temp.tdoc('{"stages": [{"id": "s1", "decider": "designated_employee", "file_within": {"kind": "none"}, "decide_within": {"kind": "none"}, "final": false}, {"id": "s2", "decider": "regulator", "file_within": {"kind": "none"}, "decide_within": {"kind": "days", "days": 3650}, "final": true}]}')),
  '23514', 'stages');
SELECT pg_temp.refuses_at('N9d … or gives the regulator no deadline at all',
  pg_temp.tariff_sql(NULL, '00000000-0000-4000-8000-0000000025a2', DATE '2026-01-01', pg_temp.tdoc('{"stages": [{"id": "s1", "decider": "designated_employee", "file_within": {"kind": "none"}, "decide_within": {"kind": "none"}, "final": false}, {"id": "s2", "decider": "regulator", "file_within": {"kind": "none"}, "decide_within": {"kind": "none"}, "final": true}]}')),
  '23514', 'stages');
SELECT pg_temp.refuses_at('N9e … or sets the customer a filing deadline where the law has none (one day after the prior decision)',
  pg_temp.tariff_sql(NULL, '00000000-0000-4000-8000-0000000025a2', DATE '2026-01-01', pg_temp.tdoc('{"stages": [{"id": "s1", "decider": "designated_employee", "file_within": {"kind": "none"}, "decide_within": {"kind": "none"}, "final": false}, {"id": "s2", "decider": "regulator", "file_within": {"kind": "days", "days": 1, "from": "prior_decision"}, "decide_within": {"kind": "days", "days": 15}, "final": true}]}')),
  '23514', 'stages');
SELECT pg_temp.refuses_at('N9f … or puts the regulator before the designated employee',
  pg_temp.tariff_sql(NULL, '00000000-0000-4000-8000-0000000025a2', DATE '2026-01-01', pg_temp.tdoc('{"stages": [{"id": "s1", "decider": "regulator", "file_within": {"kind": "none"}, "decide_within": {"kind": "days", "days": 15}, "final": false}, {"id": "s2", "decider": "designated_employee", "file_within": {"kind": "none"}, "decide_within": {"kind": "none"}, "final": true}]}')),
  '23514', 'stages');
-- r4 (Opus S3, Opus N2, Fable S2; never looser): the law's stages are the tariff's first, in order, with
-- nothing between; a stage of the tariff's own only after the law's last (it delays none of the law's).
SELECT pg_temp.refuses_at('N9g a quicker regulator (10 days), but a manager''s stage of the tariff''s own between (it may delay the regulator)',
  pg_temp.tariff_sql(NULL, '00000000-0000-4000-8000-0000000025a2', DATE '2026-01-01', pg_temp.tdoc('{"stages": [{"id": "s1", "decider": "designated_employee", "file_within": {"kind": "none"}, "decide_within": {"kind": "none"}, "final": false}, {"id": "s2", "decider": "manager", "file_within": {"kind": "none"}, "decide_within": {"kind": "none"}, "final": false}, {"id": "s3", "decider": "regulator", "file_within": {"kind": "none"}, "decide_within": {"kind": "days", "days": 10}, "final": true}]}')),
  '23514', 'nothing between');
SELECT pg_temp.refuses_at('N9h … or an executive''s stage before the law''s first (a one-day filing gate in front of the whole process)',
  pg_temp.tariff_sql(NULL, '00000000-0000-4000-8000-0000000025a2', DATE '2026-01-01', pg_temp.tdoc('{"stages": [{"id": "s1", "decider": "executive", "file_within": {"kind": "days", "days": 1, "from": "receipt"}, "decide_within": {"kind": "days", "days": 30}, "final": false}, {"id": "s2", "decider": "designated_employee", "file_within": {"kind": "none"}, "decide_within": {"kind": "none"}, "final": false}, {"id": "s3", "decider": "regulator", "file_within": {"kind": "none"}, "decide_within": {"kind": "days", "days": 15}, "final": true}]}')),
  '23514', 'nothing between');
SELECT pg_temp.admits_undone('N9i a stage of the tariff''s own after the law''s last (a governing body''s, after the regulator) is admitted: it delays none of the law''s',
  pg_temp.tariff_sql(NULL, '00000000-0000-4000-8000-0000000025a2', DATE '2026-01-01', pg_temp.tdoc('{"stages": [{"id": "s1", "decider": "designated_employee", "file_within": {"kind": "none"}, "decide_within": {"kind": "none"}, "final": false}, {"id": "s2", "decider": "regulator", "file_within": {"kind": "none"}, "decide_within": {"kind": "days", "days": 15}, "final": false}, {"id": "s3", "decider": "governing_body", "file_within": {"kind": "none"}, "decide_within": {"kind": "days", "days": 30}, "final": true}]}')));
SELECT pg_temp.admits_undone('N9j the law''s own stages, the regulator quicker (10 days), is admitted',
  pg_temp.tariff_sql(NULL, '00000000-0000-4000-8000-0000000025a2', DATE '2026-01-01', pg_temp.tdoc('{"stages": [{"id": "s1", "decider": "designated_employee", "file_within": {"kind": "none"}, "decide_within": {"kind": "none"}, "final": false}, {"id": "s2", "decider": "regulator", "file_within": {"kind": "none"}, "decide_within": {"kind": "days", "days": 10}, "final": true}]}')));
-- N7: T4 is a special district; its law is X8's row (shelter within 21 days of receipt, withhold up to 1.1).
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000025b5', true);
SELECT pg_temp.refuses_at('N7a a shorter window: 20 days of receipt against 21',
  pg_temp.tariff_sql(NULL, '00000000-0000-4000-8000-0000000025a4', DATE '2026-02-01', pg_temp.tdoc('{"shelter_earned": {"kind": "within_days", "days": 20, "from": "receipt"}}')),
  '23514', 'shelter_earned');
SELECT pg_temp.refuses_at('N7b the same days from another anchor: 21 days of issue against 21 of receipt (not comparable: refused)',
  pg_temp.tariff_sql(NULL, '00000000-0000-4000-8000-0000000025a4', DATE '2026-02-01', pg_temp.tdoc('{"shelter_earned": {"kind": "within_days", "days": 21, "from": "issue"}}')),
  '23514', 'shelter_earned');
SELECT pg_temp.refuses_at('N7c before delinquency against a window of days (not comparable: refused)',
  pg_temp.tariff_sql(NULL, '00000000-0000-4000-8000-0000000025a4', DATE '2026-02-01', pg_temp.tdoc('{"shelter_earned": {"kind": "before_delinquency"}}')),
  '23514', 'shelter_earned');
SELECT pg_temp.refuses_at('N7d withholding less: 1 of the disputed amount against 1.1',
  pg_temp.tariff_sql(NULL, '00000000-0000-4000-8000-0000000025a4', DATE '2026-02-01', pg_temp.tdoc(
    '{"shelter_earned": {"kind": "within_days", "days": 21, "from": "receipt"}, "must_pay": {"strategy": "withhold_cap", "version": 1, "id": "m1", "fraction": 1}}')),
  '23514', 'must_pay');
SELECT pg_temp.admits_undone('N7e … the law''s own window and cap are admitted',
  pg_temp.tariff_sql(NULL, '00000000-0000-4000-8000-0000000025a4', DATE '2026-02-01', pg_temp.tdoc(
    '{"shelter_earned": {"kind": "within_days", "days": 21, "from": "receipt"}, "must_pay": {"strategy": "withhold_cap", "version": 1, "id": "m1", "fraction": 1.1}}')));
SELECT pg_temp.admits_undone('N7f … as are a longer window and a larger cap',
  pg_temp.tariff_sql(NULL, '00000000-0000-4000-8000-0000000025a4', DATE '2026-02-01', pg_temp.tdoc(
    '{"shelter_earned": {"kind": "within_days", "days": 30, "from": "receipt"}, "must_pay": {"strategy": "withhold_cap", "version": 1, "id": "m1", "fraction": 1.5}}')));
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
-- det_sql(id, tenant, dispute, amount row, class, rule, tariff, outcome, sheltered, must pay, component, ends, blocks, supersedes,
--         platform default)
CREATE FUNCTION pg_temp.det_sql(p_id text, p_tenant text, p_dispute text, p_amount_row text, p_class text, p_rule uuid, p_tariff text,
                                p_outcome text, p_sheltered numeric, p_must numeric, p_component text, p_ends date, p_blocks text[],
                                p_supersedes text DEFAULT NULL, p_default uuid DEFAULT NULL) RETURNS text
LANGUAGE sql IMMUTABLE AS $$
  SELECT format($q$INSERT INTO public.dispute_determinations (id, tenant_id, dispute_id, dispute_amount_id, state_code, service_type, system_kind,
                     customer_class, rule_id, tariff_id, outcome, sheltered_amount, must_pay_amount, must_pay_component, shelter_ends_on, blocks,
                     supersedes_id, inputs, inputs_fingerprint, calculated_by, platform_default_id)
                   VALUES (%L, %L, %L, %L, 'TX', 'gas', 'distribution', %L, %L, %L, %L, %s, %s, %L, %L, %L, %L, '{"battery": true}', %L, 'core-battery-25', %L)$q$,
                p_id, p_tenant, p_dispute, p_amount_row, p_class, p_rule, p_tariff, p_outcome,
                coalesce(p_sheltered::text, 'NULL'), coalesce(p_must::text, 'NULL'), p_component, p_ends, p_blocks, p_supersedes,
                'fp-' || left(p_id, 8) || coalesce(p_sheltered::text, ''), p_default)
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
  pg_temp.det_sql(text, text, text, text, text, uuid, text, text, numeric, numeric, text, date, text[], text, uuid),
  pg_temp.ev_sql(text, text, text, date, text, text, text, text, text, text, text, text) TO tally_app;

-- N8: T5's law shelters before termination; a tariff starting before delinquency is narrower.
SET ROLE tally_app;
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000025b6', true);
SELECT pg_temp.refuses_at('N8a a narrower start in the order: before delinquency against before termination',
  pg_temp.tariff_sql(NULL, '00000000-0000-4000-8000-0000000025a5', DATE '2026-02-01', pg_temp.tdoc('{"shelter_earned": {"kind": "before_delinquency"}}')),
  '23514', 'shelter_earned');
SELECT pg_temp.admits_undone('N8b … a wider one, any time, is admitted',
  pg_temp.tariff_sql(NULL, '00000000-0000-4000-8000-0000000025a5', DATE '2026-02-01', pg_temp.tdoc('{"shelter_earned": {"kind": "any_time"}}')));
RESET ROLE;

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
SELECT pg_temp.refuses_at('D2g r2 (Opus S3): an amount above the bill''s positive charges (100.01 of 60 + 40)',
  pg_temp.amount_sql(gen_random_uuid()::text, '00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-000000002531', 100.01, 'customer_claim', DATE '2026-03-12'),
  '23514', '[D2g]');
SELECT pg_temp.admits_undone('D2g2 … the whole 100 is admitted',
  pg_temp.amount_sql(gen_random_uuid()::text, '00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-000000002531', 100, 'customer_claim', DATE '2026-03-12'));
SELECT pg_temp.refuses_at('D2e a determiner that is not the customer, an agreement, the utility or a regulator''s interim estimate',
  pg_temp.amount_sql(gen_random_uuid()::text, '00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-000000002531', 10, 'court', DATE '2026-03-12'),
  '23514', 'dispute_amounts_determined_by_check');
SELECT pg_temp.refuses_at('D2f an amount effective before the dispute was received',
  pg_temp.amount_sql(gen_random_uuid()::text, '00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-000000002531', 10, 'customer_claim', DATE '2026-03-11'),
  '23514', '[D2d]');
SELECT pg_temp.admits('D2p a revision is a new row: the regulator''s interim estimate of 35 (FL''s shape), no lines',
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
SELECT pg_temp.refuses_at('D2n T2 writes no amount on T1''s dispute',
  pg_temp.amount_sql(gen_random_uuid()::text, '00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-000000002531', 10, 'agreed', DATE '2026-03-15'),
  '42501', 'row-level security');
SELECT pg_temp.refuses_at('D2o … nor a line on T1''s amount',
  pg_temp.line_sql('00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-000000002541', '00000000-0000-4000-8000-000000002511', 10),
  '42501', 'row-level security');
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
-- r3 (Codex S2): the owner, who sees every tenant, cites a real T2 tariff written in the same statement.
-- r4 (Codex S2): D4f itself, a real tariff T1 cannot see, is after D7j (T3's policy); here each of the
-- other comparisons alone, on T1's own policies of another state, service and system.
RESET ROLE;
SELECT pg_temp.refuses_at('D4f2 … and as the owner, a real tariff of T2''s (written in the same statement)',
  pg_temp.tariff_sql('00000000-0000-4000-8000-0000000025ae', '00000000-0000-4000-8000-0000000025a2', DATE '2026-01-01', pg_temp.tdoc()) || '; '
  || pg_temp.det_sql(gen_random_uuid()::text, '00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-000000002531', '00000000-0000-4000-8000-000000002541',
                  'protected', pg_temp.law('municipal', 'protected'), '00000000-0000-4000-8000-0000000025ae', 'sheltered', 40, 50, 'm1', NULL,
                  '{notice_issue,disconnect_order,disconnect_execute,late_fee}', '00000000-0000-4000-8000-000000002551'), '23514', '[D4f]');
-- elsewhere_sql(): as the owner, T1 gets a service profile, a law row (a delegation) and its own policy in
-- another state, service or system (and, for another state, its state place and customer class).
CREATE FUNCTION pg_temp.elsewhere_sql(p_id text, p_state text, p_service text, p_system text) RETURNS text LANGUAGE sql AS $f$
  SELECT CASE WHEN p_state <> 'TX' THEN format($q$INSERT INTO public.places (kind_code, state_code, place_code, name, effective_from, source_note)
                                                  VALUES ('state', %L, %L, 'Elsewhere', DATE '1900-01-01', 'battery-25'); $q$, p_state, p_state) ELSE '' END
      || CASE WHEN (p_state, p_service) <> ('TX', 'gas') THEN format($q$INSERT INTO public.dispute_customer_classes (state_code, service_type, class_code, description, source_note)
                                                  VALUES (%L, %L, 'protected', 'battery class', 'battery-25'); $q$, p_state, p_service) ELSE '' END
      || format($q$INSERT INTO public.utility_service_profiles (tenant_id, service_type, system_kind, state_code, owner_type, commission_jurisdiction, owning_place_id,
                                                               effective_from, evidence_reference, evidence_date)
                   VALUES ('00000000-0000-4000-8000-0000000025a1', %L, %L, %L, 'investor_owned', true, NULL, DATE '2000-01-01', 'battery-25', DATE '2000-01-01'); $q$,
                p_service, p_system, p_state)
      || format($q$INSERT INTO public.dispute_rules (state_code, service_type, owner_types, system_kinds, commission_jurisdiction, customer_class,
                                                    effective_from, source_note, terms_kind, terms_version, terms_source)
                   VALUES (%L, %L, '{investor_owned}', %L, NULL, 'protected', DATE '2000-01-01', 'battery: elsewhere', 'dispute', 1,
                           '{"citation": "battery", "governs": "delegated_to_utility", "note": "battery"}'); $q$, p_state, p_service, ARRAY[p_system])
      || format($q$INSERT INTO public.dispute_tariffs (id, tenant_id, state_code, service_type, system_kind, effective_from, tariff_reference, terms_kind, terms_version, terms_source)
                   VALUES (%L, '00000000-0000-4000-8000-0000000025a1', %L, %L, %L, DATE '2026-01-01', 'battery: elsewhere', 'dispute_tariff', 1, %L); $q$,
                p_id, p_state, p_service, p_system, pg_temp.tdoc()::text)
$f$;
SELECT pg_temp.refuses_at('D4f3 … and T1''s own policy, but for another state (Oklahoma)',
  pg_temp.elsewhere_sql('00000000-0000-4000-8000-0000000025af', 'OK', 'gas', 'distribution')
  || pg_temp.det_sql(gen_random_uuid()::text, '00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-000000002531', '00000000-0000-4000-8000-000000002541',
                  'protected', pg_temp.law('municipal', 'protected'), '00000000-0000-4000-8000-0000000025af', 'sheltered', 40, 50, 'm1', NULL,
                  '{notice_issue,disconnect_order,disconnect_execute,late_fee}', '00000000-0000-4000-8000-000000002551'), '23514', '[D4f]');
SELECT pg_temp.refuses_at('D4f4 … or another service (water)',
  pg_temp.elsewhere_sql('00000000-0000-4000-8000-0000000025b8', 'TX', 'water', 'distribution')
  || pg_temp.det_sql(gen_random_uuid()::text, '00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-000000002531', '00000000-0000-4000-8000-000000002541',
                  'protected', pg_temp.law('municipal', 'protected'), '00000000-0000-4000-8000-0000000025b8', 'sheltered', 40, 50, 'm1', NULL,
                  '{notice_issue,disconnect_order,disconnect_execute,late_fee}', '00000000-0000-4000-8000-000000002551'), '23514', '[D4f]');
SELECT pg_temp.refuses_at('D4f5 … or another system (a master meter)',
  pg_temp.elsewhere_sql('00000000-0000-4000-8000-0000000025b9', 'TX', 'gas', 'master_meter')
  || pg_temp.det_sql(gen_random_uuid()::text, '00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-000000002531', '00000000-0000-4000-8000-000000002541',
                  'protected', pg_temp.law('municipal', 'protected'), '00000000-0000-4000-8000-0000000025b9', 'sheltered', 40, 50, 'm1', NULL,
                  '{notice_issue,disconnect_order,disconnect_execute,late_fee}', '00000000-0000-4000-8000-000000002551'), '23514', '[D4f]');
SET ROLE tally_app;
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000025b1', true);
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
SELECT pg_temp.refuses_at('D4l a class the state''s vocabulary lacks',
  pg_temp.det_sql(gen_random_uuid()::text, '00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-000000002531', '00000000-0000-4000-8000-000000002542',
                  'governmental', pg_temp.law('municipal', 'protected'), '00000000-0000-4000-8000-0000000025ab', 'sheltered', 35, 90, 'm1', NULL,
                  '{disconnect_order,disconnect_execute,credit_reporting}', '00000000-0000-4000-8000-000000002551'), '23503', 'dispute_customer_classes');
SELECT pg_temp.refuses_at('D4n4 an outcome that is not sheltered, not sheltered, or no terms',
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
SELECT pg_temp.refuses_at('D4n3 sheltered with no amount to pay',
  pg_temp.det_sql(gen_random_uuid()::text, '00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-000000002531', '00000000-0000-4000-8000-000000002542',
                  'protected', pg_temp.law('municipal', 'protected'), '00000000-0000-4000-8000-0000000025ab', 'sheltered', 35, NULL, 'm1', NULL,
                  '{disconnect_order,disconnect_execute,credit_reporting}', '00000000-0000-4000-8000-000000002552'), '23514', '[D4n]');
SELECT pg_temp.refuses_at('D4h2 the document''s blocks with one repeated',
  pg_temp.det_sql(gen_random_uuid()::text, '00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-000000002531', '00000000-0000-4000-8000-000000002542',
                  'protected', pg_temp.law('municipal', 'protected'), '00000000-0000-4000-8000-0000000025ab', 'sheltered', 35, 90, 'm1', NULL,
                  '{disconnect_order,disconnect_order,disconnect_execute,credit_reporting}', '00000000-0000-4000-8000-000000002552'), '23514', '[D4h]');
-- r3 (Fable N3): under a document that ends the shelter only at resolution, a shelter records no
-- last day (the reader would stop it on that day while the dispute is open).
SELECT pg_temp.refuses_at('D8h under T1''s policy (ended by resolution), a shelter that records a last day',
  pg_temp.det_sql(gen_random_uuid()::text, '00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-000000002531', '00000000-0000-4000-8000-000000002542',
                  'protected', pg_temp.law('municipal', 'protected'), '00000000-0000-4000-8000-0000000025ab', 'sheltered', 35, 90, 'm1', DATE '2026-03-12',
                  '{disconnect_order,disconnect_execute,credit_reporting}', '00000000-0000-4000-8000-000000002552'), '23514', '[D4s]');
-- r3 (Fable N2; r1 note): a shelter with nothing still to pay is a record the database admits.
SELECT pg_temp.admits_undone('D8i a shelter with nothing left to pay (0 to pay) is admitted',
  pg_temp.det_sql(gen_random_uuid()::text, '00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-000000002531', '00000000-0000-4000-8000-000000002542',
                  'protected', pg_temp.law('municipal', 'protected'), '00000000-0000-4000-8000-0000000025ab', 'sheltered', 35, 0, 'm1', NULL,
                  '{disconnect_order,disconnect_execute,credit_reporting}', '00000000-0000-4000-8000-000000002552'));
SELECT pg_temp.refuses_at('D4v a determination is never edited',
  $q$UPDATE public.dispute_determinations SET sheltered_amount = 1 WHERE id = '00000000-0000-4000-8000-000000002552'$q$, '42501', 'dispute_determinations');
SELECT pg_temp.refuses_at('D4w nor deleted',
  $q$DELETE FROM public.dispute_determinations WHERE id = '00000000-0000-4000-8000-000000002551'$q$, '42501', 'dispute_determinations');
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000025b2', true);
-- r2 (Fable S1): under 16 TAC 7.45 the shelter ends by day 60 counting the
-- issue day (April 29 for a March 1 bill), and a shelter says so.
SELECT pg_temp.refuses_at('D4p a shelter under 7.45 with no end',
  pg_temp.det_sql(gen_random_uuid()::text, '00000000-0000-4000-8000-0000000025a2', '00000000-0000-4000-8000-000000002535', '00000000-0000-4000-8000-000000002545',
                  'protected', pg_temp.law('investor_owned', 'protected'), NULL, 'sheltered', 40, 50, 'm1', NULL,
                  '{disconnect_order,disconnect_execute,late_fee}'), '23514', '[D4p]');
SELECT pg_temp.refuses_at('D4p2 … or ending after day 60 (April 30)',
  pg_temp.det_sql(gen_random_uuid()::text, '00000000-0000-4000-8000-0000000025a2', '00000000-0000-4000-8000-000000002535', '00000000-0000-4000-8000-000000002545',
                  'protected', pg_temp.law('investor_owned', 'protected'), NULL, 'sheltered', 40, 50, 'm1', DATE '2026-04-30',
                  '{disconnect_order,disconnect_execute,late_fee}'), '23514', '[D4p]');
-- r2 (Opus S2): T2's own policy in force (written in the same undone
-- statement) is cited where the law governs.
SELECT pg_temp.refuses_at('D4q the law alone, while the utility''s own wider policy is in force',
  pg_temp.tariff_sql(NULL, '00000000-0000-4000-8000-0000000025a2', DATE '2026-01-01', pg_temp.tdoc()) || '; ' || pg_temp.det_sql(gen_random_uuid()::text, '00000000-0000-4000-8000-0000000025a2', '00000000-0000-4000-8000-000000002535', '00000000-0000-4000-8000-000000002545',
                  'protected', pg_temp.law('investor_owned', 'protected'), NULL, 'sheltered', 40, 50, 'm1', DATE '2026-04-29',
                  '{disconnect_order,disconnect_execute,late_fee}'),
  '23514', '[D4q]');
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
-- r7 (Opus N1, Fable S2): the end check's unruled branch, reached on the real path. 7.45(1) leaves the
-- unprotected class's end unruled; a sheltered record under it (the core's choice, never looser) fits.
SELECT pg_temp.admits_undone('D4y2 a sheltered record for C6 under 7.45(1) alone, whose end is unruled, is admitted with a last day',
  pg_temp.det_sql(gen_random_uuid()::text, '00000000-0000-4000-8000-0000000025a2', '00000000-0000-4000-8000-000000002536', '00000000-0000-4000-8000-000000002546',
                  'unprotected', pg_temp.law('investor_owned', 'unprotected'), NULL, 'sheltered', 40, 50, 'm1', DATE '2026-05-01', '{}', '00000000-0000-4000-8000-000000002556'));
SELECT pg_temp.admits_undone('D4y3 … and with none',
  pg_temp.det_sql(gen_random_uuid()::text, '00000000-0000-4000-8000-0000000025a2', '00000000-0000-4000-8000-000000002536', '00000000-0000-4000-8000-000000002546',
                  'unprotected', pg_temp.law('investor_owned', 'unprotected'), NULL, 'sheltered', 40, 50, 'm1', NULL, '{}', '00000000-0000-4000-8000-000000002556'));
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
SELECT pg_temp.refuses_at('D5l2 an adjustment naming a credit that is not a dispute resolution (C1''s goodwill credit)',
  pg_temp.ev_sql('00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-000000002531', 'resolved', DATE '2026-04-10', NULL, NULL, NULL, 'adjusted',
                 NULL, '00000000-0000-4000-8000-000000002584'), '23514', '[D5e]');
SELECT pg_temp.refuses_at('D5l3 an adjustment naming another customer''s bill (C2''s I3)',
  pg_temp.ev_sql('00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-000000002531', 'resolved', DATE '2026-04-10', NULL, NULL, NULL, 'adjusted',
                 NULL, NULL, '00000000-0000-4000-8000-000000002503'), '23514', '[D5e]');
SELECT pg_temp.refuses_at('D5x an escalation that names a stage',
  pg_temp.ev_sql('00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-000000002531', 'escalated', DATE '2026-03-20', 's1', 'designated_employee', 'regulator'),
  '23514', '[D5b]');
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000025b2', true);
SELECT pg_temp.refuses_at('D5w T2 writes no event on T1''s dispute',
  pg_temp.ev_sql('00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-000000002531', 'escalated', DATE '2026-03-20', NULL, NULL, 'regulator'),
  '42501', 'row-level security');
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000025b1', true);
-- r2 (Opus B1, Fable B1): a record in the same statement as the resolution.
SELECT pg_temp.refuses_at('D5r a resolution and an escalation in one multi-row insert',
  $q$INSERT INTO public.dispute_events (tenant_id, dispute_id, event_type, occurred_on, outcome, escalated_to)
     VALUES ('00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-000000002531', 'resolved', DATE '2026-04-10', 'sustained', NULL),
            ('00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-000000002531', 'escalated', DATE '2026-04-10', NULL, 'regulator')$q$, '23514', '[D5f]');
SELECT pg_temp.refuses_at('D5r2 a withdrawal and an escalation in one multi-row insert',
  $q$INSERT INTO public.dispute_events (tenant_id, dispute_id, event_type, occurred_on, outcome, escalated_to)
     VALUES ('00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-000000002531', 'withdrawn', DATE '2026-04-10', NULL, NULL),
            ('00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-000000002531', 'escalated', DATE '2026-04-10', NULL, 'regulator')$q$, '23514', '[D5f]');
-- The CTE's resolution runs first: the row inserted reads it (FROM r).
SELECT pg_temp.refuses_at('D4k2 a resolution and then a superseding determination in one statement (a writable CTE)',
  'WITH r AS (' || pg_temp.ev_sql('00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-000000002531', 'resolved', DATE '2026-04-10', NULL, NULL, NULL, 'sustained') || ' RETURNING 1) ' ||
  regexp_replace(pg_temp.det_sql(gen_random_uuid()::text, '00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-000000002531', '00000000-0000-4000-8000-000000002542',
                  'protected', pg_temp.law('municipal', 'protected'), '00000000-0000-4000-8000-0000000025ab', 'sheltered', 30, 90, 'm1', NULL,
                  '{disconnect_order,disconnect_execute,credit_reporting}', '00000000-0000-4000-8000-000000002552'), 'VALUES \((.*)\)$', 'SELECT \1 FROM r'), '23514', '[D4k]');
SELECT pg_temp.refuses_at('D2m2 a resolution and then a new amount in one statement (a writable CTE)',
  'WITH r AS (' || pg_temp.ev_sql('00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-000000002531', 'resolved', DATE '2026-04-10', NULL, NULL, NULL, 'sustained') || ' RETURNING 1) ' ||
  regexp_replace(pg_temp.amount_sql(gen_random_uuid()::text, '00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-000000002531', 10, 'agreed', DATE '2026-04-10'), 'VALUES \((.*)\)$', 'SELECT \1 FROM r'), '23514', '[D2e]');
-- r3 (Codex B1): a row given the closing event's own id is still a row after it.
SELECT pg_temp.refuses_at('D8a a withdrawal and then an amount carrying the withdrawal''s id, in one statement',
  'WITH r AS (' || pg_temp.ev_sql('00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-000000002531', 'withdrawn', DATE '2026-04-10', NULL, NULL, NULL, NULL, NULL, NULL, NULL, '00000000-0000-4000-8000-00000000256f') || ' RETURNING 1) ' ||
  regexp_replace(pg_temp.amount_sql('00000000-0000-4000-8000-00000000256f', '00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-000000002531', 10, 'agreed', DATE '2026-04-10'), 'VALUES \((.*)\)$', 'SELECT \1 FROM r'), '23514', '[D2e]');
SELECT pg_temp.refuses_at('D8b … and a determination carrying it',
  'WITH r AS (' || pg_temp.ev_sql('00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-000000002531', 'withdrawn', DATE '2026-04-10', NULL, NULL, NULL, NULL, NULL, NULL, NULL, '00000000-0000-4000-8000-00000000256f') || ' RETURNING 1) ' ||
  regexp_replace(pg_temp.det_sql('00000000-0000-4000-8000-00000000256f', '00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-000000002531', '00000000-0000-4000-8000-000000002542',
                  'protected', pg_temp.law('municipal', 'protected'), '00000000-0000-4000-8000-0000000025ab', 'sheltered', 30, 90, 'm1', NULL,
                  '{disconnect_order,disconnect_execute,credit_reporting}', '00000000-0000-4000-8000-000000002552'), 'VALUES \((.*)\)$', 'SELECT \1 FROM r'), '23514', '[D4k]');
-- r3 (Opus N3): a line is a record of the dispute too.
SELECT pg_temp.refuses_at('D8c an amount, then the withdrawal, then a line on that amount, in one transaction',
  pg_temp.amount_sql('00000000-0000-4000-8000-00000000254e', '00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-000000002531', 10, 'agreed', DATE '2026-04-10') || '; '
  || pg_temp.ev_sql('00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-000000002531', 'withdrawn', DATE '2026-04-10') || '; '
  || pg_temp.line_sql('00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-00000000254e', '00000000-0000-4000-8000-000000002511', 10), '23514', '[D2e]');
SELECT pg_temp.admits_undone('D8d … the same line before the withdrawal is admitted',
  pg_temp.amount_sql('00000000-0000-4000-8000-00000000254e', '00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-000000002531', 10, 'agreed', DATE '2026-04-10') || '; '
  || pg_temp.line_sql('00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-00000000254e', '00000000-0000-4000-8000-000000002511', 10) || '; '
  || pg_temp.ev_sql('00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-000000002531', 'withdrawn', DATE '2026-04-10'));
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
                  '{disconnect_order,disconnect_execute,credit_reporting}', '00000000-0000-4000-8000-000000002552'), '23514', 'nothing is determined after it [D4k]');
-- D4k and D2m name the BEFORE guard's own message: the commit-time check from
-- the events carries the same tag (it holds D4k2 and D2m2), and would pass a
-- tag-only match with the BEFORE guard gone (mutations M43, M55).
SELECT pg_temp.refuses_at('D2m an amount after the resolution',
  pg_temp.amount_sql(gen_random_uuid()::text, '00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-000000002531', 10, 'agreed', DATE '2026-04-12'), '23514', 'is resolved — nothing is recorded on it after [D2e]');
SELECT pg_temp.admits('D5q C1''s I2 dispute is resolved adjusted, naming the adjustment entry that produced',
  pg_temp.ev_sql('00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-000000002532', 'resolved', DATE '2026-04-10', NULL, NULL, NULL, 'adjusted',
                 '00000000-0000-4000-8000-000000002582'));
SELECT pg_temp.admits('D5y C2''s reading dispute is withdrawn',
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
SELECT pg_temp.refuses_at('T2e0 r2 (Opus S4): the dispute withdrawn and the reading left marked is refused at commit',
  pg_temp.ev_sql('00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-000000002534', 'withdrawn', DATE '2026-03-21')
  || '; SET CONSTRAINTS public.zz_dispute_reading_released IMMEDIATE', '23514', '[T2c]');
SET CONSTRAINTS public.zz_dispute_reading_released DEFERRED;
SELECT pg_temp.admits('T2e the dispute is withdrawn …',
  pg_temp.ev_sql('00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-000000002534', 'withdrawn', DATE '2026-03-21'));
SELECT pg_temp.admits('T2f … and the reading unmarked in the same transaction, so the commit check passes',
  $q$UPDATE public.meter_readings SET status = 'active' WHERE id = '00000000-0000-4000-8000-000000002571';
     SET CONSTRAINTS public.zz_dispute_reading_released IMMEDIATE;
     SET CONSTRAINTS public.zz_dispute_reading_released DEFERRED$q$);
RESET ROLE;
SELECT pg_temp.ok('T2g the disputed-reading index stands, on the status',
  EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND indexname = 'idx_readings_disputed' AND indexdef ~ 'status'
             AND indexdef !~ 'dispute_'));

-- ============================================================== D7 the platform default cited (r2, item 9)
-- T3 is a city with no dispute policy until it writes one from November 24. A dispute it received from
-- November 22 (the default's first day) is under the platform default; one received before has no terms.
-- I9 is dated November 20 (day 60 is January 18), I8 November 23.
SET ROLE tally_app;
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000025b3', true);
SELECT pg_temp.admits('D7 T3''s C7 disputes I9 on November 21 and on November 22, and I8 on November 23 and 24 (40 each)',
  pg_temp.dispute_sql('00000000-0000-4000-8000-000000002539', '00000000-0000-4000-8000-0000000025a3', '00000000-0000-4000-8000-0000000025c7', '00000000-0000-4000-8000-000000002509', NULL, 'calculation', DATE '2026-11-21') || '; '
  || pg_temp.dispute_sql('00000000-0000-4000-8000-00000000253a', '00000000-0000-4000-8000-0000000025a3', '00000000-0000-4000-8000-0000000025c7', '00000000-0000-4000-8000-000000002509', NULL, 'calculation', DATE '2026-11-22') || '; '
  || pg_temp.dispute_sql('00000000-0000-4000-8000-00000000253b', '00000000-0000-4000-8000-0000000025a3', '00000000-0000-4000-8000-0000000025c7', '00000000-0000-4000-8000-000000002508', NULL, 'calculation', DATE '2026-11-23') || '; '
  || pg_temp.dispute_sql('00000000-0000-4000-8000-00000000253c', '00000000-0000-4000-8000-0000000025a3', '00000000-0000-4000-8000-0000000025c7', '00000000-0000-4000-8000-000000002508', NULL, 'calculation', DATE '2026-11-24') || '; '
  || pg_temp.amount_sql('00000000-0000-4000-8000-00000000254a', '00000000-0000-4000-8000-0000000025a3', '00000000-0000-4000-8000-000000002539', 40, 'customer_claim', DATE '2026-11-21') || '; '
  || pg_temp.amount_sql('00000000-0000-4000-8000-00000000254c', '00000000-0000-4000-8000-0000000025a3', '00000000-0000-4000-8000-00000000253a', 40, 'customer_claim', DATE '2026-11-22') || '; '
  || pg_temp.amount_sql('00000000-0000-4000-8000-00000000254f', '00000000-0000-4000-8000-0000000025a3', '00000000-0000-4000-8000-00000000253b', 40, 'customer_claim', DATE '2026-11-23') || '; '
  || pg_temp.amount_sql('00000000-0000-4000-8000-00000000254e', '00000000-0000-4000-8000-0000000025a3', '00000000-0000-4000-8000-00000000253c', 40, 'customer_claim', DATE '2026-11-24'));
SELECT pg_temp.refuses_at('D7a November 21, the day before the default: naming it is refused (none is in force)',
  pg_temp.det_sql(gen_random_uuid()::text, '00000000-0000-4000-8000-0000000025a3', '00000000-0000-4000-8000-000000002539', '00000000-0000-4000-8000-00000000254a',
                  'protected', pg_temp.law('municipal', 'protected'), NULL, 'sheltered', 40, 50, 'm1', DATE '2027-01-18',
                  '{disconnect_execute,disconnect_order,late_fee}', NULL, pg_temp.pdef('protected')), '23514', '[D7a]');
SELECT pg_temp.admits('D7a2 … and "no terms" is admitted (a city with no policy, before the platform''s default)',
  pg_temp.det_sql('00000000-0000-4000-8000-00000000255a', '00000000-0000-4000-8000-0000000025a3', '00000000-0000-4000-8000-000000002539', '00000000-0000-4000-8000-00000000254a',
                  'protected', pg_temp.law('municipal', 'protected'), NULL, 'no_terms', 0, NULL, NULL, NULL, '{}'));
SELECT pg_temp.refuses_at('D7b November 22, the default''s first day: "no terms" is refused (the default governs a city with no policy)',
  pg_temp.det_sql(gen_random_uuid()::text, '00000000-0000-4000-8000-0000000025a3', '00000000-0000-4000-8000-00000000253a', '00000000-0000-4000-8000-00000000254c',
                  'protected', pg_temp.law('municipal', 'protected'), NULL, 'no_terms', 0, NULL, NULL, NULL, '{}'), '23514', '[D7b]');
SELECT pg_temp.refuses_at('D7b2 … as is a shelter that names neither a tariff nor the default',
  pg_temp.det_sql(gen_random_uuid()::text, '00000000-0000-4000-8000-0000000025a3', '00000000-0000-4000-8000-00000000253a', '00000000-0000-4000-8000-00000000254c',
                  'protected', pg_temp.law('municipal', 'protected'), NULL, 'sheltered', 40, 50, 'm1', DATE '2027-01-18',
                  '{disconnect_execute,disconnect_order,late_fee}'), '23514', '[D7b]');
SELECT pg_temp.refuses_at('D7b3 … and the other class''s default (the unprotected row for a protected customer)',
  pg_temp.det_sql(gen_random_uuid()::text, '00000000-0000-4000-8000-0000000025a3', '00000000-0000-4000-8000-00000000253a', '00000000-0000-4000-8000-00000000254c',
                  'protected', pg_temp.law('municipal', 'protected'), NULL, 'sheltered', 40, 50, 'm1', DATE '2027-01-18',
                  '{disconnect_execute,disconnect_order,late_fee}', NULL, pg_temp.pdef('unprotected')), '23514', '[D7b]');
SELECT pg_temp.refuses_at('D7c under the default, a shelter past day 60 from issue (January 19)',
  pg_temp.det_sql(gen_random_uuid()::text, '00000000-0000-4000-8000-0000000025a3', '00000000-0000-4000-8000-00000000253a', '00000000-0000-4000-8000-00000000254c',
                  'protected', pg_temp.law('municipal', 'protected'), NULL, 'sheltered', 40, 50, 'm1', DATE '2027-01-19',
                  '{disconnect_execute,disconnect_order,late_fee}', NULL, pg_temp.pdef('protected')), '23514', '[D4p]');
SELECT pg_temp.refuses_at('D7c2 … or with no end',
  pg_temp.det_sql(gen_random_uuid()::text, '00000000-0000-4000-8000-0000000025a3', '00000000-0000-4000-8000-00000000253a', '00000000-0000-4000-8000-00000000254c',
                  'protected', pg_temp.law('municipal', 'protected'), NULL, 'sheltered', 40, 50, 'm1', NULL,
                  '{disconnect_execute,disconnect_order,late_fee}', NULL, pg_temp.pdef('protected')), '23514', '[D4p]');
SELECT pg_temp.refuses_at('D7d blocks other than the default''s (credit reporting added)',
  pg_temp.det_sql(gen_random_uuid()::text, '00000000-0000-4000-8000-0000000025a3', '00000000-0000-4000-8000-00000000253a', '00000000-0000-4000-8000-00000000254c',
                  'protected', pg_temp.law('municipal', 'protected'), NULL, 'sheltered', 40, 50, 'm1', DATE '2027-01-18',
                  '{credit_reporting,disconnect_execute,disconnect_order,late_fee}', NULL, pg_temp.pdef('protected')), '23514', '[D4h]');
SELECT pg_temp.refuses_at('D7d2 a must-pay component the default does not have',
  pg_temp.det_sql(gen_random_uuid()::text, '00000000-0000-4000-8000-0000000025a3', '00000000-0000-4000-8000-00000000253a', '00000000-0000-4000-8000-00000000254c',
                  'protected', pg_temp.law('municipal', 'protected'), NULL, 'sheltered', 40, 50, 'm2', DATE '2027-01-18',
                  '{disconnect_execute,disconnect_order,late_fee}', NULL, pg_temp.pdef('protected')), '23514', '[D4g]');
SELECT pg_temp.refuses_at('D7e "no terms" that names the default',
  pg_temp.det_sql(gen_random_uuid()::text, '00000000-0000-4000-8000-0000000025a3', '00000000-0000-4000-8000-00000000253a', '00000000-0000-4000-8000-00000000254c',
                  'protected', pg_temp.law('municipal', 'protected'), NULL, 'no_terms', 0, NULL, NULL, NULL, '{}', NULL, pg_temp.pdef('protected')), '23514', '[D4n]');
SELECT pg_temp.admits('D7f November 22: sheltered under the default — 40 sheltered, 50 (the undisputed charges) to pay, until January 18 (day 60), the late fee and both disconnection steps stopped',
  pg_temp.det_sql('00000000-0000-4000-8000-00000000255b', '00000000-0000-4000-8000-0000000025a3', '00000000-0000-4000-8000-00000000253a', '00000000-0000-4000-8000-00000000254c',
                  'protected', pg_temp.law('municipal', 'protected'), NULL, 'sheltered', 40, 50, 'm1', DATE '2027-01-18',
                  '{disconnect_execute,disconnect_order,late_fee}', NULL, pg_temp.pdef('protected')));
SELECT pg_temp.admits('D7g November 23: the unprotected class is under its own default row (every class, Ryan 2026-11-22)',
  pg_temp.det_sql('00000000-0000-4000-8000-00000000255c', '00000000-0000-4000-8000-0000000025a3', '00000000-0000-4000-8000-00000000253b', '00000000-0000-4000-8000-00000000254f',
                  'unprotected', pg_temp.law('municipal', 'unprotected'), NULL, 'sheltered', 40, 50, 'm1', DATE '2027-01-21',
                  '{disconnect_execute,disconnect_order,late_fee}', NULL, pg_temp.pdef('unprotected')));
SELECT pg_temp.ok('D7h the document a default''s determination cites is the default''s',
  public.dispute_determination_terms(pg_temp.law('municipal', 'protected'), NULL, pg_temp.pdef('protected')) = (SELECT doc FROM p25)
  AND public.dispute_determination_terms(pg_temp.law('municipal', 'protected'), NULL, NULL) ->> 'governs' = 'delegated_to_utility');
SELECT pg_temp.refuses_at('D7i the default has no review stages: a stage event under it is refused',
  pg_temp.ev_sql('00000000-0000-4000-8000-0000000025a3', '00000000-0000-4000-8000-00000000253a', 'stage_entered', DATE '2026-11-24', 's1', 'designated_employee'), '23514', '[D5b]');
SELECT pg_temp.admits('D7j T3 writes its own policy from November 24',
  pg_temp.tariff_sql('00000000-0000-4000-8000-0000000025ad', '00000000-0000-4000-8000-0000000025a3', DATE '2026-11-24', pg_temp.tdoc()));
-- r4 (Codex S2): D4f, a real tariff of another utility (T3's, just written), which T1 cannot see.
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000025b1', true);
SELECT pg_temp.refuses_at('D4f another utility''s tariff (T3''s, real, which T1 cannot see), on a new dispute of C1''s',
  pg_temp.dispute_sql('00000000-0000-4000-8000-000000002560', '00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-0000000025c1',
                      '00000000-0000-4000-8000-000000002501', NULL, 'calculation', DATE '2026-03-12') || '; '
  || pg_temp.amount_sql('00000000-0000-4000-8000-000000002561', '00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-000000002560', 40, 'customer_claim', DATE '2026-03-12') || '; '
  || pg_temp.det_sql(gen_random_uuid()::text, '00000000-0000-4000-8000-0000000025a1', '00000000-0000-4000-8000-000000002560', '00000000-0000-4000-8000-000000002561',
                  'protected', pg_temp.law('municipal', 'protected'), '00000000-0000-4000-8000-0000000025ad', 'sheltered', 40, 50, 'm1', NULL,
                  '{notice_issue,disconnect_order,disconnect_execute,late_fee}'), '23514', '[D4f]');
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000025b3', true);
SELECT pg_temp.refuses_at('D7k November 24: the default is refused — the city''s own policy is in force from that day (it replaces the default)',
  pg_temp.det_sql(gen_random_uuid()::text, '00000000-0000-4000-8000-0000000025a3', '00000000-0000-4000-8000-00000000253c', '00000000-0000-4000-8000-00000000254e',
                  'protected', pg_temp.law('municipal', 'protected'), NULL, 'sheltered', 40, 50, 'm1', DATE '2027-01-21',
                  '{disconnect_execute,disconnect_order,late_fee}', NULL, pg_temp.pdef('protected')), '23514', '[D4e]');
SELECT pg_temp.refuses_at('D7k2 … and naming both the policy and the default is refused',
  pg_temp.det_sql(gen_random_uuid()::text, '00000000-0000-4000-8000-0000000025a3', '00000000-0000-4000-8000-00000000253c', '00000000-0000-4000-8000-00000000254e',
                  'protected', pg_temp.law('municipal', 'protected'), '00000000-0000-4000-8000-0000000025ad', 'sheltered', 40, 50, 'm1', NULL,
                  '{notice_issue,disconnect_order,disconnect_execute,late_fee}', NULL, pg_temp.pdef('protected')), '23514', '[D7k]');
SELECT pg_temp.admits('D7l … citing the policy is admitted',
  pg_temp.det_sql('00000000-0000-4000-8000-00000000255d', '00000000-0000-4000-8000-0000000025a3', '00000000-0000-4000-8000-00000000253c', '00000000-0000-4000-8000-00000000254e',
                  'protected', pg_temp.law('municipal', 'protected'), '00000000-0000-4000-8000-0000000025ad', 'sheltered', 40, 50, 'm1', NULL,
                  '{notice_issue,disconnect_order,disconnect_execute,late_fee}'));
SELECT pg_temp.admits('D7m the November 22 dispute keeps the default after the policy: a new answer (35) still cites it',
  pg_temp.det_sql('00000000-0000-4000-8000-00000000255e', '00000000-0000-4000-8000-0000000025a3', '00000000-0000-4000-8000-00000000253a', '00000000-0000-4000-8000-00000000254c',
                  'protected', pg_temp.law('municipal', 'protected'), NULL, 'sheltered', 35, 55, 'm1', DATE '2027-01-18',
                  '{disconnect_execute,disconnect_order,late_fee}', '00000000-0000-4000-8000-00000000255b', pg_temp.pdef('protected')));
SELECT pg_temp.ok('D7n the reader: I9 on January 18 shelters 35 of the November 22 dispute with the default''s blocks, and nothing of the November 21 one',
  (SELECT sheltered_amount = 35 AND blocks = '{disconnect_execute,disconnect_order,late_fee}' AND outcome = 'sheltered'
     FROM public.dispute_shelter_as_of('00000000-0000-4000-8000-000000002509', DATE '2027-01-18', now()) WHERE dispute_id = '00000000-0000-4000-8000-00000000253a')
  AND (SELECT outcome = 'no_terms' AND sheltered_amount = 0 FROM public.dispute_shelter_as_of('00000000-0000-4000-8000-000000002509', DATE '2027-01-18', now()) WHERE dispute_id = '00000000-0000-4000-8000-000000002539'));
SELECT pg_temp.ok('D7n2 … and on January 19 nothing',
  (SELECT coalesce(sum(sheltered_amount), 0) = 0 FROM public.dispute_shelter_as_of('00000000-0000-4000-8000-000000002509', DATE '2027-01-19', now())));
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000025b2', true);
SELECT pg_temp.refuses_at('D7o where Texas law governs (T2), the default is never named',
  pg_temp.det_sql(gen_random_uuid()::text, '00000000-0000-4000-8000-0000000025a2', '00000000-0000-4000-8000-000000002535', '00000000-0000-4000-8000-000000002545',
                  'protected', pg_temp.law('investor_owned', 'protected'), NULL, 'sheltered', 40, 50, 'm1', DATE '2026-04-29',
                  '{disconnect_order,disconnect_execute,late_fee}', '00000000-0000-4000-8000-000000002555', pg_temp.pdef('protected')), '23514', '[D7k]');
RESET ROLE;
SELECT pg_temp.refuses_at('D7p the protected default, cited for a dispute received November 22, cannot close on November 22',
  format($q$UPDATE public.dispute_platform_defaults SET effective_to = DATE '2026-11-22' WHERE id = %L$q$, pg_temp.pdef('protected')), '23514', 'cannot close on');
SELECT pg_temp.admits_undone('D7p2 … November 23 is fine',
  format($q$UPDATE public.dispute_platform_defaults SET effective_to = DATE '2026-11-23' WHERE id = %L$q$, pg_temp.pdef('protected')));

-- ============================================================== D8 a law that tightens after a tariff (r3, Opus S1; r4, Opus S1)
-- T2 writes a wider tariff from January 1; 7.45 is then closed on June 1 and a stricter law takes over (it
-- also stops credit reporting, requires a payment arrangement to be offered, and the regulator decides
-- within 10 days, not 15). A dispute received
-- June 12, on a bill of June 10: the tariff is now looser in part. r4 (fail toward protection): it is cited
-- with the law, and the record follows the two combined — the tariff's end at resolution and its
-- undisputed-charges must-pay (no looser), the law's stages (the tariff's are looser), both blocks.
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000025b2', true);
CREATE FUNCTION pg_temp.tight_sql() RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.tariff_sql(NULL, '00000000-0000-4000-8000-0000000025a2', DATE '2026-01-01', pg_temp.tdoc()) || '; '
    || format($q$UPDATE public.dispute_rules SET effective_to = DATE '2026-06-01' WHERE id = %L$q$, pg_temp.law('investor_owned', 'protected')) || '; '
    || format($q$INSERT INTO public.dispute_rules (state_code, service_type, owner_types, system_kinds, commission_jurisdiction, customer_class,
                     effective_from, source_note, terms_kind, terms_version, terms_source)
                 VALUES ('TX', 'gas', '{cooperative,investor_owned}', '{distribution}', NULL, 'protected', DATE '2026-06-01', 'battery: a stricter law', 'dispute', 1, %L)$q$,
              ((SELECT doc FROM k25 WHERE owner = 'investor_owned' AND class = 'protected')
               || '{"blocks": {"codes": ["disconnect_order", "disconnect_execute", "late_fee", "credit_reporting"], "citation": "battery"},
                    "duties": {"codes": ["investigate", "report_result", "inform_complaint_route", "offer_payment_arrangement"], "citation": "battery"},
                    "stages": [{"id": "s1", "decider": "designated_employee", "file_within": {"kind": "none"}, "decide_within": {"kind": "none"}, "final": false, "citation": "battery"},
                               {"id": "s2", "decider": "regulator", "file_within": {"kind": "none"}, "decide_within": {"kind": "days", "days": 10}, "final": true, "citation": "battery"}]}')::text) || '; '
    || $q$SELECT pg_temp.bill('00000000-0000-4000-8000-0000000025a2', '00000000-0000-4000-8000-00000000250a', 'B25-I10', '00000000-0000-4000-8000-0000000025c5',
                              '00000000-0000-4000-8000-0000000025d5', '00000000-0000-4000-8000-0000000025e5', '00000000-0000-4000-8000-0000000025e6',
                              '00000000-0000-4000-8000-0000000025e7', DATE '2026-06-10')$q$ || '; '
    || pg_temp.dispute_sql('00000000-0000-4000-8000-00000000253d', '00000000-0000-4000-8000-0000000025a2', '00000000-0000-4000-8000-0000000025c5', '00000000-0000-4000-8000-00000000250a', NULL, 'calculation', DATE '2026-06-12') || '; '
    || pg_temp.amount_sql('00000000-0000-4000-8000-000000002540', '00000000-0000-4000-8000-0000000025a2', '00000000-0000-4000-8000-00000000253d', 40, 'customer_claim', DATE '2026-06-12') || '; '
$f$;
SELECT pg_temp.refuses_at('D8e the tariff cited with its own blocks only (credit reporting, the law''s, left out) is refused',
  pg_temp.tight_sql() || format($q$INSERT INTO public.dispute_determinations (tenant_id, dispute_id, dispute_amount_id, state_code, service_type, system_kind,
       customer_class, rule_id, tariff_id, outcome, sheltered_amount, must_pay_amount, must_pay_component, shelter_ends_on, blocks, inputs, inputs_fingerprint, calculated_by)
     SELECT '00000000-0000-4000-8000-0000000025a2', '00000000-0000-4000-8000-00000000253d', '00000000-0000-4000-8000-000000002540', 'TX', 'gas', 'distribution', 'protected',
            r.id, t.id, 'sheltered', 40, 50, 'm1', NULL, '{disconnect_execute,disconnect_order,late_fee,notice_issue}', '{}', 'fp-d8e', 'core-battery-25'
       FROM public.dispute_rules r, public.dispute_tariffs t
      WHERE r.source_note = 'battery: a stricter law' AND t.tenant_id = '00000000-0000-4000-8000-0000000025a2'$q$), '23514', '[D4h]');
SELECT pg_temp.refuses_at('D8f … and the law alone, while the tariff is in force, is refused (it would drop the tariff''s end at resolution and its notice block)',
  pg_temp.tight_sql() || format($q$INSERT INTO public.dispute_determinations (tenant_id, dispute_id, dispute_amount_id, state_code, service_type, system_kind,
       customer_class, rule_id, tariff_id, outcome, sheltered_amount, must_pay_amount, must_pay_component, shelter_ends_on, blocks, inputs, inputs_fingerprint, calculated_by)
     SELECT '00000000-0000-4000-8000-0000000025a2', '00000000-0000-4000-8000-00000000253d', '00000000-0000-4000-8000-000000002540', 'TX', 'gas', 'distribution', 'protected',
            r.id, NULL, 'sheltered', 40, 50, 'm1', DATE '2026-08-08', '{credit_reporting,disconnect_execute,disconnect_order,late_fee}', '{}', 'fp-d8f', 'core-battery-25'
       FROM public.dispute_rules r, public.dispute_tariffs t
      WHERE r.source_note = 'battery: a stricter law' AND t.tenant_id = '00000000-0000-4000-8000-0000000025a2'$q$), '23514', '[D4q]');
SELECT pg_temp.admits_undone('D8g … the tariff cited, with both documents'' blocks and no last day (the tariff''s end at resolution), is admitted',
  pg_temp.tight_sql() || format($q$INSERT INTO public.dispute_determinations (tenant_id, dispute_id, dispute_amount_id, state_code, service_type, system_kind,
       customer_class, rule_id, tariff_id, outcome, sheltered_amount, must_pay_amount, must_pay_component, shelter_ends_on, blocks, inputs, inputs_fingerprint, calculated_by)
     SELECT '00000000-0000-4000-8000-0000000025a2', '00000000-0000-4000-8000-00000000253d', '00000000-0000-4000-8000-000000002540', 'TX', 'gas', 'distribution', 'protected',
            r.id, t.id, 'sheltered', 40, 50, 'm1', NULL, '{credit_reporting,disconnect_execute,disconnect_order,late_fee,notice_issue}', '{}', 'fp-d8g', 'core-battery-25'
       FROM public.dispute_rules r, public.dispute_tariffs t
      WHERE r.source_note = 'battery: a stricter law' AND t.tenant_id = '00000000-0000-4000-8000-0000000025a2'$q$));
SELECT pg_temp.refuses_at('D8k … but not with the law''s last day (August 8): the combined document ends the shelter at resolution',
  pg_temp.tight_sql() || format($q$INSERT INTO public.dispute_determinations (tenant_id, dispute_id, dispute_amount_id, state_code, service_type, system_kind,
       customer_class, rule_id, tariff_id, outcome, sheltered_amount, must_pay_amount, must_pay_component, shelter_ends_on, blocks, inputs, inputs_fingerprint, calculated_by)
     SELECT '00000000-0000-4000-8000-0000000025a2', '00000000-0000-4000-8000-00000000253d', '00000000-0000-4000-8000-000000002540', 'TX', 'gas', 'distribution', 'protected',
            r.id, t.id, 'sheltered', 40, 50, 'm1', DATE '2026-08-08', '{credit_reporting,disconnect_execute,disconnect_order,late_fee,notice_issue}', '{}', 'fp-d8k', 'core-battery-25'
       FROM public.dispute_rules r, public.dispute_tariffs t
      WHERE r.source_note = 'battery: a stricter law' AND t.tenant_id = '00000000-0000-4000-8000-0000000025a2'$q$), '23514', '[D4s]');
SELECT pg_temp.admits_undone('D8j the combined document: the law''s stages, the tariff''s end and must-pay, both documents'' blocks and duties',
  pg_temp.tight_sql() || $q$DO $d$ DECLARE v jsonb; BEGIN
    SELECT public.dispute_determination_terms(r.id, t.id, NULL) INTO v
      FROM public.dispute_rules r, public.dispute_tariffs t
     WHERE r.source_note = 'battery: a stricter law' AND t.tenant_id = '00000000-0000-4000-8000-0000000025a2';
    IF (v #>> '{stages,1,decide_within,days}' = '10' AND jsonb_array_length(v -> 'stages') = 2
            AND v #>> '{shelter_ends,kind}' = 'resolution' AND v #>> '{must_pay,strategy}' = 'undisputed_charges'
            AND v #> '{blocks,codes}' = '["credit_reporting", "disconnect_execute", "disconnect_order", "late_fee", "notice_issue"]'
            AND v #> '{duties,codes}' = '["inform_complaint_route", "investigate", "offer_payment_arrangement", "report_result"]'
            AND v #>> '{shelter_earned,kind}' = 'before_termination') IS DISTINCT FROM true THEN
      RAISE EXCEPTION 'combined: %', v;
    END IF;
  END $d$$q$);

-- ============================================================== D9 the combination section by section (r5: Codex B1, Opus S1, Fable S1; Ryan 2026-11-26)
-- tight2_sql(tariff, law overrides): D8's shape with any tariff (written January 1 under 7.45) and any
-- stricter law (7.45's protected document with sections replaced). det2_sql(component, last day): the
-- combined determination, its blocks read from the combined document.
CREATE FUNCTION pg_temp.tight2_sql(p_tdoc jsonb, p_over jsonb) RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.tariff_sql(NULL, '00000000-0000-4000-8000-0000000025a2', DATE '2026-01-01', p_tdoc) || '; '
    || format($q$UPDATE public.dispute_rules SET effective_to = DATE '2026-06-01' WHERE id = %L$q$, pg_temp.law('investor_owned', 'protected')) || '; '
    || format($q$INSERT INTO public.dispute_rules (state_code, service_type, owner_types, system_kinds, commission_jurisdiction, customer_class,
                     effective_from, source_note, terms_kind, terms_version, terms_source)
                 VALUES ('TX', 'gas', '{cooperative,investor_owned}', '{distribution}', NULL, 'protected', DATE '2026-06-01', 'battery: a stricter law', 'dispute', 1, %L)$q$,
              ((SELECT doc FROM k25 WHERE owner = 'investor_owned' AND class = 'protected') || p_over)::text) || '; '
    || $q$SELECT pg_temp.bill('00000000-0000-4000-8000-0000000025a2', '00000000-0000-4000-8000-00000000250a', 'B25-I10', '00000000-0000-4000-8000-0000000025c5',
                              '00000000-0000-4000-8000-0000000025d5', '00000000-0000-4000-8000-0000000025e5', '00000000-0000-4000-8000-0000000025e6',
                              '00000000-0000-4000-8000-0000000025e7', DATE '2026-06-10')$q$ || '; '
    || pg_temp.dispute_sql('00000000-0000-4000-8000-00000000253d', '00000000-0000-4000-8000-0000000025a2', '00000000-0000-4000-8000-0000000025c5', '00000000-0000-4000-8000-00000000250a', NULL, 'calculation', DATE '2026-06-12') || '; '
    || pg_temp.amount_sql('00000000-0000-4000-8000-000000002540', '00000000-0000-4000-8000-0000000025a2', '00000000-0000-4000-8000-00000000253d', 40, 'customer_claim', DATE '2026-06-12') || '; '
$f$;
CREATE FUNCTION pg_temp.det2_sql(p_comp text, p_ends date) RETURNS text LANGUAGE sql AS $f$
  SELECT format($q$INSERT INTO public.dispute_determinations (tenant_id, dispute_id, dispute_amount_id, state_code, service_type, system_kind,
       customer_class, rule_id, tariff_id, outcome, sheltered_amount, must_pay_amount, must_pay_component, shelter_ends_on, blocks, inputs, inputs_fingerprint, calculated_by)
     SELECT '00000000-0000-4000-8000-0000000025a2', '00000000-0000-4000-8000-00000000253d', '00000000-0000-4000-8000-000000002540', 'TX', 'gas', 'distribution', 'protected',
            r.id, t.id, 'sheltered', 40, 50, %L, %L,
            ARRAY(SELECT jsonb_array_elements_text(public.dispute_determination_terms(r.id, t.id, NULL) #> '{blocks,codes}')), '{}', 'fp-d9', 'core-battery-25'
       FROM public.dispute_rules r, public.dispute_tariffs t
      WHERE r.source_note = 'battery: a stricter law' AND t.tenant_id = '00000000-0000-4000-8000-0000000025a2'$q$, p_comp, p_ends)
$f$;
-- combo(tariff, law overrides): the combination of two documents, by direct call.
CREATE FUNCTION pg_temp.combo(p_tdoc jsonb, p_over jsonb) RETURNS jsonb LANGUAGE sql AS $f$
  SELECT public.dispute_terms_combined(jsonb_build_object('terms', p_tdoc),
           jsonb_build_object('id', 'battery-law', 'customer_class', 'protected',
                              'terms', (SELECT doc FROM k25 WHERE owner = 'investor_owned' AND class = 'protected') || p_over))
$f$;

-- Stages: the tariff's own appeal to the governing body, after the law's, and its 10-day first decision.
CREATE FUNCTION pg_temp.st3() RETURNS jsonb LANGUAGE sql AS $f$
  SELECT pg_temp.tdoc('{"stages": [{"id": "s1", "decider": "designated_employee", "file_within": {"kind": "none"}, "decide_within": {"kind": "days", "days": 10}, "final": false},
                                   {"id": "s2", "decider": "regulator", "file_within": {"kind": "none"}, "decide_within": {"kind": "days", "days": 15}, "final": false},
                                   {"id": "s3", "decider": "governing_body", "file_within": {"kind": "days", "days": 30, "from": "prior_decision"}, "decide_within": {"kind": "days", "days": 30}, "final": true}]}')
$f$;
CREATE FUNCTION pg_temp.law10() RETURNS jsonb LANGUAGE sql AS $f$
  SELECT '{"stages": [{"id": "s1", "decider": "designated_employee", "file_within": {"kind": "none"}, "decide_within": {"kind": "none"}, "final": false, "citation": "battery"},
                      {"id": "s2", "decider": "regulator", "file_within": {"kind": "none"}, "decide_within": {"kind": "days", "days": 10}, "final": true, "citation": "battery"}]}'::jsonb
$f$;
SELECT pg_temp.admits_undone('D9a under a tightened regulator, the combined stages keep the tariff''s 10-day first decision, take the law''s 10-day regulator (final), and keep the tariff''s governing-body appeal after; its stage event is admitted',
  pg_temp.tight2_sql(pg_temp.st3(), pg_temp.law10()) || pg_temp.det2_sql('m1', NULL) || '; '
  || pg_temp.ev_sql('00000000-0000-4000-8000-0000000025a2', '00000000-0000-4000-8000-00000000253d', 'stage_entered', DATE '2026-06-20', 's3', 'governing_body') || '; '
  || $q$DO $d$ DECLARE v jsonb; BEGIN
    SELECT public.dispute_determination_terms(r.id, t.id, NULL) -> 'stages' INTO v
      FROM public.dispute_rules r, public.dispute_tariffs t
     WHERE r.source_note = 'battery: a stricter law' AND t.tenant_id = '00000000-0000-4000-8000-0000000025a2';
    IF (jsonb_array_length(v) = 3 AND v #>> '{0,id}' = 's1' AND v #>> '{0,decide_within,days}' = '10'
            AND v #>> '{1,id}' = 's2' AND v #>> '{1,decide_within,days}' = '10' AND v #>> '{1,final}' = 'true'
            AND v #>> '{2,id}' = 's3' AND v #>> '{2,decider}' = 'governing_body') IS DISTINCT FROM true THEN
      RAISE EXCEPTION 'stages: %', v;
    END IF;
  END $d$$q$);
SELECT pg_temp.refuses_at('D9a2 … a stage event naming the appeal before another decider is still refused',
  pg_temp.tight2_sql(pg_temp.st3(), pg_temp.law10()) || pg_temp.det2_sql('m1', NULL) || '; '
  || pg_temp.ev_sql('00000000-0000-4000-8000-0000000025a2', '00000000-0000-4000-8000-00000000253d', 'stage_entered', DATE '2026-06-20', 's3', 'regulator'), '23514', '[D5b]');
SELECT pg_temp.ok('D9b a stage of the law''s decider keeps the wider filing window (the tariff''s none) beside the law''s quicker decision',
  (SELECT v #> '{stages,1,file_within}' = '{"kind": "none"}' AND v #>> '{stages,1,decide_within,days}' = '10'
     FROM pg_temp.combo(pg_temp.tdoc(), '{"stages": [{"id": "s1", "decider": "designated_employee", "file_within": {"kind": "none"}, "decide_within": {"kind": "none"}, "final": false},
                                                     {"id": "s2", "decider": "regulator", "file_within": {"kind": "days", "days": 30, "from": "prior_decision"}, "decide_within": {"kind": "days", "days": 10}, "final": true}]}') v));
SELECT pg_temp.ok('D9b2 … and filing windows counted from two anchors are both kept',
  (SELECT v #> '{stages,1,file_within,either}' = '[{"kind": "days", "days": 20, "from": "issue"}, {"kind": "days", "days": 30, "from": "prior_decision"}]'
     FROM pg_temp.combo(pg_temp.tdoc('{"stages": [{"id": "s1", "decider": "designated_employee", "file_within": {"kind": "none"}, "decide_within": {"kind": "none"}, "final": false},
                                                  {"id": "s2", "decider": "regulator", "file_within": {"kind": "days", "days": 20, "from": "issue"}, "decide_within": {"kind": "days", "days": 10}, "final": true}]}'),
                        '{"stages": [{"id": "s1", "decider": "designated_employee", "file_within": {"kind": "none"}, "decide_within": {"kind": "none"}, "final": false},
                                     {"id": "s2", "decider": "regulator", "file_within": {"kind": "days", "days": 30, "from": "prior_decision"}, "decide_within": {"kind": "days", "days": 10}, "final": true}]}') v));
SELECT pg_temp.ok('D9b3 a tariff stage of another decider at the law''s place: the law''s stage there (its id marked, the tariff uses s2), then the tariff''s other stages in order',
  (SELECT array(SELECT x ->> 'id' || '/' || (x ->> 'decider') FROM jsonb_array_elements(v -> 'stages') x)
          = ARRAY['s1/designated_employee', 'law:s2/regulator', 's2/governing_body', 's3/regulator']
     FROM pg_temp.combo(pg_temp.tdoc('{"stages": [{"id": "s1", "decider": "designated_employee", "file_within": {"kind": "none"}, "decide_within": {"kind": "none"}, "final": false},
                                                  {"id": "s2", "decider": "governing_body", "file_within": {"kind": "none"}, "decide_within": {"kind": "days", "days": 30}, "final": false},
                                                  {"id": "s3", "decider": "regulator", "file_within": {"kind": "none"}, "decide_within": {"kind": "days", "days": 15}, "final": true}]}'),
                        pg_temp.law10()) v));
SELECT pg_temp.ok('D9c subjects: what either admits (listed: the tariff''s deposit beside the law''s meter accuracy)',
  (SELECT public.dispute_subjects_admitted(v -> 'subjects') = ARRAY['calculation', 'deposit', 'meter_accuracy']
     FROM pg_temp.combo(pg_temp.tdoc('{"subjects": {"kind": "listed", "codes": ["calculation", "deposit"], "excluded": []}}'),
                        '{"subjects": {"kind": "listed", "codes": ["calculation", "meter_accuracy"], "excluded": [], "citation": "battery"}}') v));
SELECT pg_temp.ok('D9c2 … (any: excluded only where both exclude; the tariff admits identity theft, the law tamper findings)',
  (SELECT v -> 'subjects' = '{"kind": "any", "excluded": []}'
     FROM pg_temp.combo(pg_temp.tdoc('{"subjects": {"kind": "any", "excluded": ["tamper_finding"]}}'),
                        '{"subjects": {"kind": "any", "excluded": ["identity_theft"], "citation": "battery"}}') v));
SELECT pg_temp.ok('D9c3 … (one any, one listed: excluded only what the listed one does not admit)',
  (SELECT v #> '{subjects,excluded}' = '["tamper_finding"]' AND v #>> '{subjects,kind}' = 'any'
     FROM pg_temp.combo(pg_temp.tdoc('{"subjects": {"kind": "any", "excluded": ["identity_theft", "tamper_finding"]}}'),
                        '{"subjects": {"kind": "listed", "codes": ["calculation", "identity_theft"], "excluded": [], "citation": "battery"}}') v));

-- Terms that rank: the law's wins (Opus N6).
SELECT pg_temp.refuses_at('D9d a must-pay the law ranks below (undisputed charges, id m2, against the tariff''s average cap): the tariff''s component is refused',
  pg_temp.tight2_sql(pg_temp.tdoc('{"must_pay": {"strategy": "average_usage_cap", "history_years": 2, "no_history": "similar_customers", "version": 1, "id": "m1"}}'),
                     '{"must_pay": {"strategy": "undisputed_charges", "version": 1, "id": "m2", "citation": "battery"}}') || pg_temp.det2_sql('m1', NULL), '23514', '[D4g]');
SELECT pg_temp.admits_undone('D9d2 … the law''s is admitted',
  pg_temp.tight2_sql(pg_temp.tdoc('{"must_pay": {"strategy": "average_usage_cap", "history_years": 2, "no_history": "similar_customers", "version": 1, "id": "m1"}}'),
                     '{"must_pay": {"strategy": "undisputed_charges", "version": 1, "id": "m2", "citation": "battery"}}') || pg_temp.det2_sql('m2', NULL));
SELECT pg_temp.admits_undone('D9e an end the law ranks later (90 days from issue, against the tariff''s 60): a last day of August 20, past the tariff''s August 8, is admitted',
  pg_temp.tight2_sql(pg_temp.tdoc('{"shelter_ends": {"kind": "earlier_of_resolution_and_days", "days": 60, "from": "issue"}}'),
                     '{"shelter_ends": {"kind": "earlier_of_resolution_and_days", "days": 90, "from": "issue", "citation": "battery"}}') || pg_temp.det2_sql('m1', DATE '2026-08-20'));
SELECT pg_temp.refuses_at('D9e2 … September 8, past the law''s September 7, is refused',
  pg_temp.tight2_sql(pg_temp.tdoc('{"shelter_ends": {"kind": "earlier_of_resolution_and_days", "days": 60, "from": "issue"}}'),
                     '{"shelter_ends": {"kind": "earlier_of_resolution_and_days", "days": 90, "from": "issue", "citation": "battery"}}') || pg_temp.det2_sql('m1', DATE '2026-09-08'), '23514', '[D4p]');

-- Terms that cannot be ranked: both kept, the record fitting either (Ryan 2026-11-26).
SELECT pg_temp.ok('D9f the comparator names the verdicts: an average over 2 years against 3 cannot be ranked; an average cap against undisputed charges is looser',
  (SELECT array_agg(verdict) = '{not_comparable}' FROM public.dispute_tariff_compare_sections(jsonb_build_object('terms',
            pg_temp.tdoc('{"must_pay": {"strategy": "average_usage_cap", "history_years": 2, "no_history": "similar_customers", "version": 1, "id": "m1"}}')),
          jsonb_build_array(jsonb_build_object('id', 'x', 'terms', (SELECT doc FROM k25 WHERE owner = 'investor_owned' AND class = 'protected')
                                                                  || '{"must_pay": {"strategy": "average_usage_cap", "history_years": 3, "no_history": "similar_customers", "version": 1, "id": "m1", "citation": "battery"}}'))))
  AND (SELECT array_agg(verdict) = '{looser}' FROM public.dispute_tariff_compare_sections(jsonb_build_object('terms',
            pg_temp.tdoc('{"must_pay": {"strategy": "average_usage_cap", "history_years": 2, "no_history": "similar_customers", "version": 1, "id": "m1"}}')),
          jsonb_build_array(jsonb_build_object('id', 'x', 'terms', (SELECT doc FROM k25 WHERE owner = 'investor_owned' AND class = 'protected')
                                                                  || '{"must_pay": {"strategy": "undisputed_charges", "version": 1, "id": "m2", "citation": "battery"}}')))));
CREATE FUNCTION pg_temp.avg3() RETURNS jsonb LANGUAGE sql AS $f$
  SELECT '{"must_pay": {"strategy": "average_usage_cap", "history_years": 3, "no_history": "similar_customers", "version": 1, "id": "m1", "citation": "battery"}}'::jsonb
$f$;
CREATE FUNCTION pg_temp.avg2t() RETURNS jsonb LANGUAGE sql AS $f$
  SELECT pg_temp.tdoc('{"must_pay": {"strategy": "average_usage_cap", "history_years": 2, "no_history": "similar_customers", "version": 1, "id": "m1"}}')
$f$;
SELECT pg_temp.ok('D9f2 … the combined must-pay keeps both, the law''s id marked',
  (SELECT v #> '{must_pay,either}' -> 0 ->> 'history_years' = '2' AND v #> '{must_pay,either}' -> 1 ->> 'history_years' = '3'
          AND v #> '{must_pay,either}' -> 1 ->> 'id' = 'law:m1' FROM pg_temp.combo(pg_temp.avg2t(), pg_temp.avg3()) v));
SELECT pg_temp.admits_undone('D9f3 … the tariff''s component (the 2-year average) is admitted',
  pg_temp.tight2_sql(pg_temp.avg2t(), pg_temp.avg3()) || pg_temp.det2_sql('m1', NULL));
SELECT pg_temp.admits_undone('D9f4 … the law''s (the 3-year average) is admitted',
  pg_temp.tight2_sql(pg_temp.avg2t(), pg_temp.avg3()) || pg_temp.det2_sql('law:m1', NULL));
SELECT pg_temp.refuses_at('D9f5 … any other is refused',
  pg_temp.tight2_sql(pg_temp.avg2t(), pg_temp.avg3()) || pg_temp.det2_sql('m3', NULL), '23514', '[D4g]');
CREATE FUNCTION pg_temp.e60t() RETURNS jsonb LANGUAGE sql AS $f$
  SELECT pg_temp.tdoc('{"shelter_ends": {"kind": "earlier_of_resolution_and_days", "days": 60, "from": "issue"}}')
$f$;
CREATE FUNCTION pg_temp.erc() RETURNS jsonb LANGUAGE sql AS $f$
  SELECT '{"shelter_ends": {"kind": "through_regulator_close", "citation": "battery"}}'::jsonb
$f$;
SELECT pg_temp.admits_undone('D9g an end that cannot be ranked (the tariff''s 60 days against the law''s regulator''s close): a last day within the tariff''s is admitted',
  pg_temp.tight2_sql(pg_temp.e60t(), pg_temp.erc()) || pg_temp.det2_sql('m1', DATE '2026-08-01'));
SELECT pg_temp.admits_undone('D9g2 … no last day (the regulator''s close) is admitted',
  pg_temp.tight2_sql(pg_temp.e60t(), pg_temp.erc()) || pg_temp.det2_sql('m1', NULL));
SELECT pg_temp.refuses_at('D9g3 … a last day past the tariff''s fits neither',
  pg_temp.tight2_sql(pg_temp.e60t(), pg_temp.erc()) || pg_temp.det2_sql('m1', DATE '2026-08-20'), '23514', '[D4t]');
SELECT pg_temp.ok('D9h a start that cannot be ranked (the tariff''s before termination, the law''s within 30 days of issue) keeps both; a ranked start takes the law''s',
  (SELECT v #> '{shelter_earned,either}' -> 0 ->> 'kind' = 'before_termination' AND v #> '{shelter_earned,either}' -> 1 ->> 'kind' = 'within_days'
     FROM pg_temp.combo(pg_temp.tdoc(), '{"shelter_earned": {"kind": "within_days", "days": 30, "from": "issue", "citation": "battery"}}') v)
  AND (SELECT v #>> '{shelter_earned,kind}' = 'any_time'
     FROM pg_temp.combo(pg_temp.tdoc(), '{"shelter_earned": {"kind": "any_time", "citation": "battery"}}') v));
SELECT pg_temp.refuses_at('D9i a policy filed while the law is in force is still refused where a term cannot be ranked',
  pg_temp.tariff_sql(NULL, '00000000-0000-4000-8000-0000000025a2', DATE '2026-01-01',
                     pg_temp.tdoc('{"must_pay": {"strategy": "average_usage_cap", "history_years": 3, "no_history": "similar_customers", "version": 1, "id": "m1"}}')), '23514', 'must_pay');

-- ============================================================== D9 r6 (Codex B1, B2, S1; Opus S1, S2, N1, N4; Fable S1, N3, N5, N6, N9)
-- verdicts(tariff, law overrides): the comparator's findings by direct call, section:verdict in order.
CREATE FUNCTION pg_temp.verdicts(p_tdoc jsonb, p_over jsonb) RETURNS text[] LANGUAGE sql AS $f$
  SELECT coalesce(array_agg(f.section || ':' || f.verdict ORDER BY f.n), '{}')
    FROM public.dispute_tariff_compare_sections(jsonb_build_object('terms', p_tdoc),
           jsonb_build_array(jsonb_build_object('id', 'x', 'customer_class', 'protected',
             'terms', (SELECT doc FROM k25 WHERE owner = 'investor_owned' AND class = 'protected') || p_over))) WITH ORDINALITY f(section, verdict, problem, n)
$f$;
-- file2_sql(tariff, law overrides): a stricter law from June 1 (7.45 closed), then T2's policy filed July 1 under it.
CREATE FUNCTION pg_temp.file2_sql(p_tdoc jsonb, p_over jsonb) RETURNS text LANGUAGE sql AS $f$
  SELECT format($q$UPDATE public.dispute_rules SET effective_to = DATE '2026-06-01' WHERE id = %L$q$, pg_temp.law('investor_owned', 'protected')) || '; '
    || format($q$INSERT INTO public.dispute_rules (state_code, service_type, owner_types, system_kinds, commission_jurisdiction, customer_class,
                     effective_from, source_note, terms_kind, terms_version, terms_source)
                 VALUES ('TX', 'gas', '{cooperative,investor_owned}', '{distribution}', NULL, 'protected', DATE '2026-06-01', 'battery: a stricter law', 'dispute', 1, %L)$q$,
              ((SELECT doc FROM k25 WHERE owner = 'investor_owned' AND class = 'protected') || p_over)::text) || '; '
    || pg_temp.tariff_sql(NULL, '00000000-0000-4000-8000-0000000025a2', DATE '2026-07-01', p_tdoc)
$f$;
-- st3b(): st3 with the law's own 15-day regulator (not final: its governing-body appeal follows), so no stage finding under 7.45.
CREATE FUNCTION pg_temp.st3b() RETURNS jsonb LANGUAGE sql AS $f$
  SELECT pg_temp.tdoc('{"stages": [{"id": "s1", "decider": "designated_employee", "file_within": {"kind": "none"}, "decide_within": {"kind": "days", "days": 10}, "final": false},
                                   {"id": "s2", "decider": "regulator", "file_within": {"kind": "none"}, "decide_within": {"kind": "days", "days": 15}, "final": false},
                                   {"id": "s3", "decider": "governing_body", "file_within": {"kind": "days", "days": 30, "from": "prior_decision"}, "decide_within": {"kind": "days", "days": 30}, "final": true}]}')
$f$;
CREATE FUNCTION pg_temp.wcap(p_fraction numeric, p_id text) RETURNS jsonb LANGUAGE sql AS $f$
  SELECT jsonb_build_object('strategy', 'withhold_cap', 'version', 1, 'id', p_id, 'fraction', p_fraction, 'citation', 'battery')
$f$;
CREATE FUNCTION pg_temp.undisp(p_id text) RETURNS jsonb LANGUAGE sql AS $f$
  SELECT jsonb_build_object('strategy', 'undisputed_charges', 'version', 1, 'id', p_id, 'citation', 'battery')
$f$;

-- Item 1: the law's final flag in every combined record.
SELECT pg_temp.admits_undone('D9j a policy no looser in its stages (7.45''s, then its own governing-body appeal; its regulator not final) under a law of the same stage terms: the combined regulator is final, the rest as the policy has it',
  pg_temp.tight2_sql(pg_temp.st3b(), '{}') || pg_temp.det2_sql('m1', NULL) || '; '
  || $q$DO $d$ DECLARE v jsonb; BEGIN
    SELECT public.dispute_determination_terms(r.id, t.id, NULL) -> 'stages' INTO v
      FROM public.dispute_rules r, public.dispute_tariffs t
     WHERE r.source_note = 'battery: a stricter law' AND t.tenant_id = '00000000-0000-4000-8000-0000000025a2';
    -- r7 (Codex S2): the whole list, so a missing field fails the check
    IF v IS DISTINCT FROM jsonb_set(pg_temp.st3b() -> 'stages', '{1,final}', 'true') THEN
      RAISE EXCEPTION 'stages: %', v;
    END IF;
  END $d$$q$);
SELECT pg_temp.ok('D9j2 … and under a law that only adds a block: the regulator is final there too, the block among the policy''s',
  (SELECT v #>> '{stages,1,final}' = 'true' AND v #> '{blocks,codes}' ? 'credit_reporting' AND jsonb_array_length(v -> 'stages') = 3
     FROM pg_temp.combo(pg_temp.st3b(), '{"blocks": {"codes": ["credit_reporting", "disconnect_execute", "disconnect_order", "late_fee"], "citation": "battery"}}') v));

-- Item 2: undisputed charges against a withholding cap compare as a fraction of 1, both ways.
SELECT pg_temp.ok('D9k undisputed charges against a cap: no finding under 0.9 or 1, narrower under 1.1; a cap against undisputed charges: narrower at 0.9, none at 1 or 1.1',
  pg_temp.verdicts(pg_temp.tdoc(), jsonb_build_object('must_pay', pg_temp.wcap(0.9, 'm2'))) = '{}'
  AND pg_temp.verdicts(pg_temp.tdoc(), jsonb_build_object('must_pay', pg_temp.wcap(1, 'm2'))) = '{}'
  AND pg_temp.verdicts(pg_temp.tdoc(), jsonb_build_object('must_pay', pg_temp.wcap(1.1, 'm2'))) = '{must_pay:looser}'
  AND pg_temp.verdicts(pg_temp.tdoc(jsonb_build_object('must_pay', pg_temp.wcap(0.9, 'm1'))), jsonb_build_object('must_pay', pg_temp.undisp('m2'))) = '{must_pay:looser}'
  AND pg_temp.verdicts(pg_temp.tdoc(jsonb_build_object('must_pay', pg_temp.wcap(1, 'm1'))), jsonb_build_object('must_pay', pg_temp.undisp('m2'))) = '{}'
  AND pg_temp.verdicts(pg_temp.tdoc(jsonb_build_object('must_pay', pg_temp.wcap(1.1, 'm1'))), jsonb_build_object('must_pay', pg_temp.undisp('m2'))) = '{}');
SELECT pg_temp.refuses_at('D9k2 a policy of undisputed charges filed under a law withholding up to 1.1 (X8, N7d''s twin) is refused',
  pg_temp.tariff_sql(NULL, '00000000-0000-4000-8000-0000000025a4', DATE '2026-02-01', pg_temp.tdoc('{"shelter_earned": {"kind": "within_days", "days": 21, "from": "receipt"}}')),
  '23514', 'must_pay');
SELECT pg_temp.admits_undone('D9k3 a policy withholding up to 1.1 filed under a law of undisputed charges is admitted',
  pg_temp.file2_sql(pg_temp.tdoc(jsonb_build_object('must_pay', pg_temp.wcap(1.1, 'm1') - 'citation')), jsonb_build_object('must_pay', pg_temp.undisp('m2'))));
SELECT pg_temp.refuses_at('D9k4 … one withholding up to 0.9 is refused',
  pg_temp.file2_sql(pg_temp.tdoc(jsonb_build_object('must_pay', pg_temp.wcap(0.9, 'm1') - 'citation')), jsonb_build_object('must_pay', pg_temp.undisp('m2'))),
  '23514', 'must_pay');
SELECT pg_temp.refuses_at('D9k5 a policy of undisputed charges under a later law withholding up to 1.1: the policy''s component is refused',
  pg_temp.tight2_sql(pg_temp.tdoc(), jsonb_build_object('must_pay', pg_temp.wcap(1.1, 'm2'))) || pg_temp.det2_sql('m1', NULL), '23514', '[D4g]');
SELECT pg_temp.admits_undone('D9k6 … the law''s is admitted',
  pg_temp.tight2_sql(pg_temp.tdoc(), jsonb_build_object('must_pay', pg_temp.wcap(1.1, 'm2'))) || pg_temp.det2_sql('m2', NULL));
SELECT pg_temp.ok('D9k7 a policy withholding up to 1.1 under a later law of undisputed charges keeps its own',
  (SELECT v -> 'must_pay' = pg_temp.wcap(1.1, 'm1') - 'citation'
     FROM pg_temp.combo(pg_temp.tdoc(jsonb_build_object('must_pay', pg_temp.wcap(1.1, 'm1') - 'citation')), jsonb_build_object('must_pay', pg_temp.undisp('m2'))) v));

-- Item 3: every looser branch and every part of the merge reached (Fable S1, Opus S2).
SELECT pg_temp.refuses_at('D9l an end of 60 days under a later law ending at resolution: the law''s end, so a last day is refused',
  pg_temp.tight2_sql(pg_temp.e60t(), '{"shelter_ends": {"kind": "resolution", "citation": "battery"}}') || pg_temp.det2_sql('m1', DATE '2026-08-01'), '23514', '[D4s]');
SELECT pg_temp.admits_undone('D9l2 … no last day is admitted',
  pg_temp.tight2_sql(pg_temp.e60t(), '{"shelter_ends": {"kind": "resolution", "citation": "battery"}}') || pg_temp.det2_sql('m1', NULL));
SELECT pg_temp.ok('D9m a full-bill policy under the law''s average cap: the law''s must-pay, not both (a full-bill policy is refused at filing, so by direct call)',
  (SELECT v -> 'must_pay' = (SELECT doc -> 'must_pay' FROM k25 WHERE owner = 'investor_owned' AND class = 'protected')
     FROM pg_temp.combo(pg_temp.tdoc('{"must_pay": {"strategy": "full_bill", "version": 1, "id": "mf"}}'), '{}') v));
SELECT pg_temp.ok('D9n a policy withholding up to 0.5 under a law of 0.8: the law''s, not both',
  (SELECT v -> 'must_pay' = pg_temp.wcap(0.8, 'm2')
     FROM pg_temp.combo(pg_temp.tdoc(jsonb_build_object('must_pay', pg_temp.wcap(0.5, 'mw') - 'citation')), jsonb_build_object('must_pay', pg_temp.wcap(0.8, 'm2'))) v));
SELECT pg_temp.ok('D9o a section the policy leaves unruled is narrower (by direct call: a policy cannot leave one unruled), and the law''s is taken',
  pg_temp.verdicts(pg_temp.tdoc('{"shelter_ends": {"kind": "unruled"}}'), '{}') = '{shelter_ends:looser}'
  AND (SELECT v -> 'shelter_ends' = (SELECT doc -> 'shelter_ends' FROM k25 WHERE owner = 'investor_owned' AND class = 'protected')
         FROM pg_temp.combo(pg_temp.tdoc('{"shelter_ends": {"kind": "unruled"}}'), '{}') v));
SELECT pg_temp.ok('D9o2 a start of fewer days from the same anchor is narrower',
  pg_temp.verdicts(pg_temp.tdoc('{"shelter_earned": {"kind": "within_days", "days": 20, "from": "issue"}}'),
                   '{"shelter_earned": {"kind": "within_days", "days": 30, "from": "issue", "citation": "battery"}}') = '{shelter_earned:looser}');
SELECT pg_temp.admits_undone('D9g4 the 60-day end against the regulator''s close (as D9g): the 60th day, August 8, is admitted',
  pg_temp.tight2_sql(pg_temp.e60t(), pg_temp.erc()) || pg_temp.det2_sql('m1', DATE '2026-08-08'));
SELECT pg_temp.refuses_at('D9g5 … August 9 fits neither',
  pg_temp.tight2_sql(pg_temp.e60t(), pg_temp.erc()) || pg_temp.det2_sql('m1', DATE '2026-08-09'), '23514', '[D4t]');
SELECT pg_temp.ok('D9p a policy stage with no decision deadline under the law''s 5 days: the combined stage decides within 5',
  (SELECT v #> '{stages,1,decide_within}' = '{"kind": "days", "days": 5}'
     FROM pg_temp.combo(pg_temp.tdoc('{"stages": [{"id": "s1", "decider": "designated_employee", "file_within": {"kind": "none"}, "decide_within": {"kind": "none"}, "final": false},
                                                  {"id": "s2", "decider": "regulator", "file_within": {"kind": "none"}, "decide_within": {"kind": "none"}, "final": true}]}'),
                        '{"stages": [{"id": "s1", "decider": "designated_employee", "file_within": {"kind": "none"}, "decide_within": {"kind": "none"}, "final": false},
                                     {"id": "s2", "decider": "regulator", "file_within": {"kind": "none"}, "decide_within": {"kind": "days", "days": 5}, "final": true}]}') v));
SELECT pg_temp.ok('D9p2 starts within days of two anchors (30 of issue, 21 of receipt) cannot be ranked: both kept',
  pg_temp.verdicts(pg_temp.tdoc('{"shelter_earned": {"kind": "within_days", "days": 30, "from": "issue"}}'),
                   '{"shelter_earned": {"kind": "within_days", "days": 21, "from": "receipt", "citation": "battery"}}') = '{shelter_earned:not_comparable}'
  AND (SELECT jsonb_array_length(v #> '{shelter_earned,either}') = 2
         FROM pg_temp.combo(pg_temp.tdoc('{"shelter_earned": {"kind": "within_days", "days": 30, "from": "issue"}}'),
                            '{"shelter_earned": {"kind": "within_days", "days": 21, "from": "receipt", "citation": "battery"}}') v));
CREATE FUNCTION pg_temp.regw(p_days integer) RETURNS jsonb LANGUAGE sql AS $f$
  SELECT jsonb_build_object('stages', jsonb_build_array(
    '{"id": "s1", "decider": "designated_employee", "file_within": {"kind": "none"}, "decide_within": {"kind": "none"}, "final": false}'::jsonb,
    jsonb_build_object('id', 's2', 'decider', 'regulator', 'file_within', jsonb_build_object('kind', 'days', 'days', p_days, 'from', 'prior_decision'),
                       'decide_within', '{"kind": "days", "days": 15}'::jsonb, 'final', true)))
$f$;
SELECT pg_temp.ok('D9p3 filing windows of one anchor: the wider is kept, the policy''s (30 against 20) or the law''s (30 against 20)',
  (SELECT v #>> '{stages,1,file_within,days}' = '30' FROM pg_temp.combo(pg_temp.tdoc(pg_temp.regw(30)), pg_temp.regw(20)) v)
  AND (SELECT v #>> '{stages,1,file_within,days}' = '30' FROM pg_temp.combo(pg_temp.tdoc(pg_temp.regw(20)), pg_temp.regw(30)) v));

-- Notes: any time is the widest start (Opus N1, Fable N3); a displaced stage on the real path (Fable N5); lists lack (Codex S1).
SELECT pg_temp.ok('D9q a start of any time is no narrower than a window, and a window is narrower than any time',
  pg_temp.verdicts(pg_temp.tdoc('{"shelter_earned": {"kind": "any_time"}}'), '{"shelter_earned": {"kind": "within_days", "days": 21, "from": "receipt", "citation": "battery"}}') = '{}'
  AND pg_temp.verdicts(pg_temp.tdoc('{"shelter_earned": {"kind": "any_time"}}'), '{"shelter_earned": {"kind": "on_regulator_complaint", "citation": "battery"}}') = '{}'
  AND pg_temp.verdicts(pg_temp.tdoc('{"shelter_earned": {"kind": "within_days", "days": 30, "from": "issue"}}'), '{"shelter_earned": {"kind": "any_time", "citation": "battery"}}') = '{shelter_earned:looser}');
SELECT pg_temp.admits_undone('D9q2 a policy sheltering any time is filed under X8''s 21-day window',
  pg_temp.tariff_sql(NULL, '00000000-0000-4000-8000-0000000025a4', DATE '2026-02-01', pg_temp.tdoc(
    '{"shelter_earned": {"kind": "any_time"}, "must_pay": {"strategy": "withhold_cap", "version": 1, "id": "m1", "fraction": 1.1}}')));
CREATE FUNCTION pg_temp.lawgb() RETURNS jsonb LANGUAGE sql AS $f$
  SELECT '{"stages": [{"id": "s1", "decider": "designated_employee", "file_within": {"kind": "none"}, "decide_within": {"kind": "none"}, "final": false, "citation": "battery"},
                      {"id": "s2", "decider": "governing_body", "file_within": {"kind": "none"}, "decide_within": {"kind": "days", "days": 30}, "final": false, "citation": "battery"},
                      {"id": "s3", "decider": "regulator", "file_within": {"kind": "days", "days": 30, "from": "prior_decision"}, "decide_within": {"kind": "days", "days": 10}, "final": true, "citation": "battery"}]}'::jsonb
$f$;
SELECT pg_temp.admits_undone('D9r a law that puts a stage mid-list: the policy''s displaced regulator follows the law''s last, and a stage event at the law''s marked id is admitted',
  pg_temp.tight2_sql(pg_temp.tdoc(), pg_temp.lawgb()) || pg_temp.det2_sql('m1', NULL) || '; '
  || pg_temp.ev_sql('00000000-0000-4000-8000-0000000025a2', '00000000-0000-4000-8000-00000000253d', 'stage_entered', DATE '2026-06-20', 'law:s2', 'governing_body') || '; '
  || $q$DO $d$ DECLARE v jsonb; BEGIN
    SELECT public.dispute_determination_terms(r.id, t.id, NULL) -> 'stages' INTO v
      FROM public.dispute_rules r, public.dispute_tariffs t
     WHERE r.source_note = 'battery: a stricter law' AND t.tenant_id = '00000000-0000-4000-8000-0000000025a2';
    IF array(SELECT x ->> 'id' || '/' || (x ->> 'decider') FROM jsonb_array_elements(v) x)
       IS DISTINCT FROM ARRAY['s1/designated_employee', 'law:s2/governing_body', 's3/regulator', 's2/regulator'] THEN
      RAISE EXCEPTION 'stages: %', v;
    END IF;
  END $d$$q$);
SELECT pg_temp.ok('D9s a list that misses one of the law''s says it lacks it (blocks, duties, stages, subjects; the single terms'' verdicts are D9k, D9o, D9o2, D9p2)',
  pg_temp.verdicts(pg_temp.tdoc('{"blocks": {"codes": []}, "duties": {"codes": []}, "stages": [], "subjects": {"kind": "listed", "codes": ["calculation"], "excluded": []}}'), '{}')
    = '{blocks:lacks,duties:lacks,stages:lacks,subjects:lacks}');

-- ============================================================== D9 r7 (Fable S1, S2, N3; Opus N1, N2)
-- avg(id): 7.45's average-usage cap.
CREATE FUNCTION pg_temp.avg(p_id text) RETURNS jsonb LANGUAGE sql AS $f$
  SELECT jsonb_build_object('strategy', 'average_usage_cap', 'version', 1, 'id', p_id, 'history_years', 2, 'no_history', 'similar_customers')
$f$;
SELECT pg_temp.ok('D9t a withholding cap against the law''s average cap: none at 1 or 1.1, not comparable at 0.9; an average cap against a law''s cap: narrower at 1 and 1.1, not comparable at 0.9',
  pg_temp.verdicts(pg_temp.tdoc(jsonb_build_object('must_pay', pg_temp.wcap(1.1, 'm1'))), '{}') = '{}'
  AND pg_temp.verdicts(pg_temp.tdoc(jsonb_build_object('must_pay', pg_temp.wcap(1, 'm1'))), '{}') = '{}'
  AND pg_temp.verdicts(pg_temp.tdoc(jsonb_build_object('must_pay', pg_temp.wcap(0.9, 'm1'))), '{}') = '{must_pay:not_comparable}'
  AND pg_temp.verdicts(pg_temp.tdoc(jsonb_build_object('must_pay', pg_temp.avg('m1'))), jsonb_build_object('must_pay', pg_temp.wcap(1.1, 'm2'))) = '{must_pay:looser}'
  AND pg_temp.verdicts(pg_temp.tdoc(jsonb_build_object('must_pay', pg_temp.avg('m1'))), jsonb_build_object('must_pay', pg_temp.wcap(1, 'm2'))) = '{must_pay:looser}'
  AND pg_temp.verdicts(pg_temp.tdoc(jsonb_build_object('must_pay', pg_temp.avg('m1'))), jsonb_build_object('must_pay', pg_temp.wcap(0.9, 'm2'))) = '{must_pay:not_comparable}');
SELECT pg_temp.refuses_at('D9t2 an average-cap policy under a later law withholding up to 1.1: the policy''s component is refused',
  pg_temp.tight2_sql(pg_temp.tdoc(jsonb_build_object('must_pay', pg_temp.avg('m1'))), jsonb_build_object('must_pay', pg_temp.wcap(1.1, 'm2'))) || pg_temp.det2_sql('m1', NULL), '23514', '[D4g]');
SELECT pg_temp.admits_undone('D9t3 … the law''s is admitted',
  pg_temp.tight2_sql(pg_temp.tdoc(jsonb_build_object('must_pay', pg_temp.avg('m1'))), jsonb_build_object('must_pay', pg_temp.wcap(1.1, 'm2'))) || pg_temp.det2_sql('m2', NULL));
SELECT pg_temp.ok('D9t4 … and under a later law withholding up to 0.9 both are kept',
  (SELECT jsonb_array_length(v #> '{must_pay,either}') = 2
     FROM pg_temp.combo(pg_temp.tdoc(jsonb_build_object('must_pay', pg_temp.avg('m1'))), jsonb_build_object('must_pay', pg_temp.wcap(0.9, 'm2'))) v));
-- The law's final flag, in the direction no seeded law has: a policy's final regulator under a law whose regulator is not final.
SELECT pg_temp.ok('D9u the law''s final flag is taken at its places either way: a policy''s final regulator under a law whose regulator is not final comes back not final (residual R10)',
  (SELECT v #>> '{stages,1,final}' = 'false'
     FROM pg_temp.combo(pg_temp.tdoc(), '{"stages": [{"id": "s1", "decider": "designated_employee", "file_within": {"kind": "none"}, "decide_within": {"kind": "none"}, "final": false},
                                                     {"id": "s2", "decider": "regulator", "file_within": {"kind": "none"}, "decide_within": {"kind": "days", "days": 15}, "final": false}]}') v));

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
     FROM unnest(ARRAY['public.disputes', 'public.dispute_amounts', 'public.dispute_determinations', 'public.dispute_events', 'public.dispute_rules',
                       'public.dispute_platform_defaults']) t));
SET ROLE tally_app;
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000025b2', true);
SELECT pg_temp.ok('H8 each utility sees its own dispute records only: T2 sees its two disputes and none of T1''s or T3''s',
  (SELECT count(*) = 2 FROM public.disputes) AND (SELECT count(*) = 2 FROM public.dispute_determinations)
  AND NOT EXISTS (SELECT 1 FROM public.dispute_events WHERE tenant_id <> '00000000-0000-4000-8000-0000000025a2')
  AND NOT EXISTS (SELECT 1 FROM public.dispute_amounts WHERE tenant_id <> '00000000-0000-4000-8000-0000000025a2')
  AND NOT EXISTS (SELECT 1 FROM public.dispute_tariffs WHERE tenant_id <> '00000000-0000-4000-8000-0000000025a2'));
SELECT pg_temp.ok('H9 the law and the platform''s defaults are the platform''s, and every utility reads them',
  (SELECT count(*) >= 4 FROM public.dispute_rules) AND (SELECT count(*) = 2 FROM public.dispute_platform_defaults));
RESET ROLE;
-- CASCADE: a plain TRUNCATE of a referenced table is refused by PostgreSQL's own FK check (0A000) before
-- any trigger runs; with CASCADE nothing but the guard stands in the way.
SELECT pg_temp.refuses_at('H10 a dispute record is never truncated, even with CASCADE', 'TRUNCATE public.dispute_events CASCADE', '23001', 'dispute');
SELECT pg_temp.admits('H11 the template''s invariants hold over the three rule tables', $q$SELECT public.assert_rule_table_invariants()$q$);
SELECT pg_temp.admits('H12 tenant isolation holds over the new tables and readers', $q$SELECT public.assert_tenant_isolation_invariants()$q$);
SELECT pg_temp.admits('H13 the retention invariants hold: no new table can be deleted from', $q$SELECT public.assert_no_hard_delete_invariants()$q$);
SELECT pg_temp.admits('H14 the core role invariants still hold', $q$SELECT public.assert_core_role_invariants()$q$);
SELECT pg_temp.ok('H15 the comments say the core decides, not the database',
  (SELECT bool_and(obj_description(t, 'pg_class') ~* 'core')
     FROM unnest(ARRAY['public.dispute_rules'::regclass, 'public.dispute_tariffs'::regclass, 'public.dispute_determinations'::regclass]) t));

-- r2 (Opus N): a superuser load with foreign keys off cannot cross tenants.
SELECT pg_temp.refuses_at('H17 a T2 dispute of T1''s bill, loaded with foreign keys off',
  $q$SET LOCAL session_replication_role = replica;
     INSERT INTO public.disputes (tenant_id, customer_id, invoice_id, subject, received_on, channel)
     VALUES ('00000000-0000-4000-8000-0000000025a2', '00000000-0000-4000-8000-0000000025c5', '00000000-0000-4000-8000-000000002501', 'calculation', DATE '2026-03-12', 'written')$q$,
  '23503', 'disputes_invoice_fkey');
-- r2 (Fable S4): -25's own guard invariant.
-- r2 (Fable S3; lesson seal-pattern-owner-roles): the status move is tally_dispute's.
SELECT pg_temp.ok('H18 the status move is a pinned definer owned by tally_dispute, a NOLOGIN role with no BYPASSRLS',
  (SELECT p.prosecdef AND pg_get_userbyid(p.proowner) = 'tally_dispute' FROM pg_proc p WHERE p.oid = 'public.dispute_move_status()'::regprocedure)
  AND (SELECT NOT rolcanlogin AND NOT rolbypassrls AND NOT rolsuper FROM pg_roles WHERE rolname = 'tally_dispute'));
SELECT pg_temp.admits('H18b the seal invariant holds, tally_dispute among its roles', $q$SELECT public.assert_seal_role_invariants()$q$);
SELECT pg_temp.refuses_at('H18c … and catches a grant beyond the move''s (UPDATE of a dispute''s subject)',
  $q$GRANT UPDATE (subject) ON public.disputes TO tally_dispute; SELECT public.assert_seal_role_invariants()$q$, '0LP01', 'tally_dispute holds other privileges');
SELECT pg_temp.refuses_at('H18d a move made by anyone but tally_dispute is refused, even one naming its resolution (the move''s trigger switched off)',
  $q$SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000025b3', true);
     ALTER TABLE public.dispute_events DISABLE TRIGGER z_dispute_move_status;
     INSERT INTO public.dispute_events (id, tenant_id, dispute_id, event_type, occurred_on, outcome)
     VALUES ('00000000-0000-4000-8000-000000002565', '00000000-0000-4000-8000-0000000025a3', '00000000-0000-4000-8000-000000002539', 'resolved', DATE '2026-11-24', 'sustained');
     UPDATE public.disputes d SET status = 'resolved', status_cause_id = e.id, status_recorded_at = e.created_at
       FROM public.dispute_events e WHERE e.id = '00000000-0000-4000-8000-000000002565' AND d.id = '00000000-0000-4000-8000-000000002539'$q$, '23514', '[D1g]');
SELECT pg_temp.admits('H16 -25''s guard invariant holds as built', $q$SELECT public.assert_dispute_guard_invariants()$q$);
SELECT pg_temp.refuses_at('H16a … and catches a guard switched off',
  $q$ALTER TABLE public.dispute_events DISABLE TRIGGER z_enforce_dispute_nothing_after_close; SELECT public.assert_dispute_guard_invariants()$q$,
  '0LP01', 'z_enforce_dispute_nothing_after_close');
SELECT pg_temp.refuses_at('H16b … an UPDATE granted on disputes (an unlisted column grant; r2: the status columns are tally_dispute''s, listed)',
  $q$GRANT UPDATE (subject) ON public.disputes TO tally_app; SELECT public.assert_dispute_guard_invariants()$q$, '0LP01', 'column grants');
SELECT pg_temp.refuses_at('H16b2 … or a listed column grant revoked (the status move''s on status_recorded_at)',
  $q$REVOKE UPDATE (status_recorded_at) ON public.disputes FROM tally_dispute; SELECT public.assert_dispute_guard_invariants()$q$, '0LP01', 'column grants');
SELECT pg_temp.refuses_at('H16b3 … or an UPDATE granted on the record sequence that orders "nothing after the resolution" (r3, Fable S2)',
  $q$GRANT UPDATE ON SEQUENCE public.dispute_record_seq TO tally_app; SELECT public.assert_dispute_guard_invariants()$q$, '0LP01', 'grants or row security');
SELECT pg_temp.refuses_at('H16b4 … or the record sequence set to cycle (r4, Fable N8: its settings are pinned)',
  $q$ALTER SEQUENCE public.dispute_record_seq CYCLE; SELECT public.assert_dispute_guard_invariants()$q$, '0LP01', 'a sequence''s settings');
SELECT pg_temp.refuses_at('H16c … a guard''s body replaced',
  $q$CREATE OR REPLACE FUNCTION public.enforce_dispute_reading_released() RETURNS trigger LANGUAGE plpgsql SET search_path = public, pg_temp AS $b$ BEGIN RETURN NULL; END $b$;
     SELECT public.assert_dispute_guard_invariants()$q$, '0LP01', 'enforce_dispute_reading_released');
SELECT pg_temp.refuses_at('H16d … the status move''s owner changed',
  $q$ALTER FUNCTION public.dispute_move_status() OWNER TO tally_core; SELECT public.assert_dispute_guard_invariants()$q$, '0LP01', 'owner');
SELECT pg_temp.refuses_at('H16e … a constraint dropped',
  $q$ALTER TABLE public.dispute_amounts DROP CONSTRAINT dispute_amounts_created_by_fkey; SELECT public.assert_dispute_guard_invariants()$q$, '0LP01', 'dispute_amounts_created_by_fkey');
SELECT pg_temp.refuses_at('H16f … a second policy',
  $q$CREATE POLICY wide ON public.disputes USING (true); SELECT public.assert_dispute_guard_invariants()$q$, '0LP01', 'unlisted');
SELECT pg_temp.refuses_at('H16f2 … a listed policy dropped',
  $q$DROP POLICY tenant_isolation ON public.disputes; SELECT public.assert_dispute_guard_invariants()$q$, '0LP01', 'disputes | tenant_isolation | ALL');
SELECT pg_temp.refuses_at('H16g … a NOT NULL dropped',
  $q$ALTER TABLE public.disputes ALTER COLUMN received_on DROP NOT NULL; SELECT public.assert_dispute_guard_invariants()$q$, '0LP01', 'lost NOT NULL');

SELECT 'battery-25: all checks passed' AS result;
ROLLBACK;
