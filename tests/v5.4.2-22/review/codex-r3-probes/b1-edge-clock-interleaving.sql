-- PREDICTED only. Owner on a fresh clone with frozen r3 applied.
\set ON_ERROR_STOP on
BEGIN ISOLATION LEVEL READ COMMITTED;
SET LOCAL search_path=public,pg_temp;
SET LOCAL client_min_messages=notice;
-- This is a scheduling simulation, NOT an unmodified two-session reproduction.
-- Only in this rollback transaction, insert a hook between the frozen close's
-- clock assignment and live-setting SELECT. The hook models a setting UPDATE
-- becoming visible in that gap. No checks/locks/SELECTs are removed.
-- A real schedule is: close obtains head+period; close assigns v_at;
-- another tenant-setting writer commits; close SELECTs live edges.
-- The head and period locks do not lock the tenant's bucket setting.
CREATE FUNCTION public.codex_r3_edge_hook(p_tenant uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
 PERFORM set_config('codex.edge_changed_at',clock_timestamp()::text,true);
 UPDATE public.tenants SET receivables_aging_bucket_days=ARRAY[10,20] WHERE id=p_tenant;
END $$;
REVOKE ALL ON FUNCTION public.codex_r3_edge_hook(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.codex_r3_edge_hook(uuid) TO tally_close;
DO $$
DECLARE src text; needle text:='    v_at := pg_catalog.clock_timestamp();';
BEGIN
 SELECT pg_get_functiondef('public.close_accounting_period(uuid,numeric,text)'::regprocedure) INTO src;
 IF (length(src)-length(replace(src,needle,'')))/length(needle) <> 1 THEN
 RAISE EXCEPTION 'instrumentation anchor not unique'; END IF;
 EXECUTE replace(src,needle,needle||E'\n    PERFORM public.codex_r3_edge_hook(v_tenant);');
END $$;
DO $$
DECLARE t uuid:=gen_random_uuid(); u uuid:=gen_random_uuid(); p uuid:=gen_random_uuid(); at_close timestamptz; e integer[];
BEGIN
 INSERT INTO tenants(id,name,slug) VALUES(t,'Clock probe','cx3-'||t);
 INSERT INTO users(id,tenant_id,display_name,email,role,is_active)
 VALUES(u,t,'Supervisor',u||'@codex.test','tenant_admin',true);
 PERFORM set_config('app.user_id',u::text,true);
 INSERT INTO accounting_periods(id,tenant_id,period_start,period_end) VALUES(p,t,'2020-01-01','2020-01-31');
 BEGIN
 at_close:=close_accounting_period(p);
 SELECT aging_bucket_days INTO e FROM accounting_period_snapshots WHERE period_id=p;
 RAISE NOTICE 'SIMULATION recorded_at=% update_after=% captured_edges=% prior_edges={30,60,90,120}',
 at_close,current_setting('codex.edge_changed_at'),e;
 IF NOT (at_close < current_setting('codex.edge_changed_at')::timestamptz AND e=ARRAY[10,20]) THEN
 RAISE EXCEPTION 'did not demonstrate predicted gap'; END IF;
 EXCEPTION WHEN OTHERS THEN
 RAISE NOTICE 'SIMULATION SQLSTATE=% message=%',SQLSTATE,SQLERRM;
 RAISE;
 END;
END $$;
ROLLBACK;
