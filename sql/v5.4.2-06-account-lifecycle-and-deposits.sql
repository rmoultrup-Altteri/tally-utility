-- ============================================================================
-- PATCH v5.4.2-06 — A-21: account lifecycle state-events, date-effective
--                    account attributes, and the deposit / interest ledger
--                    (schema-parity-plan Phase 4 Wave 2, Appendix A-21;
--                    CI-121 / CI-125 / CI-129 / CI-130 / CI-131; CI-077,
--                    CI-126 touched)
-- ============================================================================
-- Authority:   canonical-invariants.md Appendix A-21 (the three substrates it
--              names: an account state-transition event log; date-effective
--              account attributes; a deposit ledger with a date-effective
--              interest-rate bracket and an accrual sub-ledger); CI-121,
--              CI-125, CI-129, CI-130, CI-131 (the Texas deposit sub-family,
--              16 TAC §7.45); Kyle 2026-06-12 (an effective-dated
--              deposit_interest_rates table — "same pattern as rates";
--              de-review-answers action #25); Kyle 2026-07-10 Family 16
--              ("statute-sourced mechanics read clean"; sequencing flag: the
--              day-30-vs-day-31 boundary first); Kyle research Q-6 (family
--              violence = deposit waiver only, §7.45(5)(C)); decision tables
--              deposit-eligibility-and-waiver (#53), deposit-refund-and-
--              interest (#54), deposit-alternatives-and-triggers (#55) and
--              their open questions (no deposits table; six disagreeing
--              representations; basis unrecorded; instrument unrecorded;
--              interest a mutable accumulator; refund parts flattened);
--              workflows deposit-interest-accrual-cycle, deposit-refund-
--              processing, customer-move-out (closed while a refund is owed).
--
-- What lands:
--
--   1. Account lifecycle (CI-121). customers gains status_reason /
--      status_changed_at / status_changed_by; every change of
--      customers.status requires a reason and is written by the database
--      into customer_state_events (from, to, effective_at, reason, actor,
--      source) — append-only, backfilled with one 'initial' row per
--      customer at created_at. The matrix is enforced narrowly where the
--      corpus is explicit: closed reopens only to active; entering closed is
--      refused while a deposit is held / partially applied / refund pending
--      (customer-move-out Exc 2). customer_status_as_of(customer, at) reads
--      the log.
--
--   2. Date-effective account attributes (CI-121's mid-state values).
--      customer_attribute_history records every change of the attributes
--      billing and collections key on — billing_delivery_method,
--      billing_hold, consolidate_invoices, do_not_disconnect,
--      landlord_responsible, customer_type, autopay_enabled (from
--      auto_pay_settings) and deposit_status (from the projection in 5) —
--      written by triggers, append-only, backfilled with the current value
--      at created_at ('backfill'). customer_attribute_as_of(customer,
--      attribute, at) returns the value in force (NULL before recorded
--      history — never the current value).
--
--   3. deposit_interest_rates — effective-dated per tenant (Kyle
--      2026-06-12), append-only; deposit_interest_rate_as_of(tenant, date)
--      raises when no rate covers the date (no fallback). Rates are
--      annual; accruals compute per-day on a 365-day basis
--      (deposit_accrual_amount()).
--
--   4. deposit_waiver_determinations (CI-129): a recorded determination,
--      not a re-derivation — waiver_class ∈ family_violence_certified |
--      age_65_no_balance | good_payment_history | tariff, with the
--      certification reference/expiry where one exists; append-only. A
--      §7.45-basis deposit cannot be posted for a customer with an
--      unexpired determination (table #53 ranks 0–3; #55 rule 8).
--
--   5. deposits — one record per deposit with the columns every decision
--      table found missing: basis (credit_evaluation |
--      adequate_assurance_366 | additional_trigger | tariff — plus
--      legacy_unknown, insertable only by the backfill), trigger_basis,
--      instrument (§366(c)(1)(A)'s six forms + guarantor: cash accrues
--      interest, nothing else does), principal, posted_on, the cap
--      (cap_amount / cap_basis_annual_billing / cap_binding — required for
--      a Texas residential §7.45 deposit and principal may not exceed it),
--      instrument issuer/reference/expiry for non-cash. Identity is frozen;
--      status (held | partial_applied | applied | refund_pending | refunded |
--      released) is a PROJECTION of the events in 6, not a caller write.
--      customers.deposit_* and payments.is_deposit/deposit_status are
--      reconciled: the customers scalars become a database-maintained
--      projection of the deposits (direct writes rejected), and
--      payments.deposit_status must be set exactly when is_deposit (NOT
--      VALID for legacy rows, reported).
--
--   6. deposit_events — the append-only sub-ledger (posted |
--      applied_to_balance | interest_accrued | interest_credited |
--      refund_initiated | refunded | released), each with amount,
--      effective_on, optional account_ledger link (same customer/tenant;
--      'deposit_interest' joins the ledger's transaction types and
--      'deposit' its reference types). The guard makes the statute
--      structural: interest_accrued only on cash, only once the deposit has
--      been held past 30 days (day-31 cliff), with the FIRST period
--      starting ON posted_on (retroactive to day 1) and every later period
--      contiguous with the previous (no gap, no overlap — exclusion
--      constraint), never spanning a rate change or a principal
--      application, at the rate in force (deposit_interest_rate_as_of) on
--      the principal in force, with amount = deposit_accrual_amount(); never
--      after the accrual horizon. refunded requires accrued interest to be
--      credited in full when held > 30 days and accrual to reach the
--      horizon; a deposit refunded ≤ 30 days must carry no accrual. The
--      horizon is the day before the return OR the day before the principal
--      was exhausted by applications, whichever is first — interest is owed
--      on money held (Codex round 1: a deposit consumed by the final bill
--      could otherwise never be settled). A fully applied deposit is status
--      'applied' and is settled by a zero-amount refunded event (CI-131
--      Alt 2: the obligation is still recorded). The posted event is written
--      by the database when the deposit is inserted.
--      deposit_balance(deposit) derives principal / applied / remainder /
--      accrued / credited / days_held.
--
--   7. CI-131 monitoring substrate: deposit_refund_trigger_state(deposit)
--      derives the consecutive-paid-bills count, delinquent occasions and
--      current delinquency from invoices since posting; the view
--      deposits_refund_due lists §7.45 cash deposits whose trigger has
--      fired (twelve clean bills, ≤ 2 delinquencies, not delinquent) or
--      whose customer is closed / final_billed / inactive — the standing
--      obligation made visible. A §366 deposit never appears there (table
--      #54 rule 3). customer_credits gains deposit_id (required for
--      origin_type = 'deposit_refund' on INSERT / change; legacy rows linked
--      where possible).
--
--   8. Tenant binding: UNIQUE (id, tenant_id) on customers, payments,
--      customer_credits, account_ledger; every new FK composite; users
--      checked by assert_same_tenant_user(). RLS + FORCE on the six new
--      tables; the view is security_invoker (Fable: a superuser-owned view
--      bypasses RLS); REVOKE DELETE (and UPDATE on the append-only ones)
--      from tally_app; all six join the CI-014 set; every guard ENABLE
--      ALWAYS. TEMP is revoked on the database from PUBLIC and tally_app:
--      the pg_trigger_depth() fences (here and A-20's counter) hold only
--      if the application role cannot define a function or a trigger —
--      with TEMP it could (a pg_temp function on a temp table) and Fable
--      reached depth 2 as tally_app. Now it owns no table and can create
--      no function. A backdated deposit_interest_rates row is refused once
--      any accrual for the tenant has settled through that date.
--
-- Deferred with stated triggers (not in this patch): the accrual job and
-- the refund job themselves (application; the ledger refuses what they must
-- not do and the view shows what they must do); the credit-vs-disbursement
-- refund path and the minimum_refund_amount exclusion (table #54 rule 8 —
-- workflow, flagged); estimated annual billing for the cap (table #53 OQ5
-- — the cap is stored and enforced, its derivation is the application's);
-- residential non-cash instruments (table #55 rule 2 — "decide, do not
-- default": this patch accepts any instrument for any class and records
-- it; the tariff acceptance set is configuration); instrument-expiry
-- alerting (the pattern is tax_exemption_expiring — a later rider);
-- disconnect_reason on service_orders (3K-collections); a fuller
-- customers.status matrix (only the two corpus-explicit rules are
-- enforced; the rest is Kyle's).
--
-- Preconditions: none are refusals. Backfill: one 'initial' state event and
-- one 'backfill' attribute-history row per customer; one legacy_unknown
-- cash deposit per customer whose scalar reports a deposit (deposit_amount
-- > 0 and status held / partial_applied / refund_pending / applied /
-- refunded): principal = deposit_amount, posted_on = deposit_received_date
-- else created_at, the prior deposit_interest_earned kept as
-- legacy_interest_earned (no accrual events can be reconstructed without a
-- rate history). held / partial_applied / refund_pending come back as held
-- (the applied part and the pending refund are not reconstructible);
-- applied and refunded are carried as synthetic 'backfill' events written
-- before the sub-ledger guard exists (Codex round 1: without them the
-- projection froze those customers' scalars with nothing to post against).
-- payments and customer_credits rows that violate the new CHECKs are
-- counted and reported (NOT VALID), never fatal.
--
-- Drafting decisions (durable copies: application/DECISION-LOG.md):
--   * The state log is written BY THE DATABASE from customers.status with
--     the reason carried on the row (status_reason, required on change) —
--     the A-1 shape (the closing reason lives on the closed row). An
--     application-written log can be skipped; a trigger-written one cannot.
--   * Attribute history is one narrow table (attribute, old, new,
--     effective_at) rather than versioned customers rows: the invariant
--     asks "what was the value on date X", and a change log answers it
--     without a header/version split on the widest table in the schema.
--   * Deposit status is a projection of events. The decision tables found
--     six representations disagreeing because each was written
--     independently; making the events the only write path and everything
--     else derived (deposits.status, customers.deposit_*, the balance
--     function) is the reconciliation.
--   * Interest is events, never an accumulator: the accrual event carries
--     period, rate, principal basis and amount, and the guard recomputes
--     the amount — an accrual at the wrong rate, over a gap, from day 31
--     instead of day 1, on a bond, past the return date, or twice over the
--     same period is refused, not detected later.
--   * The day-31 cliff is two rules (an accrual may exist only once the
--     hold exceeds 30 days; a refund at ≤ 30 days may carry none) so the
--     cliff is visible in the events, as the accrual workflow asks.
--   * Rates are per tenant, effective-dated, append-only, no fallback:
--     deposit_interest_rate_as_of raises when no rate covers the date (the
--     A-1 rule — "unknowable" is an error, never "use today's").
--   * The waiver is a determination row with its own dates, in its own
--     table under RLS: a family-violence certification is among the most
--     sensitive data the platform holds (table #53 OQ2); it does not go on
--     customers. This patch adds no column-level access control (none
--     exists in the schema) — flagged.
--   * legacy_unknown basis exists so history can be carried without
--     inventing a basis; it is not insertable after the patch and a
--     legacy deposit never appears in deposits_refund_due (its basis is
--     unknown, so §7.45's trigger cannot be asserted for it) — an operator
--     reclassifies by refunding and re-posting, or Kyle rules. A legacy
--     deposit with no accrual events may be refunded without the accrual
--     requirement, with a recorded reason (its interest is the carried
--     legacy_interest_earned, settled outside this ledger) — flagged.
--   * The state-transition reason is consumed into the event by the BEFORE
--     trigger and cleared from the row: a reason that lingered was reused by
--     the next transition (Fable M5). Event tables carry an identity `seq`
--     so as-of reads are ordered within one instant (Fable M6). A new
--     customer gets its initial attribute rows at insert (Fable M7).
--   * NOT VALID CHECKs were the wrong tool: they still fire on any UPDATE of
--     the offending legacy row (Fable H4). payments is reconciled at patch
--     time and the CHECK is VALID; customer_credits' lineage is a trigger on
--     INSERT / change of origin or deposit.
--   * Functions are pinned SET search_path = public, pg_temp with every
--     reference qualified (D-2026-08-28-22).
--
-- Verification contract: this file applies standalone under
--   SET search_path = ''; SET check_function_bodies = on;
-- (D-2026-08-20-24). Every relation and function reference is qualified.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Tenant-bound identity for composite FKs
-- ----------------------------------------------------------------------------
DO $$
DECLARE t text;
BEGIN
    FOREACH t IN ARRAY ARRAY['customers', 'payments', 'customer_credits', 'account_ledger'] LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = t || '_id_tenant_id_key' AND conrelid = ('public.' || t)::regclass) THEN
            EXECUTE format('ALTER TABLE public.%I ADD CONSTRAINT %I UNIQUE (id, tenant_id)', t, t || '_id_tenant_id_key');
        END IF;
    END LOOP;
END;
$$;

-- ----------------------------------------------------------------------------
-- 2. Account lifecycle state events (CI-121)
-- ----------------------------------------------------------------------------
ALTER TABLE public.customers
    ADD COLUMN IF NOT EXISTS status_reason text,
    ADD COLUMN IF NOT EXISTS status_changed_at timestamp with time zone,
    ADD COLUMN IF NOT EXISTS status_changed_by uuid;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'customers_status_changed_by_fkey' AND conrelid = 'public.customers'::regclass) THEN
        ALTER TABLE public.customers ADD CONSTRAINT customers_status_changed_by_fkey FOREIGN KEY (status_changed_by) REFERENCES public.users(id);
    END IF;
END;
$$;

COMMENT ON COLUMN public.customers.status_reason IS 'Write-only (v5.4.2-06, CI-121): required (non-blank) on the UPDATE that changes status; consumed into customer_state_events.reason_code and cleared, so it never lingers for the next transition. Free text until a reason catalogue exists.';
COMMENT ON COLUMN public.customers.status_changed_at IS 'Server-stamped (clock_timestamp(), so events in one transaction stay ordered) on every status change (v5.4.2-06); caller values replaced.';

CREATE TABLE IF NOT EXISTS public.customer_state_events (
    id              uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id       uuid NOT NULL,
    customer_id     uuid NOT NULL,
    from_status     text,
    to_status       text NOT NULL,
    effective_at    timestamp with time zone NOT NULL,
    reason_code     text NOT NULL,
    changed_by      uuid,
    source          text DEFAULT 'operator' NOT NULL,
    created_at      timestamp with time zone DEFAULT now() NOT NULL,
    seq             bigint GENERATED ALWAYS AS IDENTITY,
    CONSTRAINT customer_state_events_pkey PRIMARY KEY (id),
    CONSTRAINT customer_state_events_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id),
    CONSTRAINT customer_state_events_customer_fkey FOREIGN KEY (customer_id, tenant_id) REFERENCES public.customers(id, tenant_id),
    CONSTRAINT customer_state_events_changed_by_fkey FOREIGN KEY (changed_by) REFERENCES public.users(id),
    CONSTRAINT customer_state_events_to_status_check CHECK (to_status = ANY (ARRAY['active'::text, 'inactive'::text, 'final_billed'::text, 'collections'::text, 'closed'::text])),
    CONSTRAINT customer_state_events_from_status_check CHECK (from_status IS NULL OR from_status = ANY (ARRAY['active'::text, 'inactive'::text, 'final_billed'::text, 'collections'::text, 'closed'::text])),
    CONSTRAINT customer_state_events_source_check CHECK (source = ANY (ARRAY['operator'::text, 'system'::text, 'initial'::text, 'backfill'::text])),
    CONSTRAINT customer_state_events_reason_check CHECK (reason_code IS NOT NULL AND length(btrim(reason_code)) > 0)
);
CREATE INDEX IF NOT EXISTS idx_customer_state_events_customer ON public.customer_state_events USING btree (customer_id, effective_at DESC);
CREATE INDEX IF NOT EXISTS idx_customer_state_events_tenant ON public.customer_state_events USING btree (tenant_id);
ALTER TABLE public.customer_state_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customer_state_events FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_isolation ON public.customer_state_events;
CREATE POLICY tenant_isolation ON public.customer_state_events USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));
COMMENT ON TABLE public.customer_state_events IS
    'CI-121 (v5.4.2-06, A-21): the account state-transition log. Written by the database on every INSERT of a customer (source initial) and every change of customers.status (reason from customers.status_reason, actor from status_changed_by, effective_at = server clock); one backfill row per pre-existing customer at created_at. Append-only. customer_status_as_of() reads it.';

CREATE OR REPLACE FUNCTION public.customer_status_as_of(p_customer_id uuid, p_at timestamp with time zone) RETURNS text
    LANGUAGE sql STABLE
    SET search_path = public, pg_temp
    AS $$
    SELECT e.to_status FROM public.customer_state_events e
     WHERE e.customer_id = p_customer_id AND e.effective_at <= p_at
     ORDER BY e.effective_at DESC, e.seq DESC LIMIT 1
$$;
COMMENT ON FUNCTION public.customer_status_as_of(uuid, timestamp with time zone) IS 'CI-121: the account status in force at p_at per customer_state_events; NULL before recorded history (never the current value). p_at is required.';

CREATE OR REPLACE FUNCTION public.enforce_customer_lifecycle() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        NEW.status_changed_at := clock_timestamp();
        PERFORM public.assert_same_tenant_user(NEW.status_changed_by, NEW.tenant_id, 'status_changed_by');
        -- The reason for the initial state is the creation itself; the row
        -- never carries a reason forward (a later transition must supply its own).
        NEW.status_reason := NULL;
        RETURN NEW;
    END IF;
    IF OLD.status IS DISTINCT FROM NEW.status THEN
        IF NEW.status_reason IS NULL OR length(btrim(NEW.status_reason)) = 0 THEN
            RAISE EXCEPTION USING
                MESSAGE = format('customer %s: status %s -> %s requires status_reason (CI-121: every transition is a reason-coded event)', OLD.customer_number, OLD.status, NEW.status),
                ERRCODE = 'check_violation';
        END IF;
        IF OLD.status = 'closed' AND NEW.status <> 'active' THEN
            RAISE EXCEPTION USING
                MESSAGE = format('customer %s: closed reopens only to active, not %s (CI-121)', OLD.customer_number, NEW.status),
                ERRCODE = 'check_violation';
        END IF;
        IF NEW.status = 'closed' AND EXISTS (SELECT 1 FROM public.deposits d WHERE d.customer_id = OLD.id AND d.status IN ('held', 'partial_applied', 'applied', 'refund_pending')) THEN
            RAISE EXCEPTION USING
                MESSAGE = format('customer %s cannot be closed while a deposit is held, applied but not settled, or a refund is pending (CI-131 / customer-move-out Exc 2): record the refund (a zero refund when fully applied) or release the instrument first', OLD.customer_number),
                ERRCODE = 'check_violation';
        END IF;
        PERFORM public.assert_same_tenant_user(NEW.status_changed_by, OLD.tenant_id, 'status_changed_by');
        NEW.status_changed_at := clock_timestamp();   -- ordered even within one transaction
        -- The event is the record; written here so the reason cannot linger on
        -- the row and be reused by the next transition (Fable round 1, M5).
        INSERT INTO public.customer_state_events (tenant_id, customer_id, from_status, to_status, effective_at, reason_code, changed_by, source)
        VALUES (OLD.tenant_id, OLD.id, OLD.status, NEW.status, NEW.status_changed_at, NEW.status_reason, NEW.status_changed_by, 'operator');
        NEW.status_reason := NULL;
        NEW.status_changed_by := NULL;
    ELSE
        -- No transition: nothing to record; a reason supplied without a change is dropped.
        NEW.status_reason := NULL;
        NEW.status_changed_by := OLD.status_changed_by;
        NEW.status_changed_at := coalesce(OLD.status_changed_at, NEW.status_changed_at);
    END IF;
    RETURN NEW;
END;
$$;
COMMENT ON FUNCTION public.enforce_customer_lifecycle() IS 'CI-121 guard on customers (v5.4.2-06): a status change needs status_reason and is written to customer_state_events by this trigger (the reason and actor are consumed into the event and never linger on the row); closed reopens only to active; closed is refused while a deposit is held / partially applied / applied-unsettled / refund pending; status_changed_at is the server''s (clock_timestamp()).';

-- (the lifecycle trigger is created after the backfill, section 10, so the
--  backfill can stamp status_changed_at on legacy rows)

CREATE OR REPLACE FUNCTION public.log_customer_state_event() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
BEGIN
    INSERT INTO public.customer_state_events (tenant_id, customer_id, from_status, to_status, effective_at, reason_code, changed_by, source)
    VALUES (NEW.tenant_id, NEW.id, NULL, NEW.status, NEW.status_changed_at, 'account created', NEW.status_changed_by, 'initial');
    RETURN NULL;
END;
$$;
COMMENT ON FUNCTION public.log_customer_state_event() IS 'AFTER INSERT on customers (v5.4.2-06): the initial state event. Transitions are logged by enforce_customer_lifecycle() itself.';
DROP TRIGGER IF EXISTS z_log_customer_state_event ON public.customers;
CREATE TRIGGER z_log_customer_state_event AFTER INSERT ON public.customers
    FOR EACH ROW EXECUTE FUNCTION public.log_customer_state_event();

CREATE OR REPLACE FUNCTION public.enforce_append_only() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
BEGIN
    RAISE EXCEPTION USING
        MESSAGE = format('%s is append-only (CI-121 / CI-125 / CI-088): a recorded event is never edited or deleted — record a correcting event', TG_TABLE_NAME),
        ERRCODE = 'restrict_violation';
END;
$$;
COMMENT ON FUNCTION public.enforce_append_only() IS 'Generic UPDATE/DELETE refusal for the v5.4.2-06 event tables (customer_state_events, customer_attribute_history, deposit_events, deposit_interest_rates, deposit_waiver_determinations).';

-- ----------------------------------------------------------------------------
-- 3. Date-effective account attributes (CI-121)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.customer_attribute_history (
    id              uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id       uuid NOT NULL,
    customer_id     uuid NOT NULL,
    attribute       text NOT NULL,
    old_value       text,
    new_value       text,
    effective_at    timestamp with time zone NOT NULL,
    changed_by      uuid,
    source          text DEFAULT 'operator' NOT NULL,
    created_at      timestamp with time zone DEFAULT now() NOT NULL,
    seq             bigint GENERATED ALWAYS AS IDENTITY,
    CONSTRAINT customer_attribute_history_pkey PRIMARY KEY (id),
    CONSTRAINT customer_attribute_history_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id),
    CONSTRAINT customer_attribute_history_customer_fkey FOREIGN KEY (customer_id, tenant_id) REFERENCES public.customers(id, tenant_id),
    CONSTRAINT customer_attribute_history_changed_by_fkey FOREIGN KEY (changed_by) REFERENCES public.users(id),
    CONSTRAINT customer_attribute_history_attribute_check CHECK (attribute = ANY (ARRAY[
        'billing_delivery_method'::text, 'billing_hold'::text, 'consolidate_invoices'::text, 'do_not_disconnect'::text,
        'landlord_responsible'::text, 'customer_type'::text, 'autopay_enabled'::text, 'deposit_status'::text])),
    CONSTRAINT customer_attribute_history_source_check CHECK (source = ANY (ARRAY['operator'::text, 'system'::text, 'initial'::text, 'backfill'::text]))
);
CREATE INDEX IF NOT EXISTS idx_customer_attribute_history_lookup ON public.customer_attribute_history USING btree (customer_id, attribute, effective_at DESC);
CREATE INDEX IF NOT EXISTS idx_customer_attribute_history_tenant ON public.customer_attribute_history USING btree (tenant_id);
ALTER TABLE public.customer_attribute_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customer_attribute_history FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_isolation ON public.customer_attribute_history;
CREATE POLICY tenant_isolation ON public.customer_attribute_history USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));
COMMENT ON TABLE public.customer_attribute_history IS
    'CI-121 mid-state values (v5.4.2-06, A-21): every change of the account attributes billing and collections key on, written by the database (customers: billing_delivery_method, billing_hold, consolidate_invoices, do_not_disconnect, landlord_responsible, customer_type; auto_pay_settings: autopay_enabled; deposits projection: deposit_status). One backfill row per attribute per pre-existing customer at created_at. Append-only. customer_attribute_as_of() reads it.';

CREATE OR REPLACE FUNCTION public.customer_attribute_as_of(p_customer_id uuid, p_attribute text, p_at timestamp with time zone) RETURNS text
    LANGUAGE sql STABLE
    SET search_path = public, pg_temp
    AS $$
    SELECT h.new_value FROM public.customer_attribute_history h
     WHERE h.customer_id = p_customer_id AND h.attribute = p_attribute AND h.effective_at <= p_at
     ORDER BY h.effective_at DESC, h.seq DESC LIMIT 1
$$;
COMMENT ON FUNCTION public.customer_attribute_as_of(uuid, text, timestamp with time zone) IS 'CI-121: the attribute value in force at p_at (text; cast at the call site). NULL before recorded history — never the current value.';

CREATE OR REPLACE FUNCTION public.log_customer_attribute_changes() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO public.customer_attribute_history (tenant_id, customer_id, attribute, old_value, new_value, effective_at, source)
        SELECT NEW.tenant_id, NEW.id, a.attribute, NULL,
               CASE a.attribute
                   WHEN 'billing_delivery_method' THEN NEW.billing_delivery_method
                   WHEN 'billing_hold' THEN NEW.billing_hold::text
                   WHEN 'consolidate_invoices' THEN NEW.consolidate_invoices::text
                   WHEN 'do_not_disconnect' THEN NEW.do_not_disconnect::text
                   WHEN 'landlord_responsible' THEN NEW.landlord_responsible::text
                   WHEN 'customer_type' THEN NEW.customer_type
                   WHEN 'deposit_status' THEN NEW.deposit_status
                   WHEN 'autopay_enabled' THEN 'false'
               END,
               NEW.status_changed_at, 'initial'
          FROM (SELECT unnest(ARRAY['billing_delivery_method', 'billing_hold', 'consolidate_invoices', 'do_not_disconnect', 'landlord_responsible', 'customer_type', 'deposit_status', 'autopay_enabled']) AS attribute) a;
        RETURN NULL;
    END IF;
    IF OLD.billing_delivery_method IS DISTINCT FROM NEW.billing_delivery_method THEN
        INSERT INTO public.customer_attribute_history (tenant_id, customer_id, attribute, old_value, new_value, effective_at) VALUES (NEW.tenant_id, NEW.id, 'billing_delivery_method', OLD.billing_delivery_method, NEW.billing_delivery_method, clock_timestamp());
    END IF;
    IF OLD.billing_hold IS DISTINCT FROM NEW.billing_hold THEN
        INSERT INTO public.customer_attribute_history (tenant_id, customer_id, attribute, old_value, new_value, effective_at, changed_by) VALUES (NEW.tenant_id, NEW.id, 'billing_hold', OLD.billing_hold::text, NEW.billing_hold::text, clock_timestamp(), NEW.billing_hold_set_by);
    END IF;
    IF OLD.consolidate_invoices IS DISTINCT FROM NEW.consolidate_invoices THEN
        INSERT INTO public.customer_attribute_history (tenant_id, customer_id, attribute, old_value, new_value, effective_at) VALUES (NEW.tenant_id, NEW.id, 'consolidate_invoices', OLD.consolidate_invoices::text, NEW.consolidate_invoices::text, clock_timestamp());
    END IF;
    IF OLD.do_not_disconnect IS DISTINCT FROM NEW.do_not_disconnect THEN
        INSERT INTO public.customer_attribute_history (tenant_id, customer_id, attribute, old_value, new_value, effective_at) VALUES (NEW.tenant_id, NEW.id, 'do_not_disconnect', OLD.do_not_disconnect::text, NEW.do_not_disconnect::text, clock_timestamp());
    END IF;
    IF OLD.landlord_responsible IS DISTINCT FROM NEW.landlord_responsible THEN
        INSERT INTO public.customer_attribute_history (tenant_id, customer_id, attribute, old_value, new_value, effective_at) VALUES (NEW.tenant_id, NEW.id, 'landlord_responsible', OLD.landlord_responsible::text, NEW.landlord_responsible::text, clock_timestamp());
    END IF;
    IF OLD.customer_type IS DISTINCT FROM NEW.customer_type THEN
        INSERT INTO public.customer_attribute_history (tenant_id, customer_id, attribute, old_value, new_value, effective_at) VALUES (NEW.tenant_id, NEW.id, 'customer_type', OLD.customer_type, NEW.customer_type, clock_timestamp());
    END IF;
    IF OLD.deposit_status IS DISTINCT FROM NEW.deposit_status THEN
        INSERT INTO public.customer_attribute_history (tenant_id, customer_id, attribute, old_value, new_value, effective_at, source) VALUES (NEW.tenant_id, NEW.id, 'deposit_status', OLD.deposit_status, NEW.deposit_status, clock_timestamp(), 'system');
    END IF;
    RETURN NULL;
END;
$$;
DROP TRIGGER IF EXISTS z_log_customer_attribute_changes ON public.customers;
CREATE TRIGGER z_log_customer_attribute_changes AFTER INSERT OR UPDATE ON public.customers
    FOR EACH ROW EXECUTE FUNCTION public.log_customer_attribute_changes();

CREATE OR REPLACE FUNCTION public.log_autopay_attribute_change() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO public.customer_attribute_history (tenant_id, customer_id, attribute, old_value, new_value, effective_at)
        VALUES (NEW.tenant_id, NEW.customer_id, 'autopay_enabled', NULL, NEW.enabled::text, clock_timestamp());
    ELSIF OLD.enabled IS DISTINCT FROM NEW.enabled OR OLD.customer_id <> NEW.customer_id THEN
        INSERT INTO public.customer_attribute_history (tenant_id, customer_id, attribute, old_value, new_value, effective_at)
        VALUES (NEW.tenant_id, NEW.customer_id, 'autopay_enabled', OLD.enabled::text, NEW.enabled::text, clock_timestamp());
    END IF;
    RETURN NULL;
END;
$$;
DROP TRIGGER IF EXISTS z_log_autopay_attribute_change ON public.auto_pay_settings;
CREATE TRIGGER z_log_autopay_attribute_change AFTER INSERT OR UPDATE ON public.auto_pay_settings
    FOR EACH ROW EXECUTE FUNCTION public.log_autopay_attribute_change();

-- ----------------------------------------------------------------------------
-- 4. deposit_interest_rates (CI-125 / CI-130; Kyle 2026-06-12)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.deposit_interest_rates (
    id                  uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id           uuid NOT NULL,
    effective_date      date NOT NULL,
    annual_rate         numeric(8,6) NOT NULL,
    source_reference    text,
    notes               text,
    created_by          uuid,
    created_at          timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT deposit_interest_rates_pkey PRIMARY KEY (id),
    CONSTRAINT deposit_interest_rates_tenant_effective_key UNIQUE (tenant_id, effective_date),
    CONSTRAINT deposit_interest_rates_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id),
    CONSTRAINT deposit_interest_rates_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id),
    CONSTRAINT deposit_interest_rates_rate_check CHECK (annual_rate >= 0 AND annual_rate <= 1)
);
ALTER TABLE public.deposit_interest_rates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.deposit_interest_rates FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_isolation ON public.deposit_interest_rates;
CREATE POLICY tenant_isolation ON public.deposit_interest_rates USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));
CREATE OR REPLACE FUNCTION public.enforce_deposit_interest_rate() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE v_settled date;
BEGIN
    PERFORM public.assert_same_tenant_user(NEW.created_by, NEW.tenant_id, 'created_by');
    NEW.created_at := now();
    SELECT max(e.period_end) INTO v_settled
      FROM public.deposit_events e JOIN public.deposits d ON d.id = e.deposit_id
     WHERE d.tenant_id = NEW.tenant_id AND e.event_type = 'interest_accrued';
    IF v_settled IS NOT NULL AND NEW.effective_date <= v_settled THEN
        RAISE EXCEPTION USING
            MESSAGE = format('deposit interest rate effective %s rejected: interest has already been accrued through %s at the rates then in force; a settled accrual is never re-rated (CI-125 / CI-130) — a correction is a new accrual period at the new rate from %s', NEW.effective_date, v_settled, v_settled + 1),
            ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS a_enforce_deposit_interest_rate ON public.deposit_interest_rates;
