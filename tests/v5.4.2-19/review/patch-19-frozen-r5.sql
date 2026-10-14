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
-- Revision r2 (review round 1: Opus, Fable, Codex):
--   reads are born unconsumed (an application INSERT carries no lock record);
--   a consumed read freezes every column but a named follow-up whitelist,
--   and its lock pointers move only by void_invoice()'s write or a correction
--   run's re-lock; the lock flag is set only by the move to locked; one
--   receipt per processor transaction keys on money in (amount > 0), and a
--   refund must be one; AI citations bind the tenant and are write-once;
--   import jobs' file identity is write-once, finished statuses final, one
--   live commit per file whatever its type; the ledger's created_at is the
--   database's; the rider walk is a set (linear) with a stated lock order;
--   an issued invoice's image and hash are frozen together, a draft's change
--   together; a superseded method cannot be made default; anomalies freeze
--   their subject and detection; the ledger's stored running balance is
--   dropped (Ryan, 2026-10-13), void_invoice() returning the summed balance.
--   Codex B4: supersession always rewrites the predecessor, inactive or
--   not, so a concurrent reactivation cannot slip past on an old snapshot.
--
-- Revision r3 (review round 2: Codex ready, Opus ready, Fable not yet):
--   a refund (any money out) delivered twice is refused, as a receipt is;
--   a refund or replacement cites the same customer's payment; an unconsumed
--   read's lock record is written only by the move to locked; a finished
--   import job's stored file and counts are frozen; account_ledger's table
--   comment no longer describes the dropped column; the rider lock order
--   names headers-before-edges; R15-R18 record what was left on purpose.
--
-- Revision r4 (review round 3: Opus ready, Fable ready, Codex not yet):
--   refund and replacement lineage are composite foreign keys on (id,
--   tenant_id, customer_id): a cited payment cannot move to another customer
--   (Codex B1 / Opus S1); a payment cannot cite itself. A read in locked or
--   void_released must carry the lock flag (a table CHECK, every role). A
--   finished import job's counts, summary, errors and completion time are
--   its snapshot at finish (r5, documentation and tests only: the
--   precondition names the two r4 constraints; R13 and R17 state the
--   one-write finish and the three-write re-homing). The money-out rule is stated for every negative
--   row (chargebacks included), not refunds alone.
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
--   * CI-055. One receipt and one refund per processor transaction per
--     source: UNIQUE (tenant_id, source_system, provider_transaction_id) over
--     money in (amount > 0, a replacement for a bounced payment included) and
--     again over money out (amount < 0). A row citing a refunded payment must
--     be a negative refund; a refund or replacement cites a payment of the
--     same customer.
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
--     and its hash; one live commit per tenant and file hash, whatever its
--     import type (previews and failed or cancelled jobs do not count), so a
--     renamed copy of a file already imported is refused — the
--     idempotency_key (filename-based, or caller-supplied) no longer decides
--     that alone. A job's file identity is write-once; a finished job's
--     status, stored file and row counts are final (a snapshot at finish;
--     the staging rows remain the live record of held rows).
--   * CI-098. import_type gains ach_return, lockbox and amr.
--   Programs
--   * CI-062. program_types.requires_attestation (true for
--     medical_certificate). An active enrollment of such a type carries its
--     attestation document and the time it was received; a verification
--     names who verified, and comes after receipt.
--   Ledger
--   * CI-019. account_ledger.running_balance is DROPPED with its trigger
--     (Ryan, 2026-10-13); void_invoice() returns the summed balance instead.
--   * CI-019. account_balance_as_of(customer, on, recorded):
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
--   R2. (closed in r2: the running balance is dropped, section 8.)
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
--   R11. CI-099 / CI-116: the other edges into ai_audit_log (parent_audit_id,
--       ai_suggestions, ai_tool_calls) and customer_interactions.ai_audit_id
--       (no foreign key at all) are not tenant-bound; that is the general
--       composite-foreign-key question (Ryan).
--   R12. CI-101: a dependency on an archived schedule is accepted; a
--       transaction writing several schedules' dependencies must take them in
--       schedule-id order (opposite orders deadlock; one is cancelled).
--   R13. CI-118: the file hash has no format rule (the algorithm is the
--       intake's); a job cancelled mid-import after committing rows frees the
--       file (the core marks such a job partial, not cancelled). Contract
--       (R9): a job finishes in ONE write — the terminal status with its
--       final counts, stored file, summary, validation errors and
--       completed_at; a later write of any of them is refused.
--   R14. AC-12: app.void_operation is still caller-settable; with it a caller
--       can release a locked read without voiding its bill (only the pointer
--       write void_invoice() does is admitted). Sealing void_invoice() behind
--       a definer is the A-23 question (Ryan).
--   R15. CI-031: the move to locked requires the run, not the bill; a read
--       locked without locked_by_invoice_id can never get it (the pointer is
--       frozen) and void_invoice() can never release it. Contract (R9): a run
--       sets the bill pointer in the same write as the lock. A read's
--       voided_from_invoice_id holds the latest void only; earlier voids are
--       in invoice_events.
--   R16. CI-057: a payment may cite an inactive (superseded) method — a
--       late confirmation of a charge on the old account is a true record;
--       choosing the account to draw on is the core's.
--   R17. CI-055: duplicates are keyed on source_system, the capture
--       channel: one processor transaction arriving by webhook and again in
--       an imported settlement file posts twice (the core matches across
--       channels); a zero-amount row is not counted; a pending row's amount
--       is editable, so its slot is held only while its sign is. Intake must
--       not read a unique_violation on payments_provider_refund_once as a
--       harmless redelivery without comparing the rows: a chargeback reusing
--       a refunded charge's id is a distinct event and needs its own id.
--       Likewise an ACH re-presentment is a new transaction with its own id;
--       one reusing the original's id is refused as a duplicate receipt.
--       Re-homing a cited pending payment with its pending refund to another
--       customer is three writes: clear the refund's pointer, move the
--       payment, then move the refund and re-point it in one UPDATE (one
--       statement moving both succeeds only if the payment row is first).
--   R18. CI-025: on a consumed read, status is follow-up work (whitelisted),
--       but populate_reading_calculations takes the "previous" read by
--       status = 'active', so marking a consumed read disputed changes the
--       next read's database-filled previous_value; field-reader confirmation
--       and quality_flag are frozen after consumption (a domain call, R9).
--
-- PRECONDITION. v5.4.2-18 and -15 applied (tu.sql). The tables tightened are
--   empty in every database built from tu.sql; on a database with rows, a
--   new CHECK or NOT NULL fails the patch rather than skip a row (anomalies
--   without dedup_key, ad-hoc charges requiring approval without threshold,
--   AI rows without audit, file imports without hash, active medical holds
--   without attestation, a refund or replacement citing another customer's
--   payment, a locked or void_released read without billing_period_locked).
--   Applied by a superuser, under READ COMMITTED.
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
    v_relock            boolean;
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
    -- The lock flag is set only by the move to locked (a flag set on a read no
    -- run consumed would freeze it with a false "consumed" record).
    -- -------------------------------------------------------------------------
    IF NOT OLD.billing_period_locked AND NEW.billing_period_locked AND NEW.validation_status IS DISTINCT FROM 'locked' THEN
        RAISE EXCEPTION USING
            MESSAGE = format('meter reading %s: billing_period_locked is set only by the move to locked, by a billing run (CI-031, v5.4.2-19)', OLD.id),
            ERRCODE = 'check_violation';
    END IF;

    -- r3 (Fable S1): nor is the rest of the lock record written on a read no
    -- run has consumed. The lock time, run and bill come only with the move
    -- to locked; voided_from_invoice_id only from a void (Block 3).
    IF NOT OLD.billing_period_locked THEN
        IF NEW.voided_from_invoice_id IS DISTINCT FROM OLD.voided_from_invoice_id
           OR (NEW.validation_status IS DISTINCT FROM 'locked'
               AND (NEW.locked_at IS DISTINCT FROM OLD.locked_at
                    OR NEW.locked_by_billing_run_id IS DISTINCT FROM OLD.locked_by_billing_run_id
                    OR NEW.locked_by_invoice_id IS DISTINCT FROM OLD.locked_by_invoice_id)) THEN
            RAISE EXCEPTION USING
                MESSAGE = format('meter reading %s: the lock record (locked_at, locked_by_*, voided_from_invoice_id) of a read no billing run has consumed is written only by the move to locked (CI-031, v5.4.2-19)', OLD.id),
                ERRCODE = 'check_violation';
        END IF;
    END IF;

    -- -------------------------------------------------------------------------
    -- BLOCK 2: a read a billing run consumed keeps its record (v5.4.2-19,
    -- CI-025 / CI-031). Keyed on billing_period_locked, which stays true after
    -- void_released: the read a voided bill released is the evidence the
    -- correction run rebills from, and is frozen like a locked one. EVERY
    -- column is frozen except the follow-up fields named here (r2: a
    -- whitelist, so a column added later is frozen by default) and the lock
    -- fields Block 3 governs.
    -- -------------------------------------------------------------------------
    IF OLD.billing_period_locked THEN
        SELECT coalesce(array_agg(o.key ORDER BY o.key), '{}') INTO v_changed
          FROM jsonb_each(to_jsonb(OLD)) o
         WHERE o.key <> ALL (ARRAY[
                   -- follow-up work on a consumed read
                   'notes', 'tamper_investigated', 'tamper_investigation_notes',
                   'dispute_reason', 'dispute_raised_by', 'dispute_raised_at',
                   'dispute_resolved_by', 'dispute_resolved_at', 'dispute_resolution_notes',
                   'status', 'requires_followup', 'followup_priority', 'followup_notes',
                   'assigned_to_user_id', 'replaced_by_reading_id', 'triggers_correction_workflow',
                   -- governed by Block 1 and Block 3
                   'validation_status', 'locked_at', 'locked_by_billing_run_id',
                   'locked_by_invoice_id', 'voided_from_invoice_id'])
           AND o.value IS DISTINCT FROM (to_jsonb(NEW) -> o.key);
    END IF;

    -- -------------------------------------------------------------------------
    -- BLOCK 3: the lock pointers of a consumed read (locked or void_released).
    -- Two writes may move them: void_invoice()'s (locked -> void_released:
    -- locked_by_invoice_id cleared, voided_from_invoice_id := the bill it
    -- held, run and lock time unchanged) and a correction run's re-lock
    -- (released_to_billing -> locked: its own run, a bill where there was
    -- none, the lock time stamped by Block 1). voided_from_invoice_id is
    -- written by a void and by nothing else.
    -- -------------------------------------------------------------------------
    IF OLD.billing_period_locked THEN
        v_relock := OLD.validation_status = 'released_to_billing' AND NEW.validation_status = 'locked';
        IF v_void_transition THEN
            IF NEW.locked_by_invoice_id IS NOT NULL THEN v_changed := v_changed || 'locked_by_invoice_id (void must clear it)'::text; END IF;
            IF NEW.voided_from_invoice_id IS DISTINCT FROM OLD.locked_by_invoice_id THEN v_changed := v_changed || 'voided_from_invoice_id (void sets it to the bill it held)'::text; END IF;
        ELSE
            IF NEW.voided_from_invoice_id IS DISTINCT FROM OLD.voided_from_invoice_id THEN v_changed := v_changed || 'voided_from_invoice_id'::text; END IF;
            IF NEW.locked_by_invoice_id IS DISTINCT FROM OLD.locked_by_invoice_id
               AND NOT (v_relock AND OLD.locked_by_invoice_id IS NULL) THEN
                v_changed := v_changed || 'locked_by_invoice_id'::text;
            END IF;
        END IF;
        IF NOT v_relock THEN
            IF NEW.locked_by_billing_run_id IS DISTINCT FROM OLD.locked_by_billing_run_id THEN v_changed := v_changed || 'locked_by_billing_run_id'::text; END IF;
            IF NEW.locked_at                IS DISTINCT FROM OLD.locked_at                THEN v_changed := v_changed || 'locked_at'::text; END IF;
        END IF;
    END IF;

    IF cardinality(v_changed) > 0 THEN
        RAISE EXCEPTION USING
            MESSAGE = format('meter reading %s was consumed by a billing run (validation_status %s, billing_period_locked) and its billing fields are frozen (CI-025 / CI-031, v5.4.2-19): attempted change to %s',
                             OLD.id, OLD.validation_status, array_to_string(v_changed, ', ')),
            HINT = 'To correct a read, insert a NEW reading with replaces_read_id pointing here. To undo the bill, use void_invoice(). Editable on such reads: notes, tamper_investigated, tamper_investigation_notes, dispute_*, status, requires_followup, followup_*, assigned_to_user_id, replaced_by_reading_id, triggers_correction_workflow.',
            ERRCODE = 'restrict_violation';
    END IF;

    RETURN NEW;
