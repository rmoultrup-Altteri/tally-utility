-- PREDICTED; not executed by Codex. Fresh clone, frozen r2, owner connection.
\set ON_ERROR_STOP on
-- ============================================================================
-- BATTERY v5.4.2-23 — cash: reversals, positions, payment application,
-- credits from overpayment (2026-10-16)
-- Run: psql -U tally -d <db-with-patch> -v ON_ERROR_STOP=1 -f battery-23.sql
-- One transaction, rolled back. Fixtures as the owner; every guard the
-- application meets is exercised as tally_app under app.user_id.
-- Each row names its requirement in
-- application/wave2-build-2026-10-15/v5.4.2-23-design.md.
--
--   X  reversals (X1-X4)          M  positions, write-once, status (M1-M4)
--   A  application (A1-A6)        C  overpayment credits (C1, C2)
--   T  the within-bill order (A5) F  the freeze on applications
--   I  invariants
-- What one transaction cannot show (READ COMMITTED pins, recorded order
-- across transactions, two writers on one source or line) is in
-- races/cash-23.sh.
-- ============================================================================
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
-- snap(): a calculation snapshot of a bill at (p_valid, p_rec), its lines as they are.
CREATE FUNCTION pg_temp.snap(p_inv uuid, p_valid date, p_rec timestamptz) RETURNS void LANGUAGE plpgsql AS $$
DECLARE i public.invoices%ROWTYPE;
BEGIN
  SELECT * INTO i FROM public.invoices WHERE id = p_inv;
  INSERT INTO public.invoice_calculation_snapshots
    (tenant_id, invoice_id, billing_run_id, valid_at, recorded_at, snapshot_schema_version, formula_version,
     rate_inputs, gas_factors, wna_inputs, tax_inputs, read_inputs, customer_inputs, period_inputs, line_items)
  VALUES (i.tenant_id, i.id, i.billing_run_id, p_valid, p_rec, 'v1', 'bat23',
     '{"rate_schedule_id":null,"rate_schedule_version_id":null,"rate_schedule_code":null,"customer_type":null,"partial_period_policy":null,"items":[]}',
     '{"pga_factor":null,"btu_factor":null,"pressure_factor":null,"temperature_factor":null,"meter_multiplier":null,"factor_stack_intermediates":{}}',
     '{"applied":false}', '{"jurisdictions":[],"exemptions":[],"franchise_fees":[]}', '{"reads":[]}',
     jsonb_build_object('customer_id', i.customer_id, 'customer_class', null, 'location_id', i.location_id, 'premise_zones', '{}'::jsonb),
     jsonb_build_object('period_start', i.period_start, 'period_end', i.period_end, 'days_in_period', i.period_end - i.period_start + 1, 'proration_policy', null),
     (SELECT coalesce(jsonb_agg(jsonb_build_object('invoice_line_item_id', l.id, 'charge_type', l.charge_type, 'amount', l.amount)), '[]'::jsonb)
        FROM public.invoice_line_items l WHERE l.invoice_id = i.id));
END $$;
-- post(): a pending payment's posting entry (payment, or deposit for a
-- deposit; dated its payment date, at minus its amount), then the move to
-- posted naming it (r2: a payment is born pending). A payment with no
-- effective date takes its payment date as it posts (-19 P2).
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
GRANT EXECUTE ON FUNCTION pg_temp.refuses_at(text, text, text, text), pg_temp.ok(text, boolean), pg_temp.admits(text, text), pg_temp.post(uuid, uuid) TO tally_app, tally_core;

-- ------------------------------------------------------------------ fixtures
-- T1 (…23a1), T2 (…23a2). Ids: b users, c customers, d locations, 01-09
-- bills, 11-1f lines, 41-4f applications, 51-59 approvals, 61-6f payments,
-- 71-79 credits, 81-9f ledger, ab the tariff.
INSERT INTO public.tenants (id, name, slug) VALUES
  ('00000000-0000-4000-8000-0000000023a1', 'T1 City Gas', 'bat23-t1'),
  ('00000000-0000-4000-8000-0000000023a2', 'T2 Gasco', 'bat23-t2');
INSERT INTO public.users (id, tenant_id, display_name, email, role, is_active) VALUES
  ('00000000-0000-4000-8000-0000000023b1', '00000000-0000-4000-8000-0000000023a1', 'Op1', 'op1@bat23.test', 'operator', true),
  ('00000000-0000-4000-8000-0000000023b2', '00000000-0000-4000-8000-0000000023a2', 'Op2', 'op2@bat23.test', 'operator', true);
INSERT INTO public.customers (id, tenant_id, customer_number, customer_type) VALUES
  ('00000000-0000-4000-8000-0000000023c1', '00000000-0000-4000-8000-0000000023a1', 'B23-C1', 'residential'),
  ('00000000-0000-4000-8000-0000000023c2', '00000000-0000-4000-8000-0000000023a1', 'B23-C2', 'residential'),
  ('00000000-0000-4000-8000-0000000023c9', '00000000-0000-4000-8000-0000000023a2', 'B23-C9', 'residential');
