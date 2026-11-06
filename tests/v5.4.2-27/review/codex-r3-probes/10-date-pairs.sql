-- Codex r3: AUTHOR RUN ONLY; not executed by reviewer.
-- Owner session, fresh clone with patch-27-frozen-r3.sql strictly applied.
-- Clone TEMP revoked from PUBLIC/tally_app/tally_core per brief. No role DDL.
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
-- n(): r3's ids, 00000000-0000-4000-8000-0000000029xx.
CREATE FUNCTION pg_temp.n(p text) RETURNS uuid LANGUAGE sql IMMUTABLE AS $$ SELECT ('00000000-0000-4000-8000-0000000029' || p)::uuid $$;
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
  VALUES (p_id, '00000000-0000-4000-8000-0000000027a1', 'B27-' || right(p_id::text, 4), p_cust, p_on, p_amount, 'check', p_deposit);
  PERFORM pg_temp.post(p_id, p_entry);
END $$;
CREATE FUNCTION pg_temp.refund(p_id uuid, p_entry uuid, p_cust uuid, p_pay uuid, p_credit uuid, p_amount numeric, p_on date) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO public.payments (id, tenant_id, payment_number, customer_id, payment_date, amount, payment_method, refunds_payment_id, refunds_customer_credit_id)
  VALUES (p_id, '00000000-0000-4000-8000-0000000027a1', 'B27-' || right(p_id::text, 4) || 'R', p_cust, p_on, -p_amount, 'refund', p_pay, p_credit);
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
GRANT EXECUTE ON FUNCTION pg_temp.refuses_at(text, text, text, text), pg_temp.ok(text, boolean), pg_temp.admits(text, text), pg_temp.k(text), pg_temp.n(text),
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


SELECT pg_temp.pay(pg_temp.k('61'), pg_temp.k('81'), :c1, 50, DATE '2026-03-10');
SELECT pg_temp.refund(pg_temp.k('62'), pg_temp.k('82'), :c1, pg_temp.k('61'), NULL, 30, DATE '2026-03-11');
SELECT pg_temp.bounce(pg_temp.k('61'), pg_temp.k('81'), pg_temp.k('83'), DATE '2026-03-12');
SELECT pg_temp.credit(pg_temp.k('71'), pg_temp.k('85'), :c1, 30);
INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reverses_ledger_entry_id)
VALUES (pg_temp.k('86'), pg_temp.k('a1'), :c1, DATE '2026-03-20', 'nsf', 'refund returned', -30, pg_temp.k('82'));

-- The repayment and its correcting undo may both be future dated.
-- Each scenario is isolated, and its outcome is printed, including errors.
DO $$
DECLARE d date := (now() AT TIME ZONE 'Etc/GMT-14')::date; i integer;
BEGIN
  FOR i IN 1..4 LOOP
    BEGIN
      PERFORM pg_temp.sa(pg_temp.k('87'), pg_temp.k('c1'), pg_temp.k('61'), NULL, pg_temp.k('71'), 30,
                         CASE WHEN i <= 2 THEN d + 3 ELSE DATE '2026-03-13' END);
      IF i = 1 THEN
        PERFORM pg_temp.sa(NULL, pg_temp.k('c1'), pg_temp.k('61'), NULL, pg_temp.k('71'), -30, d+3, 'undo', pg_temp.k('87'));
      ELSIF i = 2 THEN
        PERFORM pg_temp.sa(NULL, pg_temp.k('c1'), pg_temp.k('61'), NULL, pg_temp.k('71'), -30, d+4, 'undo', pg_temp.k('87'));
      ELSE
        PERFORM pg_temp.sa(NULL, pg_temp.k('c1'), pg_temp.k('61'), NULL, pg_temp.k('71'), -10, d, 'undo', pg_temp.k('87'));
        PERFORM pg_temp.sa(NULL, pg_temp.k('c1'), pg_temp.k('61'), NULL, pg_temp.k('71'), -20,
                           CASE WHEN i = 3 THEN d ELSE d+1 END, 'undo', pg_temp.k('87'));
      END IF;
      UPDATE public.payments SET status='nsf', nsf_date=DATE '2026-03-20', status_cause_id=pg_temp.k('86') WHERE id=pg_temp.k('62');
      SET CONSTRAINTS ALL IMMEDIATE;
      RAISE NOTICE 'case % accepted SQLSTATE=00000 remaining_today=% remaining_future=%', i,
        (SELECT remaining FROM public.payment_position_as_of(pg_temp.k('61'), d, clock_timestamp())),
        (SELECT remaining FROM public.payment_position_as_of(pg_temp.k('61'), d+3, clock_timestamp()));
      RAISE EXCEPTION USING ERRCODE='ZX001', MESSAGE='probe scenario rollback';
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'case % caught SQLSTATE=% message=%', i, SQLSTATE, SQLERRM;
    END;
  END LOOP;
END $$;
-- Predicted: 1 and 3 accepted, then ZX001 for deliberate local rollback;
-- 2 and 4 refused 23514 by the own-date reading. No uncorrectable future pair.
ROLLBACK;
