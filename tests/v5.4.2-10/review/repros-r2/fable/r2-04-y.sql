SET app.user_id = '00000000-0000-4000-8000-0000000fa101'; SET ROLE tally_app;
BEGIN;
SELECT 'Y: snapshotting' AS y, clock_timestamp();
SELECT public.fa_snap('00000000-0000-4000-8000-0000000fa842', '2026-02-28', now());
SELECT 'Y: snapshot in' AS y, clock_timestamp();
COMMIT;
