-- ============================================================================
-- PATCH v5.4.2-04 — A-3: invoice calculation snapshots, Option B
--                    (schema-parity-plan Phase 4 Wave 1, Appendix A-3;
--                    CI-015 / CI-005 / CI-003 / CI-012)
-- ============================================================================
-- Authority:   gas-billing-memory/application/bi-temporal-decision.md §2.3
--              (Option B "linked snapshot table", the locked decision per §5)
--              and §2 "What the Snapshot Solves"; canonical-invariants.md
--              CI-015 (the input list is the statement's list, verbatim);
--              Appendix A-3 ("the snapshot can cite *_versions row ids and
--              the run's (valid, recorded) pair as provenance"); A-1's
--              coordinate contract (AC-15) and A-4's issuance definition
--              (is_invoice_issued, v5.4.2-01).
--
-- What lands:
--
--   1. invoice_calculation_snapshots — one row per invoice (UNIQUE), bound
--      to the invoice's tenant by composite FK (invoices gains
--      UNIQUE (id, tenant_id) for it). The row carries the run's temporal
--      coordinate pair (valid_at, recorded_at) — the ONE pair AC-15 says a
--      run resolves once — a snapshot_schema_version, a formula_version,
--      and eight sections, one per CI-015 input group: rate_inputs,
--      gas_factors, wna_inputs, tax_inputs, read_inputs, customer_inputs,
--      period_inputs (objects) and line_items (array). content_hash is a
--      GENERATED sha256 over the sections + versions + coordinate: INV-099's
--      content-addressable framing at zero cost, and not caller-writable.
--
--   2. Schema versioning is enforced, not labelled: validate_calculation_
--      snapshot() knows the required key set of every schema version it
--      accepts (today: 'v1') and raises on an unknown version or a missing
--      key. A new snapshot shape is a patch that teaches the validator, not
--      a string a caller invents. Cross-checks against the invoice at
--      insert: period_inputs.period_start/period_end equal the invoice's;
--      line_items cites exactly the invoice's invoice_line_items rows (same
--      id set, same amounts) — the snapshot is written AFTER the lines.
--
--   3. Completeness at issuance (CI-015 "every issued invoice"): a
--      DEFERRABLE INITIALLY DEFERRED constraint trigger on invoices requires
--      a snapshot to exist — and to still match the line set — at commit of
--      any transaction that moves an invoice into an issued status
--      (is_invoice_issued: anything but draft/held). Order within the
--      transaction: invoice (draft) → lines → snapshot → status flip; the
--      validator refuses a snapshot for a parent already issued, so the
--      flip is last, and an invoice cannot be INSERTed directly in an
--      issued status (A-4 already forbids lines on one). Draft and held
--      invoices may be recalculated freely: the snapshot is deleted and
--      re-inserted, never edited. Voiding a draft/held invoice is a
--      discard, not an issuance, and is not gated.
--
--   4. Immutability: UPDATE is never allowed on a snapshot (there is no
--      legitimate in-place edit of a frozen input set); DELETE only while the
--      parent invoice is draft/held; INSERT only while the parent is
--      draft/held (a snapshot written after issuance is a reconstruction,
--      not a record); TRUNCATE rejected; UPDATE revoked from tally_app.
--      captured_at is forced to now(); recorded_at may not lie in the
--      future.
--
--   5. invoice_snapshot_references — the provenance link to A-1: each row
--      names one bi-temporal row (source_table ∈ the seven A-1 tables,
--      source_row_id) the calculation read. A BEFORE INSERT guard verifies
--      the cited row exists in that table, in the snapshot's tenant, and
--      was OPEN at the snapshot's recorded_at (recorded_at <= coordinate <
--      recorded_until) — a citation of a row the run could not have seen
--      is rejected. Same immutability rule as the snapshot. Optional per
--      snapshot (a credit memo reads no reference data).
--
--   6. Both tables: RLS + FORCE with the standard tenant_isolation policy;
--      every guard ENABLE ALWAYS (D-2026-08-20-27) — note that FK cascade
--      actions are internal triggers and do NOT run under
--      session_replication_role = replica, so a replica-mode delete of a
--      DRAFT invoice leaves its snapshot orphaned (no issued invoice can
--      be deleted in any mode; Fable C3, LOW, accepted); no_truncate; the
--      snapshot tables are NOT in the generic CI-014 no_hard_delete set
--      because the draft-phase delete is legitimate — their own guard
--      carries the rule (the invoice_line_items precedent, v5.4.2-01).
--
-- Deferred with stated triggers (not in this patch): a replay function
-- (nothing to replay with — no calculation code exists; CI-015 names the
-- formula_version the replay will need, and that is what is stored);
-- per-section value-domain validation beyond key presence (waits for the
-- calculation code that defines the values, R-16's trigger); valid-time
-- validation of provenance citations (bracket columns differ per table;
-- the transaction-time check is the one that proves visibility).
--
-- Preconditions: none are self-verifying refusals. Invoices issued BEFORE
-- this patch have no snapshot and can never get one (INSERT after issuance
-- is rejected by design); the patch reports their count with a NOTICE. On a
-- fresh deploy the count is zero.
--
-- Drafting decisions (durable copies: application/DECISION-LOG.md):
--   * One snapshot per invoice, for every invoice type. CI-015 says "every
--     issued invoice"; a consolidated parent, a duplicate or a credit memo
--     still had inputs (its children, its source invoice, its reason) and
--     the validator accepts empty sections for the groups that do not
--     apply (an object with the required keys whose values are null/empty
--     arrays). Carving out types would have made "issued without a
--     snapshot" a legal state again. Flagged for Ryan if it proves heavy.
--   * The coordinate pair lives on the snapshot, not on billing_runs: an
--     off-run invoice (billing_run_id NULL) still has a coordinate, and
--     the pair is what CI-003 says must be consistent across the
--     computation — the snapshot is the record of which pair was used.
--     billing_run_id is copied from the invoice for the join and checked
--     equal at insert.
--   * Sections are typed JSONB with a versioned key contract rather than
--     columns: CI-015's input list spans eight domains whose shapes will
--     change with the calculation code; Option B's whole point is that the
--     version makes drift explicit. Key presence is the structural floor;
--     values are the calculation code's contract (deferred, above).
--   * line_items is cross-checked against invoice_line_items (ids + amounts)
--     at insert AND at issuance: the two must agree or the bill is not
--     self-replayable. Storing the lines twice is deliberate — CI-016 keeps
--     them on the row for the dollar calculation, CI-015 keeps them in the
--     snapshot so replay reads one document.
--   * A snapshot cannot be inserted for an already-issued invoice. The
--     deferred completeness check would have rejected the issuance, so the
--     only way to reach that state is a pre-patch invoice; a snapshot
--     written later is a reconstruction from today's reference layer,
--     which is exactly what CI-015 forbids passing off as the original.
--   * content_hash is GENERATED ALWAYS (sha256 of the canonical jsonb text
--     of the sections + versions + coordinate). jsonb's text form is
--     canonical (keys sorted, whitespace normalised), so equal inputs hash
--     equal. It is not a signature — the database is trusted — but it
--     gives the hash INV-099 wants and nobody can write a wrong one.
--   * Provenance citations are validated for transaction-time visibility
--     only: the run passed (valid_at, recorded_at); a cited row not open at
--     recorded_at could not have been read at that coordinate. Valid-time
--     containment is not checked (bracket columns differ; a cited row can
--     legitimately be read for a date outside its bracket — e.g. R-9's
--     fallback to the latest closed version).
--   * The snapshot FK cascades on invoice delete (and references on
--     snapshot delete). A-1 stripped cascades because a header delete
--     destroyed history; here the only deletable parent is a draft (A-4),
--     whose snapshot is deletable anyway — without the cascade a legitimate
--     draft delete was blocked (found by the author's second pass).
--   * Functions are pinned to search_path = public, pg_temp (the
--     void_invoice / A-1 precedent), with every reference still qualified:
--     under '' the first RLS policy evaluation inside a guard calls the
--     v5.2.1 helpers get_user_tenant_id()/is_platform_admin(), whose
--     bodies name `users` unqualified — tally_app could not write a
--     snapshot at all (Fable CRITICAL-1). The durable fix — qualify and
--     pin those helpers — is A-23's, not this patch's.
--   * Concurrency: the snapshot/reference guards read the parent invoice
--     FOR SHARE (they wait behind an in-flight status flip and then see the
--     committed status) and the deferred check locks the lines FOR SHARE
--     (A-4's line guard does not lock the invoice), so "issue" vs
--     "delete/replace the snapshot", "add a citation" or "edit a line" in
--     two sessions serialise and the loser is rejected (Fable CRITICAL-2 —
--     both committed before). The deferred check does NOT lock the snapshot
--     row: that deadlocked against a waiting delete and needs a privilege
--     tally_app lacks.
--   * Snapshot line amounts must be JSON numbers and are compared as
--     unrounded numerics against invoice_line_items.amount (Fable MEDIUM-1:
--     20.004 matched 20.00 after a numeric(12,2) cast — replay would have
--     read a document that disagreed with the billed line).
--   * No app.* GUC carve-out anywhere (the A-4 lesson, kept by A-1).
--
-- Verification contract: this file applies standalone under
--   SET search_path = ''; SET check_function_bodies = on;
-- (D-2026-08-20-24). Every relation and function reference is qualified.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 0. Report (never refuse): issued invoices that predate the snapshot store
-- ----------------------------------------------------------------------------
DO $$
DECLARE
    v_count bigint;
BEGIN
    IF to_regclass('public.invoice_calculation_snapshots') IS NULL THEN
        SELECT count(*) INTO v_count
        FROM public.invoices i
        WHERE public.is_invoice_issued(i.status);
        IF v_count > 0 THEN
            RAISE NOTICE 'v5.4.2-04: % invoice(s) were issued before the snapshot store existed; they have no calculation snapshot and cannot be given one (CI-015 applies from this patch forward)', v_count;
        END IF;
    END IF;
END;
$$;

-- ----------------------------------------------------------------------------
-- 1. invoices: tenant-bound identity for composite FKs (A-1 precedent)
-- ----------------------------------------------------------------------------
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'invoices_id_tenant_id_key' AND conrelid = 'public.invoices'::regclass) THEN
        ALTER TABLE public.invoices ADD CONSTRAINT invoices_id_tenant_id_key UNIQUE (id, tenant_id);
    END IF;
END;
$$;

-- ----------------------------------------------------------------------------
-- 2. invoice_calculation_snapshots
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.invoice_calculation_snapshots (
    id                      uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id               uuid NOT NULL,
    invoice_id              uuid NOT NULL,
    billing_run_id          uuid,
    valid_at                date NOT NULL,
    recorded_at             timestamp with time zone NOT NULL,
    snapshot_schema_version text NOT NULL,
    formula_version         text NOT NULL,
    rate_inputs             jsonb NOT NULL,
    gas_factors             jsonb NOT NULL,
    wna_inputs              jsonb NOT NULL,
    tax_inputs              jsonb NOT NULL,
    read_inputs             jsonb NOT NULL,
    customer_inputs         jsonb NOT NULL,
    period_inputs           jsonb NOT NULL,
    line_items              jsonb NOT NULL,
    content_hash            text GENERATED ALWAYS AS (
        encode(public.digest(
            snapshot_schema_version || '|' || formula_version || '|' || (valid_at - DATE '1970-01-01')::text || '|' || extract(epoch from (recorded_at AT TIME ZONE 'UTC'))::text || '|'
            || rate_inputs::text || '|' || gas_factors::text || '|' || wna_inputs::text || '|' || tax_inputs::text || '|'
            || read_inputs::text || '|' || customer_inputs::text || '|' || period_inputs::text || '|' || line_items::text,
            'sha256'), 'hex')
    ) STORED,
    captured_at             timestamp with time zone DEFAULT now() NOT NULL,
    captured_by             uuid,
    notes                   text,
    CONSTRAINT invoice_calculation_snapshots_pkey PRIMARY KEY (id),
    CONSTRAINT invoice_calculation_snapshots_invoice_id_key UNIQUE (invoice_id),
    CONSTRAINT invoice_calculation_snapshots_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id),
    CONSTRAINT invoice_calculation_snapshots_invoice_fkey FOREIGN KEY (invoice_id, tenant_id) REFERENCES public.invoices(id, tenant_id) ON DELETE CASCADE,
    CONSTRAINT invoice_calculation_snapshots_billing_run_id_fkey FOREIGN KEY (billing_run_id) REFERENCES public.billing_runs(id),
    CONSTRAINT invoice_calculation_snapshots_captured_by_fkey FOREIGN KEY (captured_by) REFERENCES public.users(id),
    CONSTRAINT invoice_calculation_snapshots_schema_version_check CHECK (snapshot_schema_version ~ '^v[0-9]+$'),
    CONSTRAINT invoice_calculation_snapshots_formula_version_check CHECK (length(btrim(formula_version)) > 0),
    CONSTRAINT invoice_calculation_snapshots_rate_inputs_check CHECK (jsonb_typeof(rate_inputs) = 'object'),
    CONSTRAINT invoice_calculation_snapshots_gas_factors_check CHECK (jsonb_typeof(gas_factors) = 'object'),
    CONSTRAINT invoice_calculation_snapshots_wna_inputs_check CHECK (jsonb_typeof(wna_inputs) = 'object'),
    CONSTRAINT invoice_calculation_snapshots_tax_inputs_check CHECK (jsonb_typeof(tax_inputs) = 'object'),
    CONSTRAINT invoice_calculation_snapshots_read_inputs_check CHECK (jsonb_typeof(read_inputs) = 'object'),
    CONSTRAINT invoice_calculation_snapshots_customer_inputs_check CHECK (jsonb_typeof(customer_inputs) = 'object'),
    CONSTRAINT invoice_calculation_snapshots_period_inputs_check CHECK (jsonb_typeof(period_inputs) = 'object'),
    CONSTRAINT invoice_calculation_snapshots_line_items_check CHECK (jsonb_typeof(line_items) = 'array')
);

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'invoice_calculation_snapshots_invoice_fkey' AND conrelid = 'public.invoice_calculation_snapshots'::regclass AND confdeltype <> 'c') THEN
        ALTER TABLE public.invoice_calculation_snapshots DROP CONSTRAINT invoice_calculation_snapshots_invoice_fkey;
        ALTER TABLE public.invoice_calculation_snapshots ADD CONSTRAINT invoice_calculation_snapshots_invoice_fkey FOREIGN KEY (invoice_id, tenant_id) REFERENCES public.invoices(id, tenant_id) ON DELETE CASCADE;
    END IF;
