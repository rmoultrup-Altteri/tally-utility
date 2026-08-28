-- ============================================================================
-- PATCH v5.4.2-05 — A-20: read/bill exception queue and validation-state
--                    substrate (schema-parity-plan Phase 4 Wave 2, Appendix
--                    A-20; CI-112 / CI-113 / CI-115 / CI-023)
-- ============================================================================
-- Authority:   canonical-invariants.md CI-112 (read exception resolved before
--              billing — three named resolution paths, reason code recorded),
--              CI-113 (consecutive-estimate cap; Kyle D14-1: per METER, reset
--              only on a VALIDATED actual read, RF-collision estimates COUNT),
--              CI-115 (pre-mail exception routing + pre-delivery control
--              gate), CI-023's last clause ("billing against an incomplete
--              meter master record is rejected; the meter enters an exception
--              queue" — the completeness discipline v5.4.0-02 deliberately
--              left for A-20); configurable-rules decision tables
--              consecutive-estimate-enforcement (#4, rows 1–4),
--              exception-threshold-and-routing (#35, queue / blocks_delivery /
--              sla / escalation outputs), billing-run-read-gating (#30);
--              workflows flagged-read-analyst-review (Exc 2/3) and
--              pre-mail-exception-review.
--
-- What lands:
--
--   1. read_validation_exceptions — one row per failed rule per read
--      (rule_code enumerates CI-112's list plus consecutive_estimate_over_cap
--      and meter_master_incomplete). A row is open until resolved exactly
--      once with a disposition from CI-112's set (estimate_accepted |
--      manual_read_entered | read_corrected | field_order_dispatched |
--      excluded | override), a non-empty reason code, a resolver and a
--      server-stamped time; a field order or a replacement read must be
--      named when the disposition says so, and must belong to the same
--      meter. A resolved row is frozen; rows are never deleted (CI-014 set).
--      Exc 3 (flagged-read-analyst-review): consecutive_estimate_over_cap
--      resolves only by override or field_order_dispatched.
--
--   2. The read gate (CI-112): every step of meter_readings.validation_status
--      into approved / released_to_billing / locked (by UPDATE, or by INSERT
--      born there) is refused while the read has an open exception — an
--      exception raised after approval stops the read at the next step;
--      reviewed_clean requires no open exception; reviewed_with_exception
--      requires at least one exception row (INSERT included). An exception
--      cannot be raised on a locked / void_released (billed) read — that is
--      a replacement reading's job. billing_run_meters may not record billed /
--      billed_estimated against a read with an open exception (the
--      bill-generation side of the same invariant).
--
--   3. The consecutive-estimate counter (CI-113, D14-1): meters gains
--      consecutive_estimate_count / consecutive_estimate_streak_started_on /
--      last_validated_actual_reading_id, maintained ONLY by the read gate on
--      a main-register read's VALIDATION EVENT — its first entry into
--      approved / released_to_billing / locked, stamped into
--      meter_readings.validated_at (server clock, frozen) — at most once per
--      read (an estimate dated after the last validated actual → +1; an
--      actual dated at/after it → the streak becomes the validated
--      estimates dated after it, normally 0, and it is remembered); direct
--      writes to the three columns are rejected (pg_trigger_depth — no GUC
--      carve-out). consecutive_estimate_state(meter) recomputes all three
--      from validated_at order (backfill source; reconciliation check —
--      stored must always equal derived). The cap is
--      tenants.settings.estimation.max_consecutive_estimates (default 3,
--      must be ≥ 1). Inserting an estimated main-register read that would
--      reach the cap auto-raises an open consecutive_estimate_over_cap
--      exception (rows 3/4 of table #4: field order or reason-coded
--      override are the only exits); approving such a read without that
--      resolved exception is rejected even if the exception was never
--      raised (cap lowered after insert; or several estimates were pending
--      together — the auto-raise counts pending estimates too). A read born
--      approved cannot be over cap.
--
--   4. invoice_exceptions — the pre-mail queue (CI-115): one row per
--      criterion per invoice (CI-115's list + unresolved_read_exception,
--      batch_baseline_breach, meter_master_incomplete, manual), with table
--      #35's outputs stored on the row (queue, blocks_delivery, sla_days,
--      escalation_target, routing_reason), optional links to anomalies and
--      to the read exception carried forward, and a status of open |
--      resolved | overridden — the latter two require a reason code, a
--      resolver and a server-stamped time, then freeze. blocks_delivery is
--      frozen at insert (flipping it would be an override in disguise) and
--      cannot be true on an already-delivered invoice.
--
--   5. The pre-delivery gate (CI-115): invoices may not move into pending
--      (from draft or held — the release from hold) or into sent, nor have
--      sent_at / delivery_confirmed_at stamped, while an open
--      blocks_delivery exception exists. Holding is the workflow's write
--      (A-4 forbids pending → held, so the hold must precede the release);
--      the gate is what makes the hold non-optional.
--
--   6. Lineage (CI-088 via CI-115): every invoice_exceptions insert and
--      every resolution/override appends an invoice_events row
--      (exception_raised | exception_resolved | exception_overridden — the
--      event_type enum is extended). Read-side lineage is the exception row
--      itself (open once, resolved once, frozen).
--
--   7. Meter master completeness (CI-023): meter_master_incomplete_reasons
--      (meter) lists the attributes the volume-to-energy formula needs and
--      the row lacks (rollover point or dial count; pressure class for gas;
--      meter factor for elevated pressure); billing_run_meters rejects
--      billed / billed_estimated for such a meter, naming the reasons — the
--      meter goes to the exception queue (rule meter_master_incomplete),
--      not the bill stream. temperature_compensated still does not exist
--      (unruled) and is not checked.
--
--   8. Tenant binding: UNIQUE (id, tenant_id) on meters, meter_readings and
--      service_orders so the new FKs are composite (the A-1/A-3 rule); the
--      plain FKs to users (raised_by / resolved_by / assigned_to) and
--      anomalies are tenant-checked by the guards (Codex round 1). RLS +
--      FORCE with the standard policy on both new tables; REVOKE DELETE from
--      tally_app; both tables join the CI-014 set; every guard ENABLE ALWAYS.
--
-- Deferred with stated triggers (not in this patch): queue/role substrate
-- (table #35 rows 1–2 are role names — pending-decision rbac-model; queue is
-- stored as an enum string here); SLA escalation processing (columns exist,
-- the escalation is a job); a CHECK bounding the Texas tenant's cap at the
-- 6-month ceiling (table #4 open question — Kyle); anomalies.entity_type
-- CHECK (table #35 open question 2 — factual-defect set candidate); the
-- row-2 "require actual read attempt" at cap − 1 (a dispatch decision, not a
-- state — read-cycle workflow); snooze vs blocks_delivery (open question 4 —
-- invoice_exceptions has no snooze; the anomaly may snooze, the gate does
-- not).
--
-- Preconditions: none are refusals. Historical reads in a billable state get
-- validated_at from locked_at / created_at (approximation, reported; a read
-- excluded before this patch cannot be told from one never validated and is
-- not counted — from this patch on, exclusion after validation keeps it); the
-- counter is backfilled for every meter (consecutive_estimate_state) and the
-- patch reports how many meters start at or above their cap and whether any
-- tenant's cap setting is < 1 (reported, never fatal at apply time).
-- Existing invoices/reads carry no exception rows — the gates apply from
-- this patch forward. Estimates that were already pending at patch time
-- raised no auto-exception; approving one at the cap is refused until an
-- operator raises consecutive_estimate_over_cap by hand and resolves it.
--
-- Drafting decisions (durable copies: application/DECISION-LOG.md):
--   * The counter is STORED and trigger-maintained, with a derivation
--     function beside it. D14-1 ruled the shape (per meter, validated-actual
--     reset, cause-indifferent) but not stored-vs-derived; a stored value is
--     what a CHECK-shaped gate can read at approval time without a history
--     scan, and the derivation makes it auditable (battery asserts stored =
--     derived after every transition).
--   * The streak = the VALIDATED estimates (validated_at set) whose
--     reading_date lies after the latest-dated validated actual. Validation
--     (validated_at) decides membership — a read excluded after it was
--     validated stays counted, a re-approval after pending_review is not a
--     new event; reading_date decides order — a back-dated actual validated
--     later does NOT clear estimates dated after it (the customer is still
--     being estimated for those periods; Codex round 2 showed the naive
--     "any validated actual resets" let five estimates pass a cap of 3),
--     and a same-day estimate beside an actual is not counted. This refines
--     D14-1b ("resets only on a validated actual read") to "…dated at or
--     after the streak" — flagged for Kyle, since the ruling did not
--     consider out-of-order validation. Fable round 1: the rework loop
--     double-counted one estimate to the cap; a same-day estimate + actual
--     broke the backfill; exclusion desynced stored from derived — all
--     closed by the same definition, used by the gate, the derivation and
--     the backfill. validated_at is the existing v5.2.1 column, now
--     server-stamped and frozen — the one repurposing this patch makes.
--   * Once validated (approved or beyond), a read's is_estimated,
--     register_type, meter_id, reading_date and tenant_id are frozen — the
--     v5.2.1 whitelist froze them only at 'locked', which left a window in
--     which flipping is_estimated desynced the counter from its derivation
--     (author's second pass).
--   * "Validated actual read" = a non-estimated main-register read entering
--     validation_status = 'approved' (passed VEE / auto-approved / operator-
--     accepted — approved is the single choke point the existing transition
--     matrix routes every billing-bound read through). A read excluded or
--     voided after approval does not un-count; a replacement actual that is
--     approved resets. RF-collision estimates count because nothing about
--     estimation_reason is consulted (D14-1c).
--   * Counter columns are protected by pg_trigger_depth(), not a GUC: the
--     meters guard allows the write only when it arrives from inside another
--     trigger (the read gate). There is nothing for a caller to arm.
--   * The over-cap exception is raised BY THE DATABASE on insert of the
--     estimate (AFTER INSERT), not by the workflow: CI-113 says the cap is
--     enforced, and an exception the application forgot to raise would be
--     no enforcement. The approval gate re-checks independently.
--   * Resolution dispositions are enumerated per CI-112 and constrained per
--     rule where the corpus names a narrower path (Exc 3); the reason code
--     is free text NOT NULL (no reason-code catalogue exists yet — its
--     enumeration is a later patch that adds a CHECK, not a redesign).
--   * The pre-delivery gate refuses the transition; it does not auto-hold.
--     A trigger that rewrites invoices.status from inside an exception
--     insert would fight A-4's transition rules (pending → held is
--     backward) and hide the operator action CI-115 wants recorded.
--   * invoice_exceptions cascade on invoice delete (only a draft can be
--     deleted — A-4; the A-3 reasoning); read_validation_exceptions never
--     cascade (meter_readings are never deleted).
--   * Functions are pinned SET search_path = public, pg_temp with every
--     reference qualified (D-2026-08-28-22: '' breaks the RLS helpers).
--
-- Verification contract: this file applies standalone under
--   SET search_path = ''; SET check_function_bodies = on;
-- (D-2026-08-20-24). Every relation and function reference is qualified.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Tenant-bound identity for composite FKs
-- ----------------------------------------------------------------------------
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'meters_id_tenant_id_key' AND conrelid = 'public.meters'::regclass) THEN
        ALTER TABLE public.meters ADD CONSTRAINT meters_id_tenant_id_key UNIQUE (id, tenant_id);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'meter_readings_id_tenant_id_key' AND conrelid = 'public.meter_readings'::regclass) THEN
        ALTER TABLE public.meter_readings ADD CONSTRAINT meter_readings_id_tenant_id_key UNIQUE (id, tenant_id);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'service_orders_id_tenant_id_key' AND conrelid = 'public.service_orders'::regclass) THEN
        ALTER TABLE public.service_orders ADD CONSTRAINT service_orders_id_tenant_id_key UNIQUE (id, tenant_id);
    END IF;
