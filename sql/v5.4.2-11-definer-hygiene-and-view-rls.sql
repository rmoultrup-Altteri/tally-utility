-- ============================================================================
-- PATCH v5.4.2-11 — definer hygiene: two views that bypass RLS, four
--                    SECURITY DEFINER helpers, the blanket EXECUTE grant,
--                    and a domain for anomalies.entity_type
--                    (schema-parity-plan Phase 4, Appendix A-23 items 1c/1d)
-- ============================================================================
-- Authority:   Appendix A-23 (1c): "three SECURITY DEFINER functions carry no
--              search_path pin and read their tables unqualified"; A-23 (1d)
--              (tally_app must never hold TEMP / CREATE / TRIGGER).
--              GBM application/configurable-rules/decision-tables/
--              exception-threshold-and-routing.md, note 2: "anomalies.
--              entity_type has no CHECK constraint ... two detectors can write
--              'billing_run' and 'billing_runs' and row 1 silently stops
--              matching half the time. Suggested resolution: constrain it to
--              the entity set the detectors actually target."
--              Ryan, 2026-09-08: (a) get_correction_rate_date is re-issued
--              with invoker rights rather than having its EXECUTE revoked —
--              a revoke would delete a capability its own COMMENT documents
--              for the billing engine; (b) the blanket PUBLIC EXECUTE grant
--              is cleaned up in this patch, not deferred; (c) the
--              entity_type domain is the fifteen entities the existing
--              anomaly_type values actually target — adhoc_charge and
--              service_order are NOT seeded (nothing implies them today, and
--              widening a CHECK later is one line where narrowing it is a
--              data cleanup).
--
-- The hole, in one sentence: `tally` is a superuser with BYPASSRLS, so
-- anything that runs with `tally`'s rights — a view without security_invoker,
-- a SECURITY DEFINER function — reads every tenant's rows, and two views and
-- one resolver were doing exactly that.
--
-- Verified on the v5.4.2-10 build before drafting, not assumed:
--   pg_roles:  tally  rolsuper=t  rolbypassrls=t   |  tally_app  f  f
--   pg_class:  adhoc_void_pending_review, void_released_read_alerts
--              reloptions = (none), relowner = tally, granted arwd to
--              tally_app.  The other three views carry security_invoker=true.
--              FORCE RLS on the base tables does NOT save this: BYPASSRLS
--              outranks FORCE.
--   pg_proc:   all five SECURITY DEFINER functions have proacl '=X/tally' —
--              i.e. PUBLIC holds EXECUTE. The queue item as originally
--              written ("revoke tally_app's direct EXECUTE on
--              get_correction_rate_date") would have been a no-op; tally_app
--              would have kept it through PUBLIC.
--
-- ----------------------------------------------------------------------------
-- What lands
-- ----------------------------------------------------------------------------
--
--   1. THE LEAK. adhoc_void_pending_review and void_released_read_alerts get
--      security_invoker = true. Both are owned by tally (BYPASSRLS), both are
--      readable by tally_app, and neither carried the option — so today
--      tally_app selects every tenant's void-review queue and void-released
--      read alerts through them. tally_app already holds SELECT on every base
--      table (adhoc_charges, invoices, correction_run_targets,
--      meter_readings), so the option changes visibility, not access.
--
--   2. THE RLS HELPERS STAY DEFINER, AND GET PINNED. get_user_tenant_id() and
--      is_platform_admin() must keep definer rights — they are called from the
--      tenant_isolation policy on every table, including the `users` policy
--      itself, so invoker rights would recurse. What they must not keep is an
--      unpinned, unqualified body. Both are re-issued with `public.users`
--      qualified and SET search_path = ''.
--
--      A definer function here runs as a SUPERUSER. '' (not public, pg_temp)
--      is the right pin for that: an elevated body must resolve nothing
--      through a mutable path. Invoker-rights functions in this patch keep the
--      project's ordinary `public, pg_temp` (item 4) — they carry no
--      elevation, and tally_app holds no TEMP (A-23 1d), so pg_temp shadowing
--      is unreachable.
--
--      The pin costs no PLAN quality: a SECURITY DEFINER function is never
--      inlined by the optimizer regardless of proconfig, so these two were
--      already non-inlinable, and on an index path the helper's value becomes
--      a scan key evaluated once.
--
--      It does cost something on a SEQUENTIAL scan, where the policy is a
--      per-row Filter and each call now pushes and pops a GUC. The first
--      draft of this header asserted "evaluated once per query, not once per
--      row"; that was reasoning, not measurement, and it is wrong for the
--      seq-scan case (round 1, Fable LOW). Measured over 100k customers,
--      50/50 across two tenants, index paths disabled, second run of each:
--      260 ms on the -10 build, 377 ms patched — about +45%, ~1.2 us/row.
--      Correctness is unaffected and the pin stays; if this ever bites, the
--      answer is a per-transaction cached tenant id, not an unpinned
--      superuser-rights function.
--
--   3. A-23 (1c) RULE LIFT — the reason the pin is not cosmetic. Because
--      these two were unpinned, they inherited the CALLER's search_path, and
--      their unqualified `FROM users` then failed to resolve. Measured on the
--      -10 build:
--
--         SET ROLE tally_app; SET search_path = '';
--         SELECT count(*) FROM public.anomalies;
--         ERROR:  relation "users" does not exist
--         CONTEXT:  SQL function "get_user_tenant_id" during startup
--
--      That is: NO session pinned to '' could read ANY RLS table, which is
--      precisely why trigger functions in this schema were required to pin
--      `public, pg_temp` rather than '' (memory: strict-pin-vs-rls-helpers).
--      After this patch a trigger function MAY pin ''. The existing ones are
--      deliberately NOT re-pinned here — that is a separate, mechanical patch
--      over ~190 trigger functions and does not belong in a hygiene change.
--
--   4. validate_custom_fields() → SECURITY INVOKER, qualified, pinned, AND an
--      explicit tenant refusal. It has no caller anywhere in tu.sql — it is
--      app-facing — and as a definer it read any tenant's field definitions by
--      id. That is a DISCLOSURE, not merely a hygiene issue: measured on the -10
--      build (tests/v5.4.2-11/probe-pre-11.sql), tenant 1 calling it with
--      tenant 2's id got back tenant 2's field keys and labels:
--        [{"error":"Required field is missing","field":"t2_badge","label":"T2 Badge"}]
--      Invoker rights alone are NOT enough either: under RLS a foreign
--      p_tenant_id then matches zero definition rows, the FOR loop never
--      runs, and the function returns '[]' — "no validation errors", i.e. a
--      false VALID for another tenant's entity. So the function now refuses a
--      p_tenant_id that is not the caller's, unless the caller is a platform
--      admin or a superuser.
--
--      The refusal is written NULL-safely (IS DISTINCT FROM, and
--      is_platform_admin() first): get_user_tenant_id() returns NULL when
--      app.user_id is unset, and `p_tenant_id <> NULL` is NULL, which an IF
--      treats as false — the refusal would have been skipped in exactly the
--      unauthenticated case it exists for (memory: blank-checks-whitelist-alnum,
--      "coalesce the NULL leg in trigger IFs").
--
--   5. get_correction_rate_date() → SECURITY INVOKER, body qualified, pin kept
--      at `public, pg_temp`. As a definer it resolved ANY tenant's recorded
--      rate-date election from a bare (run id, invoice id) pair.
--
--      Invoker rights cost its in-schema caller nothing:
--      calculation_snapshot_coordinate_violation() (v5.4.2-10, invoker) has
--      already proved, under the caller's own rights, that the billing run is
--      visible, that the replaced invoice is visible and same-tenant, and that
--      a correction_run_targets row exists for the pair — all three tables
--      this resolver reads — BEFORE it calls it. And the new behaviour for a
--      foreign id is the contract the function's own COMMENT already
--      documents: "Returns NULL if target not found".
--
--   6. THE BLANKET GRANT. EXECUTE on all five SECURITY DEFINER functions is
--      revoked FROM PUBLIC and granted explicitly to tally_app (which already
--      held an explicit grant on each; the revoke is what changes). PUBLIC
--      EXECUTE on a definer function that runs as a superuser is a standing
--      invitation, and it silently defeated the revoke-shaped fix.
--
--   7. anomalies.entity_type gets a domain — fifteen values, SINGULAR.
--
--      Singular is settled by evidence, not taste: GBM's routing table writes
--      'billing_run' and 'invoice'; the only writer in this schema
--      (enforce_service_type_change, v5.4.2-03) writes 'rate_schedule' and
--      embeds it singular in dedup_key; and account_ledger.reference_type —
--      the closest analogue, also a polymorphic discriminator — is singular
--      across all eleven of its values. (custom_field_definitions.entity_type
--      is plural, but it keys form definitions to TABLES, a different job.)
--
--      The set is derived from the 37 anomaly_type values already in the
--      table's CHECK, keeping only names with a real table:
--
--        meter_reading        high_usage, low_usage, zero_usage,
--                             negative_consumption, meter_rollover
--        meter                possible_leak, stuck_meter, tamper_detected,
--                             endpoint_offline, endpoint_swap_unreported,
--                             missing_reading, estimated_streak,
--                             repeated_access_issue
--                             (endpoints live in meter_endpoint_history;
--                              an endpoint anomaly attaches to its meter)
--        service_location     unbilled_service, unbilled_usage,
--                             address_mismatch, disconnect_protection_expiring
--        invoice              partial_period_anomaly
--        invoice_line_item    rate_mismatch
--        rate_schedule        rate_schedule_mismatch,
--                             reference_correction_review  <- the live writer
--        billing_run          billing_run_exception, revenue_leakage
--        customer             duplicate_account, stale_account
--        payment              unusual_payment_pattern, multiple_nsf_pattern
--        payment_method       auto_pay_failure_streak, payment_method_expiring
--        customer_credit      credit_balance_stale
--        deposit              deposit_refund_overdue
--        escheatment_event    escheatment_due, escheatment_overdue
--        customer_tax_exemption   tax_exemption_expired
--        import_job           import_column_outlier_pattern,
--                             import_low_confidence_mapping
--        (any)                other
--
--      NOT seeded (Ryan's call): adhoc_charge, service_order. No current
--      anomaly_type implies either. The asymmetry decides it — widening the
--      CHECK later is a one-line ALTER; narrowing it later means cleaning up
--      rows that are already routed.
--
--      Self-verifying: the patch REFUSES (does not warn) if any existing row
--      carries a value outside the domain, and names the offenders. On the
--      -10 build anomalies is empty; a real deployment is where this earns
--      its keep.
--
--   8. FOUR MATERIALIZED VIEWS lose their grant to tally_app (section 5c).
--      Added in round 1 — both reviewers found this independently, and it is
--      the same class of hole as item 1, one relkind over. compliance_,
--      credit_aging_, payment_health_ and usage_statistics are owned by
--      tally, refreshed under BYPASSRLS, carry tenant_id, and were granted
--      to tally_app by tu.sql's blanket ALL TABLES grant. A matview can take
--      neither security_invoker nor an RLS policy, so the grant is the only
--      lever. Revoked outright (Ryan, 2026-09-09); residual R5 records the
--      read path that is now absent by decision.
--
--      Why items 1 and 7's checks did not catch it: BOTH filtered
--      `relkind = 'v'`, which by construction excludes `relkind = 'm'`. The
--      patch printed "verified — 5 views run with invoker rights" while four
--      larger holes stood one relkind away. That is worse than an unchecked
--      hole, because it buys confidence. Section 7.1b now asserts the matview
--      grant directly, and battery A3 was widened the same way.
--
--   9. THE DEFAULT PRIVILEGE behind item 6 (section 5b). Revoking EXECUTE
--      from PUBLIC on five named functions does not stop the SIXTH: PostgreSQL
--      grants PUBLIC EXECUTE on every new function by default, so the next
--      definer written here — or a DROP + CREATE of one of the five — reopens
--      what item 6 closed. Reproduced in round 1 (Fable MEDIUM): a definer
--      created straight after the patch was PUBLIC-executable while the
--      patch's own NOTICE still read "no definer function is executable by
--      PUBLIC". Section 5b revokes the default; 7.4c re-states 7.4b's
--      assertion by SHAPE rather than by name, and 7.4d checks the default
--      itself. The schema-qualified form of that REVOKE is a silent no-op —
--      section 5b carries the measurement and the reason.
--
--  10. THE CHECKS BECOME REUSABLE (section 7). Added in round 2, when both
--      reviewers independently reached the same weakness from different ends:
--      a one-shot verification block certifies only the instant it ran, and
--      tu.sql's blanket `ALTER DEFAULT PRIVILEGES ... ON TABLES TO tally_app`
--      means the NEXT view is born owner-rights and the NEXT matview is born
--      tally_app-readable. Section 5b's own fix can likewise be reopened by a
--      per-schema default that does not exist yet when this patch runs.
--
--      So the assertions live in public.assert_tenant_isolation_invariants(),
--      which every future patch calls in its tail and the container build runs
--      last. Two round-2 fixes are folded into it: has_any_column_privilege
--      instead of has_table_privilege (a COLUMN-level grant on a matview
--      passed the round-2 check and still read across tenants), and the
--      default-privilege test now covers the per-schema row as well as the
--      global one, scoped to the role whose default it is.
--
--      Round 3 added the surface it is named for: TABLES (check 7.0). Both
--      reviewers found this independently — Codex HIGH, Fable MEDIUM — and it
--      is the same "one relkind over" shape as the original matview finding,
--      two steps out: v -> m -> r. Measured before the clause existed, a new
--      table with a tenant_id column and no RLS returned BOTH tenants' rows
--      to a tenant-1 session while the assertion passed clean. Forgetting
--      ENABLE / FORCE ROW LEVEL SECURITY and a policy on a new table is the
--      most ordinary migration mistake there is, and the blanket ALL TABLES
--      grant means such a table is readable by tally_app from birth.
--      (Ryan, 2026-09-09: fold it in rather than defer to a -12 — a gate that
--      is silent on the main surface invites exactly the misplaced confidence
--      the relkind = 'v' filter already cost this patch once.)
--
--      Design limit, stated so it is not mistaken for coverage: the key is
--      the COLUMN NAME `tenant_id`. A future tenant-scoped table whose
--      discriminator is called something else (org_id, company_id) is outside
--      check 7.0 by construction and would be silent. tu.sql has no such
--      table; if one is ever added, the column name is the contract and 7.0
--      is where that decision gets written down.
--
--      Proven to CATCH drift, not merely to pass — every shape measured
--      against the finished patch: a newly created matview, a newly created
--      view, a per-schema PUBLIC EXECUTE default, a column-level grant on a
--      matview, a new table without RLS, RLS disabled on an existing table, a
--      second permissive USING (true) policy, and a partition child that
--      inherits none of its parent's row security. Each makes it raise;
--      battery group G repeats all of them.
--
-- ----------------------------------------------------------------------------
-- What deliberately does NOT land (residuals, stated so they are not lost)
-- ----------------------------------------------------------------------------
--
--   R1. void_invoice() keeps SECURITY DEFINER and its `public, pg_temp` pin
--       rather than moving to ''. It must stay definer (it writes ledger and
--       event rows and carries its own explicit cross-tenant check at Step
--       1.1), and its body is fully qualified — checked directly in round 1:
--       zero unqualified relation references across the ~300-line prosrc.
--       That, not the TEMP revocation, is why the pin is safe (see the
--       caveat below); re-pinning it to '' would mean re-proving every type,
--       operator and function reference for no reachable gain.
--
--       CAVEAT on the TEMP premise, found independently by both reviewers.
--       tu.sql revokes TEMP using current_database() (18694-18695), and
--       CREATE DATABASE ... TEMPLATE does NOT copy datacl. So:
--           has_database_privilege('tally_app','tally','TEMP')  = false
--           has_database_privilege('tally_app',<any clone>,'TEMP') = true
--       Every battery in this project, this one included, runs on a clone and
--       therefore runs WITH TEMP held — not the deployed shape. No finding
--       depends on it here (R1 rests on qualification instead), but any future
--       guard that leans on "tally_app cannot create objects" is not being
--       tested by these batteries. battery-11 now asserts the TEMP state it is
--       actually running under so the gap is visible rather than assumed.
--
--   R2. The ~190 existing trigger functions are not re-pinned to '' (item 3).
--
--   R3. This patch does not audit non-definer functions for PUBLIC EXECUTE.
--       The five definers are the ones where PUBLIC EXECUTE is a privilege
--       escalation rather than an ordinary grant.
--
--   R4. anomalies.entity_id remains a bare uuid with no FK and no per-type
--       referential check — the domain constrains the discriminator, not the
--       pointer. A polymorphic FK needs the routing feature to exist first.
--
--   R6. A PERMISSIVE policy created with NEITHER `USING` nor `WITH CHECK`
--       (`CREATE POLICY tenant_isolation ON t;` — valid syntax, both polqual
--       and polwithcheck NULL) passes check 7.0: the independent test skips
--       both disjuncts when both are NULL. Verified fail-CLOSED, not
--       fail-open — such a table returns ZERO rows to tally_app rather than
--       every tenant's (Codex, round 5, raised for completeness and
--       explicitly not as a blocker). The table is misconfigured and the
--       application would silently see nothing, which is a correctness
--       problem for whoever writes it, not a tenant-isolation hole. Left as a
--       residual rather than folded: it arrived after both reviewers had
--       approved this file, and a check that requires at least one non-NULL
--       expression is a behavioural change that would deserve its own round.
--
--   R7. Checks 7.1b and 7.4b/c name `tally_app` and PUBLIC specifically. A
--       matview or definer granted to some future second application role —
--       a reporting login, say — would be silent (both reviewers, rounds 2
--       and 3). The shape that survives a third role is "no grantee other
--       than the owner" via aclexplode. Not adopted: no such role exists, and
--       writing the check against a hypothetical role's name is speculation.
--       If one is ever added, these two checks are where it must be named.
--
--   R5. NEW (5c): the four statistics matviews are now readable by nobody but
--       the owner. There is no tenant-scoped read path to replace them, by
--       decision — no application exists to have one. When the dashboard is
--       built, the read path is designed with it. The options considered and
--       set aside: an owner-rights wrapper view per matview carrying an
--       explicit tenant predicate (a hand-maintained second copy of the
--       tenant_isolation policy, running with the same owner rights as the
--       hole being closed); a security_invoker wrapper (impossible — an
--       invoker wrapper requires the CALLER to hold SELECT on the matview,
--       which is the grant being removed); per-tenant matviews (unbounded).
--       refresh_statistics_views() (tu.sql:646) is invoker-rights and REFRESH
--       requires ownership, so tally_app could never refresh them anyway —
--       the leak was read-only of the last owner refresh. Confirmed directly
--       in round 2: REFRESH as tally_app fails with "must be owner of
--       materialized view" regardless of any grant.
--
--       AND THE REFRESH PATH IS ITSELF BROKEN, for everyone, and always has
--       been (round 2, Fable; reproduced). refresh_statistics_views() declares
--       RETURNS TABLE(view_name text, ...), which makes view_name a PL/pgSQL
--       OUT variable, and its two ON CONFLICT (view_name) clauses then fail:
--           SELECT * FROM public.refresh_statistics_views(true);
--           ERROR:  column reference "view_name" is ambiguous
--       So the four matviews were only ever populated by a hand-run REFRESH,
--       and nothing in tu.sql reads them (grepped: zero FROM/JOIN references).
--       The revoke therefore took nothing that worked. The one-line fix
--       (#variable_conflict use_column, or renaming the OUT column) is NOT
--       applied here — it is an unrelated pre-existing defect and this is a
--       hygiene patch (Ryan, 2026-09-09). Whoever builds the dashboard fixes
--       the read path and the refresh path together; both are recorded here so
--       neither is rediscovered.
--
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 1. The leak: two owner-rights views that bypass RLS
-- ----------------------------------------------------------------------------

ALTER VIEW public.adhoc_void_pending_review  SET (security_invoker = true);
ALTER VIEW public.void_released_read_alerts  SET (security_invoker = true);

COMMENT ON VIEW public.adhoc_void_pending_review IS
    'Adhoc charges parked by a void, with operator guidance and correction-run context. security_invoker since v5.4.2-11: the view is owned by a BYPASSRLS superuser, so without it every tenant''s parked charges were readable by tally_app through this view.';
COMMENT ON VIEW public.void_released_read_alerts IS
    'Meter reads released back to the pool by a void, flagged for re-billing attention. security_invoker since v5.4.2-11 (same reason as adhoc_void_pending_review).';


-- ----------------------------------------------------------------------------
-- 2. The RLS helpers: still SECURITY DEFINER (the users policy calls them),
--    now qualified and pinned to '' — they run as a superuser.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.get_user_tenant_id() RETURNS uuid
    LANGUAGE sql
    STABLE
    SECURITY DEFINER
    SET search_path = ''
    AS $$
    SELECT tenant_id FROM public.users WHERE id = current_setting('app.user_id', true)::uuid
$$;

COMMENT ON FUNCTION public.get_user_tenant_id() IS
    'The calling user''s tenant, from app.user_id. SECURITY DEFINER by necessity — the tenant_isolation policy on public.users itself calls it, so invoker rights would recurse. Pinned to an empty search_path with public.users qualified (v5.4.2-11): it executes with superuser rights, and while it was unpinned it inherited the caller''s search_path, so any session pinned to '''' failed to read ANY RLS table (A-23 1c). Returns NULL when app.user_id is unset or names no user; an app.user_id set to the EMPTY STRING raises invalid_text_representation from the ::uuid cast rather than returning NULL (pre-existing, unchanged here, and fail-closed — but a connection pooler that clears the setting with '''' turns every RLS read into an error rather than an empty result).';

CREATE OR REPLACE FUNCTION public.is_platform_admin() RETURNS boolean
    LANGUAGE sql
    STABLE
    SECURITY DEFINER
    SET search_path = ''
    AS $$
    SELECT EXISTS(SELECT 1 FROM public.users WHERE id = current_setting('app.user_id', true)::uuid AND role = 'platform_admin')
$$;

COMMENT ON FUNCTION public.is_platform_admin() IS
    'True when app.user_id names a platform_admin. SECURITY DEFINER by necessity (same reason as get_user_tenant_id) and pinned to an empty search_path with public.users qualified since v5.4.2-11 (A-23 1c). Never returns NULL: an unset or unknown app.user_id is false.';


-- ----------------------------------------------------------------------------
-- 3. validate_custom_fields: invoker rights, qualified, pinned, and an
--    explicit tenant refusal (invoker rights alone return a false VALID).
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.validate_custom_fields(p_tenant_id uuid, p_entity_type text, p_metadata jsonb)
    RETURNS jsonb
    LANGUAGE plpgsql
    STABLE
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_field RECORD;
    v_errors JSONB := '[]';
    v_value TEXT;
    v_value_jsonb JSONB;
    v_pattern TEXT;
    v_min NUMERIC;
    v_max NUMERIC;
    v_min_length INT;
    v_max_length INT;
    v_min_date DATE;
    v_max_date DATE;
    v_elem JSONB;
BEGIN
    -- v5.4.2-11: the tenant refusal. This function used to run SECURITY
    -- DEFINER and would validate against any tenant's definitions. Invoker
    -- rights alone do not fix that: under RLS a foreign p_tenant_id matches
    -- zero definition rows, the loop below never runs, and '[]' comes back —
    -- "no errors", a false VALID for another tenant's entity. Refuse instead.
    --
    -- NULL-safe on purpose: get_user_tenant_id() is NULL when app.user_id is
    -- unset, and `p_tenant_id <> NULL` is NULL, which IF treats as false —
    -- the unauthenticated caller would have walked straight through the very
    -- check written to stop them.
    IF p_tenant_id IS NULL THEN
        RAISE EXCEPTION 'validate_custom_fields: p_tenant_id is required'
            USING ERRCODE = 'null_value_not_allowed';
    END IF;

    IF NOT public.is_platform_admin()
       AND NOT (SELECT r.rolsuper FROM pg_catalog.pg_roles r WHERE r.rolname = current_user)
       AND p_tenant_id IS DISTINCT FROM public.get_user_tenant_id()
    THEN
        RAISE EXCEPTION
            'validate_custom_fields: tenant % is not the caller''s tenant. Custom-field definitions are tenant-scoped; validating against another tenant''s definitions (or against none, which returns "valid") is refused.',
            p_tenant_id
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    FOR v_field IN
        SELECT field_key, field_label, field_type, is_required, validation_rules, options
        FROM public.custom_field_definitions
        WHERE tenant_id = p_tenant_id AND entity_type = p_entity_type AND status = 'active'
    LOOP
        v_value := p_metadata ->> v_field.field_key;
        v_value_jsonb := p_metadata -> v_field.field_key;

        -- Required check
        IF v_field.is_required AND (v_value IS NULL OR v_value = '') THEN
            v_errors := v_errors || jsonb_build_object('field', v_field.field_key, 'label', v_field.field_label, 'error', 'Required field is missing');
            CONTINUE;  -- skip further checks if missing
        END IF;

        -- Skip the rest if value is empty (already passed required check)
        IF v_value IS NULL OR v_value = '' THEN
            CONTINUE;
        END IF;

        -- Type-specific format validators
        IF v_field.field_type = 'number' AND v_value !~ '^-?\d+$' THEN
            v_errors := v_errors || jsonb_build_object('field', v_field.field_key, 'label', v_field.field_label, 'error', 'Must be a whole number');
        END IF;

        IF v_field.field_type = 'decimal' AND v_value !~ '^-?\d+(\.\d+)?$' THEN
            v_errors := v_errors || jsonb_build_object('field', v_field.field_key, 'label', v_field.field_label, 'error', 'Must be a decimal number');
        END IF;

        IF v_field.field_type = 'date' THEN
            BEGIN
                PERFORM v_value::DATE;
            EXCEPTION WHEN OTHERS THEN
                v_errors := v_errors || jsonb_build_object('field', v_field.field_key, 'label', v_field.field_label, 'error', 'Must be a valid date (YYYY-MM-DD)');
            END;
        END IF;

        IF v_field.field_type = 'boolean' AND v_value NOT IN ('true','false','t','f','1','0','yes','no') THEN
            v_errors := v_errors || jsonb_build_object('field', v_field.field_key, 'label', v_field.field_label, 'error', 'Must be true or false');
        END IF;

        IF v_field.field_type = 'email' AND v_value !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' THEN
            v_errors := v_errors || jsonb_build_object('field', v_field.field_key, 'label', v_field.field_label, 'error', 'Must be a valid email');
        END IF;

        IF v_field.field_type = 'phone' AND v_value !~ '^[\d\s\-\+\(\)\.]{7,20}$' THEN
            v_errors := v_errors || jsonb_build_object('field', v_field.field_key, 'label', v_field.field_label, 'error', 'Must be a valid phone number');
        END IF;

        IF v_field.field_type = 'url' AND v_value !~* '^https?://[^\s]+$' THEN
            v_errors := v_errors || jsonb_build_object('field', v_field.field_key, 'label', v_field.field_label, 'error', 'Must be a valid URL (http:// or https://)');
        END IF;

        -- Single-select: value must match one of the options
        IF v_field.field_type = 'select' THEN
            IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_field.options) opt WHERE opt ->> 'value' = v_value) THEN
                v_errors := v_errors || jsonb_build_object('field', v_field.field_key, 'label', v_field.field_label, 'error', 'Invalid option selected');
            END IF;
        END IF;

        -- Multi-select: value should be a JSONB array; each element must match options
        IF v_field.field_type = 'multi_select' THEN
            IF v_value_jsonb IS NULL OR jsonb_typeof(v_value_jsonb) != 'array' THEN
                v_errors := v_errors || jsonb_build_object('field', v_field.field_key, 'label', v_field.field_label, 'error', 'Must be an array of selected values');
            ELSE
                FOR v_elem IN SELECT * FROM jsonb_array_elements(v_value_jsonb)
                LOOP
                    IF NOT EXISTS (
                        SELECT 1 FROM jsonb_array_elements(v_field.options) opt
                        WHERE opt ->> 'value' = v_elem #>> '{}'
                    ) THEN
                        v_errors := v_errors || jsonb_build_object('field', v_field.field_key, 'label', v_field.field_label, 'error', 'One or more selected values are not valid options');
                        EXIT;  -- one error per field is enough
                    END IF;
                END LOOP;
            END IF;
        END IF;

        -- Custom validation_rules (pattern, min/max, minLength/maxLength)
        IF v_field.validation_rules IS NOT NULL AND v_field.validation_rules != '{}'::jsonb THEN
            -- Pattern (regex)
            v_pattern := v_field.validation_rules ->> 'pattern';
            IF v_pattern IS NOT NULL AND v_value !~ v_pattern THEN
                v_errors := v_errors || jsonb_build_object('field', v_field.field_key, 'label', v_field.field_label, 'error', 'Value does not match required pattern');
            END IF;

            -- Numeric min/max for number/decimal
            IF v_field.field_type IN ('number','decimal') THEN
                BEGIN
                    v_min := (v_field.validation_rules ->> 'min')::NUMERIC;
                    IF v_min IS NOT NULL AND v_value::NUMERIC < v_min THEN
                        v_errors := v_errors || jsonb_build_object('field', v_field.field_key, 'label', v_field.field_label, 'error', format('Must be at least %s', v_min));
                    END IF;
                EXCEPTION WHEN OTHERS THEN NULL; END;

                BEGIN
                    v_max := (v_field.validation_rules ->> 'max')::NUMERIC;
                    IF v_max IS NOT NULL AND v_value::NUMERIC > v_max THEN
                        v_errors := v_errors || jsonb_build_object('field', v_field.field_key, 'label', v_field.field_label, 'error', format('Must be at most %s', v_max));
                    END IF;
                EXCEPTION WHEN OTHERS THEN NULL; END;
            END IF;

            -- Date min/max
            IF v_field.field_type = 'date' THEN
                BEGIN
                    v_min_date := (v_field.validation_rules ->> 'min')::DATE;
                    IF v_min_date IS NOT NULL AND v_value::DATE < v_min_date THEN
                        v_errors := v_errors || jsonb_build_object('field', v_field.field_key, 'label', v_field.field_label, 'error', format('Date must be on or after %s', v_min_date));
                    END IF;
                EXCEPTION WHEN OTHERS THEN NULL; END;

                BEGIN
                    v_max_date := (v_field.validation_rules ->> 'max')::DATE;
                    IF v_max_date IS NOT NULL AND v_value::DATE > v_max_date THEN
                        v_errors := v_errors || jsonb_build_object('field', v_field.field_key, 'label', v_field.field_label, 'error', format('Date must be on or before %s', v_max_date));
                    END IF;
                EXCEPTION WHEN OTHERS THEN NULL; END;
            END IF;

            -- String length bounds (text, textarea, email, phone, url)
            IF v_field.field_type IN ('text','textarea','email','phone','url') THEN
                BEGIN
                    v_min_length := (v_field.validation_rules ->> 'minLength')::INT;
                    IF v_min_length IS NOT NULL AND length(v_value) < v_min_length THEN
                        v_errors := v_errors || jsonb_build_object('field', v_field.field_key, 'label', v_field.field_label, 'error', format('Must be at least %s characters', v_min_length));
                    END IF;
                EXCEPTION WHEN OTHERS THEN NULL; END;

                BEGIN
                    v_max_length := (v_field.validation_rules ->> 'maxLength')::INT;
                    IF v_max_length IS NOT NULL AND length(v_value) > v_max_length THEN
                        v_errors := v_errors || jsonb_build_object('field', v_field.field_key, 'label', v_field.field_label, 'error', format('Must be at most %s characters', v_max_length));
                    END IF;
                EXCEPTION WHEN OTHERS THEN NULL; END;
            END IF;
        END IF;
    END LOOP;
    RETURN v_errors;
