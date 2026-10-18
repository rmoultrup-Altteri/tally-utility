-- PREDICTED. Owner, fresh clone with frozen r2 applied; frozen battery with error notices added.
\set ON_ERROR_STOP on
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
    RAISE NOTICE 'caught SQLSTATE=% message=%', SQLSTATE, SQLERRM;
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
    RAISE NOTICE 'caught SQLSTATE=% message=%', SQLSTATE, SQLERRM;
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
-- post(): a pending payment's posting entry (payment, or deposit for a
-- deposit; dated its payment date, at minus its amount), then the move to
-- posted naming it (r2: a payment is born pending). A payment with no
-- effective date takes its payment date as it posts (-19 P2).
CREATE FUNCTION pg_temp.post(p_pay uuid, p_entry uuid) RETURNS void LANGUAGE plpgsql AS $$
DECLARE p public.payments%ROWTYPE;
BEGIN
  SELECT * INTO p FROM public.payments WHERE id = p_pay;
  INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reference_type, reference_id)
  VALUES (p_entry, p.tenant_id, p.customer_id, p.payment_date,
          CASE WHEN p.refunds_payment_id IS NOT NULL OR p.refunds_customer_credit_id IS NOT NULL THEN 'refund' WHEN p.is_deposit THEN 'deposit' ELSE 'payment' END,
          p.payment_number || ' posted', -p.amount, 'payment', p.id);
  UPDATE public.payments SET status = 'posted', status_cause_id = p_entry,
         effective_date = coalesce(effective_date, payment_date), effective_date_method = coalesce(effective_date_method, 'other')
   WHERE id = p_pay;
