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
-- Scope so far: section 1 (CI-010). The other items claimed for -28 (CI-089,
-- CI-091, CI-101, CI-109) are being settled one decision at a time and join
-- this file as they are.
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
-- END PATCH v5.4.2-28
-- ============================================================================

COMMIT;
