-- ============================================================================
-- BATTERY v5.4.2-16 — places and applicability (2026-10-06)
-- Run: psql -U tally -d <db-with-patch> -v ON_ERROR_STOP=1 -f battery-16.sql
-- One transaction, rolled back. Negative cases inside DO blocks that check
-- the SQLSTATE; each built so only the guard it names can refuse it. Written
-- as tally_app except the platform rows (places, facts), which only reviewed
-- migrations write. TWO tenants. ZZ is a fictional second state.
--
--   A  vocabularies and places are platform-held, close-only   (sections 2-3)
--   F  place facts                                              (section 4)
--   M  premise memberships                                      (section 5)
--   P  utility service profiles                                 (section 6)
--   C  a place's close floor                                    (section 3)
--   L  lookups                                                  (section 8)
--   G  jurisdictions, tenancy, the AC-32 tail                   (sections 7, 11)
-- Races (a membership or profile in flight against a place's close; a close
-- under REPEATABLE READ): races/place-close-16.sh.
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
-- L1: El Paso (TX); L2: Austin area (TX); L3: a ZZ premise; L9: T2's (TX).
INSERT INTO public.service_locations (id, tenant_id, customer_id, location_number, address_line1, city, state, zip) VALUES
  ('00000000-0000-4000-8000-0000000016d1', '00000000-0000-4000-8000-0000000016a1', '00000000-0000-4000-8000-0000000016c1', 'L1', '1 Main', 'El Paso', 'TX', '79901'),
  ('00000000-0000-4000-8000-0000000016d2', '00000000-0000-4000-8000-0000000016a1', '00000000-0000-4000-8000-0000000016c1', 'L2', '2 Main', 'Austin', 'TX', '78701'),
  ('00000000-0000-4000-8000-0000000016d3', '00000000-0000-4000-8000-0000000016a1', '00000000-0000-4000-8000-0000000016c1', 'L3', '3 Main', 'Zedton', 'ZZ', '00001'),
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
-- mem(): a membership as the utility records it.
CREATE FUNCTION pg_temp.mem(p_loc uuid, p_place uuid, p_axis text, p_from date, p_to date DEFAULT NULL) RETURNS uuid
LANGUAGE sql AS $$
  INSERT INTO public.premise_place_memberships (tenant_id, service_location_id, place_id, axis, place_kind, single_per_premise,
                                                valid_from, valid_to, evidence_kind, evidence_reference, created_by)
  SELECT l.tenant_id, l.id, p_place, p_axis, 'state', true, p_from, p_to, 'ordinance', 'Ord. 2020-1',
         NULLIF(current_setting('app.user_id', true), '')::uuid
    FROM public.service_locations l WHERE l.id = p_loc
  RETURNING id
$$;
GRANT EXECUTE ON FUNCTION pg_temp.mem(uuid, uuid, text, date, date) TO tally_app;

-- Platform fixtures (owner): ZZ and its places; El Paso city inside El Paso County.
DO $$ BEGIN
  INSERT INTO b16 SELECT 'tx', id FROM public.places WHERE kind_code = 'state' AND place_code = 'TX';
  INSERT INTO b16 SELECT 'elpaso_cty', id FROM public.places WHERE kind_code = 'county' AND place_code = '48141';
  PERFORM pg_temp.place('zz', 'state', 'ZZ', 'ZZ', NULL, DATE '1900-01-01');
  PERFORM pg_temp.place('travis', 'county', 'TX', '48453', 'tx', DATE '1900-01-01');
  PERFORM pg_temp.place('elpaso', 'municipality', 'TX', 'ELPASO', 'tx', DATE '1900-01-01');
  PERFORM pg_temp.place('austin', 'municipality', 'TX', 'AUSTIN', 'tx', DATE '1900-01-01');
  PERFORM pg_temp.place('roundrock', 'municipality', 'TX', 'ROUNDROCK', 'tx', DATE '1913-01-01');
  PERFORM pg_temp.place('cmta', 'transit_authority', 'TX', 'CMTA', 'tx', DATE '1985-01-01');
  PERFORM pg_temp.place('esd1', 'special_purpose_district', 'TX', 'ESD1', 'austin', DATE '2000-01-01');
  PERFORM pg_temp.place('esd2', 'special_purpose_district', 'TX', 'ESD2', 'austin', DATE '2000-01-01');
  PERFORM pg_temp.place('zcity', 'municipality', 'ZZ', 'ZEDTON', 'zz', DATE '1950-01-01');
  PERFORM pg_temp.place('short', 'municipality', 'TX', 'SHORTVILLE', 'tx', DATE '2020-01-01', DATE '2025-01-01');
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
  INSERT INTO public.utility_owner_types (owner_type, requires_owning_place, description, source_note) VALUES ('x', false, 'x', 'x');
  RAISE EXCEPTION 'FAIL A1c: the application wrote an owner type';
