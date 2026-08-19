-- ============================================================================
-- PATCH v5.4.0-03 — Rating & WNA set (v5.4 backlog items 4, 5, 6, 7)
-- ============================================================================
-- Authority:   Kyle rulings 2026-07-10 (gas-billing-memory/application/
--              wu5-wu6-kyle-decisions-2026-07-10.md):
--                item 4  regulatory_class enum on charge definitions   (D7-2)
--                item 5  jurisdiction record + service-location link   (D5-2)
--                item 6  WNA floor/ceiling + clamp event               (T-4)
--                item 7  prorate_tier_breakpoints default -> true      (T-3)
--              Second Phase 1 migration set per the parity plan.
-- CI entries:  CI-050 (regulated-first allocation — gains its classification
--              substrate; per-charge *expression* on consolidated invoices
--              remains the known invoice_applications limitation, see the
--              payment-posting-allocation table findings), CI-043/CI-044
--              context (WNA), CI-108 (proration default), CI-020/A-5
--              (service_locations gains its first jurisdiction FK).
-- Drafting decisions (delegated by the rulings to patch time):
--              * regulatory_class lands on BOTH rate_items (the recurring
--                charge-definition table) and adhoc_charges (the one-time
--                charge-definition site): classifying only rate_items would
--                leave every adhoc charge (NSF, connection fees — classic
--                unregulated debt) unclassifiable, reproducing exactly the
--                CI-050 failure mode D7-2 exists to close. NOT NULL, no
--                default: a charge introduced without explicit
--                classification is the named failure mode, and no deployed
--                database with rows exists anywhere (provenance 2026-08-18),
--                so the backfill question is vacuous.
--              * The jurisdictions table is the D5-2 WNA-jurisdiction
--                record. It is NOT the A-8 tax_jurisdictions table (that
--                gap, incl. date-effective history, remains open) and does
--                not attempt Inc/Env (CI-093 neighbor) — only what D5-2
--                ruled: WNA applicability flag + WNA tariff-variant pointer.
--              * The WNA tariff-variant pointer targets wna_zones: in this
--                schema a WNA variant's mechanics (factors, window, clamp
--                config) live in a wna_zones row, so "Dallas has its own
--                tariff" = Dallas's jurisdiction row points at Dallas's
--                wna_zones row. (Atmos Mid-Tex four-variant pattern, D5-2
--                research note.)
--              * Clamp events get a dedicated append-only table
--                (wna_clamp_events), following the schema's per-domain
--                event-table idiom (dunning_events, escheatment_events),
--                with the bound values snapshotted at clamp time (CI-006
--                reproducibility discipline). No updated_at / no update
--                trigger: event records are immutable.
--              * T-3's "existing-row review" is vacuously complete: no
--                database with data exists anywhere, so the default flip
--                cannot silently change any live tariff's behavior.
-- Idempotent:  yes (CREATE TABLE/INDEX IF NOT EXISTS; ADD COLUMN IF NOT
--              EXISTS; constraints/trigger/policies DROP IF EXISTS + re-ADD;
--              SET DEFAULT / COMMENT overwrite).
-- Line count:  mirrored into tu.sql as a pure APPEND at end of file — no
--              existing line shifts; anchors 337/3600/3679 unaffected.
-- ============================================================================

