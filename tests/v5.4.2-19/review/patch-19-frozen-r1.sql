-- ============================================================================
-- PATCH v5.4.2-19 — hardening batch 1: close the holes in what is already
--                    built (step 1, wave 1)
-- ============================================================================
-- Authority:   Ryan, 2026-10-13: "yes, start batch 1" — wave 1 of
--              application/step1-sequencing-2026-10-13.md (tightening on
--              tables that are empty today; no ruling needed).
-- Spec:        application/invariant-parity-measurement-2026-10-13.md (the
--              PARTIAL rows named below, each with its missing piece);
--              Kyle T-3 (tier proration default true); Kyle Q-3 2026-06-12
--              (WNA deadband per zone version, value + evaluation form).
--
-- ----------------------------------------------------------------------------
-- What changes
-- ----------------------------------------------------------------------------
--   Meter reads
--   * CI-022. populate_reading_calculations no longer writes consumption. It
--     filled (reading - previous) * multiplier with no rollover branch, so a
--     wrapped dial got a negative usage written by the database itself. The
--     arithmetic (rollover, roll-under, multiplier) is the core's; the trigger
--     still fills previous_value, previous_reading_date and days_in_period.
--   * CI-025 / CI-031. enforce_reading_validation_workflow keys the freeze of
--     a read's values on billing_period_locked, not on validation_status =
--     'locked'. A read a voided bill released (void_released) keeps
--     billing_period_locked = true and was fully writable; its values are now
--     frozen like a locked read's, and meter_id, location_id and tenant_id
--     join the frozen set. The void carve-out (app.void_operation) is
--     narrowed to what void_invoice() writes: locked_by_invoice_id cleared,
--     voided_from_invoice_id set to it, nothing else. locked_at is stamped
--     by the database on every move to locked (a superuser keeps its value,
--     for history loads).
--   Rates
--   * CI-108. rate_schedule_versions.prorate_tier_breakpoints defaults to
--     true again (Kyle T-3; v5.4.2-03 moved the column with DEFAULT false).
--   * CI-106. invoice_line_items: coverage_start <= coverage_end.
--   * CI-041. wna_zone_versions gains the deadband: deadband_value,
--     deadband_measure (ratio_actual_to_normal | absolute_hdd_difference),
--     deadband_application (full_deviation | excess_over_deadband); all
--     three or none. Versions are frozen by the bitemporal guard, which
--     compares whole rows, so the new columns are frozen with the rest.
--   * CI-101. rate_item_dependencies: a dependency that closes a cycle in
--     its schedule is refused (A->B then B->A, any length), and so is one
--     whose schedule or items belong to another tenant. Writers serialise on
--     the schedule's header row (a row-version mutex: the guard bumps
--     rate_schedules.updated_at), so two halves of a cycle written at once
--     cannot both pass, under any isolation level.
--   Payments
--   * CI-058. payments.effective_date and effective_date_method (vocabulary
--     payment_effective_date_methods: postmark, lockbox_receipt,
--     bank_settlement, other — the register's four). Both are required once
--     the payment takes effect (any status but pending and voided: a payment
--     voided at intake never took effect) and are write-once once it has
--     left pending.
--   * CI-052. payments.return_code: a NACHA return code (R followed by two
--     digits), only on a payment in nsf or reversed, required when an ACH
--     payment goes to nsf, write-once.
--   * CI-055. One payment per processor transaction: UNIQUE (tenant_id,
--     source_system, provider_transaction_id) for original payments (a
--     refund or an NSF row that cites its original is not counted).
--   * CI-057. payment_methods keeps its history. The account identity
--     (customer, provider, token, method type, last four, bank, account type,
--     holder) is frozen once written; a change is a new row that names the
--     row it supersedes and why (customer_update or ach_notice_of_change,
--     the latter with its NACHA change code C followed by two digits and the
--     time the notice was received). The superseded row is deactivated by
--     the database and cannot be reactivated; a row has at most one
--     successor, of the same customer and tenant.
--   Logs and records
--   * CI-068. dunning_events is append-only (UPDATE and DELETE refused,
--     UPDATE revoked from tally_app) and its invoice foreign key no longer
--     cascades a delete.
--   * CI-126. escheatment_events is append-only, UPDATE revoked.
--   * CI-099. ai_audit_log is append-only, UPDATE revoked. A service order or
--     ad-hoc charge created by the AI (created_by_ai, or an ad-hoc charge
--     with source ai_suggestion) must cite its ai_audit_log row.
--   * created_at is stamped by the database on those three logs (a superuser
--     keeps its value, for history loads).
--   * CI-128. anomalies.dedup_key is NOT NULL and its uniqueness is no longer
--     deferrable; dedup_key, first_detected_at, created_at and the anomaly's
--     subject are write-once; recurrence_count never decreases and
--     last_detected_at never moves backwards or before first_detected_at.
--   * CI-127. adhoc_charges: a charge that requires approval records the
--     threshold in force when it was created; requires_approval and the
--     threshold are write-once.
--   * CI-096 (hash only). invoices.pdf_sha256: the SHA-256 of the image the
--     customer received, required with pdf_url and write-once with it.
--   Imports
--   * CI-118. A file import (csv, excel, pdf, legacy_export) names its file
--     and its hash; one live job per tenant, file hash, import type and
--     preview/commit (a failed or cancelled job does not count), so a
--     renamed copy of a file already imported is refused — the
--     idempotency_key (filename-based, or caller-supplied) no longer decides
--     that alone.
--   * CI-098. import_type gains ach_return, lockbox and amr.
--   Programs
--   * CI-062. program_types.requires_attestation (true for
--     medical_certificate). An active enrollment of such a type carries its
--     attestation document and the time it was received; a verification
--     names who verified, and comes after receipt.
--   Ledger
--   * CI-019 (helper only). account_balance_as_of(customer, on, recorded):
--     the customer's balance from the ledger rows dated on or before `on`
--     and recorded by `recorded` — a sum, so it does not depend on the
--     order rows were written. Both coordinates are required.
--
-- ----------------------------------------------------------------------------
-- What the database refuses (new)
-- ----------------------------------------------------------------------------
--   Reads: any change to a value field of a read with billing_period_locked
--   (locked or void_released); a void transition that writes anything but the
--   two pointers void_invoice() writes. Rates: a coverage end before its
--   start; a partial deadband; a negative deadband; a dependency cycle; a
--   dependency across tenants. Payments: leaving pending without an effective
--   date and method (a payment voided at intake needs none); changing either
--   once the payment has left pending; a return code of the wrong
--   form, on a payment not nsf/reversed, missing on an ACH nsf, or changed;
--   a second original payment for one processor transaction; a change to a
--   payment method's account identity; a supersede of another customer's
--   method, of a method already superseded, or reactivating a superseded
--   method; a notice-of-change supersede without its code and receipt time.
--   Logs: UPDATE or DELETE on dunning, escheatment and AI audit events; an AI
--   service order or charge without its audit row; an anomaly without a dedup
--   key, a second one with the same key, a rewrite of its identity or first
--   detection, a falling recurrence count. Charges: requiring approval with
--   no threshold; rewriting either. Invoices: an image without its hash, or
--   rewriting the hash. Imports: a file import without file name and hash; a
--   second live job for the same file. Programs: an active attestation-type
--   enrollment without its document and receipt time; a verification without
--   its verifier or before receipt.
--
-- ----------------------------------------------------------------------------
-- Not here (residuals)
-- ----------------------------------------------------------------------------
--   R1. CI-010 (the America/Chicago day boundary in
--       customer_is_state_agency_as_of) stays: v5.4.2-16 deferred it to the
--       surcharge rules' rule-terms rebuild on purpose, and switching now
--       would refuse every exempt-agency surcharge line on a premise whose
--       places are not loaded.
--   R2. CI-019: running_balance is still stamped by a trigger that orders by
--       created_at and id (rows written in one transaction tie on created_at
--       and fall back to a random id) and takes no lock. Whether the column
--       stays (and is fixed) or goes is Ryan's call; account_balance_as_of is
--       the correct reading either way.
--   R3. CI-025: a read's type columns are frozen from the billing lock on,
--       not from acceptance; reads before the lock stay editable (the review
--       workflow edits them).
--   R4. CI-101: rate_item_dependencies is not effective-dated, and tally_app
--       may still DELETE a row (CI-014 scoping, Ryan).
--   R5. CI-062: only medical_certificate requires attestation; whether
--       elderly_disabled and military_deployment_scra do is a domain call.
--   R6. CI-058: the register's method set has no counter-receipt value (cash
--       at a window); such a payment uses `other` until the set is extended.
--   R7. CI-096: the retention binding and "issuance requires an image" are
--       wave 5 (communications).
--   R8. CI-022: no CHECK on the sign of consumption — whether a negative
--       usage is ever a legitimate read is not ruled.
--   R9. THE APPLICATION CONTRACTS FOLLOW THE MIRROR (as -15's R12).
--       application/APPLICATION-CONTRACTS.md is rewritten in the commit that
--       mirrors this patch: AC-4 (file imports) moves from SILENT to refused;
--       new contracts for what writers must now do — the core writes a read's
--       consumption; a payment carries its effective date and method when it
--       takes effect, and an ACH return its code; a changed bank account is a
--       new payment_methods row; dunning, escheatment and AI audit rows are
--       written once, complete; an anomaly carries its dedup key and a
--       recurrence updates the canonical row; an AI-created order or charge
--       cites its audit row; a bill image is recorded with its hash.
--   R10. CI-052: a return code is required only on an ACH payment in nsf; an
--       ACH payment recorded as reversed (an unauthorized-debit return, R10)
--       may carry one but need not.
--
-- PRECONDITION. v5.4.2-18 and -15 applied (tu.sql). The tables tightened are
--   empty in every database built from tu.sql; on a database with rows, a
--   new CHECK or NOT NULL fails the patch rather than skip a row (anomalies
--   without dedup_key, ad-hoc charges requiring approval without threshold,
--   AI rows without audit, file imports without hash, active medical holds
--   without attestation). Applied by a superuser, under READ COMMITTED.
--   A second run finds payment_effective_date_methods and skips the whole
--   patch (psql's \if): apply it with psql.
-- ============================================================================

SELECT to_regclass('public.payment_effective_date_methods') IS NOT NULL AS already \gset
\if :already
DO $$ BEGIN RAISE NOTICE 'v5.4.2-19: already applied (payment_effective_date_methods exists); nothing to do'; END $$;
\else
BEGIN;


-- ----------------------------------------------------------------------------
-- 1. Meter reads (CI-022, CI-025, CI-031)
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.populate_reading_calculations() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_prev_date  date;
    v_prev_value numeric(14,2);
BEGIN
    -- Only auto-fill if not already set by the caller
    IF NEW.previous_value IS NULL OR NEW.previous_reading_date IS NULL THEN
        -- The most recent active reading for this meter + register before the new reading date
        SELECT r.reading_date, r.reading_value
          INTO v_prev_date, v_prev_value
          FROM public.meter_readings r
         WHERE r.meter_id = NEW.meter_id
           AND r.register_type = NEW.register_type
           AND r.reading_date < NEW.reading_date
           AND r.status = 'active'
         ORDER BY r.reading_date DESC
         LIMIT 1;

        IF v_prev_date IS NOT NULL THEN
            NEW.previous_reading_date := COALESCE(NEW.previous_reading_date, v_prev_date);
            NEW.previous_value := COALESCE(NEW.previous_value, v_prev_value);
        END IF;
    END IF;

    IF NEW.previous_reading_date IS NOT NULL AND NEW.days_in_period IS NULL THEN
        NEW.days_in_period := NEW.reading_date - NEW.previous_reading_date;
    END IF;

    -- v5.4.2-19 (CI-022): consumption is NOT filled here. A subtraction with
    -- no rollover branch wrote negative usage for a wrapped dial; rollover,
    -- roll-under and the multiplier are the core's arithmetic.
    RETURN NEW;
END;
$$;
COMMENT ON FUNCTION public.populate_reading_calculations() IS
    'Fills previous_value, previous_reading_date (from the latest earlier active read of the meter and register) and days_in_period when the caller leaves them NULL. v5.4.2-19 (CI-022): never writes consumption — the core computes usage, including rollover and the multiplier.';

CREATE OR REPLACE FUNCTION public.enforce_reading_validation_workflow() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_changed           text[] := '{}';
    v_is_void_operation boolean;
    v_void_transition   boolean;
    v_super             boolean := (SELECT r.rolsuper FROM pg_catalog.pg_roles r WHERE r.rolname = current_user);
BEGIN
    -- void_invoice() arms this transaction-scoped setting before it releases
    -- the reads of the bill it voids. It is caller-settable: the carve-out
    -- below admits only what void_invoice() writes (AC-12: a fence against
    -- accident, not against a hostile caller).
    v_is_void_operation := coalesce(current_setting('app.void_operation', true) = 'true', false);
    v_void_transition := v_is_void_operation
                         AND OLD.validation_status = 'locked'
                         AND NEW.validation_status = 'void_released';

    -- -------------------------------------------------------------------------
    -- BLOCK 1: validation_status transitions
    -- -------------------------------------------------------------------------
    IF OLD.validation_status IS DISTINCT FROM NEW.validation_status THEN

        IF OLD.validation_status = 'locked' THEN
            IF NOT v_void_transition THEN
                RAISE EXCEPTION
                    'Cannot change validation_status from locked. '
                    'Locked readings are terminal — corrections must create a NEW reading '
                    'via the dispute/correction workflow (insert replacement with '
                    'replaces_read_id pointing here). '
                    'To void the invoice that locked this read, use void_invoice(). '
                    'Reading: %', OLD.id;
            END IF;

        ELSIF NOT (
               (OLD.validation_status = 'pending_review'
                    AND NEW.validation_status IN ('reviewed_clean','reviewed_with_exception','approved','excluded'))
            OR (OLD.validation_status = 'reviewed_clean'
                    AND NEW.validation_status IN ('approved','excluded'))
            OR (OLD.validation_status = 'reviewed_with_exception'
                    AND NEW.validation_status IN ('approved','excluded','pending_review'))
            OR (OLD.validation_status = 'approved'
                    AND NEW.validation_status IN ('released_to_billing','excluded','pending_review'))
            OR (OLD.validation_status = 'released_to_billing'
                    AND NEW.validation_status = 'locked')
            OR (OLD.validation_status = 'excluded'
                    AND NEW.validation_status = 'pending_review')
            OR (OLD.validation_status = 'void_released'
                    AND NEW.validation_status = 'released_to_billing') -- correction run re-locks
        ) THEN
            RAISE EXCEPTION
                'Invalid validation_status transition: % -> %. Reading: %',
                OLD.validation_status, NEW.validation_status, OLD.id;
        END IF;

        -- Locking guard: transitioning TO locked requires billing metadata;
        -- the lock time is the database's (v5.4.2-19), a superuser's kept.
        IF NEW.validation_status = 'locked' THEN
            IF NEW.billing_period_locked IS DISTINCT FROM true THEN
                RAISE EXCEPTION
                    'validation_status=locked requires billing_period_locked=true. Reading: %', OLD.id;
            END IF;
            IF NEW.locked_by_billing_run_id IS NULL THEN
                RAISE EXCEPTION
                    'validation_status=locked requires locked_by_billing_run_id. Reading: %', OLD.id;
            END IF;
            IF NOT v_super OR NEW.locked_at IS NULL THEN
                NEW.locked_at := now();
            END IF;
        END IF;

    END IF;

    -- -------------------------------------------------------------------------
    -- BLOCK 2: a read a billing run consumed keeps its values (v5.4.2-19,
    -- CI-025 / CI-031). Keyed on billing_period_locked, which stays true after
    -- void_released: the read a voided bill released is the evidence the
    -- correction run rebills from, and is frozen like a locked one. Nothing
    -- here has a void carve-out — void_invoice() writes none of these.
    -- -------------------------------------------------------------------------
    IF OLD.billing_period_locked THEN
        IF NEW.tenant_id                       IS DISTINCT FROM OLD.tenant_id                       THEN v_changed := v_changed || 'tenant_id'::text; END IF;
        IF NEW.meter_id                        IS DISTINCT FROM OLD.meter_id                        THEN v_changed := v_changed || 'meter_id'::text; END IF;
        IF NEW.location_id                     IS DISTINCT FROM OLD.location_id                     THEN v_changed := v_changed || 'location_id'::text; END IF;
        IF NEW.reading_value                   IS DISTINCT FROM OLD.reading_value                   THEN v_changed := v_changed || 'reading_value'::text; END IF;
        IF NEW.previous_value                  IS DISTINCT FROM OLD.previous_value                  THEN v_changed := v_changed || 'previous_value'::text; END IF;
        IF NEW.consumption                     IS DISTINCT FROM OLD.consumption                     THEN v_changed := v_changed || 'consumption'::text; END IF;
        IF NEW.consumption_unit                IS DISTINCT FROM OLD.consumption_unit                THEN v_changed := v_changed || 'consumption_unit'::text; END IF;
        IF NEW.reading_date                    IS DISTINCT FROM OLD.reading_date                    THEN v_changed := v_changed || 'reading_date'::text; END IF;
        IF NEW.previous_reading_date           IS DISTINCT FROM OLD.previous_reading_date           THEN v_changed := v_changed || 'previous_reading_date'::text; END IF;
        IF NEW.register_type                   IS DISTINCT FROM OLD.register_type                   THEN v_changed := v_changed || 'register_type'::text; END IF;
        IF NEW.read_method                     IS DISTINCT FROM OLD.read_method                     THEN v_changed := v_changed || 'read_method'::text; END IF;
        IF NEW.is_estimated                    IS DISTINCT FROM OLD.is_estimated                    THEN v_changed := v_changed || 'is_estimated'::text; END IF;
        IF NEW.gas_meter_factor                IS DISTINCT FROM OLD.gas_meter_factor                THEN v_changed := v_changed || 'gas_meter_factor'::text; END IF;
        IF NEW.gas_pressure_corrected_volume   IS DISTINCT FROM OLD.gas_pressure_corrected_volume   THEN v_changed := v_changed || 'gas_pressure_corrected_volume'::text; END IF;
        IF NEW.gas_btu_factor                  IS DISTINCT FROM OLD.gas_btu_factor                  THEN v_changed := v_changed || 'gas_btu_factor'::text; END IF;
        IF NEW.gas_therms                      IS DISTINCT FROM OLD.gas_therms                      THEN v_changed := v_changed || 'gas_therms'::text; END IF;
        IF NEW.billing_cycle_id                IS DISTINCT FROM OLD.billing_cycle_id                THEN v_changed := v_changed || 'billing_cycle_id'::text; END IF;
        IF NEW.is_service_transition           IS DISTINCT FROM OLD.is_service_transition           THEN v_changed := v_changed || 'is_service_transition'::text; END IF;
        IF NEW.transition_outgoing_customer_id IS DISTINCT FROM OLD.transition_outgoing_customer_id THEN v_changed := v_changed || 'transition_outgoing_customer_id'::text; END IF;
        IF NEW.transition_incoming_customer_id IS DISTINCT FROM OLD.transition_incoming_customer_id THEN v_changed := v_changed || 'transition_incoming_customer_id'::text; END IF;
        IF NEW.reading_purpose                 IS DISTINCT FROM OLD.reading_purpose                 THEN v_changed := v_changed || 'reading_purpose'::text; END IF;
        IF NEW.billing_period_locked           IS DISTINCT FROM true                                THEN v_changed := v_changed || 'billing_period_locked'::text; END IF;
    END IF;

    -- -------------------------------------------------------------------------
    -- BLOCK 3: the lock pointers of a locked read. The one way out is
    -- void_invoice()'s: locked_by_invoice_id cleared, voided_from_invoice_id
    -- set to the bill it held, the run and the lock time unchanged.
    -- -------------------------------------------------------------------------
    IF OLD.validation_status = 'locked' THEN
        IF NEW.locked_by_billing_run_id IS DISTINCT FROM OLD.locked_by_billing_run_id THEN v_changed := v_changed || 'locked_by_billing_run_id'::text; END IF;
        IF NEW.locked_at                IS DISTINCT FROM OLD.locked_at                THEN v_changed := v_changed || 'locked_at'::text; END IF;
        IF v_void_transition THEN
            IF NEW.locked_by_invoice_id IS NOT NULL THEN v_changed := v_changed || 'locked_by_invoice_id (void must clear it)'::text; END IF;
            IF NEW.voided_from_invoice_id IS DISTINCT FROM OLD.locked_by_invoice_id THEN v_changed := v_changed || 'voided_from_invoice_id (void sets it to the bill it held)'::text; END IF;
        ELSE
            IF NEW.locked_by_invoice_id   IS DISTINCT FROM OLD.locked_by_invoice_id   THEN v_changed := v_changed || 'locked_by_invoice_id'::text; END IF;
            IF NEW.voided_from_invoice_id IS DISTINCT FROM OLD.voided_from_invoice_id THEN v_changed := v_changed || 'voided_from_invoice_id'::text; END IF;
        END IF;
    END IF;

    IF cardinality(v_changed) > 0 THEN
        RAISE EXCEPTION USING
            MESSAGE = format('meter reading %s was consumed by a billing run (validation_status %s, billing_period_locked) and its billing fields are frozen (CI-025 / CI-031, v5.4.2-19): attempted change to %s',
                             OLD.id, OLD.validation_status, array_to_string(v_changed, ', ')),
            HINT = 'To correct a read, insert a NEW reading with replaces_read_id pointing here. To undo the bill, use void_invoice(). Editable on such reads: notes, tamper_*, dispute_*, status, requires_followup, followup_*, assigned_to_user_id.',
            ERRCODE = 'restrict_violation';
    END IF;

    RETURN NEW;
END;
$$;
COMMENT ON FUNCTION public.enforce_reading_validation_workflow() IS
    'BEFORE UPDATE on meter_readings. Block 1: the validation_status transition matrix; locked -> void_released only under void_invoice() (app.void_operation); a move to locked needs billing_period_locked and locked_by_billing_run_id, and locked_at is stamped by the database (a superuser''s value kept). Block 2 (v5.4.2-19, CI-025/CI-031): once billing_period_locked is true — locked AND void_released — the read''s value, type, identity and transition fields are frozen and the flag cannot be cleared. Block 3: a locked read''s lock pointers are frozen, except void_invoice()''s exact write (locked_by_invoice_id -> NULL, voided_from_invoice_id := the bill it held).';


-- ----------------------------------------------------------------------------
-- 2. Rates (CI-108, CI-106, CI-041, CI-101)
-- ----------------------------------------------------------------------------

ALTER TABLE public.rate_schedule_versions ALTER COLUMN prorate_tier_breakpoints SET DEFAULT true;

ALTER TABLE public.invoice_line_items
    ADD CONSTRAINT invoice_line_items_coverage_order_check
    CHECK (coverage_start IS NULL OR coverage_end IS NULL OR coverage_start <= coverage_end);

ALTER TABLE public.wna_zone_versions
    ADD COLUMN deadband_value       numeric(10,4),
    ADD COLUMN deadband_measure     text,
    ADD COLUMN deadband_application text,
    ADD CONSTRAINT wna_zone_versions_deadband_measure_check
        CHECK (deadband_measure IS NULL OR deadband_measure IN ('ratio_actual_to_normal', 'absolute_hdd_difference')),
    ADD CONSTRAINT wna_zone_versions_deadband_application_check
        CHECK (deadband_application IS NULL OR deadband_application IN ('full_deviation', 'excess_over_deadband')),
    ADD CONSTRAINT wna_zone_versions_deadband_value_check
        CHECK (deadband_value IS NULL OR deadband_value >= 0),
    ADD CONSTRAINT wna_zone_versions_deadband_complete_check
        CHECK ((deadband_value IS NULL) = (deadband_measure IS NULL) AND (deadband_value IS NULL) = (deadband_application IS NULL));
COMMENT ON COLUMN public.wna_zone_versions.deadband_value IS
    'v5.4.2-19 (CI-041; Kyle Q-3 2026-06-12: per utility, in the filed WNA clause, at the zone-version grain). The deadband threshold: a percentage when deadband_measure is ratio_actual_to_normal (5 = 5%), heating degree days when absolute_hdd_difference. All three deadband columns are set together or not at all; NULL = the tariff names no deadband. The in/out decision is the core''s.';
COMMENT ON COLUMN public.wna_zone_versions.deadband_measure IS
    'v5.4.2-19 (CI-041). How the deviation is measured against deadband_value: ratio_actual_to_normal (|actual/normal - 1| in percent) or absolute_hdd_difference (|actual - normal| in HDD).';
COMMENT ON COLUMN public.wna_zone_versions.deadband_application IS
    'v5.4.2-19 (CI-041). Outside the deadband: full_deviation (the whole deviation drives the adjustment) or excess_over_deadband (only the part beyond the threshold).';

CREATE OR REPLACE FUNCTION public.enforce_rate_item_dependency() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_bad    text;
    v_cycle  boolean;
BEGIN
    -- Same tenant: the schedule and both items. The foreign keys are single-
    -- column and bypass row-level security, so the check is positive: each
    -- must be VISIBLE to the writer and of this row's tenant (another
    -- tenant's row is invisible to tally_app, and a superuser sees its
    -- tenant_id).
    SELECT string_agg(x.what, ', ') INTO v_bad FROM (
        SELECT 'rate schedule ' || NEW.rate_schedule_id AS what
         WHERE NOT EXISTS (SELECT 1 FROM public.rate_schedules s WHERE s.id = NEW.rate_schedule_id AND s.tenant_id = NEW.tenant_id)
        UNION ALL
        SELECT 'rate item ' || v.item_id
          FROM unnest(ARRAY[NEW.dependent_rate_item_id, NEW.base_rate_item_id]) AS v(item_id)
         WHERE NOT EXISTS (SELECT 1 FROM public.rate_items i WHERE i.id = v.item_id AND i.tenant_id = NEW.tenant_id)
    ) x;
    IF v_bad IS NOT NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('rate_item_dependencies: %s is not a row of this dependency''s tenant (CI-101 / CI-116, v5.4.2-19)', v_bad),
            ERRCODE = 'foreign_key_violation';
    END IF;

    -- Row-version mutex on the schedule header: every writer of the
    -- schedule's dependencies bumps the same row, so two halves of a cycle
    -- written at once serialise (READ COMMITTED: the second waits and its
    -- check below sees the first; REPEATABLE READ / SERIALIZABLE: the second
    -- fails with serialization_failure). The header guard admits an
    -- updated_at-only write.
    UPDATE public.rate_schedules s SET updated_at = now() WHERE s.id = NEW.rate_schedule_id;

    -- A dependency dependent -> base closes a cycle when base already
    -- reaches dependent through the schedule's other dependencies.
    WITH RECURSIVE reach(item_id, path) AS (
        SELECT NEW.base_rate_item_id, ARRAY[NEW.base_rate_item_id]
        UNION
        SELECT d.base_rate_item_id, r.path || d.base_rate_item_id
          FROM reach r
          JOIN public.rate_item_dependencies d
            ON d.dependent_rate_item_id = r.item_id
           AND d.rate_schedule_id = NEW.rate_schedule_id
           AND d.id <> NEW.id
         WHERE NOT d.base_rate_item_id = ANY (r.path)
    )
    SELECT EXISTS (SELECT 1 FROM reach WHERE item_id = NEW.dependent_rate_item_id) INTO v_cycle;
    IF v_cycle THEN
        RAISE EXCEPTION USING
            MESSAGE = format('rate_item_dependencies: rate item %s depending on %s closes a cycle in rate schedule %s — rider composition must be a DAG (CI-101, v5.4.2-19)',
                             NEW.dependent_rate_item_id, NEW.base_rate_item_id, NEW.rate_schedule_id),
            ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$;
COMMENT ON FUNCTION public.enforce_rate_item_dependency() IS
    'v5.4.2-19 (CI-101). BEFORE INSERT OR UPDATE on rate_item_dependencies: refuses a schedule or item of another tenant, and a dependency that closes a cycle within its schedule (any length). Serialises writers on the schedule header (a row-version mutex: rate_schedules.updated_at), so concurrent halves of a cycle cannot both pass at any isolation level.';
DROP TRIGGER IF EXISTS a_enforce_rate_item_dependency ON public.rate_item_dependencies;
CREATE TRIGGER a_enforce_rate_item_dependency BEFORE INSERT OR UPDATE ON public.rate_item_dependencies
    FOR EACH ROW EXECUTE FUNCTION public.enforce_rate_item_dependency();
ALTER TABLE public.rate_item_dependencies ENABLE ALWAYS TRIGGER a_enforce_rate_item_dependency;


-- ----------------------------------------------------------------------------
-- 3. Payments (CI-058, CI-052, CI-055, CI-057)
-- ----------------------------------------------------------------------------

CREATE TABLE public.payment_effective_date_methods (
    method_code text NOT NULL,
    description text NOT NULL,
    CONSTRAINT payment_effective_date_methods_pkey PRIMARY KEY (method_code),
    CONSTRAINT payment_effective_date_methods_code_check CHECK (method_code ~ '^[a-z][a-z0-9_]*$'),
    CONSTRAINT payment_effective_date_methods_description_check CHECK (description ~ '[[:alnum:]]')
);
REVOKE ALL ON public.payment_effective_date_methods FROM PUBLIC;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON public.payment_effective_date_methods FROM tally_app, tally_core;
GRANT SELECT ON public.payment_effective_date_methods TO tally_app, tally_core;
COMMENT ON TABLE public.payment_effective_date_methods IS
    'v5.4.2-19 (CI-058). Platform vocabulary: how a payment''s effective date was determined (the register''s four). Which method a jurisdiction or channel uses is tariff/operations configuration, applied by the core; the payment records the one it used.';
INSERT INTO public.payment_effective_date_methods (method_code, description) VALUES
    ('postmark',        'The postmark date (states that treat the postmark as the timely date).'),
    ('lockbox_receipt', 'The date the lockbox or office received the payment.'),
    ('bank_settlement', 'The date the payment settled at the bank.'),
    ('other',           'Any other method; the payment''s notes say which.');

ALTER TABLE public.payments
    ADD COLUMN effective_date        date,
    ADD COLUMN effective_date_method text,
    ADD COLUMN return_code           text,
    ADD CONSTRAINT payments_effective_date_method_fkey
        FOREIGN KEY (effective_date_method) REFERENCES public.payment_effective_date_methods (method_code),
    ADD CONSTRAINT payments_effective_date_pair_check
        CHECK ((effective_date IS NULL) = (effective_date_method IS NULL)),
    ADD CONSTRAINT payments_effective_date_required_check
        CHECK (status IN ('pending', 'voided') OR effective_date IS NOT NULL),
    ADD CONSTRAINT payments_return_code_check
        CHECK (return_code IS NULL OR (return_code ~ '^R[0-9]{2}$' AND status IN ('nsf', 'reversed'))),
    ADD CONSTRAINT payments_ach_nsf_return_code_check
        CHECK (NOT (payment_method = 'ach' AND status = 'nsf') OR return_code IS NOT NULL);
COMMENT ON COLUMN public.payments.effective_date IS
    'v5.4.2-19 (CI-058). The date the payment counts as made for grace periods, late fees and posting order — distinct from payment_date, which carries channel-dependent meanings. Required, with effective_date_method, in every status but pending and voided (a payment voided at intake never took effect); write-once once the payment has left pending.';
COMMENT ON COLUMN public.payments.effective_date_method IS
    'v5.4.2-19 (CI-058). How effective_date was determined (payment_effective_date_methods), so a rebill or audit reproduces the disposition.';
COMMENT ON COLUMN public.payments.return_code IS
    'v5.4.2-19 (CI-052). The NACHA return code (R + two digits) of a returned payment: only on nsf or reversed, required on an ACH payment in nsf, write-once. nsf_reason stays the free-text note.';

CREATE UNIQUE INDEX payments_provider_transaction_once
    ON public.payments (tenant_id, source_system, provider_transaction_id)
    WHERE provider_transaction_id IS NOT NULL AND refunds_payment_id IS NULL AND nsf_original_payment_id IS NULL;
COMMENT ON INDEX public.payments_provider_transaction_once IS
    'v5.4.2-19 (CI-055). One original payment per processor transaction per source: a webhook or file delivered twice cannot post twice. Rows that cite an original (refunds_payment_id, nsf_original_payment_id) are not counted.';

CREATE OR REPLACE FUNCTION public.enforce_payment_effective_date() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_changed text[] := '{}';
BEGIN
    IF OLD.status <> 'pending' THEN
        IF NEW.effective_date        IS DISTINCT FROM OLD.effective_date        THEN v_changed := v_changed || 'effective_date'::text; END IF;
        IF NEW.effective_date_method IS DISTINCT FROM OLD.effective_date_method THEN v_changed := v_changed || 'effective_date_method'::text; END IF;
    END IF;
    IF OLD.return_code IS NOT NULL AND NEW.return_code IS DISTINCT FROM OLD.return_code THEN
        v_changed := v_changed || 'return_code'::text;
    END IF;
    IF cardinality(v_changed) > 0 THEN
        RAISE EXCEPTION USING
            MESSAGE = format('payment %s: %s is write-once once recorded (CI-058 / CI-052, v5.4.2-19); reverse the payment and post a new one', OLD.payment_number, array_to_string(v_changed, ', ')),
            ERRCODE = 'restrict_violation';
    END IF;
    RETURN NEW;
END;
$$;
COMMENT ON FUNCTION public.enforce_payment_effective_date() IS
    'v5.4.2-19. BEFORE UPDATE on payments: effective_date and effective_date_method are frozen once the payment has left pending (CI-058); return_code is frozen once set (CI-052). Beside enforce_payment_immutable, which freezes the rest of the payment''s identity.';
DROP TRIGGER IF EXISTS enforce_payment_effective_date ON public.payments;
CREATE TRIGGER enforce_payment_effective_date BEFORE UPDATE ON public.payments
    FOR EACH ROW EXECUTE FUNCTION public.enforce_payment_effective_date();
ALTER TABLE public.payments ENABLE ALWAYS TRIGGER enforce_payment_effective_date;

-- Payment methods: history by supersession (CI-057)
ALTER TABLE public.payment_methods
    ADD COLUMN supersedes_payment_method_id uuid,
    ADD COLUMN supersede_reason            text,
    ADD COLUMN noc_change_code             text,
    ADD COLUMN noc_received_at             timestamp with time zone,
    ADD CONSTRAINT payment_methods_id_tenant_id_key UNIQUE (id, tenant_id),
    ADD CONSTRAINT payment_methods_supersedes_fkey
        FOREIGN KEY (supersedes_payment_method_id, tenant_id) REFERENCES public.payment_methods (id, tenant_id),
    ADD CONSTRAINT payment_methods_supersedes_once_key UNIQUE (supersedes_payment_method_id),
    ADD CONSTRAINT payment_methods_supersedes_not_self_check CHECK (supersedes_payment_method_id IS DISTINCT FROM id),
    ADD CONSTRAINT payment_methods_supersede_reason_check
        CHECK (supersede_reason IS NULL OR supersede_reason IN ('customer_update', 'ach_notice_of_change')),
    ADD CONSTRAINT payment_methods_supersede_pair_check
        CHECK ((supersedes_payment_method_id IS NULL) = (supersede_reason IS NULL)),
    ADD CONSTRAINT payment_methods_noc_check
        CHECK (CASE WHEN supersede_reason = 'ach_notice_of_change'
                    THEN coalesce(noc_change_code, '') ~ '^C[0-9]{2}$' AND noc_received_at IS NOT NULL
                    ELSE noc_change_code IS NULL AND noc_received_at IS NULL END);
COMMENT ON COLUMN public.payment_methods.supersedes_payment_method_id IS
    'v5.4.2-19 (CI-057). The method this row replaces: a change to the account identity is a new row, never an edit. The replaced row is deactivated by the database and cannot be reactivated; each row has at most one successor, of the same customer and tenant.';
COMMENT ON COLUMN public.payment_methods.supersede_reason IS
    'v5.4.2-19 (CI-057). Why the predecessor was replaced: customer_update, or ach_notice_of_change (with noc_change_code and noc_received_at, from which the core runs the NACHA window).';

CREATE OR REPLACE FUNCTION public.enforce_payment_method_history() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_changed text[] := '{}';
    v_pred    public.payment_methods%ROWTYPE;
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF NEW.supersedes_payment_method_id IS NOT NULL THEN
            -- the predecessor row, locked: a concurrent second successor or a
            -- reactivation waits here (the UNIQUE on supersedes_payment_method_id
            -- refuses the second successor in any case)
            SELECT * INTO v_pred FROM public.payment_methods p WHERE p.id = NEW.supersedes_payment_method_id FOR UPDATE;
            IF NOT FOUND THEN
                RAISE EXCEPTION USING
                    MESSAGE = format('payment_methods: superseded method %s is not visible in this tenant (CI-057, v5.4.2-19)', NEW.supersedes_payment_method_id),
                    ERRCODE = 'foreign_key_violation';
            END IF;
            IF v_pred.customer_id <> NEW.customer_id THEN
                RAISE EXCEPTION USING
                    MESSAGE = format('payment_methods: a method supersedes only a method of the same customer (%s is customer %s''s, not %s''s) (CI-057, v5.4.2-19)', v_pred.id, v_pred.customer_id, NEW.customer_id),
                    ERRCODE = 'check_violation';
            END IF;
        END IF;
        RETURN NEW;
    END IF;

    IF NEW.id                           IS DISTINCT FROM OLD.id                           THEN v_changed := v_changed || 'id'::text; END IF;
    IF NEW.tenant_id                    IS DISTINCT FROM OLD.tenant_id                    THEN v_changed := v_changed || 'tenant_id'::text; END IF;
    IF NEW.customer_id                  IS DISTINCT FROM OLD.customer_id                  THEN v_changed := v_changed || 'customer_id'::text; END IF;
    IF NEW.provider                     IS DISTINCT FROM OLD.provider                     THEN v_changed := v_changed || 'provider'::text; END IF;
    IF NEW.provider_token               IS DISTINCT FROM OLD.provider_token               THEN v_changed := v_changed || 'provider_token'::text; END IF;
    IF NEW.method_type                  IS DISTINCT FROM OLD.method_type                  THEN v_changed := v_changed || 'method_type'::text; END IF;
    IF NEW.last_four                    IS DISTINCT FROM OLD.last_four                    THEN v_changed := v_changed || 'last_four'::text; END IF;
    IF NEW.card_brand                   IS DISTINCT FROM OLD.card_brand                   THEN v_changed := v_changed || 'card_brand'::text; END IF;
    IF NEW.bank_name                    IS DISTINCT FROM OLD.bank_name                    THEN v_changed := v_changed || 'bank_name'::text; END IF;
    IF NEW.account_type                 IS DISTINCT FROM OLD.account_type                 THEN v_changed := v_changed || 'account_type'::text; END IF;
    IF NEW.holder_name                  IS DISTINCT FROM OLD.holder_name                  THEN v_changed := v_changed || 'holder_name'::text; END IF;
    IF NEW.supersedes_payment_method_id IS DISTINCT FROM OLD.supersedes_payment_method_id THEN v_changed := v_changed || 'supersedes_payment_method_id'::text; END IF;
    IF NEW.supersede_reason             IS DISTINCT FROM OLD.supersede_reason             THEN v_changed := v_changed || 'supersede_reason'::text; END IF;
    IF NEW.noc_change_code              IS DISTINCT FROM OLD.noc_change_code              THEN v_changed := v_changed || 'noc_change_code'::text; END IF;
    IF NEW.noc_received_at              IS DISTINCT FROM OLD.noc_received_at              THEN v_changed := v_changed || 'noc_received_at'::text; END IF;
    IF NEW.created_at                   IS DISTINCT FROM OLD.created_at                   THEN v_changed := v_changed || 'created_at'::text; END IF;
    IF cardinality(v_changed) > 0 THEN
        RAISE EXCEPTION USING
            MESSAGE = format('payment method %s: the account identity is never edited (CI-057, v5.4.2-19): attempted change to %s', OLD.id, array_to_string(v_changed, ', ')),
            HINT = 'Insert a new payment_methods row with supersedes_payment_method_id pointing here and a supersede_reason.',
            ERRCODE = 'restrict_violation';
    END IF;
    IF NEW.is_active AND NOT OLD.is_active
       AND EXISTS (SELECT 1 FROM public.payment_methods s WHERE s.supersedes_payment_method_id = OLD.id) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('payment method %s was superseded and cannot be reactivated (CI-057, v5.4.2-19)', OLD.id),
            ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$;
COMMENT ON FUNCTION public.enforce_payment_method_history() IS
    'v5.4.2-19 (CI-057). BEFORE INSERT OR UPDATE on payment_methods. Insert: a superseding row names a visible method of the same customer (the predecessor is locked FOR UPDATE). Update: the account identity, the supersession and created_at are frozen; a superseded method cannot be reactivated. Mutable: nickname, is_default, is_active (down), verified_at, last_used_at, expiry (card updater), metadata.';

CREATE OR REPLACE FUNCTION public.payment_method_after_supersede() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
BEGIN
    UPDATE public.payment_methods p SET is_active = false, is_default = false
     WHERE p.id = NEW.supersedes_payment_method_id AND (p.is_active OR p.is_default);
    RETURN NULL;
END;
$$;
COMMENT ON FUNCTION public.payment_method_after_supersede() IS
    'v5.4.2-19 (CI-057). AFTER INSERT on payment_methods: the superseded method is deactivated (and loses default), so a draft can no longer use the replaced account.';

DROP TRIGGER IF EXISTS a_enforce_payment_method_history ON public.payment_methods;
CREATE TRIGGER a_enforce_payment_method_history BEFORE INSERT OR UPDATE ON public.payment_methods
    FOR EACH ROW EXECUTE FUNCTION public.enforce_payment_method_history();
ALTER TABLE public.payment_methods ENABLE ALWAYS TRIGGER a_enforce_payment_method_history;
DROP TRIGGER IF EXISTS z_payment_method_after_supersede ON public.payment_methods;
CREATE TRIGGER z_payment_method_after_supersede AFTER INSERT ON public.payment_methods
    FOR EACH ROW WHEN (NEW.supersedes_payment_method_id IS NOT NULL)
    EXECUTE FUNCTION public.payment_method_after_supersede();
ALTER TABLE public.payment_methods ENABLE ALWAYS TRIGGER z_payment_method_after_supersede;


-- ----------------------------------------------------------------------------
-- 4. Logs and records (CI-068, CI-126, CI-099, CI-128, CI-127, CI-096)
-- ----------------------------------------------------------------------------

-- created_at on an append-only log is the database's (a superuser's value is
-- kept, for history loads).
CREATE OR REPLACE FUNCTION public.stamp_log_created_at() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
BEGIN
    IF NOT (SELECT r.rolsuper FROM pg_catalog.pg_roles r WHERE r.rolname = current_user) OR NEW.created_at IS NULL THEN
        NEW.created_at := now();
    END IF;
    RETURN NEW;
