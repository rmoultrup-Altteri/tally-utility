-- ============================================================================
-- BATTERY v5.4.2-16 — places and applicability (2026-10-07; round-4 revision)
-- Run: psql -U tally -d <db-with-patch> -v ON_ERROR_STOP=1 -f battery-16.sql
-- One transaction, rolled back. Negative cases inside DO blocks that check
-- the SQLSTATE; each built so only the guard it names can refuse it. Written
-- as tally_app except the platform rows (places, facts), which only reviewed
-- migrations write. TWO tenants. ZZ is a fictional second state. Success
-- checks use IS DISTINCT FROM, so a NULL is a failure (review r1, Codex).
--
--   A  vocabularies and places are platform-held, close-only   (sections 2-3)
--   F  place facts                                              (section 4)
--   M  premise memberships                                      (section 5)
--   S  a premise's state under its memberships                  (section 5)
--   P  utility service profiles                                 (section 6)
--   L  lookups                                                  (section 8)
--   C  a place's close floor                                    (section 3)
--   J  jurisdictions point at places                            (section 7)
--   N  review round 2: conflicts, voids, ranges, hygiene, boundaries
--   T  review round 3: finite distance, a state's profiles, unzoned peers,
--      citation keys, boundaries the mutations found untested
--   U  review round 4: negative distance, agreeing zones, a state before it
--      begins, owner vs system, tax-axis ETJ, keys, unknown place, no-op edit
--   G  tenancy, the AC-32 tail                                  (section 11)
-- Races and isolation (both sides of the place lock; a state change against a
-- membership): races/place-close-16.sh.
-- ============================================================================
BEGIN;
SET CONSTRAINTS ALL IMMEDIATE;

-- ------------------------------------------------------------------ fixtures
INSERT INTO public.tenants (id, name, slug) VALUES
  ('00000000-0000-4000-8000-0000000016a1', 'T1 City Gas', 'bat16-t1'),
  ('00000000-0000-4000-8000-0000000016a2', 'T2 Gasco', 'bat16-t2');
INSERT INTO public.users (id, tenant_id, display_name, email, role) VALUES
  ('00000000-0000-4000-8000-0000000016b1', '00000000-0000-4000-8000-0000000016a1', 'Op1', 'op1@bat16.test', 'operator'),
  ('00000000-0000-4000-8000-0000000016b2', '00000000-0000-4000-8000-0000000016a2', 'Op2', 'op2@bat16.test', 'operator');
INSERT INTO public.customers (id, tenant_id, customer_number, customer_type) VALUES
  ('00000000-0000-4000-8000-0000000016c1', '00000000-0000-4000-8000-0000000016a1', 'B16-C1', 'residential'),
  ('00000000-0000-4000-8000-0000000016c9', '00000000-0000-4000-8000-0000000016a2', 'B16-C9', 'residential');
-- L1 El Paso; L2 Austin area; L3 a ZZ premise; L4 El Paso, no county
-- recorded; L5 ' tx ' (padded, as -12 stores it); L6 'Texas'; L9 T2's.
INSERT INTO public.service_locations (id, tenant_id, customer_id, location_number, address_line1, city, state, zip) VALUES
  ('00000000-0000-4000-8000-0000000016d1', '00000000-0000-4000-8000-0000000016a1', '00000000-0000-4000-8000-0000000016c1', 'L1', '1 Main', 'El Paso', 'TX', '79901'),
  ('00000000-0000-4000-8000-0000000016d2', '00000000-0000-4000-8000-0000000016a1', '00000000-0000-4000-8000-0000000016c1', 'L2', '2 Main', 'Austin', 'TX', '78701'),
  ('00000000-0000-4000-8000-0000000016d3', '00000000-0000-4000-8000-0000000016a1', '00000000-0000-4000-8000-0000000016c1', 'L3', '3 Main', 'Zedton', 'ZZ', '00001'),
  ('00000000-0000-4000-8000-0000000016d4', '00000000-0000-4000-8000-0000000016a1', '00000000-0000-4000-8000-0000000016c1', 'L4', '4 Main', 'El Paso', 'TX', '79902'),
  ('00000000-0000-4000-8000-0000000016d5', '00000000-0000-4000-8000-0000000016a1', '00000000-0000-4000-8000-0000000016c1', 'L5', '5 Main', 'Austin', ' tx ', '78705'),
  ('00000000-0000-4000-8000-0000000016d6', '00000000-0000-4000-8000-0000000016a1', '00000000-0000-4000-8000-0000000016c1', 'L6', '6 Main', 'Austin', 'Texas', '78706'),
  ('00000000-0000-4000-8000-0000000016d9', '00000000-0000-4000-8000-0000000016a2', '00000000-0000-4000-8000-0000000016c9', 'L9', '9 Main', 'Austin', 'TX', '78702');

CREATE TEMP TABLE b16 (k text PRIMARY KEY, id uuid);
GRANT SELECT, INSERT ON b16 TO tally_app;
CREATE FUNCTION pg_temp.id(p_k text) RETURNS uuid LANGUAGE sql STABLE AS $$ SELECT id FROM b16 WHERE k = p_k $$;
GRANT EXECUTE ON FUNCTION pg_temp.id(text) TO tally_app;
-- place(): a platform place (owner), remembered by key.
CREATE FUNCTION pg_temp.place(p_k text, p_kind text, p_state text, p_code text, p_parent text, p_from date, p_to date DEFAULT NULL) RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE v uuid;
BEGIN
  INSERT INTO public.places (kind_code, state_code, place_code, name, parent_place_id, effective_from, effective_to, source_note)
  VALUES (p_kind, p_state, p_code, 'Place ' || p_k, pg_temp.id(p_parent), p_from, p_to, 'battery fixture ' || p_k)
  RETURNING id INTO v;
  INSERT INTO b16 VALUES (p_k, v);
  RETURN v;
END $$;
-- fact(): a platform fact (owner).
CREATE FUNCTION pg_temp.fact(p_place text, p_code text, p_value jsonb, p_from date, p_key text DEFAULT NULL) RETURNS uuid
LANGUAGE sql AS $$
  INSERT INTO public.place_facts (place_id, fact_code, fact_key, value, effective_from, source_note)
  VALUES (pg_temp.id(p_place), p_code, p_key, p_value, p_from, 'battery fact') RETURNING id
$$;
-- mem(): a membership as the utility records it. It passes a wrong kind, a
-- wrong group, T2's user as created_by and an old created_at: the trigger
-- sets all four.
CREATE FUNCTION pg_temp.mem(p_loc uuid, p_place uuid, p_axis text, p_from date, p_to date DEFAULT NULL,
                            p_relation text DEFAULT 'within', p_distance numeric DEFAULT NULL) RETURNS uuid
LANGUAGE sql AS $$
  INSERT INTO public.premise_place_memberships (tenant_id, service_location_id, place_id, axis, relation, distance_miles, place_kind, exclusivity_group,
                                                valid_from, valid_to, evidence_kind, evidence_reference, evidence_date, created_by, created_at)
  SELECT l.tenant_id, l.id, p_place, p_axis, p_relation, p_distance, 'state', 'bogus', p_from, p_to, 'ordinance', 'Ord. 2020-1', DATE '2019-12-01',
         '00000000-0000-4000-8000-0000000016b2', TIMESTAMPTZ '2001-01-01'
    FROM public.service_locations l WHERE l.id = p_loc
  RETURNING id
$$;
GRANT EXECUTE ON FUNCTION pg_temp.mem(uuid, uuid, text, date, date, text, numeric) TO tally_app;
-- prof(): a profile.
CREATE FUNCTION pg_temp.prof(p_service text, p_state text, p_owner text, p_comm boolean, p_place uuid, p_from date) RETURNS uuid
LANGUAGE sql AS $$
  INSERT INTO public.utility_service_profiles (tenant_id, service_type, system_kind, state_code, owner_type, commission_jurisdiction,
                                               owning_place_id, effective_from, evidence_reference, evidence_date)
  VALUES ('00000000-0000-4000-8000-0000000016a1', p_service, 'distribution', p_state, p_owner, p_comm, p_place, p_from, 'City charter art. 9', p_from)
  RETURNING id
$$;
GRANT EXECUTE ON FUNCTION pg_temp.prof(text, text, text, boolean, uuid, date) TO tally_app;

-- Platform fixtures (owner).
DO $$ BEGIN
  INSERT INTO b16 SELECT 'tx', id FROM public.places WHERE kind_code = 'state' AND place_code = 'TX';
  INSERT INTO b16 SELECT 'elpaso_cty', id FROM public.places WHERE kind_code = 'county' AND place_code = '48141';
  PERFORM pg_temp.place('zz', 'state', 'ZZ', 'ZZ', NULL, DATE '1900-01-01');
  PERFORM pg_temp.place('travis', 'county', 'TX', '48453', 'tx', DATE '1900-01-01');
  PERFORM pg_temp.fact('travis', 'time_zone', '"America/Chicago"', DATE '1900-01-01');
  PERFORM pg_temp.place('elpaso', 'municipality', 'TX', 'ELPASO', 'tx', DATE '1900-01-01');
  PERFORM pg_temp.place('austin', 'municipality', 'TX', 'AUSTIN', 'tx', DATE '1900-01-01');
  PERFORM pg_temp.place('roundrock', 'municipality', 'TX', 'ROUNDROCK', 'tx', DATE '1913-01-01');
  PERFORM pg_temp.place('austin_etj', 'extraterritorial_area', 'TX', 'AUSTIN-ETJ', 'austin', DATE '1963-01-01');
  PERFORM pg_temp.place('cmta', 'transit_authority', 'TX', 'CMTA', 'tx', DATE '1985-01-01');
  PERFORM pg_temp.place('esd1', 'special_purpose_district', 'TX', 'ESD1', 'austin', DATE '2000-01-01');
  PERFORM pg_temp.place('esd2', 'special_purpose_district', 'TX', 'ESD2', 'austin', DATE '2000-01-01');
  PERFORM pg_temp.place('zcity', 'municipality', 'ZZ', 'ZEDTON', 'zz', DATE '1950-01-01');
  PERFORM pg_temp.place('short', 'municipality', 'TX', 'SHORTVILLE', 'tx', DATE '2020-01-01', DATE '2025-01-01');
  PERFORM pg_temp.place('lonely', 'municipality', 'TX', 'LONELY', 'tx', DATE '1950-01-01');
END $$;


-- ============================================================ A. platform-held
SET LOCAL app.user_id = '00000000-0000-4000-8000-0000000016b1';
SET ROLE tally_app;
DO $$ BEGIN
  INSERT INTO public.places (kind_code, state_code, place_code, name, effective_from, source_note)
  VALUES ('municipality', 'TX', 'XTOWN', 'X', DATE '2020-01-01', 'x');
  RAISE EXCEPTION 'FAIL A1a: the application wrote a place';
EXCEPTION WHEN insufficient_privilege THEN NULL; END $$;
DO $$ BEGIN
  INSERT INTO public.place_facts (place_id, fact_code, value, effective_from, source_note)
  VALUES (pg_temp.id('austin'), 'census_population', '1000', DATE '2020-01-01', 'x');
  RAISE EXCEPTION 'FAIL A1b: the application wrote a place fact';
EXCEPTION WHEN insufficient_privilege THEN NULL; END $$;
DO $$ BEGIN
  INSERT INTO public.utility_owner_types (owner_type, owning_place_kinds, description, source_note) VALUES ('x', '{}', 'x', 'x');
  RAISE EXCEPTION 'FAIL A1c: the application wrote an owner type';
EXCEPTION WHEN insufficient_privilege THEN
  RAISE NOTICE 'PASS A1: the application cannot write places, place facts or the vocabularies'; END $$;
RESET ROLE;
DO $$ BEGIN
  UPDATE public.places SET name = 'Austin, Texas' WHERE id = pg_temp.id('austin');
  RAISE EXCEPTION 'FAIL A2a: a place renamed';
EXCEPTION WHEN restrict_violation THEN NULL; END $$;
DO $$ BEGIN
  UPDATE public.places SET effective_to = DATE '2090-01-01', name = 'x' WHERE id = pg_temp.id('lonely');
  RAISE EXCEPTION 'FAIL A2b: a close that carries an edit';
EXCEPTION WHEN restrict_violation THEN NULL; END $$;
DO $$ BEGIN
  DELETE FROM public.places WHERE id = pg_temp.id('lonely');
  RAISE EXCEPTION 'FAIL A2c: a place deleted';
EXCEPTION WHEN restrict_violation THEN
  RAISE NOTICE 'PASS A2: a place is never edited or deleted, only closed (and a close carries nothing else)'; END $$;
DO $$ BEGIN
  UPDATE public.place_kinds SET exclusivity_group = NULL WHERE kind_code = 'county';
  RAISE EXCEPTION 'FAIL A3a: a place kind edited';
EXCEPTION WHEN restrict_violation THEN NULL; END $$;
DO $$ BEGIN
  DELETE FROM public.utility_owner_types WHERE owner_type = 'cooperative';
  RAISE EXCEPTION 'FAIL A3b: an owner type deleted';
EXCEPTION WHEN restrict_violation THEN NULL; END $$;
DO $$ BEGIN
  -- place_fact_kinds cascades only to place_facts (platform), so only the
  -- platform tables' own guard can refuse
  TRUNCATE public.place_fact_kinds CASCADE;
  RAISE EXCEPTION 'FAIL A3c: the fact kinds truncated';
EXCEPTION WHEN restrict_violation THEN
  RAISE NOTICE 'PASS A3: the vocabularies are never edited or deleted, and no platform table is truncated, by the owner either'; END $$;
DO $$ BEGIN
  PERFORM pg_temp.place('badfips', 'county', 'TX', '4845', 'tx', DATE '1900-01-01');
  RAISE EXCEPTION 'FAIL A4a: a county code of four digits';
EXCEPTION WHEN check_violation THEN NULL; END $$;
DO $$ BEGIN
  PERFORM pg_temp.place('badstate', 'state', 'OK', 'TX', NULL, DATE '1900-01-01');
  RAISE EXCEPTION 'FAIL A4b: a state whose code is not its state';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'PASS A4: a place''s code is of its kind''s form (a county a 5-digit FIPS code; a state its own code)'; END $$;
