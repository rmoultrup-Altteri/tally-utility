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
-- Expected defect: a legal multi-row INSERT creates a two-entry cycle; balance 60 has no aging row.
SET LOCAL ROLE tally_app;
DO $$
DECLARE t uuid := current_setting('codex.t')::uuid; c uuid := current_setting('codex.c')::uuid;
        a uuid := gen_random_uuid(); b uuid := gen_random_uuid(); n integer; aged numeric; ledger numeric;
BEGIN
  BEGIN
    INSERT INTO public.account_ledger(id,tenant_id,customer_id,transaction_date,transaction_type,description,amount,reverses_ledger_entry_id,reversal_reason)
    VALUES(a,t,c,DATE '2020-01-05','adjustment','cycle A',100,b,'offset'),
          (b,t,c,DATE '2020-01-06','adjustment','cycle B',-40,a,'offset');
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'OBSERVED B3 cycle refused: % %',SQLSTATE,SQLERRM; RETURN;
  END;
  SELECT sum(amount) INTO ledger FROM public.account_ledger WHERE tenant_id=t;
  SELECT count(*),sum(amount) INTO n,aged FROM public.receivables_aging_as_of(t,DATE '2020-01-31',clock_timestamp());
  RAISE NOTICE 'OBSERVED B3 ledger=% aging rows=% aging sum=%',ledger,n,aged;
  PERFORM public.close_accounting_period(current_setting('codex.p')::uuid);
  RAISE NOTICE 'OBSERVED B3 snapshot closing=% aging lines=%',
    (SELECT closing_balance FROM public.accounting_period_snapshots WHERE period_id=current_setting('codex.p')::uuid),
    (SELECT count(*) FROM public.accounting_period_snapshot_lines WHERE period_id=current_setting('codex.p')::uuid AND section='aging');
END $$;

RESET ROLE;
ROLLBACK;
