-- PREDICTED/catalog and drift probe only. Owner, fresh frozen-r4 clone; TEMP revoked.
-- No concurrency or performance result is established by this probe.
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL search_path=public,pg_temp;
SET LOCAL client_min_messages=notice;
DO $$
DECLARE fn regprocedure; cfg text[]; refused boolean:=false;
BEGIN
 FOREACH fn IN ARRAY ARRAY['public.enforce_write_off_recovery()'::regprocedure,
                          'public.enforce_ledger_lineage_acyclic()'::regprocedure] LOOP
  SELECT proconfig INTO cfg FROM pg_proc WHERE oid=fn;
  RAISE NOTICE '% function settings: %',fn,cfg;
  IF NOT cfg @> ARRAY['enable_seqscan=off','enable_hashjoin=off','enable_mergejoin=off'] THEN
   RAISE EXCEPTION 'Missing planner settings on %',fn;
  END IF;
 END LOOP;
 RAISE NOTICE 'Edge guard body: %',pg_get_functiondef('public.enforce_aging_edges_close_order()'::regprocedure);
 RAISE NOTICE 'Close role explicit privileges: %',public.seal_role_privileges('tally_close');
 PERFORM public.assert_seal_role_invariants();
 PERFORM public.assert_periods_guard_invariants();
 BEGIN
  ALTER TABLE public.tenants DISABLE TRIGGER enforce_aging_edges_close_order;
  PERFORM public.assert_periods_guard_invariants();
 EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'disabled edge guard SQLSTATE=% message=%',SQLSTATE,SQLERRM;
  IF SQLSTATE<>'0LP01' OR position('enforce_aging_edges_close_order' in SQLERRM)=0 THEN RAISE; END IF;
  refused:=true;
 END;
 IF NOT refused THEN RAISE EXCEPTION 'Invariant missed disabled edge guard'; END IF;
END $$;
-- These are representative plans only; function settings discourage plans,
-- not an assertion that every internal statement uses a particular plan.
SET LOCAL enable_seqscan=off;
SET LOCAL enable_hashjoin=off;
SET LOCAL enable_mergejoin=off;
EXPLAIN (COSTS OFF) SELECT id FROM public.account_ledger WHERE reverses_ledger_entry_id='c0440000-0000-4000-8000-000000000003';
EXPLAIN (COSTS OFF) SELECT id,created_at FROM public.account_ledger
 WHERE (id='c0440000-0000-4000-8000-000000000003' OR id=ANY(ARRAY['c0440000-0000-4000-8000-000000000004'::uuid]))
 AND created_at>now() ORDER BY created_at DESC LIMIT 1;
ROLLBACK;
