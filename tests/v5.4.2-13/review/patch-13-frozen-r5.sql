-- ============================================================================
-- PATCH v5.4.2-13 — backbilling caps: how far back §7.45 lets a correction
--                    reach, the meter correction case that carries it, and
--                    the evidence that makes the answer defensible
--                    (schema-parity-plan Phase 4 Wave 3, item A-2)
-- ============================================================================
-- Authority:   Kyle's A-2 rulings R-19…R-31 (closed 2026-09-14), R-32…R-36
--              (GBM application/kyle-decisions-2026-09-22-a2-straddle-and-
--              meter-test-anchor.md) and R-37…R-39 with erratum E-1
--              (kyle-decisions-2026-09-23-a2-override-and-cause-freeze.md);
--              the customer-class-keying record CCK-1…CCK-14; the
--              consolidation GBM application/a2-implementation-brief-
--              2026-09-21.md. Statutory basis is 16 TAC §7.45, re-fetched and
--              read in full by Kyle on 2026-09-22 and again on 2026-09-23.
--              NOTHING in this patch is a fresh reading of the rule.
--
--              Builds on v5.4.2-12 (the meter test history, AC-33): the
--              governing test comes from meter_governing_test(), never from
--              meters.last_test_date (R-34); tenants.cutover_date is the
--              boundary R-36's gate and R-37's legacy hold both read.
--
--              Ryan, 2026-09-22: ship the CCK-14 protection default only;
--              DB-stamped homes for decisions, never app-written logs;
--              narrow first. Ryan, 2026-09-23: the meter correction case as
--              the object that carries a metering correction (below).
--
-- The rule, in one sentence: when a test finds a meter more than 2% off,
-- §7.45(7)(B)(v)(I) sets how far back its readings may be corrected — no
-- further than six months or the previous test, whichever is shorter — and
-- where the meter ran FAST the correction back to that point is a duty, not
-- an option.
--
-- ----------------------------------------------------------------------------
-- Why the shape changed from the round-1 draft
-- ----------------------------------------------------------------------------
--
--   The round-1 draft hung everything on correction_run_targets — the void-
--   and-reissue path. Kyle's R-33 takes meter-error corrections OFF that path
--   (an adjustment on a subsequent bill, not a reissued invoice: "a bill
--   computed wrong is not the same as a meter that measured wrong"), and
--   R-37(b) makes the correction follow the METER's readings across every
--   deployment and every occupant, not one account's invoices. So the
--   correction gets its own record: meter_correction_cases, one per finding
--   about one meter, tied to the test that made the finding.
--
--   HOW THE MONEY REACHES A BILL IS NOT HERE. Which object delivers each
--   cause's correction (an adjustment line, a monetary adjustment to a
--   departed customer, or a reissued invoice) is Kyle's open question OQ-1
--   (GBM application/kyle-brief-2026-09-23-oq1-correction-delivery.md), and
--   his record puts it ahead of the delivery DDL. R-38's freeze does not
--   depend on the answer. So this patch opens, evaluates, holds and FREEZES
--   a case; posting it is v5.4.2-14. A frozen case charges nobody.
--
--   R-38 attachment 4, stated as the ruling asks: R-38's freeze at evidence-
--   freeze is CONSISTENT with R-19. R-19 requires the cap to re-evaluate on
--   every cause change; re-evaluating is exactly what unfreezing and
--   re-freezing a case does. R-38 supersedes R-19's literal freeze point
--   (post) and enforces its intent.
--
--   R-37 amends R-22 and R-27: the under-reach duty is NOT overridable in the
--   customer-favourable direction. The round-1 draft's override reason codes
--   (no_read_history, meter_replaced, records_predate_acquisition) are gone;
--   a computed deployment bound, meter-scoped targeting and a two-code,
--   date-validated hold replace them.
--
-- ----------------------------------------------------------------------------
-- The shapes this patch exists to avoid (each has cost this project once)
-- ----------------------------------------------------------------------------
--
--   A NULLABLE NUMBER WHERE NULL MEANS SOMETHING (R-20, F-7): both bounds on
--   a cap row are explicit enums with the month count present exactly under
--   the counted variants.
--
--   A GUARD THAT RECORDS ITS ENFORCEMENT INSTEAD OF PERFORMING IT: the round-1
--   trim wrote "forfeited" and issued the bill at the full delta. R-32 removes
--   the trim; a forfeited period is now excluded from the case's included set
--   by the same row that records it, and that set is what -14 may post.
--
--   A CALLER-CHOSEN INPUT CHOOSING THE RULE: for the metering causes the
--   database derives the anchor, its basis and the direction from the test
--   that found the fault; the governing test from the history; the deployment
--   bound from deployments recorded before the fault was first on record; the
--   billing periods from the invoices. The caller supplies the cause (a
--   finding, gated where it lifts protection), the dollar figure per period
--   (sign-checked, never zero on a billed period of a test finding), and
--   nothing else that moves the window — with one stated exception: a
--   deployment history fabricated BEFORE the fault is first recorded is not
--   caught by any date (residual R6).
--
--   A LABEL STANDING IN FOR AN ACT: a reissued bill that charges more for a
--   period already billed is a backbilling correction whatever its
--   invoice_type says (round 1), and a "rate misapplication" that bills
--   different units is not one (R-39's definition, checked mechanically).
--
--   AN APP-WRITTEN LOG STANDING IN FOR A GUARD'S FACT: every decision a gate
--   reads is a database-stamped column or a trigger-written row.
--
-- ----------------------------------------------------------------------------
-- What lands
-- ----------------------------------------------------------------------------
--
--    1. TENANT SETTINGS. regulatory_class_mode (CCK-14; PLATFORM-SET, because
--       leaving the default removes §7.45 protection from a class of
--       customers) and backbilling_adverse_limit_months (R-37(d); tenant-set,
--       can only shorten the adverse side). Both logged.
--    2. SUPERVISORS. A tenant_admin is this patch's supervisor. Only a
--       supervisor makes a supervisor (the -12 section 1b guard, extended).
--    3. COMPOSITE KEYS and the service_locations.jurisdiction_id repair.
--    4. DEPLOYMENTS MADE TRUSTWORTHY ENOUGH TO BOUND A WINDOW (R-37(a); -12
--       residual R3): meter, location and install date immutable; removal
--       write-once; created_at stamped.
--    5. THE CAP TABLE (R-20, R-26, R-39): eight causes, platform-held — a
--       tenant reads its rows and cannot write them.
--    6. THE VOID-AND-REISSUE PATH NARROWED (R-33, R-39): correction_run_
--       targets.backbill_cause admits rate_misapplication only; an upward
--       rebill must be one, with the original's usage quantities.
--    7. PREDECESSOR ACQUISITIONS (R-37(c)), per service location.
--    8. THE CASE (R-19, R-37(b), R-38, R-39) with its trigger-written event
--       log and the tamper gate.
--    9. THE EVALUATION AND ITS PER-PERIOD EVIDENCE (R-25, R-32, R-34…R-37):
--       the window, the forfeitures, the enforceable bound per period.
--   10. THE R-36 SUPERVISOR APPROVAL, bound to one evaluation.
--   11. HOLDS (R-37(c)): two codes, system-validated, closable only as ruled.
--   12. THE FREEZE (R-38): cause, anchor and evidence together, refused on
--       stale inputs, unapproved weak provenance, or uncovered in-window days.
--   13. THE TEST-HISTORY COUPLINGS -12 left to this patch (its R7).
--   14. STANDING SURFACES: forfeitures, open holds, case status, and fast
--       findings no case rests on.
--   15. Residuals, and the AC-32 tail.
--
-- ----------------------------------------------------------------------------
-- What is deliberately NOT here
-- ----------------------------------------------------------------------------
--
--   Posting a case (OQ-1): the adjustment or monetary-adjustment object, F-1's
--   non-disconnectable flag carried onto the posted charge, R-38 attachment
--   3's supplemental adjustment and protection re-determination. The case
--   records each period's enforceable bound so -14 has the fact.
--   unbilled_service as a case cause — it has no earlier bill, so R-32's
--   billing period does not exist for it; in the OQ-1 brief.
--   estimation_catchup and the R-30 read classification that serves it — no
--   path in this patch carries that cause, so the mapping would be dead code.
--   The CCK volumetric resolver (CCK-4…CCK-13); collections behaviour on the
--   enforceable bound (Family 9); the correction-run setup surface (UI).
--   Deriving the correction AMOUNT from the test's error figure — the method
--   is not ruled; the caller supplies it and the database checks its sign.
--
-- ----------------------------------------------------------------------------
-- Review round 1 (Fable + Opus, frozen a00683c5), folded in this revision
-- ----------------------------------------------------------------------------
--
--   Both reviewers, independently:
--   * The freeze / unfreeze / withdraw branches returned before the fence on
--     derived columns, so one statement could flip a fast case's direction
--     to a charge, freeze it, or free it for withdrawal. The fence now runs
--     first, and a status change may carry nothing but its own stamps.
--   * A case froze on a discovering test already corrected to accurate: the
--     supersession was not an input. It is now; evaluation and freeze
--     refuse it, and a correction of a test waits on the meter's cases so a
--     freeze in flight cannot slip past (two-session race, both orders).
--   * A fast meter's refund could be entered as 0.00 on every period and
--     frozen. Refused on a billed period of a test finding.
--   * The reissue gate matched only the exact period at the same location;
--     a one-day shift, a spanning bill, another premise or a consolidated
--     bill re-billed voided days. It now matches overlapping days by premise
--     or by a meter the two bills share.
--   * The deployment evidence was forgeable (Opus: re-point the case at a
--     fresh copy of its test and the "recorded before the finding" filter
--     moves; Fable: the application could insert whole closed deployments).
--     The fence is now the moment the fault was FIRST on record, and the
--     application cannot insert a deployment already removed. Acquisitions
--     behind a predecessor hold are fenced the same way.
--   One reviewer each:
--   * Opus: a fast test "corrected" to a faster reading freed its case for
--     withdrawal. Withdrawal now reads the latest row of the test's chain.
--   * Opus: a hold completed by bills later voided still counted, and
--     blocked re-holding the days. Completed holds cover nothing and do not
--     exclude.
--   * Opus: a fast and a slow test on the same day could both stand and a
--     case cite the slow one. Opposite same-day findings must be corrected
--     before either is cited. And a surface for fast findings with no case.
--   * Fable: a predecessor removed years ago corroborated every later
--     meter's onboarding-date start. It must have served into the window.
--   * Fable: two live cases could rest on one test (it would post twice).
--     One live case per discovering test.
--   * LOW, both: R6 and R15 overclaimed; R-36's scope is stated for Kyle
--     (R18); the class is read as of now (R19); meter_deployments' own links
--     are tenant-blind (R20); hold completion now locks the case.
--
-- Review round 2 (Fable + Opus, frozen 9844fc48): every round-1 fix held
-- against both reviewers' own repros; siblings folded here:
--   * Both: a removal is a later write on an old row, its date is the
--     caller's, and meters.status passes one through sync_meter_
--     deployments() — pull the fast meter after its test, backdated, and the
--     unbilled stretch read as a gap. removal_recorded_at is stamped; a
--     removal recorded after the finding does not count for it.
--   * Both: the reissue gate compared whole bills of different scope — a
--     consolidated bill carrying the voided meter at the same price was
--     refused, and one with no lines and no premise got through. It now
--     compares at the scope it matched, with a customer leg for bills with
--     no premise. Per-day proration was proposed and declined (dilution).
--   * Both: round 1's FOR SHARE handshake deadlocked a "lock a case, then
--     record a test on its meter" transaction. The trigger now fires before
--     -12's, so cases are always locked before the meter.
--   * Opus (LOW): unknown (NULL) usage no longer admits a zero correction.
--   * Fable: R6 now names the meters-only route to a pre-finding fabricated
--     history; R15, R16 and R21 reworded to what is true.
--
-- Review round 4 (Fable + Opus, frozen ea35e6bb): the round-3 fixes held;
-- both found siblings in the whole-versus-meter split, all folded here:
--   * Fable: meter scope keyed on "another premise" read the header, so the
--     customer's other premise on the header re-opened round 3's leak. Meter
--     scope now needs a new bill with NO premise.
--   * Opus: a no-premise bill carried the extra on a second meter AT the
--     voided premise; Fable: or on any meter id at all, another tenant's
--     included. Both now count on the new side.
--   * Opus: the R-39 units test read only the replaced bill; a correction
--     addressed to another premise increased against that premise's voided
--     bill with other units. It now reads every voided bill it exceeds.
--
-- Review round 3 (Fable + Opus, frozen d991df92): the removal stamp, the
-- lock order and the NULL-usage zero held against every route both tried;
-- both found the same two holes in round 2's scoped reissue comparison:
--   * Meter scope at the SAME premise let the extra ride on another meter's
--     line or on a meterless line. The same premise (or the named bill) now
--     compares whole charges; meterless lines count as unattributed money.
--   * "More than EVERY matched voided bill" let one higher voided bill — a
--     mis-keyed duplicate, or a decoy issued beside the live bill — excuse a
--     rebill of its neighbour's days. Now "more than ANY" (cost in R21).
--   * Fable (LOW): a removal written in the test's own transaction tied with
--     it; application-recorded removals must now be strictly before the
--     fence. R15 names the trigger-order invariant.
--
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 1. Tenant settings (CCK-14, R-37(d))
-- ----------------------------------------------------------------------------
-- regulatory_class_mode: §7.45 protects residential and small commercial
-- customers. CCK-14's default sweeps every non-residential account in, which
-- is correct for any tenant whose filed tariff has no size tier and fails
-- toward protection. explicit_class trusts customers.customer_type;
-- volumetric_threshold is DECLARED so the CCK patch widens no CHECK and is
-- REFUSED by the resolver until its substrate exists.
--
-- PLATFORM-SET. Moving off the default takes protection away from customers
-- — and with it the mandatory refund reach R-37 says no tenant setting may
-- shorten. That is the cutover date's reasoning (-12 section 3), so it gets
-- the cutover date's answer: tally_app may change it only as a platform
-- administrator. A tenant INSERT may carry it (onboarding).
--
-- backbilling_adverse_limit_months: R-37(d). A tenant MAY bill customers for
-- less far back than the statute allows — (v)(I) expressly permits foregoing
-- a correction to the utility's disadvantage — and this is also where a
-- tenant's own filed-tariff backbilling limit is expressed. It can never
-- lengthen anything: the window is a MAX() of start dates and this is one
-- more candidate, so it can only move the adverse start later. It NEVER
-- applies in the customer-favourable direction. NULL means no tenant limit —
-- the statutory bound governs alone, which is the lawful maximum and not a
-- fail-open: a NULL here can reach no further than the statute already does.
-- Every period it excludes writes a forfeiture row (section 9).

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
    'CCK-14 (A-2, v5.4.2-13). How this tenant decides whether an account is inside 16 TAC §7.45''s protected class (residential and small commercial). all_non_residential_protected (default, v1): every non-residential account is in scope — correct for any tenant whose filed tariff has no size tier, and fails toward protection. explicit_class: trust the size tier on customers.customer_type. volumetric_threshold: the CCK-4…CCK-13 resolver, DECLARED so that patch widens no CHECK and REFUSED by backbilling_customer_class() until its substrate exists. PLATFORM-SET: leaving the default removes protection, including the mandatory refund reach R-37 says no tenant setting may shorten. Logged in tenant_configuration_history.';

COMMENT ON COLUMN public.tenants.backbilling_adverse_limit_months IS
    'R-37(d) (A-2, v5.4.2-13). An optional limit, in months back from a correction''s anchor, on how far this tenant bills customers for UNDER-billing — shorter than the statute, never longer (it is one more candidate in the MAX() of start dates, so it can only move the start later). Never applies to money owed TO a customer. Also where a tenant''s own filed-tariff backbilling limit is expressed. Every period it excludes is recorded as a forfeiture (R-32). NULL = no tenant limit: the statutory bound governs alone. Tenant-set; logged in tenant_configuration_history.';

CREATE OR REPLACE FUNCTION public.enforce_tenant_regulatory_class_mode() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
BEGIN
    IF current_user = 'tally_app'
       AND NEW.regulatory_class_mode IS DISTINCT FROM OLD.regulatory_class_mode
       AND NOT public.is_platform_admin() THEN
        RAISE EXCEPTION USING
            MESSAGE = format('tenant %s: regulatory_class_mode is platform-set — moving it off the default removes 16 TAC §7.45 protection from a class of customers, including the mandatory refund reach no tenant setting may shorten (R-37; v5.4.2-13)', OLD.id),
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
-- UNIQUE (id, tenant_id): jurisdictions (the cap rows resolve through one)
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
    'The premise''s jurisdiction (D5-2, v5.4.0-03) — through which WNA applicability, the WNA tariff variant and (since v5.4.2-13) the §7.45 backbilling cap resolve. Composite on jurisdictions(id, tenant_id) since v5.4.2-13 (one of the 229 links in GBM application/tenant-blind-foreign-keys-2026-09-22.md, repaired here because A-2 resolves a statutory cap through it). Nullable: population is an onboarding concern.';


-- ----------------------------------------------------------------------------
-- 4. Deployments trustworthy enough to bound a window (R-37(a); -12 R3)
-- ----------------------------------------------------------------------------
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
--     fences it is the next rule and section 9's evidence fence;
--   * the moment a removal is RECORDED is stamped (removal_recorded_at), so
--     a removal written after a finding cannot excuse that finding's days
--     or corroborate its shorter refund, whatever date it claims (round 2);
--   * meter_id, location_id and install_date never change. A deployment
--     entered wrong is a data repair, not an edit.
--   * removal_date and removal_reason are written once, NULL to a value.
--   * created_at is the database's clock. The evaluation (section 9) reads
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
-- (section 9) compares that moment, not the row's creation, and a removal
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
-- 5. The cap table (R-20, R-26, R-39, F-7) — platform-held
-- ----------------------------------------------------------------------------
-- Two bounds per row, because R-20 found the billable and enforceable limits
-- diverge: for a non-registering meter three months may be BILLED and none
-- of it may ever be ENFORCED. Both are explicit non-null enums with the
-- month count present exactly under the counted variants.
--
-- PLATFORM-HELD. The round-1 draft let a tenant edit its own rows — and so
-- change its six-month meter_error row to 'uncapped'. These rows are a
-- reading of the statute, like -12's accuracy threshold, and get the same
-- answer: tally_app reads them and cannot write them. A tenant's own shorter
-- limit lives in tenants.backbilling_adverse_limit_months (R-37(d)); a
-- municipal row (R-26) is written by the platform on the evidence of an
-- ordinance or filed instrument. Rows stay per tenant because jurisdictions
-- are per tenant.
--
-- R-39's eight causes; no 'other' — every cause must resolve to a cited row,
-- and 'other' resolves to nothing. tampering_theft is renamed
-- tampering_bypass: "theft" is a criminal conclusion a billing operator
-- should not write onto a customer record.

CREATE TABLE IF NOT EXISTS public.backbilling_cap_rules (
    id                  uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id           uuid NOT NULL,
    jurisdiction_id     uuid,
    service_type        text NOT NULL,
    customer_class      text NOT NULL,
    cause               text NOT NULL,
    billable_scope      text NOT NULL,
    billable_months     integer,
    enforceable_scope   text NOT NULL,
    enforceable_months  integer,
    source_note         text NOT NULL,
    created_at          timestamp with time zone DEFAULT now() NOT NULL,
    updated_at          timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT backbilling_cap_rules_pkey PRIMARY KEY (id),
    CONSTRAINT backbilling_cap_rules_id_tenant_id_key UNIQUE (id, tenant_id),
    -- NULLS NOT DISTINCT so two conflicting state-default rows cannot both
    -- exist and make resolution nondeterministic (R-26 refinement 1).
    CONSTRAINT backbilling_cap_rules_key UNIQUE NULLS NOT DISTINCT
        (tenant_id, jurisdiction_id, service_type, customer_class, cause),
    CONSTRAINT backbilling_cap_rules_tenant_id_fkey
        FOREIGN KEY (tenant_id) REFERENCES public.tenants(id),
    CONSTRAINT backbilling_cap_rules_jurisdiction_fkey
        FOREIGN KEY (jurisdiction_id, tenant_id)
        REFERENCES public.jurisdictions(id, tenant_id),
    CONSTRAINT backbilling_cap_rules_service_type_check
        CHECK ((service_type = ANY (ARRAY['water'::text, 'sewer'::text, 'electric'::text, 'gas'::text, 'stormwater'::text, 'trash'::text, 'reclaimed_water'::text]))),
    CONSTRAINT backbilling_cap_rules_customer_class_check
        CHECK ((customer_class = ANY (ARRAY['protected'::text, 'unprotected'::text]))),
    CONSTRAINT backbilling_cap_rules_cause_check
        CHECK ((cause = ANY (ARRAY['meter_error'::text, 'non_registering_meter'::text, 'rate_misapplication'::text, 'estimation_catchup'::text, 'tampering_bypass'::text, 'billing_constant_error'::text, 'crossed_meters'::text, 'unbilled_service'::text]))),
    CONSTRAINT backbilling_cap_rules_billable_scope_check
        CHECK ((billable_scope = ANY (ARRAY['uncapped'::text, 'months_from_anchor'::text, 'shorter_of_months_or_last_test'::text]))),
    CONSTRAINT backbilling_cap_rules_enforceable_scope_check
        CHECK ((enforceable_scope = ANY (ARRAY['uncapped'::text, 'months'::text, 'never'::text, 'conditional_on_read_classification'::text]))),
    -- Equivalences, not one-way implications: a one-way rule lets an
    -- uncounted variant carry a stray integer that reads as a limit nobody
    -- applies.
    CONSTRAINT backbilling_cap_rules_billable_months_check
        CHECK ((((billable_scope = ANY (ARRAY['months_from_anchor'::text, 'shorter_of_months_or_last_test'::text])) AND (billable_months IS NOT NULL) AND (billable_months > 0))
             OR ((billable_scope = 'uncapped'::text) AND (billable_months IS NULL)))),
    CONSTRAINT backbilling_cap_rules_enforceable_months_check
        CHECK ((((enforceable_scope = 'months'::text) AND (enforceable_months IS NOT NULL) AND (enforceable_months > 0))
             OR ((enforceable_scope <> 'months'::text) AND (enforceable_months IS NULL)))),
    -- R-21: every row says where its numbers come from.
    CONSTRAINT backbilling_cap_rules_source_note_check
        CHECK ((source_note ~ '[[:alnum:]]'::text))
);

CREATE INDEX IF NOT EXISTS idx_backbilling_cap_rules_tenant ON public.backbilling_cap_rules USING btree (tenant_id);
CREATE INDEX IF NOT EXISTS idx_backbilling_cap_rules_resolve ON public.backbilling_cap_rules USING btree (tenant_id, service_type, customer_class, cause);

ALTER TABLE public.backbilling_cap_rules ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.backbilling_cap_rules FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_isolation ON public.backbilling_cap_rules;
CREATE POLICY tenant_isolation ON public.backbilling_cap_rules USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));

REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.backbilling_cap_rules FROM tally_app;

DROP TRIGGER IF EXISTS set_updated_at ON public.backbilling_cap_rules;
CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.backbilling_cap_rules FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();

COMMENT ON TABLE public.backbilling_cap_rules IS
    'A-2 (v5.4.2-13). How far back 16 TAC §7.45 lets a correction BILL, and separately how far back collection may be ENFORCED, per (jurisdiction, service type, customer class, cause). Two bounds because R-20 found they diverge. Resolution is most-specific-wins over exactly two levels (R-26): the service location''s jurisdiction, else the NULL-jurisdiction state / filed-tariff default. R-39''s eight causes; no other. PLATFORM-HELD: tally_app reads and cannot write — a tenant able to edit its own statutory row could uncap it. A tenant''s own shorter limit is tenants.backbilling_adverse_limit_months (R-37(d)). Seeded by seed_backbilling_cap_defaults() for Texas gas, both classes; an unprotected row is written explicitly uncapped rather than left absent, so a missing rule is an error, never a permission.';

COMMENT ON COLUMN public.backbilling_cap_rules.jurisdiction_id IS
    'R-26. NULL is the state / filed-tariff default row, not "unknown". The UNIQUE carries NULLS NOT DISTINCT so two conflicting defaults cannot coexist.';
COMMENT ON COLUMN public.backbilling_cap_rules.customer_class IS
    'Whether the account is inside §7.45''s protected class, resolved by backbilling_customer_class() from tenants.regulatory_class_mode (CCK-14) — a finding about an account, not a stored attribute.';
COMMENT ON COLUMN public.backbilling_cap_rules.billable_scope IS
    'F-7. uncapped = no §7.45 billing limit for this cause. months_from_anchor = billable_months back from the anchor — (7)(B)(v)(II). shorter_of_months_or_last_test = the later of (anchor - billable_months) and the governing prior test''s date — (7)(B)(v)(I). R-37(a) adds the start of the meter''s deployments to either counted scope.';
COMMENT ON COLUMN public.backbilling_cap_rules.enforceable_scope IS
    'R-20. How far back collection may be pursued on what was billed. never = billed but never enforceable — the (4)(E)(vi) outcome for the metering causes, and R-39''s default for its three additions pending counsel. conditional_on_read_classification = estimation_catchup, resolved from the contemporaneous read record (R-30) when that cause gets a path. Recorded per evidence period; carried onto the posted charge by v5.4.2-14 (F-1).';
COMMENT ON COLUMN public.backbilling_cap_rules.source_note IS
    'The clause these numbers come from. Required: R-21 rejected inheriting meter_error''s six months for estimation_catchup as an uncited number.';

-- The Texas gas seed rows (R-20's table amended by R-39), as
-- NULL-jurisdiction defaults. A function rather than a one-shot INSERT so
-- onboarding can seed a tenant created after this patch. Idempotent. Run by
-- the owner — tally_app cannot write the table, so it cannot call this.

CREATE OR REPLACE FUNCTION public.seed_backbilling_cap_defaults(p_tenant_id uuid)
    RETURNS integer
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_inserted integer;
    c_unprotected CONSTANT text := '16 TAC 7.45 does not reach this class; ordinary limitations law and the filed tariff govern, outside this table.';
BEGIN
    INSERT INTO public.backbilling_cap_rules
        (tenant_id, jurisdiction_id, service_type, customer_class, cause,
         billable_scope, billable_months, enforceable_scope, enforceable_months, source_note)
    VALUES
    -- PROTECTED — residential and small commercial, the §7.45 class.
        (p_tenant_id, NULL, 'gas', 'protected', 'meter_error',
         'shorter_of_months_or_last_test', 6, 'never', NULL,
         '16 TAC 7.45(7)(B)(v)(I) — the shorter of the last six months and the last test of the meter, from the test (R-34: the most recent completed test before it); (4)(E)(vi) bars disconnection for an underbilling due to faulty metering.'),
        (p_tenant_id, NULL, 'gas', 'protected', 'non_registering_meter',
         'months_from_anchor', 3, 'never', NULL,
         '16 TAC 7.45(7)(B)(v)(II) — a charge for units used but not metered for a period not to exceed three months; (4)(E)(vi) bars disconnection.'),
        (p_tenant_id, NULL, 'gas', 'protected', 'rate_misapplication',
         'uncapped', NULL, 'months', 6,
         '16 TAC 7.45(4)(E)(v) — no billing cap on correcting a misapplied rate; (3)(C)(iii) bounds enforcement at six months.'),
        (p_tenant_id, NULL, 'gas', 'protected', 'estimation_catchup',
         'uncapped', NULL, 'conditional_on_read_classification', NULL,
         'No 7.45 billing cap on an estimation catch-up; (6)(C) governs estimation and (4)(E)(vii) enforcement, turning on whether the missed read was beyond the utility''s control. R-21 rejected inheriting meter_error''s six months here.'),
        (p_tenant_id, NULL, 'gas', 'protected', 'tampering_bypass',
         'uncapped', NULL, 'uncapped', NULL,
         '16 TAC 7.45(4)(D)(v) — tampering with or bypassing the meter sits outside the backbilling limits; the (4)(E)(vi) bar does not apply where the meter has been tampered with (R-39 renamed from tampering_theft).'),
        (p_tenant_id, NULL, 'gas', 'protected', 'billing_constant_error',
         'uncapped', NULL, 'never', NULL,
         'R-39: no 7.45 billing cap; enforceable classification (faulty metering, misapplied rate, or neither) referred to counsel — never pending, per fail-toward-protection.'),
        (p_tenant_id, NULL, 'gas', 'protected', 'crossed_meters',
         'uncapped', NULL, 'never', NULL,
         'R-39: no 7.45 billing cap; enforceable classification referred to counsel — never pending, per fail-toward-protection.'),
        (p_tenant_id, NULL, 'gas', 'protected', 'unbilled_service',
         'uncapped', NULL, 'never', NULL,
         'R-39: no 7.45 billing cap; enforceable classification referred to counsel — never pending, per fail-toward-protection.'),
    -- UNPROTECTED — written explicitly, so a missing rule stays an error.
    -- Under v1's default mode nothing resolves to this class.
        (p_tenant_id, NULL, 'gas', 'unprotected', 'meter_error',            'uncapped', NULL, 'uncapped', NULL, c_unprotected),
        (p_tenant_id, NULL, 'gas', 'unprotected', 'non_registering_meter',  'uncapped', NULL, 'uncapped', NULL, c_unprotected),
        (p_tenant_id, NULL, 'gas', 'unprotected', 'rate_misapplication',    'uncapped', NULL, 'uncapped', NULL, c_unprotected),
        (p_tenant_id, NULL, 'gas', 'unprotected', 'estimation_catchup',     'uncapped', NULL, 'uncapped', NULL, c_unprotected),
        (p_tenant_id, NULL, 'gas', 'unprotected', 'tampering_bypass',       'uncapped', NULL, 'uncapped', NULL, c_unprotected),
        (p_tenant_id, NULL, 'gas', 'unprotected', 'billing_constant_error', 'uncapped', NULL, 'uncapped', NULL, c_unprotected),
        (p_tenant_id, NULL, 'gas', 'unprotected', 'crossed_meters',         'uncapped', NULL, 'uncapped', NULL, c_unprotected),
        (p_tenant_id, NULL, 'gas', 'unprotected', 'unbilled_service',       'uncapped', NULL, 'uncapped', NULL, c_unprotected)
    ON CONFLICT ON CONSTRAINT backbilling_cap_rules_key DO NOTHING;
    GET DIAGNOSTICS v_inserted = ROW_COUNT;
    RETURN v_inserted;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.seed_backbilling_cap_defaults(uuid) FROM tally_app;

COMMENT ON FUNCTION public.seed_backbilling_cap_defaults(uuid) IS
    'A-2 (v5.4.2-13). Seeds one tenant''s Texas GAS cap defaults (R-20 amended by R-39) as NULL-jurisdiction rows for both classes. Idempotent. Onboarding (the owner) must call it — tally_app can neither write the table nor execute this, and a tenant with no rules cannot evaluate a correction, because resolution fails closed. Texas-only launch scope.';

DO $$
DECLARE r record; v_total integer := 0; v_tenants integer := 0;
BEGIN
    FOR r IN SELECT id FROM public.tenants LOOP
        v_total := v_total + public.seed_backbilling_cap_defaults(r.id);
        v_tenants := v_tenants + 1;
    END LOOP;
    RAISE NOTICE 'v5.4.2-13: seeded % backbilling cap rule(s) across % tenant(s); onboarding must call seed_backbilling_cap_defaults() for tenants created after this patch', v_total, v_tenants;
END;
$$;


-- ----------------------------------------------------------------------------
-- 5b. The resolvers: which class, and which cap row (CCK-14, R-26)
-- ----------------------------------------------------------------------------
-- Invoker rights; each reads tenant-scoped tables under RLS.

CREATE OR REPLACE FUNCTION public.backbilling_customer_class(p_customer_id uuid)
    RETURNS text
    LANGUAGE plpgsql
    STABLE
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_mode text;
    v_type text;
BEGIN
    SELECT t.regulatory_class_mode, c.customer_type
      INTO v_mode, v_type
      FROM public.customers c
      JOIN public.tenants t ON t.id = c.tenant_id
     WHERE c.id = p_customer_id;

    IF v_mode IS NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('backbilling class: customer %s is not visible in this session', p_customer_id),
            ERRCODE = 'no_data_found';
    END IF;

    IF v_mode = 'volumetric_threshold' THEN
        RAISE EXCEPTION USING
            MESSAGE = 'backbilling class: regulatory_class_mode = volumetric_threshold is not implemented — its resolver and determination record (CCK-4…CCK-13) ship in their own patch',
            ERRCODE = 'feature_not_supported',
            HINT = 'The platform sets tenants.regulatory_class_mode; all_non_residential_protected is the v1 default.';
    END IF;

    IF v_mode = 'all_non_residential_protected' THEN
        RETURN 'protected';
    END IF;

    -- explicit_class. A bare 'commercial' is ambiguous on the size-tier axis
    -- and reads as protected, the safe direction.
    RETURN CASE
        WHEN v_type IN ('residential', 'small_commercial', 'commercial') THEN 'protected'
        ELSE 'unprotected'
    END;
END;
$$;

COMMENT ON FUNCTION public.backbilling_customer_class(uuid) IS
    'A-2 (v5.4.2-13), CCK-14. Whether this customer sits inside 16 TAC §7.45''s protected class, per tenants.regulatory_class_mode. Under the v1 default always protected. Under explicit_class a bare commercial reads as protected. volumetric_threshold RAISES rather than silently behaving like the default.';

CREATE OR REPLACE FUNCTION public.backbilling_resolve_cap(
        p_tenant_id       uuid,
        p_jurisdiction_id uuid,
        p_service_type    text,
        p_customer_class  text,
        p_cause           text)
    RETURNS public.backbilling_cap_rules
    LANGUAGE plpgsql
    STABLE
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_rule public.backbilling_cap_rules;
BEGIN
    SELECT r.* INTO v_rule
      FROM public.backbilling_cap_rules r
     WHERE r.tenant_id      = p_tenant_id
       AND r.service_type   = p_service_type
       AND r.customer_class = p_customer_class
       AND r.cause          = p_cause
       AND (r.jurisdiction_id = p_jurisdiction_id OR r.jurisdiction_id IS NULL)
     ORDER BY (r.jurisdiction_id IS NULL)      -- the specific row sorts first
     LIMIT 1;

    IF v_rule.id IS NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('backbilling cap: no rule for (service %s, class %s, cause %s) in this tenant — a correction cannot be evaluated against a cap that is not configured', p_service_type, p_customer_class, p_cause),
            ERRCODE = 'no_data_found',
            HINT = 'Onboarding (the owner) runs SELECT public.seed_backbilling_cap_defaults(<tenant_id>); only Texas gas is seeded.';
    END IF;
    RETURN v_rule;
END;
$$;

COMMENT ON FUNCTION public.backbilling_resolve_cap(uuid, uuid, text, text, text) IS
    'A-2 (v5.4.2-13), R-26. The governing cap row, most-specific-wins over exactly two levels: the jurisdiction, else the NULL-jurisdiction default. RAISES where none resolves — an absent rule is never permission.';


-- ----------------------------------------------------------------------------
-- 6. The void-and-reissue path, narrowed (R-33, R-39)
-- ----------------------------------------------------------------------------
-- R-33: a meter error is corrected by an adjustment on a subsequent bill,
-- NOT by voiding and reissuing. Void-and-reissue stays correct where the
-- bill itself was computed wrong. Of R-39's causes, Kyle placed exactly one
-- on this path: rate_misapplication ("correct units, wrong price"). The
-- rest wait on OQ-1, so the column admits that one value. Narrow first:
-- widening a CHECK is one line.
--
-- The column is nullable. A reissue with no cause is a clerical re-issue,
-- and the gate below lets it only REDUCE or hold what is charged.
--
-- THE GATE ASKS WHAT THE BILL DOES, NOT WHAT IT IS CALLED (round 1). A bill
-- that charges more for days already billed — an overlapping period, at the
-- same premise or on a meter the earlier bill also billed — on a bill since
-- voided is a backbilling correction whatever its invoice_type or header.
-- Known cost (review round 1): after a void, an ordinary bill that spans the
-- voided period and a new one charges more than the voided bill alone and is
-- refused; bill the voided period as its own correction. It may
-- proceed only as a correction on a correction run, whose target records
-- rate_misapplication — AND whose line items bill the same usage quantities,
-- per meter, as the bill it replaces. That second test is R-39's definition
-- checked mechanically: without it, "rate_misapplication" is a label anyone
-- can type to take a metering correction past its window, which is the
-- keyed-on-a-label defect round 1 found, one level up.
--
-- "Charges more" is measured by backbilling_invoice_charge() — the greater
-- of the line-item sum and amount_due — on BOTH sides. Two fields are both
-- the money and nothing ties them (residual R9): the lines are the itemised
-- content, amount_due is what posts to the ledger. Round 2's open question
-- was which measure the PRIOR side needs. Answered here: the same one. The
-- greater of a voided bill's two figures is what that customer was exposed
-- to (void_invoice reverses exactly amount_due, and the lines are what the
-- bill showed); measuring the prior side by the lesser would call every
-- reissue of an amount_due-less legacy bill an increase — the corpus the
-- earlier batteries build — and buys no protection, since the new side is
-- already measured at its greatest.

ALTER TABLE public.correction_run_targets
    ADD COLUMN IF NOT EXISTS backbill_cause text;

ALTER TABLE public.correction_run_targets DROP CONSTRAINT IF EXISTS correction_run_targets_backbill_cause_check;
ALTER TABLE public.correction_run_targets ADD CONSTRAINT correction_run_targets_backbill_cause_check
    CHECK (((backbill_cause IS NULL) OR (backbill_cause = 'rate_misapplication'::text)));

COMMENT ON COLUMN public.correction_run_targets.backbill_cause IS
    'R-19 / R-33 / R-39 (A-2, v5.4.2-13). The statutory cause of a void-and-reissue correction. Admits rate_misapplication only: R-33 moves meter errors to an adjustment on a subsequent bill (meter_correction_cases), and where every other cause travels is Kyle''s OQ-1. NULL is a clerical re-issue, which may only reduce or hold the charge. A rate_misapplication reissue that charges more must bill the replaced bill''s usage quantities, meter by meter (R-39: correct units, wrong price). Frozen with the rest of the election once a calculation snapshot exists.';

CREATE OR REPLACE FUNCTION public.backbilling_invoice_charge(p_invoice_id uuid)
    RETURNS numeric
    LANGUAGE sql
    STABLE
    SET search_path = public, pg_temp
    AS $$
    SELECT greatest(
             (SELECT coalesce(sum(l.amount), 0) FROM public.invoice_line_items l
               WHERE l.invoice_id = p_invoice_id),
             (SELECT coalesce(i.amount_due, 0) FROM public.invoices i
               WHERE i.id = p_invoice_id)
           )::numeric(12,2);
$$;

COMMENT ON FUNCTION public.backbilling_invoice_charge(uuid) IS
    'A-2 (v5.4.2-13). What this invoice can charge the customer, by either path: the GREATER of its line-item sum and its amount_due. Both are the money and nothing ties them (residual R9); reading either alone was the round-1 defect and its mirror. Used on both sides of "does this reissue charge more".';

-- R-39's "correct units": per meter (a line with no meter is its own
-- group), the summed usage_quantity, gas_ccf_used and gas_therms_billed of
-- the two bills are identical. Therms are included because a wrong BTU
-- factor is a billing_constant_error, not a price error.
CREATE OR REPLACE FUNCTION public.backbilling_units_match(p_original uuid, p_correction uuid)
    RETURNS boolean
    LANGUAGE sql
    STABLE
    SET search_path = public, pg_temp
    AS $$
    WITH a AS (
        SELECT coalesce(l.meter_id::text, '-') AS k,
               sum(l.usage_quantity) AS q, sum(l.gas_ccf_used) AS c, sum(l.gas_therms_billed) AS t
          FROM public.invoice_line_items l WHERE l.invoice_id = p_original GROUP BY 1),
         b AS (
        SELECT coalesce(l.meter_id::text, '-') AS k,
               sum(l.usage_quantity) AS q, sum(l.gas_ccf_used) AS c, sum(l.gas_therms_billed) AS t
          FROM public.invoice_line_items l WHERE l.invoice_id = p_correction GROUP BY 1)
    SELECT NOT EXISTS (
        SELECT 1 FROM a FULL JOIN b ON a.k = b.k
         WHERE a.k IS NULL OR b.k IS NULL
            OR a.q IS DISTINCT FROM b.q
            OR a.c IS DISTINCT FROM b.c
            OR a.t IS DISTINCT FROM b.t);
$$;

COMMENT ON FUNCTION public.backbilling_units_match(uuid, uuid) IS
    'A-2 (v5.4.2-13), R-39. True when two bills bill the same usage, meter by meter: summed usage_quantity, gas_ccf_used and gas_therms_billed identical per meter_id (a meter present on one bill only is a mismatch). The mechanical form of rate_misapplication''s definition — correct units, wrong price.';

CREATE OR REPLACE FUNCTION public.enforce_backbilling_gate_issue() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_new_charge   numeric;
    v_new_excess   numeric;
    v_new_part     numeric;
    v_old_part     numeric;
    v_prior_charge numeric;
    v_matched      boolean := false;
    v_increase     boolean := false;
    v_other_increased uuid[] := ARRAY[]::uuid[];
    v_other        uuid;
    r              record;
    v_t            record;
    v_orig         record;
