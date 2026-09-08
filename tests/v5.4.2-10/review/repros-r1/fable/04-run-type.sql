-- ATTACK 4: billing_runs.run_type is read by the binding but not frozen.
BEGIN;
SET LOCAL app.user_id = '00000000-0000-4000-8000-0000000fa101';
SET ROLE tally_app;
INSERT INTO public.billing_runs (id, tenant_id, run_number, billing_period, period_start, period_end, run_type, status, started_at) VALUES
  ('00000000-0000-4000-8000-0000000fa631', '00000000-0000-4000-8000-0000000fa001', 'FA-RUN-3', '2026-03', '2026-03-01', '2026-03-31', 'regular', 'in_progress', now());
SELECT public.fa_inv('00000000-0000-4000-8000-0000000fa531', 'FA-RUN3-1', '00000000-0000-4000-8000-0000000fa631', 'regular', NULL, '2026-03-01', '2026-03-31');
SELECT public.fa_snap('00000000-0000-4000-8000-0000000fa531', '2026-03-31', now());
UPDATE public.billing_runs SET run_type = 'correction' WHERE id = '00000000-0000-4000-8000-0000000fa631';
SELECT run_type FROM public.billing_runs WHERE id = '00000000-0000-4000-8000-0000000fa631';
-- reverse: a correction run flipped to regular under a correction snapshot -> issuance false-refuses
ROLLBACK;
BEGIN;
SET LOCAL app.user_id = '00000000-0000-4000-8000-0000000fa101';
SET ROLE tally_app;
SELECT public.fa_inv('00000000-0000-4000-8000-0000000fa532', 'FA-VOIDME', NULL, 'regular', NULL, '2026-05-01', '2026-05-31');
SELECT public.fa_snap('00000000-0000-4000-8000-0000000fa532', '2026-05-31', now());
UPDATE public.invoices SET status = 'pending' WHERE id = '00000000-0000-4000-8000-0000000fa532';
SELECT public.void_invoice('00000000-0000-4000-8000-0000000fa532', '00000000-0000-4000-8000-0000000fa101', 'wrong_rate', 'fa', true) ->> 'status' AS void_result;
INSERT INTO public.billing_runs (id, tenant_id, run_number, billing_period, period_start, period_end, run_type, status, started_at, correction_rate_mode) VALUES
  ('00000000-0000-4000-8000-0000000fa632', '00000000-0000-4000-8000-0000000fa001', 'FA-CRUN-3', '2026-05', '2026-05-01', '2026-05-31', 'correction', 'in_progress', now(), 'historical');
INSERT INTO public.correction_run_targets (id, tenant_id, billing_run_id, voided_invoice_id, meter_id, customer_id) VALUES
  ('00000000-0000-4000-8000-0000000fa732', '00000000-0000-4000-8000-0000000fa001', '00000000-0000-4000-8000-0000000fa632', '00000000-0000-4000-8000-0000000fa532',
   '00000000-0000-4000-8000-0000000fa401', '00000000-0000-4000-8000-0000000fa201');
SELECT public.fa_inv('00000000-0000-4000-8000-0000000fa533', 'FA-CORR-3', '00000000-0000-4000-8000-0000000fa632', 'correction', '00000000-0000-4000-8000-0000000fa532', '2026-05-01', '2026-05-31');
SELECT public.fa_snap('00000000-0000-4000-8000-0000000fa533', '2026-05-31', now());
UPDATE public.billing_runs SET run_type = 'off_cycle' WHERE id = '00000000-0000-4000-8000-0000000fa632';
SAVEPOINT s;
UPDATE public.invoices SET status = 'pending' WHERE id = '00000000-0000-4000-8000-0000000fa533';
ROLLBACK TO s;
-- second correction for the SAME voided bill on the SAME run, same target row: both pass?
SELECT public.fa_inv('00000000-0000-4000-8000-0000000fa534', 'FA-CORR-3b', '00000000-0000-4000-8000-0000000fa632', 'correction', '00000000-0000-4000-8000-0000000fa532', '2026-05-01', '2026-05-31');
UPDATE public.billing_runs SET run_type = 'correction' WHERE id = '00000000-0000-4000-8000-0000000fa632';
SELECT public.fa_snap('00000000-0000-4000-8000-0000000fa534', '2026-05-31', now());
SELECT count(*) AS corrections_snapshotted_for_one_target FROM public.invoice_calculation_snapshots s JOIN public.invoices i ON i.id = s.invoice_id WHERE i.replaces_invoice_id = '00000000-0000-4000-8000-0000000fa532';
ROLLBACK;
