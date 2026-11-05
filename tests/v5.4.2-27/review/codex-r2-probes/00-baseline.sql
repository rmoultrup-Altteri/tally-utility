-- AUTHOR RUN ONLY. Not executed by Codex. Run as owner on a fresh clone
-- with patch-27-frozen-r2.sql applied. No role DDL. All writes roll back.
\set ON_ERROR_STOP on
-- ============================================================================
-- BATTERY v5.4.2-27 — a credit applied to a bounced payment's shortfall
-- (2026-11-05)
-- Run: psql -U tally -d <db-with-patch> -v ON_ERROR_STOP=1 -f battery-27.sql
-- One transaction, rolled back. Fixtures as the owner; every guard the
-- application meets is exercised as tally_app under app.user_id.
-- Requirements: application/wave2-build-2026-10-15/v5.4.2-27-design.md.
--
--   K  Kyle's example across payments; the row's own rules
--   S  Ryan's call (2026-11-05, option 1): a refund returned after its
--      shortfall was repaid waits until the repayment is undone
--   F  within one family (-23's R24) and into a family whose deficit sits
--      on its credit
--   B  a source applied to a shortfall holds up its own bounce (R15)
--   T  targets (r2)       C  a later repayment hides no earlier one (r2)
--   E  the carry after an escheat (r2)
--   D  the freeze          I  invariants
-- What one transaction cannot show (READ COMMITTED, recorded order across
-- transactions, two writers) is in races/shortfall-27.sh.
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

-- ============================================================== K Kyle's example across payments
-- C1: P1 (61) pays 50 on 03-10, is refunded 30 (62) on 03-11, and bounces
-- (83) on 03-12: the customer owes 30. G1 (71), a goodwill credit of 20.
-- P2 (63) pays 30, unapplied. D (64), a deposit of 75. P5 (65), pending.
SET ROLE tally_app;
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000027b1', true);
SELECT pg_temp.pay(pg_temp.k('61'), pg_temp.k('81'), :c1, 50, DATE '2026-03-10');
SELECT pg_temp.refund(pg_temp.k('62'), pg_temp.k('82'), :c1, pg_temp.k('61'), NULL, 30, DATE '2026-03-11');
SELECT pg_temp.bounce(pg_temp.k('61'), pg_temp.k('81'), pg_temp.k('83'), DATE '2026-03-12');
SELECT pg_temp.credit(pg_temp.k('71'), pg_temp.k('84'), :c1, 20);
SELECT pg_temp.pay(pg_temp.k('63'), pg_temp.k('85'), :c1, 30, DATE '2026-03-10');
SELECT pg_temp.pay(pg_temp.k('64'), pg_temp.k('86'), :c1, 75, DATE '2026-03-10', true);
INSERT INTO public.payments (id, tenant_id, payment_number, customer_id, payment_date, amount, payment_method)
VALUES (pg_temp.k('65'), '00000000-0000-4000-8000-0000000027a1', 'B27-65', :c1, DATE '2026-03-10', 20, 'check');
SELECT public.account_balance_as_of(:c1, DATE '2026-12-31', clock_timestamp()) AS bal_c1 \gset

SELECT pg_temp.ok('K0 Kyle''s example: P1 reads 30 short, nothing repaid',
  pg_temp.pos(pg_temp.k('61')) = '-30.00/0');
SELECT pg_temp.refuses_at('K1 a repayment dated before the bounce (03-11) would leave the payment holding money that day',
  $q$SELECT pg_temp.sa(NULL, '00000000-0000-4000-8000-0000000027c1', pg_temp.k('61'), NULL, pg_temp.k('71'), 20, DATE '2026-03-11')$q$,
  '23514', 'a payment that has ended holds no money');
SELECT pg_temp.admits('K2 G1''s 20 is applied to P1''s shortfall (customer_pot, AC-44)',
  $q$SELECT pg_temp.sa(pg_temp.k('a1'), '00000000-0000-4000-8000-0000000027c1', pg_temp.k('61'), NULL, pg_temp.k('71'), 20, DATE '2026-03-13')$q$);
SELECT pg_temp.ok('K3 G1 reads 20 applied, nothing left; P1 10 short, 20 repaid',
  (SELECT applied = 20 AND remaining = 0 FROM public.customer_credit_position_as_of(pg_temp.k('71'), DATE '2026-12-31', clock_timestamp()))
  AND pg_temp.pos(pg_temp.k('61')) = '-10.00/20.00');
SELECT pg_temp.ok('K3b the customer''s balance is unchanged: no ledger row (the debt and the credit already net there)',
  public.account_balance_as_of(:c1, DATE '2026-12-31', clock_timestamp()) = :bal_c1
  AND NOT EXISTS (SELECT 1 FROM public.account_ledger WHERE customer_id = :c1 AND created_at = now() AND reference_type = 'customer_credit' AND transaction_type <> 'credit_issued'));
SELECT pg_temp.ok('K3c as of 03-12 (before the row''s date) nothing was repaid: the position is dated by applied_on',
  (SELECT remaining = -30 AND repaid = 0 FROM public.payment_position_as_of(pg_temp.k('61'), DATE '2026-03-12', clock_timestamp())));
SELECT pg_temp.refuses_at('K4 G1 cannot be refunded now: its money paid the debt',
  $q$INSERT INTO public.payments (tenant_id, payment_number, customer_id, payment_date, amount, payment_method, refunds_customer_credit_id)
     VALUES ('00000000-0000-4000-8000-0000000027a1', 'B27-K4', '00000000-0000-4000-8000-0000000027c1', DATE '2026-03-14', -0.01, 'refund', pg_temp.k('71'))$q$,
  '23514', 'R-06 cap');
SELECT pg_temp.refuses_at('K4b nor applied to the shortfall again',
  $q$SELECT pg_temp.sa(NULL, '00000000-0000-4000-8000-0000000027c1', pg_temp.k('61'), NULL, pg_temp.k('71'), 0.01, DATE '2026-03-13')$q$,
  '23514', 'R-06 cap');
SELECT pg_temp.refuses_at('K5 P2 repays 10.01 of the 10 left: past what the payment owes',
  $q$SELECT pg_temp.sa(NULL, '00000000-0000-4000-8000-0000000027c1', pg_temp.k('61'), pg_temp.k('63'), NULL, 10.01, DATE '2026-03-13', 'operator_override')$q$,
  '23514', 'a payment that has ended holds no money');
SELECT pg_temp.admits('K6 P2 repays the 10 left (an operator''s choice, with reason and user)',
  $q$SELECT pg_temp.sa(pg_temp.k('a2'), '00000000-0000-4000-8000-0000000027c1', pg_temp.k('61'), pg_temp.k('63'), NULL, 10, DATE '2026-03-13', 'operator_override')$q$);
SELECT pg_temp.ok('K6b P1 is repaid in full (0 left, 30 repaid); P2 reads 10 applied, 20 left',
  pg_temp.pos(pg_temp.k('61')) = '0.00/30.00'
  AND (SELECT applied = 10 AND remaining = 20 FROM public.payment_position_as_of(pg_temp.k('63'), DATE '2026-12-31', clock_timestamp())));
SELECT pg_temp.refuses_at('K7 P2 cannot bounce while its money pays P1''s shortfall (R15)',
  $q$SELECT pg_temp.bounce(pg_temp.k('63'), pg_temp.k('85'), NULL, DATE '2026-03-14')$q$,
  '23001', 'takes back payment');
SELECT pg_temp.refuses_at('K7b nor have any of it taken back',
  $q$INSERT INTO public.account_ledger (tenant_id, customer_id, transaction_date, transaction_type, description, amount, reverses_ledger_entry_id)
     VALUES ('00000000-0000-4000-8000-0000000027a1', '00000000-0000-4000-8000-0000000027c1', DATE '2026-03-14', 'adjustment', 'K7b', 1, pg_temp.k('85'))$q$,
  '23001', 'takes back payment');
SELECT pg_temp.refuses_at('K8 an undo says why and who',
  $q$INSERT INTO public.shortfall_applications (tenant_id, customer_id, target_payment_id, payment_id, amount, applied_on, basis, undoes_shortfall_application_id)
     VALUES ('00000000-0000-4000-8000-0000000027a1', '00000000-0000-4000-8000-0000000027c1', pg_temp.k('61'), pg_temp.k('63'), -10, DATE '2026-03-14', 'undo', pg_temp.k('a2'))$q$,
  '23514', 'shortfall_applications_operator_check');
SELECT pg_temp.refuses_at('K8b so does an operator''s choice',
  $q$INSERT INTO public.shortfall_applications (tenant_id, customer_id, target_payment_id, payment_id, amount, applied_on, basis, applied_by)
     VALUES ('00000000-0000-4000-8000-0000000027a1', '00000000-0000-4000-8000-0000000027c1', pg_temp.k('61'), pg_temp.k('63'), 1, DATE '2026-03-14', 'operator_override', '00000000-0000-4000-8000-0000000027b1')$q$,
  '23514', 'shortfall_applications_operator_check');
SELECT pg_temp.refuses_at('K9 an undo is dated on or after what it undoes',
  $q$SELECT pg_temp.sa(NULL, '00000000-0000-4000-8000-0000000027c1', pg_temp.k('61'), pg_temp.k('63'), NULL, -10, DATE '2026-03-12', 'undo', pg_temp.k('a2'))$q$,
  '23514', 'an undo is dated on or after it');
SELECT pg_temp.refuses_at('K9b an undo names its own source (G1''s row, undone as P2''s)',
  $q$SELECT pg_temp.sa(NULL, '00000000-0000-4000-8000-0000000027c1', pg_temp.k('61'), pg_temp.k('63'), NULL, -1, DATE '2026-03-14', 'undo', pg_temp.k('a1'))$q$,
  '23514', 'of the same source and payment');
SELECT pg_temp.admits('K9c P2''s 10 is undone',
  $q$SELECT pg_temp.sa(pg_temp.k('a3'), '00000000-0000-4000-8000-0000000027c1', pg_temp.k('61'), pg_temp.k('63'), NULL, -10, DATE '2026-03-14', 'undo', pg_temp.k('a2'))$q$);
SELECT pg_temp.ok('K9d P1 10 short again; P2 nothing applied',
  pg_temp.pos(pg_temp.k('61')) = '-10.00/20.00'
  AND (SELECT applied = 0 AND remaining = 30 FROM public.payment_position_as_of(pg_temp.k('63'), DATE '2026-12-31', clock_timestamp())));
SELECT pg_temp.refuses_at('K10 undos never come to more than what they undo',
  $q$SELECT pg_temp.sa(NULL, '00000000-0000-4000-8000-0000000027c1', pg_temp.k('61'), pg_temp.k('63'), NULL, -0.01, DATE '2026-03-14', 'undo', pg_temp.k('a2'))$q$,
  '23514', 'its undos would come to');
SELECT pg_temp.refuses_at('K11 an undo is never undone',
  $q$SELECT pg_temp.sa(NULL, '00000000-0000-4000-8000-0000000027c1', pg_temp.k('61'), pg_temp.k('63'), NULL, -1, DATE '2026-03-14', 'undo', pg_temp.k('a3'))$q$,
  '23514', 'not an undo');
SELECT pg_temp.admits('K12 with nothing applied, P2 bounces as usual',
  $q$SELECT pg_temp.bounce(pg_temp.k('63'), pg_temp.k('85'), pg_temp.k('87'), DATE '2026-03-14')$q$);
SELECT pg_temp.refuses_at('K12b a bounced payment gives nothing (P2 to P1)',
  $q$SELECT pg_temp.sa(NULL, '00000000-0000-4000-8000-0000000027c1', pg_temp.k('61'), pg_temp.k('63'), NULL, 1, DATE '2026-03-15')$q$,
  '23514', 'money is drawn from a posted payment');
SELECT pg_temp.refuses_at('K13 a shortfall is repaid on a payment that bounced or was reversed: not on a posted one (10)',
  $q$SELECT pg_temp.pay(pg_temp.k('10'), pg_temp.k('11'), '00000000-0000-4000-8000-0000000027c1', 10, DATE '2026-03-10');
     SELECT pg_temp.credit(pg_temp.k('72'), pg_temp.k('88'), '00000000-0000-4000-8000-0000000027c1', 10);
     SELECT pg_temp.sa(NULL, '00000000-0000-4000-8000-0000000027c1', pg_temp.k('10'), NULL, pg_temp.k('72'), 1, DATE '2026-03-15')$q$,
  '23514', 'a shortfall is repaid on a payment that bounced or was reversed');
SELECT pg_temp.refuses_at('K13b nor on a pending one',
  $q$SELECT pg_temp.credit(pg_temp.k('72'), pg_temp.k('88'), '00000000-0000-4000-8000-0000000027c1', 10);
     SELECT pg_temp.sa(NULL, '00000000-0000-4000-8000-0000000027c1', pg_temp.k('65'), NULL, pg_temp.k('72'), 1, DATE '2026-03-15')$q$,
  '23514', 'a shortfall is repaid on a payment that bounced or was reversed');
SELECT pg_temp.refuses_at('K14 a deposit is not in the pot (-15 settles it)',
  $q$SELECT pg_temp.sa(NULL, '00000000-0000-4000-8000-0000000027c1', pg_temp.k('61'), pg_temp.k('64'), NULL, 1, DATE '2026-03-15')$q$,
  '23514', 'money is drawn from a posted payment');
SELECT pg_temp.refuses_at('K14b nor a pending payment',
  $q$SELECT pg_temp.sa(NULL, '00000000-0000-4000-8000-0000000027c1', pg_temp.k('61'), pg_temp.k('65'), NULL, 1, DATE '2026-03-15')$q$,
  '23514', 'money is drawn from a posted payment');
SELECT pg_temp.refuses_at('K15 a payment does not repay itself',
  $q$SELECT pg_temp.sa(NULL, '00000000-0000-4000-8000-0000000027c1', pg_temp.k('61'), pg_temp.k('61'), NULL, 1, DATE '2026-03-15')$q$,
  '23514', 'shortfall_applications_not_own_check');
SELECT pg_temp.refuses_at('K16 basis is customer_pot, operator_override or undo',
  $q$SELECT pg_temp.sa(NULL, '00000000-0000-4000-8000-0000000027c1', pg_temp.k('61'), NULL, pg_temp.k('71'), 1, DATE '2026-03-15', 'oldest_first')$q$,
  '23514', 'shortfall_applications_basis_check');
SELECT pg_temp.refuses_at('K16b only an undo is negative',
  $q$SELECT pg_temp.sa(NULL, '00000000-0000-4000-8000-0000000027c1', pg_temp.k('61'), NULL, pg_temp.k('71'), -1, DATE '2026-03-15')$q$,
  '23514', 'shortfall_applications_sign_check');
SELECT pg_temp.refuses_at('K16c and an undo names what it undoes',
  $q$SELECT pg_temp.sa(NULL, '00000000-0000-4000-8000-0000000027c1', pg_temp.k('61'), NULL, pg_temp.k('71'), -1, DATE '2026-03-15', 'undo')$q$,
  '23514', 'shortfall_applications_sign_check');
SELECT pg_temp.refuses_at('K16d one source, not two',
  $q$INSERT INTO public.shortfall_applications (tenant_id, customer_id, target_payment_id, payment_id, customer_credit_id, amount, applied_on, basis)
     VALUES ('00000000-0000-4000-8000-0000000027a1', '00000000-0000-4000-8000-0000000027c1', pg_temp.k('61'), pg_temp.k('63'), pg_temp.k('71'), 1, DATE '2026-03-15', 'customer_pot')$q$,
  '23514', 'shortfall_applications_one_source_check');
SELECT pg_temp.refuses_at('K17 another customer''s credit does not repay C1''s payment (X1b: that is a transfer)',
  $q$SELECT pg_temp.credit(pg_temp.k('73'), pg_temp.k('89'), '00000000-0000-4000-8000-0000000027c2', 10);
     SELECT pg_temp.sa(NULL, '00000000-0000-4000-8000-0000000027c1', pg_temp.k('61'), NULL, pg_temp.k('73'), 1, DATE '2026-03-15')$q$,
  '23503', 'shortfall_applications_credit_fkey');
SELECT pg_temp.refuses_at('K17b nor is C1''s payment another customer''s target',
  $q$SELECT pg_temp.credit(pg_temp.k('73'), pg_temp.k('89'), '00000000-0000-4000-8000-0000000027c2', 10);
     SELECT pg_temp.sa(NULL, '00000000-0000-4000-8000-0000000027c2', pg_temp.k('61'), NULL, pg_temp.k('73'), 1, DATE '2026-03-15')$q$,
  '23503', 'shortfall_applications_target_fkey');
SELECT pg_temp.refuses_at('K18 tally_app signed in to T1 writes no T2 row (the freeze cannot see T2''s close head under row-level security, and fails closed first)',
  $q$INSERT INTO public.shortfall_applications (tenant_id, customer_id, target_payment_id, customer_credit_id, amount, applied_on, basis)
     VALUES ('00000000-0000-4000-8000-0000000027a2', '00000000-0000-4000-8000-0000000027c9', pg_temp.k('61'), pg_temp.k('71'), 1, DATE '2026-03-15', 'customer_pot')$q$,
  '42501', 'no close head visible to this session');
SELECT pg_temp.refuses_at('K19 the table is add-only for tally_app: no UPDATE',
  $q$UPDATE public.shortfall_applications SET amount = 1 WHERE id = pg_temp.k('a1')$q$, '42501', 'permission denied');
SELECT pg_temp.refuses_at('K19b no DELETE',
  $q$DELETE FROM public.shortfall_applications WHERE id = pg_temp.k('a1')$q$, '42501', 'permission denied');
SELECT pg_temp.refuses_at('K20 G1''s credit_issued entry is not withdrawn while G1 pays the shortfall (R15, through cash_source_draws)',
  $q$INSERT INTO public.account_ledger (tenant_id, customer_id, transaction_date, transaction_type, description, amount, reverses_ledger_entry_id)
     VALUES ('00000000-0000-4000-8000-0000000027a1', '00000000-0000-4000-8000-0000000027c1', DATE '2026-03-15', 'adjustment', 'K20', 1, pg_temp.k('84'))$q$,
  '23001', 'while the credit is drawn on');
SELECT pg_temp.refuses_at('K21 G1, netted to 0, has nothing to remit (R24 closed; AC-44)',
  $q$INSERT INTO public.escheatment_events (tenant_id, customer_credit_id, customer_id, event_type, amount_related)
     VALUES ('00000000-0000-4000-8000-0000000027a1', pg_temp.k('71'), '00000000-0000-4000-8000-0000000027c1', 'escheated_to_state', 0.01)$q$,
  '23514', 'R-06 cap');
RESET ROLE;
-- As the owner: another tenant's row by its keys (no RLS), and a time not yet reached.
SELECT pg_temp.refuses_at('K22 a T2 row naming a T1 payment fails its keys (every key carries the tenant)',
  $q$INSERT INTO public.shortfall_applications (tenant_id, customer_id, target_payment_id, customer_credit_id, amount, applied_on, basis)
     VALUES ('00000000-0000-4000-8000-0000000027a2', '00000000-0000-4000-8000-0000000027c9', pg_temp.k('61'), pg_temp.k('71'), 1, DATE '2026-03-15', 'customer_pot')$q$,
  '23503', 'shortfall_applications_target_fkey');
SELECT pg_temp.refuses_at('K23 a row is recorded at a time already reached, for any role',
  $q$INSERT INTO public.shortfall_applications (tenant_id, customer_id, target_payment_id, payment_id, amount, applied_on, basis, created_at)
     VALUES ('00000000-0000-4000-8000-0000000027a1', '00000000-0000-4000-8000-0000000027c1', pg_temp.k('61'), pg_temp.k('63'), 1, DATE '2026-03-15', 'customer_pot', now() + interval '1 day')$q$,
  '23514', 'not a time already reached');
SELECT pg_temp.refuses_at('K23b and, chosen, not before the target bounced',
  $q$SELECT pg_temp.credit(pg_temp.k('72'), pg_temp.k('88'), '00000000-0000-4000-8000-0000000027c1', 10);
     INSERT INTO public.shortfall_applications (tenant_id, customer_id, target_payment_id, customer_credit_id, amount, applied_on, basis, created_at)
     VALUES ('00000000-0000-4000-8000-0000000027a1', '00000000-0000-4000-8000-0000000027c1', pg_temp.k('61'), pg_temp.k('72'), 1, DATE '2026-03-15', 'customer_pot', now() - interval '1 day')$q$,
  '23514', 'a time chosen for it, before payment');

-- ============================================================== S Ryan's call (2026-11-05, option 1)
-- C3: P3 (66) pays 50, is refunded 30 (67, posted by 8a) and bounces (8b);
-- G3 (74), 20, repays its shortfall (a5). Then the refund check comes back
-- uncashed (8d under 8a): the customer never owed the 30.
SET ROLE tally_app;
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000027b1', true);
SELECT pg_temp.pay(pg_temp.k('66'), pg_temp.k('8c'), :c3, 50, DATE '2026-03-10');
SELECT pg_temp.refund(pg_temp.k('67'), pg_temp.k('8a'), :c3, pg_temp.k('66'), NULL, 30, DATE '2026-03-11');
SELECT pg_temp.bounce(pg_temp.k('66'), pg_temp.k('8c'), pg_temp.k('8b'), DATE '2026-03-12');
SELECT pg_temp.credit(pg_temp.k('74'), pg_temp.k('8e'), :c3, 20);
SELECT pg_temp.sa(pg_temp.k('a5'), :c3, pg_temp.k('66'), NULL, pg_temp.k('74'), 20, DATE '2026-03-13');
SELECT pg_temp.admits('S1 the bank returns the refund check: its row under the refund''s posting row is recorded',
  $q$INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reverses_ledger_entry_id)
     VALUES (pg_temp.k('8d'), '00000000-0000-4000-8000-0000000027a1', '00000000-0000-4000-8000-0000000027c3', DATE '2026-03-14', 'nsf', 'refund check returned', -30, pg_temp.k('8a'))$q$);