END;
$$;
COMMENT ON FUNCTION public.stamp_log_created_at() IS
    'v5.4.2-19. BEFORE INSERT on an append-only log: created_at is stamped with the transaction time; a superuser''s value is kept (history loads).';

DO $$
DECLARE
    t text;
BEGIN
    FOREACH t IN ARRAY ARRAY['dunning_events', 'escheatment_events', 'ai_audit_log'] LOOP
        EXECUTE format('DROP TRIGGER IF EXISTS append_only ON public.%I', t);
        EXECUTE format('CREATE TRIGGER append_only BEFORE DELETE OR UPDATE ON public.%I FOR EACH ROW EXECUTE FUNCTION public.enforce_append_only()', t);
        EXECUTE format('ALTER TABLE public.%I ENABLE ALWAYS TRIGGER append_only', t);
        EXECUTE format('DROP TRIGGER IF EXISTS a_stamp_created_at ON public.%I', t);
        EXECUTE format('CREATE TRIGGER a_stamp_created_at BEFORE INSERT ON public.%I FOR EACH ROW EXECUTE FUNCTION public.stamp_log_created_at()', t);
        EXECUTE format('ALTER TABLE public.%I ENABLE ALWAYS TRIGGER a_stamp_created_at', t);
        EXECUTE format('REVOKE UPDATE, DELETE, TRUNCATE ON public.%I FROM tally_app, tally_core', t);
    END LOOP;
