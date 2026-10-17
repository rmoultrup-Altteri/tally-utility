-- ============================================================================
-- BATTERY v5.4.2-23 — cash: reversals, positions, payment application,
-- credits from overpayment (2026-10-16)
-- Run: psql -U tally -d <db-with-patch> -v ON_ERROR_STOP=1 -f battery-23.sql
-- One transaction, rolled back. Fixtures as the owner; every guard the
-- application meets is exercised as tally_app under app.user_id.
-- Each row names its requirement in
-- application/wave2-build-2026-10-15/v5.4.2-23-design.md.
--
--   X  reversals (X1-X4)          M  positions, write-once, status (M1-M4)
--   A  application (A1-A6)        C  overpayment credits (C1, C2)
--   T  the within-bill order (A5) F  the freeze on applications
--   I  invariants
-- What one transaction cannot show (READ COMMITTED pins, recorded order
-- across transactions, two writers on one source or line) is in
-- races/cash-23.sh.
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
-- snap(): a calculation snapshot of a bill at (p_valid, p_rec), its lines as they are.
CREATE FUNCTION pg_temp.snap(p_inv uuid, p_valid date, p_rec timestamptz) RETURNS void LANGUAGE plpgsql AS $$
DECLARE i public.invoices%ROWTYPE;
BEGIN
  SELECT * INTO i FROM public.invoices WHERE id = p_inv;
  INSERT INTO public.invoice_calculation_snapshots
    (tenant_id, invoice_id, billing_run_id, valid_at, recorded_at, snapshot_schema_version, formula_version,
     rate_inputs, gas_factors, wna_inputs, tax_inputs, read_inputs, customer_inputs, period_inputs, line_items)
  VALUES (i.tenant_id, i.id, i.billing_run_id, p_valid, p_rec, 'v1', 'bat23',
     '{"rate_schedule_id":null,"rate_schedule_version_id":null,"rate_schedule_code":null,"customer_type":null,"partial_period_policy":null,"items":[]}',
     '{"pga_factor":null,"btu_factor":null,"pressure_factor":null,"temperature_factor":null,"meter_multiplier":null,"factor_stack_intermediates":{}}',
     '{"applied":false}', '{"jurisdictions":[],"exemptions":[],"franchise_fees":[]}', '{"reads":[]}',
     jsonb_build_object('customer_id', i.customer_id, 'customer_class', null, 'location_id', i.location_id, 'premise_zones', '{}'::jsonb),
     jsonb_build_object('period_start', i.period_start, 'period_end', i.period_end, 'days_in_period', i.period_end - i.period_start + 1, 'proration_policy', null),
     (SELECT coalesce(jsonb_agg(jsonb_build_object('invoice_line_item_id', l.id, 'charge_type', l.charge_type, 'amount', l.amount)), '[]'::jsonb)
        FROM public.invoice_line_items l WHERE l.invoice_id = i.id));
END $$;
GRANT EXECUTE ON FUNCTION pg_temp.refuses_at(text, text, text, text), pg_temp.ok(text, boolean), pg_temp.admits(text, text) TO tally_app, tally_core;

-- ------------------------------------------------------------------ fixtures
-- T1 (…23a1), T2 (…23a2). Ids: b users, c customers, d locations, 01-09
-- bills, 11-1f lines, 41-4f applications, 51-59 approvals, 61-6f payments,
-- 71-79 credits, 81-9f ledger, ab the tariff.
INSERT INTO public.tenants (id, name, slug) VALUES
  ('00000000-0000-4000-8000-0000000023a1', 'T1 City Gas', 'bat23-t1'),
  ('00000000-0000-4000-8000-0000000023a2', 'T2 Gasco', 'bat23-t2');
INSERT INTO public.users (id, tenant_id, display_name, email, role, is_active) VALUES
  ('00000000-0000-4000-8000-0000000023b1', '00000000-0000-4000-8000-0000000023a1', 'Op1', 'op1@bat23.test', 'operator', true),
  ('00000000-0000-4000-8000-0000000023b2', '00000000-0000-4000-8000-0000000023a2', 'Op2', 'op2@bat23.test', 'operator', true);
INSERT INTO public.customers (id, tenant_id, customer_number, customer_type) VALUES
  ('00000000-0000-4000-8000-0000000023c1', '00000000-0000-4000-8000-0000000023a1', 'B23-C1', 'residential'),
  ('00000000-0000-4000-8000-0000000023c2', '00000000-0000-4000-8000-0000000023a1', 'B23-C2', 'residential'),
  ('00000000-0000-4000-8000-0000000023c9', '00000000-0000-4000-8000-0000000023a2', 'B23-C9', 'residential');
INSERT INTO public.service_locations (id, tenant_id, customer_id, location_number, address_line1, city, state, zip) VALUES
  ('00000000-0000-4000-8000-0000000023d1', '00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c1', 'L1', '1 Main', 'Austin', 'TX', '78701'),
  ('00000000-0000-4000-8000-0000000023d2', '00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c2', 'L2', '2 Main', 'Austin', 'TX', '78701');
-- The utility's profile (a city-owned gas distribution system in Texas): the
-- tariff is measured against the Texas law rows -23 seeds.
INSERT INTO public.places (id, kind_code, state_code, place_code, name, parent_place_id, effective_from, source_note)
SELECT '00000000-0000-4000-8000-0000000023a7', 'municipality', 'TX', 'TX-B23-CITY', 'Battery City 23', s.id, DATE '2000-01-01', 'battery-23 fixture'
  FROM public.places s WHERE s.kind_code = 'state' AND s.state_code = 'TX';
INSERT INTO public.utility_service_profiles (tenant_id, service_type, system_kind, state_code, owner_type, commission_jurisdiction,
                                             owning_place_id, effective_from, evidence_reference, evidence_date)
VALUES ('00000000-0000-4000-8000-0000000023a1', 'gas', 'distribution', 'TX', 'municipal', false,
        '00000000-0000-4000-8000-0000000023a7', DATE '2000-01-01', 'Battery City charter', DATE '2000-01-01');

