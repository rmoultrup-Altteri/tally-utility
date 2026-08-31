-- ============================================================================
-- PATCH v5.4.2-07 — A-7: regulatory cost-recovery surcharge riders — the
--                    Texas Pipeline Safety Fee as the concrete instance
--                    (schema-parity-plan Phase 4 Wave 2, Appendix A-7;
--                    CI-038 / CI-045; CI-015 / CI-121 touched)
-- ============================================================================
-- Authority:   canonical-invariants.md CI-038 (Pipeline Safety Fee Surcharge
--              Discipline) and Appendix A-7; CI-045 (tax stacking and base
--              composition — "the per-bill base composition is materialized
--              on the invoice"); Kyle ruling D4-1 (wu5-wu6-kyle-decisions-
--              2026-07-10.md): "PSF is a rate-page line item, no timing
--              enforcement machinery ... the platform owes it the same
--              effective-dating + audit trail as any rate row"; the research
--              confirmation under it (16 TAC §8.201(b)(3): "immediately
--              following" is an ordering / upper-bound rule); the axes doc
--              regulatory-cost-recovery-surcharges-texas.md (A1 cap, A4
--              state-agency exemption, A5 tax-base treatment are the
--              structural candidates; A2/A3/A6 resolved to operator
--              guidance); decision tables #23 (tax-application-and-stacking,
--              stage 2: "the PSF rider is is_taxable = false and is
--              additionally excluded from the franchise-fee and gas-utility-
--              tax bases") and #26 (franchise-fee-application: the base is
--              composed "excluding PSF (CI-038)"); knowledge/31-texas-
--              regulatory-compliance.md §3.4.
--
-- What D4-1 leaves for the schema. The remittance gate and the post-
-- remittance billing window that Appendix A-7 and CI-038 name are NOT
-- platform rules (D4-1): no regulatory_remittances ledger, no gate, no
-- window check lands here — "bill after remittance, never before" is
-- operator guidance recorded in the axes doc. What is structural:
--
--   1. regulatory_surcharge_rules — the rider classification, one row per
--      (rate item, assessment cycle): surcharge_kind (pipeline_safety_fee |
--      other_regulatory_cost_recovery), the cycle as a closed bracket of
--      BILL DATES, cap_per_service (aggregate per service line over the
--      cycle; NULL = uncapped), excluded_from_tax_bases, exempts_state_
--      agencies, the regulatory and tariff-filing references. Bi-temporal
--      in place — the A-1 group-2 pattern one-for-one (transaction-time
--      pair, enforce_bitemporal_assertion, enforce_superseded_has_successor,
--      open-rows-only EXCLUDE on the cycle per rate item) — so a rule has
--      exactly the effective-dating and audit trail D4-1 asks for. A
--      pipeline_safety_fee rule must carry a cap and both flags (CHECK).
--      regulatory_surcharge_rule_as_of(rate_item, billed_on, recorded_at):
--      both coordinates REQUIRED, NULL raises, no now() default (R-15).
--      The cap is a configured amount, not a literal in a CHECK: CI-038
--      says $1.00 per service, D4-1's research note says $0.50, and that
--      discrepancy is Kyle's to resolve (3E/3F brief Part D) — the database
--      enforces the figure the tenant declares against its filed tariff.
--
--   2. customers.is_state_agency — the account-side designation CI-038's
--      exemption keys on (customer_type = 'government' is broader: cities,
--      counties, school districts are government and NOT exempt). CHECK:
--      only a government customer can be a state agency. It joins A-21's
--      customer_attribute_history (ninth attribute; initial row at insert,
--      backfill row for every existing customer) so the exemption is
--      evaluated for the BILLED PERIOD, not for today (axes doc A4: a mid-
--      cycle status change applies prospectively). customer_is_state_
--      agency_as_of(customer, on) is the read.
--
--   3. invoice_line_item_bases — the per-bill base composition CI-045 asks
--      to materialize: one row per (percentage/tax line, line it was
--      computed on, amount taken into the base). Guards: both lines on the
--      same invoice and tenant; the citing line is a tax line or a
--      percentage_of_bill / percentage_of_charges rate item; base_amount is
--      non-zero, same sign as, and no larger than the cited line's amount;
--      AN EXCLUDED SURCHARGE LINE CAN NEVER BE CITED AS A BASE (the
--      structural half of "PSF is exempt from franchise fees, gas-utility
--      tax and sales tax"); frozen once the invoice is issued (INSERT /
--      UPDATE / DELETE refused; the A-4 line-item rule); discarded with a
--      draft (ON DELETE CASCADE, like the lines and the snapshot). While
--      the invoice is a draft the lines stay consistent with it: a line
--      that has a composition (either side) cannot be moved to another
--      invoice, and a cited line cannot change amount under what a base
--      took from it. At issuance a DEFERRABLE INITIALLY DEFERRED trigger
--      on invoices requires every non-zero tax / percentage line to carry
--      at least one base row ON THIS INVOICE, re-checks every base row
--      (both lines on the invoice, bounds, and the exclusion at the
--      snapshot's coordinate), and re-runs the surcharge line checks
--      (below) — so a
--      draft edited after its lines were written (invoice_date moved into
--      another cycle, customer changed) is caught at commit. This is the
--      mechanism that makes the K4 open question (franchise_fee_rules.
--      applies_to vs the per-item is_taxable chain — which governs base
--      composition) NOT block CI-038: whichever the engine uses, the
--      composition is written down and the exclusion is checked on it.
--
--   4. Surcharge line discipline on invoice_line_items — for a line whose
--      rate item has a rule in force for the invoice's bill date: it is
--      never charge_type = 'tax'; when excluded_from_tax_bases it is
--      is_taxable = false with no taxable_amount and is cited by no base
--      row; when exempts_state_agencies and the customer was a state agency
--      at the end of the billed period the amount must be 0.00 (a zero
--      line may show the exemption; a charge may not); when capped the line
--      names its service (meter_id NOT NULL) and the cycle's cumulative
--      POSITIVE amounts per (rate item, meter) over non-void invoices —
--      drafts counted, the transaction serialised on a per-(rate item,
--      meter) mutex row (regulatory_surcharge_service_locks) — plus this
--      line must not exceed cap_per_service. A negative line (correction)
--      is accepted but never lends headroom; a voided invoice releases its
--      amount. One open pipeline_safety_fee rule per tenant per bill date
--      (a second PSF rider cannot double the cap).
--      Config-time consistency: a rate_item_versions row with
--      is_taxable_default or is_a_tax, or a rate_schedule_items row with
--      is_taxable_override = true, is refused for a rider that has an
--      excluded rule, and a rule is refused for a rider that already has
--      one (both directions, so the rider cannot be taxable by either
--      path); a pipeline_safety_fee rule requires a gas (or all-service)
--      rider.
--
--   5. Provenance: regulatory_surcharge_rules joins the tables an
--      invoice_snapshot_references row may cite (A-3's set becomes eight);
--      validate_snapshot_reference() re-issued with the extended list, body
--      otherwise unchanged. regulatory_surcharge_billing_summary
--      (security_invoker) gives the 90-day compliance report its billed
--      side per rule / cycle: services billed, lines, total billed on
--      issued non-void invoices, first / last bill date, distinct unit
--      rates, and the amount still sitting in drafts. "Total collected"
--      is not derivable — payments are not allocated per line — and is the
--      application's (boundary stated in the view comment).
--
--   6. Tenant binding: UNIQUE (id, tenant_id) on invoice_line_items (new);
--      every new FK composite; changed_by / closed_by checked by
--      assert_same_tenant_user(). RLS + FORCE on both new tables; DELETE
--      revoked from tally_app on the rules table (bi-temporal rows are
--      closed, never deleted — the A-1 guard refuses DELETE) and the bases
--      table joins the A-4 pattern (its own guard carries the draft-only
--      delete rule; no_truncate); every guard ENABLE ALWAYS
--      (D-2026-08-20-27).
--
-- Deferred with stated triggers (not in this patch): the remittance ledger
-- and any gate on it (D4-1 — revisit only if Kyle reverses it); a v2
-- snapshot key contract carrying base_composition (the bases table is the
-- record; the snapshot's line_items already freezes the lines — a v2 waits
-- for the calculation code that would write it, R-16's trigger); tax-on-tax
-- stacking rules and the per-jurisdiction stack (A-8 — a tax line MAY cite
-- another tax line here; whether it may in a given jurisdiction is #23
-- stage 3, unruled); is_taxable_default's silent false default (K1 open
-- question 1, Kyle); the compliance report's paid side; a per-kind
-- statutory ceiling on cap_per_service (the $1.00 / $0.50 question);
-- classification of ad-hoc surcharge lines (adhoc_charge_id, no rate item —
-- outside this discipline; #25 governs their taxability).
--
-- Preconditions: none are self-verifying refusals. On a fresh deploy every
-- backfill is a no-op; on a populated one the patch reports (NOTICE) the
-- is_state_agency history rows written and the count of issued invoices
-- that carry tax / percentage lines with no base composition (pre-patch
-- bills; nothing can be written for them — their lines are frozen).
--
-- Drafting decisions (durable copies: application/DECISION-LOG.md):
--   * The rule is keyed by the rate item, not by a surcharge_class column
--     on rate_item_versions: the cap and its cycle are per assessment, the
--     classification is per rider, and both need the bi-temporal pair — one
--     in-place table (the franchise_fee_rules shape) carries both without
--     re-versioning every rider on a cycle change.
--   * The cycle is a bracket of BILL DATES (invoices.invoice_date), not of
--     service periods: §8.201 speaks of "the billing cycle or cycles"
--     following remittance and of the total billed per service; the rider's
--     own valid-time bracket (rate_item_versions) still governs whether the
--     rider is on the schedule for a service period.
--   * "Per service" = per meter (meters.id): the fee is assessed per
--     service line; a premise with two gas meters is two service lines. A
--     capped line without a meter is refused rather than aggregated by
--     location — a consolidated or location-level surcharge line cannot be
--     capped per service honestly.
--   * The cap counts drafts, and counts only positive amounts. Two drafts
--     for one meter in one cycle are both charges the tenant intends;
--     counting only issued invoices would let two concurrent runs each pass
--     and both issue. A negative line never lends headroom (Fable HIGH-1:
--     a -5.00 draft let a +6.00 bill issue, then the draft was discarded);
--     the path to bill again is void + rebill. Discarding a draft or
--     voiding an issued invoice frees its positive amount.
--   * The cap's concurrency guard is a mutex ROW, not an advisory lock: an
--     advisory lock serialises writers but under REPEATABLE READ each
--     still sums its own stale snapshot (Fable HIGH-4: 1.20 on a 1.00 cap
--     from two RR sessions); an upsert on a shared row makes the loser
--     fail with a serialization error and retry.
--   * The issuance gate judges on CURRENT knowledge, not on the snapshot's
--     coordinate: A-3 accepts any past recorded_at and any valid_at, so a
--     backdated pair hid the rule and the rider's calculation type (Fable
--     HIGH-2). The snapshot is the run's record; compliance at issue time
--     is a fact about the bill. A-3's unbound valid_at is recorded in A-23.
--   * A-21's event tables gain an INSERT fence (depth 0 refused unless a
--     superuser is migrating): tally_app held INSERT on
--     customer_attribute_history and could write the exemption away with a
--     direct row (Fable HIGH-3). Closing it here rather than in a separate
--     A-21 rider because A-7 is the first patch whose enforcement READS
--     that history.
--   * A surcharge line's rate_item_id is frozen once written (Codex
--     CRITICAL-1: nulling it detached a capped line from every check while
--     it kept its description, and it then took any amount to issuance).
--     The OLD rider's rule for the bill date decides; reclassifying a line
--     is delete + new line, which re-runs every check.
--   * Known gap, stated: "per service = per meter" resets the cap when a
--     meter is changed out mid-cycle (a new meters row); the service line
--     is the same. Aggregating by location would over-count multi-meter
--     premises. Candidate Kyle item; the header's per-meter reading stands.
--   * Two more stated gaps (Fable round 2, LOW): the per-tenant PSF EXCLUDE
--     keys on surcharge_kind, so a twin rider deliberately labelled
--     other_regulatory_cost_recovery with the same cap and flags is
--     accepted — mislabelling is a configuration act, not a bypass; and two
--     sessions writing capped lines for two meters in opposite order can
--     deadlock on the mutex rows — Postgres reports it and the writer
--     retries; never a cap breach.
--   * The exemption is evaluated at the end of the billed period from the
--     attribute history, never from the live row: a correction rebill of
--     an old period asks what the account was then (CI-005); a period that
--     predates the customer's history uses the earliest recorded value
--     (the initial / backfill row) — a customer with no history at all is
--     a defect and raises.
--   * A zero-amount PSF line is allowed on a state agency's bill (it shows
--     the exemption, the CI-046 shape); a non-zero one is refused. The
--     axes doc's "must never see a PSF line" is read as "must never be
--     charged".
--   * The bases guard requires the citing line to be a tax line or a
--     percentage rate item as of (invoice.period_end, now()) — lines are
--     written before the snapshot exists, so the guard uses current
--     knowledge; issuance re-checks classification at the snapshot's own
--     coordinate. A fixed charge cannot carry a base composition: the
--     table means one thing.
--   * A tax / percentage line with amount 0.00 may have no bases (nothing
--     on the bill was in its base — an empty composition has no rows);
--     any non-zero one must. CI-046's zero line for an exempt customer is
--     the zero case with bases: allowed, not required.
--   * remitted_on / remitted_amount were drafted on the rule and removed:
--     under D4-1 the platform owes nothing about remittance, and a later
--     fact on a frozen assertion would have needed either a mutable column
--     outside the audit trail or a correction close for a non-correction.
--     The tenant's payable to RRC lives in its accounting.
--   * Config-time refusal in both directions (rule vs taxable version /
--     override) rather than one: a rider made taxable after its rule
--     exists would otherwise be a silent CI-045 base-composition drift
--     until the next bill's line guard caught it — and the line guard
--     checks the LINE's flag, which the engine derives from the version.
--   * Rules join the citable provenance set: the run reads the rule (cap,
--     flags) and must be able to say which assertion it read.
--
-- Idempotent:  yes (CREATE TABLE/INDEX IF NOT EXISTS; CREATE OR REPLACE
--              FUNCTION / VIEW; triggers / policies / constraints DROP IF
--              EXISTS + re-CREATE; backfills guarded by NOT EXISTS; COMMENT
--              overwrite). Re-apply over an applied build is a no-op.
-- Line count:  mirrored into tu.sql as a pure APPEND at end of file — no
--              existing line shifts; anchors 337/3600/3679 unaffected.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Tenant-bound identity for composite FKs
-- ----------------------------------------------------------------------------
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'invoice_line_items_id_tenant_id_key' AND conrelid = 'public.invoice_line_items'::regclass) THEN
        ALTER TABLE public.invoice_line_items ADD CONSTRAINT invoice_line_items_id_tenant_id_key UNIQUE (id, tenant_id);
    END IF;
