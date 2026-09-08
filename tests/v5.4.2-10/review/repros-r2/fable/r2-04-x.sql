SET app.user_id = '00000000-0000-4000-8000-0000000fa101'; SET ROLE tally_app;
BEGIN;
UPDATE public.correction_run_targets SET rate_date_mode='historical' WHERE id='00000000-0000-4000-8000-0000000fab41';
SELECT 'X: target row locked' AS x, clock_timestamp();
SELECT pg_sleep(2);
UPDATE public.billing_runs SET correction_rate_mode='current' WHERE id='00000000-0000-4000-8000-0000000fa941';
SELECT 'X: run election changed' AS x, clock_timestamp();
COMMIT;
