-- NOT EXECUTED. Owner on a FRESH THROWAWAY clone with frozen r6 applied.
-- No roles are created, dropped or altered. Only A commits the shared fixture.
-- The author drops the scratch clone afterward. Both files end in ROLLBACK.
\set ON_ERROR_STOP on
\set VERBOSITY verbose
-- SCHEDULE: after A reaches A1, run B. At B1 resume A, then resume B.
-- Expected in r4: both accept, SQLSTATE=00000; no deadlock.
BEGIN ISOLATION LEVEL READ COMMITTED;
SET LOCAL search_path=public,pg_temp;
SET LOCAL app.user_id='00000000-0000-4000-8000-000000002db1';
SET LOCAL ROLE tally_app;
INSERT INTO public.disputes(id,tenant_id,customer_id,reading_id,subject,received_on,channel) VALUES ('00000000-0000-4000-8000-000000002d32','00000000-0000-4000-8000-000000002da1','00000000-0000-4000-8000-000000002dc1','00000000-0000-4000-8000-000000002d71','meter_accuracy','2026-03-02','written');
INSERT INTO public.dispute_events(tenant_id,dispute_id,event_type,occurred_on) VALUES ('00000000-0000-4000-8000-000000002da1','00000000-0000-4000-8000-000000002d32','withdrawn','2026-03-03');
\prompt 'B1: resume A1; after A finishes, press Enter: ' proceed
DO $$ BEGIN
 SET CONSTRAINTS public.zz_dispute_reading_released IMMEDIATE;
 RAISE NOTICE 'FK upgrade B SQLSTATE=00000 release accepted';
EXCEPTION WHEN OTHERS THEN
 RAISE NOTICE 'FK upgrade B SQLSTATE=% message=%',SQLSTATE,SQLERRM;
END $$;
ROLLBACK;
