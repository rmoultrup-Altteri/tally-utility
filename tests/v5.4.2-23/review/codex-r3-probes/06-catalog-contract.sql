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


DO $$ BEGIN
 PERFORM public.assert_cash_guard_invariants();
 PERFORM public.assert_periods_guard_invariants();
 PERFORM public.assert_seal_role_invariants();
 RAISE NOTICE 'baseline invariants SQLSTATE=00000';
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'baseline SQLSTATE=% message=%',SQLSTATE,SQLERRM;
END $$;
SELECT r.rolname,c.relname,has_table_privilege(r.rolname,c.oid,'SELECT') AS can_read,
 has_table_privilege(r.rolname,c.oid,'INSERT') AS can_insert,
 has_any_column_privilege(r.rolname,c.oid,'UPDATE') AS can_update_column
FROM pg_roles r CROSS JOIN pg_class c
WHERE r.rolname IN ('tally_app','tally_core','tally_void','tally_close')
 AND c.oid IN ('public.account_ledger'::regclass,'public.payments'::regclass,'public.customer_credits'::regclass,'public.invoice_applications'::regclass);
SELECT r.rolname,has_function_privilege(r.rolname,'public.check_cash_source(text,uuid,timestamptz,text,date)','EXECUTE') AS cap_execute
FROM pg_roles r WHERE r.rolname IN ('tally_app','tally_core','tally_void','tally_close');
-- Witness installed bodies/trigger paths without claiming a two-session execution.
SELECT p.oid::regprocedure,pg_get_functiondef(p.oid) FROM pg_proc p
 WHERE p.oid IN ('public.enforce_ledger_reversal()'::regprocedure,
 'public.enforce_payment_immutable()'::regprocedure,
 'public.enforce_customer_credit_immutable()'::regprocedure,
 'public.check_cash_source(text,uuid,timestamptz,text,date)'::regprocedure);
SAVEPOINT drift;
REVOKE EXECUTE ON FUNCTION public.check_cash_source(text,uuid,timestamptz,text,date) FROM tally_app;
SELECT pg_temp.attempt('app execute drift should fail invariant', 'SELECT public.assert_cash_guard_invariants()');
ROLLBACK TO drift;
CREATE POLICY codex_extra ON public.customer_credit_approvals USING (true);
SELECT pg_temp.attempt('extra policy should fail invariant', 'SELECT public.assert_cash_guard_invariants()');
ROLLBACK TO drift;
ALTER TABLE public.payments DROP CONSTRAINT payments_refund_is_refund_check;
SELECT pg_temp.attempt('refund sign drift should fail invariant', 'SELECT public.assert_cash_guard_invariants()');
ROLLBACK TO drift;
ALTER TABLE public.customer_credits DROP CONSTRAINT customer_credits_original_amount_check;
SELECT pg_temp.attempt('credit amount drift should fail invariant', 'SELECT public.assert_cash_guard_invariants()');
ROLLBACK TO drift;
DROP TRIGGER a_stamp_created_at ON public.escheatment_events;
SELECT pg_temp.attempt('escheat stamp drift should fail invariant', 'SELECT public.assert_cash_guard_invariants()');
ROLLBACK TO drift;
-- Explicit owner history exception, not treated as an app exploit.
INSERT INTO public.payments(id,tenant_id,customer_id,payment_number,payment_date,amount,payment_method,status,effective_date,effective_date_method)
 VALUES(pg_temp.uid(10),pg_temp.uid(1),pg_temp.uid(2),'CX-history',CURRENT_DATE-10,50,'check','nsf',CURRENT_DATE-10,'other');
SELECT status,status_cause_id,status_recorded_at FROM public.payments WHERE id=pg_temp.uid(10);
ROLLBACK;