CREATE TRIGGER a_enforce_deposit_interest_rate BEFORE INSERT ON public.deposit_interest_rates
    FOR EACH ROW EXECUTE FUNCTION public.enforce_deposit_interest_rate();

COMMENT ON TABLE public.deposit_interest_rates IS
    'CI-125 / CI-130 (v5.4.2-06, Kyle 2026-06-12): the effective-dated deposit interest rate per tenant (annual, as a fraction — 0.0287 = 2.87%; the PUCT-set rate for a Texas tenant). A new rate is a new row; rows are never edited or deleted. deposit_interest_rate_as_of() raises when no row covers a date.';

CREATE OR REPLACE FUNCTION public.deposit_interest_rate_as_of(p_tenant_id uuid, p_on date) RETURNS numeric
    LANGUAGE plpgsql STABLE
    SET search_path = public, pg_temp
    AS $$
DECLARE v numeric;
BEGIN
    IF p_on IS NULL THEN
        RAISE EXCEPTION USING MESSAGE = 'deposit_interest_rate_as_of: p_on is required', ERRCODE = 'null_value_not_allowed';
    END IF;
    SELECT r.annual_rate INTO v FROM public.deposit_interest_rates r
     WHERE r.tenant_id = p_tenant_id AND r.effective_date <= p_on
     ORDER BY r.effective_date DESC LIMIT 1;
    IF v IS NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('no deposit interest rate is in force for tenant %s on %s (CI-125: the rate is date-effective; there is no fallback)', p_tenant_id, p_on),
            ERRCODE = 'no_data_found';
    END IF;
    RETURN v;
