-- Opus r7: a due row and a refund event in ONE statement (a writable CTE). Runs after the r17 fixtures, before V1.
CREATE FUNCTION pg_temp.try2(p_label text, p_sql text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_state text; v_msg text;
BEGIN
  BEGIN
    PERFORM set_config('app.user_id', '00000000-0000-4000-8000-0000000015b2', true);
    SET CONSTRAINTS ALL DEFERRED;
    SET LOCAL ROLE tally_app;
    EXECUTE p_sql;
    SET CONSTRAINTS ALL IMMEDIATE;
    RESET ROLE;
    RAISE NOTICE 'PROBE % => ACCEPTED', p_label;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    RESET ROLE;
    RAISE NOTICE 'PROBE % => REFUSED % %', p_label, v_state, v_msg;
  END;
END $$;
CREATE FUNCTION pg_temp.cte_sql(p_dep uuid, p_ev text, p_amt numeric, p_on date, p_due uuid) RETURNS text LANGUAGE sql AS $$
  SELECT format($q$WITH ev AS (INSERT INTO public.deposit_events (tenant_id, deposit_id, event_type, amount, effective_on)
                     SELECT d.tenant_id, d.id, %L, %s, %L::date FROM public.deposits d WHERE d.id = %L RETURNING id)
     INSERT INTO public.deposit_return_due (id, tenant_id, deposit_id, rule_id, due_on, inputs, inputs_fingerprint, calculated_by)
     SELECT %L, d.tenant_id, d.id, d.rule_id, DATE '2026-04-01', '{"bills": 12}', 'fp-cte', 'core-battery-1' FROM public.deposits d WHERE d.id = %L;
     INSERT INTO public.deposit_return_due_evidence (tenant_id, due_id, reason_code, return_component, invoice_id, classification, rests_on_deposit)
     SELECT r.tenant_id, r.id, 'clean_bill_history', 'r1', %L, 'clean', false FROM public.deposit_return_due r WHERE r.id = %L;
     INSERT INTO public.deposit_return_due_evidence (tenant_id, due_id, reason_code, return_component, invoice_id, classification, rests_on_deposit)
     SELECT r.tenant_id, r.id, 'clean_bill_history', 'r1', %L, 'clean', false FROM public.deposit_return_due r WHERE r.id = %L$q$,
     p_ev, p_amt, p_on, p_dep, p_due, p_dep, '00000000-0000-4000-8000-0000000015e1', p_due, '00000000-0000-4000-8000-0000000015e2', p_due)
$$;
-- control: the same due row alone, after a refund notice written separately, is refused by the status check
SELECT pg_temp.try2('C0 control: due row alone on rtar (held) — expect ACCEPTED then rolled back by savepoint',
  'SAVEPOINT c0; ' || replace(pg_temp.cte_sql(pg_temp.did('rtar'), 'applied_to_balance', 1, '2026-02-01', '00000000-0000-4000-8000-00000000f001'), 'WITH ev AS', 'WITH ev0 AS (SELECT 1), ev AS') || '; ROLLBACK TO SAVEPOINT c0');
SELECT pg_temp.try2('DUE1 one statement: refund notice of 60 (1 Mar) in a CTE + a due row for rtar',
  pg_temp.cte_sql(pg_temp.did('rtar'), 'refund_initiated', 60, '2026-03-01', '00000000-0000-4000-8000-00000000f002'));
DO $$ DECLARE r record; BEGIN
  FOR r IN SELECT d.status, (SELECT count(*) FROM public.deposit_return_due x WHERE x.deposit_id = d.id) AS dues,
                  (SELECT count(*) FROM public.deposits_return_owed o WHERE o.deposit_id = d.id) AS owed
             FROM public.deposits d WHERE d.id = pg_temp.did('rtar') LOOP
    RAISE NOTICE 'STATE rtar status=% due_rows=% owed_rows=%', r.status, r.dues, r.owed;
  END LOOP; END $$;
SELECT pg_temp.try2('DUE2 control: a second statement, a due row after the notice (expect REFUSED by status)',
  'INSERT INTO public.deposit_return_due (id, tenant_id, deposit_id, rule_id, due_on, inputs, inputs_fingerprint, calculated_by) SELECT ''00000000-0000-4000-8000-00000000f003'', d.tenant_id, d.id, d.rule_id, DATE ''2026-04-01'', ''{}'', ''fp'', ''x'' FROM public.deposits d WHERE d.id = ''' || pg_temp.did('rr') || '''');
