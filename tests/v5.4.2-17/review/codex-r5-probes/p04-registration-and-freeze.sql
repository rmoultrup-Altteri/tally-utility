-- A FAIL proves facet storage mismatch, prefilled adoption, or schema-text hash drift remains possible.

\set ON_ERROR_STOP on
BEGIN;
DO $$ BEGIN
 IF current_database() NOT LIKE 'codex%' THEN
  RAISE EXCEPTION 'Run only on an operator-created codex-prefixed clone of frozen r5';
 END IF;END $$;
SET LOCAL search_path = public, pg_temp;
SET LOCAL statement_timeout = '30s';
CREATE FUNCTION pg_temp.reg(k text, s jsonb, r text DEFAULT 'law') RETURNS void LANGUAGE sql AS $$
 INSERT INTO public.rule_term_schemas(terms_kind,terms_version,rule_role,json_schema,introduced_on,description,source_note)
 VALUES(k,1,r,s,DATE '2026-10-09','codex r5 probe','codex r5 probe')
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
ALTER TABLE public.codex_probe_rules ADD COLUMN cap text;
INSERT INTO public.rule_term_facets(terms_kind,terms_version,facet_name,facet_type,json_path,description)
 VALUES('codex_probe_law',1,'cap','number','$.cap','cap');
SELECT pg_temp.expect('number facet in text column',
 $q$SELECT public.rule_table_register('public.codex_probe_rules','law','codex_probe_law','{customer_class}','{cap}')$q$,'42P16','cap');
ALTER TABLE public.codex_probe_rules ALTER COLUMN cap TYPE numeric USING cap::numeric;
ALTER TABLE public.codex_probe_rules ALTER COLUMN terms DROP NOT NULL;
ALTER TABLE public.codex_probe_rules ALTER COLUMN terms_source DROP NOT NULL;
ALTER TABLE public.codex_probe_rules ALTER COLUMN terms_kind DROP NOT NULL;
ALTER TABLE public.codex_probe_rules ALTER COLUMN terms_version DROP NOT NULL;
CREATE FUNCTION public.codex_adopt_check(jsonb) RETURNS void LANGUAGE plpgsql AS $$ BEGIN RETURN; END $$;
INSERT INTO public.codex_probe_rules(state_code,service_type,customer_class,effective_from,source_note,terms_kind,terms_version,terms_source,terms)
 VALUES('ZZ','gas','residential',DATE '2000-01-01','codex','codex_probe_law',1,'{}','{}');
SELECT pg_temp.expect('prefilled adopting table',
 $q$SELECT public.rule_table_register('public.codex_probe_rules','law','codex_probe_law','{customer_class}','{cap}',p_adoption_check=>'public.codex_adopt_check(jsonb)')$q$,'42P16','already filled');
SELECT pg_temp.expect('freeze numeric scale rewrite',
 $q$UPDATE public.rule_term_schemas SET accepts_new_rows=false,json_schema=jsonb_set(json_schema,'{oneOf,0,properties,cap,minimum}','0.0') WHERE terms_kind='codex_probe_law'$q$,'23001','one change is a freeze');
UPDATE public.rule_term_schemas SET accepts_new_rows=false WHERE terms_kind='codex_probe_law';
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM public.rule_term_schemas WHERE terms_kind='codex_probe_law'
 AND schema_hash <> 'sha256:'||encode(sha256(convert_to(json_schema::text,'UTF8')),'hex')) THEN RAISE EXCEPTION 'FAIL freeze hash'; END IF;
 RAISE NOTICE 'PASS ordinary freeze preserves hash';
END $$;

ROLLBACK;
