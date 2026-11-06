-- ============================================================================
-- BATTERY v5.4.2-30 — tax rows keyed to places and the taxability fixes
--   (tests first, 2026-11-05; interface: application/rates-build-2026-11-05/
--    tax-design.md section 2.8)
-- Run: psql -U tally -d <db-with-patch> -v ON_ERROR_STOP=1 -f battery-30.sql
-- One transaction, rolled back. Fixtures as the owner; the guards the
-- application meets are exercised as tally_app. refuses_at() requires the
-- named SQLSTATE AND a fragment of the named guard's message (or the
-- constraint's name), so a test cannot pass on another guard that shares the
-- SQLSTATE. ok() treats NULL as a fail. The first FAIL stops the run.
--
--   L  the utility's tax levies (Kyle 2026-10-14 answers 1, 2; Ryan's rule
--      that a value the utility answers for is its own row): on the
--      rule-terms template, keyed to a place and a tax kind; only a kind of
--      place that levies the tax; the place in the row's state and in force
--      over its dates; percent, four decimals; tax on tax named, never its
--      own kind, empty by default; a source and a citation; one row per key
--      and day; never edited, closed once; the utility's own rows only.
--   Q  the levy read as of a date and a recorded instant; NULL raises.
--   G  the reference compare: a levy that differs from the published rate
--      is reported, one that agrees is not.
--   F  the published sales-tax rate is percent (AC-45).
--   T  every rate item version states its taxability, whether it is a tax,
--      whether it is in the late-penalty base (Kyle 2026-11-05, 3a) and its
--      customer types (the size-tier defect, Kyle 2026-09-02): no defaults.
--   P  the late-penalty base never holds a tax or a rider excluded from tax
--      bases (the pipeline safety fee), in both orders of writing.
--   E  exemptions name their services; a NULL service type raises.
--   M  a premise's places as known at a past instant.
--   A  a state agency's basis is required and logged (Kyle 2026-11-05, 20).
--
-- Transaction time: inside one transaction every stamp is now(). A row
-- "recorded earlier" is planted by moving its stamp back with the table's
-- guard disabled (owner only, rolled back); every tested write runs with
-- every guard on.
-- ============================================================================
BEGIN;

CREATE FUNCTION pg_temp.refuses_at(p_label text, p_sql text, p_state text, p_guard text) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE v_con text;
BEGIN
  BEGIN
    EXECUTE p_sql;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_con = CONSTRAINT_NAME;
    IF SQLSTATE = p_state AND (v_con = p_guard OR strpos(SQLERRM, p_guard) > 0) THEN
      RAISE NOTICE 'PASS %: refused by % (%)', p_label, p_guard, left(SQLERRM, 140);
      RETURN;
    END IF;
    RAISE EXCEPTION 'FAIL %: refused with % [%] (%), expected % by %', p_label, SQLSTATE, v_con, SQLERRM, p_state, p_guard;
  END;
  RAISE EXCEPTION 'FAIL %: accepted', p_label;
END $$;
-- ok_q(): ok() over a query's text, so an error inside the read is a FAIL of
-- this label, not an unlabelled stop (mutation N14 of the as-of read).
CREATE FUNCTION pg_temp.ok_q(p_label text, p_sql text) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE v boolean;
BEGIN
  BEGIN
    EXECUTE p_sql INTO v;
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'FAIL %: the read raised % (%)', p_label, SQLSTATE, SQLERRM;
  END;
  IF v IS DISTINCT FROM true THEN RAISE EXCEPTION 'FAIL %', p_label; END IF;
  RAISE NOTICE 'PASS %', p_label;
END $$;
CREATE FUNCTION pg_temp.ok(p_label text, p_cond boolean) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  IF p_cond IS DISTINCT FROM true THEN RAISE EXCEPTION 'FAIL %', p_label; END IF;
  RAISE NOTICE 'PASS %', p_label;
END $$;
CREATE FUNCTION pg_temp.admits(p_label text, p_sql text) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE p_sql;
  RAISE NOTICE 'PASS %', p_label;
EXCEPTION WHEN OTHERS THEN
  RAISE EXCEPTION 'FAIL %: refused with % (%)', p_label, SQLSTATE, SQLERRM;
END $$;
GRANT EXECUTE ON FUNCTION pg_temp.refuses_at(text, text, text, text), pg_temp.ok(text, boolean), pg_temp.ok_q(text, text), pg_temp.admits(text, text) TO tally_app;

-- A levy row as the tests write it: id or NULL, tenant, state, the place by its kind and code, the tax kind, dates, terms (JSON text).
CREATE FUNCTION pg_temp.levy_sql(p_id uuid, p_tenant uuid, p_state text, p_pkind text, p_pcode text, p_kind text, p_from date, p_to date, p_terms text) RETURNS text
LANGUAGE sql AS $$
  SELECT format($f$INSERT INTO public.tax_levies (id, tenant_id, state_code, service_type, system_kind, place_kind, place_code, tax_kind, effective_from, effective_to,
                    tariff_reference, terms_kind, terms_version, terms_source)
                  VALUES (%L, %L, %L, 'gas', 'distribution', %L, %L, %L, %L, %L, 'City tariff 30', 'tax_levy', 1, %L)$f$,
                coalesce(p_id, public.uuid_generate_v4()), p_tenant, p_state, p_pkind, p_pcode, p_kind, p_from, p_to, p_terms)
$$;
GRANT EXECUTE ON FUNCTION pg_temp.levy_sql(uuid, uuid, text, text, text, text, date, date, text) TO tally_app;

-- ---------------------------------------------------------------------------
-- Fixtures
-- ---------------------------------------------------------------------------
INSERT INTO public.tenants (id, name, slug) VALUES
  ('00000000-0000-4000-8000-0000000030a1', 'T1 City Gas', 'bat30-t1'),
  ('00000000-0000-4000-8000-0000000030a2', 'T2 Gasco', 'bat30-t2');
INSERT INTO public.users (id, tenant_id, display_name, email, role, is_active) VALUES
  ('00000000-0000-4000-8000-0000000030b1', '00000000-0000-4000-8000-0000000030a1', 'Op1', 'op1@bat30.test', 'operator', true),
  ('00000000-0000-4000-8000-0000000030b2', '00000000-0000-4000-8000-0000000030a2', 'Op2', 'op2@bat30.test', 'operator', true);
INSERT INTO public.customers (id, tenant_id, customer_number, customer_type) VALUES
  ('00000000-0000-4000-8000-0000000030c1', '00000000-0000-4000-8000-0000000030a1', 'B30-C1', 'commercial'),
  ('00000000-0000-4000-8000-0000000030c2', '00000000-0000-4000-8000-0000000030a1', 'B30-C2', 'government');
INSERT INTO public.service_locations (id, tenant_id, customer_id, location_number, address_line1, city, state, zip) VALUES
  ('00000000-0000-4000-8000-0000000030d1', '00000000-0000-4000-8000-0000000030a1', '00000000-0000-4000-8000-0000000030c1', 'L1', '1 Main', 'Battery City', 'TX', '78701');

CREATE TEMP TABLE b30 (k text PRIMARY KEY, id uuid);
INSERT INTO b30 SELECT 'tx', id FROM public.places WHERE kind_code = 'state' AND place_code = 'TX' AND effective_to IS NULL;
-- A city (never a real code), its limited-purpose area, a county stand-in (an even code, never real).
INSERT INTO public.places (id, kind_code, state_code, place_code, name, parent_place_id, effective_from, source_note)
SELECT '00000000-0000-4000-8000-0000000030e1', 'municipality', 'TX', 'TX-B30-CITY', 'Battery City 30', id, DATE '2000-01-01', 'battery-30 fixture' FROM b30 WHERE k = 'tx';
INSERT INTO public.places (id, kind_code, state_code, place_code, name, parent_place_id, effective_from, source_note)
VALUES ('00000000-0000-4000-8000-0000000030e2', 'limited_purpose_area', 'TX', 'TX-B30-LPA', 'Battery City 30 limited-purpose area',
        '00000000-0000-4000-8000-0000000030e1', DATE '2000-01-01', 'battery-30 fixture');