BEGIN
    -- Only the transition INTO an issued status, and never into void.
    IF public.is_invoice_issued(OLD.status) OR NOT public.is_invoice_issued(NEW.status)
       OR NEW.status = 'void' THEN
        RETURN NEW;
    END IF;

    v_new_charge := public.backbilling_invoice_charge(NEW.id);
    -- Money on the new bill that no METER carries: lines with no meter
    -- (round 3, both reviewers — a meterless "adjustment" line escaped the
    -- meter-scoped comparison), plus amount_due above all the lines. It
    -- cannot be attributed to a meter, so it counts against every meter
    -- scope: a caller cannot hide an increase by moving it off the meter.
    v_new_excess := coalesce((SELECT sum(l.amount) FROM public.invoice_line_items l
                               WHERE l.invoice_id = NEW.id AND l.meter_id IS NULL), 0)
                  + greatest(0::numeric,
                        coalesce(NEW.amount_due, 0) - coalesce((SELECT sum(l.amount) FROM public.invoice_line_items l WHERE l.invoice_id = NEW.id), 0));

    -- Were these days billed before, on a bill since voided? Any OVERLAPPING
    -- period, found by the premise, by a meter the two bills share, or — for
    -- a bill with no premise — by the customer (review rounds 1 and 2, both
    -- reviewers: the exact-period, same-location match let a shifted,
    -- spanning, other-premise or consolidated bill through, and a
    -- consolidated bill with no lines had neither a premise nor a meter).
    --
    -- Each earlier bill is compared at the SCOPE it was found by (round 2,
    -- both reviewers): a consolidated bill with no premise that carries the
    -- voided meter at the same price and another premise besides is not
    -- charging more for the voided days. The SAME premise, or the bill it
    -- names in replaces_invoice_id, compares the whole charge — the GREATER
    -- of lines and amount_due on each side (round 3, both: meter scope at the
    -- same premise let the extra ride on another meter's line). Meter scope
    -- — the two bills' lines on their shared meters and on any meter at the
    -- voided premise, plus money no meter or no meter of this customer
    -- carries — only for a new bill with NO premise (a consolidated bill),
    -- matched through a shared meter (round 4). Deliberately NOT per day:
    -- prorating lets a cheap new month dilute an overcharge.
    --
    -- A bill charges more when it charges more than ANY earlier bill it
    -- matches (round 3, both reviewers). Round 2 required more than EVERY
    -- one, so one higher voided bill — a mis-keyed duplicate, or a decoy
    -- issued beside the live bill and voided with it — excused a rebill of
    -- the neighbouring days. The cost is stated in R21: re-issuing a lawful
    -- correction after it too was voided needs its cause again.
    FOR r IN
        SELECT i.id, i.location_id,
               EXISTS (SELECT 1 FROM public.invoice_line_items a
                         JOIN public.invoice_line_items b ON b.meter_id = a.meter_id
                        WHERE a.invoice_id = i.id AND b.invoice_id = NEW.id
                          AND a.meter_id IS NOT NULL) AS shares_meter
          FROM public.invoices i
         WHERE i.tenant_id = NEW.tenant_id
           AND i.id <> NEW.id
           AND i.status = 'void'
           AND i.first_issued_at IS NOT NULL          -- a discarded draft was never a bill (A-3)
           AND ((NEW.replaces_invoice_id IS NOT NULL AND i.id = NEW.replaces_invoice_id)
             OR (daterange(i.period_start, i.period_end, '[]') && daterange(NEW.period_start, NEW.period_end, '[]')
                 AND ((NEW.location_id IS NOT NULL AND i.location_id = NEW.location_id)
                      OR (NEW.location_id IS NULL AND i.customer_id = NEW.customer_id)
                      OR EXISTS (SELECT 1 FROM public.invoice_line_items a
                                   JOIN public.invoice_line_items b ON b.meter_id = a.meter_id
                                  WHERE a.invoice_id = i.id AND b.invoice_id = NEW.id
                                    AND a.meter_id IS NOT NULL))))
    LOOP
        v_matched := true;
        -- Meter scope ONLY for a new bill that names no premise (round 4,
        -- Fable): keyed on "another premise", the header — the caller's
        -- choice — decided the scope, and the customer's other premise on
        -- the header re-opened the same-premise leak.
        IF r.id IS DISTINCT FROM NEW.replaces_invoice_id AND r.shares_meter
           AND NEW.location_id IS NULL THEN
            -- The new side counts, beside the shared meters: any meter in
            -- service at the voided bill's premise during the new period
            -- (round 4, Opus — a second meter AT that premise carried the
            -- extra), and any meter not at one of this customer's premises,
            -- which could be anything, another tenant's included (round 4,
            -- Fable) — plus the money no meter carries.
            SELECT coalesce(sum(b.amount), 0) + v_new_excess INTO v_new_part
              FROM public.invoice_line_items b
             WHERE b.invoice_id = NEW.id
               AND (b.meter_id IN (SELECT a.meter_id FROM public.invoice_line_items a WHERE a.invoice_id = r.id)
                    OR b.meter_id IN (SELECT d.meter_id FROM public.meter_deployments d
                                       WHERE d.location_id = r.location_id AND d.tenant_id = NEW.tenant_id
                                         AND daterange(d.install_date, d.removal_date, '[)')
                                             && daterange(NEW.period_start, NEW.period_end, '[]'))
                    OR NOT EXISTS (SELECT 1 FROM public.meters m
                                     JOIN public.service_locations sl ON sl.id = m.location_id
                                    WHERE m.id = b.meter_id AND m.tenant_id = NEW.tenant_id
                                      AND sl.customer_id = NEW.customer_id));
            SELECT coalesce(sum(a.amount), 0) INTO v_old_part
              FROM public.invoice_line_items a
             WHERE a.invoice_id = r.id
               AND a.meter_id IN (SELECT b.meter_id FROM public.invoice_line_items b WHERE b.invoice_id = NEW.id);
        ELSE
            v_new_part := v_new_charge;
            v_old_part := public.backbilling_invoice_charge(r.id);
        END IF;
        IF v_new_part > v_old_part THEN
            v_increase := true;
            v_prior_charge := greatest(coalesce(v_prior_charge, 0), v_old_part);
            IF r.id IS DISTINCT FROM NEW.replaces_invoice_id THEN
                v_other_increased := v_other_increased || r.id;
            END IF;
        END IF;
    END LOOP;

    IF NOT v_matched OR NOT v_increase THEN
        RETURN NEW;       -- not a rebill, or reducing / holding: nothing §7.45 caps
    END IF;

    -- This bill charges MORE for a period already billed.
    IF NEW.invoice_type <> 'correction' OR NEW.replaces_invoice_id IS NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('backbilling: invoice %s charges %s for %s..%s, days already billed %s (same premise, meter or — with no premise — customer) on a bill since voided — charging more for days already billed is a backbilling correction whatever the invoice is typed or addressed (invoice_type %s)', NEW.invoice_number, v_new_charge, NEW.period_start, NEW.period_end, v_prior_charge, NEW.invoice_type),
            ERRCODE = 'restrict_violation',
            HINT = 'Issue it as invoice_type = correction on a correction run, with a correction_run_targets row naming the voided bill and backbill_cause = rate_misapplication. A metering fault is corrected through meter_correction_cases, not by reissuing (R-33).';
    END IF;

    SELECT t.* INTO v_t
      FROM public.correction_run_targets t
     WHERE t.tenant_id         = NEW.tenant_id
       AND t.billing_run_id    = NEW.billing_run_id
       AND t.voided_invoice_id = NEW.replaces_invoice_id;
    IF v_t IS NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('backbilling: invoice %s increases what is charged for an already-billed period but has no correction_run_targets row on its run', NEW.invoice_number),
            ERRCODE = 'restrict_violation';
    END IF;

    IF v_t.backbill_cause IS NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('backbilling: invoice %s increases the charge for an already-billed period (%s -> %s) but its correction target records no backbill_cause — an additional charge needs a statutory cause on the record', NEW.invoice_number, v_prior_charge, v_new_charge),
            ERRCODE = 'restrict_violation',
            HINT = 'On the void-and-reissue path the only cause is rate_misapplication (a price error on correct units). A meter that measured wrong is a meter_correction_cases finding (R-33).';
    END IF;

    SELECT i.invoice_number, i.period_start, i.period_end INTO v_orig
      FROM public.invoices i
     WHERE i.id = NEW.replaces_invoice_id AND i.tenant_id = NEW.tenant_id;

    IF v_orig.period_start IS DISTINCT FROM NEW.period_start
       OR v_orig.period_end IS DISTINCT FROM NEW.period_end THEN
        RAISE EXCEPTION USING
            MESSAGE = format('backbilling: invoice %s reprices %s but covers %s..%s where the replaced bill covered %s..%s — a rate misapplication corrects the price of the same period', NEW.invoice_number, v_orig.invoice_number, NEW.period_start, NEW.period_end, v_orig.period_start, v_orig.period_end),
            ERRCODE = 'restrict_violation';
    END IF;

    -- ... and against every OTHER voided bill it charges more than (round 4,
    -- Opus): a correction replacing one bill but addressed to another
    -- premise increased against that premise's voided bill with different
    -- units, and the units test only ever read the bill it named.
    FOREACH v_other IN ARRAY v_other_increased LOOP
        IF NOT public.backbilling_units_match(v_other, NEW.id) THEN
            RAISE EXCEPTION USING
                MESSAGE = format('backbilling: invoice %s charges more than voided bill %s, which it does not replace, and bills different usage from it — a rate misapplication corrects the price of the same units (R-39)', NEW.invoice_number, v_other),
                ERRCODE = 'restrict_violation';
        END IF;
    END LOOP;

    IF NOT public.backbilling_units_match(NEW.replaces_invoice_id, NEW.id) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('backbilling: invoice %s is recorded as a rate_misapplication of %s but bills different usage — R-39 defines that cause as correct units, wrong price; a change in units is a metering or billing-constant finding, which is not corrected by reissuing (R-33)', NEW.invoice_number, v_orig.invoice_number),
            ERRCODE = 'restrict_violation',
            HINT = 'Compare usage_quantity, gas_ccf_used and gas_therms_billed per meter with the replaced bill. A meter that measured wrong opens a meter_correction_cases row.';
    END IF;

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.enforce_backbilling_gate_issue() IS
    'A-2 (v5.4.2-13). BEFORE UPDATE OF status on invoices, on the transition INTO an issued status. Engages on the FACTS: was this premise and period billed before on a bill since voided (once issued), and does this bill charge MORE — both measured with backbilling_invoice_charge(). If so it must be a correction on its run''s target, the target must record backbill_cause = rate_misapplication, it must cover the replaced bill''s period, and it must bill the replaced bill''s usage quantities meter by meter (R-39). Meter errors do not travel this path (R-33). Not inside void_invoice(): the regulated act is the charge (R-22).';

DROP TRIGGER IF EXISTS a_enforce_backbilling_gate_issue ON public.invoices;
CREATE TRIGGER a_enforce_backbilling_gate_issue
    BEFORE UPDATE OF status ON public.invoices
    FOR EACH ROW EXECUTE FUNCTION public.enforce_backbilling_gate_issue();

-- backbill_cause joins the v5.4.2-10 target freeze. The column list decides
-- when the function runs and the early return what it ignores; both change
-- together, or the guard either never fires or fires on everything.
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
    'A-2 (v5.4.2-13), R-37(c). When this utility acquired a premise from a prior owner of the system — per service location, because small utilities acquire part of a neighbouring system. A predecessor_records_unavailable hold is valid only for a period before this date. Write-once, append-only; recorded_at / recorded_by stamped. Successor liability for refunds on the prior owner''s billing is with counsel (R-37 counsel bundle item 3).';


-- ----------------------------------------------------------------------------
-- 8. The meter correction case (R-19, R-33, R-37(b), R-38, R-39)
-- ----------------------------------------------------------------------------
-- One row per finding about one meter. It follows the METER — every in-scope
-- reading of it across every deployment and every occupant (R-37(b)) — which
-- is why it is keyed on the meter and not on an account or an invoice.
--
-- CAUSES. Five of R-39's eight. rate_misapplication is a void-and-reissue
-- cause (section 6); estimation_catchup is an ordinary next bill (OQ-1's
-- text); unbilled_service has no earlier bill, so R-32's billing period does
-- not exist for it (in the OQ-1 brief). Narrow first.
--
-- WHAT THE DATABASE DERIVES, AND WHY. For the two TEST-ANCHORED causes —
-- meter_error ((7)(B)(v)(I)) and non_registering_meter ((v)(II)) — the
-- statute triggers on a test finding, and R-39 rules that the test outcome,
-- not the operator, decides which of the two it is. So the case names its
-- discovering test and the database derives from it:
--   * the cause's eligibility — meter_error needs a fast or slow outcome,
--     non_registering_meter needs non_registering;
--   * anchor_date = the test's date, anchor_basis = test_date;
--   * direction — fast is money owed TO the customer, slow and
--     non-registering are money the customer owes.
-- An ADVERSE test-anchored case also needs a discovering test with READINGS:
-- a date-only migrated "slow" is an assertion, and an assertion does not
-- bill a customer. (A date-only "fast" may open a case: a refund resting on
-- a weak record errs toward the customer.)
--
-- For the three DISCOVERY causes (tampering_bypass, billing_constant_error,
-- crossed_meters) there is no test to derive from. The operator records when
-- the fault was discovered (anchor_basis = discovery_date) and claimed_from,
-- the earliest date the fault is claimed to reach back to. Their cap rows are
-- billable-uncapped, so neither date sets a statutory window; the anchor
-- feeds only the tenant's own adverse limit (R-37(d)), which can only
-- shorten. Direction is per period, from the sign of each period's amount.
--
-- CAUSE CHANGES (R-19, R-38). Revisable while the case is open, each change
-- with a recorded reason. A change INTO tampering_bypass — at opening too —
-- is gated (R-38 attachment 2): it lifts the (4)(E)(vi) disconnection bar
-- and uncaps the bill at once, so it needs a supervisor's session and an
-- evidence reference — a service order on this meter, a deployment of this
-- meter removed for tamper, or a field report. Moving OUT of tampering is
-- toward protection and needs only the reason.
--
-- A TEST FINDING KEEPS ITS CAUSE: meter_error / non_registering_meter may
-- change only to tampering_bypass. Relabelling a fast meter as a discovery
-- cause would drop its window and its mandatory refund while the test stands.
--
-- STATUS. open → frozen (section 12) → open (unfreeze: discard and
-- recompute, R-38) … and open → withdrawn. -14 adds posted, the absolute
-- lock. A FAST meter_error case — money owed to customers — cannot be
-- withdrawn while its discovering test stands: R-37 leaves the favourable
-- direction no decline path, and a withdrawal would be one. Correct the
-- test (supersede it in the history) and the case may then be withdrawn.

CREATE TABLE IF NOT EXISTS public.meter_correction_cases (
    id                      uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id               uuid NOT NULL,
    meter_id                uuid NOT NULL,
    cause                   text NOT NULL,
    discovering_test_id     uuid,
    anchor_date             date,
    anchor_basis            text,
    direction               text,
    claimed_from            date,
    status                  text DEFAULT 'open'::text NOT NULL,
    cause_change_reason     text,
    withdrawn_reason        text,
    tamper_evidence_kind    text,
    tamper_service_order_id uuid,
    tamper_deployment_id    uuid,
    tamper_field_report_ref text,
    tamper_approved_at      timestamp with time zone,
    tamper_approved_by      uuid,
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
    CONSTRAINT meter_correction_cases_discovering_test_fkey
        FOREIGN KEY (discovering_test_id, tenant_id) REFERENCES public.meter_tests(id, tenant_id),
    CONSTRAINT meter_correction_cases_tamper_service_order_fkey
        FOREIGN KEY (tamper_service_order_id, tenant_id) REFERENCES public.service_orders(id, tenant_id),
    CONSTRAINT meter_correction_cases_tamper_deployment_fkey
        FOREIGN KEY (tamper_deployment_id, tenant_id) REFERENCES public.meter_deployments(id, tenant_id),
    CONSTRAINT meter_correction_cases_cause_check
        CHECK ((cause = ANY (ARRAY['meter_error'::text, 'non_registering_meter'::text, 'tampering_bypass'::text, 'billing_constant_error'::text, 'crossed_meters'::text]))),
    CONSTRAINT meter_correction_cases_anchor_check
        CHECK (((anchor_date IS NOT NULL) AND (anchor_basis = ANY (ARRAY['test_date'::text, 'discovery_date'::text])))),
    CONSTRAINT meter_correction_cases_direction_check
        CHECK (((direction IS NULL) OR (direction = ANY (ARRAY['customer_owes'::text, 'customer_owed'::text])))),
    -- A test-anchored cause has a test, a derived direction and no claimed
    -- start; a discovery cause has a claimed start and a per-period direction.
    CONSTRAINT meter_correction_cases_shape_check
        CHECK ((((cause = ANY (ARRAY['meter_error'::text, 'non_registering_meter'::text]))
                  AND (discovering_test_id IS NOT NULL) AND (anchor_basis = 'test_date'::text)
                  AND (direction IS NOT NULL) AND (claimed_from IS NULL))
             OR ((cause <> ALL (ARRAY['meter_error'::text, 'non_registering_meter'::text]))
                  AND (anchor_basis = 'discovery_date'::text) AND (direction IS NULL)
                  AND (claimed_from IS NOT NULL) AND (claimed_from <= anchor_date)))),
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
    -- Tampering carries its approval and exactly one kind of evidence; no
    -- other cause carries either.
    CONSTRAINT meter_correction_cases_tamper_check
        CHECK ((((cause = 'tampering_bypass'::text)
                  AND (tamper_approved_at IS NOT NULL)
                  AND (((tamper_evidence_kind = 'service_order'::text) AND (tamper_service_order_id IS NOT NULL) AND (tamper_deployment_id IS NULL) AND (tamper_field_report_ref IS NULL))
                    OR ((tamper_evidence_kind = 'deployment_removal'::text) AND (tamper_deployment_id IS NOT NULL) AND (tamper_service_order_id IS NULL) AND (tamper_field_report_ref IS NULL))
                    OR ((tamper_evidence_kind = 'field_report'::text) AND (tamper_field_report_ref ~ '[[:alnum:]]'::text) AND (tamper_service_order_id IS NULL) AND (tamper_deployment_id IS NULL))))
             OR ((cause <> 'tampering_bypass'::text)
                  AND (tamper_evidence_kind IS NULL) AND (tamper_service_order_id IS NULL) AND (tamper_deployment_id IS NULL)
                  AND (tamper_field_report_ref IS NULL) AND (tamper_approved_at IS NULL) AND (tamper_approved_by IS NULL))))
);

CREATE INDEX IF NOT EXISTS idx_meter_correction_cases_tenant ON public.meter_correction_cases USING btree (tenant_id);
CREATE INDEX IF NOT EXISTS idx_meter_correction_cases_meter ON public.meter_correction_cases USING btree (meter_id);
CREATE INDEX IF NOT EXISTS idx_meter_correction_cases_test ON public.meter_correction_cases USING btree (discovering_test_id);
-- One live case per finding (review round 1, Fable): two frozen cases on one
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
    'A-2 (v5.4.2-13). One finding about one meter — the object that carries a metering correction after R-33 took meter errors off the void-and-reissue path. Follows the METER across every deployment and occupant (R-37(b)). For meter_error and non_registering_meter the database derives the anchor, its basis and the direction from the discovering test (R-39: the outcome decides the cause); for tampering_bypass, billing_constant_error and crossed_meters the operator records the discovery date and the claimed start. Status open → frozen (R-38; section 12) and back, or withdrawn; posting is v5.4.2-14 (OQ-1). Every change is logged by trigger in meter_correction_case_events.';

COMMENT ON COLUMN public.meter_correction_cases.discovering_test_id IS
    'The meter_tests row that made the finding. Required for the test-anchored causes; its date is the anchor and its outcome decides the cause and the direction. Must be on this meter and not superseded; an ADVERSE case needs one with readings. A test a frozen case rests on cannot be superseded until the case is unfrozen (section 13).';
COMMENT ON COLUMN public.meter_correction_cases.anchor_date IS
    'The date the window counts back from. Derived from the discovering test for the test-anchored causes (a caller value that disagrees is refused); recorded by the operator for the discovery causes, where it feeds only the tenant''s own adverse limit.';
COMMENT ON COLUMN public.meter_correction_cases.direction IS
    'Derived for the test-anchored causes: fast → customer_owed (the refund §7.45(7)(B)(v)(I) makes mandatory back to the window); slow and non_registering → customer_owes. NULL for the discovery causes, whose direction is per period from the sign of the amount (R-25).';
COMMENT ON COLUMN public.meter_correction_cases.claimed_from IS
    'Discovery causes only: the earliest date the fault is claimed to reach back to. These causes are billable-uncapped (R-39), so the claim, not a statute, bounds the periods evaluated; the tenant''s adverse limit may still shorten the adverse side.';
COMMENT ON COLUMN public.meter_correction_cases.cause_change_reason IS
    'The reason for the most recent cause change, required and new with every change (R-19, R-38). The full history, with every earlier reason, is in meter_correction_case_events.';
COMMENT ON COLUMN public.meter_correction_cases.tamper_approved_at IS
    'R-38 attachment 2. Stamped by the database when the case enters tampering_bypass — only from a supervisor''s session, and only with evidence: a service order on this meter, a deployment of this meter removed for tamper, or a field report reference. Cleared (the history keeps it) when the case leaves tampering.';


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
    'A-2 (v5.4.2-13). The append-only history of one meter correction case: opened, every cause change with its reason (R-19, R-38), each evaluation, the R-36 approval, freeze and unfreeze, withdrawal, and each hold opened and closed. Written only by the database''s own triggers; the actor and clock are stamped. Ordered by event_seq (now() is constant within a transaction).';


-- The case guard. Derives what the test decides; stamps what the database
-- decides; gates the move into tampering; confines a frozen or withdrawn case.

CREATE OR REPLACE FUNCTION public.enforce_meter_correction_case() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_user          uuid;
    v_test          record;
    v_anchor        date;
    v_basis         text;
    v_direction     text;
    v_test_cause    boolean := NEW.cause IN ('meter_error', 'non_registering_meter');
    v_into_tamper   boolean;
    v_substance_moved boolean;
    v_head_outcome  text;
