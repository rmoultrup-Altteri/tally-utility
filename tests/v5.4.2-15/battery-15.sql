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
--   N  review round 2: thresholds, instalments, partial returns, cap parts,
--      chronology, evidence dates, UTC, the rate report, tariff closes
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
DECLARE v_rule public.deposit_rules%ROWTYPE; v_id uuid; v_t uuid; v_kind text; v_thr public.deposit_rule_trigger_thresholds%ROWTYPE;
BEGIN
  SELECT tenant_id INTO v_t FROM public.customers WHERE id = p_cust;
  -- the rule of its key in force on the posting date
  SELECT * INTO v_rule FROM public.deposit_rules
   WHERE state_code = p_state AND service_type = 'gas' AND customer_class = p_class AND basis = p_basis
     AND daterange(effective_from, effective_to, '[)') @> p_posted;
  -- the part that governed the cap: the first (the battery's caps are one part
  -- or name their governing part in their own tests)
  SELECT cap_kind INTO v_kind FROM public.deposit_rule_cap_parts WHERE rule_id = v_rule.id ORDER BY part_no LIMIT 1;
  -- an NSF trigger deposit: the statute's threshold, met exactly, when the rule sets one
  SELECT * INTO v_thr FROM public.deposit_rule_trigger_thresholds WHERE rule_id = v_rule.id AND trigger_code = 'nsf';
  INSERT INTO public.deposits (tenant_id, customer_id, basis, trigger_basis, instrument, instrument_reference, principal, posted_on,
                               state_code, service_type, customer_class, rule_id, cap_amount, cap_basis_kind, cap_basis_amount,
                               cap_source, cap_other_held, trigger_threshold_source, trigger_rule_threshold_id, trigger_observed, decided_by)
  VALUES (v_t, p_cust, p_basis, CASE WHEN (SELECT requires_trigger FROM public.deposit_bases WHERE basis_code = p_basis) THEN 'nsf' END, p_instr,
          CASE WHEN p_instr <> 'cash' THEN 'REF-' || p_k END, p_principal, p_posted,
          p_state, 'gas', p_class, v_rule.id,
          CASE WHEN v_rule.cap_combinator <> 'none' THEN p_principal END,
          CASE WHEN v_rule.cap_combinator <> 'none' THEN v_kind END,
          CASE WHEN v_kind IN ('fraction_of_annual_billing', 'months_of_billing') THEN p_principal * 6 END,
          CASE WHEN v_rule.cap_combinator <> 'none' THEN 'statute' END,
          CASE WHEN v_rule.cap_scope = 'combined' THEN 0 END,
          CASE WHEN v_thr.id IS NOT NULL THEN 'statute' END, v_thr.id, coalesce(v_thr.min_count::numeric, v_thr.min_ratio),
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
-- accb(): an accrual on a stated principal basis.
CREATE FUNCTION pg_temp.accb(p_dep uuid, p_rate uuid, p_from date, p_to date, p_amount numeric, p_on date, p_basis numeric) RETURNS void
LANGUAGE sql AS $$
  INSERT INTO public.deposit_events (tenant_id, deposit_id, event_type, amount, effective_on, period_start, period_end,
                                     rate_applied, principal_basis, rate_id, rule_id, calculated_by)
  SELECT d.tenant_id, d.id, 'interest_accrued', p_amount, p_on, p_from, p_to,
         (SELECT annual_rate FROM public.deposit_interest_rates WHERE id = p_rate), p_basis, p_rate, d.rule_id, 'core-test'
    FROM public.deposits d WHERE d.id = p_dep
$$;
GRANT EXECUTE ON FUNCTION pg_temp.accb(uuid, uuid, date, date, numeric, date, numeric) TO tally_app;
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
  IF NOT (r.cap_combinator = 'single' AND r.cap_scope = 'per_deposit' AND NOT r.refund_excess_over_cap
          AND (SELECT array_agg(cap_kind || '/' || cap_divisor) FROM public.deposit_rule_cap_parts WHERE rule_id = r.id) = ARRAY['fraction_of_annual_billing/6']
          AND r.interest_bearing_instruments = ARRAY['cash'] AND r.interest_min_hold_days = 30 AND r.interest_retroactive
          AND r.interest_method = 'simple' AND r.interest_day_count = 'actual_365' AND r.interest_credit_cadence = 'at_refund'
          AND r.refund_mandatory AND r.refund_after_count = 12 AND r.refund_measure = 'bills' AND r.refund_max_delinquencies = 2
          AND r.refund_lookback_quantity IS NULL AND r.refund_on_account_close AND r.refund_obligation_vests IS NULL
          AND r.return_mandatory_instruments = ARRAY['cash']) THEN
    RAISE EXCEPTION 'FAIL A2: the TX residential credit-evaluation row does not carry -06''s law: %', row_to_json(r);
  END IF;
  SELECT * INTO r FROM public.deposit_rules WHERE id = pg_temp.r('TX', 'non_residential', 'tariff');
  IF r.cap_combinator <> 'none' OR NOT r.refund_mandatory THEN RAISE EXCEPTION 'FAIL A2: TX non-residential row wrong'; END IF;
  SELECT * INTO r FROM public.deposit_rules WHERE id = pg_temp.r('TX', 'residential', 'adequate_assurance_366');
  IF r.refund_mandatory OR r.cap_combinator <> 'none' THEN RAISE EXCEPTION 'FAIL A2: TX 366 row wrong'; END IF;
  -- §7.45(5)(C)(ii) on both additional-deposit rules, and nowhere else
  IF (SELECT count(*) FROM public.deposit_rule_trigger_thresholds t JOIN public.deposit_rules y ON y.id = t.rule_id
       WHERE y.state_code = 'TX' AND y.basis = 'additional_trigger' AND t.trigger_code = 'usage_doubled'
         AND t.measure = 'usage_ratio' AND t.min_ratio = 2 AND t.payment_due_days = 2) <> 2
     OR (SELECT count(*) FROM public.deposit_rule_trigger_thresholds) <> 2 THEN
    RAISE EXCEPTION 'FAIL A2: the 7.45(5)(C)(ii) usage threshold is not on the two TX additional-deposit rules';
  END IF;
  IF (SELECT count(*) FROM public.deposit_rule_waiver_reach x WHERE x.rule_id = pg_temp.r('TX', 'residential', 'credit_evaluation')
        AND x.effect = 'excuse' AND x.trigger_code IS NULL) <> 4
     OR EXISTS (SELECT 1 FROM public.deposit_rule_waiver_reach x JOIN public.deposit_rules y ON y.id = x.rule_id WHERE y.basis = 'adequate_assurance_366')
     OR (SELECT count(*) FROM public.deposit_rule_waiver_reach x JOIN public.deposit_rules y ON y.id = x.rule_id WHERE y.state_code = 'TX') <> 24
     OR (SELECT array_agg(disqualifier_code) FROM public.deposit_rule_refund_disqualifiers WHERE rule_id = pg_temp.r('TX', 'non_residential', 'tariff'))
        <> ARRAY['disconnect_nonpayment'] THEN
    RAISE EXCEPTION 'FAIL A2: the TX reach or disqualifier rows are not -06''s';
  END IF;
  RAISE NOTICE 'PASS A2: the Texas rows carry what -06 enforced and 7.45(5)(C)(ii) (cap 1/6 residential as one part, no excess return; usage twice the estimate payable in 2 days on the additional-deposit rules; 30-day retroactive simple interest, 12 bills / 2 late over the whole hold / disconnection disqualifies / close; every waiver excuses the six 7.45 rules, none reaches 366 — 24 reach rows; vesting unruled)';
END $$;
DO $$ BEGIN
  INSERT INTO public.deposit_bases (basis_code, is_federal, insertable, description) VALUES ('x_basis', false, true, 'x');
  RAISE EXCEPTION 'FAIL A3a: the application wrote a basis';
EXCEPTION WHEN insufficient_privilege THEN NULL; END $$;
DO $$ BEGIN
  UPDATE public.deposit_rules SET refund_mandatory = false WHERE id = pg_temp.r('TX', 'residential', 'tariff');
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
  UPDATE public.deposit_rules SET refund_mandatory = false WHERE id = pg_temp.r('TX', 'residential', 'tariff');
  RAISE EXCEPTION 'FAIL A4: the owner edited a rule row';
EXCEPTION WHEN restrict_violation THEN
  RAISE NOTICE 'PASS A4: not even the owner edits a rule row (deposits, accruals and due rows cite it)'; END $$;
DO $$ BEGIN
  -- a rule nothing references (no reach, no disqualifier, no citation), so
  -- only the history guard can refuse
  DELETE FROM public.deposit_rules WHERE id = pg_temp.r('TX', 'non_residential', 'adequate_assurance_366');
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
  UPDATE public.deposit_return_reasons SET description = 'edited' WHERE reason_code = 'account_closed';
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
  RAISE NOTICE 'PASS A7: the vocabularies are never edited or deleted, by the owner either'; END $$;
DO $$ BEGIN
  DELETE FROM public.deposit_rule_waiver_reach WHERE rule_id = pg_temp.r('TX', 'residential', 'tariff');
  RAISE EXCEPTION 'FAIL A7f: reach rows deleted';
EXCEPTION WHEN restrict_violation THEN NULL; END $$;
DO $$ BEGIN
  UPDATE public.deposit_rule_refund_disqualifiers SET disqualifier_code = 'returned_payment' WHERE rule_id = pg_temp.r('TX', 'residential', 'tariff');
  RAISE EXCEPTION 'FAIL A7g: a disqualifier edited';
EXCEPTION WHEN restrict_violation THEN
  RAISE NOTICE 'PASS A7b: a rule''s reach and disqualifier rows are never edited or deleted'; END $$;
DO $$ BEGIN
  UPDATE public.deposit_rule_cap_parts SET cap_divisor = 5 WHERE rule_id = pg_temp.r('TX', 'residential', 'tariff');
  RAISE EXCEPTION 'FAIL A7h: a cap part edited';
EXCEPTION WHEN restrict_violation THEN NULL; END $$;
DO $$ BEGIN
  DELETE FROM public.deposit_rule_trigger_thresholds WHERE rule_id = pg_temp.r('TX', 'residential', 'additional_trigger');
  RAISE EXCEPTION 'FAIL A7i: a trigger threshold deleted';
EXCEPTION WHEN restrict_violation THEN
  RAISE NOTICE 'PASS A7c: a rule''s cap parts and thresholds are never edited or deleted'; END $$;
DO $$ BEGIN
  -- The TX rules were recorded when the patch applied: a reach row added now
  -- would change the law their citations were decided under.
  INSERT INTO public.deposit_rule_waiver_reach (rule_id, state_code, service_type, waiver_class, effect)
  VALUES (pg_temp.r('TX', 'residential', 'adequate_assurance_366'), 'TX', 'gas', 'family_violence_certified', 'excuse');
  RAISE EXCEPTION 'FAIL A10a: reach added to a rule recorded earlier';
EXCEPTION WHEN restrict_violation THEN NULL; END $$;
DO $$ BEGIN
  INSERT INTO public.deposit_rule_refund_disqualifiers (rule_id, disqualifier_code)
  VALUES (pg_temp.r('TX', 'residential', 'tariff'), 'returned_payment');
  RAISE EXCEPTION 'FAIL A10b: a disqualifier added to a rule recorded earlier';
EXCEPTION WHEN restrict_violation THEN NULL; END $$;
DO $$ BEGIN
  INSERT INTO public.deposit_rule_trigger_thresholds (rule_id, trigger_code, measure, min_count, window_months)
  VALUES (pg_temp.r('TX', 'residential', 'additional_trigger'), 'nsf', 'event_count', 2, 12);
  RAISE EXCEPTION 'FAIL A10c: a threshold added to a rule recorded earlier';
EXCEPTION WHEN restrict_violation THEN
  RAISE NOTICE 'PASS A10: a rule''s parts are written in the rule''s own transaction (K2''s answer is a close and a successor, not an added row)'; END $$;
DO $$ BEGIN
  INSERT INTO public.deposit_rules (state_code, service_type, customer_class, basis, cap_combinator, refund_excess_over_cap,
     interest_bearing_instruments, refund_mandatory, effective_from, source_note)
  VALUES ('TX', 'gas', 'residential', 'tariff', 'none', false, '{}', false, DATE '2020-01-01', 'overlapping row');
  RAISE EXCEPTION 'FAIL A8: an overlapping rule row was accepted';
EXCEPTION WHEN exclusion_violation THEN
  RAISE NOTICE 'PASS A8: two rule rows for one key never overlap'; END $$;
DO $$ DECLARE v uuid; BEGIN
  -- deferred, so the commit-time part count cannot refuse first
  EXECUTE 'SET CONSTRAINTS ALL DEFERRED';
  INSERT INTO public.deposit_rules (state_code, service_type, customer_class, basis, cap_combinator, refund_excess_over_cap, cap_scope,
     interest_bearing_instruments, refund_mandatory, effective_from, effective_to, source_note)
  VALUES ('TX', 'gas', 'residential', 'tariff', 'single', false, 'per_deposit', '{}', false, DATE '1990-01-01', DATE '2000-01-01', 'no divisor')
  RETURNING id INTO v;
  INSERT INTO public.deposit_rule_cap_parts (rule_id, part_no, cap_kind) VALUES (v, 1, 'fraction_of_annual_billing');
  RAISE EXCEPTION 'FAIL A9a: a fraction cap part without its divisor';
EXCEPTION WHEN check_violation THEN NULL; END $$;
DO $$ BEGIN
  INSERT INTO public.deposit_rules (state_code, service_type, customer_class, basis, cap_combinator, refund_excess_over_cap,
     interest_bearing_instruments, interest_method, refund_mandatory, effective_from, effective_to, source_note)
  VALUES ('TX', 'gas', 'residential', 'tariff', 'none', false, '{}', 'simple', false, DATE '1990-01-01', DATE '2000-01-01', 'method, no instruments');
  RAISE EXCEPTION 'FAIL A9b: an interest method with no interest-bearing instrument';
EXCEPTION WHEN check_violation THEN NULL; END $$;
DO $$ BEGIN
  INSERT INTO public.deposit_rules (state_code, service_type, customer_class, basis, cap_combinator, refund_excess_over_cap,
     interest_bearing_instruments, interest_method, interest_day_count, interest_credit_cadence, interest_min_hold_days,
     refund_mandatory, effective_from, effective_to, source_note)
  VALUES ('TX', 'gas', 'residential', 'tariff', 'none', false, ARRAY['cash'], 'simple', 'actual_365', 'at_refund', 30,
          false, DATE '1990-01-01', DATE '2000-01-01', 'a hold without saying whether interest then runs from posting');
  RAISE EXCEPTION 'FAIL A9c: a minimum hold without retroactivity';
EXCEPTION WHEN check_violation THEN NULL; END $$;
DO $$ BEGIN
  INSERT INTO public.deposit_rules (state_code, service_type, customer_class, basis, cap_combinator, refund_excess_over_cap,
     interest_bearing_instruments, refund_mandatory, refund_after_count, effective_from, effective_to, source_note)
  VALUES ('TX', 'gas', 'residential', 'tariff', 'none', false, '{}', false, 12, DATE '1990-01-01', DATE '2000-01-01', 'a trigger count on no mandatory return');
  RAISE EXCEPTION 'FAIL A9d: a refund count with no mandatory return';
EXCEPTION WHEN check_violation THEN NULL; END $$;
DO $$ BEGIN
  INSERT INTO public.deposit_rules (state_code, service_type, customer_class, basis, cap_combinator, refund_excess_over_cap,
     interest_bearing_instruments, refund_mandatory, refund_on_account_close, return_mandatory_instruments,
     refund_after_count, effective_from, effective_to, source_note)
  VALUES ('TX', 'gas', 'residential', 'tariff', 'none', false, '{}', true, true, ARRAY['cash'], 12, DATE '1990-01-01', DATE '2000-01-01', 'a count without its measure');
  RAISE EXCEPTION 'FAIL A9e: a refund count without measure and limits';
EXCEPTION WHEN check_violation THEN NULL; END $$;
DO $$ BEGIN
  INSERT INTO public.deposit_rules (state_code, service_type, customer_class, basis, cap_combinator, refund_excess_over_cap,
     interest_bearing_instruments, refund_mandatory, effective_from, effective_to, source_note)
  VALUES ('TX', 'gas', 'residential', 'tariff', 'none', false, '{}', false, DATE '1990-01-01', DATE '2000-01-01', '   ');
  RAISE EXCEPTION 'FAIL A9f: a rule without a citation';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'PASS A9: a rule row says each thing whole or not at all (cap and figure, interest and its terms, a return and its trigger) and cites its source'; END $$;

-- ---- review r2: the rule's new parts and their shape (owner, with the
-- completeness check deferred so each case reaches the guard it names)
DO $$ DECLARE v uuid; BEGIN
  EXECUTE 'SET CONSTRAINTS ALL DEFERRED';
  INSERT INTO public.deposit_rules (state_code, service_type, customer_class, basis, cap_combinator, refund_excess_over_cap,
     interest_bearing_instruments, refund_mandatory, effective_from, effective_to, source_note)
  VALUES ('TX', 'gas', 'residential', 'tariff', 'none', false, '{}', false, DATE '1990-01-01', DATE '2000-01-01', 'no cap')
  RETURNING id INTO v;
  INSERT INTO public.deposit_rule_cap_parts (rule_id, part_no, cap_kind, cap_divisor) VALUES (v, 1, 'fraction_of_annual_billing', 6);
  RAISE EXCEPTION 'FAIL A11a: a cap part on a rule with no cap';
