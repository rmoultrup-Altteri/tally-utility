-- ============================================================================
-- BATTERY v5.4.2-15 (rewrite) — deposits at the rule-terms convention
--   (2026-10-12; first slice: the LAW side. Written before the patch exists.)
-- Run: psql -U tally -d <db-with-patch> -v ON_ERROR_STOP=1 -f battery-15r.sql
-- One transaction, rolled back. Negative cases go through pg_temp.refuses(),
-- which runs the statement (as a role and user when given), requires the
-- named SQLSTATE AND a phrase of the named guard's own message — a refusal by
-- a different guard is a failure, not a pass.
--
-- This replaces battery-15.sql (the first draft's, on typed columns and child
-- tables). Its record-side groups (deposits, accruals, the return-due record,
-- tenancy) return in later slices, adapted to cite a law row, and a tariff
-- row when one applied.
--
--   S  the kind, its facets and its vocabularies
--   M  deposit_rules is a registered law table
--   K  the Texas rows say what -06 enforced (and the city rows delegate)
--   D  the document gate (the schema's refusals reach the table)
--   X  the area's insert check
--   C  the utility's own deposit categories, each mapped to a law class
--   N  never looser than the law
--   P  published values, and the interest floor (F)
--   R  a deposit cites the law row and the tariff row it was decided under
--
-- Planned, not yet written (design doc section 9): accruals citing the
-- utility's rate row; the return-due record; chronology and partial returns;
-- H, history, grants, tenancy and the template's invariants over both tables.
-- The first run is meant to FAIL: nothing here exists until the patch does.
-- ============================================================================
\set ON_ERROR_STOP 1
BEGIN;
SET CONSTRAINTS ALL IMMEDIATE;

CREATE TEMP TABLE b15r (k text PRIMARY KEY, id uuid);
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
CREATE FUNCTION pg_temp.does(p_label text, p_sql text) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE v_msg text;
BEGIN
  EXECUTE p_sql;
  RAISE NOTICE 'PASS %', p_label;
EXCEPTION WHEN OTHERS THEN
  GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
  RAISE EXCEPTION 'FAIL %: %', p_label, v_msg;
END $$;

-- ============================================================ fixtures
-- A fictional state, ZZ, with two customer classes, a waiver class, and the
-- trigger codes its documents use. The vocabularies are platform-held, so the
-- battery (the owner) writes them.
INSERT INTO public.places (kind_code, state_code, place_code, name, effective_from, source_note)
VALUES ('state', 'ZZ', 'ZZ', 'Zedland', DATE '1900-01-01', 'battery fixture: a fictional state');
INSERT INTO public.deposit_customer_classes (state_code, service_type, class_code, description, source_note) VALUES
  ('ZZ', 'gas', 'household', 'battery class', 'battery fixture'),
  ('ZZ', 'gas', 'business', 'battery class', 'battery fixture');
INSERT INTO public.deposit_waiver_classes (state_code, service_type, class_code, requires_certification, tariff_defined, description, source_note) VALUES
  ('ZZ', 'gas', 'elderly', false, false, 'battery waiver class', 'battery fixture'),
  ('ZZ', 'gas', 'tariff',  false, true,  'the utility''s own waivers', 'battery fixture');
INSERT INTO public.deposit_triggers (trigger_code, description) VALUES
  ('zz_late_history', 'battery trigger'), ('zz_nsf_history', 'battery trigger');

-- The published values the ZZ documents name (platform-held: the battery, the owner, registers them).
INSERT INTO public.rule_parameters (parameter_name, unit, scoped_by, value_min, value_max, description, source_note) VALUES
  ('zz_deposit_rate', 'annual_rate_fraction', '{state_code}', 0, 1, 'battery published rate', 'battery fixture'),
  ('zz_short',        'annual_rate_fraction', '{state_code}', 0, 1, 'battery published rate', 'battery fixture'),
  ('zz_long',         'annual_rate_fraction', '{state_code}', 0, 1, 'battery published rate', 'battery fixture');

-- doc(overrides): a valid ZZ document with fields replaced.
CREATE FUNCTION pg_temp.doc(p_over jsonb DEFAULT '{}') RETURNS jsonb LANGUAGE sql IMMUTABLE AS $$
  SELECT '{"governs": "law", "citation": "ZZ 1.1",
           "cap": {"strategy": "parts", "version": 1, "combinator": "single", "scope": "per_deposit",
                   "parts": [{"id": "c1", "kind": "fraction_of_annual_billing", "divisor": 6}]},
           "triggers": [{"id": "t1", "trigger_code": "zz_late_history", "guards": [],
                         "condition": {"kind": "count", "event": "late_payment", "at_least": 2,
                                       "window": {"unit": "months", "size": 12}, "consecutive": false, "exclude_disputed": false}}],
           "waivers": [{"id": "w1", "waiver_class": "elderly", "applies_to": {"kind": "any_trigger"},
                        "effect": {"kind": "excuse"}, "also_releases_held": false, "disqualified_by": {"kind": "none"}}],
           "interest": {"strategy": "bearing", "version": 1, "instruments": ["cash"],
                        "rate": {"kind": "published", "name": "zz_deposit_rate", "binding": "minimum", "by_hold": []},
                        "method": {"kind": "simple"}, "day_count": "actual_365", "hold": {"kind": "none"},
                        "credit": {"kind": "at_refund"}, "stops_on": ["refund"], "forfeited_on": [],
                        "penalty": {"kind": "none"}, "rounding": {"kind": "none"}},
           "return": [{"id": "r1", "when": {"reason": "account_closed"}, "instruments": ["cash"], "conditions": [],
                       "minimum_amount": {"kind": "none"}, "deadline": {"kind": "none"}, "hold_while": [], "vests": "unruled"}],
           "instalments": []}'::jsonb || p_over
$$;
-- ins_sql(class, basis, document, from, to, owners): the statement that writes a ZZ rule.
CREATE FUNCTION pg_temp.ins_sql(p_class text, p_basis text, p_doc jsonb, p_from date DEFAULT DATE '2020-01-01',
                                p_to date DEFAULT NULL, p_owners text DEFAULT '{investor_owned}') RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT format($q$INSERT INTO public.deposit_rules (state_code, service_type, customer_class, basis, owner_types, effective_from, effective_to,
                                                     source_note, terms_kind, terms_version, terms_source)
                   VALUES ('ZZ', 'gas', %L, %L, %L, %L, %L, 'battery rule', 'deposit', 1, %L)$q$,
                p_class, p_basis, p_owners, p_from, p_to, p_doc::text)
$$;

-- ============================================================ S. the kind, its facets and its vocabularies
-- r1:begin kind
SELECT pg_temp.ok('S1: deposit v1 is a registered, unfrozen law kind',
  (SELECT rule_role = 'law' AND accepts_new_rows FROM public.rule_term_schemas WHERE terms_kind = 'deposit' AND terms_version = 1));
SELECT pg_temp.ok('S2: the registered schema is the committed file (its hash is the CI-checked one)',
  (SELECT schema_hash ~ '^sha256:[0-9a-f]{64}$' AND jsonb_typeof(json_schema -> '$defs' -> 'law') = 'object'
          AND json_schema ->> '$id' = 'https://tally-utility/law/deposit/deposit.v1.schema.json'
     FROM public.rule_term_schemas WHERE terms_kind = 'deposit' AND terms_version = 1));
SELECT pg_temp.ok('S3: its facets are the trigger codes, waiver classes, return reasons and cap part ids the record guards read',
  (SELECT count(*) = 4 AND bool_and(facet_type = 'text[]')
          AND array_agg(facet_name ORDER BY facet_name) = ARRAY['cap_part_ids', 'return_reasons', 'trigger_codes', 'waiver_classes']
     FROM public.rule_term_facets WHERE terms_kind = 'deposit' AND terms_version = 1));
SELECT pg_temp.ok('S4: trigger codes, waiver classes and return reasons are checked against vocabulary tables; cap part ids are not (a record cites one)',
  (SELECT bool_and(CASE facet_name
            WHEN 'trigger_codes'  THEN vocabulary_table = 'deposit_triggers'       AND json_path = '$.triggers[*].trigger_code'
            WHEN 'waiver_classes' THEN vocabulary_table = 'deposit_waiver_classes' AND json_path = '$.waivers[*].waiver_class'
            WHEN 'return_reasons' THEN vocabulary_table = 'deposit_return_reasons' AND json_path = '$.return[*].when.reason'
            WHEN 'cap_part_ids'   THEN vocabulary_table IS NULL                    AND json_path = '$.cap.parts[*].id' END)
     FROM public.rule_term_facets WHERE terms_kind = 'deposit' AND terms_version = 1));
SELECT pg_temp.ok('S5: the vocabularies exist and hold every code the Texas rows and the schema name',
  (SELECT count(*) = 8 FROM public.deposit_return_reasons WHERE reason_code = ANY (ARRAY['clean_bill_history', 'account_closed', 'hold_term_elapsed',
     'customer_demand', 'days_after_disconnection', 'entered_waiver_class', 'excess_over_cap', 'excess_over_current_bill']))
  AND (SELECT count(*) = 5 FROM public.deposit_bases WHERE basis_code = ANY (ARRAY['credit_evaluation', 'additional_trigger', 'tariff', 'adequate_assurance_366', 'legacy_unknown']))
  AND EXISTS (SELECT 1 FROM public.deposit_triggers WHERE trigger_code = 'usage_doubled')
  AND (SELECT count(*) = 4 FROM public.deposit_waiver_classes WHERE state_code = 'TX' AND service_type = 'gas'));
