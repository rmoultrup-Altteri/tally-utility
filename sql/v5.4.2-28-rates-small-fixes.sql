-- ============================================================================
-- PATCH v5.4.2-28 — rates small fixes (draft r1, in progress)
-- ============================================================================
-- Authority:   the rates stream's first patch (HANDOFF.md board, claimed
--              2026-11-02). Spec: application/invariant-parity-measurement-
--              2026-10-13.md, the CI-010 row ("customer_is_state_agency_as_of
--              still hardcodes AT TIME ZONE 'America/Chicago' ... Fix: call
--              premise_time_zone_as_of") and -16's comment on that function
--              ("the replacement for the America/Chicago constant").
--              Ryan, 2026-11-02 (DECISION-LOG, option 1): the bill's premise
--              decides the zone; a consolidated parent reads its children's
--              premises, which must agree, or the check refuses.
--
--              Ryan, 2026-11-02 (DECISION-LOG, option 1): rider dependencies
--              are dated in place, the rate_schedule_items pattern.
--
-- Scope so far: section 1 (CI-010), section 2 (CI-101). CI-109 (rounding) is
-- still being settled. CI-091 (the meter test fee) left -28 for its own patch
-- after the dated history (Ryan, 2026-11-02); CI-089 needs no SQL (nothing
-- in the schema names a prompt-pay discount; K-06 drops the element).
--
-- ----------------------------------------------------------------------------
-- 2. Rider dependencies dated in place (CI-101)
-- ----------------------------------------------------------------------------
--   rate_item_dependencies says "item X is computed on item Y" in a schedule;
--   the core orders the evaluation from it. It refused cycles and cross-
--   tenant links (-19) and was retired, not deleted (-21), but had no in-
--   force dates, and its retirement was transaction time only (-21 R3). It
--   joins A-1 group 2 (rate_schedule_items, franchise_fee_rules, the
--   surcharge rules): valid [effective_date, expiry_date] (inclusive, as on
--   schedule items), transaction [recorded_at, recorded_until), frozen once
--   written (enforce_bitemporal_assertion), correction = close as
--   superseded + a row naming it, retraction = close as retracted.
--
--   -21's one "retire" splits into its two meanings:
--     the dependency stopped applying on a date  close as superseded and
--                                                add the successor with that
--                                                expiry_date
--     it was entered in error                    close as retracted
--   retired_at / retired_by / retired_reason are dropped; closed_by and
--   changed_by are the session's user, stamped (as -21 r2 stamped
--   retired_by), never a caller-chosen id.
--
--   One open row per (schedule, dependent, base) per valid day (exclusion).
--   The cycle check reads the schedule's open rows whose valid range
--   overlaps the new row's. CONSERVATIVE, stated: it can refuse links that
--   never apply on one day together (A on B through March, B on A from
--   April, with a third link spanning both); it never admits a real cycle,
--   since every link of a cycle on day D overlaps the new row at D.
--   Read through rate_item_dependencies_as_of(schedule, day, recorded_at).
--
-- PRECONDITION for section 2: rate_item_dependencies is empty (it is in
--   every database built from tu.sql). The first run refuses a table with
--   rows rather than guess their dates; a re-run (retired_at gone) skips the
--   check.
--
-- ----------------------------------------------------------------------------
-- 1. The state-agency check's day boundary (CI-010)
-- ----------------------------------------------------------------------------
--   A state agency pays no pipeline safety fee (16 TAC §8.201; -07). The fee
--   line check asks whether the account was a state agency "at the end of
--   the billed period", and -07 fixed that end at midnight America/Chicago:
--   a Texas constant in a live function. It now asks at midnight in the
--   bill's own zone:
--
--     invoice_time_zone_as_of(bill, date)
--       a bill with a premise:  premise_time_zone_as_of(premise, date) (-16:
--                               the places it is within; refuses, never
--                               assumes — a premise with no county in a state
--                               that is not one zone has no answer)
--       a consolidated parent:  the zones of its children's premises, void
--                               children left out; all must answer and agree.
--                               No live child, a child with no premise (a
--                               nested parent), or two zones: refused.
--     customer_is_state_agency_as_of(customer, date, zone)
--                               the zone is an argument, required; the
--                               two-argument Chicago signature is dropped.
--
--   The zone is read only for an exempting rule and a non-zero line, so a
--   0.00 line on an unplaced premise still writes.
--
--   CONSEQUENCE, stated: Texas is not one zone (its time_zone_uniform fact is
--   false), and only El Paso and Hudspeth counties are seeded with a zone
--   (-16). A non-zero fee line on a premise whose county is not loaded with
--   its time_zone fact is now refused (no_data_found) where -07 assumed
--   Central. Loading a county for a tenant's premises means loading its zone.
--
-- PRECONDITION. Applied by a superuser after v5.4.2-16 (premise_time_zone_
--   as_of). Every statement re-applies cleanly (CREATE OR REPLACE, DROP ...
--   IF EXISTS), so a second run is a no-op in effect.
-- ============================================================================

BEGIN;

-- 1.1 The bill's zone ---------------------------------------------------------
CREATE OR REPLACE FUNCTION public.invoice_time_zone_as_of(p_invoice_id uuid, p_on date) RETURNS text
    LANGUAGE plpgsql STABLE
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_inv      public.invoices%ROWTYPE;
    v_children integer;
    v_orphan   text;
    v_zones    text[];
