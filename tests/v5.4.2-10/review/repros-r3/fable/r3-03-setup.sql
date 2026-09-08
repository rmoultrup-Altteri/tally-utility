SET app.user_id = '00000000-0000-4000-8000-0000000fa101'; SET ROLE tally_app;
SELECT public.fa_inv('00000000-0000-4000-8000-0000000fc021', 'FA-R3-ORIG3', NULL, 'regular', NULL, '2026-06-01', '2026-06-30');
SELECT public.fa_snap('00000000-0000-4000-8000-0000000fc021', '2026-06-30', now());
UPDATE public.invoices SET status='pending' WHERE id='00000000-0000-4000-8000-0000000fc021';
SELECT public.void_invoice('00000000-0000-4000-8000-0000000fc021', '00000000-0000-4000-8000-0000000fa101', 'wrong_rate', 'x', true) IS NOT NULL;
INSERT INTO public.billing_runs (id, tenant_id, run_number, billing_period, period_start, period_end, run_type, status, started_at) VALUES
  ('00000000-0000-4000-8000-0000000fc921', '00000000-0000-4000-8000-0000000fa001', 'FA-R3-CR3', '2026-06', '2026-06-01', '2026-06-30', 'correction', 'in_progress', now());
INSERT INTO public.correction_run_targets (id, tenant_id, billing_run_id, voided_invoice_id, meter_id, customer_id) VALUES
  ('00000000-0000-4000-8000-0000000fcb21', '00000000-0000-4000-8000-0000000fa001', '00000000-0000-4000-8000-0000000fc921', '00000000-0000-4000-8000-0000000fc021', '00000000-0000-4000-8000-0000000fa401', '00000000-0000-4000-8000-0000000fa201');
SELECT public.fa_inv('00000000-0000-4000-8000-0000000fc022', 'FA-R3-C3', '00000000-0000-4000-8000-0000000fc921', 'correction', '00000000-0000-4000-8000-0000000fc021', '2026-06-01', '2026-06-30');
