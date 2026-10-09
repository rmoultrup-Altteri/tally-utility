-- ============================================================================
-- BATTERY v5.4.2-17 — the rule-terms convention (2026-10-07; draft r1)
-- Run (tests/v5.4.2-17/run-battery-17.sh copies law/ into the container):
--   psql -U tally -d <db-with-patch> -v ON_ERROR_STOP=1 -f battery-17.sql
-- One transaction, rolled back. The fixture is a fictional state's law (ZZ):
-- a law kind, a tariff kind and an inputs kind, read from law/fixtures/zz/,
-- on tables the battery creates and registers. Negative cases go through
-- pg_temp.refuses(), which runs the statement (as a role and user when
-- given), requires the named SQLSTATE AND a phrase of the named guard's own
-- message — so a refusal by a different guard is a failure, not a pass.
-- Success checks use IS DISTINCT FROM, so a NULL fails.
--
--   R  the term-schema registry                      (patch section 4)
--   V  the validator and the parser                  (section 3)
--   F  facets                                         (section 4)
--   T  the template: registration, rows, applicability, closes (sections 5-6)
--   L  lookups                                        (section 6)
--   U  tariff rows against the law                    (section 6)
--   C  citations and the close floor                  (section 6)
--   A  adopting pre-convention rows                   (section 6)
--   P  published values                               (section 7)
--   I  core inputs and their fingerprint              (section 8)
--   K  tally_core and audit findings                  (sections 1, 9)
--   G  tenancy, the AC-32 tail                        (section 10)
-- Outside one transaction (separate transactions, isolation levels, two
-- sessions): isolation-17.sh (facets outside their schema's transaction,
-- READ COMMITTED refusals) and races/rule-close-17.sh (a close against a
-- citation; a freeze against an insert).
-- ============================================================================
\set ON_ERROR_STOP 1
BEGIN;
SET CONSTRAINTS ALL IMMEDIATE;
-- The ZZ area as an area migration would write it: its kinds, facets,
-- vocabulary, tables, hooks and registrations (shared with tools/law's CI).
\i /tmp/law/fixtures/zz/fixture-zz.sql

CREATE TEMP TABLE zzs (k text PRIMARY KEY, s jsonb NOT NULL);
INSERT INTO zzs VALUES ('fee', :'zz_fee_schema'), ('tariff', :'zz_tariff_schema'), ('inputs', :'zz_inputs_schema');
CREATE TEMP TABLE b17 (k text PRIMARY KEY, id uuid);

-- refuses(label, sql, sqlstate, phrase, role, user): the statement must fail
-- with that SQLSTATE and a message containing the phrase.
CREATE FUNCTION pg_temp.refuses(p_label text, p_sql text, p_state text, p_phrase text DEFAULT NULL,
                                p_role text DEFAULT NULL, p_user text DEFAULT NULL) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE
  v_state text;
  v_msg   text;
BEGIN
  BEGIN
    IF p_user IS NOT NULL THEN PERFORM set_config('app.user_id', p_user, true); END IF;
    IF p_role IS NOT NULL THEN EXECUTE format('SET LOCAL ROLE %I', p_role); END IF;
    EXECUTE p_sql;
    RAISE EXCEPTION 'not refused' USING ERRCODE = 'P0099';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
  END;
  IF v_state = 'P0099' THEN
    RAISE EXCEPTION 'FAIL %: not refused', p_label;
  END IF;
  IF v_state IS DISTINCT FROM p_state THEN
    RAISE EXCEPTION 'FAIL %: refused with % (%), expected %', p_label, v_state, v_msg, p_state;
  END IF;
  IF p_phrase IS NOT NULL AND strpos(v_msg, p_phrase) = 0 THEN
    RAISE EXCEPTION 'FAIL %: refused by another guard: %', p_label, v_msg;
  END IF;
  RAISE NOTICE 'PASS %', p_label;
END $$;
-- run(sql, role, user): run it (as a role and user when given), then reset.
CREATE FUNCTION pg_temp.run(p_sql text, p_role text DEFAULT NULL, p_user text DEFAULT NULL) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  IF p_user IS NOT NULL THEN PERFORM set_config('app.user_id', p_user, true); END IF;
  IF p_role IS NOT NULL THEN EXECUTE format('SET LOCAL ROLE %I', p_role); END IF;
  EXECUTE p_sql;
  RESET ROLE;
END $$;
CREATE FUNCTION pg_temp.ok(p_label text, p_cond boolean) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  IF p_cond IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'FAIL %', p_label;
  END IF;
  RAISE NOTICE 'PASS %', p_label;
END $$;
-- does(label, sql): the statement must succeed; an error is that check's FAIL.
CREATE FUNCTION pg_temp.does(p_label text, p_sql text) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE v_msg text;
BEGIN
  EXECUTE p_sql;
EXCEPTION WHEN OTHERS THEN
  GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
  RAISE EXCEPTION 'FAIL %: %', p_label, v_msg;
END $$;
-- ok_sql(label, sql): a boolean query that must be true; an error is a FAIL.
CREATE FUNCTION pg_temp.ok_sql(p_label text, p_sql text) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE v boolean; v_msg text;
BEGIN
  BEGIN
    EXECUTE p_sql INTO v;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    RAISE EXCEPTION 'FAIL %: %', p_label, v_msg;
  END;
  PERFORM pg_temp.ok(p_label, v);
END $$;
CREATE FUNCTION pg_temp.id(p_k text) RETURNS uuid LANGUAGE sql STABLE AS $$ SELECT id FROM b17 WHERE k = p_k $$;
CREATE FUNCTION pg_temp.s(p_k text) RETURNS jsonb LANGUAGE sql STABLE AS $$ SELECT s FROM zzs WHERE k = p_k $$;
-- reg(kind, version, role, schema): register a term schema (owner).
CREATE FUNCTION pg_temp.reg(p_kind text, p_version integer, p_role text, p_schema jsonb) RETURNS void
LANGUAGE sql AS $$
  INSERT INTO public.rule_term_schemas (terms_kind, terms_version, rule_role, json_schema, introduced_on, description, source_note)
  VALUES (p_kind, p_version, p_role, p_schema, DATE '2026-10-07', 'battery ' || p_kind, 'battery fixture')
$$;

-- The users and tenants: T1 runs a city-owned system in ZZ, T2 an investor-
-- owned one under the commission.
INSERT INTO public.tenants (id, name, slug) VALUES
  ('00000000-0000-4000-8000-0000000017a1', 'T1 Zedton Gas', 'bat17-t1'),
  ('00000000-0000-4000-8000-0000000017a2', 'T2 Zed Gasco', 'bat17-t2');
INSERT INTO public.users (id, tenant_id, display_name, email, role) VALUES
  ('00000000-0000-4000-8000-0000000017b1', '00000000-0000-4000-8000-0000000017a1', 'Op1', 'op1@bat17.test', 'operator'),
  ('00000000-0000-4000-8000-0000000017b2', '00000000-0000-4000-8000-0000000017a2', 'Op2', 'op2@bat17.test', 'operator');
\set u1 '00000000-0000-4000-8000-0000000017b1'
\set u2 '00000000-0000-4000-8000-0000000017b2'
\set t1 '00000000-0000-4000-8000-0000000017a1'
\set t2 '00000000-0000-4000-8000-0000000017a2'

-- ZZ places (platform) and the two profiles (the utilities').
INSERT INTO public.places (kind_code, state_code, place_code, name, effective_from, source_note)
VALUES ('state', 'ZZ', 'ZZ', 'Zedland', DATE '1900-01-01', 'battery fixture: a fictional state');
INSERT INTO b17 SELECT 'zz', id FROM public.places WHERE kind_code = 'state' AND place_code = 'ZZ';
INSERT INTO public.places (kind_code, state_code, place_code, name, parent_place_id, effective_from, source_note)
VALUES ('municipality', 'ZZ', 'ZEDTON', 'Zedton', pg_temp.id('zz'), DATE '1950-01-01', 'battery fixture');
INSERT INTO b17 SELECT 'zedton', id FROM public.places WHERE kind_code = 'municipality' AND place_code = 'ZEDTON';
SELECT pg_temp.run(format($q$
  INSERT INTO public.utility_service_profiles (tenant_id, service_type, system_kind, state_code, owner_type, commission_jurisdiction,
                                               owning_place_id, effective_from, evidence_reference, evidence_date)
  VALUES (%L, 'gas', 'distribution', 'ZZ', 'municipal', false, %L, DATE '2000-01-01', 'Zedton charter art. 9', DATE '2000-01-01')$q$,
  :'t1', pg_temp.id('zedton')), 'tally_app', :'u1');
SELECT pg_temp.run(format($q$
  INSERT INTO public.utility_service_profiles (tenant_id, service_type, system_kind, state_code, owner_type, commission_jurisdiction,
                                               effective_from, evidence_reference, evidence_date)
  VALUES (%L, 'gas', 'distribution', 'ZZ', 'investor_owned', true, DATE '2000-01-01', 'ZZ PUC certificate 1', DATE '2000-01-01')$q$,
  :'t2'), 'tally_app', :'u2');


-- ============================================================ R. the registry
SELECT pg_temp.ok('R1: a law kind with the delegated document registers; its hash is stamped from the schema',
  (SELECT schema_hash = 'sha256:' || encode(sha256(convert_to(json_schema::text, 'UTF8')), 'hex') AND accepts_new_rows AND frozen_at IS NULL
     FROM public.rule_term_schemas WHERE terms_kind = 'zz_fee' AND terms_version = 1));
SELECT pg_temp.refuses('R2a: a version that is not the next one (3 after 1)',
  $q$SELECT pg_temp.reg('zz_fee', 3, 'law', pg_temp.s('fee'))$q$, '23514', 'the next version is 2');
SELECT pg_temp.refuses('R2b: a later version that changes the kind''s role',
  $q$SELECT pg_temp.reg('zz_fee', 2, 'tariff', pg_temp.s('tariff'))$q$, '23514', 'cannot change its role');
SELECT pg_temp.refuses('R3a: a law kind whose "governs" takes a value other than law and delegated_to_utility',
  $q$SELECT pg_temp.reg('zz_nodel', 1, 'law', jsonb_set(pg_temp.s('fee'), '{$defs,delegated,properties,governs,const}', '"repealed"'))$q$,
  '23514', 'not "repealed"');
SELECT pg_temp.refuses('R3b: a law kind whose delegated document cites nothing',
  $q$SELECT pg_temp.reg('zz_nodel', 1, 'law', jsonb_set(pg_temp.s('fee'), '{$defs,delegated,required}', '["governs"]'))$q$,
  '23514', 'must admit {"governs": "delegated_to_utility"');
SELECT pg_temp.refuses('R3c: a law kind whose root is not a union on "governs"',
  $q$SELECT pg_temp.reg('zz_nodel', 1, 'law', pg_temp.s('tariff'))$q$, '23514', 'discriminated by "governs"');
SELECT pg_temp.refuses('R4a: an unsupported keyword (format) — the validator would not enforce it',
  $q$SELECT pg_temp.reg('zz_x', 1, 'tariff', jsonb_set(pg_temp.s('tariff'), '{properties,note,format}', '"date"'))$q$,
  '23514', 'keyword "format" is not supported');
SELECT pg_temp.refuses('R4b: an object schema left open (no additionalProperties: false)',
  $q$SELECT pg_temp.reg('zz_x', 1, 'tariff', pg_temp.s('tariff') - 'additionalProperties')$q$,
  '23514', 'must set "additionalProperties": false');
SELECT pg_temp.refuses('R4c: a pattern outside the whitelist',
  $q$SELECT pg_temp.reg('zz_x', 1, 'tariff', jsonb_set(pg_temp.s('tariff'), '{properties,note,pattern}', '"^\\w+$"'))$q$,
  '23514', 'pattern must be one of');
SELECT pg_temp.refuses('R4d: a $ref to a definition that does not exist',
  $q$SELECT pg_temp.reg('zz_x', 1, 'law', jsonb_set(pg_temp.s('fee'), '{$defs,law,properties,citation,$ref}', '"#/$defs/nope"'))$q$,
  '23514', 'names no definition');
SELECT pg_temp.refuses('R4e: a definition that is itself a reference (a chain)',
  $q$SELECT pg_temp.reg('zz_x', 1, 'law', jsonb_set(pg_temp.s('fee'), '{$defs,alias}', '{"$ref": "#/$defs/code"}'))$q$,
  '23514', 'may not be a reference');
SELECT pg_temp.refuses('R4f: a union whose branches share no const discriminator',
  $q$SELECT pg_temp.reg('zz_x', 1, 'law', jsonb_set(pg_temp.s('fee'), '{$defs,fee_greater_of,properties,strategy}', '{"type": "string"}'))$q$,
  '23514', 'exactly one property that every branch requires');
SELECT pg_temp.refuses('R4g: a union whose branches repeat a discriminator value',
  $q$SELECT pg_temp.reg('zz_x', 1, 'law', jsonb_set(pg_temp.s('fee'), '{$defs,fee_greater_of,properties,strategy,const}', '"flat"'))$q$,
  '23514', 'repeat a value of "strategy"');
SELECT pg_temp.refuses('R4h: the type "null" (no document may hold a null)',
  $q$SELECT pg_temp.reg('zz_x', 1, 'tariff', jsonb_set(pg_temp.s('tariff'), '{properties,note,type}', '"null"'))$q$,
  '23514', '"type" is required and must be one of');
SELECT pg_temp.refuses('R4i: a type list (["string", "null"])',
  $q$SELECT pg_temp.reg('zz_x', 1, 'tariff', jsonb_set(pg_temp.s('tariff'), '{properties,note,type}', '["string", "null"]'))$q$,
  '23514', '"type" is required and must be one of');
SELECT pg_temp.refuses('R4j: required naming a property that is not defined',
  $q$SELECT pg_temp.reg('zz_x', 1, 'tariff', jsonb_set(pg_temp.s('tariff'), '{required}', '["fee", "fees"]'))$q$,
  '23514', 'which properties does not define');
SELECT pg_temp.refuses('R4k: a schema of another JSON Schema draft',
  $q$SELECT pg_temp.reg('zz_x', 1, 'tariff', jsonb_set(pg_temp.s('tariff'), '{$schema}', '"http://json-schema.org/draft-07/schema#"'))$q$,
  '23514', '"$schema" must be');
SELECT pg_temp.refuses('R4l: $defs below the root',
  $q$SELECT pg_temp.reg('zz_x', 1, 'tariff', jsonb_set(pg_temp.s('tariff'), '{properties,fee,$defs}', '{}'))$q$,
  '23514', 'keyword "$defs" is not supported here');
SELECT pg_temp.refuses('R4m: an array schema without items',
  $q$SELECT pg_temp.reg('zz_x', 1, 'inputs', pg_temp.s('inputs') #- '{properties,flags,items}')$q$,
  '23514', 'must define items');
SELECT pg_temp.ok('R5: a tariff kind and an inputs kind register', (SELECT count(*) FROM public.rule_term_schemas WHERE terms_kind LIKE 'zz%') = 3);
SELECT pg_temp.refuses('R4n: a strategy branch whose version range is empty (minimum above maximum)',
  $q$SELECT pg_temp.reg('zz_x', 1, 'law', jsonb_set(pg_temp.s('fee'), '{$defs,fee_flat,properties,version,maximum}', '0'))$q$,
  '23514', 'strategy "flat" must require "version", an integer with 1 <= minimum <= maximum');
SELECT pg_temp.refuses('R4o: a strategy branch whose version is unbounded',
  $q$SELECT pg_temp.reg('zz_x', 1, 'law', pg_temp.s('fee') #- '{$defs,fee_flat,properties,version,maximum}')$q$,
  '23514', 'strategy "flat" must require "version"');
SELECT pg_temp.refuses('R4p: a strategy version bound that is not an integer',
  $q$SELECT pg_temp.reg('zz_x', 1, 'law', jsonb_set(pg_temp.s('fee'), '{$defs,fee_flat,properties,version,maximum}', '1.5'))$q$,
  '23514', 'strategy "flat" must require "version"');
-- review r4 (Codex B1): the delegated branch is exactly the standard document.
SELECT pg_temp.refuses('R3d: a delegated "governs" no document can satisfy (maxLength 1)',
  $q$SELECT pg_temp.reg('zz_nodel', 1, 'law', jsonb_set(pg_temp.s('fee'), '{$defs,delegated,properties,governs,maxLength}', '1'))$q$,
  '23514', 'must admit {"governs": "delegated_to_utility"');
SELECT pg_temp.refuses('R3e: a delegated branch that requires its optional note',
  $q$SELECT pg_temp.reg('zz_nodel', 1, 'law', jsonb_set(pg_temp.s('fee'), '{$defs,delegated,required}', '["governs", "citation", "note"]'))$q$,
  '23514', 'must admit {"governs": "delegated_to_utility"');
SELECT pg_temp.refuses('R3f: a delegated citation no document can satisfy (maxLength 1)',
  $q$SELECT pg_temp.reg('zz_nodel', 1, 'law', jsonb_set(pg_temp.s('fee'), '{$defs,delegated,properties,citation,maxLength}', '1'))$q$,
  '23514', 'must admit {"governs": "delegated_to_utility"');
SELECT pg_temp.does('R3g: … while annotations on the delegated branch and its properties change nothing',
  $q$SELECT pg_temp.reg('zz_annot', 1, 'law',
       jsonb_set(jsonb_set(jsonb_set(pg_temp.s('fee'), '{$defs,delegated,description}', '"the law leaves it to the utility"'),
                           '{$defs,delegated,properties,governs,description}', '"the branch"'),
                 '{$defs,delegated,properties,note,title}', '"note"'))$q$);
-- review r4 (Codex B2): a lone strategy names its version too.
SELECT pg_temp.refuses('R4q: a lone strategy (no union to choose in) that fixes no version',
  $q$SELECT pg_temp.reg('zz_lone', 1, 'tariff', '{"$schema": "https://json-schema.org/draft/2020-12/schema", "type": "object", "additionalProperties": false,
      "required": ["fee"], "properties": {"fee": {"type": "object", "additionalProperties": false, "required": ["strategy"],
        "properties": {"strategy": {"type": "string", "const": "flat"}}}}}')$q$,
  '23514', 'strategy "flat" must require "version"');
SELECT pg_temp.does('R4r: … and the same lone strategy with a bounded version registers',
  $q$SELECT pg_temp.reg('zz_lone', 1, 'tariff', '{"$schema": "https://json-schema.org/draft/2020-12/schema", "type": "object", "additionalProperties": false,
      "required": ["fee"], "properties": {"fee": {"type": "object", "additionalProperties": false, "required": ["strategy", "version"],
        "properties": {"strategy": {"type": "string", "const": "flat"},
                       "version": {"type": "integer", "minimum": 1, "maximum": 1}}}}}')$q$);
SELECT pg_temp.refuses('R6a: the application cannot register a schema',
  format($q$INSERT INTO public.rule_term_schemas (terms_kind, terms_version, rule_role, json_schema, introduced_on, description, source_note)
            VALUES ('zz_app', 1, 'tariff', %L, DATE '2026-10-07', 'x', 'x')$q$, pg_temp.s('tariff')), '42501', 'permission denied for table rule_term_schemas', 'tally_app', :'u1');
SELECT pg_temp.refuses('R6b: nor can the core',
  format($q$INSERT INTO public.rule_term_schemas (terms_kind, terms_version, rule_role, json_schema, introduced_on, description, source_note)
            VALUES ('zz_core', 1, 'tariff', %L, DATE '2026-10-07', 'x', 'x')$q$, pg_temp.s('tariff')), '42501', 'permission denied for table rule_term_schemas', 'tally_core', :'u1');
SELECT pg_temp.refuses('R7a: a schema is never edited (description)',
  $q$UPDATE public.rule_term_schemas SET description = 'x' WHERE terms_kind = 'zz_fee'$q$, '23001', 'never edited');
SELECT pg_temp.refuses('R7b: a freeze that carries an edit',
  $q$UPDATE public.rule_term_schemas SET accepts_new_rows = false, json_schema = '{}' WHERE terms_kind = 'zz_fee'$q$, '23001', 'never edited');
SELECT pg_temp.refuses('R7c: a schema is never deleted',
  $q$DELETE FROM public.rule_term_schemas WHERE terms_kind = 'zz_fee'$q$, '23001', 'never deleted');
SELECT pg_temp.refuses('R7d: the registry is never truncated',
  $q$TRUNCATE public.rule_term_schemas CASCADE$q$, '23001', 'rule_term_schemas is never truncated');
SELECT pg_temp.reg('zz_fee', 2, 'law', pg_temp.s('fee'));
UPDATE public.rule_term_schemas SET accepts_new_rows = false WHERE terms_kind = 'zz_fee' AND terms_version = 2;
SELECT pg_temp.ok('R8a: a freeze is stamped', (SELECT NOT accepts_new_rows AND frozen_at IS NOT NULL AND frozen_by = session_user
                                                   FROM public.rule_term_schemas WHERE terms_kind = 'zz_fee' AND terms_version = 2));
SELECT pg_temp.refuses('R8b: a frozen version is never thawed',
  $q$UPDATE public.rule_term_schemas SET accepts_new_rows = true, frozen_at = NULL, frozen_by = NULL WHERE terms_kind = 'zz_fee' AND terms_version = 2$q$,
  '23001', 'the one change is a freeze');


-- ============================================================ V. validator and parser
CREATE FUNCTION pg_temp.verr(p_kind text, p_doc jsonb) RETURNS text
LANGUAGE sql STABLE AS $$ SELECT array_to_string(public.rule_terms_errors(pg_temp.s(p_kind), p_doc), ' | ') $$;
CREATE TEMP TABLE good (k text PRIMARY KEY, d jsonb);
INSERT INTO good VALUES
  ('flat', '{"governs": "law", "citation": "ZZ Code 1.1", "fee": {"strategy": "flat", "version": 1, "id": "f1", "cap": 50, "citation": "ZZ Code 1.1(a)"},
             "waivers": [{"id": "w1", "class": "senior", "effect": "halve"}]}'),
  ('greater', '{"governs": "law", "citation": "ZZ Code 1.2", "fee": {"strategy": "greater_of", "version": 1, "id": "f2", "cap": 500, "citation": "ZZ Code 1.2(b)",
                "parts": [{"id": "p1", "kind": "fixed", "amount": 25}, {"id": "p2", "kind": "per_meter", "amount": 12.5}]}, "waivers": []}'),
  ('delegated', '{"governs": "delegated_to_utility", "citation": "ZZ Code 9.9", "note": "Cities set their own fees."}'),
  ('tariff', '{"fee": {"strategy": "flat", "version": 1, "id": "t1", "amount": 40}}');
CREATE FUNCTION pg_temp.g(p_k text) RETURNS jsonb LANGUAGE sql STABLE AS $$ SELECT d FROM good WHERE k = p_k $$;

SELECT pg_temp.ok('V1: valid documents of each branch have no errors',
  pg_temp.verr('fee', pg_temp.g('flat')) = '' AND pg_temp.verr('fee', pg_temp.g('greater')) = ''
  AND pg_temp.verr('fee', pg_temp.g('delegated')) = '' AND pg_temp.verr('tariff', pg_temp.g('tariff')) = '');
SELECT pg_temp.ok('V2: an unknown key is refused, by its pointer',
  pg_temp.verr('fee', jsonb_set(pg_temp.g('flat'), '{fee,retroactve}', 'true')) = '/fee/retroactve: unknown key');
SELECT pg_temp.ok('V3: a missing required key',
  pg_temp.verr('fee', pg_temp.g('flat') #- '{fee,cap}') = '/fee/cap: required');
SELECT pg_temp.ok('V4: a null anywhere',
  pg_temp.verr('fee', jsonb_set(pg_temp.g('flat'), '{fee,cap}', 'null')) LIKE '/fee/cap: null is not allowed%');
SELECT pg_temp.ok('V5: a wrong type (a string cap)',
  pg_temp.verr('fee', jsonb_set(pg_temp.g('flat'), '{fee,cap}', '"50"')) = '/fee/cap: expected a number');
SELECT pg_temp.ok('V6: an unknown strategy names the allowed ones',
  pg_temp.verr('fee', jsonb_set(pg_temp.g('flat'), '{fee,strategy}', '"lesser_of"')) = '/fee/strategy: "lesser_of" is not one of flat, greater_of');
SELECT pg_temp.ok('V7: a strategy''s own parameters are checked (greater_of needs parts)',
  pg_temp.verr('fee', jsonb_set(pg_temp.g('flat'), '{fee,strategy}', '"greater_of"')) = '/fee/parts: required');
SELECT pg_temp.ok('V8: a discriminator that is not a string',
  pg_temp.verr('fee', jsonb_set(pg_temp.g('flat'), '{governs}', '1')) = '/governs: expected a string');
SELECT pg_temp.ok('V9: an enum value',
  pg_temp.verr('fee', jsonb_set(pg_temp.g('flat'), '{waivers,0,effect}', '"double"')) = '/waivers/0/effect: "double" is not one of excuse, halve');
SELECT pg_temp.ok('V10: a strategy version beyond its range, and a non-integer one',
  pg_temp.verr('fee', jsonb_set(pg_temp.g('flat'), '{fee,version}', '2')) = '/fee/version: must be at most 1'
  AND pg_temp.verr('fee', jsonb_set(pg_temp.g('flat'), '{fee,version}', '1.5')) = '/fee/version: expected an integer | /fee/version: must be at most 1');
SELECT pg_temp.ok('V11: minimum, and exclusive bounds at their edges',
  pg_temp.verr('fee', jsonb_set(pg_temp.g('flat'), '{fee,cap}', '-0.01')) = '/fee/cap: must be at least 0'
  AND pg_temp.verr('fee', jsonb_set(pg_temp.g('flat'), '{fee,cap}', '0')) = ''
  AND pg_temp.verr('fee', jsonb_set(pg_temp.g('greater'), '{fee,parts,0,amount}', '0')) = '/fee/parts/0/amount: must be greater than 0'
  AND pg_temp.verr('fee', jsonb_set(pg_temp.g('greater'), '{fee,parts,0,amount}', '10000')) = '/fee/parts/0/amount: must be less than 10000'
  AND pg_temp.verr('fee', jsonb_set(pg_temp.g('greater'), '{fee,parts,0,amount}', '9999.99')) = '');
SELECT pg_temp.ok('V12: minItems and maxItems',
  pg_temp.verr('fee', jsonb_set(pg_temp.g('greater'), '{fee,parts}', '[{"id": "p1", "kind": "fixed", "amount": 1}]')) = '/fee/parts: at least 2 items'
  AND pg_temp.verr('fee', jsonb_set(pg_temp.g('greater'), '{fee,parts}',
        '[{"id": "a", "kind": "fixed", "amount": 1}, {"id": "b", "kind": "fixed", "amount": 1}, {"id": "c", "kind": "fixed", "amount": 1},
          {"id": "d", "kind": "fixed", "amount": 1}, {"id": "e", "kind": "fixed", "amount": 1}]')) = '/fee/parts: at most 4 items');
SELECT pg_temp.ok('V13: uniqueItems (the same waiver twice) — and the repeated id is caught too',
  pg_temp.verr('fee', jsonb_set(pg_temp.g('flat'), '{waivers}', '[{"id": "w1", "class": "senior", "effect": "halve"}, {"id": "w1", "class": "senior", "effect": "halve"}]'))
    = '/waivers: items must be unique | : component ids must be unique in a document: w1 repeated');
SELECT pg_temp.ok('V14: a pattern (a code with a capital) and a citation with no letter or digit',
  pg_temp.verr('fee', jsonb_set(pg_temp.g('flat'), '{fee,id}', '"F1"')) = '/fee/id: does not match ^[a-z][a-z0-9_]*$'
  AND pg_temp.verr('fee', jsonb_set(pg_temp.g('flat'), '{citation}', '"§ — ."')) = '/citation: does not match [A-Za-z0-9]');
SELECT pg_temp.ok('V15: component ids are unique across the document, not only within an array',
  pg_temp.verr('fee', jsonb_set(pg_temp.g('greater'), '{fee,parts,1,id}', '"f2"')) = ': component ids must be unique in a document: f2 repeated');
SELECT pg_temp.ok('V16: numbers are written canonically (1.50 and 2.0 refused, 1.5 and 2 accepted)',
  pg_temp.verr('fee', jsonb_set(pg_temp.g('flat'), '{fee,cap}', '1.50')) = ': numbers must be written canonically, without trailing fractional zeros: 1.50'
  AND pg_temp.verr('fee', jsonb_set(pg_temp.g('flat'), '{fee,cap}', '2.0')) = ': numbers must be written canonically, without trailing fractional zeros: 2.0'
  AND pg_temp.verr('fee', jsonb_set(pg_temp.g('flat'), '{fee,cap}', '1.5')) = '');
SELECT pg_temp.ok('V17: the delegated document admits nothing else',
  pg_temp.verr('fee', jsonb_set(pg_temp.g('delegated'), '{fee}', '{}')) = '/fee: unknown key');
SELECT pg_temp.ok('V18: a root that is not an object',
  pg_temp.verr('tariff', '[1]') = ': expected an object');
SELECT pg_temp.ok('V19: a string length bound (maxLength 200)',
  pg_temp.verr('tariff', jsonb_set(pg_temp.g('tariff'), '{note}', to_jsonb(repeat('a', 201)))) = '/note: at most 200 characters'
  AND pg_temp.verr('tariff', jsonb_set(pg_temp.g('tariff'), '{note}', to_jsonb(repeat('a', 200)))) = '');
SELECT pg_temp.ok('V20: a JSON Pointer escapes ~ and / in a key',
  pg_temp.verr('tariff', jsonb_set(pg_temp.g('tariff'), '{a/b~c}', 'true')) = '/a~1b~0c: unknown key');
SELECT pg_temp.refuses('V21a: the parser refuses a duplicate key at the root',
  $q$SELECT public.rule_terms_parse('{"a": 1, "a": 2}')$q$, '22030', 'repeats a key');
SELECT pg_temp.refuses('V21b: … and inside an object inside an array',
  $q$SELECT public.rule_terms_parse('{"w": [{"id": "x", "class": "a", "class": "b"}]}')$q$, '22030', 'repeats a key');
SELECT pg_temp.refuses('V21c: … and a document that is not an object',
  $q$SELECT public.rule_terms_parse('[{"a": 1}]')$q$, '22P02', 'must be a JSON object');
SELECT pg_temp.refuses('V21d: … and no document at all',
  $q$SELECT public.rule_terms_parse(NULL)$q$, '23502', 'a rule document is required');
SELECT pg_temp.ok('V23: no control character in a string or a key (a newline is where validators part company)',
  pg_temp.verr('tariff', jsonb_set(pg_temp.g('tariff'), '{fee,id}', to_jsonb(E't1\n'::text))) LIKE '/fee/id: does not match%strings and keys hold no control characters%'
  AND pg_temp.verr('tariff', jsonb_set(pg_temp.g('tariff'), '{note}', to_jsonb(E'tab\there'::text))) LIKE ': strings and keys hold no control characters%'
  AND pg_temp.verr('tariff', pg_temp.g('tariff') || jsonb_build_object(E'k\ney', 1)) LIKE '%strings and keys hold no control characters%');
SELECT pg_temp.refuses('V21e: the parser refuses what PostgreSQL cannot store (\u0000), by name',
  $q$SELECT public.rule_terms_parse('{"a": "\u0000"}')$q$, '22P02', 'JSON that PostgreSQL can store');
SELECT pg_temp.ok('V10b: a non-integer alone (meters 1.5 has no other fault)',
  array_to_string(public.rule_terms_errors(pg_temp.s('inputs'), '{"bill_amount": 1, "meters": 1.5, "rule_row": "00000000-0000-4000-8000-0000000017e1", "flags": []}', false), ' | ')
    = '/meters: expected an integer');
SELECT pg_temp.ok('V13b: a repeated item alone (no component ids in it)',
  array_to_string(public.rule_terms_errors(pg_temp.s('inputs'), '{"bill_amount": 1, "meters": 1, "rule_row": "00000000-0000-4000-8000-0000000017e1", "flags": [true, true]}', false), ' | ')
    = '/flags: items must be unique');
INSERT INTO zzs VALUES ('deep', '{"$schema": "https://json-schema.org/draft/2020-12/schema", "type": "object", "additionalProperties": false,
  "required": ["payload"], "properties": {"payload": {"$ref": "#/$defs/node"}},
  "$defs": {"node": {"oneOf": [
    {"type": "object", "additionalProperties": false, "required": ["tag"], "properties": {"tag": {"type": "string", "const": "end"}}},
    {"type": "object", "additionalProperties": false, "required": ["tag", "next"],
     "properties": {"tag": {"type": "string", "const": "more"}, "next": {"$ref": "#/$defs/node"}}}]}}}');
CREATE FUNCTION pg_temp.nest(p_levels integer) RETURNS jsonb LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE v jsonb := '{"tag": "end"}';
BEGIN
  FOR i IN 1 .. p_levels LOOP v := jsonb_build_object('tag', 'more', 'next', v); END LOOP;
  RETURN jsonb_build_object('payload', v);
END $$;
SELECT pg_temp.ok('V24: depth counts document levels, not union branches: a tag at depth 64 is valid, at 65 refused',
  public.rule_terms_schema_errors(pg_temp.s('deep')) = '{}'
  AND public.rule_terms_errors(pg_temp.s('deep'), pg_temp.nest(31), false) = '{}'
  AND public.rule_terms_errors(pg_temp.s('deep'), pg_temp.nest(62), false) = '{}'
  AND array_to_string(public.rule_terms_errors(pg_temp.s('deep'), pg_temp.nest(63), false), ' | ') LIKE '%nested more than 64 levels deep%');
SELECT pg_temp.ok('V22: the parser keeps a valid document as written', public.rule_terms_parse('{"a": {"b": [1, 2.5]}}') = '{"a": {"b": [1, 2.5]}}'::jsonb);


-- ============================================================ F. facets
SELECT pg_temp.ok('F1: facets declared with their schema (same transaction)',
  (SELECT count(*) FROM public.rule_term_facets WHERE terms_kind LIKE 'zz%') = 7);
SELECT pg_temp.refuses('F2a: a facet path that does not parse',
  $q$INSERT INTO public.rule_term_facets (terms_kind, terms_version, facet_name, facet_type, json_path, description)
     VALUES ('zz_fee', 1, 'bad', 'text', '$.fee.[', 'x')$q$, '23514', 'is not a SQL/JSON path');
SELECT pg_temp.refuses('F2b: a facet path using .datetime()',
  $q$INSERT INTO public.rule_term_facets (terms_kind, terms_version, facet_name, facet_type, json_path, description)
     VALUES ('zz_fee', 1, 'bad', 'text', '$.fee.citation.datetime()', 'x')$q$, '23514', 'may not use .datetime()');
SELECT pg_temp.refuses('F2c: a vocabulary that is not a table',
  $q$INSERT INTO public.rule_term_facets (terms_kind, terms_version, facet_name, facet_type, json_path, vocabulary_table, vocabulary_column, description)
     VALUES ('zz_fee', 1, 'bad', 'text[]', '$.waivers[*].class', 'public.no_such_table', 'code', 'x')$q$, '23514', 'is not a table');
SELECT pg_temp.refuses('F2d: a vocabulary column that does not exist',
  $q$INSERT INTO public.rule_term_facets (terms_kind, terms_version, facet_name, facet_type, json_path, vocabulary_table, vocabulary_column, description)
     VALUES ('zz_fee', 1, 'bad', 'text[]', '$.waivers[*].class', 'public.zz_waiver_classes', 'code', 'x')$q$, '23514', 'has no column code');
SELECT pg_temp.refuses('F2e: a vocabulary scope naming a column the vocabulary lacks',
  $q$INSERT INTO public.rule_term_facets (terms_kind, terms_version, facet_name, facet_type, json_path, vocabulary_table, vocabulary_column, vocabulary_scope, description)
     VALUES ('zz_fee', 1, 'bad', 'text[]', '$.waivers[*].class', 'public.zz_waiver_classes', 'class_code', '{"region": "state_code"}', 'x')$q$,
  '23514', 'scope region must map');
SELECT pg_temp.refuses('F2f: a vocabulary on a number facet',
  $q$INSERT INTO public.rule_term_facets (terms_kind, terms_version, facet_name, facet_type, json_path, vocabulary_table, vocabulary_column, description)
     VALUES ('zz_fee', 1, 'bad', 'number', '$.fee.cap', 'public.zz_waiver_classes', 'class_code', 'x')$q$, '23514', 'rule_term_facets_vocabulary_check');
SELECT pg_temp.refuses('F2g: a facet path using .double() (it rounds)',
  $q$INSERT INTO public.rule_term_facets (terms_kind, terms_version, facet_name, facet_type, json_path, description)
     VALUES ('zz_fee', 1, 'bad', 'number', '$.fee.cap.double()', 'x')$q$, '23514', 'may not use .double()');
SELECT pg_temp.refuses('F3: a facet is never edited',
  $q$UPDATE public.rule_term_facets SET json_path = '$.fee.id' WHERE facet_name = 'fee_strategy'$q$, '23001', 'never edited or deleted');
SELECT pg_temp.ok('F4: facet values — a text, a number, present, every id, the classes; and a delegated document''s',
  public.rule_terms_facets('zz_fee', 1, pg_temp.g('greater'))
    = '{"fee_cap": 500, "has_fee": true, "fee_strategy": "greater_of", "component_ids": ["f2", "p1", "p2"], "waiver_classes": []}'::jsonb
  AND public.rule_terms_facets('zz_fee', 1, pg_temp.g('delegated'))
    = '{"fee_cap": null, "has_fee": false, "fee_strategy": null, "component_ids": [], "waiver_classes": []}'::jsonb);
SELECT pg_temp.refuses('F5: a single-valued facet whose path matches twice is a registration defect',
  $q$SELECT public.rule_terms_facets('zz_fee_tariff', 1, '{"fee": {"amount": 1}, "x": {"fee": {"amount": 2}}}'::jsonb || jsonb_build_object('fee', '[{"amount": 1}, {"amount": 2}]'::jsonb))$q$,
  '22000', 'a number facet takes at most one');


-- ============================================================ T. the template
SELECT pg_temp.refuses('T1a: a table missing a template column cannot register',
  $q$SELECT public.rule_table_register('public.zz_waiver_classes', 'law', 'zz_fee', '{}', '{}')$q$, '42P16', 'has no column id');
CREATE TABLE public.zz_badkey (LIKE public.zz_fee_rules INCLUDING DEFAULTS);
ALTER TABLE public.zz_badkey ADD PRIMARY KEY (id);
ALTER TABLE public.zz_badkey ALTER COLUMN customer_class DROP NOT NULL;
SELECT pg_temp.refuses('T1b: an area key that may be NULL (it would escape the exclusion)',
  $q$SELECT public.rule_table_register('public.zz_badkey', 'law', 'zz_fee', '{customer_class}', '{}')$q$, '42P16', 'customer_class must be NOT NULL');
SELECT pg_temp.refuses('T1c: a law kind in a tariff table',
  $q$SELECT public.rule_table_register('public.zz_badkey', 'tariff', 'zz_fee', '{customer_class}', '{}')$q$, '22023', 'kind zz_fee is law kind');
SELECT pg_temp.refuses('T1d: a hook of the wrong signature',
  $q$SELECT public.rule_table_register('public.zz_badkey', 'law', 'zz_fee', '{customer_class}', '{}',
                                       'public.zz_fee_insert_check(jsonb)')$q$, '42P16', 'must be (uuid) RETURNS date');
CREATE TABLE public.zz_badfacet (LIKE public.zz_fee_rules INCLUDING DEFAULTS);
ALTER TABLE public.zz_badfacet ADD PRIMARY KEY (id);
ALTER TABLE public.zz_badfacet ALTER COLUMN fee_cap TYPE numeric(4,0);
SELECT pg_temp.refuses('T1f: a template column as a facet (it would overwrite the document)',
  $q$SELECT public.rule_table_register('public.zz_badfacet', 'law', 'zz_fee', '{customer_class}', '{terms,fee_strategy}')$q$,
  '42P16', 'terms is a template or key column, never a facet');
SELECT pg_temp.refuses('T1g: a facet column of a type that rounds (numeric(4,0))',
  $q$SELECT public.rule_table_register('public.zz_badfacet', 'law', 'zz_fee', '{customer_class}', '{fee_cap}')$q$,
  '42P16', 'fee_cap is numeric(4,0)');
CREATE TABLE public.zz_badfacet2 (LIKE public.zz_fee_rules INCLUDING DEFAULTS);
ALTER TABLE public.zz_badfacet2 ADD PRIMARY KEY (id);
ALTER TABLE public.zz_badfacet2 ALTER COLUMN component_ids TYPE text;
SELECT pg_temp.refuses('T1h: a facet column of another allowed type than its facet''s (text[] facet, text column)',
  $q$SELECT public.rule_table_register('public.zz_badfacet2', 'law', 'zz_fee', '{customer_class}', '{fee_strategy,fee_cap,has_fee,component_ids,waiver_classes}')$q$,
  '42P16', 'facet component_ids is text[] but');
SELECT pg_temp.refuses('T1e: the application cannot register a table',
  $q$SELECT public.rule_table_register('public.zz_fee_rules', 'law', 'zz_fee', '{customer_class}', '{}')$q$, '42501', 'permission denied', 'tally_app', :'u1');
SELECT pg_temp.ok('T2: registration adds the exclusion, triggers (ALWAYS), grants and, for a tariff table, FORCE RLS',
  (SELECT count(*) FROM pg_constraint WHERE conrelid IN ('public.zz_fee_rules'::regclass, 'public.zz_fee_tariffs'::regclass) AND contype = 'x') = 2
  AND (SELECT count(*) FROM pg_trigger WHERE tgrelid IN ('public.zz_fee_rules'::regclass, 'public.zz_fee_tariffs'::regclass) AND tgenabled = 'A') = 6
  AND NOT has_table_privilege('tally_app', 'public.zz_fee_rules', 'INSERT') AND NOT has_table_privilege('tally_core', 'public.zz_fee_rules', 'INSERT')
  AND has_table_privilege('tally_app', 'public.zz_fee_tariffs', 'INSERT') AND NOT has_table_privilege('tally_app', 'public.zz_fee_tariffs', 'DELETE')
  AND (SELECT relforcerowsecurity FROM pg_class WHERE oid = 'public.zz_fee_tariffs'::regclass));
SELECT pg_temp.refuses('T2b: a table registers once',
  $q$SELECT public.rule_table_register('public.zz_fee_rules', 'law', 'zz_fee', '{customer_class}', '{}')$q$, '23505', 'already registered');
SELECT pg_temp.refuses('T2c: the registry is written only at registration (no edit)',
  $q$UPDATE public.rule_tables SET area_key = '{}' WHERE table_name = 'public.zz_fee_rules'::regclass$q$, '23001', 'never edited or deleted');

-- law(key, owners, systems, jurisdiction, class, from, doc): a law row (owner).
CREATE FUNCTION pg_temp.law(p_k text, p_owners text[], p_systems text[], p_juris boolean, p_class text, p_from date, p_doc jsonb,
                            p_state text DEFAULT 'ZZ', p_kind text DEFAULT 'zz_fee', p_version integer DEFAULT 1) RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE v uuid;
BEGIN
  INSERT INTO public.zz_fee_rules (state_code, service_type, owner_types, system_kinds, commission_jurisdiction, customer_class,
                                   effective_from, source_note, terms_kind, terms_version, terms_source)
  VALUES (p_state, 'gas', p_owners, p_systems, p_juris, p_class, p_from, 'law row ' || p_k, p_kind, p_version, p_doc::text)
  RETURNING id INTO v;
  INSERT INTO b17 VALUES (p_k, v);
  RETURN v;
END $$;
SELECT pg_temp.does('T3a: law rows of disjoint owner sets, and "every owner type" for another key, are written',
  $q$SELECT pg_temp.law('lr1', '{investor_owned,cooperative}', NULL, true, 'residential', DATE '2000-01-01', pg_temp.g('flat'));
     SELECT pg_temp.law('lr2', '{municipal}', NULL, NULL, 'residential', DATE '2000-01-01', pg_temp.g('delegated'));
     SELECT pg_temp.law('lr3', NULL, NULL, NULL, 'commercial', DATE '2000-01-01', jsonb_set(pg_temp.g('greater'), '{waivers}', '[]'))$q$);
SELECT pg_temp.ok('T3a: law rows of disjoint owner sets, and "every owner type" for another key, are written', pg_temp.id('lr3') IS NOT NULL);
SELECT pg_temp.ok('T3b: a row''s document, facets, spans and stamps are the trigger''s',
  (SELECT terms = pg_temp.g('flat') AND fee_strategy = 'flat' AND fee_cap = 50 AND has_fee AND component_ids = '{f1,w1}' AND waiver_classes = '{senior}'
          AND owner_span = public.rule_applicability_span('owner_type', '{investor_owned,cooperative}') AND system_span = '{[0,)}'
          AND jurisdiction_span = '[1,2)' AND recorded_txid = txid_current() AND closed_at IS NULL
     FROM public.zz_fee_rules WHERE id = pg_temp.id('lr1'))
  AND (SELECT NOT has_fee AND fee_cap IS NULL AND jurisdiction_span = '[0,2)' FROM public.zz_fee_rules WHERE id = pg_temp.id('lr2')));
SELECT pg_temp.refuses('T4a: "every owner type" overlaps "investor-owned and cooperative" for the same key and dates',
  $q$SELECT pg_temp.law('x', NULL, NULL, NULL, 'residential', DATE '2010-01-01', pg_temp.g('flat'))$q$, '23P01', 'zz_fee_rules_rule_no_overlap');
SELECT pg_temp.refuses('T4b: "municipal" overlaps "every owner type"',
  $q$SELECT pg_temp.law('x', '{municipal}', NULL, NULL, 'commercial', DATE '2010-01-01', pg_temp.g('delegated'))$q$, '23P01', 'zz_fee_rules_rule_no_overlap');
SELECT pg_temp.law('lr4', '{political_subdivision}', NULL, NULL, 'residential', DATE '2000-01-01', pg_temp.g('delegated'));
SELECT pg_temp.law('lr5', '{investor_owned}', NULL, false, 'residential', DATE '2000-01-01', jsonb_set(pg_temp.g('flat'), '{fee,cap}', '75'));
SELECT pg_temp.ok('T4c: disjoint owner sets, and the other jurisdiction status, coexist', pg_temp.id('lr4') IS NOT NULL AND pg_temp.id('lr5') IS NOT NULL);
CREATE FUNCTION pg_temp.seed_row(p_note text, p_doc jsonb, p_owners jsonb DEFAULT '["cooperative", "investor_owned"]') RETURNS jsonb
LANGUAGE sql STABLE AS $$
  SELECT jsonb_build_object('state_code', 'ZZ', 'service_type', 'gas', 'owner_types', p_owners, 'system_kinds', NULL, 'commission_jurisdiction', true,
                            'effective_to', NULL,
                            'customer_class', 'residential', 'effective_from', '2000-01-01', 'source_note', p_note,
                            'terms_kind', 'zz_fee', 'terms_version', 1, 'terms_source', p_doc::text)
$$;
SELECT pg_temp.ok_sql('T4d: a seed of an existing row (owner types in another order) is the same row, not a new one',
  $q$SELECT public.rule_row_seed('public.zz_fee_rules', pg_temp.seed_row('law row lr1', pg_temp.g('flat'))) = pg_temp.id('lr1')$q$);
SELECT pg_temp.refuses('T4e: a seed whose document differs raises — never an upsert, never a silent skip',
  $q$SELECT public.rule_row_seed('public.zz_fee_rules', pg_temp.seed_row('law row lr1', jsonb_set(pg_temp.g('flat'), '{fee,cap}', '55')))$q$,
  '23505', 'with a different terms');
SELECT pg_temp.refuses('T4f: … and one whose citation differs',
  $q$SELECT public.rule_row_seed('public.zz_fee_rules', pg_temp.seed_row('law row lr1 (amended note)', pg_temp.g('flat')))$q$,
  '23505', 'with a different source_note');
INSERT INTO b17 VALUES ('seeded', public.rule_row_seed('public.zz_fee_rules', pg_temp.seed_row('law row seeded', pg_temp.g('flat'), '["special_district"]')));
SELECT pg_temp.ok('T4g: a seed of a new row inserts it through the same trigger',
  (SELECT has_fee AND fee_cap = 50 AND owner_span = public.rule_applicability_span('owner_type', '{special_district}')
     FROM public.zz_fee_rules WHERE id = pg_temp.id('seeded')));
CREATE FUNCTION pg_temp.seed_lr3(p_field text, p_value jsonb) RETURNS jsonb
LANGUAGE sql STABLE AS $$
  SELECT jsonb_set(jsonb_build_object('state_code', 'ZZ', 'service_type', 'gas', 'owner_types', NULL, 'system_kinds', NULL,
                                      'commission_jurisdiction', NULL, 'effective_to', NULL, 'customer_class', 'commercial',
                                      'effective_from', '2000-01-01', 'source_note', 'law row lr3',
                                      'terms_kind', 'zz_fee', 'terms_version', 1,
                                      'terms_source', jsonb_set(pg_temp.g('greater'), '{waivers}', '[]')::text),
                   ARRAY[p_field], p_value)
$$;
SELECT pg_temp.ok_sql('T4n0: lr3 (every owner, every system) re-seeds as itself with its own envelope',
  $q$SELECT public.rule_row_seed('public.zz_fee_rules', pg_temp.seed_lr3('effective_to', 'null')) = pg_temp.id('lr3')$q$);
SELECT pg_temp.refuses('T4n1: … a scalar where owner_types belongs is not read as "every owner"',
  $q$SELECT public.rule_row_seed('public.zz_fee_rules', pg_temp.seed_lr3('owner_types', '"municipal"'))$q$,
  '22023', 'null (every one) or an array of strings');
SELECT pg_temp.refuses('T4n2: … nor an object where system_kinds belongs',
  $q$SELECT public.rule_row_seed('public.zz_fee_rules', pg_temp.seed_lr3('system_kinds', '{}'))$q$,
  '22023', 'null (every one) or an array of strings');
SELECT pg_temp.refuses('T4n3: … nor a string where commission_jurisdiction belongs',
  $q$SELECT public.rule_row_seed('public.zz_fee_rules', pg_temp.seed_lr3('commission_jurisdiction', '"true"'))$q$,
  '22023', 'null (every one) or an array of strings');
SELECT pg_temp.refuses('T4n4: … nor an owner type that is not a string',
  $q$SELECT public.rule_row_seed('public.zz_fee_rules', pg_temp.seed_lr3('owner_types', '[5]'))$q$,
  '22023', 'null (every one) or an array of strings');
SELECT pg_temp.refuses('T4n5: … nor a system kind that is not a string',
  $q$SELECT public.rule_row_seed('public.zz_fee_rules', pg_temp.seed_lr3('system_kinds', '[["distribution"]]'))$q$,
  '22023', 'null (every one) or an array of strings');
SELECT pg_temp.refuses('T4h: the application seeds nothing',
  format($q$SELECT public.rule_row_seed('public.zz_fee_rules', %L)$q$, pg_temp.seed_row('x', pg_temp.g('flat'))), '42501', 'permission denied for function rule_row_seed', 'tally_app', :'u1');
SELECT pg_temp.refuses('T4i: a seed naming a column the table lacks (a misspelt end would store the row open-ended)',
  $q$SELECT public.rule_row_seed('public.zz_fee_rules', pg_temp.seed_row('law row lr1', pg_temp.g('flat')) || '{"effective_too": "2030-01-01"}')$q$,
  '42703', 'has no column effective_too');
SELECT pg_temp.refuses('T4j: a seed whose end differs from the stored row',
  $q$SELECT public.rule_row_seed('public.zz_fee_rules', pg_temp.seed_row('law row lr1', pg_temp.g('flat')) || '{"effective_to": "2030-01-01"}')$q$,
  '23505', 'with a different effective_to');
SELECT pg_temp.refuses('T4k: a re-seed naming another column with a different value (a facet) raises too',
  $q$SELECT public.rule_row_seed('public.zz_fee_rules', pg_temp.seed_row('law row lr1', pg_temp.g('flat')) || '{"has_fee": false}')$q$,
  '23505', 'with a different has_fee');
SELECT pg_temp.refuses('T4l: a seed that names an id, or leaves part of the envelope out',
  $q$SELECT public.rule_row_seed('public.zz_fee_rules', pg_temp.seed_row('law row lr1', pg_temp.g('flat')) || jsonb_build_object('id', pg_temp.id('lr2')))$q$,
  '22023', 'and no id');
SELECT pg_temp.refuses('T4m: … or leaves part of the envelope out (source_note)',
  $q$SELECT public.rule_row_seed('public.zz_fee_rules', pg_temp.seed_row('law row lr1', pg_temp.g('flat')) - 'source_note')$q$,
  '22023', 'names the whole envelope');
SELECT pg_temp.refuses('T5a: an owner type not in the vocabulary',
  $q$SELECT pg_temp.law('x', '{city}', NULL, NULL, 'industrial', DATE '2000-01-01', pg_temp.g('delegated'))$q$, '23503', 'owner_type city');
SELECT pg_temp.refuses('T5b: an empty owner set (NULL is "every one"; empty is nothing)',
  $q$SELECT pg_temp.law('x', '{}', NULL, NULL, 'industrial', DATE '2000-01-01', pg_temp.g('delegated'))$q$, '23514', 'non-empty');
SELECT pg_temp.refuses('T5c: a repeated owner type',
  $q$SELECT pg_temp.law('x', '{municipal,municipal}', NULL, NULL, 'industrial', DATE '2000-01-01', pg_temp.g('delegated'))$q$, '23514', 'without blanks or repeats');
SELECT pg_temp.refuses('T5d: a system kind not of the row''s service',
  $q$INSERT INTO public.zz_fee_rules (state_code, service_type, system_kinds, customer_class, effective_from, source_note, terms_kind, terms_version, terms_source)
     VALUES ('ZZ', 'water', '{piped_propane_distribution}', 'industrial', DATE '2000-01-01', 'x', 'zz_fee', 1, pg_temp.g('delegated')::text)$q$,
  '23514', 'is not a kind of water system');
SELECT pg_temp.refuses('T5e: a state that is not a known state (no state place)',
  $q$SELECT pg_temp.law('x', NULL, NULL, NULL, 'industrial', DATE '2000-01-01', pg_temp.g('delegated'), 'QQ')$q$, '23503', 'QQ is not a known state');
SELECT pg_temp.refuses('T6a: a document that fails its schema',
  $q$SELECT pg_temp.law('x', NULL, NULL, NULL, 'industrial', DATE '2000-01-01', jsonb_set(pg_temp.g('flat'), '{fee,cap}', '"lots"'))$q$,
  '23514', '/fee/cap: expected a number');
SELECT pg_temp.refuses('T6b: a document with a duplicate key (written as text)',
  $q$INSERT INTO public.zz_fee_rules (state_code, service_type, customer_class, effective_from, source_note, terms_kind, terms_version, terms_source)
     VALUES ('ZZ', 'gas', 'industrial', DATE '2000-01-01', 'x', 'zz_fee', 1,
             '{"governs": "delegated_to_utility", "citation": "ZZ 9", "citation": "ZZ 10"}')$q$, '22030', 'repeats a key');
SELECT pg_temp.refuses('T6c: terms set by the writer that differ from terms_source',
  $q$INSERT INTO public.zz_fee_rules (state_code, service_type, customer_class, effective_from, source_note, terms_kind, terms_version, terms_source, terms)
     VALUES ('ZZ', 'gas', 'industrial', DATE '2000-01-01', 'x', 'zz_fee', 1, pg_temp.g('delegated')::text, '{"governs": "law"}')$q$,
  '23514', 'terms is derived from terms_source');
SELECT pg_temp.refuses('T6d: a facet set by the writer that the document does not give',
  $q$INSERT INTO public.zz_fee_rules (state_code, service_type, customer_class, effective_from, source_note, terms_kind, terms_version, terms_source, has_fee)
     VALUES ('ZZ', 'gas', 'industrial', DATE '2000-01-01', 'x', 'zz_fee', 1, pg_temp.g('delegated')::text, true)$q$,
  '23514', 'is a facet, derived from the document');
SELECT pg_temp.refuses('T6e: another kind''s document in the table',
  $q$INSERT INTO public.zz_fee_rules (state_code, service_type, customer_class, effective_from, source_note, terms_kind, terms_version, terms_source)
     VALUES ('ZZ', 'gas', 'industrial', DATE '2000-01-01', 'x', 'zz_fee_tariff', 1, pg_temp.g('tariff')::text)$q$, '23514', 'holds zz_fee documents');
SELECT pg_temp.refuses('T6f: a version that does not exist',
  $q$SELECT pg_temp.law('x', NULL, NULL, NULL, 'industrial', DATE '2000-01-01', pg_temp.g('delegated'), 'ZZ', 'zz_fee', 9)$q$, '23503', 'is not a registered term schema');
SELECT pg_temp.refuses('T6g: a frozen version',
  $q$SELECT pg_temp.law('x', NULL, NULL, NULL, 'industrial', DATE '2000-01-01', pg_temp.g('delegated'), 'ZZ', 'zz_fee', 2)$q$, '23514', 'is frozen');
SELECT pg_temp.refuses('T6h: a waiver class not in the vocabulary — a misspelling reaches no one',
  $q$SELECT pg_temp.law('x', NULL, NULL, NULL, 'industrial', DATE '2000-01-01',
       jsonb_set(pg_temp.g('flat'), '{waivers,0,class}', '"senoir"'))$q$, '23503', 'names senoir');
SELECT pg_temp.refuses('T6i: a waiver class of another state (the vocabulary is scoped by the row''s state)',
  $q$SELECT pg_temp.law('x', NULL, NULL, NULL, 'industrial', DATE '2000-01-01',
       jsonb_set(pg_temp.g('flat'), '{waivers,0,class}', '"tx_only"'))$q$, '23503', 'names tx_only');
SELECT pg_temp.refuses('T6j: the area''s insert check (waivers reach residential only)',
  $q$SELECT pg_temp.law('x', NULL, NULL, NULL, 'industrial', DATE '2000-01-01', pg_temp.g('flat'))$q$, '23514', 'residential customers only');
SELECT pg_temp.reg('zz_fee', 3, 'law', pg_temp.s('fee'));
SELECT pg_temp.refuses('T6k: a version that declares other facets than the table has (v3 declares none)',
  $q$SELECT pg_temp.law('x', NULL, NULL, NULL, 'industrial', DATE '2000-01-01', pg_temp.g('delegated'), 'ZZ', 'zz_fee', 3)$q$, '42P16', 'declares facets {}');
SELECT pg_temp.refuses('R8c: a freeze that rewrites a number''s text (0 as 0.0) — the hash would no longer be of the stored schema',
  $q$UPDATE public.rule_term_schemas SET accepts_new_rows = false, json_schema = jsonb_set(json_schema, '{$defs,fee_flat,properties,cap,minimum}', '0.0')
     WHERE terms_kind = 'zz_fee' AND terms_version = 3$q$, '23001', 'the one change is a freeze');
SELECT pg_temp.refuses('T7a: the application cannot write a law row',
  format($q$INSERT INTO public.zz_fee_rules (state_code, service_type, customer_class, effective_from, source_note, terms_kind, terms_version, terms_source)
     VALUES ('ZZ', 'gas', 'industrial', DATE '2000-01-01', 'x', 'zz_fee', 1, %L)$q$, pg_temp.g('delegated')::text), '42501', 'permission denied', 'tally_app', :'u1');
SELECT pg_temp.refuses('T7b: a law row is never edited',
  format($q$UPDATE public.zz_fee_rules SET source_note = 'x' WHERE id = %L$q$, pg_temp.id('lr3')), '23001', 'never edited');
SELECT pg_temp.refuses('T7c: a close that carries an edit',
  format($q$UPDATE public.zz_fee_rules SET effective_to = DATE '2030-01-01', terms_source = '{}' WHERE id = %L$q$, pg_temp.id('lr3')), '23001', 'never edited');
SELECT pg_temp.refuses('T7d: a law row is never deleted',
  format($q$DELETE FROM public.zz_fee_rules WHERE id = %L$q$, pg_temp.id('lr3')), '23001', 'never deleted');
SELECT pg_temp.refuses('T7e: a rule table is never truncated',
  $q$TRUNCATE public.zz_fee_rules CASCADE$q$, '23001', 'never truncated');
CREATE ROLE zz_migrator NOLOGIN NOSUPERUSER NOBYPASSRLS;
GRANT SELECT, UPDATE ON public.zz_fee_rules TO zz_migrator;
GRANT SELECT ON public.zz_charges, public.rule_tables TO zz_migrator;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO zz_migrator;
SELECT pg_temp.refuses('T7f: a law row is closed only by a role that sees every tenant',
  format($q$UPDATE public.zz_fee_rules SET effective_to = DATE '2030-01-01' WHERE id = %L$q$, pg_temp.id('lr3')),
  '42501', 'only by a role that sees every tenant', 'zz_migrator');
UPDATE public.zz_fee_rules SET effective_to = DATE '2030-01-01' WHERE id = pg_temp.id('lr3');
SELECT pg_temp.ok('T8: a close is stamped', (SELECT effective_to = DATE '2030-01-01' AND closed_at IS NOT NULL AND closed_by = session_user
                                                FROM public.zz_fee_rules WHERE id = pg_temp.id('lr3')));
SELECT pg_temp.refuses('T8c: a close that rewrites a number''s scale (fee_cap 75 as 75.000) is an edit',
  format($q$UPDATE public.zz_fee_rules SET effective_to = DATE '2030-01-01', fee_cap = 75.000 WHERE id = %L$q$, pg_temp.id('lr5')), '23001', 'never edited');
SELECT pg_temp.refuses('T8b: a closed row does not close again',
  format($q$UPDATE public.zz_fee_rules SET effective_to = DATE '2031-01-01' WHERE id = %L$q$, pg_temp.id('lr3')), '23001', 'never edited');


-- ============================================================ L. lookups
SELECT pg_temp.ok_sql('L1: a city-owned utility''s residential law is the delegated row, an investor-owned one''s the cap; commercial law binds both', format($q$SELECT
  public.rule_law_row_as_of('public.zz_fee_rules', %1$L, 'gas', 'distribution', 'ZZ', '{"customer_class": "residential"}', DATE '2020-01-01') = pg_temp.id('lr2')
  AND public.rule_law_row_as_of('public.zz_fee_rules', %2$L, 'gas', 'distribution', 'ZZ', '{"customer_class": "residential"}', DATE '2020-01-01') = pg_temp.id('lr1')
  AND public.rule_law_row_as_of('public.zz_fee_rules', %2$L, 'gas', 'distribution', 'ZZ', '{"customer_class": "commercial"}', DATE '2020-01-01') = pg_temp.id('lr3')
  AND public.rule_law_row_as_of('public.zz_fee_rules', %1$L, 'gas', 'distribution', 'ZZ', '{"customer_class": "commercial"}', DATE '2020-01-01') = pg_temp.id('lr3')$q$, :'t1', :'t2'));
SELECT pg_temp.refuses('L2a: no law for the key — unknown law is not permission',
  format($q$SELECT public.rule_law_row_as_of('public.zz_fee_rules', %L, 'gas', 'distribution', 'ZZ', '{"customer_class": "industrial"}', DATE '2020-01-01')$q$, :'t2'),
  'P0002', 'unknown law is not permission');
SELECT pg_temp.refuses('L2b: no law on the date (the commercial row closed in 2030)',
  format($q$SELECT public.rule_law_row_as_of('public.zz_fee_rules', %L, 'gas', 'distribution', 'ZZ', '{"customer_class": "commercial"}', DATE '2030-01-01')$q$, :'t2'),
  'P0002', 'unknown law is not permission');
SELECT pg_temp.refuses('L2c: no profile — who owns the utility decides the law',
  format($q$SELECT public.rule_law_row_as_of('public.zz_fee_rules', %L, 'gas', 'distribution', 'ZZ', '{"customer_class": "residential"}', DATE '1999-12-31')$q$, :'t2'),
  'P0002', 'no utility profile is recorded');
SELECT pg_temp.refuses('L2d: a key that is not the table''s key',
  format($q$SELECT public.rule_law_row_as_of('public.zz_fee_rules', %L, 'gas', 'distribution', 'ZZ', '{"class": "residential"}', DATE '2020-01-01')$q$, :'t2'),
  '22023', 'names exactly {customer_class}');
SELECT pg_temp.refuses('L2e: a blank key value',
  format($q$SELECT public.rule_law_row_as_of('public.zz_fee_rules', %L, 'gas', 'distribution', 'ZZ', '{"customer_class": " "}', DATE '2020-01-01')$q$, :'t2'),
  '22023', 'each a non-blank string');
SELECT pg_temp.refuses('L2f: the law lookup on a tariff table',
  format($q$SELECT public.rule_law_row_as_of('public.zz_fee_tariffs', %L, 'gas', 'distribution', 'ZZ', '{"customer_class": "residential"}', DATE '2020-01-01')$q$, :'t2'),
  '22023', 'is not a law table');


-- ============================================================ U. tariffs against the law
CREATE FUNCTION pg_temp.tariff_sql(p_tenant text, p_class text, p_from date, p_amount numeric, p_to date DEFAULT NULL) RETURNS text
LANGUAGE sql STABLE AS $$
  SELECT format($q$INSERT INTO public.zz_fee_tariffs (tenant_id, state_code, service_type, system_kind, customer_class, effective_from, effective_to,
                                                    tariff_reference, terms_kind, terms_version, terms_source)
                   VALUES (%L, 'ZZ', 'gas', 'distribution', %L, %L, %L, 'Ord. 2020-7 §3', 'zz_fee_tariff', 1, %L)$q$,
                p_tenant, p_class, p_from, p_to, jsonb_set(pg_temp.g('tariff'), '{fee,amount}', to_jsonb(p_amount))::text)
$$;
SELECT pg_temp.run(pg_temp.tariff_sql(:'t1', 'residential', DATE '2020-01-01', 999), 'tally_app', :'u1');
INSERT INTO b17 SELECT 't1tar', id FROM public.zz_fee_tariffs WHERE tenant_id = :'t1';
SELECT pg_temp.ok('U1: under the delegated law a city sets any fee; the row is stamped with its writer',
  (SELECT tariff_amount = 999 AND created_by = :'u1'::uuid AND component_ids = '{t1}' FROM public.zz_fee_tariffs WHERE id = pg_temp.id('t1tar')));
SELECT pg_temp.refuses('U2a: an investor-owned utility''s fee above the law''s cap is looser than the law',
  pg_temp.tariff_sql(:'t2', 'residential', DATE '2020-01-01', 60), '23514', 'fee 60 above the cap 50 of law row lr1', 'tally_app', :'u2');
SELECT pg_temp.run(pg_temp.tariff_sql(:'t2', 'residential', DATE '2020-01-01', 40), 'tally_app', :'u2');
INSERT INTO b17 SELECT 't2tar', id FROM public.zz_fee_tariffs WHERE tenant_id = :'t2';
SELECT pg_temp.ok('U2b: at or under the cap, accepted', pg_temp.id('t2tar') IS NOT NULL);
SELECT pg_temp.refuses('U3a: a tariff over days with no profile',
  pg_temp.tariff_sql(:'t2', 'commercial', DATE '1999-01-01', 1, DATE '2000-06-01'), 'P0002', 'has no profile', 'tally_app', :'u2');
SELECT pg_temp.refuses('U3b: a tariff over days no law covers (the commercial row ends 2030)',
  pg_temp.tariff_sql(:'t2', 'commercial', DATE '2020-01-01', 1), 'P0002', 'no law is known', 'tally_app', :'u2');
SELECT pg_temp.refuses('U3c: another tenant''s tariff (that utility''s profile is not visible)',
  pg_temp.tariff_sql(:'t2', 'industrial', DATE '2020-01-01', 1), 'P0002', 'has no profile', 'tally_app', :'u1');
SELECT pg_temp.refuses('U4a: two tariffs over one range for one key',
  pg_temp.tariff_sql(:'t2', 'residential', DATE '2021-01-01', 30), '23P01', 'zz_fee_tariffs_rule_no_overlap', 'tally_app', :'u2');
SELECT pg_temp.refuses('U4b: a tariff row is never deleted',
  format($q$DELETE FROM public.zz_fee_tariffs WHERE id = %L$q$, pg_temp.id('t2tar')), '42501', 'permission denied', 'tally_app', :'u2');
SELECT pg_temp.refuses('U4c: nor edited',
  format($q$UPDATE public.zz_fee_tariffs SET tariff_reference = 'x' WHERE id = %L$q$, pg_temp.id('t2tar')), '23001', 'never edited', 'tally_app', :'u2');
SELECT pg_temp.ok('U5: a tariff lookup — the utility''s row, or NULL when it has none, never another tenant''s',
  public.rule_tariff_row_as_of('public.zz_fee_tariffs', :'t2', 'gas', 'distribution', 'ZZ', '{"customer_class": "residential"}', DATE '2022-01-01') = pg_temp.id('t2tar')
  AND public.rule_tariff_row_as_of('public.zz_fee_tariffs', :'t2', 'gas', 'distribution', 'ZZ', '{"customer_class": "commercial"}', DATE '2022-01-01') IS NULL);
CREATE TEMP TABLE u5 (id uuid);
GRANT INSERT ON u5 TO tally_app;
SELECT pg_temp.run(format($q$INSERT INTO u5 SELECT public.rule_tariff_row_as_of('public.zz_fee_tariffs', %L, 'gas', 'distribution', 'ZZ',
                      '{"customer_class": "residential"}', DATE '2022-01-01')$q$, :'t2'), 'tally_app', :'u1');
SELECT pg_temp.ok('U5b: … another tenant''s row is not found', (SELECT count(*) = 1 AND bool_and(id IS NULL) FROM u5));


-- ============================================================ C. citations and the close floor
-- charge_sql(tenant, class, rule, tariff, component, date, amount): a charge
-- as the application records it, citing the law row (and the tariff row).
CREATE FUNCTION pg_temp.charge_sql(p_tenant text, p_class text, p_rule uuid, p_tariff uuid, p_component text, p_on date, p_amount numeric) RETURNS text
LANGUAGE sql STABLE AS $$
  SELECT format($q$INSERT INTO public.zz_charges (tenant_id, state_code, service_type, system_kind, customer_class, rule_id, tariff_id, fee_component, charged_on, amount)
                   VALUES (%L, 'ZZ', 'gas', 'distribution', %L, %L, %L, %L, %L, %L)$q$, p_tenant, p_class, p_rule, p_tariff, p_component, p_on, p_amount)
$$;
SELECT pg_temp.run(pg_temp.charge_sql(:'t2', 'residential', pg_temp.id('lr1'), pg_temp.id('t2tar'), 't1', DATE '2024-03-01', 40), 'tally_app', :'u2');
SELECT pg_temp.run(pg_temp.charge_sql(:'t1', 'residential', pg_temp.id('lr2'), pg_temp.id('t1tar'), 't1', DATE '2024-03-01', 999), 'tally_app', :'u1');
INSERT INTO b17 SELECT 'ch2', id FROM public.zz_charges WHERE tenant_id = :'t2';
INSERT INTO b17 SELECT 'ch1', id FROM public.zz_charges WHERE tenant_id = :'t1';
SELECT pg_temp.ok('C1: a record cites its utility''s law row, its tariff row and the component that governed', pg_temp.id('ch1') IS NOT NULL AND pg_temp.id('ch2') IS NOT NULL);
SELECT pg_temp.refuses('C2a: a citation of a row not in force on the date',
  pg_temp.charge_sql(:'t2', 'residential', pg_temp.id('lr1'), NULL, 'f1', DATE '1999-01-01', 1), '23514', 'is not in force on 1999-01-01', 'tally_app', :'u2');
SELECT pg_temp.refuses('C2b: a citation of another tenant''s tariff row (not visible)',
  pg_temp.charge_sql(:'t2', 'residential', pg_temp.id('lr1'), pg_temp.id('t1tar'), 't1', DATE '2024-03-01', 1), '23503', 'or it is not visible', 'tally_app', :'u2');
SELECT pg_temp.refuses('C2c: a city-owned utility citing the investor-owned law row in force that day — not its law',
  pg_temp.charge_sql(:'t1', 'residential', pg_temp.id('lr1'), NULL, 'f1', DATE '2024-03-01', 1), '23514', 'is not the law for this utility', 'tally_app', :'u1');
SELECT pg_temp.refuses('C2d: a citation of the law row for another key (commercial law for a residential charge)',
  pg_temp.charge_sql(:'t2', 'residential', pg_temp.id('lr3'), NULL, 'f2', DATE '2024-03-01', 1), '23514', 'is not the law for this utility', 'tally_app', :'u2');
SELECT pg_temp.refuses('C2e: a component the governing row does not have (F7)',
  pg_temp.charge_sql(:'t2', 'residential', pg_temp.id('lr1'), NULL, 'p9', DATE '2024-03-01', 1), '23514', 'is not a component of the row that governed', 'tally_app', :'u2');
SELECT pg_temp.refuses('C2g: under delegated law with no tariff there is no component to charge (no policy recorded)',
  pg_temp.charge_sql(:'t1', 'residential', pg_temp.id('lr2'), NULL, 'f1', DATE '2024-03-01', 1), '23514', 'is not a component of the row that governed', 'tally_app', :'u1');
SELECT pg_temp.refuses('C2f: a citing record is never edited (its citation would escape the guard)',
  format($q$UPDATE public.zz_charges SET rule_id = %L WHERE id = %L$q$, pg_temp.id('lr3'), pg_temp.id('ch2')), '42501', 'permission denied', 'tally_app', :'u2');
SELECT pg_temp.refuses('C3a: a law row cannot close on or before a citing record''s date',
  format($q$UPDATE public.zz_fee_rules SET effective_to = DATE '2024-03-01' WHERE id = %L$q$, pg_temp.id('lr1')), '23514', 'needs it in force on 2024-03-01');
UPDATE public.zz_fee_rules SET effective_to = DATE '2024-03-02' WHERE id = pg_temp.id('lr1');
SELECT pg_temp.ok('C3b: … and closes the day after', (SELECT effective_to = DATE '2024-03-02' FROM public.zz_fee_rules WHERE id = pg_temp.id('lr1')));
SELECT pg_temp.refuses('C4a: a tariff row cannot close under its citing record either (the utility closes it)',
  format($q$UPDATE public.zz_fee_tariffs SET effective_to = DATE '2024-02-01' WHERE id = %L$q$, pg_temp.id('t1tar')),
  '23514', 'needs it in force on 2024-03-01', 'tally_app', :'u1');
SELECT pg_temp.run(format($q$UPDATE public.zz_fee_tariffs SET effective_to = DATE '2025-01-01' WHERE id = %L$q$, pg_temp.id('t1tar')), 'tally_app', :'u1');
SELECT pg_temp.ok('C4b: a utility closes its own tariff row; the close is stamped with the user',
  (SELECT effective_to = DATE '2025-01-01' AND closed_by = :'u1'::uuid AND closed_at IS NOT NULL FROM public.zz_fee_tariffs WHERE id = pg_temp.id('t1tar')));
SELECT pg_temp.run(format($q$UPDATE public.zz_fee_tariffs SET effective_to = DATE '2026-01-01' WHERE id = %L$q$, pg_temp.id('t2tar')), 'tally_app', :'u1');
SELECT pg_temp.ok('C4c: another tenant''s tariff row is not closed (not visible)',
  (SELECT effective_to IS NULL FROM public.zz_fee_tariffs WHERE id = pg_temp.id('t2tar')));


-- ============================================================ A. adopting pre-convention rows
CREATE TABLE public.zz_legacy_rules (
  id uuid DEFAULT public.uuid_generate_v4() PRIMARY KEY,
  state_code text NOT NULL, service_type text NOT NULL,
  owner_types text[], system_kinds text[], commission_jurisdiction boolean,
  owner_span int4multirange NOT NULL DEFAULT '{[0,)}', system_span int4multirange NOT NULL DEFAULT '{[0,)}',
  jurisdiction_span int4range NOT NULL DEFAULT '[0,2)',
  customer_class text NOT NULL,
  effective_from date NOT NULL, effective_to date,
  source_note text NOT NULL,
  legacy_cap numeric,
  terms_kind text, terms_version integer, terms_source text, terms jsonb,
  fee_strategy text, fee_cap numeric, has_fee boolean, component_ids text[], waiver_classes text[],
  created_at timestamptz NOT NULL DEFAULT now(), recorded_txid bigint, closed_at timestamptz, closed_by text);
INSERT INTO public.zz_legacy_rules (id, state_code, service_type, customer_class, effective_from, source_note, legacy_cap) VALUES
  ('00000000-0000-4000-8000-0000000017e1', 'ZZ', 'gas', 'residential', DATE '2004-07-12', 'legacy row 1', 50),
  ('00000000-0000-4000-8000-0000000017e2', 'ZZ', 'gas', 'commercial', DATE '2004-07-12', 'legacy row 2', 500);
-- A legacy row whose stored span disagrees with its owner types.
INSERT INTO public.zz_legacy_rules (id, state_code, service_type, owner_types, customer_class, effective_from, source_note) VALUES
  ('00000000-0000-4000-8000-0000000017e3', 'ZZ', 'gas', '{municipal}', 'industrial', DATE '2004-07-12', 'legacy row 3');
SELECT pg_temp.refuses('A1a: only a law table holds pre-convention rows',
  $q$SELECT public.rule_table_register('public.zz_legacy_rules', 'tariff', 'zz_fee_tariff', '{customer_class}', '{}', NULL, NULL, NULL, NULL, 'public.zz_fee_insert_check(jsonb)')$q$,
  '22023', 'only a law table');
-- The adopting area's adoption check, run only when an empty document is
-- filled: the document says what the old column said (inventory §4 A) — the
-- cap the facet gives is the legacy cap.
CREATE FUNCTION public.zz_legacy_check(p_row jsonb) RETURNS void LANGUAGE plpgsql SET search_path = public, pg_temp AS $$
BEGIN
  IF (p_row ->> 'legacy_cap')::numeric IS DISTINCT FROM (p_row ->> 'fee_cap')::numeric THEN
    RAISE EXCEPTION 'zz: the document''s cap % is not the legacy cap %', p_row ->> 'fee_cap', p_row ->> 'legacy_cap' USING ERRCODE = 'check_violation';
  END IF;
END $$;
SELECT pg_temp.refuses('A1c: an adoption check of the wrong signature',
  $q$SELECT public.rule_table_register('public.zz_legacy_rules', 'law', 'zz_fee', '{customer_class}',
                                       '{fee_strategy,fee_cap,has_fee,component_ids,waiver_classes}', NULL, NULL, NULL, NULL, 'public.zz_fee_floor(uuid)')$q$,
  '42P16', 'must be (jsonb) RETURNS void');
UPDATE public.zz_legacy_rules SET terms_kind = 'zz_fee', terms_version = 1, terms_source = '{}', terms = '{}' WHERE id = '00000000-0000-4000-8000-0000000017e2';
SELECT pg_temp.refuses('A1e: an adopting table holding a filled document (never validated nor compared)',
  $q$SELECT public.rule_table_register('public.zz_legacy_rules', 'law', 'zz_fee', '{customer_class}',
                                       '{fee_strategy,fee_cap,has_fee,component_ids,waiver_classes}', NULL, NULL, NULL, NULL, 'public.zz_legacy_check(jsonb)')$q$,
  '42P16', 'whose document is already filled');
UPDATE public.zz_legacy_rules SET terms_kind = NULL, terms_version = NULL, terms_source = NULL, terms = NULL WHERE id = '00000000-0000-4000-8000-0000000017e2';
SELECT pg_temp.refuses('A1d: a table that already holds rows registers only as adopting them',
  $q$SELECT public.rule_table_register('public.zz_legacy_rules', 'law', 'zz_fee', '{customer_class}',
                                       '{fee_strategy,fee_cap,has_fee,component_ids,waiver_classes}', NULL, 'public.zz_legacy_check(jsonb)')$q$,
  '42P16', 'already holds rows');
SELECT public.rule_table_register('public.zz_legacy_rules', 'law', 'zz_fee', '{customer_class}',
                                  '{fee_strategy,fee_cap,has_fee,component_ids,waiver_classes}', NULL, NULL, NULL, NULL, 'public.zz_legacy_check(jsonb)');
SELECT pg_temp.ok('A1b: a law table with pre-convention rows registers; its empty documents stand', (SELECT count(*) FROM public.zz_legacy_rules WHERE terms IS NULL) = 3);
UPDATE public.zz_legacy_rules SET terms_kind = 'zz_fee', terms_version = 1, terms_source = pg_temp.g('flat')::text
 WHERE id = '00000000-0000-4000-8000-0000000017e1';
SELECT pg_temp.ok('A2: adoption fills the document and facets once; id, key, dates and stamps unchanged',
  (SELECT terms = pg_temp.g('flat') AND fee_cap = 50 AND waiver_classes = '{senior}' AND effective_from = DATE '2004-07-12' AND source_note = 'legacy row 1'
     FROM public.zz_legacy_rules WHERE id = '00000000-0000-4000-8000-0000000017e1'));
SELECT pg_temp.refuses('A3a: a second fill is an edit',
  $q$UPDATE public.zz_legacy_rules SET terms_source = jsonb_set(terms, '{fee,cap}', '40')::text WHERE id = '00000000-0000-4000-8000-0000000017e1'$q$,
  '23001', 'never edited');
SELECT pg_temp.refuses('A3b: a fill that changes anything else',
  $q$UPDATE public.zz_legacy_rules SET terms_kind = 'zz_fee', terms_version = 1, terms_source = (SELECT d::text FROM good WHERE k = 'greater'), source_note = 'x'
     WHERE id = '00000000-0000-4000-8000-0000000017e2'$q$, '23001', 'changes only its document and facets');
SELECT pg_temp.refuses('A3c: a fill that fails the schema',
  $q$UPDATE public.zz_legacy_rules SET terms_kind = 'zz_fee', terms_version = 1, terms_source = '{"governs": "law"}' WHERE id = '00000000-0000-4000-8000-0000000017e2'$q$,
  '23514', '/citation: required');
GRANT SELECT, UPDATE ON public.zz_legacy_rules TO zz_migrator;
SELECT pg_temp.refuses('A3d: a fill by a role that does not see every tenant',
  $q$UPDATE public.zz_legacy_rules SET terms_kind = 'zz_fee', terms_version = 1, terms_source = '{"governs": "delegated_to_utility", "citation": "ZZ 9"}'
     WHERE id = '00000000-0000-4000-8000-0000000017e2'$q$, '42501', 'a reviewed migration''s act', 'zz_migrator');
SELECT pg_temp.refuses('A3e: a fill that would move the row''s applicability (its stored span disagrees)',
  $q$UPDATE public.zz_legacy_rules SET terms_kind = 'zz_fee', terms_version = 1, terms_source = '{"governs": "delegated_to_utility", "citation": "ZZ 9"}'
     WHERE id = '00000000-0000-4000-8000-0000000017e3'$q$, '23514', 'stored spans do not match');
SELECT pg_temp.refuses('A3h: a schema-valid document that says something else than the old columns (delegation for a 500 cap)',
  $q$UPDATE public.zz_legacy_rules SET terms_kind = 'zz_fee', terms_version = 1, terms_source = '{"governs": "delegated_to_utility", "citation": "ZZ 9"}'
     WHERE id = '00000000-0000-4000-8000-0000000017e2'$q$, '23514', 'is not the legacy cap 500');
UPDATE public.zz_legacy_rules SET terms_kind = 'zz_fee', terms_version = 1, terms_source = jsonb_set(pg_temp.g('greater'), '{waivers}', '[]')::text
 WHERE id = '00000000-0000-4000-8000-0000000017e2';
SELECT pg_temp.ok('A3i: … and the document that says what the old columns said is adopted',
  (SELECT fee_cap = 500 AND fee_strategy = 'greater_of' FROM public.zz_legacy_rules WHERE id = '00000000-0000-4000-8000-0000000017e2'));
SELECT pg_temp.does('A4: after adoption a new row is written normally — the adoption check runs only when a document is filled',
  $q$INSERT INTO b17 VALUES ('a4', public.rule_row_seed('public.zz_legacy_rules', jsonb_build_object('state_code', 'ZZ', 'service_type', 'gas', 'customer_class', 'other',
     'owner_types', NULL, 'system_kinds', NULL, 'commission_jurisdiction', NULL, 'effective_to', NULL,
     'effective_from', '2020-01-01', 'source_note', 'a row written after adoption', 'terms_kind', 'zz_fee', 'terms_version', 1,
     'terms_source', jsonb_set(pg_temp.g('greater'), '{waivers}', '[]')::text)))$q$);
SELECT pg_temp.ok('A4: after adoption a new row is written normally — the adoption check runs only when a document is filled',
  (SELECT fee_cap = 500 AND legacy_cap IS NULL FROM public.zz_legacy_rules WHERE id = pg_temp.id('a4')));
SELECT pg_temp.refuses('A3f: a new row in an adopting table still needs its document',
  $q$INSERT INTO public.zz_legacy_rules (state_code, service_type, customer_class, effective_from, source_note) VALUES ('ZZ', 'gas', 'other', DATE '2020-01-01', 'x')$q$,
  '23502', 'a rule document is required');
SELECT pg_temp.refuses('A3g: a half-filled document (kind without source)',
  $q$UPDATE public.zz_legacy_rules SET terms_kind = 'zz_fee' WHERE id = '00000000-0000-4000-8000-0000000017e2'$q$, '23001', 'never edited');


-- ============================================================ P. published values
INSERT INTO public.rule_parameters (parameter_name, unit, scoped_by, value_min, value_max, description, source_note) VALUES
  ('zz_deposit_rate', 'annual_rate_fraction', '{state_code}', 0, 1, 'ZZ commission''s annual deposit interest rate', 'ZZ Code 7.7'),
  ('zz_treasury_5y', 'annual_rate_fraction', '{}', 0, 1, 'Five-year Treasury yield', 'US Treasury');
INSERT INTO public.rule_parameter_values (parameter_name, state_code, effective_from, effective_to, value, source_note) VALUES
  ('zz_deposit_rate', 'ZZ', DATE '2025-01-01', DATE '2026-01-01', 0.0287, 'ZZ PUC notice 2024-12'),
  ('zz_deposit_rate', 'ZZ', DATE '2026-01-01', NULL, 0.0412, 'ZZ PUC notice 2025-12');
SELECT pg_temp.ok('P1: the value in force on a date, in its exact scope',
  (public.rule_parameter_value_as_of('zz_deposit_rate', 'ZZ', NULL, DATE '2025-06-30')).value = 0.0287
  AND (public.rule_parameter_value_as_of('zz_deposit_rate', 'ZZ', NULL, DATE '2026-01-01')).value = 0.0412);
SELECT pg_temp.refuses('P2a: a lookup broader or narrower than the parameter''s scope',
  $q$SELECT public.rule_parameter_value_as_of('zz_deposit_rate', 'ZZ', 'gas', DATE '2025-06-30')$q$, '22023', 'name exactly those');
SELECT pg_temp.refuses('P2b: no value on the date — never the nearest one',
  $q$SELECT public.rule_parameter_value_as_of('zz_deposit_rate', 'ZZ', NULL, DATE '2024-12-31')$q$, 'P0002', 'no published zz_deposit_rate');
SELECT pg_temp.refuses('P3a: a value scoped other than its parameter (a national value of a state parameter)',
  $q$INSERT INTO public.rule_parameter_values (parameter_name, effective_from, value, source_note) VALUES ('zz_deposit_rate', DATE '2030-01-01', 0.01, 'x')$q$,
  '23514', 'is scoped by state_code');
SELECT pg_temp.refuses('P3b: a value outside the parameter''s range',
  $q$INSERT INTO public.rule_parameter_values (parameter_name, effective_from, value, source_note) VALUES ('zz_treasury_5y', DATE '2030-01-01', 4.5, 'x')$q$,
  '23514', 'is outside [0, 1]');
SELECT pg_temp.refuses('P3c: NaN',
  $q$INSERT INTO public.rule_parameter_values (parameter_name, effective_from, value, source_note) VALUES ('zz_treasury_5y', DATE '2030-01-01', 'NaN', 'x')$q$,
  '23514', 'NaN is not a published value');
SELECT pg_temp.refuses('P3d: two values over one range',
  $q$INSERT INTO public.rule_parameter_values (parameter_name, state_code, effective_from, value, source_note) VALUES ('zz_deposit_rate', 'ZZ', DATE '2027-01-01', 0.05, 'x')$q$,
  '23P01', 'rule_parameter_values_no_overlap');
SELECT pg_temp.refuses('P3e: a published value is never edited',
  $q$UPDATE public.rule_parameter_values SET value = 0.03 WHERE parameter_name = 'zz_deposit_rate' AND effective_from = DATE '2025-01-01'$q$, '23001', 'never edited');
SELECT pg_temp.refuses('P3f: nor deleted',
  $q$DELETE FROM public.rule_parameter_values WHERE parameter_name = 'zz_deposit_rate'$q$, '23001', 'never deleted');
SELECT pg_temp.refuses('P3g: the application writes no published value',
  $q$INSERT INTO public.rule_parameter_values (parameter_name, effective_from, value, source_note) VALUES ('zz_treasury_5y', DATE '2030-01-01', 0.04, 'x')$q$,
  '42501', 'permission denied', 'tally_app', :'u1');
SELECT pg_temp.refuses('P3h: a parameter is never edited',
  $q$UPDATE public.rule_parameters SET unit = 'percent' WHERE parameter_name = 'zz_treasury_5y'$q$, '23001', 'never edited or deleted');
SELECT pg_temp.refuses('P3i: a unit not in the vocabulary',
  $q$INSERT INTO public.rule_parameters (parameter_name, unit, scoped_by, description, source_note) VALUES ('zz_x', 'furlongs', '{}', 'x', 'x')$q$,
  '23503', 'rule_parameters_unit_fkey');
UPDATE public.rule_parameter_values SET effective_to = DATE '2027-01-01' WHERE parameter_name = 'zz_deposit_rate' AND effective_from = DATE '2026-01-01';
SELECT pg_temp.ok('P4: a value closes once, stamped',
  (SELECT closed_at IS NOT NULL AND closed_by = session_user FROM public.rule_parameter_values WHERE parameter_name = 'zz_deposit_rate' AND effective_from = DATE '2026-01-01'));


-- ============================================================ I. core inputs
CREATE FUNCTION pg_temp.calc_sql(p_tenant text, p_charge uuid, p_inputs jsonb, p_fp text DEFAULT NULL, p_kind text DEFAULT 'zz_charge_inputs') RETURNS text
LANGUAGE sql STABLE AS $$
  SELECT format($q$INSERT INTO public.zz_charge_calcs (tenant_id, charge_id, inputs, inputs_kind, inputs_version, inputs_fingerprint, calculated_by)
                   VALUES (%L, %L, %L, %L, 1, %L, 'core 0.1.0+battery')$q$, p_tenant, p_charge, p_inputs, p_kind, p_fp)
$$;
INSERT INTO good VALUES ('inputs', '{"bill_amount": 120.5, "meters": 2, "rule_row": "00000000-0000-4000-8000-0000000017e1", "flags": [true]}');
SELECT pg_temp.run(pg_temp.calc_sql(:'t2', pg_temp.id('ch2'), pg_temp.g('inputs')), 'tally_core', :'u2');
SELECT pg_temp.ok('I1: the database stamps the fingerprint of the stored inputs',
  (SELECT inputs_fingerprint = 'sha256:' || encode(sha256(convert_to(inputs::text, 'UTF8')), 'hex') FROM public.zz_charge_calcs WHERE charge_id = pg_temp.id('ch2')));
SELECT pg_temp.run(pg_temp.calc_sql(:'t2', pg_temp.id('ch2'), '{"meters": 2, "flags": [true], "rule_row": "00000000-0000-4000-8000-0000000017e1", "bill_amount": 120.5}',
                   (SELECT inputs_fingerprint FROM public.zz_charge_calcs WHERE charge_id = pg_temp.id('ch2'))), 'tally_core', :'u2');
SELECT pg_temp.ok('I2: the same inputs in another key order hash the same, and the writer may confirm the fingerprint',
  (SELECT count(DISTINCT inputs_fingerprint) = 1 AND count(*) = 2 FROM public.zz_charge_calcs WHERE charge_id = pg_temp.id('ch2')));
SELECT pg_temp.refuses('I3a: a fingerprint the writer computed differently',
  pg_temp.calc_sql(:'t2', pg_temp.id('ch2'), pg_temp.g('inputs'), 'sha256:' || repeat('0', 64)), '23514', 'the core and the database disagree', 'tally_core', :'u2');
SELECT pg_temp.refuses('I3b: inputs that fail their schema',
  pg_temp.calc_sql(:'t2', pg_temp.id('ch2'), pg_temp.g('inputs') - 'meters'), '23514', '/meters: required', 'tally_core', :'u2');
SELECT pg_temp.refuses('I3c: a number written non-canonically (120.50) — it would hash differently from 120.5',
  pg_temp.calc_sql(:'t2', pg_temp.id('ch2'), jsonb_set(pg_temp.g('inputs'), '{bill_amount}', '120.50')), '23514', 'written canonically', 'tally_core', :'u2');
SELECT pg_temp.refuses('I3d: a kind that is not an inputs kind',
  pg_temp.calc_sql(:'t2', pg_temp.id('ch2'), pg_temp.g('tariff'), NULL, 'zz_fee_tariff'), '23503', 'is not a registered inputs schema', 'tally_core', :'u2');
SELECT pg_temp.refuses('I3e: the application writes no core record',
  pg_temp.calc_sql(:'t2', pg_temp.id('ch2'), pg_temp.g('inputs')), '42501', 'permission denied', 'tally_app', :'u2');
SELECT pg_temp.refuses('I3f: a blank calculated_by',
  replace(pg_temp.calc_sql(:'t2', pg_temp.id('ch2'), pg_temp.g('inputs')), 'core 0.1.0+battery', ' '), '23514', 'names the core release', 'tally_core', :'u2');


-- ============================================================ K. tally_core and audit findings
SELECT pg_temp.ok('K1: tally_core and tally_app are not members of each other; the core has no TEMP or CREATE',
  NOT pg_has_role('tally_core', 'tally_app', 'MEMBER') AND NOT pg_has_role('tally_app', 'tally_core', 'MEMBER')
  AND NOT has_database_privilege('tally_core', current_database(), 'TEMP') AND NOT has_database_privilege('tally_core', current_database(), 'CREATE')
  AND NOT has_schema_privilege('tally_core', 'public', 'CREATE'));
SELECT pg_temp.refuses('K2a: the core cannot create a temp table (no code of its own: the depth fences hold)',
  $q$CREATE TEMP TABLE zz_core_tmp (a int)$q$, '42501', 'permission denied', 'tally_core', :'u1');
SELECT pg_temp.refuses('K2b: the core cannot write an application table (a customer)',
  format($q$INSERT INTO public.customers (tenant_id, customer_number, customer_type) VALUES (%L, 'K2', 'residential')$q$, :'t1'), '42501', 'permission denied', 'tally_core', :'u1');
SELECT pg_temp.ok('K2c: the core reads no materialized view',
  NOT EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
               WHERE n.nspname = 'public' AND c.relkind = 'm' AND has_table_privilege('tally_core', c.oid, 'SELECT')));
CREATE FUNCTION pg_temp.finding_sql(p_tenant text, p_kind text, p_subject_table text, p_subject uuid, p_rule_table text, p_rule uuid,
                                    p_expected text DEFAULT NULL, p_by date DEFAULT NULL, p_detail jsonb DEFAULT '{"note": "battery"}') RETURNS text
LANGUAGE sql STABLE AS $$
  SELECT format($q$INSERT INTO public.rule_audit_findings (tenant_id, finding_kind, subject_table, subject_id, rule_table, rule_row_id, core_release,
                                                         coverage_from, coverage_to, expected_decision, expected_by, detail)
                   VALUES (%L, %L, %L, %L, %L, %L, 'core 0.1.0+battery', DATE '2024-01-01', DATE '2024-12-31', %L, %L, %L)$q$,
                p_tenant, p_kind, p_subject_table, p_subject, p_rule_table, p_rule, p_expected, p_by, p_detail)
$$;
SELECT pg_temp.run(pg_temp.finding_sql(:'t1', 'record_disagrees_with_rule', 'zz_charges', pg_temp.id('ch1'), 'zz_fee_rules', pg_temp.id('lr2')), 'tally_core', :'u1');
SELECT pg_temp.run(pg_temp.finding_sql(:'t1', 'missed_decision', 'public.zz_charges', pg_temp.id('ch1'), 'public.zz_fee_tariffs', pg_temp.id('t1tar'),
                                       'refund_due', DATE '2024-06-01'), 'tally_core', :'u1');
SELECT pg_temp.ok('K3: the core records findings; the rule row''s kind and version, the table names and the time are stamped',
  (SELECT count(*) = 2 AND bool_and(subject_table = 'zz_charges' AND found_at IS NOT NULL AND recorded_txid = txid_current())
          AND bool_or(terms_kind = 'zz_fee' AND terms_version = 1 AND rule_table = 'zz_fee_rules')
          AND bool_or(terms_kind = 'zz_fee_tariff' AND expected_decision = 'refund_due')
     FROM public.rule_audit_findings WHERE tenant_id = :'t1'));
SELECT pg_temp.refuses('K4a: the application records no finding',
  pg_temp.finding_sql(:'t1', 'record_disagrees_with_rule', 'zz_charges', pg_temp.id('ch1'), NULL, NULL), '42501', 'permission denied', 'tally_app', :'u1');
SELECT pg_temp.refuses('K4b: a missed decision names what was expected and by when',
  pg_temp.finding_sql(:'t1', 'missed_decision', 'zz_charges', pg_temp.id('ch1'), NULL, NULL), '23514', 'names the decision expected', 'tally_core', :'u1');
SELECT pg_temp.refuses('K4c: other kinds do not',
  pg_temp.finding_sql(:'t1', 'record_disagrees_with_rule', 'zz_charges', pg_temp.id('ch1'), NULL, NULL, 'refund_due', DATE '2024-06-01'),
  '23514', 'does not name the decision expected', 'tally_core', :'u1');
SELECT pg_temp.refuses('K4d: a subject in another tenant',
  pg_temp.finding_sql(:'t1', 'record_disagrees_with_rule', 'zz_charges', pg_temp.id('ch2'), NULL, NULL), '23503', 'has no row', 'tally_core', :'u1');
SELECT pg_temp.refuses('K4e: a subject table with no tenant',
  pg_temp.finding_sql(:'t1', 'record_disagrees_with_rule', 'zz_waiver_classes', pg_temp.id('ch1'), NULL, NULL), '23503', 'is not a tenant table', 'tally_core', :'u1');
SELECT pg_temp.refuses('K4f: a rule table that is not registered',
  pg_temp.finding_sql(:'t1', 'record_disagrees_with_rule', 'zz_charges', pg_temp.id('ch1'), 'zz_charges', pg_temp.id('ch1')), '23503', 'is not a registered rule table', 'tally_core', :'u1');
SELECT pg_temp.refuses('K4g: another tenant''s tariff row',
  pg_temp.finding_sql(:'t1', 'record_disagrees_with_rule', 'zz_charges', pg_temp.id('ch1'), 'zz_fee_tariffs', pg_temp.id('t2tar')), '23503', 'has no row', 'tally_core', :'u1');
SELECT pg_temp.refuses('K4h: detail with a null in it',
  pg_temp.finding_sql(:'t1', 'record_disagrees_with_rule', 'zz_charges', pg_temp.id('ch1'), NULL, NULL, NULL, NULL, '{"x": null}'), '23514', 'holds no nulls', 'tally_core', :'u1');
SELECT pg_temp.refuses('K4i: a date due with no decision named',
  pg_temp.finding_sql(:'t1', 'record_disagrees_with_rule', 'zz_charges', pg_temp.id('ch1'), NULL, NULL, NULL, DATE '2024-06-01'),
  '23514', 'does not name the decision expected', 'tally_core', :'u1');
SELECT pg_temp.refuses('K5a: a finding is never edited (by the owner either)',
  $q$UPDATE public.rule_audit_findings SET core_release = 'x'$q$, '23001', 'never edited or deleted');
SELECT pg_temp.refuses('K5b: nor deleted by the core',
  $q$DELETE FROM public.rule_audit_findings$q$, '42501', 'permission denied', 'tally_core', :'u1');
INSERT INTO b17 SELECT 'f1', id FROM public.rule_audit_findings WHERE tenant_id = :'t1' AND finding_kind = 'missed_decision';
CREATE FUNCTION pg_temp.disp_sql(p_tenant text, p_finding uuid, p_kind text) RETURNS text LANGUAGE sql STABLE AS $$
  SELECT format($q$INSERT INTO public.rule_audit_finding_dispositions (tenant_id, finding_id, disposition, note, decided_by)
                   VALUES (%L, %L, %L, 'Refund issued under ticket 7', '00000000-0000-4000-8000-0000000017b2')$q$, p_tenant, p_finding, p_kind)
$$;
SELECT pg_temp.run(pg_temp.disp_sql(:'t1', pg_temp.id('f1'), 'corrected'), 'tally_app', :'u1');
SELECT pg_temp.ok('K7a: a person records what was done about a finding; who and when are stamped, not taken from the writer',
  (SELECT decided_by = :'u1'::uuid AND decided_at IS NOT NULL AND disposition = 'corrected' FROM public.rule_audit_finding_dispositions WHERE finding_id = pg_temp.id('f1')));
SELECT pg_temp.refuses('K7b: the core records no disposition',
  pg_temp.disp_sql(:'t1', pg_temp.id('f1'), 'acknowledged'), '42501', 'permission denied', 'tally_core', :'u1');
SELECT pg_temp.refuses('K7c: a disposition with no user',
  replace(pg_temp.disp_sql(:'t1', pg_temp.id('f1'), 'acknowledged'), 'INSERT', 'SELECT set_config(''app.user_id'', '''', true); INSERT'),
  '23502', 'is a person''s act', 'tally_app', :'u1');
SELECT pg_temp.refuses('K7d: a disposition of another tenant''s finding',
  pg_temp.disp_sql(:'t2', pg_temp.id('f1'), 'acknowledged'), '23503', 'rule_audit_finding_dispositions_finding_fkey', 'tally_app', :'u2');
SELECT pg_temp.refuses('K7e: a disposition is never edited',
  $q$UPDATE public.rule_audit_finding_dispositions SET note = 'x'$q$, '23001', 'never edited or deleted');
CREATE TEMP TABLE k6 (n bigint);
GRANT INSERT ON k6 TO tally_app, tally_core;
SELECT pg_temp.run($q$INSERT INTO k6 SELECT count(*) FROM public.rule_audit_findings$q$, 'tally_app', :'u2');
SELECT pg_temp.run($q$INSERT INTO k6 SELECT count(*) FROM public.rule_audit_findings$q$, 'tally_core', :'u2');
SELECT pg_temp.run($q$INSERT INTO k6 SELECT count(*) + 100 FROM public.rule_audit_findings$q$, 'tally_app', :'u1');
SELECT pg_temp.ok('K6: another tenant''s application and core see none of tenant 1''s findings; tenant 1''s application reads its own',
  (SELECT array_agg(n ORDER BY n) FROM k6) = '{0,0,102}');


-- ============================================================ G. tenancy
SELECT pg_temp.refuses('K8: the core-role assertion catches a column grant on a materialized view',
  format($q$GRANT SELECT (%I) ON %s TO tally_core; SELECT public.assert_core_role_invariants()$q$,
         (SELECT a.attname FROM pg_attribute a JOIN pg_class c ON c.oid = a.attrelid JOIN pg_namespace n ON n.oid = c.relnamespace
           WHERE n.nspname = 'public' AND c.relkind = 'm' AND a.attnum > 0 ORDER BY c.relname, a.attnum LIMIT 1),
         (SELECT c.oid::regclass::text FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'public' AND c.relkind = 'm' ORDER BY c.relname LIMIT 1)),
  '0LP01', 'reaches materialized views');
SELECT pg_temp.refuses('K10: the core-role assertion catches the core joined to another role (SET ROLE past the policies)',
  $q$CREATE ROLE zz_bypass NOLOGIN BYPASSRLS; GRANT zz_bypass TO tally_core; SELECT public.assert_core_role_invariants()$q$,
  '0LP01', 'tally_core is a member of zz_bypass');
DO $$ BEGIN
  PERFORM public.assert_core_role_invariants();
  RAISE NOTICE 'PASS K9: the core-role assertion passes on this build';
END $$;
SELECT pg_temp.refuses('O1: an applicability ordinal is never edited',
  $q$UPDATE public.rule_applicability_ordinals SET ordinal = 99 WHERE dimension = 'owner_type' AND code = 'municipal'$q$, '23001', 'never edited or deleted');
SELECT pg_temp.refuses('O2: an ordinal for a code not in its vocabulary',
  $q$INSERT INTO public.rule_applicability_ordinals (dimension, code, ordinal) VALUES ('owner_type', 'city', 98)$q$, '23503', 'is not in its vocabulary');
DO $$ BEGIN
  PERFORM public.assert_tenant_isolation_invariants();
  RAISE NOTICE 'PASS G1: every tenant table here, the fixture''s tariff, charge and calculation tables included, passes the isolation invariants';
END $$;

ROLLBACK;
