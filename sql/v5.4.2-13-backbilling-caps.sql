-- ============================================================================
-- PATCH v5.4.2-13 — backbilling: per-state rules and the records of a
--                    correction (schema-parity-plan Phase 4 Wave 3, item A-2)
--                    PARITY RE-SCOPE, 2026-09-28
-- ============================================================================
-- Authority:   Kyle's A-2 rulings R-19…R-39 with erratum E-1 (GBM
--              application/kyle-decisions-2026-09-02-a2-backbilling-caps.md,
--              …-2026-09-22-a2-straddle-and-meter-test-anchor.md,
--              …-2026-09-23-a2-override-and-cause-freeze.md); CCK-1…CCK-14;
--              the consolidation GBM application/a2-implementation-brief-
--              2026-09-21.md. Statutory basis of the Texas rows: 16 TAC §7.45.
--
--              Ryan, 2026-09-28: "A Texas only launch does not mean a Texas
--              only architecture", and the schema's job in this phase is
--              PARITY — it can represent every invariant and every
--              configurable aspect, and it protects record integrity. Rule
--              EVALUATION belongs to the C# calculation core (TECH-STACK-
--              DISCUSSION.md, locked 2026-06-07: data-driven configuration +
--              a pure, typed calculation core).
--
--              Design: application/a2-parity-rescope-2026-09-28.md.
--              Audit that led here: application/texas-only-architecture-
--              audit-2026-09-28.md.
--              What the core must do (everything the r7 draft's triggers
--              decided, with the rulings and test cases that pinned it):
--              application/a2-rules-for-the-core.md.
--
-- ----------------------------------------------------------------------------
-- What changed from the r7 draft (commit 570d437)
-- ----------------------------------------------------------------------------
--
--   r7 (3,757 lines, six review rounds) evaluated §7.45 inside triggers: the
--   window, the forfeitures, the cause and direction from the test, the
--   tamper and R-36 gates, hold eligibility, the freeze's coverage and
--   fingerprint checks, and the void-and-reissue gate. It also held the law
--   per TENANT, seeded Texas rows into every tenant, and keyed behaviour on
--   cause names. All of that is gone from the database. Nothing Kyle ruled
--   is lost: each dropped behaviour is written up for the core, and r7's
--   battery, mutations and race tests stay in git history as its scenarios.
--
-- ----------------------------------------------------------------------------
-- What lands
-- ----------------------------------------------------------------------------
--
--    1. TENANT SETTINGS — regulatory_class_mode (CCK-14; platform-set) and
--       backbilling_adverse_limit_months (R-37(d); the utility's own limit).
--    2. SUPERVISORS — only a supervisor makes a supervisor (access control).
--    3. COMPOSITE KEYS and the service_locations.jurisdiction_id repair.
--    4. DEPLOYMENT HISTORY THAT CANNOT BE REWRITTEN (record integrity).
--    5. THE LAW, PER STATE — platform-held, date-effective, cited:
--       backbilling_causes, backbilling_customer_classes, backbilling_rules,
--       backbilling_rule_window_terms. Texas gas seeded once. A rule row says
--       what the law requires as ATTRIBUTES (is the refund mandatory, how is
--       a straddling period treated, must units be kept, …) so the core
--       decides by what a rule says, never by what a cause is called.
--    6. correction_run_targets.backbill_cause — any known cause.
--    7. PREDECESSOR ACQUISITIONS, per service location.
--    8. THE CASE — the record of a finding about one meter, its event log,
--       and what "frozen" and "withdrawn" mean for the record.
--    9. THE EVALUATION AND ITS PER-PERIOD EVIDENCE — what the core decided,
--       and which rule row it used, per billed period. Append-only.
--   10. APPROVALS — who approved which evaluation, stamped.
--   11. HOLDS — the record of a hold and its closure.
--   12. (folded into 8: a frozen case cannot change.)
--   13. A test a frozen case cites cannot be superseded.
--   14. Read surfaces over the records.
--   15. Residuals. 16. The AC-32 tail.
--
-- ----------------------------------------------------------------------------
-- What the database still refuses — record integrity only
-- ----------------------------------------------------------------------------
--
--   Rows across tenants; editing or deleting evaluations, evidence, approvals,
--   events, acquisitions; evidence added to an evaluation after its own
--   transaction; changing a frozen or withdrawn case; a frozen case pinned to
--   an evaluation of another case or of a different cause or anchor; an
--   approval of another case's evaluation; superseding a test a frozen case
--   cites; overlapping open holds; changing a closed hold; a law row without
--   a citation, overlapping another for the same key, or edited other than
--   closed; any application write to the law tables; an unknown cause or
--   class; caller-supplied timestamps and actors (stamped).
--
--   It does NOT decide whether a correction is lawful. The core does, and
--   the evaluation row records which rule row it used.
--
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 1. Tenant settings (CCK-14, R-37(d))
-- ----------------------------------------------------------------------------
-- regulatory_class_mode (CCK-14): how THIS UTILITY's filed tariff draws the
-- line a consumer-protection rule turns on. Which customer classes a state's
-- rule protects is law, held per state in backbilling_customer_classes
-- (section 5); where a utility's own customers fall against that line is the
-- utility's tariff, and this is it. all_non_residential_protected (default)
-- puts every non-residential account inside, which fails toward protection;
-- explicit_class trusts customers.customer_type; volumetric_threshold is
-- declared for the CCK-4…CCK-13 resolver patch. The mode NAMES are Texas-
-- shaped (the Texas rule protects residential and small commercial); they are
-- generalised with that resolver (residual R4). Evaluating the mode is the
-- calculation core's, not the database's.
--
-- PLATFORM-SET (Ryan, 2026-09-22). Moving off the default takes protection
-- away from customers, so tally_app may change it only as a platform
-- administrator — the cutover date's answer (-12 section 3). This is access
-- control on the setting, not an evaluation of it. A tenant INSERT may carry
-- it (onboarding).
--
-- backbilling_adverse_limit_months (R-37(d)): the utility's own filed-tariff
-- limit on how far back it bills customers for under-billing — shorter than
-- the law, never longer. The core applies it; the database stores it and logs
-- every change. NULL means no utility limit.

ALTER TABLE public.tenants
    ADD COLUMN IF NOT EXISTS regulatory_class_mode text
        DEFAULT 'all_non_residential_protected'::text NOT NULL,
    ADD COLUMN IF NOT EXISTS backbilling_adverse_limit_months integer;

ALTER TABLE public.tenants DROP CONSTRAINT IF EXISTS tenants_regulatory_class_mode_check;
ALTER TABLE public.tenants ADD CONSTRAINT tenants_regulatory_class_mode_check
    CHECK ((regulatory_class_mode = ANY (ARRAY[
        'all_non_residential_protected'::text,
        'explicit_class'::text,
        'volumetric_threshold'::text])));

ALTER TABLE public.tenants DROP CONSTRAINT IF EXISTS tenants_backbilling_adverse_limit_months_check;
ALTER TABLE public.tenants ADD CONSTRAINT tenants_backbilling_adverse_limit_months_check
    CHECK (((backbilling_adverse_limit_months IS NULL) OR (backbilling_adverse_limit_months > 0)));

COMMENT ON COLUMN public.tenants.regulatory_class_mode IS
    'CCK-14 (A-2, v5.4.2-13). How this utility''s filed tariff places its accounts against a consumer-protection class line (the classes a state protects are law: backbilling_customer_classes). all_non_residential_protected (default): every non-residential account inside — fails toward protection. explicit_class: trust customers.customer_type. volumetric_threshold: declared for the CCK-4…CCK-13 resolver patch. PLATFORM-SET (moving off the default removes protection). Evaluated by the calculation core, not the database. Logged in tenant_configuration_history.';

COMMENT ON COLUMN public.tenants.backbilling_adverse_limit_months IS
    'R-37(d) (A-2, v5.4.2-13). The utility''s own filed-tariff limit, in months back from a correction''s anchor, on billing customers for UNDER-billing — shorter than the law, never longer, never applied to money owed TO a customer. Applied by the calculation core; each period it excludes is recorded as a forfeiture in meter_correction_period_evidence. NULL = no utility limit. Tenant-set; logged in tenant_configuration_history.';

CREATE OR REPLACE FUNCTION public.enforce_tenant_regulatory_class_mode() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
BEGIN
    IF current_user = 'tally_app'
       AND NEW.regulatory_class_mode IS DISTINCT FROM OLD.regulatory_class_mode
       AND NOT public.is_platform_admin() THEN
        RAISE EXCEPTION USING
            MESSAGE = format('tenant %s: regulatory_class_mode is platform-set — moving it off the default removes consumer protection from a class of customers (CCK-14; v5.4.2-13)', OLD.id),
            ERRCODE = 'insufficient_privilege';
    END IF;
    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.enforce_tenant_regulatory_class_mode() IS
    'v5.4.2-13. BEFORE UPDATE OF regulatory_class_mode on tenants: tally_app may change it only as a platform administrator. The owner (onboarding) and a tenant INSERT are unaffected.';

DROP TRIGGER IF EXISTS a_enforce_tenant_regulatory_class_mode ON public.tenants;
CREATE TRIGGER a_enforce_tenant_regulatory_class_mode
    BEFORE UPDATE OF regulatory_class_mode ON public.tenants
    FOR EACH ROW EXECUTE FUNCTION public.enforce_tenant_regulatory_class_mode();
ALTER TABLE public.tenants ENABLE ALWAYS TRIGGER a_enforce_tenant_regulatory_class_mode;

-- The configuration recorder, re-issued with the two new keys, and the
-- history table's known-key CHECK widened to match. The two lists must move
-- together: a key the recorder writes and the CHECK does not know refuses
-- every tenant INSERT. The body is -12's with the key list extended.
ALTER TABLE public.tenant_configuration_history DROP CONSTRAINT IF EXISTS tenant_configuration_history_key_known_check;
ALTER TABLE public.tenant_configuration_history ADD CONSTRAINT tenant_configuration_history_key_known_check
    CHECK (((config_key ~~ 'settings.%'::text) OR (config_key = ANY (ARRAY['default_partial_period_policy'::text, 'payment_allocation_strategy'::text, 'overpayment_handling'::text, 'credit_application_timing'::text, 'minimum_refund_amount'::text, 'below_threshold_action'::text, 'donation_program_name'::text, 'auto_approve_clean_reads'::text, 'unreviewed_read_billing_policy'::text, 'meter_redeployment_policy'::text, 'default_import_error_policy'::text, 'void_only_unbilled_disposition'::text, 'void_rebill_threshold'::text, 'cutover_date'::text, 'regulatory_class_mode'::text, 'backbilling_adverse_limit_months'::text]))));

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
        'void_rebill_threshold', 'cutover_date',
        'regulatory_class_mode', 'backbilling_adverse_limit_months'
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


-- ----------------------------------------------------------------------------
-- 2. Supervisors — only a supervisor makes a supervisor
-- ----------------------------------------------------------------------------
-- Kyle's rulings name supervisor approval in three places: R-36's gate on a
-- weakly evidenced adverse correction, R-38's gate on a move into
-- tampering_bypass, and R-37(c)'s unrecoverable closure of a predecessor
-- hold. users.role has no 'supervisor'; tenant_admin is the tenant's own
-- highest role, and a platform administrator outranks it.
--
-- -12 residual R16 recorded that tenant_admin was freely assignable within a
-- tenant, so an operator could promote itself and then approve its own
-- charge. This extends -12's section 1b to the second role those gates rest
-- on: for tally_app, a row may BECOME tenant_admin only when the session is
-- already a supervisor. The first administrator of a tenant is made at
-- onboarding by the owner. Still not the role model coda A2 asks for.

CREATE OR REPLACE FUNCTION public.session_is_supervisor()
    RETURNS boolean
    LANGUAGE plpgsql
    STABLE
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_user uuid;
BEGIN
    IF public.is_platform_admin() THEN
        RETURN true;
    END IF;
    BEGIN
        v_user := NULLIF(current_setting('app.user_id', true), '')::uuid;
    EXCEPTION WHEN OTHERS THEN
        RETURN false;
    END;
    RETURN EXISTS (SELECT 1 FROM public.users u
                    WHERE u.id = v_user
                      AND u.role = 'tenant_admin'
                      AND u.tenant_id = public.get_user_tenant_id());
END;
$$;

COMMENT ON FUNCTION public.session_is_supervisor() IS
    'v5.4.2-13. True when the session''s user (app.user_id) is a platform administrator or a tenant_admin of the session''s own tenant — the supervisor Kyle''s R-36, R-37(c) and R-38 gates require. Invoker rights. Rests on app.user_id being set by trusted code, as every RLS predicate here does (-12 residual R16).';

CREATE OR REPLACE FUNCTION public.enforce_tenant_admin_grant() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
BEGIN
    IF current_user <> 'tally_app' THEN
        RETURN NEW;
    END IF;
    IF NEW.role = 'tenant_admin'
       AND (TG_OP = 'INSERT' OR OLD.role IS DISTINCT FROM 'tenant_admin')
       AND NOT public.session_is_supervisor() THEN
        RAISE EXCEPTION USING
            MESSAGE = format('user %s: only a supervisor (tenant_admin or platform administrator) may grant the tenant_admin role — the backbilling approval gates rest on it, so a session that could promote itself could approve its own charge (v5.4.2-13)', NEW.id),
            ERRCODE = 'insufficient_privilege';
    END IF;
    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.enforce_tenant_admin_grant() IS
    'v5.4.2-13. For tally_app, a users row may take the tenant_admin role only when the session is already a supervisor (session_is_supervisor()). Keeping or dropping the role is unaffected; the owner is unaffected. users.id immutability is -12''s a_enforce_platform_admin_grant.';

DROP TRIGGER IF EXISTS a_enforce_tenant_admin_grant ON public.users;
CREATE TRIGGER a_enforce_tenant_admin_grant
    BEFORE INSERT OR UPDATE OF role ON public.users
    FOR EACH ROW EXECUTE FUNCTION public.enforce_tenant_admin_grant();
ALTER TABLE public.users ENABLE ALWAYS TRIGGER a_enforce_tenant_admin_grant;


-- ----------------------------------------------------------------------------
-- 3. Composite-key groundwork, and the jurisdiction repair (F-6)
-- ----------------------------------------------------------------------------
-- Every link this patch adds is tenant-composite, so its targets need
-- UNIQUE (id, tenant_id): jurisdictions (service_locations points at one)
-- and meter_deployments (a case cites one as tamper evidence, and an
-- evaluation records the one that bounded its window). Both are primary keys
-- already, so neither UNIQUE can be violated by existing data.
--
-- KNOWINGLY PROVISIONAL: if the shared-place restructure goes ahead (GBM
-- application/jurisdictions-shared-place-modelling-2026-09-22.md), the
-- jurisdiction half is partly redone — one constraint and one foreign key.

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                    WHERE conname = 'jurisdictions_id_tenant_id_key'
                      AND conrelid = 'public.jurisdictions'::regclass) THEN
        ALTER TABLE public.jurisdictions
            ADD CONSTRAINT jurisdictions_id_tenant_id_key UNIQUE (id, tenant_id);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                    WHERE conname = 'meter_deployments_id_tenant_id_key'
                      AND conrelid = 'public.meter_deployments'::regclass) THEN
        ALTER TABLE public.meter_deployments
            ADD CONSTRAINT meter_deployments_id_tenant_id_key UNIQUE (id, tenant_id);
    END IF;
END;
$$;

-- The premise-side repair. service_locations.jurisdiction_id named a city's
-- id with nothing requiring the city to belong to the same utility. Under
-- this patch jurisdiction decides how far back the law lets a correction
-- reach, so its blindness is A-2's business. Refuse to build the composite
-- key over data that already violates it rather than pass NOT VALID.
DO $$
DECLARE v_bad bigint;
BEGIN
    SELECT count(*) INTO v_bad
      FROM public.service_locations sl
      JOIN public.jurisdictions j ON j.id = sl.jurisdiction_id
     WHERE sl.jurisdiction_id IS NOT NULL
       AND j.tenant_id IS DISTINCT FROM sl.tenant_id;
    IF v_bad > 0 THEN
        RAISE EXCEPTION 'v5.4.2-13: % service_locations row(s) point at another tenant''s jurisdiction; repair the data before applying this patch', v_bad
            USING ERRCODE = 'integrity_constraint_violation',
                  HINT = 'SELECT sl.id, sl.tenant_id, sl.jurisdiction_id FROM public.service_locations sl JOIN public.jurisdictions j ON j.id = sl.jurisdiction_id WHERE j.tenant_id IS DISTINCT FROM sl.tenant_id;  NOTE: psql -f is not one transaction — section 3''s UNIQUE keys will already have landed; they are harmless and idempotent.';
    END IF;
