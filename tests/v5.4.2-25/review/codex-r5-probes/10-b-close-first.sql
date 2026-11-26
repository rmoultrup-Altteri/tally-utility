-- NOT EXECUTED. Owner on fresh throwaway clone with frozen r5 applied.
-- Schedule: run A to A1, run B until its UPDATE blocks, resume A.
-- Predicted: 40P01 in one session; after victim rollback the survivor completes.
-- This is the documented close/reading-move inversion, close-first direction.
-- A commits only shared fixtures. No role DDL. Both files end ROLLBACK.
\set ON_ERROR_STOP on
\set VERBOSITY verbose
BEGIN ISOLATION LEVEL READ COMMITTED;
SET LOCAL app.user_id='00000000-0000-4000-8000-000000002db1';
SET LOCAL ROLE tally_app;
DO $$ BEGIN
 UPDATE public.meter_readings SET status='disputed' WHERE id='00000000-0000-4000-8000-000000002d71';
 RAISE NOTICE 'close-first B SQLSTATE=00000 accepted';
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'close-first B SQLSTATE=% message=%',SQLSTATE,SQLERRM;
END $$;
ROLLBACK;