SELECT pg_temp.ok('S6: the first draft''s typed columns and child tables are not in the database (they were never mirrored)',
  to_regclass('public.deposit_rule_cap_parts') IS NULL AND to_regclass('public.deposit_rule_trigger_thresholds') IS NULL
  AND to_regclass('public.deposit_rule_instalments') IS NULL AND to_regclass('public.deposit_rule_waiver_reach') IS NULL
  AND to_regclass('public.deposit_rule_refund_disqualifiers') IS NULL);
-- r1:end kind

-- ============================================================ M. deposit_rules is a registered law table
-- r2:begin table
SELECT pg_temp.ok('M1: deposit_rules is a registered law table on the deposit kind, keyed by class and basis, with its four facets, no adoption (no rows to adopt)',
  (SELECT rule_role = 'law' AND terms_kind = 'deposit' AND area_key = '{customer_class,basis}'
          AND facet_columns = '{cap_part_ids,return_reasons,trigger_codes,waiver_classes}'
          AND NOT adopts_legacy_rows AND insert_check IS NOT NULL AND close_floor IS NOT NULL
          AND law_table IS NULL AND compare_function IS NULL
     FROM public.rule_tables WHERE table_name = 'public.deposit_rules'::regclass));
SELECT pg_temp.ok('M2: the table has no content column of the first draft''s (cap_combinator, interest_method, refund_after_count …)',
  NOT EXISTS (SELECT 1 FROM pg_attribute a WHERE a.attrelid = 'public.deposit_rules'::regclass AND NOT a.attisdropped AND a.attnum > 0
                 AND a.attname = ANY (ARRAY['cap_combinator', 'cap_scope', 'interest_bearing_instruments', 'interest_min_hold_days', 'interest_retroactive',
                                            'interest_method', 'interest_day_count', 'interest_credit_cadence', 'refund_mandatory', 'refund_after_count',
                                            'refund_measure', 'refund_max_delinquencies', 'refund_on_account_close', 'refund_excess_over_cap'])));
SELECT pg_temp.ok('M3: the customer class and the basis are foreign keys into their vocabularies (class scoped by state and service)',
  EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public.deposit_rules'::regclass AND contype = 'f'
             AND confrelid = 'public.deposit_customer_classes'::regclass)
  AND EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public.deposit_rules'::regclass AND contype = 'f'
             AND confrelid = 'public.deposit_bases'::regclass));
SELECT pg_temp.ok('M4: the template''s three triggers stand on it, enabled always',
  (SELECT count(*) = 3 FROM pg_trigger WHERE tgrelid = 'public.deposit_rules'::regclass AND NOT tgisinternal
      AND tgname = ANY (ARRAY['rule_row_insert', 'rule_row_history', 'rule_row_no_truncate']) AND tgenabled = 'A'));
SELECT pg_temp.does('M5: the template''s invariants hold over the registered table', $q$SELECT public.assert_rule_table_invariants()$q$);
SELECT pg_temp.ok('M6: the -06 Texas deposit law is gone from the database (the core evaluates it): its functions and view',
  to_regprocedure('public.deposit_accrual_amount(uuid,date,date,numeric)') IS NULL
  AND to_regprocedure('public.deposit_interest_rate_as_of(uuid,date)') IS NULL
  AND to_regprocedure('public.deposit_refund_trigger_state(uuid,date)') IS NULL
  AND to_regclass('public.deposits_refund_due') IS NULL);
-- r2:end table

-- ============================================================ K. the Texas rows say what -06 enforced
-- r3:begin texas
-- The expected documents, built here from -06's truth table (class, basis, cap,
-- usage trigger, waivers, return), not read back from the patch.
CREATE TEMP TABLE k15 AS
SELECT c.customer_class, b.basis,
  CASE WHEN b.basis = 'adequate_assurance_366' THEN
    jsonb_build_object('governs', 'law', 'citation', '11 U.S.C. 366',
      'cap', '{"strategy": "none", "version": 1}'::jsonb, 'triggers', '[]'::jsonb, 'waivers', '[]'::jsonb,
      'interest', i.interest, 'return', '[]'::jsonb, 'instalments', '[]'::jsonb)
  ELSE
    jsonb_build_object('governs', 'law', 'citation', '16 TAC 7.45',
      'cap', CASE WHEN c.customer_class = 'residential'
                  THEN '{"strategy": "parts", "version": 1, "combinator": "single", "scope": "per_deposit",
                         "parts": [{"id": "c1", "kind": "fraction_of_annual_billing", "divisor": 6}]}'::jsonb
                  ELSE '{"strategy": "none", "version": 1}'::jsonb END,
      'triggers', CASE WHEN b.basis = 'additional_trigger'
                  THEN '[{"id": "t1", "trigger_code": "usage_doubled", "condition": {"kind": "ratio", "measure": "usage_to_estimate", "op": "at_least", "value": 2},
                          "guards": [{"kind": "payment_due_days", "days": 2}]}]'::jsonb ELSE '[]'::jsonb END,
      'waivers', (SELECT jsonb_agg(jsonb_build_object('id', 'w' || n, 'waiver_class', w, 'applies_to', '{"kind": "any_trigger"}'::jsonb,
                                  'effect', '{"kind": "excuse"}'::jsonb, 'also_releases_held', false, 'disqualified_by', '{"kind": "none"}'::jsonb) ORDER BY n)
                    FROM unnest(ARRAY['family_violence_certified', 'age_65_no_balance', 'good_payment_history', 'tariff']) WITH ORDINALITY AS x(w, n)),
      'interest', i.interest,
      'return', '[{"id": "r1", "instruments": ["cash"], "conditions": [], "minimum_amount": {"kind": "none"}, "deadline": {"kind": "none"}, "hold_while": [], "vests": "unruled",
                   "when": {"reason": "clean_bill_history", "count": 12, "measure": "bills", "max_delinquencies": 2, "lookback": {"kind": "whole_hold"},
                            "disqualifiers": ["disconnect_nonpayment"], "exclude_disputed": false}},
                  {"id": "r2", "instruments": ["cash"], "conditions": [], "minimum_amount": {"kind": "none"}, "deadline": {"kind": "none"}, "hold_while": [], "vests": "unruled",
                   "when": {"reason": "account_closed"}}]'::jsonb,
      'instalments', '[]'::jsonb) END AS doc
  FROM (VALUES ('residential'), ('non_residential')) AS c(customer_class)
  CROSS JOIN (VALUES ('credit_evaluation'), ('additional_trigger'), ('tariff'), ('adequate_assurance_366')) AS b(basis)
  CROSS JOIN (SELECT '{"strategy": "bearing", "version": 1, "instruments": ["cash"],
                       "rate": {"kind": "published", "name": "tx_deposit_interest_rate", "binding": "minimum", "by_hold": []},
                       "method": {"kind": "simple"}, "day_count": "actual_365", "hold": {"kind": "minimum", "days": 30, "retroactive": true},
                       "credit": {"kind": "at_refund"}, "stops_on": ["refund"], "forfeited_on": [],
                       "penalty": {"kind": "none"}, "rounding": {"kind": "none"}}'::jsonb AS interest) i;
SELECT pg_temp.ok('K1: eight expected documents', (SELECT count(*) = 8 FROM k15));
SELECT pg_temp.ok('K2: the investor-owned and cooperative Texas law rows hold exactly those documents',
  (SELECT count(*) = 8 AND bool_and(r.terms = k.doc)
     FROM k15 k JOIN public.deposit_rules r ON r.state_code = 'TX' AND r.service_type = 'gas' AND r.customer_class = k.customer_class
                                           AND r.basis = k.basis AND r.terms ->> 'governs' = 'law'));
SELECT pg_temp.ok('K3: they bind what 16 TAC 7.45 binds: investor-owned and cooperative owners, distribution systems, either jurisdiction status; from 2004-07-12, open-ended',
  (SELECT count(*) = 8 AND bool_and(owner_types @> '{investor_owned,cooperative}' AND owner_types <@ '{investor_owned,cooperative}'
                                    AND system_kinds = '{distribution}' AND commission_jurisdiction IS NULL
                                    AND effective_from = DATE '2004-07-12' AND effective_to IS NULL AND closed_at IS NULL)
     FROM public.deposit_rules WHERE state_code = 'TX' AND terms ->> 'governs' = 'law'));
SELECT pg_temp.ok('K4: a city-owned system gets a delegation for every class and basis: the law leaves deposits to its tariff (16 TAC 7.45 does not bind it)',
  (SELECT count(*) = 8 AND bool_and(terms ->> 'governs' = 'delegated_to_utility' AND owner_types = '{municipal}'
                                    AND cap_part_ids = '{}' AND trigger_codes = '{}' AND waiver_classes = '{}' AND return_reasons = '{}')
     FROM public.deposit_rules WHERE state_code = 'TX' AND service_type = 'gas' AND terms ->> 'governs' = 'delegated_to_utility'));
SELECT pg_temp.ok('K5: the facets are derived from the document: the usage trigger, the four waivers, both return reasons, the one cap part',
  (SELECT trigger_codes = '{usage_doubled}' AND waiver_classes = '{age_65_no_balance,family_violence_certified,good_payment_history,tariff}'
          AND return_reasons = '{account_closed,clean_bill_history}' AND cap_part_ids = '{c1}'
     FROM public.deposit_rules WHERE state_code = 'TX' AND customer_class = 'residential' AND basis = 'additional_trigger' AND terms ->> 'governs' = 'law'));