--
-- Item 4 — regulatory_class (D7-2): regulated vs. unregulated, on both
-- charge-definition sites. Load-bearing for Family 9 ("unregulated debt
-- can't drive disconnect") and CI-050's regulated-first allocation floor.
--
ALTER TABLE public.rate_items ADD COLUMN IF NOT EXISTS regulatory_class text NOT NULL;

ALTER TABLE public.rate_items DROP CONSTRAINT IF EXISTS rate_items_regulatory_class_check;
ALTER TABLE public.rate_items ADD CONSTRAINT rate_items_regulatory_class_check
    CHECK ((regulatory_class = ANY (ARRAY['regulated'::text, 'unregulated'::text])));

COMMENT ON COLUMN public.rate_items.regulatory_class IS
    'Whether this charge is tariffed/regulated or unregulated (D7-2, v5.4.0-03). NOT NULL by design: a charge definition introduced without explicit classification is CI-050''s named failure mode. Drives the regulated-first payment-allocation floor (CI-050) and the Family 9 collections rule that unregulated debt cannot drive disconnect. Canonical citation: Minnesota PUC / CenterPoint, March 2024.';

ALTER TABLE public.adhoc_charges ADD COLUMN IF NOT EXISTS regulatory_class text NOT NULL;

ALTER TABLE public.adhoc_charges DROP CONSTRAINT IF EXISTS adhoc_charges_regulatory_class_check;
ALTER TABLE public.adhoc_charges ADD CONSTRAINT adhoc_charges_regulatory_class_check
    CHECK ((regulatory_class = ANY (ARRAY['regulated'::text, 'unregulated'::text])));

COMMENT ON COLUMN public.adhoc_charges.regulatory_class IS
    'Whether this one-time charge is tariffed/regulated or unregulated (D7-2, v5.4.0-03). Required at creation for the same reason as rate_items.regulatory_class — one-off charges (NSF, connection fees) are debt too, and the disconnect/allocation rules need their classification.';

--
-- Item 5 — the D5-2 WNA-jurisdiction record. WNA applicability is a
-- property of the jurisdiction, not the customer: adding a second excluded
-- city is one row update here, never a mass customer-flag update.
--
CREATE TABLE IF NOT EXISTS public.jurisdictions (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id uuid NOT NULL,
    jurisdiction_code text NOT NULL,
    jurisdiction_name text NOT NULL,
    description text,
    wna_applicable boolean DEFAULT true NOT NULL,
    wna_zone_id uuid,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT jurisdictions_pkey PRIMARY KEY (id),
    CONSTRAINT jurisdictions_tenant_id_jurisdiction_code_key UNIQUE (tenant_id, jurisdiction_code),
    CONSTRAINT jurisdictions_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id),
    CONSTRAINT jurisdictions_wna_zone_id_fkey FOREIGN KEY (wna_zone_id) REFERENCES public.wna_zones(id)
);

CREATE INDEX IF NOT EXISTS idx_jurisdictions_tenant ON public.jurisdictions USING btree (tenant_id);
CREATE INDEX IF NOT EXISTS idx_jurisdictions_wna_zone ON public.jurisdictions USING btree (wna_zone_id);

DROP TRIGGER IF EXISTS set_updated_at ON public.jurisdictions;
CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.jurisdictions FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();

ALTER TABLE public.jurisdictions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.jurisdictions FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_isolation ON public.jurisdictions;
CREATE POLICY tenant_isolation ON public.jurisdictions USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));

COMMENT ON TABLE public.jurisdictions IS
    'The D5-2 jurisdiction record (v5.4.0-03): city/jurisdiction as a first-class, tenant-scoped reference that service locations link to. Carries the WNA applicability flag and the WNA tariff-variant pointer — a franchise-city WNA opt-out is an update to this row, never a mass customer-flag update. This is NOT the A-8 tax_jurisdictions table (that gap, with date-effective history, remains open) and carries no Inc/Env flag (CI-093''s Texas sub-jurisdiction question, also open).';

COMMENT ON COLUMN public.jurisdictions.wna_applicable IS
    'Whether WNA applies to premises in this jurisdiction (D5-2). false = jurisdiction-level opt-out (e.g., a franchise city that rejected the WNA rider). Default true — the common Texas case.';

COMMENT ON COLUMN public.jurisdictions.wna_zone_id IS
    'The WNA tariff-variant pointer (D5-2): which wna_zones row (factors, seasonal window, clamp config) governs premises in this jurisdiction. The Atmos Mid-Tex pattern — four WNA variants including a separate Dallas tariff — is four wna_zones rows, each pointed at by its jurisdictions. NULL when wna_applicable is false or the variant is not yet assigned; the application should treat wna_applicable = true with a NULL pointer as incomplete configuration.';

ALTER TABLE public.service_locations ADD COLUMN IF NOT EXISTS jurisdiction_id uuid;