END;
$$;

CREATE INDEX IF NOT EXISTS idx_invoice_calculation_snapshots_tenant ON public.invoice_calculation_snapshots USING btree (tenant_id);
CREATE INDEX IF NOT EXISTS idx_invoice_calculation_snapshots_billing_run ON public.invoice_calculation_snapshots USING btree (billing_run_id) WHERE (billing_run_id IS NOT NULL);
CREATE INDEX IF NOT EXISTS idx_invoice_calculation_snapshots_content_hash ON public.invoice_calculation_snapshots USING btree (content_hash);

ALTER TABLE public.invoice_calculation_snapshots ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.invoice_calculation_snapshots FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_isolation ON public.invoice_calculation_snapshots;
CREATE POLICY tenant_isolation ON public.invoice_calculation_snapshots USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));

REVOKE UPDATE ON public.invoice_calculation_snapshots FROM tally_app;

COMMENT ON TABLE public.invoice_calculation_snapshots IS
    'CI-015 (v5.4.2-04, A-3, Option B). The complete, frozen input set of one invoice''s calculation: the run''s temporal coordinate pair (valid_at, recorded_at — the ONE pair AC-15 resolves per run), the snapshot schema version (key contract enforced by validate_calculation_snapshot()), the formula version replay will need, and eight sections mirroring CI-015''s input list. Exactly one per invoice; required at commit of any issuance (enforce_invoice_has_snapshot on invoices); INSERT/DELETE only while the invoice is draft/held; never UPDATE. Replay reads this row and the formula it names — not the bi-temporal reference layer. Provenance to the reference rows read lives in invoice_snapshot_references.';
