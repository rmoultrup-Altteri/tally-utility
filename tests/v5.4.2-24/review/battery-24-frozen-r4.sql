-- ============================================================================
-- BATTERY v5.4.2-24 — unmatched cash and agency pledges (2026-11-07)
-- Run: psql -U tally -d <db-with-patch> -v ON_ERROR_STOP=1 -f battery-24.sql
-- One transaction, rolled back. Fixtures as the owner; every guard the
-- application meets is exercised as tally_app under app.user_id.
-- Requirements: application/wave2-build-2026-10-15/v5.4.2-24-design.md.
-- Ids: 00000000-0000-4000-8000-0000000a24xx (k()).
--
--   U  the receipt              C  candidates
--   P  a receipt becomes payments (reason, evidence, the cap)
--   X  dispositions (returned, bank-returned, escheated, undo; the cap)
--   A  agencies and agreements
--   L  pledges (pay-by, events, payments naming them, the reader)
--   G  where a refund of agency money goes (Ryan, 2026-11-07)
--   S  settings and the suspense readers
--   Y  the retired program type
--   D  the freeze               T  tenants          I  invariants
-- Two writers racing one receipt or one pledge are in races/suspense-24.sh.
-- ============================================================================
BEGIN;

CREATE FUNCTION pg_temp.refuses_at(p_label text, p_sql text, p_state text, p_guard text) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE v_con text;
BEGIN
  BEGIN
    EXECUTE p_sql;
  EXCEPTION WHEN OTHERS THEN
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

-- ============================================================== U the receipt
SET ROLE tally_app;
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000a24b1', true);
SELECT pg_temp.admits('U1 a check no one can match is recorded (CI-053: the money has a row)',
  $q$SELECT pg_temp.rcpt(pg_temp.k('01'), 100, DATE '2026-03-02')$q$);
SELECT pg_temp.ok('U1b it holds all 100 and is on no customer''s ledger (it is not receivable)',
  pg_temp.held(pg_temp.k('01')) = 100
  AND NOT EXISTS (SELECT 1 FROM public.account_ledger WHERE reference_id = pg_temp.k('01')));
SELECT pg_temp.ok('U1c the database stamps created_at (now), whatever the app sent',
  (SELECT created_at = now() FROM public.suspense_receipts WHERE id = pg_temp.k('01')));
SELECT pg_temp.refuses_at('U2 a receipt with no evidence at all (blank, a tab and a no-break space)',
  $q$INSERT INTO public.suspense_receipts (tenant_id, receipt_number, amount, received_on, channel, source_system, payer_name, check_number, recorded_by)
     VALUES (pg_temp.t1(), 'R24-U2', 5, DATE '2026-03-02', 'mail', 'internal', E'\t', E' ', pg_temp.op())$q$,
  '23514', 'suspense_receipts_evidence_check');
SELECT pg_temp.refuses_at('U3 a receipt of no money',
  $q$INSERT INTO public.suspense_receipts (tenant_id, receipt_number, amount, received_on, channel, source_system, check_number, recorded_by)
     VALUES (pg_temp.t1(), 'R24-U3', 0, DATE '2026-03-02', 'mail', 'internal', '1', pg_temp.op())$q$,
  '23514', 'suspense_receipts_amount_check');
SELECT pg_temp.refuses_at('U3b nor of NaN (NaN exceeds every number: r3, Codex r2 probe 07)',
  $q$INSERT INTO public.suspense_receipts (tenant_id, receipt_number, amount, received_on, channel, source_system, check_number, recorded_by)
     VALUES (pg_temp.t1(), 'R24-U3b', 'NaN', DATE '2026-03-02', 'mail', 'internal', '1', pg_temp.op())$q$,
  '23514', 'suspense_receipts_amount_check');
SELECT pg_temp.refuses_at('U4 a receipt dated after today (UTC+14)',
  $q$INSERT INTO public.suspense_receipts (tenant_id, receipt_number, amount, received_on, channel, source_system, check_number, recorded_by)
     VALUES (pg_temp.t1(), 'R24-U4', 5, (now() AT TIME ZONE 'Etc/GMT-14')::date + 1, 'mail', 'internal', '1', pg_temp.op())$q$,
  '23514', 'no later than today');
SELECT pg_temp.refuses_at('U5 a receipt names who recorded it',
  $q$INSERT INTO public.suspense_receipts (tenant_id, receipt_number, amount, received_on, channel, source_system, check_number)
     VALUES (pg_temp.t1(), 'R24-U5', 5, DATE '2026-03-02', 'mail', 'internal', '1')$q$,
  '23502', 'recorded_by');
SELECT pg_temp.refuses_at('U6 a receipt is never edited',
  $q$UPDATE public.suspense_receipts SET amount = 90 WHERE id = pg_temp.k('01')$q$,
  '42501', 'suspense_receipts');
SELECT pg_temp.refuses_at('U6b nor deleted',
  $q$DELETE FROM public.suspense_receipts WHERE id = pg_temp.k('01')$q$,
  '42501', 'suspense_receipts');
SELECT pg_temp.refuses_at('U7 a receipt number is used once per tenant',
  $q$INSERT INTO public.suspense_receipts (tenant_id, receipt_number, amount, received_on, channel, source_system, check_number, recorded_by)
     VALUES (pg_temp.t1(), 'R24-' || right(pg_temp.k('01')::text, 4), 5, DATE '2026-03-02', 'mail', 'internal', '1', pg_temp.op())$q$,
  '23505', 'suspense_receipts_tenant_number_key');
-- The provider's transaction id: once across receipts and payments (CI-055).
INSERT INTO public.suspense_receipts (id, tenant_id, receipt_number, amount, received_on, channel, source_system, provider_transaction_id, recorded_by)
VALUES (pg_temp.k('02'), pg_temp.t1(), 'R24-0002', 40, DATE '2026-03-02', 'api', 'stripe_webhook', 'pi_24_dup', pg_temp.op());
SELECT pg_temp.refuses_at('U8 a second receipt of the same provider transaction',
  $q$INSERT INTO public.suspense_receipts (tenant_id, receipt_number, amount, received_on, channel, source_system, provider_transaction_id, recorded_by)
     VALUES (pg_temp.t1(), 'R24-U8', 40, DATE '2026-03-02', 'api', 'stripe_webhook', 'pi_24_dup', pg_temp.op())$q$,
  '23505', 'provider transaction');
SELECT pg_temp.refuses_at('U8b a payment of a transaction already held as a receipt',
  $q$INSERT INTO public.payments (tenant_id, payment_number, customer_id, payment_date, amount, payment_method, channel, source_system, provider_transaction_id)
     VALUES (pg_temp.t1(), 'P24-U8b', '00000000-0000-4000-8000-0000000a24c1', DATE '2026-03-02', 40, 'online', 'api', 'stripe_webhook', 'pi_24_dup')$q$,
  '23505', 'provider transaction');
INSERT INTO public.payments (id, tenant_id, payment_number, customer_id, payment_date, amount, payment_method, channel, source_system, provider_transaction_id)
VALUES (pg_temp.k('03'), pg_temp.t1(), 'P24-0003', :c1, DATE '2026-03-02', 15, 'online', 'api', 'stripe_webhook', 'pi_24_paid');
SELECT pg_temp.refuses_at('U8c a receipt of a transaction already a payment',
  $q$INSERT INTO public.suspense_receipts (tenant_id, receipt_number, amount, received_on, channel, source_system, provider_transaction_id, recorded_by)
     VALUES (pg_temp.t1(), 'R24-U8c', 15, DATE '2026-03-02', 'api', 'stripe_webhook', 'pi_24_paid', pg_temp.op())$q$,
  '23505', 'provider transaction');
SELECT pg_temp.admits('U8d the same id from another source system is another transaction',
  $q$INSERT INTO public.suspense_receipts (tenant_id, receipt_number, amount, received_on, channel, source_system, provider_transaction_id, recorded_by)
     VALUES (pg_temp.t1(), 'R24-U8d', 15, DATE '2026-03-02', 'api', 'paymentus_webhook', 'pi_24_paid', pg_temp.op())$q$);
SELECT pg_temp.refuses_at('U8f a payment sharing a receipt''s uuid is still a second recording of its transaction (Codex B2)',
  $q$INSERT INTO public.payments (id, tenant_id, payment_number, customer_id, payment_date, amount, payment_method, channel, source_system, provider_transaction_id)
     VALUES (pg_temp.k('02'), pg_temp.t1(), 'P24-U8f', '00000000-0000-4000-8000-0000000a24c1', DATE '2026-03-02', 40, 'online', 'api', 'stripe_webhook', 'pi_24_dup')$q$,
  '23505', 'provider transaction');
SELECT pg_temp.refuses_at('U8g and a receipt sharing a payment''s uuid',
  $q$INSERT INTO public.suspense_receipts (id, tenant_id, receipt_number, amount, received_on, channel, source_system, provider_transaction_id, recorded_by)
     VALUES (pg_temp.k('03'), pg_temp.t1(), 'R24-U8g', 15, DATE '2026-03-02', 'api', 'stripe_webhook', 'pi_24_paid', pg_temp.op())$q$,
  '23505', 'provider transaction');
INSERT INTO public.payments (id, tenant_id, payment_number, customer_id, payment_date, amount, payment_method, channel, source_system)
VALUES (pg_temp.k('0a'), pg_temp.t1(), 'P24-000a', :c1, DATE '2026-03-02', 40, 'online', 'api', 'stripe_webhook');
SELECT pg_temp.refuses_at('U8h a payment given a receipt''s transaction id later (Codex B1, Fable B2)',
  $q$UPDATE public.payments SET provider_transaction_id = 'pi_24_dup' WHERE id = pg_temp.k('0a')$q$,
  '23505', 'provider transaction');
SELECT pg_temp.admits('U8e and a receipt of a transaction id another source system''s receipt holds',
  $q$INSERT INTO public.suspense_receipts (tenant_id, receipt_number, amount, received_on, channel, source_system, provider_transaction_id, recorded_by)
     VALUES (pg_temp.t1(), 'R24-U8e', 5, DATE '2026-03-02', 'api', 'other_webhook', 'pi_24_dup', pg_temp.op())$q$);
SELECT pg_temp.refuses_at('U9 the channel and source system are the payments'' vocabularies',
  $q$INSERT INTO public.suspense_receipts (tenant_id, receipt_number, amount, received_on, channel, source_system, check_number, recorded_by)
     VALUES (pg_temp.t1(), 'R24-U9', 5, DATE '2026-03-02', 'carrier_pigeon', 'internal', '1', pg_temp.op())$q$,
  '23514', 'suspense_receipts_channel_check');

-- ============================================================== C candidates
SELECT pg_temp.admits('C1 intake thought it might be C1 (0.62) or C2 (0.58)',
  $q$INSERT INTO public.suspense_receipt_candidates (tenant_id, suspense_receipt_id, customer_id, basis, confidence)
     VALUES (pg_temp.t1(), pg_temp.k('01'), '00000000-0000-4000-8000-0000000a24c1', 'intake_match', 0.62),
            (pg_temp.t1(), pg_temp.k('01'), '00000000-0000-4000-8000-0000000a24c2', 'intake_match', 0.58)$q$);
SELECT pg_temp.ok('C1b a candidate moves no money: the receipt still holds 100, no payment exists for it',
  pg_temp.held(pg_temp.k('01')) = 100 AND NOT EXISTS (SELECT 1 FROM public.payments WHERE suspense_receipt_id = pg_temp.k('01')));
SELECT pg_temp.refuses_at('C2 a confidence is between 0 and 1',
  $q$INSERT INTO public.suspense_receipt_candidates (tenant_id, suspense_receipt_id, customer_id, basis, confidence)
     VALUES (pg_temp.t1(), pg_temp.k('01'), '00000000-0000-4000-8000-0000000a24c3', 'intake_match', 1.5)$q$,
  '23514', 'suspense_receipt_candidates_confidence_check');
SELECT pg_temp.refuses_at('C3 an operator''s candidate names the operator',
  $q$INSERT INTO public.suspense_receipt_candidates (tenant_id, suspense_receipt_id, customer_id, basis)
     VALUES (pg_temp.t1(), pg_temp.k('01'), '00000000-0000-4000-8000-0000000a24c3', 'operator')$q$,
  '23514', 'suspense_receipt_candidates_operator_check');
SELECT pg_temp.refuses_at('C4 a candidate of another tenant''s customer (T2''s C9)',
  $q$INSERT INTO public.suspense_receipt_candidates (tenant_id, suspense_receipt_id, customer_id, basis, confidence)
     VALUES (pg_temp.t1(), pg_temp.k('01'), '00000000-0000-4000-8000-0000000a24c9', 'intake_match', 0.5)$q$,
  '23503', 'suspense_receipt_candidates_customer_fkey');
SELECT pg_temp.refuses_at('C5 candidates are never edited',
  $q$UPDATE public.suspense_receipt_candidates SET confidence = 0.99 WHERE suspense_receipt_id = pg_temp.k('01')$q$,
  '42501', 'suspense_receipt_candidates');

-- ============================================================== P a receipt becomes payments
-- R1 (01), 100 on 03-02: 60 to C1 (P 11), 40 to C2 (P 12).
SELECT pg_temp.admits('P1 60 of R1 becomes C1''s payment, with the reason and the operator',
  $q$SELECT pg_temp.fromr(pg_temp.k('11'), pg_temp.k('81'), pg_temp.k('01'), '00000000-0000-4000-8000-0000000a24c1', 60)$q$);
SELECT pg_temp.ok('P1b R1 holds 40; C1''s payment reads 60 received',
  pg_temp.held(pg_temp.k('01')) = 40
  AND (SELECT received = 60 FROM public.payment_position_as_of(pg_temp.k('11'), DATE '2026-12-31', clock_timestamp())));
SELECT pg_temp.refuses_at('P2 41 more is past what R1 holds',
  $q$SELECT pg_temp.fromr(gen_random_uuid(), gen_random_uuid(), pg_temp.k('01'), '00000000-0000-4000-8000-0000000a24c2', 41)$q$,
  '23514', 'the receipt holds');
SELECT pg_temp.refuses_at('P2b a pending payment counts too (it may yet post)',
  $q$SELECT pg_temp.fromr(pg_temp.k('12'), NULL, pg_temp.k('01'), '00000000-0000-4000-8000-0000000a24c2', 40, false);
     SELECT pg_temp.fromr(gen_random_uuid(), NULL, pg_temp.k('01'), '00000000-0000-4000-8000-0000000a24c3', 0.01, false)$q$,
  '23514', 'the receipt holds');
SELECT pg_temp.refuses_at('P3 a resolution says why',
  $q$INSERT INTO public.payments (tenant_id, payment_number, customer_id, payment_date, amount, payment_method, channel, source_system, check_number,
                                  suspense_receipt_id, suspense_resolved_by)
     SELECT pg_temp.t1(), 'P24-P3', '00000000-0000-4000-8000-0000000a24c2', r.received_on, 1, 'check', r.channel, r.source_system, r.check_number, r.id, pg_temp.op()
       FROM public.suspense_receipts r WHERE r.id = pg_temp.k('01')$q$,
  '23514', 'payments_suspense_resolution_check');
SELECT pg_temp.refuses_at('P3a and who',
  $q$INSERT INTO public.payments (tenant_id, payment_number, customer_id, payment_date, amount, payment_method, channel, source_system, check_number,
                                  suspense_receipt_id, suspense_resolution_reason)
     SELECT pg_temp.t1(), 'P24-P3a', '00000000-0000-4000-8000-0000000a24c2', r.received_on, 1, 'check', r.channel, r.source_system, r.check_number, r.id, 'identified'
       FROM public.suspense_receipts r WHERE r.id = pg_temp.k('01')$q$,
  '23514', 'payments_suspense_resolution_check');
