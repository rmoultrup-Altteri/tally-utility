-- PREDICTED; not executed by Codex. Run as owner/superuser on a fresh clone
-- with frozen r4 strictly applied and TEMP revoked from PUBLIC, tally_app, tally_core.
\set ON_ERROR_STOP on
-- ============================================================================
-- BATTERY v5.4.2-22 — wave 2, part 1: periods, the freeze, the close
-- snapshot, GL mapping, receivables aging, write-off recovery (2026-10-15)
-- Run: psql -U tally -d <db-with-patch> -v ON_ERROR_STOP=1 -f battery-22.sql
-- One transaction, rolled back. Fixtures as the owner; every guard the
-- application meets is exercised as tally_app under app.user_id.
-- Each row names its requirement in
-- application/wave2-build-2026-10-15/source-inventory-wave2.md.
--
--   P  periods (P1)              H  the close head (P2, P3)
--   C  the close and snapshot    F  the freeze (P2)
--   R  write-off recovery (W3)   W  receivables aging (W1, W2)
--   G  GL mapping (G1-G4)        I  invariants
-- What one transaction cannot show (recorded time across transactions,
-- reproducibility after later writes, isolation, two sessions) is in
-- races/close-22.sh.
-- ============================================================================
BEGIN;

CREATE FUNCTION pg_temp.refuses_at(p_label text, p_sql text, p_state text, p_guard text) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE v_con text;
BEGIN
  BEGIN
    EXECUTE p_sql;
  EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'CAUGHT SQLSTATE=% message=%', SQLSTATE, SQLERRM;
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
      RAISE NOTICE 'CAUGHT SQLSTATE=% message=%', SQLSTATE, SQLERRM;
  RAISE EXCEPTION 'FAIL %: refused with % (%)', p_label, SQLSTATE, SQLERRM;
END $$;
-- try_text(): a query's one value as text, or 'ERROR <message>' (a check
-- that compares a value fails, rather than stops the run, when it raises).
CREATE FUNCTION pg_temp.try_text(p_sql text) RETURNS text
LANGUAGE plpgsql AS $$
DECLARE v text;
BEGIN
  EXECUTE p_sql INTO v;
  RETURN v;
EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'CAUGHT SQLSTATE=% message=%', SQLSTATE, SQLERRM;
  RETURN 'ERROR ' || SQLERRM;
END $$;
GRANT EXECUTE ON FUNCTION pg_temp.refuses_at(text, text, text, text), pg_temp.ok(text, boolean), pg_temp.admits(text, text),
                          pg_temp.try_text(text) TO tally_app, tally_core;

-- ------------------------------------------------------------------ fixtures
-- T1 (…22a1): two operators' worth of users, three customers. T2 (…22a2): the
-- other tenant. Ids: b users, c customers, d locations, e ledger, f payments.
INSERT INTO public.tenants (id, name, slug) VALUES
  ('00000000-0000-4000-8000-0000000022a1', 'T1 City Gas', 'bat22-t1'),
  ('00000000-0000-4000-8000-0000000022a2', 'T2 Gasco', 'bat22-t2');
INSERT INTO public.users (id, tenant_id, display_name, email, role, is_active) VALUES
  ('00000000-0000-4000-8000-0000000022b1', '00000000-0000-4000-8000-0000000022a1', 'Op1', 'op1@bat22.test', 'operator', true),
  ('00000000-0000-4000-8000-0000000022b4', '00000000-0000-4000-8000-0000000022a1', 'Sup', 'sup@bat22.test', 'tenant_admin', true),
  ('00000000-0000-4000-8000-0000000022b2', '00000000-0000-4000-8000-0000000022a2', 'Sup2', 'sup2@bat22.test', 'tenant_admin', true),
  ('00000000-0000-4000-8000-0000000022b9', '00000000-0000-4000-8000-0000000022a1', 'Admin', 'admin@bat22.test', 'platform_admin', true);
INSERT INTO public.customers (id, tenant_id, customer_number, customer_type) VALUES
  ('00000000-0000-4000-8000-0000000022c1', '00000000-0000-4000-8000-0000000022a1', 'B22-C1', 'residential'),
  ('00000000-0000-4000-8000-0000000022c2', '00000000-0000-4000-8000-0000000022a1', 'B22-C2', 'residential'),
  ('00000000-0000-4000-8000-0000000022c3', '00000000-0000-4000-8000-0000000022a1', 'B22-C3', 'commercial'),
  ('00000000-0000-4000-8000-0000000022c5', '00000000-0000-4000-8000-0000000022a1', 'B22-C5', 'residential'),
  ('00000000-0000-4000-8000-0000000022c9', '00000000-0000-4000-8000-0000000022a2', 'B22-C9', 'residential');
INSERT INTO public.service_locations (id, tenant_id, customer_id, location_number, address_line1, city, state, zip) VALUES
  ('00000000-0000-4000-8000-0000000022d1', '00000000-0000-4000-8000-0000000022a1', '00000000-0000-4000-8000-0000000022c1', 'L1', '1 Main', 'Austin', 'TX', '78701');
-- The opening history, dated before any period (onboarding), as the owner.
INSERT INTO public.account_ledger (id, tenant_id, customer_id, location_id, transaction_date, transaction_type, description, amount) VALUES
  ('00000000-0000-4000-8000-0000000022e1', '00000000-0000-4000-8000-0000000022a1', '00000000-0000-4000-8000-0000000022c2', NULL, DATE '2025-12-01', 'charge', 'C2 Dec', 80.00),
  ('00000000-0000-4000-8000-0000000022e0', '00000000-0000-4000-8000-0000000022a1', '00000000-0000-4000-8000-0000000022c1', NULL, DATE '2026-01-01', 'adjustment', 'C1 on the first day', 1.00),
  ('00000000-0000-4000-8000-0000000022e2', '00000000-0000-4000-8000-0000000022a1', '00000000-0000-4000-8000-0000000022c1', '00000000-0000-4000-8000-0000000022d1', DATE '2026-01-05', 'charge', 'C1 Jan', 100.00),
  ('00000000-0000-4000-8000-0000000022e3', '00000000-0000-4000-8000-0000000022a1', '00000000-0000-4000-8000-0000000022c1', NULL, DATE '2026-01-20', 'payment', 'C1 pays', -60.00),
  ('00000000-0000-4000-8000-0000000022e4', '00000000-0000-4000-8000-0000000022a1', '00000000-0000-4000-8000-0000000022c3', NULL, DATE '2026-01-25', 'write_off', 'C3 written off', -50.00),
  ('00000000-0000-4000-8000-0000000022e9', '00000000-0000-4000-8000-0000000022a2', '00000000-0000-4000-8000-0000000022c9', NULL, DATE '2026-01-10', 'charge', 'T2 Jan', 70.00);
-- A pending payment dated in January, to be moved later (F2c).
INSERT INTO public.payments (id, tenant_id, payment_number, customer_id, payment_date, amount, payment_method, status) VALUES
  ('00000000-0000-4000-8000-0000000022f1', '00000000-0000-4000-8000-0000000022a1', 'B22-P1', '00000000-0000-4000-8000-0000000022c1', DATE '2026-01-28', 10, 'check', 'pending');


-- ============================================================== H the head
SELECT pg_temp.ok('H1 every tenant, a new one included, has a close head with nothing closed',
  (SELECT count(*) FROM public.accounting_close_heads h
    WHERE h.tenant_id IN ('00000000-0000-4000-8000-0000000022a1', '00000000-0000-4000-8000-0000000022a2')
      AND h.closed_through IS NULL) = 2
  AND NOT EXISTS (SELECT 1 FROM public.tenants t WHERE NOT EXISTS (SELECT 1 FROM public.accounting_close_heads h WHERE h.tenant_id = t.id)));
SELECT pg_temp.refuses_at('H2 a head is born with nothing closed',
  $q$INSERT INTO public.accounting_close_heads (tenant_id, closed_through) VALUES ('00000000-0000-4000-8000-0000000022a1', DATE '2026-01-31')$q$,
  '23514', 'born with nothing closed');
SELECT pg_temp.refuses_at('H3 the owner cannot move the head',
  $q$UPDATE public.accounting_close_heads SET closed_through = DATE '2026-01-31' WHERE tenant_id = '00000000-0000-4000-8000-0000000022a1'$q$,
  '23001', 'only through close_accounting_period()');
SELECT pg_temp.refuses_at('H4 the owner cannot delete a head',
  $q$DELETE FROM public.accounting_close_heads WHERE tenant_id = '00000000-0000-4000-8000-0000000022a1'$q$,
  '23001', 'never deleted');
SELECT pg_temp.refuses_at('H4b nor truncate the heads',
  $q$TRUNCATE public.accounting_close_heads CASCADE$q$, '23001', 'never deleted');
SET ROLE tally_app;
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000022b1', true);
SELECT pg_temp.refuses_at('H5 the application holds no UPDATE on closed_through',
  $q$UPDATE public.accounting_close_heads SET closed_through = DATE '2026-01-31' WHERE tenant_id = '00000000-0000-4000-8000-0000000022a1'$q$,
  '42501', 'permission denied');
SELECT pg_temp.refuses_at('H5b the lock column it holds does not move the head either',
  $q$UPDATE public.accounting_close_heads SET updated_at = now() WHERE tenant_id = '00000000-0000-4000-8000-0000000022a1'$q$,
  '23001', 'only through close_accounting_period()');
SELECT pg_temp.ok('H6 the application sees only its own tenant''s head',
  (SELECT count(*) FROM public.accounting_close_heads) = 1);
RESET ROLE;


-- =========================================================== P the periods
SET ROLE tally_app;
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000022b1', true);
SELECT pg_temp.admits('P1 the application opens January',
  $q$INSERT INTO public.accounting_periods (id, tenant_id, period_start, period_end)
     VALUES ('00000000-0000-4000-8000-000000002211', '00000000-0000-4000-8000-0000000022a1', DATE '2026-01-01', DATE '2026-01-31')$q$);
SELECT pg_temp.ok('P1b born open, created_by the session''s user, created_at the database''s',
  (SELECT status = 'open' AND created_by = '00000000-0000-4000-8000-0000000022b1' AND created_at = now() AND closed_at IS NULL
     FROM public.accounting_periods WHERE id = '00000000-0000-4000-8000-000000002211'));
SELECT pg_temp.refuses_at('P2 no overlap (the no-gap rule meets it first; EXCLUDE stands behind)',
  $q$INSERT INTO public.accounting_periods (tenant_id, period_start, period_end)
     VALUES ('00000000-0000-4000-8000-0000000022a1', DATE '2026-01-15', DATE '2026-02-14')$q$,
  '23514', 'no gaps');
