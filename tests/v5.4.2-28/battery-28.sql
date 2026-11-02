-- ============================================================================
-- BATTERY v5.4.2-28 — rates small fixes (2026-11-02)
-- Run: psql -U tally -d <db-with-patch> -v ON_ERROR_STOP=1 -f battery-28.sql
-- One transaction, rolled back. Fixtures as the owner; the guard the
-- application meets is exercised as tally_app too. refuses_at() requires the
-- named SQLSTATE AND a fragment of the named guard's message, so a test cannot
-- pass on another guard that shares the SQLSTATE. ok() treats NULL as a fail.
--
--   Z  the state-agency check reads the bill's premise's time zone (CI-010;
--      Ryan 2026-11-02, option 1): one premise, a consolidated parent's
--      children (agree / disagree / none / void excluded / nested), the
--      refusal when no zone can be read, no lookup for a 0.00 line, the old
--      Chicago signature gone, no zone constant left in any function.
--
-- The fixture's one fact that matters: customer C1 became a state agency at
-- 2026-07-01 05:30 UTC. That is 00:30 on July 1 in Central time (after the
-- end of June 30) and 23:30 on June 30 in Mountain time (before it). So a
-- June bill is a state agency's bill in El Paso and not one in Austin.
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
GRANT EXECUTE ON FUNCTION pg_temp.refuses_at(text, text, text, text), pg_temp.ok(text, boolean), pg_temp.admits(text, text) TO tally_app;

-- ================================================================= fixtures
INSERT INTO public.tenants (id, name, slug) VALUES
  ('00000000-0000-4000-8000-0000000028a1', 'T1 City Gas', 'bat28-t1');
INSERT INTO public.users (id, tenant_id, display_name, email, role) VALUES
  ('00000000-0000-4000-8000-0000000028b1', '00000000-0000-4000-8000-0000000028a1', 'Op1', 'op1@bat28.test', 'operator');
