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

INSERT INTO public.custom_field_definitions (id,tenant_id,entity_type,field_key,field_label,field_type) VALUES
 ('cd210000-0000-4000-8000-000000000007','cd210000-0000-4000-8000-000000000001','customers','codex_key','Probe key','text');
DO $$
DECLARE n int;
BEGIN
 BEGIN
  WITH gone AS (
   DELETE FROM public.custom_field_definitions WHERE id='cd210000-0000-4000-8000-000000000007' RETURNING tenant_id
  )
  INSERT INTO public.customers (tenant_id,customer_number,metadata)
  SELECT tenant_id,'CODEX-CTE','{"codex_key":1}'::jsonb FROM gone;
  GET DIAGNOSTICS n=ROW_COUNT;
  RAISE NOTICE 'PROBE 03 delete-then-write CTE accepted: inserted=% label_exists=% key_in_use=%',n,
   EXISTS(SELECT 1 FROM public.custom_field_definitions WHERE id='cd210000-0000-4000-8000-000000000007'),
   EXISTS(SELECT 1 FROM public.customers WHERE metadata ? 'codex_key');
 EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'PROBE 03 CTE refused [%] %',SQLSTATE,SQLERRM;
 END;
END $$;
ROLLBACK;
