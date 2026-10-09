-- A DEFECT notice for governs proves the documented property-reference spelling is refused; accepting cyclic or union-valued delegated citation schemas proves an integrity defect.
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

DO $$ DECLARE s jsonb; t jsonb; msg text; BEGIN
 SELECT json_schema INTO s FROM public.rule_term_schemas WHERE terms_kind='codex_probe_law';
 t:=s||jsonb_build_object('$defs',jsonb_build_object('citation',s#>'{oneOf,1,properties,citation}'));
 t:=jsonb_set(t,'{oneOf,1,properties,citation}','{"$ref":"#/$defs/citation"}');
 PERFORM pg_temp.reg('codex_ref_citation',t);
 RAISE NOTICE 'PASS referenced citation registers';
 t:=s||jsonb_build_object('$defs',jsonb_build_object('governs',s#>'{oneOf,1,properties,governs}'));
 t:=jsonb_set(t,'{oneOf,1,properties,governs}','{"$ref":"#/$defs/governs"}');
 BEGIN
  PERFORM pg_temp.reg('codex_ref_governs',t);
  RAISE NOTICE 'PASS referenced governs registers';
 EXCEPTION WHEN check_violation THEN
  GET STACKED DIAGNOSTICS msg=MESSAGE_TEXT;
  RAISE NOTICE 'DEFECT: documented referenced governs refused: %',msg;
 END;
 t:=s||'{"$defs":{"cycle":{"$ref":"#/$defs/cycle"}}}'::jsonb;
 t:=jsonb_set(t,'{oneOf,1,properties,citation}','{"$ref":"#/$defs/cycle"}');
 PERFORM pg_temp.expect('cyclic property reference',format('SELECT pg_temp.reg(%L,%L::jsonb)','codex_ref_cycle',t),'23514','reference');
 t:=s||jsonb_build_object('$defs',jsonb_build_object('union',jsonb_build_object('oneOf',s->'oneOf')));
 t:=jsonb_set(t,'{oneOf,1,properties,citation}','{"$ref":"#/$defs/union"}');
 PERFORM pg_temp.expect('citation reference to union',format('SELECT pg_temp.reg(%L,%L::jsonb)','codex_ref_union',t),'23514','must admit');
END $$;
ROLLBACK;
