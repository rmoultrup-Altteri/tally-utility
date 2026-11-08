-- Codex r6: PREDICTED, NOT EXECUTED. Owner; fresh clone with frozen r6 applied.
-- No role changes. A local schema-drift probe, fully rolled back.
\set ON_ERROR_STOP on
BEGIN;
DO $$
BEGIN
 PERFORM public.assert_suspense_pledge_guard_invariants();
 RAISE NOTICE 'S2 baseline SQLSTATE=00000 message=invariant returned';
EXCEPTION WHEN OTHERS THEN
 RAISE NOTICE 'S2 baseline SQLSTATE=% message=%',SQLSTATE,SQLERRM;
 RAISE;
END $$;
SAVEPOINT missing_helper;
DO $$
BEGIN
 -- No CASCADE: an unexpected dependency is printed, never removed.
 DROP FUNCTION public.cash_source_lock_key(text, uuid);
 RAISE NOTICE 'S2 DROP SQLSTATE=00000 message=helper removed locally';
 PERFORM public.assert_suspense_pledge_guard_invariants();
 RAISE NOTICE 'S2 predicted blind spot SQLSTATE=00000 message=invariant accepted missing required app helper';
EXCEPTION WHEN OTHERS THEN
 RAISE NOTICE 'S2 drop/invariant SQLSTATE=% message=%',SQLSTATE,SQLERRM;
END $$;
ROLLBACK TO missing_helper;
ROLLBACK;
