-- Static-review probe; predicted outcomes, NOT executed by Codex. Run as clone owner.
\set ON_ERROR_STOP on
BEGIN;
DO $$ BEGIN
 IF current_database() NOT LIKE 'codex%' THEN
  RAISE EXCEPTION 'Run only on an operator-created codex-prefixed clone of frozen r8';
 END IF;END $$;
SET LOCAL search_path = public, pg_temp;
SET LOCAL statement_timeout = '30s';
CREATE FUNCTION pg_temp.reg(k text, s jsonb, r text DEFAULT 'law') RETURNS void LANGUAGE sql AS $$
 INSERT INTO public.rule_term_schemas(terms_kind,terms_version,rule_role,json_schema,introduced_on,description,source_note)
 VALUES(k,1,r,s,DATE '2026-10-09','codex r8 probe','codex r8 probe')
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
CREATE FUNCTION pg_temp.register_legacy() RETURNS void LANGUAGE sql AS $$
 SELECT public.rule_table_register('public.codex_probe_rules','law','codex_probe_law','{customer_class}','{}',
 p_adoption_check=>'public.codex_adopt_check(jsonb)') $$;

SELECT pg_temp.expect('empty adopting table registers', 'SELECT pg_temp.register_legacy()', NULL);
INSERT INTO public.codex_probe_rules(id,state_code,service_type,customer_class,effective_from,source_note)
 SELECT ('c0de0000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,'ZZ','gas','class'||i,DATE '2000-01-01','legacy'
 FROM generate_series(1,100) i;
SELECT pg_temp.expect('100 valid legacy rows register', 'SELECT pg_temp.register_legacy()', NULL);
SELECT pg_temp.expect('invalid row after 99 valid rows is checked', $q$
 UPDATE public.codex_probe_rules SET state_code='QQ' WHERE customer_class='class100';
 SELECT pg_temp.register_legacy()$q$, '42P16', 'is not a known state');
SELECT pg_temp.expect('missing area key reports column error, not undefined column in loop', $q$
 ALTER TABLE public.codex_probe_rules DROP COLUMN customer_class;
 SELECT pg_temp.register_legacy()$q$, '42P16', 'customer_class');
SELECT pg_temp.expect('non-text key uses combined template error (R26 is stale)', $q$
 ALTER TABLE public.codex_probe_rules ALTER COLUMN customer_class TYPE integer USING 1;
 SELECT pg_temp.register_legacy()$q$, '42P16', 'legacy row');
SELECT pg_temp.expect('bad owner code is caught and aggregated', $q$
 UPDATE public.codex_probe_rules SET owner_types=ARRAY['codex_unknown'] WHERE customer_class='class1';
 SELECT pg_temp.register_legacy()$q$, '42P16', 'not a known code with an ordinal');
SELECT pg_temp.expect('repeated owners now use combined error (R26 is stale)', $q$
 UPDATE public.codex_probe_rules SET owner_types=ARRAY['municipal','municipal'] WHERE customer_class='class1';
 SELECT pg_temp.register_legacy()$q$, '42P16', 'legacy row');
SELECT pg_temp.expect('valid key, invalid scope', $q$
 UPDATE public.codex_probe_rules SET service_type='water',system_kinds=ARRAY['master_meter'],
 system_span=public.rule_applicability_span('system_kind',ARRAY['master_meter']) WHERE customer_class='class1';
 SELECT pg_temp.register_legacy()$q$, '42P16', 'is not a kind of water system');
SELECT pg_temp.expect('one row with two defects reports its first refusal', $q$
 UPDATE public.codex_probe_rules SET customer_class='---',state_code='QQ' WHERE customer_class='class1';
 SELECT pg_temp.register_legacy()$q$, '42P16', 'non-blank');
SELECT pg_temp.expect('four bad rows counted, including a row with two defects', $q$
 UPDATE public.codex_probe_rules SET state_code='QQ' WHERE customer_class IN ('class1','class2','class3','class4');
 UPDATE public.codex_probe_rules SET customer_class='---' WHERE customer_class='class1';
 SELECT pg_temp.register_legacy()$q$, '42P16', '4 legacy rows in all cannot be adopted');
ROLLBACK;
