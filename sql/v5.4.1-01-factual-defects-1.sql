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
--                   depends_on_row_numbers. Source: bulk-data-import-with-
--                   validation.md:82 ("the corpus now has a cycle-guard
--                   theme rather than three incidents ... it is worth one
--                   coordinated recommendation rather than three"); named
--                   in schema-parity-plan as 3L / cluster 60 / bulk-import
--                   OQ3. [DRAFTED BELOW]
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
--              Phase 2's "flag each in a brief line" rule.
--              Item 2.3 has no CI-numbered entry — the finding is sourced
--              from a workflow spec (bulk-data-import-with-validation.md)
--              and a review brief, not from canonical-invariants.md; no
--              re-grade to make. Remaining items' CI entries to be named
--              as each is drafted.
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
--              2.3  Postgres CHECKs can't express a cycle guard (row-local;
--                   a cycle is a graph property) — all three land as
--                   BEFORE INSERT OR UPDATE triggers that REJECT (RAISE
--                   EXCEPTION), not just log. This differs from the -05
--                   reversal-chain-depth event on purpose: that one guards
--                   DEPTH on a structure where depth is meaningful and
--                   bounded by policy (>3 is unusual, not impossible); these
--                   three guard a CYCLE on structures where "depth is
--                   unbounded and a cycle is reachable" per the finding —
--                   i.e. any depth is legitimate, only a cycle is a bug.
--                   landlord_customer_id / parent_order_id are both FK-
--                   backed self-references, so a cycle can only be CREATED
--                   by an UPDATE that rewires an existing row into its own
--                   descendant chain (the FK itself already forces a parent
--                   to exist before a child can reference it, so INSERT-time
--                   can only ever produce a direct self-reference, checked
--                   separately up front). Each walks the ancestor chain,
--                   capped at 50 links as a defensive backstop against an
--                   already-corrupted pre-existing cycle upstream of the
--                   row being changed — NOT a business depth limit; hitting
--                   the cap without finding the row's own id raises rather
--                   than silently allowing an update into an unverifiable
--                   ancestor chain. depends_on_row_numbers is NOT FK-backed
--                   (it's a plain integer[] keyed on row_number, not id), so
--                   unlike the other two, a cycle CAN form purely from
--                   INSERT order — the guard runs a BFS with a visited-set
--                   (cap 10,000 rows, matched to realistic bulk-import file
--                   sizes) rather than a single-parent WHILE walk, since a
--                   row can depend on multiple row numbers at once. Cycle
--                   detection is correct regardless of which of the two
--                   cyclic rows commits first, because the walk reads
--                   whatever has already been written — including earlier
--                   rows in the SAME multi-row INSERT statement, since
--                   Postgres increments the command counter between each
--                   row's BEFORE ROW trigger — so the cycle is always caught
--                   on the second of the two rows to be written, exactly
--                   matching the workflow spec's own suggested approach
--                   ("detect cycles at validation ... the array is fully
--                   known once staging is written").
--                   ADDITIONAL, beyond the three named columns: added
--                   UNIQUE (import_job_id, row_number) on import_staging.
--                   Not itself in the plan's item list, but load-bearing —
--                   the cycle walk looks up "the row for row_number N in
--                   this job" by that pair, and without uniqueness the
--                   lookup is ambiguous and the guard could silently miss
--                   a real cycle. Flagged here per Phase 2's own rule
--                   rather than landed silently.
--                   OUT OF SCOPE, noted not drafted: 3L also flags
--                   `customers_landlord_customer_id_fkey` as referencing
--                   `customers(id)` rather than `(tenant_id, id)` — the
--                   schema's only customer-to-customer link, with no
--                   tenant-scoping on the FK itself. Real defect, but it's
--                   a cross-tenant-leakage finding, not a cycle finding,
--                   and item 2.3 names only the cycle guard. Left as a
--                   candidate for a future item rather than folded in here.
-- Idempotent:  yes so far (constraints DROP IF EXISTS + re-ADD; CREATE OR
--              REPLACE FUNCTION; trigger DROP IF EXISTS + re-CREATE; backfill
--              UPDATE only touches remaining NULLs, so a re-run is a no-op;
--              COMMENT overwrite). Re-verify once all five items + carryover
--              land.
-- Line count:  DRAFT ONLY — not yet mirrored into tu.sql. Items 2.1, 2.2,
--              2.3 drafted; 2.5/2.6 + -06 carryover pending in this same
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

--
-- Item 2.3 — cycle guards on the three genuine hierarchy/dependency-graph
-- self-references (bulk-data-import-with-validation.md:82; "the corpus now
-- has a cycle-guard theme rather than three incidents"). Postgres CHECKs
-- are row-local and cannot express a cycle guard; all three land as
-- triggers that REJECT rather than log.
--

-- 2.3a — customers.landlord_customer_id. FK-backed self-reference
-- (customers_landlord_customer_id_fkey, tu.sql:9351); a cycle can only be
-- CREATED by an UPDATE rewiring an existing customer into its own
-- descendant chain, since the FK already forces a landlord row to exist
-- before it can be pointed to. 50-link cap is a defensive backstop, not a
-- business depth limit — real landlord/sub-let chains stay short, but
-- depth itself is not the defect here, a cycle is.
CREATE OR REPLACE FUNCTION public.check_landlord_customer_cycle() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_depth integer := 0;
    v_cursor uuid := NEW.landlord_customer_id;
BEGIN
    IF NEW.landlord_customer_id IS NULL THEN
        RETURN NEW;
    END IF;
    IF NEW.landlord_customer_id = NEW.id THEN
        RAISE EXCEPTION 'customer % cannot be its own landlord', NEW.id;
    END IF;
    WHILE v_cursor IS NOT NULL LOOP
        v_depth := v_depth + 1;
        IF v_depth > 50 THEN
            RAISE EXCEPTION 'landlord chain for customer % exceeds 50 links without resolving — refusing (either an implausibly long chain or an existing cycle upstream of this update)', NEW.id;
        END IF;
        IF v_cursor = NEW.id THEN
            RAISE EXCEPTION 'landlord_customer_id assignment for customer % would create a cycle', NEW.id;
        END IF;
        SELECT landlord_customer_id INTO v_cursor FROM public.customers WHERE id = v_cursor;
    END LOOP;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS landlord_customer_cycle ON public.customers;
CREATE TRIGGER landlord_customer_cycle BEFORE INSERT OR UPDATE OF landlord_customer_id ON public.customers
    FOR EACH ROW EXECUTE FUNCTION public.check_landlord_customer_cycle();

-- 2.3b — service_orders.parent_order_id. Same FK-backed-self-reference
-- shape as 2.3a (service_orders_parent_order_id_fkey, tu.sql:10511).
CREATE OR REPLACE FUNCTION public.check_service_order_parent_cycle() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_depth integer := 0;
    v_cursor uuid := NEW.parent_order_id;
BEGIN
    IF NEW.parent_order_id IS NULL THEN
        RETURN NEW;
    END IF;
    IF NEW.parent_order_id = NEW.id THEN
        RAISE EXCEPTION 'service_order % cannot be its own parent', NEW.id;
    END IF;
    WHILE v_cursor IS NOT NULL LOOP
        v_depth := v_depth + 1;
        IF v_depth > 50 THEN
            RAISE EXCEPTION 'parent-order chain for service_order % exceeds 50 links without resolving — refusing (either an implausibly long chain or an existing cycle upstream of this update)', NEW.id;
        END IF;
        IF v_cursor = NEW.id THEN
            RAISE EXCEPTION 'parent_order_id assignment for service_order % would create a cycle', NEW.id;
        END IF;
        SELECT parent_order_id INTO v_cursor FROM public.service_orders WHERE id = v_cursor;
    END LOOP;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS service_order_parent_cycle ON public.service_orders;
CREATE TRIGGER service_order_parent_cycle BEFORE INSERT OR UPDATE OF parent_order_id ON public.service_orders
    FOR EACH ROW EXECUTE FUNCTION public.check_service_order_parent_cycle();

-- 2.3c — import_staging.depends_on_row_numbers. NOT FK-backed (plain
-- integer[] keyed on row_number, not id) — a cycle can form purely from
-- INSERT order, so this needs a BFS over a visited-set rather than a
-- single-parent walk, since one row can depend on several row numbers at
-- once. UNIQUE (import_job_id, row_number) is added first: it's load-
-- bearing for the walk's row_number lookup to be unambiguous, and without
-- it the guard could silently miss a real cycle (not itself named in the
-- plan's item list — flagged here per Phase 2's own rule rather than
-- landed silently).
ALTER TABLE public.import_staging DROP CONSTRAINT IF EXISTS import_staging_job_row_number_key;
ALTER TABLE public.import_staging ADD CONSTRAINT import_staging_job_row_number_key UNIQUE (import_job_id, row_number);

CREATE OR REPLACE FUNCTION public.check_import_staging_dependency_cycle() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_visited integer[] := ARRAY[]::integer[];
    v_frontier integer[];
    v_next integer[];
    v_row_number integer;
    v_deps integer[];
BEGIN
    IF NEW.depends_on_row_numbers IS NULL THEN
        RETURN NEW;
    END IF;

    IF NEW.row_number = ANY (NEW.depends_on_row_numbers) THEN
        RAISE EXCEPTION 'import_staging row % (job %) cannot depend on itself', NEW.row_number, NEW.import_job_id;
    END IF;

    v_frontier := NEW.depends_on_row_numbers;
    WHILE array_length(v_frontier, 1) IS NOT NULL AND coalesce(array_length(v_visited, 1), 0) < 10000 LOOP
        v_next := ARRAY[]::integer[];
        FOREACH v_row_number IN ARRAY v_frontier LOOP
            IF v_row_number IS NULL OR v_row_number = ANY (v_visited) THEN
                CONTINUE;
            END IF;
            IF v_row_number = NEW.row_number THEN
                RAISE EXCEPTION 'import_staging dependency cycle detected: row % (job %) transitively depends on itself', NEW.row_number, NEW.import_job_id;
            END IF;
            v_visited := array_append(v_visited, v_row_number);
            SELECT depends_on_row_numbers INTO v_deps
            FROM public.import_staging
            WHERE import_job_id = NEW.import_job_id AND row_number = v_row_number;
            IF v_deps IS NOT NULL THEN
                v_next := v_next || v_deps;
            END IF;
        END LOOP;
        v_frontier := v_next;
    END LOOP;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS import_staging_dependency_cycle ON public.import_staging;
CREATE TRIGGER import_staging_dependency_cycle BEFORE INSERT OR UPDATE OF depends_on_row_numbers ON public.import_staging
    FOR EACH ROW EXECUTE FUNCTION public.check_import_staging_dependency_cycle();
