-- PREDICTED, not executed. Owner/superuser on fresh frozen-r5 clone; TEMP revoked.
-- Admission checks only, not a stale-snapshot concurrency reproduction.
\set ON_ERROR_STOP on
BEGIN ISOLATION LEVEL SERIALIZABLE;
SET LOCAL search_path=public,pg_temp;
SET LOCAL client_min_messages=notice;
DO $$
DECLARE t uuid:=gen_random_uuid(); c uuid:=gen_random_uuid(); w uuid:=gen_random_uuid(); q text; refused boolean;
BEGIN
 INSERT INTO tenants(id,name,slug) VALUES(t,'Serializable admission','cx4-'||t);
 INSERT INTO customers(id,tenant_id,customer_number) VALUES(c,t,'SERIAL');
 INSERT INTO account_ledger(id,tenant_id,customer_id,transaction_date,transaction_type,description,amount)
 VALUES(w,t,c,'2020-01-01','write_off','written off',-100);
 FOREACH q IN ARRAY ARRAY[
  format('INSERT INTO accounting_periods(tenant_id,period_start,period_end) VALUES(%L,''2020-01-01'',''2020-01-31'')',t),
  format('SELECT close_accounting_period(%L)',gen_random_uuid()),
  format('INSERT INTO account_ledger(tenant_id,customer_id,transaction_date,transaction_type,description,amount,reverses_ledger_entry_id,reversal_reason) VALUES(%L,%L,''2020-01-02'',''write_off_recovery'',''paid'',1,%L,''paid'')',t,c,w)
 ] LOOP
  refused:=false;
  BEGIN
   EXECUTE q;
  EXCEPTION WHEN OTHERS THEN
   RAISE NOTICE 'SERIALIZABLE admission SQLSTATE=% message=%',SQLSTATE,SQLERRM;
   IF SQLSTATE<>'25000' THEN RAISE; END IF;
   refused:=true;
  END;
  IF NOT refused THEN RAISE EXCEPTION 'Unexpected SERIALIZABLE admission: %',q; END IF;
 END LOOP;
END $$;
ROLLBACK;
