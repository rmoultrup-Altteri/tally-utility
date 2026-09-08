SET app.user_id = '00000000-0000-4000-8000-0000000fa101'; SET ROLE tally_app;
BEGIN;
UPDATE public.invoices SET notes='b' WHERE id='00000000-0000-4000-8000-0000000fd022';
SELECT 'X: B annotated' AS x, clock_timestamp();
SELECT pg_sleep(2);
UPDATE public.invoices SET notes='a' WHERE id='00000000-0000-4000-8000-0000000fd021';
SELECT 'X: A annotated' AS x, clock_timestamp();
COMMIT;
