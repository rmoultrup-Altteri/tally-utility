-- ============================================================================
-- PATCH v5.4.0-04 — Programs & lifecycle: the A-11 enrollment substrate
--                   + backlog item 10 (expiry-type enum, D8-2)
-- ============================================================================
-- Authority:   Appendix A-11 locked design (Q-13 resolution, 2026-05-26) plus
--              its v5.4 implementation decisions (2026-05-29) — followed to
--              the letter; and Kyle ruling D8-2 (2026-07-10): expiry-type
--              enum (calendar|event) + nullable end date — bankruptcy holds
--              are event-terminated, never date-terminated; the system never
--              demands a fake end date and never auto-expires on a calendar
--              tick. A bankruptcy hold IS a bankruptcy_automatic_stay
--              enrollment row, so item 10's column lands on this table.
-- CI entries:  Closes structurally: CI-061, CI-064, CI-066. Closes by
--              design (workflow logic remains): CI-059, CI-060, CI-062,
--              CI-063, CI-065. CI-082 (bankruptcy stay = one enrollment
--              row) re-graded. Composition substrate for CI-067/069/081/105.
-- Contents:    program_types reference table (platform-global, 11 seeded
--              rows); customer_program_enrollments (lifecycle, attestation,
--              supersede lineage, per-type jsonb payload); trigger-maintained
--              customers.do_not_disconnect denormalization; DROP of the four
--              customers.disconnect_protection_* columns (clean drop, no
--              backfill — no production data exists anywhere, per the
--              2026-08-18 provenance); compliance_statistics rebuilt with a
--              LEFT JOIN LATERAL to the most-recent active protective
--              enrollment (surface-continuity preserved: same columns, same
--              value sets).
-- Drafting decisions (delegated to patch time):
--              * program_types.is_disconnect_protective seeding: true for
--                the eight values of the old customers CHECK list (schema-
--                continuity — those were the disconnect-protection types the
--                register was graded against), false for the three new
--                financial/comms programs (agency_pledge, budget_billing,
--                third_party_notification). The flag is ops-editable
--                reference data BY DESIGN (A-11), so a per-type correction
--                (e.g., if elderly_disabled turns out to be deposit-waiver-
--                only in Texas, per the Family 9 research direction) is a
--                row update, not a migration.
--              * program_types is read-only for tally_app (explicit REVOKE
--                of DML): a platform-global, RLS-less table must not be
--                writable through the runtime credential. Managing it is
--                migration/ops work.
--              * status defaults to 'pending_application' (the state
--                machine's entry state; A-11 names the enum but no default).
--              * expiry_type defaults to 'calendar' (the common case;
--                event-terminated is the bankruptcy/court-event pattern).
--              * agency_pledge / third_party_notification ship substrate-
--                only per the A-11 ruling — enum rows exist, no workflow.
-- Idempotent:  yes (CREATE TABLE/INDEX IF NOT EXISTS; CREATE OR REPLACE
--              FUNCTION; triggers/policies/constraints DROP IF EXISTS +
--              re-ADD; seeds ON CONFLICT DO NOTHING; DROP COLUMN IF EXISTS;
--              matview DROP IF EXISTS + re-CREATE).
-- Line count:  mirrored into tu.sql as a pure APPEND at end of file — no
--              existing line shifts; anchors 337/3600/3679 unaffected.
--              (The dropped customers columns' original CREATE TABLE lines
--              remain in the file body as history; the append is what runs
--              last and wins.)
-- ============================================================================

--
-- The old single-slot representation goes away. The matview reads the
-- dropped columns, so it goes first (rebuilt at the end of this patch).
--
DROP MATERIALIZED VIEW IF EXISTS public.compliance_statistics;

--
-- program_types — the first genuinely platform-global reference table in
-- the schema (A-11: no tenant_id, no RLS, public read). The
-- is_disconnect_protective flag is what the denormalization trigger reads;
-- encoding it as reference data lets ops add program types without code
-- changes.
--
CREATE TABLE IF NOT EXISTS public.program_types (
    code text NOT NULL,
    display_name text NOT NULL,
    is_disconnect_protective boolean NOT NULL,
    description text,
    CONSTRAINT program_types_pkey PRIMARY KEY (code)
);

INSERT INTO public.program_types (code, display_name, is_disconnect_protective, description) VALUES
    ('medical_certificate',       'Medical Certificate',            true,  'Physician-attested serious-illness hold (16 TAC 7.45(4)(H)); Texas requires composition with an active payment_arrangement (CI-081). Texas-v1 workflow ships.'),
    ('elderly_disabled',          'Elderly / Disabled',             true,  'Elderly or disabled customer program; Texas deposit waiver per CI-129. Protective flag carried over from the pre-v5.4.0-04 disconnect_protection_type list; ops-editable if the tariff scopes it to deposits only. Texas-v1 workflow ships.'),
    ('military_deployment_scra',  'Military Deployment (SCRA)',     true,  'Servicemembers Civil Relief Act active-duty protections. Renamed from military_deployment (enum-level only). Substrate only in Texas-v1; workflow deferred.'),
    ('bankruptcy_automatic_stay', 'Bankruptcy Automatic Stay',      true,  'Federal 11 USC 362/366 stay. Event-terminated per D8-2: expiry_type = event, end date NULL until the operator records the court event (discharge/dismissal). Texas-v1 workflow ships.'),
    ('regulatory_moratorium',     'Regulatory Moratorium',          true,  'Weather or commission-ordered disconnect moratorium (Texas EWE per CI-080 is self-executing at/below 32F, county-level). Texas-v1 workflow ships.'),
    ('payment_arrangement',       'Payment Arrangement',            true,  'Installment / deferred-payment agreement. Max one active per account (D8-3, enforced by the active-row unique index); breach is terminal with a tenant-configurable grace window (D8-1). Texas-v1 workflow ships.'),
    ('pending_dispute',           'Pending Dispute',                true,  'Formal dispute in progress; disconnect suspended while pending. Texas-v1 workflow ships.'),
    ('agency_pledge',             'Agency Pledge',                  false, 'Energy-assistance agency payment commitment. Substrate only per the A-11 ruling; workflow deferred.'),
    ('budget_billing',            'Budget Billing',                 false, 'Levelized monthly billing with periodic settle-up. Substrate only; workflow deferred.'),
    ('third_party_notification',  'Third-Party Notification',       false, 'CC a designated third party on delinquency/disconnect notices. Substrate only per the A-11 ruling; workflow deferred.'),
    ('other',                     'Other',                          true,  'Catch-all carried over from the pre-v5.4.0-04 protection-type list; protective by continuity with that list''s semantics.')
ON CONFLICT (code) DO NOTHING;

COMMENT ON TABLE public.program_types IS
    'Platform-global program-type reference (A-11, v5.4.0-04): no tenant_id, no RLS, read-only for the application role. is_disconnect_protective drives the customers.do_not_disconnect denormalization trigger. Forward-compatible with per-tenant extensibility (add tenant_id + RLS) if a real requirement surfaces in v5.5+.';

--
-- customer_program_enrollments — one row per (customer x program x
-- effective bracket). Lifecycle mirrors the CI-046 exemption-cert state
-- machine; renewal is supersede-on-recertify, never in-place mutation.
--
CREATE TABLE IF NOT EXISTS public.customer_program_enrollments (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id uuid NOT NULL,
    customer_id uuid NOT NULL,
    program_type text NOT NULL,
    effective_start_date date NOT NULL,
    effective_end_date date,
    expiry_type text DEFAULT 'calendar'::text NOT NULL,
    status text DEFAULT 'pending_application'::text NOT NULL,
    attestation_artifact_url text,
    attestation_received_at timestamp with time zone,
    attestation_verified_at timestamp with time zone,
    attestation_verified_by uuid,
    enrollment_data jsonb DEFAULT '{}'::jsonb NOT NULL,
    notes text,
    enrolled_by uuid,
    supersedes_enrollment_id uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT customer_program_enrollments_pkey PRIMARY KEY (id),
    CONSTRAINT customer_program_enrollments_status_check CHECK ((status = ANY (ARRAY['pending_application'::text, 'active'::text, 'expired'::text, 'breached'::text, 'canceled'::text, 'superseded'::text]))),
    CONSTRAINT customer_program_enrollments_expiry_type_check CHECK ((expiry_type = ANY (ARRAY['calendar'::text, 'event'::text]))),
    CONSTRAINT customer_program_enrollments_enrollment_data_check CHECK ((jsonb_typeof(enrollment_data) = 'object'::text)),
    CONSTRAINT customer_program_enrollments_dates_check CHECK (((effective_end_date IS NULL) OR (effective_end_date >= effective_start_date))),
    CONSTRAINT customer_program_enrollments_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id),
    CONSTRAINT customer_program_enrollments_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.customers(id),
    CONSTRAINT customer_program_enrollments_program_type_fkey FOREIGN KEY (program_type) REFERENCES public.program_types(code),
    CONSTRAINT customer_program_enrollments_attestation_verified_by_fkey FOREIGN KEY (attestation_verified_by) REFERENCES public.users(id),
    CONSTRAINT customer_program_enrollments_enrolled_by_fkey FOREIGN KEY (enrolled_by) REFERENCES public.users(id),
    CONSTRAINT customer_program_enrollments_supersedes_enrollment_id_fkey FOREIGN KEY (supersedes_enrollment_id) REFERENCES public.customer_program_enrollments(id)
);