END;
$$;

ALTER TABLE public.service_locations DROP CONSTRAINT IF EXISTS service_locations_jurisdiction_id_fkey;
ALTER TABLE public.service_locations ADD CONSTRAINT service_locations_jurisdiction_id_fkey
    FOREIGN KEY (jurisdiction_id, tenant_id) REFERENCES public.jurisdictions(id, tenant_id);

COMMENT ON COLUMN public.service_locations.jurisdiction_id IS
    'The premise''s jurisdiction (D5-2, v5.4.0-03) — through which WNA applicability, the WNA tariff variant resolve. Composite on jurisdictions(id, tenant_id) since v5.4.2-13 (one of the 229 links in GBM application/tenant-blind-foreign-keys-2026-09-22.md, repaired by A-2). Nullable: population is an onboarding concern.';


-- ----------------------------------------------------------------------------
-- 4. Deployments trustworthy enough to bound a window (R-37(a); -12 R3)
-- ----------------------------------------------------------------------------
-- RECORD INTEGRITY, kept through the parity re-scope: the calculation core
-- reads deployment history to bound a correction window (the evidence fence
-- and service-start rules are in application/a2-rules-for-the-core.md), and
-- that history is only evidence if it cannot be rewritten after the fact.
--
-- R-37(a) adds a third candidate to the window start: when the defective
-- meter went into service. Readings taken by a different meter were never
-- "previous readings" of this one. The bound comes from meter_deployments —
-- and until now every column of that table was tally_app-writable. A MAX()
-- candidate can only move the start later, so for a FAST meter (money owed
-- to the customer) a later install date is a shorter REFUND. Kyle ruled that
-- no operator input may shorten that window.
--
-- Four guards, for tally_app (the owner — migrations, onboarding — is
-- exempt):
--   * a deployment cannot be INSERTED already removed: that is a history
--     load, and in the application's hands it manufactures a gap in service
--     or a predecessor meter (review round 1, Fable). NOTE (round 2): this is
--     not the load-bearing rule it looks like — sync_meter_deployments()
--     opens and closes deployments from meters.status / start_date /
--     removal_date, so a history can be built through meters alone. What
--     fences it is the next rule and the core's evidence fence;
--   * the moment a removal is RECORDED is stamped (removal_recorded_at), so
--     a removal written after a finding cannot excuse that finding's days
--     or corroborate its shorter refund, whatever date it claims (round 2);
--   * meter_id, location_id and install_date never change. A deployment
--     entered wrong is a data repair, not an edit.
--   * removal_date and removal_reason are written once, NULL to a value.
--   * created_at is the database's clock. The core's evaluation reads
--     only deployments recorded no later than the test that found the fault,
--     so a deployment entered AFTER the finding cannot shorten its window —
--     and without a stamped created_at that filter would be caller-chosen.

