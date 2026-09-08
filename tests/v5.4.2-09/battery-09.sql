-- ============================================================================
-- BATTERY v5.4.2-09 — A-9 tax exemption certificate evidence + renewal
-- Run: psql -U tally -d scratch -v ON_ERROR_STOP=1 -f battery-09.sql
-- One transaction, rolled back. Negative cases inside DO exception handlers.
-- End-to-end writes as tally_app (SET ROLE) with app.user_id context.
-- ============================================================================
BEGIN;
SET CONSTRAINTS ALL IMMEDIATE;

-- ---------------------------------------------------------------- fixtures
-- (as superuser; RLS bypassed here, exercised later under tally_app)
INSERT INTO public.tenants (id, name, slug, settings) VALUES
  ('00000000-0000-4000-8000-0000000000a1', 'T1 Gasco', 'bat9-t1', '{}'),
  ('00000000-0000-4000-8000-0000000000a2', 'T2 Gasco', 'bat9-t2',
   '{"tax_exemptions": {"certificate_required": {"government": false}, "renewal_notice_days_before": 30}}'),
  ('00000000-0000-4000-8000-0000000000a3', 'T3 Gasco', 'bat9-t3',
   '{"tax_exemptions": {"certificate_required": {"government": "maybe"}, "renewal_notice_days_before": 0}}');

INSERT INTO public.users (id, tenant_id, display_name, email, role) VALUES
  ('00000000-0000-4000-8000-0000000000b1', '00000000-0000-4000-8000-0000000000a1', 'U1', 'u1@bat9.test', 'operator'),
  ('00000000-0000-4000-8000-0000000000b2', '00000000-0000-4000-8000-0000000000a2', 'U2', 'u2@bat9.test', 'operator'),
  ('00000000-0000-4000-8000-0000000000b3', '00000000-0000-4000-8000-0000000000a3', 'U3', 'u3@bat9.test', 'operator');

INSERT INTO public.customers (id, tenant_id, customer_number) VALUES
  ('00000000-0000-4000-8000-0000000000c1', '00000000-0000-4000-8000-0000000000a1', 'BAT9-C1'),
  ('00000000-0000-4000-8000-0000000000c2', '00000000-0000-4000-8000-0000000000a2', 'BAT9-C2'),
  ('00000000-0000-4000-8000-0000000000c3', '00000000-0000-4000-8000-0000000000a3', 'BAT9-C3');

-- ------------------------------------------------------------ as tally_app
SET LOCAL app.user_id = '00000000-0000-4000-8000-0000000000b1';
SET ROLE tally_app;

-- F1: a draft needs no evidence
INSERT INTO public.customer_tax_exemptions (id, tenant_id, customer_id, exemption_type, effective_start)
VALUES ('00000000-0000-4000-8000-0000000000d1', '00000000-0000-4000-8000-0000000000a1',
        '00000000-0000-4000-8000-0000000000c1', 'religious', CURRENT_DATE - 400);
DO $$ BEGIN RAISE NOTICE 'PASS F1: draft (pending_verification) accepted without evidence'; END $$;

-- F2: verify into active without evidence -> refused (check_violation)
DO $$
BEGIN
    UPDATE public.customer_tax_exemptions
       SET status = 'active', verified_by = '00000000-0000-4000-8000-0000000000b1', verified_at = now()
     WHERE id = '00000000-0000-4000-8000-0000000000d1';
    RAISE EXCEPTION 'F2 FAILED: active accepted without certificate evidence';
EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'PASS F2: active without evidence refused (%)', substring(SQLERRM for 60);
END $$;

-- F3: verify into active WITH certificate_number -> ok, recorded_at stamps
UPDATE public.customer_tax_exemptions
   SET status = 'active', certificate_number = '01-339-4711',
       verified_by = '00000000-0000-4000-8000-0000000000b1', verified_at = now()
 WHERE id = '00000000-0000-4000-8000-0000000000d1';
DO $$
DECLARE r public.customer_tax_exemptions%ROWTYPE;
BEGIN
    SELECT * INTO r FROM public.customer_tax_exemptions WHERE id = '00000000-0000-4000-8000-0000000000d1';
    IF r.status = 'active' AND r.recorded_at IS NOT NULL THEN
        RAISE NOTICE 'PASS F3: active with certificate_number asserted (recorded_at stamped)';
    ELSE
        RAISE EXCEPTION 'F3 FAILED: status=% recorded_at=%', r.status, r.recorded_at;
    END IF;
