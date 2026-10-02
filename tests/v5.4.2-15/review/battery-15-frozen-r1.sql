-- ============================================================================
-- BATTERY v5.4.2-15 — deposits at parity (2026-10-02)
-- Run: psql -U tally -d <db-with-patch> -v ON_ERROR_STOP=1 -f battery-15.sql
-- One transaction, rolled back. Negative cases inside DO blocks that check
-- the SQLSTATE. Written as tally_app except fixtures and the owner-level
-- checks a group names. TWO tenants.
--
-- What it proves: the schema REPRESENTS deposit law for any state (group Z
-- stores a fictional state, ZZ, unlike Texas, with no DDL), RECORDS what the
-- core decided under which rule row, and PROTECTS the deposit records. It
-- does not test law: the database no longer evaluates it — group L proves
-- the old Texas refusals are gone (application/deposits-rules-for-the-core.md
-- holds them as the core's scenarios).
--
--   A  the law tables are platform-held        (sections 2-3)
--   Z  a second state fits without DDL         (sections 2-3)
--   B  interest rates: the utility's and the law's (section 4)
--   C  a deposit records what it was decided under (section 5)
--   D  waiver determinations                   (section 6)
--   E  the sub-ledger's arithmetic             (section 8)
--   L  the Texas law is gone from the database (sections 5, 8, 9)
--   F  the return-due record                   (section 7)
--   G  surfaces, tenancy, the AC-32 tail       (sections 9, 11)
-- "Evidence only in its due row's transaction" needs two transactions:
-- evidence-txn-15.sh.
-- ============================================================================
BEGIN;
SET CONSTRAINTS ALL IMMEDIATE;

-- ------------------------------------------------------------------ fixtures
INSERT INTO public.tenants (id, name, slug) VALUES
  ('00000000-0000-4000-8000-0000000015a1', 'T1 Gasco', 'bat15-t1'),
  ('00000000-0000-4000-8000-0000000015a2', 'T2 Gasco', 'bat15-t2');
INSERT INTO public.users (id, tenant_id, display_name, email, role) VALUES
  ('00000000-0000-4000-8000-0000000015b1', '00000000-0000-4000-8000-0000000015a1', 'Op1', 'op1@bat15.test', 'operator'),
  ('00000000-0000-4000-8000-0000000015b2', '00000000-0000-4000-8000-0000000015a2', 'Op2', 'op2@bat15.test', 'operator');
INSERT INTO public.customers (id, tenant_id, customer_number, customer_type) VALUES
  ('00000000-0000-4000-8000-0000000015c1', '00000000-0000-4000-8000-0000000015a1', 'B15-C1', 'residential'),
  ('00000000-0000-4000-8000-0000000015c2', '00000000-0000-4000-8000-0000000015a1', 'B15-C2', 'residential'),
  ('00000000-0000-4000-8000-0000000015c3', '00000000-0000-4000-8000-0000000015a1', 'B15-C3', 'commercial'),
  ('00000000-0000-4000-8000-0000000015c9', '00000000-0000-4000-8000-0000000015a2', 'B15-C9', 'residential');
INSERT INTO public.service_locations (id, tenant_id, customer_id, location_number, address_line1, city, state, zip) VALUES
  ('00000000-0000-4000-8000-0000000015d1', '00000000-0000-4000-8000-0000000015a1', '00000000-0000-4000-8000-0000000015c1', 'L1', '1 Main', 'Austin', 'TX', '78701'),
  ('00000000-0000-4000-8000-0000000015d2', '00000000-0000-4000-8000-0000000015a1', '00000000-0000-4000-8000-0000000015c2', 'L2', '2 Main', 'Austin', 'TX', '78702');
INSERT INTO public.billing_runs (id, tenant_id, run_number, billing_period, period_start, period_end) VALUES
  ('00000000-0000-4000-8000-0000000015f1', '00000000-0000-4000-8000-0000000015a1', 'R-B15', '2026-01', DATE '2025-11-01', DATE '2026-12-31');
-- Bills (drafts are enough to cite): C1 before and after posting, C2 one.
INSERT INTO public.invoices (id, tenant_id, invoice_number, billing_run_id, customer_id, location_id, invoice_type,
                             invoice_date, billing_period, period_start, period_end, due_date, amount_due) VALUES
  ('00000000-0000-4000-8000-0000000015e0', '00000000-0000-4000-8000-0000000015a1', 'B15-I0', '00000000-0000-4000-8000-0000000015f1', '00000000-0000-4000-8000-0000000015c1', '00000000-0000-4000-8000-0000000015d1', 'regular', DATE '2025-12-01', '2025-11', DATE '2025-11-01', DATE '2025-11-30', DATE '2025-12-21', 50),
  ('00000000-0000-4000-8000-0000000015e1', '00000000-0000-4000-8000-0000000015a1', 'B15-I1', '00000000-0000-4000-8000-0000000015f1', '00000000-0000-4000-8000-0000000015c1', '00000000-0000-4000-8000-0000000015d1', 'regular', DATE '2026-03-01', '2026-02', DATE '2026-02-01', DATE '2026-02-28', DATE '2026-03-21', 50),
  ('00000000-0000-4000-8000-0000000015e2', '00000000-0000-4000-8000-0000000015a1', 'B15-I2', '00000000-0000-4000-8000-0000000015f1', '00000000-0000-4000-8000-0000000015c1', '00000000-0000-4000-8000-0000000015d1', 'regular', DATE '2026-04-01', '2026-03', DATE '2026-03-01', DATE '2026-03-31', DATE '2026-04-21', 50),
  ('00000000-0000-4000-8000-0000000015e8', '00000000-0000-4000-8000-0000000015a1', 'B15-I8', '00000000-0000-4000-8000-0000000015f1', '00000000-0000-4000-8000-0000000015c2', '00000000-0000-4000-8000-0000000015d2', 'regular', DATE '2026-04-01', '2026-03', DATE '2026-03-01', DATE '2026-03-31', DATE '2026-04-21', 50);

CREATE TEMP TABLE b15 (k text PRIMARY KEY, id uuid);
GRANT SELECT, INSERT, UPDATE ON b15 TO tally_app;
CREATE FUNCTION pg_temp.id(p_k text) RETURNS uuid LANGUAGE sql STABLE AS $$ SELECT id FROM b15 WHERE k = p_k $$;
GRANT EXECUTE ON FUNCTION pg_temp.id(text) TO tally_app;
-- r(): the open rule row for a state, class and basis (gas).
CREATE FUNCTION pg_temp.r(p_state text, p_class text, p_basis text) RETURNS uuid LANGUAGE sql STABLE AS $$
  SELECT id FROM public.deposit_rules
   WHERE state_code = p_state AND service_type = 'gas' AND customer_class = p_class AND basis = p_basis AND effective_to IS NULL
$$;
GRANT EXECUTE ON FUNCTION pg_temp.r(text, text, text) TO tally_app;
-- dep(): a deposit as the core would record it, under the open rule for its
-- state, class and basis; the cap filled in exactly when the rule has one.
CREATE FUNCTION pg_temp.dep(p_k text, p_cust uuid, p_basis text, p_class text, p_instr text, p_principal numeric,
                            p_posted date, p_state text DEFAULT 'TX') RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE v_rule public.deposit_rules%ROWTYPE; v_id uuid; v_t uuid;
BEGIN
  SELECT tenant_id INTO v_t FROM public.customers WHERE id = p_cust;
  SELECT * INTO v_rule FROM public.deposit_rules WHERE id = pg_temp.r(p_state, p_class, p_basis);
  INSERT INTO public.deposits (tenant_id, customer_id, basis, trigger_basis, instrument, instrument_reference, principal, posted_on,
                               state_code, service_type, customer_class, rule_id, cap_amount, cap_basis_kind, cap_basis_amount, decided_by)
  VALUES (v_t, p_cust, p_basis, CASE WHEN p_basis = 'additional_trigger' THEN 'nsf' END, p_instr,
          CASE WHEN p_instr <> 'cash' THEN 'REF-' || p_k END, p_principal, p_posted,
          p_state, 'gas', p_class, v_rule.id,
          CASE WHEN v_rule.cap_kind <> 'none' THEN p_principal END,
          CASE WHEN v_rule.cap_kind <> 'none' THEN v_rule.cap_kind END,
          CASE WHEN v_rule.cap_kind IN ('fraction_of_annual_billing', 'months_of_billing') THEN p_principal * 6 END,
          'core-test')
  RETURNING id INTO v_id;
  INSERT INTO b15 VALUES (p_k, v_id) ON CONFLICT (k) DO UPDATE SET id = EXCLUDED.id;
  RETURN v_id;
END $$;
GRANT EXECUTE ON FUNCTION pg_temp.dep(text, uuid, text, text, text, numeric, date, text) TO tally_app;
-- acc(): an accrual citing the deposit's rule and a rate row.
CREATE FUNCTION pg_temp.acc(p_dep uuid, p_rate uuid, p_from date, p_to date, p_amount numeric, p_on date) RETURNS void
LANGUAGE sql AS $$
  INSERT INTO public.deposit_events (tenant_id, deposit_id, event_type, amount, effective_on, period_start, period_end,
                                     rate_applied, principal_basis, rate_id, rule_id, calculated_by)
  SELECT d.tenant_id, d.id, 'interest_accrued', p_amount, p_on, p_from, p_to,
         (SELECT annual_rate FROM public.deposit_interest_rates WHERE id = p_rate), d.principal, p_rate, d.rule_id, 'core-test'
    FROM public.deposits d WHERE d.id = p_dep
$$;
GRANT EXECUTE ON FUNCTION pg_temp.acc(uuid, uuid, date, date, numeric, date) TO tally_app;
-- ev(): any other event.
CREATE FUNCTION pg_temp.ev(p_dep uuid, p_type text, p_amount numeric, p_on date, p_due uuid DEFAULT NULL, p_reason text DEFAULT NULL) RETURNS void
LANGUAGE sql AS $$
  INSERT INTO public.deposit_events (tenant_id, deposit_id, event_type, amount, effective_on, return_due_id, reason)
  SELECT d.tenant_id, d.id, p_type, p_amount, p_on, p_due, p_reason FROM public.deposits d WHERE d.id = p_dep
$$;
GRANT EXECUTE ON FUNCTION pg_temp.ev(uuid, text, numeric, date, uuid, text) TO tally_app;
-- due(): a return-due row with fixed id (no evidence; the caller adds it).
CREATE FUNCTION pg_temp.due(p_id uuid, p_dep uuid, p_on date, p_supersedes uuid DEFAULT NULL, p_rule uuid DEFAULT NULL) RETURNS void
LANGUAGE sql AS $$
  INSERT INTO public.deposit_return_due (id, tenant_id, deposit_id, rule_id, due_on, supersedes_due_id, inputs, inputs_fingerprint, calculated_by)
  SELECT p_id, d.tenant_id, d.id, coalesce(p_rule, d.rule_id), p_on, p_supersedes, '{"bills": 12}', 'fp-' || left(p_id::text, 8), 'core-test'
    FROM public.deposits d WHERE d.id = p_dep
$$;
GRANT EXECUTE ON FUNCTION pg_temp.due(uuid, uuid, date, uuid, uuid) TO tally_app;
CREATE FUNCTION pg_temp.evid(p_due uuid, p_reason text, p_invoice uuid, p_class text, p_event uuid) RETURNS void
LANGUAGE sql AS $$
  INSERT INTO public.deposit_return_due_evidence (tenant_id, due_id, reason_code, invoice_id, classification, customer_state_event_id)
  SELECT r.tenant_id, r.id, p_reason, p_invoice, p_class, p_event FROM public.deposit_return_due r WHERE r.id = p_due
$$;
GRANT EXECUTE ON FUNCTION pg_temp.evid(uuid, text, uuid, text, uuid) TO tally_app;


-- ============================================================ A. law tables
SET LOCAL app.user_id = '00000000-0000-4000-8000-0000000015b1';
SET ROLE tally_app;
DO $$ DECLARE n int; m int; BEGIN
  SELECT count(*) INTO n FROM public.deposit_rules WHERE state_code = 'TX' AND service_type = 'gas';
  SELECT count(*) INTO m FROM public.deposit_bases;
  IF n <> 8 OR m <> 5 THEN RAISE EXCEPTION 'FAIL A1: expected 8 TX gas rules and 5 bases, read % and %', n, m; END IF;
  IF (SELECT count(*) FROM public.deposit_rules WHERE basis = 'legacy_unknown') <> 0 THEN
    RAISE EXCEPTION 'FAIL A1: a rule row exists for legacy_unknown';
  END IF;
  RAISE NOTICE 'PASS A1: the application reads the law (8 TX gas rows: 4 bases x 2 classes; none for legacy_unknown)';
END $$;
DO $$ DECLARE r record; BEGIN
  SELECT * INTO r FROM public.deposit_rules WHERE id = pg_temp.r('TX', 'residential', 'credit_evaluation');
  IF NOT (r.waivable AND r.cap_kind = 'fraction_of_annual_billing' AND r.cap_divisor = 6 AND r.cap_scope = 'per_deposit'
          AND r.interest_bearing_instruments = ARRAY['cash'] AND r.interest_min_hold_days = 30 AND r.interest_retroactive
          AND r.interest_method = 'simple' AND r.interest_day_count = 'actual_365' AND r.interest_credit_cadence = 'at_refund'
          AND r.refund_mandatory AND r.refund_after_count = 12 AND r.refund_measure = 'bills' AND r.refund_max_delinquencies = 2
          AND r.refund_disqualify_on_disconnect AND r.refund_on_account_close AND r.refund_obligation_vests IS NULL
          AND r.return_mandatory_instruments = ARRAY['cash']) THEN
    RAISE EXCEPTION 'FAIL A2: the TX residential credit-evaluation row does not carry -06''s law: %', row_to_json(r);
  END IF;
  SELECT * INTO r FROM public.deposit_rules WHERE id = pg_temp.r('TX', 'non_residential', 'tariff');
  IF r.cap_kind <> 'none' OR NOT r.refund_mandatory THEN RAISE EXCEPTION 'FAIL A2: TX non-residential row wrong'; END IF;
  SELECT * INTO r FROM public.deposit_rules WHERE id = pg_temp.r('TX', 'residential', 'adequate_assurance_366');
  IF r.waivable OR r.refund_mandatory OR r.cap_kind <> 'none' THEN RAISE EXCEPTION 'FAIL A2: TX 366 row wrong'; END IF;
  RAISE NOTICE 'PASS A2: the Texas rows carry what -06 enforced (cap 1/6 residential, 30-day retroactive simple interest, 12 bills / 2 late / close, 366 neither waivable nor refunded; vesting unruled)';
END $$;
DO $$ BEGIN
  INSERT INTO public.deposit_bases (basis_code, is_federal, insertable, description) VALUES ('x_basis', false, true, 'x');
  RAISE EXCEPTION 'FAIL A3a: the application wrote a basis';
EXCEPTION WHEN insufficient_privilege THEN NULL; END $$;
DO $$ BEGIN
  UPDATE public.deposit_rules SET waivable = false WHERE id = pg_temp.r('TX', 'residential', 'tariff');
  RAISE EXCEPTION 'FAIL A3b: the application edited a rule';
EXCEPTION WHEN insufficient_privilege THEN NULL; END $$;
DO $$ BEGIN
  INSERT INTO public.deposit_interest_rate_law (state_code, service_type, effective_from, annual_rate, source_note)
  VALUES ('TX', 'gas', DATE '2026-01-01', 0.05, 'x');
  RAISE EXCEPTION 'FAIL A3c: the application wrote a legal rate';
EXCEPTION WHEN insufficient_privilege THEN NULL; END $$;
DO $$ BEGIN
  INSERT INTO public.deposit_waiver_classes (state_code, service_type, class_code, requires_certification, description, source_note)
  VALUES ('TX', 'gas', 'x', false, 'x', 'x');
  RAISE EXCEPTION 'FAIL A3d: the application wrote a waiver class';
EXCEPTION WHEN insufficient_privilege THEN
  RAISE NOTICE 'PASS A3: the application cannot write the law tables (bases, rules, legal rates, waiver classes)'; END $$;
RESET ROLE;
-- Owner-level: law rows are closed, never edited or deleted.
DO $$ BEGIN
  UPDATE public.deposit_rules SET waivable = false WHERE id = pg_temp.r('TX', 'residential', 'tariff');
  RAISE EXCEPTION 'FAIL A4: the owner edited a rule row';
EXCEPTION WHEN restrict_violation THEN
  RAISE NOTICE 'PASS A4: not even the owner edits a rule row (deposits, accruals and due rows cite it)'; END $$;
DO $$ BEGIN
  DELETE FROM public.deposit_rules WHERE id = pg_temp.r('TX', 'non_residential', 'tariff');
  RAISE EXCEPTION 'FAIL A5: the owner deleted a rule row';
EXCEPTION WHEN restrict_violation THEN
  RAISE NOTICE 'PASS A5: a rule row is never deleted'; END $$;
DO $$ BEGIN
  UPDATE public.deposit_rules SET effective_to = DATE '2030-01-01', source_note = 'edited'
   WHERE id = pg_temp.r('TX', 'non_residential', 'tariff');
  RAISE EXCEPTION 'FAIL A6: a close carried another change';
EXCEPTION WHEN restrict_violation THEN
  RAISE NOTICE 'PASS A6: closing a rule row changes nothing else'; END $$;
DO $$ BEGIN
  UPDATE public.deposit_bases SET description = 'edited' WHERE basis_code = 'tariff';
  RAISE EXCEPTION 'FAIL A7a: a basis was edited';
EXCEPTION WHEN restrict_violation THEN NULL; END $$;
DO $$ BEGIN
  DELETE FROM public.deposit_waiver_classes WHERE state_code = 'TX' AND class_code = 'tariff';
  RAISE EXCEPTION 'FAIL A7b: a waiver class was deleted';
EXCEPTION WHEN restrict_violation THEN NULL; END $$;
DO $$ BEGIN
  UPDATE public.deposit_return_reasons SET evidence_kind = 'invoice' WHERE reason_code = 'account_closed';
  RAISE EXCEPTION 'FAIL A7c: a return reason was edited';
EXCEPTION WHEN restrict_violation THEN NULL; END $$;
DO $$ BEGIN
  UPDATE public.deposit_customer_classes SET source_note = 'edited' WHERE state_code = 'TX' AND class_code = 'residential';
  RAISE EXCEPTION 'FAIL A7d: a customer class was edited';
EXCEPTION WHEN restrict_violation THEN NULL; END $$;
DO $$ BEGIN
  DELETE FROM public.deposit_triggers WHERE trigger_code = 'nsf';
  RAISE EXCEPTION 'FAIL A7e: a trigger was deleted';
EXCEPTION WHEN restrict_violation THEN
  RAISE NOTICE 'PASS A7: the five vocabularies are never edited or deleted, by the owner either'; END $$;
DO $$ BEGIN
  INSERT INTO public.deposit_rules (state_code, service_type, customer_class, basis, waivable, cap_kind,
     interest_bearing_instruments, refund_mandatory, effective_from, source_note)
  VALUES ('TX', 'gas', 'residential', 'tariff', true, 'none', '{}', false, DATE '2020-01-01', 'overlapping row');
  RAISE EXCEPTION 'FAIL A8: an overlapping rule row was accepted';
EXCEPTION WHEN exclusion_violation THEN
  RAISE NOTICE 'PASS A8: two rule rows for one key never overlap'; END $$;
DO $$ BEGIN
  INSERT INTO public.deposit_rules (state_code, service_type, customer_class, basis, waivable, cap_kind, cap_scope,
     interest_bearing_instruments, refund_mandatory, effective_from, effective_to, source_note)
  VALUES ('TX', 'gas', 'residential', 'tariff', true, 'fraction_of_annual_billing', 'per_deposit', '{}', false, DATE '1990-01-01', DATE '2000-01-01', 'no divisor');
  RAISE EXCEPTION 'FAIL A9a: a fraction cap without its divisor';
EXCEPTION WHEN check_violation THEN NULL; END $$;
DO $$ BEGIN
  INSERT INTO public.deposit_rules (state_code, service_type, customer_class, basis, waivable, cap_kind,
     interest_bearing_instruments, interest_method, refund_mandatory, effective_from, effective_to, source_note)
  VALUES ('TX', 'gas', 'residential', 'tariff', true, 'none', '{}', 'simple', false, DATE '1990-01-01', DATE '2000-01-01', 'method, no instruments');
  RAISE EXCEPTION 'FAIL A9b: an interest method with no interest-bearing instrument';
EXCEPTION WHEN check_violation THEN NULL; END $$;
DO $$ BEGIN
  INSERT INTO public.deposit_rules (state_code, service_type, customer_class, basis, waivable, cap_kind,
     interest_bearing_instruments, interest_method, interest_day_count, interest_credit_cadence, interest_min_hold_days,
     refund_mandatory, effective_from, effective_to, source_note)
  VALUES ('TX', 'gas', 'residential', 'tariff', true, 'none', ARRAY['cash'], 'simple', 'actual_365', 'at_refund', 30,
          false, DATE '1990-01-01', DATE '2000-01-01', 'a hold without saying whether interest then runs from posting');
  RAISE EXCEPTION 'FAIL A9c: a minimum hold without retroactivity';
EXCEPTION WHEN check_violation THEN NULL; END $$;
DO $$ BEGIN
  INSERT INTO public.deposit_rules (state_code, service_type, customer_class, basis, waivable, cap_kind,
     interest_bearing_instruments, refund_mandatory, refund_after_count, effective_from, effective_to, source_note)
  VALUES ('TX', 'gas', 'residential', 'tariff', true, 'none', '{}', false, 12, DATE '1990-01-01', DATE '2000-01-01', 'a trigger count on no mandatory return');
  RAISE EXCEPTION 'FAIL A9d: a refund count with no mandatory return';
EXCEPTION WHEN check_violation THEN NULL; END $$;
DO $$ BEGIN
  INSERT INTO public.deposit_rules (state_code, service_type, customer_class, basis, waivable, cap_kind,
     interest_bearing_instruments, refund_mandatory, refund_on_account_close, return_mandatory_instruments,
     refund_after_count, effective_from, effective_to, source_note)
  VALUES ('TX', 'gas', 'residential', 'tariff', true, 'none', '{}', true, true, ARRAY['cash'], 12, DATE '1990-01-01', DATE '2000-01-01', 'a count without its measure');
  RAISE EXCEPTION 'FAIL A9e: a refund count without measure and limits';
EXCEPTION WHEN check_violation THEN NULL; END $$;
DO $$ BEGIN
  INSERT INTO public.deposit_rules (state_code, service_type, customer_class, basis, waivable, cap_kind,
     interest_bearing_instruments, refund_mandatory, effective_from, effective_to, source_note)
  VALUES ('TX', 'gas', 'residential', 'tariff', true, 'none', '{}', false, DATE '1990-01-01', DATE '2000-01-01', '   ');
  RAISE EXCEPTION 'FAIL A9f: a rule without a citation';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'PASS A9: a rule row says each thing whole or not at all (cap and figure, interest and its terms, a return and its trigger) and cites its source'; END $$;


-- ============================================================ Z. a second state
-- ZZ is fictional and unlike Texas: three classes, a waiver class Texas lacks
-- (certification-backed), a cap of two months' billing on the COMBINED total,
-- interest from day 1 on cash and certificates, compound, actual/actual,
-- credited annually; the return due after 24 months with at most one
-- delinquency, not on close, and it stays owed once due; a return reason
-- Texas lacks. All rows, no DDL.
DO $$ DECLARE v uuid; BEGIN
  INSERT INTO public.deposit_customer_classes (state_code, service_type, class_code, description, source_note) VALUES
    ('ZZ', 'gas', 'household', 'Households.', 'ZZ Code 1.1'),
    ('ZZ', 'gas', 'small_business', 'Small businesses.', 'ZZ Code 1.2'),
    ('ZZ', 'gas', 'large_volume', 'Large-volume users.', 'ZZ Code 1.3');
  INSERT INTO public.deposit_waiver_classes (state_code, service_type, class_code, requires_certification, description, source_note) VALUES
    ('ZZ', 'gas', 'veteran', true, 'Certified veteran.', 'ZZ Code 2.1');
  INSERT INTO public.deposit_return_reasons (reason_code, evidence_kind, description) VALUES
    ('service_term_complete', 'invoice', 'The service term the rule names has elapsed.');
  INSERT INTO public.deposit_rules (state_code, service_type, customer_class, basis, waivable, cap_kind, cap_months, cap_scope,
     interest_bearing_instruments, interest_method, interest_day_count, interest_credit_cadence,
     refund_mandatory, refund_after_count, refund_measure, refund_max_delinquencies, refund_disqualify_on_disconnect,
     refund_on_account_close, refund_obligation_vests, return_mandatory_instruments, effective_from, source_note)
  VALUES ('ZZ', 'gas', 'household', 'credit_evaluation', false, 'months_of_billing', 2, 'combined',
          ARRAY['cash', 'certificate_of_deposit'], 'compound_annual', 'actual_actual', 'annual',
          true, 24, 'months', 1, false, false, true, ARRAY['cash', 'certificate_of_deposit'],
          DATE '2025-01-01', 'ZZ Code 3.1-3.9')
  RETURNING id INTO v;
  INSERT INTO b15 VALUES ('zz_rule', v);
  -- A rule row for a basis the vocabulary marks not insertable (C7 cites it).
  INSERT INTO public.deposit_rules (state_code, service_type, customer_class, basis, waivable, cap_kind,
     interest_bearing_instruments, refund_mandatory, effective_from, source_note)
  VALUES ('ZZ', 'gas', 'large_volume', 'legacy_unknown', false, 'none', '{}', false, DATE '2025-01-01', 'ZZ fixture: legacy');
  RAISE NOTICE 'PASS Z1: a second state is stored as rows, no DDL: other classes, a certified waiver class, a two-month combined cap, interest from day 1 compound and credited annually on two instruments, a 24-month return that vests and ignores close, a new return reason';
END $$;
INSERT INTO public.deposit_interest_rates (tenant_id, state_code, service_type, effective_date, annual_rate) VALUES
  ('00000000-0000-4000-8000-0000000015a1', 'ZZ', 'gas', DATE '2025-01-01', 0.04);
SET LOCAL app.user_id = '00000000-0000-4000-8000-0000000015b1';
SET ROLE tally_app;
DO $$ DECLARE v_dep uuid; v_rate uuid; BEGIN
  v_dep := pg_temp.dep('zz_dep', '00000000-0000-4000-8000-0000000015c2', 'credit_evaluation', 'household', 'certificate_of_deposit', 400, DATE '2025-03-01', 'ZZ');
  IF (SELECT cap_basis_kind FROM public.deposits WHERE id = v_dep) <> 'months_of_billing' THEN
    RAISE EXCEPTION 'FAIL Z2: the ZZ cap kind was not recorded';
  END IF;
  SELECT id INTO v_rate FROM public.deposit_interest_rates WHERE state_code = 'ZZ';
  -- Interest on a certificate from day 1 for 10 days: law Texas lacks.
  PERFORM pg_temp.acc(v_dep, v_rate, DATE '2025-03-01', DATE '2025-03-10', 0.44, DATE '2025-03-11');
  RAISE NOTICE 'PASS Z2: the application records a ZZ deposit (a certificate, a month-based cap) and a day-1 accrual on it, exactly as Texas''s';
END $$;
SET CONSTRAINTS ALL DEFERRED;
SELECT pg_temp.due('00000000-0000-4000-8000-0000000015da', pg_temp.id('zz_dep'), DATE '2027-03-01');
SELECT pg_temp.evid('00000000-0000-4000-8000-0000000015da', 'service_term_complete', '00000000-0000-4000-8000-0000000015e8', 'clean', NULL);
SET CONSTRAINTS ALL IMMEDIATE;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.deposits_return_owed WHERE due_id = '00000000-0000-4000-8000-0000000015da'
                  AND reasons = ARRAY['service_term_complete'] AND instrument = 'certificate_of_deposit') THEN
    RAISE EXCEPTION 'FAIL Z3: the ZZ return is not on the owed list';
  END IF;
  RAISE NOTICE 'PASS Z3: a ZZ return of a non-cash instrument, for a reason Texas lacks, is recorded and listed as owed';
