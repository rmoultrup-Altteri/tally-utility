-- Codex r1 SOURCE ONLY: NOT EXECUTED. Run as OWNER on a fresh disposable clone
-- with frozen r1 applied and TEMP revoked from PUBLIC, tally_app and tally_core.
-- Helpers/fixtures copied from frozen battery; no battery checks are run.
-- No roles are created/altered/dropped. All fixture writes roll back.
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL search_path=public,pg_temp;
-- u('c1') is the fixture uuid ending 26c1; id('name') a named record's uuid.
CREATE FUNCTION pg_temp.u(p_code text) RETURNS uuid LANGUAGE sql IMMUTABLE AS $$ SELECT ('00000000-0000-4000-8000-00000000' || '26' || p_code)::uuid $$;
CREATE FUNCTION pg_temp.id(p_name text) RETURNS uuid LANGUAGE sql IMMUTABLE AS $$ SELECT CASE WHEN p_name IS NULL THEN NULL ELSE md5('b26/' || p_name)::uuid END $$;
-- The database's current date, as -26 reads it (UTC).
CREATE FUNCTION pg_temp.today() RETURNS date LANGUAGE sql STABLE AS $$ SELECT (now() AT TIME ZONE 'UTC')::date $$;
CREATE FUNCTION pg_temp.as_user(p_code text) RETURNS void LANGUAGE sql AS $$ SELECT set_config('app.user_id', pg_temp.u(p_code)::text, true) $$;

-- dec(): a decision, as SQL. p_sup names the decision it supersedes.
CREATE FUNCTION pg_temp.dec(p_name text, p_act text, p_customer text, p_invoice text, p_loc text, p_meter text,
                            p_eval date, p_outcome text, p_active text[], p_uneval text[], p_gov text, p_until date,
                            p_sup text, p_fp text, p_tenant text DEFAULT 'a1') RETURNS text LANGUAGE sql STABLE AS $$
  SELECT format($q$INSERT INTO public.collections_decisions (id, tenant_id, customer_id, act, invoice_id, location_id, meter_id,
                     evaluation_date, outcome, active_conditions, unevaluable_conditions, governing_condition, valid_until,
                     supersedes_id, inputs, inputs_fingerprint, calculated_by)
                   VALUES (%L, %L, %L, %L, %L, %L, %L, %L, %L, %L::text[], %L::text[], %L, %L, %L, '{"bat26": true}', %L, 'core bat26')$q$,
                pg_temp.id(p_name), pg_temp.u(p_tenant), pg_temp.u(p_customer), p_act,
                CASE WHEN p_invoice IS NULL THEN NULL ELSE pg_temp.u(p_invoice) END,
                CASE WHEN p_loc IS NULL THEN NULL ELSE pg_temp.u(p_loc) END,
                CASE WHEN p_meter IS NULL THEN NULL ELSE pg_temp.u(p_meter) END,
                p_eval, p_outcome, coalesce(p_active, '{}'), coalesce(p_uneval, '{}'), p_gov, p_until, pg_temp.id(p_sup), p_fp)
$$;
-- ev(): a dunning event, as SQL.
CREATE FUNCTION pg_temp.ev(p_name text, p_invoice text, p_customer text, p_type text, p_at timestamptz, p_dec text,
                           p_new text DEFAULT NULL, p_prev text DEFAULT NULL) RETURNS text LANGUAGE sql STABLE AS $$
  SELECT format($q$INSERT INTO public.dunning_events (id, tenant_id, invoice_id, customer_id, event_type, event_date, collections_decision_id, new_stage, previous_stage)
                   VALUES (%L, %L, %L, %L, %L, %L, %L, %L, %L)$q$,
                pg_temp.id(p_name), pg_temp.u('a1'), pg_temp.u(p_invoice), pg_temp.u(p_customer), p_type, p_at, pg_temp.id(p_dec), p_new, p_prev)