END;
$$;
COMMENT ON FUNCTION public.deposit_interest_rate_as_of(uuid, date) IS 'The annual deposit interest rate in force on p_on for the tenant; RAISES when none (never a fallback). Invoker rights: RLS applies.';

CREATE OR REPLACE FUNCTION public.deposit_accrual_amount(p_principal numeric, p_annual_rate numeric, p_period_start date, p_period_end date) RETURNS numeric
    LANGUAGE sql IMMUTABLE
    SET search_path = public, pg_temp
    AS $$
    SELECT round(p_principal * p_annual_rate * ((p_period_end - p_period_start + 1)::numeric / 365), 2)
$$;
COMMENT ON FUNCTION public.deposit_accrual_amount(numeric, numeric, date, date) IS 'Simple interest for an inclusive day range: principal × annual_rate × days/365, rounded to cents. The deposit_events guard requires every interest_accrued event to carry exactly this amount for its period, rate and principal basis.';

-- ----------------------------------------------------------------------------
-- 5. deposit_waiver_determinations (CI-129)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.deposit_waiver_determinations (
    id                          uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id                   uuid NOT NULL,
    customer_id                 uuid NOT NULL,
    waiver_class                text NOT NULL,
    determined_on               date NOT NULL,
    certification_reference     text,
    certification_expires_on    date,
    determined_by               uuid,
    notes                       text,
    created_at                  timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT deposit_waiver_determinations_pkey PRIMARY KEY (id),
    CONSTRAINT deposit_waiver_determinations_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id),
    CONSTRAINT deposit_waiver_determinations_customer_fkey FOREIGN KEY (customer_id, tenant_id) REFERENCES public.customers(id, tenant_id),
    CONSTRAINT deposit_waiver_determinations_determined_by_fkey FOREIGN KEY (determined_by) REFERENCES public.users(id),
    CONSTRAINT deposit_waiver_determinations_class_check CHECK (waiver_class = ANY (ARRAY['family_violence_certified'::text, 'age_65_no_balance'::text, 'good_payment_history'::text, 'tariff'::text])),
    CONSTRAINT deposit_waiver_determinations_certification_check CHECK (waiver_class <> 'family_violence_certified' OR (certification_reference IS NOT NULL AND length(btrim(certification_reference)) > 0)),
    CONSTRAINT deposit_waiver_determinations_expiry_check CHECK (certification_expires_on IS NULL OR certification_expires_on >= determined_on)
);
CREATE INDEX IF NOT EXISTS idx_deposit_waiver_determinations_customer ON public.deposit_waiver_determinations USING btree (customer_id);
CREATE INDEX IF NOT EXISTS idx_deposit_waiver_determinations_tenant ON public.deposit_waiver_determinations USING btree (tenant_id);
ALTER TABLE public.deposit_waiver_determinations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.deposit_waiver_determinations FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_isolation ON public.deposit_waiver_determinations;
CREATE POLICY tenant_isolation ON public.deposit_waiver_determinations USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));
COMMENT ON TABLE public.deposit_waiver_determinations IS
    'CI-129 (v5.4.2-06): a recorded deposit-waiver determination — 16 TAC §7.45 family-violence certification (Texas Council on Family Violence reference required), age-65-with-no-balance, good-payment-history, or a tariff class — with the determination date and the certification''s expiry. A §7.45-basis deposit cannot be posted for a customer with an unexpired determination (table #53 ranks 0–3; #55 rule 8). Append-only. SENSITIVE: the family-violence class is among the most sensitive data the platform holds; RLS applies, no column-level control exists (flagged).';

