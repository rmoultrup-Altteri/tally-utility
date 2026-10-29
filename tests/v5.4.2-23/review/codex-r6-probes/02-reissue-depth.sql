-- AUTHOR RUN ONLY: owner session, fresh clone with frozen r6 strictly applied.
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
 SELECT now()
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

-- B2: the upward walk stops at 1000 vertices, the downward walk at 1000 edges.
-- This stress probe may be slow. All ledger trees are depth 1; only the
-- credit/refund lineage is long. No timing conclusion is requested.
DO $$ DECLARE p uuid; root uuid; c uuid; r uuid; e uuid; i integer; x record; BEGIN
 p:=pg_temp.payment(1); root:=pg_temp.credit(1,p); c:=root;
 FOR i IN 1..1000 LOOP
  r:=pg_temp.refund(c,1,DATE '2026-03-18');
  PERFORM pg_temp.return_refund(r,1,DATE '2026-03-18');
  c:=pg_temp.reissue(r,1);
  IF i IN (1,999,1000) THEN
   RAISE NOTICE 'B2 generation=% credit=% root=% family_count=%',i,c,
    public.overpayment_root(c),(SELECT count(*) FROM public.overpayment_family(root));
  END IF;
 END LOOP;
 SET CONSTRAINTS ALL IMMEDIATE;
 e:=pg_temp.reverse_entry(public.cash_arrival_entry('payment',p),1,DATE '2026-03-19');
 UPDATE public.payments SET status='reversed',status_cause_id=e,status_recorded_at=pg_temp.tick() WHERE id=p;
 SELECT * INTO x FROM public.customer_credit_position_as_of(c,DATE '2026-12-31',clock_timestamp());
 RAISE NOTICE 'B2 generation 1000 after full payment return=%',row_to_json(x);
 BEGIN
  PERFORM pg_temp.refund(c,1,DATE '2026-03-20');
  SET CONSTRAINTS ALL IMMEDIATE;
  RAISE NOTICE 'B2 refund AFTER full parent return ADMITTED SQLSTATE=00000';
 EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'B2 final refund CAUGHT SQLSTATE=% MESSAGE=%',SQLSTATE,SQLERRM;
 END;
END $$;
ROLLBACK;
