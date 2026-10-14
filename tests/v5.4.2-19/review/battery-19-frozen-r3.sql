-- ============================================================================
-- BATTERY v5.4.2-19 — hardening batch 1 (2026-10-13)
-- Run: psql -U tally -d <db-with-patch> -v ON_ERROR_STOP=1 -f battery-19.sql
-- One transaction, rolled back. Fixtures as the owner; every guard that the
-- application meets is exercised as tally_app. pg_temp.refuses() runs one
-- statement and requires the named SQLSTATE: any other error, or success, is
-- a FAIL. Success checks use IS DISTINCT FROM, so a NULL is a failure.
--
--   R  meter reads: no DB usage; the billing lock freezes values, void
--      releases included; the void carve-out is void_invoice()'s exact write
--   Q  rates: tier proration default, coverage order, deadband, DAG
--   P  payments: effective date, return code, one per processor transaction
--   M  payment methods: identity frozen, history by supersession
--   L  logs: append-only, DB-stamped created_at, AI rows cite their audit
--   N  anomalies: dedup key required, immediate, identity write-once
--   H  ad-hoc charge approval capture
--   I  invoice image hash
--   J  imports: file named and hashed, one live job per file
--   E  attestation on active medical enrollments
--   B  account_balance_as_of
-- r2 adds the review-round-1 cases: RB (reads born unconsumed), RF (the lock
-- flag), RW (the whitelist), RV (pointers on a void-released read), P7-P8,
-- L6-L8, N4, M9, J6-J9, I4-I6, Q5 (a deep diamond is fast).
-- r3 adds the review-round-2 cases: RL (an unconsumed read's lock record),
-- P7c-P9b (money out once; lineage of the same customer), Q4h-Q4i, J2c
-- isolated by constraint, J10 (a finished job's file and counts), L7c by a
-- different citation, B5 (void_invoice()'s returned balance).
-- Races (two halves of a dependency cycle at once): races/cycle-19.sh.
-- ============================================================================
BEGIN;
SET CONSTRAINTS ALL IMMEDIATE;

CREATE FUNCTION pg_temp.refuses(p_label text, p_sql text, p_state text) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  BEGIN
    EXECUTE p_sql;
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = p_state THEN
      RAISE NOTICE 'PASS %: refused (%)', p_label, left(SQLERRM, 160);
      RETURN;
    END IF;
    RAISE EXCEPTION 'FAIL %: refused with % (%), expected %', p_label, SQLSTATE, SQLERRM, p_state;
  END;
  RAISE EXCEPTION 'FAIL %: accepted', p_label;
END $$;
GRANT EXECUTE ON FUNCTION pg_temp.refuses(text, text, text) TO tally_app;
-- refuses_at (r3, Codex S1): as refuses(), and the refusal must come from the
-- named guard — its constraint name, or a fragment of its message — so a test
-- cannot pass on another guard that shares the SQLSTATE.
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
GRANT EXECUTE ON FUNCTION pg_temp.refuses_at(text, text, text, text) TO tally_app;

-- ------------------------------------------------------------------ fixtures
INSERT INTO public.tenants (id, name, slug) VALUES
  ('00000000-0000-4000-8000-0000000019a1', 'T1 City Gas', 'bat19-t1'),
  ('00000000-0000-4000-8000-0000000019a2', 'T2 Gasco', 'bat19-t2');
INSERT INTO public.users (id, tenant_id, display_name, email, role) VALUES
  ('00000000-0000-4000-8000-0000000019b1', '00000000-0000-4000-8000-0000000019a1', 'Op1', 'op1@bat19.test', 'operator'),
  ('00000000-0000-4000-8000-0000000019b2', '00000000-0000-4000-8000-0000000019a2', 'Op2', 'op2@bat19.test', 'operator');
INSERT INTO public.customers (id, tenant_id, customer_number, customer_type) VALUES
  ('00000000-0000-4000-8000-0000000019c1', '00000000-0000-4000-8000-0000000019a1', 'B19-C1', 'residential'),
  ('00000000-0000-4000-8000-0000000019c2', '00000000-0000-4000-8000-0000000019a1', 'B19-C2', 'residential'),
  ('00000000-0000-4000-8000-0000000019c9', '00000000-0000-4000-8000-0000000019a2', 'B19-C9', 'residential');
INSERT INTO public.service_locations (id, tenant_id, customer_id, location_number, address_line1, city, state, zip) VALUES
  ('00000000-0000-4000-8000-0000000019d1', '00000000-0000-4000-8000-0000000019a1', '00000000-0000-4000-8000-0000000019c1', 'L1', '1 Main', 'Austin', 'TX', '78701'),
  ('00000000-0000-4000-8000-0000000019d2', '00000000-0000-4000-8000-0000000019a1', '00000000-0000-4000-8000-0000000019c1', 'L2', '2 Main', 'Austin', 'TX', '78702');
INSERT INTO public.meters (id, tenant_id, meter_number, location_id, service_type) VALUES
  ('00000000-0000-4000-8000-0000000019e1', '00000000-0000-4000-8000-0000000019a1', 'M1', '00000000-0000-4000-8000-0000000019d1', 'gas'),
  ('00000000-0000-4000-8000-0000000019e2', '00000000-0000-4000-8000-0000000019a1', 'M2', '00000000-0000-4000-8000-0000000019d2', 'gas');
INSERT INTO public.billing_runs (id, tenant_id, run_number, billing_period, period_start, period_end) VALUES
  ('00000000-0000-4000-8000-0000000019f1', '00000000-0000-4000-8000-0000000019a1', 'R1', '2026-01', '2026-01-01', '2026-01-31'),
  ('00000000-0000-4000-8000-0000000019f2', '00000000-0000-4000-8000-0000000019a1', 'R2', '2026-01', '2026-01-01', '2026-01-31');
INSERT INTO public.invoices (id, tenant_id, invoice_number, customer_id, location_id, invoice_date, billing_period, period_start, period_end, due_date) VALUES
  ('00000000-0000-4000-8000-000000001901', '00000000-0000-4000-8000-0000000019a1', 'I1', '00000000-0000-4000-8000-0000000019c1', '00000000-0000-4000-8000-0000000019d1', '2026-02-01', '2026-01', '2026-01-01', '2026-01-31', '2026-02-20'),
  ('00000000-0000-4000-8000-000000001902', '00000000-0000-4000-8000-0000000019a1', 'I2', '00000000-0000-4000-8000-0000000019c1', '00000000-0000-4000-8000-0000000019d1', '2026-02-01', '2026-01', '2026-01-01', '2026-01-31', '2026-02-20');

SET LOCAL app.user_id = '00000000-0000-4000-8000-0000000019b1';


-- ===================================================================== R. reads
SET ROLE tally_app;
-- RB: an application read is born unconsumed (r2, Opus B1).
SELECT pg_temp.refuses('RB1 a read inserted already locked',
  $q$INSERT INTO public.meter_readings (tenant_id, meter_id, reading_date, reading_value, validation_status, billing_period_locked, locked_at, locked_by_billing_run_id)
     VALUES ('00000000-0000-4000-8000-0000000019a1', '00000000-0000-4000-8000-0000000019e2', DATE '2026-01-31', 5, 'locked', true, TIMESTAMPTZ '2020-01-01 00:00Z', '00000000-0000-4000-8000-0000000019f1')$q$, '23514');
SELECT pg_temp.refuses('RB2 a read inserted void-released',
  $q$INSERT INTO public.meter_readings (tenant_id, meter_id, reading_date, reading_value, validation_status)
     VALUES ('00000000-0000-4000-8000-0000000019a1', '00000000-0000-4000-8000-0000000019e2', DATE '2026-01-31', 5, 'void_released')$q$, '23514');
SELECT pg_temp.refuses('RB3 a read inserted with a lock time',
  $q$INSERT INTO public.meter_readings (tenant_id, meter_id, reading_date, reading_value, locked_at)
     VALUES ('00000000-0000-4000-8000-0000000019a1', '00000000-0000-4000-8000-0000000019e2', DATE '2026-01-31', 5, now())$q$, '23514');
SELECT pg_temp.refuses('RB4 a read inserted with the lock flag',
  $q$INSERT INTO public.meter_readings (tenant_id, meter_id, reading_date, reading_value, billing_period_locked)
     VALUES ('00000000-0000-4000-8000-0000000019a1', '00000000-0000-4000-8000-0000000019e2', DATE '2026-01-31', 5, true)$q$, '23514');
-- RF: the flag is set only by the move to locked (r2, Opus S3 / Fable S2).
INSERT INTO public.meter_readings (id, tenant_id, meter_id, reading_date, reading_value)
VALUES ('00000000-0000-4000-8000-000000001912', '00000000-0000-4000-8000-0000000019a1', '00000000-0000-4000-8000-0000000019e2', DATE '2026-01-31', 5);
SELECT pg_temp.refuses('RF1 the lock flag set on a pending read',
  $q$UPDATE public.meter_readings SET billing_period_locked = true WHERE id = '00000000-0000-4000-8000-000000001912'$q$, '23514');
-- RL (r3, Fable S1): nor is the rest of the lock record written on it.
SELECT pg_temp.refuses_at('RL1 a run pointer on a pending read', $q$UPDATE public.meter_readings SET locked_by_billing_run_id = '00000000-0000-4000-8000-0000000019f1' WHERE id = '00000000-0000-4000-8000-000000001912'$q$, '23514', 'no billing run has consumed');
SELECT pg_temp.refuses_at('RL2 a bill pointer on a pending read', $q$UPDATE public.meter_readings SET locked_by_invoice_id = '00000000-0000-4000-8000-000000001901' WHERE id = '00000000-0000-4000-8000-000000001912'$q$, '23514', 'no billing run has consumed');
SELECT pg_temp.refuses_at('RL3 a lock time on a pending read', $q$UPDATE public.meter_readings SET locked_at = TIMESTAMPTZ '2020-01-01 00:00Z' WHERE id = '00000000-0000-4000-8000-000000001912'$q$, '23514', 'no billing run has consumed');
SELECT pg_temp.refuses_at('RL4 a voided bill on a pending read', $q$UPDATE public.meter_readings SET voided_from_invoice_id = '00000000-0000-4000-8000-000000001902' WHERE id = '00000000-0000-4000-8000-000000001912'$q$, '23514', 'no billing run has consumed');

-- R0: a wrapped dial (previous 9990, now 50) gets no usage from the database.
INSERT INTO public.meter_readings (id, tenant_id, meter_id, reading_date, reading_value, previous_value)
VALUES ('00000000-0000-4000-8000-000000001911', '00000000-0000-4000-8000-0000000019a1', '00000000-0000-4000-8000-0000000019e1', DATE '2026-01-31', 50, 9990);
DO $$ BEGIN
  IF (SELECT consumption FROM public.meter_readings WHERE id = '00000000-0000-4000-8000-000000001911') IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL R0: the database wrote a usage for a wrapped dial';
  END IF;
  IF (SELECT previous_reading_date FROM public.meter_readings WHERE id = '00000000-0000-4000-8000-000000001911') IS NOT NULL
     OR (SELECT previous_value FROM public.meter_readings WHERE id = '00000000-0000-4000-8000-000000001911') IS DISTINCT FROM 9990 THEN
    RAISE EXCEPTION 'FAIL R0b: the caller''s previous_value was not kept';
  END IF;
  RAISE NOTICE 'PASS R0: no consumption written by the database (CI-022); the caller''s previous value kept';
END $$;

-- R1: the core supplies usage and locks; locked_at is the database's.
UPDATE public.meter_readings SET validation_status = 'approved', consumption = 60 WHERE id = '00000000-0000-4000-8000-000000001911';
UPDATE public.meter_readings SET validation_status = 'released_to_billing' WHERE id = '00000000-0000-4000-8000-000000001911';
UPDATE public.meter_readings
   SET validation_status = 'locked', billing_period_locked = true, locked_at = TIMESTAMPTZ '2020-01-01 00:00Z',
       locked_by_billing_run_id = '00000000-0000-4000-8000-0000000019f1', locked_by_invoice_id = '00000000-0000-4000-8000-000000001901'
 WHERE id = '00000000-0000-4000-8000-000000001911';
DO $$ BEGIN
  IF (SELECT locked_at FROM public.meter_readings WHERE id = '00000000-0000-4000-8000-000000001911') IS DISTINCT FROM now() THEN
    RAISE EXCEPTION 'FAIL R1: the caller''s locked_at was kept';
  END IF;
  RAISE NOTICE 'PASS R1: a lock is stamped with the database''s time, not the caller''s';
END $$;

SELECT pg_temp.refuses('R2 locked read: value edit', $q$UPDATE public.meter_readings SET reading_value = 51 WHERE id = '00000000-0000-4000-8000-000000001911'$q$, '23001');
SELECT pg_temp.refuses('R2b locked read: meter moved', $q$UPDATE public.meter_readings SET meter_id = '00000000-0000-4000-8000-0000000019e2' WHERE id = '00000000-0000-4000-8000-000000001911'$q$, '23001');
SELECT pg_temp.refuses('R2c locked read: voided_from_invoice_id outside a void', $q$UPDATE public.meter_readings SET voided_from_invoice_id = '00000000-0000-4000-8000-000000001902' WHERE id = '00000000-0000-4000-8000-000000001911'$q$, '23001');
SELECT pg_temp.refuses('R2d locked read: lock flag cleared', $q$UPDATE public.meter_readings SET billing_period_locked = false WHERE id = '00000000-0000-4000-8000-000000001911'$q$, '23001');
UPDATE public.meter_readings SET notes = 'field note' WHERE id = '00000000-0000-4000-8000-000000001911';
DO $$ BEGIN RAISE NOTICE 'PASS R3: notes stay editable on a locked read'; END $$;
-- RW: every column but the follow-up whitelist is frozen (r2, Opus S2 / Fable S5).
SELECT pg_temp.refuses('RW1 days in period (a proration input)', $q$UPDATE public.meter_readings SET days_in_period = 99 WHERE id = '00000000-0000-4000-8000-000000001911'$q$, '23001');
SELECT pg_temp.refuses('RW2 raw read value', $q$UPDATE public.meter_readings SET raw_read_value = '51' WHERE id = '00000000-0000-4000-8000-000000001911'$q$, '23001');
SELECT pg_temp.refuses('RW3 estimation reason', $q$UPDATE public.meter_readings SET estimation_reason = 'x' WHERE id = '00000000-0000-4000-8000-000000001911'$q$, '23001');
SELECT pg_temp.refuses('RW4 read timestamp', $q$UPDATE public.meter_readings SET reading_timestamp = now() WHERE id = '00000000-0000-4000-8000-000000001911'$q$, '23001');
SELECT pg_temp.refuses('RW5 validated_by', $q$UPDATE public.meter_readings SET validated_by = '00000000-0000-4000-8000-0000000019b1' WHERE id = '00000000-0000-4000-8000-000000001911'$q$, '23001');
UPDATE public.meter_readings SET requires_followup = true, followup_notes = 'check', dispute_reason = 'customer call', triggers_correction_workflow = true
 WHERE id = '00000000-0000-4000-8000-000000001911';
DO $$ BEGIN RAISE NOTICE 'PASS RW6: follow-up and dispute fields stay editable'; END $$;

-- R4/R5: a "void" that writes more than void_invoice() writes.
SET LOCAL app.void_operation = 'true';
SELECT pg_temp.refuses('R4 void that also edits the value', $q$UPDATE public.meter_readings SET validation_status = 'void_released', voided_from_invoice_id = locked_by_invoice_id, locked_by_invoice_id = NULL, reading_value = 52 WHERE id = '00000000-0000-4000-8000-000000001911'$q$, '23001');
SELECT pg_temp.refuses('R5 void that keeps the bill pointer', $q$UPDATE public.meter_readings SET validation_status = 'void_released', voided_from_invoice_id = locked_by_invoice_id WHERE id = '00000000-0000-4000-8000-000000001911'$q$, '23001');
SELECT pg_temp.refuses('R5b void that points at another bill', $q$UPDATE public.meter_readings SET validation_status = 'void_released', voided_from_invoice_id = '00000000-0000-4000-8000-000000001902', locked_by_invoice_id = NULL WHERE id = '00000000-0000-4000-8000-000000001911'$q$, '23001');
SELECT pg_temp.refuses('R5c void that moves the run', $q$UPDATE public.meter_readings SET validation_status = 'void_released', voided_from_invoice_id = locked_by_invoice_id, locked_by_invoice_id = NULL, locked_by_billing_run_id = '00000000-0000-4000-8000-0000000019f2' WHERE id = '00000000-0000-4000-8000-000000001911'$q$, '23001');
-- R6: void_invoice()'s exact write passes.
UPDATE public.meter_readings SET voided_from_invoice_id = locked_by_invoice_id, locked_by_invoice_id = NULL, validation_status = 'void_released'
 WHERE id = '00000000-0000-4000-8000-000000001911';
SET LOCAL app.void_operation = 'false';
DO $$ BEGIN
  IF (SELECT validation_status FROM public.meter_readings WHERE id = '00000000-0000-4000-8000-000000001911') IS DISTINCT FROM 'void_released' THEN
    RAISE EXCEPTION 'FAIL R6: void_invoice()''s write was refused';
  END IF;
  RAISE NOTICE 'PASS R6: void_invoice()''s exact write (pointer cleared, voided_from set) still passes';
END $$;

-- R7: the hole — a void-released read was fully writable.
SELECT pg_temp.refuses('R7 void-released read: value edit', $q$UPDATE public.meter_readings SET reading_value = 53 WHERE id = '00000000-0000-4000-8000-000000001911'$q$, '23001');
SELECT pg_temp.refuses('R7b void-released read: usage edit', $q$UPDATE public.meter_readings SET consumption = 1 WHERE id = '00000000-0000-4000-8000-000000001911'$q$, '23001');
SELECT pg_temp.refuses('R7c void-released read: estimated flag edit', $q$UPDATE public.meter_readings SET is_estimated = true WHERE id = '00000000-0000-4000-8000-000000001911'$q$, '23001');
SELECT pg_temp.refuses('R7d void-released read: purpose edit', $q$UPDATE public.meter_readings SET reading_purpose = 'removal' WHERE id = '00000000-0000-4000-8000-000000001911'$q$, '23001');
SELECT pg_temp.refuses('R7e void-released read: lock flag cleared', $q$UPDATE public.meter_readings SET billing_period_locked = false WHERE id = '00000000-0000-4000-8000-000000001911'$q$, '23001');
-- RV: the lock pointers of a void-released read (r2, Opus B2 / Fable S1).
SELECT pg_temp.refuses('RV1 the voided bill erased', $q$UPDATE public.meter_readings SET voided_from_invoice_id = NULL WHERE id = '00000000-0000-4000-8000-000000001911'$q$, '23001');
SELECT pg_temp.refuses('RV2 the voided bill rewritten', $q$UPDATE public.meter_readings SET voided_from_invoice_id = '00000000-0000-4000-8000-000000001902' WHERE id = '00000000-0000-4000-8000-000000001911'$q$, '23001');
SELECT pg_temp.refuses('RV3 the run rewritten', $q$UPDATE public.meter_readings SET locked_by_billing_run_id = '00000000-0000-4000-8000-0000000019f2' WHERE id = '00000000-0000-4000-8000-000000001911'$q$, '23001');
SELECT pg_temp.refuses('RV4 the lock time rewritten', $q$UPDATE public.meter_readings SET locked_at = now() - interval '1 day' WHERE id = '00000000-0000-4000-8000-000000001911'$q$, '23001');
SELECT pg_temp.refuses('RV5 a bill pointer set without a re-lock', $q$UPDATE public.meter_readings SET locked_by_invoice_id = '00000000-0000-4000-8000-000000001902' WHERE id = '00000000-0000-4000-8000-000000001911'$q$, '23001');
SELECT pg_temp.refuses('RV6 the release to billing erases the voided bill', $q$UPDATE public.meter_readings SET validation_status = 'released_to_billing', voided_from_invoice_id = NULL WHERE id = '00000000-0000-4000-8000-000000001911'$q$, '23001');

-- R8: the correction run re-locks it under its own run and bill.
UPDATE public.meter_readings SET validation_status = 'released_to_billing' WHERE id = '00000000-0000-4000-8000-000000001911';
UPDATE public.meter_readings SET validation_status = 'locked', locked_by_billing_run_id = '00000000-0000-4000-8000-0000000019f2', locked_by_invoice_id = '00000000-0000-4000-8000-000000001902'
 WHERE id = '00000000-0000-4000-8000-000000001911';
DO $$ BEGIN
  IF (SELECT locked_by_invoice_id FROM public.meter_readings WHERE id = '00000000-0000-4000-8000-000000001911') IS DISTINCT FROM '00000000-0000-4000-8000-000000001902'::uuid THEN
    RAISE EXCEPTION 'FAIL R8: the correction run could not re-lock';
  END IF;
  IF (SELECT voided_from_invoice_id FROM public.meter_readings WHERE id = '00000000-0000-4000-8000-000000001911') IS DISTINCT FROM '00000000-0000-4000-8000-000000001901'::uuid THEN
    RAISE EXCEPTION 'FAIL R8b: the re-lock lost the voided bill';
  END IF;
  RAISE NOTICE 'PASS R8: a correction run re-locks a void-released read under its own run and bill, keeping the voided bill';
END $$;
RESET ROLE;


-- ===================================================================== Q. rates
DO $$ BEGIN
  IF (SELECT column_default FROM information_schema.columns
       WHERE table_schema = 'public' AND table_name = 'rate_schedule_versions' AND column_name = 'prorate_tier_breakpoints') IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'FAIL Q1: prorate_tier_breakpoints does not default to true';
  END IF;
  RAISE NOTICE 'PASS Q1: tier breakpoints prorate by default (CI-108, Kyle T-3)';
END $$;

SELECT pg_temp.refuses('Q2 coverage ends before it starts',
  $q$INSERT INTO public.invoice_line_items (tenant_id, invoice_id, service_type, charge_type, description, amount, coverage_start, coverage_end)
     VALUES ('00000000-0000-4000-8000-0000000019a1', '00000000-0000-4000-8000-000000001901', 'gas', 'base_charge', 'x', 1, DATE '2026-01-31', DATE '2026-01-01')$q$, '23514');

INSERT INTO public.wna_zones (id, tenant_id, zone_code) VALUES ('00000000-0000-4000-8000-000000001931', '00000000-0000-4000-8000-0000000019a1', 'Z1');
SELECT pg_temp.refuses('Q3 a deadband value with no measure',
  $q$INSERT INTO public.wna_zone_versions (tenant_id, wna_zone_id, zone_name, effective_date, change_type, deadband_value)
     VALUES ('00000000-0000-4000-8000-0000000019a1', '00000000-0000-4000-8000-000000001931', 'Z1', DATE '2026-01-01', 'initial', 5)$q$, '23514');
SELECT pg_temp.refuses('Q3b a negative deadband',
  $q$INSERT INTO public.wna_zone_versions (tenant_id, wna_zone_id, zone_name, effective_date, change_type, deadband_value, deadband_measure, deadband_application)
     VALUES ('00000000-0000-4000-8000-0000000019a1', '00000000-0000-4000-8000-000000001931', 'Z1', DATE '2026-01-01', 'initial', -1, 'ratio_actual_to_normal', 'full_deviation')$q$, '23514');
SELECT pg_temp.refuses('Q3c an unknown evaluation form',
  $q$INSERT INTO public.wna_zone_versions (tenant_id, wna_zone_id, zone_name, effective_date, change_type, deadband_value, deadband_measure, deadband_application)
     VALUES ('00000000-0000-4000-8000-0000000019a1', '00000000-0000-4000-8000-000000001931', 'Z1', DATE '2026-01-01', 'initial', 5, 'ratio_actual_to_normal', 'half')$q$, '23514');
INSERT INTO public.wna_zone_versions (id, tenant_id, wna_zone_id, zone_name, effective_date, change_type, deadband_value, deadband_measure, deadband_application)
VALUES ('00000000-0000-4000-8000-000000001932', '00000000-0000-4000-8000-0000000019a1', '00000000-0000-4000-8000-000000001931', 'Z1', DATE '2026-01-01', 'initial', 2.21, 'ratio_actual_to_normal', 'excess_over_deadband');
SELECT pg_temp.refuses('Q3d a recorded deadband edited in place (the version is frozen)',
  $q$UPDATE public.wna_zone_versions SET deadband_value = 3 WHERE id = '00000000-0000-4000-8000-000000001932'$q$, '23001');
DO $$ BEGIN RAISE NOTICE 'PASS Q3: a full deadband (value, measure, application) is recorded on the zone version (CI-041)'; END $$;

INSERT INTO public.rate_schedules (id, tenant_id, code) VALUES
  ('00000000-0000-4000-8000-000000001941', '00000000-0000-4000-8000-0000000019a1', 'RS1'),
  ('00000000-0000-4000-8000-000000001943', '00000000-0000-4000-8000-0000000019a2', 'RS-T2');
INSERT INTO public.rate_items (id, tenant_id, item_code) VALUES
  ('00000000-0000-4000-8000-0000000019a0', '00000000-0000-4000-8000-0000000019a1', 'A'),
  ('00000000-0000-4000-8000-0000000019b0', '00000000-0000-4000-8000-0000000019a1', 'B'),
  ('00000000-0000-4000-8000-0000000019c0', '00000000-0000-4000-8000-0000000019a1', 'C'),
  ('00000000-0000-4000-8000-0000000019d0', '00000000-0000-4000-8000-0000000019a1', 'D'),
  ('00000000-0000-4000-8000-0000000019f0', '00000000-0000-4000-8000-0000000019a2', 'T2X');
SET ROLE tally_app;
INSERT INTO public.rate_item_dependencies (id, tenant_id, rate_schedule_id, dependent_rate_item_id, base_rate_item_id) VALUES
  ('00000000-0000-4000-8000-000000001951', '00000000-0000-4000-8000-0000000019a1', '00000000-0000-4000-8000-000000001941', '00000000-0000-4000-8000-0000000019a0', '00000000-0000-4000-8000-0000000019b0'),
  ('00000000-0000-4000-8000-000000001952', '00000000-0000-4000-8000-0000000019a1', '00000000-0000-4000-8000-000000001941', '00000000-0000-4000-8000-0000000019b0', '00000000-0000-4000-8000-0000000019c0'),
  ('00000000-0000-4000-8000-000000001953', '00000000-0000-4000-8000-0000000019a1', '00000000-0000-4000-8000-000000001941', '00000000-0000-4000-8000-0000000019a0', '00000000-0000-4000-8000-0000000019c0');
DO $$ BEGIN RAISE NOTICE 'PASS Q4: a diamond (A on B, B on C, A on C) is a DAG and is accepted'; END $$;
SELECT pg_temp.refuses('Q4b a 2-cycle (B on A while A on B)',
  $q$INSERT INTO public.rate_item_dependencies (tenant_id, rate_schedule_id, dependent_rate_item_id, base_rate_item_id)
     VALUES ('00000000-0000-4000-8000-0000000019a1', '00000000-0000-4000-8000-000000001941', '00000000-0000-4000-8000-0000000019b0', '00000000-0000-4000-8000-0000000019a0')$q$, '23514');
SELECT pg_temp.refuses('Q4d an edit that turns an edge into a cycle',
  $q$UPDATE public.rate_item_dependencies SET dependent_rate_item_id = '00000000-0000-4000-8000-0000000019c0', base_rate_item_id = '00000000-0000-4000-8000-0000000019a0'
     WHERE id = '00000000-0000-4000-8000-000000001953'$q$, '23514');
SELECT pg_temp.refuses('Q4e a dependency on another tenant''s rate item',
  $q$INSERT INTO public.rate_item_dependencies (tenant_id, rate_schedule_id, dependent_rate_item_id, base_rate_item_id)
     VALUES ('00000000-0000-4000-8000-0000000019a1', '00000000-0000-4000-8000-000000001941', '00000000-0000-4000-8000-0000000019d0', '00000000-0000-4000-8000-0000000019f0')$q$, '23503');
-- An edit that keeps the graph acyclic passes (D joins below C).
UPDATE public.rate_item_dependencies SET base_rate_item_id = '00000000-0000-4000-8000-0000000019d0' WHERE id = '00000000-0000-4000-8000-000000001953';
DO $$ BEGIN RAISE NOTICE 'PASS Q4f: an acyclic edit passes'; END $$;
-- r2 (Codex S2): with A no longer on C directly, C on A can only close the
-- 3-hop cycle A on B on C on A — the walk must recurse past one hop.
SELECT pg_temp.refuses('Q4c a 3-cycle with no shortcut (C on A while A on B on C)',
  $q$INSERT INTO public.rate_item_dependencies (tenant_id, rate_schedule_id, dependent_rate_item_id, base_rate_item_id)
     VALUES ('00000000-0000-4000-8000-0000000019a1', '00000000-0000-4000-8000-000000001941', '00000000-0000-4000-8000-0000000019c0', '00000000-0000-4000-8000-0000000019a0')$q$, '23514');
-- Reversing the lone edge A on D to D on A passes: the walk excludes the row
-- being rewritten, or it would see the old edge and call this a 2-cycle.
UPDATE public.rate_item_dependencies SET dependent_rate_item_id = '00000000-0000-4000-8000-0000000019d0', base_rate_item_id = '00000000-0000-4000-8000-0000000019a0'
 WHERE id = '00000000-0000-4000-8000-000000001953';
DO $$ BEGIN RAISE NOTICE 'PASS Q4h: reversing a lone edge passes (the edited row is not its own cycle)'; END $$;
-- r3 (Fable N7): another tenant's schedule, not just another tenant's item.
SELECT pg_temp.refuses_at('Q4i a dependency filed under another tenant''s schedule',
  $q$INSERT INTO public.rate_item_dependencies (tenant_id, rate_schedule_id, dependent_rate_item_id, base_rate_item_id)
     VALUES ('00000000-0000-4000-8000-0000000019a1', '00000000-0000-4000-8000-000000001943', '00000000-0000-4000-8000-0000000019a0', '00000000-0000-4000-8000-0000000019b0')$q$, '23503', 'is not a row of this dependency''s tenant');
RESET ROLE;
-- The owner sees every tenant: the check compares tenants, not just visibility.
SELECT pg_temp.refuses('Q4g the owner writes a dependency on another tenant''s rate item',
  $q$INSERT INTO public.rate_item_dependencies (tenant_id, rate_schedule_id, dependent_rate_item_id, base_rate_item_id)
     VALUES ('00000000-0000-4000-8000-0000000019a1', '00000000-0000-4000-8000-000000001941', '00000000-0000-4000-8000-0000000019d0', '00000000-0000-4000-8000-0000000019f0')$q$, '23503');
-- Q5: a 40-layer diamond (2^40 paths) is checked in well under a second (r2, Opus S5).
INSERT INTO public.rate_schedules (id, tenant_id, code) VALUES ('00000000-0000-4000-8000-000000001942', '00000000-0000-4000-8000-0000000019a1', 'RS-DEEP');
DO $$
DECLARE i int; t0 timestamptz; v_ms numeric;
BEGIN
  INSERT INTO public.rate_items (id, tenant_id, item_code)
  SELECT md5('deep' || g)::uuid, '00000000-0000-4000-8000-0000000019a1', 'DEEP-' || g FROM generate_series(0, 120) g;
  FOR i IN 0..39 LOOP   -- layer i: top(3i) depends on 3i+1 and 3i+2; both depend on 3i+3
    INSERT INTO public.rate_item_dependencies (tenant_id, rate_schedule_id, dependent_rate_item_id, base_rate_item_id) VALUES
      ('00000000-0000-4000-8000-0000000019a1', '00000000-0000-4000-8000-000000001942', md5('deep' || (3*i))::uuid,   md5('deep' || (3*i+1))::uuid),
      ('00000000-0000-4000-8000-0000000019a1', '00000000-0000-4000-8000-000000001942', md5('deep' || (3*i))::uuid,   md5('deep' || (3*i+2))::uuid),
      ('00000000-0000-4000-8000-0000000019a1', '00000000-0000-4000-8000-000000001942', md5('deep' || (3*i+1))::uuid, md5('deep' || (3*i+3))::uuid),
      ('00000000-0000-4000-8000-0000000019a1', '00000000-0000-4000-8000-000000001942', md5('deep' || (3*i+2))::uuid, md5('deep' || (3*i+3))::uuid);
  END LOOP;
  t0 := clock_timestamp();
  BEGIN
    INSERT INTO public.rate_item_dependencies (tenant_id, rate_schedule_id, dependent_rate_item_id, base_rate_item_id)
    VALUES ('00000000-0000-4000-8000-0000000019a1', '00000000-0000-4000-8000-000000001942', md5('deep120')::uuid, md5('deep0')::uuid);
    RAISE EXCEPTION 'FAIL Q5: the 40-layer cycle was accepted';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  v_ms := extract(epoch FROM clock_timestamp() - t0) * 1000;
  IF v_ms > 1000 THEN RAISE EXCEPTION 'FAIL Q5: the cycle check took % ms', round(v_ms); END IF;
  RAISE NOTICE 'PASS Q5: a cycle through a 40-layer diamond is found in % ms', round(v_ms);
END $$;


-- ================================================================== P. payments
SET ROLE tally_app;
SELECT pg_temp.refuses('P1 a posted payment with no effective date',
  $q$INSERT INTO public.payments (tenant_id, payment_number, customer_id, payment_date, amount, payment_method)
     VALUES ('00000000-0000-4000-8000-0000000019a1', 'P-X', '00000000-0000-4000-8000-0000000019c1', DATE '2026-02-05', 10, 'check')$q$, '23514');
SELECT pg_temp.refuses('P1b a date with no method',
  $q$INSERT INTO public.payments (tenant_id, payment_number, customer_id, payment_date, amount, payment_method, effective_date)
     VALUES ('00000000-0000-4000-8000-0000000019a1', 'P-X', '00000000-0000-4000-8000-0000000019c1', DATE '2026-02-05', 10, 'check', DATE '2026-02-03')$q$, '23514');
SELECT pg_temp.refuses('P1c a method outside the vocabulary',
  $q$INSERT INTO public.payments (tenant_id, payment_number, customer_id, payment_date, amount, payment_method, effective_date, effective_date_method)
     VALUES ('00000000-0000-4000-8000-0000000019a1', 'P-X', '00000000-0000-4000-8000-0000000019c1', DATE '2026-02-05', 10, 'check', DATE '2026-02-03', 'whenever')$q$, '23503');
-- A pending payment may wait for its effective date; it is set as it posts.
INSERT INTO public.payments (id, tenant_id, payment_number, customer_id, payment_date, amount, payment_method, status)
VALUES ('00000000-0000-4000-8000-000000001961', '00000000-0000-4000-8000-0000000019a1', 'P-1', '00000000-0000-4000-8000-0000000019c1', DATE '2026-02-05', 10, 'check', 'pending');
UPDATE public.payments SET status = 'posted', effective_date = DATE '2026-02-03', effective_date_method = 'postmark' WHERE id = '00000000-0000-4000-8000-000000001961';
DO $$ BEGIN RAISE NOTICE 'PASS P2: a pending payment posts with its effective date and method (CI-058)'; END $$;
INSERT INTO public.payments (id, tenant_id, payment_number, customer_id, payment_date, amount, payment_method, status)
VALUES ('00000000-0000-4000-8000-000000001963', '00000000-0000-4000-8000-0000000019a1', 'P-V', '00000000-0000-4000-8000-0000000019c1', DATE '2026-02-05', 10, 'check', 'pending');
UPDATE public.payments SET status = 'voided' WHERE id = '00000000-0000-4000-8000-000000001963';
DO $$ BEGIN RAISE NOTICE 'PASS P2b: a payment voided at intake needs no effective date (it never took effect)'; END $$;
SELECT pg_temp.refuses('P3 a posted payment''s effective date rewritten',
  $q$UPDATE public.payments SET effective_date = DATE '2026-02-05' WHERE id = '00000000-0000-4000-8000-000000001961'$q$, '23001');
SELECT pg_temp.refuses('P3b a posted payment''s method rewritten',
  $q$UPDATE public.payments SET effective_date_method = 'lockbox_receipt' WHERE id = '00000000-0000-4000-8000-000000001961'$q$, '23001');
SELECT pg_temp.refuses('P4 a return code on a posted payment',
  $q$UPDATE public.payments SET return_code = 'R01' WHERE id = '00000000-0000-4000-8000-000000001961'$q$, '23514');

INSERT INTO public.payments (id, tenant_id, payment_number, customer_id, payment_date, amount, payment_method, effective_date, effective_date_method,
                             source_system, provider_transaction_id)
VALUES ('00000000-0000-4000-8000-000000001962', '00000000-0000-4000-8000-0000000019a1', 'P-2', '00000000-0000-4000-8000-0000000019c1', DATE '2026-02-06', 20, 'ach',
        DATE '2026-02-06', 'bank_settlement', 'paymentus_webhook', 'TXN-1');
SELECT pg_temp.refuses('P5 an ACH return with no return code',
  $q$UPDATE public.payments SET status = 'nsf', nsf_date = DATE '2026-02-10' WHERE id = '00000000-0000-4000-8000-000000001962'$q$, '23514');
SELECT pg_temp.refuses('P5b a return code not of NACHA form',
  $q$UPDATE public.payments SET status = 'nsf', nsf_date = DATE '2026-02-10', return_code = 'insufficient' WHERE id = '00000000-0000-4000-8000-000000001962'$q$, '23514');
UPDATE public.payments SET status = 'nsf', nsf_date = DATE '2026-02-10', return_code = 'R01' WHERE id = '00000000-0000-4000-8000-000000001962';
DO $$ BEGIN RAISE NOTICE 'PASS P5c: an ACH return records its NACHA code (CI-052)'; END $$;
SELECT pg_temp.refuses('P5d a return code rewritten',
  $q$UPDATE public.payments SET return_code = 'R10' WHERE id = '00000000-0000-4000-8000-000000001962'$q$, '23001');

SELECT pg_temp.refuses('P6 the same processor transaction posted twice',
  $q$INSERT INTO public.payments (tenant_id, payment_number, customer_id, payment_date, amount, payment_method, effective_date, effective_date_method,
                                  source_system, provider_transaction_id)
     VALUES ('00000000-0000-4000-8000-0000000019a1', 'P-3', '00000000-0000-4000-8000-0000000019c1', DATE '2026-02-06', 20, 'ach',
             DATE '2026-02-06', 'bank_settlement', 'paymentus_webhook', 'TXN-1')$q$, '23505');
INSERT INTO public.payments (tenant_id, payment_number, customer_id, payment_date, amount, payment_method, effective_date, effective_date_method,
                             source_system, provider_transaction_id, refunds_payment_id)
VALUES ('00000000-0000-4000-8000-0000000019a1', 'P-4', '00000000-0000-4000-8000-0000000019c1', DATE '2026-02-07', -20, 'refund',
        DATE '2026-02-07', 'bank_settlement', 'paymentus_webhook', 'TXN-1', '00000000-0000-4000-8000-000000001962');
INSERT INTO public.payments (tenant_id, payment_number, customer_id, payment_date, amount, payment_method, effective_date, effective_date_method,
                             source_system, provider_transaction_id)
VALUES ('00000000-0000-4000-8000-0000000019a1', 'P-5', '00000000-0000-4000-8000-0000000019c1', DATE '2026-02-06', 20, 'credit_card',
        DATE '2026-02-06', 'bank_settlement', 'stripe_webhook', 'TXN-1');
DO $$ BEGIN RAISE NOTICE 'PASS P6b: a refund citing its original, and another source''s id, are not duplicates (CI-055)'; END $$;
-- r2 (Opus B3, Fable B1): the rule keys on money in, not on a lineage label.
SELECT pg_temp.refuses('P7 a second receipt labelled a refund',
  $q$INSERT INTO public.payments (tenant_id, payment_number, customer_id, payment_date, amount, payment_method, effective_date, effective_date_method,
                                  source_system, provider_transaction_id, refunds_payment_id)
     VALUES ('00000000-0000-4000-8000-0000000019a1', 'P-6', '00000000-0000-4000-8000-0000000019c1', DATE '2026-02-06', 20, 'ach',
             DATE '2026-02-06', 'bank_settlement', 'paymentus_webhook', 'TXN-1', '00000000-0000-4000-8000-000000001961')$q$, '23514');
SELECT pg_temp.refuses('P7b a second receipt labelled a replacement for a bounced payment',
  $q$INSERT INTO public.payments (tenant_id, payment_number, customer_id, payment_date, amount, payment_method, effective_date, effective_date_method,
                                  source_system, provider_transaction_id, nsf_original_payment_id)
     VALUES ('00000000-0000-4000-8000-0000000019a1', 'P-7', '00000000-0000-4000-8000-0000000019c1', DATE '2026-02-06', 20, 'ach',
             DATE '2026-02-06', 'bank_settlement', 'paymentus_webhook', 'TXN-1', '00000000-0000-4000-8000-000000001962')$q$, '23505');
SELECT pg_temp.refuses('P8 a refund of money in (positive)',
  $q$INSERT INTO public.payments (tenant_id, payment_number, customer_id, payment_date, amount, payment_method, effective_date, effective_date_method, refunds_payment_id)
     VALUES ('00000000-0000-4000-8000-0000000019a1', 'P-8', '00000000-0000-4000-8000-0000000019c1', DATE '2026-02-07', 20, 'refund',
             DATE '2026-02-07', 'bank_settlement', '00000000-0000-4000-8000-000000001961')$q$, '23514');
-- r3 (Fable B1, Opus S4): money out delivered twice does not go out twice.
SELECT pg_temp.refuses_at('P7c the same refund delivered twice',
  $q$INSERT INTO public.payments (tenant_id, payment_number, customer_id, payment_date, amount, payment_method, effective_date, effective_date_method,
                                  source_system, provider_transaction_id, refunds_payment_id)
     VALUES ('00000000-0000-4000-8000-0000000019a1', 'P-4b', '00000000-0000-4000-8000-0000000019c1', DATE '2026-02-07', -20, 'refund',
             DATE '2026-02-07', 'bank_settlement', 'paymentus_webhook', 'TXN-1', '00000000-0000-4000-8000-000000001962')$q$, '23505', 'payments_provider_refund_once');
INSERT INTO public.payments (tenant_id, payment_number, customer_id, payment_date, amount, payment_method, effective_date, effective_date_method,
                             source_system, provider_transaction_id, refunds_payment_id)
VALUES ('00000000-0000-4000-8000-0000000019a1', 'P-4c', '00000000-0000-4000-8000-0000000019c1', DATE '2026-02-08', -5, 'refund',
        DATE '2026-02-08', 'bank_settlement', 'paymentus_webhook', 'RFND-7', '00000000-0000-4000-8000-000000001962');
DO $$ BEGIN RAISE NOTICE 'PASS P7d: a further (partial) refund under its own processor id is recorded'; END $$;
SELECT pg_temp.refuses_at('P7e a negative row with no lineage delivered twice',
  $q$INSERT INTO public.payments (tenant_id, payment_number, customer_id, payment_date, amount, payment_method, effective_date, effective_date_method,
                                  source_system, provider_transaction_id)
     VALUES ('00000000-0000-4000-8000-0000000019a1', 'P-4d', '00000000-0000-4000-8000-0000000019c1', DATE '2026-02-08', -5, 'ach',
             DATE '2026-02-08', 'bank_settlement', 'paymentus_webhook', 'RFND-7')$q$, '23505', 'payments_provider_refund_once');
-- r3 (Fable S2, Opus PR3): a refund or a replacement cites the same customer's payment.
SELECT pg_temp.refuses_at('P9 a refund of another customer''s payment',
  $q$INSERT INTO public.payments (tenant_id, payment_number, customer_id, payment_date, amount, payment_method, effective_date, effective_date_method, refunds_payment_id)
     VALUES ('00000000-0000-4000-8000-0000000019a1', 'P-9', '00000000-0000-4000-8000-0000000019c2', DATE '2026-02-07', -500, 'refund',
             DATE '2026-02-07', 'bank_settlement', '00000000-0000-4000-8000-000000001962')$q$, '23503', 'is not a payment of this customer');
SELECT pg_temp.refuses_at('P9b a replacement for another customer''s bounced payment',
  $q$INSERT INTO public.payments (tenant_id, payment_number, customer_id, payment_date, amount, payment_method, effective_date, effective_date_method, nsf_original_payment_id)
     VALUES ('00000000-0000-4000-8000-0000000019a1', 'P-9b', '00000000-0000-4000-8000-0000000019c2', DATE '2026-02-12', 20, 'check',
             DATE '2026-02-12', 'postmark', '00000000-0000-4000-8000-000000001962')$q$, '23503', 'is not a payment of this customer');
RESET ROLE;


-- =========================================================== M. payment methods
SET ROLE tally_app;
INSERT INTO public.payment_methods (id, tenant_id, customer_id, provider, provider_token, method_type, last_four, bank_name, is_default) VALUES
  ('00000000-0000-4000-8000-000000001971', '00000000-0000-4000-8000-0000000019a1', '00000000-0000-4000-8000-0000000019c1', 'paymentus', 'tok-1', 'ach', '1111', 'First Bank', true),
  ('00000000-0000-4000-8000-000000001972', '00000000-0000-4000-8000-0000000019a1', '00000000-0000-4000-8000-0000000019c2', 'paymentus', 'tok-2', 'ach', '2222', 'First Bank', false),
  ('00000000-0000-4000-8000-000000001973', '00000000-0000-4000-8000-0000000019a1', '00000000-0000-4000-8000-0000000019c1', 'paymentus', 'tok-3', 'ach', '3333', 'First Bank', false);
SELECT pg_temp.refuses('M1 bank account number edited in place',
  $q$UPDATE public.payment_methods SET last_four = '9999' WHERE id = '00000000-0000-4000-8000-000000001971'$q$, '23001');
SELECT pg_temp.refuses('M1b token edited in place',
  $q$UPDATE public.payment_methods SET provider_token = 'tok-9' WHERE id = '00000000-0000-4000-8000-000000001971'$q$, '23001');
UPDATE public.payment_methods SET nickname = 'checking', last_used_at = now() WHERE id = '00000000-0000-4000-8000-000000001971';
DO $$ BEGIN RAISE NOTICE 'PASS M2: nickname and usage stay editable'; END $$;
SELECT pg_temp.refuses('M3 a notice-of-change supersede with no change code',
  $q$INSERT INTO public.payment_methods (tenant_id, customer_id, provider, provider_token, method_type, last_four, supersedes_payment_method_id, supersede_reason)
     VALUES ('00000000-0000-4000-8000-0000000019a1', '00000000-0000-4000-8000-0000000019c1', 'paymentus', 'tok-1b', 'ach', '1112', '00000000-0000-4000-8000-000000001971', 'ach_notice_of_change')$q$, '23514');
SELECT pg_temp.refuses('M3a a notice-of-change supersede with a receipt time but no change code',
  $q$INSERT INTO public.payment_methods (tenant_id, customer_id, provider, provider_token, method_type, last_four, supersedes_payment_method_id, supersede_reason, noc_received_at)
     VALUES ('00000000-0000-4000-8000-0000000019a1', '00000000-0000-4000-8000-0000000019c1', 'paymentus', 'tok-1b', 'ach', '1112', '00000000-0000-4000-8000-000000001971', 'ach_notice_of_change', now())$q$, '23514');
SELECT pg_temp.refuses('M3b a supersede with no reason',
  $q$INSERT INTO public.payment_methods (tenant_id, customer_id, provider, provider_token, method_type, last_four, supersedes_payment_method_id)
     VALUES ('00000000-0000-4000-8000-0000000019a1', '00000000-0000-4000-8000-0000000019c1', 'paymentus', 'tok-1b', 'ach', '1112', '00000000-0000-4000-8000-000000001971')$q$, '23514');
SELECT pg_temp.refuses('M3c superseding another customer''s method',
  $q$INSERT INTO public.payment_methods (tenant_id, customer_id, provider, provider_token, method_type, last_four, supersedes_payment_method_id, supersede_reason)
     VALUES ('00000000-0000-4000-8000-0000000019a1', '00000000-0000-4000-8000-0000000019c1', 'paymentus', 'tok-2b', 'ach', '2223', '00000000-0000-4000-8000-000000001972', 'customer_update')$q$, '23514');
INSERT INTO public.payment_methods (id, tenant_id, customer_id, provider, provider_token, method_type, last_four, supersedes_payment_method_id, supersede_reason, noc_change_code, noc_received_at)
VALUES ('00000000-0000-4000-8000-000000001974', '00000000-0000-4000-8000-0000000019a1', '00000000-0000-4000-8000-0000000019c1', 'paymentus', 'tok-1b', 'ach', '1112',
        '00000000-0000-4000-8000-000000001971', 'ach_notice_of_change', 'C01', TIMESTAMPTZ '2026-02-02 10:00Z');
DO $$ BEGIN
  IF (SELECT is_active OR is_default FROM public.payment_methods WHERE id = '00000000-0000-4000-8000-000000001971') IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'FAIL M4: the superseded method stayed active or default';
  END IF;
  RAISE NOTICE 'PASS M4: a notice of change makes a new row; the database retires the old one (CI-057)';
END $$;
SELECT pg_temp.refuses('M5 a superseded method reactivated',
  $q$UPDATE public.payment_methods SET is_active = true WHERE id = '00000000-0000-4000-8000-000000001971'$q$, '23514');
SELECT pg_temp.refuses('M6 a second successor',
  $q$INSERT INTO public.payment_methods (tenant_id, customer_id, provider, provider_token, method_type, last_four, supersedes_payment_method_id, supersede_reason)
     VALUES ('00000000-0000-4000-8000-0000000019a1', '00000000-0000-4000-8000-0000000019c1', 'paymentus', 'tok-1c', 'ach', '1113', '00000000-0000-4000-8000-000000001971', 'customer_update')$q$, '23505');
SELECT pg_temp.refuses('M7 the supersession rewritten',
  $q$UPDATE public.payment_methods SET supersedes_payment_method_id = '00000000-0000-4000-8000-000000001973' WHERE id = '00000000-0000-4000-8000-000000001974'$q$, '23001');
-- A method nobody superseded may still be switched off and on.
UPDATE public.payment_methods SET is_active = false WHERE id = '00000000-0000-4000-8000-000000001973';
UPDATE public.payment_methods SET is_active = true WHERE id = '00000000-0000-4000-8000-000000001973';
DO $$ BEGIN RAISE NOTICE 'PASS M8: a method that was never superseded can be deactivated and reactivated'; END $$;
SELECT pg_temp.refuses('M9 a superseded method made the default',
  $q$UPDATE public.payment_methods SET is_default = true WHERE id = '00000000-0000-4000-8000-000000001971'$q$, '23514');
RESET ROLE;


-- ====================================================================== L. logs
INSERT INTO public.customer_credits (id, tenant_id, customer_id, origin_type, original_amount, remaining_amount)
VALUES ('00000000-0000-4000-8000-000000001981', '00000000-0000-4000-8000-0000000019a1', '00000000-0000-4000-8000-0000000019c1', 'goodwill', 10, 10);
SET ROLE tally_app;
INSERT INTO public.dunning_events (id, tenant_id, invoice_id, customer_id, event_type, created_at)
VALUES ('00000000-0000-4000-8000-000000001982', '00000000-0000-4000-8000-0000000019a1', '00000000-0000-4000-8000-000000001901', '00000000-0000-4000-8000-0000000019c1', 'reminder_sent', TIMESTAMPTZ '2020-01-01 00:00Z');
INSERT INTO public.escheatment_events (id, tenant_id, customer_credit_id, customer_id, event_type, created_at)
VALUES ('00000000-0000-4000-8000-000000001983', '00000000-0000-4000-8000-0000000019a1', '00000000-0000-4000-8000-000000001981', '00000000-0000-4000-8000-0000000019c1', 'dormancy_flag', TIMESTAMPTZ '2020-01-01 00:00Z');
INSERT INTO public.ai_audit_log (id, tenant_id, action_type, created_at)
VALUES ('00000000-0000-4000-8000-000000001984', '00000000-0000-4000-8000-0000000019a1', 'mutation_executed', TIMESTAMPTZ '2020-01-01 00:00Z'),
       ('00000000-0000-4000-8000-000000001989', '00000000-0000-4000-8000-0000000019a1', 'mutation_executed', now());
DO $$ BEGIN
  IF (SELECT created_at FROM public.dunning_events WHERE id = '00000000-0000-4000-8000-000000001982') IS DISTINCT FROM now()
     OR (SELECT created_at FROM public.escheatment_events WHERE id = '00000000-0000-4000-8000-000000001983') IS DISTINCT FROM now()
     OR (SELECT created_at FROM public.ai_audit_log WHERE id = '00000000-0000-4000-8000-000000001984') IS DISTINCT FROM now() THEN
    RAISE EXCEPTION 'FAIL L1: a caller''s created_at was kept on a log';
  END IF;
  RAISE NOTICE 'PASS L1: the three logs'' created_at is the database''s';
END $$;
SELECT pg_temp.refuses('L2 the application edits a dunning event', $q$UPDATE public.dunning_events SET notes = 'x' WHERE id = '00000000-0000-4000-8000-000000001982'$q$, '42501');
SELECT pg_temp.refuses('L2b the application edits an escheatment event', $q$UPDATE public.escheatment_events SET notes = 'x' WHERE id = '00000000-0000-4000-8000-000000001983'$q$, '42501');
SELECT pg_temp.refuses('L2c the application edits an AI audit row', $q$UPDATE public.ai_audit_log SET result_summary = 'x' WHERE id = '00000000-0000-4000-8000-000000001984'$q$, '42501');
SELECT pg_temp.refuses('L3 an AI service order with no audit row',
  $q$INSERT INTO public.service_orders (tenant_id, order_number, order_type, description, customer_id, location_id, created_by_ai)
     VALUES ('00000000-0000-4000-8000-0000000019a1', 'SO-1', 'other', 'x', '00000000-0000-4000-8000-0000000019c1', '00000000-0000-4000-8000-0000000019d1', true)$q$, '23514');
SELECT pg_temp.refuses('L3b an AI-suggested charge with no audit row',
  $q$INSERT INTO public.adhoc_charges (tenant_id, charge_number, customer_id, charge_type, description, amount, regulatory_class, source)
     VALUES ('00000000-0000-4000-8000-0000000019a1', 'CH-X', '00000000-0000-4000-8000-0000000019c1', 'miscellaneous', 'x', 5, 'unregulated', 'ai_suggestion')$q$, '23514');
INSERT INTO public.adhoc_charges (tenant_id, charge_number, customer_id, charge_type, description, amount, regulatory_class, source, ai_audit_id)
VALUES ('00000000-0000-4000-8000-0000000019a1', 'CH-AI', '00000000-0000-4000-8000-0000000019c1', 'miscellaneous', 'x', 5, 'unregulated', 'ai_suggestion', '00000000-0000-4000-8000-000000001984');
DO $$ BEGIN RAISE NOTICE 'PASS L3c: an AI-suggested charge citing its audit row is accepted (CI-099)'; END $$;
RESET ROLE;
INSERT INTO public.ai_audit_log (id, tenant_id, action_type)
VALUES ('00000000-0000-4000-8000-000000001985', '00000000-0000-4000-8000-0000000019a2', 'mutation_executed');
SET ROLE tally_app;
-- r2 (Opus B4): another tenant's audit row is not a citation.
SELECT pg_temp.refuses('L6 an AI charge citing another tenant''s audit row',
  $q$INSERT INTO public.adhoc_charges (tenant_id, charge_number, customer_id, charge_type, description, amount, regulatory_class, source, ai_audit_id)
     VALUES ('00000000-0000-4000-8000-0000000019a1', 'CH-T2', '00000000-0000-4000-8000-0000000019c1', 'miscellaneous', 'x', 5, 'unregulated', 'ai_suggestion', '00000000-0000-4000-8000-000000001985')$q$, '23503');
SELECT pg_temp.refuses('L6b an AI service order citing another tenant''s audit row',
  $q$INSERT INTO public.service_orders (tenant_id, order_number, order_type, description, customer_id, location_id, created_by_ai, ai_audit_id)
     VALUES ('00000000-0000-4000-8000-0000000019a1', 'SO-T2', 'other', 'x', '00000000-0000-4000-8000-0000000019c1', '00000000-0000-4000-8000-0000000019d1', true, '00000000-0000-4000-8000-000000001985')$q$, '23503');
INSERT INTO public.service_orders (id, tenant_id, order_number, order_type, description, customer_id, location_id, created_by_ai, ai_audit_id)
VALUES ('00000000-0000-4000-8000-000000001986', '00000000-0000-4000-8000-0000000019a1', 'SO-AI', 'other', 'x', '00000000-0000-4000-8000-0000000019c1', '00000000-0000-4000-8000-0000000019d1', true, '00000000-0000-4000-8000-000000001984');
INSERT INTO public.service_orders (id, tenant_id, order_number, order_type, description, customer_id, location_id)
VALUES ('00000000-0000-4000-8000-000000001987', '00000000-0000-4000-8000-0000000019a1', 'SO-HUMAN', 'other', 'x', '00000000-0000-4000-8000-0000000019c1', '00000000-0000-4000-8000-0000000019d1');
SELECT pg_temp.refuses('L7 an AI service order''s flag and citation cleared',
  $q$UPDATE public.service_orders SET created_by_ai = false, ai_audit_id = NULL WHERE id = '00000000-0000-4000-8000-000000001986'$q$, '23001');
SELECT pg_temp.refuses('L7b a human service order relabelled as the AI''s',
  $q$UPDATE public.service_orders SET created_by_ai = true, ai_audit_id = '00000000-0000-4000-8000-000000001984' WHERE id = '00000000-0000-4000-8000-000000001987'$q$, '23001');
-- r3 (Fable N6): a different, valid same-tenant citation — only the
-- write-once trigger can refuse it (clearing it also trips the CHECK).
SELECT pg_temp.refuses('L7c an AI charge''s citation swapped for another audit row',
  $q$UPDATE public.adhoc_charges SET ai_audit_id = '00000000-0000-4000-8000-000000001989' WHERE charge_number = 'CH-AI'$q$, '23001');
-- r2 (Opus S1, Fable S4): the ledger's recorded time is the database's.
INSERT INTO public.account_ledger (id, tenant_id, customer_id, transaction_date, transaction_type, description, amount, created_at)
VALUES ('00000000-0000-4000-8000-000000001988', '00000000-0000-4000-8000-0000000019a1', '00000000-0000-4000-8000-0000000019c2', DATE '2026-01-31', 'adjustment', 'x', 1.00, TIMESTAMPTZ '2000-01-01 00:00Z');
DO $$ BEGIN
  IF (SELECT created_at FROM public.account_ledger WHERE id = '00000000-0000-4000-8000-000000001988') IS DISTINCT FROM now() THEN
    RAISE EXCEPTION 'FAIL L8: the application back-dated a ledger row''s recorded time';
  END IF;
  RAISE NOTICE 'PASS L8: a ledger row''s created_at (the balance''s recorded coordinate) is the database''s';
END $$;
RESET ROLE;
SELECT pg_temp.refuses('L4 the owner edits a dunning event', $q$UPDATE public.dunning_events SET notes = 'x' WHERE id = '00000000-0000-4000-8000-000000001982'$q$, '23001');
SELECT pg_temp.refuses('L4b the owner deletes an escheatment event', $q$DELETE FROM public.escheatment_events WHERE id = '00000000-0000-4000-8000-000000001983'$q$, '23001');
SELECT pg_temp.refuses('L4c the owner edits an AI audit row', $q$UPDATE public.ai_audit_log SET result_summary = 'x' WHERE id = '00000000-0000-4000-8000-000000001984'$q$, '23001');
DO $$ BEGIN
  IF (SELECT c.confdeltype FROM pg_constraint c WHERE c.conname = 'dunning_events_invoice_id_fkey') IS DISTINCT FROM 'a' THEN
    RAISE EXCEPTION 'FAIL L5: deleting an invoice still cascades to its dunning events';
  END IF;
  RAISE NOTICE 'PASS L5: an invoice delete no longer cascades to its dunning history (CI-068)';
END $$;


-- ================================================================= N. anomalies
SET ROLE tally_app;
SELECT pg_temp.refuses('N1 an anomaly with no dedup key',
  $q$INSERT INTO public.anomalies (tenant_id, anomaly_type, entity_type, entity_id, description)
     VALUES ('00000000-0000-4000-8000-0000000019a1', 'other', 'customer', '00000000-0000-4000-8000-0000000019c1', 'x')$q$, '23502');
SELECT pg_temp.refuses('N1b a blank dedup key',
  $q$INSERT INTO public.anomalies (tenant_id, anomaly_type, entity_type, entity_id, description, dedup_key)
     VALUES ('00000000-0000-4000-8000-0000000019a1', 'other', 'customer', '00000000-0000-4000-8000-0000000019c1', 'x', '  ')$q$, '23514');
INSERT INTO public.anomalies (id, tenant_id, anomaly_type, entity_type, entity_id, description, dedup_key)
VALUES ('00000000-0000-4000-8000-000000001991', '00000000-0000-4000-8000-0000000019a1', 'other', 'customer', '00000000-0000-4000-8000-0000000019c1', 'x', 'k1');
SET CONSTRAINTS ALL DEFERRED;
SELECT pg_temp.refuses('N2 a duplicate key, even with constraints deferred',
  $q$INSERT INTO public.anomalies (tenant_id, anomaly_type, entity_type, entity_id, description, dedup_key)
     VALUES ('00000000-0000-4000-8000-0000000019a1', 'other', 'customer', '00000000-0000-4000-8000-0000000019c1', 'x', 'k1')$q$, '23505');
SET CONSTRAINTS ALL IMMEDIATE;
UPDATE public.anomalies SET recurrence_count = 2, last_detected_at = now() + interval '1 hour', status = 'acknowledged'
 WHERE id = '00000000-0000-4000-8000-000000001991';
DO $$ BEGIN RAISE NOTICE 'PASS N3: a recurrence updates the canonical row'; END $$;
SELECT pg_temp.refuses('N3b the recurrence count lowered', $q$UPDATE public.anomalies SET recurrence_count = 1 WHERE id = '00000000-0000-4000-8000-000000001991'$q$, '23001');
SELECT pg_temp.refuses('N3c the last detection moved back', $q$UPDATE public.anomalies SET last_detected_at = now() WHERE id = '00000000-0000-4000-8000-000000001991'$q$, '23001');
SELECT pg_temp.refuses('N3d the dedup key rewritten', $q$UPDATE public.anomalies SET dedup_key = 'k2' WHERE id = '00000000-0000-4000-8000-000000001991'$q$, '23001');
SELECT pg_temp.refuses('N4 the anomaly moved to another customer', $q$UPDATE public.anomalies SET customer_id = '00000000-0000-4000-8000-0000000019c2' WHERE id = '00000000-0000-4000-8000-000000001991'$q$, '23001');
SELECT pg_temp.refuses('N4b the detection time rewritten', $q$UPDATE public.anomalies SET detected_at = now() - interval '1 day' WHERE id = '00000000-0000-4000-8000-000000001991'$q$, '23001');
SELECT pg_temp.refuses('N3e the first detection rewritten', $q$UPDATE public.anomalies SET first_detected_at = now() - interval '1 day' WHERE id = '00000000-0000-4000-8000-000000001991'$q$, '23001');
SELECT pg_temp.refuses('N3f last detection before first',
  $q$INSERT INTO public.anomalies (tenant_id, anomaly_type, entity_type, entity_id, description, dedup_key, first_detected_at, last_detected_at)
     VALUES ('00000000-0000-4000-8000-0000000019a1', 'other', 'customer', '00000000-0000-4000-8000-0000000019c1', 'x', 'k3', now(), now() - interval '1 day')$q$, '23514');
RESET ROLE;


-- ============================================================ H. charge approval
SET ROLE tally_app;
SELECT pg_temp.refuses('H1 approval required, no threshold recorded',
  $q$INSERT INTO public.adhoc_charges (tenant_id, charge_number, customer_id, charge_type, description, amount, regulatory_class, requires_approval)
     VALUES ('00000000-0000-4000-8000-0000000019a1', 'CH-1', '00000000-0000-4000-8000-0000000019c1', 'miscellaneous', 'x', 500, 'unregulated', true)$q$, '23514');
INSERT INTO public.adhoc_charges (id, tenant_id, charge_number, customer_id, charge_type, description, amount, regulatory_class, requires_approval, approval_threshold_at_creation)
VALUES ('00000000-0000-4000-8000-0000000019a3', '00000000-0000-4000-8000-0000000019a1', 'CH-2', '00000000-0000-4000-8000-0000000019c1', 'miscellaneous', 'x', 500, 'unregulated', true, 250);
SELECT pg_temp.refuses('H2 the threshold rewritten', $q$UPDATE public.adhoc_charges SET approval_threshold_at_creation = 1000 WHERE id = '00000000-0000-4000-8000-0000000019a3'$q$, '23001');
SELECT pg_temp.refuses('H2b approval no longer required', $q$UPDATE public.adhoc_charges SET requires_approval = false WHERE id = '00000000-0000-4000-8000-0000000019a3'$q$, '23001');
UPDATE public.adhoc_charges SET approved_by = '00000000-0000-4000-8000-0000000019b1', approved_at = now() WHERE id = '00000000-0000-4000-8000-0000000019a3';
DO $$ BEGIN RAISE NOTICE 'PASS H3: the charge is still approvable (CI-127)'; END $$;
RESET ROLE;


-- ============================================================= I. invoice image
SET ROLE tally_app;
SELECT pg_temp.refuses('I1 an image with no hash', $q$UPDATE public.invoices SET pdf_url = 's3://bills/I1.pdf', pdf_generated_at = now() WHERE id = '00000000-0000-4000-8000-000000001901'$q$, '23514');
SELECT pg_temp.refuses('I1b a hash not of SHA-256 form', $q$UPDATE public.invoices SET pdf_url = 's3://bills/I1.pdf', pdf_sha256 = 'abc' WHERE id = '00000000-0000-4000-8000-000000001901'$q$, '23514');
UPDATE public.invoices SET pdf_url = 's3://bills/I1.pdf', pdf_generated_at = now(), pdf_sha256 = repeat('a', 64) WHERE id = '00000000-0000-4000-8000-000000001901';
SELECT pg_temp.refuses('I2 a draft''s fingerprint changed without its image', $q$UPDATE public.invoices SET pdf_sha256 = repeat('b', 64) WHERE id = '00000000-0000-4000-8000-000000001901'$q$, '23514');
SELECT pg_temp.refuses('I4 a draft''s image changed without its fingerprint (r2, Fable S3)', $q$UPDATE public.invoices SET pdf_url = 's3://bills/I1-v2.pdf' WHERE id = '00000000-0000-4000-8000-000000001901'$q$, '23514');
UPDATE public.invoices SET pdf_url = 's3://bills/I1-v2.pdf', pdf_sha256 = repeat('b', 64) WHERE id = '00000000-0000-4000-8000-000000001901';
DO $$ BEGIN RAISE NOTICE 'PASS I3: a draft''s re-rendered image is recorded with its new fingerprint (CI-096)'; END $$;
RESET ROLE;


-- =================================================================== J. imports
SET ROLE tally_app;
SELECT pg_temp.refuses('J1 a CSV import with no file hash',
  $q$INSERT INTO public.import_jobs (tenant_id, initiated_by, import_type, source_type, source_filename, error_handling_policy)
     VALUES ('00000000-0000-4000-8000-0000000019a1', '00000000-0000-4000-8000-0000000019b1', 'payments', 'csv', 'feb.csv', 'all_or_nothing')$q$, '23514');
SELECT pg_temp.refuses('J1b a CSV import with no file name',
  $q$INSERT INTO public.import_jobs (tenant_id, initiated_by, import_type, source_type, source_file_hash, error_handling_policy)
     VALUES ('00000000-0000-4000-8000-0000000019a1', '00000000-0000-4000-8000-0000000019b1', 'payments', 'csv', 'h-x', 'all_or_nothing')$q$, '23514');
INSERT INTO public.import_jobs (id, tenant_id, initiated_by, import_type, source_type, source_filename, source_file_hash, error_handling_policy)
VALUES ('00000000-0000-4000-8000-0000000019b3', '00000000-0000-4000-8000-0000000019a1', '00000000-0000-4000-8000-0000000019b1', 'payments', 'csv', 'feb.csv', 'h-feb', 'all_or_nothing');
SELECT pg_temp.refuses('J2 the same file renamed',
  $q$INSERT INTO public.import_jobs (tenant_id, initiated_by, import_type, source_type, source_filename, source_file_hash, error_handling_policy)
     VALUES ('00000000-0000-4000-8000-0000000019a1', '00000000-0000-4000-8000-0000000019b1', 'payments', 'csv', 'feb-copy.csv', 'h-feb', 'all_or_nothing')$q$, '23505');
SELECT pg_temp.refuses('J2b the same file under a fresh caller key',
  $q$INSERT INTO public.import_jobs (tenant_id, initiated_by, import_type, source_type, source_filename, source_file_hash, error_handling_policy, idempotency_key)
     VALUES ('00000000-0000-4000-8000-0000000019a1', '00000000-0000-4000-8000-0000000019b1', 'payments', 'csv', 'feb.csv', 'h-feb', 'all_or_nothing', 'fresh-key')$q$, '23505');
-- r3 (Codex S1): its own file name and caller key, so only the file-wide
-- index can refuse it (not the idempotency key).
SELECT pg_temp.refuses_at('J2c the same file committed as another import type (r2, Opus S4)',
  $q$INSERT INTO public.import_jobs (tenant_id, initiated_by, import_type, source_type, source_filename, source_file_hash, error_handling_policy, idempotency_key)
     VALUES ('00000000-0000-4000-8000-0000000019a1', '00000000-0000-4000-8000-0000000019b1', 'lockbox', 'csv', 'feb-lockbox.csv', 'h-feb', 'all_or_nothing', 'j2c-key')$q$, '23505', 'import_jobs_file_once');
INSERT INTO public.import_jobs (id, tenant_id, initiated_by, import_type, source_type, source_filename, source_file_hash, error_handling_policy, is_dry_run)
VALUES ('00000000-0000-4000-8000-0000000019b6', '00000000-0000-4000-8000-0000000019a1', '00000000-0000-4000-8000-0000000019b1', 'payments', 'csv', 'feb.csv', 'h-feb', 'all_or_nothing', true);
UPDATE public.import_jobs SET status = 'complete' WHERE id = '00000000-0000-4000-8000-0000000019b6';
INSERT INTO public.import_jobs (tenant_id, initiated_by, import_type, source_type, source_filename, source_file_hash, error_handling_policy, is_dry_run, idempotency_key)
VALUES ('00000000-0000-4000-8000-0000000019a1', '00000000-0000-4000-8000-0000000019b1', 'payments', 'csv', 'feb.csv', 'h-feb', 'all_or_nothing', true, 'preview-2');
DO $$ BEGIN RAISE NOTICE 'PASS J3: previews of the same file are their own jobs, and a finished preview blocks no later one'; END $$;
-- r2 (Opus B5, Fable B2): the slot cannot be freed by editing the job.
SELECT pg_temp.refuses('J6 a live job''s file hash rewritten', $q$UPDATE public.import_jobs SET source_file_hash = 'h-other' WHERE id = '00000000-0000-4000-8000-0000000019b3'$q$, '23001');
SELECT pg_temp.refuses('J6b a live commit turned into a preview', $q$UPDATE public.import_jobs SET is_dry_run = true WHERE id = '00000000-0000-4000-8000-0000000019b3'$q$, '23001');
SELECT pg_temp.refuses('J6c a live job''s import type changed', $q$UPDATE public.import_jobs SET import_type = 'lockbox' WHERE id = '00000000-0000-4000-8000-0000000019b3'$q$, '23001');
UPDATE public.import_jobs SET status = 'failed' WHERE id = '00000000-0000-4000-8000-0000000019b3';
SELECT pg_temp.refuses('J7 a failed job revived', $q$UPDATE public.import_jobs SET status = 'pending' WHERE id = '00000000-0000-4000-8000-0000000019b3'$q$, '23001');
INSERT INTO public.import_jobs (id, tenant_id, initiated_by, import_type, source_type, source_filename, source_file_hash, error_handling_policy, idempotency_key)
VALUES ('00000000-0000-4000-8000-0000000019b5', '00000000-0000-4000-8000-0000000019a1', '00000000-0000-4000-8000-0000000019b1', 'payments', 'csv', 'feb.csv', 'h-feb', 'all_or_nothing', 'feb.csv:h-feb:commit:retry-1');
DO $$ BEGIN RAISE NOTICE 'PASS J4: a failed job frees the file for a retry (CI-118)'; END $$;
UPDATE public.import_jobs SET status = 'complete' WHERE id = '00000000-0000-4000-8000-0000000019b5';
SELECT pg_temp.refuses('J8 a completed import cancelled (to free the file)', $q$UPDATE public.import_jobs SET status = 'cancelled' WHERE id = '00000000-0000-4000-8000-0000000019b5'$q$, '23001');
-- r3 (Opus S2): a finished job's stored file and counts are its record.
SELECT pg_temp.refuses_at('J10 a completed import''s stored file repointed', $q$UPDATE public.import_jobs SET source_file_url = 's3://f/other.csv' WHERE id = '00000000-0000-4000-8000-0000000019b5'$q$, '23001', 'source_file_url');
SELECT pg_temp.refuses_at('J10b a completed import''s committed rows rewritten', $q$UPDATE public.import_jobs SET committed_rows = 99 WHERE id = '00000000-0000-4000-8000-0000000019b5'$q$, '23001', 'row counts');
SELECT pg_temp.refuses('J9 the same file imported again after completion',
  $q$INSERT INTO public.import_jobs (tenant_id, initiated_by, import_type, source_type, source_filename, source_file_hash, error_handling_policy, idempotency_key)
     VALUES ('00000000-0000-4000-8000-0000000019a1', '00000000-0000-4000-8000-0000000019b1', 'payments', 'csv', 'feb-again.csv', 'h-feb', 'all_or_nothing', 'again')$q$, '23505');
INSERT INTO public.import_jobs (tenant_id, initiated_by, import_type, source_type, source_filename, source_file_hash, error_handling_policy)
VALUES ('00000000-0000-4000-8000-0000000019a1', '00000000-0000-4000-8000-0000000019b1', 'ach_return', 'csv', 'ret.csv', 'h-ret', 'partial_commit');
DO $$ BEGIN RAISE NOTICE 'PASS J5: an ACH return file is a typed import (CI-098)'; END $$;
RESET ROLE;


-- ================================================================= E. programs
SET ROLE tally_app;
SELECT pg_temp.refuses('E1 an active medical hold with no certificate',
  $q$INSERT INTO public.customer_program_enrollments (tenant_id, customer_id, program_type, effective_start_date, status)
     VALUES ('00000000-0000-4000-8000-0000000019a1', '00000000-0000-4000-8000-0000000019c1', 'medical_certificate', DATE '2026-01-01', 'active')$q$, '23514');
INSERT INTO public.customer_program_enrollments (id, tenant_id, customer_id, program_type, effective_start_date, status)
VALUES ('00000000-0000-4000-8000-0000000019b4', '00000000-0000-4000-8000-0000000019a1', '00000000-0000-4000-8000-0000000019c1', 'medical_certificate', DATE '2026-01-01', 'pending_application');
DO $$ BEGIN RAISE NOTICE 'PASS E2: an application may wait for its certificate'; END $$;
SELECT pg_temp.refuses('E3 activated before the certificate arrives',
  $q$UPDATE public.customer_program_enrollments SET status = 'active' WHERE id = '00000000-0000-4000-8000-0000000019b4'$q$, '23514');
SELECT pg_temp.refuses('E3b verified with no verifier',
  $q$UPDATE public.customer_program_enrollments SET attestation_received_at = now(), attestation_verified_at = now() WHERE id = '00000000-0000-4000-8000-0000000019b4'$q$, '23514');
SELECT pg_temp.refuses('E3c verified before it was received',
  $q$UPDATE public.customer_program_enrollments SET attestation_received_at = now(), attestation_verified_at = now() - interval '1 day',
            attestation_verified_by = '00000000-0000-4000-8000-0000000019b1' WHERE id = '00000000-0000-4000-8000-0000000019b4'$q$, '23514');
UPDATE public.customer_program_enrollments
   SET status = 'active', attestation_artifact_url = 's3://certs/c1.pdf', attestation_received_at = now()
 WHERE id = '00000000-0000-4000-8000-0000000019b4';
SELECT pg_temp.refuses('E4 the certificate removed from an active hold',
  $q$UPDATE public.customer_program_enrollments SET attestation_artifact_url = NULL WHERE id = '00000000-0000-4000-8000-0000000019b4'$q$, '23514');
INSERT INTO public.customer_program_enrollments (tenant_id, customer_id, program_type, effective_start_date, status)
VALUES ('00000000-0000-4000-8000-0000000019a1', '00000000-0000-4000-8000-0000000019c2', 'budget_billing', DATE '2026-01-01', 'active');
DO $$ BEGIN RAISE NOTICE 'PASS E5: an active hold carries its certificate (CI-062); other programs need none'; END $$;
RESET ROLE;


-- ================================================================== B. balance
INSERT INTO public.account_ledger (tenant_id, customer_id, transaction_date, transaction_type, description, amount, created_at) VALUES
  ('00000000-0000-4000-8000-0000000019a1', '00000000-0000-4000-8000-0000000019c1', DATE '2026-01-31', 'charge',  'bill',     100.00, TIMESTAMPTZ '2026-02-01 00:00Z'),
  ('00000000-0000-4000-8000-0000000019a1', '00000000-0000-4000-8000-0000000019c1', DATE '2026-02-10', 'payment', 'paid',     -40.00, TIMESTAMPTZ '2026-02-10 00:00Z'),
  ('00000000-0000-4000-8000-0000000019a1', '00000000-0000-4000-8000-0000000019c1', DATE '2026-01-31', 'adjustment', 'late', -10.00, TIMESTAMPTZ '2026-03-01 00:00Z');
SET ROLE tally_app;
DO $$ BEGIN
  IF public.account_balance_as_of('00000000-0000-4000-8000-0000000019c1', DATE '2026-12-31', TIMESTAMPTZ '2026-12-31 00:00Z') IS DISTINCT FROM 50.00
     OR public.account_balance_as_of('00000000-0000-4000-8000-0000000019c1', DATE '2026-01-31', TIMESTAMPTZ '2026-12-31 00:00Z') IS DISTINCT FROM 90.00
     OR public.account_balance_as_of('00000000-0000-4000-8000-0000000019c1', DATE '2026-01-31', TIMESTAMPTZ '2026-02-15 00:00Z') IS DISTINCT FROM 100.00
     OR public.account_balance_as_of('00000000-0000-4000-8000-0000000019c2', DATE '2026-12-31', now()) IS DISTINCT FROM 1.00
     OR public.account_balance_as_of('00000000-0000-4000-8000-0000000019c2', DATE '2026-12-31', now() - interval '1 second') IS DISTINCT FROM 0 THEN
    RAISE EXCEPTION 'FAIL B1: account_balance_as_of returned a wrong balance';
  END IF;
  RAISE NOTICE 'PASS B1: the balance by date and by what was recorded then (a late adjustment dated back is seen only after it was recorded)';
END $$;
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'account_ledger' AND column_name = 'running_balance')
     OR EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'compute_ledger_running_balance')
     OR EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'void_invoice' AND strpos(prosrc, 'running_balance') > 0) THEN
    RAISE EXCEPTION 'FAIL B4: the stored running balance (column, trigger function or a reader) remains';
  END IF;
  RAISE NOTICE 'PASS B4: the stored running balance is gone; void_invoice() sums the ledger (CI-019, Ryan 2026-10-13)';