INSERT INTO public.places (id, kind_code, state_code, place_code, name, parent_place_id, effective_from, source_note)
SELECT '00000000-0000-4000-8000-0000000030e3', 'county', 'TX', '48996', 'Battery County 30', id, DATE '1900-01-01', 'battery-30 fixture' FROM b30 WHERE k = 'tx';
INSERT INTO b30 VALUES ('city', '00000000-0000-4000-8000-0000000030e1'), ('lpa', '00000000-0000-4000-8000-0000000030e2'), ('county', '00000000-0000-4000-8000-0000000030e3');
INSERT INTO public.utility_service_profiles (tenant_id, service_type, system_kind, state_code, owner_type, commission_jurisdiction,
                                             owning_place_id, effective_from, evidence_reference, evidence_date)
VALUES ('00000000-0000-4000-8000-0000000030a1', 'gas', 'distribution', 'TX', 'municipal', false,
        '00000000-0000-4000-8000-0000000030e1', DATE '2000-01-01', 'Battery City charter', DATE '2000-01-01');
DO $$ BEGIN IF (SELECT count(*) FROM b30) <> 4 THEN RAISE EXCEPTION 'SETUP: Texas is not seeded'; END IF; END $$;
-- r2: three more premises in Texas: d2's state is corrected later (M6), d3 is
-- in the county (G5), d4 is in a place closed later (M11). A second state (New
-- Mexico, planted and rolled back), a city with two successive rows, one with a
-- gap between its rows, and a city closed later.
INSERT INTO public.service_locations (id, tenant_id, customer_id, location_number, address_line1, city, state, zip) VALUES
  ('00000000-0000-4000-8000-0000000030d2', '00000000-0000-4000-8000-0000000030a1', '00000000-0000-4000-8000-0000000030c1', 'L2', '2 Main', 'Battery City', 'TX', '78701'),
  ('00000000-0000-4000-8000-0000000030d3', '00000000-0000-4000-8000-0000000030a1', '00000000-0000-4000-8000-0000000030c1', 'L3', '3 Main', 'Battery City', 'TX', '78701'),
  ('00000000-0000-4000-8000-0000000030d4', '00000000-0000-4000-8000-0000000030a1', '00000000-0000-4000-8000-0000000030c1', 'L4', '4 Main', 'Battery City', 'TX', '78701');
INSERT INTO public.places (id, kind_code, state_code, place_code, name, effective_from, source_note)
VALUES ('00000000-0000-4000-8000-0000000030e9', 'state', 'NM', 'NM', 'New Mexico (battery 30)', DATE '1900-01-01', 'battery-30 fixture');
INSERT INTO public.places (id, kind_code, state_code, place_code, name, parent_place_id, effective_from, effective_to, source_note)
SELECT v.id, 'municipality', 'TX', v.code, v.name, b.id, v.f, v.t, 'battery-30 fixture'
  FROM b30 b, (VALUES ('00000000-0000-4000-8000-0000000030e4'::uuid, 'TX-B30-SUCC', 'Succession City 30 (first row)', DATE '2000-01-01', DATE '2026-07-01'),
                      ('00000000-0000-4000-8000-0000000030e5'::uuid, 'TX-B30-SUCC', 'Succession City 30', DATE '2026-07-01', NULL::date),
                      ('00000000-0000-4000-8000-0000000030e6'::uuid, 'TX-B30-GAP', 'Gap City 30 (first row)', DATE '2000-01-01', DATE '2026-06-01'),
                      ('00000000-0000-4000-8000-0000000030e7'::uuid, 'TX-B30-GAP', 'Gap City 30', DATE '2026-07-01', NULL::date),
                      ('00000000-0000-4000-8000-0000000030e8'::uuid, 'TX-B30-OLD', 'Old City 30', DATE '2000-01-01', NULL::date)) v(id, code, name, f, t)
 WHERE b.k = 'tx';
INSERT INTO public.premise_place_memberships (id, tenant_id, service_location_id, place_id, axis, place_kind, valid_from, evidence_kind, evidence_reference, evidence_date) VALUES
  ('00000000-0000-4000-8000-0000000030aa', '00000000-0000-4000-8000-0000000030a1', '00000000-0000-4000-8000-0000000030d2', '00000000-0000-4000-8000-0000000030e3', 'tax', 'county', DATE '2020-01-01', 'address_lookup', 'Comptroller address file 2020Q1', DATE '2020-01-01'),
  ('00000000-0000-4000-8000-0000000030ab', '00000000-0000-4000-8000-0000000030a1', '00000000-0000-4000-8000-0000000030d3', '00000000-0000-4000-8000-0000000030e3', 'tax', 'county', DATE '2020-01-01', 'address_lookup', 'Comptroller address file 2020Q1', DATE '2020-01-01'),
  ('00000000-0000-4000-8000-0000000030ac', '00000000-0000-4000-8000-0000000030a1', '00000000-0000-4000-8000-0000000030d4', '00000000-0000-4000-8000-0000000030e8', 'tax', 'municipality', DATE '2020-01-01', 'address_lookup', 'Comptroller address file 2020Q1', DATE '2020-01-01');
-- Planted (owner, the guard lifted, rolled back): every premise's state was
-- recorded two days ago. Each test's "before" instant is taken from these
-- stamps, never from the database's age (r1, Codex S2).
ALTER TABLE public.service_location_state_history DISABLE TRIGGER append_only;
UPDATE public.service_location_state_history SET recorded_at = now() - interval '2 days'
 WHERE service_location_id IN ('00000000-0000-4000-8000-0000000030d1', '00000000-0000-4000-8000-0000000030d2', '00000000-0000-4000-8000-0000000030d3', '00000000-0000-4000-8000-0000000030d4');
ALTER TABLE public.service_location_state_history ENABLE ALWAYS TRIGGER append_only;

-- ---------------------------------------------------------------------------
-- L  the utility's tax levies
-- ---------------------------------------------------------------------------
SELECT pg_temp.ok('L0 tax_kinds holds sales_tax, levied by the state, a county, a city, a transit authority or a district',
  (SELECT place_kinds @> ARRAY['state', 'county', 'municipality', 'transit_authority', 'special_purpose_district']
          AND NOT place_kinds && ARRAY['limited_purpose_area', 'extraterritorial_area', 'unincorporated_area']
     FROM public.tax_kinds WHERE tax_kind = 'sales_tax'));
SELECT pg_temp.ok('L0b tax_levies is a tariff table on the rule-terms template, keyed by the place''s kind and code (in the row''s state) and the tax kind',
  (SELECT rule_role = 'tariff' AND terms_kind = 'tax_levy' AND area_key = ARRAY['place_kind', 'place_code', 'tax_kind']
     FROM public.rule_tables WHERE table_name = 'public.tax_levies'::regclass));
SELECT pg_temp.ok('L0c tally_app reads tax kinds and writes none',
  has_table_privilege('tally_app', 'public.tax_kinds', 'SELECT') AND NOT has_table_privilege('tally_app', 'public.tax_kinds', 'INSERT')
  AND NOT has_table_privilege('tally_app', 'public.tax_kinds', 'UPDATE') AND NOT has_table_privilege('tally_app', 'public.tax_kinds', 'DELETE'));

SET ROLE tally_app;
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000030b1', true);

SELECT pg_temp.admits('L1 the city''s sales tax, 1.0000 percent, reaching residential gas, from 2026-01-01',
  pg_temp.levy_sql('00000000-0000-4000-8000-0000000030f1', '00000000-0000-4000-8000-0000000030a1', 'TX', 'municipality', 'TX-B30-CITY', 'sales_tax',
    DATE '2026-01-01', NULL,
    '{"rate_percent": 1, "stacking_position": 2, "computed_on": [], "source_kind": "ordinance", "citation": "Battery City Ord. 30-1", "reaches_residential": true}'));
SELECT pg_temp.admits('L2 the state''s sales tax, 6.25 percent, not reaching residential gas (Tax Code 151.317)',
  pg_temp.levy_sql('00000000-0000-4000-8000-0000000030f2', '00000000-0000-4000-8000-0000000030a1', 'TX', 'state', 'TX', 'sales_tax',
    DATE '2026-01-01', NULL,
    '{"rate_percent": 6.25, "stacking_position": 1, "computed_on": [], "source_kind": "statute", "citation": "Tex. Tax Code 151.051", "reaches_residential": false}'));
