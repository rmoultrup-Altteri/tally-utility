-- PREDICTED audit, no assertion about the contents of the author's database.
-- Owner/superuser, fresh clone with frozen r5 strictly applied and TEMP revoked.
-- INSERT triggers do not retroactively validate rows copied from the -21 base.
-- Inspect this BEFORE adding other probe fixtures. No data is changed.
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL search_path=public,pg_temp;
SET LOCAL client_min_messages=notice;
DO $$
DECLARE row_info record; n integer:=0; at_time timestamptz:=clock_timestamp();
BEGIN
 FOR row_info IN
  WITH RECURSIVE tree(id,tenant_id,customer_id) AS (
   SELECT id,tenant_id,customer_id FROM account_ledger WHERE transaction_type='write_off'
   UNION
   SELECT c.id,c.tenant_id,c.customer_id FROM tree p JOIN account_ledger c
    ON c.reverses_ledger_entry_id=p.id AND c.tenant_id=p.tenant_id AND c.customer_id=p.customer_id
  )
  SELECT l.id,l.created_at FROM tree t JOIN account_ledger l ON l.id=t.id
   WHERE NOT isfinite(l.created_at) OR l.created_at>at_time
 LOOP
  n:=n+1;
  RAISE NOTICE 'Existing invalid write-off-component coordinate: id=% created_at=%',row_info.id,row_info.created_at;
 END LOOP;
 RAISE NOTICE 'Existing invalid time count=% (expected zero for deployment)',n;
 IF n<>0 THEN RAISE EXCEPTION 'Deployment preflight: % existing invalid time coordinates need disposition',n; END IF;
END $$;
ROLLBACK;
