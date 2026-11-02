-- SOURCE-ONLY REVIEW: not executed by Codex.
-- Run as the owner on a fresh clone of tally with frozen r1 applied.
-- Revoke clone TEMP from PUBLIC, tally_app and tally_core before running.
-- No cluster role changes. All fixtures and helper functions roll back.
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL statement_timeout = '60s';
CREATE FUNCTION pg_temp.attempt(label text, statement text) RETURNS boolean
LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE statement;
  RAISE NOTICE '%: accepted (SQLSTATE 00000)', label;
  RETURN true;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '%: SQLSTATE=% MESSAGE=%', label, SQLSTATE, SQLERRM;
  RETURN false;
END $$;
GRANT EXECUTE ON FUNCTION pg_temp.attempt(text,text) TO tally_app, tally_core;
CREATE FUNCTION pg_temp.cid(k text) RETURNS uuid LANGUAGE sql IMMUTABLE AS $$ SELECT md5('codex28r1-' || k)::uuid $$;
GRANT EXECUTE ON FUNCTION pg_temp.cid(text) TO tally_app, tally_core;
INSERT INTO public.tenants(id,name,slug) VALUES(pg_temp.cid('tenant'),'Codex 28','codex28-r1');
INSERT INTO public.users(id,tenant_id,display_name,email,role) VALUES
(pg_temp.cid('user'),pg_temp.cid('tenant'),'Reviewer','codex28@example.test','operator'),
(pg_temp.cid('other'),pg_temp.cid('tenant'),'Other','codex28other@example.test','operator');
SELECT set_config('app.user_id',pg_temp.cid('user')::text,true);
INSERT INTO public.rate_schedules(id,tenant_id,code) VALUES(pg_temp.cid('schedule'),pg_temp.cid('tenant'),'C28');
INSERT INTO public.rate_items(id,tenant_id,item_code)
SELECT pg_temp.cid(k),pg_temp.cid('tenant'),k FROM unnest(ARRAY['A','B','C','D','E','F']) k;
CREATE FUNCTION pg_temp.edge(k text,a text,b text,lo date,hi date DEFAULT NULL) RETURNS void LANGUAGE sql AS $$
INSERT INTO public.rate_item_dependencies(id,tenant_id,rate_schedule_id,dependent_rate_item_id,base_rate_item_id,effective_date,expiry_date,changed_by)
VALUES(pg_temp.cid(k),pg_temp.cid('tenant'),pg_temp.cid('schedule'),pg_temp.cid(a),pg_temp.cid(b),lo,hi,pg_temp.cid('other'));
$$;
GRANT EXECUTE ON FUNCTION pg_temp.edge(text,text,text,date,date) TO tally_app;
SET LOCAL ROLE tally_app;
SELECT pg_temp.edge('ab','A','B','2026-01-01','2026-03-31');
RESET ROLE;
SET LOCAL session_replication_role = replica;
UPDATE public.rate_schedules SET updated_at='2000-01-01' WHERE id=pg_temp.cid('schedule');
SET LOCAL session_replication_role = origin;
SET LOCAL ROLE tally_app;
SELECT pg_temp.attempt('B1 NULL close reason (predicted accepted)', $s$
UPDATE public.rate_item_dependencies SET recorded_until=now(),closed_type='retracted',closed_reason=NULL,closed_by=pg_temp.cid('other') WHERE id=pg_temp.cid('ab')$s$);
SELECT updated_at=now() AS close_touched_header FROM public.rate_schedules WHERE id=pg_temp.cid('schedule');
SELECT recorded_until=now() AS stamped_time, closed_reason IS NULL AS missing_reason,
 changed_by=pg_temp.cid('user') AS stamped_author, closed_by=pg_temp.cid('user') AS stamped_closer
 FROM public.rate_item_dependencies WHERE id=pg_temp.cid('ab');