SELECT pg_temp.refuses_at('P3b a reason of blanks is no reason',
  $q$INSERT INTO public.payments (tenant_id, payment_number, customer_id, payment_date, amount, payment_method, channel, source_system, check_number,
                                  suspense_receipt_id, suspense_resolution_reason, suspense_resolved_by)
     SELECT pg_temp.t1(), 'P24-P3b', '00000000-0000-4000-8000-0000000a24c2', r.received_on, 1, 'check', r.channel, r.source_system, r.check_number, r.id, E' \t', pg_temp.op()
       FROM public.suspense_receipts r WHERE r.id = pg_temp.k('01')$q$,
  '23514', 'payments_suspense_resolution_check');
SELECT pg_temp.refuses_at('P3c no reason without a receipt',
  $q$INSERT INTO public.payments (tenant_id, payment_number, customer_id, payment_date, amount, payment_method, suspense_resolution_reason, suspense_resolved_by)
     VALUES (pg_temp.t1(), 'P24-P3c', '00000000-0000-4000-8000-0000000a24c2', DATE '2026-03-02', 1, 'check', 'x', pg_temp.op())$q$,
  '23514', 'payments_suspense_resolution_check');
SELECT pg_temp.rcpt(pg_temp.k('04'), 50, DATE '2026-03-03', 'CHK-7777');
SELECT pg_temp.refuses_at('P4 a payment from a receipt is not dated before the money came (R4, 50 on 03-03)',
  $q$SELECT pg_temp.fromr(gen_random_uuid(), NULL, pg_temp.k('04'), '00000000-0000-4000-8000-0000000a24c3', 1, false, NULL, DATE '2026-03-02')$q$,
  '23514', 'on or after the receipt''s received_on');
SELECT pg_temp.refuses_at('P4b nor effective after it (the customer paid by then: CI-058)',
  $q$INSERT INTO public.payments (tenant_id, payment_number, customer_id, payment_date, effective_date, effective_date_method, amount, payment_method, channel, source_system, check_number,
                                  suspense_receipt_id, suspense_resolution_reason, suspense_resolved_by)
     SELECT pg_temp.t1(), 'P24-P4b', '00000000-0000-4000-8000-0000000a24c3', r.received_on + 5, r.received_on + 1, 'lockbox_receipt', 1, 'check', r.channel, r.source_system, r.check_number, r.id, 'x', pg_temp.op()
       FROM public.suspense_receipts r WHERE r.id = pg_temp.k('04')$q$,
  '23514', 'effective no later than');
SELECT pg_temp.refuses_at('P4c nor effective after it when the effective date is written at posting (the helper writes the payment date, 03-08)',
  $q$INSERT INTO public.payments (id, tenant_id, payment_number, customer_id, payment_date, amount, payment_method, channel, source_system, check_number,
                                  suspense_receipt_id, suspense_resolution_reason, suspense_resolved_by)
     SELECT pg_temp.k('1f'), pg_temp.t1(), 'P24-P4c', '00000000-0000-4000-8000-0000000a24c3', r.received_on + 5, 1, 'check', r.channel, r.source_system, r.check_number, r.id, 'x', pg_temp.op()
       FROM public.suspense_receipts r WHERE r.id = pg_temp.k('04');
     SELECT pg_temp.post(pg_temp.k('1f'), gen_random_uuid())$q$,
  '23514', 'effective no later than');
SELECT pg_temp.admits('P4d a postmark before the money came is fine (dated 03-08, effective 03-01 by postmark)',
  $q$INSERT INTO public.payments (tenant_id, payment_number, customer_id, payment_date, effective_date, effective_date_method, amount, payment_method, channel, source_system, check_number,
                                  suspense_receipt_id, suspense_resolution_reason, suspense_resolved_by)
     SELECT pg_temp.t1(), 'P24-P4d', '00000000-0000-4000-8000-0000000a24c3', DATE '2026-03-08', DATE '2026-03-01', 'postmark', 0.01, 'check', r.channel, r.source_system, r.check_number, r.id, 'x', pg_temp.op()
       FROM public.suspense_receipts r WHERE r.id = pg_temp.k('04');
     UPDATE public.payments SET status = 'voided' WHERE payment_number = 'P24-P4d'$q$);
SELECT pg_temp.refuses_at('P5 the payment carries the receipt''s instrument (another check number)',
  $q$INSERT INTO public.payments (tenant_id, payment_number, customer_id, payment_date, amount, payment_method, channel, source_system, check_number,
                                  suspense_receipt_id, suspense_resolution_reason, suspense_resolved_by)
     SELECT pg_temp.t1(), 'P24-P5', '00000000-0000-4000-8000-0000000a24c3', r.received_on, 1, 'check', r.channel, r.source_system, 'CHK-0000', r.id, 'x', pg_temp.op()
       FROM public.suspense_receipts r WHERE r.id = pg_temp.k('04')$q$,
  '23514', 'the receipt''s instrument');
SELECT pg_temp.refuses_at('P5b and its channel',
  $q$INSERT INTO public.payments (tenant_id, payment_number, customer_id, payment_date, amount, payment_method, channel, source_system, check_number,
                                  suspense_receipt_id, suspense_resolution_reason, suspense_resolved_by)
     SELECT pg_temp.t1(), 'P24-P5b', '00000000-0000-4000-8000-0000000a24c3', r.received_on, 1, 'check', 'walk_in', r.source_system, r.check_number, r.id, 'x', pg_temp.op()
       FROM public.suspense_receipts r WHERE r.id = pg_temp.k('04')$q$,
  '23514', 'the receipt''s instrument');
SELECT pg_temp.refuses_at('P5c a payment from a receipt leaves the provider id on the receipt (it is the receipt''s, once)',
  $q$INSERT INTO public.payments (tenant_id, payment_number, customer_id, payment_date, amount, payment_method, channel, source_system, provider_transaction_id,
                                  suspense_receipt_id, suspense_resolution_reason, suspense_resolved_by)
     SELECT pg_temp.t1(), 'P24-P5c', '00000000-0000-4000-8000-0000000a24c3', r.received_on, 1, 'online', r.channel, r.source_system, 'pi_other', r.id, 'x', pg_temp.op()
       FROM public.suspense_receipts r WHERE r.id = pg_temp.k('02')$q$,
  '23514', 'payments_suspense_resolution_check');
SELECT pg_temp.admits('P5d R2 (a Stripe receipt) becomes C3''s payment with no provider id of its own',
  $q$SELECT pg_temp.fromr(pg_temp.k('13'), pg_temp.k('83'), pg_temp.k('02'), '00000000-0000-4000-8000-0000000a24c3', 40)$q$);
SELECT pg_temp.refuses_at('P6 a refund never names a receipt',
  $q$INSERT INTO public.payments (tenant_id, payment_number, customer_id, payment_date, amount, payment_method, refunds_payment_id,
                                  suspense_receipt_id, suspense_resolution_reason, suspense_resolved_by)
     VALUES (pg_temp.t1(), 'P24-P6', '00000000-0000-4000-8000-0000000a24c1', DATE '2026-03-02', -1, 'refund', pg_temp.k('11'), pg_temp.k('04'), 'x', pg_temp.op())$q$,
  '23514', 'payments_suspense_resolution_check');
SELECT pg_temp.refuses_at('P7 a payment''s receipt is written once (here: named after insert)',
  $q$UPDATE public.payments SET suspense_receipt_id = pg_temp.k('04') WHERE id = pg_temp.k('03')$q$,
  '23001', 'written once');
SELECT pg_temp.refuses_at('P7b and its reason never changes',
  $q$UPDATE public.payments SET suspense_resolution_reason = 'another' WHERE id = pg_temp.k('11')$q$,
  '23001', 'written once');
-- P12 (pending, 40 to C2) is voided: it never posted, so R1 gets it back.
UPDATE public.payments SET status = 'voided', status_cause_id = NULL WHERE id = pg_temp.k('12');
SELECT pg_temp.ok('P8 a voided payment gives its share back: R1 holds 40',
  pg_temp.held(pg_temp.k('01')) = 40);
-- R4 (50): 50 to C3 (P 14), posted. It was C4's money: reversed, then 50 to C4 (P 15).
SELECT pg_temp.admits('P8b R4''s 50 to C3 (the voided 0.01 of P4d does not count)',
  $q$SELECT pg_temp.fromr(pg_temp.k('14'), pg_temp.k('84'), pg_temp.k('04'), '00000000-0000-4000-8000-0000000a24c3', 50)$q$);
SELECT pg_temp.refuses_at('P9 while C3''s payment stands, R4 has nothing for C4',
  $q$SELECT pg_temp.fromr(gen_random_uuid(), gen_random_uuid(), pg_temp.k('04'), '00000000-0000-4000-8000-0000000a24c4', 50)$q$,
  '23514', 'the receipt holds');
SELECT pg_temp.unpost(pg_temp.k('14'), pg_temp.k('84'), DATE '2026-03-05');
-- r2 (Codex B3, Opus B1, B2): a reversal alone gives nothing back; the
-- misposting return does, from its own date.
SELECT pg_temp.ok('P9b a reversal alone gives nothing back: R4 still holds 0',
  pg_temp.held(pg_temp.k('04')) = 0);
SELECT pg_temp.refuses_at('P9b2 a misposting return is dated on or after the reversal (03-05)',
  $q$SELECT pg_temp.mret(NULL, pg_temp.k('04'), pg_temp.k('14'), 50, DATE '2026-03-04')$q$,
  '23514', 'on or after its reversal');
SELECT pg_temp.refuses_at('P9b3 it gives back at most what was reversed as misposted (here the whole 50)',
  $q$SELECT pg_temp.mret(NULL, pg_temp.k('04'), pg_temp.k('14'), 50.01, DATE '2026-03-05')$q$,
  '23514', 'at most what payment');
SELECT pg_temp.refuses_at('P9b4 it names a payment of the same receipt (C1''s P11 is R1''s)',
  $q$SELECT pg_temp.mret(NULL, pg_temp.k('04'), pg_temp.k('11'), 1, DATE '2026-03-05')$q$,
  '23514', 'names a payment made from receipt');
SELECT pg_temp.refuses_at('P9b5 and a reversed one (P13 is posted)',
  $q$SELECT pg_temp.mret(NULL, pg_temp.k('02'), pg_temp.k('13'), 1, DATE '2026-03-05')$q$,
  '23514', 'only a payment reversed as posted to the wrong customer');
SELECT pg_temp.admits('P9b6 C3''s 50 goes back to R4 as misposted, on 03-05',
  $q$SELECT pg_temp.mret(pg_temp.k('25'), pg_temp.k('04'), pg_temp.k('14'), 50, DATE '2026-03-05')$q$);
SELECT pg_temp.ok('P9b7 R4 holds 50 from 03-05, and 0 on 03-04 (the money was on C3''s ledger then)',
  pg_temp.held(pg_temp.k('04')) = 50
  AND (SELECT held = 0 FROM public.suspense_receipt_position_as_of(pg_temp.k('04'), DATE '2026-03-04', clock_timestamp())));
SELECT pg_temp.refuses_at('P9b8 once per payment',
  $q$SELECT pg_temp.mret(NULL, pg_temp.k('04'), pg_temp.k('14'), 1, DATE '2026-03-06')$q$,
  '23505', 'suspense_receipt_dispositions_one_return_per_payment');
SELECT pg_temp.refuses_at('P9b9 and the payment takes no bank return code afterwards',
  $q$UPDATE public.payments SET return_code = 'R01' WHERE id = pg_temp.k('14')$q$,
  '23514', 'returned to suspense as misposted');
SELECT pg_temp.refuses_at('P9b10 a misposting return is never undone',
  $q$SELECT pg_temp.disp(NULL, pg_temp.k('04'), 'undo', -1, DATE '2026-03-06', pg_temp.k('25'))$q$,
  '23514', 'an undo names');
SELECT pg_temp.refuses_at('P9c2 the money is not re-posted on a date before it came back (03-04)',
  $q$SELECT pg_temp.fromr(gen_random_uuid(), gen_random_uuid(), pg_temp.k('04'), '00000000-0000-4000-8000-0000000a24c4', 50, true, NULL, DATE '2026-03-04')$q$,
  '23514', 'the receipt holds');
SELECT pg_temp.admits('P9c and the operator posts it to C4, on 03-05',
  $q$SELECT pg_temp.fromr(pg_temp.k('15'), pg_temp.k('85'), pg_temp.k('04'), '00000000-0000-4000-8000-0000000a24c4', 50, true, NULL, DATE '2026-03-05')$q$);
SELECT pg_temp.ok('P9d R4 holds 0; C4 received 50, C3 nothing',
  pg_temp.held(pg_temp.k('04')) = 0
  AND (SELECT received = 50 FROM public.payment_position_as_of(pg_temp.k('15'), DATE '2026-12-31', clock_timestamp()))
  AND (SELECT received = 0 FROM public.payment_position_as_of(pg_temp.k('14'), DATE '2026-12-31', clock_timestamp())));
-- P9e (the receipt as known before the misposting return) needs two transactions: races/suspense-24.sh SU6.
-- C4's payment bounces: the bank took the money back; R4 does not get it.
SELECT pg_temp.bounce(pg_temp.k('15'), pg_temp.k('85'), DATE '2026-03-09');
SELECT pg_temp.ok('P10 an NSF payment keeps its share counted: R4 still holds 0',
  pg_temp.held(pg_temp.k('04')) = 0);
SELECT pg_temp.refuses_at('P10b so nothing more can be made from it',
  $q$SELECT pg_temp.fromr(gen_random_uuid(), gen_random_uuid(), pg_temp.k('04'), '00000000-0000-4000-8000-0000000a24c4', 0.01)$q$,
  '23514', 'the receipt holds');
-- r2 (Codex B3, Opus B1): R9 (09), 100 on 03-10, all to C1 (P19); the bank
-- takes it back, recorded as reversed with R10. The money is gone.
SELECT pg_temp.rcpt(pg_temp.k('09'), 100, DATE '2026-03-10');
SELECT pg_temp.fromr(pg_temp.k('19'), pg_temp.k('89'), pg_temp.k('09'), :c1, 100);
INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reference_type, reference_id, reverses_ledger_entry_id, reversal_reason)
VALUES (pg_temp.k('8a'), pg_temp.t1(), :c1, DATE '2026-03-12', 'adjustment', 'ACH return', 100, 'payment', pg_temp.k('19'), pg_temp.k('89'), 'ACH return R10');
UPDATE public.payments SET status = 'reversed', reversed_at = now(), reversed_by = pg_temp.op(), reversed_reason = 'ACH return', return_code = 'R10', status_cause_id = pg_temp.k('8a')
 WHERE id = pg_temp.k('19');
SELECT pg_temp.ok('P12 a bank''s take-back recorded as reversed (R10) gives nothing back: R9 holds 0',
  pg_temp.held(pg_temp.k('09')) = 0);
SELECT pg_temp.refuses_at('P12b no misposting return for it',
  $q$SELECT pg_temp.mret(NULL, pg_temp.k('09'), pg_temp.k('19'), 100, DATE '2026-03-12')$q$,
  '23514', 'a bank''s take-back keeps it spent');
SELECT pg_temp.refuses_at('P12c so the 100 cannot go to another customer',
  $q$SELECT pg_temp.fromr(gen_random_uuid(), gen_random_uuid(), pg_temp.k('09'), '00000000-0000-4000-8000-0000000a24c2', 100, true, NULL, DATE '2026-03-13')$q$,
  '23514', 'the receipt holds');
SELECT pg_temp.refuses_at('P12d nor back to the sender',
  $q$SELECT pg_temp.disp(NULL, pg_temp.k('09'), 'returned_to_sender', 100, DATE '2026-03-13')$q$,
  '23514', 'the receipt holds');
