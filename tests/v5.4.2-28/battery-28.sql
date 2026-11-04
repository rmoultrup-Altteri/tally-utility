-- ============================================================================
-- BATTERY v5.4.2-28 — rates small fixes (2026-11-02; r2 and its review's test additions 2026-11-04)
-- Run: psql -U tally -d <db-with-patch> -v ON_ERROR_STOP=1 -f battery-28.sql
-- One transaction, rolled back. Fixtures as the owner; the guard the
-- application meets is exercised as tally_app too. refuses_at() requires the
-- named SQLSTATE AND a fragment of the named guard's message, so a test cannot
-- pass on another guard that shares the SQLSTATE. ok() treats NULL as a fail.
--
--   Z  the state-agency check reads the bill's premise's time zone (CI-010;
--      Ryan 2026-11-02, option 1): one premise, a consolidated parent's
--      children (agree / disagree / none / void excluded / nested; r2: a
--      consolidated parent that names a premise of its own still reads its
--      children, a consolidated child is refused whatever its premise), the
--      refusal when no zone can be read, no lookup for a 0.00 line, the old
--      Chicago signature gone, no zone constant left in any function.
--   D  rider dependencies dated in place (CI-101; Ryan 2026-11-02, option
--      1): the date required, born open, stamped, frozen, one open row per
--      link per day, cycles by overlapping dates (and the stated
--      conservative refusal), succession and retraction, the as-of read.
--      Transaction time is read only at now() and just before: inside one
--      transaction every stamp is now(). Races: -19's cycle-19.sh and -21's
--      labels-21.sh, ported to the dated shape.
--   R  rates carry at most four decimals (K-06; Ryan 2026-11-02, option 2):
--      a version's rate, a tier's rate, a schedule's override; negative
--      rates too; a tier rate that is not a number; columns stay scale 6;
--      r2: NaN refused, a fraction-unit rate refused under the check that
--      says to store percent, and every CHECK and exclusion constraint in
--      the public schema reparses from its stored text (the form pg_dump
--      writes; the real dump and restore is a separate verification step).
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
-- zone_is(): the zone lookup answers p_zone; a refusal is a labelled FAIL,
-- not a bare error (ok() evaluates its argument before it can label it).
CREATE FUNCTION pg_temp.zone_is(p_label text, p_invoice uuid, p_zone text) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE v text;
BEGIN
  BEGIN
    v := public.invoice_time_zone_as_of(p_invoice, DATE '2026-06-30');
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'FAIL %: refused with % (%)', p_label, SQLSTATE, SQLERRM;
  END;
  IF v IS DISTINCT FROM p_zone THEN RAISE EXCEPTION 'FAIL %: % (expected %)', p_label, v, p_zone; END IF;
  RAISE NOTICE 'PASS %', p_label;
END $$;
GRANT EXECUTE ON FUNCTION pg_temp.refuses_at(text, text, text, text), pg_temp.ok(text, boolean), pg_temp.admits(text, text) TO tally_app;

-- ================================================================= fixtures
INSERT INTO public.tenants (id, name, slug) VALUES
  ('00000000-0000-4000-8000-0000000028a1', 'T1 City Gas', 'bat28-t1');
INSERT INTO public.users (id, tenant_id, display_name, email, role) VALUES
  ('00000000-0000-4000-8000-0000000028b1', '00000000-0000-4000-8000-0000000028a1', 'Op1', 'op1@bat28.test', 'operator');
-- T2: a second utility (its user forges a changed_by / closed_by in D; its
-- bills attach to T1's summary bills in Z5q/Z5r).
INSERT INTO public.tenants (id, name, slug) VALUES
  ('00000000-0000-4000-8000-0000000028a2', 'T2 Gasco', 'bat28-t2');
INSERT INTO public.users (id, tenant_id, display_name, email, role) VALUES
  ('00000000-0000-4000-8000-0000000028b2', '00000000-0000-4000-8000-0000000028a2', 'Op2', 'op2@bat28.test', 'operator');
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

-- Places: Texas, El Paso and Hudspeth counties are seeded (-16); a Central
-- county is planted here with its zone (an even code, never a real Texas
-- county, so it does not collide with -29's load); it stands in for Travis.
CREATE TEMP TABLE b28 (k text PRIMARY KEY, id uuid);
INSERT INTO b28 SELECT 'tx', id FROM public.places WHERE kind_code = 'state' AND place_code = 'TX';
INSERT INTO b28 SELECT 'elpaso', id FROM public.places WHERE kind_code = 'county' AND place_code = '48141';
INSERT INTO b28 SELECT 'hudspeth', id FROM public.places WHERE kind_code = 'county' AND place_code = '48229';
WITH p AS (
  INSERT INTO public.places (kind_code, state_code, place_code, name, parent_place_id, effective_from, source_note)
  VALUES ('county', 'TX', '48990', 'Battery County 28 (Central)', (SELECT id FROM b28 WHERE k = 'tx'), DATE '1900-01-01', 'battery 28 fixture')
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

-- inv(): a June bill of C1. p_loc NULL makes a consolidated parent (p_cons
-- true makes one that also names a premise); p_parent makes a child;
-- p_status 'void' plants a voided child (the owner).
CREATE FUNCTION pg_temp.inv(p_n int, p_loc uuid, p_parent int DEFAULT NULL, p_status text DEFAULT 'draft', p_cons boolean DEFAULT NULL) RETURNS void LANGUAGE sql AS $$
  INSERT INTO public.invoices (id, tenant_id, invoice_number, customer_id, location_id, is_consolidated, parent_invoice_id, is_consolidated_child, status,
                               invoice_date, billing_period, period_start, period_end, due_date, amount_due)
  VALUES (('00000000-0000-4000-8000-0000000289' || lpad(p_n::text, 2, '0'))::uuid, '00000000-0000-4000-8000-0000000028a1', 'B28-' || p_n,
          '00000000-0000-4000-8000-0000000028c1', p_loc, coalesce(p_cons, p_loc IS NULL),
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
-- r2 (Codex B3): consolidated invoices that name a premise of their own.
SELECT pg_temp.inv(70, '00000000-0000-4000-8000-0000000028d1', NULL, 'draft', true);  -- parent at El Paso: El Paso + Austin children
SELECT pg_temp.inv(71, '00000000-0000-4000-8000-0000000028d1', 70);
SELECT pg_temp.inv(72, '00000000-0000-4000-8000-0000000028d2', 70);
SELECT pg_temp.inv(73, '00000000-0000-4000-8000-0000000028d2', NULL, 'draft', true);  -- parent at Austin: an El Paso child
SELECT pg_temp.inv(74, '00000000-0000-4000-8000-0000000028d1', 73);
SELECT pg_temp.inv(75, '00000000-0000-4000-8000-0000000028d1', NULL, 'draft', true);  -- parent at El Paso: a Hudspeth child
SELECT pg_temp.inv(76, '00000000-0000-4000-8000-0000000028d3', 75);
SELECT pg_temp.inv(77, NULL);                                                         -- parent whose child is consolidated with a premise
SELECT pg_temp.inv(78, '00000000-0000-4000-8000-0000000028d2', 77, 'draft', true);
SELECT pg_temp.inv(79, '00000000-0000-4000-8000-0000000028d2', NULL, 'draft', true);  -- consolidated at Austin, no child
-- Another utility's bills attached to T1's summary bills (r2 review: Opus,
-- Fable and Codex). The schema admits this today (the parent link is a
-- single-column key; the cross-tenant link fix, CI-116, closes it later);
-- the lookup's tenant filters must keep them out even for the owner, who
-- sees both. T2's premise is in Austin. Parents 87 and 89 are used only
-- here, so a broken filter is named at Z5q / Z5r and nowhere earlier.
SELECT pg_temp.inv(87, NULL);                                             -- parent: an El Paso child (88) + T2's Austin bill
SELECT pg_temp.inv(88, '00000000-0000-4000-8000-0000000028d1', 87);
SELECT pg_temp.inv(89, NULL);                                             -- parent: an El Paso child (90) + T2's consolidated bill
SELECT pg_temp.inv(90, '00000000-0000-4000-8000-0000000028d1', 89);
INSERT INTO public.customers (id, tenant_id, customer_number, customer_type) VALUES
  ('00000000-0000-4000-8000-0000000028c2', '00000000-0000-4000-8000-0000000028a2', 'B28-C2', 'residential');
INSERT INTO public.service_locations (id, tenant_id, customer_id, location_number, address_line1, city, state, zip) VALUES
  ('00000000-0000-4000-8000-0000000028d5', '00000000-0000-4000-8000-0000000028a2', '00000000-0000-4000-8000-0000000028c2', 'T2-L', '5 Main', 'Austin', 'TX', '78701');
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000028b2', true);
INSERT INTO public.premise_place_memberships (tenant_id, service_location_id, place_id, axis, place_kind,
                                              valid_from, evidence_kind, evidence_reference, evidence_date)
VALUES ('00000000-0000-4000-8000-0000000028a2', '00000000-0000-4000-8000-0000000028d5', (SELECT id FROM b28 WHERE k = 'travis'), 'regulatory', 'state',
        DATE '2020-01-01', 'ordinance', 'battery 28', DATE '2019-12-01');
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000028b1', true);
INSERT INTO public.invoices (id, tenant_id, invoice_number, customer_id, location_id, is_consolidated, parent_invoice_id, is_consolidated_child, status,
                             invoice_date, billing_period, period_start, period_end, due_date, amount_due) VALUES
  -- a live Austin bill of T2 under T1's parent 87 (El Paso)
  ('00000000-0000-4000-8000-000000028985', '00000000-0000-4000-8000-0000000028a2', 'B28-T2-85', '00000000-0000-4000-8000-0000000028c2', '00000000-0000-4000-8000-0000000028d5',
   false, '00000000-0000-4000-8000-000000028987', true, 'draft', DATE '2026-07-02', '2026-06', DATE '2026-06-01', DATE '2026-06-30', DATE '2026-07-20', 1.00),
  -- a consolidated bill of T2 under T1's parent 89 (El Paso)
  ('00000000-0000-4000-8000-000000028986', '00000000-0000-4000-8000-0000000028a2', 'B28-T2-86', '00000000-0000-4000-8000-0000000028c2', '00000000-0000-4000-8000-0000000028d5',
   true, '00000000-0000-4000-8000-000000028989', true, 'draft', DATE '2026-07-02', '2026-06', DATE '2026-06-01', DATE '2026-06-30', DATE '2026-07-20', 1.00);

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
SELECT pg_temp.zone_is('Z5a one premise: El Paso reads Mountain',
  '00000000-0000-4000-8000-000000028901', 'America/Denver');
SELECT pg_temp.zone_is('Z5b one premise: Austin reads Central',
  '00000000-0000-4000-8000-000000028902', 'America/Chicago');
SELECT pg_temp.zone_is('Z5c a parent whose children agree reads their zone',
  '00000000-0000-4000-8000-000000028910', 'America/Denver');
SELECT pg_temp.zone_is('Z5d a void child does not count',
  '00000000-0000-4000-8000-000000028940', 'America/Chicago');
SELECT pg_temp.refuses_at('Z5e a parent whose children disagree',
  $q$SELECT public.invoice_time_zone_as_of('00000000-0000-4000-8000-000000028920', DATE '2026-06-30')$q$, '21000', 'more than one time zone');
SELECT pg_temp.refuses_at('Z5f a parent with no child',
  $q$SELECT public.invoice_time_zone_as_of('00000000-0000-4000-8000-000000028930', DATE '2026-06-30')$q$, 'P0002', 'has no live child invoice');
SELECT pg_temp.refuses_at('Z5g a parent with only a void child',
  $q$SELECT public.invoice_time_zone_as_of('00000000-0000-4000-8000-000000028960', DATE '2026-06-30')$q$, 'P0002', 'has no live child invoice');
SELECT pg_temp.refuses_at('Z5h a child that is itself consolidated, with no premise',
  $q$SELECT public.invoice_time_zone_as_of('00000000-0000-4000-8000-000000028950', DATE '2026-06-30')$q$, 'P0002', 'is itself a consolidated invoice');
SELECT pg_temp.refuses_at('Z5h2 a child that is itself consolidated, naming a premise (r2, Codex B3)',
  $q$SELECT public.invoice_time_zone_as_of('00000000-0000-4000-8000-000000028977', DATE '2026-06-30')$q$, 'P0002', 'is itself a consolidated invoice');
SELECT pg_temp.refuses_at('Z5m a consolidated parent with a premise still reads its children, which disagree (r2, Codex B3)',
  $q$SELECT public.invoice_time_zone_as_of('00000000-0000-4000-8000-000000028970', DATE '2026-06-30')$q$, '21000', 'more than one time zone');
SELECT pg_temp.refuses_at('Z5n a consolidated parent whose own premise disagrees with its one child (r2)',
  $q$SELECT public.invoice_time_zone_as_of('00000000-0000-4000-8000-000000028973', DATE '2026-06-30')$q$, '21000', 'more than one time zone');
SELECT pg_temp.zone_is('Z5o a consolidated parent whose own premise and child agree reads that zone (r2)',
  '00000000-0000-4000-8000-000000028975', 'America/Denver');
SELECT pg_temp.zone_is('Z5q the owner, who sees both utilities: another utility''s Austin bill under a Mountain parent stays out of the zone (r2 review)',
  '00000000-0000-4000-8000-000000028987', 'America/Denver');
SELECT pg_temp.zone_is('Z5r the owner: another utility''s consolidated bill under a parent is not read as a nested parent (r2 review)',
  '00000000-0000-4000-8000-000000028989', 'America/Denver');
SELECT pg_temp.refuses_at('Z5p a consolidated parent with a premise but no child (r2)',
  $q$SELECT public.invoice_time_zone_as_of('00000000-0000-4000-8000-000000028979', DATE '2026-06-30')$q$, 'P0002', 'has no live child invoice');
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
SELECT pg_temp.refuses_at('Z6j a consolidated parent at El Paso over El Paso and Austin children: the fee is refused, not judged at El Paso (r2, Codex B3)',
  pg_temp.psf(70, 2, 1.00), '21000', 'more than one time zone');
RESET ROLE;

-- Z7: who may call the two functions (as premise_time_zone_as_of: not PUBLIC).
SELECT pg_temp.ok('Z7 both functions: the application and the core, not PUBLIC',
  (SELECT bool_and(has_function_privilege('tally_app', f, 'EXECUTE') AND has_function_privilege('tally_core', f, 'EXECUTE')
                   AND NOT coalesce(aclcontains(p.proacl, makeaclitem(0, p.proowner, 'EXECUTE', false)), true))
     FROM unnest(ARRAY['public.customer_is_state_agency_as_of(uuid,date,text)', 'public.invoice_time_zone_as_of(uuid,date)']::regprocedure[]) f
     JOIN pg_proc p ON p.oid = f));

-- ============================================ D. rider dependencies, dated
-- Fixtures: schedule RS28; items A, B, C, D, E of tenant 1; tenant 2 and
-- its user (a forged changed_by / closed_by). Every write is tally_app's.
INSERT INTO public.rate_schedules (id, tenant_id, code) VALUES
  ('00000000-0000-4000-8000-000000002841', '00000000-0000-4000-8000-0000000028a1', 'RS28');
INSERT INTO public.rate_items (id, tenant_id, item_code) VALUES
  ('00000000-0000-4000-8000-0000000028aa', '00000000-0000-4000-8000-0000000028a1', 'A'),
  ('00000000-0000-4000-8000-0000000028bb', '00000000-0000-4000-8000-0000000028a1', 'B'),
  ('00000000-0000-4000-8000-0000000028cc', '00000000-0000-4000-8000-0000000028a1', 'C'),
  ('00000000-0000-4000-8000-0000000028dd', '00000000-0000-4000-8000-0000000028a1', 'D'),
  ('00000000-0000-4000-8000-0000000028ee', '00000000-0000-4000-8000-0000000028a1', 'E');
-- dep(): the SQL of one dependency (dependent on base) from p_from to p_to;
-- p_extra adds columns and values (a leading comma each).
CREATE FUNCTION pg_temp.dep(p_dep text, p_base text, p_from text, p_to text DEFAULT NULL, p_id text DEFAULT NULL,
                            p_cols text DEFAULT '', p_vals text DEFAULT '') RETURNS text LANGUAGE sql AS $$
  SELECT format($f$INSERT INTO public.rate_item_dependencies (id, tenant_id, rate_schedule_id, dependent_rate_item_id, base_rate_item_id, effective_date, expiry_date%s)
    VALUES (%s, '00000000-0000-4000-8000-0000000028a1', '00000000-0000-4000-8000-000000002841',
            '00000000-0000-4000-8000-0000000028%s', '00000000-0000-4000-8000-0000000028%s', %L, %L%s)$f$,
    p_cols, coalesce(quote_literal('00000000-0000-4000-8000-0000000028' || p_id), 'DEFAULT'),
    repeat(lower(p_dep), 2), repeat(lower(p_base), 2), p_from, p_to, p_vals)
$$;
CREATE FUNCTION pg_temp.did(p_id text) RETURNS uuid LANGUAGE sql AS $$ SELECT ('00000000-0000-4000-8000-0000000028' || p_id)::uuid $$;
GRANT EXECUTE ON FUNCTION pg_temp.dep(text, text, text, text, text, text, text), pg_temp.did(text) TO tally_app;

-- D0: the -21 retirement columns are gone; the shape is A-1 group 2.
SELECT pg_temp.ok('D0 retired_at, retired_by and retired_reason are dropped; the A-1 columns are there',
  NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'rate_item_dependencies' AND column_name LIKE 'retired%')
  AND (SELECT count(*) FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'rate_item_dependencies'
        AND column_name IN ('effective_date', 'expiry_date', 'recorded_at', 'recorded_until', 'change_type', 'change_reason',
                            'changed_by', 'supersedes_id', 'closed_type', 'closed_reason', 'closed_by')) = 11);

SET ROLE tally_app;
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000028b1', true);
-- D1: an in-force date is required, and the bracket is ordered.
SELECT pg_temp.refuses_at('D1a a dependency with no in-force date',
  replace(pg_temp.dep('A', 'B', '2026-01-01'), $s$'2026-01-01'$s$, 'NULL'), '23502', 'effective_date');
SELECT pg_temp.refuses_at('D1b an expiry before the start',
  pg_temp.dep('A', 'B', '2026-03-01', '2026-02-01'), '23514', 'rate_item_dependencies_valid_bracket_check');
-- D2: born open, initial, stamped by the database.
SELECT pg_temp.refuses_at('D2a born closed',
  pg_temp.dep('A', 'B', '2026-01-01', NULL, NULL, ', recorded_until, closed_type, closed_reason', $v$, now(), 'retracted', 'born closed'$v$),
  '23514', 'born open');
SELECT pg_temp.refuses_at('D2b born as a backfill',
  pg_temp.dep('A', 'B', '2026-01-01', NULL, NULL, ', change_type', $v$, 'backfill'$v$), '23514', 'backfill');
SELECT pg_temp.refuses_at('D2c a successor that names nothing',
  pg_temp.dep('A', 'B', '2026-01-01', NULL, NULL, ', change_type', $v$, 'succession'$v$), '23514', 'rate_item_dependencies_supersedes_check');
SELECT pg_temp.admits('D2d A on B, January to March, with a forged recorded_at and changed_by',
  pg_temp.dep('A', 'B', '2026-01-01', '2026-03-31', '01', ', recorded_at, changed_by', $v$, '2001-01-01', '00000000-0000-4000-8000-0000000028b2'$v$));
SELECT pg_temp.ok('D2e recorded_at is the database''s, changed_by the session''s user',
  (SELECT recorded_at = now() AND changed_by = '00000000-0000-4000-8000-0000000028b1' AND change_type = 'initial'
     FROM public.rate_item_dependencies WHERE id = pg_temp.did('01')));
-- D3: frozen.
SELECT pg_temp.refuses_at('D3a an open row edited in place',
  $q$UPDATE public.rate_item_dependencies SET expiry_date = '2026-06-30' WHERE id = '00000000-0000-4000-8000-000000002801'$q$, '23001', 'never edited in place');
SELECT pg_temp.refuses_at('D3b even its notes',
  $q$UPDATE public.rate_item_dependencies SET notes = 'edited' WHERE id = '00000000-0000-4000-8000-000000002801'$q$, '23001', 'never edited in place');
-- D3c proves only that tally_app holds no DELETE grant; D9e covers the
-- guard itself, for the owner.
SELECT pg_temp.refuses_at('D3c the application has no DELETE grant on dependencies',
  $q$DELETE FROM public.rate_item_dependencies WHERE id = '00000000-0000-4000-8000-000000002801'$q$, '42501', 'permission denied');
-- D4: one open row per link per day; the bracket is inclusive.
SELECT pg_temp.refuses_at('D4a A on B again from March 31 (the last day of the first)',
  pg_temp.dep('A', 'B', '2026-03-31'), '23P01', 'rate_item_dependencies_open_no_overlap_excl');
SELECT pg_temp.admits('D4b A on B again from April 1 (no shared day)',
  pg_temp.dep('A', 'B', '2026-04-01', NULL, '02'));
-- D5: cycles by date.
SELECT pg_temp.refuses_at('D5a B on A from March: shares March with A on B',
  pg_temp.dep('B', 'A', '2026-03-01', '2026-03-31'), '23514', 'closes a cycle');
SELECT pg_temp.refuses_at('D5b B on A from April: A on B is in force again from April (row 02)',
  pg_temp.dep('B', 'A', '2026-04-01'), '23514', 'closes a cycle');
-- D6: the stated conservative refusal. D on E through March, E on C from
-- April; C on D for all of 2026 would need all three on one day, which
-- never happens, and is refused anyway (each link overlaps the new one).
SELECT pg_temp.admits('D6-fixture D on E, January to March 2026', pg_temp.dep('D', 'E', '2026-01-01', '2026-03-31', '04'));
SELECT pg_temp.admits('D6-fixture E on C, from April 2026', pg_temp.dep('E', 'C', '2026-04-01', NULL, '05'));
SELECT pg_temp.refuses_at('D6 C on D for 2026: no day holds the whole cycle, refused by design (conservative)',
  pg_temp.dep('C', 'D', '2026-01-01', '2026-12-31'), '23514', 'closes a cycle');
SELECT pg_temp.admits('D6b C on D from 2027: D on E has ended, no overlap, no cycle',
  pg_temp.dep('C', 'D', '2027-01-01', NULL, '03'));
-- D7: the dependency stopped applying on a date: close as superseded, add
-- the successor with that expiry (same transaction).
-- D7a: a close says why (r2, Codex B1: a NULL reason passed a bare
-- pattern test). Each kind of close, each way of saying nothing.
SELECT pg_temp.refuses_at('D7a a close with a blank reason',
  $q$UPDATE public.rate_item_dependencies SET recorded_until = now(), closed_type = 'superseded', closed_reason = ' ' WHERE id = '00000000-0000-4000-8000-000000002803'$q$,
  '23514', 'rate_item_dependencies_close_consistent_check');
SELECT pg_temp.refuses_at('D7a2 a supersession that gives no reason (the column left out)',
  $q$UPDATE public.rate_item_dependencies SET recorded_until = now(), closed_type = 'superseded' WHERE id = '00000000-0000-4000-8000-000000002803'$q$,
  '23514', 'rate_item_dependencies_close_consistent_check');
SELECT pg_temp.refuses_at('D7a3 a supersession with a NULL reason',
  $q$UPDATE public.rate_item_dependencies SET recorded_until = now(), closed_type = 'superseded', closed_reason = NULL WHERE id = '00000000-0000-4000-8000-000000002803'$q$,
  '23514', 'rate_item_dependencies_close_consistent_check');
SELECT pg_temp.refuses_at('D7a4 a supersession whose reason is punctuation',
  $q$UPDATE public.rate_item_dependencies SET recorded_until = now(), closed_type = 'superseded', closed_reason = '--.' WHERE id = '00000000-0000-4000-8000-000000002803'$q$,
  '23514', 'rate_item_dependencies_close_consistent_check');
SELECT pg_temp.refuses_at('D7a5 a retraction that gives no reason (the column left out)',
  $q$UPDATE public.rate_item_dependencies SET recorded_until = now(), closed_type = 'retracted' WHERE id = '00000000-0000-4000-8000-000000002805'$q$,
  '23514', 'rate_item_dependencies_close_consistent_check');
SELECT pg_temp.refuses_at('D7a6 a retraction with a NULL reason',
  $q$UPDATE public.rate_item_dependencies SET recorded_until = now(), closed_type = 'retracted', closed_reason = NULL WHERE id = '00000000-0000-4000-8000-000000002805'$q$,
  '23514', 'rate_item_dependencies_close_consistent_check');
SELECT pg_temp.refuses_at('D7a7 a retraction with a blank reason (a tab)',
  $q$UPDATE public.rate_item_dependencies SET recorded_until = now(), closed_type = 'retracted', closed_reason = E'\t' WHERE id = '00000000-0000-4000-8000-000000002805'$q$,
  '23514', 'rate_item_dependencies_close_consistent_check');
SELECT pg_temp.refuses_at('D7a8 a retraction whose reason is punctuation',
  $q$UPDATE public.rate_item_dependencies SET recorded_until = now(), closed_type = 'retracted', closed_reason = '...' WHERE id = '00000000-0000-4000-8000-000000002805'$q$,
  '23514', 'rate_item_dependencies_close_consistent_check');
-- (Back-date the header past its own updated_at trigger directly before the
-- close, so D7c sees the close's own bump and nothing else's: r2, Fable S1.)
RESET ROLE;
SET LOCAL session_replication_role = replica;
UPDATE public.rate_schedules SET updated_at = '2000-01-01' WHERE id = '00000000-0000-4000-8000-000000002841';
SET LOCAL session_replication_role = origin;
SELECT pg_temp.ok('D7-fixture the header is back-dated', (SELECT updated_at < now() FROM public.rate_schedules WHERE id = '00000000-0000-4000-8000-000000002841'));
SET ROLE tally_app;
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000028b1', true);
UPDATE public.rate_item_dependencies SET recorded_until = '2001-01-01', closed_type = 'superseded', closed_reason = 'C on D ends 2027-06-30',
                                         closed_by = '00000000-0000-4000-8000-0000000028b2'
 WHERE id = pg_temp.did('03');
SELECT pg_temp.ok('D7c the close is stamped (recorded_until now, closed_by the session''s user) and took the schedule header (checked before the successor''s insert bumps it too)',
  (SELECT recorded_until = now() AND closed_by = '00000000-0000-4000-8000-0000000028b1' FROM public.rate_item_dependencies WHERE id = pg_temp.did('03'))
  AND (SELECT updated_at = now() FROM public.rate_schedules WHERE id = '00000000-0000-4000-8000-000000002841'));
SELECT pg_temp.admits('D7b the successor, C on D January to June 2027',
  pg_temp.dep('C', 'D', '2027-01-01', '2027-06-30', '06', ', change_type, change_reason, supersedes_id',
              $v$, 'succession', 'tariff sheet 7 withdrawn', '00000000-0000-4000-8000-000000002803'$v$));
SELECT pg_temp.admits('D7d C on D has ended, so D on C from July 2027 is no cycle',
  pg_temp.dep('D', 'C', '2027-07-01', NULL, '07'));
SELECT pg_temp.refuses_at('D7e a closed row is immutable',
  $q$UPDATE public.rate_item_dependencies SET closed_reason = 'rewritten' WHERE id = '00000000-0000-4000-8000-000000002803'$q$, '23001', 'immutable');
SELECT pg_temp.refuses_at('D7f a successor of another link',
  pg_temp.dep('A', 'C', '2026-01-01', NULL, NULL, ', change_type, supersedes_id', $v$, 'succession', '00000000-0000-4000-8000-000000002803'$v$),
  '23514', 'different entity');
SELECT pg_temp.refuses_at('D7g closed as superseded with no successor at commit',
  $q$DO $d$ BEGIN
       UPDATE public.rate_item_dependencies SET recorded_until = now(), closed_type = 'superseded', closed_reason = 'no successor'
        WHERE id = '00000000-0000-4000-8000-000000002805';
       SET CONSTRAINTS enforce_superseded_has_successor IMMEDIATE;
     END $d$$q$, '23000', 'no ASSERTED');
SET CONSTRAINTS enforce_superseded_has_successor DEFERRED;
-- D8: entered in error: close as retracted; it has no successor, and it
-- leaves the cycle walk.
UPDATE public.rate_item_dependencies SET recorded_until = now(), closed_type = 'retracted', closed_reason = 'keyed against the wrong item'
 WHERE id = pg_temp.did('02');
-- D8a: a correction says why (on a properly closed predecessor; the block
-- is rolled back with the refusal).
SELECT pg_temp.refuses_at('D8a a correction with no reason',
  $q$DO $d$ BEGIN
       UPDATE public.rate_item_dependencies SET recorded_until = now(), closed_type = 'superseded', closed_reason = 'dates were wrong'
        WHERE id = '00000000-0000-4000-8000-000000002804';
       INSERT INTO public.rate_item_dependencies (tenant_id, rate_schedule_id, dependent_rate_item_id, base_rate_item_id, effective_date, expiry_date, change_type, supersedes_id)
       VALUES ('00000000-0000-4000-8000-0000000028a1', '00000000-0000-4000-8000-000000002841', '00000000-0000-4000-8000-0000000028dd', '00000000-0000-4000-8000-0000000028ee',
               '2026-01-01', '2026-02-28', 'correction', '00000000-0000-4000-8000-000000002804');
     END $d$$q$, '23514', 'rate_item_dependencies_change_reason_check');
SELECT pg_temp.refuses_at('D8b a successor of a retracted row, with a reason',
  pg_temp.dep('A', 'B', '2026-04-01', NULL, NULL, ', change_type, change_reason, supersedes_id', $v$, 'correction', 'try', '00000000-0000-4000-8000-000000002802'$v$),
  '23514', 'a retracted assertion has no successor');
SELECT pg_temp.admits('D8c B on A from April now passes: the retracted A on B is not in the walk',
  pg_temp.dep('B', 'A', '2026-04-01', NULL, '08'));
-- D9: the read.
SELECT pg_temp.ok('D9a in force on 2026-02-10: A on B, D on E',
  (SELECT array_agg(item_code_pair ORDER BY item_code_pair) FROM (
     SELECT di.item_code || '>' || bi.item_code AS item_code_pair
       FROM public.rate_item_dependencies_as_of('00000000-0000-4000-8000-000000002841', DATE '2026-02-10', now()) d
       JOIN public.rate_items di ON di.id = d.dependent_rate_item_id JOIN public.rate_items bi ON bi.id = d.base_rate_item_id) x)
  = ARRAY['A>B', 'D>E']);
SELECT pg_temp.ok('D9b in force on 2026-08-01: B on A, E on C',
  (SELECT array_agg(item_code_pair ORDER BY item_code_pair) FROM (
     SELECT di.item_code || '>' || bi.item_code AS item_code_pair
       FROM public.rate_item_dependencies_as_of('00000000-0000-4000-8000-000000002841', DATE '2026-08-01', now()) d
       JOIN public.rate_items di ON di.id = d.dependent_rate_item_id JOIN public.rate_items bi ON bi.id = d.base_rate_item_id) x)
  = ARRAY['B>A', 'E>C']);
SELECT pg_temp.ok('D9b2 2027: C on D (the successor) in March, D on C in August',
  (SELECT array_agg(di.item_code || '>' || bi.item_code)
     FROM public.rate_item_dependencies_as_of('00000000-0000-4000-8000-000000002841', DATE '2027-03-01', now()) d
     JOIN public.rate_items di ON di.id = d.dependent_rate_item_id JOIN public.rate_items bi ON bi.id = d.base_rate_item_id
    WHERE di.item_code IN ('C', 'D')) = ARRAY['C>D']
  AND (SELECT array_agg(di.item_code || '>' || bi.item_code)
     FROM public.rate_item_dependencies_as_of('00000000-0000-4000-8000-000000002841', DATE '2027-08-01', now()) d
     JOIN public.rate_items di ON di.id = d.dependent_rate_item_id JOIN public.rate_items bi ON bi.id = d.base_rate_item_id
    WHERE di.item_code IN ('C', 'D')) = ARRAY['D>C']);
SELECT pg_temp.ok('D9c as known before any of it was recorded: nothing',
  NOT EXISTS (SELECT 1 FROM public.rate_item_dependencies_as_of('00000000-0000-4000-8000-000000002841', DATE '2026-02-10', now() - interval '1 second')));
SELECT pg_temp.refuses_at('D9d the read needs every coordinate',
  $q$SELECT * FROM public.rate_item_dependencies_as_of('00000000-0000-4000-8000-000000002841', NULL, now())$q$, '22004', 'all required');
RESET ROLE;
SELECT pg_temp.refuses_at('D9e the owner deletes a dependency',
  $q$DELETE FROM public.rate_item_dependencies WHERE id = '00000000-0000-4000-8000-000000002801'$q$, '23001', 'never');
SELECT pg_temp.ok('D10 the read: the application and the core, not PUBLIC',
  has_function_privilege('tally_app', 'public.rate_item_dependencies_as_of(uuid,date,timestamptz)', 'EXECUTE')
  AND has_function_privilege('tally_core', 'public.rate_item_dependencies_as_of(uuid,date,timestamptz)', 'EXECUTE')
  AND NOT (SELECT coalesce(aclcontains(proacl, makeaclitem(0, proowner, 'EXECUTE', false)), true)
             FROM pg_proc WHERE oid = 'public.rate_item_dependencies_as_of(uuid,date,timestamptz)'::regprocedure));
DO $$ BEGIN
  PERFORM public.assert_wave1_guard_invariants();
  RAISE NOTICE 'PASS D11: the wave-1 guard invariant holds with the two A-1 triggers';
EXCEPTION WHEN OTHERS THEN
  RAISE EXCEPTION 'FAIL D11: %', SQLERRM;
END $$;

-- ========================================= R. rates carry four decimals
-- Kyle K-06; Ryan 2026-11-02, option 2. Items R1..R8 of tenant 1; each
-- admitted version gets its own item (versions of one item may not overlap).
INSERT INTO public.rate_items (id, tenant_id, item_code)
SELECT ('00000000-0000-4000-8000-00000000287' || g)::uuid, '00000000-0000-4000-8000-0000000028a1', 'R' || g FROM generate_series(1, 8) g;
-- riv(): the SQL of one version of item R<n> with p_cols / p_vals added.
CREATE FUNCTION pg_temp.riv(p_n int, p_kind text, p_cols text, p_vals text) RETURNS text LANGUAGE sql AS $$
  SELECT format($f$INSERT INTO public.rate_item_versions (tenant_id, rate_item_id, item_name, service_type, calculation_type, regulatory_class, effective_date, change_type%s)
    VALUES ('00000000-0000-4000-8000-0000000028a1', '00000000-0000-4000-8000-00000000287%s', 'R%s', 'gas', %L, 'regulated', DATE '2026-01-01', 'initial'%s)$f$,
    p_cols, p_n, p_n, p_kind, p_vals)
$$;
GRANT EXECUTE ON FUNCTION pg_temp.riv(int, text, text, text) TO tally_app;
SET ROLE tally_app;
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000028b1', true);
SELECT public.assert_reference_version('rate_items', ('00000000-0000-4000-8000-00000000287' || g)::uuid, 1) FROM generate_series(1, 8) g;
SELECT pg_temp.admits('R1a a rate of four decimals',
  pg_temp.riv(1, 'per_unit_usage', ', rate_value', ', 0.4321'));
SELECT pg_temp.refuses_at('R1b a rate of five decimals',
  pg_temp.riv(2, 'per_unit_usage', ', rate_value', ', 0.43215'), '23514', 'rate_item_versions_rate_four_decimals_check');
SELECT pg_temp.refuses_at('R1c a negative rate of five decimals (a credit rider)',
  pg_temp.riv(2, 'per_unit_usage', ', rate_value', ', -0.00001'), '23514', 'rate_item_versions_rate_four_decimals_check');
SELECT pg_temp.refuses_at('R1e a rate that is not a number (NaN; r2, Fable S2)',
  pg_temp.riv(2, 'per_unit_usage', ', rate_value', $v$, 'NaN'$v$), '23514', 'rate_item_versions_rate_four_decimals_check');
SELECT pg_temp.admits('R1d a negative rate of four decimals',
  pg_temp.riv(2, 'per_unit_usage', ', rate_value', ', -12.0001'));
-- R5: a percentage (Ryan 2026-11-02, AC-45): 1.997% stored in percent is
-- accepted; the same rate as a fraction is refused by the check whose name
-- says to store it in percent; a fraction of four decimals still passes.
SELECT pg_temp.admits('R5a 1.997 percent, stored in percent',
  pg_temp.riv(7, 'percentage_of_charges', ', rate_value, rate_unit', $v$, 1.997, 'percent'$v$));
SELECT pg_temp.refuses_at('R5b the same rate as a fraction: refused by the check that says to store it in percent',
  pg_temp.riv(8, 'percentage_of_charges', ', rate_value, rate_unit', $v$, 0.01997, 'decimal'$v$), '23514', 'rate_item_versions_fraction_rate_store_as_percent_check');
SELECT pg_temp.refuses_at('R5c a fraction that is not a number',
  pg_temp.riv(8, 'percentage_of_charges', ', rate_value, rate_unit', $v$, 'NaN', 'decimal'$v$), '23514', 'rate_item_versions_fraction_rate_store_as_percent_check');
SELECT pg_temp.admits('R5d a fraction of four decimals still passes (the unit is retired later, AC-45)',
  pg_temp.riv(8, 'percentage_of_charges', ', rate_value, rate_unit', $v$, 0.0825, 'decimal'$v$));
SELECT pg_temp.admits('R2a tiers at four decimals',
  pg_temp.riv(3, 'tiered_usage', ', tier_config', $v$, '{"tiers": [{"label": "1", "floor": 0, "ceiling": 10.123456, "rate": 0.5}, {"label": "2", "floor": 10.123456, "ceiling": null, "rate": 0.4321}]}'$v$));
SELECT pg_temp.refuses_at('R2b a tier rate of five decimals',
  pg_temp.riv(4, 'tiered_usage', ', tier_config', $v$, '{"tiers": [{"label": "1", "floor": 0, "ceiling": 10, "rate": 0.5}, {"label": "2", "floor": 10, "ceiling": null, "rate": 0.43215}]}'$v$),
  '23514', 'rate_item_versions_tier_rates_four_decimals_check');
SELECT pg_temp.refuses_at('R2c a tier rate that is not a number',
  pg_temp.riv(4, 'tiered_usage', ', tier_config', $v$, '{"tiers": [{"label": "1", "floor": 0, "ceiling": null, "rate": "0.5"}]}'$v$),
  '23514', 'rate_item_versions_tier_rates_four_decimals_check');
-- Schedule overrides: RS28 (section D) carries R5 and R6.
SELECT pg_temp.refuses_at('R3a a schedule override of five decimals',
  $q$INSERT INTO public.rate_schedule_items (tenant_id, rate_schedule_id, rate_item_id, rate_override, effective_date)
     VALUES ('00000000-0000-4000-8000-0000000028a1', '00000000-0000-4000-8000-000000002841', '00000000-0000-4000-8000-000000002875', 1.23456, DATE '2026-01-01')$q$,
  '23514', 'rate_schedule_items_rate_override_four_decimals_check');
SELECT pg_temp.admits('R3b a schedule override of four decimals',
  $q$INSERT INTO public.rate_schedule_items (tenant_id, rate_schedule_id, rate_item_id, rate_override, effective_date)
     VALUES ('00000000-0000-4000-8000-0000000028a1', '00000000-0000-4000-8000-000000002841', '00000000-0000-4000-8000-000000002876', 1.2345, DATE '2026-01-01')$q$);
SELECT pg_temp.refuses_at('R3c a schedule override that is not a number (NaN; r2, Fable S2)',
  $q$INSERT INTO public.rate_schedule_items (tenant_id, rate_schedule_id, rate_item_id, rate_override, effective_date)
     VALUES ('00000000-0000-4000-8000-0000000028a1', '00000000-0000-4000-8000-000000002841', '00000000-0000-4000-8000-000000002875', 'NaN', DATE '2026-01-01')$q$,
  '23514', 'rate_schedule_items_rate_override_four_decimals_check');
RESET ROLE;
-- R6: every CHECK and exclusion constraint on a table in the public schema
-- reparses from the text the catalogue prints (r2, Opus B1; widened by the r2
-- review, Opus and Fable): pg_dump writes that text, so one that does not
-- reparse loses its whole table on restore. Each table gets one empty
-- scratch copy (LIKE: columns only), and each definition is fed back through
-- ALTER TABLE ... ADD CONSTRAINT. This proves the reparse, not a restore
-- (ordering, data, functions, ACLs): the real dump and restore is a separate
-- verification step.
DO $$
DECLARE t record; r record; n int := 0;
BEGIN
  FOR t IN SELECT DISTINCT c.conrelid FROM pg_constraint c JOIN pg_class k ON k.oid = c.conrelid JOIN pg_namespace s ON s.oid = k.relnamespace
            WHERE s.nspname = 'public' AND c.contype IN ('c', 'x') LOOP
    EXECUTE format('CREATE TEMP TABLE b28_reparse (LIKE %s)', t.conrelid::regclass);
    FOR r IN SELECT c.conname, pg_get_constraintdef(c.oid) AS def FROM pg_constraint c
              WHERE c.conrelid = t.conrelid AND c.contype IN ('c', 'x') LOOP
      BEGIN
        EXECUTE format('ALTER TABLE pg_temp.b28_reparse ADD CONSTRAINT %I %s', r.conname, r.def);
      EXCEPTION WHEN OTHERS THEN
        RAISE EXCEPTION 'FAIL R6: % on % does not reparse from its stored text (%): %', r.conname, t.conrelid::regclass, SQLERRM, r.def;
      END;
      n := n + 1;
    END LOOP;
    DROP TABLE pg_temp.b28_reparse;
  END LOOP;
  IF n < 300 THEN RAISE EXCEPTION 'FAIL R6: only % constraints found; the scan is not looking at the schema', n; END IF;
  RAISE NOTICE 'PASS R6 every CHECK and exclusion constraint in public (%) reparses from its stored text', n;
END $$;
SELECT pg_temp.ok('R6b the tier check is stored in the dump-safe form',
  (SELECT strpos(pg_get_constraintdef(oid), '(@ * 10000) % 1 != 0') > 0 FROM pg_constraint WHERE conname = 'rate_item_versions_tier_rates_four_decimals_check'));
SELECT pg_temp.ok('R4 the rate columns stay six-decimal (relaxing is dropping a check, no data moves)',
  (SELECT bool_and(numeric_scale = 6) FROM information_schema.columns
    WHERE table_schema = 'public' AND (table_name, column_name) IN (('rate_item_versions', 'rate_value'), ('rate_schedule_items', 'rate_override'))));

DO $$ BEGIN RAISE NOTICE 'battery-28: all checks passed'; END $$;
ROLLBACK;
