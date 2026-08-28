-- ============================================================================
-- PATCH v5.4.2-03 — A-1: bi-temporal transaction-time substrate for the seven
--                    reference tables (schema-parity-plan Phase 4 Wave 1,
--                    Appendix A-1; CI-001 / CI-002 / CI-005 / CI-011)
-- ============================================================================
-- Authority:   gas-billing-memory/application/bi-temporal-decision.md §6
--              ("Session A Output Checklist" — the DDL deliverable);
--              a1-bitemporal-design-review-2026-08-20.md §4 (synthesized
--              design after two adversarial reviews); Kyle rulings
--              kyle-decisions-2026-08-26-a1-bitemporal.md R-9 … R-17
--              (R-18 is a v5.5 item, not in this patch); D1-1 (CI-011 is
--              optimistic concurrency, not a conflict workflow).
--
-- What lands (one patch, one session — R-15 forbids landing the columns
-- without the lookups):
--
--   1. Shared machinery: enforce_bitemporal_assertion() (one guard for every
--      bi-temporal table: closed rows are immutable; open asserted rows
--      accept exactly one lifetime transition — the close — plus a named
--      per-table lifecycle set; drafts are free), a DEFERRABLE constraint
--      trigger that makes closed_type = 'superseded' mean "a successor row
--      exists at commit" (CI-002 is structural, not conventional),
--      enforce_reference_header() (identity columns frozen, version counter
--      monotone), assert_reference_version() (the D1-1 optimistic check +
--      per-entity row lock in one statement).
--
--   2. Group 1 — header/version split (entity-FK'd tables; every existing FK
--      into them keeps pointing at the same id):
--        rate_schedules  -> header (id, tenant_id, code, created_at, status,
--                           archive_reason, activated_at, archived_at,
--                           version, updated_at) + rate_schedule_versions
--        wna_zones       -> header (id, tenant_id, zone_code, created_at,
--                           status, version, updated_at) + wna_zone_versions
--        rate_items      -> header (id, tenant_id, item_code, created_at,
--                           status, version, updated_at) + rate_item_versions
--      Content columns are MOVED (backfilled into one 'backfill' version row
--      per entity, stamped at created_at as an approximation — the A-22
--      precedent — then dropped from the header). rate_items.current_rate is
--      dropped, not cached (design §4.2).
--
--   3. Group 2 — in-place transaction-time pair on rate_schedule_items,
--      franchise_fee_rules, customer_tax_exemptions, wna_monthly_adjustments.
--      The three table-wide UNIQUE constraints that made a same-date
--      correction impossible become open-rows-only constraints (exclusion on
--      the valid bracket where the bracket is a range; partial unique where
--      the valid coordinate is a month). Lifecycle tables lock at the
--      asserted state: wna_monthly_adjustments at 'approved' (R-11),
--      customer_tax_exemptions at 'active' with DEFAULT flipped to
--      'pending_verification' and the verified_by/verified_at CHECK (R-12);
--      'industrial' leaves the exemption_type domain (R-13).
--
--   4. Not-current enum reconciliation (R-14 rider 3): 'superseded' leaves
--      franchise_fee_rules.status (it now means recorded_until IS NOT NULL);
--      'expired' leaves rate_schedules' header status (valid-time expiry
--      lives on the version's expiry_date); 'archived' on the in-place
--      tables requires a valid-time end; rate_schedules.archive_reason is
--      an enum (abandoned_draft | superseded_by_filing |
--      service_discontinued), required exactly when archived (R-14 rider 1);
--      a draft schedule cannot be assigned to a meter or deployment
--      (R-14 rider 2).
--
--   5. service_type is versioned (R-9). All open versions of a schedule must
--      share one service_type (a valid-time-dated service change is
--      rejected; a correction closes every open version and re-asserts over
--      the full span). A correction that changes service_type must carry
--      service_type_change_basis = 'transcription_error' — the only value
--      the enum has, because a re-tag that moves customers between
--      regulatory regimes is a re-filing and is not available on this path
--      (R-17) — and, when invoices exist against the schedule, drops an
--      anomalies row (anomaly_type = 'reference_correction_review') so an
--      operator rules on correction scope.
--
--   6. archive_rate_item_history() becomes a RAISE stub; rate_item_history
--      and rate_item_history_archive are retired read-only (migration
--      source; guard + REVOKE). The six ON DELETE CASCADE clauses that let a
--      header delete destroy its own history are stripped; the ten tables
--      of this substrate join the A-4 no-hard-delete set.
--
--   7. Lookups (R-15): one per domain, all `(…, p_valid_at date,
--      p_recorded_at timestamptz)`, both REQUIRED, NULL raises, no now()
--      default, no COALESCE onto a live column, no per-domain variation:
--      rate_schedule_as_of, wna_zone_as_of, rate_item_as_of,
--      rate_schedule_item_as_of, franchise_fee_as_of,
--      customer_tax_exemption_as_of, wna_monthly_adjustment_as_of.
--      Sweeps: should_charge_tax gains the transaction-time axis (old
--      CURRENT_DATE-defaulting signature dropped); get_partial_period_policy
--      re-issued with both axes (2-arg form dropped — its rate_schedules
--      read no longer exists); get_effective_rate becomes a deprecation
--      RAISE (its LIMIT 1 / no ORDER BY / current_rate read is the exact
--      landmine this patch would otherwise arm); get_correction_rate_date's
--      COMMENT rewritten to name both axes; gas_usage_formula COMMENT no
--      longer names the archive table as the calc path.
--
-- Deferred with stated triggers (not in this patch): CI-003 GUC coordinate
-- net — revisit before the first bill-run calculation code lands (R-16; the
-- explicit-parameter functions here are the layer a GUC-defaulted variant
-- sits over). Sewer-to-water linkage enforcement — v5.5 (R-18). Predominant
-- -use exemptions — own table, no date (R-13). A-19 assignment history and
-- jurisdictions.wna_zone_id copy this pattern later.
--
-- Self-verifying preconditions (R-13 pattern — refuse and report, never
-- audit first): the patch raises if any row exists with
-- customer_tax_exemptions.exemption_type = 'industrial', an active/expired/
-- revoked exemption lacking verified_by/verified_at, a non-pending WNA
-- adjustment lacking approved_by/approved_at, franchise_fee_rules.status =
-- 'superseded', or rate_schedules.status IN ('expired','archived') (the
-- header needs an archive_reason nobody can invent). A fresh deploy has
-- none of these; a populated one maps them first.
--
-- Drafting decisions (durable copies: application/DECISION-LOG.md):
--   * change_type is the INSERTED row's event: initial | succession |
--     correction | backfill. 'retraction' is not a value — a retraction is
--     a close with no successor and lives on the closing side as
--     closed_type = 'retracted'. (Design §4.8 listed retraction in the
--     insert enum; no inserted row can legitimately carry it.)
--   * Lineage is supersedes_id on the NEW row, not superseded_by_id on the
--     closed row: the close must happen BEFORE the insert (the exclusion
--     constraint forbids two open rows over one valid bracket), and a closed
--     row is frozen, so the pointer can only live on the successor. The
--     deferred constraint trigger closes the gap ("superseded" with no
--     successor at commit is rejected).
--   * Valid-time changes to an asserted row (revocation date, a new expiry
--     because a successor rate starts) are ALSO insert-and-close: the guard
--     freezes every content column once asserted. Kyle's "closings of the
--     record, not in-place edits" (R-12) is read strictly; in-place
--     effective_end edits would make "what did we believe on date X" wrong.
--   * Version rows (group 1) have no draft phase — recorded_at is NOT NULL
--     and stamps at insert. The draft concept lives on the rate_schedules
--     header (status = 'draft'), where R-14 put it.
--   * rate_item_history rows are migrated into rate_item_versions only when
--     the bracket is self-consistent (the exclusion constraint validates the
--     migration; an overlapping legacy bracket fails the patch loudly).
--     Columns rate_item_history never tracked are copied from the live row —
--     an approximation flagged in change_reason on every such row.
--   * Transaction time is the database's, never the caller's: recorded_at is
--     forced to now() on every insert and on every draft -> asserted
--     transition; recorded_until must lie in [recorded_at, now()]. A
--     caller-chosen recorded_at would let "what did we know on date X" be
--     rewritten after the fact. change_type = 'backfill' is not insertable
--     after the patch (its rows are written before the guards exist).
--   * Lineage never crosses entities: supersedes_id must name a row of the
--     same entity (entity-key columns are the guard's second argument) and
--     the same tenant, already closed as superseded; the deferred successor
--     check is scoped the same way. Both from the pre-mirror review round
--     (Codex: CRITICAL cross-entity supersede on six tables; MEDIUM
--     forgeable recorded_at).
--   * Headers reconcile with their versions (R-14 rider 3, extended to the
--     three headers by review): archiving requires every open version to
--     carry an expiry_date (assert the valid-time end, or retract), an
--     archived entity accepts no new versions, and an archived schedule is
--     not assignable (beyond the ruling's "draft", by the same logic).
--     activated_at / archived_at are stamped by the trigger, not supplied.
--   * Version rows are bound to their header's tenant by a composite FK
--     (id, tenant_id) — the plain FK let a tenant-2 version hang off a
--     tenant-1 schedule.
--   * No app.* GUC carve-out is used anywhere in this patch (design §4.8
--     suggested reusing app.void_operation's shape): the one sanctioned
--     transition — the close — is expressed as a row shape the guard
--     recognises, so there is nothing for a caller to arm.
--   * An active schedule may have every version retracted (0 open): the
--     header stays active and as_of is unknowable for it — a deliberate
--     blackout, not a defect (Fable M1c). Archived is terminal on all
--     three headers.
--   * Versions of a draft schedule are asserted immediately (the header is
--     the draft, per R-14); editing a draft's content leaves history. That
--     is the cost of one write path, and it is honest.
--   * should_charge_tax() drops SECURITY DEFINER: the definer form answered
--     for any customer regardless of the caller's tenant.
--   * supersedes_id is not unique: one closed predecessor may have several
--     successors (a valid-time bracket split closes one row and inserts
--     two). Lineage walkers must expect fan-out; "which is current" is a
--     coordinate question the as_of functions answer (Codex round 2, LOW).
--   * Lookups are STABLE, invoker-rights (RLS applies), RETURNS SETOF the
--     row type — zero rows means "unknowable at that coordinate", which the
--     caller must treat as a hard error (D-2026-08-20-09).
--
-- Verification contract: this file applies standalone under
--   SET search_path = ''; SET check_function_bodies = on;
-- (D-2026-08-20-24). Every relation and function reference is qualified.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 0. Self-verifying preconditions
-- ----------------------------------------------------------------------------
DO $$
DECLARE
    n bigint;
BEGIN
    SELECT count(*) INTO n FROM public.customer_tax_exemptions WHERE exemption_type = 'industrial';
    IF n > 0 THEN
        RAISE EXCEPTION 'v5.4.2-03 refused: % customer_tax_exemptions row(s) carry exemption_type = ''industrial'' (R-13: predominant-use exemptions are not certificate-backed and this table cannot express a partial percentage). Re-key (e.g. to ''other'' — which requires exemption_reason) or retire them, then re-apply.', n;
    END IF;

    SELECT count(*) INTO n FROM public.customer_tax_exemptions
    WHERE status IN ('active', 'expired', 'revoked') AND (verified_by IS NULL OR verified_at IS NULL);
    IF n > 0 THEN
        RAISE EXCEPTION 'v5.4.2-03 refused: % asserted customer_tax_exemptions row(s) lack verified_by/verified_at (R-12 requires a verification signature behind every active exemption — Comptroller Rule 3.287). Verify or set them pending_verification, then re-apply.', n;
    END IF;

    SELECT count(*) INTO n FROM public.wna_monthly_adjustments
    WHERE status <> 'pending' AND (approved_by IS NULL OR approved_at IS NULL);
    IF n > 0 THEN
        RAISE EXCEPTION 'v5.4.2-03 refused: % non-pending wna_monthly_adjustments row(s) lack approved_by/approved_at (R-11: approval is the assertion signature). Fix or set them pending, then re-apply.', n;
    END IF;

    SELECT count(*) INTO n FROM public.franchise_fee_rules WHERE status = 'superseded';
    IF n > 0 THEN
        RAISE EXCEPTION 'v5.4.2-03 refused: % franchise_fee_rules row(s) have status = ''superseded'' (R-14 rider 3: that word now means recorded_until IS NOT NULL). Map each to archived (with an expiry_date) or to a closed transaction-time row, then re-apply.', n;
    END IF;

    SELECT count(*) INTO n FROM public.franchise_fee_rules WHERE status = 'archived' AND expiry_date IS NULL;
    IF n > 0 THEN
        RAISE EXCEPTION 'v5.4.2-03 refused: % archived franchise_fee_rules row(s) have no expiry_date (R-14 rider 3: archived is a valid-time end and must say when). Set it, then re-apply.', n;
    END IF;

    SELECT count(*) INTO n FROM public.rate_schedule_items WHERE status = 'archived' AND expiry_date IS NULL;
    IF n > 0 THEN
        RAISE EXCEPTION 'v5.4.2-03 refused: % archived rate_schedule_items row(s) have no expiry_date (R-14 rider 3). Set it, then re-apply.', n;
    END IF;

    SELECT count(*) INTO n FROM public.rate_schedules WHERE status IN ('expired', 'archived');
    IF n > 0 THEN
        RAISE EXCEPTION 'v5.4.2-03 refused: % rate_schedules row(s) are expired/archived; the header now needs an archive_reason (abandoned_draft | superseded_by_filing | service_discontinued) that this patch will not invent (R-14 rider 1). Map them, then re-apply.', n;
    END IF;
END;
$$;

-- ----------------------------------------------------------------------------
-- 1. Shared machinery
-- ----------------------------------------------------------------------------

-- 1.1 The bi-temporal row guard. Attached BEFORE INSERT OR UPDATE OR DELETE to
--     every version table and every in-place table. TG_ARGV[0] is the
--     comma-separated list of columns that stay writable on an ASSERTED, OPEN
--     row (the table's lifecycle set — e.g. wna_monthly_adjustments.status so
--     approved -> applied is a status flip, not a correction). Everything else:
--       closed row (recorded_until IS NOT NULL)      -> immutable, no exceptions
--       draft row  (recorded_at IS NULL)             -> free, but cannot close
--       asserted open row                            -> only the close
--          (recorded_until + closed_type + closed_reason + closed_by, in one
--          UPDATE, every content column byte-identical) or the lifecycle set
--     INSERT: a row is born open unless it is a 'backfill' (migration may load
--     history that is already closed).
-- 1.0 Lineage scope. supersedes_id must point at a row of the SAME entity (same
--     entity-key columns, same tenant) that is already closed as 'superseded'.
--     Without this a caller could close entity A as "superseded" and satisfy the
--     successor check with an unrelated entity B's row, leaving A silently
--     without a current assertion under a label that claims continuity
--     (Codex review of v5.4.2-03, CRITICAL).
CREATE OR REPLACE FUNCTION public.assert_bitemporal_predecessor(p_table text, p_keys text[], p_new jsonb) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_pred jsonb;
    k      text;
BEGIN
    IF (p_new ->> 'supersedes_id') IS NULL THEN
        RETURN;
    END IF;
    EXECUTE format('SELECT to_jsonb(p) FROM public.%I p WHERE p.id = $1', p_table)
        INTO v_pred USING (p_new ->> 'supersedes_id')::uuid;
    IF v_pred IS NULL THEN
        RAISE EXCEPTION USING MESSAGE = format('%s: supersedes_id %s does not exist', p_table, p_new ->> 'supersedes_id'), ERRCODE = 'foreign_key_violation';
    END IF;
    IF (v_pred ->> 'tenant_id') IS DISTINCT FROM (p_new ->> 'tenant_id') THEN
        RAISE EXCEPTION USING MESSAGE = format('%s: supersedes_id %s belongs to another tenant', p_table, p_new ->> 'supersedes_id'), ERRCODE = 'check_violation';
    END IF;
    FOREACH k IN ARRAY p_keys LOOP
        IF (v_pred ->> k) IS DISTINCT FROM (p_new ->> k) THEN
            RAISE EXCEPTION USING
                MESSAGE = format('%s: supersedes_id %s belongs to a different entity (%s differs: %s vs %s); lineage never crosses entities', p_table, p_new ->> 'supersedes_id', k, v_pred ->> k, p_new ->> k),
                ERRCODE = 'check_violation';
        END IF;
    END LOOP;
    IF (v_pred ->> 'recorded_until') IS NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('%s: close the superseded row %s (closed_type = ''superseded'') before inserting its successor', p_table, p_new ->> 'supersedes_id'),
            ERRCODE = 'check_violation';
    END IF;
    IF (v_pred ->> 'closed_type') IS DISTINCT FROM 'superseded' THEN
        RAISE EXCEPTION USING
            MESSAGE = format('%s: row %s was closed as %s, not ''superseded'' — a retracted assertion has no successor (CI-002)', p_table, p_new ->> 'supersedes_id', v_pred ->> 'closed_type'),
            ERRCODE = 'check_violation';
    END IF;
END;
$$;

COMMENT ON FUNCTION public.assert_bitemporal_predecessor(text, text[], jsonb) IS
    'A-1 (v5.4.2-03). Called by enforce_bitemporal_assertion() on INSERT when supersedes_id is set: the predecessor must exist, be the same tenant and the same entity (the trigger''s second argument names the entity-key columns), and be already closed as superseded. Lineage never crosses entities.';

CREATE OR REPLACE FUNCTION public.enforce_bitemporal_assertion() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_closing  constant text[] := ARRAY['recorded_until', 'closed_type', 'closed_reason', 'closed_by'];
    v_mutable  text[] := CASE WHEN TG_NARGS >= 1 AND TG_ARGV[0] <> '' THEN string_to_array(TG_ARGV[0], ',') ELSE ARRAY[]::text[] END;
    v_keys     text[] := CASE WHEN TG_NARGS >= 2 THEN string_to_array(TG_ARGV[1], ',') ELSE ARRAY['id']::text[] END;  -- entity-key columns (lineage scope)
    v_header_status text;
    v_old      jsonb;
    v_new      jsonb;
    v_old_ra   timestamptz;
    v_old_ru   timestamptz;
    v_new_ra   timestamptz;
    v_new_ru   timestamptz;
BEGIN
    IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION USING
            MESSAGE = format('%s: bi-temporal rows are never deleted (CI-001/CI-014); retract by closing the row (recorded_until + closed_type = ''retracted'' + closed_reason).', TG_TABLE_NAME),
            ERRCODE = 'restrict_violation';
    END IF;

    v_new_ra := (to_jsonb(NEW) ->> 'recorded_at')::timestamptz;
    v_new_ru := (to_jsonb(NEW) ->> 'recorded_until')::timestamptz;

    IF TG_OP = 'INSERT' THEN
        IF (to_jsonb(NEW) ->> 'change_type') = 'backfill' THEN
            RAISE EXCEPTION USING
                MESSAGE = format('%s: change_type = ''backfill'' is written only by the v5.4.2-03 migration, before this guard existed; a live insert is initial / succession / correction.', TG_TABLE_NAME),
                ERRCODE = 'check_violation';
        END IF;
        IF v_new_ru IS NOT NULL THEN
            RAISE EXCEPTION USING
                MESSAGE = format('%s: a new assertion is born open — recorded_until is set only by the closing UPDATE.', TG_TABLE_NAME),
                ERRCODE = 'check_violation';
        END IF;
        -- transaction time is stamped by the database, never supplied: a caller-chosen recorded_at
        -- would let "what did we know on date X" be rewritten after the fact (Codex review, v5.4.2-03).
        IF v_new_ra IS NOT NULL THEN
            NEW.recorded_at := now();
        END IF;
        PERFORM public.assert_bitemporal_predecessor(TG_TABLE_NAME, v_keys, to_jsonb(NEW));
        -- version tables (TG_ARGV[2] = header table): an archived entity accepts no new assertions
        IF TG_NARGS >= 3 AND TG_ARGV[2] <> '' THEN
            EXECUTE format('SELECT h.status FROM public.%I h WHERE h.id = $1', TG_ARGV[2])
                INTO v_header_status USING (to_jsonb(NEW) ->> v_keys[1])::uuid;
            IF v_header_status = 'archived' THEN
                RAISE EXCEPTION USING
                    MESSAGE = format('%s: %s %s is archived and accepts no new versions (R-14); create a new entity.', TG_TABLE_NAME, TG_ARGV[2], to_jsonb(NEW) ->> v_keys[1]),
                    ERRCODE = 'check_violation';
            END IF;
        END IF;
        RETURN NEW;
    END IF;

    -- UPDATE
    v_old_ra := (to_jsonb(OLD) ->> 'recorded_at')::timestamptz;
    v_old_ru := (to_jsonb(OLD) ->> 'recorded_until')::timestamptz;

    IF v_old_ru IS NOT NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('%s: this assertion was closed at %s and is immutable (CI-001). Insert a new row (supersedes_id -> the row you meant to change) instead.', TG_TABLE_NAME, v_old_ru),
            ERRCODE = 'restrict_violation';
    END IF;

    IF v_old_ra IS NULL THEN
        -- draft: free, but a draft is not an assertion and cannot be closed
        IF v_new_ru IS NOT NULL THEN
            RAISE EXCEPTION USING
                MESSAGE = format('%s: a draft (recorded_at IS NULL) has asserted nothing and cannot be closed; edit it, or move it to its rejected/abandoned state.', TG_TABLE_NAME),
                ERRCODE = 'check_violation';
        END IF;
        IF v_new_ra IS NOT NULL THEN
            NEW.recorded_at := now();   -- the assertion instant is the database's, not the caller's
        END IF;
        RETURN NEW;
    END IF;

    -- asserted, open
    v_old := to_jsonb(OLD) - v_closing - v_mutable;
    v_new := to_jsonb(NEW) - v_closing - v_mutable;
    IF v_old <> v_new THEN
        RAISE EXCEPTION USING
            MESSAGE = format('%s: an asserted row is never edited in place (CI-001/CI-002). Close it (recorded_until, closed_type, closed_reason) and insert the corrected row with supersedes_id = %s. Writable in place: %s.',
                             TG_TABLE_NAME, to_jsonb(OLD) ->> 'id', COALESCE(array_to_string(v_mutable, ', '), '(nothing)')),
            ERRCODE = 'restrict_violation';
    END IF;

    IF v_new_ru IS NOT NULL THEN
        -- the close instant is the database's: a caller-chosen recorded_until could erase the row
        -- from every coordinate or antedate what was known. (A row asserted and closed in the same
        -- transaction is a zero-width assertion — nobody could have seen it; that is equivalent to
        -- never asserting it and is tolerated.)
        NEW.recorded_until := now();
    END IF;

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.enforce_bitemporal_assertion() IS
    'A-1 row guard (v5.4.2-03), attached BEFORE INSERT OR UPDATE OR DELETE on every bi-temporal table. Closed rows (recorded_until set) are immutable. Drafts (recorded_at NULL — only the lifecycle tables have them) are free but cannot be closed. An asserted open row accepts exactly two kinds of UPDATE: the close (recorded_until + closed_type + closed_reason [+ closed_by], all content byte-identical) and the per-table lifecycle set named in the trigger argument. DELETE always raises. Correction = close the row, then INSERT the corrected row with supersedes_id pointing back; retraction = close with closed_type = ''retracted'' and no successor. Both stamps are now() = transaction start (standard MVCC: a long transaction commits rows whose recorded_at precedes coordinates other sessions already queried; keep correction transactions short). CI-001 / CI-002.';

-- 1.2 "superseded" must have a successor at commit. DEFERRABLE INITIALLY
--     DEFERRED so close-then-insert inside one transaction is fine, and a
--     close labelled superseded that never gets its successor is rejected.
CREATE OR REPLACE FUNCTION public.enforce_superseded_has_successor() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_found boolean;
BEGIN
    IF (to_jsonb(NEW) ->> 'closed_type') IS DISTINCT FROM 'superseded' THEN
        RETURN NULL;
    END IF;
    -- the successor must be the same entity: compare every entity-key column named in TG_ARGV[0]
    EXECUTE format('SELECT EXISTS (SELECT 1 FROM public.%I s WHERE s.supersedes_id = $1 AND s.recorded_at IS NOT NULL AND (s.recorded_until IS NULL OR s.closed_type = ''superseded'') AND (%s))', TG_TABLE_NAME,
                   (SELECT string_agg(format('s.%I::text IS NOT DISTINCT FROM ($2 ->> %L)', k, k), ' AND ')
                    FROM unnest(CASE WHEN TG_NARGS >= 1 THEN string_to_array(TG_ARGV[0], ',') ELSE ARRAY['id'] END) AS k))
        INTO v_found USING (to_jsonb(NEW) ->> 'id')::uuid, to_jsonb(NEW);
    IF NOT v_found THEN
        RAISE EXCEPTION USING
            MESSAGE = format('%s: row %s was closed as ''superseded'' but no ASSERTED, non-retracted row of the same entity supersedes it at commit (a pending draft does not count; a successor retracted in the same transaction does not count — retract the whole chain if the fact never existed). Insert the successor (supersedes_id = this id, same entity) in the same transaction, or close it as ''retracted'' (CI-002).', TG_TABLE_NAME, to_jsonb(NEW) ->> 'id'),
            ERRCODE = 'integrity_constraint_violation';
    END IF;
    RETURN NULL;
END;
$$;

COMMENT ON FUNCTION public.enforce_superseded_has_successor() IS
    'A-1 (v5.4.2-03). Deferred constraint trigger on every bi-temporal table: a row closed with closed_type = ''superseded'' must be pointed at by a successor (supersedes_id) OF THE SAME ENTITY (the trigger argument names the entity-key columns) when the transaction commits — the successor must be asserted (drafts do not count) and not itself retracted (a chain ends only by retraction of its head; a superseded label never hides a blackout); otherwise the close should have said ''retracted''. Makes CI-002''s correction/retraction distinction structural: the two are readable from the closed row plus the presence/absence of a successor, and the label cannot lie.';

-- 1.3 Header identity guard (group 1). TG_ARGV[0] = the natural-key column.
--     Identity columns are frozen; version may only stay or increase by 1.
CREATE OR REPLACE FUNCTION public.enforce_reference_header() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_identity      text[] := ARRAY['id', 'tenant_id', TG_ARGV[0], 'created_at'];
    c               text;
    v_old           jsonb := to_jsonb(OLD);
    v_new           jsonb := to_jsonb(NEW);
    v_open_unexpired boolean;
BEGIN
    IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION USING
            MESSAGE = format('%s: identity headers anchor permanent FKs and version history and are never deleted (CI-014); archive the entity instead.', TG_TABLE_NAME),
            ERRCODE = 'restrict_violation';
    END IF;
    FOREACH c IN ARRAY v_identity LOOP
        IF (v_old -> c) IS DISTINCT FROM (v_new -> c) THEN
            RAISE EXCEPTION USING
                MESSAGE = format('%s.%s is an identity column and is immutable (A-1 header: id, tenant_id, %s, created_at). Everything correctable lives on the version table.', TG_TABLE_NAME, c, TG_ARGV[0]),
                ERRCODE = 'restrict_violation';
        END IF;
    END LOOP;
    IF (v_new ->> 'version')::integer NOT IN ((v_old ->> 'version')::integer, (v_old ->> 'version')::integer + 1) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('%s.version moves by exactly one per write (%s -> %s rejected); use assert_reference_version() (CI-011 / D1-1).', TG_TABLE_NAME, v_old ->> 'version', v_new ->> 'version'),
            ERRCODE = 'check_violation';
    END IF;
    IF (v_old ->> 'status') = 'archived' AND (v_new ->> 'status') IS DISTINCT FROM 'archived' THEN
        RAISE EXCEPTION USING
            MESSAGE = format('%s %s: archived is terminal; create a new entity', TG_TABLE_NAME, v_new ->> 'id'),
            ERRCODE = 'check_violation';
    END IF;
    -- R-14 rider 3 on the headers: 'archived' must agree with the versions — no open version may be
    -- unexpired when the entity is archived (TG_ARGV[1] = version table, TG_ARGV[2] = its FK column).
    IF (v_new ->> 'status') = 'archived' AND (v_old ->> 'status') IS DISTINCT FROM 'archived' AND TG_NARGS >= 3 THEN
        EXECUTE format('SELECT EXISTS (SELECT 1 FROM public.%I v WHERE v.%I = $1 AND v.recorded_until IS NULL AND v.expiry_date IS NULL)', TG_ARGV[1], TG_ARGV[2])
            INTO v_open_unexpired USING (v_new ->> 'id')::uuid;
        IF v_open_unexpired THEN
            RAISE EXCEPTION USING
                MESSAGE = format('%s %s: cannot archive while an open version has no expiry_date — assert the valid-time end first (close + re-insert with expiry_date), or retract the open versions (R-14 rider 3).', TG_TABLE_NAME, v_new ->> 'id'),
                ERRCODE = 'check_violation';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.enforce_reference_header() IS
    'A-1 (v5.4.2-03) header guard for rate_schedules, wna_zones, rate_items. The trigger argument names the natural-key column; id, tenant_id, that column and created_at are frozen; version may only stay or increase by one. DELETE raises. status / version / updated_at (and rate_schedules'' archive_reason, activated_at, archived_at) are the sanctioned mutable set.';

-- 1.4 The D1-1 optimistic check. One statement: bumps the header version only
--     if the caller's token is current, and — as a side effect — takes the
--     header row lock, serialising concurrent writers on the same entity for
--     the rest of the transaction (bi-temporal-decision §3's "unsolved"
--     concurrent-write problem, solved with a plain row lock).
CREATE OR REPLACE FUNCTION public.assert_reference_version(p_table text, p_id uuid, p_expected_version integer) RETURNS integer
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_new integer;
BEGIN
    IF p_table IS NULL OR p_id IS NULL OR p_expected_version IS NULL THEN
        RAISE EXCEPTION 'assert_reference_version: p_table, p_id and p_expected_version are all required';
    END IF;
    IF p_table NOT IN ('rate_schedules', 'wna_zones', 'rate_items') THEN
        RAISE EXCEPTION 'assert_reference_version: % is not a versioned reference header (rate_schedules | wna_zones | rate_items)', p_table;
    END IF;
    EXECUTE format('UPDATE public.%I SET version = version + 1, updated_at = now() WHERE id = $1 AND version = $2 RETURNING version', p_table)
        INTO v_new USING p_id, p_expected_version;
    IF v_new IS NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('%s %s was modified since it was read (expected version %s): review and retry (CI-011 / D1-1).', p_table, p_id, p_expected_version),
            ERRCODE = 'serialization_failure';
    END IF;
    RETURN v_new;
END;
$$;

COMMENT ON FUNCTION public.assert_reference_version(text, uuid, integer) IS
    'A-1 (v5.4.2-03), CI-011 per D1-1. Call FIRST in any transaction that inserts or closes version rows of a rate_schedules / wna_zones / rate_items entity, passing the version the client read. Bumps the header version and returns the new one; raises serialization_failure (40001) if the token is stale — "modified, review and retry", never last-writer-wins. The UPDATE also row-locks the header until commit, so two writers on one entity are serialised by the database. For the four in-place tables there is no header and no counter: the closing UPDATE predicated on recorded_until IS NULL is its own optimistic check (0 rows = stale) and the open-rows exclusion/unique constraint catches concurrent overlapping inserts.';

-- ----------------------------------------------------------------------------
-- 2. Group 1 — rate_schedules: header + rate_schedule_versions
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.rate_schedule_versions (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id uuid NOT NULL,
    rate_schedule_id uuid NOT NULL,
    -- content (moved from rate_schedules)
    name text NOT NULL,
    description text,
    service_type text NOT NULL,
    customer_type text NOT NULL,
    wna_zone_id uuid,
    franchise_city text,
    regulatory_authority text,
    tariff_number text,
    tariff_document_url text,
    regulatory_code text,
    sewer_calc_method text,
    sewer_cap_gallons numeric(12,2),
    winter_avg_months integer[],
    gas_meter_factor_required boolean DEFAULT false NOT NULL,
    gas_usage_formula text,
    bill_section_label text,
    partial_period_policy text,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    allow_estimation boolean DEFAULT true NOT NULL,
    estimation_method text,
    sewer_percent_of_water numeric(5,4),
    partial_period_policy_override text,
    prorate_tier_breakpoints boolean DEFAULT false NOT NULL,
    minimum_bill_amount numeric(12,2),
    -- valid time
    effective_date date NOT NULL,
    expiry_date date,
    -- transaction time + event
    recorded_at timestamp with time zone DEFAULT now() NOT NULL,
    recorded_until timestamp with time zone,
    change_type text NOT NULL,
    change_reason text,
    changed_by uuid,
    supersedes_id uuid,
    service_type_change_basis text,
    closed_type text,
    closed_reason text,
    closed_by uuid,
    CONSTRAINT rate_schedule_versions_pkey PRIMARY KEY (id),
    CONSTRAINT rate_schedule_versions_customer_type_check CHECK ((customer_type = ANY (ARRAY['residential'::text, 'commercial'::text, 'small_commercial'::text, 'large_commercial'::text, 'industrial'::text, 'government'::text, 'wholesale'::text]))),
    CONSTRAINT rate_schedule_versions_estimation_method_check CHECK (((estimation_method IS NULL) OR (estimation_method = ANY (ARRAY['historical_average_3mo'::text, 'historical_average_12mo'::text, 'same_period_prior_year'::text, 'last_actual_reading'::text, 'zero'::text])))),
    CONSTRAINT rate_schedule_versions_gas_usage_formula_check CHECK ((gas_usage_formula = ANY (ARRAY['standard'::text, 'with_meter_factor'::text, 'with_temp_factor'::text]))),
    CONSTRAINT rate_schedule_versions_minimum_bill_amount_check CHECK (((minimum_bill_amount IS NULL) OR (minimum_bill_amount >= (0)::numeric))),
    CONSTRAINT rate_schedule_versions_partial_period_policy_check CHECK ((partial_period_policy = ANY (ARRAY['prorated'::text, 'charge_both'::text, 'period_holder'::text]))),
    CONSTRAINT rate_schedule_versions_partial_period_policy_override_check CHECK (((partial_period_policy_override IS NULL) OR (partial_period_policy_override = ANY (ARRAY['prorated'::text, 'charge_both'::text, 'period_holder'::text])))),
    CONSTRAINT rate_schedule_versions_service_type_check CHECK ((service_type = ANY (ARRAY['water'::text, 'sewer'::text, 'electric'::text, 'gas'::text, 'stormwater'::text, 'trash'::text, 'reclaimed_water'::text]))),
    CONSTRAINT rate_schedule_versions_sewer_calc_method_check CHECK ((sewer_calc_method = ANY (ARRAY['flat'::text, 'metered'::text, 'winter_avg'::text, 'percent_of_water'::text]))),
    CONSTRAINT rate_schedule_versions_sewer_percent_of_water_check CHECK (((sewer_percent_of_water IS NULL) OR ((sewer_percent_of_water > (0)::numeric) AND (sewer_percent_of_water <= (1)::numeric)))),
    CONSTRAINT rate_schedule_versions_winter_months_valid CHECK (((winter_avg_months IS NULL) OR (((array_length(winter_avg_months, 1) >= 1) AND (array_length(winter_avg_months, 1) <= 12)) AND (winter_avg_months <@ ARRAY[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12])))),
    CONSTRAINT rate_schedule_versions_valid_bracket_check CHECK ((expiry_date IS NULL) OR (expiry_date >= effective_date)),
    CONSTRAINT rate_schedule_versions_change_type_check CHECK ((change_type = ANY (ARRAY['initial'::text, 'succession'::text, 'correction'::text, 'backfill'::text]))),
    CONSTRAINT rate_schedule_versions_correction_reason_check CHECK ((change_type <> 'correction') OR (change_reason IS NOT NULL)),
    CONSTRAINT rate_schedule_versions_supersedes_check CHECK ((supersedes_id IS NULL) OR (change_type = 'succession') OR (change_type = 'correction')),
    CONSTRAINT rate_schedule_versions_closed_type_check CHECK ((closed_type IS NULL) OR (closed_type = ANY (ARRAY['superseded'::text, 'retracted'::text]))),
    CONSTRAINT rate_schedule_versions_close_consistent_check CHECK (((recorded_until IS NULL) AND (closed_type IS NULL) AND (closed_reason IS NULL) AND (closed_by IS NULL)) OR ((recorded_until IS NOT NULL) AND (closed_type IS NOT NULL) AND (closed_reason IS NOT NULL) AND (recorded_until >= recorded_at))),
    CONSTRAINT rate_schedule_versions_service_type_basis_check CHECK ((service_type_change_basis IS NULL) OR ((service_type_change_basis = 'transcription_error') AND (supersedes_id IS NOT NULL)))
);

ALTER TABLE public.rate_schedule_versions DROP CONSTRAINT IF EXISTS rate_schedule_versions_tenant_id_fkey;
ALTER TABLE public.rate_schedule_versions ADD CONSTRAINT rate_schedule_versions_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id);
ALTER TABLE public.rate_schedule_versions DROP CONSTRAINT IF EXISTS rate_schedule_versions_rate_schedule_id_fkey;
ALTER TABLE public.rate_schedules DROP CONSTRAINT IF EXISTS rate_schedules_id_tenant_id_key;
ALTER TABLE public.rate_schedules ADD CONSTRAINT rate_schedules_id_tenant_id_key UNIQUE (id, tenant_id);
ALTER TABLE public.rate_schedule_versions ADD CONSTRAINT rate_schedule_versions_rate_schedule_id_fkey FOREIGN KEY (rate_schedule_id, tenant_id) REFERENCES public.rate_schedules(id, tenant_id);
ALTER TABLE public.rate_schedule_versions DROP CONSTRAINT IF EXISTS rate_schedule_versions_wna_zone_id_fkey;
ALTER TABLE public.rate_schedule_versions ADD CONSTRAINT rate_schedule_versions_wna_zone_id_fkey FOREIGN KEY (wna_zone_id) REFERENCES public.wna_zones(id);
ALTER TABLE public.rate_schedule_versions DROP CONSTRAINT IF EXISTS rate_schedule_versions_changed_by_fkey;
ALTER TABLE public.rate_schedule_versions ADD CONSTRAINT rate_schedule_versions_changed_by_fkey FOREIGN KEY (changed_by) REFERENCES public.users(id);
ALTER TABLE public.rate_schedule_versions DROP CONSTRAINT IF EXISTS rate_schedule_versions_closed_by_fkey;
ALTER TABLE public.rate_schedule_versions ADD CONSTRAINT rate_schedule_versions_closed_by_fkey FOREIGN KEY (closed_by) REFERENCES public.users(id);
ALTER TABLE public.rate_schedule_versions DROP CONSTRAINT IF EXISTS rate_schedule_versions_supersedes_id_fkey;
ALTER TABLE public.rate_schedule_versions ADD CONSTRAINT rate_schedule_versions_supersedes_id_fkey FOREIGN KEY (supersedes_id) REFERENCES public.rate_schedule_versions(id);

-- one open assertion per schedule per valid-time point
ALTER TABLE public.rate_schedule_versions DROP CONSTRAINT IF EXISTS rate_schedule_versions_open_no_overlap_excl;
ALTER TABLE public.rate_schedule_versions ADD CONSTRAINT rate_schedule_versions_open_no_overlap_excl
    EXCLUDE USING gist (
        rate_schedule_id WITH =,
        daterange(effective_date, expiry_date, '[]') WITH &&
    ) WHERE (recorded_until IS NULL);

CREATE INDEX IF NOT EXISTS idx_rate_schedule_versions_open ON public.rate_schedule_versions USING btree (rate_schedule_id, effective_date DESC) WHERE (recorded_until IS NULL);
CREATE INDEX IF NOT EXISTS idx_rate_schedule_versions_lineage ON public.rate_schedule_versions USING btree (rate_schedule_id, recorded_at DESC);
CREATE INDEX IF NOT EXISTS idx_rate_schedule_versions_tenant ON public.rate_schedule_versions USING btree (tenant_id);
CREATE INDEX IF NOT EXISTS idx_rate_schedule_versions_service ON public.rate_schedule_versions USING btree (tenant_id, service_type) WHERE (recorded_until IS NULL);
CREATE INDEX IF NOT EXISTS idx_rate_schedule_versions_customer_type ON public.rate_schedule_versions USING btree (tenant_id, customer_type) WHERE (recorded_until IS NULL);
CREATE INDEX IF NOT EXISTS idx_rate_schedule_versions_franchise ON public.rate_schedule_versions USING btree (tenant_id, franchise_city) WHERE ((franchise_city IS NOT NULL) AND (recorded_until IS NULL));
CREATE INDEX IF NOT EXISTS idx_rate_schedule_versions_supersedes ON public.rate_schedule_versions USING btree (supersedes_id) WHERE (supersedes_id IS NOT NULL);

ALTER TABLE public.rate_schedule_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rate_schedule_versions FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_isolation ON public.rate_schedule_versions;
CREATE POLICY tenant_isolation ON public.rate_schedule_versions USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));