BEGIN
    IF p_invoice_id IS NULL OR p_on IS NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = 'invoice_time_zone_as_of: p_invoice_id and p_on are required; never default to today (v5.4.2-28)',
            ERRCODE = 'null_value_not_allowed';
    END IF;
    SELECT * INTO v_inv FROM public.invoices i WHERE i.id = p_invoice_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING
            MESSAGE = format('invoice_time_zone_as_of: invoice %s is not visible in this tenant (v5.4.2-28)', p_invoice_id),
            ERRCODE = 'no_data_found';
    END IF;
    IF v_inv.location_id IS NOT NULL THEN
        RETURN public.premise_time_zone_as_of(v_inv.location_id, p_on);
    END IF;
    -- A consolidated parent (invoices_check: no premise only when
    -- consolidated): its live children's premises decide, and must agree.
    SELECT count(*), string_agg(c.invoice_number, ', ') FILTER (WHERE c.location_id IS NULL)
      INTO v_children, v_orphan
      FROM public.invoices c
     WHERE c.parent_invoice_id = v_inv.id AND c.tenant_id = v_inv.tenant_id AND c.status <> 'void';
    IF v_children = 0 THEN
        RAISE EXCEPTION USING
            MESSAGE = format('invoice %s on %s: a consolidated invoice that has no live child invoice has no premise to read a time zone from; the lookup refuses rather than assume one (v5.4.2-28)', v_inv.invoice_number, p_on),
            ERRCODE = 'no_data_found',
            HINT = 'Attach the per-location child invoices before writing a line that needs the time zone.';
    END IF;
    IF v_orphan IS NOT NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('invoice %s on %s: its child invoice %s names no premise (a consolidated invoice under a consolidated invoice); the lookup refuses (v5.4.2-28)', v_inv.invoice_number, p_on, v_orphan),
            ERRCODE = 'no_data_found';
    END IF;
    SELECT array_agg(DISTINCT public.premise_time_zone_as_of(c.location_id, p_on))
      INTO v_zones
      FROM public.invoices c
     WHERE c.parent_invoice_id = v_inv.id AND c.tenant_id = v_inv.tenant_id AND c.status <> 'void';
    IF cardinality(v_zones) > 1 THEN
        RAISE EXCEPTION USING
            MESSAGE = format('invoice %s on %s: its child invoices'' premises span more than one time zone (%s); the lookup refuses rather than choose (v5.4.2-28)', v_inv.invoice_number, p_on, array_to_string(v_zones, ', ')),
            ERRCODE = 'cardinality_violation',
            HINT = 'Bill the premises of each zone on their own consolidated invoice, or correct the premise membership that is wrong.';
    END IF;
    RETURN v_zones[1];