COMMENT ON COLUMN public.invoice_calculation_snapshots.valid_at IS 'Valid-time coordinate the run passed to every *_as_of lookup (AC-15). A regular bill: the service period date the engine chose; a correction: the original period (CI-005) or the operator''s election (get_correction_rate_date).';
COMMENT ON COLUMN public.invoice_calculation_snapshots.recorded_at IS 'Transaction-time coordinate the run passed to every *_as_of lookup (AC-15): now() at calculation for current knowledge, or the original run''s instant when reproducing a bill. Must not be in the future.';
COMMENT ON COLUMN public.invoice_calculation_snapshots.snapshot_schema_version IS 'Key contract of the eight sections. Accepted versions are enumerated in validate_calculation_snapshot(); a new shape is a patch that teaches the validator. v1 = CI-015''s list as of 2026-08-28.';
COMMENT ON COLUMN public.invoice_calculation_snapshots.formula_version IS 'Identifier of the calculation formula/engine build that produced the bill. Replay = this snapshot + this formula version, nothing else (CI-015).';
COMMENT ON COLUMN public.invoice_calculation_snapshots.rate_inputs IS 'v1 keys: rate_schedule_id, rate_schedule_version_id, rate_schedule_code, customer_type, partial_period_policy, items[] (each: rate_item_id, rate_item_version_id, item_code, rate_value, rate_unit, tier, applicability, rate_schedule_item_id).';
COMMENT ON COLUMN public.invoice_calculation_snapshots.gas_factors IS 'v1 keys: pga_factor, btu_factor, pressure_factor, temperature_factor, meter_multiplier, factor_stack_intermediates (object). Null values allowed for non-gas invoices.';
COMMENT ON COLUMN public.invoice_calculation_snapshots.wna_inputs IS 'v1 keys: applied (boolean); when true also wna_zone_id, wna_zone_version_id, wna_monthly_adjustment_id, weather_station, normal_hdd, actual_hdd, deadband, base_load, heating_factor. CI-042: the NHDD baseline is not preserved by the reference layer — this section is the only replay substrate for WNA.';
COMMENT ON COLUMN public.invoice_calculation_snapshots.tax_inputs IS 'v1 keys: jurisdictions[] (each: jurisdiction_id, authority, rate, taxable_base), exemptions[] (each: customer_tax_exemption_id, exemption_type), franchise_fees[] (each: franchise_fee_rule_id, rate, base). Supersedes invoices.tax_breakdown as the input record (tax_breakdown remains the display record).';
COMMENT ON COLUMN public.invoice_calculation_snapshots.read_inputs IS 'v1 keys: reads[] (each: meter_id, meter_reading_id, read_date, raw_consumption, is_estimated, intermediate_values (object: every factor-stack step)).';
COMMENT ON COLUMN public.invoice_calculation_snapshots.customer_inputs IS 'v1 keys: customer_id, customer_class, location_id, premise_zones (object: zone kind -> zone id).';
COMMENT ON COLUMN public.invoice_calculation_snapshots.period_inputs IS 'v1 keys: period_start, period_end, days_in_period, proration_policy. period_start/period_end must equal the invoice''s (checked at insert and at issuance).';
COMMENT ON COLUMN public.invoice_calculation_snapshots.line_items IS 'v1: array of {invoice_line_item_id, charge_type, amount, …}. Must cite exactly the invoice''s invoice_line_items rows with matching amounts (checked at insert and again at issuance — a line edited after the snapshot invalidates it; delete and re-snapshot).';
COMMENT ON COLUMN public.invoice_calculation_snapshots.content_hash IS 'GENERATED sha256 (hex, pgcrypto digest) over versions + coordinate + all eight sections (jsonb canonical text). INV-099''s content-addressable framing; not caller-writable.';
COMMENT ON COLUMN public.invoice_calculation_snapshots.captured_at IS 'Forced to now() by trigger (the database''s clock, not the caller''s).';

