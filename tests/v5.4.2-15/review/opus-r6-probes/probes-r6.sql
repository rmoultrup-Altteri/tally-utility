-- Opus r6 probes: run after the battery's r29 block, same transaction, rolled back.
CREATE FUNCTION pg_temp.try(p_label text, p_sql text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_state text; v_msg text; v_user text;
BEGIN
  SELECT id::text INTO v_user FROM public.users WHERE tenant_id = '00000000-0000-4000-8000-0000000015a1'::uuid ORDER BY id LIMIT 1;
  BEGIN
    PERFORM set_config('app.user_id', v_user, true);
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
CREATE TEMP TABLE pd (k text PRIMARY KEY, id uuid);
GRANT ALL ON pd TO tally_app;
-- make a fresh instalment deposit (175, 87.50 at posting 15 Jan, 87.50 due 14 Feb) and remember it under k
CREATE FUNCTION pg_temp.mk(k text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_sql text;
BEGIN
  v_sql := pg_temp.dw_sql(jsonb_build_object('tenant', '00000000-0000-4000-8000-0000000015a1', 'customer', '00000000-0000-4000-8000-0000000015c1',
     'rule', pg_temp.law('residential', 'credit_evaluation', 'municipal'), 'category', 'installer',
     'tariff', pg_temp.tar('00000000-0000-4000-8000-0000000015a1', 'installer'), 'principal', '175.00', 'cap', '175.00', 'cap_source', 'tariff',
     'cap_component', null, 'cap_basis', null, 'received', '87.50'), '{87.50}', '{2026-02-14}');
  PERFORM pg_temp.try('mk ' || k, v_sql);
  INSERT INTO pd SELECT k, d.id FROM public.deposits d WHERE d.customer_id = '00000000-0000-4000-8000-0000000015c1' AND d.received_at_posting = 87.50
     AND d.id NOT IN (SELECT id FROM pd) AND d.status = 'held' ORDER BY d.created_at DESC LIMIT 1;
END $$;
CREATE FUNCTION pg_temp.ev(k text, t text, a numeric, d date, lbl text) RETURNS void LANGUAGE sql AS $$
  SELECT pg_temp.try(k || ' ' || lbl, pg_temp.ev_sql((SELECT id FROM pd WHERE pd.k = ev.k), t, a, d))
$$;
CREATE FUNCTION pg_temp.show(k text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE r record;
BEGIN
  SELECT d.status, b.remainder, b.exhausted_on INTO r FROM public.deposits d, public.deposit_balance(d.id) b WHERE d.id = (SELECT id FROM pd WHERE pd.k = show.k);
  RAISE NOTICE 'STATE % status=% remainder=% exhausted_on=%', k, r.status, r.remainder, r.exhausted_on;
END $$;

-- T: ties on one day
SELECT pg_temp.mk('T');
SELECT pg_temp.ev('T', 'instalment_received', 87.50, '2026-02-14', 'T1 instalment 14 Feb');
SELECT pg_temp.ev('T', 'applied_to_balance', 175, '2026-02-13', 'T2 apply 175 on 13 Feb (expect REFUSED, held 87.50)');
SELECT pg_temp.ev('T', 'applied_to_balance', 100, '2026-02-14', 'T3 apply 100 on 14 Feb, same day as instalment (expect ACCEPTED)');
SELECT pg_temp.ev('T', 'principal_returned', 75, '2026-02-14', 'T4 return 75 on 14 Feb (75 = remainder -> refused by < remainder rule)');
SELECT pg_temp.ev('T', 'principal_returned', 74.99, '2026-02-14', 'T5 return 74.99 on 14 Feb (expect ACCEPTED)');
SELECT pg_temp.ev('T', 'applied_to_balance', 0.02, '2026-02-14', 'T6 apply 0.02 on 14 Feb (remainder 0.01, expect REFUSED by remainder)');
SELECT pg_temp.ev('T', 'applied_to_balance', 0.01, '2026-01-15', 'T7 apply 0.01 backdated to posting day (held 87.50 then, but 14 Feb day would go to -0.00? expect ACCEPTED: 14 Feb held 0.01)');
SELECT pg_temp.show('T');

-- S: several receipts (the second instalment received in two parts, one late)
SELECT pg_temp.mk('S');
SELECT pg_temp.ev('S', 'instalment_received', 40, '2026-02-14', 'S1 receipt 40 on 14 Feb');
SELECT pg_temp.ev('S', 'instalment_received', 47.50, '2026-03-01', 'S2 receipt 47.50 on 1 Mar (late)');
SELECT pg_temp.ev('S', 'principal_returned', 127.51, '2026-02-20', 'S3 return 127.51 on 20 Feb (held 127.50; expect REFUSED)');
SELECT pg_temp.ev('S', 'principal_returned', 127.50, '2026-02-20', 'S4 return 127.50 on 20 Feb (boundary, expect ACCEPTED)');
SELECT pg_temp.ev('S', 'applied_to_balance', 0.01, '2026-02-25', 'S5 apply 0.01 on 25 Feb (held 0; expect REFUSED)');
SELECT pg_temp.ev('S', 'applied_to_balance', 47.50, '2026-03-01', 'S6 apply 47.50 on 1 Mar (expect ACCEPTED)');
SELECT pg_temp.show('S');
SELECT pg_temp.ev('S', 'refunded', 0, '2026-02-28', 'S7 zero refund dated 28 Feb, before the 1 Mar receipt/application (expect REFUSED)');
SELECT pg_temp.ev('S', 'refunded', 0, '2026-03-01', 'S8 zero refund dated 1 Mar (expect ACCEPTED)');
SELECT pg_temp.show('S');

-- B: a debit dated before posting / before any receipt
SELECT pg_temp.mk('B');
SELECT pg_temp.ev('B', 'applied_to_balance', 10, '2026-01-14', 'B1 apply dated the day before posting (expect REFUSED by posted_on check)');
SELECT pg_temp.ev('B', 'applied_to_balance', 87.50, '2026-01-15', 'B2 apply 87.50 on posting day (expect ACCEPTED)');
SELECT pg_temp.show('B');
-- L: status projection after a late receipt
SELECT pg_temp.ev('B', 'instalment_received', 87.50, '2026-01-10', 'L1 instalment dated before posting (expect REFUSED)');
SELECT pg_temp.ev('B', 'instalment_received', 87.50, '2026-01-16', 'L2 instalment backdated to 16 Jan, after the full application (expect ACCEPTED)');
SELECT pg_temp.show('B');
SELECT pg_temp.ev('B', 'applied_to_balance', 87.50, '2026-01-15', 'L3 apply 87.50 on 15 Jan again (held 0 that day; expect REFUSED)');
SELECT pg_temp.ev('B', 'applied_to_balance', 87.50, '2026-01-16', 'L4 apply 87.50 on 16 Jan (expect ACCEPTED)');
SELECT pg_temp.show('B');

-- R: refund-type events vs other events
SELECT pg_temp.mk('R');
SELECT pg_temp.ev('R', 'instalment_received', 87.50, '2026-02-14', 'R1 instalment 14 Feb');
SELECT pg_temp.ev('R', 'refund_initiated', 175, '2026-02-20', 'R2 refund notice 20 Feb');
SELECT pg_temp.ev('R', 'refunded', 175, '2026-02-15', 'R3 refunded dated 15 Feb, before the notice of 20 Feb (ordering of notice vs payment)');
SELECT pg_temp.show('R');
SELECT pg_temp.mk('R2');
SELECT pg_temp.ev('R2', 'refund_initiated', 87.50, '2026-02-01', 'R2a refund notice 1 Feb before the 14 Feb instalment is received (nothing later recorded yet: ACCEPTED?)');
SELECT pg_temp.ev('R2', 'instalment_received', 87.50, '2026-02-14', 'R2b instalment after notice (expect REFUSED: pending)');
SELECT pg_temp.show('R2');
