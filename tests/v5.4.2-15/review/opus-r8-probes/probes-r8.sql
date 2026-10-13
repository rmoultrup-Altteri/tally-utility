-- Opus r8 probes: after V28d, same transaction, as tally_app (u2, tenant t2), rolled back.
CREATE FUNCTION pg_temp.try2(p_label text, p_sql text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_state text; v_msg text;
BEGIN
  BEGIN
    PERFORM set_config('app.user_id', '00000000-0000-4000-8000-0000000015b2', true);
    SET LOCAL ROLE tally_app;
    EXECUTE p_sql;
    RESET ROLE;
    RAISE NOTICE 'PROBE % => ACCEPTED', p_label;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    RESET ROLE;
    RAISE NOTICE 'PROBE % => REFUSED % %', p_label, v_state, v_msg;
  END;
END $$;
-- due row (main-referenced CTE r, so it runs first) + evidence + whatever events p_events lists, each citing r.id or not
CREATE FUNCTION pg_temp.due_ev(p_dep uuid, p_fp text, p_events text) RETURNS text LANGUAGE sql AS $$
  SELECT format($q$WITH r AS (INSERT INTO public.deposit_return_due (tenant_id, deposit_id, rule_id, due_on, inputs, inputs_fingerprint, calculated_by)
                        SELECT d.tenant_id, d.id, d.rule_id, DATE '2026-11-02', '{"bills": 12}', %L, 'core-battery-1' FROM public.deposits d WHERE d.id = %L RETURNING id, tenant_id, deposit_id),
                ev AS (INSERT INTO public.deposit_return_due_evidence (tenant_id, due_id, reason_code, return_component, invoice_id, classification, rests_on_deposit)
                        SELECT r.tenant_id, r.id, 'clean_bill_history', 'r1', '00000000-0000-4000-8000-0000000015e1'::uuid, 'clean', false FROM r RETURNING due_id)
           INSERT INTO public.deposit_events (tenant_id, deposit_id, event_type, amount, effective_on, return_due_id)
           SELECT r.tenant_id, r.deposit_id, v.t, v.a, v.e, CASE WHEN v.cite THEN r.id END FROM r, (VALUES %s) v(t, a, e, cite)$q$, p_fp, p_dep, p_events)
$$;
SELECT pg_temp.mk('o1', '00000000-0000-4000-8000-0000000015a2', jsonb_build_object('customer', '00000000-0000-4000-8000-0000000015c9', 'basis', 'tariff', 'principal', '60.00'));
SELECT pg_temp.try2('P1 one statement: due row, notice citing it, refunded NOT citing it',
  pg_temp.due_ev(pg_temp.did('o1'), 'fp-o1', $v$('refund_initiated'::text, 60::numeric, DATE '2026-11-02', true), ('refunded', 60, DATE '2026-11-03', false)$v$));
SELECT pg_temp.try2('P2 one statement: due row, notice citing it, refunded citing it too',
  pg_temp.due_ev(pg_temp.did('o1'), 'fp-o1b', $v$('refund_initiated'::text, 60::numeric, DATE '2026-11-02', true), ('refunded', 60, DATE '2026-11-03', true)$v$));
SELECT pg_temp.mk('o2', '00000000-0000-4000-8000-0000000015a2', jsonb_build_object('customer', '00000000-0000-4000-8000-0000000015c9', 'basis', 'tariff', 'principal', '60.00'));
SELECT pg_temp.try2('P3 one statement: refunded alone (no notice) citing the new due row',
  pg_temp.due_ev(pg_temp.did('o2'), 'fp-o2', $v$('refunded'::text, 60::numeric, DATE '2026-11-02', true)$v$));
SELECT pg_temp.mk('o3', '00000000-0000-4000-8000-0000000015a2', jsonb_build_object('customer', '00000000-0000-4000-8000-0000000015c9', 'basis', 'tariff', 'principal', '60.00'));
-- P4: separate statements, the legitimate path with an uncited payment
SELECT pg_temp.try2('P4a separate: due row', pg_temp.wd_sql('00000000-0000-4000-8000-00000000f401', pg_temp.did('o3'), '2026-11-02', '{}', jsonb_build_array(pg_temp.bill('00000000-0000-4000-8000-0000000015e1'))));
SELECT pg_temp.try2('P4b separate: notice citing it', pg_temp.ev_sql(pg_temp.did('o3'), 'refund_initiated', 60, DATE '2026-11-02', '00000000-0000-4000-8000-00000000f401'));
SELECT pg_temp.try2('P4c separate: refunded, not citing', pg_temp.ev_sql(pg_temp.did('o3'), 'refunded', 60, DATE '2026-11-03'));
-- P5: withdraw-and-supersede plus the citing notice, one statement
SELECT pg_temp.mk('o4', '00000000-0000-4000-8000-0000000015a2', jsonb_build_object('customer', '00000000-0000-4000-8000-0000000015c9', 'basis', 'tariff', 'principal', '60.00'));
SELECT pg_temp.try2('P5a due row to be corrected', pg_temp.wd_sql('00000000-0000-4000-8000-00000000f501', pg_temp.did('o4'), '2026-11-02', '{}', jsonb_build_array(pg_temp.bill('00000000-0000-4000-8000-0000000015e1'))));
SELECT pg_temp.try2('P5b one statement: withdraw it, supersede it, and a notice citing the new row',
  format($q$WITH w AS (INSERT INTO public.deposit_return_due_withdrawals (tenant_id, due_id, reason) VALUES ('00000000-0000-4000-8000-0000000015a2', '00000000-0000-4000-8000-00000000f501', 'probe') RETURNING due_id),
                r AS (INSERT INTO public.deposit_return_due (tenant_id, deposit_id, rule_id, due_on, supersedes_due_id, inputs, inputs_fingerprint, calculated_by)
                        SELECT d.tenant_id, d.id, d.rule_id, DATE '2026-11-02', w.due_id, '{"bills": 12}', 'fp-o4', 'core-battery-1' FROM public.deposits d, w WHERE d.id = %L RETURNING id, tenant_id, deposit_id),
                ev AS (INSERT INTO public.deposit_return_due_evidence (tenant_id, due_id, reason_code, return_component, invoice_id, classification, rests_on_deposit)
                        SELECT r.tenant_id, r.id, 'clean_bill_history', 'r1', '00000000-0000-4000-8000-0000000015e1'::uuid, 'clean', false FROM r RETURNING due_id)
           INSERT INTO public.deposit_events (tenant_id, deposit_id, event_type, amount, effective_on, return_due_id)
           SELECT r.tenant_id, r.deposit_id, 'refund_initiated', 60, DATE '2026-11-02', r.id FROM r$q$, pg_temp.did('o4')));
-- P6: slips. Two due rows in one statement, the notice citing the first.
SELECT pg_temp.mk('o5', '00000000-0000-4000-8000-0000000015a2', jsonb_build_object('customer', '00000000-0000-4000-8000-0000000015c9', 'basis', 'tariff', 'principal', '60.00'));
SELECT pg_temp.try2('P6 one statement: two due rows, notice citing the first',
  format($q$WITH r AS (INSERT INTO public.deposit_return_due (tenant_id, deposit_id, rule_id, due_on, inputs, inputs_fingerprint, calculated_by)
                        SELECT d.tenant_id, d.id, d.rule_id, x.due, '{"bills": 12}', x.fp, 'core-battery-1' FROM public.deposits d,
                               (VALUES (DATE '2026-11-02', 'fp-o5a'), (DATE '2026-11-03', 'fp-o5b')) x(due, fp) WHERE d.id = %L RETURNING id, tenant_id, deposit_id, due_on),
                ev AS (INSERT INTO public.deposit_return_due_evidence (tenant_id, due_id, reason_code, return_component, invoice_id, classification, rests_on_deposit)
                        SELECT r.tenant_id, r.id, 'clean_bill_history', 'r1', '00000000-0000-4000-8000-0000000015e1'::uuid, 'clean', false FROM r RETURNING due_id)
           INSERT INTO public.deposit_events (tenant_id, deposit_id, event_type, amount, effective_on, return_due_id)
           SELECT r.tenant_id, r.deposit_id, 'refund_initiated', 60, DATE '2026-11-03', r.id FROM r WHERE r.due_on = DATE '2026-11-02'$q$, pg_temp.did('o5')));
-- P7: after a notice citing row A, withdraw A and write row B in one statement (no new event)
SELECT pg_temp.try2('P7 one statement on o3 (refunded) / o4: withdraw the cited row and supersede it',
  format($q$WITH w AS (INSERT INTO public.deposit_return_due_withdrawals (tenant_id, due_id, reason)
                        SELECT r.tenant_id, r.id, 'probe' FROM public.deposit_return_due r WHERE r.deposit_id = %L AND r.inputs_fingerprint = 'fp-o4' RETURNING due_id)
           INSERT INTO public.deposit_return_due (tenant_id, deposit_id, rule_id, due_on, supersedes_due_id, inputs, inputs_fingerprint, calculated_by)
           SELECT d.tenant_id, d.id, d.rule_id, DATE '2026-11-05', w.due_id, '{"bills": 12}', 'fp-o4c', 'core-battery-1' FROM public.deposits d, w WHERE d.id = %L$q$, pg_temp.did('o4'), pg_temp.did('o4')));
DO $$ DECLARE r record; BEGIN
  FOR r IN SELECT k, d.status, (SELECT count(*) FROM public.deposit_return_due x WHERE x.deposit_id = d.id) AS dues,
                  (SELECT string_agg(e.event_type || coalesce('->' || left(e.return_due_id::text, 8), ''), ',' ORDER BY e.created_at) FROM public.deposit_events e WHERE e.deposit_id = d.id) AS evs
             FROM b15r JOIN public.deposits d ON d.id = b15r.id WHERE k LIKE 'o%' ORDER BY k LOOP
    RAISE NOTICE 'STATE % status=% due_rows=% events=%', r.k, r.status, r.dues, r.evs;
  END LOOP; END $$;
