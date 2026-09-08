-- ============================================================================
-- BATTERY v5.4.2-10 — A-3 follow-up: snapshot coordinate binding
-- Run: psql -U tally -d <db-with-patch> -v ON_ERROR_STOP=1 -f battery-10.sql
-- One transaction, rolled back. Negative cases inside DO exception handlers.
-- End-to-end writes as tally_app (SET ROLE) with app.user_id context.
-- now() is constant inside the transaction: every "now"-shaped timestamp is
-- the same instant, so the original-world branch (F13) seeds its original
-- through the superuser exemption on billing_runs.started_at.
-- ============================================================================
BEGIN;
SET CONSTRAINTS ALL IMMEDIATE;

-- ---------------------------------------------------------------- fixtures
INSERT INTO public.tenants (id, name, slug) VALUES
  ('00000000-0000-4000-8000-00000000aa01', 'T1 Gasco', 'bat10-t1');
INSERT INTO public.users (id, tenant_id, display_name, email, role) VALUES
  ('00000000-0000-4000-8000-00000000ab01', '00000000-0000-4000-8000-00000000aa01', 'U1', 'u1@bat10.test', 'operator');
INSERT INTO public.customers (id, tenant_id, customer_number) VALUES
  ('00000000-0000-4000-8000-00000000ac01', '00000000-0000-4000-8000-00000000aa01', 'BAT10-C1');
INSERT INTO public.service_locations (id, tenant_id, customer_id, location_number, address_line1, city, state, zip) VALUES
  ('00000000-0000-4000-8000-00000000ad01', '00000000-0000-4000-8000-00000000aa01', '00000000-0000-4000-8000-00000000ac01', 'LOC-1', '1 Main', 'Austin', 'TX', '78701');
INSERT INTO public.meters (id, tenant_id, meter_number, location_id, service_type) VALUES
  ('00000000-0000-4000-8000-00000000ae01', '00000000-0000-4000-8000-00000000aa01', 'M-1', '00000000-0000-4000-8000-00000000ad01', 'gas');

-- A helper: a minimal v1 snapshot body for an invoice (as superuser-defined
-- SQL; parameters prefixed p_ — the shadowing lesson).
CREATE FUNCTION pg_temp.snap(p_inv uuid, p_valid date, p_rec timestamptz) RETURNS void LANGUAGE plpgsql AS $$
DECLARE i public.invoices%ROWTYPE;
BEGIN
  SELECT * INTO i FROM public.invoices WHERE id = p_inv;
  INSERT INTO public.invoice_calculation_snapshots
    (tenant_id, invoice_id, billing_run_id, valid_at, recorded_at, snapshot_schema_version, formula_version,
     rate_inputs, gas_factors, wna_inputs, tax_inputs, read_inputs, customer_inputs, period_inputs, line_items)
  VALUES (i.tenant_id, i.id, i.billing_run_id, p_valid, p_rec, 'v1', 'bat10',
     '{"rate_schedule_id":null,"rate_schedule_version_id":null,"rate_schedule_code":null,"customer_type":null,"partial_period_policy":null,"items":[]}',
     '{"pga_factor":null,"btu_factor":null,"pressure_factor":null,"temperature_factor":null,"meter_multiplier":null,"factor_stack_intermediates":{}}',
     '{"applied":false}',
     '{"jurisdictions":[],"exemptions":[],"franchise_fees":[]}',
     '{"reads":[]}',
     jsonb_build_object('customer_id', i.customer_id, 'customer_class', null, 'location_id', i.location_id, 'premise_zones', '{}'::jsonb),
     jsonb_build_object('period_start', i.period_start, 'period_end', i.period_end, 'days_in_period', i.period_end - i.period_start + 1, 'proration_policy', null),
     (SELECT coalesce(jsonb_agg(jsonb_build_object('invoice_line_item_id', l.id, 'charge_type', l.charge_type, 'amount', l.amount)), '[]'::jsonb)
        FROM public.invoice_line_items l WHERE l.invoice_id = i.id));
END $$;
GRANT EXECUTE ON FUNCTION pg_temp.snap(uuid, date, timestamptz) TO tally_app;

CREATE FUNCTION pg_temp.inv(p_id uuid, p_num text, p_run uuid, p_type text, p_replaces uuid, p_ps date, p_pe date) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO public.invoices (id, tenant_id, invoice_number, billing_run_id, customer_id, location_id, invoice_type, replaces_invoice_id,
                               invoice_date, billing_period, period_start, period_end, due_date)
  VALUES (p_id, '00000000-0000-4000-8000-00000000aa01', p_num, p_run, '00000000-0000-4000-8000-00000000ac01', '00000000-0000-4000-8000-00000000ad01',
          p_type, p_replaces, p_pe + 1, to_char(p_pe, 'YYYY-MM'), p_ps, p_pe, p_pe + 21);
  INSERT INTO public.invoice_line_items (tenant_id, invoice_id, service_type, charge_type, description, amount)
  VALUES ('00000000-0000-4000-8000-00000000aa01', p_id, 'gas', 'base_charge', 'Customer charge', 12.50);
END $$;
GRANT EXECUTE ON FUNCTION pg_temp.inv(uuid, text, uuid, text, uuid, date, date) TO tally_app;

-- The ORIGINAL bill for the correction cases, seeded as superuser with a
-- backdated run clock (the exemption exists for migrations; here it stands
-- in for "a run that happened last year").
INSERT INTO public.billing_runs (id, tenant_id, run_number, billing_period, period_start, period_end, run_type, status, started_at) VALUES
  ('00000000-0000-4000-8000-00000000b001', '00000000-0000-4000-8000-00000000aa01', 'RUN-2025-06', '2025-06', '2025-06-01', '2025-06-30', 'regular', 'in_progress', '2025-07-01 09:00-05');
DO $$ DECLARE s timestamptz; BEGIN
  SELECT started_at INTO s FROM public.billing_runs WHERE id = '00000000-0000-4000-8000-00000000b001';
  IF s <> '2025-07-01 09:00-05' THEN RAISE EXCEPTION 'F0 FAILED: superuser started_at was overwritten (%)', s; END IF;
  RAISE NOTICE 'PASS F0: superuser (migration) may write billing_runs.started_at directly';
