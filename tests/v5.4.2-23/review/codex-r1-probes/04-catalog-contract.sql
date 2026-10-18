-- PREDICTED; author-run only. Owner, fresh clone with frozen r1 applied.
-- No role DDL. Fixtures adapted from frozen battery; all changes roll back.
\set ON_ERROR_STOP on
BEGIN;
INSERT INTO public.tenants (id, name, slug) VALUES
  ('00000000-0000-4000-8000-0000000023a1', 'T1 City Gas', 'bat23-t1'),
  ('00000000-0000-4000-8000-0000000023a2', 'T2 Gasco', 'bat23-t2');
INSERT INTO public.users (id, tenant_id, display_name, email, role, is_active) VALUES
  ('00000000-0000-4000-8000-0000000023b1', '00000000-0000-4000-8000-0000000023a1', 'Op1', 'op1@bat23.test', 'operator', true),
  ('00000000-0000-4000-8000-0000000023b2', '00000000-0000-4000-8000-0000000023a2', 'Op2', 'op2@bat23.test', 'operator', true);
INSERT INTO public.customers (id, tenant_id, customer_number, customer_type) VALUES
  ('00000000-0000-4000-8000-0000000023c1', '00000000-0000-4000-8000-0000000023a1', 'B23-C1', 'residential'),
  ('00000000-0000-4000-8000-0000000023c2', '00000000-0000-4000-8000-0000000023a1', 'B23-C2', 'residential'),
  ('00000000-0000-4000-8000-0000000023c9', '00000000-0000-4000-8000-0000000023a2', 'B23-C9', 'residential');
INSERT INTO public.service_locations (id, tenant_id, customer_id, location_number, address_line1, city, state, zip) VALUES
  ('00000000-0000-4000-8000-0000000023d1', '00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c1', 'L1', '1 Main', 'Austin', 'TX', '78701'),
  ('00000000-0000-4000-8000-0000000023d2', '00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c2', 'L2', '2 Main', 'Austin', 'TX', '78701');
CREATE FUNCTION pg_temp.snap(p_inv uuid, p_valid date, p_rec timestamptz) RETURNS void LANGUAGE plpgsql AS $$
DECLARE i public.invoices%ROWTYPE;
BEGIN
  SELECT * INTO i FROM public.invoices WHERE id = p_inv;
  INSERT INTO public.invoice_calculation_snapshots
    (tenant_id, invoice_id, billing_run_id, valid_at, recorded_at, snapshot_schema_version, formula_version,
     rate_inputs, gas_factors, wna_inputs, tax_inputs, read_inputs, customer_inputs, period_inputs, line_items)
  VALUES (i.tenant_id, i.id, i.billing_run_id, p_valid, p_rec, 'v1', 'bat23',
     '{"rate_schedule_id":null,"rate_schedule_version_id":null,"rate_schedule_code":null,"customer_type":null,"partial_period_policy":null,"items":[]}',
     '{"pga_factor":null,"btu_factor":null,"pressure_factor":null,"temperature_factor":null,"meter_multiplier":null,"factor_stack_intermediates":{}}',
     '{"applied":false}', '{"jurisdictions":[],"exemptions":[],"franchise_fees":[]}', '{"reads":[]}',
     jsonb_build_object('customer_id', i.customer_id, 'customer_class', null, 'location_id', i.location_id, 'premise_zones', '{}'::jsonb),
     jsonb_build_object('period_start', i.period_start, 'period_end', i.period_end, 'days_in_period', i.period_end - i.period_start + 1, 'proration_policy', null),
     (SELECT coalesce(jsonb_agg(jsonb_build_object('invoice_line_item_id', l.id, 'charge_type', l.charge_type, 'amount', l.amount)), '[]'::jsonb)
        FROM public.invoice_line_items l WHERE l.invoice_id = i.id));
END $$;
CREATE FUNCTION pg_temp.bill(p_id uuid, p_num text, p_customer uuid, p_loc uuid, p_l1 uuid, p_l2 uuid, p_l3 uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO public.invoices (id, tenant_id, invoice_number, customer_id, location_id, invoice_date, billing_period, period_start, period_end, due_date, amount_due)
  VALUES (p_id, '00000000-0000-4000-8000-0000000023a1', p_num, p_customer, p_loc, DATE '2026-03-01', '2026-02', DATE '2026-02-01', DATE '2026-02-28', DATE '2026-03-20', 90.00);
  INSERT INTO public.invoice_line_items (id, tenant_id, invoice_id, line_order, service_type, charge_type, description, amount, rate, regulatory_class) VALUES
    (p_l1, '00000000-0000-4000-8000-0000000023a1', p_id, 0, 'gas', 'base_charge', 'Gas service', 60.00, 60.00, 'regulated'),
    (p_l2, '00000000-0000-4000-8000-0000000023a1', p_id, 1, 'general', 'misc', 'Appliance plan', 40.00, NULL, 'unregulated'),
    (p_l3, '00000000-0000-4000-8000-0000000023a1', p_id, 2, 'gas', 'credit', 'Goodwill', -10.00, NULL, 'regulated');
  PERFORM pg_temp.snap(p_id, DATE '2026-02-28', now());
  UPDATE public.invoices SET status = 'pending' WHERE id = p_id;
END $$;

CREATE FUNCTION pg_temp.attempt(label text, stmt text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
 EXECUTE stmt;
 RAISE NOTICE '%: SQLSTATE=00000 accepted', label;
EXCEPTION WHEN OTHERS THEN
 RAISE NOTICE '%: SQLSTATE=% message=%', label, SQLSTATE, SQLERRM;
END $$;

SELECT pg_temp.attempt('cash invariants baseline','SELECT public.assert_cash_guard_invariants()');
SELECT pg_temp.attempt('seal invariants baseline','SELECT public.assert_seal_role_invariants()');
SELECT pg_temp.attempt('period invariants baseline','SELECT public.assert_periods_guard_invariants()');
SELECT c.relname,pg_get_triggerdef(t.oid) FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid
 WHERE c.oid IN ('public.customer_credit_approvals'::regclass,'public.payments'::regclass,'public.customer_credits'::regclass) AND NOT t.tgisinternal ORDER BY c.relname,t.tgname;
-- S1: table-only privilege lookup does not include column UPDATE grants.
GRANT UPDATE (reason) ON public.invoice_applications TO tally_app;
SELECT has_column_privilege('tally_app','public.invoice_applications','reason','UPDATE') AS column_update,
       has_table_privilege('tally_app','public.invoice_applications','UPDATE') AS table_update;
SELECT pg_temp.attempt('S1 invariant after column grant','SELECT public.assert_cash_guard_invariants()');
-- The append-only trigger still protects data; this tests the claimed privilege invariant.


-- S2: demonstrate why I1/I2 do not prove their invariant functions ran.
ALTER TABLE public.invoice_applications DISABLE TRIGGER enforce_invoice_application;
SELECT public.assert_cash_guard_invariants() IS NULL OR true AS battery_I1_condition;
SELECT pg_temp.attempt('S2 direct invocation detects disabled trigger','SELECT public.assert_cash_guard_invariants()');
ROLLBACK;
