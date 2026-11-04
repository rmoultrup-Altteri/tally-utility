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

-- Equal recorded instants are R17's explicit remaining limitation.
SELECT pg_temp.npay(pg_temp.r('01'),pg_temp.r('11'),100,interval '14 hours');
SELECT pg_temp.hcredit(pg_temp.r('21'),pg_temp.r('31'),pg_temp.r('01'),20,interval '13 hours');
SELECT pg_temp.nrefund_on(pg_temp.r('02'),pg_temp.r('12'),NULL,pg_temp.r('21'),20,interval '12 hours');
SELECT pg_temp.hback(pg_temp.r('02'),pg_temp.r('12'),pg_temp.r('13'),interval '11 hours');
-- Expected: 20 plus concurrent-in-statement take-back 5 is refused at size,
-- because the new reissue can already absorb 5 at this shared recorded instant.
SELECT pg_temp.expect('same statement share at sizing', $q$
 WITH k AS (
 INSERT INTO public.customer_credits(id,tenant_id,customer_id,origin_type,original_amount,issued_date,reissues_refund_id)
 VALUES(pg_temp.r('22'),'00000000-0000-4000-8000-0000000023a1','00000000-0000-4000-8000-0000000023c5','refund_reissue',20,DATE '2026-03-14',pg_temp.r('02')) RETURNING id)
 INSERT INTO public.account_ledger(tenant_id,customer_id,transaction_date,transaction_type,description,amount,reverses_ledger_entry_id)
 SELECT '00000000-0000-4000-8000-0000000023a1','00000000-0000-4000-8000-0000000023c5',DATE '2026-03-15','adjustment','same instant take-back',5,pg_temp.r('11') FROM k
$q$,'23514','carries what came back');
-- In two statements the size is checked before the take-back. The later
-- share is nonzero: do not simplify the issued-side term to amount alone.
SELECT pg_temp.hreissue(pg_temp.r('22'),pg_temp.r('02'),20,interval '0 hours');
INSERT INTO public.account_ledger(tenant_id,customer_id,transaction_date,transaction_type,description,amount,reverses_ledger_entry_id)
VALUES('00000000-0000-4000-8000-0000000023a1','00000000-0000-4000-8000-0000000023c5',DATE '2026-03-15','adjustment','same instant take-back',5,pg_temp.r('11'));
DO $$ DECLARE n numeric; BEGIN
 SELECT sum(absorbed) INTO n FROM public.overpayment_shares(pg_temp.r('21')) WHERE credit_id=pg_temp.r('22');
 IF n IS DISTINCT FROM 5 THEN RAISE EXCEPTION 'FAIL expected new reissue share 5, got %',n; END IF;
 RAISE NOTICE 'PASS shared instant: new reissue share %, SQLSTATE=00000',n;
END $$;
SET CONSTRAINTS ALL IMMEDIATE;
ROLLBACK;
