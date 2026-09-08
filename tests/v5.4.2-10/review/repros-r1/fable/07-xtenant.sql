-- cross-tenant: T2's invoice as the "voided" invoice of a T1 target; the resolver is SECURITY DEFINER.
RESET ROLE;
INSERT INTO public.tenants (id, name, slug) VALUES ('00000000-0000-4000-8000-0000000fa002', 'FA T2', 'fa-t2') ON CONFLICT DO NOTHING;
INSERT INTO public.users (id, tenant_id, display_name, email, role) VALUES ('00000000-0000-4000-8000-0000000fa102', '00000000-0000-4000-8000-0000000fa002', 'FA2', 'fa2@fa.test', 'operator') ON CONFLICT DO NOTHING;
INSERT INTO public.customers (id, tenant_id, customer_number) VALUES ('00000000-0000-4000-8000-0000000fa202', '00000000-0000-4000-8000-0000000fa002', 'FA-C2') ON CONFLICT DO NOTHING;
INSERT INTO public.service_locations (id, tenant_id, customer_id, location_number, address_line1, city, state, zip) VALUES
  ('00000000-0000-4000-8000-0000000fa302', '00000000-0000-4000-8000-0000000fa002', '00000000-0000-4000-8000-0000000fa202', 'FA-LOC-2', '2 Main', 'Austin', 'TX', '78701') ON CONFLICT DO NOTHING;
INSERT INTO public.invoices (id, tenant_id, invoice_number, customer_id, location_id, invoice_date, billing_period, period_start, period_end, due_date)
VALUES ('00000000-0000-4000-8000-0000000fa562', '00000000-0000-4000-8000-0000000fa002', 'T2-SECRET', '00000000-0000-4000-8000-0000000fa202', '00000000-0000-4000-8000-0000000fa302', '2023-12-01', '2023-11', '2023-11-01', '2023-11-30', '2023-12-22') ON CONFLICT DO NOTHING;
BEGIN;
SET LOCAL app.user_id = '00000000-0000-4000-8000-0000000fa101';
SET ROLE tally_app;
SELECT count(*) AS t2_invoices_visible_to_t1 FROM public.invoices WHERE id = '00000000-0000-4000-8000-0000000fa562';
INSERT INTO public.billing_runs (id, tenant_id, run_number, billing_period, period_start, period_end, run_type, status, started_at, correction_rate_mode) VALUES
  ('00000000-0000-4000-8000-0000000fa662', '00000000-0000-4000-8000-0000000fa001', 'FA-CRUN-X', '2026-05', '2026-05-01', '2026-05-31', 'correction', 'in_progress', now(), 'historical');
INSERT INTO public.correction_run_targets (id, tenant_id, billing_run_id, voided_invoice_id, meter_id, customer_id) VALUES
  ('00000000-0000-4000-8000-0000000fa762', '00000000-0000-4000-8000-0000000fa001', '00000000-0000-4000-8000-0000000fa662', '00000000-0000-4000-8000-0000000fa562',
   '00000000-0000-4000-8000-0000000fa401', '00000000-0000-4000-8000-0000000fa201');
SELECT public.fa_inv('00000000-0000-4000-8000-0000000fa563', 'FA-CORR-X', '00000000-0000-4000-8000-0000000fa662', 'correction', '00000000-0000-4000-8000-0000000fa562', '2026-05-01', '2026-05-31');
SELECT public.fa_snap('00000000-0000-4000-8000-0000000fa563', '2026-05-31', now());
ROLLBACK;