BEGIN
    BEGIN
        v_user := NULLIF(current_setting('app.user_id', true), '')::uuid;
    EXCEPTION WHEN OTHERS THEN
        v_user := NULL;
    END;

    -- ---------------------------------------------------------- UPDATE fences
    IF TG_OP = 'UPDATE' THEN
        IF NEW.id IS DISTINCT FROM OLD.id OR NEW.tenant_id IS DISTINCT FROM OLD.tenant_id
           OR NEW.meter_id IS DISTINCT FROM OLD.meter_id
           OR NEW.opened_at IS DISTINCT FROM OLD.opened_at OR NEW.opened_by IS DISTINCT FROM OLD.opened_by
           OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
            RAISE EXCEPTION USING
                MESSAGE = format('meter correction case %s: its meter, tenant and opening are fixed — a finding about another meter is another case', OLD.id),
                ERRCODE = 'restrict_violation';
        END IF;
        IF NEW.frozen_evaluation_id IS DISTINCT FROM OLD.frozen_evaluation_id
           OR NEW.frozen_at IS DISTINCT FROM OLD.frozen_at OR NEW.frozen_by IS DISTINCT FROM OLD.frozen_by
           OR NEW.tamper_approved_at IS DISTINCT FROM OLD.tamper_approved_at
           OR NEW.tamper_approved_by IS DISTINCT FROM OLD.tamper_approved_by THEN
            RAISE EXCEPTION USING
                MESSAGE = format('meter correction case %s: the freeze and the tamper approval are stamped by the database — set status to freeze, or change the cause to tampering_bypass from a supervisor''s session', OLD.id),
                ERRCODE = 'restrict_violation';
        END IF;
        -- DERIVED COLUMNS NEVER MOVE BY HAND, ON ANY PATH (review round 1,
        -- both reviewers). This fence used to sit in the "still open" fall-
        -- through, after the freeze / unfreeze / withdraw branches had
        -- already returned — so `SET status = 'open', direction =
        -- 'customer_owes'` turned a fast meter's refund into a charge, which
        -- then froze, or could be withdrawn.
        IF NEW.anchor_basis IS DISTINCT FROM OLD.anchor_basis
           OR NEW.direction IS DISTINCT FROM OLD.direction THEN
            RAISE EXCEPTION USING
                MESSAGE = format('meter correction case %s: anchor_basis and direction are derived by the database — they follow the cause and the discovering test', OLD.id),
                ERRCODE = 'restrict_violation';
        END IF;
        IF OLD.status = 'withdrawn' THEN
            RAISE EXCEPTION USING
                MESSAGE = format('meter correction case %s was withdrawn (%s) — it is closed; a new finding is a new case', OLD.id, OLD.withdrawn_reason),
                ERRCODE = 'restrict_violation';
        END IF;
        -- A STATUS CHANGE CARRIES NOTHING ELSE (review round 1, both). Freeze,
        -- unfreeze and withdraw each return before the derivation and the
        -- tamper fences below, so the statement that changes status may
        -- change only the status, its own stamps, the withdrawal reason and
        -- the notes. Stated as a whole-row comparison so a column added later
        -- is fenced by default rather than by remembering to list it.
        v_substance_moved := (to_jsonb(NEW) - ARRAY['status', 'frozen_evaluation_id', 'frozen_at', 'frozen_by',
                                                    'withdrawn_reason', 'notes', 'updated_at'])
                             IS DISTINCT FROM
                             (to_jsonb(OLD) - ARRAY['status', 'frozen_evaluation_id', 'frozen_at', 'frozen_by',
                                                    'withdrawn_reason', 'notes', 'updated_at']);
        IF NEW.status IS DISTINCT FROM OLD.status AND v_substance_moved THEN
            RAISE EXCEPTION USING
                MESSAGE = format('meter correction case %s: a change of status (%s -> %s) cannot carry a change to the case itself — change the case in one statement, then its status in another (R-38)', OLD.id, OLD.status, NEW.status),
                ERRCODE = 'restrict_violation';
        END IF;
        IF OLD.status = 'frozen' THEN
            -- The only move out of frozen is back to open: discard and
            -- recompute (R-38).
            IF NEW.status <> 'open' THEN
                RAISE EXCEPTION USING
                    MESSAGE = format('meter correction case %s is frozen: its cause, anchor and evidence were frozen together (R-38) — unfreeze it (status = open) without changing anything it froze, then change it, re-evaluate, and freeze again', OLD.id),
                    ERRCODE = 'restrict_violation';
            END IF;
            NEW.frozen_evaluation_id := NULL;
            NEW.frozen_at := NULL;
            NEW.frozen_by := NULL;
            RETURN NEW;
        END IF;
        -- OLD.status = 'open'
        IF NEW.status = 'frozen' THEN
            -- The freeze checks, and the stamps (section 12).
            NEW.frozen_evaluation_id := public.meter_correction_freeze_check(OLD.id);
            NEW.frozen_at := now();
            NEW.frozen_by := v_user;
            RETURN NEW;
        END IF;
        IF NEW.status = 'withdrawn' THEN
            -- Keyed on what the TEST now finds — the latest row of its
            -- correction chain — not on the case's direction or on whether
            -- any correction exists (review round 1: a fast test superseded by
            -- a faster one satisfied "superseded", and a direction flipped by
            -- hand escaped "customer_owed").
            WITH RECURSIVE chain AS (
                SELECT t.id, t.outcome, 0 AS depth FROM public.meter_tests t
                 WHERE t.id = OLD.discovering_test_id
                UNION ALL
                SELECT s.id, s.outcome, chain.depth + 1 FROM public.meter_tests s
                  JOIN chain ON s.supersedes_test_id = chain.id)
            SELECT chain.outcome INTO v_head_outcome FROM chain ORDER BY chain.depth DESC LIMIT 1;
            IF v_head_outcome = 'fast' THEN
                RAISE EXCEPTION USING
                    MESSAGE = format('meter correction case %s: the test behind this case still finds the meter fast — the refund back to the window is a duty §7.45(7)(B)(v)(I) does not let the utility decline (R-37), and a withdrawal would be the decline', OLD.id),
                    ERRCODE = 'restrict_violation',
                    HINT = 'If the test was wrong, correct it in meter_tests (a superseding row that does not find it fast); the case may then be withdrawn. A period with no Tally bill is held (meter_correction_holds), not withdrawn.';
            END IF;
            RETURN NEW;
        END IF;
        -- still open: fall through to derivation
        -- A TEST FINDING KEEPS ITS CAUSE. A case the test decided (meter_error
        -- or non_registering_meter) may move only to tampering_bypass —
        -- R-19's own progression, and gated below. Relabelling a fast meter
        -- as a billing_constant_error or crossed_meters would drop the
        -- mandatory refund reach and its under-reach check while the test
        -- that found the fault still stands; if the test was wrong, correct
        -- it and withdraw the case.
        IF OLD.cause IN ('meter_error', 'non_registering_meter')
           AND NEW.cause NOT IN ('meter_error', 'non_registering_meter', 'tampering_bypass') THEN
            RAISE EXCEPTION USING
                MESSAGE = format('meter correction case %s: a %s was decided by its test and may become tampering_bypass (with a supervisor and evidence), not %s — a relabel would drop the §7.45 window and, on a fast meter, the mandatory refund (R-37, R-39)', OLD.id, OLD.cause, NEW.cause),
                ERRCODE = 'restrict_violation',
                HINT = 'If the test was wrong, supersede it in meter_tests and withdraw the case; a separate fault on the same meter is a separate case.';
        END IF;
        IF NEW.cause IS DISTINCT FROM OLD.cause THEN
            IF NEW.cause_change_reason IS NULL
               OR NEW.cause_change_reason IS NOT DISTINCT FROM OLD.cause_change_reason THEN
                RAISE EXCEPTION USING
                    MESSAGE = format('meter correction case %s: a cause change (%s -> %s) needs a new cause_change_reason (R-19, R-38)', OLD.id, OLD.cause, NEW.cause),
                    ERRCODE = 'restrict_violation';
            END IF;
        END IF;
    ELSE
        -- ------------------------------------------------------ INSERT fences
        IF NEW.status <> 'open' OR NEW.frozen_evaluation_id IS NOT NULL OR NEW.frozen_at IS NOT NULL
           OR NEW.frozen_by IS NOT NULL OR NEW.withdrawn_reason IS NOT NULL
           OR NEW.tamper_approved_at IS NOT NULL OR NEW.tamper_approved_by IS NOT NULL
           OR NEW.cause_change_reason IS NOT NULL
           OR NEW.anchor_basis IS NOT NULL OR NEW.direction IS NOT NULL THEN
            RAISE EXCEPTION USING
                MESSAGE = 'meter correction case: a case is born open, and its anchor_basis, direction, freeze and approvals are the database''s to set',
                ERRCODE = 'restrict_violation';
        END IF;
        NEW.opened_at := now();
        NEW.opened_by := v_user;
        NEW.created_at := now();
    END IF;

    -- -------------------------------------------------------------- derivation
    IF NEW.discovering_test_id IS NOT NULL THEN
        SELECT t.id, t.meter_id, t.test_date, t.outcome, t.found_defective, t.load_results IS NOT NULL AS has_readings
          INTO v_test
          FROM public.meter_tests t
         WHERE t.id = NEW.discovering_test_id AND t.tenant_id = NEW.tenant_id;
        IF v_test.id IS NULL OR v_test.meter_id <> NEW.meter_id THEN
            RAISE EXCEPTION USING
                MESSAGE = format('meter correction case: the discovering test %s is not a test of meter %s', NEW.discovering_test_id, NEW.meter_id),
                ERRCODE = 'restrict_violation';
        END IF;
        IF EXISTS (SELECT 1 FROM public.meter_tests s WHERE s.supersedes_test_id = v_test.id) THEN
            RAISE EXCEPTION USING
                MESSAGE = format('meter correction case: the discovering test %s has been superseded — cite the test that corrected it', v_test.id),
                ERRCODE = 'restrict_violation';
        END IF;
        -- A finding contradicted the same day (review round 1, Opus). -12
        -- accepts a second standing test on the same meter and date, so a
        -- meter found fast could be cited through a same-day "slow" and billed.
        -- As-found / as-left pairs are routine and an accurate test beside a
        -- failure contradicts nothing; opposite DIRECTIONS on one day do, and
        -- the history must be corrected before either is cited.
        IF v_test.outcome IN ('fast', 'slow', 'non_registering') AND EXISTS (
            SELECT 1 FROM public.meter_tests o
             WHERE o.meter_id = v_test.meter_id AND o.tenant_id = NEW.tenant_id
               AND o.test_date = v_test.test_date AND o.id <> v_test.id
               AND NOT EXISTS (SELECT 1 FROM public.meter_tests s WHERE s.supersedes_test_id = o.id)
               AND ((v_test.outcome = 'fast' AND o.outcome IN ('slow', 'non_registering'))
                 OR (v_test.outcome IN ('slow', 'non_registering') AND o.outcome = 'fast'))) THEN
            RAISE EXCEPTION USING
                MESSAGE = format('meter correction case: test %s found the meter %s, but another standing test on %s found it the opposite way — correct the history (supersede the wrong one) before a correction rests on either', v_test.id, v_test.outcome, v_test.test_date),
                ERRCODE = 'restrict_violation';
        END IF;
    END IF;

    IF v_test_cause THEN
        IF NEW.discovering_test_id IS NULL THEN
            RAISE EXCEPTION USING
                MESSAGE = format('meter correction case: %s is a test finding (§7.45 "if any meter test reveals" / "found not to register") — name the discovering test', NEW.cause),
                ERRCODE = 'restrict_violation';
        END IF;
        IF NEW.cause = 'meter_error' AND v_test.outcome NOT IN ('fast', 'slow') THEN
            RAISE EXCEPTION USING
                MESSAGE = format('meter correction case: meter_error needs a test that found the meter fast or slow — test %s found %s (R-39: the outcome decides the cause; zero registration is non_registering_meter, and a meter off both ways gives no direction to correct in)', v_test.id, coalesce(v_test.outcome, 'no result')),
                ERRCODE = 'restrict_violation';
        END IF;
        IF NEW.cause = 'non_registering_meter' AND v_test.outcome IS DISTINCT FROM 'non_registering' THEN
            RAISE EXCEPTION USING
                MESSAGE = format('meter correction case: non_registering_meter needs a test that found zero registration — test %s found %s (R-39: a meter registering slowly is meter_error)', v_test.id, coalesce(v_test.outcome, 'no result')),
                ERRCODE = 'restrict_violation';
        END IF;
        v_anchor := v_test.test_date;
        v_basis := 'test_date';
        v_direction := CASE v_test.outcome WHEN 'fast' THEN 'customer_owed' ELSE 'customer_owes' END;
        IF v_direction = 'customer_owes' AND NOT v_test.has_readings THEN
            RAISE EXCEPTION USING
                MESSAGE = format('meter correction case: test %s records a %s result without readings — an asserted result cannot bill a customer; an adverse correction rests on a test whose outcome the database derived', v_test.id, v_test.outcome),
                ERRCODE = 'restrict_violation',
                HINT = 'Re-test the meter, or record the readings as a superseding row of that test.';
        END IF;
        IF NEW.anchor_date IS NOT NULL AND NEW.anchor_date <> v_anchor
           AND (TG_OP = 'INSERT' OR NEW.anchor_date IS DISTINCT FROM OLD.anchor_date) THEN
            RAISE EXCEPTION USING
                MESSAGE = format('meter correction case: the anchor of a %s is the discovering test''s date (%s), not %s — the window counts back from the test (R-19)', NEW.cause, v_anchor, NEW.anchor_date),
                ERRCODE = 'restrict_violation';
        END IF;
        IF NEW.claimed_from IS NOT NULL THEN
            RAISE EXCEPTION USING
                MESSAGE = format('meter correction case: a %s''s reach is set by the statute from the test, not by a claimed start', NEW.cause),
                ERRCODE = 'restrict_violation';
        END IF;
        NEW.anchor_date := v_anchor;
        NEW.anchor_basis := v_basis;
        NEW.direction := v_direction;
    ELSE
        IF NEW.anchor_date IS NULL OR NEW.anchor_date > CURRENT_DATE THEN
            RAISE EXCEPTION USING
                MESSAGE = format('meter correction case: a %s needs the date it was discovered, on or before today', NEW.cause),
                ERRCODE = 'restrict_violation';
        END IF;
        IF NEW.claimed_from IS NULL OR NEW.claimed_from > NEW.anchor_date THEN
            RAISE EXCEPTION USING
                MESSAGE = format('meter correction case: a %s needs claimed_from — the earliest date the fault is claimed to reach back to, on or before its discovery', NEW.cause),
                ERRCODE = 'restrict_violation';
        END IF;
        NEW.anchor_basis := 'discovery_date';
        NEW.direction := NULL;
    END IF;

    -- ---------------------------------------------------- the tamper gate
    v_into_tamper := NEW.cause = 'tampering_bypass'
                     AND (TG_OP = 'INSERT' OR OLD.cause IS DISTINCT FROM 'tampering_bypass');
    IF v_into_tamper THEN
        IF NOT public.session_is_supervisor() THEN
            RAISE EXCEPTION USING
                MESSAGE = 'meter correction case: a finding of tampering_bypass needs a supervisor — it lifts the (4)(E)(vi) disconnection bar and uncaps the bill at once (R-38 attachment 2)',
                ERRCODE = 'insufficient_privilege';
        END IF;
        IF NEW.tamper_evidence_kind = 'service_order' THEN
            IF NOT EXISTS (SELECT 1 FROM public.service_orders so
                            WHERE so.id = NEW.tamper_service_order_id AND so.tenant_id = NEW.tenant_id
                              AND so.meter_id = NEW.meter_id) THEN
                RAISE EXCEPTION USING
                    MESSAGE = 'meter correction case: the tamper evidence service order is not an order on this meter',
                    ERRCODE = 'restrict_violation';
            END IF;
        ELSIF NEW.tamper_evidence_kind = 'deployment_removal' THEN
            IF NOT EXISTS (SELECT 1 FROM public.meter_deployments d
                            WHERE d.id = NEW.tamper_deployment_id AND d.tenant_id = NEW.tenant_id
                              AND d.meter_id = NEW.meter_id AND d.removal_reason = 'tamper') THEN
                RAISE EXCEPTION USING
                    MESSAGE = 'meter correction case: the tamper evidence deployment is not a deployment of this meter removed for tamper',
                    ERRCODE = 'restrict_violation';
            END IF;
        ELSIF NEW.tamper_evidence_kind = 'field_report' THEN
            NULL;       -- the CHECK requires an alphanumeric reference
        ELSE
            RAISE EXCEPTION USING
                MESSAGE = 'meter correction case: a finding of tampering_bypass needs evidence — a service order on this meter, a deployment of this meter removed for tamper, or a field report reference (R-38 attachment 2)',
                ERRCODE = 'restrict_violation';
        END IF;
        NEW.tamper_approved_at := now();
        NEW.tamper_approved_by := v_user;
    ELSIF NEW.cause = 'tampering_bypass' THEN
        -- staying in tampering: the approved evidence does not move
        IF NEW.tamper_evidence_kind IS DISTINCT FROM OLD.tamper_evidence_kind
           OR NEW.tamper_service_order_id IS DISTINCT FROM OLD.tamper_service_order_id
           OR NEW.tamper_deployment_id IS DISTINCT FROM OLD.tamper_deployment_id
           OR NEW.tamper_field_report_ref IS DISTINCT FROM OLD.tamper_field_report_ref THEN
            RAISE EXCEPTION USING
                MESSAGE = format('meter correction case %s: the tamper evidence was approved with the finding and does not move — leave tampering_bypass and re-enter it to cite other evidence', OLD.id),
                ERRCODE = 'restrict_violation';
        END IF;
    ELSE
        -- not tampering (or leaving it — toward protection, reason only)
        NEW.tamper_evidence_kind := NULL;
        NEW.tamper_service_order_id := NULL;
        NEW.tamper_deployment_id := NULL;
        NEW.tamper_field_report_ref := NULL;
        NEW.tamper_approved_at := NULL;
        NEW.tamper_approved_by := NULL;
    END IF;

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.enforce_meter_correction_case() IS
    'v5.4.2-13. BEFORE INSERT OR UPDATE on meter_correction_cases. A case is born open with its opening stamped. For meter_error / non_registering_meter it derives anchor_date, anchor_basis and direction from the discovering test (same meter, not superseded; meter_error needs fast or slow, non_registering_meter needs non_registering; an adverse case needs a test with readings). For the discovery causes it requires a discovery date on or before today and claimed_from on or before it. Every cause change needs a new reason; a move into tampering_bypass (at opening too) needs a supervisor''s session and evidence on this meter, and stamps tamper_approved_*. Meter, tenant and opening never change; the freeze and approvals are stamped, never written. A frozen case may only be unfrozen (alone); a withdrawn case never changes; a fast meter_error case cannot be withdrawn while its test stands (R-37). Invoker rights.';

DROP TRIGGER IF EXISTS a_enforce_meter_correction_case ON public.meter_correction_cases;
CREATE TRIGGER a_enforce_meter_correction_case
    BEFORE INSERT OR UPDATE ON public.meter_correction_cases
    FOR EACH ROW EXECUTE FUNCTION public.enforce_meter_correction_case();