-- r3 (Codex r2 probe 01): R11 (0c), 100 to C1 (P1a); the bank takes back 40
-- (nsf row), the other 60 is reversed as misposted. Only 60 comes back.
SELECT pg_temp.rcpt(pg_temp.k('0c'), 100, DATE '2026-03-10');
SELECT pg_temp.fromr(pg_temp.k('1a'), pg_temp.k('8b'), pg_temp.k('0c'), :c1, 100);
INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reference_type, reference_id, reverses_ledger_entry_id)
VALUES (pg_temp.k('8c'), pg_temp.t1(), :c1, DATE '2026-03-11', 'nsf', 'bank took back 40', 40, 'payment', pg_temp.k('1a'), pg_temp.k('8b'));
INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reference_type, reference_id, reverses_ledger_entry_id, reversal_reason)
VALUES (pg_temp.k('8d'), pg_temp.t1(), :c1, DATE '2026-03-12', 'adjustment', 'remaining 60 misposted', 60, 'payment', pg_temp.k('1a'), pg_temp.k('8b'), 'remaining 60 misposted');
UPDATE public.payments SET status = 'reversed', reversed_at = now(), reversed_by = pg_temp.op(), reversed_reason = 'remaining 60 misposted', status_cause_id = pg_temp.k('8d')
 WHERE id = pg_temp.k('1a');
SELECT pg_temp.refuses_at('P13 a misposting return gives back only what was reversed as misposted (60 of 100; the bank took 40)',
  $q$SELECT pg_temp.mret(NULL, pg_temp.k('0c'), pg_temp.k('1a'), 100, DATE '2026-03-12')$q$,
  '23514', 'at most what payment');
SELECT pg_temp.admits('P13b the 60 comes back',
  $q$SELECT pg_temp.mret(NULL, pg_temp.k('0c'), pg_temp.k('1a'), 60, DATE '2026-03-12')$q$);
SELECT pg_temp.ok('P13c R11 holds 60', pg_temp.held(pg_temp.k('0c')) = 60);
-- r4 (Opus r3 B1, Fable r3 B1): the misposted share nets each reversal's own
-- tree. R16 (10): 100 to C1 (P1c); a reversal +100 (f0), its own reversal
-- -100 (f1), a second reversal +100 (f2): 100 reversed as misposted, not 200.
SELECT pg_temp.rcpt(pg_temp.k('10'), 100, DATE '2026-03-10');
SELECT pg_temp.fromr(pg_temp.k('1c'), pg_temp.k('f3'), pg_temp.k('10'), :c1, 100);
INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reference_type, reference_id, reverses_ledger_entry_id, reversal_reason)
VALUES (pg_temp.k('f0'), pg_temp.t1(), :c1, DATE '2026-03-11', 'adjustment', 'misposted', 100, 'payment', pg_temp.k('1c'), pg_temp.k('f3'), 'misposted');
INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reference_type, reference_id, reverses_ledger_entry_id, reversal_reason)
VALUES (pg_temp.k('f1'), pg_temp.t1(), :c1, DATE '2026-03-12', 'adjustment', 'reversal entered in error', -100, 'payment', pg_temp.k('1c'), pg_temp.k('f0'), 'reversal entered in error');
INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reference_type, reference_id, reverses_ledger_entry_id, reversal_reason)
VALUES (pg_temp.k('f2'), pg_temp.t1(), :c1, DATE '2026-03-13', 'adjustment', 'misposted after all', 100, 'payment', pg_temp.k('1c'), pg_temp.k('f3'), 'misposted after all');
UPDATE public.payments SET status = 'reversed', reversed_at = now(), reversed_by = pg_temp.op(), reversed_reason = 'misposted', status_cause_id = pg_temp.k('f2') WHERE id = pg_temp.k('1c');
SELECT pg_temp.refuses_at('P14a a reversal entered, undone and entered again gives back 100, not 200 (Opus r3 B1, Fable r3 B1)',
  $q$SELECT pg_temp.mret(NULL, pg_temp.k('10'), pg_temp.k('1c'), 100.01, DATE '2026-03-13')$q$,
  '23514', 'at most what payment');
SELECT pg_temp.admits('P14a2 100 comes back',
  $q$SELECT pg_temp.mret(NULL, pg_temp.k('10'), pg_temp.k('1c'), 100, DATE '2026-03-13')$q$);
-- R17 (11): 100 to C1 (P1d); a reversal +100 (f4) undone (f5), then the
-- bank takes all 100 back (96, nsf): nothing was misposted.
SELECT pg_temp.rcpt(pg_temp.k('11'), 100, DATE '2026-03-10');
SELECT pg_temp.fromr(pg_temp.k('1d'), pg_temp.k('f7'), pg_temp.k('11'), :c1, 100);
INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reference_type, reference_id, reverses_ledger_entry_id, reversal_reason)
VALUES (pg_temp.k('f4'), pg_temp.t1(), :c1, DATE '2026-03-11', 'adjustment', 'misposted', 100, 'payment', pg_temp.k('1d'), pg_temp.k('f7'), 'misposted');
INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reference_type, reference_id, reverses_ledger_entry_id, reversal_reason)
VALUES (pg_temp.k('f5'), pg_temp.t1(), :c1, DATE '2026-03-12', 'adjustment', 'reversal entered in error', -100, 'payment', pg_temp.k('1d'), pg_temp.k('f4'), 'reversal entered in error');
INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reference_type, reference_id, reverses_ledger_entry_id)
VALUES (pg_temp.k('f6'), pg_temp.t1(), :c1, DATE '2026-03-13', 'nsf', 'returned', 100, 'payment', pg_temp.k('1d'), pg_temp.k('f7'));
UPDATE public.payments SET status = 'reversed', reversed_at = now(), reversed_by = pg_temp.op(), reversed_reason = 'bank return entered as a reversal', status_cause_id = pg_temp.k('f4') WHERE id = pg_temp.k('1d');
SELECT pg_temp.refuses_at('P14b a reversal undone, then the bank''s take-back: nothing comes back (Opus r3 B1)',
  $q$SELECT pg_temp.mret(NULL, pg_temp.k('11'), pg_temp.k('1d'), 0.01, DATE '2026-03-13')$q$,
  '23514', 'at most what payment');
-- r2 (Codex B1): a receipt's payment keeps the receipt's instrument after insert.
SELECT pg_temp.refuses_at('P5e a receipt''s payment takes no bank name of its own later (R1 has none)',
  $q$UPDATE public.payments SET check_bank_name = 'Different bank' WHERE id = pg_temp.k('11')$q$,
  '23514', 'at insert and after');
SELECT pg_temp.refuses_at('P11 a receipt of another tenant (T2''s operator naming T1''s R1)',
  $q$SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000a24b2', true);
     INSERT INTO public.payments (tenant_id, payment_number, customer_id, payment_date, amount, payment_method, check_number,
                                  suspense_receipt_id, suspense_resolution_reason, suspense_resolved_by)
     VALUES (pg_temp.t2(), 'P24-P11', '00000000-0000-4000-8000-0000000a24c9', DATE '2026-03-02', 1, 'check', 'CHK-a201', pg_temp.k('01'), 'x', '00000000-0000-4000-8000-0000000a24b2')$q$,
  '23503', 'payments_suspense_receipt_fkey');

-- ============================================================== X dispositions
-- R1 holds 40. 25 goes back to the sender on 04-01.
SELECT pg_temp.admits('X1 25 of R1 goes back to whoever sent it (CI-053)',
  $q$SELECT pg_temp.disp(pg_temp.k('21'), pg_temp.k('01'), 'returned_to_sender', 25, DATE '2026-04-01')$q$);
SELECT pg_temp.ok('X1b R1 holds 15', pg_temp.held(pg_temp.k('01')) = 15);
SELECT pg_temp.ok('X1c as of 03-31 R1 held 40 (a disposition counts from its date)',
  (SELECT held = 40 FROM public.suspense_receipt_position_as_of(pg_temp.k('01'), DATE '2026-03-31', clock_timestamp())));
SELECT pg_temp.refuses_at('X2 15.01 more is past what R1 holds',
  $q$SELECT pg_temp.disp(NULL, pg_temp.k('01'), 'escheated', 15.01, DATE '2026-09-01')$q$,
  '23514', 'the receipt holds');
SELECT pg_temp.refuses_at('X3 a return names its outgoing instrument',
  $q$INSERT INTO public.suspense_receipt_dispositions (tenant_id, suspense_receipt_id, kind, amount, disposed_on, reason, recorded_by)
     VALUES (pg_temp.t1(), pg_temp.k('01'), 'returned_to_sender', 1, DATE '2026-04-02', 'x', pg_temp.op())$q$,
  '23514', 'suspense_receipt_dispositions_kind_check');
SELECT pg_temp.refuses_at('X3b an escheat names the state and the report',
  $q$INSERT INTO public.suspense_receipt_dispositions (tenant_id, suspense_receipt_id, kind, amount, disposed_on, jurisdiction, reason, recorded_by)
     VALUES (pg_temp.t1(), pg_temp.k('01'), 'escheated', 1, DATE '2026-04-02', 'TX', 'x', pg_temp.op())$q$,
  '23514', 'suspense_receipt_dispositions_kind_check');
SELECT pg_temp.refuses_at('X3c a bank return''s code is an R-code',
  $q$INSERT INTO public.suspense_receipt_dispositions (tenant_id, suspense_receipt_id, kind, amount, disposed_on, return_code, reason, recorded_by)
     VALUES (pg_temp.t1(), pg_temp.k('01'), 'bank_returned', 1, DATE '2026-04-02', 'NSF', 'x', pg_temp.op())$q$,
  '23514', 'suspense_receipt_dispositions_kind_check');
SELECT pg_temp.refuses_at('X3d every disposition says why',
  $q$INSERT INTO public.suspense_receipt_dispositions (tenant_id, suspense_receipt_id, kind, amount, disposed_on, return_code, recorded_by)
     VALUES (pg_temp.t1(), pg_temp.k('01'), 'bank_returned', 1, DATE '2026-04-02', 'R01', pg_temp.op())$q$,
  '23514', 'suspense_receipt_dispositions_reason_check');
SELECT pg_temp.refuses_at('X4 a disposition before the money came',
  $q$SELECT pg_temp.disp(NULL, pg_temp.k('01'), 'bank_returned', 1, DATE '2026-03-01')$q$,
  '23514', 'on or after the receipt');
SELECT pg_temp.refuses_at('X4b nor after today (UTC+14)',
  $q$SELECT pg_temp.disp(NULL, pg_temp.k('01'), 'bank_returned', 1, (now() AT TIME ZONE 'Etc/GMT-14')::date + 1)$q$,
  '23514', 'no later than today');
SELECT pg_temp.refuses_at('X5b a disposition of NaN',
  $q$SELECT pg_temp.disp(NULL, pg_temp.k('01'), 'bank_returned', 'NaN', DATE '2026-04-02')$q$,
  '23514', 'suspense_receipt_dispositions_undo_check');
SELECT pg_temp.refuses_at('X5 a non-undo moves money out (a positive amount)',
  $q$SELECT pg_temp.disp(NULL, pg_temp.k('01'), 'bank_returned', -1, DATE '2026-04-02')$q$,
  '23514', 'suspense_receipt_dispositions_undo_check');
-- The refund check comes back uncashed on 04-20: the return is undone.
SELECT pg_temp.refuses_at('X6 an undo is dated on or after what it undoes',
  $q$SELECT pg_temp.disp(NULL, pg_temp.k('01'), 'undo', -25, DATE '2026-03-31', pg_temp.k('21'))$q$,
  '23514', 'an undo is dated on or after');
SELECT pg_temp.refuses_at('X6b an undo takes back at most what it undoes',
  $q$SELECT pg_temp.disp(NULL, pg_temp.k('01'), 'undo', -25.01, DATE '2026-04-20', pg_temp.k('21'))$q$,
  '23514', 'undos would come to');
SELECT pg_temp.refuses_at('X6c an undo names a disposition of the same receipt',
  $q$SELECT pg_temp.disp(NULL, pg_temp.k('04'), 'undo', -1, DATE '2026-04-20', pg_temp.k('21'))$q$,
  '23503', 'suspense_receipt_dispositions_undoes_fkey');
SELECT pg_temp.refuses_at('X6d an undo names what it undoes',
  $q$INSERT INTO public.suspense_receipt_dispositions (tenant_id, suspense_receipt_id, kind, amount, disposed_on, reason, recorded_by)
     VALUES (pg_temp.t1(), pg_temp.k('01'), 'undo', -1, DATE '2026-04-20', 'x', pg_temp.op())$q$,
  '23514', 'suspense_receipt_dispositions_undo_check');
SELECT pg_temp.admits('X6e the return is undone on 04-20',
  $q$SELECT pg_temp.disp(pg_temp.k('22'), pg_temp.k('01'), 'undo', -25, DATE '2026-04-20', pg_temp.k('21'))$q$);
SELECT pg_temp.ok('X6f R1 holds 40 again from 04-20; on 04-19 it held 15',
  pg_temp.held(pg_temp.k('01')) = 40
  AND (SELECT held = 15 FROM public.suspense_receipt_position_as_of(pg_temp.k('01'), DATE '2026-04-19', clock_timestamp())));
SELECT pg_temp.refuses_at('X6g an undo is never undone',
  $q$SELECT pg_temp.disp(NULL, pg_temp.k('01'), 'undo', -1, DATE '2026-04-21', pg_temp.k('22'))$q$,
  '23514', 'an undo names');
-- The cap reads the worst day: 40 went out from 04-01 to 04-20 as 25, and
-- the 40 now held may not be spent as if the 25 had never left.
SELECT pg_temp.refuses_at('X7 a payment of 40 counts from 03-02, when 25 was also out on 04-01 (40 + 25 > 50 held then)',
  $q$SELECT pg_temp.fromr(gen_random_uuid(), gen_random_uuid(), pg_temp.k('01'), '00000000-0000-4000-8000-0000000a24c2', 40)$q$,
  '23514', 'the receipt holds');
SELECT pg_temp.admits('X7b 15 is what R1 held on its worst day: 15 to C2',
  $q$SELECT pg_temp.fromr(pg_temp.k('16'), pg_temp.k('86'), pg_temp.k('01'), '00000000-0000-4000-8000-0000000a24c2', 15)$q$);
SELECT pg_temp.admits('X8 the 25 left is reported as unclaimed property (Texas, owner unknown)',
  $q$SELECT pg_temp.disp(pg_temp.k('23'), pg_temp.k('01'), 'escheated', 25, DATE '2026-09-01')$q$);
SELECT pg_temp.ok('X8b R1 holds 0: 60 + 15 to payments, 25 escheated',
  (SELECT held = 0 AND to_payments = 75 AND disposed = 25 FROM public.suspense_receipt_position_as_of(pg_temp.k('01'), DATE '2026-12-31', clock_timestamp())));
SELECT pg_temp.refuses_at('X9 dispositions are never edited',
  $q$UPDATE public.suspense_receipt_dispositions SET amount = 1 WHERE id = pg_temp.k('23')$q$,
  '42501', 'suspense_receipt_dispositions');
-- R5 (05), 30: the check bounces while still in suspense.
SELECT pg_temp.rcpt(pg_temp.k('05'), 30, DATE '2026-03-04');
SELECT pg_temp.admits('X10 the bank takes back R5''s 30',
  $q$SELECT pg_temp.disp(pg_temp.k('24'), pg_temp.k('05'), 'bank_returned', 30, DATE '2026-03-06')$q$);
SELECT pg_temp.ok('X10b R5 holds 0', pg_temp.held(pg_temp.k('05')) = 0);

