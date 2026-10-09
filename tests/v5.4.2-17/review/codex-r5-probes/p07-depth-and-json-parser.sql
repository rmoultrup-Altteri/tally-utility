-- A FAIL proves union depth disagreement or a duplicate/invalid Unicode parser escape; a valid surrogate pair must parse.

\set ON_ERROR_STOP on
BEGIN;
DO $$ BEGIN
 IF current_database() NOT LIKE 'codex%' THEN
  RAISE EXCEPTION 'Run only on an operator-created codex-prefixed clone of frozen r5';
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
DO $p$
DECLARE s jsonb := '{"$schema": "https://json-schema.org/draft/2020-12/schema", "type": "object", "additionalProperties": false, "properties": {"payload": {"$ref": "#/$defs/node"}}, "required": ["payload"], "$defs": {"node": {"oneOf": [{"type": "object", "additionalProperties": false, "properties": {"tag": {"type": "string", "const": "end"}}, "required": ["tag"]}, {"type": "object", "additionalProperties": false, "properties": {"tag": {"type": "string", "const": "more"}, "next": {"$ref": "#/$defs/node"}}, "required": ["tag", "next"]}]}}}'::jsonb; d jsonb; e text[]; i integer;
BEGIN
 IF cardinality(public.rule_terms_schema_errors(s))<>0 THEN RAISE EXCEPTION 'FAIL recursive schema'; END IF;
 d:='{"tag":"end"}';
 FOR i IN 1..62 LOOP d:=jsonb_build_object('tag','more','next',d); END LOOP;
 e:=public.rule_terms_errors(s,jsonb_build_object('payload',d));
 IF cardinality(e)<>0 THEN RAISE EXCEPTION 'FAIL depth 64 should pass: %',e; END IF;
 d:=jsonb_build_object('tag','more','next',d); e:=public.rule_terms_errors(s,jsonb_build_object('payload',d));
 IF NOT EXISTS(SELECT 1 FROM unnest(e) x WHERE x LIKE '%nested more than 64%') THEN RAISE EXCEPTION 'FAIL depth 65 should fail: %',e; END IF;
 RAISE NOTICE 'PASS union depth boundary';
END $p$;
SELECT pg_temp.expect('nested escaped duplicate', $q$SELECT public.rule_terms_parse('{"items":[{"a":1,"\u0061":2}]}')$q$,'22030','repeats a key');
SELECT pg_temp.expect('NUL refused before jsonb', $q$SELECT public.rule_terms_parse('{"x":"\u0000"}')$q$,'22P02','PostgreSQL can store');
SELECT pg_temp.expect('lone surrogate key refused', $q$SELECT public.rule_terms_parse('{"\ud800":"x"}')$q$,'22P02','PostgreSQL can store');
SELECT public.rule_terms_parse('{"x":"\ud83d\ude00"}') AS valid_astral_pair;

ROLLBACK;