-- WHEN a removal was written (review round 2, both reviewers). A removal is a
-- later write on a row created long ago, and its DATE is the caller's: pull
-- the failed meter after the test with removal_date backdated to the window
-- start, and every unbilled in-window day read as a recorded gap in service —
-- one statement, directly or through meters.status via sync_meter_
-- deployments(), which passes meters.removal_date through. The database now
-- stamps the moment the application recorded the removal; the evidence fence
-- (the core's) compares that moment, not the row's creation, and a removal
-- recorded after the finding does not end the deployment for the finding.
-- NULL on owner-loaded rows: their created_at stands in.
ALTER TABLE public.meter_deployments ADD COLUMN IF NOT EXISTS removal_recorded_at timestamp with time zone;

COMMENT ON COLUMN public.meter_deployments.removal_recorded_at IS
    'v5.4.2-13 (review round 2). When the application recorded this deployment''s removal — the database''s clock, stamped on the NULL → date transition by tally_app (directly or through sync_meter_deployments), never caller-set. NULL for a removal loaded by the owner, whose created_at stands in. A removal recorded after a correction''s finding does not end the deployment for that finding: it can neither excuse in-window days nor corroborate a shorter refund.';

CREATE OR REPLACE FUNCTION public.enforce_meter_deployment_history() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
BEGIN
    IF current_user <> 'tally_app' THEN
        RETURN NEW;
    END IF;
    IF TG_OP = 'INSERT' THEN
        IF NEW.removal_recorded_at IS NOT NULL THEN
            RAISE EXCEPTION USING
                MESSAGE = 'meter deployment: removal_recorded_at is stamped by the database when a removal is recorded',
                ERRCODE = 'restrict_violation';
        END IF;
        -- A deployment that is already over when it is entered is HISTORY,
        -- not an operational act (review round 1, Fable). Written by the
        -- application it could manufacture a gap in service or a
        -- predecessor meter at a premise, either of which shortens a refund.
        -- History loads are the owner's (onboarding); the application
        -- installs, and later removes.
        IF NEW.removal_date IS NOT NULL OR NEW.removal_reason IS NOT NULL THEN
            RAISE EXCEPTION USING
                MESSAGE = format('meter deployment of meter %s: a deployment entered already removed is a history load — the application records an installation and, later, its removal; past deployments are loaded at onboarding (v5.4.2-13)', NEW.meter_id),
                ERRCODE = 'restrict_violation';
        END IF;
        NEW.created_at := now();
        RETURN NEW;
    END IF;
    IF NEW.meter_id     IS DISTINCT FROM OLD.meter_id
       OR NEW.location_id  IS DISTINCT FROM OLD.location_id
       OR NEW.install_date IS DISTINCT FROM OLD.install_date
       OR NEW.created_at   IS DISTINCT FROM OLD.created_at
       OR NEW.removal_recorded_at IS DISTINCT FROM OLD.removal_recorded_at
       OR NEW.tenant_id    IS DISTINCT FROM OLD.tenant_id THEN
        RAISE EXCEPTION USING
            MESSAGE = format('meter deployment %s: the meter, the location, the install date and the recorded times are fixed once entered — a deployment''s start bounds a §7.45 correction window (R-37(a)), so moving it would move a refund (v5.4.2-13)', OLD.id),
            ERRCODE = 'restrict_violation',
            HINT = 'A deployment entered wrong is a data repair by the platform, not an application edit.';
    END IF;
    IF (OLD.removal_date IS NOT NULL AND NEW.removal_date IS DISTINCT FROM OLD.removal_date)
       OR (OLD.removal_reason IS NOT NULL AND NEW.removal_reason IS DISTINCT FROM OLD.removal_reason) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('meter deployment %s: removal_date and removal_reason are written once — a removal for tamper is evidence a tampering finding may cite (R-38 attachment 2) (v5.4.2-13)', OLD.id),
            ERRCODE = 'restrict_violation';
    END IF;
    IF OLD.removal_date IS NULL AND NEW.removal_date IS NOT NULL THEN
        NEW.removal_recorded_at := now();
    END IF;
    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.enforce_meter_deployment_history() IS
    'v5.4.2-13 (R-37(a)). BEFORE INSERT OR UPDATE on meter_deployments, for tally_app: no insert of a deployment already removed (a history load — the owner''s); created_at stamped from the database clock on insert; removal_recorded_at stamped when a removal is written (round 2); meter_id, location_id, install_date, created_at, removal_recorded_at and tenant_id immutable; removal_date and removal_reason written once. A deployment''s start bounds a correction window, so these are evidence.';

DROP TRIGGER IF EXISTS a_enforce_meter_deployment_history ON public.meter_deployments;
CREATE TRIGGER a_enforce_meter_deployment_history
    BEFORE INSERT OR UPDATE ON public.meter_deployments
    FOR EACH ROW EXECUTE FUNCTION public.enforce_meter_deployment_history();
ALTER TABLE public.meter_deployments ENABLE ALWAYS TRIGGER a_enforce_meter_deployment_history;


-- ----------------------------------------------------------------------------
-- 5. The law, per state (R-20, R-21, R-26, R-39, F-7) — platform-held
-- ----------------------------------------------------------------------------
-- The meter_accuracy_thresholds template (-12): no tenant_id; keyed by state
-- and service type (and here class and cause); date-effective with a
-- no-overlap exclusion; every row cites its source; tally_app reads and
-- cannot write. The state is resolved from the PREMISE, never the utility.
--
-- Four tables:
--   backbilling_causes             — names only (R-39's eight). What a cause
--                                    DOES is on the rule row, per state.
--   backbilling_customer_classes   — the classes a state's rule distinguishes.
--   backbilling_rules              — one per (state, service, class, cause,
--                                    effective range): the rule as attributes.
--   backbilling_rule_window_terms  — how far back a correction reaches, per
--                                    direction, as terms; the window starts at
--                                    the LATEST of its terms' dates; no terms
--                                    in a direction = uncapped that way.
--
-- CITY-LEVEL RULES (R-26's municipal level) wait for the shared places table
-- (residual R2); no Texas city override is seeded today.
--
-- A law row is never edited: it is closed (effective_to set once) and a new
-- row added, because evaluations cite rule rows and a cited row that could
-- change would change the record of what was decided.

CREATE TABLE IF NOT EXISTS public.backbilling_causes (
    cause_code      text NOT NULL,
    description     text NOT NULL,
    created_at      timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT backbilling_causes_pkey PRIMARY KEY (cause_code),
    CONSTRAINT backbilling_causes_code_check CHECK ((cause_code ~ '^[a-z][a-z0-9_]*$'::text)),
    CONSTRAINT backbilling_causes_description_check CHECK ((description ~ '[[:alnum:]]'::text))
);

REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.backbilling_causes FROM tally_app;
GRANT SELECT ON public.backbilling_causes TO tally_app;

COMMENT ON TABLE public.backbilling_causes IS
    'A-2 (v5.4.2-13, parity). The names of backbilling causes — R-39''s eight to start. Platform-held vocabulary; no behaviour: what a cause requires in a given state is on its backbilling_rules row. A new cause is a row, not a DDL change.';

INSERT INTO public.backbilling_causes (cause_code, description)
SELECT v.code, v.description
  FROM (VALUES
    ('meter_error',            'A test found the meter registering outside the accuracy threshold, fast or slow.'),
    ('non_registering_meter',  'A test found the meter not registering at all.'),
    ('rate_misapplication',    'The correct units were billed at the wrong price.'),
    ('estimation_catchup',     'A catch-up after estimated bills, once an actual read is taken.'),
    ('tampering_bypass',       'The meter was tampered with or bypassed. Named for the act, not a criminal conclusion (R-39 renamed tampering_theft).'),
    ('billing_constant_error', 'A wrong billing constant (multiplier, factor) was applied to correct readings.'),
    ('crossed_meters',         'Two premises were billed on each other''s meters.'),
    ('unbilled_service',       'Service was delivered and never billed.')
  ) AS v(code, description)
 WHERE NOT EXISTS (SELECT 1 FROM public.backbilling_causes c WHERE c.cause_code = v.code);


CREATE TABLE IF NOT EXISTS public.backbilling_customer_classes (
    state_code      text NOT NULL,
    service_type    text NOT NULL,
    class_code      text NOT NULL,
    description     text NOT NULL,
    source_note     text NOT NULL,
    created_at      timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT backbilling_customer_classes_pkey PRIMARY KEY (state_code, service_type, class_code),
    CONSTRAINT backbilling_customer_classes_state_code_check CHECK ((state_code ~ '^[A-Z]{2}$'::text)),
    CONSTRAINT backbilling_customer_classes_service_type_check
        CHECK ((service_type = ANY (ARRAY['water'::text, 'sewer'::text, 'electric'::text, 'gas'::text, 'stormwater'::text, 'trash'::text, 'reclaimed_water'::text]))),
    CONSTRAINT backbilling_customer_classes_code_check CHECK ((class_code ~ '^[a-z][a-z0-9_]*$'::text)),
    CONSTRAINT backbilling_customer_classes_description_check CHECK ((description ~ '[[:alnum:]]'::text)),
    CONSTRAINT backbilling_customer_classes_source_note_check CHECK ((source_note ~ '[[:alnum:]]'::text))
);

REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.backbilling_customer_classes FROM tally_app;
GRANT SELECT ON public.backbilling_customer_classes TO tally_app;

COMMENT ON TABLE public.backbilling_customer_classes IS
    'A-2 (v5.4.2-13, parity). The customer classes a state''s backbilling rule distinguishes, per service type. Law, platform-held. Which class a given account falls in is decided by the calculation core from the utility''s tariff (tenants.regulatory_class_mode, CCK-14) — the database stores the vocabulary, not the placement.';

INSERT INTO public.backbilling_customer_classes (state_code, service_type, class_code, description, source_note)
SELECT v.state_code, v.service_type, v.class_code, v.description, v.source_note
  FROM (VALUES
    ('TX', 'gas', 'protected',
     'Residential and small commercial customers — the customers 16 TAC 7.45 protects.',
     '16 TAC 7.45 (Railroad Commission of Texas; quality-of-service rule for gas utilities): applies to residential and small commercial customers (CCK-1…CCK-14).'),
    ('TX', 'gas', 'unprotected',
     'Every other customer: 16 TAC 7.45''s backbilling limits do not reach them.',
     '16 TAC 7.45 scope; ordinary limitations law and the filed tariff govern outside it.')
  ) AS v(state_code, service_type, class_code, description, source_note)
 WHERE NOT EXISTS (SELECT 1 FROM public.backbilling_customer_classes c
                    WHERE c.state_code = v.state_code AND c.service_type = v.service_type
                      AND c.class_code = v.class_code);


CREATE TABLE IF NOT EXISTS public.backbilling_rules (
    id                          uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    state_code                  text NOT NULL,
    service_type                text NOT NULL,
    customer_class              text NOT NULL,
    cause                       text NOT NULL,
    anchor_basis                text NOT NULL,
    qualifying_test_outcomes    text[],
    favourable_duty             text NOT NULL,
    adverse_straddle            text NOT NULL,
    favourable_straddle         text NOT NULL,
    delivery_path               text NOT NULL,
    requires_supervisor_evidence boolean NOT NULL,
    units_invariant             boolean NOT NULL,
    enforce_scope               text NOT NULL,
    enforce_months              integer,
    enforce_condition           text,
    effective_from              date NOT NULL,
    effective_to                date,
    source_note                 text NOT NULL,
    created_at                  timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT backbilling_rules_pkey PRIMARY KEY (id),
    CONSTRAINT backbilling_rules_class_fkey
        FOREIGN KEY (state_code, service_type, customer_class)
        REFERENCES public.backbilling_customer_classes(state_code, service_type, class_code),
    CONSTRAINT backbilling_rules_cause_fkey
        FOREIGN KEY (cause) REFERENCES public.backbilling_causes(cause_code),
    -- What the correction counts back from.
    CONSTRAINT backbilling_rules_anchor_basis_check
        CHECK ((anchor_basis = ANY (ARRAY['test_date'::text, 'discovery_date'::text]))),
    -- A test-anchored rule names the test outcomes that make a finding this
    -- cause (R-39: the outcome decides the cause); a discovery rule names none.
    CONSTRAINT backbilling_rules_qualifying_outcomes_check
        CHECK ((((anchor_basis = 'test_date'::text) AND (qualifying_test_outcomes IS NOT NULL)
                  AND (cardinality(qualifying_test_outcomes) > 0)
                  AND (qualifying_test_outcomes <@ ARRAY['fast'::text, 'slow'::text, 'non_registering'::text]))
             OR ((anchor_basis = 'discovery_date'::text) AND (qualifying_test_outcomes IS NULL)))),
    -- Must the utility correct in the customer's favour back to the window
    -- (a duty), or may it (a permission)?
    CONSTRAINT backbilling_rules_favourable_duty_check
        CHECK ((favourable_duty = ANY (ARRAY['mandatory'::text, 'permitted'::text]))),
    -- A billed period that begins before the window and ends inside it.
    CONSTRAINT backbilling_rules_straddle_check
        CHECK (((adverse_straddle = ANY (ARRAY['forfeit_whole'::text, 'prorate_days'::text, 'include_whole'::text]))
            AND (favourable_straddle = ANY (ARRAY['forfeit_whole'::text, 'prorate_days'::text, 'include_whole'::text])))),
    -- How the correction reaches a bill. 'unruled' is honest: Kyle's OQ-1 is
    -- open for most causes.
    CONSTRAINT backbilling_rules_delivery_path_check
        CHECK ((delivery_path = ANY (ARRAY['adjustment'::text, 'reissue'::text, 'unruled'::text]))),
    -- What collection may pursue on what was billed. The month count is
    -- present exactly under 'months', the condition exactly under
    -- 'conditional' — equivalences, so no stray value reads as a limit.
    CONSTRAINT backbilling_rules_enforce_scope_check
        CHECK ((enforce_scope = ANY (ARRAY['uncapped'::text, 'months'::text, 'never'::text, 'conditional'::text]))),
    CONSTRAINT backbilling_rules_enforce_months_check
        CHECK ((((enforce_scope = 'months'::text) AND (enforce_months IS NOT NULL) AND (enforce_months > 0))
             OR ((enforce_scope <> 'months'::text) AND (enforce_months IS NULL)))),
    CONSTRAINT backbilling_rules_enforce_condition_check
        CHECK ((((enforce_scope = 'conditional'::text) AND (enforce_condition = ANY (ARRAY['read_beyond_utility_control'::text])))
             OR ((enforce_scope <> 'conditional'::text) AND (enforce_condition IS NULL)))),
    CONSTRAINT backbilling_rules_range_check
        CHECK (((effective_to IS NULL) OR (effective_to > effective_from))),
    CONSTRAINT backbilling_rules_source_note_check
        CHECK ((source_note ~ '[[:alnum:]]'::text)),
    CONSTRAINT backbilling_rules_no_overlap
        EXCLUDE USING gist (state_code WITH =, service_type WITH =, customer_class WITH =, cause WITH =,
                            daterange(effective_from, effective_to, '[)'::text) WITH &&)
);

CREATE INDEX IF NOT EXISTS idx_backbilling_rules_key ON public.backbilling_rules USING btree (state_code, service_type, customer_class, cause, effective_from);

REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.backbilling_rules FROM tally_app;
GRANT SELECT ON public.backbilling_rules TO tally_app;

COMMENT ON TABLE public.backbilling_rules IS
    'A-2 (v5.4.2-13, parity). What a state''s law requires of a backbilling correction, per (state, service type, customer class, cause, effective range) — as ATTRIBUTES the calculation core reads, never as behaviour keyed on a cause name: anchor_basis, qualifying_test_outcomes, favourable_duty, adverse/favourable_straddle, delivery_path, requires_supervisor_evidence, units_invariant, enforce_scope/months/condition. How far back is in backbilling_rule_window_terms. Platform-held (tally_app reads only), cited (source_note), no overlap per key. Never edited — closed (effective_to set once) and superseded by a new row, because evaluations cite rule rows. The state comes from the premise, never the utility. A key with no row in force means no rule is known: the core must refuse, never fall back. City-level rows (R-26) wait for the places table.';
COMMENT ON COLUMN public.backbilling_rules.qualifying_test_outcomes IS
    'For a test-anchored rule, the meter_tests outcomes that make a finding this cause (R-39: the outcome decides the cause, not the operator). Texas: meter_error {fast, slow}; non_registering_meter {non_registering}. NULL exactly for a discovery-anchored rule. The core checks a case''s discovering test against it; the direction a test implies (fast → the customer is owed) is what the measurement means, fixed in the core.';
COMMENT ON COLUMN public.backbilling_rules.favourable_duty IS
    'mandatory: the utility must correct in the customer''s favour back to the favourable window (Texas: a fast meter, §7.45(7)(B)(v)(I), R-37 — no override, the only exception is a hold). permitted: it may.';
COMMENT ON COLUMN public.backbilling_rules.adverse_straddle IS
    'A billed period in which the customer OWES that begins before the adverse window and ends inside it. forfeit_whole: none of it is billed (Texas, R-32 — (v)(I) gives no estimation authority to split a period). prorate_days: the in-window days are billed. include_whole: all of it is.';
COMMENT ON COLUMN public.backbilling_rules.favourable_straddle IS
    'As adverse_straddle, for a period in which the customer is OWED (Texas: include_whole, R-32 / R-25).';
COMMENT ON COLUMN public.backbilling_rules.delivery_path IS
    'How a correction under this rule reaches a bill: adjustment (a line on a subsequent bill — Texas meter errors, R-33), reissue (void and reissue the original — Texas rate misapplication), or unruled (Kyle''s OQ-1, open).';
COMMENT ON COLUMN public.backbilling_rules.requires_supervisor_evidence IS
    'Moving a case INTO this cause needs a supervisor and recorded evidence, because it lifts customer protections (Texas: tampering_bypass, R-38 attachment 2). Enforced by the core; the case records the evidence.';
COMMENT ON COLUMN public.backbilling_rules.units_invariant IS
    'A correction under this cause must bill the original usage quantities — only the price may change (Texas: rate_misapplication, R-39 "correct units, wrong price").';
COMMENT ON COLUMN public.backbilling_rules.enforce_scope IS
    'What collection (disconnection, refusal of service) may pursue on what was billed: uncapped; months (enforce_months back); never (billed, never enforceable — Texas (4)(E)(vi), F-1); conditional (on enforce_condition, e.g. whether a missed read was beyond the utility''s control, R-30).';


CREATE TABLE IF NOT EXISTS public.backbilling_rule_window_terms (
    id              uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    rule_id         uuid NOT NULL,
    direction       text NOT NULL,
    term_kind       text NOT NULL,
    months          integer,
    created_at      timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT backbilling_rule_window_terms_pkey PRIMARY KEY (id),
    CONSTRAINT backbilling_rule_window_terms_key UNIQUE (rule_id, direction, term_kind),
    CONSTRAINT backbilling_rule_window_terms_rule_fkey
        FOREIGN KEY (rule_id) REFERENCES public.backbilling_rules(id),
    CONSTRAINT backbilling_rule_window_terms_direction_check
        CHECK ((direction = ANY (ARRAY['adverse'::text, 'favourable'::text]))),
    -- A general vocabulary of date terms. The window starts at the LATEST of
    -- a direction's terms, so "the shorter of six months or the last test" is
    -- two terms, and "half the time since the last test, capped at N months"
    -- is half_since_last_test plus months_before_anchor N.
    CONSTRAINT backbilling_rule_window_terms_kind_check
        CHECK ((term_kind = ANY (ARRAY['months_before_anchor'::text, 'last_test_any_outcome'::text,
                                       'last_test_accurate'::text, 'half_since_last_test'::text,
                                       'deployment_start'::text, 'service_start'::text]))),
    CONSTRAINT backbilling_rule_window_terms_months_check
        CHECK ((((term_kind = 'months_before_anchor'::text) AND (months IS NOT NULL) AND (months > 0))
             OR ((term_kind <> 'months_before_anchor'::text) AND (months IS NULL))))
);

REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.backbilling_rule_window_terms FROM tally_app;
GRANT SELECT ON public.backbilling_rule_window_terms TO tally_app;

COMMENT ON TABLE public.backbilling_rule_window_terms IS
    'A-2 (v5.4.2-13, parity). How far back a correction under a backbilling_rules row may reach, per direction (adverse: the customer owes; favourable: the customer is owed). The window starts at the LATEST date among the direction''s terms; a direction with no terms is uncapped. term_kind: months_before_anchor (months back from the anchor), last_test_any_outcome (the most recent test before the anchor, whatever it found — Texas R-34), last_test_accurate, half_since_last_test, deployment_start (when the meter went into service at the premise — R-37(a)), service_start. Immutable: a changed window is a new rule row.';
COMMENT ON COLUMN public.backbilling_rule_window_terms.term_kind IS
    'A general vocabulary of date terms, evaluated by the calculation core. Adding a kind is a CHECK change and a core change together; adding a state that uses existing kinds is rows only.';

-- Law rows are closed, never edited (they are cited by evaluations). Applies
-- to the owner too: a wrong row is closed and replaced, so the record of what
-- was in force stays true.
CREATE OR REPLACE FUNCTION public.enforce_backbilling_law_history() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION USING
            MESSAGE = format('%s: law rows are never deleted — close the row (effective_to) and add its successor (v5.4.2-13)', TG_TABLE_NAME),
            ERRCODE = 'restrict_violation';
    END IF;
    -- Closing an open rules row is the only edit. (Read through jsonb:
    -- window terms have no effective_to, and a direct OLD.effective_to
    -- reference fails on them even behind a table-name test.)
    IF TG_TABLE_NAME = 'backbilling_rules'
       AND (to_jsonb(OLD) ->> 'effective_to') IS NULL
       AND (to_jsonb(NEW) ->> 'effective_to') IS NOT NULL
       AND (to_jsonb(NEW) - 'effective_to') = (to_jsonb(OLD) - 'effective_to') THEN
        RETURN NEW;
    END IF;
    RAISE EXCEPTION USING
        MESSAGE = format('%s %s: law rows are never edited — evaluations cite them; close the row (effective_to, once) and add its successor (v5.4.2-13)', TG_TABLE_NAME, OLD.id),
        ERRCODE = 'restrict_violation';
END;
$$;

COMMENT ON FUNCTION public.enforce_backbilling_law_history() IS
    'v5.4.2-13 (parity). BEFORE UPDATE OR DELETE on backbilling_rules and backbilling_rule_window_terms, for every role: a rules row may only be closed (effective_to NULL → a date, nothing else changing); window terms never change; neither is deleted. Evaluations and evidence cite rule rows, so a cited row that could change would rewrite what was decided.';

DROP TRIGGER IF EXISTS a_enforce_backbilling_law_history ON public.backbilling_rules;
CREATE TRIGGER a_enforce_backbilling_law_history BEFORE UPDATE OR DELETE ON public.backbilling_rules
    FOR EACH ROW EXECUTE FUNCTION public.enforce_backbilling_law_history();
ALTER TABLE public.backbilling_rules ENABLE ALWAYS TRIGGER a_enforce_backbilling_law_history;
DROP TRIGGER IF EXISTS a_enforce_backbilling_law_history ON public.backbilling_rule_window_terms;
CREATE TRIGGER a_enforce_backbilling_law_history BEFORE UPDATE OR DELETE ON public.backbilling_rule_window_terms
    FOR EACH ROW EXECUTE FUNCTION public.enforce_backbilling_law_history();
ALTER TABLE public.backbilling_rule_window_terms ENABLE ALWAYS TRIGGER a_enforce_backbilling_law_history;


-- The Texas gas rows — R-20's table as amended by R-39 — seeded ONCE as
-- platform data, effective 2004-07-12 (the date of the §7.45 text Kyle read,
-- as -12's accuracy threshold row uses). Each row names its clause. The
-- window terms follow the rule text:
--   meter_error, protected: (7)(B)(v)(I) "the shorter of six months or the
--     last test", plus R-37(a)'s deployment start, in BOTH directions; the
--     refund back to that window is a duty (R-37).
--   non_registering_meter, protected: (7)(B)(v)(II) "not to exceed three
--     months"; adverse only (a non-registering meter under-bills).
--   every other cause, and every unprotected row: no terms (uncapped).
-- Idempotent: keyed on (state, service, class, cause, effective_from).
DO $$
DECLARE
    v_rule uuid;
    r record;
    c_from CONSTANT date := DATE '2004-07-12';
    c_unprotected CONSTANT text := '16 TAC 7.45 does not reach this class; ordinary limitations law and the filed tariff govern, outside this table.';
BEGIN
    FOR r IN
        SELECT * FROM (VALUES
        --  class          cause                     anchor            fav_duty     adv_straddle     fav_straddle    delivery     sup_ev  units   enforce       e_mo  e_cond                          source
        ('protected',   'meter_error',            'test_date',      'mandatory', 'forfeit_whole', 'include_whole', 'adjustment', false, false, 'never',       NULL::int, NULL::text,
         '16 TAC 7.45(7)(B)(v)(I) — correction for the shorter of the last six months and the last test of the meter (R-34: the most recent completed test before the discovering test, any outcome); R-37(a) adds the meter''s deployment start; a fast meter''s refund back to that window is mandatory (R-37); a straddling adverse period is forfeited whole (R-32); corrected on a subsequent bill (R-33); (4)(E)(vi) bars disconnection for an underbilling due to faulty metering (F-1).'),
        ('protected',   'non_registering_meter',  'test_date',      'permitted', 'forfeit_whole', 'include_whole', 'unruled',    false, false, 'never',       NULL, NULL,
         '16 TAC 7.45(7)(B)(v)(II) — a charge for units used but not metered for a period not to exceed three months (F-4); (4)(E)(vi) bars disconnection.'),
        ('protected',   'rate_misapplication',    'discovery_date', 'permitted', 'include_whole', 'include_whole', 'reissue',    false, true,  'months',      6,    NULL,
         '16 TAC 7.45(4)(E)(v) — no billing cap on correcting a misapplied rate; (3)(C)(iii) bounds enforcement at six months; correct units, wrong price (R-39); void and reissue (R-33).'),
        ('protected',   'estimation_catchup',     'discovery_date', 'permitted', 'include_whole', 'include_whole', 'unruled',    false, false, 'conditional', NULL, 'read_beyond_utility_control',
         'No 7.45 billing cap on an estimation catch-up; (6)(C) governs estimation and (4)(E)(vii) enforcement, turning on whether the missed read was beyond the utility''s control (R-30). R-21 rejected inheriting meter_error''s six months here.'),
        ('protected',   'tampering_bypass',       'discovery_date', 'permitted', 'include_whole', 'include_whole', 'unruled',    true,  false, 'uncapped',    NULL, NULL,
         '16 TAC 7.45(4)(D)(v) — tampering with or bypassing the meter sits outside the backbilling limits; the (4)(E)(vi) bar does not apply (R-39). Moving a case into this cause needs a supervisor and evidence (R-38 attachment 2).'),
        ('protected',   'billing_constant_error', 'discovery_date', 'permitted', 'include_whole', 'include_whole', 'unruled',    false, false, 'never',       NULL, NULL,
         'R-39: no 7.45 billing cap; enforceable classification referred to counsel — never pending, per fail-toward-protection.'),
        ('protected',   'crossed_meters',         'discovery_date', 'permitted', 'include_whole', 'include_whole', 'unruled',    false, false, 'never',       NULL, NULL,
         'R-39: no 7.45 billing cap; enforceable classification referred to counsel — never pending, per fail-toward-protection.'),
        ('protected',   'unbilled_service',       'discovery_date', 'permitted', 'include_whole', 'include_whole', 'unruled',    false, false, 'never',       NULL, NULL,
         'R-39: no 7.45 billing cap; enforceable classification referred to counsel — never pending, per fail-toward-protection.')
        ) AS t(customer_class, cause, anchor_basis, favourable_duty, adverse_straddle, favourable_straddle,
               delivery_path, requires_supervisor_evidence, units_invariant, enforce_scope, enforce_months,
               enforce_condition, source_note)
        UNION ALL
        -- Unprotected: written explicitly (every cause uncapped), so a missing
        -- rule stays an error and never reads as a permission.
        SELECT 'unprotected', c.cause_code,
               CASE WHEN c.cause_code IN ('meter_error', 'non_registering_meter') THEN 'test_date' ELSE 'discovery_date' END,
               'permitted', 'include_whole', 'include_whole',
               CASE c.cause_code WHEN 'meter_error' THEN 'adjustment' WHEN 'rate_misapplication' THEN 'reissue' ELSE 'unruled' END,
               false, c.cause_code = 'rate_misapplication', 'uncapped', NULL::int, NULL::text, c_unprotected
          FROM public.backbilling_causes c
         WHERE c.cause_code IN ('meter_error', 'non_registering_meter', 'rate_misapplication', 'estimation_catchup',
                                'tampering_bypass', 'billing_constant_error', 'crossed_meters', 'unbilled_service')
    LOOP
        IF EXISTS (SELECT 1 FROM public.backbilling_rules b
                    WHERE b.state_code = 'TX' AND b.service_type = 'gas'
                      AND b.customer_class = r.customer_class AND b.cause = r.cause
                      AND b.effective_from = c_from) THEN
            CONTINUE;
        END IF;
        INSERT INTO public.backbilling_rules
            (state_code, service_type, customer_class, cause, anchor_basis, qualifying_test_outcomes,
             favourable_duty, adverse_straddle, favourable_straddle, delivery_path, requires_supervisor_evidence,
             units_invariant, enforce_scope, enforce_months, enforce_condition,
             effective_from, effective_to, source_note)
        VALUES
            ('TX', 'gas', r.customer_class, r.cause, r.anchor_basis,
             CASE r.cause WHEN 'meter_error' THEN ARRAY['fast', 'slow']
                          WHEN 'non_registering_meter' THEN ARRAY['non_registering'] END,
             r.favourable_duty,
             r.adverse_straddle, r.favourable_straddle, r.delivery_path, r.requires_supervisor_evidence,
             r.units_invariant, r.enforce_scope, r.enforce_months, r.enforce_condition,
             c_from, NULL, r.source_note)
        RETURNING id INTO v_rule;

        IF r.customer_class = 'protected' AND r.cause = 'meter_error' THEN
            INSERT INTO public.backbilling_rule_window_terms (rule_id, direction, term_kind, months)
            VALUES (v_rule, 'adverse',    'months_before_anchor',  6),
                   (v_rule, 'adverse',    'last_test_any_outcome', NULL),
                   (v_rule, 'adverse',    'deployment_start',      NULL),
                   (v_rule, 'favourable', 'months_before_anchor',  6),
                   (v_rule, 'favourable', 'last_test_any_outcome', NULL),
                   (v_rule, 'favourable', 'deployment_start',      NULL);
        ELSIF r.customer_class = 'protected' AND r.cause = 'non_registering_meter' THEN
            INSERT INTO public.backbilling_rule_window_terms (rule_id, direction, term_kind, months)
            VALUES (v_rule, 'adverse', 'months_before_anchor', 3),
                   (v_rule, 'adverse', 'deployment_start',     NULL);
        END IF;
    END LOOP;
END;
$$;

-- ----------------------------------------------------------------------------
-- 6. The void-and-reissue path: its cause, recorded (R-19, R-33, R-39)
-- ----------------------------------------------------------------------------
-- A reissue that corrects a bill records WHY, as a backbilling cause. Which
-- causes may travel by reissue is law (backbilling_rules.delivery_path; Texas:
-- rate_misapplication, R-33), and whether a given reissue is lawful — does it
-- charge more for days already billed, does it keep the units — is the
-- calculation core's (application/a2-rules-for-the-core.md). The database
-- records the cause and keeps it pinned under a checked calculation snapshot.
--
-- NULL is a clerical re-issue with no backbilling cause.

ALTER TABLE public.correction_run_targets
    ADD COLUMN IF NOT EXISTS backbill_cause text;

ALTER TABLE public.correction_run_targets DROP CONSTRAINT IF EXISTS correction_run_targets_backbill_cause_check;
ALTER TABLE public.correction_run_targets DROP CONSTRAINT IF EXISTS correction_run_targets_backbill_cause_fkey;
ALTER TABLE public.correction_run_targets ADD CONSTRAINT correction_run_targets_backbill_cause_fkey
    FOREIGN KEY (backbill_cause) REFERENCES public.backbilling_causes(cause_code);

COMMENT ON COLUMN public.correction_run_targets.backbill_cause IS
    'R-19 / R-33 / R-39 (A-2, v5.4.2-13, parity). The backbilling cause of a void-and-reissue correction, or NULL for a clerical re-issue. Any known cause may be recorded; whether that cause may travel by reissue in the premise''s state (backbilling_rules.delivery_path) and whether this reissue is lawful are the calculation core''s to decide. Frozen with the rest of the election once a calculation snapshot exists.';

CREATE OR REPLACE FUNCTION public.enforce_correction_target_frozen_under_snapshot() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
BEGIN
    IF TG_OP = 'UPDATE'
       AND NEW.billing_run_id     IS NOT DISTINCT FROM OLD.billing_run_id
       AND NEW.voided_invoice_id  IS NOT DISTINCT FROM OLD.voided_invoice_id
       AND NEW.rate_date_mode     IS NOT DISTINCT FROM OLD.rate_date_mode
       AND NEW.rate_date_override IS NOT DISTINCT FROM OLD.rate_date_override
       AND NEW.backbill_cause     IS NOT DISTINCT FROM OLD.backbill_cause THEN
        RETURN NEW;                            -- nothing the binding reads is changing
    END IF;
    -- This statement already holds the row lock (UPDATE / DELETE), so it has
    -- waited behind any snapshot writer's mutex UPDATE on the same row and,
    -- under READ COMMITTED, now sees that writer's snapshot.
    IF EXISTS (
        SELECT 1
          FROM public.invoice_calculation_snapshots s
          JOIN public.invoices i ON i.id = s.invoice_id
         WHERE i.billing_run_id      = OLD.billing_run_id
           AND i.replaces_invoice_id = OLD.voided_invoice_id
           AND i.invoice_type        = 'correction') THEN
        RAISE EXCEPTION USING
            MESSAGE = format('correction target %s (run %s, voided invoice %s): a calculation snapshot was checked against this election; the target cannot change or be removed while that snapshot exists (v5.4.2-10; extended to backbill_cause by v5.4.2-13) — delete the draft snapshot first', OLD.id, OLD.billing_run_id, OLD.voided_invoice_id),
            ERRCODE = 'restrict_violation';
    END IF;
    -- No isolation pin: the validator's mutex is a real UPDATE of this row,
    -- so a REPEATABLE READ editor racing a writer fails on the row version
    -- natively (Fable round-2 LOW-4, Codex round 2 — independently).
    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.enforce_correction_target_frozen_under_snapshot() IS
    'v5.4.2-10 (A-3 follow-up), extended by v5.4.2-13 (A-2, R-38). BEFORE UPDATE OF billing_run_id, voided_invoice_id, rate_date_mode, rate_date_override, backbill_cause OR DELETE on correction_run_targets: refused while an invoice_calculation_snapshots row exists for the correction invoice (same run, replaces_invoice_id = voided_invoice_id). R-38: a cause freezes when the evidence computed from it is frozen; changing it means discarding the snapshot and recomputing. The snapshot validator takes the target row''s lock via an UPDATE of updated_at, so this guard waits behind in-flight writers and a REPEATABLE READ racer fails natively.';

DROP TRIGGER IF EXISTS a_enforce_correction_target_frozen_under_snapshot ON public.correction_run_targets;
CREATE TRIGGER a_enforce_correction_target_frozen_under_snapshot
    BEFORE UPDATE OF billing_run_id, voided_invoice_id, rate_date_mode, rate_date_override, backbill_cause OR DELETE ON public.correction_run_targets
    FOR EACH ROW EXECUTE FUNCTION public.enforce_correction_target_frozen_under_snapshot();


-- ----------------------------------------------------------------------------


-- ----------------------------------------------------------------------------
-- 7. Predecessor acquisitions, per service location (R-37(c))
-- ----------------------------------------------------------------------------
-- R-37(c)'s second hold code, predecessor_records_unavailable, is valid only
-- for a period billed by a prior owner of the system — which needs to know
-- when the tenant acquired THAT PREMISE. Per location, not per tenant: small
-- utilities commonly acquire part of a neighbouring system.
--
-- Write-once and append-only: a hold validated against this date, and closed
-- as unrecoverable on the strength of it, must be re-derivable later. An
-- acquisition entered wrong is a platform repair.

CREATE TABLE IF NOT EXISTS public.service_location_acquisitions (
    id                  uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id           uuid NOT NULL,
    location_id         uuid NOT NULL,
    predecessor_name    text NOT NULL,
    acquired_on         date NOT NULL,
    evidence_ref        text NOT NULL,
    recorded_at         timestamp with time zone DEFAULT now() NOT NULL,
    recorded_by         uuid,
    CONSTRAINT service_location_acquisitions_pkey PRIMARY KEY (id),
    CONSTRAINT service_location_acquisitions_location_key UNIQUE (location_id),
    CONSTRAINT service_location_acquisitions_id_tenant_id_key UNIQUE (id, tenant_id),
    CONSTRAINT service_location_acquisitions_tenant_id_fkey
        FOREIGN KEY (tenant_id) REFERENCES public.tenants(id),
    CONSTRAINT service_location_acquisitions_location_fkey
        FOREIGN KEY (location_id, tenant_id) REFERENCES public.service_locations(id, tenant_id),
    CONSTRAINT service_location_acquisitions_predecessor_check
        CHECK ((predecessor_name ~ '[[:alnum:]]'::text)),
    CONSTRAINT service_location_acquisitions_evidence_check
        CHECK ((evidence_ref ~ '[[:alnum:]]'::text))
);

CREATE INDEX IF NOT EXISTS idx_service_location_acquisitions_tenant ON public.service_location_acquisitions USING btree (tenant_id);

ALTER TABLE public.service_location_acquisitions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.service_location_acquisitions FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_isolation ON public.service_location_acquisitions;
CREATE POLICY tenant_isolation ON public.service_location_acquisitions USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));

CREATE OR REPLACE FUNCTION public.enforce_location_acquisition_record() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
BEGIN
    IF NEW.acquired_on > CURRENT_DATE THEN
        RAISE EXCEPTION USING
            MESSAGE = format('location acquisition: acquired_on %s is in the future', NEW.acquired_on),
            ERRCODE = 'check_violation';
    END IF;
    NEW.recorded_at := now();
    BEGIN
        NEW.recorded_by := NULLIF(current_setting('app.user_id', true), '')::uuid;
    EXCEPTION WHEN OTHERS THEN
        NEW.recorded_by := NULL;
    END;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS a_enforce_location_acquisition_record ON public.service_location_acquisitions;
CREATE TRIGGER a_enforce_location_acquisition_record BEFORE INSERT ON public.service_location_acquisitions
    FOR EACH ROW EXECUTE FUNCTION public.enforce_location_acquisition_record();
DROP TRIGGER IF EXISTS append_only ON public.service_location_acquisitions;
CREATE TRIGGER append_only BEFORE UPDATE OR DELETE ON public.service_location_acquisitions
    FOR EACH ROW EXECUTE FUNCTION public.enforce_append_only();
DROP TRIGGER IF EXISTS no_truncate ON public.service_location_acquisitions;
CREATE TRIGGER no_truncate BEFORE TRUNCATE ON public.service_location_acquisitions
    FOR EACH STATEMENT EXECUTE FUNCTION public.enforce_no_hard_delete();
ALTER TABLE public.service_location_acquisitions ENABLE ALWAYS TRIGGER append_only;
ALTER TABLE public.service_location_acquisitions ENABLE ALWAYS TRIGGER no_truncate;

COMMENT ON TABLE public.service_location_acquisitions IS
    'A-2 (v5.4.2-13), R-37(c). When this utility acquired a premise from a prior owner of the system — per service location, because small utilities acquire part of a neighbouring system. The calculation core validates a predecessor_records_unavailable hold against this date. Write-once, append-only; recorded_at / recorded_by stamped. Successor liability for refunds on the prior owner''s billing is with counsel (R-37 counsel bundle item 3).';


-- ----------------------------------------------------------------------------
-- 8. The meter correction case (R-19, R-33, R-37(b), R-38, R-39)
-- ----------------------------------------------------------------------------
-- One row per finding about one meter. It follows the METER — every in-scope
-- reading of it across every deployment and every occupant (R-37(b)) — which
-- is why it is keyed on the meter and not on an account or an invoice.
--
-- WHAT THE CASE RECORDS: the meter, the cause (any known cause), the test
-- that found the fault (if a test did), the anchor and its basis, the
-- direction when a test decides it, the claimed start when discovery does,
-- the reasons for every cause change, any evidence recorded for a gated
-- cause, and the status.
--
-- WHAT THE CORE DECIDES (application/a2-rules-for-the-core.md): which causes
-- a test outcome permits and the direction it implies (R-39), which cause
-- changes are allowed (R-19), when a move needs a supervisor and evidence
-- (backbilling_rules.requires_supervisor_evidence; R-38), whether a case may
-- be withdrawn while a mandatory refund stands (favourable_duty; R-37).
--
-- WHAT THE DATABASE REFUSES (record integrity):
--   * a frozen case changes only by unfreezing — status back to open with
--     its freeze cleared, in a statement that changes nothing else;
--   * a withdrawn case never changes;
--   * a frozen case pins an evaluation OF THIS CASE, computed for its
--     current cause and anchor (foreign key + trigger);
--   * the meter, tenant and opening stamps never change;
--   * opened_at/by, frozen_at/by and evidence_recorded_at/by are stamped;
--   * evidence is one kind with exactly its one reference;
--   * one live case per discovering test (two would be posted twice).
--
-- STATUS. open → frozen → open (unfreeze: discard and recompute, R-38), and
-- open → withdrawn. -14 adds posted.

CREATE TABLE IF NOT EXISTS public.meter_correction_cases (
    id                      uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id               uuid NOT NULL,
    meter_id                uuid NOT NULL,
    cause                   text NOT NULL,
    discovering_test_id     uuid,
    anchor_date             date NOT NULL,
    anchor_basis            text NOT NULL,
    direction               text,
    claimed_from            date,
    status                  text DEFAULT 'open'::text NOT NULL,
    cause_change_reason     text,
    withdrawn_reason        text,
    evidence_kind           text,
    evidence_service_order_id uuid,
    evidence_deployment_id  uuid,
    evidence_field_report_ref text,
    evidence_recorded_at    timestamp with time zone,
    evidence_recorded_by    uuid,
    frozen_evaluation_id    uuid,
    frozen_at               timestamp with time zone,
    frozen_by               uuid,
    opened_at               timestamp with time zone DEFAULT now() NOT NULL,
    opened_by               uuid,
    notes                   text,
    created_at              timestamp with time zone DEFAULT now() NOT NULL,
    updated_at              timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT meter_correction_cases_pkey PRIMARY KEY (id),
    CONSTRAINT meter_correction_cases_id_tenant_id_key UNIQUE (id, tenant_id),
    CONSTRAINT meter_correction_cases_tenant_id_fkey
        FOREIGN KEY (tenant_id) REFERENCES public.tenants(id),
    CONSTRAINT meter_correction_cases_meter_fkey
        FOREIGN KEY (meter_id, tenant_id) REFERENCES public.meters(id, tenant_id),
    CONSTRAINT meter_correction_cases_cause_fkey
        FOREIGN KEY (cause) REFERENCES public.backbilling_causes(cause_code),
    CONSTRAINT meter_correction_cases_discovering_test_fkey
        FOREIGN KEY (discovering_test_id, tenant_id) REFERENCES public.meter_tests(id, tenant_id),
    CONSTRAINT meter_correction_cases_evidence_service_order_fkey
        FOREIGN KEY (evidence_service_order_id, tenant_id) REFERENCES public.service_orders(id, tenant_id),
    CONSTRAINT meter_correction_cases_evidence_deployment_fkey
        FOREIGN KEY (evidence_deployment_id, tenant_id) REFERENCES public.meter_deployments(id, tenant_id),
    CONSTRAINT meter_correction_cases_anchor_basis_check
        CHECK ((anchor_basis = ANY (ARRAY['test_date'::text, 'discovery_date'::text]))),
    -- A test-anchored case names its test; a discovery case names no test and
    -- records how far back the fault is claimed to reach. This is what the
    -- two anchor kinds MEAN, not which causes use them (that is law).
    CONSTRAINT meter_correction_cases_anchor_shape_check
        CHECK ((((anchor_basis = 'test_date'::text) AND (discovering_test_id IS NOT NULL) AND (claimed_from IS NULL))
             OR ((anchor_basis = 'discovery_date'::text) AND (discovering_test_id IS NULL)
                  AND (claimed_from IS NOT NULL) AND (claimed_from <= anchor_date)))),
    CONSTRAINT meter_correction_cases_direction_check
        CHECK (((direction IS NULL) OR (direction = ANY (ARRAY['customer_owes'::text, 'customer_owed'::text])))),
    CONSTRAINT meter_correction_cases_status_check
        CHECK ((status = ANY (ARRAY['open'::text, 'frozen'::text, 'withdrawn'::text]))),
    CONSTRAINT meter_correction_cases_frozen_check
        CHECK (((status = 'frozen'::text) = (frozen_evaluation_id IS NOT NULL))
           AND ((frozen_evaluation_id IS NULL) = (frozen_at IS NULL))),
    CONSTRAINT meter_correction_cases_withdrawn_check
        CHECK (((status = 'withdrawn'::text) = (withdrawn_reason IS NOT NULL))
           AND ((withdrawn_reason IS NULL) OR (withdrawn_reason ~ '[[:alnum:]]'::text))),
    CONSTRAINT meter_correction_cases_cause_reason_check
        CHECK (((cause_change_reason IS NULL) OR (cause_change_reason ~ '[[:alnum:]]'::text))),
    -- Evidence is one kind with exactly its reference, or none at all.
    CONSTRAINT meter_correction_cases_evidence_check
        CHECK ((((evidence_kind IS NULL)
                  AND (evidence_service_order_id IS NULL) AND (evidence_deployment_id IS NULL)
                  AND (evidence_field_report_ref IS NULL) AND (evidence_recorded_at IS NULL)
                  AND (evidence_recorded_by IS NULL))
             OR ((evidence_kind = 'service_order'::text) AND (evidence_service_order_id IS NOT NULL)
                  AND (evidence_deployment_id IS NULL) AND (evidence_field_report_ref IS NULL))
             OR ((evidence_kind = 'deployment_removal'::text) AND (evidence_deployment_id IS NOT NULL)
                  AND (evidence_service_order_id IS NULL) AND (evidence_field_report_ref IS NULL))
             OR ((evidence_kind = 'field_report'::text) AND (coalesce(evidence_field_report_ref, ''::text) ~ '[[:alnum:]]'::text)
                  AND (evidence_service_order_id IS NULL) AND (evidence_deployment_id IS NULL))))
);

CREATE INDEX IF NOT EXISTS idx_meter_correction_cases_tenant ON public.meter_correction_cases USING btree (tenant_id);
CREATE INDEX IF NOT EXISTS idx_meter_correction_cases_meter ON public.meter_correction_cases USING btree (meter_id);
CREATE INDEX IF NOT EXISTS idx_meter_correction_cases_test ON public.meter_correction_cases USING btree (discovering_test_id);
-- One live case per finding (review round 1, Fable): two live cases on one
-- discovering test would be posted twice by -14. A withdrawn case frees it.
CREATE UNIQUE INDEX IF NOT EXISTS uq_meter_correction_cases_live_test ON public.meter_correction_cases
    USING btree (discovering_test_id) WHERE ((status <> 'withdrawn'::text) AND (discovering_test_id IS NOT NULL));

ALTER TABLE public.meter_correction_cases ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.meter_correction_cases FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_isolation ON public.meter_correction_cases;
CREATE POLICY tenant_isolation ON public.meter_correction_cases USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));

