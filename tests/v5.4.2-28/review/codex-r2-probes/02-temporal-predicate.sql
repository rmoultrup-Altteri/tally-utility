-- SOURCE ONLY; NOT EXECUTED. Owner, fresh clone of tally with frozen r2.
-- Revoke clone TEMP from PUBLIC/tally_app/tally_core before running.
-- This is an interval-model probe, NOT a two-session race reproduction.
-- Coordinates are synthetic. No production guards are disabled or replaced.
-- It tests the predicate's boundary independently of scheduling/MVCC.
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL statement_timeout = '30s';
DO $$
DECLARE r record; actual boolean;
BEGIN
 FOR r IN SELECT * FROM (VALUES
   ('open before new', 0, NULL::int, true),
   ('closed after new start', 0, 20, true),
   ('close and successor at same transaction instant', 0, 10, false),
   ('closed before new start', 0, 9, false),
   ('asserted after new start, remains open', 15, NULL::int, true),
   ('asserted and closed after new start', 15, 20, true)
 ) x(label, recorded_at, recorded_until, expected) LOOP
   actual := r.recorded_until IS NULL OR r.recorded_until > 10;
   IF actual IS DISTINCT FROM r.expected THEN
     RAISE EXCEPTION 'predicate mismatch: %', r.label;
   END IF;
   RAISE NOTICE 'PASS %: retained=% (SQLSTATE 00000)',r.label,actual;
 END LOOP;
 -- Open NEW has interval [10,infinity); old lower bounds must not be
 -- restricted to <=10: a row starting at 15 can coexist at 15.
 RAISE NOTICE 'The predicate tests potential overlap with NEW [10,infinity), not strictly known-at-10 membership';
EXCEPTION WHEN OTHERS THEN
 RAISE NOTICE 'caught SQLSTATE=% MESSAGE=%', SQLSTATE, SQLERRM;
 RAISE;
END $$;
-- Catalog evidence for the MVCC source argument. This prints evidence,
-- not a claim that a concurrent execution was measured.
SELECT pg_get_functiondef('public.enforce_rate_item_dependency()'::regprocedure);
SELECT tgname,tgenabled,pg_get_triggerdef(oid)
FROM pg_trigger WHERE tgrelid='public.rate_item_dependencies'::regclass AND NOT tgisinternal
ORDER BY tgname;
-- Deferred constraints do not bypass the immediate BEFORE row guard or
-- immediate CHECKs. Read Uncommitted uses PostgreSQL's Read Committed
-- behavior; RR/Serializable require a fresh snapshot or retry after the
-- schedule-header UPDATE conflicts with a concurrently changed version.
-- The actual two-session schedule remains for the author to execute with
-- the existing race harness, after adding a commit-before-insert barrier.
ROLLBACK;