END;
$$;
COMMENT ON FUNCTION public.enforce_reading_validation_workflow() IS
    'BEFORE UPDATE on meter_readings. Block 1: the validation_status transition matrix; locked -> void_released only under void_invoice() (app.void_operation); a move to locked needs billing_period_locked and locked_by_billing_run_id, and locked_at is stamped by the database (a superuser''s value kept). billing_period_locked is set only by the move to locked. Block 2 (v5.4.2-19, CI-025/CI-031): once billing_period_locked is true — locked AND void_released — every column is frozen except the follow-up fields (notes, tamper investigation, dispute_*, status, follow-up, assignee, replaced_by_reading_id, triggers_correction_workflow) and the lock fields of Block 3. Block 3: the lock pointers move only by void_invoice()''s exact write (locked_by_invoice_id -> NULL, voided_from_invoice_id := the bill it held) or a correction run''s re-lock (released_to_billing -> locked: its run, a bill where there was none, the stamped time).';

CREATE OR REPLACE FUNCTION public.enforce_reading_born_unconsumed() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
BEGIN
    IF (SELECT r.rolsuper FROM pg_catalog.pg_roles r WHERE r.rolname = current_user) THEN
        RETURN NEW;  -- a reviewed history load may carry its lock record
    END IF;
    IF NEW.billing_period_locked OR NEW.validation_status IN ('locked', 'void_released')
       OR NEW.locked_at IS NOT NULL OR NEW.locked_by_billing_run_id IS NOT NULL
       OR NEW.locked_by_invoice_id IS NOT NULL OR NEW.voided_from_invoice_id IS NOT NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('meter reading for meter %s: a read is born unconsumed — the lock record (billing_period_locked, locked/void_released, locked_*, voided_from_invoice_id) is written only by a billing run''s move to locked and by void_invoice() (CI-031, v5.4.2-19)', NEW.meter_id),
            ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$;