SELECT pg_temp.refuses_at('S2 the refund''s move to nsf waits: it would leave P3 holding the 20 repaid (Ryan, 2026-11-05)',
  $q$UPDATE public.payments SET status = 'nsf', nsf_date = DATE '2026-03-14', status_cause_id = pg_temp.k('8d') WHERE id = pg_temp.k('67')$q$,
  '23514', 'undo the shortfall application first');
SELECT pg_temp.admits('S3 the operator undoes 10 of the repayment',
  $q$SELECT pg_temp.sa(pg_temp.k('a6'), '00000000-0000-4000-8000-0000000027c3', pg_temp.k('66'), NULL, pg_temp.k('74'), -10, DATE '2026-03-14', 'undo', pg_temp.k('a5'))$q$);
SELECT pg_temp.refuses_at('S3b still refused: 10 would be left on P3',
  $q$UPDATE public.payments SET status = 'nsf', nsf_date = DATE '2026-03-14', status_cause_id = pg_temp.k('8d') WHERE id = pg_temp.k('67')$q$,
  '23514', 'undo the shortfall application first');
SELECT pg_temp.admits('S4 the operator undoes the rest, and the refund moves to nsf',
  $q$SELECT pg_temp.sa(NULL, '00000000-0000-4000-8000-0000000027c3', pg_temp.k('66'), NULL, pg_temp.k('74'), -10, DATE '2026-03-14', 'undo', pg_temp.k('a5'));
     UPDATE public.payments SET status = 'nsf', nsf_date = DATE '2026-03-14', status_cause_id = pg_temp.k('8d') WHERE id = pg_temp.k('67')$q$);