$$;
-- chg(): an adhoc charge, as SQL.
CREATE FUNCTION pg_temp.chg(p_name text, p_customer text, p_invoice text, p_eff date, p_dec text, p_type text DEFAULT 'late_fee') RETURNS text LANGUAGE sql STABLE AS $$
  SELECT format($q$INSERT INTO public.adhoc_charges (id, tenant_id, charge_number, customer_id, charge_type, description, amount, regulatory_class,
                     effective_date, triggered_by_invoice_id, collections_decision_id)
                   VALUES (%L, %L, %L, %L, %L, 'bat26 charge', 5.00, 'regulated', %L, %L, %L)$q$,
                pg_temp.id(p_name), pg_temp.u('a1'), 'B26-' || p_name, pg_temp.u(p_customer), p_type, p_eff,
                CASE WHEN p_invoice IS NULL THEN NULL ELSE pg_temp.u(p_invoice) END, pg_temp.id(p_dec))
$$;
-- so(): a service order, as SQL.
CREATE FUNCTION pg_temp.so(p_name text, p_customer text, p_loc text, p_meter text, p_dec text,
                           p_type text DEFAULT 'disconnect', p_status text DEFAULT 'open') RETURNS text LANGUAGE sql STABLE AS $$
  SELECT format($q$INSERT INTO public.service_orders (id, tenant_id, order_number, order_type, status, description, customer_id, location_id, meter_id, collections_decision_id)
                   VALUES (%L, %L, %L, %L, %L, 'bat26 order', %L, %L, %L, %L)$q$,
                pg_temp.id(p_name), pg_temp.u('a1'), 'B26-' || p_name, p_type, p_status, pg_temp.u(p_customer), pg_temp.u(p_loc),
                CASE WHEN p_meter IS NULL THEN NULL ELSE pg_temp.u(p_meter) END, pg_temp.id(p_dec))
$$;
-- visit(): a field visit, as SQL.
CREATE FUNCTION pg_temp.visit(p_name text, p_order text, p_at timestamptz, p_serial text, p_locnum text, p_outcome text,
                              p_reason text, p_dec text, p_mm text, p_ne text, p_evidence text[], p_tenant text DEFAULT 'a1') RETURNS text LANGUAGE sql STABLE AS $$
  SELECT format($q$INSERT INTO public.service_order_field_visits (id, tenant_id, service_order_id, arrived_at, captured_meter_serial, captured_location_number,
                     outcome, abort_reason, collections_decision_id, mismatch_approval_id, no_evidence_approval_id, evidence_refs)
                   VALUES (%L, %L, %L, %L, %L, %L, %L, %L, %L, %L, %L, %L::text[])$q$,
                pg_temp.id(p_name), pg_temp.u(p_tenant), pg_temp.id(p_order), p_at, p_serial, p_locnum, p_outcome, p_reason,
                pg_temp.id(p_dec), pg_temp.id(p_mm), pg_temp.id(p_ne), coalesce(p_evidence, '{}'))
$$;
-- appr(): a supervisor's approval, as SQL.
CREATE FUNCTION pg_temp.appr(p_name text, p_order text, p_kind text, p_visit text, p_reason text, p_evidence text,
                             p_approved_by text DEFAULT NULL, p_tenant text DEFAULT 'a1') RETURNS text LANGUAGE sql STABLE AS $$
  SELECT format($q$INSERT INTO public.service_order_field_approvals (id, tenant_id, service_order_id, kind, visit_id, reason_code, evidence_ref, approved_by)
                   VALUES (%L, %L, %L, %L, %L, %L, %L, %L)$q$,
                pg_temp.id(p_name), pg_temp.u(p_tenant), pg_temp.id(p_order), p_kind, pg_temp.id(p_visit), p_reason, p_evidence,
                CASE WHEN p_approved_by IS NULL THEN NULL ELSE pg_temp.u(p_approved_by) END)
