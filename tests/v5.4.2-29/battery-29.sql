-- ============================================================================
-- BATTERY v5.4.2-29 — every Texas county and its time zone (2026-11-04)
-- Run: psql -U tally -d <db-with-patch> -v ON_ERROR_STOP=1 -f battery-29.sql
-- One transaction, rolled back. Fixtures as the owner; the lookups the
-- application meets are run as tally_app. ok() treats NULL as a fail;
-- refuses_at() needs the SQLSTATE and a fragment of the guard's message.
--
--   C  the load: exactly the Census list (codes and names, by hash), each
--      county open, under Texas, in force from 1900, with one time_zone fact
--      in force across the whole range; Mountain exactly at El Paso and
--      Hudspeth; Culberson Central (the law, not local practice); the two
--      seeded rows kept, not duplicated; the citations; tally_app reads them
--      and cannot write them.
--   Z  what it changes: a premise in a county -16 never seeded (Harris,
--      Culberson) now has a zone; the state-agency fee check judges it
--      (admitted where the account was not yet a state agency at the end of
--      the period in Central time, refused where it was); a premise with no
--      county recorded is still refused (known limit L1).
--
-- The fixture's fact that matters (as in battery -28): customer C1 became a
-- state agency at 2026-07-01 05:30 UTC: 00:30 July 1 Central (after the end
-- of June 30), 23:30 June 30 Mountain (before it). C2 became one on
-- 2026-06-15, a state agency at the end of June in every zone.
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
-- zone_is(): the premise lookup answers p_zone; a refusal is a labelled FAIL.
CREATE FUNCTION pg_temp.zone_is(p_label text, p_loc uuid, p_zone text) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE v text;
BEGIN
  BEGIN
    v := public.premise_time_zone_as_of(p_loc, DATE '2026-06-30');
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'FAIL %: refused with % (%)', p_label, SQLSTATE, SQLERRM;
  END;
  IF v IS DISTINCT FROM p_zone THEN RAISE EXCEPTION 'FAIL %: % (expected %)', p_label, v, p_zone; END IF;
  RAISE NOTICE 'PASS %', p_label;
END $$;
GRANT EXECUTE ON FUNCTION pg_temp.refuses_at(text, text, text, text), pg_temp.ok(text, boolean), pg_temp.admits(text, text),
                          pg_temp.zone_is(text, uuid, text) TO tally_app;

-- ================================================================ C. the load
-- tx(): Texas's open counties.
CREATE TEMP VIEW tx_counties AS
  SELECT p.* FROM public.places p
   WHERE p.kind_code = 'county' AND p.state_code = 'TX' AND p.effective_to IS NULL;
GRANT SELECT ON tx_counties TO tally_app;

SELECT pg_temp.ok('C1 Texas has 254 open counties',
  (SELECT count(*) FROM tx_counties) = 254);
-- The hash of "code|name" lines in code order, computed from
-- application/places-sources/census-st48_tx_cou2020.txt (md5
-- e1ea7280eb41b680feb924b3bef2c411): the codes and names are the Census's.
SELECT pg_temp.ok('C1b the codes and names are exactly the Census list',
  (SELECT md5(string_agg(place_code || '|' || name, E'\n' ORDER BY place_code)) FROM tx_counties) = '5094ab8b28e6ad29990118f886535842');
SELECT pg_temp.ok('C1c every code is an odd number from 48001 to 48507',
  NOT EXISTS (SELECT 1 FROM tx_counties WHERE place_code !~ '^48[0-9]{3}$' OR substr(place_code, 3)::int % 2 = 0
                                            OR substr(place_code, 3)::int NOT BETWEEN 1 AND 507));
SELECT pg_temp.ok('C2 every county sits under Texas, in force from 1900-01-01',
  NOT EXISTS (SELECT 1 FROM tx_counties c
               WHERE c.effective_from <> DATE '1900-01-01'
                  OR c.parent_place_id IS DISTINCT FROM (SELECT id FROM public.places WHERE kind_code = 'state' AND place_code = 'TX' AND effective_to IS NULL)));