SELECT pg_temp.ok('S5 P3 owes nothing and holds nothing; G3 has its 20 back',
  pg_temp.pos(pg_temp.k('66')) = '0.00/0.00' AND pg_temp.crem(pg_temp.k('74')) = 20);
SELECT pg_temp.refuses_at('S6 and nothing more is repaid on P3: it owes nothing',
  $q$SELECT pg_temp.sa(NULL, '00000000-0000-4000-8000-0000000027c3', pg_temp.k('66'), NULL, pg_temp.k('74'), 0.01, DATE '2026-03-15')$q$,
  '23514', 'a payment that has ended holds no money');
RESET ROLE;

-- ============================================================== F within one family (R24)
-- C4, history loads as the owner at chosen times, in the order they
-- happened (h*()), as -23's battery: payment PF (f1) 100, held whole as its
-- overpayment credit K (f2); K's refund of 40 (f3) comes back and is carried
-- to reissue R1 (f4); K refunds 60 (f5) and R1 40 (f6); PF bounces (all
-- 100); then R1's refund comes back: R1 holds 40 of its own beside K's
-- deficit, reads 0 by the cover and, before -27, never closes (R24).
CREATE FUNCTION pg_temp.hpost(p_pay uuid, p_entry uuid, p_ago interval) RETURNS void LANGUAGE plpgsql AS $$
DECLARE p public.payments%ROWTYPE;
BEGIN
  SELECT * INTO p FROM public.payments WHERE id = p_pay;
  INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reference_type, reference_id, created_at)
  VALUES (p_entry, p.tenant_id, p.customer_id, p.payment_date,
          CASE WHEN p.refunds_payment_id IS NOT NULL OR p.refunds_customer_credit_id IS NOT NULL THEN 'refund' ELSE 'payment' END,
          p.payment_number || ' posted', -p.amount, 'payment', p.id, now() - p_ago);
  UPDATE public.payments SET status = 'posted', status_cause_id = p_entry, effective_date = payment_date, effective_date_method = 'other',
         status_recorded_at = now() - p_ago WHERE id = p_pay;
END $$;
CREATE FUNCTION pg_temp.hrefund(p_id uuid, p_entry uuid, p_credit uuid, p_amount numeric, p_on date, p_ago interval) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO public.payments (id, tenant_id, payment_number, customer_id, payment_date, amount, payment_method, refunds_customer_credit_id, created_at)
  VALUES (p_id, '00000000-0000-4000-8000-0000000027a1', 'B27-' || right(p_id::text, 2) || 'R', '00000000-0000-4000-8000-0000000027c4', p_on, -p_amount, 'refund', p_credit, now() - p_ago);
  PERFORM pg_temp.hpost(p_id, p_entry, p_ago);
END $$;
CREATE FUNCTION pg_temp.hback(p_refund uuid, p_entry uuid, p_row uuid, p_on date, p_ago interval) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reverses_ledger_entry_id, created_at)
  SELECT p_row, l.tenant_id, l.customer_id, p_on, 'nsf', 'came back', -l.amount, l.id, now() - p_ago FROM public.account_ledger l WHERE l.id = p_entry;
  UPDATE public.payments SET status = 'nsf', nsf_date = p_on, status_cause_id = p_row, status_recorded_at = now() - p_ago WHERE id = p_refund;
END $$;
INSERT INTO public.payments (id, tenant_id, payment_number, customer_id, payment_date, amount, payment_method, created_at)
VALUES (pg_temp.k('f1'), '00000000-0000-4000-8000-0000000027a1', 'B27-F1', '00000000-0000-4000-8000-0000000027c4', DATE '2026-03-10', 100, 'check', now() - interval '12 hours');
SELECT pg_temp.hpost(pg_temp.k('f1'), pg_temp.k('e1'), interval '12 hours');
INSERT INTO public.customer_credit_approvals (id, tenant_id, customer_id, payment_id, amount, approved_by, created_at)
VALUES (pg_temp.k('d1'), '00000000-0000-4000-8000-0000000027a1', '00000000-0000-4000-8000-0000000027c4', pg_temp.k('f1'), 100, '00000000-0000-4000-8000-0000000027b1', now() - interval '11 hours');
INSERT INTO public.customer_credits (id, tenant_id, customer_id, origin_type, original_amount, issued_date, source_payment_id, approval_id, created_at)
VALUES (pg_temp.k('f2'), '00000000-0000-4000-8000-0000000027a1', '00000000-0000-4000-8000-0000000027c4', 'overpayment', 100, DATE '2026-03-11', pg_temp.k('f1'), pg_temp.k('d1'), now() - interval '11 hours');
SELECT pg_temp.hrefund(pg_temp.k('f3'), pg_temp.k('e3'), pg_temp.k('f2'), 40, DATE '2026-03-12', interval '10 hours');
SELECT pg_temp.hback(pg_temp.k('f3'), pg_temp.k('e3'), pg_temp.k('e4'), DATE '2026-03-12', interval '9 hours 30 minutes');
INSERT INTO public.customer_credits (id, tenant_id, customer_id, origin_type, original_amount, issued_date, reissues_refund_id, created_at)
VALUES (pg_temp.k('f4'), '00000000-0000-4000-8000-0000000027a1', '00000000-0000-4000-8000-0000000027c4', 'refund_reissue', 40, DATE '2026-03-12', pg_temp.k('f3'), now() - interval '9 hours');
SELECT pg_temp.hrefund(pg_temp.k('f5'), pg_temp.k('e5'), pg_temp.k('f2'), 60, DATE '2026-03-12', interval '8 hours 30 minutes');
SELECT pg_temp.hrefund(pg_temp.k('f6'), pg_temp.k('e6'), pg_temp.k('f4'), 40, DATE '2026-03-12', interval '8 hours');
INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reference_type, reference_id, reverses_ledger_entry_id, created_at)
VALUES (pg_temp.k('e7'), '00000000-0000-4000-8000-0000000027a1', '00000000-0000-4000-8000-0000000027c4', DATE '2026-03-13', 'nsf', 'PF bounced', 100, 'payment', pg_temp.k('f1'), pg_temp.k('e1'), now() - interval '7 hours');
UPDATE public.payments SET status = 'nsf', nsf_date = DATE '2026-03-13', status_cause_id = pg_temp.k('e7'), status_recorded_at = now() - interval '7 hours' WHERE id = pg_temp.k('f1');
SELECT pg_temp.hback(pg_temp.k('f6'), pg_temp.k('e6'), pg_temp.k('e8'), DATE '2026-03-14', interval '6 hours');
SELECT pg_temp.ok('F0 before -27''s row: PF 0, K 60 short, R1 0 by the cover while it holds 40 of its own (R24)',
  pg_temp.pos(pg_temp.k('f1')) = '0.00/0' AND pg_temp.crem(pg_temp.k('f2')) = -60 AND pg_temp.crem(pg_temp.k('f4')) = 0
  AND public.customer_credit_own_remaining_as_of(pg_temp.k('f4'), DATE '2026-12-31', clock_timestamp()) = 40);