SELECT pg_temp.ok('L1b the stored row names the operator who approved it, and its document',
  (SELECT created_by = '00000000-0000-4000-8000-0000000030b1' AND (terms ->> 'rate_percent')::numeric = 1.0 AND terms -> 'computed_on' = '[]'::jsonb
     FROM public.tax_levies WHERE id = '00000000-0000-4000-8000-0000000030f1'));

SELECT pg_temp.refuses_at('L3 a limited-purpose area levies no sales tax',
  pg_temp.levy_sql(NULL, '00000000-0000-4000-8000-0000000030a1', 'TX', 'limited_purpose_area', 'TX-B30-LPA', 'sales_tax', DATE '2026-01-01', NULL,
    '{"rate_percent": 1, "stacking_position": 2, "computed_on": [], "source_kind": "ordinance", "citation": "x1", "reaches_residential": true}'),
  '23514', 'does not levy');
SELECT pg_temp.refuses_at('L4 a county code with no place in the row''s state (48994: even, never real, not planted)',
  pg_temp.levy_sql(NULL, '00000000-0000-4000-8000-0000000030a1', 'TX', 'county', '48994', 'sales_tax', DATE '2026-01-01', NULL,
    '{"rate_percent": 1, "stacking_position": 2, "computed_on": [], "source_kind": "ordinance", "citation": "x1", "reaches_residential": true}'),
  '23514', 'in force over the whole');
SELECT pg_temp.refuses_at('L5 a levy dated before its place exists (the city is in force from 2000)',
  pg_temp.levy_sql(NULL, '00000000-0000-4000-8000-0000000030a1', 'TX', 'municipality', 'TX-B30-CITY', 'sales_tax', DATE '1990-01-01', DATE '2000-06-01',
    '{"rate_percent": 1, "stacking_position": 2, "computed_on": [], "source_kind": "ordinance", "citation": "x1", "reaches_residential": true}'),
  '23514', 'in force over the whole');
SELECT pg_temp.refuses_at('L6 a rate with five decimals (four at most, K-06)',
  pg_temp.levy_sql(NULL, '00000000-0000-4000-8000-0000000030a1', 'TX', 'county', '48996', 'sales_tax', DATE '2026-01-01', NULL,
    '{"rate_percent": 0.50005, "stacking_position": 3, "computed_on": [], "source_kind": "ordinance", "citation": "x1", "reaches_residential": true}'),
  '23514', 'at most four decimals');
SELECT pg_temp.refuses_at('L7 a rate over 100 percent',
  pg_temp.levy_sql(NULL, '00000000-0000-4000-8000-0000000030a1', 'TX', 'county', '48996', 'sales_tax', DATE '2026-01-01', NULL,
    '{"rate_percent": 100.5, "stacking_position": 3, "computed_on": [], "source_kind": "ordinance", "citation": "x1", "reaches_residential": true}'),
  '23514', 'must be at most 100');
SELECT pg_temp.refuses_at('L7b a negative rate',
  pg_temp.levy_sql(NULL, '00000000-0000-4000-8000-0000000030a1', 'TX', 'county', '48996', 'sales_tax', DATE '2026-01-01', NULL,
    '{"rate_percent": -0.5, "stacking_position": 3, "computed_on": [], "source_kind": "ordinance", "citation": "x1", "reaches_residential": true}'),
  '23514', 'must be at least 0');
SELECT pg_temp.refuses_at('L8 a rate given as a fraction-looking string, not a number',
  pg_temp.levy_sql(NULL, '00000000-0000-4000-8000-0000000030a1', 'TX', 'county', '48996', 'sales_tax', DATE '2026-01-01', NULL,
    '{"rate_percent": "0.5", "stacking_position": 3, "computed_on": [], "source_kind": "ordinance", "citation": "x1", "reaches_residential": true}'),
  '23514', '/rate_percent: expected a number');
SELECT pg_temp.refuses_at('L9 tax on tax naming an unknown kind',
  pg_temp.levy_sql(NULL, '00000000-0000-4000-8000-0000000030a1', 'TX', 'county', '48996', 'sales_tax', DATE '2026-01-01', NULL,
    '{"rate_percent": 0.5, "stacking_position": 3, "computed_on": ["franchise_fee"], "source_kind": "ordinance", "citation": "x1", "reaches_residential": true}'),
  '23514', 'computed_on names');
SELECT pg_temp.refuses_at('L10 tax on tax naming the levy''s own kind',
  pg_temp.levy_sql(NULL, '00000000-0000-4000-8000-0000000030a1', 'TX', 'county', '48996', 'sales_tax', DATE '2026-01-01', NULL,
    '{"rate_percent": 0.5, "stacking_position": 3, "computed_on": ["sales_tax"], "source_kind": "ordinance", "citation": "x1", "reaches_residential": true}'),
  '23514', 'its own kind');
SELECT pg_temp.refuses_at('L11 no computed_on at all (empty is the stated "none"; absent is not a choice)',
  pg_temp.levy_sql(NULL, '00000000-0000-4000-8000-0000000030a1', 'TX', 'county', '48996', 'sales_tax', DATE '2026-01-01', NULL,
    '{"rate_percent": 0.5, "stacking_position": 3, "source_kind": "ordinance", "citation": "x1", "reaches_residential": true}'),
  '23514', '/computed_on: required');
SELECT pg_temp.refuses_at('L12 a stacking position of 0',
  pg_temp.levy_sql(NULL, '00000000-0000-4000-8000-0000000030a1', 'TX', 'county', '48996', 'sales_tax', DATE '2026-01-01', NULL,
    '{"rate_percent": 0.5, "stacking_position": 0, "computed_on": [], "source_kind": "ordinance", "citation": "x1", "reaches_residential": true}'),
  '23514', '/stacking_position: must be at least 1');
SELECT pg_temp.refuses_at('L13 a source kind that is not statute, ordinance or tariff',
  pg_temp.levy_sql(NULL, '00000000-0000-4000-8000-0000000030a1', 'TX', 'county', '48996', 'sales_tax', DATE '2026-01-01', NULL,
    '{"rate_percent": 0.5, "stacking_position": 3, "computed_on": [], "source_kind": "custom", "citation": "x1", "reaches_residential": true}'),
  '23514', '/source_kind:');
SELECT pg_temp.refuses_at('L14 a citation that is only a tab',
  pg_temp.levy_sql(NULL, '00000000-0000-4000-8000-0000000030a1', 'TX', 'county', '48996', 'sales_tax', DATE '2026-01-01', NULL,
    E'{"rate_percent": 0.5, "stacking_position": 3, "computed_on": [], "source_kind": "ordinance", "citation": "\\t", "reaches_residential": true}'),
  '23514', 'citation');
SELECT pg_temp.refuses_at('L14b no citation',
  pg_temp.levy_sql(NULL, '00000000-0000-4000-8000-0000000030a1', 'TX', 'county', '48996', 'sales_tax', DATE '2026-01-01', NULL,
    '{"rate_percent": 0.5, "stacking_position": 3, "computed_on": [], "source_kind": "ordinance", "reaches_residential": true}'),
  '23514', '/citation: required');
SELECT pg_temp.refuses_at('L15 a second city sales tax overlapping the first',
  pg_temp.levy_sql(NULL, '00000000-0000-4000-8000-0000000030a1', 'TX', 'municipality', 'TX-B30-CITY', 'sales_tax', DATE '2026-06-01', NULL,
    '{"rate_percent": 2, "stacking_position": 2, "computed_on": [], "source_kind": "ordinance", "citation": "Battery City Ord. 30-2", "reaches_residential": true}'),
  '23P01', 'tax_levies_rule_no_overlap');
SELECT pg_temp.refuses_at('L16 a levy is never edited in place',
  $q$UPDATE public.tax_levies SET tariff_reference = 'City tariff 31' WHERE id = '00000000-0000-4000-8000-0000000030f1'$q$,
  '23001', 'rows are never edited');
SELECT pg_temp.refuses_at('L17 a levy is never deleted',
  $q$DELETE FROM public.tax_levies WHERE id = '00000000-0000-4000-8000-0000000030f1'$q$,
  '42501', 'tax_levies');
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000030b2', true);
SELECT pg_temp.refuses_at('L18 another utility writes no levy for T1',
  pg_temp.levy_sql(NULL, '00000000-0000-4000-8000-0000000030a1', 'TX', 'county', '48996', 'sales_tax', DATE '2026-01-01', NULL,
    '{"rate_percent": 0.5, "stacking_position": 3, "computed_on": [], "source_kind": "ordinance", "citation": "x1", "reaches_residential": true}'),
  '42501', 'its own');