END $$;
DO $$ BEGIN
  INSERT INTO public.deposit_waiver_determinations (tenant_id, customer_id, state_code, service_type, waiver_class, determined_on)
  VALUES ('00000000-0000-4000-8000-0000000015a1', '00000000-0000-4000-8000-0000000015c2', 'ZZ', 'gas', 'veteran', DATE '2025-02-01');
  RAISE EXCEPTION 'FAIL Z4: a certified ZZ class without its reference';
EXCEPTION WHEN check_violation THEN
  INSERT INTO public.deposit_waiver_determinations (tenant_id, customer_id, state_code, service_type, waiver_class, determined_on, certification_reference)
  VALUES ('00000000-0000-4000-8000-0000000015a1', '00000000-0000-4000-8000-0000000015c2', 'ZZ', 'gas', 'veteran', DATE '2025-02-01', 'VA-123');
  RAISE NOTICE 'PASS Z4: a ZZ waiver class that rests on a certification needs its reference — read from the class row, no family-violence literal'; END $$;
RESET ROLE;
-- Owner: a law change is a stamped close plus a successor; the close floor.
DO $$ BEGIN
  UPDATE public.deposit_rules SET effective_to = DATE '2027-03-01' WHERE id = pg_temp.id('zz_rule');
  RAISE EXCEPTION 'FAIL Z5: a close on the date a due row cites the rule was accepted';