SET ROLE tally_app;
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000027b1', true);
-- PX (6b), another bounced payment of C4: 30 paid, 30 refunded, 30 short.
SELECT pg_temp.pay(pg_temp.k('6b'), pg_temp.k('97'), '00000000-0000-4000-8000-0000000027c4', 30, DATE '2026-03-10');
SELECT pg_temp.refund(pg_temp.k('6c'), pg_temp.k('98'), '00000000-0000-4000-8000-0000000027c4', pg_temp.k('6b'), NULL, 30, DATE '2026-03-11');
SELECT pg_temp.bounce(pg_temp.k('6b'), pg_temp.k('97'), pg_temp.k('99'), DATE '2026-03-12');
SELECT pg_temp.refuses_at('F1a R1''s own 40 does not go to another payment''s shortfall: its family owes more than it holds (the cap on a payment and its credits together)',
  $q$SELECT pg_temp.sa(NULL, '00000000-0000-4000-8000-0000000027c4', pg_temp.k('6b'), NULL, pg_temp.k('f4'), 10, DATE '2026-03-14')$q$,
  '23514', 'and its overpayment credit: on');
SELECT pg_temp.refuses_at('F1 R1 applies no more than its own 40 to its own payment''s shortfall',
  $q$SELECT pg_temp.sa(NULL, '00000000-0000-4000-8000-0000000027c4', pg_temp.k('f1'), NULL, pg_temp.k('f4'), 40.01, DATE '2026-03-14')$q$,
  '23514', 'R-06 cap');
SELECT pg_temp.admits('F2 R24''s closing act: R1''s 40 is applied to PF''s shortfall (within the family, not held to the family cap)',
  $q$SELECT pg_temp.sa(pg_temp.k('a7'), '00000000-0000-4000-8000-0000000027c4', pg_temp.k('f1'), NULL, pg_temp.k('f4'), 40, DATE '2026-03-14')$q$);
SELECT pg_temp.ok('F3 the family reads the same (PF 0, K 60 short, R1 0), and now R1 holds nothing of its own: it can close',
  pg_temp.pos(pg_temp.k('f1')) = '0.00/40.00' AND pg_temp.crem(pg_temp.k('f2')) = -60 AND pg_temp.crem(pg_temp.k('f4')) = 0
  AND public.customer_credit_own_remaining_as_of(pg_temp.k('f4'), DATE '2026-12-31', clock_timestamp()) = 0);
-- Into a family whose deficit sits on its credit: G4 (75), 30; G5 (76), 31.
SELECT pg_temp.credit(pg_temp.k('75'), pg_temp.k('8f'), '00000000-0000-4000-8000-0000000027c4', 30);
SELECT pg_temp.credit(pg_temp.k('76'), pg_temp.k('90'), '00000000-0000-4000-8000-0000000027c4', 31);
SELECT pg_temp.admits('F4 G4''s 30 repays PF: it lands on the payment and the cover carries it to K''s deficit',
  $q$SELECT pg_temp.sa(NULL, '00000000-0000-4000-8000-0000000027c4', pg_temp.k('f1'), NULL, pg_temp.k('75'), 30, DATE '2026-03-15')$q$);
SELECT pg_temp.ok('F4b PF 0, K 30 short, R1 0; G4 0',
  pg_temp.pos(pg_temp.k('f1')) = '0.00/70.00' AND pg_temp.crem(pg_temp.k('f2')) = -30 AND pg_temp.crem(pg_temp.k('f4')) = 0 AND pg_temp.crem(pg_temp.k('75')) = 0);
SELECT pg_temp.refuses_at('F5 G5''s 31 is a cent past the 30 the family still owes',
  $q$SELECT pg_temp.sa(NULL, '00000000-0000-4000-8000-0000000027c4', pg_temp.k('f1'), NULL, pg_temp.k('76'), 30.01, DATE '2026-03-15')$q$,
  '23514', 'a payment that has ended holds no money');
SELECT pg_temp.admits('F5b G5 repays the 30',
  $q$SELECT pg_temp.sa(NULL, '00000000-0000-4000-8000-0000000027c4', pg_temp.k('f1'), NULL, pg_temp.k('76'), 30, DATE '2026-03-15')$q$);
SELECT pg_temp.ok('F5c the family is square: PF 0, K 0, R1 0; G5 reads 1',
  pg_temp.pos(pg_temp.k('f1')) = '0.00/100.00' AND pg_temp.crem(pg_temp.k('f2')) = 0 AND pg_temp.crem(pg_temp.k('f4')) = 0 AND pg_temp.crem(pg_temp.k('76')) = 1);
SELECT pg_temp.admits('F6 undoing R1''s 40 within the family is admitted: the family''s sum is unchanged, and R1 has its own 40 again',
  $q$SELECT pg_temp.sa(NULL, '00000000-0000-4000-8000-0000000027c4', pg_temp.k('f1'), NULL, pg_temp.k('f4'), -40, DATE '2026-03-15', 'undo', pg_temp.k('a7'))$q$);
SELECT pg_temp.ok('F6b PF 0 (60 repaid), K 0, R1 0 by the cover, 40 of its own',
  pg_temp.pos(pg_temp.k('f1')) = '0.00/60.00' AND pg_temp.crem(pg_temp.k('f2')) = 0 AND pg_temp.crem(pg_temp.k('f4')) = 0
  AND public.customer_credit_own_remaining_as_of(pg_temp.k('f4'), DATE '2026-12-31', clock_timestamp()) = 40);
RESET ROLE;

-- ============================================================== B a source's own bounce (R15)
-- C5: Q (68) pays 50, held as its overpayment credit OQ (77). P1 of C1 is not
-- C5's, so C5 gets its own bounced payment PB (69): 40 paid, 40 refunded,
-- bounced (40 short).
SET ROLE tally_app;
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000027b1', true);
SELECT pg_temp.pay(pg_temp.k('69'), pg_temp.k('91'), '00000000-0000-4000-8000-0000000027c5', 40, DATE '2026-03-10');
SELECT pg_temp.refund(pg_temp.k('6a'), pg_temp.k('92'), '00000000-0000-4000-8000-0000000027c5', pg_temp.k('69'), NULL, 40, DATE '2026-03-11');
SELECT pg_temp.bounce(pg_temp.k('69'), pg_temp.k('91'), pg_temp.k('93'), DATE '2026-03-12');
SELECT pg_temp.pay(pg_temp.k('68'), pg_temp.k('94'), '00000000-0000-4000-8000-0000000027c5', 50, DATE '2026-03-10');
INSERT INTO public.customer_credit_approvals (id, tenant_id, customer_id, payment_id, amount, approved_by)
VALUES (pg_temp.k('d2'), '00000000-0000-4000-8000-0000000027a1', '00000000-0000-4000-8000-0000000027c5', pg_temp.k('68'), 50, '00000000-0000-4000-8000-0000000027b1');
INSERT INTO public.customer_credits (id, tenant_id, customer_id, origin_type, original_amount, issued_date, source_payment_id, approval_id)
VALUES (pg_temp.k('77'), '00000000-0000-4000-8000-0000000027a1', '00000000-0000-4000-8000-0000000027c5', 'overpayment', 50, DATE '2026-03-11', pg_temp.k('68'), pg_temp.k('d2'));
SELECT pg_temp.admits('B1 OQ (Q''s money, held as a credit) repays 25 of PB''s shortfall',
  $q$SELECT pg_temp.sa(pg_temp.k('a8'), '00000000-0000-4000-8000-0000000027c5', pg_temp.k('69'), NULL, pg_temp.k('77'), 25, DATE '2026-03-13')$q$);
SELECT pg_temp.ok('B1b OQ 25 left; Q 0 of its own; PB 15 short',
  pg_temp.crem(pg_temp.k('77')) = 25 AND pg_temp.pos(pg_temp.k('68')) = '0.00/0' AND pg_temp.pos(pg_temp.k('69')) = '-15.00/25.00');
