-- NOT EXECUTED. Owner on fresh throwaway clone with frozen r5 applied.
-- Schedule: run A to A1, run B; B edits notes then waits inserting an amount.
-- Resume A's deferred release after B is waiting. One session should print 40P01.
-- This exercises reading row -> dispute lock even without a reading-status move.
-- A commits shared fixtures only. Test transactions end in ROLLBACK. No role DDL.
\set ON_ERROR_STOP on
\set VERBOSITY verbose
BEGIN ISOLATION LEVEL READ COMMITTED;
SET LOCAL app.user_id='00000000-0000-4000-8000-000000002db1';
SET LOCAL ROLE tally_app;
DO $$ BEGIN
 UPDATE public.meter_readings SET notes='probe note edit' WHERE id='00000000-0000-4000-8000-000000002d71';
 INSERT INTO public.dispute_amounts(tenant_id,dispute_id,amount,determined_by,effective_on) VALUES ('00000000-0000-4000-8000-000000002da1','00000000-0000-4000-8000-000000002d31',10,'customer_claim','2026-03-03');
 RAISE NOTICE 'note-first B SQLSTATE=00000 accepted';
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'note-first B SQLSTATE=% message=%',SQLSTATE,SQLERRM;
END $$;
ROLLBACK;
