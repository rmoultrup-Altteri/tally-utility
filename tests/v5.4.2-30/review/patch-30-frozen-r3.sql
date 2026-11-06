-- ============================================================================
-- PATCH v5.4.2-30 — tax rows keyed to places, and the taxability fixes
--                    (r3, 2026-11-06; r1 and r2 frozen and reviewed 2026-11-06)
-- ============================================================================
-- Authority:   Kyle 2026-10-14 (GBM application/kyle-decisions-2026-10-14-
--              tax-jurisdictions-and-gas-cost.md, answers 1, 2, 5); Kyle
--              2026-11-03 (scenario batch 1, answer 4: city sales tax on the
--              lines the utility flags taxable); Kyle 2026-11-05 (scenario
--              batch 2, answers 3a: a per-charge late-penalty base, and 20: a
--              state agency's documented basis); Kyle 2026-09-02 (the
--              customer-type size-tier defect); Ryan 2026-09-30 (a value the
--              utility answers for stays its own row); Ryan 2026-11-02 (AC-45:
--              rates in percent). Board claim -30 (rates stream).
-- Design:      application/rates-build-2026-11-05/tax-design.md (2.1–2.8);
--              round 2: v5.4.2-30-r2-plan.md (the round-1 findings);
--              round 3: v5.4.2-30-r3-plan.md (the round-2 findings);
--              triage of the open points: tax-triage.md; sources:
--              tax-inventory.md.
-- Invariants:  CI-045 (each tax on its own base, in its order: the levy rows
--              this needs); the tax half of CI-001 and CI-004 (tax rules and
--              the tax-axis places dated and readable as known at a past
--              instant); CI-046 (exemptions per service type); CI-038 (the
--              pipeline safety fee outside the penalty base; the state-agency
--              basis).
--
-- What it does
--   1. tax_kinds: the kinds of tax a place may levy, and which kinds of place
--      levy each (platform-held). Seeded: sales_tax.
--   2. tax_levies: the utility's own tax rows, on the rule-terms template
--      (role tariff), keyed by the place's kind and code within the row's
--      state and by the tax kind. Its document (tax_levy v1): the rate in
--      percent, the stacking position, the levies it is charged on top of
--      (named; empty means none: no tax on tax unless stated), the source
--      kind and citation, and whether it reaches residential gas. Never
--      edited, closed once (the template's rules).
--   3. tax_levy_as_of(): the row in force on a date as known at an instant;
--      tax_levy_reference_gaps(): where a utility's sales-tax levy differs
--      from the published rate (the Comptroller's, a place fact). The
--      published rate never bills; the utility's row does.
--   4. rate_item_versions: is_taxable_default, is_a_tax and
--      applies_to_customer_types lose their defaults (applies_to_customer_
--      types must name known types); in_late_penalty_base is new, required,
--      no default. A tax, or a rider excluded from tax bases, is never in
--      the late-penalty base (both orders of writing).
--   5. Exemptions name their services; should_charge_tax() refuses a NULL
--      service type.
--   6. The published sales_tax_rate is percent (0 to 100).
--   7. premise_places_as_of() gains a recorded-at instant: the premise's
--      state, memberships and places as known then. The premise's state is
--      recorded on change by the database (service_location_state_history,
--      r2). The three-argument form reads at now().
--   8. customers.state_agency_basis: required while is_state_agency is true,
--      logged in the attribute history.
--   9. A place is never closed from under a levy: checked at commit, so a
--      close and its successor row may come in one transaction (r2).
--
-- Rules (each refused case is a battery check, tests/v5.4.2-30/battery-30.sql)
--   * A levy names a kind of place that levies its tax (tax_kinds.place_
--     kinds), and a place of that kind and code in the row's state is in
--     force over the whole of the row's dates (its successive rows may cover
--     them together: a levy keyed by code survives the place's succession).
--     -16's convention: a successor row of the same kind, state and code is
--     the same place. A place is closed only while its levies stay covered
--     (section 2b), so a levy never outlives its place, and a code reused
--     later inherits no levy.
--   * The rate carries at most four decimals (K-06); 0 to 100.
--   * computed_on names only known tax kinds, never the levy's own.
--   * The citation has a letter or a digit.
--   * A utility writes and reads its own levies only.
--   * Every lookup requires every argument (no default, NULL raises).
--
-- KNOWN LIMITS
--   L1. The Comptroller's quarterly files are staged and approved in the
--       application: a proposed rate is not a schema row; the approval is the
--       insert of the utility's levy, which records its approver
--       (created_by). tax_levy_reference_gaps() reports a published change
--       nobody approved.
--   L2. The late-penalty guard, like -07's taxability guard, reads the other
--       table's committed rows: a version and a surcharge rule written at
--       once in two sessions can each pass. Platform setup writes rate
--       items; this is -07's known shape, unchanged.
--   L3. No place below the state is loaded with a sales-tax rate yet: the
--       cities, transit authorities and districts are a later data patch
--       (board: -32), with the published rates as reference facts.
--   L4. The old customer-level exempt columns stay (read by no tax path); their
--       retirement needs compliance_statistics rebuilt under -11's checks
--       and is its own item.
--   L5. The bill line naming its levy and place, the no-tax-on-tax check on
--       a line's bases, an exempt $0.00 line keeping its would-be base, and
--       the defaults on one-off charges and bill lines are the money
--       stream's (board note).
--   L6. An instant before a premise's state was recorded cannot be read
--       (refused). A bill from before go-live is rebilled from its own
--       legacy record, with a supervisor's approval (Kyle 2026-11-05,
--       batch 2 answer 11).
--   L7. Two writers on one key: the template stamps created_at and
--       closed_at with now() (transaction start), as do places and
--       memberships (-16), so a successor recorded by a transaction that
--       began before its predecessor's close or void can make a read at an
--       instant between the two refuse for those seconds ("2 rows" of a levy;
--       two places of one exclusive group, r3). A read refuses, never
--       mis-answers; the change is the template's (board, unassigned). The
--       premise's state history is not in L7: its recorder refuses the
--       overlapping writer (r3).
--
-- Preconditions (a real database): no rate item version yet (each would need
-- its penalty-base answer decided, not defaulted); no exemption without
-- service types, or naming one that is not a service; no state agency without
-- a basis; no sales_tax_rate fact while the kind is still a fraction. Each
-- refuses and counts the rows. On a re-apply each is skipped once its change
-- is in place.
-- ============================================================================

BEGIN;

DO $pre30$
DECLARE
    v integer;
BEGIN
    IF current_setting('transaction_isolation') <> 'read committed' THEN
        RAISE EXCEPTION 'v5.4.2-30: run under READ COMMITTED (got %)', current_setting('transaction_isolation');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                    WHERE table_schema = 'public' AND table_name = 'rate_item_versions' AND column_name = 'in_late_penalty_base') THEN
        SELECT count(*) INTO v FROM public.rate_item_versions;
        IF v > 0 THEN
            RAISE EXCEPTION 'v5.4.2-30 precondition: % rate item version(s) exist; each needs its late-penalty base decided (Kyle 2026-11-05, 3a), not defaulted', v;
        END IF;
    END IF;
    SELECT count(*) INTO v FROM public.customer_tax_exemptions
     WHERE service_types IS NULL OR cardinality(service_types) = 0 OR array_position(service_types, NULL) IS NOT NULL
        OR NOT (service_types <@ ARRAY['water'::text, 'sewer'::text, 'electric'::text, 'gas'::text, 'stormwater'::text, 'trash'::text, 'reclaimed_water'::text]);
    IF v > 0 THEN
        RAISE EXCEPTION 'v5.4.2-30 precondition: % exemption(s) name no service type, or one that is not a service; each must name the services it covers (Kyle 2026-10-14, 5)', v;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                    WHERE table_schema = 'public' AND table_name = 'customers' AND column_name = 'state_agency_basis') THEN
        SELECT count(*) INTO v FROM public.customers WHERE is_state_agency;
        IF v > 0 THEN
            RAISE EXCEPTION 'v5.4.2-30 precondition: % state agenc(ies) have no documented basis (Kyle 2026-11-05, 20)', v;
        END IF;
    END IF;
