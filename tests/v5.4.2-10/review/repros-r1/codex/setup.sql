-- Shared fixture setup for adversarial testing of v5.4.2-10 on s10c.
-- NOT run in a single transaction across scripts; each attack script BEGIN/ROLLBACK's itself,
-- but fixtures here are committed so they persist for cross-session concurrency tests.

INSERT INTO public.tenants (id, name, slug) VALUES
  ('10000000-0000-4000-8000-00000000aa01', 'T1 Gasco', 'cdx10-t1'),
  ('10000000-0000-4000-8000-00000000aa02', 'T2 Otherco', 'cdx10-t2')
ON CONFLICT DO NOTHING;

INSERT INTO public.users (id, tenant_id, display_name, email, role) VALUES
  ('10000000-0000-4000-8000-00000000ab01', '10000000-0000-4000-8000-00000000aa01', 'U1', 'u1@cdx10.test', 'operator'),
  ('10000000-0000-4000-8000-00000000ab02', '10000000-0000-4000-8000-00000000aa02', 'U2', 'u2@cdx10.test', 'operator')
ON CONFLICT DO NOTHING;

INSERT INTO public.customers (id, tenant_id, customer_number) VALUES
  ('10000000-0000-4000-8000-00000000ac01', '10000000-0000-4000-8000-00000000aa01', 'CDX10-C1'),
  ('10000000-0000-4000-8000-00000000ac02', '10000000-0000-4000-8000-00000000aa02', 'CDX10-C2')
ON CONFLICT DO NOTHING;

INSERT INTO public.service_locations (id, tenant_id, customer_id, location_number, address_line1, city, state, zip) VALUES
  ('10000000-0000-4000-8000-00000000ad01', '10000000-0000-4000-8000-00000000aa01', '10000000-0000-4000-8000-00000000ac01', 'LOC-1', '1 Main', 'Austin', 'TX', '78701'),
  ('10000000-0000-4000-8000-00000000ad02', '10000000-0000-4000-8000-00000000aa02', '10000000-0000-4000-8000-00000000ac02', 'LOC-1', '2 Main', 'Austin', 'TX', '78701')
ON CONFLICT DO NOTHING;

INSERT INTO public.meters (id, tenant_id, meter_number, location_id, service_type) VALUES
  ('10000000-0000-4000-8000-00000000ae01', '10000000-0000-4000-8000-00000000aa01', 'M-1', '10000000-0000-4000-8000-00000000ad01', 'gas'),
  ('10000000-0000-4000-8000-00000000ae02', '10000000-0000-4000-8000-00000000aa02', 'M-1', '10000000-0000-4000-8000-00000000ad02', 'gas')
ON CONFLICT DO NOTHING;