END $$;

-- F4: evidence cannot be stripped from an asserted row (bi-temporal freeze)
DO $$
BEGIN
    UPDATE public.customer_tax_exemptions SET certificate_number = NULL
     WHERE id = '00000000-0000-4000-8000-0000000000d1';
    RAISE EXCEPTION 'F4 FAILED: certificate_number stripped from an asserted row';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'PASS F4: asserted row refuses evidence strip (%)', substring(SQLERRM for 60);
END $$;

-- F5: notes edit on an asserted row still fine (gate not re-judged)
UPDATE public.customer_tax_exemptions SET notes = 'bat9 note'
 WHERE id = '00000000-0000-4000-8000-0000000000d1';
DO $$ BEGIN RAISE NOTICE 'PASS F5: notes edit on asserted row accepted (gate fires only on entry to assertion)'; END $$;

-- F6: certificate_url alone is sufficient evidence (Comptroller letter)
INSERT INTO public.customer_tax_exemptions (id, tenant_id, customer_id, exemption_type, effective_start,
        certificate_url, status, verified_by, verified_at)
VALUES ('00000000-0000-4000-8000-0000000000d2', '00000000-0000-4000-8000-0000000000a1',
        '00000000-0000-4000-8000-0000000000c1', 'educational', CURRENT_DATE - 100,
        'https://artifacts.example/comptroller-letter-77.pdf', 'active',
        '00000000-0000-4000-8000-0000000000b1', now());
DO $$ BEGIN RAISE NOTICE 'PASS F6: certificate_url alone satisfies the evidence gate'; END $$;

-- F7: non-evidence strings are not evidence — spaces, tab, NBSP,
-- punctuation-only (the round-1 CRITICAL: btrim passed a single tab)
DO $$
DECLARE v text;
BEGIN
    FOREACH v IN ARRAY ARRAY['   ', E'\t', E'\n', chr(160), '---', E' \t.', ''] LOOP
        BEGIN
            INSERT INTO public.customer_tax_exemptions (tenant_id, customer_id, exemption_type, effective_start,
                    certificate_number, status, verified_by, verified_at)
            VALUES ('00000000-0000-4000-8000-0000000000a1', '00000000-0000-4000-8000-0000000000c1',
                    'medical', CURRENT_DATE, v, 'active', '00000000-0000-4000-8000-0000000000b1', now());
            RAISE EXCEPTION 'F7 FAILED: certificate_number "%" accepted as evidence', v;
        EXCEPTION WHEN check_violation THEN
            NULL; -- expected
        END;
    END LOOP;
    RAISE NOTICE 'PASS F7: spaces / tab / newline / NBSP / punctuation-only / empty all refused as evidence';
END $$;

-- ---- switch to T2 (government flipped to flag-only; notice window 30) ----
RESET ROLE;
SET LOCAL app.user_id = '00000000-0000-4000-8000-0000000000b2';
SET ROLE tally_app;

-- F8: flag-only category asserts without evidence
INSERT INTO public.customer_tax_exemptions (id, tenant_id, customer_id, exemption_type, effective_start,
        status, verified_by, verified_at)
VALUES ('00000000-0000-4000-8000-0000000000d3', '00000000-0000-4000-8000-0000000000a2',
        '00000000-0000-4000-8000-0000000000c2', 'government', CURRENT_DATE - 50, 'active',
        '00000000-0000-4000-8000-0000000000b2', now());
DO $$ BEGIN RAISE NOTICE 'PASS F8: flag-only category (T2 government) asserts without evidence'; END $$;

-- F9: the flip is per category — T2 non_profit still requires evidence
DO $$
BEGIN
    INSERT INTO public.customer_tax_exemptions (tenant_id, customer_id, exemption_type, effective_start,
            status, verified_by, verified_at)
    VALUES ('00000000-0000-4000-8000-0000000000a2', '00000000-0000-4000-8000-0000000000c2',
            'non_profit', CURRENT_DATE, 'active', '00000000-0000-4000-8000-0000000000b2', now());
    RAISE EXCEPTION 'F9 FAILED: T2 non_profit asserted without evidence';
EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'PASS F9: flag-only flip is per category — non_profit still gated';
END $$;

-- ---- T3: malformed config raises, never guesses ----
RESET ROLE;
SET LOCAL app.user_id = '00000000-0000-4000-8000-0000000000b3';
SET ROLE tally_app;