END;
$$;

-- ----------------------------------------------------------------------------
-- 2. regulatory_surcharge_rules — the rider classification, bi-temporal in place
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.regulatory_surcharge_rules (
    id                        uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id                 uuid NOT NULL,
    rate_item_id              uuid NOT NULL,
    surcharge_kind            text NOT NULL,
    cycle_start               date NOT NULL,
    cycle_end                 date NOT NULL,
    cap_per_service           numeric(12,2),
    excluded_from_tax_bases   boolean NOT NULL,
    exempts_state_agencies    boolean NOT NULL,
    regulatory_reference      text,
    tariff_filing_reference   text,
    notes                     text,
    metadata                  jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at                timestamp with time zone DEFAULT now() NOT NULL,
    updated_at                timestamp with time zone DEFAULT now() NOT NULL,
    recorded_at               timestamp with time zone DEFAULT now() NOT NULL,
    recorded_until            timestamp with time zone,
    change_type               text DEFAULT 'initial' NOT NULL,
    change_reason             text,
    changed_by                uuid,
    supersedes_id             uuid,
    closed_type               text,
    closed_reason             text,
    closed_by                 uuid,
    CONSTRAINT regulatory_surcharge_rules_pkey PRIMARY KEY (id),
    CONSTRAINT regulatory_surcharge_rules_id_tenant_id_key UNIQUE (id, tenant_id),
    CONSTRAINT regulatory_surcharge_rules_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id),
    CONSTRAINT regulatory_surcharge_rules_rate_item_fkey FOREIGN KEY (rate_item_id, tenant_id) REFERENCES public.rate_items(id, tenant_id),
    CONSTRAINT regulatory_surcharge_rules_changed_by_fkey FOREIGN KEY (changed_by) REFERENCES public.users(id),
    CONSTRAINT regulatory_surcharge_rules_closed_by_fkey FOREIGN KEY (closed_by) REFERENCES public.users(id),
    CONSTRAINT regulatory_surcharge_rules_supersedes_id_fkey FOREIGN KEY (supersedes_id) REFERENCES public.regulatory_surcharge_rules(id),
    CONSTRAINT regulatory_surcharge_rules_kind_check CHECK ((surcharge_kind = ANY (ARRAY['pipeline_safety_fee'::text, 'other_regulatory_cost_recovery'::text]))),
    CONSTRAINT regulatory_surcharge_rules_cycle_check CHECK ((cycle_end >= cycle_start)),
    CONSTRAINT regulatory_surcharge_rules_cap_positive_check CHECK (((cap_per_service IS NULL) OR (cap_per_service > (0)::numeric))),
    CONSTRAINT regulatory_surcharge_rules_psf_shape_check CHECK (((surcharge_kind <> 'pipeline_safety_fee'::text) OR ((cap_per_service IS NOT NULL) AND excluded_from_tax_bases AND exempts_state_agencies))),
    CONSTRAINT regulatory_surcharge_rules_change_type_check CHECK ((change_type = ANY (ARRAY['initial'::text, 'succession'::text, 'correction'::text, 'backfill'::text]))),
    CONSTRAINT regulatory_surcharge_rules_correction_reason_check CHECK (((change_type <> 'correction'::text) OR (change_reason IS NOT NULL))),
    CONSTRAINT regulatory_surcharge_rules_supersedes_check CHECK (((supersedes_id IS NULL) OR (change_type = 'succession'::text) OR (change_type = 'correction'::text))),
    CONSTRAINT regulatory_surcharge_rules_closed_type_check CHECK (((closed_type IS NULL) OR (closed_type = ANY (ARRAY['superseded'::text, 'retracted'::text])))),
    CONSTRAINT regulatory_surcharge_rules_close_consistent_check CHECK ((((recorded_until IS NULL) AND (closed_type IS NULL) AND (closed_reason IS NULL) AND (closed_by IS NULL)) OR ((recorded_until IS NOT NULL) AND (closed_type IS NOT NULL) AND (closed_reason IS NOT NULL) AND (recorded_until >= recorded_at))))
);

ALTER TABLE public.regulatory_surcharge_rules DROP CONSTRAINT IF EXISTS regulatory_surcharge_rules_open_no_overlap_excl;
ALTER TABLE public.regulatory_surcharge_rules ADD CONSTRAINT regulatory_surcharge_rules_open_no_overlap_excl
    EXCLUDE USING gist (rate_item_id WITH =, daterange(cycle_start, cycle_end, '[]') WITH &&) WHERE (recorded_until IS NULL);
-- The Pipeline Safety Fee is ONE assessment per tenant: a second PSF rider
-- with its own cap over an overlapping cycle would bill a service twice
-- (Fable MEDIUM-2a). One open pipeline_safety_fee rule per tenant per
-- bill date.
ALTER TABLE public.regulatory_surcharge_rules DROP CONSTRAINT IF EXISTS regulatory_surcharge_rules_one_psf_per_tenant_excl;
ALTER TABLE public.regulatory_surcharge_rules ADD CONSTRAINT regulatory_surcharge_rules_one_psf_per_tenant_excl
    EXCLUDE USING gist (tenant_id WITH =, daterange(cycle_start, cycle_end, '[]') WITH &&) WHERE (recorded_until IS NULL AND surcharge_kind = 'pipeline_safety_fee');

CREATE INDEX IF NOT EXISTS idx_regulatory_surcharge_rules_tenant ON public.regulatory_surcharge_rules USING btree (tenant_id);
CREATE INDEX IF NOT EXISTS idx_regulatory_surcharge_rules_open ON public.regulatory_surcharge_rules USING btree (rate_item_id, cycle_start DESC) WHERE (recorded_until IS NULL);
CREATE INDEX IF NOT EXISTS idx_regulatory_surcharge_rules_lineage ON public.regulatory_surcharge_rules USING btree (rate_item_id, recorded_at DESC);
CREATE INDEX IF NOT EXISTS idx_regulatory_surcharge_rules_supersedes ON public.regulatory_surcharge_rules USING btree (supersedes_id) WHERE (supersedes_id IS NOT NULL);

DROP TRIGGER IF EXISTS set_updated_at ON public.regulatory_surcharge_rules;
CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.regulatory_surcharge_rules FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();

