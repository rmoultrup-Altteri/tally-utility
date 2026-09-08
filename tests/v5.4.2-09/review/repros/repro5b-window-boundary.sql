BEGIN;
INSERT INTO public.tenants (id, name, slug, settings) VALUES
  ('00000000-0000-4000-8000-0000000000f1', 'F1 Gasco', 'bat9-f1', '{}');
INSERT INTO public.users (id, tenant_id, display_name, email, role) VALUES
  ('00000000-0000-4000-8000-0000000000f2', '00000000-0000-4000-8000-0000000000f1', 'UF', 'uf@bat9.test', 'operator');
INSERT INTO public.customers (id, tenant_id, customer_number) VALUES
  ('00000000-0000-4000-8000-0000000000f3', '00000000-0000-4000-8000-0000000000f1', 'BAT9-F3');
SET LOCAL app.user_id = '00000000-0000-4000-8000-0000000000f2';
SET ROLE tally_app;

-- One row with exactly 60 days remaining (should show if window truly is 60 days), one with 59.
INSERT INTO public.customer_tax_exemptions (id, tenant_id, customer_id, exemption_type, effective_start, effective_end,
        certificate_number, status, verified_by, verified_at)
VALUES
  ('00000000-0000-4000-8000-0000000000f4', '00000000-0000-4000-8000-0000000000f1', '00000000-0000-4000-8000-0000000000f3', 'medical', CURRENT_DATE - 400, CURRENT_DATE + 60, 'CERT-F4', 'active', '00000000-0000-4000-8000-0000000000f2', now()),
  ('00000000-0000-4000-8000-0000000000f5', '00000000-0000-4000-8000-0000000000f1', '00000000-0000-4000-8000-0000000000f3', 'religious', CURRENT_DATE - 400, CURRENT_DATE + 59, 'CERT-F5', 'active', '00000000-0000-4000-8000-0000000000f2', now());

SELECT exemption_id, effective_end - CURRENT_DATE AS actual_days_remaining, days_remaining, notice_window_opened_on, renewal_state
  FROM public.customer_tax_exemptions_renewal_due
 WHERE exemption_id IN ('00000000-0000-4000-8000-0000000000f4','00000000-0000-4000-8000-0000000000f5');

RESET ROLE;
ROLLBACK;
