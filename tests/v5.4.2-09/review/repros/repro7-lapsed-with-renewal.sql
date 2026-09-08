BEGIN;
INSERT INTO public.tenants (id, name, slug, settings) VALUES
  ('00000000-0000-4000-8000-00000000ab01', 'G1 Gasco', 'bat9-g1', '{}');
INSERT INTO public.users (id, tenant_id, display_name, email, role) VALUES
  ('00000000-0000-4000-8000-00000000ab02', '00000000-0000-4000-8000-00000000ab01', 'UG', 'ug@bat9.test', 'operator');
INSERT INTO public.customers (id, tenant_id, customer_number) VALUES
  ('00000000-0000-4000-8000-00000000ab03', '00000000-0000-4000-8000-00000000ab01', 'BAT9-G3');
SET LOCAL app.user_id = '00000000-0000-4000-8000-00000000ab02';
SET ROLE tally_app;

-- Old head: lapsed (effective_end in the past), still status='active', still open (recorded_until NULL).
INSERT INTO public.customer_tax_exemptions (id, tenant_id, customer_id, exemption_type, effective_start, effective_end,
        certificate_number, status, verified_by, verified_at)
VALUES ('00000000-0000-4000-8000-00000000ab04', '00000000-0000-4000-8000-00000000ab01',
        '00000000-0000-4000-8000-00000000ab03', 'medical', CURRENT_DATE - 400, CURRENT_DATE - 30,
        'CERT-OLD', 'active', '00000000-0000-4000-8000-00000000ab02', now());

-- A renewal on file: a later-bracketed, open, active row for the same customer+type.
INSERT INTO public.customer_tax_exemptions (id, tenant_id, customer_id, exemption_type, effective_start, effective_end,
        certificate_number, status, verified_by, verified_at)
VALUES ('00000000-0000-4000-8000-00000000ab05', '00000000-0000-4000-8000-00000000ab01',
        '00000000-0000-4000-8000-00000000ab03', 'medical', CURRENT_DATE - 20, CURRENT_DATE + 400,
        'CERT-NEW', 'active', '00000000-0000-4000-8000-00000000ab02', now());

SELECT exemption_id, effective_end, renewal_state
  FROM public.customer_tax_exemptions_renewal_due
 WHERE exemption_id IN ('00000000-0000-4000-8000-00000000ab04','00000000-0000-4000-8000-00000000ab05')
 ORDER BY effective_end;

RESET ROLE;
ROLLBACK;