END $$;
SELECT pg_temp.inv('00000000-0000-4000-8000-00000000c001', 'INV-ORIG', '00000000-0000-4000-8000-00000000b001', 'regular', NULL, '2025-06-01', '2025-06-30');
UPDATE public.invoices SET created_at = '2025-07-01 09:05-05' WHERE id = '00000000-0000-4000-8000-00000000c001';  -- superuser: allowed (no snapshot yet; stamping is INSERT-only)
SELECT pg_temp.snap('00000000-0000-4000-8000-00000000c001', '2025-06-30', '2025-07-01 09:10-05');
UPDATE public.invoices SET status = 'pending' WHERE id = '00000000-0000-4000-8000-00000000c001';
DO $$ BEGIN RAISE NOTICE 'PASS F0b: original 2025 bill issued with a 2025 coordinate inside its (backdated) run window'; END $$;
-- a NON-void issued bill, kept as the decoy for F22
SELECT pg_temp.inv('00000000-0000-4000-8000-00000000c002', 'INV-LIVE', '00000000-0000-4000-8000-00000000b001', 'regular', NULL, '2025-06-01', '2025-06-30');
SELECT pg_temp.snap('00000000-0000-4000-8000-00000000c002', '2025-06-30', '2025-07-01 09:10-05');
UPDATE public.invoices SET status = 'pending' WHERE id = '00000000-0000-4000-8000-00000000c002';
-- void the original (the only route to void — A-4)
SELECT public.void_invoice('00000000-0000-4000-8000-00000000c001', '00000000-0000-4000-8000-00000000ab01', 'wrong_rate', 'battery: original to be corrected', true);
DO $$ DECLARE st text; BEGIN
  SELECT status INTO st FROM public.invoices WHERE id = '00000000-0000-4000-8000-00000000c001';
  IF st <> 'void' THEN RAISE EXCEPTION 'F0c FAILED: original not void (%)', st; END IF;
  RAISE NOTICE 'PASS F0c: original voided through void_invoice(); its 2025 snapshot is sealed with it';
END $$;
DO $$ DECLARE f timestamptz; BEGIN
  SELECT first_issued_at INTO f FROM public.invoices WHERE id = '00000000-0000-4000-8000-00000000c001';
  IF f IS DISTINCT FROM now() THEN RAISE EXCEPTION 'F29a FAILED: first_issued_at not stamped on issuance (%)', f; END IF;
  RAISE NOTICE 'PASS F29a: first_issued_at stamped by the database on the first issuance, kept through void';
END $$;

-- ------------------------------------------------------------ as tally_app
SET LOCAL app.user_id = '00000000-0000-4000-8000-00000000ab01';
SET ROLE tally_app;

-- F1: a run inserted with a caller-supplied started_at is stamped now()
INSERT INTO public.billing_runs (id, tenant_id, run_number, billing_period, period_start, period_end, run_type, status, started_at) VALUES
  ('00000000-0000-4000-8000-00000000b101', '00000000-0000-4000-8000-00000000aa01', 'RUN-R1', '2026-03', '2026-03-01', '2026-03-31', 'regular', 'in_progress', '2020-01-01');
DO $$ DECLARE s timestamptz; BEGIN
  SELECT started_at INTO s FROM public.billing_runs WHERE id = '00000000-0000-4000-8000-00000000b101';
  IF s <> now() THEN RAISE EXCEPTION 'F1 FAILED: started_at % not stamped now()', s; END IF;
  RAISE NOTICE 'PASS F1: caller-supplied started_at on INSERT is overwritten with now()';
END $$;

-- F2: started_at is write-once
DO $$ BEGIN
  UPDATE public.billing_runs SET started_at = '2020-01-01' WHERE id = '00000000-0000-4000-8000-00000000b101';
  RAISE EXCEPTION 'F2 FAILED: started_at moved';
EXCEPTION WHEN restrict_violation THEN RAISE NOTICE 'PASS F2: started_at is write-once (%)', left(SQLERRM, 60); END $$;

-- F3: an unstarted run cannot receive a snapshot; starting it stamps now()
INSERT INTO public.billing_runs (id, tenant_id, run_number, billing_period, period_start, period_end, run_type, status) VALUES
  ('00000000-0000-4000-8000-00000000b102', '00000000-0000-4000-8000-00000000aa01', 'RUN-R2', '2026-03', '2026-03-01', '2026-03-31', 'regular', 'pending');
SELECT pg_temp.inv('00000000-0000-4000-8000-00000000c102', 'INV-R2-1', '00000000-0000-4000-8000-00000000b102', 'regular', NULL, '2026-03-01', '2026-03-31');
DO $$ BEGIN
  PERFORM pg_temp.snap('00000000-0000-4000-8000-00000000c102', '2026-03-31', now());
  RAISE EXCEPTION 'F3 FAILED: snapshot accepted on an unstarted run';
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'PASS F3a: snapshot on an unstarted run refused (%)', left(SQLERRM, 70); END $$;
UPDATE public.billing_runs SET started_at = '2019-01-01', status = 'in_progress' WHERE id = '00000000-0000-4000-8000-00000000b102';
DO $$ DECLARE s timestamptz; BEGIN
  SELECT started_at INTO s FROM public.billing_runs WHERE id = '00000000-0000-4000-8000-00000000b102';
  IF s <> now() THEN RAISE EXCEPTION 'F3b FAILED: NULL -> value started_at % not stamped now()', s; END IF;
  RAISE NOTICE 'PASS F3b: NULL -> value started_at is stamped now()';
END $$;
SELECT pg_temp.snap('00000000-0000-4000-8000-00000000c102', '2026-03-31', now());
DO $$ BEGIN RAISE NOTICE 'PASS F3c: after the run started, the same snapshot lands'; END $$;

