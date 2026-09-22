-- ============================================================================
-- BATTERY v5.4.2-12 — A-2 backbilling caps
-- Run: psql -U tally -d <db-with-patch> -v ON_ERROR_STOP=1 -f battery-12.sql
-- One transaction, rolled back. Negative cases inside DO exception handlers.
-- End-to-end writes as tally_app (SET ROLE) with app.user_id context.
--
-- NOTE ON THE ENVIRONMENT (A-23 1g): CREATE DATABASE ... TEMPLATE does not
-- copy datacl, so this battery runs on a clone that HOLDS TEMP, which the
-- deployed database revokes. The pg_temp helpers below therefore work here
-- and would not in production — they are test scaffolding, not a claim about
-- the deployed shape.
-- ============================================================================
BEGIN;
SET CONSTRAINTS ALL IMMEDIATE;

-- ---------------------------------------------------------------- fixtures
INSERT INTO public.tenants (id, name, slug) VALUES
  ('00000000-0000-4000-8000-0000000012a1', 'T1 Gasco', 'bat12-t1'),
  ('00000000-0000-4000-8000-0000000012a2', 'T2 Rival', 'bat12-t2');
INSERT INTO public.users (id, tenant_id, display_name, email, role) VALUES
  ('00000000-0000-4000-8000-0000000012b1', '00000000-0000-4000-8000-0000000012a1', 'U1', 'u1@bat12.test', 'operator'),
  ('00000000-0000-4000-8000-0000000012b2', '00000000-0000-4000-8000-0000000012a2', 'U2', 'u2@bat12.test', 'operator');
INSERT INTO public.customers (id, tenant_id, customer_number, customer_type) VALUES
  ('00000000-0000-4000-8000-0000000012c1', '00000000-0000-4000-8000-0000000012a1', 'BAT12-C1', 'residential'),
  ('00000000-0000-4000-8000-0000000012c2', '00000000-0000-4000-8000-0000000012a1', 'BAT12-C2', 'large_commercial');
INSERT INTO public.jurisdictions (id, tenant_id, jurisdiction_code, jurisdiction_name) VALUES
  ('00000000-0000-4000-8000-0000000012f1', '00000000-0000-4000-8000-0000000012a1', 'CITYA', 'City A'),
  ('00000000-0000-4000-8000-0000000012f2', '00000000-0000-4000-8000-0000000012a1', 'CITYB', 'City B');
INSERT INTO public.service_locations (id, tenant_id, customer_id, location_number, address_line1, city, state, zip, jurisdiction_id) VALUES
  ('00000000-0000-4000-8000-0000000012d1', '00000000-0000-4000-8000-0000000012a1', '00000000-0000-4000-8000-0000000012c1', 'LOC-1', '1 Main', 'Austin', 'TX', '78701', '00000000-0000-4000-8000-0000000012f1');
INSERT INTO public.meters (id, tenant_id, meter_number, location_id, service_type, last_test_date) VALUES
  ('00000000-0000-4000-8000-0000000012e1', '00000000-0000-4000-8000-0000000012a1', 'M-1', '00000000-0000-4000-8000-0000000012d1', 'gas', '2026-01-10'),
  ('00000000-0000-4000-8000-0000000012e2', '00000000-0000-4000-8000-0000000012a1', 'M-2', '00000000-0000-4000-8000-0000000012d1', 'gas', NULL);

SELECT public.seed_backbilling_cap_defaults('00000000-0000-4000-8000-0000000012a1');
SELECT public.seed_backbilling_cap_defaults('00000000-0000-4000-8000-0000000012a2');