ALTER TABLE public.regulatory_surcharge_rules ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.regulatory_surcharge_rules FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_isolation ON public.regulatory_surcharge_rules;
CREATE POLICY tenant_isolation ON public.regulatory_surcharge_rules USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));

REVOKE DELETE ON public.regulatory_surcharge_rules FROM tally_app;

COMMENT ON TABLE public.regulatory_surcharge_rules IS
    'CI-038 / CI-045 (v5.4.2-07, A-7). Classification of a rate item as a regulatory cost-recovery surcharge rider, one row per (rate item, assessment cycle): the cycle is a closed bracket of BILL DATES (invoices.invoice_date); cap_per_service is the aggregate a single service line (meter) may be billed over the cycle (NULL = uncapped); excluded_from_tax_bases makes the rider''s lines non-taxable and uncitable as a base by any tax / percentage line; exempts_state_agencies makes a non-zero line on a state-agency account (customers.is_state_agency at the end of the billed period) a refusal. A pipeline_safety_fee rule must carry a cap and both flags. Bi-temporal in place (A-1 group 2): frozen once recorded except notes / metadata; correction = close (closed_type = ''superseded'') + insert with supersedes_id; retraction = close as ''retracted''; one open row per rate item per bill date (exclusion). No remittance gate and no billing-window check exist (Kyle D4-1, 2026-07-10): "bill after remittance, never before" is operator guidance. Read through regulatory_surcharge_rule_as_of().';
COMMENT ON COLUMN public.regulatory_surcharge_rules.cycle_start IS 'First bill date of the assessment cycle (inclusive). A line on an invoice whose invoice_date lies in [cycle_start, cycle_end] is governed by this rule.';
COMMENT ON COLUMN public.regulatory_surcharge_rules.cycle_end IS 'Last bill date of the assessment cycle (inclusive). Open rows of one rate item never overlap.';
COMMENT ON COLUMN public.regulatory_surcharge_rules.cap_per_service IS 'Aggregate the rider may bill to ONE service line (invoice_line_items.meter_id) over the cycle, on non-void invoices, drafts included. Configured by the tenant against its filed tariff — no statutory figure is hard-coded (CI-038 states $1.00 per service; D4-1''s research note $0.50; open with Kyle). Required for pipeline_safety_fee.';
COMMENT ON COLUMN public.regulatory_surcharge_rules.excluded_from_tax_bases IS 'The rider is not a base for any tax or percentage charge (16 TAC §8.201: exempt from franchise fees, gas-utility tax and sales tax). Enforced on the rider''s versions and schedule overrides (never taxable), on its invoice lines (is_taxable = false, no taxable_amount) and on invoice_line_item_bases (never cited). Required true for pipeline_safety_fee.';
COMMENT ON COLUMN public.regulatory_surcharge_rules.exempts_state_agencies IS 'A customer that was a state agency (customers.is_state_agency, per customer_attribute_history) at the end of the billed period may carry only a 0.00 line for this rider. Required true for pipeline_safety_fee.';

-- 2.1 Rule guard: tenant-checked actors; a rider cannot be excluded from
--     tax bases while any open version or schedule override says taxable;
--     a pipeline_safety_fee rider is a gas (or all-service) item.
CREATE OR REPLACE FUNCTION public.enforce_regulatory_surcharge_rule() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_taxable_versions  integer;
    v_taxable_overrides integer;
    v_non_gas           integer;
    v_code              text;
BEGIN
    PERFORM public.assert_same_tenant_user(NEW.changed_by, NEW.tenant_id, 'regulatory_surcharge_rules.changed_by');
    PERFORM public.assert_same_tenant_user(NEW.closed_by, NEW.tenant_id, 'regulatory_surcharge_rules.closed_by');
    IF TG_OP = 'UPDATE' THEN
        RETURN NEW;      -- content is frozen by the bi-temporal guard; only the close and notes/metadata get here
    END IF;
    SELECT ri.item_code INTO v_code FROM public.rate_items ri WHERE ri.id = NEW.rate_item_id AND ri.tenant_id = NEW.tenant_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING
            MESSAGE = format('regulatory_surcharge_rules: rate item %s is not visible in tenant %s', NEW.rate_item_id, NEW.tenant_id),
            ERRCODE = 'foreign_key_violation';
    END IF;
    IF NEW.excluded_from_tax_bases THEN
        SELECT count(*) INTO v_taxable_versions
          FROM public.rate_item_versions v
         WHERE v.rate_item_id = NEW.rate_item_id AND v.recorded_until IS NULL AND (v.is_taxable_default OR v.is_a_tax);
        SELECT count(*) INTO v_taxable_overrides
          FROM public.rate_schedule_items s
         WHERE s.rate_item_id = NEW.rate_item_id AND s.recorded_until IS NULL AND s.is_taxable_override = true;
        IF v_taxable_versions > 0 OR v_taxable_overrides > 0 THEN
            RAISE EXCEPTION USING
                MESSAGE = format('regulatory_surcharge_rules: rider %s cannot be excluded from tax bases while %s open version(s) are taxable / a tax and %s open schedule override(s) say taxable — correct those assertions first (CI-038 / CI-045)', v_code, v_taxable_versions, v_taxable_overrides),
                ERRCODE = 'check_violation';
        END IF;
    END IF;
    IF NEW.surcharge_kind = 'pipeline_safety_fee' THEN
        SELECT count(*) INTO v_non_gas
          FROM public.rate_item_versions v
         WHERE v.rate_item_id = NEW.rate_item_id AND v.recorded_until IS NULL AND v.service_type NOT IN ('gas', 'all');
        IF v_non_gas > 0 THEN
            RAISE EXCEPTION USING
                MESSAGE = format('regulatory_surcharge_rules: the Pipeline Safety Fee is a gas-distribution assessment (16 TAC §8.201) but rider %s has %s open version(s) of another service type', v_code, v_non_gas),
                ERRCODE = 'check_violation';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.enforce_regulatory_surcharge_rule() IS
    'v5.4.2-07 (A-7): BEFORE INSERT/UPDATE on regulatory_surcharge_rules. Actors must belong to the tenant; on INSERT the rider must be visible in the tenant, an excluded rider may have no open taxable version / override (the reverse direction is enforced on those tables), and a pipeline_safety_fee rider is gas or all-service. Runs after a_enforce_bitemporal_assertion (name order).';

DROP TRIGGER IF EXISTS a_enforce_bitemporal_assertion ON public.regulatory_surcharge_rules;
CREATE TRIGGER a_enforce_bitemporal_assertion BEFORE INSERT OR UPDATE OR DELETE ON public.regulatory_surcharge_rules
    FOR EACH ROW EXECUTE FUNCTION public.enforce_bitemporal_assertion('notes,metadata,updated_at', 'rate_item_id');
DROP TRIGGER IF EXISTS b_enforce_regulatory_surcharge_rule ON public.regulatory_surcharge_rules;
CREATE TRIGGER b_enforce_regulatory_surcharge_rule BEFORE INSERT OR UPDATE ON public.regulatory_surcharge_rules
    FOR EACH ROW EXECUTE FUNCTION public.enforce_regulatory_surcharge_rule();
DROP TRIGGER IF EXISTS enforce_superseded_has_successor ON public.regulatory_surcharge_rules;
CREATE CONSTRAINT TRIGGER enforce_superseded_has_successor AFTER UPDATE ON public.regulatory_surcharge_rules
    DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.enforce_superseded_has_successor('rate_item_id');
DROP TRIGGER IF EXISTS no_truncate ON public.regulatory_surcharge_rules;
CREATE TRIGGER no_truncate BEFORE TRUNCATE ON public.regulatory_surcharge_rules
    FOR EACH STATEMENT EXECUTE FUNCTION public.enforce_no_hard_delete();

-- 2.2 The lookup (R-15 shape: both coordinates required, NULL raises).
CREATE OR REPLACE FUNCTION public.regulatory_surcharge_rule_as_of(p_rate_item_id uuid, p_billed_on date, p_recorded_at timestamp with time zone)
    RETURNS SETOF public.regulatory_surcharge_rules
    LANGUAGE plpgsql STABLE
    SET search_path = public, pg_temp
    AS $$
BEGIN
    IF p_billed_on IS NULL OR p_recorded_at IS NULL THEN
        RAISE EXCEPTION 'regulatory_surcharge_rule_as_of: p_billed_on and p_recorded_at are both required — pass the invoice''s bill date and the run''s recorded_at; never default to now() (CI-001 / CI-003 / CI-006)';
    END IF;
    RETURN QUERY
    SELECT r.* FROM public.regulatory_surcharge_rules r
    WHERE r.rate_item_id = p_rate_item_id
      AND r.recorded_at <= p_recorded_at AND (r.recorded_until IS NULL OR r.recorded_until > p_recorded_at)
      AND r.cycle_start <= p_billed_on AND r.cycle_end >= p_billed_on
    ORDER BY r.recorded_at DESC, r.id
    LIMIT 1;
END;
$$;

COMMENT ON FUNCTION public.regulatory_surcharge_rule_as_of(uuid, date, timestamp with time zone) IS
    'A-7 (v5.4.2-07). The surcharge rule governing a rider for a bill dated p_billed_on, as asserted at p_recorded_at: the open-at-that-instant row whose cycle contains the date. Zero rows = not a surcharge rider for that bill date. Both arguments REQUIRED; NULL RAISES; no live fallback. Invoker rights: RLS applies.';

-- 2.3 Reverse direction: a rider with an excluded rule can never be made taxable.
CREATE OR REPLACE FUNCTION public.enforce_surcharge_rider_not_taxable() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_flag boolean;
    v_rule public.regulatory_surcharge_rules%ROWTYPE;
BEGIN
    IF TG_TABLE_NAME = 'rate_item_versions' THEN
        v_flag := (to_jsonb(NEW) ->> 'is_taxable_default')::boolean OR (to_jsonb(NEW) ->> 'is_a_tax')::boolean;
    ELSE
        v_flag := (to_jsonb(NEW) ->> 'is_taxable_override')::boolean IS TRUE;
    END IF;
    IF NOT coalesce(v_flag, false) THEN
        RETURN NEW;
    END IF;
    SELECT r.* INTO v_rule
      FROM public.regulatory_surcharge_rules r
     WHERE r.rate_item_id = (to_jsonb(NEW) ->> 'rate_item_id')::uuid AND r.recorded_until IS NULL AND r.excluded_from_tax_bases
     ORDER BY r.cycle_start DESC LIMIT 1;
    IF FOUND THEN
        RAISE EXCEPTION USING
            MESSAGE = format('%s: rate item %s is a %s surcharge rider excluded from every tax base (regulatory_surcharge_rules %s, cycle %s..%s) and cannot be taxable or a tax (CI-038 / CI-045); retract the rule first if the classification is wrong', TG_TABLE_NAME, to_jsonb(NEW) ->> 'rate_item_id', v_rule.surcharge_kind, v_rule.id, v_rule.cycle_start, v_rule.cycle_end),
            ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.enforce_surcharge_rider_not_taxable() IS
    'v5.4.2-07 (A-7): BEFORE INSERT / UPDATE OF the taxability columns on rate_item_versions (is_taxable_default, is_a_tax) and rate_schedule_items (is_taxable_override): refused when the rate item has an open regulatory_surcharge_rules row with excluded_from_tax_bases. Together with the rule guard this makes the exclusion hold in both directions of configuration.';

