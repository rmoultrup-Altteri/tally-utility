-- ============================================================================
-- PATCH v5.4.2-12 — the meter test history: every test a meter has had, what
--                    it found, and which one governs a backbilling window
--                    (CI-091 / CI-092; Kyle R-31, R-34…R-36)
-- ============================================================================
-- Authority:   Kyle's R-31 (2026-09-02 A-2 record: an append-only test history
--              before the first gas tenant goes live), and R-34…R-36 with
--              findings F-2…F-5 (GBM application/kyle-decisions-2026-09-22-
--              a2-straddle-and-meter-test-anchor.md), which settle the three
--              questions the drafting brief left open and endorse its shape:
--              D-1 two tables, D-3 outcome computed by the database, D-4
--              customer and location required on a customer-requested test,
--              D-5 accept a late-entered test and flag it, D-6 a tenant-bound
--              key on users. Erratum E-1 (2026-09-23 record): the customer-
--              requested test and the 2.0% definition are §7.45(7)(B)(iv)(I)
--              and (II), not (7)(A)(iv). Drafting spec: GBM application/
--              ci091-meter-test-history-implementation-brief-2026-09-22.md.
--
--              Ryan, 2026-09-23: the test_kind domain is the brief's proposed
--              list — periodic, customer_requested, complaint, post_repair,
--              acceptance, other (D-2). Narrow first: widening a CHECK is one
--              line, narrowing means judging every row written under it.
--
--              Build order (R-34): this patch lands BEFORE A-2, which is
--              renumbered v5.4.2-13 and reads its governing test date from
--              here — meters.last_test_date is removed from that path, not
--              kept as a fallback.
--
-- The rule, in one sentence: §7.45(7)(B)(v)(I) lets a utility correct a
-- defective meter's readings back to "the shorter of the last six months or
-- the last test of the meter" — and until now the schema kept only ONE test
-- date per meter, overwritten by each new test, so the test that DISCOVERS an
-- error erased the one that bounds the correction.
--
-- ----------------------------------------------------------------------------
-- The arithmetic this history exists to serve (Kyle, 2026-09-22 record §1)
-- ----------------------------------------------------------------------------
--
--     window_start = MAX(anchor_date − 6 months, governing_test_date)
--
--   The last-test prong can only move the window start LATER. It is the
--   protective prong, so its absence defaults every correction to the longest
--   span — which is why A-2 cannot ship on a six-month-only bound, and why
--   this patch comes first. A-2 computes the MAX; this patch supplies the
--   governing test (meter_governing_test(), section 11) and the facts A-2's
--   gate needs about how far that test can be trusted.
--
--   Consequence used by R-36: every migrated test date is at or before the
--   tenant's cutover C (section 3 enforces it). For a discovery later than
--   C + 6 months, anchor − 6 months > C ≥ every migrated date, so a migrated
--   date can never set the window. Migrated provenance is a bounded,
--   transitional exposure — and the supervisor gate it needs lapses on its own.
--
-- ----------------------------------------------------------------------------
-- The two shapes this patch exists to avoid
-- ----------------------------------------------------------------------------
--
--   A STORED RESULT THAT CAN DISAGREE WITH ITS OWN EVIDENCE. The A-2 review
--   found invoices.amount_due and the line items were two versions of the
--   same money with nothing tying them together. A test outcome typed in by
--   the caller beside load results that say otherwise would be that defect
--   again, exactly where A-2 will rest a statutory window. So the caller
--   submits RAW READINGS (the standard meter's volume and the tested meter's
--   volume at each load point); the database computes each load's error from
--   them with one function, and the outcome from those errors against a
--   threshold held in data. Nothing that decides a result is caller-asserted.
--
--   A POINTER THAT CAN BE WRITTEN AROUND. meters.last_test_date and
--   last_test_result stay, as a convenience pointer maintained by trigger
--   from the history — and direct writes to them are refused, with the same
--   trigger-depth fence the read-validation gate already uses for
--   meters.consecutive_estimate_count (tu.sql, enforce_meter_estimate_counter).
--   The fence is sound only because tally_app can define no code (TEMP and
--   CREATE revoked, v5.4.2-06 / -11).
--
-- Verified on the v5.4.2-11 build before drafting, not assumed:
--   meters test columns            tu.sql:3691-3694, result CHECK 3718; NOTHING
--                                  in tu.sql reads or writes them (Kyle's
--                                  2026-09-22 grep agrees for the snapshot)
--   meters.location_id             NOT NULL (tu.sql:3667)
--   service_locations.state        text NOT NULL (tu.sql:4450)
--   service_orders                 order_type meter_test /
--                                  meter_test_failed_replace require meter_id
--                                  (CHECK service_orders_check1)
--   UNIQUE (id, tenant_id)         on meters, customers, service_orders;
--                                  NOT on service_locations or users
--   users.tenant_id                NOT NULL (tu.sql:4872)
--   program_types                  the precedent for platform reference data:
--                                  no tenant_id, no RLS, tally_app SELECT only
--   btree_gist                     installed (EXCLUDE on the threshold table)
--
-- ----------------------------------------------------------------------------
-- What lands
-- ----------------------------------------------------------------------------
--
--   1. COMPOSITE-KEY GROUNDWORK. UNIQUE (id, tenant_id) on service_locations
--      and on users (D-6), so every link this patch adds is tenant-composite
--      from day one rather than a 230th tenant-blind one.
--
--   2. THE PRECONDITION. Any meter already carrying last_test_date or
--      last_test_result with no history behind it refuses the patch: those
--      values have no provenance, and inventing a history row for them would
--      manufacture evidence. Load them as migrated_date_only rows first.
--
--   3. THE CUTOVER DATE (R-36; the per-tenant home Kyle's 2026-09-23 record
--      asks for). tenants.cutover_date, set by the platform, never the tenant.
--      Every migrated test is dated on or before it and every recorded test
--      on or after it; it may move only within those bounds, so R-36's
--      arithmetic holds whatever value it takes. Logged in
--      tenant_configuration_history.
--
--   4. THE THRESHOLD (F-3). meter_accuracy_thresholds, platform-fixed and
--      date-effective, keyed by state and service type: 2.0% is the Railroad
--      Commission's gas figure and other services do not share it. Seeded
--      with Texas gas only. tally_app reads it and cannot write it — a tenant
--      able to widen its own threshold could declare a failing meter accurate
--      and dodge the mandatory refund at (7)(B)(iv)(II).
--
--   5. THE HISTORY. meter_tests (one row per test, append-only) and
--      meter_test_load_results (one row per load point, written only by the
--      database from the test row's submitted readings, append-only). The
--      outcome and found_defective are derived, never supplied.
--      record_basis — recorded / migrated_full / migrated_date_only — sets
--      which fields are required (F-2: the (7)(B)(ii) field list attaches to
--      a customer-requested test, and a date-only record is exactly what the
--      (7)(B)(i) equipment record requires, so it is not deficient).
--
--   6. CORRECTIONS WITHOUT EDITS. A mistaken row is never updated; a
--      correcting row names it in supersedes_test_id with a reason, once —
--      on the same date, with a record at least as strong, and with readings
--      if the original had them.
--
--   7. THE POINTER. meters.last_test_date / last_test_result follow the
--      latest non-superseded test_date — not the last row inserted, so a late
--      entry with an earlier date never moves them backwards. Direct writes
--      refused. next_test_due_date and test_interval_months stay writable:
--      they are scheduling, and R-31 excludes scheduling.
--
--   8. THE ABSENCE FLAG (R-35 refinements 2 and 4). meter_test_absence_
--      declarations, append-only: attested_none (the tenant states no prior
--      test exists) or unknown (migration could not tell). They compute
--      identically; they differ for the gap report and the R-36 gate.
--      meters.test_history_absence is the pointer.
--
--   9. THE GOVERNING TEST (R-34). meter_governing_test(meter, anchor_date):
--      the most recent non-superseded test on the SAME meter dated strictly
--      before the anchor, WHATEVER ITS OUTCOME and whatever its test_kind.
--      Where there is none it returns no test and says why — never a date
--      inferred from install_date, test_interval_months, or
--      next_test_due_date − test_interval_months (R-31, R-35 refinement 3).
--      It also computes the R-36 gate flag. A-2 enforces the gate; this
--      patch supplies the fact.
--
--  10. THE GAP REPORT (R-35 refinement 1). meter_test_history_gaps, a
--      standing invoker-rights view of every meter with no test history, and
--      what its tenant has declared about that.
--
--  11. THE AC-32 TAIL.
--
-- ----------------------------------------------------------------------------
-- What is deliberately NOT here
-- ----------------------------------------------------------------------------
--
--   ENFORCEMENT OF THE R-36 GATE, the late-entry flag on evidence already
--   written (D-5), and the refusal to supersede a test an evidence row cites
--   (brief §3.6) — all three act on A-2's evidence rows, which do not exist
--   until v5.4.2-13. This patch records the facts they need
--   (entered_out_of_order; supervisor_gate) so A-2 does not have to infer them.
--   The fee rule — free test if none in four years, $15 cap, refund when more
--   than 2.0% off (§7.45(7)(B)(iv)). The history makes it answerable;
--   charging it is adhoc-charge work.
--   Test scheduling and due-date alerting (R-31 excludes them).
--   Test disputes (meter_test_disputes is a named gap in CI-091).
--   The migration loader — the tables accept migrated rows; the tool that
--   produces them is onboarding work.
--   Kyle's 2026-09-23 side finding (meters carries both num_dials and
--   dial_count) — unrelated; for Ryan.
--
-- ----------------------------------------------------------------------------
-- Review round 1 (Fable + Opus, frozen 75e33211; Codex stalled and was
-- cancelled), folded in this revision
-- ----------------------------------------------------------------------------
--
--   Both reviewers, independently:
--   * tally_app could move its own tenants.cutover_date — ending its own
--     R-36 gate, or moving go-live past a test it then filed as "migrated"
--     with an asserted result superseding a derived failure. Now platform-set.
--   * Supersession had no limits: a derived failure was replaced by a bare
--     inconclusive_reason or a weaker record, and a re-dated correction
--     lengthened a backbilling window. Now same date, no weaker basis,
--     readings for readings.
--   * The gate lapsed at cutover + 6 months, which at month ends is not the
--     inverse of A-2's anchor − 6 months (cutover 08-31: 48 cutover dates in
--     2024–2030 left a migrated date setting the window with the gate off).
--     Now stated in A-2's own arithmetic.
--   * The meter lock was FOR UPDATE, blocking every insert that merely
--     references the meter. Now FOR NO KEY UPDATE.
--   * The cutover trigger alone was not ENABLE ALWAYS.
--   One reviewer each:
--   * A "recorded" row could be back-dated before go-live and escape the gate
--     a migrated row of the same date carries (Opus). Recorded rows now sit
--     on or after cutover.
--   * Equal-and-opposite deviations beyond the threshold were filed as
--     inconclusive and the pointer said "conditional" (Opus). found_defective
--     now carries the failure separately from the direction.
--   * FOR SHARE on the tenant row deadlocked against a session that touched
--     a meter and then its tenant (Fable, reproduced). Now FOR KEY SHARE, with
--     the cutover change upgrading to FOR UPDATE.
--   * Trailing zeros beyond four decimals gave the stored max error a
--     different scale from the load rows' (Opus). Derivation now casts to the
--     stored type.
--   * cutover_date changes left no configuration-history row; load notes
--     were not type-checked; the precondition's hint and the non-transactional
--     psql -f apply were undocumented (Fable).
--
-- Review round 2 (Fable + Opus, frozen fd2418e2): all ten round-1 fixes
-- confirmed against their repros; siblings found and folded here:
--   * Both: a tenant session could make itself platform_admin (users.role
--     was unguarded) and so move cutover anyway. Section 1b.
--   * Opus: a migrated_full row with no readings switched the R-36 gate off
--     by its label alone. migrated_full now requires readings.
--   * Fable: a parallel date-only row, filed beside a derived failure on the
--     same date without superseding it, took over the pointer and the
--     governing test by insertion order. Ties now go to the stronger record.
--   * Opus: a cutover change under REPEATABLE READ / SERIALIZABLE crossed the
--     migrated/recorded boundary (three interleavings). Refused outside READ
--     COMMITTED.
--   * Opus: a date-only failure could be superseded by a bare
--     inconclusive_reason. A defective test's correction must carry readings.
--   * Lock-order note for cutover changes; the configuration recorder made
--     ENABLE ALWAYS; a stale lock comment (both).
--
-- Review round 3 (Fable + Opus, frozen ce8fcbe3): all six round-2 fixes
-- confirmed; siblings folded here:
--   * Both: a same-date row that supersedes nothing still displaced a
--     failure within one basis, or by being a stronger basis without
--     readings. Refused at insert; the readers' ranking extended to match.
--   * Opus: swapping users.id with the tenant's platform_admin row made the
--     session an administrator without touching role. Ids are immutable for
--     tally_app.
--   * Both (LOW): the isolation refusal blocked a tenant INSERT carrying its
--     cutover. Now UPDATE only.
--
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 1. Composite-key groundwork (D-6; brief §5)
-- ----------------------------------------------------------------------------
-- Both columns are already primary keys, so neither UNIQUE can be violated by
-- existing data. Two of the 229 links in GBM tenant-blind-foreign-keys-
-- 2026-09-22.md become repairable by these keys; this patch repairs none of
-- the existing links, only refuses to add new blind ones.

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                    WHERE conname = 'service_locations_id_tenant_id_key'
                      AND conrelid = 'public.service_locations'::regclass) THEN
        ALTER TABLE public.service_locations
            ADD CONSTRAINT service_locations_id_tenant_id_key UNIQUE (id, tenant_id);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                    WHERE conname = 'users_id_tenant_id_key'
                      AND conrelid = 'public.users'::regclass) THEN
        ALTER TABLE public.users
            ADD CONSTRAINT users_id_tenant_id_key UNIQUE (id, tenant_id);
    END IF;
