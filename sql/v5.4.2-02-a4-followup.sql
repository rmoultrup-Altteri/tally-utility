-- ============================================================================
-- PATCH v5.4.2-02 — A-4 follow-up: void_invoice() hardened, direct-void gated,
--                    guards ENABLE ALWAYS (post-landing assessment of v5.4.2-01)
-- ============================================================================
-- Authority:   Two independent post-landing assessments of v5.4.2-01 (Fable,
--              Codex; 2026-08-20), requested by Ryan, and Ryan's instruction
--              to fix now with the same review loop. No new spec authority;
--              nothing here changes a CI grade boundary (CI-012 stays
--              structurally-enforced, CI-013/014 partial). Appendix A-23 is
--              amended on the GBM side.
--
-- What was wrong:
--              * v5.4.2-01's header said "every object schema-qualified;
--                fresh-build safe under search_path = ''" and
--                DEPLOY-VERIFICATION recorded "search_path = '' clean". Both
--                FALSE for section 5: the re-issued void_invoice() body was
--                copied verbatim from v5.4.1-01 and carries eleven unqualified
--                relation references (invoices%ROWTYPE, FROM invoices,
--                UPDATE meter_readings / adhoc_charges / invoices, INSERT
--                INTO account_ledger / invoice_events, FROM account_ledger)
--                plus two unqualified function calls. The fresh build passed
--                only because postgres/00_preamble.sql sets
--                check_function_bodies = off; a standalone apply with
--                search_path = '' and default body checking fails at
--                "compilation of PL/pgSQL function void_invoice near line 3"
--                (the %ROWTYPE resolves at CREATE time). Inherited from
--                v5.4.1-01, repeated and mis-asserted by -01. Both earlier
--                review rounds fresh-loaded through the Docker image, so
--                the preamble masked it for them too — lesson recorded.
--              * void_invoice() is SECURITY DEFINER with no SET search_path
--                (proconfig NULL): the standard privilege-escalation vector
--                for definer functions. Re-issuing it was the moment to fix
--                that; -01 missed it.
--              * A bare UPDATE invoices SET status = 'void', voided_at =
--                now() on an issued invoice was accepted: no ledger
--                reversal, reads still locked, charges still billed — and
--                the row then sealed forever. -01 gated only the missing
--                voided_at. Not listed in A-23.
--              * Only 9 of the 77 v5.4.2-01 guard triggers were ENABLE
--                ALWAYS; the other 68 are skipped under
--                session_replication_role = replica (superuser / logical
--                replication apply only — tally_app cannot set it).
--              * The re-issued void_invoice() carried no fresh COMMENT; the
--                v5.4.1-01 text still described the function as never
--                clearing its carve-out.
--
-- What this patch does:
--              1. Re-issues void_invoice() with every relation and function
--                 reference schema-qualified and SET search_path = public,
--                 pg_temp pinned on the function. Not '' — tried first and
--                 it broke at runtime: the helpers and triggers the function
--                 fires (get_user_tenant_id() -> users, the invoice_events /
--                 account_ledger triggers) are unqualified v5.2.1 bodies
--                 that inherit the caller's path. Pinning to public closes
--                 the definer-hijack vector (the caller no longer controls
--                 resolution) without re-issuing half of tu.sql. Body otherwise
--                 byte-for-byte the v5.4.2-01 issue (which was the
--                 v5.4.1-01 issue + one set_config). Fresh COMMENT.
--              2. Re-issues enforce_invoice_immutable() with one added
--                 rule: writing status = 'void' — on UPDATE from ANY other
--                 status (draft and held included: void_invoice() voids
--                 held invoices, and a direct held->void would skip its
--                 reversal just the same) and on INSERT (the trigger now
--                 fires BEFORE INSERT OR UPDATE OR DELETE) — requires the
--                 app.void_operation carve-out, which void_invoice() arms
--                 at its Step 3 before its Step 5 UPDATE. The GUC is caller-settable (AC-12), so this is
--                 a fence against accident, not intent — the same honest
--                 grade as the read and charge guards — but it turns a
--                 one-column slip into a deliberate act that code review
--                 can grep for. All other -01 behaviour unchanged.
--              3. ENABLE ALWAYS on every v5.4.2-01 guard trigger (the 33-
--                 table loop's no_hard_delete / no_truncate, and the
--                 table-specific enforce_* guards on payments, adhoc_
--                 charges, customer_credits, invoice_applications) plus
--                 the three pre-existing immutability guards of the same
--                 kind (pga_monthly_reconciliations -06, tenant_
--                 configuration_history -02), so replication apply cannot
--                 silently skip CI-012/013/014 or those two tables.
--
-- Deliberately NOT done:
--              * The v5.4.2-01 patch file's false header sentence is left as
--                written — patch files are the historical record once
--                mirrored; the correction lives here and in DEPLOY-
--                VERIFICATION (a living document, corrected in place).
--              * Other SECURITY DEFINER functions in tu.sql without SET
--                search_path are not touched — out of A-4's scope; flagged
--                in DECISION-LOG for a factual-defect set.
--              * The judgment calls the assessors listed for Ryan (pending
--                = issued, due_date frozen, drafts deletable, write_off/paid
--                non-terminal, payments default 'posted', SECURITY-DEFINER
--                seal) are unchanged pending his ruling.
--
-- Verification contract for THIS patch: it must apply cleanly with
--   SET search_path = ''; SET check_function_bodies = on;
-- i.e. without the Docker preamble — that is the test -01 should have had.
-- Idempotent (CREATE OR REPLACE / ALTER ... ENABLE ALWAYS are re-runnable).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. void_invoice(): schema-qualified, search_path pinned to public, pg_temp, fresh COMMENT
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.void_invoice(p_invoice_id uuid, p_voided_by uuid DEFAULT NULL::uuid, p_void_reason_code text DEFAULT NULL::text, p_void_reason_notes text DEFAULT NULL::text, p_rebill_expected boolean DEFAULT true) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path = public, pg_temp
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
    SELECT running_balance INTO v_new_running_bal
    FROM public.account_ledger
    WHERE id = v_ledger_entry_id;

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