END $$;
GRANT EXECUTE ON FUNCTION pg_temp.refuses_at(text, text, text, text), pg_temp.ok(text, boolean), pg_temp.admits(text, text), pg_temp.post(uuid, uuid) TO tally_app, tally_core;

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
  -- Issued three hours ago, as a history load (the owner's stamp is kept),
  -- so M1j can record a payment and an application in the past.
  UPDATE public.invoices SET status = 'pending' WHERE id = p_id;
  UPDATE public.invoices SET first_issued_at = now() - interval '3 hours' WHERE id = p_id;
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
SELECT pg_temp.admits('T5 the utility''s own complete order, regulated first (in force January 1 to March 31)',
  $q$INSERT INTO public.payment_allocation_tariffs (id, tenant_id, state_code, service_type, system_kind, effective_from, effective_to, tariff_reference, terms_kind, terms_version, terms_source)
     VALUES ('00000000-0000-4000-8000-0000000023ab', '00000000-0000-4000-8000-0000000023a1', 'TX', 'gas', 'distribution', DATE '2026-01-01', DATE '2026-04-01', 'City tariff 7', 'payment_allocation_tariff', 1,
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
-- r2: a payment is born pending and posted by the move naming its posting
-- entry (post()); a goodwill credit's money is its credit_issued entry.
INSERT INTO public.payments (id, tenant_id, payment_number, customer_id, payment_date, amount, payment_method, effective_date, effective_date_method,
                             is_deposit, payer_class, restricted_to_invoice_id, restricted_to_line_item_id) VALUES
  ('00000000-0000-4000-8000-000000002361', '00000000-0000-4000-8000-0000000023a1', 'B23-P1', '00000000-0000-4000-8000-0000000023c1', DATE '2026-03-05', 100, 'check', DATE '2026-03-05', 'postmark', false, 'customer', NULL, NULL),
  ('00000000-0000-4000-8000-000000002362', '00000000-0000-4000-8000-0000000023a1', 'B23-P2', '00000000-0000-4000-8000-0000000023c1', DATE '2026-03-05', 20, 'ach', NULL, NULL, false, 'customer', NULL, NULL),
  ('00000000-0000-4000-8000-000000002363', '00000000-0000-4000-8000-0000000023a1', 'B23-P3', '00000000-0000-4000-8000-0000000023c1', DATE '2026-03-05', 75, 'check', DATE '2026-03-05', 'postmark', true, 'customer', NULL, NULL),
  ('00000000-0000-4000-8000-000000002364', '00000000-0000-4000-8000-0000000023a1', 'B23-P4', '00000000-0000-4000-8000-0000000023c1', DATE '2026-03-06', 50, 'check', DATE '2026-03-06', 'postmark', false, 'agency',
   '00000000-0000-4000-8000-000000002302', '00000000-0000-4000-8000-000000002315'),
  ('00000000-0000-4000-8000-000000002365', '00000000-0000-4000-8000-0000000023a1', 'B23-P5', '00000000-0000-4000-8000-0000000023c2', DATE '2026-03-05', 30, 'check', DATE '2026-03-05', 'postmark', false, 'customer', NULL, NULL);
SELECT pg_temp.post('00000000-0000-4000-8000-000000002361', '00000000-0000-4000-8000-000000002382');
SELECT pg_temp.post('00000000-0000-4000-8000-000000002363', '00000000-0000-4000-8000-0000000023f3');
SELECT pg_temp.post('00000000-0000-4000-8000-000000002364', '00000000-0000-4000-8000-0000000023f4');
SELECT pg_temp.post('00000000-0000-4000-8000-000000002365', '00000000-0000-4000-8000-0000000023f5');
-- K71: a goodwill credit of 25 for C1, issued on the ledger.
INSERT INTO public.customer_credits (id, tenant_id, customer_id, origin_type, original_amount, issued_date)
VALUES ('00000000-0000-4000-8000-000000002371', '00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c1', 'goodwill', 25, DATE '2026-03-02');
INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reference_type, reference_id) VALUES
  ('00000000-0000-4000-8000-000000002384', '00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c1', DATE '2026-03-02', 'credit_issued', 'K71 issued', -25, 'customer_credit', '00000000-0000-4000-8000-000000002371');
RESET ROLE;
-- K73: a credit of C1's loaded as voided (history), for A3k. K74: an active
-- credit issued before the March 1 bills, for A3l.
INSERT INTO public.customer_credits (id, tenant_id, customer_id, origin_type, original_amount, issued_date, status) VALUES
  ('00000000-0000-4000-8000-000000002373', '00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c1', 'goodwill', 5, DATE '2026-03-02', 'voided'),
  ('00000000-0000-4000-8000-000000002374', '00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c1', 'goodwill', 5, DATE '2026-02-20', 'active');


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
SELECT pg_temp.refuses_at('A2i an undo is of the same payment (P4 for P1''s application)',
  $q$INSERT INTO public.invoice_applications (tenant_id, customer_id, invoice_id, invoice_line_item_id, payment_id, amount, applied_on, basis, undoes_application_id, applied_by, reason)
     VALUES ('00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c1', '00000000-0000-4000-8000-000000002301', '00000000-0000-4000-8000-000000002311',
             '00000000-0000-4000-8000-000000002364', -10, DATE '2026-03-06', 'undo', '00000000-0000-4000-8000-000000002341', '00000000-0000-4000-8000-0000000023b1', 'keyed wrong')$q$,
  '23514', 'of the same source and line');
SELECT pg_temp.admits('A2g a partial undo, with its reason and user',
  $q$INSERT INTO public.invoice_applications (id, tenant_id, customer_id, invoice_id, invoice_line_item_id, payment_id, amount, applied_on, basis, undoes_application_id, applied_by, reason)
     VALUES ('00000000-0000-4000-8000-000000002342', '00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c1', '00000000-0000-4000-8000-000000002301', '00000000-0000-4000-8000-000000002311',
             '00000000-0000-4000-8000-000000002361', -10, DATE '2026-03-06', 'undo', '00000000-0000-4000-8000-000000002341', '00000000-0000-4000-8000-0000000023b1', 'keyed wrong')$q$);
SELECT pg_temp.refuses_at('A2h an undo is never undone (re-apply instead): a well-formed undo naming an undo',
  $q$INSERT INTO public.invoice_applications (tenant_id, customer_id, invoice_id, invoice_line_item_id, payment_id, amount, applied_on, basis, undoes_application_id, applied_by, reason)
     VALUES ('00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c1', '00000000-0000-4000-8000-000000002301', '00000000-0000-4000-8000-000000002311',
             '00000000-0000-4000-8000-000000002361', -1, DATE '2026-03-06', 'undo', '00000000-0000-4000-8000-000000002342', '00000000-0000-4000-8000-0000000023b1', 'x')$q$,
  '23514', '(not an undo)');
SELECT pg_temp.refuses_at('A2j an undo''s sign is negative (a positive row naming an application)',
  $q$INSERT INTO public.invoice_applications (tenant_id, customer_id, invoice_id, invoice_line_item_id, payment_id, amount, applied_on, basis, undoes_application_id, applied_by, reason)
     VALUES ('00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c1', '00000000-0000-4000-8000-000000002301', '00000000-0000-4000-8000-000000002311',
             '00000000-0000-4000-8000-000000002361', 10, DATE '2026-03-06', 'undo', '00000000-0000-4000-8000-000000002341', '00000000-0000-4000-8000-0000000023b1', 'x')$q$,
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
  '23514', 'drawn from a posted payment');
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
  '23514', 'drawn on or after it arrives');
SELECT pg_temp.admits('A3j a credit pays a line',
  $q$INSERT INTO public.invoice_applications (id, tenant_id, customer_id, invoice_id, invoice_line_item_id, customer_credit_id, amount, applied_on, basis, allocation_tariff_id)
     VALUES ('00000000-0000-4000-8000-000000002343', '00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c1', '00000000-0000-4000-8000-000000002302', '00000000-0000-4000-8000-000000002314',
             '00000000-0000-4000-8000-000000002371', 25, DATE '2026-03-07', 'oldest_first', '00000000-0000-4000-8000-0000000023ab')$q$);
SELECT pg_temp.refuses_at('A3k a voided credit pays nothing',
  $q$INSERT INTO public.invoice_applications (tenant_id, customer_id, invoice_id, invoice_line_item_id, customer_credit_id, amount, applied_on, basis, allocation_tariff_id)
     VALUES ('00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c1', '00000000-0000-4000-8000-000000002302', '00000000-0000-4000-8000-000000002314',
             '00000000-0000-4000-8000-000000002373', 1, DATE '2026-03-07', 'oldest_first', '00000000-0000-4000-8000-0000000023ab')$q$,
  '23514', 'or an active credit');
SELECT pg_temp.refuses_at('A3l money is applied on or after its bill (K74 issued February 20, applied February 25, before I2''s March 1)',
  $q$INSERT INTO public.invoice_applications (tenant_id, customer_id, invoice_id, invoice_line_item_id, customer_credit_id, amount, applied_on, basis, allocation_tariff_id)
     VALUES ('00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c1', '00000000-0000-4000-8000-000000002302', '00000000-0000-4000-8000-000000002314',
             '00000000-0000-4000-8000-000000002374', 1, DATE '2026-02-25', 'oldest_first', '00000000-0000-4000-8000-0000000023ab')$q$,
  '23514', 'before its bill');
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
-- T1's next tariff row, in force from April 1, when T5's ends.
INSERT INTO public.payment_allocation_tariffs (id, tenant_id, state_code, service_type, system_kind, effective_from, tariff_reference, terms_kind, terms_version, terms_source)
SELECT '00000000-0000-4000-8000-0000000023ac', t.tenant_id, t.state_code, t.service_type, t.system_kind, DATE '2026-04-01', 'City tariff 8', t.terms_kind, t.terms_version, t.terms_source
  FROM public.payment_allocation_tariffs t WHERE t.id = '00000000-0000-4000-8000-0000000023ab';
SELECT pg_temp.refuses_at('A4c the tariff is in force on the application''s date (a row from April 1, cited on March 7)',
  $q$INSERT INTO public.invoice_applications (tenant_id, customer_id, invoice_id, invoice_line_item_id, payment_id, amount, applied_on, basis, allocation_tariff_id)
     VALUES ('00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c2', '00000000-0000-4000-8000-000000002303', '00000000-0000-4000-8000-000000002317',
             '00000000-0000-4000-8000-000000002365', 5, DATE '2026-03-07', 'oldest_first', '00000000-0000-4000-8000-0000000023ac')$q$,
  '23514', 'is not in force on');
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
-- P68 (C2, 10) recorded two hours ago, and 5 of it applied to I3's gas line
-- an hour ago (a history load: the owner's times are kept).
INSERT INTO public.payments (id, tenant_id, payment_number, customer_id, payment_date, amount, payment_method, effective_date, effective_date_method, created_at)
VALUES ('00000000-0000-4000-8000-000000002368', '00000000-0000-4000-8000-0000000023a1', 'B23-P8', '00000000-0000-4000-8000-0000000023c2', DATE '2026-03-05', 10, 'check', DATE '2026-03-05', 'postmark', now() - interval '2 hours');
INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reference_type, reference_id, created_at)
VALUES ('00000000-0000-4000-8000-0000000023f8', '00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c2', DATE '2026-03-05', 'payment', 'P8 posted', -10, 'payment', '00000000-0000-4000-8000-000000002368', now() - interval '2 hours');
UPDATE public.payments SET status = 'posted', status_cause_id = '00000000-0000-4000-8000-0000000023f8' WHERE id = '00000000-0000-4000-8000-000000002368';
INSERT INTO public.invoice_applications (tenant_id, customer_id, invoice_id, invoice_line_item_id, payment_id, amount, applied_on, basis, allocation_tariff_id, created_at)
VALUES ('00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c2', '00000000-0000-4000-8000-000000002303', '00000000-0000-4000-8000-000000002317', '00000000-0000-4000-8000-000000002368', 5, DATE '2026-03-07', 'oldest_first', '00000000-0000-4000-8000-0000000023ab', now() - interval '1 hour');
SELECT pg_temp.ok('M1j by the recorded instant: 90 minutes ago P8 was known and nothing of it applied; now 5 is',
  (SELECT applied = 0 AND remaining = 10 FROM public.payment_position_as_of('00000000-0000-4000-8000-000000002368', DATE '2026-12-31', now() - interval '90 minutes'))
  AND (SELECT applied = 5 AND remaining = 5 FROM public.payment_position_as_of('00000000-0000-4000-8000-000000002368', DATE '2026-12-31', clock_timestamp())));
SET ROLE tally_app;
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000023b1', true);
SELECT pg_temp.refuses_at('M1h a credit is not "fully applied": what is left is read, not stored',
  $q$UPDATE public.customer_credits SET status = 'fully_applied' WHERE id = '00000000-0000-4000-8000-000000002371'$q$,
  '23001', 'cannot move from active to fully_applied');
-- As the owner: tally_app's insert stops at the birth rule first (M3j).
RESET ROLE;
SELECT pg_temp.refuses_at('M1i nor born so (the status vocabulary has no such value)',
  $q$INSERT INTO public.customer_credits (tenant_id, customer_id, origin_type, original_amount, issued_date, status)
     VALUES ('00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c1', 'goodwill', 1, DATE '2026-03-02', 'fully_applied')$q$,
  '23514', 'customer_credits_status_check');
SET ROLE tally_app;
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000023b1', true);
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
  ('00000000-0000-4000-8000-000000002381', '00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c1', DATE '2026-03-08', 'payment', 'P2 posted', -20, 'payment', '00000000-0000-4000-8000-000000002362');
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
  $q$UPDATE public.payments SET status_cause_id = NULL WHERE id = '00000000-0000-4000-8000-000000002362'$q$, '23001', 'change only with the status');
SELECT pg_temp.refuses_at('M3f bounced money is not still paying bills: the bounce row itself waits while P1 is applied (guard the act)',
  $q$INSERT INTO public.account_ledger (tenant_id, customer_id, transaction_date, transaction_type, description, amount, reference_type, reference_id, reverses_ledger_entry_id)
     VALUES ('00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c1', DATE '2026-03-09', 'nsf', 'P1 returned', 100, 'payment', '00000000-0000-4000-8000-000000002361', '00000000-0000-4000-8000-000000002382')$q$,
  '23001', 'while the payment is applied to bills');