EXCEPTION WHEN restrict_violation THEN
  RAISE NOTICE 'PASS Z5: a rule row cannot close on or before a date it is cited for (the due row''s 2027-03-01)'; END $$;
DO $$ DECLARE r record; BEGIN
  UPDATE public.deposit_rules SET effective_to = DATE '2027-06-01' WHERE id = pg_temp.id('zz_rule');
  SELECT closed_at, closed_by INTO r FROM public.deposit_rules WHERE id = pg_temp.id('zz_rule');
  IF r.closed_at IS NULL OR r.closed_by IS NULL THEN RAISE EXCEPTION 'FAIL Z6: the close was not stamped'; END IF;
  INSERT INTO public.deposit_rules (state_code, service_type, customer_class, basis, waivable, cap_kind, interest_bearing_instruments,
     refund_mandatory, effective_from, source_note)
  VALUES ('ZZ', 'gas', 'household', 'credit_evaluation', true, 'none', '{}', false, DATE '2027-06-01', 'ZZ Code 3 as amended');
  BEGIN
    UPDATE public.deposit_rules SET effective_to = DATE '2028-01-01' WHERE id = pg_temp.id('zz_rule');
    RAISE EXCEPTION 'FAIL Z6: a closed row was closed again';
  EXCEPTION WHEN restrict_violation THEN NULL; END;
  RAISE NOTICE 'PASS Z6: a law change is a close (stamped with when and which role, once) plus a successor';
END $$;


-- ============================================================ B. interest rates
SET LOCAL app.user_id = '00000000-0000-4000-8000-0000000015b1';
SET ROLE tally_app;
DO $$ DECLARE v uuid; BEGIN
  INSERT INTO public.deposit_interest_rates (tenant_id, state_code, service_type, effective_date, annual_rate)
  VALUES ('00000000-0000-4000-8000-0000000015a1', 'TX', 'gas', DATE '2026-01-01', 0.03) RETURNING id INTO v;
  INSERT INTO b15 VALUES ('rate_jan', v);
  INSERT INTO public.deposit_interest_rates (tenant_id, state_code, service_type, effective_date, annual_rate)
  VALUES ('00000000-0000-4000-8000-0000000015a1', 'TX', 'gas', DATE '2026-03-01', 0.025) RETURNING id INTO v;
  INSERT INTO b15 VALUES ('rate_mar', v);
  RAISE NOTICE 'PASS B1: the utility records the rate it applies, per state and service';
END $$;
DO $$ BEGIN
  INSERT INTO public.deposit_interest_rates (tenant_id, state_code, service_type, effective_date, annual_rate)
  VALUES ('00000000-0000-4000-8000-0000000015a1', 'TX', 'gas', DATE '2026-01-01', 0.05);
  RAISE EXCEPTION 'FAIL B2: two rates for one day';
