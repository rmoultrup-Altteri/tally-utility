-- Codex r2: PREDICTED, NOT EXECUTED. Owner on a fresh clone with frozen r2 applied.
-- No cluster role changes. Local role switches exercise app/core boundaries.
\set ON_ERROR_STOP on
BEGIN ISOLATION LEVEL REPEATABLE READ;

CREATE FUNCTION pg_temp.refuses_at(p_label text, p_sql text, p_state text, p_guard text) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE v_con text;
BEGIN
  BEGIN
    EXECUTE p_sql;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'caught SQLSTATE=% message=%', SQLSTATE, SQLERRM;
    GET STACKED DIAGNOSTICS v_con = CONSTRAINT_NAME;
    IF SQLSTATE = p_state AND (v_con = p_guard OR strpos(SQLERRM, p_guard) > 0) THEN
      RAISE NOTICE 'PASS %: refused by % (%)', p_label, p_guard, left(SQLERRM, 120);
      RETURN;
    END IF;
    RAISE EXCEPTION 'FAIL %: refused with % [%] (%), expected % by %', p_label, SQLSTATE, v_con, SQLERRM, p_state, p_guard;
  END;
  RAISE EXCEPTION 'FAIL %: accepted', p_label;
END $$;
CREATE FUNCTION pg_temp.ok(p_label text, p_cond boolean) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  IF p_cond IS DISTINCT FROM true THEN RAISE EXCEPTION 'FAIL %', p_label; END IF;
  RAISE NOTICE 'PASS %', p_label;
END $$;
CREATE FUNCTION pg_temp.admits(p_label text, p_sql text) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE p_sql;
  RAISE NOTICE 'PASS %', p_label;
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'caught SQLSTATE=% message=%', SQLSTATE, SQLERRM;
  RAISE EXCEPTION 'FAIL %: refused with % (%)', p_label, SQLSTATE, SQLERRM;
END $$;
CREATE FUNCTION pg_temp.k(p text) RETURNS uuid LANGUAGE sql IMMUTABLE AS $$ SELECT ('00000000-0000-4000-8000-0000000a24' || p)::uuid $$;
-- The tenants, users and the clock the battery reads at.
CREATE FUNCTION pg_temp.t1() RETURNS uuid LANGUAGE sql IMMUTABLE AS $$ SELECT '00000000-0000-4000-8000-0000000a24a1'::uuid $$;
CREATE FUNCTION pg_temp.t2() RETURNS uuid LANGUAGE sql IMMUTABLE AS $$ SELECT '00000000-0000-4000-8000-0000000a24a2'::uuid $$;
CREATE FUNCTION pg_temp.op() RETURNS uuid LANGUAGE sql IMMUTABLE AS $$ SELECT '00000000-0000-4000-8000-0000000a24b1'::uuid $$;
-- post(): a pending payment's posting entry, then the move to posted (-27).
CREATE FUNCTION pg_temp.post(p_pay uuid, p_entry uuid) RETURNS void LANGUAGE plpgsql AS $$
DECLARE p public.payments%ROWTYPE;
BEGIN
  SELECT * INTO p FROM public.payments WHERE id = p_pay;
  INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reference_type, reference_id)
  VALUES (p_entry, p.tenant_id, p.customer_id, p.payment_date,
          CASE WHEN p.refunds_payment_id IS NOT NULL OR p.refunds_customer_credit_id IS NOT NULL THEN 'refund' WHEN p.is_deposit THEN 'deposit' ELSE 'payment' END,
          p.payment_number || ' posted', -p.amount, 'payment', p.id);
  UPDATE public.payments SET status = 'posted', status_cause_id = p_entry,
         effective_date = coalesce(effective_date, payment_date), effective_date_method = coalesce(effective_date_method, 'other')
   WHERE id = p_pay;