-- ============================================================== A agencies and agreements
SELECT pg_temp.admits('A1 an agency (the local CEAP provider)',
  $q$INSERT INTO public.assistance_agencies (id, tenant_id, name, program_kind, recorded_by)
     VALUES (pg_temp.k('41'), pg_temp.t1(), 'Brazos Valley Community Action', 'liheap_ceap', pg_temp.op()),
            (pg_temp.k('42'), pg_temp.t1(), 'St. Vincent de Paul', 'charity', pg_temp.op())$q$);
SELECT pg_temp.refuses_at('A1b an agency''s name is used once per tenant',
  $q$INSERT INTO public.assistance_agencies (tenant_id, name, program_kind, recorded_by)
     VALUES (pg_temp.t1(), 'St. Vincent de Paul', 'charity', pg_temp.op())$q$,
  '23505', 'assistance_agencies_tenant_name_key');
SELECT pg_temp.refuses_at('A1c the program kinds are a fixed list',
  $q$INSERT INTO public.assistance_agencies (tenant_id, name, program_kind, recorded_by)
     VALUES (pg_temp.t1(), 'Uncle Bob', 'relative', pg_temp.op())$q$,
  '23514', 'assistance_agencies_program_kind_check');
SELECT pg_temp.admits('A2 the CEAP agreement from 2026-01-01: 45 days to pay a pledge, 5 business days of eligibility hold (VA-26)',
  $q$INSERT INTO public.assistance_agency_agreements (id, tenant_id, agency_id, effective_from, pledge_payment_days, eligibility_hold_business_days, source_reference, recorded_by)
     VALUES (pg_temp.k('43'), pg_temp.t1(), pg_temp.k('41'), DATE '2026-01-01', 45, 5, 'TDHCA CEAP vendor agreement, revised Aug 2025', pg_temp.op())$q$);
SELECT pg_temp.admits('A2b a new agreement from 2026-09-01: 30 days',
  $q$INSERT INTO public.assistance_agency_agreements (id, tenant_id, agency_id, effective_from, pledge_payment_days, eligibility_hold_business_days, source_reference, recorded_by)
     VALUES (pg_temp.k('44'), pg_temp.t1(), pg_temp.k('41'), DATE '2026-09-01', 30, 5, 'TDHCA CEAP vendor agreement, revised Aug 2026', pg_temp.op())$q$);
SELECT pg_temp.refuses_at('A3 two agreements from one date',
  $q$INSERT INTO public.assistance_agency_agreements (tenant_id, agency_id, effective_from, pledge_payment_days, eligibility_hold_business_days, source_reference, recorded_by)
     VALUES (pg_temp.t1(), pg_temp.k('41'), DATE '2026-09-01', 60, 5, 'x', pg_temp.op())$q$,
  '23505', 'assistance_agency_agreements_one_per_date');
SELECT pg_temp.refuses_at('A3b a window of no days',
  $q$INSERT INTO public.assistance_agency_agreements (tenant_id, agency_id, effective_from, pledge_payment_days, eligibility_hold_business_days, source_reference, recorded_by)
     VALUES (pg_temp.t1(), pg_temp.k('42'), DATE '2026-01-01', 0, 0, 'x', pg_temp.op())$q$,
  '23514', 'assistance_agency_agreements_days_check');
SELECT pg_temp.refuses_at('A3c an agreement names its source',
  $q$INSERT INTO public.assistance_agency_agreements (tenant_id, agency_id, effective_from, pledge_payment_days, eligibility_hold_business_days, source_reference, recorded_by)
     VALUES (pg_temp.t1(), pg_temp.k('42'), DATE '2026-01-01', 30, 0, E'\t', pg_temp.op())$q$,
  '23514', 'assistance_agency_agreements_source_check');
SELECT pg_temp.refuses_at('A4 an agreement''s terms are never edited',
  $q$UPDATE public.assistance_agency_agreements SET pledge_payment_days = 60 WHERE id = pg_temp.k('43')$q$,
  '42501', 'assistance_agency_agreements');
SELECT pg_temp.admits('A4b an agreement entered in error is withdrawn (reason, user), not edited',
  $q$INSERT INTO public.assistance_agency_agreements (id, tenant_id, agency_id, effective_from, pledge_payment_days, eligibility_hold_business_days, source_reference, recorded_by)
     VALUES (pg_temp.k('45'), pg_temp.t1(), pg_temp.k('41'), DATE '2026-06-01', 99, 5, 'typo', pg_temp.op());
     UPDATE public.assistance_agency_agreements SET withdrawn_by = pg_temp.op(), withdrawn_reason = 'entered in error' WHERE id = pg_temp.k('45')$q$);
SELECT pg_temp.ok('A4c it is stamped withdrawn, and a pledge of 06-05 takes the 01-01 agreement (45 days) instead',
  (SELECT withdrawn_at = now() FROM public.assistance_agency_agreements WHERE id = pg_temp.k('45'))
  AND public.assistance_agreement_in_force(pg_temp.k('41'), DATE '2026-06-05') = pg_temp.k('43'));
SELECT pg_temp.refuses_at('A4d a withdrawal is not undone',
  $q$UPDATE public.assistance_agency_agreements SET withdrawn_by = NULL, withdrawn_reason = NULL WHERE id = pg_temp.k('45')$q$,
  '23001', 'only its withdrawal');
SELECT pg_temp.refuses_at('A5 an agency is never deleted',
  $q$DELETE FROM public.assistance_agencies WHERE id = pg_temp.k('42')$q$,
  '42501', 'assistance_agencies');
SELECT pg_temp.refuses_at('A5b an agency''s name is not edited (retire it and record a new one)',
  $q$UPDATE public.assistance_agencies SET name = 'SVdP' WHERE id = pg_temp.k('42')$q$,
  '42501', 'assistance_agencies');

-- R8 (08): CEAP's batch check, 45, came with no account it could be matched to.
SELECT pg_temp.rcpt(pg_temp.k('08'), 45, DATE '2026-03-21', 'CHK-CEAP-1', pg_temp.k('41'));
SELECT pg_temp.refuses_at('A6 a receipt from an agency becomes the agency''s payment, not the customer''s',
  $q$SELECT pg_temp.fromr(gen_random_uuid(), gen_random_uuid(), pg_temp.k('08'), '00000000-0000-4000-8000-0000000a24c4', 45)$q$,
  '23514', 'the receipt''s agency');
SELECT pg_temp.refuses_at('A6b nor another agency''s',
  $q$SELECT pg_temp.fromr(gen_random_uuid(), gen_random_uuid(), pg_temp.k('08'), '00000000-0000-4000-8000-0000000a24c4', 45, true, pg_temp.k('42'))$q$,
  '23514', 'the receipt''s agency');
SELECT pg_temp.admits('A6c CEAP''s 45 to C4, as CEAP''s payment',
  $q$SELECT pg_temp.fromr(pg_temp.k('18'), pg_temp.k('88'), pg_temp.k('08'), '00000000-0000-4000-8000-0000000a24c4', 45, true, pg_temp.k('41'))$q$);

-- ============================================================== L pledges
-- PL1 (51): CEAP pledges 200 for C1 on 2026-03-10 (agreement 43: pay by 04-24).
SELECT pg_temp.admits('L1 a written pledge of 200 for C1',
  $q$SELECT pg_temp.pledge(pg_temp.k('51'), '00000000-0000-4000-8000-0000000a24c1', pg_temp.k('41'), 200, DATE '2026-03-10')$q$);
SELECT pg_temp.ok('L1b the database chose the agreement in force on the pledge date, and pay_by = 03-10 + 45 = 04-24',
  (SELECT agreement_id = pg_temp.k('43') AND pay_by = DATE '2026-04-24' AND created_at = now() FROM public.agency_pledges WHERE id = pg_temp.k('51')));
SELECT pg_temp.ok('L1c on 04-01 it reads open, nothing paid, 200 outstanding', pg_temp.pst(pg_temp.k('51'), DATE '2026-04-01') = 'open/0.00/200.00');
SELECT pg_temp.ok('L1d on 04-24 it is open; on 04-25 overdue (fail loud: CI-056)',
  pg_temp.pst(pg_temp.k('51'), DATE '2026-04-24') = 'open/0.00/200.00'
  AND pg_temp.pst(pg_temp.k('51'), DATE '2026-04-25') = 'overdue/0.00/200.00');
SELECT pg_temp.admits('L2 a pledge on 2026-09-05 takes the new agreement: pay by 10-05',
  $q$SELECT pg_temp.pledge(pg_temp.k('52'), '00000000-0000-4000-8000-0000000a24c2', pg_temp.k('41'), 80, DATE '2026-09-05')$q$);
SELECT pg_temp.ok('L2b agreement 44, pay_by 2026-10-05',
  (SELECT agreement_id = pg_temp.k('44') AND pay_by = DATE '2026-10-05' FROM public.agency_pledges WHERE id = pg_temp.k('52')));
SELECT pg_temp.refuses_at('L3 the app does not choose the pay-by date',
  $q$INSERT INTO public.agency_pledges (tenant_id, customer_id, agency_id, amount, pledged_on, pay_by, form, recorded_by)
     VALUES (pg_temp.t1(), '00000000-0000-4000-8000-0000000a24c1', pg_temp.k('41'), 10, DATE '2026-03-10', DATE '2027-01-01', 'written', pg_temp.op())$q$,
  '23514', 'written by the database');
SELECT pg_temp.refuses_at('L3b nor the agreement',
  $q$INSERT INTO public.agency_pledges (tenant_id, customer_id, agency_id, amount, pledged_on, agreement_id, form, recorded_by)
     VALUES (pg_temp.t1(), '00000000-0000-4000-8000-0000000a24c1', pg_temp.k('41'), 10, DATE '2026-03-10', pg_temp.k('44'), 'written', pg_temp.op())$q$,
  '23514', 'written by the database');
-- PL3 (53): the charity (no agreement on file) pledges 50 for C1.
SELECT pg_temp.admits('L4 a pledge with no agreement on file is still recorded (fail toward protection)',
  $q$SELECT pg_temp.pledge(pg_temp.k('53'), '00000000-0000-4000-8000-0000000a24c1', pg_temp.k('42'), 50, DATE '2026-03-12')$q$);
SELECT pg_temp.ok('L4b it has no agreement and no pay-by, and reads no_agreement',
  (SELECT agreement_id IS NULL AND pay_by IS NULL FROM public.agency_pledges WHERE id = pg_temp.k('53'))
  AND pg_temp.pst(pg_temp.k('53')) = 'no_agreement/0.00/50.00');
SELECT pg_temp.ok('L5 two live pledges for C1 from two agencies coexist (CI-064)',
  (SELECT count(*) = 2 FROM public.agency_pledges WHERE customer_id = :c1));
SELECT pg_temp.refuses_at('L6 a pledge of no money',
  $q$SELECT pg_temp.pledge(gen_random_uuid(), '00000000-0000-4000-8000-0000000a24c1', pg_temp.k('41'), 0, DATE '2026-03-10')$q$,
  '23514', 'agency_pledges_amount_check');
SELECT pg_temp.refuses_at('L6e a pledge of NaN',
  $q$SELECT pg_temp.pledge(gen_random_uuid(), '00000000-0000-4000-8000-0000000a24c1', pg_temp.k('41'), 'NaN', DATE '2026-03-10')$q$,
  '23514', 'agency_pledges_amount_check');
SELECT pg_temp.refuses_at('L6b a pledge dated after today (UTC+14)',
  $q$SELECT pg_temp.pledge(gen_random_uuid(), '00000000-0000-4000-8000-0000000a24c1', pg_temp.k('41'), 10, (now() AT TIME ZONE 'Etc/GMT-14')::date + 1)$q$,
  '23514', 'no later than today');
SELECT pg_temp.refuses_at('L6c the form is written, verbal or portal',
  $q$INSERT INTO public.agency_pledges (tenant_id, customer_id, agency_id, amount, pledged_on, form, recorded_by)
     VALUES (pg_temp.t1(), '00000000-0000-4000-8000-0000000a24c1', pg_temp.k('41'), 10, DATE '2026-03-10', 'telepathy', pg_temp.op())$q$,
  '23514', 'agency_pledges_form_check');
SELECT pg_temp.refuses_at('L6d a pledge is never edited',
  $q$UPDATE public.agency_pledges SET amount = 250 WHERE id = pg_temp.k('51')$q$,
  '42501', 'agency_pledges');
-- Agency payments.
SELECT pg_temp.refuses_at('L7 an agency payment names its agency',
  $q$INSERT INTO public.payments (tenant_id, payment_number, customer_id, payment_date, amount, payment_method, payer_class)
     VALUES (pg_temp.t1(), 'A24-L7', '00000000-0000-4000-8000-0000000a24c1', DATE '2026-03-20', 1, 'check', 'agency')$q$,
  '23514', 'payments_agency_check');
SELECT pg_temp.refuses_at('L7b and a customer''s payment names none',
  $q$INSERT INTO public.payments (tenant_id, payment_number, customer_id, payment_date, amount, payment_method, payer_class, agency_id)
     VALUES (pg_temp.t1(), 'A24-L7b', '00000000-0000-4000-8000-0000000a24c1', DATE '2026-03-20', 1, 'check', 'customer', pg_temp.k('41'))$q$,
  '23514', 'payments_agency_check');
SELECT pg_temp.refuses_at('L7c a pledge is paid by its own agency (the charity paying CEAP''s pledge)',
  $q$SELECT pg_temp.apay(gen_random_uuid(), gen_random_uuid(), '00000000-0000-4000-8000-0000000a24c1', pg_temp.k('42'), pg_temp.k('51'), 1, DATE '2026-03-20')$q$,
  '23514', 'the pledge''s agency and customer');
SELECT pg_temp.refuses_at('L7d for its own customer',
  $q$SELECT pg_temp.apay(gen_random_uuid(), gen_random_uuid(), '00000000-0000-4000-8000-0000000a24c2', pg_temp.k('41'), pg_temp.k('51'), 1, DATE '2026-03-20')$q$,
  '23514', 'the pledge''s agency and customer');
SELECT pg_temp.refuses_at('L7f a payment of NaN never names a pledge (Opus r3 S1)',
  $q$SELECT pg_temp.apay(gen_random_uuid(), gen_random_uuid(), '00000000-0000-4000-8000-0000000a24c1', pg_temp.k('41'), pg_temp.k('51'), 'NaN', DATE '2026-03-20', false)$q$,
  '23514', 'payments_agency_pledge_check');
SELECT pg_temp.refuses_at('L7e a deposit never names a pledge',
  $q$INSERT INTO public.payments (tenant_id, payment_number, customer_id, payment_date, amount, payment_method, payer_class, agency_id, agency_pledge_id, is_deposit)
     VALUES (pg_temp.t1(), 'A24-L7e', '00000000-0000-4000-8000-0000000a24c1', DATE '2026-03-20', 1, 'check', 'agency', pg_temp.k('41'), pg_temp.k('51'), true)$q$,
  '23514', 'payments_agency_pledge_check');
-- CEAP pays 120 of PL1 on 03-25 (A 61); a pending 50 (A 62) does not count yet.
SELECT pg_temp.apay(pg_temp.k('61'), pg_temp.k('91'), :c1, pg_temp.k('41'), pg_temp.k('51'), 120, DATE '2026-03-25');
SELECT pg_temp.apay(pg_temp.k('62'), NULL, :c1, pg_temp.k('41'), pg_temp.k('51'), 50, DATE '2026-03-26', false);
SELECT pg_temp.ok('L8 PL1 reads 120 paid, 80 outstanding: a pending payment has not cleared',
  pg_temp.pst(pg_temp.k('51'), DATE '2026-04-01') = 'open/120.00/80.00');
SELECT pg_temp.ok('L8b on 03-24 nothing was paid (the payment''s date)',
  pg_temp.pst(pg_temp.k('51'), DATE '2026-03-24') = 'open/0.00/200.00');