END;
$$;
REVOKE ALL ON FUNCTION public.invoice_time_zone_as_of(uuid, date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.invoice_time_zone_as_of(uuid, date) TO tally_app, tally_core;
COMMENT ON FUNCTION public.invoice_time_zone_as_of(uuid, date) IS
    'v5.4.2-28 (CI-010; Ryan 2026-11-02, option 1). The IANA time zone that sets a bill''s day boundary on a date: its premise''s (premise_time_zone_as_of); for a consolidated parent, the one zone all its live (non-void) children''s premises share. Refuses — never assumes — when a premise has no answerable zone, the parent has no live child, a child names no premise, or the children span two zones. Invoker rights: RLS applies.';

-- 1.2 The state-agency reading takes the zone ---------------------------------
DROP FUNCTION IF EXISTS public.customer_is_state_agency_as_of(uuid, date);
CREATE OR REPLACE FUNCTION public.customer_is_state_agency_as_of(p_customer_id uuid, p_on date, p_time_zone text) RETURNS boolean
    LANGUAGE plpgsql STABLE
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v text;
BEGIN
    IF p_on IS NULL THEN
        RAISE EXCEPTION 'customer_is_state_agency_as_of: p_on is required (the end of the billed period); never default to today';
    END IF;
    IF p_time_zone IS NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = 'customer_is_state_agency_as_of: a time zone is required (the bill''s: invoice_time_zone_as_of); never assume one (v5.4.2-28)',
            ERRCODE = 'null_value_not_allowed';
    END IF;
    -- An unknown zone name raises invalid_parameter_value here.
    v := public.customer_attribute_as_of(p_customer_id, 'is_state_agency', ((p_on + 1)::timestamp AT TIME ZONE p_time_zone));
    IF v IS NULL THEN
        -- the period predates the account's recorded history: the earliest recorded value is the best knowledge there is
        SELECT h.new_value INTO v FROM public.customer_attribute_history h
         WHERE h.customer_id = p_customer_id AND h.attribute = 'is_state_agency'
         ORDER BY h.effective_at, h.seq LIMIT 1;
    END IF;
    IF v IS NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('customer_is_state_agency_as_of: customer %s has no is_state_agency history (not visible, or written outside the attribute logger)', p_customer_id),
            ERRCODE = 'no_data_found';
    END IF;
    RETURN v = 'true';
END;
$$;
REVOKE ALL ON FUNCTION public.customer_is_state_agency_as_of(uuid, date, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.customer_is_state_agency_as_of(uuid, date, text) TO tally_app, tally_core;
COMMENT ON FUNCTION public.customer_is_state_agency_as_of(uuid, date, text) IS
    'A-7 (v5.4.2-07), v5.4.2-28 (CI-010): was the account a state agency at the end of p_on — midnight in p_time_zone, the bill''s zone (invoice_time_zone_as_of), required — per customer_attribute_history? A date before the account''s first recorded value answers with that first value; no history at all raises. Never reads the live customers row. Invoker rights: RLS applies. The two-argument form, which fixed midnight at America/Chicago, is dropped.';

-- 1.3 The fee line check reads the bill's zone --------------------------------
CREATE OR REPLACE FUNCTION public.assert_surcharge_line(p_line public.invoice_line_items, p_recorded_at timestamp with time zone) RETURNS void
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_inv  public.invoices%ROWTYPE;
    v_rule public.regulatory_surcharge_rules%ROWTYPE;
    v_sum  numeric;
    v_tz   text;
BEGIN
    IF p_line.rate_item_id IS NULL THEN
        RETURN;
    END IF;
    SELECT * INTO v_inv FROM public.invoices i WHERE i.id = p_line.invoice_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING
            MESSAGE = format('invoice_line_items: invoice %s is not visible in this tenant', p_line.invoice_id),
            ERRCODE = 'foreign_key_violation';
    END IF;
    IF v_inv.tenant_id <> p_line.tenant_id THEN
        RAISE EXCEPTION USING MESSAGE = 'invoice_line_items: tenant_id must equal the invoice''s tenant', ERRCODE = 'check_violation';
    END IF;
    SELECT r.* INTO v_rule FROM public.regulatory_surcharge_rule_as_of(p_line.rate_item_id, v_inv.invoice_date, p_recorded_at) r;
    IF NOT FOUND THEN
        RETURN;
    END IF;
    -- v5.4.2-08 (Fable, correction/line race): hold the governing rule row
    -- FOR SHARE until this transaction ends. A concurrent correction or
    -- retraction must close this row (an UPDATE), so it WAITS for every
    -- in-flight line checked against the rule and then sees their committed
    -- lines in its orphan check (the correction path is required to run
    -- under READ COMMITTED). Under REPEATABLE READ / SERIALIZABLE a line
    -- writer whose rule was concurrently closed fails here with a
    -- serialization error instead of passing on a stale rule.
    PERFORM 1 FROM public.regulatory_surcharge_rules r WHERE r.id = v_rule.id AND r.recorded_until IS NULL FOR SHARE;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING
            MESSAGE = format('regulatory_surcharge_rules: rule %s was corrected or closed by a concurrent transaction — retry (CI-038)', v_rule.id),
            ERRCODE = 'serialization_failure';
    END IF;
    IF p_line.charge_type = 'tax' THEN
        RAISE EXCEPTION USING
            MESSAGE = format('invoice %s: line %s is a %s surcharge rider (regulatory_surcharge_rules %s), not a tax — charge_type ''tax'' rejected (CI-038)', v_inv.invoice_number, p_line.description, v_rule.surcharge_kind, v_rule.id),
            ERRCODE = 'check_violation';
    END IF;
    IF v_rule.excluded_from_tax_bases THEN
        IF p_line.is_taxable OR coalesce(p_line.taxable_amount, 0) <> 0 THEN
            RAISE EXCEPTION USING
                MESSAGE = format('invoice %s: line %s is a %s surcharge excluded from every tax base — is_taxable must be false and taxable_amount empty (CI-038 / 16 TAC §8.201; rule %s)', v_inv.invoice_number, p_line.description, v_rule.surcharge_kind, v_rule.id),
                ERRCODE = 'check_violation';
        END IF;
        IF EXISTS (SELECT 1 FROM public.invoice_line_item_bases b WHERE b.base_line_item_id = p_line.id) THEN
            RAISE EXCEPTION USING
                MESSAGE = format('invoice %s: line %s is a %s surcharge excluded from every tax base but is cited as a base by another line (CI-038 / CI-045; rule %s)', v_inv.invoice_number, p_line.description, v_rule.surcharge_kind, v_rule.id),
                ERRCODE = 'check_violation';
        END IF;
    END IF;
    -- v5.4.2-28 (CI-010): the end of the billed period is midnight in the
    -- bill's own time zone (invoice_time_zone_as_of), read only when the
    -- answer can matter (an exempting rule and a non-zero line). Nested IFs,
    -- not AND: SQL does not promise to evaluate AND left to right, and the
    -- zone lookup refuses where no zone can be read.
    IF v_rule.exempts_state_agencies AND p_line.amount <> 0 THEN
        v_tz := public.invoice_time_zone_as_of(v_inv.id, v_inv.period_end);
        IF public.customer_is_state_agency_as_of(v_inv.customer_id, v_inv.period_end, v_tz) THEN
            RAISE EXCEPTION USING
                MESSAGE = format('invoice %s: the customer was a state agency at the end of the billed period (%s, midnight %s) and is exempt from the %s surcharge — line %s must be 0.00 (CI-038; rule %s)', v_inv.invoice_number, v_inv.period_end, v_tz, v_rule.surcharge_kind, p_line.description, v_rule.id),
                ERRCODE = 'check_violation';
        END IF;
    END IF;
    IF v_rule.cap_per_service IS NOT NULL THEN
        IF p_line.meter_id IS NULL THEN
            RAISE EXCEPTION USING
                MESSAGE = format('invoice %s: line %s is a %s surcharge capped per service (%s over the cycle %s..%s) and must name its service — meter_id is required (CI-038; rule %s)', v_inv.invoice_number, p_line.description, v_rule.surcharge_kind, v_rule.cap_per_service, v_rule.cycle_start, v_rule.cycle_end, v_rule.id),
                ERRCODE = 'check_violation';
        END IF;
        -- serialise concurrent lines for one (rider, service) on the mutex row (5.0)
        INSERT INTO public.regulatory_surcharge_service_locks (tenant_id, rate_item_id, meter_id)
        VALUES (p_line.tenant_id, p_line.rate_item_id, p_line.meter_id)
        ON CONFLICT (rate_item_id, meter_id) DO UPDATE SET touched_at = clock_timestamp();
        -- Only POSITIVE amounts count toward the cap: a negative line (a
        -- correction) never lends headroom, because the invoice carrying it
        -- can be discarded or voided later (Fable HIGH-1). The path to bill
        -- again is void + rebill, which releases the voided amount.
        SELECT coalesce(sum(greatest(l.amount, 0)), 0) INTO v_sum
          FROM public.invoice_line_items l
          JOIN public.invoices i ON i.id = l.invoice_id
         WHERE l.tenant_id = p_line.tenant_id
           AND l.rate_item_id = p_line.rate_item_id
           AND l.meter_id = p_line.meter_id
           AND l.id <> p_line.id
           AND i.status <> 'void'
           AND i.invoice_date >= v_rule.cycle_start AND i.invoice_date <= v_rule.cycle_end;
        IF v_sum + p_line.amount > v_rule.cap_per_service THEN
            RAISE EXCEPTION USING
                MESSAGE = format('invoice %s: line %s would bring the %s surcharge on this service to %s for the cycle %s..%s (%s already billed on non-void invoices and drafts, positive lines only, + %s), over the cap of %s per service (CI-038 / 16 TAC §8.201; rule %s)', v_inv.invoice_number, p_line.description, v_rule.surcharge_kind, v_sum + p_line.amount, v_rule.cycle_start, v_rule.cycle_end, v_sum, p_line.amount, v_rule.cap_per_service, v_rule.id),
                ERRCODE = 'check_violation';
        END IF;
    END IF;
END;
$$;

COMMENT ON FUNCTION public.assert_surcharge_line(public.invoice_line_items, timestamp with time zone) IS
    'CI-038 (v5.4.2-07), CI-010 (v5.4.2-28): the surcharge line rules, applied when the line''s rate item has a regulatory_surcharge_rules row for the invoice''s bill date at p_recorded_at (otherwise silent). Never charge_type = ''tax''; excluded_from_tax_bases → is_taxable false, no taxable_amount, cited by no base row; exempts_state_agencies → 0.00 for a customer that was a state agency at the end of period_end in the bill''s time zone (invoice_time_zone_as_of, read only for a non-zero line; attribute history, never the live row); cap_per_service → meter_id required and the cycle''s cumulative POSITIVE amounts for (rate item, meter) over non-void invoices — drafts included, this line excluded by id then added — must not exceed the cap; the transaction first touches the (rate item, meter) row of regulatory_surcharge_service_locks. Called with now() by the line guard and by the issuance gate (current knowledge — the snapshot coordinate is the run''s record, not the judge).';

-- ============================================================================
-- 2. Rider dependencies dated in place (CI-101)
-- ============================================================================

-- 2.1 The precondition (first run only) --------------------------------------
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.columns
                WHERE table_schema = 'public' AND table_name = 'rate_item_dependencies' AND column_name = 'retired_at')
       AND EXISTS (SELECT 1 FROM public.rate_item_dependencies) THEN
        RAISE EXCEPTION USING
            MESSAGE = 'v5.4.2-28: rate_item_dependencies has rows; their in-force dates cannot be inferred — date them by hand (and settle retired rows as superseded or retracted) before applying',
            ERRCODE = 'object_not_in_prerequisite_state';
    END IF;
END $$;

-- 2.2 The shape ----------------------------------------------------------------
DROP INDEX IF EXISTS public.rate_item_dependencies_live_key;
ALTER TABLE public.rate_item_dependencies DROP CONSTRAINT IF EXISTS rate_item_dependencies_retired_pair_check;
ALTER TABLE public.rate_item_dependencies DROP CONSTRAINT IF EXISTS rate_item_dependencies_retired_reason_check;
ALTER TABLE public.rate_item_dependencies DROP COLUMN IF EXISTS retired_at;
ALTER TABLE public.rate_item_dependencies DROP COLUMN IF EXISTS retired_by;
ALTER TABLE public.rate_item_dependencies DROP COLUMN IF EXISTS retired_reason;

ALTER TABLE public.rate_item_dependencies ADD COLUMN IF NOT EXISTS effective_date date NOT NULL;
ALTER TABLE public.rate_item_dependencies ADD COLUMN IF NOT EXISTS expiry_date date;
ALTER TABLE public.rate_item_dependencies ADD COLUMN IF NOT EXISTS recorded_at timestamp with time zone DEFAULT now() NOT NULL;
ALTER TABLE public.rate_item_dependencies ADD COLUMN IF NOT EXISTS recorded_until timestamp with time zone;
ALTER TABLE public.rate_item_dependencies ADD COLUMN IF NOT EXISTS change_type text DEFAULT 'initial' NOT NULL;
ALTER TABLE public.rate_item_dependencies ADD COLUMN IF NOT EXISTS change_reason text;
ALTER TABLE public.rate_item_dependencies ADD COLUMN IF NOT EXISTS changed_by uuid;
ALTER TABLE public.rate_item_dependencies ADD COLUMN IF NOT EXISTS supersedes_id uuid;
ALTER TABLE public.rate_item_dependencies ADD COLUMN IF NOT EXISTS closed_type text;
ALTER TABLE public.rate_item_dependencies ADD COLUMN IF NOT EXISTS closed_reason text;
ALTER TABLE public.rate_item_dependencies ADD COLUMN IF NOT EXISTS closed_by uuid;

ALTER TABLE public.rate_item_dependencies DROP CONSTRAINT IF EXISTS rate_item_dependencies_change_type_check;
ALTER TABLE public.rate_item_dependencies ADD CONSTRAINT rate_item_dependencies_change_type_check
    CHECK (change_type = ANY (ARRAY['initial'::text, 'succession'::text, 'correction'::text]));
-- A reason, where one is given or required, says something (PATCH-LESSONS
-- blank-checks-whitelist-alnum).
ALTER TABLE public.rate_item_dependencies DROP CONSTRAINT IF EXISTS rate_item_dependencies_change_reason_check;
ALTER TABLE public.rate_item_dependencies ADD CONSTRAINT rate_item_dependencies_change_reason_check
    CHECK ((change_reason IS NULL OR change_reason ~ '[[:alnum:]]') AND (change_type <> 'correction' OR change_reason IS NOT NULL));
ALTER TABLE public.rate_item_dependencies DROP CONSTRAINT IF EXISTS rate_item_dependencies_supersedes_check;
ALTER TABLE public.rate_item_dependencies ADD CONSTRAINT rate_item_dependencies_supersedes_check
    CHECK ((supersedes_id IS NULL) = (change_type = 'initial'));
ALTER TABLE public.rate_item_dependencies DROP CONSTRAINT IF EXISTS rate_item_dependencies_closed_type_check;
ALTER TABLE public.rate_item_dependencies ADD CONSTRAINT rate_item_dependencies_closed_type_check
    CHECK (closed_type IS NULL OR closed_type = ANY (ARRAY['superseded'::text, 'retracted'::text]));
ALTER TABLE public.rate_item_dependencies DROP CONSTRAINT IF EXISTS rate_item_dependencies_close_consistent_check;
ALTER TABLE public.rate_item_dependencies ADD CONSTRAINT rate_item_dependencies_close_consistent_check
    CHECK (((recorded_until IS NULL) AND (closed_type IS NULL) AND (closed_reason IS NULL) AND (closed_by IS NULL))
        OR ((recorded_until IS NOT NULL) AND (closed_type IS NOT NULL) AND (closed_reason ~ '[[:alnum:]]') AND (recorded_until >= recorded_at)));
ALTER TABLE public.rate_item_dependencies DROP CONSTRAINT IF EXISTS rate_item_dependencies_valid_bracket_check;
ALTER TABLE public.rate_item_dependencies ADD CONSTRAINT rate_item_dependencies_valid_bracket_check
    CHECK (expiry_date IS NULL OR expiry_date >= effective_date);
ALTER TABLE public.rate_item_dependencies DROP CONSTRAINT IF EXISTS rate_item_dependencies_changed_by_fkey;
ALTER TABLE public.rate_item_dependencies ADD CONSTRAINT rate_item_dependencies_changed_by_fkey FOREIGN KEY (changed_by) REFERENCES public.users(id);
ALTER TABLE public.rate_item_dependencies DROP CONSTRAINT IF EXISTS rate_item_dependencies_closed_by_fkey;
ALTER TABLE public.rate_item_dependencies ADD CONSTRAINT rate_item_dependencies_closed_by_fkey FOREIGN KEY (closed_by) REFERENCES public.users(id);
ALTER TABLE public.rate_item_dependencies DROP CONSTRAINT IF EXISTS rate_item_dependencies_supersedes_id_fkey;
ALTER TABLE public.rate_item_dependencies ADD CONSTRAINT rate_item_dependencies_supersedes_id_fkey FOREIGN KEY (supersedes_id) REFERENCES public.rate_item_dependencies(id);
-- One open row per (schedule, dependent, base) per valid day (replaces -21's
-- live uniqueness).
ALTER TABLE public.rate_item_dependencies DROP CONSTRAINT IF EXISTS rate_item_dependencies_open_no_overlap_excl;
ALTER TABLE public.rate_item_dependencies ADD CONSTRAINT rate_item_dependencies_open_no_overlap_excl
    EXCLUDE USING gist (rate_schedule_id WITH =, dependent_rate_item_id WITH =, base_rate_item_id WITH =,
                        daterange(effective_date, expiry_date, '[]') WITH &&) WHERE (recorded_until IS NULL);
CREATE INDEX IF NOT EXISTS idx_rate_item_deps_open ON public.rate_item_dependencies USING btree (rate_schedule_id, dependent_rate_item_id) WHERE (recorded_until IS NULL);
CREATE INDEX IF NOT EXISTS idx_rate_item_deps_supersedes ON public.rate_item_dependencies USING btree (supersedes_id) WHERE (supersedes_id IS NOT NULL);
CREATE INDEX IF NOT EXISTS idx_rate_item_deps_changed_by ON public.rate_item_dependencies USING btree (changed_by) WHERE (changed_by IS NOT NULL);
CREATE INDEX IF NOT EXISTS idx_rate_item_deps_closed_by ON public.rate_item_dependencies USING btree (closed_by) WHERE (closed_by IS NOT NULL);

-- 2.3 The guards ---------------------------------------------------------------
-- The shared A-1 row guard first (name order: a_enforce_bitemporal_assertion
-- before a_enforce_rate_item_dependency): it refuses DELETE, a row born
-- closed or as a backfill, any in-place edit of an asserted row but its
-- close, and any change to a closed row; it stamps recorded_at and
-- recorded_until, and checks a successor's predecessor (same tenant, same
-- dependency, closed as superseded). Nothing is writable in place.
DROP TRIGGER IF EXISTS a_enforce_bitemporal_assertion ON public.rate_item_dependencies;
CREATE TRIGGER a_enforce_bitemporal_assertion BEFORE INSERT OR UPDATE OR DELETE ON public.rate_item_dependencies
    FOR EACH ROW EXECUTE FUNCTION public.enforce_bitemporal_assertion('', 'rate_schedule_id,dependent_rate_item_id,base_rate_item_id');