END $$;
SELECT pg_temp.refuses('B2 no recorded coordinate', $q$SELECT public.account_balance_as_of('00000000-0000-4000-8000-0000000019c1', DATE '2026-12-31', NULL)$q$, '22004');
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000019b2', true);
SELECT pg_temp.refuses('B3 another tenant''s customer', $q$SELECT public.account_balance_as_of('00000000-0000-4000-8000-0000000019c1', DATE '2026-12-31', now())$q$, 'P0002');
SELECT set_config('app.user_id', '00000000-0000-4000-8000-0000000019b1', true);
RESET ROLE;

DO $$ BEGIN
  PERFORM public.assert_tenant_isolation_invariants();
  PERFORM public.assert_core_role_invariants();
  RAISE NOTICE 'PASS G1: tenant isolation and core-role invariants hold after the patch';
END $$;

-- I5/I6 (r2, Fable S3): an issued bill's image and fingerprint are frozen.
-- The issued fixture has no calculation snapshot: it exists only while the
-- snapshot check is deferred, so this section runs last and is rolled back.
SET CONSTRAINTS ALL DEFERRED;
INSERT INTO public.invoices (id, tenant_id, invoice_number, customer_id, location_id, invoice_date, billing_period, period_start, period_end, due_date, status, pdf_url, pdf_sha256)
VALUES ('00000000-0000-4000-8000-000000001903', '00000000-0000-4000-8000-0000000019a1', 'I3', '00000000-0000-4000-8000-0000000019c1', '00000000-0000-4000-8000-0000000019d1',
        '2026-02-01', '2026-01', '2026-01-01', '2026-01-31', '2026-02-20', 'pending', 's3://bills/I3.pdf', repeat('c', 64));
