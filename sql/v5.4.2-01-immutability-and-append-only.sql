-- ============================================================================
-- PATCH v5.4.2-01 — bill immutability, append-only ledger, no hard deletes
--                    (schema-parity-plan Phase 4 Wave 1, Appendix A-4)
-- ============================================================================
-- Authority:   gas-billing-memory/application/schema-parity-plan.md Phase 4
--              Wave 1 — "A-4 first (bill-immutability / append-only
--              enforcement) ... option (b)'s trigger pattern is already
--              proven three times over ... and option (a)'s infrastructure
--              (tally_app + the GRANT layer) exists since -01. A-4 is now
--              mostly generalizing a proven pattern to issued invoices,
--              account_ledger, and posted operational rows. Hardens
--              CI-012/013/014 in one patch set."
--              Appendix A-4 (canonical-invariants.md) names both options:
--              (a) revoke UPDATE/DELETE from the application role and route
--              mutations through SECURITY DEFINER procedures; (b) row-level
--              triggers that raise on UPDATE/DELETE of issued/posted rows.
--              This patch lands (b) as the primary layer (it binds the owner
--              role too, which (a) cannot) and the cheap half of (a) — a
--              REVOKE of the privileges the triggers make useless — as a
--              second fence. The SECURITY DEFINER-procedure half of (a) is
--              NOT landed: the only such procedure that exists is
--              void_invoice(), and routing every lifecycle write through
--              procedures is application architecture this schema-only
--              project has no standing to decide.
--
-- CI entries:  CI-012 Bill Immutability — requires-application-discipline
--              -> structurally-enforced for the header + line items (the
--              invariant's "header row and line-item rows are not edited in
--              place" clause). The "bill PDF/image artifacts" scope item is
--              outside the database (pdf_url is frozen; the object it points
--              at is not ours to guard) — note that in the re-grade.
--              CI-013 Append-Only Financial Ledger — requires-application-
--              discipline -> structurally-enforced for account_ledger and
--              invoice_events (INSERT-only, full stop); partially-
--              structurally-enforced across the rest of the CI's scope
--              (payments, invoice_applications, customer_credits,
--              adhoc_charges), which the schema models with MUTABLE
--              lifecycle columns (applied_amount, remaining_amount, status,
--              reversed_at ...). Those tables get their financial identity
--              frozen and their terminal states sealed; their lifecycle
--              columns stay writable because the shipped design (and
--              void_invoice()) depends on it. adhoc_charges' billed-state
--              carve-out is keyed to a session GUC that ANY caller can set
--              (see drafting decisions) — so for that table the guard is a
--              fence against accident, not against intent. Re-grade should
--              say exactly that rather than over-claim.
--              CI-014 No Hard Deletes — requires-application-discipline ->
--              partially-structurally-enforced: structural for the
--              enumerated operational set (33 tables, listed below) with
--              draft invoices the one stated exception; the CI's "every
--              other operational entity" clause still reaches reference/
--              config tables this patch leaves alone (rate_* family,
--              billing_cycles, read_routes, jurisdictions, ...) — those are
--              date-effective reference data whose retention discipline is
--              A-1's (CI-004), not a hard-delete guard's.
--              CI-017 (reversal lineage) and CI-018 (unbounded chains) are
--              NOT re-graded — the reversal-via-new-row pattern they rely on
--              is exactly what this patch makes the ONLY path.
--              New Appendix A entry (A-23) on the GBM side recording what
--              remains application discipline after this patch.
--
-- Drafting decisions:
--              * "ISSUED" = status NOT IN ('draft','held'). The status
--                COMMENT gives the lifecycle draft -> pending -> sent, with
--                held as a pre-posting review detour; void_invoice() already
--                treats pending as voidable (i.e. posted, corrected only by
--                void + rebill), so pending is on the immutable side of the
--                line. CI-012's own words are "transitions out of draft
--                into a customer-visible state"; pending is the first state
--                the ledger has seen.
--              * COLUMN-SCOPED, NOT ROW-SCOPED, FOR INVOICES. An issued
--                invoice legitimately keeps changing: amount_paid/balance/
--                status as payments apply, dunning_stage and late_fee_* as
--                collections run, delivery_* and sent_at as it ships, and
--                the void_* family when void_invoice() stamps it. What the
--                customer SAW — identity, period, dates, every total,
--                tax_breakdown, the estimated-read flags, lineage pointers,
--                pdf_url — is the frozen set (enumerated in
--                enforce_invoice_immutable). late_fee_assessed/late_fee_
--                amount are NOT frozen: a late fee is assessed after issue
--                by design. due_date IS frozen: the date the customer saw is
--                the date; payment arrangements are their own records
--                (A-21), not an edit to the bill.
--              * VOID IS TERMINAL. Once status = 'void' only notes/metadata
--                (and updated_at) may change. Un-voiding is a rewrite of
--                history; the correction is the rebill.
--              * NO BACKWARD TRANSITIONS. An issued invoice cannot return to
--                draft or held — that is "edit in place" with extra steps.
--              * LINE ITEMS FOLLOW THEIR PARENT. INSERT, UPDATE and DELETE
--                on invoice_line_items are rejected once the parent is
--                issued (INSERT too: adding a line after issue changes the
--                bill as surely as editing one). While the parent is draft/
--                held the line items are working rows and fully editable.
--              * DRAFT INVOICES MAY BE HARD-DELETED — IF NOTHING POSTED
--                HANGS OFF THEM; NOTHING ELSE MAY. A draft carrying a
--                billed adhoc charge (fk_adhoc_invoice is ON DELETE SET
--                NULL — the charge would be stranded as billed-on-nothing)
--                or a locked read is refused too.
--                CI-014 lists invoices without qualification, but a draft
--                has not been posted, is not voidable (void_invoice()
--                rejects draft), and has no soft-delete path of its own —
--                forbidding DELETE would leave a generated-then-abandoned
--                draft with no disposition at all. The line-item and
--                invoice_events guards therefore allow the ON DELETE CASCADE
--                from a draft-invoice delete (detected as "parent row no
--                longer exists", which the FK makes impossible any other
--                way). held is NOT deletable: it carries an operator's
--                hold_reason and is voidable. Flagged as the one exception;
--                if the product later wants drafts retained, the exception
--                is one predicate.
--              * account_ledger AND invoice_events ARE INSERT-ONLY, PERIOD.
--                Nothing in the shipped schema updates either (verified:
--                compute_ledger_running_balance is BEFORE INSERT; void_
--                invoice() only inserts). TRUNCATE is blocked too, as -02
--                did for tenant_configuration_history.
--              * invoice_applications IS WRITE-ONCE-REVERSIBLE. The only
--                permitted UPDATE sets reversed_at/reversed_by/
--                reversed_reason from NULL (one time) and/or edits notes.
--                The application itself (invoice_id, source, amount,
--                applied_at/by) is frozen from insert.
--              * payments: identity frozen once status <> 'pending' (amount,
--                date, customer, method, channel, source, every external
--                reference, check_*, received_by, is_deposit). pending is
--                the intake state for callers that use it (a webhook or
--                lockbox row awaiting confirmation); the column DEFAULT is
--                'posted', so a payment inserted without an explicit status
--                is frozen from its first moment — a posted payment is
--                corrected by reversal + new payment, never by edit. Once
--                out of pending there is no way back in. nsf/reversed/refunded/voided
--                are terminal; reversed_at/nsf_date are write-once.
--                applied_amount/unapplied_amount/deposit_status stay
--                writable (application lifecycle).
--              * adhoc_charges: identity frozen once status <> 'pending'
--                (amount, charge_type, customer, location, meter, service
--                type, taxability, effective_date, charge_number, source,
--                created_by, description). void/waived are terminal. A
--                'billed' charge leaves 'billed' (or changes its billing
--                pointers) only under the app.void_operation carve-out —
--                the v5.2.1 GUC void_invoice() sets, which the locked-read
--                guard on meter_readings already honours — and only to the
--                two states void_invoice() writes. The GUC is a plain
--                session variable: any caller with UPDATE can SET LOCAL it
--                and walk through. That is the existing design's property,
--                not a new one; this patch extends it to a second table
--                rather than inventing a second carve-out, records it as
--                an application contract, and grades CI-013 for
--                adhoc_charges as partial because of it. A real seal needs
--                void_invoice() to be the only holder of UPDATE on the
--                billed columns — the SECURITY DEFINER half of option (a),
--                deliberately not taken here. A charge
--                reverted to 'pending' by a void is editable again: it is
--                no longer on any issued artifact (the voided invoice is
--                preserved), and void_invoice()'s non-auto path parks it
--                in void_pending_rebill precisely so a human can review it.
--              * customer_credits: origin frozen from insert (customer,
--                origin_type, the three source_* pointers, original_amount,
--                issued_date, issued_by). refunded/donated/escheated/voided
--                are terminal. applied/remaining/status/escheat_* stay
--                writable.
--              * THE NO-HARD-DELETE SET is every table that records
--                something that happened or exists in the field (customer,
--                premise, meter, read, bill, money, order, event, audit
--                log, import job). Deliberately NOT in the set: tenant_
--                sequences, import_staging (scratch rows), import_column_
--                mappings / import_mapping_templates, materialized_view_
--                refresh_log, custom_field_definitions, custom_location_
--                types, billing_cycles, read_routes, read_cycle_meters
--                (assignments), wna_zones, franchise_fee_rules,
--                communities, jurisdictions, program_types, pga_monitoring_
--                settings, auto_pay_settings, alerts, bill_messages,
--                ai_sessions / ai_tool_calls / ai_suggestions (ai_audit_log
--                IS protected), and the rate_* family — rate_item_history
--                is moved to rate_item_history_archive by a DELETE in
--                shipped code (tu.sql:90) and its append-only shape is A-1's
--                to decide. pga_monthly_reconciliations and tenant_
--                configuration_history already have their own guards and
--                are left alone.
--              * ONE GENERIC DELETE GUARD, CREATED IN A LOOP. enforce_no_
--                hard_delete() reads TG_TABLE_NAME; a DO block attaches a
--                BEFORE DELETE row trigger and a BEFORE TRUNCATE statement
--                trigger to each table in the set. Idempotent (DROP IF
--                EXISTS first). Cascades from a protected parent hit the
--                child guard and fail — that is the point (CI-014's "a
--                deleted customer record orphans its account ledger").
--              * REVOKE AS A SECOND FENCE. tally_app loses DELETE on every
--                protected table (except invoices/invoice_line_items/
--                invoice_events, where the draft exception needs it) and
--                UPDATE on account_ledger, invoice_events, and the two
--                already-immutable tables. The triggers remain the
--                enforcement: the REVOKE cannot bind the owner and can be
--                undone by a GRANT; the triggers can only be undone by a
--                DROP, which is a visible schema change.
--
-- Review round 1 (Fable): posted->pending->edit two-step on payments
--              closed (no return to pending); direct status='void' without
--              voided_at now refused (the sealing rule made its absence
--              worse than before); primary keys added to every frozen set;
--              adhoc description + billing pointers frozen while billed;
--              draft delete refused with posted dependents; customer_credits
--              source_reference/origin_notes frozen; CI-013 (adhoc) and
--              CI-014 tokens softened to partial; guards on the three
--              INSERT-only/issued tables set ENABLE ALWAYS so replication
--              apply and session_replication_role = replica cannot skip them.
--
-- Review round 2 (Codex, concurrent): the GUC leak — void_invoice() sets
--              app.void_operation with SET LOCAL and never resets it, so
--              every later statement in the SAME transaction walked through
--              the locked-read guard (since v5.2.1) and the new billed-charge
--              guard; Codex reproduced a bypass against an UNRELATED invoice
--              in the same transaction. Both reviewers independently asked
--              for more than a footnote, so void_invoice() is re-issued
--              below (section 5) with the body unchanged except for one
--              set_config('app.void_operation','false',true) before RETURN.
--              Also: payments.status DEFAULTs to 'posted' (tu.sql), so the
--              "pending intake window" exists only for callers that set
--              status = 'pending' explicitly (webhook/lockbox intake) —
--              rationale corrected, application contract added.
--
-- Not in scope (recorded so the re-grade does not over-claim):
--              * meter_readings in-place edits — already governed by
--                enforce_reading_validation_workflow (locked reads); A-1
--                gives it the transaction-time pair.
--              * A CHECK pairing status='void' with voided_at IS NOT NULL
--                (the column COMMENT asserts it; nothing enforces it).
--                Widening; flagged for a later factual-defect set.
--              * Whether a voided invoice's balance/amount_paid should be
--                frozen — void_invoice() does not touch them and no
--                shipped code does; left writable to avoid deciding the
--                payment-transfer design by inertia.
--
-- Idempotent: every CREATE is OR REPLACE / every trigger is DROP IF EXISTS
-- first; REVOKEs are idempotent by nature. Fresh-build safe under
-- search_path = '' (every object schema-qualified; the DO block uses
-- format() with %I against public.).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. CI-014 — generic hard-delete guard + TRUNCATE twin, attached in a loop
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.enforce_no_hard_delete() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    RAISE EXCEPTION USING
        MESSAGE = format('%s rows are never hard-deleted (CI-014): retire the record through its status/voided/closed marker with a reason; the row stays for audit and lineage.', TG_TABLE_NAME),
        ERRCODE = 'restrict_violation';
END;
$$;

COMMENT ON FUNCTION public.enforce_no_hard_delete() IS
    'CI-014 guard (v5.4.2-01). Attached as BEFORE DELETE (row) and BEFORE TRUNCATE (statement) to every operational table in the protected set; raises unconditionally. Fires on FK cascades too, so deleting a protected parent fails at its first protected child — intended. The protected set is the array in the v5.4.2-01 DO block; add a table there, not ad hoc.';

DO $$
DECLARE
    t text;
    protected constant text[] := ARRAY[
        -- money
        'account_ledger', 'payments', 'invoice_applications', 'customer_credits',
        'adhoc_charges', 'escheatment_events', 'payment_methods', 'payment_provider_logs',
        -- bills (invoices / invoice_line_items / invoice_events have their own
        -- guards with the draft-cascade exception — see section 2)
        'dunning_events', 'billing_runs', 'billing_run_meters', 'correction_run_targets',
        'wna_monthly_adjustments', 'wna_clamp_events',
        -- parties and premises
        'tenants', 'users', 'customers', 'customer_contacts', 'customer_interactions',
        'customer_tax_exemptions', 'customer_winter_averages', 'customer_program_enrollments',
        'service_locations',
        -- metering
        'meters', 'meter_deployments', 'meter_readings', 'meter_endpoint_history',
        'meter_photos', 'read_cycle_instances',
        -- operations and audit
        'service_orders', 'anomalies', 'import_jobs', 'ai_audit_log'
    ];
BEGIN
    FOREACH t IN ARRAY protected LOOP
        EXECUTE format('DROP TRIGGER IF EXISTS no_hard_delete ON public.%I', t);
        EXECUTE format(
            'CREATE TRIGGER no_hard_delete BEFORE DELETE ON public.%I FOR EACH ROW EXECUTE FUNCTION public.enforce_no_hard_delete()', t);
        EXECUTE format('DROP TRIGGER IF EXISTS no_truncate ON public.%I', t);
        EXECUTE format(
            'CREATE TRIGGER no_truncate BEFORE TRUNCATE ON public.%I FOR EACH STATEMENT EXECUTE FUNCTION public.enforce_no_hard_delete()', t);
        EXECUTE format('REVOKE DELETE ON public.%I FROM tally_app', t);
    END LOOP;
END;
$$;

-- ----------------------------------------------------------------------------
-- 2. CI-012 — invoices, invoice_line_items, invoice_events
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.is_invoice_issued(p_status text) RETURNS boolean
    LANGUAGE sql IMMUTABLE
    AS $$ SELECT p_status IS NOT NULL AND p_status NOT IN ('draft', 'held') $$;

COMMENT ON FUNCTION public.is_invoice_issued(text) IS
    'The single definition of "issued" used by every CI-012 guard (v5.4.2-01): any status other than draft or held. pending counts as issued — it is post-posting and void_invoice() already treats it as voidable, not editable.';

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

COMMENT ON FUNCTION public.enforce_invoice_immutable() IS
    'CI-012 guard for invoices (v5.4.2-01). DELETE: only status = draft may be hard-deleted. UPDATE once issued (is_invoice_issued): the billed content — identity, lineage pointers, period, dates (due_date included), every total, tax_breakdown, estimated-read/anomaly flags, created_at — is frozen; pdf_url/pdf_generated_at/voided_at are write-once; no transition back to draft/held; status = void is terminal (only notes/metadata may change). Lifecycle columns (status forward, amount_paid, balance, dunning_stage, late_fee_*, write_off_*, delivery_*, sent_at, hold_*, void_* when voiding, notes, metadata) stay writable — an issued bill keeps living in collections; only what the customer saw is sealed.';

DROP TRIGGER IF EXISTS enforce_invoice_immutable ON public.invoices;
CREATE TRIGGER enforce_invoice_immutable BEFORE UPDATE OR DELETE ON public.invoices
    FOR EACH ROW EXECUTE FUNCTION public.enforce_invoice_immutable();
DROP TRIGGER IF EXISTS no_truncate ON public.invoices;
CREATE TRIGGER no_truncate BEFORE TRUNCATE ON public.invoices
    FOR EACH STATEMENT EXECUTE FUNCTION public.enforce_no_hard_delete();

-- Line items: follow the parent. "Parent row no longer exists" is only
-- reachable from the ON DELETE CASCADE of a draft-invoice delete (the FK
-- forbids it otherwise) and is allowed through.
CREATE OR REPLACE FUNCTION public.enforce_invoice_line_items_immutable() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_invoice_id uuid := CASE WHEN TG_OP = 'INSERT' THEN NEW.invoice_id ELSE OLD.invoice_id END;
    v_status     text;
    v_number     text;
BEGIN
    SELECT i.status, i.invoice_number INTO v_status, v_number
    FROM public.invoices i WHERE i.id = v_invoice_id;

    IF FOUND AND public.is_invoice_issued(v_status) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('invoice %s is issued (status %s): its line items are immutable (CI-012) — %s rejected; correct it with void_invoice() + rebill', v_number, v_status, TG_OP),
            ERRCODE = 'restrict_violation';
    END IF;

    -- Re-parenting a line onto an issued invoice is an edit of that invoice.
    IF TG_OP = 'UPDATE' AND NEW.invoice_id IS DISTINCT FROM OLD.invoice_id THEN
        SELECT i.status, i.invoice_number INTO v_status, v_number
        FROM public.invoices i WHERE i.id = NEW.invoice_id;
        IF FOUND AND public.is_invoice_issued(v_status) THEN
            RAISE EXCEPTION USING
                MESSAGE = format('invoice %s is issued (status %s): line items cannot be moved onto it (CI-012)', v_number, v_status),
                ERRCODE = 'restrict_violation';
        END IF;
    END IF;

    RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END;
$$;

COMMENT ON FUNCTION public.enforce_invoice_line_items_immutable() IS
    'CI-012 guard for invoice_line_items (v5.4.2-01): INSERT, UPDATE and DELETE are all rejected while the parent invoice is issued (is_invoice_issued); draft/held parents leave the lines fully editable. A missing parent (only reachable via the cascade of a draft-invoice delete) is allowed through.';

DROP TRIGGER IF EXISTS enforce_invoice_line_items_immutable ON public.invoice_line_items;
CREATE TRIGGER enforce_invoice_line_items_immutable BEFORE INSERT OR UPDATE OR DELETE ON public.invoice_line_items
    FOR EACH ROW EXECUTE FUNCTION public.enforce_invoice_line_items_immutable();
DROP TRIGGER IF EXISTS no_truncate ON public.invoice_line_items;
CREATE TRIGGER no_truncate BEFORE TRUNCATE ON public.invoice_line_items
    FOR EACH STATEMENT EXECUTE FUNCTION public.enforce_no_hard_delete();

-- invoice_events: append-only. Same draft-cascade allowance on DELETE.
CREATE OR REPLACE FUNCTION public.enforce_invoice_events_immutable() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF TG_OP = 'DELETE' AND NOT EXISTS (SELECT 1 FROM public.invoices i WHERE i.id = OLD.invoice_id) THEN
        RETURN OLD;   -- cascade from a draft-invoice delete
    END IF;
    RAISE EXCEPTION USING
        MESSAGE = 'invoice_events rows are append-only (CI-012/CI-013): an event that happened is never edited or deleted; record a correcting event.',
        ERRCODE = 'restrict_violation';
END;
$$;

DROP TRIGGER IF EXISTS enforce_invoice_events_immutable ON public.invoice_events;
CREATE TRIGGER enforce_invoice_events_immutable BEFORE UPDATE OR DELETE ON public.invoice_events
    FOR EACH ROW EXECUTE FUNCTION public.enforce_invoice_events_immutable();
DROP TRIGGER IF EXISTS no_truncate ON public.invoice_events;
CREATE TRIGGER no_truncate BEFORE TRUNCATE ON public.invoice_events
    FOR EACH STATEMENT EXECUTE FUNCTION public.enforce_no_hard_delete();

-- ----------------------------------------------------------------------------
-- 3. CI-013 — account_ledger (INSERT-only), invoice_applications,
--             payments, adhoc_charges, customer_credits
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.enforce_account_ledger_immutable() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    RAISE EXCEPTION USING
        MESSAGE = 'account_ledger rows are append-only (CI-013): a reversal is a new row linked via reverses_ledger_entry_id, never an edit or delete of the original.',
        ERRCODE = 'restrict_violation';
END;
$$;

DROP TRIGGER IF EXISTS enforce_account_ledger_immutable ON public.account_ledger;
CREATE TRIGGER enforce_account_ledger_immutable BEFORE UPDATE ON public.account_ledger
    FOR EACH ROW EXECUTE FUNCTION public.enforce_account_ledger_immutable();
-- (DELETE and TRUNCATE are covered by the section-1 loop.)

-- invoice_applications: write-once reversal, otherwise frozen.
CREATE OR REPLACE FUNCTION public.enforce_invoice_application_immutable() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF (to_jsonb(NEW) - 'reversed_at' - 'reversed_by' - 'reversed_reason' - 'notes')
       IS DISTINCT FROM
       (to_jsonb(OLD) - 'reversed_at' - 'reversed_by' - 'reversed_reason' - 'notes') THEN
        RAISE EXCEPTION USING
            MESSAGE = format('invoice_applications %s is immutable (CI-013): only the reversal stamp (once) and notes may change; re-apply with a new row', OLD.id),
            ERRCODE = 'restrict_violation';
    END IF;
    IF OLD.reversed_at IS NOT NULL
       AND (NEW.reversed_at IS DISTINCT FROM OLD.reversed_at
            OR NEW.reversed_by IS DISTINCT FROM OLD.reversed_by
            OR NEW.reversed_reason IS DISTINCT FROM OLD.reversed_reason) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('invoice_applications %s is already reversed (CI-013): the reversal stamp is write-once', OLD.id),
            ERRCODE = 'restrict_violation';
    END IF;
    IF NEW.reversed_at IS NULL AND (NEW.reversed_by IS NOT NULL OR NEW.reversed_reason IS NOT NULL) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('invoice_applications %s: reversed_by/reversed_reason require reversed_at', OLD.id),
            ERRCODE = 'restrict_violation';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS enforce_invoice_application_immutable ON public.invoice_applications;
CREATE TRIGGER enforce_invoice_application_immutable BEFORE UPDATE ON public.invoice_applications
    FOR EACH ROW EXECUTE FUNCTION public.enforce_invoice_application_immutable();

-- payments
CREATE OR REPLACE FUNCTION public.enforce_payment_immutable() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_changed text[] := '{}';
    v_terminal constant text[] := ARRAY['nsf', 'reversed', 'refunded', 'voided'];
BEGIN
    IF OLD.status = ANY (v_terminal) AND NEW.status IS DISTINCT FROM OLD.status THEN
        RAISE EXCEPTION USING
            MESSAGE = format('payment %s is %s — a terminal state (CI-013): it cannot transition to %s; post a new payment', OLD.payment_number, OLD.status, NEW.status),
            ERRCODE = 'restrict_violation';
    END IF;
    IF OLD.status <> 'pending' AND NEW.status = 'pending' THEN
        RAISE EXCEPTION USING
            MESSAGE = format('payment %s cannot return from %s to pending (CI-013): intake is not re-opened; reverse it and post a new payment', OLD.payment_number, OLD.status),
            ERRCODE = 'restrict_violation';
    END IF;
    IF OLD.reversed_at IS NOT NULL AND NEW.reversed_at IS DISTINCT FROM OLD.reversed_at THEN v_changed := v_changed || ARRAY['reversed_at']; END IF;
    IF OLD.nsf_date    IS NOT NULL AND NEW.nsf_date    IS DISTINCT FROM OLD.nsf_date    THEN v_changed := v_changed || ARRAY['nsf_date']; END IF;

    IF OLD.status <> 'pending' THEN
        IF NEW.id                          IS DISTINCT FROM OLD.id                          THEN v_changed := v_changed || ARRAY['id']; END IF;
        IF NEW.tenant_id                   IS DISTINCT FROM OLD.tenant_id                   THEN v_changed := v_changed || ARRAY['tenant_id']; END IF;
        IF NEW.payment_number              IS DISTINCT FROM OLD.payment_number              THEN v_changed := v_changed || ARRAY['payment_number']; END IF;
        IF NEW.customer_id                 IS DISTINCT FROM OLD.customer_id                 THEN v_changed := v_changed || ARRAY['customer_id']; END IF;
        IF NEW.payment_date                IS DISTINCT FROM OLD.payment_date                THEN v_changed := v_changed || ARRAY['payment_date']; END IF;
        IF NEW.amount                      IS DISTINCT FROM OLD.amount                      THEN v_changed := v_changed || ARRAY['amount']; END IF;
        IF NEW.payment_method              IS DISTINCT FROM OLD.payment_method              THEN v_changed := v_changed || ARRAY['payment_method']; END IF;
        IF NEW.payment_method_id           IS DISTINCT FROM OLD.payment_method_id           THEN v_changed := v_changed || ARRAY['payment_method_id']; END IF;
        IF NEW.channel                     IS DISTINCT FROM OLD.channel                     THEN v_changed := v_changed || ARRAY['channel']; END IF;
        IF NEW.source_system               IS DISTINCT FROM OLD.source_system               THEN v_changed := v_changed || ARRAY['source_system']; END IF;
        IF NEW.reference_number            IS DISTINCT FROM OLD.reference_number            THEN v_changed := v_changed || ARRAY['reference_number']; END IF;
        IF NEW.provider_transaction_id     IS DISTINCT FROM OLD.provider_transaction_id     THEN v_changed := v_changed || ARRAY['provider_transaction_id']; END IF;
        IF NEW.provider_authorization_code IS DISTINCT FROM OLD.provider_authorization_code THEN v_changed := v_changed || ARRAY['provider_authorization_code']; END IF;
        IF NEW.check_number                IS DISTINCT FROM OLD.check_number                THEN v_changed := v_changed || ARRAY['check_number']; END IF;
        IF NEW.check_date                  IS DISTINCT FROM OLD.check_date                  THEN v_changed := v_changed || ARRAY['check_date']; END IF;
        IF NEW.check_bank_name             IS DISTINCT FROM OLD.check_bank_name             THEN v_changed := v_changed || ARRAY['check_bank_name']; END IF;
        IF NEW.is_deposit                  IS DISTINCT FROM OLD.is_deposit                  THEN v_changed := v_changed || ARRAY['is_deposit']; END IF;
        IF NEW.received_by                 IS DISTINCT FROM OLD.received_by                 THEN v_changed := v_changed || ARRAY['received_by']; END IF;
        IF NEW.nsf_original_payment_id     IS DISTINCT FROM OLD.nsf_original_payment_id     THEN v_changed := v_changed || ARRAY['nsf_original_payment_id']; END IF;
        IF NEW.refunds_payment_id          IS DISTINCT FROM OLD.refunds_payment_id          THEN v_changed := v_changed || ARRAY['refunds_payment_id']; END IF;
        IF NEW.created_at                  IS DISTINCT FROM OLD.created_at                  THEN v_changed := v_changed || ARRAY['created_at']; END IF;
    END IF;

    IF cardinality(v_changed) > 0 THEN
        RAISE EXCEPTION USING
            MESSAGE = format('payment %s is posted (status %s) and its identity is immutable (CI-013): attempted change to %s; reverse it and post a new payment', OLD.payment_number, OLD.status, array_to_string(v_changed, ', ')),
            ERRCODE = 'restrict_violation';
    END IF;
    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.enforce_payment_immutable() IS
    'CI-013 guard for payments (v5.4.2-01). Once status <> pending the payment''s identity (customer, date, amount, method, channel, source, every external reference, check_*, is_deposit, received_by, lineage FKs, created_at) is frozen; nsf/reversed/refunded/voided are terminal; reversed_at/nsf_date are write-once. applied_amount/unapplied_amount/deposit_status/status-forward/notes/metadata stay writable: the shipped design tracks application lifecycle on the payment row, and this patch does not redesign it (A-21 territory).';

DROP TRIGGER IF EXISTS enforce_payment_immutable ON public.payments;
CREATE TRIGGER enforce_payment_immutable BEFORE UPDATE ON public.payments
    FOR EACH ROW EXECUTE FUNCTION public.enforce_payment_immutable();

-- adhoc_charges
CREATE OR REPLACE FUNCTION public.enforce_adhoc_charge_immutable() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_changed text[] := '{}';
    v_void_op boolean := coalesce(current_setting('app.void_operation', true) = 'true', false);
BEGIN
    IF OLD.status IN ('void', 'waived') AND NEW.status IS DISTINCT FROM OLD.status THEN
        RAISE EXCEPTION USING
            MESSAGE = format('adhoc charge %s is %s — a terminal state (CI-013): create a new charge instead', OLD.charge_number, OLD.status),
            ERRCODE = 'restrict_violation';
    END IF;

    -- A billed charge is part of an issued bill; it leaves 'billed' only
    -- through void_invoice(), and only to the two states that function writes.
    IF OLD.status = 'billed' AND NEW.status IS DISTINCT FROM OLD.status
       AND NOT (v_void_op AND NEW.status IN ('pending', 'void_pending_rebill')) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('adhoc charge %s is billed on invoice %s (CI-012/CI-013): it is undone only by voiding that invoice (void_invoice()), not by changing the charge', OLD.charge_number, OLD.billed_on_invoice_id),
            ERRCODE = 'restrict_violation';
    END IF;

    -- While billed, the billing pointers are part of the issued bill; only
    -- void_invoice() (which clears them) may touch them.
    IF OLD.status = 'billed' AND NOT v_void_op THEN
        IF NEW.billed_on_invoice_id    IS DISTINCT FROM OLD.billed_on_invoice_id    THEN v_changed := v_changed || ARRAY['billed_on_invoice_id']; END IF;
        IF NEW.billed_on_line_item_id  IS DISTINCT FROM OLD.billed_on_line_item_id  THEN v_changed := v_changed || ARRAY['billed_on_line_item_id']; END IF;
        IF NEW.billed_at               IS DISTINCT FROM OLD.billed_at               THEN v_changed := v_changed || ARRAY['billed_at']; END IF;
        IF NEW.billed_by_billing_run_id IS DISTINCT FROM OLD.billed_by_billing_run_id THEN v_changed := v_changed || ARRAY['billed_by_billing_run_id']; END IF;
    END IF;

    IF OLD.status <> 'pending' THEN
        IF NEW.id             IS DISTINCT FROM OLD.id             THEN v_changed := v_changed || ARRAY['id']; END IF;
        IF NEW.tenant_id      IS DISTINCT FROM OLD.tenant_id      THEN v_changed := v_changed || ARRAY['tenant_id']; END IF;
        IF NEW.description    IS DISTINCT FROM OLD.description    THEN v_changed := v_changed || ARRAY['description']; END IF;
        IF NEW.charge_number  IS DISTINCT FROM OLD.charge_number  THEN v_changed := v_changed || ARRAY['charge_number']; END IF;
        IF NEW.customer_id    IS DISTINCT FROM OLD.customer_id    THEN v_changed := v_changed || ARRAY['customer_id']; END IF;
        IF NEW.location_id    IS DISTINCT FROM OLD.location_id    THEN v_changed := v_changed || ARRAY['location_id']; END IF;
        IF NEW.meter_id       IS DISTINCT FROM OLD.meter_id       THEN v_changed := v_changed || ARRAY['meter_id']; END IF;
        IF NEW.charge_type    IS DISTINCT FROM OLD.charge_type    THEN v_changed := v_changed || ARRAY['charge_type']; END IF;
        IF NEW.amount         IS DISTINCT FROM OLD.amount         THEN v_changed := v_changed || ARRAY['amount']; END IF;
        IF NEW.is_taxable     IS DISTINCT FROM OLD.is_taxable     THEN v_changed := v_changed || ARRAY['is_taxable']; END IF;
        IF NEW.service_type   IS DISTINCT FROM OLD.service_type   THEN v_changed := v_changed || ARRAY['service_type']; END IF;
        IF NEW.effective_date IS DISTINCT FROM OLD.effective_date THEN v_changed := v_changed || ARRAY['effective_date']; END IF;
        IF NEW.source         IS DISTINCT FROM OLD.source         THEN v_changed := v_changed || ARRAY['source']; END IF;
        IF NEW.created_by     IS DISTINCT FROM OLD.created_by     THEN v_changed := v_changed || ARRAY['created_by']; END IF;
        IF NEW.created_at     IS DISTINCT FROM OLD.created_at     THEN v_changed := v_changed || ARRAY['created_at']; END IF;
    END IF;

    IF cardinality(v_changed) > 0 THEN
        RAISE EXCEPTION USING
            MESSAGE = format('adhoc charge %s is %s and its identity is immutable (CI-013): attempted change to %s', OLD.charge_number, OLD.status, array_to_string(v_changed, ', ')),
            ERRCODE = 'restrict_violation';
    END IF;
    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.enforce_adhoc_charge_immutable() IS
    'CI-013 guard for adhoc_charges (v5.4.2-01). Identity (customer, premise, meter, type, amount, taxability, service_type, effective_date, source, created_by) frozen once status <> pending; void/waived terminal; billed -> {pending, void_pending_rebill}, and any change to the billed_* pointers, only under the app.void_operation carve-out (set by void_invoice(); a plain session GUC any caller can also set — a fence against accident, not intent; see APPLICATION-CONTRACTS). A charge reverted to pending by a void is editable again — it is on no issued artifact.';

DROP TRIGGER IF EXISTS enforce_adhoc_charge_immutable ON public.adhoc_charges;
CREATE TRIGGER enforce_adhoc_charge_immutable BEFORE UPDATE ON public.adhoc_charges
    FOR EACH ROW EXECUTE FUNCTION public.enforce_adhoc_charge_immutable();

-- customer_credits
CREATE OR REPLACE FUNCTION public.enforce_customer_credit_immutable() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_changed text[] := '{}';
BEGIN
    IF OLD.status IN ('refunded', 'donated', 'escheated', 'voided') AND NEW.status IS DISTINCT FROM OLD.status THEN
        RAISE EXCEPTION USING
            MESSAGE = format('customer credit %s is %s — a terminal state (CI-013): issue a new credit instead', OLD.id, OLD.status),
            ERRCODE = 'restrict_violation';
    END IF;
    IF NEW.id                      IS DISTINCT FROM OLD.id                      THEN v_changed := v_changed || ARRAY['id']; END IF;
    IF NEW.tenant_id               IS DISTINCT FROM OLD.tenant_id               THEN v_changed := v_changed || ARRAY['tenant_id']; END IF;
    IF NEW.customer_id             IS DISTINCT FROM OLD.customer_id             THEN v_changed := v_changed || ARRAY['customer_id']; END IF;
    IF NEW.source_reference        IS DISTINCT FROM OLD.source_reference        THEN v_changed := v_changed || ARRAY['source_reference']; END IF;
    IF NEW.origin_notes            IS DISTINCT FROM OLD.origin_notes            THEN v_changed := v_changed || ARRAY['origin_notes']; END IF;
    IF NEW.origin_type             IS DISTINCT FROM OLD.origin_type             THEN v_changed := v_changed || ARRAY['origin_type']; END IF;
    IF NEW.source_payment_id       IS DISTINCT FROM OLD.source_payment_id       THEN v_changed := v_changed || ARRAY['source_payment_id']; END IF;
    IF NEW.source_adhoc_charge_id  IS DISTINCT FROM OLD.source_adhoc_charge_id  THEN v_changed := v_changed || ARRAY['source_adhoc_charge_id']; END IF;
    IF NEW.source_invoice_id       IS DISTINCT FROM OLD.source_invoice_id       THEN v_changed := v_changed || ARRAY['source_invoice_id']; END IF;
    IF NEW.original_amount         IS DISTINCT FROM OLD.original_amount         THEN v_changed := v_changed || ARRAY['original_amount']; END IF;
    IF NEW.issued_date             IS DISTINCT FROM OLD.issued_date             THEN v_changed := v_changed || ARRAY['issued_date']; END IF;
    IF NEW.issued_by               IS DISTINCT FROM OLD.issued_by               THEN v_changed := v_changed || ARRAY['issued_by']; END IF;
    IF NEW.created_at              IS DISTINCT FROM OLD.created_at              THEN v_changed := v_changed || ARRAY['created_at']; END IF;
    IF OLD.escheated_at IS NOT NULL AND NEW.escheated_at IS DISTINCT FROM OLD.escheated_at THEN v_changed := v_changed || ARRAY['escheated_at']; END IF;

    IF cardinality(v_changed) > 0 THEN
        RAISE EXCEPTION USING
            MESSAGE = format('customer credit %s origin is immutable (CI-013): attempted change to %s; void it and issue a new credit', OLD.id, array_to_string(v_changed, ', ')),
            ERRCODE = 'restrict_violation';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS enforce_customer_credit_immutable ON public.customer_credits;
CREATE TRIGGER enforce_customer_credit_immutable BEFORE UPDATE ON public.customer_credits
    FOR EACH ROW EXECUTE FUNCTION public.enforce_customer_credit_immutable();

-- ----------------------------------------------------------------------------
-- 4. Option (a), the cheap half: privileges the triggers make useless
-- ----------------------------------------------------------------------------
REVOKE UPDATE ON public.account_ledger               FROM tally_app;
REVOKE UPDATE ON public.invoice_events               FROM tally_app;
REVOKE UPDATE, DELETE ON public.pga_monthly_reconciliations  FROM tally_app;
REVOKE UPDATE, DELETE ON public.tenant_configuration_history FROM tally_app;

-- Guards on the three tables whose rows are the audit record itself fire
-- even under session_replication_role = replica / logical-replication apply.
ALTER TABLE public.account_ledger ENABLE ALWAYS TRIGGER enforce_account_ledger_immutable;
ALTER TABLE public.account_ledger ENABLE ALWAYS TRIGGER no_hard_delete;
ALTER TABLE public.account_ledger ENABLE ALWAYS TRIGGER no_truncate;
ALTER TABLE public.invoice_events ENABLE ALWAYS TRIGGER enforce_invoice_events_immutable;
ALTER TABLE public.invoice_events ENABLE ALWAYS TRIGGER no_truncate;
ALTER TABLE public.invoices ENABLE ALWAYS TRIGGER enforce_invoice_immutable;
ALTER TABLE public.invoices ENABLE ALWAYS TRIGGER no_truncate;
ALTER TABLE public.invoice_line_items ENABLE ALWAYS TRIGGER enforce_invoice_line_items_immutable;
ALTER TABLE public.invoice_line_items ENABLE ALWAYS TRIGGER no_truncate;

COMMENT ON TABLE public.account_ledger IS
    'Append-only financial ledger (CI-013; structurally enforced since v5.4.2-01: BEFORE UPDATE/DELETE/TRUNCATE triggers raise; tally_app holds SELECT/INSERT only). Reversals are new rows linked through reverses_ledger_entry_id. running_balance is computed on INSERT by compute_ledger_running_balance().';

-- ----------------------------------------------------------------------------
-- 5. void_invoice(): hand the app.void_operation carve-out back on exit.
--    Body identical to the v5.4.1-01 issue except for the set_config()
--    immediately before RETURN (review consensus, see header).
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.void_invoice(p_invoice_id uuid, p_voided_by uuid DEFAULT NULL::uuid, p_void_reason_code text DEFAULT NULL::text, p_void_reason_notes text DEFAULT NULL::text, p_rebill_expected boolean DEFAULT true) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
    v_invoice                    invoices%ROWTYPE;
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
    -- Step 3.7 (NEW in v5.4.1-01): Best-effort lookup of the original charge
    -- ledger entry this void reverses (CI-017 reversal lineage). NULL when
    -- no such row exists — no billing-run/charge-posting code exists
    -- anywhere in this schema-only project to have posted it yet.
    -- -------------------------------------------------------------------------
    SELECT id INTO v_original_ledger_entry_id
    FROM account_ledger
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