DROP TRIGGER IF EXISTS b_enforce_surcharge_rider_not_taxable ON public.rate_item_versions;
CREATE TRIGGER b_enforce_surcharge_rider_not_taxable BEFORE INSERT OR UPDATE OF is_taxable_default, is_a_tax ON public.rate_item_versions
    FOR EACH ROW EXECUTE FUNCTION public.enforce_surcharge_rider_not_taxable();
DROP TRIGGER IF EXISTS b_enforce_surcharge_rider_not_taxable ON public.rate_schedule_items;
CREATE TRIGGER b_enforce_surcharge_rider_not_taxable BEFORE INSERT OR UPDATE OF is_taxable_override ON public.rate_schedule_items
    FOR EACH ROW EXECUTE FUNCTION public.enforce_surcharge_rider_not_taxable();

-- ----------------------------------------------------------------------------
-- 3. customers.is_state_agency — the exemption designation, with history
-- ----------------------------------------------------------------------------
ALTER TABLE public.customers ADD COLUMN IF NOT EXISTS is_state_agency boolean DEFAULT false NOT NULL;
ALTER TABLE public.customers DROP CONSTRAINT IF EXISTS customers_state_agency_is_government_check;
ALTER TABLE public.customers ADD CONSTRAINT customers_state_agency_is_government_check
    CHECK ((NOT is_state_agency) OR (customer_type = 'government'::text));

COMMENT ON COLUMN public.customers.is_state_agency IS
    'CI-038 (v5.4.2-07, A-7): the account is an agency of the State of Texas and is exempt from the Pipeline Safety Fee surcharge (16 TAC §8.201) and from any other rider whose rule exempts_state_agencies. Narrower than customer_type = ''government'' (cities, counties, school districts are government and NOT exempt) — CHECK: only a government customer may be flagged. Every change is logged to customer_attribute_history (attribute is_state_agency); the exemption is evaluated for the billed period through customer_is_state_agency_as_of(). Whether the designation needs a verifying document is open with Kyle.';

ALTER TABLE public.customer_attribute_history DROP CONSTRAINT IF EXISTS customer_attribute_history_attribute_check;
ALTER TABLE public.customer_attribute_history ADD CONSTRAINT customer_attribute_history_attribute_check CHECK ((attribute = ANY (ARRAY[
    'billing_delivery_method'::text, 'billing_hold'::text, 'consolidate_invoices'::text, 'do_not_disconnect'::text,
    'landlord_responsible'::text, 'customer_type'::text, 'autopay_enabled'::text, 'deposit_status'::text, 'is_state_agency'::text])));

-- 3.1 A-21's logger re-issued with the ninth attribute (body otherwise unchanged).
CREATE OR REPLACE FUNCTION public.log_customer_attribute_changes() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO public.customer_attribute_history (tenant_id, customer_id, attribute, old_value, new_value, effective_at, source)
        SELECT NEW.tenant_id, NEW.id, a.attribute, NULL,
               CASE a.attribute
                   WHEN 'billing_delivery_method' THEN NEW.billing_delivery_method
                   WHEN 'billing_hold' THEN NEW.billing_hold::text
                   WHEN 'consolidate_invoices' THEN NEW.consolidate_invoices::text
                   WHEN 'do_not_disconnect' THEN NEW.do_not_disconnect::text
                   WHEN 'landlord_responsible' THEN NEW.landlord_responsible::text
                   WHEN 'customer_type' THEN NEW.customer_type
                   WHEN 'deposit_status' THEN NEW.deposit_status
                   WHEN 'autopay_enabled' THEN 'false'
                   WHEN 'is_state_agency' THEN NEW.is_state_agency::text
               END,
               NEW.status_changed_at, 'initial'
          FROM (SELECT unnest(ARRAY['billing_delivery_method', 'billing_hold', 'consolidate_invoices', 'do_not_disconnect', 'landlord_responsible', 'customer_type', 'deposit_status', 'autopay_enabled', 'is_state_agency']) AS attribute) a;
        RETURN NULL;
    END IF;
    IF OLD.billing_delivery_method IS DISTINCT FROM NEW.billing_delivery_method THEN
        INSERT INTO public.customer_attribute_history (tenant_id, customer_id, attribute, old_value, new_value, effective_at) VALUES (NEW.tenant_id, NEW.id, 'billing_delivery_method', OLD.billing_delivery_method, NEW.billing_delivery_method, clock_timestamp());
    END IF;
    IF OLD.billing_hold IS DISTINCT FROM NEW.billing_hold THEN
        INSERT INTO public.customer_attribute_history (tenant_id, customer_id, attribute, old_value, new_value, effective_at, changed_by) VALUES (NEW.tenant_id, NEW.id, 'billing_hold', OLD.billing_hold::text, NEW.billing_hold::text, clock_timestamp(), NEW.billing_hold_set_by);
    END IF;
    IF OLD.consolidate_invoices IS DISTINCT FROM NEW.consolidate_invoices THEN
        INSERT INTO public.customer_attribute_history (tenant_id, customer_id, attribute, old_value, new_value, effective_at) VALUES (NEW.tenant_id, NEW.id, 'consolidate_invoices', OLD.consolidate_invoices::text, NEW.consolidate_invoices::text, clock_timestamp());
    END IF;
    IF OLD.do_not_disconnect IS DISTINCT FROM NEW.do_not_disconnect THEN
        INSERT INTO public.customer_attribute_history (tenant_id, customer_id, attribute, old_value, new_value, effective_at) VALUES (NEW.tenant_id, NEW.id, 'do_not_disconnect', OLD.do_not_disconnect::text, NEW.do_not_disconnect::text, clock_timestamp());
    END IF;
    IF OLD.landlord_responsible IS DISTINCT FROM NEW.landlord_responsible THEN
        INSERT INTO public.customer_attribute_history (tenant_id, customer_id, attribute, old_value, new_value, effective_at) VALUES (NEW.tenant_id, NEW.id, 'landlord_responsible', OLD.landlord_responsible::text, NEW.landlord_responsible::text, clock_timestamp());
    END IF;
    IF OLD.customer_type IS DISTINCT FROM NEW.customer_type THEN
        INSERT INTO public.customer_attribute_history (tenant_id, customer_id, attribute, old_value, new_value, effective_at) VALUES (NEW.tenant_id, NEW.id, 'customer_type', OLD.customer_type, NEW.customer_type, clock_timestamp());
    END IF;
    IF OLD.deposit_status IS DISTINCT FROM NEW.deposit_status THEN
        INSERT INTO public.customer_attribute_history (tenant_id, customer_id, attribute, old_value, new_value, effective_at, source) VALUES (NEW.tenant_id, NEW.id, 'deposit_status', OLD.deposit_status, NEW.deposit_status, clock_timestamp(), 'system');
    END IF;
    IF OLD.is_state_agency IS DISTINCT FROM NEW.is_state_agency THEN
        INSERT INTO public.customer_attribute_history (tenant_id, customer_id, attribute, old_value, new_value, effective_at) VALUES (NEW.tenant_id, NEW.id, 'is_state_agency', OLD.is_state_agency::text, NEW.is_state_agency::text, clock_timestamp());
    END IF;
    RETURN NULL;
END;
$$;

COMMENT ON FUNCTION public.log_customer_attribute_changes() IS
    'CI-121 (v5.4.2-06, re-issued v5.4.2-07 for is_state_agency): writes customer_attribute_history — the initial value of every tracked attribute at INSERT (effective_at = status_changed_at, source initial) and one row per changed attribute at UPDATE (effective_at = clock_timestamp()). Nine attributes since A-7.';

-- 3.2 Backfill: one history row per pre-existing customer (guarded; no-op on a fresh deploy).
DO $$
DECLARE v integer;
BEGIN
    INSERT INTO public.customer_attribute_history (tenant_id, customer_id, attribute, old_value, new_value, effective_at, source)
    SELECT c.tenant_id, c.id, 'is_state_agency', NULL, c.is_state_agency::text, c.created_at, 'backfill'
      FROM public.customers c
     WHERE NOT EXISTS (SELECT 1 FROM public.customer_attribute_history h WHERE h.customer_id = c.id AND h.attribute = 'is_state_agency');
    GET DIAGNOSTICS v = ROW_COUNT;
    IF v > 0 THEN RAISE NOTICE 'v5.4.2-07: % is_state_agency attribute-history backfill row(s) written at created_at (current value; history before this patch is unknown)', v; END IF;
END;
$$;

