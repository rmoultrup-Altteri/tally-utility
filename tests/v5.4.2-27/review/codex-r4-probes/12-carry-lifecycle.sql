-- AUTHOR RUN ONLY. Not executed by Codex. Run as owner on a fresh clone
-- with patch-27-frozen-r4.sql applied. No role DDL. All writes roll back.
\set ON_ERROR_STOP on
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
-- k(): the battery's ids, 00000000-0000-4000-8000-0000000027xx.
CREATE FUNCTION pg_temp.k(p text) RETURNS uuid LANGUAGE sql IMMUTABLE AS $$ SELECT ('00000000-0000-4000-8000-0000000027' || p)::uuid $$;
-- post(): a pending payment's posting entry (payment, deposit or refund,
-- dated its payment date, at minus its amount), then the move to posted.
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
-- pay(): a payment of p_cust, posted. refund(): a refund of a payment or a
-- credit, posted. bounce(): an nsf row taking back the whole of a posting
-- (or refund) entry, then the move to nsf. credit(): a goodwill credit issued
-- on the ledger.
CREATE FUNCTION pg_temp.pay(p_id uuid, p_entry uuid, p_cust uuid, p_amount numeric, p_on date, p_deposit boolean DEFAULT false) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO public.payments (id, tenant_id, payment_number, customer_id, payment_date, amount, payment_method, is_deposit)
  VALUES (p_id, '00000000-0000-4000-8000-0000000027a1', 'B27-' || right(p_id::text, 2), p_cust, p_on, p_amount, 'check', p_deposit);
  PERFORM pg_temp.post(p_id, p_entry);
END $$;
CREATE FUNCTION pg_temp.refund(p_id uuid, p_entry uuid, p_cust uuid, p_pay uuid, p_credit uuid, p_amount numeric, p_on date) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO public.payments (id, tenant_id, payment_number, customer_id, payment_date, amount, payment_method, refunds_payment_id, refunds_customer_credit_id)
  VALUES (p_id, '00000000-0000-4000-8000-0000000027a1', 'B27-' || right(p_id::text, 2) || 'R', p_cust, p_on, -p_amount, 'refund', p_pay, p_credit);
  PERFORM pg_temp.post(p_id, p_entry);
END $$;
CREATE FUNCTION pg_temp.bounce(p_pay uuid, p_entry uuid, p_row uuid, p_on date) RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_row uuid := coalesce(p_row, gen_random_uuid());
BEGIN
  INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reference_type, reference_id, reverses_ledger_entry_id)
  SELECT v_row, l.tenant_id, l.customer_id, p_on, 'nsf', 'returned', -l.amount, 'payment', l.reference_id, l.id FROM public.account_ledger l WHERE l.id = p_entry;
  UPDATE public.payments SET status = 'nsf', nsf_date = p_on, status_cause_id = v_row WHERE id = (SELECT reference_id FROM public.account_ledger WHERE id = p_entry);
END $$;
CREATE FUNCTION pg_temp.credit(p_id uuid, p_entry uuid, p_cust uuid, p_amount numeric) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO public.customer_credits (id, tenant_id, customer_id, origin_type, original_amount, issued_date)
  VALUES (p_id, '00000000-0000-4000-8000-0000000027a1', p_cust, 'goodwill', p_amount, DATE '2026-03-02');
  INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reference_type, reference_id)
  VALUES (p_entry, '00000000-0000-4000-8000-0000000027a1', p_cust, DATE '2026-03-02', 'credit_issued', 'goodwill', -p_amount, 'customer_credit', p_id);
END $$;
-- sa(): a shortfall application (tenant T1), as the caller.
CREATE FUNCTION pg_temp.sa(p_id uuid, p_cust uuid, p_target uuid, p_pay uuid, p_credit uuid, p_amount numeric, p_on date,
                           p_basis text DEFAULT 'customer_pot', p_undoes uuid DEFAULT NULL) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO public.shortfall_applications (id, tenant_id, customer_id, target_payment_id, payment_id, customer_credit_id, amount, applied_on, basis,
                                             applied_by, reason, undoes_shortfall_application_id)
  VALUES (coalesce(p_id, gen_random_uuid()), '00000000-0000-4000-8000-0000000027a1', p_cust, p_target, p_pay, p_credit, p_amount, p_on, p_basis,
          CASE WHEN p_basis <> 'customer_pot' THEN '00000000-0000-4000-8000-0000000027b1'::uuid END,
          CASE WHEN p_basis <> 'customer_pot' THEN 'battery-27' END, p_undoes);
