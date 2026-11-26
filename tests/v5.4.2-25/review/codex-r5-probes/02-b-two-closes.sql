-- NOT EXECUTED. Owner on a FRESH THROWAWAY clone with frozen r5 applied.
-- No roles are created, dropped or altered. Only A commits the shared fixture.
-- The author drops the scratch clone afterward. Both files end in ROLLBACK.
\set ON_ERROR_STOP on
\set VERBOSITY verbose
-- SCHEDULE: run after 02-a reaches its prompt. Expected: waits for A, then 23514 [T2c].
BEGIN ISOLATION LEVEL READ COMMITTED;
SET LOCAL search_path=public,pg_temp;
SET LOCAL app.user_id='00000000-0000-4000-8000-000000002db1';
SET LOCAL ROLE tally_app;
INSERT INTO public.dispute_events(tenant_id,dispute_id,event_type,occurred_on) VALUES ('00000000-0000-4000-8000-000000002da1','00000000-0000-4000-8000-000000002d32','withdrawn','2026-03-03');
DO $$ BEGIN
 SET CONSTRAINTS public.zz_dispute_reading_released IMMEDIATE;
 RAISE NOTICE 'B SQLSTATE=00000 release accepted';
EXCEPTION WHEN OTHERS THEN
 RAISE NOTICE 'B SQLSTATE=% message=%',SQLSTATE,SQLERRM;
END $$;
ROLLBACK;