END;
$$;

COMMENT ON FUNCTION public.validate_custom_fields(p_tenant_id uuid, p_entity_type text, p_metadata jsonb) IS
    'Validates a metadata JSONB blob against a tenant''s active custom_field_definitions for an entity type; returns a JSONB array of {field, label, error} (empty array = valid). SECURITY INVOKER since v5.4.2-11 (was DEFINER, unpinned, unqualified — A-23 1c): RLS now scopes the definitions to the caller. Invoker rights alone were not enough — a foreign p_tenant_id matched no definitions and returned "[]", a false VALID — so the function REFUSES a p_tenant_id that is not the caller''s unless the caller is a platform admin or a superuser. Has no in-schema caller; this is an application entry point.';


-- ----------------------------------------------------------------------------
-- 4. get_correction_rate_date: invoker rights. Its in-schema caller has
--    already proved every row it reads is visible; its documented app-facing
--    contract ("Returns NULL if target not found") is unchanged in shape.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.get_correction_rate_date(p_billing_run_id uuid, p_voided_invoice_id uuid)
    RETURNS date
    LANGUAGE plpgsql
    STABLE
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_rate_date_mode        TEXT;
    v_rate_date_override    DATE;
    v_run_rate_mode         TEXT;
    v_voided_period_end     DATE;