-- The A-11 index set, exactly as specified:
CREATE INDEX IF NOT EXISTS idx_cpe_tenant_customer ON public.customer_program_enrollments USING btree (tenant_id, customer_id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_cpe_one_active_per_type ON public.customer_program_enrollments USING btree (tenant_id, customer_id, program_type) WHERE (status = 'active'::text);
CREATE INDEX IF NOT EXISTS idx_cpe_recert_due ON public.customer_program_enrollments USING btree (tenant_id, status, effective_end_date) WHERE (status = ANY (ARRAY['active'::text, 'pending_application'::text]));
CREATE INDEX IF NOT EXISTS idx_cpe_type_status ON public.customer_program_enrollments USING btree (tenant_id, program_type, status);
CREATE INDEX IF NOT EXISTS idx_cpe_enrollment_data ON public.customer_program_enrollments USING gin (enrollment_data);

COMMENT ON TABLE public.customer_program_enrollments IS
    'Program-enrollment substrate (A-11 locked design, v5.4.0-04): one row per (customer x program x effective bracket). Replaces the single-slot customers.disconnect_protection_* columns entirely. Lifecycle mirrors CI-046: recertification supersedes (flips the prior row to superseded, inserts a new active row linked via supersedes_enrollment_id) — never mutates in place. Per-type payload shapes documented on enrollment_data. Enrollment state-change audit deliberately deferred to A-21.';

COMMENT ON COLUMN public.customer_program_enrollments.effective_end_date IS
    'Nullable by ruling (D8-2): event-terminated enrollments (expiry_type = event, e.g. bankruptcy_automatic_stay) carry NULL until the operator records the terminating court event. The system never demands a fake end date. For calendar enrollments, the recertification-due job reads this via idx_cpe_recert_due.';

COMMENT ON COLUMN public.customer_program_enrollments.expiry_type IS
    'How this enrollment ends (D8-2, backlog item 10): calendar (date-driven; end date read by the recert job) or event (terminated only by explicit operator action recording the real-world event — discharge/dismissal for bankruptcy. NO automation ever auto-expires an event row on a calendar tick).';

COMMENT ON COLUMN public.customer_program_enrollments.enrollment_data IS
    'Per-type payload (A-11; object-shape CHECK only — per-type field CHECKs are an accepted tradeoff). Documented shapes: medical_certificate {physician_name, physician_phone, condition_classification, attestation_renewal_due_date}; military_deployment_scra {active_duty_start, active_duty_end_estimated, dmdc_verified_at, dmdc_query_id, scra_interest_cap_percent}; bankruptcy_automatic_stay {petition_date, chapter, case_number, court_jurisdiction, attorney_name, attorney_phone}; payment_arrangement {total_amount, installment_amount, installment_count, installments_paid, breach_trigger_config, breach_grace_days}; agency_pledge {agency_name, pledge_date, expected_receipt_date, expected_amount, actual_receipt_date, actual_amount}; budget_billing {levelized_amount, review_cadence_months, anniversary_settle_up_month, current_budget_balance}.';

--
-- Trigger 1: customer_id is immutable (A-11 implementation decision) —
-- re-assigning an enrollment is cancel + recreate, and immutability keeps
-- the do_not_disconnect recomputation to one customer per fire.
--
CREATE OR REPLACE FUNCTION public.enforce_enrollment_customer_immutable() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NEW.customer_id IS DISTINCT FROM OLD.customer_id THEN
        RAISE EXCEPTION 'customer_program_enrollments.customer_id is immutable (enrollment %); cancel and recreate to move an enrollment', OLD.id;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS enrollment_customer_immutable ON public.customer_program_enrollments;
CREATE TRIGGER enrollment_customer_immutable BEFORE UPDATE ON public.customer_program_enrollments FOR EACH ROW EXECUTE FUNCTION public.enforce_enrollment_customer_immutable();

--
-- Trigger 2: supersede-chain integrity (A-11) — the partial unique on
-- active rows alone cannot catch chain corruption among non-active rows.
--
CREATE OR REPLACE FUNCTION public.validate_enrollment_supersedes_chain() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    parent public.customer_program_enrollments%ROWTYPE;
BEGIN
    IF NEW.supersedes_enrollment_id IS NULL THEN
        RETURN NEW;
    END IF;
    SELECT * INTO parent FROM public.customer_program_enrollments WHERE id = NEW.supersedes_enrollment_id;
    IF NOT FOUND THEN
        RETURN NEW;  -- FK handles nonexistence
    END IF;
    IF parent.tenant_id IS DISTINCT FROM NEW.tenant_id
       OR parent.customer_id IS DISTINCT FROM NEW.customer_id
       OR parent.program_type IS DISTINCT FROM NEW.program_type THEN
        RAISE EXCEPTION 'supersedes_enrollment_id % does not match this row''s (tenant_id, customer_id, program_type) — renewal chains may not cross tenants, customers, or program types', NEW.supersedes_enrollment_id;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS enrollment_supersedes_chain ON public.customer_program_enrollments;
CREATE TRIGGER enrollment_supersedes_chain BEFORE INSERT OR UPDATE ON public.customer_program_enrollments FOR EACH ROW EXECUTE FUNCTION public.validate_enrollment_supersedes_chain();

--
-- Trigger 3: the do_not_disconnect denormalization (A-11) — the collections
-- hot-path boolean is recomputed from active protective enrollments on
-- every enrollment change. A nightly reconciliation job (app-layer) catches
-- trigger-bypass drift.
--
CREATE OR REPLACE FUNCTION public.recompute_do_not_disconnect() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_customer_id uuid;
BEGIN
    v_customer_id := COALESCE(NEW.customer_id, OLD.customer_id);
    UPDATE public.customers c
       SET do_not_disconnect = EXISTS (
               SELECT 1
                 FROM public.customer_program_enrollments e
                 JOIN public.program_types pt ON pt.code = e.program_type
                WHERE e.customer_id = v_customer_id
                  AND e.status = 'active'
                  AND pt.is_disconnect_protective)
     WHERE c.id = v_customer_id;
    RETURN COALESCE(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS enrollment_recompute_dnd ON public.customer_program_enrollments;
CREATE TRIGGER enrollment_recompute_dnd AFTER INSERT OR UPDATE OR DELETE ON public.customer_program_enrollments FOR EACH ROW EXECUTE FUNCTION public.recompute_do_not_disconnect();

DROP TRIGGER IF EXISTS set_updated_at ON public.customer_program_enrollments;
CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.customer_program_enrollments FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();

--
-- RLS: full-CRUD tenant isolation (A-11 — enrollments mutate, so the
-- append-only pattern does not apply). Standard policy shape.
--
ALTER TABLE public.customer_program_enrollments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customer_program_enrollments FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_isolation ON public.customer_program_enrollments;
CREATE POLICY tenant_isolation ON public.customer_program_enrollments USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));

