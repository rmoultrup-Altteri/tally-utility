-- AUTHOR RUN ONLY: owner; fresh clone with frozen r10 strictly applied.
-- Revoke clone TEMP from PUBLIC, tally_app and tally_core first. No role DDL.
-- Chosen-time analogues of CR27/CR28c: these do not demonstrate lock waiting.
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL search_path=public,pg_temp;
SET LOCAL statement_timeout='180s';
SET LOCAL client_min_messages=notice;
INSERT INTO public.tenants(id,name,slug) VALUES ('00000000-0000-4000-8000-0000000023a1','Codex r10','codex-r10');
INSERT INTO public.users(id,tenant_id,display_name,email,role) VALUES ('00000000-0000-4000-8000-0000000023b1','00000000-0000-4000-8000-0000000023a1','Reviewer','r10@example.test','operator');
INSERT INTO public.customers(id,tenant_id,customer_number,customer_type) VALUES ('00000000-0000-4000-8000-0000000023c5','00000000-0000-4000-8000-0000000023a1','R10','residential');
CREATE FUNCTION pg_temp.r(p text) RETURNS uuid LANGUAGE sql IMMUTABLE AS $$ SELECT ('00000000-0000-4000-8000-0000000036'||p)::uuid $$;
CREATE FUNCTION pg_temp.expect(label text, command text, state text, phrase text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
 BEGIN
  EXECUTE command;
 EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '% SQLSTATE=% MESSAGE=%',label,SQLSTATE,SQLERRM;
  IF SQLSTATE=state AND strpos(SQLERRM,phrase)>0 THEN RETURN; END IF;
  RAISE;
 END;
 RAISE EXCEPTION 'FAIL % admitted',label;
END $$;
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
CREATE FUNCTION pg_temp.hcredit(p_id uuid, p_appr uuid, p_pay uuid, p_amount numeric, p_ago interval) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO public.customer_credit_approvals (id, tenant_id, customer_id, payment_id, amount, approved_by, created_at)
  VALUES (p_appr, '00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c5', p_pay, p_amount, '00000000-0000-4000-8000-0000000023b1', now() - p_ago);
  INSERT INTO public.customer_credits (id, tenant_id, customer_id, origin_type, original_amount, issued_date, source_payment_id, approval_id, created_at)
  VALUES (p_id, '00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c5', 'overpayment', p_amount, DATE '2026-03-11', p_pay, p_appr, now() - p_ago);
END $$;
CREATE FUNCTION pg_temp.hrow(p_id uuid, p_parent uuid, p_amount numeric, p_ago interval) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reverses_ledger_entry_id, created_at)
  VALUES (p_id, '00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c5', DATE '2026-03-13', 'adjustment', 'x', p_amount, p_parent, now() - p_ago);
END $$;
CREATE FUNCTION pg_temp.hback(p_refund uuid, p_entry uuid, p_row uuid, p_ago interval) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reverses_ledger_entry_id, created_at)
  SELECT p_row, l.tenant_id, l.customer_id, DATE '2026-03-14', 'nsf', 'x came back', -l.amount, l.id, now() - p_ago FROM public.account_ledger l WHERE l.id = p_entry;
  UPDATE public.payments SET status = 'nsf', nsf_date = DATE '2026-03-14', status_cause_id = p_row, status_recorded_at = now() - p_ago WHERE id = p_refund;
END $$;
CREATE FUNCTION pg_temp.hreissue(p_id uuid, p_refund uuid, p_amount numeric, p_ago interval) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO public.customer_credits (id, tenant_id, customer_id, origin_type, original_amount, issued_date, reissues_refund_id, created_at)
  VALUES (p_id, '00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c5', 'refund_reissue', p_amount, DATE '2026-03-14', p_refund, now() - p_ago);
END $$;
CREATE FUNCTION pg_temp.hremit(p_credit uuid, p_event uuid, p_amount numeric, p_ago interval) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO public.escheatment_events (id, tenant_id, customer_credit_id, customer_id, event_type, amount_related, event_date, created_at)
  VALUES (p_event, '00000000-0000-4000-8000-0000000023a1', p_credit, '00000000-0000-4000-8000-0000000023c5', 'escheated_to_state', p_amount, now() - p_ago, now() - p_ago);