SELECT pg_temp.refuses_at('L8c a payment''s agency and pledge are written once',
  $q$UPDATE public.payments SET agency_pledge_id = pg_temp.k('53') WHERE id = pg_temp.k('61')$q$,
  '23001', 'written once');
-- The 50 bounces before posting? A pending payment is voided instead.
UPDATE public.payments SET status = 'voided', status_cause_id = NULL WHERE id = pg_temp.k('62');
-- CEAP pays the 80 left on 04-10 (A 63), then bounces it on 04-15.
SELECT pg_temp.apay(pg_temp.k('63'), pg_temp.k('93'), :c1, pg_temp.k('41'), pg_temp.k('51'), 80, DATE '2026-04-10');
SELECT pg_temp.ok('L9 PL1 is paid in full on 04-10',
  pg_temp.pst(pg_temp.k('51'), DATE '2026-04-10') = 'paid/200.00/0.00');
SELECT pg_temp.bounce(pg_temp.k('63'), pg_temp.k('93'), DATE '2026-04-15');
SELECT pg_temp.ok('L9b after the bounce it is open again from 04-15 (the bank took the 80 back), overdue after 04-24',
  pg_temp.pst(pg_temp.k('51'), DATE '2026-04-16') = 'open/120.00/80.00'
  AND pg_temp.pst(pg_temp.k('51'), DATE '2026-04-25') = 'overdue/120.00/80.00');
-- PL6 (56): CEAP pledges 25 for C2 today (UTC): its pay-by is 30 days on.
INSERT INTO public.agency_pledges (id, tenant_id, customer_id, agency_id, amount, pledged_on, form, recorded_by)
VALUES (pg_temp.k('56'), pg_temp.t1(), :c2, pg_temp.k('41'), 25, (now() AT TIME ZONE 'UTC')::date, 'portal', pg_temp.op());
-- PL7 (57): pledged 30 days before today at UTC-12, so its pay-by is that
-- day: dated after it at UTC+14, a lapse is still refused until the day has
-- ended everywhere.
INSERT INTO public.agency_pledges (id, tenant_id, customer_id, agency_id, amount, pledged_on, form, recorded_by)
VALUES (pg_temp.k('57'), pg_temp.t1(), :c4, pg_temp.k('41'), 15, public.suspense_today_earliest() - 30, 'written', pg_temp.op());
SELECT pg_temp.ok('L10 (PL7''s pay-by is today at UTC-12)',
  (SELECT pay_by = public.suspense_today_earliest() FROM public.agency_pledges WHERE id = pg_temp.k('57')));
SELECT pg_temp.refuses_at('L10a a lapse is recorded only once pay_by has passed everywhere',
  $q$INSERT INTO public.agency_pledge_events (tenant_id, agency_pledge_id, event, event_on, reason, recorded_by)
     VALUES (pg_temp.t1(), pg_temp.k('57'), 'lapsed', public.suspense_today_latest(), 'not paid', pg_temp.op())$q$,
  '23514', 'has not passed');
SELECT pg_temp.refuses_at('L10b a lapse is dated after pay_by (PL1 is due 04-24)',
  $q$INSERT INTO public.agency_pledge_events (tenant_id, agency_pledge_id, event, event_on, reason, recorded_by)
     VALUES (pg_temp.t1(), pg_temp.k('51'), 'lapsed', DATE '2026-04-24', 'not paid', pg_temp.op())$q$,
  '23514', 'after pay_by');
SELECT pg_temp.refuses_at('L10c a withdrawal or lapse has its date; an error has none',
  $q$INSERT INTO public.agency_pledge_events (tenant_id, agency_pledge_id, event, reason, recorded_by)
     VALUES (pg_temp.t1(), pg_temp.k('51'), 'lapsed', 'not paid', pg_temp.op())$q$,
  '23514', 'agency_pledge_events_event_on_check');
SELECT pg_temp.admits('L11 PL1 lapses with 120 of 200 paid (CEAP''s 45 days passed)',
  $q$INSERT INTO public.agency_pledge_events (id, tenant_id, agency_pledge_id, event, event_on, reason, recorded_by)
     VALUES (pg_temp.k('71'), pg_temp.t1(), pg_temp.k('51'), 'lapsed', DATE '2026-04-25', 'agency did not send the last 80', pg_temp.op())$q$);
SELECT pg_temp.ok('L11b from 04-25 PL1 reads lapsed, 120 paid, 80 outstanding; on 04-24 it was open',
  pg_temp.pst(pg_temp.k('51')) = 'lapsed/120.00/80.00'
  AND pg_temp.pst(pg_temp.k('51'), DATE '2026-04-24') = 'open/120.00/80.00');
SELECT pg_temp.refuses_at('L11c a pledge ends once',
  $q$INSERT INTO public.agency_pledge_events (tenant_id, agency_pledge_id, event, event_on, reason, recorded_by)
     VALUES (pg_temp.t1(), pg_temp.k('51'), 'withdrawn', DATE '2026-04-26', 'x', pg_temp.op())$q$,
  '23505', 'agency_pledge_events_one_per_pledge');
SELECT pg_temp.admits('L11d a late payment naming a lapsed pledge is still taken (the money is real)',
  $q$SELECT pg_temp.apay(pg_temp.k('64'), pg_temp.k('94'), '00000000-0000-4000-8000-0000000a24c1', pg_temp.k('41'), pg_temp.k('51'), 80, DATE '2026-05-02')$q$);
SELECT pg_temp.ok('L11e from 05-02 it reads paid in full; the lapse stays on record for the agency''s history',
  pg_temp.pst(pg_temp.k('51')) = 'paid/200.00/0.00'
  AND pg_temp.pst(pg_temp.k('51'), DATE '2026-05-01') = 'lapsed/120.00/80.00'
  AND EXISTS (SELECT 1 FROM public.agency_pledge_events WHERE agency_pledge_id = pg_temp.k('51') AND event = 'lapsed'));
-- PL4 (54): CEAP 60 for C3, paid 90 (the agency sent more than it pledged).
SELECT pg_temp.pledge(pg_temp.k('54'), :c3, pg_temp.k('41'), 60, DATE '2026-03-15');
SELECT pg_temp.admits('L12 an agency payment above its pledge is taken (CI-053: money is never refused)',
  $q$SELECT pg_temp.apay(pg_temp.k('65'), pg_temp.k('95'), '00000000-0000-4000-8000-0000000a24c3', pg_temp.k('41'), pg_temp.k('54'), 90, DATE '2026-03-20')$q$);
SELECT pg_temp.ok('L12b PL4 reads paid, 90 paid, nothing outstanding',
  pg_temp.pst(pg_temp.k('54')) = 'paid/90.00/0.00');
SELECT pg_temp.refuses_at('L12c a paid pledge cannot be withdrawn',
  $q$INSERT INTO public.agency_pledge_events (tenant_id, agency_pledge_id, event, event_on, reason, recorded_by)
     VALUES (pg_temp.t1(), pg_temp.k('54'), 'withdrawn', DATE '2026-04-01', 'x', pg_temp.op())$q$,
  '23514', 'paid in full');
SELECT pg_temp.refuses_at('L12d nor lapse',
  $q$INSERT INTO public.agency_pledge_events (tenant_id, agency_pledge_id, event, event_on, reason, recorded_by)
     VALUES (pg_temp.t1(), pg_temp.k('54'), 'lapsed', DATE '2026-05-01', 'x', pg_temp.op())$q$,
  '23514', 'paid in full');
SELECT pg_temp.refuses_at('L12e nor be recorded in error once a payment names it',
  $q$INSERT INTO public.agency_pledge_events (tenant_id, agency_pledge_id, event, reason, recorded_by)
     VALUES (pg_temp.t1(), pg_temp.k('54'), 'recorded_in_error', 'x', pg_temp.op())$q$,
  '23514', 'a payment names it');
SELECT pg_temp.admits('L13 PL2 is withdrawn by the agency',
  $q$INSERT INTO public.agency_pledge_events (tenant_id, agency_pledge_id, event, event_on, reason, agency_reference, recorded_by)
     VALUES (pg_temp.t1(), pg_temp.k('52'), 'withdrawn', DATE '2026-09-20', 'customer moved out of county', 'BVCA-CANCEL-12', pg_temp.op())$q$);
SELECT pg_temp.ok('L13b PL2 reads withdrawn from 09-20, open on 09-19',
  pg_temp.pst(pg_temp.k('52')) = 'withdrawn/0.00/80.00' AND pg_temp.pst(pg_temp.k('52'), DATE '2026-09-19') = 'open/0.00/80.00');
SELECT pg_temp.refuses_at('L13d a withdrawal is not dated before the pledge',
  $q$INSERT INTO public.agency_pledge_events (tenant_id, agency_pledge_id, event, event_on, reason, recorded_by)
     VALUES (pg_temp.t1(), pg_temp.k('56'), 'withdrawn', DATE '2020-01-01', 'x', pg_temp.op())$q$,
  '23514', 'on or after the pledge');
SELECT pg_temp.refuses_at('L13c every event says why',
  $q$INSERT INTO public.agency_pledge_events (tenant_id, agency_pledge_id, event, event_on, reason, recorded_by)
     VALUES (pg_temp.t1(), pg_temp.k('53'), 'withdrawn', DATE '2026-04-01', E' \t', pg_temp.op())$q$,
  '23514', 'agency_pledge_events_reason_check');
-- PL5 (55): typed for the wrong customer.
SELECT pg_temp.pledge(pg_temp.k('55'), :c4, pg_temp.k('41'), 30, DATE '2026-03-15');
SELECT pg_temp.admits('L14 PL5 is recorded in error',
  $q$INSERT INTO public.agency_pledge_events (tenant_id, agency_pledge_id, event, reason, recorded_by)
     VALUES (pg_temp.t1(), pg_temp.k('55'), 'recorded_in_error', 'typed against the wrong account', pg_temp.op())$q$);
SELECT pg_temp.ok('L14b it reads void on every date', pg_temp.pst(pg_temp.k('55')) = 'void/0.00/0.00' AND pg_temp.pst(pg_temp.k('55'), DATE '2026-03-15') = 'void/0.00/0.00');
SELECT pg_temp.refuses_at('L14c and no payment ever names it',
  $q$SELECT pg_temp.apay(gen_random_uuid(), gen_random_uuid(), '00000000-0000-4000-8000-0000000a24c4', pg_temp.k('41'), pg_temp.k('55'), 30, DATE '2026-03-20')$q$,
  '23514', 'recorded in error');
SELECT pg_temp.ok('L15 on 04-01 the open pledges are PL1 (80 outstanding) and PL3 (no agreement); PL4 is paid, PL5 void',
  (SELECT array_agg(pledge_id ORDER BY pledge_id) = ARRAY[pg_temp.k('51'), pg_temp.k('53')]
     FROM public.agency_pledges_open_as_of(pg_temp.t1(), DATE '2026-04-01', clock_timestamp())));
SELECT pg_temp.refuses_at('L16 the pledge reader needs both coordinates',
  $q$SELECT * FROM public.agency_pledge_position_as_of(pg_temp.k('51'), NULL, clock_timestamp())$q$,
  '22004', 'both given');
-- Retiring an agency.
SELECT pg_temp.admits('L17 the charity is retired',
  $q$UPDATE public.assistance_agencies SET status = 'retired', retired_by = pg_temp.op(), retired_reason = 'program ended' WHERE id = pg_temp.k('42')$q$);
SELECT pg_temp.refuses_at('L17b a retired agency takes no new pledge',
  $q$SELECT pg_temp.pledge(gen_random_uuid(), '00000000-0000-4000-8000-0000000a24c1', pg_temp.k('42'), 5, DATE '2026-04-01')$q$,
  '23514', 'is retired');
SELECT pg_temp.admits('L17c but its money is still taken (a late check for PL3)',
  $q$SELECT pg_temp.apay(pg_temp.k('66'), pg_temp.k('96'), '00000000-0000-4000-8000-0000000a24c1', pg_temp.k('42'), pg_temp.k('53'), 50, DATE '2026-04-02')$q$);
SELECT pg_temp.ok('L15b today only PL6 and PL7 are open (PL1 and PL3 paid, PL2 withdrawn, PL4 paid, PL5 void)',
  (SELECT array_agg(pledge_id ORDER BY pledge_id) = ARRAY[pg_temp.k('56'), pg_temp.k('57')]
     FROM public.agency_pledges_open_as_of(pg_temp.t1(), (now() AT TIME ZONE 'UTC')::date, clock_timestamp())));
SELECT pg_temp.admits('L17e a retired agency''s name may be used again (Opus N1)',
  $q$INSERT INTO public.assistance_agencies (tenant_id, name, program_kind, recorded_by)
     VALUES (pg_temp.t1(), 'St. Vincent de Paul', 'charity', pg_temp.op())$q$);
-- r2 (Codex N2; inventory L1): a pledge toward a bill. B1 (bf): a draft bill of C2.
INSERT INTO public.service_locations (id, tenant_id, customer_id, location_number, address_line1, city, state, zip)
VALUES (pg_temp.k('df'), pg_temp.t1(), :c2, 'L24', '1 Main', 'Austin', 'TX', '78701');
INSERT INTO public.invoices (id, tenant_id, invoice_number, customer_id, location_id, invoice_date, billing_period, period_start, period_end, due_date, amount_due)
VALUES (pg_temp.k('bf'), pg_temp.t1(), 'B24-I1', :c2, pg_temp.k('df'), DATE '2026-03-01', '2026-02', DATE '2026-02-01', DATE '2026-02-28', DATE '2026-03-20', 90.00);
INSERT INTO public.agency_pledges (id, tenant_id, customer_id, agency_id, amount, pledged_on, form, recorded_by, toward_invoice_id)
VALUES (pg_temp.k('58'), pg_temp.t1(), :c2, pg_temp.k('41'), 40, DATE '2026-03-15', 'written', pg_temp.op(), pg_temp.k('bf'));
SELECT pg_temp.refuses_at('L18 a pledge toward a bill is paid by a payment restricted to that bill (D7-1)',
  $q$SELECT pg_temp.apay(gen_random_uuid(), NULL, '00000000-0000-4000-8000-0000000a24c2', pg_temp.k('41'), pg_temp.k('58'), 40, DATE '2026-03-20', false)$q$,
  '23514', 'restricted to that bill');
SELECT pg_temp.admits('L18b restricted to it',
  $q$INSERT INTO public.payments (tenant_id, payment_number, customer_id, payment_date, amount, payment_method, payer_class, agency_id, agency_pledge_id, restricted_to_invoice_id)
     VALUES (pg_temp.t1(), 'A24-L18b', '00000000-0000-4000-8000-0000000a24c2', DATE '2026-03-20', 40, 'check', 'agency', pg_temp.k('41'), pg_temp.k('58'), pg_temp.k('bf'))$q$);
SELECT pg_temp.refuses_at('L19 an event of a pledge not visible says so (Fable N4)',
  $q$INSERT INTO public.agency_pledge_events (tenant_id, agency_pledge_id, event, event_on, reason, recorded_by)
     VALUES (pg_temp.t1(), gen_random_uuid(), 'withdrawn', DATE '2026-04-01', 'x', pg_temp.op())$q$,
  '23503', 'not visible in this tenant');
SELECT pg_temp.refuses_at('L17d a retirement is not undone',
  $q$UPDATE public.assistance_agencies SET status = 'active' WHERE id = pg_temp.k('42')$q$,
  '23001', 'only its retirement');