DO $$ BEGIN
  PERFORM pg_temp.place('zzkid', 'municipality', 'ZZ', 'ZKID', 'tx', DATE '2000-01-01');
  RAISE EXCEPTION 'FAIL A5a: a ZZ place under the Texas state';
EXCEPTION WHEN check_violation THEN NULL; END $$;
DO $$ BEGIN
  PERFORM pg_temp.place('earlykid', 'extraterritorial_area', 'TX', 'EARLY', 'short', DATE '2019-01-01');
  RAISE EXCEPTION 'FAIL A5b: a child older than its parent';
EXCEPTION WHEN check_violation THEN NULL; END $$;
DO $$ BEGIN
  PERFORM pg_temp.place('ctyincity', 'county', 'TX', '48999', 'austin', DATE '2000-01-01');
  RAISE EXCEPTION 'FAIL A5c: a county under a city';
EXCEPTION WHEN check_violation THEN NULL; END $$;
DO $$ BEGIN
  PERFORM pg_temp.place('orphanetj', 'extraterritorial_area', 'TX', 'ORPHAN', NULL, DATE '2000-01-01');
  RAISE EXCEPTION 'FAIL A5d: an extraterritorial area of no city';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'PASS A5: a parent exactly when the kind takes one, of a kind it takes, the same state, in force over the whole child'; END $$;
DO $$ BEGIN
  PERFORM pg_temp.place('austin2', 'municipality', 'TX', 'AUSTIN', 'tx', DATE '2020-01-01');
  RAISE EXCEPTION 'FAIL A6: two Austins at once';
EXCEPTION WHEN exclusion_violation THEN
  RAISE NOTICE 'PASS A6: one place per kind, state and code at a time'; END $$;
DO $$ DECLARE v timestamptz; BEGIN
  INSERT INTO public.places (kind_code, state_code, place_code, name, parent_place_id, effective_from, source_note, created_at, closed_at)
  VALUES ('municipality', 'TX', 'STAMPED', 'S', pg_temp.id('tx'), DATE '2000-01-01', 'x', TIMESTAMPTZ '2001-01-01', now());
  SELECT created_at INTO v FROM public.places WHERE place_code = 'STAMPED';
  IF v IS DISTINCT FROM now() OR (SELECT closed_at FROM public.places WHERE place_code = 'STAMPED') IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL A7: a caller''s created_at or closed_at kept';
  END IF;
  RAISE NOTICE 'PASS A7: a place''s stamps are the database''s, not the caller''s';
END $$;


-- ============================================================ F. place facts
DO $$ BEGIN
  INSERT INTO public.place_facts (place_id, fact_code, value, effective_from, source_note)
  VALUES (pg_temp.id('cmta'), 'census_population', '961855', DATE '2020-01-01', 'x');
  RAISE EXCEPTION 'FAIL F1: a census population on a transit authority';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'PASS F1: a fact applies only to the place kinds its vocabulary row names'; END $$;
DO $$ BEGIN
  PERFORM pg_temp.fact('austin', 'census_population', '"lots"', DATE '2020-01-01');
  RAISE EXCEPTION 'FAIL F2a: a population that is text';
EXCEPTION WHEN check_violation THEN NULL; END $$;
DO $$ BEGIN
  PERFORM pg_temp.fact('austin', 'time_zone', '"America/Austin"', DATE '2020-01-01');
  RAISE EXCEPTION 'FAIL F2b: a time zone the server does not know';
EXCEPTION WHEN check_violation THEN NULL; END $$;
DO $$ BEGIN
  PERFORM pg_temp.fact('austin', 'time_zone', '"Factory"', DATE '2020-01-01');
  RAISE EXCEPTION 'FAIL F2c: a non-geographic zone name';
EXCEPTION WHEN check_violation THEN NULL; END $$;
DO $$ BEGIN
  PERFORM pg_temp.fact('esd1', 'special_district_type', '"  "', DATE '2020-01-01');
  RAISE EXCEPTION 'FAIL F2d: a blank text value';
EXCEPTION WHEN check_violation THEN NULL; END $$;
DO $$ BEGIN
  PERFORM pg_temp.fact('austin', 'gas_rate_jurisdiction_retained', '"yes"', DATE '2020-01-01');
  RAISE EXCEPTION 'FAIL F2e: a boolean that is text';
EXCEPTION WHEN check_violation THEN NULL; END $$;
DO $$ BEGIN
  PERFORM pg_temp.fact('austin', 'census_population', 'null', DATE '2020-01-01');
  RAISE EXCEPTION 'FAIL F2f: a JSON null';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'PASS F2: a fact''s value is of its declared type (number, boolean, non-blank text, an Area/Location zone the server knows; never JSON null)'; END $$;
DO $$ BEGIN
  PERFORM pg_temp.place('shortfact_host', 'municipality', 'TX', 'SHORTFACT', 'tx', DATE '2020-01-01');
  PERFORM pg_temp.fact('shortfact_host', 'census_population', '500', DATE '2019-01-01');
  RAISE EXCEPTION 'FAIL F3: a fact from before its place';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'PASS F3: a fact lies within its place''s range'; END $$;
SELECT pg_temp.fact('austin', 'gas_rate_jurisdiction_retained', 'true', DATE '1975-01-01');
SELECT pg_temp.fact('esd1', 'residential_gas_taxable', 'true', DATE '2000-01-01');
DO $$ BEGIN
  PERFORM pg_temp.fact('austin', 'gas_rate_jurisdiction_retained', 'false', DATE '2020-01-01');
  RAISE EXCEPTION 'FAIL F4a: two answers to one fact at once';
EXCEPTION WHEN exclusion_violation THEN NULL; END $$;
DO $$ BEGIN
  UPDATE public.place_facts SET effective_to = DATE '2030-01-01', value = 'false'
   WHERE place_id = pg_temp.id('austin') AND fact_code = 'gas_rate_jurisdiction_retained';
  RAISE EXCEPTION 'FAIL F4b: a close that carries an edit';
EXCEPTION WHEN restrict_violation THEN NULL; END $$;
DO $$ BEGIN
  DELETE FROM public.place_facts WHERE place_id = pg_temp.id('esd1');
  RAISE EXCEPTION 'FAIL F4c: a fact deleted';
EXCEPTION WHEN restrict_violation THEN
  RAISE NOTICE 'PASS F4: one answer per fact at a time; never edited or deleted, only closed'; END $$;
DO $$ DECLARE r record; BEGIN
  UPDATE public.place_facts SET effective_to = DATE '2030-01-01'
   WHERE place_id = pg_temp.id('esd1') AND fact_code = 'residential_gas_taxable';
  SELECT closed_at, closed_by INTO r FROM public.place_facts WHERE place_id = pg_temp.id('esd1');
  IF r.closed_at IS NULL OR r.closed_by IS NULL THEN RAISE EXCEPTION 'FAIL F5: the close was not stamped'; END IF;
  RAISE NOTICE 'PASS F5: a fact''s close is stamped (when, which role)';
END $$;
-- Keyed facts: each law a place adopts is its own row (review r1 S4).
DO $$ BEGIN
  PERFORM pg_temp.fact('austin', 'local_adoption', '"Ord. 2019-7"', DATE '2019-06-01', '305 ILCS 20/13');
  PERFORM pg_temp.fact('austin', 'local_adoption', '"Ord. 2021-3"', DATE '2021-01-01', 'HB 1234');
  BEGIN
    PERFORM pg_temp.fact('austin', 'local_adoption', '"Ord. 2022-1"', DATE '2022-01-01', 'HB 1234');
    RAISE EXCEPTION 'FAIL F6a: the same law adopted twice at once';
  EXCEPTION WHEN exclusion_violation THEN NULL; END;
  BEGIN
    PERFORM pg_temp.fact('austin', 'local_adoption', '"Ord. 2022-2"', DATE '2022-01-01');
    RAISE EXCEPTION 'FAIL F6b: a keyed fact without its key';
  EXCEPTION WHEN check_violation THEN NULL; END;
  BEGIN
    PERFORM pg_temp.fact('austin', 'census_population', '961855', DATE '2020-01-01', 'x');
    RAISE EXCEPTION 'FAIL F6c: an unkeyed fact with a key';
  EXCEPTION WHEN check_violation THEN NULL; END;
  RAISE NOTICE 'PASS F6: a place holds several adopted laws at once, one per law (a keyed fact); a key exactly for a keyed kind';
END $$;


-- ============================================================ M. memberships
SET LOCAL app.user_id = '00000000-0000-4000-8000-0000000016b1';
SET ROLE tally_app;
DO $$ DECLARE v uuid; r record; BEGIN
  v := pg_temp.mem('00000000-0000-4000-8000-0000000016d2', pg_temp.id('travis'), 'regulatory', DATE '2020-01-01');
  SELECT * INTO r FROM public.premise_place_memberships WHERE id = v;
  IF r.place_kind IS DISTINCT FROM 'county' OR r.exclusivity_group IS DISTINCT FROM 'county'
     OR r.created_by IS DISTINCT FROM '00000000-0000-4000-8000-0000000016b1'::uuid OR r.created_at IS DISTINCT FROM now() THEN
    RAISE EXCEPTION 'FAIL M1: the kind facets or stamps were not set from the place and session: %', row_to_json(r);
  END IF;
  RAISE NOTICE 'PASS M1: a membership''s kind, exclusivity group and created_by come from the place and the session, not the caller; stamped';
END $$;
DO $$ BEGIN
  PERFORM pg_temp.mem('00000000-0000-4000-8000-0000000016d2', pg_temp.id('tx'), 'regulatory', DATE '2020-01-01');
  RAISE EXCEPTION 'FAIL M2a: a membership in a state';
EXCEPTION WHEN check_violation THEN NULL; END $$;
DO $$ BEGIN
  PERFORM pg_temp.mem('00000000-0000-4000-8000-0000000016d2', pg_temp.id('cmta'), 'regulatory', DATE '2020-01-01');
  RAISE EXCEPTION 'FAIL M2b: a transit authority on the regulatory axis';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'PASS M2: a membership is on an axis its kind takes (a state takes none: it is the premise''s own)'; END $$;
DO $$ BEGIN
  PERFORM pg_temp.mem('00000000-0000-4000-8000-0000000016d3', pg_temp.id('austin'), 'regulatory', DATE '2020-01-01');
  RAISE EXCEPTION 'FAIL M3: a ZZ premise in a Texas city';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'PASS M3: a premise belongs only to places of its own state'; END $$;
DO $$ BEGIN
  PERFORM pg_temp.mem('00000000-0000-4000-8000-0000000016d2', pg_temp.id('short'), 'regulatory', DATE '2024-01-01', DATE '2026-01-01');
  RAISE EXCEPTION 'FAIL M4a: a membership running past its place';
EXCEPTION WHEN check_violation THEN NULL; END $$;
DO $$ BEGIN
  PERFORM pg_temp.mem('00000000-0000-4000-8000-0000000016d2', pg_temp.id('short'), 'regulatory', DATE '2019-06-01', DATE '2021-01-01');
  RAISE EXCEPTION 'FAIL M4b: a membership from before its place';
EXCEPTION WHEN check_violation THEN NULL; END $$;
DO $$ BEGIN
  -- ending exactly when the place ends is inside it
  PERFORM pg_temp.mem('00000000-0000-4000-8000-0000000016d4', pg_temp.id('short'), 'regulatory', DATE '2021-01-01', DATE '2025-01-01');
  RAISE NOTICE 'PASS M4: a membership lies within its place''s range (and may end exactly with it)';
END $$;
-- Annexation: L2 joins Austin on the ordinance date (regulatory) and on the
-- Comptroller's quarter (tax) — two memberships, two dates.
SELECT pg_temp.mem('00000000-0000-4000-8000-0000000016d2', pg_temp.id('austin'), 'regulatory', DATE '2025-12-15');
SELECT pg_temp.mem('00000000-0000-4000-8000-0000000016d2', pg_temp.id('austin'), 'tax', DATE '2026-04-01');
DO $$ BEGIN
  PERFORM pg_temp.mem('00000000-0000-4000-8000-0000000016d2', pg_temp.id('roundrock'), 'regulatory', DATE '2026-01-01');
  RAISE EXCEPTION 'FAIL M5a: two cities at once on one axis';
EXCEPTION WHEN exclusion_violation THEN NULL; END $$;
DO $$ BEGIN
  PERFORM pg_temp.mem('00000000-0000-4000-8000-0000000016d2', pg_temp.id('austin_etj'), 'regulatory', DATE '2026-01-01');
  RAISE EXCEPTION 'FAIL M5b: a city and an extraterritorial area at once';
EXCEPTION WHEN exclusion_violation THEN NULL; END $$;
DO $$ BEGIN
  -- Round Rock on the TAX axis before Austin's tax date: allowed (different
  -- dates per axis); then two districts stack.
  PERFORM pg_temp.mem('00000000-0000-4000-8000-0000000016d2', pg_temp.id('roundrock'), 'tax', DATE '2025-01-01', DATE '2026-04-01');
  PERFORM pg_temp.mem('00000000-0000-4000-8000-0000000016d2', pg_temp.id('esd1'), 'tax', DATE '2026-04-01');
  PERFORM pg_temp.mem('00000000-0000-4000-8000-0000000016d2', pg_temp.id('esd2'), 'tax', DATE '2026-04-01');
  -- the same district twice: districts stack, so only the no-repeat rule refuses
  BEGIN
    PERFORM pg_temp.mem('00000000-0000-4000-8000-0000000016d2', pg_temp.id('esd1'), 'tax', DATE '2026-05-01');
    RAISE EXCEPTION 'FAIL M5c: the same district twice';
  EXCEPTION WHEN exclusion_violation THEN NULL; END;
  RAISE NOTICE 'PASS M5: one county, one of city / limited-purpose / extraterritorial per premise and axis at a time; never the same place twice; each axis dated on its own; districts stack';
