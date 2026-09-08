SET app.user_id = '00000000-0000-4000-8000-00000000fb01';
SET ROLE tally_app;
BEGIN ISOLATION LEVEL REPEATABLE READ;
SELECT 'E: snapshots visible for RACE-W1 = ' || count(*) FROM public.invoice_calculation_snapshots WHERE invoice_id = '00000000-0000-4000-8000-00000000f104';
SELECT pg_sleep(3);
UPDATE public.invoices SET period_end = '2026-04-02', due_date = '2026-04-23' WHERE id = '00000000-0000-4000-8000-00000000f104';
SELECT 'E: edit went through (BAD)' AS e;
COMMIT;