-- 3.3 The event tables are written by the database. A-21 left INSERT on
--     customer_state_events / customer_attribute_history open to tally_app
--     with no fence (Fable HIGH-3: a direct is_state_agency = 'false' row —
--     or 'banana' — cancelled the exemption without touching customers).
--     A direct insert (depth < 2 inside the guard) is refused unless the writer is a superuser (a
--     migration backfill — 3.2 above, and A-21's own); TEMP is revoked so
--     the depth fence is structural (D-2026-08-28-37). Boolean attributes
--     carry 'true' / 'false' only.
CREATE OR REPLACE FUNCTION public.enforce_event_written_by_db() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
BEGIN
    -- inside this trigger a direct statement is depth 1; the logger's inserts are depth 2
    IF pg_trigger_depth() < 2 AND NOT (SELECT r.rolsuper FROM pg_roles r WHERE r.rolname = current_user) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('%s is written by the database (CI-121): change the customer row and let the logger record it — a direct insert is not history', TG_TABLE_NAME),
            ERRCODE = 'insufficient_privilege';
    END IF;
    RETURN NEW;
END;
$$;
COMMENT ON FUNCTION public.enforce_event_written_by_db() IS 'v5.4.2-07 (A-7, closing an A-21 gap): BEFORE INSERT on customer_state_events and customer_attribute_history — refused for a direct statement (pg_trigger_depth() < 2 inside the guard) unless the writer is a superuser (migrations). With TEMP revoked from the app role the depth is a structural fence.';

DROP TRIGGER IF EXISTS a_enforce_event_written_by_db ON public.customer_attribute_history;
CREATE TRIGGER a_enforce_event_written_by_db BEFORE INSERT ON public.customer_attribute_history
    FOR EACH ROW EXECUTE FUNCTION public.enforce_event_written_by_db();
DROP TRIGGER IF EXISTS a_enforce_event_written_by_db ON public.customer_state_events;
CREATE TRIGGER a_enforce_event_written_by_db BEFORE INSERT ON public.customer_state_events
    FOR EACH ROW EXECUTE FUNCTION public.enforce_event_written_by_db();

ALTER TABLE public.customer_attribute_history DROP CONSTRAINT IF EXISTS customer_attribute_history_boolean_values_check;
ALTER TABLE public.customer_attribute_history ADD CONSTRAINT customer_attribute_history_boolean_values_check CHECK (
    (attribute <> ALL (ARRAY['billing_hold'::text, 'consolidate_invoices'::text, 'do_not_disconnect'::text, 'landlord_responsible'::text, 'autopay_enabled'::text, 'is_state_agency'::text]))
    OR ((new_value = ANY (ARRAY['true'::text, 'false'::text])) AND ((old_value IS NULL) OR (old_value = ANY (ARRAY['true'::text, 'false'::text])))));

-- 3.4 The read the exemption uses: the value in force at the END of a date,
--     with the day boundary pinned to Central time (the fee is a Texas
--     assessment; a session TimeZone must not move the boundary — Fable
--     MEDIUM-1). El Paso''s Mountain-time hour is accepted as within the
--     day-level precision of the rule.
CREATE OR REPLACE FUNCTION public.customer_is_state_agency_as_of(p_customer_id uuid, p_on date) RETURNS boolean
    LANGUAGE plpgsql STABLE
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v text;
BEGIN
    IF p_on IS NULL THEN
        RAISE EXCEPTION 'customer_is_state_agency_as_of: p_on is required (the end of the billed period); never default to today';
    END IF;
    v := public.customer_attribute_as_of(p_customer_id, 'is_state_agency', ((p_on + 1)::timestamp AT TIME ZONE 'America/Chicago'));
    IF v IS NULL THEN
        -- the period predates the account's recorded history: the earliest recorded value is the best knowledge there is
        SELECT h.new_value INTO v FROM public.customer_attribute_history h
         WHERE h.customer_id = p_customer_id AND h.attribute = 'is_state_agency'
         ORDER BY h.effective_at, h.seq LIMIT 1;
    END IF;
    IF v IS NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('customer_is_state_agency_as_of: customer %s has no is_state_agency history (not visible, or written outside the attribute logger)', p_customer_id),
            ERRCODE = 'no_data_found';
    END IF;
    RETURN v = 'true';
END;
$$;

COMMENT ON FUNCTION public.customer_is_state_agency_as_of(uuid, date) IS
    'A-7 (v5.4.2-07): was the account a state agency at the end of p_on (midnight America/Chicago), per customer_attribute_history? A date before the account''s first recorded value answers with that first value; no history at all raises. Never reads the live customers row. Invoker rights: RLS applies.';

-- ----------------------------------------------------------------------------
-- 4. invoice_line_item_bases — the per-bill base composition (CI-045)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.invoice_line_item_bases (
    id                 uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id          uuid NOT NULL,
    invoice_id         uuid NOT NULL,
    line_item_id       uuid NOT NULL,
    base_line_item_id  uuid NOT NULL,
    base_amount        numeric(12,2) NOT NULL,
    created_at         timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT invoice_line_item_bases_pkey PRIMARY KEY (id),
    CONSTRAINT invoice_line_item_bases_unique UNIQUE (line_item_id, base_line_item_id),
    CONSTRAINT invoice_line_item_bases_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id),
    CONSTRAINT invoice_line_item_bases_invoice_fkey FOREIGN KEY (invoice_id, tenant_id) REFERENCES public.invoices(id, tenant_id) ON DELETE CASCADE,
    CONSTRAINT invoice_line_item_bases_line_fkey FOREIGN KEY (line_item_id, tenant_id) REFERENCES public.invoice_line_items(id, tenant_id) ON DELETE CASCADE,
    CONSTRAINT invoice_line_item_bases_base_fkey FOREIGN KEY (base_line_item_id, tenant_id) REFERENCES public.invoice_line_items(id, tenant_id) ON DELETE CASCADE,
    CONSTRAINT invoice_line_item_bases_not_self_check CHECK ((line_item_id <> base_line_item_id)),
    CONSTRAINT invoice_line_item_bases_amount_nonzero_check CHECK ((base_amount <> (0)::numeric))
);

-- A draft invoice may be discarded (A-4); its composition goes with it, the
-- way its lines and snapshot do. Re-issued as CASCADE if an earlier apply
-- created it as NO ACTION.
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'invoice_line_item_bases_invoice_fkey' AND conrelid = 'public.invoice_line_item_bases'::regclass AND confdeltype <> 'c') THEN
        ALTER TABLE public.invoice_line_item_bases DROP CONSTRAINT invoice_line_item_bases_invoice_fkey;
        ALTER TABLE public.invoice_line_item_bases ADD CONSTRAINT invoice_line_item_bases_invoice_fkey FOREIGN KEY (invoice_id, tenant_id) REFERENCES public.invoices(id, tenant_id) ON DELETE CASCADE;
    END IF;
END;
$$;

CREATE INDEX IF NOT EXISTS idx_invoice_line_item_bases_tenant ON public.invoice_line_item_bases USING btree (tenant_id);
CREATE INDEX IF NOT EXISTS idx_invoice_line_item_bases_invoice ON public.invoice_line_item_bases USING btree (invoice_id);
CREATE INDEX IF NOT EXISTS idx_invoice_line_item_bases_base ON public.invoice_line_item_bases USING btree (base_line_item_id);

ALTER TABLE public.invoice_line_item_bases ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.invoice_line_item_bases FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_isolation ON public.invoice_line_item_bases;
CREATE POLICY tenant_isolation ON public.invoice_line_item_bases USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));

COMMENT ON TABLE public.invoice_line_item_bases IS
    'CI-045 (v5.4.2-07, A-7). The materialized base composition of a bill: one row per (tax / percentage line, line it was computed on, amount of that line taken into the base). Written by the calculation with the lines, before the snapshot; frozen with the invoice (INSERT / UPDATE / DELETE refused once issued — the A-4 line rule). Every non-zero tax or percentage line must have at least one row at issuance (enforce_invoice_surcharge_lines_and_bases). A line of a rider whose regulatory_surcharge_rules row says excluded_from_tax_bases can never be cited (CI-038: the PSF is not a base for franchise fee, gas-utility tax or sales tax). Whether a tax line may cite another tax line (tax-on-tax) is a jurisdiction rule (#23 stage 3, A-8) and is not decided here.';
COMMENT ON COLUMN public.invoice_line_item_bases.base_amount IS 'The part of the cited line''s amount that entered this base: non-zero, same sign as, and no larger in magnitude than the cited line''s amount (a partially taxable line contributes its taxable part).';

-- 4.1 Shared classification helper: is this line one that carries a base?
--     (a tax line, or a percentage_of_bill / percentage_of_charges rate item
--     at the given coordinate)
CREATE OR REPLACE FUNCTION public.line_item_carries_base(p_line public.invoice_line_items, p_valid_at date, p_recorded_at timestamp with time zone) RETURNS boolean
    LANGUAGE plpgsql STABLE
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_calc text;
BEGIN
    IF p_line.charge_type = 'tax' THEN
        RETURN true;
    END IF;
    IF p_line.rate_item_id IS NULL THEN
        RETURN false;
    END IF;
    SELECT v.calculation_type INTO v_calc FROM public.rate_item_as_of(p_line.rate_item_id, p_valid_at, p_recorded_at) v;
    RETURN coalesce(v_calc IN ('percentage_of_bill', 'percentage_of_charges'), false);
END;
$$;

COMMENT ON FUNCTION public.line_item_carries_base(public.invoice_line_items, date, timestamp with time zone) IS
    'A-7 helper: true for a charge_type = ''tax'' line and for a line whose rate item is percentage_of_bill / percentage_of_charges at (p_valid_at, p_recorded_at). These are the lines invoice_line_item_bases may describe and must describe when non-zero.';

-- 4.2 The bases guard.
CREATE OR REPLACE FUNCTION public.enforce_invoice_line_item_base() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_inv   public.invoices%ROWTYPE;
    v_line  public.invoice_line_items%ROWTYPE;
    v_base  public.invoice_line_items%ROWTYPE;
    v_rule  public.regulatory_surcharge_rules%ROWTYPE;
    v_invoice_id uuid := CASE WHEN TG_OP = 'DELETE' THEN OLD.invoice_id ELSE NEW.invoice_id END;