EXCEPTION WHEN insufficient_privilege THEN
  RAISE NOTICE 'PASS A1: the application cannot write places, place facts or the vocabularies'; END $$;
RESET ROLE;
DO $$ BEGIN
  UPDATE public.places SET name = 'Austin, Texas' WHERE id = pg_temp.id('austin');
  RAISE EXCEPTION 'FAIL A2a: a place renamed';
EXCEPTION WHEN restrict_violation THEN NULL; END $$;
DO $$ BEGIN
  UPDATE public.places SET effective_to = DATE '2090-01-01', name = 'x' WHERE id = pg_temp.id('roundrock');
  RAISE EXCEPTION 'FAIL A2b: a close that carries an edit';
EXCEPTION WHEN restrict_violation THEN NULL; END $$;
DO $$ BEGIN
  DELETE FROM public.places WHERE id = pg_temp.id('roundrock');
  RAISE EXCEPTION 'FAIL A2c: a place deleted';
EXCEPTION WHEN restrict_violation THEN
  RAISE NOTICE 'PASS A2: a place is never edited or deleted, only closed (and a close carries nothing else)'; END $$;
DO $$ BEGIN
  UPDATE public.place_kinds SET single_per_premise = false WHERE kind_code = 'county';
  RAISE EXCEPTION 'FAIL A3a: a place kind edited';
EXCEPTION WHEN restrict_violation THEN NULL; END $$;
DO $$ BEGIN
  DELETE FROM public.utility_owner_types WHERE owner_type = 'master_meter';
  RAISE EXCEPTION 'FAIL A3b: an owner type deleted';
EXCEPTION WHEN restrict_violation THEN
  RAISE NOTICE 'PASS A3: the vocabularies are never edited or deleted, by the owner either'; END $$;
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
  PERFORM pg_temp.place('zzkid', 'municipality', 'ZZ', 'ZKID', 'austin', DATE '2000-01-01');
  RAISE EXCEPTION 'FAIL A5a: a ZZ place under a Texas parent';
EXCEPTION WHEN check_violation THEN NULL; END $$;
DO $$ BEGIN
  PERFORM pg_temp.place('earlykid', 'special_purpose_district', 'TX', 'EARLY', 'short', DATE '2019-01-01');
  RAISE EXCEPTION 'FAIL A5b: a child older than its parent';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'PASS A5: a parent is of the same state and in force over the whole child'; END $$;
DO $$ BEGIN
  PERFORM pg_temp.place('austin2', 'municipality', 'TX', 'AUSTIN', 'tx', DATE '2020-01-01');
  RAISE EXCEPTION 'FAIL A6: two Austins at once';
EXCEPTION WHEN exclusion_violation THEN
  RAISE NOTICE 'PASS A6: one place per kind, state and code at a time'; END $$;


-- ============================================================ F. place facts
DO $$ BEGIN
  INSERT INTO public.place_facts (place_id, fact_code, value, effective_from, source_note)
  VALUES (pg_temp.id('cmta'), 'census_population', '961855', DATE '2020-01-01', 'x');
  RAISE EXCEPTION 'FAIL F1: a census population on a transit authority';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'PASS F1: a fact applies only to the place kinds its vocabulary row names'; END $$;
DO $$ BEGIN
  INSERT INTO public.place_facts (place_id, fact_code, value, effective_from, source_note)
  VALUES (pg_temp.id('austin'), 'census_population', '"lots"', DATE '2020-01-01', 'x');
  RAISE EXCEPTION 'FAIL F2a: a population that is text';
EXCEPTION WHEN check_violation THEN NULL; END $$;
DO $$ BEGIN
  INSERT INTO public.place_facts (place_id, fact_code, value, effective_from, source_note)
  VALUES (pg_temp.id('austin'), 'time_zone', '"America/Austin"', DATE '2020-01-01', 'x');
  RAISE EXCEPTION 'FAIL F2b: a time zone the server does not know';
EXCEPTION WHEN check_violation THEN NULL; END $$;
DO $$ BEGIN
  INSERT INTO public.place_facts (place_id, fact_code, value, effective_from, source_note)
  VALUES (pg_temp.id('esd1'), 'special_district_type', '"  "', DATE '2020-01-01', 'x');
  RAISE EXCEPTION 'FAIL F2c: a blank text value';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'PASS F2: a fact''s value is of its declared type (a number, a known time zone, non-blank text)'; END $$;
