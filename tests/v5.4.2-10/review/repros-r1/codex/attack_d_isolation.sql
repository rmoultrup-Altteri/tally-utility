-- ATTACK D: does the isolation-level restriction fire even when NO snapshot exists to protect,
-- i.e. is the restriction unconditional on "column changing" rather than conditional on
-- "a snapshot actually exists that would be invisible under this isolation level"?
BEGIN;
SET CONSTRAINTS ALL IMMEDIATE;

INSERT INTO public.billing_runs (id, tenant_id, run_number, billing_period, period_start, period_end, run_type, status, started_at, correction_rate_mode)
VALUES ('10000000-0000-4000-8000-00000000b201', '10000000-0000-4000-8000-00000000aa01', 'CDX-D', '2025-08', '2025-08-01', '2025-08-31', 'correction', 'in_progress', now(), 'historical');

INSERT INTO public.invoices (id, tenant_id, invoice_number, customer_id, location_id, invoice_type, invoice_date, billing_period, period_start, period_end, due_date, status)
VALUES ('10000000-0000-4000-8000-00000000c201', '10000000-0000-4000-8000-00000000aa01', 'T1-D', '10000000-0000-4000-8000-00000000ac01', '10000000-0000-4000-8000-00000000ad01', 'regular', '2025-09-01', '2025-08', '2025-08-01', '2025-08-31', '2025-09-21', 'draft');

SET LOCAL app.user_id = '10000000-0000-4000-8000-00000000ab01';
SET ROLE tally_app;
COMMIT;

-- No snapshot exists anywhere. Fresh transaction under REPEATABLE READ. Just edit period_end
-- on a brand-new never-snapshotted draft invoice.
BEGIN ISOLATION LEVEL REPEATABLE READ;
SET LOCAL app.user_id = '10000000-0000-4000-8000-00000000ab01';
SET ROLE tally_app;
DO $$
BEGIN
  UPDATE public.invoices SET period_end = '2025-09-01' WHERE id = '10000000-0000-4000-8000-00000000c201';
  RAISE NOTICE 'ATTACK D-1: editing period_end on a NEVER-snapshotted draft under REPEATABLE READ SUCCEEDED (expected)';
EXCEPTION WHEN invalid_transaction_state THEN
  RAISE NOTICE 'ATTACK D-1 RESULT: editing period_end on a NEVER-snapshotted draft under REPEATABLE READ was REFUSED (false refusal — no snapshot exists anywhere to protect): %', SQLERRM;
END $$;
ROLLBACK;

-- Same probe for correction_run_targets — no target row even exists yet at this point,
-- so create one under READ COMMITTED first (uncontested), then try editing rate_date_mode
-- under SERIALIZABLE with zero snapshots anywhere on the correction.
BEGIN;
SET LOCAL app.user_id = '10000000-0000-4000-8000-00000000ab01';
SET ROLE tally_app;
INSERT INTO public.correction_run_targets (id, tenant_id, billing_run_id, voided_invoice_id, meter_id, customer_id, rate_date_mode)
VALUES ('10000000-0000-4000-8000-00000000d201', '10000000-0000-4000-8000-00000000aa01', '10000000-0000-4000-8000-00000000b201', '10000000-0000-4000-8000-00000000c201', '10000000-0000-4000-8000-00000000ae01', '10000000-0000-4000-8000-00000000ac01', 'historical');
COMMIT;

BEGIN ISOLATION LEVEL SERIALIZABLE;
SET LOCAL app.user_id = '10000000-0000-4000-8000-00000000ab01';
SET ROLE tally_app;
DO $$
BEGIN
  UPDATE public.correction_run_targets SET rate_date_mode = 'current' WHERE id = '10000000-0000-4000-8000-00000000d201';
  RAISE NOTICE 'ATTACK D-2: editing rate_date_mode on a target with ZERO snapshots under SERIALIZABLE SUCCEEDED (expected)';
EXCEPTION WHEN invalid_transaction_state THEN
  RAISE NOTICE 'ATTACK D-2 RESULT: editing rate_date_mode on a target with ZERO snapshots anywhere under SERIALIZABLE was REFUSED (false refusal): %', SQLERRM;
END $$;
ROLLBACK;

-- Same probe for billing_runs.correction_rate_mode — run has zero snapshots anywhere.
BEGIN ISOLATION LEVEL REPEATABLE READ;
SET LOCAL app.user_id = '10000000-0000-4000-8000-00000000ab01';
SET ROLE tally_app;
DO $$
BEGIN
  UPDATE public.billing_runs SET correction_rate_mode = 'current' WHERE id = '10000000-0000-4000-8000-00000000b201';
  RAISE NOTICE 'ATTACK D-3: editing correction_rate_mode on a run with ZERO snapshots under REPEATABLE READ SUCCEEDED (expected)';
EXCEPTION WHEN invalid_transaction_state THEN
  RAISE NOTICE 'ATTACK D-3 RESULT: editing correction_rate_mode on a run with ZERO snapshots anywhere under REPEATABLE READ was REFUSED (false refusal): %', SQLERRM;
END $$;
ROLLBACK;
-- (fixtures above this point were committed deliberately to set up the probes; left in place)