EXCEPTION WHEN check_violation THEN NULL; END $$;
DO $$ DECLARE v uuid; BEGIN
  EXECUTE 'SET CONSTRAINTS ALL DEFERRED';
  INSERT INTO public.deposit_rules (state_code, service_type, customer_class, basis, cap_combinator, refund_excess_over_cap, cap_scope,
     interest_bearing_instruments, refund_mandatory, effective_from, effective_to, source_note)
  VALUES ('TX', 'gas', 'residential', 'tariff', 'single', false, 'per_deposit', '{}', false, DATE '1990-01-01', DATE '2000-01-01', 'two parts, single')
  RETURNING id INTO v;
  INSERT INTO public.deposit_rule_cap_parts (rule_id, part_no, cap_kind, cap_divisor, cap_months) VALUES
    (v, 1, 'fraction_of_annual_billing', 6, NULL), (v, 2, 'months_of_billing', NULL, 2);
  EXECUTE 'SET CONSTRAINTS ALL IMMEDIATE';
  RAISE EXCEPTION 'FAIL A11b: a single cap with two parts';
EXCEPTION WHEN check_violation THEN NULL; END $$;
DO $$ DECLARE v uuid; BEGIN
  EXECUTE 'SET CONSTRAINTS ALL DEFERRED';
  INSERT INTO public.deposit_rules (state_code, service_type, customer_class, basis, cap_combinator, refund_excess_over_cap, cap_scope,
     interest_bearing_instruments, refund_mandatory, effective_from, effective_to, source_note)
  VALUES ('TX', 'gas', 'residential', 'tariff', 'greater_of', false, 'per_deposit', '{}', false, DATE '1990-01-01', DATE '2000-01-01', 'greater of one part')
  RETURNING id INTO v;
  INSERT INTO public.deposit_rule_cap_parts (rule_id, part_no, cap_kind, cap_divisor) VALUES (v, 1, 'fraction_of_annual_billing', 5);
  EXECUTE 'SET CONSTRAINTS ALL IMMEDIATE';
  RAISE EXCEPTION 'FAIL A11c: a greater-of cap with one part';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'PASS A11: a cap has the parts its combinator needs (none: no part; single: one; lesser/greater of: two or more) — checked at commit (review r2 D2)'; END $$;
DO $$ DECLARE v uuid; BEGIN
  EXECUTE 'SET CONSTRAINTS ALL DEFERRED';
  INSERT INTO public.deposit_rules (state_code, service_type, customer_class, basis, cap_combinator, refund_excess_over_cap,
     interest_bearing_instruments, refund_mandatory, effective_from, effective_to, source_note)
  VALUES ('TX', 'gas', 'residential', 'tariff', 'none', false, '{}', false, DATE '1990-01-01', DATE '2000-01-01', 'schedule short of whole')
  RETURNING id INTO v;
  INSERT INTO public.deposit_rule_instalments (rule_id, instalment_no, fraction, days_after) VALUES (v, 1, 0.5, 0), (v, 2, 0.25, 30);
  EXECUTE 'SET CONSTRAINTS ALL IMMEDIATE';
  RAISE EXCEPTION 'FAIL A12a: an instalment schedule summing to 0.75';
EXCEPTION WHEN check_violation THEN NULL; END $$;
DO $$ DECLARE v uuid; BEGIN
  EXECUTE 'SET CONSTRAINTS ALL DEFERRED';
  INSERT INTO public.deposit_rules (state_code, service_type, customer_class, basis, cap_combinator, refund_excess_over_cap,
     interest_bearing_instruments, refund_mandatory, effective_from, effective_to, source_note)
  VALUES ('TX', 'gas', 'residential', 'tariff', 'none', false, '{}', false, DATE '1990-01-01', DATE '2000-01-01', 'schedule with a gap')
  RETURNING id INTO v;
  INSERT INTO public.deposit_rule_instalments (rule_id, instalment_no, fraction, days_after) VALUES (v, 1, 0.5, 0), (v, 3, 0.5, 60);
  EXECUTE 'SET CONSTRAINTS ALL IMMEDIATE';
  RAISE EXCEPTION 'FAIL A12b: an instalment schedule numbered 1, 3';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'PASS A12: an instalment schedule runs 1..n and sums to the whole deposit, at commit (review r2 D3)'; END $$;
DO $$ DECLARE v uuid; BEGIN
  EXECUTE 'SET CONSTRAINTS ALL DEFERRED';
  INSERT INTO public.deposit_rules (state_code, service_type, customer_class, basis, cap_combinator, refund_excess_over_cap,
     interest_bearing_instruments, refund_mandatory, effective_from, effective_to, source_note)
  VALUES ('TX', 'gas', 'residential', 'tariff', 'none', false, '{}', false, DATE '1990-01-01', DATE '2000-01-01', 'threshold, no trigger')
  RETURNING id INTO v;
  INSERT INTO public.deposit_rule_trigger_thresholds (rule_id, trigger_code, measure, min_count, window_months) VALUES (v, 'nsf', 'event_count', 2, 12);
  RAISE EXCEPTION 'FAIL A13a: a trigger threshold on a basis that names no trigger';
EXCEPTION WHEN check_violation THEN NULL; END $$;
DO $$ DECLARE v uuid; BEGIN
  EXECUTE 'SET CONSTRAINTS ALL DEFERRED';
  INSERT INTO public.deposit_rules (state_code, service_type, customer_class, basis, cap_combinator, refund_excess_over_cap,
     interest_bearing_instruments, refund_mandatory, effective_from, effective_to, source_note)
  VALUES ('TX', 'gas', 'residential', 'additional_trigger', 'none', false, '{}', false, DATE '1990-01-01', DATE '2000-01-01', 'ratio of one')
  RETURNING id INTO v;
  INSERT INTO public.deposit_rule_trigger_thresholds (rule_id, trigger_code, measure, min_ratio) VALUES (v, 'usage_doubled', 'usage_ratio', 1);
  RAISE EXCEPTION 'FAIL A13b: a usage ratio of 1 (any use at all)';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'PASS A13: a trigger threshold is set only for a basis that names a trigger, and whole (a count in a window, or a ratio above 1) — review r2 D1'; END $$;
DO $$ DECLARE v uuid; BEGIN
  EXECUTE 'SET CONSTRAINTS ALL DEFERRED';
  INSERT INTO public.deposit_rules (state_code, service_type, customer_class, basis, cap_combinator, refund_excess_over_cap,
     interest_bearing_instruments, refund_mandatory, effective_from, effective_to, source_note)
  VALUES ('TX', 'gas', 'residential', 'additional_trigger', 'none', false, '{}', false, DATE '1990-01-01', DATE '2000-01-01', 'mixed reach')
  RETURNING id INTO v;
  INSERT INTO public.deposit_rule_waiver_reach (rule_id, state_code, service_type, waiver_class, trigger_code, effect)
  VALUES (v, 'TX', 'gas', 'good_payment_history', 'nsf', 'excuse');
  INSERT INTO public.deposit_rule_waiver_reach (rule_id, state_code, service_type, waiver_class, trigger_code, effect)
  VALUES (v, 'TX', 'gas', 'good_payment_history', NULL, 'excuse');
  RAISE EXCEPTION 'FAIL A14a: one class reaching a rule for one trigger and for any';
EXCEPTION WHEN check_violation THEN NULL; END $$;
DO $$ DECLARE v uuid; BEGIN
  EXECUTE 'SET CONSTRAINTS ALL DEFERRED';
  INSERT INTO public.deposit_rules (state_code, service_type, customer_class, basis, cap_combinator, refund_excess_over_cap,
     interest_bearing_instruments, refund_mandatory, effective_from, effective_to, source_note)
  VALUES ('TX', 'gas', 'residential', 'additional_trigger', 'none', false, '{}', false, DATE '1990-01-01', DATE '2000-01-01', 'mixed reach, other order')
  RETURNING id INTO v;
  INSERT INTO public.deposit_rule_waiver_reach (rule_id, state_code, service_type, waiver_class, trigger_code, effect)
  VALUES (v, 'TX', 'gas', 'good_payment_history', NULL, 'excuse');
  INSERT INTO public.deposit_rule_waiver_reach (rule_id, state_code, service_type, waiver_class, trigger_code, effect, defer_days)
  VALUES (v, 'TX', 'gas', 'good_payment_history', 'broken_dpa', 'defer', 30);
  RAISE EXCEPTION 'FAIL A14b: one class reaching a rule for any trigger and for one';
EXCEPTION WHEN check_violation THEN
  -- and two different classes, one any-trigger and one per-trigger, are fine
  DECLARE w uuid; BEGIN
    INSERT INTO public.deposit_rules (state_code, service_type, customer_class, basis, cap_combinator, refund_excess_over_cap,
       interest_bearing_instruments, refund_mandatory, effective_from, effective_to, source_note)
    VALUES ('TX', 'gas', 'residential', 'additional_trigger', 'none', false, '{}', false, DATE '1990-01-01', DATE '2000-01-01', 'two classes')
    RETURNING id INTO w;
    INSERT INTO public.deposit_rule_waiver_reach (rule_id, state_code, service_type, waiver_class, trigger_code, effect) VALUES
      (w, 'TX', 'gas', 'good_payment_history', NULL, 'excuse'),
      (w, 'TX', 'gas', 'age_65_no_balance', 'nsf', 'excuse');
    RAISE EXCEPTION 'rollback A14';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'rollback A14' THEN RAISE; END IF;
  END;
  RAISE NOTICE 'PASS A14: one waiver class reaches a rule for any trigger or trigger by trigger, never both (review r2 I7)'; END $$;
DO $$ DECLARE v uuid; BEGIN
  -- a return on time held: a count in months, no delinquency limit (I2) ...
  INSERT INTO public.deposit_rules (state_code, service_type, customer_class, basis, cap_combinator, refund_excess_over_cap,
     interest_bearing_instruments, refund_mandatory, refund_after_count, refund_measure, refund_on_account_close,
     return_mandatory_instruments, effective_from, effective_to, source_note)
  VALUES ('TX', 'gas', 'residential', 'tariff', 'none', false, '{}', true, 24, 'months', false, ARRAY['cash'],
          DATE '1990-01-01', DATE '2000-01-01', 'held 24 months')
  RETURNING id INTO v;
  -- ... but a lookback is the window of a delinquency limit, so not without one
  BEGIN
    INSERT INTO public.deposit_rules (state_code, service_type, customer_class, basis, cap_combinator, refund_excess_over_cap,
       interest_bearing_instruments, refund_mandatory, refund_after_count, refund_measure, refund_lookback_quantity, refund_lookback_unit,
       refund_on_account_close, return_mandatory_instruments, effective_from, effective_to, source_note)
    VALUES ('TX', 'gas', 'non_residential', 'tariff', 'none', false, '{}', true, 24, 'months', 12, 'months', false, ARRAY['cash'],
            DATE '1990-01-01', DATE '2000-01-01', 'lookback, no limit');
    RAISE EXCEPTION 'FAIL A15: a lookback with no delinquency limit';
  EXCEPTION WHEN check_violation THEN NULL; END;
  RAISE EXCEPTION 'rollback A15';
EXCEPTION WHEN raise_exception THEN
  IF SQLERRM <> 'rollback A15' THEN RAISE; END IF;
  RAISE NOTICE 'PASS A15: a return on time held needs no delinquency limit; a lookback needs one (review r2 I2)'; END $$;