SELECT pg_temp.attempt('closed row cannot be rewritten', $s$UPDATE public.rate_item_dependencies SET closed_reason='repair' WHERE id=pg_temp.cid('ab')$s$);
SELECT pg_temp.edge('bc','B','C','2026-01-01','2026-03-31');
SELECT pg_temp.attempt('blank close reason control', $s$UPDATE public.rate_item_dependencies SET recorded_until=now(),closed_type='retracted',closed_reason=' ' WHERE id=pg_temp.cid('bc')$s$);
SELECT pg_temp.attempt('inclusive endpoint cycle', $s$SELECT pg_temp.edge('cb','C','B','2026-03-31')$s$);
SELECT pg_temp.attempt('disjoint reverse link', $s$SELECT pg_temp.edge('cb','C','B','2026-04-01')$s$);
SELECT pg_temp.attempt('inclusive same-link exclusion', $s$SELECT pg_temp.edge('bc2','B','C','2026-03-31')$s$);
SELECT pg_temp.attempt('frozen author', $s$UPDATE public.rate_item_dependencies SET changed_by=pg_temp.cid('other') WHERE id=pg_temp.cid('bc')$s$);
SELECT pg_temp.attempt('no-close closer', $s$UPDATE public.rate_item_dependencies SET closed_by=pg_temp.cid('other') WHERE id=pg_temp.cid('bc')$s$);
SELECT pg_temp.attempt('multi-row cycle', $s$
INSERT INTO public.rate_item_dependencies(tenant_id,rate_schedule_id,dependent_rate_item_id,base_rate_item_id,effective_date)
VALUES(pg_temp.cid('tenant'),pg_temp.cid('schedule'),pg_temp.cid('D'),pg_temp.cid('E'),'2026-01-01'),
(pg_temp.cid('tenant'),pg_temp.cid('schedule'),pg_temp.cid('E'),pg_temp.cid('D'),'2026-01-01')$s$);
SELECT pg_temp.attempt('missing successor', $s$DO $b$ BEGIN
UPDATE public.rate_item_dependencies SET recorded_until=now(),closed_type='superseded',closed_reason='replace' WHERE id=pg_temp.cid('bc');
SET CONSTRAINTS enforce_superseded_has_successor IMMEDIATE;
END $b$$s$);
UPDATE public.rate_item_dependencies SET recorded_until=now(),closed_type='superseded',closed_reason='shorten' WHERE id=pg_temp.cid('bc');
SELECT pg_temp.attempt('same-link successor', $s$
INSERT INTO public.rate_item_dependencies(tenant_id,rate_schedule_id,dependent_rate_item_id,base_rate_item_id,effective_date,expiry_date,change_type,change_reason,supersedes_id)
VALUES(pg_temp.cid('tenant'),pg_temp.cid('schedule'),pg_temp.cid('B'),pg_temp.cid('C'),'2026-01-01','2026-02-28','correction','shorten',pg_temp.cid('bc'))$s$);
SELECT pg_temp.edge('de','D','E','2026-01-01','2026-03-31');
SELECT pg_temp.edge('ef','E','F','2026-04-01');
SELECT pg_temp.attempt('L2 conservative refusal without a common day',$s$SELECT pg_temp.edge('fd','F','D','2026-01-01','2026-12-31')$s$);
SELECT pg_temp.attempt('app delete' , $s$DELETE FROM public.rate_item_dependencies WHERE id=pg_temp.cid('ab')$s$);
RESET ROLE;
SELECT pg_temp.attempt('owner delete', $s$DELETE FROM public.rate_item_dependencies WHERE id=pg_temp.cid('ab')$s$);
SELECT pg_temp.attempt('flush deferred checks', 'SET CONSTRAINTS ALL IMMEDIATE');
SELECT * FROM public.rate_item_dependencies_as_of(pg_temp.cid('schedule'),'2026-02-01',now());
SELECT count(*) AS before_recording FROM public.rate_item_dependencies_as_of(pg_temp.cid('schedule'),'2026-02-01',now()-interval '1 second');
SET LOCAL ROLE tally_core;
SELECT count(*) AS core_read FROM public.rate_item_dependencies_as_of(pg_temp.cid('schedule'),'2026-02-01',now());
SELECT pg_temp.attempt('core write denied', $s$UPDATE public.rate_item_dependencies SET closed_reason='core' WHERE id=pg_temp.cid('bc')$s$);
RESET ROLE;
SELECT public.assert_wave1_guard_invariants();
SELECT public.assert_no_hard_delete_invariants();
ROLLBACK;