ALTER TABLE public.rate_item_dependencies ENABLE ALWAYS TRIGGER a_enforce_bitemporal_assertion;
DROP TRIGGER IF EXISTS enforce_superseded_has_successor ON public.rate_item_dependencies;
CREATE CONSTRAINT TRIGGER enforce_superseded_has_successor AFTER UPDATE ON public.rate_item_dependencies
    DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.enforce_superseded_has_successor('rate_schedule_id,dependent_rate_item_id,base_rate_item_id');
ALTER TABLE public.rate_item_dependencies ENABLE ALWAYS TRIGGER enforce_superseded_has_successor;

CREATE OR REPLACE FUNCTION public.enforce_rate_item_dependency() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public', 'pg_temp'
    AS $fn$
DECLARE
    v_bad    text;
    v_cycle  boolean;
BEGIN
    IF TG_OP = 'UPDATE' THEN
        -- The row guard has already refused every change but a close. A close
        -- names its closer as the database knows the session's user (-21 r2:
        -- never a caller-chosen id) and takes the schedule header, as an
        -- insert does (one lock order); removing a link cannot close a cycle.
        IF OLD.recorded_until IS NULL AND NEW.recorded_until IS NOT NULL THEN
            NEW.closed_by := NULLIF(pg_catalog.current_setting('app.user_id', true), '')::uuid;
            UPDATE public.rate_schedules s SET updated_at = now() WHERE s.id = NEW.rate_schedule_id;
        END IF;
        RETURN NEW;
    END IF;

    NEW.changed_by := NULLIF(pg_catalog.current_setting('app.user_id', true), '')::uuid;

    -- The bracket, before the walk builds a range from it (a reversed one
    -- would fail there with a bare range error; the CHECK answers later).
    IF NEW.expiry_date < NEW.effective_date THEN
        RAISE EXCEPTION USING
            MESSAGE = format('rate_item_dependencies: expiry_date %s is before effective_date %s (rate_item_dependencies_valid_bracket_check, v5.4.2-28)', NEW.expiry_date, NEW.effective_date),
            ERRCODE = 'check_violation';
    END IF;

    -- Same tenant: the schedule and both items. The foreign keys are single-
    -- column and bypass row-level security, so the check is positive: each
    -- must be VISIBLE to the writer and of this row's tenant (another
    -- tenant's row is invisible to tally_app, and a superuser sees its
    -- tenant_id).
    SELECT string_agg(x.what, ', ') INTO v_bad FROM (
        SELECT 'rate schedule ' || NEW.rate_schedule_id AS what
         WHERE NOT EXISTS (SELECT 1 FROM public.rate_schedules s WHERE s.id = NEW.rate_schedule_id AND s.tenant_id = NEW.tenant_id)
        UNION ALL
        SELECT 'rate item ' || v.item_id
          FROM unnest(ARRAY[NEW.dependent_rate_item_id, NEW.base_rate_item_id]) AS v(item_id)
         WHERE NOT EXISTS (SELECT 1 FROM public.rate_items i WHERE i.id = v.item_id AND i.tenant_id = NEW.tenant_id)
    ) x;
    IF v_bad IS NOT NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('rate_item_dependencies: %s is not a row of this dependency''s tenant (CI-101 / CI-116, v5.4.2-19)', v_bad),
            ERRCODE = 'foreign_key_violation';
    END IF;

    -- Lock order (AC, -19 r2/r3): a transaction that writes dependencies
    -- takes the schedule headers first, in schedule-id order (this bump, or
    -- assert_reference_version), and only then writes dependency rows; a
    -- close locks the row before this bump, so a transaction holding the
    -- header that then closes a row, against one closing that row, can
    -- deadlock. PostgreSQL cancels one; the caller retries the whole
    -- transaction on deadlock_detected or serialization_failure. A cancelled
    -- participant never lets a cycle through.
    -- Row-version mutex on the schedule header: every writer of the
    -- schedule's dependencies bumps the same row, so two halves of a cycle
    -- written at once serialise (READ COMMITTED: the second waits and its
    -- check below sees the first; REPEATABLE READ / SERIALIZABLE: the second
    -- fails with serialization_failure). The header guard admits an
    -- updated_at-only write.
    UPDATE public.rate_schedules s SET updated_at = now() WHERE s.id = NEW.rate_schedule_id;

    -- A dependency dependent -> base closes a cycle when base already reaches
    -- dependent through the schedule's other OPEN dependencies whose valid
    -- range overlaps this one's (v5.4.2-28). Conservative: the links found
    -- each overlap this row but need not share one day with each other; a
    -- real cycle is never missed. A reachable set, not paths (-19 r2: UNION
    -- drops an item already reached, so the walk is linear).
    WITH RECURSIVE reach(item_id) AS (
        SELECT NEW.base_rate_item_id
        UNION
        SELECT d.base_rate_item_id
          FROM reach r
          JOIN public.rate_item_dependencies d
            ON d.dependent_rate_item_id = r.item_id
           AND d.rate_schedule_id = NEW.rate_schedule_id
           AND d.recorded_until IS NULL
           AND d.id <> NEW.id
           AND daterange(d.effective_date, d.expiry_date, '[]') && daterange(NEW.effective_date, NEW.expiry_date, '[]')
    )
    SELECT EXISTS (SELECT 1 FROM reach WHERE item_id = NEW.dependent_rate_item_id) INTO v_cycle;
    IF v_cycle THEN
        RAISE EXCEPTION USING
            MESSAGE = format('rate_item_dependencies: rate item %s depending on %s from %s to %s closes a cycle in rate schedule %s among the dependencies in force over those dates — rider composition must be a DAG (CI-101, v5.4.2-19, -28)',
                             NEW.dependent_rate_item_id, NEW.base_rate_item_id, NEW.effective_date, coalesce(NEW.expiry_date::text, 'open'), NEW.rate_schedule_id),
            ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$fn$;