-- ============================================================ Z. a second state
-- ZZ is fictional and unlike Texas: three classes, a waiver class Texas lacks
-- (certification-backed), a cap of two months' billing on the COMBINED total,
-- interest from day 1 on cash and certificates, compound, actual/actual,
-- credited annually; the return due after 24 months with at most one
-- delinquency, not on close, and it stays owed once due; a return reason
-- Texas lacks. All rows, no DDL.
DO $$ DECLARE v uuid; BEGIN
  EXECUTE 'SET CONSTRAINTS ALL DEFERRED';
  INSERT INTO public.deposit_customer_classes (state_code, service_type, class_code, description, source_note) VALUES
    ('ZZ', 'gas', 'household', 'Households.', 'ZZ Code 1.1'),
    ('ZZ', 'gas', 'small_business', 'Small businesses.', 'ZZ Code 1.2'),
    ('ZZ', 'gas', 'large_volume', 'Large-volume users.', 'ZZ Code 1.3');
  INSERT INTO public.deposit_waiver_classes (state_code, service_type, class_code, requires_certification, tariff_defined, description, source_note) VALUES
    ('ZZ', 'gas', 'veteran', true, false, 'Certified veteran.', 'ZZ Code 2.1'),
    ('ZZ', 'gas', 'senior', false, false, 'Aged 62 or older.', 'ZZ Code 2.2');
  INSERT INTO public.deposit_return_reasons (reason_code, evidence_kind, enabled_by, partial, description) VALUES
    ('service_term_complete', 'invoice', 'history_trigger', false, 'The service term the rule names has elapsed.');
  INSERT INTO public.deposit_rules (state_code, service_type, customer_class, basis, cap_combinator, cap_scope,
     interest_bearing_instruments, interest_method, interest_day_count, interest_credit_cadence,
     refund_mandatory, refund_after_count, refund_measure, refund_max_delinquencies, refund_lookback_quantity, refund_lookback_unit,
     refund_on_account_close, refund_obligation_vests, return_mandatory_instruments, refund_excess_over_cap, effective_from, source_note)
  VALUES ('ZZ', 'gas', 'household', 'credit_evaluation', 'single', 'combined',
          ARRAY['cash', 'certificate_of_deposit'], 'compound_annual', 'actual_actual', 'annual',
          true, 24, 'months', 1, 12, 'months', false, true, ARRAY['cash', 'certificate_of_deposit'], true,
          DATE '2025-01-01', 'ZZ Code 3.1-3.9')
  RETURNING id INTO v;
  INSERT INTO b15 VALUES ('zz_rule', v);
  INSERT INTO public.deposit_rule_cap_parts (rule_id, part_no, cap_kind, cap_months) VALUES (v, 1, 'months_of_billing', 2);
  -- Its parts, in its transaction: a veteran is excused; a senior pays half;
  -- a returned payment disqualifies the history trigger.
  INSERT INTO public.deposit_rule_waiver_reach (rule_id, state_code, service_type, waiver_class, effect, reduce_fraction) VALUES
    (v, 'ZZ', 'gas', 'veteran', 'excuse', NULL),
    (v, 'ZZ', 'gas', 'senior', 'reduce', 0.5);
  INSERT INTO public.deposit_rule_refund_disqualifiers (rule_id, disqualifier_code) VALUES (v, 'returned_payment');
  -- An additional-deposit rule: a senior's waiver defers an NSF deposit 60
  -- days and does not reach a disconnection-history one.
  -- It is paid in instalments if the customer elects (half now, a quarter at
  -- 30 and 60 days — the Pennsylvania shape), and its triggers have
  -- thresholds: two NSFs in 12 months, use two and a half times the estimate.
  INSERT INTO public.deposit_rules (state_code, service_type, customer_class, basis, cap_combinator, cap_scope,
     interest_bearing_instruments, refund_mandatory, refund_excess_over_cap, effective_from, source_note)
  VALUES ('ZZ', 'gas', 'household', 'additional_trigger', 'single', 'combined', '{}', false, false, DATE '2025-01-01', 'ZZ Code 4')
  RETURNING id INTO v;
  INSERT INTO b15 VALUES ('zz_add_rule', v);
  INSERT INTO public.deposit_rule_cap_parts (rule_id, part_no, cap_kind, cap_months) VALUES (v, 1, 'months_of_billing', 2);
  INSERT INTO public.deposit_rule_waiver_reach (rule_id, state_code, service_type, waiver_class, trigger_code, effect, defer_days) VALUES
    (v, 'ZZ', 'gas', 'senior', 'nsf', 'defer', 60);
  INSERT INTO public.deposit_rule_instalments (rule_id, instalment_no, fraction, days_after) VALUES
    (v, 1, 0.5, 0), (v, 2, 0.25, 30), (v, 3, 0.25, 60);
  INSERT INTO public.deposit_rule_trigger_thresholds (rule_id, trigger_code, measure, min_count, window_months, min_ratio, payment_due_days) VALUES
    (v, 'nsf', 'event_count', 2, 12, NULL, NULL),
    (v, 'usage_doubled', 'usage_ratio', NULL, NULL, 2.5, 5);
  -- A small business's cap is the GREATER of a fifth of annual billing and
  -- two months' billing (the 16 TAC 25.478 shape).
  INSERT INTO public.deposit_rules (state_code, service_type, customer_class, basis, cap_combinator, cap_scope,
     interest_bearing_instruments, refund_mandatory, refund_excess_over_cap, effective_from, source_note)
  VALUES ('ZZ', 'gas', 'small_business', 'credit_evaluation', 'greater_of', 'per_deposit', '{}', false, false, DATE '2025-01-01', 'ZZ Code 5')
  RETURNING id INTO v;
  INSERT INTO b15 VALUES ('zz_sb_rule', v);
  INSERT INTO public.deposit_rule_cap_parts (rule_id, part_no, cap_kind, cap_divisor, cap_months) VALUES
    (v, 1, 'fraction_of_annual_billing', 5, NULL), (v, 2, 'months_of_billing', NULL, 2);
  -- A rule row for a basis the vocabulary marks not insertable (C7 cites it).
  INSERT INTO public.deposit_rules (state_code, service_type, customer_class, basis, cap_combinator, refund_excess_over_cap,
     interest_bearing_instruments, refund_mandatory, effective_from, source_note)
  VALUES ('ZZ', 'gas', 'large_volume', 'legacy_unknown', 'none', false, '{}', false, DATE '2025-01-01', 'ZZ fixture: legacy');
  EXECUTE 'SET CONSTRAINTS ALL IMMEDIATE';
  RAISE NOTICE 'PASS Z1: a second state is stored as rows, no DDL: other classes; waivers that excuse, halve, or defer for one trigger only; a two-month combined cap and a greater-of cap; interest from day 1 compound and credited annually on two instruments; a 24-month return with one delinquency in 12 months, disqualified by a returned payment, that vests and ignores close, and an excess-over-cap return; an instalment schedule; NSF and usage thresholds; a new return reason';
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
SELECT pg_temp.due('00000000-0000-4000-8000-0000000015da', pg_temp.id('zz_dep'), DATE '2026-04-01');
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
  UPDATE public.deposit_rules SET effective_to = DATE '2026-04-01' WHERE id = pg_temp.id('zz_rule');
  RAISE EXCEPTION 'FAIL Z5: a close on the date a due row cites the rule was accepted';
EXCEPTION WHEN restrict_violation THEN
  RAISE NOTICE 'PASS Z5: a rule row cannot close on or before a date it is cited for (the due row''s 2026-04-01)'; END $$;
DO $$ DECLARE r record; BEGIN
  UPDATE public.deposit_rules SET effective_to = DATE '2026-06-01' WHERE id = pg_temp.id('zz_rule');
  SELECT closed_at, closed_by INTO r FROM public.deposit_rules WHERE id = pg_temp.id('zz_rule');
  IF r.closed_at IS NULL OR r.closed_by IS NULL THEN RAISE EXCEPTION 'FAIL Z6: the close was not stamped'; END IF;
  INSERT INTO public.deposit_rules (state_code, service_type, customer_class, basis, cap_combinator, refund_excess_over_cap, interest_bearing_instruments,
     refund_mandatory, effective_from, source_note)
  VALUES ('ZZ', 'gas', 'household', 'credit_evaluation', 'none', false, '{}', false, DATE '2026-06-01', 'ZZ Code 3 as amended');
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
                               cap_amount, cap_basis_kind, cap_basis_amount, cap_source)
  VALUES ('00000000-0000-4000-8000-0000000015a1', '00000000-0000-4000-8000-0000000015c1', 'tariff', 'cash', 100, DATE '2026-01-01',
          'TX', 'gas', 'residential', pg_temp.r('TX', 'residential', 'tariff'), 'core-test', 150, 'months_of_billing', 75, 'statute');
  RAISE EXCEPTION 'FAIL C5b: a cap of another kind';
EXCEPTION WHEN check_violation THEN NULL; END $$;
DO $$ BEGIN
  INSERT INTO public.deposits (tenant_id, customer_id, basis, instrument, principal, posted_on, state_code, service_type, customer_class, rule_id, decided_by,
                               cap_amount, cap_basis_kind, cap_source)
  VALUES ('00000000-0000-4000-8000-0000000015a1', '00000000-0000-4000-8000-0000000015c1', 'tariff', 'cash', 100, DATE '2026-01-01',
          'TX', 'gas', 'residential', pg_temp.r('TX', 'residential', 'tariff'), 'core-test', 150, 'fraction_of_annual_billing', 'statute');
  RAISE EXCEPTION 'FAIL C5c: a fraction cap with no basis figure';
EXCEPTION WHEN check_violation THEN NULL; END $$;
DO $$ BEGIN
  INSERT INTO public.deposits (tenant_id, customer_id, basis, instrument, principal, posted_on, state_code, service_type, customer_class, rule_id, decided_by,
                               cap_amount, cap_basis_kind, cap_basis_amount, cap_source)
  VALUES ('00000000-0000-4000-8000-0000000015a1', '00000000-0000-4000-8000-0000000015c3', 'tariff', 'cash', 100, DATE '2026-01-01',
          'TX', 'gas', 'non_residential', pg_temp.r('TX', 'non_residential', 'tariff'), 'core-test', 150, 'fraction_of_annual_billing', 900, 'statute');
  RAISE EXCEPTION 'FAIL C5d: a statutory cap under a rule with none';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'PASS C5: a rule with a statutory cap requires a recorded cap; a statutory cap is of the rule''s kind with its basis figure, and none is statutory under a rule without one'; END $$;
DO $$ BEGIN
  -- A utility's tariff caps commercial deposits at two months (Fable F-3):
  -- the TX rule sets none, and the deposit records the tariff's.
  INSERT INTO public.deposits (tenant_id, customer_id, basis, instrument, principal, posted_on, state_code, service_type, customer_class, rule_id, decided_by,
                               cap_amount, cap_basis_kind, cap_basis_amount, cap_binding, cap_source, cap_tariff_reference)
  VALUES ('00000000-0000-4000-8000-0000000015a1', '00000000-0000-4000-8000-0000000015c3', 'tariff', 'cash', 300, DATE '2026-01-01',
          'TX', 'gas', 'non_residential', pg_temp.r('TX', 'non_residential', 'tariff'), 'core-test',
          300, 'months_of_billing', 150, true, 'tariff', 'Gasco Tariff Sheet 12, Rule 4.2');
  -- A tighter residential tariff cap than the statute's 1/6, and it bound.
  INSERT INTO public.deposits (tenant_id, customer_id, basis, instrument, principal, posted_on, state_code, service_type, customer_class, rule_id, decided_by,
                               cap_amount, cap_basis_kind, cap_basis_amount, cap_binding, cap_source, cap_tariff_reference)
  VALUES ('00000000-0000-4000-8000-0000000015a1', '00000000-0000-4000-8000-0000000015c1', 'tariff', 'cash', 100, DATE '2026-01-01',
          'TX', 'gas', 'residential', pg_temp.r('TX', 'residential', 'tariff'), 'core-test',
          100, 'months_of_billing', 100, true, 'tariff', 'Gasco Tariff Sheet 12, Rule 4.1');
  RAISE NOTICE 'PASS C5e: a cap from the utility''s tariff is recorded with its source and provision — where the law sets none, and tighter than the law''s (Ryan, B2)';
END $$;
DO $$ BEGIN
  INSERT INTO public.deposits (tenant_id, customer_id, basis, instrument, principal, posted_on, state_code, service_type, customer_class, rule_id, decided_by,
                               cap_amount, cap_basis_kind, cap_basis_amount, cap_source)
  VALUES ('00000000-0000-4000-8000-0000000015a1', '00000000-0000-4000-8000-0000000015c3', 'tariff', 'cash', 300, DATE '2026-01-01',
          'TX', 'gas', 'non_residential', pg_temp.r('TX', 'non_residential', 'tariff'), 'core-test',
          300, 'months_of_billing', 150, 'tariff');
  RAISE EXCEPTION 'FAIL C5f: a tariff cap without its provision';
EXCEPTION WHEN check_violation THEN NULL; END $$;
DO $$ BEGIN
  INSERT INTO public.deposits (tenant_id, customer_id, basis, instrument, principal, posted_on, state_code, service_type, customer_class, rule_id, decided_by,
                               cap_amount, cap_basis_kind, cap_basis_amount)
  VALUES ('00000000-0000-4000-8000-0000000015a1', '00000000-0000-4000-8000-0000000015c3', 'tariff', 'cash', 300, DATE '2026-01-01',
          'TX', 'gas', 'non_residential', pg_temp.r('TX', 'non_residential', 'tariff'), 'core-test',
          300, 'months_of_billing', 150);
  RAISE EXCEPTION 'FAIL C5g: a cap with no source';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'PASS C5f: a cap names its source, and a tariff cap its provision'; END $$;
DO $$ BEGIN
  INSERT INTO public.deposits (tenant_id, customer_id, basis, instrument, principal, posted_on, state_code, service_type, customer_class, rule_id, decided_by,
                               cap_amount, cap_basis_kind, cap_basis_amount, cap_source)
  VALUES ('00000000-0000-4000-8000-0000000015a1', '00000000-0000-4000-8000-0000000015c1', 'tariff', 'cash', 200, DATE '2026-01-01',
          'TX', 'gas', 'residential', pg_temp.r('TX', 'residential', 'tariff'), 'core-test', 150, 'fraction_of_annual_billing', 900, 'statute');
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
DO $$ BEGIN
  UPDATE public.deposits SET cap_source = 'tariff', cap_tariff_reference = 'x' WHERE id = pg_temp.id('a');
  RAISE EXCEPTION 'FAIL C9e: cap_source changed';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'PASS C9b: the cap''s source is frozen with it'; END $$;
DO $$ DECLARE v uuid; BEGIN
  INSERT INTO public.deposits (tenant_id, customer_id, basis, instrument, principal, posted_on, state_code, service_type, customer_class, rule_id, decided_by, created_at)
  VALUES ('00000000-0000-4000-8000-0000000015a1', '00000000-0000-4000-8000-0000000015c3', 'tariff', 'cash', 10, DATE '2026-01-01',
          'TX', 'gas', 'non_residential', pg_temp.r('TX', 'non_residential', 'tariff'), 'core-test', TIMESTAMPTZ '2001-01-01 00:00+00')
  RETURNING id INTO v;
  IF (SELECT created_at FROM public.deposits WHERE id = v) <> now() THEN RAISE EXCEPTION 'FAIL C10: created_at not stamped'; END IF;
  RAISE NOTICE 'PASS C10: a deposit''s created_at is the database''s, not the caller''s';
END $$;
DO $$ BEGIN
  INSERT INTO public.deposits (tenant_id, customer_id, basis, instrument, principal, posted_on, state_code, service_type, customer_class, rule_id, decided_by, legacy_interest_earned)
  VALUES ('00000000-0000-4000-8000-0000000015a1', '00000000-0000-4000-8000-0000000015c3', 'tariff', 'cash', 10, DATE '2026-01-01',
          'TX', 'gas', 'non_residential', pg_temp.r('TX', 'non_residential', 'tariff'), 'core-test', 1.00);
  RAISE EXCEPTION 'FAIL C11: legacy interest on a new deposit';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'PASS C11: legacy interest is carried history, never on a new deposit (no basis named)'; END $$;