COMMENT ON FUNCTION public.enforce_reading_born_unconsumed() IS
    'v5.4.2-19 r2 (CI-031). BEFORE INSERT on meter_readings: an application read is born without a lock record — not locked or void_released, flag false, no lock pointers, no voided_from. A superuser''s history load may carry one.';
DROP TRIGGER IF EXISTS a_enforce_reading_born_unconsumed ON public.meter_readings;
CREATE TRIGGER a_enforce_reading_born_unconsumed BEFORE INSERT ON public.meter_readings
    FOR EACH ROW EXECUTE FUNCTION public.enforce_reading_born_unconsumed();
ALTER TABLE public.meter_readings ENABLE ALWAYS TRIGGER a_enforce_reading_born_unconsumed;
-- r3 (Fable N8): the read guards this patch rewrites fire as every new one does.
ALTER TABLE public.meter_readings ENABLE ALWAYS TRIGGER trg_enforce_reading_validation_workflow;
ALTER TABLE public.meter_readings ENABLE ALWAYS TRIGGER trg_populate_reading_calculations;
ALTER TABLE public.meter_readings ENABLE ALWAYS TRIGGER dry_run_no_read_locks;
ALTER TABLE public.meter_readings ENABLE ALWAYS TRIGGER trg_populate_reading_location;
-- r4 (Opus r3 N3): a read in locked or void_released carries the lock flag,
-- for every role — a history load included — so no consumed read escapes
-- Block 2 by a missing flag.
ALTER TABLE public.meter_readings
    ADD CONSTRAINT meter_readings_consumed_flag_check
        CHECK (validation_status NOT IN ('locked', 'void_released') OR billing_period_locked);