SELECT pg_temp.refuses_at('B2 Q cannot bounce while its credit pays PB''s shortfall',
  $q$INSERT INTO public.account_ledger (tenant_id, customer_id, transaction_date, transaction_type, description, amount, reference_type, reference_id, reverses_ledger_entry_id)
     VALUES ('00000000-0000-4000-8000-0000000027a1', '00000000-0000-4000-8000-0000000027c5', DATE '2026-03-14', 'nsf', 'Q returned', 50, 'payment', pg_temp.k('68'), pg_temp.k('94'))$q$,
  '23001', 'takes back payment');
RESET ROLE;
-- The move's own guard, behind the ledger's (with that one switched off for
-- the check, inside a rolled-back subtransaction).
SELECT pg_temp.refuses_at('B3 nor move to nsf (the status guard, with the ledger guard off)',
  $q$ALTER TABLE public.account_ledger DISABLE TRIGGER enforce_ledger_shortfall_source;
     INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reference_type, reference_id, reverses_ledger_entry_id)
     VALUES (pg_temp.k('95'), '00000000-0000-4000-8000-0000000027a1', '00000000-0000-4000-8000-0000000027c5', DATE '2026-03-14', 'nsf', 'Q returned', 50, 'payment', pg_temp.k('68'), pg_temp.k('94'));
     UPDATE public.payments SET status = 'nsf', nsf_date = DATE '2026-03-14', status_cause_id = pg_temp.k('95') WHERE id = pg_temp.k('68')$q$,
  '23001', 'cannot move to nsf while it (or its overpayment credit) is applied');
SET ROLE tally_app;
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000027b1', true);
SELECT pg_temp.admits('B4 the operator undoes OQ''s 25, and Q bounces',
  $q$SELECT pg_temp.sa(NULL, '00000000-0000-4000-8000-0000000027c5', pg_temp.k('69'), NULL, pg_temp.k('77'), -25, DATE '2026-03-14', 'undo', pg_temp.k('a8'));
     SELECT pg_temp.bounce(pg_temp.k('68'), pg_temp.k('94'), pg_temp.k('96'), DATE '2026-03-14')$q$);
SELECT pg_temp.ok('B4b PB is 40 short again; Q and OQ read nothing (OQ''s money went with Q)',
  pg_temp.pos(pg_temp.k('69')) = '-40.00/0.00' AND pg_temp.crem(pg_temp.k('77')) = 0);
RESET ROLE;

-- ============================================================== U an undo giving a repaid family money back
-- C2: PD (6d) pays 50, held whole as credit KD (78); KD donates 20 (9a) and
-- refunds 30 (6e); PD bounces: the family gave out 50 of nothing, 50 short.
-- GD (79), 60, repays the 50. Then the donation is undone: the family would
-- hold 20 on a payment that has ended.
SET ROLE tally_app;
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000027b1', true);
SELECT pg_temp.pay(pg_temp.k('6d'), pg_temp.k('9b'), :c2, 50, DATE '2026-03-10');
INSERT INTO public.customer_credit_approvals (id, tenant_id, customer_id, payment_id, amount, approved_by)
VALUES (pg_temp.k('d3'), '00000000-0000-4000-8000-0000000027a1', :c2, pg_temp.k('6d'), 50, '00000000-0000-4000-8000-0000000027b1');
INSERT INTO public.customer_credits (id, tenant_id, customer_id, origin_type, original_amount, issued_date, source_payment_id, approval_id)
VALUES (pg_temp.k('78'), '00000000-0000-4000-8000-0000000027a1', :c2, 'overpayment', 50, DATE '2026-03-11', pg_temp.k('6d'), pg_temp.k('d3'));
INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reference_type, reference_id)
VALUES (pg_temp.k('9a'), '00000000-0000-4000-8000-0000000027a1', :c2, DATE '2026-03-11', 'donation', 'to the assistance fund', 20, 'customer_credit', pg_temp.k('78'));
SELECT pg_temp.refund(pg_temp.k('6e'), pg_temp.k('9c'), :c2, NULL, pg_temp.k('78'), 30, DATE '2026-03-11');
SELECT pg_temp.bounce(pg_temp.k('6d'), pg_temp.k('9b'), pg_temp.k('9d'), DATE '2026-03-12');
SELECT pg_temp.credit(pg_temp.k('79'), pg_temp.k('9e'), :c2, 60);
SELECT pg_temp.admits('U1 GD repays the family''s 50',
  $q$SELECT pg_temp.sa(NULL, '00000000-0000-4000-8000-0000000027c2', pg_temp.k('6d'), NULL, pg_temp.k('79'), 50, DATE '2026-03-13')$q$);
SELECT pg_temp.refuses_at('U2 the donation''s undo waits: it would leave the bounced payment''s family holding 20 (Ryan, 2026-11-05)',
  $q$INSERT INTO public.account_ledger (tenant_id, customer_id, transaction_date, transaction_type, description, amount, reverses_ledger_entry_id)
     VALUES ('00000000-0000-4000-8000-0000000027a1', '00000000-0000-4000-8000-0000000027c2', DATE '2026-03-14', 'adjustment', 'donation keyed in error', -20, pg_temp.k('9a'))$q$,
  '23514', 'undo the shortfall application first');
RESET ROLE;

-- ============================================================== H a shortfall that grows with its dates
-- C6: PH (6f) pays 50 on 03-10, held whole as credit KH (7a); KH refunds 10
-- dated 03-10 (7b) and 30 dated 03-18 (7c); PH bounces on 03-12. The family
-- owes 10 from 03-12 and 40 from 03-18. GH1 (7d) repays 20 dated 03-18; then
-- GH2 (7e) repays 15 dated 03-13: 5 past what was owed that day, though
-- within what is owed from 03-18 on. A repayment is checked from its own date.
SET ROLE tally_app;
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000027b1', true);
SELECT pg_temp.pay(pg_temp.k('6f'), pg_temp.k('a9'), '00000000-0000-4000-8000-0000000027c6', 50, DATE '2026-03-10');
INSERT INTO public.customer_credit_approvals (id, tenant_id, customer_id, payment_id, amount, approved_by)
VALUES (pg_temp.k('d4'), '00000000-0000-4000-8000-0000000027a1', '00000000-0000-4000-8000-0000000027c6', pg_temp.k('6f'), 50, '00000000-0000-4000-8000-0000000027b1');
INSERT INTO public.customer_credits (id, tenant_id, customer_id, origin_type, original_amount, issued_date, source_payment_id, approval_id)
VALUES (pg_temp.k('7a'), '00000000-0000-4000-8000-0000000027a1', '00000000-0000-4000-8000-0000000027c6', 'overpayment', 50, DATE '2026-03-10', pg_temp.k('6f'), pg_temp.k('d4'));
SELECT pg_temp.refund(pg_temp.k('7b'), pg_temp.k('aa'), '00000000-0000-4000-8000-0000000027c6', NULL, pg_temp.k('7a'), 10, DATE '2026-03-10');
SELECT pg_temp.refund(pg_temp.k('7c'), pg_temp.k('ab'), '00000000-0000-4000-8000-0000000027c6', NULL, pg_temp.k('7a'), 30, DATE '2026-03-18');
SELECT pg_temp.bounce(pg_temp.k('6f'), pg_temp.k('a9'), pg_temp.k('ac'), DATE '2026-03-12');
SELECT pg_temp.credit(pg_temp.k('7d'), pg_temp.k('ad'), '00000000-0000-4000-8000-0000000027c6', 20);
SELECT pg_temp.credit(pg_temp.k('7e'), pg_temp.k('ae'), '00000000-0000-4000-8000-0000000027c6', 15);
SELECT pg_temp.admits('H1 GH1 repays 20 dated 03-18 (40 owed then)',
  $q$SELECT pg_temp.sa(NULL, '00000000-0000-4000-8000-0000000027c6', pg_temp.k('6f'), NULL, pg_temp.k('7d'), 20, DATE '2026-03-18')$q$);
SELECT pg_temp.refuses_at('H2 GH2''s 15 dated 03-13 is refused: 10 was owed that day (checked from its own date, not the latest row''s)',
  $q$SELECT pg_temp.sa(NULL, '00000000-0000-4000-8000-0000000027c6', pg_temp.k('6f'), NULL, pg_temp.k('7e'), 15, DATE '2026-03-13')$q$,
  '23514', 'a payment that has ended holds no money');
SELECT pg_temp.admits('H2b 10 dated 03-13 is admitted (30 repaid of the 40 owed from 03-18)',
  $q$SELECT pg_temp.sa(NULL, '00000000-0000-4000-8000-0000000027c6', pg_temp.k('6f'), NULL, pg_temp.k('7e'), 10, DATE '2026-03-13')$q$);
RESET ROLE;

