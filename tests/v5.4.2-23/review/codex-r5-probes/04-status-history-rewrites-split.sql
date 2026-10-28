-- AUTHOR RUN ONLY: owner session, fresh clone with frozen r5 strictly applied.
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
DO $$ BEGIN
 IF NOT (SELECT rolsuper FROM pg_roles WHERE rolname=current_user) THEN
   RAISE EXCEPTION 'This history-load probe requires the superuser clone owner';
 END IF;
END $$;
CREATE TEMP SEQUENCE probe_clock;
CREATE FUNCTION pg_temp.tick() RETURNS timestamptz LANGUAGE sql VOLATILE AS $$
 SELECT now() - interval '1 day' + nextval('pg_temp.probe_clock') * interval '1 minute'
$$;
CREATE FUNCTION pg_temp.post(p_pay uuid, p_entry uuid) RETURNS void LANGUAGE plpgsql AS $$
DECLARE p public.payments%ROWTYPE;
BEGIN
  SELECT * INTO p FROM public.payments WHERE id = p_pay;
  INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reference_type, reference_id, created_at)
  VALUES (p_entry, p.tenant_id, p.customer_id, p.payment_date,
          CASE WHEN p.refunds_payment_id IS NOT NULL OR p.refunds_customer_credit_id IS NOT NULL THEN 'refund' WHEN p.is_deposit THEN 'deposit' ELSE 'payment' END,
          p.payment_number || ' posted', -p.amount, 'payment', p.id, pg_temp.tick());
  UPDATE public.payments SET status = 'posted', status_cause_id = p_entry, status_recorded_at = pg_temp.tick(),
         effective_date = coalesce(effective_date, payment_date), effective_date_method = coalesce(effective_date_method, 'other')
   WHERE id = p_pay;
END $$;

CREATE FUNCTION pg_temp.payment(n numeric) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE p uuid := public.uuid_generate_v4();
BEGIN
 INSERT INTO public.payments(id,tenant_id,customer_id,payment_number,payment_date,amount,payment_method,created_at)
 VALUES(p,'00000000-0000-4000-8000-0000000023a1','00000000-0000-4000-8000-0000000023c1',p::text,DATE '2026-03-10',n,'check',pg_temp.tick());
 PERFORM pg_temp.post(p,public.uuid_generate_v4()); RETURN p;
END $$;
CREATE FUNCTION pg_temp.credit(n numeric, p uuid DEFAULT NULL) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE c uuid := public.uuid_generate_v4(); a uuid;
BEGIN
 IF p IS NOT NULL THEN
   a := public.uuid_generate_v4();
   INSERT INTO public.customer_credit_approvals(id,tenant_id,customer_id,payment_id,amount,approved_by,created_at)
   VALUES(a,'00000000-0000-4000-8000-0000000023a1','00000000-0000-4000-8000-0000000023c1',p,n,'00000000-0000-4000-8000-0000000023b1',pg_temp.tick());
 END IF;
 INSERT INTO public.customer_credits(id,tenant_id,customer_id,origin_type,original_amount,issued_date,source_payment_id,approval_id,created_at)
 VALUES(c,'00000000-0000-4000-8000-0000000023a1','00000000-0000-4000-8000-0000000023c1',CASE WHEN p IS NULL THEN 'goodwill' ELSE 'overpayment' END,n,DATE '2026-03-11',p,a,pg_temp.tick());
 IF p IS NULL THEN
   INSERT INTO public.account_ledger(tenant_id,customer_id,transaction_date,transaction_type,description,amount,reference_type,reference_id,created_at)
   VALUES('00000000-0000-4000-8000-0000000023a1','00000000-0000-4000-8000-0000000023c1',DATE '2026-03-11','credit_issued','probe',-n,'customer_credit',c,pg_temp.tick());
 END IF;
 RETURN c;
END $$;
CREATE FUNCTION pg_temp.refund(c uuid,n numeric,d date DEFAULT DATE '2026-03-12') RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE r uuid := public.uuid_generate_v4();
BEGIN
 INSERT INTO public.payments(id,tenant_id,customer_id,payment_number,payment_date,amount,payment_method,refunds_customer_credit_id,created_at)
 VALUES(r,'00000000-0000-4000-8000-0000000023a1','00000000-0000-4000-8000-0000000023c1',r::text,d,-n,'refund',c,pg_temp.tick());
 PERFORM pg_temp.post(r,public.uuid_generate_v4()); RETURN r;
END $$;
CREATE FUNCTION pg_temp.reverse_entry(e uuid,n numeric,d date DEFAULT DATE '2026-03-14') RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE k uuid := public.uuid_generate_v4();
BEGIN
 INSERT INTO public.account_ledger(id,tenant_id,customer_id,transaction_date,transaction_type,description,amount,reverses_ledger_entry_id,created_at)
 VALUES(k,'00000000-0000-4000-8000-0000000023a1','00000000-0000-4000-8000-0000000023c1',d,'adjustment','probe correction',n,e,pg_temp.tick());
 RETURN k;