SELECT pg_temp.ok('L18b and sees none of T1''s', (SELECT count(*) = 0 FROM public.tax_levies));
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000030b1', true);
SELECT pg_temp.admits('L19 the county''s rate in force from 2026-01-01 to 2026-07-01 (closed in the row)',
  pg_temp.levy_sql('00000000-0000-4000-8000-0000000030f3', '00000000-0000-4000-8000-0000000030a1', 'TX', 'county', '48996', 'sales_tax',
    DATE '2026-01-01', DATE '2026-07-01',
    '{"rate_percent": 0.5, "stacking_position": 3, "computed_on": [], "source_kind": "ordinance", "citation": "Battery County Order 30", "reaches_residential": true}'));
SELECT pg_temp.admits('L20 the city''s rate closed at 2026-07-01, once',
  $q$UPDATE public.tax_levies SET effective_to = DATE '2026-07-01' WHERE id = '00000000-0000-4000-8000-0000000030f1'$q$);
SELECT pg_temp.admits('L21 and its successor from 2026-07-01 at 2.0 percent',
  pg_temp.levy_sql('00000000-0000-4000-8000-0000000030f4', '00000000-0000-4000-8000-0000000030a1', 'TX', 'municipality', 'TX-B30-CITY', 'sales_tax',
    DATE '2026-07-01', NULL,
    '{"rate_percent": 2, "stacking_position": 2, "computed_on": [], "source_kind": "ordinance", "citation": "Battery City Ord. 30-2", "reaches_residential": true}'));
SELECT pg_temp.ok('L21b the row names its place by kind and code, so a successor row of the same place keeps it',
  (SELECT place_kind = 'municipality' AND place_code = 'TX-B30-CITY' FROM public.tax_levies WHERE id = '00000000-0000-4000-8000-0000000030f4'));
SELECT pg_temp.admits('L22 a levy spanning a city''s two successive rows (the second continues the first)',
  pg_temp.levy_sql('00000000-0000-4000-8000-0000000030f5', '00000000-0000-4000-8000-0000000030a1', 'TX', 'municipality', 'TX-B30-SUCC', 'sales_tax',
    DATE '2026-01-01', NULL,
    '{"rate_percent": 1, "stacking_position": 2, "computed_on": [], "source_kind": "ordinance", "citation": "Succession City Ord. 1", "reaches_residential": true}'));
SELECT pg_temp.refuses_at('L23 a levy across a gap between a city''s rows (June 2026 uncovered)',
  pg_temp.levy_sql(NULL, '00000000-0000-4000-8000-0000000030a1', 'TX', 'municipality', 'TX-B30-GAP', 'sales_tax', DATE '2026-01-01', NULL,
    '{"rate_percent": 1, "stacking_position": 2, "computed_on": [], "source_kind": "ordinance", "citation": "Gap City Ord. 1", "reaches_residential": true}'),
  '23514', 'in force over the whole');
SELECT pg_temp.ok('L20b the close is stamped with its time and its operator',
  (SELECT closed_at = now() AND closed_by = '00000000-0000-4000-8000-0000000030b1' FROM public.tax_levies WHERE id = '00000000-0000-4000-8000-0000000030f1'));
RESET ROLE;

-- ---------------------------------------------------------------------------
-- C  a place is never closed from under a levy (checked at commit: a close and
--    its successor row may come in one transaction). The owner closes places.
-- ---------------------------------------------------------------------------
SELECT pg_temp.ok('C0 the coverage check fires always, at commit',
  (SELECT tgenabled = 'A' AND tgdeferrable AND tginitdeferred FROM pg_trigger
    WHERE tgrelid = 'public.places'::regclass AND tgname = 'z_check_place_levy_coverage'));
SELECT pg_temp.refuses_at('C1 the city''s open row closed at 2026-12-01 with no successor, while its levy is open',
  $q$DO $x$ BEGIN
       UPDATE public.places SET effective_to = DATE '2026-12-01' WHERE id = '00000000-0000-4000-8000-0000000030e5';
       SET CONSTRAINTS public.z_check_place_levy_coverage IMMEDIATE;
     END $x$$q$,
  '23001', 'a tax levy');
SELECT pg_temp.admits('C2 a succession in one transaction: the city''s row closed at 2027-01-01 and its successor added',
  $q$DO $x$ BEGIN
       UPDATE public.places SET effective_to = DATE '2027-01-01' WHERE id = '00000000-0000-4000-8000-0000000030e5';
       INSERT INTO public.places (id, kind_code, state_code, place_code, name, parent_place_id, effective_from, source_note)
       SELECT '00000000-0000-4000-8000-0000000030ea', 'municipality', 'TX', 'TX-B30-SUCC', 'Succession City 30 (renamed)', id, DATE '2027-01-01', 'battery-30 fixture'
         FROM public.places WHERE kind_code = 'state' AND place_code = 'TX' AND effective_to IS NULL;
       SET CONSTRAINTS public.z_check_place_levy_coverage IMMEDIATE;
       SET CONSTRAINTS public.z_check_place_levy_coverage DEFERRED;
     END $x$$q$);
SELECT pg_temp.refuses_at('C3 the successor closed at 2028-01-01 with no successor of its own, while the levy is open',
  $q$DO $x$ BEGIN
       UPDATE public.places SET effective_to = DATE '2028-01-01' WHERE id = '00000000-0000-4000-8000-0000000030ea';
       SET CONSTRAINTS public.z_check_place_levy_coverage IMMEDIATE;
     END $x$$q$,
  '23001', 'a tax levy');
SET ROLE tally_app;
SELECT pg_temp.admits('C4a the utility closes its levy at 2028-01-01',
  $q$UPDATE public.tax_levies SET effective_to = DATE '2028-01-01' WHERE id = '00000000-0000-4000-8000-0000000030f5'$q$);
RESET ROLE;
SELECT pg_temp.admits('C4b then the place closes at 2028-01-01',
  $q$DO $x$ BEGIN
       UPDATE public.places SET effective_to = DATE '2028-01-01' WHERE id = '00000000-0000-4000-8000-0000000030ea';
       SET CONSTRAINTS public.z_check_place_levy_coverage IMMEDIATE;
       SET CONSTRAINTS public.z_check_place_levy_coverage DEFERRED;
     END $x$$q$);

-- ---------------------------------------------------------------------------
-- Q  the levy as of a date and a recorded instant
-- ---------------------------------------------------------------------------
-- Plant: the city's first row (f1) and the county row (f3) were recorded two
-- days ago (their stamps moved back with the guard off), so "a day ago" is an
-- instant that knew f1 open and did not yet know its successor f4.
ALTER TABLE public.tax_levies DISABLE TRIGGER rule_row_history;
UPDATE public.tax_levies SET created_at = now() - interval '2 days' WHERE id IN ('00000000-0000-4000-8000-0000000030f1', '00000000-0000-4000-8000-0000000030f3');
ALTER TABLE public.tax_levies ENABLE ALWAYS TRIGGER rule_row_history;

SELECT pg_temp.ok_q('Q1 on 2026-03-01, now: the city''s first rate',
  $q$SELECT (SELECT id = '00000000-0000-4000-8000-0000000030f1' FROM public.tax_levy_as_of('00000000-0000-4000-8000-0000000030a1', 'TX', 'municipality', 'TX-B30-CITY',
     'sales_tax', 'gas', 'distribution', DATE '2026-03-01', now()))$q$);
SET ROLE tally_app;
SELECT pg_temp.ok_q('Q1b the same read as tally_app, the utility''s own operator',
  $q$SELECT (SELECT id = '00000000-0000-4000-8000-0000000030f1' FROM public.tax_levy_as_of('00000000-0000-4000-8000-0000000030a1', 'TX', 'municipality', 'TX-B30-CITY',
     'sales_tax', 'gas', 'distribution', DATE '2026-03-01', now()))$q$);
