BEGIN;
INSERT INTO public.tenants (id, name, slug, status, settings)
VALUES ('00000000-0000-4000-8000-00000000d001', 'Ancestor Malformed Tenant', 'ancestor-malformed', 'active',
        '{"tax_exemptions": "oops"}'::jsonb);

-- tax_exemptions itself (the grandparent of certificate_required) is a
-- scalar string, not an object. Round 2 added a shape check only for the
-- certificate_required NODE itself; does the same silent-default hole
-- persist one level up the tree?
SELECT public.tax_exemption_certificate_required(
  '00000000-0000-4000-8000-00000000d001'::uuid, 'non_profit'
) AS result_for_malformed_tax_exemptions_ancestor;

SELECT public.tax_exemption_renewal_notice_days(
  '00000000-0000-4000-8000-00000000d001'::uuid
) AS days_for_malformed_tax_exemptions_ancestor;
ROLLBACK;