END $$;
COMMENT ON TABLE public.dunning_events IS
    'Collections steps per invoice. v5.4.2-19 (CI-068): append-only — a step is never edited or deleted; a correction is a new event. created_at is the database''s.';
COMMENT ON TABLE public.escheatment_events IS
    'Unclaimed-property due-diligence and remittance log per customer credit. v5.4.2-19 (CI-126): append-only; created_at is the database''s (event_date is the caller''s fact: when the notice went out, the claim arrived).';
COMMENT ON TABLE public.ai_audit_log IS
    'One row per AI action. v5.4.2-19 (CI-099): append-only — written once, when the action''s outcome is known; created_at is the database''s.';

ALTER TABLE public.dunning_events DROP CONSTRAINT dunning_events_invoice_id_fkey;
ALTER TABLE public.dunning_events
    ADD CONSTRAINT dunning_events_invoice_id_fkey FOREIGN KEY (invoice_id) REFERENCES public.invoices (id);

ALTER TABLE public.service_orders
    ADD CONSTRAINT service_orders_ai_audit_required_check CHECK (NOT created_by_ai OR ai_audit_id IS NOT NULL);
ALTER TABLE public.adhoc_charges
    ADD CONSTRAINT adhoc_charges_ai_audit_required_check
        CHECK ((NOT created_by_ai AND source <> 'ai_suggestion') OR ai_audit_id IS NOT NULL);