RESET ROLE;
-- Owner: a new basis that requires a trigger (Opus F4 / Codex R-1).
INSERT INTO public.deposit_bases (basis_code, is_federal, insertable, requires_trigger, description)
VALUES ('reestablishment', false, true, true, 'ZZ fixture: security on re-establishing service after default.');
INSERT INTO public.deposit_rules (state_code, service_type, customer_class, basis, cap_combinator, refund_excess_over_cap, interest_bearing_instruments, refund_mandatory, effective_from, source_note)
VALUES ('ZZ', 'gas', 'small_business', 'reestablishment', 'none', false, '{}', false, DATE '2025-01-01', 'ZZ fixture: re-establishment');
SET LOCAL app.user_id = '00000000-0000-4000-8000-0000000015b1';
SET ROLE tally_app;
DO $$ BEGIN
  INSERT INTO public.deposits (tenant_id, customer_id, basis, trigger_basis, instrument, principal, posted_on, state_code, service_type, customer_class, rule_id, decided_by)
  VALUES ('00000000-0000-4000-8000-0000000015a1', '00000000-0000-4000-8000-0000000015c3', 'reestablishment', 'nsf', 'cash', 50, DATE '2026-01-01',
          'ZZ', 'gas', 'small_business', pg_temp.r('ZZ', 'small_business', 'reestablishment'), 'core-test');
  BEGIN
    INSERT INTO public.deposits (tenant_id, customer_id, basis, instrument, principal, posted_on, state_code, service_type, customer_class, rule_id, decided_by)
    VALUES ('00000000-0000-4000-8000-0000000015a1', '00000000-0000-4000-8000-0000000015c3', 'reestablishment', 'cash', 50, DATE '2026-01-01',
            'ZZ', 'gas', 'small_business', pg_temp.r('ZZ', 'small_business', 'reestablishment'), 'core-test');
    RAISE EXCEPTION 'FAIL C12: a triggered basis without its trigger';
  EXCEPTION WHEN check_violation THEN NULL; END;
  BEGIN
    INSERT INTO public.deposits (tenant_id, customer_id, basis, trigger_basis, instrument, principal, posted_on, state_code, service_type, customer_class, rule_id, decided_by)
    VALUES ('00000000-0000-4000-8000-0000000015a1', '00000000-0000-4000-8000-0000000015c3', 'tariff', 'nsf', 'cash', 50, DATE '2026-01-01',
            'TX', 'gas', 'non_residential', pg_temp.r('TX', 'non_residential', 'tariff'), 'core-test');
    RAISE EXCEPTION 'FAIL C12: a trigger on a basis without one';
  EXCEPTION WHEN check_violation THEN NULL; END;
  RAISE NOTICE 'PASS C12: a new basis that requires a trigger is rows only; a trigger is named exactly when the basis requires one (no basis-name CHECK)';
END $$;
-- ZZ's additional-deposit cap is two months of billing on the COMBINED total
-- (Opus F8): monthly billing 150 (a broken-DPA deposit: ZZ sets no threshold for it), so a cap of 300, and 200 already held.
DO $$ BEGIN
  INSERT INTO public.deposits (tenant_id, customer_id, basis, trigger_basis, instrument, principal, posted_on, state_code, service_type, customer_class,
                               rule_id, decided_by, cap_amount, cap_basis_kind, cap_basis_amount, cap_source)
  VALUES ('00000000-0000-4000-8000-0000000015a1', '00000000-0000-4000-8000-0000000015c2', 'additional_trigger', 'broken_dpa', 'cash', 100, DATE '2026-01-01',
          'ZZ', 'gas', 'household', pg_temp.id('zz_add_rule'), 'core-test', 300, 'months_of_billing', 150, 'statute');
  RAISE EXCEPTION 'FAIL C5h: a combined statutory cap without what else was held';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'PASS C5h: a statutory cap under combined scope records what else was held'; END $$;
DO $$ BEGIN
  INSERT INTO public.deposits (tenant_id, customer_id, basis, trigger_basis, instrument, principal, posted_on, state_code, service_type, customer_class,
                               rule_id, decided_by, cap_amount, cap_basis_kind, cap_basis_amount, cap_source, cap_other_held, cap_binding)
  VALUES ('00000000-0000-4000-8000-0000000015a1', '00000000-0000-4000-8000-0000000015c2', 'additional_trigger', 'broken_dpa', 'cash', 100, DATE '2026-01-01',
          'ZZ', 'gas', 'household', pg_temp.id('zz_add_rule'), 'core-test', 300, 'months_of_billing', 150, 'statute', 200, true);
  BEGIN
    INSERT INTO public.deposits (tenant_id, customer_id, basis, trigger_basis, instrument, principal, posted_on, state_code, service_type, customer_class,
                                 rule_id, decided_by, cap_amount, cap_basis_kind, cap_basis_amount, cap_source, cap_other_held)
    VALUES ('00000000-0000-4000-8000-0000000015a1', '00000000-0000-4000-8000-0000000015c2', 'additional_trigger', 'broken_dpa', 'cash', 150, DATE '2026-01-01',
            'ZZ', 'gas', 'household', pg_temp.id('zz_add_rule'), 'core-test', 300, 'months_of_billing', 150, 'statute', 200);
    RAISE EXCEPTION 'FAIL C13: above the room left under a combined cap';
  EXCEPTION WHEN check_violation THEN NULL; END;
  RAISE NOTICE 'PASS C13: a combined cap binds at the room left (100 of 300 with 200 held, cap_binding true) and nothing goes above it';
END $$;


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
  RAISE NOTICE 'PASS L1: a waiver in force no longer refuses a deposit in the database (the core decides, from deposit_rule_waiver_reach)';
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
DO $$ DECLARE v text; BEGIN
  -- Every deposit function body and every CHECK on a deposit table: no state,
  -- no basis or waiver-class code, no day count (review r1 A3: L5 had read
  -- two functions only and missed -06's CHECKs and post_deposit_event).
  -- ('tariff' is left out: it is also a cap_source value.)
  SELECT string_agg(x.what, ', ') INTO v FROM (
    SELECT 'function ' || p.proname AS what, p.prosrc AS body
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.proname ~ 'deposit'
    UNION ALL
    SELECT 'constraint ' || c.conname, pg_get_constraintdef(c.oid)
      FROM pg_constraint c JOIN pg_class t ON t.oid = c.conrelid JOIN pg_namespace n ON n.oid = t.relnamespace
     WHERE n.nspname = 'public' AND t.relname ~ '^deposit' AND c.contype = 'c'
  ) x
  WHERE x.body ~ '''(TX|credit_evaluation|additional_trigger|adequate_assurance_366|legacy_unknown|family_violence_certified|age_65_no_balance|good_payment_history)'''
     OR (x.what LIKE 'function enforce_deposit%' AND x.body ~ '\m(30|31|365)\M');
  IF v IS NOT NULL THEN RAISE EXCEPTION 'FAIL L5: names a state, basis or waiver class, or a day count: %', v; END IF;
  RAISE NOTICE 'PASS L5: no deposit function or CHECK names a state, a basis or a waiver class, and no guard a day count';
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
-- Chronology and partial returns on deposit H (non-residential, 200, Jan 1).
DO $$ BEGIN
  PERFORM pg_temp.dep('h', '00000000-0000-4000-8000-0000000015c3', 'tariff', 'non_residential', 'cash', 200, DATE '2026-01-01');
  PERFORM pg_temp.acc(pg_temp.id('h'), pg_temp.id('rate_jan'), DATE '2026-01-01', DATE '2026-01-31', 0.51, DATE '2026-02-01');
END $$;
DO $$ BEGIN
  PERFORM pg_temp.ev(pg_temp.id('h'), 'principal_returned', 50, DATE '2026-01-15');
  RAISE EXCEPTION 'FAIL E19a: a return dated inside an accrued period';
EXCEPTION WHEN check_violation THEN NULL; END $$;
DO $$ BEGIN
  PERFORM pg_temp.ev(pg_temp.id('h'), 'refund_initiated', 200, DATE '2026-01-20');
  RAISE EXCEPTION 'FAIL E19b: a refund dated inside an accrued period';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'PASS E19: money handed back on a day cannot have earned interest after it (returns dated inside an accrued period refused)'; END $$;
DO $$ BEGIN
  PERFORM pg_temp.ev(pg_temp.id('h'), 'principal_returned', 50, DATE '2026-02-10');
  IF (SELECT remainder FROM public.deposit_balance(pg_temp.id('h'))) <> 150
     OR (SELECT status FROM public.deposits WHERE id = pg_temp.id('h')) <> 'held' THEN
    RAISE EXCEPTION 'FAIL E20: the partial return did not leave 150 held';
  END IF;
  BEGIN
    PERFORM pg_temp.ev(pg_temp.id('h'), 'principal_returned', 150, DATE '2026-02-11');
    RAISE EXCEPTION 'FAIL E20: a partial return of the whole remainder';
  EXCEPTION WHEN check_violation THEN NULL; END;
  RAISE NOTICE 'PASS E20: part of a deposit goes back (50 of 200, the rest held); returning all of it is a refund, not a partial return';
END $$;
DO $$ BEGIN
  INSERT INTO public.deposit_events (tenant_id, deposit_id, event_type, amount, effective_on, period_start, period_end,
                                     rate_applied, principal_basis, rate_id, rule_id, calculated_by)
  SELECT d.tenant_id, d.id, 'interest_accrued', 1, DATE '2026-03-01', DATE '2026-02-01', DATE '2026-02-09',
         0.03, 500, pg_temp.id('rate_jan'), d.rule_id, 'core-test' FROM public.deposits d WHERE d.id = pg_temp.id('h');
  RAISE EXCEPTION 'FAIL E21a: interest on more than the principal';
EXCEPTION WHEN check_violation THEN NULL; END $$;
DO $$ BEGIN
  PERFORM pg_temp.ev(pg_temp.id('h'), 'applied_to_balance', 150, DATE '2026-02-15');
  PERFORM pg_temp.acc(pg_temp.id('h'), pg_temp.id('rate_jan'), DATE '2026-02-15', DATE '2026-02-28', 0.10, DATE '2026-03-01');
  RAISE EXCEPTION 'FAIL E21b: an accrual after the principal was used up';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'PASS E21: no interest on more than the principal, nor after it was used up'; END $$;
DO $$ BEGIN
  PERFORM pg_temp.ev(pg_temp.id('h'), 'applied_to_balance', 150, DATE '2026-02-15');
  PERFORM pg_temp.ev(pg_temp.id('h'), 'interest_credited', 0.51, DATE '2026-02-16');
  INSERT INTO public.deposit_events (tenant_id, deposit_id, event_type, amount, effective_on, rule_id, calculated_by, reason)
  SELECT d.tenant_id, d.id, 'refunded', 0, DATE '2026-02-16', d.rule_id, 'core-test', 'interest through Jan 31 only: held 31 days'
    FROM public.deposits d WHERE d.id = pg_temp.id('h');
  BEGIN
    INSERT INTO public.deposit_events (tenant_id, deposit_id, event_type, amount, effective_on, calculated_by)
    SELECT d.tenant_id, d.id, 'interest_credited', 0.01, DATE '2026-02-16', 'core-test' FROM public.deposits d WHERE d.id = pg_temp.id('zz_dep');
    RAISE EXCEPTION 'FAIL E22: a core version on an event that decides nothing';
  EXCEPTION WHEN check_violation THEN NULL; END;
  RAISE NOTICE 'PASS E22: a return may name the rule and core version that decided it; other events may not';
END $$;
-- Which rule a later record cites (B1, Ryan 2026-10-02): ZZ's rule closed on
-- 2026-06-01 and a successor began (Z6); zz_dep was decided under the old one.
DO $$ DECLARE v_rate uuid; v_succ uuid; BEGIN
  SELECT id INTO v_rate FROM public.deposit_interest_rates WHERE state_code = 'ZZ';
  SELECT id INTO v_succ FROM public.deposit_rules WHERE state_code = 'ZZ' AND customer_class = 'household'
     AND basis = 'credit_evaluation' AND effective_from = DATE '2026-06-01';
  -- the new law, reaching a deposit already held
  INSERT INTO public.deposit_events (tenant_id, deposit_id, event_type, amount, effective_on, period_start, period_end,
                                     rate_applied, principal_basis, rate_id, rule_id, calculated_by)
  VALUES ('00000000-0000-4000-8000-0000000015a1', pg_temp.id('zz_dep'), 'interest_accrued', 1, DATE '2026-08-01',
          DATE '2026-07-01', DATE '2026-07-31', 0.04, 400, v_rate, v_succ, 'core-test');
  -- the old law, governing it after its close (grandfathered)
  INSERT INTO public.deposit_events (tenant_id, deposit_id, event_type, amount, effective_on, period_start, period_end,
                                     rate_applied, principal_basis, rate_id, rule_id, calculated_by)
  VALUES ('00000000-0000-4000-8000-0000000015a1', pg_temp.id('zz_dep'), 'interest_accrued', 1, DATE '2026-09-01',
          DATE '2026-08-01', DATE '2026-08-31', 0.04, 400, v_rate, pg_temp.id('zz_rule'), 'core-test');
  BEGIN
    INSERT INTO public.deposit_events (tenant_id, deposit_id, event_type, amount, effective_on, period_start, period_end,
                                       rate_applied, principal_basis, rate_id, rule_id, calculated_by)
    VALUES ('00000000-0000-4000-8000-0000000015a1', pg_temp.id('zz_dep'), 'interest_accrued', 1, DATE '2026-07-01',
            DATE '2026-05-01', DATE '2026-05-31', 0.04, 400, v_rate, v_succ, 'core-test');
    RAISE EXCEPTION 'FAIL E23: the successor cited for a period before it began';
  EXCEPTION WHEN check_violation THEN NULL; END;
  RAISE NOTICE 'PASS E23: a later accrual cites the rule the deposit was decided under, or a rule of its key in force over the period — never one not yet in force (B1)';
END $$;
DO $$ BEGIN
  INSERT INTO public.deposit_interest_rates (tenant_id, state_code, service_type, customer_class, effective_date, annual_rate)
  VALUES ('00000000-0000-4000-8000-0000000015a1', 'TX', 'gas', 'residential', DATE '2026-06-01', 0.035);
  BEGIN
    INSERT INTO public.deposit_interest_rates (tenant_id, state_code, service_type, customer_class, effective_date, annual_rate)
    VALUES ('00000000-0000-4000-8000-0000000015a1', 'TX', 'gas', 'residential', DATE '2026-06-01', 0.04);
    RAISE EXCEPTION 'FAIL E24: two residential rates on one day';
  EXCEPTION WHEN unique_violation THEN NULL; END;
  PERFORM pg_temp.dep('h2', '00000000-0000-4000-8000-0000000015c3', 'tariff', 'non_residential', 'cash', 100, DATE '2026-06-01');
  BEGIN
    PERFORM pg_temp.acc(pg_temp.id('h2'), (SELECT id FROM public.deposit_interest_rates WHERE customer_class = 'residential'),
                        DATE '2026-06-01', DATE '2026-06-30', 0.29, DATE '2026-07-01');
    RAISE EXCEPTION 'FAIL E24: a residential rate on a non-residential deposit';
  EXCEPTION WHEN check_violation THEN NULL; END;
  RAISE NOTICE 'PASS E24: a utility rate may be for one customer class; an accrual cites one for its class or for every class';
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
-- C1 final-bills (the database stamps the change now, 2026-10 as this is
-- written, so a due row resting on it falls due on or after it — review r2
-- I4); R-full is applied in full and due on two reasons at once.
UPDATE public.customers SET status = 'final_billed', status_reason = 'moved out'
 WHERE id = '00000000-0000-4000-8000-0000000015c1';
SELECT pg_temp.ev(pg_temp.id('rfull'), 'applied_to_balance', 60, DATE '2026-04-01');
SET CONSTRAINTS ALL DEFERRED;
SELECT pg_temp.due('00000000-0000-4000-8000-0000000015d4', pg_temp.id('rfull'), DATE '2026-11-01');
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
  PERFORM pg_temp.ev(pg_temp.id('rfull'), 'refunded', 0, DATE '2026-11-02', '00000000-0000-4000-8000-0000000015d1');
  RAISE EXCEPTION 'FAIL F11: a refund citing another deposit''s due row';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'PASS F11: a return cites only its own deposit''s due row'; END $$;
DO $$ BEGIN
  PERFORM pg_temp.ev(pg_temp.id('rfull'), 'refunded', 0, DATE '2026-11-02', '00000000-0000-4000-8000-0000000015d4');
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
SELECT pg_temp.due('00000000-0000-4000-8000-0000000015d7', pg_temp.id('r'), DATE '2026-11-01', '00000000-0000-4000-8000-0000000015d1');
SELECT pg_temp.evid('00000000-0000-4000-8000-0000000015d7', 'account_closed', NULL, NULL,
                    (SELECT id FROM public.customer_state_events WHERE customer_id = '00000000-0000-4000-8000-0000000015c1' AND to_status = 'final_billed'));
SET CONSTRAINTS ALL IMMEDIATE;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.deposits_return_owed WHERE due_id = '00000000-0000-4000-8000-0000000015d7') THEN
    RAISE EXCEPTION 'FAIL F15: the corrected answer is not owed';
  END IF;
  PERFORM pg_temp.ev(pg_temp.id('r'), 'refund_initiated', 300, DATE '2026-11-03', '00000000-0000-4000-8000-0000000015d7');
  IF EXISTS (SELECT 1 FROM public.deposits_return_owed WHERE deposit_id = pg_temp.id('r')) THEN
    RAISE EXCEPTION 'FAIL F15: still owed once the refund started';
  END IF;
  RAISE NOTICE 'PASS F15: a corrected answer names the row it supersedes (once); the list drops it when the refund starts';
