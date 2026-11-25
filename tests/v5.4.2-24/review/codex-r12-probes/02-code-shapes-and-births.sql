-- Codex r12: PREDICTED, NOT EXECUTED. Run as owner on a fresh clone with frozen r12 applied.
-- Revoke clone TEMP from PUBLIC, tally_app and tally_core before applying the patch.
-- No role creation/alteration; role switches below are local controls.
\set ON_ERROR_STOP on
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
CREATE FUNCTION pg_temp.n(p text) RETURNS uuid LANGUAGE sql IMMUTABLE AS $$ SELECT ('00000000-0000-4000-8000-0000000c25' || p)::uuid $$;
CREATE FUNCTION pg_temp.rev(p_id uuid, p_pay uuid, p_of uuid, p_type text, p_amount numeric, p_on date) RETURNS void LANGUAGE sql AS $$
  INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reference_type, reference_id, reverses_ledger_entry_id, reversal_reason)
  SELECT coalesce(p_id, gen_random_uuid()), p.tenant_id, p.customer_id, p_on, p_type, 'r10', p_amount, 'payment', p_pay, p_of, CASE WHEN p_type = 'nsf' THEN NULL ELSE 'r10' END
    FROM public.payments p WHERE p.id = p_pay $$;
-- The tenants, users and the clock the battery reads at.
CREATE FUNCTION pg_temp.t1() RETURNS uuid LANGUAGE sql IMMUTABLE AS $$ SELECT '00000000-0000-4000-8000-0000000a24a1'::uuid $$;
CREATE FUNCTION pg_temp.t2() RETURNS uuid LANGUAGE sql IMMUTABLE AS $$ SELECT '00000000-0000-4000-8000-0000000a24a2'::uuid $$;
CREATE FUNCTION pg_temp.op() RETURNS uuid LANGUAGE sql IMMUTABLE AS $$ SELECT '00000000-0000-4000-8000-0000000a24b1'::uuid $$;
CREATE FUNCTION pg_temp.due(p_pay uuid, p_on date, p_at timestamp with time zone DEFAULT NULL) RETURNS text LANGUAGE sql AS $$
  SELECT coalesce((SELECT x.owed || ' since ' || x.due_since FROM public.suspense_misposting_returns_due_as_of(pg_temp.t1(), p_on, coalesce(p_at, clock_timestamp())) x WHERE x.payment_id = p_pay), 'none') $$;
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
-- the money came; posted unless p_post is false; a deposit where p_deposit
-- (r12: its posting entry is typed deposit, by post()).
CREATE FUNCTION pg_temp.fromr(p_id uuid, p_entry uuid, p_r uuid, p_cust uuid, p_amount numeric, p_post boolean DEFAULT true,
                              p_agency uuid DEFAULT NULL, p_on date DEFAULT NULL, p_deposit boolean DEFAULT false) RETURNS void LANGUAGE plpgsql AS $$
DECLARE r public.suspense_receipts%ROWTYPE;
BEGIN
  SELECT * INTO r FROM public.suspense_receipts WHERE id = p_r;
  INSERT INTO public.payments (id, tenant_id, payment_number, customer_id, payment_date, effective_date, effective_date_method, amount, payment_method, channel, source_system,
                               reference_number, check_number, check_date, check_bank_name, payer_class, agency_id,
                               suspense_receipt_id, suspense_resolution_reason, suspense_resolved_by, is_deposit)
  VALUES (p_id, pg_temp.t1(), 'P24-' || right(p_id::text, 4), p_cust, coalesce(p_on, r.received_on), r.received_on, 'lockbox_receipt', p_amount, 'check', r.channel, r.source_system,
          r.reference_number, r.check_number, r.check_date, r.check_bank_name,
          CASE WHEN p_agency IS NULL THEN 'customer' ELSE 'agency' END, p_agency,
          p_r, 'the customer called with the check number', pg_temp.op(), p_deposit);
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
GRANT EXECUTE ON FUNCTION pg_temp.n(text), pg_temp.rev(uuid, uuid, uuid, text, numeric, date), pg_temp.due(uuid, date, timestamp with time zone), pg_temp.refuses_at(text, text, text, text), pg_temp.ok(text, boolean), pg_temp.admits(text, text), pg_temp.k(text),
  pg_temp.t1(), pg_temp.t2(), pg_temp.op(), pg_temp.post(uuid, uuid), pg_temp.bounce(uuid, uuid, date), pg_temp.unpost(uuid, uuid, date),
  pg_temp.rcpt(uuid, numeric, date, text, uuid), pg_temp.fromr(uuid, uuid, uuid, uuid, numeric, boolean, uuid, date, boolean),
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