SET ROLE tally_app;
SELECT pg_temp.refuses('I5 an issued bill''s fingerprint rewritten', $q$UPDATE public.invoices SET pdf_sha256 = repeat('d', 64) WHERE id = '00000000-0000-4000-8000-000000001903'$q$, '23001');
SELECT pg_temp.refuses('I6 an issued bill''s image and fingerprint replaced together', $q$UPDATE public.invoices SET pdf_url = 's3://bills/I3-v2.pdf', pdf_sha256 = repeat('d', 64) WHERE id = '00000000-0000-4000-8000-000000001903'$q$, '23001');
RESET ROLE;

-- B5 (r3, Codex S1): void_invoice() returns the customer's summed ledger
-- balance. C2 holds 1.00 (L8); its bill of 30.00 is charged and voided, so
-- the balance after the reversal is 1.00 again. C1's rows and another
-- tenant's must not count; a stub returning 0 would fail.
INSERT INTO public.invoices (id, tenant_id, invoice_number, customer_id, location_id, invoice_date, billing_period, period_start, period_end, due_date, status, amount_due)
VALUES ('00000000-0000-4000-8000-000000001904', '00000000-0000-4000-8000-0000000019a1', 'I4', '00000000-0000-4000-8000-0000000019c2', '00000000-0000-4000-8000-0000000019d1',
        '2026-02-01', '2026-01', '2026-01-01', '2026-01-31', '2026-02-20', 'pending', 30.00);
