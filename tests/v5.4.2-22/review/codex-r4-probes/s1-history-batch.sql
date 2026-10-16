-- PREDICTED, not executed. Owner/superuser, fresh frozen-r4 clone; TEMP revoked.
-- A valid historical batch is refused; identical rows in chronological statements pass.
\set ON_ERROR_STOP on
BEGIN ISOLATION LEVEL READ COMMITTED;
SET LOCAL search_path=public,pg_temp;
SET LOCAL client_min_messages=notice;
DO $$
DECLARE t uuid:=gen_random_uuid(); c uuid:=gen_random_uuid(); w uuid:=gen_random_uuid();
 r uuid:=gen_random_uuid(); a uuid:=gen_random_uuid(); refused boolean:=false;
BEGIN
 INSERT INTO tenants(id,name,slug) VALUES(t,'History batch','cx4-'||t);
 INSERT INTO customers(id,tenant_id,customer_number) VALUES(c,t,'BATCH');
 INSERT INTO account_ledger(id,tenant_id,customer_id,transaction_date,transaction_type,description,amount,created_at)
 VALUES(w,t,c,'2020-01-01','write_off','written off',-100,'2020-02-01');
 BEGIN
  INSERT INTO account_ledger(id,tenant_id,customer_id,transaction_date,transaction_type,description,amount,reverses_ledger_entry_id,reversal_reason,created_at)
  VALUES(r,t,c,'2020-01-02','write_off_recovery','paid',50,w,'paid','2020-02-02'),
        (a,t,c,'2020-01-03','adjustment','bounced partly',-20,r,'bounced','2020-02-03');
 EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'valid multi-instant batch SQLSTATE=% message=%',SQLSTATE,SQLERRM;
  IF SQLSTATE<>'40001' OR position('retry it' in SQLERRM)=0 THEN RAISE; END IF;
  refused:=true;
 END;
 IF NOT refused THEN RAISE EXCEPTION 'Expected current r4 to refuse this batch'; END IF;
 INSERT INTO account_ledger(id,tenant_id,customer_id,transaction_date,transaction_type,description,amount,reverses_ledger_entry_id,reversal_reason,created_at)
 VALUES(r,t,c,'2020-01-02','write_off_recovery','paid',50,w,'paid','2020-02-02');
 INSERT INTO account_ledger(id,tenant_id,customer_id,transaction_date,transaction_type,description,amount,reverses_ledger_entry_id,reversal_reason,created_at)
 VALUES(a,t,c,'2020-01-03','adjustment','bounced partly',-20,r,'bounced','2020-02-03');
 RAISE NOTICE 'Same historical rows admitted as two statements: all date/recorded prefixes net 0, 50 or 30';
END $$;
ROLLBACK;