END $$;
-- Within or known outside (review r1 S1): L1 is outside Lonely, 3.5 miles;
-- outside rows do not occupy the group, and a distance only on outside.
DO $$ BEGIN
  PERFORM pg_temp.mem('00000000-0000-4000-8000-0000000016d1', pg_temp.id('lonely'), 'regulatory', DATE '2020-01-01', NULL, 'outside', 3.5);
  PERFORM pg_temp.mem('00000000-0000-4000-8000-0000000016d1', pg_temp.id('elpaso'), 'regulatory', DATE '2020-01-01');
  BEGIN
    PERFORM pg_temp.mem('00000000-0000-4000-8000-0000000016d1', pg_temp.id('elpaso_cty'), 'regulatory', DATE '2020-01-01', NULL, 'within', 2);
    RAISE EXCEPTION 'FAIL M6a: a distance on a within membership';
  EXCEPTION WHEN check_violation THEN NULL; END;
  BEGIN
    PERFORM pg_temp.mem('00000000-0000-4000-8000-0000000016d1', pg_temp.id('lonely'), 'regulatory', DATE '2021-01-01');
    RAISE EXCEPTION 'FAIL M6b: within and outside one city at once';
  EXCEPTION WHEN exclusion_violation THEN NULL; END;
  RAISE NOTICE 'PASS M6: a premise is recorded within a place or known outside it (a distance only when outside); not both at once; outside rows leave the city slot free';
END $$;
SELECT pg_temp.mem('00000000-0000-4000-8000-0000000016d1', pg_temp.id('elpaso_cty'), 'regulatory', DATE '2020-01-01');
DO $$ BEGIN
  INSERT INTO public.premise_place_memberships (tenant_id, service_location_id, place_id, axis, place_kind,
                                                valid_from, evidence_kind, evidence_reference, evidence_date)
  VALUES ('00000000-0000-4000-8000-0000000016a1', '00000000-0000-4000-8000-0000000016d2', pg_temp.id('cmta'), 'tax', 'x',
          DATE '2020-01-01', 'ordinance', '   ', DATE '2020-01-01');
  RAISE EXCEPTION 'FAIL M7a: evidence without its reference';
EXCEPTION WHEN check_violation THEN NULL; END $$;
DO $$ BEGIN
  INSERT INTO public.premise_place_memberships (tenant_id, service_location_id, place_id, axis, place_kind,
                                                valid_from, evidence_kind, evidence_reference)
  VALUES ('00000000-0000-4000-8000-0000000016a1', '00000000-0000-4000-8000-0000000016d2', pg_temp.id('cmta'), 'tax', 'x',
          DATE '2020-01-01', 'ordinance', 'Ord. 1');
  RAISE EXCEPTION 'FAIL M7b: evidence without its date';
EXCEPTION WHEN not_null_violation THEN
  RAISE NOTICE 'PASS M7: a membership states what it rests on and when (reference and date)'; END $$;
DO $$ BEGIN
  UPDATE public.premise_place_memberships SET valid_from = DATE '2019-01-01'
   WHERE service_location_id = '00000000-0000-4000-8000-0000000016d2' AND place_id = pg_temp.id('travis');
  RAISE EXCEPTION 'FAIL M8a: a membership edited';
EXCEPTION WHEN restrict_violation THEN NULL; END $$;
DO $$ BEGIN
  UPDATE public.premise_place_memberships SET valid_to = DATE '2027-01-01', evidence_reference = 'rewritten'
   WHERE service_location_id = '00000000-0000-4000-8000-0000000016d2' AND place_id = pg_temp.id('travis');
  RAISE EXCEPTION 'FAIL M8b: a close that carries an edit';
EXCEPTION WHEN restrict_violation THEN NULL; END $$;
DO $$ BEGIN
  DELETE FROM public.premise_place_memberships WHERE place_id = pg_temp.id('travis');
  RAISE EXCEPTION 'FAIL M8c: the application deleted a membership';
EXCEPTION WHEN insufficient_privilege THEN NULL; END $$;
DO $$ BEGIN
  UPDATE public.premise_place_memberships SET valid_to = DATE '2026-04-01'
   WHERE service_location_id = '00000000-0000-4000-8000-0000000016d2' AND place_id = pg_temp.id('esd2');
  RAISE EXCEPTION 'FAIL M8d: a zero-length close accepted';
EXCEPTION WHEN check_violation THEN NULL; END $$;
DO $$ DECLARE r record; BEGIN
  UPDATE public.premise_place_memberships SET valid_to = DATE '2026-07-01'
   WHERE service_location_id = '00000000-0000-4000-8000-0000000016d2' AND place_id = pg_temp.id('esd2');
  SELECT closed_at, closed_by INTO r FROM public.premise_place_memberships
   WHERE service_location_id = '00000000-0000-4000-8000-0000000016d2' AND place_id = pg_temp.id('esd2');
  IF r.closed_at IS NULL OR r.closed_by IS DISTINCT FROM '00000000-0000-4000-8000-0000000016b1'::uuid THEN
    RAISE EXCEPTION 'FAIL M8e: the close was not stamped';
  END IF;
  BEGIN
    UPDATE public.premise_place_memberships SET valid_to = DATE '2026-09-01'
     WHERE service_location_id = '00000000-0000-4000-8000-0000000016d2' AND place_id = pg_temp.id('esd2');
    RAISE EXCEPTION 'FAIL M8f: a membership closed twice';
  EXCEPTION WHEN restrict_violation THEN NULL; END;
  RAISE NOTICE 'PASS M8: a membership is never edited or deleted; it closes once, after its start, stamped with who closed it';
END $$;
RESET ROLE;
DO $$ BEGIN
  -- the session's user is T2's: created_by is stamped from it and refused
  PERFORM set_config('app.user_id', '00000000-0000-4000-8000-0000000016b2', true);
  PERFORM pg_temp.mem('00000000-0000-4000-8000-0000000016d4', pg_temp.id('lonely'), 'tax', DATE '2020-01-01');
  RAISE EXCEPTION 'FAIL M9: a membership recorded by another tenant''s user';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'PASS M9: a membership''s recorder is the session''s user, and of the premise''s tenant'; END $$;


-- ============================================================ S. a premise's state
DO $$ BEGIN
  UPDATE public.service_locations SET state = 'OK' WHERE id = '00000000-0000-4000-8000-0000000016d2';
  RAISE EXCEPTION 'FAIL S1a: a premise moved to OK under its Texas memberships';
EXCEPTION WHEN restrict_violation THEN NULL; END $$;
DO $$ BEGIN
  UPDATE public.service_locations SET state = ' tx ' WHERE id = '00000000-0000-4000-8000-0000000016d2';
  UPDATE public.service_locations SET state = 'TX' WHERE id = '00000000-0000-4000-8000-0000000016d2';
  RAISE NOTICE 'PASS S1: a premise''s state cannot change to another under its memberships; a respelling of the same state can';
END $$;
DO $$ BEGIN
  -- L3 (ZZ) has no memberships: its state may change
  UPDATE public.service_locations SET state = 'OK' WHERE id = '00000000-0000-4000-8000-0000000016d3';
  UPDATE public.service_locations SET state = 'ZZ' WHERE id = '00000000-0000-4000-8000-0000000016d3';
  RAISE NOTICE 'PASS S2: a premise with no memberships may change state';
END $$;


-- ============================================================ P. profiles
SET LOCAL app.user_id = '00000000-0000-4000-8000-0000000016b1';
SET ROLE tally_app;
DO $$ BEGIN
  PERFORM pg_temp.prof('gas', 'TX', 'municipal', false, NULL, DATE '2020-01-01');
  RAISE EXCEPTION 'FAIL P1a: a municipal owner without its owning place';
EXCEPTION WHEN check_violation THEN NULL; END $$;
DO $$ BEGIN
  PERFORM pg_temp.prof('gas', 'TX', 'investor_owned', true, pg_temp.id('austin'), DATE '2020-01-01');
  RAISE EXCEPTION 'FAIL P1b: an investor-owned utility with an owning place';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'PASS P1: an owning place exactly when the owner type is a public body (from the vocabulary)'; END $$;
DO $$ BEGIN
  PERFORM pg_temp.prof('gas', 'TX', 'municipal', false, pg_temp.id('cmta'), DATE '2020-01-01');
  RAISE EXCEPTION 'FAIL P2a: a municipal system owned by a transit authority';
EXCEPTION WHEN check_violation THEN NULL; END $$;
DO $$ BEGIN
  PERFORM pg_temp.prof('gas', 'TX', 'municipal', false, pg_temp.id('travis'), DATE '2020-01-01');
  RAISE EXCEPTION 'FAIL P2b: a municipal system owned by a county';
EXCEPTION WHEN check_violation THEN NULL; END $$;
DO $$ BEGIN
  PERFORM pg_temp.prof('gas', 'TX', 'municipal', false, pg_temp.id('short'), DATE '2020-01-01');
  RAISE EXCEPTION 'FAIL P2c: owned by a place that closes first';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'PASS P2: the owning place is of a kind the owner type takes, and in force over the whole profile'; END $$;
SELECT pg_temp.prof('gas', 'TX', 'municipal', false, pg_temp.id('elpaso'), DATE '2020-01-01');
DO $$ DECLARE v uuid; r record; BEGIN
  -- a city system serving across a state line: the ZZ profile is owned by El Paso
  v := pg_temp.prof('gas', 'ZZ', 'municipal', true, pg_temp.id('elpaso'), DATE '2022-01-01');
  SELECT * INTO r FROM public.utility_service_profiles WHERE id = v;
  IF r.created_by IS DISTINCT FROM '00000000-0000-4000-8000-0000000016b1'::uuid OR r.created_at IS DISTINCT FROM now() THEN
    RAISE EXCEPTION 'FAIL P3: the profile''s created_by or created_at not stamped';
  END IF;
  RAISE NOTICE 'PASS P3: a city may own service governed by another state''s law (a border system); the profile''s recorder and time are stamped';
END $$;
DO $$ BEGIN
  PERFORM pg_temp.prof('gas', 'TX', 'investor_owned', true, NULL, DATE '2024-01-01');
  RAISE EXCEPTION 'FAIL P4: two profiles for one service and state at once';
EXCEPTION WHEN exclusion_violation THEN
  RAISE NOTICE 'PASS P4: one profile per utility, service and state at a time'; END $$;
DO $$ BEGIN
  UPDATE public.utility_service_profiles SET commission_jurisdiction = true WHERE state_code = 'TX';
  RAISE EXCEPTION 'FAIL P5a: a profile edited';
EXCEPTION WHEN restrict_violation THEN NULL; END $$;
DO $$ BEGIN
  UPDATE public.utility_service_profiles SET effective_to = DATE '2026-01-01', commission_jurisdiction = true WHERE state_code = 'TX';
  RAISE EXCEPTION 'FAIL P5b: a close that carries an edit';
EXCEPTION WHEN restrict_violation THEN NULL; END $$;
DO $$ BEGIN
  DELETE FROM public.utility_service_profiles WHERE state_code = 'TX';
  RAISE EXCEPTION 'FAIL P5c: the application deleted a profile';
EXCEPTION WHEN insufficient_privilege THEN
  RAISE NOTICE 'PASS P5: a profile is never edited or deleted'; END $$;
-- An election moves the city system under the commission: close and succeed.
DO $$ DECLARE r record; BEGIN
  UPDATE public.utility_service_profiles SET effective_to = DATE '2026-01-01' WHERE state_code = 'TX';
  SELECT closed_at, closed_by INTO r FROM public.utility_service_profiles WHERE state_code = 'TX';
  IF r.closed_at IS NULL OR r.closed_by IS DISTINCT FROM '00000000-0000-4000-8000-0000000016b1'::uuid THEN
    RAISE EXCEPTION 'FAIL P6: the profile close was not stamped';
  END IF;
  PERFORM pg_temp.prof('gas', 'TX', 'municipal', true, pg_temp.id('elpaso'), DATE '2026-01-01');
  SELECT * INTO r FROM public.utility_service_profile_as_of('00000000-0000-4000-8000-0000000016a1', 'gas', 'TX', DATE '2025-12-31');
  IF r.commission_jurisdiction IS DISTINCT FROM false THEN RAISE EXCEPTION 'FAIL P6: the 2025 profile reads %', r.commission_jurisdiction; END IF;
  SELECT * INTO r FROM public.utility_service_profile_as_of('00000000-0000-4000-8000-0000000016a1', 'gas', 'TX', DATE '2026-01-01');
  IF r.commission_jurisdiction IS DISTINCT FROM true OR r.owner_type IS DISTINCT FROM 'municipal' THEN RAISE EXCEPTION 'FAIL P6: the 2026 profile is wrong'; END IF;
  RAISE NOTICE 'PASS P6: an election changes jurisdiction without changing ownership — a stamped close and a successor, each read on its date (the boundary day reads the successor)';
END $$;


-- ============================================================ L. lookups
DO $$ DECLARE r record; BEGIN
  SELECT * INTO r FROM public.utility_service_profile_as_of('00000000-0000-4000-8000-0000000016a1', 'water', 'TX', DATE '2026-06-01');
  RAISE EXCEPTION 'FAIL L1a: a profile invented for water';
EXCEPTION WHEN no_data_found THEN NULL; END $$;
DO $$ DECLARE r record; BEGIN
  SELECT * INTO r FROM public.utility_service_profile_as_of('00000000-0000-4000-8000-0000000016a1', 'gas', 'TX', NULL);
  RAISE EXCEPTION 'FAIL L1b: a profile read on no date';
EXCEPTION WHEN invalid_parameter_value THEN
  RAISE NOTICE 'PASS L1: with no profile recorded, or no date given, the profile lookup refuses'; END $$;
DO $$ DECLARE v text; BEGIN
  v := public.premise_time_zone_as_of('00000000-0000-4000-8000-0000000016d1', DATE '2026-06-01');
  IF v IS DISTINCT FROM 'America/Denver' THEN RAISE EXCEPTION 'FAIL L2a: El Paso reads %', v; END IF;
  v := public.premise_time_zone_as_of('00000000-0000-4000-8000-0000000016d2', DATE '2026-06-01');
  IF v IS DISTINCT FROM 'America/Chicago' THEN RAISE EXCEPTION 'FAIL L2b: Austin reads %', v; END IF;
  RAISE NOTICE 'PASS L2: the time zone is the most specific place''s — Mountain for an El Paso County premise, Central from Travis County';
