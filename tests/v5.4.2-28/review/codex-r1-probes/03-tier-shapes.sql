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
CREATE FUNCTION pg_temp.version_case(label text, config jsonb) RETURNS void LANGUAGE plpgsql AS $$
DECLARE item uuid := public.uuid_generate_v4();
BEGIN
  INSERT INTO public.rate_items(id,tenant_id,item_code) VALUES(item,pg_temp.cid('tenant'),label);
  PERFORM public.assert_reference_version('rate_items',item,1);
  BEGIN
    INSERT INTO public.rate_item_versions(tenant_id,rate_item_id,item_name,service_type,calculation_type,regulatory_class,effective_date,change_type,tier_config)
    VALUES(pg_temp.cid('tenant'),item,label,'gas','tiered_usage','regulated','2026-01-01','initial',config);
    RAISE NOTICE '%: accepted config=% (SQLSTATE 00000)', label, config;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE '%: SQLSTATE=% MESSAGE=%',label,SQLSTATE,SQLERRM;
  END;
END $$;
GRANT EXECUTE ON FUNCTION pg_temp.version_case(text,jsonb) TO tally_app;
SET LOCAL ROLE tally_app;
SELECT pg_temp.version_case('four decimals','{"tiers":[{"floor":0,"ceiling":null,"rate":0.4321}]}');
SELECT pg_temp.version_case('five decimals','{"tiers":[{"floor":0,"ceiling":null,"rate":0.43215}]}');
SELECT pg_temp.version_case('negative five decimals','{"tiers":[{"floor":0,"ceiling":null,"rate":-0.00001}]}');
SELECT pg_temp.version_case('numeric string','{"tiers":[{"floor":0,"ceiling":null,"rate":"0.43215"}]}');
SELECT pg_temp.version_case('null rate','{"tiers":[{"floor":0,"ceiling":null,"rate":null}]}');
SELECT pg_temp.version_case('missing rate','{"tiers":[{"floor":0,"ceiling":null}]}');
SELECT pg_temp.version_case('missing tiers','{}');
SELECT pg_temp.version_case('rate nested elsewhere','{"tiers":[{"floor":0,"ceiling":null,"pricing":{"rate":0.43215}}]}');
SELECT pg_temp.version_case('empty tiers','{"tiers":[]}');
SELECT pg_temp.version_case('array rate','{"tiers":[{"floor":0,"ceiling":null,"rate":[0.43215]}]}');
SELECT pg_temp.version_case('nested array rate','{"tiers":[{"floor":0,"ceiling":null,"rate":[[0.43215]]}]}');
SELECT pg_temp.version_case('exact numeric tail','{"tiers":[{"floor":0,"ceiling":null,"rate":0.432100000000000000000001}]}');
SELECT public.assert_reference_version('rate_items',pg_temp.cid('A'),1);
SELECT pg_temp.attempt('scalar five decimals',$s$INSERT INTO public.rate_item_versions(tenant_id,rate_item_id,item_name,service_type,calculation_type,regulatory_class,effective_date,change_type,rate_value)
VALUES(pg_temp.cid('tenant'),pg_temp.cid('A'),'A','gas','per_unit_usage','regulated','2026-01-01','initial',0.43215)$s$);
SELECT pg_temp.attempt('scalar four decimals',$s$INSERT INTO public.rate_item_versions(tenant_id,rate_item_id,item_name,service_type,calculation_type,regulatory_class,effective_date,change_type,rate_value)
VALUES(pg_temp.cid('tenant'),pg_temp.cid('A'),'A','gas','per_unit_usage','regulated','2026-01-01','initial',0.4321)$s$);
SELECT pg_temp.attempt('override five decimals',$s$INSERT INTO public.rate_schedule_items(tenant_id,rate_schedule_id,rate_item_id,effective_date,rate_override)
VALUES(pg_temp.cid('tenant'),pg_temp.cid('schedule'),pg_temp.cid('A'),'2026-01-01',0.43215)$s$);
SELECT pg_temp.attempt('override four decimals',$s$INSERT INTO public.rate_schedule_items(tenant_id,rate_schedule_id,rate_item_id,effective_date,rate_override)
VALUES(pg_temp.cid('tenant'),pg_temp.cid('schedule'),pg_temp.cid('A'),'2026-01-01',0.4321)$s$);
RESET ROLE;
SELECT pg_temp.attempt('flush all constraints','SET CONSTRAINTS ALL IMMEDIATE');
ROLLBACK;
