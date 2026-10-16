-- PREDICTED, not executed. Owner/superuser, fresh frozen-r5 clone; TEMP revoked.
-- Bounced recovery and correction of that correction, at all event coordinates.
\set ON_ERROR_STOP on
BEGIN ISOLATION LEVEL READ COMMITTED;
SET LOCAL search_path=public,pg_temp;
SET LOCAL client_min_messages=notice;
DO $$
DECLARE t uuid:=gen_random_uuid(); c uuid:=gen_random_uuid(); w uuid:=gen_random_uuid();
 r uuid:=gen_random_uuid(); b uuid:=gen_random_uuid(); d date; at_time timestamptz;
 n numeric; aged numeric; expected numeric;
BEGIN
 INSERT INTO tenants(id,name,slug) VALUES(t,'Coordinate grid','cx4-'||t);
 INSERT INTO customers(id,tenant_id,customer_number) VALUES(c,t,'GRID');
 INSERT INTO account_ledger(tenant_id,customer_id,transaction_date,transaction_type,description,amount,created_at)
 VALUES(t,c,'2020-01-01','charge','original debt',100,'2020-02-01');
 INSERT INTO account_ledger(id,tenant_id,customer_id,transaction_date,transaction_type,description,amount,created_at)
 VALUES(w,t,c,'2020-01-02','write_off','written off',-100,'2020-02-02');
 INSERT INTO account_ledger(id,tenant_id,customer_id,transaction_date,transaction_type,description,amount,reverses_ledger_entry_id,reversal_reason,created_at)
 VALUES(r,t,c,'2020-01-03','write_off_recovery','paid',100,w,'paid','2020-02-03');
 INSERT INTO account_ledger(id,tenant_id,customer_id,transaction_date,transaction_type,description,amount,reverses_ledger_entry_id,reversal_reason,created_at)
 VALUES(b,t,c,'2020-01-04','adjustment','bounced partly',-60,r,'bounced','2020-02-04');
 INSERT INTO account_ledger(tenant_id,customer_id,transaction_date,transaction_type,description,amount,reverses_ledger_entry_id,reversal_reason,created_at)
 VALUES(t,c,'2020-01-05','adjustment','bounce correction',20,b,'corrected','2020-02-05');
 FOR d IN SELECT generate_series('2020-01-01'::date,'2020-01-06'::date,'1 day')::date LOOP
  FOR at_time IN SELECT generate_series('2020-02-01'::timestamptz,'2020-02-06'::timestamptz,'1 day') LOOP
   SELECT coalesce(sum(amount),0) INTO n FROM account_ledger
    WHERE tenant_id=t AND reverses_ledger_entry_id IS NOT NULL AND transaction_date<=d AND created_at<=at_time;
   IF n<0 OR n>100 THEN RAISE EXCEPTION 'Grid cap violation: %, %, %',d,at_time,n; END IF;
   SELECT coalesce(sum(amount),0) INTO expected FROM account_ledger
    WHERE tenant_id=t AND transaction_date<=d AND created_at<=at_time;
   SELECT coalesce(sum(amount),0) INTO aged FROM receivables_aging_as_of(t,d,at_time,ARRAY[30,60]);
   IF aged IS DISTINCT FROM expected THEN RAISE EXCEPTION 'Aging mismatch at %, %: % versus %',d,at_time,aged,expected; END IF;
  END LOOP;
 END LOOP;
 RAISE NOTICE '36 date/recorded coordinates: cap in [0,100], aging reconciles; correction of correction accepted';
END $$;
ROLLBACK;