-- F4: invoices.created_at is stamped now() on INSERT
INSERT INTO public.invoices (id, tenant_id, invoice_number, customer_id, location_id, invoice_date, billing_period, period_start, period_end, due_date, created_at)
VALUES ('00000000-0000-4000-8000-00000000c104', '00000000-0000-4000-8000-00000000aa01', 'INV-OFF-1', '00000000-0000-4000-8000-00000000ac01', '00000000-0000-4000-8000-00000000ad01',
        '2026-04-01', '2026-03', '2026-03-01', '2026-03-31', '2026-04-22', '2020-01-01');
DO $$ DECLARE c timestamptz; BEGIN
  SELECT created_at INTO c FROM public.invoices WHERE id = '00000000-0000-4000-8000-00000000c104';
  IF c <> now() THEN RAISE EXCEPTION 'F4 FAILED: created_at % not stamped', c; END IF;
  RAISE NOTICE 'PASS F4: caller-supplied invoices.created_at is overwritten with now()';
END $$;
INSERT INTO public.invoice_line_items (tenant_id, invoice_id, service_type, charge_type, description, amount)
VALUES ('00000000-0000-4000-8000-00000000aa01', '00000000-0000-4000-8000-00000000c104', 'gas', 'base_charge', 'Customer charge', 12.50);
DO $$ BEGIN
  UPDATE public.invoices SET first_issued_at = '2020-01-01' WHERE id = '00000000-0000-4000-8000-00000000c104';
  RAISE EXCEPTION 'F29b FAILED: first_issued_at caller-written';
EXCEPTION WHEN restrict_violation THEN RAISE NOTICE 'PASS F29b: first_issued_at cannot be written by the app role'; END $$;
INSERT INTO public.invoices (id, tenant_id, invoice_number, customer_id, location_id, invoice_date, billing_period, period_start, period_end, due_date, first_issued_at)
VALUES ('00000000-0000-4000-8000-00000000c110', '00000000-0000-4000-8000-00000000aa01', 'INV-FI', '00000000-0000-4000-8000-00000000ac01', '00000000-0000-4000-8000-00000000ad01',
        '2026-04-01', '2026-03', '2026-03-01', '2026-03-31', '2026-04-22', '2020-01-01');
DO $$ DECLARE f timestamptz; BEGIN
  SELECT first_issued_at INTO f FROM public.invoices WHERE id = '00000000-0000-4000-8000-00000000c110';
  IF f IS NOT NULL THEN RAISE EXCEPTION 'F29c FAILED: first_issued_at supplied at INSERT kept (%)', f; END IF;
  RAISE NOTICE 'PASS F29c: first_issued_at supplied at INSERT is discarded';
END $$;

-- F5/F6/F7: ordinary on-run binding
SELECT pg_temp.inv('00000000-0000-4000-8000-00000000c101', 'INV-R1-1', '00000000-0000-4000-8000-00000000b101', 'regular', NULL, '2026-03-01', '2026-03-31');
DO $$ BEGIN
  PERFORM pg_temp.snap('00000000-0000-4000-8000-00000000c101', '2026-03-30', now());
  RAISE EXCEPTION 'F6 FAILED: valid_at inside the period but not period_end accepted';
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'PASS F6: valid_at = period_end - 1 refused (strict: exactly period_end)'; END $$;
DO $$ BEGIN
  PERFORM pg_temp.snap('00000000-0000-4000-8000-00000000c101', '2026-03-31', now() - interval '1 second');
  RAISE EXCEPTION 'F7 FAILED: recorded_at before the run started accepted';
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'PASS F7: recorded_at one second before run.started_at refused'; END $$;
DO $$ BEGIN
  PERFORM pg_temp.snap('00000000-0000-4000-8000-00000000c101', '2026-03-31', now() + interval '1 second');
  RAISE EXCEPTION 'F7b FAILED: future recorded_at accepted';
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'PASS F7b: future recorded_at still refused'; END $$;
SELECT pg_temp.snap('00000000-0000-4000-8000-00000000c101', '2026-03-31', now());
DO $$ BEGIN RAISE NOTICE 'PASS F5: ordinary snapshot at (period_end, now()) lands'; END $$;

-- F8/F9: ordinary off-run binding
DO $$ BEGIN
  PERFORM pg_temp.snap('00000000-0000-4000-8000-00000000c104', '2026-03-31', now() - interval '1 second');
  RAISE EXCEPTION 'F8 FAILED: recorded_at before the draft''s creation accepted';
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'PASS F8: off-run recorded_at before invoices.created_at refused'; END $$;
SELECT pg_temp.snap('00000000-0000-4000-8000-00000000c104', '2026-03-31', now());
DO $$ BEGIN RAISE NOTICE 'PASS F9: off-run snapshot at (period_end, created_at) lands'; END $$;

-- F10: a snapshotted draft's binding inputs are frozen; notes are not
DO $$ BEGIN
  UPDATE public.invoices SET period_end = '2026-04-02' WHERE id = '00000000-0000-4000-8000-00000000c101';
  RAISE EXCEPTION 'F10a FAILED: period_end moved under a snapshot';
EXCEPTION WHEN restrict_violation THEN RAISE NOTICE 'PASS F10a: period_end frozen while a snapshot exists'; END $$;
DO $$ BEGIN
  UPDATE public.invoices SET invoice_type = 'correction', replaces_invoice_id = '00000000-0000-4000-8000-00000000c001' WHERE id = '00000000-0000-4000-8000-00000000c101';
  RAISE EXCEPTION 'F10b FAILED: invoice_type/replaces changed under a snapshot';
EXCEPTION WHEN restrict_violation THEN RAISE NOTICE 'PASS F10b: invoice_type / replaces_invoice_id frozen while a snapshot exists'; END $$;
DO $$ BEGIN
  UPDATE public.invoices SET created_at = '2020-01-01' WHERE id = '00000000-0000-4000-8000-00000000c104';
  RAISE EXCEPTION 'F10c FAILED: created_at moved under a snapshot';