SELECT pg_temp.ok('K6: the federal basis has no waiver reaching it, no cap and no return; it still earns cash interest as -06 accrued it',
  (SELECT count(*) = 2 AND bool_and(waiver_classes = '{}' AND cap_part_ids = '{}' AND return_reasons = '{}' AND terms #>> '{interest,strategy}' = 'bearing')
     FROM public.deposit_rules WHERE state_code = 'TX' AND basis = 'adequate_assurance_366' AND terms ->> 'governs' = 'law'));
SELECT pg_temp.ok('K7: legacy_unknown has no rule row (the core refuses to decide one)',
  NOT EXISTS (SELECT 1 FROM public.deposit_rules WHERE basis = 'legacy_unknown'));
-- r3:end texas

-- ============================================================ D. the document gate
-- r4:begin gate
SELECT pg_temp.does('D0: a valid ZZ document is written (the helper''s base)', pg_temp.ins_sql('household', 'credit_evaluation', pg_temp.doc()));
SELECT pg_temp.ok('D0b: its facets were derived, not written',
  (SELECT trigger_codes = '{zz_late_history}' AND waiver_classes = '{elderly}' AND return_reasons = '{account_closed}' AND cap_part_ids = '{c1}'
     FROM public.deposit_rules WHERE state_code = 'ZZ' AND customer_class = 'household' AND basis = 'credit_evaluation'));
SELECT pg_temp.refuses('D1: a document with a section left out (a cap is written, even as unruled)',
  pg_temp.ins_sql('household', 'tariff', pg_temp.doc() - 'cap'), '23514', '/cap: required');
SELECT pg_temp.refuses('D2: an unknown section (recalculation is out of version 1, refused rather than dropped)',
  pg_temp.ins_sql('household', 'tariff', pg_temp.doc('{"recalculation": {"every_years": 3}}')), '23514', '/recalculation: unknown key');
SELECT pg_temp.refuses('D3: a sum cap',
  pg_temp.ins_sql('household', 'tariff', pg_temp.doc('{"cap": {"strategy": "parts", "version": 1, "combinator": "sum", "scope": "per_deposit", "parts": [{"id": "c1", "kind": "months_of_billing", "months": 1}]}}')),
  '23514', '/cap/combinator');
SELECT pg_temp.refuses('D4: a bill-anchored instalment',
  pg_temp.ins_sql('household', 'tariff', pg_temp.doc('{"instalments": [{"id": "i1", "fraction": 0.5, "days_after": 0, "anchor": "next_bill"}]}')), '23514', '/instalments/0/anchor: unknown key');
SELECT pg_temp.refuses('D5: a rate that does not say whether it binds (decision 4)',
  pg_temp.ins_sql('household', 'tariff', pg_temp.doc('{"interest": {"strategy": "bearing", "version": 1, "instruments": ["cash"],
      "rate": {"kind": "published", "name": "zz_deposit_rate", "by_hold": []}, "method": {"kind": "simple"}, "day_count": "actual_365",
      "hold": {"kind": "none"}, "credit": {"kind": "at_refund"}, "stops_on": ["refund"], "forfeited_on": [],
      "penalty": {"kind": "none"}, "rounding": {"kind": "none"}}}')), '23514', '/interest/rate/binding: required');
SELECT pg_temp.refuses('D6: a minimum hold with no word on retroactivity',
  pg_temp.ins_sql('household', 'tariff', pg_temp.doc('{"interest": {"strategy": "bearing", "version": 1, "instruments": ["cash"],
      "rate": {"kind": "published", "name": "zz_deposit_rate", "binding": "minimum", "by_hold": []}, "method": {"kind": "simple"}, "day_count": "actual_365",
      "hold": {"kind": "minimum", "days": 30}, "credit": {"kind": "at_refund"}, "stops_on": ["refund"], "forfeited_on": [],
      "penalty": {"kind": "none"}, "rounding": {"kind": "none"}}}')), '23514', '/interest/hold/retroactive: required');
SELECT pg_temp.refuses('D7: a condition the schema does not name',
  pg_temp.ins_sql('household', 'tariff', pg_temp.doc('{"triggers": [{"id": "t1", "trigger_code": "zz_late_history", "guards": [], "condition": {"kind": "xor_of", "of": []}}]}')),
  '23514', '/triggers/0/condition/kind');
SELECT pg_temp.refuses('D8: a document that is a delegation but carries law fields',
  pg_temp.ins_sql('household', 'tariff', '{"governs": "delegated_to_utility", "citation": "ZZ 1.1", "cap": {}}'::jsonb), '23514', '/cap: unknown key');
-- r4:end gate

-- ============================================================ X. the area's insert check
-- r5:begin insert-check
SELECT pg_temp.refuses('X1: a cap part kind named twice (a deposit names the part that governed by its kind)',
  pg_temp.ins_sql('business', 'credit_evaluation', pg_temp.doc('{"cap": {"strategy": "parts", "version": 1, "combinator": "lesser_of", "scope": "per_deposit",
     "parts": [{"id": "c1", "kind": "fraction_of_annual_billing", "divisor": 6}, {"id": "c2", "kind": "fraction_of_annual_billing", "divisor": 8}]}}')),
  '23514', 'names the cap part kind');
SELECT pg_temp.refuses('X2: a single cap with two parts',
  pg_temp.ins_sql('business', 'credit_evaluation', pg_temp.doc('{"cap": {"strategy": "parts", "version": 1, "combinator": "single", "scope": "per_deposit",
     "parts": [{"id": "c1", "kind": "fraction_of_annual_billing", "divisor": 6}, {"id": "c2", "kind": "months_of_billing", "months": 2}]}}')),
  '23514', 'a single cap has exactly one part');
SELECT pg_temp.refuses('X3: a lesser-of cap with one part',
  pg_temp.ins_sql('business', 'credit_evaluation', pg_temp.doc('{"cap": {"strategy": "parts", "version": 1, "combinator": "lesser_of", "scope": "per_deposit",
     "parts": [{"id": "c1", "kind": "fraction_of_annual_billing", "divisor": 6}]}}')),
  '23514', 'needs two or more parts');
SELECT pg_temp.refuses('X4: cap parts out of order (by kind, byte order: one law has one document)',
  pg_temp.ins_sql('business', 'credit_evaluation', pg_temp.doc('{"cap": {"strategy": "parts", "version": 1, "combinator": "lesser_of", "scope": "per_deposit",
     "parts": [{"id": "c1", "kind": "months_of_billing", "months": 2}, {"id": "c2", "kind": "fraction_of_annual_billing", "divisor": 6}]}}')),
  '23514', 'out of order');
SELECT pg_temp.refuses('X5: instalments whose fractions do not add up to one',
  pg_temp.ins_sql('business', 'credit_evaluation', pg_temp.doc('{"instalments": [{"id": "i1", "fraction": 0.5, "days_after": 0}, {"id": "i2", "fraction": 0.25, "days_after": 30}]}')),
  '23514', 'add up to exactly 1');
SELECT pg_temp.does('X5b: … and ones that do are written',
  pg_temp.ins_sql('business', 'credit_evaluation', pg_temp.doc('{"instalments": [{"id": "i1", "fraction": 0.5, "days_after": 0}, {"id": "i2", "fraction": 0.25, "days_after": 30}, {"id": "i3", "fraction": 0.25, "days_after": 60}]}')));
SELECT pg_temp.refuses('X6: instalments not in order of days',
  pg_temp.ins_sql('business', 'additional_trigger', pg_temp.doc('{"instalments": [{"id": "i1", "fraction": 0.5, "days_after": 30}, {"id": "i2", "fraction": 0.5, "days_after": 0}]}')),
  '23514', 'out of order');
SELECT pg_temp.refuses('X7: a trigger code the vocabulary does not know (the facet check)',
  pg_temp.ins_sql('business', 'additional_trigger', pg_temp.doc('{"triggers": [{"id": "t1", "trigger_code": "no_such_trigger", "guards": [],
     "condition": {"kind": "ratio", "measure": "usage_to_estimate", "op": "at_least", "value": 2}}]}')),
  '23514', 'no_such_trigger');
SELECT pg_temp.refuses('X8: a waiver class the state and service do not have',
  pg_temp.ins_sql('business', 'additional_trigger', pg_temp.doc('{"waivers": [{"id": "w1", "waiver_class": "age_65_no_balance", "applies_to": {"kind": "any_trigger"},
     "effect": {"kind": "excuse"}, "also_releases_held": false, "disqualified_by": {"kind": "none"}}]}')),
  '23514', 'age_65_no_balance');
SELECT pg_temp.refuses('X9: a waiver that reaches a trigger the document does not have',
  pg_temp.ins_sql('business', 'additional_trigger', pg_temp.doc('{"waivers": [{"id": "w1", "waiver_class": "elderly", "applies_to": {"kind": "trigger", "trigger_code": "zz_nsf_history"},
     "effect": {"kind": "excuse"}, "also_releases_held": false, "disqualified_by": {"kind": "none"}}]}')),
  '23514', 'reaches the trigger');
SELECT pg_temp.refuses('X10: a trigger code used by two triggers',
  pg_temp.ins_sql('business', 'additional_trigger', pg_temp.doc('{"triggers": [
     {"id": "t1", "trigger_code": "zz_late_history", "guards": [], "condition": {"kind": "ratio", "measure": "usage_to_estimate", "op": "at_least", "value": 2}},
     {"id": "t2", "trigger_code": "zz_late_history", "guards": [], "condition": {"kind": "ratio", "measure": "usage_to_estimate", "op": "at_least", "value": 3}}]}')),
  '23514', 'names the trigger code');
SELECT pg_temp.refuses('X11: a return rule on entering a waiver class the document does not have',
  pg_temp.ins_sql('business', 'additional_trigger', pg_temp.doc('{"return": [{"id": "r1", "when": {"reason": "entered_waiver_class", "waiver_class": "tariff"}, "instruments": ["cash"],
     "conditions": [], "minimum_amount": {"kind": "none"}, "deadline": {"kind": "none"}, "hold_while": [], "vests": "unruled"}]}')),
  '23514', 'entering the waiver class');