ALTER TABLE public.meter_correction_cases ENABLE ALWAYS TRIGGER a_enforce_meter_correction_case;

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
                                   'tamper_evidence_kind', NEW.tamper_evidence_kind));
        RETURN NULL;
    END IF;
    IF NEW.cause IS DISTINCT FROM OLD.cause THEN
        INSERT INTO public.meter_correction_case_events (tenant_id, case_id, event_type, from_cause, to_cause, reason, metadata)
        VALUES (NEW.tenant_id, NEW.id, 'cause_changed', OLD.cause, NEW.cause, NEW.cause_change_reason,
                jsonb_build_object('anchor_date', NEW.anchor_date, 'direction', NEW.direction,
                                   'tamper_evidence_kind', NEW.tamper_evidence_kind,
                                   'tamper_service_order_id', NEW.tamper_service_order_id,
                                   'tamper_deployment_id', NEW.tamper_deployment_id,
                                   'tamper_field_report_ref', NEW.tamper_field_report_ref,
                                   'previous_tamper_evidence_kind', OLD.tamper_evidence_kind));
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
-- 9. The evaluation: the window, the periods, and the evidence
--    (R-25, R-32, R-34, R-35, R-36, R-37(a)(b)(d))
-- ----------------------------------------------------------------------------
-- THE WINDOW, for the counted causes (Kyle 2026-09-22 §1, R-37(a)):
--
--     window_start = MAX( anchor − billable_months,
--                         the governing prior test's date   [(v)(I) only],
--                         the start of the meter's service  [R-37(a)] )
--
-- Every candidate can only move the start LATER. Six months is the ceiling.
--   * The governing test is meter_governing_test(meter, anchor) (R-34): the
--     most recent non-superseded test before the anchor, whatever its outcome
--     or kind. None → the six-month cap governs alone (R-35 refinement 5; the
--     round-1 draft's refusal is gone). Never meters.last_test_date, never a
--     date inferred from install_date or the test interval (R-31, R-35 r3).
--   * The service start is the earliest install_date among the meter's
--     deployments that overlap [anchor − months, anchor), counting only
--     deployments RECORDED no later than the fault was first on record
--     (meter_correction_evidence_fence) — a deployment entered after the
--     finding cannot shorten its window, and re-pointing the case at a
--     fresh copy of the test cannot move that moment (round 1). None recorded → no bound. A deployment start BOUNDS the
--     window; it is never treated as a test date (R-37(a), against R-35 r3).
--     For a REFUND the start must be CORROBORATED — another meter served
--     that premise INTO the window and came out on or before this one went
--     in. Every meter's
--     first deployment is created from meters.start_date, which defaults to
--     the day the meter was ENTERED, so an uncorroborated start on a migrated
--     meter is its onboarding date; honouring it would end every fast-meter
--     refund at go-live and silently drop the pre-cutover stretch R-37(c)'s
--     legacy hold protects. A charge may be shortened by any recorded start.
--
-- THE PERIODS (R-25, R-37(b)). Every issued, unvoided regular / final /
-- correction invoice carrying a line on THIS METER whose period overlaps
-- [period-set start, anchor) — whoever it was billed to and wherever the
-- meter then stood. The period-set start is the window start for a counted
-- cause and claimed_from for a discovery cause. Each period is judged on its
-- own, never netted.
--
-- PER PERIOD. The cap row is re-resolved for that period's own customer and
-- that bill's own premise (class and jurisdiction may differ across
-- occupants and relocations), and the period's own window computed from it.
--   * A period where the customer is OWED money is included whole — R-25
--     passes favourable periods uncapped; a favourable straddler is included
--     whole (R-32).
--   * A period where the customer OWES is included only if it lies wholly at
--     or after every start that applies to it: its statutory window
--     (straddling or preceding it → forfeited whole, R-32), the tenant's own
--     adverse limit (→ forfeited, R-37(d)), and for a discovery cause the
--     claimed start (→ forfeited; billing a period that began before the
--     fault is claimed to have begun over-reaches the claim).
--   Every forfeited period is a row saying so, with the days inside the
--   window and the dollars given up (R-32: "so the cost is visible rather
--   than silent"). And the forfeiture is not merely recorded: disposition is
--   what -14 may post, and a forfeited row is not included.
--
-- THE AMOUNT. The caller supplies one dollar figure per period (positive:
-- the customer owes; negative: the customer is owed), for exactly the
-- periods the database found — no more, no fewer. How the figure is derived
-- from the test's error is not ruled and is not the database's to guess. For
-- a test-anchored case its SIGN must agree with the test: a fast meter
-- cannot yield a charge, nor a slow one a refund.
--
-- APPEND-ONLY, SUPERSEDED NOT DELETED (R-38 attachment 1). Re-evaluating
-- adds an evaluation; the latest governs an open case, the frozen one
-- governs a frozen case, and every earlier one is the audit trail — the old
-- window beside the new. The evaluation stores the full set of inputs it
-- used and their fingerprint, so freezing can prove the evidence still
-- describes the world (section 12).

-- Which invoices billed this meter over a date range. Shared by the
-- evaluation, the hold validation and the freeze, so the three cannot
-- disagree about what "Tally holds an invoice on this meter" means.
CREATE OR REPLACE FUNCTION public.meter_correction_billed_periods(
        p_tenant_id uuid,
        p_meter_id  uuid,
        p_from      date,
        p_before    date)
    RETURNS TABLE (
        invoice_id      uuid,
        customer_id     uuid,
        location_id     uuid,
        period_start    date,
        period_end      date,
        billed_units    numeric)
    LANGUAGE sql
    STABLE
    SET search_path = public, pg_temp
    AS $$
    SELECT i.id, i.customer_id, i.location_id, i.period_start, i.period_end,
           (SELECT sum(l.usage_quantity) FROM public.invoice_line_items l
             WHERE l.invoice_id = i.id AND l.meter_id = p_meter_id)
      FROM public.invoices i
     WHERE i.tenant_id = p_tenant_id
       AND i.first_issued_at IS NOT NULL
       AND i.status <> 'void'
       AND i.invoice_type IN ('regular', 'final', 'correction')
       AND i.period_start < p_before
       AND i.period_end >= p_from
       AND EXISTS (SELECT 1 FROM public.invoice_line_items l
                    WHERE l.invoice_id = i.id AND l.meter_id = p_meter_id)
     ORDER BY i.period_start, i.id;
$$;

COMMENT ON FUNCTION public.meter_correction_billed_periods(uuid, uuid, date, date) IS
    'v5.4.2-13 (R-37(b)). The issued, unvoided regular / final / correction invoices that billed this meter (a line naming it) for a period overlapping [p_from, p_before) — across every customer and premise. billed_units = the summed usage_quantity of this meter''s lines. The one definition the evaluation, the hold validation and the freeze share. Invoker rights.';

-- THE EVIDENCE FENCE (review round 1, Opus F3 / Fable F4). Deployments and
-- acquisitions count as evidence about a finding only if they were recorded
-- no later than the FINDING was. Round 1 fenced on the discovering test's
-- recorded_at — but the caller chooses the discovering test, and -12 lets a
-- same-date, same-readings row supersede it with a fresh recorded_at; re-
-- pointed at that row, the case admitted deployments written after the
-- real finding. The fence is therefore the EARLIEST moment the fault was on
-- record: the first row of the discovering test's correction chain, or any
-- test on this meter that found it defective within the reach of the
-- window, whichever was recorded first. NULL (no test at all) admits nothing.
CREATE OR REPLACE FUNCTION public.meter_correction_evidence_fence(p_case_id uuid)
    RETURNS timestamp with time zone
    LANGUAGE sql
    STABLE
    SET search_path = public, pg_temp
    AS $$
    WITH RECURSIVE c AS (
        SELECT mc.tenant_id, mc.meter_id, mc.discovering_test_id, mc.anchor_date
          FROM public.meter_correction_cases mc WHERE mc.id = p_case_id),
    back AS (
        SELECT t.id, t.supersedes_test_id, t.recorded_at
          FROM public.meter_tests t JOIN c ON t.id = c.discovering_test_id
        UNION ALL
        SELECT p.id, p.supersedes_test_id, p.recorded_at
          FROM public.meter_tests p JOIN back ON p.id = back.supersedes_test_id)
    SELECT least(
        (SELECT min(back.recorded_at) FROM back),
        (SELECT min(t.recorded_at) FROM public.meter_tests t, c
          WHERE t.meter_id = c.meter_id AND t.tenant_id = c.tenant_id
            AND t.found_defective
            AND t.test_date >  (c.anchor_date - interval '6 months')::date
            AND t.test_date <= c.anchor_date));
$$;

COMMENT ON FUNCTION public.meter_correction_evidence_fence(uuid) IS
    'v5.4.2-13 (review round 1). The earliest moment this case''s fault was on record: the first row of its discovering test''s correction chain, or any defective test on the meter within six months before the anchor, whichever was recorded first. Deployments and acquisitions recorded after it are not evidence about the finding — they cannot bound its window, excuse its days, or validate a hold. Re-pointing the case at a superseding or later test cannot move it later. NULL when the case has no test.';

-- Everything an evaluation depends on, as one document. The evaluation
-- stores it and its md5; the freeze recomputes it and compares. So "the
-- evidence still describes this case" is one comparison, not a list of
-- checks that can fall out of step with the evaluation.
CREATE OR REPLACE FUNCTION public.meter_correction_inputs(p_case_id uuid)
    RETURNS jsonb
    LANGUAGE plpgsql
    STABLE
    SET search_path = public, pg_temp
    AS $$
DECLARE
    c           public.meter_correction_cases;
    v_meter     record;
    v_tenant    record;
    v_jur       uuid;
    v_rule      public.backbilling_cap_rules;
    g           record;
    v_stat      date;
    v_dep       record;
    v_window    date;
    v_set_start date;
    v_limit_start date;
    v_periods   jsonb := '[]'::jsonb;
    p           record;
    v_class     text;
    v_pjur      uuid;
    v_prule     public.backbilling_cap_rules;
    v_pwindow   date;
    v_dep_corroborated boolean := false;
    v_fence     timestamptz;
    v_superseded_by uuid;
    v_dep_id    uuid;
    v_dep_install date;
BEGIN
    SELECT * INTO c FROM public.meter_correction_cases WHERE id = p_case_id;
    IF c.id IS NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('meter correction: case %s is not visible in this session', p_case_id),
            ERRCODE = 'no_data_found';
    END IF;

    SELECT m.service_type, m.location_id INTO v_meter
      FROM public.meters m WHERE m.id = c.meter_id AND m.tenant_id = c.tenant_id;
    SELECT t.regulatory_class_mode, t.backbilling_adverse_limit_months INTO v_tenant
      FROM public.tenants t WHERE t.id = c.tenant_id;
    SELECT sl.jurisdiction_id INTO v_jur
      FROM public.service_locations sl WHERE sl.id = v_meter.location_id AND sl.tenant_id = c.tenant_id;

    -- The case-level rule: the statutory reach for a protected customer at
    -- the meter's premise. It sets which periods are evaluated; each period
    -- then answers to its own rule.
    v_rule := public.backbilling_resolve_cap(c.tenant_id, v_jur, v_meter.service_type, 'protected', c.cause);

    -- Every record below is assigned on every path (a no-row SELECT INTO
    -- fills the record with NULLs), so a later field reference never meets
    -- an unassigned record.
    SELECT * INTO g FROM public.meter_governing_test(c.meter_id, c.anchor_date)
     WHERE c.cause = 'meter_error';

    IF v_rule.billable_scope <> 'uncapped' THEN
        v_stat := (c.anchor_date - make_interval(months => v_rule.billable_months))::date;
    END IF;
    v_fence := public.meter_correction_evidence_fence(c.id);
    SELECT s.id INTO v_superseded_by FROM public.meter_tests s
     WHERE s.supersedes_test_id = c.discovering_test_id AND s.tenant_id = c.tenant_id;
    SELECT d.id, d.install_date, d.location_id INTO v_dep
      FROM public.meter_deployments d
     WHERE v_stat IS NOT NULL
       AND d.meter_id = c.meter_id AND d.tenant_id = c.tenant_id
       AND d.created_at <= v_fence
       AND daterange(d.install_date, d.removal_date, '[)') && daterange(v_stat, c.anchor_date, '[)')
     ORDER BY d.install_date, d.id
     LIMIT 1;
    -- A service start shortens a REFUND only when it is corroborated: another
    -- meter served that premise and was removed on or before this meter went
    -- in — Kyle's own premise, "readings taken by a different meter". A
    -- meter's first deployment is created from meters.start_date, which
    -- defaults to the day the meter was entered, so for every migrated meter
    -- an uncorroborated start is the ONBOARDING date: honoured, it would end
    -- each fast-meter refund at go-live and drop the pre-cutover stretch the
    -- legacy hold exists to protect. A charge may be shortened by any
    -- recorded start — that errs toward the customer.
    v_dep_corroborated := v_dep.id IS NOT NULL AND EXISTS (
        SELECT 1 FROM public.meter_deployments pd
         WHERE pd.tenant_id = c.tenant_id
           AND pd.location_id = v_dep.location_id
           AND pd.meter_id <> c.meter_id
           AND pd.created_at <= v_fence
           AND pd.install_date < v_dep.install_date
           AND pd.removal_date IS NOT NULL
           AND pd.removal_date <= v_dep.install_date
           -- and its removal on record before the finding too (round 2): a
           -- live deployment closed afterwards with a chosen date is not
           -- evidence about the finding
           -- strictly before, when the application recorded it: a removal
           -- written in the same transaction as the test shares its now()
           -- (round 3, Fable). An owner-loaded removal (no stamp) is as old
           -- as its row.
           AND CASE WHEN pd.removal_recorded_at IS NULL THEN pd.created_at <= v_fence
                    ELSE pd.removal_recorded_at < v_fence END
           -- It must have served INTO the window (review round 1, Fable F4b):
           -- a meter removed years ago is ordinary migrated history, and would
           -- otherwise corroborate every later meter's onboarding-date start.
           AND pd.removal_date >= v_stat);
    v_dep_id := v_dep.id;
    v_dep_install := v_dep.install_date;
    IF v_dep_id IS NOT NULL AND c.direction = 'customer_owed' AND NOT v_dep_corroborated THEN
        v_dep_id := NULL;
        v_dep_install := NULL;
    END IF;
    IF v_stat IS NOT NULL THEN
        v_window := greatest(v_stat,
                             CASE WHEN v_rule.billable_scope = 'shorter_of_months_or_last_test' THEN g.test_date END,
                             v_dep_install);
    END IF;

    v_set_start := coalesce(v_window, c.claimed_from);
    IF v_set_start IS NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('meter correction case %s: its cap row is uncapped and it carries no claimed start, so there is nothing to bound the periods evaluated', c.id),
            ERRCODE = 'invalid_parameter_value';
    END IF;
    IF v_tenant.backbilling_adverse_limit_months IS NOT NULL THEN
        v_limit_start := (c.anchor_date - make_interval(months => v_tenant.backbilling_adverse_limit_months))::date;
    END IF;

    FOR p IN SELECT * FROM public.meter_correction_billed_periods(c.tenant_id, c.meter_id, v_set_start, c.anchor_date) LOOP
        v_class := public.backbilling_customer_class(p.customer_id);
        SELECT sl.jurisdiction_id INTO v_pjur
          FROM public.service_locations sl WHERE sl.id = p.location_id AND sl.tenant_id = c.tenant_id;
        v_prule := public.backbilling_resolve_cap(c.tenant_id, v_pjur, v_meter.service_type, v_class, c.cause);
        v_pwindow := CASE WHEN v_prule.billable_scope = 'uncapped' THEN NULL
                          ELSE greatest((c.anchor_date - make_interval(months => v_prule.billable_months))::date,
                                        CASE WHEN v_prule.billable_scope = 'shorter_of_months_or_last_test' THEN g.test_date END,
                                        v_dep_install) END;
        v_periods := v_periods || jsonb_build_object(
            'invoice_id', p.invoice_id, 'customer_id', p.customer_id, 'location_id', p.location_id,
            'period_start', p.period_start, 'period_end', p.period_end, 'billed_units', p.billed_units,
            'customer_class', v_class, 'cap_rule_id', v_prule.id, 'cap_rule_updated_at', v_prule.updated_at,
            'jurisdiction_level', CASE WHEN v_prule.jurisdiction_id IS NULL THEN 'state_default' ELSE 'municipal' END,
            'billable_scope', v_prule.billable_scope, 'window_start', v_pwindow,
            'enforceable_scope', v_prule.enforceable_scope, 'enforceable_months', v_prule.enforceable_months);
    END LOOP;

    RETURN jsonb_build_object(
        'case_id', c.id, 'meter_id', c.meter_id, 'cause', c.cause,
        'discovering_test_id', c.discovering_test_id, 'discovering_test_superseded_by', v_superseded_by,
        'evidence_fence', v_fence, 'anchor_date', c.anchor_date,
        'anchor_basis', c.anchor_basis, 'direction', c.direction, 'claimed_from', c.claimed_from,
        'service_type', v_meter.service_type, 'regulatory_class_mode', v_tenant.regulatory_class_mode,
        'cap_rule_id', v_rule.id, 'cap_rule_updated_at', v_rule.updated_at,
        'billable_scope', v_rule.billable_scope, 'billable_months', v_rule.billable_months,
        'governing_test_id', g.meter_test_id, 'governing_test_date', g.test_date,
        'governing_record_basis', g.record_basis, 'governing_entered_out_of_order', g.entered_out_of_order,
        'prior_test_failed', g.prior_test_failed, 'absence', g.absence,
        'supervisor_gate_required', coalesce(c.cause = 'meter_error' AND c.direction = 'customer_owes' AND g.supervisor_gate, false),
        'statutory_start', v_stat, 'deployment_id', v_dep_id, 'deployment_bound', v_dep_install,
        'deployment_corroborated', v_dep_corroborated,
        'window_start', v_window, 'period_set_start', v_set_start,
        'tenant_limit_months', v_tenant.backbilling_adverse_limit_months, 'tenant_limit_start', v_limit_start,
        'periods', v_periods);
END;
$$;

COMMENT ON FUNCTION public.meter_correction_inputs(uuid) IS
    'v5.4.2-13. Everything an evaluation of this case depends on, as one jsonb document: the case''s cause, test, anchor, direction and claimed start; the cap row; the governing test (meter_governing_test, R-34) with its R-36 gate — required only for an ADVERSE meter_error; the statutory start, the deployment bound (deployments recorded no later than the discovering test, R-37(a)) and the window (their MAX); the tenant''s adverse limit (R-37(d)); and every billed period of the meter in scope, each with its own customer class, cap row and window. The evaluation stores it with its md5; the freeze recomputes and compares. Invoker rights.';


CREATE SEQUENCE IF NOT EXISTS public.meter_correction_evaluations_seq;
GRANT USAGE, SELECT ON SEQUENCE public.meter_correction_evaluations_seq TO tally_app;

CREATE TABLE IF NOT EXISTS public.meter_correction_evaluations (
    id                              uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id                       uuid NOT NULL,
    case_id                         uuid NOT NULL,
    submitted_amounts               jsonb NOT NULL,
    evaluation_seq                  bigint DEFAULT nextval('public.meter_correction_evaluations_seq') NOT NULL,
    cause                           text,
    anchor_date                     date,
    anchor_basis                    text,
    direction                       text,
    claimed_from                    date,
    governing_test_id               uuid,
    governing_test_date             date,
    governing_record_basis          text,
    governing_entered_out_of_order  boolean,
    prior_test_failed               boolean,
    absence                         text,
    supervisor_gate_required        boolean,
    statutory_start                 date,
    deployment_id                   uuid,
    deployment_bound                date,
    window_start                    date,
    tenant_limit_months             integer,
    tenant_limit_start              date,
    cap_rule_id                     uuid,
    inputs                          jsonb,
    inputs_fingerprint              text,
    evaluated_at                    timestamp with time zone DEFAULT now() NOT NULL,
    evaluated_by                    uuid,
    CONSTRAINT meter_correction_evaluations_pkey PRIMARY KEY (id),
    CONSTRAINT meter_correction_evaluations_id_tenant_id_key UNIQUE (id, tenant_id),
    CONSTRAINT meter_correction_evaluations_tenant_id_fkey
        FOREIGN KEY (tenant_id) REFERENCES public.tenants(id),
    CONSTRAINT meter_correction_evaluations_case_fkey
        FOREIGN KEY (case_id, tenant_id) REFERENCES public.meter_correction_cases(id, tenant_id),
    CONSTRAINT meter_correction_evaluations_governing_test_fkey
        FOREIGN KEY (governing_test_id, tenant_id) REFERENCES public.meter_tests(id, tenant_id),
    CONSTRAINT meter_correction_evaluations_deployment_fkey
        FOREIGN KEY (deployment_id, tenant_id) REFERENCES public.meter_deployments(id, tenant_id),
    CONSTRAINT meter_correction_evaluations_cap_rule_fkey
        FOREIGN KEY (cap_rule_id, tenant_id) REFERENCES public.backbilling_cap_rules(id, tenant_id),
    CONSTRAINT meter_correction_evaluations_derived_check
        CHECK (((cause IS NOT NULL) AND (anchor_date IS NOT NULL) AND (inputs IS NOT NULL)
            AND (inputs_fingerprint IS NOT NULL) AND (supervisor_gate_required IS NOT NULL))),
    CONSTRAINT meter_correction_evaluations_amounts_check
        CHECK ((jsonb_typeof(submitted_amounts) = 'object'::text))
);

CREATE INDEX IF NOT EXISTS idx_meter_correction_evaluations_tenant ON public.meter_correction_evaluations USING btree (tenant_id);
CREATE INDEX IF NOT EXISTS idx_meter_correction_evaluations_case ON public.meter_correction_evaluations USING btree (case_id, evaluation_seq DESC);

ALTER TABLE public.meter_correction_evaluations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.meter_correction_evaluations FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_isolation ON public.meter_correction_evaluations;
CREATE POLICY tenant_isolation ON public.meter_correction_evaluations USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));

REVOKE UPDATE, DELETE, TRUNCATE ON public.meter_correction_evaluations FROM tally_app;

-- The case's frozen evaluation, now that the table exists. The freeze check
-- (section 12) also proves it belongs to the same case.
ALTER TABLE public.meter_correction_cases DROP CONSTRAINT IF EXISTS meter_correction_cases_frozen_evaluation_fkey;
ALTER TABLE public.meter_correction_cases ADD CONSTRAINT meter_correction_cases_frozen_evaluation_fkey
    FOREIGN KEY (frozen_evaluation_id, tenant_id) REFERENCES public.meter_correction_evaluations(id, tenant_id);

COMMENT ON TABLE public.meter_correction_evaluations IS
    'A-2 (v5.4.2-13), R-25 / R-32 / R-34…R-37 / R-38 attachment 1. One evaluation of one meter correction case: the caller submits one dollar figure per billed period (submitted_amounts, keyed by invoice id); the database derives everything else — the window, the governing test and its R-36 gate, the deployment bound, the tenant limit, the periods — and writes one meter_correction_period_evidence row per period. Append-only: a re-evaluation is a new row, the latest governs an open case and the frozen one a frozen case; the rest are the audit trail of how the answer changed (superseded, never deleted). inputs is the full document it was computed from and inputs_fingerprint its md5, which the freeze re-derives.';
COMMENT ON COLUMN public.meter_correction_evaluations.submitted_amounts IS
    'The caller''s dollar figure per billed period, {invoice_id: amount}: positive = the customer owes, negative = the customer is owed. Must name exactly the periods the database found; for a test-anchored case the sign must agree with the test. The one thing in an evaluation the database does not derive — the method for turning a test error into dollars is not ruled.';
COMMENT ON COLUMN public.meter_correction_evaluations.supervisor_gate_required IS
    'R-36. True for an ADVERSE meter_error correction whose governing test is date-only migrated, or which has no prior test at all, while anchor − 6 months still reaches before the tenant''s cutover (meter_governing_test().supervisor_gate). The case cannot freeze until a supervisor other than its opener and evaluator approves THIS evaluation (meter_correction_approvals). Lapses on its own after the transitional period.';
COMMENT ON COLUMN public.meter_correction_evaluations.governing_entered_out_of_order IS
    'D-5: the governing test was entered after a later-dated test on the same meter. Recorded so the evidence carries it; a test entered out of order AFTER this evaluation changes the governing test, which the freeze and the case-status surface both catch.';

CREATE OR REPLACE FUNCTION public.enforce_meter_correction_evaluation() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    c           record;
    v_inputs    jsonb;
    v_caller    jsonb;
    v_key       text;
    v_val       jsonb;
    v_ids       text[];
    v_amount    numeric;