RESET ROLE;
-- The move's own guard, behind the ledger's: a bounce row planted past it.
ALTER TABLE public.account_ledger DISABLE TRIGGER enforce_ledger_reversal;
INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reference_type, reference_id, reverses_ledger_entry_id) VALUES
  ('00000000-0000-4000-8000-000000002383', '00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c1', DATE '2026-03-09', 'nsf', 'P1 returned', 100, 'payment', '00000000-0000-4000-8000-000000002361', '00000000-0000-4000-8000-000000002382');
ALTER TABLE public.account_ledger ENABLE ALWAYS TRIGGER enforce_ledger_reversal;
SET ROLE tally_app;
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000023b1', true);
SELECT pg_temp.refuses_at('M3f2 nor does the move to nsf pass while P1 is applied (the planted bounce row past the ledger''s guard)',
  $q$UPDATE public.payments SET status = 'nsf', nsf_date = DATE '2026-03-09', status_cause_id = '00000000-0000-4000-8000-000000002383' WHERE id = '00000000-0000-4000-8000-000000002361'$q$,
  '23001', 'while it is applied to bills');
SELECT pg_temp.refuses_at('M3f3 and P1 gives no more money: its posting entry is undone (O2)',
  $q$INSERT INTO public.invoice_applications (tenant_id, customer_id, invoice_id, invoice_line_item_id, payment_id, amount, applied_on, basis, applied_by, reason)
     VALUES ('00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c1', '00000000-0000-4000-8000-000000002302', '00000000-0000-4000-8000-000000002314',
             '00000000-0000-4000-8000-000000002361', 1, DATE '2026-03-09', 'operator_override', '00000000-0000-4000-8000-0000000023b1', 'x')$q$,
  '23514', 'its money is not on the ledger');
RESET ROLE;


-- ============================================================== C credits from overpayment
SET ROLE tally_app;
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000023b1', true);
-- P66: C2 pays 50 for a 45 bill; the customer approves holding 5 as a credit.
INSERT INTO public.payments (id, tenant_id, payment_number, customer_id, payment_date, amount, payment_method, effective_date, effective_date_method)
VALUES ('00000000-0000-4000-8000-000000002366', '00000000-0000-4000-8000-0000000023a1', 'B23-P6', '00000000-0000-4000-8000-0000000023c2', DATE '2026-03-10', 50, 'check', DATE '2026-03-10', 'postmark');
SELECT pg_temp.post('00000000-0000-4000-8000-000000002366', '00000000-0000-4000-8000-0000000023f6');
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
-- P5 (C2, 30) paid 5 of I3 (A4d); 10 of it is refunded, 15 left.
INSERT INTO public.payments (id, tenant_id, payment_number, customer_id, payment_date, amount, payment_method, effective_date, effective_date_method, refunds_payment_id)
VALUES ('00000000-0000-4000-8000-000000002369', '00000000-0000-4000-8000-0000000023a1', 'B23-R2', '00000000-0000-4000-8000-0000000023c2', DATE '2026-03-11', -10, 'refund', DATE '2026-03-11', 'other', '00000000-0000-4000-8000-000000002365');
SELECT pg_temp.refuses_at('M3i a payment is refunded only when nothing of it is left (P5: 30 less 5 applied, 10 refunded)',
  $q$UPDATE public.payments SET status = 'refunded', status_cause_id = '00000000-0000-4000-8000-000000002369' WHERE id = '00000000-0000-4000-8000-000000002365'$q$,
  '23001', 'only when nothing of it is left');
-- P9: C2 pays 20, still pending; the customer's approval to hold 5 of it.
INSERT INTO public.payments (id, tenant_id, payment_number, customer_id, payment_date, amount, payment_method, status)
VALUES ('00000000-0000-4000-8000-00000000236a', '00000000-0000-4000-8000-0000000023a1', 'B23-P9', '00000000-0000-4000-8000-0000000023c2', DATE '2026-03-10', 20, 'ach', 'pending');
INSERT INTO public.customer_credit_approvals (id, tenant_id, customer_id, payment_id, amount, approved_by)
VALUES ('00000000-0000-4000-8000-000000002353', '00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c2', '00000000-0000-4000-8000-00000000236a', 5, '00000000-0000-4000-8000-0000000023b1');
SELECT pg_temp.refuses_at('C1m2 a pending payment holds no credit (money not yet arrived)',
  $q$INSERT INTO public.customer_credits (tenant_id, customer_id, origin_type, original_amount, issued_date, source_payment_id, approval_id)
     VALUES ('00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c2', 'overpayment', 5, DATE '2026-03-10', '00000000-0000-4000-8000-00000000236a', '00000000-0000-4000-8000-000000002353')$q$,
  '23514', 'drawn from a posted payment');
SELECT pg_temp.refuses_at('M3h0 a credit''s void names the row behind it',
  $q$UPDATE public.customer_credits SET status = 'voided', status_cause_id = NULL WHERE id = '00000000-0000-4000-8000-000000002371'$q$,
  '23503', 'the ledger row reversing its credit_issued entry');
SELECT pg_temp.refuses_at('M3h a credit''s money is not withdrawn on the ledger while it is drawn on (K71 paid 25 of I2; O6)',
  $q$INSERT INTO public.account_ledger (tenant_id, customer_id, transaction_date, transaction_type, description, amount, reverses_ledger_entry_id)
     VALUES ('00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c1', DATE '2026-03-12', 'adjustment', 'K71 withdrawn', 25, '00000000-0000-4000-8000-000000002384')$q$,
  '23001', 'while the credit is drawn on');
RESET ROLE;
-- The move's own guard, behind the ledger's: the withdrawal planted past it.
ALTER TABLE public.account_ledger DISABLE TRIGGER enforce_ledger_reversal;
INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reverses_ledger_entry_id) VALUES
  ('00000000-0000-4000-8000-000000002385', '00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c1', DATE '2026-03-12', 'adjustment', 'K71 withdrawn', 25, '00000000-0000-4000-8000-000000002384');
ALTER TABLE public.account_ledger ENABLE ALWAYS TRIGGER enforce_ledger_reversal;
SET ROLE tally_app;
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000023b1', true);
SELECT pg_temp.refuses_at('M3h2 a credit is voided only when nothing of it is drawn on (K71 paid 25 of I2)',
  $q$UPDATE public.customer_credits SET status = 'voided', status_cause_id = '00000000-0000-4000-8000-000000002385' WHERE id = '00000000-0000-4000-8000-000000002371'$q$,
  '23001', 'cannot be voided while');
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
  '23514', 'a reversal has the opposite sign of the entry it names');
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
-- void(): void_invoice's result, or its error as {"error": ...}.
CREATE FUNCTION pg_temp.void(p_inv uuid, p_code text, p_ack boolean) RETURNS jsonb LANGUAGE plpgsql AS $$
BEGIN
  RETURN public.void_invoice(p_inv, '00000000-0000-4000-8000-0000000023b1', p_code, NULL, p_ack);
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'caught SQLSTATE=% message=%', SQLSTATE, SQLERRM;
  RAISE NOTICE 'void of % refused: %', p_inv, SQLERRM;
  RETURN jsonb_build_object('error', SQLERRM);
END $$;
GRANT EXECUTE ON FUNCTION pg_temp.void(uuid, text, boolean) TO tally_app;
SET ROLE tally_app;
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000023b1', true);
SELECT pg_temp.ok('X3 the void reverses the 60 left of the charge, not -(amount_due), and names it',
  (SELECT (r ->> 'reversal_amount')::numeric = -60 AND (r ->> 'reverses_ledger_entry_id')::uuid = '00000000-0000-4000-8000-000000002395'
     FROM pg_temp.void('00000000-0000-4000-8000-000000002303', 'wrong_rate', true) r));
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
  (SELECT (r ->> 'reversal_amount') IS NULL AND (r ->> 'ledger_entry_id') IS NULL AND (r ->> 'error') IS NULL
     FROM pg_temp.void('00000000-0000-4000-8000-000000002302', 'duplicate', false) r));
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
    RAISE NOTICE 'caught SQLSTATE=% message=%', SQLSTATE, SQLERRM;
    v_state := SQLSTATE; v_msg := SQLERRM;
  END;
  SET CONSTRAINTS enforce_invoice_line_class DEFERRED;
  IF v_state = '23514' AND strpos(v_msg, 'its one-off charge') > 0 THEN
    RAISE NOTICE 'PASS LC1 a line classed against its one-off charge wrongly is refused at issue (%)', left(v_msg, 120);
  ELSE
    RAISE EXCEPTION 'FAIL LC1: got % (%)', v_state, v_msg;
  END IF;