COMMENT ON COLUMN public.meter_readings.voided_from_invoice_id IS
    'Set during a void operation to preserve the invoice that originally locked this read, before locked_by_invoice_id is cleared. Enables full audit traversal: read -> voided invoice -> correction invoice. Written only by a void (v5.4.2-19); it holds the latest void — a read voided again after a re-lock names the second bill, and invoice_events keeps both.';


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

    -- Lock order (AC, r2/r3): a transaction that writes dependencies takes
    -- the schedule headers first, in schedule-id order (this bump, or
    -- assert_reference_version), and only then writes dependency rows; an
    -- UPDATE of an edge locks the edge before this bump, so a transaction
    -- holding the header that then edits the edge, against one editing the
    -- edge, deadlocks. PostgreSQL cancels one; the caller retries the whole
    -- transaction on deadlock_detected or serialization_failure. A cancelled
    -- participant never lets a cycle through.
    -- Row-version mutex on the schedule header: every writer of the
    -- schedule's dependencies bumps the same row, so two halves of a cycle
    -- written at once serialise (READ COMMITTED: the second waits and its
    -- check below sees the first; REPEATABLE READ / SERIALIZABLE: the second
    -- fails with serialization_failure). The header guard admits an
    -- updated_at-only write.
    UPDATE public.rate_schedules s SET updated_at = now() WHERE s.id = NEW.rate_schedule_id;

    -- A dependency dependent -> base closes a cycle when base already
    -- reaches dependent through the schedule's other dependencies.
    -- (r2: a reachable set, not paths — UNION drops an item already
    -- reached, so the walk is linear in the schedule's dependencies.)
    WITH RECURSIVE reach(item_id) AS (
        SELECT NEW.base_rate_item_id
        UNION
        SELECT d.base_rate_item_id
          FROM reach r
          JOIN public.rate_item_dependencies d
            ON d.dependent_rate_item_id = r.item_id
           AND d.rate_schedule_id = NEW.rate_schedule_id
           AND d.id <> NEW.id
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

-- r2 (Opus B3, Fable B1): the rule keys on the act — money in — not on a
-- lineage label a caller chooses. Every positive payment with a processor id
-- counts, a replacement for a bounced payment included (nsf_original_payment_id
-- marks a REPLACEMENT, a fresh receipt); a refund is money out, and a row that
-- cites a refunded payment must be one.
ALTER TABLE public.payments
    ADD CONSTRAINT payments_refund_is_refund_check
        CHECK (refunds_payment_id IS NULL OR (payment_method = 'refund' AND amount < 0));
CREATE UNIQUE INDEX payments_provider_transaction_once
    ON public.payments (tenant_id, source_system, provider_transaction_id)
    WHERE provider_transaction_id IS NOT NULL AND amount > 0;
COMMENT ON INDEX public.payments_provider_transaction_once IS
    'v5.4.2-19 (CI-055). One receipt per processor transaction per source: a webhook or file delivered twice cannot post twice, whatever lineage it claims. Every positive payment counts (a replacement for a bounced payment is a fresh receipt). Money out is counted by payments_provider_refund_once; a zero-amount row is counted by neither.';
-- r3 (Fable B1, Opus S4): money out delivered twice must not go out twice.
-- One refund (any negative row) per processor id per source. A refund may
-- share its original's id (one receipt and one refund per id), but a second
-- refund of the same payment — a partial refund — carries the processor's own
-- id for that refund event, never the original's again.
CREATE UNIQUE INDEX payments_provider_refund_once
    ON public.payments (tenant_id, source_system, provider_transaction_id)
    WHERE provider_transaction_id IS NOT NULL AND amount < 0;
COMMENT ON INDEX public.payments_provider_refund_once IS
    'v5.4.2-19 r3 (CI-055). One money-out row per processor transaction per source — every negative row: a refund, a chargeback, a reversal recorded as its own row — so one delivered twice cannot pay out twice. A money-out row may carry its original''s id once; any further one (a second partial refund, a chargeback after a refund) carries the processor''s own id for that event (a dispute id, a refund id), or a chargeback is recorded as status reversed on the original. A zero-amount row is not counted.';

-- r3 (Fable S2, Opus PR3): the payment a refund or a replacement cites is the
-- same customer's. A positive check (visible AND same tenant AND same
-- customer): row-level security hides another tenant's payment, so absence
-- of a mismatch proves nothing.
CREATE OR REPLACE FUNCTION public.enforce_payment_lineage() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_ref  uuid;
    v_kind text;
BEGIN
    FOREACH v_kind IN ARRAY ARRAY['refunds_payment_id', 'nsf_original_payment_id'] LOOP
        v_ref := CASE v_kind WHEN 'refunds_payment_id' THEN NEW.refunds_payment_id ELSE NEW.nsf_original_payment_id END;
        CONTINUE WHEN v_ref IS NULL;
        IF NOT EXISTS (SELECT 1 FROM public.payments o
                        WHERE o.id = v_ref AND o.tenant_id = NEW.tenant_id AND o.customer_id = NEW.customer_id) THEN
            RAISE EXCEPTION USING
                MESSAGE = format('payment %s: %s %s is not a payment of this customer (CI-055, v5.4.2-19)', NEW.payment_number, v_kind, v_ref),
                ERRCODE = 'foreign_key_violation';
        END IF;
    END LOOP;
    RETURN NEW;
END;
$$;
COMMENT ON FUNCTION public.enforce_payment_lineage() IS
    'v5.4.2-19 r3 (CI-055). BEFORE INSERT OR UPDATE on payments: refunds_payment_id and nsf_original_payment_id name a visible payment of the same tenant and customer.';
DROP TRIGGER IF EXISTS a_enforce_payment_lineage ON public.payments;
CREATE TRIGGER a_enforce_payment_lineage BEFORE INSERT OR UPDATE OF refunds_payment_id, nsf_original_payment_id, customer_id, tenant_id ON public.payments
    FOR EACH ROW EXECUTE FUNCTION public.enforce_payment_lineage();
ALTER TABLE public.payments ENABLE ALWAYS TRIGGER a_enforce_payment_lineage;
-- r4 (Codex B1, Opus S1): the trigger checks from the citing row only; a
-- cited payment still pending could then move to another customer. The
-- edges are now composite foreign keys on (id, tenant_id, customer_id), so
-- the cited row's customer cannot change while anything cites it (NO
-- ACTION), and the key lock serialises a concurrent citation against a move.
-- A payment does not cite itself.
ALTER TABLE public.payments
    ADD CONSTRAINT payments_id_tenant_customer_key UNIQUE (id, tenant_id, customer_id),
    DROP CONSTRAINT payments_refunds_payment_id_fkey,
    DROP CONSTRAINT payments_nsf_original_payment_id_fkey,
    ADD CONSTRAINT payments_refunds_payment_id_fkey
        FOREIGN KEY (refunds_payment_id, tenant_id, customer_id) REFERENCES public.payments (id, tenant_id, customer_id),
    ADD CONSTRAINT payments_nsf_original_payment_id_fkey
        FOREIGN KEY (nsf_original_payment_id, tenant_id, customer_id) REFERENCES public.payments (id, tenant_id, customer_id),
    ADD CONSTRAINT payments_lineage_not_self_check
        CHECK (refunds_payment_id IS DISTINCT FROM id AND nsf_original_payment_id IS DISTINCT FROM id);

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
    IF ((NEW.is_active AND NOT OLD.is_active) OR (NEW.is_default AND NOT OLD.is_default))
       AND EXISTS (SELECT 1 FROM public.payment_methods s WHERE s.supersedes_payment_method_id = OLD.id) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('payment method %s was superseded and cannot be reactivated or made the default (CI-057, v5.4.2-19)', OLD.id),
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
    -- Unconditional (r2, Codex B4): the write is the row-version mutex. An
    -- already-inactive predecessor must still get a new version, or a
    -- REPEATABLE READ reactivation that waited on its lock commits it active.
    UPDATE public.payment_methods p SET is_active = false, is_default = false
     WHERE p.id = NEW.supersedes_payment_method_id;
    RETURN NULL;
END;
$$;
COMMENT ON FUNCTION public.payment_method_after_supersede() IS
    'v5.4.2-19 (CI-057). AFTER INSERT on payment_methods: the superseded method is deactivated (and loses default), so the core no longer draws on the replaced account. A payment row may still cite it: a processor can confirm a charge on the old account after the customer replaced it, and the record says what was drawn (R16). The predecessor is always rewritten, even when already inactive: that new row version makes a concurrent reactivation fail to serialise (REPEATABLE READ) or re-read and be refused (READ COMMITTED).';

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

