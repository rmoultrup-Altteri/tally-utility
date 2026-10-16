-- R2 prediction: prior defect is fixed; notices report actual outcomes. NOT EXECUTED.
-- Codex r3 source-review probe. NOT EXECUTED by reviewer.
-- Run with psql -U tally -d <fresh-clone-with-frozen-patch> -f this-file.sql
-- Requires the clone owner/superuser; no role DDL, no commits; all changes roll back.
-- OBSERVED notices report behavior, not a pre-declared pass. Unexpected setup errors stop psql.
\set ON_ERROR_STOP on
BEGIN ISOLATION LEVEL READ COMMITTED;
SET LOCAL search_path = public, pg_temp;
SET LOCAL client_min_messages = notice;
DO $$
DECLARE t uuid := gen_random_uuid(); t2 uuid := gen_random_uuid();
        c uuid := gen_random_uuid(); c2 uuid := gen_random_uuid();
        u uuid := gen_random_uuid(); pa uuid := gen_random_uuid(); p uuid := gen_random_uuid();
BEGIN
  PERFORM set_config('codex.t', t::text, true); PERFORM set_config('codex.t2', t2::text, true);
  PERFORM set_config('codex.c', c::text, true); PERFORM set_config('codex.c2', c2::text, true);
  PERFORM set_config('codex.u', u::text, true); PERFORM set_config('codex.pa', pa::text, true);
  PERFORM set_config('codex.p', p::text, true);
  INSERT INTO public.tenants(id,name,slug) VALUES(t,'Codex probe','cx-'||t),(t2,'Codex other','cx-'||t2);
  INSERT INTO public.users(id,tenant_id,display_name,email,role,is_active)
  VALUES(u,t,'Supervisor',u||'@codex.test','tenant_admin',true),
        (pa,t,'Platform admin',pa||'@codex.test','platform_admin',true);
  INSERT INTO public.customers(id,tenant_id,customer_number,customer_type)
  VALUES(c,t,'CX-1','residential'),(c2,t2,'CX-2','residential');
  INSERT INTO public.accounting_periods(id,tenant_id,period_start,period_end)
  VALUES(p,t,DATE '2020-01-01',DATE '2020-01-31');
  PERFORM set_config('app.user_id',u::text,true);
END $$;
SET LOCAL ROLE tally_app;
DO $$
DECLARE t uuid := current_setting('codex.t')::uuid; m uuid := gen_random_uuid();
        at_read timestamptz; before_id uuid; after_id uuid;
BEGIN
  INSERT INTO public.gl_account_mappings(id,tenant_id,gl_account,effective_from)
  VALUES(m,t,'1200',DATE '2020-01-01');
  at_read := clock_timestamp();
  before_id := public.gl_mapping_as_of(t,'ledger_entry','charge',NULL,NULL,NULL,DATE '2020-03-01',at_read);
  UPDATE public.gl_account_mappings SET effective_to=DATE '2020-02-01' WHERE id=m;
  after_id := public.gl_mapping_as_of(t,'ledger_entry','charge',NULL,NULL,NULL,DATE '2020-03-01',at_read);
  RAISE NOTICE 'OBSERVED N3 at=% before=% after=% close stamp=%',at_read,before_id,after_id,
    (SELECT closed_at FROM public.gl_account_mappings WHERE id=m);
END $$;

RESET ROLE;
ROLLBACK;
