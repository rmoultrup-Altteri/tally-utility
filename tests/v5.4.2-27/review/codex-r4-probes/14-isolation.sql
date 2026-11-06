-- Codex r4 AUTHOR RUN ONLY. Owner, fresh clone with frozen r4 applied.
-- Direct shared-check branch only; not an end-to-end writer/isolation race.
\set ON_ERROR_STOP on
BEGIN ISOLATION LEVEL REPEATABLE READ;
DO $$ BEGIN
  PERFORM public.check_cash_source('credit','00000000-0000-4000-8000-000000002771',now(),'shortfall',DATE '2026-03-13');
  RAISE NOTICE 'unexpected acceptance SQLSTATE=00000';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'REPEATABLE READ SQLSTATE=% message=%',SQLSTATE,SQLERRM;
END $$;
ROLLBACK;
BEGIN ISOLATION LEVEL SERIALIZABLE;
DO $$ BEGIN
  PERFORM public.check_cash_source('credit','00000000-0000-4000-8000-000000002771',now(),'shortfall',DATE '2026-03-13');
  RAISE NOTICE 'unexpected acceptance SQLSTATE=00000';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'SERIALIZABLE SQLSTATE=% message=%',SQLSTATE,SQLERRM;
END $$;
-- Predicted 25000 in both, before lookup of the deliberately absent credit.
ROLLBACK;
