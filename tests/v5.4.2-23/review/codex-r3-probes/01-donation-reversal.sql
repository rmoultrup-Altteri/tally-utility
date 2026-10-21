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

-- B1: all three rows in the donation tree satisfy X2, but restoring the
-- donation after spending the released balance exceeds the CREDIT cap.
SELECT pg_temp.credit(10);
SELECT pg_temp.entry(20,100,'donation',NULL,'customer_credit',10);
SELECT pg_temp.entry(21,-100,'adjustment',20);
SELECT pg_temp.refund(30,10,100);
SAVEPOINT shapes;
SELECT pg_temp.attempt('B1 restore donation after refund',
 $$SELECT pg_temp.entry(22,100,'adjustment',21,NULL,NULL,CURRENT_DATE-3)$$);
SELECT 'B1 predicted refunded=100 given_up=100 remaining=-100' AS observation,p.*
 FROM public.customer_credit_position_as_of(pg_temp.uid(10),CURRENT_DATE,clock_timestamp()) p;
ROLLBACK TO shapes;
SELECT pg_temp.attempt('B1 multi-row restore donation', $q$
 INSERT INTO public.account_ledger(id,tenant_id,customer_id,transaction_date,transaction_type,description,amount,reverses_ledger_entry_id)
 VALUES(pg_temp.uid(22),pg_temp.uid(1),pg_temp.uid(2),CURRENT_DATE-3,'adjustment','half one',50,pg_temp.uid(21)),
       (pg_temp.uid(23),pg_temp.uid(1),pg_temp.uid(2),CURRENT_DATE-3,'adjustment','half two',50,pg_temp.uid(21))$q$);
SELECT 'B1 multi-row' AS observation,p.* FROM public.customer_credit_position_as_of(pg_temp.uid(10),CURRENT_DATE,clock_timestamp()) p;
ROLLBACK TO shapes;
SELECT pg_temp.attempt('B1 writable CTE restore donation', $q$
 WITH restored AS (
 INSERT INTO public.account_ledger(id,tenant_id,customer_id,transaction_date,transaction_type,description,amount,reverses_ledger_entry_id)
 VALUES(pg_temp.uid(22),pg_temp.uid(1),pg_temp.uid(2),CURRENT_DATE-3,'adjustment','CTE half',50,pg_temp.uid(21)) RETURNING id)
 INSERT INTO public.account_ledger(id,tenant_id,customer_id,transaction_date,transaction_type,description,amount,reverses_ledger_entry_id)
 SELECT pg_temp.uid(23),pg_temp.uid(1),pg_temp.uid(2),CURRENT_DATE-3,'adjustment','second half',50,pg_temp.uid(21) FROM restored$q$);
SELECT 'B1 CTE' AS observation,p.* FROM public.customer_credit_position_as_of(pg_temp.uid(10),CURRENT_DATE,clock_timestamp()) p;
-- A separate history: an undo frees money after the credit has ended.
SELECT pg_temp.credit(40);
SELECT pg_temp.entry(50,30,'donation',NULL,'customer_credit',40);
INSERT INTO public.escheatment_events(id,tenant_id,customer_id,customer_credit_id,event_type,amount_related,event_date)
 VALUES(pg_temp.uid(60),pg_temp.uid(1),pg_temp.uid(2),pg_temp.uid(40),'escheated_to_state',70,(CURRENT_DATE-4)::timestamp AT TIME ZONE 'UTC');
UPDATE public.customer_credits SET status='escheated',status_cause_id=pg_temp.uid(60) WHERE id=pg_temp.uid(40);
SELECT pg_temp.attempt('B1 undo donation after escheat',
 $$SELECT pg_temp.entry(51,-30,'adjustment',50,NULL,NULL,CURRENT_DATE-3)$$);
SELECT 'B1 predicted escheated with remaining=30' AS observation,c.status,p.*
 FROM public.customer_credits c CROSS JOIN LATERAL public.customer_credit_position_as_of(c.id,CURRENT_DATE,clock_timestamp()) p WHERE c.id=pg_temp.uid(40);
ROLLBACK;
