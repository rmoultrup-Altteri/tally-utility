-- PREDICTED, not executed. Owner/superuser, fresh clone with frozen r5 applied.
-- TEMP revoked from PUBLIC, tally_app, tally_core. All changes roll back.
\set ON_ERROR_STOP on
BEGIN ISOLATION LEVEL READ COMMITTED;
SET LOCAL search_path=public,pg_temp;
SET LOCAL client_min_messages=notice;
DO $$
DECLARE t uuid:=gen_random_uuid(); c uuid:=gen_random_uuid(); u uuid:=gen_random_uuid();
 w uuid:=gen_random_uuid(); r uuid:=gen_random_uuid(); outside uuid:=gen_random_uuid();
 at_time timestamptz; kind text; parent uuid; value numeric; refused boolean;
BEGIN
 INSERT INTO tenants(id,name,slug) VALUES(t,'R5 time probe','cx5-'||t);
 INSERT INTO users(id,tenant_id,display_name,email,role) VALUES(u,t,'Operator',u||'@cx5.test','operator');
 INSERT INTO customers(id,tenant_id,customer_number) VALUES(c,t,'TIME');
 INSERT INTO account_ledger(id,tenant_id,customer_id,transaction_date,transaction_type,description,amount,created_at)
 VALUES(w,t,c,'2020-01-01','write_off','past history',-100,'2020-02-01');
 INSERT INTO account_ledger(id,tenant_id,customer_id,transaction_date,transaction_type,description,amount,reverses_ledger_entry_id,reversal_reason,created_at)
 VALUES(r,t,c,'2020-01-02','write_off_recovery','past recovery',20,w,'paid','2020-02-02');
 FOREACH at_time IN ARRAY ARRAY['infinity'::timestamptz,'-infinity'::timestamptz,clock_timestamp()+interval '100 years'] LOOP
  FOREACH kind IN ARRAY ARRAY['write_off','write_off_recovery','adjustment'] LOOP
   parent:=CASE kind WHEN 'write_off_recovery' THEN w WHEN 'adjustment' THEN r ELSE NULL END;
   value:=CASE kind WHEN 'write_off' THEN -100 WHEN 'write_off_recovery' THEN 1 ELSE -1 END;
   refused:=false;
   BEGIN
    INSERT INTO account_ledger(tenant_id,customer_id,transaction_date,transaction_type,description,amount,reverses_ledger_entry_id,reversal_reason,created_at)
    VALUES(t,c,'2020-01-03',kind,'invalid time',value,parent,CASE WHEN parent IS NOT NULL THEN 'time probe' END,at_time);
   EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE '% at % SQLSTATE=% message=%',kind,at_time,SQLSTATE,SQLERRM;
    IF SQLSTATE<>'23514' OR position('recorded in the future' in SQLERRM)=0 THEN RAISE; END IF;
    refused:=true;
   END;
   IF NOT refused THEN RAISE EXCEPTION 'Invalid time admitted: % %',kind,at_time; END IF;
  END LOOP;
 END LOOP;
 IF (SELECT created_at FROM account_ledger WHERE id=w) IS DISTINCT FROM '2020-02-01'::timestamptz
 OR (SELECT created_at FROM account_ledger WHERE id=r) IS DISTINCT FROM '2020-02-02'::timestamptz THEN
  RAISE EXCEPTION 'Past history timestamp was not preserved';
 END IF;
 -- The new rule must not reject future coordinates outside write-off components.
 INSERT INTO account_ledger(id,tenant_id,customer_id,transaction_date,transaction_type,description,amount,created_at)
 VALUES(outside,t,c,'2020-01-01','charge','outside tree',100,'infinity');
 INSERT INTO account_ledger(tenant_id,customer_id,transaction_date,transaction_type,description,amount,reverses_ledger_entry_id,reversal_reason,created_at)
 VALUES(t,c,'2020-01-02','adjustment','outside descendant',-1,outside,'outside','infinity');
 RAISE NOTICE 'Past history retained; future root/descendant outside write-off tree admitted';
 PERFORM set_config('cx5.tenant',t::text,true);
 PERFORM set_config('cx5.customer',c::text,true);
 PERFORM set_config('cx5.writeoff',w::text,true);
 PERFORM set_config('app.user_id',u::text,true);
END $$;
SET LOCAL ROLE tally_app;
DO $$
DECLARE entry_id uuid:=gen_random_uuid(); actual timestamptz;
BEGIN
 INSERT INTO account_ledger(id,tenant_id,customer_id,transaction_date,transaction_type,description,amount,reverses_ledger_entry_id,reversal_reason,created_at)
 VALUES(entry_id,current_setting('cx5.tenant')::uuid,current_setting('cx5.customer')::uuid,
 '2020-01-03','write_off_recovery','honest writer after rejected poison',1,current_setting('cx5.writeoff')::uuid,'paid','infinity');
 SELECT created_at INTO actual FROM account_ledger WHERE id=entry_id;
 IF actual IS DISTINCT FROM now() THEN RAISE EXCEPTION 'Ordinary timestamp not stamped: %',actual; END IF;
 RAISE NOTICE 'Ordinary recovery admitted, supplied infinity stamped to transaction time %',actual;
END $$;
RESET ROLE;
ROLLBACK;
