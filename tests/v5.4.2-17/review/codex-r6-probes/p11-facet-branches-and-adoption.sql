-- A schema-valid law document refused by the facet below demonstrates that delegated dry-run does not prove all branches storable; accepting an adopting table with an unstorable delegated facet proves a guard bypass.
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
 VALUES('codex_probe_law',1,'cap','text','$.cap','intentional schema/facet mismatch');
SELECT public.rule_table_register('public.codex_probe_rules','law','codex_probe_law','{customer_class}','{cap}');
INSERT INTO public.codex_probe_rules(state_code,service_type,customer_class,effective_from,source_note,terms_kind,terms_version,terms_source)
 VALUES('ZZ','gas','delegated',DATE '2000-01-01','control','codex_probe_law',1,'{"governs":"delegated_to_utility","citation":"ZZ 9"}');
SELECT public.rule_terms_errors(json_schema,'{"governs":"law","citation":"ZZ 1","cap":5}') AS should_be_empty
 FROM public.rule_term_schemas WHERE terms_kind='codex_probe_law';
SELECT pg_temp.expect('valid other branch hits incompatible facet',
 $q$INSERT INTO public.codex_probe_rules(state_code,service_type,customer_class,effective_from,source_note,terms_kind,terms_version,terms_source)
 VALUES('ZZ','gas','law',DATE '2000-01-01','other branch','codex_probe_law',1,'{"governs":"law","citation":"ZZ 1","cap":5}')$q$,'22000','not a text');
CREATE TABLE public.codex_adopting (LIKE public.codex_probe_rules INCLUDING DEFAULTS);
ALTER TABLE public.codex_adopting ADD PRIMARY KEY(id);
ALTER TABLE public.codex_adopting ALTER COLUMN cap SET NOT NULL;
ALTER TABLE public.codex_adopting ALTER COLUMN terms DROP NOT NULL;
ALTER TABLE public.codex_adopting ALTER COLUMN terms_source DROP NOT NULL;
ALTER TABLE public.codex_adopting ALTER COLUMN terms_kind DROP NOT NULL;
ALTER TABLE public.codex_adopting ALTER COLUMN terms_version DROP NOT NULL;
CREATE FUNCTION public.codex_adopt_check(jsonb) RETURNS void LANGUAGE plpgsql AS $$ BEGIN RETURN; END $$;
INSERT INTO public.codex_adopting(state_code,service_type,customer_class,effective_from,source_note,cap)
 VALUES('ZZ','gas','legacy',DATE '2000-01-01','legacy','old');
SELECT pg_temp.expect('adopting registration dry-runs delegated facets',
 $q$SELECT public.rule_table_register('public.codex_adopting','law','codex_probe_law','{customer_class}','{cap}',p_adoption_check=>'public.codex_adopt_check(jsonb)')$q$,'42P16','standard delegated document');
ROLLBACK;