END;
$$;


-- ----------------------------------------------------------------------------
-- 1b. Only a platform administrator makes a platform administrator
--     (review round 2, both reviewers)
-- ----------------------------------------------------------------------------
-- Section 3 makes tenants.cutover_date platform-set, and "platform" means
-- is_platform_admin(): users.role = 'platform_admin' for the session's user.
-- Nothing guarded users.role, and tally_app holds INSERT and UPDATE on its
-- own tenant's users — so a tenant session could promote itself (or insert a
-- new admin user) and then move its own cutover, with a history row that
-- looked legitimate. Pre-existing and schema-wide (every is_platform_admin()
-- gate shared it; Kyle's coda item A2, role-based access, is still open), but
-- this patch is the first to rest a statutory-window fact on it.
--
-- The narrowest guard that closes it: for tally_app, a row may BECOME
-- platform_admin only when the session is already a platform administrator.
-- Keeping or giving up the role is unaffected, and the owner (onboarding,
-- bootstrap of the first administrator) is not tally_app. This is not the
-- role model coda A2 asks for; it is the one invariant this patch needs.

CREATE OR REPLACE FUNCTION public.enforce_platform_admin_grant() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
BEGIN
    IF current_user <> 'tally_app' THEN
        RETURN NEW;
    END IF;
    -- is_platform_admin() looks the session up BY users.id, so re-keying a
    -- row is a role change by another name: swap ids with the tenant's own
    -- platform_admin row and the session is an administrator without the
    -- role column moving (review round 3, Opus). A user's id never changes.
    IF TG_OP = 'UPDATE' AND NEW.id IS DISTINCT FROM OLD.id THEN
        RAISE EXCEPTION USING
            MESSAGE = format('user %s: a user''s id is immutable — platform administration is looked up by id, so re-keying a row would transfer the role', OLD.id),
            ERRCODE = 'insufficient_privilege';
    END IF;
    IF NEW.role = 'platform_admin'
       AND (TG_OP = 'INSERT' OR OLD.role IS DISTINCT FROM 'platform_admin')
       AND NOT public.is_platform_admin() THEN
        RAISE EXCEPTION USING
            MESSAGE = format('user %s: only a platform administrator may grant the platform_admin role — a tenant session that could promote itself would hold every platform-only control, including tenants.cutover_date', NEW.id),
            ERRCODE = 'insufficient_privilege';
    END IF;
    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.enforce_platform_admin_grant() IS
    'v5.4.2-12 (review rounds 2 and 3). For tally_app, a users row may take the platform_admin role only when the session is already a platform administrator, and no users.id may change (the role is looked up by id, so a re-key would transfer it). Keeping or dropping the role is unaffected; the owner is unaffected. A BEFORE INSERT fires before ON CONFLICT resolution, so re-asserting an existing admin with INSERT … ON CONFLICT DO NOTHING is refused too — over-strict and harmless. The one role invariant the platform-only cutover_date rests on — not the role model Kyle''s coda item A2 asks for.';

DROP TRIGGER IF EXISTS a_enforce_platform_admin_grant ON public.users;
CREATE TRIGGER a_enforce_platform_admin_grant
    BEFORE INSERT OR UPDATE OF role, id ON public.users
    FOR EACH ROW EXECUTE FUNCTION public.enforce_platform_admin_grant();
ALTER TABLE public.users ENABLE ALWAYS TRIGGER a_enforce_platform_admin_grant;


-- ----------------------------------------------------------------------------
-- 2. The precondition — no pointer without a history behind it
-- ----------------------------------------------------------------------------
-- After this patch, meters.last_test_date and last_test_result mean "what the
-- history says". A value already sitting in them was written by whoever wrote
-- the meter row, with no record of who tested or what was found. Refuse
-- rather than either discard it (data loss) or turn it into a history row
-- (manufactured provenance). Counted against meters with NO history, so a
-- second apply over a populated build passes.

DO $$
DECLARE v_bad bigint;
BEGIN
    IF to_regclass('public.meter_tests') IS NULL THEN
        SELECT count(*) INTO v_bad FROM public.meters m
         WHERE m.last_test_date IS NOT NULL OR m.last_test_result IS NOT NULL;
    ELSE
        EXECUTE 'SELECT count(*) FROM public.meters m
                  WHERE (m.last_test_date IS NOT NULL OR m.last_test_result IS NOT NULL)
                    AND NOT EXISTS (SELECT 1 FROM public.meter_tests t WHERE t.meter_id = m.id)'
           INTO v_bad;
    END IF;
    IF v_bad > 0 THEN
        RAISE EXCEPTION 'v5.4.2-12: % meter(s) carry last_test_date / last_test_result with no test history behind them', v_bad
            USING ERRCODE = 'integrity_constraint_violation',
                  HINT = 'Record each as a meter_tests row (record_basis = migrated_date_only, with tenants.cutover_date set first) or clear the columns, then re-apply. A meter carrying only last_test_result = not_tested is a declared absence: clear it and record a meter_test_absence_declarations row after applying. The patch will not invent a history for them. NOTE: psql -f is not one transaction — section 1''s two UNIQUE keys will already have landed; they are harmless and idempotent.';
    END IF;
END;
$$;


-- ----------------------------------------------------------------------------
-- 3. The cutover date (R-36; Kyle 2026-09-23 "a per-tenant cutover date is
--    required")
-- ----------------------------------------------------------------------------
-- The go-live boundary between migrated and recorded history, and the
-- invariant R-36 rests on:
--
--     every migrated test_date  <=  cutover_date  <=  every recorded test_date
--
-- The left half is what lets the transitional gate lapse (Kyle §1: after
-- cutover + 6 months a migrated date can no longer set a window). The right
-- half closes the mirror (review round 1): without it a "recorded" row could
-- be back-dated before go-live and escape the gate a migrated row of the same
-- date carries. cutover_date may move — a go-live slips — but only within
-- those two bounds, and never back to NULL once history exists.
--
-- PLATFORM-SET (review round 1, both reviewers). tally_app holds UPDATE on
-- its own tenants row, and a tenant able to move its own cutover could end
-- its own gate, or move go-live past a test it wanted to file as "migrated"
-- with an asserted result. That is the threshold table's reasoning applied to
-- the gate, so it gets the threshold table's answer: only a platform
-- administrator (or the owner, at onboarding) sets it. Changes are recorded
-- in tenant_configuration_history like every other tenant policy value.
--
-- Concurrency: every test insert takes FOR KEY SHARE on its tenant row
-- before reading cutover_date (section 8) — no stronger than the foreign key
-- already takes, so ordinary tenant updates are not blocked (review round 1:
-- FOR SHARE deadlocked against a session that touched a meter and then its
-- tenant). A cutover change upgrades its own row to FOR UPDATE, which does
-- conflict with KEY SHARE: whichever of the two commits second sees the other.
--
-- Two conditions on a cutover change (review round 2):
--   * A CHANGE must run under READ COMMITTED. Test inserts only KEY-SHARE the
--     tenant row and never modify it, so a REPEATABLE READ or SERIALIZABLE
--     change whose snapshot predates a committed insert gets no serialisation
--     error and its bounds check cannot see that row — the invariant broke in
--     three measured interleavings. Refused rather than documented. A tenant
--     INSERT carrying its cutover is exempt (no test can reference a tenant
--     not yet committed), so onboarding in one SERIALIZABLE transaction sets
--     cutover on the INSERT (review round 3). A default_transaction_isolation
--     other than read committed on tally_app would refuse every app-side
--     change.
--   * It should be the FIRST row lock its transaction takes. A session that
--     already holds a meter row (or has recorded a test and holds the tenant
--     KEY SHARE) and then changes cutover can deadlock with a concurrent test
--     insert. PostgreSQL detects it, the cutover change is the victim, and
--     the invariant holds — but the change must be retried. Onboarding tooling
--     changes cutover in its own transaction.

ALTER TABLE public.tenants ADD COLUMN IF NOT EXISTS cutover_date date;

COMMENT ON COLUMN public.tenants.cutover_date IS
    'v5.4.2-12 (R-36). The date this utility went live on Tally — the boundary between migrated and recorded meter test history: every migrated test is dated on or before it and every recorded test on or after it. Set by the platform (a platform administrator, or the owner at onboarding), never by the tenant: moving it would move R-36''s gate. May change only within those bounds, and not back to NULL once history exists. R-36''s supervisor gate on weakly-evidenced adverse corrections runs for six months from here and then lapses, because beyond that a migrated date can no longer affect a backbilling window. NULL = not yet cut over: no test may be recorded yet, and the gate applies. Changes are logged in tenant_configuration_history. Also the home Kyle''s R-37 record asks for.';

CREATE OR REPLACE FUNCTION public.enforce_tenant_cutover_date() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_latest_migrated   date;
    v_earliest_recorded date;
BEGIN
    IF TG_OP = 'UPDATE' AND NEW.cutover_date IS NOT DISTINCT FROM OLD.cutover_date THEN
        RETURN NEW;
    END IF;
    IF TG_OP = 'INSERT' AND NEW.cutover_date IS NULL THEN
        RETURN NEW;
    END IF;
    IF current_user = 'tally_app' AND NOT public.is_platform_admin() THEN
        RAISE EXCEPTION USING
            MESSAGE = format('tenant %s: cutover_date is set by the platform, not the tenant — it bounds migrated against recorded meter test history and decides when R-36''s supervisor gate lapses', NEW.id),
            ERRCODE = 'insufficient_privilege';
    END IF;
    IF TG_OP = 'UPDATE' AND current_setting('transaction_isolation') <> 'read committed' THEN
        RAISE EXCEPTION USING
            MESSAGE = format('tenant %s: cutover_date may be changed only under READ COMMITTED (this transaction is %s) — under a snapshot isolation level the bounds check cannot see a test committed after the snapshot, and the migrated/recorded boundary could be crossed', NEW.id, current_setting('transaction_isolation')),
            ERRCODE = 'invalid_transaction_state';
    END IF;
    IF to_regclass('public.meter_tests') IS NULL THEN
        RETURN NEW;
    END IF;
    IF TG_OP = 'UPDATE' THEN
        -- Upgrade to FOR UPDATE: conflicts with the FOR KEY SHARE every test
        -- insert takes, so a concurrent insert and this change serialise.
        PERFORM 1 FROM public.tenants t WHERE t.id = NEW.id FOR UPDATE;
    END IF;
    SELECT max(t.test_date) FILTER (WHERE t.record_basis IN ('migrated_full', 'migrated_date_only')),
           min(t.test_date) FILTER (WHERE t.record_basis = 'recorded')
      INTO v_latest_migrated, v_earliest_recorded
      FROM public.meter_tests t
     WHERE t.tenant_id = NEW.id;
    IF v_latest_migrated IS NOT NULL AND (NEW.cutover_date IS NULL OR NEW.cutover_date < v_latest_migrated) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('tenant %s: cutover_date %s would fall before a migrated meter test dated %s — every migrated test must stay on or before cutover, or R-36''s six-month gate could lapse while a migrated date still sets a backbilling window', NEW.id, coalesce(NEW.cutover_date::text, 'NULL'), v_latest_migrated),
            ERRCODE = 'check_violation';
    END IF;
    IF v_earliest_recorded IS NOT NULL AND (NEW.cutover_date IS NULL OR NEW.cutover_date > v_earliest_recorded) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('tenant %s: cutover_date %s would fall after a recorded meter test dated %s — every recorded test must stay on or after cutover, or it would be pre-go-live history escaping the migrated-provenance gate', NEW.id, coalesce(NEW.cutover_date::text, 'NULL'), v_earliest_recorded),
            ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.enforce_tenant_cutover_date() IS
    'v5.4.2-12 (R-36). tenants.cutover_date is platform-set (tally_app may change it only as a platform administrator) and must satisfy max(migrated test_date) <= cutover_date <= min(recorded test_date), never NULL once history exists. Refused outside READ COMMITTED. Self-locks the tenant row FOR UPDATE on a change so it serialises with in-flight test inserts (which hold FOR KEY SHARE); take it as the transaction''s first row lock, or be ready to retry on deadlock.';

DROP TRIGGER IF EXISTS a_enforce_tenant_cutover_date ON public.tenants;
CREATE TRIGGER a_enforce_tenant_cutover_date
    BEFORE INSERT OR UPDATE OF cutover_date ON public.tenants
    FOR EACH ROW EXECUTE FUNCTION public.enforce_tenant_cutover_date();
ALTER TABLE public.tenants ENABLE ALWAYS TRIGGER a_enforce_tenant_cutover_date;

-- The cutover date joins the tenant policy values tenant_configuration_history
-- records (v5.4.1-02). Re-issued verbatim but for the one added key, so a
-- change to cutover_date leaves the same who/when row as any other policy.
-- Its known-key CHECK is widened by the same one value first.
ALTER TABLE public.tenant_configuration_history DROP CONSTRAINT IF EXISTS tenant_configuration_history_key_known_check;
ALTER TABLE public.tenant_configuration_history ADD CONSTRAINT tenant_configuration_history_key_known_check
    CHECK (((config_key ~~ 'settings.%'::text) OR (config_key = ANY (ARRAY['default_partial_period_policy'::text, 'payment_allocation_strategy'::text, 'overpayment_handling'::text, 'credit_application_timing'::text, 'minimum_refund_amount'::text, 'below_threshold_action'::text, 'donation_program_name'::text, 'auto_approve_clean_reads'::text, 'unreviewed_read_billing_policy'::text, 'meter_redeployment_policy'::text, 'default_import_error_policy'::text, 'void_only_unbilled_disposition'::text, 'void_rebill_threshold'::text, 'cutover_date'::text]))));

CREATE OR REPLACE FUNCTION public.record_tenant_configuration_change() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    c_policy_keys CONSTANT text[] := ARRAY[
        'default_partial_period_policy', 'payment_allocation_strategy',
        'overpayment_handling', 'credit_application_timing',
        'minimum_refund_amount', 'below_threshold_action',
        'donation_program_name', 'auto_approve_clean_reads',
        'unreviewed_read_billing_policy', 'meter_redeployment_policy',
        'default_import_error_policy', 'void_only_unbilled_disposition',
        'void_rebill_threshold', 'cutover_date'
    ];
    v_new     jsonb := to_jsonb(NEW);
    v_old     jsonb := CASE WHEN TG_OP = 'UPDATE' THEN to_jsonb(OLD) ELSE NULL END;
    v_source  text  := CASE WHEN TG_OP = 'INSERT' THEN 'onboarding' ELSE 'trigger' END;
    v_user    uuid;
    v_key     text;
    v_old_val jsonb;
    v_new_val jsonb;
BEGIN
    -- Actor from the RLS session context, if any. Tolerate a missing or
    -- malformed GUC rather than failing the tenant write.
    BEGIN
        v_user := NULLIF(current_setting('app.user_id', true), '')::uuid;
    EXCEPTION WHEN OTHERS THEN
        v_user := NULL;
    END;

    -- Typed policy columns.
    FOREACH v_key IN ARRAY c_policy_keys LOOP
        v_new_val := v_new -> v_key;
        v_old_val := CASE WHEN v_old IS NULL THEN NULL ELSE v_old -> v_key END;
        IF TG_OP = 'INSERT' OR v_old_val IS DISTINCT FROM v_new_val THEN
            INSERT INTO public.tenant_configuration_history
                (tenant_id, config_key, old_value, new_value, changed_by, change_source)
            VALUES
                (NEW.id, v_key, v_old_val, v_new_val, v_user, v_source);
        END IF;
    END LOOP;

    -- Top-level settings sub-objects (union of old and new keys).
    FOR v_key IN
        SELECT DISTINCT k FROM (
            SELECT jsonb_object_keys(COALESCE(NEW.settings, '{}'::jsonb)) AS k
            UNION
            SELECT jsonb_object_keys(COALESCE(CASE WHEN TG_OP = 'UPDATE' THEN OLD.settings END, '{}'::jsonb))
        ) keys
    LOOP
        v_new_val := NEW.settings -> v_key;
        v_old_val := CASE WHEN TG_OP = 'UPDATE' THEN OLD.settings -> v_key ELSE NULL END;
        IF TG_OP = 'INSERT' OR v_old_val IS DISTINCT FROM v_new_val THEN
            INSERT INTO public.tenant_configuration_history
                (tenant_id, config_key, old_value, new_value, changed_by, change_source)
            VALUES
                (NEW.id, 'settings.' || v_key, v_old_val, v_new_val, v_user, v_source);
        END IF;
    END LOOP;

    RETURN NEW;
END;
$$;

-- The recorder was the one tenants trigger not ENABLE ALWAYS (pre-existing;
-- review round 2): the audit of a cutover change should be at least as hard
-- to skip as the guard on it.
ALTER TABLE public.tenants ENABLE ALWAYS TRIGGER trg_record_tenant_configuration_change;

COMMENT ON TABLE public.tenant_configuration_history IS
    'Append-only history of every billing-relevant tenant policy value (the fourteen tenants.* policy columns (cutover_date added by v5.4.2-12) plus each top-level settings.<key> object). One row per (tenant, key, change): prior value, new value, when it took effect, who changed it. Written automatically by trg_record_tenant_configuration_change — on tenant INSERT every key is recorded (change_source=onboarding) so a default is a recorded decision, not a silent one; on UPDATE only keys whose value changed. UPDATE/DELETE rejected by trigger. effective_from is transaction time (when the change was made); valid-time policy changes wait on the A-1 bi-temporal pair. Resolve "what was key K for tenant T at time X": latest row with effective_from <= X. CI-004 / CI-006 / CI-093, Appendix A-22, schema-parity-plan Phase 2 item 2.4 (v5.4.1-02).';


-- ----------------------------------------------------------------------------
-- 4. The accuracy threshold (F-3; §7.45(7)(B)(iv)(II) per erratum E-1)
-- ----------------------------------------------------------------------------
-- "More than nominally defective" = a deviation of more than 2.0% from
-- accurate registration, in EITHER direction. Platform reference data, like
-- program_types: no tenant_id, no row security, and tally_app may only read.
-- Date-effective with a no-overlap exclusion, because a test is judged by the
-- threshold in force on its test date, not by today's.
--
-- effective_from is the date of the rule text Kyle read (as amended effective
-- 2004-07-12); whether the 2.0% figure predates that amendment was not
-- checked, so no earlier row is seeded. A migrated_full test dated before it
-- finds no threshold and refuses — load it as migrated_date_only instead
-- (residual R6).

CREATE TABLE IF NOT EXISTS public.meter_accuracy_thresholds (
    id              uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    state_code      text NOT NULL,
    service_type    text NOT NULL,
    threshold_pct   numeric(6,3) NOT NULL,
    effective_from  date NOT NULL,
    effective_to    date,
    source_note     text NOT NULL,
    created_at      timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT meter_accuracy_thresholds_pkey PRIMARY KEY (id),
    CONSTRAINT meter_accuracy_thresholds_state_code_check
        CHECK ((state_code ~ '^[A-Z]{2}$'::text)),
    CONSTRAINT meter_accuracy_thresholds_service_type_check
        CHECK ((service_type = ANY (ARRAY['water'::text, 'sewer'::text, 'electric'::text, 'gas'::text, 'stormwater'::text, 'trash'::text, 'reclaimed_water'::text]))),
    CONSTRAINT meter_accuracy_thresholds_pct_check
        CHECK (((threshold_pct > (0)::numeric) AND (threshold_pct < (100)::numeric))),
    CONSTRAINT meter_accuracy_thresholds_range_check
        CHECK (((effective_to IS NULL) OR (effective_to > effective_from))),
    CONSTRAINT meter_accuracy_thresholds_source_note_check
        CHECK ((source_note ~ '[[:alnum:]]'::text)),
    CONSTRAINT meter_accuracy_thresholds_no_overlap
        EXCLUDE USING gist (state_code WITH =, service_type WITH =,
                            daterange(effective_from, effective_to, '[)'::text) WITH &&)
);

REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.meter_accuracy_thresholds FROM tally_app;
GRANT SELECT ON public.meter_accuracy_thresholds TO tally_app;

INSERT INTO public.meter_accuracy_thresholds
    (state_code, service_type, threshold_pct, effective_from, effective_to, source_note)
SELECT 'TX', 'gas', 2.000, DATE '2004-07-12', NULL,
       '16 TAC 7.45(7)(B)(iv)(II) — more than nominally defective means a deviation of more than 2.0% from accurate registration, in either direction (Railroad Commission of Texas; rule text as amended effective 2004-07-12, re-read by Kyle 2026-09-22/23; cite corrected by erratum E-1).'
 WHERE NOT EXISTS (SELECT 1 FROM public.meter_accuracy_thresholds
                    WHERE state_code = 'TX' AND service_type = 'gas'
                      AND effective_from = DATE '2004-07-12');

COMMENT ON TABLE public.meter_accuracy_thresholds IS
    'v5.4.2-12 (F-3). The accuracy threshold a meter test is judged against, per state and service type, date-effective. Platform-fixed: tally_app may read and never write, because a tenant able to widen its own threshold could declare a failing meter accurate and dodge the mandatory refund at §7.45(7)(B)(iv)(II). A test''s outcome is DERIVED against the row in force on its test_date; the test row records which row and which figure it used. Seeded with Texas gas (2.0%) only.';

CREATE OR REPLACE FUNCTION public.meter_accuracy_threshold_for(
        p_state_code    text,
        p_service_type  text,
        p_on            date)
    RETURNS public.meter_accuracy_thresholds
    LANGUAGE plpgsql
    STABLE
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_row public.meter_accuracy_thresholds;
BEGIN
    IF p_state_code IS NULL OR p_service_type IS NULL OR p_on IS NULL THEN
        RAISE EXCEPTION 'meter_accuracy_threshold_for: state, service type and date are all required (got %, %, %)', p_state_code, p_service_type, p_on
            USING ERRCODE = 'null_value_not_allowed';
    END IF;
    SELECT * INTO v_row
      FROM public.meter_accuracy_thresholds th
     WHERE th.state_code = p_state_code
       AND th.service_type = p_service_type
       AND th.effective_from <= p_on
       AND (th.effective_to IS NULL OR th.effective_to > p_on);
    IF v_row.id IS NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('no meter accuracy threshold for %s %s in force on %s — the test''s outcome cannot be derived', p_state_code, p_service_type, p_on),
            ERRCODE = 'no_data_found',
            HINT = 'Only Texas gas is seeded (effective 2004-07-12). A service location''s state must be a two-letter code. A historical test with no threshold on record can be loaded as record_basis = migrated_date_only.';
    END IF;
    RETURN v_row;
END;
$$;

COMMENT ON FUNCTION public.meter_accuracy_threshold_for(text, text, date) IS
    'v5.4.2-12 (F-3). The threshold row in force for (state, service type) on a date; raises rather than defaulting when there is none. NULL arguments raise.';


-- ----------------------------------------------------------------------------
-- 5. The one error formula
-- ----------------------------------------------------------------------------
-- Used by BOTH the load table's generated error column and the outcome
-- derivation, so the two can never compute different numbers. Exact numeric
-- throughout — no rounding before the threshold comparison, so 2.0000001%
-- is not rounded into "accurate". Inputs are refused beyond four decimal
-- places at intake (section 8) so the value compared is the value stored.

CREATE OR REPLACE FUNCTION public.meter_test_error_pct(
        p_standard_volume numeric,
        p_meter_volume    numeric)
    RETURNS numeric
    LANGUAGE sql
    IMMUTABLE
    SET search_path = public, pg_temp
    AS $$
    SELECT (p_meter_volume - p_standard_volume) / p_standard_volume * 100;
$$;

COMMENT ON FUNCTION public.meter_test_error_pct(numeric, numeric) IS
    'v5.4.2-12. Registration error at one load point, in percent: (tested meter volume − standard volume) / standard volume × 100. Positive = the meter over-registers (fast), negative = under-registers (slow), −100 = registered nothing. The single formula behind meter_test_load_results.error_pct and meter_tests.outcome.';


-- ----------------------------------------------------------------------------
-- 6. meter_tests — one row per test, append-only
-- ----------------------------------------------------------------------------
-- WHAT THE CALLER SUPPLIES versus WHAT THE DATABASE STAMPS.
--   Caller: the meter, the test date and kind, the record basis, where and
--   for whom (customer-requested), who tested and with what, the meter's
--   constants as the tester recorded them, the raw readings (load_results),
--   an inconclusive reason if the test produced no valid measurement, a
--   service order link, a supersession.
--   Database: outcome, max_abs_error_pct, found_defective, the threshold used
--   (row, figure, state), entered_out_of_order, recorded_at, recorded_by,
--   recorded_seq.
--   A caller-supplied value for any database-owned column is REFUSED rather
--   than silently overwritten, so a caller that believes it set an outcome
--   learns immediately that it did not.
--
-- load_results is the submission as received: a JSON array of
-- {load_point, standard_volume, meter_volume[, notes]}. The database writes
-- the typed rows of meter_test_load_results from it in the same statement,
-- and they are the queryable record. Both are append-only and produced
-- together by the database, so they cannot drift apart.

CREATE TABLE IF NOT EXISTS public.meter_tests (
    id                      uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id               uuid NOT NULL,
    meter_id                uuid NOT NULL,
    test_date               date NOT NULL,
    test_kind               text NOT NULL,
    customer_requested      boolean GENERATED ALWAYS AS ((test_kind = 'customer_requested'::text)) STORED,
    record_basis            text NOT NULL,
    location_id             uuid,
    customer_id             uuid,
    performed_by_user_id    uuid,
    performed_by_name       text,
    test_equipment          text,
    test_equipment_serial   text,
    meter_serial_at_test    text,
    multiplier_at_test      numeric(10,4),
    meter_factor_at_test    numeric(10,6),
    gas_btu_factor_at_test  numeric(10,6),
    load_results            jsonb,
    inconclusive_reason     text,
    outcome                 text,
    max_abs_error_pct       numeric,
    found_defective         boolean,
    threshold_id            uuid,
    threshold_pct           numeric(6,3),
    threshold_state         text,
    entered_out_of_order    boolean DEFAULT false NOT NULL,
    service_order_id        uuid,
    supersedes_test_id      uuid,
    supersede_reason        text,
    notes                   text,
    recorded_at             timestamp with time zone DEFAULT now() NOT NULL,
    recorded_by             uuid,
    recorded_seq            bigint GENERATED ALWAYS AS IDENTITY,
    CONSTRAINT meter_tests_pkey PRIMARY KEY (id),
    CONSTRAINT meter_tests_id_tenant_id_key UNIQUE (id, tenant_id),
    -- A row may be superseded once. NULLs are distinct, so unsuperseding rows
    -- do not collide.
    CONSTRAINT meter_tests_supersedes_once_key UNIQUE (supersedes_test_id),
    CONSTRAINT meter_tests_tenant_id_fkey
        FOREIGN KEY (tenant_id) REFERENCES public.tenants(id),
    CONSTRAINT meter_tests_meter_fkey
        FOREIGN KEY (meter_id, tenant_id) REFERENCES public.meters(id, tenant_id),
    CONSTRAINT meter_tests_location_fkey
        FOREIGN KEY (location_id, tenant_id) REFERENCES public.service_locations(id, tenant_id),
    CONSTRAINT meter_tests_customer_fkey
        FOREIGN KEY (customer_id, tenant_id) REFERENCES public.customers(id, tenant_id),
    CONSTRAINT meter_tests_performed_by_fkey
        FOREIGN KEY (performed_by_user_id, tenant_id) REFERENCES public.users(id, tenant_id),
    CONSTRAINT meter_tests_service_order_fkey
        FOREIGN KEY (service_order_id, tenant_id) REFERENCES public.service_orders(id, tenant_id),
    CONSTRAINT meter_tests_supersedes_fkey
        FOREIGN KEY (supersedes_test_id, tenant_id) REFERENCES public.meter_tests(id, tenant_id),
    CONSTRAINT meter_tests_threshold_fkey
        FOREIGN KEY (threshold_id) REFERENCES public.meter_accuracy_thresholds(id),
    CONSTRAINT meter_tests_test_kind_check
        CHECK ((test_kind = ANY (ARRAY['periodic'::text, 'customer_requested'::text, 'complaint'::text, 'post_repair'::text, 'acceptance'::text, 'other'::text]))),
    CONSTRAINT meter_tests_record_basis_check
        CHECK ((record_basis = ANY (ARRAY['recorded'::text, 'migrated_full'::text, 'migrated_date_only'::text]))),
    CONSTRAINT meter_tests_outcome_check
        CHECK ((outcome = ANY (ARRAY['accurate'::text, 'fast'::text, 'slow'::text, 'non_registering'::text, 'inconclusive'::text]))),
    -- The (7)(B)(ii) field list, required on a full record (recorded or
    -- migrated_full) and not on a date-only one (F-2). Blank checks require an
    -- alphanumeric character and coalesce the NULL leg: `x ~ '...'` is NULL on
    -- a NULL x, and a CHECK passes on NULL.
    CONSTRAINT meter_tests_full_record_fields_check
        CHECK (((record_basis = 'migrated_date_only'::text)
             OR ((COALESCE(performed_by_name, ''::text) ~ '[[:alnum:]]'::text)
                 AND (COALESCE(test_equipment, ''::text) ~ '[[:alnum:]]'::text)
                 AND (COALESCE(meter_serial_at_test, ''::text) ~ '[[:alnum:]]'::text)
                 AND (multiplier_at_test IS NOT NULL) AND (multiplier_at_test > (0)::numeric)))),
    -- A full record either carries readings or says why it could not — and a
    -- MIGRATED full record must carry readings (review round 2): without them
    -- it is a date-only record in all but name, and the label alone would
    -- switch R-36's gate off. A legacy test with no readings loads as
    -- migrated_date_only.
    CONSTRAINT meter_tests_full_record_result_check
        CHECK (((record_basis = 'migrated_date_only'::text)
             OR ((outcome IS NOT NULL)
                 AND ((load_results IS NOT NULL) <> (inconclusive_reason IS NOT NULL))
                 AND ((record_basis <> 'migrated_full'::text) OR (load_results IS NOT NULL))))),
    -- A date-only record has no readings and no derived figures; it may carry
    -- the result the utility's records show, or none.
    CONSTRAINT meter_tests_date_only_shape_check
        CHECK (((record_basis <> 'migrated_date_only'::text)
             OR ((load_results IS NULL) AND (inconclusive_reason IS NULL)
                 AND (max_abs_error_pct IS NULL) AND (threshold_id IS NULL)
                 AND (found_defective IS NOT DISTINCT FROM (CASE outcome WHEN 'accurate'::text THEN false WHEN 'fast'::text THEN true WHEN 'slow'::text THEN true WHEN 'non_registering'::text THEN true ELSE NULL::boolean END))
                 AND (threshold_pct IS NULL) AND (threshold_state IS NULL)))),
    CONSTRAINT meter_tests_inconclusive_reason_check
        CHECK (((inconclusive_reason IS NULL) OR (inconclusive_reason ~ '[[:alnum:]]'::text))),
    -- D-4, confirmed by F-5: the four-year look-back is "for the same customer
    -- at the same location".
    CONSTRAINT meter_tests_customer_requested_check
        CHECK (((test_kind <> 'customer_requested'::text)
             OR ((location_id IS NOT NULL) AND (customer_id IS NOT NULL)))),
    CONSTRAINT meter_tests_supersede_pairing_check
        CHECK ((((supersedes_test_id IS NULL) AND (supersede_reason IS NULL))
             OR ((supersedes_test_id IS NOT NULL) AND (supersede_reason ~ '[[:alnum:]]'::text)
                 AND (supersedes_test_id <> id)))),
    CONSTRAINT meter_tests_load_results_shape_check
        CHECK (((load_results IS NULL) OR ((jsonb_typeof(load_results) = 'array'::text) AND (jsonb_array_length(load_results) > 0))))
);

CREATE INDEX IF NOT EXISTS idx_meter_tests_tenant ON public.meter_tests USING btree (tenant_id);
CREATE INDEX IF NOT EXISTS idx_meter_tests_meter_date ON public.meter_tests USING btree (meter_id, test_date DESC, recorded_seq DESC);
CREATE INDEX IF NOT EXISTS idx_meter_tests_location ON public.meter_tests USING btree (location_id) WHERE (location_id IS NOT NULL);
CREATE INDEX IF NOT EXISTS idx_meter_tests_customer ON public.meter_tests USING btree (customer_id) WHERE (customer_id IS NOT NULL);

ALTER TABLE public.meter_tests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.meter_tests FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_isolation ON public.meter_tests;
CREATE POLICY tenant_isolation ON public.meter_tests USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));