-- program_types is platform-global with no RLS: read-only for the app role.
REVOKE INSERT, UPDATE, DELETE ON public.program_types FROM tally_app;

--
-- The single-slot columns are replaced entirely (A-11: clean drop, no
-- backfill — no production data exists anywhere). do_not_disconnect and
-- the billing_hold* columns are preserved: the former as the trigger-
-- maintained denormalization, the latter as an independent admin axis.
--
ALTER TABLE public.customers DROP CONSTRAINT IF EXISTS customers_disconnect_protection_type_check;
ALTER TABLE public.customers DROP COLUMN IF EXISTS disconnect_protection_type;
ALTER TABLE public.customers DROP COLUMN IF EXISTS disconnect_protection_start;
ALTER TABLE public.customers DROP COLUMN IF EXISTS disconnect_protection_expiry;
ALTER TABLE public.customers DROP COLUMN IF EXISTS disconnect_protection_notes;

COMMENT ON COLUMN public.customers.do_not_disconnect IS
    'Trigger-maintained denormalization (A-11, v5.4.0-04): true iff the customer has at least one active enrollment whose program type is disconnect-protective. Recomputed by recompute_do_not_disconnect() on every customer_program_enrollments change; a nightly reconciliation job catches drift. NEVER set directly — it is the collections-engine hot-path filter, not an operator control. The pre-v5.4.0-04 disconnect_protection_* columns are dropped; enrollments are the source of truth.';

