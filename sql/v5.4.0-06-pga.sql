-- ============================================================================
-- PATCH v5.4.0-06 — PGA set (v5.4 backlog item 14)
-- ============================================================================
-- Authority:   Kyle ruling 2026-07-10 (gas-billing-memory/application/
--              wu5-wu6-kyle-decisions-2026-07-10.md):
--                item 14  PGA deferred-balance monitoring — monthly
--                         reconciliation record (immutable input-snapshot
--                         rows) + threshold config            (D3D-1)
--              Decision tables: pga-deferred-account-and-trueup (cluster 21,
--              rows 0 and 4), pga-application (cluster 20, context only).
--              Fifth and FINAL Phase 1 migration set per the parity plan.
-- CI entries:  CI-036 (re-grade — the monthly accrual/reconciliation record
--              slice of A-6 lands; gas_purchases + per-class deferred ledger
--              + annual true-up workflow remain open, so A-6 itself stays
--              open); CI-033 (re-check only — its audit-defense remediation
--              cites CI-036's substrate).
-- Drafting decisions (delegated by the ruling to patch time):
--              * "Immutable" is TRIGGER-ENFORCED, not convention. D3D-1 says
--                the twelve rows ARE the annual true-up workpapers and must
--                survive mid-year config changes; with no application layer,
--                convention-only immutability would grade requires-
--                application-discipline. UPDATE and DELETE both raise.
--                (wna_clamp_events stayed convention-only because T-4 only
--                said "clamp-and-log"; D3D-1's language is stronger.)
--              * The record stores threshold_band (which band the balance
--                sits in this month: none/low/medium — deterministic from
--                the row's own snapshotted values, CHECK-enforced), NOT an
--                "alert fired" flag. D3D-1's alert fires on band CROSSING;
--                crossing is derivable by comparing consecutive immutable
--                rows and stays application logic, along with the optional
--                re-alert interval.
--              * Band boundary is >= (reaching 10.00% IS the low band).
--                D3D-1 says "crosses"; at the exact boundary the balance is
--                treated as in-band.
--              * Sign convention: monthly_variance = actual_gas_cost −
--                pga_recovered_revenue; positive = under-recovery (deficit),
--                negative = over-recovery (surplus). CHECK-enforced
--                arithmetic makes each row a self-verifying workpaper.
--              * Threshold config is ONE ROW PER TENANT (UNIQUE(tenant_id));
--                D3D-1 says tenant-overridable, and PGA under 16 TAC
--                §7.5519 is a single Texas-wide mechanism per tenant — no
--                jurisdiction key. Column defaults carry the 10/20 starter
--                values; when no row exists the monthly job applies the
--                same platform defaults (re-alert off).
--              * Rows are tenant-level, not per-rate-class: D3D-1's snapshot
--                list (supplier invoice total, billed PGA revenue, variance,
--                cumulative balance, thresholds in effect) is tenant-level;
--                per-class allocation happens at the ANNUAL reconciliation
--                (cluster 21 row 1), which is A-6 territory, not this patch.
--              * Carrying cost (cluster 21 row 2) NOT modeled — annual-
--                settlement mechanics, stays with A-6.
-- Idempotent:  yes (CREATE TABLE/INDEX IF NOT EXISTS; CREATE OR REPLACE
--              FUNCTION; triggers/policies DROP IF EXISTS + re-CREATE;
--              COMMENT overwrite).
-- Line count:  mirrored into tu.sql as a pure APPEND at end of file — no
--              existing line shifts; anchors 337/3600/3679 unaffected.
-- ============================================================================

--
-- Threshold configuration (D3D-1): tenant-overridable percentage thresholds
-- against trailing-twelve-month PGA revenue, plus the optional re-alert
-- interval for a sustained breach. Mutable reference data — the monthly
-- record snapshots whatever was in effect, so editing this never rewrites
-- history.
--
CREATE TABLE IF NOT EXISTS public.pga_monitoring_settings (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id uuid NOT NULL,
    low_alert_threshold_pct numeric(5,2) DEFAULT 10.00 NOT NULL,
    medium_alert_threshold_pct numeric(5,2) DEFAULT 20.00 NOT NULL,
    re_alert_interval_days integer,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT pga_monitoring_settings_pkey PRIMARY KEY (id),
    CONSTRAINT pga_monitoring_settings_tenant_id_key UNIQUE (tenant_id),
    CONSTRAINT pga_monitoring_settings_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id),
    CONSTRAINT pga_monitoring_settings_low_positive_check CHECK ((low_alert_threshold_pct > (0)::numeric)),
    CONSTRAINT pga_monitoring_settings_band_order_check CHECK ((medium_alert_threshold_pct > low_alert_threshold_pct)),
    CONSTRAINT pga_monitoring_settings_re_alert_positive_check CHECK (((re_alert_interval_days IS NULL) OR (re_alert_interval_days > 0)))
);

DROP TRIGGER IF EXISTS set_updated_at ON public.pga_monitoring_settings;
CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.pga_monitoring_settings FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();

ALTER TABLE public.pga_monitoring_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pga_monitoring_settings FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_isolation ON public.pga_monitoring_settings;
CREATE POLICY tenant_isolation ON public.pga_monitoring_settings USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));