-- Anomalies (CI-128)
ALTER TABLE public.anomalies ALTER COLUMN dedup_key SET NOT NULL;
ALTER TABLE public.anomalies DROP CONSTRAINT anomalies_tenant_id_dedup_key_key;
ALTER TABLE public.anomalies
    ADD CONSTRAINT anomalies_tenant_id_dedup_key_key UNIQUE (tenant_id, dedup_key),
    ADD CONSTRAINT anomalies_dedup_key_check CHECK (dedup_key ~ '[[:alnum:]]'),
    ADD CONSTRAINT anomalies_recurrence_count_check CHECK (recurrence_count >= 1),
    ADD CONSTRAINT anomalies_detection_order_check CHECK (last_detected_at >= first_detected_at);

CREATE OR REPLACE FUNCTION public.enforce_anomaly_record() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_changed text[] := '{}';
BEGIN
    IF NEW.id                IS DISTINCT FROM OLD.id                THEN v_changed := v_changed || 'id'::text; END IF;
    IF NEW.tenant_id         IS DISTINCT FROM OLD.tenant_id         THEN v_changed := v_changed || 'tenant_id'::text; END IF;
    IF NEW.dedup_key         IS DISTINCT FROM OLD.dedup_key         THEN v_changed := v_changed || 'dedup_key'::text; END IF;
    IF NEW.anomaly_type      IS DISTINCT FROM OLD.anomaly_type      THEN v_changed := v_changed || 'anomaly_type'::text; END IF;
    IF NEW.entity_type       IS DISTINCT FROM OLD.entity_type       THEN v_changed := v_changed || 'entity_type'::text; END IF;
    IF NEW.entity_id         IS DISTINCT FROM OLD.entity_id         THEN v_changed := v_changed || 'entity_id'::text; END IF;
    IF NEW.first_detected_at IS DISTINCT FROM OLD.first_detected_at THEN v_changed := v_changed || 'first_detected_at'::text; END IF;
    IF NEW.created_at        IS DISTINCT FROM OLD.created_at        THEN v_changed := v_changed || 'created_at'::text; END IF;
    IF NEW.recurrence_count < OLD.recurrence_count                   THEN v_changed := v_changed || 'recurrence_count (decrease)'::text; END IF;
    IF NEW.last_detected_at < OLD.last_detected_at                   THEN v_changed := v_changed || 'last_detected_at (moved back)'::text; END IF;
    IF cardinality(v_changed) > 0 THEN
        RAISE EXCEPTION USING
            MESSAGE = format('anomaly %s: the canonical row''s identity and first detection are write-once, its recurrence only grows (CI-128, v5.4.2-19): attempted change to %s', OLD.id, array_to_string(v_changed, ', ')),
            ERRCODE = 'restrict_violation';
    END IF;
    RETURN NEW;