-- 2.1 Backfill: one 'backfill' version per existing schedule, stamped at
--     created_at (approximation, flagged), BEFORE the header columns go.
DO $$
BEGIN
    -- rate_schedules backfill: only while the header still carries the content columns (re-runnable)
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'rate_schedules' AND column_name = 'name') THEN
        EXECUTE $q$
INSERT INTO public.rate_schedule_versions (
    tenant_id, rate_schedule_id, name, description, service_type, customer_type, wna_zone_id, franchise_city,
    regulatory_authority, tariff_number, tariff_document_url, regulatory_code, sewer_calc_method, sewer_cap_gallons,
    winter_avg_months, gas_meter_factor_required, gas_usage_formula, bill_section_label, partial_period_policy, metadata,
    allow_estimation, estimation_method, sewer_percent_of_water, partial_period_policy_override, prorate_tier_breakpoints,
    minimum_bill_amount, effective_date, expiry_date, recorded_at, change_type, change_reason)
SELECT
    rs.tenant_id, rs.id, rs.name, rs.description, rs.service_type, rs.customer_type, rs.wna_zone_id, rs.franchise_city,
    rs.regulatory_authority, rs.tariff_number, rs.tariff_document_url, rs.regulatory_code, rs.sewer_calc_method, rs.sewer_cap_gallons,
    rs.winter_avg_months, rs.gas_meter_factor_required, rs.gas_usage_formula, rs.bill_section_label, rs.partial_period_policy, rs.metadata,
    rs.allow_estimation, rs.estimation_method, rs.sewer_percent_of_water, rs.partial_period_policy_override, rs.prorate_tier_breakpoints,
    rs.minimum_bill_amount, rs.effective_date, rs.expiry_date, rs.created_at, 'backfill',
    'v5.4.2-03 backfill: content observed at deploy, stamped at rate_schedules.created_at as an approximation — earlier versions are unknown'
