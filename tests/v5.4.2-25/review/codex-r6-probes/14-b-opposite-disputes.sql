-- NOT EXECUTED. Owner, fresh shared throwaway clone with frozen r6 applied. No role DDL.
-- Schedule: start A to its prompt; start B to its prompt; resume A (blocks); resume B.
-- Predicted: one caught 40P01; survivor completes. A commits shared fixtures only.
\set ON_ERROR_STOP on
BEGIN;
SELECT public.dispute_lock('00000000-0000-4000-8000-000000002d32','opposite-order probe');
\prompt 'First lock held; follow schedule, then press enter: ' proceed
DO $$ BEGIN
 PERFORM public.dispute_lock('00000000-0000-4000-8000-000000002d31','opposite-order probe');
 RAISE NOTICE 'opposite-order b SQLSTATE=00000 second lock acquired';
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'opposite-order b SQLSTATE=% message=%',SQLSTATE,SQLERRM;
END $$;
ROLLBACK;
