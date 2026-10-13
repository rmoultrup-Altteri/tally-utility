-- Fable r8 probes on rcte (T2, c9, tariff basis, principal 60, cash)
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
    RAISE NOTICE 'PROBE % -> REFUSED % %', p_label, v_state, left(v_msg, 150);
  END;
END $$;
CREATE FUNCTION pg_temp.due_cte(p_alias text, p_dep uuid, p_fp text, p_prev text DEFAULT NULL) RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT format($q$%s AS (INSERT INTO public.deposit_return_due (tenant_id, deposit_id, rule_id, due_on, inputs, inputs_fingerprint, calculated_by)
                 SELECT d.tenant_id, d.id, d.rule_id, DATE '2026-11-02', '{"bills": 12}', %L, 'core-battery-1' FROM public.deposits d WHERE d.id = %L%s RETURNING id, tenant_id, deposit_id)$q$,
                p_alias, p_fp, p_dep, CASE WHEN p_prev IS NULL THEN '' ELSE format(' AND EXISTS (SELECT 1 FROM %s)', p_prev) END)
$$;
CREATE FUNCTION pg_temp.evd_cte(p_alias text, p_due_alias text, p_inv text) RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT format($q$%s AS (INSERT INTO public.deposit_return_due_evidence (tenant_id, due_id, reason_code, return_component, invoice_id, classification, rests_on_deposit)
                 SELECT r.tenant_id, r.id, 'clean_bill_history', 'r1', %L::uuid, 'clean', false FROM %s r RETURNING due_id)$q$, p_alias, p_inv, p_due_alias)
$$;

-- H1 slipping a due row beside a started return
SAVEPOINT h1a;
SELECT pg_temp.refuses('H1a: two due rows and a refund notice citing the first, in one statement',
  format($q$WITH %s, %s, %s, %s, e AS (INSERT INTO public.deposit_events (tenant_id, deposit_id, event_type, amount, effective_on, return_due_id)
             SELECT d.tenant_id, d.id, 'refund_initiated', 60, DATE '2026-11-02', r1.id FROM public.deposits d JOIN r1 ON r1.deposit_id = d.id RETURNING id)
           SELECT count(*) FROM e, r2$q$,
         pg_temp.due_cte('r1', pg_temp.did('rcte'), 'fp-h1a-1'), pg_temp.evd_cte('ev1', 'r1', :'i1'),
         pg_temp.due_cte('r2', pg_temp.did('rcte'), 'fp-h1a-2', 'ev1'), pg_temp.evd_cte('ev2', 'r2', :'i1')),
  '23505', 'live due row', 'tally_app', :'u2');
ROLLBACK TO SAVEPOINT h1a;
SAVEPOINT h1b;
SELECT pg_temp.try('H1b: a due row, a refund notice citing it, and a second notice NOT citing it, in one statement',
  format($q$WITH %s, %s, e1 AS (INSERT INTO public.deposit_events (tenant_id, deposit_id, event_type, amount, effective_on, return_due_id)
             SELECT d.tenant_id, d.id, 'refund_initiated', 60, DATE '2026-11-02', r.id FROM public.deposits d JOIN r ON r.deposit_id = d.id RETURNING id)
           INSERT INTO public.deposit_events (tenant_id, deposit_id, event_type, amount, effective_on)
             SELECT d.tenant_id, d.id, 'refund_initiated', 60, DATE '2026-11-03' FROM public.deposits d JOIN r ON r.deposit_id = d.id WHERE EXISTS (SELECT 1 FROM e1)$q$,
         pg_temp.due_cte('r', pg_temp.did('rcte'), 'fp-h1b'), pg_temp.evd_cte('ev', 'r', :'i1')), :'u2');
ROLLBACK TO SAVEPOINT h1b;
SAVEPOINT h1c;
SELECT pg_temp.try('H1c: a due row and a RELEASE-less refund (refunded, not initiated) that does not cite it, one statement',
  format($q$WITH %s, %s INSERT INTO public.deposit_events (tenant_id, deposit_id, event_type, amount, effective_on)
             SELECT d.tenant_id, d.id, 'refunded', 60, DATE '2026-11-02' FROM public.deposits d JOIN r ON r.deposit_id = d.id$q$,
         pg_temp.due_cte('r', pg_temp.did('rcte'), 'fp-h1c'), pg_temp.evd_cte('ev', 'r', :'i1')), :'u2');
ROLLBACK TO SAVEPOINT h1c;
-- H1d the other order, two statements: the due row first, then a refund notice that does not cite it
SAVEPOINT h1d;
SELECT pg_temp.try('H1d-1: a due row with evidence on rcte (two-statement path)',
  pg_temp.wd_sql('00000000-0000-4000-8000-00000000f8d1', pg_temp.did('rcte'), '2026-11-02', '{}', jsonb_build_array(pg_temp.bill(:'i1'))), :'u2');