BEGIN
    -- Only the case and the amounts are the caller's.
    SELECT jsonb_object_agg(k, v) INTO v_caller
      FROM jsonb_each(to_jsonb(NEW) - ARRAY['id', 'tenant_id', 'case_id', 'submitted_amounts', 'evaluation_seq', 'evaluated_at']) AS e(k, v)
     WHERE v <> 'null'::jsonb;
    IF v_caller IS NOT NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('meter correction evaluation: %s are derived by the database, never supplied', (SELECT string_agg(k, ', ') FROM jsonb_object_keys(v_caller) AS k)),
            ERRCODE = 'restrict_violation',
            HINT = 'Insert only case_id and submitted_amounts.';
    END IF;

    -- Serialise with the case's freeze, cause changes and holds.
    SELECT mc.id, mc.tenant_id, mc.status, mc.direction, mc.cause INTO c
      FROM public.meter_correction_cases mc
     WHERE mc.id = NEW.case_id AND mc.tenant_id = NEW.tenant_id
       FOR NO KEY UPDATE;
    IF c.id IS NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('meter correction evaluation: case %s is not visible in this session', NEW.case_id),
            ERRCODE = 'no_data_found';
    END IF;
    IF c.status <> 'open' THEN
        RAISE EXCEPTION USING
            MESSAGE = format('meter correction evaluation: case %s is %s — only an open case is evaluated (unfreeze it first: R-38, discard and recompute)', c.id, c.status),
            ERRCODE = 'restrict_violation';
    END IF;

    v_inputs := public.meter_correction_inputs(c.id);

    -- A corrected test decides nothing (review round 1, both reviewers):
    -- the case must be re-pointed at the correction, or withdrawn.
    IF v_inputs ->> 'discovering_test_superseded_by' IS NOT NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('meter correction evaluation: case %s rests on test %s, which has been corrected by %s — re-point the case at the correcting test, or withdraw it', c.id, v_inputs ->> 'discovering_test_id', v_inputs ->> 'discovering_test_superseded_by'),
            ERRCODE = 'restrict_violation';
    END IF;

    -- Exactly the periods the database found.
    SELECT coalesce(array_agg(x ->> 'invoice_id' ORDER BY x ->> 'invoice_id'), ARRAY[]::text[]) INTO v_ids
      FROM jsonb_array_elements(v_inputs -> 'periods') AS x;
    IF v_ids IS DISTINCT FROM (SELECT coalesce(array_agg(k ORDER BY k), ARRAY[]::text[]) FROM jsonb_object_keys(NEW.submitted_amounts) AS k) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('meter correction evaluation: submitted_amounts must name exactly the %s billed period(s) this meter has in scope — expected invoice ids %s', coalesce(array_length(v_ids, 1), 0), v_ids::text),
            ERRCODE = 'invalid_parameter_value',
            HINT = 'SELECT * FROM public.meter_correction_billed_periods(tenant, meter, start, anchor) lists them; a period cannot be left out of a correction, and none can be added.';
    END IF;
    FOR v_key, v_val IN SELECT k, v FROM jsonb_each(NEW.submitted_amounts) AS e(k, v) LOOP
        IF jsonb_typeof(v_val) <> 'number' THEN
            RAISE EXCEPTION USING
                MESSAGE = format('meter correction evaluation: the amount for invoice %s is not a number', v_key),
                ERRCODE = 'invalid_parameter_value';
        END IF;
        v_amount := (v_val #>> '{}')::numeric;
        IF v_amount <> round(v_amount, 2) THEN
            RAISE EXCEPTION USING
                MESSAGE = format('meter correction evaluation: the amount for invoice %s has more than two decimal places', v_key),
                ERRCODE = 'invalid_parameter_value';
        END IF;
        -- A zero is not a derivation method (review round 1, both reviewers):
        -- on a test-anchored case a period that billed usage on the meter has
        -- a correction the test's error implies, and 0.00 would be the
        -- "de minimis" decline R-37 says the refund direction does not have.
        -- Unknown usage (NULL billed_units) counts as usage (round 2, Opus).
        IF c.direction IS NOT NULL AND v_amount = 0
           AND (SELECT (x ->> 'billed_units')::numeric
                  FROM jsonb_array_elements(v_inputs -> 'periods') AS x
                 WHERE x ->> 'invoice_id' = v_key) IS DISTINCT FROM 0 THEN
            RAISE EXCEPTION USING
                MESSAGE = format('meter correction evaluation: invoice %s billed usage on a meter the test found %s, so its correction cannot be zero', v_key,
                                 CASE c.direction WHEN 'customer_owed' THEN 'fast' ELSE 'slow or not registering' END),
                ERRCODE = 'invalid_parameter_value';
        END IF;
        IF (c.direction = 'customer_owed' AND v_amount > 0) OR (c.direction = 'customer_owes' AND v_amount < 0) THEN
            RAISE EXCEPTION USING
                MESSAGE = format('meter correction evaluation: invoice %s carries %s, but the test found the meter %s — the correction runs one way (%s) for every period', v_key, v_amount,
                                 CASE c.direction WHEN 'customer_owed' THEN 'fast' ELSE 'slow or not registering' END, c.direction),
                ERRCODE = 'invalid_parameter_value';
        END IF;
    END LOOP;

    NEW.evaluation_seq := nextval('public.meter_correction_evaluations_seq');
    NEW.evaluated_at := now();
    BEGIN
        NEW.evaluated_by := NULLIF(current_setting('app.user_id', true), '')::uuid;
    EXCEPTION WHEN OTHERS THEN
        NEW.evaluated_by := NULL;
    END;
    NEW.cause := v_inputs ->> 'cause';
    NEW.anchor_date := (v_inputs ->> 'anchor_date')::date;
    NEW.anchor_basis := v_inputs ->> 'anchor_basis';
    NEW.direction := v_inputs ->> 'direction';
    NEW.claimed_from := (v_inputs ->> 'claimed_from')::date;
    NEW.governing_test_id := (v_inputs ->> 'governing_test_id')::uuid;
    NEW.governing_test_date := (v_inputs ->> 'governing_test_date')::date;
    NEW.governing_record_basis := v_inputs ->> 'governing_record_basis';
    NEW.governing_entered_out_of_order := (v_inputs ->> 'governing_entered_out_of_order')::boolean;
    NEW.prior_test_failed := (v_inputs ->> 'prior_test_failed')::boolean;
    NEW.absence := v_inputs ->> 'absence';
    NEW.supervisor_gate_required := (v_inputs ->> 'supervisor_gate_required')::boolean;
    NEW.statutory_start := (v_inputs ->> 'statutory_start')::date;
    NEW.deployment_id := (v_inputs ->> 'deployment_id')::uuid;
    NEW.deployment_bound := (v_inputs ->> 'deployment_bound')::date;
    NEW.window_start := (v_inputs ->> 'window_start')::date;
    NEW.tenant_limit_months := (v_inputs ->> 'tenant_limit_months')::integer;
    NEW.tenant_limit_start := (v_inputs ->> 'tenant_limit_start')::date;
    NEW.cap_rule_id := (v_inputs ->> 'cap_rule_id')::uuid;
    NEW.inputs := v_inputs;
    NEW.inputs_fingerprint := md5(v_inputs::text);
    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.enforce_meter_correction_evaluation() IS
    'v5.4.2-13. BEFORE INSERT on meter_correction_evaluations: refuses any caller-supplied derived column; locks the case (FOR NO KEY UPDATE) and requires it open; computes meter_correction_inputs(); requires submitted_amounts to name exactly the billed periods found, each a number to two decimals whose sign agrees with a test-anchored case''s direction; stamps seq, time and actor and fills every derived column from the inputs. Invoker rights.';

DROP TRIGGER IF EXISTS a_enforce_meter_correction_evaluation ON public.meter_correction_evaluations;
CREATE TRIGGER a_enforce_meter_correction_evaluation BEFORE INSERT ON public.meter_correction_evaluations
    FOR EACH ROW EXECUTE FUNCTION public.enforce_meter_correction_evaluation();
DROP TRIGGER IF EXISTS append_only ON public.meter_correction_evaluations;
CREATE TRIGGER append_only BEFORE UPDATE OR DELETE ON public.meter_correction_evaluations
    FOR EACH ROW EXECUTE FUNCTION public.enforce_append_only();
DROP TRIGGER IF EXISTS no_truncate ON public.meter_correction_evaluations;
CREATE TRIGGER no_truncate BEFORE TRUNCATE ON public.meter_correction_evaluations
    FOR EACH STATEMENT EXECUTE FUNCTION public.enforce_no_hard_delete();
ALTER TABLE public.meter_correction_evaluations ENABLE ALWAYS TRIGGER a_enforce_meter_correction_evaluation;
ALTER TABLE public.meter_correction_evaluations ENABLE ALWAYS TRIGGER append_only;
ALTER TABLE public.meter_correction_evaluations ENABLE ALWAYS TRIGGER no_truncate;


-- The per-period evidence (R-25), written only by the evaluation's trigger.
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
    cap_rule_id         uuid NOT NULL,
    jurisdiction_level  text NOT NULL,
    billable_scope      text NOT NULL,
    window_start        date,
    tenant_limit_start  date,
    enforceable_scope   text NOT NULL,
    enforceable_months  integer,
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
    CONSTRAINT meter_correction_period_evidence_cap_rule_fkey
        FOREIGN KEY (cap_rule_id, tenant_id) REFERENCES public.backbilling_cap_rules(id, tenant_id),
    CONSTRAINT meter_correction_period_evidence_direction_check
        CHECK ((direction = ANY (ARRAY['customer_owes'::text, 'customer_owed'::text, 'neutral'::text]))),
    CONSTRAINT meter_correction_period_evidence_disposition_check
        CHECK ((disposition = ANY (ARRAY['included'::text, 'forfeited'::text]))),
    -- A forfeiture is adverse, names its reason and gives up the whole
    -- figure (R-32); an included period gives up nothing.
    CONSTRAINT meter_correction_period_evidence_forfeit_check
        CHECK ((((disposition = 'forfeited'::text) AND (direction = 'customer_owes'::text)
                  AND (forfeit_reason = ANY (ARRAY['straddles_window'::text, 'before_window'::text, 'tenant_limit'::text, 'straddles_claimed_start'::text]))
                  AND (forfeited_amount = correction_amount))
             OR ((disposition = 'included'::text) AND (forfeit_reason IS NULL) AND (forfeited_amount = (0)::numeric)))),
    CONSTRAINT meter_correction_period_evidence_sign_check
        CHECK ((((direction = 'customer_owes'::text) AND (correction_amount > (0)::numeric))
             OR ((direction = 'customer_owed'::text) AND (correction_amount < (0)::numeric))
             OR ((direction = 'neutral'::text) AND (correction_amount = (0)::numeric))))
);

CREATE INDEX IF NOT EXISTS idx_meter_correction_period_evidence_tenant ON public.meter_correction_period_evidence USING btree (tenant_id);
CREATE INDEX IF NOT EXISTS idx_meter_correction_period_evidence_invoice ON public.meter_correction_period_evidence USING btree (invoice_id);

ALTER TABLE public.meter_correction_period_evidence ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.meter_correction_period_evidence FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_isolation ON public.meter_correction_period_evidence;
CREATE POLICY tenant_isolation ON public.meter_correction_period_evidence USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));

REVOKE UPDATE, DELETE, TRUNCATE ON public.meter_correction_period_evidence FROM tally_app;

CREATE OR REPLACE FUNCTION public.enforce_period_evidence_written_by_evaluation() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
BEGIN
    IF pg_trigger_depth() < 2 THEN
        RAISE EXCEPTION USING
            MESSAGE = 'meter_correction_period_evidence rows are written only by the database, from the evaluation that computed them — an evidence row added later would describe a correction nobody evaluated (v5.4.2-13)',
            ERRCODE = 'restrict_violation',
            HINT = 'Insert a meter_correction_evaluations row; its trigger writes the evidence.';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS a_enforce_period_evidence_written_by_evaluation ON public.meter_correction_period_evidence;
CREATE TRIGGER a_enforce_period_evidence_written_by_evaluation BEFORE INSERT ON public.meter_correction_period_evidence
    FOR EACH ROW EXECUTE FUNCTION public.enforce_period_evidence_written_by_evaluation();
DROP TRIGGER IF EXISTS append_only ON public.meter_correction_period_evidence;
CREATE TRIGGER append_only BEFORE UPDATE OR DELETE ON public.meter_correction_period_evidence
    FOR EACH ROW EXECUTE FUNCTION public.enforce_append_only();
DROP TRIGGER IF EXISTS no_truncate ON public.meter_correction_period_evidence;
CREATE TRIGGER no_truncate BEFORE TRUNCATE ON public.meter_correction_period_evidence
    FOR EACH STATEMENT EXECUTE FUNCTION public.enforce_no_hard_delete();
ALTER TABLE public.meter_correction_period_evidence ENABLE ALWAYS TRIGGER a_enforce_period_evidence_written_by_evaluation;
ALTER TABLE public.meter_correction_period_evidence ENABLE ALWAYS TRIGGER append_only;
ALTER TABLE public.meter_correction_period_evidence ENABLE ALWAYS TRIGGER no_truncate;

COMMENT ON TABLE public.meter_correction_period_evidence IS
    'A-2 (v5.4.2-13), R-25 / R-32 / R-37(d). One row per billed period an evaluation judged — the structural ruling of A-2: direction is tested per original billing period, never netted. Carries the period''s own customer class, cap row and window (occupants and premises differ across a meter''s life, R-37(b)), the caller''s amount, and the disposition: included, or forfeited whole with its reason (straddles_window / before_window, R-32; tenant_limit, R-37(d); straddles_claimed_start), the days inside the window and the dollars given up. enforceable_scope is the fact v5.4.2-14 carries onto the posted charge (F-1: never = not disconnectable). Written only by the evaluation''s trigger; append-only.';
COMMENT ON COLUMN public.meter_correction_period_evidence.days_in_window IS
    'R-32. Days of this period on or after the start that governs it (its window, the tenant limit, or the claimed start — whichever is latest and applies); the full period length where none applies. On a forfeited row, the days that were lawfully billable and were given up with the rest.';

CREATE OR REPLACE FUNCTION public.meter_correction_evaluation_after() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    x           jsonb;
    v_amount    numeric(12,2);
    v_dir       text;
    v_pwindow   date;
    v_eff       date;
    v_disp      text;
    v_reason    text;
    v_start     date;
    v_end       date;
BEGIN
    FOR x IN SELECT * FROM jsonb_array_elements(NEW.inputs -> 'periods') LOOP
        v_amount := (NEW.submitted_amounts ->> (x ->> 'invoice_id'))::numeric;
        v_start := (x ->> 'period_start')::date;
        v_end := (x ->> 'period_end')::date;
        v_pwindow := (x ->> 'window_start')::date;
        v_dir := CASE WHEN v_amount > 0 THEN 'customer_owes'
                      WHEN v_amount < 0 THEN 'customer_owed'
                      ELSE 'neutral' END;
        -- The latest start that applies to an ADVERSE period.
        v_eff := greatest(v_pwindow, NEW.tenant_limit_start, NEW.claimed_from);
        v_disp := 'included';
        v_reason := NULL;
        IF v_dir = 'customer_owes' THEN
            IF v_pwindow IS NOT NULL AND v_start < v_pwindow THEN
                v_disp := 'forfeited';
                v_reason := CASE WHEN v_end >= v_pwindow THEN 'straddles_window' ELSE 'before_window' END;
            ELSIF NEW.tenant_limit_start IS NOT NULL AND v_start < NEW.tenant_limit_start THEN
                v_disp := 'forfeited';
                v_reason := 'tenant_limit';
            ELSIF NEW.claimed_from IS NOT NULL AND v_start < NEW.claimed_from THEN
                v_disp := 'forfeited';
                v_reason := 'straddles_claimed_start';
            END IF;
        ELSE
            -- A favourable period is judged against the statutory window only
            -- (the tenant limit never applies to it, R-37(d)).
            v_eff := greatest(v_pwindow, NEW.claimed_from);
        END IF;

        INSERT INTO public.meter_correction_period_evidence
            (tenant_id, evaluation_id, invoice_id, customer_id, location_id, period_start, period_end,
             billed_units, customer_class, cap_rule_id, jurisdiction_level, billable_scope, window_start,
             tenant_limit_start, enforceable_scope, enforceable_months, direction, correction_amount,
             disposition, forfeit_reason, days_in_window, forfeited_amount)
        VALUES
            (NEW.tenant_id, NEW.id, (x ->> 'invoice_id')::uuid, (x ->> 'customer_id')::uuid,
             (x ->> 'location_id')::uuid, v_start, v_end,
             (x ->> 'billed_units')::numeric, x ->> 'customer_class', (x ->> 'cap_rule_id')::uuid,
             x ->> 'jurisdiction_level', x ->> 'billable_scope', v_pwindow,
             NEW.tenant_limit_start, x ->> 'enforceable_scope', (x ->> 'enforceable_months')::integer,
             v_dir, v_amount, v_disp, v_reason,
             greatest(0, v_end - greatest(v_start, coalesce(v_eff, v_start)) + 1),
             CASE WHEN v_disp = 'forfeited' THEN v_amount ELSE 0 END);
    END LOOP;

    INSERT INTO public.meter_correction_case_events (tenant_id, case_id, event_type, evaluation_id, metadata)
    VALUES (NEW.tenant_id, NEW.case_id, 'evaluated', NEW.id,
            jsonb_build_object('evaluation_seq', NEW.evaluation_seq, 'window_start', NEW.window_start,
                               'governing_test_id', NEW.governing_test_id,
                               'supervisor_gate_required', NEW.supervisor_gate_required,
                               'periods', jsonb_array_length(NEW.inputs -> 'periods')));
    RETURN NULL;
END;
$$;

COMMENT ON FUNCTION public.meter_correction_evaluation_after() IS
    'v5.4.2-13. AFTER INSERT on meter_correction_evaluations: one evidence row per period. An adverse period is forfeited whole (R-32) when it begins before its statutory window (straddles_window / before_window), else before the tenant''s adverse limit (tenant_limit, R-37(d)), else before a discovery cause''s claimed start (straddles_claimed_start); everything else, and every favourable period, is included. Logs the evaluation.';

DROP TRIGGER IF EXISTS z_meter_correction_evaluation_after ON public.meter_correction_evaluations;
CREATE TRIGGER z_meter_correction_evaluation_after AFTER INSERT ON public.meter_correction_evaluations
    FOR EACH ROW EXECUTE FUNCTION public.meter_correction_evaluation_after();
ALTER TABLE public.meter_correction_evaluations ENABLE ALWAYS TRIGGER z_meter_correction_evaluation_after;


-- ----------------------------------------------------------------------------
-- 10. The R-36 supervisor approval
-- ----------------------------------------------------------------------------
-- During a tenant's first six months after cutover, an ADVERSE meter_error
-- correction resting on a date-only migrated test, or on no test at all,
-- needs a supervisor's approval (R-36). meter_governing_test() computes the
-- gate (in A-2's own anchor − 6 months arithmetic); this is where it is
-- ENFORCED — the case cannot freeze without it.
--
-- The approval is for ONE evaluation: re-evaluate and the approval does not
-- carry over, because the approver approved a particular window on a
-- particular basis. The approver is a supervisor other than the case's
-- opener and the evaluation's author — approving one's own charge is not an
-- approval. The database stamps who and when.

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
    CONSTRAINT meter_correction_approvals_note_check
        CHECK ((note ~ '[[:alnum:]]'::text))
);

CREATE INDEX IF NOT EXISTS idx_meter_correction_approvals_tenant ON public.meter_correction_approvals USING btree (tenant_id);

ALTER TABLE public.meter_correction_approvals ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.meter_correction_approvals FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_isolation ON public.meter_correction_approvals;
CREATE POLICY tenant_isolation ON public.meter_correction_approvals USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));

REVOKE UPDATE, DELETE, TRUNCATE ON public.meter_correction_approvals FROM tally_app;

CREATE OR REPLACE FUNCTION public.enforce_meter_correction_approval() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    c       record;
    e       record;
    v_user  uuid;
BEGIN
    BEGIN
        v_user := NULLIF(current_setting('app.user_id', true), '')::uuid;
    EXCEPTION WHEN OTHERS THEN
        v_user := NULL;
    END;

    SELECT mc.id, mc.status, mc.opened_by INTO c
      FROM public.meter_correction_cases mc
     WHERE mc.id = NEW.case_id AND mc.tenant_id = NEW.tenant_id
       FOR NO KEY UPDATE;
    IF c.id IS NULL OR c.status <> 'open' THEN
        RAISE EXCEPTION USING
            MESSAGE = format('meter correction approval: case %s is not an open case in this session', NEW.case_id),
            ERRCODE = 'restrict_violation';
    END IF;

    SELECT v.id, v.case_id, v.evaluation_seq, v.supervisor_gate_required, v.evaluated_by INTO e
      FROM public.meter_correction_evaluations v
     WHERE v.id = NEW.evaluation_id AND v.tenant_id = NEW.tenant_id;
    IF e.id IS NULL OR e.case_id <> c.id THEN
        RAISE EXCEPTION USING
            MESSAGE = format('meter correction approval: evaluation %s is not an evaluation of case %s', NEW.evaluation_id, c.id),
            ERRCODE = 'restrict_violation';
    END IF;
    IF EXISTS (SELECT 1 FROM public.meter_correction_evaluations v2
                WHERE v2.case_id = c.id AND v2.evaluation_seq > e.evaluation_seq) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('meter correction approval: evaluation %s has been superseded by a later evaluation — approve the current one', e.id),
            ERRCODE = 'restrict_violation';
    END IF;
    IF NOT e.supervisor_gate_required THEN
        RAISE EXCEPTION USING
            MESSAGE = format('meter correction approval: evaluation %s does not carry the R-36 gate — there is nothing to approve', e.id),
            ERRCODE = 'restrict_violation';
    END IF;
    IF NOT public.session_is_supervisor() THEN
        RAISE EXCEPTION USING
            MESSAGE = 'meter correction approval: R-36 approval needs a supervisor (tenant_admin or platform administrator)',
            ERRCODE = 'insufficient_privilege';
    END IF;
    IF v_user IS NULL OR v_user IS NOT DISTINCT FROM c.opened_by OR v_user IS NOT DISTINCT FROM e.evaluated_by THEN
        RAISE EXCEPTION USING
            MESSAGE = 'meter correction approval: the approver must be identified and must be neither the person who opened the case nor the person who evaluated it — approving one''s own charge is not an approval',
            ERRCODE = 'insufficient_privilege';
    END IF;

    NEW.approved_by := v_user;
    NEW.approved_at := now();
    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.enforce_meter_correction_approval() IS
    'v5.4.2-13 (R-36). BEFORE INSERT on meter_correction_approvals: the case is open (locked FOR NO KEY UPDATE); the evaluation is this case''s latest and carries the gate; the session is a supervisor who is neither the case''s opener nor the evaluation''s author; who and when are stamped.';

