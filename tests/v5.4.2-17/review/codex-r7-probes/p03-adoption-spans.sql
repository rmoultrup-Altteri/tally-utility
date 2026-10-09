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
ALTER TABLE public.codex_probe_rules ALTER COLUMN terms DROP NOT NULL;
ALTER TABLE public.codex_probe_rules ALTER COLUMN terms_source DROP NOT NULL;
ALTER TABLE public.codex_probe_rules ALTER COLUMN terms_kind DROP NOT NULL;
ALTER TABLE public.codex_probe_rules ALTER COLUMN terms_version DROP NOT NULL;
CREATE FUNCTION public.codex_adopt_check(jsonb) RETURNS void LANGUAGE plpgsql AS $$ BEGIN RETURN; END $$;

INSERT INTO public.codex_probe_rules(state_code,service_type,customer_class,effective_from,source_note)
 VALUES('ZZ','gas','legacy',DATE '2000-01-01','legacy');

SELECT pg_temp.expect('only system_span differs', $q$
 UPDATE public.codex_probe_rules SET system_kinds=ARRAY['distribution'];
SELECT public.rule_table_register('public.codex_probe_rules','law','codex_probe_law','{customer_class}','{}',p_adoption_check=>'public.codex_adopt_check(jsonb)');$q$,'42P16','stored spans');
SELECT pg_temp.expect('only jurisdiction_span differs', $q$
 UPDATE public.codex_probe_rules SET commission_jurisdiction=true;
SELECT public.rule_table_register('public.codex_probe_rules','law','codex_probe_law','{customer_class}','{}',p_adoption_check=>'public.codex_adopt_check(jsonb)');$q$,'42P16','stored spans');
SELECT pg_temp.expect('only owner_span differs', $q$
 UPDATE public.codex_probe_rules SET owner_types=ARRAY['municipal'];
SELECT public.rule_table_register('public.codex_probe_rules','law','codex_probe_law','{customer_class}','{}',p_adoption_check=>'public.codex_adopt_check(jsonb)');$q$,'42P16','stored spans');
SELECT pg_temp.expect('punctuation-only legacy key refused', $q$
 UPDATE public.codex_probe_rules SET customer_class='--';
SELECT public.rule_table_register('public.codex_probe_rules','law','codex_probe_law','{customer_class}','{}',p_adoption_check=>'public.codex_adopt_check(jsonb)');$q$,'42P16','a blank key');
-- Ranges are canonical and range_agg compares sets, not array ordering.
UPDATE public.codex_probe_rules SET owner_types=ARRAY['municipal','investor_owned'],
 owner_span=public.rule_applicability_span('owner_type',ARRAY['investor_owned','municipal']),
 system_kinds=ARRAY['distribution'],
 system_span=public.rule_applicability_span('system_kind',ARRAY['distribution']),
 commission_jurisdiction=false,jurisdiction_span='( -1,0]'::int4range;
SELECT public.rule_table_register('public.codex_probe_rules','law','codex_probe_law','{customer_class}','{}',p_adoption_check=>'public.codex_adopt_check(jsonb)');
UPDATE public.codex_probe_rules SET terms_kind='codex_probe_law',terms_version=1,
 terms_source='{"governs":"delegated_to_utility","citation":"ZZ 9"}';
SELECT pg_temp.check_result('reordered sets and alternate range representation register and adopt',
 (SELECT terms IS NOT NULL FROM public.codex_probe_rules));

ROLLBACK;
