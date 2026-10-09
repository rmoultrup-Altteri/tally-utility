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

INSERT INTO public.codex_probe_rules(id,state_code,service_type,customer_class,effective_from,source_note)
 VALUES('c0de0000-0000-4000-8000-000000000099','ZZ','gas','legacy','2000-01-01','legacy');
SELECT pg_temp.register_legacy();
SELECT pg_temp.reg('codex_tariff','{"$schema":"https://json-schema.org/draft/2020-12/schema","type":"object","additionalProperties":false,"required":["citation"],"properties":{"citation":{"type":"string","pattern":"[A-Za-z0-9]"}}}', 'tariff');
CREATE TABLE public.codex_tariffs (
 id uuid DEFAULT public.uuid_generate_v4() PRIMARY KEY,
 tenant_id uuid NOT NULL, state_code text NOT NULL, service_type text NOT NULL, system_kind text NOT NULL,
 customer_class text NOT NULL, effective_from date NOT NULL, effective_to date, tariff_reference text NOT NULL,
 terms_kind text NOT NULL, terms_version integer NOT NULL, terms_source text NOT NULL, terms jsonb NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(), recorded_txid bigint, created_by uuid, closed_at timestamptz, closed_by uuid);
SELECT public.rule_table_register('public.codex_tariffs','tariff','codex_tariff','{customer_class}','{}');
CREATE FUNCTION pg_temp.tariff_insert(p_state text,p_service text,p_system text) RETURNS void LANGUAGE sql AS $$
 INSERT INTO public.codex_tariffs(id,tenant_id,state_code,service_type,system_kind,customer_class,effective_from,tariff_reference,terms_kind,terms_version,terms_source)
 VALUES('c0de0000-0000-4000-8000-000000000098','c0de0000-0000-4000-8000-000000000001',p_state,p_service,p_system,
 'residential','2000-01-01','tariff','codex_tariff',1,'{"citation":"x"}') $$;
INSERT INTO public.tenants(id,name,slug) VALUES('c0de0000-0000-4000-8000-000000000001','Codex A','codex-r8-a');
INSERT INTO public.users(id,tenant_id,display_name,email,role) VALUES
 ('c0de0000-0000-4000-8000-000000000011','c0de0000-0000-4000-8000-000000000001','Codex A','a@codex-r8.test','operator');
SET LOCAL app.user_id='c0de0000-0000-4000-8000-000000000011';
SELECT pg_temp.expect('tariff prepare still refuses unknown state',
 $q$SELECT pg_temp.tariff_insert('QQ','gas','distribution')$q$,'23503','is not a known state');
SELECT pg_temp.expect('tariff prepare still refuses water master meter',
 $q$SELECT pg_temp.tariff_insert('ZZ','water','master_meter')$q$,'23514','is not a kind of water system');
SELECT pg_temp.expect('tariff prepare still refuses missing system kind',
 $q$SELECT pg_temp.tariff_insert('ZZ','gas',NULL)$q$,'23514','is not a kind of gas system');
SELECT pg_temp.tariff_insert('ZZ','gas','distribution');
SELECT pg_temp.check_result('valid tariff preserved', (SELECT terms='{"citation":"x"}'::jsonb FROM public.codex_tariffs));
CREATE TABLE public.codex_subject(id uuid PRIMARY KEY,tenant_id uuid NOT NULL);
INSERT INTO public.codex_subject VALUES('c0de0000-0000-4000-8000-000000000021','c0de0000-0000-4000-8000-000000000001');
GRANT SELECT ON public.codex_subject TO tally_core;
CREATE FUNCTION pg_temp.finding(t text,r uuid) RETURNS void LANGUAGE sql AS $$
 INSERT INTO public.rule_audit_findings(tenant_id,finding_kind,subject_table,subject_id,rule_table,rule_row_id,core_release,coverage_from,coverage_to,detail)
 VALUES('c0de0000-0000-4000-8000-000000000001','record_disagrees_with_rule','public.codex_subject','c0de0000-0000-4000-8000-000000000021',
 t,r,'codex r8','2020-01-01','2020-01-02','{}') $$;
SELECT pg_temp.expect('core cannot cite unfilled legacy law', $q$
 SET LOCAL ROLE tally_core;
 SELECT pg_temp.finding('public.codex_probe_rules','c0de0000-0000-4000-8000-000000000099');
$q$,'23514','not yet adopted');
SELECT pg_temp.expect('core can cite a valid tariff', $q$
 SET LOCAL ROLE tally_core;
 SELECT pg_temp.finding('public.codex_tariffs','c0de0000-0000-4000-8000-000000000098');
$q$,NULL);
SELECT pg_temp.expect('finding without rule still allowed', $q$
 SET LOCAL ROLE tally_core; SELECT pg_temp.finding(NULL,NULL);
$q$,NULL);
-- Direct corruption is owner-only fault injection, not a reachable tariff write.
SELECT pg_temp.expect('same empty-document guard covers tariff rows under fault injection', $q$
 ALTER TABLE public.codex_tariffs DISABLE TRIGGER rule_row_history;
 ALTER TABLE public.codex_tariffs ALTER COLUMN terms DROP NOT NULL;
 UPDATE public.codex_tariffs SET terms=NULL;
 SET LOCAL ROLE tally_core;
 SELECT pg_temp.finding('public.codex_tariffs','c0de0000-0000-4000-8000-000000000098');
$q$,'23514','not yet adopted');
ROLLBACK;
