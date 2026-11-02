-- Codex r8: AUTHOR RUN ONLY, unexecuted. Run as owner on a fresh clone
-- with frozen r8 strictly applied and clone TEMP revoked from PUBLIC, tally_app, tally_core.
-- No role DDL; all work rolls back.
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL statement_timeout = '180s';
INSERT INTO public.tenants (id,name,slug) VALUES ('00000000-0000-4000-8000-0000000023a1','Codex r8','codex-r8');
INSERT INTO public.users (id,tenant_id,display_name,email,role,is_active) VALUES
('00000000-0000-4000-8000-0000000023b1','00000000-0000-4000-8000-0000000023a1','Operator','r8@probe.test','operator',true);
INSERT INTO public.customers (id,tenant_id,customer_number,customer_type) VALUES
('00000000-0000-4000-8000-0000000023c5','00000000-0000-4000-8000-0000000023a1','R7-C5','residential');
CREATE FUNCTION pg_temp.hpost(p_pay uuid, p_entry uuid, p_ago interval) RETURNS void LANGUAGE plpgsql AS $$
DECLARE p public.payments%ROWTYPE;
BEGIN
  SELECT * INTO p FROM public.payments WHERE id = p_pay;
  INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reference_type, reference_id, created_at)
  VALUES (p_entry, p.tenant_id, p.customer_id, p.payment_date,
          CASE WHEN p.refunds_payment_id IS NOT NULL OR p.refunds_customer_credit_id IS NOT NULL THEN 'refund' ELSE 'payment' END,
          p.payment_number || ' posted', -p.amount, 'payment', p.id, now() - p_ago);
  UPDATE public.payments SET status = 'posted', status_cause_id = p_entry, effective_date = payment_date, effective_date_method = 'other',
         status_recorded_at = now() - p_ago WHERE id = p_pay;
END $$;
CREATE FUNCTION pg_temp.hpay(p_id uuid, p_entry uuid, p_amount numeric, p_ago interval) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO public.payments (id, tenant_id, payment_number, customer_id, payment_date, amount, payment_method, created_at)
  VALUES (p_id, '00000000-0000-4000-8000-0000000023a1', 'B23-X' || right(p_id::text, 2), '00000000-0000-4000-8000-0000000023c5', DATE '2026-03-10', p_amount, 'check', now() - p_ago);
  PERFORM pg_temp.hpost(p_id, p_entry, p_ago);
END $$;
CREATE FUNCTION pg_temp.hcredit(p_id uuid, p_appr uuid, p_pay uuid, p_amount numeric, p_ago interval) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO public.customer_credit_approvals (id, tenant_id, customer_id, payment_id, amount, approved_by, created_at)
  VALUES (p_appr, '00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c5', p_pay, p_amount, '00000000-0000-4000-8000-0000000023b1', now() - p_ago);
  INSERT INTO public.customer_credits (id, tenant_id, customer_id, origin_type, original_amount, issued_date, source_payment_id, approval_id, created_at)
  VALUES (p_id, '00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c5', 'overpayment', p_amount, DATE '2026-03-11', p_pay, p_appr, now() - p_ago);
END $$;
-- hrefund(): a refund of payment p_pay or credit p_credit, posted by p_entry.
CREATE FUNCTION pg_temp.hrefund(p_id uuid, p_entry uuid, p_pay uuid, p_credit uuid, p_amount numeric, p_ago interval) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO public.payments (id, tenant_id, payment_number, customer_id, payment_date, amount, payment_method, refunds_payment_id, refunds_customer_credit_id, created_at)
  VALUES (p_id, '00000000-0000-4000-8000-0000000023a1', 'B23-X' || right(p_id::text, 2) || 'R', '00000000-0000-4000-8000-0000000023c5', DATE '2026-03-12', -p_amount, 'refund', p_pay, p_credit, now() - p_ago);
  PERFORM pg_temp.hpost(p_id, p_entry, p_ago);
END $$;
CREATE FUNCTION pg_temp.hrow(p_id uuid, p_parent uuid, p_amount numeric, p_ago interval) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reverses_ledger_entry_id, created_at)
  VALUES (p_id, '00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c5', DATE '2026-03-13', 'adjustment', 'x', p_amount, p_parent, now() - p_ago);
END $$;
-- hback(): refund p_refund's check comes back (an nsf row under its posting
-- row p_entry, then the move to nsf), p_ago before now.
CREATE FUNCTION pg_temp.hback(p_refund uuid, p_entry uuid, p_row uuid, p_ago interval) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reverses_ledger_entry_id, created_at)
  SELECT p_row, l.tenant_id, l.customer_id, DATE '2026-03-14', 'nsf', 'x came back', -l.amount, l.id, now() - p_ago FROM public.account_ledger l WHERE l.id = p_entry;
  UPDATE public.payments SET status = 'nsf', nsf_date = DATE '2026-03-14', status_cause_id = p_row, status_recorded_at = now() - p_ago WHERE id = p_refund;