INSERT INTO public.account_ledger (tenant_id, customer_id, transaction_date, transaction_type, description, amount) VALUES
  ('00000000-0000-4000-8000-0000000019a1', '00000000-0000-4000-8000-0000000019c2', DATE '2026-02-01', 'charge', 'bill I4', 30.00),
  ('00000000-0000-4000-8000-0000000019a2', '00000000-0000-4000-8000-0000000019c9', DATE '2026-02-01', 'charge', 'other tenant', 70.00);
SET ROLE tally_app;
DO $$
DECLARE v jsonb;
BEGIN
  v := public.void_invoice('00000000-0000-4000-8000-000000001904', '00000000-0000-4000-8000-0000000019b1', 'wrong_customer', 'battery-19 B5', true);
  IF (v ->> 'credit_balance')::numeric IS DISTINCT FROM 1.00
     OR (v ->> 'reversal_amount')::numeric IS DISTINCT FROM -30.00
     OR (v ->> 'credit_balance')::numeric IS DISTINCT FROM public.account_balance_as_of('00000000-0000-4000-8000-0000000019c2', DATE '2999-12-31', now()) THEN
    RAISE EXCEPTION 'FAIL B5: void_invoice() returned %', v;
  END IF;
  RAISE NOTICE 'PASS B5: void_invoice() returns the customer''s summed balance after the reversal (1.00), the same as account_balance_as_of';
END $$;
RESET ROLE;

DO $$ BEGIN RAISE NOTICE 'battery-19: complete'; END $$;
ROLLBACK;