END
$pre30$;

-- ----------------------------------------------------------------------------
-- 0. A row's end as known at an instant
-- ----------------------------------------------------------------------------
-- A close sets a row's end once and stamps when (closed_at). Before that
-- instant the row was open: its end was not yet known.
CREATE OR REPLACE FUNCTION public.end_as_known(p_end date, p_closed_at timestamp with time zone, p_at timestamp with time zone) RETURNS date
    LANGUAGE sql IMMUTABLE
    SET search_path = public, pg_temp
    AS $$
    SELECT CASE WHEN p_closed_at IS NOT NULL AND p_closed_at > p_at THEN NULL ELSE p_end END
$$;
COMMENT ON FUNCTION public.end_as_known(date, timestamp with time zone, timestamp with time zone) IS
    'v5.4.2-30. A closed-once row''s end date as known at p_at: NULL (open) when its close was stamped after p_at, else its end. A row born with an end and never closed knew its end from the start.';

-- ----------------------------------------------------------------------------
-- 1. Tax kinds
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.tax_kinds (
    tax_kind     text NOT NULL,
    place_kinds  text[] NOT NULL,
    description  text NOT NULL,
    source_note  text NOT NULL,
    created_at   timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT tax_kinds_pkey PRIMARY KEY (tax_kind),
    CONSTRAINT tax_kinds_code_check CHECK ((tax_kind ~ '^[a-z][a-z0-9_]*$'::text)),
    CONSTRAINT tax_kinds_places_check CHECK (((cardinality(place_kinds) > 0) AND (array_position(place_kinds, NULL) IS NULL))),
    CONSTRAINT tax_kinds_text_check CHECK (((description ~ '[[:alnum:]]'::text) AND (source_note ~ '[[:alnum:]]'::text)))
);
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.tax_kinds FROM tally_app, tally_core;
GRANT SELECT ON public.tax_kinds TO tally_app, tally_core;
COMMENT ON TABLE public.tax_kinds IS
    'v5.4.2-30 (Kyle 2026-10-14 answer 1: a jurisdiction is a place; its taxes hang off it as dated rows). The kinds of tax a place may levy on a bill, and the kinds of place that levy each (place_kinds: every one a place_kinds code). Platform-held, written by reviewed migration; tally_app reads.';
INSERT INTO public.tax_kinds (tax_kind, place_kinds, description, source_note)
SELECT 'sales_tax', ARRAY['state', 'county', 'municipality', 'transit_authority', 'special_purpose_district'],
       'Sales and use tax on the sale of the service, levied by the state and by local taxing jurisdictions.',
       'Tex. Tax Code 151.051 (state), 321.101 (city), 323.101 (county), Transportation Code 451.401 (transit), Tax Code 321.106 / Local Government Code ch. 344, 363 (districts); Comptroller local sales tax jurisdiction list'
 WHERE NOT EXISTS (SELECT 1 FROM public.tax_kinds WHERE tax_kind = 'sales_tax');
DO $tk$
BEGIN
    IF EXISTS (SELECT 1 FROM public.tax_kinds t, unnest(t.place_kinds) k WHERE NOT EXISTS (SELECT 1 FROM public.place_kinds p WHERE p.kind_code = k)) THEN
        RAISE EXCEPTION 'v5.4.2-30: a tax kind names a kind of place that does not exist';
    END IF;
END
$tk$;

-- ----------------------------------------------------------------------------
-- 2. The utility's tax levies
-- ----------------------------------------------------------------------------
DO $schema30$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.rule_term_schemas WHERE terms_kind = 'tax_levy' AND terms_version = 1) THEN
    INSERT INTO public.rule_term_schemas (terms_kind, terms_version, rule_role, json_schema, introduced_on, description, source_note)
    VALUES ('tax_levy', 1, 'tariff', $schema${
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://tally-utility/law/tax/tax_levy.v1.schema.json",
  "title": "Tax levy, version 1",
  "description": "A utility's own record of one tax a place levies on its bills: the rate in percent, where it stands in the stack, the levies it is charged on top of (none unless named), its source and citation, and whether it reaches residential gas (Kyle 2026-10-14 answers 1 and 2; 2026-11-03 answer 4).",
  "type": "object",
  "additionalProperties": false,
  "required": [
    "rate_percent",
    "stacking_position",
    "computed_on",
    "source_kind",
    "citation",
    "reaches_residential"
  ],
  "properties": {
    "rate_percent": {
      "description": "Percent, at most four decimals (checked by the table's insert check); 8.25 means 8.25 percent.",
      "type": "number",
      "minimum": 0,
      "maximum": 100
    },
    "stacking_position": {
      "description": "Order in the bill's tax stack, 1 first.",
      "type": "integer",
      "minimum": 1,
      "maximum": 99
    },
    "computed_on": {
      "description": "The tax kinds this levy is charged on top of (tax on tax). Empty: none. Texas: none unless the jurisdiction declares it.",
      "type": "array",
      "uniqueItems": true,
      "items": {
        "type": "string",
        "pattern": "^[a-z][a-z0-9_]*$"
      }
    },
    "source_kind": {
      "type": "string",
      "enum": [
        "statute",
        "ordinance",
        "tariff"
      ]
    },
    "citation": {
      "type": "string",
      "pattern": "[A-Za-z0-9]"
    },
    "reaches_residential": {
      "description": "Whether the levy reaches residential gas (Tax Code 151.317; a city's own election, 321.105).",
      "type": "boolean"
    }
  }
}$schema$::jsonb, DATE '2026-11-05',
            'Tax levy: one tax a place levies on a utility''s bills, as the utility records and answers for it',
            'application/rates-build-2026-11-05/tax-design.md 2.1, 2.8 (v5.4.2-30)');
    END IF;
END
$schema30$;

CREATE TABLE IF NOT EXISTS public.tax_levies (
    id               uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id        uuid NOT NULL,
    state_code       text NOT NULL,
    service_type     text NOT NULL,
    system_kind      text NOT NULL,
    place_kind       text NOT NULL,
    place_code       text NOT NULL,
    tax_kind         text NOT NULL,
    effective_from   date NOT NULL,
    effective_to     date,
    tariff_reference text NOT NULL,
    terms_kind       text NOT NULL,
    terms_version    integer NOT NULL,
    terms_source     text NOT NULL,
    terms            jsonb NOT NULL,
    created_at       timestamp with time zone DEFAULT now() NOT NULL,
    recorded_txid    bigint,
    created_by       uuid,
    closed_at        timestamp with time zone,
    closed_by        uuid,
    CONSTRAINT tax_levies_pkey PRIMARY KEY (id),
    CONSTRAINT tax_levies_place_kind_fkey FOREIGN KEY (place_kind) REFERENCES public.place_kinds (kind_code),
    CONSTRAINT tax_levies_tax_kind_fkey FOREIGN KEY (tax_kind) REFERENCES public.tax_kinds (tax_kind)
);

