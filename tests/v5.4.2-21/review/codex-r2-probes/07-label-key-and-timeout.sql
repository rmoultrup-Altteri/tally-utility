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

INSERT INTO public.custom_field_definitions(id,tenant_id,entity_type,field_key,field_label,field_type) VALUES
 ('cd210000-0000-4000-8000-000000000007','cd210000-0000-4000-8000-000000000001','customers','r2_unused','Unused','text'),
 ('cd210000-0000-4000-8000-000000000008','cd210000-0000-4000-8000-000000000001','customers','r2_used','Used','text');
UPDATE public.customers SET metadata='{"r2_used":"yes"}' WHERE id='cd210000-0000-4000-8000-000000000003';
INSERT INTO public.custom_location_types(id,tenant_id,type_key,type_label) VALUES
 ('cd210000-0000-4000-8000-000000000009','cd210000-0000-4000-8000-000000000001','r2_unused','Unused');
SET ROLE tally_app;
SELECT set_config('app.user_id','cd210000-0000-4000-8000-000000000002',true);
SET LOCAL lock_timeout='1700ms';
DO $$ BEGIN
 BEGIN
  UPDATE public.custom_field_definitions SET field_key='renamed' WHERE id='cd210000-0000-4000-8000-000000000008';
  RAISE NOTICE 'PROBE 07 app key rewrite ACCEPTED';
 EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'PROBE 07 app key rewrite REFUSED [%] %',SQLSTATE,SQLERRM; END;
 DELETE FROM public.custom_field_definitions WHERE id='cd210000-0000-4000-8000-000000000007';
 RAISE NOTICE 'PROBE 07 successful field delete lock_timeout=% (expected 1700ms)',current_setting('lock_timeout');
 DELETE FROM public.custom_location_types WHERE id='cd210000-0000-4000-8000-000000000009';
 RAISE NOTICE 'PROBE 07 successful location delete lock_timeout=% (expected 1700ms)',current_setting('lock_timeout');
 BEGIN
  DELETE FROM public.custom_field_definitions WHERE id='cd210000-0000-4000-8000-000000000008';
  RAISE NOTICE 'PROBE 07 in-use delete ACCEPTED';
 EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'PROBE 07 in-use delete REFUSED [%] %',SQLSTATE,SQLERRM; END;
 RAISE NOTICE 'PROBE 07 after caught refusal lock_timeout=% (expected 1700ms)',current_setting('lock_timeout');
END $$;
RESET ROLE;
DO $$ BEGIN
 BEGIN
  UPDATE public.custom_field_definitions SET entity_type='billing_runs' WHERE id='cd210000-0000-4000-8000-000000000008';
  RAISE NOTICE 'PROBE 07 owner entity rewrite ACCEPTED';
 EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'PROBE 07 owner entity rewrite REFUSED [%] %',SQLSTATE,SQLERRM; END;
END $$;
-- This single-session probe covers normal return and caught in-use failure,
-- not a contended LOCK's 55P03. LR6 is the existing two-session timeout test.
ROLLBACK;
