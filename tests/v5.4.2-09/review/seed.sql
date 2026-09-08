\set ON_ERROR_STOP on
BEGIN;
INSERT INTO public.tenants (id, name, slug) VALUES
  ('a0000000-0000-0000-0000-00000000000a', 'Fable Gas', 'fable-gas'),
  ('b0000000-0000-0000-0000-00000000000b', 'Other Gas', 'other-gas');
INSERT INTO public.users (id, tenant_id, display_name, email, role) VALUES
  ('a1000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-00000000000a', 'Fable Admin', 'fa@example.com', 'tenant_admin'),
  ('b1000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-00000000000b', 'Other Admin', 'oa@example.com', 'tenant_admin'),
  ('c1000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-00000000000a', 'Platform', 'pl@example.com', 'platform_admin');
INSERT INTO public.customers (id, tenant_id, customer_number) VALUES
  ('a2000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-00000000000a', 'CUST-001'),
  ('a2000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-00000000000a', 'CUST-002'),
  ('b2000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-00000000000b', 'CUST-B01');
COMMIT;
