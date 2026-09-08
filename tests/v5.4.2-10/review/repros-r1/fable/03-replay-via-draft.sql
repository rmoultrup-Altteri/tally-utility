-- ATTACK 3: "original world's truth" replay anchored on a DRAFT original whose snapshot
-- recorded_at was itself backdated via Attack 1. Gives a correction on a run started
-- today an arbitrary recorded_at.
BEGIN;
SET LOCAL app.user_id = '00000000-0000-4000-8000-0000000fa101';
SET ROLE tally_app;
SELECT public.fa_inv('00000000-0000-4000-8000-0000000fa521', 'FA-ORIG-DRAFT', NULL, 'regular', NULL, '2026-07-01', '2026-07-31');
UPDATE public.invoices SET created_at = '2021-05-05' WHERE id = '00000000-0000-4000-8000-0000000fa521';
SELECT public.fa_snap('00000000-0000-4000-8000-0000000fa521', '2026-07-31', '2021-05-05');
INSERT INTO public.billing_runs (id, tenant_id, run_number, billing_period, period_start, period_end, run_type, status, started_at, correction_rate_mode) VALUES
  ('00000000-0000-4000-8000-0000000fa621', '00000000-0000-4000-8000-0000000fa001', 'FA-CRUN-2', '2026-07', '2026-07-01', '2026-07-31', 'correction', 'in_progress', now(), 'historical');
INSERT INTO public.correction_run_targets (id, tenant_id, billing_run_id, voided_invoice_id, meter_id, customer_id) VALUES
  ('00000000-0000-4000-8000-0000000fa721', '00000000-0000-4000-8000-0000000fa001', '00000000-0000-4000-8000-0000000fa621', '00000000-0000-4000-8000-0000000fa521',
   '00000000-0000-4000-8000-0000000fa401', '00000000-0000-4000-8000-0000000fa201');
SELECT public.fa_inv('00000000-0000-4000-8000-0000000fa522', 'FA-CORR-REPLAY', '00000000-0000-4000-8000-0000000fa621', 'correction', '00000000-0000-4000-8000-0000000fa521', '2026-07-01', '2026-07-31');
SELECT public.fa_snap('00000000-0000-4000-8000-0000000fa522', '2026-07-31', '2021-05-05');
UPDATE public.invoices SET status = 'pending' WHERE id = '00000000-0000-4000-8000-0000000fa522';
SELECT i.invoice_number, i.status, s.valid_at, s.recorded_at, (SELECT started_at FROM public.billing_runs WHERE id = i.billing_run_id) AS run_started
  FROM public.invoices i JOIN public.invoice_calculation_snapshots s ON s.invoice_id = i.id WHERE i.id = '00000000-0000-4000-8000-0000000fa522';
-- and the original draft is still a draft, so its snapshot can now be deleted: the correction's anchor evaporates
DELETE FROM public.invoice_calculation_snapshots WHERE invoice_id = '00000000-0000-4000-8000-0000000fa521';
SELECT count(*) AS orig_snapshots_left FROM public.invoice_calculation_snapshots WHERE invoice_id = '00000000-0000-4000-8000-0000000fa521';
ROLLBACK;