EXCEPTION WHEN restrict_violation THEN RAISE NOTICE 'PASS F10c: created_at frozen while a snapshot exists'; END $$;
UPDATE public.invoices SET notes = 'fine' WHERE id = '00000000-0000-4000-8000-00000000c101';
DELETE FROM public.invoice_calculation_snapshots WHERE invoice_id = '00000000-0000-4000-8000-00000000c101';
UPDATE public.invoices SET period_end = '2026-04-02', due_date = '2026-04-23' WHERE id = '00000000-0000-4000-8000-00000000c101';
UPDATE public.invoices SET period_end = '2026-03-31', due_date = '2026-04-21' WHERE id = '00000000-0000-4000-8000-00000000c101';
SELECT pg_temp.snap('00000000-0000-4000-8000-00000000c101', '2026-03-31', now());
DO $$ BEGIN RAISE NOTICE 'PASS F10d: notes edit free; delete snapshot -> edit period -> re-snapshot works'; END $$;

-- F21: created_at is write-once even with NO snapshot (Fable CRITICAL-1, round 1)
SELECT pg_temp.inv('00000000-0000-4000-8000-00000000c107', 'INV-OFF-2', NULL, 'regular', NULL, '2026-03-01', '2026-03-31');
DO $$ BEGIN
  UPDATE public.invoices SET created_at = '2020-01-01' WHERE id = '00000000-0000-4000-8000-00000000c107';
  RAISE EXCEPTION 'F21a FAILED: created_at moved on an unsnapshotted draft';
EXCEPTION WHEN restrict_violation THEN RAISE NOTICE 'PASS F21a: created_at write-once on an unsnapshotted draft (the round-1 CRITICAL)'; END $$;
-- the re-home variant: on-run draft moved off-run, then backdated
SELECT pg_temp.inv('00000000-0000-4000-8000-00000000c108', 'INV-REHOME', '00000000-0000-4000-8000-00000000b101', 'regular', NULL, '2026-03-01', '2026-03-31');
UPDATE public.invoices SET billing_run_id = NULL WHERE id = '00000000-0000-4000-8000-00000000c108';
DO $$ BEGIN
  UPDATE public.invoices SET created_at = '2019-06-01' WHERE id = '00000000-0000-4000-8000-00000000c108';
  RAISE EXCEPTION 'F21b FAILED: re-homed draft backdated';
EXCEPTION WHEN restrict_violation THEN RAISE NOTICE 'PASS F21b: re-homing off-run is free, backdating created_at afterwards is not'; END $$;
DO $$ BEGIN
  PERFORM pg_temp.snap('00000000-0000-4000-8000-00000000c108', '2026-03-31', '2019-06-01');
  RAISE EXCEPTION 'F21c FAILED: 2019 recorded_at accepted on a re-homed draft';
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'PASS F21c: re-homed draft still bounded by its stamped created_at'; END $$;

-- F11: correction invoices need lineage, a correction run and a target row
INSERT INTO public.billing_runs (id, tenant_id, run_number, billing_period, period_start, period_end, run_type, status, started_at, correction_rate_mode) VALUES
  ('00000000-0000-4000-8000-00000000b201', '00000000-0000-4000-8000-00000000aa01', 'RUN-C1', '2025-06', '2025-06-01', '2025-06-30', 'correction', 'in_progress', now(), 'historical');
SELECT pg_temp.inv('00000000-0000-4000-8000-00000000c201', 'INV-CORR-NOLINK', '00000000-0000-4000-8000-00000000b201', 'correction', NULL, '2025-06-01', '2025-06-30');
DO $$ BEGIN
  PERFORM pg_temp.snap('00000000-0000-4000-8000-00000000c201', '2025-06-30', now());
  RAISE EXCEPTION 'F11a FAILED: correction without replaces_invoice_id accepted';
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'PASS F11a: correction without replaces_invoice_id refused'; END $$;
SELECT pg_temp.inv('00000000-0000-4000-8000-00000000c202', 'INV-CORR-OFFRUN', NULL, 'correction', '00000000-0000-4000-8000-00000000c001', '2025-06-01', '2025-06-30');
DO $$ BEGIN
  PERFORM pg_temp.snap('00000000-0000-4000-8000-00000000c202', '2025-06-30', now());
  RAISE EXCEPTION 'F11b FAILED: off-run correction accepted';
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'PASS F11b: off-run correction refused (strict: no target row, no snapshot)'; END $$;
SELECT pg_temp.inv('00000000-0000-4000-8000-00000000c203', 'INV-CORR-REGRUN', '00000000-0000-4000-8000-00000000b101', 'correction', '00000000-0000-4000-8000-00000000c001', '2025-06-01', '2025-06-30');
DO $$ BEGIN
  PERFORM pg_temp.snap('00000000-0000-4000-8000-00000000c203', '2025-06-30', now());
  RAISE EXCEPTION 'F11c FAILED: correction on a regular run accepted';
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'PASS F11c: correction on a run of run_type regular refused'; END $$;
SELECT pg_temp.inv('00000000-0000-4000-8000-00000000c204', 'INV-CORR-1', '00000000-0000-4000-8000-00000000b201', 'correction', '00000000-0000-4000-8000-00000000c001', '2025-06-01', '2025-06-30');
DO $$ BEGIN
  PERFORM pg_temp.snap('00000000-0000-4000-8000-00000000c204', '2025-06-30', now());
  RAISE EXCEPTION 'F11d FAILED: correction with no target row accepted';
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'PASS F11d: correction with no correction_run_targets row refused'; END $$;

-- F22: the replaced bill must be VOID (Fable HIGH-2/3, Codex MEDIUM-3, round 1)
SELECT pg_temp.inv('00000000-0000-4000-8000-00000000c206', 'INV-CORR-LIVE', '00000000-0000-4000-8000-00000000b201', 'correction', '00000000-0000-4000-8000-00000000c002', '2025-06-01', '2025-06-30');
INSERT INTO public.correction_run_targets (id, tenant_id, billing_run_id, voided_invoice_id, meter_id, customer_id) VALUES
  ('00000000-0000-4000-8000-00000000d206', '00000000-0000-4000-8000-00000000aa01', '00000000-0000-4000-8000-00000000b201', '00000000-0000-4000-8000-00000000c002',
   '00000000-0000-4000-8000-00000000ae01', '00000000-0000-4000-8000-00000000ac01');