END $$;
CREATE FUNCTION pg_temp.z(p text) RETURNS uuid LANGUAGE sql IMMUTABLE AS $$ SELECT ('00000000-0000-4000-8000-0000000032' || p)::uuid $$;
-- hrefund_on(): hrefund() dated p_on (a reissue's refund, after the reissue).
CREATE FUNCTION pg_temp.hrefund_on(p_id uuid, p_entry uuid, p_pay uuid, p_credit uuid, p_amount numeric, p_ago interval, p_on date) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO public.payments (id, tenant_id, payment_number, customer_id, payment_date, amount, payment_method, refunds_payment_id, refunds_customer_credit_id, created_at)
  VALUES (p_id, '00000000-0000-4000-8000-0000000023a1', 'B23-Z' || right(p_id::text, 2) || 'R', '00000000-0000-4000-8000-0000000023c5', p_on, -p_amount, 'refund', p_pay, p_credit, now() - p_ago);
  PERFORM pg_temp.hpost(p_id, p_entry, p_ago);
END $$;
-- hreissue(): a refund_reissue credit of p_amount carrying refund p_refund.
CREATE FUNCTION pg_temp.hreissue(p_id uuid, p_refund uuid, p_amount numeric, p_ago interval) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO public.customer_credits (id, tenant_id, customer_id, origin_type, original_amount, issued_date, reissues_refund_id, created_at)
  VALUES (p_id, '00000000-0000-4000-8000-0000000023a1', '00000000-0000-4000-8000-0000000023c5', 'refund_reissue', p_amount, DATE '2026-03-14', p_refund, now() - p_ago);
END $$;
-- hremit(): p_amount of credit p_credit remitted to the state; hescheat():
-- then its move to escheated.
CREATE FUNCTION pg_temp.hremit(p_credit uuid, p_event uuid, p_amount numeric, p_ago interval) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO public.escheatment_events (id, tenant_id, customer_credit_id, customer_id, event_type, amount_related, event_date, created_at)
  VALUES (p_event, '00000000-0000-4000-8000-0000000023a1', p_credit, '00000000-0000-4000-8000-0000000023c5', 'escheated_to_state', p_amount, now() - p_ago, now() - p_ago);
END $$;
CREATE FUNCTION pg_temp.hescheat(p_credit uuid, p_event uuid, p_ago interval) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  UPDATE public.customer_credits SET status = 'escheated', status_cause_id = p_event, status_recorded_at = now() - p_ago WHERE id = p_credit;
END $$;
-- hbounce(): payment p_pay's posting entry p_entry taken back in full by an
-- nsf row p_row, and the move to nsf.
CREATE FUNCTION pg_temp.hbounce(p_pay uuid, p_entry uuid, p_row uuid, p_ago interval) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reverses_ledger_entry_id, created_at)
  SELECT p_row, l.tenant_id, l.customer_id, DATE '2026-03-15', 'nsf', 'the payment bounced', -l.amount, l.id, now() - p_ago FROM public.account_ledger l WHERE l.id = p_entry;
  UPDATE public.payments SET status = 'nsf', nsf_date = DATE '2026-03-15', status_cause_id = p_row, status_recorded_at = now() - p_ago WHERE id = p_pay;
END $$;

CREATE FUNCTION pg_temp.attempt(p_credit uuid, p_pay uuid, p_amount numeric) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  BEGIN
    INSERT INTO public.payments (tenant_id,payment_number,customer_id,payment_date,amount,payment_method,refunds_customer_credit_id,refunds_payment_id)
    VALUES ('00000000-0000-4000-8000-0000000023a1','TRY-'||gen_random_uuid(),'00000000-0000-4000-8000-0000000023c5',CURRENT_DATE,-p_amount,'refund',p_credit,p_pay);
    SET CONSTRAINTS ALL IMMEDIATE;
    RAISE NOTICE 'DRAW amount=% admitted SQLSTATE=00000',p_amount;
    RAISE EXCEPTION USING ERRCODE='P0099', MESSAGE='probe rollback of admitted draw';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'DRAW amount=% caught SQLSTATE=% message=%',p_amount,SQLSTATE,SQLERRM;
  END;
END $$;
CREATE FUNCTION pg_temp.positions(p_pay uuid,p_root uuid) RETURNS void LANGUAGE plpgsql AS $$
DECLARE r record;
BEGIN
  FOR r IN SELECT * FROM public.payment_position_as_of(p_pay,DATE '9999-12-31',clock_timestamp()) LOOP
    RAISE NOTICE 'PAYMENT % position=%',p_pay,row_to_json(r);
  END LOOP;
  FOR r IN SELECT c.id,c.status,x.remaining,c.original_amount-coalesce(a.absorbed,0)-d.applied-d.refunded-d.given_up-d.carried AS own_remaining
    FROM public.overpayment_family(p_root) f JOIN public.customer_credits c ON c.id=f.id
    CROSS JOIN LATERAL public.customer_credit_position_as_of(c.id,DATE '9999-12-31',clock_timestamp()) x
    CROSS JOIN LATERAL public.customer_credit_draws_as_of(c.id,DATE '9999-12-31',clock_timestamp()) d
    LEFT JOIN public.overpayment_absorbed_as_of(p_root,DATE '9999-12-31',clock_timestamp(),false) a ON a.credit_id=c.id
    ORDER BY c.created_at,c.id LOOP
    RAISE NOTICE 'CREDIT %',row_to_json(r);
  END LOOP;
