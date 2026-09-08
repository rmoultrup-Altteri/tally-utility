BEGIN;
SET CONSTRAINTS ALL IMMEDIATE;

INSERT INTO public.tenants (id, name, slug, settings) VALUES
  ('00000000-0000-4000-8000-0000000000e1', 'E1 Gasco', 'bat9-e1', '{}');

INSERT INTO public.users (id, tenant_id, display_name, email, role) VALUES
  ('00000000-0000-4000-8000-0000000000e2', '00000000-0000-4000-8000-0000000000e1', 'UE', 'ue@bat9.test', 'operator');

INSERT INTO public.customers (id, tenant_id, customer_number) VALUES
  ('00000000-0000-4000-8000-0000000000e3', '00000000-0000-4000-8000-0000000000e1', 'BAT9-E3');

SET LOCAL app.user_id = '00000000-0000-4000-8000-0000000000e2';
SET ROLE tally_app;

-- Attempt: certificate_number is a single TAB character, not ASCII spaces.
-- btrim() with no explicit character set strips ONLY the ASCII space (0x20),
-- not tabs/newlines/NBSP. The gate's blank-check is
--   (NEW.certificate_number IS NULL OR btrim(NEW.certificate_number) = '')
-- so a tab character survives btrim and the row is treated as "has evidence".
INSERT INTO public.customer_tax_exemptions (id, tenant_id, customer_id, exemption_type, effective_start,
        certificate_number, status, verified_by, verified_at)
VALUES ('00000000-0000-4000-8000-0000000000e4', '00000000-0000-4000-8000-0000000000e1',
        '00000000-0000-4000-8000-0000000000e3', 'medical', CURRENT_DATE,
        E'\t', 'active', '00000000-0000-4000-8000-0000000000e2', now());

SELECT id, certificate_number, length(certificate_number) AS len, status
  FROM public.customer_tax_exemptions WHERE id = '00000000-0000-4000-8000-0000000000e4';

RESET ROLE;
ROLLBACK;
