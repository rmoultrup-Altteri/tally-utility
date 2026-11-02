-- SOURCE-ONLY REVIEW: not executed by Codex.
-- Run as the owner on a fresh clone of tally with frozen r1 applied.
-- Revoke clone TEMP from PUBLIC, tally_app and tally_core before running.
-- No cluster role changes. All fixtures and helper functions roll back.
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL statement_timeout = '60s';
CREATE FUNCTION pg_temp.attempt(label text, statement text) RETURNS boolean
LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE statement;
  RAISE NOTICE '%: accepted (SQLSTATE 00000)', label;
  RETURN true;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '%: SQLSTATE=% MESSAGE=%', label, SQLSTATE, SQLERRM;
  RETURN false;
END $$;
GRANT EXECUTE ON FUNCTION pg_temp.attempt(text,text) TO tally_app, tally_core;
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
SELECT pg_temp.inv(50, NULL);                                             -- parent whose child is a parent
SELECT pg_temp.inv(51, NULL, 50);
SELECT pg_temp.inv(60, NULL);                                             -- parent: only a void child

CREATE FUNCTION pg_temp.snap(p_inv uuid, p_valid date, p_rec timestamptz) RETURNS void LANGUAGE plpgsql AS $$
DECLARE i public.invoices%ROWTYPE;
BEGIN
  SELECT * INTO i FROM public.invoices WHERE id = p_inv;
  INSERT INTO public.invoice_calculation_snapshots
    (tenant_id, invoice_id, billing_run_id, valid_at, recorded_at, snapshot_schema_version, formula_version,
     rate_inputs, gas_factors, wna_inputs, tax_inputs, read_inputs, customer_inputs, period_inputs, line_items)
  VALUES (i.tenant_id, i.id, i.billing_run_id, p_valid, p_rec, 'v1', 'bat21',
     '{"rate_schedule_id":null,"rate_schedule_version_id":null,"rate_schedule_code":null,"customer_type":null,"partial_period_policy":null,"items":[]}',
     '{"pga_factor":null,"btu_factor":null,"pressure_factor":null,"temperature_factor":null,"meter_multiplier":null,"factor_stack_intermediates":{}}',
     '{"applied":false}', '{"jurisdictions":[],"exemptions":[],"franchise_fees":[]}', '{"reads":[]}',
     jsonb_build_object('customer_id', i.customer_id, 'customer_class', null, 'location_id', i.location_id, 'premise_zones', '{}'::jsonb),
     jsonb_build_object('period_start', i.period_start, 'period_end', i.period_end, 'days_in_period', i.period_end - i.period_start + 1, 'proration_policy', null),
     (SELECT coalesce(jsonb_agg(jsonb_build_object('invoice_line_item_id', l.id, 'charge_type', l.charge_type, 'amount', l.amount)), '[]'::jsonb)
        FROM public.invoice_line_items l WHERE l.invoice_id = i.id));
END $$;
GRANT EXECUTE ON FUNCTION pg_temp.snap(uuid,date,timestamptz), pg_temp.inv(int,uuid,int,text) TO tally_app;
SET LOCAL ROLE tally_app;
SELECT public.customer_is_state_agency_as_of('00000000-0000-4000-8000-0000000028c1','2026-06-30','America/Denver') AS mountain_agency,
 public.customer_is_state_agency_as_of('00000000-0000-4000-8000-0000000028c1','2026-06-30','America/Chicago') AS central_agency,
 public.customer_is_state_agency_as_of('00000000-0000-4000-8000-0000000028c1','2019-01-01','America/Denver') AS earliest_fallback;
SELECT pg_temp.attempt('nested NULL-premise child control',$s$SELECT public.invoice_time_zone_as_of('00000000-0000-4000-8000-000000028950','2026-06-30')$s$);
SELECT pg_temp.attempt('B2 parent fee while Austin is the sole child',pg_temp.psf(40,2,1));
SELECT pg_temp.attempt('snapshot parent', $s$SELECT pg_temp.snap('00000000-0000-4000-8000-000000028940','2026-06-30',now())$s$);
SELECT pg_temp.attempt('issue parent', $s$UPDATE public.invoices SET status='pending' WHERE id='00000000-0000-4000-8000-000000028940'$s$);
RESET ROLE;
-- Flush ALL gates, not only the new helper; a failure here means issuance
-- was not proved and must be diagnosed before using the post-issue result.
SELECT pg_temp.attempt('all issuance constraints before child edit','SET CONSTRAINTS ALL IMMEDIATE');
SET LOCAL ROLE tally_app;
SELECT pg_temp.attempt('B2 change draft child premise after parent issuance', $s$
UPDATE public.invoices SET location_id='00000000-0000-4000-8000-0000000028d1'
WHERE id='00000000-0000-4000-8000-000000028941'$s$);
RESET ROLE;
SELECT pg_temp.attempt('all constraints after child edit','SET CONSTRAINTS ALL IMMEDIATE');
SELECT status,first_issued_at FROM public.invoices WHERE id='00000000-0000-4000-8000-000000028940';
SELECT public.invoice_time_zone_as_of('00000000-0000-4000-8000-000000028940','2026-06-30') AS parent_zone_after;
SELECT pg_temp.attempt('B2 existing fee fails if explicitly rechecked', $s$
SELECT public.assert_surcharge_line(l,now()) FROM public.invoice_line_items l WHERE invoice_id='00000000-0000-4000-8000-000000028940'$s$);
SET LOCAL ROLE tally_app;
SELECT pg_temp.attempt('B2 append conflicting live child to issued parent', $s$SELECT pg_temp.inv(43,'00000000-0000-4000-8000-0000000028d2',40)$s$);
SELECT pg_temp.attempt('mixed-zone parent now refuses lookup', $s$SELECT public.invoice_time_zone_as_of('00000000-0000-4000-8000-000000028940','2026-06-30')$s$);
-- The schema only says location IS NOT NULL OR consolidated. A child
-- which is itself a parent can carry a location, bypassing the NULL test.
SELECT pg_temp.attempt('B3 nested parent with a premise', $s$UPDATE public.invoices SET location_id='00000000-0000-4000-8000-0000000028d2' WHERE id='00000000-0000-4000-8000-000000028951'$s$);
SELECT pg_temp.attempt('B3 outer parent now gets a zone', $s$SELECT public.invoice_time_zone_as_of('00000000-0000-4000-8000-000000028950','2026-06-30')$s$);
SELECT pg_temp.attempt('B3 consolidated parent can itself carry a premise', $s$UPDATE public.invoices SET location_id='00000000-0000-4000-8000-0000000028d2' WHERE id='00000000-0000-4000-8000-000000028920'$s$);
SELECT pg_temp.attempt('B3 mixed children ignored when parent has premise', $s$SELECT public.invoice_time_zone_as_of('00000000-0000-4000-8000-000000028920','2026-06-30')$s$);
SELECT pg_temp.attempt('B3 fee accepted despite mixed children',pg_temp.psf(20,2,1));
SELECT pg_temp.attempt('L1 unknown county refuses', $s$SELECT public.invoice_time_zone_as_of('00000000-0000-4000-8000-000000028903','2026-06-30')$s$);
SELECT pg_temp.attempt('zero fee needs no zone',pg_temp.psf(3,4,0));
RESET ROLE;
SELECT to_regprocedure('public.customer_is_state_agency_as_of(uuid,date)') AS old_signature;
SELECT p.oid::regprocedure,p.prosrc FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND p.prosrc LIKE '%customer_is_state_agency_as_of%';
ROLLBACK;