SELECT pg_temp.refuses_at('P3 no gap: the next starts the day after the latest',
  $q$INSERT INTO public.accounting_periods (tenant_id, period_start, period_end)
     VALUES ('00000000-0000-4000-8000-0000000022a1', DATE '2026-02-02', DATE '2026-02-28')$q$,
  '23514', 'no gaps');
SELECT pg_temp.refuses_at('P4 a period is born open',
  $q$INSERT INTO public.accounting_periods (tenant_id, period_start, period_end, status, closed_at)
     VALUES ('00000000-0000-4000-8000-0000000022a1', DATE '2026-02-01', DATE '2026-02-28', 'closed', now())$q$,
  '23514', 'born open');
SELECT pg_temp.refuses_at('P5 the last day is on or after the first',
  $q$INSERT INTO public.accounting_periods (tenant_id, period_start, period_end)
     VALUES ('00000000-0000-4000-8000-0000000022a1', DATE '2026-02-01', DATE '2026-01-31')$q$,
  '23514', 'accounting_periods_range_check');
SELECT pg_temp.admits('P6 February follows',
  $q$INSERT INTO public.accounting_periods (id, tenant_id, period_start, period_end)
     VALUES ('00000000-0000-4000-8000-000000002212', '00000000-0000-4000-8000-0000000022a1', DATE '2026-02-01', DATE '2026-02-28')$q$);
SELECT pg_temp.admits('P6b and March',
  $q$INSERT INTO public.accounting_periods (id, tenant_id, period_start, period_end)
     VALUES ('00000000-0000-4000-8000-000000002213', '00000000-0000-4000-8000-0000000022a1', DATE '2026-03-01', DATE '2026-03-31')$q$);
SELECT pg_temp.refuses_at('P7 the application cannot close a period by UPDATE',
  $q$UPDATE public.accounting_periods SET status = 'closed', closed_at = now() WHERE id = '00000000-0000-4000-8000-000000002211'$q$,
  '42501', 'permission denied');
SELECT pg_temp.refuses_at('P7b nor delete one',
  $q$DELETE FROM public.accounting_periods WHERE id = '00000000-0000-4000-8000-000000002213'$q$,
  '42501', 'permission denied');
SELECT pg_temp.refuses_at('P9a only the latest period is withdrawn',
  $q$UPDATE public.accounting_periods SET status = 'withdrawn' WHERE id = '00000000-0000-4000-8000-000000002212'$q$,
  '23001', 'only the tenant''s latest period');
SELECT pg_temp.admits('P9 the latest period, while open, is withdrawn (a mistyped one)',
  $q$UPDATE public.accounting_periods SET status = 'withdrawn' WHERE id = '00000000-0000-4000-8000-000000002213'$q$);
SELECT pg_temp.ok('P9b it stays on record, stamped',
  (SELECT status = 'withdrawn' AND withdrawn_at > now() AND withdrawn_by = '00000000-0000-4000-8000-0000000022b1'
     FROM public.accounting_periods WHERE id = '00000000-0000-4000-8000-000000002213'));
SELECT pg_temp.admits('P9c and its dates are free again',
  $q$INSERT INTO public.accounting_periods (id, tenant_id, period_start, period_end)
     VALUES ('00000000-0000-4000-8000-000000002214', '00000000-0000-4000-8000-0000000022a1', DATE '2026-03-01', DATE '2026-03-31')$q$);
SELECT pg_temp.refuses_at('P9d a withdrawn period is not reopened',
  $q$UPDATE public.accounting_periods SET status = 'open', withdrawn_at = NULL WHERE id = '00000000-0000-4000-8000-000000002213'$q$,
  '23001', 'never edited');
RESET ROLE;
SELECT set_config('app.user_id', '', true);
SELECT pg_temp.refuses_at('P9f a withdrawal names its user (r3)',
  $q$UPDATE public.accounting_periods SET status = 'withdrawn' WHERE id = '00000000-0000-4000-8000-000000002214'$q$,
  '23502', 'names its user');
SELECT pg_temp.refuses_at('P8 the owner cannot edit a period',
  $q$UPDATE public.accounting_periods SET period_end = DATE '2026-01-30' WHERE id = '00000000-0000-4000-8000-000000002211'$q$,
  '23001', 'never edited');
SELECT pg_temp.refuses_at('P8b nor close one by UPDATE',
  $q$UPDATE public.accounting_periods SET status = 'closed', closed_at = now(), closed_by = '00000000-0000-4000-8000-0000000022b4' WHERE id = '00000000-0000-4000-8000-000000002211'$q$,
  '23001', 'never edited');
SELECT pg_temp.refuses_at('P8c nor delete one',
  $q$DELETE FROM public.accounting_periods WHERE id = '00000000-0000-4000-8000-000000002212'$q$,
  '23001', 'never deleted');
-- T2's first period ends today at UTC-12, the last place a day ends: it has
-- not ended everywhere (at UTC+14 it has).
INSERT INTO public.accounting_periods (id, tenant_id, period_start, period_end)
VALUES ('00000000-0000-4000-8000-000000002219', '00000000-0000-4000-8000-0000000022a2',
        (now() AT TIME ZONE 'Etc/GMT+12')::date - 9, (now() AT TIME ZONE 'Etc/GMT+12')::date);


-- ===================================================== C the close (part 1)
SET ROLE tally_app;
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000022b1', true);
SELECT pg_temp.refuses_at('C1 an operator cannot close a period',
  $q$SELECT public.close_accounting_period('00000000-0000-4000-8000-000000002211')$q$,
  '42501', 'supervisor');
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000022b4', true);
SELECT pg_temp.refuses_at('C2 periods close in order',
  $q$SELECT public.close_accounting_period('00000000-0000-4000-8000-000000002212')$q$,
  '23514', 'close in order');
SELECT pg_temp.refuses_at('C3 an unbilled figure comes with its basis',
  $q$SELECT public.close_accounting_period('00000000-0000-4000-8000-000000002211', 12.34)$q$,
  '22023', 'with its basis');
SELECT pg_temp.refuses_at('C3b a blank basis is no basis',
  $q$SELECT public.close_accounting_period('00000000-0000-4000-8000-000000002211', 12.34, '  ')$q$,
  '22023', 'with its basis');
SELECT pg_temp.refuses_at('C4 another tenant''s period is not found',
  $q$SELECT public.close_accounting_period('00000000-0000-4000-8000-000000002219')$q$,
  'P0002', 'not found');
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000022b2', true);
SELECT pg_temp.refuses_at('C5 a period whose last day has not ended does not close',
  $q$SELECT public.close_accounting_period('00000000-0000-4000-8000-000000002219')$q$,
  '23514', 'has not ended');
RESET ROLE;
SET ROLE tally_core;
SELECT pg_temp.refuses_at('C6 the core cannot close',
  $q$SELECT public.close_accounting_period('00000000-0000-4000-8000-000000002211')$q$,
  '42501', 'permission denied');
RESET ROLE;

-- January's activity, posted by the application before the close.
SET ROLE tally_app;
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000022b1', true);
INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount) VALUES
  ('00000000-0000-4000-8000-0000000022e5', '00000000-0000-4000-8000-0000000022a1', '00000000-0000-4000-8000-0000000022c2', DATE '2026-01-31', 'late_fee', 'C2 late fee', 5.00);
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000022b4', true);
SELECT set_config('bat22.close_at', public.close_accounting_period('00000000-0000-4000-8000-000000002211', 1234.56, 'core estimate: 31 days of degree-day usage')::text, true);
RESET ROLE;
SELECT pg_temp.ok('C7 the close returns its instant: the period is closed at it, by the supervisor',
  (SELECT p.status = 'closed' AND p.closed_at = current_setting('bat22.close_at')::timestamptz AND p.closed_by = '00000000-0000-4000-8000-0000000022b4'
     FROM public.accounting_periods p WHERE p.id = '00000000-0000-4000-8000-000000002211')
  AND current_setting('bat22.close_at')::timestamptz > now());
SELECT pg_temp.ok('C8 the head moves to the period''s last day',
  (SELECT closed_through FROM public.accounting_close_heads WHERE tenant_id = '00000000-0000-4000-8000-0000000022a1') = DATE '2026-01-31');
SELECT pg_temp.ok('C9 the snapshot: opening (before January 1) 80, January 1 + 100 - 60 - 50 + 5, closing 76, five entries, the unbilled figure and basis',
  (SELECT s.opening_balance = 80 AND s.closing_balance = 76 AND s.ledger_entry_count = 5
          AND s.recorded_at = current_setting('bat22.close_at')::timestamptz AND s.aging_bucket_days = '{30,60,90,120}'
          AND s.unbilled_revenue = 1234.56 AND s.unbilled_revenue_basis LIKE 'core estimate%'
          AND s.closed_by = '00000000-0000-4000-8000-0000000022b4'
     FROM public.accounting_period_snapshots s WHERE s.period_id = '00000000-0000-4000-8000-000000002211'));
SELECT pg_temp.ok('C10 activity lines by ledger type sum to closing minus opening',
  (SELECT jsonb_object_agg(code, amount) FROM public.accounting_period_snapshot_lines
    WHERE period_id = '00000000-0000-4000-8000-000000002211' AND section = 'activity')
  = '{"adjustment": 1.00, "charge": 100.00, "payment": -60.00, "write_off": -50.00, "late_fee": 5.00}'::jsonb);
-- Aging on January 31: C1 owes 41 of the Jan 5 charge (26 days); C2 owes 80
-- of Dec 1 (61 days) and the 5 late fee (0 days); C3 is owed 50 (credit).
SELECT pg_temp.ok('C11 aging lines: the tenant''s buckets on the last day, credit balances apart',
  (SELECT jsonb_object_agg(code, jsonb_build_array(amount, entry_count)) FROM public.accounting_period_snapshot_lines
    WHERE period_id = '00000000-0000-4000-8000-000000002211' AND section = 'aging')
  = '{"0-30": [46.00, 2], "61-90": [80.00, 1], "credit_balance": [-50.00, 1]}'::jsonb);
SELECT pg_temp.ok('C12 the aging lines are what receivables_aging_as_of() says at the snapshot''s coordinate and stored edges',
  (SELECT jsonb_object_agg(k, v) FROM (
     SELECT coalesce(a.bucket_index::text, 'credit') AS k, sum(a.amount) AS v
       FROM public.accounting_period_snapshots s,
            public.receivables_aging_as_of(s.tenant_id, s.period_end, s.recorded_at, s.aging_bucket_days) a
      WHERE s.period_id = '00000000-0000-4000-8000-000000002211'
      GROUP BY a.bucket_index) x)
  = '{"0": 46.00, "2": 80.00, "credit": -50.00}'::jsonb);
