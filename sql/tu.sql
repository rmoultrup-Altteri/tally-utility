-- ============================================================================
-- UTILITY BILLING PLATFORM — CURRENT SCHEMA SNAPSHOT
-- ============================================================================
-- AUTO-GENERATED — DO NOT EDIT
-- Generated:        5.13.2026
-- Source patches:   v1 -> v1.2 -> v2 -> v2.2 -> v3 -> v3.2 -> v3.3
--                   -> v4 -> v4.2 -> v4.3 -> v4.4 -> v4.5 -> v4.6 -> v4.7
--                   -> v4.8 -> v4.9 -> v5.0 -> v5.1 -> v5.2 -> v5.2.1
-- Schema version:   v5.2.1
--
-- PURPOSE
--   Read-only reference view of the current production schema state.
--   For deployment and history of record, see the individual patch files
--   in this directory. This file is regenerated after every patch — never
--   hand-edit. Hand edits will be lost on next build and will cause drift
--   between this snapshot and what production actually contains.
--
-- HOW TO REGENERATE
--   1. Drop a test database
--   2. Apply 00_supabase_shim.sql (if running on vanilla Postgres, not Supabase)
--   3. Apply each patch in order with SET check_function_bodies = off
--   4. pg_dump --schema-only --schema=public --no-owner --no-privileges
--
-- COMPATIBILITY NOTES
--   The patch files target Supabase (auth.uid(), auth.users). When applying
--   to vanilla Postgres, the 00_supabase_shim.sql stubs are required.
--   This snapshot omits the shim — it represents what the application
--   schema looks like, not the auth substrate.
--
-- BUGS PATCHED FOR THIS TEST BUILD (real fixes pending — see findings report)
--   1. v1 line 38, 43      LANGUAGE sql functions forward-reference users
--                          (workaround: SET check_function_bodies = off)
--   2. v1 line 2699        Partial index uses CURRENT_DATE (not IMMUTABLE)
--   3. v1 line 4160        import_jobs, import_staging duplicated in RLS loop
--   4. v1 line 4174        RLS for materialized_view_refresh_log before CREATE
--   5. v4, v4.2            ADD CONSTRAINT IF NOT EXISTS (invalid PG syntax)
--   6. v4.9 line 688       View references billing_runs.replaces_invoice_id
--                          (column doesn't exist; v5.0 already recreates view)
--   7. v5.2, v5.2.1        CREATE OR REPLACE VIEW with changed column shape
--                          (needs DROP VIEW + CREATE VIEW pattern)
-- ============================================================================

-- ============================================================================
-- EXTENSIONS (pg_dump omits these by default — included here so snapshot is
-- self-sufficient on a fresh database)
-- ============================================================================
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";

--
-- PostgreSQL database dump
--

\restrict aEs36qkOAMhofmB2vLfkoMmgKoI58YBi08fnaoUeHfQFg3rVEXFznvClKqh8agw

-- Dumped from database version 16.13 (Ubuntu 16.13-0ubuntu0.24.04.1)
-- Dumped by pg_dump version 16.13 (Ubuntu 16.13-0ubuntu0.24.04.1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA public IS 'standard public schema';


--
-- Name: archive_rate_item_history(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.archive_rate_item_history(p_years_to_keep integer DEFAULT 10) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_cutoff_date DATE := CURRENT_DATE - (p_years_to_keep * INTERVAL '1 year');
    v_count INTEGER;
BEGIN
    WITH moved AS (
        DELETE FROM rate_item_history
        WHERE end_date IS NOT NULL AND end_date < v_cutoff_date
        RETURNING *
    )
    INSERT INTO rate_item_history_archive SELECT * FROM moved;

    GET DIAGNOSTICS v_count = ROW_COUNT;
    RETURN v_count;
END;
$$;


--
-- Name: compute_ledger_running_balance(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.compute_ledger_running_balance() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_prior_balance DECIMAL(12,2);
BEGIN
    -- Skip if running_balance was explicitly set by the inserter
    -- (allows tools/migrations to bypass the trigger when needed)
    IF NEW.running_balance IS NOT NULL THEN
        RETURN NEW;
    END IF;

    SELECT running_balance INTO v_prior_balance
    FROM account_ledger
    WHERE tenant_id = NEW.tenant_id
      AND customer_id = NEW.customer_id
      AND id != NEW.id           -- exclude self in case of re-trigger
    ORDER BY created_at DESC, id DESC
    LIMIT 1;

    NEW.running_balance := COALESCE(v_prior_balance, 0) + NEW.amount;

    RETURN NEW;
END;
$$;


--
-- Name: FUNCTION compute_ledger_running_balance(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.compute_ledger_running_balance() IS 'Auto-computes running_balance on INSERT to account_ledger. Looks up the customer''s most recent prior entry and adds the new amount. Skipped when running_balance is explicitly provided (for migrations and back-fill scenarios). Insertion-order semantics: running_balance reflects insertion sequence, not transaction_date order. For chronological balance reconstruction, aggregate by transaction_date rather than reading running_balance directly.';


--
-- Name: enforce_billing_hold_metadata(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.enforce_billing_hold_metadata() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Setting the hold ON
    IF NEW.billing_hold = true AND (OLD.billing_hold IS NULL OR OLD.billing_hold = false) THEN
        IF NEW.billing_hold_reason IS NULL OR trim(NEW.billing_hold_reason) = '' THEN
            RAISE EXCEPTION 'billing_hold=true requires billing_hold_reason. Customer: %', NEW.id;
        END IF;
        IF NEW.billing_hold_set_at IS NULL THEN
            NEW.billing_hold_set_at := now();
        END IF;
        -- billing_hold_set_by is set by the application using auth.uid();
        -- not enforced here because a system-initiated hold (e.g., AI fraud detection)
        -- may legitimately leave it NULL.
    END IF;

    -- Clearing the hold
    IF NEW.billing_hold = false AND OLD.billing_hold = true THEN
        NEW.billing_hold_reason := NULL;
        NEW.billing_hold_set_at := NULL;
        NEW.billing_hold_set_by := NULL;
    END IF;

    RETURN NEW;
END;
$$;


--
-- Name: enforce_invoice_hold_metadata(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.enforce_invoice_hold_metadata() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Transitioning INTO held
    IF NEW.status = 'held' AND (OLD.status IS NULL OR OLD.status != 'held') THEN
        IF NEW.hold_reason IS NULL OR trim(NEW.hold_reason) = '' THEN
            RAISE EXCEPTION 'status=held requires hold_reason. Invoice: %', NEW.id;
        END IF;
        IF NEW.held_at IS NULL THEN
            NEW.held_at := now();
        END IF;
        -- held_by is set by application using auth.uid(); NULL is permitted
        -- when the hold is auto-applied by system policy (review_required_anomalies).
    END IF;

    -- Transitioning OUT of held
    IF OLD.status = 'held' AND NEW.status != 'held' THEN
        NEW.held_at := NULL;
        NEW.held_by := NULL;
        NEW.hold_reason := NULL;
    END IF;

    RETURN NEW;
END;
$$;


--
-- Name: enforce_meter_estimation_block_metadata(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.enforce_meter_estimation_block_metadata() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Setting the block ON
    IF NEW.estimation_blocked = true AND (OLD.estimation_blocked IS NULL OR OLD.estimation_blocked = false) THEN
        IF NEW.estimation_blocked_reason IS NULL OR trim(NEW.estimation_blocked_reason) = '' THEN
            RAISE EXCEPTION 'estimation_blocked=true requires estimation_blocked_reason. Meter: %', NEW.id;
        END IF;
        IF NEW.estimation_blocked_set_at IS NULL THEN
            NEW.estimation_blocked_set_at := now();
        END IF;
    END IF;

    -- Clearing the block
    IF NEW.estimation_blocked = false AND OLD.estimation_blocked = true THEN
        NEW.estimation_blocked_reason := NULL;
        NEW.estimation_blocked_set_at := NULL;
        NEW.estimation_blocked_set_by := NULL;
    END IF;

    RETURN NEW;
END;
$$;


--
-- Name: enforce_reading_validation_workflow(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.enforce_reading_validation_workflow() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_locked_field_changed BOOLEAN := false;
    v_is_void_operation    BOOLEAN := false;
BEGIN
    -- Detect whether this update is part of an authorized void operation.
    -- current_setting() returns '' (empty string) if the variable is not set;
    -- the second arg (true) suppresses the "unrecognized config param" error.
    v_is_void_operation := coalesce(
        current_setting('app.void_operation', true) = 'true',
        false
    );

    -- -------------------------------------------------------------------------
    -- BLOCK 1: Validate validation_status transitions
    -- -------------------------------------------------------------------------
    IF OLD.validation_status IS DISTINCT FROM NEW.validation_status THEN

        IF OLD.validation_status = 'locked' THEN
            -- Void carve-out: the only permitted transition out of locked
            -- is to void_released, and only when called from void_invoice().
            IF v_is_void_operation AND NEW.validation_status = 'void_released' THEN
                NULL; -- valid; fall through to RETURN NEW
            ELSE
                RAISE EXCEPTION
                    'Cannot change validation_status from locked. '
                    'Locked readings are terminal — corrections must create a NEW reading '
                    'via the dispute/correction workflow (insert replacement with '
                    'replaces_read_id pointing here). '
                    'To void the invoice that locked this read, use void_invoice(). '
                    'Reading: %', OLD.id;
            END IF;

        -- Standard transition matrix (unchanged from v1.2)
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

        -- Locking guard: transitioning TO locked requires billing metadata
        IF NEW.validation_status = 'locked' THEN
            IF NEW.billing_period_locked = false THEN
                RAISE EXCEPTION
                    'validation_status=locked requires billing_period_locked=true. Reading: %', OLD.id;
            END IF;
            IF NEW.locked_at IS NULL THEN
                NEW.locked_at := now();
            END IF;
            IF NEW.locked_by_billing_run_id IS NULL THEN
                RAISE EXCEPTION
                    'validation_status=locked requires locked_by_billing_run_id. Reading: %', OLD.id;
            END IF;
        END IF;

    END IF; -- end validation_status transition block

    -- -------------------------------------------------------------------------
    -- BLOCK 2: Billing-field whitelist for locked readings
    -- -------------------------------------------------------------------------
    -- Skipped entirely when void_invoice() is performing the locked -> void_released
    -- transition, because that operation legitimately needs to:
    --   • clear locked_by_invoice_id    (protected field)
    --   • set voided_from_invoice_id    (new; not in original whitelist)
    --   • change validation_status      (covered by Block 1 carve-out above)
    --
    -- billing_period_locked stays TRUE after void_released — it correctly
    -- signals that this read was consumed by a billing run, even if that
    -- invoice was subsequently voided.
    -- -------------------------------------------------------------------------
    IF OLD.billing_period_locked = true
       AND OLD.validation_status = 'locked'
       AND NOT (v_is_void_operation AND NEW.validation_status = 'void_released')
    THEN
        IF OLD.reading_value               IS DISTINCT FROM NEW.reading_value               THEN v_locked_field_changed := true; END IF;
        IF OLD.previous_value              IS DISTINCT FROM NEW.previous_value              THEN v_locked_field_changed := true; END IF;
        IF OLD.consumption                 IS DISTINCT FROM NEW.consumption                 THEN v_locked_field_changed := true; END IF;
        IF OLD.consumption_unit            IS DISTINCT FROM NEW.consumption_unit            THEN v_locked_field_changed := true; END IF;
        IF OLD.reading_date                IS DISTINCT FROM NEW.reading_date                THEN v_locked_field_changed := true; END IF;
        IF OLD.previous_reading_date       IS DISTINCT FROM NEW.previous_reading_date       THEN v_locked_field_changed := true; END IF;
        IF OLD.register_type               IS DISTINCT FROM NEW.register_type               THEN v_locked_field_changed := true; END IF;
        IF OLD.read_method                 IS DISTINCT FROM NEW.read_method                 THEN v_locked_field_changed := true; END IF;
        IF OLD.is_estimated                IS DISTINCT FROM NEW.is_estimated                THEN v_locked_field_changed := true; END IF;
        IF OLD.gas_meter_factor            IS DISTINCT FROM NEW.gas_meter_factor            THEN v_locked_field_changed := true; END IF;
        IF OLD.gas_pressure_corrected_volume IS DISTINCT FROM NEW.gas_pressure_corrected_volume THEN v_locked_field_changed := true; END IF;
        IF OLD.gas_btu_factor              IS DISTINCT FROM NEW.gas_btu_factor              THEN v_locked_field_changed := true; END IF;
        IF OLD.gas_therms                  IS DISTINCT FROM NEW.gas_therms                  THEN v_locked_field_changed := true; END IF;
        IF OLD.billing_cycle_id            IS DISTINCT FROM NEW.billing_cycle_id            THEN v_locked_field_changed := true; END IF;
        IF OLD.is_service_transition       IS DISTINCT FROM NEW.is_service_transition       THEN v_locked_field_changed := true; END IF;
        IF OLD.transition_outgoing_customer_id IS DISTINCT FROM NEW.transition_outgoing_customer_id THEN v_locked_field_changed := true; END IF;
        IF OLD.transition_incoming_customer_id IS DISTINCT FROM NEW.transition_incoming_customer_id THEN v_locked_field_changed := true; END IF;
        IF OLD.reading_purpose             IS DISTINCT FROM NEW.reading_purpose             THEN v_locked_field_changed := true; END IF;
        IF OLD.locked_by_billing_run_id    IS DISTINCT FROM NEW.locked_by_billing_run_id    THEN v_locked_field_changed := true; END IF;
        IF OLD.locked_by_invoice_id        IS DISTINCT FROM NEW.locked_by_invoice_id        THEN v_locked_field_changed := true; END IF;
        -- billing_period_locked: non-editable once true
        IF OLD.billing_period_locked = true AND NEW.billing_period_locked = false           THEN v_locked_field_changed := true; END IF;

        IF v_locked_field_changed THEN
            RAISE EXCEPTION
                'Cannot modify billing-affecting fields on a locked reading (%). '
                'To correct, insert a NEW reading with replaces_read_id pointing here. '
                'To void the billing invoice, use void_invoice(). '
                'Editable fields on locked reads: notes, tamper_investigated, '
                'tamper_investigation_notes, dispute_* fields, status, '
                'requires_followup, followup_priority, followup_notes, '
                'assigned_to_user_id, voided_from_invoice_id (set by void_invoice only).',
                OLD.id;
        END IF;
    END IF;

    RETURN NEW;
END;
$$;


--
-- Name: enforce_write_tool_requires_suggestion(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.enforce_write_tool_requires_suggestion() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NEW.tool_category = 'write' AND NEW.status = 'success' THEN
        IF NEW.suggestion_id IS NULL THEN
            RAISE EXCEPTION 'Write-category tool calls require a suggestion_id (Tier 2 guardrail). Tool: %', NEW.tool_name;
        END IF;

        IF NOT EXISTS (
            SELECT 1 FROM ai_suggestions s
            WHERE s.id = NEW.suggestion_id
              AND s.status IN ('approved','partially_approved','executed')
        ) THEN
            RAISE EXCEPTION 'Write-category tool calls require an approved suggestion. Suggestion % is not approved.', NEW.suggestion_id;
        END IF;
    END IF;
    RETURN NEW;
END;
$$;


--
-- Name: get_correction_rate_date(uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_correction_rate_date(p_billing_run_id uuid, p_voided_invoice_id uuid) RETURNS date
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    AS $$
DECLARE
    v_rate_date_mode        TEXT;
    v_rate_date_override    DATE;
    v_run_rate_mode         TEXT;
    v_voided_period_end     DATE;
BEGIN
    -- Load target-level fields in one query
    SELECT
        crt.rate_date_mode,
        crt.rate_date_override,
        br.correction_rate_mode,
        i.period_end
    INTO
        v_rate_date_mode,
        v_rate_date_override,
        v_run_rate_mode,
        v_voided_period_end
    FROM correction_run_targets crt
    JOIN billing_runs br ON br.id = crt.billing_run_id
    JOIN invoices     i  ON i.id  = crt.voided_invoice_id
    WHERE crt.billing_run_id    = p_billing_run_id
      AND crt.voided_invoice_id = p_voided_invoice_id;

    IF NOT FOUND THEN
        -- Target not found — caller should log and fall back to CURRENT_DATE
        RETURN NULL;
    END IF;

    -- Resolution order
    CASE v_rate_date_mode

        WHEN 'custom' THEN
            -- Operator-supplied explicit date (validated by CHECK constraint)
            RETURN v_rate_date_override;

        WHEN 'historical' THEN
            -- Force historical regardless of run-level mode
            RETURN v_voided_period_end;

        WHEN 'current' THEN
            -- Force current regardless of run-level mode
            RETURN CURRENT_DATE;

        WHEN 'run_default' THEN
            -- Delegate to the run-level setting
            IF v_run_rate_mode = 'current' THEN
                RETURN CURRENT_DATE;
            ELSE
                -- 'historical' is the default; covers NULL defensively
                RETURN v_voided_period_end;
            END IF;

        ELSE
            -- Unrecognised mode — safe fallback, billing engine should log
            RETURN v_voided_period_end;

    END CASE;
END;
$$;


--
-- Name: FUNCTION get_correction_rate_date(p_billing_run_id uuid, p_voided_invoice_id uuid); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.get_correction_rate_date(p_billing_run_id uuid, p_voided_invoice_id uuid) IS 'Returns the rate effective date ceiling for Phase 5 of a correction billing run. Resolution: custom date > per-target historical/current > run-level default. Pass the returned date to all rate_item, rate_schedule_item, wna_monthly_adjustments, and franchise_fee_rules queries as: WHERE effective_date <= get_correction_rate_date(...). Returns NULL if target not found; billing engine should treat NULL as CURRENT_DATE and log.';


--
-- Name: get_effective_rate(uuid, uuid, date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_effective_rate(p_rate_schedule_id uuid, p_rate_item_id uuid, p_billing_month date DEFAULT CURRENT_DATE) RETURNS TABLE(effective_rate numeric, rate_unit text, is_active_this_month boolean, is_taxable boolean)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    AS $$
DECLARE
    v_billing_month_num INTEGER := EXTRACT(MONTH FROM p_billing_month)::INTEGER;
    v_item_active_months INTEGER[];
    v_override_active_months INTEGER[];
    v_effective_months INTEGER[];
BEGIN
    SELECT
        COALESCE(rsi.rate_override, ri.current_rate) AS effective_rate,
        COALESCE(rsi.rate_unit_override, ri.rate_unit) AS rate_unit,
        COALESCE(rsi.is_taxable_override, ri.is_taxable_default) AS is_taxable,
        ri.active_months,
        rsi.active_months_override
    INTO
        effective_rate, rate_unit, is_taxable, v_item_active_months, v_override_active_months
    FROM rate_schedule_items rsi
    JOIN rate_items ri ON ri.id = rsi.rate_item_id
    WHERE rsi.rate_schedule_id = p_rate_schedule_id
      AND rsi.rate_item_id = p_rate_item_id
      AND rsi.status = 'active'
      AND ri.status = 'active'
    LIMIT 1;

    -- Use override months if set, otherwise item's default months
    v_effective_months := COALESCE(v_override_active_months, v_item_active_months);
    is_active_this_month := v_billing_month_num = ANY(v_effective_months);

    RETURN NEXT;
END;
$$;


--
-- Name: get_partial_period_policy(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_partial_period_policy(p_rate_schedule_id uuid) RETURNS text
    LANGUAGE sql STABLE
    AS $$
    SELECT COALESCE(rs.partial_period_policy, t.default_partial_period_policy)
    FROM rate_schedules rs
    JOIN tenants t ON t.id = rs.tenant_id
    WHERE rs.id = p_rate_schedule_id;
$$;


--
-- Name: FUNCTION get_partial_period_policy(p_rate_schedule_id uuid); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.get_partial_period_policy(p_rate_schedule_id uuid) IS 'Returns the effective partial-period policy for a rate schedule, using the per-plan override if set, else the tenant default.';


--
-- Name: get_user_tenant_id(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_user_tenant_id() RETURNS uuid
    LANGUAGE sql STABLE SECURITY DEFINER
    AS $$
    SELECT tenant_id FROM users WHERE id = auth.uid()
$$;


--
-- Name: initialize_tenant(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.initialize_tenant(p_tenant_id uuid) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
    INSERT INTO tenant_sequences (tenant_id, sequence_type, prefix, pad_length) VALUES
        (p_tenant_id, 'customer',       'CUST-',  6),
        (p_tenant_id, 'location',       'LOC-',   6),
        (p_tenant_id, 'community',      'COM-',   4),
        (p_tenant_id, 'meter',          'MTR-',   6),
        (p_tenant_id, 'rate_schedule',  'RATE-',  4),
        (p_tenant_id, 'invoice',        'INV-',   6),
        (p_tenant_id, 'payment',        'PAY-',   6),
        (p_tenant_id, 'service_order',  'WO-',    6),
        (p_tenant_id, 'billing_run',    'BR-',    4),
        (p_tenant_id, 'import',         'IMP-',   4),
        (p_tenant_id, 'adhoc_charge',   'CHG-',   6);
END;
$$;


--
-- Name: is_platform_admin(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.is_platform_admin() RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    AS $$
    SELECT EXISTS(SELECT 1 FROM users WHERE id = auth.uid() AND role = 'platform_admin')
$$;


--
-- Name: next_sequence_value(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.next_sequence_value(p_tenant_id uuid, p_sequence_type text) RETURNS text
    LANGUAGE plpgsql
    AS $$
DECLARE v_prefix TEXT; v_next BIGINT; v_pad INTEGER;
BEGIN
    UPDATE tenant_sequences
    SET current_value = current_value + 1
    WHERE tenant_id = p_tenant_id AND sequence_type = p_sequence_type
    RETURNING prefix, current_value, pad_length INTO v_prefix, v_next, v_pad;
    RETURN v_prefix || lpad(v_next::TEXT, v_pad, '0');
END;
$$;


--
-- Name: populate_reading_calculations(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.populate_reading_calculations() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_prev_date DATE;
    v_prev_value DECIMAL(14,2);
    v_multiplier DECIMAL(10,4);
BEGIN
    -- Only auto-calculate if not already set by the caller
    IF NEW.previous_value IS NULL OR NEW.previous_reading_date IS NULL THEN
        -- Find the most recent active reading for this meter + register before the new reading date
        SELECT reading_date, reading_value
        INTO v_prev_date, v_prev_value
        FROM meter_readings
        WHERE meter_id = NEW.meter_id
          AND register_type = NEW.register_type
          AND reading_date < NEW.reading_date
          AND status = 'active'
        ORDER BY reading_date DESC
        LIMIT 1;

        IF v_prev_date IS NOT NULL THEN
            NEW.previous_reading_date := COALESCE(NEW.previous_reading_date, v_prev_date);
            NEW.previous_value := COALESCE(NEW.previous_value, v_prev_value);
        END IF;
    END IF;

    -- Calculate days_in_period
    IF NEW.previous_reading_date IS NOT NULL AND NEW.days_in_period IS NULL THEN
        NEW.days_in_period := NEW.reading_date - NEW.previous_reading_date;
    END IF;

    -- Calculate consumption if we have both readings and it's not already set
    IF NEW.consumption IS NULL AND NEW.previous_value IS NOT NULL THEN
        SELECT multiplier INTO v_multiplier FROM meters WHERE id = NEW.meter_id;
        NEW.consumption := (NEW.reading_value - NEW.previous_value) * COALESCE(v_multiplier, 1.0);
    END IF;

    RETURN NEW;
END;
$$;


--
-- Name: refresh_statistics_views(boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.refresh_statistics_views(p_force boolean DEFAULT false) RETURNS TABLE(view_name text, refreshed boolean, duration_ms integer, error_msg text)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_start TIMESTAMPTZ;
    v_views TEXT[][] := ARRAY[
        ['usage_statistics',          '86400'],   -- 24h
        ['payment_health_statistics', '3600'],    -- 1h
        ['credit_aging_statistics',   '86400'],   -- 24h
        ['compliance_statistics',     '86400']    -- 24h
    ];
    v_view TEXT;
    v_cadence_seconds INTEGER;
    v_last_refresh TIMESTAMPTZ;
    v_should_refresh BOOLEAN;
    v_error TEXT;
    v_duration INTEGER;
BEGIN
    FOR i IN 1 .. array_length(v_views, 1) LOOP
        v_view := v_views[i][1];
        v_cadence_seconds := v_views[i][2]::INTEGER;

        -- Check when we last refreshed this view
        SELECT last_refresh_at INTO v_last_refresh
        FROM materialized_view_refresh_log
        WHERE materialized_view_refresh_log.view_name = v_view;

        v_should_refresh := p_force
            OR v_last_refresh IS NULL
            OR v_last_refresh < now() - (v_cadence_seconds || ' seconds')::INTERVAL;

        IF v_should_refresh THEN
            v_start := clock_timestamp();
            v_error := NULL;
            BEGIN
                EXECUTE format('REFRESH MATERIALIZED VIEW CONCURRENTLY %I', v_view);
                v_duration := EXTRACT(EPOCH FROM (clock_timestamp() - v_start)) * 1000;

                INSERT INTO materialized_view_refresh_log AS log (view_name, last_refresh_at, last_duration_ms, last_error)
                VALUES (v_view, now(), v_duration, NULL)
                ON CONFLICT (view_name) DO UPDATE
                    SET last_refresh_at = EXCLUDED.last_refresh_at,
                        last_duration_ms = EXCLUDED.last_duration_ms,
                        last_error = NULL;
            EXCEPTION WHEN OTHERS THEN
                v_error := SQLERRM;
                v_duration := EXTRACT(EPOCH FROM (clock_timestamp() - v_start)) * 1000;
                INSERT INTO materialized_view_refresh_log AS log (view_name, last_refresh_at, last_duration_ms, last_error)
                VALUES (v_view, now(), v_duration, v_error)
                ON CONFLICT (view_name) DO UPDATE
                    SET last_refresh_at = EXCLUDED.last_refresh_at,
                        last_duration_ms = EXCLUDED.last_duration_ms,
                        last_error = EXCLUDED.last_error;
            END;

            view_name := v_view;
            refreshed := (v_error IS NULL);
            duration_ms := v_duration;
            error_msg := v_error;
            RETURN NEXT;
        ELSE
            view_name := v_view;
            refreshed := false;
            duration_ms := NULL;
            error_msg := NULL;
            RETURN NEXT;
        END IF;
    END LOOP;
END;
$$;


--
-- Name: FUNCTION refresh_statistics_views(p_force boolean); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.refresh_statistics_views(p_force boolean) IS 'Refreshes statistics materialized views due based on per-view cadence. Pass p_force=true to refresh all regardless. Logs results to materialized_view_refresh_log. Uses CONCURRENTLY so reads against the views are not blocked during refresh.';


--
-- Name: reject_future_invoice_event(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.reject_future_invoice_event() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NEW.occurred_at > now() + INTERVAL '5 minutes' THEN
        RAISE EXCEPTION
            'invoice_events.occurred_at cannot be more than 5 minutes in the future. '
            'Got: %, current time: %',
            NEW.occurred_at, now();
    END IF;
    RETURN NEW;
END;
$$;


--
-- Name: FUNCTION reject_future_invoice_event(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.reject_future_invoice_event() IS 'Rejects invoice_events rows with occurred_at more than 5 minutes in the future. Replaces the v5.2 CHECK constraint which used now() and was rejected by PostgreSQL 12+ for not being IMMUTABLE. The 5-minute window tolerates application-to-database clock skew.';


--
-- Name: should_charge_tax(uuid, boolean, text, date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.should_charge_tax(p_customer_id uuid, p_item_is_taxable boolean, p_service_type text DEFAULT NULL::text, p_as_of_date date DEFAULT CURRENT_DATE) RETURNS boolean
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    AS $$
DECLARE
    v_has_exemption BOOLEAN;
BEGIN
    -- Rule 1: item-level non-taxable wins
    IF p_item_is_taxable IS NULL OR p_item_is_taxable = false THEN
        RETURN false;
    END IF;

    -- Rule 2: customer-level exemption check
    -- An exemption applies if it's active, in effect, and covers the service_type.
    -- service_type match: exemption applies to all services (NULL/empty array)
    -- OR the specific service_type is listed.
    SELECT EXISTS (
        SELECT 1
        FROM customer_tax_exemptions cte
        WHERE cte.customer_id = p_customer_id
          AND cte.status = 'active'
          AND cte.effective_start <= p_as_of_date
          AND (cte.effective_end IS NULL OR cte.effective_end >= p_as_of_date)
          AND (
              cte.service_types IS NULL
              OR array_length(cte.service_types, 1) IS NULL  -- empty array
              OR p_service_type IS NULL                      -- caller didn't specify; blanket only
              OR p_service_type = ANY(cte.service_types)
          )
    ) INTO v_has_exemption;

    IF v_has_exemption THEN
        RETURN false;
    END IF;

    -- Rule 3: no exemption found, item is taxable, customer is taxable -> charge tax
    RETURN true;
END;
$$;


--
-- Name: FUNCTION should_charge_tax(p_customer_id uuid, p_item_is_taxable boolean, p_service_type text, p_as_of_date date); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.should_charge_tax(p_customer_id uuid, p_item_is_taxable boolean, p_service_type text, p_as_of_date date) IS 'Decides whether to tax a line item for a customer. Three rules: (1) item non-taxable -> no tax; (2) customer has active exemption covering the service_type as of as_of_date -> no tax; (3) otherwise -> tax. Pass historical as_of_date for correction invoices so exemption status reflects the original billing period.';


--
-- Name: sync_invoice_event_tenant_id(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.sync_invoice_event_tenant_id() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_invoice_tenant_id UUID;
BEGIN
    SELECT tenant_id INTO v_invoice_tenant_id
    FROM invoices
    WHERE id = NEW.invoice_id;

    IF v_invoice_tenant_id IS NULL THEN
        RAISE EXCEPTION
            'Cannot create invoice_event: invoice_id % does not exist',
            NEW.invoice_id;
    END IF;

    -- Authoritatively set tenant_id from the invoice
    NEW.tenant_id := v_invoice_tenant_id;

    RETURN NEW;
END;
$$;


--
-- Name: FUNCTION sync_invoice_event_tenant_id(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.sync_invoice_event_tenant_id() IS 'Synchronises invoice_events.tenant_id with the invoice''s actual tenant_id on every INSERT. The caller can pass any value (including NULL); the trigger overwrites it from the invoices table. Prevents tenant_id drift between invoice_events and invoices that could occur through buggy API paths.';


--
-- Name: sync_meter_deployments(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.sync_meter_deployments() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_policy TEXT;
    v_next_dep_number INTEGER;
    v_old_meter_status TEXT;
BEGIN
    -- Look up the tenant's redeployment policy
    SELECT meter_redeployment_policy INTO v_policy
    FROM tenants WHERE id = NEW.tenant_id;

    -- ============================================================
    -- INSERT: new meter row -> create first deployment
    -- ============================================================
    IF TG_OP = 'INSERT' THEN
        -- Pattern enforcement: tenant set to reuse_record can't create chained rows
        IF v_policy = 'reuse_record' AND NEW.replaces_meter_id IS NOT NULL THEN
            RAISE EXCEPTION 'Tenant policy is reuse_record (Pattern A): redeployments must reactivate the existing meter row, not create a new one with replaces_meter_id. Update the existing meter % to active at the new location instead.', NEW.replaces_meter_id;
        END IF;

        -- Only create deployment row if meter starts active and has a location
        IF NEW.status = 'active' AND NEW.location_id IS NOT NULL THEN
            INSERT INTO meter_deployments (
                tenant_id, meter_id, deployment_number,
                location_id, rate_schedule_id,
                install_date
            ) VALUES (
                NEW.tenant_id, NEW.id, 1,
                NEW.location_id, NEW.rate_schedule_id,
                NEW.start_date
            );
        END IF;
        RETURN NEW;
    END IF;

    -- ============================================================
    -- UPDATE handling
    -- ============================================================
    IF TG_OP = 'UPDATE' THEN
        v_old_meter_status := OLD.status;

        -- Pattern enforcement: tenant set to new_record can't reactivate a removed meter
        IF v_policy = 'new_record'
           AND OLD.status = 'removed'
           AND NEW.status = 'active' THEN
            RAISE EXCEPTION 'Tenant policy is new_record (Pattern B): removed meter % cannot be reactivated. Create a new meter row with replaces_meter_id pointing here.', OLD.id;
        END IF;

        -- Status moved from active to a non-deployed state -> close deployment row
        IF OLD.status = 'active'
           AND NEW.status IN ('inactive','testing','failed','removed') THEN
            UPDATE meter_deployments
            SET removal_date = COALESCE(NEW.removal_date, CURRENT_DATE),
                removal_read_value = NEW.last_read_value,
                removal_reason = COALESCE(removal_reason,
                    CASE NEW.status
                        WHEN 'testing' THEN 'testing_required'
                        WHEN 'failed' THEN 'hardware_failure'
                        ELSE NULL
                    END),
                warehouse_location_after_removal = NEW.warehouse_location,
                updated_at = now()
            WHERE meter_id = NEW.id
              AND removal_date IS NULL;
        END IF;

        -- Pattern A reactivation: status moves back to active and location changed -> new deployment row
        IF OLD.status IN ('inactive','testing','failed')
           AND NEW.status = 'active' THEN
            -- Find next deployment number for this meter
            SELECT COALESCE(MAX(deployment_number), 0) + 1 INTO v_next_dep_number
            FROM meter_deployments WHERE meter_id = NEW.id;

            INSERT INTO meter_deployments (
                tenant_id, meter_id, deployment_number,
                location_id, rate_schedule_id,
                install_date
            ) VALUES (
                NEW.tenant_id, NEW.id, v_next_dep_number,
                NEW.location_id, NEW.rate_schedule_id,
                COALESCE(NEW.start_date, CURRENT_DATE)
            );
        END IF;

        RETURN NEW;
    END IF;

    RETURN NEW;
END;
$$;


--
-- Name: FUNCTION sync_meter_deployments(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.sync_meter_deployments() IS 'Keeps meter_deployments in sync with the meters table for both Pattern A (reuse_record) and Pattern B (new_record) workflows. Also enforces the tenant''s meter_redeployment_policy: reuse_record blocks chained new rows; new_record blocks reactivation of removed meters; either allows both.';


--
-- Name: update_updated_at(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END;
$$;


--
-- Name: validate_custom_fields(uuid, text, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.validate_custom_fields(p_tenant_id uuid, p_entity_type text, p_metadata jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    AS $_$
DECLARE
    v_field RECORD;
    v_errors JSONB := '[]';
    v_value TEXT;
    v_value_jsonb JSONB;
    v_pattern TEXT;
    v_min NUMERIC;
    v_max NUMERIC;
    v_min_length INT;
    v_max_length INT;
    v_min_date DATE;
    v_max_date DATE;
    v_elem JSONB;
BEGIN
    FOR v_field IN
        SELECT field_key, field_label, field_type, is_required, validation_rules, options
        FROM custom_field_definitions
        WHERE tenant_id = p_tenant_id AND entity_type = p_entity_type AND status = 'active'
    LOOP
        v_value := p_metadata ->> v_field.field_key;
        v_value_jsonb := p_metadata -> v_field.field_key;

        -- Required check
        IF v_field.is_required AND (v_value IS NULL OR v_value = '') THEN
            v_errors := v_errors || jsonb_build_object('field', v_field.field_key, 'label', v_field.field_label, 'error', 'Required field is missing');
            CONTINUE;  -- skip further checks if missing
        END IF;

        -- Skip the rest if value is empty (already passed required check)
        IF v_value IS NULL OR v_value = '' THEN
            CONTINUE;
        END IF;

        -- Type-specific format validators
        IF v_field.field_type = 'number' AND v_value !~ '^-?\d+$' THEN
            v_errors := v_errors || jsonb_build_object('field', v_field.field_key, 'label', v_field.field_label, 'error', 'Must be a whole number');
        END IF;

        IF v_field.field_type = 'decimal' AND v_value !~ '^-?\d+(\.\d+)?$' THEN
            v_errors := v_errors || jsonb_build_object('field', v_field.field_key, 'label', v_field.field_label, 'error', 'Must be a decimal number');
        END IF;

        IF v_field.field_type = 'date' THEN
            BEGIN
                PERFORM v_value::DATE;
            EXCEPTION WHEN OTHERS THEN
                v_errors := v_errors || jsonb_build_object('field', v_field.field_key, 'label', v_field.field_label, 'error', 'Must be a valid date (YYYY-MM-DD)');
            END;
        END IF;

        IF v_field.field_type = 'boolean' AND v_value NOT IN ('true','false','t','f','1','0','yes','no') THEN
            v_errors := v_errors || jsonb_build_object('field', v_field.field_key, 'label', v_field.field_label, 'error', 'Must be true or false');
        END IF;

        IF v_field.field_type = 'email' AND v_value !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' THEN
            v_errors := v_errors || jsonb_build_object('field', v_field.field_key, 'label', v_field.field_label, 'error', 'Must be a valid email');
        END IF;

        IF v_field.field_type = 'phone' AND v_value !~ '^[\d\s\-\+\(\)\.]{7,20}$' THEN
            v_errors := v_errors || jsonb_build_object('field', v_field.field_key, 'label', v_field.field_label, 'error', 'Must be a valid phone number');
        END IF;

        IF v_field.field_type = 'url' AND v_value !~* '^https?://[^\s]+$' THEN
            v_errors := v_errors || jsonb_build_object('field', v_field.field_key, 'label', v_field.field_label, 'error', 'Must be a valid URL (http:// or https://)');
        END IF;

        -- Single-select: value must match one of the options
        IF v_field.field_type = 'select' THEN
            IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_field.options) opt WHERE opt ->> 'value' = v_value) THEN
                v_errors := v_errors || jsonb_build_object('field', v_field.field_key, 'label', v_field.field_label, 'error', 'Invalid option selected');
            END IF;
        END IF;

        -- Multi-select: value should be a JSONB array; each element must match options
        IF v_field.field_type = 'multi_select' THEN
            IF v_value_jsonb IS NULL OR jsonb_typeof(v_value_jsonb) != 'array' THEN
                v_errors := v_errors || jsonb_build_object('field', v_field.field_key, 'label', v_field.field_label, 'error', 'Must be an array of selected values');
            ELSE
                FOR v_elem IN SELECT * FROM jsonb_array_elements(v_value_jsonb)
                LOOP
                    IF NOT EXISTS (
                        SELECT 1 FROM jsonb_array_elements(v_field.options) opt
                        WHERE opt ->> 'value' = v_elem #>> '{}'
                    ) THEN
                        v_errors := v_errors || jsonb_build_object('field', v_field.field_key, 'label', v_field.field_label, 'error', 'One or more selected values are not valid options');
                        EXIT;  -- one error per field is enough
                    END IF;
                END LOOP;
            END IF;
        END IF;

        -- Custom validation_rules (pattern, min/max, minLength/maxLength)
        IF v_field.validation_rules IS NOT NULL AND v_field.validation_rules != '{}'::jsonb THEN
            -- Pattern (regex)
            v_pattern := v_field.validation_rules ->> 'pattern';
            IF v_pattern IS NOT NULL AND v_value !~ v_pattern THEN
                v_errors := v_errors || jsonb_build_object('field', v_field.field_key, 'label', v_field.field_label, 'error', 'Value does not match required pattern');
            END IF;

            -- Numeric min/max for number/decimal
            IF v_field.field_type IN ('number','decimal') THEN
                BEGIN
                    v_min := (v_field.validation_rules ->> 'min')::NUMERIC;
                    IF v_min IS NOT NULL AND v_value::NUMERIC < v_min THEN
                        v_errors := v_errors || jsonb_build_object('field', v_field.field_key, 'label', v_field.field_label, 'error', format('Must be at least %s', v_min));
                    END IF;
                EXCEPTION WHEN OTHERS THEN NULL; END;

                BEGIN
                    v_max := (v_field.validation_rules ->> 'max')::NUMERIC;
                    IF v_max IS NOT NULL AND v_value::NUMERIC > v_max THEN
                        v_errors := v_errors || jsonb_build_object('field', v_field.field_key, 'label', v_field.field_label, 'error', format('Must be at most %s', v_max));
                    END IF;
                EXCEPTION WHEN OTHERS THEN NULL; END;
            END IF;

            -- Date min/max
            IF v_field.field_type = 'date' THEN
                BEGIN
                    v_min_date := (v_field.validation_rules ->> 'min')::DATE;
                    IF v_min_date IS NOT NULL AND v_value::DATE < v_min_date THEN
                        v_errors := v_errors || jsonb_build_object('field', v_field.field_key, 'label', v_field.field_label, 'error', format('Date must be on or after %s', v_min_date));
                    END IF;
                EXCEPTION WHEN OTHERS THEN NULL; END;

                BEGIN
                    v_max_date := (v_field.validation_rules ->> 'max')::DATE;
                    IF v_max_date IS NOT NULL AND v_value::DATE > v_max_date THEN
                        v_errors := v_errors || jsonb_build_object('field', v_field.field_key, 'label', v_field.field_label, 'error', format('Date must be on or before %s', v_max_date));
                    END IF;
                EXCEPTION WHEN OTHERS THEN NULL; END;
            END IF;

            -- String length bounds (text, textarea, email, phone, url)
            IF v_field.field_type IN ('text','textarea','email','phone','url') THEN
                BEGIN
                    v_min_length := (v_field.validation_rules ->> 'minLength')::INT;
                    IF v_min_length IS NOT NULL AND length(v_value) < v_min_length THEN
                        v_errors := v_errors || jsonb_build_object('field', v_field.field_key, 'label', v_field.field_label, 'error', format('Must be at least %s characters', v_min_length));
                    END IF;
                EXCEPTION WHEN OTHERS THEN NULL; END;

                BEGIN
                    v_max_length := (v_field.validation_rules ->> 'maxLength')::INT;
                    IF v_max_length IS NOT NULL AND length(v_value) > v_max_length THEN
                        v_errors := v_errors || jsonb_build_object('field', v_field.field_key, 'label', v_field.field_label, 'error', format('Must be at most %s characters', v_max_length));
                    END IF;
                EXCEPTION WHEN OTHERS THEN NULL; END;
            END IF;
        END IF;
    END LOOP;
    RETURN v_errors;
END;
$_$;


--
-- Name: FUNCTION validate_custom_fields(p_tenant_id uuid, p_entity_type text, p_metadata jsonb); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.validate_custom_fields(p_tenant_id uuid, p_entity_type text, p_metadata jsonb) IS 'Validates an entity''s metadata JSONB against the tenant''s active custom field definitions for that entity type. Returns a JSONB array of error objects (empty = valid). Validates required, type format, select options, and validation_rules (pattern, min/max, length).';


--
-- Name: void_invoice(uuid, uuid, text, text, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.void_invoice(p_invoice_id uuid, p_voided_by uuid DEFAULT NULL::uuid, p_void_reason_code text DEFAULT NULL::text, p_void_reason_notes text DEFAULT NULL::text, p_rebill_expected boolean DEFAULT true) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
    v_invoice                    invoices%ROWTYPE;
    v_reads_released             INTEGER := 0;
    v_charges_auto_reverted      INTEGER := 0;
    v_charges_pending_review     INTEGER := 0;
    v_reversal_amount            DECIMAL(12,2);
    v_ledger_entry_id            UUID;
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
    FROM invoices
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
    IF v_invoice.tenant_id != get_user_tenant_id()
       AND NOT is_platform_admin()
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
            SELECT 1 FROM invoices
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
    UPDATE meter_readings
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
        UPDATE adhoc_charges
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
        UPDATE adhoc_charges
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

    INSERT INTO account_ledger (
        tenant_id,
        customer_id,
        location_id,
        transaction_date,
        transaction_type,
        description,
        amount,
        reference_type,
        reference_id,
        created_by
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
        p_voided_by
    )
    RETURNING id INTO v_ledger_entry_id;

    -- -------------------------------------------------------------------------
    -- Step 5: Stamp void metadata on invoice
    -- -------------------------------------------------------------------------
    UPDATE invoices
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
    INSERT INTO invoice_events (
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
    SELECT running_balance INTO v_new_running_bal
    FROM account_ledger
    WHERE id = v_ledger_entry_id;

    -- -------------------------------------------------------------------------
    -- Step 7: Return payload
    -- -------------------------------------------------------------------------
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
        'had_payment',                 v_had_payment,
        'credit_balance',              v_new_running_bal
    );

END;
$$;


--
-- Name: FUNCTION void_invoice(p_invoice_id uuid, p_voided_by uuid, p_void_reason_code text, p_void_reason_notes text, p_rebill_expected boolean); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.void_invoice(p_invoice_id uuid, p_voided_by uuid, p_void_reason_code text, p_void_reason_notes text, p_rebill_expected boolean) IS 'Atomically voids a posted invoice. v5.2.1 corrections: (a) Single canonical signature — old 4-param version dropped; (b) Explicit cross-tenant check defends against RLS bypass; (c) Duplicate-warning check filters by invoice_type to avoid false negatives on multi-service locations. Steps: validate invoice + tenant, voidability + reason validation, duplicate-warning check, arm trigger carve-out, release locked reads, dispose adhoc charges, post void_reversal ledger entry, stamp void metadata, log voided event to invoice_events (tenant_id synced by trigger), return JSONB payload.';


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: account_ledger; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.account_ledger (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id uuid NOT NULL,
    customer_id uuid NOT NULL,
    location_id uuid,
    transaction_date date NOT NULL,
    transaction_type text NOT NULL,
    description text NOT NULL,
    amount numeric(12,2) NOT NULL,
    running_balance numeric(12,2),
    reference_type text,
    reference_id uuid,
    created_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT account_ledger_reference_type_check CHECK ((reference_type = ANY (ARRAY['invoice'::text, 'payment'::text, 'customer_credit'::text, 'adhoc_charge'::text, 'invoice_application'::text, 'billing_run'::text, 'escheatment_event'::text, 'manual'::text, 'invoice_void'::text, 'refund'::text]))),
    CONSTRAINT account_ledger_transaction_type_check CHECK ((transaction_type = ANY (ARRAY['charge'::text, 'payment'::text, 'adjustment'::text, 'credit_issued'::text, 'credit_applied'::text, 'late_fee'::text, 'deposit'::text, 'refund'::text, 'write_off'::text, 'transfer'::text, 'nsf'::text, 'escheat'::text, 'donation'::text, 'void_reversal'::text])))
);


--
-- Name: adhoc_charges; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.adhoc_charges (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id uuid NOT NULL,
    charge_number text NOT NULL,
    customer_id uuid NOT NULL,
    location_id uuid,
    meter_id uuid,
    charge_type text NOT NULL,
    description text NOT NULL,
    amount numeric(12,2) NOT NULL,
    is_taxable boolean DEFAULT false NOT NULL,
    service_type text,
    effective_date date DEFAULT CURRENT_DATE NOT NULL,
    target_billing_period text,
    status text DEFAULT 'pending'::text NOT NULL,
    billed_on_invoice_id uuid,
    billed_at timestamp with time zone,
    source text DEFAULT 'manual'::text NOT NULL,
    external_reference text,
    triggered_by_payment_id uuid,
    triggered_by_reading_id uuid,
    triggered_by_invoice_id uuid,
    created_by uuid,
    created_by_ai boolean DEFAULT false NOT NULL,
    ai_audit_id uuid,
    created_by_suggestion_id uuid,
    reason text,
    requires_approval boolean DEFAULT false NOT NULL,
    approval_threshold_at_creation numeric(12,2),
    approved_by uuid,
    approved_at timestamp with time zone,
    voided_at timestamp with time zone,
    voided_by uuid,
    void_reason text,
    waived_at timestamp with time zone,
    waived_by uuid,
    waive_reason text,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    billed_on_line_item_id uuid,
    billed_by_billing_run_id uuid,
    voided_from_invoice_id uuid,
    CONSTRAINT adhoc_charges_charge_type_check CHECK ((charge_type = ANY (ARRAY['tap_fee'::text, 'reconnection_fee'::text, 'disconnection_fee'::text, 'after_hours_fee'::text, 'meter_test_fee'::text, 'meter_install_fee'::text, 'damage_fee'::text, 'returned_payment_fee'::text, 'late_fee'::text, 'penalty'::text, 'deposit'::text, 'deposit_refund'::text, 'credit'::text, 'adjustment'::text, 'backflow_test_fee'::text, 'hydrant_meter_rental'::text, 'miscellaneous'::text]))),
    CONSTRAINT adhoc_charges_service_type_check CHECK ((service_type = ANY (ARRAY['water'::text, 'sewer'::text, 'electric'::text, 'gas'::text, 'stormwater'::text, 'trash'::text, 'reclaimed_water'::text]))),
    CONSTRAINT adhoc_charges_source_check CHECK ((source = ANY (ARRAY['manual'::text, 'service_order'::text, 'ai_suggestion'::text, 'import'::text, 'system_generated'::text, 'payment_reversal'::text]))),
    CONSTRAINT adhoc_charges_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'billed'::text, 'void'::text, 'waived'::text, 'void_pending_rebill'::text])))
);


--
-- Name: TABLE adhoc_charges; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.adhoc_charges IS 'One-time charges queued for the next eligible billing run. Strictly one-time — recurring charges belong in rate_items + rate_schedule_items.';


--
-- Name: COLUMN adhoc_charges.is_taxable; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.adhoc_charges.is_taxable IS 'Whether this charge is subject to percentage_of_bill tax components (sales tax, franchise tax). Set at charge creation time from platform defaults by charge_type, then overridable per row by the operator. Operator override is rare; defaults handle most cases correctly.

    Platform defaults (Texas Tax Code Chapter 151 / common utility convention):
      Generally TAXABLE (service work or equipment):
        tap_fee, reconnection_fee, disconnection_fee, meter_install_fee, meter_test_fee,
        after_hours_fee, hydrant_meter_rental, backflow_test_fee
      Generally NOT TAXABLE (penalty, recovery, refundable, financial):
        late_fee, returned_payment_fee, penalty, damage_fee, deposit, deposit_refund,
        credit, adjustment

    Tenants in jurisdictions where defaults diverge can override per-charge-type via
    tenant.settings.adhoc_taxability_overrides (see tenants.settings documentation).';


--
-- Name: COLUMN adhoc_charges.effective_date; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.adhoc_charges.effective_date IS 'Date this charge becomes eligible for billing. Default = today. Future dates schedule the charge for later. Billing engine pulls: effective_date <= run.period_end AND status = pending.';


--
-- Name: COLUMN adhoc_charges.target_billing_period; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.adhoc_charges.target_billing_period IS 'Optional: pin this charge to a specific billing period (e.g. "2026-04"). When set, billing engine includes only when the run.billing_period matches.';


--
-- Name: COLUMN adhoc_charges.status; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.adhoc_charges.status IS 'Lifecycle state. pending=ready for billing; billed=on a posted invoice; void=charge was a mistake (never bill); waived=forgiven; void_pending_rebill=was on a voided invoice, operator must decide: approve for rebill (->pending) or do not rebill (->void).';


--
-- Name: COLUMN adhoc_charges.source; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.adhoc_charges.source IS 'How this charge came into being. manual=operator; service_order=field work completion; ai_suggestion=AI proposed and approved; import=bulk load; system_generated=automated triggers (NSF, late fees); payment_reversal=from reversal logic.';


--
-- Name: COLUMN adhoc_charges.created_by_suggestion_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.adhoc_charges.created_by_suggestion_id IS 'When created_by_ai=true, this references the approved ai_suggestions row. Required by the Section 10 trigger for AI-driven mutations.';


--
-- Name: COLUMN adhoc_charges.void_reason; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.adhoc_charges.void_reason IS 'Why this charge was voided. Void = charge was a mistake (should not have existed). Different from waive (charge was correct but forgiven).';


--
-- Name: COLUMN adhoc_charges.waive_reason; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.adhoc_charges.waive_reason IS 'Why this charge was waived. Waive = charge was correct but written off (goodwill, hardship, etc.). Different from void (charge was a mistake).';


--
-- Name: COLUMN adhoc_charges.billed_on_line_item_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.adhoc_charges.billed_on_line_item_id IS 'Phase 5 sets this when the charge is picked up into a billing run, linking the charge to the specific invoice_line_items row created from it. Read direction for dispute resolution: invoice_line_items.adhoc_charge_id is the inverse link.';


--
-- Name: COLUMN adhoc_charges.billed_by_billing_run_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.adhoc_charges.billed_by_billing_run_id IS 'Phase 5 sets this when the charge is picked up. Identifies which billing run consumed the charge, distinct from billed_on_invoice_id (which is the billing artifact). Useful for auditing run-level decisions and for re-running corrections that need to know which charges were originally attached.';


--
-- Name: COLUMN adhoc_charges.voided_from_invoice_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.adhoc_charges.voided_from_invoice_id IS 'Set by void_invoice() to preserve the invoice reference before billed_on_invoice_id is cleared. Populated regardless of charge disposition (auto-revert or void_pending_rebill). Audit chain: charge -> voided_from_invoice_id -> voided invoice                                  -> replaces_invoice_id -> correction invoice.';


--
-- Name: correction_run_targets; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.correction_run_targets (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id uuid NOT NULL,
    billing_run_id uuid NOT NULL,
    voided_invoice_id uuid NOT NULL,
    meter_id uuid NOT NULL,
    customer_id uuid NOT NULL,
    location_id uuid,
    correction_invoice_id uuid,
    rate_date_mode text DEFAULT 'run_default'::text NOT NULL,
    rate_date_override date,
    created_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT correction_run_targets_check CHECK (((rate_date_mode <> 'custom'::text) OR (rate_date_override IS NOT NULL))),
    CONSTRAINT correction_run_targets_check1 CHECK (((rate_date_mode = 'custom'::text) OR (rate_date_override IS NULL))),
    CONSTRAINT correction_run_targets_rate_date_mode_check CHECK ((rate_date_mode = ANY (ARRAY['run_default'::text, 'historical'::text, 'current'::text, 'custom'::text])))
);


--
-- Name: TABLE correction_run_targets; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.correction_run_targets IS 'Junction table: one row per voided invoice targeted by a correction billing run. Inserted at Phase 0 (run initiation). correction_invoice_id populated at Phase 7 (invoice assembly). Drives Phase 1 candidate selection, Phase 5 rate date resolution, and the void_released_read_alerts view. Supports batch corrections (multiple voided invoices in one correction run) and per-target rate date overrides.';


--
-- Name: COLUMN correction_run_targets.correction_invoice_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.correction_run_targets.correction_invoice_id IS 'Set at Phase 7 (invoice assembly) once the correction invoice is created. NULL while the correction run is in progress (Phases 0-6). Used by the alert view to confirm a correction invoice exists, not just a run.';


--
-- Name: COLUMN correction_run_targets.rate_date_mode; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.correction_run_targets.rate_date_mode IS 'Per-target rate date control for Phase 5. run_default=inherit billing_runs.correction_rate_mode; historical=force voided invoice period_end; current=force CURRENT_DATE; custom=use rate_date_override. Override is useful in batch corrections where most meters use historical rates but a specific meter (wrong_meter scenario) needs current rates.';


--
-- Name: COLUMN correction_run_targets.rate_date_override; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.correction_run_targets.rate_date_override IS 'Explicit rate lookup date when rate_date_mode=custom. NULL for all other modes. Must be provided if mode=custom (enforced by CHECK constraint).';


--
-- Name: invoices; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.invoices (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id uuid NOT NULL,
    invoice_number text NOT NULL,
    billing_run_id uuid,
    customer_id uuid NOT NULL,
    location_id uuid,
    parent_invoice_id uuid,
    is_consolidated boolean DEFAULT false NOT NULL,
    invoice_type text DEFAULT 'regular'::text NOT NULL,
    replaces_invoice_id uuid,
    invoice_date date NOT NULL,
    billing_period text NOT NULL,
    period_start date NOT NULL,
    period_end date NOT NULL,
    due_date date NOT NULL,
    status text DEFAULT 'draft'::text NOT NULL,
    previous_balance numeric(12,2) DEFAULT 0 NOT NULL,
    total_charges numeric(12,2) DEFAULT 0 NOT NULL,
    total_credits numeric(12,2) DEFAULT 0 NOT NULL,
    total_taxes numeric(12,2) DEFAULT 0 NOT NULL,
    total_adjustments numeric(12,2) DEFAULT 0 NOT NULL,
    amount_due numeric(12,2) DEFAULT 0 NOT NULL,
    amount_paid numeric(12,2) DEFAULT 0 NOT NULL,
    balance numeric(12,2) DEFAULT 0 NOT NULL,
    tax_breakdown jsonb DEFAULT '[]'::jsonb NOT NULL,
    has_estimated_reads boolean DEFAULT false NOT NULL,
    estimated_read_count integer DEFAULT 0 NOT NULL,
    late_fee_assessed boolean DEFAULT false NOT NULL,
    late_fee_amount numeric(12,2) DEFAULT 0,
    dunning_stage text DEFAULT 'current'::text NOT NULL,
    write_off_reason text,
    write_off_date date,
    write_off_approved_by uuid,
    delivery_method text DEFAULT 'email'::text,
    sent_at timestamp with time zone,
    pdf_url text,
    notes text,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    is_consolidated_child boolean DEFAULT false NOT NULL,
    has_anomalies boolean DEFAULT false NOT NULL,
    held_at timestamp with time zone,
    held_by uuid,
    hold_reason text,
    pdf_generated_at timestamp with time zone,
    delivery_confirmed_at timestamp with time zone,
    delivery_failed_reason text,
    delivery_attempts integer DEFAULT 0 NOT NULL,
    voided_at timestamp with time zone,
    voided_by uuid,
    void_reason_code text,
    void_reason_notes text,
    void_rebill_expected boolean DEFAULT true NOT NULL,
    CONSTRAINT invoices_check CHECK (((location_id IS NOT NULL) OR (is_consolidated = true))),
    CONSTRAINT invoices_delivery_method_check CHECK ((delivery_method = ANY (ARRAY['email'::text, 'mail'::text, 'both'::text, 'portal_only'::text, 'text_message'::text]))),
    CONSTRAINT invoices_dunning_stage_check CHECK ((dunning_stage = ANY (ARRAY['current'::text, 'reminder_sent'::text, 'late_fee_assessed'::text, 'shutoff_warning'::text, 'shutoff_scheduled'::text, 'disconnected'::text, 'payment_plan'::text, 'collections'::text, 'resolved'::text, 'written_off'::text]))),
    CONSTRAINT invoices_invoice_type_check CHECK ((invoice_type = ANY (ARRAY['regular'::text, 'final'::text, 'correction'::text, 'duplicate'::text, 'prebill'::text, 'consolidated'::text, 'credit_memo'::text]))),
    CONSTRAINT invoices_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'pending'::text, 'held'::text, 'sent'::text, 'paid'::text, 'partial'::text, 'overdue'::text, 'void'::text, 'write_off'::text]))),
    CONSTRAINT invoices_void_reason_code_check CHECK ((void_reason_code = ANY (ARRAY['wrong_read'::text, 'wrong_rate'::text, 'wrong_customer'::text, 'duplicate'::text, 'service_date_error'::text, 'system_error'::text, 'other'::text])))
);


--
-- Name: COLUMN invoices.is_consolidated; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.invoices.is_consolidated IS 'True on parent invoices that aggregate child invoices (one per location). Parent has NULL location_id.';


--
-- Name: COLUMN invoices.invoice_type; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.invoices.invoice_type IS 'Invoice variant. Regular is the default monthly cycle bill. Final closes a customer''s service (prorated charges, includes any final adhoc charges). Correction replaces a prior invoice (replaces_invoice_id populated). Duplicate is a reprint with identical content. Prebill covers deposits or connection charges before service starts. Consolidated is the parent of a multi-location bundled bill. Credit_memo represents a net-negative billing event posted to the account_ledger as a credit; not delivered to customers by default.';


--
-- Name: COLUMN invoices.status; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.invoices.status IS 'Invoice lifecycle. draft (post-Phase 6) -> pending (post-Phase 8) -> sent (post-Phase 9) -> paid. held is a Phase 7 detour: operator flagged invoice during review; stays held until released to pending or voided. Held invoices do NOT post when the parent run posts; they are managed individually via the held-invoice queue.';


--
-- Name: COLUMN invoices.tax_breakdown; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.invoices.tax_breakdown IS 'Itemized taxes by jurisdiction for regulatory-compliant display. JSONB array of {jurisdiction, authority, rate_item_id, amount}.';


--
-- Name: COLUMN invoices.has_estimated_reads; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.invoices.has_estimated_reads IS 'True when any line item used an estimated meter reading. Surfaces for customer-service and regulatory reporting.';


--
-- Name: COLUMN invoices.dunning_stage; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.invoices.dunning_stage IS 'Collections workflow state. Progresses: current -> reminder_sent -> late_fee_assessed -> shutoff_warning -> shutoff_scheduled -> disconnected -> collections/written_off/resolved.';


--
-- Name: COLUMN invoices.is_consolidated_child; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.invoices.is_consolidated_child IS 'True when this invoice rolls up to a consolidated parent (parent_invoice_id is set). Mutually exclusive with is_consolidated (parent flag). Standalone invoices have both flags false. Reporting and dashboard queries use this for fast filtering — totals should typically exclude children to avoid double-counting (parent already sums them).';


--
-- Name: COLUMN invoices.has_anomalies; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.invoices.has_anomalies IS 'True when at least one meter on this invoice carries an anomaly flag (high/low/zero usage, estimated streak, negative consumption, etc.). Set by Phase 6 from billing_run_meters.has_anomaly. Phase 7 operator review surfaces these first. Independent from has_estimated_reads — an invoice can be flagged for either or both.';


--
-- Name: COLUMN invoices.held_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.invoices.held_at IS 'When the invoice was placed on hold. Stamped automatically by trigger when status flips to held. Cleared automatically when status moves to pending or void.';


--
-- Name: COLUMN invoices.held_by; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.invoices.held_by IS 'User who placed the hold. May be the operator (manual hold during review) or NULL if the hold was auto-applied by the review_required_anomalies setting (system-initiated hold). Cleared when the hold is released.';


--
-- Name: COLUMN invoices.hold_reason; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.invoices.hold_reason IS 'Required when status=held. Free-text explanation: "High usage flag — awaiting customer contact", "Negative consumption — service order #1247 dispatched", "Auto-held: negative_consumption". Surfaced in the held-invoice queue for at-a-glance triage. Cleared when the hold is released.';


--
-- Name: COLUMN invoices.pdf_generated_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.invoices.pdf_generated_at IS 'When the PDF was generated and stored at pdf_url. NULL means PDF generation has not started or is in flight. Used by Phase 9 PDF worker to find pending invoices and by delivery worker to gate dispatch (delivery requires pdf_url + pdf_generated_at NOT NULL).';


--
-- Name: COLUMN invoices.delivery_confirmed_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.invoices.delivery_confirmed_at IS 'When the delivery vendor confirmed completion. For email: provider webhook for delivered (not just queued). For mail: vendor confirmation that mail entered postal stream. For portal_only: equals sent_at (no separate confirmation event). Distinct from sent_at, which is when WE attempted delivery; this is when the vendor confirmed it actually happened.';


--
-- Name: COLUMN invoices.delivery_failed_reason; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.invoices.delivery_failed_reason IS 'Failure reason from the most recent delivery attempt. Examples: "bounced — invalid email", "vendor 5xx error", "address validation failed (no zip+4)". Cleared when a retry succeeds. Surfaced in the operator dashboard so failures can be triaged.';


--
-- Name: COLUMN invoices.delivery_attempts; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.invoices.delivery_attempts IS 'Number of delivery attempts made for this invoice. Incremented by Phase 9 delivery worker on each attempt regardless of outcome. When this exceeds tenants.settings.delivery.delivery_max_attempts, the invoice is removed from the retry queue and surfaces to operators for manual intervention.';


--
-- Name: COLUMN invoices.voided_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.invoices.voided_at IS 'Timestamp when the invoice was voided. NULL when status != void.';


--
-- Name: COLUMN invoices.voided_by; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.invoices.voided_by IS 'Operator who executed the void. NULL = system-initiated void.';


--
-- Name: COLUMN invoices.void_reason_code; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.invoices.void_reason_code IS 'Structured reason code for the void. Required when status = void. wrong_read | wrong_rate | wrong_customer | duplicate | service_date_error | system_error | other. When other, void_reason_notes must be non-null (enforced at API layer, not schema).';


--
-- Name: COLUMN invoices.void_reason_notes; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.invoices.void_reason_notes IS 'Free-text operator notes on the void. Mandatory when void_reason_code = other. Optional for all other codes but recommended for RRC audit trail.';


--
-- Name: COLUMN invoices.void_rebill_expected; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.invoices.void_rebill_expected IS 'Set at void time. true=operator expects a correction run to follow (default; alert views watch for the correction). false=intentional void-only; alert views suppress for this invoice; void_only_unbilled_disposition governs unbilled unit handling. Only meaningful when status=void.';


--
-- Name: adhoc_void_pending_review; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.adhoc_void_pending_review AS
 SELECT ac.id AS charge_id,
    ac.tenant_id,
    ac.charge_number,
    ac.charge_type,
    ac.description,
    ac.amount,
    ac.service_type,
    ac.customer_id,
    ac.location_id,
    ac.meter_id,
    ac.voided_from_invoice_id,
    i.invoice_number AS voided_invoice_number,
    i.billing_period AS voided_billing_period,
    i.void_reason_code,
    i.void_rebill_expected,
    i.voided_at,
    i.voided_by,
        CASE i.void_reason_code
            WHEN 'wrong_customer'::text THEN 'Charge was on an invoice voided due to wrong customer. Reassign customer_id to the correct account, then approve for rebill.'::text
            WHEN 'duplicate'::text THEN 'Charge was on a duplicate invoice. Verify this charge is not already on the standing original invoice before approving for rebill. If already billed elsewhere, choose Do Not Rebill.'::text
            ELSE 'Charge was on a voided invoice. Review and approve for rebill or void.'::text
        END AS operator_guidance,
    (EXISTS ( SELECT 1
           FROM public.correction_run_targets crt
          WHERE (crt.voided_invoice_id = ac.voided_from_invoice_id))) AS correction_run_exists,
    (EXISTS ( SELECT 1
           FROM public.correction_run_targets crt
          WHERE ((crt.voided_invoice_id = ac.voided_from_invoice_id) AND (crt.correction_invoice_id IS NOT NULL)))) AS correction_invoice_already_assembled,
    ac.created_at AS charge_created_at,
    ac.updated_at AS charge_updated_at
   FROM (public.adhoc_charges ac
     JOIN public.invoices i ON ((i.id = ac.voided_from_invoice_id)))
  WHERE ((ac.status = 'void_pending_rebill'::text) AND (i.void_rebill_expected = true))
  ORDER BY ac.tenant_id, i.voided_at DESC, ac.amount DESC;


--
-- Name: VIEW adhoc_void_pending_review; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.adhoc_void_pending_review IS 'Adhoc charges in void_pending_rebill status awaiting operator disposition. Filters by void_rebill_expected=true (NOT NULL column, no COALESCE needed). Operator actions: approve for rebill (status=pending + target_billing_period) or do not rebill (status=void).';


--
-- Name: ai_audit_log; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ai_audit_log (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id uuid NOT NULL,
    session_id uuid,
    user_id uuid,
    parent_audit_id uuid,
    action_type text NOT NULL,
    triggered_by text DEFAULT 'user_chat'::text NOT NULL,
    ai_response_type text,
    entity_type text,
    entity_id uuid,
    user_prompt text,
    ai_interpretation text,
    result_summary text,
    error_message text,
    suggestion_id uuid,
    entity_changes jsonb,
    provider text,
    model_id text,
    input_tokens integer,
    output_tokens integer,
    cost_usd numeric(10,6),
    latency_ms integer,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT ai_audit_log_action_type_check CHECK ((action_type = ANY (ARRAY['query'::text, 'analysis'::text, 'report_generation'::text, 'navigation'::text, 'suggestion_created'::text, 'suggestion_approved'::text, 'suggestion_rejected'::text, 'mutation_executed'::text, 'clarification'::text, 'error'::text]))),
    CONSTRAINT ai_audit_log_ai_response_type_check CHECK ((ai_response_type = ANY (ARRAY['text_answer'::text, 'report_export'::text, 'chart'::text, 'navigation'::text, 'data_table'::text, 'suggestion'::text, 'error'::text, 'clarification_request'::text]))),
    CONSTRAINT ai_audit_log_triggered_by_check CHECK ((triggered_by = ANY (ARRAY['user_chat'::text, 'user_report_request'::text, 'user_navigation'::text, 'scheduled_analysis'::text, 'webhook'::text])))
);


--
-- Name: COLUMN ai_audit_log.triggered_by; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.ai_audit_log.triggered_by IS 'How the AI action was initiated. user_chat/user_report_request/user_navigation = operator-initiated. scheduled_analysis/webhook = system-initiated but READ-ONLY (no mutations). No agentic_loop value exists by product design.';


--
-- Name: COLUMN ai_audit_log.entity_changes; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.ai_audit_log.entity_changes IS 'Before/after state for action_type=mutation_executed. Lets AI answer "what did you change for this customer?" without joining external tables.';


--
-- Name: COLUMN ai_audit_log.cost_usd; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.ai_audit_log.cost_usd IS 'Token cost in USD locked at insert time using the model rate at that moment. Avoids inaccuracy if provider rates change later.';


--
-- Name: ai_sessions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ai_sessions (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id uuid NOT NULL,
    user_id uuid NOT NULL,
    title text,
    auto_titled boolean DEFAULT false NOT NULL,
    status text DEFAULT 'active'::text NOT NULL,
    started_at timestamp with time zone DEFAULT now() NOT NULL,
    ended_at timestamp with time zone,
    last_activity_at timestamp with time zone DEFAULT now() NOT NULL,
    message_count integer DEFAULT 0 NOT NULL,
    tool_call_count integer DEFAULT 0 NOT NULL,
    suggestion_count integer DEFAULT 0 NOT NULL,
    total_input_tokens integer DEFAULT 0 NOT NULL,
    total_output_tokens integer DEFAULT 0 NOT NULL,
    total_cost_usd numeric(10,4) DEFAULT 0 NOT NULL,
    primary_provider text,
    primary_model_id text,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT ai_sessions_status_check CHECK ((status = ANY (ARRAY['active'::text, 'ended'::text, 'archived'::text, 'deleted'::text])))
);


--
-- Name: TABLE ai_sessions; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.ai_sessions IS 'A single operator-AI conversation. Aggregates token/cost/suggestion counts so list views do not need to scan ai_audit_log. Operator-only in v1; no customer-facing sessions.';


--
-- Name: ai_suggestions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ai_suggestions (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id uuid NOT NULL,
    session_id uuid,
    audit_log_id uuid,
    proposed_by_user_id uuid,
    suggestion_type text NOT NULL,
    title text NOT NULL,
    reasoning text NOT NULL,
    confidence numeric(3,2),
    primary_entity_type text,
    primary_entity_id uuid,
    proposed_changes jsonb DEFAULT '[]'::jsonb NOT NULL,
    status text DEFAULT 'pending'::text NOT NULL,
    reviewed_by uuid,
    reviewed_at timestamp with time zone,
    decision_reason text,
    rejected_items jsonb DEFAULT '[]'::jsonb,
    executed_at timestamp with time zone,
    execution_audit_log_id uuid,
    execution_error text,
    expires_at timestamp with time zone,
    superseded_by_id uuid,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT ai_suggestions_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'approved'::text, 'partially_approved'::text, 'rejected'::text, 'expired'::text, 'executed'::text, 'execution_failed'::text, 'superseded'::text]))),
    CONSTRAINT ai_suggestions_suggestion_type_check CHECK ((suggestion_type = ANY (ARRAY['waive_late_fee'::text, 'adjust_invoice'::text, 'apply_credit'::text, 'transfer_credit'::text, 'merge_duplicate_customers'::text, 'update_customer_field'::text, 'update_meter_field'::text, 'create_adhoc_charge'::text, 'reverse_payment'::text, 'update_rate_assignment'::text, 'send_email_draft'::text, 'close_anomaly'::text, 'schedule_service_order'::text, 'mark_disconnect_protection'::text, 'other'::text])))
);


--
-- Name: TABLE ai_suggestions; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.ai_suggestions IS 'Single source of truth for AI-proposed mutations. The ai_tool_calls trigger blocks write tools without an approved suggestion_id.';


--
-- Name: COLUMN ai_suggestions.proposed_changes; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.ai_suggestions.proposed_changes IS 'Array of proposed changes. Even single-row suggestions use array form for consistency. Operator can partially approve via rejected_items (array of indices to exclude).';


--
-- Name: COLUMN ai_suggestions.rejected_items; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.ai_suggestions.rejected_items IS 'Indices into proposed_changes that the operator excluded during partial approval. Empty array = full approval.';


--
-- Name: ai_tool_calls; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ai_tool_calls (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id uuid NOT NULL,
    audit_log_id uuid NOT NULL,
    session_id uuid,
    sequence_number integer NOT NULL,
    tool_name text NOT NULL,
    tool_category text DEFAULT 'read'::text NOT NULL,
    tool_input jsonb DEFAULT '{}'::jsonb NOT NULL,
    tool_output jsonb,
    output_summary text,
    status text DEFAULT 'pending'::text NOT NULL,
    error_message text,
    suggestion_id uuid,
    started_at timestamp with time zone DEFAULT now() NOT NULL,
    completed_at timestamp with time zone,
    duration_ms integer,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT ai_tool_calls_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'success'::text, 'error'::text, 'timeout'::text, 'rejected_by_user'::text]))),
    CONSTRAINT ai_tool_calls_tool_category_check CHECK ((tool_category = ANY (ARRAY['read'::text, 'generate'::text, 'navigation'::text, 'write'::text, 'external_api'::text])))
);


--
-- Name: TABLE ai_tool_calls; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.ai_tool_calls IS 'One row per tool invocation. Multiple rows per ai_audit_log turn (sequenced via sequence_number). Write-category tools must reference an approved ai_suggestions row.';


--
-- Name: alerts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.alerts (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id uuid NOT NULL,
    alert_type text NOT NULL,
    priority text DEFAULT 'normal'::text NOT NULL,
    title text NOT NULL,
    message text NOT NULL,
    source_type text,
    source_id uuid,
    target_user_id uuid,
    target_role text,
    channel text DEFAULT 'in_app'::text NOT NULL,
    dedup_key text,
    is_read boolean DEFAULT false NOT NULL,
    read_at timestamp with time zone,
    is_dismissed boolean DEFAULT false NOT NULL,
    dismissed_at timestamp with time zone,
    snoozed_until timestamp with time zone,
    expires_at timestamp with time zone,
    action_url text,
    action_label text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT alerts_alert_type_check CHECK ((alert_type = ANY (ARRAY['anomaly'::text, 'billing_exception'::text, 'meter_issue'::text, 'import_complete'::text, 'import_error'::text, 'system'::text, 'payment_received'::text, 'payment_nsf'::text, 'payment_method_expiring'::text, 'auto_pay_disabled'::text, 'account_past_due'::text, 'disconnect_warning'::text, 'credit_approaching_escheat'::text, 'dunning_action_due'::text, 'tax_exemption_expiring'::text, 'disconnect_protection_expiring'::text, 'bill_message_approaching_expiry'::text, 'billing_run_review_needed'::text, 'ai_suggestion'::text, 'suggestion_needs_review'::text, 'tool_approval_needed'::text]))),
    CONSTRAINT alerts_channel_check CHECK ((channel = ANY (ARRAY['in_app'::text, 'email'::text, 'sms'::text, 'push'::text, 'multiple'::text]))),
    CONSTRAINT alerts_priority_check CHECK ((priority = ANY (ARRAY['low'::text, 'normal'::text, 'high'::text, 'urgent'::text])))
);


--
-- Name: COLUMN alerts.channel; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.alerts.channel IS 'Where this alert is delivered. in_app=notification bell; email/sms/push=external; multiple=fanned out across channels.';


--
-- Name: COLUMN alerts.dedup_key; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.alerts.dedup_key IS 'When set, the alert engine suppresses duplicate inserts with the same key (e.g., one "auto-pay failed" alert per customer per day).';


--
-- Name: anomalies; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.anomalies (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id uuid NOT NULL,
    anomaly_type text NOT NULL,
    severity text DEFAULT 'medium'::text NOT NULL,
    confidence numeric(3,2),
    status text DEFAULT 'open'::text NOT NULL,
    snoozed_until date,
    snooze_reason text,
    entity_type text NOT NULL,
    entity_id uuid NOT NULL,
    location_id uuid,
    meter_id uuid,
    customer_id uuid,
    description text NOT NULL,
    details jsonb DEFAULT '{}'::jsonb NOT NULL,
    suggested_action jsonb,
    detection_method text DEFAULT 'statistical'::text NOT NULL,
    detector_name text,
    detected_at timestamp with time zone DEFAULT now() NOT NULL,
    dedup_key text,
    recurrence_count integer DEFAULT 1 NOT NULL,
    first_detected_at timestamp with time zone DEFAULT now() NOT NULL,
    last_detected_at timestamp with time zone DEFAULT now() NOT NULL,
    linked_anomaly_id uuid,
    estimated_impact numeric(12,2),
    assigned_to uuid,
    resolved_by uuid,
    resolved_at timestamp with time zone,
    resolution_notes text,
    resolution_suggestion_id uuid,
    feedback_category text,
    feedback_notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT anomalies_anomaly_type_check CHECK ((anomaly_type = ANY (ARRAY['high_usage'::text, 'low_usage'::text, 'zero_usage'::text, 'negative_consumption'::text, 'possible_leak'::text, 'stuck_meter'::text, 'meter_rollover'::text, 'tamper_detected'::text, 'endpoint_offline'::text, 'repeated_access_issue'::text, 'endpoint_swap_unreported'::text, 'missing_reading'::text, 'estimated_streak'::text, 'partial_period_anomaly'::text, 'unbilled_service'::text, 'unbilled_usage'::text, 'rate_mismatch'::text, 'rate_schedule_mismatch'::text, 'billing_run_exception'::text, 'revenue_leakage'::text, 'duplicate_account'::text, 'address_mismatch'::text, 'stale_account'::text, 'unusual_payment_pattern'::text, 'auto_pay_failure_streak'::text, 'payment_method_expiring'::text, 'multiple_nsf_pattern'::text, 'credit_balance_stale'::text, 'deposit_refund_overdue'::text, 'escheatment_due'::text, 'escheatment_overdue'::text, 'tax_exemption_expired'::text, 'disconnect_protection_expiring'::text, 'import_column_outlier_pattern'::text, 'import_low_confidence_mapping'::text, 'other'::text]))),
    CONSTRAINT anomalies_detection_method_check CHECK ((detection_method = ANY (ARRAY['statistical'::text, 'rule_based'::text, 'ai_analysis'::text, 'manual'::text]))),
    CONSTRAINT anomalies_feedback_category_check CHECK ((feedback_category = ANY (ARRAY['true_positive_resolved'::text, 'true_positive_escalated'::text, 'false_positive_threshold_too_tight'::text, 'false_positive_seasonal_variation'::text, 'false_positive_known_issue'::text, 'false_positive_other'::text]))),
    CONSTRAINT anomalies_severity_check CHECK ((severity = ANY (ARRAY['low'::text, 'medium'::text, 'high'::text, 'critical'::text]))),
    CONSTRAINT anomalies_status_check CHECK ((status = ANY (ARRAY['open'::text, 'acknowledged'::text, 'investigating'::text, 'resolved'::text, 'false_positive'::text, 'deferred'::text, 'snoozed'::text])))
);


--
-- Name: COLUMN anomalies.suggested_action; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.anomalies.suggested_action IS 'AI-recommended next step. Structured form: {"action":"create_suggestion","suggestion_type":"waive_late_fee","..."}.';


--
-- Name: COLUMN anomalies.dedup_key; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.anomalies.dedup_key IS 'Same key = same underlying issue. Re-detecting the same anomaly bumps recurrence_count and last_detected_at instead of creating a new row.';


--
-- Name: COLUMN anomalies.feedback_category; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.anomalies.feedback_category IS 'Operator feedback for detector tuning. false_positive_* values flag the detector for review; true_positive_* confirm the detector worked.';


--
-- Name: auto_pay_settings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auto_pay_settings (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id uuid NOT NULL,
    customer_id uuid NOT NULL,
    payment_method_id uuid NOT NULL,
    enabled boolean DEFAULT true NOT NULL,
    billing_day integer NOT NULL,
    pause_until date,
    pause_reason text,
    last_run_at timestamp with time zone,
    last_run_status text,
    next_run_at date,
    consecutive_failures integer DEFAULT 0 NOT NULL,
    max_amount numeric(12,2),
    enrolled_via text,
    enrolled_at timestamp with time zone DEFAULT now() NOT NULL,
    disabled_at timestamp with time zone,
    disabled_reason text,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT auto_pay_settings_billing_day_check CHECK (((billing_day >= 1) AND (billing_day <= 31))),
    CONSTRAINT auto_pay_settings_enrolled_via_check CHECK ((enrolled_via = ANY (ARRAY['portal'::text, 'paper_form'::text, 'phone'::text, 'agent'::text, 'in_person'::text]))),
    CONSTRAINT auto_pay_settings_last_run_status_check CHECK ((last_run_status = ANY (ARRAY['success'::text, 'failed'::text, 'skipped_paused'::text, 'skipped_no_balance'::text, 'skipped_below_threshold'::text])))
);


--
-- Name: bill_messages; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.bill_messages (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id uuid NOT NULL,
    title text,
    message_body text NOT NULL,
    effective_start date NOT NULL,
    effective_end date,
    target_customer_classes text[],
    target_service_types text[],
    target_service_areas text[],
    target_billing_cycle_ids uuid[],
    priority integer DEFAULT 5 NOT NULL,
    display_group text,
    status text DEFAULT 'draft'::text NOT NULL,
    created_by uuid,
    approved_by uuid,
    approved_at timestamp with time zone,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT bill_messages_display_group_check CHECK ((display_group = ANY (ARRAY['header'::text, 'footer'::text, 'notice_box'::text, 'insert'::text]))),
    CONSTRAINT bill_messages_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'active'::text, 'archived'::text])))
);


--
-- Name: billing_cycles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.billing_cycles (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id uuid NOT NULL,
    cycle_code text NOT NULL,
    cycle_name text NOT NULL,
    description text,
    frequency text DEFAULT 'monthly'::text NOT NULL,
    read_day integer NOT NULL,
    bill_day integer NOT NULL,
    due_days_after_bill integer DEFAULT 21 NOT NULL,
    read_route_code text,
    assigned_reader text,
    status text DEFAULT 'active'::text NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    requires_read_cycle boolean DEFAULT true NOT NULL,
    CONSTRAINT billing_cycles_bill_day_check CHECK (((bill_day >= 1) AND (bill_day <= 31))),
    CONSTRAINT billing_cycles_frequency_check CHECK ((frequency = ANY (ARRAY['monthly'::text, 'bimonthly'::text, 'quarterly'::text]))),
    CONSTRAINT billing_cycles_read_day_check CHECK (((read_day >= 1) AND (read_day <= 31))),
    CONSTRAINT billing_cycles_status_check CHECK ((status = ANY (ARRAY['active'::text, 'paused'::text, 'archived'::text])))
);


--
-- Name: TABLE billing_cycles; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.billing_cycles IS 'Defines staggered read/bill slots within a month. A utility typically has 10-20 cycles so reads and bills spread evenly. Service locations belong to exactly one cycle.';


--
-- Name: COLUMN billing_cycles.requires_read_cycle; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.billing_cycles.requires_read_cycle IS 'When true (default), Phase 0 of a billing run requires a read_cycle_instance in reads_complete status before allowing the run to proceed. When false, the run proceeds with a live meters snapshot at data_cutoff_at (AMI-style continuous reading). Set false on cycles whose meters are entirely AMI-fed.';


--
-- Name: billing_run_meters; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.billing_run_meters (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id uuid NOT NULL,
    billing_run_id uuid NOT NULL,
    meter_id uuid NOT NULL,
    outcome text NOT NULL,
    skip_reason text,
    meter_reading_id uuid,
    is_estimated_read boolean DEFAULT false NOT NULL,
    consumption numeric(14,2),
    consumption_unit text,
    has_anomaly boolean DEFAULT false NOT NULL,
    anomaly_types text[],
    invoice_id uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT billing_run_meters_outcome_check CHECK ((outcome = ANY (ARRAY['billed'::text, 'billed_estimated'::text, 'skipped_no_read'::text, 'skipped_pending_review'::text, 'skipped_no_rate_schedule'::text, 'skipped_inactive_mid_run'::text, 'skipped_excluded_reading'::text, 'skipped_negative_consumption'::text, 'skipped_zero_usage_suppressed'::text, 'skipped_unbillable'::text, 'failed_calculation'::text])))
);


--
-- Name: TABLE billing_run_meters; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.billing_run_meters IS 'Per-meter candidate set for each billing run. Records every meter that was eligible for the run, with an outcome flag describing what happened. Query this table for post-run exception reports (no-reads, high-usage flags, estimated-bill counts) rather than re-deriving candidate sets from billing_runs.scope. The candidate set is the snapshot at data_cutoff_at; meter status changes after the run do not affect history.';


--
-- Name: COLUMN billing_run_meters.outcome; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.billing_run_meters.outcome IS 'Resolution for this meter in this run. billed/billed_estimated produced line items; skipped_* produced no line items for documented reasons; failed_calculation needs operator intervention before run can complete.';


--
-- Name: COLUMN billing_run_meters.anomaly_types; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.billing_run_meters.anomaly_types IS 'Anomalies attached to this meter for this run. Values must be from the anomaly_type enum used elsewhere in the schema. Stored as array because one meter can carry multiple flags (e.g., high_usage AND estimated_streak in the same run).';


--
-- Name: billing_runs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.billing_runs (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id uuid NOT NULL,
    run_number text NOT NULL,
    billing_period text NOT NULL,
    period_start date NOT NULL,
    period_end date NOT NULL,
    billing_cycle_id uuid,
    run_type text DEFAULT 'regular'::text NOT NULL,
    is_dry_run boolean DEFAULT false NOT NULL,
    scope jsonb DEFAULT '{}'::jsonb NOT NULL,
    data_cutoff_at timestamp with time zone,
    generation_method text DEFAULT 'manual'::text NOT NULL,
    generated_by uuid,
    status text DEFAULT 'pending'::text NOT NULL,
    total_locations integer DEFAULT 0,
    total_invoices integer DEFAULT 0,
    total_amount numeric(14,2) DEFAULT 0,
    total_exceptions integer DEFAULT 0,
    total_estimated_reads integer DEFAULT 0,
    started_at timestamp with time zone,
    completed_at timestamp with time zone,
    approved_by uuid,
    approved_at timestamp with time zone,
    posted_by uuid,
    posted_at timestamp with time zone,
    notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    last_heartbeat_at timestamp with time zone,
    read_cycle_instance_id uuid,
    cancelled_at timestamp with time zone,
    cancelled_by uuid,
    correction_rate_mode text DEFAULT 'historical'::text NOT NULL,
    CONSTRAINT billing_runs_correction_rate_mode_check CHECK ((correction_rate_mode = ANY (ARRAY['historical'::text, 'current'::text]))),
    CONSTRAINT billing_runs_generation_method_check CHECK ((generation_method = ANY (ARRAY['manual'::text, 'scheduled'::text, 'api'::text, 'ai_initiated'::text]))),
    CONSTRAINT billing_runs_run_type_check CHECK ((run_type = ANY (ARRAY['regular'::text, 'off_cycle'::text, 'correction'::text, 'final'::text, 'dry_run'::text]))),
    CONSTRAINT billing_runs_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'in_progress'::text, 'review'::text, 'approved'::text, 'posted'::text, 'failed'::text, 'cancelled'::text])))
);


--
-- Name: COLUMN billing_runs.run_type; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.billing_runs.run_type IS 'regular=normal cycle run, off_cycle=out-of-sequence, correction=rebill, final=service-ending bill, dry_run=preview only';


--
-- Name: COLUMN billing_runs.scope; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.billing_runs.scope IS 'JSONB filter describing what was included. Keys: customer_classes[], service_areas[], service_types[], customer_ids[], location_ids[]. Empty object = no filter (full run).';


--
-- Name: COLUMN billing_runs.data_cutoff_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.billing_runs.data_cutoff_at IS 'Freeze line for the run. Every entity (meters, service_locations, customers, adhoc_charges, meter_readings) is filtered by created_at <= data_cutoff_at. Anything created after this timestamp rolls to the next cycle. Stamped at Phase 0 of the run; never modified after.';


--
-- Name: COLUMN billing_runs.last_heartbeat_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.billing_runs.last_heartbeat_at IS 'Worker writes this every 30 seconds while running. Watchdog cron flips to failed when stale: NULL && started_at < now()-5min, OR last_heartbeat_at < now()-2min. Releases the advisory lock and lets operator retry.';


--
-- Name: COLUMN billing_runs.read_cycle_instance_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.billing_runs.read_cycle_instance_id IS 'Optional link to the read cycle instance whose approved reads this run consumed. When set, Phase 1 candidate meters come from read_cycle_meters (the locked set at sheet issuance time). When NULL, the run uses a live meters snapshot at data_cutoff_at — used by AMI-only tenants where reads stream in continuously.';


--
-- Name: COLUMN billing_runs.cancelled_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.billing_runs.cancelled_at IS 'When the run was cancelled. Set in the same transaction that flips status to cancelled. NULL for runs that completed normally (status=posted) or are still in flight.';


--
-- Name: COLUMN billing_runs.cancelled_by; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.billing_runs.cancelled_by IS 'User who clicked Cancel on the run. Required when status=cancelled (cancellations cannot be system-initiated; the watchdog flips stuck runs to status=failed, not cancelled). The cancellation reason lives in metadata.cancellation_reason.';


--
-- Name: COLUMN billing_runs.correction_rate_mode; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.billing_runs.correction_rate_mode IS 'For run_type=correction only. Controls the rate effective date used in Phase 5. historical=use voided invoice period_end (RRC-compliant default); current=use CURRENT_DATE (for wrong-meter/wrong-service corrections where original period rates do not apply). Individual targets can override this per correction_run_targets.rate_date_mode.';


--
-- Name: communities; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.communities (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id uuid NOT NULL,
    community_name text NOT NULL,
    community_code text,
    community_type text,
    contact_name text,
    contact_email text,
    contact_phone text,
    city text,
    state text,
    zip text,
    master_customer_id uuid,
    total_units_planned integer,
    build_out_date date,
    revenue_category text,
    notes text,
    status text DEFAULT 'active'::text NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT communities_community_type_check CHECK ((community_type = ANY (ARRAY['subdivision'::text, 'mud'::text, 'hoa'::text, 'apartment_complex'::text, 'mobile_home_park'::text, 'commercial_development'::text, 'industrial_park'::text, 'mixed_use'::text, 'municipality'::text, 'other'::text]))),
    CONSTRAINT communities_status_check CHECK ((status = ANY (ARRAY['active'::text, 'inactive'::text, 'closed'::text])))
);


--
-- Name: customers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.customers (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id uuid NOT NULL,
    customer_number text NOT NULL,
    customer_type text DEFAULT 'residential'::text NOT NULL,
    first_name text,
    last_name text,
    company_name text,
    date_of_birth date,
    tax_id_type text,
    tax_id_last4 text,
    ssn_on_file boolean DEFAULT false NOT NULL,
    id_type text,
    id_number text,
    id_issuing_state text,
    id_expiration_date date,
    id_verified boolean DEFAULT false NOT NULL,
    id_verified_by uuid,
    id_verified_at timestamp with time zone,
    email text,
    phone text,
    alt_phone text,
    preferred_contact_method text DEFAULT 'mail'::text,
    preferred_language text DEFAULT 'en'::text,
    billing_delivery_method text DEFAULT 'email'::text NOT NULL,
    billing_address_line1 text,
    billing_address_line2 text,
    billing_city text,
    billing_county text,
    billing_state text,
    billing_zip text,
    is_property_owner boolean DEFAULT true NOT NULL,
    landlord_customer_id uuid,
    landlord_responsible boolean DEFAULT false NOT NULL,
    do_not_disconnect boolean DEFAULT false NOT NULL,
    disconnect_protection_type text,
    disconnect_protection_start date,
    disconnect_protection_expiry date,
    disconnect_protection_notes text,
    deposit_amount numeric(12,2) DEFAULT 0,
    deposit_status text DEFAULT 'none'::text,
    deposit_received_date date,
    deposit_refund_date date,
    deposit_refund_amount numeric(12,2),
    deposit_interest_earned numeric(12,2) DEFAULT 0,
    deposit_notes text,
    move_in_date date,
    is_tax_exempt boolean DEFAULT false NOT NULL,
    tax_exemption_reason text,
    tax_exemption_certificate text,
    tax_exemption_expiry_date date,
    tax_exemption_notes text,
    tax_exemption_verified_by uuid,
    tax_exemption_verified_at timestamp with time zone,
    donation_opt_in boolean DEFAULT false NOT NULL,
    donation_opt_in_date date,
    donation_opt_in_source text,
    status text DEFAULT 'active'::text NOT NULL,
    notes text,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    external_id text,
    external_id_source text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    billing_hold boolean DEFAULT false NOT NULL,
    billing_hold_reason text,
    billing_hold_set_at timestamp with time zone,
    billing_hold_set_by uuid,
    consolidate_invoices boolean DEFAULT false NOT NULL,
    CONSTRAINT customers_billing_delivery_method_check CHECK ((billing_delivery_method = ANY (ARRAY['email'::text, 'mail'::text, 'both'::text, 'portal_only'::text]))),
    CONSTRAINT customers_customer_type_check CHECK ((customer_type = ANY (ARRAY['residential'::text, 'commercial'::text, 'small_commercial'::text, 'large_commercial'::text, 'industrial'::text, 'government'::text, 'wholesale'::text]))),
    CONSTRAINT customers_deposit_status_check CHECK ((deposit_status = ANY (ARRAY['none'::text, 'held'::text, 'partial_applied'::text, 'applied'::text, 'refunded'::text, 'refund_pending'::text]))),
    CONSTRAINT customers_disconnect_protection_type_check CHECK ((disconnect_protection_type = ANY (ARRAY['medical_certificate'::text, 'elderly_disabled'::text, 'military_deployment'::text, 'bankruptcy_automatic_stay'::text, 'regulatory_moratorium'::text, 'payment_arrangement'::text, 'pending_dispute'::text, 'other'::text]))),
    CONSTRAINT customers_donation_opt_in_source_check CHECK ((donation_opt_in_source = ANY (ARRAY['portal'::text, 'paper_form'::text, 'phone'::text, 'agent'::text, 'in_person'::text]))),
    CONSTRAINT customers_id_type_check CHECK ((id_type = ANY (ARRAY['drivers_license'::text, 'state_id'::text, 'passport'::text, 'military_id'::text, 'matricula'::text, 'other'::text]))),
    CONSTRAINT customers_preferred_contact_method_check CHECK ((preferred_contact_method = ANY (ARRAY['mail'::text, 'email'::text, 'phone'::text, 'text'::text, 'portal'::text]))),
    CONSTRAINT customers_preferred_language_check CHECK ((preferred_language = ANY (ARRAY['en'::text, 'es'::text, 'vi'::text, 'zh'::text, 'ko'::text, 'other'::text]))),
    CONSTRAINT customers_status_check CHECK ((status = ANY (ARRAY['active'::text, 'inactive'::text, 'final_billed'::text, 'collections'::text, 'closed'::text]))),
    CONSTRAINT customers_tax_exemption_reason_check CHECK ((tax_exemption_reason = ANY (ARRAY['residential'::text, 'government'::text, 'nonprofit_501c3'::text, 'religious'::text, 'educational'::text, 'agricultural'::text, 'industrial_manufacturing'::text, 'reseller'::text, 'diplomatic'::text, 'other'::text]))),
    CONSTRAINT customers_tax_id_type_check CHECK ((tax_id_type = ANY (ARRAY['ssn'::text, 'ein'::text, 'itin'::text])))
);


--
-- Name: COLUMN customers.donation_opt_in; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.customers.donation_opt_in IS 'Customer has affirmatively consented to having residual credit balances below tenants.minimum_refund_amount applied to the tenants.donation_program_name fund. Without this opt-in, residuals follow state escheatment law.';


--
-- Name: COLUMN customers.billing_hold; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.customers.billing_hold IS 'When true, customer is excluded from billing runs with outcome=skipped_unbillable and skip_reason="Customer is on billing hold". Persistent across cycles until cleared. Set via operator action (billing_hold_set_by populated) or system action like AI fraud detection (billing_hold_set_by NULL). Cleared via operator action; clearing zeroes out reason and audit fields.';


--
-- Name: COLUMN customers.billing_hold_reason; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.customers.billing_hold_reason IS 'Required when billing_hold=true. Free-text explanation: "Disputed bill #INV-1247", "Fraud investigation case #2025-0034", "Court order, see file", "Bankruptcy proceeding". Surfaced in operator UI and exception reports. Cleared automatically when billing_hold is removed.';


--
-- Name: COLUMN customers.billing_hold_set_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.customers.billing_hold_set_at IS 'When the hold was placed. Stamped automatically by trigger when billing_hold flips to true. Cleared automatically when hold is removed.';


--
-- Name: COLUMN customers.billing_hold_set_by; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.customers.billing_hold_set_by IS 'User who placed the hold. NULL when set by system (AI fraud detection, automated dispute workflow). Populated from auth.uid() in application code. Cleared automatically when hold is removed.';


--
-- Name: COLUMN customers.consolidate_invoices; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.customers.consolidate_invoices IS 'When true, Phase 6 groups all this customer''s service locations into one consolidated parent invoice with per-location child invoices rolling up to the parent. When false (default), each location gets its own standalone invoice. Independent of billing_delivery_method (delivery is a separate dimension). Cross-cycle consolidation is NOT supported — locations on different billing_cycles still produce separate invoices regardless of this flag.';


--
-- Name: compliance_statistics; Type: MATERIALIZED VIEW; Schema: public; Owner: -
--

CREATE MATERIALIZED VIEW public.compliance_statistics AS
 SELECT tenant_id,
    id AS customer_id,
    customer_number,
    customer_type,
    is_tax_exempt,
    tax_exemption_reason,
    tax_exemption_expiry_date,
        CASE
            WHEN (is_tax_exempt = false) THEN 'not_exempt'::text
            WHEN (tax_exemption_expiry_date IS NULL) THEN 'permanent'::text
            WHEN (tax_exemption_expiry_date < CURRENT_DATE) THEN 'expired'::text
            WHEN (tax_exemption_expiry_date < (CURRENT_DATE + '60 days'::interval)) THEN 'expiring_soon'::text
            ELSE 'current'::text
        END AS tax_exemption_status,
    ((is_tax_exempt = true) AND (tax_exemption_expiry_date < CURRENT_DATE)) AS tax_exemption_expired,
    ((is_tax_exempt = true) AND (tax_exemption_expiry_date >= CURRENT_DATE) AND (tax_exemption_expiry_date < (CURRENT_DATE + '60 days'::interval))) AS tax_exemption_expiring_soon,
    do_not_disconnect,
    disconnect_protection_type,
    disconnect_protection_expiry,
        CASE
            WHEN (do_not_disconnect = false) THEN 'no_protection'::text
            WHEN (disconnect_protection_expiry IS NULL) THEN 'permanent'::text
            WHEN (disconnect_protection_expiry < CURRENT_DATE) THEN 'expired'::text
            WHEN (disconnect_protection_expiry < (CURRENT_DATE + '30 days'::interval)) THEN 'expiring_soon'::text
            ELSE 'current'::text
        END AS disconnect_protection_status,
    ((do_not_disconnect = true) AND (disconnect_protection_expiry >= CURRENT_DATE) AND (disconnect_protection_expiry < (CURRENT_DATE + '30 days'::interval))) AS disconnect_protection_expiring,
    id_expiration_date,
    ((id_verified = true) AND (id_expiration_date IS NOT NULL) AND (id_expiration_date < CURRENT_DATE)) AS id_expired
   FROM public.customers c
  WHERE (status = ANY (ARRAY['active'::text, 'final_billed'::text]))
  WITH NO DATA;


--
-- Name: customer_credits; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.customer_credits (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id uuid NOT NULL,
    customer_id uuid NOT NULL,
    origin_type text NOT NULL,
    origin_notes text,
    source_payment_id uuid,
    source_adhoc_charge_id uuid,
    source_invoice_id uuid,
    source_reference text,
    original_amount numeric(12,2) NOT NULL,
    applied_amount numeric(12,2) DEFAULT 0 NOT NULL,
    remaining_amount numeric(12,2) NOT NULL,
    status text DEFAULT 'active'::text NOT NULL,
    issued_date date DEFAULT CURRENT_DATE NOT NULL,
    expires_date date,
    issued_by uuid,
    last_activity_date date DEFAULT CURRENT_DATE NOT NULL,
    escheat_status text DEFAULT 'active'::text NOT NULL,
    due_diligence_sent_at timestamp with time zone,
    escheated_at timestamp with time zone,
    escheated_to_jurisdiction text,
    escheat_report_reference text,
    notes text,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT customer_credits_applied_amount_check CHECK ((applied_amount >= (0)::numeric)),
    CONSTRAINT customer_credits_check CHECK (((applied_amount + remaining_amount) = original_amount)),
    CONSTRAINT customer_credits_escheat_status_check CHECK ((escheat_status = ANY (ARRAY['active'::text, 'dormancy_approaching'::text, 'due_diligence_sent'::text, 'escheated'::text, 'owner_claimed'::text]))),
    CONSTRAINT customer_credits_origin_type_check CHECK ((origin_type = ANY (ARRAY['overpayment'::text, 'goodwill'::text, 'dispute_resolution'::text, 'deposit_refund'::text, 'transfer'::text, 'adjustment'::text, 'refund_reissue'::text, 'regulatory_rebate'::text, 'promotion'::text, 'other'::text]))),
    CONSTRAINT customer_credits_original_amount_check CHECK ((original_amount > (0)::numeric)),
    CONSTRAINT customer_credits_remaining_amount_check CHECK ((remaining_amount >= (0)::numeric)),
    CONSTRAINT customer_credits_status_check CHECK ((status = ANY (ARRAY['active'::text, 'fully_applied'::text, 'refunded'::text, 'donated'::text, 'escheated'::text, 'voided'::text])))
);


--
-- Name: TABLE customer_credits; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.customer_credits IS 'Origin-agnostic credit balances. Every credit instance lives here regardless of how it was created (overpayment, goodwill, deposit refund, adjustment, etc.). Applied to invoices via invoice_applications.';


--
-- Name: COLUMN customer_credits.origin_type; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.customer_credits.origin_type IS 'How this credit was created. Queryable by AI: "show me all goodwill credits this quarter" = filter by origin_type=goodwill.';


--
-- Name: COLUMN customer_credits.escheat_status; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.customer_credits.escheat_status IS 'State of unclaimed-property compliance. active=dormancy clock running; dormancy_approaching=within 90 days; due_diligence_sent=notice mailed; escheated=remitted to state; owner_claimed=owner reclaimed after escheatment.';


--
-- Name: credit_aging_statistics; Type: MATERIALIZED VIEW; Schema: public; Owner: -
--

CREATE MATERIALIZED VIEW public.credit_aging_statistics AS
 SELECT tenant_id,
    id AS credit_id,
    customer_id,
    origin_type,
    original_amount,
    remaining_amount,
    issued_date,
    last_activity_date,
    escheat_status,
    due_diligence_sent_at,
    (CURRENT_DATE - last_activity_date) AS days_since_activity,
        CASE
            WHEN (escheat_status = 'escheated'::text) THEN 'already_escheated'::text
            WHEN ((escheat_status = 'due_diligence_sent'::text) AND (due_diligence_sent_at < (now() - '60 days'::interval))) THEN 'escheat_overdue'::text
            WHEN ((CURRENT_DATE - last_activity_date) >= 1095) THEN 'escheat_due'::text
            WHEN ((CURRENT_DATE - last_activity_date) >= 1005) THEN 'dormancy_approaching'::text
            WHEN ((CURRENT_DATE - last_activity_date) >= 365) THEN 'stale'::text
            ELSE 'active'::text
        END AS aging_bucket,
        CASE
            WHEN ((origin_type = 'deposit_refund'::text) AND (remaining_amount > (0)::numeric) AND ((CURRENT_DATE - issued_date) > 60)) THEN true
            ELSE false
        END AS deposit_refund_overdue,
    (remaining_amount >= (250)::numeric) AS above_due_diligence_threshold
   FROM public.customer_credits cc
  WHERE ((status = 'active'::text) AND (remaining_amount > (0)::numeric))
  WITH NO DATA;


--
-- Name: custom_field_definitions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.custom_field_definitions (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id uuid NOT NULL,
    entity_type text NOT NULL,
    field_key text NOT NULL,
    field_label text NOT NULL,
    field_type text NOT NULL,
    is_required boolean DEFAULT false NOT NULL,
    is_searchable boolean DEFAULT false NOT NULL,
    is_visible_on_list boolean DEFAULT false NOT NULL,
    is_sensitive boolean DEFAULT false NOT NULL,
    display_order integer DEFAULT 0 NOT NULL,
    default_value text,
    options jsonb DEFAULT '[]'::jsonb,
    validation_rules jsonb DEFAULT '{}'::jsonb,
    help_text text,
    status text DEFAULT 'active'::text NOT NULL,
    created_by uuid,
    updated_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT custom_field_definitions_entity_type_check CHECK ((entity_type = ANY (ARRAY['customers'::text, 'service_locations'::text, 'meters'::text, 'meter_readings'::text, 'invoices'::text, 'billing_runs'::text, 'service_orders'::text, 'payments'::text, 'customer_credits'::text, 'adhoc_charges'::text]))),
    CONSTRAINT custom_field_definitions_field_key_check CHECK ((field_key <> ALL (ARRAY['id'::text, 'tenant_id'::text, 'status'::text, 'created_at'::text, 'updated_at'::text, 'metadata'::text, 'notes'::text, 'customer_number'::text, 'location_number'::text, 'meter_number'::text, 'invoice_number'::text, 'run_number'::text, 'payment_number'::text, 'charge_number'::text, 'order_number'::text, 'customer_id'::text, 'location_id'::text, 'meter_id'::text, 'invoice_id'::text, 'billing_run_id'::text, 'payment_id'::text, 'charge_id'::text, 'order_id'::text, 'amount'::text, 'description'::text, 'effective_date'::text, 'due_date'::text, 'start_date'::text, 'end_date'::text, 'created_by'::text, 'updated_by'::text, 'approved_by'::text, 'approved_at'::text]))),
    CONSTRAINT custom_field_definitions_field_type_check CHECK ((field_type = ANY (ARRAY['text'::text, 'number'::text, 'decimal'::text, 'date'::text, 'boolean'::text, 'select'::text, 'multi_select'::text, 'email'::text, 'phone'::text, 'url'::text, 'textarea'::text]))),
    CONSTRAINT custom_field_definitions_status_check CHECK ((status = ANY (ARRAY['active'::text, 'archived'::text])))
);


--
-- Name: COLUMN custom_field_definitions.is_sensitive; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.custom_field_definitions.is_sensitive IS 'When true, UI masks the value, logs exclude it, and AI responses must not surface it. Use for tax IDs, internal dispute notes, and other PII held in metadata.';


--
-- Name: COLUMN custom_field_definitions.options; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.custom_field_definitions.options IS 'For select/multi_select fields. Array of {"value":"...","label":"..."}. Validated by validate_custom_fields().';


--
-- Name: COLUMN custom_field_definitions.validation_rules; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.custom_field_definitions.validation_rules IS 'JSONB with optional keys: pattern (regex), min (numeric/date), max (numeric/date), minLength (int), maxLength (int). Enforced by validate_custom_fields().';


--
-- Name: custom_location_types; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.custom_location_types (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id uuid NOT NULL,
    type_key text NOT NULL,
    type_label text NOT NULL,
    description text,
    display_order integer DEFAULT 0 NOT NULL,
    status text DEFAULT 'active'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT custom_location_types_status_check CHECK ((status = ANY (ARRAY['active'::text, 'archived'::text])))
);


--
-- Name: customer_contacts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.customer_contacts (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id uuid NOT NULL,
    customer_id uuid NOT NULL,
    contact_type text NOT NULL,
    is_primary boolean DEFAULT false NOT NULL,
    can_make_changes boolean DEFAULT false NOT NULL,
    first_name text NOT NULL,
    last_name text NOT NULL,
    title text,
    company text,
    email text,
    phone text,
    alt_phone text,
    notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT customer_contacts_contact_type_check CHECK ((contact_type = ANY (ARRAY['billing'::text, 'service'::text, 'emergency'::text, 'authorized_agent'::text, 'property_manager'::text, 'other'::text])))
);


--
-- Name: customer_interactions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.customer_interactions (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id uuid NOT NULL,
    customer_id uuid NOT NULL,
    location_id uuid,
    interaction_type text NOT NULL,
    channel text,
    reason text NOT NULL,
    subject text NOT NULL,
    description text,
    status text DEFAULT 'open'::text NOT NULL,
    resolution text,
    resolved_at timestamp with time zone,
    follow_up_required boolean DEFAULT false NOT NULL,
    follow_up_date date,
    follow_up_assigned_to uuid,
    follow_up_notes text,
    handled_by uuid,
    duration_minutes integer,
    invoice_id uuid,
    service_order_id uuid,
    ai_audit_id uuid,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT customer_interactions_channel_check CHECK ((channel = ANY (ARRAY['phone'::text, 'email'::text, 'in_person'::text, 'portal'::text, 'mail'::text, 'text'::text, 'ai'::text, 'field'::text, 'other'::text]))),
    CONSTRAINT customer_interactions_interaction_type_check CHECK ((interaction_type = ANY (ARRAY['phone_inbound'::text, 'phone_outbound'::text, 'email_inbound'::text, 'email_outbound'::text, 'walk_in'::text, 'portal_message'::text, 'mail_inbound'::text, 'mail_outbound'::text, 'text_inbound'::text, 'text_outbound'::text, 'ai_chat'::text, 'field_visit'::text, 'other'::text]))),
    CONSTRAINT customer_interactions_reason_check CHECK ((reason = ANY (ARRAY['billing_inquiry'::text, 'payment_issue'::text, 'high_bill_complaint'::text, 'service_request'::text, 'leak_report'::text, 'water_quality'::text, 'outage_report'::text, 'meter_issue'::text, 'disconnect_reconnect'::text, 'payment_arrangement'::text, 'name_address_change'::text, 'general_inquiry'::text, 'complaint'::text, 'compliment'::text, 'other'::text]))),
    CONSTRAINT customer_interactions_status_check CHECK ((status = ANY (ARRAY['open'::text, 'in_progress'::text, 'waiting_customer'::text, 'resolved'::text, 'escalated'::text, 'closed'::text])))
);


--
-- Name: customer_tax_exemptions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.customer_tax_exemptions (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id uuid NOT NULL,
    customer_id uuid NOT NULL,
    exemption_type text NOT NULL,
    exemption_reason text,
    service_types text[],
    certificate_number text,
    issuing_authority text,
    certificate_url text,
    effective_start date DEFAULT CURRENT_DATE NOT NULL,
    effective_end date,
    status text DEFAULT 'active'::text NOT NULL,
    revoked_at timestamp with time zone,
    revoked_by uuid,
    revoked_reason text,
    verified_by uuid,
    verified_at timestamp with time zone,
    verification_notes text,
    notes text,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT customer_tax_exemptions_check CHECK (((exemption_type <> 'other'::text) OR ((exemption_reason IS NOT NULL) AND (exemption_reason <> ''::text)))),
    CONSTRAINT customer_tax_exemptions_exemption_type_check CHECK ((exemption_type = ANY (ARRAY['non_profit'::text, 'government'::text, 'agricultural'::text, 'industrial'::text, 'sales_for_resale'::text, 'religious'::text, 'educational'::text, 'medical'::text, 'other'::text]))),
    CONSTRAINT customer_tax_exemptions_status_check CHECK ((status = ANY (ARRAY['pending_verification'::text, 'active'::text, 'expired'::text, 'revoked'::text, 'rejected'::text])))
);


--
-- Name: TABLE customer_tax_exemptions; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.customer_tax_exemptions IS 'Per-service-type tax exemptions for customers. A customer may have multiple concurrent exemptions covering different service types. Replaces the simple is_tax_exempt flag on customers (which remains for backward compat). The should_charge_tax() function returns "exempt" if ANY active exemption covers the line item''s service_type.';


--
-- Name: COLUMN customer_tax_exemptions.service_types; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.customer_tax_exemptions.service_types IS 'Which service types this exemption applies to. NULL or empty array = ALL services (blanket exemption). Non-empty = only the listed types (e.g. {"gas"} = exempt from gas only, still pays sewer/water tax).';


--
-- Name: customer_winter_averages; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.customer_winter_averages (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id uuid NOT NULL,
    meter_id uuid NOT NULL,
    customer_id uuid NOT NULL,
    winter_year integer NOT NULL,
    winter_months integer[] NOT NULL,
    avg_consumption numeric(14,2) NOT NULL,
    consumption_unit text NOT NULL,
    months_used integer NOT NULL,
    sample_size integer NOT NULL,
    computed_at timestamp with time zone DEFAULT now() NOT NULL,
    computed_by_user_id uuid,
    confidence text DEFAULT 'good'::text NOT NULL,
    notes text,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT customer_winter_averages_confidence_check CHECK ((confidence = ANY (ARRAY['good'::text, 'partial'::text, 'insufficient'::text])))
);


--
-- Name: TABLE customer_winter_averages; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.customer_winter_averages IS 'Cached annual winter average consumption per meter. Used by Phase 3 sewer calculations when sewer_calc_method=winter_avg and the current period is OUTSIDE the configured winter months. Populated by a scheduled job in early spring (after winter ends) for all meters with sewer service on a winter_avg rate schedule. Operator can also trigger recomputation manually. Phase 3 reads this table; never writes during a billing run.';


--
-- Name: COLUMN customer_winter_averages.winter_year; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.customer_winter_averages.winter_year IS 'Year the winter ended. Winter 2025-2026 (Dec 2025, Jan 2026, Feb 2026) is stored as 2026. This makes "current applicable winter average" a simple max(winter_year) lookup against the current calendar year.';


--
-- Name: COLUMN customer_winter_averages.confidence; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.customer_winter_averages.confidence IS 'good = all configured winter months had actual reads. partial = some months had estimates or were missing but result is still usable. insufficient = too few reads (e.g., new customer mid-winter); Phase 3 falls back to current consumption with winter_avg_missing anomaly.';


--
-- Name: dunning_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.dunning_events (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id uuid NOT NULL,
    invoice_id uuid NOT NULL,
    customer_id uuid NOT NULL,
    event_type text NOT NULL,
    event_date timestamp with time zone DEFAULT now() NOT NULL,
    triggered_by uuid,
    triggered_automatically boolean DEFAULT false NOT NULL,
    amount_related numeric(12,2),
    scheduled_date date,
    previous_stage text,
    new_stage text,
    notes text,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT dunning_events_event_type_check CHECK ((event_type = ANY (ARRAY['reminder_sent'::text, 'late_fee_applied'::text, 'shutoff_notice_sent'::text, 'shutoff_scheduled'::text, 'disconnected'::text, 'reconnected'::text, 'payment_plan_created'::text, 'payment_plan_broken'::text, 'sent_to_collections'::text, 'written_off'::text, 'resolved'::text])))
);


--
-- Name: TABLE dunning_events; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.dunning_events IS 'Immutable log of collections actions per invoice. The current state lives on invoices.dunning_stage; this table records the full history.';


--
-- Name: escheatment_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.escheatment_events (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id uuid NOT NULL,
    customer_credit_id uuid NOT NULL,
    customer_id uuid NOT NULL,
    event_type text NOT NULL,
    event_date timestamp with time zone DEFAULT now() NOT NULL,
    amount_related numeric(12,2),
    notice_method text,
    notice_reference text,
    jurisdiction text,
    regulatory_reference text,
    triggered_by uuid,
    triggered_automatically boolean DEFAULT false NOT NULL,
    notes text,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT escheatment_events_event_type_check CHECK ((event_type = ANY (ARRAY['dormancy_flag'::text, 'due_diligence_sent'::text, 'owner_responded'::text, 'owner_claimed_credit'::text, 'escheated_to_state'::text, 'owner_reclaimed_from_state'::text, 'exemption_applied'::text, 'donated'::text]))),
    CONSTRAINT escheatment_events_notice_method_check CHECK ((notice_method = ANY (ARRAY['email'::text, 'first_class_mail'::text, 'certified_mail'::text, 'registered_mail'::text])))
);


--
-- Name: TABLE escheatment_events; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.escheatment_events IS 'Regulator-facing audit trail for unclaimed-property compliance. Every notice sent, response received, and remittance made is logged here. Current state is on customer_credits.escheat_status.';


--
-- Name: franchise_fee_rules; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.franchise_fee_rules (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id uuid NOT NULL,
    city_name text NOT NULL,
    fee_percentage numeric(8,6) NOT NULL,
    applies_to text DEFAULT 'total_bill'::text NOT NULL,
    applies_to_customer_types text[] DEFAULT '{residential,commercial,industrial,government,wholesale}'::text[] NOT NULL,
    effective_date date DEFAULT CURRENT_DATE NOT NULL,
    expiry_date date,
    status text DEFAULT 'active'::text NOT NULL,
    remittance_frequency text,
    remittance_contact text,
    ordinance_reference text,
    notes text,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT franchise_fee_rules_applies_to_check CHECK ((applies_to = ANY (ARRAY['total_bill'::text, 'gross_revenue'::text, 'base_and_usage'::text, 'usage_only'::text]))),
    CONSTRAINT franchise_fee_rules_remittance_frequency_check CHECK ((remittance_frequency = ANY (ARRAY['monthly'::text, 'quarterly'::text, 'annually'::text]))),
    CONSTRAINT franchise_fee_rules_status_check CHECK ((status = ANY (ARRAY['active'::text, 'superseded'::text, 'archived'::text])))
);


--
-- Name: import_column_mappings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.import_column_mappings (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id uuid NOT NULL,
    import_job_id uuid NOT NULL,
    source_column_name text,
    source_column_position integer NOT NULL,
    sample_values jsonb DEFAULT '[]'::jsonb NOT NULL,
    content_classification text,
    classification_confidence numeric(3,2),
    proposed_target_field text,
    mapping_confidence numeric(3,2),
    proposed_transforms jsonb DEFAULT '[]'::jsonb,
    operator_decision text DEFAULT 'pending'::text NOT NULL,
    final_target_field text,
    final_transforms jsonb DEFAULT '[]'::jsonb,
    operator_notes text,
    decided_by uuid,
    decided_at timestamp with time zone,
    has_outlier_pattern boolean DEFAULT false NOT NULL,
    outlier_count integer DEFAULT 0,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT import_column_mappings_content_classification_check CHECK ((content_classification = ANY (ARRAY['person_name'::text, 'company_name'::text, 'address'::text, 'city'::text, 'state'::text, 'zip_code'::text, 'phone'::text, 'email'::text, 'date'::text, 'currency'::text, 'number'::text, 'text'::text, 'boolean'::text, 'id_or_code'::text, 'meter_serial'::text, 'amr_ami_endpoint'::text, 'mixed'::text, 'empty'::text, 'unknown'::text]))),
    CONSTRAINT import_column_mappings_operator_decision_check CHECK ((operator_decision = ANY (ARRAY['pending'::text, 'accepted'::text, 'overridden'::text, 'ignored'::text])))
);


--
-- Name: TABLE import_column_mappings; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.import_column_mappings IS 'Per-import per-column AI inspection and operator decisions. Captures content classification, proposed mapping with confidence, sample values, and what the operator ultimately decided. Outlier pattern detection updates has_outlier_pattern after row validation.';


--
-- Name: COLUMN import_column_mappings.content_classification; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.import_column_mappings.content_classification IS 'AI''s read of what kind of data is in the column. Includes utility-specific classifications (meter_serial, amr_ami_endpoint) for read imports.';


--
-- Name: import_jobs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.import_jobs (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id uuid NOT NULL,
    initiated_by uuid NOT NULL,
    import_type text NOT NULL,
    source_type text NOT NULL,
    source_file_url text,
    source_filename text,
    source_file_size_bytes bigint,
    source_file_hash text,
    idempotency_key text,
    mapping_template_id uuid,
    column_mapping jsonb DEFAULT '[]'::jsonb,
    error_handling_policy text NOT NULL,
    is_dry_run boolean DEFAULT false NOT NULL,
    import_summary jsonb DEFAULT '{}'::jsonb,
    status text DEFAULT 'pending'::text NOT NULL,
    mapping_suggestion_id uuid,
    total_rows integer DEFAULT 0,
    processed_rows integer DEFAULT 0,
    committed_rows integer DEFAULT 0,
    held_rows integer DEFAULT 0,
    error_rows integer DEFAULT 0,
    warning_rows integer DEFAULT 0,
    skipped_rows integer DEFAULT 0,
    ai_extraction_log jsonb DEFAULT '{}'::jsonb,
    validation_errors jsonb DEFAULT '[]'::jsonb,
    started_at timestamp with time zone,
    completed_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT import_jobs_error_handling_policy_check CHECK ((error_handling_policy = ANY (ARRAY['partial_commit'::text, 'all_or_nothing'::text]))),
    CONSTRAINT import_jobs_import_type_check CHECK ((import_type = ANY (ARRAY['customers'::text, 'meters'::text, 'readings'::text, 'rates'::text, 'payments'::text, 'locations'::text, 'full_system'::text, 'custom'::text]))),
    CONSTRAINT import_jobs_source_type_check CHECK ((source_type = ANY (ARRAY['csv'::text, 'excel'::text, 'pdf'::text, 'legacy_export'::text, 'api'::text, 'ai_extracted'::text]))),
    CONSTRAINT import_jobs_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'inspecting'::text, 'awaiting_mapping_approval'::text, 'validating'::text, 'validated'::text, 'awaiting_error_review'::text, 'importing'::text, 'complete'::text, 'partial'::text, 'failed'::text, 'cancelled'::text])))
);


--
-- Name: COLUMN import_jobs.idempotency_key; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.import_jobs.idempotency_key IS 'Prevents double-import of the same file. Operator can supply OR system auto-derives from filename + source_file_hash. Unique per tenant.';


--
-- Name: COLUMN import_jobs.error_handling_policy; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.import_jobs.error_handling_policy IS 'Per-import override of tenants.default_import_error_policy. partial_commit: valid rows commit, errors held; all_or_nothing: any error aborts everything.';


--
-- Name: COLUMN import_jobs.is_dry_run; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.import_jobs.is_dry_run IS 'When true, validation runs and import_summary populates but nothing commits. Lets operators preview impact before pulling the trigger.';


--
-- Name: COLUMN import_jobs.import_summary; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.import_jobs.import_summary IS 'Post-validation impact summary. Structure: {"will_create":47,"will_update":12,"will_skip":3,"errors":2,"warnings":8,"by_entity":{"customers":47,"locations":12}}';


--
-- Name: import_mapping_templates; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.import_mapping_templates (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id uuid NOT NULL,
    name text NOT NULL,
    description text,
    import_type text NOT NULL,
    source_system text,
    source_format text,
    column_mapping jsonb DEFAULT '[]'::jsonb NOT NULL,
    learned_transforms jsonb DEFAULT '[]'::jsonb NOT NULL,
    times_used integer DEFAULT 0 NOT NULL,
    last_used_at timestamp with time zone,
    last_success_rate numeric(5,4),
    status text DEFAULT 'active'::text NOT NULL,
    created_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT import_mapping_templates_import_type_check CHECK ((import_type = ANY (ARRAY['customers'::text, 'meters'::text, 'readings'::text, 'rates'::text, 'payments'::text, 'locations'::text, 'full_system'::text, 'custom'::text]))),
    CONSTRAINT import_mapping_templates_status_check CHECK ((status = ANY (ARRAY['active'::text, 'archived'::text, 'draft'::text])))
);


--
-- Name: TABLE import_mapping_templates; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.import_mapping_templates IS 'Reusable column-to-schema mappings, tenant-scoped. AI-approved transforms accumulate in learned_transforms so each subsequent import gets smarter.';


--
-- Name: import_staging; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.import_staging (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id uuid NOT NULL,
    import_job_id uuid NOT NULL,
    row_number integer NOT NULL,
    raw_data jsonb NOT NULL,
    mapped_data jsonb,
    status text DEFAULT 'pending'::text NOT NULL,
    matched_by text,
    errors jsonb DEFAULT '[]'::jsonb,
    warnings jsonb DEFAULT '[]'::jsonb,
    target_entity text,
    target_id uuid,
    depends_on_row_numbers integer[],
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT import_staging_matched_by_check CHECK ((matched_by = ANY (ARRAY['external_id'::text, 'customer_number'::text, 'location_number'::text, 'meter_number'::text, 'composite_key'::text, 'none'::text]))),
    CONSTRAINT import_staging_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'valid'::text, 'warning'::text, 'failed_validation'::text, 'failed_fk_reference'::text, 'awaiting_dependency'::text, 'awaiting_review'::text, 'imported'::text, 'imported_with_warnings'::text, 'updated_existing'::text, 'skipped'::text, 'rejected_by_operator'::text])))
);


--
-- Name: invoice_applications; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.invoice_applications (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id uuid NOT NULL,
    invoice_id uuid NOT NULL,
    source_type text NOT NULL,
    source_id uuid NOT NULL,
    amount numeric(12,2) NOT NULL,
    applied_at timestamp with time zone DEFAULT now() NOT NULL,
    applied_by uuid,
    reversed_at timestamp with time zone,
    reversed_by uuid,
    reversed_reason text,
    notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT invoice_applications_amount_check CHECK ((amount > (0)::numeric)),
    CONSTRAINT invoice_applications_source_type_check CHECK ((source_type = ANY (ARRAY['payment'::text, 'credit'::text])))
);


--
-- Name: TABLE invoice_applications; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.invoice_applications IS 'Single polymorphic table for applying both payments and credits to invoices. source_type determines which table source_id references (payments or customer_credits).';


--
-- Name: COLUMN invoice_applications.source_type; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.invoice_applications.source_type IS 'Type of source applied: payment (source_id -> payments.id) or credit (source_id -> customer_credits.id).';


--
-- Name: invoice_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.invoice_events (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id uuid NOT NULL,
    invoice_id uuid NOT NULL,
    event_type text NOT NULL,
    operator_id uuid,
    occurred_at timestamp with time zone DEFAULT now() NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    CONSTRAINT invoice_events_event_type_check CHECK ((event_type = ANY (ARRAY['created'::text, 'sent'::text, 'held'::text, 'released_from_hold'::text, 'voided'::text, 'void_attempted_blocked'::text, 'correction_initiated'::text, 'correction_posted'::text, 'payment_applied'::text, 'written_off'::text, 'status_changed'::text])))
);


--
-- Name: TABLE invoice_events; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.invoice_events IS 'Append-only event log for invoice lifecycle events. One row per event. Never updated, never deleted. Provides single-query audit sequence. tenant_id is synchronised from invoices.tenant_id by a BEFORE INSERT trigger. occurred_at must be within 5 minutes of now() at insert time or the row is rejected by trigger. void_invoice() inserts the voided event. void_attempted_blocked events are inserted by the API layer after catching void_invoice() exceptions (in a separate transaction, since the failed void rolls back). Billing run phases should INSERT their own events as each phase completes.';


--
-- Name: COLUMN invoice_events.metadata; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.invoice_events.metadata IS 'Event-specific payload. voided event captures invoice_status_at_void and amount_due as a point-in-time snapshot — the only record of the invoice state at the exact moment of void. See table comment for schema by event_type. Indexed via GIN for efficient JSONB predicate queries.';


--
-- Name: invoice_line_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.invoice_line_items (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id uuid NOT NULL,
    invoice_id uuid NOT NULL,
    line_order integer DEFAULT 0 NOT NULL,
    service_type text NOT NULL,
    meter_id uuid,
    charge_type text NOT NULL,
    description text NOT NULL,
    rate_schedule_id uuid,
    rate_item_id uuid,
    meter_reading_id uuid,
    usage_quantity numeric(14,2),
    usage_unit text,
    rate numeric(12,6),
    tier_label text,
    coverage_start date,
    coverage_end date,
    days_covered integer,
    days_in_period integer,
    partial_period_policy_applied text,
    taxable_amount numeric(12,2),
    gas_meter_factor numeric(10,6),
    gas_ccf_used numeric(14,2),
    gas_therms_billed numeric(14,2),
    gas_commodity_rate numeric(12,6),
    adhoc_charge_id uuid,
    amount numeric(12,2) NOT NULL,
    is_taxable boolean DEFAULT false NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT invoice_line_items_charge_type_check CHECK ((charge_type = ANY (ARRAY['base_charge'::text, 'usage_charge'::text, 'surcharge'::text, 'tax'::text, 'late_fee'::text, 'deposit'::text, 'credit'::text, 'adjustment'::text, 'penalty'::text, 'adhoc'::text, 'minimum_bill_adjustment'::text, 'consolidated_summary'::text, 'misc'::text]))),
    CONSTRAINT invoice_line_items_partial_period_policy_applied_check CHECK ((partial_period_policy_applied = ANY (ARRAY['prorated'::text, 'charge_both'::text, 'period_holder'::text]))),
    CONSTRAINT invoice_line_items_service_type_check CHECK ((service_type = ANY (ARRAY['water'::text, 'sewer'::text, 'electric'::text, 'gas'::text, 'stormwater'::text, 'trash'::text, 'reclaimed_water'::text, 'general'::text])))
);


--
-- Name: COLUMN invoice_line_items.rate_item_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.invoice_line_items.rate_item_id IS 'Atomic rate_item that generated this line (Customer Charge, GCA, CRRC, etc.). Enables AI queries like "show me all GCA charges this month" via a single FK lookup instead of text-matching descriptions.';


--
-- Name: COLUMN invoice_line_items.coverage_start; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.invoice_line_items.coverage_start IS 'Start date of the coverage window for this line. NULL means the line covers the full billing period. Only populated for partial-period fixed charges.';


--
-- Name: COLUMN invoice_line_items.partial_period_policy_applied; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.invoice_line_items.partial_period_policy_applied IS 'Which partial-period policy produced this line. Only populated when coverage_start is not null (partial-period fixed charge). Values match tenants.default_partial_period_policy: prorated, charge_both, period_holder.';


--
-- Name: materialized_view_refresh_log; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.materialized_view_refresh_log (
    view_name text NOT NULL,
    last_refresh_at timestamp with time zone DEFAULT now() NOT NULL,
    last_duration_ms integer,
    last_error text
);


--
-- Name: meter_deployments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.meter_deployments (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id uuid NOT NULL,
    meter_id uuid NOT NULL,
    deployment_number integer NOT NULL,
    location_id uuid NOT NULL,
    rate_schedule_id uuid,
    install_date date NOT NULL,
    install_read_value numeric(14,2),
    installed_by uuid,
    installed_by_name text,
    removal_date date,
    removal_read_value numeric(14,2),
    removal_reason text,
    removed_by uuid,
    removed_by_name text,
    warehouse_location_after_removal text,
    notes text,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT meter_deployments_removal_reason_check CHECK ((removal_reason = ANY (ARRAY['upgrade_size'::text, 'damage'::text, 'hardware_failure'::text, 'ami_upgrade'::text, 'tamper'::text, 'weather'::text, 'end_of_life'::text, 'customer_request'::text, 'accuracy_test_failure'::text, 'testing_required'::text, 'relocation'::text, 'other'::text])))
);


--
-- Name: TABLE meter_deployments; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.meter_deployments IS 'One row per deployment period of a physical meter. Normalizes Pattern A (reuse_record) and Pattern B (new_record) so AI queries about a meter''s deployment history return consistent results regardless of which pattern the tenant uses. Maintained automatically by trg_sync_meter_deployments — do not insert directly.';


--
-- Name: meter_endpoint_history; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.meter_endpoint_history (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id uuid NOT NULL,
    meter_id uuid NOT NULL,
    endpoint_id text NOT NULL,
    endpoint_type text,
    install_date date NOT NULL,
    removal_date date,
    removal_reason text,
    installed_by uuid,
    installed_by_name text,
    removed_by uuid,
    removed_by_name text,
    notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT meter_endpoint_history_removal_reason_check CHECK ((removal_reason = ANY (ARRAY['failed'::text, 'battery_dead'::text, 'upgrade'::text, 'damaged'::text, 'theft'::text, 'meter_removal'::text, 'other'::text])))
);


--
-- Name: meter_photos; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.meter_photos (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id uuid NOT NULL,
    meter_id uuid NOT NULL,
    meter_reading_id uuid,
    photo_type text NOT NULL,
    caption text,
    storage_path text NOT NULL,
    file_name text,
    file_size_bytes bigint,
    mime_type text,
    taken_at timestamp with time zone,
    taken_by uuid,
    taken_by_name text,
    latitude numeric(10,7),
    longitude numeric(10,7),
    gps_accuracy_meters integer,
    upload_source text DEFAULT 'web_upload'::text,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    ai_extraction_status text DEFAULT 'not_attempted'::text,
    ai_extracted_value numeric(14,2),
    ai_confidence numeric(5,4),
    ai_anomalies text[],
    ai_notes text,
    ai_extracted_at timestamp with time zone,
    ai_model_version text,
    CONSTRAINT meter_photos_ai_confidence_check CHECK (((ai_confidence IS NULL) OR ((ai_confidence >= (0)::numeric) AND (ai_confidence <= (1)::numeric)))),
    CONSTRAINT meter_photos_ai_extraction_status_check CHECK ((ai_extraction_status = ANY (ARRAY['not_attempted'::text, 'pending'::text, 'success'::text, 'low_confidence'::text, 'failed'::text, 'manual_override'::text]))),
    CONSTRAINT meter_photos_photo_type_check CHECK ((photo_type = ANY (ARRAY['install'::text, 'inspection'::text, 'annual'::text, 'damage'::text, 'tamper'::text, 'leak'::text, 'removal'::text, 'reading'::text, 'access_issue'::text, 'other'::text]))),
    CONSTRAINT meter_photos_upload_source_check CHECK ((upload_source = ANY (ARRAY['web_upload'::text, 'mobile_web'::text, 'customer_portal'::text, 'email'::text, 'api'::text, 'import'::text])))
);


--
-- Name: COLUMN meter_photos.ai_extraction_status; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.meter_photos.ai_extraction_status IS 'AI extraction lifecycle. not_attempted is default for non-reading photos. pending while the vision call is in flight. success when confidence >= tenant threshold (default 0.85). low_confidence when below threshold (reader must enter manually). manual_override when reader rejected the AI value despite high confidence.';


--
-- Name: COLUMN meter_photos.ai_extracted_value; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.meter_photos.ai_extracted_value IS 'The reading value the AI extracted from the meter face. Stored even when confidence is low so we can train/evaluate the model later. The actual saved meter_reading.reading_value may differ if the reader corrected it.';


--
-- Name: COLUMN meter_photos.ai_confidence; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.meter_photos.ai_confidence IS 'AI confidence score 0.00–1.00. Tenant-configurable threshold for auto-fill vs. require-manual-entry. Default threshold: 0.85.';


--
-- Name: COLUMN meter_photos.ai_anomalies; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.meter_photos.ai_anomalies IS 'Visual anomalies the AI detected on the meter face (broken_dial, tamper_signs, leak_indicator, face_obscured, etc.). Maps to the platform-wide anomaly_type enum where overlap exists.';


--
-- Name: meter_readings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.meter_readings (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id uuid NOT NULL,
    meter_id uuid NOT NULL,
    register_type text DEFAULT 'main'::text NOT NULL,
    register_label text,
    reading_date date NOT NULL,
    reading_value numeric(14,2) NOT NULL,
    previous_value numeric(14,2),
    previous_reading_date date,
    consumption numeric(14,2),
    consumption_unit text DEFAULT 'gallons'::text NOT NULL,
    days_in_period integer,
    read_method text DEFAULT 'manual'::text NOT NULL,
    read_by text,
    data_collector_user_id text,
    read_sequence_number integer,
    actual_read_order integer,
    reading_timestamp timestamp with time zone,
    raw_read_value numeric(14,2),
    gps_latitude numeric(10,7),
    gps_longitude numeric(10,7),
    gps_accuracy_rating text,
    gps_changed_latitude numeric(10,7),
    gps_changed_longitude numeric(10,7),
    endpoint_id text,
    changed_endpoint_id text,
    endpoint_type_received text,
    extended_endpoint_type_received text,
    endpoint_read_datetime timestamp with time zone,
    access_status text DEFAULT 'accessed'::text NOT NULL,
    access_notes text,
    skip_code text,
    force_complete_reason_code text,
    trouble_code_1 text,
    trouble_code_2 text,
    trouble_message text,
    read_condition text,
    amr_read_status text,
    tamper_count_1 integer,
    tamper_count_2 integer,
    tamper_count_1_changed_flag boolean DEFAULT false,
    tamper_count_2_changed_flag boolean DEFAULT false,
    tamper_investigated boolean DEFAULT false NOT NULL,
    tamper_investigation_notes text,
    is_estimated boolean DEFAULT false NOT NULL,
    estimation_reason text,
    quality_flag text DEFAULT 'normal'::text,
    status text DEFAULT 'active'::text NOT NULL,
    replaced_by_reading_id uuid,
    replaces_reading_id uuid,
    dispute_reason text,
    dispute_raised_by uuid,
    dispute_raised_at timestamp with time zone,
    dispute_resolved_by uuid,
    dispute_resolved_at timestamp with time zone,
    dispute_resolution_notes text,
    gas_meter_factor numeric(10,6),
    gas_pressure_corrected_volume numeric(14,2),
    gas_btu_factor numeric(10,6),
    gas_therms numeric(14,2),
    import_job_id uuid,
    vendor_reference text,
    reading_purpose text DEFAULT 'regular_cycle'::text NOT NULL,
    is_service_transition boolean DEFAULT false NOT NULL,
    transition_outgoing_customer_id uuid,
    transition_incoming_customer_id uuid,
    billing_cycle_id uuid,
    validation_status text DEFAULT 'pending_review'::text NOT NULL,
    auto_approved boolean DEFAULT false NOT NULL,
    validated_by uuid,
    validated_at timestamp with time zone,
    assigned_to_user_id uuid,
    billing_period_locked boolean DEFAULT false NOT NULL,
    locked_at timestamp with time zone,
    locked_by_billing_run_id uuid,
    locked_by_invoice_id uuid,
    triggers_correction_workflow boolean DEFAULT false NOT NULL,
    consumption_prior_period numeric(14,2),
    consumption_same_period_last_year numeric(14,2),
    consumption_pct_vs_typical numeric(8,2),
    attempted_count integer DEFAULT 1 NOT NULL,
    requires_followup boolean DEFAULT false NOT NULL,
    followup_priority text,
    followup_notes text,
    source_system text,
    entered_by uuid,
    notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    confirmed_by_field_reader_at timestamp with time zone,
    confirmed_by_field_reader_id uuid,
    read_cycle_meter_id uuid,
    voided_from_invoice_id uuid,
    replaces_read_id uuid,
    CONSTRAINT meter_readings_access_status_check CHECK ((access_status = ANY (ARRAY['accessed'::text, 'locked_gate'::text, 'aggressive_dog'::text, 'meter_buried'::text, 'meter_obstructed'::text, 'meter_damaged'::text, 'meter_not_found'::text, 'unsafe_conditions'::text, 'no_access_permission'::text, 'key_required'::text, 'ami_offline'::text, 'other'::text]))),
    CONSTRAINT meter_readings_amr_read_status_check CHECK ((amr_read_status = ANY (ARRAY['success'::text, 'partial'::text, 'no_response'::text, 'invalid'::text, 'timeout'::text, 'manual_override'::text]))),
    CONSTRAINT meter_readings_consumption_unit_check CHECK ((consumption_unit = ANY (ARRAY['gallons'::text, 'ccf'::text, 'cubic_feet'::text, 'kgal'::text, 'kwh'::text, 'therms'::text, 'cubic_meters'::text, 'mcf'::text, 'kw'::text]))),
    CONSTRAINT meter_readings_estimation_reason_check CHECK ((estimation_reason = ANY (ARRAY['access_issue'::text, 'meter_malfunction'::text, 'new_meter_install'::text, 'ami_sync_failure'::text, 'prior_estimation_correction'::text, 'seasonal_closure'::text, 'historical_average'::text, 'same_period_prior_year'::text, 'weather_prevented_read'::text, 'other'::text]))),
    CONSTRAINT meter_readings_followup_priority_check CHECK ((followup_priority = ANY (ARRAY['low'::text, 'normal'::text, 'high'::text, 'urgent'::text]))),
    CONSTRAINT meter_readings_quality_flag_check CHECK ((quality_flag = ANY (ARRAY['normal'::text, 'high'::text, 'low'::text, 'zero'::text, 'negative'::text, 'suspect'::text, 'verified'::text]))),
    CONSTRAINT meter_readings_read_method_check CHECK ((read_method = ANY (ARRAY['manual'::text, 'ami'::text, 'amr'::text, 'estimated'::text, 'customer_reported'::text, 'rolled_back'::text, 'virtual'::text, 'photo_ai'::text]))),
    CONSTRAINT meter_readings_reading_purpose_check CHECK ((reading_purpose = ANY (ARRAY['regular_cycle'::text, 'final_read'::text, 'initial_read'::text, 'special_request'::text, 'audit'::text, 'turn_on'::text, 'turn_off'::text, 'dispute_recheck'::text, 'installation'::text, 'removal'::text]))),
    CONSTRAINT meter_readings_register_type_check CHECK ((register_type = ANY (ARRAY['main'::text, 'reverse_flow'::text, 'demand'::text, 'generation'::text, 'tou_peak'::text, 'tou_off_peak'::text, 'tou_shoulder'::text, 'secondary'::text, 'other'::text]))),
    CONSTRAINT meter_readings_status_check CHECK ((status = ANY (ARRAY['active'::text, 'disputed'::text, 'under_review'::text, 'replaced'::text, 'voided'::text]))),
    CONSTRAINT meter_readings_validation_status_check CHECK ((validation_status = ANY (ARRAY['pending_review'::text, 'reviewed_clean'::text, 'reviewed_with_exception'::text, 'approved'::text, 'released_to_billing'::text, 'locked'::text, 'void_released'::text, 'excluded'::text])))
);


--
-- Name: COLUMN meter_readings.is_service_transition; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.meter_readings.is_service_transition IS 'True when this read is the boundary between two customers (final read for outgoing, initial read for incoming). transition_outgoing_customer_id and transition_incoming_customer_id name the parties.';


--
-- Name: COLUMN meter_readings.validation_status; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.meter_readings.validation_status IS 'Workflow state for the read review pipeline. pending_review -> reviewed_clean | reviewed_with_exception | approved | excluded. approved -> released_to_billing -> locked (terminal for normal flow). locked -> void_released (only via void_invoice(); requires app.void_operation session var). void_released reads are available to correction billing runs. Corrections insert a NEW read with replaces_read_id pointing to the original.';


--
-- Name: COLUMN meter_readings.assigned_to_user_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.meter_readings.assigned_to_user_id IS 'Optional review assignment. Null = shared queue (any operator can grab). Populated = assigned to specific operator.';


--
-- Name: COLUMN meter_readings.billing_period_locked; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.meter_readings.billing_period_locked IS 'True once a billing run has consumed this reading. Locked readings are immutable except via dispute workflow (insert a NEW reading with replaces_reading_id pointing here, original status becomes replaced).';


--
-- Name: COLUMN meter_readings.triggers_correction_workflow; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.meter_readings.triggers_correction_workflow IS 'When true, billing engine generates a correction invoice on this read''s first billing pull. Set true for replacement reads that supersede locked ones; false for typo fixes on un-billed reads.';


--
-- Name: COLUMN meter_readings.confirmed_by_field_reader_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.meter_readings.confirmed_by_field_reader_at IS 'When a field reader confirmed an AI-extracted reading value. Populated only for read_method=photo_ai. Distinct from created_at because AI extraction may complete async after photo upload. Used for AI accuracy evaluation (compare AI-extracted vs. operator-corrected) and audit trail.';


--
-- Name: COLUMN meter_readings.confirmed_by_field_reader_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.meter_readings.confirmed_by_field_reader_id IS 'User who confirmed the photo_ai reading. Usually the same person who took the photo (taken_by on the linked meter_photos row), but may differ in handoff scenarios (one reader captures, another reviews the AI extraction).';


--
-- Name: COLUMN meter_readings.read_cycle_meter_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.meter_readings.read_cycle_meter_id IS 'Optional back-link to the read_cycle_meters row this reading satisfies. Populated when the reading was captured against an issued read sheet (manual entry, mobile photo+AI, or imported from a handheld). NULL for AMI-stream reads, ad-hoc final reads, and corrections.';


--
-- Name: COLUMN meter_readings.voided_from_invoice_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.meter_readings.voided_from_invoice_id IS 'Set during a void operation to preserve the invoice that originally locked this read, before locked_by_invoice_id is cleared. Enables full audit traversal: read -> voided invoice -> correction invoice.';


--
-- Name: COLUMN meter_readings.replaces_read_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.meter_readings.replaces_read_id IS 'When this read was inserted to correct a bad read (wrong_read void or dispute workflow), points to the original read it supersedes. That original read will be in void_released or disputed status. NULL on normal reads.';


--
-- Name: meters; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.meters (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id uuid NOT NULL,
    meter_number text NOT NULL,
    location_id uuid NOT NULL,
    rate_schedule_id uuid,
    service_type text NOT NULL,
    is_virtual boolean DEFAULT false NOT NULL,
    derives_from_meter_id uuid,
    manufacturer text,
    model text,
    serial_number text,
    size text,
    install_date date,
    removal_date date,
    warranty_expiration date,
    read_type text DEFAULT 'manual'::text NOT NULL,
    multiplier numeric(10,4) DEFAULT 1.0 NOT NULL,
    num_dials integer DEFAULT 6,
    ami_system text,
    ami_endpoint_id text,
    ami_api_config jsonb DEFAULT '{}'::jsonb,
    ami_last_sync_at timestamp with time zone,
    ami_sync_status text DEFAULT 'not_configured'::text,
    ami_sync_error text,
    meter_factor numeric(10,6),
    gas_btu_factor numeric(10,6),
    seal_number text,
    test_interval_months integer,
    last_test_date date,
    next_test_due_date date,
    last_test_result text,
    status text DEFAULT 'active'::text NOT NULL,
    start_date date DEFAULT CURRENT_DATE NOT NULL,
    end_date date,
    last_read_value numeric(14,2),
    last_read_date date,
    location_notes text,
    route_id uuid,
    route_sequence integer,
    replaces_meter_id uuid,
    swap_reason text,
    warehouse_location text,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    external_id text,
    external_id_source text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    estimation_blocked boolean DEFAULT false NOT NULL,
    estimation_blocked_reason text,
    estimation_blocked_set_at timestamp with time zone,
    estimation_blocked_set_by uuid,
    dial_count integer,
    CONSTRAINT meters_ami_sync_status_check CHECK ((ami_sync_status = ANY (ARRAY['not_configured'::text, 'active'::text, 'error'::text, 'paused'::text, 'not_configured'::text]))),
    CONSTRAINT meters_dial_count_check CHECK (((dial_count IS NULL) OR ((dial_count >= 3) AND (dial_count <= 9)))),
    CONSTRAINT meters_last_test_result_check CHECK ((last_test_result = ANY (ARRAY['passed'::text, 'failed'::text, 'conditional'::text, 'not_tested'::text]))),
    CONSTRAINT meters_read_type_check CHECK ((read_type = ANY (ARRAY['manual'::text, 'ami'::text, 'amr'::text, 'estimated'::text, 'virtual'::text]))),
    CONSTRAINT meters_service_type_check CHECK ((service_type = ANY (ARRAY['water'::text, 'sewer'::text, 'electric'::text, 'gas'::text, 'stormwater'::text, 'trash'::text, 'reclaimed_water'::text]))),
    CONSTRAINT meters_size_check CHECK ((size = ANY (ARRAY['5/8_inch'::text, '3/4_inch'::text, '1_inch'::text, '1.5_inch'::text, '2_inch'::text, '3_inch'::text, '4_inch'::text, '6_inch'::text, '8_inch'::text, '10_inch'::text, '12_inch'::text, 'other'::text]))),
    CONSTRAINT meters_status_check CHECK ((status = ANY (ARRAY['active'::text, 'inactive'::text, 'removed'::text, 'failed'::text, 'testing'::text]))),
    CONSTRAINT meters_swap_reason_check CHECK ((swap_reason = ANY (ARRAY['upgrade_size'::text, 'damage'::text, 'hardware_failure'::text, 'ami_upgrade'::text, 'tamper'::text, 'weather'::text, 'end_of_life'::text, 'customer_request'::text, 'accuracy_test_failure'::text, 'other'::text])))
);


--
-- Name: COLUMN meters.serial_number; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.meters.serial_number IS 'Manufacturer serial number. NOT unique within a tenant by design — Pattern B tenants will have multiple meter rows with the same serial across deployments. Use idx_meters_serial to find all rows representing a physical unit.';


--
-- Name: COLUMN meters.status; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.meters.status IS 'Lifecycle: active=currently deployed; inactive=temporarily not deployed (Pattern A reuse expected); testing=at calibration vendor; failed=mechanically dead, awaiting replacement; removed=terminal removal (no future reactivation expected, typical Pattern B). Convention: Pattern A tenants use inactive/testing for temporary states; Pattern B tenants use removed as final.';


--
-- Name: COLUMN meters.replaces_meter_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.meters.replaces_meter_id IS 'Pattern B chain: this meter row replaces the referenced predecessor. NULL for first-ever deployments and for Pattern A reactivations (which reuse the same row). Use to walk a physical unit''s deployment chain.';


--
-- Name: COLUMN meters.swap_reason; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.meters.swap_reason IS 'Reason this meter replaced its predecessor. Only meaningful when replaces_meter_id is set. Independent of removal_reason on the OLD meter (which describes the disposition of the unit being replaced).';


--
-- Name: COLUMN meters.warehouse_location; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.meters.warehouse_location IS 'Physical location when not deployed at a service_location. Free text — tenants'' warehouse systems vary wildly. Examples: "Bin A-12", "Vendor: Sensus / RMA #12345", "Field truck 4". Cleared when deployed.';


--
-- Name: COLUMN meters.estimation_blocked; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.meters.estimation_blocked IS 'Per-meter override that prevents Phase 2A estimation regardless of rate_schedules.allow_estimation. Use for meters under active dispute, fraud investigation, court order, or known-unstable usage patterns where estimation would mislead. When true, the meter is skipped (outcome=skipped_no_read) rather than estimated. Phase 7 surfaces these to the operator for manual read scheduling.';


--
-- Name: COLUMN meters.estimation_blocked_reason; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.meters.estimation_blocked_reason IS 'Required when estimation_blocked=true. Free-text explanation surfaced in operator UI and exception reports. Examples: "Meter under tamper investigation", "Court order #2025-0042", "Customer disputes historical baseline".';


--
-- Name: COLUMN meters.estimation_blocked_set_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.meters.estimation_blocked_set_at IS 'When the block was placed. Stamped automatically by trigger on flip to true. Cleared when block is removed.';


--
-- Name: COLUMN meters.estimation_blocked_set_by; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.meters.estimation_blocked_set_by IS 'User who placed the block. Populated from auth.uid(). NULL when set by system action (AI tamper detection, automated dispute workflow). Cleared when block is removed.';


--
-- Name: COLUMN meters.dial_count; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.meters.dial_count IS 'Number of dials on the physical meter face. Used by Phase 3 to compute the rollover ceiling (10 ^ dial_count). Common values: 4 (residential water), 5 (residential gas/electric), 6 (commercial), 7-8 (large commercial/industrial). NULL means rollover detection is disabled for this meter — Phase 3 will flag any negative delta as negative_consumption rather than attempting rollover correction.';


--
-- Name: payment_methods; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.payment_methods (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id uuid NOT NULL,
    customer_id uuid NOT NULL,
    provider text NOT NULL,
    provider_token text NOT NULL,
    method_type text NOT NULL,
    last_four text,
    card_brand text,
    expiry_month smallint,
    expiry_year smallint,
    bank_name text,
    account_type text,
    holder_name text,
    nickname text,
    is_default boolean DEFAULT false NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    verified_at timestamp with time zone,
    last_used_at timestamp with time zone,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT payment_methods_account_type_check CHECK ((account_type = ANY (ARRAY['checking'::text, 'savings'::text, 'business_checking'::text, 'business_savings'::text]))),
    CONSTRAINT payment_methods_expiry_month_check CHECK (((expiry_month >= 1) AND (expiry_month <= 12))),
    CONSTRAINT payment_methods_method_type_check CHECK ((method_type = ANY (ARRAY['credit_card'::text, 'debit_card'::text, 'ach'::text, 'bank_account'::text])))
);


--
-- Name: TABLE payment_methods; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.payment_methods IS 'Tokenized payment instruments per customer. The provider holds the sensitive data; we hold only the token and display-safe metadata.';


--
-- Name: payments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.payments (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id uuid NOT NULL,
    payment_number text NOT NULL,
    customer_id uuid NOT NULL,
    payment_date date NOT NULL,
    amount numeric(12,2) NOT NULL,
    payment_method text NOT NULL,
    payment_method_id uuid,
    channel text DEFAULT 'walk_in'::text NOT NULL,
    source_system text DEFAULT 'internal'::text NOT NULL,
    reference_number text,
    provider_transaction_id text,
    provider_authorization_code text,
    check_number text,
    check_date date,
    check_bank_name text,
    status text DEFAULT 'posted'::text NOT NULL,
    applied_amount numeric(12,2) DEFAULT 0 NOT NULL,
    unapplied_amount numeric(12,2) DEFAULT 0 NOT NULL,
    is_deposit boolean DEFAULT false NOT NULL,
    deposit_status text,
    nsf_date date,
    nsf_reason text,
    nsf_fee_charge_id uuid,
    nsf_original_payment_id uuid,
    refunds_payment_id uuid,
    refund_reason text,
    reversed_at timestamp with time zone,
    reversed_by uuid,
    reversed_reason text,
    notes text,
    received_by uuid,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT payments_channel_check CHECK ((channel = ANY (ARRAY['portal'::text, 'mobile_app'::text, 'agent_phone'::text, 'ivr'::text, 'walk_in'::text, 'mail'::text, 'auto_pay'::text, 'batch_file'::text, 'api'::text, 'lockbox'::text]))),
    CONSTRAINT payments_deposit_status_check CHECK ((deposit_status = ANY (ARRAY['held'::text, 'partial_applied'::text, 'applied'::text, 'refunded'::text]))),
    CONSTRAINT payments_payment_method_check CHECK ((payment_method = ANY (ARRAY['cash'::text, 'check'::text, 'ach'::text, 'credit_card'::text, 'debit_card'::text, 'money_order'::text, 'online'::text, 'auto_pay'::text, 'write_off'::text, 'refund'::text, 'wire'::text, 'other'::text]))),
    CONSTRAINT payments_source_system_check CHECK ((source_system = ANY (ARRAY['internal'::text, 'paymentus_webhook'::text, 'stripe_webhook'::text, 'bank_lockbox'::text, 'imported'::text, 'other_webhook'::text]))),
    CONSTRAINT payments_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'posted'::text, 'nsf'::text, 'reversed'::text, 'refunded'::text, 'voided'::text])))
);


--
-- Name: COLUMN payments.channel; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.payments.channel IS 'How the payment was captured: portal, mobile_app, agent_phone, ivr, walk_in, mail, auto_pay, batch_file, api, lockbox. Distinct from payment_method (cash/check/card).';


--
-- Name: COLUMN payments.source_system; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.payments.source_system IS 'Which system created this payment record. internal=captured directly; paymentus_webhook/stripe_webhook=received via provider notification; bank_lockbox=file import; imported=data migration.';


--
-- Name: COLUMN payments.is_deposit; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.payments.is_deposit IS 'True if this payment is a security deposit held against final billing (refundable). Deposits are tracked separately in deposit_status.';


--
-- Name: COLUMN payments.nsf_original_payment_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.payments.nsf_original_payment_id IS 'For replacement payments: points at the original bounced payment this one replaces.';


--
-- Name: payment_health_statistics; Type: MATERIALIZED VIEW; Schema: public; Owner: -
--

CREATE MATERIALIZED VIEW public.payment_health_statistics AS
 WITH payment_rollup AS (
         SELECT p.customer_id,
            count(*) FILTER (WHERE (p.payment_date >= (CURRENT_DATE - '1 year'::interval))) AS payments_12mo,
            count(*) FILTER (WHERE ((p.status = 'nsf'::text) AND (p.nsf_date >= (CURRENT_DATE - '1 year'::interval)))) AS nsf_count_12mo,
            count(*) FILTER (WHERE ((p.status = 'nsf'::text) AND (p.nsf_date >= (CURRENT_DATE - '90 days'::interval)))) AS nsf_count_90d,
            max(p.nsf_date) AS last_nsf_date,
            avg(p.amount) FILTER (WHERE ((p.status = 'posted'::text) AND (p.payment_date >= (CURRENT_DATE - '1 year'::interval)))) AS avg_payment_amount_12mo,
            sum(p.amount) FILTER (WHERE ((p.status = 'posted'::text) AND (p.payment_date >= (CURRENT_DATE - '1 year'::interval)))) AS total_paid_12mo,
            max(p.payment_date) AS last_payment_date,
            max(p.payment_date) FILTER (WHERE (p.channel = 'auto_pay'::text)) AS last_auto_pay_date
           FROM public.payments p
          WHERE (p.payment_date >= (CURRENT_DATE - '2 years'::interval))
          GROUP BY p.customer_id
        ), auto_pay_health AS (
         SELECT aps.customer_id,
            aps.enabled AS auto_pay_enabled,
            aps.consecutive_failures AS auto_pay_consecutive_failures,
            aps.last_run_status AS auto_pay_last_status,
            aps.next_run_at AS auto_pay_next_run,
            aps.payment_method_id AS auto_pay_method_id,
            aps.pause_until AS auto_pay_paused_until
           FROM public.auto_pay_settings aps
        ), method_expiry AS (
         SELECT pm.customer_id,
            count(*) FILTER (WHERE (pm.is_active = true)) AS active_method_count,
            count(*) FILTER (WHERE ((pm.is_active = true) AND (pm.method_type = ANY (ARRAY['credit_card'::text, 'debit_card'::text])) AND (make_date((pm.expiry_year)::integer, (pm.expiry_month)::integer, 1) <= (CURRENT_DATE + '60 days'::interval)))) AS methods_expiring_60d,
            min(make_date((pm.expiry_year)::integer, (pm.expiry_month)::integer, 1)) FILTER (WHERE ((pm.is_active = true) AND (pm.method_type = ANY (ARRAY['credit_card'::text, 'debit_card'::text])))) AS earliest_method_expiry
           FROM public.payment_methods pm
          GROUP BY pm.customer_id
        )
 SELECT c.tenant_id,
    c.id AS customer_id,
    c.customer_number,
    c.customer_type,
    c.status AS customer_status,
    COALESCE(pr.payments_12mo, (0)::bigint) AS payments_12mo,
    COALESCE(pr.avg_payment_amount_12mo, (0)::numeric) AS avg_payment_amount_12mo,
    COALESCE(pr.total_paid_12mo, (0)::numeric) AS total_paid_12mo,
    pr.last_payment_date,
    COALESCE(pr.nsf_count_12mo, (0)::bigint) AS nsf_count_12mo,
    COALESCE(pr.nsf_count_90d, (0)::bigint) AS nsf_count_90d,
    pr.last_nsf_date,
    (COALESCE(pr.nsf_count_90d, (0)::bigint) >= 2) AS multiple_nsf_pattern_90d,
    (COALESCE(pr.nsf_count_12mo, (0)::bigint) >= 3) AS multiple_nsf_pattern_12mo,
    COALESCE(aph.auto_pay_enabled, false) AS auto_pay_enabled,
    COALESCE(aph.auto_pay_consecutive_failures, 0) AS auto_pay_consecutive_failures,
    aph.auto_pay_last_status,
    aph.auto_pay_next_run,
    pr.last_auto_pay_date,
    (COALESCE(aph.auto_pay_consecutive_failures, 0) >= 2) AS auto_pay_failure_streak,
    COALESCE(me.active_method_count, (0)::bigint) AS active_method_count,
    COALESCE(me.methods_expiring_60d, (0)::bigint) AS methods_expiring_60d,
    me.earliest_method_expiry,
    (COALESCE(me.methods_expiring_60d, (0)::bigint) > 0) AS payment_method_expiring_soon,
    (CURRENT_DATE - pr.last_payment_date) AS days_since_last_payment
   FROM (((public.customers c
     LEFT JOIN payment_rollup pr ON ((pr.customer_id = c.id)))
     LEFT JOIN auto_pay_health aph ON ((aph.customer_id = c.id)))
     LEFT JOIN method_expiry me ON ((me.customer_id = c.id)))
  WHERE (c.status = ANY (ARRAY['active'::text, 'final_billed'::text]))
  WITH NO DATA;


--
-- Name: payment_provider_logs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.payment_provider_logs (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id uuid NOT NULL,
    provider text NOT NULL,
    endpoint text NOT NULL,
    http_method text,
    request_body text,
    response_body text,
    http_status integer,
    is_error boolean DEFAULT false NOT NULL,
    error_message text,
    error_code text,
    customer_id uuid,
    payment_id uuid,
    payment_method_id uuid,
    correlation_id text,
    operation_type text,
    duration_ms integer,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT payment_provider_logs_http_method_check CHECK ((http_method = ANY (ARRAY['GET'::text, 'POST'::text, 'PUT'::text, 'DELETE'::text, 'PATCH'::text]))),
    CONSTRAINT payment_provider_logs_operation_type_check CHECK ((operation_type = ANY (ARRAY['tokenize'::text, 'charge'::text, 'refund'::text, 'void'::text, 'capture'::text, 'webhook_received'::text, 'status_check'::text, 'method_list'::text, 'method_delete'::text])))
);


--
-- Name: TABLE payment_provider_logs; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.payment_provider_logs IS 'Immutable API audit trail with payment providers. Request/response bodies must have sensitive data redacted before insert.';


--
-- Name: rate_item_dependencies; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.rate_item_dependencies (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id uuid NOT NULL,
    rate_schedule_id uuid NOT NULL,
    dependent_rate_item_id uuid NOT NULL,
    base_rate_item_id uuid NOT NULL,
    notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT rate_item_dependencies_check CHECK ((dependent_rate_item_id <> base_rate_item_id))
);


--
-- Name: rate_item_history; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.rate_item_history (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id uuid NOT NULL,
    rate_item_id uuid NOT NULL,
    effective_date date NOT NULL,
    end_date date,
    rate_value numeric(14,6) NOT NULL,
    rate_unit text,
    changed_by uuid,
    change_reason text,
    regulatory_reference text,
    notes text,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: rate_item_history_archive; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.rate_item_history_archive (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id uuid NOT NULL,
    rate_item_id uuid NOT NULL,
    effective_date date NOT NULL,
    end_date date,
    rate_value numeric(14,6) NOT NULL,
    rate_unit text,
    changed_by uuid,
    change_reason text,
    regulatory_reference text,
    notes text,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: rate_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.rate_items (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id uuid NOT NULL,
    item_code text NOT NULL,
    item_name text NOT NULL,
    description text,
    service_type text NOT NULL,
    calculation_type text NOT NULL,
    current_rate numeric(14,6),
    rate_unit text,
    active_months integer[] DEFAULT '{1,2,3,4,5,6,7,8,9,10,11,12}'::integer[] NOT NULL,
    applies_to_customer_types text[] DEFAULT '{residential,commercial,industrial,government,wholesale}'::text[] NOT NULL,
    update_frequency text,
    calc_owner text,
    is_taxable_default boolean DEFAULT false NOT NULL,
    is_a_tax boolean DEFAULT false NOT NULL,
    display_name text,
    display_group text,
    status text DEFAULT 'active'::text NOT NULL,
    effective_date date DEFAULT CURRENT_DATE NOT NULL,
    expiry_date date,
    notes text,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    tier_config jsonb,
    annual_billing_anchor integer,
    CONSTRAINT rate_items_annual_billing_anchor_check CHECK (((annual_billing_anchor IS NULL) OR ((annual_billing_anchor >= 1) AND (annual_billing_anchor <= 12)))),
    CONSTRAINT rate_items_calc_owner_check CHECK ((calc_owner = ANY (ARRAY['regulatory'::text, 'gas_marketing'::text, 'accounting'::text, 'finance'::text, 'strategic_finance'::text, 'state_of_tx'::text, 'external'::text, 'operations'::text, 'other'::text]))),
    CONSTRAINT rate_items_calculation_type_check CHECK ((calculation_type = ANY (ARRAY['fixed_monthly'::text, 'fixed_annual'::text, 'per_unit_usage'::text, 'percentage_of_bill'::text, 'percentage_of_charges'::text, 'usage_modifier'::text, 'tiered_usage'::text, 'formula'::text]))),
    CONSTRAINT rate_items_display_group_check CHECK ((display_group = ANY (ARRAY['base_charges'::text, 'usage_charges'::text, 'riders'::text, 'taxes_fees'::text, 'adjustments'::text, 'other'::text]))),
    CONSTRAINT rate_items_rate_unit_check CHECK ((rate_unit = ANY (ARRAY['flat'::text, 'per_month'::text, 'per_year'::text, 'per_day'::text, 'per_gallon'::text, 'per_kgal'::text, 'per_ccf'::text, 'per_mcf'::text, 'per_therm'::text, 'per_kwh'::text, 'per_cubic_meter'::text, 'percent'::text, 'decimal'::text]))),
    CONSTRAINT rate_items_service_type_check CHECK ((service_type = ANY (ARRAY['water'::text, 'sewer'::text, 'electric'::text, 'gas'::text, 'stormwater'::text, 'trash'::text, 'reclaimed_water'::text, 'all'::text]))),
    CONSTRAINT rate_items_status_check CHECK ((status = ANY (ARRAY['active'::text, 'paused'::text, 'archived'::text]))),
    CONSTRAINT rate_items_tier_config_required_for_tiered CHECK (((calculation_type <> 'tiered_usage'::text) OR ((tier_config IS NOT NULL) AND (jsonb_typeof((tier_config -> 'tiers'::text)) = 'array'::text)))),
    CONSTRAINT rate_items_update_frequency_check CHECK ((update_frequency = ANY (ARRAY['never'::text, 'monthly'::text, 'quarterly'::text, 'annually'::text, 'on_rate_case'::text, 'as_needed'::text])))
);


--
-- Name: COLUMN rate_items.calculation_type; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.rate_items.calculation_type IS 'How this rate component is calculated:
     fixed_monthly        — flat dollar per month (Customer Charge, GRIP, Pipeline Safety)
     fixed_annual         — flat dollar once per year, anchor month per annual_billing_anchor
     per_unit_usage       — dollar per consumption unit (GCA, CRRC, base commodity rate)
     percentage_of_bill   — percentage of running subtotal (Sales Tax, Franchise Tax)
     percentage_of_charges— percentage of specific base items (per rate_item_dependencies)
     usage_modifier       — modifies consumption value before usage charges run
                            (Gas Temp Factor: consumption = delta * multiplier * meter_factor * temp_factor)
                            Multiplicative chain. Multiple modifiers in display_order all multiply.
     tiered_usage         — tier brackets defined in tier_config JSONB
     formula              — escape hatch (WNA-style adjustments, operator-entered monthly)';


--
-- Name: COLUMN rate_items.tier_config; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.rate_items.tier_config IS 'Tier bracket configuration for calculation_type=tiered_usage. JSONB shape: {"tiers":[{"label":string,"floor":number,"ceiling":number|null,"rate":number}, ...]}. Tier 1 floor must be 0; top tier ceiling is null (unbounded); tiers must be contiguous and non-overlapping. Required when calculation_type=tiered_usage; ignored otherwise.';


--
-- Name: COLUMN rate_items.annual_billing_anchor; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.rate_items.annual_billing_anchor IS 'For fixed_annual items: which calendar month to bill in. NULL means "first invoice of the calendar year" (Phase 4 checks if this rate_item already appears on any invoice issued in the current year for this meter; if not, it bills now). 1-12 means "bill only when period_end falls in this month". Examples: a January fee uses 1; a renewal fee that bills with the customer''s anniversary cycle uses NULL.';


--
-- Name: rate_schedule_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.rate_schedule_items (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id uuid NOT NULL,
    rate_schedule_id uuid NOT NULL,
    rate_item_id uuid NOT NULL,
    rate_override numeric(14,6),
    rate_unit_override text,
    active_months_override integer[],
    is_taxable_override boolean,
    display_order integer DEFAULT 0 NOT NULL,
    display_name_override text,
    effective_date date DEFAULT CURRENT_DATE NOT NULL,
    expiry_date date,
    status text DEFAULT 'active'::text NOT NULL,
    notes text,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT rate_schedule_items_status_check CHECK ((status = ANY (ARRAY['active'::text, 'paused'::text, 'archived'::text])))
);


--
-- Name: rate_schedules; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.rate_schedules (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id uuid NOT NULL,
    code text NOT NULL,
    name text NOT NULL,
    description text,
    service_type text NOT NULL,
    customer_type text NOT NULL,
    wna_zone_id uuid,
    franchise_city text,
    regulatory_authority text,
    tariff_number text,
    tariff_document_url text,
    regulatory_code text,
    effective_date date NOT NULL,
    expiry_date date,
    status text DEFAULT 'active'::text NOT NULL,
    sewer_calc_method text,
    sewer_cap_gallons numeric(12,2),
    winter_avg_months integer[],
    gas_meter_factor_required boolean DEFAULT false NOT NULL,
    gas_usage_formula text,
    bill_section_label text,
    partial_period_policy text,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    allow_estimation boolean DEFAULT true NOT NULL,
    estimation_method text,
    sewer_percent_of_water numeric(5,4),
    partial_period_policy_override text,
    prorate_tier_breakpoints boolean DEFAULT false NOT NULL,
    minimum_bill_amount numeric(12,2),
    CONSTRAINT rate_schedules_customer_type_check CHECK ((customer_type = ANY (ARRAY['residential'::text, 'commercial'::text, 'small_commercial'::text, 'large_commercial'::text, 'industrial'::text, 'government'::text, 'wholesale'::text]))),
    CONSTRAINT rate_schedules_estimation_method_check CHECK (((estimation_method IS NULL) OR (estimation_method = ANY (ARRAY['historical_average_3mo'::text, 'historical_average_12mo'::text, 'same_period_prior_year'::text, 'last_actual_reading'::text, 'zero'::text])))),
    CONSTRAINT rate_schedules_gas_usage_formula_check CHECK ((gas_usage_formula = ANY (ARRAY['standard'::text, 'with_meter_factor'::text, 'with_temp_factor'::text]))),
    CONSTRAINT rate_schedules_minimum_bill_amount_check CHECK (((minimum_bill_amount IS NULL) OR (minimum_bill_amount >= (0)::numeric))),
    CONSTRAINT rate_schedules_partial_period_policy_check CHECK ((partial_period_policy = ANY (ARRAY['prorated'::text, 'charge_both'::text, 'period_holder'::text]))),
    CONSTRAINT rate_schedules_partial_period_policy_override_check CHECK (((partial_period_policy_override IS NULL) OR (partial_period_policy_override = ANY (ARRAY['prorated'::text, 'charge_both'::text, 'period_holder'::text])))),
    CONSTRAINT rate_schedules_service_type_check CHECK ((service_type = ANY (ARRAY['water'::text, 'sewer'::text, 'electric'::text, 'gas'::text, 'stormwater'::text, 'trash'::text, 'reclaimed_water'::text]))),
    CONSTRAINT rate_schedules_sewer_calc_method_check CHECK ((sewer_calc_method = ANY (ARRAY['flat'::text, 'metered'::text, 'winter_avg'::text, 'percent_of_water'::text]))),
    CONSTRAINT rate_schedules_sewer_percent_of_water_check CHECK (((sewer_percent_of_water IS NULL) OR ((sewer_percent_of_water > (0)::numeric) AND (sewer_percent_of_water <= (1)::numeric)))),
    CONSTRAINT rate_schedules_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'active'::text, 'expired'::text, 'archived'::text]))),
    CONSTRAINT rate_schedules_winter_months_valid CHECK (((winter_avg_months IS NULL) OR (((array_length(winter_avg_months, 1) >= 1) AND (array_length(winter_avg_months, 1) <= 12)) AND (winter_avg_months <@ ARRAY[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]))))
);


--
-- Name: COLUMN rate_schedules.winter_avg_months; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.rate_schedules.winter_avg_months IS 'Calendar months (1-12) treated as winter for sewer winter-average calculations. Typical: {12,1,2} for Texas. During these months, sewer_calc_method=winter_avg uses actual current consumption (and contributes to next year''s average). During other months, sewer billable volume comes from the cached customer_winter_averages row.';


--
-- Name: COLUMN rate_schedules.gas_usage_formula; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.rate_schedules.gas_usage_formula IS 'Drives Phase 3 gas consumption calculation:
             standard          — consumption = (current - previous) * multiplier
             with_meter_factor — consumption = (current - previous) * multiplier * meter_factor
             with_temp_factor  — consumption = (current - previous) * multiplier * meter_factor * seasonal_temp_factor
                                  where seasonal_temp_factor is the product of all rate_items with
                                  calculation_type=usage_modifier on this rate schedule, snapped to period_end
                                  via rate_item_history_archive.
             Result rounded to unit-specific precision (MCF/CCF/therms = 1 decimal; gallons/kWh = whole).';


--
-- Name: COLUMN rate_schedules.partial_period_policy; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.rate_schedules.partial_period_policy IS 'Per-plan override for partial-period fixed charge handling. NULL means inherit tenants.default_partial_period_policy. Values: prorated, charge_both, period_holder.';


--
-- Name: COLUMN rate_schedules.allow_estimation; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.rate_schedules.allow_estimation IS 'Tariff-level permission for system-generated estimates when no actual read is available. Default true (most tariffs allow estimation up to a streak cap). Set false for tariffs that require actual reads every cycle (commercial high-value, regulatory disputes, court orders).';


--
-- Name: COLUMN rate_schedules.estimation_method; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.rate_schedules.estimation_method IS 'Method used by Phase 2A to generate the estimated consumption value. NULL means no method configured (Phase 2A falls back to platform default by service_type: gas -> same_period_prior_year, water/electric/sewer -> historical_average_3mo). Override per rate schedule when the default does not match the customer pattern.';


--
-- Name: COLUMN rate_schedules.sewer_percent_of_water; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.rate_schedules.sewer_percent_of_water IS 'When sewer_calc_method=percent_of_water, multiply the linked water meter consumption by this value to derive sewer billable volume. Example: 0.85 means sewer = 85 percent of water. Combine with sewer_cap_gallons to put a hard upper bound on the result.';


--
-- Name: COLUMN rate_schedules.partial_period_policy_override; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.rate_schedules.partial_period_policy_override IS 'Per-rate-schedule override of tenants.default_partial_period_policy. NULL means use tenant default. Values: prorated (multiply fixed charges by days_covered/days_in_period), charge_both (both outgoing and incoming customer pay full fixed charges), period_holder (whichever customer holds the account at period_end pays the full fixed charges). Most utilities use prorated.';


--
-- Name: COLUMN rate_schedules.prorate_tier_breakpoints; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.rate_schedules.prorate_tier_breakpoints IS 'When true AND partial period applies, Phase 4 scales tier ceilings by days_covered/days_in_period before allocating consumption to tiers. Prevents short-period customers from being pushed into higher tiers unfairly. Example: customer billed for 12 days of a 30-day cycle, tier 1 ceiling 2000 gal becomes 800 gal (2000 * 12/30). Default false; most utilities accept the natural tier behavior for partial periods.';


--
-- Name: COLUMN rate_schedules.minimum_bill_amount; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.rate_schedules.minimum_bill_amount IS 'When set, Phase 6 enforces a minimum charge for meters on this rate schedule. After all rate components run, if the meter''s service-type subtotal (excluding tax) is below this amount, a minimum_bill_adjustment line is added for the shortfall. Common in commercial tariffs ($X/month minimum regardless of usage). NULL means no minimum. Applied per service type on combined utility bills (water minimum independent of gas minimum).';


--
-- Name: read_cycle_instances; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.read_cycle_instances (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id uuid NOT NULL,
    billing_cycle_id uuid NOT NULL,
    period text NOT NULL,
    period_start date NOT NULL,
    period_end date NOT NULL,
    read_window_start date NOT NULL,
    read_window_end date NOT NULL,
    status text DEFAULT 'draft'::text NOT NULL,
    issued_at timestamp with time zone,
    issued_by uuid,
    reads_complete_at timestamp with time zone,
    completed_by uuid,
    billing_run_id uuid,
    total_meters_locked integer DEFAULT 0 NOT NULL,
    total_reads_captured integer DEFAULT 0 NOT NULL,
    total_reads_approved integer DEFAULT 0 NOT NULL,
    total_meters_skipped integer DEFAULT 0 NOT NULL,
    reader_overrides jsonb DEFAULT '{}'::jsonb NOT NULL,
    notes text,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT read_cycle_instances_check CHECK ((read_window_end >= read_window_start)),
    CONSTRAINT read_cycle_instances_check1 CHECK ((period_end >= period_start)),
    CONSTRAINT read_cycle_instances_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'issued'::text, 'reading'::text, 'reads_complete'::text, 'billed'::text, 'cancelled'::text])))
);


--
-- Name: TABLE read_cycle_instances; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.read_cycle_instances IS 'One row per specific reading event for a billing_cycle in a given period. Tracks the lifecycle from sheet issuance through reads_complete to billed. The locked meter set lives in the companion table read_cycle_meters. AMI-only cycles bypass this entirely (see billing_cycles.requires_read_cycle).';


--
-- Name: COLUMN read_cycle_instances.status; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.read_cycle_instances.status IS 'Lifecycle: draft (editable) -> issued (locked, readers begin) -> reading (captures arriving) -> reads_complete (ready for billing) -> billed (consumed by billing_run). cancelled is the abandon path.';


--
-- Name: COLUMN read_cycle_instances.reader_overrides; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.read_cycle_instances.reader_overrides IS 'Per-route reader assignment override for THIS instance. JSONB map of read_route_id -> user_id. Use when the default assigned_to_user_id on the route is unavailable for this cycle (e.g., regular reader is out, substitute covering). Absent keys fall back to the route default.';


--
-- Name: read_cycle_meters; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.read_cycle_meters (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id uuid NOT NULL,
    read_cycle_instance_id uuid NOT NULL,
    meter_id uuid NOT NULL,
    read_route_id uuid,
    assigned_reader_user_id uuid,
    assigned_reader_name text,
    read_status text DEFAULT 'pending'::text NOT NULL,
    skip_reason text,
    expected_read_date date,
    captured_at timestamp with time zone,
    captured_reading_id uuid,
    sequence_in_route integer,
    notes text,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT read_cycle_meters_read_status_check CHECK ((read_status = ANY (ARRAY['pending'::text, 'reading'::text, 'captured'::text, 'validated'::text, 'approved'::text, 'skipped'::text, 'cant_read'::text])))
);


--
-- Name: TABLE read_cycle_meters; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.read_cycle_meters IS 'The locked meter set for a read_cycle_instance, one row per meter on the issued sheet. Tracks per-meter progress through the read window. Drives the mobile app reader queue, route sheet exports, and the billing run candidate set. The route and reader assignments are snapshots taken at sheet issuance — even if the meter is reassigned later, this row remembers what was on the sheet.';


--
-- Name: COLUMN read_cycle_meters.read_status; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.read_cycle_meters.read_status IS 'Lifecycle: pending -> reading -> captured -> validated -> approved (happy path). skipped is operator decision (deliberate exclusion); cant_read is field-side (locked gate, dog, broken meter).';


--
-- Name: read_routes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.read_routes (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id uuid NOT NULL,
    route_code text NOT NULL,
    route_name text NOT NULL,
    description text,
    read_frequency text DEFAULT 'monthly'::text,
    typical_read_day integer,
    estimated_meter_count integer,
    estimated_time_hours numeric(4,1),
    assigned_to text,
    default_billing_cycle_id uuid,
    status text DEFAULT 'active'::text NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    assigned_to_user_id uuid,
    CONSTRAINT read_routes_read_frequency_check CHECK ((read_frequency = ANY (ARRAY['daily'::text, 'weekly'::text, 'biweekly'::text, 'monthly'::text, 'bimonthly'::text, 'quarterly'::text]))),
    CONSTRAINT read_routes_status_check CHECK ((status = ANY (ARRAY['active'::text, 'inactive'::text, 'archived'::text])))
);


--
-- Name: TABLE read_routes; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.read_routes IS 'Physical/geographic groupings of meters for field reading sequence. Distinct from billing_cycles (which group by billing schedule). Often aligned 1:1 with cycles via default_billing_cycle_id.';


--
-- Name: COLUMN read_routes.default_billing_cycle_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.read_routes.default_billing_cycle_id IS 'Typical billing cycle this route aligns with. Informational; meters may override individually via service_locations.billing_cycle_id.';


--
-- Name: COLUMN read_routes.assigned_to_user_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.read_routes.assigned_to_user_id IS 'Default reader for this route as a platform user FK. Use this when the reader has a system account. The legacy assigned_to TEXT field stays for cases where the reader does not have a login (contractor, paper-only operation). Per-cycle overrides live in read_cycle_instances.reader_overrides.';


--
-- Name: service_locations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.service_locations (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id uuid NOT NULL,
    customer_id uuid NOT NULL,
    community_id uuid,
    location_number text NOT NULL,
    address_line1 text NOT NULL,
    address_line2 text,
    city text NOT NULL,
    county text,
    state text NOT NULL,
    zip text NOT NULL,
    latitude numeric(10,7),
    longitude numeric(10,7),
    parcel_id text,
    location_type text DEFAULT 'residential_single_family'::text,
    status text DEFAULT 'active'::text NOT NULL,
    inside_city_limits boolean DEFAULT true NOT NULL,
    franchise_city text,
    billing_cycle text DEFAULT 'monthly'::text NOT NULL,
    budget_billing boolean DEFAULT false NOT NULL,
    budget_amount numeric(12,2),
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    external_id text,
    external_id_source text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    billing_cycle_id uuid,
    CONSTRAINT service_locations_billing_cycle_check CHECK ((billing_cycle = ANY (ARRAY['monthly'::text, 'bimonthly'::text, 'quarterly'::text]))),
    CONSTRAINT service_locations_status_check CHECK ((status = ANY (ARRAY['active'::text, 'inactive'::text, 'demolished'::text])))
);


--
-- Name: COLUMN service_locations.billing_cycle_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.service_locations.billing_cycle_id IS 'Which billing cycle this location belongs to. Determines read date, bill date, and due date.';


--
-- Name: service_orders; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.service_orders (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id uuid NOT NULL,
    order_number text NOT NULL,
    order_type text NOT NULL,
    status text DEFAULT 'open'::text NOT NULL,
    priority text DEFAULT 'normal'::text NOT NULL,
    customer_id uuid,
    location_id uuid,
    meter_id uuid,
    description text NOT NULL,
    completion_notes text,
    external_order_id text,
    external_system text,
    requested_date date,
    scheduled_date date,
    dispatched_at timestamp with time zone,
    started_at timestamp with time zone,
    completed_at timestamp with time zone,
    billing_applied_at timestamp with time zone,
    assigned_to text,
    cancelled_at timestamp with time zone,
    cancelled_by uuid,
    cancellation_reason text,
    parent_order_id uuid,
    triggered_adhoc_charge_ids uuid[],
    triggered_reading_ids uuid[],
    triggered_new_meter_id uuid,
    triggered_replaced_meter_id uuid,
    created_by_ai boolean DEFAULT false NOT NULL,
    ai_audit_id uuid,
    created_by_suggestion_id uuid,
    billing_action_suggestion_id uuid,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT service_orders_check CHECK (((order_type <> ALL (ARRAY['new_connect'::text, 'reconnect'::text, 'disconnect'::text, 'transfer'::text])) OR ((customer_id IS NOT NULL) AND (location_id IS NOT NULL)))),
    CONSTRAINT service_orders_check1 CHECK (((order_type <> ALL (ARRAY['meter_install'::text, 'meter_replace'::text, 'meter_change_out'::text, 'meter_test'::text, 'meter_reread'::text, 'meter_test_failed_replace'::text])) OR (meter_id IS NOT NULL))),
    CONSTRAINT service_orders_check2 CHECK (((order_type <> ALL (ARRAY['leak_check'::text, 'pressure_test'::text, 'backflow_test'::text, 'inspection'::text, 'seasonal_turn_on'::text, 'seasonal_turn_off'::text])) OR (location_id IS NOT NULL))),
    CONSTRAINT service_orders_order_type_check CHECK ((order_type = ANY (ARRAY['new_connect'::text, 'disconnect'::text, 'reconnect'::text, 'transfer'::text, 'meter_install'::text, 'meter_replace'::text, 'meter_change_out'::text, 'meter_test'::text, 'meter_reread'::text, 'meter_test_failed_replace'::text, 'final_read'::text, 'leak_check'::text, 'pressure_test'::text, 'backflow_test'::text, 'inspection'::text, 'tamper_response'::text, 'damage_repair'::text, 'customer_complaint'::text, 'seasonal_turn_on'::text, 'seasonal_turn_off'::text, 'adjustment'::text, 'other'::text]))),
    CONSTRAINT service_orders_priority_check CHECK ((priority = ANY (ARRAY['low'::text, 'normal'::text, 'high'::text, 'emergency'::text]))),
    CONSTRAINT service_orders_status_check CHECK ((status = ANY (ARRAY['open'::text, 'scheduled'::text, 'dispatched'::text, 'in_progress'::text, 'on_hold'::text, 'awaiting_billing_action'::text, 'completed'::text, 'requires_followup'::text, 'cancelled'::text, 'superseded'::text])))
);


--
-- Name: TABLE service_orders; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.service_orders IS 'Billing-system records of field events. NOT a field service system. Records what was done and links to the billing consequences (adhoc charges, meter swaps, service transitions). Hold-for-review pattern: completion does NOT auto-apply billing consequences; operator reviews and approves (manually or via AI suggestion) before status moves to completed.';


--
-- Name: COLUMN service_orders.status; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.service_orders.status IS 'Lifecycle. awaiting_billing_action is the critical state: field work is done but operator must explicitly trigger billing consequences (adhoc charges, swap workflow, transition reads). status=completed means consequences are applied AND billing_applied_at is set.';


--
-- Name: COLUMN service_orders.external_order_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.service_orders.external_order_id IS 'Work order ID from the tenant''s field service software (ServiceTitan, FieldEdge, etc.). Lets the operator correlate this order back to the source system.';


--
-- Name: COLUMN service_orders.completed_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.service_orders.completed_at IS 'When the FIELD work finished. Distinct from billing_applied_at, which is when operator approved and the billing system applied consequences. The gap between these timestamps measures operator review backlog.';


--
-- Name: COLUMN service_orders.billing_applied_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.service_orders.billing_applied_at IS 'When operator approved the order and the billing consequences (adhoc charges, meter swaps, transition reads) were applied to the system. After this, status moves to completed.';


--
-- Name: COLUMN service_orders.triggered_adhoc_charge_ids; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.service_orders.triggered_adhoc_charge_ids IS 'Array of adhoc_charges.id values created when this order''s billing consequences were applied. Empty until billing_applied_at is set.';


--
-- Name: tenant_sequences; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tenant_sequences (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id uuid NOT NULL,
    sequence_type text NOT NULL,
    prefix text DEFAULT ''::text NOT NULL,
    current_value bigint DEFAULT 0 NOT NULL,
    pad_length integer DEFAULT 6 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: tenants; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tenants (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    name text NOT NULL,
    slug text NOT NULL,
    status text DEFAULT 'active'::text NOT NULL,
    subscription_tier text DEFAULT 'starter'::text NOT NULL,
    settings jsonb DEFAULT '{}'::jsonb NOT NULL,
    billing_email text,
    phone text,
    address_line1 text,
    address_line2 text,
    city text,
    state text,
    zip text,
    logo_url text,
    default_partial_period_policy text DEFAULT 'prorated'::text NOT NULL,
    payment_allocation_strategy text DEFAULT 'oldest_first'::text NOT NULL,
    overpayment_handling text DEFAULT 'hold_as_credit'::text NOT NULL,
    credit_application_timing text DEFAULT 'on_invoice_generation'::text NOT NULL,
    minimum_refund_amount numeric(10,2) DEFAULT 5.00 NOT NULL,
    below_threshold_action text DEFAULT 'hold_for_escheat'::text NOT NULL,
    donation_program_name text,
    auto_approve_clean_reads boolean DEFAULT true NOT NULL,
    unreviewed_read_billing_policy text DEFAULT 'block_run'::text NOT NULL,
    meter_redeployment_policy text DEFAULT 'either'::text NOT NULL,
    default_import_error_policy text DEFAULT 'partial_commit'::text NOT NULL,
    onboarded_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    void_only_unbilled_disposition text DEFAULT 'write_off'::text NOT NULL,
    void_rebill_threshold numeric(10,2) DEFAULT 0.00 NOT NULL,
    CONSTRAINT tenants_below_threshold_action_check CHECK ((below_threshold_action = ANY (ARRAY['hold_for_escheat'::text, 'apply_to_donation_if_opted_in'::text]))),
    CONSTRAINT tenants_credit_application_timing_check CHECK ((credit_application_timing = ANY (ARRAY['on_invoice_generation'::text, 'on_due_date'::text, 'manual_only'::text]))),
    CONSTRAINT tenants_default_import_error_policy_check CHECK ((default_import_error_policy = ANY (ARRAY['partial_commit'::text, 'all_or_nothing'::text]))),
    CONSTRAINT tenants_default_partial_period_policy_check CHECK ((default_partial_period_policy = ANY (ARRAY['prorated'::text, 'charge_both'::text, 'period_holder'::text]))),
    CONSTRAINT tenants_meter_redeployment_policy_check CHECK ((meter_redeployment_policy = ANY (ARRAY['reuse_record'::text, 'new_record'::text, 'either'::text]))),
    CONSTRAINT tenants_overpayment_handling_check CHECK ((overpayment_handling = ANY (ARRAY['hold_as_credit'::text, 'refund_automatically'::text, 'apply_to_specific_invoices'::text]))),
    CONSTRAINT tenants_payment_allocation_strategy_check CHECK ((payment_allocation_strategy = ANY (ARRAY['oldest_first'::text, 'newest_first'::text, 'largest_first'::text, 'manual_only'::text]))),
    CONSTRAINT tenants_status_check CHECK ((status = ANY (ARRAY['onboarding'::text, 'active'::text, 'suspended'::text, 'churned'::text]))),
    CONSTRAINT tenants_subscription_tier_check CHECK ((subscription_tier = ANY (ARRAY['starter'::text, 'professional'::text, 'enterprise'::text]))),
    CONSTRAINT tenants_unreviewed_read_billing_policy_check CHECK ((unreviewed_read_billing_policy = ANY (ARRAY['block_run'::text, 'skip_unreviewed'::text, 'proceed_with_warning'::text]))),
    CONSTRAINT tenants_void_only_unbilled_disposition_check CHECK ((void_only_unbilled_disposition = ANY (ARRAY['write_off'::text, 'carry_forward'::text]))),
    CONSTRAINT tenants_void_rebill_threshold_check CHECK ((void_rebill_threshold >= 0.00))
);


--
-- Name: COLUMN tenants.settings; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.tenants.settings IS 'Tenant-level configuration JSONB. Documented sub-objects:

    service_transition: controls auto-creation of adhoc charges on move-out / move-in
      auto_charge_disconnection (bool, default true)
      auto_charge_turn_on (bool, default true)
      turn_on_minimum_vacancy_days (int, default 3)
      disconnection_fee_default_amount (decimal)
      turn_on_fee_default_amount (decimal)

    estimation: controls Phase 2A behavior
      estimation_globally_enabled (bool, default true)
      max_consecutive_estimates (int, default 3)
      stale_meter_threshold_days (int, default 180)
      default_method_gas (text, default same_period_prior_year)
      default_method_water (text, default historical_average_3mo)
      default_method_electric (text, default historical_average_3mo)
      default_method_sewer (text, default historical_average_3mo)

    anomaly_detection: controls Phase 3 anomaly flagging
      auto_skip_negative_consumption (bool, default false)
      high_usage:
        enabled_months: { jan, feb, ..., dec } each bool, default true
        multiplier_threshold (decimal, default 3.0)
        stddev_threshold (decimal, default 2.0)
      low_usage:
        enabled_months: same shape, default all true
        multiplier_threshold (decimal, default 0.25)
      zero_usage:
        enabled_months: same shape, default all true

    adhoc: controls Phase 5 ad hoc charge handling
      max_defer_attempts (int, default 3)
      pickup_on_correction_runs (bool, default false)
      taxability_overrides (object): per-charge-type taxability override

    billing: controls Phase 6 invoice assembly and Phase 7 review
      payment_terms_days (int, default 21)
      deliver_zero_amount_invoices (bool, default true)
      deliver_credit_memo_invoices (bool, default false)
      issue_warning_below_payment_terms_days (int, default 15)
      review_required_anomalies (text[], default [negative_consumption])
      review_recommended_anomalies (text[], default [high_usage, estimated_streak])
      skip_rate_warning_threshold (decimal, default 0.05)
      estimation_rate_warning_threshold (decimal, default 0.10)
      anomaly_rate_warning_threshold (decimal, default 0.15)
      amount_swing_warning_threshold (decimal, default 0.30)
      stale_review_days (int, default 7)
      require_separate_approver (bool, default false)

    delivery: controls Phase 9 PDF generation and delivery dispatch
      pdf_max_attempts (int, default 3)
        — number of PDF generation retries before surfacing to operator
      pdf_retry_backoff_minutes (int[], default [1, 5, 15])
        — exponential backoff schedule between PDF retries
      delivery_max_attempts (int, default 3)
        — number of delivery retries (separate from PDF retries) before surfacing
      delivery_retry_backoff_minutes (int[], default [5, 30, 240])
        — exponential backoff schedule between delivery retries
      mail_batch_time (text, default "16:00")
        — local-time hour:minute when daily print/mail batches submit to vendor
      mail_batch_skip_holidays (bool, default true)
        — when true, holiday batches roll to next business day
      email_provider (text, default "ses")
        — application-layer abstraction; options include ses, sendgrid, mailgun, postmark
      mail_vendor (text, default "lob")
        — application-layer abstraction; options include lob, click2mail, postal_methods

    operations: controls admin actions and platform health
      manual_view_refresh_enabled (bool, default true)
        — when false, operators cannot trigger materialized view refreshes manually
          (post-run automatic refresh still happens)
      manual_view_refresh_min_interval_minutes (int, default 15)
        — minimum gap between consecutive manual refreshes; prevents storms on large tenants
      manual_view_refresh_role_restriction (text, default "admin")
        — minimum role required to trigger manual refresh; values: operator, admin, owner

    Future sub-objects (reserved keys; populate as features ship):
      ai_assistant, portal, dunning

    Application code MUST tolerate missing keys (read with COALESCE-style fallback to platform defaults).';


--
-- Name: COLUMN tenants.default_partial_period_policy; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.tenants.default_partial_period_policy IS 'Tenant-wide default for handling fixed charges when service starts/ends mid-cycle. Values: prorated (split by days), charge_both (both customers pay full), period_holder (cycle-date account owner pays full). Overridable per rate_schedule.';


--
-- Name: COLUMN tenants.payment_allocation_strategy; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.tenants.payment_allocation_strategy IS 'How incoming payments distribute across open invoices when no specific invoice is targeted. Default oldest_first (AwaLabs-style, most regulator-friendly).';


--
-- Name: COLUMN tenants.overpayment_handling; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.tenants.overpayment_handling IS 'Behavior when a payment exceeds total open balance. Default hold_as_credit.';


--
-- Name: COLUMN tenants.credit_application_timing; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.tenants.credit_application_timing IS 'When customer credit balances sweep onto new invoices. Default on_invoice_generation (bill shows reduced amount immediately).';


--
-- Name: COLUMN tenants.minimum_refund_amount; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.tenants.minimum_refund_amount IS 'Refund checks are not issued for amounts below this threshold. Residual is handled per below_threshold_action.';


--
-- Name: COLUMN tenants.below_threshold_action; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.tenants.below_threshold_action IS 'What happens to residual credit below minimum_refund_amount. hold_for_escheat (legally safe default) or apply_to_donation_if_opted_in (requires customer donation_opt_in=true).';


--
-- Name: COLUMN tenants.auto_approve_clean_reads; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.tenants.auto_approve_clean_reads IS 'When true, meter readings with no anomaly flags skip manual review and move directly from pending_review to approved. Operators retain visibility — auto-approved reads remain inspectable for known historical meter issues.';


--
-- Name: COLUMN tenants.unreviewed_read_billing_policy; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.tenants.unreviewed_read_billing_policy IS 'How billing runs handle reads that have not been approved when the run starts. block_run is safest default; skip_unreviewed lets billing proceed with estimates; proceed_with_warning posts anyway.';


--
-- Name: COLUMN tenants.meter_redeployment_policy; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.tenants.meter_redeployment_policy IS 'How returning-to-service meters are recorded. reuse_record (Pattern A): same row reactivated at new location; new_record (Pattern B): new meter row chained via replaces_meter_id; either (default): operator chooses per swap. The meter_deployments table normalizes both patterns so AI queries return consistent history.';


--
-- Name: COLUMN tenants.default_import_error_policy; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.tenants.default_import_error_policy IS 'Default error handling for bulk imports. partial_commit (default): valid rows commit, error rows held for fix-and-resubmit. all_or_nothing: any error aborts the whole import (for regulated-data tenants). Override per-import via import_jobs.error_handling_policy.';


--
-- Name: COLUMN tenants.void_only_unbilled_disposition; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.tenants.void_only_unbilled_disposition IS 'Controls unbilled consumption when a void-only is performed (no correction run follows). write_off=next bill starts from the void_released read; utility absorbs the loss (default). carry_forward=billing engine skips void_released reads and uses the prior locked read as start; voided period consumption rolls into the next bill. Ignored for gas meters (RRC requires full correction; void-only without rebill is only permitted for duplicate and wrong_customer/no-occupant scenarios on gas).';


--
-- Name: COLUMN tenants.void_rebill_threshold; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.tenants.void_rebill_threshold IS 'Non-gas meters only. If the net correction delta is below this amount, the operator is offered an adhoc adjustment path instead of a full void/rebill correction run. 0.00 (default) = always require correction. Gas meters always require full correction regardless of this setting. The threshold is evaluated against the absolute value of (corrected_amount - original_amount), not the original invoice total.';


--
-- Name: usage_statistics; Type: MATERIALIZED VIEW; Schema: public; Owner: -
--

CREATE MATERIALIZED VIEW public.usage_statistics AS
 WITH reading_stats AS (
         SELECT mr.meter_id,
            (array_agg(mr.consumption ORDER BY mr.reading_date DESC))[1] AS latest_consumption,
            (array_agg(mr.reading_date ORDER BY mr.reading_date DESC))[1] AS latest_reading_date,
            max(mr.reading_date) AS max_reading_date,
            avg(mr.consumption) FILTER (WHERE (mr.reading_date >= (CURRENT_DATE - '3 mons'::interval))) AS avg_3mo,
            avg(mr.consumption) FILTER (WHERE (mr.reading_date >= (CURRENT_DATE - '1 year'::interval))) AS avg_12mo,
            stddev(mr.consumption) FILTER (WHERE (mr.reading_date >= (CURRENT_DATE - '1 year'::interval))) AS stddev_12mo,
            min(mr.consumption) FILTER (WHERE (mr.reading_date >= (CURRENT_DATE - '1 year'::interval))) AS min_12mo,
            max(mr.consumption) FILTER (WHERE (mr.reading_date >= (CURRENT_DATE - '1 year'::interval))) AS max_12mo,
            count(*) FILTER (WHERE (mr.reading_date >= (CURRENT_DATE - '1 year'::interval))) AS readings_12mo,
            count(*) FILTER (WHERE ((mr.reading_date >= (CURRENT_DATE - '1 year'::interval)) AND (mr.is_estimated = true))) AS estimated_count_12mo,
            avg(mr.consumption) FILTER (WHERE ((mr.reading_date >= (CURRENT_DATE - '1 year 1 mon'::interval)) AND (mr.reading_date < (CURRENT_DATE - '11 mons'::interval)))) AS avg_same_period_last_year,
            regr_slope(((mr.consumption)::numeric)::double precision, ((EXTRACT(epoch FROM mr.reading_date) / (86400)::numeric))::double precision) FILTER (WHERE (mr.reading_date >= (CURRENT_DATE - '1 year'::interval))) AS consumption_trend_slope
           FROM public.meter_readings mr
          WHERE ((mr.status = 'active'::text) AND (mr.validation_status = ANY (ARRAY['approved'::text, 'released_to_billing'::text, 'locked'::text])) AND (mr.is_service_transition = false) AND (mr.consumption IS NOT NULL))
          GROUP BY mr.meter_id
        )
 SELECT m.tenant_id,
    m.id AS meter_id,
    m.meter_number,
    m.service_type,
    m.location_id,
    sl.customer_id,
    c.customer_type,
    rs.latest_consumption,
    rs.latest_reading_date,
    rs.avg_3mo,
    rs.avg_12mo,
    rs.stddev_12mo,
    rs.min_12mo,
    rs.max_12mo,
    rs.avg_same_period_last_year,
    rs.consumption_trend_slope,
    rs.readings_12mo,
    rs.estimated_count_12mo,
        CASE
            WHEN (rs.readings_12mo > 0) THEN ((rs.estimated_count_12mo)::numeric / (rs.readings_12mo)::numeric)
            ELSE NULL::numeric
        END AS estimation_rate_12mo,
        CASE
            WHEN ((rs.readings_12mo IS NULL) OR (rs.readings_12mo < 3)) THEN 'insufficient'::text
            WHEN ((rs.readings_12mo > 0) AND (((rs.estimated_count_12mo)::numeric / (rs.readings_12mo)::numeric) > 0.50)) THEN 'poor'::text
            WHEN ((rs.readings_12mo > 0) AND (((rs.estimated_count_12mo)::numeric / (rs.readings_12mo)::numeric) > 0.20)) THEN 'marginal'::text
            ELSE 'good'::text
        END AS data_quality_flag,
    (CURRENT_DATE - rs.max_reading_date) AS days_since_last_read
   FROM (((public.meters m
     JOIN public.service_locations sl ON ((sl.id = m.location_id)))
     JOIN public.customers c ON ((c.id = sl.customer_id)))
     LEFT JOIN reading_stats rs ON ((rs.meter_id = m.id)))
  WHERE ((m.status = 'active'::text) AND (m.is_virtual = false))
  WITH NO DATA;


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    id uuid NOT NULL,
    tenant_id uuid NOT NULL,
    role text DEFAULT 'operator'::text NOT NULL,
    display_name text NOT NULL,
    email text NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    last_login_at timestamp with time zone,
    preferences jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT users_role_check CHECK ((role = ANY (ARRAY['platform_admin'::text, 'tenant_admin'::text, 'operator'::text, 'viewer'::text])))
);


--
-- Name: void_released_read_alerts; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.void_released_read_alerts AS
 SELECT mr.tenant_id,
    mr.meter_id,
    mr.id AS read_id,
    mr.reading_date,
    mr.consumption,
    mr.consumption_unit,
    mr.voided_from_invoice_id,
    i.invoice_number AS voided_invoice_number,
    i.billing_period AS voided_billing_period,
    i.period_start AS voided_period_start,
    i.period_end AS voided_period_end,
    i.customer_id AS original_customer_id,
    i.location_id AS service_location_id,
    i.void_reason_code,
    i.void_rebill_expected,
    i.voided_at,
    i.voided_by,
    (EXISTS ( SELECT 1
           FROM public.correction_run_targets crt
          WHERE (crt.voided_invoice_id = mr.voided_from_invoice_id))) AS correction_run_exists,
    (EXISTS ( SELECT 1
           FROM public.correction_run_targets crt
          WHERE ((crt.voided_invoice_id = mr.voided_from_invoice_id) AND (crt.correction_invoice_id IS NOT NULL)))) AS correction_invoice_exists,
    ( SELECT crt.billing_run_id
           FROM public.correction_run_targets crt
          WHERE (crt.voided_invoice_id = mr.voided_from_invoice_id)
         LIMIT 1) AS correction_billing_run_id,
    ( SELECT crt.correction_invoice_id
           FROM public.correction_run_targets crt
          WHERE (crt.voided_invoice_id = mr.voided_from_invoice_id)
         LIMIT 1) AS correction_invoice_id
   FROM (public.meter_readings mr
     JOIN public.invoices i ON ((i.id = mr.voided_from_invoice_id)))
  WHERE ((mr.validation_status = 'void_released'::text) AND (i.void_rebill_expected = true) AND (NOT (EXISTS ( SELECT 1
           FROM public.correction_run_targets crt
          WHERE ((crt.voided_invoice_id = mr.voided_from_invoice_id) AND (crt.correction_invoice_id IS NOT NULL))))));


--
-- Name: VIEW void_released_read_alerts; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.void_released_read_alerts IS 'Meters with void_released reads awaiting a correction invoice. Filters by void_rebill_expected=true (void_rebill_expected is NOT NULL so no COALESCE needed). Rows disappear once correction_run_targets.correction_invoice_id is set.';


--
-- Name: wna_monthly_adjustments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.wna_monthly_adjustments (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id uuid NOT NULL,
    wna_zone_id uuid NOT NULL,
    billing_month date NOT NULL,
    actual_hdd numeric(10,2),
    normal_hdd numeric(10,2),
    adjustment_factor numeric(14,6),
    adjustment_unit text DEFAULT 'per_mcf'::text,
    status text DEFAULT 'pending'::text NOT NULL,
    approved_by uuid,
    approved_at timestamp with time zone,
    notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT wna_monthly_adjustments_adjustment_unit_check CHECK ((adjustment_unit = ANY (ARRAY['per_mcf'::text, 'per_ccf'::text, 'per_therm'::text, 'percent'::text, 'flat'::text]))),
    CONSTRAINT wna_monthly_adjustments_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'approved'::text, 'applied'::text, 'archived'::text])))
);


--
-- Name: wna_zones; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.wna_zones (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id uuid NOT NULL,
    zone_code text NOT NULL,
    zone_name text NOT NULL,
    description text,
    active_months integer[] DEFAULT '{11,12,1,2,3,4}'::integer[] NOT NULL,
    normal_hdd numeric(10,2),
    base_load_consumption numeric(10,4),
    heating_factor numeric(10,6),
    calculation_notes text,
    weather_station_name text,
    weather_station_id text,
    status text DEFAULT 'active'::text NOT NULL,
    effective_date date DEFAULT CURRENT_DATE NOT NULL,
    expiry_date date,
    calc_owner text,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT wna_zones_status_check CHECK ((status = ANY (ARRAY['active'::text, 'paused'::text, 'archived'::text])))
);


--
-- Name: account_ledger account_ledger_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.account_ledger
    ADD CONSTRAINT account_ledger_pkey PRIMARY KEY (id);


--
-- Name: adhoc_charges adhoc_charges_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.adhoc_charges
    ADD CONSTRAINT adhoc_charges_pkey PRIMARY KEY (id);


--
-- Name: adhoc_charges adhoc_charges_tenant_id_charge_number_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.adhoc_charges
    ADD CONSTRAINT adhoc_charges_tenant_id_charge_number_key UNIQUE (tenant_id, charge_number);


--
-- Name: ai_audit_log ai_audit_log_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_audit_log
    ADD CONSTRAINT ai_audit_log_pkey PRIMARY KEY (id);


--
-- Name: ai_sessions ai_sessions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_sessions
    ADD CONSTRAINT ai_sessions_pkey PRIMARY KEY (id);


--
-- Name: ai_suggestions ai_suggestions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_suggestions
    ADD CONSTRAINT ai_suggestions_pkey PRIMARY KEY (id);


--
-- Name: ai_tool_calls ai_tool_calls_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_tool_calls
    ADD CONSTRAINT ai_tool_calls_pkey PRIMARY KEY (id);


--
-- Name: alerts alerts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.alerts
    ADD CONSTRAINT alerts_pkey PRIMARY KEY (id);


--
-- Name: anomalies anomalies_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.anomalies
    ADD CONSTRAINT anomalies_pkey PRIMARY KEY (id);


--
-- Name: anomalies anomalies_tenant_id_dedup_key_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.anomalies
    ADD CONSTRAINT anomalies_tenant_id_dedup_key_key UNIQUE (tenant_id, dedup_key) DEFERRABLE;


--
-- Name: auto_pay_settings auto_pay_settings_customer_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auto_pay_settings
    ADD CONSTRAINT auto_pay_settings_customer_id_key UNIQUE (customer_id) DEFERRABLE;


--
-- Name: auto_pay_settings auto_pay_settings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auto_pay_settings
    ADD CONSTRAINT auto_pay_settings_pkey PRIMARY KEY (id);


--
-- Name: bill_messages bill_messages_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bill_messages
    ADD CONSTRAINT bill_messages_pkey PRIMARY KEY (id);


--
-- Name: billing_cycles billing_cycles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.billing_cycles
    ADD CONSTRAINT billing_cycles_pkey PRIMARY KEY (id);


--
-- Name: billing_cycles billing_cycles_tenant_id_cycle_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.billing_cycles
    ADD CONSTRAINT billing_cycles_tenant_id_cycle_code_key UNIQUE (tenant_id, cycle_code);


--
-- Name: billing_run_meters billing_run_meters_billing_run_id_meter_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.billing_run_meters
    ADD CONSTRAINT billing_run_meters_billing_run_id_meter_id_key UNIQUE (billing_run_id, meter_id);


--
-- Name: billing_run_meters billing_run_meters_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.billing_run_meters
    ADD CONSTRAINT billing_run_meters_pkey PRIMARY KEY (id);


--
-- Name: billing_runs billing_runs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.billing_runs
    ADD CONSTRAINT billing_runs_pkey PRIMARY KEY (id);


--
-- Name: billing_runs billing_runs_tenant_id_run_number_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.billing_runs
    ADD CONSTRAINT billing_runs_tenant_id_run_number_key UNIQUE (tenant_id, run_number);


--
-- Name: communities communities_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.communities
    ADD CONSTRAINT communities_pkey PRIMARY KEY (id);


--
-- Name: communities communities_tenant_id_community_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.communities
    ADD CONSTRAINT communities_tenant_id_community_code_key UNIQUE (tenant_id, community_code);


--
-- Name: communities communities_tenant_id_community_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.communities
    ADD CONSTRAINT communities_tenant_id_community_name_key UNIQUE (tenant_id, community_name);


--
-- Name: correction_run_targets correction_run_targets_billing_run_id_voided_invoice_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.correction_run_targets
    ADD CONSTRAINT correction_run_targets_billing_run_id_voided_invoice_id_key UNIQUE (billing_run_id, voided_invoice_id);


--
-- Name: correction_run_targets correction_run_targets_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.correction_run_targets
    ADD CONSTRAINT correction_run_targets_pkey PRIMARY KEY (id);


--
-- Name: custom_field_definitions custom_field_definitions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.custom_field_definitions
    ADD CONSTRAINT custom_field_definitions_pkey PRIMARY KEY (id);


--
-- Name: custom_field_definitions custom_field_definitions_tenant_id_entity_type_field_key_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.custom_field_definitions
    ADD CONSTRAINT custom_field_definitions_tenant_id_entity_type_field_key_key UNIQUE (tenant_id, entity_type, field_key);


--
-- Name: custom_location_types custom_location_types_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.custom_location_types
    ADD CONSTRAINT custom_location_types_pkey PRIMARY KEY (id);


--
-- Name: custom_location_types custom_location_types_tenant_id_type_key_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.custom_location_types
    ADD CONSTRAINT custom_location_types_tenant_id_type_key_key UNIQUE (tenant_id, type_key);


--
-- Name: customer_contacts customer_contacts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_contacts
    ADD CONSTRAINT customer_contacts_pkey PRIMARY KEY (id);


--
-- Name: customer_credits customer_credits_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_credits
    ADD CONSTRAINT customer_credits_pkey PRIMARY KEY (id);


--
-- Name: customer_interactions customer_interactions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_interactions
    ADD CONSTRAINT customer_interactions_pkey PRIMARY KEY (id);


--
-- Name: customer_tax_exemptions customer_tax_exemptions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_tax_exemptions
    ADD CONSTRAINT customer_tax_exemptions_pkey PRIMARY KEY (id);


--
-- Name: customer_winter_averages customer_winter_averages_meter_id_winter_year_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_winter_averages
    ADD CONSTRAINT customer_winter_averages_meter_id_winter_year_key UNIQUE (meter_id, winter_year);


--
-- Name: customer_winter_averages customer_winter_averages_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_winter_averages
    ADD CONSTRAINT customer_winter_averages_pkey PRIMARY KEY (id);


--
-- Name: customers customers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customers
    ADD CONSTRAINT customers_pkey PRIMARY KEY (id);


--
-- Name: customers customers_tenant_id_customer_number_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customers
    ADD CONSTRAINT customers_tenant_id_customer_number_key UNIQUE (tenant_id, customer_number);


--
-- Name: customers customers_tenant_id_external_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customers
    ADD CONSTRAINT customers_tenant_id_external_id_key UNIQUE (tenant_id, external_id);


--
-- Name: dunning_events dunning_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dunning_events
    ADD CONSTRAINT dunning_events_pkey PRIMARY KEY (id);


--
-- Name: escheatment_events escheatment_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.escheatment_events
    ADD CONSTRAINT escheatment_events_pkey PRIMARY KEY (id);


--
-- Name: franchise_fee_rules franchise_fee_rules_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.franchise_fee_rules
    ADD CONSTRAINT franchise_fee_rules_pkey PRIMARY KEY (id);


--
-- Name: franchise_fee_rules franchise_fee_rules_tenant_id_city_name_effective_date_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.franchise_fee_rules
    ADD CONSTRAINT franchise_fee_rules_tenant_id_city_name_effective_date_key UNIQUE (tenant_id, city_name, effective_date);


--
-- Name: import_column_mappings import_column_mappings_import_job_id_source_column_position_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.import_column_mappings
    ADD CONSTRAINT import_column_mappings_import_job_id_source_column_position_key UNIQUE (import_job_id, source_column_position);


--
-- Name: import_column_mappings import_column_mappings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.import_column_mappings
    ADD CONSTRAINT import_column_mappings_pkey PRIMARY KEY (id);


--
-- Name: import_jobs import_jobs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.import_jobs
    ADD CONSTRAINT import_jobs_pkey PRIMARY KEY (id);


--
-- Name: import_jobs import_jobs_tenant_id_idempotency_key_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.import_jobs
    ADD CONSTRAINT import_jobs_tenant_id_idempotency_key_key UNIQUE (tenant_id, idempotency_key);


--
-- Name: import_mapping_templates import_mapping_templates_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.import_mapping_templates
    ADD CONSTRAINT import_mapping_templates_pkey PRIMARY KEY (id);


--
-- Name: import_mapping_templates import_mapping_templates_tenant_id_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.import_mapping_templates
    ADD CONSTRAINT import_mapping_templates_tenant_id_name_key UNIQUE (tenant_id, name);


--
-- Name: import_staging import_staging_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.import_staging
    ADD CONSTRAINT import_staging_pkey PRIMARY KEY (id);


--
-- Name: invoice_applications invoice_applications_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoice_applications
    ADD CONSTRAINT invoice_applications_pkey PRIMARY KEY (id);


--
-- Name: invoice_events invoice_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoice_events
    ADD CONSTRAINT invoice_events_pkey PRIMARY KEY (id);


--
-- Name: invoice_line_items invoice_line_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoice_line_items
    ADD CONSTRAINT invoice_line_items_pkey PRIMARY KEY (id);


--
-- Name: invoices invoices_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoices
    ADD CONSTRAINT invoices_pkey PRIMARY KEY (id);


--
-- Name: invoices invoices_tenant_id_invoice_number_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoices
    ADD CONSTRAINT invoices_tenant_id_invoice_number_key UNIQUE (tenant_id, invoice_number);


--
-- Name: materialized_view_refresh_log materialized_view_refresh_log_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.materialized_view_refresh_log
    ADD CONSTRAINT materialized_view_refresh_log_pkey PRIMARY KEY (view_name);


--
-- Name: meter_deployments meter_deployments_meter_id_deployment_number_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.meter_deployments
    ADD CONSTRAINT meter_deployments_meter_id_deployment_number_key UNIQUE (meter_id, deployment_number);


--
-- Name: meter_deployments meter_deployments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.meter_deployments
    ADD CONSTRAINT meter_deployments_pkey PRIMARY KEY (id);


--
-- Name: meter_endpoint_history meter_endpoint_history_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.meter_endpoint_history
    ADD CONSTRAINT meter_endpoint_history_pkey PRIMARY KEY (id);


--
-- Name: meter_photos meter_photos_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.meter_photos
    ADD CONSTRAINT meter_photos_pkey PRIMARY KEY (id);


--
-- Name: meter_readings meter_readings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.meter_readings
    ADD CONSTRAINT meter_readings_pkey PRIMARY KEY (id);


--
-- Name: meters meters_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.meters
    ADD CONSTRAINT meters_pkey PRIMARY KEY (id);


--
-- Name: meters meters_tenant_id_external_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.meters
    ADD CONSTRAINT meters_tenant_id_external_id_key UNIQUE (tenant_id, external_id);


--
-- Name: meters meters_tenant_id_meter_number_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.meters
    ADD CONSTRAINT meters_tenant_id_meter_number_key UNIQUE (tenant_id, meter_number);


--
-- Name: payment_methods payment_methods_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payment_methods
    ADD CONSTRAINT payment_methods_pkey PRIMARY KEY (id);


--
-- Name: payment_methods payment_methods_provider_provider_token_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payment_methods
    ADD CONSTRAINT payment_methods_provider_provider_token_key UNIQUE (provider, provider_token);


--
-- Name: payment_provider_logs payment_provider_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payment_provider_logs
    ADD CONSTRAINT payment_provider_logs_pkey PRIMARY KEY (id);


--
-- Name: payments payments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_pkey PRIMARY KEY (id);


--
-- Name: payments payments_tenant_id_payment_number_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_tenant_id_payment_number_key UNIQUE (tenant_id, payment_number);


--
-- Name: rate_item_dependencies rate_item_dependencies_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rate_item_dependencies
    ADD CONSTRAINT rate_item_dependencies_pkey PRIMARY KEY (id);


--
-- Name: rate_item_dependencies rate_item_dependencies_rate_schedule_id_dependent_rate_item_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rate_item_dependencies
    ADD CONSTRAINT rate_item_dependencies_rate_schedule_id_dependent_rate_item_key UNIQUE (rate_schedule_id, dependent_rate_item_id, base_rate_item_id);


--
-- Name: rate_item_history_archive rate_item_history_archive_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rate_item_history_archive
    ADD CONSTRAINT rate_item_history_archive_pkey PRIMARY KEY (id);


--
-- Name: rate_item_history rate_item_history_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rate_item_history
    ADD CONSTRAINT rate_item_history_pkey PRIMARY KEY (id);


--
-- Name: rate_items rate_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rate_items
    ADD CONSTRAINT rate_items_pkey PRIMARY KEY (id);


--
-- Name: rate_items rate_items_tenant_id_item_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rate_items
    ADD CONSTRAINT rate_items_tenant_id_item_code_key UNIQUE (tenant_id, item_code);


--
-- Name: rate_schedule_items rate_schedule_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rate_schedule_items
    ADD CONSTRAINT rate_schedule_items_pkey PRIMARY KEY (id);


--
-- Name: rate_schedule_items rate_schedule_items_rate_schedule_id_rate_item_id_effective_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rate_schedule_items
    ADD CONSTRAINT rate_schedule_items_rate_schedule_id_rate_item_id_effective_key UNIQUE (rate_schedule_id, rate_item_id, effective_date);


--
-- Name: rate_schedules rate_schedules_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rate_schedules
    ADD CONSTRAINT rate_schedules_pkey PRIMARY KEY (id);


--
-- Name: rate_schedules rate_schedules_tenant_id_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rate_schedules
    ADD CONSTRAINT rate_schedules_tenant_id_code_key UNIQUE (tenant_id, code);


--
-- Name: read_cycle_instances read_cycle_instances_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.read_cycle_instances
    ADD CONSTRAINT read_cycle_instances_pkey PRIMARY KEY (id);


--
-- Name: read_cycle_instances read_cycle_instances_tenant_id_billing_cycle_id_period_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.read_cycle_instances
    ADD CONSTRAINT read_cycle_instances_tenant_id_billing_cycle_id_period_key UNIQUE (tenant_id, billing_cycle_id, period);


--
-- Name: read_cycle_meters read_cycle_meters_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.read_cycle_meters
    ADD CONSTRAINT read_cycle_meters_pkey PRIMARY KEY (id);


--
-- Name: read_cycle_meters read_cycle_meters_read_cycle_instance_id_meter_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.read_cycle_meters
    ADD CONSTRAINT read_cycle_meters_read_cycle_instance_id_meter_id_key UNIQUE (read_cycle_instance_id, meter_id);


--
-- Name: read_routes read_routes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.read_routes
    ADD CONSTRAINT read_routes_pkey PRIMARY KEY (id);


--
-- Name: read_routes read_routes_tenant_id_route_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.read_routes
    ADD CONSTRAINT read_routes_tenant_id_route_code_key UNIQUE (tenant_id, route_code);


--
-- Name: service_locations service_locations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.service_locations
    ADD CONSTRAINT service_locations_pkey PRIMARY KEY (id);


--
-- Name: service_locations service_locations_tenant_id_external_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.service_locations
    ADD CONSTRAINT service_locations_tenant_id_external_id_key UNIQUE (tenant_id, external_id);


--
-- Name: service_locations service_locations_tenant_id_location_number_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.service_locations
    ADD CONSTRAINT service_locations_tenant_id_location_number_key UNIQUE (tenant_id, location_number);


--
-- Name: service_orders service_orders_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.service_orders
    ADD CONSTRAINT service_orders_pkey PRIMARY KEY (id);


--
-- Name: service_orders service_orders_tenant_id_order_number_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.service_orders
    ADD CONSTRAINT service_orders_tenant_id_order_number_key UNIQUE (tenant_id, order_number);


--
-- Name: tenant_sequences tenant_sequences_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tenant_sequences
    ADD CONSTRAINT tenant_sequences_pkey PRIMARY KEY (id);


--
-- Name: tenant_sequences tenant_sequences_tenant_id_sequence_type_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tenant_sequences
    ADD CONSTRAINT tenant_sequences_tenant_id_sequence_type_key UNIQUE (tenant_id, sequence_type);


--
-- Name: tenants tenants_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tenants
    ADD CONSTRAINT tenants_pkey PRIMARY KEY (id);


--
-- Name: tenants tenants_slug_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tenants
    ADD CONSTRAINT tenants_slug_key UNIQUE (slug);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: wna_monthly_adjustments wna_monthly_adjustments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wna_monthly_adjustments
    ADD CONSTRAINT wna_monthly_adjustments_pkey PRIMARY KEY (id);


--
-- Name: wna_monthly_adjustments wna_monthly_adjustments_tenant_id_wna_zone_id_billing_month_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wna_monthly_adjustments
    ADD CONSTRAINT wna_monthly_adjustments_tenant_id_wna_zone_id_billing_month_key UNIQUE (tenant_id, wna_zone_id, billing_month);


--
-- Name: wna_zones wna_zones_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wna_zones
    ADD CONSTRAINT wna_zones_pkey PRIMARY KEY (id);


--
-- Name: wna_zones wna_zones_tenant_id_zone_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wna_zones
    ADD CONSTRAINT wna_zones_tenant_id_zone_code_key UNIQUE (tenant_id, zone_code);


--
-- Name: idx_adhoc_billed_line; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_adhoc_billed_line ON public.adhoc_charges USING btree (billed_on_line_item_id) WHERE (billed_on_line_item_id IS NOT NULL);


--
-- Name: idx_adhoc_billed_run; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_adhoc_billed_run ON public.adhoc_charges USING btree (billed_by_billing_run_id) WHERE (billed_by_billing_run_id IS NOT NULL);


--
-- Name: idx_adhoc_customer; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_adhoc_customer ON public.adhoc_charges USING btree (customer_id);


--
-- Name: idx_adhoc_location; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_adhoc_location ON public.adhoc_charges USING btree (location_id) WHERE (location_id IS NOT NULL);


--
-- Name: idx_adhoc_meter; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_adhoc_meter ON public.adhoc_charges USING btree (meter_id) WHERE (meter_id IS NOT NULL);


--
-- Name: idx_adhoc_pending; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_adhoc_pending ON public.adhoc_charges USING btree (tenant_id, effective_date) WHERE (status = 'pending'::text);


--
-- Name: idx_adhoc_pending_approval; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_adhoc_pending_approval ON public.adhoc_charges USING btree (tenant_id, created_at DESC) WHERE ((requires_approval = true) AND (approved_at IS NULL) AND (status = 'pending'::text));


--
-- Name: idx_adhoc_pending_target_period_meter; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_adhoc_pending_target_period_meter ON public.adhoc_charges USING btree (meter_id, target_billing_period) WHERE ((status = 'pending'::text) AND (target_billing_period IS NOT NULL));


--
-- Name: idx_adhoc_source; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_adhoc_source ON public.adhoc_charges USING btree (tenant_id, source, created_at DESC);


--
-- Name: idx_adhoc_suggestion; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_adhoc_suggestion ON public.adhoc_charges USING btree (created_by_suggestion_id) WHERE (created_by_suggestion_id IS NOT NULL);


--
-- Name: idx_adhoc_target_period; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_adhoc_target_period ON public.adhoc_charges USING btree (tenant_id, target_billing_period) WHERE ((status = 'pending'::text) AND (target_billing_period IS NOT NULL));


--
-- Name: idx_adhoc_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_adhoc_tenant ON public.adhoc_charges USING btree (tenant_id);


--
-- Name: idx_adhoc_triggered_invoice; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_adhoc_triggered_invoice ON public.adhoc_charges USING btree (triggered_by_invoice_id) WHERE (triggered_by_invoice_id IS NOT NULL);


--
-- Name: idx_adhoc_triggered_payment; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_adhoc_triggered_payment ON public.adhoc_charges USING btree (triggered_by_payment_id) WHERE (triggered_by_payment_id IS NOT NULL);


--
-- Name: idx_adhoc_triggered_reading; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_adhoc_triggered_reading ON public.adhoc_charges USING btree (triggered_by_reading_id) WHERE (triggered_by_reading_id IS NOT NULL);


--
-- Name: idx_adhoc_void_pending_rebill; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_adhoc_void_pending_rebill ON public.adhoc_charges USING btree (tenant_id, updated_at DESC) WHERE (status = 'void_pending_rebill'::text);


--
-- Name: idx_adhoc_voided_from_invoice; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_adhoc_voided_from_invoice ON public.adhoc_charges USING btree (voided_from_invoice_id) WHERE (voided_from_invoice_id IS NOT NULL);


--
-- Name: idx_ai_audit_action; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ai_audit_action ON public.ai_audit_log USING btree (tenant_id, action_type, created_at DESC);


--
-- Name: idx_ai_audit_cost; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ai_audit_cost ON public.ai_audit_log USING btree (tenant_id, created_at) WHERE (cost_usd > (0)::numeric);


--
-- Name: idx_ai_audit_entity; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ai_audit_entity ON public.ai_audit_log USING btree (entity_type, entity_id);


--
-- Name: idx_ai_audit_errors; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ai_audit_errors ON public.ai_audit_log USING btree (tenant_id, created_at DESC) WHERE (action_type = 'error'::text);


--
-- Name: idx_ai_audit_mutations; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ai_audit_mutations ON public.ai_audit_log USING btree (tenant_id, created_at DESC) WHERE (action_type = 'mutation_executed'::text);


--
-- Name: idx_ai_audit_session; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ai_audit_session ON public.ai_audit_log USING btree (session_id, created_at);


--
-- Name: idx_ai_audit_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ai_audit_tenant ON public.ai_audit_log USING btree (tenant_id, created_at DESC);


--
-- Name: idx_ai_audit_user; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ai_audit_user ON public.ai_audit_log USING btree (user_id, created_at DESC);


--
-- Name: idx_ai_sessions_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ai_sessions_active ON public.ai_sessions USING btree (user_id, last_activity_at DESC) WHERE (status = 'active'::text);


--
-- Name: idx_ai_sessions_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ai_sessions_tenant ON public.ai_sessions USING btree (tenant_id, last_activity_at DESC);


--
-- Name: idx_ai_sessions_user; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ai_sessions_user ON public.ai_sessions USING btree (user_id, last_activity_at DESC);


--
-- Name: idx_alerts_dedup; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_alerts_dedup ON public.alerts USING btree (tenant_id, dedup_key) WHERE (dedup_key IS NOT NULL);


--
-- Name: idx_alerts_expiring; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_alerts_expiring ON public.alerts USING btree (tenant_id, expires_at) WHERE (expires_at IS NOT NULL);


--
-- Name: idx_alerts_role; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_alerts_role ON public.alerts USING btree (tenant_id, target_role) WHERE (target_role IS NOT NULL);


--
-- Name: idx_alerts_snoozed; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_alerts_snoozed ON public.alerts USING btree (target_user_id, snoozed_until) WHERE (snoozed_until IS NOT NULL);


--
-- Name: idx_alerts_source; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_alerts_source ON public.alerts USING btree (source_type, source_id);


--
-- Name: idx_alerts_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_alerts_tenant ON public.alerts USING btree (tenant_id, created_at DESC);


--
-- Name: idx_alerts_tenant_unread; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_alerts_tenant_unread ON public.alerts USING btree (tenant_id, priority, created_at DESC) WHERE ((is_read = false) AND (is_dismissed = false));


--
-- Name: idx_alerts_user_unread; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_alerts_user_unread ON public.alerts USING btree (target_user_id, created_at DESC) WHERE ((is_read = false) AND (is_dismissed = false));


--
-- Name: idx_anomalies_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_anomalies_active ON public.anomalies USING btree (tenant_id, detected_at DESC) WHERE (status <> ALL (ARRAY['resolved'::text, 'false_positive'::text]));


--
-- Name: idx_anomalies_assigned; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_anomalies_assigned ON public.anomalies USING btree (assigned_to, status) WHERE (assigned_to IS NOT NULL);


--
-- Name: idx_anomalies_customer; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_anomalies_customer ON public.anomalies USING btree (customer_id);


--
-- Name: idx_anomalies_feedback; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_anomalies_feedback ON public.anomalies USING btree (tenant_id, detector_name, feedback_category) WHERE (feedback_category IS NOT NULL);


--
-- Name: idx_anomalies_location; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_anomalies_location ON public.anomalies USING btree (location_id);


--
-- Name: idx_anomalies_meter; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_anomalies_meter ON public.anomalies USING btree (meter_id);


--
-- Name: idx_anomalies_open; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_anomalies_open ON public.anomalies USING btree (tenant_id, status, severity) WHERE (status = ANY (ARRAY['open'::text, 'acknowledged'::text, 'investigating'::text]));


--
-- Name: idx_anomalies_snoozed; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_anomalies_snoozed ON public.anomalies USING btree (tenant_id, snoozed_until) WHERE (status = 'snoozed'::text);


--
-- Name: idx_anomalies_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_anomalies_tenant ON public.anomalies USING btree (tenant_id);


--
-- Name: idx_anomalies_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_anomalies_type ON public.anomalies USING btree (tenant_id, anomaly_type, detected_at DESC);


--
-- Name: idx_auto_pay_due; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_auto_pay_due ON public.auto_pay_settings USING btree (tenant_id, next_run_at) WHERE ((enabled = true) AND (pause_until IS NULL));


--
-- Name: idx_auto_pay_failing; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_auto_pay_failing ON public.auto_pay_settings USING btree (tenant_id, consecutive_failures) WHERE ((consecutive_failures > 0) AND (enabled = true));


--
-- Name: idx_auto_pay_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_auto_pay_tenant ON public.auto_pay_settings USING btree (tenant_id);


--
-- Name: idx_bill_messages_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_bill_messages_active ON public.bill_messages USING btree (tenant_id, effective_start, effective_end) WHERE (status = 'active'::text);


--
-- Name: idx_bill_messages_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_bill_messages_tenant ON public.bill_messages USING btree (tenant_id);


--
-- Name: idx_billing_cycles_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_billing_cycles_active ON public.billing_cycles USING btree (tenant_id, status) WHERE (status = 'active'::text);


--
-- Name: idx_billing_cycles_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_billing_cycles_tenant ON public.billing_cycles USING btree (tenant_id);


--
-- Name: idx_billing_run_meters_anomaly; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_billing_run_meters_anomaly ON public.billing_run_meters USING btree (tenant_id, billing_run_id) WHERE (has_anomaly = true);


--
-- Name: idx_billing_run_meters_invoice; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_billing_run_meters_invoice ON public.billing_run_meters USING btree (invoice_id) WHERE (invoice_id IS NOT NULL);


--
-- Name: idx_billing_run_meters_meter_history; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_billing_run_meters_meter_history ON public.billing_run_meters USING btree (meter_id, created_at DESC);


--
-- Name: idx_billing_run_meters_outcome; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_billing_run_meters_outcome ON public.billing_run_meters USING btree (tenant_id, outcome);


--
-- Name: idx_billing_run_meters_run; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_billing_run_meters_run ON public.billing_run_meters USING btree (billing_run_id);


--
-- Name: idx_billing_runs_cancelled; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_billing_runs_cancelled ON public.billing_runs USING btree (tenant_id, cancelled_at DESC) WHERE (cancelled_at IS NOT NULL);


--
-- Name: idx_billing_runs_cycle; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_billing_runs_cycle ON public.billing_runs USING btree (billing_cycle_id) WHERE (billing_cycle_id IS NOT NULL);


--
-- Name: idx_billing_runs_open; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_billing_runs_open ON public.billing_runs USING btree (tenant_id, status) WHERE (status = ANY (ARRAY['pending'::text, 'in_progress'::text, 'review'::text]));


--
-- Name: idx_billing_runs_period; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_billing_runs_period ON public.billing_runs USING btree (tenant_id, billing_period);


--
-- Name: idx_billing_runs_read_cycle; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_billing_runs_read_cycle ON public.billing_runs USING btree (read_cycle_instance_id) WHERE (read_cycle_instance_id IS NOT NULL);


--
-- Name: idx_billing_runs_stale_heartbeat; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_billing_runs_stale_heartbeat ON public.billing_runs USING btree (tenant_id, last_heartbeat_at) WHERE (status = ANY (ARRAY['pending'::text, 'in_progress'::text]));


--
-- Name: idx_billing_runs_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_billing_runs_tenant ON public.billing_runs USING btree (tenant_id);


--
-- Name: idx_billing_runs_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_billing_runs_type ON public.billing_runs USING btree (tenant_id, run_type, status);


--
-- Name: idx_column_mappings_job; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_column_mappings_job ON public.import_column_mappings USING btree (import_job_id, source_column_position);


--
-- Name: idx_column_mappings_low_confidence; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_column_mappings_low_confidence ON public.import_column_mappings USING btree (tenant_id, mapping_confidence) WHERE ((mapping_confidence IS NOT NULL) AND (mapping_confidence < 0.70));


--
-- Name: idx_column_mappings_outliers; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_column_mappings_outliers ON public.import_column_mappings USING btree (import_job_id) WHERE (has_outlier_pattern = true);


--
-- Name: idx_column_mappings_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_column_mappings_tenant ON public.import_column_mappings USING btree (tenant_id);


--
-- Name: idx_communities_search; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_communities_search ON public.communities USING gin ((((community_name || ' '::text) || COALESCE(community_code, ''::text))) public.gin_trgm_ops);


--
-- Name: idx_communities_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_communities_status ON public.communities USING btree (tenant_id, status) WHERE (status = 'active'::text);


--
-- Name: idx_communities_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_communities_tenant ON public.communities USING btree (tenant_id);


--
-- Name: idx_communities_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_communities_type ON public.communities USING btree (tenant_id, community_type);


--
-- Name: idx_compliance_stats_customer; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_compliance_stats_customer ON public.compliance_statistics USING btree (customer_id);


--
-- Name: idx_compliance_stats_disconnect_expiring; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_compliance_stats_disconnect_expiring ON public.compliance_statistics USING btree (tenant_id) WHERE (disconnect_protection_expiring = true);


--
-- Name: idx_compliance_stats_tax_expired; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_compliance_stats_tax_expired ON public.compliance_statistics USING btree (tenant_id) WHERE (tax_exemption_expired = true);


--
-- Name: idx_compliance_stats_tax_expiring; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_compliance_stats_tax_expiring ON public.compliance_statistics USING btree (tenant_id) WHERE (tax_exemption_expiring_soon = true);


--
-- Name: idx_compliance_stats_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_compliance_stats_tenant ON public.compliance_statistics USING btree (tenant_id);


--
-- Name: idx_credit_aging_bucket; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_credit_aging_bucket ON public.credit_aging_statistics USING btree (tenant_id, aging_bucket);


--
-- Name: idx_credit_aging_credit; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_credit_aging_credit ON public.credit_aging_statistics USING btree (credit_id);


--
-- Name: idx_credit_aging_customer; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_credit_aging_customer ON public.credit_aging_statistics USING btree (customer_id);


--
-- Name: idx_credit_aging_deposit_overdue; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_credit_aging_deposit_overdue ON public.credit_aging_statistics USING btree (tenant_id) WHERE (deposit_refund_overdue = true);


--
-- Name: idx_credit_aging_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_credit_aging_tenant ON public.credit_aging_statistics USING btree (tenant_id);


--
-- Name: idx_credits_active_balance; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_credits_active_balance ON public.customer_credits USING btree (customer_id) WHERE ((status = 'active'::text) AND (remaining_amount > (0)::numeric));


--
-- Name: idx_credits_customer; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_credits_customer ON public.customer_credits USING btree (customer_id, status);


--
-- Name: idx_credits_escheat_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_credits_escheat_active ON public.customer_credits USING btree (tenant_id, last_activity_date) WHERE ((escheat_status = ANY (ARRAY['active'::text, 'dormancy_approaching'::text])) AND (remaining_amount > (0)::numeric));


--
-- Name: idx_credits_expiring; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_credits_expiring ON public.customer_credits USING btree (tenant_id, expires_date) WHERE ((expires_date IS NOT NULL) AND (status = 'active'::text));


--
-- Name: idx_credits_origin; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_credits_origin ON public.customer_credits USING btree (tenant_id, origin_type, issued_date DESC);


--
-- Name: idx_credits_source_payment; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_credits_source_payment ON public.customer_credits USING btree (source_payment_id) WHERE (source_payment_id IS NOT NULL);


--
-- Name: idx_credits_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_credits_tenant ON public.customer_credits USING btree (tenant_id);


--
-- Name: idx_crt_billing_run; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_crt_billing_run ON public.correction_run_targets USING btree (billing_run_id);


--
-- Name: idx_crt_correction_invoice; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_crt_correction_invoice ON public.correction_run_targets USING btree (correction_invoice_id) WHERE (correction_invoice_id IS NOT NULL);


--
-- Name: idx_crt_meter; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_crt_meter ON public.correction_run_targets USING btree (meter_id);


--
-- Name: idx_crt_tenant_open; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_crt_tenant_open ON public.correction_run_targets USING btree (tenant_id) WHERE (correction_invoice_id IS NULL);


--
-- Name: idx_crt_voided_invoice; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_crt_voided_invoice ON public.correction_run_targets USING btree (voided_invoice_id);


--
-- Name: idx_custom_fields_entity; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_custom_fields_entity ON public.custom_field_definitions USING btree (tenant_id, entity_type, status) WHERE (status = 'active'::text);


--
-- Name: idx_custom_fields_sensitive; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_custom_fields_sensitive ON public.custom_field_definitions USING btree (tenant_id, entity_type) WHERE ((is_sensitive = true) AND (status = 'active'::text));


--
-- Name: idx_custom_fields_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_custom_fields_tenant ON public.custom_field_definitions USING btree (tenant_id);


--
-- Name: idx_custom_location_types_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_custom_location_types_tenant ON public.custom_location_types USING btree (tenant_id, status) WHERE (status = 'active'::text);


--
-- Name: idx_customer_contacts_customer; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_customer_contacts_customer ON public.customer_contacts USING btree (customer_id);


--
-- Name: idx_customer_contacts_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_customer_contacts_tenant ON public.customer_contacts USING btree (tenant_id);


--
-- Name: idx_customers_billing_hold; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_customers_billing_hold ON public.customers USING btree (tenant_id, id) WHERE (billing_hold = true);


--
-- Name: idx_customers_consolidate; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_customers_consolidate ON public.customers USING btree (tenant_id, id) WHERE (consolidate_invoices = true);


--
-- Name: idx_customers_deposit; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_customers_deposit ON public.customers USING btree (tenant_id, deposit_status) WHERE (deposit_status = ANY (ARRAY['held'::text, 'partial_applied'::text, 'refund_pending'::text]));


--
-- Name: idx_customers_dob; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_customers_dob ON public.customers USING btree (tenant_id, date_of_birth) WHERE (date_of_birth IS NOT NULL);


--
-- Name: idx_customers_donation; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_customers_donation ON public.customers USING btree (tenant_id, donation_opt_in) WHERE (donation_opt_in = true);


--
-- Name: idx_customers_external_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_customers_external_id ON public.customers USING btree (tenant_id, external_id) WHERE (external_id IS NOT NULL);


--
-- Name: idx_customers_id_number; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_customers_id_number ON public.customers USING btree (tenant_id, id_issuing_state, id_number) WHERE (id_number IS NOT NULL);


--
-- Name: idx_customers_landlord; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_customers_landlord ON public.customers USING btree (landlord_customer_id) WHERE (landlord_customer_id IS NOT NULL);


--
-- Name: idx_customers_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_customers_name ON public.customers USING btree (tenant_id, last_name, first_name);


--
-- Name: idx_customers_protection; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_customers_protection ON public.customers USING btree (tenant_id, do_not_disconnect) WHERE (do_not_disconnect = true);


--
-- Name: idx_customers_search; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_customers_search ON public.customers USING gin ((((((((COALESCE(first_name, ''::text) || ' '::text) || COALESCE(last_name, ''::text)) || ' '::text) || COALESCE(company_name, ''::text)) || ' '::text) || customer_number)) public.gin_trgm_ops);


--
-- Name: idx_customers_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_customers_status ON public.customers USING btree (tenant_id, status);


--
-- Name: idx_customers_tax_exempt; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_customers_tax_exempt ON public.customers USING btree (tenant_id, is_tax_exempt) WHERE (is_tax_exempt = true);


--
-- Name: idx_customers_tax_expiry; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_customers_tax_expiry ON public.customers USING btree (tenant_id, tax_exemption_expiry_date) WHERE ((is_tax_exempt = true) AND (tax_exemption_expiry_date IS NOT NULL));


--
-- Name: idx_customers_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_customers_tenant ON public.customers USING btree (tenant_id);


--
-- Name: idx_cwa_low_confidence; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_cwa_low_confidence ON public.customer_winter_averages USING btree (tenant_id, confidence) WHERE (confidence = ANY (ARRAY['partial'::text, 'insufficient'::text]));


--
-- Name: idx_cwa_meter_year; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_cwa_meter_year ON public.customer_winter_averages USING btree (meter_id, winter_year DESC);


--
-- Name: idx_cwa_tenant_year; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_cwa_tenant_year ON public.customer_winter_averages USING btree (tenant_id, winter_year);


--
-- Name: idx_deployments_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_deployments_active ON public.meter_deployments USING btree (meter_id) WHERE (removal_date IS NULL);


--
-- Name: idx_deployments_location; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_deployments_location ON public.meter_deployments USING btree (location_id, install_date DESC);


--
-- Name: idx_deployments_meter; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_deployments_meter ON public.meter_deployments USING btree (meter_id, deployment_number);


--
-- Name: idx_deployments_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_deployments_tenant ON public.meter_deployments USING btree (tenant_id);


--
-- Name: idx_deployments_window; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_deployments_window ON public.meter_deployments USING btree (location_id, install_date, removal_date);


--
-- Name: idx_dunning_events_customer; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_dunning_events_customer ON public.dunning_events USING btree (customer_id, event_date DESC);


--
-- Name: idx_dunning_events_invoice; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_dunning_events_invoice ON public.dunning_events USING btree (invoice_id, event_date DESC);


--
-- Name: idx_dunning_events_scheduled; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_dunning_events_scheduled ON public.dunning_events USING btree (tenant_id, scheduled_date) WHERE ((event_type = 'shutoff_scheduled'::text) AND (scheduled_date IS NOT NULL));


--
-- Name: idx_dunning_events_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_dunning_events_tenant ON public.dunning_events USING btree (tenant_id, event_date DESC);


--
-- Name: idx_dunning_events_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_dunning_events_type ON public.dunning_events USING btree (tenant_id, event_type, event_date DESC);


--
-- Name: idx_endpoint_history_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_endpoint_history_active ON public.meter_endpoint_history USING btree (meter_id) WHERE (removal_date IS NULL);


--
-- Name: idx_endpoint_history_endpoint; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_endpoint_history_endpoint ON public.meter_endpoint_history USING btree (tenant_id, endpoint_id);


--
-- Name: idx_endpoint_history_meter; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_endpoint_history_meter ON public.meter_endpoint_history USING btree (meter_id, install_date DESC);


--
-- Name: idx_escheat_events_credit; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_escheat_events_credit ON public.escheatment_events USING btree (customer_credit_id, event_date DESC);


--
-- Name: idx_escheat_events_customer; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_escheat_events_customer ON public.escheatment_events USING btree (customer_id, event_date DESC);


--
-- Name: idx_escheat_events_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_escheat_events_tenant ON public.escheatment_events USING btree (tenant_id, event_date DESC);


--
-- Name: idx_escheat_events_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_escheat_events_type ON public.escheatment_events USING btree (tenant_id, event_type, event_date DESC);


--
-- Name: idx_franchise_fees_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_franchise_fees_active ON public.franchise_fee_rules USING btree (tenant_id, status, effective_date DESC) WHERE (status = 'active'::text);


--
-- Name: idx_franchise_fees_city; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_franchise_fees_city ON public.franchise_fee_rules USING btree (tenant_id, city_name, status) WHERE (status = 'active'::text);


--
-- Name: idx_franchise_fees_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_franchise_fees_tenant ON public.franchise_fee_rules USING btree (tenant_id);


--
-- Name: idx_import_jobs_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_import_jobs_active ON public.import_jobs USING btree (tenant_id, status) WHERE (status <> ALL (ARRAY['complete'::text, 'failed'::text, 'cancelled'::text]));


--
-- Name: idx_import_jobs_dry_run; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_import_jobs_dry_run ON public.import_jobs USING btree (tenant_id, created_at DESC) WHERE (is_dry_run = true);


--
-- Name: idx_import_jobs_template; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_import_jobs_template ON public.import_jobs USING btree (mapping_template_id) WHERE (mapping_template_id IS NOT NULL);


--
-- Name: idx_import_jobs_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_import_jobs_tenant ON public.import_jobs USING btree (tenant_id, created_at DESC);


--
-- Name: idx_import_jobs_user; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_import_jobs_user ON public.import_jobs USING btree (initiated_by, created_at DESC);


--
-- Name: idx_import_staging_errors; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_import_staging_errors ON public.import_staging USING btree (import_job_id) WHERE (status = ANY (ARRAY['failed_validation'::text, 'failed_fk_reference'::text]));


--
-- Name: idx_import_staging_job; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_import_staging_job ON public.import_staging USING btree (import_job_id);


--
-- Name: idx_import_staging_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_import_staging_status ON public.import_staging USING btree (import_job_id, status);


--
-- Name: idx_import_staging_target; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_import_staging_target ON public.import_staging USING btree (target_entity, target_id) WHERE (target_id IS NOT NULL);


--
-- Name: idx_interactions_customer; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_interactions_customer ON public.customer_interactions USING btree (customer_id, created_at DESC);


--
-- Name: idx_interactions_follow_up; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_interactions_follow_up ON public.customer_interactions USING btree (tenant_id, follow_up_date) WHERE ((follow_up_required = true) AND (status <> ALL (ARRAY['resolved'::text, 'closed'::text])));


--
-- Name: idx_interactions_reason; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_interactions_reason ON public.customer_interactions USING btree (tenant_id, reason);


--
-- Name: idx_interactions_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_interactions_status ON public.customer_interactions USING btree (tenant_id, status) WHERE (status <> ALL (ARRAY['resolved'::text, 'closed'::text]));


--
-- Name: idx_interactions_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_interactions_tenant ON public.customer_interactions USING btree (tenant_id, created_at DESC);


--
-- Name: idx_interactions_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_interactions_type ON public.customer_interactions USING btree (tenant_id, interaction_type);


--
-- Name: idx_invoice_apps_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_invoice_apps_active ON public.invoice_applications USING btree (invoice_id) WHERE (reversed_at IS NULL);


--
-- Name: idx_invoice_apps_invoice; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_invoice_apps_invoice ON public.invoice_applications USING btree (invoice_id);


--
-- Name: idx_invoice_apps_source; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_invoice_apps_source ON public.invoice_applications USING btree (source_type, source_id);


--
-- Name: idx_invoice_apps_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_invoice_apps_tenant ON public.invoice_applications USING btree (tenant_id);


--
-- Name: idx_invoice_events_invoice; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_invoice_events_invoice ON public.invoice_events USING btree (invoice_id, occurred_at DESC);


--
-- Name: idx_invoice_events_metadata_gin; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_invoice_events_metadata_gin ON public.invoice_events USING gin (metadata);


--
-- Name: idx_invoice_events_operator; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_invoice_events_operator ON public.invoice_events USING btree (operator_id, occurred_at DESC) WHERE (operator_id IS NOT NULL);


--
-- Name: idx_invoice_events_tenant_recent; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_invoice_events_tenant_recent ON public.invoice_events USING btree (tenant_id, occurred_at DESC);


--
-- Name: idx_invoice_events_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_invoice_events_type ON public.invoice_events USING btree (tenant_id, event_type, occurred_at DESC);


--
-- Name: idx_invoices_anomalies; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_invoices_anomalies ON public.invoices USING btree (tenant_id, billing_run_id) WHERE (has_anomalies = true);


--
-- Name: idx_invoices_consolidated_child; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_invoices_consolidated_child ON public.invoices USING btree (tenant_id, parent_invoice_id) WHERE (is_consolidated_child = true);


--
-- Name: idx_invoices_customer; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_invoices_customer ON public.invoices USING btree (customer_id);


--
-- Name: idx_invoices_delivery_failed; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_invoices_delivery_failed ON public.invoices USING btree (tenant_id, status) WHERE (delivery_failed_reason IS NOT NULL);


--
-- Name: idx_invoices_due; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_invoices_due ON public.invoices USING btree (tenant_id, due_date) WHERE (status = ANY (ARRAY['pending'::text, 'sent'::text, 'overdue'::text]));


--
-- Name: idx_invoices_dunning; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_invoices_dunning ON public.invoices USING btree (tenant_id, dunning_stage) WHERE (dunning_stage <> ALL (ARRAY['current'::text, 'resolved'::text]));


--
-- Name: idx_invoices_estimated; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_invoices_estimated ON public.invoices USING btree (tenant_id, has_estimated_reads) WHERE (has_estimated_reads = true);


--
-- Name: idx_invoices_held; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_invoices_held ON public.invoices USING btree (tenant_id, held_at DESC) WHERE (status = 'held'::text);


--
-- Name: idx_invoices_location; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_invoices_location ON public.invoices USING btree (location_id) WHERE (location_id IS NOT NULL);


--
-- Name: idx_invoices_parent; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_invoices_parent ON public.invoices USING btree (parent_invoice_id) WHERE (parent_invoice_id IS NOT NULL);


--
-- Name: idx_invoices_pdf_pending; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_invoices_pdf_pending ON public.invoices USING btree (tenant_id, status) WHERE ((pdf_url IS NULL) AND (status = 'pending'::text));


--
-- Name: idx_invoices_period; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_invoices_period ON public.invoices USING btree (tenant_id, billing_period);


--
-- Name: idx_invoices_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_invoices_status ON public.invoices USING btree (tenant_id, status);


--
-- Name: idx_invoices_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_invoices_tenant ON public.invoices USING btree (tenant_id);


--
-- Name: idx_invoices_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_invoices_type ON public.invoices USING btree (tenant_id, invoice_type, billing_period);


--
-- Name: idx_invoices_void_only; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_invoices_void_only ON public.invoices USING btree (tenant_id, location_id) WHERE ((status = 'void'::text) AND (void_rebill_expected = false));


--
-- Name: idx_invoices_voided; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_invoices_voided ON public.invoices USING btree (tenant_id, voided_at DESC) WHERE (status = 'void'::text);


--
-- Name: idx_ledger_customer; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ledger_customer ON public.account_ledger USING btree (customer_id, transaction_date DESC);


--
-- Name: idx_ledger_location; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ledger_location ON public.account_ledger USING btree (location_id, transaction_date DESC) WHERE (location_id IS NOT NULL);


--
-- Name: idx_ledger_reference; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ledger_reference ON public.account_ledger USING btree (reference_type, reference_id) WHERE (reference_type IS NOT NULL);


--
-- Name: idx_ledger_tenant_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ledger_tenant_date ON public.account_ledger USING btree (tenant_id, transaction_date DESC);


--
-- Name: idx_ledger_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ledger_type ON public.account_ledger USING btree (tenant_id, transaction_type, transaction_date DESC);


--
-- Name: idx_ledger_void_reversal; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ledger_void_reversal ON public.account_ledger USING btree (reference_id) WHERE (reference_type = 'invoice_void'::text);


--
-- Name: idx_line_items_charge_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_line_items_charge_type ON public.invoice_line_items USING btree (tenant_id, charge_type);


--
-- Name: idx_line_items_invoice; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_line_items_invoice ON public.invoice_line_items USING btree (invoice_id);


--
-- Name: idx_line_items_meter; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_line_items_meter ON public.invoice_line_items USING btree (meter_id) WHERE (meter_id IS NOT NULL);


--
-- Name: idx_line_items_partial; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_line_items_partial ON public.invoice_line_items USING btree (invoice_id) WHERE (coverage_start IS NOT NULL);


--
-- Name: idx_line_items_rate_item; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_line_items_rate_item ON public.invoice_line_items USING btree (rate_item_id) WHERE (rate_item_id IS NOT NULL);


--
-- Name: idx_line_items_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_line_items_tenant ON public.invoice_line_items USING btree (tenant_id);


--
-- Name: idx_locations_cycle; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_locations_cycle ON public.service_locations USING btree (billing_cycle_id) WHERE (billing_cycle_id IS NOT NULL);


--
-- Name: idx_mapping_templates_source; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_mapping_templates_source ON public.import_mapping_templates USING btree (tenant_id, source_system) WHERE (source_system IS NOT NULL);


--
-- Name: idx_mapping_templates_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_mapping_templates_tenant ON public.import_mapping_templates USING btree (tenant_id);


--
-- Name: idx_mapping_templates_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_mapping_templates_type ON public.import_mapping_templates USING btree (tenant_id, import_type, status) WHERE (status = 'active'::text);


--
-- Name: idx_meter_photos_ai_low_conf; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_meter_photos_ai_low_conf ON public.meter_photos USING btree (tenant_id, ai_confidence) WHERE ((ai_confidence IS NOT NULL) AND (ai_confidence < 0.85));


--
-- Name: idx_meter_photos_ai_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_meter_photos_ai_status ON public.meter_photos USING btree (tenant_id, ai_extraction_status) WHERE (ai_extraction_status = ANY (ARRAY['pending'::text, 'low_confidence'::text, 'failed'::text]));


--
-- Name: idx_meter_photos_meter; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_meter_photos_meter ON public.meter_photos USING btree (meter_id, created_at DESC);


--
-- Name: idx_meter_photos_reading; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_meter_photos_reading ON public.meter_photos USING btree (meter_reading_id) WHERE (meter_reading_id IS NOT NULL);


--
-- Name: idx_meter_photos_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_meter_photos_tenant ON public.meter_photos USING btree (tenant_id);


--
-- Name: idx_meter_photos_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_meter_photos_type ON public.meter_photos USING btree (meter_id, photo_type);


--
-- Name: idx_meter_readings_rcm; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_meter_readings_rcm ON public.meter_readings USING btree (read_cycle_meter_id) WHERE (read_cycle_meter_id IS NOT NULL);


--
-- Name: idx_meter_readings_reader_confirmed; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_meter_readings_reader_confirmed ON public.meter_readings USING btree (confirmed_by_field_reader_id, confirmed_by_field_reader_at DESC) WHERE (confirmed_by_field_reader_at IS NOT NULL);


--
-- Name: idx_meters_ami_sync; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_meters_ami_sync ON public.meters USING btree (tenant_id, ami_sync_status) WHERE (read_type = ANY (ARRAY['ami'::text, 'amr'::text]));


--
-- Name: idx_meters_estimation_blocked; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_meters_estimation_blocked ON public.meters USING btree (tenant_id, id) WHERE (estimation_blocked = true);


--
-- Name: idx_meters_external_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_meters_external_id ON public.meters USING btree (tenant_id, external_id) WHERE (external_id IS NOT NULL);


--
-- Name: idx_meters_location; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_meters_location ON public.meters USING btree (location_id);


--
-- Name: idx_meters_replaces; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_meters_replaces ON public.meters USING btree (replaces_meter_id) WHERE (replaces_meter_id IS NOT NULL);


--
-- Name: idx_meters_route; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_meters_route ON public.meters USING btree (route_id, route_sequence) WHERE (route_id IS NOT NULL);


--
-- Name: idx_meters_serial; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_meters_serial ON public.meters USING btree (tenant_id, serial_number) WHERE (serial_number IS NOT NULL);


--
-- Name: idx_meters_service_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_meters_service_type ON public.meters USING btree (tenant_id, service_type);


--
-- Name: idx_meters_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_meters_status ON public.meters USING btree (tenant_id, status);


--
-- Name: idx_meters_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_meters_tenant ON public.meters USING btree (tenant_id);


--
-- Name: idx_meters_test_due; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_meters_test_due ON public.meters USING btree (tenant_id, next_test_due_date) WHERE ((next_test_due_date IS NOT NULL) AND (status = 'active'::text));


--
-- Name: idx_meters_virtual; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_meters_virtual ON public.meters USING btree (derives_from_meter_id) WHERE (derives_from_meter_id IS NOT NULL);


--
-- Name: idx_meters_warehouse; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_meters_warehouse ON public.meters USING btree (tenant_id, warehouse_location) WHERE (warehouse_location IS NOT NULL);


--
-- Name: idx_meters_warranty; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_meters_warranty ON public.meters USING btree (tenant_id, warranty_expiration) WHERE (warranty_expiration IS NOT NULL);


--
-- Name: idx_payment_health_autopay_failing; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_payment_health_autopay_failing ON public.payment_health_statistics USING btree (tenant_id, auto_pay_failure_streak) WHERE (auto_pay_failure_streak = true);


--
-- Name: idx_payment_health_customer; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_payment_health_customer ON public.payment_health_statistics USING btree (customer_id);


--
-- Name: idx_payment_health_method_expiring; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_payment_health_method_expiring ON public.payment_health_statistics USING btree (tenant_id, payment_method_expiring_soon) WHERE (payment_method_expiring_soon = true);


--
-- Name: idx_payment_health_nsf; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_payment_health_nsf ON public.payment_health_statistics USING btree (tenant_id, multiple_nsf_pattern_90d) WHERE (multiple_nsf_pattern_90d = true);


--
-- Name: idx_payment_health_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_payment_health_tenant ON public.payment_health_statistics USING btree (tenant_id);


--
-- Name: idx_payment_methods_customer; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_payment_methods_customer ON public.payment_methods USING btree (customer_id, is_active);


--
-- Name: idx_payment_methods_default; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_payment_methods_default ON public.payment_methods USING btree (customer_id) WHERE ((is_default = true) AND (is_active = true));


--
-- Name: idx_payment_methods_expiring; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_payment_methods_expiring ON public.payment_methods USING btree (tenant_id, expiry_year, expiry_month) WHERE ((is_active = true) AND (method_type = ANY (ARRAY['credit_card'::text, 'debit_card'::text])));


--
-- Name: idx_payment_methods_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_payment_methods_tenant ON public.payment_methods USING btree (tenant_id);


--
-- Name: idx_payments_channel; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_payments_channel ON public.payments USING btree (tenant_id, channel, payment_date DESC);


--
-- Name: idx_payments_customer; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_payments_customer ON public.payments USING btree (customer_id, payment_date DESC);


--
-- Name: idx_payments_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_payments_date ON public.payments USING btree (tenant_id, payment_date DESC);


--
-- Name: idx_payments_deposits; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_payments_deposits ON public.payments USING btree (customer_id) WHERE ((is_deposit = true) AND (deposit_status <> 'refunded'::text));


--
-- Name: idx_payments_method; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_payments_method ON public.payments USING btree (payment_method_id) WHERE (payment_method_id IS NOT NULL);


--
-- Name: idx_payments_nsf; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_payments_nsf ON public.payments USING btree (tenant_id, nsf_date) WHERE (status = 'nsf'::text);


--
-- Name: idx_payments_provider_txn; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_payments_provider_txn ON public.payments USING btree (provider_transaction_id) WHERE (provider_transaction_id IS NOT NULL);


--
-- Name: idx_payments_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_payments_status ON public.payments USING btree (tenant_id, status);


--
-- Name: idx_payments_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_payments_tenant ON public.payments USING btree (tenant_id);


--
-- Name: idx_payments_unapplied; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_payments_unapplied ON public.payments USING btree (customer_id) WHERE (unapplied_amount > (0)::numeric);


--
-- Name: idx_provider_logs_correlation; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_provider_logs_correlation ON public.payment_provider_logs USING btree (correlation_id) WHERE (correlation_id IS NOT NULL);


--
-- Name: idx_provider_logs_customer; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_provider_logs_customer ON public.payment_provider_logs USING btree (customer_id, created_at DESC) WHERE (customer_id IS NOT NULL);


--
-- Name: idx_provider_logs_errors; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_provider_logs_errors ON public.payment_provider_logs USING btree (tenant_id, created_at DESC) WHERE (is_error = true);


--
-- Name: idx_provider_logs_payment; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_provider_logs_payment ON public.payment_provider_logs USING btree (payment_id) WHERE (payment_id IS NOT NULL);


--
-- Name: idx_provider_logs_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_provider_logs_tenant ON public.payment_provider_logs USING btree (tenant_id, created_at DESC);


--
-- Name: idx_rate_item_deps_base; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_rate_item_deps_base ON public.rate_item_dependencies USING btree (base_rate_item_id);


--
-- Name: idx_rate_item_deps_dependent; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_rate_item_deps_dependent ON public.rate_item_dependencies USING btree (dependent_rate_item_id);


--
-- Name: idx_rate_item_deps_schedule; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_rate_item_deps_schedule ON public.rate_item_dependencies USING btree (rate_schedule_id);


--
-- Name: idx_rate_item_history_current; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_rate_item_history_current ON public.rate_item_history USING btree (rate_item_id) WHERE (end_date IS NULL);


--
-- Name: idx_rate_item_history_item; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_rate_item_history_item ON public.rate_item_history USING btree (rate_item_id, effective_date DESC);


--
-- Name: idx_rate_item_history_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_rate_item_history_tenant ON public.rate_item_history USING btree (tenant_id, effective_date DESC);


--
-- Name: idx_rate_items_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_rate_items_active ON public.rate_items USING btree (tenant_id, status) WHERE (status = 'active'::text);


--
-- Name: idx_rate_items_code; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_rate_items_code ON public.rate_items USING btree (tenant_id, item_code);


--
-- Name: idx_rate_items_service; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_rate_items_service ON public.rate_items USING btree (tenant_id, service_type, status) WHERE (status = 'active'::text);


--
-- Name: idx_rate_items_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_rate_items_tenant ON public.rate_items USING btree (tenant_id);


--
-- Name: idx_rate_sched_items_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_rate_sched_items_active ON public.rate_schedule_items USING btree (rate_schedule_id, status) WHERE (status = 'active'::text);


--
-- Name: idx_rate_sched_items_item; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_rate_sched_items_item ON public.rate_schedule_items USING btree (rate_item_id);


--
-- Name: idx_rate_sched_items_schedule; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_rate_sched_items_schedule ON public.rate_schedule_items USING btree (rate_schedule_id, display_order);


--
-- Name: idx_rate_sched_items_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_rate_sched_items_tenant ON public.rate_schedule_items USING btree (tenant_id);


--
-- Name: idx_rate_schedules_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_rate_schedules_active ON public.rate_schedules USING btree (tenant_id, service_type, status) WHERE (status = 'active'::text);


--
-- Name: idx_rate_schedules_customer_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_rate_schedules_customer_type ON public.rate_schedules USING btree (tenant_id, customer_type);


--
-- Name: idx_rate_schedules_franchise; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_rate_schedules_franchise ON public.rate_schedules USING btree (tenant_id, franchise_city) WHERE (franchise_city IS NOT NULL);


--
-- Name: idx_rate_schedules_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_rate_schedules_tenant ON public.rate_schedules USING btree (tenant_id);


--
-- Name: idx_rci_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_rci_active ON public.read_cycle_instances USING btree (tenant_id, read_window_start) WHERE (status = ANY (ARRAY['issued'::text, 'reading'::text]));


--
-- Name: idx_rci_billing_run; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_rci_billing_run ON public.read_cycle_instances USING btree (billing_run_id) WHERE (billing_run_id IS NOT NULL);


--
-- Name: idx_rci_cycle_period; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_rci_cycle_period ON public.read_cycle_instances USING btree (billing_cycle_id, period);


--
-- Name: idx_rci_tenant_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_rci_tenant_status ON public.read_cycle_instances USING btree (tenant_id, status);


--
-- Name: idx_rcm_instance; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_rcm_instance ON public.read_cycle_meters USING btree (read_cycle_instance_id, sequence_in_route);


--
-- Name: idx_rcm_meter_history; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_rcm_meter_history ON public.read_cycle_meters USING btree (meter_id, created_at DESC);


--
-- Name: idx_rcm_pending_by_reader; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_rcm_pending_by_reader ON public.read_cycle_meters USING btree (tenant_id, assigned_reader_user_id, read_status) WHERE (read_status = ANY (ARRAY['pending'::text, 'reading'::text]));


--
-- Name: idx_rcm_reading; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_rcm_reading ON public.read_cycle_meters USING btree (captured_reading_id) WHERE (captured_reading_id IS NOT NULL);


--
-- Name: idx_rcm_route; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_rcm_route ON public.read_cycle_meters USING btree (read_route_id) WHERE (read_route_id IS NOT NULL);


--
-- Name: idx_rcm_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_rcm_status ON public.read_cycle_meters USING btree (tenant_id, read_status);


--
-- Name: idx_read_routes_assigned_user; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_read_routes_assigned_user ON public.read_routes USING btree (assigned_to_user_id) WHERE (assigned_to_user_id IS NOT NULL);


--
-- Name: idx_read_routes_cycle; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_read_routes_cycle ON public.read_routes USING btree (default_billing_cycle_id) WHERE (default_billing_cycle_id IS NOT NULL);


--
-- Name: idx_read_routes_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_read_routes_tenant ON public.read_routes USING btree (tenant_id, status) WHERE (status = 'active'::text);


--
-- Name: idx_readings_access_issues; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_readings_access_issues ON public.meter_readings USING btree (tenant_id, access_status, reading_date DESC) WHERE (access_status <> 'accessed'::text);


--
-- Name: idx_readings_amr_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_readings_amr_status ON public.meter_readings USING btree (tenant_id, amr_read_status) WHERE ((amr_read_status IS NOT NULL) AND (amr_read_status <> 'success'::text));


--
-- Name: idx_readings_approved_for_billing; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_readings_approved_for_billing ON public.meter_readings USING btree (tenant_id, billing_cycle_id) WHERE (validation_status = 'approved'::text);


--
-- Name: idx_readings_assigned; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_readings_assigned ON public.meter_readings USING btree (assigned_to_user_id, validation_status) WHERE ((assigned_to_user_id IS NOT NULL) AND (validation_status = ANY (ARRAY['pending_review'::text, 'reviewed_with_exception'::text])));


--
-- Name: idx_readings_correction_pending; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_readings_correction_pending ON public.meter_readings USING btree (meter_id) WHERE ((triggers_correction_workflow = true) AND (billing_period_locked = false));


--
-- Name: idx_readings_cycle; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_readings_cycle ON public.meter_readings USING btree (billing_cycle_id, reading_date DESC) WHERE (billing_cycle_id IS NOT NULL);


--
-- Name: idx_readings_disputed; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_readings_disputed ON public.meter_readings USING btree (tenant_id, status) WHERE (status = ANY (ARRAY['disputed'::text, 'under_review'::text]));


--
-- Name: idx_readings_endpoint; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_readings_endpoint ON public.meter_readings USING btree (endpoint_id, reading_date DESC) WHERE (endpoint_id IS NOT NULL);


--
-- Name: idx_readings_followup; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_readings_followup ON public.meter_readings USING btree (tenant_id, followup_priority, reading_date DESC) WHERE (requires_followup = true);


--
-- Name: idx_readings_import; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_readings_import ON public.meter_readings USING btree (import_job_id) WHERE (import_job_id IS NOT NULL);


--
-- Name: idx_readings_incoming; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_readings_incoming ON public.meter_readings USING btree (transition_incoming_customer_id) WHERE (transition_incoming_customer_id IS NOT NULL);


--
-- Name: idx_readings_locked; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_readings_locked ON public.meter_readings USING btree (locked_by_billing_run_id) WHERE (billing_period_locked = true);


--
-- Name: idx_readings_meter_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_readings_meter_date ON public.meter_readings USING btree (meter_id, reading_date DESC);


--
-- Name: idx_readings_meter_register; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_readings_meter_register ON public.meter_readings USING btree (meter_id, register_type, reading_date DESC);


--
-- Name: idx_readings_outgoing; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_readings_outgoing ON public.meter_readings USING btree (transition_outgoing_customer_id) WHERE (transition_outgoing_customer_id IS NOT NULL);


--
-- Name: idx_readings_purpose; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_readings_purpose ON public.meter_readings USING btree (tenant_id, reading_purpose, reading_date DESC) WHERE (reading_purpose <> 'regular_cycle'::text);


--
-- Name: idx_readings_quality; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_readings_quality ON public.meter_readings USING btree (tenant_id, quality_flag) WHERE (quality_flag <> 'normal'::text);


--
-- Name: idx_readings_replaced; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_readings_replaced ON public.meter_readings USING btree (replaced_by_reading_id) WHERE (replaced_by_reading_id IS NOT NULL);


--
-- Name: idx_readings_replaces_read; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_readings_replaces_read ON public.meter_readings USING btree (replaces_read_id) WHERE (replaces_read_id IS NOT NULL);


--
-- Name: idx_readings_review_queue; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_readings_review_queue ON public.meter_readings USING btree (tenant_id, validation_status, reading_date) WHERE (validation_status = ANY (ARRAY['pending_review'::text, 'reviewed_with_exception'::text]));


--
-- Name: idx_readings_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_readings_status ON public.meter_readings USING btree (tenant_id, status) WHERE (status <> 'active'::text);


--
-- Name: idx_readings_tamper; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_readings_tamper ON public.meter_readings USING btree (tenant_id, reading_date DESC) WHERE ((tamper_count_1_changed_flag = true) OR (tamper_count_2_changed_flag = true));


--
-- Name: idx_readings_tenant_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_readings_tenant_date ON public.meter_readings USING btree (tenant_id, reading_date DESC);


--
-- Name: idx_readings_transitions; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_readings_transitions ON public.meter_readings USING btree (tenant_id, reading_date DESC) WHERE (is_service_transition = true);


--
-- Name: idx_readings_void_released; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_readings_void_released ON public.meter_readings USING btree (meter_id, reading_date) WHERE (validation_status = 'void_released'::text);


--
-- Name: idx_readings_voided_from_invoice; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_readings_voided_from_invoice ON public.meter_readings USING btree (voided_from_invoice_id) WHERE (voided_from_invoice_id IS NOT NULL);


--
-- Name: idx_service_locations_address; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_service_locations_address ON public.service_locations USING gin ((((((address_line1 || ' '::text) || city) || ' '::text) || zip)) public.gin_trgm_ops);


--
-- Name: idx_service_locations_city_limits; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_service_locations_city_limits ON public.service_locations USING btree (tenant_id, inside_city_limits);


--
-- Name: idx_service_locations_community; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_service_locations_community ON public.service_locations USING btree (community_id) WHERE (community_id IS NOT NULL);


--
-- Name: idx_service_locations_county; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_service_locations_county ON public.service_locations USING btree (tenant_id, state, county) WHERE (county IS NOT NULL);


--
-- Name: idx_service_locations_customer; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_service_locations_customer ON public.service_locations USING btree (customer_id);


--
-- Name: idx_service_locations_external_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_service_locations_external_id ON public.service_locations USING btree (tenant_id, external_id) WHERE (external_id IS NOT NULL);


--
-- Name: idx_service_locations_franchise; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_service_locations_franchise ON public.service_locations USING btree (tenant_id, franchise_city) WHERE (franchise_city IS NOT NULL);


--
-- Name: idx_service_locations_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_service_locations_status ON public.service_locations USING btree (tenant_id, status);


--
-- Name: idx_service_locations_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_service_locations_tenant ON public.service_locations USING btree (tenant_id);


--
-- Name: idx_service_orders_awaiting; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_service_orders_awaiting ON public.service_orders USING btree (tenant_id, completed_at) WHERE (status = 'awaiting_billing_action'::text);


--
-- Name: idx_service_orders_customer; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_service_orders_customer ON public.service_orders USING btree (customer_id) WHERE (customer_id IS NOT NULL);


--
-- Name: idx_service_orders_external; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_service_orders_external ON public.service_orders USING btree (tenant_id, external_system, external_order_id) WHERE (external_order_id IS NOT NULL);


--
-- Name: idx_service_orders_followup; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_service_orders_followup ON public.service_orders USING btree (tenant_id, created_at DESC) WHERE (status = 'requires_followup'::text);


--
-- Name: idx_service_orders_location; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_service_orders_location ON public.service_orders USING btree (location_id) WHERE (location_id IS NOT NULL);


--
-- Name: idx_service_orders_meter; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_service_orders_meter ON public.service_orders USING btree (meter_id) WHERE (meter_id IS NOT NULL);


--
-- Name: idx_service_orders_open; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_service_orders_open ON public.service_orders USING btree (tenant_id, scheduled_date) WHERE (status = ANY (ARRAY['open'::text, 'scheduled'::text, 'dispatched'::text, 'in_progress'::text, 'on_hold'::text]));


--
-- Name: idx_service_orders_parent; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_service_orders_parent ON public.service_orders USING btree (parent_order_id) WHERE (parent_order_id IS NOT NULL);


--
-- Name: idx_service_orders_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_service_orders_status ON public.service_orders USING btree (tenant_id, status);


--
-- Name: idx_service_orders_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_service_orders_tenant ON public.service_orders USING btree (tenant_id);


--
-- Name: idx_service_orders_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_service_orders_type ON public.service_orders USING btree (tenant_id, order_type, status);


--
-- Name: idx_suggestions_entity; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_suggestions_entity ON public.ai_suggestions USING btree (primary_entity_type, primary_entity_id);


--
-- Name: idx_suggestions_expiring; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_suggestions_expiring ON public.ai_suggestions USING btree (tenant_id, expires_at) WHERE ((status = 'pending'::text) AND (expires_at IS NOT NULL));


--
-- Name: idx_suggestions_pending; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_suggestions_pending ON public.ai_suggestions USING btree (tenant_id, created_at DESC) WHERE (status = 'pending'::text);


--
-- Name: idx_suggestions_session; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_suggestions_session ON public.ai_suggestions USING btree (session_id);


--
-- Name: idx_suggestions_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_suggestions_tenant ON public.ai_suggestions USING btree (tenant_id, status, created_at DESC);


--
-- Name: idx_suggestions_user; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_suggestions_user ON public.ai_suggestions USING btree (proposed_by_user_id, created_at DESC);


--
-- Name: idx_tax_exemptions_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tax_exemptions_active ON public.customer_tax_exemptions USING btree (customer_id, effective_start, effective_end) WHERE (status = 'active'::text);


--
-- Name: idx_tax_exemptions_customer; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tax_exemptions_customer ON public.customer_tax_exemptions USING btree (customer_id, status);


--
-- Name: idx_tax_exemptions_expiring; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tax_exemptions_expiring ON public.customer_tax_exemptions USING btree (tenant_id, effective_end) WHERE ((status = 'active'::text) AND (effective_end IS NOT NULL));


--
-- Name: idx_tax_exemptions_pending; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tax_exemptions_pending ON public.customer_tax_exemptions USING btree (tenant_id, created_at DESC) WHERE (status = 'pending_verification'::text);


--
-- Name: idx_tax_exemptions_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tax_exemptions_tenant ON public.customer_tax_exemptions USING btree (tenant_id);


--
-- Name: idx_tenants_slug; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tenants_slug ON public.tenants USING btree (slug);


--
-- Name: idx_tenants_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tenants_status ON public.tenants USING btree (status);


--
-- Name: idx_tool_calls_audit; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tool_calls_audit ON public.ai_tool_calls USING btree (audit_log_id, sequence_number);


--
-- Name: idx_tool_calls_errors; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tool_calls_errors ON public.ai_tool_calls USING btree (tenant_id, created_at DESC) WHERE (status = 'error'::text);


--
-- Name: idx_tool_calls_session; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tool_calls_session ON public.ai_tool_calls USING btree (session_id);


--
-- Name: idx_tool_calls_tenant_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tool_calls_tenant_name ON public.ai_tool_calls USING btree (tenant_id, tool_name, created_at DESC);


--
-- Name: idx_tool_calls_writes; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tool_calls_writes ON public.ai_tool_calls USING btree (tenant_id, created_at DESC) WHERE (tool_category = 'write'::text);


--
-- Name: idx_usage_stats_meter; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_usage_stats_meter ON public.usage_statistics USING btree (meter_id);


--
-- Name: idx_usage_stats_quality; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_usage_stats_quality ON public.usage_statistics USING btree (tenant_id, data_quality_flag);


--
-- Name: idx_usage_stats_stale; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_usage_stats_stale ON public.usage_statistics USING btree (tenant_id, days_since_last_read) WHERE (days_since_last_read > 45);


--
-- Name: idx_usage_stats_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_usage_stats_tenant ON public.usage_statistics USING btree (tenant_id);


--
-- Name: idx_users_email; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_users_email ON public.users USING btree (email);


--
-- Name: idx_users_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_users_tenant ON public.users USING btree (tenant_id);


--
-- Name: idx_wna_adj_pending; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_wna_adj_pending ON public.wna_monthly_adjustments USING btree (tenant_id, status) WHERE (status = 'pending'::text);


--
-- Name: idx_wna_adj_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_wna_adj_tenant ON public.wna_monthly_adjustments USING btree (tenant_id, billing_month DESC);


--
-- Name: idx_wna_adj_zone_month; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_wna_adj_zone_month ON public.wna_monthly_adjustments USING btree (wna_zone_id, billing_month DESC);


--
-- Name: idx_wna_zones_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_wna_zones_active ON public.wna_zones USING btree (tenant_id, status) WHERE (status = 'active'::text);


--
-- Name: idx_wna_zones_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_wna_zones_tenant ON public.wna_zones USING btree (tenant_id);


--
-- Name: rate_item_history_archive_rate_item_id_effective_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX rate_item_history_archive_rate_item_id_effective_date_idx ON public.rate_item_history_archive USING btree (rate_item_id, effective_date DESC);


--
-- Name: rate_item_history_archive_rate_item_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX rate_item_history_archive_rate_item_id_idx ON public.rate_item_history_archive USING btree (rate_item_id) WHERE (end_date IS NULL);


--
-- Name: rate_item_history_archive_tenant_id_effective_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX rate_item_history_archive_tenant_id_effective_date_idx ON public.rate_item_history_archive USING btree (tenant_id, effective_date DESC);


--
-- Name: adhoc_charges set_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.adhoc_charges FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();


--
-- Name: ai_sessions set_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.ai_sessions FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();


--
-- Name: ai_suggestions set_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.ai_suggestions FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();


--
-- Name: anomalies set_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.anomalies FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();


--
-- Name: auto_pay_settings set_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.auto_pay_settings FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();


--
-- Name: bill_messages set_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.bill_messages FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();


--
-- Name: billing_cycles set_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.billing_cycles FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();


--
-- Name: billing_runs set_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.billing_runs FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();


--
-- Name: communities set_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.communities FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();


--
-- Name: correction_run_targets set_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.correction_run_targets FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();


--
-- Name: custom_field_definitions set_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.custom_field_definitions FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();


--
-- Name: custom_location_types set_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.custom_location_types FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();


--
-- Name: customer_contacts set_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.customer_contacts FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();


--
-- Name: customer_credits set_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.customer_credits FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();


--
-- Name: customer_interactions set_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.customer_interactions FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();


--
-- Name: customer_tax_exemptions set_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.customer_tax_exemptions FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();


--
-- Name: customer_winter_averages set_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.customer_winter_averages FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();


--
-- Name: customers set_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.customers FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();


--
-- Name: franchise_fee_rules set_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.franchise_fee_rules FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();


--
-- Name: import_column_mappings set_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.import_column_mappings FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();


--
-- Name: import_jobs set_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.import_jobs FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();


--
-- Name: import_mapping_templates set_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.import_mapping_templates FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();


--
-- Name: invoices set_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.invoices FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();


--
-- Name: meter_deployments set_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.meter_deployments FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();


--
-- Name: meters set_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.meters FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();


--
-- Name: payment_methods set_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.payment_methods FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();


--
-- Name: payments set_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.payments FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();


--
-- Name: rate_items set_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.rate_items FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();


--
-- Name: rate_schedule_items set_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.rate_schedule_items FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();


--
-- Name: rate_schedules set_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.rate_schedules FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();


--
-- Name: read_cycle_instances set_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.read_cycle_instances FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();


--
-- Name: read_cycle_meters set_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.read_cycle_meters FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();


--
-- Name: read_routes set_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.read_routes FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();


--
-- Name: service_locations set_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.service_locations FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();


--
-- Name: service_orders set_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.service_orders FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();


--
-- Name: tenants set_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.tenants FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();


--
-- Name: users set_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.users FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();


--
-- Name: wna_monthly_adjustments set_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.wna_monthly_adjustments FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();


--
-- Name: wna_zones set_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.wna_zones FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();


--
-- Name: account_ledger trg_compute_ledger_running_balance; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_compute_ledger_running_balance BEFORE INSERT ON public.account_ledger FOR EACH ROW EXECUTE FUNCTION public.compute_ledger_running_balance();


--
-- Name: customers trg_enforce_billing_hold_metadata; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_enforce_billing_hold_metadata BEFORE INSERT OR UPDATE ON public.customers FOR EACH ROW EXECUTE FUNCTION public.enforce_billing_hold_metadata();


--
-- Name: invoices trg_enforce_invoice_hold_metadata; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_enforce_invoice_hold_metadata BEFORE INSERT OR UPDATE ON public.invoices FOR EACH ROW EXECUTE FUNCTION public.enforce_invoice_hold_metadata();


--
-- Name: meters trg_enforce_meter_estimation_block_metadata; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_enforce_meter_estimation_block_metadata BEFORE INSERT OR UPDATE ON public.meters FOR EACH ROW EXECUTE FUNCTION public.enforce_meter_estimation_block_metadata();


--
-- Name: meter_readings trg_enforce_reading_validation_workflow; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_enforce_reading_validation_workflow BEFORE UPDATE ON public.meter_readings FOR EACH ROW EXECUTE FUNCTION public.enforce_reading_validation_workflow();


--
-- Name: ai_tool_calls trg_enforce_write_tool_suggestion; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_enforce_write_tool_suggestion BEFORE INSERT OR UPDATE ON public.ai_tool_calls FOR EACH ROW EXECUTE FUNCTION public.enforce_write_tool_requires_suggestion();


--
-- Name: invoice_events trg_invoice_events_no_future; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_invoice_events_no_future BEFORE INSERT OR UPDATE ON public.invoice_events FOR EACH ROW EXECUTE FUNCTION public.reject_future_invoice_event();


--
-- Name: invoice_events trg_invoice_events_sync_tenant; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_invoice_events_sync_tenant BEFORE INSERT ON public.invoice_events FOR EACH ROW EXECUTE FUNCTION public.sync_invoice_event_tenant_id();


--
-- Name: meter_readings trg_populate_reading_calculations; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_populate_reading_calculations BEFORE INSERT ON public.meter_readings FOR EACH ROW EXECUTE FUNCTION public.populate_reading_calculations();


--
-- Name: meters trg_sync_meter_deployments; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_sync_meter_deployments AFTER INSERT OR UPDATE ON public.meters FOR EACH ROW EXECUTE FUNCTION public.sync_meter_deployments();


--
-- Name: account_ledger account_ledger_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.account_ledger
    ADD CONSTRAINT account_ledger_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- Name: account_ledger account_ledger_customer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.account_ledger
    ADD CONSTRAINT account_ledger_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.customers(id);


--
-- Name: account_ledger account_ledger_location_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.account_ledger
    ADD CONSTRAINT account_ledger_location_id_fkey FOREIGN KEY (location_id) REFERENCES public.service_locations(id);


--
-- Name: account_ledger account_ledger_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.account_ledger
    ADD CONSTRAINT account_ledger_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;


--
-- Name: adhoc_charges adhoc_charges_approved_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.adhoc_charges
    ADD CONSTRAINT adhoc_charges_approved_by_fkey FOREIGN KEY (approved_by) REFERENCES public.users(id);


--
-- Name: adhoc_charges adhoc_charges_billed_by_billing_run_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.adhoc_charges
    ADD CONSTRAINT adhoc_charges_billed_by_billing_run_id_fkey FOREIGN KEY (billed_by_billing_run_id) REFERENCES public.billing_runs(id);


--
-- Name: adhoc_charges adhoc_charges_billed_on_line_item_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.adhoc_charges
    ADD CONSTRAINT adhoc_charges_billed_on_line_item_fk FOREIGN KEY (billed_on_line_item_id) REFERENCES public.invoice_line_items(id) ON DELETE SET NULL;


--
-- Name: adhoc_charges adhoc_charges_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.adhoc_charges
    ADD CONSTRAINT adhoc_charges_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- Name: adhoc_charges adhoc_charges_customer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.adhoc_charges
    ADD CONSTRAINT adhoc_charges_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.customers(id);


--
-- Name: adhoc_charges adhoc_charges_location_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.adhoc_charges
    ADD CONSTRAINT adhoc_charges_location_id_fkey FOREIGN KEY (location_id) REFERENCES public.service_locations(id);


--
-- Name: adhoc_charges adhoc_charges_meter_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.adhoc_charges
    ADD CONSTRAINT adhoc_charges_meter_id_fkey FOREIGN KEY (meter_id) REFERENCES public.meters(id);


--
-- Name: adhoc_charges adhoc_charges_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.adhoc_charges
    ADD CONSTRAINT adhoc_charges_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;


--
-- Name: adhoc_charges adhoc_charges_triggered_by_reading_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.adhoc_charges
    ADD CONSTRAINT adhoc_charges_triggered_by_reading_id_fkey FOREIGN KEY (triggered_by_reading_id) REFERENCES public.meter_readings(id);


--
-- Name: adhoc_charges adhoc_charges_voided_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.adhoc_charges
    ADD CONSTRAINT adhoc_charges_voided_by_fkey FOREIGN KEY (voided_by) REFERENCES public.users(id);


--
-- Name: adhoc_charges adhoc_charges_voided_from_invoice_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.adhoc_charges
    ADD CONSTRAINT adhoc_charges_voided_from_invoice_id_fkey FOREIGN KEY (voided_from_invoice_id) REFERENCES public.invoices(id);


--
-- Name: adhoc_charges adhoc_charges_waived_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.adhoc_charges
    ADD CONSTRAINT adhoc_charges_waived_by_fkey FOREIGN KEY (waived_by) REFERENCES public.users(id);


--
-- Name: ai_audit_log ai_audit_log_parent_audit_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_audit_log
    ADD CONSTRAINT ai_audit_log_parent_audit_id_fkey FOREIGN KEY (parent_audit_id) REFERENCES public.ai_audit_log(id);


--
-- Name: ai_audit_log ai_audit_log_session_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_audit_log
    ADD CONSTRAINT ai_audit_log_session_id_fkey FOREIGN KEY (session_id) REFERENCES public.ai_sessions(id) ON DELETE CASCADE;


--
-- Name: ai_audit_log ai_audit_log_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_audit_log
    ADD CONSTRAINT ai_audit_log_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;


--
-- Name: ai_audit_log ai_audit_log_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_audit_log
    ADD CONSTRAINT ai_audit_log_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: ai_sessions ai_sessions_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_sessions
    ADD CONSTRAINT ai_sessions_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;


--
-- Name: ai_sessions ai_sessions_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_sessions
    ADD CONSTRAINT ai_sessions_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: ai_suggestions ai_suggestions_audit_log_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_suggestions
    ADD CONSTRAINT ai_suggestions_audit_log_id_fkey FOREIGN KEY (audit_log_id) REFERENCES public.ai_audit_log(id);


--
-- Name: ai_suggestions ai_suggestions_execution_audit_log_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_suggestions
    ADD CONSTRAINT ai_suggestions_execution_audit_log_id_fkey FOREIGN KEY (execution_audit_log_id) REFERENCES public.ai_audit_log(id);


--
-- Name: ai_suggestions ai_suggestions_proposed_by_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_suggestions
    ADD CONSTRAINT ai_suggestions_proposed_by_user_id_fkey FOREIGN KEY (proposed_by_user_id) REFERENCES public.users(id);


--
-- Name: ai_suggestions ai_suggestions_reviewed_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_suggestions
    ADD CONSTRAINT ai_suggestions_reviewed_by_fkey FOREIGN KEY (reviewed_by) REFERENCES public.users(id);


--
-- Name: ai_suggestions ai_suggestions_session_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_suggestions
    ADD CONSTRAINT ai_suggestions_session_id_fkey FOREIGN KEY (session_id) REFERENCES public.ai_sessions(id);


--
-- Name: ai_suggestions ai_suggestions_superseded_by_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_suggestions
    ADD CONSTRAINT ai_suggestions_superseded_by_id_fkey FOREIGN KEY (superseded_by_id) REFERENCES public.ai_suggestions(id);


--
-- Name: ai_suggestions ai_suggestions_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_suggestions
    ADD CONSTRAINT ai_suggestions_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;


--
-- Name: ai_tool_calls ai_tool_calls_audit_log_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_tool_calls
    ADD CONSTRAINT ai_tool_calls_audit_log_id_fkey FOREIGN KEY (audit_log_id) REFERENCES public.ai_audit_log(id) ON DELETE CASCADE;


--
-- Name: ai_tool_calls ai_tool_calls_session_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_tool_calls
    ADD CONSTRAINT ai_tool_calls_session_id_fkey FOREIGN KEY (session_id) REFERENCES public.ai_sessions(id) ON DELETE CASCADE;


--
-- Name: ai_tool_calls ai_tool_calls_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_tool_calls
    ADD CONSTRAINT ai_tool_calls_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;


--
-- Name: alerts alerts_target_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.alerts
    ADD CONSTRAINT alerts_target_user_id_fkey FOREIGN KEY (target_user_id) REFERENCES public.users(id);


--
-- Name: alerts alerts_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.alerts
    ADD CONSTRAINT alerts_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;


--
-- Name: anomalies anomalies_assigned_to_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.anomalies
    ADD CONSTRAINT anomalies_assigned_to_fkey FOREIGN KEY (assigned_to) REFERENCES public.users(id);


--
-- Name: anomalies anomalies_customer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.anomalies
    ADD CONSTRAINT anomalies_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.customers(id);


--
-- Name: anomalies anomalies_linked_anomaly_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.anomalies
    ADD CONSTRAINT anomalies_linked_anomaly_id_fkey FOREIGN KEY (linked_anomaly_id) REFERENCES public.anomalies(id);


--
-- Name: anomalies anomalies_location_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.anomalies
    ADD CONSTRAINT anomalies_location_id_fkey FOREIGN KEY (location_id) REFERENCES public.service_locations(id);


--
-- Name: anomalies anomalies_meter_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.anomalies
    ADD CONSTRAINT anomalies_meter_id_fkey FOREIGN KEY (meter_id) REFERENCES public.meters(id);


--
-- Name: anomalies anomalies_resolution_suggestion_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.anomalies
    ADD CONSTRAINT anomalies_resolution_suggestion_id_fkey FOREIGN KEY (resolution_suggestion_id) REFERENCES public.ai_suggestions(id);


--
-- Name: anomalies anomalies_resolved_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.anomalies
    ADD CONSTRAINT anomalies_resolved_by_fkey FOREIGN KEY (resolved_by) REFERENCES public.users(id);


--
-- Name: anomalies anomalies_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.anomalies
    ADD CONSTRAINT anomalies_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;


--
-- Name: auto_pay_settings auto_pay_settings_customer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auto_pay_settings
    ADD CONSTRAINT auto_pay_settings_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.customers(id) ON DELETE CASCADE;


--
-- Name: auto_pay_settings auto_pay_settings_payment_method_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auto_pay_settings
    ADD CONSTRAINT auto_pay_settings_payment_method_id_fkey FOREIGN KEY (payment_method_id) REFERENCES public.payment_methods(id);


--
-- Name: auto_pay_settings auto_pay_settings_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auto_pay_settings
    ADD CONSTRAINT auto_pay_settings_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;


--
-- Name: bill_messages bill_messages_approved_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bill_messages
    ADD CONSTRAINT bill_messages_approved_by_fkey FOREIGN KEY (approved_by) REFERENCES public.users(id);


--
-- Name: bill_messages bill_messages_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bill_messages
    ADD CONSTRAINT bill_messages_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- Name: bill_messages bill_messages_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bill_messages
    ADD CONSTRAINT bill_messages_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;


--
-- Name: billing_cycles billing_cycles_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.billing_cycles
    ADD CONSTRAINT billing_cycles_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;


--
-- Name: billing_run_meters billing_run_meters_billing_run_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.billing_run_meters
    ADD CONSTRAINT billing_run_meters_billing_run_id_fkey FOREIGN KEY (billing_run_id) REFERENCES public.billing_runs(id) ON DELETE CASCADE;


--
-- Name: billing_run_meters billing_run_meters_invoice_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.billing_run_meters
    ADD CONSTRAINT billing_run_meters_invoice_id_fkey FOREIGN KEY (invoice_id) REFERENCES public.invoices(id) ON DELETE SET NULL;


--
-- Name: billing_run_meters billing_run_meters_meter_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.billing_run_meters
    ADD CONSTRAINT billing_run_meters_meter_id_fkey FOREIGN KEY (meter_id) REFERENCES public.meters(id);


--
-- Name: billing_run_meters billing_run_meters_meter_reading_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.billing_run_meters
    ADD CONSTRAINT billing_run_meters_meter_reading_id_fkey FOREIGN KEY (meter_reading_id) REFERENCES public.meter_readings(id);


--
-- Name: billing_run_meters billing_run_meters_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.billing_run_meters
    ADD CONSTRAINT billing_run_meters_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;


--
-- Name: billing_runs billing_runs_approved_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.billing_runs
    ADD CONSTRAINT billing_runs_approved_by_fkey FOREIGN KEY (approved_by) REFERENCES public.users(id);


--
-- Name: billing_runs billing_runs_billing_cycle_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.billing_runs
    ADD CONSTRAINT billing_runs_billing_cycle_id_fkey FOREIGN KEY (billing_cycle_id) REFERENCES public.billing_cycles(id);


--
-- Name: billing_runs billing_runs_cancelled_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.billing_runs
    ADD CONSTRAINT billing_runs_cancelled_by_fkey FOREIGN KEY (cancelled_by) REFERENCES public.users(id);


--
-- Name: billing_runs billing_runs_generated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.billing_runs
    ADD CONSTRAINT billing_runs_generated_by_fkey FOREIGN KEY (generated_by) REFERENCES public.users(id);


--
-- Name: billing_runs billing_runs_posted_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.billing_runs
    ADD CONSTRAINT billing_runs_posted_by_fkey FOREIGN KEY (posted_by) REFERENCES public.users(id);


--
-- Name: billing_runs billing_runs_read_cycle_instance_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.billing_runs
    ADD CONSTRAINT billing_runs_read_cycle_instance_id_fkey FOREIGN KEY (read_cycle_instance_id) REFERENCES public.read_cycle_instances(id);


--
-- Name: billing_runs billing_runs_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.billing_runs
    ADD CONSTRAINT billing_runs_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;


--
-- Name: communities communities_master_customer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.communities
    ADD CONSTRAINT communities_master_customer_id_fkey FOREIGN KEY (master_customer_id) REFERENCES public.customers(id);


--
-- Name: communities communities_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.communities
    ADD CONSTRAINT communities_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;


--
-- Name: correction_run_targets correction_run_targets_billing_run_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.correction_run_targets
    ADD CONSTRAINT correction_run_targets_billing_run_id_fkey FOREIGN KEY (billing_run_id) REFERENCES public.billing_runs(id) ON DELETE CASCADE;


--
-- Name: correction_run_targets correction_run_targets_correction_invoice_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.correction_run_targets
    ADD CONSTRAINT correction_run_targets_correction_invoice_id_fkey FOREIGN KEY (correction_invoice_id) REFERENCES public.invoices(id);


--
-- Name: correction_run_targets correction_run_targets_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.correction_run_targets
    ADD CONSTRAINT correction_run_targets_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- Name: correction_run_targets correction_run_targets_customer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.correction_run_targets
    ADD CONSTRAINT correction_run_targets_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.customers(id);


--
-- Name: correction_run_targets correction_run_targets_location_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.correction_run_targets
    ADD CONSTRAINT correction_run_targets_location_id_fkey FOREIGN KEY (location_id) REFERENCES public.service_locations(id);


--
-- Name: correction_run_targets correction_run_targets_meter_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.correction_run_targets
    ADD CONSTRAINT correction_run_targets_meter_id_fkey FOREIGN KEY (meter_id) REFERENCES public.meters(id);


--
-- Name: correction_run_targets correction_run_targets_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.correction_run_targets
    ADD CONSTRAINT correction_run_targets_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;


--
-- Name: correction_run_targets correction_run_targets_voided_invoice_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.correction_run_targets
    ADD CONSTRAINT correction_run_targets_voided_invoice_id_fkey FOREIGN KEY (voided_invoice_id) REFERENCES public.invoices(id);


--
-- Name: custom_field_definitions custom_field_definitions_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.custom_field_definitions
    ADD CONSTRAINT custom_field_definitions_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- Name: custom_field_definitions custom_field_definitions_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.custom_field_definitions
    ADD CONSTRAINT custom_field_definitions_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;


--
-- Name: custom_field_definitions custom_field_definitions_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.custom_field_definitions
    ADD CONSTRAINT custom_field_definitions_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(id);


--
-- Name: custom_location_types custom_location_types_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.custom_location_types
    ADD CONSTRAINT custom_location_types_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;


--
-- Name: customer_contacts customer_contacts_customer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_contacts
    ADD CONSTRAINT customer_contacts_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.customers(id) ON DELETE CASCADE;


--
-- Name: customer_contacts customer_contacts_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_contacts
    ADD CONSTRAINT customer_contacts_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;


--
-- Name: customer_credits customer_credits_customer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_credits
    ADD CONSTRAINT customer_credits_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.customers(id);


--
-- Name: customer_credits customer_credits_issued_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_credits
    ADD CONSTRAINT customer_credits_issued_by_fkey FOREIGN KEY (issued_by) REFERENCES public.users(id);


--
-- Name: customer_credits customer_credits_source_adhoc_charge_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_credits
    ADD CONSTRAINT customer_credits_source_adhoc_charge_id_fkey FOREIGN KEY (source_adhoc_charge_id) REFERENCES public.adhoc_charges(id);


--
-- Name: customer_credits customer_credits_source_invoice_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_credits
    ADD CONSTRAINT customer_credits_source_invoice_id_fkey FOREIGN KEY (source_invoice_id) REFERENCES public.invoices(id);


--
-- Name: customer_credits customer_credits_source_payment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_credits
    ADD CONSTRAINT customer_credits_source_payment_id_fkey FOREIGN KEY (source_payment_id) REFERENCES public.payments(id);


--
-- Name: customer_credits customer_credits_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_credits
    ADD CONSTRAINT customer_credits_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;


--
-- Name: customer_interactions customer_interactions_customer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_interactions
    ADD CONSTRAINT customer_interactions_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.customers(id) ON DELETE CASCADE;


--
-- Name: customer_interactions customer_interactions_follow_up_assigned_to_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_interactions
    ADD CONSTRAINT customer_interactions_follow_up_assigned_to_fkey FOREIGN KEY (follow_up_assigned_to) REFERENCES public.users(id);


--
-- Name: customer_interactions customer_interactions_handled_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_interactions
    ADD CONSTRAINT customer_interactions_handled_by_fkey FOREIGN KEY (handled_by) REFERENCES public.users(id);


--
-- Name: customer_interactions customer_interactions_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_interactions
    ADD CONSTRAINT customer_interactions_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;


--
-- Name: customer_tax_exemptions customer_tax_exemptions_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_tax_exemptions
    ADD CONSTRAINT customer_tax_exemptions_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- Name: customer_tax_exemptions customer_tax_exemptions_customer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_tax_exemptions
    ADD CONSTRAINT customer_tax_exemptions_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.customers(id) ON DELETE CASCADE;


--
-- Name: customer_tax_exemptions customer_tax_exemptions_revoked_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_tax_exemptions
    ADD CONSTRAINT customer_tax_exemptions_revoked_by_fkey FOREIGN KEY (revoked_by) REFERENCES public.users(id);


--
-- Name: customer_tax_exemptions customer_tax_exemptions_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_tax_exemptions
    ADD CONSTRAINT customer_tax_exemptions_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;


--
-- Name: customer_tax_exemptions customer_tax_exemptions_verified_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_tax_exemptions
    ADD CONSTRAINT customer_tax_exemptions_verified_by_fkey FOREIGN KEY (verified_by) REFERENCES public.users(id);


--
-- Name: customer_winter_averages customer_winter_averages_computed_by_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_winter_averages
    ADD CONSTRAINT customer_winter_averages_computed_by_user_id_fkey FOREIGN KEY (computed_by_user_id) REFERENCES public.users(id);


--
-- Name: customer_winter_averages customer_winter_averages_customer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_winter_averages
    ADD CONSTRAINT customer_winter_averages_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.customers(id);


--
-- Name: customer_winter_averages customer_winter_averages_meter_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_winter_averages
    ADD CONSTRAINT customer_winter_averages_meter_id_fkey FOREIGN KEY (meter_id) REFERENCES public.meters(id) ON DELETE CASCADE;


--
-- Name: customer_winter_averages customer_winter_averages_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_winter_averages
    ADD CONSTRAINT customer_winter_averages_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;


--
-- Name: customers customers_billing_hold_set_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customers
    ADD CONSTRAINT customers_billing_hold_set_by_fkey FOREIGN KEY (billing_hold_set_by) REFERENCES public.users(id);


--
-- Name: customers customers_landlord_customer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customers
    ADD CONSTRAINT customers_landlord_customer_id_fkey FOREIGN KEY (landlord_customer_id) REFERENCES public.customers(id);


--
-- Name: customers customers_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customers
    ADD CONSTRAINT customers_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;


--
-- Name: dunning_events dunning_events_customer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dunning_events
    ADD CONSTRAINT dunning_events_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.customers(id);


--
-- Name: dunning_events dunning_events_invoice_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dunning_events
    ADD CONSTRAINT dunning_events_invoice_id_fkey FOREIGN KEY (invoice_id) REFERENCES public.invoices(id) ON DELETE CASCADE;


--
-- Name: dunning_events dunning_events_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dunning_events
    ADD CONSTRAINT dunning_events_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;


--
-- Name: dunning_events dunning_events_triggered_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dunning_events
    ADD CONSTRAINT dunning_events_triggered_by_fkey FOREIGN KEY (triggered_by) REFERENCES public.users(id);


--
-- Name: escheatment_events escheatment_events_customer_credit_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.escheatment_events
    ADD CONSTRAINT escheatment_events_customer_credit_id_fkey FOREIGN KEY (customer_credit_id) REFERENCES public.customer_credits(id);


--
-- Name: escheatment_events escheatment_events_customer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.escheatment_events
    ADD CONSTRAINT escheatment_events_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.customers(id);


--
-- Name: escheatment_events escheatment_events_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.escheatment_events
    ADD CONSTRAINT escheatment_events_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;


--
-- Name: escheatment_events escheatment_events_triggered_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.escheatment_events
    ADD CONSTRAINT escheatment_events_triggered_by_fkey FOREIGN KEY (triggered_by) REFERENCES public.users(id);


--
-- Name: adhoc_charges fk_adhoc_ai_audit; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.adhoc_charges
    ADD CONSTRAINT fk_adhoc_ai_audit FOREIGN KEY (ai_audit_id) REFERENCES public.ai_audit_log(id);


--
-- Name: adhoc_charges fk_adhoc_invoice; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.adhoc_charges
    ADD CONSTRAINT fk_adhoc_invoice FOREIGN KEY (billed_on_invoice_id) REFERENCES public.invoices(id) ON DELETE SET NULL;


--
-- Name: adhoc_charges fk_adhoc_suggestion; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.adhoc_charges
    ADD CONSTRAINT fk_adhoc_suggestion FOREIGN KEY (created_by_suggestion_id) REFERENCES public.ai_suggestions(id);


--
-- Name: adhoc_charges fk_adhoc_triggered_invoice; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.adhoc_charges
    ADD CONSTRAINT fk_adhoc_triggered_invoice FOREIGN KEY (triggered_by_invoice_id) REFERENCES public.invoices(id);


--
-- Name: adhoc_charges fk_adhoc_triggered_payment; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.adhoc_charges
    ADD CONSTRAINT fk_adhoc_triggered_payment FOREIGN KEY (triggered_by_payment_id) REFERENCES public.payments(id);


--
-- Name: ai_audit_log fk_audit_suggestion; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_audit_log
    ADD CONSTRAINT fk_audit_suggestion FOREIGN KEY (suggestion_id) REFERENCES public.ai_suggestions(id);


--
-- Name: customer_interactions fk_interactions_location; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_interactions
    ADD CONSTRAINT fk_interactions_location FOREIGN KEY (location_id) REFERENCES public.service_locations(id);


--
-- Name: service_locations fk_locations_community; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.service_locations
    ADD CONSTRAINT fk_locations_community FOREIGN KEY (community_id) REFERENCES public.communities(id);


--
-- Name: meter_photos fk_meter_photos_reading; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.meter_photos
    ADD CONSTRAINT fk_meter_photos_reading FOREIGN KEY (meter_reading_id) REFERENCES public.meter_readings(id);


--
-- Name: meters fk_meters_route; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.meters
    ADD CONSTRAINT fk_meters_route FOREIGN KEY (route_id) REFERENCES public.read_routes(id);


--
-- Name: payment_provider_logs fk_provider_log_payment; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payment_provider_logs
    ADD CONSTRAINT fk_provider_log_payment FOREIGN KEY (payment_id) REFERENCES public.payments(id) ON DELETE SET NULL;


--
-- Name: read_routes fk_read_routes_billing_cycle; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.read_routes
    ADD CONSTRAINT fk_read_routes_billing_cycle FOREIGN KEY (default_billing_cycle_id) REFERENCES public.billing_cycles(id);


--
-- Name: meter_readings fk_readings_billing_cycle; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.meter_readings
    ADD CONSTRAINT fk_readings_billing_cycle FOREIGN KEY (billing_cycle_id) REFERENCES public.billing_cycles(id);


--
-- Name: meter_readings fk_readings_import_job; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.meter_readings
    ADD CONSTRAINT fk_readings_import_job FOREIGN KEY (import_job_id) REFERENCES public.import_jobs(id);


--
-- Name: meter_readings fk_readings_locked_by_billing_run; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.meter_readings
    ADD CONSTRAINT fk_readings_locked_by_billing_run FOREIGN KEY (locked_by_billing_run_id) REFERENCES public.billing_runs(id);


--
-- Name: meter_readings fk_readings_locked_by_invoice; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.meter_readings
    ADD CONSTRAINT fk_readings_locked_by_invoice FOREIGN KEY (locked_by_invoice_id) REFERENCES public.invoices(id);


--
-- Name: ai_tool_calls fk_toolcall_suggestion; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_tool_calls
    ADD CONSTRAINT fk_toolcall_suggestion FOREIGN KEY (suggestion_id) REFERENCES public.ai_suggestions(id);


--
-- Name: franchise_fee_rules franchise_fee_rules_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.franchise_fee_rules
    ADD CONSTRAINT franchise_fee_rules_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;


--
-- Name: import_column_mappings import_column_mappings_decided_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.import_column_mappings
    ADD CONSTRAINT import_column_mappings_decided_by_fkey FOREIGN KEY (decided_by) REFERENCES public.users(id);


--
-- Name: import_column_mappings import_column_mappings_import_job_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.import_column_mappings
    ADD CONSTRAINT import_column_mappings_import_job_id_fkey FOREIGN KEY (import_job_id) REFERENCES public.import_jobs(id) ON DELETE CASCADE;


--
-- Name: import_column_mappings import_column_mappings_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.import_column_mappings
    ADD CONSTRAINT import_column_mappings_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;


--
-- Name: import_jobs import_jobs_initiated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.import_jobs
    ADD CONSTRAINT import_jobs_initiated_by_fkey FOREIGN KEY (initiated_by) REFERENCES public.users(id);


--
-- Name: import_jobs import_jobs_mapping_suggestion_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.import_jobs
    ADD CONSTRAINT import_jobs_mapping_suggestion_id_fkey FOREIGN KEY (mapping_suggestion_id) REFERENCES public.ai_suggestions(id);


--
-- Name: import_jobs import_jobs_mapping_template_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.import_jobs
    ADD CONSTRAINT import_jobs_mapping_template_id_fkey FOREIGN KEY (mapping_template_id) REFERENCES public.import_mapping_templates(id);


--
-- Name: import_jobs import_jobs_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.import_jobs
    ADD CONSTRAINT import_jobs_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;


--
-- Name: import_mapping_templates import_mapping_templates_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.import_mapping_templates
    ADD CONSTRAINT import_mapping_templates_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- Name: import_mapping_templates import_mapping_templates_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.import_mapping_templates
    ADD CONSTRAINT import_mapping_templates_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;


--
-- Name: import_staging import_staging_import_job_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.import_staging
    ADD CONSTRAINT import_staging_import_job_id_fkey FOREIGN KEY (import_job_id) REFERENCES public.import_jobs(id) ON DELETE CASCADE;


--
-- Name: import_staging import_staging_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.import_staging
    ADD CONSTRAINT import_staging_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;


--
-- Name: invoice_applications invoice_applications_applied_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoice_applications
    ADD CONSTRAINT invoice_applications_applied_by_fkey FOREIGN KEY (applied_by) REFERENCES public.users(id);


--
-- Name: invoice_applications invoice_applications_invoice_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoice_applications
    ADD CONSTRAINT invoice_applications_invoice_id_fkey FOREIGN KEY (invoice_id) REFERENCES public.invoices(id) ON DELETE CASCADE;


--
-- Name: invoice_applications invoice_applications_reversed_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoice_applications
    ADD CONSTRAINT invoice_applications_reversed_by_fkey FOREIGN KEY (reversed_by) REFERENCES public.users(id);


--
-- Name: invoice_applications invoice_applications_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoice_applications
    ADD CONSTRAINT invoice_applications_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;


--
-- Name: invoice_events invoice_events_invoice_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoice_events
    ADD CONSTRAINT invoice_events_invoice_id_fkey FOREIGN KEY (invoice_id) REFERENCES public.invoices(id) ON DELETE CASCADE;


--
-- Name: invoice_events invoice_events_operator_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoice_events
    ADD CONSTRAINT invoice_events_operator_id_fkey FOREIGN KEY (operator_id) REFERENCES public.users(id);


--
-- Name: invoice_events invoice_events_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoice_events
    ADD CONSTRAINT invoice_events_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;


--
-- Name: invoice_line_items invoice_line_items_adhoc_charge_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoice_line_items
    ADD CONSTRAINT invoice_line_items_adhoc_charge_id_fkey FOREIGN KEY (adhoc_charge_id) REFERENCES public.adhoc_charges(id);


--
-- Name: invoice_line_items invoice_line_items_invoice_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoice_line_items
    ADD CONSTRAINT invoice_line_items_invoice_id_fkey FOREIGN KEY (invoice_id) REFERENCES public.invoices(id) ON DELETE CASCADE;


--
-- Name: invoice_line_items invoice_line_items_meter_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoice_line_items
    ADD CONSTRAINT invoice_line_items_meter_id_fkey FOREIGN KEY (meter_id) REFERENCES public.meters(id);


--
-- Name: invoice_line_items invoice_line_items_meter_reading_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoice_line_items
    ADD CONSTRAINT invoice_line_items_meter_reading_id_fkey FOREIGN KEY (meter_reading_id) REFERENCES public.meter_readings(id);


--
-- Name: invoice_line_items invoice_line_items_rate_item_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoice_line_items
    ADD CONSTRAINT invoice_line_items_rate_item_id_fkey FOREIGN KEY (rate_item_id) REFERENCES public.rate_items(id);


--
-- Name: invoice_line_items invoice_line_items_rate_schedule_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoice_line_items
    ADD CONSTRAINT invoice_line_items_rate_schedule_id_fkey FOREIGN KEY (rate_schedule_id) REFERENCES public.rate_schedules(id);


--
-- Name: invoice_line_items invoice_line_items_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoice_line_items
    ADD CONSTRAINT invoice_line_items_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;


--
-- Name: invoices invoices_billing_run_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoices
    ADD CONSTRAINT invoices_billing_run_id_fkey FOREIGN KEY (billing_run_id) REFERENCES public.billing_runs(id);


--
-- Name: invoices invoices_customer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoices
    ADD CONSTRAINT invoices_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.customers(id);


--
-- Name: invoices invoices_held_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoices
    ADD CONSTRAINT invoices_held_by_fkey FOREIGN KEY (held_by) REFERENCES public.users(id);


--
-- Name: invoices invoices_location_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoices
    ADD CONSTRAINT invoices_location_id_fkey FOREIGN KEY (location_id) REFERENCES public.service_locations(id);


--
-- Name: invoices invoices_parent_invoice_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoices
    ADD CONSTRAINT invoices_parent_invoice_id_fkey FOREIGN KEY (parent_invoice_id) REFERENCES public.invoices(id);


--
-- Name: invoices invoices_replaces_invoice_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoices
    ADD CONSTRAINT invoices_replaces_invoice_id_fkey FOREIGN KEY (replaces_invoice_id) REFERENCES public.invoices(id);


--
-- Name: invoices invoices_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoices
    ADD CONSTRAINT invoices_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;


--
-- Name: invoices invoices_voided_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoices
    ADD CONSTRAINT invoices_voided_by_fkey FOREIGN KEY (voided_by) REFERENCES public.users(id);


--
-- Name: invoices invoices_write_off_approved_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoices
    ADD CONSTRAINT invoices_write_off_approved_by_fkey FOREIGN KEY (write_off_approved_by) REFERENCES public.users(id);


--
-- Name: meter_deployments meter_deployments_installed_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.meter_deployments
    ADD CONSTRAINT meter_deployments_installed_by_fkey FOREIGN KEY (installed_by) REFERENCES public.users(id);


--
-- Name: meter_deployments meter_deployments_location_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.meter_deployments
    ADD CONSTRAINT meter_deployments_location_id_fkey FOREIGN KEY (location_id) REFERENCES public.service_locations(id);


--
-- Name: meter_deployments meter_deployments_meter_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.meter_deployments
    ADD CONSTRAINT meter_deployments_meter_id_fkey FOREIGN KEY (meter_id) REFERENCES public.meters(id) ON DELETE CASCADE;


--
-- Name: meter_deployments meter_deployments_rate_schedule_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.meter_deployments
    ADD CONSTRAINT meter_deployments_rate_schedule_id_fkey FOREIGN KEY (rate_schedule_id) REFERENCES public.rate_schedules(id);


--
-- Name: meter_deployments meter_deployments_removed_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.meter_deployments
    ADD CONSTRAINT meter_deployments_removed_by_fkey FOREIGN KEY (removed_by) REFERENCES public.users(id);


--
-- Name: meter_deployments meter_deployments_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.meter_deployments
    ADD CONSTRAINT meter_deployments_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;


--
-- Name: meter_endpoint_history meter_endpoint_history_installed_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.meter_endpoint_history
    ADD CONSTRAINT meter_endpoint_history_installed_by_fkey FOREIGN KEY (installed_by) REFERENCES public.users(id);


--
-- Name: meter_endpoint_history meter_endpoint_history_meter_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.meter_endpoint_history
    ADD CONSTRAINT meter_endpoint_history_meter_id_fkey FOREIGN KEY (meter_id) REFERENCES public.meters(id);


--
-- Name: meter_endpoint_history meter_endpoint_history_removed_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.meter_endpoint_history
    ADD CONSTRAINT meter_endpoint_history_removed_by_fkey FOREIGN KEY (removed_by) REFERENCES public.users(id);


--
-- Name: meter_endpoint_history meter_endpoint_history_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.meter_endpoint_history
    ADD CONSTRAINT meter_endpoint_history_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;


--
-- Name: meter_photos meter_photos_meter_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.meter_photos
    ADD CONSTRAINT meter_photos_meter_id_fkey FOREIGN KEY (meter_id) REFERENCES public.meters(id) ON DELETE CASCADE;


--
-- Name: meter_photos meter_photos_taken_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.meter_photos
    ADD CONSTRAINT meter_photos_taken_by_fkey FOREIGN KEY (taken_by) REFERENCES public.users(id);


--
-- Name: meter_photos meter_photos_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.meter_photos
    ADD CONSTRAINT meter_photos_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;


--
-- Name: meter_readings meter_readings_assigned_to_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.meter_readings
    ADD CONSTRAINT meter_readings_assigned_to_user_id_fkey FOREIGN KEY (assigned_to_user_id) REFERENCES public.users(id);


--
-- Name: meter_readings meter_readings_confirmed_by_field_reader_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.meter_readings
    ADD CONSTRAINT meter_readings_confirmed_by_field_reader_id_fkey FOREIGN KEY (confirmed_by_field_reader_id) REFERENCES public.users(id);


--
-- Name: meter_readings meter_readings_dispute_raised_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.meter_readings
    ADD CONSTRAINT meter_readings_dispute_raised_by_fkey FOREIGN KEY (dispute_raised_by) REFERENCES public.users(id);


--
-- Name: meter_readings meter_readings_dispute_resolved_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.meter_readings
    ADD CONSTRAINT meter_readings_dispute_resolved_by_fkey FOREIGN KEY (dispute_resolved_by) REFERENCES public.users(id);


--
-- Name: meter_readings meter_readings_entered_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.meter_readings
    ADD CONSTRAINT meter_readings_entered_by_fkey FOREIGN KEY (entered_by) REFERENCES public.users(id);


--
-- Name: meter_readings meter_readings_meter_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.meter_readings
    ADD CONSTRAINT meter_readings_meter_id_fkey FOREIGN KEY (meter_id) REFERENCES public.meters(id);


--
-- Name: meter_readings meter_readings_read_cycle_meter_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.meter_readings
    ADD CONSTRAINT meter_readings_read_cycle_meter_id_fkey FOREIGN KEY (read_cycle_meter_id) REFERENCES public.read_cycle_meters(id);


--
-- Name: meter_readings meter_readings_replaced_by_reading_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.meter_readings
    ADD CONSTRAINT meter_readings_replaced_by_reading_id_fkey FOREIGN KEY (replaced_by_reading_id) REFERENCES public.meter_readings(id);


--
-- Name: meter_readings meter_readings_replaces_read_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.meter_readings
    ADD CONSTRAINT meter_readings_replaces_read_id_fkey FOREIGN KEY (replaces_read_id) REFERENCES public.meter_readings(id);


--
-- Name: meter_readings meter_readings_replaces_reading_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.meter_readings
    ADD CONSTRAINT meter_readings_replaces_reading_id_fkey FOREIGN KEY (replaces_reading_id) REFERENCES public.meter_readings(id);


--
-- Name: meter_readings meter_readings_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.meter_readings
    ADD CONSTRAINT meter_readings_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;


--
-- Name: meter_readings meter_readings_transition_incoming_customer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.meter_readings
    ADD CONSTRAINT meter_readings_transition_incoming_customer_id_fkey FOREIGN KEY (transition_incoming_customer_id) REFERENCES public.customers(id);


--
-- Name: meter_readings meter_readings_transition_outgoing_customer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.meter_readings
    ADD CONSTRAINT meter_readings_transition_outgoing_customer_id_fkey FOREIGN KEY (transition_outgoing_customer_id) REFERENCES public.customers(id);


--
-- Name: meter_readings meter_readings_validated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.meter_readings
    ADD CONSTRAINT meter_readings_validated_by_fkey FOREIGN KEY (validated_by) REFERENCES public.users(id);


--
-- Name: meter_readings meter_readings_voided_from_invoice_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.meter_readings
    ADD CONSTRAINT meter_readings_voided_from_invoice_id_fkey FOREIGN KEY (voided_from_invoice_id) REFERENCES public.invoices(id);


--
-- Name: meters meters_derives_from_meter_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.meters
    ADD CONSTRAINT meters_derives_from_meter_id_fkey FOREIGN KEY (derives_from_meter_id) REFERENCES public.meters(id);


--
-- Name: meters meters_estimation_blocked_set_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.meters
    ADD CONSTRAINT meters_estimation_blocked_set_by_fkey FOREIGN KEY (estimation_blocked_set_by) REFERENCES public.users(id);


--
-- Name: meters meters_location_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.meters
    ADD CONSTRAINT meters_location_id_fkey FOREIGN KEY (location_id) REFERENCES public.service_locations(id);


--
-- Name: meters meters_rate_schedule_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.meters
    ADD CONSTRAINT meters_rate_schedule_id_fkey FOREIGN KEY (rate_schedule_id) REFERENCES public.rate_schedules(id);


--
-- Name: meters meters_replaces_meter_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.meters
    ADD CONSTRAINT meters_replaces_meter_id_fkey FOREIGN KEY (replaces_meter_id) REFERENCES public.meters(id);


--
-- Name: meters meters_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.meters
    ADD CONSTRAINT meters_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;


--
-- Name: payment_methods payment_methods_customer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payment_methods
    ADD CONSTRAINT payment_methods_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.customers(id) ON DELETE CASCADE;


--
-- Name: payment_methods payment_methods_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payment_methods
    ADD CONSTRAINT payment_methods_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;


--
-- Name: payment_provider_logs payment_provider_logs_customer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payment_provider_logs
    ADD CONSTRAINT payment_provider_logs_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.customers(id);


--
-- Name: payment_provider_logs payment_provider_logs_payment_method_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payment_provider_logs
    ADD CONSTRAINT payment_provider_logs_payment_method_id_fkey FOREIGN KEY (payment_method_id) REFERENCES public.payment_methods(id);


--
-- Name: payment_provider_logs payment_provider_logs_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payment_provider_logs
    ADD CONSTRAINT payment_provider_logs_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;


--
-- Name: payments payments_customer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.customers(id);


--
-- Name: payments payments_nsf_fee_charge_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_nsf_fee_charge_id_fkey FOREIGN KEY (nsf_fee_charge_id) REFERENCES public.adhoc_charges(id);


--
-- Name: payments payments_nsf_original_payment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_nsf_original_payment_id_fkey FOREIGN KEY (nsf_original_payment_id) REFERENCES public.payments(id);


--
-- Name: payments payments_payment_method_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_payment_method_id_fkey FOREIGN KEY (payment_method_id) REFERENCES public.payment_methods(id);


--
-- Name: payments payments_received_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_received_by_fkey FOREIGN KEY (received_by) REFERENCES public.users(id);


--
-- Name: payments payments_refunds_payment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_refunds_payment_id_fkey FOREIGN KEY (refunds_payment_id) REFERENCES public.payments(id);


--
-- Name: payments payments_reversed_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_reversed_by_fkey FOREIGN KEY (reversed_by) REFERENCES public.users(id);


--
-- Name: payments payments_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;


--
-- Name: rate_item_dependencies rate_item_dependencies_base_rate_item_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rate_item_dependencies
    ADD CONSTRAINT rate_item_dependencies_base_rate_item_id_fkey FOREIGN KEY (base_rate_item_id) REFERENCES public.rate_items(id) ON DELETE CASCADE;


--
-- Name: rate_item_dependencies rate_item_dependencies_dependent_rate_item_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rate_item_dependencies
    ADD CONSTRAINT rate_item_dependencies_dependent_rate_item_id_fkey FOREIGN KEY (dependent_rate_item_id) REFERENCES public.rate_items(id) ON DELETE CASCADE;


--
-- Name: rate_item_dependencies rate_item_dependencies_rate_schedule_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rate_item_dependencies
    ADD CONSTRAINT rate_item_dependencies_rate_schedule_id_fkey FOREIGN KEY (rate_schedule_id) REFERENCES public.rate_schedules(id) ON DELETE CASCADE;


--
-- Name: rate_item_dependencies rate_item_dependencies_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rate_item_dependencies
    ADD CONSTRAINT rate_item_dependencies_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;


--
-- Name: rate_item_history rate_item_history_changed_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rate_item_history
    ADD CONSTRAINT rate_item_history_changed_by_fkey FOREIGN KEY (changed_by) REFERENCES public.users(id);


--
-- Name: rate_item_history rate_item_history_rate_item_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rate_item_history
    ADD CONSTRAINT rate_item_history_rate_item_id_fkey FOREIGN KEY (rate_item_id) REFERENCES public.rate_items(id) ON DELETE CASCADE;


--
-- Name: rate_item_history rate_item_history_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rate_item_history
    ADD CONSTRAINT rate_item_history_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;


--
-- Name: rate_items rate_items_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rate_items
    ADD CONSTRAINT rate_items_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;


--
-- Name: rate_schedule_items rate_schedule_items_rate_item_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rate_schedule_items
    ADD CONSTRAINT rate_schedule_items_rate_item_id_fkey FOREIGN KEY (rate_item_id) REFERENCES public.rate_items(id);


--
-- Name: rate_schedule_items rate_schedule_items_rate_schedule_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rate_schedule_items
    ADD CONSTRAINT rate_schedule_items_rate_schedule_id_fkey FOREIGN KEY (rate_schedule_id) REFERENCES public.rate_schedules(id) ON DELETE CASCADE;


--
-- Name: rate_schedule_items rate_schedule_items_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rate_schedule_items
    ADD CONSTRAINT rate_schedule_items_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;


--
-- Name: rate_schedules rate_schedules_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rate_schedules
    ADD CONSTRAINT rate_schedules_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;


--
-- Name: rate_schedules rate_schedules_wna_zone_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rate_schedules
    ADD CONSTRAINT rate_schedules_wna_zone_id_fkey FOREIGN KEY (wna_zone_id) REFERENCES public.wna_zones(id);


--
-- Name: read_cycle_instances read_cycle_instances_billing_cycle_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.read_cycle_instances
    ADD CONSTRAINT read_cycle_instances_billing_cycle_id_fkey FOREIGN KEY (billing_cycle_id) REFERENCES public.billing_cycles(id);


--
-- Name: read_cycle_instances read_cycle_instances_billing_run_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.read_cycle_instances
    ADD CONSTRAINT read_cycle_instances_billing_run_id_fkey FOREIGN KEY (billing_run_id) REFERENCES public.billing_runs(id);


--
-- Name: read_cycle_instances read_cycle_instances_completed_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.read_cycle_instances
    ADD CONSTRAINT read_cycle_instances_completed_by_fkey FOREIGN KEY (completed_by) REFERENCES public.users(id);


--
-- Name: read_cycle_instances read_cycle_instances_issued_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.read_cycle_instances
    ADD CONSTRAINT read_cycle_instances_issued_by_fkey FOREIGN KEY (issued_by) REFERENCES public.users(id);


--
-- Name: read_cycle_instances read_cycle_instances_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.read_cycle_instances
    ADD CONSTRAINT read_cycle_instances_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;


--
-- Name: read_cycle_meters read_cycle_meters_assigned_reader_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.read_cycle_meters
    ADD CONSTRAINT read_cycle_meters_assigned_reader_user_id_fkey FOREIGN KEY (assigned_reader_user_id) REFERENCES public.users(id);


--
-- Name: read_cycle_meters read_cycle_meters_captured_reading_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.read_cycle_meters
    ADD CONSTRAINT read_cycle_meters_captured_reading_id_fkey FOREIGN KEY (captured_reading_id) REFERENCES public.meter_readings(id);


--
-- Name: read_cycle_meters read_cycle_meters_meter_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.read_cycle_meters
    ADD CONSTRAINT read_cycle_meters_meter_id_fkey FOREIGN KEY (meter_id) REFERENCES public.meters(id);


--
-- Name: read_cycle_meters read_cycle_meters_read_cycle_instance_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.read_cycle_meters
    ADD CONSTRAINT read_cycle_meters_read_cycle_instance_id_fkey FOREIGN KEY (read_cycle_instance_id) REFERENCES public.read_cycle_instances(id) ON DELETE CASCADE;


--
-- Name: read_cycle_meters read_cycle_meters_read_route_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.read_cycle_meters
    ADD CONSTRAINT read_cycle_meters_read_route_id_fkey FOREIGN KEY (read_route_id) REFERENCES public.read_routes(id);


--
-- Name: read_cycle_meters read_cycle_meters_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.read_cycle_meters
    ADD CONSTRAINT read_cycle_meters_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;


--
-- Name: read_routes read_routes_assigned_to_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.read_routes
    ADD CONSTRAINT read_routes_assigned_to_user_id_fkey FOREIGN KEY (assigned_to_user_id) REFERENCES public.users(id);


--
-- Name: read_routes read_routes_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.read_routes
    ADD CONSTRAINT read_routes_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;


--
-- Name: service_locations service_locations_billing_cycle_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.service_locations
    ADD CONSTRAINT service_locations_billing_cycle_id_fkey FOREIGN KEY (billing_cycle_id) REFERENCES public.billing_cycles(id);


--
-- Name: service_locations service_locations_customer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.service_locations
    ADD CONSTRAINT service_locations_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.customers(id);


--
-- Name: service_locations service_locations_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.service_locations
    ADD CONSTRAINT service_locations_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;


--
-- Name: service_orders service_orders_ai_audit_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.service_orders
    ADD CONSTRAINT service_orders_ai_audit_id_fkey FOREIGN KEY (ai_audit_id) REFERENCES public.ai_audit_log(id);


--
-- Name: service_orders service_orders_billing_action_suggestion_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.service_orders
    ADD CONSTRAINT service_orders_billing_action_suggestion_id_fkey FOREIGN KEY (billing_action_suggestion_id) REFERENCES public.ai_suggestions(id);


--
-- Name: service_orders service_orders_cancelled_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.service_orders
    ADD CONSTRAINT service_orders_cancelled_by_fkey FOREIGN KEY (cancelled_by) REFERENCES public.users(id);


--
-- Name: service_orders service_orders_created_by_suggestion_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.service_orders
    ADD CONSTRAINT service_orders_created_by_suggestion_id_fkey FOREIGN KEY (created_by_suggestion_id) REFERENCES public.ai_suggestions(id);


--
-- Name: service_orders service_orders_customer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.service_orders
    ADD CONSTRAINT service_orders_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.customers(id);


--
-- Name: service_orders service_orders_location_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.service_orders
    ADD CONSTRAINT service_orders_location_id_fkey FOREIGN KEY (location_id) REFERENCES public.service_locations(id);


--
-- Name: service_orders service_orders_meter_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.service_orders
    ADD CONSTRAINT service_orders_meter_id_fkey FOREIGN KEY (meter_id) REFERENCES public.meters(id);


--
-- Name: service_orders service_orders_parent_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.service_orders
    ADD CONSTRAINT service_orders_parent_order_id_fkey FOREIGN KEY (parent_order_id) REFERENCES public.service_orders(id);


--
-- Name: service_orders service_orders_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.service_orders
    ADD CONSTRAINT service_orders_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;


--
-- Name: service_orders service_orders_triggered_new_meter_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.service_orders
    ADD CONSTRAINT service_orders_triggered_new_meter_id_fkey FOREIGN KEY (triggered_new_meter_id) REFERENCES public.meters(id);


--
-- Name: service_orders service_orders_triggered_replaced_meter_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.service_orders
    ADD CONSTRAINT service_orders_triggered_replaced_meter_id_fkey FOREIGN KEY (triggered_replaced_meter_id) REFERENCES public.meters(id);


--
-- Name: tenant_sequences tenant_sequences_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tenant_sequences
    ADD CONSTRAINT tenant_sequences_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;


--
-- Name: users users_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: users users_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;


--
-- Name: wna_monthly_adjustments wna_monthly_adjustments_approved_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wna_monthly_adjustments
    ADD CONSTRAINT wna_monthly_adjustments_approved_by_fkey FOREIGN KEY (approved_by) REFERENCES public.users(id);


--
-- Name: wna_monthly_adjustments wna_monthly_adjustments_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wna_monthly_adjustments
    ADD CONSTRAINT wna_monthly_adjustments_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;


--
-- Name: wna_monthly_adjustments wna_monthly_adjustments_wna_zone_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wna_monthly_adjustments
    ADD CONSTRAINT wna_monthly_adjustments_wna_zone_id_fkey FOREIGN KEY (wna_zone_id) REFERENCES public.wna_zones(id) ON DELETE CASCADE;


--
-- Name: wna_zones wna_zones_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wna_zones
    ADD CONSTRAINT wna_zones_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;


--
-- Name: account_ledger; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.account_ledger ENABLE ROW LEVEL SECURITY;

--
-- Name: adhoc_charges; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.adhoc_charges ENABLE ROW LEVEL SECURITY;

--
-- Name: ai_audit_log; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.ai_audit_log ENABLE ROW LEVEL SECURITY;

--
-- Name: ai_sessions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.ai_sessions ENABLE ROW LEVEL SECURITY;

--
-- Name: ai_suggestions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.ai_suggestions ENABLE ROW LEVEL SECURITY;

--
-- Name: ai_tool_calls; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.ai_tool_calls ENABLE ROW LEVEL SECURITY;

--
-- Name: alerts; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.alerts ENABLE ROW LEVEL SECURITY;

--
-- Name: anomalies; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.anomalies ENABLE ROW LEVEL SECURITY;

--
-- Name: auto_pay_settings; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.auto_pay_settings ENABLE ROW LEVEL SECURITY;

--
-- Name: bill_messages; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.bill_messages ENABLE ROW LEVEL SECURITY;

--
-- Name: billing_cycles; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.billing_cycles ENABLE ROW LEVEL SECURITY;

--
-- Name: billing_run_meters; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.billing_run_meters ENABLE ROW LEVEL SECURITY;

--
-- Name: billing_runs; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.billing_runs ENABLE ROW LEVEL SECURITY;

--
-- Name: communities; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.communities ENABLE ROW LEVEL SECURITY;

--
-- Name: correction_run_targets; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.correction_run_targets ENABLE ROW LEVEL SECURITY;

--
-- Name: custom_field_definitions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.custom_field_definitions ENABLE ROW LEVEL SECURITY;

--
-- Name: custom_location_types; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.custom_location_types ENABLE ROW LEVEL SECURITY;

--
-- Name: customer_contacts; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.customer_contacts ENABLE ROW LEVEL SECURITY;

--
-- Name: customer_credits; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.customer_credits ENABLE ROW LEVEL SECURITY;

--
-- Name: customer_interactions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.customer_interactions ENABLE ROW LEVEL SECURITY;

--
-- Name: customer_tax_exemptions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.customer_tax_exemptions ENABLE ROW LEVEL SECURITY;

--
-- Name: customer_winter_averages; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.customer_winter_averages ENABLE ROW LEVEL SECURITY;

--
-- Name: customers; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;

--
-- Name: dunning_events; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.dunning_events ENABLE ROW LEVEL SECURITY;

--
-- Name: escheatment_events; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.escheatment_events ENABLE ROW LEVEL SECURITY;

--
-- Name: franchise_fee_rules; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.franchise_fee_rules ENABLE ROW LEVEL SECURITY;

--
-- Name: import_column_mappings; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.import_column_mappings ENABLE ROW LEVEL SECURITY;

--
-- Name: import_jobs; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.import_jobs ENABLE ROW LEVEL SECURITY;

--
-- Name: import_mapping_templates; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.import_mapping_templates ENABLE ROW LEVEL SECURITY;

--
-- Name: import_staging; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.import_staging ENABLE ROW LEVEL SECURITY;

--
-- Name: invoice_applications; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.invoice_applications ENABLE ROW LEVEL SECURITY;

--
-- Name: invoice_events; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.invoice_events ENABLE ROW LEVEL SECURITY;

--
-- Name: invoice_events invoice_events_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY invoice_events_insert ON public.invoice_events FOR INSERT WITH CHECK ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));


--
-- Name: invoice_events invoice_events_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY invoice_events_select ON public.invoice_events FOR SELECT USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));


--
-- Name: invoice_line_items; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.invoice_line_items ENABLE ROW LEVEL SECURITY;

--
-- Name: invoices; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.invoices ENABLE ROW LEVEL SECURITY;

--
-- Name: meter_deployments; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.meter_deployments ENABLE ROW LEVEL SECURITY;

--
-- Name: meter_endpoint_history; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.meter_endpoint_history ENABLE ROW LEVEL SECURITY;

--
-- Name: meter_photos; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.meter_photos ENABLE ROW LEVEL SECURITY;

--
-- Name: meter_readings; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.meter_readings ENABLE ROW LEVEL SECURITY;

--
-- Name: meters; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.meters ENABLE ROW LEVEL SECURITY;

--
-- Name: payment_methods; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.payment_methods ENABLE ROW LEVEL SECURITY;

--
-- Name: payment_provider_logs; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.payment_provider_logs ENABLE ROW LEVEL SECURITY;

--
-- Name: payments; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.payments ENABLE ROW LEVEL SECURITY;

--
-- Name: rate_item_dependencies; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.rate_item_dependencies ENABLE ROW LEVEL SECURITY;

--
-- Name: rate_item_history; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.rate_item_history ENABLE ROW LEVEL SECURITY;

--
-- Name: rate_item_history_archive; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.rate_item_history_archive ENABLE ROW LEVEL SECURITY;

--
-- Name: rate_items; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.rate_items ENABLE ROW LEVEL SECURITY;

--
-- Name: rate_schedule_items; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.rate_schedule_items ENABLE ROW LEVEL SECURITY;

--
-- Name: rate_schedules; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.rate_schedules ENABLE ROW LEVEL SECURITY;

--
-- Name: read_cycle_instances; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.read_cycle_instances ENABLE ROW LEVEL SECURITY;

--
-- Name: read_cycle_meters; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.read_cycle_meters ENABLE ROW LEVEL SECURITY;

--
-- Name: read_routes; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.read_routes ENABLE ROW LEVEL SECURITY;

--
-- Name: service_locations; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.service_locations ENABLE ROW LEVEL SECURITY;

--
-- Name: service_orders; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.service_orders ENABLE ROW LEVEL SECURITY;

--
-- Name: account_ledger tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.account_ledger USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));


--
-- Name: adhoc_charges tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.adhoc_charges USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));


--
-- Name: ai_audit_log tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.ai_audit_log USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));


--
-- Name: ai_sessions tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.ai_sessions USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));


--
-- Name: ai_suggestions tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.ai_suggestions USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));


--
-- Name: ai_tool_calls tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.ai_tool_calls USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));


--
-- Name: alerts tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.alerts USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));


--
-- Name: anomalies tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.anomalies USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));


--
-- Name: auto_pay_settings tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.auto_pay_settings USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));


--
-- Name: bill_messages tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.bill_messages USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));


--
-- Name: billing_cycles tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.billing_cycles USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));


--
-- Name: billing_run_meters tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.billing_run_meters USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));


--
-- Name: billing_runs tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.billing_runs USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));


--
-- Name: communities tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.communities USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));


--
-- Name: correction_run_targets tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.correction_run_targets USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));


--
-- Name: custom_field_definitions tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.custom_field_definitions USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));


--
-- Name: custom_location_types tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.custom_location_types USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));


--
-- Name: customer_contacts tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.customer_contacts USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));


--
-- Name: customer_credits tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.customer_credits USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));


--
-- Name: customer_interactions tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.customer_interactions USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));


--
-- Name: customer_tax_exemptions tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.customer_tax_exemptions USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));


--
-- Name: customer_winter_averages tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.customer_winter_averages USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));


--
-- Name: customers tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.customers USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));


--
-- Name: dunning_events tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.dunning_events USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));


--
-- Name: escheatment_events tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.escheatment_events USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));


--
-- Name: franchise_fee_rules tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.franchise_fee_rules USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));


--
-- Name: import_column_mappings tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.import_column_mappings USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));


--
-- Name: import_jobs tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.import_jobs USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));


--
-- Name: import_mapping_templates tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.import_mapping_templates USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));


--
-- Name: import_staging tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.import_staging USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));


--
-- Name: invoice_applications tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.invoice_applications USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));


--
-- Name: invoice_line_items tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.invoice_line_items USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));


--
-- Name: invoices tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.invoices USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));


--
-- Name: meter_deployments tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.meter_deployments USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));


--
-- Name: meter_endpoint_history tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.meter_endpoint_history USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));


--
-- Name: meter_photos tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.meter_photos USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));


--
-- Name: meter_readings tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.meter_readings USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));


--
-- Name: meters tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.meters USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));


--
-- Name: payment_methods tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.payment_methods USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));


--
-- Name: payment_provider_logs tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.payment_provider_logs USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));


--
-- Name: payments tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.payments USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));


--
-- Name: rate_item_dependencies tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.rate_item_dependencies USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));


--
-- Name: rate_item_history tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.rate_item_history USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));


--
-- Name: rate_item_history_archive tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.rate_item_history_archive USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));


--
-- Name: rate_items tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.rate_items USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));


--
-- Name: rate_schedule_items tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.rate_schedule_items USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));


--
-- Name: rate_schedules tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.rate_schedules USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));


--
-- Name: read_cycle_instances tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.read_cycle_instances USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));


--
-- Name: read_cycle_meters tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.read_cycle_meters USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));


--
-- Name: read_routes tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.read_routes USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));


--
-- Name: service_locations tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.service_locations USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));


--
-- Name: service_orders tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.service_orders USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));


--
-- Name: tenant_sequences tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.tenant_sequences USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));


--
-- Name: tenants tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.tenants USING ((public.is_platform_admin() OR (id = public.get_user_tenant_id())));


--
-- Name: users tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.users USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));


--
-- Name: wna_monthly_adjustments tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.wna_monthly_adjustments USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));


--
-- Name: wna_zones tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.wna_zones USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));


--
-- Name: tenant_sequences; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.tenant_sequences ENABLE ROW LEVEL SECURITY;

--
-- Name: tenants; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.tenants ENABLE ROW LEVEL SECURITY;

--
-- Name: users; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;

--
-- Name: wna_monthly_adjustments; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.wna_monthly_adjustments ENABLE ROW LEVEL SECURITY;

--
-- Name: wna_zones; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.wna_zones ENABLE ROW LEVEL SECURITY;

--
-- PostgreSQL database dump complete
--

\unrestrict aEs36qkOAMhofmB2vLfkoMmgKoI58YBi08fnaoUeHfQFg3rVEXFznvClKqh8agw
