-- PREDICTED; not executed by Codex. Run as owner/superuser on a fresh clone
-- with frozen r4 strictly applied and TEMP revoked from PUBLIC, tally_app, tally_core.
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
-- Exploratory regression probes: ordered multi-row periods, multi-row recovery cap,
-- and a writable CTE whose rows are consumed before closing. Expected: no freeze bypass.
SET LOCAL ROLE tally_app;
DO $$
DECLARE t uuid := current_setting('codex.t')::uuid; c uuid := current_setting('codex.c')::uuid;
        wo uuid := gen_random_uuid(); at_close timestamptz; cap_state text; total numeric;
BEGIN
  INSERT INTO public.accounting_periods(tenant_id,period_start,period_end)
  VALUES(t,DATE '2020-02-01',DATE '2020-02-29'),(t,DATE '2020-03-01',DATE '2020-03-31');
  RAISE NOTICE 'OBSERVED N2 contiguous periods in multi-row statement=%',
    (SELECT count(*) FROM public.accounting_periods WHERE tenant_id=t);
  INSERT INTO public.account_ledger(id,tenant_id,customer_id,transaction_date,transaction_type,description,amount)
  VALUES(wo,t,c,DATE '2020-01-01','write_off','cap fixture',-50);
  BEGIN
    INSERT INTO public.account_ledger(tenant_id,customer_id,transaction_date,transaction_type,description,amount,reverses_ledger_entry_id,reversal_reason)
    VALUES(t,c,DATE '2020-01-02','write_off_recovery','first',30,wo,'paid'),
          (t,c,DATE '2020-01-03','write_off_recovery','second',30,wo,'paid');
    RAISE NOTICE 'OBSERVED N2 unexpected acceptance of 60 recovery against 50';
  EXCEPTION WHEN OTHERS THEN
    cap_state:=SQLSTATE; RAISE NOTICE 'OBSERVED N2 recovery statement refused: % %',SQLSTATE,SQLERRM;
  END;
  RAISE NOTICE 'OBSERVED N2 cap SQLSTATE=% surviving recovery count=%',cap_state,
    (SELECT count(*) FROM public.account_ledger WHERE reverses_ledger_entry_id=wo);
  WITH posted AS (
    INSERT INTO public.account_ledger(tenant_id,customer_id,transaction_date,transaction_type,description,amount)
    VALUES(t,c,DATE '2020-01-05','charge','CTE first',100),
          (t,c,DATE '2020-01-06','charge','CTE second',25)
    RETURNING id
  )
  SELECT public.close_accounting_period(current_setting('codex.p')::uuid)
    INTO at_close FROM (SELECT count(*) AS n FROM posted) consumed WHERE n=2;
  SELECT sum(amount) INTO total FROM public.account_ledger WHERE tenant_id=t;
  RAISE NOTICE 'OBSERVED N2 CTE close at=% snapshot closing=% ledger=%',at_close,
    (SELECT closing_balance FROM public.accounting_period_snapshots WHERE period_id=current_setting('codex.p')::uuid),total;
  BEGIN
    INSERT INTO public.account_ledger(tenant_id,customer_id,transaction_date,transaction_type,description,amount)
    VALUES(t,c,DATE '2020-01-07','adjustment','after own close',1);
    RAISE NOTICE 'OBSERVED N2 unexpected acceptance after own close';
  EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'OBSERVED N2 after-close write refused: % %',SQLSTATE,SQLERRM;
  END;
END $$;
RESET ROLE;
ROLLBACK;