-- ----------------------------------------------------------------------------
-- 3. Schema validator + invoice cross-checks (BEFORE INSERT)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.calculation_snapshot_line_items_match(p_invoice_id uuid, p_line_items jsonb) RETURNS boolean
    LANGUAGE sql STABLE
    SET search_path = public, pg_temp
    AS $$
    -- True when the snapshot's line_items array cites exactly the invoice's
    -- invoice_line_items rows (same id set, same amounts, no duplicates).
    WITH snap AS (
        SELECT (e ->> 'invoice_line_item_id')::uuid AS id,
               CASE WHEN jsonb_typeof(e -> 'amount') = 'number' THEN (e ->> 'amount')::numeric END AS amount
        FROM jsonb_array_elements(p_line_items) e
    ),
    live AS (
        SELECT l.id, l.amount FROM public.invoice_line_items l WHERE l.invoice_id = p_invoice_id
    )
    SELECT (SELECT count(*) FROM snap) = (SELECT count(DISTINCT id) FROM snap)
       AND NOT EXISTS (SELECT 1 FROM snap s WHERE s.id IS NULL OR s.amount IS NULL)
       AND NOT EXISTS (SELECT s.id, s.amount FROM snap s EXCEPT SELECT l.id, l.amount FROM live l)
       AND NOT EXISTS (SELECT l.id, l.amount FROM live l EXCEPT SELECT s.id, s.amount FROM snap s);