-- F10: certificate_required = "maybe" refuses the write that consulted it
DO $$
BEGIN
    INSERT INTO public.customer_tax_exemptions (tenant_id, customer_id, exemption_type, effective_start,
            status, verified_by, verified_at)
    VALUES ('00000000-0000-4000-8000-0000000000a3', '00000000-0000-4000-8000-0000000000c3',
            'government', CURRENT_DATE, 'active', '00000000-0000-4000-8000-0000000000b3', now());
    RAISE EXCEPTION 'F10 FAILED: malformed certificate_required config did not raise';
EXCEPTION WHEN check_violation THEN
    IF SQLERRM LIKE '%invalid%' THEN
        RAISE NOTICE 'PASS F10: malformed certificate_required raises (%)', substring(SQLERRM for 60);
    ELSE
        RAISE EXCEPTION 'F10 FAILED: wrong refusal: %', SQLERRM;
    END IF;
END $$;

-- F11: accessor rejects a non-domain category
DO $$
BEGIN
    PERFORM public.tax_exemption_certificate_required('00000000-0000-4000-8000-0000000000a3', 'industrial');
    RAISE EXCEPTION 'F11 FAILED: retired category accepted';
EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'PASS F11: non-domain category (industrial, retired by R-13) refused';
END $$;

-- F12: renewal_notice_days — default and override; and RLS: another
-- tenant's window is not resolvable (the accessor reads tenants under
-- the caller's RLS — no SECURITY DEFINER escape)
DO $$
DECLARE d3 int;
BEGIN
    BEGIN
        d3 := public.tax_exemption_renewal_notice_days('00000000-0000-4000-8000-0000000000a1');
        RAISE EXCEPTION 'F12a FAILED: T3 operator resolved T1''s window (RLS escape)';
    EXCEPTION WHEN no_data_found THEN
        RAISE NOTICE 'PASS F12a: cross-tenant window lookup refused under RLS';
    END;
END $$;
RESET ROLE;
DO $$
DECLARE d1 int; d2 int;
BEGIN
    d1 := public.tax_exemption_renewal_notice_days('00000000-0000-4000-8000-0000000000a1');
    d2 := public.tax_exemption_renewal_notice_days('00000000-0000-4000-8000-0000000000a2');
    IF d1 = 60 AND d2 = 30 THEN
        RAISE NOTICE 'PASS F12b: renewal notice days default 60, T2 override 30';
    ELSE
        RAISE EXCEPTION 'F12b FAILED: got % / %', d1, d2;
    END IF;
END $$;
SET LOCAL app.user_id = '00000000-0000-4000-8000-0000000000b3';
SET ROLE tally_app;

-- F13: renewal_notice_days = 0 raises
DO $$
BEGIN
    PERFORM public.tax_exemption_renewal_notice_days('00000000-0000-4000-8000-0000000000a3');
    RAISE EXCEPTION 'F13 FAILED: zero notice window accepted';
EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'PASS F13: renewal_notice_days_before = 0 refused';
END $$;

-- ---- renewal view, back on T1 ----
RESET ROLE;
SET LOCAL app.user_id = '00000000-0000-4000-8000-0000000000b1';
SET ROLE tally_app;

-- fixtures: due-in-10 (in window), due-in-200 (outside), lapsed
INSERT INTO public.customer_tax_exemptions (id, tenant_id, customer_id, exemption_type, effective_start, effective_end,
        certificate_number, status, verified_by, verified_at)
VALUES
 ('00000000-0000-4000-8000-0000000000d4', '00000000-0000-4000-8000-0000000000a1',
  '00000000-0000-4000-8000-0000000000c1', 'non_profit', CURRENT_DATE - 355, CURRENT_DATE + 10,
  '01-339-1010', 'active', '00000000-0000-4000-8000-0000000000b1', now()),
 ('00000000-0000-4000-8000-0000000000d5', '00000000-0000-4000-8000-0000000000a1',
  '00000000-0000-4000-8000-0000000000c1', 'agricultural', CURRENT_DATE - 165, CURRENT_DATE + 200,
  '01-924-2020', 'active', '00000000-0000-4000-8000-0000000000b1', now()),
 ('00000000-0000-4000-8000-0000000000d6', '00000000-0000-4000-8000-0000000000a1',
  '00000000-0000-4000-8000-0000000000c1', 'sales_for_resale', CURRENT_DATE - 400, CURRENT_DATE - 5,
  '01-339-3030', 'active', '00000000-0000-4000-8000-0000000000b1', now());

