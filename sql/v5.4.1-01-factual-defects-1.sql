-- ============================================================================
-- PATCH v5.4.1-01 — Factual-defect hardening, part 1
--                    (schema-parity-plan Phase 2, items 2.1 / 2.2 / 2.3 / 2.5
--                    / 2.6 — plus the two-reviewer v5.4.0-06 carryover)
-- ============================================================================
-- Authority:   gas-billing-memory/application/schema-parity-plan.md Phase 2 —
--              "factual-defect hardening (schema contradicts itself or a
--              proven invariant; low-controversy, but flag each in a brief
--              line rather than land silently)". Not a Kyle ruling set:
--              these are review-brief findings Ryan is authorized to draft
--              directly, one flagged line per item below.
--              Item 2.4 (tenant_configuration_history + date-parameterised
--              get_partial_period_policy()) is its OWN patch, v5.4.1-02 — it
--              adds a table and changes a function signature, unlike the
--              five narrower items landing here. Patch-split decision made
--              2026-08-19 (this session), per the plan's own candidate split.
--
--              2.1  service_orders CHECK coverage gap. Source: 3M item 7
--                   (application/configurable-rules/wu6-session-3m-review-
--                   brief.md:132-138); corroborated independently in
--                   decision-tables/service-order-type-routing.md rules 4-6
--                   and wiki-ingestion-pending.md item 7. [DRAFTED BELOW]
--              2.2  import_jobs.idempotency_key NOT NULL + default
--                   (CI-118, 3M item 2). [PENDING]
--              2.3  cycle guards: customers.landlord_customer_id,
--                   service_orders.parent_order_id, import_staging.
--                   depends_on_row_numbers (3L, cluster 60, bulk-import
--                   OQ3). [PENDING]
--              2.5  account_ledger reversal lineage FK + reason (re-grade
--                   finding, 2026-08-13; CI-017/CI-018). [PENDING]
--              2.6  meter_readings service-point premise (CI-027 re-grade
--                   finding). [PENDING]
--              Plus: positivity CHECK on pga_monthly_reconciliations
--              threshold columns (consensus defect, two independent -06
--              reviewers) + non-negativity on actual_gas_cost /
--              pga_recovered_revenue. [PENDING]
--
-- CI entries:  CI-122 (re-check only, item 2.1) — its enforcement-status
--              text currently claims the service_orders_check CHECK family
--              covers `final_read` ("order_type CHECK enum ... includes
--              new_connect | transfer | final_read | ..."); that claim was
--              WRONG before this patch (service_orders_check only covers
--              new_connect/reconnect/disconnect/transfer) and becomes true
--              only once service_orders_final_read_referents_check lands.
--              Status token unchanged (partially-structurally-enforced);
--              descriptive text corrected on the GBM side. Remaining items'
--              CI entries to be named as each is drafted.
-- Drafting decisions:
--              2.1  Bind `final_read` to customer_id + location_id +
--                   meter_id (all three — it closes an occupancy AND
--                   produces the final bill off a specific meter, CI-124).
--                   Bind `tamper_response` + `damage_repair` to location_id
--                   only (both carry money — tamper fronts a CI-008
--                   backbilling case, damage triggers cost recovery — but
--                   neither names a meter or customer at intake time).
--                   `customer_complaint`, `adjustment`, `other` are left
--                   DELIBERATELY unconstrained per the review brief's own
--                   recommendation, and that is now stated in a
--                   COMMENT ON CONSTRAINT rather than left implicit — the
--                   brief's exact ask ("saying they are deliberate").
--                   Two new named constraints (existing service_orders_check/
--                   check1/check2 are anonymous pg_dump-style names from the
--                   original dump; new ones get descriptive names per this
--                   project's v5.4.0-02/-03/-05 convention).
-- Idempotent:  yes so far (constraints DROP IF EXISTS + re-ADD; COMMENT
--              overwrite). Re-verify once all five items + carryover land.
-- Line count:  DRAFT ONLY — not yet mirrored into tu.sql. Item 2.1 only;
--              2.2/2.3/2.5/2.6 + -06 carryover pending in this same file
--              before the mirror step.
-- ============================================================================

--
-- Item 2.1 — service_orders CHECK coverage gap (3M item 7). Three existing
-- conditional CHECKs (service_orders_check/check1/check2, tu.sql:4520-4522)
-- partition sixteen of the twenty-two order_type values by required
-- referent; six were left uncovered. For customer_complaint/adjustment/
-- other that's correct (a complaint can arrive before the account is
-- identified). For final_read/tamper_response/damage_repair it is not: a
-- final_read order could insert with customer, location, AND meter all
-- NULL — an instruction to take a final read of nothing, at nowhere, for
-- nobody — while inspection, which has no billing consequence at all, is
-- structurally required to name a location.
--
ALTER TABLE public.service_orders DROP CONSTRAINT IF EXISTS service_orders_final_read_referents_check;
ALTER TABLE public.service_orders ADD CONSTRAINT service_orders_final_read_referents_check
    CHECK (((order_type <> 'final_read'::text) OR ((customer_id IS NOT NULL) AND (location_id IS NOT NULL) AND (meter_id IS NOT NULL))));

COMMENT ON CONSTRAINT service_orders_final_read_referents_check ON public.service_orders IS
    'A final_read order closes an occupancy and produces the final bill (CI-124) — it cannot be filed against nobody, at nowhere, off no meter. Closes the gap where final_read sat uncovered between the meter-type CHECK (service_orders_check1) and the premise-type CHECK (service_orders_check2). schema-parity-plan Phase 2 item 2.1, 3M item 7 (v5.4.1-01).';

ALTER TABLE public.service_orders DROP CONSTRAINT IF EXISTS service_orders_incident_location_check;
ALTER TABLE public.service_orders ADD CONSTRAINT service_orders_incident_location_check
    CHECK (((order_type <> ALL (ARRAY['tamper_response'::text, 'damage_repair'::text])) OR (location_id IS NOT NULL)));

COMMENT ON CONSTRAINT service_orders_incident_location_check ON public.service_orders IS
    'tamper_response fronts a backbilling case (CI-008, capped and regulator-visible) and damage_repair triggers cost recovery — both need a premise at intake. customer_complaint, adjustment, and other are DELIBERATELY left unconstrained: a complaint can arrive before the account is identified, and forcing a location there would misrepresent intake reality as billing structure. schema-parity-plan Phase 2 item 2.1, 3M item 7 (v5.4.1-01).';
