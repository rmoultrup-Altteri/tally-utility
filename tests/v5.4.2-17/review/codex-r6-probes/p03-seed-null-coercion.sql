-- A FAIL proves malformed applicability can match the all-applicability row, or an explicit JSON-null reseed loses identity.

\set ON_ERROR_STOP on
BEGIN;
DO $$ BEGIN
 IF current_database() NOT LIKE 'codex%' THEN
  RAISE EXCEPTION 'Run only on an operator-created codex-prefixed clone of frozen r6';
 END IF;END $$;
SET LOCAL search_path = public, pg_temp;
SET LOCAL statement_timeout = '30s';
CREATE FUNCTION pg_temp.reg(k text, s jsonb, r text DEFAULT 'law') RETURNS void LANGUAGE sql AS $$
 INSERT INTO public.rule_term_schemas(terms_kind,terms_version,rule_role,json_schema,introduced_on,description,source_note)
 VALUES(k,1,r,s,DATE '2026-10-09','codex r6 probe','codex r6 probe')
$$;
SELECT pg_temp.reg('codex_probe_law','{"$schema": "https://json-schema.org/draft/2020-12/schema", "oneOf": [{"type": "object", "additionalProperties": false, "properties": {"governs": {"type": "string", "const": "law"}, "citation": {"type": "string", "pattern": "[A-Za-z0-9]"}, "cap": {"type": "number", "minimum": 0}}, "required": ["governs", "citation", "cap"]}, {"type": "object", "additionalProperties": false, "properties": {"governs": {"type": "string", "const": "delegated_to_utility"}, "citation": {"type": "string", "pattern": "[A-Za-z0-9]"}, "note": {"type": "string", "pattern": "[A-Za-z0-9]"}}, "required": ["governs", "citation"]}]}'::jsonb);
INSERT INTO public.places(kind_code,state_code,place_code,name,effective_from,source_note)
 SELECT 'state','ZZ','ZZ','Zedland',DATE '1900-01-01','codex fixture'
 WHERE NOT EXISTS(SELECT 1 FROM public.places WHERE kind_code='state' AND place_code='ZZ');
CREATE TABLE public.codex_probe_rules (
 id uuid DEFAULT public.uuid_generate_v4() PRIMARY KEY,
 state_code text NOT NULL, service_type text NOT NULL, owner_types text[], system_kinds text[], commission_jurisdiction boolean,
 owner_span int4multirange NOT NULL DEFAULT '{[0,)}', system_span int4multirange NOT NULL DEFAULT '{[0,)}', jurisdiction_span int4range NOT NULL DEFAULT '[0,2)',
 customer_class text NOT NULL, effective_from date NOT NULL, effective_to date, source_note text NOT NULL,
 terms_kind text NOT NULL, terms_version integer NOT NULL, terms_source text NOT NULL, terms jsonb NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(), recorded_txid bigint, closed_at timestamptz, closed_by text);
SELECT public.rule_table_register('public.codex_probe_rules','law','codex_probe_law','{customer_class}','{}');
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
DECLARE s jsonb := '{"state_code": "ZZ", "service_type": "gas", "owner_types": null, "system_kinds": null, "commission_jurisdiction": null, "customer_class": "residential", "effective_from": "2000-01-01", "effective_to": null, "source_note": "codex seed", "terms_kind": "codex_probe_law", "terms_version": 1, "terms_source": "{\"governs\": \"delegated_to_utility\", \"citation\": \"ZZ 9\"}"}'::jsonb; k text; bad jsonb; first_id uuid; again_id uuid;
BEGIN
 first_id:=public.rule_row_seed('public.codex_probe_rules',s);
 again_id:=public.rule_row_seed('public.codex_probe_rules',s);
 IF first_id IS DISTINCT FROM again_id THEN RAISE EXCEPTION 'FAIL reseed identity'; END IF;
 FOREACH k IN ARRAY ARRAY['owner_types','system_kinds'] LOOP
  FOR bad IN SELECT value FROM jsonb_array_elements('["municipal",{},true,1,[null],[{}],[1]]') LOOP
   PERFORM pg_temp.expect(k||' rejects '||bad::text,format('SELECT public.rule_row_seed(%L,%L::jsonb)','public.codex_probe_rules',jsonb_set(s,ARRAY[k],bad)),'22023','null (every one) or an array of strings');
  END LOOP;
  PERFORM pg_temp.expect(k||' cannot be omitted',format('SELECT public.rule_row_seed(%L,%L::jsonb)','public.codex_probe_rules',s-k),'22023','whole envelope');
  PERFORM pg_temp.expect(k||' empty',format('SELECT public.rule_row_seed(%L,%L::jsonb)','public.codex_probe_rules',jsonb_set(s,ARRAY[k],'[]')),'23514','non-empty');
 END LOOP;
 FOR bad IN SELECT value FROM jsonb_array_elements('["", "null", "false", 0, {}, []]') LOOP
  PERFORM pg_temp.expect('jurisdiction rejects '||bad::text,format('SELECT public.rule_row_seed(%L,%L::jsonb)','public.codex_probe_rules',jsonb_set(s,'{commission_jurisdiction}',bad)),'22023','null or a boolean');
 END LOOP;
 RAISE NOTICE 'PASS explicit JSON null means every one and reseeds unchanged';
END $p$;

ROLLBACK;