-- bill(): an issued bill of C1 or C2 dated March 1 with three lines: gas
-- service 60 (regulated), an add-on 40 (unregulated), a credit -10.
CREATE FUNCTION pg_temp.bill(p_id uuid, p_num text, p_customer uuid, p_loc uuid, p_l1 uuid, p_l2 uuid, p_l3 uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO public.invoices (id, tenant_id, invoice_number, customer_id, location_id, invoice_date, billing_period, period_start, period_end, due_date, amount_due)
  VALUES (p_id, '00000000-0000-4000-8000-0000000023a1', p_num, p_customer, p_loc, DATE '2026-03-01', '2026-02', DATE '2026-02-01', DATE '2026-02-28', DATE '2026-03-20', 90.00);
  INSERT INTO public.invoice_line_items (id, tenant_id, invoice_id, line_order, service_type, charge_type, description, amount, rate, regulatory_class) VALUES
    (p_l1, '00000000-0000-4000-8000-0000000023a1', p_id, 0, 'gas', 'base_charge', 'Gas service', 60.00, 60.00, 'regulated'),
    (p_l2, '00000000-0000-4000-8000-0000000023a1', p_id, 1, 'general', 'misc', 'Appliance plan', 40.00, NULL, 'unregulated'),
    (p_l3, '00000000-0000-4000-8000-0000000023a1', p_id, 2, 'gas', 'credit', 'Goodwill', -10.00, NULL, 'regulated');
  PERFORM pg_temp.snap(p_id, DATE '2026-02-28', now());
  UPDATE public.invoices SET status = 'pending' WHERE id = p_id;
END $$;
SELECT pg_temp.bill('00000000-0000-4000-8000-000000002301', 'B23-I1', '00000000-0000-4000-8000-0000000023c1', '00000000-0000-4000-8000-0000000023d1',
                    '00000000-0000-4000-8000-000000002311', '00000000-0000-4000-8000-000000002312', '00000000-0000-4000-8000-000000002313');
SELECT pg_temp.bill('00000000-0000-4000-8000-000000002302', 'B23-I2', '00000000-0000-4000-8000-0000000023c1', '00000000-0000-4000-8000-0000000023d1',
                    '00000000-0000-4000-8000-000000002314', '00000000-0000-4000-8000-000000002315', '00000000-0000-4000-8000-000000002316');
SELECT pg_temp.bill('00000000-0000-4000-8000-000000002303', 'B23-I3', '00000000-0000-4000-8000-0000000023c2', '00000000-0000-4000-8000-0000000023d2',
                    '00000000-0000-4000-8000-000000002317', '00000000-0000-4000-8000-000000002318', '00000000-0000-4000-8000-000000002319');
-- A draft bill of C1 (never issued).
INSERT INTO public.invoices (id, tenant_id, invoice_number, customer_id, location_id, invoice_date, billing_period, period_start, period_end, due_date, amount_due)
VALUES ('00000000-0000-4000-8000-000000002304', '00000000-0000-4000-8000-0000000023a1', 'B23-I4', '00000000-0000-4000-8000-0000000023c1', '00000000-0000-4000-8000-0000000023d1',
        DATE '2026-03-01', '2026-02', DATE '2026-02-01', DATE '2026-02-28', DATE '2026-03-20', 25.00);
INSERT INTO public.invoice_line_items (id, tenant_id, invoice_id, service_type, charge_type, description, amount, rate, regulatory_class) VALUES
  ('00000000-0000-4000-8000-00000000231a', '00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-000000002304', 'gas', 'base_charge', 'Draft line', 25.00, 25.00, 'regulated');


-- ============================================================== T the within-bill order (A5)
SELECT pg_temp.ok('T1 Texas gas has two law rows for distribution systems, both delegating to the utility (K-05)',
  (SELECT count(*) = 2 AND bool_and(terms ->> 'governs' = 'delegated_to_utility')
     FROM public.payment_allocation_rules WHERE state_code = 'TX' AND service_type = 'gas'));
SET ROLE tally_app;
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000023b1', true);
SELECT pg_temp.refuses_at('T2 a tariff order that leaves a charge type out (K-07: no assumed default)',
  $q$INSERT INTO public.payment_allocation_tariffs (tenant_id, state_code, service_type, system_kind, effective_from, tariff_reference, terms_kind, terms_version, terms_source)
     VALUES ('00000000-0000-4000-8000-0000000023a1', 'TX', 'gas', 'distribution', DATE '2026-01-01', 'City tariff 7', 'payment_allocation_tariff', 1,
             '{"citation": "City tariff 7", "within_bill": {"strategy": "charge_type_order", "version": 1, "regulated": ["base_charge"], "unregulated": ["misc"]}}')$q$,
  '23514', 'every bill-line charge type exactly once');
SELECT pg_temp.refuses_at('T3 a charge type in both lists',
  $q$INSERT INTO public.payment_allocation_tariffs (tenant_id, state_code, service_type, system_kind, effective_from, tariff_reference, terms_kind, terms_version, terms_source)
     VALUES ('00000000-0000-4000-8000-0000000023a1', 'TX', 'gas', 'distribution', DATE '2026-01-01', 'City tariff 7', 'payment_allocation_tariff', 1,
             '{"citation": "City tariff 7", "within_bill": {"strategy": "charge_type_order", "version": 1, "regulated": ["base_charge", "usage_charge", "surcharge", "tax", "late_fee", "deposit", "credit", "adjustment", "penalty", "minimum_bill_adjustment", "consolidated_summary", "misc"], "unregulated": ["adhoc", "misc"]}}')$q$,
  '23514', 'listed twice');
SELECT pg_temp.refuses_at('T4 the shape admits no other class order: an "order" list in place of the two lists is not a document',
  $q$INSERT INTO public.payment_allocation_tariffs (tenant_id, state_code, service_type, system_kind, effective_from, tariff_reference, terms_kind, terms_version, terms_source)
     VALUES ('00000000-0000-4000-8000-0000000023a1', 'TX', 'gas', 'distribution', DATE '2026-01-01', 'City tariff 7', 'payment_allocation_tariff', 1,
             '{"citation": "City tariff 7", "within_bill": {"strategy": "charge_type_order", "version": 1, "order": ["unregulated", "regulated"], "regulated": [], "unregulated": []}}')$q$,
  '23514', 'payment_allocation_tariff');
SELECT pg_temp.admits('T5 the utility''s own complete order, regulated first',
  $q$INSERT INTO public.payment_allocation_tariffs (id, tenant_id, state_code, service_type, system_kind, effective_from, tariff_reference, terms_kind, terms_version, terms_source)
     VALUES ('00000000-0000-4000-8000-0000000023ab', '00000000-0000-4000-8000-0000000023a1', 'TX', 'gas', 'distribution', DATE '2026-01-01', 'City tariff 7', 'payment_allocation_tariff', 1,
             '{"citation": "City tariff 7", "within_bill": {"strategy": "charge_type_order", "version": 1, "regulated": ["base_charge", "usage_charge", "surcharge", "minimum_bill_adjustment", "tax", "late_fee", "penalty", "deposit", "adjustment", "credit", "consolidated_summary"], "unregulated": ["adhoc", "misc"]}}')$q$);
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000023b2', true);
SELECT pg_temp.refuses_at('T6 another utility writes no tariff for T1',
  $q$INSERT INTO public.payment_allocation_tariffs (tenant_id, state_code, service_type, system_kind, effective_from, tariff_reference, terms_kind, terms_version, terms_source)
     VALUES ('00000000-0000-4000-8000-0000000023a1', 'TX', 'gas', 'distribution', DATE '2027-01-01', 'x', 'payment_allocation_tariff', 1,
             '{"citation": "x", "within_bill": {"strategy": "charge_type_order", "version": 1, "regulated": ["base_charge", "usage_charge", "surcharge", "minimum_bill_adjustment", "tax", "late_fee", "penalty", "deposit", "adjustment", "credit", "consolidated_summary"], "unregulated": ["adhoc", "misc"]}}')$q$,
  '42501', 'row-level security');
RESET ROLE;


-- ============================================================== payments and credits
SET ROLE tally_app;
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000023b1', true);
-- P61: C1 pays 100 (posted). P62: C1, pending. P63: C1's deposit. P64: an
-- agency pays 50 for C1, restricted to I2's add-on (line 15). P65: C2 pays 30.
INSERT INTO public.payments (id, tenant_id, payment_number, customer_id, payment_date, amount, payment_method, effective_date, effective_date_method, status,
                             is_deposit, payer_class, restricted_to_invoice_id, restricted_to_line_item_id) VALUES
  ('00000000-0000-4000-8000-000000002361', '00000000-0000-4000-8000-0000000023a1', 'B23-P1', '00000000-0000-4000-8000-0000000023c1', DATE '2026-03-05', 100, 'check', DATE '2026-03-05', 'postmark', 'posted', false, 'customer', NULL, NULL),
  ('00000000-0000-4000-8000-000000002362', '00000000-0000-4000-8000-0000000023a1', 'B23-P2', '00000000-0000-4000-8000-0000000023c1', DATE '2026-03-05', 20, 'ach', NULL, NULL, 'pending', false, 'customer', NULL, NULL),
  ('00000000-0000-4000-8000-000000002363', '00000000-0000-4000-8000-0000000023a1', 'B23-P3', '00000000-0000-4000-8000-0000000023c1', DATE '2026-03-05', 75, 'check', DATE '2026-03-05', 'postmark', 'posted', true, 'customer', NULL, NULL),
  ('00000000-0000-4000-8000-000000002364', '00000000-0000-4000-8000-0000000023a1', 'B23-P4', '00000000-0000-4000-8000-0000000023c1', DATE '2026-03-06', 50, 'check', DATE '2026-03-06', 'postmark', 'posted', false, 'agency',
   '00000000-0000-4000-8000-000000002302', '00000000-0000-4000-8000-000000002315'),
  ('00000000-0000-4000-8000-000000002365', '00000000-0000-4000-8000-0000000023a1', 'B23-P5', '00000000-0000-4000-8000-0000000023c2', DATE '2026-03-05', 30, 'check', DATE '2026-03-05', 'postmark', 'posted', false, 'customer', NULL, NULL);
-- K71: a goodwill credit of 25 for C1.
INSERT INTO public.customer_credits (id, tenant_id, customer_id, origin_type, original_amount, issued_date)
VALUES ('00000000-0000-4000-8000-000000002371', '00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c1', 'goodwill', 25, DATE '2026-03-02');
RESET ROLE;


-- ============================================================== A6 the restriction
SET ROLE tally_app;
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000023b1', true);
SELECT pg_temp.refuses_at('A6 only an agency payment carries a restriction',
  $q$INSERT INTO public.payments (tenant_id, payment_number, customer_id, payment_date, amount, payment_method, effective_date, effective_date_method, restricted_to_invoice_id)
     VALUES ('00000000-0000-4000-8000-0000000023a1', 'B23-PX', '00000000-0000-4000-8000-0000000023c1', DATE '2026-03-05', 10, 'check', DATE '2026-03-05', 'postmark', '00000000-0000-4000-8000-000000002302')$q$,
  '23514', 'payments_restriction_agency_check');
SELECT pg_temp.refuses_at('A6b a restricted line is a line of the restricted bill',
  $q$INSERT INTO public.payments (tenant_id, payment_number, customer_id, payment_date, amount, payment_method, effective_date, effective_date_method, payer_class, restricted_to_invoice_id, restricted_to_line_item_id)
     VALUES ('00000000-0000-4000-8000-0000000023a1', 'B23-PX', '00000000-0000-4000-8000-0000000023c1', DATE '2026-03-05', 10, 'check', DATE '2026-03-05', 'postmark', 'agency',
             '00000000-0000-4000-8000-000000002302', '00000000-0000-4000-8000-000000002311')$q$,
  '23503', 'payments_restricted_line_fkey');
SELECT pg_temp.refuses_at('A6c a restricted bill is the payment''s customer''s',
  $q$INSERT INTO public.payments (tenant_id, payment_number, customer_id, payment_date, amount, payment_method, effective_date, effective_date_method, payer_class, restricted_to_invoice_id)
     VALUES ('00000000-0000-4000-8000-0000000023a1', 'B23-PX', '00000000-0000-4000-8000-0000000023c1', DATE '2026-03-05', 10, 'check', DATE '2026-03-05', 'postmark', 'agency',
             '00000000-0000-4000-8000-000000002303')$q$,
  '23503', 'payments_restricted_invoice_fkey');
RESET ROLE;


-- ============================================================== A application
SET ROLE tally_app;
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000023b1', true);
SELECT pg_temp.admits('A1 an application to a bill line, oldest first, citing the tariff in force',
  $q$INSERT INTO public.invoice_applications (id, tenant_id, customer_id, invoice_id, invoice_line_item_id, payment_id, amount, applied_on, basis, allocation_tariff_id)
     VALUES ('00000000-0000-4000-8000-000000002341', '00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c1', '00000000-0000-4000-8000-000000002301',
             '00000000-0000-4000-8000-000000002311', '00000000-0000-4000-8000-000000002361', 60, DATE '2026-03-05', 'oldest_first', '00000000-0000-4000-8000-0000000023ab')$q$);
SELECT pg_temp.refuses_at('A1b a line of another bill',
  $q$INSERT INTO public.invoice_applications (tenant_id, customer_id, invoice_id, invoice_line_item_id, payment_id, amount, applied_on, basis, allocation_tariff_id)
     VALUES ('00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c1', '00000000-0000-4000-8000-000000002301',
             '00000000-0000-4000-8000-000000002314', '00000000-0000-4000-8000-000000002361', 1, DATE '2026-03-05', 'oldest_first', '00000000-0000-4000-8000-0000000023ab')$q$,
  '23503', 'invoice_applications_line_fkey');
SELECT pg_temp.refuses_at('A1c another customer''s bill',
  $q$INSERT INTO public.invoice_applications (tenant_id, customer_id, invoice_id, invoice_line_item_id, payment_id, amount, applied_on, basis, allocation_tariff_id)
     VALUES ('00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c1', '00000000-0000-4000-8000-000000002303',
             '00000000-0000-4000-8000-000000002317', '00000000-0000-4000-8000-000000002361', 1, DATE '2026-03-05', 'oldest_first', '00000000-0000-4000-8000-0000000023ab')$q$,
  '23503', 'invoice_applications_invoice_fkey');
SELECT pg_temp.refuses_at('A1d one source, not two',
  $q$INSERT INTO public.invoice_applications (tenant_id, customer_id, invoice_id, invoice_line_item_id, payment_id, customer_credit_id, amount, applied_on, basis, allocation_tariff_id)
     VALUES ('00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c1', '00000000-0000-4000-8000-000000002301', '00000000-0000-4000-8000-000000002312',
             '00000000-0000-4000-8000-000000002361', '00000000-0000-4000-8000-000000002371', 1, DATE '2026-03-05', 'oldest_first', '00000000-0000-4000-8000-0000000023ab')$q$,
  '23514', 'invoice_applications_one_source_check');
-- A2: add-only.
SELECT pg_temp.refuses_at('A2 an application is never edited',
  $q$UPDATE public.invoice_applications SET amount = 50 WHERE id = '00000000-0000-4000-8000-000000002341'$q$, '42501', 'permission denied');
SELECT pg_temp.refuses_at('A2b nor deleted',
  $q$DELETE FROM public.invoice_applications WHERE id = '00000000-0000-4000-8000-000000002341'$q$, '42501', 'permission denied');
SELECT pg_temp.refuses_at('A2c an undo says why and who',
  $q$INSERT INTO public.invoice_applications (tenant_id, customer_id, invoice_id, invoice_line_item_id, payment_id, amount, applied_on, basis, undoes_application_id)
     VALUES ('00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c1', '00000000-0000-4000-8000-000000002301', '00000000-0000-4000-8000-000000002311',
             '00000000-0000-4000-8000-000000002361', -10, DATE '2026-03-06', 'undo', '00000000-0000-4000-8000-000000002341')$q$,
  '23514', 'invoice_applications_operator_check');
SELECT pg_temp.refuses_at('A2d an undo takes back at most the application',
  $q$INSERT INTO public.invoice_applications (tenant_id, customer_id, invoice_id, invoice_line_item_id, payment_id, amount, applied_on, basis, undoes_application_id, applied_by, reason)
     VALUES ('00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c1', '00000000-0000-4000-8000-000000002301', '00000000-0000-4000-8000-000000002311',
             '00000000-0000-4000-8000-000000002361', -61, DATE '2026-03-06', 'undo', '00000000-0000-4000-8000-000000002341', '00000000-0000-4000-8000-0000000023b1', 'keyed wrong')$q$,
  '23514', 'A2 cap');
SELECT pg_temp.refuses_at('A2e an undo is dated on or after what it undoes',
  $q$INSERT INTO public.invoice_applications (tenant_id, customer_id, invoice_id, invoice_line_item_id, payment_id, amount, applied_on, basis, undoes_application_id, applied_by, reason)
     VALUES ('00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c1', '00000000-0000-4000-8000-000000002301', '00000000-0000-4000-8000-000000002311',
             '00000000-0000-4000-8000-000000002361', -10, DATE '2026-03-04', 'undo', '00000000-0000-4000-8000-000000002341', '00000000-0000-4000-8000-0000000023b1', 'keyed wrong')$q$,
  '23514', 'dated on or after it');
SELECT pg_temp.refuses_at('A2f an undo is of the same source',
  $q$INSERT INTO public.invoice_applications (tenant_id, customer_id, invoice_id, invoice_line_item_id, customer_credit_id, amount, applied_on, basis, undoes_application_id, applied_by, reason)
     VALUES ('00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c1', '00000000-0000-4000-8000-000000002301', '00000000-0000-4000-8000-000000002311',
             '00000000-0000-4000-8000-000000002371', -10, DATE '2026-03-06', 'undo', '00000000-0000-4000-8000-000000002341', '00000000-0000-4000-8000-0000000023b1', 'keyed wrong')$q$,
  '23514', 'of the same source and line');
SELECT pg_temp.admits('A2g a partial undo, with its reason and user',
  $q$INSERT INTO public.invoice_applications (id, tenant_id, customer_id, invoice_id, invoice_line_item_id, payment_id, amount, applied_on, basis, undoes_application_id, applied_by, reason)
     VALUES ('00000000-0000-4000-8000-000000002342', '00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c1', '00000000-0000-4000-8000-000000002301', '00000000-0000-4000-8000-000000002311',
             '00000000-0000-4000-8000-000000002361', -10, DATE '2026-03-06', 'undo', '00000000-0000-4000-8000-000000002341', '00000000-0000-4000-8000-0000000023b1', 'keyed wrong')$q$);
SELECT pg_temp.refuses_at('A2h an undo is never undone (re-apply instead)',
  $q$INSERT INTO public.invoice_applications (tenant_id, customer_id, invoice_id, invoice_line_item_id, payment_id, amount, applied_on, basis, undoes_application_id, applied_by, reason)
     VALUES ('00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c1', '00000000-0000-4000-8000-000000002301', '00000000-0000-4000-8000-000000002311',
             '00000000-0000-4000-8000-000000002361', 10, DATE '2026-03-06', 'undo', '00000000-0000-4000-8000-000000002342', '00000000-0000-4000-8000-0000000023b1', 'x')$q$,
  '23514', 'invoice_applications_sign_check');
-- A3: caps and sources.
SELECT pg_temp.refuses_at('A3 a line takes no more than it is (50 applied of 60, then 11)',
  $q$INSERT INTO public.invoice_applications (tenant_id, customer_id, invoice_id, invoice_line_item_id, payment_id, amount, applied_on, basis, allocation_tariff_id)
     VALUES ('00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c1', '00000000-0000-4000-8000-000000002301', '00000000-0000-4000-8000-000000002311',
             '00000000-0000-4000-8000-000000002361', 11, DATE '2026-03-07', 'oldest_first', '00000000-0000-4000-8000-0000000023ab')$q$,
  '23514', 'more than the line''s');
SELECT pg_temp.admits('A3b and exactly what is left (10)',
  $q$INSERT INTO public.invoice_applications (tenant_id, customer_id, invoice_id, invoice_line_item_id, payment_id, amount, applied_on, basis, allocation_tariff_id)
     VALUES ('00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c1', '00000000-0000-4000-8000-000000002301', '00000000-0000-4000-8000-000000002311',
             '00000000-0000-4000-8000-000000002361', 10, DATE '2026-03-07', 'oldest_first', '00000000-0000-4000-8000-0000000023ab')$q$);
SELECT pg_temp.refuses_at('A3c a credit line takes no money (the bill''s own netting)',
  $q$INSERT INTO public.invoice_applications (tenant_id, customer_id, invoice_id, invoice_line_item_id, payment_id, amount, applied_on, basis, allocation_tariff_id)
     VALUES ('00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c1', '00000000-0000-4000-8000-000000002301', '00000000-0000-4000-8000-000000002313',
             '00000000-0000-4000-8000-000000002361', 1, DATE '2026-03-07', 'oldest_first', '00000000-0000-4000-8000-0000000023ab')$q$,
  '23514', 'only a positive line takes money');
SELECT pg_temp.admits('A3d the add-on line from the same payment (40: 100 of 100 drawn)',
  $q$INSERT INTO public.invoice_applications (tenant_id, customer_id, invoice_id, invoice_line_item_id, payment_id, amount, applied_on, basis, allocation_tariff_id)
     VALUES ('00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c1', '00000000-0000-4000-8000-000000002301', '00000000-0000-4000-8000-000000002312',
             '00000000-0000-4000-8000-000000002361', 40, DATE '2026-03-07', 'oldest_first', '00000000-0000-4000-8000-0000000023ab')$q$);
SELECT pg_temp.refuses_at('A3e a payment pays no more than it is: 1 more of P1''s 100',
  $q$INSERT INTO public.invoice_applications (tenant_id, customer_id, invoice_id, invoice_line_item_id, payment_id, amount, applied_on, basis, allocation_tariff_id)
     VALUES ('00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c1', '00000000-0000-4000-8000-000000002302', '00000000-0000-4000-8000-000000002314',
             '00000000-0000-4000-8000-000000002361', 1, DATE '2026-03-07', 'oldest_first', '00000000-0000-4000-8000-0000000023ab')$q$,
  '23514', 'more than its 100');
SELECT pg_temp.refuses_at('A3f a pending payment pays nothing',
  $q$INSERT INTO public.invoice_applications (tenant_id, customer_id, invoice_id, invoice_line_item_id, payment_id, amount, applied_on, basis, allocation_tariff_id)
     VALUES ('00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c1', '00000000-0000-4000-8000-000000002302', '00000000-0000-4000-8000-000000002314',
             '00000000-0000-4000-8000-000000002362', 1, DATE '2026-03-07', 'oldest_first', '00000000-0000-4000-8000-0000000023ab')$q$,
  '23514', 'from a posted bill payment');
SELECT pg_temp.refuses_at('A3g a deposit pays no bill (K-05)',
  $q$INSERT INTO public.invoice_applications (tenant_id, customer_id, invoice_id, invoice_line_item_id, payment_id, amount, applied_on, basis, allocation_tariff_id)
     VALUES ('00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c1', '00000000-0000-4000-8000-000000002302', '00000000-0000-4000-8000-000000002314',
             '00000000-0000-4000-8000-000000002363', 1, DATE '2026-03-07', 'oldest_first', '00000000-0000-4000-8000-0000000023ab')$q$,
  '23514', 'a deposit');
SELECT pg_temp.refuses_at('A3h a draft bill takes no money',
  $q$INSERT INTO public.invoice_applications (tenant_id, customer_id, invoice_id, invoice_line_item_id, customer_credit_id, amount, applied_on, basis, allocation_tariff_id)
     VALUES ('00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c1', '00000000-0000-4000-8000-000000002304', '00000000-0000-4000-8000-00000000231a',
             '00000000-0000-4000-8000-000000002371', 1, DATE '2026-03-07', 'oldest_first', '00000000-0000-4000-8000-0000000023ab')$q$,
  '23514', 'an issued, unvoided bill');
SELECT pg_temp.refuses_at('A3i money is applied on or after it arrived (credit issued March 2, applied March 1)',
  $q$INSERT INTO public.invoice_applications (tenant_id, customer_id, invoice_id, invoice_line_item_id, customer_credit_id, amount, applied_on, basis, allocation_tariff_id)
     VALUES ('00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c1', '00000000-0000-4000-8000-000000002302', '00000000-0000-4000-8000-000000002314',
             '00000000-0000-4000-8000-000000002371', 1, DATE '2026-03-01', 'oldest_first', '00000000-0000-4000-8000-0000000023ab')$q$,
  '23514', 'on or after both');
SELECT pg_temp.admits('A3j a credit pays a line',
  $q$INSERT INTO public.invoice_applications (id, tenant_id, customer_id, invoice_id, invoice_line_item_id, customer_credit_id, amount, applied_on, basis, allocation_tariff_id)
     VALUES ('00000000-0000-4000-8000-000000002343', '00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c1', '00000000-0000-4000-8000-000000002302', '00000000-0000-4000-8000-000000002314',
             '00000000-0000-4000-8000-000000002371', 25, DATE '2026-03-07', 'oldest_first', '00000000-0000-4000-8000-0000000023ab')$q$);
-- A4: how each application was chosen.
SELECT pg_temp.refuses_at('A4 an operator''s choice says why',
  $q$INSERT INTO public.invoice_applications (tenant_id, customer_id, invoice_id, invoice_line_item_id, payment_id, amount, applied_on, basis, applied_by)
     VALUES ('00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c2', '00000000-0000-4000-8000-000000002303', '00000000-0000-4000-8000-000000002318',
             '00000000-0000-4000-8000-000000002365', 5, DATE '2026-03-07', 'operator_override', '00000000-0000-4000-8000-0000000023b1')$q$,
  '23514', 'invoice_applications_operator_check');
SELECT pg_temp.refuses_at('A4b a rule-chosen application names its tariff',
  $q$INSERT INTO public.invoice_applications (tenant_id, customer_id, invoice_id, invoice_line_item_id, payment_id, amount, applied_on, basis)
     VALUES ('00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c2', '00000000-0000-4000-8000-000000002303', '00000000-0000-4000-8000-000000002317',
             '00000000-0000-4000-8000-000000002365', 5, DATE '2026-03-07', 'oldest_first')$q$,
  '23514', 'invoice_applications_tariff_check');
SELECT pg_temp.refuses_at('A4c the tariff is in force on the application''s date (the row starts January 1, 2026)',
  $q$INSERT INTO public.invoice_applications (tenant_id, customer_id, invoice_id, invoice_line_item_id, payment_id, amount, applied_on, basis, allocation_tariff_id)
     VALUES ('00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c2', '00000000-0000-4000-8000-000000002303', '00000000-0000-4000-8000-000000002317',
             '00000000-0000-4000-8000-000000002365', 5, DATE '2025-12-31', 'oldest_first', '00000000-0000-4000-8000-0000000023ab')$q$,
  '23514', 'on or after both');
SELECT pg_temp.admits('A4d an operator''s choice with a reason and user',
  $q$INSERT INTO public.invoice_applications (tenant_id, customer_id, invoice_id, invoice_line_item_id, payment_id, amount, applied_on, basis, applied_by, reason)
     VALUES ('00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c2', '00000000-0000-4000-8000-000000002303', '00000000-0000-4000-8000-000000002318',
             '00000000-0000-4000-8000-000000002365', 5, DATE '2026-03-07', 'operator_override', '00000000-0000-4000-8000-0000000023b1', 'customer asked at the counter')$q$);
SELECT pg_temp.refuses_at('A4e an unrestricted payment says no restriction',
  $q$INSERT INTO public.invoice_applications (tenant_id, customer_id, invoice_id, invoice_line_item_id, payment_id, amount, applied_on, basis, allocation_tariff_id)
     VALUES ('00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c2', '00000000-0000-4000-8000-000000002303', '00000000-0000-4000-8000-000000002317',
             '00000000-0000-4000-8000-000000002365', 5, DATE '2026-03-07', 'restriction', '00000000-0000-4000-8000-0000000023ab')$q$,
  '23514', 'restriction is a restricted payment');
SELECT pg_temp.refuses_at('A4f a restricted payment is not applied oldest first',
  $q$INSERT INTO public.invoice_applications (tenant_id, customer_id, invoice_id, invoice_line_item_id, payment_id, amount, applied_on, basis, allocation_tariff_id)
     VALUES ('00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c1', '00000000-0000-4000-8000-000000002302', '00000000-0000-4000-8000-000000002315',
             '00000000-0000-4000-8000-000000002364', 5, DATE '2026-03-07', 'oldest_first', '00000000-0000-4000-8000-0000000023ab')$q$,
  '23514', 'restriction is a restricted payment');
SELECT pg_temp.admits('A4g the agency''s money goes to its target, the add-on (D7-1 b)',
  $q$INSERT INTO public.invoice_applications (tenant_id, customer_id, invoice_id, invoice_line_item_id, payment_id, amount, applied_on, basis, allocation_tariff_id)
     VALUES ('00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c1', '00000000-0000-4000-8000-000000002302', '00000000-0000-4000-8000-000000002315',
             '00000000-0000-4000-8000-000000002364', 10, DATE '2026-03-07', 'restriction', '00000000-0000-4000-8000-0000000023ab')$q$);
SELECT pg_temp.admits('A4h or to gas service ahead of the unregulated target, said so (CI-050''s floor; Kyle to rule which wins)',
  $q$INSERT INTO public.invoice_applications (tenant_id, customer_id, invoice_id, invoice_line_item_id, payment_id, amount, applied_on, basis, allocation_tariff_id)
     VALUES ('00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c1', '00000000-0000-4000-8000-000000002302', '00000000-0000-4000-8000-000000002314',
             '00000000-0000-4000-8000-000000002364', 20, DATE '2026-03-07', 'floor_over_restriction', '00000000-0000-4000-8000-0000000023ab')$q$);
SELECT pg_temp.refuses_at('A4i the floor takes a regulated line only (the add-on of I1 is not one)',
  $q$INSERT INTO public.invoice_applications (tenant_id, customer_id, invoice_id, invoice_line_item_id, payment_id, amount, applied_on, basis, allocation_tariff_id)
     VALUES ('00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c1', '00000000-0000-4000-8000-000000002301', '00000000-0000-4000-8000-000000002312',
             '00000000-0000-4000-8000-000000002364', 1, DATE '2026-03-07', 'floor_over_restriction', '00000000-0000-4000-8000-0000000023ab')$q$,
  '23514', 'floor_over_restriction a regulated line');
RESET ROLE;
SELECT pg_temp.ok('A5 every application to I1''s gas line is visible on the line: 60 + 10 - 10 = 60 applied, nothing open',
  (SELECT applied = 60 AND open = 0 FROM public.invoice_line_position_as_of('00000000-0000-4000-8000-000000002311', DATE '2026-12-31', clock_timestamp())));


-- ============================================================== M positions, write-once, status
SELECT pg_temp.ok('M1 the counters are gone',
  NOT EXISTS (SELECT 1 FROM information_schema.columns
               WHERE table_schema = 'public'
                 AND (table_name, column_name) IN (('payments', 'applied_amount'), ('payments', 'unapplied_amount'), ('payments', 'deposit_status'),
                                                   ('customer_credits', 'applied_amount'), ('customer_credits', 'remaining_amount'),
                                                   ('invoices', 'amount_paid'), ('invoices', 'balance'))));
SELECT pg_temp.ok('M1b P1''s position: 100 applied (60 - 10 + 10 + 40), nothing left',
  (SELECT amount = 100 AND applied = 100 AND credited = 0 AND refunded = 0 AND remaining = 0
     FROM public.payment_position_as_of('00000000-0000-4000-8000-000000002361', DATE '2026-12-31', clock_timestamp())));
SELECT pg_temp.ok('M1c by the money date: on March 6, P1 had paid 50 (60 less the undo)',
  (SELECT applied = 50 AND remaining = 50 FROM public.payment_position_as_of('00000000-0000-4000-8000-000000002361', DATE '2026-03-06', clock_timestamp())));
SELECT pg_temp.ok('M1d before the payment''s date there is no position',
  NOT EXISTS (SELECT 1 FROM public.payment_position_as_of('00000000-0000-4000-8000-000000002361', DATE '2026-03-04', clock_timestamp())));
SELECT pg_temp.refuses_at('M1e a position is read at given coordinates (no live fallback)',
  $q$SELECT * FROM public.payment_position_as_of('00000000-0000-4000-8000-000000002361', NULL, clock_timestamp())$q$,
  '22004', 'both given');
SELECT pg_temp.ok('M1f K71''s position: 25 applied, nothing left; I2''s line 14 has 25 + 20 applied of 60',
  (SELECT remaining = 0 FROM public.customer_credit_position_as_of('00000000-0000-4000-8000-000000002371', DATE '2026-12-31', clock_timestamp()))
  AND (SELECT applied = 45 AND open = 15 FROM public.invoice_line_position_as_of('00000000-0000-4000-8000-000000002314', DATE '2026-12-31', clock_timestamp())));
SELECT pg_temp.ok('M1g I1''s position from its lines: 90 of lines, 100 applied, 0 open on its positive lines',
  (SELECT lines_total = 90 AND applied = 100 AND open = 0 FROM public.invoice_position_as_of('00000000-0000-4000-8000-000000002301', DATE '2026-12-31', clock_timestamp())));
SET ROLE tally_app;
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000023b1', true);
SELECT pg_temp.refuses_at('M1h a credit is not "fully applied": what is left is read, not stored',
  $q$UPDATE public.customer_credits SET status = 'fully_applied' WHERE id = '00000000-0000-4000-8000-000000002371'$q$,
  '23001', 'cannot move from active to fully_applied');
SELECT pg_temp.refuses_at('M1i nor born so (the status vocabulary has no such value)',
  $q$INSERT INTO public.customer_credits (tenant_id, customer_id, origin_type, original_amount, issued_date, status)
     VALUES ('00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c1', 'goodwill', 1, DATE '2026-03-02', 'fully_applied')$q$,
  '23514', 'customer_credits_status_check');
-- M2: write-once from insert.
SELECT pg_temp.refuses_at('M2 a pending payment''s amount is fixed from insert (R-05)',
  $q$UPDATE public.payments SET amount = 25 WHERE id = '00000000-0000-4000-8000-000000002362'$q$, '23001', 'is written once');
SELECT pg_temp.admits('M2b a reference that arrives later is written once',
  $q$UPDATE public.payments SET provider_transaction_id = 'ACH-1' WHERE id = '00000000-0000-4000-8000-000000002362'$q$);
SELECT pg_temp.refuses_at('M2c and never changed',
  $q$UPDATE public.payments SET provider_transaction_id = 'ACH-2' WHERE id = '00000000-0000-4000-8000-000000002362'$q$, '23001', 'is written once');
SELECT pg_temp.refuses_at('M2d a payment''s restriction is fixed from insert',
  $q$UPDATE public.payments SET restricted_to_line_item_id = NULL WHERE id = '00000000-0000-4000-8000-000000002364'$q$, '23001', 'is written once');
SELECT pg_temp.refuses_at('M2e a credit''s amount is fixed from insert',
  $q$UPDATE public.customer_credits SET original_amount = 30 WHERE id = '00000000-0000-4000-8000-000000002371'$q$, '23001', 'fixed from insert');
RESET ROLE;
INSERT INTO public.adhoc_charges (id, tenant_id, charge_number, customer_id, charge_type, description, amount, regulatory_class)
VALUES ('00000000-0000-4000-8000-0000000023e1', '00000000-0000-4000-8000-0000000023a1', 'B23-A1', '00000000-0000-4000-8000-0000000023c1', 'miscellaneous', 'Surge protection', 8.00, 'unregulated');
SET ROLE tally_app;
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000023b1', true);
SELECT pg_temp.refuses_at('M2f a pending one-off charge''s amount is fixed from insert',
  $q$UPDATE public.adhoc_charges SET amount = 9 WHERE id = '00000000-0000-4000-8000-0000000023e1'$q$, '23001', 'fixed from insert');
SELECT pg_temp.refuses_at('M2g and its class (D7-2)',
  $q$UPDATE public.adhoc_charges SET regulatory_class = 'regulated' WHERE id = '00000000-0000-4000-8000-0000000023e1'$q$, '23001', 'regulatory_class');
SELECT pg_temp.refuses_at('M2h a void says why',
  $q$UPDATE public.adhoc_charges SET status = 'void' WHERE id = '00000000-0000-4000-8000-0000000023e1'$q$, '23514', 'adhoc_charges_void_reason_check');
-- M3: status moves name their row.
SELECT pg_temp.refuses_at('M3 a move to posted names its posting ledger entry',
  $q$UPDATE public.payments SET status = 'posted', effective_date = DATE '2026-03-08', effective_date_method = 'bank_settlement' WHERE id = '00000000-0000-4000-8000-000000002362'$q$,
  '23503', 'its posting ledger entry');
INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reference_type, reference_id) VALUES
  ('00000000-0000-4000-8000-000000002381', '00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c1', DATE '2026-03-08', 'payment', 'P2 posted', -20, 'payment', '00000000-0000-4000-8000-000000002362'),
  ('00000000-0000-4000-8000-000000002382', '00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c1', DATE '2026-03-05', 'payment', 'P1 posted', -100, 'payment', '00000000-0000-4000-8000-000000002361');
