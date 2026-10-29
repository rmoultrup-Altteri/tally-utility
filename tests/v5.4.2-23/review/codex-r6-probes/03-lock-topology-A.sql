-- AUTHOR RUN ONLY: owner, same fresh clone with frozen r6 applied.
-- S1 LOCK-TOPOLOGY probe, not a full trigger/fixture race. No money rows.
-- Models the exact advisory-key sequence in the two source paths.
-- Run A, then B in a second owner session within 5 seconds. Both roll back.
-- Root K UUID sorts AFTER child K2. The missing payment lock allows overlap.
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL search_path=public,pg_temp;
SET LOCAL client_min_messages=notice;
SET LOCAL lock_timeout='15s';
DO $$ BEGIN
 -- reissue void: source credit, then itself (patch 2354, 2363).
 PERFORM pg_advisory_xact_lock(public.cash_source_lock_key('credit','00000000-0000-4000-8000-000000009902'));
 RAISE NOTICE 'S1 A holds K; start B now';
 PERFORM pg_sleep(5);
 PERFORM pg_advisory_xact_lock(public.cash_source_lock_key('credit','00000000-0000-4000-8000-000000009901'));
 RAISE NOTICE 'S1 A completed SQLSTATE=00000';
EXCEPTION WHEN OTHERS THEN
 RAISE NOTICE 'S1 A CAUGHT SQLSTATE=% MESSAGE=%',SQLSTATE,SQLERRM;
END $$;
ROLLBACK;