COMMENT ON FUNCTION public.enforce_rate_item_dependency() IS
    'v5.4.2-19 (CI-101), -21 (CI-014), -28 (CI-101 dated). BEFORE INSERT OR UPDATE on rate_item_dependencies, after the shared A-1 row guard (enforce_bitemporal_assertion), which leaves an UPDATE only the close. INSERT: changed_by is the session''s user; refuses a schedule or item of another tenant, and a dependency that closes a cycle among the schedule''s open dependencies whose valid range overlaps its own (any length; conservative across dates). UPDATE (a close): closed_by is the session''s user. Both serialise on the schedule header (a row-version mutex: rate_schedules.updated_at), so concurrent halves of a cycle cannot both pass at any isolation level.';
DROP TRIGGER IF EXISTS a_enforce_rate_item_dependency ON public.rate_item_dependencies;
CREATE TRIGGER a_enforce_rate_item_dependency BEFORE INSERT OR UPDATE ON public.rate_item_dependencies
    FOR EACH ROW EXECUTE FUNCTION public.enforce_rate_item_dependency();
ALTER TABLE public.rate_item_dependencies ENABLE ALWAYS TRIGGER a_enforce_rate_item_dependency;

-- 2.4 The read -----------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rate_item_dependencies_as_of(p_rate_schedule_id uuid, p_valid_on date, p_recorded_at timestamp with time zone)
    RETURNS SETOF public.rate_item_dependencies
    LANGUAGE plpgsql STABLE
    SET search_path = public, pg_temp
    AS $$
