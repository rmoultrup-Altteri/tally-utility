-- ============================================================================
-- BATTERY v5.4.2-18 — backbilling at the rule-terms convention (2026-10-09; draft r1)
-- Run (tests/v5.4.2-18/run-battery-18.sh copies law/ into the container):
--   psql -U tally -d <db-with-patch> -v ON_ERROR_STOP=1 -f battery-18.sql
-- One transaction, rolled back. The area is Texas gas backbilling as the -13
-- migration left it: the 16 adopted rows, on the table the battery finds
-- registered. A fictional state's rows (ZZ) are written to prove the
-- document gate. Negative cases go through pg_temp.refuses(), which runs the
-- statement (as a role and user when given), requires the named SQLSTATE AND
-- a phrase of the named guard's own message — a refusal by a different guard
-- is a failure, not a pass. Success checks use IS DISTINCT FROM.
--
--   S  the kind and its facet                     (patch section 2)
--   M  the table after the migration              (sections 3-6)
--   K  the sixteen rows say what -13 said         (section 5)
--   D  the document gate                          (sections 2, 4)
--   O  overlap and applicability
--   H  history, closes, grants
--   X  the area's insert check
--   L  lookups
-- The migration itself (a damaged base, a repaired one, a second run) is
-- migration-18.sh; the close against a citing evaluation is battery-13 F.
-- ============================================================================
\set ON_ERROR_STOP 1
BEGIN;
SET CONSTRAINTS ALL IMMEDIATE;

CREATE TEMP TABLE b18 (k text PRIMARY KEY, id uuid);
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
CREATE FUNCTION pg_temp.id(p_k text) RETURNS uuid LANGUAGE sql STABLE AS $$ SELECT id FROM b18 WHERE k = p_k $$;

-- The users and tenants: T1 runs a city-owned Texas system, T2 an investor-owned one.
INSERT INTO public.tenants (id, name, slug) VALUES
  ('00000000-0000-4000-8000-0000000018a1', 'T1 City Gas', 'bat18-t1'),
  ('00000000-0000-4000-8000-0000000018a2', 'T2 Gasco', 'bat18-t2');
INSERT INTO public.users (id, tenant_id, display_name, email, role) VALUES
  ('00000000-0000-4000-8000-0000000018b1', '00000000-0000-4000-8000-0000000018a1', 'Op1', 'op1@bat18.test', 'operator'),
  ('00000000-0000-4000-8000-0000000018b2', '00000000-0000-4000-8000-0000000018a2', 'Op2', 'op2@bat18.test', 'operator');
INSERT INTO public.tenants (id, name, slug) VALUES
  ('00000000-0000-4000-8000-0000000018a3', 'T3 Co-op Gas', 'bat18-t3'),
  ('00000000-0000-4000-8000-0000000018a4', 'T4 Propane Pipe', 'bat18-t4'),
  ('00000000-0000-4000-8000-0000000018a5', 'T5 Master Meter', 'bat18-t5');
INSERT INTO public.users (id, tenant_id, display_name, email, role) VALUES
  ('00000000-0000-4000-8000-0000000018b3', '00000000-0000-4000-8000-0000000018a3', 'Op3', 'op3@bat18.test', 'operator'),
  ('00000000-0000-4000-8000-0000000018b4', '00000000-0000-4000-8000-0000000018a4', 'Op4', 'op4@bat18.test', 'operator'),
  ('00000000-0000-4000-8000-0000000018b5', '00000000-0000-4000-8000-0000000018a5', 'Op5', 'op5@bat18.test', 'operator');
\set u1 '00000000-0000-4000-8000-0000000018b1'
\set u2 '00000000-0000-4000-8000-0000000018b2'
\set t1 '00000000-0000-4000-8000-0000000018a1'
\set t2 '00000000-0000-4000-8000-0000000018a2'
\set u3 '00000000-0000-4000-8000-0000000018b3'
\set u4 '00000000-0000-4000-8000-0000000018b4'
\set u5 '00000000-0000-4000-8000-0000000018b5'
\set t3 '00000000-0000-4000-8000-0000000018a3'
\set t4 '00000000-0000-4000-8000-0000000018a4'
\set t5 '00000000-0000-4000-8000-0000000018a5'

-- A fictional state, ZZ, with two classes; and a Texas city that owns T1.
INSERT INTO public.places (kind_code, state_code, place_code, name, effective_from, source_note)
VALUES ('state', 'ZZ', 'ZZ', 'Zedland', DATE '1900-01-01', 'battery fixture: a fictional state');
INSERT INTO public.backbilling_customer_classes (state_code, service_type, class_code, description, source_note) VALUES
  ('ZZ', 'gas', 'protected', 'battery class', 'battery fixture'),
  ('ZZ', 'gas', 'other', 'battery class', 'battery fixture');
INSERT INTO b18 SELECT 'tx', id FROM public.places WHERE kind_code = 'state' AND place_code = 'TX';
INSERT INTO public.places (kind_code, state_code, place_code, name, parent_place_id, effective_from, source_note)
VALUES ('municipality', 'TX', 'BAT18CITY', 'Battery City', pg_temp.id('tx'), DATE '1950-01-01', 'battery fixture');
INSERT INTO b18 SELECT 'city', id FROM public.places WHERE kind_code = 'municipality' AND place_code = 'BAT18CITY';
SELECT pg_temp.run(format($q$
  INSERT INTO public.utility_service_profiles (tenant_id, service_type, system_kind, state_code, owner_type, commission_jurisdiction,
                                               owning_place_id, effective_from, evidence_reference, evidence_date)
  VALUES (%L, 'gas', 'distribution', 'TX', 'municipal', false, %L, DATE '2000-01-01', 'Battery City charter', DATE '2000-01-01')$q$,
  :'t1', pg_temp.id('city')), 'tally_app', :'u1');
SELECT pg_temp.run(format($q$
  INSERT INTO public.utility_service_profiles (tenant_id, service_type, system_kind, state_code, owner_type, commission_jurisdiction,
                                               effective_from, evidence_reference, evidence_date)
  VALUES (%L, 'gas', 'distribution', 'TX', 'investor_owned', true, DATE '2000-01-01', 'RRC certificate bat18', DATE '2000-01-01')$q$,
  :'t2'), 'tally_app', :'u2');

SELECT pg_temp.run(format($q$
  INSERT INTO public.utility_service_profiles (tenant_id, service_type, system_kind, state_code, owner_type, commission_jurisdiction,
                                               effective_from, evidence_reference, evidence_date)
  VALUES (%L, 'gas', 'distribution', 'TX', 'cooperative', false, DATE '2000-01-01', 'Co-op certificate bat18', DATE '2000-01-01')$q$,
  :'t3'), 'tally_app', :'u3');
SELECT pg_temp.run(format($q$
  INSERT INTO public.utility_service_profiles (tenant_id, service_type, system_kind, state_code, owner_type, commission_jurisdiction,
                                               effective_from, evidence_reference, evidence_date)
  VALUES (%L, 'gas', 'piped_propane_distribution', 'TX', 'investor_owned', true, DATE '2000-01-01', 'RRC certificate bat18 propane', DATE '2000-01-01')$q$,
  :'t4'), 'tally_app', :'u4');
SELECT pg_temp.run(format($q$
  INSERT INTO public.utility_service_profiles (tenant_id, service_type, system_kind, state_code, owner_type, commission_jurisdiction,
                                               effective_from, evidence_reference, evidence_date)
  VALUES (%L, 'gas', 'master_meter', 'TX', 'investor_owned', true, DATE '2000-01-01', 'RRC certificate bat18 master meter', DATE '2000-01-01')$q$,
  :'t5'), 'tally_app', :'u5');

