SET app.user_id = '00000000-0000-4000-8000-00000000fb01';
SET ROLE tally_app;
SELECT 'B heartbeat start' AS b, clock_timestamp();
UPDATE public.billing_runs SET last_heartbeat_at = now(), total_invoices = 1 WHERE id = '00000000-0000-4000-8000-00000000f002';
SELECT 'B heartbeat done' AS b, clock_timestamp();
