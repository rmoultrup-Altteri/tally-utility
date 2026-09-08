BEGIN;
SET LOCAL app.user_id = '00000000-0000-4000-8000-0000000fa101';
SET ROLE tally_app;
SELECT public.fa_snap('00000000-0000-4000-8000-0000000fa542', '2026-03-31', now());
SELECT pg_sleep(2);
UPDATE public.billing_runs SET total_invoices = total_invoices + 1 WHERE id = '00000000-0000-4000-8000-0000000fa641';
SELECT 'B updated run' AS b;
COMMIT;