$$;
-- snap(), bill(): an issued bill (as battery-25).
CREATE FUNCTION pg_temp.snap(p_inv uuid, p_valid date, p_rec timestamptz) RETURNS void LANGUAGE plpgsql AS $$
DECLARE i public.invoices%ROWTYPE;
BEGIN
  SELECT * INTO i FROM public.invoices WHERE id = p_inv;
  INSERT INTO public.invoice_calculation_snapshots
    (tenant_id, invoice_id, billing_run_id, valid_at, recorded_at, snapshot_schema_version, formula_version,
     rate_inputs, gas_factors, wna_inputs, tax_inputs, read_inputs, customer_inputs, period_inputs, line_items)
  VALUES (i.tenant_id, i.id, i.billing_run_id, p_valid, p_rec, 'v1', 'bat26',
     '{"rate_schedule_id":null,"rate_schedule_version_id":null,"rate_schedule_code":null,"customer_type":null,"partial_period_policy":null,"items":[]}',
     '{"pga_factor":null,"btu_factor":null,"pressure_factor":null,"temperature_factor":null,"meter_multiplier":null,"factor_stack_intermediates":{}}',
     '{"applied":false}', '{"jurisdictions":[],"exemptions":[],"franchise_fees":[]}', '{"reads":[]}',
     jsonb_build_object('customer_id', i.customer_id, 'customer_class', null, 'location_id', i.location_id, 'premise_zones', '{}'::jsonb),
     jsonb_build_object('period_start', i.period_start, 'period_end', i.period_end, 'days_in_period', i.period_end - i.period_start + 1, 'proration_policy', null),
     (SELECT coalesce(jsonb_agg(jsonb_build_object('invoice_line_item_id', l.id, 'charge_type', l.charge_type, 'amount', l.amount)), '[]'::jsonb)
        FROM public.invoice_line_items l WHERE l.invoice_id = i.id));
END $$;
CREATE FUNCTION pg_temp.bill(p_tenant uuid, p_id uuid, p_num text, p_customer uuid, p_loc uuid, p_issue boolean) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO public.invoices (id, tenant_id, invoice_number, customer_id, location_id, is_consolidated, invoice_date, billing_period, period_start, period_end, due_date, amount_due)
  VALUES (p_id, p_tenant, p_num, p_customer, p_loc, p_loc IS NULL, DATE '2026-03-01', '2026-02', DATE '2026-02-01', DATE '2026-02-28', DATE '2026-03-20', 60.00);
  INSERT INTO public.invoice_line_items (tenant_id, invoice_id, line_order, service_type, charge_type, description, amount, rate, regulatory_class)
  VALUES (p_tenant, p_id, 0, 'gas', 'base_charge', 'Gas service', 60.00, 60.00, 'regulated');
  IF p_issue THEN
    PERFORM pg_temp.snap(p_id, DATE '2026-02-28', now());
    UPDATE public.invoices SET status = 'pending' WHERE id = p_id;
  END IF;
END $$;
DO $$
DECLARE f regprocedure;
BEGIN
  FOR f IN SELECT p.oid::regprocedure FROM pg_proc p WHERE p.pronamespace = pg_my_temp_schema() LOOP
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO tally_app', f);
  END LOOP;
END $$;