REVOKE DELETE, TRUNCATE ON public.meter_correction_cases FROM tally_app;

DROP TRIGGER IF EXISTS set_updated_at ON public.meter_correction_cases;
CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.meter_correction_cases FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();
DROP TRIGGER IF EXISTS no_hard_delete ON public.meter_correction_cases;
CREATE TRIGGER no_hard_delete BEFORE DELETE ON public.meter_correction_cases
    FOR EACH ROW EXECUTE FUNCTION public.enforce_no_hard_delete();
DROP TRIGGER IF EXISTS no_truncate ON public.meter_correction_cases;
CREATE TRIGGER no_truncate BEFORE TRUNCATE ON public.meter_correction_cases
    FOR EACH STATEMENT EXECUTE FUNCTION public.enforce_no_hard_delete();

COMMENT ON TABLE public.meter_correction_cases IS
    'A-2 (v5.4.2-13, parity). The record of one finding about one meter — the object that carries a metering correction (R-33 takes meter errors off the void-and-reissue path). Follows the METER across every deployment and occupant (R-37(b)). Records the cause, the discovering test or the claimed start, the anchor, the direction where a test decides it, cause-change reasons, evidence for a gated cause, and status (open / frozen / withdrawn; -14 adds posted). Which causes, directions, changes and withdrawals are lawful is the calculation core''s (application/a2-rules-for-the-core.md). The database keeps the record whole: a frozen case changes only by unfreezing, a withdrawn one never; stamps are the database''s; every change is logged in meter_correction_case_events.';