-- snapshot + invoice helpers (battery-10's shape)
CREATE FUNCTION pg_temp.snap(p_inv uuid, p_valid date, p_rec timestamptz) RETURNS void LANGUAGE plpgsql AS $$
DECLARE i public.invoices%ROWTYPE;
BEGIN
  SELECT * INTO i FROM public.invoices WHERE id = p_inv;
  INSERT INTO public.invoice_calculation_snapshots
    (tenant_id, invoice_id, billing_run_id, valid_at, recorded_at, snapshot_schema_version, formula_version,
     rate_inputs, gas_factors, wna_inputs, tax_inputs, read_inputs, customer_inputs, period_inputs, line_items)
  VALUES (i.tenant_id, i.id, i.billing_run_id, p_valid, p_rec, 'v1', 'bat12',
     '{"rate_schedule_id":null,"rate_schedule_version_id":null,"rate_schedule_code":null,"customer_type":null,"partial_period_policy":null,"items":[]}',
     '{"pga_factor":null,"btu_factor":null,"pressure_factor":null,"temperature_factor":null,"meter_multiplier":null,"factor_stack_intermediates":{}}',
     '{"applied":false}',
     '{"jurisdictions":[],"exemptions":[],"franchise_fees":[]}',
     '{"reads":[]}',
     jsonb_build_object('customer_id', i.customer_id, 'customer_class', null, 'location_id', i.location_id, 'premise_zones', '{}'::jsonb),
     jsonb_build_object('period_start', i.period_start, 'period_end', i.period_end, 'days_in_period', i.period_end - i.period_start + 1, 'proration_policy', null),
     (SELECT coalesce(jsonb_agg(jsonb_build_object('invoice_line_item_id', l.id, 'charge_type', l.charge_type, 'amount', l.amount)), '[]'::jsonb)
        FROM public.invoice_line_items l WHERE l.invoice_id = i.id));
END $$;
GRANT EXECUTE ON FUNCTION pg_temp.snap(uuid, date, timestamptz) TO tally_app;

CREATE FUNCTION pg_temp.inv(p_id uuid, p_num text, p_run uuid, p_type text, p_replaces uuid, p_ps date, p_pe date, p_amount numeric) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO public.invoices (id, tenant_id, invoice_number, billing_run_id, customer_id, location_id, invoice_type, replaces_invoice_id,
                               invoice_date, billing_period, period_start, period_end, due_date, amount_due)
  VALUES (p_id, '00000000-0000-4000-8000-0000000012a1', p_num, p_run, '00000000-0000-4000-8000-0000000012c1', '00000000-0000-4000-8000-0000000012d1',
          p_type, p_replaces, p_pe + 1, to_char(p_pe, 'YYYY-MM'), p_ps, p_pe, p_pe + 21, p_amount);
  INSERT INTO public.invoice_line_items (tenant_id, invoice_id, service_type, charge_type, description, amount)
  VALUES ('00000000-0000-4000-8000-0000000012a1', p_id, 'gas', 'base_charge', 'Customer charge', p_amount);
END $$;
GRANT EXECUTE ON FUNCTION pg_temp.inv(uuid, text, uuid, text, uuid, date, date, numeric) TO tally_app;

-- ============================================================================
-- GROUP A — the cap table's constraints (proved to REFUSE, not merely to pass)
-- ============================================================================
DO $$ DECLARE t uuid := '00000000-0000-4000-8000-0000000012a1';
BEGIN
  BEGIN
    INSERT INTO public.backbilling_cap_rules (tenant_id,jurisdiction_id,service_type,customer_class,cause,billable_scope,billable_months,enforceable_scope,source_note)
    VALUES (t,NULL,'gas','protected','meter_error','months_from_anchor',99,'never','dup');
    RAISE EXCEPTION 'A1 FAILED: a second NULL-jurisdiction default was accepted';
  EXCEPTION WHEN unique_violation THEN RAISE NOTICE 'PASS A1: UNIQUE NULLS NOT DISTINCT refuses a second state default (resolution stays deterministic)'; END;
  BEGIN
    INSERT INTO public.backbilling_cap_rules (tenant_id,jurisdiction_id,service_type,customer_class,cause,billable_scope,billable_months,enforceable_scope,source_note)
    VALUES (t,NULL,'water','protected','meter_error','uncapped',6,'never','x');
    RAISE EXCEPTION 'A2 FAILED: uncapped carried a month count';
  EXCEPTION WHEN check_violation THEN RAISE NOTICE 'PASS A2: uncapped + a stray month count refused'; END;
  BEGIN
    INSERT INTO public.backbilling_cap_rules (tenant_id,jurisdiction_id,service_type,customer_class,cause,billable_scope,billable_months,enforceable_scope,source_note)
    VALUES (t,NULL,'water','protected','meter_error','months_from_anchor',NULL,'never','x');
    RAISE EXCEPTION 'A3 FAILED: a counted billable scope accepted NULL months (the R-20 NULL-poisoning class, on the billable side)';
  EXCEPTION WHEN check_violation THEN RAISE NOTICE 'PASS A3: months_from_anchor with NULL months refused (F-7)'; END;
  BEGIN
    INSERT INTO public.backbilling_cap_rules (tenant_id,jurisdiction_id,service_type,customer_class,cause,billable_scope,enforceable_scope,enforceable_months,source_note)
    VALUES (t,NULL,'water','protected','meter_error','uncapped','never',6,'x');
    RAISE EXCEPTION 'A4 FAILED: enforceable never carried a month count';
  EXCEPTION WHEN check_violation THEN RAISE NOTICE 'PASS A4: enforceable never + months refused'; END;
  BEGIN
    INSERT INTO public.backbilling_cap_rules (tenant_id,jurisdiction_id,service_type,customer_class,cause,billable_scope,enforceable_scope,source_note)
    VALUES (t,NULL,'water','protected','meter_error','uncapped','never','   ');
    RAISE EXCEPTION 'A5 FAILED: a blank source_note was accepted';
  EXCEPTION WHEN check_violation THEN RAISE NOTICE 'PASS A5: a source_note of ASCII spaces refused (alnum whitelist, not btrim)'; END;
END $$;

DO $$ DECLARE n integer;
BEGIN
  n := public.seed_backbilling_cap_defaults('00000000-0000-4000-8000-0000000012a1');
  IF n <> 0 THEN RAISE EXCEPTION 'A6 FAILED: re-seeding inserted % row(s)', n; END IF;
  RAISE NOTICE 'PASS A6: seeding is idempotent — a tenant''s edited rule is never overwritten';
END $$;

-- ============================================================================
-- GROUP B — resolution (R-26 most-specific-wins over exactly two levels)
-- ============================================================================
DO $$
DECLARE t uuid := '00000000-0000-4000-8000-0000000012a1';
        j1 uuid := '00000000-0000-4000-8000-0000000012f1';
        j2 uuid := '00000000-0000-4000-8000-0000000012f2';
        r public.backbilling_cap_rules;
BEGIN
  r := public.backbilling_resolve_cap(t,j1,'gas','protected','meter_error');
  IF r.billable_scope <> 'shorter_of_months_or_last_test' OR r.billable_months <> 6 THEN
    RAISE EXCEPTION 'B1 FAILED: state default resolved as %/%', r.billable_scope, r.billable_months; END IF;
  RAISE NOTICE 'PASS B1: with no municipal row, the NULL-jurisdiction state default resolves';

  INSERT INTO public.backbilling_cap_rules (tenant_id,jurisdiction_id,service_type,customer_class,cause,billable_scope,billable_months,enforceable_scope,source_note)
  VALUES (t,j1,'gas','protected','meter_error','months_from_anchor',4,'never','City A ordinance 12-3 (lawfully established differing municipal standard)');
  r := public.backbilling_resolve_cap(t,j1,'gas','protected','meter_error');
  IF r.billable_months <> 4 THEN RAISE EXCEPTION 'B2 FAILED: City A got % months', r.billable_months; END IF;
  RAISE NOTICE 'PASS B2: a municipal row wins for its own jurisdiction';

  r := public.backbilling_resolve_cap(t,j2,'gas','protected','meter_error');
  IF r.billable_months <> 6 OR r.jurisdiction_id IS NOT NULL THEN
    RAISE EXCEPTION 'B3 FAILED: City B inherited another city''s rule (%/%)', r.jurisdiction_id, r.billable_months; END IF;
  RAISE NOTICE 'PASS B3: City A''s municipal row does NOT leak to City B — it falls to the state default';

  BEGIN
    r := public.backbilling_resolve_cap(t,NULL,'water','protected','meter_error');
    RAISE EXCEPTION 'B4 FAILED: an unconfigured service type returned a rule';
  EXCEPTION WHEN no_data_found THEN RAISE NOTICE 'PASS B4: an unconfigured cap FAILS CLOSED — an absent rule is not permission'; END;
END $$;

-- Remove the municipal row again: group E must exercise the STATE DEFAULT.
-- A group that silently governs a later group's fixture is how a battery
-- starts testing its own leftovers instead of the patch.
DELETE FROM public.backbilling_cap_rules WHERE jurisdiction_id = '00000000-0000-4000-8000-0000000012f1';

DO $$
DECLARE c1 uuid := '00000000-0000-4000-8000-0000000012c1';  -- residential
        c2 uuid := '00000000-0000-4000-8000-0000000012c2';  -- large_commercial
        t  uuid := '00000000-0000-4000-8000-0000000012a1';
BEGIN
  IF public.backbilling_customer_class(c2) <> 'protected' THEN
    RAISE EXCEPTION 'B5 FAILED: default mode did not protect a large_commercial account'; END IF;
  RAISE NOTICE 'PASS B5: under all_non_residential_protected even a large_commercial account is protected (CCK-14, errs toward protection)';

  UPDATE public.tenants SET regulatory_class_mode = 'explicit_class' WHERE id = t;
  IF public.backbilling_customer_class(c2) <> 'unprotected' THEN
    RAISE EXCEPTION 'B6 FAILED: explicit_class did not release a large_commercial account'; END IF;
  IF public.backbilling_customer_class(c1) <> 'protected' THEN
    RAISE EXCEPTION 'B6b FAILED: explicit_class released a residential account'; END IF;
  RAISE NOTICE 'PASS B6: explicit_class separates the classes; residential stays protected';

  UPDATE public.tenants SET regulatory_class_mode = 'volumetric_threshold' WHERE id = t;
  BEGIN
    PERFORM public.backbilling_customer_class(c2);
    RAISE EXCEPTION 'B7 FAILED: volumetric_threshold silently resolved';
  EXCEPTION WHEN feature_not_supported THEN
    RAISE NOTICE 'PASS B7: volumetric_threshold RAISES rather than degrading to the default (a mode that lied about itself would be a guard failing open)'; END;
  UPDATE public.tenants SET regulatory_class_mode = 'all_non_residential_protected' WHERE id = t;
END $$;

-- ============================================================================
-- GROUP C — R-30 classification (the platform-fixed mapping)
-- ============================================================================
DO $$
DECLARE got text;
BEGIN
  got := public.backbilling_read_classification('locked_gate','access_issue');
  IF got <> 'beyond_utility_control' THEN RAISE EXCEPTION 'C1 FAILED: %', got; END IF;
  RAISE NOTICE 'PASS C1: access_issue delegates to access_status, which carries the detail';

  got := public.backbilling_read_classification('ami_offline','access_issue');
  IF got <> 'within_utility_control' THEN RAISE EXCEPTION 'C2 FAILED: %', got; END IF;
  RAISE NOTICE 'PASS C2: ami_offline is WITHIN the utility''s control — protection stands';

  got := public.backbilling_read_classification('locked_gate','meter_malfunction');
  IF got <> 'within_utility_control' THEN RAISE EXCEPTION 'C3 FAILED: %', got; END IF;
  RAISE NOTICE 'PASS C3: where the two columns disagree the MORE CONSERVATIVE bucket wins';

  got := public.backbilling_read_classification(NULL,NULL);
  IF got <> 'determination_required' THEN RAISE EXCEPTION 'C4 FAILED: %', got; END IF;
  RAISE NOTICE 'PASS C4: a period with no read row classifies determination_required (R-30''s standing default)';

  got := public.backbilling_read_classification('accessed',NULL);
  IF got <> 'determination_required' THEN RAISE EXCEPTION 'C5 FAILED: %', got; END IF;
  RAISE NOTICE 'PASS C5: accessed contributes nothing — it must not read as "beyond control" by omission';

  got := public.backbilling_read_classification(NULL,'historical_average');
  IF got <> 'determination_required' THEN RAISE EXCEPTION 'C6 FAILED: %', got; END IF;
  RAISE NOTICE 'PASS C6: historical_average is METHOD not cause, so it carries no basis (R-30''s separate defect)';

  got := public.backbilling_read_classification('meter_buried','access_issue');
  IF got <> 'determination_required' THEN RAISE EXCEPTION 'C7 FAILED: %', got; END IF;
  RAISE NOTICE 'PASS C7: the four counsel-referral values sit in the safe third bucket';
END $$;

-- ============================================================================
-- GROUP D — the window (both sides of every boundary)
-- ============================================================================
DO $$
DECLARE d date;
BEGIN
  IF public.backbilling_window_start('uncapped',NULL,'2026-06-15',NULL,'customer_owes') IS NOT NULL THEN
    RAISE EXCEPTION 'D1 FAILED'; END IF;
  RAISE NOTICE 'PASS D1: uncapped has no window';

  IF public.backbilling_window_start('months_from_anchor',3,'2026-06-15',NULL,'customer_owes') <> '2026-03-15' THEN
    RAISE EXCEPTION 'D2 FAILED'; END IF;
  RAISE NOTICE 'PASS D2: 3 months back from a 2026-06-15 discovery anchor opens 2026-03-15';

  -- the SHORTER window is the LATER start: getting this backwards over-collects
  IF public.backbilling_window_start('shorter_of_months_or_last_test',6,'2026-06-15','2026-01-10','customer_owes') <> '2026-01-10' THEN
    RAISE EXCEPTION 'D3 FAILED'; END IF;
  RAISE NOTICE 'PASS D3: a test INSIDE the 6-month span shortens the window to the test date';

  IF public.backbilling_window_start('shorter_of_months_or_last_test',6,'2026-06-15','2025-06-01','customer_owes') <> '2025-12-15' THEN
    RAISE EXCEPTION 'D4 FAILED'; END IF;
  RAISE NOTICE 'PASS D4: a test OLDER than the span leaves the months bound standing';

  IF public.backbilling_window_start('shorter_of_months_or_last_test',6,'2026-06-15','2025-12-15','customer_owes') <> '2025-12-15' THEN
    RAISE EXCEPTION 'D5 FAILED'; END IF;
  IF public.backbilling_window_start('shorter_of_months_or_last_test',6,'2026-06-15','2025-12-16','customer_owes') <> '2025-12-16' THEN
    RAISE EXCEPTION 'D5b FAILED'; END IF;
  IF public.backbilling_window_start('shorter_of_months_or_last_test',6,'2026-06-15','2025-12-14','customer_owes') <> '2025-12-15' THEN
    RAISE EXCEPTION 'D5c FAILED'; END IF;
  RAISE NOTICE 'PASS D5: the boundary is pinned on the day itself and one day either side';

  IF public.backbilling_window_start('shorter_of_months_or_last_test',6,'2026-06-15',NULL,'customer_owed') <> '2025-12-15' THEN
    RAISE EXCEPTION 'D6 FAILED'; END IF;
  RAISE NOTICE 'PASS D6: with no recorded test a FAVOURABLE period still gets the months bound';

  BEGIN
    d := public.backbilling_window_start('shorter_of_months_or_last_test',6,'2026-06-15',NULL,'customer_owes');
    RAISE EXCEPTION 'D7 FAILED: an adverse period on an untested meter returned % instead of refusing', d;
  EXCEPTION WHEN no_data_found THEN
    RAISE NOTICE 'PASS D7: an adverse period on a meter with no recorded test REFUSES — no test date is ever derived from test_interval_months (R-31)'; END;
END $$;

-- ============================================================================
-- GROUP E — end to end: the two gates on a real correction
-- ============================================================================
-- The ORIGINAL bills, seeded as superuser with backdated run clocks (the
-- migration exemption standing in for "runs that happened earlier").
INSERT INTO public.billing_runs (id, tenant_id, run_number, billing_period, period_start, period_end, run_type, status, started_at) VALUES
  ('00000000-0000-4000-8000-0000000012b0', '00000000-0000-4000-8000-0000000012a1', 'RUN-2026-05', '2026-05', '2026-05-01', '2026-05-31', 'regular', 'in_progress', '2026-06-01 09:00-05'),
  ('00000000-0000-4000-8000-0000000012b3', '00000000-0000-4000-8000-0000000012a1', 'RUN-2025-01', '2025-01', '2025-01-01', '2025-01-31', 'regular', 'in_progress', '2025-02-01 09:00-05');

SELECT pg_temp.inv('00000000-0000-4000-8000-0000000012c0', 'INV-ORIG', '00000000-0000-4000-8000-0000000012b0', 'regular', NULL, '2026-05-01', '2026-05-31', 100.00);
SELECT pg_temp.snap('00000000-0000-4000-8000-0000000012c0', '2026-05-31', '2026-06-01 09:10-05');
UPDATE public.invoices SET status = 'pending' WHERE id = '00000000-0000-4000-8000-0000000012c0';
SELECT pg_temp.inv('00000000-0000-4000-8000-0000000012c3', 'INV-OLD', '00000000-0000-4000-8000-0000000012b3', 'regular', NULL, '2025-01-01', '2025-01-31', 100.00);
SELECT pg_temp.snap('00000000-0000-4000-8000-0000000012c3', '2025-01-31', '2025-02-01 09:10-05');
UPDATE public.invoices SET status = 'pending' WHERE id = '00000000-0000-4000-8000-0000000012c3';

SELECT public.void_invoice('00000000-0000-4000-8000-0000000012c0', '00000000-0000-4000-8000-0000000012b1', 'wrong_rate', 'battery: meter found fast', true);
SELECT public.void_invoice('00000000-0000-4000-8000-0000000012c3', '00000000-0000-4000-8000-0000000012b1', 'wrong_rate', 'battery: far outside the window', true);

-- the correction run
INSERT INTO public.billing_runs (id, tenant_id, run_number, billing_period, period_start, period_end, run_type, status, correction_rate_mode, started_at) VALUES
  ('00000000-0000-4000-8000-0000000012b4', '00000000-0000-4000-8000-0000000012a1', 'RUN-CORR', '2026-06', '2026-06-01', '2026-06-30', 'correction', 'in_progress', 'historical', now());

-- ------------------------------------------------------------ as tally_app
SET LOCAL app.user_id = '00000000-0000-4000-8000-0000000012b1';
SET ROLE tally_app;

-- E1: a target whose ENTIRE original period is before the window is refused
DO $$ BEGIN
  INSERT INTO public.correction_run_targets (id, tenant_id, billing_run_id, voided_invoice_id, meter_id, customer_id, location_id, rate_date_mode, backbill_cause, anchor_date)
  VALUES ('00000000-0000-4000-8000-0000000012d3', '00000000-0000-4000-8000-0000000012a1', '00000000-0000-4000-8000-0000000012b4',
          '00000000-0000-4000-8000-0000000012c3', '00000000-0000-4000-8000-0000000012e1', '00000000-0000-4000-8000-0000000012c1',
          '00000000-0000-4000-8000-0000000012d1', 'historical', 'meter_error', '2026-06-15');
  RAISE EXCEPTION 'E1 FAILED: a wholly out-of-window target was accepted';
EXCEPTION WHEN restrict_violation THEN
  RAISE NOTICE 'PASS E1: gate (ii) refuses a target whose whole period precedes the window (%)', left(SQLERRM, 80); END $$;

-- E2: the in-window target is accepted, and raises the under-reach warning
INSERT INTO public.correction_run_targets (id, tenant_id, billing_run_id, voided_invoice_id, meter_id, customer_id, location_id, rate_date_mode, backbill_cause, anchor_date)
VALUES ('00000000-0000-4000-8000-0000000012d0', '00000000-0000-4000-8000-0000000012a1', '00000000-0000-4000-8000-0000000012b4',
        '00000000-0000-4000-8000-0000000012c0', '00000000-0000-4000-8000-0000000012e1', '00000000-0000-4000-8000-0000000012c1',
        '00000000-0000-4000-8000-0000000012d1', 'historical', 'meter_error', '2026-06-15');
DO $$ DECLARE n integer; BEGIN
  SELECT count(*) INTO n FROM public.correction_run_target_events
   WHERE target_id = '00000000-0000-4000-8000-0000000012d0' AND event_type = 'underreach_warning_raised';
  IF n <> 1 THEN RAISE EXCEPTION 'E2 FAILED: % under-reach events', n; END IF;
  SELECT count(*) INTO n FROM public.correction_run_target_events
   WHERE target_id = '00000000-0000-4000-8000-0000000012d0' AND event_type = 'backbill_cause_set';
  IF n <> 1 THEN RAISE EXCEPTION 'E2b FAILED: cause not logged'; END IF;
  RAISE NOTICE 'PASS E2: gate (ii) accepts the in-window target, raises the under-reach warning and logs the cause';
END $$;

-- E3: the under-reach warning is meter_error ONLY — no noise on other causes
DO $$ DECLARE n integer; BEGIN
  UPDATE public.correction_run_targets SET backbill_cause = 'non_registering_meter', anchor_date = '2026-06-15'
   WHERE id = '00000000-0000-4000-8000-0000000012d0';
  SELECT count(*) INTO n FROM public.correction_run_target_events
   WHERE target_id = '00000000-0000-4000-8000-0000000012d0' AND event_type = 'underreach_warning_raised';
  IF n <> 1 THEN RAISE EXCEPTION 'E3 FAILED: a non-meter_error cause raised an under-reach warning (% total)', n; END IF;
  SELECT count(*) INTO n FROM public.correction_run_target_events
   WHERE target_id = '00000000-0000-4000-8000-0000000012d0' AND event_type = 'backbill_cause_changed';
  IF n <> 1 THEN RAISE EXCEPTION 'E3b FAILED: the cause change was not logged'; END IF;
  RAISE NOTICE 'PASS E3: only meter_error raises the under-reach warning ((v)(I) is the only mandatory bound); the change is logged';
  UPDATE public.correction_run_targets SET backbill_cause = 'meter_error' WHERE id = '00000000-0000-4000-8000-0000000012d0';
END $$;

-- the correction invoice: an ADVERSE correction (120 > 100)
SELECT pg_temp.inv('00000000-0000-4000-8000-0000000012c4', 'INV-CORR', '00000000-0000-4000-8000-0000000012b4', 'correction', '00000000-0000-4000-8000-0000000012c0', '2026-05-01', '2026-05-31', 120.00);

-- E4: issuance is refused while no per-period evaluation exists
DO $$ BEGIN
  UPDATE public.invoices SET status = 'pending' WHERE id = '00000000-0000-4000-8000-0000000012c4';
  RAISE EXCEPTION 'E4 FAILED: a correction issued with no evidence record';
EXCEPTION WHEN restrict_violation THEN
  RAISE NOTICE 'PASS E4: gate (iii) refuses issuance with no R-25 evaluation on the record (CI-008)'; END $$;

-- E5: the evaluation is written; direction is the database's arithmetic
DO $$ DECLARE e public.backbilling_period_evaluations%ROWTYPE; v_eid uuid; BEGIN
  v_eid := public.backbilling_evaluate_period('00000000-0000-4000-8000-0000000012d0', '00000000-0000-4000-8000-0000000012c4');
  SELECT * INTO e FROM public.backbilling_period_evaluations ev WHERE ev.id = v_eid;
  IF e.direction <> 'customer_owes' OR e.delta_amount <> 20.00 THEN
    RAISE EXCEPTION 'E5 FAILED: direction=% delta=%', e.direction, e.delta_amount; END IF;
  IF e.window_start <> '2026-01-10' THEN RAISE EXCEPTION 'E5b FAILED: window %', e.window_start; END IF;
  IF e.trimmed THEN RAISE EXCEPTION 'E5c FAILED: an in-window period was trimmed'; END IF;
  IF NOT e.underreach_warning THEN RAISE EXCEPTION 'E5d FAILED: the warning is not on the evidence row'; END IF;
  IF e.anchor_basis <> 'test_date' THEN RAISE EXCEPTION 'E5e FAILED: anchor_basis %', e.anchor_basis; END IF;
  IF e.read_classification <> 'determination_required' THEN RAISE EXCEPTION 'E5f FAILED: classification %', e.read_classification; END IF;
  RAISE NOTICE 'PASS E5: the evidence row carries direction, delta, window, classification and the warning — computed, never declared';
END $$;

-- E6: the under-reach warning BLOCKS issuance until an override is recorded
DO $$ BEGIN
  UPDATE public.invoices SET status = 'pending' WHERE id = '00000000-0000-4000-8000-0000000012c4';
  RAISE EXCEPTION 'E6 FAILED: issued with an unoverridden under-reach warning';
EXCEPTION WHEN restrict_violation THEN
  RAISE NOTICE 'PASS E6: gate (iii) refuses while the under-reach warning stands unoverridden (R-27)'; END $$;

-- ============================================================================
-- GROUP F — the override is the DATABASE's fact, not the application's
-- ============================================================================
-- F1: the caller cannot supply the clock or the actor
DO $$ DECLARE a timestamptz; b uuid; BEGIN
  UPDATE public.correction_run_targets
     SET underreach_override_reason = 'no_read_history',
         underreach_override_at     = '2020-01-01',
         underreach_override_by     = '00000000-0000-4000-8000-0000000012b2'
   WHERE id = '00000000-0000-4000-8000-0000000012d0';
  SELECT underreach_override_at, underreach_override_by INTO a, b
    FROM public.correction_run_targets WHERE id = '00000000-0000-4000-8000-0000000012d0';
  IF a <> now() THEN RAISE EXCEPTION 'F1 FAILED: caller-supplied override clock survived (%)', a; END IF;
  IF b <> '00000000-0000-4000-8000-0000000012b1' THEN RAISE EXCEPTION 'F1b FAILED: caller attributed the override to % ', b; END IF;
  RAISE NOTICE 'PASS F1: the override clock and actor are the database''s — a caller cannot backdate its own override or attribute it to someone else';
END $$;

-- F2: write-once — the override cannot be changed or cleared
DO $$ BEGIN
  UPDATE public.correction_run_targets SET underreach_override_reason = 'meter_replaced'
   WHERE id = '00000000-0000-4000-8000-0000000012d0';
  RAISE EXCEPTION 'F2 FAILED: the override was rewritten';
EXCEPTION WHEN restrict_violation THEN RAISE NOTICE 'PASS F2a: the override is write-once'; END $$;
DO $$ BEGIN
  UPDATE public.correction_run_targets SET underreach_override_reason = NULL, underreach_override_at = NULL
   WHERE id = '00000000-0000-4000-8000-0000000012d0';
  RAISE EXCEPTION 'F2b FAILED: the override was cleared';
EXCEPTION WHEN restrict_violation THEN RAISE NOTICE 'PASS F2b: the override cannot be cleared — the warning cannot be un-answered'; END $$;

-- F3: free text and unlisted grounds are refused (the narrow list, R-27)
DO $$ BEGIN
  INSERT INTO public.correction_run_targets (tenant_id, billing_run_id, voided_invoice_id, meter_id, customer_id, location_id, backbill_cause, anchor_date, underreach_override_reason)
  VALUES ('00000000-0000-4000-8000-0000000012a1','00000000-0000-4000-8000-0000000012b4','00000000-0000-4000-8000-0000000012c0',
          '00000000-0000-4000-8000-0000000012e1','00000000-0000-4000-8000-0000000012c1','00000000-0000-4000-8000-0000000012d1',
          'meter_error','2026-06-15','customer was nice about it');
  RAISE EXCEPTION 'F3 FAILED: free-text override accepted';
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'PASS F3: an unlisted override ground is refused (narrow-first: widening this CHECK later is one line)';
          WHEN restrict_violation THEN RAISE NOTICE 'PASS F3: an override supplied at INSERT is refused before the list is even consulted'; END $$;

-- F3b: and the narrow LIST itself refuses an unlisted ground. F3 above exits
-- through the INSERT guard, so on its own it proves the wrong thing — it
-- never reaches the CHECK it is cited for. This reaches it: a target with no
-- cause returns early from gate (ii), so the only thing left to refuse the
-- write is the reason-code domain.
INSERT INTO public.correction_run_targets (id, tenant_id, billing_run_id, voided_invoice_id, meter_id, customer_id, location_id)
VALUES ('00000000-0000-4000-8000-0000000012d9','00000000-0000-4000-8000-0000000012a1','00000000-0000-4000-8000-0000000012b4',
        '00000000-0000-4000-8000-0000000012c3','00000000-0000-4000-8000-0000000012e1','00000000-0000-4000-8000-0000000012c1',
        '00000000-0000-4000-8000-0000000012d1');
DO $$ BEGIN
  UPDATE public.correction_run_targets SET underreach_override_reason = 'customer was nice about it'
   WHERE id = '00000000-0000-4000-8000-0000000012d9';
  RAISE EXCEPTION 'F3b FAILED: free text was accepted as an override ground';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'PASS F3b: the reason-code CHECK itself refuses free text (R-27 narrowed: the statute permits foregoing a correction only where the error was to the UTILITY-S disadvantage)'; END $$;
DO $$ DECLARE a timestamptz; BEGIN
  UPDATE public.correction_run_targets SET underreach_override_reason = 'records_predate_acquisition'
   WHERE id = '00000000-0000-4000-8000-0000000012d9';
  SELECT underreach_override_at INTO a FROM public.correction_run_targets WHERE id = '00000000-0000-4000-8000-0000000012d9';
  IF a IS NULL THEN RAISE EXCEPTION 'F3c FAILED: a listed ground was accepted without being stamped'; END IF;
  RAISE NOTICE 'PASS F3c: a listed ground is accepted and stamped';
END $$;

-- F4: with the override recorded, issuance proceeds
SELECT pg_temp.snap('00000000-0000-4000-8000-0000000012c4', '2026-05-31', now());
DO $$ DECLARE st text; BEGIN
  UPDATE public.invoices SET status = 'pending' WHERE id = '00000000-0000-4000-8000-0000000012c4';
  SELECT status INTO st FROM public.invoices WHERE id = '00000000-0000-4000-8000-0000000012c4';
  IF st <> 'pending' THEN RAISE EXCEPTION 'F4 FAILED: status %', st; END IF;
  RAISE NOTICE 'PASS F4: with the evidentiary-impossibility ground on the record, gate (iii) lets the correction issue';
END $$;

-- F5: both logs are append-only
DO $$ BEGIN
  UPDATE public.correction_run_target_events SET event_type = 'backbill_cause_set'
   WHERE target_id = '00000000-0000-4000-8000-0000000012d0';
  RAISE EXCEPTION 'F5 FAILED: the target log was edited';
EXCEPTION WHEN restrict_violation THEN RAISE NOTICE 'PASS F5a: correction_run_target_events is append-only'; END $$;
DO $$ BEGIN
  DELETE FROM public.backbilling_period_evaluations WHERE target_id = '00000000-0000-4000-8000-0000000012d0';
  RAISE EXCEPTION 'F5b FAILED: an evidence row was deleted';
EXCEPTION WHEN restrict_violation THEN RAISE NOTICE 'PASS F5b: backbilling_period_evaluations is append-only — a re-evaluation is a new row, not an edit of the old answer'; END $$;

-- ============================================================================
-- GROUP G — the freeze extension (F-4)
-- ============================================================================
-- The correction's calculation snapshot was written at F4, above.
DO $$ BEGIN
  UPDATE public.correction_run_targets SET backbill_cause = 'tampering_theft'
   WHERE id = '00000000-0000-4000-8000-0000000012d0';
  RAISE EXCEPTION 'G1 FAILED: the cause moved under a snapshot';
EXCEPTION WHEN restrict_violation THEN
  RAISE NOTICE 'PASS G1: backbill_cause is frozen once a snapshot exists (F-4 — earlier than R-19''s "at post", because the snapshot is the frozen evidence)'; END $$;
DO $$ BEGIN
  UPDATE public.correction_run_targets SET anchor_date = '2026-07-01'
   WHERE id = '00000000-0000-4000-8000-0000000012d0';
  RAISE EXCEPTION 'G2 FAILED: the anchor moved under a snapshot';
EXCEPTION WHEN restrict_violation THEN RAISE NOTICE 'PASS G2: anchor_date is frozen with it'; END $$;
-- the column list and the early-return must agree: an unrelated update still passes
DO $$ BEGIN
  UPDATE public.correction_run_targets SET updated_at = now() WHERE id = '00000000-0000-4000-8000-0000000012d0';
  RAISE NOTICE 'PASS G3: an update that touches none of the frozen columns still passes (the column list and the early-return agree)';
END $$;

-- ============================================================================
-- GROUP H — tenant isolation on the three new tables, and AC-32
-- ============================================================================
RESET ROLE;
SET LOCAL app.user_id = '00000000-0000-4000-8000-0000000012b2';   -- tenant 2's operator
SET ROLE tally_app;
DO $$ DECLARE n integer; BEGIN
  SELECT count(*) INTO n FROM public.backbilling_cap_rules
   WHERE tenant_id = '00000000-0000-4000-8000-0000000012a1';
  IF n <> 0 THEN RAISE EXCEPTION 'H1 FAILED: tenant 2 sees % of tenant 1''s cap rules', n; END IF;
  SELECT count(*) INTO n FROM public.backbilling_period_evaluations;
  IF n <> 0 THEN RAISE EXCEPTION 'H1b FAILED: tenant 2 sees % evidence rows', n; END IF;
  SELECT count(*) INTO n FROM public.correction_run_target_events;
  IF n <> 0 THEN RAISE EXCEPTION 'H1c FAILED: tenant 2 sees % target events', n; END IF;
  RAISE NOTICE 'PASS H1: tenant 2 reads none of tenant 1''s cap rules, evidence rows or target events';
END $$;
-- the WRITE side: planting a row tagged with another tenant. No RETURNING —
-- it re-applies the SELECT policy and raises an RLS error that LOOKS like the
-- write was blocked, masking a write hole (a v5.4.2-11 failed approach).
DO $$ BEGIN
  INSERT INTO public.backbilling_cap_rules (tenant_id,jurisdiction_id,service_type,customer_class,cause,billable_scope,enforceable_scope,source_note)
  VALUES ('00000000-0000-4000-8000-0000000012a1',NULL,'water','protected','meter_error','uncapped','uncapped','planted');
  RAISE EXCEPTION 'H2 FAILED: tenant 2 planted a cap rule in tenant 1';
EXCEPTION WHEN insufficient_privilege THEN RAISE NOTICE 'PASS H2: a cross-tenant cap-rule write is refused by the policy''s WITH CHECK'; END $$;

RESET ROLE;
DO $$ BEGIN
  PERFORM public.assert_tenant_isolation_invariants();
  RAISE NOTICE 'PASS H3: AC-32 passes on the patched schema';
END $$;
-- and it must RAISE on planted drift, on THIS patch's own tables — a check
-- that has never failed is not evidence of anything.
DO $$ BEGIN
  ALTER TABLE public.backbilling_cap_rules DISABLE ROW LEVEL SECURITY;
  BEGIN
    PERFORM public.assert_tenant_isolation_invariants();
    RAISE EXCEPTION 'H4 FAILED: AC-32 passed with RLS off on a new table';
  EXCEPTION WHEN insufficient_privilege THEN RAISE NOTICE 'PASS H4: AC-32 RAISES on RLS-off'; END;
  ALTER TABLE public.backbilling_cap_rules ENABLE ROW LEVEL SECURITY;

  DROP POLICY tenant_isolation ON public.backbilling_period_evaluations;
  CREATE POLICY tenant_isolation ON public.backbilling_period_evaluations USING (true);
  BEGIN
    PERFORM public.assert_tenant_isolation_invariants();
    RAISE EXCEPTION 'H5 FAILED: AC-32 passed with USING (true)';
  EXCEPTION WHEN insufficient_privilege THEN RAISE NOTICE 'PASS H5: AC-32 RAISES on a permissive USING (true)'; END;
  DROP POLICY tenant_isolation ON public.backbilling_period_evaluations;
  CREATE POLICY tenant_isolation ON public.backbilling_period_evaluations USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));

  DROP POLICY tenant_isolation ON public.correction_run_target_events;
  CREATE POLICY tenant_isolation ON public.correction_run_target_events
    USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id()))) WITH CHECK (true);
  BEGIN
    PERFORM public.assert_tenant_isolation_invariants();
    RAISE EXCEPTION 'H6 FAILED: AC-32 passed with WITH CHECK (true)';
  EXCEPTION WHEN insufficient_privilege THEN RAISE NOTICE 'PASS H6: AC-32 RAISES on a read-isolated but WRITE-OPEN policy'; END;
  DROP POLICY tenant_isolation ON public.correction_run_target_events;
  CREATE POLICY tenant_isolation ON public.correction_run_target_events USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));

  ALTER TABLE public.correction_run_target_events NO FORCE ROW LEVEL SECURITY;
  BEGIN
    PERFORM public.assert_tenant_isolation_invariants();
    RAISE EXCEPTION 'H7 FAILED: AC-32 passed without FORCE';
  EXCEPTION WHEN insufficient_privilege THEN RAISE NOTICE 'PASS H7: AC-32 RAISES on a missing FORCE'; END;
  ALTER TABLE public.correction_run_target_events FORCE ROW LEVEL SECURITY;

  PERFORM public.assert_tenant_isolation_invariants();
  RAISE NOTICE 'PASS H8: AC-32 passes again once every planted drift is undone';
