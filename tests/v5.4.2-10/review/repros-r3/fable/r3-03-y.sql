SET app.user_id = '00000000-0000-4000-8000-0000000fa101'; SET ROLE tally_app;
BEGIN;
SELECT public.fa_snap('00000000-0000-4000-8000-0000000fc022', '2026-06-30', now());
SELECT 'Y: snapshot in' AS y, clock_timestamp();
COMMIT;