CREATE OR REPLACE FUNCTION public.tax_levy_insert_check(p_row jsonb) RETURNS void
    LANGUAGE plpgsql VOLATILE
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_kinds  text[];
    v_cover  datemultirange;
    v_range  daterange := daterange((p_row ->> 'effective_from')::date, (p_row ->> 'effective_to')::date, '[)');
    v_rate   numeric := (p_row -> 'terms' ->> 'rate_percent')::numeric;
    v_on     text;
    v_place  uuid;
    v_locked uuid[] := ARRAY[]::uuid[];
    v_now    uuid[];
BEGIN
    IF NOT public.is_platform_admin() AND (p_row ->> 'tenant_id')::uuid IS DISTINCT FROM public.get_user_tenant_id()
       AND NOT coalesce((SELECT r.rolsuper OR r.rolbypassrls FROM pg_roles r WHERE r.rolname = current_user), false) THEN
        RAISE EXCEPTION USING
            MESSAGE = 'new row violates row-level security policy for table "tax_levies": a utility writes its own levies only (v5.4.2-30)',
            ERRCODE = 'insufficient_privilege';
    END IF;
    SELECT t.place_kinds INTO v_kinds FROM public.tax_kinds t WHERE t.tax_kind = p_row ->> 'tax_kind';
    IF NOT coalesce(p_row ->> 'place_kind' = ANY (v_kinds), false) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('tax levy: a %s does not levy %s (tax_kinds: %s; v5.4.2-30)', p_row ->> 'place_kind', p_row ->> 'tax_kind', coalesce(array_to_string(v_kinds, ', '), 'no such tax kind')),
            ERRCODE = 'check_violation';
    END IF;
    -- The place, by kind and code in the row's state: its rows together
    -- cover the levy's dates (a successor row of the same place continues it).
    -- Each row's lock is taken shared first, so a close of it waits for this
    -- levy's commit and then sees it (section 2b); the rows are then re-read
    -- under READ COMMITTED (a close committed meanwhile is seen).
    PERFORM public.assert_place_read_committed('recording a tax levy');
    FOR v_place IN SELECT p.id FROM public.places p
                    WHERE p.kind_code = p_row ->> 'place_kind' AND p.state_code = p_row ->> 'state_code' AND p.place_code = p_row ->> 'place_code'
                    ORDER BY p.id LOOP
        PERFORM pg_advisory_xact_lock_shared(public.place_lock_key(v_place));
        v_locked := v_locked || v_place;
    END LOOP;
    -- r3 (-16's rule, race R19 there): a row of the code committed while this
    -- waited was never locked, so it is not trusted; the writer retries.
    SELECT coalesce(array_agg(p.id ORDER BY p.id), ARRAY[]::uuid[]) INTO v_now FROM public.places p
     WHERE p.kind_code = p_row ->> 'place_kind' AND p.state_code = p_row ->> 'state_code' AND p.place_code = p_row ->> 'place_code';
    IF v_now <> v_locked THEN
        RAISE EXCEPTION USING
            MESSAGE = format('tax levy: the rows of %s %s in %s changed while this waited; retry (v5.4.2-30)', p_row ->> 'place_kind', p_row ->> 'place_code', p_row ->> 'state_code'),
            ERRCODE = 'serialization_failure';
    END IF;
    SELECT range_agg(daterange(p.effective_from, p.effective_to, '[)')) INTO v_cover
      FROM public.places p
     WHERE p.kind_code = p_row ->> 'place_kind' AND p.state_code = p_row ->> 'state_code' AND p.place_code = p_row ->> 'place_code';
    IF v_cover IS NULL OR NOT v_cover @> v_range THEN
        RAISE EXCEPTION USING
            MESSAGE = format('tax levy: no %s %s in %s is in force over the whole of %s (its rows: %s; v5.4.2-30)',
                             p_row ->> 'place_kind', p_row ->> 'place_code', p_row ->> 'state_code', v_range, coalesce(v_cover::text, 'none')),
            ERRCODE = 'check_violation';
    END IF;
    IF v_rate IS DISTINCT FROM round(v_rate, 4) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('tax levy: a rate carries at most four decimals, in percent (K-06, AC-45); got %s (v5.4.2-30)', v_rate),
            ERRCODE = 'check_violation';
    END IF;
    FOR v_on IN SELECT jsonb_array_elements_text(p_row -> 'terms' -> 'computed_on') LOOP
        IF v_on = p_row ->> 'tax_kind' THEN
            RAISE EXCEPTION USING
                MESSAGE = format('tax levy: computed_on names its own kind (%s): a levy is never charged on itself (v5.4.2-30)', v_on),
                ERRCODE = 'check_violation';
        END IF;
        IF NOT EXISTS (SELECT 1 FROM public.tax_kinds t WHERE t.tax_kind = v_on) THEN
            RAISE EXCEPTION USING
                MESSAGE = format('tax levy: computed_on names %s, which is not a tax kind (v5.4.2-30)', v_on),
                ERRCODE = 'check_violation';
        END IF;
    END LOOP;
END;
$$;
COMMENT ON FUNCTION public.tax_levy_insert_check(jsonb) IS
    'v5.4.2-30. The area predicate of tax_levies (rule_tables.insert_check), over the new row with its document: the writer is the row''s own utility; the place kind levies the tax (tax_kinds.place_kinds); a place of that kind and code in the row''s state is in force over the whole of the row''s dates (READ COMMITTED; each of the code''s rows share-locked first, so a close waits and then sees the levy); the rate has at most four decimals; computed_on names known tax kinds, never the levy''s own. Raises.';

DO $register30$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.rule_tables WHERE table_name = 'public.tax_levies'::regclass) THEN
        PERFORM public.rule_table_register('public.tax_levies', 'tariff', 'tax_levy', ARRAY['place_kind', 'place_code', 'tax_kind'], ARRAY[]::text[],
                                           NULL, 'public.tax_levy_insert_check(jsonb)');
    END IF;
END
$register30$;
REVOKE ALL ON FUNCTION public.tax_levy_insert_check(jsonb) FROM PUBLIC, tally_core;
GRANT EXECUTE ON FUNCTION public.tax_levy_insert_check(jsonb) TO tally_app;

-- ----------------------------------------------------------------------------
-- 2b. A place is never closed from under a levy (r2; review r1: Codex B1,
--     Opus S2, Fable S1)
-- ----------------------------------------------------------------------------
-- -16's enforce_place() refuses a close while a citing row runs past it. A
-- levy names its place by code, and a succession is a close then a successor
-- row (the rows of one code never overlap), so the levy's check runs at
-- commit: by then the successor is there, or the close is refused. The closer
-- sees every tenant (enforce_place requires superuser or BYPASSRLS) and holds
-- the place's exclusive lock until commit; a levy insert takes it shared
-- (tax_levy_insert_check), so the two serialise.
CREATE OR REPLACE FUNCTION public.check_place_levy_coverage() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_levy uuid;
    v_sees_all boolean;