DO $$ BEGIN
  PERFORM pg_temp.snap('00000000-0000-4000-8000-00000000c206', '2025-06-30', now());
  RAISE EXCEPTION 'F22 FAILED: correction of a live (pending) bill accepted';
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'PASS F22: correction replacing a non-void bill refused (%)', left(SQLERRM, 70); END $$;

-- F12: historical election -> valid_at = voided bill's period_end
INSERT INTO public.correction_run_targets (id, tenant_id, billing_run_id, voided_invoice_id, meter_id, customer_id) VALUES
  ('00000000-0000-4000-8000-00000000d201', '00000000-0000-4000-8000-00000000aa01', '00000000-0000-4000-8000-00000000b201', '00000000-0000-4000-8000-00000000c001',
   '00000000-0000-4000-8000-00000000ae01', '00000000-0000-4000-8000-00000000ac01');
DO $$ BEGIN
  PERFORM pg_temp.snap('00000000-0000-4000-8000-00000000c204', CURRENT_DATE, now());
  RAISE EXCEPTION 'F12a FAILED: historical election accepted a current-date valid_at';
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'PASS F12a: historical election refuses valid_at = today (%)', left(SQLERRM, 60); END $$;
-- F13: recorded_at — this run's window, or exactly the original's instant
DO $$ BEGIN
  PERFORM pg_temp.snap('00000000-0000-4000-8000-00000000c204', '2025-06-30', '2025-07-01 09:11-05');
  RAISE EXCEPTION 'F13a FAILED: a third instant (neither window nor original) accepted';
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'PASS F13a: recorded_at that is neither in this run''s window nor the original''s coordinate refused'; END $$;
SELECT pg_temp.snap('00000000-0000-4000-8000-00000000c204', '2025-06-30', '2025-07-01 09:10-05');
DO $$ BEGIN RAISE NOTICE 'PASS F13b: original-world replay — recorded_at = the replaced bill''s snapshot coordinate lands'; END $$;
DELETE FROM public.invoice_calculation_snapshots WHERE invoice_id = '00000000-0000-4000-8000-00000000c204';
SELECT pg_temp.snap('00000000-0000-4000-8000-00000000c204', '2025-06-30', now());
DO $$ BEGIN RAISE NOTICE 'PASS F12b: historical election at current knowledge (period_end of the voided bill, now()) lands'; END $$;

-- F16: the target and the run's election are frozen under the snapshot
DO $$ BEGIN
  UPDATE public.correction_run_targets SET rate_date_mode = 'current' WHERE id = '00000000-0000-4000-8000-00000000d201';
  RAISE EXCEPTION 'F16a FAILED: target election changed under a snapshot';
EXCEPTION WHEN restrict_violation THEN RAISE NOTICE 'PASS F16a: correction_run_targets.rate_date_mode frozen while the correction is snapshotted'; END $$;
-- (tally_app holds no DELETE on correction_run_targets — a pre-existing
--  CI-014 revoke — so the delete branch is a superuser-only path; exercised as one.)
RESET ROLE;
DO $$ BEGIN
  DELETE FROM public.correction_run_targets WHERE id = '00000000-0000-4000-8000-00000000d201';
  RAISE EXCEPTION 'F16b FAILED: target deleted under a snapshot';
EXCEPTION WHEN restrict_violation THEN RAISE NOTICE 'PASS F16b: target row undeletable while the correction is snapshotted (superuser path; tally_app has no DELETE)'; END $$;
SET ROLE tally_app;
DO $$ BEGIN
  UPDATE public.billing_runs SET correction_rate_mode = 'current' WHERE id = '00000000-0000-4000-8000-00000000b201';
  RAISE EXCEPTION 'F16c FAILED: run election changed under a snapshot';
EXCEPTION WHEN restrict_violation THEN RAISE NOTICE 'PASS F16c: billing_runs.correction_rate_mode frozen while snapshots exist on the run'; END $$;
UPDATE public.correction_run_targets SET updated_at = now() WHERE id = '00000000-0000-4000-8000-00000000d201';
UPDATE public.billing_runs SET notes = 'fine', status = 'review', last_heartbeat_at = now(), total_invoices = 1 WHERE id = '00000000-0000-4000-8000-00000000b201';
DO $$ BEGIN RAISE NOTICE 'PASS F16d: non-election columns on the target and the run (heartbeat, totals, status) stay editable'; END $$;
DO $$ BEGIN
  UPDATE public.billing_runs SET run_type = 'off_cycle' WHERE id = '00000000-0000-4000-8000-00000000b201';
  RAISE EXCEPTION 'F24 FAILED: run_type changed under snapshots';
EXCEPTION WHEN restrict_violation THEN RAISE NOTICE 'PASS F24: billing_runs.run_type frozen while snapshots exist on the run (Fable MEDIUM-5)'; END $$;
-- F25: one snapshotted correction per (run, replaced bill)
SELECT pg_temp.inv('00000000-0000-4000-8000-00000000c207', 'INV-CORR-DUP', '00000000-0000-4000-8000-00000000b201', 'correction', '00000000-0000-4000-8000-00000000c001', '2025-06-01', '2025-06-30');
DO $$ BEGIN
  PERFORM pg_temp.snap('00000000-0000-4000-8000-00000000c207', '2025-06-30', now());
  RAISE EXCEPTION 'F25 FAILED: second correction of the same bill on the same run accepted';
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'PASS F25: a second snapshotted correction for one target refused (Fable LOW-7)'; END $$;
-- F14: current-rules election -> valid_at = CURRENT_DATE
DELETE FROM public.invoice_calculation_snapshots WHERE invoice_id = '00000000-0000-4000-8000-00000000c204';
UPDATE public.correction_run_targets SET rate_date_mode = 'current' WHERE id = '00000000-0000-4000-8000-00000000d201';
DO $$ BEGIN
  PERFORM pg_temp.snap('00000000-0000-4000-8000-00000000c204', '2025-06-30', now());
  RAISE EXCEPTION 'F14a FAILED: current election accepted the historical date';
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'PASS F14a: current-rules election refuses valid_at = the original period_end'; END $$;
SELECT pg_temp.snap('00000000-0000-4000-8000-00000000c204', CURRENT_DATE, now());
DO $$ BEGIN RAISE NOTICE 'PASS F14b: current-rules election at (CURRENT_DATE, now()) lands'; END $$;

