-- Codex r1: AUTHOR RUN ONLY, not executed by reviewer.
-- Run as owner on a fresh clone with frozen r1 applied; revoke TEMP from
-- PUBLIC, tally_app and tally_core on the clone per brief. No role DDL.
\set ON_ERROR_STOP on

BEGIN;
-- Each mutation is local to a savepoint; no roles are created or altered.
SAVEPOINT missing_insert;
REVOKE INSERT ON public.shortfall_applications FROM tally_app;
DO $$ BEGIN
  BEGIN
    PERFORM public.assert_shortfall_guard_invariants();
    RAISE NOTICE 'S1 missing INSERT undetected: SQLSTATE=00000';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'S1 missing INSERT caught: SQLSTATE=% message=%', SQLSTATE, SQLERRM;
  END;
END $$;
ROLLBACK TO missing_insert;
SAVEPOINT missing_core_read;
REVOKE SELECT ON public.shortfall_applications FROM tally_core;
DO $$ BEGIN
  BEGIN
    PERFORM public.assert_shortfall_guard_invariants();
    RAISE NOTICE 'S1 missing core SELECT undetected: SQLSTATE=00000';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'S1 missing core SELECT caught: SQLSTATE=% message=%', SQLSTATE, SQLERRM;
  END;
END $$;
ROLLBACK TO missing_core_read;
SAVEPOINT core_reference;
GRANT REFERENCES ON public.shortfall_applications TO tally_core;
DO $$ BEGIN
  BEGIN
    PERFORM public.assert_shortfall_guard_invariants();
    RAISE NOTICE 'S1 core REFERENCES undetected: SQLSTATE=00000';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'S1 core REFERENCES caught: SQLSTATE=% message=%', SQLSTATE, SQLERRM;
  END;
END $$;
ROLLBACK TO core_reference;
ROLLBACK;
