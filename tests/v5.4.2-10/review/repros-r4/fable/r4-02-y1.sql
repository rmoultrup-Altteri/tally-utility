SET app.user_id = '00000000-0000-4000-8000-0000000fa101'; SET ROLE tally_app;
BEGIN;
SELECT public.fa_snap('00000000-0000-4000-8000-0000000fd023', '2026-03-31', now());
SELECT 'Y1: C snapshot in (root A + B locked), holding 3s' AS y1, clock_timestamp();
SELECT pg_sleep(3);
COMMIT;
SELECT 'Y1: committed' AS y1, clock_timestamp();