-- ----------------------------------------------------------------------------
-- 6. deposits (CI-077 / CI-129 / CI-131)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.deposits (
    id                          uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id                   uuid NOT NULL,
    customer_id                 uuid NOT NULL,
    basis                       text NOT NULL,
    trigger_basis               text,
    instrument                  text DEFAULT 'cash' NOT NULL,
    principal                   numeric(12,2) NOT NULL,
    posted_on                   date NOT NULL,
    source_payment_id           uuid,
    cap_amount                  numeric(12,2),
    cap_basis_annual_billing    numeric(12,2),
    cap_binding                 boolean DEFAULT false NOT NULL,
    instrument_issuer           text,
    instrument_reference        text,
    instrument_expires_on       date,
    status                      text DEFAULT 'held' NOT NULL,
    refund_eligibility_on       date,
    refunded_on                 date,
    released_on                 date,
    legacy_interest_earned      numeric(12,2),
    notes                       text,
    created_by                  uuid,
    created_at                  timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT deposits_pkey PRIMARY KEY (id),
    CONSTRAINT deposits_id_tenant_id_key UNIQUE (id, tenant_id),
    CONSTRAINT deposits_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id),
    CONSTRAINT deposits_customer_fkey FOREIGN KEY (customer_id, tenant_id) REFERENCES public.customers(id, tenant_id),
    CONSTRAINT deposits_source_payment_fkey FOREIGN KEY (source_payment_id, tenant_id) REFERENCES public.payments(id, tenant_id),
    CONSTRAINT deposits_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id),
    CONSTRAINT deposits_basis_check CHECK (basis = ANY (ARRAY['credit_evaluation'::text, 'adequate_assurance_366'::text, 'additional_trigger'::text, 'tariff'::text, 'legacy_unknown'::text])),
    CONSTRAINT deposits_trigger_basis_check CHECK (trigger_basis IS NULL OR trigger_basis = ANY (ARRAY['nsf'::text, 'disconnect_history'::text, 'broken_dpa'::text])),
    CONSTRAINT deposits_trigger_basis_required_check CHECK ((basis = 'additional_trigger') = (trigger_basis IS NOT NULL)),
    CONSTRAINT deposits_instrument_check CHECK (instrument = ANY (ARRAY['cash'::text, 'letter_of_credit'::text, 'certificate_of_deposit'::text, 'surety_bond'::text, 'prepayment'::text, 'guarantor'::text, 'other_agreed'::text])),
    CONSTRAINT deposits_principal_check CHECK (principal > 0),
    CONSTRAINT deposits_cap_check CHECK (cap_amount IS NULL OR (cap_amount > 0 AND principal <= cap_amount)),
    CONSTRAINT deposits_cap_binding_check CHECK (NOT cap_binding OR (cap_amount IS NOT NULL AND principal = cap_amount)),
    CONSTRAINT deposits_cap_basis_check CHECK (cap_basis_annual_billing IS NULL OR cap_basis_annual_billing > 0),
    CONSTRAINT deposits_instrument_fields_check CHECK (
        (instrument = 'cash' AND instrument_issuer IS NULL AND instrument_reference IS NULL AND instrument_expires_on IS NULL)
     OR (instrument <> 'cash' AND instrument_reference IS NOT NULL AND length(btrim(instrument_reference)) > 0)),
    CONSTRAINT deposits_status_check CHECK (status = ANY (ARRAY['held'::text, 'partial_applied'::text, 'applied'::text, 'refund_pending'::text, 'refunded'::text, 'released'::text])),
    CONSTRAINT deposits_status_dates_check CHECK (
        (status = 'refunded') = (refunded_on IS NOT NULL) AND (status = 'released') = (released_on IS NOT NULL)),
    CONSTRAINT deposits_released_noncash_check CHECK (status <> 'released' OR instrument <> 'cash'),
    CONSTRAINT deposits_legacy_interest_check CHECK (legacy_interest_earned IS NULL OR basis = 'legacy_unknown')
);
CREATE INDEX IF NOT EXISTS idx_deposits_customer ON public.deposits USING btree (customer_id);
CREATE INDEX IF NOT EXISTS idx_deposits_tenant_open ON public.deposits USING btree (tenant_id, status) WHERE (status = ANY (ARRAY['held'::text, 'partial_applied'::text, 'applied'::text, 'refund_pending'::text]));
CREATE INDEX IF NOT EXISTS idx_deposits_source_payment ON public.deposits USING btree (source_payment_id) WHERE (source_payment_id IS NOT NULL);
ALTER TABLE public.deposits ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.deposits FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_isolation ON public.deposits;
CREATE POLICY tenant_isolation ON public.deposits USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));
COMMENT ON TABLE public.deposits IS
    'A-21 (v5.4.2-06): one record per deposit — the substrate CI-077 / CI-125 / CI-129–131 and decision tables #53–#55 found missing. basis (which rule governs its refund: §7.45 credit_evaluation / additional_trigger / tariff refund on CI-131''s triggers; adequate_assurance_366 never does; legacy_unknown = carried from customers.deposit_* at patch time, not insertable now), instrument (only cash accrues interest; non-cash carries issuer/reference/expiry), principal, posted_on, the §7.45 cap as recorded at the decision (required for a Texas residential §7.45 deposit; principal ≤ cap; cap_binding when it bit). Identity is frozen after insert. status / refunded_on / released_on are a PROJECTION of deposit_events (direct writes rejected): held → partial_applied (applied_to_balance) → refund_pending (refund_initiated) → refunded (refunded); non-cash → released. customers.deposit_* mirror the deposits (database-maintained).';
COMMENT ON COLUMN public.deposits.cap_amount IS '1/6 of estimated annual billing as computed at the deposit decision (table #53 rank 8); the customer is entitled to know when it bound (cap_binding). Its derivation (cap_basis_annual_billing) is the application''s — the database records and enforces it.';
COMMENT ON COLUMN public.deposits.refund_eligibility_on IS 'Optional: the date the application computed the twelve-bill trigger would earliest fire, or a tariff-set eligibility date. Informational; deposits_refund_due derives the standing trigger.';

CREATE TABLE IF NOT EXISTS public.deposit_events (
    id                  uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id           uuid NOT NULL,
    deposit_id          uuid NOT NULL,
    event_type          text NOT NULL,
    amount              numeric(12,2) NOT NULL,
    effective_on        date NOT NULL,
    period_start        date,
    period_end          date,
    rate_applied        numeric(8,6),
    principal_basis     numeric(12,2),
    ledger_entry_id     uuid,
    reason              text,
    created_by          uuid,
    source              text DEFAULT 'operator' NOT NULL,
    created_at          timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT deposit_events_pkey PRIMARY KEY (id),
    CONSTRAINT deposit_events_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id),
    CONSTRAINT deposit_events_deposit_fkey FOREIGN KEY (deposit_id, tenant_id) REFERENCES public.deposits(id, tenant_id),
    CONSTRAINT deposit_events_ledger_fkey FOREIGN KEY (ledger_entry_id, tenant_id) REFERENCES public.account_ledger(id, tenant_id),
    CONSTRAINT deposit_events_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id),
    CONSTRAINT deposit_events_type_check CHECK (event_type = ANY (ARRAY['posted'::text, 'applied_to_balance'::text, 'interest_accrued'::text, 'interest_credited'::text, 'refund_initiated'::text, 'refunded'::text, 'released'::text])),
    CONSTRAINT deposit_events_amount_check CHECK (amount >= 0),
    CONSTRAINT deposit_events_source_check CHECK (source = ANY (ARRAY['operator'::text, 'system'::text, 'backfill'::text])),
    CONSTRAINT deposit_events_accrual_fields_check CHECK (
        (event_type = 'interest_accrued' AND period_start IS NOT NULL AND period_end IS NOT NULL AND period_end >= period_start AND rate_applied IS NOT NULL AND principal_basis IS NOT NULL AND principal_basis > 0)
     OR (event_type <> 'interest_accrued' AND period_start IS NULL AND period_end IS NULL AND rate_applied IS NULL AND principal_basis IS NULL)),
    CONSTRAINT deposit_events_accrual_no_overlap EXCLUDE USING gist (deposit_id WITH =, daterange(period_start, period_end, '[]') WITH &&) WHERE (event_type = 'interest_accrued')
);
CREATE INDEX IF NOT EXISTS idx_deposit_events_deposit ON public.deposit_events USING btree (deposit_id, effective_on);
CREATE INDEX IF NOT EXISTS idx_deposit_events_tenant ON public.deposit_events USING btree (tenant_id);
ALTER TABLE public.deposit_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.deposit_events FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_isolation ON public.deposit_events;
CREATE POLICY tenant_isolation ON public.deposit_events USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));
COMMENT ON TABLE public.deposit_events IS
    'CI-125 / CI-130 / CI-131 (v5.4.2-06): the append-only deposit sub-ledger. posted (written by the database at deposit insert), applied_to_balance, interest_accrued (period, rate in force, principal in force, amount = deposit_accrual_amount — cash only, only once held > 30 days, first period starts ON posted_on, periods contiguous, never across a rate change or a principal application, never past the return date), interest_credited (≤ accrued − credited), refund_initiated, refunded (held ≤ 30 days: no accrual may exist; > 30 days: accrual must reach the return date and be credited in full; amount = remainder), released (non-cash). deposits.status is projected from these. Optional link to the account_ledger row that moved the money (same customer/tenant; transaction_type deposit / adjustment / deposit_interest / refund).';

-- account_ledger enum extensions (interest is its own movement; a deposit is a reference)
ALTER TABLE public.account_ledger DROP CONSTRAINT IF EXISTS account_ledger_transaction_type_check;
ALTER TABLE public.account_ledger ADD CONSTRAINT account_ledger_transaction_type_check CHECK ((transaction_type = ANY (ARRAY[
    'charge'::text, 'payment'::text, 'adjustment'::text, 'credit_issued'::text, 'credit_applied'::text, 'late_fee'::text, 'deposit'::text, 'refund'::text,
    'write_off'::text, 'transfer'::text, 'nsf'::text, 'escheat'::text, 'donation'::text, 'void_reversal'::text, 'deposit_interest'::text])));
ALTER TABLE public.account_ledger DROP CONSTRAINT IF EXISTS account_ledger_reference_type_check;
ALTER TABLE public.account_ledger ADD CONSTRAINT account_ledger_reference_type_check CHECK ((reference_type = ANY (ARRAY[
    'invoice'::text, 'payment'::text, 'customer_credit'::text, 'adhoc_charge'::text, 'invoice_application'::text, 'billing_run'::text,
    'escheatment_event'::text, 'manual'::text, 'invoice_void'::text, 'refund'::text, 'deposit'::text])));

