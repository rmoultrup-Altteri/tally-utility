SET app.user_id = '00000000-0000-4000-8000-0000000fa101'; SET ROLE tally_app;
SELECT public.fa_inv('00000000-0000-4000-8000-0000000fa841', 'FA-R2-ORIG4', NULL, 'regular', NULL, '2026-02-01', '2026-02-28');
SELECT public.fa_snap('00000000-0000-4000-8000-0000000fa841', '2026-02-28', now());
UPDATE public.invoices SET status='pending' WHERE id='00000000-0000-4000-8000-0000000fa841';
SELECT public.void_invoice('00000000-0000-4000-8000-0000000fa841', '00000000-0000-4000-8000-0000000fa101', 'wrong_rate', 'x', true) IS NOT NULL;
INSERT INTO public.billing_runs (id, tenant_id, run_number, billing_period, period_start, period_end, run_type, status, started_at, correction_rate_mode) VALUES
  ('00000000-0000-4000-8000-0000000fa941', '00000000-0000-4000-8000-0000000fa001', 'FA-R2-CRUN-4', '2026-02', '2026-02-01', '2026-02-28', 'correction', 'in_progress', now(), 'historical');
INSERT INTO public.correction_run_targets (id, tenant_id, billing_run_id, voided_invoice_id, meter_id, customer_id) VALUES
  ('00000000-0000-4000-8000-0000000fab41', '00000000-0000-4000-8000-0000000fa001', '00000000-0000-4000-8000-0000000fa941', '00000000-0000-4000-8000-0000000fa841', '00000000-0000-4000-8000-0000000fa401', '00000000-0000-4000-8000-0000000fa201');
SELECT public.fa_inv('00000000-0000-4000-8000-0000000fa842', 'FA-R2-C4', '00000000-0000-4000-8000-0000000fa941', 'correction', '00000000-0000-4000-8000-0000000fa841', '2026-02-01', '2026-02-28');
