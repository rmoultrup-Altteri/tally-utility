-- ============================================================================
-- PATCH v5.4.1-02 — tenant_configuration_history + time-aware
--                    get_partial_period_policy()
--                    (schema-parity-plan Phase 2, item 2.4)
-- ============================================================================
-- Authority:   gas-billing-memory/application/schema-parity-plan.md Phase 2
--              item 2.4 — "the one place an invariant is provably violated
--              by shipped code (get_partial_period_policy() takes no date; a
--              March rebill gets June's policy, breaking CI-006's
--              byte-identical requirement). Draft the table + a new Appendix
--              A entry; the companion function change (date-parameterised
--              lookup, modeled on get_correction_rate_date()) rides along."
--              Source finding: 3M item 3 (application/configurable-rules/
--              wu6-session-3m-review-brief.md:62-88 — "the item that matters
--              most"); corroborated wiki-ingestion-pending.md:674 (V7) and
--              :722 (W-tenant-onboarding item 5: "nothing distinguishes a
--              default from a decision ... thirteen rows ... written once at
--              onboarding"). Not a Kyle ruling; the brief asked for "a
--              decision before the correction engine is built" and the
--              parity plan places that decision in Phase 2 (Ryan-drafted,
--              flagged, low-controversy). Split from v5.4.1-01 because it
--              adds a table and changes a function signature.
--
-- CI entries:  CI-004 (re-check — its universal sentence "No 'current value
--              only' attribute exists for any value with historical billing
--              relevance" covered these columns while its Scope and
--              enforcement note enumerated neither; the enumeration gap is
--              what this patch closes. Token stays partially-structurally-
--              enforced: the bracket here is transaction-time-only, see
--              drafting decisions).
--              CI-006 (re-check — the helper the brief used as proof is no
--              longer time-blind: its temporal coordinate is a REQUIRED
--              explicit input. Token unchanged at requires-application-
--              discipline — purity is still the engine's rule; the schema
--              now makes the pure form available, not mandatory).
--              CI-093 (re-check only — tenant policy resolution joins the
--              set of decisions reproducible from persisted records; token
--              unchanged, weakest-link note untouched).
--              CI-007 is NOT re-graded (unchanged; cited as the model).
--              New Appendix A entry A-22 on the GBM side.
--
-- Drafting decisions:
--              * ONE TABLE, KEY/VALUE, JSONB VALUES. tenant_configuration_
--                history(tenant_id, config_key, old_value, new_value,
--                effective_from, changed_by, change_source, change_reason).
--                Thirteen typed columns + an open-ended settings blob do not
--                fit a typed-column history; the brief's own shape ("tenant,
--                key, prior value, new value, effective from, changed by,
--                changed at") is key/value. Values are to_jsonb(column) so
--                text/numeric/boolean/object all round-trip; read scalars
--                back with  new_value #>> '{}'.
--              * POPULATED BY TRIGGER, NOT BY CONVENTION. trg_record_tenant_
--                configuration_change (AFTER INSERT OR UPDATE ON tenants)
--                writes one row per changed key. With no application layer,
--                a convention-only history would grade requires-application-
--                discipline and the brief's hazard would remain. On INSERT
--                it writes EVERY policy key and every top-level settings key
--                — the onboarding defaults become recorded decisions (W-
--                tenant-onboarding item 5), with change_source =
--                'onboarding'. The trigger is the ONLY intended writer;
--                direct inserts are allowed (change_source = 'manual') for
--                backdated corrections, but UPDATE/DELETE are rejected.
--              * APPEND-ONLY, TRIGGER-ENFORCED (enforce_tenant_configuration_
--                history_immutable, BEFORE UPDATE OR DELETE) — the -04/-05/
--                -06 immutability pattern. A history that can be edited is
--                not a history.
--              * THE BRACKET IS TRANSACTION TIME, NOT VALID TIME. effective_
--                from is now() at the moment of the change; an operator
--                cannot say "this policy took effect last month" through
--                the trigger path. That is a deliberate limit: valid-time
--                policy changes are the A-1 bi-temporal pair's job
--                (bi-temporal-decision §6), and inventing a second valid-
--                time mechanism here would pre-empt it. Hence CI-004 stays
--                partial. Backdated rows CAN be inserted manually
--                (change_source = 'manual', effective_from in the past) —
--                representable, not the normal path.
--              * KEYS COVERED: the thirteen tenants policy columns the brief
--                enumerates (tu.sql:4605-4615 and 4619-4620 — not
--                contiguous; 4616-4618 are onboarded_at/created_at/
--                updated_at) — default_partial_period_
--                policy, payment_allocation_strategy, overpayment_handling,
--                credit_application_timing, minimum_refund_amount, below_
--                threshold_action, donation_program_name, auto_approve_
--                clean_reads, unreviewed_read_billing_policy, meter_
--                redeployment_policy, default_import_error_policy, void_
--                only_unbilled_disposition, void_rebill_threshold — plus
--                each TOP-LEVEL key of settings as 'settings.<key>'
--                (service_transition, estimation, anomaly_detection, ...)
--                — WHEN PRESENT: settings defaults to '{}', so a tenant
--                onboarded without explicit settings gets no settings.*
--                rows until the application writes them; the seven
--                documented sub-objects are not materialised by the DB.
--                Sub-object granularity is top-level: a change anywhere
--                inside settings.estimation records the whole estimation
--                object before/after. Finer granularity is a later call.
--                NOT covered (deliberately): name, slug, status,
--                subscription_tier, contact/address fields, logo_url,
--                onboarded_at — none has billing-period relevance.
--              * TIEBREAK (found in testing): now() is fixed per transaction,
--                so two changes to one key in one transaction share
--                effective_from AND created_at; "latest row" was a coin
--                flip. seq (identity) is the deterministic tiebreaker;
--                resolution orders by effective_from DESC, seq DESC.
--              * BACKFILL: one 'backfill' row per existing tenant per key,
--                effective_from = tenants.created_at, old_value NULL. THIS
--                IS AN APPROXIMATION (review finding): the value written is
--                the one observed at deploy, and a policy changed after
--                onboarding is recorded as if in effect since created_at —
--                earlier history is unknowable. created_at is used (rather
--                than now()) so that, with no live fallback in the
--                function, existing tenants still resolve for pre-deploy
--                coordinates; change_reason states the approximation on
--                every backfill row. On a fresh deploy this is 0 rows.
--                Re-running inserts nothing (NOT EXISTS guard).
--              * GUARDS ON DIRECT INSERTS (review finding): config_key must
--                be one of the thirteen or settings.*; a
--                default_partial_period_policy row must carry one of the
--                three legal values; a direct insert may not claim
--                change_source onboarding/trigger (pg_trigger_depth()
--                guard). tally_app keeps INSERT (RLS-scoped) so backdated
--                corrections are possible without a migration. TRUNCATE is
--                rejected like UPDATE/DELETE. tenant FK is plain REFERENCES
--                (no CASCADE) — deleting a tenant must not erase its audit
--                trail (CI-093).
--              * get_partial_period_policy(p_rate_schedule_id uuid,
--                p_as_of timestamptz) — the second parameter is REQUIRED,
--                no DEFAULT. CI-006: "the temporal-coordinate basis is an
--                explicit input, not an implicit 'current time' reading";
--                a DEFAULT now() would have kept the time-blind form as the
--                path of least resistance. The old one-argument signature
--                is DROPPED (single canonical signature — the v5.2.1
--                void_invoice() precedent); nothing in tu.sql calls it
--                (3M brief :80, re-verified by grep), so nothing breaks.
--                Resolution: rate_schedules.partial_period_policy override
--                (unchanged — the schedule row is its own bracket per
--                CI-004's enforcement note, A-19 pending) > history row for
--                'default_partial_period_policy' with the latest
--                effective_from <= p_as_of (seq DESC tiebreak). NO live-
--                column fallback and NULL p_as_of RAISES (consensus review
--                finding — the first draft's COALESCE onto tenants.default_
--                partial_period_policy made NULL, and any pre-history
--                coordinate, silently resolve to TODAY's value: the time-
--                blind form back through the side door, and a realistic
--                path since get_correction_rate_date() documents returning
--                NULL). Pre-history coordinates return NULL, the same
--                contract as unknown-schedule; the engine must fail on
--                NULL. DATE arguments cast to midnight — documented.
--                Callers pass the run's evaluation coordinate; for a
--                correction run that is the voided invoice's period_end /
--                get_correction_rate_date() result, the same date already
--                used to bracket rates. STABLE, SECURITY INVOKER (history
--                is RLS'd like everything else; the caller's tenant
--                context applies).
--              * FLAGGED, NOT CHANGED: rate_schedules carries BOTH
--                partial_period_policy (tu.sql:4200, no CHECK, read by this
--                function) and partial_period_policy_override (tu.sql:4207,
--                CHECK-constrained, read by nothing). Two columns for one
--                override, the unchecked one live. Pre-existing; the
--                function keeps reading partial_period_policy so this patch
--                changes exactly one thing about it (time-awareness).
--                Candidate Phase 2 item for a later set.
--              * NOT DONE HERE (the brief's "narrow interim fix"):
--                snapshotting the resolved policy set onto billing_runs.
--                That is A-3's invoice_calculation_snapshots territory and
--                lands there.
-- Idempotent:  yes (CREATE TABLE IF NOT EXISTS; CREATE OR REPLACE FUNCTION;
--              DROP TRIGGER/POLICY IF EXISTS + re-CREATE; DROP FUNCTION IF
--              EXISTS for the old signature; backfill guarded by NOT EXISTS;
--              COMMENT overwrite). Everything schema-qualified — tu.sql runs
--              under search_path = '' (the v5.4.1-01 btree_gist lesson).
-- Line count:  DRAFT — not yet mirrored into tu.sql.
-- ============================================================================

--
-- The history table. One row per (tenant, key, change). Append-only.
--
CREATE TABLE IF NOT EXISTS public.tenant_configuration_history (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    seq bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
    tenant_id uuid NOT NULL,
    config_key text NOT NULL,
    old_value jsonb,
    new_value jsonb,
    effective_from timestamp with time zone DEFAULT now() NOT NULL,
    changed_by uuid,
    change_source text DEFAULT 'trigger'::text NOT NULL,
    change_reason text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT tenant_configuration_history_pkey PRIMARY KEY (id),
    CONSTRAINT tenant_configuration_history_seq_key UNIQUE (seq),
    CONSTRAINT tenant_configuration_history_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id),
    CONSTRAINT tenant_configuration_history_changed_by_fkey FOREIGN KEY (changed_by) REFERENCES public.users(id),
    CONSTRAINT tenant_configuration_history_change_source_check CHECK ((change_source = ANY (ARRAY['onboarding'::text, 'trigger'::text, 'backfill'::text, 'manual'::text]))),
    CONSTRAINT tenant_configuration_history_key_nonempty_check CHECK ((length(config_key) > 0)),
    CONSTRAINT tenant_configuration_history_value_changed_check CHECK ((old_value IS DISTINCT FROM new_value)),
    CONSTRAINT tenant_configuration_history_key_known_check CHECK (((config_key ~~ 'settings.%'::text) OR (config_key = ANY (ARRAY['default_partial_period_policy'::text, 'payment_allocation_strategy'::text, 'overpayment_handling'::text, 'credit_application_timing'::text, 'minimum_refund_amount'::text, 'below_threshold_action'::text, 'donation_program_name'::text, 'auto_approve_clean_reads'::text, 'unreviewed_read_billing_policy'::text, 'meter_redeployment_policy'::text, 'default_import_error_policy'::text, 'void_only_unbilled_disposition'::text, 'void_rebill_threshold'::text])))),
    CONSTRAINT tenant_configuration_history_ppp_value_check CHECK (((config_key <> 'default_partial_period_policy'::text) OR ((new_value #>> '{}'::text[]) = ANY (ARRAY['prorated'::text, 'charge_both'::text, 'period_holder'::text]))))
);

CREATE INDEX IF NOT EXISTS idx_tenant_config_history_lookup
    ON public.tenant_configuration_history USING btree (tenant_id, config_key, effective_from DESC, seq DESC);

CREATE OR REPLACE FUNCTION public.enforce_tenant_configuration_history_immutable() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    RAISE EXCEPTION 'tenant_configuration_history rows are append-only (CI-004/CI-093): a policy change is recorded by a new row, never by editing or deleting an old one.';
END;
$$;

DROP TRIGGER IF EXISTS enforce_tenant_configuration_history_immutable ON public.tenant_configuration_history;
CREATE TRIGGER enforce_tenant_configuration_history_immutable BEFORE UPDATE OR DELETE ON public.tenant_configuration_history
    FOR EACH ROW EXECUTE FUNCTION public.enforce_tenant_configuration_history_immutable();
DROP TRIGGER IF EXISTS enforce_tenant_configuration_history_no_truncate ON public.tenant_configuration_history;
CREATE TRIGGER enforce_tenant_configuration_history_no_truncate BEFORE TRUNCATE ON public.tenant_configuration_history
    FOR EACH STATEMENT EXECUTE FUNCTION public.enforce_tenant_configuration_history_immutable();

-- Direct inserts may not impersonate the recorder. The recorder runs inside
-- the tenants trigger (pg_trigger_depth() = 2 when this fires); a direct
-- INSERT sees depth 1 and may only be 'manual' or 'backfill'.
CREATE OR REPLACE FUNCTION public.guard_tenant_configuration_history_source() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF pg_trigger_depth() < 2 AND NEW.change_source IN ('onboarding', 'trigger') THEN
        RAISE EXCEPTION 'tenant_configuration_history: change_source % is written only by trg_record_tenant_configuration_change; direct inserts must be ''manual'' or ''backfill''', NEW.change_source;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS guard_tenant_configuration_history_source ON public.tenant_configuration_history;
CREATE TRIGGER guard_tenant_configuration_history_source BEFORE INSERT ON public.tenant_configuration_history
    FOR EACH ROW EXECUTE FUNCTION public.guard_tenant_configuration_history_source();

ALTER TABLE public.tenant_configuration_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tenant_configuration_history FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_isolation ON public.tenant_configuration_history;
CREATE POLICY tenant_isolation ON public.tenant_configuration_history USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));

COMMENT ON TABLE public.tenant_configuration_history IS
    'Append-only history of every billing-relevant tenant policy value (the thirteen tenants.* policy columns plus each top-level settings.<key> object). One row per (tenant, key, change): prior value, new value, when it took effect, who changed it. Written automatically by trg_record_tenant_configuration_change — on tenant INSERT every key is recorded (change_source=onboarding) so a default is a recorded decision, not a silent one; on UPDATE only keys whose value changed. UPDATE/DELETE rejected by trigger. effective_from is transaction time (when the change was made); valid-time policy changes wait on the A-1 bi-temporal pair. Resolve "what was key K for tenant T at time X": latest row with effective_from <= X. CI-004 / CI-006 / CI-093, Appendix A-22, schema-parity-plan Phase 2 item 2.4 (v5.4.1-02).';
COMMENT ON COLUMN public.tenant_configuration_history.seq IS
    'Insertion order. The deterministic tiebreaker when two rows for the same key share an effective_from — which every change made inside one transaction does, because now() is fixed for the transaction. Resolution is ORDER BY effective_from DESC, seq DESC.';
COMMENT ON COLUMN public.tenant_configuration_history.config_key IS
    'tenants column name (e.g. default_partial_period_policy) or settings.<top-level key> (e.g. settings.estimation).';
COMMENT ON COLUMN public.tenant_configuration_history.old_value IS
    'Value before the change as JSONB (to_jsonb of the column / settings sub-object). NULL on the onboarding and backfill rows. Scalars read back with  old_value #>> ''{}''.';
COMMENT ON COLUMN public.tenant_configuration_history.new_value IS
    'Value after the change as JSONB. A SQL-NULL column value is recorded as the JSON literal null (to_jsonb semantics) — test with  new_value = ''null''::jsonb  or  new_value #>> ''{}'' IS NULL, never  new_value IS NULL. SQL NULL here means a settings key was removed.';
COMMENT ON COLUMN public.tenant_configuration_history.effective_from IS
    'When this value started applying. Trigger-written rows use now(); backfill rows use tenants.created_at; manual rows may be backdated (representable, not the normal path).';
COMMENT ON COLUMN public.tenant_configuration_history.changed_by IS
    'users.id from the app.user_id session GUC at the time of the change; NULL when no GUC is set (migrations, backfill, superuser sessions).';
COMMENT ON COLUMN public.tenant_configuration_history.change_source IS
    'onboarding = written by the tenant INSERT; trigger = written by a tenant UPDATE; backfill = v5.4.1-02 seeded the value OBSERVED at deploy, stamped at tenants.created_at as an approximation (earlier changes are unknown — see change_reason); manual = inserted directly (backdated correction). onboarding/trigger cannot be claimed by a direct insert (guard trigger).';

--
-- The recorder. One row per changed key on tenants INSERT/UPDATE.
--
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
        'void_rebill_threshold'
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

DROP TRIGGER IF EXISTS trg_record_tenant_configuration_change ON public.tenants;
CREATE TRIGGER trg_record_tenant_configuration_change AFTER INSERT OR UPDATE ON public.tenants
    FOR EACH ROW EXECUTE FUNCTION public.record_tenant_configuration_change();

--
-- Backfill: pre-existing tenants get one 'backfill' row per key at
-- created_at. 0 rows on a fresh deploy; a re-run inserts nothing.
--
INSERT INTO public.tenant_configuration_history
    (tenant_id, config_key, old_value, new_value, effective_from, change_source, change_reason)
SELECT t.id, k.key, NULL, to_jsonb(t) -> k.key, t.created_at, 'backfill',
       'value observed at v5.4.1-02 deploy; stamped at tenants.created_at as an approximation — earlier history unknown'
FROM public.tenants t
CROSS JOIN unnest(ARRAY[
        'default_partial_period_policy', 'payment_allocation_strategy',
        'overpayment_handling', 'credit_application_timing',
        'minimum_refund_amount', 'below_threshold_action',
        'donation_program_name', 'auto_approve_clean_reads',
        'unreviewed_read_billing_policy', 'meter_redeployment_policy',
        'default_import_error_policy', 'void_only_unbilled_disposition',
        'void_rebill_threshold']) AS k(key)
WHERE (to_jsonb(t) -> k.key) IS NOT NULL
  AND NOT EXISTS (
      SELECT 1 FROM public.tenant_configuration_history h
      WHERE h.tenant_id = t.id AND h.config_key = k.key);

INSERT INTO public.tenant_configuration_history
    (tenant_id, config_key, old_value, new_value, effective_from, change_source, change_reason)
SELECT t.id, 'settings.' || s.key, NULL, s.value, t.created_at, 'backfill',
       'value observed at v5.4.1-02 deploy; stamped at tenants.created_at as an approximation — earlier history unknown'
FROM public.tenants t
CROSS JOIN LATERAL jsonb_each(COALESCE(t.settings, '{}'::jsonb)) AS s(key, value)
WHERE NOT EXISTS (
      SELECT 1 FROM public.tenant_configuration_history h
      WHERE h.tenant_id = t.id AND h.config_key = 'settings.' || s.key);

--
-- get_partial_period_policy(): time-aware. Old one-argument signature
-- dropped (single canonical signature). p_as_of is REQUIRED.
--
DROP FUNCTION IF EXISTS public.get_partial_period_policy(uuid);

CREATE OR REPLACE FUNCTION public.get_partial_period_policy(p_rate_schedule_id uuid, p_as_of timestamp with time zone) RETURNS text
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    v_override  text;
    v_tenant_id uuid;
    v_policy    text;
BEGIN
    -- CI-006: the temporal coordinate is an explicit input. A NULL here is a
    -- caller bug (e.g. passing get_correction_rate_date()'s NULL through
    -- unhandled), and silently resolving "now" would reintroduce the exact
    -- time-blind hazard this function exists to close. Fail loudly.
    IF p_as_of IS NULL THEN
        RAISE EXCEPTION 'get_partial_period_policy: p_as_of must not be NULL — pass the run''s evaluation coordinate (CI-006)';
    END IF;

    SELECT rs.partial_period_policy, rs.tenant_id
    INTO v_override, v_tenant_id
    FROM public.rate_schedules rs
    WHERE rs.id = p_rate_schedule_id;

    IF NOT FOUND THEN
        RETURN NULL;   -- unknown rate schedule (same contract as get_correction_rate_date)
    END IF;

    IF v_override IS NOT NULL THEN
        RETURN v_override;   -- per-schedule override; the schedule row is its own bracket
    END IF;

    -- Tenant default as recorded AT p_as_of. No fallback to the live column:
    -- a coordinate earlier than the tenant's first recorded row returns NULL
    -- ("no policy is knowable at that coordinate") rather than today's value.
    SELECT h.new_value #>> '{}'
    INTO v_policy
    FROM public.tenant_configuration_history h
    WHERE h.tenant_id = v_tenant_id
      AND h.config_key = 'default_partial_period_policy'
      AND h.effective_from <= p_as_of
    ORDER BY h.effective_from DESC, h.seq DESC
    LIMIT 1;

    RETURN v_policy;
END;
$$;

COMMENT ON FUNCTION public.get_partial_period_policy(p_rate_schedule_id uuid, p_as_of timestamp with time zone) IS
    'Effective partial-period policy for a rate schedule AS OF an explicit temporal coordinate (v5.4.1-02, CI-006: the coordinate is a required input, never an implicit now()). NULL p_as_of RAISES — do not pass get_correction_rate_date()''s NULL through; substitute and log first, per that function''s own COMMENT. Resolution: rate_schedules.partial_period_policy override if set > the tenant default recorded in tenant_configuration_history with the latest effective_from <= p_as_of (seq breaks ties). There is deliberately NO fallback to the live tenants column: an unknown rate schedule, or a coordinate earlier than the tenant''s first recorded row, returns NULL — the engine must treat NULL as a hard error, never as "use the default". A DATE argument casts to midnight of that day; a policy changed later the same day is excluded — pass an end-of-day timestamptz if "in effect on that day" is the intent. Correction runs pass the voided invoice''s period_end / get_correction_rate_date() result — the same coordinate used to bracket rates — so a March rebill resolves March''s policy. The one-argument time-blind form (v5.2.1) was dropped; it had no callers.';
