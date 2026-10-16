-- PREDICTED, not executed. Owner/superuser, fresh clone, frozen r4 strictly applied.
-- TEMP revoked from PUBLIC, tally_app and tally_core. No role DDL or disabled guards.
-- The repeated attempts below are NOT separate transactions. Infinity > every
-- finite transaction start is the reason a fresh transaction cannot resolve this.
\set ON_ERROR_STOP on
BEGIN ISOLATION LEVEL READ COMMITTED;
SET LOCAL search_path=public,pg_temp;
SET LOCAL client_min_messages=notice;
DO $$
DECLARE t uuid:=gen_random_uuid(); c uuid:=gen_random_uuid(); u uuid:=gen_random_uuid();
 w uuid:=gen_random_uuid(); r uuid:=gen_random_uuid(); at_time timestamptz; refused boolean;
BEGIN
 INSERT INTO tenants(id,name,slug) VALUES(t,'Future recorded probe','cx4-'||t);
 INSERT INTO users(id,tenant_id,display_name,email,role) VALUES(u,t,'Operator',u||'@cx4.test','operator');
 INSERT INTO customers(id,tenant_id,customer_number) VALUES(c,t,'FUTURE');
 INSERT INTO account_ledger(id,tenant_id,customer_id,transaction_date,transaction_type,description,amount)
 VALUES(w,t,c,'2020-01-01','write_off','written off',-100);
 INSERT INTO account_ledger(id,tenant_id,customer_id,transaction_date,transaction_type,description,amount,reverses_ledger_entry_id,reversal_reason,created_at)
 VALUES(r,t,c,'2020-01-02','write_off_recovery','owner history timestamp',20,w,'paid','infinity');
 IF (SELECT created_at FROM account_ledger WHERE id=r) IS DISTINCT FROM 'infinity'::timestamptz THEN
  RAISE EXCEPTION 'Owner infinity was not preserved';
 END IF;
 RAISE NOTICE 'Owner recovery with created_at=infinity admitted, net=20 of 100';
 -- Even progressively later finite owner timestamps cannot recover the remaining 80.
 FOREACH at_time IN ARRAY ARRAY[clock_timestamp(), '2200-01-01'::timestamptz, '9000-01-01'::timestamptz] LOOP
  refused:=false;
  BEGIN
   INSERT INTO account_ledger(tenant_id,customer_id,transaction_date,transaction_type,description,amount,reverses_ledger_entry_id,reversal_reason,created_at)
   VALUES(t,c,'2020-01-03','write_off_recovery','remaining capacity',1,w,'paid',at_time);
  EXCEPTION WHEN OTHERS THEN
   RAISE NOTICE 'finite timestamp % SQLSTATE=% message=%',at_time,SQLSTATE,SQLERRM;
   IF SQLSTATE<>'40001' OR position('retry it' in SQLERRM)=0 THEN RAISE; END IF;
   refused:=true;
  END;
  IF NOT refused THEN RAISE EXCEPTION 'Expected persistent 40001 at %',at_time; END IF;
 END LOOP;
 PERFORM set_config('cx4.tenant',t::text,true);
 PERFORM set_config('cx4.customer',c::text,true);
 PERFORM set_config('cx4.writeoff',w::text,true);
 PERFORM set_config('app.user_id',u::text,true);
END $$;
SET LOCAL ROLE tally_app;
DO $$
DECLARE refused boolean:=false;
BEGIN
 BEGIN
  INSERT INTO account_ledger(tenant_id,customer_id,transaction_date,transaction_type,description,amount,reverses_ledger_entry_id,reversal_reason,created_at)
  VALUES(current_setting('cx4.tenant')::uuid,current_setting('cx4.customer')::uuid,
   '2020-01-03','write_off_recovery','ordinary writer cannot repair timestamp',1,
   current_setting('cx4.writeoff')::uuid,'paid','infinity');
 EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'ordinary writer, even supplying infinity: SQLSTATE=% message=%',SQLSTATE,SQLERRM;
  IF SQLSTATE<>'40001' OR position('retry it' in SQLERRM)=0 THEN RAISE; END IF;
  refused:=true;
 END;
 IF NOT refused THEN RAISE EXCEPTION 'Expected ordinary writer 40001'; END IF;
END $$;
RESET ROLE;
ROLLBACK;
