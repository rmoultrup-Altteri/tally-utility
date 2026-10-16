-- Codex r2 source-review probe. NOT EXECUTED by reviewer.
-- Run with psql -U tally -d <fresh-clone-with-frozen-r2-patch> -f this-file.sql
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

-- PREDICTED: both short-cycle INSERT statement shapes raise 23514.
SET LOCAL ROLE tally_app;
DO $$
DECLARE t uuid := current_setting('codex.t')::uuid; c uuid := current_setting('codex.c')::uuid;
        a uuid := gen_random_uuid(); b uuid := gen_random_uuid(); n integer;
BEGIN
  BEGIN
    INSERT INTO public.account_ledger(id,tenant_id,customer_id,transaction_date,transaction_type,description,amount,reverses_ledger_entry_id,reversal_reason)
    VALUES(a,t,c,DATE '2020-01-05','adjustment','cycle A',100,b,'offset'),
          (b,t,c,DATE '2020-01-06','adjustment','cycle B',-40,a,'offset');
    RAISE NOTICE 'multi-row cycle accepted';
  EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'multi-row cycle SQLSTATE=% message=%',SQLSTATE,SQLERRM; END;
  a:=gen_random_uuid(); b:=gen_random_uuid();
  BEGIN
    WITH first_row AS (
      INSERT INTO public.account_ledger(id,tenant_id,customer_id,transaction_date,transaction_type,description,amount,reverses_ledger_entry_id,reversal_reason)
      VALUES(a,t,c,DATE '2020-01-05','adjustment','CTE A',100,b,'offset') RETURNING id
    )
    INSERT INTO public.account_ledger(id,tenant_id,customer_id,transaction_date,transaction_type,description,amount,reverses_ledger_entry_id,reversal_reason)
    SELECT b,t,c,DATE '2020-01-06','adjustment','CTE B',-40,id,'offset' FROM first_row;
    RAISE NOTICE 'writable CTE cycle accepted';
  EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'writable CTE cycle SQLSTATE=% message=%',SQLSTATE,SQLERRM; END;
END $$;

RESET ROLE;
ROLLBACK;
