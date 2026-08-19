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
--              2.2  import_jobs.idempotency_key NOT NULL + generated
--                   default. Source: 3M item 2 (wu6-session-3m-review-
--                   brief.md:50-58, CI-118); derivation formula and the
--                   preview/commit collision fix folded in from item 8
--                   (same brief, :148). [DRAFTED BELOW]
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
--              descriptive text corrected on the GBM side.
--              CI-118 (re-grade, item 2.2) — the 3M brief graded this
--              `structurally-enforced` as defective (a UNIQUE constraint
--              over a nullable column lets an unbounded number of NULL-key
--              rows insert cleanly; family-15's intro overclaims "four"
--              structural guarantees when only three genuinely hold). This
--              patch does NOT just correct the doc to "three" — it lands
--              the brief's own recommended fix (NOT NULL + generated
--              default), which restores the fourth guarantee. Call made
--              this session: re-grade CI-118 forward to genuinely
--              `structurally-enforced` (not backward to `partially-`),
--              and correct family-15's intro to confirm "four" as of
--              v5.4.1-01 rather than demote it to "three" — the plan's
--              phrasing described the PRE-patch defect, not the intended
--              post-patch state. Flagging this reading explicitly per
--              Phase 2's "flag each in a brief line" rule. Remaining
--              items' CI entries to be named as each is drafted.
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
--              2.2  "Generated default" implemented as a BEFORE INSERT
--                   trigger (populate_import_job_idempotency_key), mirroring
--                   the existing populate_reading_calculations idiom
--                   (tu.sql:599) — "only auto-calculate if not already set
--                   by the caller". A true GENERATED ALWAYS column can't be
--                   overridden by an operator-supplied value, which the
--                   column's own COMMENT requires ("operator can supply OR
--                   system auto-derives"); a plain column DEFAULT can't
--                   reference sibling columns (filename/hash/is_dry_run) —
--                   only a trigger satisfies both constraints at once.
--                   Derivation: <source_filename>:<source_file_hash>:
--                   <'preview'|'commit'> keyed off is_dry_run — item 8's
--                   exact recommendation, which also fixes the preview/
--                   commit collision (both currently derive the SAME key
--                   from filename+hash alone, so a commit after its own
--                   preview hits the UNIQUE constraint). Not every import
--                   has a file (api/ai_extracted sources can have NULL
--                   filename+hash): falls back to the job's own id::text,
--                   which is always unique and always present (id's column
--                   DEFAULT fires before BEFORE INSERT triggers run, so
--                   NEW.id is already populated). Pre-existing NULL rows
--                   (none in a fresh deploy) are backfilled to id::text
--                   rather than run through the smart derivation, to avoid
--                   a backfill collision where two old rows already shared
--                   a (filename, hash, is_dry_run) triple that NULL was
--                   silently masking.
-- Idempotent:  yes so far (constraints DROP IF EXISTS + re-ADD; CREATE OR
--              REPLACE FUNCTION; trigger DROP IF EXISTS + re-CREATE; backfill
--              UPDATE only touches remaining NULLs, so a re-run is a no-op;
--              COMMENT overwrite). Re-verify once all five items + carryover
--              land.
-- Line count:  DRAFT ONLY — not yet mirrored into tu.sql. Items 2.1, 2.2
--              drafted; 2.3/2.5/2.6 + -06 carryover pending in this same
--              file before the mirror step.
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

--
-- Item 2.2 — import_jobs.idempotency_key NOT NULL + generated default
-- (CI-118, 3M item 2). UNIQUE (tenant_id, idempotency_key) already exists
-- (tu.sql:5344) but Postgres treats NULLs as distinct, so an unbounded
-- number of NULL-key jobs insert cleanly and CI-118's duplicate-import
-- guarantee held for none of them. Fix moves the derivation into the
-- column: a BEFORE INSERT trigger fills the key only when the caller
-- didn't supply one, then NOT NULL makes the fallback unconditional.
--
CREATE OR REPLACE FUNCTION public.populate_import_job_idempotency_key() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Only auto-derive if not already set by the caller (operator-supplied
    -- keys pass through untouched).
    IF NEW.idempotency_key IS NULL THEN
        IF NEW.source_filename IS NOT NULL AND NEW.source_file_hash IS NOT NULL THEN
            -- <filename>:<hash>:<'preview'|'commit'> — 3M item 8's derivation.
            -- Keying on is_dry_run also fixes the preview/commit collision:
            -- previously both derived the same key from filename+hash alone,
            -- so committing after its own preview hit the UNIQUE constraint.
            NEW.idempotency_key := NEW.source_filename || ':' || NEW.source_file_hash || ':' ||
                (CASE WHEN NEW.is_dry_run THEN 'preview' ELSE 'commit' END);
        ELSE
            -- No file to derive from (api / ai_extracted sources can have
            -- NULL filename+hash). Fall back to the job's own id — always
            -- present (column DEFAULT fires before this BEFORE INSERT
            -- trigger runs) and always unique.
            NEW.idempotency_key := NEW.id::text;
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_populate_import_job_idempotency_key ON public.import_jobs;
CREATE TRIGGER trg_populate_import_job_idempotency_key BEFORE INSERT ON public.import_jobs
    FOR EACH ROW EXECUTE FUNCTION public.populate_import_job_idempotency_key();

-- Backfill pre-existing NULLs to id::text (not the smart derivation — two
-- old rows could already share a (filename, hash, is_dry_run) triple that
-- NULL was silently masking; id::text can never collide). No-op on a fresh
-- deploy (0 rows); re-running touches only rows still NULL.
UPDATE public.import_jobs SET idempotency_key = id::text WHERE idempotency_key IS NULL;

ALTER TABLE public.import_jobs ALTER COLUMN idempotency_key SET NOT NULL;

COMMENT ON COLUMN public.import_jobs.idempotency_key IS
    'Prevents double-import of the same file. Operator can supply OR system auto-derives via trg_populate_import_job_idempotency_key: <source_filename>:<source_file_hash>:<preview|commit> when a file is present, else the job''s own id. NOT NULL as of v5.4.1-01 (CI-118) — UNIQUE (tenant_id, idempotency_key) previously let an unbounded number of NULL-key jobs bypass the duplicate-import guarantee entirely.';
