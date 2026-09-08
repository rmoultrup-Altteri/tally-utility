SELECT 'B: attempting election change (READ COMMITTED)' AS b, clock_timestamp();
SET app.user_id = '00000000-0000-4000-8000-00000000fb01';
SET ROLE tally_app;
UPDATE public.correction_run_targets SET rate_date_mode = 'current' WHERE id = '00000000-0000-4000-8000-00000000f301';
SELECT 'B: target update outcome above' AS b, clock_timestamp();
UPDATE public.billing_runs SET correction_rate_mode = 'current' WHERE id = '00000000-0000-4000-8000-00000000f002';
SELECT 'B: run update outcome above' AS b, clock_timestamp();
