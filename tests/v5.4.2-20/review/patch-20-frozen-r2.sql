-- ============================================================================
-- PATCH v5.4.2-20 — seal the version check (CI-011) and the void carve-out
--                    (A-23 item 1, AC-12)
-- ============================================================================
-- Authority:   Ryan, 2026-10-14: "yes, go ahead and draft it" — the corrected
--              design after the design review of
--              application/a23-seal-review-2026-10-14/ (Opus, Fable: sound
--              with changes; Codex: seal both, not as first written).
-- Spec:        application/a23-seal-review-2026-10-14/source-inventory-20.md
--              (requirements R1-R5, S1-S7, V1-V4, O1-O5, each tagged with
--              the review finding it comes from).
--
-- Revision r2 (review round 1: Opus, Fable, Codex all "not yet";
--   tests/v5.4.2-20/review/review-findings-20-r1.md):
--   the attach guard refuses a bill the caller cannot see, or of another
--   tenant than the row (F1); void_invoice() runs only at READ COMMITTED
--   (F2); a charge is billed if and only if it names its bill (F3); every
--   new guard is ENABLE ALWAYS (F4, D-2026-08-20-27); the invariant checks
--   exact identities, an exact privilege allowlist per seal role, and the
--   shape and state of every guard trigger (F5); tally_void's grants are
--   column-level and minimal (F6); the lock-order note states the deadlock
--   a caller can meet (F7).
--
-- ----------------------------------------------------------------------------
-- What changes
-- ----------------------------------------------------------------------------
--   Two roles own the two sealed acts. Both are NOLOGIN, hold no
--   SUPERUSER, BYPASSRLS, CREATEROLE, CREATEDB or REPLICATION, are members
--   of no role and have no members, can define no code, and own exactly
--   their functions (assert_seal_role_invariants(), run below and in CI).
--   Neither bypasses row-level security: what they read and write is the
--   caller's tenant, by the same policies tally_app meets.
--   * tally_seal owns assert_reference_version() and
--     reference_version_receipt_held().
--   * tally_void owns void_invoice().
--
--   The version check (CI-011, D1-1)
--   * tally_app loses UPDATE on the version column of rate_schedules,
--     rate_items and wna_zones: table-level UPDATE is revoked and the
--     sanctioned columns granted back (status, updated_at; on
--     rate_schedules also archive_reason, activated_at, archived_at).
--     updated_at stays: the rate_item_dependencies mutex writes it.
--   * A header is born at version 1.
--   * assert_reference_version() runs as tally_seal. It reads the header
--     under RLS (not visible: P0002, not retryable, naming nothing of
--     another tenant), bumps the version if the caller's token is current
--     (else 40001, as before), and writes a receipt:
--     (transaction, header table, entity, new version, tenant, time).
--   * reference_version_receipts holds them: append-only, RLS, readable and
--     writable by tally_seal alone; the database stamps the transaction and
--     the time.
--   * Every INSERT or UPDATE of rate_schedule_versions, rate_item_versions
--     and wna_zone_versions, and every lifecycle move of a header (status,
--     archive_reason, activated_at, archived_at), is refused unless this
--     transaction holds a receipt for that entity at its current version
--     (reference_version_receipt_held()). No role is exempt; the receipt
--     is the only door for ordinary writers (an administrator who can
--     write the receipts or disable triggers is outside this boundary).
--   * tally_core loses EXECUTE on assert_reference_version(): a read-only
--     core cannot bump a token through a definer.
--
--   The void (A-23 item 1, AC-12, v5.4.2-19 R14)
--   * void_invoice() runs as tally_void, no longer as the superuser: every
--     guard it meets binds it, and RLS scopes it to the caller's tenant.
--   * The read, charge and invoice guards admit the void's writes when
--     current_user = 'tally_void' — the owner of the running void_invoice(),
--     a role no caller can become — instead of the caller-settable session
--     setting of v5.4.2-01, which is gone from every function body. The
--     admission ends when the function returns.
--   * The charge guard admits exactly the void's disposition; a read is
--     released only if it names the bill it held; a bill is voided only by
--     an UPDATE (an INSERT born void only in a superuser's history load).
--   * Row-level security is the tenant check (tally_void does not bypass
--     it). The v5.2.1 comparison it replaces was NULL for a caller with no
--     tenant (no app.user_id, or one naming no user), so that caller voided
--     any tenant's bill (Opus, reproduced). Every refusal now reads
--     "Invoice not found" (P0002) and names only the caller's id.
--   * The invoice is locked (FOR UPDATE) before its status is read. A write
--     that attaches a read (locked_by_invoice_id) or a charge
--     (billed_on_invoice_id) to a bill takes FOR SHARE on the bill and
--     refuses a void one (enforce_attach_to_live_invoice).
--
-- ----------------------------------------------------------------------------
-- Lock order (stated once)
-- ----------------------------------------------------------------------------
--   Version check: the header row (assert_reference_version's UPDATE), then
--   the version rows. The receipt is written after the header lock.
--   Void: the invoice (FOR UPDATE), then its reads and charges.
--   Attach: the read or charge row, then the invoice (FOR SHARE). The void's
--   UPDATEs match only rows already committed as attached, so a void does
--   not wait on an attach in flight. A transaction that already holds a
--   row ATTACHED to the bill (an edit of a billed charge, say) and then
--   attaches another can deadlock with a void: PostgreSQL aborts one of the
--   two (40P01) and nothing is stranded. Retry the aborted transaction
--   (races/seal-20.sh RC6). The void runs only at READ COMMITTED: under a
--   snapshot older than its lock it would miss an attach that committed
--   while it waited (r1 F2).
--
-- ----------------------------------------------------------------------------
-- Residuals (left on purpose)
-- ----------------------------------------------------------------------------
--   R1. The caller's identity is caller-asserted (Codex B3). app.user_id
--       decides every tenant wall, these two seals included: code running
--       as tally_app can name another real user, a platform administrator
--       included. Ryan's next decision; it binds this patch without
--       redoing it.
--   R2. The token is the caller's (Opus S2). The database proves that a
--       check ran in the transaction under the header row lock, not that
--       the token came from the read the edit is based on. AC-42.
--   R3. The caller contract changes (Codex S2): the check is called, in
--       the same transaction as the write, before a first version, before
--       every close, and before a lifecycle move. Autocommit between the
--       check and the write fails. AC-42; AC-12 rewritten.
--   R4. A write API over the version tables (Codex's alternative a) is the
--       next step if they ever get a second writer.
--   R5. Version rows do not carry the header version they were written
--       under (Opus S7); the receipts record it per transaction.
--   R6. The platform-admin and tenant-admin fences on users key on
--       current_user <> 'tally_app' and stand aside inside any definer
--       (Fable S5). Neither seal role holds a privilege on users (asserted),
--       so they are unreachable from them; invert them when a definer that
--       writes users is written.
--   R7. Schedule composition (rate_schedule_items, rate_item_dependencies)
--       is outside the token, by the D1-1 design (Opus S8).
--   R8. A charge INSERTed with voided_from_invoice_id set is not refused
--       (the charge guard is UPDATE-only); no sanctioned workflow writes
--       one, though a direct INSERT can. Candidate for the CI-017 lineage
--       patch.
--   R9. Receipts are permanent. They prove a check ran, not that an edit
--       followed (Codex S1).
--
-- Tests. battery-20 (G, S, V), races/seal-20.sh (RC1-RC6, RC3b, T1-T7) and
--   mutations-20.py (each guard and invariant caught at its named check).
--   Three older batteries change with it. battery-10 and battery-11 voided
--   bills with no app.user_id: they passed only through the Opus B1 hole,
--   and now name the bill's operator. battery-19 wrote a zone version with
--   no check and simulated the void with the old setting: it now calls the
--   check, and writes as tally_void.
--
-- PRECONDITION. v5.4.2-19 applied (tu.sql). Applied by a superuser, under
--   READ COMMITTED. The roles are cluster-wide: created if absent, their
--   attributes asserted either way. A second run finds
--   reference_version_receipts and skips the whole patch (psql's \if):
--   apply it with psql.
-- ============================================================================

SELECT to_regclass('public.reference_version_receipts') IS NOT NULL AS already \gset
\if :already
DO $$ BEGIN RAISE NOTICE 'v5.4.2-20: already applied (reference_version_receipts exists); nothing to do'; END $$;
\else
BEGIN;


-- ----------------------------------------------------------------------------
-- 1. The two roles (R1)
-- ----------------------------------------------------------------------------
DO $$
DECLARE r text;
BEGIN
    FOREACH r IN ARRAY ARRAY['tally_seal', 'tally_void'] LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = r) THEN
            EXECUTE format('CREATE ROLE %I NOLOGIN NOSUPERUSER NOBYPASSRLS NOCREATEROLE NOCREATEDB NOREPLICATION', r);
        END IF;
    END LOOP;
END $$;
-- A TEMPLATE clone restores TEMP to PUBLIC; the seal roles must define no
-- code in any database built from this one (the clone helpers revoke TEMP
-- from PUBLIC, and the invariant checks it).
REVOKE TEMP ON DATABASE :"DBNAME" FROM PUBLIC;
REVOKE ALL ON SCHEMA public FROM tally_seal, tally_void;
GRANT USAGE ON SCHEMA public TO tally_seal, tally_void;
-- The canonical policy calls the two helpers: a role subject to RLS needs them.
GRANT EXECUTE ON FUNCTION public.get_user_tenant_id(), public.is_platform_admin() TO tally_seal, tally_void;


-- ----------------------------------------------------------------------------
-- 2. The receipts (S3)
-- ----------------------------------------------------------------------------
CREATE TABLE public.reference_version_receipts (
    xact          xid8 NOT NULL,
    header_table  text NOT NULL,
    entity_id     uuid NOT NULL,
    version       integer NOT NULL,
    tenant_id     uuid NOT NULL REFERENCES public.tenants(id),
    at            timestamptz NOT NULL,
    PRIMARY KEY (xact, header_table, entity_id, version),
    CONSTRAINT reference_version_receipts_header_check
        CHECK (header_table = ANY (ARRAY['rate_schedules', 'rate_items', 'wna_zones']))
);
-- O1: the default ACL hands tally_app every privilege on a new table.
REVOKE ALL ON public.reference_version_receipts FROM PUBLIC, tally_app, tally_core;
GRANT SELECT, INSERT ON public.reference_version_receipts TO tally_seal;
ALTER TABLE public.reference_version_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reference_version_receipts FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON public.reference_version_receipts
    USING (public.is_platform_admin() OR tenant_id = public.get_user_tenant_id());
COMMENT ON TABLE public.reference_version_receipts IS
    'CI-011 (v5.4.2-20). One row per successful assert_reference_version(): in transaction xact, header_table/entity_id was checked against the caller''s token and bumped to version. Written only by that function (as tally_seal); xact and at are stamped by the database. A version row, or a header lifecycle move, is admitted only while its transaction holds the receipt for the entity''s current version (reference_version_receipt_held()). Append-only and permanent: a receipt proves a check ran, not that an edit followed.';

-- The database stamps the transaction and the time; nothing edits a receipt.
CREATE FUNCTION public.stamp_reference_version_receipt() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
BEGIN
    IF TG_OP <> 'INSERT' THEN
        RAISE EXCEPTION USING
            MESSAGE = 'reference_version_receipts is append-only (CI-011, v5.4.2-20)',
            ERRCODE = 'restrict_violation';
    END IF;
    NEW.xact := pg_catalog.pg_current_xact_id();
    NEW.at := pg_catalog.now();
    RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.stamp_reference_version_receipt() FROM PUBLIC, tally_app, tally_core;
CREATE TRIGGER a_stamp_reference_version_receipt BEFORE INSERT OR UPDATE ON public.reference_version_receipts
    FOR EACH ROW EXECUTE FUNCTION public.stamp_reference_version_receipt();
CREATE TRIGGER no_hard_delete BEFORE DELETE ON public.reference_version_receipts
    FOR EACH ROW EXECUTE FUNCTION public.enforce_no_hard_delete();
CREATE TRIGGER no_truncate BEFORE TRUNCATE ON public.reference_version_receipts
    FOR EACH STATEMENT EXECUTE FUNCTION public.enforce_no_hard_delete();
-- F4: guards fire under replication apply too (D-2026-08-20-27).
ALTER TABLE public.reference_version_receipts ENABLE ALWAYS TRIGGER a_stamp_reference_version_receipt;
ALTER TABLE public.reference_version_receipts ENABLE ALWAYS TRIGGER no_hard_delete;
ALTER TABLE public.reference_version_receipts ENABLE ALWAYS TRIGGER no_truncate;


-- ----------------------------------------------------------------------------
-- 3. The check and the receipt test (S4, S5)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.assert_reference_version(p_table text, p_id uuid, p_expected_version integer) RETURNS integer
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_tenant uuid;
    v_new    integer;
BEGIN
    IF p_table IS NULL OR p_id IS NULL OR p_expected_version IS NULL THEN
        RAISE EXCEPTION 'assert_reference_version: p_table, p_id and p_expected_version are all required';
    END IF;
    IF p_table NOT IN ('rate_schedules', 'wna_zones', 'rate_items') THEN
        RAISE EXCEPTION 'assert_reference_version: % is not a versioned reference header (rate_schedules | wna_zones | rate_items)', p_table;
    END IF;
    -- Visible first, under RLS (this function's owner does not bypass it):
    -- an entity the caller cannot see is not a stale token, and a 40001
    -- would be retried for ever (O-S3).
    EXECUTE format('SELECT h.tenant_id FROM public.%I h WHERE h.id = $1', p_table)
        INTO v_tenant USING p_id;
    IF v_tenant IS NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('%s %s not found (CI-011)', p_table, p_id),
            ERRCODE = 'no_data_found';
    END IF;
    EXECUTE format('UPDATE public.%I SET version = version + 1, updated_at = now() WHERE id = $1 AND version = $2 RETURNING version', p_table)
        INTO v_new USING p_id, p_expected_version;
    IF v_new IS NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('%s %s was modified since it was read (expected version %s): review and retry (CI-011 / D1-1).', p_table, p_id, p_expected_version),
            ERRCODE = 'serialization_failure';
    END IF;
    -- The database stamps the transaction and the time (the receipts' trigger).
    INSERT INTO public.reference_version_receipts (header_table, entity_id, version, tenant_id)
    VALUES (p_table, p_id, v_new, v_tenant);
    RETURN v_new;
END;
$$;
COMMENT ON FUNCTION public.assert_reference_version(text, uuid, integer) IS
    'A-1 (v5.4.2-03), CI-011 per D1-1; sealed in v5.4.2-20. Call FIRST, in the same transaction, before inserting or closing version rows of a rate_schedules / wna_zones / rate_items entity, and before a lifecycle move of its header, passing the version the client read. Runs as tally_seal, under RLS: an entity the caller cannot see raises P0002 (not found); a stale token raises 40001 ("modified, review and retry"). Bumps the header version, row-locks the header until commit (serialising two writers on one entity), writes a reference_version_receipts row, and returns the new version. The receipt is what the version tables'' guard requires: there is no other way to write them.';
ALTER FUNCTION public.assert_reference_version(text, uuid, integer) OWNER TO tally_seal;
REVOKE ALL ON FUNCTION public.assert_reference_version(text, uuid, integer) FROM PUBLIC, tally_app, tally_core;
GRANT EXECUTE ON FUNCTION public.assert_reference_version(text, uuid, integer) TO tally_app;

CREATE FUNCTION public.reference_version_receipt_held(p_table text, p_id uuid) RETURNS boolean
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_xact    xid8 := pg_catalog.pg_current_xact_id_if_assigned();
    v_version integer;
BEGIN
    IF v_xact IS NULL OR p_id IS NULL OR p_table IS NULL
       OR p_table NOT IN ('rate_schedules', 'wna_zones', 'rate_items') THEN
        RETURN false;
    END IF;
    EXECUTE format('SELECT h.version FROM public.%I h WHERE h.id = $1', p_table)
        INTO v_version USING p_id;
    IF v_version IS NULL THEN
        RETURN false;
    END IF;
    -- at = now() binds the receipt to this transaction's start as well as
    -- its id: after a dump and restore the id counter can meet an old
    -- receipt's id again, but not, by ordinary means, its start time
    -- (O-S4). The version binds it to the header's current generation
    -- (C-Q2); the table and the entity name the header row.
    RETURN EXISTS (SELECT 1 FROM public.reference_version_receipts r
                    WHERE r.xact = v_xact
                      AND r.header_table = p_table
                      AND r.entity_id = p_id
                      AND r.version = v_version
                      AND r.at = pg_catalog.now());
END;
$$;
COMMENT ON FUNCTION public.reference_version_receipt_held(text, uuid) IS
    'CI-011 (v5.4.2-20). True when the current transaction holds a reference_version_receipts row for this entity at its current version: assert_reference_version() ran in it. The transaction is the database''s own (pg_current_xact_id_if_assigned()), never the caller''s; a transaction that has written nothing holds no receipt. Runs as tally_seal under RLS; reads only the caller''s own transaction.';
ALTER FUNCTION public.reference_version_receipt_held(text, uuid) OWNER TO tally_seal;
REVOKE ALL ON FUNCTION public.reference_version_receipt_held(text, uuid) FROM PUBLIC, tally_app, tally_core;
GRANT EXECUTE ON FUNCTION public.reference_version_receipt_held(text, uuid) TO tally_app;

GRANT SELECT ON public.rate_schedules, public.rate_items, public.wna_zones TO tally_seal;
GRANT UPDATE (version, updated_at) ON public.rate_schedules, public.rate_items, public.wna_zones TO tally_seal;


-- ----------------------------------------------------------------------------
-- 4. The version tables and the headers (S2, S6, S7)
-- ----------------------------------------------------------------------------
CREATE FUNCTION public.enforce_reference_version_receipt() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_id uuid := (to_jsonb(NEW) ->> TG_ARGV[1])::uuid;
BEGIN
    IF NOT public.reference_version_receipt_held(TG_ARGV[0], v_id) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('%s: a version of %s %s is written only after the version check, in the same transaction: call assert_reference_version(''%s'', %s, <the version you read>) first (CI-011, v5.4.2-20)',
                             TG_TABLE_NAME, TG_ARGV[0], v_id, TG_ARGV[0], v_id),
            ERRCODE = 'restrict_violation';
    END IF;
    RETURN NEW;
END;
$$;
COMMENT ON FUNCTION public.enforce_reference_version_receipt() IS
    'CI-011 (v5.4.2-20). BEFORE INSERT OR UPDATE on rate_schedule_versions, rate_item_versions and wna_zone_versions (TG_ARGV: header table, the entity column). Every write needs reference_version_receipt_held() for the entity: no role, depth or label is exempt, so the check is the only door. Sorts first, so an unchecked write is told so before any other rule.';
REVOKE ALL ON FUNCTION public.enforce_reference_version_receipt() FROM PUBLIC, tally_app, tally_core;
CREATE TRIGGER a0_enforce_reference_version_receipt BEFORE INSERT OR UPDATE ON public.rate_schedule_versions
    FOR EACH ROW EXECUTE FUNCTION public.enforce_reference_version_receipt('rate_schedules', 'rate_schedule_id');
CREATE TRIGGER a0_enforce_reference_version_receipt BEFORE INSERT OR UPDATE ON public.rate_item_versions
    FOR EACH ROW EXECUTE FUNCTION public.enforce_reference_version_receipt('rate_items', 'rate_item_id');
CREATE TRIGGER a0_enforce_reference_version_receipt BEFORE INSERT OR UPDATE ON public.wna_zone_versions
    FOR EACH ROW EXECUTE FUNCTION public.enforce_reference_version_receipt('wna_zones', 'wna_zone_id');
ALTER TABLE public.rate_schedule_versions ENABLE ALWAYS TRIGGER a0_enforce_reference_version_receipt;
ALTER TABLE public.rate_item_versions ENABLE ALWAYS TRIGGER a0_enforce_reference_version_receipt;
ALTER TABLE public.wna_zone_versions ENABLE ALWAYS TRIGGER a0_enforce_reference_version_receipt;
-- (A version row's entity column is frozen by the bitemporal guard, so the
-- NEW row's entity is the row's entity on UPDATE too.)

-- A header is born at version 1 (C-B1): the counter is the database's.
CREATE FUNCTION public.enforce_reference_header_birth() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
BEGIN
    IF NEW.version IS DISTINCT FROM 1 THEN
        RAISE EXCEPTION USING
            MESSAGE = format('%s: a header is created at version 1 (got %s); the version moves only through assert_reference_version() (CI-011, v5.4.2-20)', TG_TABLE_NAME, NEW.version),
            ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.enforce_reference_header_birth() FROM PUBLIC, tally_app, tally_core;
CREATE TRIGGER enforce_reference_header_birth BEFORE INSERT ON public.rate_schedules
    FOR EACH ROW EXECUTE FUNCTION public.enforce_reference_header_birth();
CREATE TRIGGER enforce_reference_header_birth BEFORE INSERT ON public.rate_items
    FOR EACH ROW EXECUTE FUNCTION public.enforce_reference_header_birth();
CREATE TRIGGER enforce_reference_header_birth BEFORE INSERT ON public.wna_zones
    FOR EACH ROW EXECUTE FUNCTION public.enforce_reference_header_birth();
ALTER TABLE public.rate_schedules ENABLE ALWAYS TRIGGER enforce_reference_header_birth;
ALTER TABLE public.rate_items ENABLE ALWAYS TRIGGER enforce_reference_header_birth;
ALTER TABLE public.wna_zones ENABLE ALWAYS TRIGGER enforce_reference_header_birth;

-- The header guard: a lifecycle move needs the receipt too (S7).
CREATE OR REPLACE FUNCTION public.enforce_reference_header()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
    -- v5.4.2-20 (F-S6): a lifecycle move (status and the columns that go
    -- with it) is an edit of the entity: it needs the version check in this
    -- transaction, as a version row does. The check's own bump changes only
    -- version and updated_at.
    IF (v_old - 'version' - 'updated_at') IS DISTINCT FROM (v_new - 'version' - 'updated_at')
       AND NOT public.reference_version_receipt_held(TG_TABLE_NAME, (v_new ->> 'id')::uuid) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('%s %s: a lifecycle change needs the version check first, in this transaction: call assert_reference_version(''%s'', id, <the version you read>) (CI-011, v5.4.2-20)', TG_TABLE_NAME, v_new ->> 'id', TG_TABLE_NAME),
            ERRCODE = 'restrict_violation';
    END IF;
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
$function$;


-- tally_app keeps UPDATE on the sanctioned columns only (S1). A column
-- REVOKE alone is a no-op while the table-level grant stands.
REVOKE UPDATE ON public.rate_schedules, public.rate_items, public.wna_zones FROM tally_app;
GRANT UPDATE (status, updated_at, archive_reason, activated_at, archived_at) ON public.rate_schedules TO tally_app;
GRANT UPDATE (status, updated_at) ON public.rate_items, public.wna_zones TO tally_app;


-- ----------------------------------------------------------------------------
-- 5. The void (V1-V4)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.enforce_reading_validation_workflow()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_changed           text[] := '{}';
    v_is_void_operation boolean;
    v_void_transition   boolean;
    v_relock            boolean;
    v_super             boolean := (SELECT r.rolsuper FROM pg_catalog.pg_roles r WHERE r.rolname = current_user);
BEGIN
    -- v5.4.2-20: the void is the write made as tally_void, the owner of
    -- void_invoice() — current_user here only while that function runs, a
    -- role no caller can become (assert_seal_role_invariants). It replaces
    -- the caller-settable session setting of v5.4.2-01 (AC-12, A-23 item 1).
    -- The carve-out below still admits only what void_invoice() writes, and
    -- only for a read that names the bill it held (C-B2).
    v_is_void_operation := current_user = 'tally_void';
    v_void_transition := v_is_void_operation
                         AND OLD.validation_status = 'locked'
                         AND NEW.validation_status = 'void_released'
                         AND OLD.locked_by_invoice_id IS NOT NULL;

    -- -------------------------------------------------------------------------
    -- BLOCK 1: validation_status transitions
    -- -------------------------------------------------------------------------
    IF OLD.validation_status IS DISTINCT FROM NEW.validation_status THEN

        IF OLD.validation_status = 'locked' THEN
            IF NOT v_void_transition THEN
                RAISE EXCEPTION
                    'Cannot change validation_status from locked. '
                    'Locked readings are terminal — corrections must create a NEW reading '
                    'via the dispute/correction workflow (insert replacement with '
                    'replaces_read_id pointing here). '
                    'To void the invoice that locked this read, use void_invoice(). '
                    'Reading: %', OLD.id;
            END IF;

        ELSIF NOT (
               (OLD.validation_status = 'pending_review'
                    AND NEW.validation_status IN ('reviewed_clean','reviewed_with_exception','approved','excluded'))
            OR (OLD.validation_status = 'reviewed_clean'
                    AND NEW.validation_status IN ('approved','excluded'))
            OR (OLD.validation_status = 'reviewed_with_exception'
                    AND NEW.validation_status IN ('approved','excluded','pending_review'))
            OR (OLD.validation_status = 'approved'
                    AND NEW.validation_status IN ('released_to_billing','excluded','pending_review'))
            OR (OLD.validation_status = 'released_to_billing'
                    AND NEW.validation_status = 'locked')
            OR (OLD.validation_status = 'excluded'
                    AND NEW.validation_status = 'pending_review')
            OR (OLD.validation_status = 'void_released'
                    AND NEW.validation_status = 'released_to_billing') -- correction run re-locks
        ) THEN
            RAISE EXCEPTION
                'Invalid validation_status transition: % -> %. Reading: %',
                OLD.validation_status, NEW.validation_status, OLD.id;
        END IF;

        -- Locking guard: transitioning TO locked requires billing metadata;
        -- the lock time is the database's (v5.4.2-19), a superuser's kept.
        IF NEW.validation_status = 'locked' THEN
            IF NEW.billing_period_locked IS DISTINCT FROM true THEN
                RAISE EXCEPTION
                    'validation_status=locked requires billing_period_locked=true. Reading: %', OLD.id;
            END IF;
            IF NEW.locked_by_billing_run_id IS NULL THEN
                RAISE EXCEPTION
                    'validation_status=locked requires locked_by_billing_run_id. Reading: %', OLD.id;
            END IF;
            IF NOT v_super OR NEW.locked_at IS NULL THEN
                NEW.locked_at := now();
            END IF;
        END IF;

    END IF;

    -- -------------------------------------------------------------------------
    -- The lock flag is set only by the move to locked (a flag set on a read no
    -- run consumed would freeze it with a false "consumed" record).
    -- -------------------------------------------------------------------------
    IF NOT OLD.billing_period_locked AND NEW.billing_period_locked AND NEW.validation_status IS DISTINCT FROM 'locked' THEN
        RAISE EXCEPTION USING
            MESSAGE = format('meter reading %s: billing_period_locked is set only by the move to locked, by a billing run (CI-031, v5.4.2-19)', OLD.id),
            ERRCODE = 'check_violation';
    END IF;

    -- r3 (Fable S1): nor is the rest of the lock record written on a read no
    -- run has consumed. The lock time, run and bill come only with the move
    -- to locked; voided_from_invoice_id only from a void (Block 3).
    IF NOT OLD.billing_period_locked THEN
        IF NEW.voided_from_invoice_id IS DISTINCT FROM OLD.voided_from_invoice_id
           OR (NEW.validation_status IS DISTINCT FROM 'locked'
               AND (NEW.locked_at IS DISTINCT FROM OLD.locked_at
                    OR NEW.locked_by_billing_run_id IS DISTINCT FROM OLD.locked_by_billing_run_id
                    OR NEW.locked_by_invoice_id IS DISTINCT FROM OLD.locked_by_invoice_id)) THEN
            RAISE EXCEPTION USING
                MESSAGE = format('meter reading %s: the lock record (locked_at, locked_by_*, voided_from_invoice_id) of a read no billing run has consumed is written only by the move to locked (CI-031, v5.4.2-19)', OLD.id),
                ERRCODE = 'check_violation';
        END IF;
    END IF;

    -- -------------------------------------------------------------------------
    -- BLOCK 2: a read a billing run consumed keeps its record (v5.4.2-19,
    -- CI-025 / CI-031). Keyed on billing_period_locked, which stays true after
    -- void_released: the read a voided bill released is the evidence the
    -- correction run rebills from, and is frozen like a locked one. EVERY
    -- column is frozen except the follow-up fields named here (r2: a
    -- whitelist, so a column added later is frozen by default) and the lock
    -- fields Block 3 governs.
    -- -------------------------------------------------------------------------
    IF OLD.billing_period_locked THEN
        SELECT coalesce(array_agg(o.key ORDER BY o.key), '{}') INTO v_changed
          FROM jsonb_each(to_jsonb(OLD)) o
         WHERE o.key <> ALL (ARRAY[
                   -- follow-up work on a consumed read
                   'notes', 'tamper_investigated', 'tamper_investigation_notes',
                   'dispute_reason', 'dispute_raised_by', 'dispute_raised_at',
                   'dispute_resolved_by', 'dispute_resolved_at', 'dispute_resolution_notes',
                   'status', 'requires_followup', 'followup_priority', 'followup_notes',
                   'assigned_to_user_id', 'replaced_by_reading_id', 'triggers_correction_workflow',
                   -- governed by Block 1 and Block 3
                   'validation_status', 'locked_at', 'locked_by_billing_run_id',
                   'locked_by_invoice_id', 'voided_from_invoice_id'])
           AND o.value IS DISTINCT FROM (to_jsonb(NEW) -> o.key);
    END IF;

    -- -------------------------------------------------------------------------
    -- BLOCK 3: the lock pointers of a consumed read (locked or void_released).
    -- Two writes may move them: void_invoice()'s (locked -> void_released:
    -- locked_by_invoice_id cleared, voided_from_invoice_id := the bill it
    -- held, run and lock time unchanged) and a correction run's re-lock
    -- (released_to_billing -> locked: its own run, a bill where there was
    -- none, the lock time stamped by Block 1). voided_from_invoice_id is
    -- written by a void and by nothing else.
    -- -------------------------------------------------------------------------
    IF OLD.billing_period_locked THEN
        v_relock := OLD.validation_status = 'released_to_billing' AND NEW.validation_status = 'locked';
        IF v_void_transition THEN
            IF NEW.locked_by_invoice_id IS NOT NULL THEN v_changed := v_changed || 'locked_by_invoice_id (void must clear it)'::text; END IF;
            IF NEW.voided_from_invoice_id IS DISTINCT FROM OLD.locked_by_invoice_id THEN v_changed := v_changed || 'voided_from_invoice_id (void sets it to the bill it held)'::text; END IF;
        ELSE
            IF NEW.voided_from_invoice_id IS DISTINCT FROM OLD.voided_from_invoice_id THEN v_changed := v_changed || 'voided_from_invoice_id'::text; END IF;
            IF NEW.locked_by_invoice_id IS DISTINCT FROM OLD.locked_by_invoice_id
               AND NOT (v_relock AND OLD.locked_by_invoice_id IS NULL) THEN
                v_changed := v_changed || 'locked_by_invoice_id'::text;
            END IF;
        END IF;
        IF NOT v_relock THEN
            IF NEW.locked_by_billing_run_id IS DISTINCT FROM OLD.locked_by_billing_run_id THEN v_changed := v_changed || 'locked_by_billing_run_id'::text; END IF;
            IF NEW.locked_at                IS DISTINCT FROM OLD.locked_at                THEN v_changed := v_changed || 'locked_at'::text; END IF;
        END IF;
    END IF;

    IF cardinality(v_changed) > 0 THEN
        RAISE EXCEPTION USING
            MESSAGE = format('meter reading %s was consumed by a billing run (validation_status %s, billing_period_locked) and its billing fields are frozen (CI-025 / CI-031, v5.4.2-19): attempted change to %s',
                             OLD.id, OLD.validation_status, array_to_string(v_changed, ', ')),
            HINT = 'To correct a read, insert a NEW reading with replaces_read_id pointing here. To undo the bill, use void_invoice(). Editable on such reads: notes, tamper_investigated, tamper_investigation_notes, dispute_*, status, requires_followup, followup_*, assigned_to_user_id, replaced_by_reading_id, triggers_correction_workflow.',
            ERRCODE = 'restrict_violation';
    END IF;

    RETURN NEW;
END;
$function$;


CREATE OR REPLACE FUNCTION public.enforce_adhoc_charge_immutable()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_changed text[] := '{}';
    -- v5.4.2-20: the void is the write made as tally_void (void_invoice()'s
    -- owner, current_user only while it runs), not a caller-settable setting.
    v_void_op boolean := current_user = 'tally_void';
    v_void_disposition boolean;
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

    -- v5.4.2-20 (C-B2): the void's disposition, exactly. Leaving billed as
    -- tally_void clears the three billing pointers and records the bill it
    -- leaves in voided_from_invoice_id. (The run that billed it, and the
    -- charge's identity, are outside tally_void's column grants.) Anything
    -- else the role writes falls to the rules below.
    v_void_disposition := v_void_op AND OLD.status = 'billed'
                          AND NEW.status IN ('pending', 'void_pending_rebill');
    IF v_void_disposition
       AND NOT (OLD.billed_on_invoice_id IS NOT NULL
                AND NEW.billed_on_invoice_id IS NULL
                AND NEW.billed_on_line_item_id IS NULL
                AND NEW.billed_at IS NULL
                AND NEW.voided_from_invoice_id IS NOT DISTINCT FROM OLD.billed_on_invoice_id) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('adhoc charge %s: a void clears billed_on_invoice_id, billed_on_line_item_id and billed_at and sets voided_from_invoice_id to the bill it leaves (CI-013, v5.4.2-20)', OLD.charge_number),
            ERRCODE = 'restrict_violation';
    END IF;
    -- voided_from_invoice_id is written by a void and by nothing else.
    IF NEW.voided_from_invoice_id IS DISTINCT FROM OLD.voided_from_invoice_id AND NOT v_void_disposition THEN
        RAISE EXCEPTION USING
            MESSAGE = format('adhoc charge %s: voided_from_invoice_id is written only by void_invoice() (CI-013, v5.4.2-20)', OLD.charge_number),
            ERRCODE = 'restrict_violation';
    END IF;

    -- While billed, the billing pointers are part of the issued bill; only
    -- void_invoice()'s disposition (checked above) may touch them.
    IF OLD.status = 'billed' AND NOT v_void_disposition THEN
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
$function$;


CREATE OR REPLACE FUNCTION public.enforce_invoice_immutable()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
    -- held as voidable too): it posts the reversal, releases locked reads and
    -- disposes of billed charges before stamping the row. A bare write to
    -- 'void' would skip all of that and then be sealed for good (assessment
    -- finding, v5.4.2-02). v5.4.2-20: the void is an UPDATE made as
    -- tally_void, void_invoice()'s owner (current_user only while it runs; no
    -- caller can become it), replacing the caller-settable session setting
    -- of v5.4.2-01 (AC-12). An INSERT is born void only in a superuser's history load.
    IF NEW.status = 'void'
       AND (TG_OP = 'INSERT' OR OLD.status <> 'void')
       AND NOT (TG_OP = 'UPDATE' AND current_user = 'tally_void')
       AND NOT (TG_OP = 'INSERT' AND (SELECT r.rolsuper FROM pg_catalog.pg_roles r WHERE r.rolname = current_user)) THEN
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
$function$;


-- V4: a read or a charge is attached only to a live bill. FOR SHARE waits
-- for a void in flight (it holds the bill FOR UPDATE) and then reads its
-- committed status.
CREATE FUNCTION public.enforce_attach_to_live_invoice() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_invoice uuid := (to_jsonb(NEW) ->> TG_ARGV[0])::uuid;
    v_status  text;
    v_tenant  uuid;
BEGIN
    IF v_invoice IS NULL
       OR (TG_OP = 'UPDATE' AND (to_jsonb(OLD) ->> TG_ARGV[0])::uuid IS NOT DISTINCT FROM v_invoice) THEN
        RETURN NEW;
    END IF;
    SELECT i.status, i.tenant_id INTO v_status, v_tenant FROM public.invoices i WHERE i.id = v_invoice FOR SHARE;
    -- r2 (F1): a bill the caller cannot see is refused, not left to the
    -- foreign key (which checks only the id): tenant 1 billed a charge onto
    -- tenant 2's void bill. A bill of another tenant than the row is refused
    -- too: a platform administrator sees both.
    IF NOT FOUND OR v_tenant IS DISTINCT FROM NEW.tenant_id THEN
        RAISE EXCEPTION USING
            MESSAGE = format('%s: %s names no invoice of this row''s tenant visible to the caller (CI-012, v5.4.2-20)', TG_TABLE_NAME, TG_ARGV[0]),
            ERRCODE = 'restrict_violation';
    END IF;
    IF v_status = 'void' THEN
        RAISE EXCEPTION USING
            MESSAGE = format('%s: %s names a void invoice; a voided bill takes no new reads or charges — bill them on its correction (CI-012, v5.4.2-20)', TG_TABLE_NAME, TG_ARGV[0]),
            ERRCODE = 'restrict_violation';
    END IF;
    RETURN NEW;
END;
$$;
COMMENT ON FUNCTION public.enforce_attach_to_live_invoice() IS
    'v5.4.2-20 (A-23, Codex B6). BEFORE INSERT OR UPDATE OF the invoice pointer (TG_ARGV[0]) on meter_readings (locked_by_invoice_id) and adhoc_charges (billed_on_invoice_id): setting it to an invoice takes FOR SHARE on that invoice and refuses a void one, one the caller cannot see, and one of another tenant than the row. void_invoice() holds the invoice FOR UPDATE, so an attach racing a void waits for it and then sees void; a void racing an attach waits for the attach and then releases what it attached (both at READ COMMITTED; the void refuses any other level). A charge is billed only with its pointer (adhoc_charges_billed_names_its_bill), so entering billed always passes here.';
REVOKE ALL ON FUNCTION public.enforce_attach_to_live_invoice() FROM PUBLIC, tally_app, tally_core;
CREATE TRIGGER a_enforce_attach_to_live_invoice BEFORE INSERT OR UPDATE OF locked_by_invoice_id ON public.meter_readings
    FOR EACH ROW EXECUTE FUNCTION public.enforce_attach_to_live_invoice('locked_by_invoice_id');
CREATE TRIGGER a_enforce_attach_to_live_invoice BEFORE INSERT OR UPDATE OF billed_on_invoice_id ON public.adhoc_charges
    FOR EACH ROW EXECUTE FUNCTION public.enforce_attach_to_live_invoice('billed_on_invoice_id');
ALTER TABLE public.meter_readings ENABLE ALWAYS TRIGGER a_enforce_attach_to_live_invoice;
ALTER TABLE public.adhoc_charges ENABLE ALWAYS TRIGGER a_enforce_attach_to_live_invoice;
-- r2 (F3, Codex B1): a charge is billed if and only if it names its bill.
-- Without it a pending charge could carry a pointer to a live bill, keep it
-- through that bill's void (the void releases only billed charges), and then
-- be marked billed with the pointer unchanged, never meeting the guard.
ALTER TABLE public.adhoc_charges ADD CONSTRAINT adhoc_charges_billed_names_its_bill
    CHECK ((status = 'billed') = (billed_on_invoice_id IS NOT NULL));

CREATE OR REPLACE FUNCTION public.void_invoice(p_invoice_id uuid, p_voided_by uuid DEFAULT NULL::uuid, p_void_reason_code text DEFAULT NULL::text, p_void_reason_notes text DEFAULT NULL::text, p_rebill_expected boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
    -- v5.4.2-20 (C-B6): the invoice is locked before its status is read, so
    -- a second void waits here and then sees 'void'; a write attaching a
    -- read or a charge to it takes FOR SHARE on it and waits too
    -- (enforce_attach_to_live_invoice). Lock order: the invoice, then its
    -- reads and charges. The owner, tally_void, is subject to RLS: another
    -- tenant's invoice is not found.
    -- r2 (F2): only at READ COMMITTED. Under an older snapshot the release
    -- of reads and charges below would miss one attached while this waited
    -- for the lock, and the bill would be void with it still attached.
    IF pg_catalog.current_setting('transaction_isolation') <> 'read committed' THEN
        RAISE EXCEPTION USING
            MESSAGE = format('void_invoice() runs at READ COMMITTED (this transaction is %s): a void under an older snapshot misses what was attached to the bill while it waited for the lock (v5.4.2-20)', pg_catalog.current_setting('transaction_isolation')),
            ERRCODE = 'invalid_transaction_state';
    END IF;
    SELECT * INTO v_invoice
    FROM public.invoices
    WHERE id = p_invoice_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION USING
            MESSAGE = format('Invoice not found: %s', p_invoice_id),
            ERRCODE = 'no_data_found';
    END IF;

    -- -------------------------------------------------------------------------
    -- Step 1.1: the tenant. v5.4.2-20: row-level security is the check. The
    -- owner, tally_void, does not bypass it (assert_seal_role_invariants), so
    -- the SELECT above finds only what the caller's policy admits: its own
    -- tenant's invoices, every tenant's for a platform admin, none for a
    -- caller with no user or one naming no user. The v5.2.1 comparison it
    -- replaces (`tenant_id != get_user_tenant_id()`) was NULL for such a
    -- caller, so it never refused, and the then-superuser owner voided any
    -- tenant's bill (Opus B1); its refusal also named the other tenant's
    -- invoice number (Opus S6). A not-found names only the caller's id.
    -- -------------------------------------------------------------------------

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
    -- Step 2 (v5.4.2-20): no carve-out to arm. The read, charge and invoice
    -- guards admit the writes below because they run as this function's
    -- owner, tally_void (current_user inside a SECURITY DEFINER function, and
    -- in every trigger its statements fire). No caller can become that role,
    -- and the admission ends when this function returns.
    -- -------------------------------------------------------------------------

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
    -- v5.4.2-19: the balance is the sum of the customer's ledger rows (the
    -- stored running balance column is dropped). The sum names the tenant as
    -- well as the customer (RLS scopes it too, since v5.4.2-20).
    SELECT coalesce(sum(l.amount), 0) INTO v_new_running_bal
      FROM public.account_ledger l
     WHERE l.tenant_id = v_invoice.tenant_id
       AND l.customer_id = v_invoice.customer_id;

    -- -------------------------------------------------------------------------
    -- Step 7: Return payload
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
$function$;


COMMENT ON FUNCTION public.void_invoice(uuid, uuid, text, text, boolean) IS
    'Atomically voids a posted invoice — the ONLY way to set invoices.status = ''void'' outside a superuser''s history load. Locks the invoice, releases its locked reads, disposes of its billed ad-hoc charges, posts the void_reversal ledger row (with reverses_ledger_entry_id and reversal_reason, CI-017) and logs the event. Since v5.4.2-20 it runs as tally_void, a role subject to RLS that no caller can become: the read, charge and invoice guards admit its writes because they run as tally_void, and only while it runs. An invoice the caller cannot see, or a caller with no tenant, gets "Invoice not found" (P0002). Returns the customer''s summed ledger balance as credit_balance.';
ALTER FUNCTION public.void_invoice(uuid, uuid, text, text, boolean) OWNER TO tally_void;
REVOKE ALL ON FUNCTION public.void_invoice(uuid, uuid, text, text, boolean) FROM PUBLIC, tally_app, tally_core;
GRANT EXECUTE ON FUNCTION public.void_invoice(uuid, uuid, text, text, boolean) TO tally_app;

-- What void_invoice() and the triggers its writes fire read and write,
-- exactly (r2 F6: column-level UPDATE; enumerated by end-to-end runs for
-- every reason code, a held bill, an empty bill and a platform admin;
-- assert_seal_role_invariants() holds the role to this list).
GRANT SELECT ON public.invoices, public.meter_readings, public.adhoc_charges, public.account_ledger TO tally_void;
GRANT UPDATE (status, voided_at, voided_by, void_reason_code, void_reason_notes, void_rebill_expected, updated_at)
    ON public.invoices TO tally_void;
GRANT UPDATE (voided_from_invoice_id, locked_by_invoice_id, validation_status) ON public.meter_readings TO tally_void;
GRANT UPDATE (status, voided_from_invoice_id, billed_on_invoice_id, billed_on_line_item_id, billed_at, target_billing_period, updated_at)
    ON public.adhoc_charges TO tally_void;
GRANT INSERT ON public.account_ledger, public.invoice_events TO tally_void;


-- ----------------------------------------------------------------------------
-- 6. The invariants (R4, R5, O4, O5)
-- ----------------------------------------------------------------------------
-- The privileges a role holds directly, as text, schema-qualified (so the
-- rendering does not depend on any search_path): its own functions excluded.
CREATE FUNCTION public.seal_role_privileges(p_role text) RETURNS text[]
    LANGUAGE sql
    STABLE
    SET search_path = public, pg_temp
    AS $$
    SELECT coalesce(array_agg(g ORDER BY g), '{}') FROM (
        SELECT 'table ' || n.nspname || '.' || c.relname || ' ' || a.privilege_type AS g
          FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace, aclexplode(c.relacl) a
         WHERE a.grantee = p_role::regrole
        UNION ALL
        SELECT 'column ' || n.nspname || '.' || c.relname || '.' || t.attname || ' ' || a.privilege_type
          FROM pg_attribute t JOIN pg_class c ON c.oid = t.attrelid JOIN pg_namespace n ON n.oid = c.relnamespace, aclexplode(t.attacl) a
         WHERE a.grantee = p_role::regrole AND NOT t.attisdropped
        UNION ALL
        SELECT 'function ' || n.nspname || '.' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ') ' || a.privilege_type
          FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace, aclexplode(p.proacl) a
         WHERE a.grantee = p_role::regrole AND p.proowner <> p_role::regrole
           AND n.nspname NOT LIKE 'pg\_temp\_%'   -- a session's own temporary functions die with it
        UNION ALL
        SELECT 'schema ' || n.nspname || ' ' || a.privilege_type
          FROM pg_namespace n, aclexplode(n.nspacl) a
         WHERE a.grantee = p_role::regrole
        UNION ALL
        SELECT 'database ' || d.datname || ' ' || a.privilege_type
          FROM pg_database d, aclexplode(d.datacl) a
         WHERE a.grantee = p_role::regrole AND d.datname = current_database()
        UNION ALL
        SELECT 'type ' || n.nspname || '.' || y.typname || ' ' || a.privilege_type
          FROM pg_type y JOIN pg_namespace n ON n.oid = y.typnamespace, aclexplode(y.typacl) a
         WHERE a.grantee = p_role::regrole
    ) x;
$$;
COMMENT ON FUNCTION public.seal_role_privileges(text) IS
    'v5.4.2-20 r2. Every privilege the role holds directly in this database (tables, columns, functions it does not own outside a session''s temporary schema, schemas, the database, types), as sorted text. assert_seal_role_invariants() compares it with the exact list each seal role is granted.';
REVOKE ALL ON FUNCTION public.seal_role_privileges(text) FROM PUBLIC, tally_app, tally_core;

CREATE FUNCTION public.assert_seal_role_invariants() RETURNS void
    LANGUAGE plpgsql
    STABLE
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_bad    text;
    r        text;
    v_have   text[];
    v_want   text[];
    -- Exactly what each role owns (r2 F5: exact identities, not names).
    c_owns   CONSTANT jsonb := jsonb_build_object(
        'tally_seal', jsonb_build_array('public.assert_reference_version(text,uuid,integer)'::regprocedure::oid,
                                        'public.reference_version_receipt_held(text,uuid)'::regprocedure::oid),
        'tally_void', jsonb_build_array('public.void_invoice(uuid,uuid,text,text,boolean)'::regprocedure::oid));
    -- Exactly what each role is granted (r2 F5/F6): anything more or less raises.
    c_grants CONSTANT jsonb := jsonb_build_object(
        'tally_seal', '["column public.rate_items.updated_at UPDATE", "column public.rate_items.version UPDATE", "column public.rate_schedules.updated_at UPDATE", "column public.rate_schedules.version UPDATE", "column public.wna_zones.updated_at UPDATE", "column public.wna_zones.version UPDATE", "function public.get_user_tenant_id() EXECUTE", "function public.is_platform_admin() EXECUTE", "schema public USAGE", "table public.rate_items SELECT", "table public.rate_schedules SELECT", "table public.reference_version_receipts INSERT", "table public.reference_version_receipts SELECT", "table public.wna_zones SELECT"]'::jsonb,
        'tally_void', '["column public.adhoc_charges.billed_at UPDATE", "column public.adhoc_charges.billed_on_invoice_id UPDATE", "column public.adhoc_charges.billed_on_line_item_id UPDATE", "column public.adhoc_charges.status UPDATE", "column public.adhoc_charges.target_billing_period UPDATE", "column public.adhoc_charges.updated_at UPDATE", "column public.adhoc_charges.voided_from_invoice_id UPDATE", "column public.invoices.status UPDATE", "column public.invoices.updated_at UPDATE", "column public.invoices.void_reason_code UPDATE", "column public.invoices.void_reason_notes UPDATE", "column public.invoices.void_rebill_expected UPDATE", "column public.invoices.voided_at UPDATE", "column public.invoices.voided_by UPDATE", "column public.meter_readings.locked_by_invoice_id UPDATE", "column public.meter_readings.validation_status UPDATE", "column public.meter_readings.voided_from_invoice_id UPDATE", "function public.get_user_tenant_id() EXECUTE", "function public.is_platform_admin() EXECUTE", "schema public USAGE", "table public.account_ledger INSERT", "table public.account_ledger SELECT", "table public.adhoc_charges SELECT", "table public.invoice_events INSERT", "table public.invoices SELECT", "table public.meter_readings SELECT"]'::jsonb);
    -- Every guard of the two seals, by its exact definition, enabled ALWAYS
    -- (D-2026-08-20-27: a replication apply does not skip it).
    c_triggers CONSTANT text[] := ARRAY['CREATE TRIGGER a0_enforce_reference_version_receipt BEFORE INSERT OR UPDATE ON public.rate_item_versions FOR EACH ROW EXECUTE FUNCTION enforce_reference_version_receipt(''rate_items'', ''rate_item_id'')',
        'CREATE TRIGGER a0_enforce_reference_version_receipt BEFORE INSERT OR UPDATE ON public.rate_schedule_versions FOR EACH ROW EXECUTE FUNCTION enforce_reference_version_receipt(''rate_schedules'', ''rate_schedule_id'')',
        'CREATE TRIGGER a0_enforce_reference_version_receipt BEFORE INSERT OR UPDATE ON public.wna_zone_versions FOR EACH ROW EXECUTE FUNCTION enforce_reference_version_receipt(''wna_zones'', ''wna_zone_id'')',
        'CREATE TRIGGER a_enforce_attach_to_live_invoice BEFORE INSERT OR UPDATE OF billed_on_invoice_id ON public.adhoc_charges FOR EACH ROW EXECUTE FUNCTION enforce_attach_to_live_invoice(''billed_on_invoice_id'')',
        'CREATE TRIGGER a_enforce_attach_to_live_invoice BEFORE INSERT OR UPDATE OF locked_by_invoice_id ON public.meter_readings FOR EACH ROW EXECUTE FUNCTION enforce_attach_to_live_invoice(''locked_by_invoice_id'')',
        'CREATE TRIGGER a_stamp_reference_version_receipt BEFORE INSERT OR UPDATE ON public.reference_version_receipts FOR EACH ROW EXECUTE FUNCTION stamp_reference_version_receipt()',
        'CREATE TRIGGER enforce_adhoc_charge_immutable BEFORE UPDATE ON public.adhoc_charges FOR EACH ROW EXECUTE FUNCTION enforce_adhoc_charge_immutable()',
        'CREATE TRIGGER enforce_invoice_immutable BEFORE INSERT OR DELETE OR UPDATE ON public.invoices FOR EACH ROW EXECUTE FUNCTION enforce_invoice_immutable()',
        'CREATE TRIGGER enforce_reference_header BEFORE DELETE OR UPDATE ON public.rate_items FOR EACH ROW EXECUTE FUNCTION enforce_reference_header(''item_code'', ''rate_item_versions'', ''rate_item_id'')',
        'CREATE TRIGGER enforce_reference_header BEFORE DELETE OR UPDATE ON public.rate_schedules FOR EACH ROW EXECUTE FUNCTION enforce_reference_header(''code'', ''rate_schedule_versions'', ''rate_schedule_id'')',
        'CREATE TRIGGER enforce_reference_header BEFORE DELETE OR UPDATE ON public.wna_zones FOR EACH ROW EXECUTE FUNCTION enforce_reference_header(''zone_code'', ''wna_zone_versions'', ''wna_zone_id'')',
        'CREATE TRIGGER enforce_reference_header_birth BEFORE INSERT ON public.rate_items FOR EACH ROW EXECUTE FUNCTION enforce_reference_header_birth()',
        'CREATE TRIGGER enforce_reference_header_birth BEFORE INSERT ON public.rate_schedules FOR EACH ROW EXECUTE FUNCTION enforce_reference_header_birth()',
        'CREATE TRIGGER enforce_reference_header_birth BEFORE INSERT ON public.wna_zones FOR EACH ROW EXECUTE FUNCTION enforce_reference_header_birth()',
        'CREATE TRIGGER no_hard_delete BEFORE DELETE ON public.reference_version_receipts FOR EACH ROW EXECUTE FUNCTION enforce_no_hard_delete()',
        'CREATE TRIGGER no_truncate BEFORE TRUNCATE ON public.reference_version_receipts FOR EACH STATEMENT EXECUTE FUNCTION enforce_no_hard_delete()',
        'CREATE TRIGGER trg_enforce_reading_validation_workflow BEFORE UPDATE ON public.meter_readings FOR EACH ROW EXECUTE FUNCTION enforce_reading_validation_workflow()'];
BEGIN
    FOREACH r IN ARRAY ARRAY['tally_seal', 'tally_void'] LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = r) THEN
            RAISE EXCEPTION USING MESSAGE = format('%s does not exist (v5.4.2-20)', r), ERRCODE = 'invalid_grant_operation';
        END IF;
        IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = r
                      AND (rolsuper OR rolbypassrls OR rolcreaterole OR rolcreatedb OR rolcanlogin OR rolreplication)) THEN
            RAISE EXCEPTION USING
                MESSAGE = format('%s is NOLOGIN and holds no SUPERUSER, BYPASSRLS, CREATEROLE, CREATEDB or REPLICATION (v5.4.2-20)', r),
                ERRCODE = 'invalid_grant_operation';
        END IF;
        -- No members: a member could SET ROLE to it and write as the seal.
        SELECT string_agg(m.member::regrole::text, ', ' ORDER BY 1) INTO v_bad
          FROM pg_auth_members m WHERE m.roleid = r::regrole;
        IF v_bad IS NOT NULL THEN
            RAISE EXCEPTION USING
                MESSAGE = format('%s has members (%s): no role may become it (v5.4.2-20)', r, v_bad),
                ERRCODE = 'invalid_grant_operation';
        END IF;
        SELECT string_agg(m.roleid::regrole::text, ', ' ORDER BY 1) INTO v_bad
          FROM pg_auth_members m WHERE m.member = r::regrole;
        IF v_bad IS NOT NULL THEN
            RAISE EXCEPTION USING
                MESSAGE = format('%s is a member of %s: it belongs to no role (v5.4.2-20)', r, v_bad),
                ERRCODE = 'invalid_grant_operation';
        END IF;
        IF EXISTS (SELECT 1 FROM pg_default_acl d WHERE d.defaclrole = r::regrole)
           OR EXISTS (SELECT 1 FROM pg_default_acl d, aclexplode(d.defaclacl) a WHERE a.grantee = r::regrole) THEN
            RAISE EXCEPTION USING
                MESSAGE = format('%s holds or sets a default privilege: its grants are explicit (v5.4.2-20)', r),
                ERRCODE = 'invalid_grant_operation';
        END IF;
        -- No code of its own: effective privileges, through PUBLIC as well.
        SELECT string_agg(n.nspname, ', ' ORDER BY 1) INTO v_bad
          FROM pg_namespace n
         WHERE has_schema_privilege(r, n.oid, 'CREATE');
        IF has_database_privilege(r, current_database(), 'TEMP') OR has_database_privilege(r, current_database(), 'CREATE')
           OR v_bad IS NOT NULL THEN
            RAISE EXCEPTION USING
                MESSAGE = format('%s can define code (TEMP, CREATE on the database, or CREATE on schema %s) — after a TEMPLATE clone, revoke TEMP from PUBLIC (v5.4.2-20)', r, coalesce(v_bad, 'none')),
                ERRCODE = 'invalid_grant_operation';
        END IF;
        -- It owns exactly its functions, each a definer pinned to public, pg_temp, and no relation or type.
        SELECT string_agg(p.oid::regprocedure::text, ', ' ORDER BY 1) INTO v_bad
          FROM pg_proc p
         WHERE p.proowner = r::regrole
           AND NOT ((c_owns -> r) ? p.oid::text
                    AND p.prosecdef
                    AND coalesce(p.proconfig @> ARRAY['search_path=public, pg_temp'], false));
        IF v_bad IS NOT NULL THEN
            RAISE EXCEPTION USING
                MESSAGE = format('%s owns %s, which is not one of its pinned SECURITY DEFINER functions (v5.4.2-20)', r, v_bad),
                ERRCODE = 'invalid_grant_operation';
        END IF;
        SELECT string_agg(f::oid::regprocedure::text, ', ' ORDER BY 1) INTO v_bad
          FROM jsonb_array_elements_text(c_owns -> r) f
         WHERE NOT EXISTS (SELECT 1 FROM pg_proc p WHERE p.oid = f::oid AND p.proowner = r::regrole);
        IF v_bad IS NOT NULL THEN
            RAISE EXCEPTION USING
                MESSAGE = format('%s no longer owns %s: a DROP and CREATE reverts the owner to its creator — ALTER FUNCTION ... OWNER TO %s (v5.4.2-20)', r, v_bad, r),
                ERRCODE = 'invalid_grant_operation';
        END IF;
        IF EXISTS (SELECT 1 FROM pg_class c WHERE c.relowner = r::regrole)
           OR EXISTS (SELECT 1 FROM pg_type y WHERE y.typowner = r::regrole)
           OR EXISTS (SELECT 1 FROM pg_namespace n WHERE n.nspowner = r::regrole) THEN
            RAISE EXCEPTION USING MESSAGE = format('%s owns a relation, type or schema (v5.4.2-20)', r), ERRCODE = 'invalid_grant_operation';
        END IF;
        -- Exactly its grants (this also keeps both roles off users: R6).
        v_have := public.seal_role_privileges(r);
        SELECT coalesce(array_agg(x ORDER BY x), '{}') INTO v_want FROM jsonb_array_elements_text(c_grants -> r) x;
        IF EXISTS (SELECT 1 FROM unnest(v_have) x WHERE x <> ALL (v_want))
           OR EXISTS (SELECT 1 FROM unnest(v_want) x WHERE x <> ALL (v_have)) THEN
            RAISE EXCEPTION USING
                MESSAGE = format('%s holds other privileges than it is granted (v5.4.2-20): extra %s; missing %s', r,
                                 (SELECT coalesce(string_agg(x, '; '), 'none') FROM unnest(v_have) x WHERE x <> ALL (v_want)),
                                 (SELECT coalesce(string_agg(x, '; '), 'none') FROM unnest(v_want) x WHERE x <> ALL (v_have))),
                ERRCODE = 'invalid_grant_operation';
        END IF;
    END LOOP;

    -- R5: the core executes no definer but the two RLS helpers (O-B4, C-B4).
    SELECT string_agg(p.oid::regprocedure::text, ', ' ORDER BY 1) INTO v_bad
      FROM pg_proc p
     WHERE p.prosecdef
       AND p.oid NOT IN ('public.get_user_tenant_id()'::regprocedure, 'public.is_platform_admin()'::regprocedure)
       AND has_function_privilege('tally_core', p.oid, 'EXECUTE');
    IF v_bad IS NOT NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('tally_core can execute SECURITY DEFINER %s: a read-only core writes through no definer (v5.4.2-20)', v_bad),
            ERRCODE = 'invalid_grant_operation';
    END IF;

    -- O5: nothing around the check. No privilege at all on the receipts for
    -- the application, the core or PUBLIC, column grants included.
    SELECT string_agg(g || ' ' || p, ', ' ORDER BY 1) INTO v_bad
      FROM unnest(ARRAY['tally_app', 'tally_core', 'public']) g,
           unnest(ARRAY['SELECT', 'INSERT', 'UPDATE', 'REFERENCES']) p
     WHERE has_any_column_privilege(g, 'public.reference_version_receipts', p);
    IF v_bad IS NOT NULL
       OR has_table_privilege('tally_app', 'public.reference_version_receipts', 'DELETE, TRUNCATE')
       OR has_table_privilege('tally_core', 'public.reference_version_receipts', 'DELETE, TRUNCATE')
       OR has_table_privilege('public', 'public.reference_version_receipts', 'DELETE, TRUNCATE') THEN
        RAISE EXCEPTION USING
            MESSAGE = format('reference_version_receipts is reachable by tally_app, tally_core or PUBLIC (%s) (v5.4.2-20)', coalesce(v_bad, 'DELETE or TRUNCATE')),
            ERRCODE = 'invalid_grant_operation';
    END IF;
    SELECT string_agg(t, ', ' ORDER BY t) INTO v_bad
      FROM unnest(ARRAY['rate_schedules', 'rate_items', 'wna_zones']) t
     WHERE has_column_privilege('tally_app', ('public.' || t)::regclass, 'version', 'UPDATE')
        OR has_column_privilege('tally_core', ('public.' || t)::regclass, 'version', 'UPDATE')
        OR has_column_privilege('public', ('public.' || t)::regclass, 'version', 'UPDATE');
    IF v_bad IS NOT NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('the version column of %s is writable outside assert_reference_version() (v5.4.2-20)', v_bad),
            ERRCODE = 'invalid_grant_operation';
    END IF;

    -- O4, lexically: no function in public names the caller-settable void
    -- setting of v5.4.2-01 (a constructed name would pass; the guards key on
    -- the role, so such a function would change nothing they admit).
    SELECT string_agg(p.oid::regprocedure::text, ', ' ORDER BY 1) INTO v_bad
      FROM pg_proc p
     WHERE p.pronamespace = 'public'::regnamespace
       AND strpos(p.prosrc, 'app.' || 'void_operation') > 0;
    IF v_bad IS NOT NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('%s reads the caller-settable void setting; the void is the write made as tally_void (v5.4.2-20)', v_bad),
            ERRCODE = 'invalid_grant_operation';
    END IF;

    -- Every guard, exactly as defined, enabled ALWAYS.
    SELECT string_agg(d, E'\n  ' ORDER BY d) INTO v_bad
      FROM unnest(c_triggers) d
     WHERE NOT EXISTS (SELECT 1 FROM pg_trigger g
                        WHERE NOT g.tgisinternal AND g.tgenabled = 'A'
                          AND pg_get_triggerdef(g.oid) = d);
    IF v_bad IS NOT NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format(E'a seal guard is missing, changed, or not ENABLE ALWAYS (v5.4.2-20):\n  %s', v_bad),
            ERRCODE = 'invalid_grant_operation';
    END IF;
END;
$$;
COMMENT ON FUNCTION public.assert_seal_role_invariants() IS
    'v5.4.2-20 (r2). Raises unless: tally_seal and tally_void exist, are NOLOGIN without SUPERUSER, BYPASSRLS, CREATEROLE, CREATEDB or REPLICATION, have no members and are members of nothing, hold and set no default privilege, can define no code, own exactly their pinned SECURITY DEFINER functions (by identity) and no relation, type or schema, and hold exactly their granted privileges (seal_role_privileges); tally_core executes no definer but the two RLS helpers (by identity); tally_app, tally_core and PUBLIC hold no privilege on the receipts and no UPDATE on a header version; no public function names the old void setting (a lexical test); and every guard of the two seals exists exactly as defined and ENABLE ALWAYS. Run in the patch tail and in CI.';
REVOKE ALL ON FUNCTION public.assert_seal_role_invariants() FROM PUBLIC, tally_app, tally_core;

DO $$ BEGIN
    PERFORM public.assert_seal_role_invariants();
    PERFORM public.assert_core_role_invariants();
    PERFORM public.assert_tenant_isolation_invariants();
END $$;

-- ============================================================================
-- END PATCH v5.4.2-20
-- ============================================================================

COMMIT;
\endif