BEGIN
    IF p_rate_schedule_id IS NULL OR p_valid_on IS NULL OR p_recorded_at IS NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = 'rate_item_dependencies_as_of: the schedule, the day and the recorded-at instant are all required — pass the bill''s day and the run''s recorded_at; never default to now() (CI-001 / CI-101, v5.4.2-28)',
            ERRCODE = 'null_value_not_allowed';
    END IF;
    RETURN QUERY
    SELECT d.* FROM public.rate_item_dependencies d
     WHERE d.rate_schedule_id = p_rate_schedule_id
       AND d.recorded_at <= p_recorded_at AND (d.recorded_until IS NULL OR d.recorded_until > p_recorded_at)
       AND d.effective_date <= p_valid_on AND (d.expiry_date IS NULL OR d.expiry_date >= p_valid_on)
     ORDER BY d.dependent_rate_item_id, d.base_rate_item_id;
END;
$$;
REVOKE ALL ON FUNCTION public.rate_item_dependencies_as_of(uuid, date, timestamp with time zone) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rate_item_dependencies_as_of(uuid, date, timestamp with time zone) TO tally_app, tally_core;
COMMENT ON FUNCTION public.rate_item_dependencies_as_of(uuid, date, timestamp with time zone) IS
    'v5.4.2-28 (CI-101). A schedule''s rider dependencies in force on p_valid_on, as recorded at p_recorded_at: the rows open at that instant whose valid range [effective_date, expiry_date] contains the day. All three arguments REQUIRED; NULL raises; no live fallback. Invoker rights: RLS applies.';