BEGIN
    -- The invoice row is locked FOR SHARE so a concurrent issuance (an
    -- UPDATE of status holding the row lock) is waited for and then seen.
    SELECT * INTO v_inv FROM public.invoices i WHERE i.id = v_invoice_id FOR SHARE;
    IF NOT FOUND THEN
        IF TG_OP = 'DELETE' THEN
            RETURN OLD;      -- only reachable through the cascade of a draft-invoice delete (A-3's snapshot rule)
        END IF;
        RAISE EXCEPTION USING
            MESSAGE = format('invoice_line_item_bases: invoice %s is not visible in this tenant', v_invoice_id),
            ERRCODE = 'foreign_key_violation';
    END IF;
    IF public.is_invoice_issued(v_inv.status) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('invoice %s is issued (status %s): its base composition is immutable (CI-012 / CI-045) — %s rejected; correct it with void_invoice() + rebill', v_inv.invoice_number, v_inv.status, TG_OP),
            ERRCODE = 'restrict_violation';
    END IF;
    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    IF NEW.tenant_id <> v_inv.tenant_id THEN
        RAISE EXCEPTION USING MESSAGE = 'invoice_line_item_bases: tenant_id must equal the invoice''s tenant', ERRCODE = 'check_violation';
    END IF;
    SELECT * INTO v_line FROM public.invoice_line_items l WHERE l.id = NEW.line_item_id;
    IF NOT FOUND OR v_line.invoice_id <> NEW.invoice_id THEN
        RAISE EXCEPTION USING
            MESSAGE = format('invoice_line_item_bases: line %s is not a line of invoice %s', NEW.line_item_id, v_inv.invoice_number),
            ERRCODE = 'check_violation';
    END IF;
    SELECT * INTO v_base FROM public.invoice_line_items l WHERE l.id = NEW.base_line_item_id;
    IF NOT FOUND OR v_base.invoice_id <> NEW.invoice_id THEN
        RAISE EXCEPTION USING
            MESSAGE = format('invoice_line_item_bases: base line %s is not a line of invoice %s', NEW.base_line_item_id, v_inv.invoice_number),
            ERRCODE = 'check_violation';
    END IF;
    IF NOT public.line_item_carries_base(v_line, v_inv.period_end, now()) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('invoice_line_item_bases: line %s (%s) is neither a tax line nor a percentage rate item — only those carry a base composition (CI-045)', v_line.id, v_line.description),
            ERRCODE = 'check_violation';
    END IF;
    IF sign(NEW.base_amount) <> sign(v_base.amount) OR abs(NEW.base_amount) > abs(v_base.amount) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('invoice_line_item_bases: base_amount %s must have the sign of, and not exceed, the cited line''s amount %s (line %s)', NEW.base_amount, v_base.amount, v_base.description),
            ERRCODE = 'check_violation';
    END IF;
    IF v_base.rate_item_id IS NOT NULL THEN
        SELECT r.* INTO v_rule FROM public.regulatory_surcharge_rule_as_of(v_base.rate_item_id, v_inv.invoice_date, now()) r;
        IF FOUND AND v_rule.excluded_from_tax_bases THEN
            RAISE EXCEPTION USING
                MESSAGE = format('invoice_line_item_bases: line %s is a %s surcharge excluded from every tax base (regulatory_surcharge_rules %s) and cannot enter the base of %s (CI-038 / 16 TAC §8.201)', v_base.description, v_rule.surcharge_kind, v_rule.id, v_line.description),
                ERRCODE = 'check_violation';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.enforce_invoice_line_item_base() IS
    'CI-045 / CI-038 (v5.4.2-07): BEFORE INSERT / UPDATE / DELETE on invoice_line_item_bases. Parent invoice visible and not issued (frozen after); both lines on that invoice; the citing line carries a base (tax or percentage item as of (period_end, now()) — lines precede the snapshot); base_amount sign-consistent and bounded by the cited line; a cited line whose rider is excluded_from_tax_bases for the bill date is refused. Issuance re-checks at the snapshot coordinate.';

DROP TRIGGER IF EXISTS enforce_invoice_line_item_base ON public.invoice_line_item_bases;
CREATE TRIGGER enforce_invoice_line_item_base BEFORE INSERT OR UPDATE OR DELETE ON public.invoice_line_item_bases
    FOR EACH ROW EXECUTE FUNCTION public.enforce_invoice_line_item_base();
DROP TRIGGER IF EXISTS no_truncate ON public.invoice_line_item_bases;
CREATE TRIGGER no_truncate BEFORE TRUNCATE ON public.invoice_line_item_bases
    FOR EACH STATEMENT EXECUTE FUNCTION public.enforce_no_hard_delete();

-- ----------------------------------------------------------------------------
-- 5. Surcharge line discipline on invoice_line_items
-- ----------------------------------------------------------------------------
-- 5.0 The per-(rider, service) mutex the cap check serialises on. A row is
--     upserted (touched) before the cycle total is summed: under READ
--     COMMITTED the second writer waits on the row lock and then sums with
--     a fresh snapshot; under REPEATABLE READ / SERIALIZABLE the second
--     writer's UPDATE of a row the first writer changed raises a
--     serialization failure instead of passing on a stale sum (Fable
--     HIGH-4 — an advisory lock serialised the writers but not their
--     snapshots). Not a projection: it carries no total.
CREATE TABLE IF NOT EXISTS public.regulatory_surcharge_service_locks (
    tenant_id     uuid NOT NULL,
    rate_item_id  uuid NOT NULL,
    meter_id      uuid NOT NULL,
    touched_at    timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT regulatory_surcharge_service_locks_pkey PRIMARY KEY (rate_item_id, meter_id),
    CONSTRAINT regulatory_surcharge_service_locks_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id),
    CONSTRAINT regulatory_surcharge_service_locks_rate_item_fkey FOREIGN KEY (rate_item_id, tenant_id) REFERENCES public.rate_items(id, tenant_id),
    CONSTRAINT regulatory_surcharge_service_locks_meter_fkey FOREIGN KEY (meter_id, tenant_id) REFERENCES public.meters(id, tenant_id)
);
CREATE INDEX IF NOT EXISTS idx_regulatory_surcharge_service_locks_tenant ON public.regulatory_surcharge_service_locks USING btree (tenant_id);
ALTER TABLE public.regulatory_surcharge_service_locks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.regulatory_surcharge_service_locks FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_isolation ON public.regulatory_surcharge_service_locks;
CREATE POLICY tenant_isolation ON public.regulatory_surcharge_service_locks USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));
REVOKE DELETE ON public.regulatory_surcharge_service_locks FROM tally_app;
COMMENT ON TABLE public.regulatory_surcharge_service_locks IS
    'v5.4.2-07 (A-7): serialisation rows for the per-service surcharge cap — one per (rider, meter), touched by assert_surcharge_line() before it sums the cycle. Under READ COMMITTED concurrent writers queue on the row; under REPEATABLE READ / SERIALIZABLE the loser gets a serialization failure and must retry with a fresh snapshot. Carries no amount: the cap total is always summed from invoice_line_items.';