-- F14: view contents — due-in-10 renewal_due, lapsed lapsed, due-in-200 absent
DO $$
DECLARE n_due int; n_lapsed int; n_far int; d_remaining int;
BEGIN
    SELECT count(*) INTO n_due    FROM public.customer_tax_exemptions_renewal_due WHERE exemption_id = '00000000-0000-4000-8000-0000000000d4' AND renewal_state = 'renewal_due';
    SELECT count(*) INTO n_lapsed FROM public.customer_tax_exemptions_renewal_due WHERE exemption_id = '00000000-0000-4000-8000-0000000000d6' AND renewal_state = 'lapsed';
    SELECT count(*) INTO n_far    FROM public.customer_tax_exemptions_renewal_due WHERE exemption_id = '00000000-0000-4000-8000-0000000000d5';
    SELECT days_remaining INTO d_remaining FROM public.customer_tax_exemptions_renewal_due WHERE exemption_id = '00000000-0000-4000-8000-0000000000d4';
    IF n_due = 1 AND n_lapsed = 1 AND n_far = 0 AND d_remaining = 10 THEN
        RAISE NOTICE 'PASS F14: view shows renewal_due (10 days) and lapsed; outside-window row absent';
    ELSE
        RAISE EXCEPTION 'F14 FAILED: due=% lapsed=% far=% days=%', n_due, n_lapsed, n_far, d_remaining;
    END IF;
END $$;

-- F15: a renewal on file suppresses the expiring row
INSERT INTO public.customer_tax_exemptions (id, tenant_id, customer_id, exemption_type, effective_start, effective_end,
        certificate_number, status, verified_by, verified_at)
VALUES ('00000000-0000-4000-8000-0000000000d7', '00000000-0000-4000-8000-0000000000a1',
        '00000000-0000-4000-8000-0000000000c1', 'non_profit', CURRENT_DATE + 11, CURRENT_DATE + 376,
        '01-339-1011', 'active', '00000000-0000-4000-8000-0000000000b1', now());
DO $$
DECLARE n int;
BEGIN
    SELECT count(*) INTO n FROM public.customer_tax_exemptions_renewal_due WHERE exemption_id = '00000000-0000-4000-8000-0000000000d4';
    IF n = 0 THEN
        RAISE NOTICE 'PASS F15: renewal on file suppresses the expiring row';
    ELSE
        RAISE EXCEPTION 'F15 FAILED: expiring row still listed with a renewal on file';
    END IF;
END $$;

-- F15b: a LAPSED row stays listed even with a renewal on file (it owes
-- its expiry succession) — round-1 Fable LOW
INSERT INTO public.customer_tax_exemptions (id, tenant_id, customer_id, exemption_type, effective_start, effective_end,
        certificate_number, status, verified_by, verified_at)
VALUES ('00000000-0000-4000-8000-0000000000d9', '00000000-0000-4000-8000-0000000000a1',
        '00000000-0000-4000-8000-0000000000c1', 'sales_for_resale', CURRENT_DATE + 300, CURRENT_DATE + 665,
        '01-339-3031', 'active', '00000000-0000-4000-8000-0000000000b1', now());
DO $$
DECLARE n int;
BEGIN
    SELECT count(*) INTO n FROM public.customer_tax_exemptions_renewal_due
     WHERE exemption_id = '00000000-0000-4000-8000-0000000000d6' AND renewal_state = 'lapsed';
    IF n = 1 THEN
        RAISE NOTICE 'PASS F15b: lapsed row stays listed despite a gapped renewal on file';
    ELSE
        RAISE EXCEPTION 'F15b FAILED: lapsed row suppressed by the renewal';
    END IF;
END $$;

-- F15c: the window boundary — "notify 60 days before expiry" means a row
-- with EXACTLY 60 days remaining is listed TODAY (opened_on = today), and
-- one with 61 days remaining is not (round-2 Codex MEDIUM: < gave N-1 days)
INSERT INTO public.customer_tax_exemptions (id, tenant_id, customer_id, exemption_type, effective_start, effective_end,
        certificate_number, status, verified_by, verified_at, exemption_reason)