-- doc(overrides): a valid document for a ZZ discovery-date rule, with fields replaced.
CREATE FUNCTION pg_temp.doc(p_over jsonb DEFAULT '{}') RETURNS jsonb LANGUAGE sql IMMUTABLE AS $$
  SELECT '{"governs": "law", "citation": "ZZ 7.45", "anchor": {"strategy": "discovery_date", "version": 1},
           "favourable_duty": "permitted", "adverse_straddle": "include_whole", "favourable_straddle": "include_whole",
           "delivery_path": "unruled", "requires_supervisor_evidence": false, "units_invariant": false,
           "enforcement": {"strategy": "uncapped", "version": 1}, "windows": {"adverse": [], "favourable": []}}'::jsonb || p_over
$$;
-- ins_sql(class, cause, document, from, to, owners): the statement that writes a ZZ rule.
CREATE FUNCTION pg_temp.ins_sql(p_class text, p_cause text, p_doc jsonb, p_from date DEFAULT DATE '2020-01-01',
                                p_to date DEFAULT NULL, p_owners text DEFAULT '{investor_owned}') RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT format($q$INSERT INTO public.backbilling_rules (state_code, service_type, customer_class, cause, owner_types, effective_from, effective_to,
                                                         source_note, terms_kind, terms_version, terms_source)
                   VALUES ('ZZ', 'gas', %L, %L, %L, %L, %L, 'battery rule', 'backbilling', 1, %L)$q$,
                p_class, p_cause, p_owners, p_from, p_to, p_doc::text)
$$;

-- ============================================================ S. the kind and its facet
SELECT pg_temp.ok('S1: backbilling v1 is a registered, unfrozen law kind',
  (SELECT rule_role = 'law' AND accepts_new_rows FROM public.rule_term_schemas WHERE terms_kind = 'backbilling' AND terms_version = 1));
SELECT pg_temp.ok('S2: its one facet is the anchor basis, from the anchor strategy, in the basis vocabulary',
  (SELECT count(*) = 1 AND bool_and(facet_name = 'anchor_basis' AND facet_type = 'text' AND json_path = '$.anchor.strategy'
                                    AND vocabulary_table = 'backbilling_anchor_bases' AND vocabulary_column = 'basis_code')
     FROM public.rule_term_facets WHERE terms_kind = 'backbilling' AND terms_version = 1));
SELECT pg_temp.ok('S3: the window-term kinds and the enforcement condition live in the schema, not in tables',
  to_regclass('public.backbilling_window_term_kinds') IS NULL AND to_regclass('public.backbilling_enforce_conditions') IS NULL
  AND to_regclass('public.backbilling_rule_window_terms') IS NULL);
SELECT pg_temp.ok('S4: the vocabularies records cite stay tables (causes, classes, anchor bases)',
  to_regclass('public.backbilling_causes') IS NOT NULL AND to_regclass('public.backbilling_customer_classes') IS NOT NULL
  AND to_regclass('public.backbilling_anchor_bases') IS NOT NULL);

-- ============================================================ M. the table after the migration
SELECT pg_temp.ok('M1: backbilling_rules is a registered law table on the backbilling kind, keyed by class and cause, adopting its rows',
  (SELECT rule_role = 'law' AND terms_kind = 'backbilling' AND area_key = '{customer_class,cause}' AND facet_columns = '{anchor_basis}'
          AND adopts_legacy_rows AND adoption_check IS NOT NULL AND close_floor IS NOT NULL AND insert_check IS NOT NULL
          AND law_table IS NULL AND compare_function IS NULL
     FROM public.rule_tables WHERE table_name = 'public.backbilling_rules'::regclass));
SELECT pg_temp.ok('M2: the ten content columns are gone',
  NOT EXISTS (SELECT 1 FROM pg_attribute a WHERE a.attrelid = 'public.backbilling_rules'::regclass AND NOT a.attisdropped AND a.attnum > 0
                 AND a.attname = ANY (ARRAY['qualifying_test_outcomes', 'favourable_duty', 'adverse_straddle', 'favourable_straddle', 'delivery_path',
                                            'requires_supervisor_evidence', 'units_invariant', 'enforce_scope', 'enforce_months', 'enforce_condition'])));
SELECT pg_temp.ok('M3: the anchor basis is a facet now: nullable, and still a foreign key into the basis vocabulary',
  (SELECT NOT a.attnotnull FROM pg_attribute a WHERE a.attrelid = 'public.backbilling_rules'::regclass AND a.attname = 'anchor_basis')
  AND EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public.backbilling_rules'::regclass AND conname = 'backbilling_rules_anchor_basis_fkey'));
SELECT pg_temp.ok('M4: the history and record triggers of -13 are gone; the template''s three stand, enabled always',
  NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid = 'public.backbilling_rules'::regclass AND NOT tgisinternal
                 AND tgname = ANY (ARRAY['a_enforce_backbilling_rule_history', 'a_enforce_backbilling_rule_record']))
  AND (SELECT count(*) FROM pg_trigger WHERE tgrelid = 'public.backbilling_rules'::regclass AND NOT tgisinternal
          AND tgname = ANY (ARRAY['rule_row_insert', 'rule_row_history', 'rule_row_no_truncate']) AND tgenabled = 'A') = 3
  AND to_regprocedure('public.enforce_backbilling_rule_history()') IS NULL AND to_regprocedure('public.enforce_backbilling_rule_record()') IS NULL
  AND to_regprocedure('public.enforce_backbilling_window_term_record()') IS NULL);
SELECT pg_temp.ok('M5: -13''s own overlap, range and source-note constraints are replaced by the template''s',
  NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public.backbilling_rules'::regclass
                 AND conname = ANY (ARRAY['backbilling_rules_no_overlap', 'backbilling_rules_range_check', 'backbilling_rules_source_note_check']))
  AND (SELECT count(*) FROM pg_constraint WHERE conrelid = 'public.backbilling_rules'::regclass
          AND conname = ANY (ARRAY['backbilling_rules_rule_no_overlap', 'backbilling_rules_rule_range_check', 'backbilling_rules_rule_source_check'])) = 3
  AND EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public.backbilling_rules'::regclass AND conname = 'backbilling_rules_class_fkey')
  AND EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public.backbilling_rules'::regclass AND conname = 'backbilling_rules_cause_fkey'));
SELECT pg_temp.ok('M6: all sixteen Texas rows hold a backbilling v1 document, with the facet derived from it: the protected eight are law, the unprotected eight delegations (no anchor)',
  (SELECT count(*) = 16 AND bool_and(terms_kind = 'backbilling' AND terms_version = 1 AND terms IS NOT NULL AND terms_source IS NOT NULL
                                     AND CASE customer_class WHEN 'protected' THEN terms ->> 'governs' = 'law' AND anchor_basis = terms -> 'anchor' ->> 'strategy'
                                                             ELSE terms ->> 'governs' = 'delegated_to_utility' AND anchor_basis IS NULL END)
     FROM public.backbilling_rules WHERE state_code = 'TX' AND service_type = 'gas'));
SELECT pg_temp.ok('M7: the sixteen bind what 16 TAC 7.45 binds: investor-owned and cooperative owners, distribution systems (not propane, not master meters), either jurisdiction status',
  (SELECT bool_and(owner_types = '{cooperative,investor_owned}'::text[] OR owner_types = '{investor_owned,cooperative}'::text[])
          AND bool_and(system_kinds = '{distribution}' AND commission_jurisdiction IS NULL)
          AND bool_and(owner_span = public.rule_applicability_span('owner_type', ARRAY['investor_owned', 'cooperative'])
                       AND system_span = public.rule_applicability_span('system_kind', ARRAY['distribution'])
                       AND jurisdiction_span = public.rule_jurisdiction_span(NULL))
     FROM public.backbilling_rules WHERE state_code = 'TX'));