FROM public.rate_schedules rs
WHERE NOT EXISTS (SELECT 1 FROM public.rate_schedule_versions v WHERE v.rate_schedule_id = rs.id)
        $q$;
    END IF;
END;
$$;

-- 2.2 Header: shed the content columns, gain the lifecycle columns.
ALTER TABLE public.rate_schedules
    DROP COLUMN IF EXISTS name,
    DROP COLUMN IF EXISTS description,
    DROP COLUMN IF EXISTS service_type,
    DROP COLUMN IF EXISTS customer_type,
    DROP COLUMN IF EXISTS wna_zone_id,
    DROP COLUMN IF EXISTS franchise_city,
    DROP COLUMN IF EXISTS regulatory_authority,
    DROP COLUMN IF EXISTS tariff_number,
    DROP COLUMN IF EXISTS tariff_document_url,
    DROP COLUMN IF EXISTS regulatory_code,
    DROP COLUMN IF EXISTS effective_date,
    DROP COLUMN IF EXISTS expiry_date,
    DROP COLUMN IF EXISTS sewer_calc_method,
    DROP COLUMN IF EXISTS sewer_cap_gallons,
    DROP COLUMN IF EXISTS winter_avg_months,
    DROP COLUMN IF EXISTS gas_meter_factor_required,
    DROP COLUMN IF EXISTS gas_usage_formula,
    DROP COLUMN IF EXISTS bill_section_label,
    DROP COLUMN IF EXISTS partial_period_policy,
    DROP COLUMN IF EXISTS metadata,
    DROP COLUMN IF EXISTS allow_estimation,
    DROP COLUMN IF EXISTS estimation_method,
    DROP COLUMN IF EXISTS sewer_percent_of_water,
    DROP COLUMN IF EXISTS partial_period_policy_override,
    DROP COLUMN IF EXISTS prorate_tier_breakpoints,
    DROP COLUMN IF EXISTS minimum_bill_amount;

ALTER TABLE public.rate_schedules ADD COLUMN IF NOT EXISTS version integer DEFAULT 1 NOT NULL;
ALTER TABLE public.rate_schedules ADD COLUMN IF NOT EXISTS archive_reason text;
ALTER TABLE public.rate_schedules ADD COLUMN IF NOT EXISTS activated_at timestamp with time zone;
ALTER TABLE public.rate_schedules ADD COLUMN IF NOT EXISTS archived_at timestamp with time zone;

UPDATE public.rate_schedules SET activated_at = created_at WHERE status = 'active' AND activated_at IS NULL;

ALTER TABLE public.rate_schedules ALTER COLUMN status SET DEFAULT 'draft';
ALTER TABLE public.rate_schedules DROP CONSTRAINT IF EXISTS rate_schedules_status_check;
ALTER TABLE public.rate_schedules ADD CONSTRAINT rate_schedules_status_check
    CHECK ((status = ANY (ARRAY['draft'::text, 'active'::text, 'archived'::text])));
ALTER TABLE public.rate_schedules DROP CONSTRAINT IF EXISTS rate_schedules_archive_reason_check;
ALTER TABLE public.rate_schedules ADD CONSTRAINT rate_schedules_archive_reason_check
    CHECK ((archive_reason IS NULL) OR (archive_reason = ANY (ARRAY['abandoned_draft'::text, 'superseded_by_filing'::text, 'service_discontinued'::text])));
ALTER TABLE public.rate_schedules DROP CONSTRAINT IF EXISTS rate_schedules_lifecycle_consistent_check;
ALTER TABLE public.rate_schedules ADD CONSTRAINT rate_schedules_lifecycle_consistent_check
    CHECK (
        ((status = 'draft')    AND (archive_reason IS NULL) AND (archived_at IS NULL) AND (activated_at IS NULL))
     OR ((status = 'active')   AND (archive_reason IS NULL) AND (archived_at IS NULL) AND (activated_at IS NOT NULL))
     OR ((status = 'archived') AND (archive_reason IS NOT NULL) AND (archived_at IS NOT NULL)
         AND (((archive_reason = 'abandoned_draft') AND (activated_at IS NULL))
              OR ((archive_reason <> 'abandoned_draft') AND (activated_at IS NOT NULL))))
    );
ALTER TABLE public.rate_schedules DROP CONSTRAINT IF EXISTS rate_schedules_version_check;
ALTER TABLE public.rate_schedules ADD CONSTRAINT rate_schedules_version_check CHECK ((version >= 1));

CREATE INDEX IF NOT EXISTS idx_rate_schedules_status ON public.rate_schedules USING btree (tenant_id, status);

-- 2.3 Header lifecycle: born draft (INSERT); draft -> active (needs an open version; stamps
--     activated_at) ; draft -> archived (abandoned_draft) ; active -> archived
--     (superseded_by_filing | service_discontinued) ; archived is terminal.
CREATE OR REPLACE FUNCTION public.enforce_rate_schedule_lifecycle() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        -- a header is born draft: its content is a version row, which needs the header to exist first,
        -- and activation requires an open version (below). DEFAULT is 'draft' (was 'active').
        IF NEW.status <> 'draft' THEN
            RAISE EXCEPTION 'rate_schedules: a new schedule is created as draft (got %); insert its rate_schedule_versions row, then activate (R-14)', NEW.status;
        END IF;
        RETURN NEW;
    END IF;
    IF NEW.status IS DISTINCT FROM OLD.status THEN
        IF OLD.status = 'archived' THEN
            RAISE EXCEPTION 'rate_schedules %: archived is terminal (R-14); create a new schedule instead', OLD.id;
        END IF;
        IF OLD.status = 'active' AND NEW.status = 'draft' THEN
            RAISE EXCEPTION 'rate_schedules %: an activated schedule cannot return to draft', OLD.id;
        END IF;
        IF NEW.status = 'active' THEN
            IF NOT EXISTS (SELECT 1 FROM public.rate_schedule_versions v WHERE v.rate_schedule_id = NEW.id AND v.recorded_until IS NULL) THEN
                RAISE EXCEPTION 'rate_schedules %: cannot activate a schedule with no open version row — insert its content first', OLD.id;
            END IF;
            NEW.activated_at := now();
        END IF;
        IF NEW.status = 'archived' THEN
            NEW.archived_at := now();
            IF OLD.status = 'draft' AND NEW.archive_reason IS DISTINCT FROM 'abandoned_draft' THEN
                RAISE EXCEPTION 'rate_schedules %: a draft is archived with archive_reason = ''abandoned_draft'' (got %)', OLD.id, NEW.archive_reason;
            END IF;
        END IF;
    ELSE
        IF NEW.archive_reason IS DISTINCT FROM OLD.archive_reason OR NEW.archived_at IS DISTINCT FROM OLD.archived_at OR NEW.activated_at IS DISTINCT FROM OLD.activated_at THEN
            RAISE EXCEPTION 'rate_schedules %: archive_reason / archived_at / activated_at change only with the status transition that sets them', OLD.id;
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS enforce_rate_schedule_lifecycle ON public.rate_schedules;
CREATE TRIGGER enforce_rate_schedule_lifecycle BEFORE INSERT OR UPDATE ON public.rate_schedules
    FOR EACH ROW EXECUTE FUNCTION public.enforce_rate_schedule_lifecycle();

DROP TRIGGER IF EXISTS enforce_reference_header ON public.rate_schedules;
CREATE TRIGGER enforce_reference_header BEFORE UPDATE OR DELETE ON public.rate_schedules
    FOR EACH ROW EXECUTE FUNCTION public.enforce_reference_header('code', 'rate_schedule_versions', 'rate_schedule_id');

-- 2.4 Version-row rules specific to rate schedules: R-9 (one service_type
--     across all open versions — a valid-time-dated service change is
--     rejected) and R-17 (a service_type correction needs its basis and,
--     when bills exist, queues a correction-scope review).
CREATE OR REPLACE FUNCTION public.enforce_rate_schedule_version_rules() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_pred              public.rate_schedule_versions%ROWTYPE;
    v_invoices          bigint;
    v_ref_service_type  text;
BEGIN
    -- 'initial' is the first assertion ever; anything after that is succession or correction
    IF NEW.change_type = 'initial' AND EXISTS (SELECT 1 FROM public.rate_schedule_versions v WHERE v.rate_schedule_id = NEW.rate_schedule_id AND v.id <> NEW.id) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('rate_schedules %s: already has versions — change_type must be succession or correction, not initial', NEW.rate_schedule_id),
            ERRCODE = 'check_violation';
    END IF;

    -- R-9: one service per schedule. The reference is every open version, or — when none is open
    -- (all closed) — the most recently closed one, so a retract-then-reassert cannot re-tag the schedule
    -- outside the R-17 path (a correction with supersedes_id + basis).
    SELECT v.service_type INTO v_ref_service_type
    FROM public.rate_schedule_versions v
    WHERE v.rate_schedule_id = NEW.rate_schedule_id AND v.id <> NEW.id
    ORDER BY (v.recorded_until IS NULL) DESC, v.recorded_until DESC NULLS LAST, v.recorded_at DESC
    LIMIT 1;
    IF v_ref_service_type IS NOT NULL AND v_ref_service_type <> NEW.service_type
       AND NOT (NEW.supersedes_id IS NOT NULL AND NEW.service_type_change_basis IS NOT NULL) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('rate_schedules %s: one schedule = one service (%s). A different service_type is only a transcription correction — supersede the open version with service_type_change_basis set (R-9 / R-17); a genuine service change is a new schedule.', NEW.rate_schedule_id, v_ref_service_type),
            ERRCODE = 'check_violation';
    END IF;
    IF EXISTS (
        SELECT 1 FROM public.rate_schedule_versions v
        WHERE v.rate_schedule_id = NEW.rate_schedule_id
          AND v.recorded_until IS NULL
          AND v.id <> NEW.id
          AND v.service_type <> NEW.service_type
    ) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('rate_schedules %s: all open versions share one service_type (R-9). A service_type change is a transcription correction over the schedule''s full valid span — close every open version first, then re-assert; a valid-time-dated service change is a different tariff, not a correction.', NEW.rate_schedule_id),
            ERRCODE = 'check_violation';
    END IF;

    IF NEW.supersedes_id IS NOT NULL THEN
        SELECT * INTO v_pred FROM public.rate_schedule_versions p WHERE p.id = NEW.supersedes_id;
        -- same-entity / already-closed checks are done by enforce_bitemporal_assertion (a_ fires first)
        IF v_pred.service_type <> NEW.service_type THEN
            -- full span only: the corrected row covers exactly the bracket it replaces
            IF NEW.effective_date <> v_pred.effective_date OR NEW.expiry_date IS DISTINCT FROM v_pred.expiry_date THEN
                RAISE EXCEPTION USING
                    MESSAGE = format('rate_schedules %s: a service_type correction keeps the predecessor''s valid bracket [%s, %s] — a service change dated in valid time is a different tariff (R-9)', NEW.rate_schedule_id, v_pred.effective_date, COALESCE(v_pred.expiry_date::text, 'open')),
                    ERRCODE = 'check_violation';
            END IF;
            IF NEW.service_type_change_basis IS NULL THEN
                RAISE EXCEPTION USING
                    MESSAGE = format('rate_schedules %s: changing service_type (%s -> %s) requires service_type_change_basis = ''transcription_error'' (R-17). Moving a customer population between regulatory regimes is a re-filing — a new schedule — not a correction.', NEW.rate_schedule_id, v_pred.service_type, NEW.service_type),
                    ERRCODE = 'check_violation';
            END IF;
            SELECT count(DISTINCT ili.invoice_id) INTO v_invoices
            FROM public.invoice_line_items ili
            WHERE ili.rate_schedule_id = NEW.rate_schedule_id;
            IF v_invoices > 0 THEN
                INSERT INTO public.anomalies (
                    tenant_id, anomaly_type, severity, status, entity_type, entity_id, description, details,
                    detection_method, detector_name, dedup_key)
                VALUES (
                    NEW.tenant_id, 'reference_correction_review', 'high', 'open', 'rate_schedule', NEW.rate_schedule_id,
                    format('service_type corrected %s -> %s on a schedule with %s invoiced bill(s): rule on correction scope (RRC: no de minimis exception for gas billing errors)', v_pred.service_type, NEW.service_type, v_invoices),
                    jsonb_build_object(
                        'predecessor_version_id', v_pred.id,
                        'new_version_id', NEW.id,
                        'old_service_type', v_pred.service_type,
                        'new_service_type', NEW.service_type,
                        'invoices_affected', v_invoices,
                        'basis', NEW.service_type_change_basis,
                        'change_reason', NEW.change_reason,
                        'changed_by', NEW.changed_by),
                    'rule_based', 'v5.4.2-03 rate_schedule_versions service_type correction (R-17)',
                    'reference_correction_review:rate_schedule:' || NEW.rate_schedule_id::text || ':' || NEW.id::text);
            END IF;
        ELSIF NEW.service_type_change_basis IS NOT NULL THEN
            RAISE EXCEPTION 'rate_schedule_versions: service_type_change_basis is set but service_type did not change from the superseded row';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS a_enforce_bitemporal_assertion ON public.rate_schedule_versions;
CREATE TRIGGER a_enforce_bitemporal_assertion BEFORE INSERT OR UPDATE OR DELETE ON public.rate_schedule_versions
    FOR EACH ROW EXECUTE FUNCTION public.enforce_bitemporal_assertion('', 'rate_schedule_id', 'rate_schedules');
DROP TRIGGER IF EXISTS b_enforce_rate_schedule_version_rules ON public.rate_schedule_versions;
CREATE TRIGGER b_enforce_rate_schedule_version_rules BEFORE INSERT ON public.rate_schedule_versions
    FOR EACH ROW EXECUTE FUNCTION public.enforce_rate_schedule_version_rules();
DROP TRIGGER IF EXISTS enforce_superseded_has_successor ON public.rate_schedule_versions;
CREATE CONSTRAINT TRIGGER enforce_superseded_has_successor AFTER UPDATE ON public.rate_schedule_versions
    DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.enforce_superseded_has_successor('rate_schedule_id');

-- the anomalies queue gains the review type R-17 posts into
ALTER TABLE public.anomalies DROP CONSTRAINT IF EXISTS anomalies_anomaly_type_check;
ALTER TABLE public.anomalies ADD CONSTRAINT anomalies_anomaly_type_check
    CHECK ((anomaly_type = ANY (ARRAY['high_usage'::text, 'low_usage'::text, 'zero_usage'::text, 'negative_consumption'::text, 'possible_leak'::text, 'stuck_meter'::text, 'meter_rollover'::text, 'tamper_detected'::text, 'endpoint_offline'::text, 'repeated_access_issue'::text, 'endpoint_swap_unreported'::text, 'missing_reading'::text, 'estimated_streak'::text, 'partial_period_anomaly'::text, 'unbilled_service'::text, 'unbilled_usage'::text, 'rate_mismatch'::text, 'rate_schedule_mismatch'::text, 'billing_run_exception'::text, 'revenue_leakage'::text, 'duplicate_account'::text, 'address_mismatch'::text, 'stale_account'::text, 'unusual_payment_pattern'::text, 'auto_pay_failure_streak'::text, 'payment_method_expiring'::text, 'multiple_nsf_pattern'::text, 'credit_balance_stale'::text, 'deposit_refund_overdue'::text, 'escheatment_due'::text, 'escheatment_overdue'::text, 'tax_exemption_expired'::text, 'disconnect_protection_expiring'::text, 'import_column_outlier_pattern'::text, 'import_low_confidence_mapping'::text, 'reference_correction_review'::text, 'other'::text])));

-- 2.5 R-14 rider 2: a draft schedule is not assignable.
CREATE OR REPLACE FUNCTION public.enforce_rate_schedule_assignable() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_status text;
BEGIN
    IF NEW.rate_schedule_id IS NULL THEN RETURN NEW; END IF;
    IF TG_OP = 'UPDATE' AND NEW.rate_schedule_id IS NOT DISTINCT FROM OLD.rate_schedule_id THEN RETURN NEW; END IF;
    SELECT rs.status INTO v_status FROM public.rate_schedules rs WHERE rs.id = NEW.rate_schedule_id;
    IF v_status = 'draft' THEN
        RAISE EXCEPTION USING
            MESSAGE = format('%s: rate schedule %s is a draft and cannot be assigned (R-14); activate it first', TG_TABLE_NAME, NEW.rate_schedule_id),
            ERRCODE = 'check_violation';
    END IF;
    IF v_status = 'archived' THEN
        RAISE EXCEPTION USING
            MESSAGE = format('%s: rate schedule %s is archived and cannot be assigned', TG_TABLE_NAME, NEW.rate_schedule_id),
            ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS enforce_rate_schedule_assignable ON public.meters;
