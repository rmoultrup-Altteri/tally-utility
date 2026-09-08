-- Session B: REPEATABLE READ, snapshot fixed BEFORE A's write. Waits long enough for A to run and
-- commit entirely, THEN attempts to UPDATE the SAME target row A's validator mutex-touched.
-- Question: does Postgres's own MVCC write-write conflict detection (since A's mutex is a REAL
-- UPDATE on this row) fire natively, or does the trigger's manual EXISTS+isolation check run first
-- and produce its own (different) error?
\echo SESSION_B: starting, fixing RR snapshot now
SET LOCAL app.user_id = '10000000-0000-4000-8000-00000000ab01';
SET ROLE tally_app;
BEGIN ISOLATION LEVEL REPEATABLE READ;
SET LOCAL app.user_id = '10000000-0000-4000-8000-00000000ab01';
SET ROLE tally_app;
-- fix the snapshot with a throwaway read
SELECT count(*) FROM public.correction_run_targets WHERE id = '10000000-0000-4000-8000-00000000d701';
\echo SESSION_B: snapshot fixed, sleeping 3s to let A start and finish
SELECT pg_sleep(3);
\echo SESSION_B: attempting UPDATE now (A should have committed by ~t=6s from its own start; this update will block on the row lock A still holds if A hasn't committed yet, or hit A's committed write if it has)
DO $$
BEGIN
  UPDATE public.correction_run_targets SET rate_date_mode = 'current' WHERE id = '10000000-0000-4000-8000-00000000d701';
  RAISE NOTICE 'SESSION_B: update SUCCEEDED (unexpected)';
EXCEPTION
  WHEN invalid_transaction_state THEN
    RAISE NOTICE 'SESSION_B RESULT: trigger''s manual isolation-pin fired (SQLSTATE %): %', SQLSTATE, SQLERRM;
  WHEN serialization_failure THEN
    RAISE NOTICE 'SESSION_B RESULT: POSTGRES NATIVE serialization_failure fired (SQLSTATE %) BEFORE/INSTEAD of the trigger''s manual pin: %', SQLSTATE, SQLERRM;
  WHEN restrict_violation THEN
    RAISE NOTICE 'SESSION_B RESULT: trigger''s EXISTS-based freeze fired (SQLSTATE %): %', SQLSTATE, SQLERRM;
END $$;
ROLLBACK;
\echo SESSION_B: done