BEGIN
    -- Load target-level fields in one query.
    -- v5.4.2-11: invoker rights — RLS applies, so another tenant's (run,
    -- invoice) pair is simply NOT FOUND and resolves to NULL, which is the
    -- contract this function already documented for an unknown target.
    SELECT
        crt.rate_date_mode,
        crt.rate_date_override,
        br.correction_rate_mode,
        i.period_end
    INTO
        v_rate_date_mode,
        v_rate_date_override,
        v_run_rate_mode,
        v_voided_period_end
    FROM public.correction_run_targets crt
    JOIN public.billing_runs br ON br.id = crt.billing_run_id
    JOIN public.invoices     i  ON i.id  = crt.voided_invoice_id
    WHERE crt.billing_run_id    = p_billing_run_id
      AND crt.voided_invoice_id = p_voided_invoice_id;

    IF NOT FOUND THEN
        -- Target not found, or not visible to this tenant — caller should log
        -- and substitute; do NOT pass this NULL into a *_as_of helper.
        RETURN NULL;
    END IF;

    -- Resolution order
    CASE v_rate_date_mode

        WHEN 'custom' THEN
            -- Operator-supplied explicit date (validated by CHECK constraint)
            RETURN v_rate_date_override;

        WHEN 'historical' THEN
            -- Force historical regardless of run-level mode
            RETURN v_voided_period_end;

        WHEN 'current' THEN
            -- Force current regardless of run-level mode
            RETURN CURRENT_DATE;

        WHEN 'run_default' THEN
            -- Delegate to the run-level setting
            IF v_run_rate_mode = 'current' THEN
                RETURN CURRENT_DATE;
            ELSE
                -- 'historical' is the default; covers NULL defensively
                RETURN v_voided_period_end;
            END IF;

        ELSE
            -- Unrecognised mode — safe fallback, billing engine should log
            RETURN v_voided_period_end;

    END CASE;