SELECT pg_temp.ok('M8: dates and stamps of the sixteen are as -13 wrote them: all from 2004-07-12, open-ended, unclosed',
  (SELECT bool_and(effective_from = DATE '2004-07-12' AND effective_to IS NULL AND closed_at IS NULL AND closed_by IS NULL AND recorded_txid IS NOT NULL
                   AND source_note ~ '[[:alnum:]]') FROM public.backbilling_rules WHERE state_code = 'TX'));
SELECT pg_temp.does('M9: the template''s invariants hold over the registered table', $q$SELECT public.assert_rule_table_invariants()$q$);
SELECT pg_temp.ok('M10: it is the registered rule table (the assertion is no longer vacuous)',
  (SELECT count(*) = 1 FROM public.rule_tables WHERE table_name = 'public.backbilling_rules'::regclass));

-- ============================================================ K. the sixteen rows say what -13 said
-- The expected documents, built here from the -13 seed's own table (class, cause,
-- basis, duty, straddles, delivery, supervisor, units, enforcement) and the two
-- window rules the seed text names, not read back from the migration.
CREATE TEMP TABLE k18 AS
SELECT t.customer_class, t.cause,
       CASE WHEN t.customer_class = 'unprotected' THEN
         jsonb_build_object('governs', 'delegated_to_utility', 'citation', '16 TAC 7.45',
                            'note', '16 TAC 7.45 does not reach this class; ordinary limitations law and the filed tariff govern, outside this table.')
       ELSE jsonb_build_object(
         'governs', 'law', 'citation', t.citation,
         'anchor', CASE t.anchor WHEN 'test_date'
                     THEN jsonb_build_object('strategy', 'test_date', 'version', 1, 'qualifying_outcomes', t.outcomes)
                     ELSE jsonb_build_object('strategy', 'discovery_date', 'version', 1) END,
         'favourable_duty', t.duty, 'adverse_straddle', t.adv, 'favourable_straddle', t.fav, 'delivery_path', t.delivery,
         'requires_supervisor_evidence', t.sup, 'units_invariant', t.units,
         'enforcement', CASE t.enf WHEN 'months' THEN jsonb_build_object('strategy', 'months', 'version', 1, 'months', t.months)
                                   WHEN 'conditional' THEN jsonb_build_object('strategy', 'conditional', 'version', 1, 'condition', t.cond)
                                   ELSE jsonb_build_object('strategy', t.enf, 'version', 1) END,
         'windows', CASE
            WHEN t.customer_class = 'protected' AND t.cause = 'meter_error' THEN
              '{"adverse": [{"kind": "before_anchor", "quantity": 6, "unit": "months"}, {"kind": "deployment_start"}, {"kind": "last_test_any_outcome"}],
                "favourable": [{"kind": "before_anchor", "quantity": 6, "unit": "months"}, {"kind": "deployment_start"}, {"kind": "last_test_any_outcome"}]}'::jsonb
            WHEN t.customer_class = 'protected' AND t.cause = 'non_registering_meter' THEN
              '{"adverse": [{"kind": "before_anchor", "quantity": 3, "unit": "months"}, {"kind": "deployment_start"}], "favourable": []}'::jsonb
            ELSE '{"adverse": [], "favourable": []}'::jsonb END) END AS doc
  FROM (VALUES
    ('protected', 'meter_error',            '16 TAC 7.45(7)(B)(v)(I)',                          'test_date',      '["fast", "slow"]'::jsonb,   'mandatory', 'forfeit_whole', 'include_whole', 'adjustment', false, false, 'never',       NULL::int, NULL::text),
    ('protected', 'non_registering_meter',  '16 TAC 7.45(7)(B)(v)(II)',                         'test_date',      '["non_registering"]'::jsonb, 'permitted', 'forfeit_whole', 'include_whole', 'unruled',    false, false, 'never',       NULL, NULL),
    ('protected', 'rate_misapplication',    '16 TAC 7.45(4)(E)(v)',                             'discovery_date', NULL,                         'permitted', 'include_whole', 'include_whole', 'reissue',    false, true,  'months',      6,    NULL),
    ('protected', 'estimation_catchup',     'No 7.45 billing cap on an estimation catch-up',    'discovery_date', NULL,                         'permitted', 'include_whole', 'include_whole', 'unruled',    false, false, 'conditional', NULL, 'read_beyond_utility_control'),
    ('protected', 'tampering_bypass',       '16 TAC 7.45(4)(D)(v)',                             'discovery_date', NULL,                         'permitted', 'include_whole', 'include_whole', 'unruled',    true,  false, 'uncapped',    NULL, NULL),
    ('protected', 'billing_constant_error', 'R-39: no 7.45 billing cap',                        'discovery_date', NULL,                         'permitted', 'include_whole', 'include_whole', 'unruled',    false, false, 'never',       NULL, NULL),
    ('protected', 'crossed_meters',         'R-39: no 7.45 billing cap',                        'discovery_date', NULL,                         'permitted', 'include_whole', 'include_whole', 'unruled',    false, false, 'never',       NULL, NULL),
    ('protected', 'unbilled_service',       'R-39: no 7.45 billing cap',                        'discovery_date', NULL,                         'permitted', 'include_whole', 'include_whole', 'unruled',    false, false, 'never',       NULL, NULL),
    ('unprotected', 'meter_error',            '16 TAC 7.45 does not reach this class',          'test_date',      '["fast", "slow"]'::jsonb,   'permitted', 'include_whole', 'include_whole', 'adjustment', false, false, 'uncapped', NULL, NULL),
    ('unprotected', 'non_registering_meter',  '16 TAC 7.45 does not reach this class',          'test_date',      '["non_registering"]'::jsonb, 'permitted', 'include_whole', 'include_whole', 'unruled',    false, false, 'uncapped', NULL, NULL),
    ('unprotected', 'rate_misapplication',    '16 TAC 7.45 does not reach this class',          'discovery_date', NULL,                         'permitted', 'include_whole', 'include_whole', 'reissue',    false, true,  'uncapped', NULL, NULL),
    ('unprotected', 'estimation_catchup',     '16 TAC 7.45 does not reach this class',          'discovery_date', NULL,                         'permitted', 'include_whole', 'include_whole', 'unruled',    false, false, 'uncapped', NULL, NULL),
    ('unprotected', 'tampering_bypass',       '16 TAC 7.45 does not reach this class',          'discovery_date', NULL,                         'permitted', 'include_whole', 'include_whole', 'unruled',    false, false, 'uncapped', NULL, NULL),
    ('unprotected', 'billing_constant_error', '16 TAC 7.45 does not reach this class',          'discovery_date', NULL,                         'permitted', 'include_whole', 'include_whole', 'unruled',    false, false, 'uncapped', NULL, NULL),
    ('unprotected', 'crossed_meters',         '16 TAC 7.45 does not reach this class',          'discovery_date', NULL,                         'permitted', 'include_whole', 'include_whole', 'unruled',    false, false, 'uncapped', NULL, NULL),
    ('unprotected', 'unbilled_service',       '16 TAC 7.45 does not reach this class',          'discovery_date', NULL,                         'permitted', 'include_whole', 'include_whole', 'unruled',    false, false, 'uncapped', NULL, NULL)
  ) AS t(customer_class, cause, citation, anchor, outcomes, duty, adv, fav, delivery, sup, units, enf, months, cond);
SELECT pg_temp.ok('K1: sixteen expected documents', (SELECT count(*) = 16 FROM k18));
SELECT pg_temp.ok('K2: every stored document equals the one -13''s columns and window terms said',
  (SELECT count(*) = 16 AND bool_and(b.terms = k.doc)
     FROM k18 k JOIN public.backbilling_rules b ON b.state_code = 'TX' AND b.service_type = 'gas' AND b.customer_class = k.customer_class AND b.cause = k.cause));
SELECT pg_temp.ok('K3: the stored text is the stored document (terms_source parses to terms)',
  (SELECT bool_and(terms_source::jsonb = terms) FROM public.backbilling_rules WHERE state_code = 'TX'));