-- r2 (Opus B4): the citation is to an audit row of the SAME tenant. The
-- single-column foreign keys bypass row-level security; composite ones bind
-- the tenant. The other edges into ai_audit_log (parent, suggestions, tool
-- calls) are CI-116's general question (residual R11).
ALTER TABLE public.ai_audit_log ADD CONSTRAINT ai_audit_log_id_tenant_id_key UNIQUE (id, tenant_id);
ALTER TABLE public.service_orders DROP CONSTRAINT service_orders_ai_audit_id_fkey;
ALTER TABLE public.service_orders
    ADD CONSTRAINT service_orders_ai_audit_id_fkey FOREIGN KEY (ai_audit_id, tenant_id) REFERENCES public.ai_audit_log (id, tenant_id);
ALTER TABLE public.adhoc_charges DROP CONSTRAINT fk_adhoc_ai_audit;
ALTER TABLE public.adhoc_charges
    ADD CONSTRAINT fk_adhoc_ai_audit FOREIGN KEY (ai_audit_id, tenant_id) REFERENCES public.ai_audit_log (id, tenant_id);

-- r2 (Opus B4): who created a row is a fact about its creation — the AI
-- flag and the audit citation are write-once.
CREATE OR REPLACE FUNCTION public.enforce_ai_provenance_write_once() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
BEGIN
    IF NEW.created_by_ai IS DISTINCT FROM OLD.created_by_ai OR NEW.ai_audit_id IS DISTINCT FROM OLD.ai_audit_id THEN
        RAISE EXCEPTION USING
            MESSAGE = format('%s %s: created_by_ai and ai_audit_id record how the row was created and are write-once (CI-099, v5.4.2-19)', TG_TABLE_NAME, OLD.id),
            ERRCODE = 'restrict_violation';
    END IF;
    RETURN NEW;
END;
$$;
COMMENT ON FUNCTION public.enforce_ai_provenance_write_once() IS
    'v5.4.2-19 r2 (CI-099). BEFORE UPDATE on service_orders and adhoc_charges: created_by_ai and ai_audit_id are write-once.';
DO $$
DECLARE
    t text;
BEGIN
    FOREACH t IN ARRAY ARRAY['service_orders', 'adhoc_charges'] LOOP
        EXECUTE format('DROP TRIGGER IF EXISTS enforce_ai_provenance_write_once ON public.%I', t);
        EXECUTE format('CREATE TRIGGER enforce_ai_provenance_write_once BEFORE UPDATE ON public.%I FOR EACH ROW EXECUTE FUNCTION public.enforce_ai_provenance_write_once()', t);
        EXECUTE format('ALTER TABLE public.%I ENABLE ALWAYS TRIGGER enforce_ai_provenance_write_once', t);
    END LOOP;
END $$;

-- r2 (Opus S1, Fable S4): the ledger's created_at is the "recorded" coordinate
-- of account_balance_as_of, so it is the database's (a superuser's kept).
DROP TRIGGER IF EXISTS a_stamp_created_at ON public.account_ledger;
CREATE TRIGGER a_stamp_created_at BEFORE INSERT ON public.account_ledger
    FOR EACH ROW EXECUTE FUNCTION public.stamp_log_created_at();
ALTER TABLE public.account_ledger ENABLE ALWAYS TRIGGER a_stamp_created_at;

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
    IF NEW.customer_id       IS DISTINCT FROM OLD.customer_id       THEN v_changed := v_changed || 'customer_id'::text; END IF;
    IF NEW.meter_id          IS DISTINCT FROM OLD.meter_id          THEN v_changed := v_changed || 'meter_id'::text; END IF;
    IF NEW.location_id       IS DISTINCT FROM OLD.location_id       THEN v_changed := v_changed || 'location_id'::text; END IF;
    IF NEW.detected_at       IS DISTINCT FROM OLD.detected_at       THEN v_changed := v_changed || 'detected_at'::text; END IF;
    IF NEW.detection_method  IS DISTINCT FROM OLD.detection_method  THEN v_changed := v_changed || 'detection_method'::text; END IF;
    IF NEW.detector_name     IS DISTINCT FROM OLD.detector_name     THEN v_changed := v_changed || 'detector_name'::text; END IF;
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
    'v5.4.2-19 (CI-128). BEFORE UPDATE on anomalies: the dedup key, the subject (type, entity, customer, meter, location), the detection (detected_at, method, detector), first_detected_at and created_at are write-once; recurrence_count never decreases and last_detected_at never moves back. A recurring detection updates the canonical row; resolution fields stay editable.';
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
    -- Issued: the image and its fingerprint are frozen together (pdf_url is
    -- also frozen by enforce_invoice_immutable once set).
    IF public.is_invoice_issued(OLD.status)
       AND (NEW.pdf_sha256 IS DISTINCT FROM OLD.pdf_sha256 OR NEW.pdf_url IS DISTINCT FROM OLD.pdf_url)
       AND (OLD.pdf_sha256 IS NOT NULL OR OLD.pdf_url IS NOT NULL) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('invoice %s is issued: its image (pdf_url) and fingerprint (pdf_sha256) are write-once (CI-096, v5.4.2-19)', OLD.invoice_number),
            ERRCODE = 'restrict_violation';
    END IF;
    -- Draft or held (r2, Fable S3): a re-rendered preview changes the image
    -- and its fingerprint together, never one without the other.
    IF NOT public.is_invoice_issued(OLD.status)
       AND NEW.pdf_url IS NOT NULL AND OLD.pdf_url IS NOT NULL
       AND ((NEW.pdf_url IS DISTINCT FROM OLD.pdf_url) <> (NEW.pdf_sha256 IS DISTINCT FROM OLD.pdf_sha256)) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('invoice %s: pdf_url and pdf_sha256 change together — a new image has a new fingerprint (CI-096, v5.4.2-19)', OLD.invoice_number),
            ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$;
COMMENT ON FUNCTION public.enforce_invoice_image_hash() IS
    'v5.4.2-19 (CI-096). BEFORE UPDATE on invoices: once the invoice is issued, pdf_url and pdf_sha256 are write-once; on a draft or held invoice they change together (a re-rendered preview has a new fingerprint). The pair CHECK sets the hash with the URL.';
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
-- r2 (Opus B5, Fable B2; Opus S4): one live COMMIT per tenant and file
-- content, whatever import type it claims (one file committed as payments
-- and again as lockbox is a double posting). Previews import nothing and are
-- not counted. The key columns are frozen and a finished job's status is
-- final (enforce_import_job_record), so the slot cannot be freed by editing.
CREATE UNIQUE INDEX import_jobs_file_once
    ON public.import_jobs (tenant_id, source_file_hash)
    WHERE source_file_hash IS NOT NULL AND NOT is_dry_run AND status NOT IN ('failed', 'cancelled');