END;
$$;

COMMENT ON FUNCTION public.get_correction_rate_date(p_billing_run_id uuid, p_voided_invoice_id uuid) IS
    'Returns the rate effective date ceiling for Phase 5 of a correction billing run — the operator''s recorded valid-time election. Resolution: custom date > per-target historical/current > run-level default. Pass the returned date to all rate_item, rate_schedule_item, wna_monthly_adjustments and franchise_fee_rules queries as: WHERE effective_date <= get_correction_rate_date(...). SECURITY INVOKER since v5.4.2-11 (was DEFINER, which resolved ANY tenant''s election from a bare id pair): RLS now scopes it, and a target that is not visible returns NULL exactly as an absent one does. Returns NULL if the target is not found or not visible — the billing engine must substitute and log, never pass this NULL into a *_as_of helper (those RAISE on a NULL coordinate). The v5.4.2-10 caller, calculation_snapshot_coordinate_violation(), has already proved the run, the replaced invoice and the target row visible under the writer''s own rights before consulting this resolver.';


-- ----------------------------------------------------------------------------
-- 5. The blanket grant: PUBLIC holds EXECUTE on every SECURITY DEFINER
--    function in this schema. Revoke it; grant tally_app explicitly.
-- ----------------------------------------------------------------------------

REVOKE ALL ON FUNCTION public.get_user_tenant_id()                                   FROM PUBLIC;
REVOKE ALL ON FUNCTION public.is_platform_admin()                                    FROM PUBLIC;
REVOKE ALL ON FUNCTION public.validate_custom_fields(uuid, text, jsonb)              FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_correction_rate_date(uuid, uuid)                   FROM PUBLIC;
REVOKE ALL ON FUNCTION public.void_invoice(uuid, uuid, text, text, boolean)          FROM PUBLIC;

