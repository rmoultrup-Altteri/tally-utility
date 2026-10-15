\set ON_ERROR_STOP on
-- Source-only handoff. Run as superuser tally on a clone with frozen r4 applied.
-- No role definitions changed; every fixture and attempted write rolls back.
BEGIN;
SET LOCAL search_path = public, pg_temp;
INSERT INTO public.tenants(id,name,slug) VALUES
 ('cd240000-0000-4000-8000-000000000001','R4 own','codex-r4-own'),
 ('cd240000-0000-4000-8000-000000000011','R4 foreign','codex-r4-foreign');
INSERT INTO public.users(id,tenant_id,display_name,email,role,is_active,cognito_sub) VALUES
 ('cd240000-0000-4000-8000-000000000002','cd240000-0000-4000-8000-000000000001','Operator','r4-op@example.test','operator',true,'r4-op'),
 ('cd240000-0000-4000-8000-000000000003','cd240000-0000-4000-8000-000000000001','Supervisor','r4-super@example.test','tenant_admin',true,'r4-super'),
 ('cd240000-0000-4000-8000-000000000004','cd240000-0000-4000-8000-000000000001','Platform','r4-platform@example.test','platform_admin',true,'r4-platform'),
 ('cd240000-0000-4000-8000-000000000005','cd240000-0000-4000-8000-000000000001','Other supervisor','r4-other@example.test','tenant_admin',true,'r4-other'),
 ('cd240000-0000-4000-8000-000000000012','cd240000-0000-4000-8000-000000000011','Foreign platform','r4-foreign@example.test','platform_admin',true,'r4-foreign');

-- Invoker helper: each case has its own exception subtransaction. Even an
-- unexpectedly successful attack is rolled back before the next case.
-- All supplied statements are writes expected to affect exactly one row.
CREATE FUNCTION pg_temp.try_steps(label text, actor uuid, steps text[]) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE statement text; n bigint; step integer := 0;
BEGIN
  PERFORM set_config('app.user_id', actor::text, true);
  BEGIN
    FOREACH statement IN ARRAY steps LOOP
      step := step + 1;
      EXECUTE statement;
      GET DIAGNOSTICS n = ROW_COUNT;
      RAISE NOTICE 'PROBE 01 % step % ACCEPTED rows=%', label, step, n;
      IF n <> 1 THEN
        RAISE EXCEPTION USING ERRCODE='P0002', MESSAGE='probe expected exactly one affected row';
      END IF;
    END LOOP;
    SET CONSTRAINTS ALL IMMEDIATE;
    RAISE NOTICE 'PROBE 01 % ALL STEPS ACCEPTED after ALL constraints', label;
    RAISE EXCEPTION USING ERRCODE='ZP001', MESSAGE='probe rollback';
  EXCEPTION WHEN SQLSTATE 'ZP001' THEN NULL;
    WHEN OTHERS THEN
      RAISE NOTICE 'PROBE 01 % step % REFUSED [%] %', label, step, SQLSTATE, SQLERRM;
  END;
END $$;
GRANT EXECUTE ON FUNCTION pg_temp.try_steps(text,uuid,text[]) TO tally_app;
SET ROLE tally_app;
SELECT set_config('app.user_id','cd240000-0000-4000-8000-000000000002',true);

SELECT pg_temp.try_steps('operator demotes tenant admin','cd240000-0000-4000-8000-000000000002',ARRAY[
 $q$UPDATE users SET role='operator' WHERE id='cd240000-0000-4000-8000-000000000003'$q$]);
SELECT pg_temp.try_steps('tenant admin demotes platform','cd240000-0000-4000-8000-000000000003',ARRAY[
 $q$UPDATE users SET role='tenant_admin' WHERE id='cd240000-0000-4000-8000-000000000004'$q$]);
SELECT pg_temp.try_steps('operator switches supervisor off','cd240000-0000-4000-8000-000000000002',ARRAY[
 $q$UPDATE users SET is_active=false WHERE id='cd240000-0000-4000-8000-000000000003'$q$]);
SELECT pg_temp.try_steps('tenant admin clears platform binding','cd240000-0000-4000-8000-000000000003',ARRAY[
 $q$UPDATE users SET cognito_sub=NULL WHERE id='cd240000-0000-4000-8000-000000000004'$q$]);
SELECT pg_temp.try_steps('supervisor clears bound tenant admin','cd240000-0000-4000-8000-000000000003',ARRAY[
 $q$UPDATE users SET cognito_sub=NULL WHERE id='cd240000-0000-4000-8000-000000000005'$q$]);
