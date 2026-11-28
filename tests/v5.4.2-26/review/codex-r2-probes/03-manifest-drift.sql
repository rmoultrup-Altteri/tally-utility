-- Codex r2: NOT EXECUTED. Owner session, fresh clone with frozen r2 strictly applied.
-- Revoke TEMP from PUBLIC/tally_app/tally_core when preparing the clone.
-- Fixtures are frozen-battery fixtures. No role creation or alteration.
\set ON_ERROR_STOP on
\set VERBOSITY verbose

BEGIN;
-- S3: each edit is isolated and undone, including when the invariant misses it.
CREATE FUNCTION pg_temp.drift(label text, stmt text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  BEGIN
    EXECUTE stmt;
    PERFORM public.assert_collections_guard_invariants();
    RAISE NOTICE '%: invariant ACCEPTED drift SQLSTATE=00000', label;
    RAISE EXCEPTION 'intentional undo of drift' USING ERRCODE='P0098';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE '%: SQLSTATE=% message=%', label, SQLSTATE, SQLERRM;
  END;
END $$;
SELECT public.assert_collections_guard_invariants();
SELECT pg_temp.drift('control: disabled guard', 'ALTER TABLE public.service_order_field_visits DISABLE TRIGGER b_enforce_field_visit');
SELECT pg_temp.drift('policy becomes allow-all', 'ALTER POLICY tenant_isolation ON public.collections_decisions USING (true) WITH CHECK (true)');
SELECT pg_temp.drift('evidence array loses NOT NULL', 'ALTER TABLE public.service_order_field_visits ALTER COLUMN evidence_refs DROP NOT NULL');
SELECT pg_temp.drift('column grant not table grant', 'GRANT SELECT (inputs) ON public.collections_decisions TO PUBLIC');
SELECT pg_temp.drift('helper volatility changes', 'ALTER FUNCTION public.collections_live_decision(uuid,text,uuid,uuid,uuid,uuid) VOLATILE');
SELECT public.assert_collections_guard_invariants();
ROLLBACK;