DO $$ BEGIN
  INSERT INTO public.place_facts (place_id, fact_code, value, effective_from, source_note)
  VALUES (pg_temp.id('short'), 'census_population', '500', DATE '2019-01-01', 'x');
  RAISE EXCEPTION 'FAIL F3: a fact from before its place';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'PASS F3: a fact lies within its place''s range'; END $$;
INSERT INTO public.place_facts (place_id, fact_code, value, effective_from, source_note)
VALUES (pg_temp.id('austin'), 'gas_rate_jurisdiction_retained', 'true', DATE '1975-01-01', 'Utilities Code 103.001');
INSERT INTO public.place_facts (place_id, fact_code, value, effective_from, source_note)
VALUES (pg_temp.id('esd1'), 'residential_gas_taxable', 'true', DATE '2000-01-01', 'Comptroller');
DO $$ BEGIN
  INSERT INTO public.place_facts (place_id, fact_code, value, effective_from, source_note)
  VALUES (pg_temp.id('austin'), 'gas_rate_jurisdiction_retained', 'false', DATE '2020-01-01', 'x');
  RAISE EXCEPTION 'FAIL F4a: two answers to one fact at once';
EXCEPTION WHEN exclusion_violation THEN NULL; END $$;
DO $$ BEGIN
  UPDATE public.place_facts SET value = 'false' WHERE place_id = pg_temp.id('austin') AND fact_code = 'gas_rate_jurisdiction_retained';
  RAISE EXCEPTION 'FAIL F4b: a fact edited';
EXCEPTION WHEN restrict_violation THEN NULL; END $$;
DO $$ BEGIN
  UPDATE public.place_facts SET effective_to = DATE '2030-01-01', value = 'false'
   WHERE place_id = pg_temp.id('austin') AND fact_code = 'gas_rate_jurisdiction_retained';
  RAISE EXCEPTION 'FAIL F4c: a close that carries an edit';
EXCEPTION WHEN restrict_violation THEN NULL; END $$;
DO $$ BEGIN
  DELETE FROM public.place_facts WHERE place_id = pg_temp.id('esd1');
  RAISE EXCEPTION 'FAIL F4d: a fact deleted';
EXCEPTION WHEN restrict_violation THEN
  RAISE NOTICE 'PASS F4: one answer per fact at a time; never edited or deleted, only closed'; END $$;
DO $$ DECLARE r record; BEGIN
  UPDATE public.place_facts SET effective_to = DATE '2030-01-01'
   WHERE place_id = pg_temp.id('esd1') AND fact_code = 'residential_gas_taxable';
  SELECT closed_at, closed_by INTO r FROM public.place_facts WHERE place_id = pg_temp.id('esd1');
  IF r.closed_at IS NULL OR r.closed_by IS NULL THEN RAISE EXCEPTION 'FAIL F5: the close was not stamped'; END IF;
  RAISE NOTICE 'PASS F5: a fact''s close is stamped (when, which role)';
END $$;


-- ============================================================ M. memberships
SET LOCAL app.user_id = '00000000-0000-4000-8000-0000000016b1';
SET ROLE tally_app;
DO $$ DECLARE v uuid; r record; BEGIN
  v := pg_temp.mem('00000000-0000-4000-8000-0000000016d2', pg_temp.id('travis'), 'regulatory', DATE '2020-01-01');
  SELECT * INTO r FROM public.premise_place_memberships WHERE id = v;
  -- mem() passes place_kind 'state' and single true: the trigger copies the place's
  IF r.place_kind <> 'county' OR NOT r.single_per_premise OR r.created_by IS NULL OR r.created_at IS NULL THEN
    RAISE EXCEPTION 'FAIL M1: the kind facets or stamps were not set from the place: %', row_to_json(r);
  END IF;
  RAISE NOTICE 'PASS M1: a membership''s kind and single-per-premise flag come from its place, not the caller; stamped';
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
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'PASS M4: a membership lies within its place''s range'; END $$;
-- Annexation: L2 joins Austin on the ordinance date (regulatory) and on the
-- Comptroller's quarter (tax) — two memberships, two dates.
SELECT pg_temp.mem('00000000-0000-4000-8000-0000000016d2', pg_temp.id('austin'), 'regulatory', DATE '2025-12-15');
SELECT pg_temp.mem('00000000-0000-4000-8000-0000000016d2', pg_temp.id('austin'), 'tax', DATE '2026-04-01');
DO $$ BEGIN
  PERFORM pg_temp.mem('00000000-0000-4000-8000-0000000016d2', pg_temp.id('roundrock'), 'regulatory', DATE '2026-01-01');
  RAISE EXCEPTION 'FAIL M5a: two cities at once on one axis';