END $$;
DO $$ DECLARE v text; BEGIN
  v := public.premise_time_zone_as_of('00000000-0000-4000-8000-0000000016d4', DATE '2026-06-01');
  RAISE EXCEPTION 'FAIL L3a: an El Paso premise with no county given %', v;
EXCEPTION WHEN no_data_found THEN NULL; END $$;
DO $$ DECLARE v text; BEGIN
  v := public.premise_time_zone_as_of('00000000-0000-4000-8000-0000000016d3', DATE '2026-06-01');
  RAISE EXCEPTION 'FAIL L3b: a ZZ premise given the time zone %', v;
EXCEPTION WHEN no_data_found THEN
  RAISE NOTICE 'PASS L3: a premise known only by a state not in one zone (Texas), or by a state with no zone, is refused — never assumed Central'; END $$;
DO $$ DECLARE v text; BEGIN
  -- L4 gets El Paso County on the TAX axis only: geography is the same
  PERFORM pg_temp.mem('00000000-0000-4000-8000-0000000016d4', pg_temp.id('elpaso_cty'), 'tax', DATE '2020-01-01');
  v := public.premise_time_zone_as_of('00000000-0000-4000-8000-0000000016d4', DATE '2026-06-01');
  IF v IS DISTINCT FROM 'America/Denver' THEN RAISE EXCEPTION 'FAIL L4: a tax-axis county reads %', v; END IF;
  RAISE NOTICE 'PASS L4: the time zone reads both axes (a county recorded for tax only still places the premise)';
END $$;
RESET ROLE;
DO $$ DECLARE v text; BEGIN
  -- a city fact outranks its county; a ZZ state in one zone answers
  PERFORM pg_temp.fact('austin', 'time_zone', '"America/Indiana/Knox"', DATE '1900-01-01');
  PERFORM pg_temp.fact('zz', 'time_zone', '"America/Phoenix"', DATE '1900-01-01');
  PERFORM pg_temp.fact('zz', 'time_zone_uniform', 'true', DATE '1900-01-01');
  v := public.premise_time_zone_as_of('00000000-0000-4000-8000-0000000016d2', DATE '2026-06-01');
  IF v IS DISTINCT FROM 'America/Indiana/Knox' THEN RAISE EXCEPTION 'FAIL L5a: the city did not outrank its county: %', v; END IF;
  v := public.premise_time_zone_as_of('00000000-0000-4000-8000-0000000016d3', DATE '2026-06-01');
  IF v IS DISTINCT FROM 'America/Phoenix' THEN RAISE EXCEPTION 'FAIL L5b: a uniform state did not answer: %', v; END IF;
  RAISE EXCEPTION 'rollback L5';
EXCEPTION WHEN raise_exception THEN
  IF SQLERRM <> 'rollback L5' THEN RAISE; END IF;
  RAISE NOTICE 'PASS L5: a city''s zone outranks its county''s; a state in one zone answers for itself';
END $$;
SET LOCAL app.user_id = '00000000-0000-4000-8000-0000000016b1';
SET ROLE tally_app;
DO $$ DECLARE n_reg int; n_tax int; v_city text; n_out int; BEGIN
  -- On 2026-02-01 L2 is in Austin for rates (ordinance 2025-12-15) but still
  -- Round Rock's for tax (until the quarter, 2026-04-01).
  SELECT count(*) INTO n_reg FROM public.premise_places_as_of('00000000-0000-4000-8000-0000000016d2', DATE '2026-02-01', 'regulatory') WHERE place_id = pg_temp.id('austin');
  SELECT place_code INTO v_city FROM public.premise_places_as_of('00000000-0000-4000-8000-0000000016d2', DATE '2026-02-01', 'tax') WHERE kind_code = 'municipality';
  SELECT count(*) INTO n_tax FROM public.premise_places_as_of('00000000-0000-4000-8000-0000000016d2', DATE '2026-05-01', 'tax') WHERE kind_code IN ('municipality', 'special_purpose_district', 'state');
  SELECT count(*) INTO n_out FROM public.premise_places_as_of('00000000-0000-4000-8000-0000000016d1', DATE '2026-05-01', 'regulatory') WHERE relation = 'outside' AND distance_miles = 3.5;
  IF n_reg IS DISTINCT FROM 1::bigint OR v_city IS DISTINCT FROM 'ROUNDROCK' OR n_tax IS DISTINCT FROM 4::bigint OR n_out IS DISTINCT FROM 1::bigint THEN
    RAISE EXCEPTION 'FAIL L6: places as of: reg % city % tax-count % outside %', n_reg, v_city, n_tax, n_out;
  END IF;
  -- the day a membership ends it is no longer in force (Round Rock tax ends 2026-04-01)
  IF EXISTS (SELECT 1 FROM public.premise_places_as_of('00000000-0000-4000-8000-0000000016d2', DATE '2026-04-01', 'tax') WHERE place_id = pg_temp.id('roundrock')) THEN
    RAISE EXCEPTION 'FAIL L6: a membership read on the day it ended';
  END IF;
  RAISE NOTICE 'PASS L6: a premise''s places are read per axis on a date — Austin for rates from the ordinance, Round Rock for tax until (not on) the quarter, then Austin, two districts and the state; an outside relation is returned with its distance';
END $$;
DO $$ BEGIN
  PERFORM * FROM public.premise_places_as_of('00000000-0000-4000-8000-0000000016d2', DATE '2026-06-01', 'typo');
  RAISE EXCEPTION 'FAIL L7a: an unknown axis answered';
EXCEPTION WHEN invalid_parameter_value THEN NULL; END $$;
DO $$ BEGIN
  PERFORM * FROM public.premise_places_as_of('00000000-0000-4000-8000-0000000016d2', NULL, 'tax');
  RAISE EXCEPTION 'FAIL L7b: no date answered';
EXCEPTION WHEN invalid_parameter_value THEN NULL; END $$;
DO $$ BEGIN
  PERFORM * FROM public.premise_places_as_of('00000000-0000-4000-8000-0000000016d6', DATE '2026-06-01', 'tax');
  RAISE EXCEPTION 'FAIL L7c: a premise in "Texas" answered';
EXCEPTION WHEN no_data_found THEN NULL; END $$;
DO $$ DECLARE v text; BEGIN
  -- ' tx ' is Texas, read as -12 reads it
  PERFORM pg_temp.mem('00000000-0000-4000-8000-0000000016d5', pg_temp.id('travis'), 'regulatory', DATE '2020-01-01');
  v := public.premise_time_zone_as_of('00000000-0000-4000-8000-0000000016d5', DATE '2026-06-01');
  IF v IS DISTINCT FROM 'America/Chicago' THEN RAISE EXCEPTION 'FAIL L7d: a padded " tx " premise reads %', v; END IF;
  RAISE NOTICE 'PASS L7: the place lookup refuses an unknown or missing axis, a missing date, and a state no state answers (" tx " is Texas, "Texas" is nothing)';
END $$;
RESET ROLE;
SET LOCAL app.user_id = '00000000-0000-4000-8000-0000000016b2';
SET ROLE tally_app;
DO $$ BEGIN
  PERFORM * FROM public.premise_places_as_of('00000000-0000-4000-8000-0000000016d2', DATE '2026-06-01', 'tax');
  RAISE EXCEPTION 'FAIL L8a: T2 read T1''s premise''s places';
EXCEPTION WHEN no_data_found THEN NULL; END $$;
DO $$ DECLARE r record; BEGIN
  SELECT * INTO r FROM public.utility_service_profile_as_of('00000000-0000-4000-8000-0000000016a1', 'gas', 'TX', DATE '2026-06-01');
  RAISE EXCEPTION 'FAIL L8b: T2 read T1''s profile';
EXCEPTION WHEN no_data_found THEN
  RAISE NOTICE 'PASS L8: another utility''s premises and profiles are not found through the lookups'; END $$;
RESET ROLE;


-- ============================================================ C. a place's close floor
-- Owner (a superuser). Each close below is refused by exactly one citation
-- in force past it.
-- C-city: cited only by one open membership (no fact, child, profile or
-- jurisdiction), so only the membership leg can refuse.
DO $$ BEGIN
  PERFORM pg_temp.place('ccity', 'municipality', 'TX', 'CCITY', 'tx', DATE '1950-01-01');
  PERFORM set_config('app.user_id', '00000000-0000-4000-8000-0000000016b1', true);
  PERFORM pg_temp.mem('00000000-0000-4000-8000-0000000016d5', pg_temp.id('ccity'), 'regulatory', DATE '2020-01-01');
END $$;
DO $$ BEGIN
  UPDATE public.places SET effective_to = DATE '2027-01-01' WHERE id = pg_temp.id('ccity');
  RAISE EXCEPTION 'FAIL C1: a city closed under a membership still open';
EXCEPTION WHEN restrict_violation THEN
  RAISE NOTICE 'PASS C1: a place does not close while a premise''s membership in it runs past the close'; END $$;
DO $$ BEGIN
  -- ZZ city: only a profile cites it.
  PERFORM set_config('app.user_id', '00000000-0000-4000-8000-0000000016b1', true);
  INSERT INTO public.utility_service_profiles (tenant_id, service_type, system_kind, state_code, owner_type, commission_jurisdiction,
                                               owning_place_id, effective_from, evidence_reference, evidence_date)
  VALUES ('00000000-0000-4000-8000-0000000016a1', 'water', 'distribution', 'ZZ', 'municipal', false, pg_temp.id('zcity'), DATE '2020-01-01', 'ZZ charter', DATE '2020-01-01');
  UPDATE public.places SET effective_to = DATE '2027-01-01' WHERE id = pg_temp.id('zcity');
  RAISE EXCEPTION 'FAIL C2: a city closed under the profile it owns';
EXCEPTION WHEN restrict_violation THEN
  RAISE NOTICE 'PASS C2: a place does not close while a utility it owns has a profile running past the close'; END $$;
DO $$ BEGIN
  -- ESD2: its membership closed 2026-07-01; a fact keeps it open.
  PERFORM pg_temp.fact('esd2', 'special_district_type', '"emergency_services"', DATE '2000-01-01');
  UPDATE public.places SET effective_to = DATE '2029-06-01' WHERE id = pg_temp.id('esd2');
  RAISE EXCEPTION 'FAIL C3: a district closed under its own fact';
EXCEPTION WHEN restrict_violation THEN
  RAISE NOTICE 'PASS C3: a place does not close while a fact about it runs past the close'; END $$;
DO $$ BEGIN
  -- Round Rock: its only membership ended 2026-04-01; a child keeps it open.
  PERFORM pg_temp.place('rrdist', 'special_purpose_district', 'TX', 'RRDIST', 'roundrock', DATE '2010-01-01');
  UPDATE public.places SET effective_to = DATE '2027-01-01' WHERE id = pg_temp.id('roundrock');
  RAISE EXCEPTION 'FAIL C4: a city closed under its open child district';
EXCEPTION WHEN restrict_violation THEN
  RAISE NOTICE 'PASS C4: a place does not close while a child place runs past the close'; END $$;
DO $$ DECLARE r record; BEGIN
  -- Round Rock closes exactly when its last membership ended: allowed.
  UPDATE public.places SET effective_to = DATE '2026-04-01' WHERE id = pg_temp.id('roundrock');
  SELECT closed_at, closed_by INTO r FROM public.places WHERE id = pg_temp.id('roundrock');
  IF r.closed_at IS NULL OR r.closed_by IS NULL THEN RAISE EXCEPTION 'FAIL C5: the close was not stamped'; END IF;
  BEGIN
    UPDATE public.places SET effective_to = DATE '2028-01-01' WHERE id = pg_temp.id('roundrock');
    RAISE EXCEPTION 'FAIL C5: closed twice';
  EXCEPTION WHEN restrict_violation THEN NULL; END;
  RAISE EXCEPTION 'rollback C5';
EXCEPTION WHEN raise_exception THEN
  IF SQLERRM <> 'rollback C5' THEN RAISE; END IF;
  RAISE NOTICE 'PASS C5: with nothing in force past it (a membership ending on the close day is not), a place closes once, stamped';
END $$;
DO $$ DECLARE v_place uuid := pg_temp.id('ccity'); BEGIN
  -- a role row-level security narrows (review r1 B4)
  CREATE ROLE b16_closer NOBYPASSRLS;
  GRANT USAGE ON SCHEMA public TO b16_closer;
  GRANT SELECT, UPDATE ON public.places TO b16_closer;
  GRANT SELECT ON public.premise_place_memberships, public.utility_service_profiles, public.place_facts, public.jurisdictions TO b16_closer;
  GRANT EXECUTE ON FUNCTION public.place_lock_key(uuid), public.assert_place_read_committed(text),
                            public.get_user_tenant_id(), public.is_platform_admin() TO b16_closer;
  -- the session is T2's: row-level security hides T1's membership from the role
  PERFORM set_config('app.user_id', '00000000-0000-4000-8000-0000000016b2', true);
  SET LOCAL ROLE b16_closer;
  UPDATE public.places SET effective_to = DATE '2027-01-01' WHERE id = v_place;
  RAISE EXCEPTION 'FAIL C6: a role that sees no tenant''s memberships closed a cited place';
EXCEPTION WHEN insufficient_privilege THEN
  IF SQLERRM !~ 'needs a role that sees every tenant' THEN
    RAISE EXCEPTION 'FAIL C6: refused for another reason: %', SQLERRM;
  END IF;
  RAISE NOTICE 'PASS C6: only a role that sees every tenant''s citations may close a place'; END $$;
RESET ROLE;


