-- Codex r3: NOT EXECUTED. Run as owner on a fresh clone with frozen r3 applied.
-- No role is created, dropped, or altered. All fixture changes roll back.
\set ON_ERROR_STOP on
\set VERBOSITY verbose
BEGIN ISOLATION LEVEL READ COMMITTED;
SET LOCAL search_path = public, pg_temp;
INSERT INTO public.tenants (id,name,slug) VALUES ('00000000-0000-4000-8000-000000002da1','Codex r2','codex-r2');
INSERT INTO public.users (id,tenant_id,display_name,email,role) VALUES
 ('00000000-0000-4000-8000-000000002db1','00000000-0000-4000-8000-000000002da1','Operator','codex-r2@example.test','operator');
INSERT INTO public.customers (id,tenant_id,customer_number,customer_type) VALUES
 ('00000000-0000-4000-8000-000000002dc1','00000000-0000-4000-8000-000000002da1','CR2','residential');
INSERT INTO public.service_locations (id,tenant_id,customer_id,location_number,address_line1,city,state,zip) VALUES
 ('00000000-0000-4000-8000-000000002dd1','00000000-0000-4000-8000-000000002da1','00000000-0000-4000-8000-000000002dc1','CR2','1 Main','Austin','TX','78701');
INSERT INTO public.meters (id,tenant_id,meter_number,location_id,service_type) VALUES
 ('00000000-0000-4000-8000-000000002de1','00000000-0000-4000-8000-000000002da1','CR2','00000000-0000-4000-8000-000000002dd1','gas');
INSERT INTO public.meter_readings (id,tenant_id,meter_id,reading_date,reading_value) VALUES
 ('00000000-0000-4000-8000-000000002d71','00000000-0000-4000-8000-000000002da1','00000000-0000-4000-8000-000000002de1',DATE '2026-03-01',50);
SET LOCAL app.user_id = '00000000-0000-4000-8000-000000002db1';

INSERT INTO public.disputes(id,tenant_id,customer_id,reading_id,subject,received_on,channel)
VALUES('00000000-0000-4000-8000-000000002d31','00000000-0000-4000-8000-000000002da1','00000000-0000-4000-8000-000000002dc1','00000000-0000-4000-8000-000000002d71','meter_accuracy','2026-03-02','written');

-- Without a session identity, even the owner's close must fail at the RLS-bound move.
SET LOCAL app.user_id = '';
DO $$ BEGIN
 BEGIN
  INSERT INTO public.dispute_events(tenant_id,dispute_id,event_type,occurred_on)
  VALUES('00000000-0000-4000-8000-000000002da1','00000000-0000-4000-8000-000000002d31','withdrawn','2026-03-03');
  RAISE NOTICE 'missing-identity close ACCEPTED SQLSTATE=00000 (unexpected)';
 EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'missing-identity close caught SQLSTATE=% message=%',SQLSTATE,SQLERRM;
 END;
END $$;
SET LOCAL app.user_id = '00000000-0000-4000-8000-000000002db1';
SET LOCAL ROLE tally_core;
DO $$ BEGIN
 BEGIN
  UPDATE public.disputes SET status='withdrawn' WHERE id='00000000-0000-4000-8000-000000002d31';
  RAISE NOTICE 'core update ACCEPTED SQLSTATE=00000 (unexpected)';
 EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'core update caught SQLSTATE=% message=%',SQLSTATE,SQLERRM;
 END;
END $$;
RESET ROLE;
SET LOCAL ROLE tally_app;
DO $$ BEGIN
 BEGIN
  UPDATE public.disputes SET status='withdrawn' WHERE id='00000000-0000-4000-8000-000000002d31';
  RAISE NOTICE 'app update ACCEPTED SQLSTATE=00000 (unexpected)';
 EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'app update caught SQLSTATE=% message=%',SQLSTATE,SQLERRM;
 END;
END $$;
RESET ROLE;
SET LOCAL session_replication_role = replica;
DO $$ BEGIN
 BEGIN
  INSERT INTO public.dispute_events(tenant_id,dispute_id,event_type,occurred_on)
  VALUES('00000000-0000-4000-8000-000000002da1','00000000-0000-4000-8000-000000002d31','withdrawn','2026-03-03');
  RAISE NOTICE 'replica owner close SQLSTATE=00000 status=%',(SELECT status FROM public.disputes WHERE id='00000000-0000-4000-8000-000000002d31');
 EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'replica owner close caught SQLSTATE=% message=%',SQLSTATE,SQLERRM;
 END;
END $$;
SET LOCAL session_replication_role = origin;
SELECT public.assert_seal_role_invariants();
ROLLBACK;
BEGIN ISOLATION LEVEL REPEATABLE READ;
DO $$ BEGIN
 PERFORM public.dispute_lock('00000000-0000-4000-8000-000000002d31','Codex repeatable read probe');
 RAISE NOTICE 'RR lock ACCEPTED SQLSTATE=00000 (unexpected)';
EXCEPTION WHEN OTHERS THEN
 RAISE NOTICE 'RR caught SQLSTATE=% message=%',SQLSTATE,SQLERRM;
END $$;
ROLLBACK;
BEGIN ISOLATION LEVEL SERIALIZABLE;
DO $$ BEGIN
 PERFORM public.dispute_lock('00000000-0000-4000-8000-000000002d31','Codex serializable probe');
 RAISE NOTICE 'serializable lock ACCEPTED SQLSTATE=00000 (unexpected)';
EXCEPTION WHEN OTHERS THEN
 RAISE NOTICE 'serializable caught SQLSTATE=% message=%',SQLSTATE,SQLERRM;
END $$;
ROLLBACK;
BEGIN ISOLATION LEVEL READ UNCOMMITTED;
DO $$ BEGIN
 PERFORM public.dispute_lock('00000000-0000-4000-8000-000000002d31','Codex read uncommitted probe');
 RAISE NOTICE 'read-uncommitted lock ACCEPTED SQLSTATE=00000 (unexpected)';
EXCEPTION WHEN OTHERS THEN
 RAISE NOTICE 'read-uncommitted caught SQLSTATE=% message=%',SQLSTATE,SQLERRM;
END $$;
ROLLBACK;
