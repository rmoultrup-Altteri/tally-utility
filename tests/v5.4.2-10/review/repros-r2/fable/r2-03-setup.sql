SET app.user_id = '00000000-0000-4000-8000-0000000fa101';
SET ROLE tally_app;
SELECT public.fa_inv('00000000-0000-4000-8000-0000000fa831', 'FA-R2-ORIG3', NULL, 'regular', NULL, '2026-04-01', '2026-04-30');
SELECT public.fa_snap('00000000-0000-4000-8000-0000000fa831', '2026-04-30', now());
UPDATE public.invoices SET status='pending' WHERE id='00000000-0000-4000-8000-0000000fa831';
SELECT public.void_invoice('00000000-0000-4000-8000-0000000fa831', '00000000-0000-4000-8000-0000000fa101', 'wrong_rate', 'x', true) IS NOT NULL;
INSERT INTO public.billing_runs (id, tenant_id, run_number, billing_period, period_start, period_end, run_type, status, started_at, correction_rate_mode) VALUES
  ('00000000-0000-4000-8000-0000000fa931', '00000000-0000-4000-8000-0000000fa001', 'FA-R2-CRUN-3', '2026-04', '2026-04-01', '2026-04-30', 'correction', 'in_progress', now(), 'historical');
INSERT INTO public.correction_run_targets (id, tenant_id, billing_run_id, voided_invoice_id, meter_id, customer_id) VALUES
  ('00000000-0000-4000-8000-0000000fab31', '00000000-0000-4000-8000-0000000fa001', '00000000-0000-4000-8000-0000000fa931', '00000000-0000-4000-8000-0000000fa831', '00000000-0000-4000-8000-0000000fa401', '00000000-0000-4000-8000-0000000fa201');
SELECT public.fa_inv('00000000-0000-4000-8000-0000000fa832', 'FA-R2-C3', '00000000-0000-4000-8000-0000000fa931', 'correction', '00000000-0000-4000-8000-0000000fa831', '2026-04-01', '2026-04-30');