$$;

COMMENT ON FUNCTION public.calculation_snapshot_line_items_match(uuid, jsonb) IS
    'CI-015 helper (v5.4.2-04): does this line_items array cite exactly the invoice''s invoice_line_items (id set and amounts equal, no duplicate or null citations)? Used at snapshot insert and at issuance. Invoker rights: RLS applies.';

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
    IF NEW.recorded_at > now() THEN
        RAISE EXCEPTION USING
            MESSAGE = 'snapshot rejected: recorded_at may not lie in the future (it is the transaction-time coordinate the run used, AC-15)',
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
    'CI-015 gate on invoice_calculation_snapshots INSERT (v5.4.2-04): parent must exist in the same tenant and be draft/held; billing_run_id equals the invoice''s; recorded_at not in the future; captured_at forced to now(); snapshot_schema_version must be one the function enumerates (v1) and every section must carry that version''s required keys (nested shapes for items/reads/line_items); period and customer match the invoice; line_items cites exactly the invoice''s lines.';

DROP TRIGGER IF EXISTS a_validate_calculation_snapshot ON public.invoice_calculation_snapshots;
CREATE TRIGGER a_validate_calculation_snapshot BEFORE INSERT ON public.invoice_calculation_snapshots
    FOR EACH ROW EXECUTE FUNCTION public.validate_calculation_snapshot();