-- C1: a government account, not a state agency from 2020, one from
-- 2026-07-01 05:30 UTC (the owner writes the history row; the application
-- cannot, -07's enforce_event_written_by_db).
-- (The database stamps the account's initial row at now(), so the 2020 row
-- is the owner's too.)
INSERT INTO public.customers (id, tenant_id, customer_number, customer_type, is_state_agency) VALUES
  ('00000000-0000-4000-8000-0000000028c1', '00000000-0000-4000-8000-0000000028a1', 'B28-C1', 'government', false);
INSERT INTO public.customer_attribute_history (tenant_id, customer_id, attribute, old_value, new_value, effective_at, source) VALUES
  ('00000000-0000-4000-8000-0000000028a1', '00000000-0000-4000-8000-0000000028c1', 'is_state_agency', NULL, 'false', TIMESTAMPTZ '2020-01-01 00:00+00', 'backfill'),
  ('00000000-0000-4000-8000-0000000028a1', '00000000-0000-4000-8000-0000000028c1', 'is_state_agency', 'false', 'true', TIMESTAMPTZ '2026-07-01 05:30+00', 'operator');
-- Premises: D1 El Paso (Mountain), D2 Austin (Central), D3 Hudspeth
-- (Mountain), D4 with no county (its state comes from its address, and
-- Texas is not in one zone: unknown).
INSERT INTO public.service_locations (id, tenant_id, customer_id, location_number, address_line1, city, state, zip) VALUES
  ('00000000-0000-4000-8000-0000000028d1', '00000000-0000-4000-8000-0000000028a1', '00000000-0000-4000-8000-0000000028c1', 'L1', '1 Main', 'El Paso', 'TX', '79901'),
  ('00000000-0000-4000-8000-0000000028d2', '00000000-0000-4000-8000-0000000028a1', '00000000-0000-4000-8000-0000000028c1', 'L2', '2 Main', 'Austin', 'TX', '78701'),
  ('00000000-0000-4000-8000-0000000028d3', '00000000-0000-4000-8000-0000000028a1', '00000000-0000-4000-8000-0000000028c1', 'L3', '3 Main', 'Sierra Blanca', 'TX', '79851'),
  ('00000000-0000-4000-8000-0000000028d4', '00000000-0000-4000-8000-0000000028a1', '00000000-0000-4000-8000-0000000028c1', 'L4', '4 Main', 'Somewhere', 'TX', '76000');
INSERT INTO public.meters (id, tenant_id, meter_number, location_id, service_type) VALUES
  ('00000000-0000-4000-8000-0000000028f1', '00000000-0000-4000-8000-0000000028a1', 'M1', '00000000-0000-4000-8000-0000000028d1', 'gas'),
  ('00000000-0000-4000-8000-0000000028f2', '00000000-0000-4000-8000-0000000028a1', 'M2', '00000000-0000-4000-8000-0000000028d2', 'gas'),
  ('00000000-0000-4000-8000-0000000028f3', '00000000-0000-4000-8000-0000000028a1', 'M3', '00000000-0000-4000-8000-0000000028d3', 'gas'),
  ('00000000-0000-4000-8000-0000000028f4', '00000000-0000-4000-8000-0000000028a1', 'M4', '00000000-0000-4000-8000-0000000028d4', 'gas');

-- Places: Texas, El Paso and Hudspeth counties are seeded (-16); Travis is
-- loaded here with its zone, as a platform place.
CREATE TEMP TABLE b28 (k text PRIMARY KEY, id uuid);
INSERT INTO b28 SELECT 'tx', id FROM public.places WHERE kind_code = 'state' AND place_code = 'TX';
INSERT INTO b28 SELECT 'elpaso', id FROM public.places WHERE kind_code = 'county' AND place_code = '48141';
INSERT INTO b28 SELECT 'hudspeth', id FROM public.places WHERE kind_code = 'county' AND place_code = '48229';
WITH p AS (
  INSERT INTO public.places (kind_code, state_code, place_code, name, parent_place_id, effective_from, source_note)
  VALUES ('county', 'TX', '48453', 'Travis County', (SELECT id FROM b28 WHERE k = 'tx'), DATE '1900-01-01', 'battery 28 fixture')
  RETURNING id)
INSERT INTO b28 SELECT 'travis', id FROM p;
INSERT INTO public.place_facts (place_id, fact_code, value, effective_from, source_note)
  VALUES ((SELECT id FROM b28 WHERE k = 'travis'), 'time_zone', '"America/Chicago"', DATE '1900-01-01', '49 CFR 71.7 (battery 28)');
DO $$
DECLARE m record;
BEGIN
  IF (SELECT count(*) FROM b28) <> 4 THEN RAISE EXCEPTION 'SETUP: seeded places missing'; END IF;
  FOR m IN SELECT * FROM (VALUES
      ('00000000-0000-4000-8000-0000000028d1'::uuid, 'elpaso'),
      ('00000000-0000-4000-8000-0000000028d2', 'travis'),
      ('00000000-0000-4000-8000-0000000028d3', 'hudspeth')) v(loc, place) LOOP
    INSERT INTO public.premise_place_memberships (tenant_id, service_location_id, place_id, axis, place_kind,
                                                  valid_from, evidence_kind, evidence_reference, evidence_date)
    VALUES ('00000000-0000-4000-8000-0000000028a1', m.loc, (SELECT id FROM b28 WHERE k = m.place), 'regulatory', 'state',
            DATE '2020-01-01', 'ordinance', 'battery 28', DATE '2019-12-01');
  END LOOP;
END $$;

-- The pipeline safety fee rider: capped per service, both flags set.
INSERT INTO public.rate_items (id, tenant_id, item_code) VALUES
  ('00000000-0000-4000-8000-0000000028e1', '00000000-0000-4000-8000-0000000028a1', 'PSF');
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000028b1', true);
SELECT public.assert_reference_version('rate_items', '00000000-0000-4000-8000-0000000028e1', 1);
INSERT INTO public.rate_item_versions (tenant_id, rate_item_id, item_name, service_type, calculation_type, regulatory_class, effective_date, change_type) VALUES
  ('00000000-0000-4000-8000-0000000028a1', '00000000-0000-4000-8000-0000000028e1', 'PSF', 'gas', 'fixed_monthly', 'regulated', DATE '2020-01-01', 'initial');
INSERT INTO public.regulatory_surcharge_rules (tenant_id, rate_item_id, surcharge_kind, cycle_start, cycle_end, cap_per_service, excluded_from_tax_bases, exempts_state_agencies) VALUES
  ('00000000-0000-4000-8000-0000000028a1', '00000000-0000-4000-8000-0000000028e1', 'pipeline_safety_fee', DATE '2026-01-01', DATE '2026-12-31', 50, true, true);

-- inv(): a June bill of C1. p_loc NULL makes a consolidated parent; p_parent
-- makes a child; p_status 'void' plants a voided child (the owner).
CREATE FUNCTION pg_temp.inv(p_n int, p_loc uuid, p_parent int DEFAULT NULL, p_status text DEFAULT 'draft') RETURNS void LANGUAGE sql AS $$
  INSERT INTO public.invoices (id, tenant_id, invoice_number, customer_id, location_id, is_consolidated, parent_invoice_id, is_consolidated_child, status,
                               invoice_date, billing_period, period_start, period_end, due_date, amount_due)
  VALUES (('00000000-0000-4000-8000-0000000289' || lpad(p_n::text, 2, '0'))::uuid, '00000000-0000-4000-8000-0000000028a1', 'B28-' || p_n,
          '00000000-0000-4000-8000-0000000028c1', p_loc, p_loc IS NULL,
          CASE WHEN p_parent IS NOT NULL THEN ('00000000-0000-4000-8000-0000000289' || lpad(p_parent::text, 2, '0'))::uuid END,
          p_parent IS NOT NULL, p_status,
          DATE '2026-07-02', '2026-06', DATE '2026-06-01', DATE '2026-06-30', DATE '2026-07-20', 1.00);
$$;
-- psf(): the SQL of one fee line of p_amount on bill p_n, on meter p_meter.
-- regulatory_class is named only where a pending money patch has added it
-- (NOT NULL there), so the battery runs before and after that patch.
CREATE FUNCTION pg_temp.psf(p_n int, p_meter int, p_amount numeric) RETURNS text LANGUAGE sql AS $$
  SELECT format($f$INSERT INTO public.invoice_line_items (tenant_id, invoice_id, line_order, service_type, charge_type, description, amount, rate_item_id, meter_id, is_taxable%s)
    VALUES ('00000000-0000-4000-8000-0000000028a1', %L, (SELECT coalesce(max(line_order) + 1, 0) FROM public.invoice_line_items WHERE invoice_id = %L),
            'gas', 'surcharge', 'PSF', %s, '00000000-0000-4000-8000-0000000028e1', %L, false%s)$f$,
    CASE WHEN c.present THEN ', regulatory_class' ELSE '' END,
    '00000000-0000-4000-8000-0000000289' || lpad(p_n::text, 2, '0'), '00000000-0000-4000-8000-0000000289' || lpad(p_n::text, 2, '0'),
    p_amount, '00000000-0000-4000-8000-0000000028f' || p_meter,
    CASE WHEN c.present THEN ', ''regulated''' ELSE '' END)
  FROM (SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'invoice_line_items'
                                                                 AND column_name = 'regulatory_class') AS present) c
$$;
GRANT EXECUTE ON FUNCTION pg_temp.psf(int, int, numeric) TO tally_app;

SELECT pg_temp.inv(1, '00000000-0000-4000-8000-0000000028d1');            -- El Paso
SELECT pg_temp.inv(2, '00000000-0000-4000-8000-0000000028d2');            -- Austin
SELECT pg_temp.inv(3, '00000000-0000-4000-8000-0000000028d4');            -- no county
SELECT pg_temp.inv(10, NULL);                                             -- parent: El Paso + Hudspeth
SELECT pg_temp.inv(11, '00000000-0000-4000-8000-0000000028d1', 10);
SELECT pg_temp.inv(12, '00000000-0000-4000-8000-0000000028d3', 10);
SELECT pg_temp.inv(20, NULL);                                             -- parent: El Paso + Austin
SELECT pg_temp.inv(21, '00000000-0000-4000-8000-0000000028d1', 20);
SELECT pg_temp.inv(22, '00000000-0000-4000-8000-0000000028d2', 20);
SELECT pg_temp.inv(30, NULL);                                             -- parent: no child
SELECT pg_temp.inv(40, NULL);                                             -- parent: Austin live, El Paso void
SELECT pg_temp.inv(41, '00000000-0000-4000-8000-0000000028d2', 40);
SELECT pg_temp.inv(42, '00000000-0000-4000-8000-0000000028d1', 40, 'void');
SELECT pg_temp.inv(50, NULL);                                             -- parent whose child is a parent
SELECT pg_temp.inv(51, NULL, 50);
SELECT pg_temp.inv(60, NULL);                                             -- parent: only a void child
SELECT pg_temp.inv(61, '00000000-0000-4000-8000-0000000028d2', 60, 'void');

-- ======================================================= Z. the time zone
-- Z1-Z2: the reading itself, one zone each side of the change.
SELECT pg_temp.ok('Z1 the end of June 30 in Mountain time is after the change',
  public.customer_is_state_agency_as_of('00000000-0000-4000-8000-0000000028c1', DATE '2026-06-30', 'America/Denver'));
SELECT pg_temp.ok('Z2 the end of June 30 in Central time is before it',
  NOT public.customer_is_state_agency_as_of('00000000-0000-4000-8000-0000000028c1', DATE '2026-06-30', 'America/Chicago'));
SELECT pg_temp.ok('Z2b the day after, both zones read a state agency',
  public.customer_is_state_agency_as_of('00000000-0000-4000-8000-0000000028c1', DATE '2026-07-01', 'America/Chicago')
  AND public.customer_is_state_agency_as_of('00000000-0000-4000-8000-0000000028c1', DATE '2026-07-01', 'America/Denver'));
-- Z3: the zone is required and must be a real one; the date stays required.
SELECT pg_temp.refuses_at('Z3a no zone',
  $q$SELECT public.customer_is_state_agency_as_of('00000000-0000-4000-8000-0000000028c1', DATE '2026-06-30', NULL)$q$, '22004', 'a time zone is required');
SELECT pg_temp.refuses_at('Z3b a zone the server does not know',
  $q$SELECT public.customer_is_state_agency_as_of('00000000-0000-4000-8000-0000000028c1', DATE '2026-06-30', 'Mars/Olympus')$q$, '22023', 'Mars/Olympus');
SELECT pg_temp.refuses_at('Z3c no date',
  $q$SELECT public.customer_is_state_agency_as_of('00000000-0000-4000-8000-0000000028c1', NULL, 'America/Chicago')$q$, 'P0001', 'p_on is required');
-- Z4: the Chicago signature is gone, and no function keeps a zone constant.
SELECT pg_temp.ok('Z4a the two-argument signature is dropped',
  to_regprocedure('public.customer_is_state_agency_as_of(uuid,date)') IS NULL);
SELECT pg_temp.ok('Z4b no function in public names an America/ zone',
  NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
               WHERE n.nspname = 'public' AND p.prosrc ~ 'America/'));
