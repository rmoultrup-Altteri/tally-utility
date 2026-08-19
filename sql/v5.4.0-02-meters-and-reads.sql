-- ============================================================================
-- PATCH v5.4.0-02 — Meters & reads set (v5.4 backlog items 1, 2, 8, 9)
-- ============================================================================
-- Authority:   Kyle rulings 2026-07-10 (gas-billing-memory/application/
--              wu5-wu6-kyle-decisions-2026-07-10.md):
--                item 1  rollover_point column on meters        (D3-1)
--                item 2  meter_pressure_class column            (D3-1; 3B dep)
--                item 8  meter_skip_reason enum                 (D3A-3)
--                item 9  tamper recording columns               (D3A-4)
--              First Phase 1 migration set per the parity plan.
-- CI entries:  CI-023 (re-grade: two of its three missing meter columns land;
--              temperature_compensated remains absent and the populated-
--              completeness rule remains app-layer — status token unchanged,
--              text updated). Appendix A-5 meters bullet updated. CI-029's
--              candidate structural CHECK (Fp = 1.0 on residential_base) is
--              deliberately NOT drafted — it is an open flag to Kyle
--              (gas-conversion-and-energy decision table, Open questions).
-- Drafting decisions (delegated by the rulings to patch time):
--              * D3A-4 says "on meter or read record" — columns land on
--                METERS: tamper is a life-of-meter investigation state
--                feeding the Critical portlet; per-read signals already have
--                meter_readings.has_anomaly/anomaly_types. tamper_confirmed
--                is NOT a column — the decision table sources it from the
--                investigation outcome, not the recording substrate.
--              * D3A-3's "other+notes" is enforced: skip_reason = 'other'
--                requires read_cycle_meters.notes. billing_run_meters.
--                skip_reason (a different, billing-outcome concept) is
--                untouched.
--              * rollover_point is numeric(14,2) to match reading_value /
--                previous_value arithmetic; NULL falls back to
--                10^dial_count, both NULL = rollover detection disabled
--                (existing dial_count contract).
--              * All new columns are nullable (or defaulted): CI-023's
--                completeness rule ("billing an incomplete master is
--                rejected") is the A-20 exception-queue's job, not a NOT
--                NULL on a table with pre-existing sparse rows.
-- Idempotent:  yes (ADD COLUMN IF NOT EXISTS; constraints DROP IF EXISTS +
--              re-ADD; COMMENT overwrite).
-- Line count:  mirrored into tu.sql as a pure APPEND at end of file — no
--              existing line shifts; anchors 337/3600/3679 unaffected.
-- ============================================================================

--
-- Item 1 — meters.rollover_point (D3-1). Canonical register ceiling for
-- rollover arithmetic: usage = (rollover_point - start_read) + end_read.
--
ALTER TABLE public.meters ADD COLUMN IF NOT EXISTS rollover_point numeric(14,2);

ALTER TABLE public.meters DROP CONSTRAINT IF EXISTS meters_rollover_point_check;
ALTER TABLE public.meters ADD CONSTRAINT meters_rollover_point_check
    CHECK ((rollover_point IS NULL) OR (rollover_point > (0)::numeric));

COMMENT ON COLUMN public.meters.rollover_point IS
    'Canonical register rollover ceiling (D3-1, v5.4.0-02). Rollover arithmetic: usage = (rollover_point - start_read) + end_read when end < start. When NULL, fall back to 10^dial_count per that column''s contract; when both are NULL, rollover detection is disabled and a negative delta is flagged negative_consumption instead of corrected. Silent life-of-meter failure mode if wrong — set from the physical register, not guessed.';

--
-- Item 2 — meters.meter_pressure_class (D3-1; Session 3B dependency).
-- Values per the gas-conversion-and-energy decision table (cluster 8).
--
ALTER TABLE public.meters ADD COLUMN IF NOT EXISTS meter_pressure_class text;

ALTER TABLE public.meters DROP CONSTRAINT IF EXISTS meters_meter_pressure_class_check;
ALTER TABLE public.meters ADD CONSTRAINT meters_meter_pressure_class_check
    CHECK ((meter_pressure_class IS NULL) OR (meter_pressure_class = ANY (ARRAY['residential_base'::text, 'elevated'::text])));

COMMENT ON COLUMN public.meters.meter_pressure_class IS
    'Delivery pressure class of the meter set (D3-1, v5.4.0-02): residential_base or elevated. Replaces the fragile rate-schedule-association inference (CI-023 gap). Engine rule CI-029: residential_base ALWAYS gets Fp = 1.0 regardless of meter_factor''s stored value; only elevated applies the pressure-correction factor. NULL = not yet affirmed — the D3B-2 activation QA gate (backlog item 13) will require affirmation at activation; until then the application must treat NULL as incomplete master data, never default it.';

--
-- Item 8 — meter skip reason enum (D3A-3) on read_cycle_meters.skip_reason
-- (previously free text). Ruled set, with other requiring notes.
--
ALTER TABLE public.read_cycle_meters DROP CONSTRAINT IF EXISTS read_cycle_meters_skip_reason_check;
ALTER TABLE public.read_cycle_meters ADD CONSTRAINT read_cycle_meters_skip_reason_check
    CHECK ((skip_reason IS NULL) OR (skip_reason = ANY (ARRAY['no_access'::text, 'locked_gate'::text, 'dog'::text, 'hazard'::text, 'meter_damaged'::text, 'customer_refused'::text, 'weather'::text, 'other'::text])));

ALTER TABLE public.read_cycle_meters DROP CONSTRAINT IF EXISTS read_cycle_meters_skip_other_notes_check;
ALTER TABLE public.read_cycle_meters ADD CONSTRAINT read_cycle_meters_skip_other_notes_check
    CHECK ((skip_reason IS DISTINCT FROM 'other') OR (notes IS NOT NULL));

COMMENT ON COLUMN public.read_cycle_meters.skip_reason IS
    'Why the meter was not read this cycle (D3A-3 ruled enum, v5.4.0-02): no_access, locked_gate, dog, hazard, meter_damaged, customer_refused, weather, other. other requires notes (enforced). Pairs with read_status skipped (operator decision) or cant_read (field-side). Feeds the meter-skip-disposition rules in read-cycle-reader-routing.';

--
-- Item 9 — tamper recording columns (D3A-4), placed on METERS (see header).
-- Signal sources per the tamper-detection-response decision table (cluster 6).
-- Recording substrate only: algorithmic tamper detection is v2 analytics
-- (deferral register), and the investigation outcome lives with the
-- revenue-protection workflow, not here.
--
ALTER TABLE public.meters ADD COLUMN IF NOT EXISTS tamper_flag boolean DEFAULT false NOT NULL;
ALTER TABLE public.meters ADD COLUMN IF NOT EXISTS tamper_reported_at timestamp with time zone;
ALTER TABLE public.meters ADD COLUMN IF NOT EXISTS tamper_signal_source text;
ALTER TABLE public.meters ADD COLUMN IF NOT EXISTS tamper_reason text;

ALTER TABLE public.meters DROP CONSTRAINT IF EXISTS meters_tamper_signal_source_check;
ALTER TABLE public.meters ADD CONSTRAINT meters_tamper_signal_source_check
    CHECK ((tamper_signal_source IS NULL) OR (tamper_signal_source = ANY (ARRAY['ami_alarm'::text, 'field_observation'::text, 'billing_analyst_flagged'::text])));

ALTER TABLE public.meters DROP CONSTRAINT IF EXISTS meters_tamper_flag_consistency_check;
ALTER TABLE public.meters ADD CONSTRAINT meters_tamper_flag_consistency_check
    CHECK ((NOT tamper_flag) OR ((tamper_reported_at IS NOT NULL) AND (tamper_signal_source IS NOT NULL)));

COMMENT ON COLUMN public.meters.tamper_flag IS
    'Active tamper condition on this meter (D3A-4, v5.4.0-02). Setting it requires tamper_reported_at and tamper_signal_source (enforced). Feeds the Critical portlet and the tamper-detection-response routing (cluster 6); confirmed tampering is the uncapped-backbilling cause per 16 TAC 7.45. Clearing the flag after a false positive does not clear the reporting columns — retention of false-trip history is an open question (cluster 6), so the schema does not force erasure.';

COMMENT ON COLUMN public.meters.tamper_reported_at IS
    'When the tamper signal was recorded (D3A-4). Required while tamper_flag is set.';

COMMENT ON COLUMN public.meters.tamper_signal_source IS
    'How the tamper condition surfaced (D3A-4): ami_alarm (two-way AMI only), field_observation, or billing_analyst_flagged. AMR/manual meters have no alarm channel — only the two human sources are possible for them (application discipline, not a schema rule). Required while tamper_flag is set. Consumption-pattern inference is deliberately NOT a source — v2 analytics, deferred.';

COMMENT ON COLUMN public.meters.tamper_reason IS
    'Free-text description of the tamper evidence (D3A-4): what was observed or which alarm fired. Optional companion to tamper_signal_source.';