CREATE TRIGGER enforce_rate_schedule_assignable BEFORE INSERT OR UPDATE OF rate_schedule_id ON public.meters
    FOR EACH ROW EXECUTE FUNCTION public.enforce_rate_schedule_assignable();
DROP TRIGGER IF EXISTS enforce_rate_schedule_assignable ON public.meter_deployments;
CREATE TRIGGER enforce_rate_schedule_assignable BEFORE INSERT OR UPDATE OF rate_schedule_id ON public.meter_deployments
    FOR EACH ROW EXECUTE FUNCTION public.enforce_rate_schedule_assignable();

COMMENT ON TABLE public.rate_schedules IS
    'Identity header of a rate schedule (A-1, v5.4.2-03): id, tenant_id, code, created_at are immutable; every FK in the schema (meters, meter_deployments, invoice_line_items, rate_schedule_items, rate_item_dependencies) keeps pointing here. Content — name, service_type, customer_type, zone, tariff references, sewer/gas/estimation/partial-period settings, the valid-time bracket — lives on rate_schedule_versions as bi-temporal assertions. status is the entity lifecycle (draft | active | archived; ''expired'' was dropped — valid-time expiry is the version''s expiry_date). Abandoned drafts persist as archived / abandoned_draft (R-14). version is the CI-011 optimistic token — bump it through assert_reference_version(). Codes are unique per tenant across services (R-10): namespace by convention (GAS-R1, WTR-R1); the filed designation is the version''s tariff_number.';
COMMENT ON COLUMN public.rate_schedules.archive_reason IS
    'Required exactly when status = ''archived'' (R-14 rider 1). abandoned_draft = never went live (activated_at NULL); superseded_by_filing / service_discontinued = went live and ended (activated_at set). Tariff-history exports treat the two groups differently.';
COMMENT ON COLUMN public.rate_schedules.version IS
    'CI-011 optimistic-concurrency token (D1-1). A client carries (id, version) from its read; assert_reference_version(''rate_schedules'', id, version) bumps it — 0 rows means a stale write and raises. Also row-locks the header, serialising concurrent writers on the entity.';
COMMENT ON TABLE public.rate_schedule_versions IS
    'Bi-temporal content of a rate schedule (A-1, v5.4.2-03). Valid time: [effective_date, expiry_date] (date, inclusive; NULL = open). Transaction time: [recorded_at, recorded_until) (timestamptz; NULL = current knowledge). One open row per schedule per valid-time point (exclusion constraint). Rows are never edited: a correction closes the row (closed_type = superseded) and inserts the corrected row with supersedes_id; a retraction closes with closed_type = retracted and no successor (deferred trigger enforces the pairing). Read through rate_schedule_as_of(id, p_valid_at, p_recorded_at) — never with WHERE effective_date <= X alone. Backfill rows (change_type = backfill) are the content observed at deploy stamped at created_at, an approximation.';
COMMENT ON COLUMN public.rate_schedule_versions.service_type IS
    'Versioned (R-9): a mis-tag is corrected as a transcription error over the schedule''s full valid span — all open versions must agree (trigger). A change requires service_type_change_basis; if invoices exist it also queues an anomalies row (reference_correction_review) so an operator rules on correction scope (R-17). A genuine service change is a new schedule.';
COMMENT ON COLUMN public.rate_schedule_versions.service_type_change_basis IS
    'Required when this row changes service_type from the row it supersedes; the only legal value is transcription_error (R-17). A re-tag intended to move customers between regulatory regimes is a re-filing and is not available on this path.';
COMMENT ON COLUMN public.rate_schedule_versions.gas_usage_formula IS
    'Drives Phase 3 gas consumption calculation:
             standard          — consumption = (current - previous) * multiplier
             with_meter_factor — consumption = (current - previous) * multiplier * meter_factor
             with_temp_factor  — consumption = (current - previous) * multiplier * meter_factor * seasonal_temp_factor
                                  where seasonal_temp_factor is the product of all rate items with
                                  calculation_type = usage_modifier on this rate schedule, each resolved with
                                  rate_item_as_of(rate_item_id, period_end, <run''s recorded_at>) (v5.4.2-03 —
                                  the pre-A-1 comment named rate_item_history_archive, the retired overflow table).
             Result rounded to unit-specific precision (MCF/CCF/therms = 1 decimal; gallons/kWh = whole).';
COMMENT ON COLUMN public.rate_schedule_versions.change_type IS
    'Event that produced this row: initial (first assertion for the entity), succession (a scheduled, non-corrective change — e.g. a rate effective next January; the prior open row is closed and re-asserted with an expiry_date), correction (the prior assertion was wrong at the same valid time; change_reason required), backfill (v5.4.2-03 migration; approximation). Retraction is not an insert event — it is closed_type = retracted on the closed row.';
COMMENT ON COLUMN public.rate_schedule_versions.supersedes_id IS
    'Lineage: the row this one replaces (closed first, with closed_type = superseded). NULL for initial/backfill rows and for a succession that adds a new bracket without replacing one.';

-- ----------------------------------------------------------------------------
-- 3. Group 1 — wna_zones: header + wna_zone_versions
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.wna_zone_versions (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id uuid NOT NULL,
    wna_zone_id uuid NOT NULL,
    zone_name text NOT NULL,
    description text,
    active_months integer[] DEFAULT '{11,12,1,2,3,4}'::integer[] NOT NULL,
    normal_hdd numeric(10,2),
    base_load_consumption numeric(10,4),
    heating_factor numeric(10,6),
    calculation_notes text,
    weather_station_name text,
    weather_station_id text,
    calc_owner text,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    wna_adjustment_floor numeric(14,6),
    wna_adjustment_ceiling numeric(14,6),
    wna_clamp_basis text,
    effective_date date NOT NULL,
    expiry_date date,
    recorded_at timestamp with time zone DEFAULT now() NOT NULL,
    recorded_until timestamp with time zone,
    change_type text NOT NULL,
    change_reason text,
    changed_by uuid,
    supersedes_id uuid,
    closed_type text,
    closed_reason text,
    closed_by uuid,
    CONSTRAINT wna_zone_versions_pkey PRIMARY KEY (id),
    CONSTRAINT wna_zone_versions_clamp_basis_check CHECK ((wna_clamp_basis IS NULL) OR (wna_clamp_basis = ANY (ARRAY['percent_of_base'::text, 'dollars'::text]))),
    CONSTRAINT wna_zone_versions_clamp_basis_required_check CHECK (((wna_adjustment_floor IS NULL) AND (wna_adjustment_ceiling IS NULL)) OR (wna_clamp_basis IS NOT NULL)),
    CONSTRAINT wna_zone_versions_floor_le_ceiling_check CHECK ((wna_adjustment_floor IS NULL) OR (wna_adjustment_ceiling IS NULL) OR (wna_adjustment_floor <= wna_adjustment_ceiling)),
    CONSTRAINT wna_zone_versions_valid_bracket_check CHECK ((expiry_date IS NULL) OR (expiry_date >= effective_date)),
    CONSTRAINT wna_zone_versions_change_type_check CHECK ((change_type = ANY (ARRAY['initial'::text, 'succession'::text, 'correction'::text, 'backfill'::text]))),
    CONSTRAINT wna_zone_versions_correction_reason_check CHECK ((change_type <> 'correction') OR (change_reason IS NOT NULL)),
    CONSTRAINT wna_zone_versions_supersedes_check CHECK ((supersedes_id IS NULL) OR (change_type = 'succession') OR (change_type = 'correction')),
    CONSTRAINT wna_zone_versions_closed_type_check CHECK ((closed_type IS NULL) OR (closed_type = ANY (ARRAY['superseded'::text, 'retracted'::text]))),
    CONSTRAINT wna_zone_versions_close_consistent_check CHECK (((recorded_until IS NULL) AND (closed_type IS NULL) AND (closed_reason IS NULL) AND (closed_by IS NULL)) OR ((recorded_until IS NOT NULL) AND (closed_type IS NOT NULL) AND (closed_reason IS NOT NULL) AND (recorded_until >= recorded_at)))
);

ALTER TABLE public.wna_zone_versions DROP CONSTRAINT IF EXISTS wna_zone_versions_tenant_id_fkey;
ALTER TABLE public.wna_zone_versions ADD CONSTRAINT wna_zone_versions_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id);
ALTER TABLE public.wna_zone_versions DROP CONSTRAINT IF EXISTS wna_zone_versions_wna_zone_id_fkey;
ALTER TABLE public.wna_zones DROP CONSTRAINT IF EXISTS wna_zones_id_tenant_id_key;
ALTER TABLE public.wna_zones ADD CONSTRAINT wna_zones_id_tenant_id_key UNIQUE (id, tenant_id);
ALTER TABLE public.wna_zone_versions ADD CONSTRAINT wna_zone_versions_wna_zone_id_fkey FOREIGN KEY (wna_zone_id, tenant_id) REFERENCES public.wna_zones(id, tenant_id);
ALTER TABLE public.wna_zone_versions DROP CONSTRAINT IF EXISTS wna_zone_versions_changed_by_fkey;
ALTER TABLE public.wna_zone_versions ADD CONSTRAINT wna_zone_versions_changed_by_fkey FOREIGN KEY (changed_by) REFERENCES public.users(id);
ALTER TABLE public.wna_zone_versions DROP CONSTRAINT IF EXISTS wna_zone_versions_closed_by_fkey;
ALTER TABLE public.wna_zone_versions ADD CONSTRAINT wna_zone_versions_closed_by_fkey FOREIGN KEY (closed_by) REFERENCES public.users(id);
ALTER TABLE public.wna_zone_versions DROP CONSTRAINT IF EXISTS wna_zone_versions_supersedes_id_fkey;
ALTER TABLE public.wna_zone_versions ADD CONSTRAINT wna_zone_versions_supersedes_id_fkey FOREIGN KEY (supersedes_id) REFERENCES public.wna_zone_versions(id);
ALTER TABLE public.wna_zone_versions DROP CONSTRAINT IF EXISTS wna_zone_versions_open_no_overlap_excl;
ALTER TABLE public.wna_zone_versions ADD CONSTRAINT wna_zone_versions_open_no_overlap_excl
    EXCLUDE USING gist (wna_zone_id WITH =, daterange(effective_date, expiry_date, '[]') WITH &&) WHERE (recorded_until IS NULL);

CREATE INDEX IF NOT EXISTS idx_wna_zone_versions_open ON public.wna_zone_versions USING btree (wna_zone_id, effective_date DESC) WHERE (recorded_until IS NULL);
CREATE INDEX IF NOT EXISTS idx_wna_zone_versions_lineage ON public.wna_zone_versions USING btree (wna_zone_id, recorded_at DESC);
CREATE INDEX IF NOT EXISTS idx_wna_zone_versions_tenant ON public.wna_zone_versions USING btree (tenant_id);
CREATE INDEX IF NOT EXISTS idx_wna_zone_versions_supersedes ON public.wna_zone_versions USING btree (supersedes_id) WHERE (supersedes_id IS NOT NULL);

ALTER TABLE public.wna_zone_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.wna_zone_versions FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_isolation ON public.wna_zone_versions;
CREATE POLICY tenant_isolation ON public.wna_zone_versions USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));

DO $$
BEGIN
    -- wna_zones backfill: only while the header still carries the content columns (re-runnable)
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'wna_zones' AND column_name = 'zone_name') THEN
        EXECUTE $q$
INSERT INTO public.wna_zone_versions (
    tenant_id, wna_zone_id, zone_name, description, active_months, normal_hdd, base_load_consumption, heating_factor,
    calculation_notes, weather_station_name, weather_station_id, calc_owner, metadata,
    wna_adjustment_floor, wna_adjustment_ceiling, wna_clamp_basis, effective_date, expiry_date, recorded_at, change_type, change_reason)
SELECT
    z.tenant_id, z.id, z.zone_name, z.description, z.active_months, z.normal_hdd, z.base_load_consumption, z.heating_factor,
    z.calculation_notes, z.weather_station_name, z.weather_station_id, z.calc_owner, z.metadata,
    z.wna_adjustment_floor, z.wna_adjustment_ceiling, z.wna_clamp_basis, z.effective_date, z.expiry_date, z.created_at, 'backfill',
    'v5.4.2-03 backfill: content observed at deploy, stamped at wna_zones.created_at as an approximation — earlier versions are unknown'
FROM public.wna_zones z
WHERE NOT EXISTS (SELECT 1 FROM public.wna_zone_versions v WHERE v.wna_zone_id = z.id)
        $q$;
    END IF;
END;
$$;

ALTER TABLE public.wna_zones
    DROP COLUMN IF EXISTS zone_name,
    DROP COLUMN IF EXISTS description,
    DROP COLUMN IF EXISTS active_months,
    DROP COLUMN IF EXISTS normal_hdd,
    DROP COLUMN IF EXISTS base_load_consumption,
    DROP COLUMN IF EXISTS heating_factor,
    DROP COLUMN IF EXISTS calculation_notes,
    DROP COLUMN IF EXISTS weather_station_name,
    DROP COLUMN IF EXISTS weather_station_id,
    DROP COLUMN IF EXISTS effective_date,
    DROP COLUMN IF EXISTS expiry_date,
    DROP COLUMN IF EXISTS calc_owner,
    DROP COLUMN IF EXISTS metadata,
    DROP COLUMN IF EXISTS wna_adjustment_floor,
    DROP COLUMN IF EXISTS wna_adjustment_ceiling,
    DROP COLUMN IF EXISTS wna_clamp_basis;
ALTER TABLE public.wna_zones ADD COLUMN IF NOT EXISTS version integer DEFAULT 1 NOT NULL;
ALTER TABLE public.wna_zones DROP CONSTRAINT IF EXISTS wna_zones_version_check;
ALTER TABLE public.wna_zones ADD CONSTRAINT wna_zones_version_check CHECK ((version >= 1));

DROP TRIGGER IF EXISTS enforce_reference_header ON public.wna_zones;
CREATE TRIGGER enforce_reference_header BEFORE UPDATE OR DELETE ON public.wna_zones
    FOR EACH ROW EXECUTE FUNCTION public.enforce_reference_header('zone_code', 'wna_zone_versions', 'wna_zone_id');
DROP TRIGGER IF EXISTS a_enforce_bitemporal_assertion ON public.wna_zone_versions;
CREATE TRIGGER a_enforce_bitemporal_assertion BEFORE INSERT OR UPDATE OR DELETE ON public.wna_zone_versions
    FOR EACH ROW EXECUTE FUNCTION public.enforce_bitemporal_assertion('', 'wna_zone_id', 'wna_zones');
DROP TRIGGER IF EXISTS enforce_superseded_has_successor ON public.wna_zone_versions;
CREATE CONSTRAINT TRIGGER enforce_superseded_has_successor AFTER UPDATE ON public.wna_zone_versions
    DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.enforce_superseded_has_successor('wna_zone_id');

COMMENT ON TABLE public.wna_zones IS
    'Identity header of a WNA zone (A-1, v5.4.2-03): id, tenant_id, zone_code, created_at immutable; status (active | paused | archived) is operational lifecycle; version is the CI-011 token. Weather station, normal HDD, factors, active months and the T-4 clamp bounds live on wna_zone_versions — a station remap or an HDD-normal restatement is a dated assertion, reproducible for every bill that used it. wna_clamp_events.wna_zone_id keeps pointing here (provenance is recoverable through wna_zone_as_of at the event''s coordinates, and the event snapshots its bounds).';
COMMENT ON TABLE public.wna_zone_versions IS
    'Bi-temporal content of a WNA zone (A-1, v5.4.2-03). Same contract as rate_schedule_versions: valid [effective_date, expiry_date] inclusive dates, transaction [recorded_at, recorded_until), one open row per zone per valid point, never edited, correction = close + insert with supersedes_id, retraction = close as retracted. Read through wna_zone_as_of(id, p_valid_at, p_recorded_at).';
COMMENT ON COLUMN public.wna_zone_versions.wna_adjustment_floor IS
    'Lower clamp bound for a bill''s WNA adjustment (T-4, v5.4.0-03; versioned by A-1), in wna_clamp_basis units. Nullable by ruling — no forced value; the application should raise a config-time warning when left NULL. When the raw computed adjustment falls below it, the adjustment is clamped and a wna_clamp_events row posts.';
COMMENT ON COLUMN public.wna_zone_versions.wna_adjustment_ceiling IS
    'Upper clamp bound for a bill''s WNA adjustment (T-4, v5.4.0-03; versioned by A-1), in wna_clamp_basis units. Same contract as wna_adjustment_floor. The PGW 2022 low-usage-boundary pathology is the reason this exists; under monthly-settled WNA (D5-1) the clamp is the only guard.';
COMMENT ON COLUMN public.wna_zone_versions.wna_clamp_basis IS
    'Units of the floor/ceiling (T-4): percent_of_base (percent of the bill''s base distribution charge) or dollars. Tenant''s choice per their tariff. Required whenever either bound is set (enforced).';

-- ----------------------------------------------------------------------------
-- 4. Group 1 — rate_items: header + rate_item_versions; rate_item_history retired
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.rate_item_versions (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id uuid NOT NULL,
    rate_item_id uuid NOT NULL,
    item_name text NOT NULL,
    description text,
    service_type text NOT NULL,
    calculation_type text NOT NULL,
    rate_value numeric(14,6),
    rate_unit text,
    active_months integer[] DEFAULT '{1,2,3,4,5,6,7,8,9,10,11,12}'::integer[] NOT NULL,
    applies_to_customer_types text[] DEFAULT '{residential,commercial,industrial,government,wholesale}'::text[] NOT NULL,
    update_frequency text,
    calc_owner text,
    is_taxable_default boolean DEFAULT false NOT NULL,
    is_a_tax boolean DEFAULT false NOT NULL,
    display_name text,
    display_group text,
    notes text,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    tier_config jsonb,
    annual_billing_anchor integer,
    regulatory_class text NOT NULL,
    regulatory_reference text,
    effective_date date NOT NULL,
    expiry_date date,
    recorded_at timestamp with time zone DEFAULT now() NOT NULL,
    recorded_until timestamp with time zone,
    change_type text NOT NULL,
    change_reason text,
    changed_by uuid,
    supersedes_id uuid,
    closed_type text,
    closed_reason text,
    closed_by uuid,
    CONSTRAINT rate_item_versions_pkey PRIMARY KEY (id),
    CONSTRAINT rate_item_versions_annual_billing_anchor_check CHECK (((annual_billing_anchor IS NULL) OR ((annual_billing_anchor >= 1) AND (annual_billing_anchor <= 12)))),
    CONSTRAINT rate_item_versions_calc_owner_check CHECK ((calc_owner = ANY (ARRAY['regulatory'::text, 'gas_marketing'::text, 'accounting'::text, 'finance'::text, 'strategic_finance'::text, 'state_of_tx'::text, 'external'::text, 'operations'::text, 'other'::text]))),
    CONSTRAINT rate_item_versions_calculation_type_check CHECK ((calculation_type = ANY (ARRAY['fixed_monthly'::text, 'fixed_annual'::text, 'per_unit_usage'::text, 'percentage_of_bill'::text, 'percentage_of_charges'::text, 'usage_modifier'::text, 'tiered_usage'::text, 'formula'::text]))),
    CONSTRAINT rate_item_versions_display_group_check CHECK ((display_group = ANY (ARRAY['base_charges'::text, 'usage_charges'::text, 'riders'::text, 'taxes_fees'::text, 'adjustments'::text, 'other'::text]))),
    CONSTRAINT rate_item_versions_rate_unit_check CHECK ((rate_unit = ANY (ARRAY['flat'::text, 'per_month'::text, 'per_year'::text, 'per_day'::text, 'per_gallon'::text, 'per_kgal'::text, 'per_ccf'::text, 'per_mcf'::text, 'per_therm'::text, 'per_kwh'::text, 'per_cubic_meter'::text, 'percent'::text, 'decimal'::text]))),
    CONSTRAINT rate_item_versions_service_type_check CHECK ((service_type = ANY (ARRAY['water'::text, 'sewer'::text, 'electric'::text, 'gas'::text, 'stormwater'::text, 'trash'::text, 'reclaimed_water'::text, 'all'::text]))),
    CONSTRAINT rate_item_versions_tier_config_required_for_tiered CHECK (((calculation_type <> 'tiered_usage'::text) OR ((tier_config IS NOT NULL) AND (jsonb_typeof((tier_config -> 'tiers'::text)) = 'array'::text)))),
    CONSTRAINT rate_item_versions_update_frequency_check CHECK ((update_frequency = ANY (ARRAY['never'::text, 'monthly'::text, 'quarterly'::text, 'annually'::text, 'on_rate_case'::text, 'as_needed'::text]))),
    CONSTRAINT rate_item_versions_regulatory_class_check CHECK ((regulatory_class = ANY (ARRAY['regulated'::text, 'unregulated'::text]))),
    CONSTRAINT rate_item_versions_valid_bracket_check CHECK ((expiry_date IS NULL) OR (expiry_date >= effective_date)),
    CONSTRAINT rate_item_versions_change_type_check CHECK ((change_type = ANY (ARRAY['initial'::text, 'succession'::text, 'correction'::text, 'backfill'::text]))),
    CONSTRAINT rate_item_versions_correction_reason_check CHECK ((change_type <> 'correction') OR (change_reason IS NOT NULL)),
    CONSTRAINT rate_item_versions_supersedes_check CHECK ((supersedes_id IS NULL) OR (change_type = 'succession') OR (change_type = 'correction')),
    CONSTRAINT rate_item_versions_closed_type_check CHECK ((closed_type IS NULL) OR (closed_type = ANY (ARRAY['superseded'::text, 'retracted'::text]))),
    CONSTRAINT rate_item_versions_close_consistent_check CHECK (((recorded_until IS NULL) AND (closed_type IS NULL) AND (closed_reason IS NULL) AND (closed_by IS NULL)) OR ((recorded_until IS NOT NULL) AND (closed_type IS NOT NULL) AND (closed_reason IS NOT NULL) AND (recorded_until >= recorded_at)))
);

