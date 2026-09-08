SET app.user_id = '00000000-0000-4000-8000-0000000fa101'; SET ROLE tally_app;
BEGIN;
SELECT public.fa_snap('00000000-0000-4000-8000-0000000fa832', '2026-04-30', now());
SELECT 'A: snapshot in, mutex held' AS a, clock_timestamp();
SELECT pg_sleep(3);
COMMIT;
SELECT 'A: committed' AS a, clock_timestamp();