END $$;
-- pos(): a payment's remaining and repaid, as text; crem(): a credit's remaining.
CREATE FUNCTION pg_temp.pos(p_pay uuid) RETURNS text LANGUAGE sql AS $$
  SELECT format('%s/%s', remaining, repaid) FROM public.payment_position_as_of(p_pay, DATE '2026-12-31', clock_timestamp())
$$;
CREATE FUNCTION pg_temp.crem(p_credit uuid) RETURNS numeric LANGUAGE sql AS $$
  SELECT remaining FROM public.customer_credit_position_as_of(p_credit, DATE '2026-12-31', clock_timestamp())
$$;
GRANT EXECUTE ON FUNCTION pg_temp.refuses_at(text, text, text, text), pg_temp.ok(text, boolean), pg_temp.admits(text, text), pg_temp.k(text),
  pg_temp.post(uuid, uuid), pg_temp.pay(uuid, uuid, uuid, numeric, date, boolean), pg_temp.refund(uuid, uuid, uuid, uuid, uuid, numeric, date),
  pg_temp.bounce(uuid, uuid, uuid, date), pg_temp.credit(uuid, uuid, uuid, numeric),
  pg_temp.sa(uuid, uuid, uuid, uuid, uuid, numeric, date, text, uuid), pg_temp.pos(uuid), pg_temp.crem(uuid) TO tally_app, tally_core;

-- ------------------------------------------------------------------ fixtures
-- T1 (…27a1), T2 (…27a2). Users b1 (T1), b2 (T2). Customers c1-c5 (T1), c9 (T2).
INSERT INTO public.tenants (id, name, slug) VALUES
  ('00000000-0000-4000-8000-0000000027a1', 'T1 City Gas', 'bat27-t1'),
  ('00000000-0000-4000-8000-0000000027a2', 'T2 Gasco', 'bat27-t2');
INSERT INTO public.users (id, tenant_id, display_name, email, role, is_active) VALUES
  ('00000000-0000-4000-8000-0000000027b1', '00000000-0000-4000-8000-0000000027a1', 'Op1', 'op1@bat27.test', 'operator', true),
  ('00000000-0000-4000-8000-0000000027b2', '00000000-0000-4000-8000-0000000027a2', 'Op2', 'op2@bat27.test', 'operator', true);
INSERT INTO public.customers (id, tenant_id, customer_number, customer_type) VALUES
  ('00000000-0000-4000-8000-0000000027c1', '00000000-0000-4000-8000-0000000027a1', 'B27-C1', 'residential'),
  ('00000000-0000-4000-8000-0000000027c2', '00000000-0000-4000-8000-0000000027a1', 'B27-C2', 'residential'),
  ('00000000-0000-4000-8000-0000000027c3', '00000000-0000-4000-8000-0000000027a1', 'B27-C3', 'residential'),
  ('00000000-0000-4000-8000-0000000027c4', '00000000-0000-4000-8000-0000000027a1', 'B27-C4', 'residential'),
  ('00000000-0000-4000-8000-0000000027c5', '00000000-0000-4000-8000-0000000027a1', 'B27-C5', 'residential'),
  ('00000000-0000-4000-8000-0000000027c6', '00000000-0000-4000-8000-0000000027a1', 'B27-C6', 'residential'),
  ('00000000-0000-4000-8000-0000000027c9', '00000000-0000-4000-8000-0000000027a2', 'B27-C9', 'residential');
\set c1 '''00000000-0000-4000-8000-0000000027c1'''
\set c2 '''00000000-0000-4000-8000-0000000027c2'''
\set c3 '''00000000-0000-4000-8000-0000000027c3'''