SELECT pg_temp.ok('C2b every county carries exactly one time_zone fact, open, from 1900-01-01',
  NOT EXISTS (SELECT 1 FROM tx_counties c
               WHERE (SELECT count(*) FROM public.place_facts f WHERE f.place_id = c.id AND f.fact_code = 'time_zone') <> 1
                  OR NOT EXISTS (SELECT 1 FROM public.place_facts f WHERE f.place_id = c.id AND f.fact_code = 'time_zone'
                                    AND f.effective_to IS NULL AND f.effective_from = DATE '1900-01-01')));
SELECT pg_temp.ok('C3 Mountain time exactly at El Paso (48141) and Hudspeth (48229)',
  (SELECT array_agg(c.place_code ORDER BY c.place_code) FROM tx_counties c
     JOIN public.place_facts f ON f.place_id = c.id AND f.fact_code = 'time_zone'
    WHERE f.value <> '"America/Chicago"') = ARRAY['48141', '48229']
  AND (SELECT bool_and(f.value = '"America/Denver"') FROM tx_counties c
         JOIN public.place_facts f ON f.place_id = c.id AND f.fact_code = 'time_zone'
        WHERE c.place_code IN ('48141', '48229')));
SELECT pg_temp.ok('C3b Culberson (48109), east of Hudspeth''s east line, is Central by law',
  (SELECT f.value FROM tx_counties c JOIN public.place_facts f ON f.place_id = c.id AND f.fact_code = 'time_zone'
    WHERE c.place_code = '48109') = '"America/Chicago"');
SELECT pg_temp.ok('C4 El Paso and Hudspeth are -16''s seeded rows, one each, unchanged',
  (SELECT count(*) FROM public.places WHERE kind_code = 'county' AND state_code = 'TX' AND place_code IN ('48141', '48229')) = 2
  AND (SELECT bool_and(source_note = 'Texas county (FIPS ' || place_code || ').') FROM tx_counties WHERE place_code IN ('48141', '48229')));
SELECT pg_temp.ok('C5 the 252 loaded counties cite the Census file, their facts 49 CFR 71.7(e)',
  (SELECT count(*) FROM tx_counties c
     JOIN public.place_facts f ON f.place_id = c.id AND f.fact_code = 'time_zone'
    WHERE strpos(c.source_note, 'st48_tx_cou2020.txt') > 0 AND strpos(c.source_note, c.place_code) > 0
      AND strpos(f.source_note, '49 CFR 71.7(e)') > 0) = 252);

SET ROLE tally_app;
SELECT pg_temp.ok('C6 the application reads all 254 and their zones',
  (SELECT count(*) FROM tx_counties c JOIN public.place_facts f ON f.place_id = c.id AND f.fact_code = 'time_zone') = 254);
SELECT pg_temp.refuses_at('C6b the application cannot write a county',
  $q$INSERT INTO public.places (kind_code, state_code, place_code, name, parent_place_id, effective_from, source_note)
     SELECT 'county', 'TX', '48990', 'X', id, DATE '1900-01-01', 'x' FROM public.places WHERE kind_code = 'state' AND place_code = 'TX'$q$,
  '42501', 'permission denied');
SELECT pg_temp.refuses_at('C6c the application cannot close one',
  $q$UPDATE public.places SET effective_to = DATE '2026-01-01' WHERE kind_code = 'county' AND place_code = '48201'$q$,
  '42501', 'permission denied');
RESET ROLE;

-- ================================================================ fixtures
INSERT INTO public.tenants (id, name, slug) VALUES
  ('00000000-0000-4000-8000-0000000029a1', 'T1 City Gas', 'bat29-t1');