END;
$$;
COMMENT ON FUNCTION public.enforce_anomaly_record() IS
    'v5.4.2-19 (CI-128). BEFORE UPDATE on anomalies: the dedup key, the subject (type, entity), first_detected_at and created_at are write-once; recurrence_count never decreases and last_detected_at never moves back. A recurring detection updates the canonical row; resolution fields stay editable.';
DROP TRIGGER IF EXISTS a_enforce_anomaly_record ON public.anomalies;
CREATE TRIGGER a_enforce_anomaly_record BEFORE UPDATE ON public.anomalies
    FOR EACH ROW EXECUTE FUNCTION public.enforce_anomaly_record();
ALTER TABLE public.anomalies ENABLE ALWAYS TRIGGER a_enforce_anomaly_record;

-- Ad-hoc charge approval capture (CI-127)
ALTER TABLE public.adhoc_charges
    ADD CONSTRAINT adhoc_charges_approval_threshold_check
        CHECK ((NOT requires_approval OR approval_threshold_at_creation IS NOT NULL)
               AND (approval_threshold_at_creation IS NULL OR approval_threshold_at_creation >= 0));

CREATE OR REPLACE FUNCTION public.enforce_adhoc_charge_approval_capture() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
BEGIN
    IF NEW.requires_approval IS DISTINCT FROM OLD.requires_approval
       OR NEW.approval_threshold_at_creation IS DISTINCT FROM OLD.approval_threshold_at_creation THEN
        RAISE EXCEPTION USING
            MESSAGE = format('adhoc charge %s: requires_approval and approval_threshold_at_creation record the rule in force when the charge was created and are write-once (CI-127, v5.4.2-19)', OLD.charge_number),
            ERRCODE = 'restrict_violation';
    END IF;
    RETURN NEW;