SELECT pg_temp.refuses('X12: a return reason used by two return rules',
  pg_temp.ins_sql('business', 'additional_trigger', pg_temp.doc('{"return": [
     {"id": "r1", "when": {"reason": "account_closed"}, "instruments": ["cash"], "conditions": [], "minimum_amount": {"kind": "none"}, "deadline": {"kind": "none"}, "hold_while": [], "vests": "unruled"},
     {"id": "r2", "when": {"reason": "account_closed"}, "instruments": ["cash"], "conditions": [], "minimum_amount": {"kind": "none"}, "deadline": {"kind": "none"}, "hold_while": [], "vests": "unruled"}]}')),
  '23514', 'names the return reason');
SELECT pg_temp.refuses('X13: rate-by-hold thresholds not strictly ascending',
  pg_temp.ins_sql('business', 'additional_trigger', pg_temp.doc('{"interest": {"strategy": "bearing", "version": 1, "instruments": ["cash"],
      "rate": {"kind": "published", "name": "zz_deposit_rate", "binding": "minimum",
               "by_hold": [{"up_to_months": 24, "name": "zz_long"}, {"up_to_months": 12, "name": "zz_short"}]},
      "method": {"kind": "simple"}, "day_count": "actual_365", "hold": {"kind": "none"}, "credit": {"kind": "at_refund"}, "stops_on": ["refund"],
      "forfeited_on": [], "penalty": {"kind": "none"}, "rounding": {"kind": "none"}}}')),
  '23514', 'by_hold');
-- r5:end insert-check


-- ============================================================ utility fixtures
-- T1 runs a city-owned Texas gas system (the law delegates), T2 an investor-owned one (16 TAC 7.45 binds it).
INSERT INTO public.tenants (id, name, slug) VALUES
  ('00000000-0000-4000-8000-0000000015a1', 'T1 City Gas', 'bat15r-t1'),
  ('00000000-0000-4000-8000-0000000015a2', 'T2 Gasco', 'bat15r-t2');
INSERT INTO public.users (id, tenant_id, display_name, email, role) VALUES
  ('00000000-0000-4000-8000-0000000015b1', '00000000-0000-4000-8000-0000000015a1', 'Op1', 'op1@bat15r.test', 'operator'),
  ('00000000-0000-4000-8000-0000000015b2', '00000000-0000-4000-8000-0000000015a2', 'Op2', 'op2@bat15r.test', 'operator');
\set u1 '00000000-0000-4000-8000-0000000015b1'
\set u2 '00000000-0000-4000-8000-0000000015b2'
\set t1 '00000000-0000-4000-8000-0000000015a1'
\set t2 '00000000-0000-4000-8000-0000000015a2'
INSERT INTO b15r SELECT 'tx', id FROM public.places WHERE kind_code = 'state' AND place_code = 'TX';
INSERT INTO public.places (kind_code, state_code, place_code, name, parent_place_id, effective_from, source_note)
VALUES ('municipality', 'TX', 'BAT15CITY', 'Battery City', (SELECT id FROM b15r WHERE k = 'tx'), DATE '1950-01-01', 'battery fixture');
INSERT INTO b15r SELECT 'city', id FROM public.places WHERE kind_code = 'municipality' AND place_code = 'BAT15CITY';
SELECT pg_temp.run(format($q$
  INSERT INTO public.utility_service_profiles (tenant_id, service_type, system_kind, state_code, owner_type, commission_jurisdiction,
                                               owning_place_id, effective_from, evidence_reference, evidence_date)
  VALUES (%L, 'gas', 'distribution', 'TX', 'municipal', false, %L, DATE '2000-01-01', 'Battery City charter', DATE '2000-01-01')$q$,
  :'t1', (SELECT id FROM b15r WHERE k = 'city')), 'tally_app', :'u1');
SELECT pg_temp.run(format($q$
  INSERT INTO public.utility_service_profiles (tenant_id, service_type, system_kind, state_code, owner_type, commission_jurisdiction,
                                               effective_from, evidence_reference, evidence_date)
  VALUES (%L, 'gas', 'distribution', 'TX', 'investor_owned', true, DATE '2000-01-01', 'RRC certificate bat15r', DATE '2000-01-01')$q$,
  :'t2'), 'tally_app', :'u2');
-- cat_sql(tenant, category, law class): a utility's own category, mapped to a law class.
CREATE FUNCTION pg_temp.cat_sql(p_tenant text, p_cat text, p_law text, p_state text DEFAULT 'TX') RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT format($q$INSERT INTO public.deposit_utility_categories (tenant_id, state_code, service_type, category_code, law_class, description)
                   VALUES (%L, %L, 'gas', %L, %L, 'battery category')$q$, p_tenant, p_state, p_cat, p_law)
$$;
-- tar_sql(tenant, system kind, category, tariff document, from, to): a tariff record in the utility's own category.
CREATE FUNCTION pg_temp.tar_sql(p_tenant text, p_cat text, p_doc jsonb, p_from date DEFAULT DATE '2020-01-01', p_to date DEFAULT NULL) RETURNS text
LANGUAGE sql IMMUTABLE AS $$
  SELECT format($q$INSERT INTO public.deposit_tariffs (tenant_id, state_code, service_type, system_kind, tariff_category, effective_from, effective_to,
                                                       tariff_reference, terms_kind, terms_version, terms_source)
                   VALUES (%L, 'TX', 'gas', 'distribution', %L, %L, %L, 'battery tariff', 'deposit_tariff', 1, %L)$q$,
                p_tenant, p_cat, p_from, p_to, p_doc::text)
$$;
-- tdoc(overrides): a valid tariff document with fields replaced.
CREATE FUNCTION pg_temp.tdoc(p_over jsonb DEFAULT '{}') RETURNS jsonb LANGUAGE sql IMMUTABLE AS $$
  SELECT '{"citation": "Battery tariff, deposits", "amount": {"strategy": "fixed", "version": 1, "amount": 150},
           "triggers": [], "waivers": [], "instalments": []}'::jsonb || p_over
$$;

-- does_as(label, tenant, sql): the statement must succeed as that utility's operator (role tally_app, its user).
CREATE FUNCTION pg_temp.does_as(p_label text, p_tenant text, p_sql text) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE v_msg text; v_user text;
BEGIN
  SELECT id::text INTO v_user FROM public.users WHERE tenant_id = p_tenant::uuid ORDER BY id LIMIT 1;
  PERFORM set_config('app.user_id', v_user, true);
  SET LOCAL ROLE tally_app;
  EXECUTE p_sql;
  RESET ROLE;
  RAISE NOTICE 'PASS %', p_label;
EXCEPTION WHEN OTHERS THEN
  GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
  RESET ROLE;
  RAISE EXCEPTION 'FAIL %: %', p_label, v_msg;
END $$;
-- count_as(sql, role, user): how many rows a query returns to that role and user.
CREATE FUNCTION pg_temp.count_as(p_sql text, p_role text, p_user text) RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE v bigint;
BEGIN
  PERFORM set_config('app.user_id', p_user, true);
  EXECUTE format('SET LOCAL ROLE %I', p_role);
  EXECUTE format('SELECT count(*) FROM (%s) q', p_sql) INTO v;
  RESET ROLE;
  RETURN v;
END $$;

-- ============================================================ C. the utility's own deposit categories
-- r6:begin categories
SELECT pg_temp.does_as('C1: a city writes its own categories, each mapped to a law class', :'t1', pg_temp.cat_sql(:'t1', 'homeowner', 'residential'));
SELECT pg_temp.run(pg_temp.cat_sql(:'t1', 'renter', 'residential'), 'tally_app', :'u1');
SELECT pg_temp.run(pg_temp.cat_sql(:'t1', 'small_commercial', 'non_residential'), 'tally_app', :'u1');
SELECT pg_temp.run(pg_temp.cat_sql(:'t2', 'residential', 'residential'), 'tally_app', :'u2');
SELECT pg_temp.ok('C2: the category table is tenant-owned under row security: a utility sees its own categories only',
  (SELECT relrowsecurity AND relforcerowsecurity FROM pg_class WHERE oid = 'public.deposit_utility_categories'::regclass)
  AND has_table_privilege('tally_app', 'public.deposit_utility_categories', 'INSERT'));
SELECT pg_temp.refuses('C3: a category mapped to a law class the state and service do not have',
  pg_temp.cat_sql(:'t1', 'church', 'religious'), '23503', 'deposit_utility_categories_law_class_fkey', 'tally_app', :'u1');
SELECT pg_temp.refuses('C4: a category written for another utility (row security)',
  pg_temp.cat_sql(:'t2', 'sneaky', 'residential'), '42501', NULL, 'tally_app', :'u1');
SELECT pg_temp.refuses('C5: the same category twice for one utility, state and service',
  pg_temp.cat_sql(:'t1', 'renter', 'residential'), '23505', NULL, 'tally_app', :'u1');
SELECT pg_temp.refuses('C6: a category code that is not a code (blank, capitals, spaces)',
  pg_temp.cat_sql(:'t1', 'Home Owner', 'residential'), '23514', NULL, 'tally_app', :'u1');
SELECT pg_temp.refuses('C7: a category''s law class is never changed: tariffs and deposits cite it',
  format($q$UPDATE public.deposit_utility_categories SET law_class = 'non_residential' WHERE tenant_id = %L AND category_code = 'renter'$q$, :'t1'),
  '23001', 'never edited', 'tally_app', :'u1');
SELECT pg_temp.refuses('C8: … and is never deleted',
  format($q$DELETE FROM public.deposit_utility_categories WHERE tenant_id = %L AND category_code = 'renter'$q$, :'t1'),
  '23001', 'never deleted', 'tally_app', :'u1');
SELECT pg_temp.ok('C9: each utility sees its own categories and not another''s',
  pg_temp.count_as('SELECT 1 FROM public.deposit_utility_categories', 'tally_app', :'u1') = 3
  AND pg_temp.count_as('SELECT 1 FROM public.deposit_utility_categories', 'tally_app', :'u2') = 1);