EXCEPTION WHEN unique_violation THEN
  RAISE NOTICE 'PASS B2: one utility rate per state, service and date'; END $$;
RESET ROLE;
INSERT INTO public.deposit_interest_rates (tenant_id, state_code, service_type, effective_date, annual_rate) VALUES
  ('00000000-0000-4000-8000-0000000015a2', 'TX', 'gas', DATE '2026-02-01', 0.0287);
DO $$ DECLARE v uuid; BEGIN
  INSERT INTO public.deposit_interest_rate_law (state_code, service_type, effective_from, effective_to, annual_rate, source_note)
  VALUES ('TX', 'gas', DATE '2026-01-01', DATE '2027-01-01', 0.0287, 'PUCT 2026 deposit interest rate (fixture)') RETURNING id INTO v;
  INSERT INTO b15 VALUES ('law_2026', v);
  BEGIN
    UPDATE public.deposit_interest_rate_law SET annual_rate = 0.03 WHERE id = v;
    RAISE EXCEPTION 'FAIL B3: the owner edited a published rate';
  EXCEPTION WHEN restrict_violation THEN NULL; END;
  BEGIN
    DELETE FROM public.deposit_interest_rate_law WHERE id = v;
    RAISE EXCEPTION 'FAIL B3: the owner deleted a published rate';
  EXCEPTION WHEN restrict_violation THEN NULL; END;
  RAISE NOTICE 'PASS B3: a published legal rate is never edited or deleted';
END $$;
SET LOCAL app.user_id = '00000000-0000-4000-8000-0000000015b1';
SET ROLE tally_app;
DO $$ DECLARE n int; BEGIN
  SELECT count(*) INTO n FROM public.deposit_interest_rate_discrepancies
   WHERE discrepancy = 'rate_differs' AND tenant_id = '00000000-0000-4000-8000-0000000015a1' AND state_code = 'TX';
  IF n <> 2 THEN RAISE EXCEPTION 'FAIL B4: T1 should differ from the published rate twice (3%% Jan-Feb, 2.5%% from Mar), read %', n; END IF;
  IF EXISTS (SELECT 1 FROM public.deposit_interest_rate_discrepancies WHERE tenant_id <> '00000000-0000-4000-8000-0000000015a1') THEN
    RAISE EXCEPTION 'FAIL B4: T1 sees another tenant''s rows';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.deposit_interest_rate_discrepancies
                  WHERE rate_id = pg_temp.id('rate_jan') AND from_date = DATE '2026-01-01' AND to_date_exclusive = DATE '2026-03-01'
                    AND utility_rate = 0.03 AND law_rate = 0.0287) THEN
    RAISE EXCEPTION 'FAIL B4: the January span is wrong';
  END IF;
  RAISE NOTICE 'PASS B4: the discrepancy report lists each span where the utility''s rate differs from the published one, for the tenant only';
END $$;
RESET ROLE;
SET LOCAL app.user_id = '00000000-0000-4000-8000-0000000015b2';
SET ROLE tally_app;
DO $$ DECLARE r record; BEGIN
  SELECT * INTO r FROM public.deposit_interest_rate_discrepancies;
  IF r.discrepancy <> 'no_utility_rate' OR r.from_date <> DATE '2026-01-01' OR r.to_date_exclusive <> DATE '2026-02-01'
     OR (SELECT count(*) FROM public.deposit_interest_rate_discrepancies) <> 1 THEN
    RAISE EXCEPTION 'FAIL B5: T2 (2.87%% from Feb) should show one gap, January: %', row_to_json(r);
  END IF;
  RAISE NOTICE 'PASS B5: a published rate before the utility''s first row is reported as no_utility_rate; an equal rate is no discrepancy';
END $$;
RESET ROLE;


-- ============================================================ C. deposits
SET LOCAL app.user_id = '00000000-0000-4000-8000-0000000015b1';
SET ROLE tally_app;
DO $$ BEGIN
  PERFORM pg_temp.dep('a', '00000000-0000-4000-8000-0000000015c1', 'credit_evaluation', 'residential', 'cash', 200, DATE '2026-01-01');
  RAISE NOTICE 'PASS C1: a deposit records its state, service, class, rule row, cap and core version';
END $$;
DO $$ BEGIN
  INSERT INTO public.deposits (tenant_id, customer_id, basis, instrument, principal, posted_on)
  VALUES ('00000000-0000-4000-8000-0000000015a1', '00000000-0000-4000-8000-0000000015c1', 'tariff', 'cash', 100, DATE '2026-01-01');
  RAISE EXCEPTION 'FAIL C2a: a deposit with no rule';
EXCEPTION WHEN check_violation THEN NULL; END $$;
DO $$ BEGIN
  INSERT INTO public.deposits (tenant_id, customer_id, basis, instrument, principal, posted_on, state_code, service_type, customer_class, rule_id)
  VALUES ('00000000-0000-4000-8000-0000000015a1', '00000000-0000-4000-8000-0000000015c3', 'tariff', 'cash', 100, DATE '2026-01-01',
          'TX', 'gas', 'non_residential', pg_temp.r('TX', 'non_residential', 'tariff'));
  RAISE EXCEPTION 'FAIL C2b: a deposit with no core version';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'PASS C2: a new deposit cites the rule row it was decided under and the core version'; END $$;
DO $$ BEGIN
  INSERT INTO public.deposits (tenant_id, customer_id, basis, instrument, principal, posted_on, state_code, service_type, customer_class, rule_id, decided_by)
  VALUES ('00000000-0000-4000-8000-0000000015a1', '00000000-0000-4000-8000-0000000015c3', 'tariff', 'cash', 100, DATE '2026-01-01',
          'TX', 'gas', 'non_residential', pg_temp.r('TX', 'non_residential', 'credit_evaluation'), 'core-test');
  RAISE EXCEPTION 'FAIL C3a: a rule of another basis';
EXCEPTION WHEN check_violation THEN NULL; END $$;
DO $$ BEGIN
  INSERT INTO public.deposits (tenant_id, customer_id, basis, instrument, principal, posted_on, state_code, service_type, customer_class, rule_id, decided_by)
  VALUES ('00000000-0000-4000-8000-0000000015a1', '00000000-0000-4000-8000-0000000015c3', 'tariff', 'cash', 100, DATE '2026-01-01',
          'TX', 'gas', 'residential', pg_temp.r('TX', 'non_residential', 'tariff'), 'core-test');
  RAISE EXCEPTION 'FAIL C3b: a rule of another class';
EXCEPTION WHEN check_violation THEN NULL; END $$;
DO $$ BEGIN
  INSERT INTO public.deposits (tenant_id, customer_id, basis, instrument, principal, posted_on, state_code, service_type, customer_class, rule_id, decided_by)
  VALUES ('00000000-0000-4000-8000-0000000015a1', '00000000-0000-4000-8000-0000000015c3', 'credit_evaluation', 'cash', 100, DATE '2026-01-01',
          'ZZ', 'gas', 'household', pg_temp.r('TX', 'residential', 'credit_evaluation'), 'core-test');
  RAISE EXCEPTION 'FAIL C3c: a rule of another state';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'PASS C3: the cited rule is for the deposit''s own state, class and basis'; END $$;
DO $$ BEGIN
  INSERT INTO public.deposits (tenant_id, customer_id, basis, instrument, principal, posted_on, state_code, service_type, customer_class, rule_id, decided_by)
  VALUES ('00000000-0000-4000-8000-0000000015a1', '00000000-0000-4000-8000-0000000015c3', 'tariff', 'cash', 100, DATE '2001-01-01',
          'TX', 'gas', 'non_residential', pg_temp.r('TX', 'non_residential', 'tariff'), 'core-test');
  RAISE EXCEPTION 'FAIL C4: a rule not yet in force on the posting date';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'PASS C4: the cited rule is in force on the posting date'; END $$;
DO $$ BEGIN
  INSERT INTO public.deposits (tenant_id, customer_id, basis, instrument, principal, posted_on, state_code, service_type, customer_class, rule_id, decided_by)
  VALUES ('00000000-0000-4000-8000-0000000015a1', '00000000-0000-4000-8000-0000000015c1', 'tariff', 'cash', 100, DATE '2026-01-01',
          'TX', 'gas', 'residential', pg_temp.r('TX', 'residential', 'tariff'), 'core-test');
  RAISE EXCEPTION 'FAIL C5a: a capped rule, no cap recorded';
EXCEPTION WHEN check_violation THEN NULL; END $$;
DO $$ BEGIN
  INSERT INTO public.deposits (tenant_id, customer_id, basis, instrument, principal, posted_on, state_code, service_type, customer_class, rule_id, decided_by,
                               cap_amount, cap_basis_kind, cap_basis_amount)
  VALUES ('00000000-0000-4000-8000-0000000015a1', '00000000-0000-4000-8000-0000000015c1', 'tariff', 'cash', 100, DATE '2026-01-01',
          'TX', 'gas', 'residential', pg_temp.r('TX', 'residential', 'tariff'), 'core-test', 150, 'months_of_billing', 75);
  RAISE EXCEPTION 'FAIL C5b: a cap of another kind';
EXCEPTION WHEN check_violation THEN NULL; END $$;
DO $$ BEGIN
  INSERT INTO public.deposits (tenant_id, customer_id, basis, instrument, principal, posted_on, state_code, service_type, customer_class, rule_id, decided_by,
                               cap_amount, cap_basis_kind)
  VALUES ('00000000-0000-4000-8000-0000000015a1', '00000000-0000-4000-8000-0000000015c1', 'tariff', 'cash', 100, DATE '2026-01-01',
          'TX', 'gas', 'residential', pg_temp.r('TX', 'residential', 'tariff'), 'core-test', 150, 'fraction_of_annual_billing');
  RAISE EXCEPTION 'FAIL C5c: a fraction cap with no basis figure';
EXCEPTION WHEN check_violation THEN NULL; END $$;
DO $$ BEGIN
  INSERT INTO public.deposits (tenant_id, customer_id, basis, instrument, principal, posted_on, state_code, service_type, customer_class, rule_id, decided_by,
                               cap_amount, cap_basis_kind, cap_basis_amount)
  VALUES ('00000000-0000-4000-8000-0000000015a1', '00000000-0000-4000-8000-0000000015c3', 'tariff', 'cash', 100, DATE '2026-01-01',
          'TX', 'gas', 'non_residential', pg_temp.r('TX', 'non_residential', 'tariff'), 'core-test', 150, 'fraction_of_annual_billing', 900);
  RAISE EXCEPTION 'FAIL C5d: a cap under a rule with none';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'PASS C5: the cap is recorded exactly when the rule has one, of the rule''s kind, with its basis figure'; END $$;