COMMENT ON INDEX public.import_jobs_file_once IS
    'v5.4.2-19 (CI-118). One live committing job per tenant and file content: a renamed copy, a fresh idempotency_key or another import_type cannot import a file again. Previews are not counted. A job that failed or was cancelled before finishing frees the file for a retry; a finished job''s status is final.';

CREATE OR REPLACE FUNCTION public.enforce_import_job_record() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_changed text[] := '{}';
BEGIN
    IF NEW.id                IS DISTINCT FROM OLD.id                THEN v_changed := v_changed || 'id'::text; END IF;
    IF NEW.tenant_id         IS DISTINCT FROM OLD.tenant_id         THEN v_changed := v_changed || 'tenant_id'::text; END IF;
    IF NEW.initiated_by      IS DISTINCT FROM OLD.initiated_by      THEN v_changed := v_changed || 'initiated_by'::text; END IF;
    IF NEW.import_type       IS DISTINCT FROM OLD.import_type       THEN v_changed := v_changed || 'import_type'::text; END IF;
    IF NEW.source_type       IS DISTINCT FROM OLD.source_type       THEN v_changed := v_changed || 'source_type'::text; END IF;
    IF NEW.source_filename   IS DISTINCT FROM OLD.source_filename   THEN v_changed := v_changed || 'source_filename'::text; END IF;
    IF NEW.source_file_hash  IS DISTINCT FROM OLD.source_file_hash  THEN v_changed := v_changed || 'source_file_hash'::text; END IF;
    IF NEW.is_dry_run        IS DISTINCT FROM OLD.is_dry_run        THEN v_changed := v_changed || 'is_dry_run'::text; END IF;
    IF NEW.idempotency_key   IS DISTINCT FROM OLD.idempotency_key   THEN v_changed := v_changed || 'idempotency_key'::text; END IF;
    IF NEW.created_at        IS DISTINCT FROM OLD.created_at        THEN v_changed := v_changed || 'created_at'::text; END IF;
    IF OLD.status IN ('complete', 'partial', 'failed', 'cancelled') THEN
        IF NEW.status IS DISTINCT FROM OLD.status THEN
            v_changed := v_changed || format('status (%s is final)', OLD.status);
        END IF;
        -- r3 (Opus S2): a finished job's stored file and its counts are its record.
        IF NEW.source_file_url        IS DISTINCT FROM OLD.source_file_url        THEN v_changed := v_changed || 'source_file_url'::text; END IF;
        IF NEW.source_file_size_bytes IS DISTINCT FROM OLD.source_file_size_bytes THEN v_changed := v_changed || 'source_file_size_bytes'::text; END IF;
        IF (NEW.total_rows, NEW.processed_rows, NEW.committed_rows, NEW.held_rows, NEW.error_rows, NEW.warning_rows, NEW.skipped_rows)
           IS DISTINCT FROM (OLD.total_rows, OLD.processed_rows, OLD.committed_rows, OLD.held_rows, OLD.error_rows, OLD.warning_rows, OLD.skipped_rows) THEN
            v_changed := v_changed || 'row counts'::text;
        END IF;
        -- r4 (Fable r3 S3): the summary and errors reported at finish, and when.
        IF NEW.import_summary    IS DISTINCT FROM OLD.import_summary    THEN v_changed := v_changed || 'import_summary'::text; END IF;
        IF NEW.validation_errors IS DISTINCT FROM OLD.validation_errors THEN v_changed := v_changed || 'validation_errors'::text; END IF;
        IF NEW.completed_at      IS DISTINCT FROM OLD.completed_at      THEN v_changed := v_changed || 'completed_at'::text; END IF;
    END IF;
    IF cardinality(v_changed) > 0 THEN
        RAISE EXCEPTION USING
            MESSAGE = format('import job %s: its file identity is write-once and a finished job''s status is final (CI-118, v5.4.2-19): attempted change to %s', OLD.id, array_to_string(v_changed, ', ')),
            HINT = 'To import the file again, start a new job (allowed once the earlier one failed or was cancelled before finishing).',
            ERRCODE = 'restrict_violation';
    END IF;
    RETURN NEW;
END;
$$;
COMMENT ON FUNCTION public.enforce_import_job_record() IS
    'v5.4.2-19 r2 (CI-118). BEFORE UPDATE on import_jobs: tenant, initiator, import and source type, file name, file hash, preview flag, idempotency key and created_at are write-once; complete, partial, failed and cancelled are final statuses, and a finished job''s stored file (URL, size), row counts, summary, validation errors and completed_at are frozen with it (r3, r4) — a snapshot at finish; staging rows stay the live record.';
DROP TRIGGER IF EXISTS a_enforce_import_job_record ON public.import_jobs;
CREATE TRIGGER a_enforce_import_job_record BEFORE UPDATE ON public.import_jobs
    FOR EACH ROW EXECUTE FUNCTION public.enforce_import_job_record();
ALTER TABLE public.import_jobs ENABLE ALWAYS TRIGGER a_enforce_import_job_record;


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
    'v5.4.2-19 (CI-019). The customer''s ledger balance: the sum of account_ledger amounts dated on or before p_on and recorded (created_at) by p_recorded_at. Order-independent. All coordinates required; a customer not visible raises.';
REVOKE ALL ON FUNCTION public.account_balance_as_of(uuid, date, timestamp with time zone) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.account_balance_as_of(uuid, date, timestamp with time zone) TO tally_app, tally_core;


-- ----------------------------------------------------------------------------
-- 8. The stored running balance is dropped (CI-019; Ryan, 2026-10-13: "drop it")
-- ----------------------------------------------------------------------------
-- account_ledger.running_balance was stamped by a trigger from the "previous"
-- row, ordered by created_at and id: rows written in one transaction tie on
-- created_at and fell back to a random id, and two concurrent writers for one
-- customer read the same prior balance — a wrong value, frozen forever on an
-- append-only table. The balance is a sum (account_balance_as_of, section 7);
-- nothing else reads the column but void_invoice()'s return value, rewritten
-- here unchanged except for that read.