ALTER TABLE public.rate_item_versions DROP CONSTRAINT IF EXISTS rate_item_versions_tenant_id_fkey;
ALTER TABLE public.rate_item_versions ADD CONSTRAINT rate_item_versions_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id);
ALTER TABLE public.rate_item_versions DROP CONSTRAINT IF EXISTS rate_item_versions_rate_item_id_fkey;
ALTER TABLE public.rate_items DROP CONSTRAINT IF EXISTS rate_items_id_tenant_id_key;
ALTER TABLE public.rate_items ADD CONSTRAINT rate_items_id_tenant_id_key UNIQUE (id, tenant_id);
ALTER TABLE public.rate_item_versions ADD CONSTRAINT rate_item_versions_rate_item_id_fkey FOREIGN KEY (rate_item_id, tenant_id) REFERENCES public.rate_items(id, tenant_id);
ALTER TABLE public.rate_item_versions DROP CONSTRAINT IF EXISTS rate_item_versions_changed_by_fkey;
ALTER TABLE public.rate_item_versions ADD CONSTRAINT rate_item_versions_changed_by_fkey FOREIGN KEY (changed_by) REFERENCES public.users(id);
ALTER TABLE public.rate_item_versions DROP CONSTRAINT IF EXISTS rate_item_versions_closed_by_fkey;
ALTER TABLE public.rate_item_versions ADD CONSTRAINT rate_item_versions_closed_by_fkey FOREIGN KEY (closed_by) REFERENCES public.users(id);
ALTER TABLE public.rate_item_versions DROP CONSTRAINT IF EXISTS rate_item_versions_supersedes_id_fkey;
ALTER TABLE public.rate_item_versions ADD CONSTRAINT rate_item_versions_supersedes_id_fkey FOREIGN KEY (supersedes_id) REFERENCES public.rate_item_versions(id);
ALTER TABLE public.rate_item_versions DROP CONSTRAINT IF EXISTS rate_item_versions_open_no_overlap_excl;
ALTER TABLE public.rate_item_versions ADD CONSTRAINT rate_item_versions_open_no_overlap_excl
    EXCLUDE USING gist (rate_item_id WITH =, daterange(effective_date, expiry_date, '[]') WITH &&) WHERE (recorded_until IS NULL);

CREATE INDEX IF NOT EXISTS idx_rate_item_versions_open ON public.rate_item_versions USING btree (rate_item_id, effective_date DESC) WHERE (recorded_until IS NULL);
CREATE INDEX IF NOT EXISTS idx_rate_item_versions_lineage ON public.rate_item_versions USING btree (rate_item_id, recorded_at DESC);
CREATE INDEX IF NOT EXISTS idx_rate_item_versions_tenant ON public.rate_item_versions USING btree (tenant_id);
CREATE INDEX IF NOT EXISTS idx_rate_item_versions_service ON public.rate_item_versions USING btree (tenant_id, service_type) WHERE (recorded_until IS NULL);
CREATE INDEX IF NOT EXISTS idx_rate_item_versions_supersedes ON public.rate_item_versions USING btree (supersedes_id) WHERE (supersedes_id IS NOT NULL);

ALTER TABLE public.rate_item_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rate_item_versions FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_isolation ON public.rate_item_versions;
CREATE POLICY tenant_isolation ON public.rate_item_versions USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));

-- 4.1 Backfill. Items with no rate_item_history: one row from the live values.
--     Items with history: one row per history bracket (rate_value/rate_unit
--     from history, every other column from the live row — flagged), plus a
--     live-values row after the last closed bracket if no history row is
--     open-ended. The exclusion constraint validates the migration. Each step
--     runs only while rate_items still carries current_rate (re-runnable).
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'rate_items' AND column_name = 'current_rate') THEN
        -- (a) no history: live row
        EXECUTE $q$
INSERT INTO public.rate_item_versions (
    tenant_id, rate_item_id, item_name, description, service_type, calculation_type, rate_value, rate_unit,
    active_months, applies_to_customer_types, update_frequency, calc_owner, is_taxable_default, is_a_tax,
    display_name, display_group, notes, metadata, tier_config, annual_billing_anchor, regulatory_class,
    effective_date, expiry_date, recorded_at, change_type, change_reason)
SELECT
    ri.tenant_id, ri.id, ri.item_name, ri.description, ri.service_type, ri.calculation_type, ri.current_rate, ri.rate_unit,
    ri.active_months, ri.applies_to_customer_types, ri.update_frequency, ri.calc_owner, ri.is_taxable_default, ri.is_a_tax,
    ri.display_name, ri.display_group, ri.notes, ri.metadata, ri.tier_config, ri.annual_billing_anchor, ri.regulatory_class,
    ri.effective_date, ri.expiry_date, ri.created_at, 'backfill',
    'v5.4.2-03 backfill: live rate_items row observed at deploy (current_rate -> rate_value), stamped at created_at as an approximation'
FROM public.rate_items ri
WHERE NOT EXISTS (SELECT 1 FROM public.rate_item_history h WHERE h.rate_item_id = ri.id)
  AND NOT EXISTS (SELECT 1 FROM public.rate_item_versions v WHERE v.rate_item_id = ri.id)
        $q$;

        -- (b) history brackets
        EXECUTE $q$
INSERT INTO public.rate_item_versions (
    tenant_id, rate_item_id, item_name, description, service_type, calculation_type, rate_value, rate_unit,
    active_months, applies_to_customer_types, update_frequency, calc_owner, is_taxable_default, is_a_tax,
    display_name, display_group, notes, metadata, tier_config, annual_billing_anchor, regulatory_class, regulatory_reference,
    effective_date, expiry_date, recorded_at, change_type, change_reason, changed_by)
SELECT
    ri.tenant_id, ri.id, ri.item_name, ri.description, ri.service_type, ri.calculation_type, h.rate_value, COALESCE(h.rate_unit, ri.rate_unit),
    ri.active_months, ri.applies_to_customer_types, ri.update_frequency, ri.calc_owner, ri.is_taxable_default, ri.is_a_tax,
    ri.display_name, ri.display_group, h.notes, h.metadata, ri.tier_config, ri.annual_billing_anchor, ri.regulatory_class, h.regulatory_reference,
    h.effective_date, h.end_date, h.created_at, 'backfill',
    'v5.4.2-03 backfill from rate_item_history ' || h.id::text || ': rate_value/rate_unit are genuine history; every other column is the live rate_items value at deploy (rate_item_history never tracked them) — approximation'
        || COALESCE(' — original change_reason: ' || h.change_reason, ''),
    h.changed_by
FROM public.rate_item_history h
JOIN public.rate_items ri ON ri.id = h.rate_item_id
WHERE NOT EXISTS (SELECT 1 FROM public.rate_item_versions v WHERE v.rate_item_id = ri.id)
        $q$;

        -- (c) live row after the last closed bracket, when no history row is open-ended
        EXECUTE $q$
INSERT INTO public.rate_item_versions (
    tenant_id, rate_item_id, item_name, description, service_type, calculation_type, rate_value, rate_unit,
    active_months, applies_to_customer_types, update_frequency, calc_owner, is_taxable_default, is_a_tax,
    display_name, display_group, notes, metadata, tier_config, annual_billing_anchor, regulatory_class,
    effective_date, expiry_date, recorded_at, change_type, change_reason)
SELECT
    ri.tenant_id, ri.id, ri.item_name, ri.description, ri.service_type, ri.calculation_type, ri.current_rate, ri.rate_unit,
    ri.active_months, ri.applies_to_customer_types, ri.update_frequency, ri.calc_owner, ri.is_taxable_default, ri.is_a_tax,
    ri.display_name, ri.display_group, ri.notes, ri.metadata, ri.tier_config, ri.annual_billing_anchor, ri.regulatory_class,
    GREATEST(ri.effective_date, (SELECT max(h.end_date) + 1 FROM public.rate_item_history h WHERE h.rate_item_id = ri.id)), ri.expiry_date, ri.created_at, 'backfill',
    'v5.4.2-03 backfill: live rate_items row after the last closed rate_item_history bracket (no open-ended history row existed) — approximation'
FROM public.rate_items ri
WHERE EXISTS (SELECT 1 FROM public.rate_item_history h WHERE h.rate_item_id = ri.id)
  AND NOT EXISTS (SELECT 1 FROM public.rate_item_history h WHERE h.rate_item_id = ri.id AND h.end_date IS NULL)
  AND NOT EXISTS (SELECT 1 FROM public.rate_item_versions v WHERE v.rate_item_id = ri.id AND v.expiry_date IS NULL)
        $q$;
    END IF;
END;
$$;

-- 4.2 Header sheds content (current_rate included — dropped, not cached).
ALTER TABLE public.rate_items
    DROP COLUMN IF EXISTS item_name,
    DROP COLUMN IF EXISTS description,
    DROP COLUMN IF EXISTS service_type,
    DROP COLUMN IF EXISTS calculation_type,
    DROP COLUMN IF EXISTS current_rate,
    DROP COLUMN IF EXISTS rate_unit,
    DROP COLUMN IF EXISTS active_months,
    DROP COLUMN IF EXISTS applies_to_customer_types,
    DROP COLUMN IF EXISTS update_frequency,
    DROP COLUMN IF EXISTS calc_owner,
    DROP COLUMN IF EXISTS is_taxable_default,
    DROP COLUMN IF EXISTS is_a_tax,
    DROP COLUMN IF EXISTS display_name,
    DROP COLUMN IF EXISTS display_group,
    DROP COLUMN IF EXISTS effective_date,
    DROP COLUMN IF EXISTS expiry_date,
    DROP COLUMN IF EXISTS notes,
    DROP COLUMN IF EXISTS metadata,
    DROP COLUMN IF EXISTS tier_config,
    DROP COLUMN IF EXISTS annual_billing_anchor,
    DROP COLUMN IF EXISTS regulatory_class;
ALTER TABLE public.rate_items ADD COLUMN IF NOT EXISTS version integer DEFAULT 1 NOT NULL;
ALTER TABLE public.rate_items DROP CONSTRAINT IF EXISTS rate_items_version_check;
ALTER TABLE public.rate_items ADD CONSTRAINT rate_items_version_check CHECK ((version >= 1));

DROP TRIGGER IF EXISTS enforce_reference_header ON public.rate_items;
CREATE TRIGGER enforce_reference_header BEFORE UPDATE OR DELETE ON public.rate_items
    FOR EACH ROW EXECUTE FUNCTION public.enforce_reference_header('item_code', 'rate_item_versions', 'rate_item_id');
DROP TRIGGER IF EXISTS a_enforce_bitemporal_assertion ON public.rate_item_versions;
CREATE TRIGGER a_enforce_bitemporal_assertion BEFORE INSERT OR UPDATE OR DELETE ON public.rate_item_versions
    FOR EACH ROW EXECUTE FUNCTION public.enforce_bitemporal_assertion('', 'rate_item_id', 'rate_items');
DROP TRIGGER IF EXISTS enforce_superseded_has_successor ON public.rate_item_versions;
CREATE CONSTRAINT TRIGGER enforce_superseded_has_successor AFTER UPDATE ON public.rate_item_versions
    DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.enforce_superseded_has_successor('rate_item_id');

-- 4.3 rate_item_history / _archive retired: read-only migration source.
CREATE OR REPLACE FUNCTION public.enforce_retired_read_only() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    RAISE EXCEPTION USING
        MESSAGE = format('%s is retired (v5.4.2-03, A-1): it is a read-only migration source. Rate history lives in rate_item_versions.', TG_TABLE_NAME),
        ERRCODE = 'restrict_violation';
END;
$$;

DROP TRIGGER IF EXISTS retired_read_only ON public.rate_item_history;
CREATE TRIGGER retired_read_only BEFORE INSERT OR UPDATE OR DELETE ON public.rate_item_history
    FOR EACH ROW EXECUTE FUNCTION public.enforce_retired_read_only();
DROP TRIGGER IF EXISTS retired_no_truncate ON public.rate_item_history;
CREATE TRIGGER retired_no_truncate BEFORE TRUNCATE ON public.rate_item_history
    FOR EACH STATEMENT EXECUTE FUNCTION public.enforce_retired_read_only();
DROP TRIGGER IF EXISTS retired_read_only ON public.rate_item_history_archive;
CREATE TRIGGER retired_read_only BEFORE INSERT OR UPDATE OR DELETE ON public.rate_item_history_archive
    FOR EACH ROW EXECUTE FUNCTION public.enforce_retired_read_only();
DROP TRIGGER IF EXISTS retired_no_truncate ON public.rate_item_history_archive;
CREATE TRIGGER retired_no_truncate BEFORE TRUNCATE ON public.rate_item_history_archive
    FOR EACH STATEMENT EXECUTE FUNCTION public.enforce_retired_read_only();
REVOKE INSERT, UPDATE, DELETE ON public.rate_item_history FROM tally_app;
REVOKE INSERT, UPDATE, DELETE ON public.rate_item_history_archive FROM tally_app;

CREATE OR REPLACE FUNCTION public.archive_rate_item_history(p_years_to_keep integer DEFAULT 10) RETURNS integer
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
BEGIN
    RAISE EXCEPTION USING
        MESSAGE = 'archive_rate_item_history() is disabled (v5.4.2-03, A-1): rate history is a permanent bi-temporal record (CI-001 — subpoena and audit reconstruction have no retention cap). Nothing is moved or deleted.',
        ERRCODE = 'feature_not_supported';
END;
$$;
COMMENT ON FUNCTION public.archive_rate_item_history(integer) IS
    'DISABLED by v5.4.2-03 (A-1): raises unconditionally. It hard-deleted rate_item_history rows older than N years into rate_item_history_archive — a live DELETE path beside the table this substrate declares permanent. Both tables are retired read-only; rate_item_versions is the record. Kept as a stub so any scheduled caller fails loudly instead of resolving to nothing.';

COMMENT ON TABLE public.rate_items IS
    'Identity header of a rate item (A-1, v5.4.2-03): id, tenant_id, item_code, created_at immutable; status (active | paused | archived) is operational lifecycle; version is the CI-011 token. Everything else — name, calculation_type, rate_value (was current_rate, dropped rather than cached), rate_unit, tier_config, active months, taxability, regulatory_class, the valid-time bracket — is on rate_item_versions. invoice_line_items / rate_schedule_items / rate_item_dependencies keep pointing here.';
COMMENT ON TABLE public.rate_item_versions IS
    'Bi-temporal content of a rate item (A-1, v5.4.2-03) — the successor of rate_item_history, which tracked only rate_value/rate_unit. Same contract as rate_schedule_versions. Read through rate_item_as_of(id, p_valid_at, p_recorded_at). Backfill rows migrated from rate_item_history carry genuine rate_value/rate_unit history but live-row values for every column that table never tracked (flagged in change_reason).';
COMMENT ON COLUMN public.rate_item_versions.regulatory_class IS
    'Whether this charge is tariffed/regulated or unregulated (D7-2, v5.4.0-03; versioned by A-1 — a misclassification correction is a dated assertion). NOT NULL by design: a charge definition introduced without explicit classification is CI-050''s named failure mode. Drives the regulated-first payment-allocation floor (CI-050) and the Family 9 collections rule that unregulated debt cannot drive disconnect.';
COMMENT ON TABLE public.rate_item_history IS
    'RETIRED by v5.4.2-03 (A-1). Read-only migration source (trigger + REVOKE); its rows were migrated into rate_item_versions as backfill. Do not write here.';
COMMENT ON TABLE public.rate_item_history_archive IS
    'RETIRED by v5.4.2-03 (A-1). Read-only (trigger + REVOKE). archive_rate_item_history() no longer feeds it.';

-- ----------------------------------------------------------------------------
-- 5. Group 2 — in-place transaction-time pair
-- ----------------------------------------------------------------------------

-- 5.1 rate_schedule_items
ALTER TABLE public.rate_schedule_items ADD COLUMN IF NOT EXISTS recorded_at timestamp with time zone DEFAULT now() NOT NULL;
ALTER TABLE public.rate_schedule_items ADD COLUMN IF NOT EXISTS recorded_until timestamp with time zone;
ALTER TABLE public.rate_schedule_items ADD COLUMN IF NOT EXISTS change_type text DEFAULT 'initial' NOT NULL;
ALTER TABLE public.rate_schedule_items ADD COLUMN IF NOT EXISTS change_reason text;
ALTER TABLE public.rate_schedule_items ADD COLUMN IF NOT EXISTS changed_by uuid;
ALTER TABLE public.rate_schedule_items ADD COLUMN IF NOT EXISTS supersedes_id uuid;
ALTER TABLE public.rate_schedule_items ADD COLUMN IF NOT EXISTS closed_type text;
ALTER TABLE public.rate_schedule_items ADD COLUMN IF NOT EXISTS closed_reason text;
ALTER TABLE public.rate_schedule_items ADD COLUMN IF NOT EXISTS closed_by uuid;

-- every row present at patch time predates the substrate: one backfill assertion each
DO $$
BEGIN
    -- first run only (the guard does not exist yet): every row present predates the substrate
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'a_enforce_bitemporal_assertion' AND tgrelid = 'public.rate_schedule_items'::regclass) THEN
        UPDATE public.rate_schedule_items
           SET recorded_at = created_at, change_type = 'backfill',
               change_reason = 'v5.4.2-03 backfill: row observed at deploy, stamped at created_at as an approximation'
         WHERE change_type = 'initial';
    END IF;
END;
$$;

