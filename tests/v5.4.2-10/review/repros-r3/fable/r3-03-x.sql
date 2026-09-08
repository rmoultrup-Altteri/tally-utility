SET app.user_id = '00000000-0000-4000-8000-0000000fa101'; SET ROLE tally_app;
BEGIN;
UPDATE public.correction_run_targets SET rate_date_mode='historical' WHERE id='00000000-0000-4000-8000-0000000fcb21';
SELECT 'X: target locked' AS x, clock_timestamp();
SELECT pg_sleep(2);
UPDATE public.invoices SET notes='annotated' WHERE id='00000000-0000-4000-8000-0000000fc021';
SELECT 'X: void original annotated' AS x, clock_timestamp();
COMMIT;