DO $$ BEGIN
  INSERT INTO public.deposits (tenant_id, customer_id, basis, instrument, principal, posted_on, state_code, service_type, customer_class, rule_id, decided_by,
                               cap_amount, cap_basis_kind, cap_basis_amount)
  VALUES ('00000000-0000-4000-8000-0000000015a1', '00000000-0000-4000-8000-0000000015c1', 'tariff', 'cash', 200, DATE '2026-01-01',
          'TX', 'gas', 'residential', pg_temp.r('TX', 'residential', 'tariff'), 'core-test', 150, 'fraction_of_annual_billing', 900);
  RAISE EXCEPTION 'FAIL C6: principal above the recorded cap';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'PASS C6: principal never exceeds the recorded cap (arithmetic on the record, kept)'; END $$;
DO $$ BEGIN
  INSERT INTO public.deposits (tenant_id, customer_id, basis, instrument, principal, posted_on, state_code, service_type, customer_class, rule_id, decided_by)
  VALUES ('00000000-0000-4000-8000-0000000015a1', '00000000-0000-4000-8000-0000000015c3', 'legacy_unknown', 'cash', 100, DATE '2026-01-01',
          'ZZ', 'gas', 'large_volume', pg_temp.r('ZZ', 'large_volume', 'legacy_unknown'), 'core-test');
  RAISE EXCEPTION 'FAIL C7: a legacy_unknown deposit was inserted';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'PASS C7: a basis the vocabulary marks not insertable is refused (legacy_unknown), even under a rule row for it'; END $$;
DO $$ BEGIN
  INSERT INTO public.deposits (tenant_id, customer_id, basis, trigger_basis, instrument, principal, posted_on, state_code, service_type, customer_class, rule_id, decided_by)
  VALUES ('00000000-0000-4000-8000-0000000015a1', '00000000-0000-4000-8000-0000000015c3', 'additional_trigger', 'late_twice', 'cash', 100, DATE '2026-01-01',
          'TX', 'gas', 'non_residential', pg_temp.r('TX', 'non_residential', 'additional_trigger'), 'core-test');
  RAISE EXCEPTION 'FAIL C8a: an unknown trigger';
EXCEPTION WHEN foreign_key_violation THEN NULL; END $$;
DO $$ BEGIN
  INSERT INTO public.deposits (tenant_id, customer_id, basis, instrument, principal, posted_on, state_code, service_type, customer_class, rule_id, decided_by)
  VALUES ('00000000-0000-4000-8000-0000000015a1', '00000000-0000-4000-8000-0000000015c3', 'additional_trigger', 'cash', 100, DATE '2026-01-01',
          'TX', 'gas', 'non_residential', pg_temp.r('TX', 'non_residential', 'additional_trigger'), 'core-test');
  RAISE EXCEPTION 'FAIL C8b: an additional deposit with no trigger';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'PASS C8: a trigger is a vocabulary row, and an additional deposit names one'; END $$;
DO $$ BEGIN
  UPDATE public.deposits SET rule_id = pg_temp.r('TX', 'residential', 'tariff') WHERE id = pg_temp.id('a');
  RAISE EXCEPTION 'FAIL C9a: rule_id changed';
EXCEPTION WHEN check_violation THEN NULL; END $$;
DO $$ BEGIN
  UPDATE public.deposits SET decided_by = 'core-other' WHERE id = pg_temp.id('a');
  RAISE EXCEPTION 'FAIL C9b: decided_by changed';
EXCEPTION WHEN check_violation THEN NULL; END $$;
DO $$ BEGIN
  UPDATE public.deposits SET cap_basis_amount = 1 WHERE id = pg_temp.id('a');
  RAISE EXCEPTION 'FAIL C9c: cap_basis_amount changed';
EXCEPTION WHEN check_violation THEN NULL; END $$;
DO $$ BEGIN
  UPDATE public.deposits SET status = 'refunded', refunded_on = DATE '2026-05-01' WHERE id = pg_temp.id('a');
  RAISE EXCEPTION 'FAIL C9d: status written directly';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'PASS C9: what a deposit was decided under is frozen with its identity; status stays a projection'; END $$;


-- ============================================================ D. waivers
DO $$ BEGIN
  INSERT INTO public.deposit_waiver_determinations (tenant_id, customer_id, state_code, service_type, waiver_class, determined_on)
  VALUES ('00000000-0000-4000-8000-0000000015a1', '00000000-0000-4000-8000-0000000015c1', 'TX', 'gas', 'family_violence_certified', DATE '2025-06-01');
  RAISE EXCEPTION 'FAIL D1: a certified class without its reference';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'PASS D1: the TX family-violence class still needs its certification reference (from the class row)'; END $$;
DO $$ BEGIN
  INSERT INTO public.deposit_waiver_determinations (tenant_id, customer_id, state_code, service_type, waiver_class, determined_on)
  VALUES ('00000000-0000-4000-8000-0000000015a1', '00000000-0000-4000-8000-0000000015c1', 'TX', 'gas', 'veteran', DATE '2025-06-01');
  RAISE EXCEPTION 'FAIL D2: another state''s class for TX';
EXCEPTION WHEN foreign_key_violation THEN
  RAISE NOTICE 'PASS D2: a waiver class is the named state''s (ZZ''s veteran is no TX class)'; END $$;
DO $$ BEGIN
  INSERT INTO public.deposit_waiver_determinations (tenant_id, customer_id, state_code, service_type, waiver_class, determined_on, certification_reference)
  VALUES ('00000000-0000-4000-8000-0000000015a1', '00000000-0000-4000-8000-0000000015c1', 'TX', 'gas', 'family_violence_certified', DATE '2025-06-01', 'TCFV-77');
  INSERT INTO public.deposit_waiver_determinations (tenant_id, customer_id, state_code, service_type, waiver_class, determined_on)
  VALUES ('00000000-0000-4000-8000-0000000015a1', '00000000-0000-4000-8000-0000000015c1', 'TX', 'gas', 'age_65_no_balance', DATE '2025-06-01');
  RAISE NOTICE 'PASS D3: determinations of TX classes are recorded (with a reference where the class needs one)';
END $$;
DO $$ BEGIN
  UPDATE public.deposit_waiver_determinations SET certification_reference = 'x' WHERE customer_id = '00000000-0000-4000-8000-0000000015c1';
  RAISE EXCEPTION 'FAIL D4: a determination was edited';
EXCEPTION WHEN insufficient_privilege THEN
  RAISE NOTICE 'PASS D4: determinations stay append-only'; END $$;


-- ============================================================ L. Texas law gone
DO $$ BEGIN
  -- C1 holds two in-force TX waivers (D3); -06 refused any §7.45 deposit.
  PERFORM pg_temp.dep('l_waived', '00000000-0000-4000-8000-0000000015c1', 'tariff', 'residential', 'cash', 50, DATE '2026-01-02');
  RAISE NOTICE 'PASS L1: a waiver in force no longer refuses a deposit in the database (the core decides, from deposit_rules.waivable)';
END $$;
DO $$ BEGIN
  -- -06 refused a TX residential cash deposit without a cap only for a TX TENANT;
  -- these tenants carry no state at all. The cap now follows the rule row.
  IF (SELECT cap_amount FROM public.deposits WHERE id = pg_temp.id('a')) IS NULL THEN
    RAISE EXCEPTION 'FAIL L2: the cap was not recorded';
  END IF;
  IF (SELECT state FROM public.tenants WHERE id = '00000000-0000-4000-8000-0000000015a1') IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL L2: fixture tenant has a state';
  END IF;
  RAISE NOTICE 'PASS L2: the cap follows the cited rule, not the utility''s home state';
END $$;
DO $$ BEGIN
  -- Day 10, any amount, a gap, a non-cash instrument: every one refused by -06.
  PERFORM pg_temp.acc(pg_temp.id('a'), pg_temp.id('rate_jan'), DATE '2026-01-01', DATE '2026-01-10', 9.99, DATE '2026-01-11');
  PERFORM pg_temp.acc(pg_temp.id('a'), pg_temp.id('rate_jan'), DATE '2026-01-15', DATE '2026-01-31', 0.10, DATE '2026-02-01');
  PERFORM pg_temp.dep('l_bond', '00000000-0000-4000-8000-0000000015c3', 'tariff', 'non_residential', 'surety_bond', 500, DATE '2026-01-01');
  PERFORM pg_temp.acc(pg_temp.id('l_bond'), pg_temp.id('rate_jan'), DATE '2026-01-01', DATE '2026-01-31', 1.00, DATE '2026-02-01');
  RAISE NOTICE 'PASS L3: the database no longer refuses an accrual inside 30 days, of any amount, after a gap, or on a bond (the core decides, from the rule row)';
END $$;
DO $$ BEGIN
  IF to_regclass('public.deposits_refund_due') IS NOT NULL
     OR to_regprocedure('public.deposit_refund_trigger_state(uuid)') IS NOT NULL
     OR to_regprocedure('public.deposit_accrual_amount(numeric,numeric,date,date)') IS NOT NULL
     OR to_regprocedure('public.deposit_interest_rate_as_of(uuid,date)') IS NOT NULL
     OR EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'deposits'
                 AND column_name IN ('refund_eligibility_on', 'cap_basis_annual_billing')) THEN
    RAISE EXCEPTION 'FAIL L4: a dropped law object survives';
  END IF;
  RAISE NOTICE 'PASS L4: the refund-due view, the trigger-state, formula and rate-lookup functions, and the two columns are gone';
END $$;
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
              WHERE n.nspname = 'public' AND p.proname IN ('enforce_deposit', 'enforce_deposit_event')
                AND (p.prosrc ~ '''TX''' OR p.prosrc ~ '365' OR p.prosrc ~ '\m3[01]\M' OR p.prosrc ~ 'family_violence'
                     OR p.prosrc ~ 'credit_evaluation')) THEN
    RAISE EXCEPTION 'FAIL L5: a deposit guard still names a state, a day count, a basis or a waiver class';
  END IF;
  RAISE NOTICE 'PASS L5: the deposit guards name no state, day count, basis or waiver class';
END $$;


-- ============================================================ E. the sub-ledger
DO $$ BEGIN
  INSERT INTO public.deposit_events (tenant_id, deposit_id, event_type, amount, effective_on, period_start, period_end,
                                     rate_applied, principal_basis, rate_id, rule_id, calculated_by)
  VALUES ('00000000-0000-4000-8000-0000000015a1', pg_temp.id('a'), 'interest_accrued', 0.1, DATE '2026-02-21', DATE '2026-02-11', DATE '2026-02-20',
          0.03, 200, pg_temp.id('rate_jan'), pg_temp.r('TX', 'residential', 'tariff'), 'core-test');
  RAISE EXCEPTION 'FAIL E1: an accrual cited another rule';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'PASS E1: an accrual cites the rule its deposit was decided under'; END $$;