SELECT pg_temp.refuses_at('M3b the entry is the payment''s own, at minus its amount (P1''s entry named for P2)',
  $q$UPDATE public.payments SET status = 'posted', effective_date = DATE '2026-03-08', effective_date_method = 'bank_settlement',
            status_cause_id = '00000000-0000-4000-8000-000000002382' WHERE id = '00000000-0000-4000-8000-000000002362'$q$,
  '23503', 'its posting ledger entry');
SELECT pg_temp.admits('M3c posted, naming its entry',
  $q$UPDATE public.payments SET status = 'posted', effective_date = DATE '2026-03-08', effective_date_method = 'bank_settlement',
            status_cause_id = '00000000-0000-4000-8000-000000002381' WHERE id = '00000000-0000-4000-8000-000000002362'$q$);
SELECT pg_temp.refuses_at('M3d nothing returns to pending',
  $q$UPDATE public.payments SET status = 'pending' WHERE id = '00000000-0000-4000-8000-000000002362'$q$, '23001', 'cannot move from posted to pending');
SELECT pg_temp.refuses_at('M3e the cause changes only with the status',
  $q$UPDATE public.payments SET status_cause_id = NULL WHERE id = '00000000-0000-4000-8000-000000002362'$q$, '23001', 'changes only with the status');
INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reference_type, reference_id, reverses_ledger_entry_id) VALUES
  ('00000000-0000-4000-8000-000000002383', '00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c1', DATE '2026-03-09', 'nsf', 'P1 returned', 100, 'payment', '00000000-0000-4000-8000-000000002361', '00000000-0000-4000-8000-000000002382');
SELECT pg_temp.refuses_at('M3f bounced money is not still paying bills: P1 is applied (guard the act)',
  $q$UPDATE public.payments SET status = 'nsf', nsf_date = DATE '2026-03-09', status_cause_id = '00000000-0000-4000-8000-000000002383' WHERE id = '00000000-0000-4000-8000-000000002361'$q$,
  '23001', 'while it is applied to bills');
RESET ROLE;


-- ============================================================== C credits from overpayment
SET ROLE tally_app;
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000023b1', true);
-- P66: C2 pays 50 for a 45 bill; the customer approves holding 5 as a credit.
INSERT INTO public.payments (id, tenant_id, payment_number, customer_id, payment_date, amount, payment_method, effective_date, effective_date_method)
VALUES ('00000000-0000-4000-8000-000000002366', '00000000-0000-4000-8000-0000000023a1', 'B23-P6', '00000000-0000-4000-8000-0000000023c2', DATE '2026-03-10', 50, 'check', DATE '2026-03-10', 'postmark');
SELECT pg_temp.refuses_at('C1 an overpayment credit cites the customer''s approval',
  $q$INSERT INTO public.customer_credits (tenant_id, customer_id, origin_type, original_amount, issued_date, source_payment_id)
     VALUES ('00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c2', 'overpayment', 5, DATE '2026-03-10', '00000000-0000-4000-8000-000000002366')$q$,
  '23514', 'customer_credits_overpayment_approved_check');
