-- NOT EXECUTED. Owner on a FRESH THROWAWAY clone with frozen r3 applied.
-- No roles are created, dropped or altered. Only A commits the shared fixture.
-- The author drops the scratch clone afterward. Both files end in ROLLBACK.
\set ON_ERROR_STOP on
\set VERBOSITY verbose
-- SCHEDULE: start A; start B at A1. When B reaches B1, resume A1.
-- A waits upgrading its reading FK KEY SHARE to FOR UPDATE. Resume B1.
-- One session should print 40P01; after that session rolls back the other succeeds.
-- No UPDATE of meter_readings.status is made by either actor.
BEGIN;
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

COMMIT;
BEGIN ISOLATION LEVEL READ COMMITTED;
SET LOCAL search_path=public,pg_temp;
SET LOCAL app.user_id='00000000-0000-4000-8000-000000002db1';
SET LOCAL ROLE tally_app;
INSERT INTO public.disputes(id,tenant_id,customer_id,reading_id,subject,received_on,channel) VALUES ('00000000-0000-4000-8000-000000002d31','00000000-0000-4000-8000-000000002da1','00000000-0000-4000-8000-000000002dc1','00000000-0000-4000-8000-000000002d71','meter_accuracy','2026-03-02','written');
INSERT INTO public.dispute_events(tenant_id,dispute_id,event_type,occurred_on) VALUES ('00000000-0000-4000-8000-000000002da1','00000000-0000-4000-8000-000000002d31','withdrawn','2026-03-03');
\prompt 'A1: start B; when B reaches B1, press Enter: ' proceed
DO $$ BEGIN
 SET CONSTRAINTS public.zz_dispute_reading_released IMMEDIATE;
 RAISE NOTICE 'FK upgrade A SQLSTATE=00000 release accepted';
EXCEPTION WHEN OTHERS THEN
 RAISE NOTICE 'FK upgrade A SQLSTATE=% message=%',SQLSTATE,SQLERRM;
END $$;
ROLLBACK;
