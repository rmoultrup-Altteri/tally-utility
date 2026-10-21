-- AUTHOR RUN ONLY: owner session, fresh clone with frozen r4 strictly applied.
-- Revoke clone TEMP from PUBLIC, tally_app and tally_core before running.
-- No roles are created/altered. No database execution was performed by Codex.
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL search_path = public, pg_temp;
SET LOCAL client_min_messages = notice;
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

CREATE FUNCTION pg_temp.payment(n numeric) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE p uuid := public.uuid_generate_v4();
BEGIN
 INSERT INTO public.payments(id,tenant_id,customer_id,payment_number,payment_date,amount,payment_method)
 VALUES(p,'00000000-0000-4000-8000-0000000023a1','00000000-0000-4000-8000-0000000023c1',p::text,DATE '2026-03-10',n,'check');
 PERFORM pg_temp.post(p,public.uuid_generate_v4()); RETURN p;
END $$;
CREATE FUNCTION pg_temp.credit(n numeric, p uuid DEFAULT NULL) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE c uuid := public.uuid_generate_v4(); a uuid;
BEGIN
 IF p IS NOT NULL THEN
   a := public.uuid_generate_v4();
   INSERT INTO public.customer_credit_approvals(id,tenant_id,customer_id,payment_id,amount,approved_by)
   VALUES(a,'00000000-0000-4000-8000-0000000023a1','00000000-0000-4000-8000-0000000023c1',p,n,'00000000-0000-4000-8000-0000000023b1');
 END IF;
 INSERT INTO public.customer_credits(id,tenant_id,customer_id,origin_type,original_amount,issued_date,source_payment_id,approval_id)
 VALUES(c,'00000000-0000-4000-8000-0000000023a1','00000000-0000-4000-8000-0000000023c1',CASE WHEN p IS NULL THEN 'goodwill' ELSE 'overpayment' END,n,DATE '2026-03-11',p,a);
 IF p IS NULL THEN
   INSERT INTO public.account_ledger(tenant_id,customer_id,transaction_date,transaction_type,description,amount,reference_type,reference_id)
   VALUES('00000000-0000-4000-8000-0000000023a1','00000000-0000-4000-8000-0000000023c1',DATE '2026-03-11','credit_issued','probe',-n,'customer_credit',c);
 END IF;
 RETURN c;
END $$;
CREATE FUNCTION pg_temp.refund(c uuid,n numeric,d date DEFAULT DATE '2026-03-12') RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE r uuid := public.uuid_generate_v4();
BEGIN
 INSERT INTO public.payments(id,tenant_id,customer_id,payment_number,payment_date,amount,payment_method,refunds_customer_credit_id)
 VALUES(r,'00000000-0000-4000-8000-0000000023a1','00000000-0000-4000-8000-0000000023c1',r::text,d,-n,'refund',c);
 PERFORM pg_temp.post(r,public.uuid_generate_v4()); RETURN r;
END $$;
CREATE FUNCTION pg_temp.reverse_entry(e uuid,n numeric,d date DEFAULT DATE '2026-03-14') RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE k uuid := public.uuid_generate_v4();
BEGIN
 INSERT INTO public.account_ledger(id,tenant_id,customer_id,transaction_date,transaction_type,description,amount,reverses_ledger_entry_id)
 VALUES(k,'00000000-0000-4000-8000-0000000023a1','00000000-0000-4000-8000-0000000023c1',d,'adjustment','probe correction',n,e);
 RETURN k;
END $$;
CREATE FUNCTION pg_temp.escheat(c uuid,n numeric) RETURNS void LANGUAGE plpgsql AS $$
DECLARE e uuid := public.uuid_generate_v4();
BEGIN
 INSERT INTO public.escheatment_events(id,tenant_id,customer_credit_id,customer_id,event_type,amount_related,event_date)
 VALUES(e,'00000000-0000-4000-8000-0000000023a1',c,'00000000-0000-4000-8000-0000000023c1','escheated_to_state',n,TIMESTAMPTZ '2026-03-15 12:00Z');
 UPDATE public.customer_credits SET status='escheated',status_cause_id=e WHERE id=c;
END $$;
CREATE FUNCTION pg_temp.reissue(r uuid,n numeric) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE c uuid := public.uuid_generate_v4();
BEGIN
 INSERT INTO public.customer_credits(id,tenant_id,customer_id,origin_type,original_amount,issued_date,reissues_refund_id)
 VALUES(c,'00000000-0000-4000-8000-0000000023a1','00000000-0000-4000-8000-0000000023c1','refund_reissue',n,DATE '2026-03-18',r);
 RETURN c;
END $$;