-- ============================================================ J. jurisdictions
SET LOCAL app.user_id = '00000000-0000-4000-8000-0000000016b1';
SET ROLE tally_app;
DO $$ BEGIN
  INSERT INTO public.jurisdictions (tenant_id, jurisdiction_code, jurisdiction_name, place_id)
  VALUES ('00000000-0000-4000-8000-0000000016a1', 'ELP', 'El Paso', pg_temp.id('elpaso'));
  INSERT INTO public.jurisdictions (tenant_id, jurisdiction_code, jurisdiction_name)
  VALUES ('00000000-0000-4000-8000-0000000016a1', 'FR-EAST', 'East franchise area');
  BEGIN
    INSERT INTO public.jurisdictions (tenant_id, jurisdiction_code, jurisdiction_name, place_id)
    VALUES ('00000000-0000-4000-8000-0000000016a1', 'TXX', 'Texas', pg_temp.id('tx'));
    RAISE EXCEPTION 'FAIL J1a: a utility jurisdiction that is a state';
  EXCEPTION WHEN check_violation THEN NULL; END;
  BEGIN
    UPDATE public.jurisdictions SET place_id = pg_temp.id('short') WHERE jurisdiction_code = 'FR-EAST';
    RAISE EXCEPTION 'FAIL J1b: pointed at a place no longer in force';
  EXCEPTION WHEN check_violation THEN NULL; END;
  RAISE NOTICE 'PASS J1: a utility''s jurisdiction points at a place below the state in force, or at none';
END $$;
RESET ROLE;
DO $$ BEGIN
  -- Lonely: close its outside membership, so a jurisdiction pointing at it is
  -- the only citation left.
  UPDATE public.premise_place_memberships SET valid_to = DATE '2024-01-01' WHERE place_id = pg_temp.id('lonely');
  PERFORM set_config('app.user_id', '00000000-0000-4000-8000-0000000016b1', true);
  INSERT INTO public.jurisdictions (tenant_id, jurisdiction_code, jurisdiction_name, place_id)
  VALUES ('00000000-0000-4000-8000-0000000016a1', 'LON', 'Lonely', pg_temp.id('lonely'));
  UPDATE public.places SET effective_to = DATE '2090-01-01' WHERE id = pg_temp.id('lonely');
  RAISE EXCEPTION 'FAIL J2: a place closed under the jurisdiction pointing at it';
EXCEPTION WHEN restrict_violation THEN
  RAISE NOTICE 'PASS J2: a place does not close while a utility jurisdiction points at it'; END $$;

-- ============================================================ N. review round 2
-- Platform fixtures for N (owner).
INSERT INTO public.service_locations (id, tenant_id, customer_id, location_number, address_line1, city, state, zip) VALUES
  ('00000000-0000-4000-8000-0000000016d7', '00000000-0000-4000-8000-0000000016a1', '00000000-0000-4000-8000-0000000016c1', 'L7', '7 Main', 'Austin', 'TX', '78707'),
  ('00000000-0000-4000-8000-0000000016d8', '00000000-0000-4000-8000-0000000016a1', '00000000-0000-4000-8000-0000000016c1', 'L8', '8 Main', 'Austin', 'TX', '78708'),
  ('00000000-0000-4000-8000-0000000016dc', '00000000-0000-4000-8000-0000000016a1', '00000000-0000-4000-8000-0000000016c1', 'L12', '12 Main', 'Austin', 'TX', '78712');
DO $$ BEGIN
  INSERT INTO b16 SELECT 'uninc', id FROM public.places WHERE kind_code = 'unincorporated_area' AND state_code = 'TX';
  PERFORM pg_temp.place('austin_lpa', 'limited_purpose_area', 'TX', 'AUSTIN-LPA', 'austin', DATE '1990-01-01');
  PERFORM pg_temp.place('outsider', 'municipality', 'TX', 'OUTSIDER', 'tx', DATE '1950-01-01');
  PERFORM pg_temp.fact('outsider', 'time_zone', '"America/Chicago"', DATE '1950-01-01');
  PERFORM pg_temp.place('futurezone', 'municipality', 'TX', 'FUTUREZONE', 'tx', DATE '1950-01-01');
  INSERT INTO public.place_facts (place_id, fact_code, value, effective_from, source_note)
  VALUES (pg_temp.id('futurezone'), 'time_zone', '"America/Denver"', DATE '2030-01-01', 'a zone not yet in force');
  PERFORM pg_temp.place('scheduled', 'municipality', 'TX', 'SCHEDULED', 'tx', DATE '1950-01-01', DATE '2099-01-01');
END $$;
SET LOCAL app.user_id = '00000000-0000-4000-8000-0000000016b1';
SET ROLE tally_app;
DO $$ DECLARE v text; BEGIN
  -- N1 (r2): L1 is in El Paso County (Mountain) for rates; recorded in
  -- Travis County (Central) for tax, the two most specific candidates disagree.
  PERFORM pg_temp.mem('00000000-0000-4000-8000-0000000016d1', pg_temp.id('travis'), 'tax', DATE '2020-01-01');
  v := public.premise_time_zone_as_of('00000000-0000-4000-8000-0000000016d1', DATE '2026-06-01');
  RAISE EXCEPTION 'FAIL N1: two counties with two zones answered %', v;
EXCEPTION WHEN cardinality_violation THEN
  RAISE NOTICE 'PASS N1: when the most specific places a premise is within disagree on its time zone, the lookup refuses rather than choose'; END $$;
DO $$ DECLARE v text; BEGIN
  -- agreeing duplicates are fine: L2 is in Travis County on both axes
  PERFORM pg_temp.mem('00000000-0000-4000-8000-0000000016d2', pg_temp.id('travis'), 'tax', DATE '2020-01-01');
  -- L12: within FutureZone (Denver from 2030 only) and Travis (Central)
  PERFORM pg_temp.mem('00000000-0000-4000-8000-0000000016dc', pg_temp.id('travis'), 'regulatory', DATE '2020-01-01');
  PERFORM pg_temp.mem('00000000-0000-4000-8000-0000000016dc', pg_temp.id('futurezone'), 'regulatory', DATE '2020-01-01');
  v := public.premise_time_zone_as_of('00000000-0000-4000-8000-0000000016dc', DATE '2026-06-01');
  IF v IS DISTINCT FROM 'America/Chicago' THEN RAISE EXCEPTION 'FAIL N2a: a zone not yet in force answered %', v; END IF;
  -- L8: in Travis; known OUTSIDE Outsider (Chicago) — the outside row is no answer
  PERFORM pg_temp.mem('00000000-0000-4000-8000-0000000016d8', pg_temp.id('elpaso_cty'), 'regulatory', DATE '2020-01-01');
  PERFORM pg_temp.mem('00000000-0000-4000-8000-0000000016d8', pg_temp.id('outsider'), 'regulatory', DATE '2020-01-01', NULL, 'outside', 12);
  v := public.premise_time_zone_as_of('00000000-0000-4000-8000-0000000016d8', DATE '2026-06-01');
  IF v IS DISTINCT FROM 'America/Denver' THEN RAISE EXCEPTION 'FAIL N2b: an outside place answered %', v; END IF;
  RAISE NOTICE 'PASS N2: agreeing candidates answer; a zone not yet in force and a place the premise is only known to be outside give no answer';
END $$;
DO $$ BEGIN
  PERFORM pg_temp.mem('00000000-0000-4000-8000-0000000016d2', pg_temp.id('elpaso_cty'), 'regulatory', DATE '2026-01-01');
  RAISE EXCEPTION 'FAIL N3a: a second county on one axis';
EXCEPTION WHEN exclusion_violation THEN NULL; END $$;
DO $$ BEGIN
  PERFORM pg_temp.mem('00000000-0000-4000-8000-0000000016d2', pg_temp.id('austin_lpa'), 'regulatory', DATE '2026-01-01');
  RAISE EXCEPTION 'FAIL N3b: a city and its limited-purpose area at once';
EXCEPTION WHEN exclusion_violation THEN NULL; END $$;
DO $$ BEGIN
  PERFORM pg_temp.mem('00000000-0000-4000-8000-0000000016d2', pg_temp.id('uninc'), 'regulatory', DATE '2026-01-01');
  RAISE EXCEPTION 'FAIL N3c: a city and unincorporated territory at once';
EXCEPTION WHEN exclusion_violation THEN
  RAISE NOTICE 'PASS N3: one county per axis; a premise is in one of a city, a limited-purpose area, an extraterritorial area or unincorporated territory (review r2 S-c)'; END $$;
SELECT pg_temp.mem('00000000-0000-4000-8000-0000000016d7', pg_temp.id('uninc'), 'regulatory', DATE '2020-01-01');
-- Void (r2 S-b): L7 was recorded unincorporated from its first day, wrongly:
-- it is in Austin. A close keeps a day; a void removes the row from every reader.
DO $$ DECLARE r record; v_id uuid; BEGIN
  SELECT id INTO v_id FROM public.premise_place_memberships WHERE service_location_id = '00000000-0000-4000-8000-0000000016d7';
  BEGIN
    UPDATE public.premise_place_memberships SET void_reason = 'wrong from the start', axis = 'tax' WHERE id = v_id;
    RAISE EXCEPTION 'FAIL N4a: a void that changes something else';
  EXCEPTION WHEN restrict_violation THEN NULL; END;
  BEGIN
    UPDATE public.premise_place_memberships SET void_reason = '   ' WHERE id = v_id;
    RAISE EXCEPTION 'FAIL N4b: a void without a reason';
  EXCEPTION WHEN restrict_violation THEN NULL; END;
  UPDATE public.premise_place_memberships SET void_reason = 'Address verified inside Austin city limits' WHERE id = v_id;
  SELECT voided_at, voided_by INTO r FROM public.premise_place_memberships WHERE id = v_id;
  IF r.voided_at IS NULL OR r.voided_by IS DISTINCT FROM '00000000-0000-4000-8000-0000000016b1'::uuid THEN RAISE EXCEPTION 'FAIL N4c: the void was not stamped'; END IF;
  PERFORM pg_temp.mem('00000000-0000-4000-8000-0000000016d7', pg_temp.id('austin'), 'regulatory', DATE '2020-01-01');
  IF (SELECT kind_code FROM public.premise_places_as_of('00000000-0000-4000-8000-0000000016d7', DATE '2020-01-01', 'regulatory') WHERE kind_code <> 'state')
     IS DISTINCT FROM 'municipality' THEN
    RAISE EXCEPTION 'FAIL N4d: the voided row still answers';
  END IF;
  BEGIN
    -- a second void would restamp it with a new reason: only the frozen rule refuses
    UPDATE public.premise_place_memberships SET void_reason = 'a different story' WHERE id = v_id;
    RAISE EXCEPTION 'FAIL N4e: a voided row voided again';
  EXCEPTION WHEN restrict_violation THEN NULL; END;
  RAISE NOTICE 'PASS N4: a membership wrong from its first day is voided with a reason (stamped, nothing else changed, never edited after); the correct row takes its place for the same days';
END $$;
DO $$ DECLARE v_id uuid; r record; BEGIN
  -- a profile wrong from its first day: the ZZ profile is voided and recorded again
  SELECT id INTO v_id FROM public.utility_service_profiles WHERE state_code = 'ZZ' AND service_type = 'gas';
  UPDATE public.utility_service_profiles SET void_reason = 'ZZ service is the cooperative''s, not ours' WHERE id = v_id;
  SELECT voided_at, voided_by INTO r FROM public.utility_service_profiles WHERE id = v_id;
  IF r.voided_at IS NULL OR r.voided_by IS DISTINCT FROM '00000000-0000-4000-8000-0000000016b1'::uuid THEN RAISE EXCEPTION 'FAIL N5a: the profile void was not stamped'; END IF;
  BEGIN
    SELECT * INTO r FROM public.utility_service_profile_as_of('00000000-0000-4000-8000-0000000016a1', 'gas', 'ZZ', DATE '2023-01-01');
    RAISE EXCEPTION 'FAIL N5b: a voided profile still answers';
  EXCEPTION WHEN no_data_found THEN NULL; END;
  PERFORM pg_temp.prof('gas', 'ZZ', 'investor_owned', true, NULL, DATE '2022-01-01');
  RAISE NOTICE 'PASS N5: a profile wrong from its first day is voided (stamped), no longer answers, and its successor takes the same days';
END $$;
DO $$ BEGIN
  PERFORM pg_temp.prof('gas', 'QQ', 'investor_owned', true, NULL, DATE '2020-01-01');
  RAISE EXCEPTION 'FAIL N6a: a profile for a state that does not exist';
EXCEPTION WHEN check_violation THEN NULL; END $$;
DO $$ BEGIN
  INSERT INTO public.utility_service_profiles (tenant_id, service_type, system_kind, state_code, owner_type, commission_jurisdiction, effective_from, evidence_reference, evidence_date)
  VALUES ('00000000-0000-4000-8000-0000000016a1', 'sewer', 'distribution', 'TX', 'investor_owned', true, DATE '2020-01-01', 'x', CURRENT_DATE + 30);
  RAISE EXCEPTION 'FAIL N6b: a profile on evidence dated in the future';
EXCEPTION WHEN check_violation THEN NULL; END $$;
DO $$ BEGIN
  INSERT INTO public.premise_place_memberships (tenant_id, service_location_id, place_id, axis, place_kind, valid_from, evidence_kind, evidence_reference, evidence_date)
  VALUES ('00000000-0000-4000-8000-0000000016a1', '00000000-0000-4000-8000-0000000016d8', pg_temp.id('cmta'), 'tax', 'x', DATE '2020-01-01', 'ordinance', 'x', CURRENT_DATE + 30);
  RAISE EXCEPTION 'FAIL N6c: a membership on evidence dated in the future';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'PASS N6: a profile is for a state that exists over its range; evidence is never dated after it is recorded'; END $$;
