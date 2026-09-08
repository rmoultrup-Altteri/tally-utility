-- R2 PROBE 2: one void bill, two correction runs, two issued corrections; and the void
-- original's snapshot cannot be deleted.
BEGIN;
SET CONSTRAINTS ALL IMMEDIATE;
SET LOCAL app.user_id = '00000000-0000-4000-8000-0000000fa101';
SET ROLE tally_app;
SELECT public.fa_inv('00000000-0000-4000-8000-0000000fa821', 'FA-R2-ORIG', NULL, 'regular', NULL, '2026-05-01', '2026-05-31');
SELECT public.fa_snap('00000000-0000-4000-8000-0000000fa821', '2026-05-31', now());
UPDATE public.invoices SET status='pending' WHERE id='00000000-0000-4000-8000-0000000fa821';
SELECT (public.void_invoice('00000000-0000-4000-8000-0000000fa821', '00000000-0000-4000-8000-0000000fa101', 'wrong_rate', 'x', true)) IS NOT NULL AS voided;
SAVEPOINT d;
DELETE FROM public.invoice_calculation_snapshots WHERE invoice_id='00000000-0000-4000-8000-0000000fa821';
ROLLBACK TO d;
INSERT INTO public.billing_runs (id, tenant_id, run_number, billing_period, period_start, period_end, run_type, status, started_at, correction_rate_mode) VALUES
  ('00000000-0000-4000-8000-0000000fa921', '00000000-0000-4000-8000-0000000fa001', 'FA-R2-CRUN-2a', '2026-05', '2026-05-01', '2026-05-31', 'correction', 'in_progress', now(), 'historical'),
  ('00000000-0000-4000-8000-0000000fa922', '00000000-0000-4000-8000-0000000fa001', 'FA-R2-CRUN-2b', '2026-05', '2026-05-01', '2026-05-31', 'correction', 'in_progress', now(), 'historical');
INSERT INTO public.correction_run_targets (id, tenant_id, billing_run_id, voided_invoice_id, meter_id, customer_id) VALUES
  ('00000000-0000-4000-8000-0000000fab21', '00000000-0000-4000-8000-0000000fa001', '00000000-0000-4000-8000-0000000fa921', '00000000-0000-4000-8000-0000000fa821', '00000000-0000-4000-8000-0000000fa401', '00000000-0000-4000-8000-0000000fa201'),
  ('00000000-0000-4000-8000-0000000fab22', '00000000-0000-4000-8000-0000000fa001', '00000000-0000-4000-8000-0000000fa922', '00000000-0000-4000-8000-0000000fa821', '00000000-0000-4000-8000-0000000fa401', '00000000-0000-4000-8000-0000000fa201');
SELECT public.fa_inv('00000000-0000-4000-8000-0000000fa822', 'FA-R2-C2a', '00000000-0000-4000-8000-0000000fa921', 'correction', '00000000-0000-4000-8000-0000000fa821', '2026-05-01', '2026-05-31');
SELECT public.fa_inv('00000000-0000-4000-8000-0000000fa823', 'FA-R2-C2b', '00000000-0000-4000-8000-0000000fa922', 'correction', '00000000-0000-4000-8000-0000000fa821', '2026-05-01', '2026-05-31');
SELECT public.fa_snap('00000000-0000-4000-8000-0000000fa822', '2026-05-31', now());
SELECT public.fa_snap('00000000-0000-4000-8000-0000000fa823', '2026-05-31', now());
UPDATE public.invoices SET status='pending' WHERE id IN ('00000000-0000-4000-8000-0000000fa822','00000000-0000-4000-8000-0000000fa823');
SELECT count(*) AS live_corrections_of_one_void_bill FROM public.invoices WHERE replaces_invoice_id='00000000-0000-4000-8000-0000000fa821' AND status='pending';
ROLLBACK;
