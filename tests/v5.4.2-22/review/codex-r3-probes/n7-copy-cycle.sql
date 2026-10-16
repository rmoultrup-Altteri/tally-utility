-- Codex r3 source-only probe; NOT EXECUTED.
-- Fresh frozen-r3 clone, owner/superuser psql. COPY FROM public RLS table
-- is deliberately run as owner/superuser; tally_app COPY FROM is unsupported by RLS.
-- LAST_ERROR is captured unconditionally and independently checked against the
-- deliberate 22P02 control and the subsequent cycle-specific 23514 message.
\set ON_ERROR_STOP on
BEGIN ISOLATION LEVEL READ COMMITTED;
SET LOCAL search_path = public, pg_temp;
SET LOCAL client_min_messages = notice;
INSERT INTO public.tenants(id,name,slug)
VALUES('c0220002-0000-4000-8000-000000000001','Codex COPY probe','codex-r3-copy-probe');
INSERT INTO public.customers(id,tenant_id,customer_number,customer_type)
VALUES('c0220002-0000-4000-8000-000000000002','c0220002-0000-4000-8000-000000000001','COPY-1','residential');
CREATE TEMP TABLE copy_capture_selftest(n integer);
SAVEPOINT capture_control;
\set ON_ERROR_STOP off
COPY copy_capture_selftest FROM STDIN;
not_an_integer
\.
\set control_state :LAST_ERROR_SQLSTATE
\set control_message :LAST_ERROR_MESSAGE
ROLLBACK TO SAVEPOINT capture_control;
\set ON_ERROR_STOP on
SELECT set_config('codex.control_state', :'control_state', true), set_config('codex.control_message', :'control_message', true);
DO $$ BEGIN
 RAISE NOTICE 'COPY capture control SQLSTATE=% message=%',current_setting('codex.control_state'),current_setting('codex.control_message');
 IF current_setting('codex.control_state') <> '22P02' THEN RAISE EXCEPTION 'COPY capture self-test failed'; END IF;
END $$;
SAVEPOINT copy_attempt;
\set ON_ERROR_STOP off
COPY public.account_ledger(id,tenant_id,customer_id,transaction_date,transaction_type,description,amount,reverses_ledger_entry_id,reversal_reason) FROM STDIN WITH (FORMAT csv);
c0220002-0000-4000-8000-000000000003,c0220002-0000-4000-8000-000000000001,c0220002-0000-4000-8000-000000000002,2020-01-05,adjustment,COPY cycle A,100,c0220002-0000-4000-8000-000000000004,offset
c0220002-0000-4000-8000-000000000004,c0220002-0000-4000-8000-000000000001,c0220002-0000-4000-8000-000000000002,2020-01-06,adjustment,COPY cycle B,-40,c0220002-0000-4000-8000-000000000003,offset
\.
\set copy_state :LAST_ERROR_SQLSTATE
\set copy_message :LAST_ERROR_MESSAGE
ROLLBACK TO SAVEPOINT copy_attempt;
\set ON_ERROR_STOP on
SELECT set_config('codex.copy_state', :'copy_state', true), set_config('codex.copy_message', :'copy_message', true);
DO $$ BEGIN
 RAISE NOTICE 'COPY cycle SQLSTATE=% message=%',current_setting('codex.copy_state'),current_setting('codex.copy_message');
 IF current_setting('codex.copy_state') <> '23514' OR position('returns to itself' in current_setting('codex.copy_message'))=0 THEN
   RAISE EXCEPTION 'COPY cycle did not produce its own expected error (stale self-test error is not success)';
 END IF;
END $$;
ROLLBACK;