-- F15: custom election -> valid_at = the override
DELETE FROM public.invoice_calculation_snapshots WHERE invoice_id = '00000000-0000-4000-8000-00000000c204';
UPDATE public.correction_run_targets SET rate_date_mode = 'custom', rate_date_override = '2025-09-15' WHERE id = '00000000-0000-4000-8000-00000000d201';
DO $$ BEGIN
  PERFORM pg_temp.snap('00000000-0000-4000-8000-00000000c204', '2025-06-30', now());
  RAISE EXCEPTION 'F15a FAILED: custom election accepted a non-override date';
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'PASS F15a: custom election refuses a valid_at other than the override'; END $$;
SELECT pg_temp.snap('00000000-0000-4000-8000-00000000c204', '2025-09-15', now());
DO $$ BEGIN RAISE NOTICE 'PASS F15b: custom election at (override, now()) lands'; END $$;

-- F26: ... and on ANOTHER correction run too (Fable round-2 MEDIUM-2)
INSERT INTO public.billing_runs (id, tenant_id, run_number, billing_period, period_start, period_end, run_type, status, started_at, correction_rate_mode) VALUES
  ('00000000-0000-4000-8000-00000000b203', '00000000-0000-4000-8000-00000000aa01', 'RUN-C3', '2025-06', '2025-06-01', '2025-06-30', 'correction', 'in_progress', now(), 'historical');
INSERT INTO public.correction_run_targets (id, tenant_id, billing_run_id, voided_invoice_id, meter_id, customer_id) VALUES
  ('00000000-0000-4000-8000-00000000d203', '00000000-0000-4000-8000-00000000aa01', '00000000-0000-4000-8000-00000000b203', '00000000-0000-4000-8000-00000000c001',
   '00000000-0000-4000-8000-00000000ae01', '00000000-0000-4000-8000-00000000ac01');
SELECT pg_temp.inv('00000000-0000-4000-8000-00000000c209', 'INV-CORR-RUN3', '00000000-0000-4000-8000-00000000b203', 'correction', '00000000-0000-4000-8000-00000000c001', '2025-06-01', '2025-06-30');
DO $$ BEGIN
  PERFORM pg_temp.snap('00000000-0000-4000-8000-00000000c209', '2025-06-30', now());
  RAISE EXCEPTION 'F26 FAILED: second live correction of the same bill on another run accepted';
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'PASS F26: a second live correction of one void bill refused across runs'; END $$;
-- F27: void the first correction (after issuing it) -> the bill may be corrected again
UPDATE public.invoices SET status = 'pending' WHERE id = '00000000-0000-4000-8000-00000000c204';
SELECT public.void_invoice('00000000-0000-4000-8000-00000000c204', '00000000-0000-4000-8000-00000000ab01', 'wrong_rate', 'battery: correct again', true);
SELECT pg_temp.snap('00000000-0000-4000-8000-00000000c209', '2025-06-30', now());
DO $$ BEGIN RAISE NOTICE 'PASS F27: once the earlier correction is void, a new correction of the same bill lands'; END $$;

-- F30: lineage — a correction of a correction leaves ONE live bill per lineage (round 3, Fable LOW-1 / Codex)
--      c001 (void, root) <- c209 (live correction, issued in F17 below? no: issue it here) ; void c209 ; c211 replaces c209 (lands) ; c212 replaces c001 directly -> refused
UPDATE public.invoices SET status = 'pending' WHERE id = '00000000-0000-4000-8000-00000000c209';
SELECT public.void_invoice('00000000-0000-4000-8000-00000000c209', '00000000-0000-4000-8000-00000000ab01', 'wrong_read', 'battery: correct the correction', true);
INSERT INTO public.correction_run_targets (id, tenant_id, billing_run_id, voided_invoice_id, meter_id, customer_id) VALUES
  ('00000000-0000-4000-8000-00000000d211', '00000000-0000-4000-8000-00000000aa01', '00000000-0000-4000-8000-00000000b203', '00000000-0000-4000-8000-00000000c209',
   '00000000-0000-4000-8000-00000000ae01', '00000000-0000-4000-8000-00000000ac01');
SELECT pg_temp.inv('00000000-0000-4000-8000-00000000c211', 'INV-CORR-OF-CORR', '00000000-0000-4000-8000-00000000b203', 'correction', '00000000-0000-4000-8000-00000000c209', '2025-06-01', '2025-06-30');
SELECT pg_temp.snap('00000000-0000-4000-8000-00000000c211', '2025-06-30', now());
DO $$ BEGIN RAISE NOTICE 'PASS F30a: a correction of a (void) correction lands — one hop, root two hops up'; END $$;
SELECT pg_temp.inv('00000000-0000-4000-8000-00000000c212', 'INV-CORR-ROOT-AGAIN', '00000000-0000-4000-8000-00000000b201', 'correction', '00000000-0000-4000-8000-00000000c001', '2025-06-01', '2025-06-30');
DO $$ BEGIN
  PERFORM pg_temp.snap('00000000-0000-4000-8000-00000000c212', '2025-06-30', now());
  RAISE EXCEPTION 'F30b FAILED: a second live correction landed one hop up the lineage';
EXCEPTION WHEN check_violation THEN
  IF SQLERRM NOT LIKE '%lineage%' THEN RAISE EXCEPTION 'F30b FAILED: wrong reason: %', SQLERRM; END IF;
  RAISE NOTICE 'PASS F30b: correcting the root while a live correction stands deeper in the lineage is refused';
END $$;
DO $$ BEGIN
  IF public.invoice_lineage_root('00000000-0000-4000-8000-00000000c211') <> '00000000-0000-4000-8000-00000000c001' THEN RAISE EXCEPTION 'F30c FAILED: root walk wrong'; END IF;
  RAISE NOTICE 'PASS F30c: invoice_lineage_root walks c211 -> c209 -> c001';