-- r6:end categories

-- ============================================================ U. the utility's tariff record
-- r7:begin tariff
SELECT pg_temp.ok('U1: deposit_tariffs is a registered tariff table on the deposit_tariff kind, keyed by the utility''s own category, measured against deposit_rules',
  (SELECT rule_role = 'tariff' AND terms_kind = 'deposit_tariff' AND area_key = '{tariff_category}' AND law_table = 'public.deposit_rules'::regclass
          AND compare_function IS NOT NULL AND NOT adopts_legacy_rows
     FROM public.rule_tables WHERE table_name = 'public.deposit_tariffs'::regclass));
SELECT pg_temp.ok('U2: the tariff key does not share a column name with the law key (the utility''s categories are not the law''s classes); the comparator chooses the law rows',
  NOT EXISTS (SELECT 1 FROM pg_attribute a WHERE a.attrelid = 'public.deposit_tariffs'::regclass AND NOT a.attisdropped AND a.attname IN ('customer_class', 'basis')));
SELECT pg_temp.does_as('U3: a city writes a flat deposit for its homeowner category (its law row delegates: nothing to compare)', :'t1', pg_temp.tar_sql(:'t1', 'homeowner', pg_temp.tdoc()));
SELECT pg_temp.run(pg_temp.tar_sql(:'t1', 'renter', pg_temp.tdoc('{"amount": {"strategy": "fixed", "version": 1, "amount": 250}}')), 'tally_app', :'u1');
SELECT pg_temp.refuses('U4: a tariff for a category the utility has not defined',
  pg_temp.tar_sql(:'t1', 'landlord', pg_temp.tdoc()), '23514', 'landlord', 'tally_app', :'u1');
SELECT pg_temp.refuses('U5: a tariff for another utility''s category (the category is the writer''s own)',
  pg_temp.tar_sql(:'t2', 'residential', pg_temp.tdoc()), '42501', NULL, 'tally_app', :'u1');
SELECT pg_temp.refuses('U6: two tariff records for one category over the same dates',
  pg_temp.tar_sql(:'t1', 'homeowner', pg_temp.tdoc('{"amount": {"strategy": "fixed", "version": 1, "amount": 175}}')), '23P01', NULL, 'tally_app', :'u1');
SELECT pg_temp.does_as('U7: … and a successor from a later date is fine after the first is closed', :'t1',
  format($q$UPDATE public.deposit_tariffs SET effective_to = DATE '2024-01-01' WHERE tenant_id = %L AND tariff_category = 'homeowner'$q$, :'t1'));
SELECT pg_temp.run(pg_temp.tar_sql(:'t1', 'homeowner', pg_temp.tdoc('{"amount": {"strategy": "fixed", "version": 1, "amount": 175}}'), DATE '2024-01-01'), 'tally_app', :'u1');
SELECT pg_temp.ok('U8: the lookup finds the tariff in force for a category on a date, and none before the first',
  public.rule_tariff_row_as_of('public.deposit_tariffs', :'t1', 'gas', 'distribution', 'TX', '{"tariff_category": "homeowner"}', DATE '2025-06-01')
    IS DISTINCT FROM public.rule_tariff_row_as_of('public.deposit_tariffs', :'t1', 'gas', 'distribution', 'TX', '{"tariff_category": "homeowner"}', DATE '2022-06-01')
  AND public.rule_tariff_row_as_of('public.deposit_tariffs', :'t1', 'gas', 'distribution', 'TX', '{"tariff_category": "homeowner"}', DATE '2019-06-01') IS NULL);
SELECT pg_temp.refuses('U9: a tariff record is never edited (its document is what deposits cited)',
  format($q$UPDATE public.deposit_tariffs SET terms_source = %L WHERE tenant_id = %L AND tariff_category = 'renter'$q$, pg_temp.tdoc('{"amount": {"strategy": "fixed", "version": 1, "amount": 1}}')::text, :'t1'),
  '23001', NULL, 'tally_app', :'u1');
-- r7:end tariff

-- ============================================================ N. never looser than the law
-- The investor-owned utility's residential law cap is one-sixth of annual billing: two average months.
-- r8:begin never-looser
SELECT pg_temp.run(pg_temp.cat_sql(:'t2', 'residential_senior', 'residential'), 'tally_app', :'u2');
SELECT pg_temp.refuses('N1: a deposit of three average months where the law caps it at two',
  pg_temp.tar_sql(:'t2', 'residential', pg_temp.tdoc('{"amount": {"strategy": "months_of_billing", "version": 1, "months": 3, "of": "average", "minimum_amount": {"kind": "none"}}}')),
  '23514', 'looser than the law', 'tally_app', :'u2');
SELECT pg_temp.does_as('N2: … two average months, the law''s own figure, is not looser', :'t2', pg_temp.tar_sql(:'t2', 'residential', pg_temp.tdoc('{"amount": {"strategy": "months_of_billing", "version": 1, "months": 2, "of": "average", "minimum_amount": {"kind": "none"}}}'), DATE '2020-01-01', DATE '2021-01-01'));
SELECT pg_temp.run(pg_temp.tar_sql(:'t2', 'residential', pg_temp.tdoc('{"amount": {"strategy": "months_of_billing", "version": 1, "months": 1, "of": "average", "minimum_amount": {"kind": "none"}}}'), DATE '2021-01-01', DATE '2022-01-01'), 'tally_app', :'u2');
SELECT pg_temp.refuses('N3: a category is measured against the law class it maps to: three months for a senior sub-category of residential is held to the residential cap too',
  pg_temp.tar_sql(:'t2', 'residential_senior', pg_temp.tdoc('{"amount": {"strategy": "months_of_billing", "version": 1, "months": 3, "of": "average", "minimum_amount": {"kind": "none"}}}')),
  '23514', 'looser than the law', 'tally_app', :'u2');
SELECT pg_temp.does_as('N4: a flat amount cannot be compared with a billing fraction when it is written; it is accepted (each deposit records the cap that applied and its own check holds it to it)', :'t2', pg_temp.tar_sql(:'t2', 'residential_senior', pg_temp.tdoc('{"amount": {"strategy": "fixed", "version": 1, "amount": 5000}}')));
SELECT pg_temp.refuses('N5: a usage trigger that fires at one and a half times the estimate where the law waits for twice',
  pg_temp.tar_sql(:'t2', 'residential', pg_temp.tdoc('{"triggers": [{"id": "t1", "trigger_code": "usage_doubled", "guards": [],
     "condition": {"kind": "ratio", "measure": "usage_to_estimate", "op": "at_least", "value": 1.5}}]}'), DATE '2022-01-01', DATE '2023-01-01'),
  '23514', 'looser than the law', 'tally_app', :'u2');
SELECT pg_temp.does_as('N6: … three times the estimate, with five days to pay, is stricter than the law and is accepted', :'t2', pg_temp.tar_sql(:'t2', 'residential', pg_temp.tdoc('{"triggers": [{"id": "t1", "trigger_code": "usage_doubled", "guards": [{"kind": "payment_due_days", "days": 5}],
     "condition": {"kind": "ratio", "measure": "usage_to_estimate", "op": "at_least", "value": 3}}]}'), DATE '2022-01-01', DATE '2023-01-01'));
SELECT pg_temp.refuses('N7: … but one day to pay, where the law gives two, is looser',
  pg_temp.tar_sql(:'t2', 'residential', pg_temp.tdoc('{"triggers": [{"id": "t1", "trigger_code": "usage_doubled", "guards": [{"kind": "payment_due_days", "days": 1}],
     "condition": {"kind": "ratio", "measure": "usage_to_estimate", "op": "at_least", "value": 3}}]}'), DATE '2023-01-01', DATE '2024-01-01'),
  '23514', 'looser than the law', 'tally_app', :'u2');
SELECT pg_temp.does_as('N8: a trigger the law has no word on (a utility''s own NSF trigger) is the utility''s to set', :'t2', pg_temp.tar_sql(:'t2', 'residential', pg_temp.tdoc('{"triggers": [{"id": "t1", "trigger_code": "nsf", "guards": [],
     "condition": {"kind": "count", "event": "nsf", "at_least": 2, "window": {"unit": "months", "size": 12}, "consecutive": false, "exclude_disputed": false}}]}'), DATE '2024-01-01', DATE '2025-01-01'));
SELECT pg_temp.does_as('N9: a utility''s own waiver ground, in its own name, is accepted (the law holds only the permission)', :'t2', pg_temp.tar_sql(:'t2', 'residential', pg_temp.tdoc('{"waivers": [{"id": "w1", "ground": "military_deployment", "applies_to": {"kind": "any_trigger"},
     "effect": {"kind": "defer", "days": 90}, "also_releases_held": false, "disqualified_by": {"kind": "none"}}]}'), DATE '2025-01-01', DATE '2026-01-01'));
SELECT pg_temp.run(pg_temp.cat_sql(:'t2', 'commercial', 'non_residential'), 'tally_app', :'u2');
SELECT pg_temp.does_as('N10: a non-residential tariff of any months is accepted where the law sets no cap', :'t2', pg_temp.tar_sql(:'t2', 'commercial', pg_temp.tdoc('{"amount": {"strategy": "months_of_billing", "version": 1, "months": 6, "of": "highest", "minimum_amount": {"kind": "amount", "amount": 300}}}')));
SELECT pg_temp.refuses('N11: a tariff for a utility with no service profile in that state and service (unknown law is not permission)',
  format($q$INSERT INTO public.deposit_tariffs (tenant_id, state_code, service_type, system_kind, tariff_category, effective_from, tariff_reference, terms_kind, terms_version, terms_source)
            VALUES (%L, 'TX', 'water', 'distribution', 'residential', DATE '2020-01-01', 'x', 'deposit_tariff', 1, %L)$q$, :'t2', pg_temp.tdoc()::text),
  '23514', 'profile', 'tally_app', :'u2');