-- tally_app already held an explicit grant on each of these; re-issued so the
-- intent is legible in one place and the statements are idempotent.
-- get_user_tenant_id and is_platform_admin are named by the tenant_isolation
-- policy on every table: without EXECUTE, tally_app can read NOTHING.
GRANT EXECUTE ON FUNCTION public.get_user_tenant_id()                                TO tally_app;
GRANT EXECUTE ON FUNCTION public.is_platform_admin()                                 TO tally_app;
GRANT EXECUTE ON FUNCTION public.validate_custom_fields(uuid, text, jsonb)           TO tally_app;
GRANT EXECUTE ON FUNCTION public.get_correction_rate_date(uuid, uuid)                TO tally_app;
GRANT EXECUTE ON FUNCTION public.void_invoice(uuid, uuid, text, text, boolean)       TO tally_app;

-- 5b. The revoke above is by name, and PostgreSQL's own default is to grant
-- EXECUTE on every NEW function to PUBLIC. Without this, the next SECURITY
-- DEFINER function anyone writes — or a DROP + CREATE of one of the five —
-- silently re-opens what 5a just closed (round 1, Fable MEDIUM, reproduced:
-- a definer created immediately after this patch was PUBLIC-executable while
-- the patch's own NOTICE still read "no definer function is executable by
-- PUBLIC"). tu.sql's ALTER DEFAULT PRIVILEGES block (11388-11391) grants
-- tally_app EXECUTE but never revoked PUBLIC's.
--
-- NOTE the missing `IN SCHEMA public`, and do not "fix" it. PUBLIC's EXECUTE
-- on new functions comes from the GLOBAL (schema-less) default ACL, not the
-- per-schema one; a schema-qualified REVOKE is silently a no-op. Measured
-- while folding this finding — a function created after each variant:
--     ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ... FROM PUBLIC
--         -> pg_default_acl unchanged, new function acl '=X/tally ...',
--            PUBLIC-executable = true   (no-op)
--     ALTER DEFAULT PRIVILEGES FOR ROLE tally REVOKE ... FROM PUBLIC
--         -> global entry 'tally=X/tally', new function acl carries no '=X/',
--            PUBLIC-executable = false  (works)
-- The unqualified form covers functions this role creates in ANY schema.
-- That is wider than `public`, and intended: the migration role creates
-- nothing outside public here, and a definer dropped into another schema
-- would be exactly the case worth catching.
ALTER DEFAULT PRIVILEGES FOR ROLE tally REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;

-- ----------------------------------------------------------------------------
-- 5c. THE SECOND LEAK, found in round 1 by both reviewers independently:
--     four materialized views hand every tenant's rows to tally_app.
-- ----------------------------------------------------------------------------
-- A materialized view cannot be fixed the way items 1's views were. It holds
-- its own copy of the rows, populated by REFRESH under tally's BYPASSRLS
-- rights; PostgreSQL has no security_invoker for matviews and no row-security
-- policies on them. There is no option to set. The only lever is the grant.
--
-- Measured on the -10 build and again on the patched build before this
-- revision — one session, two relations:
--     SELECT tenant_id, customer_number FROM public.compliance_statistics;
--        -> 2 rows: MV-C1 (own tenant) and MV-C2-SECRET (tenant 2)
--     SELECT tenant_id, customer_number FROM public.customers;
--        -> 1 row  (the base table is correctly scoped)
-- The four carry tax-exemption status and expiry, disconnect-protection
-- status, NSF and payment history, credit aging, and consumption history.
--
-- tally_app reached them through tu.sql:11381's blanket
-- `GRANT ... ON ALL TABLES IN SCHEMA public` (ALL TABLES includes matviews),
-- with `arwd` — write bits it can never use, since a matview is not writable
-- and REFRESH requires ownership.
--
-- Ryan, 2026-09-09: REVOKE, do not wrap. The alternative was an owner-rights
-- view per matview carrying `is_platform_admin() OR tenant_id =
-- get_user_tenant_id()`. That preserves a dashboard read path — but no
-- application exists yet to have one, the predicate would be a second,
-- hand-maintained copy of the tenant_isolation policy, and a wrapper that
-- must run with owner rights to be useful is the same shape as the hole
-- being closed. The read path is designed when the dashboard is (residual R5).
REVOKE ALL ON public.compliance_statistics      FROM tally_app, PUBLIC;
REVOKE ALL ON public.credit_aging_statistics    FROM tally_app, PUBLIC;
REVOKE ALL ON public.payment_health_statistics  FROM tally_app, PUBLIC;
REVOKE ALL ON public.usage_statistics           FROM tally_app, PUBLIC;

COMMENT ON MATERIALIZED VIEW public.compliance_statistics IS
    'Per-customer compliance rollup (tax exemption, disconnect protection). NOT readable by tally_app since v5.4.2-11: a materialized view holds its own copy of the rows, refreshed under the owner''s BYPASSRLS rights, and can carry neither security_invoker nor an RLS policy — so any grant to the application role is a cross-tenant read. A tenant-scoped read path is designed with the dashboard that needs it.';
COMMENT ON MATERIALIZED VIEW public.credit_aging_statistics IS
    'Per-customer credit and deposit aging rollup. NOT readable by tally_app since v5.4.2-11 (same reason as compliance_statistics).';
COMMENT ON MATERIALIZED VIEW public.payment_health_statistics IS
    'Per-customer payment health rollup (NSF, autopay, method expiry). NOT readable by tally_app since v5.4.2-11 (same reason as compliance_statistics).';
COMMENT ON MATERIALIZED VIEW public.usage_statistics IS
    'Per-meter consumption rollup. NOT readable by tally_app since v5.4.2-11 (same reason as compliance_statistics).';


-- ----------------------------------------------------------------------------
-- 6. anomalies.entity_type: a domain. Self-verifying — refuse, do not warn.
-- ----------------------------------------------------------------------------

DO $$
DECLARE
    v_bad text;
BEGIN
    SELECT string_agg(DISTINCT quote_literal(a.entity_type), ', ' ORDER BY quote_literal(a.entity_type))
      INTO v_bad
      FROM public.anomalies a
     WHERE a.entity_type NOT IN (
        'customer', 'service_location', 'meter', 'meter_reading',
        'invoice', 'invoice_line_item', 'billing_run', 'rate_schedule',
        'payment', 'payment_method', 'customer_credit', 'deposit',
        'customer_tax_exemption', 'escheatment_event', 'import_job');

    IF v_bad IS NOT NULL THEN
        RAISE EXCEPTION
            'v5.4.2-11: anomalies.entity_type carries value(s) outside the domain this patch installs: %. Reclassify or resolve those rows first — the domain is deliberately the entity set the existing anomaly_type values target, and widening it is a decision, not a migration side effect.',
            v_bad
            USING ERRCODE = 'check_violation';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                    WHERE conname = 'anomalies_entity_type_check'
                      AND conrelid = 'public.anomalies'::regclass) THEN
        ALTER TABLE public.anomalies
            ADD CONSTRAINT anomalies_entity_type_check CHECK (entity_type = ANY (ARRAY[
                'customer'::text,
                'service_location'::text,
                'meter'::text,
                'meter_reading'::text,
                'invoice'::text,
                'invoice_line_item'::text,
                'billing_run'::text,
                'rate_schedule'::text,
                'payment'::text,
                'payment_method'::text,
                'customer_credit'::text,
                'deposit'::text,
                'customer_tax_exemption'::text,
                'escheatment_event'::text,
                'import_job'::text]));
    END IF;