-- Append-only: tally_app may read and insert, never update or delete. The
-- triggers repeat it so that an owner session, or a future grant, still
-- cannot edit a recorded test.
REVOKE UPDATE, DELETE, TRUNCATE ON public.meter_tests FROM tally_app;

DROP TRIGGER IF EXISTS append_only ON public.meter_tests;
CREATE TRIGGER append_only BEFORE UPDATE OR DELETE ON public.meter_tests
    FOR EACH ROW EXECUTE FUNCTION public.enforce_append_only();
DROP TRIGGER IF EXISTS no_truncate ON public.meter_tests;
CREATE TRIGGER no_truncate BEFORE TRUNCATE ON public.meter_tests
    FOR EACH STATEMENT EXECUTE FUNCTION public.enforce_no_hard_delete();
ALTER TABLE public.meter_tests ENABLE ALWAYS TRIGGER append_only;
ALTER TABLE public.meter_tests ENABLE ALWAYS TRIGGER no_truncate;

COMMENT ON TABLE public.meter_tests IS
    'v5.4.2-12 (CI-091 / CI-092; R-31, R-34…R-36). One row per meter test, append-only — never updated or deleted; a mistake is corrected by a new row naming it in supersedes_test_id. The outcome is DERIVED by the database from the submitted readings against meter_accuracy_thresholds, never asserted by the caller. meters.last_test_date / last_test_result are a pointer maintained from here. meter_governing_test() reads it for A-2''s backbilling window.';