END $$;
-- bounce(): an nsf row taking back the whole posting entry, then nsf.
-- unpost(): a reversal (not nsf) of the posting entry, then reversed: the
-- payment was posted to the wrong customer.
CREATE FUNCTION pg_temp.bounce(p_pay uuid, p_entry uuid, p_on date) RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_row uuid := gen_random_uuid();
BEGIN
  INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reference_type, reference_id, reverses_ledger_entry_id)
  SELECT v_row, l.tenant_id, l.customer_id, p_on, 'nsf', 'returned', -l.amount, 'payment', l.reference_id, l.id FROM public.account_ledger l WHERE l.id = p_entry;
  UPDATE public.payments SET status = 'nsf', nsf_date = p_on, status_cause_id = v_row WHERE id = p_pay;
END $$;
CREATE FUNCTION pg_temp.unpost(p_pay uuid, p_entry uuid, p_on date) RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_row uuid := gen_random_uuid();
BEGIN
  INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reference_type, reference_id, reverses_ledger_entry_id, reversal_reason)
  SELECT v_row, l.tenant_id, l.customer_id, p_on, 'adjustment', 'posted to the wrong customer', -l.amount, 'payment', l.reference_id, l.id, 'posted to the wrong customer'
    FROM public.account_ledger l WHERE l.id = p_entry;
  UPDATE public.payments SET status = 'reversed', reversed_at = now(), reversed_by = pg_temp.op(), reversed_reason = 'posted to the wrong customer', status_cause_id = v_row
   WHERE id = p_pay;
END $$;
-- rcpt(): a receipt of T1 with a check number as its evidence.
CREATE FUNCTION pg_temp.rcpt(p_id uuid, p_amount numeric, p_on date, p_check text DEFAULT NULL, p_agency uuid DEFAULT NULL) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO public.suspense_receipts (id, tenant_id, receipt_number, amount, received_on, channel, source_system, check_number, payer_name, agency_id, recorded_by)
  VALUES (p_id, pg_temp.t1(), 'R24-' || right(p_id::text, 4), p_amount, p_on, 'lockbox', 'bank_lockbox', coalesce(p_check, 'CHK-' || right(p_id::text, 4)),
          'J. Smith', p_agency, pg_temp.op());