EXCEPTION WHEN exclusion_violation THEN NULL; END $$;
DO $$ BEGIN
  PERFORM pg_temp.mem('00000000-0000-4000-8000-0000000016d2', pg_temp.id('austin'), 'regulatory', DATE '2026-02-01');
  RAISE EXCEPTION 'FAIL M5b: the same city twice';
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
  RAISE NOTICE 'PASS M5: one city per premise and axis at a time, never the same place twice; each axis dated on its own; districts stack';
END $$;
DO $$ BEGIN
  INSERT INTO public.premise_place_memberships (tenant_id, service_location_id, place_id, axis, place_kind, single_per_premise,
                                                valid_from, evidence_kind, evidence_reference)
  VALUES ('00000000-0000-4000-8000-0000000016a1', '00000000-0000-4000-8000-0000000016d1', pg_temp.id('elpaso_cty'), 'regulatory', 'x', true,
          DATE '2020-01-01', 'ordinance', '   ');
  RAISE EXCEPTION 'FAIL M6: evidence without its reference';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'PASS M6: a membership states what it rests on'; END $$;
DO $$ BEGIN
  UPDATE public.premise_place_memberships SET valid_from = DATE '2019-01-01'
   WHERE service_location_id = '00000000-0000-4000-8000-0000000016d2' AND place_id = pg_temp.id('travis');
  RAISE EXCEPTION 'FAIL M7a: a membership edited';
EXCEPTION WHEN restrict_violation THEN NULL; END $$;
DO $$ BEGIN
  UPDATE public.premise_place_memberships SET valid_to = DATE '2027-01-01', evidence_reference = 'rewritten'
   WHERE service_location_id = '00000000-0000-4000-8000-0000000016d2' AND place_id = pg_temp.id('travis');
  RAISE EXCEPTION 'FAIL M7e: a close that carries an edit';
EXCEPTION WHEN restrict_violation THEN NULL; END $$;
DO $$ BEGIN
  DELETE FROM public.premise_place_memberships WHERE place_id = pg_temp.id('travis');
  RAISE EXCEPTION 'FAIL M7b: a membership deleted';
EXCEPTION WHEN restrict_violation OR insufficient_privilege THEN NULL; END $$;
DO $$ DECLARE r record; BEGIN
  UPDATE public.premise_place_memberships SET valid_to = DATE '2026-04-01'
   WHERE service_location_id = '00000000-0000-4000-8000-0000000016d2' AND place_id = pg_temp.id('esd2');
  SELECT closed_at, closed_by INTO r FROM public.premise_place_memberships
   WHERE service_location_id = '00000000-0000-4000-8000-0000000016d2' AND place_id = pg_temp.id('esd2');
  RAISE EXCEPTION 'FAIL M7c: a zero-length close accepted';
EXCEPTION WHEN check_violation THEN NULL; END $$;
DO $$ DECLARE r record; BEGIN
  UPDATE public.premise_place_memberships SET valid_to = DATE '2026-07-01'
   WHERE service_location_id = '00000000-0000-4000-8000-0000000016d2' AND place_id = pg_temp.id('esd2');
  SELECT closed_at, closed_by INTO r FROM public.premise_place_memberships
   WHERE service_location_id = '00000000-0000-4000-8000-0000000016d2' AND place_id = pg_temp.id('esd2');
  IF r.closed_at IS NULL OR r.closed_by IS DISTINCT FROM '00000000-0000-4000-8000-0000000016b1'::uuid THEN
    RAISE EXCEPTION 'FAIL M7d: the close was not stamped';
  END IF;
  RAISE NOTICE 'PASS M7: a membership is never edited or deleted; its close is after its start and stamped with who closed it';
END $$;
SELECT pg_temp.mem('00000000-0000-4000-8000-0000000016d1', pg_temp.id('elpaso_cty'), 'regulatory', DATE '2020-01-01');
SELECT pg_temp.mem('00000000-0000-4000-8000-0000000016d1', pg_temp.id('elpaso'), 'regulatory', DATE '2020-01-01');


