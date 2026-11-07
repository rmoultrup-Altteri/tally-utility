-- ============================================================================
-- PATCH v5.4.2-24 — unmatched cash and agency pledges
-- ============================================================================
-- Authority:   Ryan, 2026-10-16: cash splits into -23 and -24; -24 is U
--              (unmatched cash) and L (agency pledges), new tables that point
--              at payments (DECISION-LOG 2026-10-16). Ryan, 2026-11-02: the
--              stream's order is -23, -27, -24. Ryan, 2026-11-07: a refund of
--              an agency's money goes to the agency, for every agency
--              (10 TAC 6.312(f); DECISION-LOG 2026-11-07).
-- Spec:        application/wave2-build-2026-10-15/v5.4.2-24-design.md.
--              ADDITIVE: new tables, nullable payment columns that name them,
--              new tenant settings keys; one program type retires (agency_
--              pledge, as -25 retired pending_dispute). No existing column
--              changes meaning.
-- Closes:      CI-053 (unapplied cash and suspense holding); CI-056's record
--              side (the pledge and suspense service level). The rows -26's
--              conditions agency_pledge and aged_suspense read.
--
-- ----------------------------------------------------------------------------
-- What changes
-- ----------------------------------------------------------------------------
--   * suspense_receipts: money the utility holds but cannot attribute to a
--     customer (payments.customer_id is NOT NULL, so it had no row). Add-
--     only. received_on is the money date and the service-level clock (NOT
--     NULL); created_at is the database's. Instrument evidence as a payment
--     has it; at least one evidence field with content. A provider
--     transaction id is held once across receipts and payments (CI-055).
--   * suspense_receipt_candidates: customers the money might be, with a
--     basis and a confidence. Evidence only: nothing moves money on it.
--   * A receipt leaves suspense by (1) payments that name it
--     (payments.suspense_receipt_id, with a reason and the operator), dated
--     on or after the money came and effective no later than that; (2)
--     dispositions: returned_to_sender, bank_returned, escheated, and undo
--     (a negative row naming one, at most its amount, never itself undone).
--     What it holds is derived (suspense_receipt_position_as_of). The cap:
--     on every date, what went to payments (not voided or reversed) and to
--     dispositions never exceeds the receipt. A reversed payment (posted to
--     the wrong customer) gives its share back; an NSF one does not.
--   * Tenant settings settings.suspense_service_level_days and settings.
--     suspense_retention_days (whole numbers > 0, no default; recorded in
--     tenant_configuration_history). Readers raise while unset (fail loud).
--   * assistance_agencies (retired by a stamp, never deleted) and
--     assistance_agency_agreements (dated terms: the pledge payment window,
--     the eligibility hold; withdrawn by a stamp, never edited).
--   * agency_pledges: typed amount, the agency's date and the database's
--     created_at; agreement_id and pay_by are the database's (the agreement
--     in force on pledged_on; pledged_on + its window). Several coexist.
--     agency_pledge_events end a pledge once: withdrawn, lapsed (only once
--     pay_by has passed everywhere) or recorded_in_error. Paid is derived:
--     what the payments naming it received.
--   * payments: agency_id (required for an agency's payment; on a refund,
--     the agency the refund is paid to), agency_pledge_id (of its agency and
--     customer), suspense_receipt_id with suspense_resolution_reason and
--     suspense_resolved_by. All written once, at insert.
--   * A refund of money that traces to an agency's payment names that agency;
--     a refund of the customer's own money names none (Ryan, 2026-11-07).
--   * The agency_pledge program type takes no new enrollment.
--
-- ----------------------------------------------------------------------------
-- Known limits (design section 6)
-- ----------------------------------------------------------------------------
--   L1 a receipt's candidates are as good as intake made them.
--   L2 a pledge's protection under statute (16 TAC 7.460(b)(2)) is wave 7's
--      law row; -26 makes the condition unevaluable until then, which blocks.
--   L3 agency remittance batches are matched by the core (no import route).
--   L4 the period close's snapshot carries no suspense line yet;
--      suspense_held_as_of gives the figure.
--   L5 an agency-paid deposit's return is not yet routed to the agency by the
--      database (-15 returns a deposit by its events, not a refund payment).
--
-- PRECONDITION. v5.4.2-23 and v5.4.2-27 applied. No agency_pledge enrollment
--   and no agency payment exist. Applied by a superuser, under READ
--   COMMITTED. A second run finds suspense_receipts and skips the whole
--   patch (psql's \if): apply it with psql.
-- ============================================================================

SELECT to_regclass('public.shortfall_applications') IS NULL AS no_27 \gset
\if :no_27
DO $$ BEGIN RAISE EXCEPTION 'v5.4.2-24 needs v5.4.2-27 (shortfall_applications is missing)'; END $$;
\endif
SELECT to_regclass('public.suspense_receipts') IS NOT NULL AS already \gset
\if :already
DO $$ BEGIN RAISE NOTICE 'v5.4.2-24: already applied (suspense_receipts exists); nothing to do'; END $$;
\else
BEGIN;

DO $$
DECLARE v_id uuid;
BEGIN
    SELECT e.id INTO v_id FROM public.customer_program_enrollments e WHERE e.program_type = 'agency_pledge' ORDER BY e.id LIMIT 1;
    IF v_id IS NOT NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('v5.4.2-24 retires the agency_pledge program type (a pledge becomes an agency_pledges row): enrollment %s would lose its meaning. Record it as a pledge first (DEPLOY-VERIFICATION -24)', v_id),
            ERRCODE = 'object_not_in_prerequisite_state';
    END IF;
    SELECT p.id INTO v_id FROM public.payments p WHERE p.payer_class = 'agency' ORDER BY p.id LIMIT 1;
    IF v_id IS NOT NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('v5.4.2-24 requires every agency payment to name its agency: payment %s has none. Record the agency first (DEPLOY-VERIFICATION -24)', v_id),
            ERRCODE = 'object_not_in_prerequisite_state';
    END IF;
END $$;

-- ----------------------------------------------------------------------------
-- 0. Shared helpers
-- ----------------------------------------------------------------------------
-- The latest date anywhere on earth now (UTC+14): a date no later than it has
-- begun somewhere. The earliest (UTC-12): a date before it has ended
-- everywhere.
CREATE OR REPLACE FUNCTION public.suspense_today_latest() RETURNS date
    LANGUAGE sql STABLE
    SET search_path = public, pg_temp
    AS $$ SELECT (pg_catalog.now() AT TIME ZONE 'Etc/GMT-14')::date $$;
CREATE OR REPLACE FUNCTION public.suspense_today_earliest() RETURNS date
    LANGUAGE sql STABLE
    SET search_path = public, pg_temp
    AS $$ SELECT (pg_catalog.now() AT TIME ZONE 'Etc/GMT+12')::date $$;
COMMENT ON FUNCTION public.suspense_today_latest() IS
    'v5.4.2-24. Today''s date at UTC+14: the latest date that has begun anywhere. A money date or a pledge date is no later than it.';
COMMENT ON FUNCTION public.suspense_today_earliest() IS
    'v5.4.2-24. Today''s date at UTC-12: a date before it has ended everywhere. A pledge lapses only once its pay_by is before it.';
REVOKE ALL ON FUNCTION public.suspense_today_latest() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.suspense_today_earliest() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.suspense_today_latest(), public.suspense_today_earliest() TO tally_app, tally_core;

-- A write that reads what other transactions committed must be at READ
-- COMMITTED: a snapshot taken before a lock was granted would hide them.
CREATE OR REPLACE FUNCTION public.suspense_require_read_committed(p_what text) RETURNS void
    LANGUAGE plpgsql STABLE
    SET search_path = public, pg_temp
    AS $$
BEGIN
    IF pg_catalog.current_setting('transaction_isolation') <> 'read committed' THEN
        RAISE EXCEPTION USING
            MESSAGE = format('%s is written at READ COMMITTED (this transaction is %s): it must see every row committed while it waited for its lock (v5.4.2-24)', p_what, pg_catalog.current_setting('transaction_isolation')),
            ERRCODE = 'invalid_transaction_state';
    END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.suspense_require_read_committed(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.suspense_require_read_committed(text) TO tally_app, tally_core;

-- ----------------------------------------------------------------------------
-- 1. Agencies and their agreements (design section 3)
-- ----------------------------------------------------------------------------
CREATE TABLE public.assistance_agencies (
    id              uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id       uuid NOT NULL,
    name            text NOT NULL,
    program_kind    text NOT NULL,
    contact_name    text,
    contact_phone   text,
    contact_email   text,
    status          text DEFAULT 'active' NOT NULL,
    retired_at      timestamp with time zone,
    retired_by      uuid,
    retired_reason  text,
    recorded_by     uuid NOT NULL,
    created_at      timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT assistance_agencies_pkey PRIMARY KEY (id),
    CONSTRAINT assistance_agencies_id_tenant_key UNIQUE (id, tenant_id),
    CONSTRAINT assistance_agencies_tenant_name_key UNIQUE (tenant_id, name),
    CONSTRAINT assistance_agencies_tenant_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants (id),
    CONSTRAINT assistance_agencies_recorded_by_fkey FOREIGN KEY (recorded_by, tenant_id) REFERENCES public.users (id, tenant_id),
    CONSTRAINT assistance_agencies_retired_by_fkey FOREIGN KEY (retired_by, tenant_id) REFERENCES public.users (id, tenant_id),
    CONSTRAINT assistance_agencies_name_check CHECK (name ~ '[[:alnum:]]'),
    CONSTRAINT assistance_agencies_program_kind_check
        CHECK (program_kind = ANY (ARRAY['liheap_ceap'::text, 'state_crisis'::text, 'charity'::text, 'government_other'::text])),
    CONSTRAINT assistance_agencies_status_check CHECK (status = ANY (ARRAY['active'::text, 'retired'::text])),
    CONSTRAINT assistance_agencies_retired_check
        CHECK ((status = 'retired') = (retired_at IS NOT NULL)
               AND (status = 'retired') = (retired_by IS NOT NULL)
               AND (status <> 'retired' OR coalesce(retired_reason ~ '[[:alnum:]]', false)))
);
COMMENT ON TABLE public.assistance_agencies IS
    'v5.4.2-24 (design section 3). An outside organization that pays toward a customer''s bill: the federal energy-assistance program''s local agencies (CEAP in Texas), state crisis funds, charities, other government funds. A relative or landlord paying is the customer''s own payment. Never deleted or edited: an agency is retired by a stamp (status, retired_by, retired_reason; retired_at is the database''s). A retired agency takes no new pledge or agreement; its money is still taken.';

CREATE OR REPLACE FUNCTION public.enforce_assistance_agency_retire() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
BEGIN
    -- The agency's lock: a pledge or agreement being written for it waits, or
    -- is seen by it (an advisory lock: tally_app holds no row-lock privilege).
    PERFORM pg_catalog.pg_advisory_xact_lock(public.cash_source_lock_key('agency', OLD.id));
    IF OLD.status <> 'active' OR NEW.status <> 'retired'
       OR (to_jsonb(NEW) - ARRAY['status', 'retired_at', 'retired_by', 'retired_reason'])
          IS DISTINCT FROM (to_jsonb(OLD) - ARRAY['status', 'retired_at', 'retired_by', 'retired_reason']) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('assistance agency %s: only its retirement is recorded (active to retired, with who and why); an agency is never edited or brought back — record a new one (v5.4.2-24)', OLD.id),
            ERRCODE = 'restrict_violation';
    END IF;
    NEW.retired_at := pg_catalog.now();
    RETURN NEW;
END;
$$;
CREATE TRIGGER enforce_assistance_agency_retire BEFORE UPDATE ON public.assistance_agencies
    FOR EACH ROW EXECUTE FUNCTION public.enforce_assistance_agency_retire();
ALTER TABLE public.assistance_agencies ENABLE ALWAYS TRIGGER enforce_assistance_agency_retire;

CREATE TABLE public.assistance_agency_agreements (
    id                              uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id                       uuid NOT NULL,
    agency_id                       uuid NOT NULL,
    effective_from                  date NOT NULL,
    pledge_payment_days             integer NOT NULL,
    eligibility_hold_business_days  integer NOT NULL,
    source_reference                text NOT NULL,
    recorded_by                     uuid NOT NULL,
    created_at                      timestamp with time zone DEFAULT now() NOT NULL,
    withdrawn_at                    timestamp with time zone,
    withdrawn_by                    uuid,
    withdrawn_reason                text,
    CONSTRAINT assistance_agency_agreements_pkey PRIMARY KEY (id),
    CONSTRAINT assistance_agency_agreements_id_tenant_key UNIQUE (id, tenant_id),
    CONSTRAINT assistance_agency_agreements_tenant_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants (id),
    CONSTRAINT assistance_agency_agreements_agency_fkey FOREIGN KEY (agency_id, tenant_id) REFERENCES public.assistance_agencies (id, tenant_id),
    CONSTRAINT assistance_agency_agreements_recorded_by_fkey FOREIGN KEY (recorded_by, tenant_id) REFERENCES public.users (id, tenant_id),
    CONSTRAINT assistance_agency_agreements_withdrawn_by_fkey FOREIGN KEY (withdrawn_by, tenant_id) REFERENCES public.users (id, tenant_id),
    CONSTRAINT assistance_agency_agreements_days_check
        CHECK (pledge_payment_days > 0 AND pledge_payment_days <= 366 AND eligibility_hold_business_days >= 0 AND eligibility_hold_business_days <= 60),
    CONSTRAINT assistance_agency_agreements_source_check CHECK (source_reference ~ '[[:alnum:]]'),
    CONSTRAINT assistance_agency_agreements_withdrawn_check
        CHECK ((withdrawn_at IS NULL) = (withdrawn_by IS NULL)
               AND (withdrawn_at IS NULL) = (withdrawn_reason IS NULL)
               AND (withdrawn_reason IS NULL OR withdrawn_reason ~ '[[:alnum:]]'))
);
CREATE UNIQUE INDEX assistance_agency_agreements_one_per_date
    ON public.assistance_agency_agreements (agency_id, effective_from) WHERE withdrawn_at IS NULL;
COMMENT ON TABLE public.assistance_agency_agreements IS
    'v5.4.2-24 (design section 3). The agreement in force with an agency from effective_from until the next one: its contract terms (pledge_payment_days: the agency pays a pledge within this many days of making it, TDHCA CEAP 45; eligibility_hold_business_days: service held while the agency determines eligibility, CEAP 5) and its source (the signed agreement and revision). Contract terms, not law: the statutory protection of a pledge is wave 7''s law row. Never edited; one entered in error is withdrawn by a stamp (withdrawn_by, withdrawn_reason; withdrawn_at is the database''s) and is then never chosen for a pledge. A pledge records the agreement chosen for it.';

CREATE OR REPLACE FUNCTION public.enforce_assistance_agreement() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF NEW.withdrawn_at IS NOT NULL OR NEW.withdrawn_by IS NOT NULL OR NEW.withdrawn_reason IS NOT NULL THEN
            RAISE EXCEPTION USING
                MESSAGE = 'an agency agreement is born in force: a withdrawal is recorded afterwards (v5.4.2-24)',
                ERRCODE = 'check_violation';
        END IF;
        PERFORM public.suspense_require_read_committed('an agency agreement');
        PERFORM pg_catalog.pg_advisory_xact_lock(public.cash_source_lock_key('agency', NEW.agency_id));
        IF NOT EXISTS (SELECT 1 FROM public.assistance_agencies a WHERE a.id = NEW.agency_id AND a.status = 'active') THEN
            RAISE EXCEPTION USING
                MESSAGE = format('agency %s is retired (or not visible): it takes no new agreement (v5.4.2-24)', NEW.agency_id),
                ERRCODE = 'check_violation';
        END IF;
        RETURN NEW;
    END IF;
    PERFORM pg_catalog.pg_advisory_xact_lock(public.cash_source_lock_key('agency', OLD.agency_id));
    IF OLD.withdrawn_at IS NOT NULL OR NEW.withdrawn_by IS NULL
       OR (to_jsonb(NEW) - ARRAY['withdrawn_at', 'withdrawn_by', 'withdrawn_reason'])
          IS DISTINCT FROM (to_jsonb(OLD) - ARRAY['withdrawn_at', 'withdrawn_by', 'withdrawn_reason']) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('agency agreement %s: only its withdrawal is recorded (once, with who and why); its terms are never edited — record a new agreement (v5.4.2-24)', OLD.id),
            ERRCODE = 'restrict_violation';
    END IF;
    NEW.withdrawn_at := pg_catalog.now();
    RETURN NEW;
END;
$$;
CREATE TRIGGER enforce_assistance_agreement BEFORE INSERT OR UPDATE ON public.assistance_agency_agreements
    FOR EACH ROW EXECUTE FUNCTION public.enforce_assistance_agreement();
ALTER TABLE public.assistance_agency_agreements ENABLE ALWAYS TRIGGER enforce_assistance_agreement;

-- The agreement in force on a date: the latest not withdrawn from on or
-- before it. NULL if none.
CREATE OR REPLACE FUNCTION public.assistance_agreement_in_force(p_agency_id uuid, p_on date) RETURNS uuid
    LANGUAGE plpgsql STABLE
    SET search_path = public, pg_temp
    AS $$
BEGIN
    IF p_agency_id IS NULL OR p_on IS NULL OR NOT pg_catalog.isfinite(p_on) THEN
        RAISE EXCEPTION USING
            MESSAGE = 'assistance_agreement_in_force: an agency and a finite date, both given (v5.4.2-24)',
            ERRCODE = 'null_value_not_allowed';
    END IF;
    RETURN (SELECT g.id FROM public.assistance_agency_agreements g
             WHERE g.agency_id = p_agency_id AND g.effective_from <= p_on AND g.withdrawn_at IS NULL
             ORDER BY g.effective_from DESC LIMIT 1);
END;
$$;
COMMENT ON FUNCTION public.assistance_agreement_in_force(uuid, date) IS
    'v5.4.2-24. The agency''s agreement in force on p_on: the latest not withdrawn whose effective_from is on or before it; NULL if none. A pledge records the one chosen when it is written, so a later withdrawal does not move it.';
REVOKE ALL ON FUNCTION public.assistance_agreement_in_force(uuid, date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.assistance_agreement_in_force(uuid, date) TO tally_app, tally_core;

-- ----------------------------------------------------------------------------
-- 2. Unmatched receipts (design section 2)
-- ----------------------------------------------------------------------------
CREATE TABLE public.suspense_receipts (
    id                       uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id                uuid NOT NULL,
    receipt_number           text NOT NULL,
    amount                   numeric(12,2) NOT NULL,
    received_on              date NOT NULL,
    channel                  text NOT NULL,
    source_system            text NOT NULL,
    reference_number         text,
    provider_transaction_id  text,
    check_number             text,
    check_date               date,
    check_bank_name          text,
    payer_name               text,
    payer_address            text,
    payer_account_text       text,
    agency_id                uuid,
    evidence_reference       text,
    notes                    text,
    recorded_by              uuid NOT NULL,
    created_at               timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT suspense_receipts_pkey PRIMARY KEY (id),
    CONSTRAINT suspense_receipts_id_tenant_key UNIQUE (id, tenant_id),
    CONSTRAINT suspense_receipts_tenant_number_key UNIQUE (tenant_id, receipt_number),
    CONSTRAINT suspense_receipts_tenant_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants (id),
    CONSTRAINT suspense_receipts_agency_fkey FOREIGN KEY (agency_id, tenant_id) REFERENCES public.assistance_agencies (id, tenant_id),
    CONSTRAINT suspense_receipts_recorded_by_fkey FOREIGN KEY (recorded_by, tenant_id) REFERENCES public.users (id, tenant_id),
    CONSTRAINT suspense_receipts_number_check CHECK (receipt_number ~ '[[:alnum:]]'),
    CONSTRAINT suspense_receipts_amount_check CHECK (amount > 0),
    CONSTRAINT suspense_receipts_channel_check
        CHECK (channel = ANY (ARRAY['portal'::text, 'mobile_app'::text, 'agent_phone'::text, 'ivr'::text, 'walk_in'::text, 'mail'::text, 'auto_pay'::text, 'batch_file'::text, 'api'::text, 'lockbox'::text])),
    CONSTRAINT suspense_receipts_source_system_check
        CHECK (source_system = ANY (ARRAY['internal'::text, 'paymentus_webhook'::text, 'stripe_webhook'::text, 'bank_lockbox'::text, 'imported'::text, 'other_webhook'::text])),
    -- At least one field a person could research the money by, with content.
    CONSTRAINT suspense_receipts_evidence_check
        CHECK (coalesce(reference_number ~ '[[:alnum:]]', false) OR coalesce(provider_transaction_id ~ '[[:alnum:]]', false)
               OR coalesce(check_number ~ '[[:alnum:]]', false) OR coalesce(payer_name ~ '[[:alnum:]]', false)
               OR coalesce(payer_account_text ~ '[[:alnum:]]', false) OR coalesce(evidence_reference ~ '[[:alnum:]]', false)
               OR agency_id IS NOT NULL)
);
CREATE UNIQUE INDEX suspense_receipts_provider_transaction_once
    ON public.suspense_receipts (tenant_id, source_system, provider_transaction_id) WHERE provider_transaction_id IS NOT NULL;
CREATE INDEX idx_suspense_receipts_tenant_date ON public.suspense_receipts (tenant_id, received_on);
COMMENT ON TABLE public.suspense_receipts IS
    'v5.4.2-24 (CI-053; design section 2). Money the utility holds and cannot yet attribute to a customer: on no customer''s ledger, never applied to a guessed account, never revenue. Add-only. received_on is the money date (the bank''s; frozen by the close) and the service-level clock; created_at is the database''s, the knowledge coordinate. It leaves suspense by payments naming it (suspense_receipt_id) and by dispositions; what it holds is derived (suspense_receipt_position_as_of). A provider transaction id is held once across receipts and payments (CI-055). Evidence: at least one research field with content.';
COMMENT ON COLUMN public.suspense_receipts.evidence_reference IS
    'v5.4.2-24. Where the evidence is: the intake file and row (an import job''s file and row number), an image or document reference.';

CREATE TABLE public.suspense_receipt_candidates (
    id                   uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id            uuid NOT NULL,
    suspense_receipt_id  uuid NOT NULL,
    customer_id          uuid NOT NULL,
    basis                text NOT NULL,
    confidence           numeric(5,4),
    note                 text,
    recorded_by          uuid,
    created_at           timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT suspense_receipt_candidates_pkey PRIMARY KEY (id),
    CONSTRAINT suspense_receipt_candidates_tenant_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants (id),
    CONSTRAINT suspense_receipt_candidates_receipt_fkey FOREIGN KEY (suspense_receipt_id, tenant_id) REFERENCES public.suspense_receipts (id, tenant_id),
    CONSTRAINT suspense_receipt_candidates_customer_fkey FOREIGN KEY (customer_id, tenant_id) REFERENCES public.customers (id, tenant_id),
    CONSTRAINT suspense_receipt_candidates_recorded_by_fkey FOREIGN KEY (recorded_by, tenant_id) REFERENCES public.users (id, tenant_id),
    CONSTRAINT suspense_receipt_candidates_basis_check CHECK (basis = ANY (ARRAY['intake_match'::text, 'operator'::text])),
    CONSTRAINT suspense_receipt_candidates_confidence_check CHECK (confidence IS NULL OR (confidence >= 0 AND confidence <= 1)),
    CONSTRAINT suspense_receipt_candidates_operator_check CHECK (basis <> 'operator' OR recorded_by IS NOT NULL)
);
CREATE INDEX idx_suspense_candidates_receipt ON public.suspense_receipt_candidates (suspense_receipt_id);
CREATE INDEX idx_suspense_candidates_customer ON public.suspense_receipt_candidates (customer_id);
COMMENT ON TABLE public.suspense_receipt_candidates IS
    'v5.4.2-24 (CI-053; design section 2.2). A customer the intake or an operator thought a receipt might belong to: evidence, never an application. No guard reads it to move money. An aged receipt bars a disconnection on each of its candidates (CI-056; -26''s aged_suspense, read by the core). Add-only.';

CREATE TABLE public.suspense_receipt_dispositions (
    id                     uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id              uuid NOT NULL,
    suspense_receipt_id    uuid NOT NULL,
    kind                   text NOT NULL,
    amount                 numeric(12,2) NOT NULL,
    disposed_on            date NOT NULL,
    instrument_reference   text,
    return_code            text,
    jurisdiction           text,
    report_reference       text,
    reason                 text,
    recorded_by            uuid NOT NULL,
    undoes_disposition_id  uuid,
    created_at             timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT suspense_receipt_dispositions_pkey PRIMARY KEY (id),
    CONSTRAINT suspense_receipt_dispositions_id_receipt_key UNIQUE (id, tenant_id, suspense_receipt_id),
    CONSTRAINT suspense_receipt_dispositions_tenant_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants (id),
    CONSTRAINT suspense_receipt_dispositions_receipt_fkey FOREIGN KEY (suspense_receipt_id, tenant_id) REFERENCES public.suspense_receipts (id, tenant_id),
    CONSTRAINT suspense_receipt_dispositions_recorded_by_fkey FOREIGN KEY (recorded_by, tenant_id) REFERENCES public.users (id, tenant_id),
    CONSTRAINT suspense_receipt_dispositions_undoes_fkey
        FOREIGN KEY (undoes_disposition_id, tenant_id, suspense_receipt_id) REFERENCES public.suspense_receipt_dispositions (id, tenant_id, suspense_receipt_id),
    CONSTRAINT suspense_receipt_dispositions_not_self_check CHECK (undoes_disposition_id IS DISTINCT FROM id),
    CONSTRAINT suspense_receipt_dispositions_kind_check
        CHECK (CASE kind
                 WHEN 'returned_to_sender' THEN coalesce(instrument_reference ~ '[[:alnum:]]', false) AND return_code IS NULL AND jurisdiction IS NULL AND report_reference IS NULL
                 WHEN 'bank_returned' THEN (return_code IS NULL OR return_code ~ '^R[0-9]{2}$') AND jurisdiction IS NULL AND report_reference IS NULL
                 WHEN 'escheated' THEN coalesce(jurisdiction ~ '^[A-Z]{2}$', false) AND coalesce(report_reference ~ '[[:alnum:]]', false) AND return_code IS NULL
                 WHEN 'undo' THEN return_code IS NULL AND jurisdiction IS NULL AND report_reference IS NULL
                 ELSE false END),
    -- An undo, and only an undo, is negative and names the row it undoes.
    CONSTRAINT suspense_receipt_dispositions_undo_check
        CHECK (amount <> 0 AND (amount < 0) = (kind = 'undo') AND (kind = 'undo') = (undoes_disposition_id IS NOT NULL)),
    CONSTRAINT suspense_receipt_dispositions_reason_check CHECK (coalesce(reason ~ '[[:alnum:]]', false))
);
CREATE INDEX idx_suspense_dispositions_receipt ON public.suspense_receipt_dispositions (suspense_receipt_id, disposed_on);
CREATE INDEX idx_suspense_dispositions_undoes ON public.suspense_receipt_dispositions (undoes_disposition_id) WHERE undoes_disposition_id IS NOT NULL;
COMMENT ON TABLE public.suspense_receipt_dispositions IS
    'v5.4.2-24 (CI-053; design section 2.3). Money leaving a receipt other than as a payment: returned_to_sender (the outgoing instrument), bank_returned (the bank took it back while in suspense; an R-code where ACH), escheated (reported as unclaimed property: the state and the report; when is the core''s), and undo (a negative row naming one of the same receipt, dated on or after it, the undos of one at most its amount; an undo is never undone: a refund check that comes back uncashed). Every row says why and who. Add-only; disposed_on is frozen by the close. The receipt''s cap: on every date, its payments (not voided or reversed) and its dispositions never exceed it.';

-- ----------------------------------------------------------------------------
-- 3. Agency pledges (design section 4)
-- ----------------------------------------------------------------------------
CREATE TABLE public.agency_pledges (
    id                 uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id          uuid NOT NULL,
    customer_id        uuid NOT NULL,
    agency_id          uuid NOT NULL,
    agreement_id       uuid,
    amount             numeric(12,2) NOT NULL,
    pledged_on         date NOT NULL,
    pay_by             date,
    form               text NOT NULL,
    agency_reference   text,
    toward_invoice_id  uuid,
    notes              text,
    recorded_by        uuid NOT NULL,
    created_at         timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT agency_pledges_pkey PRIMARY KEY (id),
    CONSTRAINT agency_pledges_id_tenant_key UNIQUE (id, tenant_id),
    CONSTRAINT agency_pledges_tenant_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants (id),
    CONSTRAINT agency_pledges_customer_fkey FOREIGN KEY (customer_id, tenant_id) REFERENCES public.customers (id, tenant_id),
    CONSTRAINT agency_pledges_agency_fkey FOREIGN KEY (agency_id, tenant_id) REFERENCES public.assistance_agencies (id, tenant_id),
    CONSTRAINT agency_pledges_agreement_fkey FOREIGN KEY (agreement_id, tenant_id) REFERENCES public.assistance_agency_agreements (id, tenant_id),
    CONSTRAINT agency_pledges_invoice_fkey FOREIGN KEY (toward_invoice_id, tenant_id, customer_id) REFERENCES public.invoices (id, tenant_id, customer_id),
    CONSTRAINT agency_pledges_recorded_by_fkey FOREIGN KEY (recorded_by, tenant_id) REFERENCES public.users (id, tenant_id),
    CONSTRAINT agency_pledges_amount_check CHECK (amount > 0),
    CONSTRAINT agency_pledges_form_check CHECK (form = ANY (ARRAY['written'::text, 'verbal'::text, 'portal'::text])),
    CONSTRAINT agency_pledges_pay_by_check CHECK ((agreement_id IS NULL) = (pay_by IS NULL) AND (pay_by IS NULL OR pay_by > pledged_on))
);
CREATE INDEX idx_agency_pledges_customer ON public.agency_pledges (customer_id, pledged_on);
CREATE INDEX idx_agency_pledges_tenant ON public.agency_pledges (tenant_id, pay_by);
CREATE INDEX idx_agency_pledges_agency ON public.agency_pledges (agency_id);
COMMENT ON TABLE public.agency_pledges IS
    'v5.4.2-24 (CI-056; design section 4). An agency''s commitment to pay toward a customer''s bill. Typed amount and dates (they decide a disconnection). pledged_on is the agency''s date; created_at the database''s (when the utility recorded it). agreement_id and pay_by are the database''s: the agency''s agreement in force on pledged_on, and pledged_on plus its pledge_payment_days; both NULL when no agreement is on file (the pledge is still recorded; its reader says no_agreement, and -26 reads that as unevaluable, which blocks). Several pledges of a customer coexist. Add-only; ended once by agency_pledge_events; paid is derived from the payments naming it (agency_pledge_position_as_of). The form is recorded because the law row may count only a written pledge (16 TAC 7.460(b)(2)).';

CREATE TABLE public.agency_pledge_events (
    id                uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id         uuid NOT NULL,
    agency_pledge_id  uuid NOT NULL,
    event             text NOT NULL,
    event_on          date,
    reason            text,
    agency_reference  text,
    recorded_by       uuid NOT NULL,
    created_at        timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT agency_pledge_events_pkey PRIMARY KEY (id),
    CONSTRAINT agency_pledge_events_one_per_pledge UNIQUE (agency_pledge_id),
    CONSTRAINT agency_pledge_events_tenant_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants (id),
    CONSTRAINT agency_pledge_events_pledge_fkey FOREIGN KEY (agency_pledge_id, tenant_id) REFERENCES public.agency_pledges (id, tenant_id),
    CONSTRAINT agency_pledge_events_recorded_by_fkey FOREIGN KEY (recorded_by, tenant_id) REFERENCES public.users (id, tenant_id),
    CONSTRAINT agency_pledge_events_event_check CHECK (event = ANY (ARRAY['withdrawn'::text, 'lapsed'::text, 'recorded_in_error'::text])),
    CONSTRAINT agency_pledge_events_event_on_check CHECK ((event = 'recorded_in_error') = (event_on IS NULL)),
    CONSTRAINT agency_pledge_events_reason_check CHECK (coalesce(reason ~ '[[:alnum:]]', false))
);
COMMENT ON TABLE public.agency_pledge_events IS
    'v5.4.2-24 (design section 4.2). The one act that ends a pledge: withdrawn (by the agency, from event_on), lapsed (pay_by passed with the pledge not paid in full; event_on after pay_by, recorded only once pay_by has passed everywhere: the agency''s record of a pledge not honoured), recorded_in_error (never counted; only while no payment names it, and none may afterwards). Paid in full is not an event: it is read from the payments. A payment naming a lapsed or withdrawn pledge is still taken. Add-only; one per pledge.';

-- ----------------------------------------------------------------------------
-- 4. Payments name their receipt, agency and pledge (design 2.3, 4.3, 4.4)
-- ----------------------------------------------------------------------------
ALTER TABLE public.payments
    ADD COLUMN agency_id                   uuid,
    ADD COLUMN agency_pledge_id            uuid,
    ADD COLUMN suspense_receipt_id         uuid,
    ADD COLUMN suspense_resolution_reason  text,
    ADD COLUMN suspense_resolved_by        uuid,
    ADD CONSTRAINT payments_agency_fkey FOREIGN KEY (agency_id, tenant_id) REFERENCES public.assistance_agencies (id, tenant_id),
    ADD CONSTRAINT payments_agency_pledge_fkey FOREIGN KEY (agency_pledge_id, tenant_id) REFERENCES public.agency_pledges (id, tenant_id),
    ADD CONSTRAINT payments_suspense_receipt_fkey FOREIGN KEY (suspense_receipt_id, tenant_id) REFERENCES public.suspense_receipts (id, tenant_id),
    ADD CONSTRAINT payments_suspense_resolved_by_fkey FOREIGN KEY (suspense_resolved_by, tenant_id) REFERENCES public.users (id, tenant_id),
    -- Money in: an agency's payment names its agency, a customer's none. A
    -- refund's agency is whom it is paid to (enforce_payment_suspense_pledge).
    ADD CONSTRAINT payments_agency_check
        CHECK (payment_method = 'refund' OR (payer_class = 'agency') = (agency_id IS NOT NULL)),
    ADD CONSTRAINT payments_agency_pledge_check
        CHECK (agency_pledge_id IS NULL OR (agency_id IS NOT NULL AND payment_method <> 'refund' AND NOT is_deposit AND amount > 0)),
    -- A resolution of a receipt says why and who; the provider's transaction
    -- id stays on the receipt (it is held once).
    ADD CONSTRAINT payments_suspense_resolution_check
        CHECK ((suspense_receipt_id IS NULL) = (suspense_resolution_reason IS NULL)
               AND (suspense_receipt_id IS NULL) = (suspense_resolved_by IS NULL)
               AND (suspense_resolution_reason IS NULL OR suspense_resolution_reason ~ '[[:alnum:]]')
               AND (suspense_receipt_id IS NULL OR (payment_method <> 'refund' AND amount > 0 AND provider_transaction_id IS NULL)));
CREATE INDEX idx_payments_suspense_receipt ON public.payments (suspense_receipt_id) WHERE suspense_receipt_id IS NOT NULL;
CREATE INDEX idx_payments_agency_pledge ON public.payments (agency_pledge_id) WHERE agency_pledge_id IS NOT NULL;
CREATE INDEX idx_payments_agency ON public.payments (agency_id) WHERE agency_id IS NOT NULL;
COMMENT ON COLUMN public.payments.agency_id IS
    'v5.4.2-24 (design 4.3, 4.4). On money in: the agency that paid (required when payer_class is agency, absent otherwise). On a refund: the agency the refund is paid to — required when the refunded money traces to an agency''s payment, absent when it is the customer''s own (Ryan, 2026-11-07; 10 TAC 6.312(f)). Written once, at insert.';
COMMENT ON COLUMN public.payments.agency_pledge_id IS
    'v5.4.2-24 (design 4.2). The pledge this agency payment pays: of the payment''s agency and customer, not recorded in error. Written once, at insert. What it received counts toward the pledge (agency_pledge_position_as_of); a payment above the pledge is still taken.';
COMMENT ON COLUMN public.payments.suspense_receipt_id IS
    'v5.4.2-24 (design 2.3). The unmatched receipt this payment''s money came from, with suspense_resolution_reason and suspense_resolved_by (CI-049, CI-053). Dated on or after the receipt''s received_on, effective no later than it; carries its channel, source system and instrument; of its agency where it names one. Written once, at insert.';

-- The money a refund pays out traces to an agency's payment, or to the
-- customer. Walks -23's and -27's lineage: a payment (an agency's, or a
-- refund paid to one); a credit by its origin (overpayment: its payment;
-- refund_reissue: the refund it reissues; shortfall_reissue: the source of
-- the undone repayment). NULL: the customer's own money.
CREATE OR REPLACE FUNCTION public.cash_money_agency(p_payment_id uuid, p_credit_id uuid) RETURNS uuid
    LANGUAGE plpgsql STABLE
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_pay    uuid := p_payment_id;
    v_credit uuid := p_credit_id;
    p        public.payments%ROWTYPE;
    c        public.customer_credits%ROWTYPE;
    s        public.shortfall_applications%ROWTYPE;
    v_steps  integer := 0;
BEGIN
    IF num_nonnulls(p_payment_id, p_credit_id) <> 1 THEN
        RAISE EXCEPTION USING
            MESSAGE = 'cash_money_agency: one of a payment and a credit (v5.4.2-24)',
            ERRCODE = 'null_value_not_allowed';
    END IF;
    LOOP
        v_steps := v_steps + 1;
        IF v_steps > 1000 THEN
            RAISE EXCEPTION USING
                MESSAGE = format('cash_money_agency: the lineage of payment %s / credit %s is deeper than 1,000 steps (v5.4.2-24)', p_payment_id, p_credit_id),
                ERRCODE = 'program_limit_exceeded';
        END IF;
        IF v_pay IS NOT NULL THEN
            SELECT * INTO p FROM public.payments x WHERE x.id = v_pay;
            IF NOT FOUND THEN RETURN NULL; END IF;
            -- A payment in, or a refund: whose money it carries is its agency.
            RETURN p.agency_id;
        END IF;
        SELECT * INTO c FROM public.customer_credits x WHERE x.id = v_credit;
        IF NOT FOUND THEN RETURN NULL; END IF;
        IF c.origin_type = 'overpayment' AND c.source_payment_id IS NOT NULL THEN
            v_pay := c.source_payment_id; v_credit := NULL;
        ELSIF c.origin_type = 'refund_reissue' AND c.reissues_refund_id IS NOT NULL THEN
            v_pay := c.reissues_refund_id; v_credit := NULL;
        ELSIF c.origin_type = 'shortfall_reissue' AND c.reissues_shortfall_application_id IS NOT NULL THEN
            SELECT * INTO s FROM public.shortfall_applications x WHERE x.id = c.reissues_shortfall_application_id;
            IF NOT FOUND THEN RETURN NULL; END IF;
            v_pay := s.payment_id; v_credit := s.customer_credit_id;
        ELSE
            RETURN NULL;
        END IF;
    END LOOP;
END;
$$;
COMMENT ON FUNCTION public.cash_money_agency(uuid, uuid) IS
    'v5.4.2-24 (Ryan, 2026-11-07). The agency whose money a payment or a credit carries, or NULL for the customer''s own: a payment''s agency_id (an agency''s payment, or a refund paid to one); a credit by its origin (overpayment: its payment; refund_reissue: the refund it reissues; shortfall_reissue: the source of the repayment it carries). Bounded at 1,000 steps. A refund of it must name the same agency (enforce_payment_suspense_pledge).';
REVOKE ALL ON FUNCTION public.cash_money_agency(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.cash_money_agency(uuid, uuid) TO tally_app, tally_core;

-- The cap on a receipt: on every date, its live payments and its
-- dispositions never exceed it. Called under the receipt's lock.
CREATE OR REPLACE FUNCTION public.check_suspense_receipt_cap(p_receipt_id uuid) RETURNS void
    LANGUAGE plpgsql STABLE
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_amount numeric;
    v_number text;
    v_day    date;
    v_out    numeric;
BEGIN
    SELECT r.amount, r.receipt_number INTO v_amount, v_number FROM public.suspense_receipts r WHERE r.id = p_receipt_id;
    SELECT d, o INTO v_day, v_out FROM (
        SELECT e.d,
               coalesce((SELECT sum(p.amount) FROM public.payments p
                          WHERE p.suspense_receipt_id = p_receipt_id AND p.payment_date <= e.d
                            AND p.status NOT IN ('voided', 'reversed')), 0)
             + coalesce((SELECT sum(x.amount) FROM public.suspense_receipt_dispositions x
                          WHERE x.suspense_receipt_id = p_receipt_id AND x.disposed_on <= e.d), 0) AS o
          FROM (SELECT p.payment_date AS d FROM public.payments p WHERE p.suspense_receipt_id = p_receipt_id
                UNION SELECT x.disposed_on FROM public.suspense_receipt_dispositions x WHERE x.suspense_receipt_id = p_receipt_id) e
    ) w
    WHERE w.o > v_amount
    ORDER BY w.d LIMIT 1;
    IF v_day IS NOT NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('suspense receipt %s: on %s its payments and dispositions would come to %s, more than the %s the receipt holds (CI-053, v5.4.2-24)', v_number, v_day, v_out, v_amount),
            ERRCODE = 'check_violation';
    END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.check_suspense_receipt_cap(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.check_suspense_receipt_cap(uuid) TO tally_app;

-- One provider transaction across receipts and payments (CI-055). A receipt
-- is checked against receipts and payments; a payment against receipts only
-- (a second payment of one transaction is -19's unique index, which runs
-- after the CHECKs that name a mislabelled row first).
CREATE OR REPLACE FUNCTION public.check_provider_transaction_once(p_tenant uuid, p_source text, p_txn text, p_amount numeric, p_self uuid, p_self_is_receipt boolean) RETURNS void
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
BEGIN
    -- Money in only: a refund's provider id has its own space (-23's
    -- payments_provider_refund_once).
    IF p_txn IS NULL OR p_amount <= 0 THEN RETURN; END IF;
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('v5.4.2-24 txn ' || p_tenant::text || ' ' || p_source || ' ' || p_txn, 0));
    IF EXISTS (SELECT 1 FROM public.suspense_receipts r
                WHERE r.tenant_id = p_tenant AND r.source_system = p_source AND r.provider_transaction_id = p_txn AND r.id IS DISTINCT FROM p_self)
       OR (p_self_is_receipt AND EXISTS (SELECT 1 FROM public.payments p
                WHERE p.tenant_id = p_tenant AND p.source_system = p_source AND p.provider_transaction_id = p_txn AND p.amount > 0
                  AND p.id IS DISTINCT FROM p_self)) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('provider transaction %s from %s is already recorded as a receipt or a payment: money is recorded once (CI-055, v5.4.2-24)', p_txn, p_source),
            ERRCODE = 'unique_violation';
    END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.check_provider_transaction_once(uuid, text, text, numeric, uuid, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.check_provider_transaction_once(uuid, text, text, numeric, uuid, boolean) TO tally_app;

-- BEFORE INSERT OR UPDATE on payments: the new columns, for every role.
CREATE OR REPLACE FUNCTION public.enforce_payment_suspense_pledge() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    r          public.suspense_receipts%ROWTYPE;
    l          public.agency_pledges%ROWTYPE;
    v_changed  text[] := '{}';
    v_col      text;
    v_agency   uuid;
    c_once CONSTANT text[] := ARRAY['agency_id', 'agency_pledge_id', 'suspense_receipt_id', 'suspense_resolution_reason', 'suspense_resolved_by'];
BEGIN
    IF TG_OP = 'UPDATE' THEN
        FOREACH v_col IN ARRAY c_once LOOP
            IF to_jsonb(NEW) -> v_col IS DISTINCT FROM to_jsonb(OLD) -> v_col THEN v_changed := v_changed || v_col; END IF;
        END LOOP;
        IF cardinality(v_changed) > 0 THEN
            RAISE EXCEPTION USING
                MESSAGE = format('payment %s: %s is written once, at insert (v5.4.2-24) — reverse the payment and post a new one', OLD.payment_number, array_to_string(v_changed, ', ')),
                ERRCODE = 'restrict_violation';
        END IF;
        -- The effective date of a receipt's payment, when first written.
        IF NEW.suspense_receipt_id IS NOT NULL AND NEW.effective_date IS DISTINCT FROM OLD.effective_date AND NEW.effective_date IS NOT NULL THEN
            SELECT * INTO r FROM public.suspense_receipts x WHERE x.id = NEW.suspense_receipt_id;
            IF NEW.effective_date > r.received_on THEN
                RAISE EXCEPTION USING
                    MESSAGE = format('payment %s from receipt %s is effective %s: a payment from a receipt is effective no later than %s, the day the money came (CI-058, v5.4.2-24)', NEW.payment_number, r.receipt_number, NEW.effective_date, r.received_on),
                    ERRCODE = 'check_violation';
            END IF;
        END IF;
        RETURN NEW;
    END IF;

    -- INSERT. One provider transaction across receipts and payments (a
    -- second payment of it is -19's payments_provider_transaction_once).
    PERFORM public.check_provider_transaction_once(NEW.tenant_id, NEW.source_system, NEW.provider_transaction_id, NEW.amount, NEW.id, false);

    -- (A refund naming a receipt is refused by payments_suspense_resolution_check.)
    IF NEW.suspense_receipt_id IS NOT NULL AND NEW.payment_method <> 'refund' THEN
        PERFORM public.suspense_require_read_committed('a payment from a suspense receipt');
        SELECT * INTO r FROM public.suspense_receipts x WHERE x.id = NEW.suspense_receipt_id AND x.tenant_id = NEW.tenant_id;
        IF NOT FOUND THEN
            RAISE EXCEPTION USING
                MESSAGE = format('payment %s: suspense receipt %s is not visible in this tenant (v5.4.2-24)', NEW.payment_number, NEW.suspense_receipt_id),
                ERRCODE = 'foreign_key_violation', CONSTRAINT = 'payments_suspense_receipt_fkey';
        END IF;
        IF NEW.payment_date < r.received_on THEN
            RAISE EXCEPTION USING
                MESSAGE = format('payment %s is dated %s: a payment from receipt %s is dated on or after the receipt''s received_on (%s) (v5.4.2-24)', NEW.payment_number, NEW.payment_date, r.receipt_number, r.received_on),
                ERRCODE = 'check_violation';
        END IF;
        IF NEW.effective_date IS NOT NULL AND NEW.effective_date > r.received_on THEN
            RAISE EXCEPTION USING
                MESSAGE = format('payment %s from receipt %s is effective %s: a payment from a receipt is effective no later than %s, the day the money came (CI-058, v5.4.2-24)', NEW.payment_number, r.receipt_number, NEW.effective_date, r.received_on),
                ERRCODE = 'check_violation';
        END IF;
        IF NEW.channel IS DISTINCT FROM r.channel OR NEW.source_system IS DISTINCT FROM r.source_system
           OR NEW.reference_number IS DISTINCT FROM r.reference_number OR NEW.check_number IS DISTINCT FROM r.check_number
           OR NEW.check_date IS DISTINCT FROM r.check_date OR NEW.check_bank_name IS DISTINCT FROM r.check_bank_name THEN
            RAISE EXCEPTION USING
                MESSAGE = format('payment %s carries the receipt''s instrument: channel, source system, reference, check number, date and bank as receipt %s records them (v5.4.2-24)', NEW.payment_number, r.receipt_number),
                ERRCODE = 'check_violation';
        END IF;
        IF r.agency_id IS NOT NULL AND NEW.agency_id IS DISTINCT FROM r.agency_id THEN
            RAISE EXCEPTION USING
                MESSAGE = format('payment %s: receipt %s came from an agency, so its payment is the receipt''s agency''s (v5.4.2-24)', NEW.payment_number, r.receipt_number),
                ERRCODE = 'check_violation';
        END IF;
    END IF;

    IF NEW.agency_pledge_id IS NOT NULL THEN
        -- The pledge's lock: an event recording it in error waits, or is seen.
        PERFORM public.suspense_require_read_committed('a payment naming a pledge');
        PERFORM pg_catalog.pg_advisory_xact_lock(public.cash_source_lock_key('agency_pledge', NEW.agency_pledge_id));
        SELECT * INTO l FROM public.agency_pledges x WHERE x.id = NEW.agency_pledge_id AND x.tenant_id = NEW.tenant_id;
        IF NOT FOUND THEN
            RAISE EXCEPTION USING
                MESSAGE = format('payment %s: pledge %s is not visible in this tenant (v5.4.2-24)', NEW.payment_number, NEW.agency_pledge_id),
                ERRCODE = 'foreign_key_violation', CONSTRAINT = 'payments_agency_pledge_fkey';
        END IF;
        IF l.agency_id IS DISTINCT FROM NEW.agency_id OR l.customer_id IS DISTINCT FROM NEW.customer_id THEN
            RAISE EXCEPTION USING
                MESSAGE = format('payment %s: a pledge is paid by the pledge''s agency and customer (pledge %s) (v5.4.2-24)', NEW.payment_number, l.id),
                ERRCODE = 'check_violation';
        END IF;
        IF EXISTS (SELECT 1 FROM public.agency_pledge_events e WHERE e.agency_pledge_id = l.id AND e.event = 'recorded_in_error') THEN
            RAISE EXCEPTION USING
                MESSAGE = format('payment %s: pledge %s was recorded in error; no payment names it (v5.4.2-24)', NEW.payment_number, l.id),
                ERRCODE = 'check_violation';
        END IF;
    END IF;

    -- A refund goes back to whoever's money it is (Ryan, 2026-11-07).
    IF NEW.payment_method = 'refund' AND num_nonnulls(NEW.refunds_payment_id, NEW.refunds_customer_credit_id) = 1 THEN
        v_agency := public.cash_money_agency(NEW.refunds_payment_id, NEW.refunds_customer_credit_id);
        IF v_agency IS DISTINCT FROM NEW.agency_id THEN
            IF v_agency IS NOT NULL THEN
                RAISE EXCEPTION USING
                    MESSAGE = format('refund %s: the money came from agency %s, so a refund of it goes back to the agency (agency_id), never to the customer or another agency (Ryan, 2026-11-07; 10 TAC 6.312(f); v5.4.2-24)', NEW.payment_number, v_agency),
                    ERRCODE = 'check_violation';
            END IF;
            RAISE EXCEPTION USING
                MESSAGE = format('refund %s: the money is the customer''s own, so a refund of it goes to the customer and names no agency (v5.4.2-24)', NEW.payment_number),
                ERRCODE = 'check_violation';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;
COMMENT ON FUNCTION public.enforce_payment_suspense_pledge() IS
    'v5.4.2-24. BEFORE INSERT OR UPDATE on payments, for every role. Update: agency_id, agency_pledge_id, suspense_receipt_id and its reason and user are written once, at insert; a receipt''s payment is effective no later than the receipt''s received_on. Insert: a provider transaction is recorded once across receipts and payments (CI-055); a payment from a receipt is dated on or after received_on, effective no later, and carries the receipt''s channel, source system and instrument, and its agency where it names one (READ COMMITTED); a payment naming a pledge is of its agency and customer and the pledge was not recorded in error (under the pledge''s lock); a refund names the agency whose money it carries, or none for the customer''s own (cash_money_agency; Ryan, 2026-11-07). The receipt''s cap runs after the statement''s rows are in (enforce_payment_suspense_cap).';
CREATE TRIGGER enforce_payment_suspense_pledge BEFORE INSERT OR UPDATE ON public.payments
    FOR EACH ROW EXECUTE FUNCTION public.enforce_payment_suspense_pledge();
ALTER TABLE public.payments ENABLE ALWAYS TRIGGER enforce_payment_suspense_pledge;

-- AFTER INSERT: the receipt's cap, under its row lock, with every row of the
-- statement visible (lesson projection-checks-lag-in-one-statement).
CREATE OR REPLACE FUNCTION public.enforce_payment_suspense_cap() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
BEGIN
    PERFORM pg_catalog.pg_advisory_xact_lock(public.cash_source_lock_key('suspense_receipt', NEW.suspense_receipt_id));
    PERFORM public.check_suspense_receipt_cap(NEW.suspense_receipt_id);
    RETURN NULL;
END;
$$;
CREATE TRIGGER enforce_payment_suspense_cap AFTER INSERT ON public.payments
    FOR EACH ROW WHEN (NEW.suspense_receipt_id IS NOT NULL) EXECUTE FUNCTION public.enforce_payment_suspense_cap();
ALTER TABLE public.payments ENABLE ALWAYS TRIGGER enforce_payment_suspense_cap;

-- ----------------------------------------------------------------------------
-- 5. Receipts, candidates and dispositions: their guards
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.enforce_suspense_receipt() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
BEGIN
    IF NEW.received_on > public.suspense_today_latest() THEN
        RAISE EXCEPTION USING
            MESSAGE = format('suspense receipt %s is dated %s: money is dated no later than today (UTC+14) (v5.4.2-24)', NEW.receipt_number, NEW.received_on),
            ERRCODE = 'check_violation';
    END IF;
    PERFORM public.check_provider_transaction_once(NEW.tenant_id, NEW.source_system, NEW.provider_transaction_id, NEW.amount, NEW.id, true);
    RETURN NEW;
END;
$$;
CREATE TRIGGER enforce_suspense_receipt BEFORE INSERT ON public.suspense_receipts
    FOR EACH ROW EXECUTE FUNCTION public.enforce_suspense_receipt();
ALTER TABLE public.suspense_receipts ENABLE ALWAYS TRIGGER enforce_suspense_receipt;

CREATE OR REPLACE FUNCTION public.enforce_suspense_disposition() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    r       public.suspense_receipts%ROWTYPE;
    u       public.suspense_receipt_dispositions%ROWTYPE;
    v_undos numeric;
BEGIN
    PERFORM public.suspense_require_read_committed('a suspense disposition');
    PERFORM pg_catalog.pg_advisory_xact_lock(public.cash_source_lock_key('suspense_receipt', NEW.suspense_receipt_id));
    SELECT * INTO r FROM public.suspense_receipts x WHERE x.id = NEW.suspense_receipt_id;
    IF NEW.disposed_on < r.received_on THEN
        RAISE EXCEPTION USING
            MESSAGE = format('a disposition of receipt %s is dated on or after the receipt (%s), not %s (v5.4.2-24)', r.receipt_number, r.received_on, NEW.disposed_on),
            ERRCODE = 'check_violation';
    END IF;
    IF NEW.disposed_on > public.suspense_today_latest() THEN
        RAISE EXCEPTION USING
            MESSAGE = format('a disposition of receipt %s is dated %s: money is dated no later than today (UTC+14) (v5.4.2-24)', r.receipt_number, NEW.disposed_on),
            ERRCODE = 'check_violation';
    END IF;
    IF NEW.kind = 'undo' THEN
        SELECT * INTO u FROM public.suspense_receipt_dispositions x WHERE x.id = NEW.undoes_disposition_id;
        IF NOT FOUND OR u.suspense_receipt_id <> NEW.suspense_receipt_id OR u.kind = 'undo' THEN
            RAISE EXCEPTION USING
                MESSAGE = format('an undo names a disposition of the same receipt that is not itself an undo (receipt %s) (v5.4.2-24)', r.receipt_number),
                ERRCODE = 'check_violation';
        END IF;
        IF NEW.disposed_on < u.disposed_on THEN
            RAISE EXCEPTION USING
                MESSAGE = format('an undo is dated on or after what it undoes (%s), not %s (v5.4.2-24)', u.disposed_on, NEW.disposed_on),
                ERRCODE = 'check_violation';
        END IF;
        SELECT -coalesce(sum(x.amount), 0) INTO v_undos FROM public.suspense_receipt_dispositions x WHERE x.undoes_disposition_id = u.id;
        IF v_undos > u.amount THEN
            RAISE EXCEPTION USING
                MESSAGE = format('disposition %s: its undos would come to %s, more than its %s (v5.4.2-24)', u.id, v_undos, u.amount),
                ERRCODE = 'check_violation';
        END IF;
    END IF;
    PERFORM public.check_suspense_receipt_cap(NEW.suspense_receipt_id);
    RETURN NULL;
END;
$$;
COMMENT ON FUNCTION public.enforce_suspense_disposition() IS
    'v5.4.2-24. AFTER INSERT on suspense_receipt_dispositions, for every role, READ COMMITTED, under the receipt''s lock: dated on or after the receipt and no later than today (UTC+14); an undo names a non-undo disposition of the same receipt, is dated on or after it, and the undos of one never exceed it; then the receipt''s cap on every date.';
CREATE TRIGGER enforce_suspense_disposition AFTER INSERT ON public.suspense_receipt_dispositions
    FOR EACH ROW EXECUTE FUNCTION public.enforce_suspense_disposition();
ALTER TABLE public.suspense_receipt_dispositions ENABLE ALWAYS TRIGGER enforce_suspense_disposition;

-- ----------------------------------------------------------------------------
-- 6. Pledges and their events: their guards
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.enforce_agency_pledge() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_days integer;
BEGIN
    IF NEW.agreement_id IS NOT NULL OR NEW.pay_by IS NOT NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = 'a pledge''s agreement and pay_by are written by the database (the agreement in force on pledged_on); send neither (v5.4.2-24)',
            ERRCODE = 'check_violation';
    END IF;
    IF NEW.pledged_on > public.suspense_today_latest() THEN
        RAISE EXCEPTION USING
            MESSAGE = format('a pledge is dated no later than today (UTC+14), not %s (v5.4.2-24)', NEW.pledged_on),
            ERRCODE = 'check_violation';
    END IF;
    PERFORM public.suspense_require_read_committed('a pledge');
    PERFORM pg_catalog.pg_advisory_xact_lock(public.cash_source_lock_key('agency', NEW.agency_id));
    IF NOT EXISTS (SELECT 1 FROM public.assistance_agencies a WHERE a.id = NEW.agency_id AND a.tenant_id = NEW.tenant_id AND a.status = 'active') THEN
        IF EXISTS (SELECT 1 FROM public.assistance_agencies a WHERE a.id = NEW.agency_id AND a.tenant_id = NEW.tenant_id) THEN
            RAISE EXCEPTION USING
                MESSAGE = format('agency %s is retired: it takes no new pledge (v5.4.2-24)', NEW.agency_id),
                ERRCODE = 'check_violation';
        END IF;
        RAISE EXCEPTION USING
            MESSAGE = format('agency %s is not visible in this tenant (v5.4.2-24)', NEW.agency_id),
            ERRCODE = 'foreign_key_violation', CONSTRAINT = 'agency_pledges_agency_fkey';
    END IF;
    NEW.agreement_id := public.assistance_agreement_in_force(NEW.agency_id, NEW.pledged_on);
    IF NEW.agreement_id IS NOT NULL THEN
        SELECT g.pledge_payment_days INTO v_days FROM public.assistance_agency_agreements g WHERE g.id = NEW.agreement_id;
        NEW.pay_by := NEW.pledged_on + v_days;
    END IF;
    RETURN NEW;
END;
$$;
COMMENT ON FUNCTION public.enforce_agency_pledge() IS
    'v5.4.2-24 (design 4.1). BEFORE INSERT on agency_pledges, for every role: agreement_id and pay_by are the database''s (the agreement in force on pledged_on, and pledged_on plus its pledge_payment_days; both NULL with no agreement); pledged_on no later than today (UTC+14); the agency active, under its lock (a retirement waits).';
CREATE TRIGGER enforce_agency_pledge BEFORE INSERT ON public.agency_pledges
    FOR EACH ROW EXECUTE FUNCTION public.enforce_agency_pledge();
ALTER TABLE public.agency_pledges ENABLE ALWAYS TRIGGER enforce_agency_pledge;

-- What the payments naming a pledge received, at the coordinates.
CREATE OR REPLACE FUNCTION public.agency_pledge_paid_as_of(p_pledge_id uuid, p_on date, p_recorded_at timestamp with time zone) RETURNS numeric
    LANGUAGE sql STABLE
    SET search_path = public, pg_temp
    AS $$
    SELECT coalesce(sum(d.received), 0)::numeric(12,2)
      FROM public.payments p
      CROSS JOIN LATERAL public.payment_position_as_of(p.id, p_on, p_recorded_at) d
     WHERE p.agency_pledge_id = p_pledge_id AND p.payment_date <= p_on AND p.created_at <= p_recorded_at
$$;
REVOKE ALL ON FUNCTION public.agency_pledge_paid_as_of(uuid, date, timestamp with time zone) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.agency_pledge_paid_as_of(uuid, date, timestamp with time zone) TO tally_app, tally_core;

CREATE OR REPLACE FUNCTION public.enforce_agency_pledge_event() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    l      public.agency_pledges%ROWTYPE;
    v_paid numeric;
BEGIN
    PERFORM public.suspense_require_read_committed('a pledge event');
    PERFORM pg_catalog.pg_advisory_xact_lock(public.cash_source_lock_key('agency_pledge', NEW.agency_pledge_id));
    SELECT * INTO l FROM public.agency_pledges x WHERE x.id = NEW.agency_pledge_id;
    IF NEW.event_on IS NOT NULL AND (NEW.event_on < l.pledged_on OR NEW.event_on > public.suspense_today_latest()) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('pledge %s: an event is dated on or after the pledge (%s) and no later than today (UTC+14), not %s (v5.4.2-24)', l.id, l.pledged_on, NEW.event_on),
            ERRCODE = 'check_violation';
    END IF;
    IF NEW.event = 'recorded_in_error' THEN
        IF EXISTS (SELECT 1 FROM public.payments p WHERE p.agency_pledge_id = l.id AND p.status <> 'voided') THEN
            RAISE EXCEPTION USING
                MESSAGE = format('pledge %s cannot be recorded in error: a payment names it (v5.4.2-24)', l.id),
                ERRCODE = 'check_violation';
        END IF;
        RETURN NEW;
    END IF;
    v_paid := public.agency_pledge_paid_as_of(l.id, DATE '9999-12-31', pg_catalog.clock_timestamp());
    IF v_paid >= l.amount THEN
        RAISE EXCEPTION USING
            MESSAGE = format('pledge %s is paid in full (%s of %s): it is neither withdrawn nor lapsed (v5.4.2-24)', l.id, v_paid, l.amount),
            ERRCODE = 'check_violation';
    END IF;
    IF NEW.event = 'lapsed' THEN
        IF l.pay_by IS NULL THEN
            RAISE EXCEPTION USING
                MESSAGE = format('pledge %s has no agreement and so no pay_by: it lapses only by a date; record its agreement, or withdraw it (v5.4.2-24)', l.id),
                ERRCODE = 'check_violation';
        END IF;
        IF NEW.event_on <= l.pay_by THEN
            RAISE EXCEPTION USING
                MESSAGE = format('pledge %s: a lapse is dated after pay_by (%s), not %s (v5.4.2-24)', l.id, l.pay_by, NEW.event_on),
                ERRCODE = 'check_violation';
        END IF;
        IF l.pay_by >= public.suspense_today_earliest() THEN
            RAISE EXCEPTION USING
                MESSAGE = format('pledge %s: its pay_by (%s) has not passed everywhere yet; a lapse waits until it has (v5.4.2-24)', l.id, l.pay_by),
                ERRCODE = 'check_violation';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;
COMMENT ON FUNCTION public.enforce_agency_pledge_event() IS
    'v5.4.2-24 (design 4.2). BEFORE INSERT on agency_pledge_events, for every role, READ COMMITTED, under the pledge''s lock: dated on or after the pledge and no later than today (UTC+14); recorded_in_error only while no payment (not voided) names it; withdrawn and lapsed only while not paid in full; a lapse needs a pay_by, is dated after it, and is recorded only once pay_by has passed everywhere (UTC-12).';
CREATE TRIGGER enforce_agency_pledge_event BEFORE INSERT ON public.agency_pledge_events
    FOR EACH ROW EXECUTE FUNCTION public.enforce_agency_pledge_event();
ALTER TABLE public.agency_pledge_events ENABLE ALWAYS TRIGGER enforce_agency_pledge_event;

-- ----------------------------------------------------------------------------
-- 7. Settings (design 2.4)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.suspense_days_setting_valid(p_value jsonb) RETURNS boolean
    LANGUAGE sql IMMUTABLE
    SET search_path = public, pg_temp
    AS $$
    SELECT p_value IS NULL OR p_value = 'null'::jsonb
        OR (jsonb_typeof(p_value) = 'number' AND (p_value #>> '{}') ~ '^[1-9][0-9]{0,4}$')
$$;
REVOKE ALL ON FUNCTION public.suspense_days_setting_valid(jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.suspense_days_setting_valid(jsonb) TO tally_app, tally_core;
ALTER TABLE public.tenants ADD CONSTRAINT tenants_suspense_days_check
    CHECK (public.suspense_days_setting_valid(settings -> 'suspense_service_level_days')
           AND public.suspense_days_setting_valid(settings -> 'suspense_retention_days'));

CREATE OR REPLACE FUNCTION public.suspense_setting_days_as_of(p_tenant_id uuid, p_key text, p_at timestamp with time zone) RETURNS integer
    LANGUAGE plpgsql STABLE
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_val jsonb;
BEGIN
    IF p_tenant_id IS NULL OR p_at IS NULL OR NOT pg_catalog.isfinite(p_at) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('%s_as_of: tenant and a finite instant are both given; never default to now (v5.4.2-24)', p_key),
            ERRCODE = 'null_value_not_allowed';
    END IF;
    SELECT h.new_value INTO v_val
      FROM public.tenant_configuration_history h
     WHERE h.tenant_id = p_tenant_id AND h.config_key = 'settings.' || p_key AND h.effective_from <= p_at
     ORDER BY h.effective_from DESC, h.seq DESC
     LIMIT 1;
    IF v_val IS NULL OR jsonb_typeof(v_val) <> 'number' THEN
        RETURN NULL;
    END IF;
    RETURN (v_val #>> '{}')::integer;
END;
$$;
CREATE OR REPLACE FUNCTION public.suspense_service_level_days_as_of(p_tenant_id uuid, p_at timestamp with time zone) RETURNS integer
    LANGUAGE sql STABLE
    SET search_path = public, pg_temp
    AS $$ SELECT public.suspense_setting_days_as_of(p_tenant_id, 'suspense_service_level_days', p_at) $$;
CREATE OR REPLACE FUNCTION public.suspense_retention_days_as_of(p_tenant_id uuid, p_at timestamp with time zone) RETURNS integer
    LANGUAGE sql STABLE
    SET search_path = public, pg_temp
    AS $$ SELECT public.suspense_setting_days_as_of(p_tenant_id, 'suspense_retention_days', p_at) $$;
COMMENT ON FUNCTION public.suspense_service_level_days_as_of(uuid, timestamp with time zone) IS
    'v5.4.2-24 (CI-056). The tenant''s suspense service level in days, as recorded at p_at (tenant_configuration_history, settings.suspense_service_level_days); NULL when unset (no assumed default, K-07). Both coordinates required.';
COMMENT ON FUNCTION public.suspense_retention_days_as_of(uuid, timestamp with time zone) IS
    'v5.4.2-24 (CI-053). The tenant''s suspense retention period in days, as recorded at p_at (settings.suspense_retention_days): after it a receipt is to be returned or reported. NULL when unset. Both coordinates required.';
REVOKE ALL ON FUNCTION public.suspense_setting_days_as_of(uuid, text, timestamp with time zone),
    public.suspense_service_level_days_as_of(uuid, timestamp with time zone), public.suspense_retention_days_as_of(uuid, timestamp with time zone) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.suspense_setting_days_as_of(uuid, text, timestamp with time zone),
    public.suspense_service_level_days_as_of(uuid, timestamp with time zone), public.suspense_retention_days_as_of(uuid, timestamp with time zone) TO tally_app, tally_core;

-- ----------------------------------------------------------------------------
-- 8. The readers (design 2.4, 4.2)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.suspense_receipt_position_as_of(p_receipt_id uuid, p_on date, p_recorded_at timestamp with time zone)
    RETURNS TABLE (amount numeric, to_payments numeric, disposed numeric, held numeric, received_on date, age_days integer)
    LANGUAGE plpgsql STABLE
    SET search_path = public, pg_temp
    AS $$
BEGIN
    PERFORM public.cash_coordinates_required('suspense_receipt_position_as_of', p_on, p_recorded_at);
    RETURN QUERY
    SELECT r.amount, x.pays::numeric(12,2), x.disp::numeric(12,2), (r.amount - x.pays - x.disp)::numeric(12,2), r.received_on, (p_on - r.received_on)::integer
      FROM public.suspense_receipts r
      CROSS JOIN LATERAL (SELECT
            coalesce((SELECT sum(p.amount) FROM public.payments p
                       WHERE p.suspense_receipt_id = r.id AND p.payment_date <= p_on AND p.created_at <= p_recorded_at
                         AND NOT (p.status IN ('voided', 'reversed') AND p.status_recorded_at <= p_recorded_at)), 0) AS pays,
            coalesce((SELECT sum(d.amount) FROM public.suspense_receipt_dispositions d
                       WHERE d.suspense_receipt_id = r.id AND d.disposed_on <= p_on AND d.created_at <= p_recorded_at), 0) AS disp) x
     WHERE r.id = p_receipt_id AND r.received_on <= p_on AND r.created_at <= p_recorded_at;
END;
$$;
COMMENT ON FUNCTION public.suspense_receipt_position_as_of(uuid, date, timestamp with time zone) IS
    'v5.4.2-24 (CI-053). A receipt at a money date and a recorded instant: its amount; to_payments (the payments naming it, dated by then, not voided or reversed as recorded then); disposed (its dispositions dated by then, undos netted); held = amount less both; received_on; age_days from received_on. No row before the receipt exists at the coordinates. NULL or infinite coordinates raise.';

CREATE OR REPLACE FUNCTION public.suspense_held_as_of(p_tenant_id uuid, p_on date, p_recorded_at timestamp with time zone) RETURNS numeric
    LANGUAGE plpgsql STABLE
    SET search_path = public, pg_temp
    AS $$
BEGIN
    PERFORM public.cash_coordinates_required('suspense_held_as_of', p_on, p_recorded_at);
    RETURN (SELECT coalesce(sum(x.held), 0) FROM public.suspense_receipts r
             CROSS JOIN LATERAL public.suspense_receipt_position_as_of(r.id, p_on, p_recorded_at) x
             WHERE r.tenant_id = p_tenant_id);
END;
$$;
COMMENT ON FUNCTION public.suspense_held_as_of(uuid, date, timestamp with time zone) IS
    'v5.4.2-24 (known limit L4). What a tenant holds in suspense at the coordinates: the figure that reconciles the subledger to the bank until the close''s snapshot carries it.';

CREATE OR REPLACE FUNCTION public.suspense_receipts_aged_as_of(p_tenant_id uuid, p_on date, p_recorded_at timestamp with time zone)
    RETURNS TABLE (receipt_id uuid, held numeric, received_on date, age_days integer, service_level_days integer,
                   past_retention boolean, candidate_customer_ids uuid[])
    LANGUAGE plpgsql STABLE
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_level     integer;
    v_retention integer;
BEGIN
    PERFORM public.cash_coordinates_required('suspense_receipts_aged_as_of', p_on, p_recorded_at);
    v_level := public.suspense_service_level_days_as_of(p_tenant_id, p_recorded_at);
    IF v_level IS NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('suspense_receipts_aged_as_of: tenant %s''s suspense service level is not set at %s: which receipts are aged cannot be known (fail loud; -26 reads it as unevaluable) (CI-056, v5.4.2-24)', p_tenant_id, p_recorded_at),
            ERRCODE = 'object_not_in_prerequisite_state';
    END IF;
    v_retention := public.suspense_retention_days_as_of(p_tenant_id, p_recorded_at);
    RETURN QUERY
    SELECT r.id, x.held, r.received_on, x.age_days, v_level,
           CASE WHEN v_retention IS NULL THEN NULL ELSE x.age_days > v_retention END,
           ARRAY(SELECT DISTINCT c.customer_id FROM public.suspense_receipt_candidates c
                  WHERE c.suspense_receipt_id = r.id AND c.created_at <= p_recorded_at ORDER BY c.customer_id)
      FROM public.suspense_receipts r
      CROSS JOIN LATERAL public.suspense_receipt_position_as_of(r.id, p_on, p_recorded_at) x
     WHERE r.tenant_id = p_tenant_id AND x.held > 0 AND x.age_days > v_level
     ORDER BY r.received_on, r.id;
END;
$$;
COMMENT ON FUNCTION public.suspense_receipts_aged_as_of(uuid, date, timestamp with time zone) IS
    'v5.4.2-24 (CI-056; -26 aged_suspense). Every receipt of the tenant still holding money past the service level at the coordinates (age in days from received_on above it), oldest first, with whether it is past retention (NULL when retention is unset) and its candidate customers (the accounts the bar protects). Raises while the service level is unset (fail loud).';

CREATE OR REPLACE FUNCTION public.agency_pledge_position_as_of(p_pledge_id uuid, p_on date, p_recorded_at timestamp with time zone)
    RETURNS TABLE (amount numeric, paid numeric, outstanding numeric, pay_by date, state text)
    LANGUAGE plpgsql STABLE
    SET search_path = public, pg_temp
    AS $$
BEGIN
    PERFORM public.cash_coordinates_required('agency_pledge_position_as_of', p_on, p_recorded_at);
    RETURN QUERY
    SELECT l.amount, x.paid,
           (CASE WHEN e.event = 'recorded_in_error' THEN 0 ELSE greatest(l.amount - x.paid, 0) END)::numeric(12,2),
           l.pay_by,
           CASE WHEN e.event = 'recorded_in_error' THEN 'void'
                WHEN x.paid >= l.amount THEN 'paid'
                WHEN e.event IS NOT NULL AND e.event_on <= p_on THEN e.event
                WHEN l.pay_by IS NULL THEN 'no_agreement'
                WHEN p_on > l.pay_by THEN 'overdue'
                ELSE 'open' END
      FROM public.agency_pledges l
      CROSS JOIN LATERAL (SELECT public.agency_pledge_paid_as_of(l.id, p_on, p_recorded_at) AS paid) x
      LEFT JOIN public.agency_pledge_events e ON e.agency_pledge_id = l.id AND e.created_at <= p_recorded_at
     WHERE l.id = p_pledge_id AND l.pledged_on <= p_on AND l.created_at <= p_recorded_at;
END;
$$;
COMMENT ON FUNCTION public.agency_pledge_position_as_of(uuid, date, timestamp with time zone) IS
    'v5.4.2-24 (CI-056; -26 agency_pledge). A pledge at a money date and a recorded instant: amount; paid (what the payments naming it received, payment_position_as_of); outstanding; pay_by; state: void (recorded in error), paid (paid in full), withdrawn or lapsed (from the event''s date), no_agreement (no pay_by: unevaluable for -26), overdue (after pay_by), open. No row before the pledge exists at the coordinates. NULL or infinite coordinates raise.';

CREATE OR REPLACE FUNCTION public.agency_pledges_open_as_of(p_tenant_id uuid, p_on date, p_recorded_at timestamp with time zone)
    RETURNS TABLE (pledge_id uuid, customer_id uuid, agency_id uuid, amount numeric, paid numeric, outstanding numeric, pay_by date, state text)
    LANGUAGE plpgsql STABLE
    SET search_path = public, pg_temp
    AS $$
BEGIN
    PERFORM public.cash_coordinates_required('agency_pledges_open_as_of', p_on, p_recorded_at);
    RETURN QUERY
    SELECT l.id, l.customer_id, l.agency_id, x.amount, x.paid, x.outstanding, x.pay_by, x.state
      FROM public.agency_pledges l
      CROSS JOIN LATERAL public.agency_pledge_position_as_of(l.id, p_on, p_recorded_at) x
     WHERE l.tenant_id = p_tenant_id AND x.state IN ('open', 'overdue', 'no_agreement')
     ORDER BY l.pay_by NULLS FIRST, l.id;
END;
$$;
COMMENT ON FUNCTION public.agency_pledges_open_as_of(uuid, date, timestamp with time zone) IS
    'v5.4.2-24 (CI-056: fail loud). Every pledge of the tenant not ended at the coordinates (open, overdue, or with no agreement), soonest pay_by first and those with none before all.';

REVOKE ALL ON FUNCTION public.suspense_receipt_position_as_of(uuid, date, timestamp with time zone),
    public.suspense_held_as_of(uuid, date, timestamp with time zone),
    public.suspense_receipts_aged_as_of(uuid, date, timestamp with time zone),
    public.agency_pledge_position_as_of(uuid, date, timestamp with time zone),
    public.agency_pledges_open_as_of(uuid, date, timestamp with time zone) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.suspense_receipt_position_as_of(uuid, date, timestamp with time zone),
    public.suspense_held_as_of(uuid, date, timestamp with time zone),
    public.suspense_receipts_aged_as_of(uuid, date, timestamp with time zone),
    public.agency_pledge_position_as_of(uuid, date, timestamp with time zone),
    public.agency_pledges_open_as_of(uuid, date, timestamp with time zone) TO tally_app, tally_core;

-- ----------------------------------------------------------------------------
-- 9. The agency_pledge program type retires (design 4.5; -25's precedent)
-- ----------------------------------------------------------------------------
UPDATE public.program_types
   SET description = 'Retired by v5.4.2-24: a pledge is an agency_pledges row (typed amount and dates; several at once; ended by agency_pledge_events). Not protective; no new enrollment. Kept for history.'
 WHERE code = 'agency_pledge';
CREATE OR REPLACE FUNCTION public.enforce_enrollment_not_agency_pledge() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
BEGIN
    IF NEW.program_type = 'agency_pledge' THEN
        RAISE EXCEPTION USING
            MESSAGE = 'program enrollment: agency_pledge is retired — a pledge is an agency_pledges row (v5.4.2-24)',
            ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$;
COMMENT ON FUNCTION public.enforce_enrollment_not_agency_pledge() IS
    'v5.4.2-24 (design 4.5). BEFORE INSERT OR UPDATE on customer_program_enrollments: no enrollment is of type agency_pledge.';
REVOKE ALL ON FUNCTION public.enforce_enrollment_not_agency_pledge() FROM PUBLIC, tally_app, tally_core;
CREATE TRIGGER enforce_enrollment_not_agency_pledge BEFORE INSERT OR UPDATE ON public.customer_program_enrollments
    FOR EACH ROW EXECUTE FUNCTION public.enforce_enrollment_not_agency_pledge();
ALTER TABLE public.customer_program_enrollments ENABLE ALWAYS TRIGGER enforce_enrollment_not_agency_pledge;

-- ----------------------------------------------------------------------------
-- 10. Shared plumbing on the new tables: stamps, add-only, retention, freeze,
--     row-level security
-- ----------------------------------------------------------------------------
DO $$
DECLARE
    t text;
BEGIN
    FOREACH t IN ARRAY ARRAY['assistance_agencies', 'assistance_agency_agreements', 'suspense_receipts', 'suspense_receipt_candidates',
                             'suspense_receipt_dispositions', 'agency_pledges', 'agency_pledge_events'] LOOP
        EXECUTE format('CREATE TRIGGER a_stamp_created_at BEFORE INSERT ON public.%I FOR EACH ROW EXECUTE FUNCTION public.stamp_log_created_at()', t);
        EXECUTE format('ALTER TABLE public.%I ENABLE ALWAYS TRIGGER a_stamp_created_at', t);
        EXECUTE format('CREATE TRIGGER no_hard_delete BEFORE DELETE ON public.%I FOR EACH ROW EXECUTE FUNCTION public.enforce_no_hard_delete()', t);
        EXECUTE format('ALTER TABLE public.%I ENABLE ALWAYS TRIGGER no_hard_delete', t);
        EXECUTE format('CREATE TRIGGER no_truncate BEFORE TRUNCATE ON public.%I FOR EACH STATEMENT EXECUTE FUNCTION public.enforce_no_hard_delete()', t);
        EXECUTE format('ALTER TABLE public.%I ENABLE ALWAYS TRIGGER no_truncate', t);
        EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);
        EXECUTE format('ALTER TABLE public.%I FORCE ROW LEVEL SECURITY', t);
        EXECUTE format('CREATE POLICY tenant_isolation ON public.%I USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())))', t);
        IF t NOT IN ('assistance_agencies', 'assistance_agency_agreements') THEN
            EXECUTE format('CREATE TRIGGER append_only BEFORE DELETE OR UPDATE ON public.%I FOR EACH ROW EXECUTE FUNCTION public.enforce_append_only()', t);
            EXECUTE format('ALTER TABLE public.%I ENABLE ALWAYS TRIGGER append_only', t);
        END IF;
    END LOOP;
END $$;
CREATE TRIGGER a_enforce_accounting_freeze BEFORE INSERT ON public.suspense_receipts
    FOR EACH ROW EXECUTE FUNCTION public.enforce_accounting_freeze('received_on');
ALTER TABLE public.suspense_receipts ENABLE ALWAYS TRIGGER a_enforce_accounting_freeze;
CREATE TRIGGER a_enforce_accounting_freeze BEFORE INSERT ON public.suspense_receipt_dispositions
    FOR EACH ROW EXECUTE FUNCTION public.enforce_accounting_freeze('disposed_on');
ALTER TABLE public.suspense_receipt_dispositions ENABLE ALWAYS TRIGGER a_enforce_accounting_freeze;

-- ----------------------------------------------------------------------------
-- 11. Grants
-- ----------------------------------------------------------------------------
REVOKE ALL ON public.assistance_agencies, public.assistance_agency_agreements, public.suspense_receipts, public.suspense_receipt_candidates,
    public.suspense_receipt_dispositions, public.agency_pledges, public.agency_pledge_events FROM PUBLIC, tally_app, tally_core;
GRANT SELECT, INSERT ON public.assistance_agencies, public.assistance_agency_agreements, public.suspense_receipts, public.suspense_receipt_candidates,
    public.suspense_receipt_dispositions, public.agency_pledges, public.agency_pledge_events TO tally_app;
GRANT UPDATE (status, retired_by, retired_reason) ON public.assistance_agencies TO tally_app;
GRANT UPDATE (withdrawn_by, withdrawn_reason) ON public.assistance_agency_agreements TO tally_app;
GRANT SELECT ON public.assistance_agencies, public.assistance_agency_agreements, public.suspense_receipts, public.suspense_receipt_candidates,
    public.suspense_receipt_dispositions, public.agency_pledges, public.agency_pledge_events TO tally_core;
REVOKE ALL ON FUNCTION public.enforce_assistance_agency_retire(), public.enforce_assistance_agreement(), public.enforce_payment_suspense_pledge(),
    public.enforce_payment_suspense_cap(), public.enforce_suspense_receipt(), public.enforce_suspense_disposition(),
    public.enforce_agency_pledge(), public.enforce_agency_pledge_event() FROM PUBLIC, tally_app, tally_core;

-- ----------------------------------------------------------------------------
-- 12. The invariants
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.assert_suspense_pledge_guard_invariants() RETURNS void
    LANGUAGE plpgsql STABLE
    SET search_path = public, pg_temp
    AS $fn$
DECLARE
    v_bad text;
    t     text;
    c_tables CONSTANT text[] := ARRAY['assistance_agencies', 'assistance_agency_agreements', 'suspense_receipts', 'suspense_receipt_candidates',
                                      'suspense_receipt_dispositions', 'agency_pledges', 'agency_pledge_events'];
    -- PostgreSQL 16's rendering by pg_get_triggerdef.
    c_triggers CONSTANT text[] := ARRAY[
        'CREATE TRIGGER enforce_assistance_agency_retire BEFORE UPDATE ON public.assistance_agencies FOR EACH ROW EXECUTE FUNCTION enforce_assistance_agency_retire()',
        'CREATE TRIGGER enforce_assistance_agreement BEFORE INSERT OR UPDATE ON public.assistance_agency_agreements FOR EACH ROW EXECUTE FUNCTION enforce_assistance_agreement()',
        'CREATE TRIGGER enforce_payment_suspense_pledge BEFORE INSERT OR UPDATE ON public.payments FOR EACH ROW EXECUTE FUNCTION enforce_payment_suspense_pledge()',
        'CREATE TRIGGER enforce_payment_suspense_cap AFTER INSERT ON public.payments FOR EACH ROW WHEN ((new.suspense_receipt_id IS NOT NULL)) EXECUTE FUNCTION enforce_payment_suspense_cap()',
        'CREATE TRIGGER enforce_suspense_receipt BEFORE INSERT ON public.suspense_receipts FOR EACH ROW EXECUTE FUNCTION enforce_suspense_receipt()',
        'CREATE TRIGGER enforce_suspense_disposition AFTER INSERT ON public.suspense_receipt_dispositions FOR EACH ROW EXECUTE FUNCTION enforce_suspense_disposition()',
        'CREATE TRIGGER enforce_agency_pledge BEFORE INSERT ON public.agency_pledges FOR EACH ROW EXECUTE FUNCTION enforce_agency_pledge()',
        'CREATE TRIGGER enforce_agency_pledge_event BEFORE INSERT ON public.agency_pledge_events FOR EACH ROW EXECUTE FUNCTION enforce_agency_pledge_event()',
        'CREATE TRIGGER enforce_enrollment_not_agency_pledge BEFORE INSERT OR UPDATE ON public.customer_program_enrollments FOR EACH ROW EXECUTE FUNCTION enforce_enrollment_not_agency_pledge()',
        'CREATE TRIGGER a_enforce_accounting_freeze BEFORE INSERT ON public.suspense_receipts FOR EACH ROW EXECUTE FUNCTION enforce_accounting_freeze(''received_on'')',
        'CREATE TRIGGER a_enforce_accounting_freeze BEFORE INSERT ON public.suspense_receipt_dispositions FOR EACH ROW EXECUTE FUNCTION enforce_accounting_freeze(''disposed_on'')'];
BEGIN
    -- The named guards, exactly, and ENABLE ALWAYS.
    SELECT string_agg(d, E'\n  ' ORDER BY d) INTO v_bad
      FROM unnest(c_triggers) d
     WHERE NOT EXISTS (SELECT 1 FROM pg_catalog.pg_trigger g
                        WHERE NOT g.tgisinternal AND g.tgenabled = 'A' AND pg_catalog.pg_get_triggerdef(g.oid) = d);
    IF v_bad IS NOT NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format(E'a v5.4.2-24 guard is missing, changed, or not ENABLE ALWAYS:\n  %s', v_bad),
            ERRCODE = 'invalid_grant_operation';
    END IF;
    FOREACH t IN ARRAY c_tables LOOP
        -- The shared plumbing on each new table.
        SELECT string_agg(d, E'\n  ' ORDER BY d) INTO v_bad
          FROM unnest(ARRAY[
                format('CREATE TRIGGER a_stamp_created_at BEFORE INSERT ON public.%s FOR EACH ROW EXECUTE FUNCTION stamp_log_created_at()', t),
                format('CREATE TRIGGER no_hard_delete BEFORE DELETE ON public.%s FOR EACH ROW EXECUTE FUNCTION enforce_no_hard_delete()', t),
                format('CREATE TRIGGER no_truncate BEFORE TRUNCATE ON public.%s FOR EACH STATEMENT EXECUTE FUNCTION enforce_no_hard_delete()', t)]
                || CASE WHEN t IN ('assistance_agencies', 'assistance_agency_agreements') THEN ARRAY[]::text[]
                        ELSE ARRAY[format('CREATE TRIGGER append_only BEFORE DELETE OR UPDATE ON public.%s FOR EACH ROW EXECUTE FUNCTION enforce_append_only()', t)] END) d
         WHERE NOT EXISTS (SELECT 1 FROM pg_catalog.pg_trigger g
                            WHERE NOT g.tgisinternal AND g.tgenabled = 'A' AND pg_catalog.pg_get_triggerdef(g.oid) = d);
        IF v_bad IS NOT NULL THEN
            RAISE EXCEPTION USING
                MESSAGE = format(E'%s: a v5.4.2-24 stamp, retention or add-only trigger is missing, changed, or not ENABLE ALWAYS:\n  %s', t, v_bad),
                ERRCODE = 'invalid_grant_operation';
        END IF;
        -- Its tenant policy, alone, and forced row security.
        IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_policies p
                        WHERE p.schemaname = 'public' AND p.tablename = t AND p.policyname = 'tenant_isolation'
                          AND p.cmd = 'ALL' AND p.permissive = 'PERMISSIVE' AND p.roles = '{public}'
                          AND p.qual = '(is_platform_admin() OR (tenant_id = get_user_tenant_id()))' AND p.with_check IS NULL)
           OR (SELECT count(*) FROM pg_catalog.pg_policies p WHERE p.schemaname = 'public' AND p.tablename = t) <> 1
           OR NOT (SELECT c.relrowsecurity AND c.relforcerowsecurity FROM pg_catalog.pg_class c WHERE c.oid = ('public.' || t)::regclass) THEN
            RAISE EXCEPTION USING
                MESSAGE = format('%s has lost its tenant_isolation policy or forced row security, or has another policy beside it (v5.4.2-24)', t),
                ERRCODE = 'invalid_grant_operation';
        END IF;
        -- tally_app: SELECT and INSERT, and on the two setup tables UPDATE of
        -- their stamp columns only; tally_core: SELECT; PUBLIC nothing.
        IF has_table_privilege('tally_app', 'public.' || t, 'UPDATE') OR has_table_privilege('tally_app', 'public.' || t, 'DELETE')
           OR has_table_privilege('tally_app', 'public.' || t, 'TRUNCATE') OR has_table_privilege('tally_app', 'public.' || t, 'REFERENCES')
           OR has_table_privilege('tally_app', 'public.' || t, 'TRIGGER')
           OR has_any_column_privilege('tally_app', 'public.' || t, 'REFERENCES')
           OR NOT has_table_privilege('tally_app', 'public.' || t, 'SELECT') OR NOT has_table_privilege('tally_app', 'public.' || t, 'INSERT')
           OR EXISTS (SELECT 1 FROM pg_catalog.pg_attribute a
                       WHERE a.attrelid = ('public.' || t)::regclass AND a.attnum > 0 AND NOT a.attisdropped
                         AND has_column_privilege('tally_app', a.attrelid, a.attnum, 'UPDATE')
                         AND NOT ((t = 'assistance_agencies' AND a.attname IN ('status', 'retired_by', 'retired_reason'))
                               OR (t = 'assistance_agency_agreements' AND a.attname IN ('withdrawn_by', 'withdrawn_reason'))))
           OR has_table_privilege('tally_core', 'public.' || t, 'INSERT') OR has_table_privilege('tally_core', 'public.' || t, 'UPDATE')
           OR has_table_privilege('tally_core', 'public.' || t, 'DELETE') OR has_table_privilege('tally_core', 'public.' || t, 'TRUNCATE')
           OR has_table_privilege('tally_core', 'public.' || t, 'REFERENCES') OR has_table_privilege('tally_core', 'public.' || t, 'TRIGGER')
           OR has_any_column_privilege('tally_core', 'public.' || t, 'INSERT') OR has_any_column_privilege('tally_core', 'public.' || t, 'UPDATE')
           OR NOT has_table_privilege('tally_core', 'public.' || t, 'SELECT')
           OR has_any_column_privilege('public', 'public.' || t, 'SELECT') OR has_any_column_privilege('public', 'public.' || t, 'INSERT')
           OR has_any_column_privilege('public', 'public.' || t, 'UPDATE') THEN
            RAISE EXCEPTION USING
                MESSAGE = format('%s: tally_app may only SELECT and INSERT it (and UPDATE its retirement or withdrawal stamps), tally_core only read it, PUBLIC nothing (v5.4.2-24)', t),
                ERRCODE = 'invalid_grant_operation';
        END IF;
    END LOOP;
    -- R-12: every key from a new table, or from payments to one, to a table
    -- that carries tenant_id includes tenant_id on both sides, matched.
    SELECT string_agg(k.conname, ', ' ORDER BY k.conname) INTO v_bad
      FROM pg_catalog.pg_constraint k
     WHERE k.contype = 'f'
       AND (k.conrelid::regclass::text = ANY (c_tables)
            OR (k.conrelid = 'public.payments'::regclass AND k.confrelid::regclass::text = ANY (c_tables)))
       AND EXISTS (SELECT 1 FROM pg_catalog.pg_attribute a WHERE a.attrelid = k.confrelid AND a.attname = 'tenant_id' AND NOT a.attisdropped)
       AND k.confrelid <> 'public.tenants'::regclass
       AND NOT EXISTS (
             SELECT 1 FROM unnest(k.conkey, k.confkey) AS m(src, dst)
               JOIN pg_catalog.pg_attribute sa ON sa.attrelid = k.conrelid AND sa.attnum = m.src
               JOIN pg_catalog.pg_attribute da ON da.attrelid = k.confrelid AND da.attnum = m.dst
              WHERE sa.attname = 'tenant_id' AND da.attname = 'tenant_id');
    IF v_bad IS NOT NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('a v5.4.2-24 key between tenant tables does not carry tenant_id on both sides (R-12: a single-column key skips row-level security): %s', v_bad),
            ERRCODE = 'invalid_grant_operation';
    END IF;
    -- The cap and the provider check are tally_app's to run, as the guards'.
    IF has_function_privilege('public', 'public.check_suspense_receipt_cap(uuid)', 'EXECUTE')
       OR has_function_privilege('tally_core', 'public.check_suspense_receipt_cap(uuid)', 'EXECUTE')
       OR has_function_privilege('public', 'public.check_provider_transaction_once(uuid, text, text, numeric, uuid, boolean)', 'EXECUTE')
       OR has_function_privilege('tally_core', 'public.check_provider_transaction_once(uuid, text, text, numeric, uuid, boolean)', 'EXECUTE') THEN
        RAISE EXCEPTION USING
            MESSAGE = 'check_suspense_receipt_cap or check_provider_transaction_once is executable beyond tally_app (v5.4.2-24)',
            ERRCODE = 'invalid_grant_operation';
    END IF;
END;
$fn$;
COMMENT ON FUNCTION public.assert_suspense_pledge_guard_invariants() IS
    'v5.4.2-24. Raises unless every v5.4.2-24 guard exists exactly as defined (PostgreSQL 16''s rendering) and ENABLE ALWAYS; each new table keeps its stamp, retention and (but for the two setup tables) add-only triggers, its tenant policy alone with forced row security, and its grants (tally_app SELECT and INSERT, plus UPDATE of the retirement and withdrawal stamps on the setup tables; tally_core SELECT; PUBLIC nothing); every key from a new table, or from payments to one, to a tenant table carries tenant_id on both sides (R-12); the cap and the provider check are not the core''s or PUBLIC''s. Run in the patch tail and in CI.';
REVOKE ALL ON FUNCTION public.assert_suspense_pledge_guard_invariants() FROM PUBLIC, tally_app, tally_core;

DO $$ BEGIN
    PERFORM public.assert_suspense_pledge_guard_invariants();
    PERFORM public.assert_shortfall_guard_invariants();
    PERFORM public.assert_cash_guard_invariants();
    PERFORM public.assert_periods_guard_invariants();
    PERFORM public.assert_seal_role_invariants();
    PERFORM public.assert_core_role_invariants();
    PERFORM public.assert_tenant_isolation_invariants();
    PERFORM public.assert_rule_table_invariants();
    PERFORM public.assert_no_hard_delete_invariants();
    PERFORM public.assert_wave1_guard_invariants();
END $$;

-- ============================================================================
-- END PATCH v5.4.2-24
-- ============================================================================

COMMIT;
\endif
