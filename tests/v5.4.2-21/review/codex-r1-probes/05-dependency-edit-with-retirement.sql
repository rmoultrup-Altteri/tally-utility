\set ON_ERROR_STOP on
-- Run as tally against a throwaway clone with frozen -21 already applied.
BEGIN;
SET LOCAL search_path = public, pg_temp;
SET LOCAL transaction_isolation = 'read committed';
INSERT INTO public.tenants (id,name,slug) VALUES
 ('cd210000-0000-4000-8000-000000000001','Codex probe','codex-r1-probe');
INSERT INTO public.users (id,tenant_id,display_name,email,role,is_active) VALUES
 ('cd210000-0000-4000-8000-000000000002','cd210000-0000-4000-8000-000000000001','Probe','codex-r1@example.test','operator',true);
INSERT INTO public.customers (id,tenant_id,customer_number) VALUES
 ('cd210000-0000-4000-8000-000000000003','cd210000-0000-4000-8000-000000000001','CODEX-R1');
SET ROLE tally_app;
SELECT set_config('app.user_id','cd210000-0000-4000-8000-000000000002',true);

INSERT INTO public.rate_schedules (id,tenant_id,code) VALUES
 ('cd210000-0000-4000-8000-000000000004','cd210000-0000-4000-8000-000000000001','CODEX-SCHEDULE');
INSERT INTO public.rate_items (id,tenant_id,item_code) VALUES
 ('cd210000-0000-4000-8000-000000000005','cd210000-0000-4000-8000-000000000001','CODEX-A'),
 ('cd210000-0000-4000-8000-000000000006','cd210000-0000-4000-8000-000000000001','CODEX-B');
INSERT INTO public.rate_item_dependencies (id,tenant_id,rate_schedule_id,dependent_rate_item_id,base_rate_item_id,notes) VALUES
 ('cd210000-0000-4000-8000-000000000007','cd210000-0000-4000-8000-000000000001','cd210000-0000-4000-8000-000000000004','cd210000-0000-4000-8000-000000000005','cd210000-0000-4000-8000-000000000006','Original');
DO $$ BEGIN
 BEGIN
  UPDATE public.rate_item_dependencies SET notes='Changed',retired_reason='Retire and edit'
   WHERE id='cd210000-0000-4000-8000-000000000007';
  RAISE NOTICE 'PROBE 05 simultaneous notes edit and retirement ACCEPTED (unexpected on frozen patch)';
 EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'PROBE 05 simultaneous edit/retire REFUSED [%] %',SQLSTATE,SQLERRM;
 END;
END $$;
UPDATE public.rate_item_dependencies SET retired_reason='Retire normally'
 WHERE id='cd210000-0000-4000-8000-000000000007';
DO $$ BEGIN
 BEGIN
  UPDATE public.rate_item_dependencies SET retired_reason='Rewrite retirement'
   WHERE id='cd210000-0000-4000-8000-000000000007';
  RAISE NOTICE 'PROBE 05 retirement rewrite ACCEPTED (unexpected on frozen patch)';
 EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'PROBE 05 retirement rewrite REFUSED [%] %',SQLSTATE,SQLERRM;
 END;
END $$;
ROLLBACK;