-- ============================================================ P. profiles
DO $$ BEGIN
  INSERT INTO public.utility_service_profiles (tenant_id, service_type, state_code, owner_type, commission_jurisdiction,
                                               effective_from, evidence_reference, created_by)
  VALUES ('00000000-0000-4000-8000-0000000016a1', 'gas', 'TX', 'municipal', false, DATE '2020-01-01', 'City charter art. 9',
          '00000000-0000-4000-8000-0000000016b1');
  RAISE EXCEPTION 'FAIL P1a: a municipal owner without its owning place';
EXCEPTION WHEN check_violation THEN NULL; END $$;
DO $$ BEGIN
  INSERT INTO public.utility_service_profiles (tenant_id, service_type, state_code, owner_type, commission_jurisdiction,
                                               owning_place_id, effective_from, evidence_reference)
  VALUES ('00000000-0000-4000-8000-0000000016a1', 'gas', 'TX', 'investor_owned', true, pg_temp.id('austin'), DATE '2020-01-01', 'x');
  RAISE EXCEPTION 'FAIL P1b: an investor-owned utility with an owning place';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'PASS P1: an owning place exactly when the owner type is a public body (from the vocabulary)'; END $$;
DO $$ BEGIN
  INSERT INTO public.utility_service_profiles (tenant_id, service_type, state_code, owner_type, commission_jurisdiction,
                                               owning_place_id, effective_from, evidence_reference)
  VALUES ('00000000-0000-4000-8000-0000000016a1', 'gas', 'TX', 'municipal', false, pg_temp.id('zcity'), DATE '2020-01-01', 'x');
  RAISE EXCEPTION 'FAIL P2a: a Texas profile owned by a ZZ city';
EXCEPTION WHEN check_violation THEN NULL; END $$;
DO $$ BEGIN
  INSERT INTO public.utility_service_profiles (tenant_id, service_type, state_code, owner_type, commission_jurisdiction,
                                               owning_place_id, effective_from, evidence_reference)
  VALUES ('00000000-0000-4000-8000-0000000016a1', 'gas', 'TX', 'municipal', false, pg_temp.id('tx'), DATE '2020-01-01', 'x');
  RAISE EXCEPTION 'FAIL P2b: a state as the owning place';
EXCEPTION WHEN check_violation THEN NULL; END $$;
DO $$ BEGIN
  INSERT INTO public.utility_service_profiles (tenant_id, service_type, state_code, owner_type, commission_jurisdiction,
                                               owning_place_id, effective_from, evidence_reference)
  VALUES ('00000000-0000-4000-8000-0000000016a1', 'gas', 'TX', 'municipal', false, pg_temp.id('short'), DATE '2020-01-01', 'x');
  RAISE EXCEPTION 'FAIL P2c: owned by a place that closes first';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'PASS P2: the owning place is of the profile''s state, below the state, and in force over the whole profile'; END $$;
INSERT INTO public.utility_service_profiles (tenant_id, service_type, state_code, owner_type, commission_jurisdiction,
                                             owning_place_id, effective_from, evidence_reference, created_by)
VALUES ('00000000-0000-4000-8000-0000000016a1', 'gas', 'TX', 'municipal', false, pg_temp.id('elpaso'), DATE '2020-01-01',
        'City charter art. 9', '00000000-0000-4000-8000-0000000016b1');
DO $$ BEGIN
  INSERT INTO public.utility_service_profiles (tenant_id, service_type, state_code, owner_type, commission_jurisdiction,
                                               effective_from, evidence_reference)
  VALUES ('00000000-0000-4000-8000-0000000016a1', 'gas', 'TX', 'investor_owned', true, DATE '2024-01-01', 'x');
  RAISE EXCEPTION 'FAIL P3: two profiles for one service and state at once';
EXCEPTION WHEN exclusion_violation THEN
  RAISE NOTICE 'PASS P3: one profile per utility, service and state at a time'; END $$;
DO $$ BEGIN
  UPDATE public.utility_service_profiles SET commission_jurisdiction = true WHERE tenant_id = '00000000-0000-4000-8000-0000000016a1';
  RAISE EXCEPTION 'FAIL P4a: a profile edited';
EXCEPTION WHEN restrict_violation THEN NULL; END $$;
DO $$ BEGIN
  UPDATE public.utility_service_profiles SET effective_to = DATE '2026-01-01', owner_type = 'investor_owned', owning_place_id = NULL
   WHERE tenant_id = '00000000-0000-4000-8000-0000000016a1';
  RAISE EXCEPTION 'FAIL P4c: a close that carries an edit';
EXCEPTION WHEN restrict_violation THEN NULL; END $$;
DO $$ BEGIN
  DELETE FROM public.utility_service_profiles WHERE tenant_id = '00000000-0000-4000-8000-0000000016a1';
  RAISE EXCEPTION 'FAIL P4b: a profile deleted';