-- ----------------------------------------------------------------------------
-- 4. Immutability (UPDATE never; DELETE only while the invoice is draft/held)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.enforce_calculation_snapshot_immutable() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_status text;
    v_number text;
BEGIN
    IF TG_OP = 'UPDATE' THEN
        RAISE EXCEPTION USING
            MESSAGE = format('%s is immutable (CI-015): a frozen input set is never edited — while the invoice is draft/held, DELETE and re-insert', TG_TABLE_NAME),
            ERRCODE = 'check_violation';
    END IF;
    -- DELETE: only while the parent invoice is not issued. A missing parent
    -- is only reachable through the cascade of a draft-invoice delete (the
    -- FK cascades; A-4 forbids deleting an issued invoice, so the cascade
    -- can only ever remove a draft's snapshot — the invoice_line_items rule).
    SELECT i.status, i.invoice_number INTO v_status, v_number
    FROM public.invoices i WHERE i.id = OLD.invoice_id FOR SHARE;
    IF FOUND AND public.is_invoice_issued(v_status) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('invoice %s is issued (status %s): its calculation snapshot is immutable (CI-015) — DELETE rejected', v_number, v_status),
            ERRCODE = 'check_violation';
    END IF;
    RETURN OLD;
END;
$$;

COMMENT ON FUNCTION public.enforce_calculation_snapshot_immutable() IS
    'CI-015 guard (v5.4.2-04) for invoice_calculation_snapshots: UPDATE always rejected; DELETE rejected once the parent invoice is issued (is_invoice_issued). Draft/held parents may be re-snapshotted by delete + insert.';

DROP TRIGGER IF EXISTS enforce_calculation_snapshot_immutable ON public.invoice_calculation_snapshots;
CREATE TRIGGER enforce_calculation_snapshot_immutable BEFORE UPDATE OR DELETE ON public.invoice_calculation_snapshots
    FOR EACH ROW EXECUTE FUNCTION public.enforce_calculation_snapshot_immutable();
DROP TRIGGER IF EXISTS no_truncate ON public.invoice_calculation_snapshots;
CREATE TRIGGER no_truncate BEFORE TRUNCATE ON public.invoice_calculation_snapshots
    FOR EACH STATEMENT EXECUTE FUNCTION public.enforce_no_hard_delete();

-- ----------------------------------------------------------------------------
-- 5. Completeness at issuance (DEFERRABLE, on invoices)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.enforce_invoice_has_snapshot() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_snap public.invoice_calculation_snapshots%ROWTYPE;
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
    'CI-015 completeness (v5.4.2-04): at commit of any transaction that moves an invoice into an issued status (is_invoice_issued; INSERT included), exactly one invoice_calculation_snapshots row must exist for it and still agree with the invoice (period, billing run, customer, line id set + amounts). Voiding a draft/held invoice (a discard) is exempt. DEFERRABLE INITIALLY DEFERRED so the check runs at commit; the write order is invoice → lines → snapshot → status flip (the snapshot validator refuses an already-issued parent). Locks the lines (FOR SHARE) so a concurrent line edit is waited for and seen; a concurrent snapshot delete/insert waits on the invoice row lock inside its own guard and is then rejected.';

DROP TRIGGER IF EXISTS enforce_invoice_has_snapshot ON public.invoices;
CREATE CONSTRAINT TRIGGER enforce_invoice_has_snapshot
    AFTER INSERT OR UPDATE ON public.invoices
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION public.enforce_invoice_has_snapshot();

-- ----------------------------------------------------------------------------
-- 6. invoice_snapshot_references — provenance into the A-1 layer
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.invoice_snapshot_references (
    id              uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id       uuid NOT NULL,
    snapshot_id     uuid NOT NULL,
    source_table    text NOT NULL,
    source_row_id   uuid NOT NULL,
    role            text,
    CONSTRAINT invoice_snapshot_references_pkey PRIMARY KEY (id),
    CONSTRAINT invoice_snapshot_references_unique UNIQUE (snapshot_id, source_table, source_row_id),
    CONSTRAINT invoice_snapshot_references_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id),
    CONSTRAINT invoice_snapshot_references_snapshot_fkey FOREIGN KEY (snapshot_id) REFERENCES public.invoice_calculation_snapshots(id) ON DELETE CASCADE,
    CONSTRAINT invoice_snapshot_references_source_table_check CHECK (source_table = ANY (ARRAY[
        'rate_schedule_versions'::text, 'wna_zone_versions'::text, 'rate_item_versions'::text,
        'rate_schedule_items'::text, 'franchise_fee_rules'::text, 'customer_tax_exemptions'::text, 'wna_monthly_adjustments'::text]))
);

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'invoice_snapshot_references_snapshot_fkey' AND conrelid = 'public.invoice_snapshot_references'::regclass AND confdeltype <> 'c') THEN
        ALTER TABLE public.invoice_snapshot_references DROP CONSTRAINT invoice_snapshot_references_snapshot_fkey;
        ALTER TABLE public.invoice_snapshot_references ADD CONSTRAINT invoice_snapshot_references_snapshot_fkey FOREIGN KEY (snapshot_id) REFERENCES public.invoice_calculation_snapshots(id) ON DELETE CASCADE;
    END IF;