DO $$ DECLARE r record; BEGIN
  -- the caller cannot pre-stamp a close or a void
  INSERT INTO public.premise_place_memberships (tenant_id, service_location_id, place_id, axis, place_kind, valid_from, evidence_kind, evidence_reference, evidence_date,
                                                closed_at, closed_by, void_reason, voided_at)
  VALUES ('00000000-0000-4000-8000-0000000016a1', '00000000-0000-4000-8000-0000000016d8', pg_temp.id('cmta'), 'tax', 'x', DATE '2020-01-01', 'ordinance', 'x', DATE '2020-01-01',
          now(), '00000000-0000-4000-8000-0000000016b1', 'pre', now())
  RETURNING closed_at, closed_by, void_reason, voided_at INTO r;
  IF r.closed_at IS NOT NULL OR r.closed_by IS NOT NULL OR r.void_reason IS NOT NULL OR r.voided_at IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL N7a: a membership born closed or voided';
  END IF;
  INSERT INTO public.utility_service_profiles (tenant_id, service_type, system_kind, state_code, owner_type, commission_jurisdiction, effective_from, evidence_reference, evidence_date,
                                               closed_at, closed_by, void_reason, voided_at)
  VALUES ('00000000-0000-4000-8000-0000000016a1', 'trash', 'distribution', 'TX', 'investor_owned', true, DATE '2020-01-01', 'x', DATE '2020-01-01',
          now(), '00000000-0000-4000-8000-0000000016b1', 'pre', now())
  RETURNING closed_at, closed_by, void_reason, voided_at INTO r;
  IF r.closed_at IS NOT NULL OR r.closed_by IS NOT NULL OR r.void_reason IS NOT NULL OR r.voided_at IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL N7b: a profile born closed or voided';
  END IF;
  RAISE NOTICE 'PASS N7: memberships and profiles are born unclosed and unvoided, whatever the caller sends';
END $$;
DO $$ BEGIN
  PERFORM * FROM public.premise_places_as_of('00000000-0000-4000-8000-0000000016d2', DATE '2026-06-01', NULL);
  RAISE EXCEPTION 'FAIL N8a: a NULL axis answered';
EXCEPTION WHEN invalid_parameter_value THEN NULL; END $$;
DO $$ DECLARE r record; BEGIN
  SELECT * INTO r FROM public.utility_service_profile_as_of(NULL, 'gas', 'TX', DATE '2026-06-01');
  RAISE EXCEPTION 'FAIL N8b: a NULL tenant answered';
EXCEPTION WHEN invalid_parameter_value THEN NULL; END $$;
DO $$ DECLARE r record; BEGIN
  SELECT * INTO r FROM public.utility_service_profile_as_of('00000000-0000-4000-8000-0000000016a1', NULL, 'TX', DATE '2026-06-01');
  RAISE EXCEPTION 'FAIL N8c: a NULL service answered';
EXCEPTION WHEN invalid_parameter_value THEN NULL; END $$;
DO $$ DECLARE r record; BEGIN
  SELECT * INTO r FROM public.utility_service_profile_as_of('00000000-0000-4000-8000-0000000016a1', 'gas', NULL, DATE '2026-06-01');
  RAISE EXCEPTION 'FAIL N8d: a NULL state answered';
EXCEPTION WHEN invalid_parameter_value THEN
  RAISE NOTICE 'PASS N8: the lookups refuse a NULL axis, tenant, service or state'; END $$;
DO $$ BEGIN
  UPDATE public.jurisdictions SET place_id = pg_temp.id('scheduled') WHERE jurisdiction_code = 'FR-EAST';
  RAISE EXCEPTION 'FAIL N9: a jurisdiction pointed at a place already scheduled to close';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'PASS N9: an undated jurisdiction points only at an open place (none scheduled to close)'; END $$;
DO $$ BEGIN
  INSERT INTO public.place_membership_evidence_kinds (evidence_kind, description) VALUES ('x', 'x');
  RAISE EXCEPTION 'FAIL N10: the application wrote an evidence kind';
EXCEPTION WHEN insufficient_privilege THEN
  RAISE NOTICE 'PASS N10: the application cannot write the evidence vocabulary'; END $$;
RESET ROLE;
DO $$ BEGIN
  UPDATE public.place_fact_kinds SET keyed = true WHERE fact_code = 'census_population';
  RAISE EXCEPTION 'FAIL N11a: a fact kind edited';
EXCEPTION WHEN restrict_violation THEN NULL; END $$;
DO $$ BEGIN
  DELETE FROM public.place_membership_evidence_kinds WHERE evidence_kind = 'census';
  RAISE EXCEPTION 'FAIL N11b: an evidence kind deleted';
EXCEPTION WHEN restrict_violation THEN
  RAISE NOTICE 'PASS N11: fact kinds and evidence kinds are never edited or deleted'; END $$;
DO $$ BEGIN
  PERFORM pg_temp.fact('austin', 'sales_tax_rate', '5', DATE '2020-01-01');
  RAISE EXCEPTION 'FAIL N12a: a sales tax of 500%%';
EXCEPTION WHEN check_violation THEN NULL; END $$;
DO $$ BEGIN
  PERFORM pg_temp.fact('austin', 'sales_tax_rate', '-0.01', DATE '2020-01-01');
  RAISE EXCEPTION 'FAIL N12b: a negative sales tax';
EXCEPTION WHEN check_violation THEN NULL; END $$;
DO $$ BEGIN
  PERFORM pg_temp.fact('austin', 'census_population', '-3', DATE '2020-01-01');
  RAISE EXCEPTION 'FAIL N12c: a negative population';
EXCEPTION WHEN check_violation THEN NULL; END $$;
DO $$ BEGIN
  PERFORM pg_temp.fact('austin', 'sales_tax_rate', '0.02', DATE '2020-01-01');
  PERFORM pg_temp.fact('austin', 'census_population', '0', DATE '2020-01-01');
  RAISE NOTICE 'PASS N12: a number fact lies in its kind''s range (a rate in [0, 1), a population of at least 0)';
END $$;
DO $$ BEGIN
  PERFORM pg_temp.fact('austin', 'time_zone', '"Etc/GMT+6"', DATE '1990-01-01');
  RAISE EXCEPTION 'FAIL N13a: a fixed Etc/ offset as a zone';
EXCEPTION WHEN check_violation THEN NULL; END $$;
DO $$ BEGIN
  PERFORM pg_temp.fact('austin', 'local_adoption', '"Ord. 2023-1"', DATE '2023-01-01', 'HB 1234 ');
  RAISE EXCEPTION 'FAIL N13b: a key with a trailing blank';
EXCEPTION WHEN check_violation THEN NULL; END $$;
DO $$ DECLARE v timestamptz; BEGIN
  INSERT INTO public.place_facts (place_id, fact_code, value, effective_from, source_note, created_at)
  VALUES (pg_temp.id('outsider'), 'census_population', '100', DATE '1990-01-01', 'x', TIMESTAMPTZ '2001-01-01') RETURNING created_at INTO v;
  IF v IS DISTINCT FROM now() THEN RAISE EXCEPTION 'FAIL N13c: a fact kept the caller''s created_at'; END IF;
  RAISE NOTICE 'PASS N13: a zone is never a fixed Etc/ offset; a key carries no surrounding blanks; a fact''s created_at is the database''s';
END $$;
DO $$ DECLARE v text; BEGIN
  -- a state's uniform fact must be in force: ZZ was uniform until 2000 only
  PERFORM pg_temp.fact('zz', 'time_zone', '"America/Phoenix"', DATE '1900-01-01');
  INSERT INTO public.place_facts (place_id, fact_code, value, effective_from, effective_to, source_note)
  VALUES (pg_temp.id('zz'), 'time_zone_uniform', 'true', DATE '1900-01-01', DATE '2000-01-01', 'uniform until 2000');
  v := public.premise_time_zone_as_of('00000000-0000-4000-8000-0000000016d3', DATE '1999-06-01');
  IF v IS DISTINCT FROM 'America/Phoenix' THEN RAISE EXCEPTION 'FAIL N14a: the uniform state did not answer in 1999: %', v; END IF;
  BEGIN
    v := public.premise_time_zone_as_of('00000000-0000-4000-8000-0000000016d3', DATE '2026-06-01');
    RAISE EXCEPTION 'FAIL N14b: a uniform fact no longer in force answered %', v;
  EXCEPTION WHEN no_data_found THEN NULL; END;
  RAISE EXCEPTION 'rollback N14';
EXCEPTION WHEN raise_exception THEN
  IF SQLERRM <> 'rollback N14' THEN RAISE; END IF;
  RAISE NOTICE 'PASS N14: a state answers for its premises only while its uniform fact is in force';
END $$;
DO $$ BEGIN
  -- a premise with only a CLOSED Texas membership still cannot leave Texas
  PERFORM set_config('app.user_id', '00000000-0000-4000-8000-0000000016b1', true);
  INSERT INTO public.service_locations (id, tenant_id, customer_id, location_number, address_line1, city, state, zip) VALUES
    ('00000000-0000-4000-8000-0000000016da', '00000000-0000-4000-8000-0000000016a1', '00000000-0000-4000-8000-0000000016c1', 'L10', '10 Main', 'Austin', 'TX', '78710');
  PERFORM pg_temp.mem('00000000-0000-4000-8000-0000000016da', pg_temp.id('outsider'), 'regulatory', DATE '2020-01-01', DATE '2021-01-01');
  UPDATE public.service_locations SET state = 'OK' WHERE id = '00000000-0000-4000-8000-0000000016da';
  RAISE EXCEPTION 'FAIL N15: a premise moved state under a closed membership';
EXCEPTION WHEN restrict_violation THEN
  RAISE NOTICE 'PASS N15: a premise''s state does not change under its memberships, closed ones included (history is not relabelled)'; END $$;
DO $$ BEGIN
  -- Close boundaries: a profile, a fact and a child ending on the close day do not hold it open.
  PERFORM pg_temp.place('edge', 'municipality', 'TX', 'EDGE', 'tx', DATE '1950-01-01');
  PERFORM pg_temp.place('edgekid', 'special_purpose_district', 'TX', 'EDGEKID', 'edge', DATE '1960-01-01', DATE '2030-01-01');
  INSERT INTO public.place_facts (place_id, fact_code, value, effective_from, effective_to, source_note)
  VALUES (pg_temp.id('edge'), 'census_population', '10', DATE '1960-01-01', DATE '2030-01-01', 'x');
  PERFORM set_config('app.user_id', '00000000-0000-4000-8000-0000000016b1', true);
  INSERT INTO public.utility_service_profiles (tenant_id, service_type, system_kind, state_code, owner_type, commission_jurisdiction, owning_place_id,
                                               effective_from, effective_to, evidence_reference, evidence_date)
  VALUES ('00000000-0000-4000-8000-0000000016a1', 'stormwater', 'distribution', 'TX', 'municipal', false, pg_temp.id('edge'), DATE '2020-01-01', DATE '2030-01-01', 'x', DATE '2020-01-01');
  UPDATE public.places SET effective_to = DATE '2030-01-01' WHERE id = pg_temp.id('edge');
  RAISE NOTICE 'PASS N16: a profile, a fact or a child place ending on the close day does not hold a place open';
END $$;
DO $$ BEGIN
  -- a voided membership does not hold a place open: L7's voided
  -- unincorporated row is the only membership of... (use a fresh place)
  PERFORM pg_temp.place('voidtown', 'municipality', 'TX', 'VOIDTOWN', 'tx', DATE '1950-01-01');
  PERFORM set_config('app.user_id', '00000000-0000-4000-8000-0000000016b1', true);
  INSERT INTO public.service_locations (id, tenant_id, customer_id, location_number, address_line1, city, state, zip) VALUES
    ('00000000-0000-4000-8000-0000000016db', '00000000-0000-4000-8000-0000000016a1', '00000000-0000-4000-8000-0000000016c1', 'L11', '11 Main', 'Austin', 'TX', '78711');
  PERFORM pg_temp.mem('00000000-0000-4000-8000-0000000016db', pg_temp.id('voidtown'), 'regulatory', DATE '2020-01-01');
  UPDATE public.premise_place_memberships SET void_reason = 'wrong town' WHERE place_id = pg_temp.id('voidtown');
  UPDATE public.places SET effective_to = DATE '2025-01-01' WHERE id = pg_temp.id('voidtown');
  RAISE NOTICE 'PASS N17: a voided membership does not hold its place open';
END $$;
DO $$ BEGIN
  -- L11's only membership (Voidtown) was voided: it no longer holds the premise's state
  UPDATE public.service_locations SET state = 'OK' WHERE id = '00000000-0000-4000-8000-0000000016db';
  RAISE NOTICE 'PASS N18: a voided membership does not hold a premise''s state';
END $$;

-- ============================================================ T. review round 3
-- Platform fixtures for T (owner). YY and XW are fictional states with no
-- facts and no children, so only the guard a case names can refuse it.
RESET ROLE;
INSERT INTO public.service_locations (id, tenant_id, customer_id, location_number, address_line1, city, state, zip) VALUES
  ('00000000-0000-4000-8000-0000000016dd', '00000000-0000-4000-8000-0000000016a1', '00000000-0000-4000-8000-0000000016c1', 'L13', '13 Main', 'El Paso', 'TX', '79913'),
  ('00000000-0000-4000-8000-0000000016de', '00000000-0000-4000-8000-0000000016a1', '00000000-0000-4000-8000-0000000016c1', 'L14', '14 Main', 'Austin', 'TX', '78714'),
  ('00000000-0000-4000-8000-0000000016df', '00000000-0000-4000-8000-0000000016a1', '00000000-0000-4000-8000-0000000016c1', 'L15', '15 Main', 'Annex', 'TX', '78715'),
  ('00000000-0000-4000-8000-0000000016e0', '00000000-0000-4000-8000-0000000016a1', '00000000-0000-4000-8000-0000000016c1', 'L16', '16 Main', 'Austin', 'TX', '78716');
DO $$ BEGIN
  PERFORM pg_temp.place('yy', 'state', 'YY', 'YY', NULL, DATE '2010-01-01');
  PERFORM pg_temp.place('xw', 'state', 'XW', 'XW', NULL, DATE '1900-01-01', DATE '2015-01-01');
  PERFORM pg_temp.place('harris', 'county', 'TX', '48201', 'tx', DATE '1900-01-01');
  PERFORM pg_temp.place('nanville', 'municipality', 'TX', 'NANVILLE', 'tx', DATE '1950-01-01');
  PERFORM pg_temp.place('zoneeast', 'municipality', 'TX', 'ZONEEAST', 'tx', DATE '1950-01-01');
  PERFORM pg_temp.fact('zoneeast', 'time_zone', '"America/Chicago"', DATE '1950-01-01');
  PERFORM pg_temp.place('zonewest', 'municipality', 'TX', 'ZONEWEST', 'tx', DATE '1950-01-01');
  PERFORM pg_temp.fact('zonewest', 'time_zone', '"America/Denver"', DATE '1950-01-01');
  PERFORM pg_temp.place('vown', 'municipality', 'TX', 'VOWN', 'tx', DATE '1950-01-01');
  PERFORM pg_temp.place('redo', 'municipality', 'TX', 'REDO', 'tx', DATE '1950-01-01');
  PERFORM pg_temp.place('notyet', 'municipality', 'TX', 'NOTYET', 'tx', CURRENT_DATE + 30);
  PERFORM pg_temp.place('fromtoday', 'municipality', 'TX', 'FROMTODAY', 'tx', CURRENT_DATE);