SELECT pg_temp.admits('C1b the approval: the payment, the amount, who took it (the time is the database''s)',
  $q$INSERT INTO public.customer_credit_approvals (id, tenant_id, customer_id, payment_id, amount, approved_by, created_at)
     VALUES ('00000000-0000-4000-8000-000000002351', '00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c2', '00000000-0000-4000-8000-000000002366', 5,
             '00000000-0000-4000-8000-0000000023b1', TIMESTAMPTZ '2020-01-01 00:00Z')$q$);
SELECT pg_temp.ok('C1c its time is stamped, not supplied',
  (SELECT created_at = now() FROM public.customer_credit_approvals WHERE id = '00000000-0000-4000-8000-000000002351'));
SELECT pg_temp.refuses_at('C1d the credit equals the approved amount',
  $q$INSERT INTO public.customer_credits (tenant_id, customer_id, origin_type, original_amount, issued_date, source_payment_id, approval_id)
     VALUES ('00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c2', 'overpayment', 6, DATE '2026-03-10', '00000000-0000-4000-8000-000000002366', '00000000-0000-4000-8000-000000002351')$q$,
  '23503', 'customer_credits_approval_fkey');
SELECT pg_temp.refuses_at('C1e and comes from the approved payment',
  $q$INSERT INTO public.customer_credits (tenant_id, customer_id, origin_type, original_amount, issued_date, source_payment_id, approval_id)
     VALUES ('00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c2', 'overpayment', 5, DATE '2026-03-10', '00000000-0000-4000-8000-000000002365', '00000000-0000-4000-8000-000000002351')$q$,
  '23503', 'customer_credits_approval_fkey');