-- payments: deposit_status exactly when is_deposit. Legacy rows are
-- reconciled first (reported), then the CHECK is added VALID — a NOT VALID
-- check would still fire on any later UPDATE of the offending row (Fable
-- round 1, H4), freezing legacy payments.
DO $$
DECLARE v bigint;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'payments_deposit_status_consistent_check' AND conrelid = 'public.payments'::regclass) THEN
        PERFORM set_config('search_path', 'public, pg_temp', true);
        UPDATE public.payments p SET deposit_status = NULL WHERE NOT coalesce(p.is_deposit, false) AND p.deposit_status IS NOT NULL;
        GET DIAGNOSTICS v = ROW_COUNT;
        IF v > 0 THEN RAISE NOTICE 'v5.4.2-06: deposit_status cleared on % payments row(s) not flagged is_deposit', v; END IF;
        UPDATE public.payments p
           SET deposit_status = CASE coalesce(c.deposit_status, 'none')
                                    WHEN 'held' THEN 'held' WHEN 'partial_applied' THEN 'partial_applied' WHEN 'refund_pending' THEN 'held'
                                    WHEN 'applied' THEN 'applied' ELSE 'refunded' END
          FROM public.customers c
         WHERE c.id = p.customer_id AND coalesce(p.is_deposit, false) AND p.deposit_status IS NULL;
        GET DIAGNOSTICS v = ROW_COUNT;
        IF v > 0 THEN RAISE NOTICE 'v5.4.2-06: deposit_status set on % is_deposit payments row(s) from the customer''s deposit status at patch time (approximation)', v; END IF;
        ALTER TABLE public.payments ADD CONSTRAINT payments_deposit_status_consistent_check
            CHECK ((coalesce(is_deposit, false)) = (deposit_status IS NOT NULL));
    END IF;
END;
$$;

-- customer_credits: a deposit refund names its deposit. Enforced by a
-- trigger on INSERT and on a change of origin_type / deposit_id — legacy
-- rows stay updatable (Fable round 1, H4); the backfill links them where the
-- customer has exactly one legacy deposit.
ALTER TABLE public.customer_credits ADD COLUMN IF NOT EXISTS deposit_id uuid;
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'customer_credits_deposit_fkey' AND conrelid = 'public.customer_credits'::regclass) THEN
        ALTER TABLE public.customer_credits ADD CONSTRAINT customer_credits_deposit_fkey FOREIGN KEY (deposit_id, tenant_id) REFERENCES public.deposits(id, tenant_id);
    END IF;
END;
$$;
CREATE OR REPLACE FUNCTION public.enforce_customer_credit_deposit_lineage() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
BEGIN
    IF NEW.origin_type = 'deposit_refund' AND NEW.deposit_id IS NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = 'customer_credits: a deposit_refund credit must name the deposit it returns (deposit_id) — its interest is a separate deposit_events.interest_credited movement',
            ERRCODE = 'check_violation';
    END IF;
    IF NEW.deposit_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.deposits d WHERE d.id = NEW.deposit_id AND d.customer_id = NEW.customer_id) THEN
        RAISE EXCEPTION USING MESSAGE = 'customer_credits: deposit_id must name a deposit of the same customer', ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS enforce_customer_credit_deposit_lineage ON public.customer_credits;
CREATE TRIGGER enforce_customer_credit_deposit_lineage BEFORE INSERT OR UPDATE OF origin_type, deposit_id ON public.customer_credits
    FOR EACH ROW EXECUTE FUNCTION public.enforce_customer_credit_deposit_lineage();
COMMENT ON COLUMN public.customer_credits.deposit_id IS 'v5.4.2-06: the deposit a deposit_refund credit returns (required for that origin on INSERT and when origin_type/deposit_id change; legacy rows were linked where the customer had exactly one legacy deposit, else left NULL and reported). The interest component is a separate deposit_events.interest_credited / account_ledger deposit_interest movement, not folded into the credit.';

-- ----------------------------------------------------------------------------
-- 7. Derivations
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.deposit_balance(p_deposit_id uuid)
    RETURNS TABLE (principal numeric, applied numeric, remainder numeric, interest_accrued numeric, interest_credited numeric, days_held integer, accrued_through date, exhausted_on date)
    LANGUAGE sql STABLE
    SET search_path = public, pg_temp
    AS $$
    SELECT d.principal,
           coalesce((SELECT sum(e.amount) FROM public.deposit_events e WHERE e.deposit_id = d.id AND e.event_type = 'applied_to_balance'), 0),
           d.principal - coalesce((SELECT sum(e.amount) FROM public.deposit_events e WHERE e.deposit_id = d.id AND e.event_type = 'applied_to_balance'), 0),
           coalesce((SELECT sum(e.amount) FROM public.deposit_events e WHERE e.deposit_id = d.id AND e.event_type = 'interest_accrued'), 0),
           coalesce((SELECT sum(e.amount) FROM public.deposit_events e WHERE e.deposit_id = d.id AND e.event_type = 'interest_credited'), 0),
           (coalesce(d.refunded_on, d.released_on, CURRENT_DATE) - d.posted_on)::integer,
           (SELECT max(e.period_end) FROM public.deposit_events e WHERE e.deposit_id = d.id AND e.event_type = 'interest_accrued'),
           -- the first day on which cumulative applications reached the principal (NULL while any remains)
           (SELECT min(x.effective_on) FROM (
                SELECT e.effective_on, sum(e.amount) OVER (ORDER BY e.effective_on, e.created_at, e.id) AS cum
                  FROM public.deposit_events e WHERE e.deposit_id = d.id AND e.event_type = 'applied_to_balance') x
             WHERE x.cum >= d.principal)
    FROM public.deposits d WHERE d.id = p_deposit_id
$$;
COMMENT ON FUNCTION public.deposit_balance(uuid) IS 'Derived from deposit_events (never stored): principal, applied to balance, remainder, interest accrued, interest credited, days held (to refund/release/today), accrued-through date, exhausted_on (the day applications consumed the whole principal — interest is owed through the day before it).';

CREATE OR REPLACE FUNCTION public.deposit_principal_in_force(p_deposit_id uuid, p_on date) RETURNS numeric
    LANGUAGE sql STABLE
    SET search_path = public, pg_temp
    AS $$
    SELECT d.principal - coalesce((SELECT sum(e.amount) FROM public.deposit_events e WHERE e.deposit_id = d.id AND e.event_type = 'applied_to_balance' AND e.effective_on <= p_on), 0)
    FROM public.deposits d WHERE d.id = p_deposit_id
$$;
COMMENT ON FUNCTION public.deposit_principal_in_force(uuid, date) IS 'Principal on which interest accrues on p_on: principal less applications effective on or before that day — an application reduces the basis from its own date forward (accrual-cycle Alt 3).';

CREATE OR REPLACE FUNCTION public.deposit_refund_trigger_state(p_deposit_id uuid)
    RETURNS TABLE (consecutive_paid_bills integer, delinquent_occasions integer, currently_delinquent boolean, twelve_bill_trigger_met boolean)
    LANGUAGE sql STABLE
    SET search_path = public, pg_temp
    AS $$
    -- Bills issued since posting, newest first. "Paid clean": status paid with
    -- no balance and never past dunning_stage current/resolved. Delinquent
    -- occasion: a bill that entered any dunning stage beyond current, or is
    -- overdue. Approximation of §7.45's "paid ... without delinquency"
    -- stated in the COMMENT; the workflow is the authority on the payment
    -- history it feeds.
    WITH d AS (SELECT * FROM public.deposits WHERE id = p_deposit_id),
    bills AS (
        SELECT i.id, i.status, i.balance, i.dunning_stage, i.invoice_date,
               (i.status = 'paid' AND i.balance = 0 AND i.dunning_stage IN ('current', 'resolved')) AS paid_clean,
               (i.status = 'overdue' OR i.dunning_stage NOT IN ('current', 'resolved')) AS delinquent,
               row_number() OVER (ORDER BY i.invoice_date DESC, i.created_at DESC) AS rn
        FROM public.invoices i, d
        WHERE i.customer_id = d.customer_id AND i.invoice_date >= d.posted_on
          AND i.status NOT IN ('draft', 'held', 'void') AND i.invoice_type IN ('regular', 'final', 'correction')
    ),
    first_unclean AS (SELECT min(rn) AS rn FROM bills WHERE NOT paid_clean)
    SELECT (SELECT count(*)::integer FROM bills b, first_unclean f WHERE b.paid_clean AND (f.rn IS NULL OR b.rn < f.rn)),
           (SELECT count(*)::integer FROM bills WHERE delinquent),
           (SELECT count(*) > 0 FROM bills WHERE status = 'overdue'),
           (SELECT count(*)::integer FROM bills b, first_unclean f WHERE b.paid_clean AND (f.rn IS NULL OR b.rn < f.rn)) >= 12
             AND (SELECT count(*)::integer FROM bills WHERE delinquent) <= 2
             AND NOT (SELECT count(*) > 0 FROM bills WHERE status = 'overdue')
$$;
COMMENT ON FUNCTION public.deposit_refund_trigger_state(uuid) IS 'CI-131 standing condition, derived from invoices since posting: trailing consecutive paid-clean bills, delinquent occasions, current delinquency, and whether §7.45''s twelve-bill trigger is met (≥ 12, ≤ 2, not delinquent). The definition of "paid clean" / "delinquent" is an approximation stated in the function body; the refund workflow is the authority and must record its own evaluation.';

CREATE OR REPLACE VIEW public.deposits_refund_due WITH (security_invoker = true) AS
    SELECT d.id AS deposit_id, d.tenant_id, d.customer_id, d.basis, d.principal, d.posted_on, d.status,
           c.status AS customer_status,
           CASE WHEN c.status IN ('closed', 'final_billed', 'inactive') THEN 'account_closed_or_inactive' ELSE 'twelve_clean_bills' END AS refund_trigger,
           s.consecutive_paid_bills, s.delinquent_occasions, s.currently_delinquent
    FROM public.deposits d
    JOIN public.customers c ON c.id = d.customer_id
    CROSS JOIN LATERAL public.deposit_refund_trigger_state(d.id) s
    WHERE d.instrument = 'cash'
      AND d.basis IN ('credit_evaluation', 'additional_trigger', 'tariff')
      AND d.status IN ('held', 'partial_applied', 'applied')
      AND (c.status IN ('closed', 'final_billed', 'inactive') OR s.twelve_bill_trigger_met);
COMMENT ON VIEW public.deposits_refund_due IS 'CI-131 (v5.4.2-06): §7.45 cash deposits whose mandatory refund trigger has fired and no refund has been initiated — the standing obligation made visible (the schema previously watched only refunds issued and unpaid). A §366 deposit never appears (table #54 rule 3); a legacy_unknown deposit never appears (its basis is unknown). The refund job reads this; an anomaly on a row that persists is the job''s.';

-- ----------------------------------------------------------------------------
-- 8. Guards: deposits (identity frozen, projection columns database-only,
--    Texas cap, waivers, legacy), deposit_events (the ledger rules),
--    projections onto deposits and customers
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.enforce_deposit() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_cust public.customers%ROWTYPE;
    v_state text;
    v_waiver text;
