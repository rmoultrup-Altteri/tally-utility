-- PREDICTED; not executed by Codex. Run as owner/superuser on a fresh clone
-- with frozen r5 strictly applied and TEMP revoked from PUBLIC, tally_app, tally_core.
-- R2 prediction: prior defect is fixed; notices report actual outcomes. NOT EXECUTED.
-- Codex r3 source-review probe. NOT EXECUTED by reviewer.
-- Run with psql -U tally -d <fresh-clone-with-frozen-patch> -f this-file.sql
-- Requires the clone owner/superuser; no role DDL, no commits; all changes roll back.
-- OBSERVED notices report behavior, not a pre-declared pass. Unexpected setup errors stop psql.
\set ON_ERROR_STOP on
BEGIN ISOLATION LEVEL READ COMMITTED;
SET LOCAL search_path = public, pg_temp;
SET LOCAL client_min_messages = notice;
-- R2 prediction: replacing the recovery CHECK by CHECK(true) is detected.
-- DDL is database-local and rolled back; no cluster-wide role mutations.
ALTER TABLE public.account_ledger DROP CONSTRAINT account_ledger_recovery_lineage_check;
ALTER TABLE public.account_ledger ADD CONSTRAINT account_ledger_recovery_lineage_check CHECK (true);
DO $$ BEGIN
  BEGIN
    PERFORM public.assert_periods_guard_invariants();
    RAISE NOTICE 'OBSERVED N4 invariant accepted a vacuous recovery lineage CHECK';
  EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'OBSERVED N4 invariant refused: % %',SQLSTATE,SQLERRM;
  END;
END $$;

RESET ROLE;
ROLLBACK;