SELECT pg_temp.refuses_at('C1f an overpayment credit names its payment (an approval without one is not checked by the FK)',
  $q$INSERT INTO public.customer_credits (tenant_id, customer_id, origin_type, original_amount, issued_date, approval_id)
     VALUES ('00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c2', 'overpayment', 5, DATE '2026-03-10', '00000000-0000-4000-8000-000000002351')$q$,
  '23514', 'customer_credits_overpayment_approved_check');
SELECT pg_temp.admits('C1g the credit, under its approval',
  $q$INSERT INTO public.customer_credits (id, tenant_id, customer_id, origin_type, original_amount, issued_date, source_payment_id, approval_id)
     VALUES ('00000000-0000-4000-8000-000000002372', '00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c2', 'overpayment', 5, DATE '2026-03-10', '00000000-0000-4000-8000-000000002366', '00000000-0000-4000-8000-000000002351')$q$);
SELECT pg_temp.refuses_at('C1h one approval, one credit',
  $q$INSERT INTO public.customer_credits (tenant_id, customer_id, origin_type, original_amount, issued_date, source_payment_id, approval_id)
     VALUES ('00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c2', 'overpayment', 5, DATE '2026-03-10', '00000000-0000-4000-8000-000000002366', '00000000-0000-4000-8000-000000002351')$q$,
  '23505', 'customer_credits_one_per_approval');