SELECT set_config('app.user_id','00000000-0000-4000-8000-0000000a24b1',true);
SET LOCAL ROLE tally_app;
SELECT pg_temp.rcpt(pg_temp.n('10'),100,'2026-03-10');
SELECT pg_temp.fromr(pg_temp.n('11'),pg_temp.n('12'),pg_temp.n('10'),pg_temp.k('c1'),100);
SELECT pg_temp.rev(pg_temp.n('13'),pg_temp.n('11'),pg_temp.n('12'),'adjustment',100,'2026-03-11');
UPDATE public.payments SET status='reversed',status_cause_id=pg_temp.n('13'),return_code='R01',reversed_at=now(),reversed_by=pg_temp.op(),reversed_reason='bank' WHERE id=pg_temp.n('11');
SELECT pg_temp.refuses_at('whole leaf cannot acquire later negative child',$q$SELECT pg_temp.rev(pg_temp.n('14'),pg_temp.n('11'),pg_temp.n('13'),'adjustment',-100,'2026-03-12')$q$,'23001','has ended');
SELECT pg_temp.rcpt(pg_temp.n('20'),100,'2026-03-10');
SELECT pg_temp.fromr(pg_temp.n('21'),pg_temp.n('22'),pg_temp.n('20'),pg_temp.k('c1'),100);
SELECT pg_temp.rev(pg_temp.n('23'),pg_temp.n('21'),pg_temp.n('22'),'adjustment',100,'2026-03-11');
SELECT pg_temp.rev(pg_temp.n('24'),pg_temp.n('21'),pg_temp.n('23'),'adjustment',-100,'2026-03-12');
SELECT pg_temp.rev(pg_temp.n('25'),pg_temp.n('21'),pg_temp.n('22'),'adjustment',100,'2026-03-13');
SELECT pg_temp.refuses_at('negative child of named row even with whole replaced at root',$q$UPDATE public.payments SET status='reversed',status_cause_id=pg_temp.n('23'),return_code='R01',reversed_at=now(),reversed_by=pg_temp.op(),reversed_reason='bank' WHERE id=pg_temp.n('21')$q$,'23514','nothing is filed beneath it');
UPDATE public.payments SET status='reversed',status_cause_id=pg_temp.n('25'),return_code='R01',reversed_at=now(),reversed_by=pg_temp.op(),reversed_reason='bank' WHERE id=pg_temp.n('21');
SELECT pg_temp.rcpt(pg_temp.n('30'),100,'2026-03-10');
SELECT pg_temp.fromr(pg_temp.n('31'),pg_temp.n('32'),pg_temp.n('30'),pg_temp.k('c1'),100);
SELECT pg_temp.rev(pg_temp.n('33'),pg_temp.n('31'),pg_temp.n('32'),'adjustment',100,'2026-03-11');
SELECT pg_temp.rev(pg_temp.n('34'),pg_temp.n('31'),pg_temp.n('33'),'adjustment',-100,'2026-03-12');
SELECT pg_temp.rev(pg_temp.n('35'),pg_temp.n('31'),pg_temp.n('34'),'nsf',100,'2026-03-13');
UPDATE public.payments SET status='reversed',status_cause_id=pg_temp.n('33'),return_code='R01',reversed_at=now(),reversed_by=pg_temp.op(),reversed_reason='bank' WHERE id=pg_temp.n('31');
SELECT pg_temp.ok('all typed NSF beneath undo is allowed: share zero',public.suspense_misposted_share(pg_temp.n('31'))=0);
SELECT pg_temp.rcpt(pg_temp.n('40'),100,'2026-03-10');
SELECT pg_temp.fromr(pg_temp.n('41'),pg_temp.n('42'),pg_temp.n('40'),pg_temp.k('c1'),100);
SELECT pg_temp.rev(pg_temp.n('43'),pg_temp.n('41'),pg_temp.n('42'),'nsf',100,'2026-03-11');
SELECT pg_temp.refuses_at('named cause typed NSF rejected before r12 rule',$q$UPDATE public.payments SET status='reversed',status_cause_id=pg_temp.n('43'),return_code='R01',reversed_at=now(),reversed_by=pg_temp.op(),reversed_reason='bank' WHERE id=pg_temp.n('41')$q$,'23503','move to reversed names the row');
SELECT pg_temp.rcpt(pg_temp.n('50'),100,'2026-03-10');
SELECT pg_temp.fromr(pg_temp.n('51'),pg_temp.n('52'),pg_temp.n('50'),pg_temp.k('c1'),100);
SELECT pg_temp.rev(pg_temp.n('53'),pg_temp.n('51'),pg_temp.n('52'),'adjustment',100,'2026-03-11');
SELECT pg_temp.rev(pg_temp.n('54'),pg_temp.n('51'),pg_temp.n('53'),'adjustment',-100,'2026-03-11');
SELECT pg_temp.rev(pg_temp.n('55'),pg_temp.n('51'),pg_temp.n('54'),'adjustment',100,'2026-03-11');
SELECT pg_temp.rev(pg_temp.n('56'),pg_temp.n('51'),pg_temp.n('55'),'adjustment',-100,'2026-03-12');
SELECT pg_temp.rev(pg_temp.n('57'),pg_temp.n('51'),pg_temp.n('56'),'adjustment',60,'2026-03-13');
SELECT pg_temp.rev(pg_temp.n('58'),pg_temp.n('51'),pg_temp.n('56'),'adjustment',40,'2026-03-14');
SELECT pg_temp.refuses_at('another level down and later-dated rows still reject code',$q$UPDATE public.payments SET status='reversed',status_cause_id=pg_temp.n('53'),return_code='R01',reversed_at=now(),reversed_by=pg_temp.op(),reversed_reason='bank' WHERE id=pg_temp.n('51')$q$,'23514','nothing is filed beneath it');
RESET ROLE;
SET LOCAL session_replication_role=replica;
SELECT pg_temp.refuses_at('owner replica cannot bypass same descendant rule',$q$UPDATE public.payments SET status='reversed',status_cause_id=pg_temp.n('53'),return_code='R01',reversed_at=now(),reversed_by=pg_temp.op(),reversed_reason='bank' WHERE id=pg_temp.n('51')$q$,'23514','nothing is filed beneath it');
SET LOCAL session_replication_role=origin;
SELECT pg_temp.rcpt(pg_temp.n('60'),100,'2026-03-10');
SELECT pg_temp.refuses_at('multi-row birth includes posted',$q$INSERT INTO public.payments(tenant_id,payment_number,customer_id,payment_date,amount,payment_method,channel,source_system,check_number,suspense_receipt_id,suspense_resolution_reason,suspense_resolved_by,status) VALUES (pg_temp.t1(),'birth1',pg_temp.k('c1'),'2026-03-10',50,'check','lockbox','bank_lockbox','CHK-2560',pg_temp.n('60'),'identified',pg_temp.op(),'pending'),(pg_temp.t1(),'birth2',pg_temp.k('c1'),'2026-03-10',50,'check','lockbox','bank_lockbox','CHK-2560',pg_temp.n('60'),'identified',pg_temp.op(),'posted')$q$,'23514','load it pending and move it');
DO $probe$
DECLARE payload text;
BEGIN
 payload:=format(E'%s,copy-born-posted,%s,2026-03-10,50,check,lockbox,bank_lockbox,CHK-2560,%s,identified,%s,posted\n',pg_temp.t1(),pg_temp.k('c1'),pg_temp.n('60'),pg_temp.op());
 BEGIN
 EXECUTE format('COPY public.payments(tenant_id,payment_number,customer_id,payment_date,amount,payment_method,channel,source_system,check_number,suspense_receipt_id,suspense_resolution_reason,suspense_resolved_by,status) FROM PROGRAM %L WITH (FORMAT csv)','printf '||quote_literal(payload));
 RAISE EXCEPTION 'unexpected COPY success';
 EXCEPTION WHEN OTHERS THEN
 RAISE NOTICE 'COPY born posted SQLSTATE=% message=%',SQLSTATE,SQLERRM;
 IF SQLSTATE<>'23514' OR strpos(SQLERRM,'load it pending and move it')=0 THEN RAISE; END IF;
 END;
END $probe$;
SELECT pg_temp.ok('failed multi-row and COPY births leave all 100 held',pg_temp.held(pg_temp.n('60'))=100);
ROLLBACK;