SELECT pg_temp.try_steps('operator rekeys tenant admin','cd240000-0000-4000-8000-000000000002',ARRAY[
 $q$UPDATE users SET id='cd240000-0000-4000-8000-000000000099' WHERE id='cd240000-0000-4000-8000-000000000003'$q$]);
SELECT pg_temp.try_steps('tenant admin rekeys platform','cd240000-0000-4000-8000-000000000003',ARRAY[
 $q$UPDATE users SET id='cd240000-0000-4000-8000-000000000099' WHERE id='cd240000-0000-4000-8000-000000000004'$q$]);
SELECT pg_temp.try_steps('operator moves supervisor to foreign tenant','cd240000-0000-4000-8000-000000000002',ARRAY[
 $q$UPDATE users SET tenant_id='cd240000-0000-4000-8000-000000000011' WHERE id='cd240000-0000-4000-8000-000000000003'$q$]);
SELECT pg_temp.try_steps('tenant admin moves platform to foreign tenant','cd240000-0000-4000-8000-000000000003',ARRAY[
 $q$UPDATE users SET tenant_id='cd240000-0000-4000-8000-000000000011' WHERE id='cd240000-0000-4000-8000-000000000004'$q$]);
SELECT pg_temp.try_steps('combined demotion deactivation rekey and tenant move','cd240000-0000-4000-8000-000000000003',ARRAY[
 $q$UPDATE users SET role='operator',is_active=false,id='cd240000-0000-4000-8000-000000000099',tenant_id='cd240000-0000-4000-8000-000000000011' WHERE id='cd240000-0000-4000-8000-000000000004'$q$]);
SELECT pg_temp.try_steps('demote then deactivate platform','cd240000-0000-4000-8000-000000000003',ARRAY[
 $q$UPDATE users SET role='operator' WHERE id='cd240000-0000-4000-8000-000000000004'$q$,
 $q$UPDATE users SET is_active=false WHERE id='cd240000-0000-4000-8000-000000000004'$q$]);
SELECT pg_temp.try_steps('move then demote supervisor','cd240000-0000-4000-8000-000000000002',ARRAY[
 $q$UPDATE users SET tenant_id='cd240000-0000-4000-8000-000000000011' WHERE id='cd240000-0000-4000-8000-000000000003'$q$,
 $q$UPDATE users SET role='operator' WHERE id='cd240000-0000-4000-8000-000000000003'$q$]);
SELECT pg_temp.try_steps('no-op role then demote platform','cd240000-0000-4000-8000-000000000003',ARRAY[
 $q$UPDATE users SET role=role,is_active=is_active,cognito_sub=cognito_sub WHERE id='cd240000-0000-4000-8000-000000000004'$q$,
 $q$UPDATE users SET role='operator' WHERE id='cd240000-0000-4000-8000-000000000004'$q$]);
SELECT pg_temp.try_steps('delete then reinsert administrator','cd240000-0000-4000-8000-000000000002',ARRAY[
 $q$DELETE FROM users WHERE id='cd240000-0000-4000-8000-000000000003'$q$,
 $q$INSERT INTO users(id,tenant_id,display_name,email,role) VALUES ('cd240000-0000-4000-8000-000000000003','cd240000-0000-4000-8000-000000000001','Replacement','r4-replacement@example.test','operator')$q$]);

-- Positive controls, including the missing-id fixture error in the r3 probe.
SELECT pg_temp.try_steps('authorized tenant demotion then deactivation','cd240000-0000-4000-8000-000000000003',ARRAY[
 $q$UPDATE users SET role='operator' WHERE id='cd240000-0000-4000-8000-000000000005'$q$,
 $q$UPDATE users SET is_active=false WHERE id='cd240000-0000-4000-8000-000000000005'$q$]);
SELECT pg_temp.try_steps('authorized foreign platform combined demotion','cd240000-0000-4000-8000-000000000012',ARRAY[
 $q$UPDATE users SET role='operator',is_active=false,tenant_id='cd240000-0000-4000-8000-000000000011' WHERE id='cd240000-0000-4000-8000-000000000004'$q$]);
SELECT pg_temp.try_steps('authorized bound platform insert with explicit id','cd240000-0000-4000-8000-000000000012',ARRAY[
 $q$INSERT INTO users(id,tenant_id,display_name,email,role,cognito_sub) VALUES ('cd240000-0000-4000-8000-000000000099','cd240000-0000-4000-8000-000000000001','Born platform','r4-born@example.test','platform_admin','r4-born')$q$]);
ROLLBACK;
