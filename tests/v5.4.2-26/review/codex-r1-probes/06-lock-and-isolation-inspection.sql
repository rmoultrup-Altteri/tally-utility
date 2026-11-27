-- SOURCE ONLY, NOT EXECUTED. Owner; fresh clone with frozen r1 applied.
-- This is a catalog/isolation probe, NOT a claim that a concurrent race was run.
-- Predicted dangerous schedule to reproduce in the author's race harness:
--   committed fixture: open disconnect order O, eligible execute decision D.
--   A: BEGIN ISOLATION LEVEL REPEATABLE READ; SELECT * FROM service_orders WHERE id=O;
--   B: BEGIN READ COMMITTED; insert matched/photo executed visit for O under D; COMMIT;
--   A: UPDATE service_orders SET status='cancelled',cancellation_reason='probe' WHERE id=O;
--      read status and visits; ROLLBACK.
-- Prediction: A sees no visit in its old snapshot. B only locked O FOR SHARE;
-- it did not change O's tuple, so A has no row-version serialization conflict.
-- Repeat with A SERIALIZABLE and B READ COMMITTED; mixing isolation is not a cure.
-- A real run needs committed shared fixtures; this file deliberately keeps every
-- write rolled back and gives source/catal​og evidence, not a fabricated race result.
\set ON_ERROR_STOP on
BEGIN ISOLATION LEVEL REPEATABLE READ;
DO $$ BEGIN
 BEGIN
 PERFORM public.collections_subject_lock(NULL,'disconnect_execute',NULL,NULL,NULL,NULL,'isolation probe');
 RAISE NOTICE 'subject lock accepted SQLSTATE=00000';
 EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'subject lock SQLSTATE=% MESSAGE=%',SQLSTATE,SQLERRM; END;
END $$;
SELECT p.oid::regprocedure,p.provolatile,p.prosecdef,p.prosrc FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname IN ('enforce_disconnect_order','enforce_field_visit','enforce_collections_decision','recompute_do_not_disconnect');
SELECT c.relname,t.tgname,t.tgenabled,pg_get_triggerdef(t.oid) FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid
 WHERE NOT t.tgisinternal AND c.oid IN ('public.service_orders'::regclass,'public.meter_deployments'::regclass,'public.customer_program_enrollments'::regclass) ORDER BY 1,2;
ROLLBACK;