CREATE OR REPLACE FUNCTION public.void_invoice(p_invoice_id uuid, p_voided_by uuid DEFAULT NULL::uuid, p_void_reason_code text DEFAULT NULL::text, p_void_reason_notes text DEFAULT NULL::text, p_rebill_expected boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
    v_invoice                    public.invoices%ROWTYPE;
    v_reads_released             INTEGER := 0;
    v_charges_auto_reverted      INTEGER := 0;
    v_charges_pending_review     INTEGER := 0;
    v_reversal_amount            DECIMAL(12,2);
    v_ledger_entry_id            UUID;
    v_original_ledger_entry_id   UUID;
    v_had_payment                BOOLEAN := false;
    v_new_running_bal            DECIMAL(12,2);
    v_description                TEXT;
    v_duplicate_no_match_warning BOOLEAN := false;
    v_invoice_status_at_void     TEXT;
    v_auto_revert_codes          TEXT[] := ARRAY[
        'wrong_read', 'wrong_rate', 'service_date_error', 'system_error'
    ];
BEGIN
    -- -------------------------------------------------------------------------
    -- Step 1: Load and validate the invoice
    -- -------------------------------------------------------------------------
    SELECT * INTO v_invoice
    FROM public.invoices
    WHERE id = p_invoice_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Invoice not found: %', p_invoice_id;
    END IF;

    -- -------------------------------------------------------------------------
    -- Step 1.1 (NEW in v5.2.1): Cross-tenant access check (Fix #5)
    -- -------------------------------------------------------------------------
    -- Defense in depth. Even if RLS is bypassed or the function owner has
    -- BYPASSRLS, this check enforces tenant isolation. Platform admins
    -- (cross-tenant by design) are exempted.
    -- -------------------------------------------------------------------------
    IF v_invoice.tenant_id != public.get_user_tenant_id()
       AND NOT public.is_platform_admin()
    THEN
        RAISE EXCEPTION
            'Cross-tenant access denied for invoice %. '
            'Caller tenant does not match invoice tenant.',
            v_invoice.invoice_number;
    END IF;

    -- -------------------------------------------------------------------------
    -- Step 1.2: Voidability and reason validation
    -- -------------------------------------------------------------------------
    IF v_invoice.status NOT IN ('pending','sent','overdue','partial','paid','held') THEN
        RAISE EXCEPTION
            'Invoice % is not voidable. Current status: %. '
            'Voidable statuses: pending, sent, overdue, partial, paid, held.',
            v_invoice.invoice_number, v_invoice.status;
    END IF;

    IF p_void_reason_code IS NULL THEN
        RAISE EXCEPTION 'void_reason_code is required.';
    END IF;

    IF p_void_reason_code = 'other'
       AND (p_void_reason_notes IS NULL OR trim(p_void_reason_notes) = '')
    THEN
        RAISE EXCEPTION
            'void_reason_notes is required when void_reason_code = ''other''.';
    END IF;

    -- Snapshot status before any changes (for invoice_events audit record)
    v_invoice_status_at_void := v_invoice.status;
    v_had_payment := v_invoice.status IN ('paid','partial');

    -- -------------------------------------------------------------------------
    -- Step 1.5: Duplicate-warning check (Fix #4: filter by invoice_type)
    -- -------------------------------------------------------------------------
    -- The v5.2 check matched ANY non-void invoice for the same location and
    -- billing period. That gave false negatives when a single location had
    -- multiple service types (water + gas + electric) for the same period —
    -- it would find the unrelated water invoice and suppress the warning for
    -- the gas duplicate.
    --
    -- v5.2.1: also require matching invoice_type. A regular gas duplicate
    -- will only match other regular invoices for the same location/period,
    -- not water/electric or correction/final invoices.
    -- -------------------------------------------------------------------------
    IF p_void_reason_code = 'duplicate' THEN
        SELECT NOT EXISTS (
            SELECT 1 FROM public.invoices
            WHERE location_id    = v_invoice.location_id
              AND billing_period = v_invoice.billing_period
              AND invoice_type   = v_invoice.invoice_type       -- Fix #4
              AND status         NOT IN ('void','draft')
              AND id             != p_invoice_id
        ) INTO v_duplicate_no_match_warning;
    END IF;

    -- -------------------------------------------------------------------------
    -- Step 2: Arm trigger carve-out (transaction-scoped)
    -- -------------------------------------------------------------------------
    SET LOCAL app.void_operation = 'true';

    -- -------------------------------------------------------------------------
    -- Step 3: Release locked meter reads
    -- -------------------------------------------------------------------------
    UPDATE public.meter_readings
    SET
        voided_from_invoice_id = locked_by_invoice_id,
        locked_by_invoice_id   = NULL,
        validation_status      = 'void_released'
    WHERE locked_by_invoice_id = p_invoice_id
      AND validation_status    = 'locked';

    GET DIAGNOSTICS v_reads_released = ROW_COUNT;

    -- -------------------------------------------------------------------------
    -- Step 3.5: Adhoc charge disposition
    -- -------------------------------------------------------------------------
    IF p_void_reason_code = ANY(v_auto_revert_codes) THEN
        UPDATE public.adhoc_charges
        SET
            status                 = 'pending',
            voided_from_invoice_id = billed_on_invoice_id,
            billed_on_invoice_id   = NULL,
            billed_on_line_item_id = NULL,
            billed_at              = NULL,
            target_billing_period  = v_invoice.billing_period,
            updated_at             = now()
        WHERE billed_on_invoice_id = p_invoice_id
          AND status               = 'billed';

        GET DIAGNOSTICS v_charges_auto_reverted = ROW_COUNT;
        v_charges_pending_review := 0;
    ELSE
        UPDATE public.adhoc_charges
        SET
            status                 = 'void_pending_rebill',
            voided_from_invoice_id = billed_on_invoice_id,
            billed_on_invoice_id   = NULL,
            billed_on_line_item_id = NULL,
            billed_at              = NULL,
            updated_at             = now()
        WHERE billed_on_invoice_id = p_invoice_id
          AND status               = 'billed';

        GET DIAGNOSTICS v_charges_pending_review = ROW_COUNT;
        v_charges_auto_reverted := 0;
    END IF;

    -- -------------------------------------------------------------------------
    -- Step 3.7 (NEW in v5.4.1-01): Best-effort lookup of the original charge
    -- ledger entry this void reverses (CI-017 reversal lineage). NULL when
    -- no such row exists — no billing-run/charge-posting code exists
    -- anywhere in this schema-only project to have posted it yet.
    -- -------------------------------------------------------------------------
    SELECT id INTO v_original_ledger_entry_id
    FROM public.account_ledger
    WHERE tenant_id       = v_invoice.tenant_id
      AND reference_type  = 'invoice'
      AND reference_id    = p_invoice_id
      AND transaction_type = 'charge'
    ORDER BY created_at
    LIMIT 1;

    -- -------------------------------------------------------------------------
    -- Step 4: Post void_reversal ledger entry
    -- -------------------------------------------------------------------------
    v_reversal_amount := -(v_invoice.amount_due);

    v_description := format(
        'Void reversal — Invoice %s (%s). Reason: %s%s',
        v_invoice.invoice_number,
        v_invoice.billing_period,
        p_void_reason_code,
        CASE WHEN p_void_reason_notes IS NOT NULL
             THEN '. Notes: ' || p_void_reason_notes
             ELSE ''
        END
    );

    INSERT INTO public.account_ledger (
        tenant_id,
        customer_id,
        location_id,
        transaction_date,
        transaction_type,
        description,
        amount,
        reference_type,
        reference_id,
        created_by,
        reverses_ledger_entry_id,
        reversal_reason
    )
    VALUES (
        v_invoice.tenant_id,
        v_invoice.customer_id,
        v_invoice.location_id,
        CURRENT_DATE,
        'void_reversal',
        v_description,
        v_reversal_amount,
        'invoice_void',
        p_invoice_id,
        p_voided_by,
        v_original_ledger_entry_id,
        p_void_reason_code || CASE WHEN p_void_reason_notes IS NOT NULL
                                    THEN ': ' || p_void_reason_notes
                                    ELSE ''
                               END
    )
    RETURNING id INTO v_ledger_entry_id;

    -- -------------------------------------------------------------------------
    -- Step 5: Stamp void metadata on invoice
    -- -------------------------------------------------------------------------
    UPDATE public.invoices
    SET
        status               = 'void',
        voided_at            = now(),
        voided_by            = p_voided_by,
        void_reason_code     = p_void_reason_code,
        void_reason_notes    = p_void_reason_notes,
        void_rebill_expected = p_rebill_expected,
        updated_at           = now()
    WHERE id = p_invoice_id;

    -- -------------------------------------------------------------------------
    -- Step 5.5: Log the voided event
    -- -------------------------------------------------------------------------
    -- tenant_id will be overwritten by the sync trigger from Fix #6, but we
    -- still pass it for explicitness and to satisfy NOT NULL.
    -- -------------------------------------------------------------------------
    INSERT INTO public.invoice_events (
        tenant_id,
        invoice_id,
        event_type,
        operator_id,
        occurred_at,
        metadata
    )
    VALUES (
        v_invoice.tenant_id,
        p_invoice_id,
        'voided',
        p_voided_by,
        now(),
        jsonb_build_object(
            'void_reason_code',       p_void_reason_code,
            'void_reason_notes',      p_void_reason_notes,
            'rebill_expected',        p_rebill_expected,
            'reads_released',         v_reads_released,
            'charges_auto_reverted',  v_charges_auto_reverted,
            'charges_pending_review', v_charges_pending_review,
            'reversal_amount',        v_reversal_amount,
            'had_payment',            v_had_payment,
            'invoice_amount_due',     v_invoice.amount_due,
            'invoice_status_at_void', v_invoice_status_at_void,
            'invoice_number',         v_invoice.invoice_number,
            'billing_period',         v_invoice.billing_period
        )
    );

    -- -------------------------------------------------------------------------
    -- Step 6: Retrieve updated running balance
    -- -------------------------------------------------------------------------
    -- v5.4.2-19: the balance is the sum of the customer's ledger rows (the
    -- stored running balance column is dropped). This function is a definer and
    -- sees every tenant, so the sum names the tenant as well as the customer.
    SELECT coalesce(sum(l.amount), 0) INTO v_new_running_bal
      FROM public.account_ledger l
     WHERE l.tenant_id = v_invoice.tenant_id
       AND l.customer_id = v_invoice.customer_id;

    -- -------------------------------------------------------------------------
    -- Step 7: Return payload
    -- -------------------------------------------------------------------------
    -- v5.4.2-01: hand the carve-out back. SET LOCAL above would otherwise
    -- stay 'true' for the rest of the caller's transaction, letting every
    -- later statement walk through the locked-read and billed-charge guards
    -- (both review rounds reproduced a cross-invoice bypass). An exception
    -- path needs no reset: the transaction (or the caller's savepoint)
    -- rolls the setting back with everything else.
    PERFORM set_config('app.void_operation', 'false', true);

    RETURN jsonb_build_object(
        'invoice_id',                  p_invoice_id,
        'invoice_number',              v_invoice.invoice_number,
        'void_reason_code',            p_void_reason_code,
        'rebill_expected',             p_rebill_expected,
        'duplicate_no_match_warning',  v_duplicate_no_match_warning,
        'reads_released',              v_reads_released,
        'charges_auto_reverted',       v_charges_auto_reverted,
        'charges_pending_review',      v_charges_pending_review,
        'reversal_amount',             v_reversal_amount,
        'ledger_entry_id',             v_ledger_entry_id,
        'reverses_ledger_entry_id',    v_original_ledger_entry_id,
        'had_payment',                 v_had_payment,
        'credit_balance',              v_new_running_bal
    );

END;
$$;

DROP TRIGGER IF EXISTS trg_compute_ledger_running_balance ON public.account_ledger;
DROP FUNCTION IF EXISTS public.compute_ledger_running_balance();
ALTER TABLE public.account_ledger DROP COLUMN running_balance;
COMMENT ON TABLE public.account_ledger IS
    'Append-only financial ledger (CI-013; structurally enforced since v5.4.2-01: BEFORE UPDATE/DELETE/TRUNCATE triggers raise; tally_app holds SELECT/INSERT only). Reversals are new rows linked through reverses_ledger_entry_id. A balance is a sum of amounts, never a stored column (v5.4.2-19, CI-019): account_balance_as_of() for a date and recorded-time coordinate; created_at is stamped by the database.';

-- ============================================================================
-- END PATCH v5.4.2-19
-- ============================================================================

COMMIT;
\endif
