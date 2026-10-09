-- Static-review probe; predicted outcomes, NOT executed by Codex. Run as clone owner.
\set ON_ERROR_STOP on
BEGIN;
DO $$ BEGIN
 IF current_database() NOT LIKE 'codex%' THEN
  RAISE EXCEPTION 'Run only on an operator-created codex-prefixed clone of frozen r7';
 END IF;END $$;
SET LOCAL search_path = public, pg_temp;
SET LOCAL statement_timeout = '30s';
CREATE FUNCTION pg_temp.reg(k text, s jsonb, r text DEFAULT 'law') RETURNS void LANGUAGE sql AS $$
 INSERT INTO public.rule_term_schemas(terms_kind,terms_version,rule_role,json_schema,introduced_on,description,source_note)
 VALUES(k,1,r,s,DATE '2026-10-09','codex r7 probe','codex r7 probe')
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
CREATE FUNCTION pg_temp.check_result(label text, good boolean) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF good IS TRUE THEN RAISE NOTICE 'PASS %', label;
ELSE RAISE NOTICE 'DEFECT %', label; END IF; END $$;
-- Every command is rolled back in its own subtransaction, including successful DDL.
CREATE FUNCTION pg_temp.expect(label text, command text, expected_state text, phrase text DEFAULT '') RETURNS void LANGUAGE plpgsql AS $$
DECLARE actual_state text; message text;
BEGIN
 BEGIN
  EXECUTE command;
  RAISE EXCEPTION 'probe rollback' USING ERRCODE='P7777';
 EXCEPTION WHEN SQLSTATE 'P7777' THEN NULL;
 WHEN OTHERS THEN GET STACKED DIAGNOSTICS actual_state=RETURNED_SQLSTATE,message=MESSAGE_TEXT;
 END;
 IF actual_state IS NOT DISTINCT FROM expected_state AND
    (expected_state IS NULL OR position(phrase in message)>0) THEN
  RAISE NOTICE 'PASS %: % %',label,coalesce(actual_state,'success'),coalesce(message,'');
 ELSE RAISE NOTICE 'DEFECT %: expected % / %, observed % / %',label,expected_state,phrase,actual_state,message;
 END IF;
END $$;


-- The registry explicitly permits omission of note from delegated properties.
SELECT pg_temp.reg('codex_no_note',
 (SELECT json_schema #- '{oneOf,1,properties,note}' FROM public.rule_term_schemas
  WHERE terms_kind='codex_probe_law' AND terms_version=1));
ALTER TABLE public.codex_probe_rules ADD COLUMN cap numeric;
-- A shared extractor permits cap or note; only cap is reachable in this schema.
-- All schema-valid law documents give a numeric cap; delegated documents give NULL.
INSERT INTO public.rule_term_facets(terms_kind,terms_version,facet_name,facet_type,json_path,description)
 VALUES('codex_no_note',1,'cap','number','$.keyvalue() ? (@.key == "cap" || @.key == "note").value','Shared cap extractor');
SELECT pg_temp.check_result('delegated document with note is outside this registered schema',
 (SELECT cardinality(public.rule_terms_errors(json_schema,'{"governs":"delegated_to_utility","citation":"x","note":"x"}'))>0
 FROM public.rule_term_schemas WHERE terms_kind='codex_no_note' AND terms_version=1));
SELECT pg_temp.check_result('valid delegated document derives nullable cap',
 public.rule_terms_facets('codex_no_note',1,'{"governs":"delegated_to_utility","citation":"x"}')='{"cap":null}');
SELECT pg_temp.check_result('valid law document derives numeric cap',
 public.rule_terms_facets('codex_no_note',1,'{"governs":"law","citation":"x","cap":12}')='{"cap":12}');
-- Expected DEFECT on r7; r6 only tries the valid no-note delegated document.
SELECT pg_temp.expect('schema-compatible facets must register when note is forbidden', $q$
 SELECT public.rule_table_register('public.codex_probe_rules','law','codex_no_note','{customer_class}','{cap}')
$q$,NULL);
ROLLBACK;