SELECT pg_temp.ok('K4: the facet is the document''s anchor strategy: meter and non-registering causes on a test, the rest on discovery; a delegation has none',
  (SELECT bool_and(anchor_basis IS NOT DISTINCT FROM CASE WHEN customer_class = 'unprotected' THEN NULL WHEN cause IN ('meter_error', 'non_registering_meter') THEN 'test_date' ELSE 'discovery_date' END)
     FROM public.backbilling_rules WHERE state_code = 'TX'));
SELECT pg_temp.ok('K5: the protected meter-error window is the shorter of six months and the last test, from deployment (R-37), in both directions; the refund is a duty',
  (SELECT terms -> 'windows' -> 'adverse' @> '[{"kind": "before_anchor", "quantity": 6}, {"kind": "last_test_any_outcome"}, {"kind": "deployment_start"}]'
      AND terms -> 'windows' -> 'favourable' @> '[{"kind": "before_anchor", "quantity": 6}, {"kind": "last_test_any_outcome"}, {"kind": "deployment_start"}]'
      AND terms ->> 'favourable_duty' = 'mandatory'
     FROM public.backbilling_rules WHERE state_code = 'TX' AND customer_class = 'protected' AND cause = 'meter_error'));

-- ============================================================ D. the document gate
SELECT pg_temp.does('D0: a valid ZZ document is written (the helper''s base)',
  pg_temp.ins_sql('protected', 'meter_error', pg_temp.doc()));
SELECT pg_temp.ok('D0b: and its facet was derived, not written', (SELECT anchor_basis = 'discovery_date' FROM public.backbilling_rules WHERE state_code = 'ZZ' AND cause = 'meter_error'));
SELECT pg_temp.refuses('D1: a document without its windows (a direction with no terms is written as an empty list, never omitted)',
  pg_temp.ins_sql('protected', 'crossed_meters', pg_temp.doc() - 'windows'), '23514', '/windows: required');
SELECT pg_temp.refuses('D2: a window without one of its directions',
  pg_temp.ins_sql('protected', 'crossed_meters', pg_temp.doc('{"windows": {"adverse": []}}')), '23514', '/windows/favourable: required');
SELECT pg_temp.refuses('D3: a month count of zero',
  pg_temp.ins_sql('protected', 'crossed_meters', pg_temp.doc('{"enforcement": {"strategy": "months", "version": 1, "months": 0}}')), '23514', '/enforcement/months: must be at least 1');
SELECT pg_temp.refuses('D4: months without a count',
  pg_temp.ins_sql('protected', 'crossed_meters', pg_temp.doc('{"enforcement": {"strategy": "months", "version": 1}}')), '23514', '/enforcement/months: required');
SELECT pg_temp.refuses('D5: a count under a strategy that takes none (a stray value reads as a limit)',
  pg_temp.ins_sql('protected', 'crossed_meters', pg_temp.doc('{"enforcement": {"strategy": "never", "version": 1, "months": 6}}')), '23514', '/enforcement/months: unknown key');
SELECT pg_temp.refuses('D6: a conditional enforcement without its condition',
  pg_temp.ins_sql('protected', 'crossed_meters', pg_temp.doc('{"enforcement": {"strategy": "conditional", "version": 1}}')), '23514', '/enforcement/condition: required');
SELECT pg_temp.refuses('D7: a condition the schema does not name',
  pg_temp.ins_sql('protected', 'crossed_meters', pg_temp.doc('{"enforcement": {"strategy": "conditional", "version": 1, "condition": "whenever"}}')), '23514', '/enforcement/condition: "whenever" is not one of');
SELECT pg_temp.refuses('D8: an enforcement strategy the schema does not name',
  pg_temp.ins_sql('protected', 'crossed_meters', pg_temp.doc('{"enforcement": {"strategy": "weekly", "version": 1}}')), '23514', '/enforcement/strategy: "weekly" is not one of');
SELECT pg_temp.refuses('D9: a strategy without its version',
  pg_temp.ins_sql('protected', 'crossed_meters', pg_temp.doc('{"enforcement": {"strategy": "never"}}')), '23514', '/enforcement/version: required');
SELECT pg_temp.refuses('D10: a rule on a test basis that names no outcomes (R-39: the outcome decides the cause)',
  pg_temp.ins_sql('protected', 'crossed_meters', pg_temp.doc('{"anchor": {"strategy": "test_date", "version": 1}}')), '23514', '/anchor/qualifying_outcomes: required');
SELECT pg_temp.refuses('D11: a rule on any other basis that names outcomes',
  pg_temp.ins_sql('protected', 'crossed_meters', pg_temp.doc('{"anchor": {"strategy": "discovery_date", "version": 1, "qualifying_outcomes": ["fast"]}}')), '23514', '/anchor/qualifying_outcomes: unknown key');
SELECT pg_temp.refuses('D12: an outcome that is not a test outcome',
  pg_temp.ins_sql('protected', 'crossed_meters', pg_temp.doc('{"anchor": {"strategy": "test_date", "version": 1, "qualifying_outcomes": ["fast", "broken"]}}')), '23514', '"broken" is not one of');
SELECT pg_temp.refuses('D13: an outcome named twice',
  pg_temp.ins_sql('protected', 'crossed_meters', pg_temp.doc('{"anchor": {"strategy": "test_date", "version": 1, "qualifying_outcomes": ["fast", "fast"]}}')), '23514', 'items must be unique');
SELECT pg_temp.refuses('D14: an empty outcome list',
  pg_temp.ins_sql('protected', 'crossed_meters', pg_temp.doc('{"anchor": {"strategy": "test_date", "version": 1, "qualifying_outcomes": []}}')), '23514', 'at least 1 items');
SELECT pg_temp.refuses('D15: an anchor basis the vocabulary does not know is not even a strategy',
  pg_temp.ins_sql('protected', 'crossed_meters', pg_temp.doc('{"anchor": {"strategy": "notice_date", "version": 1}}')), '23514', '/anchor/strategy: "notice_date" is not one of');
SELECT pg_temp.refuses('D16: a window term of a kind the schema does not name',
  pg_temp.ins_sql('protected', 'crossed_meters', pg_temp.doc('{"windows": {"adverse": [{"kind": "full_moon"}], "favourable": []}}')), '23514', '/windows/adverse/0/kind: "full_moon" is not one of');
SELECT pg_temp.refuses('D17: a before_anchor term without its quantity',
  pg_temp.ins_sql('protected', 'crossed_meters', pg_temp.doc('{"windows": {"adverse": [{"kind": "before_anchor", "unit": "months"}], "favourable": []}}')), '23514', '/windows/adverse/0/quantity: required');
SELECT pg_temp.refuses('D18: … or without its unit',
  pg_temp.ins_sql('protected', 'crossed_meters', pg_temp.doc('{"windows": {"adverse": [{"kind": "before_anchor", "quantity": 6}], "favourable": []}}')), '23514', '/windows/adverse/0/unit: required');
SELECT pg_temp.refuses('D19: a quantity on a kind that takes none',
  pg_temp.ins_sql('protected', 'crossed_meters', pg_temp.doc('{"windows": {"adverse": [{"kind": "deployment_start", "quantity": 6, "unit": "months"}], "favourable": []}}')), '23514', '/windows/adverse/0/quantity: unknown key');
SELECT pg_temp.refuses('D20: a unit of time the schema does not name',
  pg_temp.ins_sql('protected', 'crossed_meters', pg_temp.doc('{"windows": {"adverse": [{"kind": "before_anchor", "quantity": 6, "unit": "fortnights"}], "favourable": []}}')), '23514', '"fortnights" is not one of');
SELECT pg_temp.refuses('D21: a quantity of zero',
  pg_temp.ins_sql('protected', 'crossed_meters', pg_temp.doc('{"windows": {"adverse": [{"kind": "before_anchor", "quantity": 0, "unit": "months"}], "favourable": []}}')), '23514', '/windows/adverse/0/quantity: must be at least 1');
