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
--              2.5  account_ledger reversal lineage FK + reason. Source:
--                   2026-08-13 re-grade finding (canonical-invariants.md:
--                   340, 355; CI-017/CI-018). [DRAFTED BELOW]
--              2.6  meter_readings service-point premise (CI-027 re-grade
--                   finding, canonical-invariants.md:500). Lands BOTH
--                   halves the plan offered as either/or: an EXCLUDE on
--                   meter_deployments (the schema's first) AND a
--                   snapshotted meter_readings.location_id. [DRAFTED BELOW]
--              Plus: positivity CHECK on pga_monthly_reconciliations
--              threshold columns (consensus defect, two independent -06
--              reviewers) + non-negativity on actual_gas_cost /
--              pga_recovered_revenue. [DRAFTED BELOW] No CI entry — -06's
--              own CI grades are unchanged; this tightens a snapshot column
--              to match the settings row it copies from.
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
--              CI-118 (re-check, item 2.2 — REVISED after independent
--              review) — the 3M brief graded this `structurally-enforced`
--              as defective (a UNIQUE constraint over a nullable column
--              lets an unbounded number of NULL-key rows insert cleanly;
--              family-15's intro overclaims "four" structural guarantees
--              when only three genuinely hold). This patch's first draft
--              argued the NOT NULL + trigger fix restored the fourth
--              guarantee outright and re-graded CI-118 forward to
--              unqualified `structurally-enforced`. Two independent
--              review passes (Fable, Codex — 2026-08-19) both found and
--              live-reproduced the same hole: the id-fallback only
--              engages when source_filename/source_file_hash are BOTH
--              NULL, but nothing requires a csv/excel/pdf/legacy_export
--              import to populate them — import_jobs_source_type_check
--              constrains only the enum value, not correlated columns. Two
--              file-less (or hash-less) imports of the SAME logical file
--              each get a distinct id-derived key and insert cleanly, no
--              collision, no duplicate-detection — for exactly the source
--              types CI-118's "duplicate imports structurally impossible"
--              statement is supposed to cover. REVISED call: CI-118 stays
--              at `partially-structurally-enforced`, NOT re-graded upward
--              — the guarantee holds only when the caller supplies
--              filename+hash (or its own key), which is exactly the
--              "when set" hedge CI-117 already carries and CI-118's
--              Statement does not. The NOT NULL fix genuinely closes the
--              NULL-key hole (verified: two rows with identical
--              filename+hash+is_dry_run now correctly collide); it does
--              NOT make duplicate-import detection unconditional. Family-
--              15's intro correction (four vs. three) is a GBM-side call
--              to make alongside this — not resolved in this SQL patch.
--              Item 2.3 has no CI-numbered entry — the finding is sourced
--              from a workflow spec (bulk-data-import-with-validation.md)
--              and a review brief, not from canonical-invariants.md; no
--              re-grade to make.
--              CI-017 / CI-018 (re-check, item 2.5) — both were already
--              re-graded `structurally-enforced` → `partially-structurally-
--              enforced` on 2026-08-13 specifically BECAUSE account_ledger
--              had no reversal FK/reason. This patch closes that gap, but
--              does NOT re-grade either back to `structurally-enforced`:
--              both columns land nullable (matching the existing invoice/
--              payment lineage columns, which the same 2026-08-13 finding
--              already conceded are "representable, not enforced" — every
--              lineage column in the schema is optional, not required), so
--              the guarantee remains representable rather than guaranteed.
--              Status token unchanged at `partially-structurally-enforced`
--              for both; descriptive text corrected on the GBM side to
--              note the columns now exist. This is the one item this
--              session where landing the fix does NOT restore the stronger
--              grade — worth flagging precisely because it looks like the
--              CI-118 case (item 2.2) and isn't.
--              CI-027 (re-check, item 2.6) — both defects the 2026-08-13
--              re-grade named are addressed: overlapping deployments are
--              now structurally impossible (so the deployment-at-read-date
--              reconstruction is single-valued), and the premise IS now
--              recorded on the read. Status token stays
--              `partially-structurally-enforced` — location_id is nullable
--              and default-populated, not required, so a read can still
--              exist with no premise (meter rows with no location can't,
--              meters.location_id is NOT NULL, but the column itself does
--              not forbid NULL). Same discipline as 2.2/2.5: descriptive
--              text corrected on the GBM side ("zero EXCLUDE constraints"
--              and "no location or service-point column" are both false
--              once this lands), token unchanged.
--              CI-032 (re-check only, item 2.6) — enforcement text should
--              gain the EXCLUDE as a named structural guarantee of the
--              "one deployment per meter per date" property its
--              "reconstructable in both directions" claim silently relied
--              on. Token unchanged (structurally-enforced).
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
--                   POST-REVIEW FIXES (two independent review passes,
--                   Fable + Codex, 2026-08-19): (1) the trigger originally
--                   fired only on UPDATE OF depends_on_row_numbers — since
--                   the graph's edges are keyed on row_number, which is
--                   NOT FK-protected, an UPDATE moving a row's OWN
--                   row_number (or relocating it into another import_job_id)
--                   could complete a cycle the guard never re-checked.
--                   Fable reproduced this live. Fixed: trigger now also
--                   fires on UPDATE OF row_number, import_job_id. (2) the
--                   BFS's 10,000-node visited-cap silently returned NEW
--                   rather than raising, contradicting this same header's
--                   stated philosophy for the other two guards ("raises
--                   rather than silently allowing"). Fixed: now raises.
--                   KNOWN LIMITATION, not fixed, documented instead
--                   (Fable finding): all three guards read via plain MVCC
--                   SELECTs with no locking. Two concurrent transactions
--                   each completing "their half" of a cycle (e.g. txn1 sets
--                   A.landlord=B while txn2 concurrently sets B.landlord=A)
--                   can both commit under READ COMMITTED, since neither
--                   sees the other's uncommitted half. The "cycle always
--                   caught on the second row written" property holds only
--                   within one session/transaction, not across concurrent
--                   ones. Not fixed in this patch — closing it needs
--                   per-chain advisory locking or SERIALIZABLE, which is
--                   more machinery than a Phase 2 "factual-defect
--                   hardening" item should carry; flagged per Phase 2's
--                   own rule as a candidate for a future item rather than
--                   silently left undocumented.
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
--              2.5  Two new nullable columns on account_ledger:
--                   reverses_ledger_entry_id (self-referencing FK) and
--                   reversal_reason (text). Deliberately NOT paired by a
--                   CHECK requiring both-or-neither: the invoice/payment
--                   lineage columns this mirrors (replaces_invoice_id,
--                   void_reason_code, etc.) are independent columns, not a
--                   paired unit, and the 2026-08-13 finding itself already
--                   concedes every lineage column in the schema is
--                   "representable, not enforced" — inventing a stricter
--                   pairing rule here than the pattern it mirrors would be
--                   a new invariant, not a factual-defect fix. Self-
--                   reference forbidden by a plain CHECK (no trigger
--                   needed — unlike 2.3, CI-018 explicitly wants
--                   reversal-of-a-reversal and unbounded chain depth left
--                   UNCONSTRAINED: "an N-deep chain is a queryable
--                   structure, not an error condition." No depth-
--                   monitoring event added either (unlike -05's
--                   reversal_chain_depth_exceeded on invoices) — that was
--                   a specific D1-3 ruling for invoice reversals; nothing
--                   analogous has been ruled for the ledger, so adding one
--                   here would be inventing a threshold nobody asked for.
--                   Naming: reverses_ledger_entry_id, not reversal_of_id
--                   or similar — matches the exact grep the 2026-08-13
--                   finding ran ("reverses_|reversal_of") and the
--                   reverses_/replaces_/refunds_ prefix-on-the-successor-
--                   row convention already used by
--                   invoices.replaces_invoice_id and
--                   payments.refunds_payment_id.
--                   void_invoice() (tu.sql:1126) is the ONE place in the
--                   schema that posts a void_reversal ledger row, so it is
--                   updated to populate both new columns rather than
--                   leaving them permanently unused by the only caller
--                   that exists: reversal_reason is populated directly
--                   from p_void_reason_code/p_void_reason_notes (already
--                   validated, already required); reverses_ledger_entry_id
--                   is populated by a best-effort lookup for a prior
--                   'charge' ledger row referencing this invoice
--                   (reference_type='invoice', reference_id=p_invoice_id)
--                   — NULL if none is found, which will be the common case
--                   today since no billing-run/charge-posting code exists
--                   anywhere in this schema-only project (per the parity
--                   plan's own framing) to have posted that row in the
--                   first place. This is exactly the "representable, not
--                   enforced" character the finding already named, made
--                   concrete rather than left aspirational.
--                   NOTED, same class as item 2.3's out-of-scope call
--                   (independent review, Fable pass): account_ledger_
--                   reverses_ledger_entry_id_fkey references (id), not
--                   (tenant_id, id) — cross-tenant lineage is representable
--                   by a direct row insert bypassing the FK's tenant
--                   scoping, same shape as customers_landlord_customer_id_
--                   fkey. void_invoice() itself is tenant-safe (its own
--                   lookup is tenant_id-scoped, Step 1.1's cross-tenant
--                   check is intact), so this is a latent gap in the
--                   column's structural guarantee, not a live hole in the
--                   one caller that populates it today. Consistent with
--                   2.3's landlord-FK call: noted, not drafted here.
--              2.6  EXCLUDE over (meter_id WITH =, daterange(install_date,
--                   removal_date, '[)') WITH &&). HALF-OPEN on purpose:
--                   sync_meter_deployments() closes a deployment with
--                   COALESCE(NEW.removal_date, CURRENT_DATE) and reopens
--                   with COALESCE(NEW.start_date, CURRENT_DATE), so a
--                   same-day Pattern A remove+reinstall yields
--                   [..,D) + [D,..) — allowed. '[]' would have broken that
--                   path. Live-tested: the inactive->active round trip
--                   through the sync trigger passes.
--                   BEHAVIOR CHANGE, flagged: a Pattern A reactivation that
--                   leaves meters.start_date stale (earlier than the prior
--                   deployment's removal_date) now FAILS inside
--                   sync_meter_deployments() at the EXCLUDE, where before
--                   it silently wrote an overlapping deployment. That is
--                   the correct rejection (it is literally the ambiguity
--                   CI-027 names) but the application layer must set
--                   start_date on reactivation. Not patched in the sync
--                   trigger here (changing its COALESCE to a GREATEST
--                   would be guessing operator intent) — recorded for the
--                   A-series / Kyle brief list.
--                   Companion CHECK removal_date >= install_date exists
--                   only to give a readable error instead of daterange's
--                   bound-order error; it is not a new rule (daterange
--                   would reject the same row).
--                   meter_readings.location_id is nullable, FK to
--                   service_locations(id) (not tenant-scoped — same shape
--                   as the landlord and reverses_ledger_entry FKs, same
--                   "noted, not drafted" call). Populated BEFORE INSERT
--                   only: deployment covering reading_date, else
--                   meters.location_id (reads on never-deployed meters are
--                   allowed rather than rejected). NOT re-derived on UPDATE
--                   — the column is a snapshot and a later meter move must
--                   not reattribute it; the cost is that a reading_date
--                   correction does not re-sync location_id automatically
--                   (flagged, representable-not-enforced, like 2.5).
--                   Backfill: two UPDATEs (deployment-derived, then
--                   meters fallback), NULL-only, no-op on a fresh deploy.
--                   Also adds idx_readings_location_date partial index —
--                   the premise-side query ("all reads at this premise")
--                   is the whole point of recording the column.
--                   Requires CREATE EXTENSION btree_gist (contrib; present
--                   in the postgres:16 image; supported on RDS). Added in
--                   the patch body, NOT in tu.sql's extension preamble
--                   (tu.sql:47-49) — append-only rule; mirror as an append.
-- Idempotent:  yes so far (constraints DROP IF EXISTS + re-ADD; CREATE OR
--              REPLACE FUNCTION; trigger DROP IF EXISTS + re-CREATE; backfill
--              UPDATE only touches remaining NULLs, so a re-run is a no-op;
--              COMMENT overwrite; CREATE EXTENSION / ADD COLUMN / CREATE
--              INDEX all IF NOT EXISTS). Re-applied twice after 2.6 landed,
--              zero errors; again after the carryover, zero errors.
-- Line count:  DRAFT ONLY — not yet mirrored into tu.sql. Items 2.1, 2.2,
--              2.3, 2.5, 2.6 + -06 carryover ALL DRAFTED and live-tested.
--              Next: mirror into tu.sql (pure append), fresh rebuild, full
--              re-test, CI re-grades, DEPLOY-VERIFICATION, GBM Section AL.
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
    WHILE array_length(v_frontier, 1) IS NOT NULL LOOP
        IF array_length(v_visited, 1) >= 10000 THEN
            RAISE EXCEPTION 'import_staging dependency walk for row % (job %) exceeded 10,000 visited rows without resolving — refusing (either an implausibly large dependency graph or an existing cycle this insert/update did not itself create)', NEW.row_number, NEW.import_job_id;
        END IF;
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

-- Fires on UPDATE OF row_number and import_job_id too, not just
-- depends_on_row_numbers: the graph's edges are keyed on row_number, which
-- is NOT FK-protected and freely updatable — an UPDATE that moves a row's
-- own row_number (or relocates it into another job) can complete a cycle
-- the guard would otherwise never re-check. Found by independent review
-- (Fable pass, 2026-08-19): insert row 1 deps {2}, row 3 deps {1} (no
-- cycle visible yet), then UPDATE row 3's row_number to 2 — completes a
-- 1->2->1 cycle that a depends_on_row_numbers-only trigger never sees.
DROP TRIGGER IF EXISTS import_staging_dependency_cycle ON public.import_staging;
CREATE TRIGGER import_staging_dependency_cycle BEFORE INSERT OR UPDATE OF depends_on_row_numbers, row_number, import_job_id ON public.import_staging
    FOR EACH ROW EXECUTE FUNCTION public.check_import_staging_dependency_cycle();

--
-- Item 2.5 — account_ledger reversal lineage FK + reason (2026-08-13
-- re-grade finding; CI-017/CI-018). invoices and payments each have an
-- explicit lineage FK + reason on the REVERSING row pointing back to its
-- predecessor (replaces_invoice_id/void_reason_code,
-- refunds_payment_id/nsf_reason); account_ledger had neither — a ledger
-- reversal was distinguishable only by transaction_type = 'void_reversal',
-- with no link to the entry it offsets and no recorded reason.
--
ALTER TABLE public.account_ledger ADD COLUMN IF NOT EXISTS reverses_ledger_entry_id uuid;
ALTER TABLE public.account_ledger ADD COLUMN IF NOT EXISTS reversal_reason text;

ALTER TABLE public.account_ledger DROP CONSTRAINT IF EXISTS account_ledger_reverses_ledger_entry_id_fkey;
ALTER TABLE public.account_ledger ADD CONSTRAINT account_ledger_reverses_ledger_entry_id_fkey
    FOREIGN KEY (reverses_ledger_entry_id) REFERENCES public.account_ledger(id);

ALTER TABLE public.account_ledger DROP CONSTRAINT IF EXISTS account_ledger_reversal_not_self_check;
ALTER TABLE public.account_ledger ADD CONSTRAINT account_ledger_reversal_not_self_check
    CHECK ((reverses_ledger_entry_id IS DISTINCT FROM id));

COMMENT ON COLUMN public.account_ledger.reverses_ledger_entry_id IS
    'Lineage FK to the account_ledger row this entry reverses/offsets — the ledger''s analogue of invoices.replaces_invoice_id and payments.refunds_payment_id (CI-017). Nullable: most ledger rows are not reversals, and per the same "representable, not enforced" pattern as the invoice/payment lineage columns, a reversal row is not REQUIRED to populate it. Populated by void_invoice() on a best-effort basis (v5.4.1-01) — NULL when no prior charge-type ledger row referencing the voided invoice can be found. Unbounded chain depth and reversal-of-a-reversal are both intentionally unconstrained (CI-018): a correction to a correction is a normal operation, not an error condition.';

COMMENT ON COLUMN public.account_ledger.reversal_reason IS
    'Free-text reason this entry reverses/offsets reverses_ledger_entry_id (CI-017 — "each link records ... the reason for the offset"). Independent of reverses_ledger_entry_id (not paired by a CHECK): a reversal''s reason is known even when the specific predecessor ledger row cannot be resolved. Populated by void_invoice() from the same void_reason_code/void_reason_notes already required for the voided invoice (v5.4.1-01).';

--
-- void_invoice() — updated (v5.4.1-01) to populate the two new columns.
-- Only change from the v5.2.1 body: a best-effort lookup for the original
-- charge-type ledger row before Step 4, and that lookup's result plus the
-- void reason threaded into the account_ledger INSERT and the return
-- payload. Everything else is unchanged.
--
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

COMMENT ON FUNCTION public.void_invoice(p_invoice_id uuid, p_voided_by uuid, p_void_reason_code text, p_void_reason_notes text, p_rebill_expected boolean) IS 'Atomically voids a posted invoice. v5.2.1 corrections: (a) Single canonical signature — old 4-param version dropped; (b) Explicit cross-tenant check defends against RLS bypass; (c) Duplicate-warning check filters by invoice_type to avoid false negatives on multi-service locations. v5.4.1-01 addition (CI-017): populates the new account_ledger.reverses_ledger_entry_id (best-effort lookup of the prior charge-type ledger row for this invoice, NULL if none exists) and reversal_reason (from void_reason_code/void_reason_notes) on the posted void_reversal row. Steps: validate invoice + tenant, voidability + reason validation, duplicate-warning check, arm trigger carve-out, release locked reads, dispose adhoc charges, look up original charge ledger entry, post void_reversal ledger entry with reversal lineage, stamp void metadata, log voided event to invoice_events (tenant_id synced by trigger), return JSONB payload.';

--
-- Item 2.6 — meter_readings service-point premise (CI-027 re-grade finding,
-- canonical-invariants.md:500). Two defects named in the 2026-08-13 re-grade,
-- both addressed here because fixing either alone leaves the other standing:
--   (a) "tu.sql contains zero EXCLUDE constraints, and meter_deployments'
--       only uniqueness is (meter_id, deployment_number), so nothing prevents
--       temporally overlapping deployments. Where two overlap, the read's
--       premise is ambiguous."  -> 2.6a, the schema's first EXCLUDE.
--   (b) "meter_readings carries no location or service-point column — the
--       premise is not *recorded* on the read, only *reconstructable*."
--       -> 2.6b, a snapshotted location_id on the read.
-- The schema-parity-plan phrased 2.6 as "either ... or"; this patch lands
-- both and flags the widening here rather than silently. Rationale: (a)
-- without (b) still leaves the premise unrecorded (the CI's own statement
-- is "every meter read RECORDS ... the service point"); (b) without (a)
-- records a premise derived from an ambiguous history.
--

-- 2.6a — no two deployments of one meter may overlap in time. btree_gist
-- is required for the scalar `meter_id WITH =` operator in a GiST exclusion
-- index; it ships with contrib on vanilla Postgres and is supported on RDS.
-- Range is HALF-OPEN [install_date, removal_date): a removal on day D and
-- a reinstall on day D do not overlap, which is exactly what
-- sync_meter_deployments() produces for a same-day Pattern A reactivation
-- (close with CURRENT_DATE, reopen with CURRENT_DATE). An open deployment
-- (removal_date IS NULL) is unbounded above, so a second open deployment
-- of the same meter is always rejected. The companion CHECK gives a
-- readable error for removal_date < install_date instead of daterange's
-- "range lower bound must be less than or equal to range upper bound".
CREATE EXTENSION IF NOT EXISTS btree_gist;

ALTER TABLE public.meter_deployments DROP CONSTRAINT IF EXISTS meter_deployments_removal_after_install_check;
ALTER TABLE public.meter_deployments ADD CONSTRAINT meter_deployments_removal_after_install_check
    CHECK ((removal_date IS NULL) OR (removal_date >= install_date));

ALTER TABLE public.meter_deployments DROP CONSTRAINT IF EXISTS meter_deployments_no_overlap_excl;
ALTER TABLE public.meter_deployments ADD CONSTRAINT meter_deployments_no_overlap_excl
    EXCLUDE USING gist (
        meter_id WITH =,
        daterange(install_date, removal_date, '[)') WITH &&
    );

COMMENT ON CONSTRAINT meter_deployments_no_overlap_excl ON public.meter_deployments IS
    'A physical meter is installed at one premise at a time: no two deployment rows of the same meter may overlap in [install_date, removal_date). Half-open so a same-day removal+reinstall (what sync_meter_deployments produces) is allowed; an open deployment (removal_date NULL) blocks any later or concurrent deployment until closed. The schema''s first EXCLUDE constraint. Makes "which premise was this meter at on date D" a single-row answer, which is what meter_readings.location_id snapshots. CI-027 / CI-032, schema-parity-plan Phase 2 item 2.6 (v5.4.1-01).';

-- 2.6b — record the premise on the read. Nullable, FK to service_locations,
-- filled by a BEFORE INSERT trigger when the caller doesn't supply it:
-- the deployment in effect on reading_date (now unambiguous per 2.6a),
-- else the meter's current location_id (covers reads on meters that never
-- got a deployment row — e.g. inserted with status <> 'active' — rather
-- than rejecting the read). INSERT-only on purpose: the column is a
-- snapshot of where the meter WAS, and a later meter move must not
-- re-derive it (that is the CI's whole point). If reading_date itself is
-- corrected the operator corrects location_id with it; the
-- meter_readings.reading_date <-> location_id coupling is not re-enforced
-- on UPDATE here (flagged, not drafted — same representable-not-enforced
-- character as every other lineage column, see item 2.5).
ALTER TABLE public.meter_readings ADD COLUMN IF NOT EXISTS location_id uuid;

ALTER TABLE public.meter_readings DROP CONSTRAINT IF EXISTS meter_readings_location_id_fkey;
ALTER TABLE public.meter_readings ADD CONSTRAINT meter_readings_location_id_fkey
    FOREIGN KEY (location_id) REFERENCES public.service_locations(id);

CREATE INDEX IF NOT EXISTS idx_readings_location_date ON public.meter_readings USING btree (location_id, reading_date DESC) WHERE (location_id IS NOT NULL);

CREATE OR REPLACE FUNCTION public.populate_reading_location() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NEW.location_id IS NOT NULL THEN
        RETURN NEW;   -- caller-supplied premise passes through untouched
    END IF;

    -- Deployment in effect on the read date (2.6a guarantees at most one).
    SELECT d.location_id INTO NEW.location_id
    FROM public.meter_deployments d
    WHERE d.meter_id = NEW.meter_id
      AND daterange(d.install_date, d.removal_date, '[)') @> NEW.reading_date
    LIMIT 1;

    -- No deployment row covers the date: fall back to the meter's current
    -- premise rather than rejecting the read. Leaves NULL only if the meter
    -- row itself is missing (the meter_id FK will reject that anyway).
    IF NEW.location_id IS NULL THEN
        SELECT m.location_id INTO NEW.location_id
        FROM public.meters m
        WHERE m.id = NEW.meter_id;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_populate_reading_location ON public.meter_readings;
CREATE TRIGGER trg_populate_reading_location BEFORE INSERT ON public.meter_readings
    FOR EACH ROW EXECUTE FUNCTION public.populate_reading_location();

-- Backfill pre-existing reads from deployment history, then meters.
-- No-op on a fresh deploy; re-running touches only rows still NULL.
UPDATE public.meter_readings r
SET location_id = d.location_id
FROM public.meter_deployments d
WHERE r.location_id IS NULL
  AND d.meter_id = r.meter_id
  AND daterange(d.install_date, d.removal_date, '[)') @> r.reading_date;

UPDATE public.meter_readings r
SET location_id = m.location_id
FROM public.meters m
WHERE r.location_id IS NULL
  AND m.id = r.meter_id;

COMMENT ON COLUMN public.meter_readings.location_id IS
    'Service point (premise) the meter was installed at WHEN THIS READ WAS TAKEN — a snapshot, not a live join. Populated on INSERT by trg_populate_reading_location from the meter_deployments row covering reading_date (unambiguous per meter_deployments_no_overlap_excl), else meters.location_id; caller-supplied values pass through. Deliberately not re-derived on UPDATE: a later meter move must not reattribute historical consumption. Nullable (representable, not required). CI-027, schema-parity-plan Phase 2 item 2.6 (v5.4.1-01).';

--
-- v5.4.0-06 review carryover — pga_monthly_reconciliations positivity /
-- non-negativity. Both independent -06 reviewers (Fable + Codex) flagged the
-- same defect: pga_monitoring_settings enforces low_alert_threshold_pct > 0
-- (pga_monitoring_settings_low_positive_check) but the per-row snapshot of
-- those thresholds on pga_monthly_reconciliations only enforces band ORDER
-- (medium > low), so a row could snapshot low = -5, medium = 0 and the
-- band_consistent CHECK's ratio comparison would classify every month as
-- 'medium'. Mirror the settings-side rule onto the snapshot. Also: a month's
-- actual_gas_cost and pga_recovered_revenue are gross dollar amounts
-- (monthly_variance is the signed quantity) — neither can be negative.
-- Consistent with the existing trailing_nonnegative_check on the same table.
-- Not touched: monthly_variance, deferred_balance_after (signed by design,
-- v5.4.0-06 header).
--
ALTER TABLE public.pga_monthly_reconciliations DROP CONSTRAINT IF EXISTS pga_monthly_reconciliations_low_positive_check;
ALTER TABLE public.pga_monthly_reconciliations ADD CONSTRAINT pga_monthly_reconciliations_low_positive_check
    CHECK ((low_threshold_pct_applied > (0)::numeric));

ALTER TABLE public.pga_monthly_reconciliations DROP CONSTRAINT IF EXISTS pga_monthly_reconciliations_gas_cost_nonnegative_check;
ALTER TABLE public.pga_monthly_reconciliations ADD CONSTRAINT pga_monthly_reconciliations_gas_cost_nonnegative_check
    CHECK ((actual_gas_cost >= (0)::numeric));

ALTER TABLE public.pga_monthly_reconciliations DROP CONSTRAINT IF EXISTS pga_monthly_reconciliations_recovered_nonnegative_check;
ALTER TABLE public.pga_monthly_reconciliations ADD CONSTRAINT pga_monthly_reconciliations_recovered_nonnegative_check
    CHECK ((pga_recovered_revenue >= (0)::numeric));

COMMENT ON CONSTRAINT pga_monthly_reconciliations_low_positive_check ON public.pga_monthly_reconciliations IS
    'Mirrors pga_monitoring_settings_low_positive_check onto the per-month threshold snapshot; with threshold_order_check this forces 0 < low < medium, so the band_consistent_check ratio test cannot be trivially satisfied by non-positive thresholds. Consensus finding of the two independent v5.4.0-06 reviews, landed in v5.4.1-01.';