INSERT INTO public.users (id, tenant_id, display_name, email, role) VALUES
  ('00000000-0000-4000-8000-0000000029b1', '00000000-0000-4000-8000-0000000029a1', 'Op1', 'op1@bat29.test', 'operator');
INSERT INTO public.customers (id, tenant_id, customer_number, customer_type, is_state_agency) VALUES
  ('00000000-0000-4000-8000-0000000029c1', '00000000-0000-4000-8000-0000000029a1', 'B29-C1', 'government', false),
  ('00000000-0000-4000-8000-0000000029c2', '00000000-0000-4000-8000-0000000029a1', 'B29-C2', 'government', false);
INSERT INTO public.customer_attribute_history (tenant_id, customer_id, attribute, old_value, new_value, effective_at, source) VALUES
  ('00000000-0000-4000-8000-0000000029a1', '00000000-0000-4000-8000-0000000029c1', 'is_state_agency', NULL, 'false', TIMESTAMPTZ '2020-01-01 00:00+00', 'backfill'),
  ('00000000-0000-4000-8000-0000000029a1', '00000000-0000-4000-8000-0000000029c1', 'is_state_agency', 'false', 'true', TIMESTAMPTZ '2026-07-01 05:30+00', 'operator'),
  ('00000000-0000-4000-8000-0000000029a1', '00000000-0000-4000-8000-0000000029c2', 'is_state_agency', NULL, 'false', TIMESTAMPTZ '2020-01-01 00:00+00', 'backfill'),
  ('00000000-0000-4000-8000-0000000029a1', '00000000-0000-4000-8000-0000000029c2', 'is_state_agency', 'false', 'true', TIMESTAMPTZ '2026-06-15 00:00+00', 'operator');
-- Premises of C1: D1 Houston (Harris), D2 Van Horn (Culberson), D3 El Paso,
-- D4 with no county recorded. D5: C2's, in Houston.
INSERT INTO public.service_locations (id, tenant_id, customer_id, location_number, address_line1, city, state, zip) VALUES
  ('00000000-0000-4000-8000-0000000029d1', '00000000-0000-4000-8000-0000000029a1', '00000000-0000-4000-8000-0000000029c1', 'L1', '1 Main', 'Houston', 'TX', '77002'),
  ('00000000-0000-4000-8000-0000000029d2', '00000000-0000-4000-8000-0000000029a1', '00000000-0000-4000-8000-0000000029c1', 'L2', '2 Main', 'Van Horn', 'TX', '79855'),
  ('00000000-0000-4000-8000-0000000029d3', '00000000-0000-4000-8000-0000000029a1', '00000000-0000-4000-8000-0000000029c1', 'L3', '3 Main', 'El Paso', 'TX', '79901'),
  ('00000000-0000-4000-8000-0000000029d4', '00000000-0000-4000-8000-0000000029a1', '00000000-0000-4000-8000-0000000029c1', 'L4', '4 Main', 'Somewhere', 'TX', '76000'),
  ('00000000-0000-4000-8000-0000000029d5', '00000000-0000-4000-8000-0000000029a1', '00000000-0000-4000-8000-0000000029c2', 'L5', '5 Main', 'Houston', 'TX', '77002');
INSERT INTO public.meters (id, tenant_id, meter_number, location_id, service_type) VALUES
  ('00000000-0000-4000-8000-0000000029f1', '00000000-0000-4000-8000-0000000029a1', 'M1', '00000000-0000-4000-8000-0000000029d1', 'gas'),
  ('00000000-0000-4000-8000-0000000029f2', '00000000-0000-4000-8000-0000000029a1', 'M2', '00000000-0000-4000-8000-0000000029d2', 'gas'),
  ('00000000-0000-4000-8000-0000000029f3', '00000000-0000-4000-8000-0000000029a1', 'M3', '00000000-0000-4000-8000-0000000029d3', 'gas'),
  ('00000000-0000-4000-8000-0000000029f4', '00000000-0000-4000-8000-0000000029a1', 'M4', '00000000-0000-4000-8000-0000000029d4', 'gas'),
  ('00000000-0000-4000-8000-0000000029f5', '00000000-0000-4000-8000-0000000029a1', 'M5', '00000000-0000-4000-8000-0000000029d5', 'gas');