END $$;

-- F31: only corrections, credit memos and duplicates may carry replaces_invoice_id through the binding (round 4, Fable LOW-1)
SELECT pg_temp.inv('00000000-0000-4000-8000-00000000c213', 'INV-REGULAR-REBILL', '00000000-0000-4000-8000-00000000b101', 'regular', '00000000-0000-4000-8000-00000000c001', '2026-03-01', '2026-03-31');
DO $$ BEGIN
  PERFORM pg_temp.snap('00000000-0000-4000-8000-00000000c213', '2026-03-31', now());
  RAISE EXCEPTION 'F31a FAILED: a regular bill carrying replaces_invoice_id was snapshotted';
EXCEPTION WHEN check_violation THEN
  IF SQLERRM NOT LIKE '%correction in all but name%' THEN RAISE EXCEPTION 'F31a FAILED: wrong reason: %', SQLERRM; END IF;
  RAISE NOTICE 'PASS F31a: a regular bill with replaces_invoice_id refused — a rebill must be typed correction';
END $$;
SELECT pg_temp.inv('00000000-0000-4000-8000-00000000c214', 'INV-CREDIT-MEMO', '00000000-0000-4000-8000-00000000b101', 'credit_memo', '00000000-0000-4000-8000-00000000c001', '2026-03-01', '2026-03-31');
SELECT pg_temp.snap('00000000-0000-4000-8000-00000000c214', '2026-03-31', now());
DO $$ BEGIN RAISE NOTICE 'PASS F31b: a credit memo reversing a same-tenant bill snapshots under the ordinary shape and does not count in the lineage'; END $$;
-- F17: issuance — the ordinary bill issues; the correction issues
UPDATE public.invoices SET status = 'pending' WHERE id = '00000000-0000-4000-8000-00000000c101';
UPDATE public.invoices SET status = 'pending' WHERE id = '00000000-0000-4000-8000-00000000c211';
DO $$ BEGIN RAISE NOTICE 'PASS F17: ordinary and correction invoices with bound snapshots issue (deferred gate immediate; corrections issued in F27/F30 too)'; END $$;

-- F18: RLS — the run row lock inside the validator is tenant-scoped (a
--      second tenant's app user cannot snapshot into T1's invoice at all)
RESET ROLE;
INSERT INTO public.tenants (id, name, slug) VALUES ('00000000-0000-4000-8000-00000000aa02', 'T2 Gasco', 'bat10-t2');
INSERT INTO public.users (id, tenant_id, display_name, email, role) VALUES
  ('00000000-0000-4000-8000-00000000ab02', '00000000-0000-4000-8000-00000000aa02', 'U2', 'u2@bat10.test', 'operator');
SELECT pg_temp.inv('00000000-0000-4000-8000-00000000c105', 'INV-R1-2', '00000000-0000-4000-8000-00000000b101', 'regular', NULL, '2026-03-01', '2026-03-31');
SET LOCAL app.user_id = '00000000-0000-4000-8000-00000000ab02';
SET ROLE tally_app;
DO $$ BEGIN
  PERFORM pg_temp.snap('00000000-0000-4000-8000-00000000c105', '2026-03-31', now());
  RAISE EXCEPTION 'F18 FAILED: cross-tenant snapshot accepted';
EXCEPTION WHEN foreign_key_violation OR insufficient_privilege OR check_violation THEN RAISE NOTICE 'PASS F18: cross-tenant snapshot refused under RLS (%)', SQLSTATE; END $$;
RESET ROLE;
-- F23: T2 "corrects" T1's void bill — the FK admits the id, the binding does not
--      (replaced bill must be RLS-visible and same-tenant before the resolver runs)
INSERT INTO public.customers (id, tenant_id, customer_number) VALUES ('00000000-0000-4000-8000-00000000ac02', '00000000-0000-4000-8000-00000000aa02', 'BAT10-C2');
INSERT INTO public.service_locations (id, tenant_id, customer_id, location_number, address_line1, city, state, zip) VALUES
  ('00000000-0000-4000-8000-00000000ad02', '00000000-0000-4000-8000-00000000aa02', '00000000-0000-4000-8000-00000000ac02', 'LOC-2', '2 Main', 'Austin', 'TX', '78701');
INSERT INTO public.meters (id, tenant_id, meter_number, location_id, service_type) VALUES
  ('00000000-0000-4000-8000-00000000ae02', '00000000-0000-4000-8000-00000000aa02', 'M-2', '00000000-0000-4000-8000-00000000ad02', 'gas');
SET LOCAL app.user_id = '00000000-0000-4000-8000-00000000ab02';
SET ROLE tally_app;
INSERT INTO public.billing_runs (id, tenant_id, run_number, billing_period, period_start, period_end, run_type, status, started_at, correction_rate_mode) VALUES
  ('00000000-0000-4000-8000-00000000b202', '00000000-0000-4000-8000-00000000aa02', 'RUN-C2', '2025-06', '2025-06-01', '2025-06-30', 'correction', 'in_progress', now(), 'historical');
INSERT INTO public.correction_run_targets (id, tenant_id, billing_run_id, voided_invoice_id, meter_id, customer_id) VALUES
  ('00000000-0000-4000-8000-00000000d208', '00000000-0000-4000-8000-00000000aa02', '00000000-0000-4000-8000-00000000b202', '00000000-0000-4000-8000-00000000c001',
   '00000000-0000-4000-8000-00000000ae02', '00000000-0000-4000-8000-00000000ac02');
DO $$ BEGIN
  INSERT INTO public.invoices (id, tenant_id, invoice_number, billing_run_id, customer_id, location_id, invoice_type, replaces_invoice_id, invoice_date, billing_period, period_start, period_end, due_date)
  VALUES ('00000000-0000-4000-8000-00000000c208', '00000000-0000-4000-8000-00000000aa02', 'INV-T2-XCORR', '00000000-0000-4000-8000-00000000b202', '00000000-0000-4000-8000-00000000ac02', '00000000-0000-4000-8000-00000000ad02',
          'correction', '00000000-0000-4000-8000-00000000c001', CURRENT_DATE, '2025-06', '2025-06-01', '2025-06-30', CURRENT_DATE + 21);
  RAISE EXCEPTION 'F23 FAILED: cross-tenant replaces_invoice_id accepted';
