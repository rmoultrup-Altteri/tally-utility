-- ============================================================================
-- PATCH v5.4.2-21 — wave 1 built: retention (CI-014), bill-line arithmetic
--                    (CI-016), lineage (CI-017); the void's reversal; the
--                    identity follow-ups (R1); the -20 notes
-- ============================================================================
-- Authority:   Ryan, 2026-10-14: "ok go ahead with -21", over the decisions
--              of 2026-10-14 in application/DECISION-LOG.md (CI-014, CI-016,
--              CI-017; R1, Cognito identity; the void's reversal, "yes, go
--              with the default"; the rate-dependency retirement, drafting).
-- Spec:        application/wave1-build-2026-10-14/source-inventory-21.md
--              (requirements D, L, K, A, G, V, U, N, T).
--
-- Revision r2 (review round 1: Opus, Fable, Codex all "not yet";
--   tests/v5.4.2-21/review/review-findings-21-r1.md):
--   a surcharge whose rate item has no version visible at the bill's
--   coordinate needs its figures (all three, B1); the arithmetic is read at
--   the bill's snapshot date, not its period end (Codex B2); a
--   label's key, entity and tenant are write-once (Opus B3, Fable B1); a
--   supervisor binds an identity and switches a user on or off (Opus B2);
--   the void's charge is the bill's customer's (Opus S1); the void's
--   reversal is one act under one name, at most once per entry (Opus S2,
--   Fable S3); the label lock waits at most 5 s and the deadlock note is
--   corrected (all three); retired_by is the session's user (Opus S4, Fable
--   N7); a gas rider does not carry the commodity rate (Fable S4); the
--   invariants watch every new guard (Codex S1, Fable S2).
--
-- Revision r3 (review round 2: Codex ready; Opus, Fable "not yet";
--   tests/v5.4.2-21/review/review-findings-21-r2.md): the arithmetic is read
--   under current knowledge, now(), at the snapshot's date — the snapshot's
--   recorded_at is the caller's to choose and could hide a reclassification
--   (Fable B1); binding or switching a platform administrator takes a
--   platform administrator (Opus B1).
--
-- Revision r4 (review round 3: Opus, Fable "not yet" on the same item):
--   taking a user out of tenant_admin or platform_admin is switching it off,
--   and is guarded as such (Opus B1, Fable B1).
--
-- ----------------------------------------------------------------------------
-- What changes
-- ----------------------------------------------------------------------------
--   Retention (CI-014)
--   * Sixteen tables refuse DELETE and TRUNCATE for every role
--     (enforce_no_hard_delete, ENABLE ALWAYS), and tally_app loses DELETE on
--     them (D1, D2). The decision says 17 and lists 16; the catalog agrees
--     with the list (D0).
--   * custom_field_definitions and custom_location_types stay deletable, but
--     a delete is refused while the label is in use (L1, L2). The guard locks
--     the entity table in SHARE mode before it looks, and runs only at READ
--     COMMITTED (L3). A label's key, entity and tenant are write-once (r2).
--     This is a deletion-time check, not referential integrity: a write that
--     commits after the delete, or one later in the deleting transaction,
--     may still use the key.
--   * Consequence: a tenant, a customer (auto_pay_settings) or a read cycle
--     instance (read_cycle_meters) with a retained child can no longer be
--     deleted by anyone.
--   * rate_item_dependencies is retired, not deleted: retired_at (stamped by
--     the database), retired_by, retired_reason. A dependency is write-once
--     except for its retirement; uniqueness and the cycle check count live
--     rows only (K1-K5).
--   * assert_no_hard_delete_invariants() checks D1, D2 and L's guards (D4).
--
--   Bill-line arithmetic (CI-016)
--   * At issue (a deferred check beside the snapshot and surcharge checks),
--     read at the bill's snapshot date under current knowledge, a usage line
--     carries quantity,
--     unit and rate (and on gas the factor, Ccf, therms and commodity rate);
--     a base line its rate, and its five coverage columns all or none; a
--     surcharge names a rate item with a version visible there, and a
--     per-unit one carries quantity, unit and rate (on gas also the factor,
--     Ccf and therms) (A1-A6).
--
--   Lineage (CI-017)
--   * A correction names the bill it replaces (G1).
--   * A void_reversal names the entry it reverses, of its own tenant, with a
--     reason (G2, G3); only a void_reversal is filed against an invoice void,
--     and an entry is reversed by a void at most once (r2).
--   * A refund names exactly one source: the payment it returns, or the
--     customer credit it pays out (new: refunds_customer_credit_id) (G4).
--   * A charge is never born with voided_from_invoice_id (G6, -20 R8).
--   * Every lineage column is indexed (G7).
--
--   The void (Ryan, 2026-10-14)
--   * A posted bill's void requires the bill's charge entry on the ledger
--     and names it; with none, the void is refused before it writes. A bill
--     never posted (voided from held) gets no ledger entry (V1, V2).
--
--   Identity (R1, AC-43)
--   * users.cognito_sub: unique, write-once once set (except a superuser
--     repair), nullable for service users (U1). For the application, binding
--     an identity and switching a user on or off take a supervisor (r2): a
--     user is bound when a supervisor provisions it, not at its own first
--     login.
--   * The RLS helpers see only an active user (U2).
--
--   The -20 notes
--   * REVOKE TEMP via current_database(), with no psql variable (N1).
--   * The PUBLIC clause says "relation" (N2); the trigger strings are
--     PostgreSQL 16's rendering (N3).
--
-- ----------------------------------------------------------------------------
-- Lock order and isolation
-- ----------------------------------------------------------------------------
--   A label delete holds the label row, then SHARE on its entity table.
--   SHARE conflicts with every writer of that table, across tenants, and
--   with maintenance (VACUUM, ANALYZE, CREATE INDEX CONCURRENTLY): every
--   INSERT, UPDATE, DELETE or COPY on customers, invoices or payments waits
--   while a label delete of that entity is uncommitted, and also while one
--   is still waiting for its lock. The guard waits at most 5 s (55P03).
--   Keep label deletes short, in their own transaction.
--   Deadlock: two transactions that have each written the entity table and
--   then each delete any label of that entity deadlock; so do two that
--   delete labels and then write the table. PostgreSQL aborts one (40P01);
--   retry the whole transaction.
--   A retirement takes the schedule header (the -19 mutex), as an insert does.
--
-- ----------------------------------------------------------------------------
-- Residuals (left on purpose)
-- ----------------------------------------------------------------------------
--   R1. The void reverses -(amount_due), not the named charge's amount; a
--       bill with several charge entries names the earliest (V4). Posting is
--       the core's.
--   R2. A void_reversal must name an entry of its tenant, at most once, not
--       necessarily a charge of the same bill or customer: void_invoice()
--       writes the right one; another writer of a void_reversal is not
--       otherwise fenced (G2). The same customer was not ruled for the FK.
--   R3. rate_item_dependencies is still not effective-dated (-19 R4); a
--       retirement is transaction time only.
--   R4. The arithmetic check verifies that the figures are carried, not that
--       they multiply out: tiers, minimums and rounding are the core's.
--   R5. The -20 REVOKE TEMP line in tu.sql keeps its psql variable until Ryan
--       decides at mirror time whether the mirrored line may be replaced (N1).
--   R6. "Posted" is first_issued_at for every bill the application writes. A
--       superuser load stands outside it: it sets the stamp with the bill, or
--       the bill voids as a discard.
--   R7. Not mutation-tested: the issued-to-issued skip in the arithmetic gate
--       and its FOR SHARE on the lines (the siblings' model).
--   R8. A reverses_ledger_entry_id on a row that is not a void_reversal is
--       not constrained: an adjustment may name an entry with no reason
--       (Fable r2 S3). CI-017 binds the void's reversal; other reversal
--       kinds are not ruled.
--   R9. line_item_carries_base, the surcharge sibling's base rule, still
--       classifies at the period end, not a correction's elected date
--       (Fable r2, pre-existing); a follow-up.
--   R10. "Current knowledge" is the issuing transaction's start (now()), as
--       for the surcharge sibling: a reclassification committed while the
--       issuance is open is not seen (Codex r3 N3). A historical-mode rebill
--       of an item reclassified since must carry the figures its current
--       class needs, and an item whose version at the date was retracted
--       with no replacement cannot be reissued at all — only rebilled at
--       current knowledge (Opus r3, Codex r3 N2). The fail-safe side, by
--       ruling.
--
-- Tests. battery-21 (one row per requirement), races/labels-21.sh, and
--   mutations-21.py. The invariants assert_no_hard_delete_invariants() and
--   assert_wave1_guard_invariants() run in the tail and in CI. Older batteries that void a posted bill now plant its
--   charge entry first (T4).
--
-- PRECONDITION. v5.4.2-20 applied (tu.sql). Applied by a superuser, under
--   READ COMMITTED. A second run finds users.cognito_sub and skips the whole
--   patch (psql's \if): apply it with psql.
-- ============================================================================

SELECT EXISTS (SELECT 1 FROM pg_catalog.pg_attribute
                WHERE attrelid = 'public.users'::regclass AND attname = 'cognito_sub' AND NOT attisdropped) AS already \gset
\if :already
DO $$ BEGIN RAISE NOTICE 'v5.4.2-21: already applied (users.cognito_sub exists); nothing to do'; END $$;
\else
BEGIN;


-- ----------------------------------------------------------------------------
-- 1. Retention: sixteen tables never hard-deleted (D1, D2)
-- ----------------------------------------------------------------------------
DO $$
DECLARE t text;
BEGIN
    FOREACH t IN ARRAY ARRAY['ai_sessions', 'ai_suggestions', 'ai_tool_calls',
                             'billing_cycles', 'read_routes', 'jurisdictions', 'communities', 'deposit_utility_categories',
                             'bill_messages', 'auto_pay_settings', 'tenant_sequences',
                             'read_cycle_meters', 'alerts', 'service_location_acquisitions',
                             'rate_item_dependencies', 'pga_monitoring_settings'] LOOP
        EXECUTE format('DROP TRIGGER IF EXISTS no_hard_delete ON public.%I', t);
        EXECUTE format('CREATE TRIGGER no_hard_delete BEFORE DELETE ON public.%I FOR EACH ROW EXECUTE FUNCTION public.enforce_no_hard_delete()', t);
        EXECUTE format('ALTER TABLE public.%I ENABLE ALWAYS TRIGGER no_hard_delete', t);
        EXECUTE format('DROP TRIGGER IF EXISTS no_truncate ON public.%I', t);
        EXECUTE format('CREATE TRIGGER no_truncate BEFORE TRUNCATE ON public.%I FOR EACH STATEMENT EXECUTE FUNCTION public.enforce_no_hard_delete()', t);
        EXECUTE format('ALTER TABLE public.%I ENABLE ALWAYS TRIGGER no_truncate', t);
        EXECUTE format('REVOKE DELETE, TRUNCATE ON public.%I FROM tally_app', t);
    END LOOP;
END $$;


-- ----------------------------------------------------------------------------
-- 2. The custom labels: refused while in use (L1-L5)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.enforce_custom_label_unused() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public', 'pg_temp'
    AS $fn$
DECLARE
    v_table  regclass;
    v_key    text;
    v_in_use boolean;
    -- r2 (Opus S3): a delete waiting for SHARE queues every later writer of
    -- the entity table behind it; it gives up after this long (55P03).
    c_lock_wait CONSTANT text := '5s';
    v_saved  text := pg_catalog.current_setting('lock_timeout');
BEGIN
    -- The lock below makes every writer of the entity table finish first and
    -- every new one wait; only a snapshot taken after it sees them all.
    IF pg_catalog.current_setting('transaction_isolation') <> 'read committed' THEN
        RAISE EXCEPTION USING
            MESSAGE = format('%s: a label is deleted at READ COMMITTED (this transaction is %s): under an older snapshot the in-use check would miss a row written while it waited (CI-014, v5.4.2-21)', TG_TABLE_NAME, pg_catalog.current_setting('transaction_isolation')),
            ERRCODE = 'invalid_transaction_state';
    END IF;
    IF TG_TABLE_NAME = 'custom_field_definitions' THEN
        v_key   := OLD.field_key;
        v_table := pg_catalog.to_regclass('public.' || pg_catalog.quote_ident(OLD.entity_type));
        -- A table with no metadata holds no custom values (meter_readings,
        -- billing_runs): nothing can use the label.
        IF v_table IS NULL OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_attribute a
                                           WHERE a.attrelid = v_table AND a.attname = 'metadata' AND NOT a.attisdropped) THEN
            RETURN OLD;
        END IF;
        PERFORM pg_catalog.set_config('lock_timeout', c_lock_wait, true);
        EXECUTE format('LOCK TABLE %s IN SHARE MODE', v_table);
        PERFORM pg_catalog.set_config('lock_timeout', v_saved, true);
        EXECUTE format('SELECT EXISTS (SELECT 1 FROM %s e WHERE e.tenant_id = $1 AND e.metadata ? $2)', v_table)
           INTO v_in_use USING OLD.tenant_id, v_key;
    ELSE
        v_key   := OLD.type_key;
        v_table := 'public.service_locations'::regclass;
        PERFORM pg_catalog.set_config('lock_timeout', c_lock_wait, true);
        LOCK TABLE public.service_locations IN SHARE MODE;
        PERFORM pg_catalog.set_config('lock_timeout', v_saved, true);
        SELECT EXISTS (SELECT 1 FROM public.service_locations l
                        WHERE l.tenant_id = OLD.tenant_id AND l.location_type = OLD.type_key)
          INTO v_in_use;
    END IF;
    IF v_in_use THEN
        RAISE EXCEPTION USING
            MESSAGE = format('%s: label %s is in use on %s — archive it (status = archived) or clear it from those rows first (CI-014, v5.4.2-21)', TG_TABLE_NAME, v_key, v_table),
            ERRCODE = 'restrict_violation';
    END IF;
    RETURN OLD;
END;
$fn$;
COMMENT ON FUNCTION public.enforce_custom_label_unused() IS
    'v5.4.2-21 (CI-014). BEFORE DELETE on custom_field_definitions and custom_location_types: refused while a row of the same tenant uses the label (a metadata key on the entity table the definition names; service_locations.location_type for a location type). Takes SHARE on the entity table first (writers finish, new ones wait), waiting at most 5 s (55P03), and runs only at READ COMMITTED. Invoker rights: RLS applies. A deletion-time check, not referential integrity: a write after the delete commits, or later in the deleting transaction, may still use the key.';
REVOKE ALL ON FUNCTION public.enforce_custom_label_unused() FROM PUBLIC, tally_app, tally_core;

-- r2 (Opus B3, Fable B1): a label is its key. Renaming or re-pointing an
-- in-use label lost its values exactly as a delete did; the key columns are
-- write-once for every role. A renamed label is a new definition, and the
-- old one is archived (or deleted once unused).
CREATE OR REPLACE FUNCTION public.enforce_custom_label_key_frozen() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public', 'pg_temp'
    AS $fn$
DECLARE
    v_moved boolean;
BEGIN
    -- One branch per table: a record field is resolved when its expression runs.
    IF TG_TABLE_NAME = 'custom_field_definitions' THEN
        v_moved := (NEW.tenant_id, NEW.entity_type, NEW.field_key) IS DISTINCT FROM (OLD.tenant_id, OLD.entity_type, OLD.field_key);
    ELSE
        v_moved := (NEW.tenant_id, NEW.type_key) IS DISTINCT FROM (OLD.tenant_id, OLD.type_key);
    END IF;
    IF v_moved THEN
        RAISE EXCEPTION USING
            MESSAGE = format('%s: label %s keeps its key, entity and tenant — add a new label and archive this one (CI-014, v5.4.2-21)', TG_TABLE_NAME, OLD.id),
            ERRCODE = 'restrict_violation';
    END IF;
    RETURN NEW;
END;
$fn$;
COMMENT ON FUNCTION public.enforce_custom_label_key_frozen() IS
    'v5.4.2-21 r2 (CI-014). BEFORE UPDATE on custom_field_definitions (tenant_id, entity_type, field_key) and custom_location_types (tenant_id, type_key): the key columns are write-once for every role, so an in-use label cannot be renamed or re-pointed out from under its values.';
REVOKE ALL ON FUNCTION public.enforce_custom_label_key_frozen() FROM PUBLIC, tally_app, tally_core;

DO $$
DECLARE t text;
BEGIN
    FOREACH t IN ARRAY ARRAY['custom_field_definitions', 'custom_location_types'] LOOP
        EXECUTE format('DROP TRIGGER IF EXISTS a_enforce_custom_label_key_frozen ON public.%I', t);
        EXECUTE format('CREATE TRIGGER a_enforce_custom_label_key_frozen BEFORE UPDATE ON public.%I FOR EACH ROW EXECUTE FUNCTION public.enforce_custom_label_key_frozen()', t);
        EXECUTE format('ALTER TABLE public.%I ENABLE ALWAYS TRIGGER a_enforce_custom_label_key_frozen', t);
        EXECUTE format('DROP TRIGGER IF EXISTS a_enforce_custom_label_unused ON public.%I', t);
        EXECUTE format('CREATE TRIGGER a_enforce_custom_label_unused BEFORE DELETE ON public.%I FOR EACH ROW EXECUTE FUNCTION public.enforce_custom_label_unused()', t);
        EXECUTE format('ALTER TABLE public.%I ENABLE ALWAYS TRIGGER a_enforce_custom_label_unused', t);
        EXECUTE format('DROP TRIGGER IF EXISTS no_truncate ON public.%I', t);
        EXECUTE format('CREATE TRIGGER no_truncate BEFORE TRUNCATE ON public.%I FOR EACH STATEMENT EXECUTE FUNCTION public.enforce_no_hard_delete()', t);
        EXECUTE format('ALTER TABLE public.%I ENABLE ALWAYS TRIGGER no_truncate', t);
        EXECUTE format('REVOKE TRUNCATE ON public.%I FROM tally_app', t);
    END LOOP;
END $$;


-- ----------------------------------------------------------------------------
-- 3. Rate dependencies are retired, not deleted (K1-K5)
-- ----------------------------------------------------------------------------
ALTER TABLE public.rate_item_dependencies
    ADD COLUMN retired_at     timestamp with time zone,
    ADD COLUMN retired_by     uuid REFERENCES public.users(id),
    ADD COLUMN retired_reason text,
    ADD CONSTRAINT rate_item_dependencies_retired_pair_check
        CHECK ((retired_at IS NULL) = (retired_reason IS NULL)),
    ADD CONSTRAINT rate_item_dependencies_retired_reason_check
        CHECK (retired_reason IS NULL OR retired_reason ~ '[[:alnum:]]');
COMMENT ON COLUMN public.rate_item_dependencies.retired_at IS
    'v5.4.2-21 (CI-014). When the dependency was retired; stamped by the database. A retired dependency is kept for history, counts in neither the live uniqueness nor the cycle check, and is never revived (add it again).';

ALTER TABLE public.rate_item_dependencies DROP CONSTRAINT rate_item_dependencies_rate_schedule_id_dependent_rate_item_key;
CREATE UNIQUE INDEX rate_item_dependencies_live_key
    ON public.rate_item_dependencies (rate_schedule_id, dependent_rate_item_id, base_rate_item_id)
    WHERE retired_at IS NULL;

CREATE OR REPLACE FUNCTION public.enforce_rate_item_dependency() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public', 'pg_temp'
    AS $fn$
DECLARE
    v_bad    text;
    v_cycle  boolean;
BEGIN
    -- v5.4.2-21 (K2, K3): born live; an UPDATE only retires a live
    -- dependency, which is permanent; everything else is write-once.
    IF TG_OP = 'INSERT' THEN
        IF NEW.retired_at IS NOT NULL OR NEW.retired_by IS NOT NULL OR NEW.retired_reason IS NOT NULL THEN
            RAISE EXCEPTION USING
                MESSAGE = 'rate_item_dependencies: a dependency is born live — retire it with an UPDATE (CI-014, v5.4.2-21)',
                ERRCODE = 'check_violation';
        END IF;
    ELSE
        IF OLD.retired_at IS NOT NULL THEN
            RAISE EXCEPTION USING
                MESSAGE = format('rate_item_dependencies: dependency %s is retired, and a retirement is permanent — add the dependency again (CI-014, v5.4.2-21)', OLD.id),
                ERRCODE = 'restrict_violation';
        END IF;
        IF (NEW.id, NEW.tenant_id, NEW.rate_schedule_id, NEW.dependent_rate_item_id, NEW.base_rate_item_id, NEW.notes, NEW.created_at)
           IS DISTINCT FROM (OLD.id, OLD.tenant_id, OLD.rate_schedule_id, OLD.dependent_rate_item_id, OLD.base_rate_item_id, OLD.notes, OLD.created_at) THEN
            RAISE EXCEPTION USING
                MESSAGE = format('rate_item_dependencies: dependency %s is write-once — retire it and add a new one (CI-014, v5.4.2-21)', OLD.id),
                ERRCODE = 'restrict_violation';
        END IF;
        IF NEW.retired_reason IS NULL THEN
            RAISE EXCEPTION USING
                MESSAGE = format('rate_item_dependencies: the only change to dependency %s is its retirement, with a reason (CI-014, v5.4.2-21)', OLD.id),
                ERRCODE = 'restrict_violation';
        END IF;
        NEW.retired_at := now();
        -- r2 (Opus S4, Fable N7): who retired it is the session's user, as
        -- the database knows it, never a caller-chosen id.
        NEW.retired_by := NULLIF(pg_catalog.current_setting('app.user_id', true), '')::uuid;
        -- The mutex, as an insert takes it (one lock order); a retirement
        -- removes an edge and cannot close a cycle.
        UPDATE public.rate_schedules s SET updated_at = now() WHERE s.id = NEW.rate_schedule_id;
        RETURN NEW;
    END IF;

    -- Same tenant: the schedule and both items. The foreign keys are single-
    -- column and bypass row-level security, so the check is positive: each
    -- must be VISIBLE to the writer and of this row's tenant (another
    -- tenant's row is invisible to tally_app, and a superuser sees its
    -- tenant_id).
    SELECT string_agg(x.what, ', ') INTO v_bad FROM (
        SELECT 'rate schedule ' || NEW.rate_schedule_id AS what
         WHERE NOT EXISTS (SELECT 1 FROM public.rate_schedules s WHERE s.id = NEW.rate_schedule_id AND s.tenant_id = NEW.tenant_id)
        UNION ALL
        SELECT 'rate item ' || v.item_id
          FROM unnest(ARRAY[NEW.dependent_rate_item_id, NEW.base_rate_item_id]) AS v(item_id)
         WHERE NOT EXISTS (SELECT 1 FROM public.rate_items i WHERE i.id = v.item_id AND i.tenant_id = NEW.tenant_id)
    ) x;
    IF v_bad IS NOT NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('rate_item_dependencies: %s is not a row of this dependency''s tenant (CI-101 / CI-116, v5.4.2-19)', v_bad),
            ERRCODE = 'foreign_key_violation';
    END IF;

    -- Lock order (AC, r2/r3): a transaction that writes dependencies takes
    -- the schedule headers first, in schedule-id order (this bump, or
    -- assert_reference_version), and only then writes dependency rows; an
    -- UPDATE of an edge locks the edge before this bump, so a transaction
    -- holding the header that then edits the edge, against one editing the
    -- edge, deadlocks. PostgreSQL cancels one; the caller retries the whole
    -- transaction on deadlock_detected or serialization_failure. A cancelled
    -- participant never lets a cycle through.
    -- Row-version mutex on the schedule header: every writer of the
    -- schedule's dependencies bumps the same row, so two halves of a cycle
    -- written at once serialise (READ COMMITTED: the second waits and its
    -- check below sees the first; REPEATABLE READ / SERIALIZABLE: the second
    -- fails with serialization_failure). The header guard admits an
    -- updated_at-only write.
    UPDATE public.rate_schedules s SET updated_at = now() WHERE s.id = NEW.rate_schedule_id;

    -- A dependency dependent -> base closes a cycle when base already
    -- reaches dependent through the schedule's other LIVE dependencies.
    -- (r2: a reachable set, not paths — UNION drops an item already
    -- reached, so the walk is linear in the schedule's dependencies.)
    WITH RECURSIVE reach(item_id) AS (
        SELECT NEW.base_rate_item_id
        UNION
        SELECT d.base_rate_item_id
          FROM reach r
          JOIN public.rate_item_dependencies d
            ON d.dependent_rate_item_id = r.item_id
           AND d.rate_schedule_id = NEW.rate_schedule_id
           AND d.retired_at IS NULL
           AND d.id <> NEW.id
    )
    SELECT EXISTS (SELECT 1 FROM reach WHERE item_id = NEW.dependent_rate_item_id) INTO v_cycle;
    IF v_cycle THEN
        RAISE EXCEPTION USING
            MESSAGE = format('rate_item_dependencies: rate item %s depending on %s closes a cycle in rate schedule %s — rider composition must be a DAG (CI-101, v5.4.2-19)',
                             NEW.dependent_rate_item_id, NEW.base_rate_item_id, NEW.rate_schedule_id),
            ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$fn$;
COMMENT ON FUNCTION public.enforce_rate_item_dependency() IS
    'v5.4.2-19 (CI-101), v5.4.2-21 (CI-014). BEFORE INSERT OR UPDATE on rate_item_dependencies. INSERT: born live; refuses a schedule or item of another tenant, and a dependency that closes a cycle among the schedule''s live dependencies (any length). UPDATE: only the retirement of a live dependency (reason required; retired_at and retired_by stamped by the database, the latter from app.user_id); every other column is write-once and a retirement is permanent. Both serialise on the schedule header (a row-version mutex: rate_schedules.updated_at), so concurrent halves of a cycle cannot both pass at any isolation level.';


-- ----------------------------------------------------------------------------
-- 4. Bill-line arithmetic at issue (A1-A6)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.invoice_line_arithmetic_gap(p_line public.invoice_line_items, p_valid_at date, p_recorded_at timestamp with time zone)
    RETURNS text
    LANGUAGE plpgsql
    STABLE
    SET search_path TO 'public', 'pg_temp'
    AS $fn$
DECLARE
    v_missing  text[] := '{}';
    v_per_unit boolean := p_line.charge_type = 'usage_charge';
    v_calc     text;
BEGIN
    IF p_line.charge_type = 'surcharge' THEN
        IF p_line.rate_item_id IS NULL THEN
            RETURN 'rate_item_id (a surcharge names its rate item)';
        END IF;
        SELECT v.calculation_type INTO v_calc FROM public.rate_item_as_of(p_line.rate_item_id, p_valid_at, p_recorded_at) v;
        -- r2 (all three reviewers, B1): no version visible at the coordinate
        -- (none effective then, or an item this caller cannot see) is not
        -- "fixed": a line that cannot be classified needs its figures.
        -- calculation_type is NOT NULL, so NULL means exactly no version.
        IF v_calc IS NULL THEN
            RETURN format('a classification: rate item %s has no version visible at (%s, %s)', p_line.rate_item_id, p_valid_at, p_recorded_at);
        END IF;
        v_per_unit := v_calc IN ('per_unit_usage', 'tiered_usage');
    END IF;
    IF v_per_unit THEN
        IF p_line.usage_quantity IS NULL THEN v_missing := v_missing || 'usage_quantity'::text; END IF;
        IF coalesce(p_line.usage_unit !~ '[[:alnum:]]', true) THEN v_missing := v_missing || 'usage_unit'::text; END IF;
        IF p_line.rate IS NULL THEN v_missing := v_missing || 'rate'::text; END IF;
        IF p_line.service_type = 'gas' THEN
            IF p_line.gas_meter_factor   IS NULL THEN v_missing := v_missing || 'gas_meter_factor'::text; END IF;
            IF p_line.gas_ccf_used       IS NULL THEN v_missing := v_missing || 'gas_ccf_used'::text; END IF;
            IF p_line.gas_therms_billed  IS NULL THEN v_missing := v_missing || 'gas_therms_billed'::text; END IF;
            -- The commodity rate is the usage line's; a rider's own rate is
            -- `rate` (r2, Fable S4).
            IF p_line.charge_type = 'usage_charge' AND p_line.gas_commodity_rate IS NULL THEN v_missing := v_missing || 'gas_commodity_rate'::text; END IF;
        END IF;
    ELSIF p_line.charge_type = 'base_charge' THEN
        IF p_line.rate IS NULL THEN v_missing := v_missing || 'rate'::text; END IF;
        IF num_nonnulls(p_line.coverage_start, p_line.coverage_end, p_line.days_covered, p_line.days_in_period, p_line.partial_period_policy_applied) NOT IN (0, 5) THEN
            v_missing := v_missing || 'coverage_start, coverage_end, days_covered, days_in_period and partial_period_policy_applied (all or none)'::text;
        END IF;
    END IF;
    RETURN CASE WHEN cardinality(v_missing) = 0 THEN NULL ELSE array_to_string(v_missing, ', ') END;
END;
$fn$;
COMMENT ON FUNCTION public.invoice_line_arithmetic_gap(public.invoice_line_items, date, timestamp with time zone) IS
    'v5.4.2-21 (CI-016). What a bill line lacks of the arithmetic it must carry at issue, or NULL. usage_charge: usage_quantity, usage_unit, rate (gas: also gas_meter_factor, gas_ccf_used, gas_therms_billed, gas_commodity_rate). base_charge: rate, and the five coverage columns all or none (none = the full period). surcharge: its rate_item_id and a version of it visible at (p_valid_at, p_recorded_at); when that version is per_unit_usage or tiered_usage, usage_quantity, usage_unit and rate (gas: also the meter factor, Ccf and therms; the commodity rate is the usage line''s). Every other kind: nothing. Presence only; the product is the core''s. tally_app executes it: the issuance check calls it with the caller''s rights, so RLS decides which rate items are visible.';
REVOKE ALL ON FUNCTION public.invoice_line_arithmetic_gap(public.invoice_line_items, date, timestamp with time zone) FROM PUBLIC, tally_core;

CREATE OR REPLACE FUNCTION public.enforce_invoice_line_arithmetic() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public', 'pg_temp'
    AS $fn$
DECLARE
    v_line public.invoice_line_items%ROWTYPE;
    v_gap  text;
    v_snap public.invoice_calculation_snapshots%ROWTYPE;
BEGIN
    -- Gated as its siblings: only the move into an issued status, and not a
    -- void (a discard of a draft or held bill).
    IF NOT public.is_invoice_issued(NEW.status) THEN
        RETURN NULL;
    END IF;
    IF TG_OP = 'UPDATE' AND public.is_invoice_issued(OLD.status) THEN
        RETURN NULL;
    END IF;
    IF TG_OP = 'UPDATE' AND NEW.status = 'void' THEN
        RETURN NULL;
    END IF;
    -- r2 (Codex B2), r3 (Fable r2 B1): the date is the bill's own, its
    -- snapshot's valid_at (validated and frozen since v5.4.2-10: the period
    -- end, or a correction's elected rate date); the knowledge is now. The
    -- snapshot's recorded_at is the caller's to choose inside a window, and
    -- an earlier instant would hide a classification retracted since — the
    -- surcharge sibling reads now() for the same reason. A retracted
    -- classification is retracted. No snapshot: enforce_invoice_has_snapshot
    -- refuses the issuance.
    SELECT * INTO v_snap FROM public.invoice_calculation_snapshots s WHERE s.invoice_id = NEW.id;
    IF NOT FOUND THEN
        RETURN NULL;
    END IF;
    -- The lines are locked, as the siblings lock them: a concurrent edit of
    -- an existing line waits for this transaction.
    PERFORM 1 FROM public.invoice_line_items l WHERE l.invoice_id = NEW.id FOR SHARE;
    FOR v_line IN SELECT l.* FROM public.invoice_line_items l WHERE l.invoice_id = NEW.id ORDER BY l.line_order, l.id LOOP
        v_gap := public.invoice_line_arithmetic_gap(v_line, v_snap.valid_at, now());
        IF v_gap IS NOT NULL THEN
            RAISE EXCEPTION USING
                MESSAGE = format('invoice %s cannot be issued: line %s (%s, %s) does not carry its arithmetic — missing %s (CI-016, v5.4.2-21)', NEW.invoice_number, v_line.line_order, v_line.charge_type, v_line.description, v_gap),
                ERRCODE = 'check_violation';
        END IF;
    END LOOP;
    RETURN NULL;
END;
$fn$;
COMMENT ON FUNCTION public.enforce_invoice_line_arithmetic() IS
    'v5.4.2-21 (CI-016). Deferred AFTER INSERT OR UPDATE on invoices: on the move into an issued status (not a void), every line must carry its arithmetic (invoice_line_arithmetic_gap at the bill''s calculation snapshot''s valid_at — the rate date the price was calculated for — under current knowledge, now()). Without a snapshot it defers to enforce_invoice_has_snapshot. Locks the lines FOR SHARE. A superuser''s load of a bill born issued is checked too.';
REVOKE ALL ON FUNCTION public.enforce_invoice_line_arithmetic() FROM PUBLIC, tally_app, tally_core;

DROP TRIGGER IF EXISTS enforce_invoice_line_arithmetic ON public.invoices;
CREATE CONSTRAINT TRIGGER enforce_invoice_line_arithmetic AFTER INSERT OR UPDATE ON public.invoices
    DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.enforce_invoice_line_arithmetic();
ALTER TABLE public.invoices ENABLE ALWAYS TRIGGER enforce_invoice_line_arithmetic;


-- ----------------------------------------------------------------------------
-- 5. Lineage (G1-G7)
-- ----------------------------------------------------------------------------
-- G1. A correction names the bill it replaces. That the bill is void and was
-- issued is refused at issue already (calculation_snapshot_coordinate_violation).
ALTER TABLE public.invoices
    ADD CONSTRAINT invoices_correction_names_replaced_check
        CHECK (invoice_type <> 'correction' OR replaces_invoice_id IS NOT NULL);

-- G2, G3. A void_reversal names the entry it reverses, of its own tenant,
-- with a reason.
ALTER TABLE public.account_ledger
    ADD CONSTRAINT account_ledger_void_reversal_lineage_check
        CHECK (transaction_type <> 'void_reversal'
               OR (reverses_ledger_entry_id IS NOT NULL AND coalesce(reversal_reason ~ '[[:alnum:]]', false)));
-- r2 (Opus S2): the void's reversal is one act under one name. An
-- adjustment filed against an invoice void would carry no link.
ALTER TABLE public.account_ledger
    ADD CONSTRAINT account_ledger_void_reversal_reference_check
        CHECK (coalesce(reference_type = 'invoice_void', false) = (transaction_type = 'void_reversal'));
-- r2 (Fable S3): an entry is reversed by a void at most once.
CREATE UNIQUE INDEX account_ledger_one_void_reversal_per_entry
    ON public.account_ledger (reverses_ledger_entry_id) WHERE transaction_type = 'void_reversal';
ALTER TABLE public.account_ledger DROP CONSTRAINT account_ledger_reverses_ledger_entry_id_fkey;
ALTER TABLE public.account_ledger
    ADD CONSTRAINT account_ledger_reverses_ledger_entry_fkey
        FOREIGN KEY (reverses_ledger_entry_id, tenant_id) REFERENCES public.account_ledger (id, tenant_id);

-- G4. A refund names exactly one source.
ALTER TABLE public.customer_credits
    ADD CONSTRAINT customer_credits_id_tenant_customer_key UNIQUE (id, tenant_id, customer_id);
ALTER TABLE public.payments
    ADD COLUMN refunds_customer_credit_id uuid;
COMMENT ON COLUMN public.payments.refunds_customer_credit_id IS
    'v5.4.2-21 (CI-017). The customer credit a refund pays out — the other source a refund may name, beside refunds_payment_id (an overpayment built from several payments is refunded from its credit). A refund names exactly one.';
ALTER TABLE public.payments
    ADD CONSTRAINT payments_refunds_customer_credit_fkey
        FOREIGN KEY (refunds_customer_credit_id, tenant_id, customer_id) REFERENCES public.customer_credits (id, tenant_id, customer_id);
ALTER TABLE public.payments DROP CONSTRAINT payments_refund_is_refund_check;
ALTER TABLE public.payments
    ADD CONSTRAINT payments_refund_is_refund_check
        CHECK ((refunds_payment_id IS NULL AND refunds_customer_credit_id IS NULL)
               OR (payment_method = 'refund' AND amount < 0)),
    ADD CONSTRAINT payments_refund_names_one_source_check
        CHECK (payment_method <> 'refund' OR num_nonnulls(refunds_payment_id, refunds_customer_credit_id) = 1);

CREATE OR REPLACE FUNCTION public.enforce_payment_immutable()
 RETURNS trigger
 LANGUAGE plpgsql
AS $fn$
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
        IF NEW.refunds_customer_credit_id  IS DISTINCT FROM OLD.refunds_customer_credit_id  THEN v_changed := v_changed || ARRAY['refunds_customer_credit_id']; END IF;  -- v5.4.2-21
        IF NEW.created_at                  IS DISTINCT FROM OLD.created_at                  THEN v_changed := v_changed || ARRAY['created_at']; END IF;
    END IF;

    IF cardinality(v_changed) > 0 THEN
        RAISE EXCEPTION USING
            MESSAGE = format('payment %s is posted (status %s) and its identity is immutable (CI-013): attempted change to %s; reverse it and post a new payment', OLD.payment_number, OLD.status, array_to_string(v_changed, ', ')),
            ERRCODE = 'restrict_violation';
    END IF;
    RETURN NEW;
END;
$fn$;
COMMENT ON FUNCTION public.enforce_payment_immutable() IS
    'CI-013 guard for payments (v5.4.2-01). Terminal statuses (nsf, reversed, refunded, voided) never transition; nothing returns to pending; once a payment leaves pending its identity is frozen — the lineage columns included (refunds_customer_credit_id since v5.4.2-21) — and reversed_at / nsf_date are write-once.';

-- G6 (-20 R8). A charge is never born carrying a void's pointer.
CREATE OR REPLACE FUNCTION public.enforce_adhoc_charge_born_unvoided() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public', 'pg_temp'
    AS $fn$
BEGIN
    IF NEW.voided_from_invoice_id IS NOT NULL
       AND NOT (SELECT r.rolsuper FROM pg_catalog.pg_roles r WHERE r.rolname = current_user) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('adhoc_charges: charge %s cannot be inserted with voided_from_invoice_id — only void_invoice() writes it, when it releases a billed charge (CI-017, v5.4.2-21)', NEW.id),
            ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$fn$;
COMMENT ON FUNCTION public.enforce_adhoc_charge_born_unvoided() IS
    'v5.4.2-21 (CI-017; -20 residual R8). BEFORE INSERT on adhoc_charges: voided_from_invoice_id is written only by void_invoice(), on an UPDATE; an insert carrying it is refused, except a superuser''s history load.';
REVOKE ALL ON FUNCTION public.enforce_adhoc_charge_born_unvoided() FROM PUBLIC, tally_app, tally_core;
DROP TRIGGER IF EXISTS a_enforce_adhoc_charge_born_unvoided ON public.adhoc_charges;
CREATE TRIGGER a_enforce_adhoc_charge_born_unvoided BEFORE INSERT ON public.adhoc_charges
    FOR EACH ROW EXECUTE FUNCTION public.enforce_adhoc_charge_born_unvoided();
ALTER TABLE public.adhoc_charges ENABLE ALWAYS TRIGGER a_enforce_adhoc_charge_born_unvoided;

-- G7. Every lineage column is indexed: a walk forward from an original is a
-- lookup, not a scan.
CREATE INDEX IF NOT EXISTS idx_invoices_replaces_invoice ON public.invoices (replaces_invoice_id) WHERE replaces_invoice_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_account_ledger_reverses ON public.account_ledger (reverses_ledger_entry_id) WHERE reverses_ledger_entry_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_payments_refunds_payment ON public.payments (refunds_payment_id) WHERE refunds_payment_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_payments_nsf_original ON public.payments (nsf_original_payment_id) WHERE nsf_original_payment_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_payments_refunds_credit ON public.payments (refunds_customer_credit_id) WHERE refunds_customer_credit_id IS NOT NULL;


-- ----------------------------------------------------------------------------
-- 6. The void: reverse the posted charge, or post nothing (V1-V3)
-- ----------------------------------------------------------------------------
-- CREATE OR REPLACE keeps the owner (tally_void) and the grants.
CREATE OR REPLACE FUNCTION public.void_invoice(p_invoice_id uuid, p_voided_by uuid DEFAULT NULL::uuid, p_void_reason_code text DEFAULT NULL::text, p_void_reason_notes text DEFAULT NULL::text, p_rebill_expected boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
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
    -- Step 2.5 (v5.4.2-21, CI-017; Ryan 2026-10-14): the charge this void
    -- reverses. A posted bill (first_issued_at, stamped by the database on
    -- the first move into an issued status) was charged to the account, and
    -- its reversal names that charge: if the charge entry is missing the void
    -- is refused, before anything is written. A bill never posted (voided
    -- straight from held) was never charged: the void writes no ledger entry.
    -- -------------------------------------------------------------------------
    IF v_invoice.first_issued_at IS NOT NULL THEN
        SELECT l.id INTO v_original_ledger_entry_id
          FROM public.account_ledger l
         WHERE l.tenant_id        = v_invoice.tenant_id
           AND l.customer_id      = v_invoice.customer_id   -- r2 (Opus S1)
           AND l.reference_type   = 'invoice'
           AND l.reference_id     = p_invoice_id
           AND l.transaction_type = 'charge'
         ORDER BY l.created_at, l.id
         LIMIT 1;
        IF NOT FOUND THEN
            RAISE EXCEPTION USING
                MESSAGE = format('invoice %s was posted but has no charge entry on account_ledger (reference_type = invoice, transaction_type = charge): its void must reverse that charge and name it (CI-017, v5.4.2-21) — post the missing charge first', v_invoice.invoice_number),
                ERRCODE = 'no_data_found';
        END IF;
    END IF;

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
    -- Step 4: Post void_reversal ledger entry
    -- -------------------------------------------------------------------------
    -- v5.4.2-21: a posted bill only (Step 2.5); a never-posted bill has no
    -- charge to reverse, and the reversal amount stays NULL.
    IF v_invoice.first_issued_at IS NOT NULL THEN
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
    END IF;

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
$fn$;
COMMENT ON FUNCTION public.void_invoice(uuid, uuid, text, text, boolean) IS
    'Atomically voids an invoice — the ONLY way to set invoices.status = ''void'' outside a superuser''s history load. Locks the invoice, releases its locked reads, disposes of its billed ad-hoc charges and logs the event. A posted bill (first_issued_at set) must have its charge entry on account_ledger, of the bill''s tenant and customer: the void posts the void_reversal naming it (reverses_ledger_entry_id, reversal_reason; CI-017), and is refused (P0002) before writing anything if the charge is missing. A bill never posted (voided from held) gets no ledger entry; its reversal_amount is NULL (v5.4.2-21, Ryan 2026-10-14). A superuser load that brings in a posted bill sets first_issued_at with it, or the bill voids as a discard. Since v5.4.2-20 it runs as tally_void, a role subject to RLS that no caller can become: the read, charge and invoice guards admit its writes because they run as tally_void, and only while it runs. An invoice the caller cannot see, or a caller with no tenant, gets "Invoice not found" (P0002). Returns the customer''s summed ledger balance as credit_balance.';


-- ----------------------------------------------------------------------------
-- 7. Identity (U1, U2)
-- ----------------------------------------------------------------------------
ALTER TABLE public.users
    ADD COLUMN cognito_sub text,
    ADD CONSTRAINT users_cognito_sub_key UNIQUE (cognito_sub),
    ADD CONSTRAINT users_cognito_sub_format_check CHECK (cognito_sub ~ '^[0-9A-Za-z_-]{1,128}$');
COMMENT ON COLUMN public.users.cognito_sub IS
    'v5.4.2-21 (R1, AC-43). The Cognito subject (the verified token''s sub) this user is. The application sets app.user_id to the user whose cognito_sub is the token''s sub, and nothing else. Unique; written by a supervisor''s session (r2); write-once once set, except a superuser repair; NULL for a service user, which has no Cognito identity.';

CREATE OR REPLACE FUNCTION public.enforce_user_cognito_sub_write_once() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public', 'pg_temp'
    AS $fn$
BEGIN
    IF OLD.cognito_sub IS NOT NULL AND NEW.cognito_sub IS DISTINCT FROM OLD.cognito_sub
       AND NOT (SELECT r.rolsuper FROM pg_catalog.pg_roles r WHERE r.rolname = current_user) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('users: user %s is bound to a Cognito identity, and the binding is write-once (R1, v5.4.2-21) — a new identity is a new user', OLD.id),
            ERRCODE = 'restrict_violation';
    END IF;
    RETURN NEW;
END;
$fn$;
COMMENT ON FUNCTION public.enforce_user_cognito_sub_write_once() IS
    'v5.4.2-21 (R1). BEFORE UPDATE OF cognito_sub on users: once set, never changed or cleared, except by a superuser repair.';
REVOKE ALL ON FUNCTION public.enforce_user_cognito_sub_write_once() FROM PUBLIC, tally_app, tally_core;
DROP TRIGGER IF EXISTS a_enforce_user_cognito_sub_write_once ON public.users;
CREATE TRIGGER a_enforce_user_cognito_sub_write_once BEFORE UPDATE OF cognito_sub ON public.users
    FOR EACH ROW EXECUTE FUNCTION public.enforce_user_cognito_sub_write_once();
ALTER TABLE public.users ENABLE ALWAYS TRIGGER a_enforce_user_cognito_sub_write_once;

-- r2 (Opus B2): who may bind an identity, or switch a user on or off. A
-- binding is write-once, but nothing guarded who set it: an operator could
-- bind its own second Cognito account to an unbound tenant_admin (or
-- reactivate a deactivated one), and session_is_supervisor() would then
-- answer true — the self-promotion enforce_tenant_admin_grant refuses
-- (v5.4.2-13). And U2 makes is_active a wall: an operator could switch its
-- supervisors off. For the application, binding any user and changing any
-- user's is_active take a supervisor; the owner (a superuser load or repair)
-- stands aside, as in enforce_tenant_admin_grant. Consequence for onboarding
-- (AC-43): a user's binding is written by a supervisor's session when the
-- user is provisioned (Cognito's admin create returns the sub), not by the
-- new user's own first login.
CREATE OR REPLACE FUNCTION public.enforce_user_binding_by_supervisor() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public', 'pg_temp'
    AS $fn$
BEGIN
    IF current_user <> 'tally_app' THEN
        RETURN NEW;
    END IF;
    -- r4 (Opus r3 B1, Fable r3 B1): a demotion switches an administrator off
    -- as surely as is_active does; taking a user out of tenant_admin or
    -- platform_admin is guarded as switching it off. (Granting a role is the
    -- -13 grant guards'.)
    IF NOT ((TG_OP = 'INSERT' AND NEW.cognito_sub IS NOT NULL)
            OR (TG_OP = 'UPDATE' AND (NEW.cognito_sub IS DISTINCT FROM OLD.cognito_sub OR NEW.is_active IS DISTINCT FROM OLD.is_active
                                      OR (OLD.role IN ('tenant_admin', 'platform_admin') AND NEW.role IS DISTINCT FROM OLD.role)))) THEN
        RETURN NEW;
    END IF;
    -- r3 (Opus r2 B1): a platform administrator is bound, revived or switched
    -- off only by a platform administrator — a tenant_admin who could bind a
    -- deactivated platform administrator of its tenant would become one, the
    -- grant enforce_platform_admin_grant refuses.
    IF NEW.role = 'platform_admin' OR (TG_OP = 'UPDATE' AND OLD.role = 'platform_admin') THEN
        IF NOT public.is_platform_admin() THEN
            RAISE EXCEPTION USING
                MESSAGE = format('user %s: only a platform administrator binds a platform administrator''s identity, switches one on or off, or demotes one (R1, v5.4.2-21)', NEW.id),
                ERRCODE = 'insufficient_privilege';
        END IF;
    ELSIF NOT public.session_is_supervisor() THEN
        RAISE EXCEPTION USING
            MESSAGE = format('user %s: only a supervisor (tenant_admin or platform administrator) binds a Cognito identity, switches a user on or off, or demotes a tenant_admin — a session that could bind or revive an administrator could promote itself (R1, v5.4.2-21)', NEW.id),
            ERRCODE = 'insufficient_privilege';
    END IF;
    RETURN NEW;
END;
$fn$;
COMMENT ON FUNCTION public.enforce_user_binding_by_supervisor() IS
    'v5.4.2-21 r2 (R1). BEFORE INSERT OR UPDATE OF cognito_sub, is_active, role on users: for tally_app, binding a Cognito identity (on insert or update), changing is_active either way, and taking a user out of tenant_admin or platform_admin (r4) require session_is_supervisor(), and is_platform_admin() when the user is (or was) a platform administrator (r3). Other roles (the owner''s load or repair) stand aside, as in enforce_tenant_admin_grant.';
REVOKE ALL ON FUNCTION public.enforce_user_binding_by_supervisor() FROM PUBLIC, tally_app, tally_core;
DROP TRIGGER IF EXISTS a_enforce_user_binding_by_supervisor ON public.users;
CREATE TRIGGER a_enforce_user_binding_by_supervisor BEFORE INSERT OR UPDATE OF cognito_sub, is_active, role ON public.users
    FOR EACH ROW EXECUTE FUNCTION public.enforce_user_binding_by_supervisor();
ALTER TABLE public.users ENABLE ALWAYS TRIGGER a_enforce_user_binding_by_supervisor;

-- U2. Only an active user has a tenant, or is a platform administrator.
CREATE OR REPLACE FUNCTION public.get_user_tenant_id() RETURNS uuid
    LANGUAGE sql
    STABLE
    SECURITY DEFINER
    SET search_path = ''
    AS $fn$
    SELECT tenant_id FROM public.users WHERE id = current_setting('app.user_id', true)::uuid AND is_active
$fn$;
CREATE OR REPLACE FUNCTION public.is_platform_admin() RETURNS boolean
    LANGUAGE sql
    STABLE
    SECURITY DEFINER
    SET search_path = ''
    AS $fn$
    SELECT EXISTS(SELECT 1 FROM public.users WHERE id = current_setting('app.user_id', true)::uuid AND role = 'platform_admin' AND is_active)
$fn$;
COMMENT ON FUNCTION public.get_user_tenant_id() IS
    'The calling user''s tenant, from app.user_id, for an ACTIVE user only (v5.4.2-21, R1: a deactivated user passes no RLS policy). SECURITY DEFINER by necessity — the tenant_isolation policy on public.users itself calls it, so invoker rights would recurse. Pinned to an empty search_path with public.users qualified (v5.4.2-11). Returns NULL when app.user_id is unset, names no user or names an inactive one; an app.user_id set to the EMPTY STRING raises invalid_text_representation from the ::uuid cast (fail-closed; AC-43: never set it empty).';
COMMENT ON FUNCTION public.is_platform_admin() IS
    'True when app.user_id names an ACTIVE platform administrator (v5.4.2-21, R1). SECURITY DEFINER, pinned to an empty search_path (v5.4.2-11).';


-- ----------------------------------------------------------------------------
-- 8. The -20 notes (N1-N3)
-- ----------------------------------------------------------------------------
-- N1. No psql variable: the database is the current one.
DO $$ BEGIN
    EXECUTE format('REVOKE TEMP ON DATABASE %I FROM PUBLIC', pg_catalog.current_database());
END $$;

-- N2, N3.
CREATE OR REPLACE FUNCTION public.assert_seal_role_invariants()
 RETURNS void
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $fn$
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
    -- (D-2026-08-20-27: a replication apply does not skip it). r3 (Opus S2):
    -- with the version tables' bitemporal guards, which freeze a version
    -- row's entity (the receipt guard reads NEW's entity on that basis).
    -- v5.4.2-21 (-20 note): these strings are PostgreSQL 16's rendering by
    -- pg_get_triggerdef. A major upgrade may render them differently: re-
    -- capture them from the upgraded catalog (after checking each trigger is
    -- unchanged) before trusting a failure here.
    c_triggers CONSTANT text[] := ARRAY['CREATE TRIGGER a0_enforce_reference_version_receipt BEFORE INSERT OR UPDATE ON public.rate_item_versions FOR EACH ROW EXECUTE FUNCTION enforce_reference_version_receipt(''rate_items'', ''rate_item_id'')',
        'CREATE TRIGGER a0_enforce_reference_version_receipt BEFORE INSERT OR UPDATE ON public.rate_schedule_versions FOR EACH ROW EXECUTE FUNCTION enforce_reference_version_receipt(''rate_schedules'', ''rate_schedule_id'')',
        'CREATE TRIGGER a0_enforce_reference_version_receipt BEFORE INSERT OR UPDATE ON public.wna_zone_versions FOR EACH ROW EXECUTE FUNCTION enforce_reference_version_receipt(''wna_zones'', ''wna_zone_id'')',
        'CREATE TRIGGER a_enforce_attach_to_live_invoice BEFORE INSERT OR UPDATE OF billed_on_invoice_id ON public.adhoc_charges FOR EACH ROW EXECUTE FUNCTION enforce_attach_to_live_invoice(''billed_on_invoice_id'')',
        'CREATE TRIGGER a_enforce_attach_to_live_invoice BEFORE INSERT OR UPDATE OF locked_by_invoice_id ON public.meter_readings FOR EACH ROW EXECUTE FUNCTION enforce_attach_to_live_invoice(''locked_by_invoice_id'')',
        'CREATE TRIGGER a_enforce_bitemporal_assertion BEFORE INSERT OR DELETE OR UPDATE ON public.rate_item_versions FOR EACH ROW EXECUTE FUNCTION enforce_bitemporal_assertion('''', ''rate_item_id'', ''rate_items'')',
        'CREATE TRIGGER a_enforce_bitemporal_assertion BEFORE INSERT OR DELETE OR UPDATE ON public.rate_schedule_versions FOR EACH ROW EXECUTE FUNCTION enforce_bitemporal_assertion('''', ''rate_schedule_id'', ''rate_schedules'')',
        'CREATE TRIGGER a_enforce_bitemporal_assertion BEFORE INSERT OR DELETE OR UPDATE ON public.wna_zone_versions FOR EACH ROW EXECUTE FUNCTION enforce_bitemporal_assertion('''', ''wna_zone_id'', ''wna_zones'')',
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

    -- r3 (Codex S1): PUBLIC, which every role inherits, holds no privilege on
    -- any relation in public (table, view, sequence, or a column of one), so
    -- the seal roles' privileges are exactly their own lists above. A
    -- world-readable lookup is granted to named roles, never to PUBLIC.
    SELECT string_agg(DISTINCT c.relname, ', ') INTO v_bad
      FROM pg_class c
     WHERE c.relnamespace = 'public'::regnamespace
       AND (EXISTS (SELECT 1 FROM aclexplode(c.relacl) a WHERE a.grantee = 0)
            OR EXISTS (SELECT 1 FROM pg_attribute t, aclexplode(t.attacl) a
                        WHERE t.attrelid = c.oid AND NOT t.attisdropped AND a.grantee = 0));
    IF v_bad IS NOT NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('PUBLIC holds a privilege on relation %s (or a column of it): every role, the seal roles included, would inherit it (v5.4.2-20)', v_bad),
            ERRCODE = 'invalid_grant_operation';
    END IF;

    -- r3 (Opus S1, Codex S2): the CHECK that keeps a billed charge on its bill.
    IF NOT EXISTS (SELECT 1 FROM pg_constraint k
                    WHERE k.conrelid = 'public.adhoc_charges'::regclass
                      AND k.conname = 'adhoc_charges_billed_names_its_bill'
                      AND k.contype = 'c' AND k.convalidated
                      AND pg_get_constraintdef(k.oid) = 'CHECK (((status = ''billed''::text) = (billed_on_invoice_id IS NOT NULL)))') THEN
        RAISE EXCEPTION USING
            MESSAGE = 'adhoc_charges_billed_names_its_bill is missing, changed or not validated (v5.4.2-20)',
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
$fn$;
COMMENT ON FUNCTION public.assert_seal_role_invariants() IS
    'v5.4.2-20 (r3), v5.4.2-21. Raises unless: tally_seal and tally_void exist, are NOLOGIN without SUPERUSER, BYPASSRLS, CREATEROLE, CREATEDB or REPLICATION, have no members and are members of nothing, hold and set no default privilege, can define no code, own exactly their pinned SECURITY DEFINER functions (by identity) and no relation, type or schema, and hold exactly their granted privileges, grant options included (seal_role_privileges); tally_core executes no definer but the two RLS helpers (by identity); tally_app, tally_core and PUBLIC hold no privilege on the receipts and no UPDATE on a header version; no public function names the old void setting (a lexical test); every guard of the two seals exists exactly as defined (PostgreSQL 16''s rendering) and ENABLE ALWAYS; PUBLIC holds no privilege on any relation in public; and adhoc_charges_billed_names_its_bill is present and validated. Run in the patch tail and in CI.';
REVOKE ALL ON FUNCTION public.assert_seal_role_invariants() FROM PUBLIC, tally_app, tally_core;


-- ----------------------------------------------------------------------------
-- 9. The retention invariant (D4)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.assert_no_hard_delete_invariants() RETURNS void
    LANGUAGE plpgsql
    STABLE
    SET search_path TO 'public', 'pg_temp'
    AS $fn$
DECLARE
    v_bad text;
    -- The sixteen of v5.4.2-21 (CI-014).
    c_kept CONSTANT text[] := ARRAY['ai_sessions', 'ai_suggestions', 'ai_tool_calls',
        'billing_cycles', 'read_routes', 'jurisdictions', 'communities', 'deposit_utility_categories',
        'bill_messages', 'auto_pay_settings', 'tenant_sequences',
        'read_cycle_meters', 'alerts', 'service_location_acquisitions',
        'rate_item_dependencies', 'pga_monitoring_settings'];
    -- What tally_app may still delete: the bill tables (their own CI-012
    -- guards), the import working data, housekeeping, and the two labels
    -- (guarded while in use).
    c_deletable CONSTANT text[] := ARRAY['invoices', 'invoice_line_items', 'invoice_events', 'invoice_calculation_snapshots',
        'invoice_line_item_bases', 'invoice_snapshot_references',
        'import_staging', 'import_column_mappings', 'import_mapping_templates', 'materialized_view_refresh_log',
        'custom_field_definitions', 'custom_location_types'];
BEGIN
    -- Both guards on each of the sixteen, exactly, ENABLE ALWAYS (PostgreSQL
    -- 16's rendering of pg_get_triggerdef).
    SELECT string_agg(t || ' ' || g, ', ' ORDER BY t, g) INTO v_bad
      FROM unnest(c_kept) t,
           unnest(ARRAY['no_hard_delete', 'no_truncate']) g
     WHERE NOT EXISTS (
            SELECT 1 FROM pg_catalog.pg_trigger x
             WHERE x.tgrelid = ('public.' || pg_catalog.quote_ident(t))::regclass
               AND x.tgname = g AND NOT x.tgisinternal AND x.tgenabled = 'A'
               AND pg_catalog.pg_get_triggerdef(x.oid) = CASE g
                    WHEN 'no_hard_delete' THEN format('CREATE TRIGGER no_hard_delete BEFORE DELETE ON public.%I FOR EACH ROW EXECUTE FUNCTION enforce_no_hard_delete()', t)
                    ELSE format('CREATE TRIGGER no_truncate BEFORE TRUNCATE ON public.%I FOR EACH STATEMENT EXECUTE FUNCTION enforce_no_hard_delete()', t) END);
    IF v_bad IS NOT NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('a retention guard is missing, changed or not ENABLE ALWAYS (CI-014, v5.4.2-21): %s', v_bad),
            ERRCODE = 'invalid_grant_operation';
    END IF;
    -- The label guards: in use, keys frozen, never emptied (r2: Codex S1,
    -- Fable S2).
    SELECT string_agg(t || ' ' || g, ', ' ORDER BY t, g) INTO v_bad
      FROM unnest(ARRAY['custom_field_definitions', 'custom_location_types']) t,
           unnest(ARRAY['a_enforce_custom_label_unused', 'a_enforce_custom_label_key_frozen', 'no_truncate']) g
     WHERE NOT EXISTS (
            SELECT 1 FROM pg_catalog.pg_trigger x
             WHERE x.tgrelid = ('public.' || t)::regclass AND x.tgname = g AND NOT x.tgisinternal AND x.tgenabled = 'A'
               AND pg_catalog.pg_get_triggerdef(x.oid) = CASE g
                    WHEN 'a_enforce_custom_label_unused' THEN format('CREATE TRIGGER a_enforce_custom_label_unused BEFORE DELETE ON public.%I FOR EACH ROW EXECUTE FUNCTION enforce_custom_label_unused()', t)
                    WHEN 'a_enforce_custom_label_key_frozen' THEN format('CREATE TRIGGER a_enforce_custom_label_key_frozen BEFORE UPDATE ON public.%I FOR EACH ROW EXECUTE FUNCTION enforce_custom_label_key_frozen()', t)
                    ELSE format('CREATE TRIGGER no_truncate BEFORE TRUNCATE ON public.%I FOR EACH STATEMENT EXECUTE FUNCTION enforce_no_hard_delete()', t) END);
    IF v_bad IS NOT NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('a label guard is missing, changed or not ENABLE ALWAYS: %s (CI-014, v5.4.2-21)', v_bad),
            ERRCODE = 'invalid_grant_operation';
    END IF;
    -- tally_app deletes nothing else, and truncates nothing.
    SELECT string_agg(c.relname, ', ' ORDER BY c.relname) INTO v_bad
      FROM pg_catalog.pg_class c
     WHERE c.relnamespace = 'public'::regnamespace AND c.relkind IN ('r', 'p')
       AND (   (has_table_privilege('tally_app', c.oid, 'DELETE') AND c.relname <> ALL (c_deletable))
            OR has_table_privilege('tally_app', c.oid, 'TRUNCATE'));
    IF v_bad IS NOT NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('tally_app may delete or truncate %s, which is not in the deletable set (CI-014, v5.4.2-21)', v_bad),
            ERRCODE = 'invalid_grant_operation';
    END IF;
END;
$fn$;
COMMENT ON FUNCTION public.assert_no_hard_delete_invariants() IS
    'v5.4.2-21 (CI-014). Raises unless: the sixteen retained tables each carry no_hard_delete and no_truncate exactly as defined and ENABLE ALWAYS; the two custom-label tables carry the in-use guard, the key freeze and no_truncate likewise; and tally_app holds DELETE on no public table outside the twelve deletable ones and TRUNCATE on none. It checks tally_app''s privileges only (tally_core is assert_core_role_invariants''s, PUBLIC assert_seal_role_invariants''s), and the triggers'' definitions and state, not the bodies of the functions they call. Run in the patch tail and in CI.';
REVOKE ALL ON FUNCTION public.assert_no_hard_delete_invariants() FROM PUBLIC, tally_app, tally_core;

-- ----------------------------------------------------------------------------
-- 10. The wave-1 guard invariant (r2, Fable S2)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.assert_wave1_guard_invariants() RETURNS void
    LANGUAGE plpgsql
    STABLE
    SET search_path TO 'public', 'pg_temp'
    AS $fn$
DECLARE
    v_bad text;
    -- PostgreSQL 16's rendering by pg_get_triggerdef: re-capture on a major
    -- upgrade, after checking each trigger is unchanged.
    c_triggers CONSTANT text[] := ARRAY[
        'CREATE CONSTRAINT TRIGGER enforce_invoice_line_arithmetic AFTER INSERT OR UPDATE ON public.invoices DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION enforce_invoice_line_arithmetic()',
        'CREATE TRIGGER a_enforce_adhoc_charge_born_unvoided BEFORE INSERT ON public.adhoc_charges FOR EACH ROW EXECUTE FUNCTION enforce_adhoc_charge_born_unvoided()',
        'CREATE TRIGGER a_enforce_user_cognito_sub_write_once BEFORE UPDATE OF cognito_sub ON public.users FOR EACH ROW EXECUTE FUNCTION enforce_user_cognito_sub_write_once()',
        'CREATE TRIGGER a_enforce_user_binding_by_supervisor BEFORE INSERT OR UPDATE OF cognito_sub, is_active, role ON public.users FOR EACH ROW EXECUTE FUNCTION enforce_user_binding_by_supervisor()',
        'CREATE TRIGGER a_enforce_rate_item_dependency BEFORE INSERT OR UPDATE ON public.rate_item_dependencies FOR EACH ROW EXECUTE FUNCTION enforce_rate_item_dependency()'];
BEGIN
    SELECT string_agg(d, E'\n  ' ORDER BY d) INTO v_bad
      FROM unnest(c_triggers) d
     WHERE NOT EXISTS (SELECT 1 FROM pg_catalog.pg_trigger g
                        WHERE NOT g.tgisinternal AND g.tgenabled = 'A'
                          AND pg_catalog.pg_get_triggerdef(g.oid) = d);
    IF v_bad IS NOT NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format(E'a wave-1 guard is missing, changed, or not ENABLE ALWAYS (v5.4.2-21):\n  %s', v_bad),
            ERRCODE = 'invalid_grant_operation';
    END IF;
END;
$fn$;
COMMENT ON FUNCTION public.assert_wave1_guard_invariants() IS
    'v5.4.2-21 r2. Raises unless the guards of v5.4.2-21 outside retention — the bill-line arithmetic check, the born-unvoided charge guard, the Cognito write-once and supervisor guards, and the rate-dependency guard (with its retirement) — exist exactly as defined (PostgreSQL 16''s rendering) and ENABLE ALWAYS. Checks the triggers, not the bodies of their functions. Run in the patch tail and in CI.';
REVOKE ALL ON FUNCTION public.assert_wave1_guard_invariants() FROM PUBLIC, tally_app, tally_core;

DO $$ BEGIN
    PERFORM public.assert_wave1_guard_invariants();
    PERFORM public.assert_no_hard_delete_invariants();
    PERFORM public.assert_seal_role_invariants();
    PERFORM public.assert_core_role_invariants();
    PERFORM public.assert_tenant_isolation_invariants();
END $$;

-- ============================================================================
-- END PATCH v5.4.2-21
-- ============================================================================

COMMIT;
\endif
