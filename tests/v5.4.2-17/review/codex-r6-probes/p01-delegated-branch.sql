-- A FAIL proves a valid annotated/reordered/referenced delegated branch is refused, or an extra constraint is accepted.

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
DECLARE s jsonb := '{"$schema": "https://json-schema.org/draft/2020-12/schema", "oneOf": [{"type": "object", "additionalProperties": false, "properties": {"governs": {"type": "string", "const": "law"}, "citation": {"type": "string", "pattern": "[A-Za-z0-9]"}, "cap": {"type": "number", "minimum": 0}}, "required": ["governs", "citation", "cap"]}, {"type": "object", "additionalProperties": false, "properties": {"governs": {"type": "string", "const": "delegated_to_utility"}, "citation": {"type": "string", "pattern": "[A-Za-z0-9]"}, "note": {"type": "string", "pattern": "[A-Za-z0-9]"}}, "required": ["governs", "citation"]}]}'::jsonb; t jsonb; i integer:=0;
BEGIN
 FOR i IN 1..5 LOOP
  t:=s;
  IF i=2 THEN t:=jsonb_set(t,'{oneOf,1,required}','["citation","governs"]'); END IF;
  IF i=3 THEN
   t:=jsonb_set(t,'{oneOf,1,description}','"annotation"');
   t:=jsonb_set(t,'{oneOf,1,properties,citation,title}','"citation annotation"');
   t:=jsonb_set(t,'{oneOf,1,properties,governs,$comment}','"governs annotation"');
  END IF;
  IF i=4 THEN
   t:=t || jsonb_build_object('$defs',jsonb_build_object('delegated',t#>'{oneOf,1}'));
   t:=jsonb_set(t,'{oneOf,1}','{"$ref":"#/$defs/delegated","description":"reference annotation"}');
  END IF;
  IF i=5 THEN t:=t #- '{oneOf,1,properties,note}'; END IF;
  PERFORM pg_temp.reg('codex_delegate_'||i,t);
  IF cardinality(public.rule_terms_errors(t,'{"governs":"delegated_to_utility","citation":"ZZ 9"}'))<>0 THEN
   RAISE EXCEPTION 'FAIL valid delegated document refused, variant %',i;
  END IF;
  RAISE NOTICE 'PASS positive delegated variant %',i;
 END LOOP;
 PERFORM pg_temp.expect('extra governs constraint',format('SELECT pg_temp.reg(%L,%L::jsonb)','codex_bad_delegate',jsonb_set(s,'{oneOf,1,properties,governs,maxLength}','1')),'23514','must admit');
 PERFORM pg_temp.expect('required optional note',format('SELECT pg_temp.reg(%L,%L::jsonb)','codex_bad_delegate',jsonb_set(s,'{oneOf,1,required}','["governs","citation","note"]')),'23514','must admit');
 PERFORM pg_temp.expect('extra citation constraint',format('SELECT pg_temp.reg(%L,%L::jsonb)','codex_bad_delegate',jsonb_set(s,'{oneOf,1,properties,citation,maxLength}','1')),'23514','must admit');
END $p$;

ROLLBACK;