EXCEPTION WHEN restrict_violation OR insufficient_privilege THEN
  RAISE NOTICE 'PASS P4: a profile is never edited or deleted'; END $$;
-- An election moves the city system under the commission: close and succeed.
DO $$ DECLARE r record; BEGIN
  UPDATE public.utility_service_profiles SET effective_to = DATE '2026-01-01' WHERE tenant_id = '00000000-0000-4000-8000-0000000016a1';
  INSERT INTO public.utility_service_profiles (tenant_id, service_type, state_code, owner_type, commission_jurisdiction,
                                               owning_place_id, effective_from, evidence_reference)
  VALUES ('00000000-0000-4000-8000-0000000016a1', 'gas', 'TX', 'municipal', true, pg_temp.id('elpaso'), DATE '2026-01-01', 'Election of 2025-11-04');
  SELECT * INTO r FROM public.utility_service_profile_as_of('00000000-0000-4000-8000-0000000016a1', 'gas', 'TX', DATE '2025-06-01');
  IF r.commission_jurisdiction THEN RAISE EXCEPTION 'FAIL P5: the 2025 profile reads under the commission'; END IF;
  SELECT * INTO r FROM public.utility_service_profile_as_of('00000000-0000-4000-8000-0000000016a1', 'gas', 'TX', DATE '2026-06-01');
  IF NOT r.commission_jurisdiction OR r.owner_type <> 'municipal' THEN RAISE EXCEPTION 'FAIL P5: the 2026 profile is wrong'; END IF;
  RAISE NOTICE 'PASS P5: an election changes jurisdiction without changing ownership — a close and a successor, each read on its date';
END $$;
DO $$ DECLARE r record; BEGIN
  SELECT * INTO r FROM public.utility_service_profile_as_of('00000000-0000-4000-8000-0000000016a1', 'water', 'TX', DATE '2026-06-01');
  RAISE EXCEPTION 'FAIL L1: a profile invented for water';
EXCEPTION WHEN no_data_found THEN
  RAISE NOTICE 'PASS L1: with no profile recorded the lookup refuses, never assumes one'; END $$;


-- ============================================================ L. lookups
DO $$ DECLARE v text; BEGIN
  v := public.premise_time_zone_as_of('00000000-0000-4000-8000-0000000016d1', DATE '2026-06-01');
  IF v <> 'America/Denver' THEN RAISE EXCEPTION 'FAIL L2a: El Paso reads %', v; END IF;
  v := public.premise_time_zone_as_of('00000000-0000-4000-8000-0000000016d2', DATE '2026-06-01');
  IF v <> 'America/Chicago' THEN RAISE EXCEPTION 'FAIL L2b: Austin reads %', v; END IF;
  RAISE NOTICE 'PASS L2: the time zone is the most specific place''s — Mountain for an El Paso County premise, the state''s Central otherwise';
END $$;
DO $$ DECLARE v text; BEGIN
  v := public.premise_time_zone_as_of('00000000-0000-4000-8000-0000000016d3', DATE '2026-06-01');
  RAISE EXCEPTION 'FAIL L3: a ZZ premise given the time zone %', v;
EXCEPTION WHEN no_data_found THEN
  RAISE NOTICE 'PASS L3: with no time zone recorded the lookup refuses, never assumes Chicago'; END $$;
DO $$ DECLARE n_reg int; n_tax int; v_city text; BEGIN
  -- On 2026-02-01 L2 is in Austin for rates (ordinance 2025-12-15) but still
  -- Round Rock's for tax (until the quarter, 2026-04-01).
  SELECT count(*) INTO n_reg FROM public.premise_places_as_of('00000000-0000-4000-8000-0000000016d2', DATE '2026-02-01', 'regulatory') WHERE place_id = pg_temp.id('austin');
  SELECT place_code INTO v_city FROM public.premise_places_as_of('00000000-0000-4000-8000-0000000016d2', DATE '2026-02-01', 'tax') WHERE kind_code = 'municipality';
  SELECT count(*) INTO n_tax FROM public.premise_places_as_of('00000000-0000-4000-8000-0000000016d2', DATE '2026-05-01', 'tax') WHERE kind_code IN ('municipality', 'special_purpose_district', 'state');
  IF n_reg <> 1 OR v_city <> 'ROUNDROCK' OR n_tax <> 4 THEN
    RAISE EXCEPTION 'FAIL L4: places as of: reg % city % tax-count %', n_reg, v_city, n_tax;
  END IF;
  RAISE NOTICE 'PASS L4: a premise''s places are read per axis on a date — Austin for rates from the ordinance, Round Rock for tax until the quarter; then Austin, two districts and the state';