-- ============================================================== G where a refund of agency money goes
-- A 65 (CEAP's 90 for C3) has 90 unapplied. Refunded: to the agency.
SELECT pg_temp.refuses_at('G1 a refund of an agency''s payment paid to the customer (Ryan 2026-11-07; 10 TAC 6.312(f))',
  $q$INSERT INTO public.payments (tenant_id, payment_number, customer_id, payment_date, amount, payment_method, refunds_payment_id)
     VALUES (pg_temp.t1(), 'G24-1', '00000000-0000-4000-8000-0000000a24c3', DATE '2026-04-01', -30, 'refund', pg_temp.k('65'))$q$,
  '23514', 'goes back to the agency');
SELECT pg_temp.refuses_at('G1b nor to another agency',
  $q$INSERT INTO public.payments (tenant_id, payment_number, customer_id, payment_date, amount, payment_method, refunds_payment_id, agency_id)
     VALUES (pg_temp.t1(), 'G24-1b', '00000000-0000-4000-8000-0000000a24c3', DATE '2026-04-01', -30, 'refund', pg_temp.k('65'), pg_temp.k('42'))$q$,
  '23514', 'goes back to the agency');
SELECT pg_temp.admits('G2 30 refunded to CEAP',
  $q$INSERT INTO public.payments (id, tenant_id, payment_number, customer_id, payment_date, amount, payment_method, refunds_payment_id, agency_id)
     VALUES (pg_temp.k('67'), pg_temp.t1(), 'G24-2', '00000000-0000-4000-8000-0000000a24c3', DATE '2026-04-01', -30, 'refund', pg_temp.k('65'), pg_temp.k('41'))$q$);
SELECT pg_temp.refuses_at('G3 a refund of the customer''s own payment names no agency',
  $q$INSERT INTO public.payments (tenant_id, payment_number, customer_id, payment_date, amount, payment_method, refunds_payment_id, agency_id)
     VALUES (pg_temp.t1(), 'G24-3', '00000000-0000-4000-8000-0000000a24c1', DATE '2026-04-01', -5, 'refund', pg_temp.k('11'), pg_temp.k('41'))$q$,
  '23514', 'goes to the customer');
SELECT pg_temp.admits('G3b a refund of the customer''s own payment, to the customer',
  $q$INSERT INTO public.payments (tenant_id, payment_number, customer_id, payment_date, amount, payment_method, refunds_payment_id)
     VALUES (pg_temp.t1(), 'G24-3b', '00000000-0000-4000-8000-0000000a24c1', DATE '2026-04-01', -5, 'refund', pg_temp.k('11'))$q$);
-- Through a credit: A 65's leftover 60 is held as an approved overpayment
-- credit (CR 31), then refunded: still to the agency.
INSERT INTO public.customer_credit_approvals (id, tenant_id, customer_id, payment_id, amount, approved_by)
VALUES (pg_temp.k('30'), pg_temp.t1(), :c3, pg_temp.k('65'), 60, pg_temp.op());
INSERT INTO public.customer_credits (id, tenant_id, customer_id, origin_type, source_payment_id, approval_id, original_amount, issued_date)
VALUES (pg_temp.k('31'), pg_temp.t1(), :c3, 'overpayment', pg_temp.k('65'), pg_temp.k('30'), 60, DATE '2026-04-02');
SELECT pg_temp.refuses_at('G4 a refund of a credit that came from an agency''s payment, to the customer',
  $q$INSERT INTO public.payments (tenant_id, payment_number, customer_id, payment_date, amount, payment_method, refunds_customer_credit_id)
     VALUES (pg_temp.t1(), 'G24-4', '00000000-0000-4000-8000-0000000a24c3', DATE '2026-04-03', -10, 'refund', pg_temp.k('31'))$q$,
  '23514', 'goes back to the agency');
SELECT pg_temp.admits('G4b to the agency',
  $q$INSERT INTO public.payments (id, tenant_id, payment_number, customer_id, payment_date, amount, payment_method, refunds_customer_credit_id, agency_id)
     VALUES (pg_temp.k('68'), pg_temp.t1(), 'G24-4b', '00000000-0000-4000-8000-0000000a24c3', DATE '2026-04-03', -10, 'refund', pg_temp.k('31'), pg_temp.k('41'))$q$);
-- The agency's refund check (68, 10) comes back after the credit's other 50
-- was escheated (-23 V7's path): the 10 is reissued as a credit (CR 32), and
-- a refund of that is still the agency's money.
SELECT pg_temp.post(pg_temp.k('68'), pg_temp.k('98'));
INSERT INTO public.escheatment_events (id, tenant_id, customer_credit_id, customer_id, event_type, amount_related)
VALUES (pg_temp.k('34'), pg_temp.t1(), pg_temp.k('31'), :c3, 'escheated_to_state', 50);
UPDATE public.customer_credits SET status = 'escheated', status_cause_id = pg_temp.k('34') WHERE id = pg_temp.k('31');
SELECT pg_temp.bounce(pg_temp.k('68'), pg_temp.k('98'), DATE '2026-04-08');
INSERT INTO public.customer_credits (id, tenant_id, customer_id, origin_type, reissues_refund_id, original_amount, issued_date)
VALUES (pg_temp.k('32'), pg_temp.t1(), :c3, 'refund_reissue', pg_temp.k('68'), 10, DATE '2026-04-09');
SET CONSTRAINTS enforce_escheated_credit_settled IMMEDIATE;
SET CONSTRAINTS enforce_escheated_credit_settled DEFERRED;
SELECT pg_temp.ok('G5 (the reissue stands: 10 on CR 32, traced to CEAP)',
  public.cash_money_agency(NULL, pg_temp.k('32')) = pg_temp.k('41'));
SELECT pg_temp.refuses_at('G5a a refund of a reissue of an agency''s refund, to the customer',
  $q$INSERT INTO public.payments (tenant_id, payment_number, customer_id, payment_date, amount, payment_method, refunds_customer_credit_id)
     VALUES (pg_temp.t1(), 'G24-5', '00000000-0000-4000-8000-0000000a24c3', DATE '2026-04-10', -10, 'refund', pg_temp.k('32'))$q$,
  '23514', 'goes back to the agency');
SELECT pg_temp.admits('G5b to the agency',
  $q$INSERT INTO public.payments (tenant_id, payment_number, customer_id, payment_date, amount, payment_method, refunds_customer_credit_id, agency_id)
     VALUES (pg_temp.t1(), 'G24-5b', '00000000-0000-4000-8000-0000000a24c3', DATE '2026-04-10', -10, 'refund', pg_temp.k('32'), pg_temp.k('41'))$q$);
-- r2 (Opus S4, Codex N2): the shortfall reissue (-27's carry). C4's X (e1)
-- pays 50, is refunded 30 (e3) and bounces: 30 short. CEAP's AP (e5) pays 50,
-- held whole as credit CE (e8), which repays the 30 (e9); CE's other 20 is
-- escheated. X's refund check comes back: the repayment is undone (ec) and
-- the 30 carried into a new credit (ed). Its money is CEAP's.
INSERT INTO public.payments (id, tenant_id, payment_number, customer_id, payment_date, amount, payment_method) VALUES
  (pg_temp.k('e1'), pg_temp.t1(), 'G24-X', :c4, DATE '2026-03-10', 50, 'check');
SELECT pg_temp.post(pg_temp.k('e1'), pg_temp.k('e2'));
INSERT INTO public.payments (id, tenant_id, payment_number, customer_id, payment_date, amount, payment_method, refunds_payment_id) VALUES
  (pg_temp.k('e3'), pg_temp.t1(), 'G24-XR', :c4, DATE '2026-03-11', -30, 'refund', pg_temp.k('e1'));
SELECT pg_temp.post(pg_temp.k('e3'), pg_temp.k('e4'));
SELECT pg_temp.bounce(pg_temp.k('e1'), pg_temp.k('e2'), DATE '2026-03-12');
SELECT pg_temp.apay(pg_temp.k('e5'), pg_temp.k('e6'), :c4, pg_temp.k('41'), NULL, 50, DATE '2026-03-10');
INSERT INTO public.customer_credit_approvals (id, tenant_id, customer_id, payment_id, amount, approved_by)
VALUES (pg_temp.k('e7'), pg_temp.t1(), :c4, pg_temp.k('e5'), 50, pg_temp.op());
INSERT INTO public.customer_credits (id, tenant_id, customer_id, origin_type, source_payment_id, approval_id, original_amount, issued_date)
VALUES (pg_temp.k('e8'), pg_temp.t1(), :c4, 'overpayment', pg_temp.k('e5'), pg_temp.k('e7'), 50, DATE '2026-03-10');
INSERT INTO public.shortfall_applications (id, tenant_id, customer_id, target_payment_id, customer_credit_id, amount, applied_on, basis)
VALUES (pg_temp.k('e9'), pg_temp.t1(), :c4, pg_temp.k('e1'), pg_temp.k('e8'), 30, DATE '2026-03-13', 'customer_pot');
INSERT INTO public.escheatment_events (id, tenant_id, customer_credit_id, customer_id, event_type, amount_related, event_date)
VALUES (pg_temp.k('ea'), pg_temp.t1(), pg_temp.k('e8'), :c4, 'escheated_to_state', 20, '2026-03-14 12:00+00');
UPDATE public.customer_credits SET status = 'escheated', status_cause_id = pg_temp.k('ea'), escheated_at = now() WHERE id = pg_temp.k('e8');
INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reverses_ledger_entry_id)
VALUES (pg_temp.k('eb'), pg_temp.t1(), :c4, DATE '2026-03-15', 'nsf', 'refund check returned', -30, pg_temp.k('e4'));
INSERT INTO public.shortfall_applications (id, tenant_id, customer_id, target_payment_id, customer_credit_id, amount, applied_on, basis, applied_by, reason, undoes_shortfall_application_id)
VALUES (pg_temp.k('ec'), pg_temp.t1(), :c4, pg_temp.k('e1'), pg_temp.k('e8'), -30, DATE '2026-03-15', 'undo', pg_temp.op(), 'refund check returned', pg_temp.k('e9'));
UPDATE public.payments SET status = 'nsf', nsf_date = DATE '2026-03-15', status_cause_id = pg_temp.k('eb') WHERE id = pg_temp.k('e3');
INSERT INTO public.customer_credits (id, tenant_id, customer_id, origin_type, original_amount, issued_date, reissues_shortfall_application_id)
VALUES (pg_temp.k('ed'), pg_temp.t1(), :c4, 'shortfall_reissue', 30, DATE '2026-03-15', pg_temp.k('ec'));
SET CONSTRAINTS public.enforce_shortfall_undo_carried IMMEDIATE;
SET CONSTRAINTS public.enforce_shortfall_undo_carried DEFERRED;
SELECT pg_temp.ok('G6 the carry''s money traces to CEAP (shortfall reissue, its undo''s credit, the overpayment, the agency''s payment)',
  public.cash_money_agency(NULL, pg_temp.k('ed')) = pg_temp.k('41'));
SELECT pg_temp.refuses_at('G6a so a refund of the carry to the customer is refused',
  $q$INSERT INTO public.payments (tenant_id, payment_number, customer_id, payment_date, amount, payment_method, refunds_customer_credit_id)
     VALUES (pg_temp.t1(), 'G24-6a', '00000000-0000-4000-8000-0000000a24c4', DATE '2026-03-16', -30, 'refund', pg_temp.k('ed'))$q$,
  '23514', 'goes back to the agency');
SELECT pg_temp.admits('G6b and to CEAP admitted',
  $q$INSERT INTO public.payments (tenant_id, payment_number, customer_id, payment_date, amount, payment_method, refunds_customer_credit_id, agency_id)
     VALUES (pg_temp.t1(), 'G24-6b', '00000000-0000-4000-8000-0000000a24c4', DATE '2026-03-16', -30, 'refund', pg_temp.k('ed'), pg_temp.k('41'))$q$);
-- A goodwill credit is the customer's: no agency.
INSERT INTO public.customer_credits (id, tenant_id, customer_id, origin_type, original_amount, issued_date)
VALUES (pg_temp.k('33'), pg_temp.t1(), :c3, 'goodwill', 5, DATE '2026-04-02');
INSERT INTO public.account_ledger (tenant_id, customer_id, transaction_date, transaction_type, description, amount, reference_type, reference_id)
VALUES (pg_temp.t1(), :c3, DATE '2026-04-02', 'credit_issued', 'goodwill', -5, 'customer_credit', pg_temp.k('33'));
SELECT pg_temp.refuses_at('G6 a refund of a goodwill credit names no agency',
  $q$INSERT INTO public.payments (tenant_id, payment_number, customer_id, payment_date, amount, payment_method, refunds_customer_credit_id, agency_id)
     VALUES (pg_temp.t1(), 'G24-6', '00000000-0000-4000-8000-0000000a24c3', DATE '2026-04-03', -5, 'refund', pg_temp.k('33'), pg_temp.k('41'))$q$,
  '23514', 'goes to the customer');
SELECT pg_temp.refuses_at('G7 a refund''s agency is written once',
  $q$UPDATE public.payments SET agency_id = NULL WHERE id = pg_temp.k('67')$q$,
  '23001', 'written once');
RESET ROLE;

-- ============================================================== S settings and the suspense readers
SET ROLE tally_app;
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000a24b1', true);
SELECT pg_temp.refuses_at('S1 with no service level set, the aged reader raises (unevaluable: -26 blocks)',
  $q$SELECT * FROM public.suspense_receipts_aged_as_of(pg_temp.t1(), DATE '2026-12-31', clock_timestamp())$q$,
  '55000', 'is not set');
RESET ROLE;
UPDATE public.tenants SET settings = settings || '{"suspense_service_level_days": 10, "suspense_retention_days": 180}'::jsonb WHERE id = pg_temp.t1();
SET ROLE tally_app;
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000a24b1', true);
SELECT pg_temp.ok('S2 the settings are recorded in the configuration history (two changes)',
  (SELECT count(*) = 2 FROM public.tenant_configuration_history
    WHERE tenant_id = pg_temp.t1() AND config_key IN ('settings.suspense_service_level_days', 'settings.suspense_retention_days')));
SELECT pg_temp.ok('S2b and read as of an instant (before the change: unset)',
  public.suspense_service_level_days_as_of(pg_temp.t1(), clock_timestamp()) = 10
  AND public.suspense_retention_days_as_of(pg_temp.t1(), clock_timestamp()) = 180
  AND public.suspense_service_level_days_as_of(pg_temp.t1(), now() - interval '1 microsecond') IS NULL);
-- R6 (06), 70 on 03-20, a candidate of C2; nothing done with it.
SELECT pg_temp.rcpt(pg_temp.k('06'), 70, DATE '2026-03-20');
INSERT INTO public.suspense_receipt_candidates (tenant_id, suspense_receipt_id, customer_id, basis, recorded_by)
VALUES (pg_temp.t1(), pg_temp.k('06'), :c2, 'operator', pg_temp.op());
SELECT pg_temp.ok('S3 on 03-30 (10 days) R6 is not aged; on 03-31 (11 days) it is, with C2 as the account to protect',
  NOT EXISTS (SELECT 1 FROM public.suspense_receipts_aged_as_of(pg_temp.t1(), DATE '2026-03-30', clock_timestamp()) WHERE receipt_id = pg_temp.k('06'))
  AND (SELECT held = 70 AND age_days = 11 AND candidate_customer_ids = ARRAY[:c2::uuid] AND NOT past_retention
         FROM public.suspense_receipts_aged_as_of(pg_temp.t1(), DATE '2026-03-31', clock_timestamp()) WHERE receipt_id = pg_temp.k('06')));
SELECT pg_temp.ok('S3b a receipt that holds nothing is never aged (R1, R4, R5)',
  NOT EXISTS (SELECT 1 FROM public.suspense_receipts_aged_as_of(pg_temp.t1(), DATE '2026-12-31', clock_timestamp())
               WHERE receipt_id IN (pg_temp.k('01'), pg_temp.k('04'), pg_temp.k('05'))));
SELECT pg_temp.ok('S3c past retention: 180 days after 03-20 is 09-16; on 09-16 not yet, on 09-17 past',
  (SELECT NOT past_retention FROM public.suspense_receipts_aged_as_of(pg_temp.t1(), DATE '2026-09-16', clock_timestamp()) WHERE receipt_id = pg_temp.k('06'))
  AND (SELECT past_retention FROM public.suspense_receipts_aged_as_of(pg_temp.t1(), DATE '2026-09-17', clock_timestamp()) WHERE receipt_id = pg_temp.k('06')));
SELECT pg_temp.ok('S4 the tenant''s total held on 12-31 (R6 70 + R2''s nothing + U8d''s 15 + U8e''s 5 + R11''s 60 + R16''s 100)',
  public.suspense_held_as_of(pg_temp.t1(), DATE '2026-12-31', clock_timestamp()) = 250);
SELECT pg_temp.refuses_at('S5 the receipt reader needs both coordinates',
  $q$SELECT * FROM public.suspense_receipt_position_as_of(pg_temp.k('06'), DATE '2026-12-31', NULL)$q$,
  '22004', 'both given');
SELECT pg_temp.refuses_at('S5b a value written straight into the history is held to the same rule (Opus S2)',
  $q$INSERT INTO public.tenant_configuration_history (tenant_id, config_key, old_value, new_value, change_source)
     VALUES (pg_temp.t1(), 'settings.suspense_service_level_days', '10', '1000000', 'manual')$q$,
  '23514', 'tenant_configuration_history_suspense_days_check');
SELECT pg_temp.refuses_at('S5c nor 10.5',
  $q$INSERT INTO public.tenant_configuration_history (tenant_id, config_key, old_value, new_value, change_source)
     VALUES (pg_temp.t1(), 'settings.suspense_retention_days', '180', '10.5', 'manual')$q$,
  '23514', 'tenant_configuration_history_suspense_days_check');
RESET ROLE;
SELECT pg_temp.refuses_at('S6 a setting of no days',
  $q$UPDATE public.tenants SET settings = settings || '{"suspense_service_level_days": 0}'::jsonb WHERE id = pg_temp.t1()$q$,
  '23514', 'tenants_suspense_days_check');
SELECT pg_temp.refuses_at('S6b nor a fraction, nor text',
  $q$UPDATE public.tenants SET settings = settings || '{"suspense_retention_days": "180"}'::jsonb WHERE id = pg_temp.t1()$q$,
  '23514', 'tenants_suspense_days_check');
SELECT pg_temp.refuses_at('S6d nor 10000',
  $q$UPDATE public.tenants SET settings = settings || '{"suspense_retention_days": 10000}'::jsonb WHERE id = pg_temp.t1()$q$,
  '23514', 'tenants_suspense_days_check');
SELECT pg_temp.refuses_at('S6c nor 10.5',
  $q$UPDATE public.tenants SET settings = settings || '{"suspense_retention_days": 10.5}'::jsonb WHERE id = pg_temp.t1()$q$,
  '23514', 'tenants_suspense_days_check');

-- ============================================================== Y the retired program type
SELECT pg_temp.refuses_at('Y1 no new agency_pledge enrollment (a pledge is an agency_pledges row)',
  $q$INSERT INTO public.customer_program_enrollments (tenant_id, customer_id, program_type, effective_start_date, status)
     VALUES (pg_temp.t1(), '00000000-0000-4000-8000-0000000a24c1', 'agency_pledge', DATE '2026-03-01', 'pending_application')$q$,
  '23514', 'agency_pledge is retired');
SELECT pg_temp.ok('Y2 the type says so and is still not protective',
  (SELECT NOT is_disconnect_protective AND description LIKE '%v5.4.2-24%' FROM public.program_types WHERE code = 'agency_pledge'));

-- ============================================================== O history loads (the owner chooses its times)
-- r2 (Codex B4): R10 (0b), 100, recorded 03-02; returned 03-03; the return
-- undone, dated 03-04 but recorded 03-10. A payment recorded 03-05 would spend
-- the undone money before the undo was known.
INSERT INTO public.suspense_receipts (id, tenant_id, receipt_number, amount, received_on, channel, source_system, check_number, recorded_by, created_at)
VALUES (pg_temp.k('0b'), pg_temp.t1(), 'R24-000b', 100, DATE '2026-04-02', 'mail', 'internal', 'CHK-0b', pg_temp.op(), '2026-04-02 12:00+00');
INSERT INTO public.suspense_receipt_dispositions (id, tenant_id, suspense_receipt_id, kind, amount, disposed_on, instrument_reference, reason, recorded_by, created_at)
VALUES (pg_temp.k('26'), pg_temp.t1(), pg_temp.k('0b'), 'returned_to_sender', 100, DATE '2026-04-03', 'RCHK-26', 'returned', pg_temp.op(), '2026-04-03 12:00+00');
INSERT INTO public.suspense_receipt_dispositions (id, tenant_id, suspense_receipt_id, kind, amount, disposed_on, reason, recorded_by, undoes_disposition_id, created_at)
VALUES (pg_temp.k('27'), pg_temp.t1(), pg_temp.k('0b'), 'undo', -100, DATE '2026-04-04', 'check came back', pg_temp.op(), pg_temp.k('26'), '2026-04-10 12:00+00');
SELECT pg_temp.refuses_at('O1 a payment recorded before the release it spends (04-05, the undo known 04-10) is refused (Codex B4)',
  $q$INSERT INTO public.payments (tenant_id, payment_number, customer_id, payment_date, effective_date, effective_date_method, amount, payment_method, channel, source_system, check_number,
                                  suspense_receipt_id, suspense_resolution_reason, suspense_resolved_by, created_at)
     VALUES (pg_temp.t1(), 'P24-O1', '00000000-0000-4000-8000-0000000a24c1', DATE '2026-04-05', DATE '2026-04-02', 'lockbox_receipt', 100, 'check', 'mail', 'internal', 'CHK-0b',
             pg_temp.k('0b'), 'identified', pg_temp.op(), '2026-04-05 12:00+00')$q$,
  '23514', 'before a row of the receipt already recorded');
SELECT pg_temp.refuses_at('O1b nor a disposition',
  $q$INSERT INTO public.suspense_receipt_dispositions (tenant_id, suspense_receipt_id, kind, amount, disposed_on, return_code, reason, recorded_by, created_at)
     VALUES (pg_temp.t1(), pg_temp.k('0b'), 'bank_returned', 100, DATE '2026-04-05', 'R01', 'x', pg_temp.op(), '2026-04-05 12:00+00')$q$,
  '23514', 'before a row of the receipt already recorded');
SELECT pg_temp.admits('O1c recorded after the undo, the payment is admitted',
  $q$INSERT INTO public.payments (tenant_id, payment_number, customer_id, payment_date, effective_date, effective_date_method, amount, payment_method, channel, source_system, check_number,
                                  suspense_receipt_id, suspense_resolution_reason, suspense_resolved_by, created_at)
     VALUES (pg_temp.t1(), 'P24-O1c', '00000000-0000-4000-8000-0000000a24c1', DATE '2026-04-05', DATE '2026-04-02', 'lockbox_receipt', 100, 'check', 'mail', 'internal', 'CHK-0b',
             pg_temp.k('0b'), 'identified', pg_temp.op(), '2026-04-11 12:00+00')$q$);
SELECT pg_temp.ok('O1d no recorded instant reads R10 below 0 (04-06 as known on 04-06: 0 held, nothing paid)',
  (SELECT held = 0 AND to_payments = 0 FROM public.suspense_receipt_position_as_of(pg_temp.k('0b'), DATE '2026-04-06', '2026-04-06 12:00+00')));
-- r3 (Codex r2 probe 02): R12 (0d): returned (28, recorded 04-03), the
-- return undone (29, dated 04-04, recorded 04-10). A payment recorded 04-05
-- whose uuid is the undo's is still ordered after the undo.
INSERT INTO public.suspense_receipts (id, tenant_id, receipt_number, amount, received_on, channel, source_system, check_number, recorded_by, created_at)
VALUES (pg_temp.k('0d'), pg_temp.t1(), 'R24-000d', 100, DATE '2026-04-02', 'mail', 'internal', 'CHK-0d', pg_temp.op(), '2026-04-02 12:00+00');
INSERT INTO public.suspense_receipt_dispositions (id, tenant_id, suspense_receipt_id, kind, amount, disposed_on, instrument_reference, reason, recorded_by, created_at)
VALUES (pg_temp.k('28'), pg_temp.t1(), pg_temp.k('0d'), 'returned_to_sender', 100, DATE '2026-04-03', 'RCHK-28', 'returned', pg_temp.op(), '2026-04-03 12:00+00');
INSERT INTO public.suspense_receipt_dispositions (id, tenant_id, suspense_receipt_id, kind, amount, disposed_on, reason, recorded_by, undoes_disposition_id, created_at)
VALUES (pg_temp.k('29'), pg_temp.t1(), pg_temp.k('0d'), 'undo', -100, DATE '2026-04-04', 'check came back', pg_temp.op(), pg_temp.k('28'), '2026-04-10 12:00+00');
SELECT pg_temp.refuses_at('O1e a payment sharing the undo''s uuid is still ordered after it (Codex r2 probe 02)',
  $q$INSERT INTO public.payments (id, tenant_id, payment_number, customer_id, payment_date, effective_date, effective_date_method, amount, payment_method, channel, source_system, check_number,
                                  suspense_receipt_id, suspense_resolution_reason, suspense_resolved_by, created_at)
     VALUES (pg_temp.k('29'), pg_temp.t1(), 'P24-O1e', '00000000-0000-4000-8000-0000000a24c1', DATE '2026-04-05', DATE '2026-04-02', 'lockbox_receipt', 100, 'check', 'mail', 'internal', 'CHK-0d',
             pg_temp.k('0d'), 'identified', pg_temp.op(), '2026-04-05 12:00+00')$q$,
  '23514', 'before a row of the receipt already recorded');
-- r3 (Opus B1, Fable B1, Codex r2 probe 03): a release is ordered too.
INSERT INTO public.suspense_receipts (id, tenant_id, receipt_number, amount, received_on, channel, source_system, check_number, recorded_by, created_at)
VALUES (pg_temp.k('0e'), pg_temp.t1(), 'R24-000e', 100, DATE '2026-04-02', 'mail', 'internal', 'CHK-0e', pg_temp.op(), '2026-04-02 12:00+00');
INSERT INTO public.suspense_receipt_dispositions (id, tenant_id, suspense_receipt_id, kind, amount, disposed_on, instrument_reference, reason, recorded_by, created_at)
VALUES (pg_temp.k('2a'), pg_temp.t1(), pg_temp.k('0e'), 'returned_to_sender', 100, DATE '2026-04-03', 'RCHK-2a', 'returned', pg_temp.op(), '2026-04-10 12:00+00');
SELECT pg_temp.refuses_at('O1f an undo recorded before what it undoes (04-05, the return recorded 04-10)',
  $q$INSERT INTO public.suspense_receipt_dispositions (tenant_id, suspense_receipt_id, kind, amount, disposed_on, reason, recorded_by, undoes_disposition_id, created_at)
     VALUES (pg_temp.t1(), pg_temp.k('0e'), 'undo', -100, DATE '2026-04-04', 'x', pg_temp.op(), pg_temp.k('2a'), '2026-04-05 12:00+00')$q$,
  '23514', 'before a row of the receipt already recorded');
-- R15 (0f): a payment from it posted, then reversed as misposted, recorded 04-10.
INSERT INTO public.suspense_receipts (id, tenant_id, receipt_number, amount, received_on, channel, source_system, check_number, recorded_by, created_at)
VALUES (pg_temp.k('0f'), pg_temp.t1(), 'R24-000f', 100, DATE '2026-04-02', 'mail', 'internal', 'CHK-0f', pg_temp.op(), '2026-04-02 12:00+00');
INSERT INTO public.payments (id, tenant_id, payment_number, customer_id, payment_date, effective_date, effective_date_method, amount, payment_method, channel, source_system, check_number,
                             suspense_receipt_id, suspense_resolution_reason, suspense_resolved_by, created_at)
VALUES (pg_temp.k('1b'), pg_temp.t1(), 'P24-001b', :c1, DATE '2026-04-02', DATE '2026-04-02', 'lockbox_receipt', 100, 'check', 'mail', 'internal', 'CHK-0f',
        pg_temp.k('0f'), 'identified', pg_temp.op(), '2026-04-03 12:00+00');
INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reference_type, reference_id, created_at)
VALUES (pg_temp.k('8e'), pg_temp.t1(), :c1, DATE '2026-04-02', 'payment', 'posted', -100, 'payment', pg_temp.k('1b'), '2026-04-03 12:00+00');
UPDATE public.payments SET status = 'posted', status_cause_id = pg_temp.k('8e'), status_recorded_at = '2026-04-03 12:00+00' WHERE id = pg_temp.k('1b');
INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reference_type, reference_id, reverses_ledger_entry_id, reversal_reason, created_at)
VALUES (pg_temp.k('8f'), pg_temp.t1(), :c1, DATE '2026-04-04', 'adjustment', 'misposted', 100, 'payment', pg_temp.k('1b'), pg_temp.k('8e'), 'misposted', '2026-04-10 12:00+00');
UPDATE public.payments SET status = 'reversed', reversed_at = '2026-04-10 12:00+00', reversed_by = pg_temp.op(), reversed_reason = 'misposted', status_cause_id = pg_temp.k('8f'),
       status_recorded_at = '2026-04-10 12:00+00' WHERE id = pg_temp.k('1b');