COMMENT ON FUNCTION public.void_invoice(p_invoice_id uuid, p_voided_by uuid, p_void_reason_code text, p_void_reason_notes text, p_rebill_expected boolean) IS
    'Atomically voids a posted invoice — the ONLY supported way to set invoices.status = ''void'' (v5.4.2-02: the invoice guard refuses a direct UPDATE to void outside this function''s carve-out). Steps: validate invoice + tenant (explicit cross-tenant check defends against RLS bypass), voidability + reason validation, duplicate-warning check, arm the app.void_operation carve-out (SET LOCAL), release locked reads, dispose billed adhoc charges (auto-revert to pending for wrong_read/wrong_rate/service_date_error/system_error, else void_pending_rebill), best-effort lookup of the original charge ledger row (CI-017 lineage, v5.4.1-01), post the void_reversal ledger entry, stamp void metadata, log the voided event, CLEAR the carve-out (v5.4.2-01 — it previously leaked to every later statement in the caller''s transaction), return a JSONB payload. SECURITY DEFINER with search_path pinned to public, pg_temp and every reference schema-qualified (v5.4.2-02). Single canonical 5-parameter signature since v5.2.1.';

-- ----------------------------------------------------------------------------
-- 2. enforce_invoice_immutable(): writing void requires the carve-out (INSERT too)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.enforce_invoice_immutable() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_changed text[] := '{}';
BEGIN
    IF TG_OP = 'DELETE' THEN
        IF OLD.status <> 'draft' THEN
            RAISE EXCEPTION USING
                MESSAGE = format('invoice %s (%s) cannot be hard-deleted (CI-012/CI-014): only draft invoices may be discarded; void it instead', OLD.invoice_number, OLD.status),
                ERRCODE = 'restrict_violation';
        END IF;
        -- A draft with posted dependents is not a discardable working row:
        -- fk_adhoc_invoice is ON DELETE SET NULL and would strand a billed
        -- charge; a locked read would lose its lock holder.
        IF EXISTS (SELECT 1 FROM public.adhoc_charges a WHERE a.billed_on_invoice_id = OLD.id)
           OR EXISTS (SELECT 1 FROM public.meter_readings r WHERE r.locked_by_invoice_id = OLD.id) THEN
            RAISE EXCEPTION USING
                MESSAGE = format('draft invoice %s has billed charges or locked reads attached (CI-014): release them before discarding the draft, or void it through void_invoice()', OLD.invoice_number),
                ERRCODE = 'restrict_violation';
        END IF;
        RETURN OLD;
    END IF;

    -- Entering void is void_invoice()'s job from ANY prior state (it treats
    -- held as voidable too) and on INSERT: it posts the reversal, releases
    -- locked reads and disposes of billed charges before stamping the row.
    -- A bare write to 'void' would skip all of that and then be sealed for
    -- good (assessment finding, v5.4.2-02; review moved it above the
    -- draft/held early-return and onto INSERT). Gate on the same carve-out
    -- the read and charge guards honour — caller-settable (AC-12), so a
    -- fence against accident, but it turns a one-column slip into a
    -- deliberate act.
    IF NEW.status = 'void'
       AND (TG_OP = 'INSERT' OR OLD.status <> 'void')
       AND NOT coalesce(current_setting('app.void_operation', true) = 'true', false) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('invoice %s: status = ''void'' is set by void_invoice() only (CI-012) — a direct write would void the bill without its ledger reversal, read release and charge disposition', NEW.invoice_number),
            ERRCODE = 'restrict_violation';
    END IF;
    IF TG_OP = 'INSERT' THEN
        RETURN NEW;
    END IF;

    -- UPDATE from here on.
    IF NOT public.is_invoice_issued(OLD.status) THEN
        RETURN NEW;   -- draft/held: working row, fully editable
    END IF;

    -- void is terminal: only annotation columns may change.
    IF OLD.status = 'void' THEN
        IF NEW.status IS DISTINCT FROM OLD.status
           OR (to_jsonb(NEW) - 'notes' - 'metadata' - 'updated_at') IS DISTINCT FROM (to_jsonb(OLD) - 'notes' - 'metadata' - 'updated_at') THEN
            RAISE EXCEPTION USING
                MESSAGE = format('invoice %s is void and sealed (CI-012): a voided bill is never edited or un-voided; the correction is the rebill', OLD.invoice_number),
                ERRCODE = 'restrict_violation';
        END IF;
        RETURN NEW;
    END IF;

    -- Entering void requires the stamp; once sealed it could never be added.
    IF NEW.status = 'void' AND NEW.voided_at IS NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('invoice %s: status = ''void'' requires voided_at (CI-012) — use void_invoice(), which also posts the reversal and releases reads', OLD.invoice_number),
            ERRCODE = 'restrict_violation';
    END IF;

    -- No backward transitions.
    IF NEW.status IN ('draft', 'held') THEN
        RAISE EXCEPTION USING
            MESSAGE = format('invoice %s cannot move from %s back to %s (CI-012): an issued bill is corrected by void + rebill, not by reopening it', OLD.invoice_number, OLD.status, NEW.status),
            ERRCODE = 'restrict_violation';
    END IF;

    -- Frozen set: what the customer saw.
    IF NEW.id                   IS DISTINCT FROM OLD.id                   THEN v_changed := v_changed || ARRAY['id']; END IF;
    IF NEW.tenant_id            IS DISTINCT FROM OLD.tenant_id            THEN v_changed := v_changed || ARRAY['tenant_id']; END IF;
    IF NEW.invoice_number       IS DISTINCT FROM OLD.invoice_number       THEN v_changed := v_changed || ARRAY['invoice_number']; END IF;
    IF NEW.billing_run_id       IS DISTINCT FROM OLD.billing_run_id       THEN v_changed := v_changed || ARRAY['billing_run_id']; END IF;
    IF NEW.customer_id          IS DISTINCT FROM OLD.customer_id          THEN v_changed := v_changed || ARRAY['customer_id']; END IF;
    IF NEW.location_id          IS DISTINCT FROM OLD.location_id          THEN v_changed := v_changed || ARRAY['location_id']; END IF;
    IF NEW.parent_invoice_id    IS DISTINCT FROM OLD.parent_invoice_id    THEN v_changed := v_changed || ARRAY['parent_invoice_id']; END IF;
    IF NEW.is_consolidated      IS DISTINCT FROM OLD.is_consolidated      THEN v_changed := v_changed || ARRAY['is_consolidated']; END IF;
    IF NEW.is_consolidated_child IS DISTINCT FROM OLD.is_consolidated_child THEN v_changed := v_changed || ARRAY['is_consolidated_child']; END IF;
    IF NEW.invoice_type         IS DISTINCT FROM OLD.invoice_type         THEN v_changed := v_changed || ARRAY['invoice_type']; END IF;
    IF NEW.replaces_invoice_id  IS DISTINCT FROM OLD.replaces_invoice_id  THEN v_changed := v_changed || ARRAY['replaces_invoice_id']; END IF;
    IF NEW.invoice_date         IS DISTINCT FROM OLD.invoice_date         THEN v_changed := v_changed || ARRAY['invoice_date']; END IF;
    IF NEW.billing_period       IS DISTINCT FROM OLD.billing_period       THEN v_changed := v_changed || ARRAY['billing_period']; END IF;
    IF NEW.period_start         IS DISTINCT FROM OLD.period_start         THEN v_changed := v_changed || ARRAY['period_start']; END IF;
    IF NEW.period_end           IS DISTINCT FROM OLD.period_end           THEN v_changed := v_changed || ARRAY['period_end']; END IF;
    IF NEW.due_date             IS DISTINCT FROM OLD.due_date             THEN v_changed := v_changed || ARRAY['due_date']; END IF;
    IF NEW.previous_balance     IS DISTINCT FROM OLD.previous_balance     THEN v_changed := v_changed || ARRAY['previous_balance']; END IF;
    IF NEW.total_charges        IS DISTINCT FROM OLD.total_charges        THEN v_changed := v_changed || ARRAY['total_charges']; END IF;
    IF NEW.total_credits        IS DISTINCT FROM OLD.total_credits        THEN v_changed := v_changed || ARRAY['total_credits']; END IF;
    IF NEW.total_taxes          IS DISTINCT FROM OLD.total_taxes          THEN v_changed := v_changed || ARRAY['total_taxes']; END IF;
    IF NEW.total_adjustments    IS DISTINCT FROM OLD.total_adjustments    THEN v_changed := v_changed || ARRAY['total_adjustments']; END IF;
    IF NEW.amount_due           IS DISTINCT FROM OLD.amount_due           THEN v_changed := v_changed || ARRAY['amount_due']; END IF;
    IF NEW.tax_breakdown        IS DISTINCT FROM OLD.tax_breakdown        THEN v_changed := v_changed || ARRAY['tax_breakdown']; END IF;
    IF NEW.has_estimated_reads  IS DISTINCT FROM OLD.has_estimated_reads  THEN v_changed := v_changed || ARRAY['has_estimated_reads']; END IF;
    IF NEW.estimated_read_count IS DISTINCT FROM OLD.estimated_read_count THEN v_changed := v_changed || ARRAY['estimated_read_count']; END IF;
    IF NEW.has_anomalies        IS DISTINCT FROM OLD.has_anomalies        THEN v_changed := v_changed || ARRAY['has_anomalies']; END IF;
    IF NEW.created_at           IS DISTINCT FROM OLD.created_at           THEN v_changed := v_changed || ARRAY['created_at']; END IF;
    -- pdf_url / pdf_generated_at: write-once (the artifact the customer received).
    IF OLD.pdf_url IS NOT NULL AND NEW.pdf_url IS DISTINCT FROM OLD.pdf_url THEN v_changed := v_changed || ARRAY['pdf_url']; END IF;
    IF OLD.pdf_generated_at IS NOT NULL AND NEW.pdf_generated_at IS DISTINCT FROM OLD.pdf_generated_at THEN v_changed := v_changed || ARRAY['pdf_generated_at']; END IF;
    -- void stamp: write-once; only set together with status = 'void'.
    IF OLD.voided_at IS NOT NULL AND NEW.voided_at IS DISTINCT FROM OLD.voided_at THEN v_changed := v_changed || ARRAY['voided_at']; END IF;
    IF NEW.voided_at IS NOT NULL AND OLD.voided_at IS NULL AND NEW.status <> 'void' THEN
        RAISE EXCEPTION USING
            MESSAGE = format('invoice %s: voided_at may only be set together with status = ''void'' (CI-012)', OLD.invoice_number),
            ERRCODE = 'restrict_violation';
    END IF;

    IF cardinality(v_changed) > 0 THEN
        RAISE EXCEPTION USING
            MESSAGE = format('invoice %s is issued (status %s) and its billed content is immutable (CI-012): attempted change to %s; correct it with void_invoice() + rebill', OLD.invoice_number, OLD.status, array_to_string(v_changed, ', ')),
            ERRCODE = 'restrict_violation';
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS enforce_invoice_immutable ON public.invoices;
CREATE TRIGGER enforce_invoice_immutable BEFORE INSERT OR UPDATE OR DELETE ON public.invoices
    FOR EACH ROW EXECUTE FUNCTION public.enforce_invoice_immutable();

-- ----------------------------------------------------------------------------
-- 3. ENABLE ALWAYS on every v5.4.2-01 guard (+ the three earlier immutability guards)
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
          AND t.tgenabled <> 'A'
          AND (t.tgname IN ('no_hard_delete', 'no_truncate')
               OR t.tgname IN ('enforce_payment_immutable', 'enforce_adhoc_charge_immutable',
                               'enforce_customer_credit_immutable', 'enforce_invoice_application_immutable',
                               'enforce_account_ledger_immutable', 'enforce_invoice_events_immutable',
                               'enforce_invoice_immutable', 'enforce_invoice_line_items_immutable',
                               'enforce_pga_reconciliation_immutable',
                               'enforce_tenant_configuration_history_immutable',
                               'enforce_tenant_configuration_history_no_truncate'))
    LOOP
        EXECUTE format('ALTER TABLE public.%I ENABLE ALWAYS TRIGGER %I', r.relname, r.tgname);
    END LOOP;
END;
$$;