SELECT pg_temp.does('N12: the template''s invariants hold over both rule tables', $q$SELECT public.assert_rule_table_invariants()$q$);
-- r8:end never-looser


-- ============================================================ P. published values, the utility's rate, the floor
-- Decision 4: a state-set rate is a FLOOR the utility's own rate may not go below. The floor is read from the
-- published value the law row names; a rate that would go below it is refused when written; no published value in
-- force on the rate's date refuses it (unknown law is not permission); a city the law does not bind has no floor.
-- The battery registers fictional published values (platform-held, so the owner writes them).
INSERT INTO public.rule_parameter_values (parameter_name, state_code, service_type, effective_from, effective_to, value, source_note) VALUES
  ('tx_deposit_interest_rate', 'TX', NULL, DATE '2020-01-01', DATE '2024-01-01', 0.02, 'battery fixture, not a real publication'),
  ('tx_deposit_interest_rate', 'TX', NULL, DATE '2024-01-01', NULL,               0.04, 'battery fixture, not a real publication'),
  ('zz_deposit_rate', 'ZZ', NULL, DATE '2020-01-01', NULL, 0.03, 'battery fixture'),
  ('zz_short', 'ZZ', NULL, DATE '2020-01-01', NULL, 0.02, 'battery fixture'),
  ('zz_long',  'ZZ', NULL, DATE '2020-01-01', NULL, 0.04, 'battery fixture');
-- T3 runs a ZZ system: a household class whose law row names a fixed 5% floor, a business class whose law row names a rate only as a reference.
INSERT INTO public.tenants (id, name, slug) VALUES ('00000000-0000-4000-8000-0000000015a3', 'T3 Zed Gas', 'bat15r-t3');
INSERT INTO public.users (id, tenant_id, display_name, email, role) VALUES
  ('00000000-0000-4000-8000-0000000015b3', '00000000-0000-4000-8000-0000000015a3', 'Op3', 'op3@bat15r.test', 'operator');
\set u3 '00000000-0000-4000-8000-0000000015b3'
\set t3 '00000000-0000-4000-8000-0000000015a3'
SELECT pg_temp.run(format($q$
  INSERT INTO public.utility_service_profiles (tenant_id, service_type, system_kind, state_code, owner_type, commission_jurisdiction,
                                               effective_from, evidence_reference, evidence_date)
  VALUES (%L, 'gas', 'distribution', 'ZZ', 'investor_owned', true, DATE '2000-01-01', 'ZZ certificate bat15r', DATE '2000-01-01')$q$,
  :'t3'), 'tally_app', :'u3');
-- rate_sql(tenant, category, from, rate, state): a utility's own rate row (category NULL = every category).
CREATE FUNCTION pg_temp.rate_sql(p_tenant text, p_cat text, p_from date, p_rate numeric, p_state text DEFAULT 'TX') RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT format($q$INSERT INTO public.deposit_interest_rates (tenant_id, state_code, service_type, tariff_category, effective_date, annual_rate, source_reference)
                   VALUES (%L, %L, 'gas', %L, %L, %s, 'battery rate')$q$, p_tenant, p_state, p_cat, p_from, p_rate)
$$;

-- r9:begin published
SELECT pg_temp.ok('P1: the Texas deposit rate is a registered published parameter: an annual fraction, scoped by state, between 0 and 1',
  (SELECT unit = 'annual_rate_fraction' AND scoped_by = '{state_code}' AND value_min = 0 AND value_max = 1
     FROM public.rule_parameters WHERE parameter_name = 'tx_deposit_interest_rate'));
SELECT pg_temp.ok('P2: its value in force on a date is answered, and a date before the first publication has none (no fallback)',
  public.rule_parameter_value_as_of('tx_deposit_interest_rate', 'TX', NULL, DATE '2022-06-01') = 0.02
  AND public.rule_parameter_value_as_of('tx_deposit_interest_rate', 'TX', NULL, DATE '2025-06-01') = 0.04
  AND public.rule_parameter_value_as_of('tx_deposit_interest_rate', 'TX', NULL, DATE '2019-06-01') IS NULL);
SELECT pg_temp.refuses('P3: a utility cannot write a published value (platform-held)',
  $q$INSERT INTO public.rule_parameter_values (parameter_name, state_code, effective_from, value, source_note) VALUES ('tx_deposit_interest_rate', 'TX', DATE '2030-01-01', 0, 'x')$q$,
  '42501', NULL, 'tally_app');