COMMENT ON COLUMN public.meter_tests.test_kind IS
    'D-2 (Ryan, 2026-09-23): periodic, customer_requested, complaint, post_repair, acceptance (before first install), other. Every kind anchors a backbilling window (R-34) — a customer-requested test is off-schedule and mandatory, and carries the full (7)(B)(ii) record.';
COMMENT ON COLUMN public.meter_tests.customer_requested IS
    'Generated from test_kind — one fact, one source. §7.45(7)(B)(ii)''s field list and (7)(B)(iv)(I)''s four-year look-back attach to a customer-requested test; location_id and customer_id are required on one (D-4 / F-5).';
COMMENT ON COLUMN public.meter_tests.record_basis IS
    'What the row can prove (R-35 / R-36). recorded = captured in Tally at or after the test, full field list. migrated_full = loaded at onboarding with the full field list. migrated_date_only = loaded with a date and at most a result — exactly what the (7)(B)(i) equipment record requires, so not deficient (F-2), but it cannot win a dispute over the test''s accuracy. A date-only row still anchors a window (R-36), marked, behind the supervisor gate meter_governing_test() computes. Migrated rows must be dated on or before tenants.cutover_date.';
COMMENT ON COLUMN public.meter_tests.load_results IS
    'The raw readings as submitted: a JSON array of {load_point, standard_volume, meter_volume[, notes]}, volumes in the same unit, at most four decimal places, standard_volume > 0, meter_volume >= 0. The database derives each load''s error and the test''s outcome from these and writes meter_test_load_results from them in the same statement. Absent on a date-only row, and on a full row that records an inconclusive_reason instead.';
COMMENT ON COLUMN public.meter_tests.outcome IS
    'DERIVED, never caller-set on a full record. accurate: every load within the threshold (a deviation of exactly the threshold is accurate — the rule says MORE than 2.0%). fast / slow: the largest deviation exceeds it, signed by that load. non_registering: every load registered nothing — zero registration only (Kyle R-39: a very slow meter that registers is meter_error, not non_registering), which selects the (7)(B)(v)(II) bound. inconclusive: the test produced no valid measurement (inconclusive_reason), or its largest deviations are equal and opposite — in which case found_defective is still true. On a date-only row it is the result the utility''s records show, or NULL.';
COMMENT ON COLUMN public.meter_tests.found_defective IS
    'DERIVED. Whether the test found the meter more than nominally defective (§7.45(7)(B)(iv)(II): more than the threshold off in EITHER direction, or not registering). Separate from outcome because a meter off by more than the threshold in both directions is defective with no direction to correct in (review round 1): outcome says inconclusive, this says true, and the pointer shows failed. On a date-only row it follows the recorded result (NULL where there is none or it was inconclusive); on a row with an inconclusive_reason and no readings it is NULL.';

COMMENT ON COLUMN public.meter_tests.entered_out_of_order IS
    'Stamped by the database: true when, at the moment of recording, the meter already had a non-superseded test dated LATER than this one. D-5 (accept and flag): a late entry is accepted, and A-2 (v5.4.2-13) uses this to flag evidence computed before it arrived.';
COMMENT ON COLUMN public.meter_tests.supersedes_test_id IS
    'Corrections without edits (brief §3.6): names the row this one corrects, which then drops out of the pointer and of meter_governing_test(). Same meter only; each row may be superseded once; a reason is required. A correction may NOT move the test''s date (moving it either way can lengthen a backbilling window — a question for Kyle, not a clerical fix), may not weaken its record_basis, and a test with readings may be corrected only by one with readings (review round 1).';
COMMENT ON COLUMN public.meter_tests.threshold_pct IS
    'The threshold figure the outcome was derived against, copied from threshold_id at recording so the evidence is re-derivable without trusting that the reference row never changed.';
COMMENT ON COLUMN public.meter_tests.threshold_state IS
    'The state the threshold was resolved for: the state of the METER''s location (upper-cased, trimmed) — never the caller''s location_id, which could otherwise name a past deployment in another state and so choose the rule the test is judged by. A location_id in a different state is refused.';
COMMENT ON COLUMN public.meter_tests.meter_serial_at_test IS
    'The meter''s identifying number and constants as the tester recorded them ((7)(B)(ii)), with multiplier_at_test, meter_factor_at_test and gas_btu_factor_at_test. Caller-supplied on purpose: they are what was observed at the test, and a late-entered or migrated test must not be stamped with today''s values from the mutable meter row (residual R4).';
COMMENT ON COLUMN public.meter_tests.recorded_seq IS
    'Insertion order. Ties on test_date are broken by this, never by recorded_at: now() is constant within a transaction, so two rows recorded together share a timestamp.';