END $$;
SET LOCAL app.user_id = '00000000-0000-4000-8000-0000000016b1';
SET ROLE tally_app;
DO $$ BEGIN
  PERFORM pg_temp.mem('00000000-0000-4000-8000-0000000016d8', pg_temp.id('nanville'), 'regulatory', DATE '2020-01-01', NULL, 'outside', 'NaN'::numeric);
  RAISE EXCEPTION 'FAIL T1a: an outside distance of NaN';
EXCEPTION WHEN check_violation THEN NULL; END $$;
DO $$ BEGIN
  PERFORM pg_temp.mem('00000000-0000-4000-8000-0000000016d8', pg_temp.id('nanville'), 'regulatory', DATE '2020-01-01', NULL, 'outside', 0);
  RAISE EXCEPTION 'FAIL T1b: an outside distance of 0';
EXCEPTION WHEN check_violation THEN NULL; END $$;
DO $$ DECLARE v numeric; BEGIN
  PERFORM pg_temp.mem('00000000-0000-4000-8000-0000000016d8', pg_temp.id('nanville'), 'regulatory', DATE '2020-01-01', NULL, 'outside', 0.001);
  SELECT distance_miles INTO v FROM public.premise_places_as_of('00000000-0000-4000-8000-0000000016d8', DATE '2026-06-01', 'regulatory') WHERE place_id = pg_temp.id('nanville');
  IF v IS DISTINCT FROM 0.001 THEN RAISE EXCEPTION 'FAIL T1c: the smallest positive distance did not answer: %', v; END IF;
  RAISE NOTICE 'PASS T1: an outside distance is a positive finite number (NaN and 0 refused, 0.001 kept) (review r3)';
END $$;
SELECT pg_temp.prof('gas', 'YY', 'investor_owned', true, NULL, DATE '2020-01-01');
RESET ROLE;
DO $$ BEGIN
  UPDATE public.places SET effective_to = DATE '2025-01-01' WHERE id = pg_temp.id('yy');
  RAISE EXCEPTION 'FAIL T2a: a state closed under a profile it governs';
EXCEPTION WHEN restrict_violation THEN
  IF SQLERRM NOT LIKE '%governed by it%' THEN RAISE EXCEPTION 'FAIL T2a: refused by another guard: %', SQLERRM; END IF;
END $$;
DO $$ BEGIN
  -- the governed profile ends on the close day: no longer a conflict
  PERFORM set_config('app.user_id', '00000000-0000-4000-8000-0000000016b1', true);
  UPDATE public.utility_service_profiles SET effective_to = DATE '2030-01-01' WHERE state_code = 'YY';
  UPDATE public.places SET effective_to = DATE '2030-01-01' WHERE id = pg_temp.id('yy');
  RAISE EXCEPTION 'rollback T2b';
EXCEPTION WHEN raise_exception THEN
  IF SQLERRM <> 'rollback T2b' THEN RAISE; END IF;
END $$;
DO $$ BEGIN
  -- a voided governed profile does not hold its state open
  PERFORM set_config('app.user_id', '00000000-0000-4000-8000-0000000016b1', true);
  UPDATE public.utility_service_profiles SET void_reason = 'YY service never began' WHERE state_code = 'YY';
  UPDATE public.places SET effective_to = DATE '2025-01-01' WHERE id = pg_temp.id('yy');
  RAISE EXCEPTION 'rollback T2c';
EXCEPTION WHEN raise_exception THEN
  IF SQLERRM <> 'rollback T2c' THEN RAISE; END IF;
  RAISE NOTICE 'PASS T2: a state place does not close under a profile it governs; a profile ending on the close day, or voided, does not hold it (review r3)';
END $$;
SET LOCAL app.user_id = '00000000-0000-4000-8000-0000000016b1';
SET ROLE tally_app;
DO $$ DECLARE v text; BEGIN
  -- L13: El Paso County (Mountain) for rates; Harris County, no zone loaded, for tax
  PERFORM pg_temp.mem('00000000-0000-4000-8000-0000000016dd', pg_temp.id('elpaso_cty'), 'regulatory', DATE '2020-01-01');
  PERFORM pg_temp.mem('00000000-0000-4000-8000-0000000016dd', pg_temp.id('harris'), 'tax', DATE '2020-01-01');
  v := public.premise_time_zone_as_of('00000000-0000-4000-8000-0000000016dd', DATE '2026-06-01');
  RAISE EXCEPTION 'FAIL T3a: a county with a zone answered over a peer county with none: %', v;
EXCEPTION WHEN no_data_found THEN
  IF SQLERRM NOT LIKE '%carries none%' THEN RAISE EXCEPTION 'FAIL T3a: refused by another guard: %', SQLERRM; END IF;
END $$;
DO $$ DECLARE v text; BEGIN
  -- L14: Austin (no zone) and Travis (Central): the city level falls through
  PERFORM pg_temp.mem('00000000-0000-4000-8000-0000000016de', pg_temp.id('austin'), 'regulatory', DATE '2020-01-01');
  PERFORM pg_temp.mem('00000000-0000-4000-8000-0000000016de', pg_temp.id('travis'), 'regulatory', DATE '2020-01-01');
  v := public.premise_time_zone_as_of('00000000-0000-4000-8000-0000000016de', DATE '2026-06-01');
  IF v IS DISTINCT FROM 'America/Chicago' THEN RAISE EXCEPTION 'FAIL T3b: a city with no zone did not fall through to its county: %', v; END IF;
END $$;
DO $$ DECLARE v text; v_id uuid; BEGIN
  -- L15, an annexation window: ZoneEast for rates, ZoneWest for tax, two zones
  PERFORM pg_temp.mem('00000000-0000-4000-8000-0000000016df', pg_temp.id('zoneeast'), 'regulatory', DATE '2020-01-01');
  v_id := pg_temp.mem('00000000-0000-4000-8000-0000000016df', pg_temp.id('zonewest'), 'tax', DATE '2020-01-01');
  BEGIN
    v := public.premise_time_zone_as_of('00000000-0000-4000-8000-0000000016df', DATE '2026-06-01');
    RAISE EXCEPTION 'FAIL T3c: two cities with two zones answered %', v;
  EXCEPTION WHEN cardinality_violation THEN NULL; END;
  UPDATE public.premise_place_memberships SET void_reason = 'tax authority file misread' WHERE id = v_id;
  v := public.premise_time_zone_as_of('00000000-0000-4000-8000-0000000016df', DATE '2026-06-01');
  IF v IS DISTINCT FROM 'America/Chicago' THEN RAISE EXCEPTION 'FAIL T3d: the conflict outlived the void of one side: %', v; END IF;
  RAISE NOTICE 'PASS T3: at the answering level a place with no zone refuses, as two zones do; a level with none falls through; voiding one side clears a conflict (review r3)';
END $$;
RESET ROLE;
DO $$ BEGIN
  PERFORM pg_temp.fact('austin', 'local_adoption', '"Ord. 1"', DATE '2023-01-01', E'HB 1\t');
  RAISE EXCEPTION 'FAIL T4a: a key with a trailing tab';
EXCEPTION WHEN check_violation THEN NULL; END $$;
DO $$ BEGIN
  PERFORM pg_temp.fact('austin', 'local_adoption', '"Ord. 1"', DATE '2023-01-01', E'HB 1');
  RAISE EXCEPTION 'FAIL T4b: a key with a no-break space';
EXCEPTION WHEN check_violation THEN NULL; END $$;
DO $$ BEGIN
  PERFORM pg_temp.fact('austin', 'local_adoption', '"Ord. 1"', DATE '2023-01-01', 'HB  1');
  RAISE EXCEPTION 'FAIL T4c: a key with a doubled space';
EXCEPTION WHEN check_violation THEN NULL; END $$;
DO $$ BEGIN
  PERFORM pg_temp.fact('austin', 'local_adoption', '"Ord. 1"', DATE '2023-01-01', '305 ILCS 20/13(k)');
  PERFORM pg_temp.fact('austin', 'local_adoption', '"Ord. 2"', DATE '2023-01-01', '§7.45');
  RAISE NOTICE 'PASS T4: a fact key is citation-shaped: no tab, no-break space or doubled space; real citations pass (review r3)';
END $$;
DO $$ BEGIN
  PERFORM pg_temp.place('uninc2', 'unincorporated_area', 'TX', 'UNINC-B', 'tx', DATE '2000-01-01');
  RAISE EXCEPTION 'FAIL T5: a second unincorporated area of Texas';
EXCEPTION WHEN exclusion_violation THEN
  RAISE NOTICE 'PASS T5: one unincorporated area per state at a time (review r2 S-c, enforced r3)'; END $$;
DO $$ BEGIN
  -- Vown's only owning profile is voided: it does not hold Vown open
  PERFORM set_config('app.user_id', '00000000-0000-4000-8000-0000000016b1', true);
  INSERT INTO public.utility_service_profiles (tenant_id, service_type, system_kind, state_code, owner_type, commission_jurisdiction, owning_place_id,
                                               effective_from, evidence_reference, evidence_date)
  VALUES ('00000000-0000-4000-8000-0000000016a1', 'electric', 'distribution', 'TX', 'municipal', false, pg_temp.id('vown'), DATE '2020-01-01', 'x', DATE '2020-01-01');
  UPDATE public.utility_service_profiles SET void_reason = 'not Vown''s system' WHERE owning_place_id = pg_temp.id('vown');
  UPDATE public.places SET effective_to = DATE '2025-01-01' WHERE id = pg_temp.id('vown');
  RAISE NOTICE 'PASS T6: a voided owning profile does not hold its place open';
END $$;
DO $$ BEGIN
  PERFORM pg_temp.fact('nanville', 'sales_tax_rate', '1', DATE '1990-01-01');
  RAISE EXCEPTION 'FAIL T7a: a sales-tax rate of exactly 1';
EXCEPTION WHEN check_violation THEN NULL; END $$;
DO $$ BEGIN
  PERFORM pg_temp.fact('nanville', 'sales_tax_rate', '0.9999', DATE '1990-01-01');
  RAISE EXCEPTION 'rollback T7';
EXCEPTION WHEN raise_exception THEN
  IF SQLERRM <> 'rollback T7' THEN RAISE; END IF;
  RAISE NOTICE 'PASS T7: a rate''s upper bound is open (1 refused, 0.9999 kept)';
END $$;
SET LOCAL app.user_id = '00000000-0000-4000-8000-0000000016b1';
SET ROLE tally_app;
DO $$ BEGIN
  INSERT INTO public.jurisdictions (tenant_id, jurisdiction_code, jurisdiction_name, place_id)
  VALUES ('00000000-0000-4000-8000-0000000016a1', 'NOTYET', 'Not yet', pg_temp.id('notyet'));
  RAISE EXCEPTION 'FAIL T8a: a jurisdiction pointed at a place not yet begun';
EXCEPTION WHEN check_violation THEN NULL; END $$;
DO $$ BEGIN
  INSERT INTO public.jurisdictions (tenant_id, jurisdiction_code, jurisdiction_name, place_id)
  VALUES ('00000000-0000-4000-8000-0000000016a1', 'FROMTODAY', 'From today', pg_temp.id('fromtoday'));
  RAISE NOTICE 'PASS T8: a jurisdiction points at a begun place (one beginning today is begun; one beginning next month is not)';
END $$;
DO $$ DECLARE v_id uuid; BEGIN
  -- the commonest void: the same place, a wrong start date, recorded again
  v_id := pg_temp.mem('00000000-0000-4000-8000-0000000016e0', pg_temp.id('redo'), 'regulatory', DATE '2021-01-01');
  UPDATE public.premise_place_memberships SET void_reason = 'ordinance date misread' WHERE id = v_id;
  PERFORM pg_temp.mem('00000000-0000-4000-8000-0000000016e0', pg_temp.id('redo'), 'regulatory', DATE '2020-06-01');
  RAISE NOTICE 'PASS T9: a voided membership does not block the same place recorded again with the corrected date';
END $$;
DO $$ BEGIN
  PERFORM pg_temp.prof('water', 'YY', 'cooperative', true, NULL, DATE '2005-01-01');
  RAISE EXCEPTION 'FAIL T10a: a profile from before its state place began';
EXCEPTION WHEN check_violation THEN NULL; END $$;
DO $$ BEGIN
  PERFORM pg_temp.prof('water', 'XW', 'cooperative', true, NULL, DATE '2010-01-01');
  RAISE EXCEPTION 'FAIL T10b: an open profile for a state place that closed in 2015';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'PASS T10: a profile''s state place covers its whole range, not merely overlaps it'; END $$;
DO $$ BEGIN
  INSERT INTO public.premise_place_memberships (tenant_id, service_location_id, place_id, axis, place_kind, valid_from, evidence_kind, evidence_reference, evidence_date)
  VALUES ('00000000-0000-4000-8000-0000000016a1', '00000000-0000-4000-8000-0000000016e0', pg_temp.id('cmta'), 'tax', 'x', DATE '2020-01-01', 'ordinance', 'x', CURRENT_DATE);
  INSERT INTO public.utility_service_profiles (tenant_id, service_type, system_kind, state_code, owner_type, commission_jurisdiction, effective_from, evidence_reference, evidence_date)
  VALUES ('00000000-0000-4000-8000-0000000016a1', 'reclaimed_water', 'distribution', 'TX', 'investor_owned', true, DATE '2020-01-01', 'x', CURRENT_DATE);
  RAISE NOTICE 'PASS T11: evidence dated today is accepted, for a membership and a profile';