SELECT pg_temp.refuses('D22: a priority of zero',
  pg_temp.ins_sql('protected', 'crossed_meters', pg_temp.doc('{"windows": {"adverse": [{"kind": "claimed_start", "priority": 0}], "favourable": []}}')), '23514', '/windows/adverse/0/priority: must be at least 1');
SELECT pg_temp.refuses('D23: a straddle rule the schema does not name',
  pg_temp.ins_sql('protected', 'crossed_meters', pg_temp.doc('{"adverse_straddle": "split"}')), '23514', '/adverse_straddle: "split" is not one of');
SELECT pg_temp.refuses('D24: a delivery path the schema does not name',
  pg_temp.ins_sql('protected', 'crossed_meters', pg_temp.doc('{"delivery_path": "courier"}')), '23514', '/delivery_path: "courier" is not one of');
SELECT pg_temp.refuses('D25: a duty that is neither a duty nor a permission',
  pg_temp.ins_sql('protected', 'crossed_meters', pg_temp.doc('{"favourable_duty": "maybe"}')), '23514', '/favourable_duty: "maybe" is not one of');
SELECT pg_temp.refuses('D26: a flag written as text',
  pg_temp.ins_sql('protected', 'crossed_meters', pg_temp.doc('{"units_invariant": "no"}')), '23514', '/units_invariant: expected a boolean');
SELECT pg_temp.refuses('D27: a citation with no letter or digit',
  pg_temp.ins_sql('protected', 'crossed_meters', pg_temp.doc('{"citation": "—"}')), '23514', '/citation: does not match');
SELECT pg_temp.refuses('D28: a null anywhere (unknown is "unruled", never absent)',
  replace(pg_temp.ins_sql('protected', 'crossed_meters', pg_temp.doc()), '"delivery_path": "unruled"', '"delivery_path": null'), '23514', 'null is not allowed');
SELECT pg_temp.refuses('D29: a key the schema does not know',
  pg_temp.ins_sql('protected', 'crossed_meters', pg_temp.doc('{"enforce_months": 6}')), '23514', '/enforce_months: unknown key');
SELECT pg_temp.refuses('D30: a duplicate key in the text',
  replace(pg_temp.ins_sql('protected', 'crossed_meters', pg_temp.doc()), '"governs": "law"', '"governs": "law", "governs": "law"'), '22030', 'repeats a key');
SELECT pg_temp.does('D31: the law leaving it to the utility is a document too (a city''s standards)',
  pg_temp.ins_sql('other', 'meter_error', '{"governs": "delegated_to_utility", "citation": "ZZ Code 9", "note": "Cities set their own."}'::jsonb, DATE '2020-01-01', NULL, '{municipal}'));
SELECT pg_temp.refuses('D32: a rule for a class the state does not have (the class foreign key stays)',
  pg_temp.ins_sql('nonesuch', 'crossed_meters', pg_temp.doc()), '23503', 'backbilling_rules_class_fkey');
SELECT pg_temp.refuses('D33: a rule for a cause nobody named (the cause foreign key stays)',
  pg_temp.ins_sql('protected', 'sunspots', pg_temp.doc()), '23503', 'backbilling_rules_cause_fkey');
SELECT pg_temp.refuses('D34: a blank cause is no key',
  pg_temp.ins_sql('protected', ' ', pg_temp.doc()), '22023', 'non-blank');
SELECT pg_temp.refuses('D35: a rule with no document',
  $q$INSERT INTO public.backbilling_rules (state_code, service_type, customer_class, cause, owner_types, effective_from, source_note)
     VALUES ('ZZ', 'gas', 'protected', 'crossed_meters', '{investor_owned}', DATE '2020-01-01', 'no document')$q$, '23502', 'a rule document is required');
SELECT pg_temp.refuses('D36: a facet the writer sets must be the document''s (test_date, against a discovery-date document)',
  format($q$INSERT INTO public.backbilling_rules (state_code, service_type, customer_class, cause, owner_types, effective_from, source_note,
                                                  anchor_basis, terms_kind, terms_version, terms_source)
            VALUES ('ZZ', 'gas', 'protected', 'crossed_meters', '{investor_owned}', DATE '2020-01-01', 'battery rule', 'test_date', 'backbilling', 1, %L)$q$,
         pg_temp.doc()::text), '23514', 'is a facet, derived from the document');
SELECT pg_temp.refuses('D37: the writer cannot set the document apart from its text',
  format($q$INSERT INTO public.backbilling_rules (state_code, service_type, customer_class, cause, owner_types, effective_from, source_note,
                                                  terms_kind, terms_version, terms_source, terms)
            VALUES ('ZZ', 'gas', 'protected', 'crossed_meters', '{investor_owned}', DATE '2020-01-01', 'battery rule', 'backbilling', 1, %L, %L)$q$,
         pg_temp.doc()::text, pg_temp.doc('{"citation": "ZZ other"}')::text), '23514', 'terms is derived from terms_source');
