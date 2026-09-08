-- ============================================================================
-- PATCH v5.4.2-10 — A-3 follow-up: the snapshot's coordinate pair is bound
--                    to facts the database holds (schema-parity-plan Phase 4,
--                    Appendix A-23 item 1e; CI-015 / CI-003 / CI-005)
-- ============================================================================
-- Authority:   Appendix A-23 (1e), recorded by the A-7 reviews (2026-08-31):
--              "A-3's invoice_calculation_snapshots accepts any past
--              recorded_at and does not bind valid_at to the period — a
--              compliance gate that trusted the pair was bypassed with a
--              backdated coordinate; ... binding valid_at (or requiring
--              recorded_at within the run) is an A-3 follow-up."
--              D-2026-08-31-07 (A-7's gate judges on now(), not the pair);
--              D-2026-08-28-18 (the pair lives on the snapshot); AC-15 (one
--              pair per run); CI-005 and Kyle's correction-rate-mode ruling
--              (get_correction_rate_date resolves the operator's valid-time
--              election: custom > per-target > run default); the v5.4.2-03
--              convention that a regular bill is priced at period_end
--              (rate_schedule_versions.gas_usage_formula COMMENT);
--              D-2026-08-28-03 ("transaction time is the database's").
--              Ryan, 2026-09-08: strict on both calls — an ordinary bill is
--              priced at exactly period_end, and a correction invoice with no
--              correction-run target row is refused.
--
-- The hole, in one sentence: the snapshot is the record of WHICH coordinate
-- a bill was priced at, and until now the caller could write any coordinate.
-- A recorded_at of 2020 makes the provenance guard (v5.4.2-04 §5) certify
-- that a row retracted in 2024 "was visible to the run"; a valid_at of 2025
-- on a 2026 March bill prices it against next year's tariff and the
-- content_hash freezes the lie on an immutable row. A-7 stopped trusting the
-- pair; this patch makes the pair trustworthy.
--
-- What lands:
--
--   1. The binding, in validate_calculation_snapshot() (redefined; same
--      trigger). Two shapes, selected by invoices.invoice_type:
--
--      ORDINARY invoice (every type except correction):
--        valid_at    = invoices.period_end, exactly. Not "inside the period":
--                      the -03 formula convention prices at period_end and a
--                      snapshot priced at the read date would be a silent
--                      engine defect, not a policy (Ryan, strict).
--        recorded_at ∈ [lower, now()], where lower is
--                      billing_runs.started_at when the invoice is on a run
--                      (the run must have started — a snapshot on a
--                      not-yet-started run is refused), else the invoice's
--                      own created_at (an off-run draft). Both lower bounds
--                      are the database's clock (items 2 and 4 below).
--
--      CORRECTION invoice (invoice_type = 'correction'):
--        The invoice must sit on a run of run_type = 'correction', name the
--        bill it replaces (replaces_invoice_id), and that pair must have a
--        correction_run_targets row — the row where the operator's
--        valid-time election is recorded (CI-005). No target row, no
--        snapshot: an off-run manual rebill has nowhere to record its
--        election and is refused (Ryan, strict).
--        valid_at    = get_correction_rate_date(run, replaced invoice):
--                      the voided bill's period_end (historical, the RRC
--                      default), the session's CURRENT_DATE (current-rules
--                      election, evaluated at snapshot insert), or the
--                      operator's override date (custom). Checked at insert.
--        recorded_at ∈ [run.started_at, now()] — current knowledge — OR
--                      exactly the replaced invoice's snapshot recorded_at:
--                      the "original world's truth" rebill flavor
--                      (16-bi-temporality §5.1) legitimately prices against
--                      what was known when the original bill ran. Nothing
--                      else: a correction cannot invent a third instant.
--
--   2. billing_runs.started_at is the database's clock. Setting it (INSERT
--      with a value, or the NULL → value transition) stamps now(); once set
--      it never moves. Without this the run-window lower bound is the
--      caller's number. Superusers (migrations) are exempt, as in
--      enforce_event_written_by_db.
--
--   3. The correction election is frozen once a snapshot has relied on it:
--      billing_runs.correction_rate_mode cannot change while any snapshot
--      exists on the run; a correction_run_targets row cannot change its
--      run, voided invoice, rate_date_mode or rate_date_override — nor be
--      deleted — while a snapshot exists for the correction invoice that
--      replaces its voided invoice on its run. Otherwise valid_at would be
--      checked against one election and issued under another.
--
--   4. A snapshotted draft's binding inputs are frozen: while a snapshot
--      exists, an invoice's invoice_type, replaces_invoice_id, billing_run_id,
--      period_start, period_end and created_at cannot change ("delete the
--      snapshot first" — the -04 recalculation model, delete + re-snapshot,
--      now applies to these columns too). created_at is additionally forced
--      to now() at INSERT (the off-run lower bound must not be caller-
--      supplied). Issued invoices were already frozen by A-4; this closes
--      the draft window between snapshot and issuance.
--
--   5. The issuance gate (enforce_invoice_has_snapshot, redefined; same
--      deferred constraint trigger) re-runs the binding at commit: the
--      ordinary shape in full; for a correction, that the target row still
--      exists and recorded_at still satisfies its rule. valid_at is NOT
--      re-derived for a correction at issuance — the current-rules election
--      is CURRENT_DATE at insert and issuance may be a later day; the freezes
--      in 3 and 4 are what guarantee the insert-time check still holds.
--
--   6. Concurrency (the -08 handshake): the validator holds the billing_runs
--      row and, for a correction, the correction_run_targets row FOR SHARE
--      for the rest of the snapshot writer's transaction, so an election
--      change or a started_at edit waits behind an in-flight snapshot and
--      then sees it. The freeze guards in 3 and 4 refuse to run under any
--      isolation level other than READ COMMITTED when a frozen column is
--      actually changing (a REPEATABLE READ snapshot could not see the
--      waited-for row — AC-29's rule, applied here).
--
-- Deliberately NOT landed (attack these if you think they are wrong):
--   * No binding for invoice_type = 'duplicate' beyond the ordinary shape.
--     A duplicate ("a reprint with identical content") has no lineage column
--     — replaces_invoice_id is the reversal chain and a duplicate is not a
--     reversal — so its coordinate cannot be tied to its original. Stated
--     boundary; a reprint is a PDF concern, not a new priced bill.
--   * No re-derivation of a correction's valid_at at issuance (see 5).
--   * No reimplementation of get_correction_rate_date's resolution: the
--     v5.2.1 function IS the ruling's implementation (SECURITY DEFINER,
--     pinned public, pg_temp since -03). Its 'current' branch returns the
--     session's CURRENT_DATE — the binding inherits that day boundary; the
--     engine must run the election and the snapshot insert in one session
--     TimeZone (the A-7 Central-time pin was for a Texas assessment; this
--     is the operator's own election and is recorded as they made it).
--   * Nothing verifies the engine passed THIS pair to the *_as_of lookups —
--     CI-003 stays application discipline until R-16's GUC net.
--
-- Preconditions: none refuse. Snapshots written before this patch are
-- immutable and cannot be corrected; the patch REPORTS how many would fail
-- the binding (NOTICE), and how many runs carry snapshots without a
-- started_at. On a fresh deploy both counts are zero.
--
-- Verification contract: this file applies standalone under
--   SET search_path = ''; SET check_function_bodies = on;
-- Every relation and function reference is qualified; trigger functions pin
-- SET search_path = public, pg_temp (A-23 1c: the RLS helpers are still
-- unqualified, so '' is not yet safe for a function that reads an RLS table).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. billing_runs.started_at is the database's; the correction election is
--    frozen under snapshots.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.enforce_billing_run_clock_and_election() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_super boolean := (SELECT r.rolsuper FROM pg_roles r WHERE r.rolname = current_user);
BEGIN
    IF TG_OP = 'INSERT' THEN
        -- A run inserted already-started is stamped by the server, not the caller.
        IF NEW.started_at IS NOT NULL AND NOT v_super THEN
            NEW.started_at := now();
        END IF;
        RETURN NEW;
    END IF;

    -- UPDATE ------------------------------------------------------------------
    IF NEW.started_at IS DISTINCT FROM OLD.started_at AND NOT v_super THEN
        IF OLD.started_at IS NULL THEN
            NEW.started_at := now();          -- the start is when the database saw it start
        ELSE
            RAISE EXCEPTION USING
                MESSAGE = format('billing run %s: started_at is the database''s clock and is write-once (v5.4.2-10) — it is the lower bound every calculation snapshot on this run is checked against', OLD.run_number),
                ERRCODE = 'restrict_violation';
        END IF;
    END IF;

    IF NEW.correction_rate_mode IS DISTINCT FROM OLD.correction_rate_mode THEN
        IF current_setting('transaction_isolation') <> 'read committed' THEN
            RAISE EXCEPTION USING
                MESSAGE = format('billing run %s: correction_rate_mode may only be changed under READ COMMITTED (v5.4.2-10) — under %s this transaction could not see a snapshot committed while it waited', OLD.run_number, current_setting('transaction_isolation')),
                ERRCODE = 'invalid_transaction_state';
        END IF;
        IF EXISTS (SELECT 1 FROM public.invoice_calculation_snapshots s WHERE s.billing_run_id = OLD.id) THEN
            RAISE EXCEPTION USING
                MESSAGE = format('billing run %s: correction_rate_mode cannot change while calculation snapshots exist on the run (v5.4.2-10) — their valid_at was checked against the current election; delete the draft snapshots first, or start a new correction run', OLD.run_number),
                ERRCODE = 'restrict_violation';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.enforce_billing_run_clock_and_election() IS
    'v5.4.2-10 (A-3 follow-up). BEFORE INSERT OR UPDATE OF started_at, correction_rate_mode on billing_runs: started_at is stamped now() when set (INSERT with a value, or NULL -> value) and never moves afterwards — it is the lower bound of every snapshot recorded_at on the run; correction_rate_mode is frozen while any invoice_calculation_snapshots row cites the run, and its change refuses any isolation level but READ COMMITTED (the snapshot validator holds the run row FOR SHARE, so the change waits behind in-flight snapshots and must then see them). Superusers (migrations) may write started_at directly.';

DROP TRIGGER IF EXISTS a_enforce_billing_run_clock_and_election ON public.billing_runs;
CREATE TRIGGER a_enforce_billing_run_clock_and_election BEFORE INSERT OR UPDATE OF started_at, correction_rate_mode ON public.billing_runs
    FOR EACH ROW EXECUTE FUNCTION public.enforce_billing_run_clock_and_election();

-- ----------------------------------------------------------------------------
-- 2. correction_run_targets: the election row is frozen once a snapshot has
--    been checked against it.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.enforce_correction_target_frozen_under_snapshot() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
BEGIN
    IF TG_OP = 'UPDATE'
       AND NEW.billing_run_id     IS NOT DISTINCT FROM OLD.billing_run_id
       AND NEW.voided_invoice_id  IS NOT DISTINCT FROM OLD.voided_invoice_id
       AND NEW.rate_date_mode     IS NOT DISTINCT FROM OLD.rate_date_mode
       AND NEW.rate_date_override IS NOT DISTINCT FROM OLD.rate_date_override THEN
        RETURN NEW;                            -- nothing the binding reads is changing
    END IF;
    IF current_setting('transaction_isolation') <> 'read committed' THEN
        RAISE EXCEPTION USING
            MESSAGE = format('correction target %s: its rate-date election may only be changed or removed under READ COMMITTED (v5.4.2-10) — under %s this transaction could not see a snapshot committed while it waited', OLD.id, current_setting('transaction_isolation')),
            ERRCODE = 'invalid_transaction_state';
    END IF;
    IF EXISTS (
        SELECT 1
          FROM public.invoice_calculation_snapshots s
          JOIN public.invoices i ON i.id = s.invoice_id
         WHERE i.billing_run_id      = OLD.billing_run_id
           AND i.replaces_invoice_id = OLD.voided_invoice_id
           AND i.invoice_type        = 'correction') THEN
        RAISE EXCEPTION USING
            MESSAGE = format('correction target %s (run %s, voided invoice %s): a calculation snapshot was checked against this election; the target cannot change or be removed while that snapshot exists (v5.4.2-10) — delete the draft snapshot first', OLD.id, OLD.billing_run_id, OLD.voided_invoice_id),
            ERRCODE = 'restrict_violation';
    END IF;
    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.enforce_correction_target_frozen_under_snapshot() IS
    'v5.4.2-10 (A-3 follow-up). BEFORE UPDATE OF billing_run_id, voided_invoice_id, rate_date_mode, rate_date_override OR DELETE on correction_run_targets: refused while an invoice_calculation_snapshots row exists for the correction invoice (same run, replaces_invoice_id = voided_invoice_id) — its valid_at was checked against this election. Only under READ COMMITTED (the snapshot validator holds the target row FOR SHARE).';

DROP TRIGGER IF EXISTS a_enforce_correction_target_frozen_under_snapshot ON public.correction_run_targets;
CREATE TRIGGER a_enforce_correction_target_frozen_under_snapshot
    BEFORE UPDATE OF billing_run_id, voided_invoice_id, rate_date_mode, rate_date_override OR DELETE ON public.correction_run_targets
    FOR EACH ROW EXECUTE FUNCTION public.enforce_correction_target_frozen_under_snapshot();

-- ----------------------------------------------------------------------------
-- 3. invoices: created_at is the database's; a snapshotted draft's binding
--    inputs are frozen.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.enforce_invoice_snapshot_inputs() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF NOT (SELECT r.rolsuper FROM pg_roles r WHERE r.rolname = current_user) THEN
            NEW.created_at := now();          -- the off-run lower bound is never caller-supplied
        END IF;
        RETURN NEW;
    END IF;

    IF NEW.invoice_type        IS NOT DISTINCT FROM OLD.invoice_type
       AND NEW.replaces_invoice_id IS NOT DISTINCT FROM OLD.replaces_invoice_id
       AND NEW.billing_run_id   IS NOT DISTINCT FROM OLD.billing_run_id
       AND NEW.period_start     IS NOT DISTINCT FROM OLD.period_start
       AND NEW.period_end       IS NOT DISTINCT FROM OLD.period_end
       AND NEW.created_at       IS NOT DISTINCT FROM OLD.created_at THEN
        RETURN NEW;
    END IF;
    -- Issued invoices: A-4 already refuses every one of these; this guard
    -- closes the draft/held window between snapshot and issuance.
    IF current_setting('transaction_isolation') <> 'read committed' THEN
        RAISE EXCEPTION USING
            MESSAGE = format('invoice %s: invoice_type / replaces_invoice_id / billing_run_id / period / created_at may only change under READ COMMITTED (v5.4.2-10) — under %s this transaction could not see a snapshot committed while it waited', OLD.invoice_number, current_setting('transaction_isolation')),
            ERRCODE = 'invalid_transaction_state';
    END IF;
    IF EXISTS (SELECT 1 FROM public.invoice_calculation_snapshots s WHERE s.invoice_id = OLD.id) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('invoice %s has a calculation snapshot: invoice_type, replaces_invoice_id, billing_run_id, period_start, period_end and created_at are frozen while it exists (v5.4.2-10) — the snapshot''s coordinate was checked against them; delete the snapshot, change the invoice, re-snapshot', OLD.invoice_number),
            ERRCODE = 'restrict_violation';
    END IF;
    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.enforce_invoice_snapshot_inputs() IS
    'v5.4.2-10 (A-3 follow-up). BEFORE INSERT OR UPDATE OF invoice_type, replaces_invoice_id, billing_run_id, period_start, period_end, created_at on invoices: INSERT stamps created_at = now() (superusers exempt) — it is the recorded_at lower bound for an off-run snapshot; UPDATE of any of these is refused while an invoice_calculation_snapshots row exists for the invoice (delete + re-snapshot, the -04 model) and refuses any isolation level but READ COMMITTED when one of them changes.';

DROP TRIGGER IF EXISTS a_enforce_invoice_snapshot_inputs ON public.invoices;
CREATE TRIGGER a_enforce_invoice_snapshot_inputs
    BEFORE INSERT OR UPDATE OF invoice_type, replaces_invoice_id, billing_run_id, period_start, period_end, created_at ON public.invoices
    FOR EACH ROW EXECUTE FUNCTION public.enforce_invoice_snapshot_inputs();

-- ----------------------------------------------------------------------------
-- 4. The binding: one helper, called at snapshot insert and at issuance.
--    Returns NULL when the pair is admissible, else the reason (the callers
--    raise). Locks are the callers' business (the helper is pure reads).
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.calculation_snapshot_coordinate_violation(
    p_inv         public.invoices,
    p_valid_at    date,
    p_recorded_at timestamp with time zone,
    p_at_issuance boolean
) RETURNS text
    LANGUAGE plpgsql STABLE
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_run        public.billing_runs%ROWTYPE;
    v_target_id  uuid;
    v_expected   date;
    v_orig_rec   timestamp with time zone;
BEGIN
    IF p_recorded_at > now() THEN
        RETURN 'recorded_at may not lie in the future (it is the transaction-time coordinate the run used, AC-15)';
    END IF;

    IF p_inv.billing_run_id IS NOT NULL THEN
        SELECT * INTO v_run FROM public.billing_runs b WHERE b.id = p_inv.billing_run_id;
        IF NOT FOUND THEN
            RETURN format('billing run %s not found (or not visible to this tenant)', p_inv.billing_run_id);
        END IF;
    END IF;

    -- ---------------------------------------------------------------- correction
    IF p_inv.invoice_type = 'correction' THEN
        IF p_inv.replaces_invoice_id IS NULL THEN
            RETURN 'a correction invoice must name the bill it replaces (replaces_invoice_id) — the operator''s rate-date election is recorded per replaced invoice (CI-005)';
        END IF;
        IF p_inv.billing_run_id IS NULL THEN
            RETURN 'a correction invoice must sit on a correction billing run — an off-run rebill has no correction_run_targets row to record its rate-date election (CI-005; v5.4.2-10, strict)';
        END IF;
        IF v_run.run_type <> 'correction' THEN
            RETURN format('a correction invoice must sit on a run of run_type = correction; run %s is %s', v_run.run_number, v_run.run_type);
        END IF;
        SELECT t.id INTO v_target_id
          FROM public.correction_run_targets t
         WHERE t.billing_run_id = p_inv.billing_run_id
           AND t.voided_invoice_id = p_inv.replaces_invoice_id;
        IF NOT FOUND THEN
            RETURN format('no correction_run_targets row for (run %s, voided invoice %s) — the rate-date election must be recorded before the correction is priced (CI-005; v5.4.2-10, strict)', v_run.run_number, p_inv.replaces_invoice_id);
        END IF;
        IF NOT p_at_issuance THEN
            v_expected := public.get_correction_rate_date(p_inv.billing_run_id, p_inv.replaces_invoice_id);
            IF v_expected IS NULL THEN
                RETURN 'get_correction_rate_date() resolved no date for this target';
            END IF;
            IF p_valid_at <> v_expected THEN
                RETURN format('valid_at %s is not the recorded rate-date election %s for this correction (correction_run_targets.rate_date_mode / billing_runs.correction_rate_mode; CI-005)', p_valid_at, v_expected);
            END IF;
        END IF;
        -- recorded_at: this run's window, or exactly the original bill's instant.
        SELECT s.recorded_at INTO v_orig_rec
          FROM public.invoice_calculation_snapshots s
         WHERE s.invoice_id = p_inv.replaces_invoice_id;
        IF v_orig_rec IS NOT NULL AND p_recorded_at = v_orig_rec THEN
            RETURN NULL;                       -- "original world's truth" replay
        END IF;
        IF v_run.started_at IS NULL THEN
            RETURN format('correction run %s has not started (started_at is NULL): a snapshot''s recorded_at must lie within the run''s window, or equal the replaced bill''s snapshot recorded_at%s', v_run.run_number,
                          CASE WHEN v_orig_rec IS NULL THEN ' (the replaced bill has no snapshot)' ELSE format(' (%s)', v_orig_rec) END);
        END IF;
        IF p_recorded_at < v_run.started_at THEN
            RETURN format('recorded_at %s predates correction run %s''s start %s and is not the replaced bill''s snapshot coordinate%s — a correction prices at current knowledge or at the original bill''s instant, nothing else', p_recorded_at, v_run.run_number, v_run.started_at,
                          CASE WHEN v_orig_rec IS NULL THEN ' (the replaced bill has no snapshot)' ELSE format(' (%s)', v_orig_rec) END);
        END IF;
        RETURN NULL;
    END IF;

    -- ------------------------------------------------------------------ ordinary
    IF p_valid_at <> p_inv.period_end THEN
        RETURN format('valid_at %s must equal the invoice''s period_end %s — an ordinary bill is priced at the last day of its service period (v5.4.2-03 convention; v5.4.2-10, strict)', p_valid_at, p_inv.period_end);
    END IF;
    IF p_inv.billing_run_id IS NOT NULL THEN
        IF v_run.started_at IS NULL THEN
            RETURN format('billing run %s has not started (started_at is NULL): a snapshot cannot be written for a run that has not begun', v_run.run_number);
        END IF;
        IF p_recorded_at < v_run.started_at THEN
            RETURN format('recorded_at %s predates billing run %s''s start %s — the run''s knowledge cannot be older than the run', p_recorded_at, v_run.run_number, v_run.started_at);
        END IF;
    ELSE
        IF p_recorded_at < p_inv.created_at THEN
            RETURN format('recorded_at %s predates the invoice''s creation %s — an off-run bill''s knowledge cannot be older than its draft', p_recorded_at, p_inv.created_at);
        END IF;
    END IF;
    RETURN NULL;
END;
$$;

COMMENT ON FUNCTION public.calculation_snapshot_coordinate_violation(public.invoices, date, timestamp with time zone, boolean) IS
    'v5.4.2-10 (A-3 follow-up, A-23 1e). NULL when a snapshot''s (valid_at, recorded_at) is admissible for the invoice, else the reason. Ordinary invoice: valid_at = period_end exactly; recorded_at in [billing_runs.started_at, now()] on a run (the run must have started) or [invoices.created_at, now()] off-run. Correction invoice: must be on a correction run, name replaces_invoice_id, and have a correction_run_targets row; valid_at = get_correction_rate_date(run, replaced) (checked at insert only — the current-rules election is CURRENT_DATE at insert); recorded_at in the run''s window or exactly the replaced bill''s snapshot recorded_at (original-world replay). Callers take the locks; this function only reads.';

-- 4.1 validate_calculation_snapshot: everything v5.4.2-04 checked, plus the
--     binding, with the run row (and the target row) held FOR SHARE.
CREATE OR REPLACE FUNCTION public.validate_calculation_snapshot() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_inv       public.invoices%ROWTYPE;
    v_missing   text[];
    v_required  jsonb;
    v_section   text;
    v_key       text;
    v_elem      jsonb;
    v_idx       integer;
    v_why       text;
BEGIN
    -- FOR SHARE: blocks behind a concurrent status flip on the same invoice so
    -- the status read here is the committed one (Fable CRITICAL-2 race).
    SELECT * INTO v_inv FROM public.invoices i WHERE i.id = NEW.invoice_id FOR SHARE;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING
            MESSAGE = format('snapshot rejected: invoice %s not found (or not visible to this tenant)', NEW.invoice_id),
            ERRCODE = 'foreign_key_violation';
    END IF;
    IF v_inv.tenant_id <> NEW.tenant_id THEN
        RAISE EXCEPTION USING
            MESSAGE = 'snapshot rejected: tenant_id must equal the invoice''s tenant',
            ERRCODE = 'check_violation';
    END IF;
    IF public.is_invoice_issued(v_inv.status) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('snapshot rejected: invoice %s is already issued (status %s); a snapshot written after issuance is a reconstruction, not the record (CI-015)', v_inv.invoice_number, v_inv.status),
            ERRCODE = 'check_violation';
    END IF;
    IF NEW.billing_run_id IS DISTINCT FROM v_inv.billing_run_id THEN
        RAISE EXCEPTION USING
            MESSAGE = format('snapshot rejected: billing_run_id %s does not match the invoice''s %s', NEW.billing_run_id, v_inv.billing_run_id),
            ERRCODE = 'check_violation';
    END IF;

    -- v5.4.2-10: hold the rows the binding reads for the rest of this
    -- transaction, so an election change / started_at edit waits behind this
    -- snapshot and then sees it (the -08 handshake). RLS applies to both.
    IF v_inv.billing_run_id IS NOT NULL THEN
        PERFORM 1 FROM public.billing_runs b WHERE b.id = v_inv.billing_run_id FOR SHARE;
    END IF;
    IF v_inv.invoice_type = 'correction' AND v_inv.billing_run_id IS NOT NULL AND v_inv.replaces_invoice_id IS NOT NULL THEN
        PERFORM 1 FROM public.correction_run_targets t
         WHERE t.billing_run_id = v_inv.billing_run_id AND t.voided_invoice_id = v_inv.replaces_invoice_id FOR SHARE;
    END IF;
    v_why := public.calculation_snapshot_coordinate_violation(v_inv, NEW.valid_at, NEW.recorded_at, false);
    IF v_why IS NOT NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('snapshot rejected for invoice %s: %s (v5.4.2-10 — the coordinate pair is bound to the invoice, its run and its correction election)', v_inv.invoice_number, v_why),
            ERRCODE = 'check_violation';
    END IF;
    -- Server clock, never the caller's.
    NEW.captured_at := now();

    -- Key contract per schema version.
    CASE NEW.snapshot_schema_version
        WHEN 'v1' THEN
            v_required := jsonb_build_object(
                'rate_inputs',     jsonb_build_array('rate_schedule_id', 'rate_schedule_version_id', 'rate_schedule_code', 'customer_type', 'partial_period_policy', 'items'),
                'gas_factors',     jsonb_build_array('pga_factor', 'btu_factor', 'pressure_factor', 'temperature_factor', 'meter_multiplier', 'factor_stack_intermediates'),
                'wna_inputs',      jsonb_build_array('applied'),
                'tax_inputs',      jsonb_build_array('jurisdictions', 'exemptions', 'franchise_fees'),
                'read_inputs',     jsonb_build_array('reads'),
                'customer_inputs', jsonb_build_array('customer_id', 'customer_class', 'location_id', 'premise_zones'),
                'period_inputs',   jsonb_build_array('period_start', 'period_end', 'days_in_period', 'proration_policy')
            );
        ELSE
            RAISE EXCEPTION USING
                MESSAGE = format('snapshot rejected: unknown snapshot_schema_version %L — validate_calculation_snapshot() accepts: v1', NEW.snapshot_schema_version),
                ERRCODE = 'check_violation';
    END CASE;

    v_missing := ARRAY[]::text[];
    FOR v_section, v_elem IN SELECT key, value FROM jsonb_each(v_required) LOOP
        FOR v_key IN SELECT jsonb_array_elements_text(v_elem) LOOP
            IF NOT (to_jsonb(NEW) -> v_section) ? v_key THEN
                v_missing := array_append(v_missing, ((v_section || '.' || v_key))::text);
            END IF;
        END LOOP;
    END LOOP;

    -- v1 shape rules beyond key presence.
    IF NEW.snapshot_schema_version = 'v1' THEN
        IF jsonb_typeof(NEW.rate_inputs -> 'items') IS DISTINCT FROM 'array' THEN v_missing := array_append(v_missing, ('rate_inputs.items (array)')::text); END IF;
        IF jsonb_typeof(NEW.gas_factors -> 'factor_stack_intermediates') IS DISTINCT FROM 'object' THEN v_missing := array_append(v_missing, ('gas_factors.factor_stack_intermediates (object)')::text); END IF;
        IF jsonb_typeof(NEW.wna_inputs -> 'applied') IS DISTINCT FROM 'boolean' THEN
            v_missing := array_append(v_missing, ('wna_inputs.applied (boolean)')::text);
        ELSIF (NEW.wna_inputs ->> 'applied')::boolean THEN
            FOR v_key IN SELECT unnest(ARRAY['wna_zone_id', 'wna_zone_version_id', 'wna_monthly_adjustment_id', 'weather_station', 'normal_hdd', 'actual_hdd', 'deadband', 'base_load', 'heating_factor']) LOOP
                IF NOT (NEW.wna_inputs ? v_key) OR jsonb_typeof(NEW.wna_inputs -> v_key) = 'null' THEN
                    v_missing := array_append(v_missing, (('wna_inputs.' || v_key || ' (required when applied)'))::text);
                END IF;
            END LOOP;
        END IF;
        FOR v_key IN SELECT unnest(ARRAY['jurisdictions', 'exemptions', 'franchise_fees']) LOOP
            IF jsonb_typeof(NEW.tax_inputs -> v_key) IS DISTINCT FROM 'array' THEN v_missing := array_append(v_missing, (('tax_inputs.' || v_key || ' (array)'))::text); END IF;
        END LOOP;
        IF jsonb_typeof(NEW.read_inputs -> 'reads') IS DISTINCT FROM 'array' THEN
            v_missing := array_append(v_missing, ('read_inputs.reads (array)')::text);
        ELSE
            v_idx := 0;
            FOR v_elem IN SELECT jsonb_array_elements(NEW.read_inputs -> 'reads') LOOP
                FOR v_key IN SELECT unnest(ARRAY['meter_id', 'meter_reading_id', 'read_date', 'raw_consumption', 'is_estimated', 'intermediate_values']) LOOP
                    IF NOT (v_elem ? v_key) THEN v_missing := array_append(v_missing, (format('read_inputs.reads[%s].%s', v_idx, v_key))::text); END IF;
                END LOOP;
                v_idx := v_idx + 1;
            END LOOP;
        END IF;
        IF jsonb_typeof(NEW.customer_inputs -> 'premise_zones') IS DISTINCT FROM 'object' THEN v_missing := array_append(v_missing, ('customer_inputs.premise_zones (object)')::text); END IF;
        v_idx := 0;
        FOR v_elem IN SELECT jsonb_array_elements(NEW.rate_inputs -> 'items') LOOP
            FOR v_key IN SELECT unnest(ARRAY['rate_item_id', 'rate_item_version_id', 'item_code', 'rate_value', 'rate_unit', 'applicability']) LOOP
                IF NOT (v_elem ? v_key) THEN v_missing := array_append(v_missing, (format('rate_inputs.items[%s].%s', v_idx, v_key))::text); END IF;
            END LOOP;
            v_idx := v_idx + 1;
        END LOOP;
        v_idx := 0;
        FOR v_elem IN SELECT jsonb_array_elements(NEW.line_items) LOOP
            FOR v_key IN SELECT unnest(ARRAY['invoice_line_item_id', 'charge_type', 'amount']) LOOP
                IF NOT (v_elem ? v_key) THEN v_missing := array_append(v_missing, (format('line_items[%s].%s', v_idx, v_key))::text); END IF;
            END LOOP;
            v_idx := v_idx + 1;
        END LOOP;
    END IF;

    IF cardinality(v_missing) > 0 THEN
        RAISE EXCEPTION USING
            MESSAGE = format('snapshot rejected: schema %s requires %s (CI-015 — every input, or an explicit null for a group that does not apply)', NEW.snapshot_schema_version, array_to_string(v_missing, ', ')),
            ERRCODE = 'check_violation';
    END IF;

    -- Cross-checks against the invoice.
    IF (NEW.period_inputs ->> 'period_start')::date IS DISTINCT FROM v_inv.period_start
       OR (NEW.period_inputs ->> 'period_end')::date IS DISTINCT FROM v_inv.period_end THEN
        RAISE EXCEPTION USING
            MESSAGE = format('snapshot rejected: period_inputs (%s .. %s) do not match invoice %s (%s .. %s)', NEW.period_inputs ->> 'period_start', NEW.period_inputs ->> 'period_end', v_inv.invoice_number, v_inv.period_start, v_inv.period_end),
            ERRCODE = 'check_violation';
    END IF;
    IF (NEW.customer_inputs ->> 'customer_id')::uuid IS DISTINCT FROM v_inv.customer_id THEN
        RAISE EXCEPTION USING
            MESSAGE = format('snapshot rejected: customer_inputs.customer_id does not match invoice %s', v_inv.invoice_number),
            ERRCODE = 'check_violation';
    END IF;
    IF NOT public.calculation_snapshot_line_items_match(NEW.invoice_id, NEW.line_items) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('snapshot rejected: line_items must cite exactly invoice %s''s invoice_line_items rows (same ids, same amounts) — write the lines first, then the snapshot', v_inv.invoice_number),
            ERRCODE = 'check_violation';
    END IF;

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.validate_calculation_snapshot() IS
    'CI-015 gate on invoice_calculation_snapshots INSERT (v5.4.2-04; coordinate binding added v5.4.2-10): parent must exist in the same tenant and be draft/held; billing_run_id equals the invoice''s; the (valid_at, recorded_at) pair is admissible per calculation_snapshot_coordinate_violation() — ordinary: valid_at = period_end, recorded_at within [run.started_at | invoice.created_at, now()]; correction: on a correction run with a correction_run_targets row, valid_at = get_correction_rate_date(), recorded_at within the run or equal to the replaced bill''s snapshot — with the run row and the target row held FOR SHARE; captured_at forced to now(); snapshot_schema_version must be one the function enumerates (v1) and every section must carry that version''s required keys (nested shapes for items/reads/line_items); period and customer match the invoice; line_items cites exactly the invoice''s lines.';

-- 4.2 enforce_invoice_has_snapshot: everything v5.4.2-04 checked at commit,
--     plus the binding re-run (issuance flavour).
CREATE OR REPLACE FUNCTION public.enforce_invoice_has_snapshot() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_snap public.invoice_calculation_snapshots%ROWTYPE;
    v_why  text;
BEGIN
    -- Only the transition INTO an issued status is gated. An already-issued
    -- invoice keeps living (collections, void) and its snapshot is frozen.
    IF NOT public.is_invoice_issued(NEW.status) THEN
        RETURN NULL;
    END IF;
    IF TG_OP = 'UPDATE' AND public.is_invoice_issued(OLD.status) THEN
        RETURN NULL;
    END IF;
    -- Voiding a never-issued (draft/held) invoice is a discard, not an
    -- issuance: nobody was billed, there is nothing to replay (Fable HIGH-1;
    -- void_invoice() lists held as voidable).
    IF TG_OP = 'UPDATE' AND NEW.status = 'void' THEN
        RETURN NULL;
    END IF;
    -- No lock on the snapshot row here: the snapshot/reference guards take
    -- the invoice FOR SHARE, so a concurrent delete/insert waits behind this
    -- transaction's row lock and re-reads the committed (issued) status.
    -- Locking here would deadlock against a waiting delete (and FOR UPDATE
    -- needs the UPDATE privilege tally_app deliberately lacks).
    SELECT * INTO v_snap FROM public.invoice_calculation_snapshots s WHERE s.invoice_id = NEW.id;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING
            MESSAGE = format('invoice %s cannot be issued (status %s) without a calculation snapshot (CI-015): insert invoice_calculation_snapshots in the same transaction, after the line items', NEW.invoice_number, NEW.status),
            ERRCODE = 'check_violation';
    END IF;
    IF (v_snap.period_inputs ->> 'period_start')::date IS DISTINCT FROM NEW.period_start
       OR (v_snap.period_inputs ->> 'period_end')::date IS DISTINCT FROM NEW.period_end
       OR v_snap.billing_run_id IS DISTINCT FROM NEW.billing_run_id
       OR (v_snap.customer_inputs ->> 'customer_id')::uuid IS DISTINCT FROM NEW.customer_id THEN
        RAISE EXCEPTION USING
            MESSAGE = format('invoice %s cannot be issued: its calculation snapshot no longer matches the invoice (period, billing run or customer changed after the snapshot) — delete and re-snapshot (CI-015)', NEW.invoice_number),
            ERRCODE = 'check_violation';
    END IF;
    -- v5.4.2-10: the coordinate pair must still be admissible for the invoice
    -- as it is being issued (the freezes make this hold unless a superuser
    -- bypassed them; this is the last word).
    v_why := public.calculation_snapshot_coordinate_violation(NEW, v_snap.valid_at, v_snap.recorded_at, true);
    IF v_why IS NOT NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('invoice %s cannot be issued: its calculation snapshot''s coordinate pair is no longer admissible — %s (v5.4.2-10); delete and re-snapshot', NEW.invoice_number, v_why),
            ERRCODE = 'check_violation';
    END IF;
    -- The lines ARE locked: A-4's line guard reads the invoice without a
    -- lock, so a concurrent line edit would otherwise be invisible here
    -- (Fable CRITICAL-2 variant B).
    PERFORM 1 FROM public.invoice_line_items l WHERE l.invoice_id = NEW.id FOR SHARE;
    IF NOT public.calculation_snapshot_line_items_match(NEW.id, v_snap.line_items) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('invoice %s cannot be issued: its line items changed after the calculation snapshot was taken — delete and re-snapshot (CI-015)', NEW.invoice_number),
            ERRCODE = 'check_violation';
    END IF;
    RETURN NULL;
END;
$$;

COMMENT ON FUNCTION public.enforce_invoice_has_snapshot() IS
    'CI-015 completeness (v5.4.2-04; coordinate re-check added v5.4.2-10): at commit of any transaction that moves an invoice into an issued status (is_invoice_issued; INSERT included), exactly one invoice_calculation_snapshots row must exist for it and still agree with the invoice (period, billing run, customer, line id set + amounts), and its (valid_at, recorded_at) must still be admissible per calculation_snapshot_coordinate_violation(…, true) — a correction''s valid_at is not re-derived (the current-rules election is CURRENT_DATE at insert; the -10 freezes hold it). Voiding a draft/held invoice (a discard) is exempt. DEFERRABLE INITIALLY DEFERRED so the check runs at commit; the write order is invoice → lines → snapshot → status flip. Locks the lines (FOR SHARE) so a concurrent line edit is waited for and seen.';

-- ----------------------------------------------------------------------------
-- 5. ENABLE ALWAYS on every guard this patch created (D-2026-08-20-27). The
--    two redefined functions keep their existing (ENABLE ALWAYS) triggers.
-- ----------------------------------------------------------------------------
DO $$
DECLARE
    r record;
BEGIN
    FOR r IN
        SELECT c.relname, t.tgname
        FROM pg_trigger t
        JOIN pg_class c ON c.oid = t.tgrelid
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public'
          AND NOT t.tgisinternal
          AND t.tgname IN ('a_enforce_billing_run_clock_and_election',
                           'a_enforce_correction_target_frozen_under_snapshot',
                           'a_enforce_invoice_snapshot_inputs')
          AND t.tgenabled <> 'A'
    LOOP
        EXECUTE format('ALTER TABLE public.%I ENABLE ALWAYS TRIGGER %I', r.relname, r.tgname);
    END LOOP;
END;
$$;

-- ----------------------------------------------------------------------------
-- 6. Comment refresh (append the -10 rule) and the report — never a refusal:
--    pre-patch snapshots are immutable and are counted, not corrected.
-- ----------------------------------------------------------------------------

COMMENT ON COLUMN public.invoice_calculation_snapshots.valid_at IS
    'Valid-time coordinate the run passed to every *_as_of lookup (AC-15). BOUND since v5.4.2-10: an ordinary bill''s valid_at IS its invoice''s period_end; a correction''s IS get_correction_rate_date(run, replaced invoice) — the original period (CI-005), the session''s CURRENT_DATE at insert (current-rules election) or the operator''s override (custom) — checked at insert against a correction_run_targets row that is then frozen.';
COMMENT ON COLUMN public.invoice_calculation_snapshots.recorded_at IS
    'Transaction-time coordinate the run passed to every *_as_of lookup (AC-15). BOUND since v5.4.2-10: within [billing_runs.started_at, now()] for a run''s invoice (the run must have started; started_at is the database''s clock), within [invoices.created_at, now()] for an off-run invoice, or — for a correction only — exactly the replaced bill''s snapshot recorded_at (original-world replay). Never in the future.';
COMMENT ON COLUMN public.billing_runs.started_at IS
    'When the run began. Since v5.4.2-10 the database''s clock: stamped now() when set (INSERT with a value or NULL -> value), write-once afterwards (superusers exempt). It is the lower bound every calculation snapshot on the run is checked against; a run without started_at cannot receive snapshots.';
COMMENT ON COLUMN public.correction_run_targets.rate_date_mode IS
    'Per-target rate date control for Phase 5. run_default=inherit billing_runs.correction_rate_mode; historical=force voided invoice period_end; current=force CURRENT_DATE; custom=use rate_date_override. Since v5.4.2-10 this election (with rate_date_override, billing_run_id, voided_invoice_id) is frozen — and the row undeletable — once a calculation snapshot exists for the correction invoice that replaces voided_invoice_id on billing_run_id.';
COMMENT ON COLUMN public.billing_runs.correction_rate_mode IS
    'For run_type=correction only. Controls the rate effective date used in Phase 5. historical=use voided invoice period_end (RRC-compliant default); current=use CURRENT_DATE. Per-target correction_run_targets.rate_date_mode overrides this. Since v5.4.2-10 frozen while any calculation snapshot cites the run.';

DO $$
DECLARE
    v_bad  bigint;
    v_runs bigint;
BEGIN
    SELECT count(*) INTO v_bad
      FROM public.invoice_calculation_snapshots s
      JOIN public.invoices i ON i.id = s.invoice_id
     WHERE public.calculation_snapshot_coordinate_violation(i, s.valid_at, s.recorded_at, true) IS NOT NULL;
    IF v_bad > 0 THEN
        RAISE NOTICE 'v5.4.2-10: % existing calculation snapshot(s) carry a coordinate pair the binding would now refuse (unbound before this patch); they are immutable and are left as recorded — draft/held ones can be deleted and re-snapshotted, issued ones are the record they are', v_bad;
    END IF;
    SELECT count(DISTINCT s.billing_run_id) INTO v_runs
      FROM public.invoice_calculation_snapshots s
      JOIN public.billing_runs b ON b.id = s.billing_run_id
     WHERE b.started_at IS NULL;
    IF v_runs > 0 THEN
        RAISE NOTICE 'v5.4.2-10: % billing run(s) carry snapshots but no started_at; new snapshots on them are refused until the run is started (started_at is stamped by the database when set)', v_runs;
    END IF;
END;
$$;

-- ============================================================================
-- END PATCH v5.4.2-10
-- ============================================================================
