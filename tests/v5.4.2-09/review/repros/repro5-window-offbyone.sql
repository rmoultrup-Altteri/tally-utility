BEGIN;
INSERT INTO public.tenants (id, name, slug, settings) VALUES
  ('00000000-0000-4000-8000-0000000000f1', 'F1 Gasco', 'bat9-f1', '{}'); -- default 60-day window

INSERT INTO public.users (id, tenant_id, display_name, email, role) VALUES
  ('00000000-0000-4000-8000-0000000000f2', '00000000-0000-4000-8000-0000000000f1', 'UF', 'uf@bat9.test', 'operator');

INSERT INTO public.customers (id, tenant_id, customer_number) VALUES
  ('00000000-0000-4000-8000-0000000000f3', '00000000-0000-4000-8000-0000000000f1', 'BAT9-F3');

SET LOCAL app.user_id = '00000000-0000-4000-8000-0000000000f2';
SET ROLE tally_app;

-- effective_end exactly 60 days from today: with a 60-day notice window,
-- today (60 days out) should be the FIRST day the row is due for renewal
-- notice if "60 days before expiry" means what it says.
INSERT INTO public.customer_tax_exemptions (id, tenant_id, customer_id, exemption_type, effective_start, effective_end,
        certificate_number, status, verified_by, verified_at)
VALUES ('00000000-0000-4000-8000-0000000000f4', '00000000-0000-4000-8000-0000000000f1',
        '00000000-0000-4000-8000-0000000000f3', 'medical', CURRENT_DATE - 400, CURRENT_DATE + 60,
        'CERT-F4', 'active', '00000000-0000-4000-8000-0000000000f2', now());

-- Is the row visible in the renewal queue TODAY, when exactly 60 days remain?
SELECT exemption_id, effective_end, days_remaining, notice_window_opened_on, renewal_state
  FROM public.customer_tax_exemptions_renewal_due
 WHERE exemption_id = '00000000-0000-4000-8000-0000000000f4';

RESET ROLE;
ROLLBACK;