COMMENT ON TABLE public.rate_item_dependencies IS
    'Rider composition: in rate schedule S, rate item dependent_rate_item_id is computed on base_rate_item_id; the core orders the evaluation (a DAG: cycles refused, -19). Bi-temporal in place (A-1 group 2, v5.4.2-28; the rate_schedule_items pattern): valid [effective_date, expiry_date] inclusive, transaction [recorded_at, recorded_until). Frozen once written; nothing is writable in place. The dependency stopped applying on a date = close as superseded + a successor (supersedes_id) with that expiry_date; entered in error = close as retracted. One open row per (schedule, dependent, base) per valid day. changed_by and closed_by are the session''s user, stamped. Never deleted (-21). Read through rate_item_dependencies_as_of(schedule, day, recorded_at).';

-- 2.5 The wave-1 guard invariant learns the two A-1 triggers ------------------
CREATE OR REPLACE FUNCTION public.assert_wave1_guard_invariants() RETURNS void
    LANGUAGE plpgsql
    STABLE
    SET search_path TO 'public', 'pg_temp'
    AS $fn$
DECLARE
    v_bad text;
    -- PostgreSQL 16's rendering by pg_get_triggerdef: re-capture on a major
    -- upgrade, after checking each trigger is unchanged.
    c_triggers CONSTANT text[] := ARRAY[
        'CREATE CONSTRAINT TRIGGER enforce_invoice_line_arithmetic AFTER INSERT OR UPDATE ON public.invoices DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION enforce_invoice_line_arithmetic()',
        'CREATE TRIGGER a_enforce_adhoc_charge_born_unvoided BEFORE INSERT ON public.adhoc_charges FOR EACH ROW EXECUTE FUNCTION enforce_adhoc_charge_born_unvoided()',
        'CREATE TRIGGER a_enforce_user_cognito_sub_write_once BEFORE UPDATE OF cognito_sub ON public.users FOR EACH ROW EXECUTE FUNCTION enforce_user_cognito_sub_write_once()',
        'CREATE TRIGGER a_enforce_user_binding_by_supervisor BEFORE INSERT OR UPDATE OF cognito_sub, is_active, role ON public.users FOR EACH ROW EXECUTE FUNCTION enforce_user_binding_by_supervisor()',
        'CREATE TRIGGER a_enforce_rate_item_dependency BEFORE INSERT OR UPDATE ON public.rate_item_dependencies FOR EACH ROW EXECUTE FUNCTION enforce_rate_item_dependency()',
        -- v5.4.2-28: the dependency table's A-1 guards.
        'CREATE TRIGGER a_enforce_bitemporal_assertion BEFORE INSERT OR DELETE OR UPDATE ON public.rate_item_dependencies FOR EACH ROW EXECUTE FUNCTION enforce_bitemporal_assertion('''', ''rate_schedule_id,dependent_rate_item_id,base_rate_item_id'')',
        'CREATE CONSTRAINT TRIGGER enforce_superseded_has_successor AFTER UPDATE ON public.rate_item_dependencies DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION enforce_superseded_has_successor(''rate_schedule_id,dependent_rate_item_id,base_rate_item_id'')'];
BEGIN
    SELECT string_agg(d, E'\n  ' ORDER BY d) INTO v_bad
      FROM unnest(c_triggers) d
     WHERE NOT EXISTS (SELECT 1 FROM pg_catalog.pg_trigger g
                        WHERE NOT g.tgisinternal AND g.tgenabled = 'A'
                          AND pg_catalog.pg_get_triggerdef(g.oid) = d);
    IF v_bad IS NOT NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format(E'a wave-1 guard is missing, changed, or not ENABLE ALWAYS (v5.4.2-21, -28):\n  %s', v_bad),
            ERRCODE = 'invalid_grant_operation';
    END IF;
END;
$fn$;
COMMENT ON FUNCTION public.assert_wave1_guard_invariants() IS
    'v5.4.2-21 r2, v5.4.2-28. Raises unless the guards of v5.4.2-21 outside retention — the bill-line arithmetic check, the born-unvoided charge guard, the Cognito write-once and supervisor guards, and the rate-dependency guard — and the rate-dependency table''s two A-1 guards (the row guard and the superseded-has-successor check, -28) exist exactly as defined (PostgreSQL 16''s rendering) and ENABLE ALWAYS. Checks the triggers, not the bodies of their functions. Run in the patch tail and in CI.';
REVOKE ALL ON FUNCTION public.assert_wave1_guard_invariants() FROM PUBLIC, tally_app, tally_core;

DO $$ BEGIN
    PERFORM public.assert_wave1_guard_invariants();
    PERFORM public.assert_no_hard_delete_invariants();
END $$;

-- ============================================================================
-- END PATCH v5.4.2-28
-- ============================================================================

COMMIT;
