-- Author-run only. Run as owner on a fresh clone of tally with frozen r1 applied.
-- Revoke clone TEMP from PUBLIC, tally_app, tally_core as in the brief.
-- No role creation/alteration; all fixture changes roll back.
BEGIN;
DO $$
DECLARE oldest timestamptz; n integer;
BEGIN
 SELECT min(created_at),count(*) INTO oldest,n FROM public.places
 WHERE kind_code='state' AND state_code='TX'
   AND created_at<=now()-interval '3 days'
   AND daterange(effective_from,public.end_as_known(effective_to,closed_at,now()-interval '3 days'),'[)') @> DATE '2026-06-01';
 RAISE NOTICE 'S2 Texas rows known three days ago=% oldest=%; M3 requires zero',n,oldest;
EXCEPTION WHEN OTHERS THEN
 RAISE NOTICE 'S2 caught SQLSTATE=% message=%',SQLSTATE,SQLERRM;
END $$;
ROLLBACK;