COMMENT ON TABLE public.pga_monitoring_settings IS
    'PGA deferred-balance monitoring thresholds (D3D-1, v5.4.0-06). One row per tenant. Percentages of trailing-twelve-month PGA revenue — percentage-based, not dollar, so they scale with tenant size. Column defaults 10.00/20.00 are D3D-1''s reasoned starter defaults (no RRC-prescribed number exists — tune per tenant); when no row exists the monthly monitoring job applies these same platform defaults with re-alerting off. Editing this table never rewrites history: each pga_monthly_reconciliations row snapshots the thresholds in effect when it posted.';

COMMENT ON COLUMN public.pga_monitoring_settings.low_alert_threshold_pct IS
    '|deferred balance| >= this percent of trailing-12mo PGA revenue puts the balance in the low band (Low portlet on band crossing). D3D-1 starter default 10%.';

COMMENT ON COLUMN public.pga_monitoring_settings.medium_alert_threshold_pct IS
    '|deferred balance| >= this percent of trailing-12mo PGA revenue puts the balance in the medium band (Medium portlet on band crossing). D3D-1 starter default 20%. Must exceed the low threshold.';

COMMENT ON COLUMN public.pga_monitoring_settings.re_alert_interval_days IS
    'Optional re-alert interval for a sustained breach (D3D-1): when set, the application re-fires the alert every N days while the balance stays over a threshold. NULL = re-alerting off (alerts fire on band crossing only). Crossing detection and re-alerting are application logic over the immutable monthly rows.';

--
-- The monthly reconciliation record (D3D-1 row 0): one immutable row per
-- tenant per month, posted by the backend monitoring job. The twelve rows
-- of a PGA year ARE the annual true-up workpapers — they snapshot every
-- input as it stood that month and survive mid-year config changes.
-- Immutability is trigger-enforced (drafting call — see header).
--
CREATE TABLE IF NOT EXISTS public.pga_monthly_reconciliations (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id uuid NOT NULL,
    reconciliation_month date NOT NULL,
    actual_gas_cost numeric(14,2) NOT NULL,
    pga_recovered_revenue numeric(14,2) NOT NULL,
    monthly_variance numeric(14,2) NOT NULL,
    deferred_balance_after numeric(14,2) NOT NULL,
    trailing_12mo_pga_revenue numeric(14,2) NOT NULL,
    low_threshold_pct_applied numeric(5,2) NOT NULL,
    medium_threshold_pct_applied numeric(5,2) NOT NULL,
    threshold_band text NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT pga_monthly_reconciliations_pkey PRIMARY KEY (id),
    CONSTRAINT pga_monthly_reconciliations_tenant_month_key UNIQUE (tenant_id, reconciliation_month),
    CONSTRAINT pga_monthly_reconciliations_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id),
    CONSTRAINT pga_monthly_reconciliations_month_first_day_check CHECK ((EXTRACT(day FROM reconciliation_month) = (1)::numeric)),
    CONSTRAINT pga_monthly_reconciliations_variance_arithmetic_check CHECK ((monthly_variance = (actual_gas_cost - pga_recovered_revenue))),
    CONSTRAINT pga_monthly_reconciliations_trailing_nonnegative_check CHECK ((trailing_12mo_pga_revenue >= (0)::numeric)),
    CONSTRAINT pga_monthly_reconciliations_threshold_order_check CHECK ((medium_threshold_pct_applied > low_threshold_pct_applied)),
    CONSTRAINT pga_monthly_reconciliations_threshold_band_check CHECK ((threshold_band = ANY (ARRAY['none'::text, 'low'::text, 'medium'::text]))),
    CONSTRAINT pga_monthly_reconciliations_band_consistent_check CHECK (((trailing_12mo_pga_revenue = (0)::numeric) OR (threshold_band =
        CASE
            WHEN (((abs(deferred_balance_after) / trailing_12mo_pga_revenue) * (100)::numeric) >= medium_threshold_pct_applied) THEN 'medium'::text
            WHEN (((abs(deferred_balance_after) / trailing_12mo_pga_revenue) * (100)::numeric) >= low_threshold_pct_applied) THEN 'low'::text
            ELSE 'none'::text
        END))),
    CONSTRAINT pga_monthly_reconciliations_metadata_object_check CHECK ((jsonb_typeof(metadata) = 'object'::text))
);