BEGIN
    IF TG_OP = 'INSERT' THEN
        SELECT * INTO v_cust FROM public.customers c WHERE c.id = NEW.customer_id;
        IF NOT FOUND THEN
            RAISE EXCEPTION USING MESSAGE = format('deposit rejected: customer %s not found (or not visible)', NEW.customer_id), ERRCODE = 'foreign_key_violation';
        END IF;
        IF NEW.basis = 'legacy_unknown' THEN
            RAISE EXCEPTION USING MESSAGE = 'deposit rejected: basis legacy_unknown exists only for rows carried from customers.deposit_* at patch time — record the basis that governs this deposit''s refund', ERRCODE = 'check_violation';
        END IF;
        IF NEW.status <> 'held' OR NEW.refunded_on IS NOT NULL OR NEW.released_on IS NOT NULL THEN
            RAISE EXCEPTION USING MESSAGE = 'deposit rejected: a deposit is born held; status / refunded_on / released_on are projected from deposit_events', ERRCODE = 'check_violation';
        END IF;
        PERFORM public.assert_same_tenant_user(NEW.created_by, NEW.tenant_id, 'created_by');
        IF NEW.source_payment_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.payments p WHERE p.id = NEW.source_payment_id AND p.customer_id = NEW.customer_id AND coalesce(p.is_deposit, false)) THEN
            RAISE EXCEPTION USING MESSAGE = 'deposit rejected: source_payment_id must be a payment of the same customer flagged is_deposit', ERRCODE = 'check_violation';
        END IF;
        -- §7.45 deposits (everything but a §366 assurance) honour a recorded waiver.
        IF NEW.basis IN ('credit_evaluation', 'additional_trigger', 'tariff') THEN
            SELECT w.waiver_class INTO v_waiver FROM public.deposit_waiver_determinations w
             WHERE w.customer_id = NEW.customer_id AND w.determined_on <= NEW.posted_on
               AND (w.certification_expires_on IS NULL OR w.certification_expires_on >= NEW.posted_on)
             ORDER BY w.determined_on DESC LIMIT 1;
            IF v_waiver IS NOT NULL THEN
                RAISE EXCEPTION USING
                    MESSAGE = format('deposit rejected: customer %s holds a %s deposit-waiver determination in force on %s — no §7.45 deposit may be required (CI-129, 16 TAC §7.45; table #53 ranks 0–3, #55 rule 8)', v_cust.customer_number, v_waiver, NEW.posted_on),
                    ERRCODE = 'check_violation';
            END IF;
            -- Texas residential: the cap is part of the record.
            SELECT t.state INTO v_state FROM public.tenants t WHERE t.id = NEW.tenant_id;
            IF upper(coalesce(v_state, '')) = 'TX' AND v_cust.customer_type = 'residential' AND NEW.instrument = 'cash' AND NEW.cap_amount IS NULL THEN
                RAISE EXCEPTION USING
                    MESSAGE = 'deposit rejected: a Texas residential deposit must record cap_amount (1/6 of estimated annual billing, 16 TAC §7.45 — CI-129) and principal may not exceed it',
                    ERRCODE = 'check_violation';
            END IF;
        END IF;
        RETURN NEW;
    END IF;

    -- UPDATE: identity frozen; projection columns only from inside the events trigger.
    IF OLD.id <> NEW.id OR OLD.tenant_id <> NEW.tenant_id OR OLD.customer_id <> NEW.customer_id OR OLD.basis <> NEW.basis
       OR OLD.trigger_basis IS DISTINCT FROM NEW.trigger_basis OR OLD.instrument <> NEW.instrument OR OLD.principal <> NEW.principal
       OR OLD.posted_on <> NEW.posted_on OR OLD.source_payment_id IS DISTINCT FROM NEW.source_payment_id
       OR OLD.cap_amount IS DISTINCT FROM NEW.cap_amount OR OLD.cap_basis_annual_billing IS DISTINCT FROM NEW.cap_basis_annual_billing
       OR OLD.cap_binding <> NEW.cap_binding OR OLD.legacy_interest_earned IS DISTINCT FROM NEW.legacy_interest_earned
       OR OLD.created_by IS DISTINCT FROM NEW.created_by OR OLD.created_at <> NEW.created_at THEN
        RAISE EXCEPTION USING
            MESSAGE = format('deposit %s: identity (customer, basis, instrument, principal, posted_on, cap, source) is frozen — a wrong deposit is refunded/released and re-posted', OLD.id),
            ERRCODE = 'check_violation';
    END IF;
    IF (OLD.status <> NEW.status OR OLD.refunded_on IS DISTINCT FROM NEW.refunded_on OR OLD.released_on IS DISTINCT FROM NEW.released_on)
       AND pg_trigger_depth() < 2 THEN
        RAISE EXCEPTION USING
            MESSAGE = format('deposit %s: status / refunded_on / released_on are projected from deposit_events — insert the event (applied_to_balance, refund_initiated, refunded, released)', OLD.id),
            ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$;
-- (the a_enforce_deposit trigger is created after the backfill, section 10 —
--  the legacy_unknown rows must be written before the guard that refuses
--  that basis exists; the posted-event and projection triggers exist first)

CREATE OR REPLACE FUNCTION public.enforce_deposit_event() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    d public.deposits%ROWTYPE;
    b record;
    v_rate numeric;
    v_prev_end date;
    v_basis numeric;
    v_expected numeric;
    v_horizon date;
BEGIN
    SELECT * INTO d FROM public.deposits x WHERE x.id = NEW.deposit_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING MESSAGE = format('deposit event rejected: deposit %s not found (or not visible)', NEW.deposit_id), ERRCODE = 'foreign_key_violation';
    END IF;
    IF d.tenant_id <> NEW.tenant_id THEN
        RAISE EXCEPTION USING MESSAGE = 'deposit event rejected: tenant_id must equal the deposit''s', ERRCODE = 'check_violation';
    END IF;
    IF NEW.source = 'backfill' AND pg_trigger_depth() < 2 THEN
        RAISE EXCEPTION USING MESSAGE = 'deposit event rejected: source backfill is written only by the database for a legacy deposit''s posted event', ERRCODE = 'check_violation';
    END IF;
    PERFORM public.assert_same_tenant_user(NEW.created_by, NEW.tenant_id, 'created_by');
    NEW.created_at := now();
    IF d.status IN ('refunded', 'released') THEN
        RAISE EXCEPTION USING MESSAGE = format('deposit %s is %s: no further events (post a new deposit if one is required again)', d.id, d.status), ERRCODE = 'check_violation';
    END IF;
    IF NEW.effective_on < d.posted_on THEN
        RAISE EXCEPTION USING MESSAGE = format('deposit event rejected: effective_on %s precedes posted_on %s', NEW.effective_on, d.posted_on), ERRCODE = 'check_violation';
    END IF;
    IF NEW.ledger_entry_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM public.account_ledger l WHERE l.id = NEW.ledger_entry_id AND l.customer_id = d.customer_id
           AND l.transaction_type IN ('deposit', 'adjustment', 'deposit_interest', 'refund', 'credit_issued')) THEN
        RAISE EXCEPTION USING MESSAGE = 'deposit event rejected: ledger_entry_id must be an account_ledger row of the same customer with transaction_type deposit / adjustment / deposit_interest / refund / credit_issued', ERRCODE = 'check_violation';
    END IF;
    SELECT * INTO b FROM public.deposit_balance(d.id);

    CASE NEW.event_type
    WHEN 'posted' THEN
        IF pg_trigger_depth() < 2 THEN
            RAISE EXCEPTION USING MESSAGE = 'deposit event rejected: the posted event is written by the database when the deposit is inserted', ERRCODE = 'check_violation';
        END IF;
    WHEN 'applied_to_balance' THEN
        IF d.status = 'refund_pending' THEN
            RAISE EXCEPTION USING MESSAGE = format('deposit %s: a refund is pending — the remainder is committed to the customer; record the refund (or a new deposit)', d.id), ERRCODE = 'check_violation';
        END IF;
        IF NEW.amount <= 0 OR NEW.amount > b.remainder THEN
            RAISE EXCEPTION USING MESSAGE = format('deposit %s: applied_to_balance must be > 0 and ≤ the remainder %s', d.id, b.remainder), ERRCODE = 'check_violation';
        END IF;
        IF b.accrued_through IS NOT NULL AND NEW.effective_on <= b.accrued_through THEN
            RAISE EXCEPTION USING MESSAGE = format('deposit %s: interest has already accrued through %s on the full principal; an application effective %s would change a settled period — apply it from %s', d.id, b.accrued_through, NEW.effective_on, b.accrued_through + 1), ERRCODE = 'check_violation';
        END IF;
    WHEN 'interest_accrued' THEN
        IF d.instrument <> 'cash' THEN
            RAISE EXCEPTION USING MESSAGE = format('deposit %s is a %s: only cash accrues interest (CI-125; table #55 — the LDC owes interest on money it holds, not on a promise)', d.id, d.instrument), ERRCODE = 'check_violation';
        END IF;
        IF NEW.effective_on - d.posted_on < 31 THEN
            RAISE EXCEPTION USING MESSAGE = format('deposit %s: no interest accrues until the deposit has been held more than 30 days (posted %s; day 31 is %s) — then it accrues retroactively to the posting date (CI-130, 16 TAC §7.45)', d.id, d.posted_on, d.posted_on + 31), ERRCODE = 'check_violation';
        END IF;
        -- The same 30-day rule measured to the accrual horizon: a deposit
        -- whose principal was exhausted within 30 days of posting owes no
        -- interest at all, and an accrual recorded for its short life would
        -- block the zero refund forever (Codex round 2).
        IF b.exhausted_on IS NOT NULL AND b.exhausted_on - d.posted_on <= 30 THEN
            RAISE EXCEPTION USING MESSAGE = format('deposit %s was exhausted on %s, %s days after posting: no interest is owed on it (CI-130) — settle it with a zero refund', d.id, b.exhausted_on, b.exhausted_on - d.posted_on), ERRCODE = 'check_violation';
        END IF;
        SELECT max(e.period_end) INTO v_prev_end FROM public.deposit_events e WHERE e.deposit_id = d.id AND e.event_type = 'interest_accrued';
        IF v_prev_end IS NULL THEN
            IF NEW.period_start <> d.posted_on THEN
                RAISE EXCEPTION USING MESSAGE = format('deposit %s: the first accrual period must start ON the posting date %s — interest is retroactive to day 1, not from day 31 (CI-130)', d.id, d.posted_on), ERRCODE = 'check_violation';
            END IF;
        ELSIF NEW.period_start <> v_prev_end + 1 THEN
            RAISE EXCEPTION USING MESSAGE = format('deposit %s: accrual periods are contiguous — the next period starts %s, not %s', d.id, v_prev_end + 1, NEW.period_start), ERRCODE = 'check_violation';
        END IF;
        IF NEW.period_end >= NEW.effective_on THEN
            RAISE EXCEPTION USING MESSAGE = format('deposit %s: an accrual is recorded after the period it covers (period_end %s, effective_on %s)', d.id, NEW.period_end, NEW.effective_on), ERRCODE = 'check_violation';
        END IF;
        v_rate := public.deposit_interest_rate_as_of(d.tenant_id, NEW.period_start);
        IF NEW.rate_applied <> v_rate THEN
            RAISE EXCEPTION USING MESSAGE = format('deposit %s: rate_applied %s is not the rate in force on %s (%s) — deposit_interest_rate_as_of (CI-125 / CI-130)', d.id, NEW.rate_applied, NEW.period_start, v_rate), ERRCODE = 'check_violation';
        END IF;
        IF EXISTS (SELECT 1 FROM public.deposit_interest_rates r WHERE r.tenant_id = d.tenant_id AND r.effective_date > NEW.period_start AND r.effective_date <= NEW.period_end) THEN
            RAISE EXCEPTION USING MESSAGE = format('deposit %s: the accrual period %s..%s spans a rate change — split it at the rate''s effective date (accrual-cycle step 3)', d.id, NEW.period_start, NEW.period_end), ERRCODE = 'check_violation';
        END IF;
        IF EXISTS (SELECT 1 FROM public.deposit_events e WHERE e.deposit_id = d.id AND e.event_type = 'applied_to_balance' AND e.effective_on > NEW.period_start AND e.effective_on <= NEW.period_end) THEN
            RAISE EXCEPTION USING MESSAGE = format('deposit %s: the accrual period %s..%s spans a principal application — split it at the application date (accrual-cycle Alt 3)', d.id, NEW.period_start, NEW.period_end), ERRCODE = 'check_violation';
        END IF;
        v_basis := public.deposit_principal_in_force(d.id, NEW.period_start);
        IF v_basis <= 0 THEN
            RAISE EXCEPTION USING MESSAGE = format('deposit %s: the principal was exhausted on %s — nothing is held from that day and no interest accrues after %s', d.id, b.exhausted_on, b.exhausted_on - 1), ERRCODE = 'check_violation';
        END IF;
        IF NEW.principal_basis <> v_basis THEN
            RAISE EXCEPTION USING MESSAGE = format('deposit %s: principal_basis %s is not the principal in force on %s (%s)', d.id, NEW.principal_basis, NEW.period_start, v_basis), ERRCODE = 'check_violation';
        END IF;
        v_expected := public.deposit_accrual_amount(v_basis, v_rate, NEW.period_start, NEW.period_end);
        IF NEW.amount <> v_expected THEN
            RAISE EXCEPTION USING MESSAGE = format('deposit %s: accrual amount %s ≠ %s = %s × %s × %s/365 (deposit_accrual_amount)', d.id, NEW.amount, v_expected, v_basis, v_rate, NEW.period_end - NEW.period_start + 1), ERRCODE = 'check_violation';
        END IF;
    WHEN 'interest_credited' THEN
        IF NEW.amount <= 0 OR NEW.amount > b.interest_accrued - b.interest_credited THEN
            RAISE EXCEPTION USING MESSAGE = format('deposit %s: interest_credited must be > 0 and ≤ accrued − credited (%s)', d.id, b.interest_accrued - b.interest_credited), ERRCODE = 'check_violation';
        END IF;
    WHEN 'refund_initiated' THEN
        IF d.status = 'refund_pending' THEN
            RAISE EXCEPTION USING MESSAGE = format('deposit %s: a refund is already pending', d.id), ERRCODE = 'check_violation';
        END IF;
        IF NEW.amount <> b.remainder THEN
            RAISE EXCEPTION USING MESSAGE = format('deposit %s: refund_initiated amount must be the remainder %s (interest is credited separately and disclosed separately — table #54 rule 7)', d.id, b.remainder), ERRCODE = 'check_violation';
        END IF;
    WHEN 'refunded' THEN
        IF d.instrument <> 'cash' THEN
            RAISE EXCEPTION USING MESSAGE = format('deposit %s is a %s: a non-cash instrument is released, not refunded', d.id, d.instrument), ERRCODE = 'check_violation';
        END IF;
        IF NEW.amount <> b.remainder THEN
            RAISE EXCEPTION USING MESSAGE = format('deposit %s: refunded amount must be the remainder %s (apply to balance first with applied_to_balance; interest is a separate movement; a fully applied deposit is settled by a zero refund)', d.id, b.remainder), ERRCODE = 'check_violation';
        END IF;
        -- Interest is owed on money held: through the day before the return,
        -- or the day before the principal was exhausted, whichever is first
        -- (Codex round 1: a deposit consumed by the final bill could never
        -- satisfy "accrue to the return date" — nothing was held to accrue on).
        v_horizon := least(NEW.effective_on, coalesce(b.exhausted_on, NEW.effective_on));
        IF d.basis = 'legacy_unknown' AND b.interest_accrued = 0 THEN
            -- A deposit carried from customers.deposit_* has no rate history to
            -- accrue against; its interest lives in legacy_interest_earned. It
            -- may be settled without ledger accrual, with the reason recorded
            -- (flagged for Ryan/Kyle: the alternative is to enter the rate
            -- history back to posting and accrue before every legacy refund).
            IF NEW.reason IS NULL OR length(btrim(NEW.reason)) = 0 THEN
                RAISE EXCEPTION USING MESSAGE = format('deposit %s is a legacy deposit with no accrual history: refunding it requires a reason stating how its interest was settled (legacy_interest_earned = %s)', d.id, coalesce(d.legacy_interest_earned, 0)), ERRCODE = 'check_violation';
            END IF;
        ELSIF v_horizon - d.posted_on <= 30 THEN
            IF b.interest_accrued > 0 THEN
                RAISE EXCEPTION USING MESSAGE = format('deposit %s was held %s days (to %s): no interest is owed, yet %s has been accrued (CI-130)', d.id, v_horizon - d.posted_on, v_horizon, b.interest_accrued), ERRCODE = 'check_violation';
            END IF;
        ELSE
            IF b.accrued_through IS NULL OR b.accrued_through < v_horizon - 1 THEN
                RAISE EXCEPTION USING MESSAGE = format('deposit %s held %s days: interest must be accrued retroactively from %s through %s (the day before %s) before it is refunded — accrued through %s (CI-130: retained > 30 days ⇒ interest to the return date)', d.id, v_horizon - d.posted_on, d.posted_on, v_horizon - 1, CASE WHEN b.exhausted_on IS NOT NULL AND b.exhausted_on <= NEW.effective_on THEN 'exhaustion' ELSE 'return' END, coalesce(b.accrued_through::text, 'nothing')), ERRCODE = 'check_violation';
            END IF;
            IF b.interest_credited <> b.interest_accrued THEN
                RAISE EXCEPTION USING MESSAGE = format('deposit %s: accrued interest %s must be credited in full (credited %s) before the refund — paid at refund (CI-130 / CI-131)', d.id, b.interest_accrued, b.interest_credited), ERRCODE = 'check_violation';
            END IF;
        END IF;
    WHEN 'released' THEN
        IF d.instrument = 'cash' THEN
            RAISE EXCEPTION USING MESSAGE = format('deposit %s is cash: cash is refunded, not released', d.id), ERRCODE = 'check_violation';
        END IF;
        IF NEW.amount <> b.remainder THEN
            RAISE EXCEPTION USING MESSAGE = format('deposit %s: released amount must be the instrument''s remaining face value %s', d.id, b.remainder), ERRCODE = 'check_violation';
        END IF;
    END CASE;
    RETURN NEW;
