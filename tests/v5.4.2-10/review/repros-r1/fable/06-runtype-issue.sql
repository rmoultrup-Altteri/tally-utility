BEGIN;
SET CONSTRAINTS ALL IMMEDIATE;
SET LOCAL app.user_id = '00000000-0000-4000-8000-0000000fa101';
SET ROLE tally_app;
SELECT public.fa_inv('00000000-0000-4000-8000-0000000fa552', 'FA-VOIDME2', NULL, 'regular', NULL, '2026-05-01', '2026-05-31');
SELECT public.fa_snap('00000000-0000-4000-8000-0000000fa552', '2026-05-31', now());
UPDATE public.invoices SET status = 'pending' WHERE id = '00000000-0000-4000-8000-0000000fa552';
SELECT public.void_invoice('00000000-0000-4000-8000-0000000fa552', '00000000-0000-4000-8000-0000000fa101', 'wrong_rate', 'fa', true) ->> 'success' AS void_ok;
SELECT status AS voided_status FROM public.invoices WHERE id = '00000000-0000-4000-8000-0000000fa552';
INSERT INTO public.billing_runs (id, tenant_id, run_number, billing_period, period_start, period_end, run_type, status, started_at, correction_rate_mode) VALUES
  ('00000000-0000-4000-8000-0000000fa652', '00000000-0000-4000-8000-0000000fa001', 'FA-CRUN-6', '2026-05', '2026-05-01', '2026-05-31', 'correction', 'in_progress', now(), 'historical');
INSERT INTO public.correction_run_targets (id, tenant_id, billing_run_id, voided_invoice_id, meter_id, customer_id) VALUES
  ('00000000-0000-4000-8000-0000000fa752', '00000000-0000-4000-8000-0000000fa001', '00000000-0000-4000-8000-0000000fa652', '00000000-0000-4000-8000-0000000fa552',
   '00000000-0000-4000-8000-0000000fa401', '00000000-0000-4000-8000-0000000fa201');
SELECT public.fa_inv('00000000-0000-4000-8000-0000000fa553', 'FA-CORR-6', '00000000-0000-4000-8000-0000000fa652', 'correction', '00000000-0000-4000-8000-0000000fa552', '2026-05-01', '2026-05-31');
SELECT public.fa_snap('00000000-0000-4000-8000-0000000fa553', '2026-05-31', now());
UPDATE public.billing_runs SET run_type = 'off_cycle' WHERE id = '00000000-0000-4000-8000-0000000fa652';
SAVEPOINT s;
UPDATE public.invoices SET status = 'pending' WHERE id = '00000000-0000-4000-8000-0000000fa553';
ROLLBACK TO s;
-- legit flow check: correction run status moves to review/approved/posted; started_at untouched; issuance fine
UPDATE public.billing_runs SET run_type = 'correction', status = 'review' WHERE id = '00000000-0000-4000-8000-0000000fa652';
UPDATE public.invoices SET status = 'pending' WHERE id = '00000000-0000-4000-8000-0000000fa553';
SELECT status AS corr_status FROM public.invoices WHERE id = '00000000-0000-4000-8000-0000000fa553';
ROLLBACK;
