BEGIN;

-- Tenant A: tax_exemptions present as an EMPTY object (legitimate: "no overrides set").
INSERT INTO public.tenants (id, name, slug, settings) VALUES
  ('00000000-0000-4000-8000-00000000ba01', 'Empty TE Object', 'r3-empty-te', '{"tax_exemptions": {}}'::jsonb);

-- Tenant B: tax_exemptions present with ONLY renewal_notice_days_before set
-- (legitimate: no certificate_required key at all).
INSERT INTO public.tenants (id, name, slug, settings) VALUES
  ('00000000-0000-4000-8000-00000000ba02', 'Only Renewal Days', 'r3-only-renewal', '{"tax_exemptions": {"renewal_notice_days_before": 45}}'::jsonb);

INSERT INTO public.users (id, tenant_id, display_name, email, role) VALUES
  ('00000000-0000-4000-8000-00000000ba03', '00000000-0000-4000-8000-00000000ba01', 'UA', 'ua@r3.test', 'operator'),
  ('00000000-0000-4000-8000-00000000ba04', '00000000-0000-4000-8000-00000000ba02', 'UB', 'ub@r3.test', 'operator');

INSERT INTO public.customers (id, tenant_id, customer_number) VALUES
  ('00000000-0000-4000-8000-00000000ba05', '00000000-0000-4000-8000-00000000ba01', 'R3-CA'),
  ('00000000-0000-4000-8000-00000000ba06', '00000000-0000-4000-8000-00000000ba02', 'R3-CB');

-- Does the deploy-time malformed-shape NOTICE false-positive on either legitimate shape?
-- (Re-run the precondition's own detection query directly against these two tenants.)
SELECT t.slug,
       (t.settings ? 'tax_exemptions' AND jsonb_typeof(t.settings -> 'tax_exemptions') <> 'object')
       OR (jsonb_typeof(t.settings -> 'tax_exemptions') = 'object'
           AND t.settings -> 'tax_exemptions' ? 'certificate_required'
           AND jsonb_typeof(t.settings #> '{tax_exemptions,certificate_required}') <> 'object')
       AS flagged_as_malformed
  FROM public.tenants t
 WHERE t.id IN ('00000000-0000-4000-8000-00000000ba01', '00000000-0000-4000-8000-00000000ba02');

-- Do the accessors themselves work normally (no spurious raise) for these tenants?
SELECT public.tax_exemption_certificate_required('00000000-0000-4000-8000-00000000ba01'::uuid, 'medical') AS empty_obj_default_true;
SELECT public.tax_exemption_renewal_notice_days('00000000-0000-4000-8000-00000000ba01'::uuid) AS empty_obj_default_60;
SELECT public.tax_exemption_certificate_required('00000000-0000-4000-8000-00000000ba02'::uuid, 'medical') AS only_renewal_set_default_true;
SELECT public.tax_exemption_renewal_notice_days('00000000-0000-4000-8000-00000000ba02'::uuid) AS only_renewal_set_is_45;

SET LOCAL app.user_id = '00000000-0000-4000-8000-00000000ba03';
SET ROLE tally_app;

-- Independent boundary check: exactly 60 days remaining (tenant A, default 60-day window).
INSERT INTO public.customer_tax_exemptions (id, tenant_id, customer_id, exemption_type, effective_start, effective_end,
        certificate_number, status, verified_by, verified_at)
VALUES ('00000000-0000-4000-8000-00000000ba07', '00000000-0000-4000-8000-00000000ba01',
        '00000000-0000-4000-8000-00000000ba05', 'medical', CURRENT_DATE - 400, CURRENT_DATE + 60,
        'CERT-BOUND-60', 'active', '00000000-0000-4000-8000-00000000ba03', now());

-- 61 days remaining: should be excluded.
INSERT INTO public.customer_tax_exemptions (id, tenant_id, customer_id, exemption_type, effective_start, effective_end,
        certificate_number, status, verified_by, verified_at)
VALUES ('00000000-0000-4000-8000-00000000ba08', '00000000-0000-4000-8000-00000000ba01',
        '00000000-0000-4000-8000-00000000ba05', 'religious', CURRENT_DATE - 400, CURRENT_DATE + 61,
        'CERT-BOUND-61', 'active', '00000000-0000-4000-8000-00000000ba03', now());

SELECT exemption_id, effective_end - CURRENT_DATE AS actual_days_remaining, days_remaining, notice_window_opened_on, renewal_state
  FROM public.customer_tax_exemptions_renewal_due
 WHERE exemption_id IN ('00000000-0000-4000-8000-00000000ba07','00000000-0000-4000-8000-00000000ba08')
 ORDER BY effective_end;

RESET ROLE;
ROLLBACK;