SET ROLE tally_app;
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000022b4', true);
SELECT pg_temp.refuses_at('C13 a closed period never reopens, nor closes twice',
  $q$SELECT public.close_accounting_period('00000000-0000-4000-8000-000000002211')$q$,
  '23514', 'already closed');
SELECT pg_temp.refuses_at('C13b a withdrawn period does not close, and is named for what it is',
  $q$SELECT public.close_accounting_period('00000000-0000-4000-8000-000000002213')$q$,
  '23514', 'is withdrawn');
SELECT pg_temp.refuses_at('C14 the application cannot write a snapshot',
  $q$INSERT INTO public.accounting_period_snapshots (period_id, tenant_id, period_start, period_end, recorded_at, opening_balance, closing_balance, ledger_entry_count, aging_bucket_days, closed_by)
     VALUES ('00000000-0000-4000-8000-000000002212', '00000000-0000-4000-8000-0000000022a1', DATE '2026-02-01', DATE '2026-02-28', now(), 0, 0, 0, '{30}', '00000000-0000-4000-8000-0000000022b4')$q$,
  '42501', 'permission denied');
SELECT pg_temp.refuses_at('C14b nor edit a line',
  $q$UPDATE public.accounting_period_snapshot_lines SET amount = 0 WHERE period_id = '00000000-0000-4000-8000-000000002211'$q$,
  '42501', 'permission denied');
RESET ROLE;
SELECT pg_temp.refuses_at('C15 the owner cannot edit a snapshot',
  $q$UPDATE public.accounting_period_snapshots SET closing_balance = 0 WHERE period_id = '00000000-0000-4000-8000-000000002211'$q$,
  '23001', 'written only by close_accounting_period()');
SELECT pg_temp.refuses_at('C15b nor delete a line',
  $q$DELETE FROM public.accounting_period_snapshot_lines WHERE period_id = '00000000-0000-4000-8000-000000002211'$q$,
  '23001', 'written only by close_accounting_period()');
SELECT pg_temp.refuses_at('C15c nor write one',
  $q$INSERT INTO public.accounting_period_snapshot_lines (period_id, tenant_id, section, code, amount)
     VALUES ('00000000-0000-4000-8000-000000002211', '00000000-0000-4000-8000-0000000022a1', 'activity', 'x', 1)$q$,
  '23001', 'written only by close_accounting_period()');


-- ============================================================ F the freeze
SET ROLE tally_app;
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000022b1', true);
SELECT pg_temp.refuses_at('F1 a ledger row dated in the closed period',
  $q$INSERT INTO public.account_ledger (tenant_id, customer_id, transaction_date, transaction_type, description, amount)
     VALUES ('00000000-0000-4000-8000-0000000022a1', '00000000-0000-4000-8000-0000000022c1', DATE '2026-01-15', 'adjustment', 'late', 1)$q$,
  '23514', 'a closed period is frozen');
SELECT pg_temp.refuses_at('F1b and one dated before the first period, once it is closed',
  $q$INSERT INTO public.account_ledger (tenant_id, customer_id, transaction_date, transaction_type, description, amount)
     VALUES ('00000000-0000-4000-8000-0000000022a1', '00000000-0000-4000-8000-0000000022c1', DATE '2025-06-30', 'adjustment', 'history', 1)$q$,
  '23514', 'a closed period is frozen');
SELECT pg_temp.admits('F1c a row dated the day after posts',
  $q$INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount)
     VALUES ('00000000-0000-4000-8000-0000000022e6', '00000000-0000-4000-8000-0000000022a1', '00000000-0000-4000-8000-0000000022c1', DATE '2026-02-01', 'adjustment', 'Feb adj', 0.00)$q$);
SELECT pg_temp.refuses_at('F2 a payment dated in the closed period',
  $q$INSERT INTO public.payments (tenant_id, payment_number, customer_id, payment_date, amount, payment_method, effective_date, effective_date_method)
     VALUES ('00000000-0000-4000-8000-0000000022a1', 'B22-PX', '00000000-0000-4000-8000-0000000022c1', DATE '2026-01-30', 5, 'check', DATE '2026-01-30', 'other')$q$,
  '23514', 'a closed period is frozen');
SELECT pg_temp.admits('F2b a payment dated after posts',
  $q$INSERT INTO public.payments (tenant_id, payment_number, customer_id, payment_date, amount, payment_method, effective_date, effective_date_method)
     VALUES ('00000000-0000-4000-8000-0000000022a1', 'B22-P2', '00000000-0000-4000-8000-0000000022c1', DATE '2026-02-03', 5, 'check', DATE '2026-02-03', 'other')$q$);
SELECT pg_temp.refuses_at('F2c a payment is not moved out of the closed period',
  $q$UPDATE public.payments SET payment_date = DATE '2026-02-02' WHERE id = '00000000-0000-4000-8000-0000000022f1'$q$,
  '23514', 'a closed period is frozen');
SELECT pg_temp.refuses_at('F2d nor into it',
  $q$UPDATE public.payments SET payment_date = DATE '2026-01-31' WHERE payment_number = 'B22-P2'$q$,
  '23514', 'a closed period is frozen');
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000022b9', true);
SELECT pg_temp.refuses_at('F2e a payment moved to another tenant leaves the closed books it was in',
  $q$UPDATE public.payments SET tenant_id = '00000000-0000-4000-8000-0000000022a2', customer_id = '00000000-0000-4000-8000-0000000022c9',
       payment_date = DATE '2026-02-02' WHERE id = '00000000-0000-4000-8000-0000000022f1'$q$,
  '23514', 'a closed period is frozen');
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000022b1', true);
SELECT pg_temp.refuses_at('F3 a customer credit issued in the closed period',
  $q$INSERT INTO public.customer_credits (tenant_id, customer_id, origin_type, original_amount, remaining_amount, issued_date)
     VALUES ('00000000-0000-4000-8000-0000000022a1', '00000000-0000-4000-8000-0000000022c1', 'goodwill', 5, 5, DATE '2026-01-31')$q$,
  '23514', 'a closed period is frozen');
SELECT pg_temp.admits('F3b and one issued after',
  $q$INSERT INTO public.customer_credits (tenant_id, customer_id, origin_type, original_amount, remaining_amount, issued_date)
     VALUES ('00000000-0000-4000-8000-0000000022a1', '00000000-0000-4000-8000-0000000022c1', 'goodwill', 5, 5, DATE '2026-02-01')$q$);
RESET ROLE;
SELECT pg_temp.refuses_at('F4 the owner is frozen out too',
  $q$INSERT INTO public.account_ledger (tenant_id, customer_id, transaction_date, transaction_type, description, amount)
     VALUES ('00000000-0000-4000-8000-0000000022a1', '00000000-0000-4000-8000-0000000022c1', DATE '2026-01-31', 'adjustment', 'owner', 1)$q$,
  '23514', 'a closed period is frozen');
SET ROLE tally_app;
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000022b2', true);
SELECT pg_temp.admits('F5 another tenant''s books are its own: T2 still posts in January',
  $q$INSERT INTO public.account_ledger (tenant_id, customer_id, transaction_date, transaction_type, description, amount)
     VALUES ('00000000-0000-4000-8000-0000000022a2', '00000000-0000-4000-8000-0000000022c9', DATE '2026-01-15', 'adjustment', 'T2', 1)$q$);
RESET ROLE;


-- ===================================================== R write-off recovery
SET ROLE tally_app;
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000022b1', true);
SELECT pg_temp.refuses_at('R1 a recovery names its write-off, with a reason',
  $q$INSERT INTO public.account_ledger (tenant_id, customer_id, transaction_date, transaction_type, description, amount)
     VALUES ('00000000-0000-4000-8000-0000000022a1', '00000000-0000-4000-8000-0000000022c3', DATE '2026-02-10', 'write_off_recovery', 'r', 10)$q$,
  '23514', 'account_ledger_recovery_lineage_check');
SELECT pg_temp.refuses_at('R1b the reason is not blank',
  $q$INSERT INTO public.account_ledger (tenant_id, customer_id, transaction_date, transaction_type, description, amount, reverses_ledger_entry_id, reversal_reason)
     VALUES ('00000000-0000-4000-8000-0000000022a1', '00000000-0000-4000-8000-0000000022c3', DATE '2026-02-10', 'write_off_recovery', 'r', 10, '00000000-0000-4000-8000-0000000022e4', ' ')$q$,
  '23514', 'account_ledger_recovery_lineage_check');
SELECT pg_temp.refuses_at('R2 it names a write_off, not a charge',
  $q$INSERT INTO public.account_ledger (tenant_id, customer_id, transaction_date, transaction_type, description, amount, reverses_ledger_entry_id, reversal_reason)
     VALUES ('00000000-0000-4000-8000-0000000022a1', '00000000-0000-4000-8000-0000000022c1', DATE '2026-02-10', 'write_off_recovery', 'r', 10, '00000000-0000-4000-8000-0000000022e2', 'paid')$q$,
  '23503', 'names a write_off entry');
SELECT pg_temp.refuses_at('R3 of its own customer',
  $q$INSERT INTO public.account_ledger (tenant_id, customer_id, transaction_date, transaction_type, description, amount, reverses_ledger_entry_id, reversal_reason)
     VALUES ('00000000-0000-4000-8000-0000000022a1', '00000000-0000-4000-8000-0000000022c1', DATE '2026-02-10', 'write_off_recovery', 'r', 10, '00000000-0000-4000-8000-0000000022e4', 'paid')$q$,
  '23503', 'names a write_off entry');
SELECT pg_temp.refuses_at('R4 with the opposite sign',
  $q$INSERT INTO public.account_ledger (tenant_id, customer_id, transaction_date, transaction_type, description, amount, reverses_ledger_entry_id, reversal_reason)
     VALUES ('00000000-0000-4000-8000-0000000022a1', '00000000-0000-4000-8000-0000000022c3', DATE '2026-02-10', 'write_off_recovery', 'r', -10, '00000000-0000-4000-8000-0000000022e4', 'paid')$q$,
  '23514', 'opposite sign');