END $$;
-- On R2 (no refund started): X live, withdrawn; Y supersedes X, withdrawn; a
-- third row superseding X again can be refused only by the UNIQUE.
SET CONSTRAINTS ALL DEFERRED;
SELECT pg_temp.due('00000000-0000-4000-8000-0000000015e3', pg_temp.id('r2'), DATE '2026-04-01');
SELECT pg_temp.evid('00000000-0000-4000-8000-0000000015e3', 'clean_bill_history', '00000000-0000-4000-8000-0000000015e8', 'clean', NULL);
SET CONSTRAINTS ALL IMMEDIATE;
INSERT INTO public.deposit_return_due_withdrawals (tenant_id, due_id, reason)
VALUES ('00000000-0000-4000-8000-0000000015a1', '00000000-0000-4000-8000-0000000015e3', 'battery: X wrong');
SET CONSTRAINTS ALL DEFERRED;
SELECT pg_temp.due('00000000-0000-4000-8000-0000000015e4', pg_temp.id('r2'), DATE '2026-04-02', '00000000-0000-4000-8000-0000000015e3');
SELECT pg_temp.evid('00000000-0000-4000-8000-0000000015e4', 'clean_bill_history', '00000000-0000-4000-8000-0000000015e8', 'clean', NULL);
SET CONSTRAINTS ALL IMMEDIATE;
INSERT INTO public.deposit_return_due_withdrawals (tenant_id, due_id, reason)
VALUES ('00000000-0000-4000-8000-0000000015a1', '00000000-0000-4000-8000-0000000015e4', 'battery: Y wrong too');
DO $$ BEGIN
  EXECUTE 'SET CONSTRAINTS ALL DEFERRED';
  PERFORM pg_temp.due('00000000-0000-4000-8000-0000000015e5', pg_temp.id('r2'), DATE '2026-04-03', '00000000-0000-4000-8000-0000000015e3');
  RAISE EXCEPTION 'FAIL F15b: a withdrawn row superseded twice';
EXCEPTION WHEN unique_violation THEN
  RAISE NOTICE 'PASS F15b: a withdrawn row is superseded once'; END $$;
DO $$ BEGIN
  PERFORM pg_temp.ev(pg_temp.id('r2'), 'refund_initiated', 120, DATE '2026-04-05');
  EXECUTE 'SET CONSTRAINTS ALL DEFERRED';
  PERFORM pg_temp.due('00000000-0000-4000-8000-0000000015d9', pg_temp.id('r2'), DATE '2026-04-02');
  RAISE EXCEPTION 'FAIL F17: a due row once the refund started';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'PASS F17: no due row once a return has started (refund_pending)'; END $$;
DO $$ BEGIN
  PERFORM pg_temp.dep('rlate', '00000000-0000-4000-8000-0000000015c1', 'tariff', 'residential', 'cash', 40, DATE '2026-12-01');
END $$;
DO $$ BEGIN
  EXECUTE 'SET CONSTRAINTS ALL DEFERRED';
  PERFORM pg_temp.due('00000000-0000-4000-8000-0000000015db', pg_temp.id('rlate'), DATE '2026-12-02');
  PERFORM pg_temp.evid('00000000-0000-4000-8000-0000000015db', 'account_closed', NULL, NULL,
                       (SELECT id FROM public.customer_state_events WHERE customer_id = '00000000-0000-4000-8000-0000000015c1' AND to_status = 'active' LIMIT 1));
  RAISE EXCEPTION 'FAIL F18a: an active event as closure evidence';
EXCEPTION WHEN check_violation THEN NULL; END $$;
DO $$ BEGIN
  EXECUTE 'SET CONSTRAINTS ALL DEFERRED';
  PERFORM pg_temp.due('00000000-0000-4000-8000-0000000015db', pg_temp.id('rlate'), DATE '2026-12-02');
  PERFORM pg_temp.evid('00000000-0000-4000-8000-0000000015db', 'account_closed', NULL, NULL,
                       (SELECT id FROM public.customer_state_events WHERE customer_id = '00000000-0000-4000-8000-0000000015c1' AND to_status = 'final_billed'));
  RAISE EXCEPTION 'FAIL F18b: a closure from before the deposit was posted';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'PASS F18: closure evidence is a change to a qualifying status (from the reason row), on or after posting'; END $$;
DO $$ BEGIN
  -- C3 moves to collections after H2 was posted: dated right, wrong status.
  UPDATE public.customers SET status = 'collections', status_reason = 'arrears' WHERE id = '00000000-0000-4000-8000-0000000015c3';
  EXECUTE 'SET CONSTRAINTS ALL DEFERRED';
  PERFORM pg_temp.due('00000000-0000-4000-8000-0000000015dd', pg_temp.id('h2'), DATE '2026-11-01');
  PERFORM pg_temp.evid('00000000-0000-4000-8000-0000000015dd', 'account_closed', NULL, NULL,
                       (SELECT id FROM public.customer_state_events WHERE customer_id = '00000000-0000-4000-8000-0000000015c3' AND to_status = 'collections'));
  RAISE EXCEPTION 'FAIL F18c: a move to collections as closure evidence';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'PASS F18c: a state change after posting to a status the reason does not name is no closure'; END $$;
DO $$ BEGIN
  -- R2 (C2's deposit, posted Jan 15) cites C1's final-billing: dated right,
  -- qualifying status, wrong customer.
  EXECUTE 'SET CONSTRAINTS ALL DEFERRED';
  PERFORM pg_temp.due('00000000-0000-4000-8000-0000000015de', pg_temp.id('r2'), DATE '2026-11-01');
  PERFORM pg_temp.evid('00000000-0000-4000-8000-0000000015de', 'account_closed', NULL, NULL,
                       (SELECT id FROM public.customer_state_events WHERE customer_id = '00000000-0000-4000-8000-0000000015c1' AND to_status = 'final_billed'));
  RAISE EXCEPTION 'FAIL F21: another customer''s closure';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'PASS F21: closure evidence is the deposit''s own customer''s'; END $$;
DO $$ BEGIN
  PERFORM pg_temp.dep('zz2', '00000000-0000-4000-8000-0000000015c2', 'credit_evaluation', 'household', 'cash', 100, DATE '2025-03-01', 'ZZ');
  UPDATE public.customers SET status = 'final_billed', status_reason = 'moved out' WHERE id = '00000000-0000-4000-8000-0000000015c2';
END $$;
DO $$ BEGIN
  EXECUTE 'SET CONSTRAINTS ALL DEFERRED';
  PERFORM pg_temp.due('00000000-0000-4000-8000-0000000015dc', pg_temp.id('zz2'), DATE '2026-11-01');
  PERFORM pg_temp.evid('00000000-0000-4000-8000-0000000015dc', 'account_closed', NULL, NULL,
                       (SELECT id FROM public.customer_state_events WHERE customer_id = '00000000-0000-4000-8000-0000000015c2' AND to_status = 'final_billed'));
  RAISE EXCEPTION 'FAIL F19: account_closed under a rule where closing is no trigger';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'PASS F19: a reason the rule does not enable is refused (ZZ returns ignore account close)'; END $$;
SET CONSTRAINTS ALL DEFERRED;
SELECT pg_temp.due('00000000-0000-4000-8000-0000000015dc', pg_temp.id('zz2'), DATE '2027-03-01');
INSERT INTO public.deposit_return_due_evidence (tenant_id, due_id, reason_code, rests_on_deposit)
VALUES ('00000000-0000-4000-8000-0000000015a1', '00000000-0000-4000-8000-0000000015dc', 'hold_term_elapsed', true);
SET CONSTRAINTS ALL IMMEDIATE;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.deposits_return_owed WHERE due_id = '00000000-0000-4000-8000-0000000015dc' AND reasons = ARRAY['hold_term_elapsed']) THEN
    RAISE EXCEPTION 'FAIL F20: a return due on time held is not listed';
  END IF;
  BEGIN
    INSERT INTO public.deposit_return_due_evidence (tenant_id, due_id, reason_code, invoice_id, classification, rests_on_deposit)
    -- a reason resting on bills with no measure of its own, so only the
    -- subject CHECK can refuse (clean_bill_history would fail I2 first)
    VALUES ('00000000-0000-4000-8000-0000000015a1', '00000000-0000-4000-8000-0000000015dc', 'service_term_complete', '00000000-0000-4000-8000-0000000015e8', 'clean', true);
    RAISE EXCEPTION 'FAIL F20: two subjects on one evidence row';
  EXCEPTION WHEN check_violation THEN NULL; END;
  RAISE NOTICE 'PASS F20: a return due on time held rests on the deposit itself — a third evidence kind, as a row';
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


-- ============================================================ W. waivers: reach and tariff grounds
SET LOCAL app.user_id = '00000000-0000-4000-8000-0000000015b1';
SET ROLE tally_app;
DO $$ DECLARE v uuid; BEGIN
  INSERT INTO public.deposit_tariff_waiver_grounds (tenant_id, state_code, service_type, ground_code, description, tariff_reference,
         reaches_customer_classes, effect, effective_from)
  VALUES ('00000000-0000-4000-8000-0000000015a1', 'TX', 'gas', 'active_military', 'Active-duty military households.', 'Gasco Tariff Sheet 12, Rule 5',
          ARRAY['residential'], 'excuse', DATE '2026-01-01') RETURNING id INTO v;
  INSERT INTO b15 VALUES ('ground', v);
  RAISE NOTICE 'PASS W1: the utility records its own tariff waiver — its provision, scope (residential only) and effect';
END $$;
DO $$ BEGIN
  INSERT INTO public.deposit_tariff_waiver_grounds (tenant_id, state_code, service_type, ground_code, description, tariff_reference, effect, effective_from)
  VALUES ('00000000-0000-4000-8000-0000000015a1', 'ZZ', 'gas', 'x', 'x', 'x', 'excuse', DATE '2026-01-01');
  RAISE EXCEPTION 'FAIL W2a: a tariff waiver where the law permits none';
EXCEPTION WHEN check_violation THEN NULL; END $$;
DO $$ BEGIN
  INSERT INTO public.deposit_tariff_waiver_grounds (tenant_id, state_code, service_type, ground_code, description, tariff_reference,
         reaches_bases, effect, effective_from)
  VALUES ('00000000-0000-4000-8000-0000000015a1', 'TX', 'gas', 'y', 'y', 'y', ARRAY['no_such_basis'], 'excuse', DATE '2026-01-01');
  RAISE EXCEPTION 'FAIL W2b: a scope naming no basis';
EXCEPTION WHEN foreign_key_violation THEN NULL; END $$;
DO $$ BEGIN
  INSERT INTO public.deposit_tariff_waiver_grounds (tenant_id, state_code, service_type, ground_code, description, tariff_reference, effect, effective_from)
  VALUES ('00000000-0000-4000-8000-0000000015a1', 'TX', 'gas', 'z', 'z', 'z', 'reduce', DATE '2026-01-01');
  RAISE EXCEPTION 'FAIL W2c: a reduction without its fraction';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'PASS W2: a tariff ground needs the law''s permission, a scope of real values, and an effect with its figure'; END $$;
DO $$ BEGIN
  INSERT INTO public.deposit_waiver_determinations (tenant_id, customer_id, state_code, service_type, waiver_class, determined_on)
  VALUES ('00000000-0000-4000-8000-0000000015a1', '00000000-0000-4000-8000-0000000015c1', 'TX', 'gas', 'tariff', DATE '2026-03-01');
  RAISE EXCEPTION 'FAIL W3a: a tariff determination without its ground';
EXCEPTION WHEN check_violation THEN NULL; END $$;
DO $$ BEGIN
  INSERT INTO public.deposit_waiver_determinations (tenant_id, customer_id, state_code, service_type, waiver_class, determined_on, tariff_ground_id)
  VALUES ('00000000-0000-4000-8000-0000000015a1', '00000000-0000-4000-8000-0000000015c1', 'TX', 'gas', 'tariff', DATE '2025-12-01', pg_temp.id('ground'));
  RAISE EXCEPTION 'FAIL W3b: a ground not yet in force';
EXCEPTION WHEN check_violation THEN NULL; END $$;
DO $$ BEGIN
  INSERT INTO public.deposit_waiver_determinations (tenant_id, customer_id, state_code, service_type, waiver_class, determined_on, tariff_ground_id)
  VALUES ('00000000-0000-4000-8000-0000000015a1', '00000000-0000-4000-8000-0000000015c1', 'TX', 'gas', 'good_payment_history', DATE '2026-03-01', pg_temp.id('ground'));
  RAISE EXCEPTION 'FAIL W3c: a statutory class naming a tariff ground';
EXCEPTION WHEN check_violation THEN NULL; END $$;
DO $$ BEGIN
  INSERT INTO public.deposit_waiver_determinations (tenant_id, customer_id, state_code, service_type, waiver_class, determined_on, tariff_ground_id)
  VALUES ('00000000-0000-4000-8000-0000000015a1', '00000000-0000-4000-8000-0000000015c1', 'TX', 'gas', 'tariff', DATE '2026-03-01', pg_temp.id('ground'));
  RAISE NOTICE 'PASS W3: a tariff determination names the utility''s ground in force on its date; a statutory one names none';
END $$;
DO $$ BEGIN
  -- An edit carried on a close (a bare edit is refused as "not a close" too).
  UPDATE public.deposit_tariff_waiver_grounds SET effective_to = DATE '2026-09-01', description = 'edited' WHERE id = pg_temp.id('ground');
  RAISE EXCEPTION 'FAIL W4a: a ground edited';
EXCEPTION WHEN restrict_violation THEN NULL; END $$;
DO $$ BEGIN
  UPDATE public.deposit_tariff_waiver_grounds SET effective_to = DATE '2026-03-01' WHERE id = pg_temp.id('ground');
  RAISE EXCEPTION 'FAIL W4b: a ground closed under a determination citing it';