-- ----------------------------------------------------------------------------
-- 7. meter_test_load_results — one row per load point, written by the database
-- ----------------------------------------------------------------------------
-- D-1: a typed child table rather than a jsonb blob, because the error at
-- each load is the figure a dispute contests and needs types, a CHECK and a
-- query path. Rows are written ONLY by meter_tests' own AFTER INSERT trigger,
-- in the statement that records the test — so once a test is recorded its
-- load rows are fixed, and no load row can be added to a test later to change
-- what it found. The fence is trigger depth (a direct INSERT fires this
-- table's BEFORE trigger at depth 1; the parent's trigger inserts at depth 2).

CREATE TABLE IF NOT EXISTS public.meter_test_load_results (
    id              uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id       uuid NOT NULL,
    meter_test_id   uuid NOT NULL,
    load_point      text NOT NULL,
    standard_volume numeric(14,4) NOT NULL,
    meter_volume    numeric(14,4) NOT NULL,
    error_pct       numeric GENERATED ALWAYS AS (public.meter_test_error_pct(standard_volume, meter_volume)) STORED,
    notes           text,
    created_at      timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT meter_test_load_results_pkey PRIMARY KEY (id),
    CONSTRAINT meter_test_load_results_point_key UNIQUE (meter_test_id, load_point),
    CONSTRAINT meter_test_load_results_tenant_id_fkey
        FOREIGN KEY (tenant_id) REFERENCES public.tenants(id),
    CONSTRAINT meter_test_load_results_test_fkey
        FOREIGN KEY (meter_test_id, tenant_id) REFERENCES public.meter_tests(id, tenant_id),
    CONSTRAINT meter_test_load_results_load_point_check
        CHECK ((load_point ~ '[[:alnum:]]'::text)),
    CONSTRAINT meter_test_load_results_standard_check
        CHECK ((standard_volume > (0)::numeric)),
    CONSTRAINT meter_test_load_results_meter_check
        CHECK ((meter_volume >= (0)::numeric))
);

CREATE INDEX IF NOT EXISTS idx_meter_test_load_results_tenant ON public.meter_test_load_results USING btree (tenant_id);

ALTER TABLE public.meter_test_load_results ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.meter_test_load_results FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_isolation ON public.meter_test_load_results;
CREATE POLICY tenant_isolation ON public.meter_test_load_results USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));

REVOKE UPDATE, DELETE, TRUNCATE ON public.meter_test_load_results FROM tally_app;

CREATE OR REPLACE FUNCTION public.enforce_load_results_written_by_test() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
BEGIN
    IF pg_trigger_depth() < 2 THEN
        RAISE EXCEPTION USING
            MESSAGE = 'meter_test_load_results rows are written only by the database, from meter_tests.load_results, in the statement that records the test — a load row added later would change what a recorded test found',
            ERRCODE = 'restrict_violation',
            HINT = 'Record the readings in meter_tests.load_results. To correct a recorded test, insert a new meter_tests row with supersedes_test_id.';
    END IF;
    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.enforce_load_results_written_by_test() IS
    'v5.4.2-12. Refuses a direct INSERT into meter_test_load_results (trigger depth < 2). Sound only while tally_app can define no code of its own — TEMP and CREATE revoked.';

DROP TRIGGER IF EXISTS a_enforce_load_results_written_by_test ON public.meter_test_load_results;
CREATE TRIGGER a_enforce_load_results_written_by_test BEFORE INSERT ON public.meter_test_load_results
    FOR EACH ROW EXECUTE FUNCTION public.enforce_load_results_written_by_test();
DROP TRIGGER IF EXISTS append_only ON public.meter_test_load_results;
CREATE TRIGGER append_only BEFORE UPDATE OR DELETE ON public.meter_test_load_results
    FOR EACH ROW EXECUTE FUNCTION public.enforce_append_only();
DROP TRIGGER IF EXISTS no_truncate ON public.meter_test_load_results;
CREATE TRIGGER no_truncate BEFORE TRUNCATE ON public.meter_test_load_results
    FOR EACH STATEMENT EXECUTE FUNCTION public.enforce_no_hard_delete();
ALTER TABLE public.meter_test_load_results ENABLE ALWAYS TRIGGER a_enforce_load_results_written_by_test;
ALTER TABLE public.meter_test_load_results ENABLE ALWAYS TRIGGER append_only;
ALTER TABLE public.meter_test_load_results ENABLE ALWAYS TRIGGER no_truncate;

COMMENT ON TABLE public.meter_test_load_results IS
    'v5.4.2-12 (D-1). The error at each load point of a meter test — the figure a dispute contests. Written only by the database from meter_tests.load_results, in the statement that records the test, and append-only thereafter. error_pct is generated by meter_test_error_pct(), the same function that derives the test''s outcome.';


-- ----------------------------------------------------------------------------
-- 8. Recording a test — validation, stamping, and the derived outcome
-- ----------------------------------------------------------------------------
-- Lock order, stated once: tenant row (FOR KEY SHARE, every basis) → meter
-- row (FOR NO KEY UPDATE). The meter lock serialises every test and absence
-- declaration for one meter, so the pointer and entered_out_of_order are
-- computed against a history no concurrent writer is changing. Under READ
-- COMMITTED each later statement in the trigger sees rows committed while
-- it waited.

-- 8a. The readings: shape, and exactly four decimal places at most, so the
-- number the outcome is derived from is the number the load table stores.
CREATE OR REPLACE FUNCTION public.meter_test_check_load_results(p_loads jsonb)
    RETURNS void
    LANGUAGE plpgsql
    IMMUTABLE
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_e    jsonb;
    v_key  text;
    v_std  numeric;
    v_met  numeric;
BEGIN
    IF p_loads IS NULL OR jsonb_typeof(p_loads) <> 'array' OR jsonb_array_length(p_loads) = 0 THEN
        RAISE EXCEPTION 'meter test load_results must be a non-empty JSON array of {load_point, standard_volume, meter_volume}'
            USING ERRCODE = 'invalid_parameter_value';
    END IF;
    FOR v_e IN SELECT e FROM jsonb_array_elements(p_loads) AS a(e) LOOP
        IF jsonb_typeof(v_e) <> 'object' THEN
            RAISE EXCEPTION 'meter test load_results: every element must be an object, got %', v_e
                USING ERRCODE = 'invalid_parameter_value';
        END IF;
        IF v_e ? 'notes' AND jsonb_typeof(v_e -> 'notes') NOT IN ('string', 'null') THEN
            RAISE EXCEPTION 'meter test load_results: notes must be a string, got %', v_e
                USING ERRCODE = 'invalid_parameter_value';
        END IF;
        FOR v_key IN SELECT jsonb_object_keys(v_e) LOOP
            IF v_key <> ALL (ARRAY['load_point', 'standard_volume', 'meter_volume', 'notes']) THEN
                RAISE EXCEPTION 'meter test load_results: unknown key "%" — allowed: load_point, standard_volume, meter_volume, notes', v_key
                    USING ERRCODE = 'invalid_parameter_value';
            END IF;
        END LOOP;
        IF jsonb_typeof(v_e -> 'load_point') IS DISTINCT FROM 'string'
           OR coalesce(v_e ->> 'load_point', '') !~ '[[:alnum:]]' THEN
            RAISE EXCEPTION 'meter test load_results: load_point must be a non-blank string, got %', v_e
                USING ERRCODE = 'invalid_parameter_value';
        END IF;
        IF jsonb_typeof(v_e -> 'standard_volume') IS DISTINCT FROM 'number'
           OR jsonb_typeof(v_e -> 'meter_volume') IS DISTINCT FROM 'number' THEN
            RAISE EXCEPTION 'meter test load_results: standard_volume and meter_volume must be JSON numbers, got %', v_e
                USING ERRCODE = 'invalid_parameter_value';
        END IF;
        v_std := (v_e ->> 'standard_volume')::numeric;
        v_met := (v_e ->> 'meter_volume')::numeric;
        IF v_std <= 0 OR v_met < 0 THEN
            RAISE EXCEPTION 'meter test load_results: standard_volume must be > 0 and meter_volume >= 0, got %', v_e
                USING ERRCODE = 'invalid_parameter_value';
        END IF;
        IF v_std <> round(v_std, 4) OR v_met <> round(v_met, 4)
           OR v_std >= 1e10 OR v_met >= 1e10 THEN
            RAISE EXCEPTION 'meter test load_results: volumes carry at most four decimal places and must be below 10^10, got % — the outcome is derived from exactly the value stored', v_e
                USING ERRCODE = 'invalid_parameter_value';
        END IF;
    END LOOP;
END;
$$;

COMMENT ON FUNCTION public.meter_test_check_load_results(jsonb) IS
    'v5.4.2-12. Validates a submitted load_results array; raises on the first defect. Four decimal places at most, so the outcome is derived from the same value numeric(14,4) stores.';

-- 8b. The derivation. One formula (meter_test_error_pct), one threshold.
CREATE OR REPLACE FUNCTION public.meter_test_derive_outcome(
        p_loads          jsonb,
        p_threshold_pct  numeric,
        OUT outcome           text,
        OUT max_abs_error_pct numeric)
    LANGUAGE plpgsql
    IMMUTABLE
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_all_zero boolean;
    v_max_pos  numeric;
    v_min_neg  numeric;
BEGIN
    -- Cast to the STORED type, numeric(14,4), before the formula: a JSON
    -- value like 0.0003000000 passes the four-decimal check but carries a
    -- larger scale, and numeric division rounds by scale (review round 1).
    SELECT bool_and(v.met = 0),
           max(abs(public.meter_test_error_pct(v.std, v.met))),
           max(public.meter_test_error_pct(v.std, v.met)),
           min(public.meter_test_error_pct(v.std, v.met))
      INTO v_all_zero, max_abs_error_pct, v_max_pos, v_min_neg
      FROM jsonb_array_elements(p_loads) AS a(e)
     CROSS JOIN LATERAL (SELECT (a.e ->> 'standard_volume')::numeric(14,4) AS std,
                                (a.e ->> 'meter_volume')::numeric(14,4)    AS met) AS v;

    IF v_all_zero THEN
        -- Zero registration at every load point: (7)(B)(v)(II), not (v)(I).
        outcome := 'non_registering';
    ELSIF max_abs_error_pct <= p_threshold_pct THEN
        -- "MORE than 2.0%" — a deviation of exactly the threshold is accurate.
        outcome := 'accurate';
    ELSIF v_max_pos = max_abs_error_pct AND -v_min_neg = max_abs_error_pct THEN
        -- Equal and opposite beyond the threshold: defective (found_defective
        -- is true), but with no direction to correct in (residual R11).
        outcome := 'inconclusive';
    ELSIF v_max_pos = max_abs_error_pct THEN
        outcome := 'fast';
    ELSE
        outcome := 'slow';
    END IF;
END;
$$;

COMMENT ON FUNCTION public.meter_test_derive_outcome(jsonb, numeric) IS
    'v5.4.2-12 (D-3). A test''s outcome from its readings: non_registering if every load registered nothing; accurate if the largest deviation is at most the threshold; else fast or slow by the sign of the largest deviation; inconclusive if the largest deviations are equal and opposite. Uses meter_test_error_pct(), the formula behind the stored load errors.';

-- 8c. The BEFORE INSERT guard.
CREATE OR REPLACE FUNCTION public.enforce_meter_test_record() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_meter     record;
    v_cutover   date;
    v_state     text;
    v_threshold public.meter_accuracy_thresholds;
    v_derived   record;
    v_target    record;
    v_order     record;