END $$;


-- B1: Q5's return needs a carry even when the family's net remains negative.
-- Run the 50 control and the 60 variant in independently rolled-back subtransactions.
DO $$
DECLARE takeback numeric; carry numeric; phase text; failed boolean;
BEGIN
  FOREACH takeback IN ARRAY ARRAY[50::numeric,60::numeric] LOOP
    BEGIN
      phase := 'setup';
      SET CONSTRAINTS ALL DEFERRED;
      PERFORM pg_temp.hpay(pg_temp.z('01'),pg_temp.z('11'),100,interval '20 hours');
      PERFORM pg_temp.hcredit(pg_temp.z('21'),pg_temp.z('31'),pg_temp.z('01'),30,interval '19 hours');
      PERFORM pg_temp.hrefund(pg_temp.z('02'),pg_temp.z('12'),NULL,pg_temp.z('21'),20,interval '18 hours');
      PERFORM pg_temp.hrefund(pg_temp.z('03'),pg_temp.z('13'),pg_temp.z('01'),NULL,70,interval '17 hours');
      PERFORM pg_temp.hremit(pg_temp.z('21'),pg_temp.z('41'),10,interval '16 hours');
      PERFORM pg_temp.hescheat(pg_temp.z('21'),pg_temp.z('41'),interval '15 hours');
      SET CONSTRAINTS ALL IMMEDIATE;
      PERFORM pg_temp.hrow(pg_temp.z('14'),pg_temp.z('11'),takeback,interval '14 hours');
      PERFORM pg_temp.hrow(pg_temp.z('15'),pg_temp.z('14'),-30,interval '13 hours');
      SET CONSTRAINTS ALL IMMEDIATE;
      phase := 'bank return';
      SET CONSTRAINTS ALL DEFERRED;
      PERFORM pg_temp.hback(pg_temp.z('02'),pg_temp.z('12'),pg_temp.z('16'),interval '12 hours');
      RAISE NOTICE 'takeback=%: bank return staged; own K=%',takeback,
        public.customer_credit_own_remaining_as_of(pg_temp.z('21'),DATE '9999-12-31',clock_timestamp());
      PERFORM pg_temp.positions(pg_temp.z('01'),pg_temp.z('21'));
      -- The no-carry path must fail settlement; catch locally to preserve the staged return.
      BEGIN
        SET CONSTRAINTS ALL IMMEDIATE;
        RAISE NOTICE 'takeback=%: no-carry settlement admitted SQLSTATE=00000',takeback;
      EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'takeback=%: no-carry settlement caught SQLSTATE=% message=%',takeback,SQLSTATE,SQLERRM;
      END;
      SET CONSTRAINTS ALL DEFERRED;
      -- Each amount is an independent alternative, not cumulative.
      FOREACH carry IN ARRAY ARRAY[10::numeric,20::numeric,20.01::numeric] LOOP
        BEGIN
          phase := 'reissue';
          PERFORM pg_temp.hreissue(pg_temp.z('22'),pg_temp.z('02'),carry,interval '11 hours');
          SET CONSTRAINTS ALL IMMEDIATE;
          RAISE NOTICE 'takeback=% carry=%: ADMITTED SQLSTATE=00000',takeback,carry;
          PERFORM pg_temp.positions(pg_temp.z('01'),pg_temp.z('21'));
          IF carry = 20 THEN
            -- External money still cannot escape a zero/negative pot.
            PERFORM pg_temp.attempt(pg_temp.z('22'),NULL,0.01);
            -- Actual later return of the other refund makes the carried money visible.
            PERFORM pg_temp.hback(pg_temp.z('03'),pg_temp.z('13'),pg_temp.z('17'),interval '10 hours');
            SET CONSTRAINTS ALL IMMEDIATE;
            PERFORM pg_temp.positions(pg_temp.z('01'),pg_temp.z('21'));
          END IF;
          RAISE EXCEPTION USING ERRCODE='P0099', MESSAGE='rollback successful alternative';
        EXCEPTION WHEN OTHERS THEN
          RAISE NOTICE 'takeback=% carry=% phase=% caught SQLSTATE=% message=%',takeback,carry,phase,SQLSTATE,SQLERRM;
        END;
      END LOOP;
      RAISE EXCEPTION USING ERRCODE='P0099', MESSAGE='rollback scenario including pending settlement';
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'scenario takeback=% phase=% caught SQLSTATE=% message=%',takeback,phase,SQLSTATE,SQLERRM;
    END;
  END LOOP;
END $$;
ROLLBACK;