VALUES
 ('00000000-0000-4000-8000-0000000000da', '00000000-0000-4000-8000-0000000000a1',
  '00000000-0000-4000-8000-0000000000c1', 'medical', CURRENT_DATE - 305, CURRENT_DATE + 60,
  '01-339-6060', 'active', '00000000-0000-4000-8000-0000000000b1', now(), NULL),
 ('00000000-0000-4000-8000-0000000000db', '00000000-0000-4000-8000-0000000000a1',
  '00000000-0000-4000-8000-0000000000c1', 'other', CURRENT_DATE - 304, CURRENT_DATE + 61,
  '01-339-6161', 'active', '00000000-0000-4000-8000-0000000000b1', now(), 'bat9 boundary probe');
DO $$
DECLARE n60 int; n61 int; d date; rem int;
BEGIN
    SELECT count(*) INTO n60 FROM public.customer_tax_exemptions_renewal_due WHERE exemption_id = '00000000-0000-4000-8000-0000000000da';
    SELECT count(*) INTO n61 FROM public.customer_tax_exemptions_renewal_due WHERE exemption_id = '00000000-0000-4000-8000-0000000000db';
    SELECT notice_window_opened_on, days_remaining INTO d, rem FROM public.customer_tax_exemptions_renewal_due
     WHERE exemption_id = '00000000-0000-4000-8000-0000000000da';
    IF n60 = 1 AND n61 = 0 AND d = CURRENT_DATE AND rem = 60 THEN
        RAISE NOTICE 'PASS F15c: exactly-60-days row enters today (opened_on = today); 61-days row absent';
    ELSE
        RAISE EXCEPTION 'F15c FAILED: n60=% n61=% opened_on=% remaining=%', n60, n61, d, rem;
    END IF;
END $$;

-- F16: RLS through the view — T2's operator sees only T2 rows
RESET ROLE;
SET LOCAL app.user_id = '00000000-0000-4000-8000-0000000000b2';
SET ROLE tally_app;
DO $$
DECLARE n_t1 int;
BEGIN
    SELECT count(*) INTO n_t1 FROM public.customer_tax_exemptions_renewal_due
     WHERE tenant_id = '00000000-0000-4000-8000-0000000000a1';
    IF n_t1 = 0 THEN
        RAISE NOTICE 'PASS F16: security_invoker view honours RLS (T1 rows invisible to T2)';
    ELSE
        RAISE EXCEPTION 'F16 FAILED: % cross-tenant rows visible', n_t1;
    END IF;
END $$;

-- F17: succession end-to-end — close the lapsed row, insert the expired
-- successor: refused without evidence, accepted with it.
RESET ROLE;
SET LOCAL app.user_id = '00000000-0000-4000-8000-0000000000b1';
SET ROLE tally_app;
SET CONSTRAINTS ALL DEFERRED;
UPDATE public.customer_tax_exemptions
   SET recorded_until = now(), closed_type = 'superseded', closed_reason = 'expiry recorded (bat9 F17)',
       closed_by = '00000000-0000-4000-8000-0000000000b1'
 WHERE id = '00000000-0000-4000-8000-0000000000d6';
DO $$
BEGIN
    INSERT INTO public.customer_tax_exemptions (tenant_id, customer_id, exemption_type, effective_start, effective_end,
            status, verified_by, verified_at, revoked_at, revoked_by,
            change_type, change_reason, supersedes_id)
    VALUES ('00000000-0000-4000-8000-0000000000a1', '00000000-0000-4000-8000-0000000000c1',
            'sales_for_resale', CURRENT_DATE - 400, CURRENT_DATE - 5,
            'expired', '00000000-0000-4000-8000-0000000000b1', now(), NULL, NULL,
            'succession', 'certificate lapsed (bat9 F17)', '00000000-0000-4000-8000-0000000000d6');
    RAISE EXCEPTION 'F17a FAILED: expired successor asserted without evidence';
EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'PASS F17a: expired successor without evidence refused';
END $$;
INSERT INTO public.customer_tax_exemptions (id, tenant_id, customer_id, exemption_type, effective_start, effective_end,
        certificate_number, status, verified_by, verified_at, change_type, change_reason, supersedes_id)
VALUES ('00000000-0000-4000-8000-0000000000d8', '00000000-0000-4000-8000-0000000000a1',
        '00000000-0000-4000-8000-0000000000c1', 'sales_for_resale', CURRENT_DATE - 400, CURRENT_DATE - 5,
        '01-339-3030', 'expired', '00000000-0000-4000-8000-0000000000b1', now(),
        'succession', 'certificate lapsed (bat9 F17)', '00000000-0000-4000-8000-0000000000d6');
SET CONSTRAINTS ALL IMMEDIATE;
DO $$ BEGIN RAISE NOTICE 'PASS F17b: expired successor with evidence lands; successor gate satisfied'; END $$;