BEGIN
    IF NEW.tenant_id IS NULL OR NEW.meter_id IS NULL OR NEW.test_date IS NULL OR NEW.record_basis IS NULL THEN
        RAISE EXCEPTION 'meter test: tenant_id, meter_id, test_date and record_basis are required'
            USING ERRCODE = 'not_null_violation';
    END IF;

    -- DATABASE-OWNED COLUMNS ARE NOT THE CALLER'S TO SET. Refused, not
    -- overwritten, so a caller that thinks it set an outcome finds out.
    IF NEW.max_abs_error_pct IS NOT NULL OR NEW.threshold_id IS NOT NULL OR NEW.found_defective IS NOT NULL
       OR NEW.threshold_pct IS NOT NULL OR NEW.threshold_state IS NOT NULL
       OR (NEW.outcome IS NOT NULL AND NEW.record_basis <> 'migrated_date_only') THEN
        RAISE EXCEPTION USING
            MESSAGE = format('meter test on meter %s: outcome, max_abs_error_pct, found_defective and the threshold columns are derived by the database from the readings, never supplied — a %s row''s result comes from its load_results', NEW.meter_id, NEW.record_basis),
            ERRCODE = 'restrict_violation',
            HINT = 'Submit the raw readings in load_results, or an inconclusive_reason if the test produced no valid measurement. Only a migrated_date_only row may carry a result the utility''s records show.';
    END IF;
    NEW.recorded_at := now();
    NEW.recorded_by := NULLIF(current_setting('app.user_id', true), '')::uuid;
    NEW.entered_out_of_order := false;

    -- The go-live boundary (R-36's invariant, section 3): migrated history on
    -- or before cutover, recorded history on or after it. FOR KEY SHARE on
    -- the tenant row — no stronger than the foreign key takes — reads the
    -- latest committed cutover and conflicts only with a cutover change.
    SELECT t.cutover_date INTO v_cutover
      FROM public.tenants t WHERE t.id = NEW.tenant_id FOR KEY SHARE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'meter test: tenant % is not visible to this session', NEW.tenant_id
            USING ERRCODE = 'foreign_key_violation';
    END IF;
    IF NEW.record_basis IN ('migrated_full', 'migrated_date_only')
       AND (v_cutover IS NULL OR NEW.test_date > v_cutover) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('meter test on meter %s: a %s row must be dated on or before the tenant''s cutover_date (test_date %s, cutover %s)', NEW.meter_id, NEW.record_basis, NEW.test_date, coalesce(v_cutover::text, 'not set')),
            ERRCODE = 'check_violation',
            HINT = 'The platform sets tenants.cutover_date at onboarding, before migrated history is loaded. A test performed after cutover is record_basis = recorded.';
    END IF;
    IF NEW.record_basis = 'recorded'
       AND (v_cutover IS NULL OR NEW.test_date < v_cutover) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('meter test on meter %s: a recorded row must be dated on or after the tenant''s cutover_date (test_date %s, cutover %s) — a test from before go-live is migrated history, and carries the migrated-provenance marking', NEW.meter_id, NEW.test_date, coalesce(v_cutover::text, 'not set')),
            ERRCODE = 'check_violation',
            HINT = 'Load a pre-go-live test as migrated_full (with the field list and readings) or migrated_date_only.';
    END IF;

    SELECT m.id, m.tenant_id, m.location_id, m.service_type INTO v_meter
      FROM public.meters m
     WHERE m.id = NEW.meter_id AND m.tenant_id = NEW.tenant_id
       FOR NO KEY UPDATE;
    IF v_meter.id IS NULL THEN
        RAISE EXCEPTION 'meter test: meter % is not a meter of tenant %', NEW.meter_id, NEW.tenant_id
            USING ERRCODE = 'foreign_key_violation';
    END IF;

    IF NEW.test_date > CURRENT_DATE THEN
        RAISE EXCEPTION 'meter test on meter %: test_date % is in the future', NEW.meter_id, NEW.test_date
            USING ERRCODE = 'check_violation';
    END IF;

    -- Where the meter stood: its current location, or one it has been deployed
    -- at. Not bound to the deployment covering test_date (residual R3).
    IF NEW.location_id IS NOT NULL
       AND NEW.location_id IS DISTINCT FROM v_meter.location_id
       AND NOT EXISTS (SELECT 1 FROM public.meter_deployments d
                        WHERE d.meter_id = NEW.meter_id AND d.tenant_id = NEW.tenant_id
                          AND d.location_id = NEW.location_id) THEN
        RAISE EXCEPTION 'meter test on meter %: location % is neither the meter''s location nor one it has been deployed at', NEW.meter_id, NEW.location_id
            USING ERRCODE = 'check_violation';
    END IF;

    IF NEW.service_order_id IS NOT NULL THEN
        SELECT so.meter_id, so.order_type INTO v_order
          FROM public.service_orders so
         WHERE so.id = NEW.service_order_id AND so.tenant_id = NEW.tenant_id;
        IF v_order.meter_id IS DISTINCT FROM NEW.meter_id
           OR v_order.order_type NOT IN ('meter_test', 'meter_test_failed_replace') THEN
            RAISE EXCEPTION 'meter test on meter %: service order % is not a meter-test order for this meter (order_type %, meter %)', NEW.meter_id, NEW.service_order_id, v_order.order_type, v_order.meter_id
                USING ERRCODE = 'check_violation';
        END IF;
    END IF;

    IF NEW.supersedes_test_id IS NOT NULL THEN
        SELECT t.meter_id, t.test_date, t.record_basis, t.load_results IS NOT NULL AS has_readings,
               t.found_defective
          INTO v_target
          FROM public.meter_tests t
         WHERE t.id = NEW.supersedes_test_id AND t.tenant_id = NEW.tenant_id;
        IF v_target.meter_id IS DISTINCT FROM NEW.meter_id THEN
            RAISE EXCEPTION 'meter test on meter %: it may supersede only a test of the same meter (test % is on meter %)', NEW.meter_id, NEW.supersedes_test_id, v_target.meter_id
                USING ERRCODE = 'check_violation';
        END IF;
        IF EXISTS (SELECT 1 FROM public.meter_tests s WHERE s.supersedes_test_id = NEW.supersedes_test_id) THEN
            RAISE EXCEPTION 'meter test on meter %: test % has already been superseded — supersede the row that superseded it', NEW.meter_id, NEW.supersedes_test_id
                USING ERRCODE = 'unique_violation';
        END IF;
        -- WHAT A CORRECTION MAY CHANGE (review round 1, both reviewers). A
        -- correction that moves the date can lengthen a backbilling window
        -- in either direction — earlier moves window_start back, later can
        -- move the test past the anchor and drop it — so the date is fixed;
        -- whether a date may ever be corrected is a question for Kyle. A
        -- correction may not weaken the record (date-only < migrated_full <
        -- recorded), and a test that carried readings — or found the meter
        -- defective, even by assertion (review round 2) — may be corrected
        -- only by one that carries readings, so a failure cannot be replaced
        -- by an asserted result or a bare inconclusive_reason.
        IF NEW.test_date IS DISTINCT FROM v_target.test_date THEN
            RAISE EXCEPTION USING
                MESSAGE = format('meter test on meter %s: a correction may not move a test''s date (%s -> %s) — moving it either way can lengthen a backbilling window', NEW.meter_id, v_target.test_date, NEW.test_date),
                ERRCODE = 'check_violation',
                HINT = 'Correct the readings or fields on the same date. A test recorded against the wrong date entirely is an open question for Kyle (residual R13).';
        END IF;
        IF array_position(ARRAY['migrated_date_only', 'migrated_full', 'recorded'], NEW.record_basis)
           < array_position(ARRAY['migrated_date_only', 'migrated_full', 'recorded'], v_target.record_basis) THEN
            RAISE EXCEPTION 'meter test on meter %: a % row may not correct a % row — a correction may not weaken the record', NEW.meter_id, NEW.record_basis, v_target.record_basis
                USING ERRCODE = 'check_violation';
        END IF;
        IF (v_target.has_readings OR v_target.found_defective) AND NEW.load_results IS NULL THEN
            RAISE EXCEPTION 'meter test on meter %: test % carried readings or found the meter defective, so its correction must carry readings — a failure cannot be replaced by an asserted result or by an inconclusive_reason', NEW.meter_id, NEW.supersedes_test_id
                USING ERRCODE = 'check_violation';
        END IF;
    END IF;

    -- A SAME-DATE ROW THAT CORRECTS NOTHING MAY NOT DO WHAT A CORRECTION MAY
    -- NOT (review round 3, both reviewers). Without a supersedes_test_id, a
    -- second row for the same meter and date carrying no readings would sit
    -- beside a derived result or a recorded failure and — by insertion order
    -- or by basis — erase it from the pointer and the governing test. A
    -- same-day retest WITH readings (as-found / as-left) is still accepted.
    IF NEW.supersedes_test_id IS NULL AND NEW.load_results IS NULL
       AND EXISTS (SELECT 1 FROM public.meter_tests t
                    WHERE t.meter_id = NEW.meter_id AND t.tenant_id = NEW.tenant_id
                      AND t.test_date = NEW.test_date
                      AND (t.load_results IS NOT NULL OR t.found_defective)
                      AND NOT EXISTS (SELECT 1 FROM public.meter_tests s WHERE s.supersedes_test_id = t.id)) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('meter test on meter %s: %s already has a test with readings or a recorded failure — a second row without readings on the same date would displace it; correct that test (supersedes_test_id) or record a retest with readings', NEW.meter_id, NEW.test_date),
            ERRCODE = 'check_violation';
    END IF;

    -- The derived result, for a full record with readings.
    IF NEW.record_basis <> 'migrated_date_only' THEN
        IF NEW.inconclusive_reason IS NOT NULL THEN
            IF NEW.load_results IS NOT NULL THEN
                RAISE EXCEPTION 'meter test on meter %: a test with readings is judged by them — an inconclusive_reason is for a test that produced no valid measurement', NEW.meter_id
                    USING ERRCODE = 'check_violation';
            END IF;
            NEW.outcome := 'inconclusive';
            NEW.found_defective := NULL;
        ELSE
            PERFORM public.meter_test_check_load_results(NEW.load_results);
            -- The threshold's state comes from the METER's location, never
            -- from the caller's location_id: a caller able to name a past
            -- deployment in another state would be choosing the rule its own
            -- test is judged by. A named location in a different state is
            -- refused rather than silently judged by the wrong one.
            SELECT upper(btrim(sl.state)) INTO v_state
              FROM public.service_locations sl
             WHERE sl.id = v_meter.location_id AND sl.tenant_id = NEW.tenant_id;
            IF NEW.location_id IS NOT NULL AND EXISTS (
                   SELECT 1 FROM public.service_locations sl
                    WHERE sl.id = NEW.location_id AND sl.tenant_id = NEW.tenant_id
                      AND upper(btrim(sl.state)) IS DISTINCT FROM v_state) THEN
                RAISE EXCEPTION 'meter test on meter %: location % is in a different state from the meter''s location (%) — the accuracy threshold is resolved from the meter''s location and cannot judge a test taken under another state''s rule', NEW.meter_id, NEW.location_id, v_state
                    USING ERRCODE = 'check_violation';
            END IF;
            v_threshold := public.meter_accuracy_threshold_for(v_state, v_meter.service_type, NEW.test_date);
            SELECT d.outcome, d.max_abs_error_pct INTO v_derived
              FROM public.meter_test_derive_outcome(NEW.load_results, v_threshold.threshold_pct) AS d;
            NEW.outcome := v_derived.outcome;
            NEW.max_abs_error_pct := v_derived.max_abs_error_pct;
            NEW.found_defective := v_derived.outcome = 'non_registering'
                                   OR v_derived.max_abs_error_pct > v_threshold.threshold_pct;
            NEW.threshold_id := v_threshold.id;
            NEW.threshold_pct := v_threshold.threshold_pct;
            NEW.threshold_state := v_state;
        END IF;
    ELSE
        -- A date-only row: defective only if the utility's records say so.
        NEW.found_defective := CASE NEW.outcome
                                   WHEN 'accurate'        THEN false
                                   WHEN 'fast'            THEN true
                                   WHEN 'slow'            THEN true
                                   WHEN 'non_registering' THEN true
                                   ELSE NULL
                               END;
    END IF;

    -- D-5: accepted, and flagged, if a later-dated test was already on record.
    NEW.entered_out_of_order := EXISTS (
        SELECT 1 FROM public.meter_tests t
         WHERE t.meter_id = NEW.meter_id AND t.tenant_id = NEW.tenant_id
           AND t.test_date > NEW.test_date
           AND NOT EXISTS (SELECT 1 FROM public.meter_tests s WHERE s.supersedes_test_id = t.id));

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.enforce_meter_test_record() IS
    'v5.4.2-12. BEFORE INSERT on meter_tests: refuses caller-supplied derived columns; stamps recorded_at / recorded_by / entered_out_of_order; holds migrated rows on or before and recorded rows on or after the cutover date (tenant row FOR KEY SHARE); locks the meter row FOR NO KEY UPDATE (serialising the meter''s history without blocking inserts that merely reference the meter); refuses future dates, a location the meter was never at or in another state, a service order for another meter or of another type, and a supersession that is of another meter''s test, of a row already superseded, moves the date, weakens the record basis, or replaces readings with none; derives the outcome and found_defective from the readings against the threshold in force on the test date. Invoker rights.';

-- 8d. The AFTER INSERT half: the load rows, then the pointer.
CREATE OR REPLACE FUNCTION public.meter_test_after_record() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
BEGIN
    IF NEW.load_results IS NOT NULL THEN
        INSERT INTO public.meter_test_load_results
            (tenant_id, meter_test_id, load_point, standard_volume, meter_volume, notes)
        SELECT NEW.tenant_id, NEW.id, e ->> 'load_point',
               (e ->> 'standard_volume')::numeric, (e ->> 'meter_volume')::numeric,
               e ->> 'notes'
          FROM jsonb_array_elements(NEW.load_results) AS a(e);
    END IF;
    PERFORM public.meter_test_refresh_pointer(NEW.meter_id, NEW.tenant_id);
    RETURN NULL;
END;
$$;

COMMENT ON FUNCTION public.meter_test_after_record() IS
    'v5.4.2-12. AFTER INSERT on meter_tests: writes the typed load rows from load_results (the only path into meter_test_load_results), then refreshes the meter''s test pointer.';


-- ----------------------------------------------------------------------------
-- 9. The pointer on meters (brief §3.5)
-- ----------------------------------------------------------------------------

ALTER TABLE public.meters ADD COLUMN IF NOT EXISTS test_history_absence text;
ALTER TABLE public.meters DROP CONSTRAINT IF EXISTS meters_test_history_absence_check;
ALTER TABLE public.meters ADD CONSTRAINT meters_test_history_absence_check
    CHECK (((test_history_absence IS NULL) OR (test_history_absence = ANY (ARRAY['attested_none'::text, 'unknown'::text]))));

CREATE OR REPLACE FUNCTION public.meter_test_refresh_pointer(p_meter_id uuid, p_tenant_id uuid)
    RETURNS void
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_date      date;
    v_outcome   text;
    v_defective boolean;
    v_result    text;
BEGIN
    -- Latest TEST DATE among non-superseded rows — not the last row inserted,
    -- so a late entry with an earlier date never moves the pointer back. On a
    -- tie of dates: a row with readings beats one without; among rows
    -- without, an asserted failure beats any other assertion; then the
    -- stronger record (review round 2); only then the later insertion (round
    -- 3). The ranking mirrors what a correction may and may not replace — a
    -- failure is displaced only by readings — and among rows with readings
    -- the later same-day retest (as-left) governs. The insert guard already
    -- refuses the parallel rows that would need this; it keeps both readers
    -- consistent whatever is on disk.
    SELECT t.test_date, t.outcome, t.found_defective INTO v_date, v_outcome, v_defective
      FROM public.meter_tests t
     WHERE t.meter_id = p_meter_id AND t.tenant_id = p_tenant_id
       AND NOT EXISTS (SELECT 1 FROM public.meter_tests s WHERE s.supersedes_test_id = t.id)
     ORDER BY t.test_date DESC,
              (t.load_results IS NOT NULL) DESC,
              (t.found_defective IS TRUE AND t.load_results IS NULL) DESC,
              array_position(ARRAY['migrated_date_only', 'migrated_full', 'recorded'], t.record_basis) DESC,
              t.recorded_seq DESC
     LIMIT 1;
    v_result := CASE
                    WHEN v_defective              THEN 'failed'
                    WHEN v_outcome = 'accurate'     THEN 'passed'
                    WHEN v_outcome = 'inconclusive' THEN 'conditional'
                    ELSE NULL
                END;
    UPDATE public.meters m
       SET last_test_date = v_date, last_test_result = v_result
     WHERE m.id = p_meter_id AND m.tenant_id = p_tenant_id
       AND (m.last_test_date IS DISTINCT FROM v_date OR m.last_test_result IS DISTINCT FROM v_result);
END;
$$;

COMMENT ON FUNCTION public.meter_test_refresh_pointer(uuid, uuid) IS
    'v5.4.2-12. Sets meters.last_test_date / last_test_result from the latest non-superseded test by test_date (ties by recorded_seq). Result mapping: found_defective → failed (which covers fast, slow, non_registering, and an inconclusive test that was more than the threshold off both ways); otherwise accurate → passed, inconclusive → conditional; a date-only row with no result → NULL. Called only from the meter_tests trigger; the meters guard refuses the same write from anywhere else.';

CREATE OR REPLACE FUNCTION public.enforce_meter_test_pointer() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
BEGIN
    IF pg_trigger_depth() >= 2 THEN
        RETURN NEW;
    END IF;
    IF TG_OP = 'INSERT' THEN
        IF NEW.last_test_date IS NOT NULL OR NEW.last_test_result IS NOT NULL
           OR NEW.test_history_absence IS NOT NULL THEN
            RAISE EXCEPTION USING
                MESSAGE = format('meter %s: last_test_date, last_test_result and test_history_absence are maintained from the test history — a new meter starts with none', NEW.meter_number),
                ERRCODE = 'check_violation',
                HINT = 'Record the test in meter_tests (or declare absence in meter_test_absence_declarations) after inserting the meter.';
        END IF;
    ELSIF NEW.last_test_date IS DISTINCT FROM OLD.last_test_date
       OR NEW.last_test_result IS DISTINCT FROM OLD.last_test_result
       OR NEW.test_history_absence IS DISTINCT FROM OLD.test_history_absence THEN
        RAISE EXCEPTION USING
            MESSAGE = format('meter %s: last_test_date, last_test_result and test_history_absence are maintained from the test history (v5.4.2-12) — record a test in meter_tests, or declare absence in meter_test_absence_declarations', OLD.meter_number),
            ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.enforce_meter_test_pointer() IS
    'v5.4.2-12 (brief §3.5). Refuses a direct write to meters.last_test_date / last_test_result / test_history_absence (trigger depth < 2) — the same fence enforce_meter_estimate_counter uses. next_test_due_date and test_interval_months stay writable: scheduling, which R-31 excludes.';

DROP TRIGGER IF EXISTS a_enforce_meter_test_pointer ON public.meters;
CREATE TRIGGER a_enforce_meter_test_pointer
    BEFORE INSERT OR UPDATE OF last_test_date, last_test_result, test_history_absence ON public.meters
    FOR EACH ROW EXECUTE FUNCTION public.enforce_meter_test_pointer();
ALTER TABLE public.meters ENABLE ALWAYS TRIGGER a_enforce_meter_test_pointer;

DROP TRIGGER IF EXISTS a_enforce_meter_test_record ON public.meter_tests;
CREATE TRIGGER a_enforce_meter_test_record BEFORE INSERT ON public.meter_tests
    FOR EACH ROW EXECUTE FUNCTION public.enforce_meter_test_record();
DROP TRIGGER IF EXISTS z_meter_test_after_record ON public.meter_tests;
CREATE TRIGGER z_meter_test_after_record AFTER INSERT ON public.meter_tests
    FOR EACH ROW EXECUTE FUNCTION public.meter_test_after_record();
ALTER TABLE public.meter_tests ENABLE ALWAYS TRIGGER a_enforce_meter_test_record;
ALTER TABLE public.meter_tests ENABLE ALWAYS TRIGGER z_meter_test_after_record;

COMMENT ON COLUMN public.meters.last_test_date IS
    'Since v5.4.2-12 a POINTER, maintained from meter_tests: the latest non-superseded test_date. Direct writes refused. Do not read it for a backbilling window — meter_governing_test() answers "the last test before this anchor", which this column cannot.';
COMMENT ON COLUMN public.meters.last_test_result IS
    'Since v5.4.2-12 a POINTER, maintained from the test last_test_date points at: failed where it found the meter defective (found_defective); otherwise accurate → passed, inconclusive → conditional. not_tested is no longer written — absence is meters.test_history_absence. Direct writes refused.';
COMMENT ON COLUMN public.meters.test_history_absence IS
    'v5.4.2-12 (R-35 refinement 2). What the tenant has declared about a meter with no test history: attested_none (states no prior test exists) or unknown (migration could not tell); NULL = nothing declared. The two compute identically — no last-test prong, the six-month cap alone — and differ only for the gap report and the R-36 gate. A POINTER to the latest meter_test_absence_declarations row; direct writes refused.';


-- ----------------------------------------------------------------------------
-- 10. Absence declarations (R-35 refinements 2 and 4)
-- ----------------------------------------------------------------------------
-- Append-only: every change is a new row, so a move to a more permissive
-- value always leaves the audit row refinement 4 asks for.

CREATE TABLE IF NOT EXISTS public.meter_test_absence_declarations (
    id              uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id       uuid NOT NULL,
    meter_id        uuid NOT NULL,
    absence         text NOT NULL,
    basis_note      text NOT NULL,
    declared_at     timestamp with time zone DEFAULT now() NOT NULL,
    declared_by     uuid,
    seq             bigint GENERATED ALWAYS AS IDENTITY,
    CONSTRAINT meter_test_absence_declarations_pkey PRIMARY KEY (id),
    CONSTRAINT meter_test_absence_declarations_tenant_id_fkey
        FOREIGN KEY (tenant_id) REFERENCES public.tenants(id),
    CONSTRAINT meter_test_absence_declarations_meter_fkey
        FOREIGN KEY (meter_id, tenant_id) REFERENCES public.meters(id, tenant_id),
    CONSTRAINT meter_test_absence_declarations_absence_check
        CHECK ((absence = ANY (ARRAY['attested_none'::text, 'unknown'::text]))),
    CONSTRAINT meter_test_absence_declarations_basis_check
        CHECK ((basis_note ~ '[[:alnum:]]'::text))
);

CREATE INDEX IF NOT EXISTS idx_meter_test_absence_tenant ON public.meter_test_absence_declarations USING btree (tenant_id);
CREATE INDEX IF NOT EXISTS idx_meter_test_absence_meter ON public.meter_test_absence_declarations USING btree (meter_id, seq DESC);

ALTER TABLE public.meter_test_absence_declarations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.meter_test_absence_declarations FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_isolation ON public.meter_test_absence_declarations;
CREATE POLICY tenant_isolation ON public.meter_test_absence_declarations USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));