SELECT pg_temp.refuses('P4: a law row cannot name a published rate that is not registered',
  pg_temp.ins_sql('household', 'tariff', pg_temp.doc('{"interest": {"strategy": "bearing", "version": 1, "instruments": ["cash"],
      "rate": {"kind": "published", "name": "no_such_rate", "binding": "minimum", "by_hold": []}, "method": {"kind": "simple"}, "day_count": "actual_365",
      "hold": {"kind": "none"}, "credit": {"kind": "at_refund"}, "stops_on": ["refund"], "forfeited_on": [],
      "penalty": {"kind": "none"}, "rounding": {"kind": "none"}}}')), '23514', 'no_such_rate');
SELECT pg_temp.refuses('P5: … or one in its by-hold list',
  pg_temp.ins_sql('household', 'tariff', pg_temp.doc('{"interest": {"strategy": "bearing", "version": 1, "instruments": ["cash"],
      "rate": {"kind": "published", "name": "zz_deposit_rate", "binding": "minimum", "by_hold": [{"up_to_months": 12, "name": "no_such_rate"}]},
      "method": {"kind": "simple"}, "day_count": "actual_365", "hold": {"kind": "none"}, "credit": {"kind": "at_refund"}, "stops_on": ["refund"],
      "forfeited_on": [], "penalty": {"kind": "none"}, "rounding": {"kind": "none"}}}')), '23514', 'no_such_rate');
SELECT pg_temp.ok('P6: the utility''s rate table carries the state, the service and an optional category (decision 1), and one rate per key and date',
  (SELECT count(*) = 3 FROM pg_attribute a WHERE a.attrelid = 'public.deposit_interest_rates'::regclass AND NOT a.attisdropped
      AND a.attname IN ('state_code', 'service_type', 'tariff_category'))
  AND NOT (SELECT a.attnotnull FROM pg_attribute a WHERE a.attrelid = 'public.deposit_interest_rates'::regclass AND a.attname = 'tariff_category'));
-- r9:end published

-- ============================================================ the floor
-- r10:begin floor
SELECT pg_temp.refuses('F1: a Texas investor-owned utility''s rate below the published rate in force on its date (2% in 2020)',
  pg_temp.rate_sql(:'t2', NULL, DATE '2020-06-01', 0.01), '23514', 'below the floor', 'tally_app', :'u2');
SELECT pg_temp.does_as('F2: … a rate equal to the floor is accepted', :'t2', pg_temp.rate_sql(:'t2', NULL, DATE '2020-06-01', 0.02));
SELECT pg_temp.refuses('F3: the floor in force on the row''s own date is the one that counts: 2% is below the 4% published from 2024',
  pg_temp.rate_sql(:'t2', NULL, DATE '2024-06-01', 0.02), '23514', 'below the floor', 'tally_app', :'u2');
SELECT pg_temp.run(pg_temp.rate_sql(:'t2', NULL, DATE '2024-06-01', 0.05), 'tally_app', :'u2');
SELECT pg_temp.refuses('F4: a rate dated before any publication of the floor (unknown law is not permission)',
  pg_temp.rate_sql(:'t2', NULL, DATE '2019-06-01', 0.10), '23514', 'no published value', 'tally_app', :'u2');
SELECT pg_temp.does('F5: a new publication that rises above a utility''s rate is not refused: the law wins and the core audits (a later law change is a finding, never a refusal of the law)',
  $q$INSERT INTO public.rule_parameter_values (parameter_name, state_code, effective_from, value, source_note) VALUES ('tx_deposit_interest_rate', 'TX', DATE '2030-01-01', 0.09, 'battery fixture')$q$);
-- the city: the law row delegates, so there is no floor
SELECT pg_temp.does_as('F6: a city-owned system, whose law row delegates, may pay any rate, even none', :'t1',
  pg_temp.rate_sql(:'t1', NULL, DATE '2020-06-01', 0));
-- A ZZ utility with finer classes: retail names a fixed 5% as a floor; wholesale names a rate only as a reference;
-- bulk names a rate that depends on how long the deposit is held (the floor is the highest of its names).
INSERT INTO public.deposit_customer_classes (state_code, service_type, class_code, description, source_note) VALUES
  ('ZZ', 'gas', 'retail', 'battery class', 'battery fixture'), ('ZZ', 'gas', 'wholesale', 'battery class', 'battery fixture'),
  ('ZZ', 'gas', 'bulk', 'battery class', 'battery fixture');
SELECT pg_temp.run(pg_temp.ins_sql('retail', 'credit_evaluation', pg_temp.doc('{"interest": {"strategy": "bearing", "version": 1, "instruments": ["cash"],
   "rate": {"kind": "fixed", "rate": 0.05, "binding": "minimum"}, "method": {"kind": "simple"}, "day_count": "actual_365", "hold": {"kind": "none"},
   "credit": {"kind": "at_refund"}, "stops_on": ["refund"], "forfeited_on": [], "penalty": {"kind": "none"}, "rounding": {"kind": "none"}}}')));
SELECT pg_temp.run(pg_temp.ins_sql('wholesale', 'credit_evaluation', pg_temp.doc('{"interest": {"strategy": "bearing", "version": 1, "instruments": ["cash"],
   "rate": {"kind": "published", "name": "zz_long", "binding": "reference", "by_hold": []}, "method": {"kind": "simple"}, "day_count": "actual_365",
   "hold": {"kind": "none"}, "credit": {"kind": "at_refund"}, "stops_on": ["refund"], "forfeited_on": [], "penalty": {"kind": "none"}, "rounding": {"kind": "none"}}}')));
SELECT pg_temp.run(pg_temp.ins_sql('bulk', 'credit_evaluation', pg_temp.doc('{"interest": {"strategy": "bearing", "version": 1, "instruments": ["cash"],
   "rate": {"kind": "published", "name": "zz_long", "binding": "minimum", "by_hold": [{"up_to_months": 12, "name": "zz_short"}]},
   "method": {"kind": "simple"}, "day_count": "actual_365", "hold": {"kind": "none"}, "credit": {"kind": "at_refund"}, "stops_on": ["refund"],
   "forfeited_on": [], "penalty": {"kind": "none"}, "rounding": {"kind": "none"}}}')));
SELECT pg_temp.run(pg_temp.cat_sql(:'t3', 'home', 'household', 'ZZ'), 'tally_app', :'u3');
SELECT pg_temp.run(pg_temp.cat_sql(:'t3', 'shop', 'retail', 'ZZ'), 'tally_app', :'u3');
SELECT pg_temp.run(pg_temp.cat_sql(:'t3', 'depot', 'wholesale', 'ZZ'), 'tally_app', :'u3');
SELECT pg_temp.run(pg_temp.cat_sql(:'t3', 'warehouse', 'bulk', 'ZZ'), 'tally_app', :'u3');
SELECT pg_temp.refuses('F7: a fixed statutory rate is a floor: 3% for a retail category where the law states 5%',
  pg_temp.rate_sql(:'t3', 'shop', DATE '2021-01-01', 0.03, 'ZZ'), '23514', 'below the floor', 'tally_app', :'u3');
SELECT pg_temp.does_as('F7b: … 5% is accepted', :'t3', pg_temp.rate_sql(:'t3', 'shop', DATE '2021-01-01', 0.05, 'ZZ'));
SELECT pg_temp.does_as('F8: a rate the law names only as a reference has no floor: 1% for a wholesale category', :'t3', pg_temp.rate_sql(:'t3', 'depot', DATE '2021-01-01', 0.01, 'ZZ'));
SELECT pg_temp.refuses('F9: where the law''s rate depends on how long the deposit is held, the floor is the highest of its names (4%, not 2%)',
  pg_temp.rate_sql(:'t3', 'warehouse', DATE '2021-01-01', 0.03, 'ZZ'), '23514', 'below the floor', 'tally_app', :'u3');
SELECT pg_temp.does_as('F9b: … 4% is accepted', :'t3', pg_temp.rate_sql(:'t3', 'warehouse', DATE '2021-01-01', 0.04, 'ZZ'));
SELECT pg_temp.does_as('F10: a category is held to its own law class only: a household category is held to 3%, not to retail''s 5%', :'t3', pg_temp.rate_sql(:'t3', 'home', DATE '2021-01-01', 0.03, 'ZZ'));
SELECT pg_temp.refuses('F11: a rate for every category must clear every class''s floor: 4.5% is below retail''s 5%',
  pg_temp.rate_sql(:'t3', NULL, DATE '2022-01-01', 0.045, 'ZZ'), '23514', 'below the floor', 'tally_app', :'u3');
SELECT pg_temp.does_as('F11b: … 5% clears them all', :'t3', pg_temp.rate_sql(:'t3', NULL, DATE '2022-01-01', 0.05, 'ZZ'));
SELECT pg_temp.refuses('F12: one rate per utility, state, service, category and date',
  pg_temp.rate_sql(:'t3', NULL, DATE '2022-01-01', 0.06, 'ZZ'), '23505', NULL, 'tally_app', :'u3');
SELECT pg_temp.refuses('F13: a rate for a category the utility has not defined',
  pg_temp.rate_sql(:'t3', 'kiosk', DATE '2022-01-01', 0.06, 'ZZ'), '23514', 'kiosk', 'tally_app', :'u3');
SELECT pg_temp.ok('F14: the lookup returns the category''s own rate over the every-category one on a date, and refuses when none is in force (no fallback)',
  public.deposit_interest_rate_row_as_of(:'t3', 'ZZ', 'gas', 'shop', DATE '2022-06-01') = (
    SELECT id FROM public.deposit_interest_rates WHERE tenant_id = :'t3' AND tariff_category = 'shop' AND effective_date = DATE '2021-01-01'));
SELECT pg_temp.refuses('F15: … and none before the first',
  format($q$SELECT public.deposit_interest_rate_row_as_of(%L, 'ZZ', 'gas', 'shop', DATE '2019-06-01')$q$, :'t3'), 'P0002', 'no deposit interest rate');
-- r10:end floor


-- ============================================================ R. a deposit cites what it was decided under
-- A deposit records the premise's state and service, the law class and the utility's own category, the LAW row it was
-- decided under (always: the delegation row for a city), the utility's TARIFF row when one applied, the cap that applied
-- and which document it came from, the component of that document that governed, and the core version. The citing side
-- is the template's: lock shared, re-read, in force on the date, the row the profile and key resolve to.
INSERT INTO public.customers (id, tenant_id, customer_number, customer_type) VALUES
  ('00000000-0000-4000-8000-0000000015c1', '00000000-0000-4000-8000-0000000015a1', 'B15R-C1', 'residential'),
  ('00000000-0000-4000-8000-0000000015c2', '00000000-0000-4000-8000-0000000015a2', 'B15R-C2', 'residential'),
  ('00000000-0000-4000-8000-0000000015c3', '00000000-0000-4000-8000-0000000015a2', 'B15R-C3', 'commercial');
\set c1 '00000000-0000-4000-8000-0000000015c1'
\set c2 '00000000-0000-4000-8000-0000000015c2'
\set c3 '00000000-0000-4000-8000-0000000015c3'
-- law(state, class, basis, owner, on): the id of the law row in force.
CREATE FUNCTION pg_temp.law(p_class text, p_basis text, p_owner text, p_on date DEFAULT DATE '2026-01-15') RETURNS uuid LANGUAGE sql STABLE AS $$
  SELECT id FROM public.deposit_rules WHERE state_code = 'TX' AND service_type = 'gas' AND customer_class = p_class AND basis = p_basis
     AND p_owner = ANY (owner_types) AND daterange(effective_from, effective_to, '[)') @> p_on
$$;
-- tar(tenant, category, on): the id of the tariff row in force.
CREATE FUNCTION pg_temp.tar(p_tenant text, p_cat text, p_on date DEFAULT DATE '2026-01-15') RETURNS uuid LANGUAGE sql STABLE AS $$
  SELECT id FROM public.deposit_tariffs WHERE tenant_id = p_tenant::uuid AND tariff_category = p_cat AND daterange(effective_from, effective_to, '[)') @> p_on
$$;
-- ov(overrides, key, default): the SQL literal for a field: the override when given (JSON null is SQL NULL), else the default.
CREATE FUNCTION pg_temp.ov(p_over jsonb, p_key text, p_default text) RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE WHEN p_over ? p_key THEN CASE WHEN jsonb_typeof(p_over -> p_key) = 'null' THEN 'NULL' ELSE quote_literal(p_over ->> p_key) END ELSE p_default END
$$;
-- dep_sql(overrides): by default a Texas investor-owned residential cash deposit of 100.00 on the credit-evaluation basis,
-- decided under the statute's cap of one-sixth of annual billing 1200.00 (200.00), the part c1.
CREATE FUNCTION pg_temp.dep_sql(p_over jsonb DEFAULT '{}') RETURNS text LANGUAGE sql STABLE AS $$
  SELECT format($q$INSERT INTO public.deposits (tenant_id, customer_id, basis, trigger_basis, instrument, principal, posted_on,
                     state_code, service_type, system_kind, customer_class, tariff_category, rule_id, tariff_id, decided_by,
                     cap_amount, cap_source, cap_component, cap_basis_amount, trigger_source, trigger_component, trigger_observed, received_at_posting)
                   VALUES (%s, %s, %s, %s, 'cash', %s, %s, 'TX', 'gas', 'distribution', %s, %s, %s, %s, 'core-battery-1',
                           %s, %s, %s, %s, %s, %s, %s, %s)$q$,
    pg_temp.ov(p_over, 'tenant', quote_literal('00000000-0000-4000-8000-0000000015a2')),
    pg_temp.ov(p_over, 'customer', quote_literal('00000000-0000-4000-8000-0000000015c2')),
    pg_temp.ov(p_over, 'basis', quote_literal('credit_evaluation')), pg_temp.ov(p_over, 'trigger_basis', 'NULL'),
    pg_temp.ov(p_over, 'principal', '100.00'), pg_temp.ov(p_over, 'posted', quote_literal('2026-01-15')),
    pg_temp.ov(p_over, 'class', quote_literal('residential')), pg_temp.ov(p_over, 'category', 'NULL'),
    pg_temp.ov(p_over, 'rule', quote_literal(pg_temp.law(coalesce(p_over ->> 'class', 'residential'), coalesce(p_over ->> 'basis', 'credit_evaluation'), 'investor_owned'))),
    pg_temp.ov(p_over, 'tariff', 'NULL'),
    pg_temp.ov(p_over, 'cap', '200.00'), pg_temp.ov(p_over, 'cap_source', quote_literal('statute')), pg_temp.ov(p_over, 'cap_component', quote_literal('c1')),
    pg_temp.ov(p_over, 'cap_basis', '1200.00'),
    pg_temp.ov(p_over, 'trigger_source', 'NULL'), pg_temp.ov(p_over, 'trigger_component', 'NULL'),
    pg_temp.ov(p_over, 'observed', 'NULL'), pg_temp.ov(p_over, 'received', 'NULL'))
$$;

-- r11:begin deposit-cites
SELECT pg_temp.does_as('R1: a deposit cites the law row of its state, service, class and basis in force on its posting date, with the cap that applied and the part that governed it',
  :'t2', pg_temp.dep_sql());
SELECT pg_temp.ok('R1b: and was born held, with its posting event written by the database',
  (SELECT d.status = 'held' AND d.recorded_txid IS NOT NULL AND EXISTS (SELECT 1 FROM public.deposit_events e WHERE e.deposit_id = d.id AND e.event_type = 'posted')
     FROM public.deposits d WHERE d.customer_id = :'c2' AND d.basis = 'credit_evaluation'));
SELECT pg_temp.refuses('R2: a new deposit that cites no law row',
  pg_temp.dep_sql('{"rule": null}'), '23514', 'records the deposit_rules row', 'tally_app', :'u2');
SELECT pg_temp.refuses('R2b: … or a law row that does not exist',
  pg_temp.dep_sql('{"rule": "00000000-0000-4000-8000-000000000000"}'), '23514', 'law row', 'tally_app', :'u2');
SELECT pg_temp.refuses('R3: a law row for another class: a residential deposit citing the non-residential row',
  pg_temp.dep_sql(jsonb_build_object('rule', pg_temp.law('non_residential', 'credit_evaluation', 'investor_owned'))), '23514', 'law row', 'tally_app', :'u2');
SELECT pg_temp.refuses('R4: a law row not in force on the posting date (before 2004-07-12)',
  pg_temp.dep_sql('{"posted": "2003-01-15"}'), '23514', 'in force', 'tally_app', :'u2');
SELECT pg_temp.refuses('R5: under a law row that caps the deposit, the cap that applied is recorded',
  pg_temp.dep_sql('{"cap": null, "cap_source": null, "cap_component": null, "cap_basis": null}'), '23514', 'cap', 'tally_app', :'u2');
SELECT pg_temp.refuses('R6: a statutory cap names a part of the cited document: "nope" is not one',
  pg_temp.dep_sql('{"cap_component": "nope"}'), '23514', 'nope', 'tally_app', :'u2');
SELECT pg_temp.refuses('R7: a principal above the cap that applied',
  pg_temp.dep_sql('{"principal": "250.00"}'), '23514', 'cap', 'tally_app', :'u2');
SELECT pg_temp.refuses('R8: the law row the profile does not resolve to: the city''s delegation row cited by the investor-owned utility',
  pg_temp.dep_sql(jsonb_build_object('rule', pg_temp.law('residential', 'credit_evaluation', 'municipal'))), '23514', 'law row', 'tally_app', :'u2');
SELECT pg_temp.refuses('R9: a new deposit on the carried-history basis',
  pg_temp.dep_sql('{"basis": "legacy_unknown"}'), '23514', 'carried history', 'tally_app', :'u2');
SELECT pg_temp.refuses('R10: a category that maps to another law class: "residential_senior" maps to residential, and non-residential is claimed',
  pg_temp.dep_sql('{"class": "non_residential", "category": "residential_senior", "customer": "00000000-0000-4000-8000-0000000015c3"}'), '23514', 'category', 'tally_app', :'u2');
SELECT pg_temp.refuses('R11: a category the utility has not defined',
  pg_temp.dep_sql('{"category": "kiosk"}'), '23514', 'kiosk', 'tally_app', :'u2');
-- r11:end deposit-cites

-- r12:begin deposit-city
-- The city: its law row delegates, so the deposit must cite its own tariff row, which sets the amount and the cap.
SELECT pg_temp.does_as('R12: a city deposit cites the delegation row AND its own tariff row in force for the category; the cap is the tariff''s',
  :'t1', pg_temp.dep_sql(jsonb_build_object('tenant', :'t1', 'customer', :'c1', 'rule', pg_temp.law('residential', 'credit_evaluation', 'municipal'),
     'category', 'homeowner', 'tariff', pg_temp.tar(:'t1', 'homeowner'), 'principal', '175.00', 'cap', '175.00', 'cap_source', 'tariff',
     'cap_component', null, 'cap_basis', null)));
SELECT pg_temp.refuses('R13: a city deposit that cites no tariff row (the law leaves it to the utility; the core refuses a decision with no policy recorded)',
  pg_temp.dep_sql(jsonb_build_object('tenant', :'t1', 'customer', :'c1', 'rule', pg_temp.law('residential', 'tariff', 'municipal'), 'basis', 'tariff',
     'category', 'homeowner', 'principal', '175.00', 'cap', '175.00', 'cap_source', 'tariff', 'cap_component', null, 'cap_basis', null)), '23514', 'tariff', 'tally_app', :'u1');
SELECT pg_temp.refuses('R14: a tariff row of another category: the renter''s cited for a homeowner',
  pg_temp.dep_sql(jsonb_build_object('tenant', :'t1', 'customer', :'c1', 'rule', pg_temp.law('residential', 'credit_evaluation', 'municipal'),
     'category', 'homeowner', 'tariff', pg_temp.tar(:'t1', 'renter'), 'principal', '250.00', 'cap', '250.00', 'cap_source', 'tariff', 'cap_component', null, 'cap_basis', null)),
  '23514', 'tariff row', 'tally_app', :'u1');
SELECT pg_temp.refuses('R15: a tariff row not in force on the posting date (the homeowner tariff changed on 2024-01-01)',
  pg_temp.dep_sql(jsonb_build_object('tenant', :'t1', 'customer', :'c1', 'rule', pg_temp.law('residential', 'credit_evaluation', 'municipal', DATE '2022-06-01'),
     'category', 'homeowner', 'tariff', pg_temp.tar(:'t1', 'homeowner', DATE '2025-06-01'), 'posted', '2022-06-01', 'principal', '175.00', 'cap', '175.00',
     'cap_source', 'tariff', 'cap_component', null, 'cap_basis', null)),
  '23514', 'in force', 'tally_app', :'u1');
SELECT pg_temp.refuses('R16: another utility''s tariff row (it is not visible to this one)',
  pg_temp.dep_sql(jsonb_build_object('tenant', :'t1', 'customer', :'c1', 'rule', pg_temp.law('residential', 'credit_evaluation', 'municipal'),
     'category', 'homeowner', 'tariff', pg_temp.tar(:'t2', 'residential', DATE '2025-06-01'), 'principal', '100.00', 'cap', '100.00',
     'cap_source', 'tariff', 'cap_component', null, 'cap_basis', null)),
  '23514', 'tariff row', 'tally_app', :'u1');
SELECT pg_temp.refuses('R17: a cap said to come from a tariff, with no tariff row cited',
  pg_temp.dep_sql('{"cap_source": "tariff", "cap_component": null}'), '23514', 'tariff', 'tally_app', :'u2');
-- r12:end deposit-city

-- r13:begin deposit-trigger
-- An additional deposit names a trigger of the document that governed it, and the measure the core observed meets that trigger's threshold.
SELECT pg_temp.does_as('R18: an additional deposit on the statute''s usage trigger: twice the estimate is met by 2.5',
  :'t2', pg_temp.dep_sql('{"basis": "additional_trigger", "trigger_basis": "usage_doubled", "trigger_source": "statute", "trigger_component": "t1", "observed": "2.5", "customer": "00000000-0000-4000-8000-0000000015c3"}'));
SELECT pg_temp.refuses('R19: … not met by 1.5',
  pg_temp.dep_sql('{"basis": "additional_trigger", "trigger_basis": "usage_doubled", "trigger_source": "statute", "trigger_component": "t1", "observed": "1.5"}'),
  '23514', 'does not meet the threshold', 'tally_app', :'u2');
SELECT pg_temp.refuses('R20: a trigger the cited document does not have',
  pg_temp.dep_sql('{"basis": "additional_trigger", "trigger_basis": "nsf", "trigger_source": "statute", "trigger_component": "t1", "observed": "5"}'),
  '23514', 'nsf', 'tally_app', :'u2');
SELECT pg_temp.refuses('R21: a basis that needs a trigger, without one',
  pg_temp.dep_sql('{"basis": "additional_trigger"}'), '23514', 'trigger', 'tally_app', :'u2');
SELECT pg_temp.refuses('R22: a trigger named on a basis that takes none',
  pg_temp.dep_sql('{"trigger_basis": "usage_doubled", "trigger_source": "statute", "trigger_component": "t1", "observed": "2.5"}'), '23514', 'trigger', 'tally_app', :'u2');
-- r13:end deposit-trigger

-- r14:begin deposit-frozen
SELECT pg_temp.refuses('R23: a deposit''s identity is frozen: its law row cannot be edited',
  format($q$UPDATE public.deposits SET rule_id = %L WHERE customer_id = %L AND basis = 'credit_evaluation'$q$, pg_temp.law('residential', 'tariff', 'investor_owned'), :'c2'),
  '23514', 'frozen', 'tally_app', :'u2');
SELECT pg_temp.refuses('R24: … nor its principal',
  format($q$UPDATE public.deposits SET principal = 1 WHERE customer_id = %L AND basis = 'credit_evaluation'$q$, :'c2'), '23514', 'frozen', 'tally_app', :'u2');
SELECT pg_temp.refuses('R25: the law row a deposit cites cannot be closed on or before the deposit''s posting date (the close floor counts the citing deposits)',
  format($q$UPDATE public.deposit_rules SET effective_to = DATE '2026-01-15' WHERE id = %L$q$, pg_temp.law('residential', 'credit_evaluation', 'investor_owned')), '23514', 'cited');
SELECT pg_temp.refuses('R26: nor the tariff row the city''s deposit cites',
  format($q$UPDATE public.deposit_tariffs SET effective_to = DATE '2026-01-15' WHERE id = %L$q$, pg_temp.tar(:'t1', 'homeowner')), '23514', 'cited', 'tally_app', :'u1');
-- r14:end deposit-frozen

ROLLBACK;
