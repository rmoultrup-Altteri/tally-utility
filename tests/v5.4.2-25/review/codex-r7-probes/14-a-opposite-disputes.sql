-- R7 reissue; NOT EXECUTED. Predictions reconsidered against frozen r7.
-- NOT EXECUTED. Owner, fresh shared throwaway clone with frozen r7 applied. No role DDL.
-- Schedule: start A to its prompt; start B to its prompt; resume A (blocks); resume B.
-- Predicted: one caught 40P01; survivor completes. A commits shared fixtures only.
\set ON_ERROR_STOP on
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

INSERT INTO public.disputes(id,tenant_id,customer_id,reading_id,subject,received_on,channel) VALUES ('00000000-0000-4000-8000-000000002d31','00000000-0000-4000-8000-000000002da1','00000000-0000-4000-8000-000000002dc1','00000000-0000-4000-8000-000000002d71','meter_accuracy','2026-03-02','written');
INSERT INTO public.disputes(id,tenant_id,customer_id,reading_id,subject,received_on,channel) VALUES ('00000000-0000-4000-8000-000000002d32','00000000-0000-4000-8000-000000002da1','00000000-0000-4000-8000-000000002dc1','00000000-0000-4000-8000-000000002d71','meter_accuracy','2026-03-02','written');
UPDATE public.meter_readings SET status='disputed' WHERE id='00000000-0000-4000-8000-000000002d71';
COMMIT;
BEGIN;
SELECT public.dispute_lock('00000000-0000-4000-8000-000000002d31','opposite-order probe');
\prompt 'First lock held; follow schedule, then press enter: ' proceed
DO $$ BEGIN
 PERFORM public.dispute_lock('00000000-0000-4000-8000-000000002d32','opposite-order probe');
 RAISE NOTICE 'opposite-order a SQLSTATE=00000 second lock acquired';
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'opposite-order a SQLSTATE=% message=%',SQLSTATE,SQLERRM;
END $$;
ROLLBACK;