SELECT pg_temp.admits('R5 a recovery of 30 of the 50',
  $q$INSERT INTO public.account_ledger (tenant_id, customer_id, transaction_date, transaction_type, description, amount, reverses_ledger_entry_id, reversal_reason)
     VALUES ('00000000-0000-4000-8000-0000000022a1', '00000000-0000-4000-8000-0000000022c3', DATE '2026-02-10', 'write_off_recovery', 'r', 30, '00000000-0000-4000-8000-0000000022e4', 'agency paid')$q$);
SELECT pg_temp.refuses_at('R6 recoveries never exceed the write-off',
  $q$INSERT INTO public.account_ledger (tenant_id, customer_id, transaction_date, transaction_type, description, amount, reverses_ledger_entry_id, reversal_reason)
     VALUES ('00000000-0000-4000-8000-0000000022a1', '00000000-0000-4000-8000-0000000022c3', DATE '2026-02-11', 'write_off_recovery', 'r', 20.01, '00000000-0000-4000-8000-0000000022e4', 'more')$q$,
  '23514', 'R-02 cap');
SELECT pg_temp.admits('R6b up to the whole of it',
  $q$INSERT INTO public.account_ledger (tenant_id, customer_id, transaction_date, transaction_type, description, amount, reverses_ledger_entry_id, reversal_reason)
     VALUES ('00000000-0000-4000-8000-0000000022a1', '00000000-0000-4000-8000-0000000022c3', DATE '2026-02-11', 'write_off_recovery', 'r', 20, '00000000-0000-4000-8000-0000000022e4', 'rest')$q$);
SELECT pg_temp.refuses_at('R6c and not a cent more',
  $q$INSERT INTO public.account_ledger (tenant_id, customer_id, transaction_date, transaction_type, description, amount, reverses_ledger_entry_id, reversal_reason)
     VALUES ('00000000-0000-4000-8000-0000000022a1', '00000000-0000-4000-8000-0000000022c3', DATE '2026-02-12', 'write_off_recovery', 'r', 0.01, '00000000-0000-4000-8000-0000000022e4', 'x')$q$,
  '23514', 'R-02 cap');
SELECT pg_temp.refuses_at('R7 a row that names a write-off is its recovery: an adjustment cannot reinstate it outside the cap',
  $q$INSERT INTO public.account_ledger (tenant_id, customer_id, transaction_date, transaction_type, description, amount, reverses_ledger_entry_id, reversal_reason)
     VALUES ('00000000-0000-4000-8000-0000000022a1', '00000000-0000-4000-8000-0000000022c3', DATE '2026-02-12', 'adjustment', 'r', 100, '00000000-0000-4000-8000-0000000022e4', 'reinstated')$q$,
  '23514', 'only a write_off_recovery names a write-off');
SELECT pg_temp.refuses_at('R8 a reversal chain never loops (two rows of one statement naming each other)',
  $q$INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reverses_ledger_entry_id, reversal_reason) VALUES
     ('00000000-0000-4000-8000-0000000022ea', '00000000-0000-4000-8000-0000000022a1', '00000000-0000-4000-8000-0000000022c3', DATE '2026-02-12', 'adjustment', 'a', 100, '00000000-0000-4000-8000-0000000022eb', 'loop'),
     ('00000000-0000-4000-8000-0000000022eb', '00000000-0000-4000-8000-0000000022a1', '00000000-0000-4000-8000-0000000022c3', DATE '2026-02-12', 'adjustment', 'b', -40, '00000000-0000-4000-8000-0000000022ea', 'loop')$q$,
  '23514', 'returns to itself');
-- r3 (Codex B1, Opus B1, Fable S1): the rule sees the whole statement, and
-- the cap is on the net of the write-off's tree. C5 is written off 100.
SELECT pg_temp.refuses_at('R9 a row naming a write-off listed after it in the same statement is still caught',
  $q$INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reverses_ledger_entry_id, reversal_reason) VALUES
     ('00000000-0000-4000-8000-000000002250', '00000000-0000-4000-8000-0000000022a1', '00000000-0000-4000-8000-0000000022c5', DATE '2026-02-14', 'adjustment', 'reinstated', 500, '00000000-0000-4000-8000-000000002251', 'x'),
     ('00000000-0000-4000-8000-000000002251', '00000000-0000-4000-8000-0000000022a1', '00000000-0000-4000-8000-0000000022c5', DATE '2026-02-13', 'write_off', 'C5 written off', -100, NULL, NULL)$q$,
  '23514', 'only a write_off_recovery names a write-off');
SELECT pg_temp.refuses_at('R9b and in a writable CTE, the adjustment first',
  $q$WITH a AS (INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reverses_ledger_entry_id, reversal_reason)
                VALUES ('00000000-0000-4000-8000-000000002250', '00000000-0000-4000-8000-0000000022a1', '00000000-0000-4000-8000-0000000022c5', DATE '2026-02-14', 'adjustment', 'reinstated', 500, '00000000-0000-4000-8000-000000002251', 'x') RETURNING 1),
          w AS (INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reverses_ledger_entry_id, reversal_reason)
                VALUES ('00000000-0000-4000-8000-000000002251', '00000000-0000-4000-8000-0000000022a1', '00000000-0000-4000-8000-0000000022c5', DATE '2026-02-13', 'write_off', 'C5 written off', -100, NULL, NULL) RETURNING 1)
     SELECT (SELECT count(*) FROM a) + (SELECT count(*) FROM w)$q$,
  '23514', 'only a write_off_recovery names a write-off');
SELECT pg_temp.admits('R9c a recovery listed before its write-off in one statement is a recovery (40 of 100)',
  $q$INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reverses_ledger_entry_id, reversal_reason) VALUES
     ('00000000-0000-4000-8000-000000002252', '00000000-0000-4000-8000-0000000022a1', '00000000-0000-4000-8000-0000000022c5', DATE '2026-02-14', 'write_off_recovery', 'agency paid', 40, '00000000-0000-4000-8000-000000002251', 'agency'),
     ('00000000-0000-4000-8000-000000002251', '00000000-0000-4000-8000-0000000022a1', '00000000-0000-4000-8000-0000000022c5', DATE '2026-02-13', 'write_off', 'C5 written off', -100, NULL, NULL)$q$);
SELECT pg_temp.refuses_at('R10 a row naming the recovery is netted into the write-off: +70 would make 110 of 100',
  $q$INSERT INTO public.account_ledger (tenant_id, customer_id, transaction_date, transaction_type, description, amount, reverses_ledger_entry_id, reversal_reason)
     VALUES ('00000000-0000-4000-8000-0000000022a1', '00000000-0000-4000-8000-0000000022c5', DATE '2026-02-15', 'adjustment', 'more', 70, '00000000-0000-4000-8000-000000002252', 'x')$q$,
  '23514', 'R-02 cap');
SELECT pg_temp.refuses_at('R10b nor below nothing recovered: -50 would make -10',
  $q$INSERT INTO public.account_ledger (tenant_id, customer_id, transaction_date, transaction_type, description, amount, reverses_ledger_entry_id, reversal_reason)
     VALUES ('00000000-0000-4000-8000-0000000022a1', '00000000-0000-4000-8000-0000000022c5', DATE '2026-02-15', 'adjustment', 'less', -50, '00000000-0000-4000-8000-000000002252', 'x')$q$,
  '23514', 'R-02 cap');
SELECT pg_temp.admits('R10c a recovery posted in error is reversed (net 0)',
  $q$INSERT INTO public.account_ledger (tenant_id, customer_id, transaction_date, transaction_type, description, amount, reverses_ledger_entry_id, reversal_reason)
     VALUES ('00000000-0000-4000-8000-0000000022a1', '00000000-0000-4000-8000-0000000022c5', DATE '2026-02-15', 'adjustment', 'recovery in error', -40, '00000000-0000-4000-8000-000000002252', 'bounced')$q$);
SELECT pg_temp.admits('R10d and the cap is free again: the whole 100 is recovered',
  $q$INSERT INTO public.account_ledger (tenant_id, customer_id, transaction_date, transaction_type, description, amount, reverses_ledger_entry_id, reversal_reason)
     VALUES ('00000000-0000-4000-8000-0000000022a1', '00000000-0000-4000-8000-0000000022c5', DATE '2026-02-16', 'write_off_recovery', 'paid in full', 100, '00000000-0000-4000-8000-000000002251', 'paid')$q$);
SELECT pg_temp.refuses_at('R10e and not a cent more',
  $q$INSERT INTO public.account_ledger (tenant_id, customer_id, transaction_date, transaction_type, description, amount, reverses_ledger_entry_id, reversal_reason)
     VALUES ('00000000-0000-4000-8000-0000000022a1', '00000000-0000-4000-8000-0000000022c5', DATE '2026-02-16', 'write_off_recovery', 'x', 0.01, '00000000-0000-4000-8000-000000002251', 'x')$q$,
  '23514', 'R-02 cap');
SELECT pg_temp.refuses_at('R10f another customer''s row naming into the tree stands alone: with it in, C5''s cap still nets 99 of 100 (rolled back by a sentinel)',
  $q$DO $d$ BEGIN
     INSERT INTO public.account_ledger (tenant_id, customer_id, transaction_date, transaction_type, description, amount, reverses_ledger_entry_id, reversal_reason)
     VALUES ('00000000-0000-4000-8000-0000000022a1', '00000000-0000-4000-8000-0000000022c1', DATE '2026-02-16', 'adjustment', 'C1 row', 5, '00000000-0000-4000-8000-000000002252', 'x');
     -- a C5 row runs C5's cap over the tree that now holds the C1 row: 100 - 1 = 99, not 104
     INSERT INTO public.account_ledger (tenant_id, customer_id, transaction_date, transaction_type, description, amount, reverses_ledger_entry_id, reversal_reason)
     VALUES ('00000000-0000-4000-8000-0000000022a1', '00000000-0000-4000-8000-0000000022c5', DATE '2026-02-16', 'adjustment', 'C5 row', -1, '00000000-0000-4000-8000-000000002252', 'x');
     RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'R10f sentinel: admitted';
   END $d$$q$,
  'P0001', 'R10f sentinel');