COMMENT ON COLUMN public.meter_correction_cases.anchor_basis IS
    'test_date: the case rests on discovering_test_id and counts back from its date. discovery_date: no test; the operator records when the fault was discovered (anchor_date) and how far back it is claimed to reach (claimed_from). Which basis a cause uses in a state is backbilling_rules.anchor_basis; the core checks the case against it.';
COMMENT ON COLUMN public.meter_correction_cases.direction IS
    'Set when a test decides it (Texas: fast → customer_owed, slow / non-registering → customer_owes — derived by the core, R-39). NULL where direction is judged per period from the sign of each amount (R-25).';
COMMENT ON COLUMN public.meter_correction_cases.evidence_kind IS
    'Evidence recorded for a cause whose rule requires it (backbilling_rules.requires_supervisor_evidence; Texas: tampering_bypass, R-38 attachment 2): a service order, a deployment removal, or a field report reference. evidence_recorded_at / _by are stamped by the database from the session. Whether evidence was required, and whether the session was a supervisor, is the core''s check.';


-- The case record guard: stamps, and what frozen / withdrawn mean. It does
-- not judge causes, directions or transitions — that is the core's.
CREATE OR REPLACE FUNCTION public.enforce_meter_correction_case_record() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_user uuid;
    v_eval record;
    c_freeze_cols CONSTANT text[] := ARRAY['status', 'frozen_evaluation_id', 'frozen_at', 'frozen_by', 'updated_at'];
BEGIN
    BEGIN
        v_user := NULLIF(current_setting('app.user_id', true), '')::uuid;
    EXCEPTION WHEN OTHERS THEN
        v_user := NULL;
    END;

    IF TG_OP = 'INSERT' THEN
        IF NEW.status <> 'open' THEN
            RAISE EXCEPTION USING
                MESSAGE = format('meter correction case: a case is opened open, not %s (v5.4.2-13)', NEW.status),
                ERRCODE = 'check_violation';
        END IF;
        NEW.opened_at  := now();
        NEW.opened_by  := v_user;
        NEW.created_at := now();
        IF NEW.evidence_kind IS NOT NULL THEN
            NEW.evidence_recorded_at := now();
            NEW.evidence_recorded_by := v_user;
        ELSE
            NEW.evidence_recorded_at := NULL;
            NEW.evidence_recorded_by := NULL;
        END IF;
        RETURN NEW;
    END IF;

    -- Never changes, in any status.
    IF NEW.tenant_id IS DISTINCT FROM OLD.tenant_id
       OR NEW.meter_id IS DISTINCT FROM OLD.meter_id
       OR NEW.opened_at IS DISTINCT FROM OLD.opened_at
       OR NEW.opened_by IS DISTINCT FROM OLD.opened_by
       OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
        RAISE EXCEPTION USING
            MESSAGE = format('meter correction case %s: the meter, the tenant and the opening stamps never change (v5.4.2-13)', OLD.id),
            ERRCODE = 'restrict_violation';
    END IF;

    IF OLD.status = 'withdrawn' THEN
        RAISE EXCEPTION USING
            MESSAGE = format('meter correction case %s is withdrawn; a withdrawn case never changes — open a new case (v5.4.2-13)', OLD.id),
            ERRCODE = 'restrict_violation';
    END IF;

    IF OLD.status = 'frozen' THEN
        -- Only an unfreeze: back to open, freeze cleared, nothing else.
        IF NEW.status <> 'open' OR NEW.frozen_evaluation_id IS NOT NULL
           OR (to_jsonb(NEW) - c_freeze_cols) <> (to_jsonb(OLD) - c_freeze_cols) THEN
            RAISE EXCEPTION USING
                MESSAGE = format('meter correction case %s is frozen; it changes only by unfreezing (status open, freeze cleared, nothing else in the same statement) — R-38 (v5.4.2-13)', OLD.id),
                ERRCODE = 'restrict_violation',
                HINT = 'UPDATE … SET status = ''open'', frozen_evaluation_id = NULL, frozen_at = NULL, frozen_by = NULL; then change the case.';
        END IF;
        NEW.frozen_at := NULL;
        NEW.frozen_by := NULL;
        RETURN NEW;
    END IF;

    -- OLD.status = 'open'.
    IF NEW.status = 'frozen' THEN
        -- A freeze pins an evaluation; it carries no other change, so the
        -- pinned evaluation describes the case as it stands.
        IF (to_jsonb(NEW) - c_freeze_cols) <> (to_jsonb(OLD) - c_freeze_cols) THEN
            RAISE EXCEPTION USING
                MESSAGE = format('meter correction case %s: a freeze changes nothing but the freeze itself (v5.4.2-13)', OLD.id),
                ERRCODE = 'restrict_violation';
        END IF;
        SELECT v.case_id, v.cause, v.anchor_date INTO v_eval
          FROM public.meter_correction_evaluations v
         WHERE v.id = NEW.frozen_evaluation_id;
        IF v_eval.case_id IS DISTINCT FROM NEW.id
           OR v_eval.cause IS DISTINCT FROM NEW.cause
           OR v_eval.anchor_date IS DISTINCT FROM NEW.anchor_date THEN
            RAISE EXCEPTION USING
                MESSAGE = format('meter correction case %s: the frozen evaluation must be one of this case''s, computed for its current cause and anchor (v5.4.2-13)', OLD.id),
                ERRCODE = 'restrict_violation';
        END IF;
        NEW.frozen_at := now();
        NEW.frozen_by := v_user;
        RETURN NEW;
    END IF;

    IF NEW.frozen_at IS DISTINCT FROM OLD.frozen_at OR NEW.frozen_by IS DISTINCT FROM OLD.frozen_by THEN
        RAISE EXCEPTION USING
            MESSAGE = format('meter correction case %s: frozen_at / frozen_by are stamped by the database (v5.4.2-13)', OLD.id),
            ERRCODE = 'restrict_violation';
    END IF;

    -- Evidence changed: stamp who recorded it and when.
    IF NEW.evidence_kind IS DISTINCT FROM OLD.evidence_kind
       OR NEW.evidence_service_order_id IS DISTINCT FROM OLD.evidence_service_order_id
       OR NEW.evidence_deployment_id IS DISTINCT FROM OLD.evidence_deployment_id
       OR NEW.evidence_field_report_ref IS DISTINCT FROM OLD.evidence_field_report_ref THEN
        IF NEW.evidence_kind IS NULL THEN
            NEW.evidence_recorded_at := NULL;
            NEW.evidence_recorded_by := NULL;
        ELSE
            NEW.evidence_recorded_at := now();
            NEW.evidence_recorded_by := v_user;
        END IF;
    ELSIF NEW.evidence_recorded_at IS DISTINCT FROM OLD.evidence_recorded_at
       OR NEW.evidence_recorded_by IS DISTINCT FROM OLD.evidence_recorded_by THEN
        RAISE EXCEPTION USING
            MESSAGE = format('meter correction case %s: evidence_recorded_at / _by are stamped by the database (v5.4.2-13)', OLD.id),
            ERRCODE = 'restrict_violation';
    END IF;

    -- A cause change carries a new reason.
    IF NEW.cause IS DISTINCT FROM OLD.cause
       AND (NEW.cause_change_reason IS NULL
            OR NEW.cause_change_reason IS NOT DISTINCT FROM OLD.cause_change_reason) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('meter correction case %s: a cause change needs its own reason (cause_change_reason, new with every change) — R-19 (v5.4.2-13)', OLD.id),
            ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.enforce_meter_correction_case_record() IS
    'v5.4.2-13 (parity). BEFORE INSERT OR UPDATE on meter_correction_cases, every role: a case opens open; opened_at/by, frozen_at/by and evidence_recorded_at/by are stamped; meter, tenant and opening stamps never change; a withdrawn case never changes; a frozen case changes only by unfreezing, alone; a freeze changes nothing else and pins an evaluation of THIS case computed for its current cause and anchor; a cause change carries a new reason. It judges no law — which causes, directions, transitions and withdrawals are lawful is the calculation core''s.';

DROP TRIGGER IF EXISTS a_enforce_meter_correction_case ON public.meter_correction_cases;
DROP TRIGGER IF EXISTS a_enforce_meter_correction_case_record ON public.meter_correction_cases;
CREATE TRIGGER a_enforce_meter_correction_case_record
    BEFORE INSERT OR UPDATE ON public.meter_correction_cases
    FOR EACH ROW EXECUTE FUNCTION public.enforce_meter_correction_case_record();
ALTER TABLE public.meter_correction_cases ENABLE ALWAYS TRIGGER a_enforce_meter_correction_case_record;

-- The case's event log. Written only by the database — the case's own
-- trigger, the evaluation's, the approval's and the hold's — never directly
-- by the application: tally_app could otherwise write a "gate approved" or
-- "frozen" entry for something that never happened. The fence is trigger
-- depth, sound while tally_app can define no code (-12 residual R10).

CREATE SEQUENCE IF NOT EXISTS public.meter_correction_case_events_seq;
GRANT USAGE, SELECT ON SEQUENCE public.meter_correction_case_events_seq TO tally_app;

CREATE TABLE IF NOT EXISTS public.meter_correction_case_events (
    id              uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id       uuid NOT NULL,
    case_id         uuid NOT NULL,
    event_type      text NOT NULL,
    from_cause      text,
    to_cause        text,
    reason          text,
    evaluation_id   uuid,
    hold_id         uuid,
    actor_id        uuid,
    occurred_at     timestamp with time zone DEFAULT now() NOT NULL,
    event_seq       bigint DEFAULT nextval('public.meter_correction_case_events_seq') NOT NULL,
    metadata        jsonb DEFAULT '{}'::jsonb NOT NULL,
    CONSTRAINT meter_correction_case_events_pkey PRIMARY KEY (id),
    CONSTRAINT meter_correction_case_events_tenant_id_fkey
        FOREIGN KEY (tenant_id) REFERENCES public.tenants(id),
    CONSTRAINT meter_correction_case_events_case_fkey
        FOREIGN KEY (case_id, tenant_id) REFERENCES public.meter_correction_cases(id, tenant_id),
    CONSTRAINT meter_correction_case_events_type_check
        CHECK ((event_type = ANY (ARRAY['opened'::text, 'cause_changed'::text, 'evaluated'::text, 'gate_approved'::text, 'frozen'::text, 'unfrozen'::text, 'withdrawn'::text, 'hold_opened'::text, 'hold_completed'::text, 'hold_unrecoverable'::text])))
);

CREATE INDEX IF NOT EXISTS idx_meter_correction_case_events_tenant ON public.meter_correction_case_events USING btree (tenant_id);
CREATE INDEX IF NOT EXISTS idx_meter_correction_case_events_case ON public.meter_correction_case_events USING btree (case_id, event_seq);

ALTER TABLE public.meter_correction_case_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.meter_correction_case_events FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_isolation ON public.meter_correction_case_events;
CREATE POLICY tenant_isolation ON public.meter_correction_case_events USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));

REVOKE UPDATE, DELETE, TRUNCATE ON public.meter_correction_case_events FROM tally_app;

CREATE OR REPLACE FUNCTION public.enforce_case_events_written_by_database() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
BEGIN
    IF pg_trigger_depth() < 2 THEN
        RAISE EXCEPTION USING
            MESSAGE = 'meter_correction_case_events rows are written only by the database, as the consequence of the act they record — an application-written entry could claim an approval or a freeze that never happened (v5.4.2-13)',
            ERRCODE = 'restrict_violation';
    END IF;
    NEW.occurred_at := now();
    BEGIN
        NEW.actor_id := NULLIF(current_setting('app.user_id', true), '')::uuid;
    EXCEPTION WHEN OTHERS THEN
        NEW.actor_id := NULL;
    END;
    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.enforce_case_events_written_by_database() IS
    'v5.4.2-13. Refuses a direct INSERT into meter_correction_case_events (trigger depth < 2) and stamps occurred_at and actor_id. Sound only while tally_app can define no code of its own.';

DROP TRIGGER IF EXISTS a_enforce_case_events_written_by_database ON public.meter_correction_case_events;
CREATE TRIGGER a_enforce_case_events_written_by_database BEFORE INSERT ON public.meter_correction_case_events
    FOR EACH ROW EXECUTE FUNCTION public.enforce_case_events_written_by_database();
DROP TRIGGER IF EXISTS append_only ON public.meter_correction_case_events;
CREATE TRIGGER append_only BEFORE UPDATE OR DELETE ON public.meter_correction_case_events
    FOR EACH ROW EXECUTE FUNCTION public.enforce_append_only();
DROP TRIGGER IF EXISTS no_truncate ON public.meter_correction_case_events;
CREATE TRIGGER no_truncate BEFORE TRUNCATE ON public.meter_correction_case_events
    FOR EACH STATEMENT EXECUTE FUNCTION public.enforce_no_hard_delete();
ALTER TABLE public.meter_correction_case_events ENABLE ALWAYS TRIGGER a_enforce_case_events_written_by_database;
ALTER TABLE public.meter_correction_case_events ENABLE ALWAYS TRIGGER append_only;
ALTER TABLE public.meter_correction_case_events ENABLE ALWAYS TRIGGER no_truncate;