ALTER TABLE public.service_locations DROP CONSTRAINT IF EXISTS service_locations_jurisdiction_id_fkey;
ALTER TABLE public.service_locations ADD CONSTRAINT service_locations_jurisdiction_id_fkey
    FOREIGN KEY (jurisdiction_id) REFERENCES public.jurisdictions(id);

CREATE INDEX IF NOT EXISTS idx_service_locations_jurisdiction ON public.service_locations USING btree (jurisdiction_id);

COMMENT ON COLUMN public.service_locations.jurisdiction_id IS
    'The premise''s jurisdiction (D5-2, v5.4.0-03) — the service-location attribute through which WNA applicability and the WNA tariff variant resolve. First premise-side jurisdiction FK (Appendix A-5); the remaining zone FKs (BTU, pressure, rate zone, weather station, tax jurisdiction) are still open. Nullable: population is a tenant-onboarding/backfill concern, and the existing inside_city_limits/franchise_city columns remain as-is.';

--
-- Item 6 — WNA floor/ceiling guard (T-4), on the WNA config record.
-- PGW 2022 ($12.4M refund): a correct formula still blew up at the
-- low-usage boundary. Under D5-1 monthly settlement there is no annual
-- reconciliation backstop — this clamp is the only guard.
--
ALTER TABLE public.wna_zones ADD COLUMN IF NOT EXISTS wna_adjustment_floor numeric(14,6);
ALTER TABLE public.wna_zones ADD COLUMN IF NOT EXISTS wna_adjustment_ceiling numeric(14,6);
ALTER TABLE public.wna_zones ADD COLUMN IF NOT EXISTS wna_clamp_basis text;

ALTER TABLE public.wna_zones DROP CONSTRAINT IF EXISTS wna_zones_clamp_basis_check;
ALTER TABLE public.wna_zones ADD CONSTRAINT wna_zones_clamp_basis_check
    CHECK ((wna_clamp_basis IS NULL) OR (wna_clamp_basis = ANY (ARRAY['percent_of_base'::text, 'dollars'::text])));

ALTER TABLE public.wna_zones DROP CONSTRAINT IF EXISTS wna_zones_clamp_basis_required_check;
ALTER TABLE public.wna_zones ADD CONSTRAINT wna_zones_clamp_basis_required_check
    CHECK (((wna_adjustment_floor IS NULL) AND (wna_adjustment_ceiling IS NULL)) OR (wna_clamp_basis IS NOT NULL));

ALTER TABLE public.wna_zones DROP CONSTRAINT IF EXISTS wna_zones_floor_le_ceiling_check;
ALTER TABLE public.wna_zones ADD CONSTRAINT wna_zones_floor_le_ceiling_check
    CHECK ((wna_adjustment_floor IS NULL) OR (wna_adjustment_ceiling IS NULL) OR (wna_adjustment_floor <= wna_adjustment_ceiling));

COMMENT ON COLUMN public.wna_zones.wna_adjustment_floor IS
    'Lower clamp bound for a bill''s WNA adjustment (T-4, v5.4.0-03), in wna_clamp_basis units. Nullable by ruling — no forced value; the application should raise a config-time warning when left NULL. When the raw computed adjustment falls below it, the adjustment is clamped and a wna_clamp_events row posts.';

COMMENT ON COLUMN public.wna_zones.wna_adjustment_ceiling IS
    'Upper clamp bound for a bill''s WNA adjustment (T-4, v5.4.0-03), in wna_clamp_basis units. Same contract as wna_adjustment_floor. The PGW 2022 low-usage-boundary pathology is the reason this exists; under monthly-settled WNA (D5-1) the clamp is the only guard.';

COMMENT ON COLUMN public.wna_zones.wna_clamp_basis IS
    'Units of the floor/ceiling (T-4): percent_of_base (percent of the bill''s base distribution charge) or dollars. Tenant''s choice per their tariff. Required whenever either bound is set (enforced).';

