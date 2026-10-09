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

CREATE TABLE public.codex_citations(rule_id uuid, needs_on date);
CREATE FUNCTION public.codex_floor(p_id uuid) RETURNS date LANGUAGE sql STABLE AS
 $$SELECT max(needs_on) FROM public.codex_citations WHERE rule_id=p_id$$;
INSERT INTO public.codex_probe_rules(id,state_code,service_type,customer_class,effective_from,source_note)
 VALUES('c0de0000-0000-4000-8000-000000000099','ZZ','gas','legacy',DATE '2000-01-01','legacy');
SELECT public.rule_table_register('public.codex_probe_rules','law','codex_probe_law','{customer_class}','{}',
 p_close_floor=>'public.codex_floor(uuid)',p_adoption_check=>'public.codex_adopt_check(jsonb)');
INSERT INTO public.tenants(id,name,slug) VALUES('c0de0000-0000-4000-8000-000000000001','Codex A','codex-r7-a');
INSERT INTO public.users(id,tenant_id,display_name,email,role) VALUES
 ('c0de0000-0000-4000-8000-000000000011','c0de0000-0000-4000-8000-000000000001','Codex A','a@codex-r7.test','operator');
SET LOCAL app.user_id='c0de0000-0000-4000-8000-000000000011';
INSERT INTO public.utility_service_profiles(tenant_id,service_type,system_kind,state_code,owner_type,commission_jurisdiction,effective_from,evidence_reference,evidence_date)
 VALUES('c0de0000-0000-4000-8000-000000000001','gas','distribution','ZZ','investor_owned',true,'2000-01-01','probe','2000-01-01');
SELECT pg_temp.expect('unfilled direct citation refused',
 $q$SELECT public.rule_row_cite('public.codex_probe_rules','c0de0000-0000-4000-8000-000000000099','2020-01-01')$q$,'23514','not yet adopted');
SELECT pg_temp.expect('unfilled law lookup refused',
 $q$SELECT public.rule_law_row_as_of('public.codex_probe_rules','c0de0000-0000-4000-8000-000000000001','gas','distribution','ZZ','{"customer_class":"legacy"}','2020-01-01')$q$,'23514','not yet adopted');
SELECT pg_temp.expect('law citation wrapper also refuses',
 $q$SELECT public.rule_law_row_cite('public.codex_probe_rules','c0de0000-0000-4000-8000-000000000099','c0de0000-0000-4000-8000-000000000001','gas','distribution','ZZ','{"customer_class":"legacy"}','2020-01-01')$q$,'23514','not yet adopted');
SELECT pg_temp.expect('tariff lookup refuses a law table before reading it',
 $q$SELECT public.rule_tariff_row_as_of('public.codex_probe_rules','c0de0000-0000-4000-8000-000000000001','gas','distribution','ZZ','{"customer_class":"legacy"}','2020-01-01')$q$,'22023','not a tariff table');
SELECT pg_temp.expect('seeding does not silently accept or fill an unfilled row', $q$
 SELECT public.rule_row_seed('public.codex_probe_rules','{"state_code":"ZZ","service_type":"gas","owner_types":null,"system_kinds":null,"commission_jurisdiction":null,"customer_class":"legacy","effective_from":"2000-01-01","effective_to":null,"source_note":"legacy","terms_kind":"codex_probe_law","terms_version":1,"terms_source":"{\"governs\":\"delegated_to_utility\",\"citation\":\"ZZ 9\"}"}')
 $q$,'23505','terms');
INSERT INTO public.codex_citations VALUES('c0de0000-0000-4000-8000-000000000099','2020-01-01');
SELECT pg_temp.expect('legacy close still enforces old citation floor',
 $q$UPDATE public.codex_probe_rules SET effective_to='2020-01-01'$q$,'23514','a citing record needs');
SELECT pg_temp.expect('legacy close above floor remains allowed',
 $q$UPDATE public.codex_probe_rules SET effective_to='2020-01-02'$q$,NULL);
CREATE TABLE public.codex_subject(id uuid PRIMARY KEY,tenant_id uuid NOT NULL);
INSERT INTO public.codex_subject VALUES('c0de0000-0000-4000-8000-000000000021','c0de0000-0000-4000-8000-000000000001');
GRANT SELECT ON public.codex_subject TO tally_core;
-- Expected DEFECT under a blanket policy that all semantic rule references require adoption.
SELECT pg_temp.expect('audit rule reference should refuse unfilled law', $q$
 SET LOCAL ROLE tally_core;
 INSERT INTO public.rule_audit_findings(tenant_id,finding_kind,subject_table,subject_id,rule_table,rule_row_id,core_release,coverage_from,coverage_to,detail)
 VALUES('c0de0000-0000-4000-8000-000000000001','record_disagrees_with_rule','public.codex_subject','c0de0000-0000-4000-8000-000000000021',
 'public.codex_probe_rules','c0de0000-0000-4000-8000-000000000099','codex r7','2020-01-01','2020-01-02','{}');
 RESET ROLE;$q$,'23514','not yet adopted');

ROLLBACK;
