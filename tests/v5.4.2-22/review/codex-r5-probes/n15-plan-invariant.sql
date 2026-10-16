-- PREDICTED. Owner/superuser, fresh clone with frozen r5 strictly applied;
-- TEMP revoked from PUBLIC, tally_app, tally_core. Local DDL rolls back.
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL search_path=public,pg_temp;
SET LOCAL client_min_messages=notice;
DO $$
DECLARE fn text; setting_name text; refused boolean;
BEGIN
 PERFORM assert_periods_guard_invariants();
 FOREACH fn IN ARRAY ARRAY['public.enforce_write_off_recovery()','public.enforce_ledger_lineage_acyclic()'] LOOP
  FOREACH setting_name IN ARRAY ARRAY['enable_seqscan','enable_hashjoin','enable_mergejoin','search_path'] LOOP
   refused:=false;
   BEGIN
    EXECUTE format('ALTER FUNCTION %s RESET %I',fn,setting_name);
    PERFORM assert_periods_guard_invariants();
   EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE '% reset % SQLSTATE=% message=%',fn,setting_name,SQLSTATE,SQLERRM;
    IF SQLSTATE<>'0LP01' OR position('lost its plan settings' in SQLERRM)=0 THEN RAISE; END IF;
    refused:=true;
   END;
   IF NOT refused THEN RAISE EXCEPTION 'Invariant missed % %',fn,setting_name; END IF;
  END LOOP;
 END LOOP;
 PERFORM assert_periods_guard_invariants();
 RAISE NOTICE 'Both functions: each removed setting detected; subtransaction restored definitions';
END $$;
ROLLBACK;
