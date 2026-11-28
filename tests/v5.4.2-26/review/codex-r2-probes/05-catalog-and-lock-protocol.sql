-- Codex r2: NOT EXECUTED. Owner session, fresh clone with frozen r2 strictly applied.
-- Revoke TEMP from PUBLIC/tally_app/tally_core when preparing the clone.
-- Fixtures are frozen-battery fixtures. No role creation or alteration.
\set ON_ERROR_STOP on
\set VERBOSITY verbose

BEGIN;
-- This is catalog evidence, NOT a concurrent reproduction.
-- Author's additional race schedules (use own harness/clone):
-- (a) A writes a broad blocked decision, holds; B cites the existing eligible
-- meter decision for an act. B must wait, then get A10 after A commits.
-- Reverse: A's act holds lock; B writes broad block; B must wait then succeed.
-- (b) B begins before A; A writes first event and holds bill lock; B inserts
-- second event. After A commits B must chain from A and get a larger record_seq.
-- (c) Old-snapshot cancellation at SERIALIZABLE must get 25000/F4f, as RR does.
-- No concurrent claim is independently measured by this file.
SELECT p.oid::regprocedure, pg_get_functiondef(p.oid)
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND p.proname IN
 ('collections_subject_lock','collections_act_check','enforce_dunning_event','enforce_disconnect_order','enforce_field_visit','recompute_do_not_disconnect');
SELECT r.rolname,
 has_table_privilege(r.rolname,'public.invoice_line_items','INSERT') AS insert_lines,
 has_table_privilege(r.rolname,'public.invoice_line_items','UPDATE') AS update_lines,
 has_table_privilege(r.rolname,'public.adhoc_charges','SELECT') AS read_charges,
 has_table_privilege(r.rolname,'public.invoices','SELECT') AS read_bills
FROM pg_roles r WHERE r.rolname IN ('tally','tally_app','tally_core','tally_seal','tally_close','tally_void','tally_dispute') ORDER BY 1;
SELECT n.nspname,p.proname,pg_get_userbyid(p.proowner) AS owner,p.prosecdef
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND p.prosrc ~* '(insert[[:space:]]+into|update)[[:space:]]+(public[.])?invoice_line_items';
DO $$ DECLARE f record; BEGIN
 FOR f IN SELECT p.oid::regprocedure AS signature FROM pg_proc p
 WHERE p.pronamespace='public'::regnamespace AND p.proname LIKE 'assert_%invariants' AND p.pronargs=0
 LOOP
  BEGIN
   EXECUTE format('SELECT %s',f.signature);
   RAISE NOTICE '%: SQLSTATE=00000 invariants accepted',f.signature;
  EXCEPTION WHEN OTHERS THEN
   RAISE NOTICE '%: SQLSTATE=% message=%',f.signature,SQLSTATE,SQLERRM;
  END;
 END LOOP;
END $$;
-- R1's local/UTC distinction, fixed coordinates, no clock dependency.
SELECT t, (t AT TIME ZONE 'UTC')::date AS utc_day,
 (t AT TIME ZONE 'America/Chicago')::date AS utility_day
FROM (VALUES(TIMESTAMPTZ '2026-11-26 20:00:00-06'),
            (TIMESTAMPTZ '2026-11-27 10:00:00-06')) v(t);
ROLLBACK;
