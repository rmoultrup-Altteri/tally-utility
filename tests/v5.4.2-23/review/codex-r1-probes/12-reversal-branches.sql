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

INSERT INTO public.account_ledger (id,tenant_id,customer_id,transaction_date,transaction_type,description,amount,reverses_ledger_entry_id) VALUES
('00000000-0000-4000-8000-00000000cd01','00000000-0000-4000-8000-0000000023a1','00000000-0000-4000-8000-0000000023c1','2026-03-01','charge','root',100,NULL),
('00000000-0000-4000-8000-00000000cd02','00000000-0000-4000-8000-0000000023a1','00000000-0000-4000-8000-0000000023c1','2026-03-02','adjustment','branch A',-60,'00000000-0000-4000-8000-00000000cd01'),
('00000000-0000-4000-8000-00000000cd03','00000000-0000-4000-8000-0000000023a1','00000000-0000-4000-8000-0000000023c1','2026-03-02','adjustment','branch B',-40,'00000000-0000-4000-8000-00000000cd01'),
('00000000-0000-4000-8000-00000000cd04','00000000-0000-4000-8000-0000000023a1','00000000-0000-4000-8000-0000000023c1','2026-03-03','adjustment','undo A',20,'00000000-0000-4000-8000-00000000cd02');
SELECT pg_temp.attempt('branch B over-undo: root would be legal, B would not', $q$
INSERT INTO public.account_ledger (tenant_id,customer_id,transaction_date,transaction_type,description,amount,reverses_ledger_entry_id)
VALUES ('00000000-0000-4000-8000-0000000023a1','00000000-0000-4000-8000-0000000023c1','2026-03-04','adjustment','over undo B',41,'00000000-0000-4000-8000-00000000cd03')$q$);
SELECT pg_temp.attempt('root cap includes sibling B when posting under A', $q$
INSERT INTO public.account_ledger (tenant_id,customer_id,transaction_date,transaction_type,description,amount,reverses_ledger_entry_id)
VALUES ('00000000-0000-4000-8000-0000000023a1','00000000-0000-4000-8000-0000000023c1','2026-03-02','adjustment','early extra',-1,'00000000-0000-4000-8000-00000000cd01')$q$);
SELECT pg_temp.attempt('same-date peers net together despite row order', $q$
INSERT INTO public.account_ledger (id,tenant_id,customer_id,transaction_date,transaction_type,description,amount,reverses_ledger_entry_id) VALUES
('00000000-0000-4000-8000-00000000cd11','00000000-0000-4000-8000-0000000023a1','00000000-0000-4000-8000-0000000023c1','2026-03-01','charge','second root',100,NULL),
('00000000-0000-4000-8000-00000000cd12','00000000-0000-4000-8000-0000000023a1','00000000-0000-4000-8000-0000000023c1','2026-03-02','adjustment','peer debit',-120,'00000000-0000-4000-8000-00000000cd11'),
('00000000-0000-4000-8000-00000000cd13','00000000-0000-4000-8000-0000000023a1','00000000-0000-4000-8000-0000000023c1','2026-03-02','adjustment','same-day correction',20,'00000000-0000-4000-8000-00000000cd12')$q$);
SELECT public.ledger_entry_remaining('00000000-0000-4000-8000-00000000cd11') AS same_date_remaining;
ROLLBACK;