-- ============================================================== T targets (r2, Opus S1, S2; Fable N1)
-- C1: a bounced deposit (12) and a refund that came back (17) are not
-- targets; a reversed payment (1a) is.
SET ROLE tally_app;
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000027b1', true);
SELECT pg_temp.pay(pg_temp.k('12'), pg_temp.k('13'), :c1, 40, DATE '2026-03-10', true);
SELECT pg_temp.bounce(pg_temp.k('12'), pg_temp.k('13'), pg_temp.k('14'), DATE '2026-03-12');
SELECT pg_temp.pay(pg_temp.k('15'), pg_temp.k('16'), :c1, 40, DATE '2026-03-10');
SELECT pg_temp.refund(pg_temp.k('17'), pg_temp.k('18'), :c1, pg_temp.k('15'), NULL, 10, DATE '2026-03-11');
SELECT pg_temp.bounce(pg_temp.k('17'), pg_temp.k('18'), pg_temp.k('19'), DATE '2026-03-12');
SELECT pg_temp.pay(pg_temp.k('1a'), pg_temp.k('1b'), :c1, 40, DATE '2026-03-10');
SELECT pg_temp.refund(pg_temp.k('1c'), pg_temp.k('1d'), :c1, pg_temp.k('1a'), NULL, 40, DATE '2026-03-11');
INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reference_type, reference_id, reverses_ledger_entry_id)
VALUES (pg_temp.k('1e'), '00000000-0000-4000-8000-0000000027a1', :c1, DATE '2026-03-12', 'adjustment', 'keyed to the wrong customer', 40, 'payment', pg_temp.k('1a'), pg_temp.k('1b'));
UPDATE public.payments SET status = 'reversed', status_cause_id = pg_temp.k('1e') WHERE id = pg_temp.k('1a');
SELECT pg_temp.credit(pg_temp.k('2e'), pg_temp.k('2f'), :c1, 50);
SELECT pg_temp.refuses_at('T1 a bounced deposit is not a target: a deposit is kept out of the pot (K-05)',
  $q$SELECT pg_temp.sa(NULL, '00000000-0000-4000-8000-0000000027c1', pg_temp.k('12'), NULL, pg_temp.k('2e'), 1, DATE '2026-03-15')$q$,
  '23514', 'is a deposit');
SELECT pg_temp.refuses_at('T2 a refund that came back is not a target: it leaves no shortfall',
  $q$SELECT pg_temp.sa(NULL, '00000000-0000-4000-8000-0000000027c1', pg_temp.k('17'), NULL, pg_temp.k('2e'), 1, DATE '2026-03-15')$q$,
  '23514', 'is a refund');
SELECT pg_temp.admits('T3 a reversed payment''s shortfall is repaid (40)',
  $q$SELECT pg_temp.sa(NULL, '00000000-0000-4000-8000-0000000027c1', pg_temp.k('1a'), NULL, pg_temp.k('2e'), 40, DATE '2026-03-13')$q$);
SELECT pg_temp.ok('T3b the reversed payment reads 0 left, 40 repaid',
  pg_temp.pos(pg_temp.k('1a')) = '0.00/40.00');
RESET ROLE;

-- ============================================================== C a later repayment hides no earlier one (r2, Codex B1, Opus B1)
-- C7: P (20) pays 50 on 03-10; refunds of 10 (22, 03-11) and 30 (24, 03-18);
-- bounces on 03-12: 10 short to 03-17, then 40. G (27), 30, repays 20 dated
-- 03-18 (29), then 10 dated 03-13 (2a). The 03-11 refund comes back: P
-- would hold 10 from 03-13 to 03-17. r1 checked from 03-18 and admitted it.
INSERT INTO public.customers (id, tenant_id, customer_number, customer_type) VALUES
  ('00000000-0000-4000-8000-0000000027c7', '00000000-0000-4000-8000-0000000027a1', 'B27-C7', 'residential'),
  ('00000000-0000-4000-8000-0000000027c8', '00000000-0000-4000-8000-0000000027a1', 'B27-C8', 'residential');
\set c7 '''00000000-0000-4000-8000-0000000027c7'''
\set c8 '''00000000-0000-4000-8000-0000000027c8'''
SET ROLE tally_app;
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000027b1', true);
SELECT pg_temp.pay(pg_temp.k('20'), pg_temp.k('21'), :c7, 50, DATE '2026-03-10');
SELECT pg_temp.refund(pg_temp.k('22'), pg_temp.k('23'), :c7, pg_temp.k('20'), NULL, 10, DATE '2026-03-11');
SELECT pg_temp.refund(pg_temp.k('24'), pg_temp.k('25'), :c7, pg_temp.k('20'), NULL, 30, DATE '2026-03-18');
SELECT pg_temp.bounce(pg_temp.k('20'), pg_temp.k('21'), pg_temp.k('26'), DATE '2026-03-12');
SELECT pg_temp.credit(pg_temp.k('27'), pg_temp.k('28'), :c7, 30);
SELECT pg_temp.sa(pg_temp.k('29'), :c7, pg_temp.k('20'), NULL, pg_temp.k('27'), 20, DATE '2026-03-18');
SELECT pg_temp.sa(pg_temp.k('2a'), :c7, pg_temp.k('20'), NULL, pg_temp.k('27'), 10, DATE '2026-03-13');
INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reverses_ledger_entry_id)
VALUES (pg_temp.k('2b'), '00000000-0000-4000-8000-0000000027a1', :c7, DATE '2026-03-19', 'nsf', 'refund check returned', -10, pg_temp.k('23'));
SELECT pg_temp.refuses_at('C1 the 03-11 refund''s return waits: P would hold 10 from 03-13 to 03-17, though the latest repayment (03-18) still fits',
  $q$UPDATE public.payments SET status = 'nsf', nsf_date = DATE '2026-03-19', status_cause_id = pg_temp.k('2b') WHERE id = pg_temp.k('22')$q$,
  '23514', 'undo the shortfall application first');
SELECT pg_temp.refuses_at('C2 undoing the later repayment (20) does not settle the earlier one',
  $q$SELECT pg_temp.sa(NULL, '00000000-0000-4000-8000-0000000027c7', pg_temp.k('20'), NULL, pg_temp.k('27'), -20, DATE '2026-03-19', 'undo', pg_temp.k('29'));
     UPDATE public.payments SET status = 'nsf', nsf_date = DATE '2026-03-19', status_cause_id = pg_temp.k('2b') WHERE id = pg_temp.k('22')$q$,
  '23514', 'undo the shortfall application first');
SELECT pg_temp.admits('C3 undoing the earlier one (10), dated 03-19, settles it from 03-13: the return is recorded',
  $q$SELECT pg_temp.sa(pg_temp.k('2c'), '00000000-0000-4000-8000-0000000027c7', pg_temp.k('20'), NULL, pg_temp.k('27'), -10, DATE '2026-03-19', 'undo', pg_temp.k('2a'));
     UPDATE public.payments SET status = 'nsf', nsf_date = DATE '2026-03-19', status_cause_id = pg_temp.k('2b') WHERE id = pg_temp.k('22')$q$);
SELECT pg_temp.ok('C3b P reads 10 short, 20 repaid; G 10 left',
  pg_temp.pos(pg_temp.k('20')) = '-10.00/20.00' AND pg_temp.crem(pg_temp.k('27')) = 10);
SELECT pg_temp.refuses_at('C4 a repayment is still read with every row at its own date: another credit''s 10 dated 03-18 is refused (the undo of 03-13''s, dated 03-19, does not count on 03-18 for it)',
  $q$SELECT pg_temp.credit(pg_temp.k('2d'), pg_temp.k('1f'), '00000000-0000-4000-8000-0000000027c7', 10);
     SELECT pg_temp.sa(NULL, '00000000-0000-4000-8000-0000000027c7', pg_temp.k('20'), NULL, pg_temp.k('2d'), 10, DATE '2026-03-18')$q$,
  '23514', 'a payment that has ended holds no money');
-- C8, the same through a family credit's refund (Fable S2): PQ (30) pays 50,
-- held whole as its overpayment credit KQ (32); KQ refunds 10 (34, 03-11)
-- and 30 (36, 03-18); PQ bounces 03-12. G8 (39) repays 20 dated 03-18 (3b),
-- then 10 dated 03-13 (3c). KQ's 03-11 refund comes back.
SELECT pg_temp.pay(pg_temp.k('30'), pg_temp.k('31'), :c8, 50, DATE '2026-03-10');
INSERT INTO public.customer_credit_approvals (id, tenant_id, customer_id, payment_id, amount, approved_by)
VALUES (pg_temp.k('33'), '00000000-0000-4000-8000-0000000027a1', :c8, pg_temp.k('30'), 50, '00000000-0000-4000-8000-0000000027b1');
INSERT INTO public.customer_credits (id, tenant_id, customer_id, origin_type, original_amount, issued_date, source_payment_id, approval_id)
VALUES (pg_temp.k('32'), '00000000-0000-4000-8000-0000000027a1', :c8, 'overpayment', 50, DATE '2026-03-10', pg_temp.k('30'), pg_temp.k('33'));
SELECT pg_temp.refund(pg_temp.k('34'), pg_temp.k('35'), :c8, NULL, pg_temp.k('32'), 10, DATE '2026-03-11');
SELECT pg_temp.refund(pg_temp.k('36'), pg_temp.k('37'), :c8, NULL, pg_temp.k('32'), 30, DATE '2026-03-18');
SELECT pg_temp.bounce(pg_temp.k('30'), pg_temp.k('31'), pg_temp.k('38'), DATE '2026-03-12');
SELECT pg_temp.credit(pg_temp.k('39'), pg_temp.k('3a'), :c8, 30);
SELECT pg_temp.admits('C5 G8 repays the family 20 dated 03-18, then 10 dated 03-13',
  $q$SELECT pg_temp.sa(pg_temp.k('3b'), '00000000-0000-4000-8000-0000000027c8', pg_temp.k('30'), NULL, pg_temp.k('39'), 20, DATE '2026-03-18');
     SELECT pg_temp.sa(pg_temp.k('3c'), '00000000-0000-4000-8000-0000000027c8', pg_temp.k('30'), NULL, pg_temp.k('39'), 10, DATE '2026-03-13')$q$);
INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reverses_ledger_entry_id)
VALUES (pg_temp.k('3d'), '00000000-0000-4000-8000-0000000027a1', :c8, DATE '2026-03-19', 'nsf', 'refund check returned', -10, pg_temp.k('35'));
SELECT pg_temp.refuses_at('C6 KQ''s returned refund waits too: the family would hold 10 from 03-13 (a family credit''s refund leaving, Fable S2)',
  $q$UPDATE public.payments SET status = 'nsf', nsf_date = DATE '2026-03-19', status_cause_id = pg_temp.k('3d') WHERE id = pg_temp.k('34')$q$,
  '23514', 'undo the shortfall application first');