END;
$$;
COMMENT ON FUNCTION public.enforce_adhoc_charge_approval_capture() IS
    'v5.4.2-19 (CI-127). BEFORE UPDATE on adhoc_charges: requires_approval and approval_threshold_at_creation are write-once (the approval rule in force at creation; a later threshold change never reclassifies an existing charge).';
DROP TRIGGER IF EXISTS enforce_adhoc_charge_approval_capture ON public.adhoc_charges;
CREATE TRIGGER enforce_adhoc_charge_approval_capture BEFORE UPDATE ON public.adhoc_charges
    FOR EACH ROW EXECUTE FUNCTION public.enforce_adhoc_charge_approval_capture();
ALTER TABLE public.adhoc_charges ENABLE ALWAYS TRIGGER enforce_adhoc_charge_approval_capture;

-- Invoice image hash (CI-096)
ALTER TABLE public.invoices
    ADD COLUMN pdf_sha256 text,
    ADD CONSTRAINT invoices_pdf_sha256_check CHECK (pdf_sha256 IS NULL OR pdf_sha256 ~ '^[0-9a-f]{64}$'),
    ADD CONSTRAINT invoices_pdf_sha256_pair_check CHECK ((pdf_url IS NULL) = (pdf_sha256 IS NULL));
COMMENT ON COLUMN public.invoices.pdf_sha256 IS
    'v5.4.2-19 (CI-096). SHA-256 (lowercase hex) of the bill image the customer received at pdf_url: set with pdf_url, write-once with it, so a changed object behind the URL is detectable.';