EXCEPTION WHEN foreign_key_violation THEN
  RAISE NOTICE 'PASS F23: cross-tenant replaces_invoice_id refused at INSERT by the tenant-composite FK (the binding''s RLS visibility check stands behind it)';
END $$;
RESET ROLE;

-- F19: the issuance re-check is the last word — bypass the target freeze as
--      superuser (disable the ENABLE ALWAYS trigger), remove the target, and
--      the correction can no longer issue.
SELECT pg_temp.inv('00000000-0000-4000-8000-00000000c205', 'INV-CORR-2', '00000000-0000-4000-8000-00000000b201', 'correction', '00000000-0000-4000-8000-00000000c102', '2026-03-01', '2026-03-31');
UPDATE public.invoices SET status = 'pending' WHERE id = '00000000-0000-4000-8000-00000000c102';
SET LOCAL app.user_id = '00000000-0000-4000-8000-00000000ab01';   -- void_invoice checks the caller's tenant
SELECT public.void_invoice('00000000-0000-4000-8000-00000000c102', '00000000-0000-4000-8000-00000000ab01', 'wrong_read', 'battery', true);
INSERT INTO public.correction_run_targets (id, tenant_id, billing_run_id, voided_invoice_id, meter_id, customer_id, rate_date_mode) VALUES
  ('00000000-0000-4000-8000-00000000d202', '00000000-0000-4000-8000-00000000aa01', '00000000-0000-4000-8000-00000000b201', '00000000-0000-4000-8000-00000000c102',
   '00000000-0000-4000-8000-00000000ae01', '00000000-0000-4000-8000-00000000ac01', 'historical');
SELECT pg_temp.snap('00000000-0000-4000-8000-00000000c205', '2026-03-31', now());
-- (CI-014 forbids hard-deleting a target even as superuser, so the bypass
--  re-points the target at another voided invoice instead.)
ALTER TABLE public.correction_run_targets DISABLE TRIGGER a_enforce_correction_target_frozen_under_snapshot;
UPDATE public.correction_run_targets SET voided_invoice_id = '00000000-0000-4000-8000-00000000c101' WHERE id = '00000000-0000-4000-8000-00000000d202';
ALTER TABLE public.correction_run_targets ENABLE ALWAYS TRIGGER a_enforce_correction_target_frozen_under_snapshot;
DO $$ BEGIN
  UPDATE public.invoices SET status = 'pending' WHERE id = '00000000-0000-4000-8000-00000000c205';
  RAISE EXCEPTION 'F19 FAILED: correction issued after its target row was re-pointed';
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'PASS F19: issuance re-check refuses a correction whose target row no longer matches (%)', left(SQLERRM, 80); END $$;

-- F20: the -04 behaviours survive the redefinition: void-as-discard exempt;
--      missing snapshot refused
SELECT pg_temp.inv('00000000-0000-4000-8000-00000000c106', 'INV-R1-3', '00000000-0000-4000-8000-00000000b101', 'regular', NULL, '2026-03-01', '2026-03-31');
DO $$ BEGIN
  UPDATE public.invoices SET status = 'pending' WHERE id = '00000000-0000-4000-8000-00000000c106';
  RAISE EXCEPTION 'F20a FAILED: issued without a snapshot';
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'PASS F20a: issuance without a snapshot still refused'; END $$;
SET LOCAL app.user_id = '00000000-0000-4000-8000-00000000ab01';
SET ROLE tally_app;
UPDATE public.invoices SET status = 'held', held_at = now(), held_by = '00000000-0000-4000-8000-00000000ab01', hold_reason = 'battery' WHERE id = '00000000-0000-4000-8000-00000000c106';
SELECT public.void_invoice('00000000-0000-4000-8000-00000000c106', '00000000-0000-4000-8000-00000000ab01', 'system_error', 'battery discard', false);
DO $$ DECLARE st text; BEGIN
  SELECT status INTO st FROM public.invoices WHERE id = '00000000-0000-4000-8000-00000000c106';
  IF st <> 'void' THEN RAISE EXCEPTION 'F20b FAILED: draft not voided (%)', st; END IF;
  RAISE NOTICE 'PASS F20b: discarding an unsnapshotted held invoice through void_invoice() still exempt from the snapshot gate';
END $$;
-- F28: that discard is void but was never billed — it cannot anchor a correction (Fable round-2 MEDIUM-1)
INSERT INTO public.correction_run_targets (id, tenant_id, billing_run_id, voided_invoice_id, meter_id, customer_id) VALUES
  ('00000000-0000-4000-8000-00000000d209', '00000000-0000-4000-8000-00000000aa01', '00000000-0000-4000-8000-00000000b201', '00000000-0000-4000-8000-00000000c106',
   '00000000-0000-4000-8000-00000000ae01', '00000000-0000-4000-8000-00000000ac01');
SELECT pg_temp.inv('00000000-0000-4000-8000-00000000c210', 'INV-CORR-DISCARD', '00000000-0000-4000-8000-00000000b201', 'correction', '00000000-0000-4000-8000-00000000c106', '2026-03-01', '2026-03-31');
DO $$ BEGIN
  PERFORM pg_temp.snap('00000000-0000-4000-8000-00000000c210', '2026-03-31', now());
  RAISE EXCEPTION 'F28 FAILED: never-issued void discard anchored a correction';
EXCEPTION WHEN check_violation THEN
  IF SQLERRM NOT LIKE '%never issued%' THEN RAISE EXCEPTION 'F28 FAILED: wrong reason: %', SQLERRM; END IF;
  RAISE NOTICE 'PASS F28: a void bill that was never issued (first_issued_at NULL) cannot anchor a correction';
END $$;
RESET ROLE;

ROLLBACK;