END $$;
SELECT pg_temp.refuses_at('LC2 every line carries a class (NOT NULL; no assumed default)',
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


-- ============================================================== R r2: round 1's findings
-- Ids 24xx. I6 (…2406): an issued bill of C1, lines 2411 gas 60, 2412 add-on
-- 40, 2413 credit -10. Each check names the finding it answers.
SELECT pg_temp.bill('00000000-0000-4000-8000-000000002406', 'B23-I6', '00000000-0000-4000-8000-0000000023c1', '00000000-0000-4000-8000-0000000023d1',
                    '00000000-0000-4000-8000-000000002411', '00000000-0000-4000-8000-000000002412', '00000000-0000-4000-8000-000000002413');
SET ROLE tally_app;
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000023b1', true);
-- Births (Fable S3; Opus B2 O1).
SELECT pg_temp.refuses_at('R1 a payment is born pending: not posted with no posting entry',
  $q$INSERT INTO public.payments (tenant_id, payment_number, customer_id, payment_date, amount, payment_method, status)
     VALUES ('00000000-0000-4000-8000-0000000023a1', 'B23-PB1', '00000000-0000-4000-8000-0000000023c1', DATE '2026-03-10', 10, 'check', 'posted')$q$,
  '23514', 'is born posted');
SELECT pg_temp.refuses_at('R1b nor refunded or nsf with no cause',
  $q$INSERT INTO public.payments (tenant_id, payment_number, customer_id, payment_date, amount, payment_method, status)
     VALUES ('00000000-0000-4000-8000-0000000023a1', 'B23-PB2', '00000000-0000-4000-8000-0000000023c1', DATE '2026-03-10', 10, 'check', 'refunded')$q$,
  '23514', 'is born refunded');
SELECT pg_temp.refuses_at('R1c a credit is born active',
  $q$INSERT INTO public.customer_credits (tenant_id, customer_id, origin_type, original_amount, issued_date, status)
     VALUES ('00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c1', 'goodwill', 1, DATE '2026-03-10', 'voided')$q$,
  '23514', 'is born voided');
SELECT pg_temp.ok('R1d payments.status defaults to pending',
  (SELECT column_default = '''pending''::text' FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'payments' AND column_name = 'status'));
-- P2461 (C1, 30), P2462 (C1, 25), P2463 (C1, 20), P2464 (C1, 40), P2465 (C1, 10, stays pending).
INSERT INTO public.payments (id, tenant_id, payment_number, customer_id, payment_date, amount, payment_method) VALUES
  ('00000000-0000-4000-8000-000000002461', '00000000-0000-4000-8000-0000000023a1', 'B23-Q1', '00000000-0000-4000-8000-0000000023c1', DATE '2026-03-10', 30, 'check'),
  ('00000000-0000-4000-8000-000000002462', '00000000-0000-4000-8000-0000000023a1', 'B23-Q2', '00000000-0000-4000-8000-0000000023c1', DATE '2026-03-10', 25, 'check'),
  ('00000000-0000-4000-8000-000000002463', '00000000-0000-4000-8000-0000000023a1', 'B23-Q3', '00000000-0000-4000-8000-0000000023c1', DATE '2026-03-10', 20, 'check'),
  ('00000000-0000-4000-8000-000000002464', '00000000-0000-4000-8000-0000000023a1', 'B23-Q4', '00000000-0000-4000-8000-0000000023c1', DATE '2026-03-10', 40, 'check'),
  ('00000000-0000-4000-8000-000000002465', '00000000-0000-4000-8000-0000000023a1', 'B23-Q5', '00000000-0000-4000-8000-0000000023c1', DATE '2026-03-10', 10, 'check');
-- Posted by the wrong kind of row (Codex B4).
INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reference_type, reference_id) VALUES
  ('00000000-0000-4000-8000-000000002480', '00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c1', DATE '2026-03-10', 'adjustment', 'Q1 as an adjustment', -30, 'payment', '00000000-0000-4000-8000-000000002461');
SELECT pg_temp.refuses_at('R2 a payment is posted by a payment row, not an adjustment of its amount (Codex B4)',
  $q$UPDATE public.payments SET status = 'posted', status_cause_id = '00000000-0000-4000-8000-000000002480' WHERE id = '00000000-0000-4000-8000-000000002461'$q$,
  '23503', 'of type payment');
SELECT pg_temp.post('00000000-0000-4000-8000-000000002461', '00000000-0000-4000-8000-000000002481');
SELECT pg_temp.post('00000000-0000-4000-8000-000000002462', '00000000-0000-4000-8000-000000002482');
SELECT pg_temp.post('00000000-0000-4000-8000-000000002463', '00000000-0000-4000-8000-000000002483');
SELECT pg_temp.post('00000000-0000-4000-8000-000000002464', '00000000-0000-4000-8000-000000002484');
-- Ending a payment: the whole posting entry undone (Opus B2 O3).
INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reference_type, reference_id, reverses_ledger_entry_id) VALUES
  ('00000000-0000-4000-8000-000000002485', '00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c1', DATE '2026-03-11', 'nsf', 'Q1 returned in part', 1, 'payment', '00000000-0000-4000-8000-000000002461', '00000000-0000-4000-8000-000000002481');
SELECT pg_temp.refuses_at('R3 a 1.00 nsf row does not end a 30.00 payment (Opus B2 O3)',
  $q$UPDATE public.payments SET status = 'nsf', nsf_date = DATE '2026-03-11', status_cause_id = '00000000-0000-4000-8000-000000002485' WHERE id = '00000000-0000-4000-8000-000000002461'$q$,
  '23503', 'which then has nothing left');
SELECT pg_temp.refuses_at('R3b and the payment gives no money while any of its posting entry is undone',
  $q$INSERT INTO public.invoice_applications (tenant_id, customer_id, invoice_id, invoice_line_item_id, payment_id, amount, applied_on, basis, applied_by, reason)
     VALUES ('00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c1', '00000000-0000-4000-8000-000000002406', '00000000-0000-4000-8000-000000002411',
             '00000000-0000-4000-8000-000000002461', 5, DATE '2026-03-11', 'operator_override', '00000000-0000-4000-8000-0000000023b1', 'x')$q$,
  '23514', 'its money is not on the ledger');
INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reference_type, reference_id, reverses_ledger_entry_id) VALUES
  ('00000000-0000-4000-8000-000000002486', '00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c1', DATE '2026-03-11', 'nsf', 'Q1 returned, the rest', 29, 'payment', '00000000-0000-4000-8000-000000002461', '00000000-0000-4000-8000-000000002481');
SELECT pg_temp.admits('R3c the rest returned, the move to nsf names an nsf row and nothing is left',
  $q$UPDATE public.payments SET status = 'nsf', nsf_date = DATE '2026-03-11', status_cause_id = '00000000-0000-4000-8000-000000002486' WHERE id = '00000000-0000-4000-8000-000000002461'$q$);
SELECT pg_temp.ok('R3d the move''s time is the database''s',
  (SELECT status_recorded_at = now() FROM public.payments WHERE id = '00000000-0000-4000-8000-000000002461'));
SELECT pg_temp.refuses_at('R3e and is never written by a caller',
  $q$UPDATE public.payments SET status_recorded_at = now() - interval '1 day' WHERE id = '00000000-0000-4000-8000-000000002461'$q$,
  '23001', 'change only with the status');
-- reversed: a reversal of the posting entry that leaves nothing (Fable S6).
-- R4: an nsf row wholly undoing Q2's own posting entry is still not a
-- reversal (rolled back).
DO $$
DECLARE v_state text; v_msg text;
BEGIN
  BEGIN
    INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reference_type, reference_id, reverses_ledger_entry_id) VALUES
      ('00000000-0000-4000-8000-00000000249f', '00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c1', DATE '2026-03-11', 'nsf', 'Q2 returned', 25, 'payment',
       '00000000-0000-4000-8000-000000002462', '00000000-0000-4000-8000-000000002482');
    UPDATE public.payments SET status = 'reversed', status_cause_id = '00000000-0000-4000-8000-00000000249f' WHERE id = '00000000-0000-4000-8000-000000002462';
    RAISE EXCEPTION USING ERRCODE = 'P0099', MESSAGE = 'admitted';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'caught SQLSTATE=% message=%', SQLSTATE, SQLERRM;
    v_state := SQLSTATE; v_msg := SQLERRM;
  END;
  IF v_state = '23503' AND strpos(v_msg, 'not nsf') > 0 THEN
    RAISE NOTICE 'PASS R4 reversed names a reversal that is not an nsf (an nsf row wholly undoing its own posting entry is refused)';
  ELSE
    RAISE EXCEPTION 'FAIL R4 reversed names a reversal that is not an nsf: got % (%)', v_state, v_msg;
  END IF;
END $$;
INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reverses_ledger_entry_id) VALUES
  ('00000000-0000-4000-8000-000000002487', '00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c1', DATE '2026-03-11', 'adjustment', 'Q2 keyed to the wrong customer', 25, '00000000-0000-4000-8000-000000002482');
SELECT pg_temp.refuses_at('R4a nor another payment''s nsf row',
  $q$UPDATE public.payments SET status = 'reversed', status_cause_id = '00000000-0000-4000-8000-000000002486' WHERE id = '00000000-0000-4000-8000-000000002462'$q$,
  '23503', 'not nsf');
SELECT pg_temp.admits('R4b reversed, naming the adjustment that undoes its posting entry',
  $q$UPDATE public.payments SET status = 'reversed', status_cause_id = '00000000-0000-4000-8000-000000002487' WHERE id = '00000000-0000-4000-8000-000000002462'$q$);
SELECT pg_temp.admits('R4c a pending payment is voided, naming nothing',
  $q$UPDATE public.payments SET status = 'voided' WHERE id = '00000000-0000-4000-8000-000000002465'$q$);
-- The ledger types that may name an entry (Fable S7), and no future undo (Opus S2).
SELECT pg_temp.refuses_at('R5 a payment row does not "reverse" a charge (Fable S7)',
  $q$INSERT INTO public.account_ledger (tenant_id, customer_id, transaction_date, transaction_type, description, amount, reference_type, reference_id, reverses_ledger_entry_id)
     VALUES ('00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c2', DATE '2026-03-11', 'payment', 'x', -10, 'payment', '00000000-0000-4000-8000-000000002463', '00000000-0000-4000-8000-000000002391')$q$,
  '23514', 'account_ledger_reversal_types_only_check');
SELECT pg_temp.refuses_at('R5b a reversal is not dated after today (Opus S2)',
  $q$INSERT INTO public.account_ledger (tenant_id, customer_id, transaction_date, transaction_type, description, amount, reverses_ledger_entry_id)
     VALUES ('00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c2', CURRENT_DATE + 30, 'adjustment', 'x', -1, '00000000-0000-4000-8000-000000002391')$q$,
  '23514', 'after today');
-- A credit names a payment only as an overpayment credit (Fable B1).
SELECT pg_temp.refuses_at('R6 a goodwill credit naming a payment is refused: it would spend the payment twice (Fable B1)',
  $q$INSERT INTO public.customer_credits (tenant_id, customer_id, origin_type, original_amount, issued_date, source_payment_id)
     VALUES ('00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c1', 'goodwill', 20, DATE '2026-03-11', '00000000-0000-4000-8000-000000002463')$q$,
  '23514', 'customer_credits_payment_overpayment_check');
SELECT pg_temp.refuses_at('R6b an approval is signed by the tenant''s own user (Opus S4)',
  $q$INSERT INTO public.customer_credit_approvals (tenant_id, customer_id, payment_id, amount, approved_by)
     VALUES ('00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c1', '00000000-0000-4000-8000-000000002463', 5, '00000000-0000-4000-8000-0000000023b2')$q$,
  '23503', 'customer_credit_approvals_approved_by_fkey');
-- A voided overpayment credit stops drawing on its payment (Fable S1).
INSERT INTO public.customer_credit_approvals (id, tenant_id, customer_id, payment_id, amount, approved_by)
VALUES ('00000000-0000-4000-8000-000000002451', '00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c1', '00000000-0000-4000-8000-000000002463', 20, '00000000-0000-4000-8000-0000000023b1');
INSERT INTO public.customer_credits (id, tenant_id, customer_id, origin_type, original_amount, issued_date, source_payment_id, approval_id)
VALUES ('00000000-0000-4000-8000-000000002471', '00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c1', 'overpayment', 20, DATE '2026-03-11', '00000000-0000-4000-8000-000000002463', '00000000-0000-4000-8000-000000002451');
SELECT pg_temp.refuses_at('R7 while the credit holds Q3''s 20, Q3 refunds nothing',
  $q$INSERT INTO public.payments (tenant_id, payment_number, customer_id, payment_date, amount, payment_method, refunds_payment_id)
     VALUES ('00000000-0000-4000-8000-0000000023a1', 'B23-QR1', '00000000-0000-4000-8000-0000000023c1', DATE '2026-03-12', -1, 'refund', '00000000-0000-4000-8000-000000002463')$q$,
  '23514', 'more than its 20');
SELECT pg_temp.admits('R7b an overpayment credit posts no ledger row, so its void names nothing',
  $q$UPDATE public.customer_credits SET status = 'voided' WHERE id = '00000000-0000-4000-8000-000000002471'$q$);
SELECT pg_temp.admits('R7c the voided credit no longer holds Q3''s money: Q3 refunds 20',
  $q$INSERT INTO public.payments (id, tenant_id, payment_number, customer_id, payment_date, amount, payment_method, refunds_payment_id)
     VALUES ('00000000-0000-4000-8000-000000002466', '00000000-0000-4000-8000-0000000023a1', 'B23-QR2', '00000000-0000-4000-8000-0000000023c1', DATE '2026-03-12', -20, 'refund', '00000000-0000-4000-8000-000000002463')$q$);
SELECT pg_temp.ok('R7d Q3''s position: no credit, 20 refunded, nothing left',
  (SELECT credited = 0 AND refunded = 20 AND remaining = 0 FROM public.payment_position_as_of('00000000-0000-4000-8000-000000002463', DATE '2026-12-31', clock_timestamp())));
-- Undo and refund on a refunded payment (Opus B3).
SELECT pg_temp.admits('R8 Q4 (40) pays 15 of I6''s gas line',
  $q$INSERT INTO public.invoice_applications (id, tenant_id, customer_id, invoice_id, invoice_line_item_id, payment_id, amount, applied_on, basis, applied_by, reason)
     VALUES ('00000000-0000-4000-8000-000000002441', '00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c1', '00000000-0000-4000-8000-000000002406', '00000000-0000-4000-8000-000000002411',
             '00000000-0000-4000-8000-000000002464', 15, DATE '2026-03-11', 'operator_override', '00000000-0000-4000-8000-0000000023b1', 'x')$q$);
INSERT INTO public.payments (id, tenant_id, payment_number, customer_id, payment_date, amount, payment_method, refunds_payment_id)
VALUES ('00000000-0000-4000-8000-000000002467', '00000000-0000-4000-8000-0000000023a1', 'B23-QR3', '00000000-0000-4000-8000-0000000023c1', DATE '2026-03-12', -25, 'refund', '00000000-0000-4000-8000-000000002464');
SELECT pg_temp.admits('R8b Q4 refunded: 15 applied and 25 refunded leave nothing',
  $q$UPDATE public.payments SET status = 'refunded', status_cause_id = '00000000-0000-4000-8000-000000002467' WHERE id = '00000000-0000-4000-8000-000000002464'$q$);
SELECT pg_temp.refuses_at('R8c an undo does not bring money back to a refunded payment (Opus B3 O4b)',
  $q$INSERT INTO public.invoice_applications (tenant_id, customer_id, invoice_id, invoice_line_item_id, payment_id, amount, applied_on, basis, undoes_application_id, applied_by, reason)
     VALUES ('00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c1', '00000000-0000-4000-8000-000000002406', '00000000-0000-4000-8000-000000002411',
             '00000000-0000-4000-8000-000000002464', -15, DATE '2026-03-12', 'undo', '00000000-0000-4000-8000-000000002441', '00000000-0000-4000-8000-0000000023b1', 'x')$q$,
  '23514', 'an undo only while its source has not ended');
SELECT pg_temp.refuses_at('R8d nor is the refund it names voided (Opus B3 O4c)',
  $q$UPDATE public.payments SET status = 'voided' WHERE id = '00000000-0000-4000-8000-000000002467'$q$,
  '23001', 'would be ended with money on it');
-- Q9 (C1, 10) posted; a refund of it, voided before it went out.
INSERT INTO public.payments (id, tenant_id, payment_number, customer_id, payment_date, amount, payment_method) VALUES
  ('00000000-0000-4000-8000-000000002469', '00000000-0000-4000-8000-0000000023a1', 'B23-Q9', '00000000-0000-4000-8000-0000000023c1', DATE '2026-03-10', 10, 'check');
SELECT pg_temp.post('00000000-0000-4000-8000-000000002469', '00000000-0000-4000-8000-000000002489');
INSERT INTO public.payments (id, tenant_id, payment_number, customer_id, payment_date, amount, payment_method, refunds_payment_id)
VALUES ('00000000-0000-4000-8000-00000000246a', '00000000-0000-4000-8000-0000000023a1', 'B23-QR9', '00000000-0000-4000-8000-0000000023c1', DATE '2026-03-12', -10, 'refund', '00000000-0000-4000-8000-000000002469');
UPDATE public.payments SET status = 'voided' WHERE id = '00000000-0000-4000-8000-00000000246a';
SELECT pg_temp.refuses_at('R8e a refunded move names a refund still standing, not a voided one (Fable S4)',
  $q$UPDATE public.payments SET status = 'refunded', status_cause_id = '00000000-0000-4000-8000-00000000246a' WHERE id = '00000000-0000-4000-8000-000000002469'$q$,
  '23503', 'pending or posted');
-- Credits: refund, donation, escheat, and the void of a goodwill credit (Codex B1, B4; Fable S6).
INSERT INTO public.customer_credits (id, tenant_id, customer_id, origin_type, original_amount, issued_date) VALUES
  ('00000000-0000-4000-8000-000000002472', '00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c1', 'goodwill', 30, DATE '2026-03-10'),
  ('00000000-0000-4000-8000-000000002473', '00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c1', 'goodwill', 100, DATE '2026-03-10'),
  ('00000000-0000-4000-8000-000000002474', '00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c1', 'goodwill', 15, DATE '2026-03-10'),
  ('00000000-0000-4000-8000-000000002475', '00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c1', 'goodwill', 10, DATE '2026-03-10'),
  ('00000000-0000-4000-8000-000000002476', '00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c1', 'goodwill', 12, DATE '2026-03-10');
INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reference_type, reference_id) VALUES
  ('00000000-0000-4000-8000-000000002492', '00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c1', DATE '2026-03-10', 'credit_issued', 'K2', -30, 'customer_credit', '00000000-0000-4000-8000-000000002472'),
  ('00000000-0000-4000-8000-000000002493', '00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c1', DATE '2026-03-10', 'credit_issued', 'K3', -100, 'customer_credit', '00000000-0000-4000-8000-000000002473'),
  ('00000000-0000-4000-8000-000000002494', '00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c1', DATE '2026-03-10', 'credit_issued', 'K4', -15, 'customer_credit', '00000000-0000-4000-8000-000000002474'),
  ('00000000-0000-4000-8000-000000002495', '00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c1', DATE '2026-03-10', 'credit_issued', 'K5', -10, 'customer_credit', '00000000-0000-4000-8000-000000002475');
SELECT pg_temp.refuses_at('R9 a credit with no credit_issued entry gives no money (K6, Opus B2)',
  $q$INSERT INTO public.invoice_applications (tenant_id, customer_id, invoice_id, invoice_line_item_id, customer_credit_id, amount, applied_on, basis, applied_by, reason)
     VALUES ('00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c1', '00000000-0000-4000-8000-000000002406', '00000000-0000-4000-8000-000000002412',
             '00000000-0000-4000-8000-000000002476', 1, DATE '2026-03-11', 'operator_override', '00000000-0000-4000-8000-0000000023b1', 'x')$q$,
  '23514', 'its money is not on the ledger');
SELECT pg_temp.refuses_at('R10 a credit refunds no more than it is (K2: 31 of 30; Fable S6)',
  $q$INSERT INTO public.payments (tenant_id, payment_number, customer_id, payment_date, amount, payment_method, refunds_customer_credit_id)
     VALUES ('00000000-0000-4000-8000-0000000023a1', 'B23-KR1', '00000000-0000-4000-8000-0000000023c1', DATE '2026-03-12', -31, 'refund', '00000000-0000-4000-8000-000000002472')$q$,
  '23514', 'more than its 30');
SELECT pg_temp.admits('R10b K2 refunded in full',
  $q$INSERT INTO public.payments (id, tenant_id, payment_number, customer_id, payment_date, amount, payment_method, refunds_customer_credit_id)
     VALUES ('00000000-0000-4000-8000-000000002468', '00000000-0000-4000-8000-0000000023a1', 'B23-KR2', '00000000-0000-4000-8000-0000000023c1', DATE '2026-03-12', -30, 'refund', '00000000-0000-4000-8000-000000002472')$q$);
SELECT pg_temp.admits('R10c K2 moves to refunded, naming it',
  $q$UPDATE public.customer_credits SET status = 'refunded', status_cause_id = '00000000-0000-4000-8000-000000002468' WHERE id = '00000000-0000-4000-8000-000000002472'$q$);
SELECT pg_temp.refuses_at('R10d the refund a refunded credit rests on is not voided (Opus B3)',
  $q$UPDATE public.payments SET status = 'voided' WHERE id = '00000000-0000-4000-8000-000000002468'$q$,
  '23001', 'would be ended with money on it');
SELECT pg_temp.admits('R11 K3 (100) donated in full: the donation is a draw on it',
  $q$INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reference_type, reference_id)
     VALUES ('00000000-0000-4000-8000-000000002496', '00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c1', DATE '2026-03-12', 'donation', 'K3 to the fund', 100, 'customer_credit', '00000000-0000-4000-8000-000000002473')$q$);
SELECT pg_temp.refuses_at('R11b nothing is refunded after a full donation (Codex B1)',
  $q$INSERT INTO public.payments (tenant_id, payment_number, customer_id, payment_date, amount, payment_method, refunds_customer_credit_id)
     VALUES ('00000000-0000-4000-8000-0000000023a1', 'B23-KR3', '00000000-0000-4000-8000-0000000023c1', DATE '2026-03-12', -1, 'refund', '00000000-0000-4000-8000-000000002473')$q$,
  '23514', 'more than its 100');
SELECT pg_temp.admits('R11c K3 moves to donated, naming the donation, nothing left',
  $q$UPDATE public.customer_credits SET status = 'donated', status_cause_id = '00000000-0000-4000-8000-000000002496' WHERE id = '00000000-0000-4000-8000-000000002473'$q$);
SELECT pg_temp.admits('R11d K4 (15): a donation of 1',
  $q$INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reference_type, reference_id)
     VALUES ('00000000-0000-4000-8000-000000002497', '00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c1', DATE '2026-03-12', 'donation', 'K4 in part', 1, 'customer_credit', '00000000-0000-4000-8000-000000002474')$q$);
SELECT pg_temp.refuses_at('R11e a donation of 1 does not end a credit with 14 left (Codex B1)',
  $q$UPDATE public.customer_credits SET status = 'donated', status_cause_id = '00000000-0000-4000-8000-000000002497' WHERE id = '00000000-0000-4000-8000-000000002474'$q$,
  '23001', 'only when nothing of it is left');
SELECT pg_temp.refuses_at('R11f a donation of a credit is more than 0',
  $q$INSERT INTO public.account_ledger (tenant_id, customer_id, transaction_date, transaction_type, description, amount, reference_type, reference_id)
     VALUES ('00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c1', DATE '2026-03-12', 'donation', 'x', -1, 'customer_credit', '00000000-0000-4000-8000-000000002474')$q$,
  '23514', 'more than 0');
SELECT pg_temp.admits('R12 K5 (10): a dormancy flag is recorded',
  $q$INSERT INTO public.escheatment_events (id, tenant_id, customer_credit_id, customer_id, event_type)
     VALUES ('00000000-0000-4000-8000-0000000024e1', '00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-000000002475', '00000000-0000-4000-8000-0000000023c1', 'dormancy_flag')$q$);
SELECT pg_temp.refuses_at('R12b a dormancy flag is not an escheat (Codex B4)',
  $q$UPDATE public.customer_credits SET status = 'escheated', status_cause_id = '00000000-0000-4000-8000-0000000024e1' WHERE id = '00000000-0000-4000-8000-000000002475'$q$,
  '23503', 'escheated_to_state');
SELECT pg_temp.refuses_at('R12c a remittance carries its amount',
  $q$INSERT INTO public.escheatment_events (tenant_id, customer_credit_id, customer_id, event_type)
     VALUES ('00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-000000002475', '00000000-0000-4000-8000-0000000023c1', 'escheated_to_state')$q$,
  '23514', 'carries the amount remitted');
SELECT pg_temp.refuses_at('R12d and remits no more than is left (11 of 10)',
  $q$INSERT INTO public.escheatment_events (tenant_id, customer_credit_id, customer_id, event_type, amount_related)
     VALUES ('00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-000000002475', '00000000-0000-4000-8000-0000000023c1', 'escheated_to_state', 11)$q$,
  '23514', 'more than its 10');
SELECT pg_temp.admits('R12e the remittance of 10',
  $q$INSERT INTO public.escheatment_events (id, tenant_id, customer_credit_id, customer_id, event_type, amount_related)
     VALUES ('00000000-0000-4000-8000-0000000024e2', '00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-000000002475', '00000000-0000-4000-8000-0000000023c1', 'escheated_to_state', 10)$q$);
SELECT pg_temp.admits('R12f K5 moves to escheated, naming its remittance',
  $q$UPDATE public.customer_credits SET status = 'escheated', status_cause_id = '00000000-0000-4000-8000-0000000024e2' WHERE id = '00000000-0000-4000-8000-000000002475'$q$);
SELECT pg_temp.ok('R12g K5''s position: 10 given up, nothing left',
  (SELECT given_up = 10 AND remaining = 0 FROM public.customer_credit_position_as_of('00000000-0000-4000-8000-000000002475', DATE '2026-12-31', clock_timestamp())));
-- K6 (12): issued, then withdrawn in part, then in full (Opus B2; Fable S6).
INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reference_type, reference_id) VALUES
  ('00000000-0000-4000-8000-0000000024a6', '00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c1', DATE '2026-03-10', 'credit_issued', 'K6', -12, 'customer_credit', '00000000-0000-4000-8000-000000002476');
INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reverses_ledger_entry_id) VALUES
  ('00000000-0000-4000-8000-0000000024a7', '00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c1', DATE '2026-03-12', 'adjustment', 'K6 withdrawn in part', 4, '00000000-0000-4000-8000-0000000024a6');
SELECT pg_temp.refuses_at('R13 a credit is voided only when its credit_issued entry is wholly reversed (4 of 12)',
  $q$UPDATE public.customer_credits SET status = 'voided', status_cause_id = '00000000-0000-4000-8000-0000000024a7' WHERE id = '00000000-0000-4000-8000-000000002476'$q$,
  '23503', 'which then has nothing left');
INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reverses_ledger_entry_id) VALUES
  ('00000000-0000-4000-8000-0000000024a8', '00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c1', DATE '2026-03-12', 'adjustment', 'K6 withdrawn, the rest', 8, '00000000-0000-4000-8000-0000000024a6');
SELECT pg_temp.admits('R13b and voided once it is',
  $q$UPDATE public.customer_credits SET status = 'voided', status_cause_id = '00000000-0000-4000-8000-0000000024a8' WHERE id = '00000000-0000-4000-8000-000000002476'$q$);
-- A restricted payment's target (Fable S6).
SELECT pg_temp.refuses_at('R14 a restricted payment says restriction only for its target line (P4, restricted to I2''s add-on, on I1''s gas line)',
  $q$INSERT INTO public.invoice_applications (tenant_id, customer_id, invoice_id, invoice_line_item_id, payment_id, amount, applied_on, basis, allocation_tariff_id)
     VALUES ('00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c1', '00000000-0000-4000-8000-000000002406', '00000000-0000-4000-8000-000000002411',
             '00000000-0000-4000-8000-000000002364', 1, DATE '2026-03-11', 'restriction', '00000000-0000-4000-8000-0000000023ab')$q$,
  '23514', 'restriction is a restricted payment');
-- Several rows in one statement (Fable S6): the cap sees them all.
INSERT INTO public.payments (id, tenant_id, payment_number, customer_id, payment_date, amount, payment_method) VALUES
  ('00000000-0000-4000-8000-00000000246b', '00000000-0000-4000-8000-0000000023a1', 'B23-QB', '00000000-0000-4000-8000-0000000023c1', DATE '2026-03-10', 100, 'check');
SELECT pg_temp.post('00000000-0000-4000-8000-00000000246b', '00000000-0000-4000-8000-00000000248b');
SELECT pg_temp.refuses_at('R15 two applications in one INSERT that together pass the line (35 + 30 of 60)',
  $q$INSERT INTO public.invoice_applications (tenant_id, customer_id, invoice_id, invoice_line_item_id, payment_id, amount, applied_on, basis, applied_by, reason)
     VALUES ('00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c1', '00000000-0000-4000-8000-000000002406', '00000000-0000-4000-8000-000000002411',
             '00000000-0000-4000-8000-00000000246b', 35, DATE '2026-03-11', 'operator_override', '00000000-0000-4000-8000-0000000023b1', 'x'),
            ('00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c1', '00000000-0000-4000-8000-000000002406', '00000000-0000-4000-8000-000000002411',
             '00000000-0000-4000-8000-00000000246b', 30, DATE '2026-03-11', 'operator_override', '00000000-0000-4000-8000-0000000023b1', 'x')$q$,
  '23514', 'more than the line''s');
SELECT pg_temp.refuses_at('R15b and through a writable CTE',
  $q$WITH a AS (INSERT INTO public.invoice_applications (tenant_id, customer_id, invoice_id, invoice_line_item_id, payment_id, amount, applied_on, basis, applied_by, reason)
     VALUES ('00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c1', '00000000-0000-4000-8000-000000002406', '00000000-0000-4000-8000-000000002411',
             '00000000-0000-4000-8000-00000000246b', 35, DATE '2026-03-11', 'operator_override', '00000000-0000-4000-8000-0000000023b1', 'x') RETURNING 1)
     INSERT INTO public.invoice_applications (tenant_id, customer_id, invoice_id, invoice_line_item_id, payment_id, amount, applied_on, basis, applied_by, reason)
     SELECT '00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c1', '00000000-0000-4000-8000-000000002406', '00000000-0000-4000-8000-000000002411',
            '00000000-0000-4000-8000-00000000246b', 30, DATE '2026-03-11', 'operator_override', '00000000-0000-4000-8000-0000000023b1', 'x' FROM a$q$,
  '23514', 'more than the line''s');
RESET ROLE;
-- Positions at fixed coordinates (Codex B3; Opus B3).
SELECT pg_temp.ok('R16 a draft bill''s line has no position (Codex B3)',
  NOT EXISTS (SELECT 1 FROM public.invoice_line_position_as_of('00000000-0000-4000-8000-00000000231a', DATE '2026-12-31', clock_timestamp())));
SELECT pg_temp.ok('R16b nor an issued bill before it was issued (I1, issued three hours ago, read four hours back)',
  NOT EXISTS (SELECT 1 FROM public.invoice_line_position_as_of('00000000-0000-4000-8000-000000002311', DATE '2026-12-31', now() - interval '4 hours'))
  AND NOT EXISTS (SELECT 1 FROM public.invoice_position_as_of('00000000-0000-4000-8000-000000002301', DATE '2026-12-31', now() - interval '4 hours')));
SELECT pg_temp.ok('R16c nor before its invoice date (I1, read on February 28)',
  NOT EXISTS (SELECT 1 FROM public.invoice_position_as_of('00000000-0000-4000-8000-000000002301', DATE '2026-02-28', clock_timestamp())));
-- A history load: QH (C1, 50) recorded five hours ago; a refund of 20
-- recorded four hours ago, voided two hours ago.
INSERT INTO public.payments (id, tenant_id, payment_number, customer_id, payment_date, amount, payment_method, created_at) VALUES
  ('00000000-0000-4000-8000-00000000246c', '00000000-0000-4000-8000-0000000023a1', 'B23-QH', '00000000-0000-4000-8000-0000000023c1', DATE '2026-03-10', 50, 'check', now() - interval '5 hours');
INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reference_type, reference_id, created_at) VALUES
  ('00000000-0000-4000-8000-00000000248c', '00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c1', DATE '2026-03-10', 'payment', 'QH posted', -50, 'payment', '00000000-0000-4000-8000-00000000246c', now() - interval '5 hours');
UPDATE public.payments SET status = 'posted', status_cause_id = '00000000-0000-4000-8000-00000000248c', effective_date = DATE '2026-03-10', effective_date_method = 'other', status_recorded_at = now() - interval '5 hours' WHERE id = '00000000-0000-4000-8000-00000000246c';
INSERT INTO public.payments (id, tenant_id, payment_number, customer_id, payment_date, amount, payment_method, refunds_payment_id, created_at) VALUES
  ('00000000-0000-4000-8000-00000000246d', '00000000-0000-4000-8000-0000000023a1', 'B23-QHR', '00000000-0000-4000-8000-0000000023c1', DATE '2026-03-11', -20, 'refund', '00000000-0000-4000-8000-00000000246c', now() - interval '4 hours');
UPDATE public.payments SET status = 'voided', status_recorded_at = now() - interval '2 hours' WHERE id = '00000000-0000-4000-8000-00000000246d';
SELECT pg_temp.ok('R17 a refund voided two hours ago still counts at an instant three hours ago, and not now (Codex B3, R2 closed)',
  (SELECT refunded = 20 AND remaining = 30 FROM public.payment_position_as_of('00000000-0000-4000-8000-00000000246c', DATE '2026-12-31', now() - interval '3 hours'))
  AND (SELECT refunded = 0 AND remaining = 50 FROM public.payment_position_as_of('00000000-0000-4000-8000-00000000246c', DATE '2026-12-31', clock_timestamp())));
SELECT pg_temp.refuses_at('R18 a history row is not recorded before its source (Opus S3)',
  $q$INSERT INTO public.invoice_applications (tenant_id, customer_id, invoice_id, invoice_line_item_id, payment_id, amount, applied_on, basis, applied_by, reason, created_at)
     VALUES ('00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c1', '00000000-0000-4000-8000-000000002406', '00000000-0000-4000-8000-000000002412',
             '00000000-0000-4000-8000-00000000246b', 1, DATE '2026-03-11', 'operator_override', '00000000-0000-4000-8000-0000000023b1', 'x', now() - interval '1 day')$q$,
  '23514', 'before the payment itself');
SELECT pg_temp.refuses_at('R18b nor before its bill was issued',
  $q$INSERT INTO public.invoice_applications (tenant_id, customer_id, invoice_id, invoice_line_item_id, payment_id, amount, applied_on, basis, applied_by, reason, created_at)
     VALUES ('00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c1', '00000000-0000-4000-8000-000000002301', '00000000-0000-4000-8000-000000002311',
             '00000000-0000-4000-8000-00000000246c', 1, DATE '2026-03-11', 'operator_override', '00000000-0000-4000-8000-0000000023b1', 'x', now() - interval '4 hours')$q$,
  '23514', 'before invoice B23-I1 was issued');
-- LC3 (Fable S6): a line from a rate item is classed as the item's version
-- in force on the bill's coordinates.
INSERT INTO public.rate_items (id, tenant_id, item_code) VALUES
  ('00000000-0000-4000-8000-0000000024c1', '00000000-0000-4000-8000-0000000023a1', 'B23-GAS');
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000023b1', true);
SELECT public.assert_reference_version('rate_items', '00000000-0000-4000-8000-0000000024c1', 1);
INSERT INTO public.rate_item_versions (tenant_id, rate_item_id, item_name, service_type, calculation_type, regulatory_class, effective_date, change_type) VALUES
  ('00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000024c1', 'Gas service', 'gas', 'fixed_monthly', 'regulated', DATE '2026-01-01', 'initial');
INSERT INTO public.invoices (id, tenant_id, invoice_number, customer_id, location_id, invoice_date, billing_period, period_start, period_end, due_date, amount_due)
VALUES ('00000000-0000-4000-8000-000000002407', '00000000-0000-4000-8000-0000000023a1', 'B23-I7', '00000000-0000-4000-8000-0000000023c1', '00000000-0000-4000-8000-0000000023d1',
        DATE '2026-04-01', '2026-03', DATE '2026-03-01', DATE '2026-03-31', DATE '2026-04-20', 20.00);
INSERT INTO public.invoice_line_items (tenant_id, invoice_id, service_type, charge_type, description, amount, rate_item_id, regulatory_class) VALUES
  ('00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-000000002407', 'gas', 'base_charge', 'Gas service', 20.00, '00000000-0000-4000-8000-0000000024c1', 'unregulated');
SELECT pg_temp.snap('00000000-0000-4000-8000-000000002407', DATE '2026-03-31', now());
DO $$
DECLARE v_state text; v_msg text;
BEGIN
  BEGIN
    UPDATE public.invoices SET status = 'pending' WHERE id = '00000000-0000-4000-8000-000000002407';
    SET CONSTRAINTS enforce_invoice_line_class IMMEDIATE;
    RAISE EXCEPTION USING ERRCODE = 'P0099', MESSAGE = 'issued';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'caught SQLSTATE=% message=%', SQLSTATE, SQLERRM;
    v_state := SQLSTATE; v_msg := SQLERRM;
  END;
  SET CONSTRAINTS enforce_invoice_line_class DEFERRED;
  IF v_state = '23514' AND strpos(v_msg, 'its rate item') > 0 THEN
    RAISE NOTICE 'PASS LC3 a line classed against its rate item''s version wrongly is refused at issue (%)', left(v_msg, 120);
  ELSE
    RAISE EXCEPTION 'FAIL LC3: got % (%)', v_state, v_msg;
  END IF;
END $$;
RESET ROLE;


-- ============================================================== I invariants
-- r2 (Codex S2): each invariant is called, not folded into a constant.
DO $$ BEGIN
  PERFORM public.assert_cash_guard_invariants();
  RAISE NOTICE 'PASS I1 every -23 guard is in place, exactly';
END $$;
DO $$ BEGIN
  PERFORM public.assert_periods_guard_invariants();
  PERFORM public.assert_seal_role_invariants();
  PERFORM public.assert_tenant_isolation_invariants();
  PERFORM public.assert_rule_table_invariants();
  RAISE NOTICE 'PASS I2 the earlier invariants still hold with -23';
END $$;

ROLLBACK;