COMMENT ON TABLE public.meter_correction_case_events IS
    'A-2 (v5.4.2-13). The append-only history of one meter correction case: opened, every cause change with its reason (R-19, R-38), each evaluation, each approval, freeze and unfreeze, withdrawal, and each hold opened and closed. Written only by the database''s own triggers; the actor and clock are stamped. Ordered by event_seq (now() is constant within a transaction).';

CREATE OR REPLACE FUNCTION public.meter_correction_case_after() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO public.meter_correction_case_events (tenant_id, case_id, event_type, to_cause, metadata)
        VALUES (NEW.tenant_id, NEW.id, 'opened', NEW.cause,
                jsonb_build_object('meter_id', NEW.meter_id, 'discovering_test_id', NEW.discovering_test_id,
                                   'anchor_date', NEW.anchor_date, 'anchor_basis', NEW.anchor_basis,
                                   'direction', NEW.direction, 'claimed_from', NEW.claimed_from,
                                   'evidence_kind', NEW.evidence_kind));
        RETURN NULL;
    END IF;
    IF NEW.cause IS DISTINCT FROM OLD.cause THEN
        INSERT INTO public.meter_correction_case_events (tenant_id, case_id, event_type, from_cause, to_cause, reason, metadata)
        VALUES (NEW.tenant_id, NEW.id, 'cause_changed', OLD.cause, NEW.cause, NEW.cause_change_reason,
                jsonb_build_object('anchor_date', NEW.anchor_date, 'direction', NEW.direction,
                                   'evidence_kind', NEW.evidence_kind,
                                   'evidence_service_order_id', NEW.evidence_service_order_id,
                                   'evidence_deployment_id', NEW.evidence_deployment_id,
                                   'evidence_field_report_ref', NEW.evidence_field_report_ref,
                                   'previous_evidence_kind', OLD.evidence_kind));
    END IF;
    IF NEW.status IS DISTINCT FROM OLD.status THEN
        INSERT INTO public.meter_correction_case_events (tenant_id, case_id, event_type, reason, evaluation_id)
        VALUES (NEW.tenant_id, NEW.id,
                CASE NEW.status WHEN 'frozen' THEN 'frozen' WHEN 'withdrawn' THEN 'withdrawn' ELSE 'unfrozen' END,
                CASE WHEN NEW.status = 'withdrawn' THEN NEW.withdrawn_reason END,
                coalesce(NEW.frozen_evaluation_id, OLD.frozen_evaluation_id));
    END IF;
    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS z_meter_correction_case_after ON public.meter_correction_cases;
CREATE TRIGGER z_meter_correction_case_after
    AFTER INSERT OR UPDATE ON public.meter_correction_cases
    FOR EACH ROW EXECUTE FUNCTION public.meter_correction_case_after();
ALTER TABLE public.meter_correction_cases ENABLE ALWAYS TRIGGER z_meter_correction_case_after;


-- ----------------------------------------------------------------------------
-- 9. The evaluation and its per-period evidence (R-25, R-32, R-34…R-38)
-- ----------------------------------------------------------------------------
-- WRITTEN BY THE CALCULATION CORE. An evaluation records what the core
-- decided for a case: the rule row it applied, the window per direction, the
-- governing test, the deployment bound, the utility's limit, whether a
-- supervisor's approval is required, the inputs it computed from and their
-- fingerprint, and the core version that computed it. Its evidence is one row
-- per billed period — never netted (R-25) — with that period's own rule row,
-- window, amount and disposition (included, forfeited, or partly forfeited),
-- and the days and dollars given up.
--
-- How the core computes all of it: application/a2-rules-for-the-core.md.
--
-- WHAT THE DATABASE KEEPS TRUE:
--   * append-only — a re-evaluation is a new row; the latest governs an open
--     case, the frozen one a frozen case, the rest are the audit trail (R-38
--     attachment 1);
--   * an evaluation's evidence is written in the SAME transaction as the
--     evaluation — evidence added later would describe a correction nobody
--     evaluated;
--   * each evidence row is internally consistent: its sign matches its
--     direction, and its forfeited dollars match its disposition;
--   * the rule rows cited exist and never change (section 5);
--   * evaluated_at / evaluated_by and the transaction are stamped.

CREATE SEQUENCE IF NOT EXISTS public.meter_correction_evaluations_seq;
GRANT USAGE, SELECT ON SEQUENCE public.meter_correction_evaluations_seq TO tally_app;

CREATE TABLE IF NOT EXISTS public.meter_correction_evaluations (
    id                              uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id                       uuid NOT NULL,
    case_id                         uuid NOT NULL,
    evaluation_seq                  bigint DEFAULT nextval('public.meter_correction_evaluations_seq') NOT NULL,
    cause                           text NOT NULL,
    anchor_date                     date NOT NULL,
    anchor_basis                    text NOT NULL,
    direction                       text,
    claimed_from                    date,
    rule_id                         uuid NOT NULL,
    governing_test_id               uuid,
    governing_test_date             date,
    governing_record_basis          text,
    governing_entered_out_of_order  boolean,
    prior_test_failed               boolean,
    absence                         text,
    approval_required               boolean NOT NULL,
    deployment_id                   uuid,
    deployment_bound                date,
    adverse_window_start            date,
    favourable_window_start         date,
    tenant_limit_months             integer,
    tenant_limit_start              date,
    inputs                          jsonb NOT NULL,
    inputs_fingerprint              text NOT NULL,
    calculated_by                   text NOT NULL,
    recorded_txid                   bigint NOT NULL DEFAULT txid_current(),
    evaluated_at                    timestamp with time zone DEFAULT now() NOT NULL,
    evaluated_by                    uuid,
    CONSTRAINT meter_correction_evaluations_pkey PRIMARY KEY (id),
    CONSTRAINT meter_correction_evaluations_id_tenant_id_key UNIQUE (id, tenant_id),
    CONSTRAINT meter_correction_evaluations_id_case_key UNIQUE (id, case_id),
    CONSTRAINT meter_correction_evaluations_tenant_id_fkey
        FOREIGN KEY (tenant_id) REFERENCES public.tenants(id),
    CONSTRAINT meter_correction_evaluations_case_fkey
        FOREIGN KEY (case_id, tenant_id) REFERENCES public.meter_correction_cases(id, tenant_id),
    CONSTRAINT meter_correction_evaluations_cause_fkey
        FOREIGN KEY (cause) REFERENCES public.backbilling_causes(cause_code),
    CONSTRAINT meter_correction_evaluations_rule_fkey
        FOREIGN KEY (rule_id) REFERENCES public.backbilling_rules(id),
    CONSTRAINT meter_correction_evaluations_governing_test_fkey
        FOREIGN KEY (governing_test_id, tenant_id) REFERENCES public.meter_tests(id, tenant_id),
    CONSTRAINT meter_correction_evaluations_deployment_fkey
        FOREIGN KEY (deployment_id, tenant_id) REFERENCES public.meter_deployments(id, tenant_id),
    CONSTRAINT meter_correction_evaluations_anchor_basis_check
        CHECK ((anchor_basis = ANY (ARRAY['test_date'::text, 'discovery_date'::text]))),
    CONSTRAINT meter_correction_evaluations_direction_check
        CHECK (((direction IS NULL) OR (direction = ANY (ARRAY['customer_owes'::text, 'customer_owed'::text])))),
    CONSTRAINT meter_correction_evaluations_tenant_limit_check
        CHECK (((tenant_limit_months IS NULL) = (tenant_limit_start IS NULL))
           AND ((tenant_limit_months IS NULL) OR (tenant_limit_months > 0))),
    CONSTRAINT meter_correction_evaluations_inputs_check
        CHECK (((jsonb_typeof(inputs) = 'object'::text) AND (inputs_fingerprint ~ '[[:alnum:]]'::text))),
    CONSTRAINT meter_correction_evaluations_calculated_by_check
        CHECK ((calculated_by ~ '[[:alnum:]]'::text))
);

CREATE INDEX IF NOT EXISTS idx_meter_correction_evaluations_tenant ON public.meter_correction_evaluations USING btree (tenant_id);
CREATE INDEX IF NOT EXISTS idx_meter_correction_evaluations_case ON public.meter_correction_evaluations USING btree (case_id, evaluation_seq DESC);

ALTER TABLE public.meter_correction_evaluations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.meter_correction_evaluations FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_isolation ON public.meter_correction_evaluations;
CREATE POLICY tenant_isolation ON public.meter_correction_evaluations USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));

REVOKE UPDATE, DELETE, TRUNCATE ON public.meter_correction_evaluations FROM tally_app;

-- The case's frozen evaluation, now that the table exists. (The case guard
-- also proves it is this case's, for its current cause and anchor.)
ALTER TABLE public.meter_correction_cases DROP CONSTRAINT IF EXISTS meter_correction_cases_frozen_evaluation_fkey;
ALTER TABLE public.meter_correction_cases ADD CONSTRAINT meter_correction_cases_frozen_evaluation_fkey
    FOREIGN KEY (frozen_evaluation_id, id) REFERENCES public.meter_correction_evaluations(id, case_id);

CREATE OR REPLACE FUNCTION public.enforce_meter_correction_evaluation_record() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_rule_cause text;
BEGIN
    SELECT b.cause INTO v_rule_cause FROM public.backbilling_rules b WHERE b.id = NEW.rule_id;
    IF v_rule_cause IS DISTINCT FROM NEW.cause THEN
        RAISE EXCEPTION USING
            MESSAGE = format('meter correction evaluation: rule %s is a rule for %s, not for the evaluated cause %s (v5.4.2-13)', NEW.rule_id, coalesce(v_rule_cause, '(none)'), NEW.cause),
            ERRCODE = 'check_violation';
    END IF;
    NEW.evaluated_at  := now();
    NEW.recorded_txid := txid_current();
    NEW.evaluation_seq := nextval('public.meter_correction_evaluations_seq');
    BEGIN
        NEW.evaluated_by := NULLIF(current_setting('app.user_id', true), '')::uuid;
    EXCEPTION WHEN OTHERS THEN
        NEW.evaluated_by := NULL;
    END;
    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.enforce_meter_correction_evaluation_record() IS
    'v5.4.2-13 (parity). BEFORE INSERT on meter_correction_evaluations: the cited rule row must be a rule for the evaluated cause; stamps evaluated_at, evaluated_by (session user), evaluation_seq and recorded_txid (the transaction its evidence must be written in). Judges nothing the core computed.';

CREATE OR REPLACE FUNCTION public.meter_correction_evaluation_after() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
BEGIN
    INSERT INTO public.meter_correction_case_events (tenant_id, case_id, event_type, evaluation_id, metadata)
    VALUES (NEW.tenant_id, NEW.case_id, 'evaluated', NEW.id,
            jsonb_build_object('rule_id', NEW.rule_id, 'cause', NEW.cause, 'anchor_date', NEW.anchor_date,
                               'adverse_window_start', NEW.adverse_window_start,
                               'favourable_window_start', NEW.favourable_window_start,
                               'approval_required', NEW.approval_required,
                               'calculated_by', NEW.calculated_by));
    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS a_enforce_meter_correction_evaluation ON public.meter_correction_evaluations;
DROP TRIGGER IF EXISTS a_enforce_meter_correction_evaluation_record ON public.meter_correction_evaluations;
CREATE TRIGGER a_enforce_meter_correction_evaluation_record BEFORE INSERT ON public.meter_correction_evaluations
    FOR EACH ROW EXECUTE FUNCTION public.enforce_meter_correction_evaluation_record();
DROP TRIGGER IF EXISTS append_only ON public.meter_correction_evaluations;
CREATE TRIGGER append_only BEFORE UPDATE OR DELETE ON public.meter_correction_evaluations
    FOR EACH ROW EXECUTE FUNCTION public.enforce_append_only();
DROP TRIGGER IF EXISTS no_truncate ON public.meter_correction_evaluations;
CREATE TRIGGER no_truncate BEFORE TRUNCATE ON public.meter_correction_evaluations
    FOR EACH STATEMENT EXECUTE FUNCTION public.enforce_no_hard_delete();
DROP TRIGGER IF EXISTS z_meter_correction_evaluation_after ON public.meter_correction_evaluations;
CREATE TRIGGER z_meter_correction_evaluation_after AFTER INSERT ON public.meter_correction_evaluations
    FOR EACH ROW EXECUTE FUNCTION public.meter_correction_evaluation_after();
ALTER TABLE public.meter_correction_evaluations ENABLE ALWAYS TRIGGER a_enforce_meter_correction_evaluation_record;
ALTER TABLE public.meter_correction_evaluations ENABLE ALWAYS TRIGGER append_only;
ALTER TABLE public.meter_correction_evaluations ENABLE ALWAYS TRIGGER no_truncate;
ALTER TABLE public.meter_correction_evaluations ENABLE ALWAYS TRIGGER z_meter_correction_evaluation_after;

COMMENT ON TABLE public.meter_correction_evaluations IS
    'A-2 (v5.4.2-13, parity). One evaluation of one meter correction case, written by the calculation core: the rule row applied (rule_id), the window start per direction, the governing test (R-34), the deployment bound (R-37(a)), the utility''s limit (R-37(d)), whether a supervisor''s approval is required (R-36), the inputs document and its fingerprint (R-38: freezing proves the evidence still describes the world), and the core version that computed it (calculated_by). One meter_correction_period_evidence row per billed period, written in the same transaction. Append-only: re-evaluating adds a row; the latest governs an open case, the frozen one a frozen case, the rest are the audit trail.';
COMMENT ON COLUMN public.meter_correction_evaluations.rule_id IS
    'The backbilling_rules row the core resolved for the case (premise state, service type, class, cause, date). Each period''s own rule row is on its evidence row, since occupants and premises differ across a meter''s life (R-37(b)). Rule rows never change, so this citation stays true.';
COMMENT ON COLUMN public.meter_correction_evaluations.approval_required IS
    'The core''s answer to whether a supervisor must approve THIS evaluation before the case may freeze (Texas: R-36''s transitional gate on an adverse correction resting on a date-only migrated test or none). Recorded so a freeze without one is visible (meter_correction_case_status.approval_pending).';
COMMENT ON COLUMN public.meter_correction_evaluations.calculated_by IS
    'The calculation core''s version that computed this evaluation — with inputs and the cited rule rows, what makes it reproducible.';


CREATE TABLE IF NOT EXISTS public.meter_correction_period_evidence (
    id                  uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id           uuid NOT NULL,
    evaluation_id       uuid NOT NULL,
    invoice_id          uuid NOT NULL,
    customer_id         uuid NOT NULL,
    location_id         uuid,
    period_start        date NOT NULL,
    period_end          date NOT NULL,
    billed_units        numeric(14,2),
    customer_class      text NOT NULL,
    rule_id             uuid NOT NULL,
    window_start        date,
    tenant_limit_start  date,
    direction           text NOT NULL,
    correction_amount   numeric(12,2) NOT NULL,
    disposition         text NOT NULL,
    forfeit_reason      text,
    days_in_window      integer NOT NULL,
    forfeited_amount    numeric(12,2) DEFAULT 0.00 NOT NULL,
    CONSTRAINT meter_correction_period_evidence_pkey PRIMARY KEY (id),
    CONSTRAINT meter_correction_period_evidence_period_key UNIQUE (evaluation_id, invoice_id),
    CONSTRAINT meter_correction_period_evidence_tenant_id_fkey
        FOREIGN KEY (tenant_id) REFERENCES public.tenants(id),
    CONSTRAINT meter_correction_period_evidence_evaluation_fkey
        FOREIGN KEY (evaluation_id, tenant_id) REFERENCES public.meter_correction_evaluations(id, tenant_id),
    CONSTRAINT meter_correction_period_evidence_invoice_fkey
        FOREIGN KEY (invoice_id, tenant_id) REFERENCES public.invoices(id, tenant_id),
    CONSTRAINT meter_correction_period_evidence_customer_fkey
        FOREIGN KEY (customer_id, tenant_id) REFERENCES public.customers(id, tenant_id),
    CONSTRAINT meter_correction_period_evidence_location_fkey
        FOREIGN KEY (location_id, tenant_id) REFERENCES public.service_locations(id, tenant_id),
    CONSTRAINT meter_correction_period_evidence_rule_fkey
        FOREIGN KEY (rule_id) REFERENCES public.backbilling_rules(id),
    CONSTRAINT meter_correction_period_evidence_period_check
        CHECK (((period_end >= period_start) AND (days_in_window >= 0)
            AND (days_in_window <= ((period_end - period_start) + 1)))),
    CONSTRAINT meter_correction_period_evidence_direction_check
        CHECK ((direction = ANY (ARRAY['customer_owes'::text, 'customer_owed'::text, 'neutral'::text]))),
    CONSTRAINT meter_correction_period_evidence_sign_check
        CHECK ((((direction = 'customer_owes'::text) AND (correction_amount > (0)::numeric))
             OR ((direction = 'customer_owed'::text) AND (correction_amount < (0)::numeric))
             OR ((direction = 'neutral'::text) AND (correction_amount = (0)::numeric)))),
    CONSTRAINT meter_correction_period_evidence_disposition_check
        CHECK ((disposition = ANY (ARRAY['included'::text, 'forfeited'::text, 'partly_forfeited'::text]))),
    -- What a disposition MEANS for the dollars. Which disposition a period
    -- gets is the rule's (backbilling_rules.adverse_straddle / …) and the
    -- core's; the record must add up either way.
    CONSTRAINT meter_correction_period_evidence_forfeit_check
        CHECK ((((disposition = 'included'::text) AND (forfeit_reason IS NULL) AND (forfeited_amount = (0)::numeric))
             OR ((disposition = 'forfeited'::text) AND (forfeit_reason IS NOT NULL)
                  AND (forfeited_amount = correction_amount) AND (correction_amount <> (0)::numeric))
             OR ((disposition = 'partly_forfeited'::text) AND (forfeit_reason IS NOT NULL)
                  AND (sign(forfeited_amount) = sign(correction_amount))
                  AND (abs(forfeited_amount) > (0)::numeric)
                  AND (abs(forfeited_amount) < abs(correction_amount))))),
    CONSTRAINT meter_correction_period_evidence_forfeit_reason_check
        CHECK (((forfeit_reason IS NULL) OR (forfeit_reason = ANY (ARRAY['straddles_window'::text, 'before_window'::text, 'tenant_limit'::text, 'straddles_claimed_start'::text, 'before_claimed_start'::text]))))
);