SELECT pg_temp.pay(pg_temp.k('40'), pg_temp.k('41'), :c1, 50, DATE '2026-03-10');
SELECT pg_temp.refund(pg_temp.k('42'), pg_temp.k('43'), :c1, pg_temp.k('40'), NULL, 30, DATE '2026-03-11');
SELECT pg_temp.bounce(pg_temp.k('40'), pg_temp.k('41'), pg_temp.k('44'), DATE '2026-03-12');
SELECT pg_temp.credit(pg_temp.k('45'), pg_temp.k('46'), :c1, 50);
SELECT pg_temp.sa(pg_temp.k('47'), :c1, pg_temp.k('40'), NULL, pg_temp.k('45'), 30, DATE '2026-03-13');
SELECT pg_temp.admits('E1 CE''s other 20 is sent to the state and CE is escheated',
  $q$INSERT INTO public.escheatment_events (id, tenant_id, customer_credit_id, customer_id, event_type, amount_related, event_date)
     VALUES (pg_temp.k('48'), '00000000-0000-4000-8000-0000000027a1', pg_temp.k('45'), '00000000-0000-4000-8000-0000000027c1', 'escheated_to_state', 20, '2026-03-14 12:00+00');
     UPDATE public.customer_credits SET status = 'escheated', status_cause_id = pg_temp.k('48'), escheated_at = now() WHERE id = pg_temp.k('45')$q$);
INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reverses_ledger_entry_id)
VALUES (pg_temp.k('49'), '00000000-0000-4000-8000-0000000027a1', :c1, DATE '2026-03-15', 'nsf', 'refund check returned', -30, pg_temp.k('43'));


SELECT pg_temp.sa(pg_temp.k('4a'), :c1, pg_temp.k('40'), NULL, pg_temp.k('45'), -30, DATE '2026-03-15', 'undo', pg_temp.k('47'));
UPDATE public.payments SET status='nsf', nsf_date=DATE '2026-03-15', status_cause_id=pg_temp.k('49') WHERE id=pg_temp.k('42');
INSERT INTO public.customer_credits (id,tenant_id,customer_id,origin_type,original_amount,issued_date,reissues_shortfall_application_id)
VALUES (pg_temp.k('4b'),pg_temp.k('a1'),:c1,'shortfall_reissue',30,DATE '2026-03-15',pg_temp.k('4a'));
SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;
SELECT pg_temp.refuses_at('active carry cannot end without remittance',
  $q$UPDATE public.customer_credits SET status='escheated' WHERE id=pg_temp.k('4b')$q$,
  '23503', 'status_cause_id');
SELECT pg_temp.refuses_at('active carry cannot be voided',
  $q$UPDATE public.customer_credits SET status='voided' WHERE id=pg_temp.k('4b')$q$,
  '23001', 'nothing goes back to that credit');
SAVEPOINT settled;
INSERT INTO public.escheatment_events (id,tenant_id,customer_credit_id,customer_id,event_type,amount_related,event_date)
VALUES (pg_temp.k('4e'),pg_temp.k('a1'),pg_temp.k('4b'),:c1,'escheated_to_state',30,'2026-03-16 12:00+00');
UPDATE public.customer_credits SET status='escheated',status_cause_id=pg_temp.k('4e'),escheated_at=now() WHERE id=pg_temp.k('4b');
SET CONSTRAINTS ALL IMMEDIATE;
SELECT pg_temp.ok('carry ends through checked remittance with zero remaining', pg_temp.crem(pg_temp.k('4b'))=0);
ROLLBACK TO settled;
CREATE FUNCTION pg_temp.n(p text) RETURNS uuid LANGUAGE sql IMMUTABLE AS $$ SELECT ('00000000-0000-4000-8000-0000000029' || p)::uuid $$;
GRANT EXECUTE ON FUNCTION pg_temp.n(text) TO tally_app;
INSERT INTO public.service_locations (id, tenant_id, customer_id, location_number, address_line1, city, state, zip) VALUES
  (pg_temp.n('d4'), '00000000-0000-4000-8000-0000000027a1', :c1, 'L27-X4', '4 Main', 'Austin', 'TX', '78701');
INSERT INTO public.places (id, kind_code, state_code, place_code, name, parent_place_id, effective_from, source_note)
SELECT pg_temp.n('a7'), 'municipality', 'TX', 'TX-B27-CITY', 'Battery City 27', s.id, DATE '2000-01-01', 'battery-27 fixture'
  FROM public.places s WHERE s.kind_code = 'state' AND s.state_code = 'TX';
INSERT INTO public.utility_service_profiles (tenant_id, service_type, system_kind, state_code, owner_type, commission_jurisdiction,
                                             owning_place_id, effective_from, evidence_reference, evidence_date)
