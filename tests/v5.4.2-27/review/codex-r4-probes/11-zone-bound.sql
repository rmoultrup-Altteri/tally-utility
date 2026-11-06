-- Codex r4: AUTHOR RUN ONLY; not executed by reviewer.
-- Owner session, fresh clone with patch-27-frozen-r4.sql strictly applied.
-- Clone TEMP revoked from PUBLIC/tally_app/tally_core per brief. No role DDL.
\set ON_ERROR_STOP on
BEGIN;
-- Deterministic calendar calculation; does not replace the clock or patch.
DO $$
DECLARE t timestamptz := TIMESTAMPTZ '2026-11-06 10:30:00+00'; z text;
BEGIN
  FOREACH z IN ARRAY ARRAY['Etc/GMT+12','Pacific/Pago_Pago','Pacific/Honolulu','America/Chicago','Pacific/Kiritimati'] LOOP
    RAISE NOTICE 'instant=% zone=% local_date=% latest_date=% date_difference=%', t, z,
      (t AT TIME ZONE z)::date, (t AT TIME ZONE 'Etc/GMT-14')::date,
      (t AT TIME ZONE 'Etc/GMT-14')::date - (t AT TIME ZONE z)::date;
  END LOOP;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'caught SQLSTATE=% message=%', SQLSTATE, SQLERRM;
END $$;
-- Predicted: UTC-12 and Pago Pago date_difference=2, not at most 1.
-- Honolulu and Chicago =1, Kiritimati =0 at this instant.
ROLLBACK;
