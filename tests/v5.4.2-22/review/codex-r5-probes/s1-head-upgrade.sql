-- PREDICTED lock-protocol probe, not a full posting/close integration test.
-- Run this SAME file in two interactive owner sessions on ONE fresh clone
-- with frozen r5 strictly applied; TEMP revoked from PUBLIC/app/core.
-- Requires at least one existing tenant copied from tally. If none exists,
-- this probe raises a setup error rather than claiming a deadlock result.
-- Both sessions stop at the prompt after taking the SAME head FOR SHARE.
-- Only once BOTH prompts are visible, press enter in A then in B.
-- Expected: one upgrade catches 40P01 with its full server message; the
-- other succeeds once the victim reaches ROLLBACK. Neither changes data.
-- This is exactly the head-lock upgrade a post-then-close transaction takes.
\set ON_ERROR_STOP on
BEGIN ISOLATION LEVEL READ COMMITTED;
SET LOCAL search_path=public,pg_temp;
SET LOCAL client_min_messages=notice;
SET LOCAL statement_timeout='120s';
DO $$
DECLARE t uuid;
BEGIN
 SELECT tenant_id INTO t FROM accounting_close_heads ORDER BY tenant_id LIMIT 1 FOR SHARE;
 IF t IS NULL THEN RAISE EXCEPTION 'Setup: clone needs an existing tenant/head'; END IF;
 PERFORM set_config('cx5.head',t::text,true);
 RAISE NOTICE 'PID % holds head % FOR SHARE',pg_backend_pid(),t;
END $$;
\prompt 'Wait until BOTH sessions show this prompt, then press enter in each: ' ready
DO $$
BEGIN
 BEGIN
  PERFORM 1 FROM accounting_close_heads WHERE tenant_id=current_setting('cx5.head')::uuid FOR UPDATE;
  RAISE NOTICE 'Head upgrade acquired';
 EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Head upgrade SQLSTATE=% message=%',SQLSTATE,SQLERRM;
  IF SQLSTATE<>'40P01' THEN RAISE; END IF;
 END;
END $$;
ROLLBACK;