BEGIN
    -- r3 (review r2, Fable S1): the levies are tenant rows; the check runs
    -- as whoever holds the session at commit, so it requires a role that
    -- sees them all, as the close itself does (enforce_place).
    SELECT r.rolsuper OR r.rolbypassrls INTO v_sees_all FROM pg_catalog.pg_roles r WHERE r.rolname = current_user;
    IF v_sees_all IS NOT TRUE THEN
        RAISE EXCEPTION USING
            MESSAGE = format('place %s: its close is checked against every tenant''s levies, which needs a role that sees them all (superuser or BYPASSRLS); %s does not (v5.4.2-30)', OLD.id, current_user),
            ERRCODE = 'insufficient_privilege';
    END IF;
    SELECT t.id INTO v_levy FROM public.tax_levies t
     WHERE t.place_kind = OLD.kind_code AND t.state_code = OLD.state_code AND t.place_code = OLD.place_code
       AND NOT coalesce((SELECT range_agg(daterange(p.effective_from, p.effective_to, '[)')) FROM public.places p
                          WHERE p.kind_code = t.place_kind AND p.state_code = t.state_code AND p.place_code = t.place_code)
                        @> daterange(t.effective_from, t.effective_to, '[)'), false)
     ORDER BY t.id LIMIT 1;
    IF v_levy IS NOT NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('place %s: closed at %s, a tax levy %s of %s %s runs past what the place''s rows cover; add the successor row in the same transaction, or have the utility close its levy first (v5.4.2-30)',
                             OLD.id, NEW.effective_to, v_levy, OLD.kind_code, OLD.place_code),
            ERRCODE = 'restrict_violation';
    END IF;
    RETURN NULL;
END;
$$;
COMMENT ON FUNCTION public.check_place_levy_coverage() IS
    'v5.4.2-30 r2. Deferred (at commit) AFTER UPDATE OF effective_to on places, every role: after a place row''s close, every tax levy of its kind, state and code must still be covered by that code''s rows. A succession (the close and the successor row in one transaction) passes; a dissolution waits for the utility''s close of its levy.';
REVOKE ALL ON FUNCTION public.check_place_levy_coverage() FROM PUBLIC;
DROP TRIGGER IF EXISTS z_check_place_levy_coverage ON public.places;
CREATE CONSTRAINT TRIGGER z_check_place_levy_coverage AFTER UPDATE OF effective_to ON public.places
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION public.check_place_levy_coverage();
ALTER TABLE public.places ENABLE ALWAYS TRIGGER z_check_place_levy_coverage;
COMMENT ON TABLE public.tax_levies IS
    'v5.4.2-30 (Kyle 2026-10-14 answers 1, 2; Ryan 2026-09-30: a value the utility answers for stays its own), on the rule-terms convention. The utility''s own record of each tax a place levies on its bills, per (tenant, state, service, system, place kind and code, tax kind, dates): one tax_levy document (rate in percent, stacking position, computed_on, source kind and citation, reaches_residential). The place is named by its kind and code, not its row id, so the levy survives the place''s succession. Never edited; closed once (effective_to), stamped; a change is a close and a successor. The published rate (place_facts sales_tax_rate) is the reference and never bills: tax_levy_reference_gaps() reports a difference. Read through tax_levy_as_of().';

-- ----------------------------------------------------------------------------
-- 3. Reading a levy; the reference compare
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.tax_levy_as_of(p_tenant_id uuid, p_state_code text, p_place_kind text, p_place_code text, p_tax_kind text,
                                                 p_service_type text, p_system_kind text, p_on date, p_recorded_at timestamp with time zone)
    RETURNS SETOF public.tax_levies
    LANGUAGE plpgsql STABLE
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_n integer;
BEGIN
    IF p_tenant_id IS NULL OR p_state_code IS NULL OR p_place_kind IS NULL OR p_place_code IS NULL OR p_tax_kind IS NULL
       OR p_service_type IS NULL OR p_system_kind IS NULL OR p_on IS NULL OR p_recorded_at IS NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = 'tax_levy_as_of: every argument is required — never default to today or to now() (v5.4.2-30)',
            ERRCODE = 'null_value_not_allowed';
    END IF;
    RETURN QUERY
    SELECT t.* FROM public.tax_levies t
     WHERE t.tenant_id = p_tenant_id AND t.state_code = p_state_code AND t.place_kind = p_place_kind AND t.place_code = p_place_code
       AND t.tax_kind = p_tax_kind AND t.service_type = p_service_type AND t.system_kind = p_system_kind
       AND t.created_at <= p_recorded_at
       AND daterange(t.effective_from, public.end_as_known(t.effective_to, t.closed_at, p_recorded_at), '[)') @> p_on;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    IF v_n > 1 THEN
        RAISE EXCEPTION USING
            MESSAGE = format('tax_levy_as_of: %s rows of %s %s %s in force on %s as known at %s (v5.4.2-30)', v_n, p_place_kind, p_place_code, p_tax_kind, p_on, p_recorded_at),
            ERRCODE = 'cardinality_violation';
    END IF;
END;
$$;
COMMENT ON FUNCTION public.tax_levy_as_of(uuid, text, text, text, text, text, text, date, timestamp with time zone) IS
    'v5.4.2-30 (CI-001, CI-004). The utility''s levy of a tax by a place (kind and code, as premise_places_as_of returns it) for a service and system, in force on p_on as known at p_recorded_at: recorded by then, and its end only if its close was recorded by then. No row: none. Every argument required (NULL raises); invoker rights, RLS applies.';

CREATE OR REPLACE FUNCTION public.tax_levy_reference_gaps(p_tenant_id uuid, p_on date)
    RETURNS TABLE (levy_id uuid, place_kind text, place_code text, levy_rate_percent numeric, reference_rate_percent numeric, reference_source text)
    LANGUAGE plpgsql STABLE
    SET search_path = public, pg_temp
    AS $$
