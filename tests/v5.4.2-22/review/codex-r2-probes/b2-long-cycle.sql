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

-- PREDICTED B2: 10001-node cycle passes the 10000-step walk.
-- This is deliberately large: roughly 100 million recursive steps with all guards enabled.
-- No timeout is imposed; a cancellation is inconclusive, not a guard success.
SET LOCAL ROLE tally_app;
DO $$
DECLARE t uuid := current_setting('codex.t')::uuid; c uuid := current_setting('codex.c')::uuid;
        ids uuid[]; n integer := 10001;
BEGIN
  SELECT array_agg(gen_random_uuid() ORDER BY i) INTO ids FROM generate_series(1,n) i;
  BEGIN
    INSERT INTO public.account_ledger(id,tenant_id,customer_id,transaction_date,transaction_type,description,amount,reverses_ledger_entry_id,reversal_reason)
    SELECT ids[i],t,c,DATE '2020-01-05','adjustment','long cycle '||i,1,
           ids[CASE WHEN i=n THEN 1 ELSE i+1 END],'cycle probe'
    FROM generate_series(1,n) i ORDER BY i;
    RAISE NOTICE 'B2 inserted cycle rows=% sum=%',
      (SELECT count(*) FROM public.account_ledger WHERE tenant_id=t),
      (SELECT sum(amount) FROM public.account_ledger WHERE tenant_id=t);
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'B2 insert refused SQLSTATE=% message=%',SQLSTATE,SQLERRM; RETURN;
  END;
  BEGIN
    PERFORM * FROM public.receivables_aging_as_of(t,DATE '2020-01-31',clock_timestamp(),ARRAY[30,60,90,120]);
    RAISE NOTICE 'B2 aging unexpectedly accepted';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'B2 aging SQLSTATE=% message=%',SQLSTATE,SQLERRM;
  END;
  BEGIN
    PERFORM public.close_accounting_period(current_setting('codex.p')::uuid);
    RAISE NOTICE 'B2 close unexpectedly accepted';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'B2 close SQLSTATE=% message=%',SQLSTATE,SQLERRM;
  END;
  RAISE NOTICE 'B2 after failed close status=% head=% snapshot count=%',
    (SELECT status FROM public.accounting_periods WHERE id=current_setting('codex.p')::uuid),
    (SELECT closed_through FROM public.accounting_close_heads WHERE tenant_id=t),
    (SELECT count(*) FROM public.accounting_period_snapshots WHERE tenant_id=t);
END $$;

RESET ROLE;
ROLLBACK;