EXCEPTION WHEN restrict_violation THEN NULL; END $$;
DO $$ BEGIN
  UPDATE public.deposit_tariff_waiver_grounds SET effective_to = DATE '2026-09-01' WHERE id = pg_temp.id('ground');
  IF (SELECT closed_by FROM public.deposit_tariff_waiver_grounds WHERE id = pg_temp.id('ground')) IS DISTINCT FROM '00000000-0000-4000-8000-0000000015b1'::uuid THEN
    RAISE EXCEPTION 'FAIL W4c: the close was not stamped with the user';
  END IF;
  RAISE NOTICE 'PASS W4: a ground is never edited; it is closed once, stamped, and not before a date a determination cites it for';
END $$;
DO $$ BEGIN
  INSERT INTO public.deposit_rule_waiver_reach (rule_id, state_code, service_type, waiver_class, effect)
  VALUES (pg_temp.id('zz_add_rule'), 'ZZ', 'gas', 'veteran', 'excuse');
  RAISE EXCEPTION 'FAIL W5a: the application wrote a reach row';
EXCEPTION WHEN insufficient_privilege THEN NULL; END $$;
RESET ROLE;
DO $$ DECLARE v uuid; BEGIN
  INSERT INTO public.deposit_rules (state_code, service_type, customer_class, basis, cap_combinator, refund_excess_over_cap, interest_bearing_instruments, refund_mandatory, effective_from, source_note)
  VALUES ('ZZ', 'gas', 'large_volume', 'tariff', 'none', false, '{}', false, DATE '2025-01-01', 'ZZ fixture: reach probes') RETURNING id INTO v;
  BEGIN
    INSERT INTO public.deposit_rule_waiver_reach (rule_id, state_code, service_type, waiver_class, effect)
    VALUES (v, 'TX', 'gas', 'family_violence_certified', 'excuse');
    RAISE EXCEPTION 'FAIL W5b: a reach row of another state than its rule';
  EXCEPTION WHEN foreign_key_violation THEN NULL; END;
  BEGIN
    INSERT INTO public.deposit_rule_waiver_reach (rule_id, state_code, service_type, waiver_class, trigger_code, effect)
    VALUES (v, 'ZZ', 'gas', 'veteran', 'nsf', 'excuse');
    RAISE EXCEPTION 'FAIL W5c: a trigger on a rule whose basis has none';
  EXCEPTION WHEN check_violation THEN NULL; END;
  BEGIN
    INSERT INTO public.deposit_rule_refund_disqualifiers (rule_id, disqualifier_code) VALUES (v, 'returned_payment');
    RAISE EXCEPTION 'FAIL W5d: a disqualifier on a rule with no count-based trigger';
  EXCEPTION WHEN check_violation THEN NULL; END;
  BEGIN
    INSERT INTO public.deposit_rule_waiver_reach (rule_id, state_code, service_type, waiver_class, effect, defer_days, reduce_fraction)
    VALUES (v, 'ZZ', 'gas', 'senior', 'defer', 30, 0.5);
    RAISE EXCEPTION 'FAIL W5e: a deferral carrying a fraction';
  EXCEPTION WHEN check_violation THEN NULL; END;
  RAISE NOTICE 'PASS W5: reach rows are the platform''s: of their rule''s state (by composite key), a trigger only for a triggered basis, an effect with exactly its figure; a disqualifier only on a count-based trigger';
END $$;

-- ============================================================ N. review round 2
-- Each case is built so that only the guard it names can refuse it.
SET LOCAL app.user_id = '00000000-0000-4000-8000-0000000015b1';
SET ROLE tally_app;
-- N1 (D2): a greater-of cap names the part that governed it.
DO $$ BEGIN
  INSERT INTO public.deposits (tenant_id, customer_id, basis, instrument, principal, posted_on, state_code, service_type, customer_class,
                               rule_id, decided_by, cap_amount, cap_basis_kind, cap_basis_amount, cap_source)
  VALUES ('00000000-0000-4000-8000-0000000015a1', '00000000-0000-4000-8000-0000000015c3', 'credit_evaluation', 'cash', 300, DATE '2025-06-01',
          'ZZ', 'gas', 'small_business', pg_temp.id('zz_sb_rule'), 'core-test', 300, 'months_of_billing', 150, 'statute');
  BEGIN
    INSERT INTO public.deposits (tenant_id, customer_id, basis, instrument, principal, posted_on, state_code, service_type, customer_class,
                                 rule_id, decided_by, cap_amount, cap_basis_kind, cap_source)
    VALUES ('00000000-0000-4000-8000-0000000015a1', '00000000-0000-4000-8000-0000000015c3', 'credit_evaluation', 'cash', 300, DATE '2025-06-01',
            'ZZ', 'gas', 'small_business', pg_temp.id('zz_sb_rule'), 'core-test', 300, 'fixed_amount', 'statute');
    RAISE EXCEPTION 'FAIL N1: a statutory cap of a kind the rule has no part of';
  EXCEPTION WHEN check_violation THEN NULL; END;
  RAISE NOTICE 'PASS N1: under a greater-of cap the deposit names the part that governed (two months of billing); a kind the rule lacks is refused (review r2 D2)';
END $$;
-- N2 (D1): the threshold an additional deposit was judged against.
DO $$ DECLARE v_nsf uuid; v_use uuid; BEGIN
  SELECT id INTO v_nsf FROM public.deposit_rule_trigger_thresholds WHERE rule_id = pg_temp.id('zz_add_rule') AND trigger_code = 'nsf';
  SELECT id INTO v_use FROM public.deposit_rule_trigger_thresholds WHERE rule_id = pg_temp.id('zz_add_rule') AND trigger_code = 'usage_doubled';
  BEGIN
    INSERT INTO public.deposits (tenant_id, customer_id, basis, trigger_basis, instrument, principal, posted_on, state_code, service_type, customer_class,
                                 rule_id, decided_by, cap_amount, cap_basis_kind, cap_basis_amount, cap_source, cap_other_held)
    VALUES ('00000000-0000-4000-8000-0000000015a1', '00000000-0000-4000-8000-0000000015c2', 'additional_trigger', 'usage_doubled', 'cash', 100, DATE '2026-01-01',
            'ZZ', 'gas', 'household', pg_temp.id('zz_add_rule'), 'core-test', 300, 'months_of_billing', 150, 'statute', 0);
    RAISE EXCEPTION 'FAIL N2a: a usage deposit without the threshold its rule sets';
  EXCEPTION WHEN check_violation THEN NULL; END;
  BEGIN
    INSERT INTO public.deposits (tenant_id, customer_id, basis, trigger_basis, instrument, principal, posted_on, state_code, service_type, customer_class,
                                 rule_id, decided_by, cap_amount, cap_basis_kind, cap_basis_amount, cap_source, cap_other_held,
                                 trigger_threshold_source, trigger_rule_threshold_id, trigger_observed)
    VALUES ('00000000-0000-4000-8000-0000000015a1', '00000000-0000-4000-8000-0000000015c2', 'additional_trigger', 'usage_doubled', 'cash', 100, DATE '2026-01-01',
            'ZZ', 'gas', 'household', pg_temp.id('zz_add_rule'), 'core-test', 300, 'months_of_billing', 150, 'statute', 0,
            'statute', v_nsf, 3);
    RAISE EXCEPTION 'FAIL N2b: a usage deposit citing the NSF threshold';
  EXCEPTION WHEN check_violation THEN NULL; END;
  BEGIN
    INSERT INTO public.deposits (tenant_id, customer_id, basis, trigger_basis, instrument, principal, posted_on, state_code, service_type, customer_class,
                                 rule_id, decided_by, cap_amount, cap_basis_kind, cap_basis_amount, cap_source, cap_other_held,
                                 trigger_threshold_source, trigger_rule_threshold_id, trigger_observed)
    VALUES ('00000000-0000-4000-8000-0000000015a1', '00000000-0000-4000-8000-0000000015c2', 'additional_trigger', 'usage_doubled', 'cash', 100, DATE '2026-01-01',
            'ZZ', 'gas', 'household', pg_temp.id('zz_add_rule'), 'core-test', 300, 'months_of_billing', 150, 'statute', 0,
            'statute', v_use, 2.4);
    RAISE EXCEPTION 'FAIL N2c: use at 2.4 times the estimate under a 2.5 threshold';
  EXCEPTION WHEN check_violation THEN NULL; END;
  BEGIN
    INSERT INTO public.deposits (tenant_id, customer_id, basis, trigger_basis, instrument, principal, posted_on, state_code, service_type, customer_class,
                                 rule_id, decided_by, cap_amount, cap_basis_kind, cap_basis_amount, cap_source, cap_other_held,
                                 trigger_threshold_source, trigger_rule_threshold_id, trigger_observed)
    VALUES ('00000000-0000-4000-8000-0000000015a1', '00000000-0000-4000-8000-0000000015c2', 'additional_trigger', 'nsf', 'cash', 100, DATE '2026-01-01',
            'ZZ', 'gas', 'household', pg_temp.id('zz_add_rule'), 'core-test', 300, 'months_of_billing', 150, 'statute', 0,
            'statute', v_nsf, 2.5);
    RAISE EXCEPTION 'FAIL N2d: two and a half NSFs';
  EXCEPTION WHEN check_violation THEN NULL; END;
  INSERT INTO public.deposits (tenant_id, customer_id, basis, trigger_basis, instrument, principal, posted_on, state_code, service_type, customer_class,
                               rule_id, decided_by, cap_amount, cap_basis_kind, cap_basis_amount, cap_source, cap_other_held,
                               trigger_threshold_source, trigger_rule_threshold_id, trigger_observed)
  VALUES ('00000000-0000-4000-8000-0000000015a1', '00000000-0000-4000-8000-0000000015c2', 'additional_trigger', 'usage_doubled', 'cash', 100, DATE '2026-01-01',
          'ZZ', 'gas', 'household', pg_temp.id('zz_add_rule'), 'core-test', 300, 'months_of_billing', 150, 'statute', 0,
          'statute', v_use, 2.5);
  RAISE NOTICE 'PASS N2: where the rule sets a threshold for the trigger, the deposit cites it — that trigger''s, and met (2.5 times the estimate; a whole number of NSFs) (review r2 D1)';
END $$;
DO $$ DECLARE v_dpa uuid; v_nsf uuid; BEGIN
  INSERT INTO public.deposit_tariff_trigger_thresholds (tenant_id, state_code, service_type, trigger_code, measure, min_count, window_months,
                                                        tariff_reference, effective_from, created_by)
  VALUES ('00000000-0000-4000-8000-0000000015a1', 'ZZ', 'gas', 'broken_dpa', 'event_count', 3, 12, 'Gasco tariff 9.2', DATE '2025-06-01',
          '00000000-0000-4000-8000-0000000015b1') RETURNING id INTO v_dpa;
  INSERT INTO b15 VALUES ('tt_dpa', v_dpa);
  INSERT INTO public.deposit_tariff_trigger_thresholds (tenant_id, state_code, service_type, trigger_code, measure, min_count, window_months,
                                                        tariff_reference, effective_from)
  VALUES ('00000000-0000-4000-8000-0000000015a1', 'ZZ', 'gas', 'nsf', 'event_count', 2, 6, 'Gasco tariff 9.1', DATE '2025-06-01') RETURNING id INTO v_nsf;
  BEGIN
    INSERT INTO public.deposits (tenant_id, customer_id, basis, trigger_basis, instrument, principal, posted_on, state_code, service_type, customer_class,
                                 rule_id, decided_by, cap_amount, cap_basis_kind, cap_basis_amount, cap_source, cap_other_held,
                                 trigger_threshold_source, trigger_tariff_threshold_id, trigger_observed)
    VALUES ('00000000-0000-4000-8000-0000000015a1', '00000000-0000-4000-8000-0000000015c2', 'additional_trigger', 'broken_dpa', 'cash', 100, DATE '2026-01-01',
            'ZZ', 'gas', 'household', pg_temp.id('zz_add_rule'), 'core-test', 300, 'months_of_billing', 150, 'statute', 0,
            'tariff', v_nsf, 3);
    RAISE EXCEPTION 'FAIL N3a: a broken-DPA deposit citing the tariff''s NSF threshold';
  EXCEPTION WHEN check_violation THEN NULL; END;
  BEGIN
    INSERT INTO public.deposits (tenant_id, customer_id, basis, trigger_basis, instrument, principal, posted_on, state_code, service_type, customer_class,
                                 rule_id, decided_by, cap_amount, cap_basis_kind, cap_basis_amount, cap_source, cap_other_held,
                                 trigger_threshold_source, trigger_tariff_threshold_id, trigger_observed)
    VALUES ('00000000-0000-4000-8000-0000000015a1', '00000000-0000-4000-8000-0000000015c2', 'additional_trigger', 'broken_dpa', 'cash', 100, DATE '2025-03-01',
            'ZZ', 'gas', 'household', pg_temp.id('zz_add_rule'), 'core-test', 300, 'months_of_billing', 150, 'statute', 0,
            'tariff', v_dpa, 3);
    RAISE EXCEPTION 'FAIL N3b: a tariff threshold cited before it took effect';
  EXCEPTION WHEN check_violation THEN NULL; END;
  INSERT INTO public.deposits (tenant_id, customer_id, basis, trigger_basis, instrument, principal, posted_on, state_code, service_type, customer_class,
                               rule_id, decided_by, cap_amount, cap_basis_kind, cap_basis_amount, cap_source, cap_other_held,
                               trigger_threshold_source, trigger_tariff_threshold_id, trigger_observed)
  VALUES ('00000000-0000-4000-8000-0000000015a1', '00000000-0000-4000-8000-0000000015c2', 'additional_trigger', 'broken_dpa', 'cash', 100, DATE '2026-01-01',
          'ZZ', 'gas', 'household', pg_temp.id('zz_add_rule'), 'core-test', 300, 'months_of_billing', 150, 'statute', 0,
          'tariff', v_dpa, 3);
  BEGIN
    UPDATE public.deposits SET trigger_observed = 4 WHERE trigger_tariff_threshold_id = v_dpa;
    RAISE EXCEPTION 'FAIL N3c: the observed measure edited';
  EXCEPTION WHEN check_violation THEN NULL; END;
  RAISE NOTICE 'PASS N3: the utility''s own tariff threshold is its row; a deposit cites one of its trigger in force on posting, and the citation is frozen (review r2 D1)';
END $$;
-- N4 (D3): a deposit taken in instalments, under ZZ's schedule (half, then
-- a quarter at 30 and 60 days). Principal 300 = two months of 150.
DO $$ BEGIN
  EXECUTE 'SET CONSTRAINTS ALL DEFERRED';
  INSERT INTO public.deposits (id, tenant_id, customer_id, basis, trigger_basis, instrument, principal, posted_on, state_code, service_type, customer_class,
                               rule_id, decided_by, cap_amount, cap_basis_kind, cap_basis_amount, cap_source, cap_other_held, cap_binding, received_at_posting)
  VALUES ('00000000-0000-4000-8000-00000000154a', '00000000-0000-4000-8000-0000000015a1', '00000000-0000-4000-8000-0000000015c1', 'additional_trigger', 'broken_dpa', 'cash', 300, DATE '2026-02-01',
          'ZZ', 'gas', 'household', pg_temp.id('zz_add_rule'), 'core-test', 300, 'months_of_billing', 150, 'statute', 0, true, 150);
  INSERT INTO public.deposit_instalments (tenant_id, deposit_id, instalment_no, amount, due_on) VALUES
    ('00000000-0000-4000-8000-0000000015a1', '00000000-0000-4000-8000-00000000154a', 2, 75, DATE '2026-03-03'),
    ('00000000-0000-4000-8000-0000000015a1', '00000000-0000-4000-8000-00000000154a', 3, 75, DATE '2026-04-02');
  EXECUTE 'SET CONSTRAINTS ALL IMMEDIATE';
  INSERT INTO b15 VALUES ('inst', '00000000-0000-4000-8000-00000000154a');
