-- Session B: while A is mid-flight holding FOR SHARE on the target row, try to change
-- rate_date_mode on the SAME target under READ COMMITTED. Should block behind A, then
-- (once A commits) see A's snapshot and be refused -- no deadlock either way.
\echo SESSION_B: starting, will attempt UPDATE now (should block behind A)
SET LOCAL app.user_id = '10000000-0000-4000-8000-00000000ab01';
SET ROLE tally_app;
BEGIN;
SET LOCAL app.user_id = '10000000-0000-4000-8000-00000000ab01';
SET ROLE tally_app;
\timing on
DO $$
BEGIN
  UPDATE public.correction_run_targets SET rate_date_mode = 'current' WHERE id = '10000000-0000-4000-8000-00000000d401';
  RAISE NOTICE 'SESSION_B: update unexpectedly SUCCEEDED (no snapshot block?)';
EXCEPTION WHEN restrict_violation THEN
  RAISE NOTICE 'SESSION_B RESULT: update correctly refused after waiting behind A''s snapshot: %', SQLERRM;
END $$;
ROLLBACK;
\echo SESSION_B: done
