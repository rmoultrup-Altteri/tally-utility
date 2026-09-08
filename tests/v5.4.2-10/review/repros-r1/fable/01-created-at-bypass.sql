-- ATTACK 1: off-run lower bound. created_at is stamped on INSERT but freely UPDATEable
-- while no snapshot exists. Backdate it, then snapshot with a 2020 recorded_at.
BEGIN;
SET LOCAL app.user_id = '00000000-0000-4000-8000-0000000fa101';
SET ROLE tally_app;
SELECT public.fa_inv('00000000-0000-4000-8000-0000000fa501', 'FA-OFF-1', NULL, 'regular', NULL, '2026-03-01', '2026-03-31');
SELECT created_at AS created_at_after_insert FROM public.invoices WHERE id = '00000000-0000-4000-8000-0000000fa501';
UPDATE public.invoices SET created_at = '2020-01-01 00:00-06' WHERE id = '00000000-0000-4000-8000-0000000fa501';
SELECT created_at AS created_at_after_update FROM public.invoices WHERE id = '00000000-0000-4000-8000-0000000fa501';
SELECT public.fa_snap('00000000-0000-4000-8000-0000000fa501', '2026-03-31', '2020-01-01 00:00-06');
SELECT valid_at, recorded_at FROM public.invoice_calculation_snapshots WHERE invoice_id = '00000000-0000-4000-8000-0000000fa501';
UPDATE public.invoices SET status = 'pending' WHERE id = '00000000-0000-4000-8000-0000000fa501';
SELECT status FROM public.invoices WHERE id = '00000000-0000-4000-8000-0000000fa501';
COMMIT;
-- Variant: an on-run invoice re-homed off-run first (billing_run_id -> NULL), then the same.
BEGIN;
SET LOCAL app.user_id = '00000000-0000-4000-8000-0000000fa101';
SET ROLE tally_app;
INSERT INTO public.billing_runs (id, tenant_id, run_number, billing_period, period_start, period_end, run_type, status, started_at) VALUES
  ('00000000-0000-4000-8000-0000000fa601', '00000000-0000-4000-8000-0000000fa001', 'FA-RUN-1', '2026-03', '2026-03-01', '2026-03-31', 'regular', 'in_progress', now());
SELECT public.fa_inv('00000000-0000-4000-8000-0000000fa502', 'FA-RUN1-1', '00000000-0000-4000-8000-0000000fa601', 'regular', NULL, '2026-03-01', '2026-03-31');
UPDATE public.invoices SET billing_run_id = NULL, created_at = '2019-06-01' WHERE id = '00000000-0000-4000-8000-0000000fa502';
SELECT public.fa_snap('00000000-0000-4000-8000-0000000fa502', '2026-03-31', '2019-06-01');
SELECT valid_at, recorded_at FROM public.invoice_calculation_snapshots WHERE invoice_id = '00000000-0000-4000-8000-0000000fa502';
ROLLBACK;