END;
$$;

-- ----------------------------------------------------------------------------
-- 2. Consecutive-estimate counter (CI-113, D14-1)
-- ----------------------------------------------------------------------------
ALTER TABLE public.meters
    ADD COLUMN IF NOT EXISTS consecutive_estimate_count integer DEFAULT 0 NOT NULL,
    ADD COLUMN IF NOT EXISTS consecutive_estimate_streak_started_on date,
    ADD COLUMN IF NOT EXISTS last_validated_actual_reading_id uuid;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'meters_consecutive_estimate_count_check' AND conrelid = 'public.meters'::regclass) THEN
        ALTER TABLE public.meters ADD CONSTRAINT meters_consecutive_estimate_count_check CHECK (consecutive_estimate_count >= 0);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'meters_streak_consistent_check' AND conrelid = 'public.meters'::regclass) THEN
        ALTER TABLE public.meters ADD CONSTRAINT meters_streak_consistent_check
            CHECK ((consecutive_estimate_count = 0 AND consecutive_estimate_streak_started_on IS NULL)
                OR (consecutive_estimate_count > 0 AND consecutive_estimate_streak_started_on IS NOT NULL));
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'meters_last_validated_actual_reading_id_fkey' AND conrelid = 'public.meters'::regclass) THEN
        ALTER TABLE public.meters ADD CONSTRAINT meters_last_validated_actual_reading_id_fkey
            FOREIGN KEY (last_validated_actual_reading_id, tenant_id) REFERENCES public.meter_readings(id, tenant_id)
            DEFERRABLE INITIALLY DEFERRED;   -- a read born approved resets the meter before its own row exists
    END IF;
END;
$$;

COMMENT ON COLUMN public.meters.consecutive_estimate_count IS
    'CI-113 / D14-1 (v5.4.2-05): number of consecutive estimated main-register reads approved for this meter since the last VALIDATED actual read (a non-estimated read that reached validation_status = approved). Maintained only by enforce_read_exception_gate(); direct writes are rejected. Cause-indifferent (an RF-collision estimate counts). derive_consecutive_estimate_count(id) recomputes it from history.';
COMMENT ON COLUMN public.meters.consecutive_estimate_streak_started_on IS 'reading_date of the first estimate in the current streak; NULL when the count is 0.';
COMMENT ON COLUMN public.meters.last_validated_actual_reading_id IS 'The read that last reset the streak (D14-1b: passed VEE or operator-accepted, i.e. reached approved). NULL until one has.';