DROP TRIGGER IF EXISTS a_enforce_meter_correction_approval ON public.meter_correction_approvals;
CREATE TRIGGER a_enforce_meter_correction_approval BEFORE INSERT ON public.meter_correction_approvals
    FOR EACH ROW EXECUTE FUNCTION public.enforce_meter_correction_approval();
DROP TRIGGER IF EXISTS append_only ON public.meter_correction_approvals;
CREATE TRIGGER append_only BEFORE UPDATE OR DELETE ON public.meter_correction_approvals
    FOR EACH ROW EXECUTE FUNCTION public.enforce_append_only();
DROP TRIGGER IF EXISTS no_truncate ON public.meter_correction_approvals;
CREATE TRIGGER no_truncate BEFORE TRUNCATE ON public.meter_correction_approvals
    FOR EACH STATEMENT EXECUTE FUNCTION public.enforce_no_hard_delete();
ALTER TABLE public.meter_correction_approvals ENABLE ALWAYS TRIGGER a_enforce_meter_correction_approval;
ALTER TABLE public.meter_correction_approvals ENABLE ALWAYS TRIGGER append_only;
ALTER TABLE public.meter_correction_approvals ENABLE ALWAYS TRIGGER no_truncate;

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

DROP TRIGGER IF EXISTS z_meter_correction_approval_after ON public.meter_correction_approvals;
CREATE TRIGGER z_meter_correction_approval_after AFTER INSERT ON public.meter_correction_approvals
    FOR EACH ROW EXECUTE FUNCTION public.meter_correction_approval_after();
ALTER TABLE public.meter_correction_approvals ENABLE ALWAYS TRIGGER z_meter_correction_approval_after;

COMMENT ON TABLE public.meter_correction_approvals IS
    'A-2 (v5.4.2-13), R-36. A supervisor''s approval of ONE evaluation that carries the transitional gate (an adverse meter_error correction on a date-only migrated test or no test, inside cutover + the six-month reach). Does not carry over to a re-evaluation. Approver stamped; never the case''s opener or the evaluation''s author. Append-only.';


-- ----------------------------------------------------------------------------
-- 11. Holds — the only exception to the refund duty (R-37(c))
-- ----------------------------------------------------------------------------
-- Where a meter ran FAST, the refund back to the window is mandatory (R-37:
-- no override in the favourable direction). The one exception is a stretch
-- of the window for which TALLY HOLDS NO INVOICE on that meter — the
-- correction cannot be computed from a bill Tally does not have. That is a
-- HOLD, not a decline: it sits on a standing surface, does not block the
-- rest of the correction, and closes only by completing the correction or,
-- for the second code alone, by a gated unrecoverable disposition.
--
-- Two codes, no 'other', no free text, and both conditions checked by the
-- database, never asserted by an operator:
--   legacy_records_not_loaded — the stretch ends before the tenant's
--     cutover, so the tenant billed it before Tally and the records exist in
--     its legacy system. Cannot close as unrecoverable: it closes when the
--     records are loaded (the bills then exist and the hold completes).
--   predecessor_records_unavailable — the stretch ends before the tenant
--     acquired the premise the meter then served, so a prior owner billed
--     it. May close as unrecoverable, only with a supervisor, an artifact
--     reference and the counsel-referral flag (successor liability, R-37
--     counsel bundle item 3).
--
-- SELF-LAPSE. Every hold needs a stretch with no Tally invoice on the meter,
-- inside the window. Once a meter has six months of Tally billing, no such
-- stretch exists and no hold can be opened — the favourable direction then
-- has no decline path at all, enforced by the condition, not by operators.

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
        CHECK (((status <> 'unrecoverable'::text)
             OR ((hold_code = 'predecessor_records_unavailable'::text)
                 AND (closure_artifact_ref ~ '[[:alnum:]]'::text)
                 AND counsel_referral)))
);

CREATE INDEX IF NOT EXISTS idx_meter_correction_holds_tenant ON public.meter_correction_holds USING btree (tenant_id);

-- No two holds of a case cover the same day — except a COMPLETED one, whose
-- days are covered by bills, not by the hold (review round 1, Opus): if those
-- bills are later voided the days need holding again, and a completed hold
-- must not stand in the way. Dropped and re-added so a re-apply over an
-- earlier shape takes the predicate.
ALTER TABLE public.meter_correction_holds DROP CONSTRAINT IF EXISTS meter_correction_holds_no_overlap;
ALTER TABLE public.meter_correction_holds ADD CONSTRAINT meter_correction_holds_no_overlap
    EXCLUDE USING gist (case_id WITH =, daterange(range_start, range_end, '[]') WITH &&)
    WHERE ((status <> 'completed'::text));

ALTER TABLE public.meter_correction_holds ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.meter_correction_holds FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_isolation ON public.meter_correction_holds;
CREATE POLICY tenant_isolation ON public.meter_correction_holds USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));

REVOKE DELETE, TRUNCATE ON public.meter_correction_holds FROM tally_app;

-- True when Tally holds an issued invoice on this meter for any day of the
-- range. The evaluation's own definition of "billed".
CREATE OR REPLACE FUNCTION public.meter_correction_range_billed(
        p_tenant_id uuid, p_meter_id uuid, p_start date, p_end date)
    RETURNS boolean
    LANGUAGE sql
    STABLE
    SET search_path = public, pg_temp
    AS $$
    SELECT EXISTS (SELECT 1 FROM public.meter_correction_billed_periods(p_tenant_id, p_meter_id, p_start, p_end + 1));
$$;

-- True when every day of the range is covered by one.
CREATE OR REPLACE FUNCTION public.meter_correction_range_fully_billed(
        p_tenant_id uuid, p_meter_id uuid, p_start date, p_end date)
    RETURNS boolean
    LANGUAGE sql
    STABLE
    SET search_path = public, pg_temp
    AS $$
    SELECT NOT EXISTS (
        SELECT 1 FROM generate_series(p_start, p_end, interval '1 day') AS d(day)
         WHERE NOT EXISTS (
             SELECT 1 FROM public.meter_correction_billed_periods(p_tenant_id, p_meter_id, p_start, p_end + 1) b
              WHERE d.day::date BETWEEN b.period_start AND b.period_end));
$$;

CREATE OR REPLACE FUNCTION public.enforce_meter_correction_hold() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    c       record;
    e       record;
    v_user  uuid;
    v_cut   date;
    v_acq   record;
    v_fence timestamptz;
BEGIN
    BEGIN
        v_user := NULLIF(current_setting('app.user_id', true), '')::uuid;
    EXCEPTION WHEN OTHERS THEN
        v_user := NULL;
    END;

    IF TG_OP = 'UPDATE' THEN
        IF OLD.status <> 'open' THEN
            RAISE EXCEPTION USING
                MESSAGE = format('hold %s is closed (%s) — a closed hold does not change', OLD.id, OLD.status),
                ERRCODE = 'restrict_violation';
        END IF;
        IF NEW.id IS DISTINCT FROM OLD.id OR NEW.tenant_id IS DISTINCT FROM OLD.tenant_id
           OR NEW.case_id IS DISTINCT FROM OLD.case_id
           OR NEW.range_start IS DISTINCT FROM OLD.range_start OR NEW.range_end IS DISTINCT FROM OLD.range_end
           OR NEW.hold_code IS DISTINCT FROM OLD.hold_code OR NEW.acquisition_id IS DISTINCT FROM OLD.acquisition_id
           OR NEW.opened_at IS DISTINCT FROM OLD.opened_at OR NEW.opened_by IS DISTINCT FROM OLD.opened_by
           OR NEW.status = 'open' THEN
            RAISE EXCEPTION USING
                MESSAGE = format('hold %s: a hold''s range, code and opening are fixed; the only change is its closure (completed, or unrecoverable for a predecessor hold)', OLD.id),
                ERRCODE = 'restrict_violation';
        END IF;
        -- Serialise with the case's freeze and evaluations (round 1, Fable).
        SELECT mc.meter_id, mc.tenant_id INTO c FROM public.meter_correction_cases mc
         WHERE mc.id = OLD.case_id AND mc.tenant_id = OLD.tenant_id
           FOR NO KEY UPDATE;
        IF NEW.status = 'completed' THEN
            IF NOT public.meter_correction_range_fully_billed(OLD.tenant_id, c.meter_id, OLD.range_start, OLD.range_end) THEN
                RAISE EXCEPTION USING
                    MESSAGE = format('hold %s: it completes when Tally holds the bills for %s..%s on this meter — some days are still unbilled (R-37(c): the records are loaded or the billed units entered)', OLD.id, OLD.range_start, OLD.range_end),
                    ERRCODE = 'restrict_violation',
                    HINT = 'Load the legacy or predecessor bills for the range, then re-evaluate the case so they are included, and complete the hold.';
            END IF;
        ELSE  -- unrecoverable
            IF OLD.hold_code <> 'predecessor_records_unavailable' THEN
                RAISE EXCEPTION USING
                    MESSAGE = format('hold %s: a legacy_records_not_loaded hold cannot close as unrecoverable — the tenant billed that period and holds its records (R-37(c))', OLD.id),
                    ERRCODE = 'restrict_violation';
            END IF;
            IF NOT public.session_is_supervisor() THEN
                RAISE EXCEPTION USING
                    MESSAGE = format('hold %s: an unrecoverable closure needs a supervisor (R-37(c))', OLD.id),
                    ERRCODE = 'insufficient_privilege';
            END IF;
        END IF;
        NEW.closed_at := now();
        NEW.closed_by := v_user;
        RETURN NEW;
    END IF;

    -- INSERT
    IF NEW.status <> 'open' OR NEW.closed_at IS NOT NULL OR NEW.closed_by IS NOT NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = 'hold: a hold is born open; its closure is stamped by the database',
            ERRCODE = 'restrict_violation';
    END IF;

    SELECT mc.id, mc.tenant_id, mc.meter_id, mc.status, mc.cause, mc.direction, mc.anchor_date INTO c
      FROM public.meter_correction_cases mc
     WHERE mc.id = NEW.case_id AND mc.tenant_id = NEW.tenant_id
       FOR NO KEY UPDATE;
    IF c.id IS NULL OR c.status <> 'open' THEN
        RAISE EXCEPTION USING
            MESSAGE = format('hold: case %s is not an open case in this session', NEW.case_id),
            ERRCODE = 'restrict_violation';
    END IF;
    IF c.cause <> 'meter_error' OR c.direction <> 'customer_owed' THEN
        RAISE EXCEPTION USING
            MESSAGE = format('hold: case %s is not a fast-meter correction — a hold is the exception to the mandatory refund of §7.45(7)(B)(v)(I), and no other correction carries that duty (R-27 / R-37: meter_error only)', c.id),
            ERRCODE = 'restrict_violation';
    END IF;

    SELECT v.window_start INTO e
      FROM public.meter_correction_evaluations v
     WHERE v.case_id = c.id ORDER BY v.evaluation_seq DESC LIMIT 1;
    IF e.window_start IS NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('hold: case %s has no evaluated window yet — evaluate it first, so the hold can be checked against the window', c.id),
            ERRCODE = 'restrict_violation';
    END IF;
    IF NEW.range_start < e.window_start OR NEW.range_end >= c.anchor_date THEN
        RAISE EXCEPTION USING
            MESSAGE = format('hold: %s..%s is not inside the window %s..%s — only an in-window stretch carries the refund duty a hold defers', NEW.range_start, NEW.range_end, e.window_start, c.anchor_date - 1),
            ERRCODE = 'restrict_violation';
    END IF;
    IF public.meter_correction_range_billed(c.tenant_id, c.meter_id, NEW.range_start, NEW.range_end) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('hold: Tally holds an invoice on this meter within %s..%s — a billed period is corrected from its bill, never held (R-37(c): only a period with no Tally invoice)', NEW.range_start, NEW.range_end),
            ERRCODE = 'restrict_violation';
    END IF;

    IF NEW.hold_code = 'legacy_records_not_loaded' THEN
        SELECT t.cutover_date INTO v_cut FROM public.tenants t WHERE t.id = c.tenant_id;
        IF v_cut IS NULL OR NEW.range_end >= v_cut THEN
            RAISE EXCEPTION USING
                MESSAGE = format('hold: legacy_records_not_loaded covers only periods the tenant billed before its Tally cutover (%s) — %s..%s is not one', coalesce(v_cut::text, 'not set'), NEW.range_start, NEW.range_end),
                ERRCODE = 'restrict_violation';
        END IF;
        IF NEW.acquisition_id IS NOT NULL THEN
            RAISE EXCEPTION USING MESSAGE = 'hold: a legacy hold cites no acquisition', ERRCODE = 'restrict_violation';
        END IF;
    ELSE
        -- The meter's deployment covering the whole stretch, at a premise
        -- acquired from a prior owner after the stretch ended — both recorded
        -- no later than the finding (meter_correction_evidence_fence).
        v_fence := public.meter_correction_evidence_fence(c.id);
        SELECT a.id, a.acquired_on INTO v_acq
          FROM public.meter_deployments d
          JOIN public.service_location_acquisitions a
            ON a.location_id = d.location_id AND a.tenant_id = d.tenant_id
         WHERE d.meter_id = c.meter_id AND d.tenant_id = c.tenant_id
           AND d.install_date <= NEW.range_start
           AND (d.removal_date IS NULL OR d.removal_date > NEW.range_end)
           AND a.acquired_on > NEW.range_end
           -- both facts on record before the finding (round 1, Opus F3c)
           AND d.created_at <= v_fence
           AND a.recorded_at <= v_fence
         LIMIT 1;
        IF v_acq.id IS NULL THEN
            RAISE EXCEPTION USING
                MESSAGE = format('hold: predecessor_records_unavailable needs the meter to have been deployed through %s..%s at a premise the tenant acquired from a prior owner after that stretch — none is recorded', NEW.range_start, NEW.range_end),
                ERRCODE = 'restrict_violation',
                HINT = 'Record the acquisition in service_location_acquisitions and the deployment in meter_deployments.';
        END IF;
        NEW.acquisition_id := v_acq.id;
    END IF;

    NEW.opened_at := now();
    NEW.opened_by := v_user;
    NEW.counsel_referral := coalesce(NEW.counsel_referral, false);
    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.enforce_meter_correction_hold() IS
    'v5.4.2-13 (R-37(c)). BEFORE INSERT OR UPDATE on meter_correction_holds. INSERT: only on an open fast-meter meter_error case (locked); inside its latest evaluated window; only where Tally holds no invoice on the meter for any day of the range; legacy_records_not_loaded only before the tenant''s cutover; predecessor_records_unavailable only where a recorded deployment covered the range at a premise acquired after it (acquisition_id set by the database); opening stamped. UPDATE: only an open hold closes — completed when Tally now holds bills for every day of the range, unrecoverable only for a predecessor hold, from a supervisor, with an artifact reference and the counsel-referral flag; closure stamped; nothing else moves.';

DROP TRIGGER IF EXISTS a_enforce_meter_correction_hold ON public.meter_correction_holds;
CREATE TRIGGER a_enforce_meter_correction_hold BEFORE INSERT OR UPDATE ON public.meter_correction_holds
    FOR EACH ROW EXECUTE FUNCTION public.enforce_meter_correction_hold();
ALTER TABLE public.meter_correction_holds ENABLE ALWAYS TRIGGER a_enforce_meter_correction_hold;
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
    'A-2 (v5.4.2-13), R-37(c). The only exception to the mandatory refund on a fast meter: an in-window stretch for which Tally holds no invoice on that meter. Two codes, both database-validated — legacy_records_not_loaded (before cutover; closes only by completion) and predecessor_records_unavailable (before the premise''s acquisition; may close unrecoverable with a supervisor, an artifact and the counsel flag). Does not block the rest of the correction. Self-lapsing: once the window is fully billed in Tally, no hold can open. Standing surface: meter_correction_open_holds.';


-- ----------------------------------------------------------------------------
-- 12. The freeze (R-38)
-- ----------------------------------------------------------------------------
-- The cause and the anchor freeze when the evidence computed from them is
-- frozen. Freezing a case pins its latest evaluation; afterwards the case
-- changes only by unfreezing (discard and recompute). The freeze is REFUSED
-- when:
--   * the case has never been evaluated;
--   * the evaluation no longer describes the world — anything it was
--     computed from has moved: the cause, the test, the anchor, the governing
--     test (a test entered late, D-5), the deployments, the cap rows, the
--     tenant's limit or class mode, or the billed periods themselves (a bill
--     voided or issued since). One comparison, against the stored fingerprint;
--   * the evaluation carries R-36's gate and no qualifying supervisor
--     approved it;
--   * a fast-meter case leaves in-window days uncovered — days the meter was
--     in service that neither an evaluated period nor a hold covers. A day
--     counts unless it lies in a RECORDED gap (a deployment of the meter had
--     ended and none covers it); days before the first recorded deployment
--     always count, because that deployment may only mark when the meter was
--     entered into Tally. That is under-reach, and R-37 allows no override.

CREATE OR REPLACE FUNCTION public.meter_correction_uncovered_days(p_evaluation_id uuid)
    RETURNS integer
    LANGUAGE plpgsql
    STABLE
    SET search_path = public, pg_temp
    AS $$
DECLARE
    e       record;
    v_rec   timestamptz;
    v_n     integer;
BEGIN
    SELECT v.id, v.tenant_id, v.case_id, v.cause, v.direction, v.window_start, v.anchor_date, mc.meter_id, mc.discovering_test_id
      INTO e
      FROM public.meter_correction_evaluations v
      JOIN public.meter_correction_cases mc ON mc.id = v.case_id
     WHERE v.id = p_evaluation_id;
    IF e.id IS NULL OR e.cause <> 'meter_error' OR e.direction <> 'customer_owed' OR e.window_start IS NULL THEN
        RETURN 0;
    END IF;
    v_rec := public.meter_correction_evidence_fence(e.case_id);

    SELECT count(*) INTO v_n
      FROM generate_series(e.window_start, e.anchor_date - 1, interval '1 day') AS g(day)
     WHERE NOT EXISTS (SELECT 1 FROM public.meter_correction_period_evidence p
                        WHERE p.evaluation_id = e.id
                          AND g.day::date BETWEEN p.period_start AND p.period_end)
       -- a COMPLETED hold covers nothing: its days are covered by bills, or
       -- by nothing if those bills were voided (round 1, Opus F5)
       AND NOT EXISTS (SELECT 1 FROM public.meter_correction_holds h
                        WHERE h.case_id = e.case_id AND h.status <> 'completed'
                          AND g.day::date BETWEEN h.range_start AND h.range_end)
       -- A day is out of service only inside a RECORDED gap: no deployment
       -- covers it and an earlier one had ended. Days before the meter's
       -- first recorded deployment are never excused — that deployment may be
       -- the day the meter was entered into Tally, not the day it went in.
       -- Everything is as it stood when the fault was first on record: a
       -- deployment created later does not exist here, and a removal recorded
       -- later has not happened (round 2, both reviewers — a backdated
       -- removal of the fast meter's own deployment, written after the test,
       -- turned the unbilled stretch into a "gap"). A removal the application
       -- recorded must be STRICTLY before: one written in the same
       -- transaction as the test shares its now() (round 3, Fable).
       AND NOT (
            NOT EXISTS (SELECT 1 FROM public.meter_deployments d
                         WHERE d.meter_id = e.meter_id AND d.tenant_id = e.tenant_id
                           AND d.created_at <= v_rec
                           AND g.day::date >= d.install_date
                           AND (d.removal_date IS NULL OR g.day::date < d.removal_date
                                OR d.removal_recorded_at >= v_rec
                                OR (d.removal_recorded_at IS NULL AND d.created_at > v_rec)))
        AND EXISTS (SELECT 1 FROM public.meter_deployments d
                     WHERE d.meter_id = e.meter_id AND d.tenant_id = e.tenant_id
                       AND d.created_at <= v_rec
                       AND d.removal_date IS NOT NULL
                       AND d.removal_date <= g.day::date
                       AND CASE WHEN d.removal_recorded_at IS NULL THEN d.created_at <= v_rec
                                ELSE d.removal_recorded_at < v_rec END));
    RETURN v_n;
END;
$$;

