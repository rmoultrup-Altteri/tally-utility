-- AUTHOR RUN ONLY: owner, fresh clone with frozen r6 applied and clone TEMP revoked.
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL search_path=public,pg_temp;
SELECT current_user, current_setting('transaction_isolation');
SELECT c.relname,g.tgname,g.tgenabled,pg_get_triggerdef(g.oid)
FROM pg_trigger g JOIN pg_class c ON c.oid=g.tgrelid
WHERE NOT g.tgisinternal AND c.relname IN ('payments','customer_credits','account_ledger','invoice_applications','escheatment_events') ORDER BY 1,2;
SELECT p.oid::regprocedure,p.prosecdef,p.proconfig,pg_get_functiondef(p.oid)
FROM pg_proc p WHERE p.oid IN (
 'public.enforce_ledger_reversal()'::regprocedure,
 'public.enforce_payment_immutable()'::regprocedure,
 'public.enforce_customer_credit_immutable()'::regprocedure,
 'public.check_cash_source(text,uuid,timestamptz,text,date)'::regprocedure,
 'public.enforce_escheated_credit_settled()'::regprocedure);
DO $$ BEGIN
 PERFORM public.assert_cash_guard_invariants();
 PERFORM public.assert_seal_role_invariants();
 PERFORM public.assert_core_role_invariants();
 PERFORM public.assert_tenant_isolation_invariants();
 RAISE NOTICE 'baseline invariants ADMITTED SQLSTATE=00000';
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'invariants CAUGHT SQLSTATE=% MESSAGE=%',SQLSTATE,SQLERRM; END $$;
SELECT pg_get_functiondef('public.overpayment_split(uuid)'::regprocedure);
SELECT pg_get_functiondef('public.cash_drawn_at(text,uuid,timestamptz)'::regprocedure);
ROLLBACK;