-- r3 (mutation M57 hung the run): each walk step is an index lookup, not a
-- scan of the customer's ledger. A 300-deep tree in one statement is quick.
-- A statement timeout escapes WHEN OTHERS, so this check names it.
SET LOCAL statement_timeout = '30s';
DO $d$ BEGIN
  BEGIN
    INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reverses_ledger_entry_id, reversal_reason)
    SELECT ('00000000-0000-4000-9023-' || lpad(i::text, 12, '0'))::uuid, '00000000-0000-4000-8000-0000000022a1', '00000000-0000-4000-8000-0000000022c5', DATE '2026-02-17',
           CASE WHEN i = 0 THEN 'write_off' WHEN i = 1 THEN 'write_off_recovery' ELSE 'adjustment' END, 'deep',
           CASE WHEN i = 0 THEN -1000 WHEN i % 2 = 1 THEN 1 ELSE -1 END,
           CASE WHEN i = 0 THEN NULL ELSE ('00000000-0000-4000-9023-' || lpad((i - 1)::text, 12, '0'))::uuid END,
           CASE WHEN i = 0 THEN NULL ELSE 'deep' END
      FROM generate_series(0, 300) i;
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'R10g sentinel';
  EXCEPTION
    WHEN query_canceled THEN
      RAISE NOTICE 'CAUGHT SQLSTATE=% message=%', SQLSTATE, SQLERRM;
      RAISE EXCEPTION 'FAIL R10g: a 300-deep tree did not finish within 30 s';
    WHEN OTHERS THEN
      RAISE NOTICE 'CAUGHT SQLSTATE=% message=%', SQLSTATE, SQLERRM;
      IF SQLERRM <> 'R10g sentinel' THEN
        RAISE EXCEPTION 'FAIL R10g: refused with % (%)', SQLSTATE, SQLERRM;
      END IF;
  END;
  RAISE NOTICE 'PASS R10g a 300-deep tree under one write-off, in one statement, is admitted within 30 s (rolled back)';
END $d$;
RESET statement_timeout;
SELECT pg_temp.refuses_at('R11 a chain that does not reach an original within 1000 entries is refused (a ring of 1001)',
  $q$INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reverses_ledger_entry_id, reversal_reason)
     SELECT ('00000000-0000-4000-9022-' || lpad(i::text, 12, '0'))::uuid, '00000000-0000-4000-8000-0000000022a1', '00000000-0000-4000-8000-0000000022c5', DATE '2026-02-17', 'adjustment', 'ring', 1,
            ('00000000-0000-4000-9022-' || lpad((i % 1001 + 1)::text, 12, '0'))::uuid, 'ring'
       FROM generate_series(1, 1001) i$q$,
  '23514', 'does not reach an original');
-- r4 (Opus B1): aging nets the tree at a date, so the cap holds at every date.
SELECT pg_temp.refuses_at('R12 a later-dated reversal makes no room for an earlier-dated recovery: on Feb 20 the tree would net 200 of 100',
  $q$DO $d$ BEGIN
     INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reverses_ledger_entry_id, reversal_reason) VALUES ('00000000-0000-4000-8000-000000002261', '00000000-0000-4000-8000-0000000022a1', '00000000-0000-4000-8000-0000000022c5', DATE '2026-02-01', 'write_off', 'written off', -100, NULL, NULL);
     INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reverses_ledger_entry_id, reversal_reason) VALUES ('00000000-0000-4000-8000-000000002262', '00000000-0000-4000-8000-0000000022a1', '00000000-0000-4000-8000-0000000022c5', DATE '2026-02-10', 'write_off_recovery', 'agency', 100, '00000000-0000-4000-8000-000000002261', 'agency');
     INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reverses_ledger_entry_id, reversal_reason) VALUES (gen_random_uuid(), '00000000-0000-4000-8000-0000000022a1', '00000000-0000-4000-8000-0000000022c5', DATE '2026-03-05', 'adjustment', 'bounced', -100, '00000000-0000-4000-8000-000000002262', 'bounced');
     INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reverses_ledger_entry_id, reversal_reason) VALUES (gen_random_uuid(), '00000000-0000-4000-8000-0000000022a1', '00000000-0000-4000-8000-0000000022c5', DATE '2026-02-20', 'write_off_recovery', 'again', 100, '00000000-0000-4000-8000-000000002261', 'again');
   END $d$$q$,
  '23514', 'on 2026-02-20 the rows netted');
SELECT pg_temp.refuses_at('R12b a recovery is dated on or after its write-off',
  $q$DO $d$ BEGIN
     INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reverses_ledger_entry_id, reversal_reason) VALUES ('00000000-0000-4000-8000-000000002261', '00000000-0000-4000-8000-0000000022a1', '00000000-0000-4000-8000-0000000022c5', DATE '2026-02-25', 'write_off', 'written off', -40, NULL, NULL);
     INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reverses_ledger_entry_id, reversal_reason) VALUES (gen_random_uuid(), '00000000-0000-4000-8000-0000000022a1', '00000000-0000-4000-8000-0000000022c5', DATE '2026-02-03', 'write_off_recovery', 'early', 40, '00000000-0000-4000-8000-000000002261', 'early');
   END $d$$q$,
  '23514', 'dated on or after the entry it names');
SELECT pg_temp.refuses_at('R12c and any row under it on or after the entry it names (a reversal of the recovery dated before it)',
  $q$DO $d$ BEGIN
     INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reverses_ledger_entry_id, reversal_reason) VALUES ('00000000-0000-4000-8000-000000002261', '00000000-0000-4000-8000-0000000022a1', '00000000-0000-4000-8000-0000000022c5', DATE '2026-02-01', 'write_off', 'written off', -100, NULL, NULL);
     INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reverses_ledger_entry_id, reversal_reason) VALUES ('00000000-0000-4000-8000-000000002262', '00000000-0000-4000-8000-0000000022a1', '00000000-0000-4000-8000-0000000022c5', DATE '2026-02-10', 'write_off_recovery', 'agency', 100, '00000000-0000-4000-8000-000000002261', 'agency');
     INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reverses_ledger_entry_id, reversal_reason) VALUES (gen_random_uuid(), '00000000-0000-4000-8000-0000000022a1', '00000000-0000-4000-8000-0000000022c5', DATE '2026-02-09', 'adjustment', 'bounced', -100, '00000000-0000-4000-8000-000000002262', 'bounced');
   END $d$$q$,
  '23514', 'dated on or after the entry it names');
SELECT pg_temp.admits('R12d the bounced recovery, then a new one, both dated in order: net 100 at every date (rolled back)',
  $q$DO $d$ BEGIN
     INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reverses_ledger_entry_id, reversal_reason) VALUES ('00000000-0000-4000-8000-000000002261', '00000000-0000-4000-8000-0000000022a1', '00000000-0000-4000-8000-0000000022c5', DATE '2026-02-01', 'write_off', 'written off', -100, NULL, NULL);
     INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reverses_ledger_entry_id, reversal_reason) VALUES ('00000000-0000-4000-8000-000000002262', '00000000-0000-4000-8000-0000000022a1', '00000000-0000-4000-8000-0000000022c5', DATE '2026-02-10', 'write_off_recovery', 'agency', 100, '00000000-0000-4000-8000-000000002261', 'agency');
     INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reverses_ledger_entry_id, reversal_reason) VALUES (gen_random_uuid(), '00000000-0000-4000-8000-0000000022a1', '00000000-0000-4000-8000-0000000022c5', DATE '2026-02-12', 'adjustment', 'bounced', -100, '00000000-0000-4000-8000-000000002262', 'bounced');
     INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reverses_ledger_entry_id, reversal_reason) VALUES (gen_random_uuid(), '00000000-0000-4000-8000-0000000022a1', '00000000-0000-4000-8000-0000000022c5', DATE '2026-02-20', 'write_off_recovery', 'again', 100, '00000000-0000-4000-8000-000000002261', 'again');
     RAISE EXCEPTION 'R12d sentinel';
   EXCEPTION WHEN raise_exception THEN
     IF SQLERRM <> 'R12d sentinel' THEN RAISE; END IF;
   END $d$$q$);
RESET ROLE;
-- r4: aging nets the tree as recorded (created_at, the transaction's start);
-- a row recorded before one already in the tree is a writer that began
-- earlier and posted later, and retries. The owner's created_at is kept.
SELECT pg_temp.refuses_at('R12e a row recorded before a row already in its tree is refused for retry (40001)',
  $q$DO $d$ BEGIN
     INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, created_at) VALUES
       ('00000000-0000-4000-8000-000000002261', '00000000-0000-4000-8000-0000000022a1', '00000000-0000-4000-8000-0000000022c5', DATE '2026-02-01', 'write_off', 'written off', -100, now());
     INSERT INTO public.account_ledger (tenant_id, customer_id, transaction_date, transaction_type, description, amount, reverses_ledger_entry_id, reversal_reason, created_at) VALUES
       ('00000000-0000-4000-8000-0000000022a1', '00000000-0000-4000-8000-0000000022c5', DATE '2026-02-10', 'write_off_recovery', 'begun earlier', 100, '00000000-0000-4000-8000-000000002261', 'x', now() - interval '1 minute');
   END $d$$q$,
  '40001', 'retry it');
SET ROLE tally_app;
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000022b1', true);
RESET ROLE;


-- ===================================================== W receivables aging
SET ROLE tally_app;
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000022b1', true);
SELECT pg_temp.refuses_at('W1 every coordinate is required',
  $q$SELECT * FROM public.receivables_aging_as_of('00000000-0000-4000-8000-0000000022a1', DATE '2026-03-31', NULL)$q$,
  '22004', 'all required');
SELECT pg_temp.refuses_at('W1b another tenant is not visible',
  $q$SELECT * FROM public.receivables_aging_as_of('00000000-0000-4000-8000-0000000022a2', DATE '2026-03-31', clock_timestamp())$q$,
  'P0002', 'not visible');
SELECT pg_temp.refuses_at('W1d explicit edges are a valid list',
  $q$SELECT * FROM public.receivables_aging_as_of('00000000-0000-4000-8000-0000000022a1', DATE '2026-03-31', clock_timestamp(), '[0:1]={90,30}')$q$,
  '22023', 'not a list of bucket edges');
SELECT pg_temp.refuses_at('W1c before the setting''s history there is no aging',
  $q$SELECT * FROM public.receivables_aging_as_of('00000000-0000-4000-8000-0000000022a1', DATE '2026-03-31', now() - interval '1 second')$q$,
  'P0002', 'no aging bucket setting');
-- C2: Dec 1 charge 80 and a Mar 1 charge 40 reversed by an adjustment that
-- names it: the netted Mar charge is gone, the 80 of December is aged.
INSERT INTO public.account_ledger (id, tenant_id, customer_id, location_id, transaction_date, transaction_type, description, amount) VALUES
  ('00000000-0000-4000-8000-0000000022e7', '00000000-0000-4000-8000-0000000022a1', '00000000-0000-4000-8000-0000000022c2', '00000000-0000-4000-8000-0000000022d1', DATE '2026-03-01', 'charge', 'C2 Mar', 40.00);