END;
$$;

CREATE INDEX IF NOT EXISTS idx_invoice_snapshot_references_tenant ON public.invoice_snapshot_references USING btree (tenant_id);
CREATE INDEX IF NOT EXISTS idx_invoice_snapshot_references_source ON public.invoice_snapshot_references USING btree (source_table, source_row_id);

ALTER TABLE public.invoice_snapshot_references ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.invoice_snapshot_references FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_isolation ON public.invoice_snapshot_references;
CREATE POLICY tenant_isolation ON public.invoice_snapshot_references USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));

REVOKE UPDATE ON public.invoice_snapshot_references FROM tally_app;

COMMENT ON TABLE public.invoice_snapshot_references IS
    'Provenance for a calculation snapshot (v5.4.2-04, A-3 → A-1): each row cites one bi-temporal row the calculation read (source_table ∈ the seven A-1 tables). The guard proves the citation was visible at the snapshot''s recorded_at (open on the transaction-time axis at that instant, same tenant). "Which rows did this bill use, and were they really what we knew then?" is answerable from this table; the values themselves are in the snapshot sections. Optional per snapshot; same immutability as the snapshot.';
COMMENT ON COLUMN public.invoice_snapshot_references.role IS 'Free-text tag of what the citation supplied (e.g. ''commodity_rate'', ''wna_factor'', ''tax_exemption''). Not enumerated: the calculation code names its own roles.';

CREATE OR REPLACE FUNCTION public.validate_snapshot_reference() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_snap    public.invoice_calculation_snapshots%ROWTYPE;
    v_status  text;
    v_visible boolean;
BEGIN
    SELECT * INTO v_snap FROM public.invoice_calculation_snapshots s WHERE s.id = NEW.snapshot_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING
            MESSAGE = format('snapshot reference rejected: snapshot %s not found (or not visible to this tenant)', NEW.snapshot_id),
            ERRCODE = 'foreign_key_violation';
    END IF;
    IF v_snap.tenant_id <> NEW.tenant_id THEN
        RAISE EXCEPTION USING
            MESSAGE = 'snapshot reference rejected: tenant_id must equal the snapshot''s tenant',
            ERRCODE = 'check_violation';
    END IF;
    SELECT i.status INTO v_status FROM public.invoices i WHERE i.id = v_snap.invoice_id FOR SHARE;
    IF FOUND AND public.is_invoice_issued(v_status) THEN
        RAISE EXCEPTION USING
            MESSAGE = 'snapshot reference rejected: the invoice is issued and its snapshot is frozen (CI-015)',
            ERRCODE = 'check_violation';
    END IF;
    -- The cited row must have been OPEN on the transaction-time axis at the
    -- snapshot's recorded_at, in the same tenant (every A-1 table carries
    -- recorded_at / recorded_until). The table name is re-checked here
    -- because this BEFORE trigger runs before the CHECK constraint would.
    IF NEW.source_table <> ALL (ARRAY['rate_schedule_versions', 'wna_zone_versions', 'rate_item_versions',
                                      'rate_schedule_items', 'franchise_fee_rules', 'customer_tax_exemptions', 'wna_monthly_adjustments']) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('snapshot reference rejected: %L is not one of the seven bi-temporal reference tables (invoice_snapshot_references_source_table_check)', NEW.source_table),
            ERRCODE = 'check_violation';
    END IF;
    EXECUTE format(
        'SELECT EXISTS (SELECT 1 FROM public.%I r WHERE r.id = $1 AND r.tenant_id = $2 AND r.recorded_at IS NOT NULL AND r.recorded_at <= $3 AND (r.recorded_until IS NULL OR r.recorded_until > $3))',
        NEW.source_table)
    INTO v_visible
    USING NEW.source_row_id, NEW.tenant_id, v_snap.recorded_at;
    IF NOT v_visible THEN
        RAISE EXCEPTION USING
            MESSAGE = format('snapshot reference rejected: %s row %s was not an open assertion at recorded_at %s in this tenant — the run could not have read it at that coordinate (AC-15 / CI-003)', NEW.source_table, NEW.source_row_id, v_snap.recorded_at),
            ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.validate_snapshot_reference() IS
    'Provenance guard (v5.4.2-04): a cited reference row must exist in source_table, in the snapshot''s tenant, and be open on the transaction-time axis at the snapshot''s recorded_at; the parent invoice must still be draft/held.';