END $$;
DO $$ DECLARE b record; BEGIN
  SELECT * INTO b FROM public.deposit_balance(pg_temp.id('inst'));
  IF b.principal <> 300 OR b.remainder <> 150
     OR (SELECT amount FROM public.deposit_events WHERE deposit_id = pg_temp.id('inst') AND event_type = 'posted') <> 150 THEN
    RAISE EXCEPTION 'FAIL N4: the deposit holds what was received: %', row_to_json(b);
  END IF;
  RAISE NOTICE 'PASS N4: a deposit taken in instalments records the deposit required (300) and holds what was received (150 at posting) (review r2 D3)';
END $$;
DO $$ BEGIN
  INSERT INTO public.deposits (tenant_id, customer_id, basis, instrument, principal, posted_on, state_code, service_type, customer_class,
                               rule_id, decided_by, cap_amount, cap_basis_kind, cap_basis_amount, cap_source, received_at_posting)
  VALUES ('00000000-0000-4000-8000-0000000015a1', '00000000-0000-4000-8000-0000000015c1', 'credit_evaluation', 'cash', 100, DATE '2026-02-01',
          'TX', 'gas', 'residential', pg_temp.r('TX', 'residential', 'credit_evaluation'), 'core-test', 100, 'fraction_of_annual_billing', 600, 'statute', 50);
  RAISE EXCEPTION 'FAIL N5a: instalments under a rule that offers none';
EXCEPTION WHEN check_violation THEN NULL; END $$;
DO $$ BEGIN
  EXECUTE 'SET CONSTRAINTS ALL DEFERRED';
  INSERT INTO public.deposits (id, tenant_id, customer_id, basis, trigger_basis, instrument, principal, posted_on, state_code, service_type, customer_class,
                               rule_id, decided_by, cap_amount, cap_basis_kind, cap_basis_amount, cap_source, cap_other_held, received_at_posting)
  VALUES ('00000000-0000-4000-8000-00000000154b', '00000000-0000-4000-8000-0000000015a1', '00000000-0000-4000-8000-0000000015c1', 'additional_trigger', 'broken_dpa', 'cash', 300, DATE '2026-02-01',
          'ZZ', 'gas', 'household', pg_temp.id('zz_add_rule'), 'core-test', 300, 'months_of_billing', 150, 'statute', 0, 150);
  INSERT INTO public.deposit_instalments (tenant_id, deposit_id, instalment_no, amount, due_on) VALUES
    ('00000000-0000-4000-8000-0000000015a1', '00000000-0000-4000-8000-00000000154b', 2, 150, DATE '2026-03-03');
  EXECUTE 'SET CONSTRAINTS ALL IMMEDIATE';
  RAISE EXCEPTION 'FAIL N5b: two instalments under a three-instalment schedule';
EXCEPTION WHEN check_violation THEN NULL; END $$;
DO $$ BEGIN
  EXECUTE 'SET CONSTRAINTS ALL DEFERRED';
  INSERT INTO public.deposits (id, tenant_id, customer_id, basis, trigger_basis, instrument, principal, posted_on, state_code, service_type, customer_class,
                               rule_id, decided_by, cap_amount, cap_basis_kind, cap_basis_amount, cap_source, cap_other_held, received_at_posting)
  VALUES ('00000000-0000-4000-8000-00000000154b', '00000000-0000-4000-8000-0000000015a1', '00000000-0000-4000-8000-0000000015c1', 'additional_trigger', 'broken_dpa', 'cash', 300, DATE '2026-02-01',
          'ZZ', 'gas', 'household', pg_temp.id('zz_add_rule'), 'core-test', 300, 'months_of_billing', 150, 'statute', 0, 150);
  INSERT INTO public.deposit_instalments (tenant_id, deposit_id, instalment_no, amount, due_on) VALUES
    ('00000000-0000-4000-8000-0000000015a1', '00000000-0000-4000-8000-00000000154b', 2, 75, DATE '2026-03-03'),
    ('00000000-0000-4000-8000-0000000015a1', '00000000-0000-4000-8000-00000000154b', 3, 50, DATE '2026-04-02');
  EXECUTE 'SET CONSTRAINTS ALL IMMEDIATE';
  RAISE EXCEPTION 'FAIL N5c: instalments summing to 275 of 300';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'PASS N5: instalments only where the rule offers a schedule; at commit as many as the schedule, summing to the deposit (review r2 D3)'; END $$;
DO $$ BEGIN
  INSERT INTO public.deposit_instalments (tenant_id, deposit_id, instalment_no, amount, due_on)
  VALUES ('00000000-0000-4000-8000-0000000015a1', pg_temp.id('r'), 2, 10, DATE '2026-03-03');
  RAISE EXCEPTION 'FAIL N6a: an instalment on a deposit received whole';
EXCEPTION WHEN check_violation THEN NULL; END $$;
DO $$ BEGIN
  EXECUTE 'SET CONSTRAINTS ALL DEFERRED';
  INSERT INTO public.deposits (id, tenant_id, customer_id, basis, trigger_basis, instrument, principal, posted_on, state_code, service_type, customer_class,
                               rule_id, decided_by, cap_amount, cap_basis_kind, cap_basis_amount, cap_source, cap_other_held, received_at_posting)
  VALUES ('00000000-0000-4000-8000-00000000154c', '00000000-0000-4000-8000-0000000015a1', '00000000-0000-4000-8000-0000000015c1', 'additional_trigger', 'broken_dpa', 'cash', 300, DATE '2026-02-01',
          'ZZ', 'gas', 'household', pg_temp.id('zz_add_rule'), 'core-test', 300, 'months_of_billing', 150, 'statute', 0, 150);
  INSERT INTO public.deposit_instalments (tenant_id, deposit_id, instalment_no, amount, due_on) VALUES
    ('00000000-0000-4000-8000-0000000015a1', '00000000-0000-4000-8000-00000000154c', 2, 75, DATE '2026-01-31');
  RAISE EXCEPTION 'FAIL N6b: an instalment due before posting';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'PASS N6: an instalment belongs to a deposit taken in instalments and falls due on or after posting'; END $$;
DO $$ DECLARE st text; BEGIN
  BEGIN
    PERFORM pg_temp.ev(pg_temp.id('r2'), 'instalment_received', 10, DATE '2026-03-03');
    RAISE EXCEPTION 'FAIL N7a: an instalment received on a deposit received whole';
  EXCEPTION WHEN check_violation THEN NULL; END;
  PERFORM pg_temp.ev(pg_temp.id('inst'), 'applied_to_balance', 150, DATE '2026-02-20');
  IF (SELECT status FROM public.deposits WHERE id = pg_temp.id('inst')) <> 'applied' THEN RAISE EXCEPTION 'FAIL N7: not applied'; END IF;
  PERFORM pg_temp.ev(pg_temp.id('inst'), 'instalment_received', 75, DATE '2026-03-03');
  SELECT status INTO st FROM public.deposits WHERE id = pg_temp.id('inst');
  IF st <> 'partial_applied' OR (SELECT remainder FROM public.deposit_balance(pg_temp.id('inst'))) <> 75 THEN
    RAISE EXCEPTION 'FAIL N7b: an instalment received after the whole was applied leaves status % ', st;
  END IF;
  BEGIN
    PERFORM pg_temp.ev(pg_temp.id('inst'), 'instalment_received', 76, DATE '2026-04-02');
    RAISE EXCEPTION 'FAIL N7c: more received than the deposit required';
  EXCEPTION WHEN check_violation THEN NULL; END;
  BEGIN
    UPDATE public.deposits SET received_at_posting = 100 WHERE id = pg_temp.id('inst');
    RAISE EXCEPTION 'FAIL N7d: received_at_posting edited';
  EXCEPTION WHEN check_violation THEN NULL; END;
  RAISE NOTICE 'PASS N7: instalments are received only on a deposit taken in instalments, never beyond the deposit required; a receipt after full application makes it partially applied again; the schedule is frozen (review r2 D3)';
END $$;
-- N8 (I3): chronology holds whichever record is written first. Deposit P:
-- TX residential cash 100, posted 2026-01-01; 30 returned on 2026-03-15.
DO $$ BEGIN
  PERFORM pg_temp.dep('p', '00000000-0000-4000-8000-0000000015c1', 'credit_evaluation', 'residential', 'cash', 100, DATE '2026-01-01');
  PERFORM pg_temp.ev(pg_temp.id('p'), 'principal_returned', 30, DATE '2026-03-15');
  BEGIN
    PERFORM pg_temp.accb(pg_temp.id('p'), pg_temp.id('rate_mar'), DATE '2026-03-01', DATE '2026-03-31', 0.10, DATE '2026-04-01', 70);
    RAISE EXCEPTION 'FAIL N8a: an accrual spanning a partial return written after it';
  EXCEPTION WHEN check_violation THEN NULL; END;
  PERFORM pg_temp.accb(pg_temp.id('p'), pg_temp.id('rate_mar'), DATE '2026-04-01', DATE '2026-04-30', 0.14, DATE '2026-05-01', 70);
  BEGIN
    PERFORM pg_temp.accb(pg_temp.id('p'), pg_temp.id('rate_mar'), DATE '2026-05-01', DATE '2026-05-31', 0.21, DATE '2026-06-01', 100);
    RAISE EXCEPTION 'FAIL N8b: an accrual on more than was held through the period';
  EXCEPTION WHEN check_violation THEN NULL; END;
  BEGIN
    INSERT INTO public.deposit_events (tenant_id, deposit_id, event_type, amount, effective_on)
    SELECT d.tenant_id, d.id, 'interest_credited', 0.14, DATE '2026-04-30' FROM public.deposits d WHERE d.id = pg_temp.id('p');
    RAISE EXCEPTION 'FAIL N8c: interest credited on the last day of the period it was earned in';
  EXCEPTION WHEN check_violation THEN NULL; END;
  INSERT INTO public.deposit_events (tenant_id, deposit_id, event_type, amount, effective_on)
  SELECT d.tenant_id, d.id, 'interest_credited', 0.14, DATE '2026-05-01' FROM public.deposits d WHERE d.id = pg_temp.id('p');
  BEGIN
    PERFORM pg_temp.accb(pg_temp.id('p'), pg_temp.id('rate_mar'), DATE '2026-09-01', (now() AT TIME ZONE 'UTC')::date, 0.10,
                         (now() AT TIME ZONE 'UTC')::date + 1, 70);
    RAISE EXCEPTION 'FAIL N8d: an accrual for a period ending today';
  EXCEPTION WHEN check_violation THEN NULL; END;
  RAISE NOTICE 'PASS N8: no accrual spans a partial return or earns on more than was held through its period; interest is credited only once earned; an accrual''s period has ended (review r2 I3)';
END $$;
DO $$ BEGIN
  -- Q: refund started 2026-05-01; an accrual written after it may not reach
  -- that day (the remainder is still held, so only this guard refuses).
  PERFORM pg_temp.dep('q', '00000000-0000-4000-8000-0000000015c1', 'credit_evaluation', 'residential', 'cash', 100, DATE '2026-01-01');
  PERFORM pg_temp.ev(pg_temp.id('q'), 'refund_initiated', 100, DATE '2026-05-01');
  PERFORM pg_temp.accb(pg_temp.id('q'), pg_temp.id('rate_mar'), DATE '2026-03-01', DATE '2026-04-30', 0.41, DATE '2026-05-02', 100);
  BEGIN
    PERFORM pg_temp.accb(pg_temp.id('q'), pg_temp.id('rate_mar'), DATE '2026-05-01', DATE '2026-05-31', 0.21, DATE '2026-06-01', 100);
    RAISE EXCEPTION 'FAIL N9: an accrual reaching the day the refund started';
  EXCEPTION WHEN check_violation THEN NULL; END;
  RAISE NOTICE 'PASS N9: no accrual ends on or after a full return, whichever is written first (review r2 I3)';
END $$;
-- N10 (I4): evidence on or before the due date; a return on or after it.
DO $$ BEGIN
  PERFORM pg_temp.dep('n10', '00000000-0000-4000-8000-0000000015c1', 'credit_evaluation', 'residential', 'cash', 50, DATE '2026-01-20');
  BEGIN
    EXECUTE 'SET CONSTRAINTS ALL DEFERRED';
    PERFORM pg_temp.due('00000000-0000-4000-8000-0000000015f0', pg_temp.id('n10'), DATE '2026-03-15');
    PERFORM pg_temp.evid('00000000-0000-4000-8000-0000000015f0', 'clean_bill_history', '00000000-0000-4000-8000-0000000015e2', 'clean', NULL);
    RAISE EXCEPTION 'FAIL N10a: a bill dated after the due date as its evidence';
  EXCEPTION WHEN check_violation THEN NULL; END;
  BEGIN
    EXECUTE 'SET CONSTRAINTS ALL DEFERRED';
    PERFORM pg_temp.due('00000000-0000-4000-8000-0000000015f0', pg_temp.id('n10'), DATE '2026-04-01');
    PERFORM pg_temp.evid('00000000-0000-4000-8000-0000000015f0', 'account_closed', NULL, NULL,
                         (SELECT id FROM public.customer_state_events WHERE customer_id = '00000000-0000-4000-8000-0000000015c1' AND to_status = 'final_billed'));
    RAISE EXCEPTION 'FAIL N10b: a closure after the due date as its evidence';
  EXCEPTION WHEN check_violation THEN NULL; END;
  EXECUTE 'SET CONSTRAINTS ALL DEFERRED';
  PERFORM pg_temp.due('00000000-0000-4000-8000-0000000015f0', pg_temp.id('n10'), DATE '2026-03-15');
  PERFORM pg_temp.evid('00000000-0000-4000-8000-0000000015f0', 'clean_bill_history', '00000000-0000-4000-8000-0000000015e1', 'clean', NULL);
  EXECUTE 'SET CONSTRAINTS ALL IMMEDIATE';
  BEGIN
    PERFORM pg_temp.ev(pg_temp.id('n10'), 'refund_initiated', 50, DATE '2026-03-10', '00000000-0000-4000-8000-0000000015f0');
    RAISE EXCEPTION 'FAIL N10c: a refund settling a due row before it fell due';
  EXCEPTION WHEN check_violation THEN NULL; END;
  PERFORM pg_temp.ev(pg_temp.id('n10'), 'refund_initiated', 50, DATE '2026-03-15', '00000000-0000-4000-8000-0000000015f0');
  RAISE NOTICE 'PASS N10: a due row''s evidence is dated on or before it fell due, and a return settling it on or after (review r2 I4)';