BEGIN
    IF p_tenant_id IS NULL OR p_on IS NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = 'tax_levy_reference_gaps: the utility and the date are required (v5.4.2-30)',
            ERRCODE = 'null_value_not_allowed';
    END IF;
    RETURN QUERY
    -- A levy whose rate differs from the published one.
    SELECT t.id, t.place_kind, t.place_code, (t.terms ->> 'rate_percent')::numeric, (f.value #>> '{}')::numeric, f.source_note
      FROM public.tax_levies t
      JOIN public.places p ON p.kind_code = t.place_kind AND p.state_code = t.state_code AND p.place_code = t.place_code
                          AND daterange(p.effective_from, p.effective_to, '[)') @> p_on
      JOIN public.place_facts f ON f.place_id = p.id AND f.fact_code = 'sales_tax_rate'
                               AND daterange(f.effective_from, f.effective_to, '[)') @> p_on
     WHERE t.tenant_id = p_tenant_id AND t.tax_kind = 'sales_tax'
       AND daterange(t.effective_from, t.effective_to, '[)') @> p_on
       AND (t.terms ->> 'rate_percent')::numeric IS DISTINCT FROM (f.value #>> '{}')::numeric
    UNION ALL
    -- r2 (review r1, Fable S6): a place the utility's premises are in (an open
    -- tax-axis membership on p_on, or the premise's state), publishing a rate
    -- on p_on, with no sales-tax levy of the utility in force: a published tax
    -- nobody approved (known limit L1).
    SELECT NULL::uuid, p.kind_code, p.place_code, NULL::numeric, (f.value #>> '{}')::numeric, f.source_note
      FROM public.places p
      JOIN public.place_facts f ON f.place_id = p.id AND f.fact_code = 'sales_tax_rate'
                               AND daterange(f.effective_from, f.effective_to, '[)') @> p_on
     WHERE daterange(p.effective_from, p.effective_to, '[)') @> p_on
       AND (EXISTS (SELECT 1 FROM public.premise_place_memberships m
                     WHERE m.place_id = p.id AND m.tenant_id = p_tenant_id AND m.axis = 'tax' AND m.voided_at IS NULL
                       AND daterange(m.valid_from, m.valid_to, '[)') @> p_on)
            OR (p.kind_code = 'state'
                AND EXISTS (SELECT 1 FROM public.service_locations l
                             WHERE l.tenant_id = p_tenant_id AND upper(btrim(l.state)) = p.state_code)))
       AND NOT EXISTS (SELECT 1 FROM public.tax_levies t
                        WHERE t.tenant_id = p_tenant_id AND t.tax_kind = 'sales_tax' AND t.state_code = p.state_code
                          AND t.place_kind = p.kind_code AND t.place_code = p.place_code
                          AND daterange(t.effective_from, t.effective_to, '[)') @> p_on)
     ORDER BY 2, 3;
END;
$$;
COMMENT ON FUNCTION public.tax_levy_reference_gaps(uuid, date) IS
    'v5.4.2-30 (Ryan 2026-09-30: the platform keeps the published value as a reference and reports a disagreement). On p_on: each sales-tax levy of the utility whose place carries a published sales_tax_rate that differs (both rates and the published value''s source); and (r2) each place the utility''s premises are in (an open tax-axis membership, or the premise''s state) that publishes a rate while the utility has no levy of it (levy_id and levy_rate_percent NULL). A report, never a refusal: the utility''s row bills. The second part reads memberships and premises as they stand now, counts every premise of the utility whatever its status, and does not look at service type: a place listed for an inactive premise is a false alarm, never a missed one. Both arguments required.';
REVOKE ALL ON FUNCTION public.tax_levy_as_of(uuid, text, text, text, text, text, text, date, timestamp with time zone),
                       public.tax_levy_reference_gaps(uuid, date), public.end_as_known(date, timestamp with time zone, timestamp with time zone) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.tax_levy_as_of(uuid, text, text, text, text, text, text, date, timestamp with time zone),
                          public.tax_levy_reference_gaps(uuid, date), public.end_as_known(date, timestamp with time zone, timestamp with time zone) TO tally_app, tally_core;

-- ----------------------------------------------------------------------------
-- 4. Rate item versions: no defaults; the late-penalty base
-- ----------------------------------------------------------------------------
ALTER TABLE public.rate_item_versions ADD COLUMN IF NOT EXISTS in_late_penalty_base boolean NOT NULL;
ALTER TABLE public.rate_item_versions ALTER COLUMN is_taxable_default DROP DEFAULT;
ALTER TABLE public.rate_item_versions ALTER COLUMN is_a_tax DROP DEFAULT;
ALTER TABLE public.rate_item_versions ALTER COLUMN applies_to_customer_types DROP DEFAULT;
ALTER TABLE public.rate_item_versions DROP CONSTRAINT IF EXISTS rate_item_versions_customer_types_check;
ALTER TABLE public.rate_item_versions ADD CONSTRAINT rate_item_versions_customer_types_check
    CHECK ((cardinality(applies_to_customer_types) > 0) AND (array_position(applies_to_customer_types, NULL) IS NULL)
           AND (applies_to_customer_types <@ ARRAY['residential'::text, 'commercial'::text, 'small_commercial'::text, 'large_commercial'::text,
                                                  'industrial'::text, 'government'::text, 'wholesale'::text]));
COMMENT ON COLUMN public.rate_item_versions.is_taxable_default IS
    'Whether the rider''s lines are in the sales-tax base (overridable per schedule, rate_schedule_items.is_taxable_override). Required, no default (v5.4.2-30; Kyle 2026-10-14 answer 5: every charge declares its tax status). A rider with an open regulatory_surcharge_rules row excluded_from_tax_bases can never assert true here (v5.4.2-07). Whether a line is actually taxed also needs the customer taxable for its service type (should_charge_tax).';
COMMENT ON COLUMN public.rate_item_versions.is_a_tax IS
    'Whether the rider is itself a tax. Required, no default (v5.4.2-30). A tax is never in the late-penalty base.';
COMMENT ON COLUMN public.rate_item_versions.in_late_penalty_base IS
    'Whether the rider''s lines are in the base a late penalty is computed on (Kyle 2026-11-05, scenario batch 2 answer 3a: every line priced by the tariff, never taxes or state fees such as the pipeline safety fee; a per-charge setting the utility controls). Required, no default (v5.4.2-30). Never true for a tax, or for a rider excluded from tax bases. The penalty itself is the money stream''s.';
COMMENT ON COLUMN public.rate_item_versions.applies_to_customer_types IS
    'The customer types the rider bills: a non-empty list of the types customers_customer_type_check allows. Required, no default (v5.4.2-30; Kyle 2026-09-02: the old default left out small_commercial and large_commercial and silently skipped them).';

CREATE OR REPLACE FUNCTION public.enforce_late_penalty_base() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_rule public.regulatory_surcharge_rules%ROWTYPE;
BEGIN
    IF NOT NEW.in_late_penalty_base THEN
        RETURN NEW;
    END IF;
    IF NEW.is_a_tax THEN
        RAISE EXCEPTION USING
            MESSAGE = format('rate_item_versions: rate item %s is a tax and cannot be in the late-penalty base (Kyle 2026-11-05, 3a: never on taxes; v5.4.2-30)', NEW.rate_item_id),
            ERRCODE = 'check_violation';
    END IF;
    SELECT r.* INTO v_rule FROM public.regulatory_surcharge_rules r
     WHERE r.rate_item_id = NEW.rate_item_id AND r.recorded_until IS NULL AND r.excluded_from_tax_bases
     ORDER BY r.cycle_start DESC LIMIT 1;
    IF FOUND THEN
        RAISE EXCEPTION USING
            MESSAGE = format('rate_item_versions: rate item %s is a %s surcharge rider excluded from tax bases (regulatory_surcharge_rules %s) and cannot be in the late-penalty base (Kyle 2026-11-05, 3a: never on state fees; v5.4.2-30)',
                             NEW.rate_item_id, v_rule.surcharge_kind, v_rule.id),
            ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$;
COMMENT ON FUNCTION public.enforce_late_penalty_base() IS
    'v5.4.2-30. BEFORE INSERT / UPDATE OF in_late_penalty_base, is_a_tax on rate_item_versions: a version in the late-penalty base is refused when it is a tax, or when its rate item has an open surcharge rule excluded from tax bases. With enforce_surcharge_rule_late_penalty_base() the rule holds in both orders of writing (known limit L2: concurrent writers, as -07).';
DROP TRIGGER IF EXISTS b_enforce_late_penalty_base ON public.rate_item_versions;
CREATE TRIGGER b_enforce_late_penalty_base BEFORE INSERT OR UPDATE OF in_late_penalty_base, is_a_tax ON public.rate_item_versions
    FOR EACH ROW EXECUTE FUNCTION public.enforce_late_penalty_base();
ALTER TABLE public.rate_item_versions ENABLE ALWAYS TRIGGER b_enforce_late_penalty_base;

CREATE OR REPLACE FUNCTION public.enforce_surcharge_rule_late_penalty_base() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v integer;
BEGIN
    IF NOT NEW.excluded_from_tax_bases THEN
        RETURN NEW;
    END IF;
    SELECT count(*) INTO v FROM public.rate_item_versions iv
     WHERE iv.rate_item_id = NEW.rate_item_id AND iv.recorded_until IS NULL AND iv.in_late_penalty_base;
    IF v > 0 THEN
        RAISE EXCEPTION USING
            MESSAGE = format('regulatory_surcharge_rules: rider %s cannot be excluded from tax bases while %s open version(s) are in the late-penalty base — correct those versions first (Kyle 2026-11-05, 3a; v5.4.2-30)', NEW.rate_item_id, v),
            ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$;
COMMENT ON FUNCTION public.enforce_surcharge_rule_late_penalty_base() IS
    'v5.4.2-30. BEFORE INSERT on regulatory_surcharge_rules: a rule excluding its rider from tax bases is refused while an open version of the rider is in the late-penalty base. The other half of enforce_late_penalty_base().';
DROP TRIGGER IF EXISTS c_enforce_surcharge_rule_late_penalty_base ON public.regulatory_surcharge_rules;
CREATE TRIGGER c_enforce_surcharge_rule_late_penalty_base BEFORE INSERT ON public.regulatory_surcharge_rules
    FOR EACH ROW EXECUTE FUNCTION public.enforce_surcharge_rule_late_penalty_base();
ALTER TABLE public.regulatory_surcharge_rules ENABLE ALWAYS TRIGGER c_enforce_surcharge_rule_late_penalty_base;

-- ----------------------------------------------------------------------------
-- 5. Exemptions name their services
-- ----------------------------------------------------------------------------
ALTER TABLE public.customer_tax_exemptions DROP CONSTRAINT IF EXISTS customer_tax_exemptions_service_types_check;
ALTER TABLE public.customer_tax_exemptions ADD CONSTRAINT customer_tax_exemptions_service_types_check
    CHECK ((service_types IS NOT NULL) AND (cardinality(service_types) > 0) AND (array_position(service_types, NULL) IS NULL)
           AND (service_types <@ ARRAY['water'::text, 'sewer'::text, 'electric'::text, 'gas'::text, 'stormwater'::text, 'trash'::text, 'reclaimed_water'::text]));
COMMENT ON CONSTRAINT customer_tax_exemptions_service_types_check ON public.customer_tax_exemptions IS
    'v5.4.2-30 (Kyle 2026-10-14 answer 5: customer taxability is per service type): an exemption names the services it covers, each one a service (r2: a misspelled one is refused, never silently matching nothing); "every service" is the list written out.';
COMMENT ON COLUMN public.customer_tax_exemptions.service_types IS
    'The service types this exemption covers: required, non-empty, each one a service (water, sewer, electric, gas, stormwater, trash, reclaimed_water). An exemption of every service lists them all; {gas} is exempt from gas only and still pays tax on the others (v5.4.2-30; Kyle 2026-10-14 answer 5).';

CREATE OR REPLACE FUNCTION public.should_charge_tax(p_customer_id uuid, p_item_is_taxable boolean, p_service_type text, p_valid_at date, p_recorded_at timestamp with time zone) RETURNS boolean
    LANGUAGE plpgsql STABLE
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_has_exemption boolean;
BEGIN
    IF p_valid_at IS NULL OR p_recorded_at IS NULL THEN
        RAISE EXCEPTION 'should_charge_tax: p_valid_at and p_recorded_at are both required — never default to now() (CI-001 / CI-003 / CI-006)';
    END IF;

    -- v5.4.2-30 (Kyle 2026-10-14 answer 5: customer taxability is per service
    -- type): a line with no service type matches no exemption; it is refused,
    -- not read as matching every exemption.
    IF p_service_type IS NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = 'should_charge_tax: a service type is required: a line with none matches no exemption (v5.4.2-30)',
            ERRCODE = 'null_value_not_allowed';
    END IF;

    -- Rule 1: item-level non-taxable wins
    IF p_item_is_taxable IS NULL OR p_item_is_taxable = false THEN
        RETURN false;
    END IF;

    -- Rule 2: a customer exemption asserted as of p_recorded_at, covering p_valid_at and the service type
    SELECT EXISTS (
        SELECT 1
        FROM public.customer_tax_exemption_as_of(p_customer_id, p_valid_at, p_recorded_at) cte
        WHERE p_service_type = ANY (cte.service_types)   -- v5.4.2-30: every exemption names its services
    ) INTO v_has_exemption;

    IF v_has_exemption THEN
        RETURN false;
    END IF;

    -- Rule 3: taxable item, no exemption -> charge tax
    RETURN true;
END;
$$;

-- ----------------------------------------------------------------------------
-- 6. The published sales-tax rate is percent
-- ----------------------------------------------------------------------------
-- A reviewed platform repair of a vocabulary row (the guard's own hint: "a row
-- wrong from its first day is a reviewed platform repair"): the kind was
-- seeded as a fraction, against AC-45, and no fact of it exists, so nothing
-- changes meaning. The guard is lifted for this one statement, in this
-- transaction, and set back to ALWAYS before anything else runs. Refused if
-- any sales_tax_rate fact exists (its value would change meaning).
DO $repair30$
BEGIN
    -- r2 (review r1: Opus S3, Fable S3, Codex S1): only while the repair is
    -- still to be made; once the kind is percent, its facts are percent.
    IF EXISTS (SELECT 1 FROM public.place_fact_kinds WHERE fact_code = 'sales_tax_rate' AND value_max IS DISTINCT FROM 100)
       AND EXISTS (SELECT 1 FROM public.place_facts WHERE fact_code = 'sales_tax_rate') THEN
        RAISE EXCEPTION 'v5.4.2-30 precondition: sales_tax_rate facts exist; their values are fractions and the kind cannot move to percent in place';
    END IF;
END
$repair30$;
ALTER TABLE public.place_fact_kinds DISABLE TRIGGER a_enforce_place_vocabulary_immutable;
UPDATE public.place_fact_kinds
   SET value_max = 100,
       description = 'The place''s published sales-tax rate, in percent (8.25 = 8.25%), 0 up to but not including 100, stored as the tax authority publishes it and dated as it publishes it. A reference value: the utility''s own levy (tax_levies, four decimals at most) bills.',
       source_note = 'Texas Tax 321.102 (quarter-start effective dates), Comptroller rate file (inventory P7; review r1 B5); in percent since v5.4.2-30 (AC-45)'
 WHERE fact_code = 'sales_tax_rate' AND (value_max IS DISTINCT FROM 100 OR description !~ 'in percent');
ALTER TABLE public.place_fact_kinds ENABLE ALWAYS TRIGGER a_enforce_place_vocabulary_immutable;

-- ----------------------------------------------------------------------------
-- 7a. A premise's state, recorded on change (r2; review r1: Opus B1, Codex B2)
-- ----------------------------------------------------------------------------
-- A read as known at an instant needs the premise's state as known then: the
-- operator can correct a state (once its other-state memberships are voided,
-- -16), and the past read must still answer the old state and its places.
-- The database records the normalised state when a premise is inserted and
-- each time it changes; the app writes and edits none of it.
CREATE TABLE IF NOT EXISTS public.service_location_state_history (
    id                  uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id           uuid NOT NULL,
    service_location_id uuid NOT NULL,
    state               text NOT NULL,
    recorded_at         timestamp with time zone DEFAULT now() NOT NULL,
    seq                 bigint GENERATED ALWAYS AS IDENTITY,
    CONSTRAINT service_location_state_history_pkey PRIMARY KEY (id),
    CONSTRAINT service_location_state_history_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id),
    CONSTRAINT service_location_state_history_location_fkey FOREIGN KEY (service_location_id, tenant_id) REFERENCES public.service_locations(id, tenant_id)
);
CREATE INDEX IF NOT EXISTS idx_service_location_state_history_lookup
    ON public.service_location_state_history USING btree (service_location_id, recorded_at DESC, seq DESC);
CREATE INDEX IF NOT EXISTS idx_service_location_state_history_tenant ON public.service_location_state_history USING btree (tenant_id);
ALTER TABLE public.service_location_state_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.service_location_state_history FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_isolation ON public.service_location_state_history;
CREATE POLICY tenant_isolation ON public.service_location_state_history USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));
REVOKE ALL ON public.service_location_state_history FROM PUBLIC, tally_app, tally_core;
GRANT SELECT, INSERT ON public.service_location_state_history TO tally_app;
GRANT SELECT ON public.service_location_state_history TO tally_core;
COMMENT ON TABLE public.service_location_state_history IS
    'v5.4.2-30 r2 (CI-001, CI-004). Each premise''s normalised state (upper(btrim(service_locations.state))) as recorded: one row when the premise is inserted and one each time its normalised state changes, written by the database (record_service_location_state). Append-only. premise_places_as_of() reads the state as known at an instant from it. Backfilled for every existing premise at its created_at.';

CREATE OR REPLACE FUNCTION public.enforce_state_history_written_by_db() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
BEGIN
    -- inside this trigger a direct statement is depth 1; the recorder's insert is depth 2
    IF pg_trigger_depth() < 2 AND NOT coalesce((SELECT r.rolsuper FROM pg_roles r WHERE r.rolname = current_user), false) THEN
        RAISE EXCEPTION USING
            MESSAGE = 'service_location_state_history is written by the database: change the premise''s state and let it be recorded; a direct insert is not history (v5.4.2-30)',
            ERRCODE = 'insufficient_privilege';
    END IF;
    RETURN NEW;
END;
$$;
COMMENT ON FUNCTION public.enforce_state_history_written_by_db() IS
    'v5.4.2-30 r2. BEFORE INSERT on service_location_state_history, every role: refused for a direct statement (pg_trigger_depth() < 2 inside the guard) unless the writer is a superuser (the backfill). With TEMP revoked from the app role the depth is a structural fence (as -07''s enforce_event_written_by_db).';
DROP TRIGGER IF EXISTS a_enforce_state_history_written_by_db ON public.service_location_state_history;
CREATE TRIGGER a_enforce_state_history_written_by_db BEFORE INSERT ON public.service_location_state_history
    FOR EACH ROW EXECUTE FUNCTION public.enforce_state_history_written_by_db();
ALTER TABLE public.service_location_state_history ENABLE ALWAYS TRIGGER a_enforce_state_history_written_by_db;
DROP TRIGGER IF EXISTS append_only ON public.service_location_state_history;
CREATE TRIGGER append_only BEFORE DELETE OR UPDATE ON public.service_location_state_history
    FOR EACH ROW EXECUTE FUNCTION public.enforce_append_only();
ALTER TABLE public.service_location_state_history ENABLE ALWAYS TRIGGER append_only;
DROP TRIGGER IF EXISTS no_truncate ON public.service_location_state_history;
CREATE TRIGGER no_truncate BEFORE TRUNCATE ON public.service_location_state_history
    FOR EACH STATEMENT EXECUTE FUNCTION public.enforce_no_hard_delete();
ALTER TABLE public.service_location_state_history ENABLE ALWAYS TRIGGER no_truncate;

CREATE OR REPLACE FUNCTION public.record_service_location_state() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
BEGIN
    IF TG_OP = 'UPDATE' AND upper(btrim(NEW.state)) IS NOT DISTINCT FROM upper(btrim(OLD.state)) THEN
        RETURN NULL;
    END IF;
    -- r3 (review r2: Opus B1, Fable B1): a row stamped after this transaction
    -- began was written by a transaction that began later and committed
    -- first (both hold the premise's row lock). Recorded after it, this row
    -- would sort below it and the history would end on the wrong state, so
    -- this writer retries.
    IF TG_OP = 'UPDATE' AND EXISTS (SELECT 1 FROM public.service_location_state_history h
                                     WHERE h.service_location_id = NEW.id AND h.recorded_at > now()) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('service location %s: its state was recorded by a transaction that began after this one; retry (v5.4.2-30)', NEW.id),
            ERRCODE = 'serialization_failure';
    END IF;
    INSERT INTO public.service_location_state_history (tenant_id, service_location_id, state, recorded_at)
    VALUES (NEW.tenant_id, NEW.id, upper(btrim(NEW.state)), now());
    RETURN NULL;
END;
$$;
COMMENT ON FUNCTION public.record_service_location_state() IS
    'v5.4.2-30 r2, r3. AFTER INSERT OR UPDATE OF state on service_locations, every role: records the premise''s normalised state at insert and whenever it changes (a change of spelling alone records nothing), stamped now(). A change is refused (40001, retry) when the premise already has a row stamped after this transaction began, so the history''s order is the order of the changes.';
REVOKE ALL ON FUNCTION public.record_service_location_state(), public.enforce_state_history_written_by_db() FROM PUBLIC;
DROP TRIGGER IF EXISTS z_record_service_location_state ON public.service_locations;
CREATE TRIGGER z_record_service_location_state AFTER INSERT OR UPDATE OF state ON public.service_locations
    FOR EACH ROW EXECUTE FUNCTION public.record_service_location_state();
ALTER TABLE public.service_locations ENABLE ALWAYS TRIGGER z_record_service_location_state;
-- Backfill: every premise without a recorded state, at its created_at (the
-- owner; the guard lets the superuser write). Its state today is the best
-- record there is: -16 refused a change under other-state memberships.
INSERT INTO public.service_location_state_history (tenant_id, service_location_id, state, recorded_at)
SELECT l.tenant_id, l.id, upper(btrim(l.state)), l.created_at
  FROM public.service_locations l
 WHERE NOT EXISTS (SELECT 1 FROM public.service_location_state_history h WHERE h.service_location_id = l.id);

-- ----------------------------------------------------------------------------
-- 7. A premise's places as known at an instant
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.premise_places_as_of(p_service_location_id uuid, p_on date, p_axis text, p_recorded_at timestamp with time zone)
    RETURNS TABLE (place_id uuid, kind_code text, state_code text, place_code text, name text, specificity integer, relation text, distance_miles numeric)
    LANGUAGE plpgsql STABLE
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_state text;
    v_state_place uuid;
BEGIN
    IF p_on IS NULL OR p_axis IS NULL OR p_axis <> ALL (ARRAY['regulatory', 'tax']) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('premise_places_as_of: a date and an axis (regulatory or tax) are required; got %s, %s (v5.4.2-16)', coalesce(p_on::text, 'NULL'), coalesce(p_axis, 'NULL')),
            ERRCODE = 'invalid_parameter_value';
    END IF;
    IF p_recorded_at IS NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = 'premise_places_as_of: a recorded-at instant is required: the places as known then (v5.4.2-30)',
            ERRCODE = 'null_value_not_allowed';
    END IF;
    -- The premise's state as known at p_recorded_at (r2): the latest recorded
    -- by then. An invisible or missing premise has none, nor one recorded
    -- later, and is refused.
    SELECT h.state INTO v_state FROM public.service_location_state_history h
     WHERE h.service_location_id = p_service_location_id AND h.recorded_at <= p_recorded_at
     ORDER BY h.recorded_at DESC, h.seq DESC LIMIT 1;
    IF v_state IS NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('premise_places_as_of: premise %s is not found (or not visible), or was not yet recorded at %s; its places cannot be read (v5.4.2-30)', p_service_location_id, p_recorded_at),
            ERRCODE = 'no_data_found';
    END IF;
    SELECT p.id INTO v_state_place FROM public.places p
     WHERE p.kind_code = 'state' AND p.state_code = v_state AND p.created_at <= p_recorded_at
       AND daterange(p.effective_from, public.end_as_known(p.effective_to, p.closed_at, p_recorded_at), '[)') @> p_on;
    IF v_state_place IS NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('premise_places_as_of: premise %s is not found (or not visible), or its state %s is no state known on %s; its places cannot be read (v5.4.2-16)', p_service_location_id, coalesce(v_state, 'NULL'), p_on),
            ERRCODE = 'no_data_found';
    END IF;
    -- r3 (review r2, Opus S1): two within places of one exclusive group as
    -- known at the instant (a void and its successor recorded by overlapping
    -- transactions, L7) is ambiguous: refused, never both.
    IF EXISTS (SELECT 1 FROM public.premise_place_memberships m
                 JOIN public.places p ON p.id = m.place_id
                WHERE m.service_location_id = p_service_location_id AND m.axis = p_axis
                  AND m.relation = 'within' AND m.exclusivity_group IS NOT NULL
                  AND m.created_at <= p_recorded_at AND (m.voided_at IS NULL OR m.voided_at > p_recorded_at)
                  AND daterange(m.valid_from, public.end_as_known(m.valid_to, m.closed_at, p_recorded_at), '[)') @> p_on
                  AND p.created_at <= p_recorded_at
                  AND daterange(p.effective_from, public.end_as_known(p.effective_to, p.closed_at, p_recorded_at), '[)') @> p_on
                  AND p.state_code = v_state
                GROUP BY m.exclusivity_group HAVING count(*) > 1) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('premise_places_as_of: premise %s is within two places of one exclusive group on %s as known at %s (v5.4.2-30)', p_service_location_id, p_on, p_recorded_at),
            ERRCODE = 'cardinality_violation';
    END IF;
    RETURN QUERY
    SELECT p.id, p.kind_code, p.state_code, p.place_code, p.name, k.specificity, m.relation, m.distance_miles
      FROM public.premise_place_memberships m
      JOIN public.places p ON p.id = m.place_id
      JOIN public.place_kinds k ON k.kind_code = p.kind_code
     WHERE m.service_location_id = p_service_location_id AND m.axis = p_axis
       -- v5.4.2-30: as known at p_recorded_at — recorded by then, not voided by
       -- then, and its end only if its close was recorded by then.
       AND m.created_at <= p_recorded_at AND (m.voided_at IS NULL OR m.voided_at > p_recorded_at)
       AND daterange(m.valid_from, public.end_as_known(m.valid_to, m.closed_at, p_recorded_at), '[)') @> p_on
       -- defence in depth: the place in force on the date, of the premise's state, as known then
       AND p.created_at <= p_recorded_at
       AND daterange(p.effective_from, public.end_as_known(p.effective_to, p.closed_at, p_recorded_at), '[)') @> p_on
       AND p.state_code = v_state
    UNION ALL
    SELECT p.id, p.kind_code, p.state_code, p.place_code, p.name, k.specificity, 'within'::text, NULL::numeric
      FROM public.places p JOIN public.place_kinds k ON k.kind_code = p.kind_code
     WHERE p.id = v_state_place;
END;
$$;
COMMENT ON FUNCTION public.premise_places_as_of(uuid, date, text, timestamp with time zone) IS
    'v5.4.2-30 (CI-001, CI-004). The places a premise is related to on a date, on an axis, as known at p_recorded_at: its state as recorded by then (service_location_state_history, r2), memberships recorded by then and not voided by then, each ending only if its close was recorded by then; places likewise. A rebill reads the jurisdictions the original bill saw. Refuses a premise not yet recorded then. Every argument required.';

CREATE OR REPLACE FUNCTION public.premise_places_as_of(p_service_location_id uuid, p_on date, p_axis text)
    RETURNS TABLE (place_id uuid, kind_code text, state_code text, place_code text, name text, specificity integer, relation text, distance_miles numeric)
    LANGUAGE sql STABLE
    SET search_path = public, pg_temp
    AS $$
    SELECT * FROM public.premise_places_as_of(p_service_location_id, p_on, p_axis, now())
$$;
COMMENT ON FUNCTION public.premise_places_as_of(uuid, date, text) IS
    'v5.4.2-16; since v5.4.2-30 the four-argument form read at now(): the places a premise is related to on a date, on an axis (regulatory or tax), as known now.';
REVOKE ALL ON FUNCTION public.premise_places_as_of(uuid, date, text, timestamp with time zone) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.premise_places_as_of(uuid, date, text, timestamp with time zone) TO tally_app, tally_core;

-- ----------------------------------------------------------------------------
-- 8. A state agency's basis
-- ----------------------------------------------------------------------------
ALTER TABLE public.customers ADD COLUMN IF NOT EXISTS state_agency_basis text;
ALTER TABLE public.customers DROP CONSTRAINT IF EXISTS customers_state_agency_basis_check;
ALTER TABLE public.customers ADD CONSTRAINT customers_state_agency_basis_check
    CHECK ((NOT is_state_agency) OR ((state_agency_basis IS NOT NULL) AND (state_agency_basis ~ '[[:alnum:]]'::text)));
COMMENT ON COLUMN public.customers.state_agency_basis IS
    'v5.4.2-30 (Kyle 2026-11-05, scenario batch 2 answer 20): the documented basis for treating the account as an exempt state agency (a citation or document reference: a public college or university may be one, Gov''t Code 572.002 as limited by Nat. Res. Code 31.401(a); counties, school districts and private colleges are not). Required while is_state_agency is true; logged in customer_attribute_history (attribute state_agency_basis).';

ALTER TABLE public.customer_attribute_history DROP CONSTRAINT IF EXISTS customer_attribute_history_attribute_check;
ALTER TABLE public.customer_attribute_history ADD CONSTRAINT customer_attribute_history_attribute_check CHECK ((attribute = ANY (ARRAY[
    'billing_delivery_method'::text, 'billing_hold'::text, 'consolidate_invoices'::text, 'do_not_disconnect'::text,
    'landlord_responsible'::text, 'customer_type'::text, 'autopay_enabled'::text, 'deposit_status'::text, 'is_state_agency'::text,
    'state_agency_basis'::text])));

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
                   WHEN 'is_state_agency' THEN NEW.is_state_agency::text
                   WHEN 'state_agency_basis' THEN NEW.state_agency_basis
               END,
               NEW.status_changed_at, 'initial'
          FROM (SELECT unnest(ARRAY['billing_delivery_method', 'billing_hold', 'consolidate_invoices', 'do_not_disconnect', 'landlord_responsible', 'customer_type', 'deposit_status', 'autopay_enabled', 'is_state_agency', 'state_agency_basis']) AS attribute) a;
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
    IF OLD.is_state_agency IS DISTINCT FROM NEW.is_state_agency THEN
        INSERT INTO public.customer_attribute_history (tenant_id, customer_id, attribute, old_value, new_value, effective_at) VALUES (NEW.tenant_id, NEW.id, 'is_state_agency', OLD.is_state_agency::text, NEW.is_state_agency::text, clock_timestamp());
    END IF;
    IF OLD.state_agency_basis IS DISTINCT FROM NEW.state_agency_basis THEN
        INSERT INTO public.customer_attribute_history (tenant_id, customer_id, attribute, old_value, new_value, effective_at) VALUES (NEW.tenant_id, NEW.id, 'state_agency_basis', OLD.state_agency_basis, NEW.state_agency_basis, clock_timestamp());
    END IF;
    RETURN NULL;
END;
$$;
COMMENT ON FUNCTION public.log_customer_attribute_changes() IS
    'CI-121 (v5.4.2-06, re-issued v5.4.2-07 for is_state_agency and v5.4.2-30 for state_agency_basis): writes customer_attribute_history — the initial value of every tracked attribute at INSERT (effective_at = status_changed_at, source initial) and one row per changed attribute at UPDATE (effective_at = clock_timestamp()). Ten attributes.';

-- ----------------------------------------------------------------------------
-- 9. The standing invariants
-- ----------------------------------------------------------------------------
DO $inv30$
BEGIN
    PERFORM public.assert_tenant_isolation_invariants();
    PERFORM public.assert_rule_table_invariants();
    RAISE NOTICE 'v5.4.2-30: tenant isolation and rule-table invariants hold';
END
$inv30$;

COMMIT;