CREATE INDEX IF NOT EXISTS idx_pga_monthly_reconciliations_tenant_band ON public.pga_monthly_reconciliations USING btree (tenant_id, threshold_band) WHERE (threshold_band <> 'none'::text);

--
-- Immutability guard (drafting call, see header): the monthly record never
-- mutates — not for config changes, not for corrections. A wrong posting is
-- corrected the way the deferred account itself is corrected: the next
-- month's variance absorbs it (cluster 21 row 5 — correction_path is always
-- deferred_account_amortization, never rewriting history).
--
CREATE OR REPLACE FUNCTION public.enforce_pga_reconciliation_immutable() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    RAISE EXCEPTION 'pga_monthly_reconciliations rows are immutable (D3D-1): they are the annual true-up workpapers. Corrections flow through the next month''s variance, never through rewriting a posted month.';
END;
$$;

DROP TRIGGER IF EXISTS enforce_pga_reconciliation_immutable ON public.pga_monthly_reconciliations;
CREATE TRIGGER enforce_pga_reconciliation_immutable BEFORE UPDATE OR DELETE ON public.pga_monthly_reconciliations FOR EACH ROW EXECUTE FUNCTION public.enforce_pga_reconciliation_immutable();

ALTER TABLE public.pga_monthly_reconciliations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pga_monthly_reconciliations FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_isolation ON public.pga_monthly_reconciliations;
CREATE POLICY tenant_isolation ON public.pga_monthly_reconciliations USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));

COMMENT ON TABLE public.pga_monthly_reconciliations IS
    'PGA monthly reconciliation record (D3D-1, v5.4.0-06): one immutable row per tenant per month, posted by the backend monitoring job — supplier gas cost vs. PGA revenue recovered, the month''s variance, the running deferred balance, and the thresholds in effect at posting time. The twelve rows of a PGA year ARE the annual true-up workpapers (cluster 21 row 1) and survive mid-year threshold-config changes. Immutability is trigger-enforced. Customer-facing true-up factors still change only at the annual reconciliation (monitoring and settlement are different cadences). Tenant-level by design; per-rate-class allocation happens at annual reconciliation (A-6). Bonus property: a stale-factor billing error (T-1''s cancel-rebill category) surfaces here as an anomalous monthly variance within a month or two, while the rebill window is clean.';

COMMENT ON COLUMN public.pga_monthly_reconciliations.reconciliation_month IS
    'First day of the month being reconciled (CHECK-enforced day=1). One row per tenant per month.';

COMMENT ON COLUMN public.pga_monthly_reconciliations.actual_gas_cost IS
    'Supplier invoice total for the month — actual gas cost pulled by the monitoring job, snapshotted as it stood at posting. The value''s provenance (gas-purchase records) is A-6 substrate, upstream of this record.';

COMMENT ON COLUMN public.pga_monthly_reconciliations.pga_recovered_revenue IS
    'PGA revenue actually billed for the month, snapshotted at posting.';

COMMENT ON COLUMN public.pga_monthly_reconciliations.monthly_variance IS
    'actual_gas_cost − pga_recovered_revenue (CHECK-enforced arithmetic). Positive = under-recovery (deficit grows), negative = over-recovery (surplus grows).';

COMMENT ON COLUMN public.pga_monthly_reconciliations.deferred_balance_after IS
    'Running signed deferred balance after this month''s variance posted. Positive = cumulative under-recovery owed to the utility, negative = over-recovery owed back to customers. Continuity with the prior row (previous balance + variance) is the posting job''s discipline — not CHECK-enforced, because the opening balance of the first row has no prior row to reference.';

COMMENT ON COLUMN public.pga_monthly_reconciliations.trailing_12mo_pga_revenue IS
    'Trailing-twelve-month PGA revenue at posting — the denominator for threshold evaluation (D3D-1). Zero disables band evaluation (see the band-consistency CHECK).';

COMMENT ON COLUMN public.pga_monthly_reconciliations.threshold_band IS
    'Which band |deferred_balance_after| / trailing_12mo_pga_revenue sits in this month, against the SNAPSHOTTED thresholds: none / low / medium. CHECK-enforced to match the row''s own numbers (boundary is >=). This is the band, not the alert: D3D-1 alerts fire on band CROSSING, detected by the application comparing consecutive rows; the optional re-alert interval lives in pga_monitoring_settings.';

COMMENT ON COLUMN public.pga_monthly_reconciliations.low_threshold_pct_applied IS
    'Low threshold in effect when this row posted (snapshot from pga_monitoring_settings or platform default). Makes the row reproducible after config changes.';

COMMENT ON COLUMN public.pga_monthly_reconciliations.medium_threshold_pct_applied IS
    'Medium threshold in effect when this row posted (snapshot). Must exceed the low snapshot.';