INSERT INTO public.account_ledger (tenant_id, customer_id, transaction_date, transaction_type, description, amount, reverses_ledger_entry_id, reversal_reason) VALUES
  ('00000000-0000-4000-8000-0000000022a1', '00000000-0000-4000-8000-0000000022c2', DATE '2026-03-02', 'adjustment', 'C2 Mar charge cancelled', -40.00, '00000000-0000-4000-8000-0000000022e7', 'billed in error');
-- C1: owes 40 of Jan 5 after the 60 paid; a Feb 10 charge of 50; a Feb 20
-- payment of 70. Balance 20: the newest debt is what is left (Feb 10).
INSERT INTO public.account_ledger (tenant_id, customer_id, transaction_date, transaction_type, description, amount) VALUES
  ('00000000-0000-4000-8000-0000000022a1', '00000000-0000-4000-8000-0000000022c1', DATE '2026-02-10', 'charge', 'C1 Feb', 50.00),
  ('00000000-0000-4000-8000-0000000022a1', '00000000-0000-4000-8000-0000000022c1', DATE '2026-02-20', 'payment', 'C1 pays', -70.00);
RESET ROLE;
SELECT set_config('bat22.before_status', clock_timestamp()::text, true);
UPDATE public.customers SET status = 'final_billed', status_reason = 'moved out'
 WHERE id = '00000000-0000-4000-8000-0000000022c2';
CREATE TEMP TABLE aging ON COMMIT DROP AS
  SELECT * FROM public.receivables_aging_as_of('00000000-0000-4000-8000-0000000022a1', DATE '2026-03-31', clock_timestamp());
SELECT pg_temp.ok('W2 the balance is aged newest first: C1''s 21 is the February charge (49 days, 31-60)',
  (SELECT jsonb_agg(jsonb_build_array(balance, bucket_index, bucket_from_days, bucket_to_days, amount))
     FROM aging WHERE customer_number = 'B22-C1') = '[[21.00, 1, 31, 60, 21.00]]'::jsonb);
SELECT pg_temp.ok('W3 an entry is netted with the reversal that names it: C2 owes December''s 80 (120 days) and the 5 late fee (59 days)',
  (SELECT jsonb_agg(jsonb_build_array(bucket_index, amount) ORDER BY bucket_index)
     FROM aging WHERE customer_number = 'B22-C2') = '[[1, 5.00], [3, 80.00]]'::jsonb);
SELECT pg_temp.ok('W4 the customer''s status is on the row (D-3): C2 is final-billed',
  (SELECT bool_and(customer_status = 'final_billed') FROM aging WHERE customer_number = 'B22-C2')
  AND (SELECT bool_and(customer_status = 'active') FROM aging WHERE customer_number = 'B22-C1'));
SELECT pg_temp.ok('W4b at an instant before the change, C2 was active',
  (SELECT bool_and(customer_status = 'active')
     FROM public.receivables_aging_as_of('00000000-0000-4000-8000-0000000022a1', DATE '2026-03-31', current_setting('bat22.before_status')::timestamptz)
    WHERE customer_number = 'B22-C2'));
SELECT pg_temp.ok('W5 the last located entry gives the location',
  (SELECT bool_and(last_location_id = '00000000-0000-4000-8000-0000000022d1') FROM aging WHERE customer_number IN ('B22-C1', 'B22-C2')));
SELECT pg_temp.ok('W6 a zero balance is omitted: C3 (written off 50, recovered 50)',
  NOT EXISTS (SELECT 1 FROM aging WHERE customer_number = 'B22-C3'));
INSERT INTO public.account_ledger (tenant_id, customer_id, transaction_date, transaction_type, description, amount) VALUES
  ('00000000-0000-4000-8000-0000000022a1', '00000000-0000-4000-8000-0000000022c3', DATE '2026-03-05', 'payment', 'C3 overpays', -25.00);
-- A row the owner records "later": invisible at an earlier recorded instant.
INSERT INTO public.account_ledger (tenant_id, customer_id, transaction_date, transaction_type, description, amount, created_at) VALUES
  ('00000000-0000-4000-8000-0000000022a1', '00000000-0000-4000-8000-0000000022c1', DATE '2026-03-10', 'charge', 'C1 later', 9.00, now() + interval '1 day');
SELECT pg_temp.ok('W7 a credit balance is one row with no bucket',
  (SELECT jsonb_agg(jsonb_build_array(balance, bucket_index, amount))
     FROM public.receivables_aging_as_of('00000000-0000-4000-8000-0000000022a1', DATE '2026-03-31', clock_timestamp())
    WHERE customer_number = 'B22-C3') = '[[-25.00, null, -25.00]]'::jsonb);
SELECT pg_temp.ok('W8 the recorded coordinate: a row recorded after it is not seen, then is',
  (SELECT sum(amount) FROM public.receivables_aging_as_of('00000000-0000-4000-8000-0000000022a1', DATE '2026-03-31', clock_timestamp())
    WHERE customer_number = 'B22-C1') = 21.00
  AND (SELECT sum(amount) FROM public.receivables_aging_as_of('00000000-0000-4000-8000-0000000022a1', DATE '2026-03-31', now() + interval '2 days')
    WHERE customer_number = 'B22-C1') = 30.00);
SELECT pg_temp.ok('W9 the date coordinate: on February 15, C1 owes 41 of January 5 (41 days) and 50 of February 10 (5 days)',
  (SELECT jsonb_agg(jsonb_build_array(bucket_index, amount) ORDER BY bucket_index)
     FROM public.receivables_aging_as_of('00000000-0000-4000-8000-0000000022a1', DATE '2026-02-15', clock_timestamp())
    WHERE customer_number = 'B22-C1') = '[[0, 50.00], [1, 41.00]]'::jsonb);
-- W2: the bucket setting.
SELECT pg_temp.refuses_at('W10 bucket edges increase', $q$UPDATE public.tenants SET receivables_aging_bucket_days = '{60,30}' WHERE id = '00000000-0000-4000-8000-0000000022a1'$q$,
  '23514', 'tenants_receivables_aging_bucket_days_check');
SELECT pg_temp.refuses_at('W10b are positive', $q$UPDATE public.tenants SET receivables_aging_bucket_days = '{0,30}' WHERE id = '00000000-0000-4000-8000-0000000022a1'$q$,
  '23514', 'tenants_receivables_aging_bucket_days_check');
SELECT pg_temp.refuses_at('W10c are not empty', $q$UPDATE public.tenants SET receivables_aging_bucket_days = '{}' WHERE id = '00000000-0000-4000-8000-0000000022a1'$q$,
  '23514', 'tenants_receivables_aging_bucket_days_check');
SELECT pg_temp.refuses_at('W10d hold no NULL', $q$UPDATE public.tenants SET receivables_aging_bucket_days = '{30,NULL}' WHERE id = '00000000-0000-4000-8000-0000000022a1'$q$,
  '23514', 'tenants_receivables_aging_bucket_days_check');
SELECT pg_temp.refuses_at('W10e are one-based (a [0:1] array hides a decreasing pair)', $q$UPDATE public.tenants SET receivables_aging_bucket_days = '[0:1]={90,30}' WHERE id = '00000000-0000-4000-8000-0000000022a1'$q$,
  '23514', 'tenants_receivables_aging_bucket_days_check');
SET ROLE tally_app;
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000022b4', true);
SELECT pg_temp.refuses_at('W10f a recorded value is a valid list, a direct history row included',
  $q$INSERT INTO public.tenant_configuration_history (tenant_id, config_key, new_value, effective_from, change_source)
     VALUES ('00000000-0000-4000-8000-0000000022a1', 'receivables_aging_bucket_days', '["abc"]', now() - interval '1 day', 'manual')$q$,
  '23514', 'tenant_configuration_history_aging_days_check');
SELECT pg_temp.refuses_at('W10g nor a decreasing one',
  $q$INSERT INTO public.tenant_configuration_history (tenant_id, config_key, new_value, effective_from, change_source)
     VALUES ('00000000-0000-4000-8000-0000000022a1', 'receivables_aging_bucket_days', '[90, 30]', now() - interval '1 day', 'manual')$q$,
  '23514', 'tenant_configuration_history_aging_days_check');
RESET ROLE;
UPDATE public.tenants SET receivables_aging_bucket_days = '{15,45}' WHERE id = '00000000-0000-4000-8000-0000000022a1';
SELECT pg_temp.ok('W11 a change is recorded in the configuration history',
  (SELECT new_value FROM public.tenant_configuration_history
    WHERE tenant_id = '00000000-0000-4000-8000-0000000022a1' AND config_key = 'receivables_aging_bucket_days'
    ORDER BY effective_from DESC, seq DESC LIMIT 1) = '[15, 45]'::jsonb);
SELECT pg_temp.ok('W12 aging reads the edges as recorded: C2''s 80 (120 days) and 5 (59 days) are both over 45',
  (SELECT jsonb_agg(jsonb_build_array(bucket_index, bucket_from_days, bucket_to_days, amount) ORDER BY bucket_index)
     FROM public.receivables_aging_as_of('00000000-0000-4000-8000-0000000022a1', DATE '2026-03-31', clock_timestamp())
    WHERE customer_number = 'B22-C2') = '[[2, 46, null, 85.00]]'::jsonb
  AND (SELECT jsonb_agg(jsonb_build_array(bucket_index, bucket_from_days, bucket_to_days, amount) ORDER BY bucket_index)
     FROM public.receivables_aging_as_of('00000000-0000-4000-8000-0000000022a1', DATE '2026-03-31', clock_timestamp())
    WHERE customer_number = 'B22-C1') = '[[2, 46, null, 21.00]]'::jsonb);
SELECT pg_temp.ok('W12b explicit edges age by those edges, whatever is recorded',
  (SELECT jsonb_agg(jsonb_build_array(bucket_index, amount) ORDER BY bucket_index)
     FROM public.receivables_aging_as_of('00000000-0000-4000-8000-0000000022a1', DATE '2026-03-31', clock_timestamp(), '{30,60,90,120}')
    WHERE customer_number = 'B22-C2') = '[[1, 5.00], [3, 80.00]]'::jsonb);


INSERT INTO public.account_ledger (tenant_id, customer_id, transaction_date, transaction_type, description, amount, reverses_ledger_entry_id, reversal_reason) VALUES
  ('00000000-0000-4000-8000-0000000022a1', '00000000-0000-4000-8000-0000000022c1', DATE '2026-03-15', 'adjustment', 'C1 names C2''s charge', -10.00, '00000000-0000-4000-8000-0000000022e1', 'misfiled');