CREATE OR REPLACE FUNCTION public.enforce_invoice_image_hash() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
BEGIN
    IF OLD.pdf_sha256 IS NOT NULL AND NEW.pdf_sha256 IS DISTINCT FROM OLD.pdf_sha256 THEN
        RAISE EXCEPTION USING
            MESSAGE = format('invoice %s: pdf_sha256 is write-once — it fingerprints the image the customer received (CI-096, v5.4.2-19)', OLD.invoice_number),
            ERRCODE = 'restrict_violation';
    END IF;
    RETURN NEW;
END;
$$;
COMMENT ON FUNCTION public.enforce_invoice_image_hash() IS
    'v5.4.2-19 (CI-096). BEFORE UPDATE on invoices: pdf_sha256 is write-once (pdf_url and pdf_generated_at are write-once in enforce_invoice_immutable; the pair CHECK sets the hash with the URL).';
DROP TRIGGER IF EXISTS enforce_invoice_image_hash ON public.invoices;
CREATE TRIGGER enforce_invoice_image_hash BEFORE UPDATE ON public.invoices
    FOR EACH ROW EXECUTE FUNCTION public.enforce_invoice_image_hash();
ALTER TABLE public.invoices ENABLE ALWAYS TRIGGER enforce_invoice_image_hash;