END $$;
RESET ROLE;


-- ============================================================ C. a place's close floor
-- Owner. Each close below is refused by exactly one citation in force past it.
DO $$ BEGIN
  UPDATE public.places SET effective_to = DATE '2027-01-01' WHERE id = pg_temp.id('travis');
  RAISE EXCEPTION 'FAIL C1: a county closed under a membership still open';
EXCEPTION WHEN restrict_violation THEN
  RAISE NOTICE 'PASS C1: a place does not close while a premise''s membership in it runs past the close'; END $$;
DO $$ BEGIN
  UPDATE public.places SET effective_to = DATE '2027-01-01' WHERE id = pg_temp.id('elpaso_cty');
  RAISE EXCEPTION 'FAIL C1b: El Paso County closed under its membership';
EXCEPTION WHEN restrict_violation THEN NULL; END $$;
DO $$ BEGIN
  -- ZZ city: only a profile cites it.
  INSERT INTO public.utility_service_profiles (tenant_id, service_type, state_code, owner_type, commission_jurisdiction,
                                               owning_place_id, effective_from, evidence_reference)
  VALUES ('00000000-0000-4000-8000-0000000016a1', 'gas', 'ZZ', 'municipal', false, pg_temp.id('zcity'), DATE '2020-01-01', 'ZZ charter');
  UPDATE public.places SET effective_to = DATE '2027-01-01' WHERE id = pg_temp.id('zcity');
  RAISE EXCEPTION 'FAIL C2: a city closed under the profile it owns';
EXCEPTION WHEN restrict_violation THEN
  RAISE NOTICE 'PASS C2: a place does not close while a utility it owns has a profile running past the close'; END $$;
DO $$ BEGIN
  -- Austin: no membership past 2030? It has open ones; use ESD1, cited by an
  -- open tax membership — close that first, leaving only its closed fact.
  UPDATE public.premise_place_memberships SET valid_to = DATE '2029-01-01' WHERE place_id = pg_temp.id('esd1');
  INSERT INTO public.place_facts (place_id, fact_code, value, effective_from, source_note)
  VALUES (pg_temp.id('esd1'), 'special_district_type', '"emergency_services"', DATE '2000-01-01', 'Comptroller');
  UPDATE public.places SET effective_to = DATE '2029-06-01' WHERE id = pg_temp.id('esd1');
  RAISE EXCEPTION 'FAIL C3: a district closed under its own fact';
EXCEPTION WHEN restrict_violation THEN
  RAISE NOTICE 'PASS C3: a place does not close while a fact about it runs past the close'; END $$;
DO $$ BEGIN
  -- Round Rock: its only membership closed 2026-04-01; a child keeps it open.
  PERFORM pg_temp.place('rrdist', 'special_purpose_district', 'TX', 'RRDIST', 'roundrock', DATE '2010-01-01');
  UPDATE public.places SET effective_to = DATE '2027-01-01' WHERE id = pg_temp.id('roundrock');
  RAISE EXCEPTION 'FAIL C4: a city closed under its open child district';
EXCEPTION WHEN restrict_violation THEN
  RAISE NOTICE 'PASS C4: a place does not close while a child place runs past the close'; END $$;
DO $$ DECLARE r record; BEGIN
  UPDATE public.places SET effective_to = DATE '2027-01-01' WHERE id = pg_temp.id('roundrock');
  SELECT closed_at, closed_by INTO r FROM public.places WHERE id = pg_temp.id('roundrock');
  IF r.closed_at IS NULL OR r.closed_by IS NULL THEN RAISE EXCEPTION 'FAIL C5: the close was not stamped'; END IF;
  BEGIN
    UPDATE public.places SET effective_to = DATE '2028-01-01' WHERE id = pg_temp.id('roundrock');
    RAISE EXCEPTION 'FAIL C5: closed twice';
  EXCEPTION WHEN restrict_violation THEN NULL; END;
  RAISE NOTICE 'PASS C5: with nothing in force past it, a place closes once, stamped';
END $$;


