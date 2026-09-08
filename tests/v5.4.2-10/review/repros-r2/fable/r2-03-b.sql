SET app.user_id = '00000000-0000-4000-8000-0000000fa101'; SET ROLE tally_app;
BEGIN ISOLATION LEVEL REPEATABLE READ;
SELECT 'B: RR snapshot taken (target has no visible snapshot yet? see next)' AS b, clock_timestamp();
SELECT count(*) AS snapshots_visible_to_B FROM public.invoice_calculation_snapshots WHERE invoice_id='00000000-0000-4000-8000-0000000fa832';
SELECT pg_sleep(1);
UPDATE public.correction_run_targets SET rate_date_mode='current' WHERE id='00000000-0000-4000-8000-0000000fab31';
SELECT 'B: update passed' AS b, clock_timestamp();
ROLLBACK;