END $$;
DO $$ BEGIN
  INSERT INTO public.utility_service_profiles (tenant_id, service_type, system_kind, state_code, owner_type, commission_jurisdiction, effective_from, evidence_reference, evidence_date)
  VALUES ('00000000-0000-4000-8000-0000000016a1', 'reclaimed_water', 'distribution', 'ZZ', 'investor_owned', true, DATE '2020-01-01', 'x', NULL);
  RAISE EXCEPTION 'FAIL T12a: a profile with no evidence date';
EXCEPTION WHEN not_null_violation THEN NULL; END $$;
DO $$ BEGIN
  INSERT INTO public.premise_place_memberships (tenant_id, service_location_id, place_id, axis, place_kind, valid_from, evidence_kind, evidence_reference, evidence_date)
  VALUES ('00000000-0000-4000-8000-0000000016a1', '00000000-0000-4000-8000-0000000016e0', pg_temp.id('esd1'), 'tax', 'x', DATE '2020-01-01', 'ordinance', 'x', NULL);
  RAISE EXCEPTION 'FAIL T12b: a membership with no evidence date';
EXCEPTION WHEN not_null_violation THEN
  RAISE NOTICE 'PASS T12: memberships and profiles carry an evidence date'; END $$;
RESET ROLE;

-- ============================================================ U. review round 4
-- Platform fixtures for U (owner). YZ is a fictional state with no facts and
-- no children.
RESET ROLE;
INSERT INTO public.service_locations (id, tenant_id, customer_id, location_number, address_line1, city, state, zip) VALUES
  ('00000000-0000-4000-8000-0000000016e6', '00000000-0000-4000-8000-0000000016a1', '00000000-0000-4000-8000-0000000016c1', 'L17', '17 Main', 'Yville', 'YY', '00017'),
  ('00000000-0000-4000-8000-0000000016e7', '00000000-0000-4000-8000-0000000016a1', '00000000-0000-4000-8000-0000000016c1', 'L18', '18 Main', 'Austin', 'TX', '78718'),
  ('00000000-0000-4000-8000-0000000016e8', '00000000-0000-4000-8000-0000000016a1', '00000000-0000-4000-8000-0000000016c1', 'L19', '19 Main', 'Austin', 'TX', '78719'),
  ('00000000-0000-4000-8000-0000000016e9', '00000000-0000-4000-8000-0000000016a1', '00000000-0000-4000-8000-0000000016c1', 'L20', '20 Main', 'Austin', 'TX', '78720');
DO $$ BEGIN
  PERFORM pg_temp.place('yz', 'state', 'YZ', 'YZ', NULL, DATE '2000-01-01');
  PERFORM pg_temp.place('bastrop', 'county', 'TX', '48021', 'tx', DATE '1900-01-01');
  PERFORM pg_temp.fact('bastrop', 'time_zone', '"America/Chicago"', DATE '1900-01-01');
END $$;
SET LOCAL app.user_id = '00000000-0000-4000-8000-0000000016b1';
SET ROLE tally_app;
DO $$ BEGIN
  PERFORM pg_temp.mem('00000000-0000-4000-8000-0000000016d8', pg_temp.id('nanville'), 'tax', DATE '2020-01-01', NULL, 'outside', -1);
  RAISE EXCEPTION 'FAIL U1: an outside distance of -1';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'PASS U1: a negative distance is refused'; END $$;
DO $$ DECLARE v text; BEGIN
  -- L2 is in Travis on both axes (N2): one place twice is one answer
  v := public.premise_time_zone_as_of('00000000-0000-4000-8000-0000000016d2', DATE '2026-06-01');
  IF v IS DISTINCT FROM 'America/Chicago' THEN RAISE EXCEPTION 'FAIL U2a: one county on both axes read %', v; END IF;
  -- L18: Travis for rates, Bastrop for tax — two counties, one zone
  PERFORM pg_temp.mem('00000000-0000-4000-8000-0000000016e7', pg_temp.id('travis'), 'regulatory', DATE '2020-01-01');
  PERFORM pg_temp.mem('00000000-0000-4000-8000-0000000016e7', pg_temp.id('bastrop'), 'tax', DATE '2020-01-01');
  v := public.premise_time_zone_as_of('00000000-0000-4000-8000-0000000016e7', DATE '2026-06-01');
  IF v IS DISTINCT FROM 'America/Chicago' THEN RAISE EXCEPTION 'FAIL U2b: two counties agreeing read %', v; END IF;
  RAISE NOTICE 'PASS U2: agreeing places at the answering level answer — one county on both axes, or two counties with one zone';
END $$;
DO $$ BEGIN
  -- YY's state place begins in 2010: on a date before, L17 has no state
  PERFORM * FROM public.premise_places_as_of('00000000-0000-4000-8000-0000000016e6', DATE '2005-01-01', 'regulatory');
  RAISE EXCEPTION 'FAIL U3: a state read on a date before its place began';
EXCEPTION WHEN no_data_found THEN
  RAISE NOTICE 'PASS U3: the place lookup reads a state only on a date its place is in force'; END $$;
SELECT 1 FROM (SELECT pg_temp.prof('gas', 'YZ', 'investor_owned', true, NULL, DATE '2020-01-01')) x;
DO $$ BEGIN
  UPDATE public.utility_service_profiles SET effective_to = DATE '2030-01-01' WHERE state_code = 'YZ';
END $$;
RESET ROLE;
DO $$ BEGIN
  UPDATE public.places SET effective_to = DATE '2025-01-01' WHERE id = pg_temp.id('yz');
  RAISE EXCEPTION 'FAIL U4: a state closed under a governed profile that ends after the close';
EXCEPTION WHEN restrict_violation THEN
  IF SQLERRM NOT LIKE '%governed by it%' THEN RAISE EXCEPTION 'FAIL U4: refused by another guard: %', SQLERRM; END IF;
  RAISE NOTICE 'PASS U4: a governed profile with an end date after the close holds its state open'; END $$;
SET LOCAL app.user_id = '00000000-0000-4000-8000-0000000016b1';
SET ROLE tally_app;
DO $$ BEGIN
  -- a district stacks (no group): only no_repeat can refuse within and outside it at once
  PERFORM pg_temp.mem('00000000-0000-4000-8000-0000000016e8', pg_temp.id('esd2'), 'regulatory', DATE '2020-01-01');
  PERFORM pg_temp.mem('00000000-0000-4000-8000-0000000016e8', pg_temp.id('esd2'), 'regulatory', DATE '2020-01-01', NULL, 'outside', 2);
  RAISE EXCEPTION 'FAIL U5: within and outside one district at once on one axis';
EXCEPTION WHEN exclusion_violation THEN
  IF SQLERRM NOT LIKE '%no_repeat%' THEN RAISE EXCEPTION 'FAIL U5: refused by another guard: %', SQLERRM; END IF;
  RAISE NOTICE 'PASS U5: a premise is not within and outside one place at once on one axis'; END $$;
DO $$ BEGIN
  INSERT INTO public.utility_service_profiles (tenant_id, service_type, system_kind, state_code, owner_type, commission_jurisdiction, effective_from, evidence_reference, evidence_date)
  VALUES ('00000000-0000-4000-8000-0000000016a1', 'water', 'master_meter', 'ZZ', 'investor_owned', true, DATE '2020-01-01', 'x', DATE '2020-01-01');
  RAISE EXCEPTION 'FAIL U6a: a water master-meter system';
EXCEPTION WHEN check_violation THEN NULL; END $$;
DO $$ BEGIN
  INSERT INTO public.utility_service_profiles (tenant_id, service_type, system_kind, state_code, owner_type, commission_jurisdiction, effective_from, evidence_reference, evidence_date)
  VALUES ('00000000-0000-4000-8000-0000000016a1', 'sewer', 'distribution', 'ZZ', 'propane_piped', true, DATE '2020-01-01', 'x', DATE '2020-01-01');
  RAISE EXCEPTION 'FAIL U6b: piped propane as an owner type';
EXCEPTION WHEN foreign_key_violation THEN NULL; END $$;
DO $$ DECLARE r record; BEGIN
  -- a city-owned piped-propane system: owner and system are separate facts
  INSERT INTO public.utility_service_profiles (tenant_id, service_type, system_kind, state_code, owner_type, commission_jurisdiction, owning_place_id, effective_from, evidence_reference, evidence_date)
  VALUES ('00000000-0000-4000-8000-0000000016a1', 'gas', 'piped_propane_distribution', 'YZ', 'municipal', false, pg_temp.id('zcity'), DATE '2030-01-01', 'x', DATE '2020-01-01');
  SELECT * INTO r FROM public.utility_service_profile_as_of('00000000-0000-4000-8000-0000000016a1', 'gas', 'YZ', DATE '2031-01-01');
  IF r.system_kind IS DISTINCT FROM 'piped_propane_distribution' OR r.owner_type IS DISTINCT FROM 'municipal' THEN RAISE EXCEPTION 'FAIL U6c: read %/%', r.owner_type, r.system_kind; END IF;
  RAISE NOTICE 'PASS U6: who owns a utility and what system it runs are separate: a city-owned piped-propane system; a system kind fits its service; propane is not an owner';
END $$;
DO $$ BEGIN
  -- L19: in Austin's ETJ for tax too, so "in no city" is recorded positively
  PERFORM pg_temp.mem('00000000-0000-4000-8000-0000000016e9', pg_temp.id('austin_etj'), 'tax', DATE '2020-01-01');
  PERFORM pg_temp.mem('00000000-0000-4000-8000-0000000016e9', pg_temp.id('austin_lpa'), 'regulatory', DATE '2020-01-01');
  BEGIN
    PERFORM pg_temp.mem('00000000-0000-4000-8000-0000000016e9', pg_temp.id('austin'), 'tax', DATE '2020-01-01');
    RAISE EXCEPTION 'FAIL U7a: a city and its ETJ at once on the tax axis';
  EXCEPTION WHEN exclusion_violation THEN NULL; END;
  RAISE NOTICE 'PASS U7: extraterritorial and limited-purpose areas take the tax axis, exclusive with the city there too';
END $$;
RESET ROLE;
DO $$ BEGIN
  PERFORM pg_temp.fact('austin', 'local_adoption', '"Ord. 1"', DATE '2023-01-01', '§');
  RAISE EXCEPTION 'FAIL U8a: a key that is a bare section sign';
EXCEPTION WHEN check_violation THEN NULL; END $$;
DO $$ BEGIN
  PERFORM pg_temp.fact('austin', 'local_adoption', '"Ord. 1"', DATE '2023-01-01', '16 TAC § 7.45');
  RAISE EXCEPTION 'FAIL U8b: a key with a space after the section sign';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'PASS U8: a key holds a letter or digit, and no space after §'; END $$;
SET LOCAL app.user_id = '00000000-0000-4000-8000-0000000016b1';
SET ROLE tally_app;
DO $$ BEGIN
  PERFORM pg_temp.mem('00000000-0000-4000-8000-0000000016e9', '00000000-0000-4000-8000-00000000dead'::uuid, 'regulatory', DATE '2020-01-01');
  RAISE EXCEPTION 'FAIL U9: a membership of a place that does not exist';
EXCEPTION WHEN foreign_key_violation THEN
  IF SQLERRM NOT LIKE '%place % not found%' THEN RAISE EXCEPTION 'FAIL U9: refused without naming the place: %', SQLERRM; END IF;
  RAISE NOTICE 'PASS U9: a membership of an unknown place is refused by name'; END $$;
RESET ROLE;
DO $$ BEGIN
  -- NotYet has no citation, so only the edit rule can refuse
  UPDATE public.places SET name = name WHERE id = pg_temp.id('notyet');
  RAISE EXCEPTION 'FAIL U10: a no-op update of an open place';
EXCEPTION WHEN restrict_violation THEN
  RAISE NOTICE 'PASS U10: an update of a place that does not close it is refused, even one that changes nothing'; END $$;

-- ============================================================ G. tenancy
SET LOCAL app.user_id = '00000000-0000-4000-8000-0000000016b2';
SET ROLE tally_app;
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM public.premise_place_memberships) OR EXISTS (SELECT 1 FROM public.utility_service_profiles) THEN
    RAISE EXCEPTION 'FAIL G1: T2 sees T1''s memberships or profiles';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.places WHERE id = pg_temp.id('austin')) THEN
    RAISE EXCEPTION 'FAIL G1: T2 cannot see the shared places';
  END IF;
  RAISE NOTICE 'PASS G1: another utility sees the shared places but none of T1''s memberships or profiles';
END $$;
DO $$ BEGIN
  INSERT INTO public.premise_place_memberships (tenant_id, service_location_id, place_id, axis, place_kind,
                                                valid_from, evidence_kind, evidence_reference, evidence_date)
  VALUES ('00000000-0000-4000-8000-0000000016a1', '00000000-0000-4000-8000-0000000016d2', pg_temp.id('austin'), 'tax', 'x',
          DATE '2027-01-01', 'ordinance', 'x', DATE '2026-01-01');
  RAISE EXCEPTION 'FAIL G2: T2 recorded a membership for T1''s premise';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'PASS G2: a utility''s user cannot record memberships for another utility''s premises'; END $$;
RESET ROLE;
DO $$ BEGIN
  DELETE FROM public.premise_place_memberships WHERE place_id = pg_temp.id('travis');
  RAISE EXCEPTION 'FAIL G3a: the owner deleted a membership';
EXCEPTION WHEN restrict_violation THEN NULL; END $$;
DO $$ BEGIN
  DELETE FROM public.utility_service_profiles WHERE tenant_id = '00000000-0000-4000-8000-0000000016a1';
  RAISE EXCEPTION 'FAIL G3b: the owner deleted a profile';
EXCEPTION WHEN restrict_violation THEN
  RAISE NOTICE 'PASS G3: memberships and profiles are never deleted, by the owner either'; END $$;
DO $$ BEGIN
  PERFORM public.assert_tenant_isolation_invariants();
  RAISE NOTICE 'PASS G4: tenant isolation holds over the new tables (AC-32)';
END $$;

ROLLBACK;
