BEGIN;
INSERT INTO public.tenants (id, name, slug, settings) VALUES
  ('00000000-0000-4000-8000-00000000bb01', 'Explicit Null TE', 'r3-null-te', '{"tax_exemptions": null}'::jsonb),
  ('00000000-0000-4000-8000-00000000bb02', 'Explicit Null CertReq', 'r3-null-cr', '{"tax_exemptions": {"certificate_required": null}}'::jsonb);

SELECT public.tax_exemption_certificate_required('00000000-0000-4000-8000-00000000bb01'::uuid, 'medical');
ROLLBACK;