-- ------------------------------------------------------------------ fixtures
-- T1 (a1) a Texas city gas system; T2 (a2) another utility.
-- b1 an operator (the field tech's and the core's session), b2 a tenant_admin
-- (a supervisor), b3 T2's operator. c1, c2 T1's customers; c3 T2's.
-- Locations: d1 L1 (c1, meter e1), d2 L2 (c2, meter e2), d4 L4 (c1, no meter),
-- d5 L5 (c1: e5 until April 1, e7 from April 1), d6 L6 (c1: two meters, e8
-- and e9), d3 L3 (T2's). Bills 01 (c1 at d1), 02 (c1, no location), 03 (c2
-- at d2), 04 (c1, a draft), 05 (T2's). A bill with no location is a
-- consolidated one (invoices_check).
INSERT INTO public.tenants (id, name, slug) VALUES
  (pg_temp.u('a1'), 'T1 City Gas 26', 'bat26-t1'),
  (pg_temp.u('a2'), 'T2 Gas 26', 'bat26-t2');
INSERT INTO public.users (id, tenant_id, display_name, email, role, is_active) VALUES
  (pg_temp.u('b1'), pg_temp.u('a1'), 'Op1', 'op1@bat26.test', 'operator', true),
  (pg_temp.u('b2'), pg_temp.u('a1'), 'Sup1', 'sup1@bat26.test', 'tenant_admin', true),
  (pg_temp.u('b3'), pg_temp.u('a2'), 'Op3', 'op3@bat26.test', 'operator', true);
INSERT INTO public.customers (id, tenant_id, customer_number, customer_type) VALUES
  (pg_temp.u('c1'), pg_temp.u('a1'), 'B26-C1', 'residential'),
  (pg_temp.u('c2'), pg_temp.u('a1'), 'B26-C2', 'residential'),
  (pg_temp.u('c3'), pg_temp.u('a2'), 'B26-C3', 'residential');
INSERT INTO public.service_locations (id, tenant_id, customer_id, location_number, address_line1, city, state, zip) VALUES
  (pg_temp.u('d1'), pg_temp.u('a1'), pg_temp.u('c1'), 'L1', '1 Main', 'Brenham', 'TX', '77833'),
  (pg_temp.u('d2'), pg_temp.u('a1'), pg_temp.u('c2'), 'L2', '2 Main', 'Brenham', 'TX', '77833'),
  (pg_temp.u('d4'), pg_temp.u('a1'), pg_temp.u('c1'), 'L4', '4 Main', 'Brenham', 'TX', '77833'),
  (pg_temp.u('d5'), pg_temp.u('a1'), pg_temp.u('c1'), 'L5', '5 Main', 'Brenham', 'TX', '77833'),
  (pg_temp.u('d6'), pg_temp.u('a1'), pg_temp.u('c1'), 'L6', '6 Main', 'Brenham', 'TX', '77833'),
  (pg_temp.u('d3'), pg_temp.u('a2'), pg_temp.u('c3'), 'L3', '3 Main', 'Austin', 'TX', '78701');
INSERT INTO public.meters (id, tenant_id, meter_number, serial_number, location_id, service_type, start_date) VALUES
  (pg_temp.u('e1'), pg_temp.u('a1'), 'B26-M1', 'SN-E1', pg_temp.u('d1'), 'gas', DATE '2020-01-01'),
  (pg_temp.u('e2'), pg_temp.u('a1'), 'B26-M2', 'SN-E2', pg_temp.u('d2'), 'gas', DATE '2020-01-01'),
  (pg_temp.u('e5'), pg_temp.u('a1'), 'B26-M5', 'SN-E5', pg_temp.u('d5'), 'gas', DATE '2020-01-01'),
  (pg_temp.u('e8'), pg_temp.u('a1'), 'B26-M8', 'SN-E8', pg_temp.u('d6'), 'gas', DATE '2020-01-01'),
  (pg_temp.u('e9'), pg_temp.u('a1'), 'B26-M9', 'SN-E9', pg_temp.u('d6'), 'gas', DATE '2020-01-01'),
  (pg_temp.u('e3'), pg_temp.u('a2'), 'B26-M3', 'SN-E3', pg_temp.u('d3'), 'gas', DATE '2020-01-01');
-- e5 came out of L5 on April 1 (the owner's history path) and e7 went in.
UPDATE public.meter_deployments SET removal_date = DATE '2026-04-01', removal_reason = 'upgrade_size' WHERE meter_id = pg_temp.u('e5');
INSERT INTO public.meters (id, tenant_id, meter_number, serial_number, location_id, service_type, start_date) VALUES
  (pg_temp.u('e7'), pg_temp.u('a1'), 'B26-M7', 'SN-E7', pg_temp.u('d5'), 'gas', DATE '2026-04-01');
SELECT pg_temp.bill(pg_temp.u('a1'), pg_temp.u('01'), 'B26-I1', pg_temp.u('c1'), pg_temp.u('d1'), true);
SELECT pg_temp.bill(pg_temp.u('a1'), pg_temp.u('02'), 'B26-I2', pg_temp.u('c1'), NULL, true);
SELECT pg_temp.bill(pg_temp.u('a1'), pg_temp.u('03'), 'B26-I3', pg_temp.u('c2'), pg_temp.u('d2'), true);
SELECT pg_temp.bill(pg_temp.u('a1'), pg_temp.u('04'), 'B26-I4', pg_temp.u('c1'), pg_temp.u('d1'), false);
SELECT pg_temp.bill(pg_temp.u('a2'), pg_temp.u('05'), 'B26-I5', pg_temp.u('c3'), pg_temp.u('d3'), true);
-- A T2 order (a meter test) T1 cannot see.
INSERT INTO public.service_orders (id, tenant_id, order_number, order_type, description, customer_id, location_id, meter_id)
VALUES (pg_temp.id('SOT2'), pg_temp.u('a2'), 'B26-SOT2', 'meter_test', 'bat26 T2 order', pg_temp.u('c3'), pg_temp.u('d3'), pg_temp.u('e3'));


CREATE FUNCTION pg_temp.probe(label text,stmt text) RETURNS boolean LANGUAGE plpgsql AS $$
BEGIN EXECUTE stmt; RAISE NOTICE '%: ACCEPTED SQLSTATE=00000',label; RETURN true;
EXCEPTION WHEN OTHERS THEN RAISE NOTICE '%: REJECTED SQLSTATE=% MESSAGE=%',label,SQLSTATE,SQLERRM; RETURN false; END $$;
GRANT EXECUTE ON FUNCTION pg_temp.probe(text,text) TO tally_app,tally_core,tally_seal,tally_close,tally_void,tally_dispute;

SET LOCAL ROLE tally_app;
SELECT pg_temp.as_user('b1');
-- Consolidated notice exception is explicitly intentional (design C3, battery C3d2).
SELECT pg_temp.probe('consolidated notice',pg_temp.dec('CN','notice','c1','02','d4',NULL,pg_temp.today(),'eligible',NULL,NULL,NULL,pg_temp.today(),NULL,'cn'));
SELECT pg_temp.probe('order decision',pg_temp.dec('OD','disconnect_order','c1',NULL,'d1',NULL,pg_temp.today(),'eligible',NULL,NULL,NULL,pg_temp.today(),NULL,'od'));
SELECT pg_temp.probe('order for C1',pg_temp.so('SO','c1','d1',NULL,'OD'));
SELECT pg_temp.probe('C1 execute is blocked',pg_temp.dec('XB','disconnect_execute','c1',NULL,'d1',NULL,pg_temp.today(),'blocked',ARRAY['medical_hold'],NULL,'medical_hold',NULL,NULL,'xb'));
SELECT pg_temp.probe('transfer location to C2',format('UPDATE public.service_locations SET customer_id=%L WHERE id=%L',pg_temp.u('c2'),pg_temp.u('d1')));
SELECT pg_temp.probe('execute decision for C2',pg_temp.dec('XD','disconnect_execute','c2',NULL,'d1',NULL,pg_temp.today(),'eligible',NULL,NULL,NULL,pg_temp.today(),NULL,'xd'));
SELECT pg_temp.probe('B1 execute C1 order with C2 decision',pg_temp.visit('VX','SO',now(),'SN-E1','L1','executed',NULL,'XD',NULL,NULL,ARRAY['photo']));
SELECT o.customer_id AS order_customer,d.customer_id AS decision_customer,v.matched FROM public.service_order_field_visits v JOIN public.service_orders o ON o.id=v.service_order_id JOIN public.collections_decisions d ON d.id=v.collections_decision_id WHERE v.id=pg_temp.id('VX');
SELECT pg_temp.probe('order 2 decision',pg_temp.dec('OD2','disconnect_order','c1',NULL,'d5',NULL,pg_temp.today(),'eligible',NULL,NULL,NULL,pg_temp.today(),NULL,'od2'));
SELECT pg_temp.probe('order 2',pg_temp.so('SO2','c1','d5',NULL,'OD2'));
SELECT pg_temp.probe('execute 2 decision',pg_temp.dec('XD2','disconnect_execute','c1',NULL,'d5',NULL,pg_temp.today(),'eligible',NULL,NULL,NULL,pg_temp.today(),NULL,'xd2'));
SELECT pg_temp.as_user('b2');
SELECT pg_temp.probe('approval for SO',pg_temp.appr('AP','SO','no_evidence',NULL,'camera_failure',NULL));
SELECT pg_temp.as_user('b1');
SELECT pg_temp.probe('S1 wrong-order/wrong-kind surplus approval',pg_temp.visit('VX2','SO2',now(),'SN-E7','L5','executed',NULL,'XD2','AP','AP',ARRAY['photo']));
SELECT v.id,v.service_order_id,a.service_order_id AS approval_order,a.kind FROM public.service_order_field_visits v JOIN public.service_order_field_approvals a ON a.id=v.mismatch_approval_id;

RESET ROLE;
SELECT pg_temp.probe('deferred constraints','SET CONSTRAINTS ALL IMMEDIATE');
ROLLBACK;