SELECT pg_temp.refuses_at('C1i an approval is never edited',
  $q$UPDATE public.customer_credit_approvals SET amount = 50 WHERE id = '00000000-0000-4000-8000-000000002351'$q$, '42501', 'permission denied');
SELECT pg_temp.ok('C1j P6''s position counts the credit: 5 credited, 45 left',
  (SELECT credited = 5 AND remaining = 45 FROM public.payment_position_as_of('00000000-0000-4000-8000-000000002366', DATE '2026-12-31', clock_timestamp())));
-- The payment's money goes three ways and never past it.
INSERT INTO public.customer_credit_approvals (id, tenant_id, customer_id, payment_id, amount, approved_by)
VALUES ('00000000-0000-4000-8000-000000002352', '00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c2', '00000000-0000-4000-8000-000000002366', 46, '00000000-0000-4000-8000-0000000023b1');
SELECT pg_temp.refuses_at('C1k an approval for more than is left makes no credit past the payment (5 + 46 of 50)',
  $q$INSERT INTO public.customer_credits (tenant_id, customer_id, origin_type, original_amount, issued_date, source_payment_id, approval_id)
     VALUES ('00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c2', 'overpayment', 46, DATE '2026-03-10', '00000000-0000-4000-8000-000000002366', '00000000-0000-4000-8000-000000002352')$q$,
  '23514', 'more than its 50');
SELECT pg_temp.refuses_at('C1l a refund draws on the same money (45 left, 46 refunded)',
  $q$INSERT INTO public.payments (tenant_id, payment_number, customer_id, payment_date, amount, payment_method, effective_date, effective_date_method, refunds_payment_id)
     VALUES ('00000000-0000-4000-8000-0000000023a1', 'B23-R1', '00000000-0000-4000-8000-0000000023c2', DATE '2026-03-11', -46, 'refund', DATE '2026-03-11', 'other', '00000000-0000-4000-8000-000000002366')$q$,
  '23514', 'more than its 50');
SELECT pg_temp.admits('C1m the rest refunded (45)',
  $q$INSERT INTO public.payments (id, tenant_id, payment_number, customer_id, payment_date, amount, payment_method, effective_date, effective_date_method, refunds_payment_id)
     VALUES ('00000000-0000-4000-8000-000000002367', '00000000-0000-4000-8000-0000000023a1', 'B23-R1', '00000000-0000-4000-8000-0000000023c2', DATE '2026-03-11', -45, 'refund', DATE '2026-03-11', 'other', '00000000-0000-4000-8000-000000002366')$q$);
SELECT pg_temp.admits('M3g refunded, naming the refund, with nothing left',
  $q$UPDATE public.payments SET status = 'refunded', status_cause_id = '00000000-0000-4000-8000-000000002367' WHERE id = '00000000-0000-4000-8000-000000002366'$q$);
SELECT pg_temp.refuses_at('M3h a credit is voided only when nothing of it is applied (K71 paid 25 of I2)',
  $q$UPDATE public.customer_credits SET status = 'voided', status_cause_id = NULL WHERE id = '00000000-0000-4000-8000-000000002371'$q$,
  '23503', 'the ledger row reversing its issuing entry');
-- C2.
RESET ROLE;
SELECT pg_temp.refuses_at('C2 overpayment_handling no longer applies to a bill of the payer''s choosing (K-05)',
  $q$UPDATE public.tenants SET overpayment_handling = 'apply_to_specific_invoices' WHERE id = '00000000-0000-4000-8000-0000000023a1'$q$,
  '23514', 'tenants_overpayment_handling_check');
SELECT pg_temp.ok('C2b the allocation strategy column is retired (K-05: oldest first)',
  NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'tenants' AND column_name = 'payment_allocation_strategy'));


-- ============================================================== X reversals
INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount) VALUES
  ('00000000-0000-4000-8000-000000002391', '00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c2', DATE '2026-03-01', 'charge', 'C2 charge', 100.00);
SET ROLE tally_app;
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000023b1', true);
SELECT pg_temp.refuses_at('X1 an nsf names the entry it reverses',
  $q$INSERT INTO public.account_ledger (tenant_id, customer_id, transaction_date, transaction_type, description, amount)
     VALUES ('00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c2', DATE '2026-03-02', 'nsf', 'x', 10)$q$,
  '23514', 'account_ledger_reversal_types_name_check');
SELECT pg_temp.refuses_at('X1b of its own customer',
  $q$INSERT INTO public.account_ledger (tenant_id, customer_id, transaction_date, transaction_type, description, amount, reverses_ledger_entry_id)
     VALUES ('00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c1', DATE '2026-03-02', 'adjustment', 'x', -10, '00000000-0000-4000-8000-000000002391')$q$,
  '23503', 'account_ledger_reverses_ledger_entry_fkey');
SELECT pg_temp.refuses_at('X2 with the opposite sign',
  $q$INSERT INTO public.account_ledger (tenant_id, customer_id, transaction_date, transaction_type, description, amount, reverses_ledger_entry_id)
     VALUES ('00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c2', DATE '2026-03-02', 'adjustment', 'x', 10, '00000000-0000-4000-8000-000000002391')$q$,
  '23514', 'opposite sign');
SELECT pg_temp.refuses_at('X2b and never dated before it',
  $q$INSERT INTO public.account_ledger (tenant_id, customer_id, transaction_date, transaction_type, description, amount, reverses_ledger_entry_id)
     VALUES ('00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c2', DATE '2026-02-28', 'adjustment', 'x', -10, '00000000-0000-4000-8000-000000002391')$q$,
  '23514', 'dated on or after the entry it names');
INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reverses_ledger_entry_id) VALUES
  ('00000000-0000-4000-8000-000000002392', '00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c2', DATE '2026-03-02', 'adjustment', 'R1', -60, '00000000-0000-4000-8000-000000002391');
SELECT pg_temp.refuses_at('X2c reversals total at most the entry (60 + 50 of 100)',
  $q$INSERT INTO public.account_ledger (tenant_id, customer_id, transaction_date, transaction_type, description, amount, reverses_ledger_entry_id)
     VALUES ('00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c2', DATE '2026-03-03', 'adjustment', 'R2', -50, '00000000-0000-4000-8000-000000002391')$q$,
  '23514', 'R-02 cap');
INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reverses_ledger_entry_id) VALUES
  ('00000000-0000-4000-8000-000000002393', '00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c2', DATE '2026-03-03', 'adjustment', 'RR1: R1 was wrong', 60, '00000000-0000-4000-8000-000000002392'),
  ('00000000-0000-4000-8000-000000002394', '00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c2', DATE '2026-03-04', 'adjustment', 'R2', -50, '00000000-0000-4000-8000-000000002391');
DO $$ BEGIN RAISE NOTICE 'PASS X2d a reversal of a reversal frees the room it took (R2 of 50 admitted after RR1)'; END $$;
SELECT pg_temp.refuses_at('X2e three levels down still nets into the original: R3 under RR1 brings R1 back, 60 + 50 of 100',
  $q$INSERT INTO public.account_ledger (tenant_id, customer_id, transaction_date, transaction_type, description, amount, reverses_ledger_entry_id)
     VALUES ('00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c2', DATE '2026-03-05', 'adjustment', 'R3', -60, '00000000-0000-4000-8000-000000002393')$q$,
  '23514', 'entry 00000000-0000-4000-8000-000000002391');