CREATE OR REPLACE FUNCTION public.max_consecutive_estimates(p_tenant_id uuid) RETURNS integer
    LANGUAGE plpgsql STABLE
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_cap integer;
BEGIN
    SELECT coalesce((t.settings #>> '{estimation,max_consecutive_estimates}')::integer, 3)
      INTO v_cap
      FROM public.tenants t WHERE t.id = p_tenant_id;
    IF v_cap IS NULL THEN
        RAISE EXCEPTION USING MESSAGE = format('tenant %s not found (or not visible)', p_tenant_id), ERRCODE = 'no_data_found';
    END IF;
    IF v_cap < 1 THEN
        RAISE EXCEPTION USING
            MESSAGE = format('tenants.settings.estimation.max_consecutive_estimates = %s is invalid: the cap must be at least 1 (CI-113)', v_cap),
            ERRCODE = 'check_violation';
    END IF;
    RETURN v_cap;
END;
$$;

COMMENT ON FUNCTION public.max_consecutive_estimates(uuid) IS
    'The tenant''s consecutive-estimate cap: tenants.settings.estimation.max_consecutive_estimates, default 3, must be >= 1 (decision table #4). The Texas 6-month ceiling is NOT enforced here (open question for Kyle).';

CREATE OR REPLACE FUNCTION public.consecutive_estimate_state(p_meter_id uuid)
    RETURNS TABLE (cnt integer, started_on date, last_actual uuid)
    LANGUAGE sql STABLE
    SET search_path = public, pg_temp
    AS $$
    -- The streak is the set of VALIDATED estimates (validated_at set — a read
    -- excluded after validation stays counted) whose reading_date lies AFTER
    -- the latest-dated validated actual. A back-dated actual validated later
    -- does not clear estimates dated after it (the customer is still being
    -- estimated for those periods); a same-day estimate beside an actual is
    -- not counted (the actual covers that date). Main register only.
    WITH v AS (
        SELECT r.id, r.is_estimated, r.reading_date, r.validated_at
        FROM public.meter_readings r
        WHERE r.meter_id = p_meter_id AND r.register_type = 'main' AND r.validated_at IS NOT NULL
    ),
    la AS (
        SELECT v.id, v.reading_date FROM v WHERE NOT v.is_estimated
        ORDER BY v.reading_date DESC, v.validated_at DESC, v.id DESC LIMIT 1
    )
    SELECT (SELECT count(*)::integer FROM v WHERE v.is_estimated AND v.reading_date > coalesce((SELECT la.reading_date FROM la), DATE '0001-01-01')),
           (SELECT min(v.reading_date) FROM v WHERE v.is_estimated AND v.reading_date > coalesce((SELECT la.reading_date FROM la), DATE '0001-01-01')),
           (SELECT la.id FROM la);
$$;

COMMENT ON FUNCTION public.consecutive_estimate_state(uuid) IS
    'Recomputes (consecutive_estimate_count, consecutive_estimate_streak_started_on, last_validated_actual_reading_id) for a meter: validated main-register estimates dated after the latest-dated validated actual (validated_at marks validation; reading_date orders the streak). Backfill source and reconciliation check for the stored columns; the stored value must always equal this.';

CREATE OR REPLACE FUNCTION public.derive_consecutive_estimate_count(p_meter_id uuid) RETURNS integer
    LANGUAGE sql STABLE
    SET search_path = public, pg_temp
    AS $$ SELECT cnt FROM public.consecutive_estimate_state(p_meter_id) $$;

COMMENT ON FUNCTION public.derive_consecutive_estimate_count(uuid) IS 'consecutive_estimate_state(meter).cnt — the derived counter (CI-113).';

-- Backfill once. Step 1: validation events for history — every read already
-- in a billable state gets validated_at (locked_at, else created_at: an
-- approximation, reported). Step 2: the counter from the same function the
-- reconciliation uses. Re-runnable: step 1 matches nothing once stamped,
-- step 2 is skipped once any counter is populated.
DO $$
DECLARE
    v_stamped bigint;
    v_over bigint;
    v_badcap bigint;
BEGIN
    -- The UPDATEs fire the v5.2.1 triggers on these tables, whose bodies are
    -- unqualified; under the strict prelude they need a path for the length
    -- of this transaction (D-2026-08-28-22's class).
    PERFORM set_config('search_path', 'public, pg_temp', true);

    -- An app-set validated_at on a read that never reached a billable state
    -- is not a validation event (Fable round 2): clear it, report it.
    UPDATE public.meter_readings r
       SET validated_at = NULL
     WHERE r.validation_status NOT IN ('approved', 'released_to_billing', 'locked', 'void_released')
       AND r.validated_at IS NOT NULL;
    GET DIAGNOSTICS v_stamped = ROW_COUNT;
    IF v_stamped > 0 THEN
        RAISE NOTICE 'v5.4.2-05: validated_at cleared on % read(s) that never reached a billable state (the column now marks the validation event)', v_stamped;
    END IF;
    UPDATE public.meter_readings r
       SET validated_at = coalesce(r.locked_at, r.created_at)
     WHERE r.validation_status IN ('approved', 'released_to_billing', 'locked', 'void_released')
       AND r.validated_at IS NULL;
    GET DIAGNOSTICS v_stamped = ROW_COUNT;
    IF v_stamped > 0 THEN
        RAISE NOTICE 'v5.4.2-05: validated_at stamped on % historical read(s) from locked_at/created_at (approximation of the validation instant)', v_stamped;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.meters m WHERE m.consecutive_estimate_count > 0 OR m.last_validated_actual_reading_id IS NOT NULL) THEN
        UPDATE public.meters m
           SET consecutive_estimate_count = st.cnt,
               consecutive_estimate_streak_started_on = st.started_on,
               last_validated_actual_reading_id = st.last_actual
          FROM (SELECT m2.id, st2.* FROM public.meters m2 CROSS JOIN LATERAL public.consecutive_estimate_state(m2.id) st2) st
         WHERE st.id = m.id
           AND (st.cnt > 0 OR st.last_actual IS NOT NULL);
        -- Reporting only — never a refusal: a misconfigured cap is named, not fatal.
        SELECT count(*) INTO v_badcap FROM public.tenants t
         WHERE coalesce((t.settings #>> '{estimation,max_consecutive_estimates}')::integer, 3) < 1;
        IF v_badcap > 0 THEN
            RAISE NOTICE 'v5.4.2-05: % tenant(s) have settings.estimation.max_consecutive_estimates < 1; max_consecutive_estimates() will raise for them until corrected', v_badcap;
        END IF;
        SELECT count(*) INTO v_over
          FROM public.meters m JOIN public.tenants t ON t.id = m.tenant_id
         WHERE m.consecutive_estimate_count >= greatest(coalesce((t.settings #>> '{estimation,max_consecutive_estimates}')::integer, 3), 1);
        IF v_over > 0 THEN
            RAISE NOTICE 'v5.4.2-05: % meter(s) start at or above their consecutive-estimate cap; their next estimate cannot be approved without a field order or a reason-coded override (CI-113)', v_over;
        END IF;
    END IF;
END;
$$;

COMMENT ON COLUMN public.meter_readings.validated_at IS
    'Since v5.4.2-05: the instant the read first entered a billable validation_status (approved / released_to_billing / locked) — stamped by enforce_read_exception_gate() with the server clock (clock_timestamp(), so events in one transaction stay ordered), caller values replaced, frozen once set, NULL until then. The consecutive-estimate streak is ordered by this column. Historical reads were stamped from locked_at/created_at at patch time.';

-- Counter columns are written only from inside the read gate (trigger depth).
CREATE OR REPLACE FUNCTION public.enforce_meter_estimate_counter() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
BEGIN
    IF (OLD.consecutive_estimate_count IS DISTINCT FROM NEW.consecutive_estimate_count
        OR OLD.consecutive_estimate_streak_started_on IS DISTINCT FROM NEW.consecutive_estimate_streak_started_on
        OR OLD.last_validated_actual_reading_id IS DISTINCT FROM NEW.last_validated_actual_reading_id)
       AND pg_trigger_depth() < 2 THEN
        RAISE EXCEPTION USING
            MESSAGE = format('meter %s: consecutive_estimate_count / streak columns are maintained by the read validation gate only (CI-113, D14-1) — approve or reset through meter_readings.validation_status', OLD.id),
            ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS enforce_meter_estimate_counter ON public.meters;
CREATE TRIGGER enforce_meter_estimate_counter BEFORE UPDATE ON public.meters
    FOR EACH ROW EXECUTE FUNCTION public.enforce_meter_estimate_counter();

-- ----------------------------------------------------------------------------
-- 3. Meter master completeness (CI-023)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.meter_master_incomplete_reasons(p_meter_id uuid) RETURNS text[]
    LANGUAGE plpgsql STABLE
    SET search_path = public, pg_temp
    AS $$
DECLARE
    m public.meters%ROWTYPE;
    v text[] := ARRAY[]::text[];
BEGIN
    SELECT * INTO m FROM public.meters x WHERE x.id = p_meter_id;
    IF NOT FOUND THEN
        RETURN ARRAY['meter not found (or not visible)'];
    END IF;
    IF m.rollover_point IS NULL AND m.dial_count IS NULL THEN
        v := array_append(v, 'rollover_point or dial_count');
    END IF;
    IF m.service_type = 'gas' THEN
        IF m.meter_pressure_class IS NULL THEN
            v := array_append(v, 'meter_pressure_class');
        ELSIF m.meter_pressure_class = 'elevated' AND m.meter_factor IS NULL THEN
            v := array_append(v, 'meter_factor (elevated pressure)');
        END IF;
    END IF;
    RETURN v;
END;
$$;

COMMENT ON FUNCTION public.meter_master_incomplete_reasons(uuid) IS
    'CI-023 (v5.4.2-05): the master attributes the volume-to-energy formula depends on that this meter lacks — empty array = complete. Checked: rollover_point or dial_count; for gas, meter_pressure_class, and meter_factor when elevated. multiplier is NOT NULL already; temperature_compensated does not exist (unruled). billing_run_meters refuses billed/billed_estimated for an incomplete meter.';

-- Tenant binding for the plain FKs to users / anomalies (Codex round 1: a
-- T2 user's id was accepted as resolved_by on a T1 row — FK checks bypass
-- RLS, so the guard must check the referenced row's tenant itself).
CREATE OR REPLACE FUNCTION public.assert_same_tenant_user(p_user_id uuid, p_tenant_id uuid, p_column text) RETURNS void
    LANGUAGE plpgsql STABLE
    SET search_path = public, pg_temp
    AS $$
BEGIN
    IF p_user_id IS NULL THEN RETURN; END IF;
    IF NOT EXISTS (SELECT 1 FROM public.users u WHERE u.id = p_user_id AND (u.tenant_id = p_tenant_id OR u.role = 'platform_admin')) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('%s must name a user of tenant %s (or a platform admin)', p_column, p_tenant_id),
            ERRCODE = 'check_violation';
    END IF;
END;
$$;

COMMENT ON FUNCTION public.assert_same_tenant_user(uuid, uuid, text) IS 'v5.4.2-05: the referenced user must belong to the row''s tenant (platform admins excepted). Used by the exception guards for raised_by / resolved_by / assigned_to.';

-- ----------------------------------------------------------------------------
-- 4. read_validation_exceptions (CI-112)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.read_validation_exceptions (
    id                      uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id               uuid NOT NULL,
    meter_reading_id        uuid NOT NULL,
    meter_id                uuid NOT NULL,
    rule_code               text NOT NULL,
    severity                text DEFAULT 'medium' NOT NULL,
    detail                  jsonb DEFAULT '{}'::jsonb NOT NULL,
    detected_at             timestamp with time zone DEFAULT now() NOT NULL,
    detected_by             text DEFAULT 'system' NOT NULL,
    raised_by_user_id       uuid,
    status                  text DEFAULT 'open' NOT NULL,
    resolution_disposition  text,
    resolution_reason_code  text,
    resolution_notes        text,
    resolved_by             uuid,
    resolved_at             timestamp with time zone,
    field_order_id          uuid,
    replacement_reading_id  uuid,
    notes                   text,
    created_at              timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT read_validation_exceptions_pkey PRIMARY KEY (id),
    CONSTRAINT read_validation_exceptions_id_tenant_id_key UNIQUE (id, tenant_id),
    CONSTRAINT read_validation_exceptions_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id),
    CONSTRAINT read_validation_exceptions_reading_fkey FOREIGN KEY (meter_reading_id, tenant_id) REFERENCES public.meter_readings(id, tenant_id),
    CONSTRAINT read_validation_exceptions_meter_fkey FOREIGN KEY (meter_id, tenant_id) REFERENCES public.meters(id, tenant_id),
    CONSTRAINT read_validation_exceptions_raised_by_fkey FOREIGN KEY (raised_by_user_id) REFERENCES public.users(id),
    CONSTRAINT read_validation_exceptions_resolved_by_fkey FOREIGN KEY (resolved_by) REFERENCES public.users(id),
    CONSTRAINT read_validation_exceptions_field_order_fkey FOREIGN KEY (field_order_id, tenant_id) REFERENCES public.service_orders(id, tenant_id),
    CONSTRAINT read_validation_exceptions_replacement_fkey FOREIGN KEY (replacement_reading_id, tenant_id) REFERENCES public.meter_readings(id, tenant_id),
    CONSTRAINT read_validation_exceptions_rule_code_check CHECK (rule_code = ANY (ARRAY[
        'high_vs_history'::text, 'low_vs_history'::text, 'reverse_read'::text, 'max_dial_rollover'::text,
        'consecutive_estimate_over_cap'::text, 'zero_read_active_account'::text, 'reading_date_gap'::text,
        'negative_consumption'::text, 'meter_master_incomplete'::text, 'tamper_indicated'::text, 'other'::text])),
    CONSTRAINT read_validation_exceptions_severity_check CHECK (severity = ANY (ARRAY['low'::text, 'medium'::text, 'high'::text, 'critical'::text])),
    CONSTRAINT read_validation_exceptions_detected_by_check CHECK (detected_by = ANY (ARRAY['system'::text, 'operator'::text, 'import'::text])),
    CONSTRAINT read_validation_exceptions_status_check CHECK (status = ANY (ARRAY['open'::text, 'resolved'::text])),
    CONSTRAINT read_validation_exceptions_disposition_check CHECK (resolution_disposition IS NULL OR resolution_disposition = ANY (ARRAY[
        'estimate_accepted'::text, 'manual_read_entered'::text, 'read_corrected'::text, 'field_order_dispatched'::text, 'excluded'::text, 'override'::text])),
    CONSTRAINT read_validation_exceptions_detail_check CHECK (jsonb_typeof(detail) = 'object'),
    CONSTRAINT read_validation_exceptions_resolution_consistent_check CHECK (
        (status = 'open' AND resolution_disposition IS NULL AND resolution_reason_code IS NULL AND resolved_by IS NULL AND resolved_at IS NULL
             AND field_order_id IS NULL AND replacement_reading_id IS NULL)
     OR (status = 'resolved' AND resolution_disposition IS NOT NULL AND resolution_reason_code IS NOT NULL AND length(btrim(resolution_reason_code)) > 0 AND resolved_by IS NOT NULL AND resolved_at IS NOT NULL)),
    CONSTRAINT read_validation_exceptions_disposition_links_check CHECK (
        status = 'open'
     OR (resolution_disposition = 'field_order_dispatched' AND field_order_id IS NOT NULL)
     OR (resolution_disposition IN ('manual_read_entered', 'read_corrected') AND replacement_reading_id IS NOT NULL)
     OR (resolution_disposition IN ('estimate_accepted', 'excluded', 'override'))),
    CONSTRAINT read_validation_exceptions_over_cap_path_check CHECK (
        status = 'open' OR rule_code <> 'consecutive_estimate_over_cap'
     OR resolution_disposition IN ('override', 'field_order_dispatched'))
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_read_validation_exceptions_open_rule
    ON public.read_validation_exceptions USING btree (meter_reading_id, rule_code) WHERE (status = 'open');
CREATE INDEX IF NOT EXISTS idx_read_validation_exceptions_tenant_open
    ON public.read_validation_exceptions USING btree (tenant_id, status) WHERE (status = 'open');
CREATE INDEX IF NOT EXISTS idx_read_validation_exceptions_meter ON public.read_validation_exceptions USING btree (meter_id);
CREATE INDEX IF NOT EXISTS idx_read_validation_exceptions_reading ON public.read_validation_exceptions USING btree (meter_reading_id);

ALTER TABLE public.read_validation_exceptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.read_validation_exceptions FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_isolation ON public.read_validation_exceptions;
CREATE POLICY tenant_isolation ON public.read_validation_exceptions USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));

COMMENT ON TABLE public.read_validation_exceptions IS
    'CI-112 read exception queue (v5.4.2-05, A-20). One row per failed validation rule per read. Open until resolved exactly once with a CI-112 disposition (estimate_accepted | manual_read_entered | read_corrected | field_order_dispatched | excluded | override), a reason code, a resolver and a server-stamped time; a resolved row is frozen; rows are never deleted. A read with an open row cannot reach approved / released_to_billing and cannot be billed (enforce_read_exception_gate, billing_run_meters guard). consecutive_estimate_over_cap rows are raised by the database and resolve only by override or field_order_dispatched (CI-113 rows 3/4).';
COMMENT ON COLUMN public.read_validation_exceptions.resolution_reason_code IS 'Free text, required at resolution (CI-112 "with a reason code recorded"). No catalogue exists yet; a later patch may add a CHECK.';
COMMENT ON COLUMN public.read_validation_exceptions.field_order_id IS 'Required when resolution_disposition = field_order_dispatched; must be a service_orders row for the same meter.';
COMMENT ON COLUMN public.read_validation_exceptions.replacement_reading_id IS 'Required when resolution_disposition ∈ (manual_read_entered, read_corrected); must be a different meter_readings row for the same meter.';

CREATE OR REPLACE FUNCTION public.enforce_read_validation_exception() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_read   public.meter_readings%ROWTYPE;
    v_meter  uuid;
BEGIN
    IF TG_OP = 'INSERT' THEN
        -- FOR SHARE: serialises against a concurrent validation of the same read.
        SELECT * INTO v_read FROM public.meter_readings r WHERE r.id = NEW.meter_reading_id FOR SHARE;
        IF NOT FOUND THEN
            RAISE EXCEPTION USING MESSAGE = format('read exception rejected: reading %s not found (or not visible)', NEW.meter_reading_id), ERRCODE = 'foreign_key_violation';
        END IF;
        IF v_read.validation_status IN ('locked', 'void_released') THEN
            RAISE EXCEPTION USING MESSAGE = format('read exception rejected: reading %s is %s (already billed) — a problem found now is corrected with a replacement reading, not an exception on the billed one (CI-012)', NEW.meter_reading_id, v_read.validation_status), ERRCODE = 'check_violation';
        END IF;
        IF v_read.tenant_id <> NEW.tenant_id OR v_read.meter_id <> NEW.meter_id THEN
            RAISE EXCEPTION USING MESSAGE = 'read exception rejected: tenant_id and meter_id must be the reading''s', ERRCODE = 'check_violation';
        END IF;
        IF NEW.status <> 'open' THEN
            RAISE EXCEPTION USING MESSAGE = 'read exception rejected: a row is born open and resolved by a later UPDATE (the resolution is the lineage, CI-088)', ERRCODE = 'check_violation';
        END IF;
        PERFORM public.assert_same_tenant_user(NEW.raised_by_user_id, NEW.tenant_id, 'raised_by_user_id');
        NEW.detected_at := now();
        NEW.created_at := now();
        RETURN NEW;
    END IF;

    -- UPDATE
    IF OLD.status = 'resolved' THEN
        RAISE EXCEPTION USING
            MESSAGE = format('read exception %s is resolved and frozen (CI-112 / CI-088): a disposition is never edited — raise a new exception if the read fails again', OLD.id),
            ERRCODE = 'check_violation';
    END IF;
    -- Identity of an open row is frozen; only severity/detail/notes and the resolution may change.
    IF OLD.id <> NEW.id OR OLD.tenant_id <> NEW.tenant_id OR OLD.meter_reading_id <> NEW.meter_reading_id OR OLD.meter_id <> NEW.meter_id
       OR OLD.rule_code <> NEW.rule_code OR OLD.detected_at <> NEW.detected_at OR OLD.detected_by <> NEW.detected_by
       OR OLD.raised_by_user_id IS DISTINCT FROM NEW.raised_by_user_id OR OLD.created_at <> NEW.created_at THEN
        RAISE EXCEPTION USING MESSAGE = format('read exception %s: identity columns are frozen', OLD.id), ERRCODE = 'check_violation';
    END IF;
    IF NEW.status = 'resolved' THEN
        NEW.resolved_at := now();
        PERFORM public.assert_same_tenant_user(NEW.resolved_by, OLD.tenant_id, 'resolved_by');
        IF NEW.resolution_disposition = 'field_order_dispatched' THEN
            SELECT so.meter_id INTO v_meter FROM public.service_orders so WHERE so.id = NEW.field_order_id;
            IF NOT FOUND OR v_meter IS DISTINCT FROM OLD.meter_id THEN
                RAISE EXCEPTION USING MESSAGE = format('read exception %s: field_order_id must name a service order for meter %s', OLD.id, OLD.meter_id), ERRCODE = 'check_violation';
            END IF;
        ELSIF NEW.resolution_disposition IN ('manual_read_entered', 'read_corrected') THEN
            SELECT r.meter_id INTO v_meter FROM public.meter_readings r WHERE r.id = NEW.replacement_reading_id;
            IF NOT FOUND OR v_meter IS DISTINCT FROM OLD.meter_id OR NEW.replacement_reading_id = OLD.meter_reading_id THEN
                RAISE EXCEPTION USING MESSAGE = format('read exception %s: replacement_reading_id must name a different reading of meter %s', OLD.id, OLD.meter_id), ERRCODE = 'check_violation';
            END IF;
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.enforce_read_validation_exception() IS
    'read_validation_exceptions guard (v5.4.2-05): born open in the reading''s tenant/meter with server stamps; open rows may change severity/detail/notes or resolve (once — resolved_at forced to now(); field order / replacement read verified against the same meter); resolved rows are frozen. Table CHECKs carry the disposition and over-cap path rules.';

DROP TRIGGER IF EXISTS a_enforce_read_validation_exception ON public.read_validation_exceptions;
CREATE TRIGGER a_enforce_read_validation_exception BEFORE INSERT OR UPDATE ON public.read_validation_exceptions
    FOR EACH ROW EXECUTE FUNCTION public.enforce_read_validation_exception();

-- ----------------------------------------------------------------------------
-- 5. The read gate + counter maintenance on meter_readings (CI-112, CI-113)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.enforce_read_exception_gate() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_billable boolean;          -- NEW is in a billable state
    v_transition boolean;        -- entering a billable state from a non-billable one (or born there)
    v_first boolean;             -- the read's FIRST validation event (validated_at not yet set)
    v_open_rules text;
    v_count integer;
    v_cap integer;
    v_last_actual_date date;
BEGIN
    v_billable := NEW.validation_status IN ('approved', 'released_to_billing', 'locked');
    v_transition := v_billable AND (TG_OP = 'INSERT' OR OLD.validation_status NOT IN ('approved', 'released_to_billing', 'locked', 'void_released'));

    -- validated_at is the database's: NULL until the first validation event,
    -- then frozen. Caller values are replaced.
    IF TG_OP = 'INSERT' THEN
        NEW.validated_at := NULL;
    ELSE
        NEW.validated_at := OLD.validated_at;
    END IF;
    v_first := v_billable AND NEW.validated_at IS NULL;

    -- Once validated, the facts the streak was derived from are frozen (the
    -- v5.2.1 whitelist only froze them at 'locked'; flipping is_estimated on
    -- an approved read desynced the counter from its derivation).
    IF TG_OP = 'UPDATE' AND OLD.validated_at IS NOT NULL
       AND (OLD.is_estimated <> NEW.is_estimated OR OLD.register_type <> NEW.register_type OR OLD.meter_id <> NEW.meter_id
            OR OLD.reading_date <> NEW.reading_date OR OLD.tenant_id <> NEW.tenant_id) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('reading %s is validated (%s): is_estimated, register_type, meter_id, reading_date and tenant_id are frozen (CI-113 counter derivation) — correct it with a replacement reading', OLD.id, OLD.validation_status),
            ERRCODE = 'check_violation';
    END IF;

    IF NEW.validation_status = 'reviewed_clean' AND (TG_OP = 'INSERT' OR OLD.validation_status IS DISTINCT FROM 'reviewed_clean') THEN
        IF EXISTS (SELECT 1 FROM public.read_validation_exceptions e WHERE e.meter_reading_id = NEW.id AND e.status = 'open') THEN
            RAISE EXCEPTION USING MESSAGE = format('reading %s cannot be reviewed_clean while an exception is open (CI-112)', NEW.id), ERRCODE = 'check_violation';
        END IF;
    END IF;
    IF NEW.validation_status = 'reviewed_with_exception' AND (TG_OP = 'INSERT' OR OLD.validation_status IS DISTINCT FROM 'reviewed_with_exception') THEN
        IF NOT EXISTS (SELECT 1 FROM public.read_validation_exceptions e WHERE e.meter_reading_id = NEW.id) THEN
            RAISE EXCEPTION USING MESSAGE = format('reading %s cannot be reviewed_with_exception without a read_validation_exceptions row naming the failed rule (CI-112)', NEW.id), ERRCODE = 'check_violation';
        END IF;
    END IF;

    -- CI-112: no open exception may ride into, or further along, billing —
    -- checked on EVERY step into approved / released_to_billing / locked.
    IF v_billable AND (TG_OP = 'INSERT' OR OLD.validation_status IS DISTINCT FROM NEW.validation_status) THEN
        SELECT string_agg(e.rule_code, ', ' ORDER BY e.rule_code) INTO v_open_rules
          FROM public.read_validation_exceptions e WHERE e.meter_reading_id = NEW.id AND e.status = 'open';
        IF v_open_rules IS NOT NULL THEN
            RAISE EXCEPTION USING
                MESSAGE = format('reading %s cannot enter %s: open validation exception(s) %s must be resolved first — estimate accepted, manual read entered, field order dispatched, or a reason-coded override (CI-112)', NEW.id, NEW.validation_status, v_open_rules),
                ERRCODE = 'check_violation';
        END IF;
    END IF;

    IF NOT v_first THEN
        RETURN NEW;   -- re-entries (approved -> pending_review -> approved) are not new validation events
    END IF;
    -- clock_timestamp(), not now(): two reads validated in one transaction
    -- must still have a definite order (the streak is ordered by this stamp).
    NEW.validated_at := clock_timestamp();

    -- CI-113 / D14-1: the counter moves at most once per main-register read,
    -- on its validation event, in READING-DATE terms: an estimate counts only
    -- if dated after the latest validated actual; an actual resets only if it
    -- is dated at/after that actual (a back-dated correction does not clear
    -- estimates dated after it — Codex round 2 showed the naive reset let
    -- estimates run past the cap).
    IF NEW.register_type <> 'main' THEN
        RETURN NEW;
    END IF;
    SELECT m.consecutive_estimate_count, a.reading_date
      INTO v_count, v_last_actual_date
      FROM public.meters m
      LEFT JOIN public.meter_readings a ON a.id = m.last_validated_actual_reading_id
     WHERE m.id = NEW.meter_id
       FOR UPDATE OF m;
    IF NOT FOUND THEN
        RETURN NEW;   -- FK will reject the insert anyway
    END IF;
    IF NEW.is_estimated THEN
        IF v_last_actual_date IS NOT NULL AND NEW.reading_date <= v_last_actual_date THEN
            RETURN NEW;   -- dated at/before the last validated actual: not part of the streak
        END IF;
        v_cap := public.max_consecutive_estimates(NEW.tenant_id);
        IF v_count + 1 >= v_cap
           AND NOT EXISTS (SELECT 1 FROM public.read_validation_exceptions e
                            WHERE e.meter_reading_id = NEW.id AND e.rule_code = 'consecutive_estimate_over_cap'
                              AND e.status = 'resolved' AND e.resolution_disposition IN ('override', 'field_order_dispatched')) THEN
            RAISE EXCEPTION USING
                MESSAGE = format('reading %s: approving this estimate makes %s consecutive estimates on meter %s (cap %s) — a bill cannot be generated against an over-cap streak without a field order or a reason-coded override on the consecutive_estimate_over_cap exception (CI-113, D14-1)', NEW.id, v_count + 1, NEW.meter_id, v_cap),
                ERRCODE = 'check_violation';
        END IF;
        UPDATE public.meters m
           SET consecutive_estimate_count = v_count + 1,
               consecutive_estimate_streak_started_on = CASE WHEN v_count = 0 THEN NEW.reading_date ELSE least(m.consecutive_estimate_streak_started_on, NEW.reading_date) END
         WHERE m.id = NEW.meter_id;
    ELSE
        IF v_last_actual_date IS NOT NULL AND NEW.reading_date < v_last_actual_date THEN
            RETURN NEW;   -- back-dated actual: the later actual still bounds the streak
        END IF;
        -- This actual is the latest-dated: the streak is whatever validated
        -- estimates are dated after it (usually none).
        UPDATE public.meters m
           SET consecutive_estimate_count = s.cnt,
               consecutive_estimate_streak_started_on = s.started_on,
               last_validated_actual_reading_id = NEW.id
          FROM (SELECT count(*)::integer AS cnt, min(r.reading_date) AS started_on
                  FROM public.meter_readings r
                 WHERE r.meter_id = NEW.meter_id AND r.register_type = 'main' AND r.is_estimated
                   AND r.validated_at IS NOT NULL AND r.reading_date > NEW.reading_date) s
         WHERE m.id = NEW.meter_id;
    END IF;
    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.enforce_read_exception_gate() IS
    'CI-112 + CI-113 gate on meter_readings (v5.4.2-05). Every step into approved / released_to_billing / locked (by UPDATE, or born there) requires no open read_validation_exceptions row; reviewed_clean requires none open, reviewed_with_exception requires one to exist (INSERT included). validated_at is stamped with the server clock on the read''s FIRST billable entry and frozen; on that event — once per main-register read, re-entries do not recount — the meter''s streak moves: an estimate increments it (refused at the cap unless a consecutive_estimate_over_cap exception on this read was resolved by override or field order), a non-estimated read resets it and is remembered as last_validated_actual_reading_id (D14-1). Once validated, is_estimated / register_type / meter_id / reading_date / tenant_id are frozen. Runs after enforce_reading_validation_workflow (name-ordered).';

DROP TRIGGER IF EXISTS z_enforce_read_exception_gate ON public.meter_readings;
CREATE TRIGGER z_enforce_read_exception_gate BEFORE INSERT OR UPDATE ON public.meter_readings
    FOR EACH ROW EXECUTE FUNCTION public.enforce_read_exception_gate();

-- The database raises the over-cap exception when the estimate is recorded.
CREATE OR REPLACE FUNCTION public.raise_consecutive_estimate_exception() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_count integer;
    v_cap integer;
    v_last_actual_date date;
BEGIN
    IF NOT NEW.is_estimated OR NEW.register_type <> 'main'
       OR NEW.validation_status IN ('approved', 'released_to_billing', 'locked', 'void_released', 'excluded') THEN
        RETURN NULL;
    END IF;
    -- Stored streak + estimates already waiting (not yet validated, not
    -- excluded/voided, dated after the last validated actual) + this one.
    SELECT m.consecutive_estimate_count
         + (SELECT count(*) FROM public.meter_readings p
             WHERE p.meter_id = NEW.meter_id AND p.register_type = 'main' AND p.is_estimated
               AND p.validated_at IS NULL AND p.id <> NEW.id
               AND p.validation_status <> 'excluded' AND p.status NOT IN ('voided', 'replaced')
               AND (a.reading_date IS NULL OR p.reading_date > a.reading_date)),
           a.reading_date
      INTO v_count, v_last_actual_date
      FROM public.meters m LEFT JOIN public.meter_readings a ON a.id = m.last_validated_actual_reading_id
     WHERE m.id = NEW.meter_id;
    IF v_last_actual_date IS NOT NULL AND NEW.reading_date <= v_last_actual_date THEN
        RETURN NULL;   -- dated at/before the last validated actual: cannot extend the streak
    END IF;
    v_cap := public.max_consecutive_estimates(NEW.tenant_id);
    IF v_count + 1 >= v_cap THEN
        INSERT INTO public.read_validation_exceptions (tenant_id, meter_reading_id, meter_id, rule_code, severity, detail, detected_by)
        VALUES (NEW.tenant_id, NEW.id, NEW.meter_id, 'consecutive_estimate_over_cap', 'high',
                jsonb_build_object('consecutive_estimate_count_before', v_count, 'would_become', v_count + 1, 'cap', v_cap,
                                   'estimation_reason', NEW.estimation_reason, 'streak_started_on', (SELECT m.consecutive_estimate_streak_started_on FROM public.meters m WHERE m.id = NEW.meter_id)),
                'system')
        ON CONFLICT DO NOTHING;
    END IF;
    RETURN NULL;
END;
$$;

COMMENT ON FUNCTION public.raise_consecutive_estimate_exception() IS
    'CI-113 rows 3/4 (v5.4.2-05): when an estimated main-register read is inserted in a pre-approval state and would bring the meter to its cap (stored streak + estimates already pending + this one), the database opens a consecutive_estimate_over_cap exception (severity high; estimation_reason recorded for triage, D14-1c — the counter is cause-indifferent). Only a field order or a reason-coded override can resolve it.';

DROP TRIGGER IF EXISTS z_raise_consecutive_estimate_exception ON public.meter_readings;
CREATE TRIGGER z_raise_consecutive_estimate_exception AFTER INSERT ON public.meter_readings
    FOR EACH ROW EXECUTE FUNCTION public.raise_consecutive_estimate_exception();

-- Bill-generation side (CI-112) + master completeness (CI-023) on billing_run_meters.
CREATE OR REPLACE FUNCTION public.enforce_billing_run_meter_gate() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_open_rules text;
    v_reasons text[];
BEGIN
    IF NEW.outcome NOT IN ('billed', 'billed_estimated') THEN
        RETURN NEW;
    END IF;
    IF TG_OP = 'UPDATE' AND OLD.outcome IN ('billed', 'billed_estimated') AND OLD.meter_reading_id IS NOT DISTINCT FROM NEW.meter_reading_id AND OLD.meter_id = NEW.meter_id THEN
        RETURN NEW;   -- already billed on this read; not re-gating lifecycle edits
    END IF;
    IF NEW.meter_reading_id IS NOT NULL THEN
        SELECT string_agg(e.rule_code, ', ' ORDER BY e.rule_code) INTO v_open_rules
          FROM public.read_validation_exceptions e WHERE e.meter_reading_id = NEW.meter_reading_id AND e.status = 'open';
        IF v_open_rules IS NOT NULL THEN
            RAISE EXCEPTION USING
                MESSAGE = format('billing_run_meters: meter %s cannot be billed against reading %s — open validation exception(s) %s (CI-112)', NEW.meter_id, NEW.meter_reading_id, v_open_rules),
                ERRCODE = 'check_violation';
        END IF;
    END IF;
    v_reasons := public.meter_master_incomplete_reasons(NEW.meter_id);
    IF cardinality(v_reasons) > 0 THEN
        RAISE EXCEPTION USING
            MESSAGE = format('billing_run_meters: meter %s master record is incomplete (%s) — it belongs in the exception queue (read_validation_exceptions rule meter_master_incomplete), not the bill stream (CI-023)', NEW.meter_id, array_to_string(v_reasons, '; ')),
            ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.enforce_billing_run_meter_gate() IS
    'billing_run_meters guard (v5.4.2-05): an outcome of billed / billed_estimated is refused while the read carries an open read_validation_exceptions row (CI-112) or the meter master is incomplete per meter_master_incomplete_reasons() (CI-023).';

DROP TRIGGER IF EXISTS enforce_billing_run_meter_gate ON public.billing_run_meters;
CREATE TRIGGER enforce_billing_run_meter_gate BEFORE INSERT OR UPDATE ON public.billing_run_meters
    FOR EACH ROW EXECUTE FUNCTION public.enforce_billing_run_meter_gate();

-- ----------------------------------------------------------------------------
-- 6. invoice_exceptions — the pre-mail queue (CI-115)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.invoice_exceptions (
    id                          uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id                   uuid NOT NULL,
    invoice_id                  uuid NOT NULL,
    billing_run_id              uuid,
    criterion                   text NOT NULL,
    severity                    text DEFAULT 'medium' NOT NULL,
    exception_source            text DEFAULT 'bill_detector' NOT NULL,
    detail                      jsonb DEFAULT '{}'::jsonb NOT NULL,
    estimated_impact            numeric(12,2),
    queue                       text NOT NULL,
    blocks_delivery             boolean NOT NULL,
    sla_days                    integer,
    escalation_target           text,
    routing_reason              text NOT NULL,
    anomaly_id                  uuid,
    read_validation_exception_id uuid,
    detected_at                 timestamp with time zone DEFAULT now() NOT NULL,
    raised_by_user_id           uuid,
    assigned_to                 uuid,
    status                      text DEFAULT 'open' NOT NULL,
    resolution_reason_code      text,
    resolution_notes            text,
    resolved_by                 uuid,
    resolved_at                 timestamp with time zone,
    notes                       text,
    created_at                  timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT invoice_exceptions_pkey PRIMARY KEY (id),
    CONSTRAINT invoice_exceptions_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id),
    CONSTRAINT invoice_exceptions_invoice_fkey FOREIGN KEY (invoice_id, tenant_id) REFERENCES public.invoices(id, tenant_id) ON DELETE CASCADE,
    CONSTRAINT invoice_exceptions_billing_run_id_fkey FOREIGN KEY (billing_run_id) REFERENCES public.billing_runs(id),
    CONSTRAINT invoice_exceptions_anomaly_id_fkey FOREIGN KEY (anomaly_id) REFERENCES public.anomalies(id),
    CONSTRAINT invoice_exceptions_read_exception_fkey FOREIGN KEY (read_validation_exception_id, tenant_id) REFERENCES public.read_validation_exceptions(id, tenant_id),
    CONSTRAINT invoice_exceptions_raised_by_fkey FOREIGN KEY (raised_by_user_id) REFERENCES public.users(id),
    CONSTRAINT invoice_exceptions_assigned_to_fkey FOREIGN KEY (assigned_to) REFERENCES public.users(id),
    CONSTRAINT invoice_exceptions_resolved_by_fkey FOREIGN KEY (resolved_by) REFERENCES public.users(id),
    CONSTRAINT invoice_exceptions_criterion_check CHECK (criterion = ANY (ARRAY[
        'high_bill'::text, 'zero_bill_active_account'::text, 'negative_bill'::text, 'consecutive_estimate_streak'::text,
        'out_of_tolerance_usage'::text, 'rider_trueup_over_threshold'::text, 'missing_rebill_approval'::text,
        'unresolved_read_exception'::text, 'batch_baseline_breach'::text, 'meter_master_incomplete'::text,
        'tamper_detected'::text, 'canary_mismatch'::text, 'manual'::text, 'other'::text])),
    CONSTRAINT invoice_exceptions_severity_check CHECK (severity = ANY (ARRAY['low'::text, 'medium'::text, 'high'::text, 'critical'::text])),
    CONSTRAINT invoice_exceptions_source_check CHECK (exception_source = ANY (ARRAY['bill_detector'::text, 'batch_baseline'::text, 'read_carryforward'::text, 'manual'::text])),
    CONSTRAINT invoice_exceptions_queue_check CHECK (queue = ANY (ARRAY['batch_hold'::text, 'billing_analyst'::text, 'senior_analyst'::text, 'csr'::text, 'field_ops'::text, 'informational'::text])),
    CONSTRAINT invoice_exceptions_escalation_check CHECK (escalation_target IS NULL OR escalation_target = ANY (ARRAY['senior_analyst'::text, 'billing_manager'::text, 'cfo'::text])),
    CONSTRAINT invoice_exceptions_sla_check CHECK (sla_days IS NULL OR sla_days >= 0),
    CONSTRAINT invoice_exceptions_status_check CHECK (status = ANY (ARRAY['open'::text, 'resolved'::text, 'overridden'::text])),
    CONSTRAINT invoice_exceptions_detail_check CHECK (jsonb_typeof(detail) = 'object'),
    CONSTRAINT invoice_exceptions_routing_reason_check CHECK (routing_reason IS NOT NULL AND length(btrim(routing_reason)) > 0),
    CONSTRAINT invoice_exceptions_carryforward_check CHECK (criterion <> 'unresolved_read_exception' OR read_validation_exception_id IS NOT NULL),
    CONSTRAINT invoice_exceptions_resolution_consistent_check CHECK (
        (status = 'open' AND resolution_reason_code IS NULL AND resolved_by IS NULL AND resolved_at IS NULL)
     OR (status IN ('resolved', 'overridden') AND resolution_reason_code IS NOT NULL AND length(btrim(resolution_reason_code)) > 0 AND resolved_by IS NOT NULL AND resolved_at IS NOT NULL))
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_invoice_exceptions_open_criterion
    ON public.invoice_exceptions USING btree (invoice_id, criterion) WHERE (status = 'open');
CREATE INDEX IF NOT EXISTS idx_invoice_exceptions_open_blocking
    ON public.invoice_exceptions USING btree (invoice_id) WHERE (status = 'open' AND blocks_delivery);
CREATE INDEX IF NOT EXISTS idx_invoice_exceptions_tenant_queue
    ON public.invoice_exceptions USING btree (tenant_id, queue, status);
CREATE INDEX IF NOT EXISTS idx_invoice_exceptions_billing_run ON public.invoice_exceptions USING btree (billing_run_id) WHERE (billing_run_id IS NOT NULL);

ALTER TABLE public.invoice_exceptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.invoice_exceptions FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_isolation ON public.invoice_exceptions;
CREATE POLICY tenant_isolation ON public.invoice_exceptions USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));

COMMENT ON TABLE public.invoice_exceptions IS
    'CI-115 pre-mail exception queue (v5.4.2-05, A-20). One row per exception criterion per invoice, carrying decision table #35''s routing outputs (queue, blocks_delivery, sla_days, escalation_target, routing_reason). Open until resolved or overridden — both require a reason code, a resolver and a server-stamped time, then the row is frozen. While an open row has blocks_delivery = true the invoice cannot enter pending (release from hold) or sent, and cannot be stamped delivered (enforce_invoice_predelivery_gate). blocks_delivery is frozen at insert and cannot be true on an already-delivered invoice. Every insert / resolution appends an invoice_events row. Queue values are strings until the rbac-model decision lands.';
COMMENT ON COLUMN public.invoice_exceptions.blocks_delivery IS 'Table #35''s control output: the invoice may not be delivered while this is open. Frozen at insert — clearing it is an override, which is a status with a reason code.';
COMMENT ON COLUMN public.invoice_exceptions.status IS 'open → resolved (the bill was corrected or the exception judged not applicable) or → overridden (the flagged bill goes out as-is, by reason-coded decision — CI-115''s escape hatch). Both terminal.';

CREATE OR REPLACE FUNCTION public.enforce_invoice_exception() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_inv public.invoices%ROWTYPE;
BEGIN
    IF TG_OP = 'INSERT' THEN
        SELECT * INTO v_inv FROM public.invoices i WHERE i.id = NEW.invoice_id FOR SHARE;
        IF NOT FOUND THEN
            RAISE EXCEPTION USING MESSAGE = format('invoice exception rejected: invoice %s not found (or not visible)', NEW.invoice_id), ERRCODE = 'foreign_key_violation';
        END IF;
        IF v_inv.tenant_id <> NEW.tenant_id THEN
            RAISE EXCEPTION USING MESSAGE = 'invoice exception rejected: tenant_id must equal the invoice''s', ERRCODE = 'check_violation';
        END IF;
        IF NEW.billing_run_id IS NULL THEN
            NEW.billing_run_id := v_inv.billing_run_id;
        ELSIF NEW.billing_run_id IS DISTINCT FROM v_inv.billing_run_id THEN
            RAISE EXCEPTION USING MESSAGE = 'invoice exception rejected: billing_run_id must equal the invoice''s', ERRCODE = 'check_violation';
        END IF;
        IF NEW.status <> 'open' THEN
            RAISE EXCEPTION USING MESSAGE = 'invoice exception rejected: a row is born open; resolve or override it by a later UPDATE (the lineage, CI-088)', ERRCODE = 'check_violation';
        END IF;
        IF NEW.blocks_delivery AND (v_inv.sent_at IS NOT NULL OR v_inv.delivery_confirmed_at IS NOT NULL
                                    OR v_inv.status IN ('sent', 'paid', 'partial', 'overdue', 'write_off')) THEN
            RAISE EXCEPTION USING
                MESSAGE = format('invoice exception rejected: invoice %s is already delivered (status %s) — a pre-mail block is meaningless; raise it as blocks_delivery = false or use the dispute workflow', v_inv.invoice_number, v_inv.status),
                ERRCODE = 'check_violation';
        END IF;
        PERFORM public.assert_same_tenant_user(NEW.raised_by_user_id, NEW.tenant_id, 'raised_by_user_id');
        PERFORM public.assert_same_tenant_user(NEW.assigned_to, NEW.tenant_id, 'assigned_to');
        IF NEW.anomaly_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.anomalies a WHERE a.id = NEW.anomaly_id AND a.tenant_id = NEW.tenant_id) THEN
            RAISE EXCEPTION USING MESSAGE = 'invoice exception rejected: anomaly_id must name an anomaly of the same tenant', ERRCODE = 'check_violation';
        END IF;
        NEW.detected_at := now();
        NEW.created_at := now();
        RETURN NEW;
    END IF;

    IF OLD.status <> 'open' THEN
        RAISE EXCEPTION USING
            MESSAGE = format('invoice exception %s is %s and frozen (CI-115 / CI-088): a disposition is never edited — raise a new exception', OLD.id, OLD.status),
            ERRCODE = 'check_violation';
    END IF;
    IF OLD.id <> NEW.id OR OLD.tenant_id <> NEW.tenant_id OR OLD.invoice_id <> NEW.invoice_id OR OLD.billing_run_id IS DISTINCT FROM NEW.billing_run_id
       OR OLD.criterion <> NEW.criterion OR OLD.exception_source <> NEW.exception_source OR OLD.blocks_delivery <> NEW.blocks_delivery
       OR OLD.routing_reason <> NEW.routing_reason OR OLD.detected_at <> NEW.detected_at OR OLD.raised_by_user_id IS DISTINCT FROM NEW.raised_by_user_id
       OR OLD.anomaly_id IS DISTINCT FROM NEW.anomaly_id OR OLD.read_validation_exception_id IS DISTINCT FROM NEW.read_validation_exception_id
       OR OLD.created_at <> NEW.created_at THEN
        RAISE EXCEPTION USING
            MESSAGE = format('invoice exception %s: identity, blocks_delivery and routing_reason are frozen — clearing a block is an override (status = overridden, with a reason code)', OLD.id),
            ERRCODE = 'check_violation';
    END IF;
    IF OLD.assigned_to IS DISTINCT FROM NEW.assigned_to THEN
        PERFORM public.assert_same_tenant_user(NEW.assigned_to, OLD.tenant_id, 'assigned_to');
    END IF;
    IF NEW.status IN ('resolved', 'overridden') THEN
        NEW.resolved_at := now();
        PERFORM public.assert_same_tenant_user(NEW.resolved_by, OLD.tenant_id, 'resolved_by');
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS a_enforce_invoice_exception ON public.invoice_exceptions;
CREATE TRIGGER a_enforce_invoice_exception BEFORE INSERT OR UPDATE ON public.invoice_exceptions
    FOR EACH ROW EXECUTE FUNCTION public.enforce_invoice_exception();

-- Draft-invoice delete cascades; every other DELETE is rejected.
CREATE OR REPLACE FUNCTION public.enforce_invoice_exception_no_delete() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.invoices i WHERE i.id = OLD.invoice_id) THEN
        RETURN OLD;   -- cascade from a draft-invoice delete (A-4: only drafts are deletable)
    END IF;
    RAISE EXCEPTION USING
        MESSAGE = format('invoice_exceptions rows are never deleted (CI-014 / CI-088): exception %s stays as lineage — resolve or override it', OLD.id),
        ERRCODE = 'restrict_violation';
END;
$$;

DROP TRIGGER IF EXISTS no_hard_delete ON public.invoice_exceptions;
CREATE TRIGGER no_hard_delete BEFORE DELETE ON public.invoice_exceptions
    FOR EACH ROW EXECUTE FUNCTION public.enforce_invoice_exception_no_delete();
DROP TRIGGER IF EXISTS no_truncate ON public.invoice_exceptions;
CREATE TRIGGER no_truncate BEFORE TRUNCATE ON public.invoice_exceptions
    FOR EACH STATEMENT EXECUTE FUNCTION public.enforce_no_hard_delete();

-- Lineage: invoice_events (enum extended).
ALTER TABLE public.invoice_events DROP CONSTRAINT IF EXISTS invoice_events_event_type_check;
ALTER TABLE public.invoice_events ADD CONSTRAINT invoice_events_event_type_check CHECK ((event_type = ANY (ARRAY[
    'created'::text, 'sent'::text, 'held'::text, 'released_from_hold'::text, 'voided'::text, 'void_attempted_blocked'::text,
    'correction_initiated'::text, 'correction_posted'::text, 'payment_applied'::text, 'written_off'::text, 'status_changed'::text,
    'reversal_chain_depth_exceeded'::text, 'exception_raised'::text, 'exception_resolved'::text, 'exception_overridden'::text])));

CREATE OR REPLACE FUNCTION public.log_invoice_exception_event() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO public.invoice_events (tenant_id, invoice_id, event_type, operator_id, occurred_at, metadata)
        VALUES (NEW.tenant_id, NEW.invoice_id, 'exception_raised', NEW.raised_by_user_id, NEW.detected_at,
                jsonb_build_object('invoice_exception_id', NEW.id, 'criterion', NEW.criterion, 'severity', NEW.severity,
                                   'queue', NEW.queue, 'blocks_delivery', NEW.blocks_delivery, 'routing_reason', NEW.routing_reason));
    ELSIF OLD.status = 'open' AND NEW.status IN ('resolved', 'overridden') THEN
        INSERT INTO public.invoice_events (tenant_id, invoice_id, event_type, operator_id, occurred_at, metadata)
        VALUES (NEW.tenant_id, NEW.invoice_id, CASE WHEN NEW.status = 'resolved' THEN 'exception_resolved' ELSE 'exception_overridden' END,
                NEW.resolved_by, NEW.resolved_at,
                jsonb_build_object('invoice_exception_id', NEW.id, 'criterion', NEW.criterion, 'blocks_delivery', NEW.blocks_delivery,
                                   'resolution_reason_code', NEW.resolution_reason_code, 'resolution_notes', NEW.resolution_notes));
    END IF;
    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS z_log_invoice_exception_event ON public.invoice_exceptions;
CREATE TRIGGER z_log_invoice_exception_event AFTER INSERT OR UPDATE ON public.invoice_exceptions
    FOR EACH ROW EXECUTE FUNCTION public.log_invoice_exception_event();

-- ----------------------------------------------------------------------------
-- 7. The pre-delivery gate on invoices (CI-115)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.enforce_invoice_predelivery_gate() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_gated boolean := false;
    v_what text;
    v_criteria text;
BEGIN
    IF NEW.status = 'pending' AND OLD.status IN ('draft', 'held') THEN v_gated := true; v_what := 'enter pending'; END IF;
    IF NEW.status = 'sent' AND OLD.status <> 'sent' THEN v_gated := true; v_what := 'enter sent'; END IF;
    IF NEW.sent_at IS NOT NULL AND OLD.sent_at IS NULL THEN v_gated := true; v_what := 'be stamped sent_at'; END IF;
    IF NEW.delivery_confirmed_at IS NOT NULL AND OLD.delivery_confirmed_at IS NULL THEN v_gated := true; v_what := 'be stamped delivery_confirmed_at'; END IF;
    IF NOT v_gated THEN
        RETURN NEW;
    END IF;
    SELECT string_agg(e.criterion || ' (' || e.queue || ')', ', ' ORDER BY e.criterion) INTO v_criteria
      FROM public.invoice_exceptions e
     WHERE e.invoice_id = NEW.id AND e.status = 'open' AND e.blocks_delivery;
    IF v_criteria IS NOT NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('invoice %s cannot %s: open delivery-blocking exception(s) %s must be resolved or overridden with a reason code first (CI-115 pre-delivery control gate)', NEW.invoice_number, v_what, v_criteria),
            ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.enforce_invoice_predelivery_gate() IS
    'CI-115 (v5.4.2-05): an invoice with an open invoice_exceptions row where blocks_delivery = true may not enter pending (from draft or held), enter sent, or be stamped sent_at / delivery_confirmed_at. Holding is the workflow''s write (A-4 forbids pending → held, so hold before release); this gate makes the hold non-optional.';

DROP TRIGGER IF EXISTS enforce_invoice_predelivery_gate ON public.invoices;
CREATE TRIGGER enforce_invoice_predelivery_gate BEFORE UPDATE ON public.invoices
    FOR EACH ROW EXECUTE FUNCTION public.enforce_invoice_predelivery_gate();

-- ----------------------------------------------------------------------------
-- 8. CI-014 set, privileges, ENABLE ALWAYS
-- ----------------------------------------------------------------------------
DROP TRIGGER IF EXISTS no_hard_delete ON public.read_validation_exceptions;
CREATE TRIGGER no_hard_delete BEFORE DELETE ON public.read_validation_exceptions
    FOR EACH ROW EXECUTE FUNCTION public.enforce_no_hard_delete();
DROP TRIGGER IF EXISTS no_truncate ON public.read_validation_exceptions;
CREATE TRIGGER no_truncate BEFORE TRUNCATE ON public.read_validation_exceptions
    FOR EACH STATEMENT EXECUTE FUNCTION public.enforce_no_hard_delete();
REVOKE DELETE ON public.read_validation_exceptions FROM tally_app;
REVOKE DELETE ON public.invoice_exceptions FROM tally_app;

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
          AND t.tgenabled <> 'A'
          AND (
                (c.relname IN ('read_validation_exceptions', 'invoice_exceptions')
                 AND t.tgname IN ('no_hard_delete', 'no_truncate', 'a_enforce_read_validation_exception',
                                  'a_enforce_invoice_exception', 'z_log_invoice_exception_event'))
             OR (c.relname = 'meters' AND t.tgname = 'enforce_meter_estimate_counter')
             OR (c.relname = 'meter_readings' AND t.tgname IN ('z_enforce_read_exception_gate', 'z_raise_consecutive_estimate_exception'))
             OR (c.relname = 'billing_run_meters' AND t.tgname = 'enforce_billing_run_meter_gate')
             OR (c.relname = 'invoices' AND t.tgname = 'enforce_invoice_predelivery_gate')
          )
    LOOP
        EXECUTE format('ALTER TABLE public.%I ENABLE ALWAYS TRIGGER %I', r.relname, r.tgname);
    END LOOP;
END;
$$;

-- ----------------------------------------------------------------------------
-- 9. Cross-references on existing objects
-- ----------------------------------------------------------------------------
COMMENT ON COLUMN public.invoices.hold_reason IS
    'Why the invoice is held (required when status = held). Since v5.4.2-05 the pre-mail queue is invoice_exceptions: an open row with blocks_delivery = true prevents the release to pending and the transition to sent regardless of this text (CI-115).';
COMMENT ON COLUMN public.billing_run_meters.outcome IS
    'Phase-1 disposition of the meter in this run (decision table #30). Since v5.4.2-05, billed / billed_estimated are refused while the read has an open read_validation_exceptions row (CI-112) or the meter master is incomplete (CI-023, meter_master_incomplete_reasons()).';
