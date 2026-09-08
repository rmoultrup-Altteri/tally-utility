-- Repro: does a CURRENT (unsuperseded) revoked/expired customer_tax_exemptions row
-- lacking certificate evidence (a) survive the v5.4.2-09 precondition unblocked, and
-- (b) still suppress tax via should_charge_tax for dates within its valid bracket?

BEGIN;

INSERT INTO public.tenants (id, name, slug, status, settings)
VALUES ('00000000-0000-4000-8000-00000000a001', 'Repro Tenant', 'repro-tenant', 'active', '{}'::jsonb);

INSERT INTO public.users (id, tenant_id, display_name, email, role)
VALUES ('00000000-0000-4000-8000-00000000a002', '00000000-0000-4000-8000-00000000a001', 'Admin', 'admin@repro.test', 'tenant_admin');

INSERT INTO public.customers (id, tenant_id, customer_number)
VALUES ('00000000-0000-4000-8000-00000000a003', '00000000-0000-4000-8000-00000000a001', 'CUST-A001');

-- A revoked exemption, CURRENT (recorded_until IS NULL), NO certificate evidence.
-- Before v5.4.2-09 this is perfectly legal (no evidence gate exists pre-patch).
INSERT INTO public.customer_tax_exemptions
  (id, tenant_id, customer_id, exemption_type, status,
   effective_start, effective_end,
   verified_by, verified_at, revoked_by, revoked_at,
   certificate_number, certificate_url, change_type)
VALUES
  ('00000000-0000-4000-8000-00000000a004', '00000000-0000-4000-8000-00000000a001',
   '00000000-0000-4000-8000-00000000a003', 'non_profit', 'revoked',
   '2024-01-01', '2024-06-30',
   '00000000-0000-4000-8000-00000000a002', now(), '00000000-0000-4000-8000-00000000a002', now(),
   NULL, NULL, 'initial');

-- Confirm it's the CURRENT row (recorded_until IS NULL) with no evidence.
SELECT id, status, recorded_at, recorded_until, certificate_number, certificate_url, effective_start, effective_end
  FROM public.customer_tax_exemptions WHERE id = '00000000-0000-4000-8000-00000000a004';

COMMIT;