SELECT pg_temp.refuses_at('O1g a misposting return recorded before the reversal (04-05, the reversal recorded 04-10; Opus B1, Fable B1)',
  $q$INSERT INTO public.suspense_receipt_dispositions (tenant_id, suspense_receipt_id, kind, amount, disposed_on, reason, recorded_by, returned_payment_id, created_at)
     VALUES (pg_temp.t1(), pg_temp.k('0f'), 'misposting_returned', -100, DATE '2026-04-04', 'misposted', pg_temp.op(), pg_temp.k('1b'), '2026-04-05 12:00+00')$q$,
  '23514', 'before a row of the receipt already recorded');
SELECT pg_temp.admits('O1h recorded after it, admitted',
  $q$INSERT INTO public.suspense_receipt_dispositions (tenant_id, suspense_receipt_id, kind, amount, disposed_on, reason, recorded_by, returned_payment_id, created_at)
     VALUES (pg_temp.t1(), pg_temp.k('0f'), 'misposting_returned', -100, DATE '2026-04-04', 'misposted', pg_temp.op(), pg_temp.k('1b'), '2026-04-11 12:00+00')$q$);
-- r4 (Fable r3 S1): a history load's payment born voided, its void after
-- its insert, is not ordered after its own void.
INSERT INTO public.suspense_receipts (id, tenant_id, receipt_number, amount, received_on, channel, source_system, check_number, recorded_by, created_at)
VALUES (pg_temp.k('12'), pg_temp.t1(), 'R24-0012', 100, DATE '2026-04-02', 'mail', 'internal', 'CHK-12', pg_temp.op(), '2026-04-02 12:00+00');
SELECT pg_temp.admits('O4 a payment loaded already voided (voided 04-04, recorded 04-03)',
  $q$INSERT INTO public.payments (tenant_id, payment_number, customer_id, payment_date, amount, payment_method, channel, source_system, check_number,
                                  suspense_receipt_id, suspense_resolution_reason, suspense_resolved_by, created_at, status, status_recorded_at)
     VALUES (pg_temp.t1(), 'P24-O4', '00000000-0000-4000-8000-0000000a24c1', DATE '2026-04-02', 100, 'check', 'mail', 'internal', 'CHK-12',
             pg_temp.k('12'), 'identified', pg_temp.op(), '2026-04-03 12:00+00', 'voided', '2026-04-04 12:00+00')$q$);