END;
$$;
COMMENT ON FUNCTION public.enforce_deposit_event() IS 'The deposit sub-ledger rules (v5.4.2-06; CI-125 / CI-130 / CI-131) — see the table COMMENT on deposit_events. Locks the deposit row so concurrent events serialise.';

-- (the a_enforce_deposit_event trigger is created after the backfill, section
--  10 — legacy applied/refunded history is carried as synthetic events the
--  rules could not admit; the projection triggers exist first)

-- Projection: deposits.status from events; customers.deposit_* from deposits.
CREATE OR REPLACE FUNCTION public.project_deposit_status() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    b record;
BEGIN
    SELECT * INTO b FROM public.deposit_balance(NEW.deposit_id);
    UPDATE public.deposits d
       SET status = CASE NEW.event_type
                        WHEN 'refunded' THEN 'refunded'
                        WHEN 'released' THEN 'released'
                        WHEN 'refund_initiated' THEN 'refund_pending'
                        WHEN 'applied_to_balance' THEN CASE WHEN b.remainder = 0 THEN 'applied' ELSE 'partial_applied' END
                        ELSE d.status END,
           refunded_on = CASE WHEN NEW.event_type = 'refunded' THEN NEW.effective_on ELSE d.refunded_on END,
           released_on = CASE WHEN NEW.event_type = 'released' THEN NEW.effective_on ELSE d.released_on END
     WHERE d.id = NEW.deposit_id;
    RETURN NULL;
END;
$$;
DROP TRIGGER IF EXISTS z_project_deposit_status ON public.deposit_events;
CREATE TRIGGER z_project_deposit_status AFTER INSERT ON public.deposit_events
    FOR EACH ROW EXECUTE FUNCTION public.project_deposit_status();

CREATE OR REPLACE FUNCTION public.project_customer_deposit_scalars() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_customer uuid := coalesce(NEW.customer_id, OLD.customer_id);
    v_open record;
    v_last record;
    v_interest numeric;
BEGIN
    SELECT count(*) AS n,
           coalesce(sum(CASE WHEN d.instrument = 'cash' THEN bal.remainder ELSE 0 END), 0) AS held,
           max(d.posted_on) AS last_posted,
           (array_agg(d.status ORDER BY d.posted_on DESC, d.created_at DESC))[1] AS latest_status
      INTO v_open
      FROM public.deposits d
      CROSS JOIN LATERAL public.deposit_balance(d.id) bal
     WHERE d.customer_id = v_customer AND d.status IN ('held', 'partial_applied', 'applied', 'refund_pending');
    SELECT d.refunded_on, bal.remainder AS refunded_amount
      INTO v_last
      FROM public.deposits d
      CROSS JOIN LATERAL public.deposit_balance(d.id) bal
     WHERE d.customer_id = v_customer AND d.status = 'refunded'
     ORDER BY d.refunded_on DESC, d.created_at DESC LIMIT 1;
    SELECT coalesce(sum(bal.interest_accrued + coalesce(d.legacy_interest_earned, 0)), 0)
      INTO v_interest
      FROM public.deposits d
      CROSS JOIN LATERAL public.deposit_balance(d.id) bal
     WHERE d.customer_id = v_customer;
    UPDATE public.customers c
       SET deposit_amount = v_open.held,
           deposit_status = CASE WHEN v_open.n = 0 THEN CASE WHEN v_last.refunded_on IS NOT NULL THEN 'refunded' ELSE 'none' END ELSE v_open.latest_status END,
           deposit_received_date = v_open.last_posted,
           deposit_refund_date = v_last.refunded_on,
           deposit_refund_amount = v_last.refunded_amount,
           deposit_interest_earned = v_interest
     WHERE c.id = v_customer;
    RETURN NULL;
END;
$$;
COMMENT ON FUNCTION public.project_customer_deposit_scalars() IS 'v5.4.2-06: customers.deposit_amount / deposit_status / deposit_received_date / deposit_refund_date / deposit_refund_amount / deposit_interest_earned are a projection of the customer''s deposits (cash remainder held; latest open status or refunded/none; last posting; last refund; interest accrued + legacy). Maintained here; direct writes are rejected.';
DROP TRIGGER IF EXISTS z_project_customer_deposit_scalars ON public.deposits;
CREATE TRIGGER z_project_customer_deposit_scalars AFTER INSERT OR UPDATE ON public.deposits
    FOR EACH ROW EXECUTE FUNCTION public.project_customer_deposit_scalars();

-- The database writes the posted event.
CREATE OR REPLACE FUNCTION public.post_deposit_event() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
BEGIN
    INSERT INTO public.deposit_events (tenant_id, deposit_id, event_type, amount, effective_on, created_by, source)
    VALUES (NEW.tenant_id, NEW.id, 'posted', NEW.principal, NEW.posted_on, NEW.created_by, CASE WHEN NEW.basis = 'legacy_unknown' THEN 'backfill' ELSE 'system' END);
    RETURN NULL;
END;
$$;
DROP TRIGGER IF EXISTS y_post_deposit_event ON public.deposits;
CREATE TRIGGER y_post_deposit_event AFTER INSERT ON public.deposits
    FOR EACH ROW EXECUTE FUNCTION public.post_deposit_event();

-- customers.deposit_* are the database's.
CREATE OR REPLACE FUNCTION public.enforce_customer_deposit_projection() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
BEGIN
    IF (OLD.deposit_amount IS DISTINCT FROM NEW.deposit_amount OR OLD.deposit_status IS DISTINCT FROM NEW.deposit_status
        OR OLD.deposit_received_date IS DISTINCT FROM NEW.deposit_received_date OR OLD.deposit_refund_date IS DISTINCT FROM NEW.deposit_refund_date
        OR OLD.deposit_refund_amount IS DISTINCT FROM NEW.deposit_refund_amount OR OLD.deposit_interest_earned IS DISTINCT FROM NEW.deposit_interest_earned)
       AND pg_trigger_depth() < 2 THEN
        RAISE EXCEPTION USING
            MESSAGE = format('customer %s: deposit_amount / deposit_status / deposit_received_date / deposit_refund_* / deposit_interest_earned are projected from deposits and deposit_events (v5.4.2-06) — post a deposit or a deposit event', OLD.customer_number),
            ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS b_enforce_customer_deposit_projection ON public.customers;
CREATE TRIGGER b_enforce_customer_deposit_projection BEFORE UPDATE ON public.customers
    FOR EACH ROW EXECUTE FUNCTION public.enforce_customer_deposit_projection();

-- ----------------------------------------------------------------------------
-- 9. Append-only guards, CI-014 set, privileges
-- ----------------------------------------------------------------------------
DO $$
DECLARE t text;
BEGIN
    FOREACH t IN ARRAY ARRAY['customer_state_events', 'customer_attribute_history', 'deposit_events', 'deposit_interest_rates', 'deposit_waiver_determinations'] LOOP
        EXECUTE format('DROP TRIGGER IF EXISTS append_only ON public.%I', t);
        EXECUTE format('CREATE TRIGGER append_only BEFORE UPDATE OR DELETE ON public.%I FOR EACH ROW EXECUTE FUNCTION public.enforce_append_only()', t);
        EXECUTE format('DROP TRIGGER IF EXISTS no_truncate ON public.%I', t);
        EXECUTE format('CREATE TRIGGER no_truncate BEFORE TRUNCATE ON public.%I FOR EACH STATEMENT EXECUTE FUNCTION public.enforce_no_hard_delete()', t);
        EXECUTE format('REVOKE UPDATE, DELETE ON public.%I FROM tally_app', t);
    END LOOP;
    DROP TRIGGER IF EXISTS no_hard_delete ON public.deposits;
    CREATE TRIGGER no_hard_delete BEFORE DELETE ON public.deposits FOR EACH ROW EXECUTE FUNCTION public.enforce_no_hard_delete();
    DROP TRIGGER IF EXISTS no_truncate ON public.deposits;
    CREATE TRIGGER no_truncate BEFORE TRUNCATE ON public.deposits FOR EACH STATEMENT EXECUTE FUNCTION public.enforce_no_hard_delete();
    REVOKE DELETE ON public.deposits FROM tally_app;
    -- pg_trigger_depth() is a structural fence only if the application role
    -- cannot run code inside a trigger of its own: with TEMP it could create a
    -- temp table + pg_temp function + trigger and reach depth 2 (Fable round
    -- 1, CRITICAL). No CREATE on any schema, no TRIGGER on any table, and now
    -- no TEMP: there is no table tally_app owns and no function it can define.
    EXECUTE format('REVOKE TEMP ON DATABASE %I FROM PUBLIC', current_database());
    EXECUTE format('REVOKE TEMP ON DATABASE %I FROM tally_app', current_database());
