-- PREDICTED; owner sessions on a fresh clone with frozen r1 applied.
-- First run 05-race-fixtures.sql as owner, once on this fresh clone.
\set ON_ERROR_STOP on
-- Start A first. While it pauses, start 07 in session B.
SET application_name='codex_r1_status_A';
BEGIN;
DO $$ BEGIN
UPDATE public.payments SET status='nsf',nsf_date=DATE '2026-03-06',status_cause_id='00000000-0000-4000-8000-00000000cd03' WHERE id='00000000-0000-4000-8000-00000000cd01';
RAISE NOTICE 'B2 RC status: SQLSTATE=00000 accepted';
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'B2 RC status: SQLSTATE=% message=%',SQLSTATE,SQLERRM; END $$;
\prompt 'Start B; confirm B is waiting on this source lock, then press Enter to commit A: ' go
-- Check pg_blocking_pids(B) from a third owner connection if needed.
COMMIT;
BEGIN;
ROLLBACK;