RESET ROLE;
SELECT pg_temp.ok_q('Q2 on 2026-08-01, now: the successor',
  $q$SELECT (SELECT id = '00000000-0000-4000-8000-0000000030f4' FROM public.tax_levy_as_of('00000000-0000-4000-8000-0000000030a1', 'TX', 'municipality', 'TX-B30-CITY',
     'sales_tax', 'gas', 'distribution', DATE '2026-08-01', now()))$q$);
SELECT pg_temp.ok_q('Q3 on 2026-08-01, as known a day ago: the first rate, then still open (its close came later)',
  $q$SELECT (SELECT id = '00000000-0000-4000-8000-0000000030f1' FROM public.tax_levy_as_of('00000000-0000-4000-8000-0000000030a1', 'TX', 'municipality', 'TX-B30-CITY',
     'sales_tax', 'gas', 'distribution', DATE '2026-08-01', now() - interval '1 day'))$q$);
SELECT pg_temp.ok_q('Q4 as known three days ago: nothing (no row was recorded yet)',
  $q$SELECT NOT EXISTS (SELECT 1 FROM public.tax_levy_as_of('00000000-0000-4000-8000-0000000030a1', 'TX', 'municipality', 'TX-B30-CITY',
     'sales_tax', 'gas', 'distribution', DATE '2026-03-01', now() - interval '3 days'))$q$);
SELECT pg_temp.ok_q('Q5 the county on 2026-08-01: nothing (its row ends 2026-07-01, known from the start)',
  $q$SELECT NOT EXISTS (SELECT 1 FROM public.tax_levy_as_of('00000000-0000-4000-8000-0000000030a1', 'TX', 'county', '48996',
     'sales_tax', 'gas', 'distribution', DATE '2026-08-01', now() - interval '1 day'))$q$);
SELECT pg_temp.refuses_at('Q6 no recorded instant',
  $q$SELECT * FROM public.tax_levy_as_of('00000000-0000-4000-8000-0000000030a1', 'TX', 'municipality', 'TX-B30-CITY', 'sales_tax', 'gas', 'distribution', DATE '2026-03-01', NULL)$q$,
  '22004', 'every argument is required');
SELECT pg_temp.refuses_at('Q6b no date',
  $q$SELECT * FROM public.tax_levy_as_of('00000000-0000-4000-8000-0000000030a1', 'TX', 'municipality', 'TX-B30-CITY', 'sales_tax', 'gas', 'distribution', NULL, now())$q$,
  '22004', 'every argument is required');
SELECT pg_temp.refuses_at('Q6c no place code',
  $q$SELECT * FROM public.tax_levy_as_of('00000000-0000-4000-8000-0000000030a1', 'TX', 'municipality', NULL, 'sales_tax', 'gas', 'distribution', DATE '2026-03-01', now())$q$,
  '22004', 'every argument is required');
SELECT pg_temp.ok('Q7 the lookup has no defaulted argument',
  (SELECT pronargdefaults = 0 FROM pg_proc WHERE oid = 'public.tax_levy_as_of(uuid, text, text, text, text, text, text, date, timestamp with time zone)'::regprocedure));

-- ---------------------------------------------------------------------------
-- G  the reference compare, F  the published rate in percent
-- ---------------------------------------------------------------------------
SELECT pg_temp.ok('F1 the sales_tax_rate fact kind is percent, 0 to 100',
  (SELECT value_min = 0 AND value_max = 100 AND description ~* 'percent' AND description !~* 'fraction' FROM public.place_fact_kinds WHERE fact_code = 'sales_tax_rate'));
-- The repair lifts the vocabulary guard for one statement: it must be back on, as ALWAYS.
SELECT pg_temp.ok('F1b the vocabulary guard on fact kinds is back on after the repair, firing always',
  (SELECT tgenabled = 'A' FROM pg_trigger WHERE tgrelid = 'public.place_fact_kinds'::regclass AND tgname = 'a_enforce_place_vocabulary_immutable'));
INSERT INTO public.place_facts (place_id, fact_code, value, effective_from, source_note) VALUES
  ('00000000-0000-4000-8000-0000000030e1', 'sales_tax_rate', '1.5', DATE '2026-01-01', 'Comptroller rate file 2026Q1 (battery 30)'),
  ((SELECT id FROM b30 WHERE k = 'tx'), 'sales_tax_rate', '6.25', DATE '2026-01-01', 'Tax Code 151.051 (battery 30)');
SELECT pg_temp.refuses_at('F2 a published rate of 101 percent',
  $q$INSERT INTO public.place_facts (place_id, fact_code, value, effective_from, source_note)
     VALUES ('00000000-0000-4000-8000-0000000030e3', 'sales_tax_rate', '101', DATE '2026-01-01', 'x')$q$,
  '23514', 'sales_tax_rate');
SELECT pg_temp.ok('G1 on 2026-03-01 the city''s levy (1.0) differs from the published 1.5: reported, with both and the source',
  (SELECT count(*) = 1 AND bool_and(levy_id = '00000000-0000-4000-8000-0000000030f1' AND levy_rate_percent = 1.0 AND reference_rate_percent = 1.5
                                    AND reference_source ~ 'Comptroller')
     FROM public.tax_levy_reference_gaps('00000000-0000-4000-8000-0000000030a1', DATE '2026-03-01')));
SELECT pg_temp.ok('G2 the state''s levy agrees with the published 6.25: not reported',
  NOT EXISTS (SELECT 1 FROM public.tax_levy_reference_gaps('00000000-0000-4000-8000-0000000030a1', DATE '2026-03-01') g
               WHERE g.levy_id = '00000000-0000-4000-8000-0000000030f2'));
SELECT pg_temp.ok('G3 on 2026-08-01 the successor (2.0) differs from 1.5: reported',
  EXISTS (SELECT 1 FROM public.tax_levy_reference_gaps('00000000-0000-4000-8000-0000000030a1', DATE '2026-08-01') g
           WHERE g.levy_id = '00000000-0000-4000-8000-0000000030f4' AND g.reference_rate_percent = 1.5));
SELECT pg_temp.refuses_at('G4 no date',
  $q$SELECT * FROM public.tax_levy_reference_gaps('00000000-0000-4000-8000-0000000030a1', NULL)$q$,
  '22004', 'required');

-- ---------------------------------------------------------------------------
-- T  every rate item version states its taxability, tax, penalty base, customer types
-- P  the late-penalty base holds no tax and no excluded rider
-- ---------------------------------------------------------------------------
INSERT INTO public.rate_items (id, tenant_id, item_code) VALUES
  ('00000000-0000-4000-8000-000000003011', '00000000-0000-4000-8000-0000000030a1', 'CUST'),
  ('00000000-0000-4000-8000-000000003012', '00000000-0000-4000-8000-0000000030a1', 'PSF'),
  ('00000000-0000-4000-8000-000000003013', '00000000-0000-4000-8000-0000000030a1', 'CITYTAX'),
  ('00000000-0000-4000-8000-000000003014', '00000000-0000-4000-8000-0000000030a1', 'WNA');
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000030b1', true);
SELECT public.assert_reference_version('rate_items', '00000000-0000-4000-8000-000000003011', 1);
SELECT public.assert_reference_version('rate_items', '00000000-0000-4000-8000-000000003012', 1);
SELECT public.assert_reference_version('rate_items', '00000000-0000-4000-8000-000000003013', 1);
SELECT public.assert_reference_version('rate_items', '00000000-0000-4000-8000-000000003014', 1);

CREATE FUNCTION pg_temp.version_sql(p_item uuid, p_cols text, p_vals text) RETURNS text LANGUAGE sql AS $$
  SELECT format($f$INSERT INTO public.rate_item_versions (tenant_id, rate_item_id, item_name, service_type, calculation_type, regulatory_class, effective_date, change_type%s)
                  VALUES ('00000000-0000-4000-8000-0000000030a1', %L, 'Item', 'gas', 'fixed_monthly', 'regulated', DATE '2026-01-01', 'initial'%s)$f$,
                p_cols, p_item, p_vals)
$$;
SELECT pg_temp.refuses_at('T1 a version that does not state its taxability',
  pg_temp.version_sql('00000000-0000-4000-8000-000000003011', ', is_a_tax, in_late_penalty_base, applies_to_customer_types', $v$, false, true, '{residential}'$v$),
  '23502', 'is_taxable_default');