END $$;
CREATE FUNCTION pg_temp.hescheat(p_credit uuid, p_event uuid, p_ago interval) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  UPDATE public.customer_credits SET status = 'escheated', status_cause_id = p_event, status_recorded_at = now() - p_ago WHERE id = p_credit;
END $$;
CREATE FUNCTION pg_temp.npay(p_id uuid, p_entry uuid, p_amount numeric, p_ago interval) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO public.payments (id, tenant_id, payment_number, customer_id, payment_date, amount, payment_method, created_at)
  VALUES (p_id, '00000000-0000-4000-8000-0000000023a1', 'B23-N' || right(p_id::text, 4), '00000000-0000-4000-8000-0000000023c5', DATE '2026-03-10', p_amount, 'check', now() - p_ago);
  PERFORM pg_temp.hpost(p_id, p_entry, p_ago);
END $$;
CREATE FUNCTION pg_temp.nrefund_on(p_id uuid, p_entry uuid, p_pay uuid, p_credit uuid, p_amount numeric, p_ago interval, p_on date DEFAULT DATE '2026-03-12') RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO public.payments (id, tenant_id, payment_number, customer_id, payment_date, amount, payment_method, refunds_payment_id, refunds_customer_credit_id, created_at)
  VALUES (p_id, '00000000-0000-4000-8000-0000000023a1', 'B23-N' || right(p_id::text, 4) || 'R', '00000000-0000-4000-8000-0000000023c5', p_on, -p_amount, 'refund', p_pay, p_credit, now() - p_ago);
  PERFORM pg_temp.hpost(p_id, p_entry, p_ago);
END $$;
-- J: refund return at an old stamp must not move the escheated sibling's share.
SELECT pg_temp.npay(pg_temp.r('01'),pg_temp.r('11'),100,interval '14 hours');
SELECT pg_temp.hcredit(pg_temp.r('21'),pg_temp.r('31'),pg_temp.r('01'),50,interval '13 hours');
SELECT pg_temp.nrefund_on(pg_temp.r('02'),pg_temp.r('12'),pg_temp.r('01'),NULL,50,interval '12 hours');
SELECT pg_temp.nrefund_on(pg_temp.r('03'),pg_temp.r('13'),NULL,pg_temp.r('21'),20,interval '11 hours');
SELECT pg_temp.nrefund_on(pg_temp.r('04'),pg_temp.r('14'),NULL,pg_temp.r('21'),15,interval '10 hours');
SELECT pg_temp.hback(pg_temp.r('04'),pg_temp.r('14'),pg_temp.r('15'),interval '9 hours');
SELECT pg_temp.hreissue(pg_temp.r('22'),pg_temp.r('04'),15,interval '8 hours');
SELECT pg_temp.nrefund_on(pg_temp.r('05'),pg_temp.r('16'),NULL,pg_temp.r('21'),15,interval '7 hours');
SELECT pg_temp.hrow(pg_temp.r('17'),pg_temp.r('11'),10,interval '5 hours');
SELECT pg_temp.hremit(pg_temp.r('22'),pg_temp.r('32'),5,interval '4 hours');
SELECT pg_temp.hescheat(pg_temp.r('22'),pg_temp.r('32'),interval '4 hours');
SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;
SELECT pg_temp.expect('J old return', $q$SELECT pg_temp.hback(pg_temp.r('03'),pg_temp.r('13'),pg_temp.r('18'),interval '6 hours')$q$, '23514','under the payment''s posting entry');
SELECT pg_temp.hback(pg_temp.r('03'),pg_temp.r('13'),pg_temp.r('18'),interval '3 hours');
SET CONSTRAINTS ALL IMMEDIATE;
DO $$ BEGIN
 IF public.customer_credit_own_remaining_as_of(pg_temp.r('22'),DATE '9999-12-31',clock_timestamp()) IS DISTINCT FROM 0
 OR (SELECT remaining FROM public.customer_credit_position_as_of(pg_temp.r('21'),DATE '9999-12-31',clock_timestamp())) IS DISTINCT FROM 20 THEN
  RAISE EXCEPTION 'FAIL J retry positions';
 END IF;
 RAISE NOTICE 'PASS J retry SQLSTATE=00000: K 20, escheated R own 0';