END $$;
-- fromr(): a pending payment of p_cust made from receipt p_r, carrying its
-- instrument, dated p_on (default the receipt's date) and effective the day
-- the money came; posted unless p_post is false.
CREATE FUNCTION pg_temp.fromr(p_id uuid, p_entry uuid, p_r uuid, p_cust uuid, p_amount numeric, p_post boolean DEFAULT true,
                              p_agency uuid DEFAULT NULL, p_on date DEFAULT NULL) RETURNS void LANGUAGE plpgsql AS $$
DECLARE r public.suspense_receipts%ROWTYPE;
BEGIN
  SELECT * INTO r FROM public.suspense_receipts WHERE id = p_r;
  INSERT INTO public.payments (id, tenant_id, payment_number, customer_id, payment_date, effective_date, effective_date_method, amount, payment_method, channel, source_system,
                               reference_number, check_number, check_date, check_bank_name, payer_class, agency_id,
                               suspense_receipt_id, suspense_resolution_reason, suspense_resolved_by)
  VALUES (p_id, pg_temp.t1(), 'P24-' || right(p_id::text, 4), p_cust, coalesce(p_on, r.received_on), r.received_on, 'lockbox_receipt', p_amount, 'check', r.channel, r.source_system,
          r.reference_number, r.check_number, r.check_date, r.check_bank_name,
          CASE WHEN p_agency IS NULL THEN 'customer' ELSE 'agency' END, p_agency,
          p_r, 'the customer called with the check number', pg_temp.op());
  IF p_post THEN PERFORM pg_temp.post(p_id, p_entry); END IF;
END $$;
-- disp(): a disposition of receipt p_r.
CREATE FUNCTION pg_temp.disp(p_id uuid, p_r uuid, p_kind text, p_amount numeric, p_on date, p_undoes uuid DEFAULT NULL) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO public.suspense_receipt_dispositions (id, tenant_id, suspense_receipt_id, kind, amount, disposed_on, instrument_reference,
                                                    return_code, jurisdiction, report_reference, reason, recorded_by, undoes_disposition_id)
  VALUES (coalesce(p_id, gen_random_uuid()), pg_temp.t1(), p_r, p_kind, p_amount, p_on,
          CASE WHEN p_kind = 'returned_to_sender' THEN 'REFUND-CHK-9001' END,
          CASE WHEN p_kind = 'bank_returned' THEN 'R01' END,
          CASE WHEN p_kind = 'escheated' THEN 'TX' END,
          CASE WHEN p_kind = 'escheated' THEN 'TX-UP-2027-0001' END,
          'battery-24 ' || p_kind, pg_temp.op(), p_undoes);
END $$;
-- mret(): a misposting return of payment p_pay (amount p_amount) to receipt p_r.
CREATE FUNCTION pg_temp.mret(p_id uuid, p_r uuid, p_pay uuid, p_amount numeric, p_on date) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO public.suspense_receipt_dispositions (id, tenant_id, suspense_receipt_id, kind, amount, disposed_on, reason, recorded_by, returned_payment_id)
  VALUES (coalesce(p_id, gen_random_uuid()), pg_temp.t1(), p_r, 'misposting_returned', -p_amount, p_on, 'posted to the wrong customer', pg_temp.op(), p_pay);
END $$;
-- held(): what a receipt still holds, read now at 2026-12-31.
CREATE FUNCTION pg_temp.held(p_r uuid) RETURNS numeric LANGUAGE sql AS $$
  SELECT held FROM public.suspense_receipt_position_as_of(p_r, DATE '2026-12-31', clock_timestamp())
$$;
-- pledge(): a pledge of T1 (agency p_ag, customer p_cust).
CREATE FUNCTION pg_temp.pledge(p_id uuid, p_cust uuid, p_ag uuid, p_amount numeric, p_on date) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO public.agency_pledges (id, tenant_id, customer_id, agency_id, amount, pledged_on, form, agency_reference, recorded_by)
  VALUES (p_id, pg_temp.t1(), p_cust, p_ag, p_amount, p_on, 'written', 'PL-' || right(p_id::text, 4), pg_temp.op());
END $$;
-- apay(): an agency payment of p_cust from p_ag, naming pledge p_pl; posted.
CREATE FUNCTION pg_temp.apay(p_id uuid, p_entry uuid, p_cust uuid, p_ag uuid, p_pl uuid, p_amount numeric, p_on date, p_post boolean DEFAULT true) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO public.payments (id, tenant_id, payment_number, customer_id, payment_date, amount, payment_method, payer_class, agency_id, agency_pledge_id)
  VALUES (p_id, pg_temp.t1(), 'A24-' || right(p_id::text, 4), p_cust, p_on, p_amount, 'check', 'agency', p_ag, p_pl);
  IF p_post THEN PERFORM pg_temp.post(p_id, p_entry); END IF;
END $$;
-- pst(): a pledge's state and paid, as text.
CREATE FUNCTION pg_temp.pst(p_pl uuid, p_on date DEFAULT DATE '2026-12-31') RETURNS text LANGUAGE sql AS $$
  SELECT format('%s/%s/%s', state, paid, outstanding) FROM public.agency_pledge_position_as_of(p_pl, p_on, clock_timestamp())
$$;
GRANT EXECUTE ON FUNCTION pg_temp.refuses_at(text, text, text, text), pg_temp.ok(text, boolean), pg_temp.admits(text, text), pg_temp.k(text),
  pg_temp.t1(), pg_temp.t2(), pg_temp.op(), pg_temp.post(uuid, uuid), pg_temp.bounce(uuid, uuid, date), pg_temp.unpost(uuid, uuid, date),
  pg_temp.rcpt(uuid, numeric, date, text, uuid), pg_temp.fromr(uuid, uuid, uuid, uuid, numeric, boolean, uuid, date),
  pg_temp.disp(uuid, uuid, text, numeric, date, uuid), pg_temp.held(uuid), pg_temp.mret(uuid, uuid, uuid, numeric, date),
  pg_temp.pledge(uuid, uuid, uuid, numeric, date), pg_temp.apay(uuid, uuid, uuid, uuid, uuid, numeric, date, boolean),
  pg_temp.pst(uuid, date) TO tally_app, tally_core;

-- ------------------------------------------------------------------ fixtures
-- T1 (…a24a1), T2 (…a24a2). Users b1 (T1), b2 (T2). Customers c1-c4 (T1), c9 (T2).
INSERT INTO public.tenants (id, name, slug) VALUES
  ('00000000-0000-4000-8000-0000000a24a1', 'T1 City Gas', 'bat24-t1'),
  ('00000000-0000-4000-8000-0000000a24a2', 'T2 Gasco', 'bat24-t2');
INSERT INTO public.users (id, tenant_id, display_name, email, role, is_active) VALUES
  ('00000000-0000-4000-8000-0000000a24b1', '00000000-0000-4000-8000-0000000a24a1', 'Op1', 'op1@bat24.test', 'operator', true),
  ('00000000-0000-4000-8000-0000000a24b2', '00000000-0000-4000-8000-0000000a24a2', 'Op2', 'op2@bat24.test', 'operator', true);
INSERT INTO public.customers (id, tenant_id, customer_number, customer_type) VALUES
  ('00000000-0000-4000-8000-0000000a24c1', '00000000-0000-4000-8000-0000000a24a1', 'B24-C1', 'residential'),
  ('00000000-0000-4000-8000-0000000a24c2', '00000000-0000-4000-8000-0000000a24a1', 'B24-C2', 'residential'),
  ('00000000-0000-4000-8000-0000000a24c3', '00000000-0000-4000-8000-0000000a24a1', 'B24-C3', 'residential'),
  ('00000000-0000-4000-8000-0000000a24c4', '00000000-0000-4000-8000-0000000a24a1', 'B24-C4', 'residential'),
  ('00000000-0000-4000-8000-0000000a24c9', '00000000-0000-4000-8000-0000000a24a2', 'B24-C9', 'residential');
\set c1 '''00000000-0000-4000-8000-0000000a24c1'''
\set c2 '''00000000-0000-4000-8000-0000000a24c2'''
\set c3 '''00000000-0000-4000-8000-0000000a24c3'''
\set c4 '''00000000-0000-4000-8000-0000000a24c4'''
\set c9 '''00000000-0000-4000-8000-0000000a24c9'''


CREATE FUNCTION pg_temp.observe(label text, stmt text) RETURNS boolean LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE stmt;
  RAISE NOTICE '%: ACCEPTED SQLSTATE=00000', label;
  RETURN true;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '%: REJECTED SQLSTATE=% message=%', label, SQLSTATE, SQLERRM;
  RETURN false;
END $$;
GRANT EXECUTE ON FUNCTION pg_temp.observe(text,text) TO tally_app, tally_core;
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000a24b1', true);

SET LOCAL ROLE tally_app;
SELECT pg_temp.observe('provider receipt: expect 25000', $q$
INSERT INTO public.suspense_receipts(id,tenant_id,receipt_number,amount,received_on,channel,source_system,provider_transaction_id,recorded_by)
VALUES(pg_temp.k('01'),pg_temp.t1(),'iso-receipt',100,'2026-03-02','api','stripe_webhook','codex-iso',pg_temp.op())$q$);
SELECT pg_temp.observe('ordinary provider payment: expect 25000', $q$
INSERT INTO public.payments(id,tenant_id,payment_number,customer_id,payment_date,amount,payment_method,channel,source_system,provider_transaction_id)
VALUES(pg_temp.k('11'),pg_temp.t1(),'iso-payment',pg_temp.k('c1'),'2026-03-02',100,'online','api','stripe_webhook','codex-iso-payment')$q$);
INSERT INTO public.payments(id,tenant_id,payment_number,customer_id,payment_date,amount,payment_method,channel,source_system)
VALUES(pg_temp.k('12'),pg_temp.t1(),'late-iso',pg_temp.k('c1'),'2026-03-02',100,'online','api','stripe_webhook');
SELECT pg_temp.observe('late provider assignment: expect 25000', $q$
UPDATE public.payments SET provider_transaction_id='codex-iso-late' WHERE id=pg_temp.k('12')$q$);

RESET ROLE;
ROLLBACK;