-- Same B1/B2/B3/S1 paths as an application user, inside an owner session.
GRANT EXECUTE ON FUNCTION pg_temp.post(uuid,uuid),pg_temp.payment(numeric),pg_temp.credit(numeric,uuid),pg_temp.refund(uuid,numeric,date),pg_temp.reverse_entry(uuid,numeric,date),pg_temp.escheat(uuid,numeric),pg_temp.reissue(uuid,numeric) TO tally_app;
SET ROLE tally_app;
SELECT set_config('app.user_id','00000000-0000-4000-8000-0000000023b1',true);
DO $$
DECLARE c uuid; r uuid; u uuid; k uuid; e uuid; x record;
BEGIN
 c:=pg_temp.credit(100); r:=pg_temp.refund(c,30); PERFORM pg_temp.escheat(c,70);
 u:=pg_temp.reverse_entry(public.cash_arrival_entry('payment',r),-30,DATE '2026-03-16');
 UPDATE public.payments SET status='reversed',status_cause_id=u WHERE id=r;
 k:=pg_temp.reissue(r,30);
 SET CONSTRAINTS enforce_escheated_credit_settled IMMEDIATE;
 BEGIN
   e:=pg_temp.reverse_entry(u,30,DATE '2026-03-19');
   RAISE NOTICE 'B1 ADMITTED SQLSTATE=00000: restored old refund entry %, refund status %, tree remaining %',e,(SELECT status FROM public.payments WHERE id=r),public.ledger_entry_remaining(public.cash_arrival_entry('payment',r));
 EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'B1 CAUGHT SQLSTATE=% MESSAGE=%',SQLSTATE,SQLERRM; END;
 SELECT * INTO x FROM public.customer_credit_position_as_of(k,DATE '2026-12-31',clock_timestamp());
 RAISE NOTICE 'B1 reissue position=%',row_to_json(x);
 BEGIN
   PERFORM pg_temp.refund(k,30,DATE '2026-03-20');
   RAISE NOTICE 'B1 second refund from reissue ADMITTED SQLSTATE=00000';
 EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'B1 second refund CAUGHT SQLSTATE=% MESSAGE=%',SQLSTATE,SQLERRM; END;
END $$;


SET CONSTRAINTS ALL DEFERRED;
DO $$
DECLARE p uuid; c uuid; u uuid; x record;
BEGIN
 p:=pg_temp.payment(100); c:=pg_temp.credit(100,p);
 u:=pg_temp.reverse_entry(public.cash_arrival_entry('payment',p),20);
 PERFORM pg_temp.escheat(c,80);
 BEGIN
   PERFORM pg_temp.reverse_entry(u,-20,DATE '2026-03-16');
   RAISE NOTICE 'B2 give-back ADMITTED SQLSTATE=00000';
 EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'B2 CAUGHT SQLSTATE=% MESSAGE=%',SQLSTATE,SQLERRM; END;
 SELECT * INTO x FROM public.customer_credit_position_as_of(c,DATE '2026-12-31',clock_timestamp());
 RAISE NOTICE 'B2 credit status=% position=%',(SELECT status FROM public.customer_credits WHERE id=c),row_to_json(x);
 SET CONSTRAINTS ALL IMMEDIATE;
END $$;


SET CONSTRAINTS ALL DEFERRED;
DO $$
DECLARE p uuid; c uuid; r uuid; u uuid; n numeric; x record;
BEGIN
 FOREACH n IN ARRAY ARRAY[100::numeric,30::numeric] LOOP
  -- The enclosing savepoint-like block always rolls back this variant.
  BEGIN
   p:=pg_temp.payment(100); c:=pg_temp.credit(100,p); r:=pg_temp.refund(c,30);
   PERFORM pg_temp.escheat(c,70);
   PERFORM pg_temp.reverse_entry(public.cash_arrival_entry('payment',p),n,DATE '2026-03-16');
   u:=pg_temp.reverse_entry(public.cash_arrival_entry('payment',r),-30,DATE '2026-03-17');
   UPDATE public.payments SET status='reversed',status_cause_id=u WHERE id=r;
   SELECT * INTO x FROM public.customer_credit_position_as_of(c,DATE '2026-12-31',clock_timestamp());
   RAISE NOTICE 'B3 parent take-back=% old credit position=%',n,row_to_json(x);
   BEGIN
    PERFORM pg_temp.reissue(r,30);
    RAISE NOTICE 'B3 take-back=% reissue ADMITTED SQLSTATE=00000',n;
   EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'B3 take-back=% reissue CAUGHT SQLSTATE=% MESSAGE=%',n,SQLSTATE,SQLERRM; END;
   BEGIN
    SET CONSTRAINTS enforce_escheated_credit_settled IMMEDIATE;
    RAISE NOTICE 'B3 take-back=% deferred settlement ADMITTED SQLSTATE=00000, reissue count=%',n,(SELECT count(*) FROM public.customer_credits WHERE reissues_refund_id=r);
   EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'B3 take-back=% settlement CAUGHT SQLSTATE=% MESSAGE=%',n,SQLSTATE,SQLERRM; END;
   RAISE EXCEPTION USING ERRCODE='P0099',MESSAGE='rollback probe variant';
  EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'B3 variant cleanup SQLSTATE=% MESSAGE=%',SQLSTATE,SQLERRM; END;
 END LOOP;
END $$;


SET CONSTRAINTS ALL DEFERRED;
DO $$
DECLARE p uuid; c uuid; x record;
BEGIN
 p:=pg_temp.payment(100); c:=pg_temp.credit(40,p);
 PERFORM pg_temp.reverse_entry(public.cash_arrival_entry('payment',p),20);
 SELECT * INTO x FROM public.payment_position_as_of(p,DATE '2026-12-31',clock_timestamp());
 RAISE NOTICE 'S1 payment position=%',row_to_json(x);
 SELECT * INTO x FROM public.customer_credit_position_as_of(c,DATE '2026-12-31',clock_timestamp());
 RAISE NOTICE 'S1 credit position=%',row_to_json(x);
 BEGIN
 INSERT INTO public.payments(tenant_id,customer_id,payment_number,payment_date,amount,payment_method,refunds_payment_id)
 VALUES('00000000-0000-4000-8000-0000000023a1','00000000-0000-4000-8000-0000000023c1','probe-direct-refund',DATE '2026-03-16',-60,'refund',p);
 RAISE NOTICE 'S1 direct refund 60 ADMITTED SQLSTATE=00000';
 EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'S1 CAUGHT SQLSTATE=% MESSAGE=%',SQLSTATE,SQLERRM; END;
END $$;


RESET ROLE;
ROLLBACK;