CREATE INDEX IF NOT EXISTS idx_meter_correction_period_evidence_tenant ON public.meter_correction_period_evidence USING btree (tenant_id);
CREATE INDEX IF NOT EXISTS idx_meter_correction_period_evidence_invoice ON public.meter_correction_period_evidence USING btree (invoice_id);

ALTER TABLE public.meter_correction_period_evidence ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.meter_correction_period_evidence FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_isolation ON public.meter_correction_period_evidence;
CREATE POLICY tenant_isolation ON public.meter_correction_period_evidence USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));

REVOKE UPDATE, DELETE, TRUNCATE ON public.meter_correction_period_evidence FROM tally_app;

CREATE OR REPLACE FUNCTION public.enforce_period_evidence_with_evaluation() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_txid bigint;
    v_rule record;
BEGIN
    SELECT b.customer_class, b.cause INTO v_rule FROM public.backbilling_rules b WHERE b.id = NEW.rule_id;
    IF v_rule.customer_class IS DISTINCT FROM NEW.customer_class
       OR v_rule.cause IS DISTINCT FROM (SELECT v.cause FROM public.meter_correction_evaluations v WHERE v.id = NEW.evaluation_id) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('meter correction evidence: rule %s is for class %s and cause %s — it must match the period''s class (%s) and the evaluation''s cause (v5.4.2-13)', NEW.rule_id, v_rule.customer_class, v_rule.cause, NEW.customer_class),
            ERRCODE = 'check_violation';
    END IF;
    SELECT v.recorded_txid INTO v_txid
      FROM public.meter_correction_evaluations v
     WHERE v.id = NEW.evaluation_id;
    IF v_txid IS DISTINCT FROM txid_current() THEN
        RAISE EXCEPTION USING
            MESSAGE = format('meter correction evidence: evaluation %s was recorded in an earlier transaction; its evidence is complete — evidence added later would describe a correction nobody evaluated (v5.4.2-13)', NEW.evaluation_id),
            ERRCODE = 'restrict_violation',
            HINT = 'Record a new evaluation, with its evidence, in one transaction.';
    END IF;
    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.enforce_period_evidence_with_evaluation() IS
    'v5.4.2-13 (parity). BEFORE INSERT on meter_correction_period_evidence: the cited rule must be for this period''s class and the evaluation''s cause, and the row must be written in the same transaction as its evaluation (evaluations.recorded_txid). Once that transaction commits, the evaluation''s evidence is closed.';

DROP TRIGGER IF EXISTS a_enforce_period_evidence_written_by_evaluation ON public.meter_correction_period_evidence;
DROP TRIGGER IF EXISTS a_enforce_period_evidence_with_evaluation ON public.meter_correction_period_evidence;
CREATE TRIGGER a_enforce_period_evidence_with_evaluation BEFORE INSERT ON public.meter_correction_period_evidence
    FOR EACH ROW EXECUTE FUNCTION public.enforce_period_evidence_with_evaluation();
DROP TRIGGER IF EXISTS append_only ON public.meter_correction_period_evidence;
CREATE TRIGGER append_only BEFORE UPDATE OR DELETE ON public.meter_correction_period_evidence
    FOR EACH ROW EXECUTE FUNCTION public.enforce_append_only();
DROP TRIGGER IF EXISTS no_truncate ON public.meter_correction_period_evidence;
CREATE TRIGGER no_truncate BEFORE TRUNCATE ON public.meter_correction_period_evidence
    FOR EACH STATEMENT EXECUTE FUNCTION public.enforce_no_hard_delete();
ALTER TABLE public.meter_correction_period_evidence ENABLE ALWAYS TRIGGER a_enforce_period_evidence_with_evaluation;
ALTER TABLE public.meter_correction_period_evidence ENABLE ALWAYS TRIGGER append_only;
ALTER TABLE public.meter_correction_period_evidence ENABLE ALWAYS TRIGGER no_truncate;

COMMENT ON TABLE public.meter_correction_period_evidence IS
    'A-2 (v5.4.2-13, parity). One row per billed period an evaluation judged — direction per original billing period, never netted (R-25). Carries the period''s own customer class and rule row (occupants and premises differ across a meter''s life, R-37(b)), its window, the amount, and the disposition: included, forfeited (all of it) or partly_forfeited (proration, where the rule allows it), with the reason, the days inside the window and the dollars given up — "so the cost is visible rather than silent" (R-32). What collection may pursue is the cited rule''s enforce_scope (F-1). Written by the core in the evaluation''s own transaction; append-only.';
COMMENT ON COLUMN public.meter_correction_period_evidence.days_in_window IS
    'Days of this period on or after the start that governs it (its window, the utility''s limit, or the claimed start — whichever is latest and applies); the full period length where none applies. On a forfeited or partly forfeited row, the days that were billable.';


-- ----------------------------------------------------------------------------
-- 10. Approvals (R-36)
-- ----------------------------------------------------------------------------
-- The record that a person approved ONE evaluation. Whether an approval is
-- required (evaluations.approval_required), and who may give it — a
-- supervisor, not the case's opener or the evaluation's author — is the
-- core's (Ryan, 2026-09-28: control-flavoured, but policy). The database
-- stamps who and when, ties the approval to an evaluation of the same case,
-- and never lets it change: re-evaluate and the approval does not carry over.

CREATE TABLE IF NOT EXISTS public.meter_correction_approvals (
    id              uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id       uuid NOT NULL,
    case_id         uuid NOT NULL,
    evaluation_id   uuid NOT NULL,
    note            text NOT NULL,
    approved_by     uuid,
    approved_at     timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT meter_correction_approvals_pkey PRIMARY KEY (id),
    CONSTRAINT meter_correction_approvals_evaluation_key UNIQUE (evaluation_id),
    CONSTRAINT meter_correction_approvals_tenant_id_fkey
        FOREIGN KEY (tenant_id) REFERENCES public.tenants(id),
    CONSTRAINT meter_correction_approvals_case_fkey
        FOREIGN KEY (case_id, tenant_id) REFERENCES public.meter_correction_cases(id, tenant_id),
    CONSTRAINT meter_correction_approvals_evaluation_fkey
        FOREIGN KEY (evaluation_id, tenant_id) REFERENCES public.meter_correction_evaluations(id, tenant_id),
    CONSTRAINT meter_correction_approvals_same_case_fkey
        FOREIGN KEY (evaluation_id, case_id) REFERENCES public.meter_correction_evaluations(id, case_id),
    CONSTRAINT meter_correction_approvals_note_check
        CHECK ((note ~ '[[:alnum:]]'::text))
);

CREATE INDEX IF NOT EXISTS idx_meter_correction_approvals_tenant ON public.meter_correction_approvals USING btree (tenant_id);

ALTER TABLE public.meter_correction_approvals ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.meter_correction_approvals FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_isolation ON public.meter_correction_approvals;
CREATE POLICY tenant_isolation ON public.meter_correction_approvals USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));

REVOKE UPDATE, DELETE, TRUNCATE ON public.meter_correction_approvals FROM tally_app;

CREATE OR REPLACE FUNCTION public.enforce_meter_correction_approval_record() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
BEGIN
    NEW.approved_at := now();
    BEGIN
        NEW.approved_by := NULLIF(current_setting('app.user_id', true), '')::uuid;
    EXCEPTION WHEN OTHERS THEN
        NEW.approved_by := NULL;
    END;
    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.enforce_meter_correction_approval_record() IS
    'v5.4.2-13 (parity). BEFORE INSERT on meter_correction_approvals: approved_by is the session''s user and approved_at the database clock — never caller-set. Whether the approver was allowed to approve is the core''s check.';

CREATE OR REPLACE FUNCTION public.meter_correction_approval_after() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
BEGIN
    INSERT INTO public.meter_correction_case_events (tenant_id, case_id, event_type, reason, evaluation_id)
    VALUES (NEW.tenant_id, NEW.case_id, 'gate_approved', NEW.note, NEW.evaluation_id);
    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS a_enforce_meter_correction_approval ON public.meter_correction_approvals;
DROP TRIGGER IF EXISTS a_enforce_meter_correction_approval_record ON public.meter_correction_approvals;
CREATE TRIGGER a_enforce_meter_correction_approval_record BEFORE INSERT ON public.meter_correction_approvals
    FOR EACH ROW EXECUTE FUNCTION public.enforce_meter_correction_approval_record();
DROP TRIGGER IF EXISTS append_only ON public.meter_correction_approvals;
CREATE TRIGGER append_only BEFORE UPDATE OR DELETE ON public.meter_correction_approvals
    FOR EACH ROW EXECUTE FUNCTION public.enforce_append_only();
DROP TRIGGER IF EXISTS no_truncate ON public.meter_correction_approvals;
CREATE TRIGGER no_truncate BEFORE TRUNCATE ON public.meter_correction_approvals
    FOR EACH STATEMENT EXECUTE FUNCTION public.enforce_no_hard_delete();
DROP TRIGGER IF EXISTS z_meter_correction_approval_after ON public.meter_correction_approvals;
CREATE TRIGGER z_meter_correction_approval_after AFTER INSERT ON public.meter_correction_approvals
    FOR EACH ROW EXECUTE FUNCTION public.meter_correction_approval_after();
ALTER TABLE public.meter_correction_approvals ENABLE ALWAYS TRIGGER a_enforce_meter_correction_approval_record;
ALTER TABLE public.meter_correction_approvals ENABLE ALWAYS TRIGGER append_only;
ALTER TABLE public.meter_correction_approvals ENABLE ALWAYS TRIGGER no_truncate;
ALTER TABLE public.meter_correction_approvals ENABLE ALWAYS TRIGGER z_meter_correction_approval_after;

COMMENT ON TABLE public.meter_correction_approvals IS
    'A-2 (v5.4.2-13, parity), R-36. A person''s approval of ONE evaluation of the same case. Does not carry over to a re-evaluation. approved_by / approved_at stamped from the session. Whether approval was required and whether this approver qualified (a supervisor, not the opener or the evaluator) is the calculation core''s. Append-only.';


-- ----------------------------------------------------------------------------
-- 11. Holds (R-37(c))
-- ----------------------------------------------------------------------------
-- The record of a stretch of a correction deferred because Tally holds no
-- bill for it: legacy_records_not_loaded (before the utility's cutover) or
-- predecessor_records_unavailable (before it acquired the premise). Whether a
-- hold is allowed — the cause and direction, the stretch really unbilled, the
-- dates before cutover or acquisition — and whether it may close as
-- unrecoverable, are the core's.
--
-- The database keeps the record: one code, the acquisition named exactly for
-- a predecessor hold, no two open holds of a case over the same day, opened
-- and closed stamps, a hold closes once (open → completed | unrecoverable)
-- and never changes after, an unrecoverable closure names its artifact.

CREATE TABLE IF NOT EXISTS public.meter_correction_holds (
    id                      uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id               uuid NOT NULL,
    case_id                 uuid NOT NULL,
    range_start             date NOT NULL,
    range_end               date NOT NULL,
    hold_code               text NOT NULL,
    acquisition_id          uuid,
    status                  text DEFAULT 'open'::text NOT NULL,
    closure_artifact_ref    text,
    counsel_referral        boolean DEFAULT false NOT NULL,
    opened_at               timestamp with time zone DEFAULT now() NOT NULL,
    opened_by               uuid,
    closed_at               timestamp with time zone,
    closed_by               uuid,
    CONSTRAINT meter_correction_holds_pkey PRIMARY KEY (id),
    CONSTRAINT meter_correction_holds_tenant_id_fkey
        FOREIGN KEY (tenant_id) REFERENCES public.tenants(id),
    CONSTRAINT meter_correction_holds_case_fkey
        FOREIGN KEY (case_id, tenant_id) REFERENCES public.meter_correction_cases(id, tenant_id),
    CONSTRAINT meter_correction_holds_acquisition_fkey
        FOREIGN KEY (acquisition_id, tenant_id) REFERENCES public.service_location_acquisitions(id, tenant_id),
    CONSTRAINT meter_correction_holds_range_check CHECK ((range_end >= range_start)),
    CONSTRAINT meter_correction_holds_code_check
        CHECK ((hold_code = ANY (ARRAY['legacy_records_not_loaded'::text, 'predecessor_records_unavailable'::text]))),
    CONSTRAINT meter_correction_holds_acquisition_check
        CHECK (((hold_code = 'predecessor_records_unavailable'::text) = (acquisition_id IS NOT NULL))),
    CONSTRAINT meter_correction_holds_status_check
        CHECK ((status = ANY (ARRAY['open'::text, 'completed'::text, 'unrecoverable'::text]))),
    CONSTRAINT meter_correction_holds_closed_check
        CHECK (((status = 'open'::text) = (closed_at IS NULL))),
    CONSTRAINT meter_correction_holds_unrecoverable_check
        CHECK (((status <> 'unrecoverable'::text) OR (coalesce(closure_artifact_ref, ''::text) ~ '[[:alnum:]]'::text)))
);

CREATE INDEX IF NOT EXISTS idx_meter_correction_holds_tenant ON public.meter_correction_holds USING btree (tenant_id);

-- No two holds of a case cover the same day — except a COMPLETED one, whose
-- days are covered by bills, not by the hold (review round 1, Opus): if those
-- bills are later voided the days need holding again.
ALTER TABLE public.meter_correction_holds DROP CONSTRAINT IF EXISTS meter_correction_holds_no_overlap;
ALTER TABLE public.meter_correction_holds ADD CONSTRAINT meter_correction_holds_no_overlap
    EXCLUDE USING gist (case_id WITH =, daterange(range_start, range_end, '[]') WITH &&)
    WHERE ((status <> 'completed'::text));

ALTER TABLE public.meter_correction_holds ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.meter_correction_holds FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_isolation ON public.meter_correction_holds;
CREATE POLICY tenant_isolation ON public.meter_correction_holds USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));

REVOKE DELETE, TRUNCATE ON public.meter_correction_holds FROM tally_app;

CREATE OR REPLACE FUNCTION public.enforce_meter_correction_hold_record() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_user uuid;
    c_close_cols CONSTANT text[] := ARRAY['status', 'closure_artifact_ref', 'counsel_referral', 'closed_at', 'closed_by'];