DO $$ DECLARE v uuid; BEGIN
  SELECT id INTO v FROM public.deposit_interest_rates WHERE state_code = 'ZZ';
  PERFORM pg_temp.acc(pg_temp.id('a'), v, DATE '2026-02-11', DATE '2026-02-20', 0.1, DATE '2026-02-21');
  RAISE EXCEPTION 'FAIL E2a: a ZZ rate on a TX deposit';
EXCEPTION WHEN check_violation THEN NULL; END $$;
RESET ROLE;
DO $$ DECLARE v uuid; BEGIN
  SELECT id INTO v FROM public.deposit_interest_rates WHERE tenant_id = '00000000-0000-4000-8000-0000000015a2';
  INSERT INTO b15 VALUES ('rate_t2', v);
END $$;
SET LOCAL app.user_id = '00000000-0000-4000-8000-0000000015b1';
SET ROLE tally_app;
DO $$ BEGIN
  INSERT INTO public.deposit_events (tenant_id, deposit_id, event_type, amount, effective_on, period_start, period_end,
                                     rate_applied, principal_basis, rate_id, rule_id, calculated_by)
  VALUES ('00000000-0000-4000-8000-0000000015a1', pg_temp.id('a'), 'interest_accrued', 0.1, DATE '2026-02-21', DATE '2026-02-11', DATE '2026-02-20',
          0.0287, 200, pg_temp.id('rate_t2'), pg_temp.r('TX', 'residential', 'credit_evaluation'), 'core-test');
  RAISE EXCEPTION 'FAIL E2b: another tenant''s rate';
-- RLS hides T2's row, so the guard refuses it before the composite key does.
EXCEPTION WHEN foreign_key_violation OR check_violation THEN
  RAISE NOTICE 'PASS E2: an accrual cites a rate row of its own utility, state and service'; END $$;
DO $$ BEGIN
  PERFORM pg_temp.acc(pg_temp.id('a'), pg_temp.id('rate_mar'), DATE '2026-02-11', DATE '2026-02-20', 0.1, DATE '2026-02-21');
  RAISE EXCEPTION 'FAIL E3: a rate not yet effective';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'PASS E3: a rate row cannot apply to a period that starts before it takes effect'; END $$;
DO $$ BEGIN
  INSERT INTO public.deposit_events (tenant_id, deposit_id, event_type, amount, effective_on, period_start, period_end,
                                     rate_applied, principal_basis, rate_id, rule_id, calculated_by)
  SELECT d.tenant_id, d.id, 'interest_accrued', 0.1, DATE '2026-02-21', DATE '2026-02-11', DATE '2026-02-20',
         0.04, 200, pg_temp.id('rate_jan'), d.rule_id, 'core-test' FROM public.deposits d WHERE d.id = pg_temp.id('a');
  RAISE EXCEPTION 'FAIL E4: rate_applied not the cited row''s';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'PASS E4: rate_applied is the cited row''s rate'; END $$;
DO $$ BEGIN
  PERFORM pg_temp.acc(pg_temp.id('l_waived'), pg_temp.id('rate_jan'), DATE '2026-01-01', DATE '2026-01-05', 0.1, DATE '2026-02-21');
  RAISE EXCEPTION 'FAIL E5a: a period before posting';
EXCEPTION WHEN check_violation THEN NULL; END $$;
DO $$ BEGIN
  PERFORM pg_temp.acc(pg_temp.id('a'), pg_temp.id('rate_jan'), DATE '2026-02-11', DATE '2026-02-20', 0.1, DATE '2026-02-20');
  RAISE EXCEPTION 'FAIL E5b: recorded before its period ended';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'PASS E5: an accrual period lies inside the deposit''s life and is recorded after it ends'; END $$;
DO $$ BEGIN
  PERFORM pg_temp.acc(pg_temp.id('a'), pg_temp.id('rate_jan'), DATE '2026-01-05', DATE '2026-01-12', 0.1, DATE '2026-02-21');
  RAISE EXCEPTION 'FAIL E6: overlapping accruals';
EXCEPTION WHEN exclusion_violation THEN
  RAISE NOTICE 'PASS E6: accrual periods never overlap'; END $$;
DO $$ BEGIN
  INSERT INTO public.deposit_events (tenant_id, deposit_id, event_type, amount, effective_on, period_start, period_end,
                                     rate_applied, principal_basis, rate_id, rule_id)
  SELECT d.tenant_id, d.id, 'interest_accrued', 0.1, DATE '2026-03-01', DATE '2026-02-11', DATE '2026-02-20',
         0.03, 200, pg_temp.id('rate_jan'), d.rule_id FROM public.deposits d WHERE d.id = pg_temp.id('a');
  RAISE EXCEPTION 'FAIL E7a: an accrual with no core version';
EXCEPTION WHEN check_violation THEN NULL; END $$;
DO $$ BEGIN
  INSERT INTO public.deposit_events (tenant_id, deposit_id, event_type, amount, effective_on, rate_id)
  SELECT d.tenant_id, d.id, 'applied_to_balance', 10, DATE '2026-03-01', pg_temp.id('rate_jan') FROM public.deposits d WHERE d.id = pg_temp.id('a');
  RAISE EXCEPTION 'FAIL E7b: a rate citation on an application';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'PASS E7: an accrual carries its rate row, rule row and core version; no other event does'; END $$;
DO $$ BEGIN
  PERFORM pg_temp.ev(pg_temp.id('a'), 'applied_to_balance', 20, DATE '2026-01-20');
  RAISE EXCEPTION 'FAIL E8a: an application into an accrued period';
EXCEPTION WHEN check_violation THEN NULL; END $$;
DO $$ BEGIN
  PERFORM pg_temp.ev(pg_temp.id('a'), 'applied_to_balance', 500, DATE '2026-03-01');
  RAISE EXCEPTION 'FAIL E8b: an application above the remainder';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'PASS E8: an application stays within the remainder and out of accrued periods'; END $$;
DO $$ BEGIN
  PERFORM pg_temp.ev(pg_temp.id('a'), 'interest_credited', 100, DATE '2026-03-01');
  RAISE EXCEPTION 'FAIL E9: credit above accrued';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'PASS E9: credit stays within accrued − credited'; END $$;
DO $$ BEGIN
  PERFORM pg_temp.ev(pg_temp.id('a'), 'refunded', 200, DATE '2026-03-01');
  RAISE EXCEPTION 'FAIL E10: a refund leaving accrued interest uncredited';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'PASS E10: a refund, the deposit''s last event, cannot leave accrued interest uncredited'; END $$;
DO $$ BEGIN
  PERFORM pg_temp.ev(pg_temp.id('a'), 'interest_credited', 9.99 + 0.10, DATE '2026-03-01');
  PERFORM pg_temp.ev(pg_temp.id('a'), 'refunded', 199, DATE '2026-03-01');
  RAISE EXCEPTION 'FAIL E11: a refund other than the remainder';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'PASS E11: a refund is exactly the remainder'; END $$;
DO $$ BEGIN
  PERFORM pg_temp.ev(pg_temp.id('a'), 'released', 200, DATE '2026-03-01');
  RAISE EXCEPTION 'FAIL E12a: cash released';
EXCEPTION WHEN check_violation THEN NULL; END $$;
DO $$ BEGIN
  PERFORM pg_temp.ev(pg_temp.id('l_bond'), 'interest_credited', 1, DATE '2026-03-01');
  PERFORM pg_temp.ev(pg_temp.id('l_bond'), 'refunded', 500, DATE '2026-03-01');
  RAISE EXCEPTION 'FAIL E12b: a bond refunded';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'PASS E12: cash is refunded and non-cash released, never the other way'; END $$;
DO $$ BEGIN
  PERFORM pg_temp.ev(pg_temp.id('l_bond'), 'interest_credited', 1, DATE '2026-03-01');
  PERFORM pg_temp.ev(pg_temp.id('l_bond'), 'released', 500, DATE '2026-03-01');
  PERFORM pg_temp.ev(pg_temp.id('l_bond'), 'applied_to_balance', 1, DATE '2026-03-02');
  RAISE EXCEPTION 'FAIL E13: an event after release';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'PASS E13: no event follows a release'; END $$;
DO $$ BEGIN
  INSERT INTO public.deposit_events (tenant_id, deposit_id, event_type, amount, effective_on)
  VALUES ('00000000-0000-4000-8000-0000000015a1', pg_temp.id('a'), 'posted', 200, DATE '2026-01-01');
  RAISE EXCEPTION 'FAIL E14: the application wrote a posted event';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'PASS E14: the posted event is the database''s'; END $$;
DO $$ BEGIN
  PERFORM pg_temp.ev(pg_temp.id('a'), 'interest_credited', 10.09, DATE '2026-03-01');
  PERFORM pg_temp.ev(pg_temp.id('a'), 'refund_initiated', 200, DATE '2026-03-01');
  BEGIN
    PERFORM pg_temp.ev(pg_temp.id('a'), 'applied_to_balance', 10, DATE '2026-03-02');
    RAISE EXCEPTION 'FAIL E15: an application while a refund is pending';
  EXCEPTION WHEN check_violation THEN NULL; END;
  BEGIN
    PERFORM pg_temp.ev(pg_temp.id('a'), 'refund_initiated', 200, DATE '2026-03-02');
    RAISE EXCEPTION 'FAIL E15: a second pending refund';
  EXCEPTION WHEN check_violation THEN NULL; END;
  PERFORM pg_temp.ev(pg_temp.id('a'), 'refunded', 200, DATE '2026-03-05');
  IF (SELECT status FROM public.deposits WHERE id = pg_temp.id('a')) <> 'refunded' THEN RAISE EXCEPTION 'FAIL E15: not projected'; END IF;
  RAISE NOTICE 'PASS E15: one pending refund, nothing applied meanwhile; credited, refunded and projected';
END $$;
DO $$ BEGIN
  INSERT INTO public.deposit_interest_rates (tenant_id, state_code, service_type, effective_date, annual_rate)
  VALUES ('00000000-0000-4000-8000-0000000015a1', 'TX', 'gas', DATE '2026-01-20', 0.02);
  RAISE EXCEPTION 'FAIL E16: a rate backdated under a settled accrual';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'PASS E16: a utility rate cannot be backdated under an accrual that cites its state and service'; END $$;
DO $$ BEGIN
  INSERT INTO public.deposit_interest_rates (tenant_id, state_code, service_type, effective_date, annual_rate)
  VALUES ('00000000-0000-4000-8000-0000000015a1', 'TX', 'electric', DATE '2026-01-20', 0.02);
  RAISE NOTICE 'PASS E17: a gas accrual does not freeze the electric rates (the guard is per state and service)';
