-- Fable r7 probe G1: a refund notice and a due row in ONE statement (data-modifying CTE) — the due-row trigger reads d.status
CREATE FUNCTION pg_temp.try(p_label text, p_sql text, p_user text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_state text; v_msg text;
BEGIN
  BEGIN
    PERFORM set_config('app.user_id', p_user, true);
    SET LOCAL ROLE tally_app;
    EXECUTE p_sql;
    RESET ROLE;
    RAISE NOTICE 'PROBE % -> ACCEPTED', p_label;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    RAISE NOTICE 'PROBE % -> REFUSED % %', p_label, v_state, left(v_msg, 140);
  END;
END $$;
SAVEPOINT g1;
SELECT pg_temp.try('G1a control: refund notice on rtar, then a due row in a second statement',
  pg_temp.ev_sql(pg_temp.did('rtar'), 'refund_initiated', 60, DATE '2026-11-02'), :'u2');
SELECT pg_temp.try('G1a control (2nd statement)',
  format($q$INSERT INTO public.deposit_return_due (tenant_id, deposit_id, rule_id, due_on, inputs, inputs_fingerprint, calculated_by)
           SELECT d.tenant_id, d.id, d.rule_id, DATE '2026-11-02', '{"bills": 12}', 'fp-ctl', 'core-battery-1' FROM public.deposits d WHERE d.id = %L$q$, pg_temp.did('rtar')), :'u2');
ROLLBACK TO SAVEPOINT g1;
SELECT count(*) AS due_rows_before_g1b FROM public.deposit_return_due WHERE deposit_id = pg_temp.did('rtar');
SAVEPOINT g2;
SET CONSTRAINTS ALL DEFERRED;
SELECT pg_temp.try('G1b: the same two writes in ONE statement (WITH … INSERT) — the due row is written while the notice is already in the ledger',
  format($q$WITH e AS (INSERT INTO public.deposit_events (tenant_id, deposit_id, event_type, amount, effective_on)
                       SELECT d.tenant_id, d.id, 'refund_initiated', 60, DATE '2026-11-02' FROM public.deposits d WHERE d.id = %L RETURNING deposit_id)
           INSERT INTO public.deposit_return_due (tenant_id, deposit_id, rule_id, due_on, inputs, inputs_fingerprint, calculated_by)
           SELECT d.tenant_id, d.id, d.rule_id, DATE '2026-11-02', '{"bills": 12}', 'fp-cte', 'core-battery-1' FROM public.deposits d JOIN e ON e.deposit_id = d.id$q$, pg_temp.did('rtar')), :'u2');
SELECT pg_temp.ok('G1c: after G1b the ledger holds the notice AND a due row (if G1b was accepted)',
  NOT EXISTS (SELECT 1 FROM public.deposit_events WHERE deposit_id = pg_temp.did('rtar') AND event_type = 'refund_initiated')
  OR EXISTS (SELECT 1 FROM public.deposit_return_due WHERE deposit_id = pg_temp.did('rtar')));
SELECT pg_temp.try('G1d: and the status now says', format('SELECT 1 WHERE %L = (SELECT status FROM public.deposits WHERE id = %L)', 'x', pg_temp.did('rtar')), :'u2');
SELECT status AS rtar_status_after_g1b FROM public.deposits WHERE id = pg_temp.did('rtar');
SELECT count(*) AS due_rows_after_g1b FROM public.deposit_return_due WHERE deposit_id = pg_temp.did('rtar');
ROLLBACK TO SAVEPOINT g2;
SAVEPOINT g3;
SELECT pg_temp.try('G1e: notice, due row AND its evidence in ONE statement (chained CTEs) — a complete record, constraints immediate',
  format($q$WITH e AS (INSERT INTO public.deposit_events (tenant_id, deposit_id, event_type, amount, effective_on)
                       SELECT d.tenant_id, d.id, 'refund_initiated', 60, DATE '2026-11-02' FROM public.deposits d WHERE d.id = %L RETURNING deposit_id),
                r AS (INSERT INTO public.deposit_return_due (tenant_id, deposit_id, rule_id, due_on, inputs, inputs_fingerprint, calculated_by)
                       SELECT d.tenant_id, d.id, d.rule_id, DATE '2026-11-02', '{"bills": 12}', 'fp-cte3', 'core-battery-1' FROM public.deposits d JOIN e ON e.deposit_id = d.id RETURNING id, tenant_id)
           INSERT INTO public.deposit_return_due_evidence (tenant_id, due_id, reason_code, return_component, invoice_id, classification, rests_on_deposit)
           SELECT r.tenant_id, r.id, 'clean_bill_history', 'r1', %L::uuid, 'clean', false FROM r$q$, pg_temp.did('rtar'), :'i1'), :'u2');
SELECT (SELECT status FROM public.deposits WHERE id = pg_temp.did('rtar')) AS status_after_g1e,
       (SELECT count(*) FROM public.deposit_return_due WHERE deposit_id = pg_temp.did('rtar')) AS due_rows_after_g1e,
       (SELECT count(*) FROM public.deposits_return_owed WHERE deposit_id = pg_temp.did('rtar')) AS owed_rows_after_g1e;
ROLLBACK TO SAVEPOINT g3;