SELECT pg_temp.admits('C7 undoing the 03-13 repayment settles it',
  $q$SELECT pg_temp.sa(NULL, '00000000-0000-4000-8000-0000000027c8', pg_temp.k('30'), NULL, pg_temp.k('39'), -10, DATE '2026-03-19', 'undo', pg_temp.k('3c'));
     UPDATE public.payments SET status = 'nsf', nsf_date = DATE '2026-03-19', status_cause_id = pg_temp.k('3d') WHERE id = pg_temp.k('34')$q$);
RESET ROLE;

-- ============================================================== E the carry (r2; Ryan, 2026-11-05, option 1; Opus B2, Fable S1)
-- C7: P7 (40) pays 50, is refunded 30 (42, posted by 43) and bounces: 30
-- short. Credit CE (45), 50, repays the 30 (47); its other 20 is sent to
-- the state (48) and CE is escheated. Then P7's refund check comes back
-- (49): the repayment is undone, and the 30 it gives back to CE, which has
-- ended, is carried into a new credit naming the undo.
SET ROLE tally_app;
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000027b1', true);
SELECT pg_temp.pay(pg_temp.k('40'), pg_temp.k('41'), :c7, 50, DATE '2026-03-10');
SELECT pg_temp.refund(pg_temp.k('42'), pg_temp.k('43'), :c7, pg_temp.k('40'), NULL, 30, DATE '2026-03-11');
SELECT pg_temp.bounce(pg_temp.k('40'), pg_temp.k('41'), pg_temp.k('44'), DATE '2026-03-12');
SELECT pg_temp.credit(pg_temp.k('45'), pg_temp.k('46'), :c7, 50);
SELECT pg_temp.sa(pg_temp.k('47'), :c7, pg_temp.k('40'), NULL, pg_temp.k('45'), 30, DATE '2026-03-13');
SELECT pg_temp.admits('E1 CE''s other 20 is sent to the state and CE is escheated',
  $q$INSERT INTO public.escheatment_events (id, tenant_id, customer_credit_id, customer_id, event_type, amount_related, event_date)
     VALUES (pg_temp.k('48'), '00000000-0000-4000-8000-0000000027a1', pg_temp.k('45'), '00000000-0000-4000-8000-0000000027c7', 'escheated_to_state', 20, '2026-03-14 12:00+00');
     UPDATE public.customer_credits SET status = 'escheated', status_cause_id = pg_temp.k('48'), escheated_at = now() WHERE id = pg_temp.k('45')$q$);
INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reverses_ledger_entry_id)
VALUES (pg_temp.k('49'), '00000000-0000-4000-8000-0000000027a1', :c7, DATE '2026-03-15', 'nsf', 'refund check returned', -30, pg_temp.k('43'));
SELECT pg_temp.refuses_at('E2 P7''s refund''s return waits for the undo (option 1)',
  $q$UPDATE public.payments SET status = 'nsf', nsf_date = DATE '2026-03-15', status_cause_id = pg_temp.k('49') WHERE id = pg_temp.k('42')$q$,
  '23514', 'undo the shortfall application first');
SELECT pg_temp.refuses_at('E3 the undo onto the escheated credit, with nothing carried, is refused at commit',
  $q$SELECT pg_temp.sa(NULL, '00000000-0000-4000-8000-0000000027c7', pg_temp.k('40'), NULL, pg_temp.k('45'), -30, DATE '2026-03-15', 'undo', pg_temp.k('47'));
     UPDATE public.payments SET status = 'nsf', nsf_date = DATE '2026-03-15', status_cause_id = pg_temp.k('49') WHERE id = pg_temp.k('42');
     SET CONSTRAINTS public.enforce_shortfall_undo_carried IMMEDIATE$q$,
  '23514', 'carry it to a new credit');
SELECT pg_temp.refuses_at('E4 the new credit carries what the undo gave back (30), not 29',
  $q$SELECT pg_temp.sa(pg_temp.k('4a'), '00000000-0000-4000-8000-0000000027c7', pg_temp.k('40'), NULL, pg_temp.k('45'), -30, DATE '2026-03-15', 'undo', pg_temp.k('47'));
     INSERT INTO public.customer_credits (tenant_id, customer_id, origin_type, original_amount, issued_date, reissues_shortfall_application_id)
     VALUES ('00000000-0000-4000-8000-0000000027a1', '00000000-0000-4000-8000-0000000027c7', 'shortfall_reissue', 29, DATE '2026-03-15', pg_temp.k('4a'))$q$,
  '23514', 'it carries what the undo gave back');
SELECT pg_temp.refuses_at('E5 nor is it dated before the undo',
  $q$SELECT pg_temp.sa(pg_temp.k('4a'), '00000000-0000-4000-8000-0000000027c7', pg_temp.k('40'), NULL, pg_temp.k('45'), -30, DATE '2026-03-15', 'undo', pg_temp.k('47'));
     INSERT INTO public.customer_credits (tenant_id, customer_id, origin_type, original_amount, issued_date, reissues_shortfall_application_id)
     VALUES ('00000000-0000-4000-8000-0000000027a1', '00000000-0000-4000-8000-0000000027c7', 'shortfall_reissue', 30, DATE '2026-03-14', pg_temp.k('4a'))$q$,
  '23514', 'dated on or after the undo');
SELECT pg_temp.refuses_at('E6 it names an undo, not a repayment',
  $q$INSERT INTO public.customer_credits (tenant_id, customer_id, origin_type, original_amount, issued_date, reissues_shortfall_application_id)
     VALUES ('00000000-0000-4000-8000-0000000027a1', '00000000-0000-4000-8000-0000000027c7', 'shortfall_reissue', 30, DATE '2026-03-15', pg_temp.k('47'))$q$,
  '23514', 'it is not an undo');
SELECT pg_temp.refuses_at('E6b and only a shortfall_reissue names one',
  $q$INSERT INTO public.customer_credits (tenant_id, customer_id, origin_type, original_amount, issued_date, reissues_shortfall_application_id)
     VALUES ('00000000-0000-4000-8000-0000000027a1', '00000000-0000-4000-8000-0000000027c7', 'goodwill', 30, DATE '2026-03-15', pg_temp.k('47'))$q$,
  '23514', 'customer_credits_shortfall_reissue_check');
SELECT pg_temp.admits('E7 the undo, the refund''s return and the new credit (KE, 30), together; checked at commit',
  $q$SELECT pg_temp.sa(pg_temp.k('4a'), '00000000-0000-4000-8000-0000000027c7', pg_temp.k('40'), NULL, pg_temp.k('45'), -30, DATE '2026-03-15', 'undo', pg_temp.k('47'));
     UPDATE public.payments SET status = 'nsf', nsf_date = DATE '2026-03-15', status_cause_id = pg_temp.k('49') WHERE id = pg_temp.k('42');
     INSERT INTO public.customer_credits (id, tenant_id, customer_id, origin_type, original_amount, issued_date, reissues_shortfall_application_id)
     VALUES (pg_temp.k('4b'), '00000000-0000-4000-8000-0000000027a1', '00000000-0000-4000-8000-0000000027c7', 'shortfall_reissue', 30, DATE '2026-03-15', pg_temp.k('4a'));
     SET CONSTRAINTS public.enforce_shortfall_undo_carried IMMEDIATE;
     SET CONSTRAINTS public.enforce_shortfall_undo_carried DEFERRED$q$);
SELECT pg_temp.ok('E7b P7 owes nothing and holds nothing; CE reads nothing left; KE 30',
  pg_temp.pos(pg_temp.k('40')) = '0.00/0.00' AND pg_temp.crem(pg_temp.k('45')) = 0 AND pg_temp.crem(pg_temp.k('4b')) = 30
  AND (SELECT carried = 30 FROM public.customer_credit_position_as_of(pg_temp.k('45'), DATE '2026-12-31', clock_timestamp())));
SELECT pg_temp.ok('E7c KE posts no ledger row: the customer''s balance is unchanged by the carry',
  NOT EXISTS (SELECT 1 FROM public.account_ledger WHERE reference_type = 'customer_credit' AND reference_id = pg_temp.k('4b')));
SELECT pg_temp.refuses_at('E8 one carry per undo',
  $q$INSERT INTO public.customer_credits (tenant_id, customer_id, origin_type, original_amount, issued_date, reissues_shortfall_application_id)
     VALUES ('00000000-0000-4000-8000-0000000027a1', '00000000-0000-4000-8000-0000000027c7', 'shortfall_reissue', 0.01, DATE '2026-03-15', pg_temp.k('4a'))$q$,
  '23505', 'customer_credits_one_per_shortfall_undo');
SELECT pg_temp.refuses_at('E10 KE is never voided, even with nothing drawn on it: its money would go back to an escheated credit',
  $q$UPDATE public.customer_credits SET status = 'voided' WHERE id = pg_temp.k('4b')$q$,
  '23001', 'nothing goes back to that credit');
SELECT pg_temp.admits('E9 KE is money like any credit: it is refunded 5 (no credit_issued entry needed)',
  $q$SELECT pg_temp.refund(pg_temp.k('4c'), pg_temp.k('4d'), '00000000-0000-4000-8000-0000000027c7', NULL, pg_temp.k('4b'), 5, DATE '2026-03-16')$q$);
RESET ROLE;
SELECT pg_temp.refuses_at('E11 KE posts no credit_issued row',
  $q$INSERT INTO public.account_ledger (tenant_id, customer_id, transaction_date, transaction_type, description, amount, reference_type, reference_id)
     VALUES ('00000000-0000-4000-8000-0000000027a1', '00000000-0000-4000-8000-0000000027c7', DATE '2026-03-16', 'credit_issued', 'E11', -30, 'customer_credit', pg_temp.k('4b'))$q$,
  '23514', 'posts no ledger row');
