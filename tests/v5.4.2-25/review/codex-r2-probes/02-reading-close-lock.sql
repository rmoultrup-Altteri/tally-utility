-- Codex r2: NOT EXECUTED. Run as owner on a fresh clone with frozen r2 applied.
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

-- Lock witness for the predicted two-close race, not an executed two-session race.
-- Real interleaving: committed reading R disputed under open A and B; session 1 closes A,
-- session 2 closes B; both force zz_dispute_reading_released IMMEDIATE before either commits.
-- Each sees the other's old open row. Both can finish without moving R.
-- This rollback-only probe verifies one leg and whether it acquired the sibling mutex.
INSERT INTO public.disputes(id,tenant_id,customer_id,reading_id,subject,received_on,channel) VALUES
 ('00000000-0000-4000-8000-000000002d31','00000000-0000-4000-8000-000000002da1','00000000-0000-4000-8000-000000002dc1','00000000-0000-4000-8000-000000002d71','meter_accuracy','2026-03-02','written'),
 ('00000000-0000-4000-8000-000000002d32','00000000-0000-4000-8000-000000002da1','00000000-0000-4000-8000-000000002dc1','00000000-0000-4000-8000-000000002d71','meter_accuracy','2026-03-02','written');
-- Plant an otherwise legal committed starting state without retaining both advisory locks
-- from the setup UPDATE; restore the trigger before exercising the closing path.
ALTER TABLE public.meter_readings DISABLE TRIGGER a_enforce_reading_dispute_status;
UPDATE public.meter_readings SET status='disputed' WHERE id='00000000-0000-4000-8000-000000002d71';
ALTER TABLE public.meter_readings ENABLE ALWAYS TRIGGER a_enforce_reading_dispute_status;
SELECT public.assert_dispute_guard_invariants();
SET LOCAL ROLE tally_app;
DO $$
BEGIN
 INSERT INTO public.dispute_events(tenant_id,dispute_id,event_type,occurred_on)
 VALUES('00000000-0000-4000-8000-000000002da1','00000000-0000-4000-8000-000000002d31','withdrawn','2026-03-03');
 SET CONSTRAINTS public.zz_dispute_reading_released IMMEDIATE;
 RAISE NOTICE 'first close and release check ACCEPTED SQLSTATE=00000';
EXCEPTION WHEN OTHERS THEN
 RAISE NOTICE 'first close caught SQLSTATE=% message=%',SQLSTATE,SQLERRM;
END $$;
RESET ROLE;
SELECT x.id, x.status, EXISTS (
 SELECT 1 FROM pg_catalog.pg_locks l WHERE l.pid=pg_backend_pid() AND l.locktype='advisory' AND l.objsubid=1
 AND l.classid::bigint=((public.dispute_lock_key(x.id)>>32)&4294967295::bigint)
 AND l.objid::bigint=(public.dispute_lock_key(x.id)&4294967295::bigint)
) AS dispute_mutex_held
FROM public.disputes x WHERE x.reading_id='00000000-0000-4000-8000-000000002d71' ORDER BY x.id;
-- Expected A=true, B=false. No assertion of an executed concurrent commit is made.
ROLLBACK;