COMMENT ON FUNCTION public.meter_correction_uncovered_days(uuid) IS
    'v5.4.2-13 (R-37). For a fast-meter meter_error evaluation: the number of days in [window_start, anchor) on which the meter was in service — every day except those inside a recorded gap (after a deployment of it ended and before another began, per deployments recorded no later than the discovering test); days before its first recorded deployment are never excused that neither an evaluated period nor a hold of the case covers. Zero for every other case. The freeze requires zero — that is the under-reach check with no override.';

CREATE OR REPLACE FUNCTION public.meter_correction_freeze_check(p_case_id uuid)
    RETURNS uuid
    LANGUAGE plpgsql
    STABLE
    SET search_path = public, pg_temp
    AS $$
DECLARE
    e       record;
    v_now   jsonb;
    v_gap   integer;
BEGIN
    SELECT v.id, v.inputs, v.inputs_fingerprint, v.supervisor_gate_required INTO e
      FROM public.meter_correction_evaluations v
     WHERE v.case_id = p_case_id ORDER BY v.evaluation_seq DESC LIMIT 1;
    IF e.id IS NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('meter correction case %s: it has not been evaluated — there is no evidence to freeze', p_case_id),
            ERRCODE = 'restrict_violation';
    END IF;

    v_now := public.meter_correction_inputs(p_case_id);
    IF v_now ->> 'discovering_test_superseded_by' IS NOT NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('meter correction case %s: its discovering test has been corrected (by %s) — re-point the case at the correcting test and re-evaluate, or withdraw it', p_case_id, v_now ->> 'discovering_test_superseded_by'),
            ERRCODE = 'restrict_violation';
    END IF;
    IF md5(v_now::text) <> e.inputs_fingerprint THEN
        RAISE EXCEPTION USING
            MESSAGE = format('meter correction case %s: its latest evaluation (%s) no longer describes it — something it was computed from has changed since (the cause, the test, the governing test, the deployments, a cap row, the tenant''s limit or class mode, or the billed periods). Re-evaluate, then freeze (R-38)', p_case_id, e.id),
            ERRCODE = 'restrict_violation',
            DETAIL = format('evaluated: %s  now: %s', e.inputs - 'periods', v_now - 'periods');
    END IF;

    IF e.supervisor_gate_required
       AND NOT EXISTS (SELECT 1 FROM public.meter_correction_approvals a WHERE a.evaluation_id = e.id) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('meter correction case %s: this adverse meter-error correction rests on a date-only migrated test or on no test, inside the tenant''s first six months of reach after cutover — a supervisor must approve evaluation %s first (R-36)', p_case_id, e.id),
            ERRCODE = 'restrict_violation',
            HINT = 'INSERT INTO public.meter_correction_approvals (tenant_id, case_id, evaluation_id, note) VALUES (...) from a supervisor''s session — not the case''s opener or the evaluation''s author.';
    END IF;

    v_gap := public.meter_correction_uncovered_days(e.id);
    IF v_gap > 0 THEN
        RAISE EXCEPTION USING
            MESSAGE = format('meter correction case %s: %s in-window day(s) of this fast meter''s service are neither corrected nor held — where a meter ran fast the refund back to the window is mandatory, and there is no override (§7.45(7)(B)(v)(I); R-37)', p_case_id, v_gap),
            ERRCODE = 'restrict_violation',
            HINT = 'Every in-window period Tally billed is corrected; a stretch Tally never billed is held (meter_correction_holds) with a database-validated code.';
    END IF;

    RETURN e.id;
END;
$$;

COMMENT ON FUNCTION public.meter_correction_freeze_check(uuid) IS
    'v5.4.2-13 (R-36, R-37, R-38). Called by the case guard on open → frozen. Returns the latest evaluation, after proving: it exists; meter_correction_inputs() still yields its fingerprint (nothing it was computed from has moved — including a late-entered test, D-5); a carried R-36 gate has its approval; a fast-meter case has no uncovered in-window day. Raises otherwise.';


-- ----------------------------------------------------------------------------
-- 13. The test-history couplings (-12 residual R7)
-- ----------------------------------------------------------------------------
-- -12 recorded three facts for this patch to act on:
--   * supervisor_gate (R-36) — enforced by the freeze (section 12);
--   * entered_out_of_order (D-5: accept a late test and flag it) — the test
--     is accepted; the governing test it displaces changes the fingerprint,
--     so an open case cannot freeze on stale evidence, and a frozen case
--     shows as stale on meter_correction_case_status;
--   * "a test an evidence row cites cannot be superseded silently" (brief
--     §3.6) — here. A test a FROZEN case rests on, as its discovering test
--     or its frozen evaluation's governing test, cannot be superseded until
--     the case is unfrozen. Unfreeze, correct the test, re-evaluate, freeze:
--     the old window stays beside the new in the evaluations.

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
-- 14. Standing surfaces (R-27's "detection without a surface" problem)
-- ----------------------------------------------------------------------------
-- Invoker-rights views: each tenant sees only its own rows. The governing
-- evaluation of a case is its frozen one if frozen, else its latest.

CREATE OR REPLACE FUNCTION public.meter_correction_evaluation_current(p_evaluation_id uuid)
    RETURNS boolean
    LANGUAGE plpgsql
    STABLE
    SET search_path = public, pg_temp
    AS $$
DECLARE
    e record;
BEGIN
    SELECT v.case_id, v.inputs_fingerprint INTO e
      FROM public.meter_correction_evaluations v WHERE v.id = p_evaluation_id;
    IF e.case_id IS NULL THEN
        RETURN NULL;
    END IF;
    RETURN md5(public.meter_correction_inputs(e.case_id)::text) = e.inputs_fingerprint;
EXCEPTION WHEN OTHERS THEN
    -- A surface must not fail for every case because one case cannot be
    -- recomputed; NULL reads as "cannot tell", which the view reports.
    RETURN NULL;
END;
$$;

COMMENT ON FUNCTION public.meter_correction_evaluation_current(uuid) IS
    'v5.4.2-13. True when this evaluation''s inputs are unchanged (the freeze''s test); false when something moved — a late test (D-5), a voided or new bill, a cap row, the tenant''s limit; NULL when the case cannot be recomputed at all (the surface reports it rather than failing for every case).';

CREATE OR REPLACE VIEW public.meter_correction_case_status
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
       gov.window_start,
       public.meter_correction_evaluation_current(gov.id) AS evaluation_current,
       EXISTS (SELECT 1 FROM public.meter_tests s WHERE s.supersedes_test_id = mc.discovering_test_id) AS discovering_test_superseded,
       (gov.supervisor_gate_required
        AND NOT EXISTS (SELECT 1 FROM public.meter_correction_approvals a WHERE a.evaluation_id = gov.id)) AS gate_pending,
       gov.prior_test_failed,
       gov.governing_entered_out_of_order,
       public.meter_correction_uncovered_days(gov.id) AS uncovered_days,
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
    'A-2 (v5.4.2-13). One row per meter correction case, from its governing evaluation (frozen, else latest): whether that evaluation still describes the world (false after a late-entered test, D-5, or a bill voided or issued since; a FROZEN case reading false is stale and must be unfrozen and re-evaluated before -14 can post it), whether an R-36 approval is pending, the R-34 prior-test-failed flag, uncovered in-window days on a fast meter, open holds and the dollars forfeited. Invoker rights.';

CREATE OR REPLACE VIEW public.backbilling_forfeitures
    WITH (security_invoker = true) AS
SELECT mc.id AS case_id,
       mc.tenant_id,
       mc.meter_id,
       mc.cause,
       mc.status AS case_status,
       p.evaluation_id,
       p.invoice_id,
       p.customer_id,
       p.location_id,
       p.period_start,
       p.period_end,
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
 WHERE p.disposition = 'forfeited';

COMMENT ON VIEW public.backbilling_forfeitures IS
    'A-2 (v5.4.2-13), R-32 / R-37(d). Every billed period a case''s governing evaluation forfeited — straddling or preceding the statutory window, before the tenant''s own adverse limit, or before a discovery cause''s claimed start — with the days inside the window and the dollars given up. "So the cost is visible rather than silent." Invoker rights.';

CREATE OR REPLACE VIEW public.meter_correction_open_holds
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
    'A-2 (v5.4.2-13), R-37(c). The standing surface of open holds — refunds deferred because Tally holds no bill for the stretch. A hold closes only by completion or, for a predecessor hold, by the gated unrecoverable disposition. Invoker rights.';

-- A fast finding nobody opened a case for (review round 1, Opus). Not
-- opening a case is the quietest way to decline a mandatory refund, and no
-- guard can refuse an act that never happens — so it is a standing surface:
-- every standing (not superseded) test that found a meter FAST, with no live
-- case resting on it.
CREATE OR REPLACE VIEW public.meter_fast_findings_without_case
    WITH (security_invoker = true) AS
SELECT t.id AS meter_test_id,
       t.tenant_id,
       t.meter_id,
       t.test_date,
       t.record_basis,
       t.max_abs_error_pct,
       t.recorded_at,
       (CURRENT_DATE - t.test_date) AS days_since_test
  FROM public.meter_tests t
 WHERE t.outcome = 'fast'
   AND NOT EXISTS (SELECT 1 FROM public.meter_tests s WHERE s.supersedes_test_id = t.id)
   AND NOT EXISTS (SELECT 1 FROM public.meter_correction_cases mc
                    WHERE mc.discovering_test_id = t.id AND mc.status <> 'withdrawn');

COMMENT ON VIEW public.meter_fast_findings_without_case IS
    'A-2 (v5.4.2-13), R-37 / R-27. Every standing test that found a meter more than 2% FAST with no live meter correction case resting on it — the refund §7.45(7)(B)(v)(I) makes mandatory, not yet taken up. Not opening a case is a decline no trigger can refuse, so it is surfaced instead. Invoker rights.';

REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.meter_correction_case_status, public.backbilling_forfeitures, public.meter_correction_open_holds, public.meter_fast_findings_without_case FROM tally_app;
GRANT SELECT ON public.meter_correction_case_status, public.backbilling_forfeitures, public.meter_correction_open_holds, public.meter_fast_findings_without_case TO tally_app;

-- A-23 note: no function in this patch is SECURITY DEFINER. Every one runs
-- with the caller's rights under RLS; the pins are public, pg_temp for
-- consistency with the ~190 existing trigger functions (-11 residual).
GRANT EXECUTE ON FUNCTION
    public.session_is_supervisor(),
    public.backbilling_customer_class(uuid),
    public.backbilling_resolve_cap(uuid, uuid, text, text, text),
    public.backbilling_invoice_charge(uuid),
    public.backbilling_units_match(uuid, uuid),
    public.meter_correction_billed_periods(uuid, uuid, date, date),
    public.meter_correction_evidence_fence(uuid),
    public.meter_correction_inputs(uuid),
    public.meter_correction_range_billed(uuid, uuid, date, date),
    public.meter_correction_range_fully_billed(uuid, uuid, date, date),
    public.meter_correction_uncovered_days(uuid),
    public.meter_correction_freeze_check(uuid),
    public.meter_correction_evaluation_current(uuid)
  TO tally_app;


-- ----------------------------------------------------------------------------
-- 15. Residuals, stated
-- ----------------------------------------------------------------------------
-- R1. NOTHING POSTS. A frozen case charges and refunds nobody until -14
--     builds delivery on Kyle's OQ-1. Until then a fast meter's refund is
--     computed, frozen and visible on the surfaces, and still owed.
--
-- R2. THE AMOUNT IS THE CALLER'S. The database checks the periods named, the
--     precision and (for a test-anchored case) the sign; it does not derive
--     the dollars from the test's error, because the method — which load
--     point's error, weighted how — is not ruled. -14 must post exactly the
--     included amounts of the frozen evaluation.
--
-- R3. A DOWNWARD VOID-AND-REISSUE IS NOT GATED. R-33 takes meter errors off
--     that path in both directions, but a reissue that reduces the charge
--     cannot be told apart from a legitimate wrong-read correction, so the
--     gate engages only on an increase.
--
-- R4. ONLY TEXAS GAS IS SEEDED. Anything else resolves no cap row and
--     refuses. A tenant created after this patch has no rows until onboarding
--     (the owner) seeds them.
--
-- R5. THE PERIOD SET FOLLOWS THE CASE-LEVEL RULE. Which periods are evaluated
--     is set by the protected-class rule at the meter's CURRENT premise; each
--     period then answers to its own rule. A municipal row LONGER than the
--     state default at a premise the meter left would not widen the set —
--     under-reach in a case no tenant has yet (municipal rows are platform-
--     written on evidence of an ordinance, R-26).
--
-- R6. R-37(a)'S SERVICE-START BOUND IS APPLIED TO A REFUND ONLY WHEN
--     CORROBORATED — an engineering reading of Kyle's ruling, put to him in
--     the OQ-1 brief. Found while building the battery: sync_meter_
--     deployments() creates every meter's first deployment from
--     meters.start_date, which defaults to CURRENT_DATE, so on a migrated
--     meter "the start of its deployments" is its onboarding date. The bound
--     shortens a refund only where another meter served that premise INTO the
--     window and came out on or before this one went in (round 1, Fable: a
--     predecessor removed years ago corroborated every later onboarding
--     date); it shortens a charge whenever a deployment is recorded. Cost: a
--     genuinely new meter at a new premise with a migrated start reaches back
--     further for a refund than R-37(a) requires — toward the customer, and
--     bounded by six months.
--     WHAT THE FENCE DOES AND DOES NOT CATCH. Deployments and acquisitions
--     count only if recorded no later than the fault was first on record
--     (meter_correction_evidence_fence: the first row of the discovering
--     test's chain, or any defective test within the window's reach), and a
--     removal counts only if IT was recorded by then (removal_recorded_at,
--     round 2) — so neither re-pointing a case at a fresh copy of its test
--     (round 1) nor pulling the failed meter with a backdated removal after
--     the test (round 2) changes what the finding rests on. What is NOT
--     caught: a history fabricated BEFORE any defective test is recorded.
--     It needs no write to meter_deployments at all — a phantom meter
--     inserted with an old start_date, then set inactive with a chosen
--     removal_date, becomes a closed predecessor row through
--     sync_meter_deployments() (round 2, Fable). One INSERT and one UPDATE
--     on meters, before the test; the deployment rows carry no trace of that
--     origin. Recorded, not closed: closing it needs the meters row's own
--     start and removal dates to become evidence, which is the meter
--     lifecycle's patch, not A-2's. Existing rows keep whatever created_at
--     they had.
--     SAME TRANSACTION (round 3, Fable): now() is one instant per
--     transaction, so a removal the application writes in the transaction
--     that records the test would tie with it. Application-recorded removals
--     must be strictly before the fence; owner-loaded rows (no stamp) keep
--     <=, because a history load and its test are routinely one transaction.
--     COST (round 2): a removal recorded AFTER the test with a truthful
--     earlier date also does not end the deployment — a meter pulled on
--     05-01, bench-tested 06-15 and removed in Tally only afterwards leaves
--     05-01..06-14 uncovered, and the case cannot freeze until the owner
--     repairs the removal. Toward the customer; the ordinary order of work
--     (remove, then test) avoids it.

-- R7. THE APPROVAL AND TAMPER GATES REST ON users.role AND app.user_id. Only a
--     supervisor makes a supervisor now (section 2), but the demotion of a
--     supervisor, and app.user_id being set by trusted code, remain as -12
--     residual R16 describes. The gates name tally_app where they exempt the
--     owner; a second application role would be unwatched (-12 R14).
--
-- R8. THE ENFORCEABLE BOUND IS RECORDED, NOT WIRED. Each evidence row carries
--     its enforceable_scope (never = not disconnectable, F-1). Carrying that
--     onto the posted charge and into collections is -14 and Family 9.
--
-- R9. invoices.amount_due IS NOT DERIVED FROM invoice_line_items. The rebill
--     gate measures the greater of the two on both sides; the schema-wide
--     invariant belongs to the invoice, not to A-2.
--
-- R10. THE UNITS TEST COMPARES SUMS PER METER. Two bills with the same total
--     units per meter but different reads within the period pass. Price
--     errors on correct units are what the cause means; a bill that moved
--     usage between its own lines on one meter is not caught.
--
-- R11. estimation_catchup, unbilled_service AND THE R-30 READ CLASSIFICATION
--     HAVE NO PATH YET. Their cap rows are seeded; OQ-1 decides where they
--     travel, and the classification lands with estimation_catchup's path.
--
-- R12. THE FINGERPRINT IS jsonb's CANONICAL TEXT. Deterministic for equal
--     documents in one server version; an upgrade that changed jsonb text
--     output would read every open evaluation as stale — refusing freezes,
--     the safe direction — until re-evaluated.
--
-- R13. A HOLD'S WINDOW IS CHECKED AT OPENING. A later re-evaluation with a
--     shorter window leaves an earlier hold partly outside it; the hold still
--     counts toward coverage only for the days it covers, and it closes on
--     its own terms.
--
-- R14. meter_correction_case_status COMPUTES PER ROW. Each row recomputes the
--     case's inputs and counts uncovered days; fine for a tenant's handful of
--     open cases, not a reporting query across years of closed ones.
--
-- R15. THE FREEZE LOCKS THE CASE ROW, NOT THE WORLD. Evaluation, approval,
--     hold opening and completion, and freeze all serialise on the case row
--     (FOR NO KEY UPDATE / the UPDATE itself); a correction of a test a case
--     rests on reads the meter's cases FOR SHARE before -12 locks the meter,
--     so every path takes cases before the meter and none inverts (round 2;
--     round 1's order deadlocked). THE INVARIANT RESTS ON TRIGGER NAMES
--     (round 3, Fable): BEFORE triggers fire in name order, and
--     a0_enforce_test_supersession_vs_frozen_case must sort before any
--     meter_tests trigger that locks the meter — a later patch adding one
--     named a0_… or earlier re-opens the deadlock. What is still not locked out: a bill
--     issued, a deployment entered or an unrelated test recorded on the
--     meter at the same moment as a freeze. The case freezes on the evidence
--     it could see and meter_correction_case_status then reads
--     evaluation_current = false. -14's posting must re-derive the
--     fingerprint and refuse a stale frozen case — the freeze is a
--     checkpoint, not the last check.

-- R16. A REMOVAL'S DATE IS STILL THE CALLER'S. Round 2 stamps WHEN a removal
--     was recorded, and a removal recorded after a finding is ignored for
--     that finding. A removal recorded before the finding with a false date
--     — the pre-finding fabrication of R6 — is not caught.

-- R18. R-36's GATE IS APPLIED TO ADVERSE meter_error ONLY. Its text also
--     names corrections "raised on a meter flagged attested_none or unknown",
--     with no cause qualifier; an adverse non_registering_meter on such a
--     meter is not gated. The reasoning — R-36 protects a window whose start
--     a weak prior test can move, and the (v)(II) window is a fixed three
--     months from the test — is an engineering reading for Kyle to confirm
--     (round 1, both reviewers).
--
-- R19. THE CUSTOMER CLASS IS READ AS OF NOW. backbilling_customer_class()
--     reads customers.customer_type today, not as of the period. Constant
--     under the v1 default mode; under explicit_class a reclassified customer
--     changes an evaluation's per-period rule (and its fingerprint).
--
-- R20. meter_deployments' OWN LINKS, AND invoice_line_items.meter_id, ARE
--     TENANT-BLIND (round 4, Fable: a line may name another tenant's meter).
--     The reissue gate counts a line on a meter not at one of the
--     customer's premises as unattributed money, so it cannot hide an
--     increase there; the FKs themselves are for the tenant-blind-link patch.
-- R20a. meter_deployments' OWN LINKS ARE TENANT-BLIND. Its meter_id and
--     location_id foreign keys are single-column (two of the 229); every
--     query in this patch also filters on tenant_id, so no cross-tenant read
--     happens, but the table is now evidence and the repair is due.
--
-- R21. THE REISSUE GATE ERRS TOWARD REFUSING. It matches any overlapping
--     period on the same premise, a shared meter, or (for a bill with no
--     premise) the customer, and compares at that scope — shared meters by
--     their lines, otherwise whole charges (round 2). Deliberately not per
--     day, because prorating lets a cheap new month dilute an overcharge
--     (round 2, declined). So after a void these ordinary bills are refused
--     when they charge more than the voided bill: one spanning the voided
--     month and a new one; a full-month bill after a short voided one (a
--     one-day duplicate); a consolidated bill with no shared meter that
--     covers more than the voided bill did. Each is billed as a correction
--     of the voided days, or the voided bill is re-issued at its own scope.
--     A bill that names a premise always compares whole charges (round 4),
--     so a single-premise bill that legitimately carries another premise's
--     meter at a lower price plus its own is refused when its total exceeds
--     the voided bill — contrived, and toward refusal.
--     "Charges more than ANY matched voided bill" (round 3) also means:
--     after a lawful correction ($100 → $150) is itself voided, re-issuing
--     it at $150 is gated again and needs its correction target and cause —
--     toward refusal, on purpose (a higher voided bill, mis-keyed or planted,
--     otherwise excused the rebill of its neighbour's days).
--     A consolidated PARENT whose line re-sums a live correction of a
--     voided bill (C-B2's $150 against voided O-MAY's $100) is refused the
--     same way: the gate sees the voided bill, not the correction that
--     superseded it. How consolidated parents and children are built is not
--     defined yet (no battery exercises them); when it is, the gate should
--     read the children, and compare a parent against its issued children.

-- ----------------------------------------------------------------------------
-- 16. The AC-32 tail
-- ----------------------------------------------------------------------------
-- Seven new tenant tables and four views, each born leaky by the default
-- grants. The assertion raises if any lacks RLS, FORCE, the single canonical
-- policy, or invoker rights.

SELECT public.assert_tenant_isolation_invariants();

-- ============================================================================
-- END PATCH v5.4.2-13
-- ============================================================================
