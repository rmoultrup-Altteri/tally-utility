-- R2 ATTACK D: re-run — isolation-level false refusal on a NEVER-snapshotted draft/target/run.
BEGIN;
SET CONSTRAINTS ALL IMMEDIATE;

INSERT INTO public.billing_runs (id, tenant_id, run_number, billing_period, period_start, period_end, run_type, status, started_at, correction_rate_mode)
VALUES ('10000000-0000-4000-8000-00000000b601', '10000000-0000-4000-8000-00000000aa01', 'CDX-R2-D', '2025-08', '2025-08-01', '2025-08-31', 'correction', 'in_progress', now(), 'historical');

INSERT INTO public.invoices (id, tenant_id, invoice_number, customer_id, location_id, invoice_type, invoice_date, billing_period, period_start, period_end, due_date, status)
VALUES ('10000000-0000-4000-8000-00000000c601', '10000000-0000-4000-8000-00000000aa01', 'T1-D-R2', '10000000-0000-4000-8000-00000000ac01', '10000000-0000-4000-8000-00000000ad01', 'regular', '2025-09-01', '2025-08', '2025-08-01', '2025-08-31', '2025-09-21', 'draft');

SET LOCAL app.user_id = '10000000-0000-4000-8000-00000000ab01';
SET ROLE tally_app;
COMMIT;

BEGIN ISOLATION LEVEL REPEATABLE READ;
SET LOCAL app.user_id = '10000000-0000-4000-8000-00000000ab01';
SET ROLE tally_app;
DO $$
BEGIN
  UPDATE public.invoices SET period_end = '2025-09-01' WHERE id = '10000000-0000-4000-8000-00000000c601';
  RAISE NOTICE 'R2 D-1: editing period_end on a NEVER-snapshotted draft under REPEATABLE READ SUCCEEDED';
EXCEPTION WHEN invalid_transaction_state THEN
  RAISE NOTICE 'R2 D-1 RESULT: still refused under REPEATABLE READ despite zero snapshots anywhere: %', SQLERRM;
END $$;
ROLLBACK;

BEGIN;
SET LOCAL app.user_id = '10000000-0000-4000-8000-00000000ab01';
SET ROLE tally_app;
INSERT INTO public.correction_run_targets (id, tenant_id, billing_run_id, voided_invoice_id, meter_id, customer_id, rate_date_mode)
VALUES ('10000000-0000-4000-8000-00000000d601', '10000000-0000-4000-8000-00000000aa01', '10000000-0000-4000-8000-00000000b601', '10000000-0000-4000-8000-00000000c601', '10000000-0000-4000-8000-00000000ae01', '10000000-0000-4000-8000-00000000ac01', 'historical');
COMMIT;

BEGIN ISOLATION LEVEL SERIALIZABLE;
SET LOCAL app.user_id = '10000000-0000-4000-8000-00000000ab01';
SET ROLE tally_app;
DO $$
BEGIN
  UPDATE public.correction_run_targets SET rate_date_mode = 'current' WHERE id = '10000000-0000-4000-8000-00000000d601';
  RAISE NOTICE 'R2 D-2: editing rate_date_mode with ZERO snapshots under SERIALIZABLE SUCCEEDED';
EXCEPTION WHEN invalid_transaction_state THEN
  RAISE NOTICE 'R2 D-2 RESULT: still refused under SERIALIZABLE despite zero snapshots anywhere: %', SQLERRM;
END $$;
ROLLBACK;

BEGIN ISOLATION LEVEL REPEATABLE READ;
SET LOCAL app.user_id = '10000000-0000-4000-8000-00000000ab01';
SET ROLE tally_app;
DO $$
BEGIN
  UPDATE public.billing_runs SET correction_rate_mode = 'current' WHERE id = '10000000-0000-4000-8000-00000000b601';
  RAISE NOTICE 'R2 D-3: editing correction_rate_mode with ZERO snapshots under REPEATABLE READ SUCCEEDED';
EXCEPTION WHEN invalid_transaction_state THEN
  RAISE NOTICE 'R2 D-3 RESULT: still refused under REPEATABLE READ despite zero snapshots anywhere: %', SQLERRM;
END $$;
ROLLBACK;