-- 5.1 The checks, shared by the line guard and the issuance gate — both on
--     CURRENT knowledge (now()): the cap, the exemption and the exclusion
--     are facts about the bill being issued, not about what the run knew
--     (Fable HIGH-2: the snapshot's coordinate pair is caller-chosen).
--     Silent when the line's rate item has no rule for the invoice's bill
--     date.
CREATE OR REPLACE FUNCTION public.assert_surcharge_line(p_line public.invoice_line_items, p_recorded_at timestamp with time zone) RETURNS void
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_inv  public.invoices%ROWTYPE;
    v_rule public.regulatory_surcharge_rules%ROWTYPE;
    v_sum  numeric;
BEGIN
    IF p_line.rate_item_id IS NULL THEN
        RETURN;
    END IF;
    SELECT * INTO v_inv FROM public.invoices i WHERE i.id = p_line.invoice_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING
            MESSAGE = format('invoice_line_items: invoice %s is not visible in this tenant', p_line.invoice_id),
            ERRCODE = 'foreign_key_violation';
    END IF;
    IF v_inv.tenant_id <> p_line.tenant_id THEN
        RAISE EXCEPTION USING MESSAGE = 'invoice_line_items: tenant_id must equal the invoice''s tenant', ERRCODE = 'check_violation';
    END IF;
    SELECT r.* INTO v_rule FROM public.regulatory_surcharge_rule_as_of(p_line.rate_item_id, v_inv.invoice_date, p_recorded_at) r;
    IF NOT FOUND THEN
        RETURN;
    END IF;
    IF p_line.charge_type = 'tax' THEN
        RAISE EXCEPTION USING
            MESSAGE = format('invoice %s: line %s is a %s surcharge rider (regulatory_surcharge_rules %s), not a tax — charge_type ''tax'' rejected (CI-038)', v_inv.invoice_number, p_line.description, v_rule.surcharge_kind, v_rule.id),
            ERRCODE = 'check_violation';
    END IF;
    IF v_rule.excluded_from_tax_bases THEN
        IF p_line.is_taxable OR coalesce(p_line.taxable_amount, 0) <> 0 THEN
            RAISE EXCEPTION USING
                MESSAGE = format('invoice %s: line %s is a %s surcharge excluded from every tax base — is_taxable must be false and taxable_amount empty (CI-038 / 16 TAC §8.201; rule %s)', v_inv.invoice_number, p_line.description, v_rule.surcharge_kind, v_rule.id),
                ERRCODE = 'check_violation';
        END IF;
        IF EXISTS (SELECT 1 FROM public.invoice_line_item_bases b WHERE b.base_line_item_id = p_line.id) THEN
            RAISE EXCEPTION USING
                MESSAGE = format('invoice %s: line %s is a %s surcharge excluded from every tax base but is cited as a base by another line (CI-038 / CI-045; rule %s)', v_inv.invoice_number, p_line.description, v_rule.surcharge_kind, v_rule.id),
                ERRCODE = 'check_violation';
        END IF;
    END IF;
    IF v_rule.exempts_state_agencies AND p_line.amount <> 0 AND public.customer_is_state_agency_as_of(v_inv.customer_id, v_inv.period_end) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('invoice %s: the customer was a state agency at the end of the billed period (%s) and is exempt from the %s surcharge — line %s must be 0.00 (CI-038; rule %s)', v_inv.invoice_number, v_inv.period_end, v_rule.surcharge_kind, p_line.description, v_rule.id),
            ERRCODE = 'check_violation';
    END IF;
    IF v_rule.cap_per_service IS NOT NULL THEN
        IF p_line.meter_id IS NULL THEN
            RAISE EXCEPTION USING
                MESSAGE = format('invoice %s: line %s is a %s surcharge capped per service (%s over the cycle %s..%s) and must name its service — meter_id is required (CI-038; rule %s)', v_inv.invoice_number, p_line.description, v_rule.surcharge_kind, v_rule.cap_per_service, v_rule.cycle_start, v_rule.cycle_end, v_rule.id),
                ERRCODE = 'check_violation';
        END IF;
        -- serialise concurrent lines for one (rider, service) on the mutex row (5.0)
        INSERT INTO public.regulatory_surcharge_service_locks (tenant_id, rate_item_id, meter_id)
        VALUES (p_line.tenant_id, p_line.rate_item_id, p_line.meter_id)
        ON CONFLICT (rate_item_id, meter_id) DO UPDATE SET touched_at = clock_timestamp();
        -- Only POSITIVE amounts count toward the cap: a negative line (a
        -- correction) never lends headroom, because the invoice carrying it
        -- can be discarded or voided later (Fable HIGH-1). The path to bill
        -- again is void + rebill, which releases the voided amount.
        SELECT coalesce(sum(greatest(l.amount, 0)), 0) INTO v_sum
          FROM public.invoice_line_items l
          JOIN public.invoices i ON i.id = l.invoice_id
         WHERE l.tenant_id = p_line.tenant_id
           AND l.rate_item_id = p_line.rate_item_id
           AND l.meter_id = p_line.meter_id
           AND l.id <> p_line.id
           AND i.status <> 'void'
           AND i.invoice_date >= v_rule.cycle_start AND i.invoice_date <= v_rule.cycle_end;
        IF v_sum + p_line.amount > v_rule.cap_per_service THEN
            RAISE EXCEPTION USING
                MESSAGE = format('invoice %s: line %s would bring the %s surcharge on this service to %s for the cycle %s..%s (%s already billed on non-void invoices and drafts, positive lines only, + %s), over the cap of %s per service (CI-038 / 16 TAC §8.201; rule %s)', v_inv.invoice_number, p_line.description, v_rule.surcharge_kind, v_sum + p_line.amount, v_rule.cycle_start, v_rule.cycle_end, v_sum, p_line.amount, v_rule.cap_per_service, v_rule.id),
                ERRCODE = 'check_violation';
        END IF;
    END IF;
END;
$$;

COMMENT ON FUNCTION public.assert_surcharge_line(public.invoice_line_items, timestamp with time zone) IS
    'CI-038 (v5.4.2-07): the surcharge line rules, applied when the line''s rate item has a regulatory_surcharge_rules row for the invoice''s bill date at p_recorded_at (otherwise silent). Never charge_type = ''tax''; excluded_from_tax_bases → is_taxable false, no taxable_amount, cited by no base row; exempts_state_agencies → 0.00 for a customer that was a state agency at period_end (attribute history, never the live row); cap_per_service → meter_id required and the cycle''s cumulative POSITIVE amounts for (rate item, meter) over non-void invoices — drafts included, this line excluded by id then added — must not exceed the cap; the transaction first touches the (rate item, meter) row of regulatory_surcharge_service_locks. Called with now() by the line guard and by the issuance gate (current knowledge — the snapshot coordinate is the run''s record, not the judge).';

-- 5.2 The line guard — runs after A-4's immutability guard (name order).
CREATE OR REPLACE FUNCTION public.enforce_surcharge_line() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_bad  record;
    v_inv  public.invoices%ROWTYPE;
    v_rule public.regulatory_surcharge_rules%ROWTYPE;
BEGIN
    IF TG_OP = 'UPDATE' THEN
        -- A surcharge line keeps its rider link: nulling or swapping
        -- rate_item_id detached the line from every cap / exclusion check
        -- while it kept its description and amount (Codex CRITICAL-1). The
        -- OLD rider's rule for the bill date decides; a genuine
        -- reclassification is delete + new line.
        IF NEW.rate_item_id IS DISTINCT FROM OLD.rate_item_id AND OLD.rate_item_id IS NOT NULL THEN
            SELECT * INTO v_inv FROM public.invoices i WHERE i.id = OLD.invoice_id;
            IF FOUND THEN
                SELECT r.* INTO v_rule FROM public.regulatory_surcharge_rule_as_of(OLD.rate_item_id, v_inv.invoice_date, now()) r;
                IF FOUND THEN
                    RAISE EXCEPTION USING
                        MESSAGE = format('line %s (%s) is a %s surcharge line (rule %s): its rate_item_id cannot be changed or removed — delete the line and write a new one (CI-038)', OLD.id, OLD.description, v_rule.surcharge_kind, v_rule.id),
                        ERRCODE = 'check_violation';
                END IF;
            END IF;
        END IF;
        -- A line with a base composition (on either side) stays on its invoice:
        -- re-parenting it would carry rows that describe another bill.
        IF NEW.invoice_id IS DISTINCT FROM OLD.invoice_id
           AND EXISTS (SELECT 1 FROM public.invoice_line_item_bases b WHERE b.line_item_id = OLD.id OR b.base_line_item_id = OLD.id) THEN
            RAISE EXCEPTION USING
                MESSAGE = format('line %s (%s) has a base composition (invoice_line_item_bases) and cannot be moved to another invoice — delete the composition first (CI-045)', OLD.id, OLD.description),
                ERRCODE = 'check_violation';
        END IF;
        -- A cited line cannot shrink under, or flip the sign of, what a base already took from it.
        IF NEW.amount IS DISTINCT FROM OLD.amount THEN
            SELECT b.base_amount, cl.description INTO v_bad
              FROM public.invoice_line_item_bases b
              JOIN public.invoice_line_items cl ON cl.id = b.line_item_id
             WHERE b.base_line_item_id = OLD.id
               AND (sign(b.base_amount) <> sign(NEW.amount) OR abs(b.base_amount) > abs(NEW.amount))
             LIMIT 1;
            IF FOUND THEN
                RAISE EXCEPTION USING
                    MESSAGE = format('line %s (%s) cannot change to %s: %s of it is already in the base of %s (invoice_line_item_bases) — adjust the composition first (CI-045)', OLD.id, OLD.description, NEW.amount, v_bad.base_amount, v_bad.description),
                    ERRCODE = 'check_violation';
            END IF;
        END IF;
    END IF;
    PERFORM public.assert_surcharge_line(NEW, now());
    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.enforce_surcharge_line() IS 'v5.4.2-07: BEFORE INSERT / UPDATE on invoice_line_items — a surcharge line''s rate_item_id is frozen (the OLD rider''s rule for the bill date decides); a draft line that has a base composition (either side) cannot be moved to another invoice, and a cited line cannot change amount under what a base took from it; then assert_surcharge_line(NEW, now()).';

DROP TRIGGER IF EXISTS z_enforce_surcharge_line ON public.invoice_line_items;
CREATE TRIGGER z_enforce_surcharge_line BEFORE INSERT OR UPDATE OF rate_item_id, amount, meter_id, is_taxable, taxable_amount, invoice_id, charge_type ON public.invoice_line_items
    FOR EACH ROW EXECUTE FUNCTION public.enforce_surcharge_line();

-- 5.3 The issuance gate: base completeness + re-check at the snapshot coordinate.
CREATE OR REPLACE FUNCTION public.enforce_invoice_surcharge_lines_and_bases() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_snap public.invoice_calculation_snapshots%ROWTYPE;
    v_line public.invoice_line_items%ROWTYPE;
    v_base record;
    v_rule public.regulatory_surcharge_rules%ROWTYPE;
BEGIN
    IF NOT public.is_invoice_issued(NEW.status) THEN
        RETURN NULL;
    END IF;
    IF TG_OP = 'UPDATE' AND public.is_invoice_issued(OLD.status) THEN
        RETURN NULL;
    END IF;
    IF TG_OP = 'UPDATE' AND NEW.status = 'void' THEN
        RETURN NULL;         -- discarding a draft/held invoice is not an issuance (A-3's rule)
    END IF;
    SELECT * INTO v_snap FROM public.invoice_calculation_snapshots s WHERE s.invoice_id = NEW.id;
    IF NOT FOUND THEN
        RETURN NULL;         -- enforce_invoice_has_snapshot (queued first) raises for this
    END IF;
    -- Every check below runs on CURRENT knowledge — (invoice_date, now()) for
    -- the rules, (period_end, now()) for the classification. The snapshot's
    -- pair is caller-supplied (A-3 refuses only a future recorded_at and
    -- does not bind valid_at) and would let a backdated coordinate hide the
    -- rule or the rider's calculation type (Fable HIGH-2).
    PERFORM 1 FROM public.invoice_line_items l WHERE l.invoice_id = NEW.id FOR SHARE;
    FOR v_line IN SELECT l.* FROM public.invoice_line_items l WHERE l.invoice_id = NEW.id ORDER BY l.line_order, l.id LOOP
        -- (a) the surcharge rules
        PERFORM public.assert_surcharge_line(v_line, now());
        -- (b) base completeness for non-zero tax / percentage lines
        IF v_line.amount <> 0 AND public.line_item_carries_base(v_line, NEW.period_end, now())
           AND NOT EXISTS (SELECT 1 FROM public.invoice_line_item_bases b WHERE b.line_item_id = v_line.id AND b.invoice_id = NEW.id) THEN
            RAISE EXCEPTION USING
                MESSAGE = format('invoice %s cannot be issued: line %s (%s) is a tax / percentage charge with no base composition in invoice_line_item_bases (CI-045 — the base is materialized, not assembled ad hoc)', NEW.invoice_number, v_line.line_order, v_line.description),
                ERRCODE = 'check_violation';
        END IF;
    END LOOP;
    -- (c) every base row: both lines on this invoice, bounds still hold, and the
    --     exclusion as the run knew it
    FOR v_base IN
        SELECT b.id AS base_row_id, b.base_amount, bl.invoice_id AS base_invoice_id, bl.amount AS base_line_amount, bl.rate_item_id,
               bl.description AS base_description, cl.invoice_id AS line_invoice_id, cl.description AS line_description, cl AS citing_line
          FROM public.invoice_line_item_bases b
          JOIN public.invoice_line_items bl ON bl.id = b.base_line_item_id
          JOIN public.invoice_line_items cl ON cl.id = b.line_item_id
         WHERE b.invoice_id = NEW.id
    LOOP
        IF v_base.base_invoice_id <> NEW.id OR v_base.line_invoice_id <> NEW.id THEN
            RAISE EXCEPTION USING
                MESSAGE = format('invoice %s cannot be issued: a base row (%s ← %s) cites a line that is no longer on this invoice (CI-045)', NEW.invoice_number, v_base.line_description, v_base.base_description),
                ERRCODE = 'check_violation';
        END IF;
        -- the citing line must still be one that carries a base (a rider re-classified
        -- to a fixed charge after the row was written would freeze a false composition — Codex MEDIUM-3)
        IF NOT public.line_item_carries_base(v_base.citing_line, NEW.period_end, now()) THEN
            RAISE EXCEPTION USING
                MESSAGE = format('invoice %s cannot be issued: %s carries a base composition but is no longer a tax / percentage charge — delete its base rows (CI-045)', NEW.invoice_number, v_base.line_description),
                ERRCODE = 'check_violation';
        END IF;
        IF sign(v_base.base_amount) <> sign(v_base.base_line_amount) OR abs(v_base.base_amount) > abs(v_base.base_line_amount) THEN
            RAISE EXCEPTION USING
                MESSAGE = format('invoice %s cannot be issued: base row (%s ← %s) takes %s from a line whose amount is now %s (CI-045)', NEW.invoice_number, v_base.line_description, v_base.base_description, v_base.base_amount, v_base.base_line_amount),
                ERRCODE = 'check_violation';
        END IF;
        IF v_base.rate_item_id IS NULL THEN
            CONTINUE;
        END IF;
        SELECT r.* INTO v_rule FROM public.regulatory_surcharge_rule_as_of(v_base.rate_item_id, NEW.invoice_date, now()) r;
        IF FOUND AND v_rule.excluded_from_tax_bases THEN
            RAISE EXCEPTION USING
                MESSAGE = format('invoice %s cannot be issued: %s is a %s surcharge excluded from every tax base but enters the base of %s (CI-038 / CI-045; rule %s)', NEW.invoice_number, v_base.base_description, v_rule.surcharge_kind, v_base.line_description, v_rule.id),
                ERRCODE = 'check_violation';
        END IF;
    END LOOP;
    RETURN NULL;
END;
$$;

COMMENT ON FUNCTION public.enforce_invoice_surcharge_lines_and_bases() IS
    'CI-038 / CI-045 completeness (v5.4.2-07): at commit of any transaction that moves an invoice into an issued status (the A-3 shape; a draft/held void is exempt), on current knowledge — the snapshot must exist (A-3''s gate) but its caller-supplied coordinate is not trusted: every line passes assert_surcharge_line at now(); every non-zero tax / percentage line (line_item_carries_base at (period_end, now())) has at least one invoice_line_item_bases row on this invoice; every base row cites two lines of this invoice, its citing line still carries a base, within bounds, and none of them an excluded surcharge line. Queued after enforce_invoice_has_snapshot (name order) so a missing snapshot is reported by that gate. Locks the lines FOR SHARE.';

DROP TRIGGER IF EXISTS enforce_invoice_surcharge_lines_and_bases ON public.invoices;
CREATE CONSTRAINT TRIGGER enforce_invoice_surcharge_lines_and_bases
    AFTER INSERT OR UPDATE ON public.invoices
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION public.enforce_invoice_surcharge_lines_and_bases();

-- ----------------------------------------------------------------------------
-- 6. Provenance: the rules table joins the citable set (A-3)
-- ----------------------------------------------------------------------------
ALTER TABLE public.invoice_snapshot_references DROP CONSTRAINT IF EXISTS invoice_snapshot_references_source_table_check;
ALTER TABLE public.invoice_snapshot_references ADD CONSTRAINT invoice_snapshot_references_source_table_check CHECK ((source_table = ANY (ARRAY[
    'rate_schedule_versions'::text, 'wna_zone_versions'::text, 'rate_item_versions'::text,
    'rate_schedule_items'::text, 'franchise_fee_rules'::text, 'customer_tax_exemptions'::text, 'wna_monthly_adjustments'::text,
    'regulatory_surcharge_rules'::text])));

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
    -- snapshot's recorded_at, in the same tenant (every citable table carries
    -- recorded_at / recorded_until). The table name is re-checked here
    -- because this BEFORE trigger runs before the CHECK constraint would.
    IF NEW.source_table <> ALL (ARRAY['rate_schedule_versions', 'wna_zone_versions', 'rate_item_versions',
                                      'rate_schedule_items', 'franchise_fee_rules', 'customer_tax_exemptions', 'wna_monthly_adjustments',
                                      'regulatory_surcharge_rules']) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('snapshot reference rejected: %L is not one of the eight bi-temporal reference tables (invoice_snapshot_references_source_table_check)', NEW.source_table),
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
    'A-3 (v5.4.2-04; re-issued v5.4.2-07 to admit regulatory_surcharge_rules — body otherwise unchanged): BEFORE INSERT on invoice_snapshot_references — the snapshot exists in this tenant and its invoice is not issued; source_table is one of the eight bi-temporal tables; the cited row was an open assertion at the snapshot''s recorded_at in the same tenant.';

COMMENT ON TABLE public.invoice_snapshot_references IS
    'Provenance for a calculation snapshot (v5.4.2-04, A-3 → A-1; A-7 adds regulatory_surcharge_rules): each row cites one bi-temporal row the calculation read (source_table ∈ the seven A-1 tables + regulatory_surcharge_rules). The guard proves the citation was visible at the snapshot''s recorded_at (open on the transaction-time axis at that instant, same tenant). "Which rows did this bill use, and were they really what we knew then?" is answerable from this table; the values themselves are in the snapshot sections. Optional per snapshot; same immutability as the snapshot.';

-- ----------------------------------------------------------------------------
-- 7. The compliance report's billed side
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW public.regulatory_surcharge_billing_summary WITH (security_invoker = true) AS
SELECT r.id                    AS rule_id,
       r.tenant_id,
       r.rate_item_id,
       ri.item_code,
       r.surcharge_kind,
       r.cycle_start,
       r.cycle_end,
       r.cap_per_service,
       r.regulatory_reference,
       r.tariff_filing_reference,
       coalesce(b.services_billed, 0)   AS services_billed,
       coalesce(b.lines_billed, 0)      AS lines_billed,
       coalesce(b.total_billed, 0)      AS total_billed,
       b.first_billed_on,
       b.last_billed_on,
       b.unit_rates_billed,
       coalesce(b.pending_in_drafts, 0) AS pending_in_drafts
  FROM public.regulatory_surcharge_rules r
  JOIN public.rate_items ri ON ri.id = r.rate_item_id
  LEFT JOIN LATERAL (
        SELECT count(DISTINCT l.meter_id) FILTER (WHERE public.is_invoice_issued(i.status)) AS services_billed,
               count(l.id)                FILTER (WHERE public.is_invoice_issued(i.status)) AS lines_billed,
               sum(l.amount)              FILTER (WHERE public.is_invoice_issued(i.status)) AS total_billed,
               min(i.invoice_date)        FILTER (WHERE public.is_invoice_issued(i.status)) AS first_billed_on,
               max(i.invoice_date)        FILTER (WHERE public.is_invoice_issued(i.status)) AS last_billed_on,
               array_agg(DISTINCT l.rate) FILTER (WHERE public.is_invoice_issued(i.status) AND l.rate IS NOT NULL) AS unit_rates_billed,
               sum(l.amount)              FILTER (WHERE NOT public.is_invoice_issued(i.status)) AS pending_in_drafts
          FROM public.invoice_line_items l
          JOIN public.invoices i ON i.id = l.invoice_id
         WHERE l.tenant_id = r.tenant_id
           AND l.rate_item_id = r.rate_item_id
           AND i.status <> 'void'
           AND i.invoice_date >= r.cycle_start AND i.invoice_date <= r.cycle_end
  ) b ON true
 WHERE r.recorded_until IS NULL;

COMMENT ON VIEW public.regulatory_surcharge_billing_summary IS
    'CI-038 (v5.4.2-07, A-7): the billed side of the 16 TAC §8.201 compliance report (due 90 days after the last billing cycle carrying the surcharge), per open rule / cycle: services billed (distinct meters), lines, total billed and first / last bill date on issued non-void invoices, the distinct unit rates billed, and the amount still in draft / held invoices. NOT here: the amount paid to RRC and the amount COLLECTED from customers — payments are not allocated per line — both are the application''s / the tenant''s accounting. A report, not an exception list: after a cap correction it shows what was billed under the earlier assertion without flagging it. security_invoker: RLS applies.';

-- ----------------------------------------------------------------------------
-- 8. Pre-patch bills: report, never rewrite
-- ----------------------------------------------------------------------------
DO $$
DECLARE v integer;
BEGIN
    SELECT count(DISTINCT i.id) INTO v
      FROM public.invoices i
      JOIN public.invoice_line_items l ON l.invoice_id = i.id
     WHERE public.is_invoice_issued(i.status) AND i.status <> 'void'
       AND l.amount <> 0 AND l.charge_type = 'tax'
       AND NOT EXISTS (SELECT 1 FROM public.invoice_line_item_bases b WHERE b.line_item_id = l.id);
    IF v > 0 THEN
        RAISE NOTICE 'v5.4.2-07: % issued invoice(s) carry non-zero tax lines with no base composition (pre-patch bills; their lines are frozen and no composition can be written for them — CI-045 holds from this patch forward)', v;
    END IF;
END;
$$;

-- ----------------------------------------------------------------------------
-- 9. ENABLE ALWAYS on every guard this patch created (D-2026-08-20-27)
-- ----------------------------------------------------------------------------
DO $$
DECLARE r record;
BEGIN
    FOR r IN
        SELECT c.relname, t.tgname
        FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public' AND NOT t.tgisinternal AND t.tgenabled <> 'A'
          AND (
                (c.relname = 'regulatory_surcharge_rules' AND t.tgname IN ('a_enforce_bitemporal_assertion', 'b_enforce_regulatory_surcharge_rule', 'enforce_superseded_has_successor', 'no_truncate'))
             OR (c.relname IN ('rate_item_versions', 'rate_schedule_items') AND t.tgname = 'b_enforce_surcharge_rider_not_taxable')
             OR (c.relname = 'invoice_line_item_bases' AND t.tgname IN ('enforce_invoice_line_item_base', 'no_truncate'))
             OR (c.relname = 'invoice_line_items' AND t.tgname = 'z_enforce_surcharge_line')
             OR (c.relname = 'invoices' AND t.tgname = 'enforce_invoice_surcharge_lines_and_bases')
             OR (c.relname IN ('customer_state_events', 'customer_attribute_history') AND t.tgname = 'a_enforce_event_written_by_db')
          )
    LOOP
        EXECUTE format('ALTER TABLE public.%I ENABLE ALWAYS TRIGGER %I', r.relname, r.tgname);
    END LOOP;
END;
$$;

-- ----------------------------------------------------------------------------
-- 10. Cross-references on existing objects
-- ----------------------------------------------------------------------------
COMMENT ON COLUMN public.invoice_line_items.is_taxable IS 'Whether this line enters the taxable base (resolved by the engine from the rider''s is_taxable_default / is_taxable_override, #23 stage 2). Since v5.4.2-07 a line of a rider excluded_from_tax_bases (regulatory_surcharge_rules) must be false; the base each tax / percentage line was actually computed on is materialized in invoice_line_item_bases (CI-045).';
COMMENT ON COLUMN public.invoice_line_items.taxable_amount IS 'The part of this line''s amount that is taxable, when not the whole line. Must be empty / 0 on a line of a rider excluded from tax bases (v5.4.2-07, CI-038).';
COMMENT ON COLUMN public.invoice_line_items.meter_id IS 'The meter (service line) this line bills. Required on a line of a rider capped per service (regulatory_surcharge_rules.cap_per_service, v5.4.2-07): the cap aggregates by (rate item, meter) over the cycle.';
COMMENT ON COLUMN public.franchise_fee_rules.applies_to IS 'Which composition the franchise-fee base uses (total_bill | gross_revenue | base_and_usage | usage_only). Open with Kyle (decision table #26, question 2) how this relates to the per-item is_taxable chain; whichever governs, the base actually used on each bill is written to invoice_line_item_bases (v5.4.2-07) and a PSF / excluded-surcharge line can never be in it (CI-038).';
COMMENT ON COLUMN public.rate_item_versions.is_taxable_default IS 'Default taxability of the rider''s lines (overridable per schedule). A rider with an open regulatory_surcharge_rules row excluded_from_tax_bases can never assert true here (v5.4.2-07). The false DEFAULT is decision table #23''s open question 1 (Kyle): the schema cannot tell "decided false" from "never decided".';