END $$;
SET CONSTRAINTS ALL DEFERRED;
-- V: void a sibling that holds no share; old stamp refused by the new guard.
SELECT pg_temp.npay(pg_temp.r('41'),pg_temp.r('51'),100,interval '16 hours');
SELECT pg_temp.hcredit(pg_temp.r('61'),pg_temp.r('71'),pg_temp.r('41'),50,interval '15 hours');
SELECT pg_temp.nrefund_on(pg_temp.r('42'),pg_temp.r('52'),pg_temp.r('41'),NULL,50,interval '14 hours');
SELECT pg_temp.nrefund_on(pg_temp.r('43'),pg_temp.r('53'),NULL,pg_temp.r('61'),15,interval '13 hours');
SELECT pg_temp.hback(pg_temp.r('43'),pg_temp.r('53'),pg_temp.r('54'),interval '12 hours');
SELECT pg_temp.hreissue(pg_temp.r('62'),pg_temp.r('43'),15,interval '11 hours');
SELECT pg_temp.nrefund_on(pg_temp.r('44'),pg_temp.r('55'),NULL,pg_temp.r('61'),10,interval '10 hours');
SELECT pg_temp.hback(pg_temp.r('44'),pg_temp.r('55'),pg_temp.r('56'),interval '9 hours');
SELECT pg_temp.hreissue(pg_temp.r('63'),pg_temp.r('44'),10,interval '8 hours');
SELECT pg_temp.nrefund_on(pg_temp.r('45'),pg_temp.r('57'),NULL,pg_temp.r('61'),25,interval '7 hours');
SELECT pg_temp.hrow(pg_temp.r('58'),pg_temp.r('51'),10,interval '5 hours');
SELECT pg_temp.hremit(pg_temp.r('62'),pg_temp.r('72'),5,interval '4 hours');
SELECT pg_temp.hescheat(pg_temp.r('62'),pg_temp.r('72'),interval '4 hours');
SELECT pg_temp.expect('V old void', $q$UPDATE public.customer_credits SET status='voided',status_recorded_at=now()-interval '6 hours' WHERE id=pg_temp.r('63')$q$, '23514','under the payment''s posting entry');
UPDATE public.customer_credits SET status='voided',status_recorded_at=now()-interval '3 hours' WHERE id=pg_temp.r('63');
SET CONSTRAINTS ALL IMMEDIATE;
DO $$ BEGIN
 IF public.customer_credit_own_remaining_as_of(pg_temp.r('62'),DATE '9999-12-31',clock_timestamp()) IS DISTINCT FROM 0
 OR (SELECT remaining FROM public.customer_credit_position_as_of(pg_temp.r('61'),DATE '9999-12-31',clock_timestamp())) IS DISTINCT FROM 10 THEN
  RAISE EXCEPTION 'FAIL V retry positions';
 END IF;
 RAISE NOTICE 'PASS V retry SQLSTATE=00000: K 10, escheated R1 own 0';
END $$;

-- Transaction-start branch without concurrent sessions: owner records the
-- take-back at the already-reached wall clock, later than this transaction's now().
SET CONSTRAINTS ALL DEFERRED;
SELECT pg_temp.npay(pg_temp.r('81'),pg_temp.r('91'),100,interval '14 hours');
SELECT pg_temp.hcredit(pg_temp.r('a1'),pg_temp.r('b1'),pg_temp.r('81'),20,interval '13 hours');
SELECT pg_temp.nrefund_on(pg_temp.r('82'),pg_temp.r('92'),NULL,pg_temp.r('a1'),10,interval '12 hours');
INSERT INTO public.account_ledger(id,tenant_id,customer_id,transaction_date,transaction_type,description,amount,reverses_ledger_entry_id,created_at)
VALUES(pg_temp.r('93'),'00000000-0000-4000-8000-0000000023a1','00000000-0000-4000-8000-0000000023c5',DATE '2026-03-13','adjustment','later than transaction start',5,pg_temp.r('91'),clock_timestamp());
SELECT pg_temp.expect('transaction-start return', $q$SELECT pg_temp.hback(pg_temp.r('82'),pg_temp.r('92'),pg_temp.r('94'),interval '0 hours')$q$, '40001','under the payment''s posting entry');
SELECT pg_temp.hback(pg_temp.r('82'),pg_temp.r('92'),pg_temp.r('94'),now()-clock_timestamp());
SET CONSTRAINTS ALL IMMEDIATE;
DO $$ BEGIN RAISE NOTICE 'PASS later chosen-time return SQLSTATE=00000; real transaction retry remains author race evidence'; END $$;
ROLLBACK;
