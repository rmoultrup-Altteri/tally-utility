-- PREDICTED; NOT EXECUTED. Run as owner on a fresh clone with frozen r3 applied.
-- No role changes, persistent fixtures or commits. Every caught error prints its state/message.
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL search_path = public, pg_temp;
CREATE FUNCTION pg_temp.uid(n integer) RETURNS uuid LANGUAGE sql IMMUTABLE AS $$
 SELECT ('c0de0003-0000-4000-8000-' || lpad(n::text,12,'0'))::uuid
$$;
INSERT INTO public.tenants(id,name,slug) VALUES(pg_temp.uid(1),'Codex r3','codex-r3');
INSERT INTO public.customers(id,tenant_id,customer_number,customer_type)
 VALUES(pg_temp.uid(2),pg_temp.uid(1),'CX-R3','residential');
CREATE FUNCTION pg_temp.attempt(label text, command text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
 EXECUTE command;
 RAISE NOTICE '% ACCEPTED SQLSTATE=00000',label;
EXCEPTION WHEN OTHERS THEN
 RAISE NOTICE '% SQLSTATE=% message=%',label,SQLSTATE,SQLERRM;
END $$;
CREATE FUNCTION pg_temp.entry(n integer, amt numeric, typ text, parent integer DEFAULT NULL,
 refkind text DEFAULT NULL, refnum integer DEFAULT NULL, day date DEFAULT CURRENT_DATE-5)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
 INSERT INTO public.account_ledger(id,tenant_id,customer_id,transaction_date,transaction_type,description,amount,reverses_ledger_entry_id,reference_type,reference_id)
 VALUES(pg_temp.uid(n),pg_temp.uid(1),pg_temp.uid(2),day,typ,'Codex r3 probe',amt,pg_temp.uid(parent),refkind,pg_temp.uid(refnum));
END $$;
CREATE FUNCTION pg_temp.credit(n integer, amt numeric DEFAULT 100) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
 INSERT INTO public.customer_credits(id,tenant_id,customer_id,origin_type,original_amount,issued_date)
 VALUES(pg_temp.uid(n),pg_temp.uid(1),pg_temp.uid(2),'goodwill',amt,CURRENT_DATE-10);
 PERFORM pg_temp.entry(n+1000,-amt,'credit_issued',NULL,'customer_credit',n,CURRENT_DATE-10);
END $$;
CREATE FUNCTION pg_temp.refund(n integer, src integer, amt numeric, kind text DEFAULT 'credit', day date DEFAULT CURRENT_DATE-4)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
 INSERT INTO public.payments(id,tenant_id,customer_id,payment_number,payment_date,amount,payment_method,refunds_customer_credit_id,refunds_payment_id)
 VALUES(pg_temp.uid(n),pg_temp.uid(1),pg_temp.uid(2),'CX-'||n,day,-amt,'refund',
 CASE WHEN kind='credit' THEN pg_temp.uid(src) END,CASE WHEN kind='payment' THEN pg_temp.uid(src) END);
END $$;
CREATE FUNCTION pg_temp.payment(n integer, amt numeric, day date DEFAULT CURRENT_DATE-10, ledgerday date DEFAULT CURRENT_DATE-10)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
 INSERT INTO public.payments(id,tenant_id,customer_id,payment_number,payment_date,amount,payment_method)
 VALUES(pg_temp.uid(n),pg_temp.uid(1),pg_temp.uid(2),'CX-'||n,day,amt,'check');
 PERFORM pg_temp.entry(n+1000,-amt,'payment',NULL,'payment',n,ledgerday);
 UPDATE public.payments SET status='posted',status_cause_id=pg_temp.uid(n+1000),effective_date=day,effective_date_method='other' WHERE id=pg_temp.uid(n);
END $$;

-- B3: source date and arrival ledger date need not agree. The root is
-- excluded from check_cash_source's dated sum and v_amount exists at all dates.
SELECT pg_temp.payment(10,100,CURRENT_DATE-10,CURRENT_DATE-2);
SELECT pg_temp.attempt('B3 refund dated before ledger arrival',
 $$SELECT pg_temp.refund(20,10,30,'payment',CURRENT_DATE-5)$$);
SELECT 'B3 predicted received=0 refunded=30 remaining=-30 without a bounce' AS observation,p.*
 FROM public.payment_position_as_of(pg_temp.uid(10),CURRENT_DATE-5,clock_timestamp()) p;
INSERT INTO public.customer_credits(id,tenant_id,customer_id,origin_type,original_amount,issued_date)
 VALUES(pg_temp.uid(30),pg_temp.uid(1),pg_temp.uid(2),'goodwill',100,CURRENT_DATE-10);
SELECT pg_temp.entry(1030,-100,'credit_issued',NULL,'customer_credit',30,CURRENT_DATE-2);
SELECT pg_temp.attempt('B3 donation dated before credit ledger arrival',
 $$SELECT pg_temp.entry(40,30,'donation',NULL,'customer_credit',30,CURRENT_DATE-5)$$);
SELECT 'B3 predicted issued=0 given_up=30 remaining=-30' AS observation,p.*
 FROM public.customer_credit_position_as_of(pg_temp.uid(30),CURRENT_DATE-5,clock_timestamp()) p;
ROLLBACK;