REVOKE UPDATE, DELETE, TRUNCATE ON public.meter_test_absence_declarations FROM tally_app;

CREATE OR REPLACE FUNCTION public.enforce_meter_test_absence_declaration() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_meter uuid;
BEGIN
    SELECT m.id INTO v_meter
      FROM public.meters m
     WHERE m.id = NEW.meter_id AND m.tenant_id = NEW.tenant_id
       FOR NO KEY UPDATE;
    IF v_meter IS NULL THEN
        RAISE EXCEPTION 'absence declaration: meter % is not a meter of tenant %', NEW.meter_id, NEW.tenant_id
            USING ERRCODE = 'foreign_key_violation';
    END IF;
    NEW.declared_at := now();
    NEW.declared_by := NULLIF(current_setting('app.user_id', true), '')::uuid;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.meter_test_absence_after_declare() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
BEGIN
    UPDATE public.meters m
       SET test_history_absence = NEW.absence
     WHERE m.id = NEW.meter_id AND m.tenant_id = NEW.tenant_id
       AND m.test_history_absence IS DISTINCT FROM NEW.absence;
    RETURN NULL;
END;
$$;

COMMENT ON FUNCTION public.enforce_meter_test_absence_declaration() IS
    'v5.4.2-12. BEFORE INSERT on meter_test_absence_declarations: the meter must be the tenant''s (locked FOR NO KEY UPDATE, the same lock and order as a test); declared_at / declared_by stamped by the database.';
COMMENT ON FUNCTION public.meter_test_absence_after_declare() IS
    'v5.4.2-12. AFTER INSERT: points meters.test_history_absence at the declaration just made (the latest, since the meter row is locked for the duration).';

DROP TRIGGER IF EXISTS a_enforce_meter_test_absence_declaration ON public.meter_test_absence_declarations;
CREATE TRIGGER a_enforce_meter_test_absence_declaration BEFORE INSERT ON public.meter_test_absence_declarations
    FOR EACH ROW EXECUTE FUNCTION public.enforce_meter_test_absence_declaration();
DROP TRIGGER IF EXISTS z_meter_test_absence_after_declare ON public.meter_test_absence_declarations;
CREATE TRIGGER z_meter_test_absence_after_declare AFTER INSERT ON public.meter_test_absence_declarations
    FOR EACH ROW EXECUTE FUNCTION public.meter_test_absence_after_declare();
DROP TRIGGER IF EXISTS append_only ON public.meter_test_absence_declarations;
CREATE TRIGGER append_only BEFORE UPDATE OR DELETE ON public.meter_test_absence_declarations
    FOR EACH ROW EXECUTE FUNCTION public.enforce_append_only();
DROP TRIGGER IF EXISTS no_truncate ON public.meter_test_absence_declarations;
CREATE TRIGGER no_truncate BEFORE TRUNCATE ON public.meter_test_absence_declarations
    FOR EACH STATEMENT EXECUTE FUNCTION public.enforce_no_hard_delete();
ALTER TABLE public.meter_test_absence_declarations ENABLE ALWAYS TRIGGER a_enforce_meter_test_absence_declaration;
ALTER TABLE public.meter_test_absence_declarations ENABLE ALWAYS TRIGGER z_meter_test_absence_after_declare;
ALTER TABLE public.meter_test_absence_declarations ENABLE ALWAYS TRIGGER append_only;
ALTER TABLE public.meter_test_absence_declarations ENABLE ALWAYS TRIGGER no_truncate;

COMMENT ON TABLE public.meter_test_absence_declarations IS
    'v5.4.2-12 (R-35 refinements 2 and 4). What a tenant declares about a meter''s missing test history — attested_none or unknown — with the basis. It describes the history BEFORE the meter''s earliest recorded test, so a declaration on a meter that has tests is not a contradiction: meter_governing_test() reports it only for an anchor no test precedes. Append-only; the latest row per meter is meters.test_history_absence. Absence never bars an adverse correction (R-35 refinement 5): the six-month cap governs alone, behind the R-36 gate during the transitional period.';


