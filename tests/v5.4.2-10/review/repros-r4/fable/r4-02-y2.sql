SET app.user_id = '00000000-0000-4000-8000-0000000fa101'; SET ROLE tally_app;
BEGIN;
SELECT 'Y2: attempting C2 snapshot (root A)' AS y2, clock_timestamp();
SELECT public.fa_snap('00000000-0000-4000-8000-0000000fd024', '2026-03-31', now());
SELECT 'Y2: C2 snapshot in' AS y2, clock_timestamp();
COMMIT;