END $$;
RESET ROLE;
-- A carried legacy deposit (as -06's backfill made it: guard off, owner).
ALTER TABLE public.deposits DISABLE TRIGGER a_enforce_deposit;
INSERT INTO public.deposits (id, tenant_id, customer_id, basis, instrument, principal, posted_on, legacy_interest_earned)
VALUES ('00000000-0000-4000-8000-0000000015ee', '00000000-0000-4000-8000-0000000015a1', '00000000-0000-4000-8000-0000000015c2',
        'legacy_unknown', 'cash', 80, DATE '2024-01-01', 3.10);
ALTER TABLE public.deposits ENABLE ALWAYS TRIGGER a_enforce_deposit;
SET LOCAL app.user_id = '00000000-0000-4000-8000-0000000015b1';
SET ROLE tally_app;
DO $$ BEGIN
  PERFORM pg_temp.ev('00000000-0000-4000-8000-0000000015ee', 'refunded', 80, DATE '2026-03-01');
  RAISE EXCEPTION 'FAIL E18a: a legacy refund without a reason';
EXCEPTION WHEN check_violation THEN NULL; END $$;
DO $$ BEGIN
  PERFORM pg_temp.acc('00000000-0000-4000-8000-0000000015ee', pg_temp.id('rate_jan'), DATE '2026-01-01', DATE '2026-01-31', 0.2, DATE '2026-02-01');
  RAISE EXCEPTION 'FAIL E18b: an accrual on a legacy deposit (no rule)';
EXCEPTION WHEN check_violation THEN NULL; END $$;
DO $$ BEGIN
  PERFORM pg_temp.ev('00000000-0000-4000-8000-0000000015ee', 'refunded', 80, DATE '2026-03-01', NULL, 'legacy interest 3.10 paid by cheque 2026-03-01');
  RAISE NOTICE 'PASS E18: a legacy deposit cites no rule, accrues nothing here, and its return says how its interest was settled';
END $$;


-- ============================================================ F. return-due
-- Deposit R: TX residential cash, posted 2026-01-15.
DO $$ BEGIN
  PERFORM pg_temp.dep('r', '00000000-0000-4000-8000-0000000015c1', 'credit_evaluation', 'residential', 'cash', 300, DATE '2026-01-15');
  PERFORM pg_temp.dep('r366', '00000000-0000-4000-8000-0000000015c1', 'adequate_assurance_366', 'residential', 'cash', 100, DATE '2026-01-15');
  PERFORM pg_temp.dep('rbond', '00000000-0000-4000-8000-0000000015c3', 'tariff', 'non_residential', 'letter_of_credit', 900, DATE '2026-01-15');
  PERFORM pg_temp.dep('rfull', '00000000-0000-4000-8000-0000000015c1', 'tariff', 'residential', 'cash', 60, DATE '2026-01-15');
  PERFORM pg_temp.dep('r2', '00000000-0000-4000-8000-0000000015c2', 'credit_evaluation', 'residential', 'cash', 120, DATE '2026-01-15');
END $$;
DO $$ BEGIN
  EXECUTE 'SET CONSTRAINTS ALL DEFERRED';
  PERFORM pg_temp.due('00000000-0000-4000-8000-0000000015d0', pg_temp.id('r'), DATE '2026-04-01');
  EXECUTE 'SET CONSTRAINTS ALL IMMEDIATE';
  RAISE EXCEPTION 'FAIL F1: a due row with no evidence survived the commit check';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'PASS F1: a due row without evidence is refused at commit'; END $$;
SET CONSTRAINTS ALL DEFERRED;
SELECT pg_temp.due('00000000-0000-4000-8000-0000000015d1', pg_temp.id('r'), DATE '2026-04-01');
SELECT pg_temp.evid('00000000-0000-4000-8000-0000000015d1', 'clean_bill_history', '00000000-0000-4000-8000-0000000015e1', 'clean', NULL);
SELECT pg_temp.evid('00000000-0000-4000-8000-0000000015d1', 'clean_bill_history', '00000000-0000-4000-8000-0000000015e2', 'clean', NULL);
SET CONSTRAINTS ALL IMMEDIATE;
DO $$ DECLARE r record; BEGIN
  SELECT * INTO r FROM public.deposits_return_owed WHERE due_id = '00000000-0000-4000-8000-0000000015d1';
  IF r.deposit_id IS DISTINCT FROM pg_temp.id('r') OR r.reasons <> ARRAY['clean_bill_history'] OR r.remainder <> 300 THEN
    RAISE EXCEPTION 'FAIL F2: the owed list does not show the due return: %', row_to_json(r);
  END IF;
  IF (SELECT created_by FROM public.deposit_return_due WHERE id = '00000000-0000-4000-8000-0000000015d1') IS DISTINCT FROM '00000000-0000-4000-8000-0000000015b1'::uuid THEN
    RAISE EXCEPTION 'FAIL F2: created_by not stamped';
  END IF;
  RAISE NOTICE 'PASS F2: the core''s due row and its bill evidence are recorded, stamped, and listed as owed';
END $$;
DO $$ BEGIN
  EXECUTE 'SET CONSTRAINTS ALL DEFERRED';
  PERFORM pg_temp.due('00000000-0000-4000-8000-0000000015d2', pg_temp.id('r'), DATE '2026-04-02');
  RAISE EXCEPTION 'FAIL F3: a second live due row';
EXCEPTION WHEN unique_violation THEN
  RAISE NOTICE 'PASS F3: at most one live due row per deposit — written when the answer changes, not per check'; END $$;
DO $$ BEGIN
  EXECUTE 'SET CONSTRAINTS ALL DEFERRED';
  PERFORM pg_temp.due('00000000-0000-4000-8000-0000000015d2', pg_temp.id('r366'), DATE '2026-04-01');
  RAISE EXCEPTION 'FAIL F4a: a due row on a 366 deposit';
EXCEPTION WHEN check_violation THEN NULL; END $$;
DO $$ BEGIN
  EXECUTE 'SET CONSTRAINTS ALL DEFERRED';
  PERFORM pg_temp.due('00000000-0000-4000-8000-0000000015d2', pg_temp.id('rbond'), DATE '2026-04-01');
  RAISE EXCEPTION 'FAIL F4b: a due row for an instrument the rule does not cover';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'PASS F4: a due row needs a rule that makes the return mandatory for the deposit''s instrument (366 and a TX letter of credit refused, read from the row)'; END $$;
DO $$ BEGIN
  EXECUTE 'SET CONSTRAINTS ALL DEFERRED';
  PERFORM pg_temp.due('00000000-0000-4000-8000-0000000015d2', pg_temp.id('rfull'), DATE '2026-04-01', NULL, pg_temp.r('TX', 'residential', 'credit_evaluation'));
  RAISE EXCEPTION 'FAIL F5: a due row citing another rule';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'PASS F5: a due row cites the deposit''s own rule'; END $$;
DO $$ BEGIN
  EXECUTE 'SET CONSTRAINTS ALL DEFERRED';
  PERFORM pg_temp.due('00000000-0000-4000-8000-0000000015d2', pg_temp.id('rfull'), DATE '2026-01-01');
  RAISE EXCEPTION 'FAIL F6: due before posting';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'PASS F6: a return is not due before the deposit was posted'; END $$;
DO $$ BEGIN
  EXECUTE 'SET CONSTRAINTS ALL DEFERRED';
  PERFORM pg_temp.due('00000000-0000-4000-8000-0000000015d2', '00000000-0000-4000-8000-0000000015ee', DATE '2026-04-01');
  RAISE EXCEPTION 'FAIL F7: a due row on a refunded legacy deposit';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'PASS F7: no due row on a legacy deposit (no rule) or a returned one'; END $$;
-- Evidence on a fresh due row for R-full, one bad row at a time.
DO $$ BEGIN
  EXECUTE 'SET CONSTRAINTS ALL DEFERRED';
  PERFORM pg_temp.due('00000000-0000-4000-8000-0000000015d3', pg_temp.id('rfull'), DATE '2026-04-01');
  PERFORM pg_temp.evid('00000000-0000-4000-8000-0000000015d3', 'account_closed', '00000000-0000-4000-8000-0000000015e1', 'clean', NULL);
  RAISE EXCEPTION 'FAIL F8a: a bill as evidence of a closure';
EXCEPTION WHEN check_violation THEN NULL; END $$;
DO $$ BEGIN
  EXECUTE 'SET CONSTRAINTS ALL DEFERRED';
  PERFORM pg_temp.due('00000000-0000-4000-8000-0000000015d3', pg_temp.id('rfull'), DATE '2026-04-01');
  PERFORM pg_temp.evid('00000000-0000-4000-8000-0000000015d3', 'clean_bill_history', NULL, NULL,
                       (SELECT id FROM public.customer_state_events WHERE customer_id = '00000000-0000-4000-8000-0000000015c1' LIMIT 1));
  RAISE EXCEPTION 'FAIL F8b: a state event as evidence of bills';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'PASS F8: evidence is of its reason''s kind (bills for history, a state change for a closure)'; END $$;
DO $$ BEGIN
  EXECUTE 'SET CONSTRAINTS ALL DEFERRED';
  PERFORM pg_temp.due('00000000-0000-4000-8000-0000000015d3', pg_temp.id('rfull'), DATE '2026-04-01');
  PERFORM pg_temp.evid('00000000-0000-4000-8000-0000000015d3', 'clean_bill_history', '00000000-0000-4000-8000-0000000015e8', 'clean', NULL);
  RAISE EXCEPTION 'FAIL F9a: another customer''s bill';
EXCEPTION WHEN check_violation THEN NULL; END $$;
DO $$ BEGIN
  EXECUTE 'SET CONSTRAINTS ALL DEFERRED';
  PERFORM pg_temp.due('00000000-0000-4000-8000-0000000015d3', pg_temp.id('rfull'), DATE '2026-04-01');
  PERFORM pg_temp.evid('00000000-0000-4000-8000-0000000015d3', 'clean_bill_history', '00000000-0000-4000-8000-0000000015e0', 'clean', NULL);
  RAISE EXCEPTION 'FAIL F9b: a bill from before posting';
EXCEPTION WHEN check_violation THEN NULL; END $$;
DO $$ BEGIN
  EXECUTE 'SET CONSTRAINTS ALL DEFERRED';
  PERFORM pg_temp.due('00000000-0000-4000-8000-0000000015d3', pg_temp.id('rfull'), DATE '2026-04-01');
  PERFORM pg_temp.evid('00000000-0000-4000-8000-0000000015d3', 'account_closed', NULL, NULL,
                       (SELECT id FROM public.customer_state_events WHERE customer_id = '00000000-0000-4000-8000-0000000015c2' LIMIT 1));
  RAISE EXCEPTION 'FAIL F9c: another customer''s state change';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'PASS F9: evidence is the deposit''s customer''s, from on or after posting'; END $$;
-- C1 final-bills; R-full is applied in full and due on two reasons at once.
UPDATE public.customers SET status = 'final_billed', status_reason = 'moved out'
 WHERE id = '00000000-0000-4000-8000-0000000015c1';
SELECT pg_temp.ev(pg_temp.id('rfull'), 'applied_to_balance', 60, DATE '2026-04-01');
SET CONSTRAINTS ALL DEFERRED;
SELECT pg_temp.due('00000000-0000-4000-8000-0000000015d4', pg_temp.id('rfull'), DATE '2026-04-01');
SELECT pg_temp.evid('00000000-0000-4000-8000-0000000015d4', 'account_closed', NULL, NULL,
                    (SELECT id FROM public.customer_state_events WHERE customer_id = '00000000-0000-4000-8000-0000000015c1' AND to_status = 'final_billed'));
SELECT pg_temp.evid('00000000-0000-4000-8000-0000000015d4', 'clean_bill_history', '00000000-0000-4000-8000-0000000015e1', 'clean', NULL);
SET CONSTRAINTS ALL IMMEDIATE;
DO $$ DECLARE r record; BEGIN
  SELECT * INTO r FROM public.deposits_return_owed WHERE due_id = '00000000-0000-4000-8000-0000000015d4';
  IF r.reasons <> ARRAY['account_closed', 'clean_bill_history'] OR r.deposit_status <> 'applied' OR r.remainder <> 0 THEN
    RAISE EXCEPTION 'FAIL F10: %', row_to_json(r);
  END IF;
  RAISE NOTICE 'PASS F10: one due row carries both reasons; a fully applied deposit stays owed (its zero refund is not yet recorded)';
END $$;
DO $$ BEGIN
  PERFORM pg_temp.ev(pg_temp.id('rfull'), 'refunded', 0, DATE '2026-04-02', '00000000-0000-4000-8000-0000000015d1');
  RAISE EXCEPTION 'FAIL F11: a refund citing another deposit''s due row';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'PASS F11: a return cites only its own deposit''s due row'; END $$;
DO $$ BEGIN
  PERFORM pg_temp.ev(pg_temp.id('rfull'), 'refunded', 0, DATE '2026-04-02', '00000000-0000-4000-8000-0000000015d4');
  IF EXISTS (SELECT 1 FROM public.deposits_return_owed WHERE due_id = '00000000-0000-4000-8000-0000000015d4') THEN
    RAISE EXCEPTION 'FAIL F12: still owed after the zero refund';
  END IF;
  BEGIN
    -- 'a' was refunded in E15 and has no due row: only the status guard can refuse.
    EXECUTE 'SET CONSTRAINTS ALL DEFERRED';
    PERFORM pg_temp.due('00000000-0000-4000-8000-0000000015d5', pg_temp.id('a'), DATE '2026-04-03');
    RAISE EXCEPTION 'FAIL F12: a due row on a refunded deposit';
  EXCEPTION WHEN check_violation THEN NULL; END;
  RAISE NOTICE 'PASS F12: the zero refund settles it and leaves the list; no due row follows a refund';
END $$;
-- Withdrawal and a corrected answer.
DO $$ BEGIN
  EXECUTE 'SET CONSTRAINTS ALL DEFERRED';
  PERFORM pg_temp.due('00000000-0000-4000-8000-0000000015d6', pg_temp.id('r2'), DATE '2026-04-01', '00000000-0000-4000-8000-0000000015d1');
  RAISE EXCEPTION 'FAIL F13: superseding another deposit''s live row';
EXCEPTION WHEN check_violation THEN NULL; END $$;
DO $$ BEGIN
  INSERT INTO public.deposit_return_due_withdrawals (tenant_id, due_id, reason)
  VALUES ('00000000-0000-4000-8000-0000000015a1', '00000000-0000-4000-8000-0000000015d1', '   ');
  RAISE EXCEPTION 'FAIL F13: a withdrawal with no reason';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'PASS F13: a withdrawal states its reason; only a withdrawn row of the same deposit can be superseded'; END $$;
INSERT INTO public.deposit_return_due_withdrawals (tenant_id, due_id, reason, calculated_by)
VALUES ('00000000-0000-4000-8000-0000000015a1', '00000000-0000-4000-8000-0000000015d1', 'payment on B15-I2 reversed (NSF)', 'core-test');
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM public.deposits_return_owed WHERE due_id = '00000000-0000-4000-8000-0000000015d1') THEN
    RAISE EXCEPTION 'FAIL F14: a withdrawn row is still owed';
  END IF;
  BEGIN
    INSERT INTO public.deposit_return_due_withdrawals (tenant_id, due_id, reason)
    VALUES ('00000000-0000-4000-8000-0000000015a1', '00000000-0000-4000-8000-0000000015d1', 'again');
    RAISE EXCEPTION 'FAIL F14: withdrawn twice';
  EXCEPTION WHEN unique_violation THEN NULL; END;
  BEGIN
    PERFORM pg_temp.ev(pg_temp.id('r'), 'refund_initiated', 300, DATE '2026-04-05', '00000000-0000-4000-8000-0000000015d1');
    RAISE EXCEPTION 'FAIL F14: a refund citing a withdrawn row';
  EXCEPTION WHEN check_violation THEN NULL; END;
  RAISE NOTICE 'PASS F14: a withdrawn row leaves the list, is withdrawn once, and cannot be cited by a refund';
