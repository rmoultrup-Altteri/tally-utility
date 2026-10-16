-- PREDICTED; not executed by Codex. Run as owner/superuser on a fresh clone
-- with frozen r5 strictly applied and TEMP revoked from PUBLIC, tally_app, tally_core.
-- PREDICTED only. Owner on a fresh clone with frozen r5 applied.
\set ON_ERROR_STOP on
BEGIN ISOLATION LEVEL READ COMMITTED;
SET LOCAL search_path=public,pg_temp;
SET LOCAL client_min_messages=notice;
DO $$
DECLARE t uuid:=gen_random_uuid(); c uuid:=gen_random_uuid(); refused boolean;
BEGIN
 INSERT INTO tenants(id,name,slug) VALUES(t,'Bound','cx3-'||t);
 INSERT INTO customers(id,tenant_id,customer_number,customer_type) VALUES(c,t,'BOUND','residential');
 INSERT INTO account_ledger(id,tenant_id,customer_id,transaction_date,transaction_type,description,amount,reverses_ledger_entry_id,reversal_reason)
 SELECT ('c0330000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,t,c,'2020-01-01','adjustment','chain',1,
 CASE WHEN i=1 THEN NULL ELSE ('c0330000-0000-4000-8000-'||lpad((i-1)::text,12,'0'))::uuid END,
 CASE WHEN i=1 THEN NULL ELSE 'chain' END FROM generate_series(1,1000) i;
 RAISE NOTICE '1000 entries including root admitted';
 refused:=false;
 BEGIN
 INSERT INTO account_ledger(tenant_id,customer_id,transaction_date,transaction_type,description,amount,reverses_ledger_entry_id,reversal_reason)
 VALUES(t,c,'2020-01-01','adjustment','1001st',1,'c0330000-0000-4000-8000-000000001000','chain');
 EXCEPTION WHEN OTHERS THEN
 RAISE NOTICE 'bound SQLSTATE=% message=%',SQLSTATE,SQLERRM;
 IF SQLSTATE<>'23514' OR position('does not reach an original' in SQLERRM)=0 THEN RAISE; END IF;
 refused:=true;
 END;
 IF NOT refused THEN RAISE EXCEPTION '1001st entry accepted'; END IF;
END $$;
DO $$
DECLARE c text;
BEGIN
 FOREACH c IN ARRAY ARRAY['tenant_configuration_history_key_known_check','account_ledger_reversal_not_self_check','account_ledger_reverses_ledger_entry_fkey'] LOOP
 BEGIN
 EXECUTE format('ALTER TABLE public.%I DROP CONSTRAINT %I', CASE WHEN c LIKE 'tenant_%' THEN 'tenant_configuration_history' ELSE 'account_ledger' END,c);
 PERFORM public.assert_periods_guard_invariants();
 RAISE EXCEPTION 'invariant accepted missing %',c;
 EXCEPTION WHEN OTHERS THEN
 RAISE NOTICE 'constraint % SQLSTATE=% message=%',c,SQLSTATE,SQLERRM;
 IF SQLSTATE<>'0LP01' THEN RAISE; END IF;
 END;
 END LOOP;
 BEGIN
 GRANT UPDATE(closed_by) ON public.accounting_periods TO tally_app;
 PERFORM public.assert_seal_role_invariants();
 RAISE EXCEPTION 'seal accepted closed_by grant';
 EXCEPTION WHEN OTHERS THEN
 RAISE NOTICE 'closed_by SQLSTATE=% message=%',SQLSTATE,SQLERRM;
 IF SQLSTATE<>'0LP01' THEN RAISE; END IF;
 END;
END $$;
ROLLBACK;