-- ----------------------------------------------------------------------------
-- 5. Imports (CI-118, CI-098)
-- ----------------------------------------------------------------------------

ALTER TABLE public.import_jobs
    ADD CONSTRAINT import_jobs_file_source_check
        CHECK (source_type NOT IN ('csv', 'excel', 'pdf', 'legacy_export')
               OR (coalesce(source_filename, '') ~ '[[:alnum:]]' AND coalesce(source_file_hash, '') ~ '[[:alnum:]]'));
ALTER TABLE public.import_jobs DROP CONSTRAINT import_jobs_import_type_check;
ALTER TABLE public.import_jobs
    ADD CONSTRAINT import_jobs_import_type_check
        CHECK (import_type IN ('customers', 'meters', 'readings', 'rates', 'payments', 'locations', 'full_system', 'custom',
                               'ach_return', 'lockbox', 'amr'));
CREATE UNIQUE INDEX import_jobs_file_once
    ON public.import_jobs (tenant_id, source_file_hash, import_type, is_dry_run)
    WHERE source_file_hash IS NOT NULL AND status NOT IN ('failed', 'cancelled');
COMMENT ON INDEX public.import_jobs_file_once IS
    'v5.4.2-19 (CI-118). One live job per tenant, file content, import type and preview/commit: a renamed copy of a file already imported (or one submitted with a fresh idempotency_key) is refused. A failed or cancelled job frees the file for a retry.';


-- ----------------------------------------------------------------------------
-- 6. Programs (CI-062)
-- ----------------------------------------------------------------------------

ALTER TABLE public.program_types ADD COLUMN requires_attestation boolean NOT NULL DEFAULT false;
UPDATE public.program_types SET requires_attestation = true WHERE code = 'medical_certificate';
COMMENT ON COLUMN public.program_types.requires_attestation IS
    'v5.4.2-19 (CI-062). An active enrollment of this type must carry its attestation document (attestation_artifact_url) and the time it was received. True for medical_certificate.';

ALTER TABLE public.customer_program_enrollments
    ADD CONSTRAINT customer_program_enrollments_verification_check
        CHECK ((attestation_verified_at IS NULL) = (attestation_verified_by IS NULL)
               AND (attestation_verified_at IS NULL OR (attestation_received_at IS NOT NULL AND attestation_verified_at >= attestation_received_at)));

CREATE OR REPLACE FUNCTION public.enforce_enrollment_attestation() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
BEGIN
    IF NEW.status = 'active'
       AND (SELECT t.requires_attestation FROM public.program_types t WHERE t.code = NEW.program_type)
       AND (NEW.attestation_received_at IS NULL OR coalesce(NEW.attestation_artifact_url, '') !~ '[[:alnum:]]') THEN
        RAISE EXCEPTION USING
            MESSAGE = format('enrollment %s: an active %s enrollment carries its attestation document and the time it was received (CI-062, v5.4.2-19)', NEW.id, NEW.program_type),
            ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$;
COMMENT ON FUNCTION public.enforce_enrollment_attestation() IS
    'v5.4.2-19 (CI-062). BEFORE INSERT OR UPDATE on customer_program_enrollments: an active enrollment of a type with requires_attestation names its document (attestation_artifact_url) and attestation_received_at.';
DROP TRIGGER IF EXISTS a_enforce_enrollment_attestation ON public.customer_program_enrollments;
CREATE TRIGGER a_enforce_enrollment_attestation BEFORE INSERT OR UPDATE ON public.customer_program_enrollments
    FOR EACH ROW EXECUTE FUNCTION public.enforce_enrollment_attestation();
ALTER TABLE public.customer_program_enrollments ENABLE ALWAYS TRIGGER a_enforce_enrollment_attestation;


-- ----------------------------------------------------------------------------
-- 7. Ledger balance (CI-019, helper)
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.account_balance_as_of(p_customer_id uuid, p_on date, p_recorded_at timestamp with time zone) RETURNS numeric
    LANGUAGE plpgsql STABLE
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_sum numeric;
BEGIN
    IF p_customer_id IS NULL OR p_on IS NULL OR p_recorded_at IS NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = 'account_balance_as_of: customer, date and recorded-at coordinate are all required; never default to today (v5.4.2-19)',
            ERRCODE = 'null_value_not_allowed';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.customers c WHERE c.id = p_customer_id) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('account_balance_as_of: customer %s is not visible in this tenant', p_customer_id),
            ERRCODE = 'no_data_found';
    END IF;
    SELECT coalesce(sum(l.amount), 0) INTO v_sum
      FROM public.account_ledger l
     WHERE l.customer_id = p_customer_id
       AND l.transaction_date <= p_on
       AND l.created_at <= p_recorded_at;
    RETURN v_sum;
END;
$$;
COMMENT ON FUNCTION public.account_balance_as_of(uuid, date, timestamp with time zone) IS
    'v5.4.2-19 (CI-019). The customer''s ledger balance: the sum of account_ledger amounts dated on or before p_on and recorded (created_at) by p_recorded_at. Order-independent, unlike running_balance. All coordinates required; a customer not visible raises.';
REVOKE ALL ON FUNCTION public.account_balance_as_of(uuid, date, timestamp with time zone) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.account_balance_as_of(uuid, date, timestamp with time zone) TO tally_app, tally_core;

-- ============================================================================
-- END PATCH v5.4.2-19
-- ============================================================================

COMMIT;
\endif
