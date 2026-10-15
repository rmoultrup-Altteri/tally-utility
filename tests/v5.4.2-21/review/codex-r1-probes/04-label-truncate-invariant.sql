\set ON_ERROR_STOP on
-- Catalog-drift probe, as superuser tally. All DDL is rolled back.
BEGIN;
SET LOCAL search_path = public, pg_temp;
DO $$ BEGIN
 PERFORM public.assert_no_hard_delete_invariants();
 RAISE NOTICE 'PROBE 04 baseline invariant accepted';
END $$;
ALTER TABLE public.custom_field_definitions DISABLE TRIGGER no_truncate;
ALTER TABLE public.custom_location_types DISABLE TRIGGER no_truncate;
DO $$ BEGIN
 BEGIN
  PERFORM public.assert_no_hard_delete_invariants();
  RAISE NOTICE 'PROBE 04 invariant ACCEPTED with both label no_truncate triggers disabled';
 EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'PROBE 04 invariant REFUSED [%] %',SQLSTATE,SQLERRM;
 END;
END $$;
ROLLBACK;