END $$;


-- ============================================================================
-- GROUP I — the evidence row must still describe the bill it lets through
-- ============================================================================
-- Found by the author before review, and reproduced end to end. The
-- evaluation is written against a DRAFT, and a draft's amount_due is not
-- frozen by the v5.4.2-10 snapshot guard (that guard freezes invoice_type,
-- replaces_invoice_id, billing_run_id, the period and created_at — not the
-- money). So: evaluate a small correction, inflate the draft, issue. Every
-- other check in gate (iii) passes — the cause matches, the evidence row
-- exists, the window was computed, nothing was trimmed.
--
-- This is the same shape as two entries already on the failed-approaches
-- list: later facts on a frozen bi-temporal row, and trusting a snapshot's
-- coordinate pair in a gate.
RESET ROLE;
SET LOCAL app.user_id = '00000000-0000-4000-8000-0000000012b1';
INSERT INTO public.billing_runs (id, tenant_id, run_number, billing_period, period_start, period_end, run_type, status, started_at) VALUES
  ('00000000-0000-4000-8000-0000000012b7','00000000-0000-4000-8000-0000000012a1','RUN-2026-04','2026-04','2026-04-01','2026-04-30','regular','in_progress','2026-05-01 09:00-05');
SELECT pg_temp.inv('00000000-0000-4000-8000-0000000012c7','INV-ORIG2','00000000-0000-4000-8000-0000000012b7','regular',NULL,'2026-04-01','2026-04-30',100.00);
SELECT pg_temp.snap('00000000-0000-4000-8000-0000000012c7','2026-04-30','2026-05-01 09:10-05');
UPDATE public.invoices SET status='pending' WHERE id='00000000-0000-4000-8000-0000000012c7';
SELECT public.void_invoice('00000000-0000-4000-8000-0000000012c7','00000000-0000-4000-8000-0000000012b1','wrong_rate','battery I fixture',true);