SELECT pg_temp.ok('W13 a reversal is netted only within its customer: C2 still owes December''s 80, C1''s 10 credit is aged balance-forward',
  (SELECT jsonb_agg(jsonb_build_array(bucket_index, amount) ORDER BY bucket_index)
     FROM public.receivables_aging_as_of('00000000-0000-4000-8000-0000000022a1', DATE '2026-03-31', clock_timestamp())
    WHERE customer_number = 'B22-C2') = '[[2, 85.00]]'::jsonb
  AND (SELECT jsonb_agg(jsonb_build_array(balance, bucket_index, amount) ORDER BY bucket_index)
     FROM public.receivables_aging_as_of('00000000-0000-4000-8000-0000000022a1', DATE '2026-03-31', clock_timestamp())
    WHERE customer_number = 'B22-C1') = '[[11.00, 2, 11.00]]'::jsonb);
-- C4: a chain (charge X 60; -20 naming X; +5 naming the -20) and an early-
-- dated reversal (-10 on March 1 naming charge Y of 30 on March 20).
INSERT INTO public.customers (id, tenant_id, customer_number) VALUES
  ('00000000-0000-4000-8000-0000000022c4', '00000000-0000-4000-8000-0000000022a1', 'B22-C4');
INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reverses_ledger_entry_id, reversal_reason) VALUES
  ('00000000-0000-4000-8000-0000000022ec', '00000000-0000-4000-8000-0000000022a1', '00000000-0000-4000-8000-0000000022c4', DATE '2026-03-10', 'charge', 'X', 60.00, NULL, NULL),
  ('00000000-0000-4000-8000-0000000022ed', '00000000-0000-4000-8000-0000000022a1', '00000000-0000-4000-8000-0000000022c4', DATE '2026-03-12', 'adjustment', 'X less 20', -20.00, '00000000-0000-4000-8000-0000000022ec', 'partly'),
  ('00000000-0000-4000-8000-0000000022ee', '00000000-0000-4000-8000-0000000022a1', '00000000-0000-4000-8000-0000000022c4', DATE '2026-03-13', 'adjustment', 'undo 5 of it', 5.00, '00000000-0000-4000-8000-0000000022ed', 'over-credited'),
  ('00000000-0000-4000-8000-0000000022ef', '00000000-0000-4000-8000-0000000022a1', '00000000-0000-4000-8000-0000000022c4', DATE '2026-03-20', 'charge', 'Y', 30.00, NULL, NULL),
  ('00000000-0000-4000-8000-0000000022f9', '00000000-0000-4000-8000-0000000022a1', '00000000-0000-4000-8000-0000000022c4', DATE '2026-03-01', 'adjustment', 'Y less 10, dated early', -10.00, '00000000-0000-4000-8000-0000000022ef', 'agreed');
SELECT pg_temp.ok('W14 a chain nets into its original, and a reversal dated before its original stands alone until the original is in the window',
  (SELECT jsonb_agg(jsonb_build_array(balance, bucket_index, amount) ORDER BY bucket_index)
     FROM public.receivables_aging_as_of('00000000-0000-4000-8000-0000000022a1', DATE '2026-03-15', clock_timestamp())
    WHERE customer_number = 'B22-C4') = '[[35.00, 0, 35.00]]'::jsonb
  AND (SELECT jsonb_agg(jsonb_build_array(balance, bucket_index, amount) ORDER BY bucket_index)
     FROM public.receivables_aging_as_of('00000000-0000-4000-8000-0000000022a1', DATE '2026-03-31', clock_timestamp())
    WHERE customer_number = 'B22-C4') = '[[65.00, 0, 20.00], [65.00, 1, 45.00]]'::jsonb);
SELECT pg_temp.refuses_at('W16 should a loop ever be in the ledger (the loop guard disabled by the owner), aging raises rather than drop it',
  $q$DO $d$ BEGIN
       ALTER TABLE public.account_ledger DISABLE TRIGGER enforce_ledger_lineage_acyclic;
       INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, reverses_ledger_entry_id, reversal_reason) VALUES
         ('00000000-0000-4000-8000-0000000022fa', '00000000-0000-4000-8000-0000000022a1', '00000000-0000-4000-8000-0000000022c4', DATE '2026-03-21', 'adjustment', 'a', 100, '00000000-0000-4000-8000-0000000022fb', 'loop'),
         ('00000000-0000-4000-8000-0000000022fb', '00000000-0000-4000-8000-0000000022a1', '00000000-0000-4000-8000-0000000022c4', DATE '2026-03-21', 'adjustment', 'b', -40, '00000000-0000-4000-8000-0000000022fa', 'loop');
       PERFORM * FROM public.receivables_aging_as_of('00000000-0000-4000-8000-0000000022a1', DATE '2026-03-31', clock_timestamp());
     END $d$$q$,
  '22000', 'reach no original');
SELECT pg_temp.refuses_at('W15 the write-off threshold is a positive number of days, or unset',
  $q$UPDATE public.tenants SET write_off_threshold_days = 0 WHERE id = '00000000-0000-4000-8000-0000000022a1'$q$,
  '23514', 'tenants_write_off_threshold_days_check');
UPDATE public.tenants SET write_off_threshold_days = 180 WHERE id = '00000000-0000-4000-8000-0000000022a1';
SELECT pg_temp.ok('W15b born unset, and recorded when set',
  (SELECT array_agg(new_value ORDER BY effective_from, seq) FROM public.tenant_configuration_history
    WHERE tenant_id = '00000000-0000-4000-8000-0000000022a1' AND config_key = 'write_off_threshold_days') = ARRAY['null'::jsonb, '180'::jsonb]);


-- ========================================================= G GL mapping
INSERT INTO public.places (id, kind_code, state_code, place_code, name, parent_place_id, effective_from, source_note)
SELECT '00000000-0000-4000-8000-0000000022a7', 'municipality', 'TX', 'TX-B22-CITY', 'Battery City', s.id, DATE '2000-01-01', 'battery-22 fixture'
  FROM public.places s WHERE s.kind_code = 'state' AND s.state_code = 'TX';
SET ROLE tally_app;
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000022b1', true);
SELECT pg_temp.admits('G1 a default account (every key a wildcard)',
  $q$INSERT INTO public.gl_account_mappings (id, tenant_id, gl_account, effective_from)
     VALUES ('00000000-0000-4000-8000-000000002231', '00000000-0000-4000-8000-0000000022a1', '1200-AR', DATE '2026-02-01')$q$);
SELECT pg_temp.admits('G1b usage charges',
  $q$INSERT INTO public.gl_account_mappings (id, tenant_id, charge_source, charge_code, gl_account, usoa_code, effective_from)
     VALUES ('00000000-0000-4000-8000-000000002232', '00000000-0000-4000-8000-0000000022a1', 'bill_line', 'usage_charge', '4800', '480', DATE '2026-02-01')$q$);
SELECT pg_temp.admits('G1c residential usage charges',
  $q$INSERT INTO public.gl_account_mappings (id, tenant_id, charge_source, charge_code, customer_class, gl_account, effective_from)
     VALUES ('00000000-0000-4000-8000-000000002233', '00000000-0000-4000-8000-0000000022a1', 'bill_line', 'usage_charge', 'residential', '4800-RES', DATE '2026-02-01')$q$);
SELECT pg_temp.ok('G1d created_by and created_at are the database''s, closed_* empty',
  (SELECT created_by = '00000000-0000-4000-8000-0000000022b1' AND created_at > now() AND created_at <= clock_timestamp() AND closed_at IS NULL
     FROM public.gl_account_mappings WHERE id = '00000000-0000-4000-8000-000000002233'));
SELECT pg_temp.refuses_at('G2 a code from its source''s vocabulary',
  $q$INSERT INTO public.gl_account_mappings (tenant_id, charge_source, charge_code, gl_account, effective_from)
     VALUES ('00000000-0000-4000-8000-0000000022a1', 'adhoc_charge', 'usage_charge', '4000', DATE '2026-02-01')$q$,
  '23514', 'gl_account_mappings_charge_check');
SELECT pg_temp.refuses_at('G2b a source with a code',
  $q$INSERT INTO public.gl_account_mappings (tenant_id, charge_source, gl_account, effective_from)
     VALUES ('00000000-0000-4000-8000-0000000022a1', 'bill_line', '4000', DATE '2026-02-01')$q$,
  '23514', 'gl_account_mappings_charge_pair_check');
SELECT pg_temp.refuses_at('G2c a known customer class',
  $q$INSERT INTO public.gl_account_mappings (tenant_id, customer_class, gl_account, effective_from)
     VALUES ('00000000-0000-4000-8000-0000000022a1', 'residental', '4000', DATE '2026-02-01')$q$,
  '23514', 'gl_account_mappings_customer_class_check');
SELECT pg_temp.refuses_at('G2d an account that is not blank',
  $q$INSERT INTO public.gl_account_mappings (tenant_id, gl_account, effective_from)
     VALUES ('00000000-0000-4000-8000-0000000022a1', ' - ', DATE '2026-02-01')$q$,
  '23514', 'gl_account_mappings_account_check');
SELECT pg_temp.refuses_at('G3 one key, one mapping at a time (wildcards compare equal)',
  $q$INSERT INTO public.gl_account_mappings (tenant_id, gl_account, effective_from)
     VALUES ('00000000-0000-4000-8000-0000000022a1', '1300', DATE '2026-06-01')$q$,
  '23P01', 'gl_account_mappings_no_overlap');
SELECT pg_temp.refuses_at('G4 no mapping in force in a closed period',
  $q$INSERT INTO public.gl_account_mappings (tenant_id, charge_source, charge_code, gl_account, effective_from)
     VALUES ('00000000-0000-4000-8000-0000000022a1', 'ledger_entry', 'payment', '1100', DATE '2026-01-31')$q$,
  '23514', 'closed period''s export');
SELECT pg_temp.ok('G5 the most specific row wins: residential usage',
  public.gl_mapping_as_of('00000000-0000-4000-8000-0000000022a1', 'bill_line', 'usage_charge', 'residential', NULL, NULL, DATE '2026-03-01', clock_timestamp())
    = '00000000-0000-4000-8000-000000002233');
SELECT pg_temp.ok('G5b commercial usage takes the usage row',
  public.gl_mapping_as_of('00000000-0000-4000-8000-0000000022a1', 'bill_line', 'usage_charge', 'commercial', NULL, NULL, DATE '2026-03-01', clock_timestamp())
    = '00000000-0000-4000-8000-000000002232');