ALTER TABLE public.rate_schedule_items DROP CONSTRAINT IF EXISTS rate_schedule_items_change_type_check;
ALTER TABLE public.rate_schedule_items ADD CONSTRAINT rate_schedule_items_change_type_check CHECK ((change_type = ANY (ARRAY['initial'::text, 'succession'::text, 'correction'::text, 'backfill'::text])));
ALTER TABLE public.rate_schedule_items DROP CONSTRAINT IF EXISTS rate_schedule_items_correction_reason_check;
ALTER TABLE public.rate_schedule_items ADD CONSTRAINT rate_schedule_items_correction_reason_check CHECK ((change_type <> 'correction') OR (change_reason IS NOT NULL));
ALTER TABLE public.rate_schedule_items DROP CONSTRAINT IF EXISTS rate_schedule_items_supersedes_check;
ALTER TABLE public.rate_schedule_items ADD CONSTRAINT rate_schedule_items_supersedes_check CHECK ((supersedes_id IS NULL) OR (change_type = 'succession') OR (change_type = 'correction'));
ALTER TABLE public.rate_schedule_items DROP CONSTRAINT IF EXISTS rate_schedule_items_closed_type_check;
ALTER TABLE public.rate_schedule_items ADD CONSTRAINT rate_schedule_items_closed_type_check CHECK ((closed_type IS NULL) OR (closed_type = ANY (ARRAY['superseded'::text, 'retracted'::text])));
ALTER TABLE public.rate_schedule_items DROP CONSTRAINT IF EXISTS rate_schedule_items_close_consistent_check;
ALTER TABLE public.rate_schedule_items ADD CONSTRAINT rate_schedule_items_close_consistent_check CHECK (((recorded_until IS NULL) AND (closed_type IS NULL) AND (closed_reason IS NULL) AND (closed_by IS NULL)) OR ((recorded_until IS NOT NULL) AND (closed_type IS NOT NULL) AND (closed_reason IS NOT NULL) AND (recorded_until >= recorded_at)));
ALTER TABLE public.rate_schedule_items DROP CONSTRAINT IF EXISTS rate_schedule_items_valid_bracket_check;
ALTER TABLE public.rate_schedule_items ADD CONSTRAINT rate_schedule_items_valid_bracket_check CHECK ((expiry_date IS NULL) OR (expiry_date >= effective_date));
ALTER TABLE public.rate_schedule_items DROP CONSTRAINT IF EXISTS rate_schedule_items_archived_has_end_check;
ALTER TABLE public.rate_schedule_items ADD CONSTRAINT rate_schedule_items_archived_has_end_check CHECK ((status <> 'archived') OR (expiry_date IS NOT NULL));
ALTER TABLE public.rate_schedule_items DROP CONSTRAINT IF EXISTS rate_schedule_items_changed_by_fkey;
ALTER TABLE public.rate_schedule_items ADD CONSTRAINT rate_schedule_items_changed_by_fkey FOREIGN KEY (changed_by) REFERENCES public.users(id);
ALTER TABLE public.rate_schedule_items DROP CONSTRAINT IF EXISTS rate_schedule_items_closed_by_fkey;
ALTER TABLE public.rate_schedule_items ADD CONSTRAINT rate_schedule_items_closed_by_fkey FOREIGN KEY (closed_by) REFERENCES public.users(id);
ALTER TABLE public.rate_schedule_items DROP CONSTRAINT IF EXISTS rate_schedule_items_supersedes_id_fkey;
ALTER TABLE public.rate_schedule_items ADD CONSTRAINT rate_schedule_items_supersedes_id_fkey FOREIGN KEY (supersedes_id) REFERENCES public.rate_schedule_items(id);

-- the same-date correction blocker becomes open-rows-only
ALTER TABLE public.rate_schedule_items DROP CONSTRAINT IF EXISTS rate_schedule_items_rate_schedule_id_rate_item_id_effective_key;
ALTER TABLE public.rate_schedule_items DROP CONSTRAINT IF EXISTS rate_schedule_items_open_no_overlap_excl;
ALTER TABLE public.rate_schedule_items ADD CONSTRAINT rate_schedule_items_open_no_overlap_excl
    EXCLUDE USING gist (rate_schedule_id WITH =, rate_item_id WITH =, daterange(effective_date, expiry_date, '[]') WITH &&) WHERE (recorded_until IS NULL);

DROP INDEX IF EXISTS public.idx_rate_sched_items_active;
CREATE INDEX idx_rate_sched_items_active ON public.rate_schedule_items USING btree (rate_schedule_id, status) WHERE ((status = 'active'::text) AND (recorded_until IS NULL));
CREATE INDEX IF NOT EXISTS idx_rate_sched_items_open ON public.rate_schedule_items USING btree (rate_schedule_id, rate_item_id, effective_date DESC) WHERE (recorded_until IS NULL);
CREATE INDEX IF NOT EXISTS idx_rate_sched_items_supersedes ON public.rate_schedule_items USING btree (supersedes_id) WHERE (supersedes_id IS NOT NULL);

DROP TRIGGER IF EXISTS a_enforce_bitemporal_assertion ON public.rate_schedule_items;
CREATE TRIGGER a_enforce_bitemporal_assertion BEFORE INSERT OR UPDATE OR DELETE ON public.rate_schedule_items
    FOR EACH ROW EXECUTE FUNCTION public.enforce_bitemporal_assertion('notes,metadata,updated_at', 'rate_schedule_id,rate_item_id');
DROP TRIGGER IF EXISTS enforce_superseded_has_successor ON public.rate_schedule_items;
CREATE CONSTRAINT TRIGGER enforce_superseded_has_successor AFTER UPDATE ON public.rate_schedule_items
    DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.enforce_superseded_has_successor('rate_schedule_id,rate_item_id');

COMMENT ON TABLE public.rate_schedule_items IS
    'Schedule-level overrides of a rate item — bi-temporal in place (A-1, v5.4.2-03; nothing entity-FKs to this table, so no header). Valid [effective_date, expiry_date], transaction [recorded_at, recorded_until). One open row per (schedule, item) per valid point (exclusion constraint — the former UNIQUE on effective_date blocked same-date corrections). Once recorded (always, on insert) a row is frozen except notes/metadata: correction = close + insert with supersedes_id; retraction = close as retracted. status is operational (active | paused | archived; archived requires an expiry_date) and, being content, changes by a new row. Read through rate_schedule_item_as_of(schedule, item, p_valid_at, p_recorded_at). No version counter: the closing UPDATE ... WHERE recorded_until IS NULL is the CI-011 check.';

-- 5.2 franchise_fee_rules
ALTER TABLE public.franchise_fee_rules ADD COLUMN IF NOT EXISTS recorded_at timestamp with time zone DEFAULT now() NOT NULL;
ALTER TABLE public.franchise_fee_rules ADD COLUMN IF NOT EXISTS recorded_until timestamp with time zone;
ALTER TABLE public.franchise_fee_rules ADD COLUMN IF NOT EXISTS change_type text DEFAULT 'initial' NOT NULL;
ALTER TABLE public.franchise_fee_rules ADD COLUMN IF NOT EXISTS change_reason text;
ALTER TABLE public.franchise_fee_rules ADD COLUMN IF NOT EXISTS changed_by uuid;
ALTER TABLE public.franchise_fee_rules ADD COLUMN IF NOT EXISTS supersedes_id uuid;
ALTER TABLE public.franchise_fee_rules ADD COLUMN IF NOT EXISTS closed_type text;
ALTER TABLE public.franchise_fee_rules ADD COLUMN IF NOT EXISTS closed_reason text;
ALTER TABLE public.franchise_fee_rules ADD COLUMN IF NOT EXISTS closed_by uuid;

DO $$
BEGIN
    -- first run only (the guard does not exist yet): every row present predates the substrate
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'a_enforce_bitemporal_assertion' AND tgrelid = 'public.franchise_fee_rules'::regclass) THEN
        UPDATE public.franchise_fee_rules
           SET recorded_at = created_at, change_type = 'backfill',
               change_reason = 'v5.4.2-03 backfill: row observed at deploy, stamped at created_at as an approximation'
         WHERE change_type = 'initial';
    END IF;
END;
$$;

ALTER TABLE public.franchise_fee_rules DROP CONSTRAINT IF EXISTS franchise_fee_rules_status_check;
ALTER TABLE public.franchise_fee_rules ADD CONSTRAINT franchise_fee_rules_status_check CHECK ((status = ANY (ARRAY['active'::text, 'archived'::text])));
ALTER TABLE public.franchise_fee_rules DROP CONSTRAINT IF EXISTS franchise_fee_rules_archived_has_end_check;
ALTER TABLE public.franchise_fee_rules ADD CONSTRAINT franchise_fee_rules_archived_has_end_check CHECK ((status <> 'archived') OR (expiry_date IS NOT NULL));
ALTER TABLE public.franchise_fee_rules DROP CONSTRAINT IF EXISTS franchise_fee_rules_change_type_check;
ALTER TABLE public.franchise_fee_rules ADD CONSTRAINT franchise_fee_rules_change_type_check CHECK ((change_type = ANY (ARRAY['initial'::text, 'succession'::text, 'correction'::text, 'backfill'::text])));
ALTER TABLE public.franchise_fee_rules DROP CONSTRAINT IF EXISTS franchise_fee_rules_correction_reason_check;
ALTER TABLE public.franchise_fee_rules ADD CONSTRAINT franchise_fee_rules_correction_reason_check CHECK ((change_type <> 'correction') OR (change_reason IS NOT NULL));
ALTER TABLE public.franchise_fee_rules DROP CONSTRAINT IF EXISTS franchise_fee_rules_supersedes_check;
ALTER TABLE public.franchise_fee_rules ADD CONSTRAINT franchise_fee_rules_supersedes_check CHECK ((supersedes_id IS NULL) OR (change_type = 'succession') OR (change_type = 'correction'));
ALTER TABLE public.franchise_fee_rules DROP CONSTRAINT IF EXISTS franchise_fee_rules_closed_type_check;
ALTER TABLE public.franchise_fee_rules ADD CONSTRAINT franchise_fee_rules_closed_type_check CHECK ((closed_type IS NULL) OR (closed_type = ANY (ARRAY['superseded'::text, 'retracted'::text])));
ALTER TABLE public.franchise_fee_rules DROP CONSTRAINT IF EXISTS franchise_fee_rules_close_consistent_check;
ALTER TABLE public.franchise_fee_rules ADD CONSTRAINT franchise_fee_rules_close_consistent_check CHECK (((recorded_until IS NULL) AND (closed_type IS NULL) AND (closed_reason IS NULL) AND (closed_by IS NULL)) OR ((recorded_until IS NOT NULL) AND (closed_type IS NOT NULL) AND (closed_reason IS NOT NULL) AND (recorded_until >= recorded_at)));
ALTER TABLE public.franchise_fee_rules DROP CONSTRAINT IF EXISTS franchise_fee_rules_valid_bracket_check;
ALTER TABLE public.franchise_fee_rules ADD CONSTRAINT franchise_fee_rules_valid_bracket_check CHECK ((expiry_date IS NULL) OR (expiry_date >= effective_date));
ALTER TABLE public.franchise_fee_rules DROP CONSTRAINT IF EXISTS franchise_fee_rules_changed_by_fkey;
ALTER TABLE public.franchise_fee_rules ADD CONSTRAINT franchise_fee_rules_changed_by_fkey FOREIGN KEY (changed_by) REFERENCES public.users(id);
ALTER TABLE public.franchise_fee_rules DROP CONSTRAINT IF EXISTS franchise_fee_rules_closed_by_fkey;
ALTER TABLE public.franchise_fee_rules ADD CONSTRAINT franchise_fee_rules_closed_by_fkey FOREIGN KEY (closed_by) REFERENCES public.users(id);
ALTER TABLE public.franchise_fee_rules DROP CONSTRAINT IF EXISTS franchise_fee_rules_supersedes_id_fkey;
ALTER TABLE public.franchise_fee_rules ADD CONSTRAINT franchise_fee_rules_supersedes_id_fkey FOREIGN KEY (supersedes_id) REFERENCES public.franchise_fee_rules(id);

ALTER TABLE public.franchise_fee_rules DROP CONSTRAINT IF EXISTS franchise_fee_rules_tenant_id_city_name_effective_date_key;
ALTER TABLE public.franchise_fee_rules DROP CONSTRAINT IF EXISTS franchise_fee_rules_open_no_overlap_excl;
ALTER TABLE public.franchise_fee_rules ADD CONSTRAINT franchise_fee_rules_open_no_overlap_excl
    EXCLUDE USING gist (tenant_id WITH =, city_name WITH =, daterange(effective_date, expiry_date, '[]') WITH &&) WHERE (recorded_until IS NULL);

DROP INDEX IF EXISTS public.idx_franchise_fees_active;
CREATE INDEX idx_franchise_fees_active ON public.franchise_fee_rules USING btree (tenant_id, status, effective_date DESC) WHERE ((status = 'active'::text) AND (recorded_until IS NULL));
DROP INDEX IF EXISTS public.idx_franchise_fees_city;
CREATE INDEX idx_franchise_fees_city ON public.franchise_fee_rules USING btree (tenant_id, city_name, status) WHERE ((status = 'active'::text) AND (recorded_until IS NULL));
CREATE INDEX IF NOT EXISTS idx_franchise_fees_supersedes ON public.franchise_fee_rules USING btree (supersedes_id) WHERE (supersedes_id IS NOT NULL);

DROP TRIGGER IF EXISTS a_enforce_bitemporal_assertion ON public.franchise_fee_rules;
CREATE TRIGGER a_enforce_bitemporal_assertion BEFORE INSERT OR UPDATE OR DELETE ON public.franchise_fee_rules
    FOR EACH ROW EXECUTE FUNCTION public.enforce_bitemporal_assertion('notes,metadata,updated_at', 'tenant_id,city_name');
DROP TRIGGER IF EXISTS enforce_superseded_has_successor ON public.franchise_fee_rules;
CREATE CONSTRAINT TRIGGER enforce_superseded_has_successor AFTER UPDATE ON public.franchise_fee_rules
    DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.enforce_superseded_has_successor('tenant_id,city_name');

COMMENT ON TABLE public.franchise_fee_rules IS
    'Municipal franchise-fee rules — bi-temporal in place (A-1, v5.4.2-03). One open row per (tenant, city) per valid point (exclusion constraint replaces the UNIQUE on effective_date that blocked same-date corrections). Frozen once recorded except notes/metadata; correction = close + insert with supersedes_id. status = ''superseded'' was removed (R-14 rider 3): that state is recorded_until IS NOT NULL now; archived requires an expiry_date. Read through franchise_fee_as_of(tenant, city, p_valid_at, p_recorded_at).';

-- 5.3 customer_tax_exemptions (lifecycle table: locks at active — R-12/R-13)
ALTER TABLE public.customer_tax_exemptions ADD COLUMN IF NOT EXISTS recorded_at timestamp with time zone;
ALTER TABLE public.customer_tax_exemptions ADD COLUMN IF NOT EXISTS recorded_until timestamp with time zone;
ALTER TABLE public.customer_tax_exemptions ADD COLUMN IF NOT EXISTS change_type text DEFAULT 'initial' NOT NULL;
ALTER TABLE public.customer_tax_exemptions ADD COLUMN IF NOT EXISTS change_reason text;
ALTER TABLE public.customer_tax_exemptions ADD COLUMN IF NOT EXISTS changed_by uuid;
ALTER TABLE public.customer_tax_exemptions ADD COLUMN IF NOT EXISTS supersedes_id uuid;
ALTER TABLE public.customer_tax_exemptions ADD COLUMN IF NOT EXISTS closed_type text;
ALTER TABLE public.customer_tax_exemptions ADD COLUMN IF NOT EXISTS closed_reason text;
ALTER TABLE public.customer_tax_exemptions ADD COLUMN IF NOT EXISTS closed_by uuid;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'b_enforce_bitemporal_assertion' AND tgrelid = 'public.customer_tax_exemptions'::regclass) THEN
        UPDATE public.customer_tax_exemptions
           SET recorded_at = COALESCE(verified_at, created_at), change_type = 'backfill',
               change_reason = 'v5.4.2-03 backfill: asserted row observed at deploy, stamped at verified_at (else created_at) as an approximation'
         WHERE status IN ('active', 'expired', 'revoked') AND recorded_at IS NULL;
    END IF;
END;
$$;

ALTER TABLE public.customer_tax_exemptions ALTER COLUMN status SET DEFAULT 'pending_verification';

ALTER TABLE public.customer_tax_exemptions DROP CONSTRAINT IF EXISTS customer_tax_exemptions_exemption_type_check;
ALTER TABLE public.customer_tax_exemptions ADD CONSTRAINT customer_tax_exemptions_exemption_type_check
    CHECK ((exemption_type = ANY (ARRAY['non_profit'::text, 'government'::text, 'agricultural'::text, 'sales_for_resale'::text, 'religious'::text, 'educational'::text, 'medical'::text, 'other'::text])));
ALTER TABLE public.customer_tax_exemptions DROP CONSTRAINT IF EXISTS customer_tax_exemptions_active_is_verified_check;
ALTER TABLE public.customer_tax_exemptions ADD CONSTRAINT customer_tax_exemptions_active_is_verified_check
    CHECK (((status <> 'active') AND (status <> 'expired') AND (status <> 'revoked')) OR ((verified_by IS NOT NULL) AND (verified_at IS NOT NULL)));
ALTER TABLE public.customer_tax_exemptions DROP CONSTRAINT IF EXISTS customer_tax_exemptions_assertion_state_check;
ALTER TABLE public.customer_tax_exemptions ADD CONSTRAINT customer_tax_exemptions_assertion_state_check
    CHECK ((((status = 'pending_verification') OR (status = 'rejected')) AND (recorded_at IS NULL) AND (recorded_until IS NULL))
        OR (((status = 'active') OR (status = 'expired') OR (status = 'revoked')) AND (recorded_at IS NOT NULL)));
ALTER TABLE public.customer_tax_exemptions DROP CONSTRAINT IF EXISTS customer_tax_exemptions_revoked_check;
ALTER TABLE public.customer_tax_exemptions ADD CONSTRAINT customer_tax_exemptions_revoked_check
    CHECK ((status <> 'revoked') OR ((revoked_at IS NOT NULL) AND (revoked_by IS NOT NULL) AND (effective_end IS NOT NULL)));
ALTER TABLE public.customer_tax_exemptions DROP CONSTRAINT IF EXISTS customer_tax_exemptions_expired_check;
ALTER TABLE public.customer_tax_exemptions ADD CONSTRAINT customer_tax_exemptions_expired_check
    CHECK ((status <> 'expired') OR (effective_end IS NOT NULL));