-- Memberships: the utility records each premise's county (its data), here
-- pointing at the counties -29 loaded.
DO $$
DECLARE m record;
BEGIN
  FOR m IN SELECT * FROM (VALUES
      ('00000000-0000-4000-8000-0000000029d1'::uuid, '48201'),
      ('00000000-0000-4000-8000-0000000029d2', '48109'),
      ('00000000-0000-4000-8000-0000000029d3', '48141'),
      ('00000000-0000-4000-8000-0000000029d5', '48201')) v(loc, fips) LOOP
    INSERT INTO public.premise_place_memberships (tenant_id, service_location_id, place_id, axis, place_kind,
                                                  valid_from, evidence_kind, evidence_reference, evidence_date)
    VALUES ('00000000-0000-4000-8000-0000000029a1', m.loc,
            (SELECT id FROM public.places WHERE kind_code = 'county' AND state_code = 'TX' AND place_code = m.fips AND effective_to IS NULL),
            'regulatory', 'state', DATE '2020-01-01', 'ordinance', 'battery 29', DATE '2019-12-01');
  END LOOP;
END $$;

-- The pipeline safety fee rider, as in battery -28.
INSERT INTO public.rate_items (id, tenant_id, item_code) VALUES
  ('00000000-0000-4000-8000-0000000029e1', '00000000-0000-4000-8000-0000000029a1', 'PSF');
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000029b1', true);
SELECT public.assert_reference_version('rate_items', '00000000-0000-4000-8000-0000000029e1', 1);
INSERT INTO public.rate_item_versions (tenant_id, rate_item_id, item_name, service_type, calculation_type, regulatory_class, effective_date, change_type) VALUES
  ('00000000-0000-4000-8000-0000000029a1', '00000000-0000-4000-8000-0000000029e1', 'PSF', 'gas', 'fixed_monthly', 'regulated', DATE '2020-01-01', 'initial');
INSERT INTO public.regulatory_surcharge_rules (tenant_id, rate_item_id, surcharge_kind, cycle_start, cycle_end, cap_per_service, excluded_from_tax_bases, exempts_state_agencies) VALUES
  ('00000000-0000-4000-8000-0000000029a1', '00000000-0000-4000-8000-0000000029e1', 'pipeline_safety_fee', DATE '2026-01-01', DATE '2026-12-31', 50, true, true);

-- inv(): a June bill n of customer c at premise loc.
CREATE FUNCTION pg_temp.inv(p_n int, p_cust int, p_loc int) RETURNS void LANGUAGE sql AS $$
  INSERT INTO public.invoices (id, tenant_id, invoice_number, customer_id, location_id, is_consolidated, parent_invoice_id, is_consolidated_child, status,
                               invoice_date, billing_period, period_start, period_end, due_date, amount_due)
  VALUES (('00000000-0000-4000-8000-0000000299' || lpad(p_n::text, 2, '0'))::uuid, '00000000-0000-4000-8000-0000000029a1', 'B29-' || p_n,
          ('00000000-0000-4000-8000-0000000029c' || p_cust)::uuid, ('00000000-0000-4000-8000-0000000029d' || p_loc)::uuid, false, NULL, false, 'draft',
          DATE '2026-07-02', '2026-06', DATE '2026-06-01', DATE '2026-06-30', DATE '2026-07-20', 1.00);