SELECT pg_temp.refuses_at('T2 a version that does not state whether it is a tax',
  pg_temp.version_sql('00000000-0000-4000-8000-000000003011', ', is_taxable_default, in_late_penalty_base, applies_to_customer_types', $v$, true, true, '{residential}'$v$),
  '23502', 'is_a_tax');
SELECT pg_temp.refuses_at('T3 a version that does not state whether it is in the late-penalty base',
  pg_temp.version_sql('00000000-0000-4000-8000-000000003011', ', is_taxable_default, is_a_tax, applies_to_customer_types', $v$, true, false, '{residential}'$v$),
  '23502', 'in_late_penalty_base');
SELECT pg_temp.refuses_at('T4 a version that does not state its customer types (the old default left out small and large commercial)',
  pg_temp.version_sql('00000000-0000-4000-8000-000000003011', ', is_taxable_default, is_a_tax, in_late_penalty_base', $v$, true, false, true$v$),
  '23502', 'applies_to_customer_types');
SELECT pg_temp.refuses_at('T5 an empty customer-type list',
  pg_temp.version_sql('00000000-0000-4000-8000-000000003011', ', is_taxable_default, is_a_tax, in_late_penalty_base, applies_to_customer_types', $v$, true, false, true, '{}'$v$),
  '23514', 'rate_item_versions_customer_types_check');
SELECT pg_temp.refuses_at('T6 a customer type that does not exist',
  pg_temp.version_sql('00000000-0000-4000-8000-000000003011', ', is_taxable_default, is_a_tax, in_late_penalty_base, applies_to_customer_types', $v$, true, false, true, '{residential,retail}'$v$),
  '23514', 'rate_item_versions_customer_types_check');
SELECT pg_temp.refuses_at('T6b a NULL among the customer types',
  pg_temp.version_sql('00000000-0000-4000-8000-000000003011', ', is_taxable_default, is_a_tax, in_late_penalty_base, applies_to_customer_types', $v$, true, false, true, ARRAY['residential', NULL]$v$),
  '23514', 'rate_item_versions_customer_types_check');
SELECT pg_temp.admits('T7 the customer charge: taxable, not a tax, in the penalty base, for every type including small and large commercial',
  pg_temp.version_sql('00000000-0000-4000-8000-000000003011', ', is_taxable_default, is_a_tax, in_late_penalty_base, applies_to_customer_types',
    $v$, true, false, true, '{residential,commercial,small_commercial,large_commercial,industrial,government,wholesale}'$v$));
SELECT pg_temp.ok('T8 no default left on the four columns',
  (SELECT count(*) = 4 AND bool_and(column_default IS NULL AND is_nullable = 'NO') FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'rate_item_versions'
      AND column_name IN ('is_taxable_default', 'is_a_tax', 'in_late_penalty_base', 'applies_to_customer_types')));
SELECT pg_temp.ok('T9 the taxability comment no longer calls the default an open question',
  col_description('public.rate_item_versions'::regclass,
                  (SELECT attnum FROM pg_attribute WHERE attrelid = 'public.rate_item_versions'::regclass AND attname = 'is_taxable_default')) !~* 'open question');

SELECT pg_temp.refuses_at('P1 a tax in the late-penalty base (Kyle: never on taxes)',
  pg_temp.version_sql('00000000-0000-4000-8000-000000003013', ', is_taxable_default, is_a_tax, in_late_penalty_base, applies_to_customer_types', $v$, false, true, true, '{residential}'$v$),
  '23514', 'late-penalty base');
SELECT pg_temp.admits('P2 the same tax, out of the penalty base',
  pg_temp.version_sql('00000000-0000-4000-8000-000000003013', ', is_taxable_default, is_a_tax, in_late_penalty_base, applies_to_customer_types', $v$, false, true, false, '{residential}'$v$));
-- The fee's surcharge rule (excluded from tax bases) comes first; the fee then has no version.
INSERT INTO public.regulatory_surcharge_rules (tenant_id, rate_item_id, surcharge_kind, cycle_start, cycle_end, cap_per_service, excluded_from_tax_bases, exempts_state_agencies) VALUES
  ('00000000-0000-4000-8000-0000000030a1', '00000000-0000-4000-8000-000000003012', 'pipeline_safety_fee', DATE '2026-01-01', DATE '2026-12-31', 50, true, true);
SELECT pg_temp.refuses_at('P4 the fee''s version put into the penalty base (Kyle: never on state fees)',
  pg_temp.version_sql('00000000-0000-4000-8000-000000003012', ', is_taxable_default, is_a_tax, in_late_penalty_base, applies_to_customer_types', $v$, false, false, true, '{residential}'$v$),
  '23514', 'late-penalty base');
SELECT pg_temp.admits('P3 the pipeline safety fee, out of every base',
  pg_temp.version_sql('00000000-0000-4000-8000-000000003012', ', is_taxable_default, is_a_tax, in_late_penalty_base, applies_to_customer_types', $v$, false, false, false, '{residential}'$v$));
SELECT pg_temp.admits('P5 a rider in the penalty base but not taxable (so only the penalty-base rule speaks in P6)',
  pg_temp.version_sql('00000000-0000-4000-8000-000000003014', ', is_taxable_default, is_a_tax, in_late_penalty_base, applies_to_customer_types', $v$, false, false, true, '{residential}'$v$));
SELECT pg_temp.refuses_at('P6 the other order: an excluded-from-tax-bases rule for a rider whose open version is in the penalty base',
  $q$INSERT INTO public.regulatory_surcharge_rules (tenant_id, rate_item_id, surcharge_kind, cycle_start, cycle_end, cap_per_service, excluded_from_tax_bases, exempts_state_agencies)
     VALUES ('00000000-0000-4000-8000-0000000030a1', '00000000-0000-4000-8000-000000003014', 'pipeline_safety_fee', DATE '2026-01-01', DATE '2026-12-31', 50, true, true)$q$,
  '23514', 'late-penalty base');
SELECT pg_temp.ok('P7 both late-penalty guards fire always (as -07''s taxability guard)',
  (SELECT count(*) = 2 AND bool_and(tgenabled = 'A') FROM pg_trigger
    WHERE (tgrelid, tgname) IN (('public.rate_item_versions'::regclass, 'b_enforce_late_penalty_base'),
                                ('public.regulatory_surcharge_rules'::regclass, 'c_enforce_surcharge_rule_late_penalty_base'))));

-- ---------------------------------------------------------------------------
-- E  exemptions name their services
-- ---------------------------------------------------------------------------
SELECT pg_temp.refuses_at('E1 an exemption with no service types',
  $q$INSERT INTO public.customer_tax_exemptions (tenant_id, customer_id, exemption_type, effective_start)
     VALUES ('00000000-0000-4000-8000-0000000030a1', '00000000-0000-4000-8000-0000000030c2', 'religious', DATE '2026-01-01')$q$,
  '23514', 'customer_tax_exemptions_service_types_check');
SELECT pg_temp.refuses_at('E2 an exemption with an empty list of service types',
  $q$INSERT INTO public.customer_tax_exemptions (tenant_id, customer_id, exemption_type, effective_start, service_types)
     VALUES ('00000000-0000-4000-8000-0000000030a1', '00000000-0000-4000-8000-0000000030c2', 'religious', DATE '2026-01-01', '{}')$q$,
  '23514', 'customer_tax_exemptions_service_types_check');
SELECT pg_temp.refuses_at('E2b a NULL among the service types',
  $q$INSERT INTO public.customer_tax_exemptions (tenant_id, customer_id, exemption_type, effective_start, service_types)
     VALUES ('00000000-0000-4000-8000-0000000030a1', '00000000-0000-4000-8000-0000000030c2', 'religious', DATE '2026-01-01', ARRAY['gas', NULL])$q$,
  '23514', 'customer_tax_exemptions_service_types_check');
SELECT pg_temp.refuses_at('E2c a misspelled service (Gas): refused, not silently matching nothing',
  $q$INSERT INTO public.customer_tax_exemptions (tenant_id, customer_id, exemption_type, effective_start, service_types)
     VALUES ('00000000-0000-4000-8000-0000000030a1', '00000000-0000-4000-8000-0000000030c2', 'religious', DATE '2026-01-01', '{Gas}')$q$,
  '23514', 'customer_tax_exemptions_service_types_check');
