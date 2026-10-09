-- A FAIL proves a versionless strategy under a reference, array or other discriminator survives, or a valid version reference fails.

\set ON_ERROR_STOP on
BEGIN;
DO $$ BEGIN
 IF current_database() NOT LIKE 'codex%' THEN
  RAISE EXCEPTION 'Run only on an operator-created codex-prefixed clone of frozen r6';
 END IF;END $$;
SET LOCAL search_path = public, pg_temp;
SET LOCAL statement_timeout = '30s';
DO $p$
DECLARE s jsonb; errors text[];
BEGIN
 s := '{"$schema": "https://json-schema.org/draft/2020-12/schema", "type": "object", "additionalProperties": false, "properties": {"fee": {"type": "object", "additionalProperties": false, "properties": {"strategy": {"type": "string", "const": "flat"}}, "required": ["strategy"]}}, "required": ["fee"]}'::jsonb; errors:=public.rule_terms_schema_errors(s);
 IF NOT EXISTS(SELECT 1 FROM unnest(errors) e WHERE e LIKE '%must require%version%') THEN RAISE EXCEPTION 'FAIL versionless form 0: %',errors; END IF;
 RAISE NOTICE 'PASS versionless form 0: %',errors;
 s := '{"$schema": "https://json-schema.org/draft/2020-12/schema", "type": "object", "additionalProperties": false, "properties": {"fee": {"$ref": "#/$defs/fee"}}, "required": ["fee"], "$defs": {"fee": {"type": "object", "additionalProperties": false, "properties": {"strategy": {"type": "string", "const": "flat"}}, "required": ["strategy"]}}}'::jsonb; errors:=public.rule_terms_schema_errors(s);
 IF NOT EXISTS(SELECT 1 FROM unnest(errors) e WHERE e LIKE '%must require%version%') THEN RAISE EXCEPTION 'FAIL versionless form 1: %',errors; END IF;
 RAISE NOTICE 'PASS versionless form 1: %',errors;
 s := '{"$schema": "https://json-schema.org/draft/2020-12/schema", "type": "object", "additionalProperties": false, "properties": {"fees": {"type": "array", "items": {"type": "object", "additionalProperties": false, "properties": {"strategy": {"type": "string", "const": "flat"}}, "required": ["strategy"]}}}, "required": ["fees"]}'::jsonb; errors:=public.rule_terms_schema_errors(s);
 IF NOT EXISTS(SELECT 1 FROM unnest(errors) e WHERE e LIKE '%must require%version%') THEN RAISE EXCEPTION 'FAIL versionless form 2: %',errors; END IF;
 RAISE NOTICE 'PASS versionless form 2: %',errors;
 s := '{"$schema": "https://json-schema.org/draft/2020-12/schema", "type": "object", "additionalProperties": false, "properties": {"fee": {"oneOf": [{"type": "object", "additionalProperties": false, "properties": {"mode": {"type": "string", "const": "a"}, "strategy": {"type": "string"}}, "required": ["mode", "strategy"]}, {"type": "object", "additionalProperties": false, "properties": {"mode": {"type": "string", "const": "b"}, "strategy": {"type": "string"}}, "required": ["mode", "strategy"]}]}}, "required": ["fee"]}'::jsonb; errors:=public.rule_terms_schema_errors(s);
 IF NOT EXISTS(SELECT 1 FROM unnest(errors) e WHERE e LIKE '%must require%version%') THEN RAISE EXCEPTION 'FAIL versionless form 3: %',errors; END IF;
 RAISE NOTICE 'PASS versionless form 3: %',errors;
 s:='{"$schema": "https://json-schema.org/draft/2020-12/schema", "type": "object", "additionalProperties": false, "properties": {"fees": {"type": "array", "items": {"$ref": "#/$defs/fee"}}}, "required": ["fees"], "$defs": {"fee": {"type": "object", "additionalProperties": false, "properties": {"strategy": {"$ref": "#/$defs/code"}, "version": {"$ref": "#/$defs/version"}}, "required": ["strategy", "version"]}, "code": {"type": "string", "const": "flat"}, "version": {"type": "integer", "minimum": 1, "maximum": 2}}}'::jsonb; errors:=public.rule_terms_schema_errors(s); IF cardinality(errors)<>0 THEN RAISE EXCEPTION 'FAIL valid reference form: %',errors; END IF;
 IF cardinality(public.rule_terms_errors(s,'{"fees":[{"strategy":"flat","version":2}]}'))<>0 THEN RAISE EXCEPTION 'FAIL valid reference document'; END IF;
 RAISE NOTICE 'PASS versioned references';
END $p$;

ROLLBACK;
