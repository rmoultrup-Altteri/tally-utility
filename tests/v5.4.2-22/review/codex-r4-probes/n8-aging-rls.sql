-- PREDICTED; not executed by Codex. Run as owner/superuser on a fresh clone
-- with frozen r4 strictly applied and TEMP revoked from PUBLIC, tally_app, tally_core.
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

INSERT INTO public.account_ledger(tenant_id,customer_id,transaction_date,transaction_type,description,amount)
VALUES(current_setting('codex.t')::uuid,current_setting('codex.c')::uuid,DATE '2020-01-05','charge','tenant one',100),
      (current_setting('codex.t2')::uuid,current_setting('codex.c2')::uuid,DATE '2020-01-05','charge','tenant two',200);
SET LOCAL ROLE tally_app;
DO $$
DECLARE n integer; total numeric;
BEGIN
 SELECT count(*),sum(amount) INTO n,total FROM public.receivables_aging_as_of(current_setting('codex.t')::uuid,DATE '2020-01-31',clock_timestamp(),ARRAY[30]);
 RAISE NOTICE 'tenant own aging rows=% sum=%',n,total;
 BEGIN
  PERFORM * FROM public.receivables_aging_as_of(current_setting('codex.t2')::uuid,DATE '2020-01-31',clock_timestamp(),ARRAY[30]);
  RAISE NOTICE 'tenant cross-tenant explicit aging accepted';
 EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'tenant cross-tenant SQLSTATE=% message=%',SQLSTATE,SQLERRM; END;
 PERFORM set_config('app.user_id',current_setting('codex.pa'),true);
 SELECT count(*),sum(amount) INTO n,total FROM public.receivables_aging_as_of(current_setting('codex.t')::uuid,DATE '2020-01-31',clock_timestamp(),ARRAY[30]);
 RAISE NOTICE 'platform requested tenant one rows=% sum=%',n,total;
 SELECT count(*),sum(amount) INTO n,total FROM public.receivables_aging_as_of(current_setting('codex.t2')::uuid,DATE '2020-01-31',clock_timestamp(),ARRAY[30]);
 RAISE NOTICE 'platform requested tenant two rows=% sum=%',n,total;
END $$;
RESET ROLE;
ROLLBACK;
