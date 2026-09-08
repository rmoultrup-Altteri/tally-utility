BEGIN;
INSERT INTO public.tenants (id, name, slug, status, settings)
VALUES ('00000000-0000-4000-8000-00000000c001', 'Overflow Tenant', 'overflow-tenant', 'active',
        '{"tax_exemptions": {"renewal_notice_days_before": "99999999999999999999"}}'::jsonb);
SELECT public.tax_exemption_renewal_notice_days('00000000-0000-4000-8000-00000000c001'::uuid);
ROLLBACK;