SET ROLE tally_app;
INSERT INTO public.correction_run_targets (id, tenant_id, billing_run_id, voided_invoice_id, meter_id, customer_id, location_id, backbill_cause, anchor_date)
VALUES ('00000000-0000-4000-8000-0000000012d7','00000000-0000-4000-8000-0000000012a1','00000000-0000-4000-8000-0000000012b4',
        '00000000-0000-4000-8000-0000000012c7','00000000-0000-4000-8000-0000000012e1','00000000-0000-4000-8000-0000000012c1',
        '00000000-0000-4000-8000-0000000012d1','rate_misapplication','2026-06-15');
SELECT pg_temp.inv('00000000-0000-4000-8000-0000000012c8','INV-CORR2','00000000-0000-4000-8000-0000000012b4','correction','00000000-0000-4000-8000-0000000012c7','2026-04-01','2026-04-30',105.00);

DO $$ DECLARE d numeric; BEGIN
  PERFORM public.backbilling_evaluate_period('00000000-0000-4000-8000-0000000012d7','00000000-0000-4000-8000-0000000012c8');
  SELECT delta_amount INTO d FROM public.backbilling_period_evaluations WHERE target_id='00000000-0000-4000-8000-0000000012d7' ORDER BY evaluation_seq DESC LIMIT 1;
  IF d <> 5.00 THEN RAISE EXCEPTION 'I0 FAILED: evaluated delta %', d; END IF;
  UPDATE public.invoices SET amount_due = 5000.00 WHERE id='00000000-0000-4000-8000-0000000012c8';
  PERFORM pg_temp.snap('00000000-0000-4000-8000-0000000012c8','2026-04-30',now());
  BEGIN
    UPDATE public.invoices SET status='pending' WHERE id='00000000-0000-4000-8000-0000000012c8';
    RAISE EXCEPTION 'I1 FAILED: issued a $5000 bill on evidence that describes a $5 one';
  EXCEPTION WHEN restrict_violation THEN
    RAISE NOTICE 'PASS I1: gate (iii) re-derives the delta and refuses evidence that no longer describes this bill';
  END;
END $$;

-- and re-evaluating unblocks it, because the log is append-only rather than editable
DO $$ DECLARE st text; n integer; BEGIN
  PERFORM public.backbilling_evaluate_period('00000000-0000-4000-8000-0000000012d7','00000000-0000-4000-8000-0000000012c8');
  SELECT count(*) INTO n FROM public.backbilling_period_evaluations WHERE target_id='00000000-0000-4000-8000-0000000012d7';
  IF n <> 2 THEN RAISE EXCEPTION 'I2 FAILED: % evidence rows (a re-evaluation must ADD a row)', n; END IF;
  UPDATE public.invoices SET status='pending' WHERE id='00000000-0000-4000-8000-0000000012c8';
  SELECT status INTO st FROM public.invoices WHERE id='00000000-0000-4000-8000-0000000012c8';
  IF st <> 'pending' THEN RAISE EXCEPTION 'I2b FAILED: status %', st; END IF;
  RAISE NOTICE 'PASS I2: re-evaluating APPENDS the current answer and issuance proceeds — the old answer is still on the record';
END $$;

ROLLBACK;
