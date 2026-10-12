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
--
-- Planned, not yet written (design doc section 9):
--   P  published values and the interest floor (decision 4)
--   U  the utility's tariff record and "never looser than the law"
--   R  records cite what they were decided under; the return-due record
--   H  history, grants, tenancy, the template's invariants over both tables
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

ROLLBACK;
