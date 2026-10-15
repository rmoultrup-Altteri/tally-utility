\set ON_ERROR_STOP on
-- Run as superuser tally on a clone with frozen r3 applied. Entirely rolled back.
BEGIN;
SET LOCAL search_path = public, pg_temp;
INSERT INTO public.tenants(id,name,slug) VALUES
 ('cd230000-0000-4000-8000-000000000001','R3 own','codex-r3-own'),
 ('cd230000-0000-4000-8000-000000000011','R3 foreign','codex-r3-foreign');
INSERT INTO public.users(id,tenant_id,display_name,email,role,is_active) VALUES
 ('cd230000-0000-4000-8000-000000000002','cd230000-0000-4000-8000-000000000001','Supervisor','r3-super@example.test','tenant_admin',true),
 ('cd230000-0000-4000-8000-000000000003','cd230000-0000-4000-8000-000000000001','Inactive platform','r3-inactive@example.test','platform_admin',false),
 ('cd230000-0000-4000-8000-000000000004','cd230000-0000-4000-8000-000000000001','Operator','r3-op@example.test','operator',true),
 ('cd230000-0000-4000-8000-000000000012','cd230000-0000-4000-8000-000000000011','Foreign platform','r3-platform@example.test','platform_admin',true);
CREATE FUNCTION pg_temp.attempt(p_label text,p_sql text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE n bigint;
BEGIN
 EXECUTE p_sql; GET DIAGNOSTICS n=ROW_COUNT;
 RAISE NOTICE 'PROBE 01 % ACCEPTED rows=%',p_label,n;
EXCEPTION WHEN OTHERS THEN
 RAISE NOTICE 'PROBE 01 % REFUSED [%] %',p_label,SQLSTATE,SQLERRM;
END $$;
GRANT EXECUTE ON FUNCTION pg_temp.attempt(text,text) TO tally_app;
SET ROLE tally_app;
SELECT set_config('app.user_id','cd230000-0000-4000-8000-000000000002',true);
SELECT pg_temp.attempt('tenant binds inactive platform', $q$UPDATE public.users SET cognito_sub='r3-bind' WHERE id='cd230000-0000-4000-8000-000000000003'$q$);
SELECT pg_temp.attempt('tenant inserts bound platform', $q$INSERT INTO public.users(tenant_id,display_name,email,role,cognito_sub) VALUES ('cd230000-0000-4000-8000-000000000001','Born platform','r3-born@example.test','platform_admin','r3-born')$q$);
SELECT pg_temp.attempt('tenant demotes and binds platform in same UPDATE', $q$UPDATE public.users SET role='operator',cognito_sub='r3-demote' WHERE id='cd230000-0000-4000-8000-000000000003'$q$);
SELECT pg_temp.attempt('tenant promotes and binds operator in same UPDATE', $q$UPDATE public.users SET role='platform_admin',cognito_sub='r3-promote' WHERE id='cd230000-0000-4000-8000-000000000004'$q$);
SELECT pg_temp.attempt('tenant switches foreign platform off (expect zero rows)', $q$UPDATE public.users SET is_active=false WHERE id='cd230000-0000-4000-8000-000000000012'$q$);
SELECT set_config('app.user_id','cd230000-0000-4000-8000-000000000012',true);
SELECT pg_temp.attempt('foreign platform binds and revives platform (expect one row)', $q$UPDATE public.users SET cognito_sub='r3-authorized',is_active=true WHERE id='cd230000-0000-4000-8000-000000000003'$q$);
SELECT pg_temp.attempt('foreign platform inserts bound platform (expect one row)', $q$INSERT INTO public.users(tenant_id,display_name,email,role,cognito_sub) VALUES ('cd230000-0000-4000-8000-000000000001','Born platform','r3-born@example.test','platform_admin','r3-born')$q$);
SELECT pg_temp.attempt('foreign platform switches platform off (expect one row)', $q$UPDATE public.users SET is_active=false WHERE id='cd230000-0000-4000-8000-000000000003'$q$);
ROLLBACK;