SELECT pg_temp.refuses('D38: a document of another kind',
  replace(pg_temp.ins_sql('protected', 'crossed_meters', pg_temp.doc()), '''backbilling'', 1', '''zz_fee'', 1'), '23514', 'holds backbilling documents');
SELECT pg_temp.refuses('D39: a version that was never registered',
  replace(pg_temp.ins_sql('protected', 'crossed_meters', pg_temp.doc()), '''backbilling'', 1', '''backbilling'', 2'), '23503', 'is not a registered term schema');

SELECT pg_temp.refuses('D40: a priority past the chain''s length',
  pg_temp.ins_sql('protected', 'crossed_meters', pg_temp.doc('{"windows": {"adverse": [{"kind": "claimed_start", "priority": 9}], "favourable": []}}')), '23514', '/windows/adverse/0/priority: must be at most 8');
SELECT pg_temp.refuses('D41: a window of more terms than there are kinds and priorities',
  pg_temp.ins_sql('protected', 'crossed_meters', pg_temp.doc(format('{"windows": {"adverse": [%s], "favourable": []}}', (SELECT string_agg('{"kind": "service_start"}', ', ') FROM generate_series(1, 9)))::jsonb)),
  '23514', '/windows/adverse: at most 8 items');

-- ============================================================ O. overlap and applicability
SELECT pg_temp.refuses('O1: two rules for one class and cause, binding the same owners, overlapping in time',
  pg_temp.ins_sql('protected', 'meter_error', pg_temp.doc(), DATE '2021-01-01'), '23P01', 'backbilling_rules_rule_no_overlap');
SELECT pg_temp.does('O2: the same key for owners the first does not bind is no overlap (the city''s standards beside the investor-owned rule)',
  pg_temp.ins_sql('protected', 'meter_error', '{"governs": "delegated_to_utility", "citation": "ZZ Code 9"}'::jsonb, DATE '2020-01-01', NULL, '{municipal}'));
SELECT pg_temp.refuses('O3: … but not a rule for every owner type beside either of them',
  replace(pg_temp.ins_sql('protected', 'meter_error', pg_temp.doc(), DATE '2021-01-01'), '''{investor_owned}''', 'NULL'), '23P01', 'backbilling_rules_rule_no_overlap');
SELECT pg_temp.does('O4: the same key and owners after the first rule ends is its successor',
  pg_temp.ins_sql('other', 'meter_error', pg_temp.doc(), DATE '2020-01-01', DATE '2022-01-01'));
SELECT pg_temp.does('O5: … which starts where the first ends',
  pg_temp.ins_sql('other', 'meter_error', pg_temp.doc('{"citation": "ZZ 7.45 as amended"}'), DATE '2022-01-01'));
SELECT pg_temp.refuses('O9: a rule for cooperatives alone beside the sixteen overlaps them (a subset of the owner set is no escape)',
  replace(pg_temp.ins_sql('protected', 'meter_error', pg_temp.doc(), DATE '2021-01-01', NULL, '{cooperative}'), '''ZZ''', '''TX'''), '23P01', 'backbilling_rules_rule_no_overlap');
SELECT pg_temp.does('O10: a delegation for city-type owners beside the sixteen is the R2 shape and is accepted',
  replace(pg_temp.ins_sql('protected', 'meter_error', '{"governs": "delegated_to_utility", "citation": "Tex. Util. Code 101.003(7)(A)"}'::jsonb, DATE '2004-07-12', NULL,
                          '{municipal,political_subdivision,special_district}'), '''ZZ''', '''TX'''));
SELECT pg_temp.does('O11: … and a rule for master-meter systems (R9) is a new row beside the sixteen, not an edit',
  format($q$INSERT INTO public.backbilling_rules (state_code, service_type, customer_class, cause, owner_types, system_kinds, effective_from, source_note,
                                                  terms_kind, terms_version, terms_source)
            VALUES ('TX', 'gas', 'protected', 'meter_error', '{investor_owned}', '{master_meter}', DATE '2004-07-12', 'master meter rule', 'backbilling', 1, %L)$q$, pg_temp.doc()::text));
SELECT pg_temp.refuses('O6: a rule that ends where it starts',
  pg_temp.ins_sql('other', 'crossed_meters', pg_temp.doc(), DATE '2020-01-01', DATE '2020-01-01'), '23514', 'backbilling_rules_rule_range_check');
SELECT pg_temp.refuses('O7: an owner type nobody defined',
  pg_temp.ins_sql('other', 'crossed_meters', pg_temp.doc(), DATE '2020-01-01', NULL, '{lemonade_stand}'), '23503', 'lemonade_stand');
SELECT pg_temp.refuses('O8: a state no place records',
  replace(pg_temp.ins_sql('other', 'crossed_meters', pg_temp.doc()), '''ZZ''', '''QQ'''), '23503', 'is not a known state');

-- ============================================================ H. history, closes, grants
SELECT pg_temp.refuses('H1: a rule is never edited (its note)',
  $q$UPDATE public.backbilling_rules SET source_note = 'edited' WHERE state_code = 'TX' AND customer_class = 'protected' AND cause = 'meter_error'$q$, '23001', 'never edited');
SELECT pg_temp.refuses('H2: … nor its document',
  $q$UPDATE public.backbilling_rules SET terms_source = replace(terms_source, '"months"', '"days"') WHERE state_code = 'TX' AND customer_class = 'protected' AND cause = 'meter_error'$q$, '23001', 'never edited');
SELECT pg_temp.refuses('H3: … nor its applicability',
  $q$UPDATE public.backbilling_rules SET owner_types = NULL WHERE state_code = 'TX' AND customer_class = 'protected' AND cause = 'meter_error'$q$, '23001', 'never edited');
SELECT pg_temp.refuses('H4: a rule is never deleted',
  $q$DELETE FROM public.backbilling_rules WHERE state_code = 'ZZ' AND cause = 'meter_error' AND owner_types = '{investor_owned}'$q$, '23001', 'never deleted');
SELECT pg_temp.refuses('H5: the table is never truncated',
  $q$TRUNCATE public.backbilling_rules CASCADE$q$, '23001', NULL);
SELECT pg_temp.does('H6: a close is the one edit: the end date, once',
  $q$UPDATE public.backbilling_rules SET effective_to = DATE '2030-01-01' WHERE state_code = 'ZZ' AND customer_class = 'protected' AND cause = 'meter_error' AND owner_types = '{investor_owned}'$q$);
SELECT pg_temp.ok('H6b: … stamped with the closer and the time',
  (SELECT closed_at IS NOT NULL AND closed_by = session_user AND effective_to = DATE '2030-01-01'
     FROM public.backbilling_rules WHERE state_code = 'ZZ' AND customer_class = 'protected' AND cause = 'meter_error' AND owner_types = '{investor_owned}'));
SELECT pg_temp.refuses('H7: a second close',
  $q$UPDATE public.backbilling_rules SET effective_to = DATE '2031-01-01' WHERE state_code = 'ZZ' AND customer_class = 'protected' AND cause = 'meter_error' AND owner_types = '{investor_owned}'$q$, '23001', 'never edited');
SELECT pg_temp.refuses('H8: tally_app cannot write the law',
  $q$INSERT INTO public.backbilling_rules (state_code, service_type, customer_class, cause, effective_from, source_note) VALUES ('ZZ', 'gas', 'other', 'crossed_meters', DATE '2020-01-01', 'x')$q$,
  '42501', 'permission denied', 'tally_app', :'u2');
SELECT pg_temp.refuses('H9: … nor close it',
  $q$UPDATE public.backbilling_rules SET effective_to = DATE '2040-01-01' WHERE state_code = 'TX'$q$, '42501', 'permission denied', 'tally_app', :'u2');
SELECT pg_temp.ok('H10: tally_app and tally_core read the law and write none of it',
  has_table_privilege('tally_app', 'public.backbilling_rules', 'SELECT') AND has_table_privilege('tally_core', 'public.backbilling_rules', 'SELECT')
  AND NOT has_table_privilege('tally_app', 'public.backbilling_rules', 'INSERT, UPDATE, DELETE, TRUNCATE')
  AND NOT has_table_privilege('tally_core', 'public.backbilling_rules', 'INSERT, UPDATE, DELETE, TRUNCATE'));
SELECT pg_temp.ok('H11: the close floor of an uncited rule is nothing',
  public.backbilling_rule_close_floor((SELECT id FROM public.backbilling_rules WHERE state_code = 'TX' AND customer_class = 'protected' AND cause = 'meter_error' AND system_kinds = '{distribution}' AND owner_types @> '{cooperative}')) IS NULL);
-- The floor over planted citations (the citing tables' own guards and keys are battery-13's; here only the
-- dates the floor reads).
INSERT INTO b18 VALUES ('fl_eval', public.uuid_generate_v4()), ('fl_anchor', public.uuid_generate_v4()), ('fl_ev', public.uuid_generate_v4()), ('fl_both', public.uuid_generate_v4());
SELECT pg_temp.run($q$
  INSERT INTO public.backbilling_rules (id, state_code, service_type, customer_class, cause, owner_types, effective_from, source_note, terms_kind, terms_version, terms_source)
  SELECT pg_temp.id(k), 'ZZ', 'gas', 'other', c, '{investor_owned}', DATE '2020-01-01', 'floor rule', 'backbilling', 1, pg_temp.doc()::text
    FROM (VALUES ('fl_eval', 'estimation_catchup'), ('fl_anchor', 'rate_misapplication'), ('fl_ev', 'billing_constant_error'), ('fl_both', 'non_registering_meter')) v(k, c)$q$);
ALTER TABLE public.meter_correction_evaluations DISABLE TRIGGER ALL;
ALTER TABLE public.meter_correction_period_evidence DISABLE TRIGGER ALL;
-- an evaluation whose own date is later than its anchor; one whose anchor is later than its own date
INSERT INTO public.meter_correction_evaluations (id, tenant_id, case_id, cause, anchor_date, anchor_basis, rule_id, approval_required, inputs, inputs_fingerprint, calculated_by, evaluated_at) VALUES
  (public.uuid_generate_v4(), :'t2', public.uuid_generate_v4(), 'estimation_catchup', DATE '2025-03-01', 'discovery_date', pg_temp.id('fl_eval'),   false, '{}', 'fp', 'b18', TIMESTAMPTZ '2025-05-01 12:00+00'),
  (public.uuid_generate_v4(), :'t2', public.uuid_generate_v4(), 'rate_misapplication', DATE '2025-07-01', 'discovery_date', pg_temp.id('fl_anchor'), false, '{}', 'fp', 'b18', TIMESTAMPTZ '2025-05-01 12:00+00'),
  (public.uuid_generate_v4(), :'t2', public.uuid_generate_v4(), 'non_registering_meter', DATE '2025-02-01', 'discovery_date', pg_temp.id('fl_both'), false, '{}', 'fp', 'b18', TIMESTAMPTZ '2025-04-01 12:00+00');
INSERT INTO public.meter_correction_period_evidence (tenant_id, evaluation_id, invoice_id, customer_id, period_start, period_end, customer_class, rule_id, direction, correction_amount, disposition, days_in_window) VALUES
  (:'t2', public.uuid_generate_v4(), public.uuid_generate_v4(), public.uuid_generate_v4(), DATE '2025-09-01', DATE '2025-09-30', 'other', pg_temp.id('fl_ev'),   'customer_owes', 1, 'included', 30),
  (:'t2', public.uuid_generate_v4(), public.uuid_generate_v4(), public.uuid_generate_v4(), DATE '2025-11-01', DATE '2025-11-30', 'other', pg_temp.id('fl_both'), 'customer_owes', 1, 'included', 30);
ALTER TABLE public.meter_correction_evaluations ENABLE TRIGGER ALL;
ALTER TABLE public.meter_correction_period_evidence ENABLE TRIGGER ALL;
SELECT pg_temp.ok('H12: an evaluation cites its rule for the later of its anchor and its own date (the later its own date)',
  public.backbilling_rule_close_floor(pg_temp.id('fl_eval')) = DATE '2025-05-01');
SELECT pg_temp.ok('H13: … (the later its anchor)', public.backbilling_rule_close_floor(pg_temp.id('fl_anchor')) = DATE '2025-07-01');
SELECT pg_temp.ok('H14: an evidence row cites its rule for its period start', public.backbilling_rule_close_floor(pg_temp.id('fl_ev')) = DATE '2025-09-01');
SELECT pg_temp.ok('H15: a rule cited by both is held to the latest of them', public.backbilling_rule_close_floor(pg_temp.id('fl_both')) = DATE '2025-11-01');
SELECT pg_temp.refuses('H16: a close on the floor is refused, naming the date a citation needs',
  $q$UPDATE public.backbilling_rules SET effective_to = DATE '2025-11-01' WHERE id = pg_temp.id('fl_both')$q$, '23514', 'a citing record needs it in force on 2025-11-01');
SELECT pg_temp.refuses('H17: … and so is a day well before it',
  $q$UPDATE public.backbilling_rules SET effective_to = DATE '2025-10-15' WHERE id = pg_temp.id('fl_both')$q$, '23514', 'a citing record needs it in force on 2025-11-01');
SELECT pg_temp.refuses('H18: an evaluation''s own date holds its rule in force that day',
  $q$UPDATE public.backbilling_rules SET effective_to = DATE '2025-05-01' WHERE id = pg_temp.id('fl_eval')$q$, '23514', 'a citing record needs it in force on 2025-05-01');
SELECT pg_temp.refuses('H19: … and an anchor later than that date holds it, whatever the evaluation date',
  $q$UPDATE public.backbilling_rules SET effective_to = DATE '2025-06-30' WHERE id = pg_temp.id('fl_anchor')$q$, '23514', 'a citing record needs it in force on 2025-07-01');
SELECT pg_temp.does('H20: the day after the floor closes it',
  $q$UPDATE public.backbilling_rules SET effective_to = DATE '2025-07-02' WHERE id = pg_temp.id('fl_anchor')$q$);

-- ============================================================ X. the area's insert check
SELECT pg_temp.refuses('X1: a kind named twice in one direction (-13''s unique (rule, direction, kind))',
  pg_temp.ins_sql('other', 'unbilled_service', pg_temp.doc('{"windows": {"adverse": [{"kind": "before_anchor", "quantity": 6, "unit": "months"}, {"kind": "before_anchor", "quantity": 3, "unit": "months"}], "favourable": []}}')),
  '23514', 'names the window-term kind before_anchor twice');
SELECT pg_temp.does('X2: … a kind in each direction is one term each',
  pg_temp.ins_sql('other', 'unbilled_service', pg_temp.doc('{"windows": {"adverse": [{"kind": "before_anchor", "quantity": 6, "unit": "months"}], "favourable": [{"kind": "before_anchor", "quantity": 3, "unit": "months"}]}}')));
SELECT pg_temp.refuses('X3: a priority used twice in one direction (-13''s unique (rule, direction, priority))',
  pg_temp.ins_sql('other', 'tampering_bypass', pg_temp.doc('{"windows": {"adverse": [{"kind": "claimed_start", "priority": 1}, {"kind": "half_since_last_test", "priority": 1}], "favourable": []}}')),
  '23514', 'uses priority 1 twice');
SELECT pg_temp.does('X4: a fallback chain of distinct priorities beside unprioritised terms is the documented shape',
  pg_temp.ins_sql('other', 'tampering_bypass', pg_temp.doc('{"windows": {"adverse": [{"kind": "before_anchor", "quantity": 24, "unit": "months"}, {"kind": "claimed_start", "priority": 1}, {"kind": "half_since_last_test", "priority": 2}], "favourable": []}}')));
SELECT pg_temp.refuses('X7: a window listing its terms out of the canonical order (kind, byte order): one law, one document',
  pg_temp.ins_sql('other', 'crossed_meters', pg_temp.doc('{"windows": {"adverse": [{"kind": "service_start"}, {"kind": "claimed_start"}], "favourable": []}}')),
  '23514', 'out of order');
SELECT pg_temp.does('X8: … in order, they are written',
  pg_temp.ins_sql('other', 'crossed_meters', pg_temp.doc('{"windows": {"adverse": [{"kind": "claimed_start"}, {"kind": "service_start"}], "favourable": [{"kind": "last_test_accurate"}, {"kind": "last_test_any_outcome"}]}}')));
SELECT pg_temp.refuses('X9: … in the favourable direction as well (a kind named twice)',
  pg_temp.ins_sql('other', 'unbilled_service', pg_temp.doc('{"windows": {"adverse": [], "favourable": [{"kind": "service_start"}, {"kind": "service_start"}]}}')),
  '23514', 'the favourable window names the window-term kind service_start twice');
SELECT pg_temp.refuses('X10: … (a priority used twice)',
  pg_temp.ins_sql('other', 'unbilled_service', pg_temp.doc('{"windows": {"adverse": [], "favourable": [{"kind": "claimed_start", "priority": 2}, {"kind": "service_start", "priority": 2}]}}')),
  '23514', 'the favourable window uses priority 2 twice');
SELECT pg_temp.refuses('X11: … (out of order)',
  pg_temp.ins_sql('other', 'unbilled_service', pg_temp.doc('{"windows": {"adverse": [], "favourable": [{"kind": "service_start"}, {"kind": "claimed_start"}]}}')),
  '23514', 'the favourable window lists its terms out of order');
SELECT pg_temp.refuses('X12: qualifying outcomes listed out of byte order (a seed restating the law in another order would differ)',
  pg_temp.ins_sql('other', 'crossed_meters', pg_temp.doc('{"anchor": {"strategy": "test_date", "version": 1, "qualifying_outcomes": ["slow", "fast"]}}')),
  '23514', 'qualifying outcomes are listed out of order');
SELECT pg_temp.does('X13: … in byte order they are written',
  pg_temp.ins_sql('protected', 'crossed_meters', pg_temp.doc('{"anchor": {"strategy": "test_date", "version": 1, "qualifying_outcomes": ["fast", "non_registering", "slow"]}}')));
-- The basis vocabulary says whether a basis rests on a test; the document must agree (a vocabulary
-- row altered under the schema's feet is caught where the rule is written, not at a case).
ALTER TABLE public.backbilling_anchor_bases DISABLE TRIGGER USER;
UPDATE public.backbilling_anchor_bases SET rests_on_test = false WHERE basis_code = 'test_date';
SELECT pg_temp.refuses('X5: a test-date rule when the vocabulary says that basis rests on no test',
  pg_temp.ins_sql('other', 'billing_constant_error', pg_temp.doc('{"anchor": {"strategy": "test_date", "version": 1, "qualifying_outcomes": ["fast"]}}')),
  '23514', 'rests_on_test');
UPDATE public.backbilling_anchor_bases SET rests_on_test = true WHERE basis_code = 'test_date';
UPDATE public.backbilling_anchor_bases SET rests_on_test = true WHERE basis_code = 'discovery_date';
SELECT pg_temp.refuses('X6: … and a discovery-date rule when the vocabulary says that basis rests on a test',
  pg_temp.ins_sql('other', 'billing_constant_error', pg_temp.doc()), '23514', 'rests_on_test');
UPDATE public.backbilling_anchor_bases SET rests_on_test = false WHERE basis_code = 'discovery_date';
ALTER TABLE public.backbilling_anchor_bases ENABLE TRIGGER USER;

-- ============================================================ L. lookups
SELECT pg_temp.ok('L1: an investor-owned Texas utility''s protected meter-error rule is the adopted row',
  public.rule_law_row_as_of('public.backbilling_rules', :'t2', 'gas', 'distribution', 'TX', '{"customer_class": "protected", "cause": "meter_error"}', DATE '2026-01-15')
  = (SELECT id FROM public.backbilling_rules WHERE state_code = 'TX' AND customer_class = 'protected' AND cause = 'meter_error' AND system_kinds = '{distribution}' AND owner_types @> '{cooperative}'));
SELECT pg_temp.refuses('L2: a city-owned system finds no Texas rule: 16 TAC 7.45 does not bind it, and unknown law is not permission',
  format($q$SELECT public.rule_law_row_as_of('public.backbilling_rules', %L, 'gas', 'distribution', 'TX', '{"customer_class": "protected", "cause": "crossed_meters"}', DATE '2026-01-15')$q$, :'t1'),
  'P0002', 'no law in backbilling_rules binds a municipal gas utility');
SELECT pg_temp.refuses('L3: nor before the rule''s first day',
  format($q$SELECT public.rule_law_row_as_of('public.backbilling_rules', %L, 'gas', 'distribution', 'TX', '{"customer_class": "protected", "cause": "meter_error"}', DATE '2004-07-11')$q$, :'t2'),
  'P0002', 'no law in backbilling_rules binds');
SELECT pg_temp.refuses('L4: a key that is not the area''s key (class alone)',
  format($q$SELECT public.rule_law_row_as_of('public.backbilling_rules', %L, 'gas', 'distribution', 'TX', '{"customer_class": "protected"}', DATE '2026-01-15')$q$, :'t2'),
  '22023', NULL);

SELECT pg_temp.ok('L5: a cooperative (outside the commission''s jurisdiction) is bound by the same row as an investor-owned utility',
  public.rule_law_row_as_of('public.backbilling_rules', :'t3', 'gas', 'distribution', 'TX', '{"customer_class": "protected", "cause": "meter_error"}', DATE '2026-01-15')
  = public.rule_law_row_as_of('public.backbilling_rules', :'t2', 'gas', 'distribution', 'TX', '{"customer_class": "protected", "cause": "meter_error"}', DATE '2026-01-15'));
SELECT pg_temp.refuses('L6: a piped-propane system (LPG distribution is outside 101.003(7)) finds no Texas rule',
  format($q$SELECT public.rule_law_row_as_of('public.backbilling_rules', %L, 'gas', 'piped_propane_distribution', 'TX', '{"customer_class": "protected", "cause": "crossed_meters"}', DATE '2026-01-15')$q$, :'t4'),
  'P0002', 'no law in backbilling_rules binds');
SELECT pg_temp.refuses('L7: … nor a master-meter system, by default',
  format($q$SELECT public.rule_law_row_as_of('public.backbilling_rules', %L, 'gas', 'master_meter', 'TX', '{"customer_class": "protected", "cause": "crossed_meters"}', DATE '2026-01-15')$q$, :'t5'),
  'P0002', 'no law in backbilling_rules binds');
SELECT pg_temp.ok('L8: an unprotected-class case resolves to a delegation: the law leaves it to the utility (R10)',
  (SELECT terms ->> 'governs' = 'delegated_to_utility' FROM public.backbilling_rules
    WHERE id = public.rule_law_row_as_of('public.backbilling_rules', :'t2', 'gas', 'distribution', 'TX', '{"customer_class": "unprotected", "cause": "meter_error"}', DATE '2026-01-15')));
SELECT pg_temp.ok('L9: a city-type owner resolves to the delegation written for it (O10)',
  (SELECT terms ->> 'citation' = 'Tex. Util. Code 101.003(7)(A)' FROM public.backbilling_rules
    WHERE id = public.rule_law_row_as_of('public.backbilling_rules', :'t1', 'gas', 'distribution', 'TX', '{"customer_class": "protected", "cause": "meter_error"}', DATE '2026-01-15')));

-- ============================================================ G. the neighbours
SELECT pg_temp.does('G1: the tenant-isolation tail still passes', $q$SELECT public.assert_tenant_isolation_invariants()$q$);
SELECT pg_temp.does('G2: the core role''s invariants still hold', $q$SELECT public.assert_core_role_invariants()$q$);
SELECT pg_temp.ok('G3: the evaluations and evidence of -13 still cite a rule by foreign key',
  EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public.meter_correction_evaluations'::regclass AND confrelid = 'public.backbilling_rules'::regclass)
  AND EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public.meter_correction_period_evidence'::regclass AND confrelid = 'public.backbilling_rules'::regclass));

SELECT pg_temp.ok('G4: nothing in the catalogue still names a dropped column of backbilling_rules or a dropped table (every comment, every function body but the adoption check''s)',
  NOT EXISTS (SELECT 1 FROM pg_description d WHERE d.description ~ 'backbilling_rules\.(qualifying_test_outcomes|favourable_duty|adverse_straddle|favourable_straddle|delivery_path|requires_supervisor_evidence|units_invariant|enforce_scope|enforce_months|enforce_condition)'
                 OR d.description ~ 'backbilling_rule_window_terms|backbilling_window_term_kinds|backbilling_enforce_conditions|rule''s enforce_scope')
  AND NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                   WHERE n.nspname = 'public' AND p.proname <> 'backbilling_rule_adoption_check'
                     AND p.prosrc ~ 'backbilling_rule_window_terms|backbilling_window_term_kinds|backbilling_enforce_conditions|backbilling_rules\.(enforce_scope|qualifying_test_outcomes)'));
SELECT pg_temp.ok('G5: the hooks are the template''s to call: neither the application nor the core may',
  NOT has_function_privilege('tally_app', 'public.backbilling_rule_close_floor(uuid)', 'EXECUTE')
  AND NOT has_function_privilege('tally_core', 'public.backbilling_rule_close_floor(uuid)', 'EXECUTE')
  AND NOT has_function_privilege('tally_app', 'public.backbilling_rule_insert_check(jsonb)', 'EXECUTE')
  AND NOT has_function_privilege('tally_core', 'public.backbilling_rule_insert_check(jsonb)', 'EXECUTE')
  AND NOT has_function_privilege('tally_app', 'public.backbilling_rule_adoption_check(jsonb)', 'EXECUTE')
  AND NOT has_function_privilege('tally_core', 'public.backbilling_rule_adoption_check(jsonb)', 'EXECUTE'));
SELECT pg_temp.ok('G7: the basis vocabulary''s comment says a new basis needs a new schema version',
  (SELECT description LIKE '%a new schema version of the kind%' FROM pg_description WHERE objoid = 'public.backbilling_anchor_bases'::regclass AND objsubid = 0));
SELECT pg_temp.ok('G6: the migration''s builder is gone', to_regprocedure('public.backbilling_rule_legacy_document(uuid)') IS NULL);

ROLLBACK;