END $$;
CREATE FUNCTION pg_temp.escheat(c uuid,n numeric) RETURNS void LANGUAGE plpgsql AS $$
DECLARE e uuid := public.uuid_generate_v4();
BEGIN
 INSERT INTO public.escheatment_events(id,tenant_id,customer_credit_id,customer_id,event_type,amount_related,event_date,created_at)
 VALUES(e,'00000000-0000-4000-8000-0000000023a1',c,'00000000-0000-4000-8000-0000000023c1','escheated_to_state',n,TIMESTAMPTZ '2026-03-15 12:00Z',pg_temp.tick());
 UPDATE public.customer_credits SET status='escheated',status_cause_id=e,status_recorded_at=pg_temp.tick() WHERE id=c;
END $$;
CREATE FUNCTION pg_temp.reissue(r uuid,n numeric) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE c uuid := public.uuid_generate_v4();
BEGIN
 INSERT INTO public.customer_credits(id,tenant_id,customer_id,origin_type,original_amount,issued_date,reissues_refund_id,created_at)
 VALUES(c,'00000000-0000-4000-8000-0000000023a1','00000000-0000-4000-8000-0000000023c1','refund_reissue',n,DATE '2026-03-18',r,pg_temp.tick());
 RETURN c;
END $$;


CREATE FUNCTION pg_temp.direct_refund(p uuid,n numeric,d date DEFAULT DATE '2026-03-12') RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE r uuid := public.uuid_generate_v4();
BEGIN
 INSERT INTO public.payments(id,tenant_id,customer_id,payment_number,payment_date,amount,payment_method,refunds_payment_id,created_at)
 VALUES(r,'00000000-0000-4000-8000-0000000023a1','00000000-0000-4000-8000-0000000023c1',r::text,d,-n,'refund',p,pg_temp.tick());
 PERFORM pg_temp.post(r,public.uuid_generate_v4()); RETURN r;
END $$;
CREATE FUNCTION pg_temp.return_refund(r uuid,n numeric,d date DEFAULT DATE '2026-03-16') RETURNS void LANGUAGE plpgsql AS $$
DECLARE e uuid;
BEGIN
 e := pg_temp.reverse_entry(public.cash_arrival_entry('payment',r),-n,d);
 UPDATE public.payments SET status='reversed', status_cause_id=e,status_recorded_at=pg_temp.tick() WHERE id=r;
END $$;
CREATE FUNCTION pg_temp.positions(label text,p uuid,c uuid) RETURNS void LANGUAGE plpgsql AS $$
DECLARE x record;
BEGIN
 SELECT * INTO x FROM public.payment_position_as_of(p,DATE '2026-12-31',clock_timestamp());
 RAISE NOTICE '% payment=%',label,row_to_json(x);
 SELECT * INTO x FROM public.customer_credit_position_as_of(c,DATE '2026-12-31',clock_timestamp());
 RAISE NOTICE '% credit=%',label,row_to_json(x);
 RAISE NOTICE '% split=%',label,(SELECT jsonb_agg(to_jsonb(s)) FROM public.overpayment_split(c) s);
END $$;


-- Predicted B4: finite past status correction restores cash to an ended credit.
-- All writes keep all triggers enabled. No timestamp is future or infinite.
DO $$ DECLARE p uuid; c uuid; r uuid; t timestamptz; x record; BEGIN
 p:=pg_temp.payment(60); c:=pg_temp.credit(20,p); r:=pg_temp.refund(c,20);
 PERFORM pg_temp.return_refund(r,20,DATE '2026-03-13');
 -- Flush the active-credit return's deferred check before escheat.
 SET CONSTRAINTS ALL IMMEDIATE;
 SET CONSTRAINTS ALL DEFERRED;
 PERFORM pg_temp.reverse_entry(public.cash_arrival_entry('payment',p),10);
 SELECT max(created_at) INTO t FROM public.overpayment_split(c);
 PERFORM pg_temp.escheat(c,10);
 PERFORM pg_temp.positions('escheated with zero left',p,c);
 SELECT * INTO x FROM public.customer_credit_position_as_of(c,DATE '2026-12-31',t);
 RAISE NOTICE 'past credit before correction=%',row_to_json(x);
 BEGIN
  UPDATE public.payments SET status_recorded_at=t+interval '30 seconds' WHERE id=r;
  SET CONSTRAINTS ALL IMMEDIATE;
  RAISE NOTICE 'past-only status timestamp correction and deferred checks ADMITTED SQLSTATE=00000';
 EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'correction CAUGHT SQLSTATE=% MESSAGE=%',SQLSTATE,SQLERRM; END;
 PERFORM pg_temp.positions('after timestamp correction',p,c);
 SELECT * INTO x FROM public.customer_credit_position_as_of(c,DATE '2026-12-31',t);
 RAISE NOTICE 'past credit after correction=%',row_to_json(x);
END $$;
ROLLBACK;
