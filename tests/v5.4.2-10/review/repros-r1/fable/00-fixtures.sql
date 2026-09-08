-- Fable review fixtures for s10c (committed). Prefix fa.
INSERT INTO public.tenants (id, name, slug) VALUES ('00000000-0000-4000-8000-0000000fa001', 'FA Gasco', 'fa-t1');
INSERT INTO public.users (id, tenant_id, display_name, email, role) VALUES
  ('00000000-0000-4000-8000-0000000fa101', '00000000-0000-4000-8000-0000000fa001', 'FA1', 'fa1@fa.test', 'operator');
INSERT INTO public.customers (id, tenant_id, customer_number) VALUES ('00000000-0000-4000-8000-0000000fa201', '00000000-0000-4000-8000-0000000fa001', 'FA-C1');
INSERT INTO public.service_locations (id, tenant_id, customer_id, location_number, address_line1, city, state, zip) VALUES
  ('00000000-0000-4000-8000-0000000fa301', '00000000-0000-4000-8000-0000000fa001', '00000000-0000-4000-8000-0000000fa201', 'FA-LOC-1', '1 Main', 'Austin', 'TX', '78701');
INSERT INTO public.meters (id, tenant_id, meter_number, location_id, service_type) VALUES
  ('00000000-0000-4000-8000-0000000fa401', '00000000-0000-4000-8000-0000000fa001', 'FA-M-1', '00000000-0000-4000-8000-0000000fa301', 'gas');

CREATE OR REPLACE FUNCTION public.fa_snap(p_inv uuid, p_valid date, p_rec timestamptz) RETURNS void LANGUAGE plpgsql AS $$
DECLARE i public.invoices%ROWTYPE;
BEGIN
  SELECT * INTO i FROM public.invoices WHERE id = p_inv;
  INSERT INTO public.invoice_calculation_snapshots
    (tenant_id, invoice_id, billing_run_id, valid_at, recorded_at, snapshot_schema_version, formula_version,
     rate_inputs, gas_factors, wna_inputs, tax_inputs, read_inputs, customer_inputs, period_inputs, line_items)
  VALUES (i.tenant_id, i.id, i.billing_run_id, p_valid, p_rec, 'v1', 'fa',
     '{"rate_schedule_id":null,"rate_schedule_version_id":null,"rate_schedule_code":null,"customer_type":null,"partial_period_policy":null,"items":[]}',
     '{"pga_factor":null,"btu_factor":null,"pressure_factor":null,"temperature_factor":null,"meter_multiplier":null,"factor_stack_intermediates":{}}',
     '{"applied":false}', '{"jurisdictions":[],"exemptions":[],"franchise_fees":[]}', '{"reads":[]}',
     jsonb_build_object('customer_id', i.customer_id, 'customer_class', null, 'location_id', i.location_id, 'premise_zones', '{}'::jsonb),
     jsonb_build_object('period_start', i.period_start, 'period_end', i.period_end, 'days_in_period', i.period_end - i.period_start + 1, 'proration_policy', null),
     (SELECT coalesce(jsonb_agg(jsonb_build_object('invoice_line_item_id', l.id, 'charge_type', l.charge_type, 'amount', l.amount)), '[]'::jsonb)
        FROM public.invoice_line_items l WHERE l.invoice_id = i.id));
END $$;
GRANT EXECUTE ON FUNCTION public.fa_snap(uuid, date, timestamptz) TO tally_app;

CREATE OR REPLACE FUNCTION public.fa_inv(p_id uuid, p_num text, p_run uuid, p_type text, p_replaces uuid, p_ps date, p_pe date) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO public.invoices (id, tenant_id, invoice_number, billing_run_id, customer_id, location_id, invoice_type, replaces_invoice_id,
                               invoice_date, billing_period, period_start, period_end, due_date)
  VALUES (p_id, '00000000-0000-4000-8000-0000000fa001', p_num, p_run, '00000000-0000-4000-8000-0000000fa201', '00000000-0000-4000-8000-0000000fa301',
          p_type, p_replaces, p_pe + 1, to_char(p_pe, 'YYYY-MM'), p_ps, p_pe, p_pe + 21);
  INSERT INTO public.invoice_line_items (tenant_id, invoice_id, service_type, charge_type, description, amount)
  VALUES ('00000000-0000-4000-8000-0000000fa001', p_id, 'gas', 'base_charge', 'Customer charge', 12.50);
END $$;
GRANT EXECUTE ON FUNCTION public.fa_inv(uuid, text, uuid, text, uuid, date, date) TO tally_app;
