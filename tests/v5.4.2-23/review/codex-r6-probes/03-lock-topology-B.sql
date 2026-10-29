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
 -- give-back: payment, then the family in UUID order (patch 804-808).
 PERFORM pg_advisory_xact_lock(public.cash_source_lock_key('payment','00000000-0000-4000-8000-000000009900'));
 PERFORM pg_advisory_xact_lock(public.cash_source_lock_key('credit','00000000-0000-4000-8000-000000009901'));
 RAISE NOTICE 'S1 B holds payment and K2; now requests K';
 PERFORM pg_advisory_xact_lock(public.cash_source_lock_key('credit','00000000-0000-4000-8000-000000009902'));
 RAISE NOTICE 'S1 B completed SQLSTATE=00000';
EXCEPTION WHEN OTHERS THEN
 RAISE NOTICE 'S1 B CAUGHT SQLSTATE=% MESSAGE=%',SQLSTATE,SQLERRM;
END $$;
ROLLBACK;