VALUES ('00000000-0000-4000-8000-0000000027a1', 'gas', 'distribution', 'TX', 'municipal', false, pg_temp.n('a7'), DATE '2000-01-01', 'Battery City charter', DATE '2000-01-01');
INSERT INTO public.payment_allocation_tariffs (id, tenant_id, state_code, service_type, system_kind, effective_from, effective_to, tariff_reference, terms_kind, terms_version, terms_source)
VALUES (pg_temp.n('ab'), '00000000-0000-4000-8000-0000000027a1', 'TX', 'gas', 'distribution', DATE '2026-01-01', DATE '2026-04-01', 'City tariff 7', 'payment_allocation_tariff', 1,
        '{"citation": "City tariff 7", "within_bill": {"strategy": "charge_type_order", "version": 1, "regulated": ["base_charge", "usage_charge", "surcharge", "minimum_bill_adjustment", "tax", "late_fee", "penalty", "deposit", "adjustment", "credit", "consolidated_summary"], "unregulated": ["adhoc", "misc"]}}');
INSERT INTO public.invoices (id, tenant_id, invoice_number, customer_id, location_id, invoice_date, billing_period, period_start, period_end, due_date, amount_due)
VALUES (pg_temp.n('5a'), '00000000-0000-4000-8000-0000000027a1', 'B27-X4-I1', :c1, pg_temp.n('d4'), DATE '2026-03-01', '2026-02', DATE '2026-02-01', DATE '2026-02-28', DATE '2026-03-20', 60.00);
INSERT INTO public.invoice_line_items (id, tenant_id, invoice_id, line_order, service_type, charge_type, description, amount, rate, regulatory_class) VALUES
  (pg_temp.n('5b'), '00000000-0000-4000-8000-0000000027a1', pg_temp.n('5a'), 0, 'gas', 'base_charge', 'Gas service', 60.00, 60.00, 'regulated');
INSERT INTO public.invoice_calculation_snapshots
  (tenant_id, invoice_id, billing_run_id, valid_at, recorded_at, snapshot_schema_version, formula_version,
   rate_inputs, gas_factors, wna_inputs, tax_inputs, read_inputs, customer_inputs, period_inputs, line_items)
SELECT i.tenant_id, i.id, i.billing_run_id, DATE '2026-02-28', now(), 'v1', 'bat27',
   '{"rate_schedule_id":null,"rate_schedule_version_id":null,"rate_schedule_code":null,"customer_type":null,"partial_period_policy":null,"items":[]}',
   '{"pga_factor":null,"btu_factor":null,"pressure_factor":null,"temperature_factor":null,"meter_multiplier":null,"factor_stack_intermediates":{}}',
   '{"applied":false}', '{"jurisdictions":[],"exemptions":[],"franchise_fees":[]}', '{"reads":[]}',
   jsonb_build_object('customer_id', i.customer_id, 'customer_class', null, 'location_id', i.location_id, 'premise_zones', '{}'::jsonb),
   jsonb_build_object('period_start', i.period_start, 'period_end', i.period_end, 'days_in_period', i.period_end - i.period_start + 1, 'proration_policy', null),
   (SELECT coalesce(jsonb_agg(jsonb_build_object('invoice_line_item_id', l.id, 'charge_type', l.charge_type, 'amount', l.amount)), '[]'::jsonb)
      FROM public.invoice_line_items l WHERE l.invoice_id = i.id)
  FROM public.invoices i WHERE i.id = pg_temp.n('5a');
UPDATE public.invoices SET status = 'pending' WHERE id = pg_temp.n('5a');
UPDATE public.invoices SET first_issued_at = now() - interval '3 hours' WHERE id = pg_temp.n('5a');
SET ROLE tally_app;
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000027b1', true);

SELECT pg_temp.admits('carry pays a real bill through invoice writer',
$q$INSERT INTO public.invoice_applications (id,tenant_id,customer_id,invoice_id,invoice_line_item_id,customer_credit_id,amount,applied_on,basis,allocation_tariff_id)
VALUES (pg_temp.n('53'),pg_temp.k('a1'),pg_temp.k('c1'),pg_temp.n('5a'),pg_temp.n('5b'),pg_temp.k('4b'),20,DATE '2026-03-16','oldest_first',pg_temp.n('ab'))$q$);
SELECT pg_temp.ok('carry has 10 left and 20 applied',
 (SELECT applied=20 AND remaining=10 FROM public.customer_credit_position_as_of(pg_temp.k('4b'),DATE '2026-12-31',clock_timestamp())));
RESET ROLE;
SET CONSTRAINTS ALL IMMEDIATE;
ROLLBACK;
