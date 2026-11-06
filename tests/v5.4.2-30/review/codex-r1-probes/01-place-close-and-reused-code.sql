-- Author-run only. Run as owner on a fresh clone of tally with frozen r1 applied.
-- Revoke clone TEMP from PUBLIC, tally_app, tally_core as in the brief.
-- No role creation/alteration; all fixture changes roll back.
BEGIN;

CREATE FUNCTION pg_temp.refuses_at(p_label text, p_sql text, p_state text, p_guard text) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE v_con text;
BEGIN
  BEGIN
    EXECUTE p_sql;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'caught SQLSTATE=% message=%', SQLSTATE, SQLERRM;
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
    RAISE NOTICE 'caught SQLSTATE=% message=%', SQLSTATE, SQLERRM;
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
    RAISE NOTICE 'caught SQLSTATE=% message=%', SQLSTATE, SQLERRM;
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

-- ---------------------------------------------------------------------------

SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000030b1', true);
DO $$
DECLARE n integer; covered boolean;
BEGIN
  EXECUTE pg_temp.levy_sql('00000000-0000-4000-8000-0000000030f9',
    '00000000-0000-4000-8000-0000000030a1', 'TX', 'county', '48996', 'sales_tax',
    DATE '2026-01-01', NULL,
    '{"rate_percent":1,"stacking_position":2,"computed_on":[],"source_kind":"ordinance","citation":"probe 1","reaches_residential":true}');
  BEGIN
    UPDATE public.places SET effective_to = DATE '2026-07-01'
      WHERE id = '00000000-0000-4000-8000-0000000030e3';
    RAISE NOTICE 'B1: place close accepted with an open levy';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'B1 close caught SQLSTATE=% message=%', SQLSTATE, SQLERRM;
    RETURN;
  END;
  SELECT count(*) INTO n FROM public.tax_levy_as_of(
    '00000000-0000-4000-8000-0000000030a1', 'TX', 'county', '48996', 'sales_tax',
    'gas', 'distribution', DATE '2026-08-01', now());
  SELECT coalesce(range_agg(daterange(effective_from,effective_to,'[)')) @>
    daterange(DATE '2026-01-01',NULL,'[)'), false) INTO covered
    FROM public.places WHERE state_code='TX' AND kind_code='county' AND place_code='48996';
  RAISE NOTICE 'B1: August levy rows=%; full coverage=% (predicted 1, false)', n, covered;
  INSERT INTO public.places(kind_code,state_code,place_code,name,parent_place_id,effective_from,source_note)
    SELECT 'county','TX','48996','Different county using released code',id,DATE '2026-07-01','probe reused code'
    FROM b30 WHERE k='tx';
  SELECT count(*) INTO n FROM public.tax_levy_as_of(
    '00000000-0000-4000-8000-0000000030a1', 'TX', 'county', '48996', 'sales_tax',
    'gas', 'distribution', DATE '2026-08-01', now());
  RAISE NOTICE 'S3: levy rows after differently named successor=%; schema has no continuity assertion', n;
  PERFORM set_config('app.user_id','00000000-0000-4000-8000-0000000030b2',true);
  EXECUTE pg_temp.levy_sql(NULL,
    '00000000-0000-4000-8000-0000000030a2', 'TX', 'county', '48996', 'sales_tax',
    DATE '2026-01-01', NULL,
    '{"rate_percent":1,"stacking_position":2,"computed_on":[],"source_kind":"ordinance","citation":"probe reused code","reaches_residential":true}');
  RAISE NOTICE 'S3: new levy spanning both differently named place rows accepted';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'probe setup/read caught SQLSTATE=% message=%', SQLSTATE, SQLERRM;
END $$;
ROLLBACK;