--
-- compliance_statistics rebuilt (A-11): the disconnect-protection columns
-- now come from a LEFT JOIN LATERAL to the most-recent active protective
-- enrollment. Column surface and value sets preserved for existing readers;
-- cost moves to refresh time. Same five indexes.
--
CREATE MATERIALIZED VIEW public.compliance_statistics AS
 SELECT c.tenant_id,
    c.id AS customer_id,
    c.customer_number,
    c.customer_type,
    c.is_tax_exempt,
    c.tax_exemption_reason,
    c.tax_exemption_expiry_date,
        CASE
            WHEN (c.is_tax_exempt = false) THEN 'not_exempt'::text
            WHEN (c.tax_exemption_expiry_date IS NULL) THEN 'permanent'::text
            WHEN (c.tax_exemption_expiry_date < CURRENT_DATE) THEN 'expired'::text
            WHEN (c.tax_exemption_expiry_date < (CURRENT_DATE + '60 days'::interval)) THEN 'expiring_soon'::text
            ELSE 'current'::text
        END AS tax_exemption_status,
    ((c.is_tax_exempt = true) AND (c.tax_exemption_expiry_date < CURRENT_DATE)) AS tax_exemption_expired,
    ((c.is_tax_exempt = true) AND (c.tax_exemption_expiry_date >= CURRENT_DATE) AND (c.tax_exemption_expiry_date < (CURRENT_DATE + '60 days'::interval))) AS tax_exemption_expiring_soon,
    c.do_not_disconnect,
    dp.program_type AS disconnect_protection_type,
    dp.effective_end_date AS disconnect_protection_expiry,
        CASE
            WHEN (c.do_not_disconnect = false) THEN 'no_protection'::text
            WHEN (dp.effective_end_date IS NULL) THEN 'permanent'::text
            WHEN (dp.effective_end_date < CURRENT_DATE) THEN 'expired'::text
            WHEN (dp.effective_end_date < (CURRENT_DATE + '30 days'::interval)) THEN 'expiring_soon'::text
            ELSE 'current'::text
        END AS disconnect_protection_status,
    ((c.do_not_disconnect = true) AND (dp.effective_end_date >= CURRENT_DATE) AND (dp.effective_end_date < (CURRENT_DATE + '30 days'::interval))) AS disconnect_protection_expiring,
    c.id_expiration_date,
    ((c.id_verified = true) AND (c.id_expiration_date IS NOT NULL) AND (c.id_expiration_date < CURRENT_DATE)) AS id_expired
   FROM (public.customers c
     LEFT JOIN LATERAL (
        SELECT e.program_type,
               e.effective_end_date
          FROM (public.customer_program_enrollments e
            JOIN public.program_types pt ON ((pt.code = e.program_type)))
         WHERE ((e.customer_id = c.id) AND (e.status = 'active'::text) AND (pt.is_disconnect_protective = true))
         ORDER BY e.effective_start_date DESC
         LIMIT 1) dp ON (true))
  WHERE (c.status = ANY (ARRAY['active'::text, 'final_billed'::text]))
  WITH NO DATA;

CREATE UNIQUE INDEX IF NOT EXISTS idx_compliance_stats_customer ON public.compliance_statistics USING btree (customer_id);
CREATE INDEX IF NOT EXISTS idx_compliance_stats_disconnect_expiring ON public.compliance_statistics USING btree (tenant_id) WHERE (disconnect_protection_expiring = true);
CREATE INDEX IF NOT EXISTS idx_compliance_stats_tax_expired ON public.compliance_statistics USING btree (tenant_id) WHERE (tax_exemption_expired = true);
CREATE INDEX IF NOT EXISTS idx_compliance_stats_tax_expiring ON public.compliance_statistics USING btree (tenant_id) WHERE (tax_exemption_expiring_soon = true);
CREATE INDEX IF NOT EXISTS idx_compliance_stats_tenant ON public.compliance_statistics USING btree (tenant_id);

COMMENT ON MATERIALIZED VIEW public.compliance_statistics IS
    'Rebuilt in v5.4.0-04 (A-11): disconnect-protection columns now derive from the most-recent active disconnect-protective enrollment via LEFT JOIN LATERAL, replacing the dropped customers.disconnect_protection_* columns. Column surface and value sets unchanged for existing readers.';