END;
$$;

-- ----------------------------------------------------------------------------
-- 10. Backfill (reporting only, never a refusal; re-runnable)
-- ----------------------------------------------------------------------------
DO $$
DECLARE
    v bigint;
BEGIN
    PERFORM set_config('search_path', 'public, pg_temp', true);

    -- 10.1 One initial state event per pre-existing customer.
    INSERT INTO public.customer_state_events (tenant_id, customer_id, from_status, to_status, effective_at, reason_code, source)
    SELECT c.tenant_id, c.id, NULL, c.status, c.created_at, 'backfill: status at v5.4.2-06', 'backfill'
      FROM public.customers c
     WHERE NOT EXISTS (SELECT 1 FROM public.customer_state_events e WHERE e.customer_id = c.id);
    GET DIAGNOSTICS v = ROW_COUNT;
    IF v > 0 THEN RAISE NOTICE 'v5.4.2-06: initial state event written for % customer(s) at created_at (approximation of the transition instant)', v; END IF;
    UPDATE public.customers c SET status_changed_at = c.created_at WHERE c.status_changed_at IS NULL;

    -- 10.2 One backfill attribute row per attribute per customer.
    INSERT INTO public.customer_attribute_history (tenant_id, customer_id, attribute, old_value, new_value, effective_at, source)
    SELECT c.tenant_id, c.id, a.attribute, NULL,
           CASE a.attribute
               WHEN 'billing_delivery_method' THEN c.billing_delivery_method
               WHEN 'billing_hold' THEN c.billing_hold::text
               WHEN 'consolidate_invoices' THEN c.consolidate_invoices::text
               WHEN 'do_not_disconnect' THEN c.do_not_disconnect::text
               WHEN 'landlord_responsible' THEN c.landlord_responsible::text
               WHEN 'customer_type' THEN c.customer_type
               WHEN 'deposit_status' THEN c.deposit_status
               WHEN 'autopay_enabled' THEN coalesce((SELECT a2.enabled::text FROM public.auto_pay_settings a2 WHERE a2.customer_id = c.id LIMIT 1), 'false')
           END,
           c.created_at, 'backfill'
      FROM public.customers c
      CROSS JOIN (SELECT unnest(ARRAY['billing_delivery_method', 'billing_hold', 'consolidate_invoices', 'do_not_disconnect', 'landlord_responsible', 'customer_type', 'deposit_status', 'autopay_enabled']) AS attribute) a
     WHERE NOT EXISTS (SELECT 1 FROM public.customer_attribute_history h WHERE h.customer_id = c.id AND h.attribute = a.attribute);
    GET DIAGNOSTICS v = ROW_COUNT;
    IF v > 0 THEN RAISE NOTICE 'v5.4.2-06: % attribute-history backfill row(s) written at created_at (current values; history before this patch is unknown)', v; END IF;

    -- 10.3 Legacy deposits from the customers scalars (only where no deposit
    --      exists yet). The event guard does not exist yet: applied / refunded
    --      history is carried as synthetic 'backfill' events the rules could
    --      not admit (no rate history, no accrual). A refund_pending scalar
    --      comes back as held (the pending refund is not an event we can
    --      reconstruct); a partial_applied scalar as held with the amount the
    --      scalar reported (the applied part is unknown).
    CREATE TEMP TABLE zz_legacy_deposits ON COMMIT DROP AS
    SELECT c.id AS customer_id, c.tenant_id, c.deposit_amount, c.deposit_status, c.deposit_refund_date, c.deposit_refund_amount,
           coalesce(c.deposit_received_date, c.created_at::date) AS posted_on, c.created_at, nullif(c.deposit_interest_earned, 0) AS legacy_interest
      FROM public.customers c
     WHERE c.deposit_amount > 0
       AND c.deposit_status IN ('held', 'partial_applied', 'refund_pending', 'applied', 'refunded')
       AND NOT EXISTS (SELECT 1 FROM public.deposits d WHERE d.customer_id = c.id);
    INSERT INTO public.deposits (id, tenant_id, customer_id, basis, instrument, principal, posted_on, status, legacy_interest_earned, notes)
    SELECT public.uuid_generate_v5(l.customer_id, 'legacy-deposit-v5.4.2-06'), l.tenant_id, l.customer_id, 'legacy_unknown', 'cash', l.deposit_amount, l.posted_on, 'held', l.legacy_interest,
           'backfill v5.4.2-06 from customers.deposit_* (status was ' || l.deposit_status || '); basis unknown — reclassify by refund + re-post, or a Kyle ruling'
      FROM zz_legacy_deposits l;
    GET DIAGNOSTICS v = ROW_COUNT;
    -- applied: the whole principal was applied (date unknown: refund date, else the posting date)
    INSERT INTO public.deposit_events (tenant_id, deposit_id, event_type, amount, effective_on, reason, source)
    SELECT l.tenant_id, public.uuid_generate_v5(l.customer_id, 'legacy-deposit-v5.4.2-06'), 'applied_to_balance', l.deposit_amount,
           greatest(coalesce(l.deposit_refund_date, l.posted_on), l.posted_on), 'backfill: customers.deposit_status was applied; application date unknown', 'backfill'
      FROM zz_legacy_deposits l WHERE l.deposit_status = 'applied';
    -- refunded: refunded for the amount the scalar reported (else the principal), on the refund date (else the posting date)
    INSERT INTO public.deposit_events (tenant_id, deposit_id, event_type, amount, effective_on, reason, source)
    SELECT l.tenant_id, public.uuid_generate_v5(l.customer_id, 'legacy-deposit-v5.4.2-06'), 'refunded', coalesce(l.deposit_refund_amount, l.deposit_amount),
           greatest(coalesce(l.deposit_refund_date, l.posted_on), l.posted_on), 'backfill: customers.deposit_status was refunded; interest history unknown', 'backfill'
      FROM zz_legacy_deposits l WHERE l.deposit_status = 'refunded';
    IF v > 0 THEN RAISE NOTICE 'v5.4.2-06: % legacy deposit(s) carried from customers.deposit_* as basis legacy_unknown (held / partial_applied / refund_pending → held; applied → applied; refunded → refunded via synthetic backfill events; prior deposit_interest_earned kept as legacy_interest_earned)', v; END IF;

    -- 10.4 Legacy deposit_refund credits: link to the customer's legacy deposit where exactly one exists.
    UPDATE public.customer_credits cc
       SET deposit_id = d.id
      FROM public.deposits d
     WHERE cc.origin_type = 'deposit_refund' AND cc.deposit_id IS NULL AND d.customer_id = cc.customer_id AND d.basis = 'legacy_unknown'
       AND (SELECT count(*) FROM public.deposits d2 WHERE d2.customer_id = cc.customer_id) = 1;
    GET DIAGNOSTICS v = ROW_COUNT;
    IF v > 0 THEN RAISE NOTICE 'v5.4.2-06: % legacy deposit_refund credit(s) linked to the customer''s legacy deposit', v; END IF;
    SELECT count(*) INTO v FROM public.customer_credits cc WHERE cc.origin_type = 'deposit_refund' AND cc.deposit_id IS NULL;
    IF v > 0 THEN RAISE NOTICE 'v5.4.2-06: % deposit_refund credit(s) remain without a deposit_id (no single legacy deposit to link); they stay as they are', v; END IF;
END;
$$;

DROP TRIGGER IF EXISTS a_enforce_customer_lifecycle ON public.customers;
CREATE TRIGGER a_enforce_customer_lifecycle BEFORE INSERT OR UPDATE ON public.customers
    FOR EACH ROW EXECUTE FUNCTION public.enforce_customer_lifecycle();
DROP TRIGGER IF EXISTS a_enforce_deposit ON public.deposits;
CREATE TRIGGER a_enforce_deposit BEFORE INSERT OR UPDATE ON public.deposits
    FOR EACH ROW EXECUTE FUNCTION public.enforce_deposit();
DROP TRIGGER IF EXISTS a_enforce_deposit_event ON public.deposit_events;
CREATE TRIGGER a_enforce_deposit_event BEFORE INSERT ON public.deposit_events
    FOR EACH ROW EXECUTE FUNCTION public.enforce_deposit_event();

-- ----------------------------------------------------------------------------
-- 11. ENABLE ALWAYS on every guard this patch created
-- ----------------------------------------------------------------------------
DO $$
DECLARE r record;
BEGIN
    FOR r IN
        SELECT c.relname, t.tgname
        FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public' AND NOT t.tgisinternal AND t.tgenabled <> 'A'
          AND (
                (c.relname IN ('customer_state_events', 'customer_attribute_history', 'deposit_events', 'deposit_interest_rates', 'deposit_waiver_determinations', 'deposits')
                 AND t.tgname IN ('append_only', 'no_truncate', 'no_hard_delete', 'a_enforce_deposit', 'a_enforce_deposit_event', 'z_project_deposit_status', 'y_post_deposit_event', 'z_project_customer_deposit_scalars'))
             OR (c.relname = 'customers' AND t.tgname IN ('a_enforce_customer_lifecycle', 'z_log_customer_state_event', 'z_log_customer_attribute_changes', 'b_enforce_customer_deposit_projection'))
             OR (c.relname = 'auto_pay_settings' AND t.tgname = 'z_log_autopay_attribute_change')
             OR (c.relname = 'deposit_interest_rates' AND t.tgname = 'a_enforce_deposit_interest_rate')
             OR (c.relname = 'customer_credits' AND t.tgname = 'enforce_customer_credit_deposit_lineage')
          )
    LOOP
        EXECUTE format('ALTER TABLE public.%I ENABLE ALWAYS TRIGGER %I', r.relname, r.tgname);
    END LOOP;
END;
$$;

-- ----------------------------------------------------------------------------
-- 12. Cross-references on existing objects
-- ----------------------------------------------------------------------------
COMMENT ON COLUMN public.customers.deposit_amount IS 'PROJECTION (v5.4.2-06): cash principal currently held less applications, over the customer''s open deposits. Maintained by the database from deposits / deposit_events; direct writes rejected. The record is public.deposits.';
COMMENT ON COLUMN public.customers.deposit_status IS 'PROJECTION (v5.4.2-06): the latest open deposit''s status (held | partial_applied | refund_pending), or refunded / none. Maintained by the database; direct writes rejected. Change history in customer_attribute_history (attribute deposit_status).';
COMMENT ON COLUMN public.customers.deposit_interest_earned IS 'PROJECTION (v5.4.2-06): interest accrued across the customer''s deposits per deposit_events (+ any pre-patch legacy_interest_earned). Never written directly; the derivation is deposit_balance().';
COMMENT ON COLUMN public.customers.status IS 'Account lifecycle (active | inactive | final_billed | collections | closed). Since v5.4.2-06 every change requires status_reason and is logged to customer_state_events by the database; closed reopens only to active and is refused while a deposit is held / refund pending (CI-121, CI-131). customer_status_as_of() answers "what was the status on date X".';
COMMENT ON COLUMN public.payments.is_deposit IS 'True if this payment funded a security deposit. Since v5.4.2-06 the deposit itself is a public.deposits row (source_payment_id → this payment) and deposit_status must be set exactly when is_deposit (CHECK; older rows were reconciled at patch time).';