SELECT pg_temp.refuses_at('E2d "all" is not a service: every service is the list written out',
  $q$INSERT INTO public.customer_tax_exemptions (tenant_id, customer_id, exemption_type, effective_start, service_types)
     VALUES ('00000000-0000-4000-8000-0000000030a1', '00000000-0000-4000-8000-0000000030c2', 'religious', DATE '2026-01-01', '{all}')$q$,
  '23514', 'customer_tax_exemptions_service_types_check');
SELECT pg_temp.ok('E2e the exemption comments no longer say an empty list means every service',
  obj_description('public.customer_tax_exemptions'::regclass, 'pg_class') !~* 'empty (array|list)'
  AND col_description('public.customer_tax_exemptions'::regclass,
        (SELECT attnum FROM pg_attribute WHERE attrelid = 'public.customer_tax_exemptions'::regclass AND attname = 'service_types')) !~* 'empty (array|list)');
SELECT pg_temp.admits('E3 a verified exemption for gas only',
  $q$INSERT INTO public.customer_tax_exemptions (id, tenant_id, customer_id, exemption_type, effective_start, service_types,
        certificate_url, status, verified_by, verified_at)
     VALUES ('00000000-0000-4000-8000-0000000030ce', '00000000-0000-4000-8000-0000000030a1', '00000000-0000-4000-8000-0000000030c2', 'educational', DATE '2026-01-01', '{gas}',
             'https://artifacts.example/comptroller-letter-30.pdf', 'active', '00000000-0000-4000-8000-0000000030b1', now())$q$);
SELECT pg_temp.ok('E4 a taxable gas line of the exempt customer: not taxed',
  public.should_charge_tax('00000000-0000-4000-8000-0000000030c2', true, 'gas', DATE '2026-03-01', now()) = false);
SELECT pg_temp.ok('E5 a taxable water line of the same customer: taxed (the exemption names gas only)',
  public.should_charge_tax('00000000-0000-4000-8000-0000000030c2', true, 'water', DATE '2026-03-01', now()) = true);
SELECT pg_temp.refuses_at('E6 a line with no service type is not matched to any exemption: the call raises',
  $q$SELECT public.should_charge_tax('00000000-0000-4000-8000-0000000030c2', true, NULL, DATE '2026-03-01', now())$q$,
  '22004', 'a service type is required');
SELECT pg_temp.ok('E7 a non-taxable item stays untaxed for a taxable customer',
  public.should_charge_tax('00000000-0000-4000-8000-0000000030c1', false, 'gas', DATE '2026-03-01', now()) = false);

-- ---------------------------------------------------------------------------
-- M  a premise's places as known at a past instant
-- ---------------------------------------------------------------------------
INSERT INTO public.premise_place_memberships (id, tenant_id, service_location_id, place_id, axis, place_kind, valid_from, evidence_kind, evidence_reference, evidence_date) VALUES
  ('00000000-0000-4000-8000-0000000030a7', '00000000-0000-4000-8000-0000000030a1', '00000000-0000-4000-8000-0000000030d1', '00000000-0000-4000-8000-0000000030e1',
   'tax', 'municipality', DATE '2020-01-01', 'address_lookup', 'Comptroller address file 2020Q1', DATE '2020-01-01'),
  ('00000000-0000-4000-8000-0000000030a8', '00000000-0000-4000-8000-0000000030a1', '00000000-0000-4000-8000-0000000030d1', '00000000-0000-4000-8000-0000000030e3',
   'tax', 'county', DATE '2020-01-01', 'address_lookup', 'Comptroller address file 2020Q1', DATE '2020-01-01');
-- Both recorded two days ago (planted); then, now, the city membership is
-- closed at 2026-04-01 and the county membership voided (with every guard on).
-- The battery's own places (the city, its area, the county, Old City, New
-- Mexico) are planted as recorded two days ago too, as are the premises'
-- states (fixtures). "A moment ago" (one second) is after every plant; "before
-- the premise was recorded" is taken from its own planted stamp.
ALTER TABLE public.premise_place_memberships DISABLE TRIGGER a_enforce_premise_place_membership;
UPDATE public.premise_place_memberships SET created_at = now() - interval '2 days'
 WHERE id IN ('00000000-0000-4000-8000-0000000030a7', '00000000-0000-4000-8000-0000000030a8', '00000000-0000-4000-8000-0000000030aa',
              '00000000-0000-4000-8000-0000000030ab', '00000000-0000-4000-8000-0000000030ac');
ALTER TABLE public.premise_place_memberships ENABLE ALWAYS TRIGGER a_enforce_premise_place_membership;
ALTER TABLE public.places DISABLE TRIGGER a_enforce_place;
UPDATE public.places SET created_at = now() - interval '2 days'
 WHERE id IN ('00000000-0000-4000-8000-0000000030e1', '00000000-0000-4000-8000-0000000030e2', '00000000-0000-4000-8000-0000000030e3',
              '00000000-0000-4000-8000-0000000030e8', '00000000-0000-4000-8000-0000000030e9');
ALTER TABLE public.places ENABLE ALWAYS TRIGGER a_enforce_place;
UPDATE public.premise_place_memberships SET valid_to = DATE '2026-04-01' WHERE id = '00000000-0000-4000-8000-0000000030a7';
UPDATE public.premise_place_memberships SET void_reason = 'wrong county keyed' WHERE id = '00000000-0000-4000-8000-0000000030a8';
-- A third, recorded now: the limited-purpose area from 2026-04-01.
INSERT INTO public.premise_place_memberships (id, tenant_id, service_location_id, place_id, axis, place_kind, valid_from, evidence_kind, evidence_reference, evidence_date) VALUES
  ('00000000-0000-4000-8000-0000000030a9', '00000000-0000-4000-8000-0000000030a1', '00000000-0000-4000-8000-0000000030d1', '00000000-0000-4000-8000-0000000030e2',
   'tax', 'limited_purpose_area', DATE '2026-04-01', 'ordinance', 'Battery City Ord. 30-3 (disannexation to limited purpose)', DATE '2026-03-01');

SELECT pg_temp.ok('M1 on 2026-06-01, as known now: below the state, the limited-purpose area only',
  (SELECT array_agg(place_id ORDER BY place_id) = ARRAY['00000000-0000-4000-8000-0000000030e2'::uuid]
     FROM public.premise_places_as_of('00000000-0000-4000-8000-0000000030d1', DATE '2026-06-01', 'tax', now()) WHERE kind_code <> 'state'));
SELECT pg_temp.ok('M2 on 2026-06-01, as known a moment ago: the city (not yet closed) and the county (not yet voided), not the area (not yet recorded)',
  (SELECT array_agg(place_id ORDER BY place_id) = ARRAY['00000000-0000-4000-8000-0000000030e1'::uuid, '00000000-0000-4000-8000-0000000030e3'::uuid]
     FROM public.premise_places_as_of('00000000-0000-4000-8000-0000000030d1', DATE '2026-06-01', 'tax', now() - interval '1 second') WHERE kind_code <> 'state'));
SELECT pg_temp.refuses_at('M3 as known before the premise was recorded: its places cannot be read',
  format($f$SELECT * FROM public.premise_places_as_of('00000000-0000-4000-8000-0000000030d1', DATE '2026-06-01', 'tax', %L::timestamptz)$f$,
         (SELECT min(recorded_at) - interval '1 second' FROM public.service_location_state_history WHERE service_location_id = '00000000-0000-4000-8000-0000000030d1')),
  'P0002', 'not yet recorded');
SELECT pg_temp.ok('M4 the three-argument form still reads as known now',
  (SELECT array_agg(place_id) = ARRAY['00000000-0000-4000-8000-0000000030e2'::uuid]
     FROM public.premise_places_as_of('00000000-0000-4000-8000-0000000030d1', DATE '2026-06-01', 'tax') WHERE kind_code <> 'state'));
SELECT pg_temp.refuses_at('M5 no recorded instant',
  $q$SELECT * FROM public.premise_places_as_of('00000000-0000-4000-8000-0000000030d1', DATE '2026-06-01', 'tax', NULL)$q$,
  '22004', 'a recorded-at instant is required');