END $$;
SET CONSTRAINTS ALL DEFERRED;
SELECT pg_temp.due('00000000-0000-4000-8000-0000000015d7', pg_temp.id('r'), DATE '2026-05-01', '00000000-0000-4000-8000-0000000015d1');
SELECT pg_temp.evid('00000000-0000-4000-8000-0000000015d7', 'account_closed', NULL, NULL,
                    (SELECT id FROM public.customer_state_events WHERE customer_id = '00000000-0000-4000-8000-0000000015c1' AND to_status = 'final_billed'));
SET CONSTRAINTS ALL IMMEDIATE;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.deposits_return_owed WHERE due_id = '00000000-0000-4000-8000-0000000015d7') THEN
    RAISE EXCEPTION 'FAIL F15: the corrected answer is not owed';
  END IF;
  PERFORM pg_temp.ev(pg_temp.id('r'), 'refund_initiated', 300, DATE '2026-05-03', '00000000-0000-4000-8000-0000000015d7');
  IF EXISTS (SELECT 1 FROM public.deposits_return_owed WHERE deposit_id = pg_temp.id('r')) THEN
    RAISE EXCEPTION 'FAIL F15: still owed once the refund started';
  END IF;
  -- With d7 withdrawn no row is live, so only the UNIQUE on
  -- supersedes_due_id can refuse superseding d1 a second time.
  INSERT INTO public.deposit_return_due_withdrawals (tenant_id, due_id, reason)
  VALUES ('00000000-0000-4000-8000-0000000015a1', '00000000-0000-4000-8000-0000000015d7', 'battery: free the deposit');
  BEGIN
    EXECUTE 'SET CONSTRAINTS ALL DEFERRED';
    PERFORM pg_temp.due('00000000-0000-4000-8000-0000000015d8', pg_temp.id('r'), DATE '2026-05-04', '00000000-0000-4000-8000-0000000015d1');
    RAISE EXCEPTION 'FAIL F15: a withdrawn row superseded twice';
  EXCEPTION WHEN unique_violation THEN NULL; END;
  RAISE NOTICE 'PASS F15: a corrected answer names the row it supersedes (once); the list drops it when the refund starts';
END $$;
DO $$ BEGIN
  UPDATE public.deposit_return_due SET due_on = DATE '2026-06-01' WHERE id = '00000000-0000-4000-8000-0000000015d7';
  RAISE EXCEPTION 'FAIL F16a: a due row edited';
EXCEPTION WHEN insufficient_privilege THEN NULL; END $$;
DO $$ BEGIN
  DELETE FROM public.deposit_return_due_withdrawals WHERE due_id = '00000000-0000-4000-8000-0000000015d1';
  RAISE EXCEPTION 'FAIL F16b: a withdrawal deleted';
EXCEPTION WHEN insufficient_privilege THEN NULL; END $$;
RESET ROLE;
DO $$ BEGIN
  UPDATE public.deposit_return_due SET due_on = DATE '2026-06-01' WHERE id = '00000000-0000-4000-8000-0000000015d7';
  RAISE EXCEPTION 'FAIL F16c: the owner edited a due row';
EXCEPTION WHEN restrict_violation THEN NULL; END $$;
DO $$ BEGIN
  DELETE FROM public.deposit_return_due_evidence WHERE due_id = '00000000-0000-4000-8000-0000000015d7';
  RAISE EXCEPTION 'FAIL F16d: the owner deleted evidence';
EXCEPTION WHEN restrict_violation THEN
  RAISE NOTICE 'PASS F16: due rows, evidence and withdrawals are append-only, for the owner too'; END $$;


-- ============================================================ G. surfaces
SET LOCAL app.user_id = '00000000-0000-4000-8000-0000000015b2';
SET ROLE tally_app;
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM public.deposit_return_due) OR EXISTS (SELECT 1 FROM public.deposit_return_due_evidence)
     OR EXISTS (SELECT 1 FROM public.deposit_return_due_withdrawals) OR EXISTS (SELECT 1 FROM public.deposits_return_owed)
     OR EXISTS (SELECT 1 FROM public.deposits) THEN
    RAISE EXCEPTION 'FAIL G1: T2 sees T1''s deposit records';
  END IF;
  RAISE NOTICE 'PASS G1: another tenant sees none of the due rows, evidence, withdrawals, owed list or deposits';
END $$;
DO $$ BEGIN
  INSERT INTO public.deposit_return_due_withdrawals (tenant_id, due_id, reason)
  VALUES ('00000000-0000-4000-8000-0000000015a2', '00000000-0000-4000-8000-0000000015d7', 'cross-tenant');
  RAISE EXCEPTION 'FAIL G2: a cross-tenant withdrawal';
EXCEPTION WHEN foreign_key_violation OR insufficient_privilege THEN
  RAISE NOTICE 'PASS G2: a tenant cannot withdraw another tenant''s due row'; END $$;
DO $$ BEGIN
  INSERT INTO public.deposits_return_owed (due_id) VALUES (public.uuid_generate_v4());
  RAISE EXCEPTION 'FAIL G3: wrote through the owed view';
EXCEPTION WHEN insufficient_privilege OR object_not_in_prerequisite_state OR feature_not_supported THEN
  RAISE NOTICE 'PASS G3: the owed list and the rate report are read-only'; END $$;
RESET ROLE;
DO $$ BEGIN
  PERFORM public.assert_tenant_isolation_invariants();
  IF obj_description('public.deposit_rules'::regclass, 'pg_class') !~ 'core'
     OR obj_description('public.deposits'::regclass, 'pg_class') !~ 'core'
     OR obj_description('public.enforce_deposit_event()'::regprocedure, 'pg_proc') !~ 'Decides no law' THEN
    RAISE EXCEPTION 'FAIL G4: a comment still says the database decides';
  END IF;
  RAISE NOTICE 'PASS G4: tenant isolation holds over the new tables and views (AC-32); the comments say the core decides';
END $$;

ROLLBACK;
