-- PREDICTED; not executed by Codex. Run as owner/superuser on a fresh clone
-- with frozen r4 strictly applied and TEMP revoked from PUBLIC, tally_app, tally_core.
-- Codex r4: PREDICTED, not executed. Owner/superuser, fresh clone with frozen r4 applied.
-- No cluster-role changes. All SQL changes roll back.
\set ON_ERROR_STOP on
BEGIN ISOLATION LEVEL READ COMMITTED;
SET LOCAL search_path = public, pg_temp;
SET LOCAL client_min_messages = notice;
DO $$
DECLARE t uuid:=gen_random_uuid(); c uuid:=gen_random_uuid(); c2 uuid:=gen_random_uuid();
 w uuid:=gen_random_uuid(); r uuid:=gen_random_uuid(); w2 uuid:=gen_random_uuid(); r2 uuid:=gen_random_uuid();
 bridge uuid:=gen_random_uuid(); n numeric; failed boolean;
BEGIN
 INSERT INTO tenants(id,name,slug) VALUES(t,'Nested probe','cx3-'||t);
 INSERT INTO customers(id,tenant_id,customer_number,customer_type)
 VALUES(c,t,'A','residential'),(c2,t,'B','residential');
 -- Reverse listing order; nested write-off under a recovery. Outer net=50, inner net=0.
 INSERT INTO account_ledger(id,tenant_id,customer_id,transaction_date,transaction_type,description,amount,reverses_ledger_entry_id,reversal_reason)
 VALUES(w2,t,c,'2020-01-01','write_off','inner',-30,r,'inner'),
       (r,t,c,'2020-01-01','write_off_recovery','outer recovery',80,w,'paid'),
       (w,t,c,'2020-01-01','write_off','outer',-100,NULL,NULL);
 INSERT INTO account_ledger(id,tenant_id,customer_id,transaction_date,transaction_type,description,amount,reverses_ledger_entry_id,reversal_reason)
 VALUES(r2,t,c,'2020-01-01','write_off_recovery','inner recovery',30,w2,'paid');
 RAISE NOTICE 'nested valid tree admitted; expected outer net=80 inner net=30';
 failed:=false;
 BEGIN
  INSERT INTO account_ledger(tenant_id,customer_id,transaction_date,transaction_type,description,amount,reverses_ledger_entry_id,reversal_reason)
  VALUES(t,c,'2020-01-01','adjustment','inner overflow',1,r2,'x');
 EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'inner overflow SQLSTATE=% message=%',SQLSTATE,SQLERRM;
  IF SQLSTATE <> '23514' OR position('R-02 cap' in SQLERRM)=0 THEN RAISE; END IF;
  failed:=true;
 END;
 IF NOT failed THEN RAISE EXCEPTION 'inner overflow accepted'; END IF;
 -- Inner remains valid, but outer would be 101.
 failed:=false;
 BEGIN
  INSERT INTO account_ledger(tenant_id,customer_id,transaction_date,transaction_type,description,amount,reverses_ledger_entry_id,reversal_reason)
  VALUES(t,c,'2020-01-01','adjustment','outer overflow',21,r,'x');
 EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'outer overflow SQLSTATE=% message=%',SQLSTATE,SQLERRM;
  IF SQLSTATE <> '23514' OR position('R-02 cap' in SQLERRM)=0 THEN RAISE; END IF;
  failed:=true;
 END;
 IF NOT failed THEN RAISE EXCEPTION 'outer overflow accepted'; END IF;
 -- Leave customer A and return to A: neither row is in the original A tree.
 INSERT INTO account_ledger(id,tenant_id,customer_id,transaction_date,transaction_type,description,amount,reverses_ledger_entry_id,reversal_reason)
 VALUES(bridge,t,c2,'2020-01-01','adjustment','other customer',500,r,'x');
 INSERT INTO account_ledger(tenant_id,customer_id,transaction_date,transaction_type,description,amount,reverses_ledger_entry_id,reversal_reason)
 VALUES(t,c,'2020-01-01','adjustment','return across customer boundary',500,bridge,'x'),
       (t,c,'2020-01-01','adjustment','outer still 81',1,r,'x');
 SELECT sum(amount) INTO n FROM receivables_aging_as_of(t,'2020-01-31',clock_timestamp(),ARRAY[30,60]);
 IF n <> 981 THEN RAISE EXCEPTION 'aging expected 981, got %',n; END IF;
 RAISE NOTICE 'cross-customer boundary respected; total aging=%',n;
END $$;
ROLLBACK;
