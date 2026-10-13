-- One statement, several rows: the status projection is an AFTER ROW trigger, queued to the statement's end.
CREATE FUNCTION pg_temp.multi(k text, p_rows text, lbl text) RETURNS void LANGUAGE sql AS $$
  SELECT pg_temp.try(k || ' ' || lbl, format($q$INSERT INTO public.deposit_events (tenant_id, deposit_id, event_type, amount, effective_on)
     SELECT d.tenant_id, d.id, v.t, v.a, v.e FROM public.deposits d, (VALUES %s) v(t, a, e) WHERE d.id = %L$q$, p_rows, (SELECT id FROM pd WHERE pd.k = multi.k)))
$$;
SELECT pg_temp.mk('M1');
SELECT pg_temp.multi('M1', $v$('refund_initiated'::text, 87.50::numeric, DATE '2026-02-01'), ('instalment_received', 87.50, DATE '2026-02-14')$v$,
  'MS1 one statement: refund notice 1 Feb for 87.50, then the instalment of 14 Feb');
SELECT pg_temp.show('M1');
SELECT pg_temp.mk('M2');
SELECT pg_temp.multi('M2', $v$('refunded'::text, 87.50::numeric, DATE '2026-02-01'), ('instalment_received', 87.50, DATE '2026-02-14'), ('applied_to_balance', 87.50, DATE '2026-02-15')$v$,
  'MS2 one statement: refunded 1 Feb, then an instalment and an application after it');
SELECT pg_temp.show('M2');
SELECT pg_temp.try('M2 events', format('DO $d$ DECLARE r record; BEGIN FOR r IN SELECT event_type, amount, effective_on FROM public.deposit_events WHERE deposit_id = %L ORDER BY created_at, id LOOP RAISE NOTICE %L, r.event_type, r.amount, r.effective_on; END LOOP; END $d$', (SELECT id FROM pd WHERE k = 'M2'), 'EV % % %'));
SELECT pg_temp.mk('M3');
SELECT pg_temp.multi('M3', $v$('applied_to_balance'::text, 87.50::numeric, DATE '2026-01-20'), ('applied_to_balance', 87.50, DATE '2026-01-20')$v$,
  'MS3 one statement: two applications of 87.50 on 20 Jan (held 87.50) — the timeline guard sees the earlier row');