BEGIN
    BEGIN
        v_user := NULLIF(current_setting('app.user_id', true), '')::uuid;
    EXCEPTION WHEN OTHERS THEN
        v_user := NULL;
    END;
    IF TG_OP = 'INSERT' THEN
        IF NEW.status <> 'open' THEN
            RAISE EXCEPTION USING
                MESSAGE = format('meter correction hold: a hold is opened open, not %s (v5.4.2-13)', NEW.status),
                ERRCODE = 'check_violation';
        END IF;
        NEW.opened_at := now();
        NEW.opened_by := v_user;
        NEW.closed_at := NULL;
        NEW.closed_by := NULL;
        RETURN NEW;
    END IF;
    IF OLD.status <> 'open' THEN
        RAISE EXCEPTION USING
            MESSAGE = format('meter correction hold %s is closed (%s); a closed hold never changes (v5.4.2-13)', OLD.id, OLD.status),
            ERRCODE = 'restrict_violation';
    END IF;
    IF NEW.status = 'open' OR (to_jsonb(NEW) - c_close_cols) <> (to_jsonb(OLD) - c_close_cols) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('meter correction hold %s: an open hold changes only by closing (completed or unrecoverable), and a closure changes nothing else (v5.4.2-13)', OLD.id),
            ERRCODE = 'restrict_violation';
    END IF;
    NEW.closed_at := now();
    NEW.closed_by := v_user;
    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.enforce_meter_correction_hold_record() IS
    'v5.4.2-13 (parity). BEFORE INSERT OR UPDATE on meter_correction_holds, every role: a hold opens open, stamped; it changes only by closing once (completed or unrecoverable), stamped, with nothing else changing; a closed hold never changes. Whether a hold or an unrecoverable closure is allowed is the core''s.';

DROP TRIGGER IF EXISTS a_enforce_meter_correction_hold ON public.meter_correction_holds;
DROP TRIGGER IF EXISTS a_enforce_meter_correction_hold_record ON public.meter_correction_holds;
CREATE TRIGGER a_enforce_meter_correction_hold_record BEFORE INSERT OR UPDATE ON public.meter_correction_holds
    FOR EACH ROW EXECUTE FUNCTION public.enforce_meter_correction_hold_record();
ALTER TABLE public.meter_correction_holds ENABLE ALWAYS TRIGGER a_enforce_meter_correction_hold_record;
DROP TRIGGER IF EXISTS no_hard_delete ON public.meter_correction_holds;
CREATE TRIGGER no_hard_delete BEFORE DELETE ON public.meter_correction_holds
    FOR EACH ROW EXECUTE FUNCTION public.enforce_no_hard_delete();
DROP TRIGGER IF EXISTS no_truncate ON public.meter_correction_holds;
CREATE TRIGGER no_truncate BEFORE TRUNCATE ON public.meter_correction_holds
    FOR EACH STATEMENT EXECUTE FUNCTION public.enforce_no_hard_delete();

CREATE OR REPLACE FUNCTION public.meter_correction_hold_after() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
BEGIN
    INSERT INTO public.meter_correction_case_events (tenant_id, case_id, event_type, hold_id, reason, metadata)
    VALUES (NEW.tenant_id, NEW.case_id,
            CASE WHEN TG_OP = 'INSERT' THEN 'hold_opened'
                 WHEN NEW.status = 'completed' THEN 'hold_completed'
                 ELSE 'hold_unrecoverable' END,
            NEW.id, NEW.closure_artifact_ref,
            jsonb_build_object('hold_code', NEW.hold_code, 'range_start', NEW.range_start,
                               'range_end', NEW.range_end, 'counsel_referral', NEW.counsel_referral));
    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS z_meter_correction_hold_after ON public.meter_correction_holds;
CREATE TRIGGER z_meter_correction_hold_after AFTER INSERT OR UPDATE ON public.meter_correction_holds
    FOR EACH ROW EXECUTE FUNCTION public.meter_correction_hold_after();
ALTER TABLE public.meter_correction_holds ENABLE ALWAYS TRIGGER z_meter_correction_hold_after;

COMMENT ON TABLE public.meter_correction_holds IS
    'A-2 (v5.4.2-13, parity), R-37(c). The record of a stretch of a correction deferred because Tally holds no bill for it: legacy_records_not_loaded or predecessor_records_unavailable (naming the acquisition). Opens open; closes once, as completed or unrecoverable (naming its artifact); never changes after. No two non-completed holds of a case overlap. Whether a hold, or an unrecoverable closure, is allowed is the calculation core''s (a supervisor, the counsel flag, the dates — application/a2-rules-for-the-core.md).';

-- ----------------------------------------------------------------------------
-- 12. The freeze — folded into section 8 (a frozen case changes only by
--     unfreezing; it pins an evaluation of itself). What must be true BEFORE
--     a freeze (coverage, a current fingerprint, a required approval) is the
--     core's: application/a2-rules-for-the-core.md.
-- ----------------------------------------------------------------------------

-- ----------------------------------------------------------------------------
-- 13. The test-history couplings (-12 residual R7)
-- ----------------------------------------------------------------------------
-- -12 recorded three facts for this patch to act on. Two are the core's now:
-- R-36's supervisor_gate (the core computes the gate from the resolved rule;
-- residual R8) and D-5's entered_out_of_order (a late test changes the
-- governing test, which the core's fingerprint catches). The third is record
-- integrity and stays: "a test an evidence row cites cannot be superseded
-- silently" (brief §3.6). A test a FROZEN case rests on, as its discovering
-- test or its frozen evaluation's governing test, cannot be superseded until
-- the case is unfrozen. Unfreeze, correct the test, re-evaluate, freeze: the
-- old window stays beside the new in the evaluations.

CREATE OR REPLACE FUNCTION public.enforce_test_supersession_vs_frozen_case() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_case uuid;
BEGIN
    IF NEW.supersedes_test_id IS NULL THEN
        RETURN NEW;
    END IF;
    -- Wait behind any freeze in flight on this meter's cases (round 1, both
    -- reviewers: a supersession committed between a freeze's check and its
    -- commit, and the case froze on a corrected test). The freeze holds its
    -- case row; this reads the cases FOR SHARE, so it sees the freeze once
    -- committed. This trigger fires before -12's meter lock, so the order is
    -- always the meter's cases, then the meter (round 2).
    PERFORM 1 FROM public.meter_correction_cases mc
      WHERE mc.tenant_id = NEW.tenant_id AND mc.meter_id = NEW.meter_id
        FOR SHARE;
    SELECT mc.id INTO v_case
      FROM public.meter_correction_cases mc
      LEFT JOIN public.meter_correction_evaluations v ON v.id = mc.frozen_evaluation_id
     WHERE mc.tenant_id = NEW.tenant_id
       AND mc.status = 'frozen'
       AND (mc.discovering_test_id = NEW.supersedes_test_id
            OR v.governing_test_id = NEW.supersedes_test_id)
     LIMIT 1;
    IF v_case IS NOT NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('meter test %s is cited by the frozen meter correction case %s — correcting it would change a window the frozen evidence rests on (CI-091 brief §3.6; R-38)', NEW.supersedes_test_id, v_case),
            ERRCODE = 'restrict_violation',
            HINT = 'Unfreeze the case (status = open), record the correcting test, re-evaluate and freeze again.';
    END IF;
    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.enforce_test_supersession_vs_frozen_case() IS
    'v5.4.2-13 (-12 residual R7; CI-091 brief §3.6). BEFORE INSERT on meter_tests: a row that supersedes a test a FROZEN meter correction case rests on — its discovering test, or its frozen evaluation''s governing test — is refused until the case is unfrozen.';

-- Named a0_ so it fires BEFORE -12's a_enforce_meter_test_record (round 2,
-- both reviewers): that trigger locks the meter row, and taking the case lock
-- after it inverted the order of a transaction that locks a case and then
-- records a test on its meter — a detected deadlock. Every path now takes
-- the meter's cases before the meter. ('0' sorts before '_'.)
DROP TRIGGER IF EXISTS b_enforce_test_supersession_vs_frozen_case ON public.meter_tests;
DROP TRIGGER IF EXISTS a0_enforce_test_supersession_vs_frozen_case ON public.meter_tests;
CREATE TRIGGER a0_enforce_test_supersession_vs_frozen_case BEFORE INSERT ON public.meter_tests
    FOR EACH ROW EXECUTE FUNCTION public.enforce_test_supersession_vs_frozen_case();
ALTER TABLE public.meter_tests ENABLE ALWAYS TRIGGER a0_enforce_test_supersession_vs_frozen_case;


-- ----------------------------------------------------------------------------

-- ----------------------------------------------------------------------------
-- 14. Read surfaces over the records
-- ----------------------------------------------------------------------------
-- Invoker-rights views: each tenant sees only its own rows. The governing
-- evaluation of a case is its frozen one if frozen, else its latest. These
-- read what was recorded; they compute no law. (r7's view of fast findings
-- with no case read "a fast meter owes a refund" — law — and is the core's
-- surface now: application/a2-rules-for-the-core.md.)

DROP VIEW IF EXISTS public.meter_fast_findings_without_case;
DROP VIEW IF EXISTS public.meter_correction_case_status;
CREATE VIEW public.meter_correction_case_status
    WITH (security_invoker = true) AS
SELECT mc.id AS case_id,
       mc.tenant_id,
       mc.meter_id,
       mc.cause,
       mc.direction,
       mc.anchor_date,
       mc.status,
       gov.id AS governing_evaluation_id,
       gov.evaluation_seq,
       gov.rule_id,
       gov.adverse_window_start,
       gov.favourable_window_start,
       gov.calculated_by,
       EXISTS (SELECT 1 FROM public.meter_tests s WHERE s.supersedes_test_id = mc.discovering_test_id) AS discovering_test_superseded,
       (gov.approval_required
        AND NOT EXISTS (SELECT 1 FROM public.meter_correction_approvals a WHERE a.evaluation_id = gov.id)) AS approval_pending,
       gov.prior_test_failed,
       gov.governing_entered_out_of_order,
       (SELECT count(*) FROM public.meter_correction_holds h
         WHERE h.case_id = mc.id AND h.status = 'open') AS open_holds,
       (SELECT coalesce(sum(p.forfeited_amount), 0) FROM public.meter_correction_period_evidence p
         WHERE p.evaluation_id = gov.id) AS forfeited_amount
  FROM public.meter_correction_cases mc
  LEFT JOIN LATERAL (
        SELECT v.* FROM public.meter_correction_evaluations v
         WHERE v.case_id = mc.id
           AND (mc.frozen_evaluation_id IS NULL OR v.id = mc.frozen_evaluation_id)
         ORDER BY v.evaluation_seq DESC LIMIT 1) gov ON true;

COMMENT ON VIEW public.meter_correction_case_status IS
    'A-2 (v5.4.2-13, parity). One row per meter correction case, from its governing evaluation (frozen, else latest): the rule row applied, the windows, the core version, whether the discovering test has since been superseded, whether a required approval is missing (approval_pending — visible even on a frozen case), open holds and the dollars forfeited. Whether an evaluation still describes the world is the core''s fingerprint check. Invoker rights.';

DROP VIEW IF EXISTS public.backbilling_forfeitures;
CREATE VIEW public.backbilling_forfeitures
    WITH (security_invoker = true) AS
SELECT mc.id AS case_id,
       mc.tenant_id,
       mc.meter_id,
       mc.cause,
       mc.status AS case_status,
       p.evaluation_id,
       p.rule_id,
       p.invoice_id,
       p.customer_id,
       p.location_id,
       p.period_start,
       p.period_end,
       p.disposition,
       p.forfeit_reason,
       p.window_start,
       p.tenant_limit_start,
       p.days_in_window,
       p.forfeited_amount
  FROM public.meter_correction_cases mc
  JOIN LATERAL (
        SELECT v.id FROM public.meter_correction_evaluations v
         WHERE v.case_id = mc.id
           AND (mc.frozen_evaluation_id IS NULL OR v.id = mc.frozen_evaluation_id)
         ORDER BY v.evaluation_seq DESC LIMIT 1) gov ON true
  JOIN public.meter_correction_period_evidence p ON p.evaluation_id = gov.id
 WHERE p.disposition IN ('forfeited', 'partly_forfeited');

COMMENT ON VIEW public.backbilling_forfeitures IS
    'A-2 (v5.4.2-13, parity), R-32 / R-37(d). Every billed period a case''s governing evaluation forfeited in whole or in part, with the rule row, the reason, the days inside the window and the dollars given up. "So the cost is visible rather than silent." Invoker rights.';

DROP VIEW IF EXISTS public.meter_correction_open_holds;
CREATE VIEW public.meter_correction_open_holds
    WITH (security_invoker = true) AS
SELECT h.id AS hold_id,
       h.tenant_id,
       h.case_id,
       mc.meter_id,
       h.range_start,
       h.range_end,
       h.hold_code,
       h.acquisition_id,
       h.opened_at,
       h.opened_by,
       (CURRENT_DATE - h.opened_at::date) AS days_open
  FROM public.meter_correction_holds h
  JOIN public.meter_correction_cases mc ON mc.id = h.case_id
 WHERE h.status = 'open';

COMMENT ON VIEW public.meter_correction_open_holds IS
    'A-2 (v5.4.2-13, parity), R-37(c). The standing surface of open holds — corrections deferred because Tally holds no bill for the stretch. Invoker rights.';

REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.meter_correction_case_status, public.backbilling_forfeitures, public.meter_correction_open_holds FROM tally_app;
GRANT SELECT ON public.meter_correction_case_status, public.backbilling_forfeitures, public.meter_correction_open_holds TO tally_app;

-- A-23 note: no function in this patch is SECURITY DEFINER.
GRANT EXECUTE ON FUNCTION public.session_is_supervisor() TO tally_app;


-- ----------------------------------------------------------------------------
-- 15. Residuals, stated
-- ----------------------------------------------------------------------------
-- R1. NOTHING POSTS. A frozen case charges and refunds nobody until -14
--     builds delivery on Kyle's OQ-1 (backbilling_rules.delivery_path =
--     'unruled' for most causes says so).
--
-- R2. STATE-LEVEL RULES ONLY. R-26's city level (a city with original rate
--     authority overriding the state rule) waits for the shared places table
--     (GBM application/jurisdictions-shared-place-modelling-2026-09-22.md);
--     it then adds place_id to backbilling_rules and the key. No Texas city
--     override is seeded today (Ryan, 2026-09-28).
--
-- R3. WHICH DATE PICKS THE RULE ROW — each period's start, the anchor, or the
--     correction date — is for Kyle. The schema stores the answer either way:
--     every evidence row cites its own rule row.
--
-- R4. THE CLASS-MODE NAMES ARE TEXAS-SHAPED. tenants.regulatory_class_mode's
--     values describe the Texas residential / small-commercial line. They are
--     generalised with the CCK-4…CCK-13 resolver patch (Ryan, 2026-09-28).
--
-- R5. THE DATABASE NO LONGER DECIDES LAWFULNESS. An application that writes
--     an evaluation the rules do not support, freezes a case whose required
--     approval is missing, or reissues a bill under a cause that may not
--     travel that way is not refused here — by design (Ryan, 2026-09-28).
--     The records show it: every evaluation cites its rule rows and core
--     version, approval_pending stays visible, and the event log is the
--     database's. The core's rules and their scenarios are in
--     application/a2-rules-for-the-core.md.
--
-- R6. ONLY TEXAS GAS IS SEEDED. A premise in another state, or another
--     service type, has no rule row; the core must refuse, never fall back.
--
-- R7. A LAW ROW IS NEVER EDITED — for the owner too. A row superseded by a
--     later text is closed (effective_to) and a successor added. A row wrong
--     from its first day is repaired by a reviewed platform migration that
--     disables the history trigger for that statement: rare by intent, and
--     visible in the migration history.
--
-- R8. -12's meter_governing_test() still computes R-36's supervisor_gate with
--     Texas's six months written in (-12:1615). A-2 no longer reads it; the
--     core computes the gate from the resolved rule. Retiring the column is
--     follow-up work on -12 (audit §3.3).

--
-- R9. FOR KYLE: THE UNPROTECTED CLASS. r7 keyed the fast-meter refund duty
--     (R-37) and the tamper gate (R-38 attachment 2) on the cause name, so
--     both reached every customer class; r7 also bounded every case's period
--     set by the PROTECTED window (its R5). The rows here follow the law as
--     ruled in R-20: §7.45 does not reach the unprotected class, so its rows
--     are uncapped, the refund is permitted rather than mandatory, and the
--     tamper move is ungated. Whether Kyle wants either duty extended to
--     unprotected accounts as policy is a question for him; the answer is a
--     row change, not a schema change.

-- ----------------------------------------------------------------------------
-- 16. The AC-32 tail
-- ----------------------------------------------------------------------------
-- Six new tenant tables and three views, each born leaky by the default
-- grants. The assertion raises if any lacks RLS, FORCE, the single canonical
-- policy, or invoker rights. The four law tables carry no tenant_id and are
-- read-only to tally_app.

SELECT public.assert_tenant_isolation_invariants();

-- ============================================================================
-- END PATCH v5.4.2-13
-- ============================================================================