ALTER TABLE public.customer_tax_exemptions DROP CONSTRAINT IF EXISTS customer_tax_exemptions_valid_bracket_check;
ALTER TABLE public.customer_tax_exemptions ADD CONSTRAINT customer_tax_exemptions_valid_bracket_check CHECK ((effective_end IS NULL) OR (effective_end >= effective_start));
ALTER TABLE public.customer_tax_exemptions DROP CONSTRAINT IF EXISTS customer_tax_exemptions_change_type_check;
ALTER TABLE public.customer_tax_exemptions ADD CONSTRAINT customer_tax_exemptions_change_type_check CHECK ((change_type = ANY (ARRAY['initial'::text, 'succession'::text, 'correction'::text, 'backfill'::text])));
ALTER TABLE public.customer_tax_exemptions DROP CONSTRAINT IF EXISTS customer_tax_exemptions_correction_reason_check;
ALTER TABLE public.customer_tax_exemptions ADD CONSTRAINT customer_tax_exemptions_correction_reason_check CHECK ((change_type <> 'correction') OR (change_reason IS NOT NULL));
ALTER TABLE public.customer_tax_exemptions DROP CONSTRAINT IF EXISTS customer_tax_exemptions_supersedes_check;
ALTER TABLE public.customer_tax_exemptions ADD CONSTRAINT customer_tax_exemptions_supersedes_check CHECK ((supersedes_id IS NULL) OR (change_type = 'succession') OR (change_type = 'correction'));
ALTER TABLE public.customer_tax_exemptions DROP CONSTRAINT IF EXISTS customer_tax_exemptions_closed_type_check;
ALTER TABLE public.customer_tax_exemptions ADD CONSTRAINT customer_tax_exemptions_closed_type_check CHECK ((closed_type IS NULL) OR (closed_type = ANY (ARRAY['superseded'::text, 'retracted'::text])));
ALTER TABLE public.customer_tax_exemptions DROP CONSTRAINT IF EXISTS customer_tax_exemptions_close_consistent_check;
ALTER TABLE public.customer_tax_exemptions ADD CONSTRAINT customer_tax_exemptions_close_consistent_check CHECK (((recorded_until IS NULL) AND (closed_type IS NULL) AND (closed_reason IS NULL) AND (closed_by IS NULL)) OR ((recorded_until IS NOT NULL) AND (recorded_at IS NOT NULL) AND (closed_type IS NOT NULL) AND (closed_reason IS NOT NULL) AND (recorded_until >= recorded_at)));
ALTER TABLE public.customer_tax_exemptions DROP CONSTRAINT IF EXISTS customer_tax_exemptions_changed_by_fkey;
ALTER TABLE public.customer_tax_exemptions ADD CONSTRAINT customer_tax_exemptions_changed_by_fkey FOREIGN KEY (changed_by) REFERENCES public.users(id);
ALTER TABLE public.customer_tax_exemptions DROP CONSTRAINT IF EXISTS customer_tax_exemptions_closed_by_fkey;
ALTER TABLE public.customer_tax_exemptions ADD CONSTRAINT customer_tax_exemptions_closed_by_fkey FOREIGN KEY (closed_by) REFERENCES public.users(id);
ALTER TABLE public.customer_tax_exemptions DROP CONSTRAINT IF EXISTS customer_tax_exemptions_supersedes_id_fkey;
ALTER TABLE public.customer_tax_exemptions ADD CONSTRAINT customer_tax_exemptions_supersedes_id_fkey FOREIGN KEY (supersedes_id) REFERENCES public.customer_tax_exemptions(id);

ALTER TABLE public.customer_tax_exemptions DROP CONSTRAINT IF EXISTS customer_tax_exemptions_open_no_overlap_excl;
ALTER TABLE public.customer_tax_exemptions ADD CONSTRAINT customer_tax_exemptions_open_no_overlap_excl
    EXCLUDE USING gist (customer_id WITH =, exemption_type WITH =, daterange(effective_start, effective_end, '[]') WITH &&)
    WHERE ((recorded_at IS NOT NULL) AND (recorded_until IS NULL));

DROP INDEX IF EXISTS public.idx_tax_exemptions_active;
CREATE INDEX idx_tax_exemptions_active ON public.customer_tax_exemptions USING btree (customer_id, effective_start, effective_end) WHERE ((recorded_at IS NOT NULL) AND (recorded_until IS NULL));
DROP INDEX IF EXISTS public.idx_tax_exemptions_expiring;
CREATE INDEX idx_tax_exemptions_expiring ON public.customer_tax_exemptions USING btree (tenant_id, effective_end) WHERE ((status = 'active'::text) AND (effective_end IS NOT NULL) AND (recorded_until IS NULL));
CREATE INDEX IF NOT EXISTS idx_tax_exemptions_lineage ON public.customer_tax_exemptions USING btree (customer_id, recorded_at DESC);
CREATE INDEX IF NOT EXISTS idx_tax_exemptions_supersedes ON public.customer_tax_exemptions USING btree (supersedes_id) WHERE (supersedes_id IS NOT NULL);

-- lifecycle: stamps recorded_at on entry to an asserted state; pending may
-- only go to active or rejected; rejected is terminal; asserted states
-- never change status in place (revocation / expiry = new row + close).
CREATE OR REPLACE FUNCTION public.enforce_tax_exemption_lifecycle() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF TG_OP = 'UPDATE' THEN
        IF OLD.status = 'rejected' AND NEW.status <> 'rejected' THEN
            RAISE EXCEPTION 'customer_tax_exemptions %: rejected is terminal; enter a new exemption', OLD.id;
        END IF;
        IF OLD.status = 'pending_verification' AND NEW.status NOT IN ('pending_verification', 'active', 'rejected') THEN
            RAISE EXCEPTION 'customer_tax_exemptions %: pending_verification moves to active (verified) or rejected only, not %', OLD.id, NEW.status;
        END IF;
        IF OLD.recorded_at IS NOT NULL AND NEW.status IS DISTINCT FROM OLD.status THEN
            RAISE EXCEPTION 'customer_tax_exemptions %: an asserted exemption does not change status in place — revocation (valid-time: the authority pulled the certificate) or expiry is a new row with effective_end/status set and supersedes_id = %, after closing this row; a certificate that never existed is a retraction (close as retracted)', OLD.id, OLD.id;
        END IF;
    END IF;
    IF NEW.status IN ('active', 'expired', 'revoked') AND NEW.recorded_at IS NULL THEN
        NEW.recorded_at := now();
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS a_enforce_tax_exemption_lifecycle ON public.customer_tax_exemptions;
CREATE TRIGGER a_enforce_tax_exemption_lifecycle BEFORE INSERT OR UPDATE ON public.customer_tax_exemptions
    FOR EACH ROW EXECUTE FUNCTION public.enforce_tax_exemption_lifecycle();
DROP TRIGGER IF EXISTS b_enforce_bitemporal_assertion ON public.customer_tax_exemptions;
CREATE TRIGGER b_enforce_bitemporal_assertion BEFORE INSERT OR UPDATE OR DELETE ON public.customer_tax_exemptions
    FOR EACH ROW EXECUTE FUNCTION public.enforce_bitemporal_assertion('notes,metadata,updated_at', 'customer_id');
DROP TRIGGER IF EXISTS enforce_superseded_has_successor ON public.customer_tax_exemptions;
CREATE CONSTRAINT TRIGGER enforce_superseded_has_successor AFTER UPDATE ON public.customer_tax_exemptions
    DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.enforce_superseded_has_successor('customer_id');

COMMENT ON TABLE public.customer_tax_exemptions IS
    'Certificate-backed sales-tax exemptions only (R-13, v5.4.2-03): exempt organisations under Form 01-339 / Comptroller letter. Residential (§151.317) is derived from rate class, not a row; predominant-use (manufacturing) exemptions are per point of delivery and usually partial and get their own table later — ''industrial'' was removed from exemption_type. Bi-temporal in place (A-1): a row is a draft while pending_verification (recorded_at NULL, freely editable, DEFAULT — flipped from active by R-12), becomes an assertion when verified into active (recorded_at stamps; verified_by/verified_at required — Comptroller Rule 3.287 puts certificate liability on the seller), and is then frozen except notes/metadata. Revocation is a valid-time event (a new row with effective_end/revoked_* and status revoked, superseding the active row); a certificate that never existed is a retraction (close with closed_type = retracted). A revocation discovered late means issued bills were under-taxed — that routes to the void/rebill infrastructure as a correction run, not merely a status change. Read through customer_tax_exemption_as_of(customer, p_valid_at, p_recorded_at) / should_charge_tax().';
COMMENT ON COLUMN public.customer_tax_exemptions.status IS
    'pending_verification (default; draft, editable) -> active (verified; asserted, frozen) | rejected (terminal draft). expired / revoked are asserted end states written as NEW rows superseding the active one (valid-time closings), never in-place flips. CHECKs: active/expired/revoked require verified_by AND verified_at; revoked requires revoked_at, revoked_by AND effective_end; expired requires effective_end; drafts have recorded_at NULL, asserted rows have it set.';

-- 5.4 wna_monthly_adjustments (lifecycle table: locks at approved — R-11)
ALTER TABLE public.wna_monthly_adjustments ADD COLUMN IF NOT EXISTS recorded_at timestamp with time zone;
ALTER TABLE public.wna_monthly_adjustments ADD COLUMN IF NOT EXISTS recorded_until timestamp with time zone;
ALTER TABLE public.wna_monthly_adjustments ADD COLUMN IF NOT EXISTS change_type text DEFAULT 'initial' NOT NULL;
ALTER TABLE public.wna_monthly_adjustments ADD COLUMN IF NOT EXISTS change_reason text;
ALTER TABLE public.wna_monthly_adjustments ADD COLUMN IF NOT EXISTS changed_by uuid;
ALTER TABLE public.wna_monthly_adjustments ADD COLUMN IF NOT EXISTS supersedes_id uuid;
ALTER TABLE public.wna_monthly_adjustments ADD COLUMN IF NOT EXISTS closed_type text;
ALTER TABLE public.wna_monthly_adjustments ADD COLUMN IF NOT EXISTS closed_reason text;
ALTER TABLE public.wna_monthly_adjustments ADD COLUMN IF NOT EXISTS closed_by uuid;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'b_enforce_bitemporal_assertion' AND tgrelid = 'public.wna_monthly_adjustments'::regclass) THEN
        UPDATE public.wna_monthly_adjustments
           SET recorded_at = COALESCE(approved_at, created_at), change_type = 'backfill',
               change_reason = 'v5.4.2-03 backfill: asserted row observed at deploy, stamped at approved_at (else created_at) as an approximation'
         WHERE status <> 'pending' AND recorded_at IS NULL;
    END IF;
END;
$$;

ALTER TABLE public.wna_monthly_adjustments DROP CONSTRAINT IF EXISTS wna_monthly_adjustments_assertion_state_check;
ALTER TABLE public.wna_monthly_adjustments ADD CONSTRAINT wna_monthly_adjustments_assertion_state_check
    CHECK (((status = 'pending') AND (recorded_at IS NULL) AND (recorded_until IS NULL))
        OR ((status <> 'pending') AND (recorded_at IS NOT NULL) AND (approved_by IS NOT NULL) AND (approved_at IS NOT NULL)));
ALTER TABLE public.wna_monthly_adjustments DROP CONSTRAINT IF EXISTS wna_monthly_adjustments_change_type_check;
ALTER TABLE public.wna_monthly_adjustments ADD CONSTRAINT wna_monthly_adjustments_change_type_check CHECK ((change_type = ANY (ARRAY['initial'::text, 'succession'::text, 'correction'::text, 'backfill'::text])));
ALTER TABLE public.wna_monthly_adjustments DROP CONSTRAINT IF EXISTS wna_monthly_adjustments_correction_reason_check;
ALTER TABLE public.wna_monthly_adjustments ADD CONSTRAINT wna_monthly_adjustments_correction_reason_check CHECK ((change_type <> 'correction') OR (change_reason IS NOT NULL));
ALTER TABLE public.wna_monthly_adjustments DROP CONSTRAINT IF EXISTS wna_monthly_adjustments_supersedes_check;
ALTER TABLE public.wna_monthly_adjustments ADD CONSTRAINT wna_monthly_adjustments_supersedes_check CHECK ((supersedes_id IS NULL) OR (change_type = 'succession') OR (change_type = 'correction'));
ALTER TABLE public.wna_monthly_adjustments DROP CONSTRAINT IF EXISTS wna_monthly_adjustments_closed_type_check;
ALTER TABLE public.wna_monthly_adjustments ADD CONSTRAINT wna_monthly_adjustments_closed_type_check CHECK ((closed_type IS NULL) OR (closed_type = ANY (ARRAY['superseded'::text, 'retracted'::text])));
ALTER TABLE public.wna_monthly_adjustments DROP CONSTRAINT IF EXISTS wna_monthly_adjustments_close_consistent_check;
ALTER TABLE public.wna_monthly_adjustments ADD CONSTRAINT wna_monthly_adjustments_close_consistent_check CHECK (((recorded_until IS NULL) AND (closed_type IS NULL) AND (closed_reason IS NULL) AND (closed_by IS NULL)) OR ((recorded_until IS NOT NULL) AND (recorded_at IS NOT NULL) AND (closed_type IS NOT NULL) AND (closed_reason IS NOT NULL) AND (recorded_until >= recorded_at)));
ALTER TABLE public.wna_monthly_adjustments DROP CONSTRAINT IF EXISTS wna_monthly_adjustments_changed_by_fkey;
ALTER TABLE public.wna_monthly_adjustments ADD CONSTRAINT wna_monthly_adjustments_changed_by_fkey FOREIGN KEY (changed_by) REFERENCES public.users(id);
ALTER TABLE public.wna_monthly_adjustments DROP CONSTRAINT IF EXISTS wna_monthly_adjustments_closed_by_fkey;
ALTER TABLE public.wna_monthly_adjustments ADD CONSTRAINT wna_monthly_adjustments_closed_by_fkey FOREIGN KEY (closed_by) REFERENCES public.users(id);
ALTER TABLE public.wna_monthly_adjustments DROP CONSTRAINT IF EXISTS wna_monthly_adjustments_supersedes_id_fkey;
ALTER TABLE public.wna_monthly_adjustments ADD CONSTRAINT wna_monthly_adjustments_supersedes_id_fkey FOREIGN KEY (supersedes_id) REFERENCES public.wna_monthly_adjustments(id);

-- the HDD-restatement blocker becomes open-rows-only (valid time is a month, so a partial UNIQUE, not a range exclusion)
ALTER TABLE public.wna_monthly_adjustments DROP CONSTRAINT IF EXISTS wna_monthly_adjustments_tenant_id_wna_zone_id_billing_month_key;
DROP INDEX IF EXISTS public.wna_monthly_adjustments_open_month_key;
CREATE UNIQUE INDEX wna_monthly_adjustments_open_month_key ON public.wna_monthly_adjustments USING btree (tenant_id, wna_zone_id, billing_month) WHERE ((recorded_at IS NOT NULL) AND (recorded_until IS NULL));
CREATE INDEX IF NOT EXISTS idx_wna_adj_supersedes ON public.wna_monthly_adjustments USING btree (supersedes_id) WHERE (supersedes_id IS NOT NULL);
CREATE INDEX IF NOT EXISTS idx_wna_adj_lineage ON public.wna_monthly_adjustments USING btree (wna_zone_id, billing_month, recorded_at DESC);

CREATE OR REPLACE FUNCTION public.enforce_wna_adjustment_lifecycle() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF TG_OP = 'UPDATE' AND OLD.recorded_at IS NOT NULL AND NEW.status IS DISTINCT FROM OLD.status THEN
        IF NOT ((OLD.status = 'approved' AND NEW.status IN ('applied', 'archived')) OR (OLD.status = 'applied' AND NEW.status = 'archived')) THEN
            RAISE EXCEPTION 'wna_monthly_adjustments %: status moves forward only once approved (approved -> applied -> archived); % -> % rejected. A restated HDD or factor is a correction: close this row and insert the corrected one (R-11)', OLD.id, OLD.status, NEW.status;
        END IF;
    END IF;
    IF NEW.status <> 'pending' AND NEW.recorded_at IS NULL THEN
        NEW.recorded_at := now();
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS a_enforce_wna_adjustment_lifecycle ON public.wna_monthly_adjustments;
CREATE TRIGGER a_enforce_wna_adjustment_lifecycle BEFORE INSERT OR UPDATE ON public.wna_monthly_adjustments
    FOR EACH ROW EXECUTE FUNCTION public.enforce_wna_adjustment_lifecycle();
DROP TRIGGER IF EXISTS b_enforce_bitemporal_assertion ON public.wna_monthly_adjustments;
CREATE TRIGGER b_enforce_bitemporal_assertion BEFORE INSERT OR UPDATE OR DELETE ON public.wna_monthly_adjustments
    FOR EACH ROW EXECUTE FUNCTION public.enforce_bitemporal_assertion('status,notes,updated_at', 'wna_zone_id,billing_month');
DROP TRIGGER IF EXISTS enforce_superseded_has_successor ON public.wna_monthly_adjustments;
CREATE CONSTRAINT TRIGGER enforce_superseded_has_successor AFTER UPDATE ON public.wna_monthly_adjustments
    DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.enforce_superseded_has_successor('wna_zone_id,billing_month');

COMMENT ON TABLE public.wna_monthly_adjustments IS
    'Monthly WNA factors per zone — bi-temporal in place (A-1, v5.4.2-03). pending is a draft (recorded_at NULL, editable). Approval is the assertion (R-11): recorded_at stamps on pending -> approved, approved_by/approved_at are required from then on, and the row is frozen except the forward lifecycle (approved -> applied -> archived — bill-run mechanics, not truth claims), notes and updated_at. An HDD restatement (NCEI/NWS preliminary -> final) for a past month is the canonical CI-001 correction: close the row, insert the corrected one with supersedes_id. One open row per (tenant, zone, month) (partial unique replaces the UNIQUE that made restatement impossible). status = archived is a lifecycle end (the month was consumed and filed) and the row stays the current assertion for its month — as_of still returns it; only recorded_until says "no longer believed". wna_clamp_events.wna_monthly_adjustment_id is a provenance FK — it correctly pins the exact assertion that produced the clamp, even after that assertion is superseded. Read through wna_monthly_adjustment_as_of(zone, billing_month, p_recorded_at).';

-- ----------------------------------------------------------------------------
-- 6. CASCADE strip + protected set
-- ----------------------------------------------------------------------------
ALTER TABLE public.rate_item_history DROP CONSTRAINT IF EXISTS rate_item_history_rate_item_id_fkey;
ALTER TABLE public.rate_item_history ADD CONSTRAINT rate_item_history_rate_item_id_fkey FOREIGN KEY (rate_item_id) REFERENCES public.rate_items(id);
ALTER TABLE public.wna_monthly_adjustments DROP CONSTRAINT IF EXISTS wna_monthly_adjustments_wna_zone_id_fkey;
ALTER TABLE public.wna_monthly_adjustments ADD CONSTRAINT wna_monthly_adjustments_wna_zone_id_fkey FOREIGN KEY (wna_zone_id) REFERENCES public.wna_zones(id);
ALTER TABLE public.rate_schedule_items DROP CONSTRAINT IF EXISTS rate_schedule_items_rate_schedule_id_fkey;
ALTER TABLE public.rate_schedule_items ADD CONSTRAINT rate_schedule_items_rate_schedule_id_fkey FOREIGN KEY (rate_schedule_id) REFERENCES public.rate_schedules(id);
ALTER TABLE public.rate_item_dependencies DROP CONSTRAINT IF EXISTS rate_item_dependencies_base_rate_item_id_fkey;
ALTER TABLE public.rate_item_dependencies ADD CONSTRAINT rate_item_dependencies_base_rate_item_id_fkey FOREIGN KEY (base_rate_item_id) REFERENCES public.rate_items(id);
ALTER TABLE public.rate_item_dependencies DROP CONSTRAINT IF EXISTS rate_item_dependencies_dependent_rate_item_id_fkey;
ALTER TABLE public.rate_item_dependencies ADD CONSTRAINT rate_item_dependencies_dependent_rate_item_id_fkey FOREIGN KEY (dependent_rate_item_id) REFERENCES public.rate_items(id);
ALTER TABLE public.rate_item_dependencies DROP CONSTRAINT IF EXISTS rate_item_dependencies_rate_schedule_id_fkey;
ALTER TABLE public.rate_item_dependencies ADD CONSTRAINT rate_item_dependencies_rate_schedule_id_fkey FOREIGN KEY (rate_schedule_id) REFERENCES public.rate_schedules(id);

