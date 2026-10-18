-- PREDICTED; owner sessions on a fresh clone with frozen r1 applied.
-- First run 05-race-fixtures.sql as owner, once on this fresh clone.
\set ON_ERROR_STOP on
-- Use a separate fresh clone. Start A first, then run 09 while this pauses.
SET application_name='codex_r1_rr_status_A';
BEGIN ISOLATION LEVEL REPEATABLE READ;
SELECT status FROM public.payments WHERE id='00000000-0000-4000-8000-00000000cd01';
\prompt 'Run 09 in B to completion (it commits a draw), then press Enter: ' go
DO $$ BEGIN
UPDATE public.payments SET status='nsf',nsf_date=DATE '2026-03-06',status_cause_id='00000000-0000-4000-8000-00000000cd03' WHERE id='00000000-0000-4000-8000-00000000cd01';
RAISE NOTICE 'B2 RR terminal status after concurrent application: SQLSTATE=00000 accepted';
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'B2 RR terminal status after concurrent application: SQLSTATE=% message=%',SQLSTATE,SQLERRM; END $$;
-- Expected safe result: 25000, 40001, or refusal for money still applied.
-- Predicted bug: SQLSTATE=00000. Its snapshot hides B's committed application.
SELECT status FROM public.payments WHERE id='00000000-0000-4000-8000-00000000cd01';
ROLLBACK;
