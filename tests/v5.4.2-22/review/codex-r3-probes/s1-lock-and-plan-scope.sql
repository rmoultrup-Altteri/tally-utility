-- PREDICTED/catalog diagnostic only. Owner, fresh frozen-r3 clone.
-- This does not execute a race or establish any runtime/planner result.
-- Author follow-up schedule (not run here): two existing independent write-offs
-- W1 and W2, with sufficient unused cap; A's VALUES visits W1 then W2,
-- B's VALUES visits W2 then W1. Pause each after its first AFTER-row cap lock.
-- The per-row ORDER BY does not globally order these retained transaction locks.
-- Likewise, earlier statements can retain a higher-id lock before a lower-id one.
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL search_path=public,pg_temp;
DO $$
DECLARE s text;
BEGIN
 SELECT pg_get_functiondef('public.enforce_write_off_recovery()'::regprocedure) INTO s;
 RAISE NOTICE 'SOURCE: per-row ordered ancestor query=%; transaction advisory lock=%',
 position('ORDER BY l.id' in s)>0,position('pg_advisory_xact_lock' in s)>0;
 RAISE NOTICE 'SOURCE: recovery trigger definition=%',
 (SELECT pg_get_triggerdef(oid) FROM pg_trigger WHERE tgrelid='public.account_ledger'::regclass AND tgname='enforce_write_off_recovery');
 RAISE NOTICE 'SOURCE: reversal-link index=%',pg_get_indexdef('public.idx_account_ledger_reverses'::regclass);
END $$;
-- Plan inspection only: a fresh clone may rationally choose a sequential scan
-- on a tiny table. Link-only predicates permit indexes; they do not force them.
EXPLAIN (COSTS OFF) SELECT id FROM public.account_ledger WHERE reverses_ledger_entry_id='c0330000-0000-4000-8000-000000000001';
EXPLAIN (COSTS OFF) SELECT reverses_ledger_entry_id FROM public.account_ledger WHERE id='c0330000-0000-4000-8000-000000000001';
ROLLBACK;
