-- Codex r10: AUTHOR RUN ONLY, unexecuted. Run as owner on a fresh clone
-- with frozen r10 strictly applied and clone TEMP revoked from PUBLIC, tally_app, tally_core.
-- No role DDL; all work rolls back.
-- AUTHOR RUN ONLY: owner, fresh clone with frozen r10 applied and clone TEMP revoked.
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
-- r10's helper is an invoker read; inspect its grants and pin set too.
SELECT p.oid::regprocedure, p.prosecdef, p.provolatile, p.proconfig,
       has_function_privilege('tally_app',p.oid,'EXECUTE') AS app_exec,
       has_function_privilege('tally_core',p.oid,'EXECUTE') AS core_exec,
       has_function_privilege('public',p.oid,'EXECUTE') AS public_exec
FROM pg_proc p WHERE p.oid IN (
 'public.customer_credit_own_remaining_as_of(uuid,date,timestamp with time zone)'::regprocedure,
 'public.reissue_generation(uuid)'::regprocedure,
 'public.overpayment_root(uuid)'::regprocedure,
 'public.overpayment_family(uuid)'::regprocedure,
 'public.cash_source_draws(text,uuid)'::regprocedure);
ROLLBACK;
