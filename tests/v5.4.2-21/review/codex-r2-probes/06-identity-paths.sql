\set ON_ERROR_STOP on
-- Run as tally against a throwaway clone with patch-21-frozen-r2.sql already applied.
BEGIN;
SET LOCAL search_path = public, pg_temp;
SET LOCAL transaction_isolation = 'read committed';
INSERT INTO public.tenants (id,name,slug) VALUES
 ('cd210000-0000-4000-8000-000000000001','Codex probe','codex-r2-probe');
INSERT INTO public.users (id,tenant_id,display_name,email,role,is_active) VALUES
 ('cd210000-0000-4000-8000-000000000002','cd210000-0000-4000-8000-000000000001','Probe','codex-r2@example.test','operator',true);
INSERT INTO public.customers (id,tenant_id,customer_number) VALUES
 ('cd210000-0000-4000-8000-000000000003','cd210000-0000-4000-8000-000000000001','CODEX-R2');
INSERT INTO public.service_locations (id,tenant_id,customer_id,location_number,address_line1,city,state,zip) VALUES
 ('cd210000-0000-4000-8000-000000000004','cd210000-0000-4000-8000-000000000001','cd210000-0000-4000-8000-000000000003','CODEX-LOC','1 Main','Austin','TX','78701');

INSERT INTO public.tenants(id,name,slug) VALUES
 ('cd210000-0000-4000-8000-000000000011','Other tenant','codex-r2-other');
INSERT INTO public.users(id,tenant_id,display_name,email,role,is_active) VALUES
 ('cd210000-0000-4000-8000-000000000012','cd210000-0000-4000-8000-000000000001','Supervisor','r2-super@example.test','tenant_admin',true),
 ('cd210000-0000-4000-8000-000000000013','cd210000-0000-4000-8000-000000000001','Inactive','r2-inactive@example.test','tenant_admin',false),
 ('cd210000-0000-4000-8000-000000000014','cd210000-0000-4000-8000-000000000011','Platform','r2-platform@example.test','platform_admin',true);
-- Invoker helper logs the actual row count, so a zero-row RLS UPDATE is not
-- mistaken for an authorized write. No SECURITY DEFINER escape is installed.
CREATE FUNCTION pg_temp.attempt(p_label text,p_sql text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE n bigint;
BEGIN
 EXECUTE p_sql; GET DIAGNOSTICS n=ROW_COUNT;
 RAISE NOTICE 'PROBE 06 % ACCEPTED rows=% role=%',p_label,n,current_user;
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'PROBE 06 % REFUSED [%] %',p_label,SQLSTATE,SQLERRM;
END $$;
GRANT EXECUTE ON FUNCTION pg_temp.attempt(text,text) TO tally_app,tally_core;
SET ROLE tally_app;
SELECT set_config('app.user_id','cd210000-0000-4000-8000-000000000002',true);
SELECT pg_temp.attempt('operator binds administrator', $q$UPDATE public.users SET cognito_sub='r2-attack' WHERE id='cd210000-0000-4000-8000-000000000012'$q$);
SELECT pg_temp.attempt('operator revives administrator', $q$UPDATE public.users SET is_active=true WHERE id='cd210000-0000-4000-8000-000000000013'$q$);
SELECT pg_temp.attempt('operator inserts bound user', $q$INSERT INTO public.users(tenant_id,display_name,email,role,cognito_sub) VALUES ('cd210000-0000-4000-8000-000000000001','Bound','r2-bound@example.test','operator','r2-born-bound')$q$);
SELECT pg_temp.attempt('operator inserts unbound active administrator', $q$INSERT INTO public.users(tenant_id,display_name,email,role,is_active) VALUES ('cd210000-0000-4000-8000-000000000001','Born admin','r2-bornadmin@example.test','tenant_admin',true)$q$);
SELECT pg_temp.attempt('operator upserts inactive administrator active', $q$INSERT INTO public.users(id,tenant_id,display_name,email,role,is_active) VALUES ('cd210000-0000-4000-8000-000000000013','cd210000-0000-4000-8000-000000000001','Conflict','r2-upsert@example.test','operator',true) ON CONFLICT (id) DO UPDATE SET is_active=EXCLUDED.is_active$q$);
SELECT set_config('app.user_id','cd210000-0000-4000-8000-000000000012',true);
SELECT pg_temp.attempt('tenant supervisor binds own operator', $q$UPDATE public.users SET cognito_sub='r2-operator' WHERE id='cd210000-0000-4000-8000-000000000002'$q$);
SELECT pg_temp.attempt('tenant supervisor updates foreign platform user', $q$UPDATE public.users SET cognito_sub='r2-foreign' WHERE id='cd210000-0000-4000-8000-000000000014'$q$);
SELECT set_config('app.user_id','cd210000-0000-4000-8000-000000000014',true);
SELECT pg_temp.attempt('foreign platform admin binds tenant supervisor', $q$UPDATE public.users SET cognito_sub='r2-supervisor' WHERE id='cd210000-0000-4000-8000-000000000012'$q$);
SELECT pg_temp.attempt('platform admin rewrites binding', $q$UPDATE public.users SET cognito_sub='r2-rewrite' WHERE id='cd210000-0000-4000-8000-000000000012'$q$);
RESET ROLE;
SET ROLE tally_core;
SELECT set_config('app.user_id','cd210000-0000-4000-8000-000000000014',true);
SELECT pg_temp.attempt('core attempts identity update', $q$UPDATE public.users SET cognito_sub='r2-core' WHERE id='cd210000-0000-4000-8000-000000000013'$q$);
RESET ROLE;
SELECT pg_temp.attempt('superuser repairs binding', $q$UPDATE public.users SET cognito_sub='r2-owner-repair' WHERE id='cd210000-0000-4000-8000-000000000002'$q$);
DO $$ DECLARE r text; BEGIN
 FOREACH r IN ARRAY ARRAY['tally_core','tally_seal','tally_void'] LOOP
  RAISE NOTICE 'PROBE 06 role=% users INSERT=% binding UPDATE=% active UPDATE=% app can become=%',r,
   has_table_privilege(r,'public.users','INSERT'),
   has_column_privilege(r,'public.users','cognito_sub','UPDATE'),
   has_column_privilege(r,'public.users','is_active','UPDATE'),
   pg_has_role('tally_app',r,'MEMBER');
 END LOOP;
END $$;
ROLLBACK;