SELECT pg_temp.refuses_at('X2f and at every date: an earlier-dated reversal is not made room for by a later one',
  $q$INSERT INTO public.account_ledger (tenant_id, customer_id, transaction_date, transaction_type, description, amount, reverses_ledger_entry_id)
     VALUES ('00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c2', DATE '2026-03-02', 'adjustment', 'R4 dated with R1', -50, '00000000-0000-4000-8000-000000002391')$q$,
  '23514', 'R-02 cap');
RESET ROLE;
SELECT pg_temp.refuses_at('X2g a ledger row is recorded at a time already reached (the owner''s too)',
  $q$INSERT INTO public.account_ledger (tenant_id, customer_id, transaction_date, transaction_type, description, amount, created_at)
     VALUES ('00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c2', DATE '2026-03-05', 'charge', 'x', 1, now() + interval '1 day')$q$,
  '23514', 'non-finite or future time');
SELECT pg_temp.refuses_at('X2h a history row with a chosen time is recorded after every row already in its tree',
  $q$INSERT INTO public.account_ledger (tenant_id, customer_id, transaction_date, transaction_type, description, amount, reverses_ledger_entry_id, created_at)
     VALUES ('00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c2', DATE '2026-03-05', 'adjustment', 'x', -1, '00000000-0000-4000-8000-000000002391', now() - interval '1 day')$q$,
  '23514', 'a time chosen for it');
-- X3: the void reverses what is left. I3 is posted; its charge is 90, of
-- which 30 was reversed already.
INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reference_type, reference_id) VALUES
  ('00000000-0000-4000-8000-000000002395', '00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c2', DATE '2026-03-01', 'charge', 'I3', 90.00, 'invoice', '00000000-0000-4000-8000-000000002303');
INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reverses_ledger_entry_id) VALUES
  ('00000000-0000-4000-8000-000000002396', '00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c2', DATE '2026-03-02', 'adjustment', 'I3 less 30', -30.00, '00000000-0000-4000-8000-000000002395');
SET ROLE tally_app;
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000023b1', true);
SELECT pg_temp.ok('X3 the void reverses the 60 left of the charge, not -(amount_due), and names it',
  (SELECT (r ->> 'reversal_amount')::numeric = -60 AND (r ->> 'reverses_ledger_entry_id')::uuid = '00000000-0000-4000-8000-000000002395'
     FROM public.void_invoice('00000000-0000-4000-8000-000000002303', '00000000-0000-4000-8000-0000000023b1', 'wrong_rate', NULL, true) r));
SELECT pg_temp.ok('X3b nothing of the charge is left after it',
  public.ledger_entry_remaining('00000000-0000-4000-8000-000000002395') = 0);
RESET ROLE;
INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reference_type, reference_id) VALUES
  ('00000000-0000-4000-8000-000000002397', '00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c1', DATE '2026-03-01', 'charge', 'I2', 90.00, 'invoice', '00000000-0000-4000-8000-000000002302');
INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reverses_ledger_entry_id) VALUES
  ('00000000-0000-4000-8000-000000002398', '00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c1', DATE '2026-03-02', 'adjustment', 'I2 forgiven', -90.00, '00000000-0000-4000-8000-000000002397');
SET ROLE tally_app;
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000023b1', true);
SELECT pg_temp.ok('X3c a charge already fully reversed voids with no ledger row',
  (SELECT (r ->> 'reversal_amount') IS NULL AND (r ->> 'ledger_entry_id') IS NULL
     FROM public.void_invoice('00000000-0000-4000-8000-000000002302', '00000000-0000-4000-8000-0000000023b1', 'duplicate', NULL, false) r));
SELECT pg_temp.refuses_at('X3d a void bill takes no new money',
  $q$INSERT INTO public.invoice_applications (tenant_id, customer_id, invoice_id, invoice_line_item_id, payment_id, amount, applied_on, basis, allocation_tariff_id)
     VALUES ('00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c1', '00000000-0000-4000-8000-000000002302', '00000000-0000-4000-8000-000000002314',
             '00000000-0000-4000-8000-000000002364', 1, DATE '2026-03-08', 'floor_over_restriction', '00000000-0000-4000-8000-0000000023ab')$q$,
  '23514', 'an issued, unvoided bill');
RESET ROLE;


-- ============================================================== A1b the line's class at issue
INSERT INTO public.invoices (id, tenant_id, invoice_number, customer_id, location_id, invoice_date, billing_period, period_start, period_end, due_date, amount_due)
VALUES ('00000000-0000-4000-8000-000000002305', '00000000-0000-4000-8000-0000000023a1', 'B23-I5', '00000000-0000-4000-8000-0000000023c1', '00000000-0000-4000-8000-0000000023d1',
        DATE '2026-04-01', '2026-03', DATE '2026-03-01', DATE '2026-03-31', DATE '2026-04-20', 8.00);
INSERT INTO public.invoice_line_items (tenant_id, invoice_id, service_type, charge_type, description, amount, adhoc_charge_id, regulatory_class) VALUES
  ('00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-000000002305', 'general', 'adhoc', 'Surge protection', 8.00, '00000000-0000-4000-8000-0000000023e1', 'regulated');
SELECT pg_temp.snap('00000000-0000-4000-8000-000000002305', DATE '2026-03-31', now());
DO $$
DECLARE v_state text; v_msg text;
BEGIN
  BEGIN
    UPDATE public.invoices SET status = 'pending' WHERE id = '00000000-0000-4000-8000-000000002305';
    SET CONSTRAINTS enforce_invoice_line_class IMMEDIATE;
    RAISE EXCEPTION USING ERRCODE = 'P0099', MESSAGE = 'issued';
  EXCEPTION WHEN OTHERS THEN
    v_state := SQLSTATE; v_msg := SQLERRM;
  END;
  SET CONSTRAINTS enforce_invoice_line_class DEFERRED;
  IF v_state = '23514' AND strpos(v_msg, 'its one-off charge') > 0 THEN
    RAISE NOTICE 'PASS A1b a line classed against its one-off charge wrongly is refused at issue (%)', left(v_msg, 120);
  ELSE
    RAISE EXCEPTION 'FAIL A1b: got % (%)', v_state, v_msg;
  END IF;
END $$;
SELECT pg_temp.refuses_at('A1c every line carries a class (NOT NULL; no assumed default)',
  $q$INSERT INTO public.invoice_line_items (tenant_id, invoice_id, service_type, charge_type, description, amount)
     VALUES ('00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-000000002305', 'gas', 'tax', 'Tax', 1.00)$q$,
  '23502', 'regulatory_class');


-- ============================================================== F the freeze on applications
SET ROLE tally_close;
UPDATE public.accounting_close_heads SET closed_through = DATE '2026-03-06' WHERE tenant_id = '00000000-0000-4000-8000-0000000023a1';
RESET ROLE;
SET ROLE tally_app;
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000023b1', true);
SELECT pg_temp.refuses_at('F1 an application dated in a closed period',
  $q$INSERT INTO public.invoice_applications (tenant_id, customer_id, invoice_id, invoice_line_item_id, payment_id, amount, applied_on, basis, applied_by, reason)
     VALUES ('00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c1', '00000000-0000-4000-8000-000000002301', '00000000-0000-4000-8000-000000002312',
             '00000000-0000-4000-8000-000000002364', 1, DATE '2026-03-06', 'operator_override', '00000000-0000-4000-8000-0000000023b1', 'x')$q$,
  '23514', 'a closed period is frozen');
RESET ROLE;


-- ============================================================== I invariants
SELECT pg_temp.ok('I1 every -23 guard is in place, exactly',
  (SELECT public.assert_cash_guard_invariants() IS NULL OR true));
SELECT pg_temp.ok('I2 the earlier invariants still hold with -23',
  (SELECT public.assert_periods_guard_invariants() IS NULL OR true)
  AND (SELECT public.assert_seal_role_invariants() IS NULL OR true)
  AND (SELECT public.assert_tenant_isolation_invariants() IS NULL OR true)
  AND (SELECT public.assert_rule_table_invariants() IS NULL OR true));

ROLLBACK;