--
-- The clamp event record (T-4: "clamp-and-log when hit"). Append-only;
-- bound values snapshotted at clamp time so the event is reproducible
-- after the zone config changes.
--
CREATE TABLE IF NOT EXISTS public.wna_clamp_events (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id uuid NOT NULL,
    wna_zone_id uuid NOT NULL,
    wna_monthly_adjustment_id uuid,
    customer_id uuid,
    invoice_id uuid,
    billing_month date NOT NULL,
    bound_hit text NOT NULL,
    raw_adjustment numeric(14,6) NOT NULL,
    clamped_adjustment numeric(14,6) NOT NULL,
    clamp_basis text NOT NULL,
    floor_value_at_clamp numeric(14,6),
    ceiling_value_at_clamp numeric(14,6),
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT wna_clamp_events_pkey PRIMARY KEY (id),
    CONSTRAINT wna_clamp_events_bound_hit_check CHECK ((bound_hit = ANY (ARRAY['floor'::text, 'ceiling'::text]))),
    CONSTRAINT wna_clamp_events_clamp_basis_check CHECK ((clamp_basis = ANY (ARRAY['percent_of_base'::text, 'dollars'::text]))),
    CONSTRAINT wna_clamp_events_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id),
    CONSTRAINT wna_clamp_events_wna_zone_id_fkey FOREIGN KEY (wna_zone_id) REFERENCES public.wna_zones(id),
    CONSTRAINT wna_clamp_events_wna_monthly_adjustment_id_fkey FOREIGN KEY (wna_monthly_adjustment_id) REFERENCES public.wna_monthly_adjustments(id),
    CONSTRAINT wna_clamp_events_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.customers(id),
    CONSTRAINT wna_clamp_events_invoice_id_fkey FOREIGN KEY (invoice_id) REFERENCES public.invoices(id)
);

CREATE INDEX IF NOT EXISTS idx_wna_clamp_events_tenant_month ON public.wna_clamp_events USING btree (tenant_id, billing_month);
CREATE INDEX IF NOT EXISTS idx_wna_clamp_events_zone ON public.wna_clamp_events USING btree (wna_zone_id);
CREATE INDEX IF NOT EXISTS idx_wna_clamp_events_customer ON public.wna_clamp_events USING btree (customer_id);
CREATE INDEX IF NOT EXISTS idx_wna_clamp_events_invoice ON public.wna_clamp_events USING btree (invoice_id);

ALTER TABLE public.wna_clamp_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.wna_clamp_events FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_isolation ON public.wna_clamp_events;
CREATE POLICY tenant_isolation ON public.wna_clamp_events USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));

COMMENT ON TABLE public.wna_clamp_events IS
    'Append-only log of WNA floor/ceiling clamps (T-4, v5.4.0-03): one row each time a bill''s raw WNA adjustment exceeded a configured bound and was clamped. Bound values are snapshotted at clamp time (floor/ceiling_value_at_clamp) so the event stays reproducible after zone config changes. Immutable by convention — no update trigger; per-domain event-table idiom (dunning_events, escheatment_events).';

--
-- Item 7 — prorate_tier_breakpoints default flips to true (T-3, per
-- CI-108): prorate unless the tariff forbids it; tariffs forbidding
-- proration are the explicit opt-out. The old default silently reproduced
-- the CC&B under-proration bug on every new rate schedule. Existing-row
-- review: vacuous — no database with data exists anywhere.
--
ALTER TABLE public.rate_schedules ALTER COLUMN prorate_tier_breakpoints SET DEFAULT true;

COMMENT ON COLUMN public.rate_schedules.prorate_tier_breakpoints IS
    'When true AND partial period applies, Phase 4 scales tier ceilings by days_covered/days_in_period before allocating consumption to tiers. Prevents short-period customers from being pushed into higher tiers unfairly. Example: customer billed for 12 days of a 30-day cycle, tier 1 ceiling 2000 gal becomes 800 gal (2000 * 12/30). Default TRUE as of v5.4.0-03 (T-3, per CI-108): prorate unless the tariff explicitly forbids it — the old false default silently reproduced the CC&B under-proration bug on every new rate schedule. Set false only when the filed tariff forbids proration.';
