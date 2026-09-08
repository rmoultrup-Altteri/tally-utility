BEGIN;
INSERT INTO public.tenants (id, name, slug, status, settings)
VALUES ('00000000-0000-4000-8000-00000000b001', 'Malformed Tenant', 'malformed-tenant', 'active',
        '{"tax_exemptions": {"certificate_required": false}}'::jsonb);

SELECT public.tax_exemption_certificate_required(
  '00000000-0000-4000-8000-00000000b001'::uuid, 'non_profit'
) AS result_for_non_object_certificate_required;
ROLLBACK;
