-- AUTHOR RUN ONLY: owner, fresh clone with frozen r10 strictly applied.
-- Clone TEMP revoked from PUBLIC, tally_app and tally_core beforehand.
-- Transactional function ACL/name perturbations only; no role DDL.
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL search_path=public,pg_temp;
SET LOCAL statement_timeout='60s';
SET LOCAL client_min_messages=notice;
DO $$
DECLARE f text; change_sql text; n integer;
BEGIN
 PERFORM public.assert_cash_guard_invariants();
 FOR f IN SELECT unnest(ARRAY[
  'public.check_cash_order(text,uuid,timestamptz,uuid,text)',
  'public.check_cash_leaving_order(uuid,timestamptz,text)']) LOOP
  FOR n IN 1..4 LOOP
   change_sql := CASE n
    WHEN 1 THEN format('GRANT EXECUTE ON FUNCTION %s TO PUBLIC',f)
    WHEN 2 THEN format('GRANT EXECUTE ON FUNCTION %s TO tally_core',f)
    WHEN 3 THEN format('REVOKE EXECUTE ON FUNCTION %s FROM tally_app',f)
    WHEN 4 THEN format('ALTER FUNCTION %s RENAME TO codex_r10_hidden_check',f) END;
   BEGIN
    EXECUTE change_sql;
    PERFORM public.assert_cash_guard_invariants();
    RAISE EXCEPTION 'FAIL invariant admitted %',change_sql;
   EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE '% SQLSTATE=% MESSAGE=%',change_sql,SQLSTATE,SQLERRM;
    IF SQLSTATE <> '0LP01' OR strpos(SQLERRM,'a recorded-order check is missing')=0 THEN RAISE; END IF;
   END;
   PERFORM public.assert_cash_guard_invariants();
  END LOOP;
 END LOOP;
 RAISE NOTICE 'PASS both order checks: missing, PUBLIC/core grants, missing app grant; baseline restored';
END $$;
ROLLBACK;