-- Z5: the bill's zone.
SELECT pg_temp.ok('Z5a one premise: El Paso reads Mountain',
  public.invoice_time_zone_as_of('00000000-0000-4000-8000-000000028901', DATE '2026-06-30') = 'America/Denver');
SELECT pg_temp.ok('Z5b one premise: Austin reads Central',
  public.invoice_time_zone_as_of('00000000-0000-4000-8000-000000028902', DATE '2026-06-30') = 'America/Chicago');
SELECT pg_temp.ok('Z5c a parent whose children agree reads their zone',
  public.invoice_time_zone_as_of('00000000-0000-4000-8000-000000028910', DATE '2026-06-30') = 'America/Denver');
SELECT pg_temp.ok('Z5d a void child does not count',
  public.invoice_time_zone_as_of('00000000-0000-4000-8000-000000028940', DATE '2026-06-30') = 'America/Chicago');
SELECT pg_temp.refuses_at('Z5e a parent whose children disagree',
  $q$SELECT public.invoice_time_zone_as_of('00000000-0000-4000-8000-000000028920', DATE '2026-06-30')$q$, '21000', 'more than one time zone');
SELECT pg_temp.refuses_at('Z5f a parent with no child',
  $q$SELECT public.invoice_time_zone_as_of('00000000-0000-4000-8000-000000028930', DATE '2026-06-30')$q$, 'P0002', 'has no live child invoice');
