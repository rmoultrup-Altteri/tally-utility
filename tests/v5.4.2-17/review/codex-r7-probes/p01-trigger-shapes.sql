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
SELECT public.rule_table_register('public.codex_probe_rules','law','codex_probe_law','{customer_class}','{}');

CREATE FUNCTION public.codex_noop() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RETURN NEW; END $$;
SELECT pg_temp.expect('insert function on UPDATE is refused', $q$
 CREATE OR REPLACE TRIGGER rule_row_insert BEFORE UPDATE ON public.codex_probe_rules FOR EACH ROW EXECUTE FUNCTION public.enforce_rule_row_insert();
 ALTER TABLE public.codex_probe_rules ENABLE ALWAYS TRIGGER rule_row_insert;
 SELECT public.assert_rule_table_invariants()$q$,'42P16','rule_row_insert is not the template');
SELECT pg_temp.expect('no-truncate function on AFTER TRUNCATE is refused', $q$
 CREATE OR REPLACE TRIGGER rule_row_no_truncate AFTER TRUNCATE ON public.codex_probe_rules FOR EACH STATEMENT EXECUTE FUNCTION public.enforce_rule_registry_no_truncate();
 ALTER TABLE public.codex_probe_rules ENABLE ALWAYS TRIGGER rule_row_no_truncate;
 SELECT public.assert_rule_table_invariants()$q$,'42P16','rule_row_no_truncate is not the template');
SELECT pg_temp.expect('AFTER transition-table replacement is refused', $q$
 CREATE OR REPLACE TRIGGER rule_row_insert AFTER INSERT ON public.codex_probe_rules REFERENCING NEW TABLE AS inserted FOR EACH STATEMENT EXECUTE FUNCTION public.enforce_rule_row_insert();
 ALTER TABLE public.codex_probe_rules ENABLE ALWAYS TRIGGER rule_row_insert;
 SELECT public.assert_rule_table_invariants()$q$,'42P16','rule_row_insert is not the template');
SELECT pg_temp.expect('deferred constraint replacement is refused', $q$
 DROP TRIGGER rule_row_history ON public.codex_probe_rules;
 CREATE CONSTRAINT TRIGGER rule_row_history AFTER UPDATE OR DELETE ON public.codex_probe_rules DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.enforce_rule_row_history();
 ALTER TABLE public.codex_probe_rules ENABLE ALWAYS TRIGGER rule_row_history;
 SELECT public.assert_rule_table_invariants()$q$,'42P16','rule_row_history is not the template');
SELECT pg_temp.expect('extra AFTER transition and constraint triggers are allowed', $q$
 CREATE TRIGGER z_transition AFTER INSERT ON public.codex_probe_rules REFERENCING NEW TABLE AS inserted FOR EACH STATEMENT EXECUTE FUNCTION public.codex_noop();
 CREATE CONSTRAINT TRIGGER z_deferred AFTER UPDATE ON public.codex_probe_rules DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.codex_noop();
 SELECT public.assert_rule_table_invariants()$q$,NULL);
SELECT pg_temp.expect('trigger arguments are harmless for current functions, which do not read TG_ARGV', $q$
 CREATE OR REPLACE TRIGGER rule_row_insert BEFORE INSERT ON public.codex_probe_rules FOR EACH ROW EXECUTE FUNCTION public.enforce_rule_row_insert('ignored');
 ALTER TABLE public.codex_probe_rules ENABLE ALWAYS TRIGGER rule_row_insert;
 SELECT public.assert_rule_table_invariants()$q$,NULL);
SELECT pg_temp.check_result('cast and CTE preserve C collation',
 (WITH trg AS (SELECT tgname::text AS name FROM pg_trigger WHERE tgrelid='public.codex_probe_rules'::regclass)
 SELECT bool_and(pg_collation_for(name)='"C"') FROM trg));

ROLLBACK;
