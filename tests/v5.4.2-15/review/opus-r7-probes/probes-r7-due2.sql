-- Opus r7, part 2: control in a second statement; the reverse CTE order; what a due-row BEFORE trigger can see.
CREATE FUNCTION public.zz_opus_peek() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  RAISE NOTICE 'PEEK due-row BEFORE trigger sees % refund-type event(s) for the deposit',
    (SELECT count(*) FROM public.deposit_events e WHERE e.deposit_id = NEW.deposit_id AND e.event_type IN ('refund_initiated', 'refunded', 'released'));
  RETURN NEW;
END $$;
CREATE TRIGGER b_zz_opus_peek BEFORE INSERT ON public.deposit_return_due FOR EACH ROW EXECUTE FUNCTION public.zz_opus_peek();
SELECT pg_temp.try2('DUE1 one statement: refund notice in a CTE + due row in the main statement (rtar)',
  pg_temp.cte_sql(pg_temp.did('rtar'), 'refund_initiated', 60, '2026-03-01', '00000000-0000-4000-8000-00000000f002'));
SELECT pg_temp.try2('DUE2 control, separate statement: a due row on rtar after its notice',
  'INSERT INTO public.deposit_return_due (id, tenant_id, deposit_id, rule_id, due_on, inputs, inputs_fingerprint, calculated_by) SELECT ''00000000-0000-4000-8000-00000000f003'', d.tenant_id, d.id, d.rule_id, DATE ''2026-04-01'', ''{}'', ''fp'', ''x'' FROM public.deposits d WHERE d.id = ''' || pg_temp.did('rtar') || '''');
-- reverse: due row in the CTE, the notice in the main statement (rr, held, no due row yet)
SELECT pg_temp.try2('DUE3 one statement: due row in a CTE + refund notice of 100 in the main statement (rr)',
  format($q$WITH due AS (INSERT INTO public.deposit_return_due (id, tenant_id, deposit_id, rule_id, due_on, inputs, inputs_fingerprint, calculated_by)
                   SELECT '00000000-0000-4000-8000-00000000f004', d.tenant_id, d.id, d.rule_id, DATE '2026-04-01', '{"bills": 12}', 'fp-cte', 'core-battery-1'
                     FROM public.deposits d WHERE d.id = %L RETURNING id)
     INSERT INTO public.deposit_events (tenant_id, deposit_id, event_type, amount, effective_on)
     SELECT d.tenant_id, d.id, 'refund_initiated', 100, DATE '2026-03-01' FROM public.deposits d WHERE d.id = %L;
     INSERT INTO public.deposit_return_due_evidence (tenant_id, due_id, reason_code, return_component, invoice_id, classification, rests_on_deposit)
     SELECT r.tenant_id, r.id, 'clean_bill_history', 'r1', '00000000-0000-4000-8000-0000000015e1', 'clean', false FROM public.deposit_return_due r WHERE r.id = '00000000-0000-4000-8000-00000000f004'$q$,
     pg_temp.did('rr'), pg_temp.did('rr')));
DO $$ DECLARE r record; BEGIN
  FOR r IN SELECT k, d.status, (SELECT count(*) FROM public.deposit_return_due x WHERE x.deposit_id = d.id) AS dues
             FROM b15r JOIN public.deposits d ON d.id = b15r.id WHERE k IN ('rr', 'rtar') LOOP
    RAISE NOTICE 'STATE % status=% due_rows=%', r.k, r.status, r.dues;
  END LOOP; END $$;