END;
$$;

COMMENT ON COLUMN public.anomalies.entity_type IS
    'What the anomaly is attached to — the discriminator for entity_id (which carries no FK). Constrained since v5.4.2-11 to the fifteen entities the existing anomaly_type values target. SINGULAR, matching account_ledger.reference_type and the only writer in this schema (enforce_service_type_change writes ''rate_schedule''); NOT the plural table names used by custom_field_definitions.entity_type. The constraint exists because exception routing keys on this column: an unconstrained discriminator lets one detector write ''billing_run'' and another ''billing_runs'', and batch-level exceptions then silently stop reaching their queue. adhoc_charge and service_order are deliberately absent — no current anomaly_type targets either, and widening this CHECK is one line where narrowing it is a data cleanup.';


-- ----------------------------------------------------------------------------
-- 7. Self-verification, as a RE-RUNNABLE function rather than a one-shot.
--
--    Round 2 (both reviewers, from different directions) landed on the same
--    weakness: every assertion here is true when this patch applies and drifts
--    at the next CREATE. tu.sql's `ALTER DEFAULT PRIVILEGES ... ON TABLES TO
--    tally_app` (11388) covers views AND matviews, so the next matview is born
--    tally_app-readable and the next view is born owner-rights — both
--    reproduced. And section 5b's own global fix can be reopened by a
--    per-schema default (also reproduced), which a one-shot check cannot see
--    because the offending row does not exist yet when it runs.
--
--    So the checks live in public.assert_tenant_isolation_invariants(). Every
--    future patch calls it in its tail, and the container build runs it last.
--    A one-shot DO block could only ever certify the moment it executed.
--
--    The alternative — a ddl_command_end event trigger fixing each view and
--    matview as it is born — was declined (Ryan, 2026-09-09): it catches drift
--    earlier, but adds a new privileged execution surface to a patch whose
--    whole purpose is removing them. Recorded as the option not taken.
--
--    INVOKER rights on purpose: it reads only catalogs and privilege
--    functions, it must never be the thing that grants anything, and a
--    checking routine that runs elevated is the shape this patch exists to
--    remove. Owner-only by grant (see the REVOKE below) — the per-schema
--    default would otherwise hand it to tally_app automatically.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.assert_tenant_isolation_invariants() RETURNS void
    LANGUAGE plpgsql
    STABLE
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_bad     text;
    v_owner   regrole := (SELECT p.proowner::regrole FROM pg_proc p
                           WHERE p.oid = 'public.assert_tenant_isolation_invariants()'::regprocedure);
    -- The two canonical policy predicates, as pg_get_expr renders them under
    -- this function's own pin (public, pg_temp — so no schema qualification).
    c_tenant  CONSTANT text := '(is_platform_admin() OR (tenant_id = get_user_tenant_id()))';
    c_tenants CONSTANT text := '(is_platform_admin() OR (id = get_user_tenant_id()))';
BEGIN
    -- 7.0 THE TABLES. Added in round 3, found independently by both reviewers
    --     (Codex HIGH, Fable MEDIUM) — the function was named for tenant
    --     isolation and looked only at relkind 'v' and 'm'. Ordinary tables,
    --     where the customer data actually lives, were never checked, and a
    --     new table is by far the likeliest next object: tu.sql's blanket
    --     ALL TABLES grant plus ALTER DEFAULT PRIVILEGES make it readable by
    --     tally_app at birth, while ENABLE / FORCE ROW LEVEL SECURITY and a
    --     policy are things a migration author has to remember. Measured on
    --     the round-3 build before this clause existed: a new table with a
    --     tenant_id column and no RLS returned BOTH tenants' rows to a
    --     tenant-1 session while the assertion passed silently.
    --
    --     Keyed on "carries a tenant_id column", which needs no allowlist —
    --     the only three tables in public without one are tenants (checked
    --     separately below; it is keyed on id), program_types and
    --     materialized_view_refresh_log (no tenant data). relkind 'p' and its
    --     'r' children are both covered, which is what catches a PARTITION:
    --     a child inherits the column but NOT the parent's row security, and
    --     a direct read of the child bypasses the parent's policy entirely.
    --
    --     Every PERMISSIVE policy must be the canonical predicate, not merely
    --     exist: permissive policies are OR-ed, so one added `USING (true)`
    --     opens the table to every tenant while it still "has RLS and a
    --     policy". RESTRICTIVE policies are exempt — they are AND-ed and can
    --     only narrow access, never widen it, so requiring them to be
    --     canonical refused a legitimate extra guard (Codex, round 4,
    --     reproduced). The table must still carry at least one PERMISSIVE
    --     policy: with RLS on and none, everything is denied.
    --
    --     polqual AND polwithcheck are checked INDEPENDENTLY, not coalesced.
    --     The round-4 draft read `coalesce(polqual, polwithcheck)`, which
    --     never looks at WITH CHECK while USING is non-NULL — so a policy with
    --     a canonical USING and `WITH CHECK (true)` passed clean while every
    --     session could write rows tagged with ANY tenant_id. Found
    --     independently by both reviewers (Codex HIGH, Fable MEDIUM) and
    --     reproduced end to end: a tenant-1 session INSERTed a row into
    --     tenant 2, could not see it afterwards, and tenant 2 held it. It is
    --     the write-side inverse of the permissive-USING case: that one leaks
    --     reads, this one plants rows (and on UPDATE, moves a row out of its
    --     tenant). A canonical USING does not excuse a non-canonical WITH
    --     CHECK, and neither excuses the other by being absent.
    --
    --     The comparison is against pg_get_expr's rendering under this
    --     function's own pin, which is stable: schema-qualified and bare
    --     policy text converge to the same string, and a hostile caller
    --     search_path cannot change it. It is sensitive to STRUCTURE, so a
    --     semantically identical predicate written with the operands in the
    --     other order is refused (Codex, round 4). That is accepted, not
    --     fixed: it fails closed and loudly, and one canonical spelling
    --     across every policy is worth having. The HINT says so.
    SELECT string_agg(c.relname, ', ' ORDER BY c.relname) INTO v_bad
      FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname = 'public'
       AND c.relkind IN ('r', 'p', 'f')
       AND EXISTS (SELECT 1 FROM pg_attribute a
                    WHERE a.attrelid = c.oid AND a.attname = 'tenant_id' AND NOT a.attisdropped)
       AND NOT (c.relrowsecurity
                AND c.relforcerowsecurity
                AND EXISTS (SELECT 1 FROM pg_policy pol
                             WHERE pol.polrelid = c.oid AND pol.polpermissive)
                AND NOT EXISTS (SELECT 1 FROM pg_policy pol
                                 WHERE pol.polrelid = c.oid
                                   AND pol.polpermissive
                                   AND ((pol.polqual IS NOT NULL
                                         AND pg_get_expr(pol.polqual, pol.polrelid) IS DISTINCT FROM c_tenant)
                                     OR (pol.polwithcheck IS NOT NULL
                                         AND pg_get_expr(pol.polwithcheck, pol.polrelid) IS DISTINCT FROM c_tenant))));
    IF v_bad IS NOT NULL THEN
        RAISE EXCEPTION 'tenant isolation: table(s) with a tenant_id column lack RLS, FORCE, a policy, or carry a non-canonical policy: %', v_bad
            USING ERRCODE = 'insufficient_privilege',
                  HINT = 'ALTER TABLE x ENABLE ROW LEVEL SECURITY; ALTER TABLE x FORCE ROW LEVEL SECURITY; CREATE POLICY tenant_isolation ON x USING (is_platform_admin() OR tenant_id = get_user_tenant_id());  -- write the predicate in exactly that form and order: the check compares structure, so an equivalent predicate with the operands swapped is refused. Every PERMISSIVE policy must match, in BOTH its USING and its WITH CHECK (a canonical USING with WITH CHECK (true) lets any session write rows tagged with any tenant_id); RESTRICTIVE policies are exempt, they can only narrow. A partition CHILD needs its own row security; it does not inherit the parent''s. A table whose predicate must LEGITIMATELY differ is an explicit edit of this function, not a reason to weaken it.';
    END IF;

    -- 7.0b the tenants table itself — the one tenant-scoped table keyed on id
    IF NOT EXISTS (SELECT 1 FROM pg_class c
                    WHERE c.oid = 'public.tenants'::regclass
                      AND c.relrowsecurity AND c.relforcerowsecurity)
       OR EXISTS (SELECT 1 FROM pg_policy pol
                   WHERE pol.polrelid = 'public.tenants'::regclass
                     AND pol.polpermissive
                     AND ((pol.polqual IS NOT NULL
                           AND pg_get_expr(pol.polqual, pol.polrelid) IS DISTINCT FROM c_tenants)
                       OR (pol.polwithcheck IS NOT NULL
                           AND pg_get_expr(pol.polwithcheck, pol.polrelid) IS DISTINCT FROM c_tenants)))
       OR NOT EXISTS (SELECT 1 FROM pg_policy pol
                       WHERE pol.polrelid = 'public.tenants'::regclass AND pol.polpermissive) THEN
        RAISE EXCEPTION 'tenant isolation: public.tenants lacks RLS, FORCE, or its canonical id-keyed policy'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    -- 7.1 every VIEW runs with invoker rights (the owner is a BYPASSRLS superuser)
    SELECT string_agg(c.relname, ', ' ORDER BY c.relname) INTO v_bad
      FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname = 'public' AND c.relkind = 'v'
       AND coalesce((SELECT o FROM unnest(c.reloptions) o WHERE o LIKE 'security_invoker=%'), '') <> 'security_invoker=true';
    IF v_bad IS NOT NULL THEN
        RAISE EXCEPTION 'tenant isolation: view(s) run with owner rights: %', v_bad
            USING ERRCODE = 'insufficient_privilege',
                  HINT = 'ALTER VIEW ... SET (security_invoker = true). A view created after v5.4.2-11 is born owner-rights: the CREATE VIEW default has no such option.';
    END IF;

    -- 7.1b no MATERIALIZED view is reachable by tally_app or PUBLIC.
    --      A matview takes neither security_invoker nor a policy, so the grant
    --      is the only lever. has_any_column_privilege, NOT has_table_privilege:
    --      the latter ignores COLUMN-level grants, and a
    --      `GRANT SELECT (tenant_id, customer_number)` passed the round-2 check
    --      while reading across tenants (Fable, round 2, reproduced). The
    --      column form is true whenever the table form is, so it strictly
    --      subsumes the test it replaces.
    SELECT string_agg(c.relname, ', ' ORDER BY c.relname) INTO v_bad
      FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname = 'public' AND c.relkind = 'm'
       AND (has_any_column_privilege('tally_app', c.oid, 'SELECT')
            OR has_any_column_privilege('public', c.oid, 'SELECT'));
    IF v_bad IS NOT NULL THEN
        RAISE EXCEPTION 'tenant isolation: materialized view(s) readable by tally_app or PUBLIC: %', v_bad
            USING ERRCODE = 'insufficient_privilege',
                  HINT = 'REVOKE ALL ON <matview> FROM tally_app, PUBLIC. A matview holds rows refreshed under the owner''s BYPASSRLS rights and can carry neither security_invoker nor RLS; the blanket ALL TABLES default grant makes a new one readable at birth.';
    END IF;

    -- 7.2 the two RLS policy helpers are definer AND pinned to ''
    SELECT string_agg(p.proname, ', ' ORDER BY p.proname) INTO v_bad
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
       AND p.proname IN ('get_user_tenant_id', 'is_platform_admin')
       AND NOT (p.prosecdef AND p.proconfig @> ARRAY['search_path=""']);
    IF v_bad IS NOT NULL THEN
        RAISE EXCEPTION 'tenant isolation: RLS helper(s) not SECURITY DEFINER pinned to an empty search_path: %', v_bad
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    -- 7.3 the two re-issued helpers are NOT definer
    SELECT string_agg(p.proname, ', ' ORDER BY p.proname) INTO v_bad
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
       AND p.proname IN ('validate_custom_fields', 'get_correction_rate_date')
       AND p.prosecdef;
    IF v_bad IS NOT NULL THEN
        RAISE EXCEPTION 'tenant isolation: function(s) unexpectedly SECURITY DEFINER: %', v_bad
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    -- 7.4a no SECURITY DEFINER function is left unpinned
    SELECT string_agg(p.proname, ', ' ORDER BY p.proname) INTO v_bad
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.prosecdef AND p.proconfig IS NULL;
    IF v_bad IS NOT NULL THEN
        RAISE EXCEPTION 'tenant isolation: SECURITY DEFINER function(s) with no search_path pin: %', v_bad
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    -- 7.4b/c no SECURITY DEFINER function is executable by PUBLIC. By SHAPE:
    --        an enumeration by name cannot notice the next one written.
    SELECT string_agg(p.proname, ', ' ORDER BY p.proname) INTO v_bad
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.prosecdef
       AND has_function_privilege('public', p.oid, 'EXECUTE');
    IF v_bad IS NOT NULL THEN
        RAISE EXCEPTION 'tenant isolation: SECURITY DEFINER function(s) executable by PUBLIC: %', v_bad
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    -- 7.4d the DEFAULT that decides the NEXT function, checked in BOTH places
    --      it can live. Global and per-schema default ACLs are ADDITIVE (not
    --      precedence): a PUBLIC grant in EITHER makes new functions
    --      PUBLIC-executable, and round 2 reproduced the per-schema case
    --      reopening what section 5b closed (Codex). Scoped to the role whose
    --      default it is, so a second creating role cannot pass on tally's
    --      entry (Fable). A PUBLIC grant renders as an ACL item with an empty
    --      grantee, i.e. beginning '='; a real grantee needing punctuation is
    --      double-quoted by PostgreSQL and cannot collide.
    -- Keyed on this function's OWNER, not on current_user: the invariant is
    -- about the role that OWNS AND CREATES the objects, not whoever asks. The
    -- round-2 form refused any other superuser that ran the assertion (Fable,
    -- round 3, reproduced), and owner-keying answers the second-creating-role
    -- concern better anyway — a second role is caught the moment it owns this.
    IF NOT EXISTS (SELECT 1 FROM pg_default_acl d
                    WHERE d.defaclnamespace = 0 AND d.defaclobjtype = 'f'
                      AND d.defaclrole = v_owner) THEN
        RAISE EXCEPTION 'tenant isolation: % has no global default-privilege entry for functions, so PostgreSQL''s built-in PUBLIC EXECUTE applies to every function it creates', v_owner
            USING ERRCODE = 'insufficient_privilege',
                  HINT = 'ALTER DEFAULT PRIVILEGES FOR ROLE <role> REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;  (no IN SCHEMA -- the schema-qualified form is a silent no-op for this)';
    END IF;

    SELECT string_agg(DISTINCT CASE WHEN d.defaclnamespace = 0 THEN 'global' ELSE d.defaclnamespace::regnamespace::text END, ', ') INTO v_bad
      FROM pg_default_acl d, unnest(d.defaclacl::text[]) AS item
     WHERE d.defaclobjtype = 'f'
       AND (d.defaclnamespace = 0 OR d.defaclnamespace = 'public'::regnamespace)
       AND item LIKE '=%';
    IF v_bad IS NOT NULL THEN
        RAISE EXCEPTION 'tenant isolation: a default privilege grants PUBLIC EXECUTE on new functions (in: %) — the next SECURITY DEFINER function written here would be world-executable', v_bad
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    -- 7.5 tally_app can still execute the policy helpers. Without these two
    --     grants the application reads NOTHING: every RLS policy calls them.
    IF NOT has_function_privilege('tally_app', 'public.get_user_tenant_id()', 'EXECUTE')
       OR NOT has_function_privilege('tally_app', 'public.is_platform_admin()', 'EXECUTE') THEN
        RAISE EXCEPTION 'tenant isolation: tally_app lost EXECUTE on a tenant_isolation policy helper — every RLS read would fail'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    -- 7.6 the anomaly discriminator domain
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                    WHERE conrelid = 'public.anomalies'::regclass
                      AND conname  = 'anomalies_entity_type_check') THEN
        RAISE EXCEPTION 'tenant isolation: anomalies_entity_type_check is missing'
            USING ERRCODE = 'check_violation';
    END IF;
END;
$$;

COMMENT ON FUNCTION public.assert_tenant_isolation_invariants() IS
    'Raises unless every tenant-isolation invariant this schema depends on still holds: every table carrying a tenant_id column (and public.tenants, keyed on id) has ROW LEVEL SECURITY enabled AND forced AND at least one policy AND no policy other than the canonical predicate — policies are OR-ed, so one permissive policy defeats the rest, and a partition CHILD does not inherit its parent''s row security; views run with invoker rights; no materialized view is reachable by tally_app or PUBLIC (column grants included); the two RLS policy helpers are SECURITY DEFINER pinned to an empty search_path and executable by tally_app; no other function is definer-and-unpinned or definer-and-PUBLIC-executable; no default privilege — global or per-schema — grants PUBLIC EXECUTE on new functions; anomalies.entity_type carries its domain. Introduced v5.4.2-11. CALL IT IN THE TAIL OF EVERY PATCH and last in the container build: these invariants are true when a patch applies and DRIFT AT THE NEXT CREATE, because tu.sql''s ALTER DEFAULT PRIVILEGES ... ON TABLES grant covers views and matviews, so a new one of either is born readable by tally_app, and a view is born without security_invoker. Invoker rights and owner-only by design — a checking routine must never run elevated, and must never be the thing that grants.';

-- Owner-only: the per-schema default (tu.sql:11390) would otherwise hand this
-- to tally_app at creation.
REVOKE ALL ON FUNCTION public.assert_tenant_isolation_invariants() FROM tally_app, PUBLIC;

DO $$
BEGIN
    PERFORM public.assert_tenant_isolation_invariants();
    RAISE NOTICE 'v5.4.2-11: verified via assert_tenant_isolation_invariants() — views run with invoker rights; no materialized view is reachable by tally_app or PUBLIC; the RLS helpers are definer pinned to '''' and still executable by tally_app; validate_custom_fields / get_correction_rate_date are invoker; no definer function is PUBLIC-executable and no default privilege (global or per-schema) would make the next one so; anomalies.entity_type has a 15-value domain.';
END;
$$;

-- ----------------------------------------------------------------------------
-- A-23 (1c) RULE LIFT — recorded here, deliberately not acted on (residual R2)
-- ----------------------------------------------------------------------------
-- Before this patch, a session or function pinned to search_path = '' could
-- not read ANY row-level-secured table: the tenant_isolation policy calls
-- get_user_tenant_id(), which was unpinned and therefore inherited the
-- caller's empty path, and its unqualified `FROM users` failed to resolve.
-- That is why every trigger function in this schema pins `public, pg_temp`
-- rather than ''. With both policy helpers now pinned and qualified, a
-- trigger function MAY pin '' — provided its own body is fully qualified.
-- The ~190 existing trigger functions are NOT re-pinned here; that is a
-- mechanical patch of its own and does not belong in a hygiene change.

-- ============================================================================
-- END PATCH v5.4.2-11
-- ============================================================================
