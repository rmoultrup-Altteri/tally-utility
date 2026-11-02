-- AUTHOR RUN ONLY. Owner sessions on the same fresh clone with frozen r8 applied.
-- Revoke clone TEMP from PUBLIC, tally_app and tally_core first. No role DDL.
-- Extracted CR26 advisory-lock order ONLY, not an end-to-end trigger race.
-- Start A; when it prints 'start B now', start B in the other session.
-- Expected both complete; timeout, missing overlap, or any error is inconclusive/failure.
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL lock_timeout = '15s';
DO $$ BEGIN
  PERFORM pg_advisory_xact_lock(public.ledger_tree_lock_key('00000000-0000-4000-8000-000000009713'));
  PERFORM pg_advisory_xact_lock(public.cash_source_lock_key('payment','00000000-0000-4000-8000-000000009711'));
  PERFORM pg_advisory_xact_lock(public.cash_source_lock_key('credit','00000000-0000-4000-8000-000000009712'));
  RAISE NOTICE 'B completed SQLSTATE=00000';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'B caught SQLSTATE=% message=%',SQLSTATE,SQLERRM;
END $$;
ROLLBACK;
