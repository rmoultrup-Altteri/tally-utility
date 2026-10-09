-- Missing late-trigger diagnostics, or DEFECT notices after replacing history with an ALWAYS trigger on another event, prove an incomplete trigger invariant; odd early names and statement/AFTER triggers should remain allowed.
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

CREATE FUNCTION public.codex_noop() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RETURN NEW; END $$;
DO $$ DECLARE n text; errs text[]; BEGIN
 FOREACH n IN ARRAY ARRAY['0_early','A_early','_early','rule_row_historx','rule_row_history_','rule_row_inseru','z_late'] LOOP
  EXECUTE format('CREATE TRIGGER %I BEFORE INSERT ON public.codex_probe_rules FOR EACH ROW EXECUTE FUNCTION public.codex_noop()',n);
  errs:=public.rule_table_trigger_errors('public.codex_probe_rules');
  IF (cardinality(errs)>0) IS DISTINCT FROM (n COLLATE "C">='rule_row_history') THEN
   RAISE EXCEPTION 'FAIL ordering %: %',n,errs;
  END IF;
  RAISE NOTICE 'PASS ordering %: %',n,errs;
  EXECUTE format('DROP TRIGGER %I ON public.codex_probe_rules',n);
 END LOOP;
END $$;
CREATE TRIGGER z_statement BEFORE INSERT ON public.codex_probe_rules FOR EACH STATEMENT EXECUTE FUNCTION public.codex_noop();
CREATE TRIGGER z_after AFTER INSERT ON public.codex_probe_rules FOR EACH ROW EXECUTE FUNCTION public.codex_noop();
CREATE TRIGGER rule_row_history BEFORE INSERT ON public.codex_probe_rules FOR EACH ROW EXECUTE FUNCTION public.codex_noop();
SELECT pg_temp.expect('reserved history name on wrong event collides at registration',
 $q$SELECT public.rule_table_register('public.codex_probe_rules','law','codex_probe_law','{customer_class}','{}')$q$,'42710','already exists');
DROP TRIGGER rule_row_history ON public.codex_probe_rules;
SELECT public.rule_table_register('public.codex_probe_rules','law','codex_probe_law','{customer_class}','{}');
SELECT public.assert_rule_table_invariants();
INSERT INTO public.codex_probe_rules(state_code,service_type,customer_class,effective_from,source_note,terms_kind,terms_version,terms_source)
 VALUES('ZZ','gas','residential',DATE '2000-01-01','original','codex_probe_law',1,'{"governs":"delegated_to_utility","citation":"ZZ 9"}');
DROP TRIGGER rule_row_history ON public.codex_probe_rules;
CREATE TRIGGER rule_row_history BEFORE INSERT ON public.codex_probe_rules FOR EACH ROW EXECUTE FUNCTION public.codex_noop();
ALTER TABLE public.codex_probe_rules ENABLE ALWAYS TRIGGER rule_row_history;
DO $$ BEGIN
 BEGIN
  PERFORM public.assert_rule_table_invariants();
  RAISE NOTICE 'DEFECT: assertion accepted history trigger on INSERT with wrong function';
 EXCEPTION WHEN invalid_table_definition THEN
  RAISE NOTICE 'PASS assertion refused wrong history trigger';
 END;
END $$;
UPDATE public.codex_probe_rules SET source_note='changed without a close';
SELECT 'DEFECT: history edit accepted after misconfigured migration' AS result,source_note FROM public.codex_probe_rules;
ROLLBACK;
