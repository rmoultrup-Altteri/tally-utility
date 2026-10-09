-- A FAIL or false denial column (or true TEMP/CREATE) proves the core privilege boundary/invariant is incomplete.

\set ON_ERROR_STOP on
BEGIN;
DO $$ BEGIN
 IF current_database() NOT LIKE 'codex%' THEN
  RAISE EXCEPTION 'Run only on an operator-created codex-prefixed clone of frozen r6';
 END IF;END $$;
SET LOCAL search_path = public, pg_temp;
SET LOCAL statement_timeout = '30s';
CREATE FUNCTION pg_temp.expect(label text, command text, state text, phrase text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE actual_state text; message text;
BEGIN
 BEGIN
  EXECUTE command;
 EXCEPTION WHEN OTHERS THEN
  GET STACKED DIAGNOSTICS actual_state = RETURNED_SQLSTATE, message = MESSAGE_TEXT;
 END;
 IF actual_state IS DISTINCT FROM state OR (state IS NOT NULL AND position(phrase in message)=0) THEN
  RAISE EXCEPTION 'FAIL %: expected % / %, got % / %',label,state,phrase,actual_state,message;
 END IF;
 RAISE NOTICE 'PASS % (state %, message %)',label,coalesce(actual_state,'success'),coalesce(message,'none');
END $$;
SELECT public.assert_core_role_invariants();
CREATE MATERIALIZED VIEW public.codex_probe_mv AS SELECT 1 AS secret;
GRANT SELECT(secret) ON public.codex_probe_mv TO tally_core;
SELECT pg_temp.expect('column grant matview', 'SELECT public.assert_core_role_invariants()', '0LP01','reaches materialized views');
REVOKE SELECT(secret) ON public.codex_probe_mv FROM tally_core;
CREATE SCHEMA codex_probe_schema;
GRANT CREATE ON SCHEMA codex_probe_schema TO tally_core;
SELECT pg_temp.expect('nonpublic schema create', 'SELECT public.assert_core_role_invariants()', '0LP01','can define code');
REVOKE CREATE ON SCHEMA codex_probe_schema FROM tally_core;
SELECT public.assert_core_role_invariants();
SELECT 'migration functions inaccessible' AS check_name,
 NOT has_function_privilege('tally_core','public.rule_row_seed(regclass,jsonb)','EXECUTE') AS core_seed_denied,
 NOT has_function_privilege('tally_app','public.rule_row_seed(regclass,jsonb)','EXECUTE') AS app_seed_denied;
SET LOCAL ROLE tally_core;
SELECT current_user, has_database_privilege(current_user,current_database(),'TEMP') AS must_be_false,
 has_database_privilege(current_user,current_database(),'CREATE') AS must_also_be_false;
RESET ROLE;

ROLLBACK;
