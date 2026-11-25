-- Codex r11: PREDICTED, NOT EXECUTED. Owner on a fresh clone with frozen r11 applied.
-- Revoke clone TEMP from PUBLIC, tally_app and tally_core before patch application.
-- No role creation/alteration. Each file is independent and ends in ROLLBACK.
\set ON_ERROR_STOP on
-- Codex r11: PREDICTED, NOT EXECUTED. Owner; fresh clone with frozen r11 applied.
\set ON_ERROR_STOP on
BEGIN;
DO $$
BEGIN
 PERFORM public.assert_suspense_pledge_guard_invariants();
 PERFORM public.assert_shortfall_guard_invariants();
 PERFORM public.assert_cash_guard_invariants();
 PERFORM public.assert_periods_guard_invariants();
 RAISE NOTICE 'catalog controls SQLSTATE=00000 message=all four invariants returned';
EXCEPTION WHEN OTHERS THEN
 RAISE NOTICE 'catalog controls SQLSTATE=% message=%',SQLSTATE,SQLERRM;
END $$;
-- Establish actual trigger ordering and inherited ALWAYS lineage guard.
SELECT c.relname,t.tgname,t.tgenabled,pg_get_triggerdef(t.oid)
FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid
WHERE NOT t.tgisinternal AND t.tgrelid IN ('public.payments'::regclass,'public.account_ledger'::regclass)
ORDER BY c.relname,t.tgname;
SELECT p.oid::regprocedure,p.provolatile,p.proconfig
FROM pg_proc p WHERE p.oid IN ('public.enforce_suspense_disposition()'::regprocedure,'public.check_suspense_receipt_cap(uuid)'::regprocedure);
-- The downward walk relies on this inherited writer validation; no claim of
-- benchmarking a 1000-level chain or certifying its plan is made here.
SELECT p.oid::regprocedure,pg_get_functiondef(p.oid)
FROM pg_proc p WHERE p.oid IN
 (SELECT tgfoid FROM pg_trigger WHERE tgrelid='public.account_ledger'::regclass AND tgname ILIKE '%lineage%');
-- Effective grants and every live definer mentioning the ledger.
SELECT r.rolname,has_table_privilege(r.oid,'public.account_ledger','INSERT') AS ledger_insert,
 has_table_privilege(r.oid,'public.account_ledger','SELECT') AS ledger_select,
 has_table_privilege(r.oid,'public.payments','SELECT') AS payments_select
FROM pg_roles r WHERE r.rolname IN ('tally_app','tally_core','tally_void','tally_seal','tally_close',current_user);
SELECT p.oid::regprocedure,pg_get_userbyid(p.proowner),p.prosecdef
FROM pg_proc p WHERE p.pronamespace='public'::regnamespace AND p.prosecdef AND p.prosrc ILIKE '%account_ledger%';
ROLLBACK;