$$;
-- psf(): the SQL of one fee line on bill n, meter m (regulatory_class named
-- only where a pending money patch has added it).
CREATE FUNCTION pg_temp.psf(p_n int, p_meter int, p_amount numeric) RETURNS text LANGUAGE sql AS $$
  SELECT format($f$INSERT INTO public.invoice_line_items (tenant_id, invoice_id, line_order, service_type, charge_type, description, amount, rate_item_id, meter_id, is_taxable%s)
    VALUES ('00000000-0000-4000-8000-0000000029a1', %L, (SELECT coalesce(max(line_order) + 1, 0) FROM public.invoice_line_items WHERE invoice_id = %L),
            'gas', 'surcharge', 'PSF', %s, '00000000-0000-4000-8000-0000000029e1', %L, false%s)$f$,
    CASE WHEN c.present THEN ', regulatory_class' ELSE '' END,
    '00000000-0000-4000-8000-0000000299' || lpad(p_n::text, 2, '0'), '00000000-0000-4000-8000-0000000299' || lpad(p_n::text, 2, '0'),
    p_amount, '00000000-0000-4000-8000-0000000029f' || p_meter,
    CASE WHEN c.present THEN ', ''regulated''' ELSE '' END)
  FROM (SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'invoice_line_items'
                                                                 AND column_name = 'regulatory_class') AS present) c
$$;
GRANT EXECUTE ON FUNCTION pg_temp.psf(int, int, numeric) TO tally_app;

SELECT pg_temp.inv(1, 1, 1);   -- C1, Houston
SELECT pg_temp.inv(2, 1, 2);   -- C1, Van Horn
SELECT pg_temp.inv(3, 1, 3);   -- C1, El Paso
SELECT pg_temp.inv(4, 1, 4);   -- C1, no county
SELECT pg_temp.inv(5, 2, 5);   -- C2, Houston

-- ============================================================ Z. what it changes
SET ROLE tally_app;
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000029b1', true);
SELECT pg_temp.zone_is('Z1 a Houston premise (Harris, not seeded by -16) reads Central',
  '00000000-0000-4000-8000-0000000029d1', 'America/Chicago');
SELECT pg_temp.zone_is('Z1b a Van Horn premise (Culberson) reads Central, the legal zone',
  '00000000-0000-4000-8000-0000000029d2', 'America/Chicago');
SELECT pg_temp.zone_is('Z1c an El Paso premise still reads Mountain',
  '00000000-0000-4000-8000-0000000029d3', 'America/Denver');
SELECT pg_temp.refuses_at('Z1d a premise with no county recorded is still refused (L1)',
  $q$SELECT public.premise_time_zone_as_of('00000000-0000-4000-8000-0000000029d4', DATE '2026-06-30')$q$, 'P0002', 'no time zone can be read');
SELECT pg_temp.ok('Z1e the bill-level lookup agrees for Houston',
  public.invoice_time_zone_as_of('00000000-0000-4000-8000-000000029901', DATE '2026-06-30') = 'America/Chicago');

SELECT pg_temp.admits('Z2 Houston: not yet a state agency at the end of June in Central time, the fee stands (it was refused before -29)',
  pg_temp.psf(1, 1, 1.00));
SELECT pg_temp.admits('Z2b Van Horn: judged in Central, the fee stands (Mountain would refuse it)',
  pg_temp.psf(2, 2, 1.00));
SELECT pg_temp.refuses_at('Z2c El Paso: judged in Mountain, a state agency''s bill, the fee is refused',
  pg_temp.psf(3, 3, 1.00), '23514', 'was a state agency at the end of the billed period');
SELECT pg_temp.refuses_at('Z2d Houston, C2 (a state agency since June 15): the fee is refused, so the check runs on the loaded county',
  pg_temp.psf(5, 5, 1.00), '23514', 'was a state agency at the end of the billed period');
SELECT pg_temp.refuses_at('Z2e no county recorded: the fee refuses, never assumes Central (L1)',
  pg_temp.psf(4, 4, 1.00), 'P0002', 'no time zone can be read');
RESET ROLE;

DO $$ BEGIN RAISE NOTICE 'battery-29: all checks passed'; END $$;
ROLLBACK;
