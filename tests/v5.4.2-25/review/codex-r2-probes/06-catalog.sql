-- Codex r2: NOT EXECUTED. Owner, fresh clone with frozen r2 applied.
\set ON_ERROR_STOP on
BEGIN;
DO $$
DECLARE f text;
BEGIN
 FOREACH f IN ARRAY ARRAY['assert_dispute_guard_invariants','assert_cash_guard_invariants','assert_periods_guard_invariants',
 'assert_seal_role_invariants','assert_core_role_invariants','assert_tenant_isolation_invariants','assert_rule_table_invariants',
 'assert_no_hard_delete_invariants','assert_wave1_guard_invariants'] LOOP
  BEGIN
   EXECUTE format('SELECT public.%I()',f);
   RAISE NOTICE '% SQLSTATE=00000 passed',f;
  EXCEPTION WHEN OTHERS THEN
   RAISE NOTICE '% caught SQLSTATE=% message=%',f,SQLSTATE,SQLERRM;
  END;
 END LOOP;
END $$;
SELECT t.table_name,t.rule_role,t.terms_kind,t.area_key,t.law_table,t.close_floor,t.insert_check
 FROM public.rule_tables t WHERE t.table_name IN ('public.dispute_rules'::regclass,'public.dispute_tariffs'::regclass,'public.dispute_platform_defaults'::regclass);
SELECT public.seal_role_privileges('tally_dispute');
SELECT k.conrelid::regclass,k.conname,pg_get_constraintdef(k.oid) FROM pg_catalog.pg_constraint k
 WHERE k.conrelid IN ('public.disputes'::regclass,'public.dispute_amounts'::regclass,'public.dispute_amount_lines'::regclass,
 'public.dispute_determinations'::regclass,'public.dispute_events'::regclass,'public.dispute_tariffs'::regclass) AND k.contype='f'
 ORDER BY 1,2;
ROLLBACK;
