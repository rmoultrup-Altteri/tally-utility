-- AUTHOR RUN ONLY: owner sessions on one fresh clone with frozen r7 applied.
-- Revoke TEMP from PUBLIC, tally_app and tally_core before running.
-- Extracted lock topology only, NOT an end-to-end cash-trigger race.
-- Start C, then A within 2 seconds, then B within 2 more seconds.
-- Expected all finish, no 40P01; timeout is inconclusive, not a pass.
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL lock_timeout = '15s';
DO $$ BEGIN
  PERFORM pg_advisory_xact_lock(public.cash_source_lock_key('payment','00000000-0000-4000-8000-000000009701'));
  RAISE NOTICE 'session B acquired P';
  PERFORM pg_advisory_xact_lock(public.cash_source_lock_key('credit','00000000-0000-4000-8000-000000009702'));
  RAISE NOTICE 'session B acquired R';
  PERFORM pg_advisory_xact_lock(public.cash_source_lock_key('credit','00000000-0000-4000-8000-000000009703'));
  RAISE NOTICE 'session B acquired K';
  RAISE NOTICE 'session B completed SQLSTATE=00000';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'session B caught SQLSTATE=% message=%',SQLSTATE,SQLERRM;
END $$;
ROLLBACK;