-- the substrate joins the A-4 no-hard-delete set (same loop shape as v5.4.2-01)
DO $$
DECLARE
    t text;
    protected constant text[] := ARRAY[
        'rate_schedules', 'rate_schedule_versions', 'rate_schedule_items',
        'rate_items', 'rate_item_versions', 'rate_item_history', 'rate_item_history_archive',
        'franchise_fee_rules',
        'wna_zones', 'wna_zone_versions'
        -- wna_monthly_adjustments and customer_tax_exemptions are in the v5.4.2-01 array already
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
-- 7. Lookups — the enforcement layer (R-15)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rate_schedule_as_of(p_rate_schedule_id uuid, p_valid_at date, p_recorded_at timestamp with time zone)
    RETURNS SETOF public.rate_schedule_versions
    LANGUAGE plpgsql STABLE
    SET search_path = public, pg_temp
    AS $$
BEGIN
    IF p_valid_at IS NULL OR p_recorded_at IS NULL THEN
        RAISE EXCEPTION 'rate_schedule_as_of: p_valid_at and p_recorded_at are both required — pass the run''s (valid, recorded) coordinate pair; never default to now() (CI-001 / CI-003 / CI-006)';
    END IF;
    RETURN QUERY
    SELECT v.* FROM public.rate_schedule_versions v
    WHERE v.rate_schedule_id = p_rate_schedule_id
      AND v.recorded_at <= p_recorded_at AND (v.recorded_until IS NULL OR v.recorded_until > p_recorded_at)
      AND v.effective_date <= p_valid_at AND (v.expiry_date IS NULL OR v.expiry_date >= p_valid_at)
    ORDER BY v.recorded_at DESC, v.id
    LIMIT 1;
END;
$$;

CREATE OR REPLACE FUNCTION public.wna_zone_as_of(p_wna_zone_id uuid, p_valid_at date, p_recorded_at timestamp with time zone)
    RETURNS SETOF public.wna_zone_versions
    LANGUAGE plpgsql STABLE
    SET search_path = public, pg_temp
    AS $$
BEGIN
    IF p_valid_at IS NULL OR p_recorded_at IS NULL THEN
        RAISE EXCEPTION 'wna_zone_as_of: p_valid_at and p_recorded_at are both required — pass the run''s (valid, recorded) coordinate pair; never default to now() (CI-001 / CI-003 / CI-006)';
    END IF;
    RETURN QUERY
    SELECT v.* FROM public.wna_zone_versions v
    WHERE v.wna_zone_id = p_wna_zone_id
      AND v.recorded_at <= p_recorded_at AND (v.recorded_until IS NULL OR v.recorded_until > p_recorded_at)
      AND v.effective_date <= p_valid_at AND (v.expiry_date IS NULL OR v.expiry_date >= p_valid_at)
    ORDER BY v.recorded_at DESC, v.id
    LIMIT 1;
END;
$$;

CREATE OR REPLACE FUNCTION public.rate_item_as_of(p_rate_item_id uuid, p_valid_at date, p_recorded_at timestamp with time zone)
    RETURNS SETOF public.rate_item_versions
    LANGUAGE plpgsql STABLE
    SET search_path = public, pg_temp
    AS $$
BEGIN
    IF p_valid_at IS NULL OR p_recorded_at IS NULL THEN
        RAISE EXCEPTION 'rate_item_as_of: p_valid_at and p_recorded_at are both required — pass the run''s (valid, recorded) coordinate pair; never default to now() (CI-001 / CI-003 / CI-006)';
    END IF;
    RETURN QUERY
    SELECT v.* FROM public.rate_item_versions v
    WHERE v.rate_item_id = p_rate_item_id
      AND v.recorded_at <= p_recorded_at AND (v.recorded_until IS NULL OR v.recorded_until > p_recorded_at)
      AND v.effective_date <= p_valid_at AND (v.expiry_date IS NULL OR v.expiry_date >= p_valid_at)
    ORDER BY v.recorded_at DESC, v.id
    LIMIT 1;
END;
$$;

CREATE OR REPLACE FUNCTION public.rate_schedule_item_as_of(p_rate_schedule_id uuid, p_rate_item_id uuid, p_valid_at date, p_recorded_at timestamp with time zone)
    RETURNS SETOF public.rate_schedule_items
    LANGUAGE plpgsql STABLE
    SET search_path = public, pg_temp
    AS $$
BEGIN
    IF p_valid_at IS NULL OR p_recorded_at IS NULL THEN
        RAISE EXCEPTION 'rate_schedule_item_as_of: p_valid_at and p_recorded_at are both required — pass the run''s (valid, recorded) coordinate pair; never default to now() (CI-001 / CI-003 / CI-006)';
    END IF;
    RETURN QUERY
    SELECT r.* FROM public.rate_schedule_items r
    WHERE r.rate_schedule_id = p_rate_schedule_id AND r.rate_item_id = p_rate_item_id
      AND r.recorded_at <= p_recorded_at AND (r.recorded_until IS NULL OR r.recorded_until > p_recorded_at)
      AND r.effective_date <= p_valid_at AND (r.expiry_date IS NULL OR r.expiry_date >= p_valid_at)
    ORDER BY r.recorded_at DESC, r.id
    LIMIT 1;
END;
$$;

CREATE OR REPLACE FUNCTION public.franchise_fee_as_of(p_tenant_id uuid, p_city_name text, p_valid_at date, p_recorded_at timestamp with time zone)
    RETURNS SETOF public.franchise_fee_rules
    LANGUAGE plpgsql STABLE
    SET search_path = public, pg_temp
    AS $$
BEGIN
    IF p_valid_at IS NULL OR p_recorded_at IS NULL THEN
        RAISE EXCEPTION 'franchise_fee_as_of: p_valid_at and p_recorded_at are both required — pass the run''s (valid, recorded) coordinate pair; never default to now() (CI-001 / CI-003 / CI-006)';
    END IF;
    RETURN QUERY
    SELECT f.* FROM public.franchise_fee_rules f
    WHERE f.tenant_id = p_tenant_id AND f.city_name = p_city_name
      AND f.recorded_at <= p_recorded_at AND (f.recorded_until IS NULL OR f.recorded_until > p_recorded_at)
      AND f.effective_date <= p_valid_at AND (f.expiry_date IS NULL OR f.expiry_date >= p_valid_at)
    ORDER BY f.recorded_at DESC, f.id
    LIMIT 1;
END;
$$;

CREATE OR REPLACE FUNCTION public.customer_tax_exemption_as_of(p_customer_id uuid, p_valid_at date, p_recorded_at timestamp with time zone)
    RETURNS SETOF public.customer_tax_exemptions
    LANGUAGE plpgsql STABLE
    SET search_path = public, pg_temp
    AS $$
BEGIN
    IF p_valid_at IS NULL OR p_recorded_at IS NULL THEN
        RAISE EXCEPTION 'customer_tax_exemption_as_of: p_valid_at and p_recorded_at are both required — pass the run''s (valid, recorded) coordinate pair; never default to now() (CI-001 / CI-003 / CI-006)';
    END IF;
    RETURN QUERY
    SELECT e.* FROM public.customer_tax_exemptions e
    WHERE e.customer_id = p_customer_id
      AND e.recorded_at IS NOT NULL
      AND e.recorded_at <= p_recorded_at AND (e.recorded_until IS NULL OR e.recorded_until > p_recorded_at)
      AND e.effective_start <= p_valid_at AND (e.effective_end IS NULL OR e.effective_end >= p_valid_at)
    ORDER BY e.recorded_at DESC, e.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.wna_monthly_adjustment_as_of(p_wna_zone_id uuid, p_billing_month date, p_recorded_at timestamp with time zone)
    RETURNS SETOF public.wna_monthly_adjustments
    LANGUAGE plpgsql STABLE
    SET search_path = public, pg_temp
    AS $$
BEGIN
    IF p_billing_month IS NULL OR p_recorded_at IS NULL THEN
        RAISE EXCEPTION 'wna_monthly_adjustment_as_of: p_billing_month (the valid-time coordinate) and p_recorded_at are both required; never default to now() (CI-001 / CI-003 / CI-006)';
    END IF;
    RETURN QUERY
    SELECT w.* FROM public.wna_monthly_adjustments w
    WHERE w.wna_zone_id = p_wna_zone_id
      AND w.billing_month = date_trunc('month', p_billing_month)::date
      AND w.recorded_at IS NOT NULL
      AND w.recorded_at <= p_recorded_at AND (w.recorded_until IS NULL OR w.recorded_until > p_recorded_at)
    ORDER BY w.recorded_at DESC, w.id
    LIMIT 1;
END;
$$;

COMMENT ON FUNCTION public.rate_schedule_as_of(uuid, date, timestamp with time zone) IS
    'A-1 lookup (v5.4.2-03, R-15). The rate_schedule_versions row asserted at transaction time p_recorded_at whose valid bracket covers p_valid_at. Both coordinates REQUIRED; NULL raises; there is no now() default and no fallback to any live column. Zero rows = unknowable at that coordinate — the caller treats it as a hard error, never as "use the current version". Three call shapes, one contract: new bill (service period, now()); correction run — RRC default — (original period, now(), so a correction discovered since is picked up); reproduce/defend the original bill (original period, the original run''s recorded_at). Date policy belongs to the billing run, not here (R-16 keeps a GUC-defaulted layer addable over these).';
COMMENT ON FUNCTION public.wna_zone_as_of(uuid, date, timestamp with time zone) IS
    'A-1 lookup (v5.4.2-03, R-15): wna_zone_versions at (p_valid_at, p_recorded_at). Same contract as rate_schedule_as_of — both coordinates required, NULL raises, zero rows = unknowable.';
COMMENT ON FUNCTION public.rate_item_as_of(uuid, date, timestamp with time zone) IS
    'A-1 lookup (v5.4.2-03, R-15): rate_item_versions at (p_valid_at, p_recorded_at) — rate_value, rate_unit, tier_config, calculation_type, taxability, regulatory_class as asserted then. Replaces get_effective_rate''s current_rate read. Same contract as rate_schedule_as_of.';
COMMENT ON FUNCTION public.rate_schedule_item_as_of(uuid, uuid, date, timestamp with time zone) IS
    'A-1 lookup (v5.4.2-03, R-15): the schedule-level override row for (schedule, item) at (p_valid_at, p_recorded_at). COALESCE its *_override columns over rate_item_as_of() to get the effective rate — that composition is the billing engine''s, not this function''s. Same contract as rate_schedule_as_of.';
COMMENT ON FUNCTION public.franchise_fee_as_of(uuid, text, date, timestamp with time zone) IS
    'A-1 lookup (v5.4.2-03, R-15): the franchise_fee_rules row for (tenant, city) at (p_valid_at, p_recorded_at). Same contract as rate_schedule_as_of.';
COMMENT ON FUNCTION public.customer_tax_exemption_as_of(uuid, date, timestamp with time zone) IS
    'A-1 lookup (v5.4.2-03, R-15): every ASSERTED exemption row (recorded_at set — pending/rejected drafts never appear) for the customer whose transaction bracket covers p_recorded_at and whose valid bracket [effective_start, effective_end] covers p_valid_at. A revoked/expired successor row still covers the dates before its effective_end — that is the point. Service-type matching is the caller''s (should_charge_tax does it). Both coordinates required, NULL raises.';
COMMENT ON FUNCTION public.wna_monthly_adjustment_as_of(uuid, date, timestamp with time zone) IS
    'A-1 lookup (v5.4.2-03, R-15): the asserted (approved or later) wna_monthly_adjustments row for (zone, month) at transaction time p_recorded_at. Valid time is the billing month (p_billing_month is truncated to month). Pending drafts never appear. Both coordinates required, NULL raises, zero rows = unknowable.';

-- 7.1 should_charge_tax: transaction-time axis added; the CURRENT_DATE-defaulting signature dropped.
DROP FUNCTION IF EXISTS public.should_charge_tax(uuid, boolean, text, date);
CREATE OR REPLACE FUNCTION public.should_charge_tax(p_customer_id uuid, p_item_is_taxable boolean, p_service_type text, p_valid_at date, p_recorded_at timestamp with time zone) RETURNS boolean
    LANGUAGE plpgsql STABLE
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_has_exemption boolean;
BEGIN
    IF p_valid_at IS NULL OR p_recorded_at IS NULL THEN
        RAISE EXCEPTION 'should_charge_tax: p_valid_at and p_recorded_at are both required — never default to now() (CI-001 / CI-003 / CI-006)';
    END IF;

    -- Rule 1: item-level non-taxable wins
    IF p_item_is_taxable IS NULL OR p_item_is_taxable = false THEN
        RETURN false;
    END IF;

    -- Rule 2: a customer exemption asserted as of p_recorded_at, covering p_valid_at and the service type
    SELECT EXISTS (
        SELECT 1
        FROM public.customer_tax_exemption_as_of(p_customer_id, p_valid_at, p_recorded_at) cte
        WHERE (
              cte.service_types IS NULL
              OR array_length(cte.service_types, 1) IS NULL
              OR p_service_type IS NULL
              OR p_service_type = ANY(cte.service_types)
        )
    ) INTO v_has_exemption;

    IF v_has_exemption THEN
        RETURN false;
    END IF;

    -- Rule 3: taxable item, no exemption -> charge tax
    RETURN true;
END;
$$;

COMMENT ON FUNCTION public.should_charge_tax(uuid, boolean, text, date, timestamp with time zone) IS
    'Decides whether to tax a line item for a customer, at an explicit (valid, recorded) coordinate (re-issued v5.4.2-03, A-1 / R-15; the 4-argument form with p_as_of_date DEFAULT CURRENT_DATE was dropped — it filtered valid time only and defaulted to now()). Rules: (1) item non-taxable -> no tax; (2) an exemption asserted as of p_recorded_at whose bracket covers p_valid_at and matches the service type -> no tax; (3) otherwise tax. Both coordinates required, NULL raises. Correction runs pass the original period''s date; which recorded_at to pass (current knowledge vs the original run''s) is the run''s policy. No longer SECURITY DEFINER (the definer form read exemptions across tenants for any caller — RLS now applies); search_path pinned.';

-- 7.2 get_effective_rate: neutralised (LIMIT 1, no ORDER BY, no temporal predicate, read current_rate — which no longer exists).
CREATE OR REPLACE FUNCTION public.get_effective_rate(p_rate_schedule_id uuid, p_rate_item_id uuid, p_billing_month date DEFAULT CURRENT_DATE)
    RETURNS TABLE(effective_rate numeric, rate_unit text, is_active_this_month boolean, is_taxable boolean)
    LANGUAGE plpgsql STABLE
    SET search_path = public, pg_temp
    AS $$
BEGIN
    RAISE EXCEPTION USING
        MESSAGE = 'get_effective_rate() is deprecated and disabled (v5.4.2-03, A-1): it had no temporal predicate and returned an arbitrary row (LIMIT 1, no ORDER BY) from tables that are now multi-version. Compose rate_schedule_item_as_of(schedule, item, p_valid_at, p_recorded_at) over rate_item_as_of(item, p_valid_at, p_recorded_at) — COALESCE(rsi.rate_override, ri.rate_value), COALESCE(rsi.rate_unit_override, ri.rate_unit), COALESCE(rsi.is_taxable_override, ri.is_taxable_default), COALESCE(rsi.active_months_override, ri.active_months) — with an explicit coordinate pair.',
        ERRCODE = 'feature_not_supported';
END;
$$;
COMMENT ON FUNCTION public.get_effective_rate(uuid, uuid, date) IS
    'DISABLED by v5.4.2-03 (A-1): raises unconditionally with the replacement recipe. Kept so a caller fails loudly rather than resolving to nothing. The original filtered status = active only, ignored effective/expiry dates, did LIMIT 1 with no ORDER BY and read rate_items.current_rate (dropped). No longer SECURITY DEFINER; search_path pinned.';

-- 7.3 get_partial_period_policy: both axes (the 2-argument form read rate_schedules columns that moved).
DROP FUNCTION IF EXISTS public.get_partial_period_policy(uuid, timestamp with time zone);
CREATE OR REPLACE FUNCTION public.get_partial_period_policy(p_rate_schedule_id uuid, p_valid_at date, p_recorded_at timestamp with time zone)
    RETURNS text
    LANGUAGE plpgsql STABLE
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_override  text;
    v_tenant_id uuid;
    v_policy    text;
BEGIN
    IF p_valid_at IS NULL OR p_recorded_at IS NULL THEN
        RAISE EXCEPTION 'get_partial_period_policy: p_valid_at and p_recorded_at are both required — pass the run''s evaluation coordinates (CI-006)';
    END IF;

    SELECT v.partial_period_policy, v.tenant_id INTO v_override, v_tenant_id
    FROM public.rate_schedule_as_of(p_rate_schedule_id, p_valid_at, p_recorded_at) v;

    IF NOT FOUND THEN RETURN NULL; END IF;                       -- unknown schedule, or unknowable at that coordinate
    IF v_override IS NOT NULL THEN RETURN v_override; END IF;    -- per-schedule override wins

    SELECT h.new_value #>> '{}' INTO v_policy
    FROM public.tenant_configuration_history h
    WHERE h.tenant_id = v_tenant_id
      AND h.config_key = 'default_partial_period_policy'
      AND h.effective_from <= p_recorded_at                      -- that history is transaction time (D-2026-08-20-10)
    ORDER BY h.effective_from DESC, h.seq DESC
    LIMIT 1;

    RETURN v_policy;                                             -- NULL if the coordinate predates all history — no live fallback
END;
$$;

COMMENT ON FUNCTION public.get_partial_period_policy(uuid, date, timestamp with time zone) IS
    'Effective partial-period policy for a rate schedule at an explicit (valid, recorded) coordinate pair (re-issued v5.4.2-03 for A-1; the 2-argument v5.4.1-02 form was dropped — its rate_schedules read no longer exists and R-15 requires both axes everywhere). Both arguments REQUIRED; NULL RAISES — do not pass get_correction_rate_date()''s NULL through. Resolution: the schedule version at (p_valid_at, p_recorded_at) — its partial_period_policy override if set — else the tenant default recorded in tenant_configuration_history with the latest effective_from <= p_recorded_at (that bracket is transaction time). No fallback to the live tenants column: an unknown schedule, a coordinate no version covers, or a coordinate earlier than the tenant''s first recorded row returns NULL — a hard error to the engine, never "use the default".';

-- 7.4 get_correction_rate_date: the documented caller contract now names both axes; while touched, its
--     search_path is pinned (A-23 item; body unchanged, still v5.2.1 unqualified — safe under public, pg_temp).
ALTER FUNCTION public.get_correction_rate_date(uuid, uuid) SET search_path = public, pg_temp;
COMMENT ON FUNCTION public.get_correction_rate_date(p_billing_run_id uuid, p_voided_invoice_id uuid) IS
    'Returns the VALID-TIME coordinate (a date) for Phase 5 of a correction billing run — the original service period by default (CI-005), or the operator''s explicit election. Resolution: custom date > per-target historical/current > run-level default. Since v5.4.2-03 (A-1) the reference tables are bi-temporal, so this date alone does not identify a row: pass it as p_valid_at to the as-of family — rate_schedule_as_of, rate_item_as_of, rate_schedule_item_as_of, franchise_fee_as_of, wna_monthly_adjustment_as_of, customer_tax_exemption_as_of / should_charge_tax, get_partial_period_policy — together with ONE p_recorded_at chosen once per run (now() for "current knowledge", the original run''s instant to reproduce the original bill; CI-003). Never filter these tables with WHERE effective_date <= X alone — that matches every transaction-time version and a LIMIT 1 on top returns the latest correction, not what was known. Returns NULL if the target is not found: the engine must substitute and log — NULL passed to any as-of function RAISES.';

-- ----------------------------------------------------------------------------
-- 8. ENABLE ALWAYS on every guard this patch created (D-2026-08-20-27)
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
          AND t.tgname IN ('no_hard_delete', 'no_truncate',
                           'a_enforce_bitemporal_assertion', 'b_enforce_bitemporal_assertion',
                           'b_enforce_rate_schedule_version_rules', 'enforce_superseded_has_successor',
                           'enforce_reference_header', 'enforce_rate_schedule_lifecycle',
                           'a_enforce_tax_exemption_lifecycle', 'a_enforce_wna_adjustment_lifecycle',
                           'enforce_rate_schedule_assignable', 'retired_read_only', 'retired_no_truncate')
    LOOP
        EXECUTE format('ALTER TABLE public.%I ENABLE ALWAYS TRIGGER %I', r.relname, r.tgname);
    END LOOP;
END;
$$;