-- r2 (Codex B6): clocks.
SELECT pg_temp.refuses_at('O2 a receipt recorded at infinity',
  $q$INSERT INTO public.suspense_receipts (tenant_id, receipt_number, amount, received_on, channel, source_system, check_number, recorded_by, created_at)
     VALUES (pg_temp.t1(), 'R24-O2', 5, DATE '2026-04-02', 'mail', 'internal', '1', pg_temp.op(), 'infinity')$q$,
  '23514', 'a finite time already reached');
SELECT pg_temp.refuses_at('O2e or at -infinity (it would read as known before every other row)',
  $q$INSERT INTO public.suspense_receipt_candidates (tenant_id, suspense_receipt_id, customer_id, basis, recorded_by, created_at)
     VALUES (pg_temp.t1(), pg_temp.k('0b'), '00000000-0000-4000-8000-0000000a24c1', 'operator', pg_temp.op(), '-infinity')$q$,
  '23514', 'a finite time already reached');
SELECT pg_temp.refuses_at('O2b or in the future',
  $q$INSERT INTO public.agency_pledges (tenant_id, customer_id, agency_id, amount, pledged_on, form, recorded_by, created_at)
     VALUES (pg_temp.t1(), '00000000-0000-4000-8000-0000000a24c1', pg_temp.k('41'), 5, DATE '2026-04-02', 'written', pg_temp.op(), clock_timestamp() + interval '1 day')$q$,
  '23514', 'a finite time already reached');
SELECT pg_temp.refuses_at('O2c a receipt dated -infinity (tally_app could reach it with no closed period)',
  $q$INSERT INTO public.suspense_receipts (tenant_id, receipt_number, amount, received_on, channel, source_system, check_number, recorded_by)
     VALUES (pg_temp.t2(), 'R24-O2c', 5, '-infinity', 'mail', 'internal', '1', '00000000-0000-4000-8000-0000000a24b2')$q$,
  '23514', 'suspense_receipts_dates_check');
SELECT pg_temp.refuses_at('O2d a pledge dated -infinity',
  $q$INSERT INTO public.agency_pledges (tenant_id, customer_id, agency_id, amount, pledged_on, form, recorded_by)
     VALUES (pg_temp.t1(), '00000000-0000-4000-8000-0000000a24c1', pg_temp.k('41'), 5, '-infinity', 'written', pg_temp.op())$q$,
  '22004', 'a finite date');
SELECT pg_temp.refuses_at('O3 a superuser''s pledge for another tenant''s customer (Opus N2)',
  $q$SET LOCAL session_replication_role = replica;
     INSERT INTO public.agency_pledges (tenant_id, customer_id, agency_id, amount, pledged_on, form, recorded_by)
     VALUES (pg_temp.t1(), '00000000-0000-4000-8000-0000000a24c9', pg_temp.k('41'), 5, DATE '2026-04-02', 'written', pg_temp.op())$q$,
  '23503', 'not visible in this tenant');

SELECT pg_temp.refuses_at('O3b a superuser''s disposition of another tenant''s receipt, foreign keys off (Opus r2 N)',
  $q$SET LOCAL session_replication_role = replica;
     INSERT INTO public.suspense_receipt_dispositions (tenant_id, suspense_receipt_id, kind, amount, disposed_on, return_code, reason, recorded_by)
     VALUES (pg_temp.t2(), pg_temp.k('06'), 'bank_returned', 1, DATE '2026-04-02', 'R01', 'x', '00000000-0000-4000-8000-0000000a24b2')$q$,
  '23503', 'not visible in this tenant');
SELECT pg_temp.refuses_at('O3c and a pledge event of another tenant''s pledge',
  $q$SET LOCAL session_replication_role = replica;
     INSERT INTO public.agency_pledge_events (tenant_id, agency_pledge_id, event, event_on, reason, recorded_by)
     VALUES (pg_temp.t2(), pg_temp.k('56'), 'withdrawn', (now() AT TIME ZONE 'UTC')::date, 'x', '00000000-0000-4000-8000-0000000a24b2')$q$,
  '23503', 'not visible in this tenant');

-- ============================================================== D the freeze
SET ROLE tally_close;
UPDATE public.accounting_close_heads SET closed_through = DATE '2026-03-31' WHERE tenant_id = '00000000-0000-4000-8000-0000000a24a1';
RESET ROLE;
SET ROLE tally_app;
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000a24b1', true);
SELECT pg_temp.refuses_at('D1 a receipt dated in a closed period (-22 P2)',
  $q$SELECT pg_temp.rcpt(gen_random_uuid(), 5, DATE '2026-03-31')$q$,
  '23514', 'a closed period is frozen');
SELECT pg_temp.refuses_at('D2 a disposition dated in a closed period',
  $q$SELECT pg_temp.disp(NULL, pg_temp.k('06'), 'returned_to_sender', 5, DATE '2026-03-31')$q$,
  '23514', 'a closed period is frozen');
SELECT pg_temp.admits('D3 one dated after it',
  $q$SELECT pg_temp.disp(NULL, pg_temp.k('06'), 'returned_to_sender', 5, DATE '2026-04-01')$q$);
SELECT pg_temp.refuses_at('D4 a payment from a receipt dated in the closed period is refused',
  $q$SELECT pg_temp.fromr(gen_random_uuid(), gen_random_uuid(), pg_temp.k('06'), '00000000-0000-4000-8000-0000000a24c2', 5)$q$,
  '23514', 'a closed period is frozen');
SELECT pg_temp.admits('D4b money identified after the close is posted in the open period, effective the day it came (03-20)',
  $q$SELECT pg_temp.fromr(pg_temp.k('17'), pg_temp.k('87'), pg_temp.k('06'), '00000000-0000-4000-8000-0000000a24c2', 65, true, NULL, DATE '2026-04-02')$q$);
SELECT pg_temp.ok('D4c R6 holds 0 (65 to C2, 5 returned); the payment is effective 03-20',
  pg_temp.held(pg_temp.k('06')) = 0
  AND (SELECT effective_date = DATE '2026-03-20' FROM public.payments WHERE id = pg_temp.k('17')));
RESET ROLE;

-- ============================================================== T tenants
SET ROLE tally_app;
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000a24b2', true);
SELECT pg_temp.ok('T1 T2''s operator sees none of T1''s receipts, candidates, dispositions, agencies, agreements, pledges or events',
  NOT EXISTS (SELECT 1 FROM public.suspense_receipts) AND NOT EXISTS (SELECT 1 FROM public.suspense_receipt_candidates)
  AND NOT EXISTS (SELECT 1 FROM public.suspense_receipt_dispositions) AND NOT EXISTS (SELECT 1 FROM public.assistance_agencies)
  AND NOT EXISTS (SELECT 1 FROM public.assistance_agency_agreements) AND NOT EXISTS (SELECT 1 FROM public.agency_pledges)
  AND NOT EXISTS (SELECT 1 FROM public.agency_pledge_events));
SELECT pg_temp.refuses_at('T2 nor writes one under T1',
  $q$INSERT INTO public.assistance_agencies (tenant_id, name, program_kind, recorded_by)
     VALUES (pg_temp.t1(), 'Sneaky', 'charity', '00000000-0000-4000-8000-0000000a24b2')$q$,
  '42501', 'row-level security');
INSERT INTO public.assistance_agencies (id, tenant_id, name, program_kind, recorded_by)
VALUES (pg_temp.k('49'), pg_temp.t2(), 'T2 Agency', 'charity', '00000000-0000-4000-8000-0000000a24b2');
SELECT pg_temp.refuses_at('T3 a T2 pledge naming T1''s customer',
  $q$INSERT INTO public.agency_pledges (tenant_id, customer_id, agency_id, amount, pledged_on, form, recorded_by)
     VALUES (pg_temp.t2(), '00000000-0000-4000-8000-0000000a24c1', pg_temp.k('49'), 10, DATE '2026-04-01', 'written', '00000000-0000-4000-8000-0000000a24b2')$q$,
  '23503', 'agency_pledges_customer_fkey');
SELECT pg_temp.refuses_at('T4 a T2 payment naming T1''s agency',
  $q$INSERT INTO public.payments (tenant_id, payment_number, customer_id, payment_date, amount, payment_method, payer_class, agency_id)
     VALUES (pg_temp.t2(), 'T24-4', '00000000-0000-4000-8000-0000000a24c9', DATE '2026-04-01', 1, 'check', 'agency', pg_temp.k('41'))$q$,
  '23503', 'payments_agency_fkey');
SELECT pg_temp.refuses_at('T5 a T2 pledge naming T1''s agency',
  $q$INSERT INTO public.agency_pledges (tenant_id, customer_id, agency_id, amount, pledged_on, form, recorded_by)
     VALUES (pg_temp.t2(), '00000000-0000-4000-8000-0000000a24c9', pg_temp.k('41'), 10, DATE '2026-04-01', 'written', '00000000-0000-4000-8000-0000000a24b2')$q$,
  '23503', 'agency_pledges_agency_fkey');
SELECT pg_temp.refuses_at('T6 a receipt recorded by another tenant''s user',
  $q$INSERT INTO public.suspense_receipts (tenant_id, receipt_number, amount, received_on, channel, source_system, check_number, recorded_by)
     VALUES (pg_temp.t2(), 'R24-T6', 5, DATE '2026-04-01', 'mail', 'internal', '1', '00000000-0000-4000-8000-0000000a24b1')$q$,
  '23503', 'suspense_receipts_recorded_by_fkey');
RESET ROLE;

-- ============================================================== I invariants
SELECT pg_temp.admits('I1 the invariants hold as applied',
  $q$SELECT public.assert_suspense_pledge_guard_invariants()$q$);
SELECT pg_temp.refuses_at('I2 a guard switched off',
  $q$ALTER TABLE public.suspense_receipt_dispositions DISABLE TRIGGER enforce_suspense_disposition;
     SELECT public.assert_suspense_pledge_guard_invariants()$q$,
  '0LP01', 'enforce_suspense_disposition');
SELECT pg_temp.refuses_at('I3 a grant widened',
  $q$GRANT UPDATE (amount) ON public.suspense_receipts TO tally_app;
     SELECT public.assert_suspense_pledge_guard_invariants()$q$,
  '0LP01', 'suspense_receipts');
SELECT pg_temp.refuses_at('I4 a second policy',
  $q$CREATE POLICY wide ON public.agency_pledges USING (true);
     SELECT public.assert_suspense_pledge_guard_invariants()$q$,
  '0LP01', 'another policy beside it');
SELECT pg_temp.refuses_at('I5 RLS forced off',
  $q$ALTER TABLE public.agency_pledges NO FORCE ROW LEVEL SECURITY;
     SELECT public.assert_suspense_pledge_guard_invariants()$q$,
  '0LP01', 'agency_pledges');
SELECT pg_temp.refuses_at('I6 a single-column key between tenant tables (R-12)',
  $q$ALTER TABLE public.agency_pledges ADD CONSTRAINT stray_fk FOREIGN KEY (agency_id) REFERENCES public.assistance_agencies(id);
     SELECT public.assert_suspense_pledge_guard_invariants()$q$,
  '0LP01', 'stray_fk');
-- r2 (Codex S1, Opus S1, Fable S1): what the invariant now pins.
SELECT pg_temp.refuses_at('I8 a CHECK dropped (payments_agency_check)',
  $q$ALTER TABLE public.payments DROP CONSTRAINT payments_agency_check;
     SELECT public.assert_suspense_pledge_guard_invariants()$q$,
  '0LP01', 'payments_agency_check');
SELECT pg_temp.refuses_at('I8b a key dropped (payments_suspense_receipt_fkey)',
  $q$ALTER TABLE public.payments DROP CONSTRAINT payments_suspense_receipt_fkey;
     SELECT public.assert_suspense_pledge_guard_invariants()$q$,
  '0LP01', 'payments_suspense_receipt_fkey');
SELECT pg_temp.refuses_at('I8c the settings CHECK on the history dropped',
  $q$ALTER TABLE public.tenant_configuration_history DROP CONSTRAINT tenant_configuration_history_suspense_days_check;
     SELECT public.assert_suspense_pledge_guard_invariants()$q$,
  '0LP01', 'tenant_configuration_history_suspense_days_check');
SELECT pg_temp.refuses_at('I8d a unique index dropped',
  $q$DROP INDEX public.suspense_receipts_provider_transaction_once;
     SELECT public.assert_suspense_pledge_guard_invariants()$q$,
  '0LP01', 'suspense_receipts_provider_transaction_once');
SELECT pg_temp.refuses_at('I8e a stamp grant revoked',
  $q$REVOKE UPDATE (status) ON public.assistance_agencies FROM tally_app;
     SELECT public.assert_suspense_pledge_guard_invariants()$q$,
  '0LP01', 'lost an UPDATE grant');
SELECT pg_temp.refuses_at('I8f the cap''s body replaced',
  $q$CREATE OR REPLACE FUNCTION public.check_suspense_receipt_cap(p_receipt_id uuid) RETURNS void LANGUAGE plpgsql STABLE SET search_path = public, pg_temp AS $b$ BEGIN RETURN; END; $b$;
     SELECT public.assert_suspense_pledge_guard_invariants()$q$,
  '0LP01', 'check_suspense_receipt_cap');
SELECT pg_temp.refuses_at('I8g the recorded-at guard switched off on one table',
  $q$ALTER TABLE public.agency_pledges DISABLE TRIGGER b_enforce_recorded_at;
     SELECT public.assert_suspense_pledge_guard_invariants()$q$,
  '0LP01', 'b_enforce_recorded_at');
-- r3 (Opus S1, Fable S1, Codex r2 probe 06).
SELECT pg_temp.refuses_at('I9 the READ COMMITTED pin''s body replaced',
  $q$CREATE OR REPLACE FUNCTION public.suspense_require_read_committed(p_what text) RETURNS void LANGUAGE plpgsql STABLE SET search_path = public, pg_temp AS $b$ BEGIN RETURN; END; $b$;
     SELECT public.assert_suspense_pledge_guard_invariants()$q$,
  '0LP01', 'suspense_require_read_committed');
SELECT pg_temp.refuses_at('I9b a guard''s volatility changed',
  $q$ALTER FUNCTION public.check_provider_transaction_once(uuid, text, text, numeric, uuid, boolean) STABLE;
     SELECT public.assert_suspense_pledge_guard_invariants()$q$,
  '0LP01', 'volatility, security or settings');
SELECT pg_temp.refuses_at('I9c a function''s search_path pin removed',
  $q$ALTER FUNCTION public.cash_money_agency(uuid, uuid) RESET search_path;
     SELECT public.assert_suspense_pledge_guard_invariants()$q$,
  '0LP01', 'volatility, security or settings');
SELECT pg_temp.refuses_at('I9d tally_app''s EXECUTE on a helper revoked',
  $q$REVOKE EXECUTE ON FUNCTION public.suspense_today_latest() FROM tally_app;
     SELECT public.assert_suspense_pledge_guard_invariants()$q$,
  '0LP01', 'lost EXECUTE');
SELECT pg_temp.refuses_at('I9e a NOT NULL dropped',
  $q$ALTER TABLE public.agency_pledges ALTER COLUMN amount DROP NOT NULL;
     SELECT public.assert_suspense_pledge_guard_invariants()$q$,
  '0LP01', 'lost NOT NULL');
SELECT pg_temp.refuses_at('I7 the payments write-once guard switched off',
  $q$ALTER TABLE public.payments DISABLE TRIGGER enforce_payment_suspense_pledge;
     SELECT public.assert_suspense_pledge_guard_invariants()$q$,
  '0LP01', 'enforce_payment_suspense_pledge');

ROLLBACK;