SELECT pg_temp.try('H1d-2: OBSERVATION — then a refund notice that does NOT cite the live due row',
  pg_temp.ev_sql(pg_temp.did('rcte'), 'refund_initiated', 60, DATE '2026-11-03'), :'u2');
SELECT (SELECT status FROM public.deposits WHERE id = pg_temp.did('rcte')) AS status_h1d,
       public.deposit_return_due_is_live('00000000-0000-4000-8000-00000000f8d1') AS due_row_live_h1d,
       (SELECT count(*) FROM public.deposits_return_owed WHERE deposit_id = pg_temp.did('rcte')) AS owed_h1d;
SELECT pg_temp.try('H1d-3: … and the refund itself may then cite that row', pg_temp.ev_sql(pg_temp.did('rcte'), 'refunded', 60, DATE '2026-11-03', '00000000-0000-4000-8000-00000000f8d1'), :'u2');
ROLLBACK TO SAVEPOINT h1d;
-- H1e withdraw a cited row, then supersede it
SAVEPOINT h1e;
SELECT pg_temp.try('H1e-1: due row A', pg_temp.wd_sql('00000000-0000-4000-8000-00000000f8e1', pg_temp.did('rcte'), '2026-11-02', '{}', jsonb_build_array(pg_temp.bill(:'i1'))), :'u2');
SELECT pg_temp.try('H1e-2: refund notice citing A', pg_temp.ev_sql(pg_temp.did('rcte'), 'refund_initiated', 60, DATE '2026-11-02', '00000000-0000-4000-8000-00000000f8e1'), :'u2');
SELECT pg_temp.try('H1e-3: withdraw A after the notice cited it',
  format($q$INSERT INTO public.deposit_return_due_withdrawals (tenant_id, due_id, reason) VALUES (%L, %L, 'battery: A wrong')$q$, :'t2', '00000000-0000-4000-8000-00000000f8e1'), :'u2');
SELECT pg_temp.try('H1e-4: due row B superseding A, beside the started return',
  pg_temp.wd_sql('00000000-0000-4000-8000-00000000f8e2', pg_temp.did('rcte'), '2026-11-03', jsonb_build_object('supersedes', '00000000-0000-4000-8000-00000000f8e1'), jsonb_build_array(pg_temp.bill(:'i1'))), :'u2');
ROLLBACK TO SAVEPOINT h1e;

-- H2 legitimate flows must still pass
SAVEPOINT h2a;
SELECT pg_temp.does_as('H2a: due row, evidence, the notice citing it and the refund citing it — all in one statement', :'t2',
  format($q$WITH %s, %s, e1 AS (INSERT INTO public.deposit_events (tenant_id, deposit_id, event_type, amount, effective_on, return_due_id)
             SELECT d.tenant_id, d.id, 'refund_initiated', 60, DATE '2026-11-02', r.id FROM public.deposits d JOIN r ON r.deposit_id = d.id RETURNING id)
           INSERT INTO public.deposit_events (tenant_id, deposit_id, event_type, amount, effective_on, return_due_id)
             SELECT d.tenant_id, d.id, 'refunded', 60, DATE '2026-11-02', r.id FROM public.deposits d JOIN r ON r.deposit_id = d.id WHERE EXISTS (SELECT 1 FROM e1)$q$,
         pg_temp.due_cte('r', pg_temp.did('rcte'), 'fp-h2a'), pg_temp.evd_cte('ev', 'r', :'i1')));
SELECT pg_temp.ok('H2a-2: the deposit is refunded', (SELECT status FROM public.deposits WHERE id = pg_temp.did('rcte')) = 'refunded');
ROLLBACK TO SAVEPOINT h2a;
SAVEPOINT h2b;
SELECT pg_temp.does_as('H2b-1: due row A', :'t2', pg_temp.wd_sql('00000000-0000-4000-8000-00000000f8b1', pg_temp.did('rcte'), '2026-11-02', '{}', jsonb_build_array(pg_temp.bill(:'i1'))));
SELECT pg_temp.does_as('H2b-2: A withdrawn', :'t2', format($q$INSERT INTO public.deposit_return_due_withdrawals (tenant_id, due_id, reason) VALUES (%L, %L, 'battery: A wrong')$q$, :'t2', '00000000-0000-4000-8000-00000000f8b1'));
SELECT pg_temp.does_as('H2b-3: B supersedes A', :'t2', pg_temp.wd_sql('00000000-0000-4000-8000-00000000f8b2', pg_temp.did('rcte'), '2026-11-03', jsonb_build_object('supersedes', '00000000-0000-4000-8000-00000000f8b1'), jsonb_build_array(pg_temp.bill(:'i1'))));
SELECT pg_temp.does_as('H2b-4: the refund (no notice first) cites B, two statements', :'t2', pg_temp.ev_sql(pg_temp.did('rcte'), 'refunded', 60, DATE '2026-11-03', '00000000-0000-4000-8000-00000000f8b2'));
ROLLBACK TO SAVEPOINT h2b;