-- The premise's state as known (r1, Opus B1, Codex B2): d2's county membership
-- is voided now and its state then corrected to New Mexico, with every guard on.
UPDATE public.premise_place_memberships SET void_reason = 'premise keyed in the wrong state' WHERE id = '00000000-0000-4000-8000-0000000030aa';
UPDATE public.service_locations SET state = 'NM' WHERE id = '00000000-0000-4000-8000-0000000030d2';
SELECT pg_temp.ok_q('M6 d2 on 2026-06-01, as known a moment ago: Texas and its county, as a bill then saw them',
  $q$SELECT (SELECT array_agg(place_code ORDER BY place_code) = ARRAY['48996', 'TX']
               FROM public.premise_places_as_of('00000000-0000-4000-8000-0000000030d2', DATE '2026-06-01', 'tax', now() - interval '1 second'))$q$);
SELECT pg_temp.ok_q('M7 d2 as known now: New Mexico only',
  $q$SELECT (SELECT array_agg(place_code) = ARRAY['NM']
               FROM public.premise_places_as_of('00000000-0000-4000-8000-0000000030d2', DATE '2026-06-01', 'tax', now()))$q$);
SELECT pg_temp.ok('M8 d2''s states are recorded in order, the correction stamped now',
  (SELECT array_agg(state ORDER BY recorded_at, seq) = ARRAY['TX', 'NM'] AND max(recorded_at) = now()
     FROM public.service_location_state_history WHERE service_location_id = '00000000-0000-4000-8000-0000000030d2'));
UPDATE public.service_locations SET state = ' nm' WHERE id = '00000000-0000-4000-8000-0000000030d2';
SELECT pg_temp.ok('M8b a write that keeps the state (" nm": only its spelling) records nothing',
  (SELECT count(*) = 2 FROM public.service_location_state_history WHERE service_location_id = '00000000-0000-4000-8000-0000000030d2'));
SELECT pg_temp.ok('M9 every premise has its state recorded (backfill and insert)',
  NOT EXISTS (SELECT 1 FROM public.service_locations l
               WHERE NOT EXISTS (SELECT 1 FROM public.service_location_state_history h WHERE h.service_location_id = l.id)));
SET ROLE tally_app;
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000030b1', true);
SELECT pg_temp.refuses_at('M10 the app writes no state history of its own',
  $q$INSERT INTO public.service_location_state_history (tenant_id, service_location_id, state, recorded_at)
     VALUES ('00000000-0000-4000-8000-0000000030a1', '00000000-0000-4000-8000-0000000030d1', 'NM', now() - interval '5 days')$q$,
  '42501', 'written by the database');
-- No UPDATE privilege; the append-only trigger stands behind it (every role).
SELECT pg_temp.refuses_at('M10b nor edits it',
  $q$UPDATE public.service_location_state_history SET state = 'NM' WHERE service_location_id = '00000000-0000-4000-8000-0000000030d1'$q$,
  '42501', 'service_location_state_history');
SELECT pg_temp.admits('M10c a premise the app adds has its state recorded',
  $q$INSERT INTO public.service_locations (id, tenant_id, customer_id, location_number, address_line1, city, state, zip)
     VALUES ('00000000-0000-4000-8000-0000000030d5', '00000000-0000-4000-8000-0000000030a1', '00000000-0000-4000-8000-0000000030c1', 'L5', '5 Main', 'Battery City', 'tx ', '78701')$q$);
SELECT pg_temp.ok('M10d recorded normalised, by the database, now',
  (SELECT count(*) = 1 AND bool_and(state = 'TX' AND recorded_at = now()) FROM public.service_location_state_history
    WHERE service_location_id = '00000000-0000-4000-8000-0000000030d5'));
RESET ROLE;
-- A place's end as known (r1, Opus S5): d4's Old City membership and Old City
-- itself are closed now at 2026-05-01.
UPDATE public.premise_place_memberships SET valid_to = DATE '2026-05-01' WHERE id = '00000000-0000-4000-8000-0000000030ac';
UPDATE public.places SET effective_to = DATE '2026-05-01' WHERE id = '00000000-0000-4000-8000-0000000030e8';
SELECT pg_temp.ok_q('M11 d4 on 2026-06-01, as known a moment ago: Old City, then still open',
  $q$SELECT (SELECT array_agg(place_code ORDER BY place_code) = ARRAY['TX', 'TX-B30-OLD']
               FROM public.premise_places_as_of('00000000-0000-4000-8000-0000000030d4', DATE '2026-06-01', 'tax', now() - interval '1 second'))$q$);
SELECT pg_temp.ok_q('M11b as known now: closed',
  $q$SELECT (SELECT array_agg(place_code) = ARRAY['TX']
               FROM public.premise_places_as_of('00000000-0000-4000-8000-0000000030d4', DATE '2026-06-01', 'tax', now()))$q$);

-- G5: a published rate with no levy at all is reported (r1, Fable S6). d3 is
-- in the county; the county publishes 0.5 from 2026-01-01; the utility's county
-- levy ends 2026-07-01.
INSERT INTO public.place_facts (place_id, fact_code, value, effective_from, source_note) VALUES
  ('00000000-0000-4000-8000-0000000030e3', 'sales_tax_rate', '0.5', DATE '2026-01-01', 'Comptroller rate file 2026Q1 (battery 30)');
SELECT pg_temp.ok('G5 on 2026-08-01 the county publishes 0.5 and the utility has no county levy: reported, no levy named',
  (SELECT count(*) = 1 AND bool_and(levy_id IS NULL AND levy_rate_percent IS NULL AND reference_rate_percent = 0.5)
     FROM public.tax_levy_reference_gaps('00000000-0000-4000-8000-0000000030a1', DATE '2026-08-01') WHERE place_code = '48996'));
SELECT pg_temp.ok('G5b on 2026-03-01 the county levy (0.5) agrees: not reported',
  NOT EXISTS (SELECT 1 FROM public.tax_levy_reference_gaps('00000000-0000-4000-8000-0000000030a1', DATE '2026-03-01') WHERE place_code = '48996'));

-- ---------------------------------------------------------------------------
-- A  a state agency's basis
-- ---------------------------------------------------------------------------
SET ROLE tally_app;
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000030b1', true);
SELECT pg_temp.refuses_at('A1 a customer set as a state agency with no basis',
  $q$UPDATE public.customers SET is_state_agency = true WHERE id = '00000000-0000-4000-8000-0000000030c2'$q$,
  '23514', 'customers_state_agency_basis_check');
SELECT pg_temp.refuses_at('A2 a basis that is only a tab',
  $q$UPDATE public.customers SET is_state_agency = true, state_agency_basis = E'\t' WHERE id = '00000000-0000-4000-8000-0000000030c2'$q$,
  '23514', 'customers_state_agency_basis_check');
SELECT pg_temp.refuses_at('A3 a new customer born a state agency with no basis',
  $q$INSERT INTO public.customers (tenant_id, customer_number, customer_type, is_state_agency) VALUES ('00000000-0000-4000-8000-0000000030a1', 'B30-C3', 'government', true)$q$,
  '23514', 'customers_state_agency_basis_check');
SELECT pg_temp.admits('A4 with its basis (a public university, Gov''t Code 572.002)',
  $q$UPDATE public.customers SET is_state_agency = true, state_agency_basis = 'Gov''t Code 572.002: public university; RRC letter on file'
      WHERE id = '00000000-0000-4000-8000-0000000030c2'$q$);
RESET ROLE;
SELECT pg_temp.ok('A5 the basis is logged in the attribute history beside the flag',
  (SELECT count(*) = 1 FROM public.customer_attribute_history
    WHERE customer_id = '00000000-0000-4000-8000-0000000030c2' AND attribute = 'state_agency_basis' AND new_value ~ '572.002')
  AND (SELECT count(*) = 1 FROM public.customer_attribute_history
    WHERE customer_id = '00000000-0000-4000-8000-0000000030c2' AND attribute = 'is_state_agency' AND new_value = 'true'));
SELECT pg_temp.ok('A6 a customer that is not a state agency needs no basis',
  (SELECT state_agency_basis IS NULL AND NOT is_state_agency FROM public.customers WHERE id = '00000000-0000-4000-8000-0000000030c1'));

DO $$ BEGIN RAISE NOTICE 'battery-30: all checks passed'; END $$;
ROLLBACK;
