-- Codex r1 source-review probe. NOT EXECUTED by reviewer.
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
-- Expected defect: stored 0-30=100 becomes recomputed 16-45=100 at the SAME coordinate.
SET LOCAL ROLE tally_app;
DO $$
DECLARE t uuid := current_setting('codex.t')::uuid; c uuid := current_setting('codex.c')::uuid;
        p uuid := current_setting('codex.p')::uuid; at_close timestamptz; before_rows jsonb; after_rows jsonb;
BEGIN
  INSERT INTO public.account_ledger(tenant_id,customer_id,transaction_date,transaction_type,description,amount)
  VALUES(t,c,DATE '2020-01-05','charge','coordinate probe',100);
  at_close := public.close_accounting_period(p);
  SELECT jsonb_agg(to_jsonb(a)) INTO before_rows FROM public.receivables_aging_as_of(t,DATE '2020-01-31',at_close) a;
  UPDATE public.tenants SET receivables_aging_bucket_days=ARRAY[15,45] WHERE id=t;
  SELECT jsonb_agg(to_jsonb(a)) INTO after_rows FROM public.receivables_aging_as_of(t,DATE '2020-01-31',at_close) a;
  RAISE NOTICE 'OBSERVED B1 before=% after=% changed=%',before_rows,after_rows,before_rows IS DISTINCT FROM after_rows;
  RAISE NOTICE 'OBSERVED B1 snapshot edges=%; as-of edges=%',
    (SELECT aging_bucket_days FROM public.accounting_period_snapshots WHERE period_id=p),
    public.receivables_aging_bucket_days_as_of(t,at_close);
  BEGIN
    INSERT INTO public.tenant_configuration_history
      (tenant_id,config_key,old_value,new_value,effective_from,change_source,change_reason)
    VALUES(t,'receivables_aging_bucket_days','[15,45]'::jsonb,'[10,20]'::jsonb,at_close,'manual','probe backdated history');
    RAISE NOTICE 'OBSERVED B1 manual backdate accepted; same-coordinate edges now=%',
      public.receivables_aging_bucket_days_as_of(t,at_close);
  EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'OBSERVED B1 manual history refused: % %',SQLSTATE,SQLERRM;
  END;
END $$;

RESET ROLE;
ROLLBACK;