-- ============================================================ G. jurisdictions, tenancy
SET LOCAL app.user_id = '00000000-0000-4000-8000-0000000016b1';
SET ROLE tally_app;
DO $$ BEGIN
  INSERT INTO public.jurisdictions (tenant_id, jurisdiction_code, jurisdiction_name, place_id)
  VALUES ('00000000-0000-4000-8000-0000000016a1', 'ELP', 'El Paso', pg_temp.id('elpaso'));
  INSERT INTO public.jurisdictions (tenant_id, jurisdiction_code, jurisdiction_name)
  VALUES ('00000000-0000-4000-8000-0000000016a1', 'FR-EAST', 'East franchise area');
  RAISE NOTICE 'PASS G1: a utility''s jurisdiction points at a shared place when it is one, and need not when it is not';
END $$;
RESET ROLE;
SET LOCAL app.user_id = '00000000-0000-4000-8000-0000000016b2';
SET ROLE tally_app;
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM public.premise_place_memberships) OR EXISTS (SELECT 1 FROM public.utility_service_profiles) THEN
    RAISE EXCEPTION 'FAIL G2: T2 sees T1''s memberships or profiles';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.places WHERE id = pg_temp.id('austin')) THEN
    RAISE EXCEPTION 'FAIL G2: T2 cannot see the shared places';
  END IF;
  RAISE NOTICE 'PASS G2: another utility sees the shared places but none of T1''s memberships or profiles';
END $$;
DO $$ BEGIN
  INSERT INTO public.premise_place_memberships (tenant_id, service_location_id, place_id, axis, place_kind, single_per_premise,
                                                valid_from, evidence_kind, evidence_reference)
  VALUES ('00000000-0000-4000-8000-0000000016a2', '00000000-0000-4000-8000-0000000016d2', pg_temp.id('austin'), 'tax', 'x', true,
          DATE '2026-01-01', 'ordinance', 'x');
  RAISE EXCEPTION 'FAIL G3: T2 recorded a membership for T1''s premise';
EXCEPTION WHEN foreign_key_violation OR insufficient_privilege THEN
  RAISE NOTICE 'PASS G3: a utility records memberships only for its own premises'; END $$;
RESET ROLE;
-- The premise's state is read as v5.4.2-12 reads it (upper(btrim())): a
-- padded lower-case 'tx' is Texas; 'Texas' is no known state, so lookups refuse.
INSERT INTO public.service_locations (id, tenant_id, customer_id, location_number, address_line1, city, state, zip) VALUES
  ('00000000-0000-4000-8000-0000000016d5', '00000000-0000-4000-8000-0000000016a1', '00000000-0000-4000-8000-0000000016c1', 'L5', '5 Main', 'Austin', ' tx ', '78705'),
  ('00000000-0000-4000-8000-0000000016d6', '00000000-0000-4000-8000-0000000016a1', '00000000-0000-4000-8000-0000000016c1', 'L6', '6 Main', 'Austin', 'Texas', '78706');
DO $$ DECLARE v text; BEGIN
  PERFORM set_config('app.user_id', '00000000-0000-4000-8000-0000000016b1', true);
  PERFORM pg_temp.mem('00000000-0000-4000-8000-0000000016d5', pg_temp.id('travis'), 'regulatory', DATE '2020-01-01');
  v := public.premise_time_zone_as_of('00000000-0000-4000-8000-0000000016d5', DATE '2026-06-01');
  IF v <> 'America/Chicago' THEN RAISE EXCEPTION 'FAIL G4a: a padded " tx " premise reads %', v; END IF;
  BEGIN
    v := public.premise_time_zone_as_of('00000000-0000-4000-8000-0000000016d6', DATE '2026-06-01');
    RAISE EXCEPTION 'FAIL G4b: a "Texas" premise given the time zone %', v;
  EXCEPTION WHEN no_data_found THEN NULL; END;
  RAISE NOTICE 'PASS G4: a premise''s state is read normalised, as -12 reads it (" tx " is Texas); an unrecognised state resolves nothing, so the lookup refuses';
END $$;
DO $$ BEGIN
  DELETE FROM public.premise_place_memberships WHERE place_id = pg_temp.id('travis');
  RAISE EXCEPTION 'FAIL G6a: the owner deleted a membership';
EXCEPTION WHEN restrict_violation THEN NULL; END $$;
DO $$ BEGIN
  DELETE FROM public.utility_service_profiles WHERE tenant_id = '00000000-0000-4000-8000-0000000016a1';
  RAISE EXCEPTION 'FAIL G6b: the owner deleted a profile';
EXCEPTION WHEN restrict_violation THEN
  RAISE NOTICE 'PASS G6: memberships and profiles are never deleted, by the owner either'; END $$;
DO $$ BEGIN
  PERFORM public.assert_tenant_isolation_invariants();
  RAISE NOTICE 'PASS G5: tenant isolation holds over the new tables (AC-32)';
END $$;

ROLLBACK;