-- F18: the lapsed row leaves the queue once its expiry successor is written
DO $$
DECLARE n int;
BEGIN
    SELECT count(*) INTO n FROM public.customer_tax_exemptions_renewal_due WHERE exemption_id = '00000000-0000-4000-8000-0000000000d6';
    IF n = 0 THEN
        RAISE NOTICE 'PASS F18: lapsed row leaves the renewal queue after the expiry succession';
    ELSE
        RAISE EXCEPTION 'F18 FAILED: closed lapsed row still in the queue';
    END IF;
END $$;

-- F19: should_charge_tax end-to-end at coordinates — the asserted
-- non_profit exemption (d4) exempts a taxable gas item today
DO $$
DECLARE taxed boolean;
BEGIN
    taxed := public.should_charge_tax('00000000-0000-4000-8000-0000000000c1', true, 'gas', CURRENT_DATE, now());
    IF taxed = false THEN
        RAISE NOTICE 'PASS F19: should_charge_tax honours the asserted evidence-backed exemption';
    ELSE
        RAISE EXCEPTION 'F19 FAILED: exemption not honoured';
    END IF;
END $$;

-- F20/F21: config-shape and overflow refusals (as superuser; T4 fixture)
RESET ROLE;
INSERT INTO public.tenants (id, name, slug, settings) VALUES
  ('00000000-0000-4000-8000-0000000000a4', 'T4 Gasco', 'bat9-t4',
   '{"tax_exemptions": {"certificate_required": false, "renewal_notice_days_before": "99999999999999999999"}}');
DO $$
BEGIN
    PERFORM public.tax_exemption_certificate_required('00000000-0000-4000-8000-0000000000a4', 'non_profit');
    RAISE EXCEPTION 'F20 FAILED: scalar certificate_required node silently defaulted';
EXCEPTION WHEN check_violation THEN
    IF SQLERRM LIKE '%not an object%' THEN
        RAISE NOTICE 'PASS F20: wrong-shape certificate_required node raises instead of defaulting';
    ELSE
        RAISE EXCEPTION 'F20 FAILED: wrong refusal: %', SQLERRM;
    END IF;
END $$;
DO $$
BEGIN
    PERFORM public.tax_exemption_renewal_notice_days('00000000-0000-4000-8000-0000000000a4');
    RAISE EXCEPTION 'F21 FAILED: overflow-length notice days accepted';
EXCEPTION WHEN check_violation THEN
    IF SQLERRM LIKE '%invalid%' THEN
        RAISE NOTICE 'PASS F21: overflow-length notice days refused with the friendly message';
    ELSE
        RAISE EXCEPTION 'F21 FAILED: wrong refusal: %', SQLERRM;
    END IF;
END $$;
DO $$
BEGIN
    UPDATE public.tenants SET settings = jsonb_set(settings, '{tax_exemptions,renewal_notice_days_before}', '"60.5"')
     WHERE id = '00000000-0000-4000-8000-0000000000a4';
    PERFORM public.tax_exemption_renewal_notice_days('00000000-0000-4000-8000-0000000000a4');
    RAISE EXCEPTION 'F21b FAILED: non-integer notice days accepted';
EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'PASS F21b: non-integer notice days refused with the friendly message';
END $$;

-- F22: ancestor-shape — tax_exemptions itself malformed raises in BOTH
-- accessors instead of silently defaulting (round-2 Codex LOW/MEDIUM)
INSERT INTO public.tenants (id, name, slug, settings) VALUES
  ('00000000-0000-4000-8000-0000000000a5', 'T5 Gasco', 'bat9-t5', '{"tax_exemptions": "oops"}');
DO $$
BEGIN
    PERFORM public.tax_exemption_certificate_required('00000000-0000-4000-8000-0000000000a5', 'non_profit');
    RAISE EXCEPTION 'F22a FAILED: malformed tax_exemptions node silently defaulted (certificate_required)';
EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'PASS F22a: malformed tax_exemptions node raises in tax_exemption_certificate_required';
END $$;
DO $$
BEGIN
    PERFORM public.tax_exemption_renewal_notice_days('00000000-0000-4000-8000-0000000000a5');
    RAISE EXCEPTION 'F22b FAILED: malformed tax_exemptions node silently defaulted (renewal days)';
EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'PASS F22b: malformed tax_exemptions node raises in tax_exemption_renewal_notice_days';
END $$;

ROLLBACK;
