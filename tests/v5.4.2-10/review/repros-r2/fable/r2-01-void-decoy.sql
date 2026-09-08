-- R2 ATTACK 1: a never-issued draft, held then voided (a discard), satisfies status='void'.
-- Its period_end is attacker-chosen and now sealed. A correction for Aug-2026 "replaces" it.
BEGIN;
SET CONSTRAINTS ALL IMMEDIATE;
SET LOCAL app.user_id = '00000000-0000-4000-8000-0000000fa101';
SET ROLE tally_app;
SELECT public.fa_inv('00000000-0000-4000-8000-0000000fa811', 'FA-DISCARD', NULL, 'regular', NULL, '2024-01-01', '2024-01-31');
UPDATE public.invoices SET status='held', held_at=now(), held_by='00000000-0000-4000-8000-0000000fa101', hold_reason='x' WHERE id='00000000-0000-4000-8000-0000000fa811';
SELECT (public.void_invoice('00000000-0000-4000-8000-0000000fa811', '00000000-0000-4000-8000-0000000fa101', 'system_error', 'discard', true)) IS NOT NULL AS voided;
SELECT status AS discard_status, (SELECT count(*) FROM public.invoice_calculation_snapshots WHERE invoice_id='00000000-0000-4000-8000-0000000fa811') AS discard_snapshots FROM public.invoices WHERE id='00000000-0000-4000-8000-0000000fa811';
INSERT INTO public.billing_runs (id, tenant_id, run_number, billing_period, period_start, period_end, run_type, status, started_at, correction_rate_mode) VALUES
  ('00000000-0000-4000-8000-0000000fa911', '00000000-0000-4000-8000-0000000fa001', 'FA-R2-CRUN-1', '2026-08', '2026-08-01', '2026-08-31', 'correction', 'in_progress', now(), 'historical');
INSERT INTO public.correction_run_targets (id, tenant_id, billing_run_id, voided_invoice_id, meter_id, customer_id) VALUES
  ('00000000-0000-4000-8000-0000000fab11', '00000000-0000-4000-8000-0000000fa001', '00000000-0000-4000-8000-0000000fa911', '00000000-0000-4000-8000-0000000fa811',
   '00000000-0000-4000-8000-0000000fa401', '00000000-0000-4000-8000-0000000fa201');
SELECT public.fa_inv('00000000-0000-4000-8000-0000000fa812', 'FA-R2-CORR-DECOY', '00000000-0000-4000-8000-0000000fa911', 'correction', '00000000-0000-4000-8000-0000000fa811', '2026-08-01', '2026-08-31');
SELECT public.fa_snap('00000000-0000-4000-8000-0000000fa812', '2024-01-31', now());
UPDATE public.invoices SET status='pending' WHERE id='00000000-0000-4000-8000-0000000fa812';
SELECT i.invoice_number, i.status, i.period_start, i.period_end, s.valid_at FROM public.invoices i JOIN public.invoice_calculation_snapshots s ON s.invoice_id=i.id WHERE i.id='00000000-0000-4000-8000-0000000fa812';
ROLLBACK;
