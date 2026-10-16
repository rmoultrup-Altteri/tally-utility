-- PREDICTED, not executed. Owner/superuser, fresh frozen-r4 clone; TEMP revoked.
-- Server-side COPY FROM PROGRAM supplies fixed test CSV via printf. Capture is
-- inside PL/pgSQL, NOT psql LAST_ERROR_SQLSTATE. Requires owner's PROGRAM privilege.
-- A positive COPY and a deliberate 22P02 control must pass before the cycle leg.
\set ON_ERROR_STOP on
BEGIN ISOLATION LEVEL READ COMMITTED;
SET LOCAL search_path=public,pg_temp;
SET LOCAL client_min_messages=notice;
CREATE TEMP TABLE copy_control(n integer);
DO $$
DECLARE caught boolean:=false;
BEGIN
 EXECUTE $copy$COPY pg_temp.copy_control FROM PROGRAM 'printf "7\n"'$copy$;
 IF (SELECT count(*) FROM pg_temp.copy_control WHERE n=7) <> 1 THEN
  RAISE EXCEPTION 'COPY transport control failed';
 END IF;
 BEGIN
  EXECUTE $copy$COPY pg_temp.copy_control FROM PROGRAM 'printf "not-an-integer\n"'$copy$;
 EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'COPY capture control SQLSTATE=% message=%',SQLSTATE,SQLERRM;
  IF SQLSTATE<>'22P02' OR position('not-an-integer' in SQLERRM)=0 THEN RAISE; END IF;
  caught:=true;
 END;
 IF NOT caught THEN RAISE EXCEPTION 'COPY error-capture control did not catch 22P02'; END IF;
 RAISE NOTICE 'COPY transport and error capture controls passed';
END $$;
INSERT INTO tenants(id,name,slug) VALUES('c0440000-0000-4000-8000-000000000001','COPY probe','cx4-copy');
INSERT INTO customers(id,tenant_id,customer_number) VALUES('c0440000-0000-4000-8000-000000000002','c0440000-0000-4000-8000-000000000001','COPY');
DO $$
DECLARE caught boolean:=false;
BEGIN
 BEGIN
  EXECUTE $copy$COPY public.account_ledger(id,tenant_id,customer_id,transaction_date,transaction_type,description,amount,reverses_ledger_entry_id,reversal_reason)
   FROM PROGRAM 'printf "c0440000-0000-4000-8000-000000000003,c0440000-0000-4000-8000-000000000001,c0440000-0000-4000-8000-000000000002,2020-01-01,adjustment,cycle,1,c0440000-0000-4000-8000-000000000004,cycle\nc0440000-0000-4000-8000-000000000004,c0440000-0000-4000-8000-000000000001,c0440000-0000-4000-8000-000000000002,2020-01-01,adjustment,cycle,-1,c0440000-0000-4000-8000-000000000003,cycle\n"' WITH (FORMAT csv)$copy$;
 EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'COPY cycle SQLSTATE=% message=%',SQLSTATE,SQLERRM;
  IF SQLSTATE<>'23514' OR position('returns to itself' in SQLERRM)=0 THEN RAISE; END IF;
  caught:=true;
 END;
 IF NOT caught THEN RAISE EXCEPTION 'COPY cycle admitted'; END IF;
 IF EXISTS(SELECT 1 FROM account_ledger WHERE tenant_id='c0440000-0000-4000-8000-000000000001') THEN
  RAISE EXCEPTION 'COPY left partial ledger rows';
 END IF;
END $$;
ROLLBACK;
