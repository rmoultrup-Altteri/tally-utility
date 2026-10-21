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


-- Codex r3 B1 closure in two statement shapes beyond frozen V8.
DO $$
DECLARE c uuid; d uuid:=public.uuid_generate_v4(); u uuid;
BEGIN
 c:=pg_temp.credit(100);
 INSERT INTO public.account_ledger(id,tenant_id,customer_id,transaction_date,transaction_type,description,amount,reference_type,reference_id)
 VALUES(d,'00000000-0000-4000-8000-0000000023a1','00000000-0000-4000-8000-0000000023c1',DATE '2026-03-12','donation','probe',100,'customer_credit',c);
 u:=pg_temp.reverse_entry(d,-100,DATE '2026-03-13');
 PERFORM pg_temp.refund(c,100,DATE '2026-03-14');
 BEGIN
 INSERT INTO public.account_ledger(tenant_id,customer_id,transaction_date,transaction_type,description,amount,reverses_ledger_entry_id)
 SELECT '00000000-0000-4000-8000-0000000023a1'::uuid,'00000000-0000-4000-8000-0000000023c1'::uuid,DATE '2026-03-15','adjustment','multi-row',50,u FROM generate_series(1,2);
 RAISE NOTICE 'donation multi-row ADMITTED SQLSTATE=00000 (unexpected)';
 EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'donation multi-row CAUGHT SQLSTATE=% MESSAGE=%',SQLSTATE,SQLERRM; END;
 BEGIN
 WITH a AS (
 INSERT INTO public.account_ledger(tenant_id,customer_id,transaction_date,transaction_type,description,amount,reverses_ledger_entry_id)
 VALUES('00000000-0000-4000-8000-0000000023a1','00000000-0000-4000-8000-0000000023c1',DATE '2026-03-15','adjustment','CTE first',50,u) RETURNING id)
 INSERT INTO public.account_ledger(tenant_id,customer_id,transaction_date,transaction_type,description,amount,reverses_ledger_entry_id)
 SELECT '00000000-0000-4000-8000-0000000023a1'::uuid,'00000000-0000-4000-8000-0000000023c1'::uuid,DATE '2026-03-15','adjustment','CTE second',50,u FROM a;
 RAISE NOTICE 'donation CTE ADMITTED SQLSTATE=00000 (unexpected)';
 EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'donation CTE CAUGHT SQLSTATE=% MESSAGE=%',SQLSTATE,SQLERRM; END;
END $$;
ROLLBACK;
