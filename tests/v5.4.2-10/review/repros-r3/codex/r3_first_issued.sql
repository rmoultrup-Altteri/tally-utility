BEGIN;
SET CONSTRAINTS ALL IMMEDIATE;
SET LOCAL app.user_id = '10000000-0000-4000-8000-00000000ab01';
SET ROLE tally_app;

INSERT INTO public.invoices (id, tenant_id, invoice_number, customer_id, location_id, invoice_type, invoice_date, billing_period, period_start, period_end, due_date, status)
VALUES ('10000000-0000-4000-8000-00000000ca01', '10000000-0000-4000-8000-00000000aa01', 'T1-FI', '10000000-0000-4000-8000-00000000ac01', '10000000-0000-4000-8000-00000000ad01', 'regular', '2025-10-01', '2025-09', '2025-09-01', '2025-09-30', '2025-10-21', 'draft');

-- 1: caller tries to directly forge first_issued_at while flipping to held (not issued).
DO $$
BEGIN
  UPDATE public.invoices SET status='held', hold_reason='test', first_issued_at='2020-01-01' WHERE id='10000000-0000-4000-8000-00000000ca01';
  RAISE NOTICE 'R3 FI-1: forged first_issued_at while entering HELD succeeded (BAD)';
EXCEPTION WHEN restrict_violation THEN
  RAISE NOTICE 'R3 FI-1 RESULT: correctly refused: %', SQLERRM;
END $$;

-- 2: caller tries to forge first_issued_at while flipping straight to pending (issued) --
-- should ALSO be refused (write-once check fires before the stamp logic, blocking any
-- caller-supplied value even on a legitimate transition).
DO $$
BEGIN
  UPDATE public.invoices SET status='pending', first_issued_at='2020-01-01' WHERE id='10000000-0000-4000-8000-00000000ca01';
  RAISE NOTICE 'R3 FI-2: forged first_issued_at while entering PENDING succeeded (BAD)';
EXCEPTION WHEN restrict_violation THEN
  RAISE NOTICE 'R3 FI-2 RESULT: correctly refused: %', SQLERRM;
END $$;

-- 3: legitimate flip to held (no snapshot needed) then check first_issued_at stayed NULL.
UPDATE public.invoices SET status='held', hold_reason='test' WHERE id='10000000-0000-4000-8000-00000000ca01';
DO $$
DECLARE v_fi timestamptz;
BEGIN
  SELECT first_issued_at INTO v_fi FROM public.invoices WHERE id='10000000-0000-4000-8000-00000000ca01';
  RAISE NOTICE 'R3 FI-3: first_issued_at after entering HELD (never issued) = % (expect NULL)', v_fi;
END $$;

ROLLBACK;