-- ----------------------------------------------------------------------------
-- 11. The governing test (R-34), and the R-36 gate as a computed fact
-- ----------------------------------------------------------------------------
-- The most recent completed test on THE SAME METER dated STRICTLY BEFORE the
-- anchor (the discovering test's date), WHATEVER ITS OUTCOME, any test_kind,
-- superseded rows excluded. Kyle took the text over the brief's "last test
-- that found it accurate": any completed test is at or after the last
-- accurate one, so the window is shorter or equal — the reading that matches
-- the words also errs toward the customer.
--
-- It reads meter_tests, meters.test_history_absence and tenants.cutover_date
-- — and NOTHING ELSE on meters. Never install_date, test_interval_months,
-- next_test_due_date or last_test_date: a test date is never derived
-- (R-31, R-35 refinement 3). The battery sets those columns to values that
-- would change the answer if they were read.
--
-- Two tests on the same date: a row with readings, then an asserted failure,
-- then the stronger record_basis, then the later insertion (review rounds 2
-- and 3) — the same order the pointer uses.
--
-- One row, always. Where no test qualifies, the test columns are NULL and
-- `absence` says what the tenant declared (or 'undeclared'); A-2 then applies
-- the six-month cap alone (R-35 refinement 5) — it never refuses for lack of
-- a test, and this function never guesses one.
--
-- supervisor_gate (R-36): the basis is weak — a date-only migrated test, or
-- no test at all — AND anchor − 6 months still reaches before cutover (or the
-- tenant has not cut over). An undeclared absence gates like unknown: the
-- gate is for evidence nobody vouched for.

CREATE OR REPLACE FUNCTION public.meter_governing_test(
        p_meter_id     uuid,
        p_anchor_date  date)
    RETURNS TABLE (
        meter_test_id         uuid,
        test_date             date,
        test_kind             text,
        outcome               text,
        record_basis          text,
        entered_out_of_order  boolean,
        prior_test_failed     boolean,
        absence               text,
        weak_provenance       boolean,
        supervisor_gate       boolean)
    LANGUAGE plpgsql
    STABLE
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_meter   record;
    v_test    record;
    v_cutover date;
    v_weak    boolean;
BEGIN
    IF p_meter_id IS NULL OR p_anchor_date IS NULL THEN
        RAISE EXCEPTION 'meter_governing_test: a meter and an anchor date are both required (got %, %) — there is no default anchor', p_meter_id, p_anchor_date
            USING ERRCODE = 'null_value_not_allowed';
    END IF;

    SELECT m.id, m.tenant_id, m.test_history_absence INTO v_meter
      FROM public.meters m WHERE m.id = p_meter_id;
    IF v_meter.id IS NULL THEN
        RAISE EXCEPTION 'meter_governing_test: meter % is not visible to this session', p_meter_id
            USING ERRCODE = 'no_data_found';
    END IF;

    SELECT t.id, t.test_date, t.test_kind, t.outcome, t.record_basis, t.entered_out_of_order, t.found_defective INTO v_test
      FROM public.meter_tests t
     WHERE t.meter_id = p_meter_id AND t.tenant_id = v_meter.tenant_id
       AND t.test_date < p_anchor_date
       AND NOT EXISTS (SELECT 1 FROM public.meter_tests s WHERE s.supersedes_test_id = t.id)
     ORDER BY t.test_date DESC,
              (t.load_results IS NOT NULL) DESC,
              (t.found_defective IS TRUE AND t.load_results IS NULL) DESC,
              array_position(ARRAY['migrated_date_only', 'migrated_full', 'recorded'], t.record_basis) DESC,
              t.recorded_seq DESC
     LIMIT 1;

    SELECT tn.cutover_date INTO v_cutover FROM public.tenants tn WHERE tn.id = v_meter.tenant_id;

    v_weak := v_test.id IS NULL OR v_test.record_basis = 'migrated_date_only';

    meter_test_id        := v_test.id;
    test_date            := v_test.test_date;
    test_kind            := v_test.test_kind;
    outcome              := v_test.outcome;
    record_basis         := v_test.record_basis;
    entered_out_of_order := v_test.entered_out_of_order;
    prior_test_failed    := coalesce(v_test.found_defective, false);
    absence              := CASE WHEN v_test.id IS NULL
                                 THEN coalesce(v_meter.test_history_absence, 'undeclared') END;
    weak_provenance      := v_weak;
    -- Stated in the SAME arithmetic A-2 uses for the six-month bound
    -- (anchor − 6 months), not as cutover + 6 months: at month ends the two
    -- are not inverses (cutover 2026-08-31 + 6 months = 2027-02-28, but
    -- 2027-02-28 − 6 months = 2026-08-28), and the forward form lapsed the
    -- gate while a migrated date still set the window (review round 1, both
    -- reviewers). The gate applies exactly while the six-month bound still
    -- reaches back before cutover — i.e. while a pre-cutover date can matter.
    supervisor_gate      := v_weak AND (v_cutover IS NULL
                                        OR (p_anchor_date - interval '6 months')::date < v_cutover);
    RETURN NEXT;
END;
$$;

COMMENT ON FUNCTION public.meter_governing_test(uuid, date) IS
    'v5.4.2-12 (R-34, R-35, R-36). "The last test of the meter" for §7.45(7)(B)(v)(I): the most recent non-superseded test on the same meter dated strictly before p_anchor_date, whatever its outcome or kind. Always one row; where none qualifies the test columns are NULL and absence reports the tenant''s declaration (or undeclared) — never an inferred date (R-31; install_date, test_interval_months and next_test_due_date are not read). prior_test_failed = the governing test itself found the meter defective (found_defective), a data-integrity flag for the operator (R-34) and not a reason to skip it. supervisor_gate = R-36''s transitional approval requirement: weak provenance (date-only or none) while anchor − 6 months still falls before cutover — stated in A-2''s own six-month arithmetic so the two cannot disagree at month ends. A-2 (v5.4.2-13) computes window_start = max(anchor − 6 months, test_date) and enforces the gate. Invoker rights: an invisible meter raises.';


-- ----------------------------------------------------------------------------
-- 12. The gap report (R-35 refinement 1)
-- ----------------------------------------------------------------------------
-- A standing surface, not a migration artefact: it persists past cutover and
-- is what the operator screens read. Invoker rights, so it shows each tenant
-- only its own meters; read-only for tally_app.

CREATE OR REPLACE VIEW public.meter_test_history_gaps
    WITH (security_invoker = true) AS
 SELECT m.tenant_id,
    m.id AS meter_id,
    m.meter_number,
    m.service_type,
    m.status,
    COALESCE(m.test_history_absence, 'undeclared'::text) AS absence,
    ( SELECT d.basis_note
           FROM public.meter_test_absence_declarations d
          WHERE d.meter_id = m.id
          ORDER BY d.seq DESC
         LIMIT 1) AS absence_basis_note,
    ( SELECT d.declared_at
           FROM public.meter_test_absence_declarations d
          WHERE d.meter_id = m.id
          ORDER BY d.seq DESC
         LIMIT 1) AS absence_declared_at
   FROM public.meters m
  WHERE NOT EXISTS ( SELECT 1
           FROM public.meter_tests t
          WHERE t.meter_id = m.id);

REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.meter_test_history_gaps FROM tally_app;
GRANT SELECT ON public.meter_test_history_gaps TO tally_app;

COMMENT ON VIEW public.meter_test_history_gaps IS
    'v5.4.2-12 (R-35 refinement 1). Every meter with no test history, with what its tenant has declared (attested_none / unknown / undeclared). A standing operator surface that persists past cutover — detection that expired at migration would discard the point of detecting. Invoker rights; read-only.';


-- ----------------------------------------------------------------------------
-- 13. Residuals, stated (R1–R18)
-- ----------------------------------------------------------------------------
-- R1. THE FEE RULE IS NOT ENFORCED. §7.45(7)(B)(iv): a customer-requested
--     test is free if none was made for that customer at that location in the
--     previous four years, the fee is capped, and it is refunded when the
--     meter is more than 2.0% off. The history makes each answerable; charging
--     and refunding is adhoc-charge work (charge_type meter_test_fee exists).
--
-- R2. customer_id IS BOUND ONLY TO THE TENANT. The fee rule's look-back is
--     per customer at a location; nothing here checks that the named
--     customer was the one served at that location on the test date. The fee
--     patch must bind it before resting a charge on it.
--
-- R3. location_id IS NOT BOUND TO THE TEST DATE. It must be the meter's
--     current location or one in its deployment history — not necessarily the
--     deployment covering test_date. meter_deployments is trigger-maintained
--     and not bi-temporal, so a date-exact binding would rest on a table that
--     can itself be wrong.
--
-- R4. THE METER CONSTANTS ARE CALLER-SUPPLIED. They are what the tester
--     recorded; stamping them from the mutable meter row would give a late
--     or migrated test today's values. They are evidence, not a guard: no
--     outcome or window reads them.
--
-- R5. THE THRESHOLD KEY IS THE METER'S CURRENT LOCATION'S service_locations.
--     state, UPPER-CASED AND TRIMMED. A location whose state is not a two-
--     letter code ("Texas") finds no threshold and its tests REFUSE, loudly.
--     A test whose named location lies in another state refuses. The meter's
--     own location_id is still tally_app-writable, so moving a meter and then
--     recording a test resolves the new location's state (Opus, round 1): with
--     only Texas gas seeded that can only refuse; once a second state is
--     seeded, binding the threshold to the deployment covering test_date is
--     the fix, and it needs meter_deployments made trustworthy first (R3).
--
-- R6. ONLY TEXAS GAS IS SEEDED, effective 2004-07-12. A full-record test on
--     any other service, or a migrated_full test before that date, refuses;
--     the latter can load as migrated_date_only. Texas-only launch scope.
--
-- R7. THE A-2 COUPLINGS ARE FACTS HERE, GUARDS IN -13. entered_out_of_order
--     (D-5), supervisor_gate (R-36) and "a test an evidence row cites cannot
--     be superseded silently" (brief §3.6) all need A-2's evidence rows to
--     act on. This patch records; v5.4.2-13 must enforce, and its battery
--     must prove each one acts.
--
-- R8. test_date <= CURRENT_DATE USES THE SESSION'S DAY BOUNDARY, as every
--     other date-vs-today check in this schema does.
--
-- R9. recorded_by / declared_by CARRY NO FOREIGN KEY. They are stamped from
--     app.user_id, which may name a platform administrator of another tenant;
--     a composite key would refuse that and a plain one would be a new
--     tenant-blind link. They are database-stamped, so not caller-chosen.
--
-- R10. THE LOAD-ROW FENCE AND THE POINTER FENCE ARE TRIGGER DEPTH. Sound
--     while tally_app can define no code (TEMP, CREATE and TRIGGER all
--     absent). The batteries run on clones that still HOLD TEMP (CREATE
--     DATABASE … TEMPLATE does not copy datacl), so they do not test that
--     premise; the deployed database does not grant it.
--
-- R11. EQUAL AND OPPOSITE DEVIATIONS BEYOND THE THRESHOLD: outcome is
--     inconclusive (no direction for a correction to run in) and
--     found_defective is true (the meter failed). Direction-less failure is
--     rare enough to record rather than rule on.
--
-- R12. non_registering MEANS EVERY LOAD REGISTERED NOTHING. A meter dead at
--     one load and registering at another is slow (−100% at that load),
--     which selects (v)(I). Kyle R-39: zero registration only.
--
-- R13. A TEST RECORDED AGAINST THE WRONG DATE CANNOT BE CORRECTED. A
--     correction must keep the date, because moving it either way can
--     lengthen a window. Whether a date correction should exist, and under
--     what gate, is a question for Kyle. Until then the wrong-dated row
--     stands, and a note can say so.
--
-- R14. THE PLATFORM-ONLY RULES NAME tally_app. The cutover guard and the
--     platform_admin grant guard (1b) both key on current_user = 'tally_app';
--     a future second application role would be unwatched by both, and — the
--     tables being FORCE RLS — would also see no history in the bounds check.
--     The same shape as -11's residual R7. Superuser and owner sessions
--     (onboarding, migrations) may set cutover and grant the role.
--
-- R16. SECTION 1b IS NOT A ROLE MODEL. It guards one transition —
--     becoming platform_admin — because this patch rests on it. tenant_admin,
--     operator and viewer remain freely assignable within a tenant — and a
--     tenant operator can DEMOTE a platform_admin row that lives in its tenant
--     (a denial, not a grant). The permission model (Kyle's coda A2;
--     "Session D") is still open. Every platform-only control, this patch's
--     included, rests on app.user_id being set by trusted code: a session able
--     to issue raw SQL can set_config() it to an administrator's id, which it
--     can read from tenant_configuration_history.changed_by. That is the RLS
--     model's premise, not this patch's to change (review round 3).
--
-- R17. TENANTS THAT EXIST BEFORE THIS PATCH GET NO BACKFILL HISTORY ROW for
--     cutover_date (NULL for all of them; a fresh deployment has none). Their
--     first change is recorded normally.
--
-- R18. WITHIN migrated_date_only, AN ASSERTED RESULT MAY BE CORRECTED TO
--     ANOTHER ASSERTED RESULT, except that a failure may not be (review
--     round 2: a defective test's correction needs readings). An
--     accurate or absent result may be corrected to anything; assertion
--     replacing assertion is what date-only means.
--
-- R15. THE LOADER CANNOT BE CAUGHT OMITTING A LOAD POINT. The schema judges
--     the readings it is given; a tester who submits only the passing load,
--     or no readings and an inconclusive_reason, is outside what a database
--     can see (Fable, round 1). The (7)(B)(ii) record of each load tested is
--     the operational control.
--
-- ----------------------------------------------------------------------------


-- ----------------------------------------------------------------------------
-- 14. The AC-32 tail
-- ----------------------------------------------------------------------------
-- Three new tenant tables and one new view, each born leaky by the default
-- grants: RLS enabled, forced and single-policy on all three, security_invoker
-- on the view. The assertion raises if any of that did not take.

SELECT public.assert_tenant_isolation_invariants();

-- ============================================================================
-- END PATCH v5.4.2-12
-- ============================================================================