SELECT pg_temp.ok('G5c a base charge takes the default',
  public.gl_mapping_as_of('00000000-0000-4000-8000-0000000022a1', 'bill_line', 'base_charge', 'residential', NULL, NULL, DATE '2026-03-01', clock_timestamp())
    = '00000000-0000-4000-8000-000000002231');
SELECT pg_temp.ok('G5d before any mapping is in force: none (the export refuses the line)',
  public.gl_mapping_as_of('00000000-0000-4000-8000-0000000022a1', 'bill_line', 'base_charge', 'residential', NULL, NULL, DATE '2026-01-15', clock_timestamp()) IS NULL);
SELECT pg_temp.admits('G6 usage in Battery City (a key of the same size as residential usage)',
  $q$INSERT INTO public.gl_account_mappings (id, tenant_id, charge_source, charge_code, territory_place_id, gl_account, effective_from)
     VALUES ('00000000-0000-4000-8000-000000002234', '00000000-0000-4000-8000-0000000022a1', 'bill_line', 'usage_charge', '00000000-0000-4000-8000-0000000022a7', '4800-CITY', DATE '2026-02-01')$q$);
SELECT pg_temp.ok('G6b the stated precedence: the customer class outranks the territory',
  pg_temp.try_text($q$SELECT public.gl_mapping_as_of('00000000-0000-4000-8000-0000000022a1', 'bill_line', 'usage_charge', 'residential', '00000000-0000-4000-8000-0000000022a7', NULL, DATE '2026-03-01', clock_timestamp())$q$)
    = '00000000-0000-4000-8000-000000002233'
  AND pg_temp.try_text($q$SELECT public.gl_mapping_as_of('00000000-0000-4000-8000-0000000022a1', 'bill_line', 'usage_charge', 'commercial', '00000000-0000-4000-8000-0000000022a7', NULL, DATE '2026-03-01', clock_timestamp())$q$)
    = '00000000-0000-4000-8000-000000002234');
SELECT pg_temp.ok('G6c a line with no territory matches only wildcards on it',
  public.gl_mapping_as_of('00000000-0000-4000-8000-0000000022a1', 'bill_line', 'usage_charge', 'commercial', NULL, NULL, DATE '2026-03-01', clock_timestamp())
    = '00000000-0000-4000-8000-000000002232');
SELECT pg_temp.refuses_at('G7 a mapping is never edited',
  $q$UPDATE public.gl_account_mappings SET gl_account = '4801' WHERE id = '00000000-0000-4000-8000-000000002232'$q$,
  '23001', 'never edited');
SELECT pg_temp.refuses_at('G7b a close does not reach into a closed period',
  $q$UPDATE public.gl_account_mappings SET effective_to = DATE '2026-01-31' WHERE id = '00000000-0000-4000-8000-000000002232'$q$,
  '23514', 'inside a closed period');
SELECT pg_temp.admits('G7c a close',
  $q$UPDATE public.gl_account_mappings SET effective_to = DATE '2026-03-01' WHERE id = '00000000-0000-4000-8000-000000002232'$q$);
SELECT pg_temp.ok('G7d the close is stamped',
  (SELECT closed_at > created_at AND closed_at <= clock_timestamp() AND closed_by = '00000000-0000-4000-8000-0000000022b1'
     FROM public.gl_account_mappings WHERE id = '00000000-0000-4000-8000-000000002232'));
SELECT pg_temp.refuses_at('G7e and happens once',
  $q$UPDATE public.gl_account_mappings SET effective_to = DATE '2026-04-01' WHERE id = '00000000-0000-4000-8000-000000002232'$q$,
  '23001', 'never edited');
SELECT pg_temp.admits('G7f the successor carries the new account',
  $q$INSERT INTO public.gl_account_mappings (tenant_id, charge_source, charge_code, gl_account, effective_from)
     VALUES ('00000000-0000-4000-8000-0000000022a1', 'bill_line', 'usage_charge', '4801', DATE '2026-03-01')$q$);
SELECT pg_temp.ok('G7g each date takes its own row',
  (SELECT m.gl_account FROM public.gl_account_mappings m
    WHERE m.id = public.gl_mapping_as_of('00000000-0000-4000-8000-0000000022a1', 'bill_line', 'usage_charge', 'commercial', NULL, NULL, DATE '2026-02-28', clock_timestamp())) = '4800'
  AND (SELECT m.gl_account FROM public.gl_account_mappings m
    WHERE m.id = public.gl_mapping_as_of('00000000-0000-4000-8000-0000000022a1', 'bill_line', 'usage_charge', 'commercial', NULL, NULL, DATE '2026-03-01', clock_timestamp())) = '4801');
SELECT pg_temp.refuses_at('G8 the application cannot delete a mapping',
  $q$DELETE FROM public.gl_account_mappings WHERE id = '00000000-0000-4000-8000-000000002231'$q$,
  '42501', 'permission denied');
SELECT pg_temp.refuses_at('G9 the lookup''s coordinates are required',
  $q$SELECT public.gl_mapping_as_of('00000000-0000-4000-8000-0000000022a1', 'bill_line', 'usage_charge', NULL, NULL, NULL, DATE '2026-03-01', NULL)$q$,
  '22004', 'never default to today');
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000022b2', true);
SELECT pg_temp.ok('G10 another tenant sees none of it',
  NOT EXISTS (SELECT 1 FROM public.gl_account_mappings)
  AND public.gl_mapping_as_of('00000000-0000-4000-8000-0000000022a1', 'bill_line', 'usage_charge', 'residential', NULL, NULL, DATE '2026-03-01', clock_timestamp()) IS NULL);
RESET ROLE;
SELECT pg_temp.refuses_at('G8b nor can the owner',
  $q$DELETE FROM public.gl_account_mappings WHERE id = '00000000-0000-4000-8000-000000002231'$q$,
  '23001', 'never deleted');


-- ============================================================ C (part 2)
-- February closes after January; the snapshot's opening is January's close.
SET ROLE tally_app;
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000022b4', true);
SELECT pg_temp.refuses_at('C15d after a close, the next period is the next to close: not March before February',
  $q$SELECT public.close_accounting_period('00000000-0000-4000-8000-000000002214')$q$,
  '23514', 'close in order');
-- r3 (Opus S1): a history row the application writes, dated now, says {1,2};
-- the tenant's own setting is {15,45} (W11). The close ages by the setting.
INSERT INTO public.tenant_configuration_history (tenant_id, config_key, new_value, effective_from, change_source)
VALUES ('00000000-0000-4000-8000-0000000022a1', 'receivables_aging_bucket_days', '[1, 2]', now(), 'manual');
SELECT pg_temp.admits('C16 February closes next', $q$SELECT public.close_accounting_period('00000000-0000-4000-8000-000000002212')$q$);
RESET ROLE;
SELECT pg_temp.ok('C16b the close ages by the tenant''s setting, not by a history row the application wrote',
  (SELECT aging_bucket_days FROM public.accounting_period_snapshots WHERE period_id = '00000000-0000-4000-8000-000000002212') = '{15,45}');
SELECT pg_temp.ok('C17 February opens at January''s closing balance, and the head moves on',
  (SELECT opening_balance FROM public.accounting_period_snapshots WHERE period_id = '00000000-0000-4000-8000-000000002212')
  = (SELECT closing_balance FROM public.accounting_period_snapshots WHERE period_id = '00000000-0000-4000-8000-000000002211')
  AND (SELECT closed_through FROM public.accounting_close_heads WHERE tenant_id = '00000000-0000-4000-8000-0000000022a1') = DATE '2026-02-28'
  AND (SELECT unbilled_revenue IS NULL AND unbilled_revenue_basis IS NULL FROM public.accounting_period_snapshots WHERE period_id = '00000000-0000-4000-8000-000000002212'));
SELECT pg_temp.ok('C18 February''s closing balance is the ledger''s through February 28',
  (SELECT closing_balance FROM public.accounting_period_snapshots WHERE period_id = '00000000-0000-4000-8000-000000002212')
  = (SELECT sum(amount) FROM public.account_ledger WHERE tenant_id = '00000000-0000-4000-8000-0000000022a1' AND transaction_date <= DATE '2026-02-28'));
SET ROLE tally_app;
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000022b4', true);
SELECT pg_temp.refuses_at('C19 a close refuses while a row it would freeze is recorded after its instant (W8''s "later" row, March 10)',
  $q$SELECT public.close_accounting_period('00000000-0000-4000-8000-000000002214')$q$,
  '23514', 'recorded after the close''s instant');
SELECT pg_temp.refuses_at('P9e a closed period is not withdrawn',
  $q$UPDATE public.accounting_periods SET status = 'withdrawn' WHERE id = '00000000-0000-4000-8000-000000002212'$q$,
  '23001', 'never edited');
RESET ROLE;


-- ============================================================ I invariants
SELECT pg_temp.admits('I1 the -22 guards and the seal roles are as defined',
  $q$SELECT public.assert_periods_guard_invariants(), public.assert_seal_role_invariants()$q$);
SELECT pg_temp.ok('I2 close_accounting_period() is a definer owned by tally_close, pinned',
  (SELECT p.prosecdef AND p.proowner = 'tally_close'::regrole AND p.proconfig @> ARRAY['search_path=public, pg_temp']
     FROM pg_proc p WHERE p.oid = 'public.close_accounting_period(uuid,numeric,text)'::regprocedure));
SELECT pg_temp.ok('I3 the application executes the close; the core and PUBLIC do not',
  has_function_privilege('tally_app', 'public.close_accounting_period(uuid,numeric,text)', 'EXECUTE')
  AND NOT has_function_privilege('tally_core', 'public.close_accounting_period(uuid,numeric,text)', 'EXECUTE')
  AND NOT has_function_privilege('public', 'public.close_accounting_period(uuid,numeric,text)', 'EXECUTE'));
SELECT pg_temp.ok('I4 the new tables are under forced row security (their policies: I5)',
  (SELECT bool_and(c.relrowsecurity AND c.relforcerowsecurity) FROM pg_class c
    WHERE c.oid IN ('public.accounting_close_heads'::regclass, 'public.accounting_periods'::regclass, 'public.accounting_period_snapshots'::regclass,
                    'public.accounting_period_snapshot_lines'::regclass, 'public.gl_account_mappings'::regclass)));
SELECT pg_temp.admits('I5 tenant isolation and the core''s invariants hold',
  $q$SELECT public.assert_tenant_isolation_invariants(), public.assert_core_role_invariants()$q$);

ROLLBACK;