SELECT pg_temp.refuses_at('Z5g a parent with only a void child',
  $q$SELECT public.invoice_time_zone_as_of('00000000-0000-4000-8000-000000028960', DATE '2026-06-30')$q$, 'P0002', 'has no live child invoice');
SELECT pg_temp.refuses_at('Z5h a child that names no premise',
  $q$SELECT public.invoice_time_zone_as_of('00000000-0000-4000-8000-000000028950', DATE '2026-06-30')$q$, 'P0002', 'names no premise');
SELECT pg_temp.refuses_at('Z5i a premise with no county (Texas is not one zone)',
  $q$SELECT public.invoice_time_zone_as_of('00000000-0000-4000-8000-000000028903', DATE '2026-06-30')$q$, 'P0002', 'no time zone can be read');
SELECT pg_temp.refuses_at('Z5j no bill',
  $q$SELECT public.invoice_time_zone_as_of(NULL, DATE '2026-06-30')$q$, '22004', 'p_invoice_id and p_on are required');
SELECT pg_temp.refuses_at('Z5k no date',
  $q$SELECT public.invoice_time_zone_as_of('00000000-0000-4000-8000-000000028901', NULL)$q$, '22004', 'p_invoice_id and p_on are required');
SELECT pg_temp.refuses_at('Z5l a bill that is not there',
  $q$SELECT public.invoice_time_zone_as_of('00000000-0000-4000-8000-0000000289ff', DATE '2026-06-30')$q$, 'P0002', 'is not visible');