END $$;
-- N11 (I8): a closure is dated by the UTC day, whatever the session's time
-- zone. Deposit and due date are today (UTC); the session is put in a zone
-- whose date differs from UTC's right now.
DO $$ DECLARE v_today date := (now() AT TIME ZONE 'UTC')::date; v_old text := current_setting('TimeZone'); BEGIN
  PERFORM set_config('TimeZone', CASE WHEN extract(hour FROM now() AT TIME ZONE 'UTC') >= 10 THEN 'Pacific/Kiritimati' ELSE 'Pacific/Pago_Pago' END, true);
  IF now()::date = v_today THEN RAISE EXCEPTION 'FAIL N11: the probe zone shares UTC''s date'; END IF;
  PERFORM pg_temp.dep('n11', '00000000-0000-4000-8000-0000000015c2', 'credit_evaluation', 'residential', 'cash', 50, v_today);
  EXECUTE 'SET CONSTRAINTS ALL DEFERRED';
  PERFORM pg_temp.due('00000000-0000-4000-8000-0000000015f1', pg_temp.id('n11'), v_today);
  PERFORM pg_temp.evid('00000000-0000-4000-8000-0000000015f1', 'account_closed', NULL, NULL,
                       (SELECT id FROM public.customer_state_events WHERE customer_id = '00000000-0000-4000-8000-0000000015c2' AND to_status = 'final_billed'));
  EXECUTE 'SET CONSTRAINTS ALL IMMEDIATE';
  PERFORM set_config('TimeZone', v_old, true);
  RAISE NOTICE 'PASS N11: closure evidence is dated by its UTC day, so a session in another zone reads the same answer (review r2 I8)';
END $$;
-- N12 (D4): a partial return due — ZZ returns the excess over the cap.
DO $$ BEGIN
  PERFORM pg_temp.dep('x', '00000000-0000-4000-8000-0000000015c2', 'credit_evaluation', 'household', 'cash', 300, DATE '2025-06-01', 'ZZ');
  BEGIN
    EXECUTE 'SET CONSTRAINTS ALL DEFERRED';
    INSERT INTO public.deposit_return_due (id, tenant_id, deposit_id, rule_id, due_on, amount, inputs, inputs_fingerprint, calculated_by)
    SELECT '00000000-0000-4000-8000-0000000015f2', d.tenant_id, d.id, d.rule_id, DATE '2026-04-01', 10, '{}', 'fp', 'core-test'
      FROM public.deposits d WHERE d.id = pg_temp.id('p');
    RAISE EXCEPTION 'FAIL N12a: a partial return due under a rule that returns no excess';
  EXCEPTION WHEN check_violation THEN NULL; END;
  BEGIN
    EXECUTE 'SET CONSTRAINTS ALL DEFERRED';
    INSERT INTO public.deposit_return_due (id, tenant_id, deposit_id, rule_id, due_on, amount, inputs, inputs_fingerprint, calculated_by)
    SELECT '00000000-0000-4000-8000-0000000015f2', d.tenant_id, d.id, d.rule_id, DATE '2026-02-01', 300, '{}', 'fp', 'core-test'
      FROM public.deposits d WHERE d.id = pg_temp.id('x');
    RAISE EXCEPTION 'FAIL N12b: a partial return of everything held';
  EXCEPTION WHEN check_violation THEN NULL; END;
  BEGIN
    EXECUTE 'SET CONSTRAINTS ALL DEFERRED';
    INSERT INTO public.deposit_return_due (id, tenant_id, deposit_id, rule_id, due_on, amount, inputs, inputs_fingerprint, calculated_by)
    SELECT '00000000-0000-4000-8000-0000000015f2', d.tenant_id, d.id, d.rule_id, DATE '2026-02-01', 100, '{}', 'fp', 'core-test'
      FROM public.deposits d WHERE d.id = pg_temp.id('x');
    PERFORM pg_temp.evid('00000000-0000-4000-8000-0000000015f2', 'service_term_complete', '00000000-0000-4000-8000-0000000015e8', 'clean', NULL);
    RAISE EXCEPTION 'FAIL N12c: a whole-return reason on a partial due row';
  EXCEPTION WHEN check_violation THEN NULL; END;
  BEGIN
    EXECUTE 'SET CONSTRAINTS ALL DEFERRED';
    PERFORM pg_temp.due('00000000-0000-4000-8000-0000000015f2', pg_temp.id('x'), DATE '2026-02-01');
    INSERT INTO public.deposit_return_due_evidence (tenant_id, due_id, reason_code, rests_on_deposit)
    VALUES ('00000000-0000-4000-8000-0000000015a1', '00000000-0000-4000-8000-0000000015f2', 'excess_over_cap', true);
    RAISE EXCEPTION 'FAIL N12d: an excess-over-cap reason on a whole-return due row';
  EXCEPTION WHEN check_violation THEN NULL; END;
  RAISE NOTICE 'PASS N12: a partial return is due only under a rule that returns an excess over the cap, leaves something held, and rests on a partial reason — and a partial reason only on a due row with an amount (review r2 D4)';
END $$;
SET CONSTRAINTS ALL DEFERRED;
INSERT INTO public.deposit_return_due (id, tenant_id, deposit_id, rule_id, due_on, amount, inputs, inputs_fingerprint, calculated_by)
SELECT '00000000-0000-4000-8000-0000000015f2', d.tenant_id, d.id, d.rule_id, DATE '2026-02-01', 100, '{}', 'fp', 'core-test'
  FROM public.deposits d WHERE d.id = pg_temp.id('x');
INSERT INTO public.deposit_return_due_evidence (tenant_id, due_id, reason_code, rests_on_deposit)
VALUES ('00000000-0000-4000-8000-0000000015a1', '00000000-0000-4000-8000-0000000015f2', 'excess_over_cap', true);
SET CONSTRAINTS ALL IMMEDIATE;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.deposits_return_owed WHERE due_id = '00000000-0000-4000-8000-0000000015f2' AND amount_due = 100) THEN
    RAISE EXCEPTION 'FAIL N13: the partial return is not listed with its amount';
  END IF;
  BEGIN
    PERFORM pg_temp.ev(pg_temp.id('x'), 'refund_initiated', 300, DATE '2026-02-02', '00000000-0000-4000-8000-0000000015f2');
    RAISE EXCEPTION 'FAIL N13a: a refund settling a partial due row';
  EXCEPTION WHEN check_violation THEN NULL; END;
  BEGIN
    PERFORM pg_temp.ev(pg_temp.id('x'), 'principal_returned', 50, DATE '2026-02-02', '00000000-0000-4000-8000-0000000015f2');
    RAISE EXCEPTION 'FAIL N13b: a partial return of another amount settling it';
  EXCEPTION WHEN check_violation THEN NULL; END;
  PERFORM pg_temp.ev(pg_temp.id('x'), 'principal_returned', 100, DATE '2026-02-02', '00000000-0000-4000-8000-0000000015f2');
  IF EXISTS (SELECT 1 FROM public.deposits_return_owed WHERE due_id = '00000000-0000-4000-8000-0000000015f2') THEN
    RAISE EXCEPTION 'FAIL N13c: a settled partial return still owed';
  END IF;
  -- settled, it is no longer live: the deposit may fall due again
  EXECUTE 'SET CONSTRAINTS ALL DEFERRED';
  PERFORM pg_temp.due('00000000-0000-4000-8000-0000000015f3', pg_temp.id('x'), DATE '2026-04-01');
  PERFORM pg_temp.evid('00000000-0000-4000-8000-0000000015f3', 'service_term_complete', '00000000-0000-4000-8000-0000000015e8', 'clean', NULL);
  EXECUTE 'SET CONSTRAINTS ALL IMMEDIATE';
  BEGIN
    PERFORM pg_temp.ev(pg_temp.id('x'), 'principal_returned', 50, DATE '2026-04-02', '00000000-0000-4000-8000-0000000015f3');
    RAISE EXCEPTION 'FAIL N13d: a partial return settling a whole-return due row';
  EXCEPTION WHEN check_violation THEN NULL; END;
  RAISE NOTICE 'PASS N13: a partial due row is listed with its amount and settled only by principal_returned of exactly that amount, after which it is no longer live; a whole-return row is not settled by a partial return (review r2 D4)';
END $$;
-- N14 (I2): a history reason rests on the measure its rule counts in.
DO $$ BEGIN
  BEGIN
    EXECUTE 'SET CONSTRAINTS ALL DEFERRED';
    PERFORM pg_temp.due('00000000-0000-4000-8000-0000000015f4', pg_temp.id('p'), DATE '2026-06-01');
    INSERT INTO public.deposit_return_due_evidence (tenant_id, due_id, reason_code, rests_on_deposit)
    VALUES ('00000000-0000-4000-8000-0000000015a1', '00000000-0000-4000-8000-0000000015f4', 'hold_term_elapsed', true);
    RAISE EXCEPTION 'FAIL N14a: time held as the reason under a rule that counts bills';
  EXCEPTION WHEN check_violation THEN NULL; END;
  PERFORM pg_temp.dep('y', '00000000-0000-4000-8000-0000000015c2', 'credit_evaluation', 'household', 'cash', 100, DATE '2025-03-01', 'ZZ');
  BEGIN
    EXECUTE 'SET CONSTRAINTS ALL DEFERRED';
    PERFORM pg_temp.due('00000000-0000-4000-8000-0000000015f4', pg_temp.id('y'), DATE '2026-04-01');
    PERFORM pg_temp.evid('00000000-0000-4000-8000-0000000015f4', 'clean_bill_history', '00000000-0000-4000-8000-0000000015e8', 'clean', NULL);
    RAISE EXCEPTION 'FAIL N14b: a clean bill history as the reason under a rule that counts months';
  EXCEPTION WHEN check_violation THEN NULL; END;
  RAISE NOTICE 'PASS N14: a clean bill history rests on a rule counting bills, time held on one counting months (review r2 I2)';
END $$;
RESET ROLE;
-- N15 (I6): a third utility keeps a residential-only rate and holds a
-- non-residential deposit; the report shows the missing rate for that class.
DO $$ BEGIN
  INSERT INTO public.tenants (id, name, slug) VALUES ('00000000-0000-4000-8000-0000000015a3', 'T3 Gasco', 'bat15-t3');
  INSERT INTO public.customers (id, tenant_id, customer_number, customer_type) VALUES
    ('00000000-0000-4000-8000-0000000015ca', '00000000-0000-4000-8000-0000000015a3', 'B15-CA', 'commercial');
  INSERT INTO public.deposit_interest_rates (tenant_id, state_code, service_type, customer_class, effective_date, annual_rate)
  VALUES ('00000000-0000-4000-8000-0000000015a3', 'TX', 'gas', 'residential', DATE '2026-01-01', 0.0287);
  INSERT INTO public.deposits (tenant_id, customer_id, basis, instrument, principal, posted_on, state_code, service_type, customer_class, rule_id, decided_by)
  VALUES ('00000000-0000-4000-8000-0000000015a3', '00000000-0000-4000-8000-0000000015ca', 'credit_evaluation', 'cash', 500, DATE '2026-02-01',
          'TX', 'gas', 'non_residential', pg_temp.r('TX', 'non_residential', 'credit_evaluation'), 'core-test');
  IF NOT EXISTS (SELECT 1 FROM public.deposit_interest_rate_discrepancies
                  WHERE tenant_id = '00000000-0000-4000-8000-0000000015a3' AND discrepancy = 'no_utility_rate' AND customer_class = 'non_residential') THEN
    RAISE EXCEPTION 'FAIL N15: a residential-only rate hides the missing non-residential rate';
  END IF;
  IF EXISTS (SELECT 1 FROM public.deposit_interest_rate_discrepancies
              WHERE tenant_id = '00000000-0000-4000-8000-0000000015a3' AND discrepancy = 'no_utility_rate' AND customer_class = 'residential') THEN
    RAISE EXCEPTION 'FAIL N15: the covered residential class reported missing';
  END IF;
  RAISE NOTICE 'PASS N15: the rate report judges coverage per class held — a residential rate no longer hides the non-residential deposits'' missing rate (review r2 I6)';
END $$;
-- N16: a tariff threshold closes like a waiver ground — never on or before
-- a deposit citing it, stamped once.
SET LOCAL app.user_id = '00000000-0000-4000-8000-0000000015b1';
SET ROLE tally_app;
DO $$ BEGIN
  BEGIN
    UPDATE public.deposit_tariff_trigger_thresholds SET effective_to = DATE '2026-01-01' WHERE id = pg_temp.id('tt_dpa');
    RAISE EXCEPTION 'FAIL N16a: a tariff threshold closed on the day a deposit cites it';
  EXCEPTION WHEN restrict_violation THEN NULL; END;
  BEGIN
    -- a close that carries an edit (a bare edit is refused as "not a close")
    UPDATE public.deposit_tariff_trigger_thresholds SET effective_to = DATE '2026-07-01', min_count = 2 WHERE id = pg_temp.id('tt_dpa');
    RAISE EXCEPTION 'FAIL N16b: a tariff threshold edited';
  EXCEPTION WHEN restrict_violation THEN NULL; END;
  UPDATE public.deposit_tariff_trigger_thresholds SET effective_to = DATE '2026-07-01' WHERE id = pg_temp.id('tt_dpa');
  IF (SELECT closed_at IS NULL OR closed_by IS NULL FROM public.deposit_tariff_trigger_thresholds WHERE id = pg_temp.id('tt_dpa')) THEN
    RAISE EXCEPTION 'FAIL N16c: the close was not stamped';
  END IF;
  RAISE NOTICE 'PASS N16: the utility''s threshold is never edited, closes once (stamped) and never on or before a deposit citing it';
END $$;
-- N17 (I1): a return's own date holds its rule's close floor. ZZ's
-- successor (Z6) is cited by an accrual through 2026-07-31 and now by a
-- refund started 2026-09-15; a close from 2026-09-01 is refused.
DO $$ BEGIN
  INSERT INTO public.deposit_events (tenant_id, deposit_id, event_type, amount, effective_on, rule_id, calculated_by)
  SELECT d.tenant_id, d.id, 'refund_initiated', b.remainder, DATE '2026-09-15',
         (SELECT id FROM public.deposit_rules WHERE state_code = 'ZZ' AND customer_class = 'household' AND basis = 'credit_evaluation'
             AND effective_from = DATE '2026-06-01'), 'core-test'
    FROM public.deposits d CROSS JOIN LATERAL public.deposit_balance(d.id) b WHERE d.id = pg_temp.id('zz_dep');
END $$;
RESET ROLE;
DO $$ BEGIN
  UPDATE public.deposit_rules SET effective_to = DATE '2026-09-01'
   WHERE state_code = 'ZZ' AND customer_class = 'household' AND basis = 'credit_evaluation' AND effective_from = DATE '2026-06-01';
  RAISE EXCEPTION 'FAIL N17: a rule closed before the date a return cites it for';
EXCEPTION WHEN restrict_violation THEN
  RAISE NOTICE 'PASS N17: a return''s date holds its rule''s close floor, as an accrual''s period end does (review r2 I1)'; END $$;


-- ============================================================ G. surfaces
SET LOCAL app.user_id = '00000000-0000-4000-8000-0000000015b2';
SET ROLE tally_app;
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM public.deposit_return_due) OR EXISTS (SELECT 1 FROM public.deposit_return_due_evidence)
     OR EXISTS (SELECT 1 FROM public.deposit_return_due_withdrawals) OR EXISTS (SELECT 1 FROM public.deposits_return_owed)
     OR EXISTS (SELECT 1 FROM public.deposits) OR EXISTS (SELECT 1 FROM public.deposit_tariff_waiver_grounds) THEN
    RAISE EXCEPTION 'FAIL G1: T2 sees T1''s deposit records';
  END IF;
  RAISE NOTICE 'PASS G1: another tenant sees none of the due rows, evidence, withdrawals, owed list, deposits or tariff grounds';
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