SELECT pg_temp.refuses_at('E12 KE''s undo is fixed from insert',
  $q$UPDATE public.customer_credits SET reissues_shortfall_application_id = pg_temp.k('47') WHERE id = pg_temp.k('4b')$q$,
  '23001', 'is fixed from insert');
-- In an overpayment line: Q (50) pays 40, held whole as OQ7 (52); P (54)
-- pays 30, refunded 30 (56), bounces: OQ7 repays its 30 (59), its other 10
-- reaches the state (5a); P's refund comes back (5b); the undo (5c) is
-- carried into KQ (5d), which holds Q's money: in OQ7's family, and Q's
-- bounce takes it back from KQ.
SET ROLE tally_app;
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000027b1', true);
SELECT pg_temp.pay(pg_temp.k('50'), pg_temp.k('51'), :c7, 40, DATE '2026-03-10');
INSERT INTO public.customer_credit_approvals (id, tenant_id, customer_id, payment_id, amount, approved_by)
VALUES (pg_temp.k('53'), '00000000-0000-4000-8000-0000000027a1', :c7, pg_temp.k('50'), 40, '00000000-0000-4000-8000-0000000027b1');
INSERT INTO public.customer_credits (id, tenant_id, customer_id, origin_type, original_amount, issued_date, source_payment_id, approval_id)
VALUES (pg_temp.k('52'), '00000000-0000-4000-8000-0000000027a1', :c7, 'overpayment', 40, DATE '2026-03-11', pg_temp.k('50'), pg_temp.k('53'));
SELECT pg_temp.pay(pg_temp.k('54'), pg_temp.k('55'), :c7, 30, DATE '2026-03-10');
SELECT pg_temp.refund(pg_temp.k('56'), pg_temp.k('57'), :c7, pg_temp.k('54'), NULL, 30, DATE '2026-03-11');
SELECT pg_temp.bounce(pg_temp.k('54'), pg_temp.k('55'), pg_temp.k('58'), DATE '2026-03-12');
SELECT pg_temp.sa(pg_temp.k('59'), :c7, pg_temp.k('54'), NULL, pg_temp.k('52'), 30, DATE '2026-03-13');
INSERT INTO public.escheatment_events (id, tenant_id, customer_credit_id, customer_id, event_type, amount_related, event_date)
VALUES (pg_temp.k('5a'), '00000000-0000-4000-8000-0000000027a1', pg_temp.k('52'), :c7, 'escheated_to_state', 10, '2026-03-14 12:00+00');
UPDATE public.customer_credits SET status = 'escheated', status_cause_id = pg_temp.k('5a'), escheated_at = now() WHERE id = pg_temp.k('52');
INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reverses_ledger_entry_id)
VALUES (pg_temp.k('5b'), '00000000-0000-4000-8000-0000000027a1', :c7, DATE '2026-03-15', 'nsf', 'refund check returned', -30, pg_temp.k('57'));
SELECT pg_temp.admits('E13 the undo onto OQ7 (escheated), the return and the carry into KQ (30)',
  $q$SELECT pg_temp.sa(pg_temp.k('5c'), '00000000-0000-4000-8000-0000000027c7', pg_temp.k('54'), NULL, pg_temp.k('52'), -30, DATE '2026-03-15', 'undo', pg_temp.k('59'));
     UPDATE public.payments SET status = 'nsf', nsf_date = DATE '2026-03-15', status_cause_id = pg_temp.k('5b') WHERE id = pg_temp.k('56');
     INSERT INTO public.customer_credits (id, tenant_id, customer_id, origin_type, original_amount, issued_date, reissues_shortfall_application_id)
     VALUES (pg_temp.k('5d'), '00000000-0000-4000-8000-0000000027a1', '00000000-0000-4000-8000-0000000027c7', 'shortfall_reissue', 30, DATE '2026-03-15', pg_temp.k('5c'));
     SET CONSTRAINTS public.enforce_shortfall_undo_carried IMMEDIATE;
     SET CONSTRAINTS public.enforce_shortfall_undo_carried DEFERRED$q$);
SELECT pg_temp.ok('E13b KQ is in OQ7''s line: its root is OQ7, it is one reissue down, and it is in the family',
  public.overpayment_root(pg_temp.k('5d')) = pg_temp.k('52') AND public.reissue_generation(pg_temp.k('5d')) = 1
  AND EXISTS (SELECT 1 FROM public.overpayment_family(pg_temp.k('52')) f WHERE f.id = pg_temp.k('5d'))
  AND pg_temp.crem(pg_temp.k('5d')) = 30);
SELECT pg_temp.admits('E14 Q bounces (nothing of its family is applied to a shortfall now)',
  $q$SELECT pg_temp.bounce(pg_temp.k('50'), pg_temp.k('51'), pg_temp.k('5e'), DATE '2026-03-16')$q$);
SELECT pg_temp.ok('E14b the take-back reaches KQ: it holds nothing of Q''s money',
  pg_temp.crem(pg_temp.k('5d')) = 0);
SELECT pg_temp.ok('E14c and as recorded, before the cover: KQ held all 30 of the family''s money at the take-back (OQ7, escheated, held none), so it took 30',
  (SELECT coalesce(sum(x.absorbed), 0) FROM public.overpayment_shares(pg_temp.k('52')) x WHERE x.credit_id = pg_temp.k('5d')) = 30);
RESET ROLE;

-- ============================================================== D the freeze
-- G2 (72), 10, issued before the close.
SET ROLE tally_app;
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000027b1', true);
SELECT pg_temp.credit(pg_temp.k('72'), pg_temp.k('88'), '00000000-0000-4000-8000-0000000027c1', 10);
RESET ROLE;
SET ROLE tally_close;
UPDATE public.accounting_close_heads SET closed_through = DATE '2026-03-20' WHERE tenant_id = '00000000-0000-4000-8000-0000000027a1';
RESET ROLE;
SET ROLE tally_app;
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000027b1', true);
SELECT pg_temp.refuses_at('D1 a shortfall application dated in a closed period (-22 P2)',
  $q$SELECT pg_temp.sa(NULL, '00000000-0000-4000-8000-0000000027c1', pg_temp.k('61'), NULL, pg_temp.k('72'), 1, DATE '2026-03-20')$q$,
  '23514', 'a closed period is frozen');
SELECT pg_temp.admits('D2 one dated after it is admitted (G2 repays 10 of P1''s 10)',
  $q$SELECT pg_temp.sa(NULL, '00000000-0000-4000-8000-0000000027c1', pg_temp.k('61'), NULL, pg_temp.k('72'), 10, DATE '2026-03-21')$q$);
SELECT pg_temp.ok('D3 P1 is repaid: 0 left, 30 repaid',
  pg_temp.pos(pg_temp.k('61')) = '0.00/30.00');
RESET ROLE;

-- ============================================================== I invariants
DO $$ BEGIN
  PERFORM public.assert_shortfall_guard_invariants();
  RAISE NOTICE 'PASS I1 every -27 guard is in place, exactly';
END $$;
DO $$ BEGIN
  PERFORM public.assert_cash_guard_invariants();
  PERFORM public.assert_periods_guard_invariants();
  PERFORM public.assert_seal_role_invariants();
  PERFORM public.assert_core_role_invariants();
  PERFORM public.assert_tenant_isolation_invariants();
  PERFORM public.assert_rule_table_invariants();
  PERFORM public.assert_no_hard_delete_invariants();
  RAISE NOTICE 'PASS I2 the earlier invariants still hold with -27';
END $$;
SELECT pg_temp.refuses_at('I3 the invariant catches a guard switched off',
  $q$ALTER TABLE public.shortfall_applications DISABLE TRIGGER enforce_shortfall_application;
     SELECT public.assert_shortfall_guard_invariants()$q$,
  '0LP01', 'enforce_shortfall_application');
SELECT pg_temp.refuses_at('I3b and a grant widened',
  $q$GRANT UPDATE (reason) ON public.shortfall_applications TO tally_app;
     SELECT public.assert_shortfall_guard_invariants()$q$,
  '0LP01', 'tally_app may only SELECT and INSERT');
SELECT pg_temp.refuses_at('I3c and a second policy',
  $q$CREATE POLICY wide ON public.shortfall_applications USING (true);
     SELECT public.assert_shortfall_guard_invariants()$q$,
  '0LP01', 'another policy beside it');
-- r2 (Codex S1): each privilege is asked alone.
SELECT pg_temp.refuses_at('I3d and the app''s INSERT taken away (SELECT left)',
  $q$REVOKE INSERT ON public.shortfall_applications FROM tally_app;
     SELECT public.assert_shortfall_guard_invariants()$q$,
  '0LP01', 'tally_app may only SELECT and INSERT');
SELECT pg_temp.refuses_at('I3e and the core''s SELECT taken away',
  $q$REVOKE SELECT ON public.shortfall_applications FROM tally_core;
     SELECT public.assert_shortfall_guard_invariants()$q$,
  '0LP01', 'tally_core only read it');
SELECT pg_temp.refuses_at('I3f and REFERENCES granted to the core',
  $q$GRANT REFERENCES ON public.shortfall_applications TO tally_core;
     SELECT public.assert_shortfall_guard_invariants()$q$,
  '0LP01', 'tally_core only read it');
SELECT pg_temp.refuses_at('I3g and the carry''s commit check switched off (r2)',
  $q$ALTER TABLE public.shortfall_applications DISABLE TRIGGER enforce_shortfall_undo_carried;
     SELECT public.assert_shortfall_guard_invariants()$q$,
  '0LP01', 'enforce_shortfall_undo_carried');

ROLLBACK;