-- Author-run only. Start as owner on a fresh clone with frozen r2 applied.
-- The owner creates fixtures/helpers; all tested writes below use tally_app.
CREATE FUNCTION pg_temp.uid(n integer) RETURNS uuid LANGUAGE sql IMMUTABLE AS $$
 SELECT ('c0de0000-0000-4000-8000-' || lpad(n::text,12,'0'))::uuid
$$;
CREATE FUNCTION pg_temp.attempt(label text, command text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
 EXECUTE command;
 RAISE NOTICE '%: ACCEPTED SQLSTATE=00000', label;
EXCEPTION WHEN OTHERS THEN
 RAISE NOTICE '%: SQLSTATE=% message=%', label, SQLSTATE, SQLERRM;
END $$;
CREATE FUNCTION pg_temp.entry(n integer, amt numeric, typ text, parent integer DEFAULT NULL, refkind text DEFAULT NULL, refnum integer DEFAULT NULL) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
 INSERT INTO public.account_ledger(id,tenant_id,customer_id,transaction_date,transaction_type,description,amount,reverses_ledger_entry_id,reference_type,reference_id)
 VALUES(pg_temp.uid(n),'00000000-0000-4000-8000-0000000023a1','00000000-0000-4000-8000-0000000023c1',DATE '2026-03-10',typ,'Codex r2 probe',amt,pg_temp.uid(parent),refkind,pg_temp.uid(refnum));
END $$;
CREATE FUNCTION pg_temp.pay(n integer, amt numeric, parent integer DEFAULT NULL, credit integer DEFAULT NULL, refkind text DEFAULT 'payment') RETURNS void LANGUAGE plpgsql AS $$
BEGIN
 INSERT INTO public.payments(id,tenant_id,customer_id,payment_number,payment_date,amount,payment_method,refunds_payment_id,refunds_customer_credit_id)
 VALUES(pg_temp.uid(n),'00000000-0000-4000-8000-0000000023a1','00000000-0000-4000-8000-0000000023c1','CDXR2-'||n,DATE '2026-03-10',amt,CASE WHEN amt<0 THEN 'refund' ELSE 'check' END,pg_temp.uid(parent),pg_temp.uid(credit));
 IF amt>0 THEN
  PERFORM pg_temp.entry(n+100000,-amt,'payment',NULL,refkind,n);
  UPDATE public.payments SET status='posted',status_cause_id=pg_temp.uid(n+100000),effective_date=payment_date,effective_date_method='other' WHERE id=pg_temp.uid(n);
 END IF;
END $$;
CREATE FUNCTION pg_temp.credit(n integer, amt numeric) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
 INSERT INTO public.customer_credits(id,tenant_id,customer_id,origin_type,original_amount,issued_date)
 VALUES(pg_temp.uid(n),'00000000-0000-4000-8000-0000000023a1','00000000-0000-4000-8000-0000000023c1','goodwill',amt,DATE '2026-03-10');
 PERFORM pg_temp.entry(n+100000,-amt,'credit_issued',NULL,'customer_credit',n);
END $$;
CREATE FUNCTION pg_temp.apply(n integer, amt numeric, line uuid DEFAULT '00000000-0000-4000-8000-000000002311') RETURNS void LANGUAGE plpgsql AS $$
BEGIN
 INSERT INTO public.invoice_applications(tenant_id,customer_id,invoice_id,invoice_line_item_id,payment_id,amount,applied_on,basis,applied_by,reason)
 VALUES('00000000-0000-4000-8000-0000000023a1','00000000-0000-4000-8000-0000000023c1','00000000-0000-4000-8000-000000002301',line,pg_temp.uid(n),amt,DATE '2026-03-10','operator_override','00000000-0000-4000-8000-0000000023b1','Codex probe');
END $$;
GRANT EXECUTE ON FUNCTION pg_temp.uid(integer),pg_temp.attempt(text,text),pg_temp.entry(integer,numeric,text,integer,text,integer),pg_temp.pay(integer,numeric,integer,integer,text),pg_temp.credit(integer,numeric),pg_temp.apply(integer,numeric,uuid) TO tally_app,tally_core;
SELECT set_config('app.user_id','00000000-0000-4000-8000-0000000023b1',true);
SET ROLE tally_app;


RESET ROLE;
INSERT INTO public.payments(id,tenant_id,customer_id,payment_number,payment_date,amount,payment_method)
VALUES(pg_temp.uid(1),'00000000-0000-4000-8000-0000000023a1','00000000-0000-4000-8000-0000000023c1','CDXR2-isolation',DATE '2026-03-10',100,'check');
SELECT pg_temp.entry(100001,-100,'payment',NULL,'payment',1);
SET ROLE tally_app;
SELECT pg_temp.attempt('isolation: valid pending to posted cause', $$UPDATE public.payments SET status='posted',status_cause_id=pg_temp.uid(100001),effective_date=payment_date,effective_date_method='other' WHERE id=pg_temp.uid(1)$$);
SELECT pg_temp.attempt('isolation: direct draw pin', $$SELECT public.check_cash_source('payment',pg_temp.uid(1),now(),'application',CURRENT_DATE)$$);
SELECT pg_temp.attempt('isolation: reversal pin', $$SELECT pg_temp.entry(201,10,'adjustment',100001)$$);

RESET ROLE;
ROLLBACK;