-- Z6: the fee line, as the application writes it.
SET ROLE tally_app;
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000028b1', true);
SELECT pg_temp.refuses_at('Z6a El Paso: a state agency''s bill, a fee is refused',
  pg_temp.psf(1, 1, 1.00), '23514', 'was a state agency at the end of the billed period');
SELECT pg_temp.admits('Z6b Austin: not yet a state agency, the fee stands',
  pg_temp.psf(2, 2, 1.00));
SELECT pg_temp.admits('Z6c El Paso: a 0.00 fee line stands',
  pg_temp.psf(1, 1, 0.00));
SELECT pg_temp.admits('Z6d no zone needed for a 0.00 line: a premise with no county',
  pg_temp.psf(3, 4, 0.00));
SELECT pg_temp.refuses_at('Z6e a premise with no county: a fee refuses, never assumes Central',
  pg_temp.psf(3, 4, 1.00), 'P0002', 'no time zone can be read');
SELECT pg_temp.refuses_at('Z6f parent, children in Mountain: refused as a state agency''s bill',
  pg_temp.psf(10, 1, 1.00), '23514', 'was a state agency at the end of the billed period');
SELECT pg_temp.refuses_at('Z6g parent, children in two zones',
  pg_temp.psf(20, 1, 1.00), '21000', 'more than one time zone');
SELECT pg_temp.refuses_at('Z6h parent, no child',
  pg_temp.psf(30, 1, 1.00), 'P0002', 'has no live child invoice');
SELECT pg_temp.admits('Z6i parent, Austin child live and El Paso child void: Central, the fee stands',
  pg_temp.psf(40, 2, 1.00));
RESET ROLE;

-- Z7: who may call the two functions (as premise_time_zone_as_of: not PUBLIC).
SELECT pg_temp.ok('Z7 both functions: the application and the core, not PUBLIC',
  (SELECT bool_and(has_function_privilege('tally_app', f, 'EXECUTE') AND has_function_privilege('tally_core', f, 'EXECUTE')
                   AND NOT coalesce(aclcontains(p.proacl, makeaclitem(0, p.proowner, 'EXECUTE', false)), true))
     FROM unnest(ARRAY['public.customer_is_state_agency_as_of(uuid,date,text)', 'public.invoice_time_zone_as_of(uuid,date)']::regprocedure[]) f
     JOIN pg_proc p ON p.oid = f));

DO $$ BEGIN RAISE NOTICE 'battery-28: all checks passed'; END $$;
ROLLBACK;
