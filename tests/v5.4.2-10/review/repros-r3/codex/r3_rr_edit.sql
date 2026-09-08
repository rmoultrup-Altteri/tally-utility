-- Confirm round-3 claim: RR edit of a never-snapshotted draft now SUCCEEDS (invoice + target),
-- while the billing_runs guard STILL refuses under RR (pin kept there).
BEGIN;
SET CONSTRAINTS ALL IMMEDIATE;
SET LOCAL app.user_id = '10000000-0000-4000-8000-00000000ab01';
SET ROLE tally_app;

INSERT INTO public.billing_runs (id, tenant_id, run_number, billing_period, period_start, period_end, run_type, status, started_at, correction_rate_mode)
VALUES ('10000000-0000-4000-8000-00000000b901', '10000000-0000-4000-8000-00000000aa01', 'CDX-R3-RR', '2025-09', '2025-09-01', '2025-09-30', 'correction', 'in_progress', now(), 'historical');

INSERT INTO public.invoices (id, tenant_id, invoice_number, customer_id, location_id, invoice_type, invoice_date, billing_period, period_start, period_end, due_date, status)
VALUES ('10000000-0000-4000-8000-00000000c901', '10000000-0000-4000-8000-00000000aa01', 'T1-R3-RR', '10000000-0000-4000-8000-00000000ac01', '10000000-0000-4000-8000-00000000ad01', 'regular', '2025-10-01', '2025-09', '2025-09-01', '2025-09-30', '2025-10-21', 'draft');

INSERT INTO public.correction_run_targets (id, tenant_id, billing_run_id, voided_invoice_id, meter_id, customer_id, rate_date_mode)
VALUES ('10000000-0000-4000-8000-00000000d901', '10000000-0000-4000-8000-00000000aa01', '10000000-0000-4000-8000-00000000b901', '10000000-0000-4000-8000-00000000c901', '10000000-0000-4000-8000-00000000ae01', '10000000-0000-4000-8000-00000000ac01', 'historical');
COMMIT;

BEGIN ISOLATION LEVEL REPEATABLE READ;
SET LOCAL app.user_id = '10000000-0000-4000-8000-00000000ab01';
SET ROLE tally_app;
DO $$
BEGIN
  UPDATE public.invoices SET period_end = '2025-10-01' WHERE id = '10000000-0000-4000-8000-00000000c901';
  RAISE NOTICE 'R3 RR-1: editing period_end on a never-snapshotted draft under REPEATABLE READ SUCCEEDED (expected fix)';
EXCEPTION WHEN invalid_transaction_state THEN
  RAISE NOTICE 'R3 RR-1 RESULT: still refused (regression): %', SQLERRM;
END $$;
ROLLBACK;

BEGIN ISOLATION LEVEL SERIALIZABLE;
SET LOCAL app.user_id = '10000000-0000-4000-8000-00000000ab01';
SET ROLE tally_app;
DO $$
BEGIN
  UPDATE public.correction_run_targets SET rate_date_mode = 'current' WHERE id = '10000000-0000-4000-8000-00000000d901';
  RAISE NOTICE 'R3 RR-2: editing rate_date_mode on a never-snapshotted target under SERIALIZABLE SUCCEEDED (expected fix)';
EXCEPTION WHEN invalid_transaction_state THEN
  RAISE NOTICE 'R3 RR-2 RESULT: still refused (regression): %', SQLERRM;
END $$;
ROLLBACK;

BEGIN ISOLATION LEVEL REPEATABLE READ;
SET LOCAL app.user_id = '10000000-0000-4000-8000-00000000ab01';
SET ROLE tally_app;
DO $$
BEGIN
  UPDATE public.billing_runs SET correction_rate_mode = 'current' WHERE id = '10000000-0000-4000-8000-00000000b901';
  RAISE NOTICE 'R3 RR-3: editing correction_rate_mode on a never-snapshotted run under REPEATABLE READ SUCCEEDED';
EXCEPTION WHEN invalid_transaction_state THEN
  RAISE NOTICE 'R3 RR-3 RESULT: still refused (expected -- pin kept on billing_runs): %', SQLERRM;
END $$;
ROLLBACK;