DROP TRIGGER IF EXISTS a_validate_snapshot_reference ON public.invoice_snapshot_references;
CREATE TRIGGER a_validate_snapshot_reference BEFORE INSERT ON public.invoice_snapshot_references
    FOR EACH ROW EXECUTE FUNCTION public.validate_snapshot_reference();

CREATE OR REPLACE FUNCTION public.enforce_snapshot_reference_immutable() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_status text;
    v_number text;
BEGIN
    IF TG_OP = 'UPDATE' THEN
        RAISE EXCEPTION USING
            MESSAGE = 'invoice_snapshot_references is immutable (CI-015): citations are never edited — while the invoice is draft/held, DELETE and re-insert',
            ERRCODE = 'check_violation';
    END IF;
    SELECT i.status, i.invoice_number INTO v_status, v_number
    FROM public.invoice_calculation_snapshots s
    JOIN public.invoices i ON i.id = s.invoice_id
    WHERE s.id = OLD.snapshot_id
    FOR SHARE OF i;
    IF FOUND AND public.is_invoice_issued(v_status) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('invoice %s is issued (status %s): its snapshot provenance is immutable (CI-015) — DELETE rejected', v_number, v_status),
            ERRCODE = 'check_violation';
    END IF;
    RETURN OLD;
END;
$$;

DROP TRIGGER IF EXISTS enforce_snapshot_reference_immutable ON public.invoice_snapshot_references;
CREATE TRIGGER enforce_snapshot_reference_immutable BEFORE UPDATE OR DELETE ON public.invoice_snapshot_references
    FOR EACH ROW EXECUTE FUNCTION public.enforce_snapshot_reference_immutable();
DROP TRIGGER IF EXISTS no_truncate ON public.invoice_snapshot_references;
CREATE TRIGGER no_truncate BEFORE TRUNCATE ON public.invoice_snapshot_references
    FOR EACH STATEMENT EXECUTE FUNCTION public.enforce_no_hard_delete();

-- ----------------------------------------------------------------------------
-- 7. ENABLE ALWAYS on every guard this patch created (D-2026-08-20-27)
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
          AND (
                (c.relname IN ('invoice_calculation_snapshots', 'invoice_snapshot_references')
                 AND t.tgname IN ('no_truncate', 'a_validate_calculation_snapshot', 'enforce_calculation_snapshot_immutable',
                                  'a_validate_snapshot_reference', 'enforce_snapshot_reference_immutable'))
             OR (c.relname = 'invoices' AND t.tgname = 'enforce_invoice_has_snapshot')
          )
    LOOP
        EXECUTE format('ALTER TABLE public.%I ENABLE ALWAYS TRIGGER %I', r.relname, r.tgname);
    END LOOP;
END;
$$;

-- ----------------------------------------------------------------------------
-- 8. Cross-references on existing objects
-- ----------------------------------------------------------------------------
COMMENT ON COLUMN public.invoices.tax_breakdown IS
    'Itemized taxes by jurisdiction for regulatory-compliant display. JSONB array of {jurisdiction, authority, rate_item_id, amount}. Display record only: since v5.4.2-04 the tax INPUTS (rates, bases, exemptions, franchise rules) are frozen in invoice_calculation_snapshots.tax_inputs (CI-015).';
