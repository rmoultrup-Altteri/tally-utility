-- ============================================================================
-- PATCH v5.4.2-16 — places and applicability: where a premise is, and what
--                    kind of utility serves it, as dated, cited facts
-- ============================================================================
-- Authority:   Ryan, 2026-10-06: the rule-terms convention v2 (application/
--              rule-terms-convention-v2-2026-10-06.md §9, §12 step 1) puts
--              places and applicability first; audit §4 step 2 (application/
--              texas-only-architecture-audit-2026-09-28.md); Ryan's shared-
--              places proposal, 2026-09-22 (gas-billing-memory application/
--              jurisdictions-shared-place-modelling-2026-09-22.md).
-- Spec:        application/places-source-inventory-2026-10-06.md — every
--              requirement P1-P10, A1-A7, D1-D3 is either held here or a
--              stated residual (section 10).
--
-- REVIEW ROUND 1 (frozen a87f2e9f; Opus, Fable, Codex: all "not yet";
--   record: tests/v5.4.2-16/review/review-findings-16-r1.md). Folded: both
--   citation insert paths and the jurisdiction pointer run only under READ
--   COMMITTED (B1); a premise's state cannot change under its memberships
--   (B2); the time zone refuses rather than falls back to a non-uniform
--   state's zone, and reads both axes (B3); the close refuses a role row-level
--   security narrows (B4, the v5.4.2-13 guard); a sales-tax rate fact (P7) and
--   an explicit within/outside relation with an optional distance (P10, S1);
--   exclusivity groups (S2); owner/place-kind compatibility and cross-state
--   ownership (S3); keyed facts (S4); lookups refuse bad arguments (S5); the
--   jurisdiction pointer guarded and counted by the close (S6); created_by
--   stamped (S7); parent kinds (S8); evidence dates (S9); no TRUNCATE (S10);
--   time-zone names (S14); residuals A5, A6, S11-S13.
-- REVIEW ROUND 2 (frozen 24998853; all three "not yet", each on the same
--   item; record: tests/v5.4.2-16/review/review-findings-16-r2.md). Folded:
--   the time zone refuses when its most specific candidates disagree (N1); a
--   membership or profile wrong from its first day is VOIDED, stamped, and
--   every reader and exclusion ignores it (S-b); an unincorporated-area kind
--   (S-c); a profile's state is a known state (S-d); fact kinds declare value
--   ranges, evidence is dated no later than its recording, keys carry no
--   surrounding blanks, Etc/ zones are refused (S-e/f/g); a jurisdiction
--   points only at an open place (S-a); residuals R16-R18.
-- REVIEW ROUND 3 (frozen c49b1ec5; all three "not yet", each on the same
--   item; record: tests/v5.4.2-16/review/review-findings-16-r3.md). Folded:
--   a distance is a positive finite number — NaN refused (B); a state place
--   does not close under the profiles it governs, and a profile takes its
--   state place's lock (S-d after insert); the time zone refuses when a place
--   at the answering level carries no zone (a partial load is not an
--   answer); a fact key is citation-shaped, not merely space-trimmed; the
--   isolation refusal is invalid_transaction_state, as tu.sql's guards are,
--   not a retryable serialization_failure; one unincorporated area per state
--   at a time; residual R19.
-- REVIEW ROUND 4 (frozen a0b43c01; Opus and Fable "ready", Codex "not yet";
--   record: tests/v5.4.2-16/review/review-findings-16-r4.md). Folded: a
--   profile locks the state row that covers it and re-reads that same row —
--   a successor committed while it waited is never trusted unlocked (B1); who
--   owns a utility and what system it runs are separate facts: piped propane
--   and master-meter operation leave the owner types for a system kind
--   (Opus); extraterritorial and limited-purpose areas take the tax axis, so
--   each kind means one thing on both axes (Opus); a fact key needs a letter
--   or digit and takes no space after §; a membership of an unknown place is
--   refused by name; residual R20.
-- REVIEW ROUND 5 (frozen 24757cfc; all three "ready"; record:
--   tests/v5.4.2-16/review/review-findings-16-r5.md). Ryan, 2026-10-07: a
--   profile is per system kind — a utility may run a gas distribution system
--   and a piped-propane system in one state, and the profile lookup names
--   the system (Opus SF1; residual R21). Owner types say what they mean by
--   ownership (a nonprofit or trust acting for a city is the city's;
--   operator-only and other owners are residual R22). A jurisdiction pointer
--   at an unknown place is refused by name. Tests only otherwise.
--
-- ----------------------------------------------------------------------------
-- What changes
-- ----------------------------------------------------------------------------
--   * PLACES, shared by every utility (no tenant): states, counties, cities,
--     limited-purpose and extraterritorial areas, transit authorities and
--     special-purpose districts, each of a kind from a vocabulary, with a
--     jurisdiction code, a parent of an allowed kind, dated validity and a
--     citation. One Dallas, whoever serves it (Ryan, 2026-09-22).
--   * PLACE FACTS, dated and cited: a place's time zone (and whether its
--     state is in one zone), a city's census population, whether a city
--     retained gas-rate jurisdiction, whether a city or district taxes
--     residential gas, its sales-tax rate, a district's type, a county's
--     weather station, and each law a place adopted (a keyed fact). A fact is
--     a row of a fact kind whose value type the vocabulary declares, not a
--     column per fact (rule-terms v2).
--   * A PREMISE'S MEMBERSHIP in places, written by the utility, dated, with
--     dated evidence, on an AXIS — regulatory or tax — and a RELATION: within
--     the place, or known to be outside it (with the distance where a law
--     needs it). One annexation is two memberships with two dates: the
--     ordinance date for rate jurisdiction and franchise, the first day of a
--     quarter for city sales tax (Tax Code §321.102(c)-(d)) (inventory D1).
--     Absence of a membership means UNKNOWN, never outside (inventory P10).
--   * A UTILITY'S SERVICE PROFILE, dated, per service type and governing
--     state: who owns it (five owner types), what system it runs (a
--     distribution system, piped propane, a master meter — a separate fact;
--     review r4), whether it is under the state commission's jurisdiction — a separate fact, since an election changes
--     it without changing ownership — and, for a public owner, the place of
--     an allowed kind that owns it (in any state: a border city may serve
--     across the line). Texas: a city-owned gas system is not a "gas utility"
--     (Utilities Code §101.003(7)(A)) and the Railroad Commission does not
--     regulate its rates or service (§102.002) (inventory A1-A2).
--   * jurisdictions (the utility's own settings) points at a shared place.
--   * A premise's state is read as v5.4.2-12 reads it, upper(btrim(state)),
--     and cannot change to another state while the premise has memberships of
--     the old one.
--   * Lookups that REFUSE rather than guess: a premise's places on a date and
--     axis; its time zone; a utility's profile on a date.
--
--   Not here: law and tariff rows gaining owner type and jurisdiction status
--   as key columns. Each is done when its table is rebuilt on the rule-terms
--   convention (v2 §12 step 4). The America/Chicago day boundary (tu.sql
--   19184) is replaced when its law area is (audit §4); this patch gives it
--   the lookup to use.
--
-- ----------------------------------------------------------------------------
-- What the database refuses
-- ----------------------------------------------------------------------------
--   Places: any application write; an edit other than a stamped close; a
--   close by a role row-level security narrows, outside READ COMMITTED, or
--   that would cut off a membership, profile, fact or child place in force
--   after it, a profile governed by it (a state), or a jurisdiction pointing
--   at it; a parent of a kind its kind
--   does not take, of another state, or not in force over the child's range;
--   two places of one kind and code over one range; two unincorporated areas
--   of one state over one range; a code not of its kind's form (a state is
--   its two-letter code); TRUNCATE.
--   Place facts: any application write; a fact of a kind not declared for the
--   place's kind; a value not of the declared type (an IANA zone the server
--   knows); a key on an unkeyed fact or none on a keyed one; a key not of
--   citation form (letters and digits, at least one; single inner spaces,
--   . , : ; ( ) / ' _ - §; no blank at either end, none after §); outside the
--   place's range; two of one kind and key over one range; any edit but a
--   stamped close; TRUNCATE.
--   Memberships: outside READ COMMITTED; a premise of another tenant; a place
--   not in force over the whole membership; a place of another state than the
--   premise's; an axis the place's kind does not take; a kind that takes no
--   membership (a state comes from the premise's own column); two places of
--   one exclusivity group within on one axis at once (one county; a city, its
--   limited-purpose area or an extraterritorial area — not two); the same
--   place twice; a distance on a within relation, or one that is not a
--   positive finite number (NaN); evidence without its
--   reference, or dated after it was recorded; any edit but a stamped close or
--   a stamped void with its reason (once); delete.
--   Premises: a change of normalised state outside READ COMMITTED (any
--   such change, memberships or not — a behaviour change for existing
--   writers), or while the premise has an unvoided membership of a place of
--   another state.
--   Profiles: outside READ COMMITTED; two over one range for a tenant,
--   service, state and system kind; a system kind not of the profile's
--   service; an owner type that needs an owning place without one
--   (or the reverse), or an owning place of a kind the owner type does not
--   take, or not in force; a governing state with no state place in force
--   over the range (that row's lock taken shared and the row re-read, so a
--   close of it waits, and a row committed meanwhile is not trusted); evidence without its reference or dated after it was
--   recorded; any edit but a stamped close or void; delete.
--   Jurisdictions: a pointer to a state or to a place with a close date, or a
--   change of pointer outside READ COMMITTED.
--
-- PRECONDITION. None: the patch adds tables and one nullable column, and
--   changes no existing row.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 1. (No precondition)
-- ----------------------------------------------------------------------------


-- ----------------------------------------------------------------------------
-- 2. Vocabularies — platform-held, never edited
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.place_kinds (
    kind_code           text NOT NULL,
    membership_axes     text[] NOT NULL,
    exclusivity_group   text,
    parent_kinds        text[] NOT NULL,
    specificity         integer NOT NULL,
    code_pattern        text NOT NULL,
    description         text NOT NULL,
    source_note         text NOT NULL,
    created_at          timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT place_kinds_pkey PRIMARY KEY (kind_code),
    CONSTRAINT place_kinds_code_check CHECK ((kind_code ~ '^[a-z][a-z0-9_]*$'::text)),
    -- The axes a premise may belong to a place of this kind on; empty = no
    -- membership (a state comes from the premise's own state column).
    CONSTRAINT place_kinds_axes_check
        CHECK (((membership_axes <@ ARRAY['regulatory'::text, 'tax'::text]) AND (array_position(membership_axes, NULL) IS NULL))),
    CONSTRAINT place_kinds_group_check CHECK (((exclusivity_group IS NULL) OR (exclusivity_group ~ '^[a-z][a-z0-9_]*$'::text))),
    CONSTRAINT place_kinds_parents_check CHECK ((array_position(parent_kinds, NULL) IS NULL)),
    CONSTRAINT place_kinds_specificity_check CHECK ((specificity >= 0)),
    CONSTRAINT place_kinds_text_check
        CHECK (((description ~ '[[:alnum:]]'::text) AND (source_note ~ '[[:alnum:]]'::text) AND (code_pattern ~ '[[:alnum:]]'::text)))
);
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.place_kinds FROM tally_app;
GRANT SELECT ON public.place_kinds TO tally_app;
COMMENT ON TABLE public.place_kinds IS
    'v5.4.2-16 (places inventory P1-P7). The kinds of place a premise can be in. membership_axes: the axes (regulatory, tax) a premise may belong to a place of this kind on — empty for a kind derived from the premise itself (state). exclusivity_group: kinds sharing a group are mutually exclusive per premise and axis (within) — one county; one of a city, a limited-purpose area, an extraterritorial area or unincorporated territory outside any (Texas LGC ch. 42-43); NULL = places of the kind stack (districts). parent_kinds: the kinds a place of this kind may sit under (empty = no parent). specificity: higher = narrower, where the most specific place answers (a time zone). code_pattern: the form of a place''s code. Kinds are general; Texas''s are rows. Platform-held vocabulary; a new kind is a row.';

INSERT INTO public.place_kinds (kind_code, membership_axes, exclusivity_group, parent_kinds, specificity, code_pattern, description, source_note)
SELECT v.k, v.ax, v.grp, v.par, v.sp, v.pat, v.d, v.src
  FROM (VALUES
    ('state',                  ARRAY[]::text[],               NULL::text,         ARRAY[]::text[],                              0, '^[A-Z]{2}$',
     'A state. A premise''s state is its own service_locations.state, not a membership.', 'Every rule family keys on the state (inventory P1).'),
    ('county',                 ARRAY['regulatory', 'tax'],   'county',           ARRAY['state'],                              10, '^[0-9]{5}$',
     'A county, coded by its five-digit FIPS code.', 'Texas: time zone (49 CFR 71), freeze-rule weather station (16 TAC 7.460), rate notices (Utilities Code 104.103), county sales tax (inventory P2).'),
    ('municipality',           ARRAY['regulatory', 'tax'],   'municipal_status', ARRAY['state'],                              20, '^[A-Z0-9][A-Z0-9_-]*$',
     'An incorporated city or town, full-purpose limits. Regulatory and tax membership are dated separately.', 'Texas: gas rate jurisdiction (Utilities Code 102-103), franchise and street charge (Tax 182.025), city sales tax (Tax 321); the owning city of a municipal system (inventory P3).'),
    ('limited_purpose_area',   ARRAY['regulatory', 'tax'],   'municipal_status', ARRAY['municipality'],                       20, '^[A-Z0-9][A-Z0-9_-]*$',
     'Territory annexed by a city for limited purposes only; outside its full-purpose limits. On the tax axis too: what it means for a tax is the tax''s rule.', 'Texas LGC 43.130: city taxes barred; gas-rate treatment unresolved (inventory P4; review r4).'),
    ('extraterritorial_area',  ARRAY['regulatory', 'tax'],   'municipal_status', ARRAY['municipality'],                       15, '^[A-Z0-9][A-Z0-9_-]*$',
     'A city''s extraterritorial jurisdiction: unincorporated territory. On the tax axis too, so "in no city" is recorded positively and unincorporated_area keeps one meaning on both axes.', 'Texas LGC ch. 42: no gas-rate effect; where most annexations come from (inventory P5; review r4).'),
    ('unincorporated_area',    ARRAY['regulatory', 'tax'],   'municipal_status', ARRAY['state'],                              5, '^[A-Z0-9][A-Z0-9_-]*$',
     'Unincorporated territory outside any city''s extraterritorial jurisdiction. "Unincorporated" in a law''s sense is this or an extraterritorial area (a law row''s predicate).', '16 TAC 7.45 applies of its own force "in unincorporated areas" (places-sources/texas.md; review r2 S-c).'),
    ('transit_authority',      ARRAY['tax'],                 'transit_authority', ARRAY['state'],                             25, '^[A-Z0-9][A-Z0-9_-]*$',
     'A transit authority levying sales tax.', 'Texas Comptroller local sales tax jurisdictions (inventory P7).'),
    ('special_purpose_district', ARRAY['regulatory', 'tax'], NULL,               ARRAY['state', 'county', 'municipality'],    30, '^[A-Z0-9][A-Z0-9_-]*$',
     'A special-purpose district; its type is a place fact (special_district_type). Districts stack.', 'Texas Comptroller SPDs: only fire-control and crime-control districts may tax residential gas (Tax 321.105) (inventory P7).')
  ) AS v(k, ax, grp, par, sp, pat, d, src)
 WHERE NOT EXISTS (SELECT 1 FROM public.place_kinds x WHERE x.kind_code = v.k);


CREATE TABLE IF NOT EXISTS public.place_fact_kinds (
    fact_code       text NOT NULL,
    value_type      text NOT NULL,
    keyed           boolean NOT NULL,
    value_min       numeric,
    value_max       numeric,
    place_kinds     text[] NOT NULL,
    description     text NOT NULL,
    source_note     text NOT NULL,
    created_at      timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT place_fact_kinds_pkey PRIMARY KEY (fact_code),
    CONSTRAINT place_fact_kinds_code_check CHECK ((fact_code ~ '^[a-z][a-z0-9_]*$'::text)),
    CONSTRAINT place_fact_kinds_value_type_check
        CHECK ((value_type = ANY (ARRAY['text'::text, 'number'::text, 'boolean'::text, 'time_zone'::text]))),
    -- A number's range: value_min <= v < value_max (either may be open);
    -- only a number has one (review r2 S-e).
    CONSTRAINT place_fact_kinds_range_check
        CHECK ((((value_min IS NULL) AND (value_max IS NULL)) OR (value_type = 'number'::text))
           AND ((value_min IS NULL) OR (value_max IS NULL) OR (value_min < value_max))),
    CONSTRAINT place_fact_kinds_place_kinds_check
        CHECK (((cardinality(place_kinds) > 0) AND (array_position(place_kinds, NULL) IS NULL))),
    CONSTRAINT place_fact_kinds_text_check CHECK (((description ~ '[[:alnum:]]'::text) AND (source_note ~ '[[:alnum:]]'::text)))
);
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.place_fact_kinds FROM tally_app;
GRANT SELECT ON public.place_fact_kinds TO tally_app;
COMMENT ON TABLE public.place_fact_kinds IS
    'v5.4.2-16 (places inventory P3, P7-P9, A4). The facts a place can carry: the value''s type (text, number, boolean, or time_zone — an IANA zone the server knows), a number''s range (value_min <= v < value_max), whether the fact is KEYED (several at once, one per key — each law a place adopted), and the place kinds it applies to. A fact is a dated row, never a column (rule-terms v2). Platform-held vocabulary; a new fact is a row.';

INSERT INTO public.place_fact_kinds (fact_code, value_type, keyed, value_min, value_max, place_kinds, description, source_note)
SELECT v.c, v.t, v.k,
       CASE v.c WHEN 'census_population' THEN 0 WHEN 'sales_tax_rate' THEN 0 END,
       CASE v.c WHEN 'sales_tax_rate' THEN 1 END,
       v.pk, v.d, v.src
  FROM (VALUES
    ('time_zone',                     'time_zone', false, ARRAY['state', 'county', 'municipality'],
     'The IANA time zone of the place; a premise takes the most specific one in force.', '49 CFR 71 (Texas: El Paso and Hudspeth counties Mountain, the rest Central, 71.7(e)) (inventory P8).'),
    ('time_zone_uniform',             'boolean',   false, ARRAY['state'],
     'Whether the whole state is in one time zone. When false, a premise''s zone must come from a place below the state; the lookup refuses rather than take the state''s.', '49 CFR 71 (Texas: false) (review r1 B3).'),
    ('census_population',             'number',    false, ARRAY['municipality'],
     'The population at the census the law cites.', 'Texas Tax 182.022 gross receipts bands (inventory P3).'),
    ('gas_rate_jurisdiction_retained', 'boolean',  false, ARRAY['municipality'],
     'Whether the city holds original gas-rate jurisdiction inside its limits (false: surrendered to the state commission).', 'Texas Utilities Code 102.001, 103.001, 103.003 (inventory P3).'),
    ('residential_gas_taxable',       'boolean',   false, ARRAY['municipality', 'special_purpose_district'],
     'Whether the place''s sales tax reaches residential gas.', 'Texas Tax 151.317, 321.105; Comptroller list (inventory P3, P7).'),
    ('sales_tax_rate',                'number',    false, ARRAY['state', 'county', 'municipality', 'transit_authority', 'special_purpose_district'],
     'The place''s sales-tax rate, as a fraction (0.02 = 2%), dated as the tax authority publishes it.', 'Texas Tax 321.102 (quarter-start effective dates), Comptroller rate file (inventory P7; review r1 B5).'),
    ('special_district_type',         'text',      false, ARRAY['special_purpose_district'],
     'The district''s type as its enabling act names it (fire control, crime control, …).', 'Texas Comptroller SPD types (inventory P7).'),
    ('weather_station',               'text',      false, ARRAY['county'],
     'The National Weather Service station the law uses for the county.', '16 TAC 7.460 (inventory P9).'),
    ('local_adoption',                'text',      true,  ARRAY['municipality', 'county'],
     'A law the place''s governing body adopted, keyed by the law''s citation code; the value is the adopting act.', 'Illinois 305 ILCS 20/13(k) (inventory A4; review r1 S4).')
  ) AS v(c, t, k, pk, d, src)
 WHERE NOT EXISTS (SELECT 1 FROM public.place_fact_kinds x WHERE x.fact_code = v.c);


CREATE TABLE IF NOT EXISTS public.utility_owner_types (
    owner_type              text NOT NULL,
    owning_place_kinds      text[] NOT NULL,
    description             text NOT NULL,
    source_note             text NOT NULL,
    created_at              timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT utility_owner_types_pkey PRIMARY KEY (owner_type),
    CONSTRAINT utility_owner_types_code_check CHECK ((owner_type ~ '^[a-z][a-z0-9_]*$'::text)),
    CONSTRAINT utility_owner_types_kinds_check
        CHECK (((array_position(owning_place_kinds, NULL) IS NULL) AND (NOT ('state'::text = ANY (owning_place_kinds))))),
    CONSTRAINT utility_owner_types_text_check CHECK (((description ~ '[[:alnum:]]'::text) AND (source_note ~ '[[:alnum:]]'::text)))
);
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.utility_owner_types FROM tally_app;
GRANT SELECT ON public.utility_owner_types TO tally_app;
COMMENT ON TABLE public.utility_owner_types IS
    'v5.4.2-16 (places inventory A1; review r4, r5). Who OWNS a utility, as the law distinguishes it — ownership, not operation (Louisiana 45:850 turns on "owned by"); what it runs is utility_system_kinds. A single municipal/investor flag is not enough: Kansas 12-808c reaches any political subdivision, Ohio''s exclusion names only municipal corporations, Louisiana and California districts are their own classes. owning_place_kinds: the place kinds that may own a utility of this type — empty for a private owner, which names no owning place. Platform-held vocabulary.';

INSERT INTO public.utility_owner_types (owner_type, owning_place_kinds, description, source_note)
SELECT v.o, v.k, v.d, v.src
  FROM (VALUES
    ('municipal',              ARRAY['municipality'],              'Owned by a city or town — or by a nonprofit corporation or public trust acting for it (its directors appointed by the city, or the city its beneficiary): the city is the owning place. Ownership, not operation: a system a city only operates or leases out is residual R22.', 'TX Utilities Code 101.003(7)(A), 101.003(8) (nonprofit with city-appointed directors); OK 60 O.S. 176 trusts with the city as beneficiary; LA R.S. 45:850 "owned by"; OH 4905.02(A)(3), IL 3-105(b)(1) "owned or operated" (review r5).'),
    ('political_subdivision',  ARRAY['county'],                    'Owned by a county or other general political subdivision.', 'KS 12-808c "any political subdivision"; NM county systems.'),
    ('special_district',       ARRAY['special_purpose_district'],  'A special district or authority under its own enabling act, with territory of its own (gas utility district, municipal or public utility district). A public trust acting for a city is municipal; an association with no territory is residual R22.', 'LA 33:4301, 33:4306 (gas utility districts are political subdivisions); CA PUC Div. 6-7, Gov. Code 60370 (review r5).'),
    ('investor_owned',         ARRAY[]::text[],                    'A private or investor-owned utility.', 'Each state''s "public utility" / "gas utility" definition.'),
    ('cooperative',            ARRAY[]::text[],                    'A cooperative or customer-owned not-for-profit.', 'KS 66-104c; OH 4905.02(A)(2); NM 62-3-3.')
  ) AS v(o, k, d, src)
 WHERE NOT EXISTS (SELECT 1 FROM public.utility_owner_types x WHERE x.owner_type = v.o);


-- What the utility runs, apart from who owns it (review r4, Opus): the law
-- keys on the product and the operator's role as well as on the owner — New
-- Mexico 62-3-3(G)(2) takes in piped LPG "to or for the public" while (E)
-- still leaves a city's system out; Ohio 4905.90(K) says a master-meter
-- operator is not a public utility; Texas 121.211(d) names "each operator of
-- a gas distribution system and each gas master meter operator". A city may
-- own a piped-propane system, so these are not owner types.
CREATE TABLE IF NOT EXISTS public.utility_system_kinds (
    system_kind     text NOT NULL,
    service_types   text[] NOT NULL,
    description     text NOT NULL,
    source_note     text NOT NULL,
    created_at      timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT utility_system_kinds_pkey PRIMARY KEY (system_kind),
    CONSTRAINT utility_system_kinds_code_check CHECK ((system_kind ~ '^[a-z][a-z0-9_]*$'::text)),
    CONSTRAINT utility_system_kinds_services_check
        CHECK (((cardinality(service_types) > 0) AND (array_position(service_types, NULL) IS NULL))),
    CONSTRAINT utility_system_kinds_text_check CHECK (((description ~ '[[:alnum:]]'::text) AND (source_note ~ '[[:alnum:]]'::text)))
);
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.utility_system_kinds FROM tally_app;
GRANT SELECT ON public.utility_system_kinds TO tally_app;
COMMENT ON TABLE public.utility_system_kinds IS
    'v5.4.2-16 (places inventory A1; review r4). What a utility runs for a service, apart from who owns it: a distribution system, a piped-propane distribution system, or a master-meter system reselling to tenants. service_types: the services a kind applies to. Platform-held vocabulary; a new kind is a row.';

INSERT INTO public.utility_system_kinds (system_kind, service_types, description, source_note)
SELECT v.k, v.st, v.d, v.src
  FROM (VALUES
    ('distribution',               ARRAY['water', 'sewer', 'electric', 'gas', 'stormwater', 'trash', 'reclaimed_water'],
     'A system serving the public with the service. For gas: natural gas, including gas blended with propane.', 'OH 4905.03 (blended gas is natural gas); each state''s utility definition.'),
    ('piped_propane_distribution', ARRAY['gas'],
     'A system distributing propane or LP-gas by pipe to the public (not by tank or cylinder).', 'NM 62-3-3(G)(2) (in); OH 5117.01(D) "retail propane dealer that distributes propane by pipeline"; unresolved in several states (inventory gaps).'),
    ('master_meter',               ARRAY['gas'],
     'A master-meter system: gas bought through one meter and distributed to tenants.', 'OH 4905.90(K) (not a public utility; safety only); TX Utilities Code 121.211(d) ("gas master meter operator").')
  ) AS v(k, st, d, src)
 WHERE NOT EXISTS (SELECT 1 FROM public.utility_system_kinds x WHERE x.system_kind = v.k);


CREATE TABLE IF NOT EXISTS public.place_membership_evidence_kinds (
    evidence_kind   text NOT NULL,
    description     text NOT NULL,
    created_at      timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT place_membership_evidence_kinds_pkey PRIMARY KEY (evidence_kind),
    CONSTRAINT place_membership_evidence_kinds_code_check CHECK ((evidence_kind ~ '^[a-z][a-z0-9_]*$'::text)),
    CONSTRAINT place_membership_evidence_kinds_text_check CHECK ((description ~ '[[:alnum:]]'::text))
);
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.place_membership_evidence_kinds FROM tally_app;
GRANT SELECT ON public.place_membership_evidence_kinds TO tally_app;
COMMENT ON TABLE public.place_membership_evidence_kinds IS
    'v5.4.2-16 (places inventory D2). What a premise''s membership in a place rests on. Platform-held vocabulary.';

INSERT INTO public.place_membership_evidence_kinds (evidence_kind, description)
SELECT v.k, v.d
  FROM (VALUES
    ('ordinance',            'A city or county ordinance (annexation, incorporation, boundary), by number and date.'),
    ('tax_authority_notice', 'The tax authority''s published effective date (Texas: the Comptroller''s quarter, Tax 321.102).'),
    ('commission_order',     'A state commission order or tariff.'),
    ('census',               'A census designation.'),
    ('address_lookup',       'The tax authority''s or a government address locator, with its reference and retrieval date.'),
    ('utility_record',       'The utility''s own service records (onboarding, for a place nobody contests).')
  ) AS v(k, d)
 WHERE NOT EXISTS (SELECT 1 FROM public.place_membership_evidence_kinds x WHERE x.evidence_kind = v.k);


-- ----------------------------------------------------------------------------
-- 3. places — shared, dated, cited
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.places (
    id              uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    kind_code       text NOT NULL,
    state_code      text NOT NULL,
    place_code      text NOT NULL,
    name            text NOT NULL,
    parent_place_id uuid,
    effective_from  date NOT NULL,
    effective_to    date,
    source_note     text NOT NULL,
    created_at      timestamp with time zone DEFAULT now() NOT NULL,
    recorded_txid   bigint DEFAULT txid_current() NOT NULL,
    closed_at       timestamp with time zone,
    closed_by       text,
    CONSTRAINT places_pkey PRIMARY KEY (id),
    CONSTRAINT places_kind_fkey FOREIGN KEY (kind_code) REFERENCES public.place_kinds(kind_code),
    CONSTRAINT places_parent_fkey FOREIGN KEY (parent_place_id) REFERENCES public.places(id),
    CONSTRAINT places_state_code_check CHECK ((state_code ~ '^[A-Z]{2}$'::text)),
    CONSTRAINT places_text_check CHECK (((name ~ '[[:alnum:]]'::text) AND (source_note ~ '[[:alnum:]]'::text))),
    CONSTRAINT places_range_check CHECK (((effective_to IS NULL) OR (effective_to > effective_from))),
    CONSTRAINT places_no_overlap
        EXCLUDE USING gist (kind_code WITH =, state_code WITH =, place_code WITH =,
                            daterange(effective_from, effective_to, '[)'::text) WITH &&),
    -- One unincorporated area per state at a time: it is the state's
    -- territory outside every city and ETJ (review r2 S-c, enforced r3).
    CONSTRAINT places_one_unincorporated
        EXCLUDE USING gist (state_code WITH =, daterange(effective_from, effective_to, '[)'::text) WITH &&)
        WHERE (kind_code = 'unincorporated_area'::text)
);
CREATE INDEX IF NOT EXISTS idx_places_parent ON public.places USING btree (parent_place_id);
CREATE INDEX IF NOT EXISTS idx_places_state_kind ON public.places USING btree (state_code, kind_code);
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.places FROM tally_app;
GRANT SELECT ON public.places TO tally_app;
COMMENT ON TABLE public.places IS
    'v5.4.2-16 (places inventory; Ryan 2026-09-22; review r3). One row per real place, shared by every utility (no tenant): its kind, state, jurisdiction code (a state''s USPS code, a county''s FIPS code, a city''s or district''s code as its tax authority publishes it), name, parent (of a kind its kind takes, same state, in force over the child), dated validity and citation. A city that annexes keeps its row; the premises it gains get memberships. A place that dissolves or is replaced is closed (stamped, once) — never on a date that would cut off a membership, profile (owned, or governed by a state), fact or child place in force after it, nor while a utility''s jurisdiction points at it. One unincorporated area per state at a time. Written only by reviewed platform migrations, one at a time (residual R9).';

-- The lock a membership, profile or jurisdiction pointer citing a place takes
-- (shared) and a close of it takes (exclusive): tally_app cannot row-lock a
-- platform row it may not update, so the handshake is an advisory lock. Both
-- sides run only under READ COMMITTED, so each reads, after the wait, what
-- the other committed (review r1 B1: the citing side was unpinned).
CREATE OR REPLACE FUNCTION public.place_lock_key(p_place_id uuid) RETURNS bigint
    LANGUAGE sql IMMUTABLE
    SET search_path = public, pg_temp
    AS $$
    SELECT hashtextextended('places/' || p_place_id::text, 0)
$$;
COMMENT ON FUNCTION public.place_lock_key(uuid) IS
    'v5.4.2-16. The advisory-lock key for a place: a membership, profile or jurisdiction pointer citing it takes it shared, a close takes it exclusive.';

-- Every writer of a place citation, and the close, runs under READ COMMITTED.
CREATE OR REPLACE FUNCTION public.assert_place_read_committed(p_what text) RETURNS void
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
BEGIN
    IF current_setting('transaction_isolation') <> 'read committed' THEN
        RAISE EXCEPTION USING
            MESSAGE = format('%s runs only under READ COMMITTED — under %s it would read a place from a snapshot taken before a close or citation it waited for (v5.4.2-16)', p_what, current_setting('transaction_isolation')),
            -- not serialization_failure: a driver retries that, at the same
            -- isolation, forever (review r3, Fable); tu.sql's guards use this
            ERRCODE = 'invalid_transaction_state';
    END IF;
END;
$$;
COMMENT ON FUNCTION public.assert_place_read_committed(text) IS
    'v5.4.2-16 (review r1 B1, r3). Refuses (invalid_transaction_state, never a retryable code) outside READ COMMITTED: the place-lock handshake makes each side wait for the other''s commit, and only READ COMMITTED then reads what was committed.';

CREATE OR REPLACE FUNCTION public.enforce_place() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    c_close_cols CONSTANT text[] := ARRAY['effective_to', 'closed_at', 'closed_by'];
    v_kind public.place_kinds%ROWTYPE;
    v_parent public.places%ROWTYPE;
    v_conflict text;
    v_sees_all boolean;
BEGIN
    IF TG_OP = 'INSERT' THEN
        SELECT * INTO v_kind FROM public.place_kinds k WHERE k.kind_code = NEW.kind_code;
        IF NEW.place_code !~ v_kind.code_pattern OR (NEW.kind_code = 'state' AND NEW.place_code <> NEW.state_code) THEN
            RAISE EXCEPTION USING
                MESSAGE = format('place rejected: code %s is not the form of a %s code (%s%s) — v5.4.2-16', NEW.place_code, NEW.kind_code, v_kind.code_pattern,
                                 CASE WHEN NEW.kind_code = 'state' THEN '; a state''s code is its state_code' ELSE '' END),
                ERRCODE = 'check_violation';
        END IF;
        IF (NEW.parent_place_id IS NULL) <> (cardinality(v_kind.parent_kinds) = 0) THEN
            RAISE EXCEPTION USING
                MESSAGE = format('place rejected: a %s %s (place_kinds.parent_kinds) — v5.4.2-16', NEW.kind_code,
                                 CASE WHEN cardinality(v_kind.parent_kinds) = 0 THEN 'has no parent' ELSE 'sits under a ' || array_to_string(v_kind.parent_kinds, ' / ') END),
                ERRCODE = 'check_violation';
        END IF;
        IF NEW.parent_place_id IS NOT NULL THEN
            SELECT * INTO v_parent FROM public.places p WHERE p.id = NEW.parent_place_id;
            IF NOT coalesce(v_parent.kind_code = ANY (v_kind.parent_kinds), false)
               OR v_parent.state_code IS DISTINCT FROM NEW.state_code
               OR NOT coalesce(daterange(v_parent.effective_from, v_parent.effective_to, '[)') @> daterange(NEW.effective_from, NEW.effective_to, '[)'), false) THEN
                RAISE EXCEPTION USING
                    MESSAGE = format('place rejected: parent %s is not a %s of state %s in force over %s..%s — v5.4.2-16', NEW.parent_place_id, array_to_string(v_kind.parent_kinds, ' / '), NEW.state_code, NEW.effective_from, coalesce(NEW.effective_to::text, 'open')),
                    ERRCODE = 'check_violation';
            END IF;
        END IF;
        NEW.created_at    := now();
        NEW.recorded_txid := txid_current();
        NEW.closed_at     := NULL;
        NEW.closed_by     := NULL;
        RETURN NEW;
    END IF;
    IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION USING
            MESSAGE = format('place %s: never deleted — close it (effective_to) and add its successor (v5.4.2-16)', OLD.id),
            ERRCODE = 'restrict_violation';
    END IF;
    IF OLD.effective_to IS NOT NULL OR NEW.effective_to IS NULL
       OR (to_jsonb(NEW) - c_close_cols) <> (to_jsonb(OLD) - c_close_cols) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('place %s: never edited — close it (effective_to, once, nothing else) and add its successor (v5.4.2-16)', OLD.id),
            ERRCODE = 'restrict_violation';
    END IF;
    -- The citations are tenant rows: a role row-level security narrows would
    -- count only its own (review r1 B4; the v5.4.2-13 guard).
    SELECT r.rolsuper OR r.rolbypassrls INTO v_sees_all FROM pg_catalog.pg_roles r WHERE r.rolname = current_user;
    IF v_sees_all IS NOT TRUE THEN
        RAISE EXCEPTION USING
            MESSAGE = format('place %s: closing a place needs a role that sees every tenant''s citations of it (superuser or BYPASSRLS); %s does not (v5.4.2-16)', OLD.id, current_user),
            ERRCODE = 'insufficient_privilege';
    END IF;
    PERFORM public.assert_place_read_committed(format('closing place %s', OLD.id));
    PERFORM pg_advisory_xact_lock(public.place_lock_key(OLD.id));
    SELECT x.what INTO v_conflict FROM (
        SELECT 'a premise membership ' || m.id::text AS what FROM public.premise_place_memberships m
         WHERE m.place_id = OLD.id AND m.voided_at IS NULL AND (m.valid_to IS NULL OR m.valid_to > NEW.effective_to)
        UNION ALL
        SELECT 'a utility profile ' || u.id::text FROM public.utility_service_profiles u
         WHERE u.owning_place_id = OLD.id AND u.voided_at IS NULL AND (u.effective_to IS NULL OR u.effective_to > NEW.effective_to)
        UNION ALL
        -- a state governs the profiles of its state_code (review r3)
        SELECT 'a utility profile governed by it ' || g.id::text FROM public.utility_service_profiles g
         WHERE OLD.kind_code = 'state' AND g.state_code = OLD.state_code AND g.voided_at IS NULL
           AND (g.effective_to IS NULL OR g.effective_to > NEW.effective_to)
        UNION ALL
        SELECT 'a fact ' || f.id::text FROM public.place_facts f
         WHERE f.place_id = OLD.id AND (f.effective_to IS NULL OR f.effective_to > NEW.effective_to)
        UNION ALL
        SELECT 'a child place ' || c.id::text FROM public.places c
         WHERE c.parent_place_id = OLD.id AND (c.effective_to IS NULL OR c.effective_to > NEW.effective_to)
        UNION ALL
        SELECT 'a utility jurisdiction ' || j.id::text FROM public.jurisdictions j
         WHERE j.place_id = OLD.id
    ) x LIMIT 1;
    IF v_conflict IS NOT NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('place %s: %s is in force after %s; close or repoint it first (v5.4.2-16)', OLD.id, v_conflict, NEW.effective_to),
            ERRCODE = 'restrict_violation';
    END IF;
    NEW.closed_at := now();
    NEW.closed_by := session_user;
    RETURN NEW;
END;
$$;
COMMENT ON FUNCTION public.enforce_place() IS
    'v5.4.2-16. BEFORE INSERT OR UPDATE OR DELETE on places, every role. INSERT: the code is of its kind''s form (a state''s is its state_code); a parent exactly when the kind takes one, of an allowed kind, the same state, in force over the whole range; stamps. Never deleted. UPDATE: only a close (effective_to once, stamped with the session role), only by a role that sees every tenant (superuser or BYPASSRLS), only under READ COMMITTED, after the exclusive place lock, and not while a membership, profile (owned by it, or for a state governed by it), fact or child place citing it runs past the close, nor while a utility jurisdiction points at it.';
DROP TRIGGER IF EXISTS a_enforce_place ON public.places;
CREATE TRIGGER a_enforce_place BEFORE INSERT OR UPDATE OR DELETE ON public.places
    FOR EACH ROW EXECUTE FUNCTION public.enforce_place();
ALTER TABLE public.places ENABLE ALWAYS TRIGGER a_enforce_place;


-- ----------------------------------------------------------------------------
-- 4. place_facts — the map's facts, dated and cited
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.place_facts (
    id              uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    place_id        uuid NOT NULL,
    fact_code       text NOT NULL,
    fact_key        text,
    value           jsonb NOT NULL,
    effective_from  date NOT NULL,
    effective_to    date,
    source_note     text NOT NULL,
    created_at      timestamp with time zone DEFAULT now() NOT NULL,
    closed_at       timestamp with time zone,
    closed_by       text,
    CONSTRAINT place_facts_pkey PRIMARY KEY (id),
    CONSTRAINT place_facts_place_fkey FOREIGN KEY (place_id) REFERENCES public.places(id),
    CONSTRAINT place_facts_fact_fkey FOREIGN KEY (fact_code) REFERENCES public.place_fact_kinds(fact_code),
    -- A key is a citation code: letters and digits (at least one), single
    -- inner spaces and the punctuation citations use; no tab, newline,
    -- no-break space, doubled or end blank (review r2 S-g, r3: btrim strips
    -- only U+0020), no space after § (r4). Its canonical spelling is the
    -- loader's (residual R20).
    CONSTRAINT place_facts_key_check
        CHECK (((fact_key IS NULL) OR ((fact_key ~ '^[[:alnum:]§](?:[[:alnum:]§.,:;()/''_-]| (?=[^ ]))*$'::text)
                                       AND (fact_key ~ '[[:alnum:]]'::text) AND (fact_key !~ '§ '::text)))),
    CONSTRAINT place_facts_source_note_check CHECK ((source_note ~ '[[:alnum:]]'::text)),
    CONSTRAINT place_facts_range_check CHECK (((effective_to IS NULL) OR (effective_to > effective_from))),
    CONSTRAINT place_facts_no_overlap
        EXCLUDE USING gist (place_id WITH =, fact_code WITH =, (coalesce(fact_key, ''::text)) WITH =,
                            daterange(effective_from, effective_to, '[)'::text) WITH &&)
);
CREATE INDEX IF NOT EXISTS idx_place_facts_place ON public.place_facts USING btree (place_id, fact_code);
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.place_facts FROM tally_app;
GRANT SELECT ON public.place_facts TO tally_app;
COMMENT ON TABLE public.place_facts IS
    'v5.4.2-16 (places inventory P3, P7-P9, A4). A dated, cited fact about a place: its kind (place_fact_kinds), a key for a keyed kind (the law a place adopted), a value of the kind''s declared type (a JSON string, number or boolean; an IANA time zone the server knows), effective range within the place''s. One per place, kind and key at a time. Written only by reviewed platform migrations; never edited — closed (stamped, once) and superseded.';

CREATE OR REPLACE FUNCTION public.enforce_place_fact() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    c_close_cols CONSTANT text[] := ARRAY['effective_to', 'closed_at', 'closed_by'];
    v_fk public.place_fact_kinds%ROWTYPE;
    v_place public.places%ROWTYPE;
BEGIN
    IF TG_OP = 'INSERT' THEN
        SELECT * INTO v_fk FROM public.place_fact_kinds k WHERE k.fact_code = NEW.fact_code;
        SELECT * INTO v_place FROM public.places p WHERE p.id = NEW.place_id;
        IF NOT coalesce(v_place.kind_code = ANY (v_fk.place_kinds), false) THEN
            RAISE EXCEPTION USING
                MESSAGE = format('place fact rejected: %s is a fact of %s, not of a %s (v5.4.2-16)', NEW.fact_code, array_to_string(v_fk.place_kinds, ' / '), v_place.kind_code),
                ERRCODE = 'check_violation';
        END IF;
        IF v_fk.keyed <> (NEW.fact_key IS NOT NULL) THEN
            RAISE EXCEPTION USING
                MESSAGE = format('place fact rejected: %s %s (place_fact_kinds.keyed) — v5.4.2-16', NEW.fact_code,
                                 CASE WHEN v_fk.keyed THEN 'is keyed: name what it is about (fact_key)' ELSE 'takes no key' END),
                ERRCODE = 'check_violation';
        END IF;
        IF NOT coalesce((CASE v_fk.value_type
                    WHEN 'text'      THEN jsonb_typeof(NEW.value) = 'string' AND (NEW.value #>> '{}') ~ '[[:alnum:]]'
                    WHEN 'number'    THEN jsonb_typeof(NEW.value) = 'number'
                                          AND (v_fk.value_min IS NULL OR (NEW.value)::text::numeric >= v_fk.value_min)
                                          AND (v_fk.value_max IS NULL OR (NEW.value)::text::numeric <  v_fk.value_max)
                    WHEN 'boolean'   THEN jsonb_typeof(NEW.value) = 'boolean'
                    -- an IANA zone (Area/Location, never a fixed Etc/ offset) or UTC, that the server knows
                    WHEN 'time_zone' THEN jsonb_typeof(NEW.value) = 'string'
                                          AND ((NEW.value #>> '{}') ~ '^[A-Z][A-Za-z_]+/[A-Za-z0-9_/+-]+$' OR (NEW.value #>> '{}') = 'UTC')
                                          AND (NEW.value #>> '{}') !~ '^Etc/'
                                          AND EXISTS (SELECT 1 FROM pg_catalog.pg_timezone_names z WHERE z.name = NEW.value #>> '{}')
                    END), false) THEN
            RAISE EXCEPTION USING
                MESSAGE = format('place fact rejected: %s takes a %s; %s is not one (v5.4.2-16)', NEW.fact_code, v_fk.value_type, NEW.value::text),
                ERRCODE = 'check_violation';
        END IF;
        IF NOT (daterange(v_place.effective_from, v_place.effective_to, '[)') @> daterange(NEW.effective_from, NEW.effective_to, '[)')) THEN
            RAISE EXCEPTION USING
                MESSAGE = format('place fact rejected: place %s is in force %s..%s, not over the whole fact (v5.4.2-16)', NEW.place_id, v_place.effective_from, coalesce(v_place.effective_to::text, 'open')),
                ERRCODE = 'check_violation';
        END IF;
        NEW.created_at := now();
        NEW.closed_at  := NULL;
        NEW.closed_by  := NULL;
        RETURN NEW;
    END IF;
    IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION USING MESSAGE = format('place fact %s: never deleted — close it (v5.4.2-16)', OLD.id), ERRCODE = 'restrict_violation';
    END IF;
    IF OLD.effective_to IS NOT NULL OR NEW.effective_to IS NULL
       OR (to_jsonb(NEW) - c_close_cols) <> (to_jsonb(OLD) - c_close_cols) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('place fact %s: never edited — close it (effective_to, once, nothing else) and add its successor (v5.4.2-16)', OLD.id),
            ERRCODE = 'restrict_violation';
    END IF;
    NEW.closed_at := now();
    NEW.closed_by := session_user;
    RETURN NEW;
END;
$$;
COMMENT ON FUNCTION public.enforce_place_fact() IS
    'v5.4.2-16. BEFORE INSERT OR UPDATE OR DELETE on place_facts, every role. INSERT: the fact kind applies to the place''s kind; a key exactly for a keyed kind (of citation form: place_facts_key_check); the value is of the declared type (text non-blank; an IANA Area/Location zone or UTC the server knows); within the place''s range; stamps. Never deleted; the only edit is a stamped close.';
DROP TRIGGER IF EXISTS a_enforce_place_fact ON public.place_facts;
CREATE TRIGGER a_enforce_place_fact BEFORE INSERT OR UPDATE OR DELETE ON public.place_facts
    FOR EACH ROW EXECUTE FUNCTION public.enforce_place_fact();
ALTER TABLE public.place_facts ENABLE ALWAYS TRIGGER a_enforce_place_fact;

-- The vocabularies never change.
CREATE OR REPLACE FUNCTION public.enforce_place_vocabulary_immutable() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
BEGIN
    RAISE EXCEPTION USING
        MESSAGE = format('%s: vocabulary rows are never edited or deleted — places, facts, memberships and profiles cite them (v5.4.2-16)', TG_TABLE_NAME),
        ERRCODE = 'restrict_violation',
        HINT = 'A new kind or value is a new row. A row wrong from its first day is a reviewed platform repair.';
END;
$$;
COMMENT ON FUNCTION public.enforce_place_vocabulary_immutable() IS
    'v5.4.2-16. BEFORE UPDATE OR DELETE, every role, on place_kinds, place_fact_kinds, utility_owner_types, utility_system_kinds and place_membership_evidence_kinds: refused.';
DO $$
DECLARE t text;
BEGIN
    FOREACH t IN ARRAY ARRAY['place_kinds', 'place_fact_kinds', 'utility_owner_types', 'utility_system_kinds', 'place_membership_evidence_kinds'] LOOP
        EXECUTE format('DROP TRIGGER IF EXISTS a_enforce_place_vocabulary_immutable ON public.%I', t);
        EXECUTE format('CREATE TRIGGER a_enforce_place_vocabulary_immutable BEFORE UPDATE OR DELETE ON public.%I FOR EACH ROW EXECUTE FUNCTION public.enforce_place_vocabulary_immutable()', t);
        EXECUTE format('ALTER TABLE public.%I ENABLE ALWAYS TRIGGER a_enforce_place_vocabulary_immutable', t);
    END LOOP;
    -- No TRUNCATE of any platform table, by the owner either (review r1 S10).
    FOREACH t IN ARRAY ARRAY['place_kinds', 'place_fact_kinds', 'utility_owner_types', 'utility_system_kinds', 'place_membership_evidence_kinds', 'places', 'place_facts'] LOOP
        EXECUTE format('DROP TRIGGER IF EXISTS no_truncate ON public.%I', t);
        EXECUTE format('CREATE TRIGGER no_truncate BEFORE TRUNCATE ON public.%I FOR EACH STATEMENT EXECUTE FUNCTION public.enforce_no_hard_delete()', t);
        EXECUTE format('ALTER TABLE public.%I ENABLE ALWAYS TRIGGER no_truncate', t);
    END LOOP;
END;
$$;


-- ----------------------------------------------------------------------------
-- 5. premise_place_memberships — written by the utility, dated, evidenced
-- ----------------------------------------------------------------------------

COMMENT ON COLUMN public.service_locations.state IS
    'The premise''s state as entered. Every rule lookup starts here (audit rule 1: the state comes from the premise, never the utility), read normalised as upper(btrim(state)) — as v5.4.2-12 reads it; a value that is not a known state''s code resolves no state place, and the lookups refuse. Not validated on write (residual R10), but it cannot change to another state while the premise has memberships of places in the old one (v5.4.2-16). The finer places a premise is in are premise_place_memberships; city, county, inside_city_limits and franchise_city remain as entered address text and are not read for law.';

CREATE TABLE IF NOT EXISTS public.premise_place_memberships (
    id                  uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id           uuid NOT NULL,
    service_location_id uuid NOT NULL,
    place_id            uuid NOT NULL,
    axis                text NOT NULL,
    relation            text DEFAULT 'within'::text NOT NULL,
    distance_miles      numeric(8,3),
    place_kind          text NOT NULL,
    exclusivity_group   text,
    valid_from          date NOT NULL,
    valid_to            date,
    evidence_kind       text NOT NULL,
    evidence_reference  text NOT NULL,
    evidence_date       date NOT NULL,
    created_at          timestamp with time zone DEFAULT now() NOT NULL,
    created_by          uuid,
    closed_at           timestamp with time zone,
    closed_by           uuid,
    void_reason         text,
    voided_at           timestamp with time zone,
    voided_by           uuid,
    CONSTRAINT premise_place_memberships_pkey PRIMARY KEY (id),
    CONSTRAINT premise_place_memberships_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id),
    CONSTRAINT premise_place_memberships_location_fkey
        FOREIGN KEY (service_location_id, tenant_id) REFERENCES public.service_locations(id, tenant_id),
    CONSTRAINT premise_place_memberships_place_fkey FOREIGN KEY (place_id) REFERENCES public.places(id),
    CONSTRAINT premise_place_memberships_kind_fkey FOREIGN KEY (place_kind) REFERENCES public.place_kinds(kind_code),
    CONSTRAINT premise_place_memberships_evidence_fkey
        FOREIGN KEY (evidence_kind) REFERENCES public.place_membership_evidence_kinds(evidence_kind),
    CONSTRAINT premise_place_memberships_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id),
    CONSTRAINT premise_place_memberships_closed_by_fkey FOREIGN KEY (closed_by) REFERENCES public.users(id),
    CONSTRAINT premise_place_memberships_voided_by_fkey FOREIGN KEY (voided_by) REFERENCES public.users(id),
    CONSTRAINT premise_place_memberships_void_check
        CHECK ((((void_reason IS NULL) AND (voided_at IS NULL)) OR ((void_reason ~ '[[:alnum:]]'::text) AND (voided_at IS NOT NULL)))),
    CONSTRAINT premise_place_memberships_axis_check CHECK ((axis = ANY (ARRAY['regulatory'::text, 'tax'::text]))),
    -- Within the place, or known to be outside it — with the distance where a
    -- law needs one (Kansas 66-104f's 3 miles; New Mexico 3-25-3's 5).
    -- Absence of any row means unknown (review r1 S1).
    CONSTRAINT premise_place_memberships_relation_check
        CHECK ((((relation = 'within'::text) AND (distance_miles IS NULL))
             OR ((relation = 'outside'::text) AND ((distance_miles IS NULL)
                                                  -- NaN sorts above every number: refuse it by name (review r3)
                                                  OR ((distance_miles > (0)::numeric) AND (distance_miles <> 'NaN'::numeric)))))),
    CONSTRAINT premise_place_memberships_evidence_check CHECK ((evidence_reference ~ '[[:alnum:]]'::text)),
    CONSTRAINT premise_place_memberships_range_check CHECK (((valid_to IS NULL) OR (valid_to > valid_from))),
    -- The same place once per premise and axis at a time (within or outside).
    CONSTRAINT premise_place_memberships_no_repeat
        EXCLUDE USING gist (service_location_id WITH =, place_id WITH =, axis WITH =,
                            daterange(valid_from, valid_to, '[)'::text) WITH &&)
        WHERE (voided_at IS NULL),
    -- One place per exclusivity group within, per premise and axis at a time:
    -- one county; one of a city, a limited-purpose area or an
    -- extraterritorial area (review r1 S2). Districts stack.
    CONSTRAINT premise_place_memberships_exclusive
        EXCLUDE USING gist (service_location_id WITH =, exclusivity_group WITH =, axis WITH =,
                            daterange(valid_from, valid_to, '[)'::text) WITH &&)
        WHERE ((exclusivity_group IS NOT NULL) AND (relation = 'within'::text) AND (voided_at IS NULL))
);
CREATE INDEX IF NOT EXISTS idx_premise_place_memberships_tenant ON public.premise_place_memberships USING btree (tenant_id);
CREATE INDEX IF NOT EXISTS idx_premise_place_memberships_location ON public.premise_place_memberships USING btree (service_location_id, axis);
CREATE INDEX IF NOT EXISTS idx_premise_place_memberships_place ON public.premise_place_memberships USING btree (place_id);
ALTER TABLE public.premise_place_memberships ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.premise_place_memberships FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_isolation ON public.premise_place_memberships;
CREATE POLICY tenant_isolation ON public.premise_place_memberships USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));
REVOKE DELETE, TRUNCATE ON public.premise_place_memberships FROM tally_app;
COMMENT ON TABLE public.premise_place_memberships IS
    'v5.4.2-16 (places inventory P2-P7, P10, D1-D3). That a premise is within a place — or known to be outside it, with the distance where a law needs one (a positive finite number) — on an axis (regulatory: rate jurisdiction, franchise, customer law; tax: sales and local taxes), over a dated range, on dated evidence (an ordinance, the tax authority''s quarter, a commission order, an address lookup). No row means unknown, never outside. The axes are dated separately: one annexation is a regulatory membership from the ordinance date and a tax membership from the tax authority''s date (Texas Tax 321.102). place_kind and exclusivity_group are copied from the place''s kind at insert (not settable): within, at most one place per group per premise and axis at a time — one county; one of a city, its limited-purpose area or an extraterritorial area; districts stack. Written by the utility (RLS), under READ COMMITTED; never deleted; the only edits are a close (valid_to once, stamped) and a VOID for a row wrong from its first day (void_reason once, stamped) — a voided row is ignored by every exclusion, lookup, state guard and close floor, so the correct row can be recorded for the same days (review r2 S-b). The axes are independent: within a place on one axis and outside it on the other, over the same days, is accepted (D1). How the utility determined it (a boundary map, a geocoder) is outside the schema.';

-- The two edits a membership or profile takes (review r2 S-b): a close (its
-- end date, once) or a void (its reason, once — the row was wrong from its
-- first day); each stamped with when and who, nothing else changed. A voided
-- row takes no further edit.
CREATE OR REPLACE FUNCTION public.place_citation_close_or_void(p_old anyelement, p_new anyelement, p_what text, p_end_col text)
    RETURNS anyelement
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    c_close_cols CONSTANT text[] := ARRAY[p_end_col, 'closed_at', 'closed_by'];
    c_void_cols  CONSTANT text[] := ARRAY['void_reason', 'voided_at', 'voided_by'];
    o jsonb := to_jsonb(p_old);
    n jsonb := to_jsonb(p_new);
    v_user jsonb;
BEGIN
    BEGIN
        v_user := to_jsonb(NULLIF(current_setting('app.user_id', true), '')::uuid);
    EXCEPTION WHEN OTHERS THEN
        v_user := 'null'::jsonb;
    END;
    IF o ->> 'voided_at' IS NOT NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('%s %s: it was voided; a voided row takes no further edit (v5.4.2-16)', p_what, o ->> 'id'),
            ERRCODE = 'restrict_violation';
    END IF;
    IF n ->> 'void_reason' IS NOT NULL THEN
        IF (n - c_void_cols) <> (o - c_void_cols) OR (n ->> 'void_reason') !~ '[[:alnum:]]' THEN
            RAISE EXCEPTION USING
                MESSAGE = format('%s %s: a void states its reason and changes nothing else (v5.4.2-16)', p_what, o ->> 'id'),
                ERRCODE = 'restrict_violation';
        END IF;
        RETURN jsonb_populate_record(p_new, jsonb_build_object('voided_at', now(), 'voided_by', v_user));
    END IF;
    IF o ->> p_end_col IS NOT NULL OR n ->> p_end_col IS NULL OR (n - c_close_cols) <> (o - c_close_cols) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('%s %s: never edited — close it (%s, once, nothing else), void it with a reason if it was wrong from its first day, and record the correct row (v5.4.2-16)', p_what, o ->> 'id', p_end_col),
            ERRCODE = 'restrict_violation';
    END IF;
    RETURN jsonb_populate_record(p_new, jsonb_build_object('closed_at', now(), 'closed_by', v_user));
END;
$$;
COMMENT ON FUNCTION public.place_citation_close_or_void(anyelement, anyelement, text, text) IS
    'v5.4.2-16 (review r2 S-b). The edit rule for a premise place membership or a utility service profile: a close (the end column set once, nothing else) or a void (void_reason set once, nothing else), each stamped with the time and the session''s user; a voided row takes no further edit. A closed row may still be voided (its close kept): a row wrong from its first day is wrong whether or not it has ended. The compared row is the whole row, so a client echoing every column must send the stored values.';

CREATE OR REPLACE FUNCTION public.enforce_premise_place_membership() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_state text;
    v_place public.places%ROWTYPE;
    v_kind public.place_kinds%ROWTYPE;
BEGIN
    IF TG_OP = 'INSERT' THEN
        PERFORM public.assert_place_read_committed('recording a premise place membership');
        BEGIN
            NEW.created_by := NULLIF(current_setting('app.user_id', true), '')::uuid;
        EXCEPTION WHEN OTHERS THEN
            NEW.created_by := NULL;
        END;
        PERFORM public.assert_same_tenant_user(NEW.created_by, NEW.tenant_id, 'created_by');
        -- Share-lock the premise: a change of its state waits for this
        -- membership, then sees it (review r1 B2).
        SELECT upper(btrim(l.state)) INTO v_state FROM public.service_locations l
         WHERE l.id = NEW.service_location_id AND l.tenant_id = NEW.tenant_id
           FOR SHARE;
        IF NOT FOUND THEN
            RAISE EXCEPTION USING MESSAGE = format('premise place membership: service location %s not found (or not visible)', NEW.service_location_id), ERRCODE = 'foreign_key_violation';
        END IF;
        -- Shared place lock: a close of the place waits for this membership's
        -- commit, then sees it.
        PERFORM pg_advisory_xact_lock_shared(public.place_lock_key(NEW.place_id));
        SELECT * INTO v_place FROM public.places p WHERE p.id = NEW.place_id;
        IF NOT FOUND THEN
            RAISE EXCEPTION USING MESSAGE = format('premise place membership: place %s not found (v5.4.2-16)', NEW.place_id), ERRCODE = 'foreign_key_violation';
        END IF;
        SELECT * INTO v_kind FROM public.place_kinds k WHERE k.kind_code = v_place.kind_code;
        NEW.place_kind        := v_kind.kind_code;
        NEW.exclusivity_group := v_kind.exclusivity_group;
        IF NOT coalesce(NEW.axis = ANY (v_kind.membership_axes), false) THEN
            RAISE EXCEPTION USING
                MESSAGE = format('premise place membership rejected: a %s takes %s; not the %s axis (v5.4.2-16)', v_kind.kind_code,
                                 CASE WHEN cardinality(v_kind.membership_axes) = 0 THEN 'no membership (it comes from the premise''s own state)'
                                      ELSE 'membership on ' || array_to_string(v_kind.membership_axes, ' / ') END, NEW.axis),
                ERRCODE = 'check_violation';
        END IF;
        IF v_place.state_code IS DISTINCT FROM v_state THEN
            RAISE EXCEPTION USING
                MESSAGE = format('premise place membership rejected: place %s is in %s; the premise is in %s (v5.4.2-16)', NEW.place_id, v_place.state_code, v_state),
                ERRCODE = 'check_violation';
        END IF;
        IF NOT (daterange(v_place.effective_from, v_place.effective_to, '[)') @> daterange(NEW.valid_from, NEW.valid_to, '[)')) THEN
            RAISE EXCEPTION USING
                MESSAGE = format('premise place membership rejected: place %s is in force %s..%s, not over the whole membership %s..%s (v5.4.2-16)', NEW.place_id, v_place.effective_from, coalesce(v_place.effective_to::text, 'open'), NEW.valid_from, coalesce(NEW.valid_to::text, 'open')),
                ERRCODE = 'check_violation';
        END IF;
        IF NEW.evidence_date > CURRENT_DATE THEN
            RAISE EXCEPTION USING
                MESSAGE = format('premise place membership rejected: its evidence is dated %s, after it is recorded (v5.4.2-16)', NEW.evidence_date),
                ERRCODE = 'check_violation';
        END IF;
        NEW.created_at  := now();
        NEW.closed_at   := NULL;
        NEW.closed_by   := NULL;
        NEW.void_reason := NULL;
        NEW.voided_at   := NULL;
        NEW.voided_by   := NULL;
        RETURN NEW;
    END IF;
    RETURN public.place_citation_close_or_void(OLD, NEW, 'premise place membership', 'valid_to');
END;
$$;
COMMENT ON FUNCTION public.enforce_premise_place_membership() IS
    'v5.4.2-16. BEFORE INSERT OR UPDATE on premise_place_memberships. INSERT: READ COMMITTED only; created_by stamped from the session and of the tenant; the premise visible and the tenant''s, share-locked (a state change waits); the place''s lock taken shared; place_kind and exclusivity_group copied from the place''s kind; the axis one the kind takes (a state takes none); the place of the premise''s normalised state and in force over the whole membership; evidence dated no later than today; stamps (born unclosed, unvoided). UPDATE: a stamped close or void (place_citation_close_or_void). Deletes are refused by no_hard_delete.';
DROP TRIGGER IF EXISTS a_enforce_premise_place_membership ON public.premise_place_memberships;
CREATE TRIGGER a_enforce_premise_place_membership BEFORE INSERT OR UPDATE ON public.premise_place_memberships
    FOR EACH ROW EXECUTE FUNCTION public.enforce_premise_place_membership();
ALTER TABLE public.premise_place_memberships ENABLE ALWAYS TRIGGER a_enforce_premise_place_membership;

-- A premise's state does not change under its memberships (review r1 B2).
CREATE OR REPLACE FUNCTION public.enforce_service_location_state_vs_places() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_other text;
BEGIN
    IF upper(btrim(NEW.state)) IS NOT DISTINCT FROM upper(btrim(OLD.state)) THEN
        RETURN NEW;
    END IF;
    PERFORM public.assert_place_read_committed(format('changing the state of service location %s', OLD.id));
    SELECT p.state_code INTO v_other
      FROM public.premise_place_memberships m JOIN public.places p ON p.id = m.place_id
     WHERE m.service_location_id = OLD.id AND m.voided_at IS NULL AND p.state_code IS DISTINCT FROM upper(btrim(NEW.state))
     LIMIT 1;
    IF v_other IS NOT NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('service location %s: it has memberships of places in %s; its state cannot become %s under them (v5.4.2-16)', OLD.id, v_other, coalesce(quote_literal(NEW.state), 'NULL')),
            ERRCODE = 'restrict_violation',
            HINT = 'A premise wrongly placed is a new premise, or a reviewed repair; its memberships are never rewritten.';
    END IF;
    RETURN NEW;
END;
$$;
COMMENT ON FUNCTION public.enforce_service_location_state_vs_places() IS
    'v5.4.2-16 (review r1 B2). BEFORE UPDATE OF state on service_locations, every role: a change of the normalised state (upper(btrim())) runs only under READ COMMITTED and is refused while the premise has any membership of a place of another state. A membership insert share-locks the premise, so the change waits for it.';
DROP TRIGGER IF EXISTS a_enforce_service_location_state_vs_places ON public.service_locations;
CREATE TRIGGER a_enforce_service_location_state_vs_places BEFORE UPDATE OF state ON public.service_locations
    FOR EACH ROW EXECUTE FUNCTION public.enforce_service_location_state_vs_places();
ALTER TABLE public.service_locations ENABLE ALWAYS TRIGGER a_enforce_service_location_state_vs_places;


-- ----------------------------------------------------------------------------
-- 6. utility_service_profiles — who owns the utility, under whose jurisdiction
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.utility_service_profiles (
    id                       uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id                uuid NOT NULL,
    service_type             text NOT NULL,
    state_code               text NOT NULL,
    owner_type               text NOT NULL,
    system_kind              text NOT NULL,
    commission_jurisdiction  boolean NOT NULL,
    owning_place_id          uuid,
    effective_from           date NOT NULL,
    effective_to             date,
    evidence_reference       text NOT NULL,
    evidence_date            date NOT NULL,
    created_at               timestamp with time zone DEFAULT now() NOT NULL,
    created_by               uuid,
    closed_at                timestamp with time zone,
    closed_by                uuid,
    void_reason              text,
    voided_at                timestamp with time zone,
    voided_by                uuid,
    CONSTRAINT utility_service_profiles_pkey PRIMARY KEY (id),
    CONSTRAINT utility_service_profiles_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id),
    CONSTRAINT utility_service_profiles_owner_fkey FOREIGN KEY (owner_type) REFERENCES public.utility_owner_types(owner_type),
    CONSTRAINT utility_service_profiles_system_fkey FOREIGN KEY (system_kind) REFERENCES public.utility_system_kinds(system_kind),
    CONSTRAINT utility_service_profiles_place_fkey FOREIGN KEY (owning_place_id) REFERENCES public.places(id),
    CONSTRAINT utility_service_profiles_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id),
    CONSTRAINT utility_service_profiles_closed_by_fkey FOREIGN KEY (closed_by) REFERENCES public.users(id),
    CONSTRAINT utility_service_profiles_voided_by_fkey FOREIGN KEY (voided_by) REFERENCES public.users(id),
    CONSTRAINT utility_service_profiles_void_check
        CHECK ((((void_reason IS NULL) AND (voided_at IS NULL)) OR ((void_reason ~ '[[:alnum:]]'::text) AND (voided_at IS NOT NULL)))),
    CONSTRAINT utility_service_profiles_service_type_check
        CHECK ((service_type = ANY (ARRAY['water'::text, 'sewer'::text, 'electric'::text, 'gas'::text, 'stormwater'::text, 'trash'::text, 'reclaimed_water'::text]))),
    CONSTRAINT utility_service_profiles_state_code_check CHECK ((state_code ~ '^[A-Z]{2}$'::text)),
    CONSTRAINT utility_service_profiles_evidence_check CHECK ((evidence_reference ~ '[[:alnum:]]'::text)),
    CONSTRAINT utility_service_profiles_range_check CHECK (((effective_to IS NULL) OR (effective_to > effective_from))),
    CONSTRAINT utility_service_profiles_no_overlap
        EXCLUDE USING gist (tenant_id WITH =, service_type WITH =, state_code WITH =, system_kind WITH =,
                            daterange(effective_from, effective_to, '[)'::text) WITH &&)
        WHERE (voided_at IS NULL)
);
CREATE INDEX IF NOT EXISTS idx_utility_service_profiles_tenant ON public.utility_service_profiles USING btree (tenant_id);
ALTER TABLE public.utility_service_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.utility_service_profiles FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_isolation ON public.utility_service_profiles;
CREATE POLICY tenant_isolation ON public.utility_service_profiles USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));
REVOKE DELETE, TRUNCATE ON public.utility_service_profiles FROM tally_app;
COMMENT ON TABLE public.utility_service_profiles IS
    'v5.4.2-16 (places inventory A1-A2). What kind of utility serves a service type under a state''s law, dated: its owner type, the system it runs (distribution, piped propane, master meter — a separate fact: a city may own a piped-propane system; review r4), whether it is under that state commission''s jurisdiction for that service (a separate fact: Louisiana, New Mexico and Kansas elections change it without changing ownership, and Louisiana 45:850 still keys on ownership after an opt-in), and for a public owner the place that owns it — of a kind the owner type takes, in any state (a border city may serve across the line; review r1 S3). Per governing state, because a utility may serve two; per system kind, because a utility may run a gas distribution system and a piped-propane system in one state and the law reaches them differently (Ryan, 2026-10-07; which system serves a premise is residual R21). Law and tariff rows will key on owner type and jurisdiction status (rule-terms v2 §9); the core reads the profile in force on the date and refuses when there is none. Written by the utility (RLS) on dated evidence, under READ COMMITTED, for a state with a state place in force over its range (which cannot then close under it); never deleted; the only edits are a stamped close and a stamped void (a row wrong from its first day, ignored by every reader and exclusion — review r2 S-b).';

CREATE OR REPLACE FUNCTION public.enforce_utility_service_profile() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_owner public.utility_owner_types%ROWTYPE;
    v_place public.places%ROWTYPE;
    v_state_place uuid;
BEGIN
    IF TG_OP = 'INSERT' THEN
        PERFORM public.assert_place_read_committed('recording a utility service profile');
        BEGIN
            NEW.created_by := NULLIF(current_setting('app.user_id', true), '')::uuid;
        EXCEPTION WHEN OTHERS THEN
            NEW.created_by := NULL;
        END;
        PERFORM public.assert_same_tenant_user(NEW.created_by, NEW.tenant_id, 'created_by');
        -- The state row that covers the profile, its lock taken shared, then
        -- THAT row read again: a close of it waits for this profile, or this
        -- profile, having waited, sees the close and is refused. A row
        -- committed while it waited (a successor) is never trusted unlocked
        -- (review r3; r4 B1, Codex). Lock order: the state place, then the
        -- owning place.
        SELECT p.id INTO v_state_place FROM public.places p
         WHERE p.kind_code = 'state' AND p.state_code = NEW.state_code
           AND daterange(p.effective_from, p.effective_to, '[)') @> daterange(NEW.effective_from, NEW.effective_to, '[)');
        IF v_state_place IS NOT NULL THEN
            PERFORM pg_advisory_xact_lock_shared(public.place_lock_key(v_state_place));
            PERFORM 1 FROM public.places p
             WHERE p.id = v_state_place
               AND daterange(p.effective_from, p.effective_to, '[)') @> daterange(NEW.effective_from, NEW.effective_to, '[)');
            IF NOT FOUND THEN
                v_state_place := NULL;
            END IF;
        END IF;
        IF v_state_place IS NULL THEN
            RAISE EXCEPTION USING
                MESSAGE = format('utility service profile rejected: %s is no state with a place in force over %s..%s, or its state place closed while this waited (v5.4.2-16)', NEW.state_code, NEW.effective_from, coalesce(NEW.effective_to::text, 'open')),
                ERRCODE = 'check_violation',
                HINT = 'If the state place was succeeded meanwhile, record the profile again.';
        END IF;
        IF NOT EXISTS (SELECT 1 FROM public.utility_system_kinds k
                        WHERE k.system_kind = NEW.system_kind AND NEW.service_type = ANY (k.service_types)) THEN
            RAISE EXCEPTION USING
                MESSAGE = format('utility service profile rejected: a %s system is not one of %s service (utility_system_kinds.service_types) — v5.4.2-16', NEW.system_kind, NEW.service_type),
                ERRCODE = 'check_violation';
        END IF;
        IF NEW.evidence_date > CURRENT_DATE THEN
            RAISE EXCEPTION USING
                MESSAGE = format('utility service profile rejected: its evidence is dated %s, after it is recorded (v5.4.2-16)', NEW.evidence_date),
                ERRCODE = 'check_violation';
        END IF;
        SELECT * INTO v_owner FROM public.utility_owner_types o WHERE o.owner_type = NEW.owner_type;
        IF (cardinality(v_owner.owning_place_kinds) > 0) <> (NEW.owning_place_id IS NOT NULL) THEN
            RAISE EXCEPTION USING
                MESSAGE = format('utility service profile rejected: a %s owner %s (utility_owner_types.owning_place_kinds) — v5.4.2-16', NEW.owner_type,
                                 CASE WHEN cardinality(v_owner.owning_place_kinds) > 0 THEN 'names the place that owns it (owning_place_id)' ELSE 'names no owning place' END),
                ERRCODE = 'check_violation';
        END IF;
        IF NEW.owning_place_id IS NOT NULL THEN
            PERFORM pg_advisory_xact_lock_shared(public.place_lock_key(NEW.owning_place_id));
            SELECT * INTO v_place FROM public.places p WHERE p.id = NEW.owning_place_id;
            IF NOT coalesce(v_place.kind_code = ANY (v_owner.owning_place_kinds), false) THEN
                RAISE EXCEPTION USING
                    MESSAGE = format('utility service profile rejected: a %s utility is owned by a %s; place %s is a %s (v5.4.2-16)', NEW.owner_type, array_to_string(v_owner.owning_place_kinds, ' / '), NEW.owning_place_id, v_place.kind_code),
                    ERRCODE = 'check_violation';
            END IF;
            IF NOT coalesce(daterange(v_place.effective_from, v_place.effective_to, '[)') @> daterange(NEW.effective_from, NEW.effective_to, '[)'), false) THEN
                RAISE EXCEPTION USING
                    MESSAGE = format('utility service profile rejected: owning place %s is in force %s..%s, not over the whole profile %s..%s (v5.4.2-16)', NEW.owning_place_id, v_place.effective_from, coalesce(v_place.effective_to::text, 'open'), NEW.effective_from, coalesce(NEW.effective_to::text, 'open')),
                    ERRCODE = 'check_violation';
            END IF;
        END IF;
        NEW.created_at  := now();
        NEW.closed_at   := NULL;
        NEW.closed_by   := NULL;
        NEW.void_reason := NULL;
        NEW.voided_at   := NULL;
        NEW.voided_by   := NULL;
        RETURN NEW;
    END IF;
    RETURN public.place_citation_close_or_void(OLD, NEW, 'utility service profile', 'effective_to');
END;
$$;
COMMENT ON FUNCTION public.enforce_utility_service_profile() IS
    'v5.4.2-16. BEFORE INSERT OR UPDATE on utility_service_profiles. INSERT: READ COMMITTED only; created_by stamped from the session and of the tenant; a governing state with a state row in force over the range — that row''s lock taken shared, then that row re-read (a close of it waits; a successor committed meanwhile is not trusted); a system kind of the profile''s service; evidence dated no later than today; an owning place exactly when the owner type takes one — of a kind it takes, in force over the whole range, its lock taken shared; stamps (born unclosed, unvoided). UPDATE: a stamped close or void (place_citation_close_or_void). Deletes are refused by no_hard_delete.';
DROP TRIGGER IF EXISTS a_enforce_utility_service_profile ON public.utility_service_profiles;
CREATE TRIGGER a_enforce_utility_service_profile BEFORE INSERT OR UPDATE ON public.utility_service_profiles
    FOR EACH ROW EXECUTE FUNCTION public.enforce_utility_service_profile();
ALTER TABLE public.utility_service_profiles ENABLE ALWAYS TRIGGER a_enforce_utility_service_profile;

DO $$
DECLARE t text;
BEGIN
    FOREACH t IN ARRAY ARRAY['premise_place_memberships', 'utility_service_profiles'] LOOP
        EXECUTE format('DROP TRIGGER IF EXISTS no_hard_delete ON public.%I', t);
        EXECUTE format('CREATE TRIGGER no_hard_delete BEFORE DELETE ON public.%I FOR EACH ROW EXECUTE FUNCTION public.enforce_no_hard_delete()', t);
        EXECUTE format('DROP TRIGGER IF EXISTS no_truncate ON public.%I', t);
        EXECUTE format('CREATE TRIGGER no_truncate BEFORE TRUNCATE ON public.%I FOR EACH STATEMENT EXECUTE FUNCTION public.enforce_no_hard_delete()', t);
        EXECUTE format('ALTER TABLE public.%I ENABLE ALWAYS TRIGGER no_hard_delete', t);
        EXECUTE format('ALTER TABLE public.%I ENABLE ALWAYS TRIGGER no_truncate', t);
    END LOOP;
END;
$$;


-- ----------------------------------------------------------------------------
-- 7. jurisdictions points at a shared place
-- ----------------------------------------------------------------------------
-- The utility's own settings stay its own (the weather-normalization flag and
-- zone); the place's identity moves to the shared row (Ryan, 2026-09-22). The
-- pointer is optional: not every utility jurisdiction is a real place (a
-- franchise area). It names only an id, which is right for shared reference
-- data — a deliberate exception to the tenant-bound foreign key rule. A place
-- does not close while a jurisdiction points at it (review r1 S6).
ALTER TABLE public.jurisdictions ADD COLUMN IF NOT EXISTS place_id uuid;
ALTER TABLE public.jurisdictions DROP CONSTRAINT IF EXISTS jurisdictions_place_fkey;
ALTER TABLE public.jurisdictions ADD CONSTRAINT jurisdictions_place_fkey FOREIGN KEY (place_id) REFERENCES public.places(id);
CREATE INDEX IF NOT EXISTS idx_jurisdictions_place ON public.jurisdictions USING btree (place_id);
COMMENT ON COLUMN public.jurisdictions.place_id IS
    'v5.4.2-16 (Ryan 2026-09-22). The shared place this utility jurisdiction is, when it is one (a city); NULL for an area that is not a place (a franchise area). Never a state; set or changed only under READ COMMITTED and against an open place (begun, no close date), its lock taken shared; the place cannot close while pointed at. Names only an id — shared reference data has no tenant, so this is a deliberate exception to tenant-bound foreign keys. The utility''s settings (wna_applicable, wna_zone_id) stay on this row. Undated (residual R3).';

CREATE OR REPLACE FUNCTION public.enforce_jurisdiction_place() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_place public.places%ROWTYPE;
BEGIN
    IF NEW.place_id IS NULL OR (TG_OP = 'UPDATE' AND NEW.place_id IS NOT DISTINCT FROM OLD.place_id) THEN
        RETURN NEW;
    END IF;
    PERFORM public.assert_place_read_committed(format('pointing jurisdiction %s at a place', NEW.id));
    PERFORM pg_advisory_xact_lock_shared(public.place_lock_key(NEW.place_id));
    SELECT * INTO v_place FROM public.places p WHERE p.id = NEW.place_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING MESSAGE = format('jurisdiction %s: place %s not found (v5.4.2-16)', NEW.id, NEW.place_id), ERRCODE = 'foreign_key_violation';
    END IF;
    -- The pointer is undated, so its place must be open: in force today with
    -- no close date (review r2 S-a).
    IF v_place.kind_code = 'state' OR v_place.effective_to IS NOT NULL
       OR NOT coalesce(v_place.effective_from <= CURRENT_DATE, false) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('jurisdiction %s: place %s is a state, has a close date, or has not begun; a utility jurisdiction points at an open place below the state (v5.4.2-16)', NEW.id, NEW.place_id),
            ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$;
COMMENT ON FUNCTION public.enforce_jurisdiction_place() IS
    'v5.4.2-16 (review r1 S6, r2 S-a). BEFORE INSERT OR UPDATE OF place_id on jurisdictions: a new pointer runs only under READ COMMITTED, takes the place''s lock shared, and names an open place (begun, no close date) below the state.';
DROP TRIGGER IF EXISTS a_enforce_jurisdiction_place ON public.jurisdictions;
CREATE TRIGGER a_enforce_jurisdiction_place BEFORE INSERT OR UPDATE OF place_id ON public.jurisdictions
    FOR EACH ROW EXECUTE FUNCTION public.enforce_jurisdiction_place();
ALTER TABLE public.jurisdictions ENABLE ALWAYS TRIGGER a_enforce_jurisdiction_place;


-- ----------------------------------------------------------------------------
-- 8. Lookups that refuse rather than guess
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.premise_places_as_of(p_service_location_id uuid, p_on date, p_axis text)
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
    -- An invisible or missing premise has no state, so the state check
    -- below refuses it too (review r2: one refusal, not two).
    SELECT upper(btrim(l.state)) INTO v_state FROM public.service_locations l WHERE l.id = p_service_location_id;
    SELECT p.id INTO v_state_place FROM public.places p
     WHERE p.kind_code = 'state' AND p.state_code = v_state AND daterange(p.effective_from, p.effective_to, '[)') @> p_on;
    IF v_state_place IS NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('premise_places_as_of: premise %s is not found (or not visible), or its state %s is no state known on %s; its places cannot be read (v5.4.2-16)', p_service_location_id, coalesce(v_state, 'NULL'), p_on),
            ERRCODE = 'no_data_found';
    END IF;
    RETURN QUERY
    SELECT p.id, p.kind_code, p.state_code, p.place_code, p.name, k.specificity, m.relation, m.distance_miles
      FROM public.premise_place_memberships m
      JOIN public.places p ON p.id = m.place_id
      JOIN public.place_kinds k ON k.kind_code = p.kind_code
     WHERE m.service_location_id = p_service_location_id AND m.axis = p_axis AND m.voided_at IS NULL
       AND daterange(m.valid_from, m.valid_to, '[)') @> p_on
       -- defence in depth: the place in force on the date, of the premise's state
       AND daterange(p.effective_from, p.effective_to, '[)') @> p_on
       AND p.state_code = v_state
    UNION ALL
    SELECT p.id, p.kind_code, p.state_code, p.place_code, p.name, k.specificity, 'within'::text, NULL::numeric
      FROM public.places p JOIN public.place_kinds k ON k.kind_code = p.kind_code
     WHERE p.id = v_state_place;
END;
$$;
COMMENT ON FUNCTION public.premise_places_as_of(uuid, date, text) IS
    'v5.4.2-16. The places a premise is related to on a date, on an axis (regulatory or tax): its memberships in force (within, or known outside, with any distance) whose place is in force and of the premise''s state, plus its state''s place. Refuses a NULL date, a NULL or unknown axis, an invisible premise, or a state no state place answers (service_locations.state read as upper(btrim())). Invoker rights: RLS applies.';

CREATE OR REPLACE FUNCTION public.premise_time_zone_as_of(p_service_location_id uuid, p_on date) RETURNS text
    LANGUAGE plpgsql STABLE
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_tz text;
    v_kind text;
    v_uniform boolean;
    v_zones text[];
    v_unzoned text;
BEGIN
    -- Both axes place the premise (a county recorded for tax only still
    -- counts — review r1 B3). Every place it is within whose kind can carry a
    -- zone is a candidate, zone or none. The answering level is the most
    -- specific one where some candidate carries a zone: a level where none
    -- does falls through (a city with no zone answers by its county). At that
    -- level every candidate must carry one, and all must agree: two counties
    -- on two axes with different zones (review r2 N1), or one with a zone and
    -- one without (r3: a partial load), are refused, not tie-broken. A more
    -- specific zone outranks a less specific one by design: a city's zone
    -- answers over its county's, and the refusals apply only at the
    -- answering level (a county conflict under a zoned city is not read).
    WITH cand AS (
        SELECT DISTINCT pl.place_id, pl.kind_code, pl.specificity, pl.name, f.value #>> '{}' AS tz
          FROM (SELECT * FROM public.premise_places_as_of(p_service_location_id, p_on, 'regulatory')
                UNION ALL
                SELECT * FROM public.premise_places_as_of(p_service_location_id, p_on, 'tax')) pl
          LEFT JOIN public.place_facts f ON f.place_id = pl.place_id AND f.fact_code = 'time_zone'
                                        AND daterange(f.effective_from, f.effective_to, '[)') @> p_on
         WHERE pl.relation = 'within'
           AND pl.kind_code = ANY ((SELECT k.place_kinds FROM public.place_fact_kinds k WHERE k.fact_code = 'time_zone')::text[])
    )
    SELECT array_agg(DISTINCT c.tz) FILTER (WHERE c.tz IS NOT NULL),
           min(c.kind_code),
           string_agg(c.name, ', ') FILTER (WHERE c.tz IS NULL)
      INTO v_zones, v_kind, v_unzoned
      FROM cand c
     WHERE c.specificity = (SELECT max(z.specificity) FROM cand z WHERE z.tz IS NOT NULL);
    IF v_unzoned IS NOT NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('premise %s on %s: %s, as specific as the places that carry its time zone, carries none; the lookup refuses rather than let the other answer (v5.4.2-16)', p_service_location_id, p_on, v_unzoned),
            ERRCODE = 'no_data_found',
            HINT = 'Load that place''s time_zone fact, or correct the membership that is wrong (close or void it).';
    END IF;
    IF cardinality(v_zones) > 1 THEN
        RAISE EXCEPTION USING
            MESSAGE = format('premise %s on %s: the places it is most specifically within disagree on its time zone (%s); the lookup refuses rather than choose (v5.4.2-16)', p_service_location_id, p_on, array_to_string(v_zones, ', ')),
            ERRCODE = 'cardinality_violation',
            HINT = 'Correct the membership that is wrong (close or void it).';
    END IF;
    v_tz := v_zones[1];
    -- Only the state answered: that is an answer only for a state in one
    -- zone. Texas is not (El Paso and Hudspeth are Mountain): a premise with
    -- no county or city recorded is unknown, not Central.
    IF v_kind = 'state' THEN
        SELECT (f.value)::text::boolean INTO v_uniform
          FROM public.premise_places_as_of(p_service_location_id, p_on, 'regulatory') pl
          JOIN public.place_facts f ON f.place_id = pl.place_id AND f.fact_code = 'time_zone_uniform'
                                   AND daterange(f.effective_from, f.effective_to, '[)') @> p_on
         WHERE pl.kind_code = 'state';
        IF v_uniform IS NOT TRUE THEN
            v_tz := NULL;
        END IF;
    END IF;
    IF v_tz IS NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('no time zone can be read for premise %s on %s: no place it is within carries one, or only its state does and the state is not in one zone (v5.4.2-16)', p_service_location_id, p_on),
            ERRCODE = 'no_data_found',
            HINT = 'Record the premise''s county (or city) membership; or, for a state in one zone, its time_zone_uniform fact.';
    END IF;
    RETURN v_tz;
END;
$$;
COMMENT ON FUNCTION public.premise_time_zone_as_of(uuid, date) IS
    'v5.4.2-16 (places inventory P8; review r1 B3, r2 N1, r3). The IANA time zone of a premise on a date: the time_zone fact of the most specific places it is within, on either axis, in force, at the most specific level where any carries one — refused if they disagree, or if another place at that level carries none (a city''s zone outranks its county''s; a level with no zone falls through). The state''s own zone answers only where the state''s time_zone_uniform fact is true; otherwise, and when nothing answers, it refuses — never assumes. The replacement for the America/Chicago constant (tu.sql 19184), used when that law area is rebuilt.';

-- The lookup names the system (Ryan, 2026-10-07): drop the r1-r5 signature.
DROP FUNCTION IF EXISTS public.utility_service_profile_as_of(uuid, text, text, date);
CREATE OR REPLACE FUNCTION public.utility_service_profile_as_of(p_tenant_id uuid, p_service_type text, p_system_kind text, p_state_code text, p_on date)
    RETURNS public.utility_service_profiles
    LANGUAGE plpgsql STABLE
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v public.utility_service_profiles%ROWTYPE;
BEGIN
    IF p_tenant_id IS NULL OR p_service_type IS NULL OR p_system_kind IS NULL OR p_state_code IS NULL OR p_on IS NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = 'utility_service_profile_as_of: tenant, service type, system kind, state and date are all required (v5.4.2-16)',
            ERRCODE = 'invalid_parameter_value';
    END IF;
    SELECT * INTO v FROM public.utility_service_profiles u
     WHERE u.tenant_id = p_tenant_id AND u.service_type = p_service_type AND u.system_kind = p_system_kind
       AND u.state_code = p_state_code AND u.voided_at IS NULL AND daterange(u.effective_from, u.effective_to, '[)') @> p_on;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING
            MESSAGE = format('no utility profile is recorded (or visible) for tenant %s, %s (%s) in %s on %s: who owns it and whose jurisdiction it is under decide which law applies (v5.4.2-16)', p_tenant_id, p_service_type, p_system_kind, p_state_code, p_on),
            ERRCODE = 'no_data_found';
    END IF;
    RETURN v;
END;
$$;
COMMENT ON FUNCTION public.utility_service_profile_as_of(uuid, text, text, text, date) IS
    'v5.4.2-16 (places inventory A1-A2; Ryan 2026-10-07). The utility''s profile (owner type, commission jurisdiction, owning place) for a service and system kind under a state''s law on a date; the caller names the system (residual R21). Refuses NULL arguments, and when none is recorded or visible — never assumes one. Invoker rights: RLS applies (another tenant''s profile is not found).';


-- ----------------------------------------------------------------------------
-- 9. Seed: the time-zone facts Texas needs
-- ----------------------------------------------------------------------------
-- Texas (not in one zone) and its two Mountain-time counties (49 CFR
-- 71.7(e)); every other place is data a reviewed migration loads from its
-- publisher (residual R2). A Texas premise's time zone therefore needs its
-- county (or city) recorded.
DO $$
DECLARE
    v_tx uuid;
    v_cty uuid;
    r record;
    c_from CONSTANT date := DATE '1900-01-01';
BEGIN
    SELECT id INTO v_tx FROM public.places WHERE kind_code = 'state' AND place_code = 'TX' AND effective_to IS NULL;
    IF v_tx IS NULL THEN
        INSERT INTO public.places (kind_code, state_code, place_code, name, effective_from, source_note)
        VALUES ('state', 'TX', 'TX', 'Texas', c_from, 'State of Texas.') RETURNING id INTO v_tx;
        INSERT INTO public.place_facts (place_id, fact_code, value, effective_from, source_note) VALUES
          (v_tx, 'time_zone', to_jsonb('America/Chicago'::text), c_from, '49 CFR 71.7: Central time, except the counties in Mountain time.'),
          (v_tx, 'time_zone_uniform', 'false'::jsonb, c_from, '49 CFR 71.7(e): El Paso and Hudspeth counties are Mountain time.');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.places WHERE kind_code = 'unincorporated_area' AND state_code = 'TX') THEN
        INSERT INTO public.places (kind_code, state_code, place_code, name, parent_place_id, effective_from, source_note)
        VALUES ('unincorporated_area', 'TX', 'UNINCORPORATED', 'Unincorporated Texas (outside any city''s extraterritorial jurisdiction)', v_tx, c_from,
                'Texas territory in no city and no city''s ETJ (LGC ch. 42); 16 TAC 7.45 applies of its own force in unincorporated areas.');
    END IF;
    FOR r IN SELECT * FROM (VALUES ('48141', 'El Paso County'), ('48229', 'Hudspeth County')) AS v(fips, name) LOOP
        IF NOT EXISTS (SELECT 1 FROM public.places WHERE kind_code = 'county' AND state_code = 'TX' AND place_code = r.fips) THEN
            INSERT INTO public.places (kind_code, state_code, place_code, name, parent_place_id, effective_from, source_note)
            VALUES ('county', 'TX', r.fips, r.name, v_tx, c_from, 'Texas county (FIPS ' || r.fips || ').') RETURNING id INTO v_cty;
            INSERT INTO public.place_facts (place_id, fact_code, value, effective_from, source_note)
            VALUES (v_cty, 'time_zone', to_jsonb('America/Denver'::text), c_from, '49 CFR 71.7(e): El Paso and Hudspeth counties, Texas, are in the Mountain time zone.');
        END IF;
    END LOOP;
END;
$$;


-- ----------------------------------------------------------------------------
-- 10. Residuals, stated
-- ----------------------------------------------------------------------------
-- R1. LAW ROWS DO NOT YET KEY ON OWNER TYPE. deposit_rules (v5.4.2-15
--     draft), backbilling_rules (-13) and the meter-test thresholds (-12) key
--     on state only. Each gains owner type and commission jurisdiction when it
--     is rebuilt on the rule-terms convention (v2 §12 step 4). Until then a
--     Texas law row describes an investor-owned gas utility; a city system's
--     policy is its own (inventory §1: Utilities Code §101.003(7)(A)).
-- R2. PLACES ARE DATA. Only Texas and its two Mountain-time counties are
--     seeded. Counties, cities, districts and tax jurisdictions, with their
--     facts (time zones, sales-tax rates by quarter), are loaded by reviewed
--     migrations from their publishers (Census FIPS, the Comptroller's files).
--     Texas is seeded from 1900-01-01 and a child lies within its parent, so
--     a county dated from its creation (1836-1931) is refused: the loader
--     dates places from no earlier than 1900 — no bill reads a place before
--     it (review r3, Fable N5).
-- R3. UTILITY RATE AREAS (inventory P6). A utility's inside/outside or
--     environs rate areas stay its jurisdictions rows (undated, as v5.4.0-03
--     built them), pointing at a place where one exists. Dating them is its
--     own change when rates are rebuilt.
-- R4. THE ADDRESS COLUMNS STAY. service_locations.city, county,
--     inside_city_limits and franchise_city remain as entered text; nothing
--     reads them for law. franchise_fee_rules still names its city by text;
--     it moves to a place when franchise fees are rebuilt (audit §4).
-- R5. AMERICA/CHICAGO STAYS UNTIL ITS AREA IS REBUILT. The state-agency
--     day boundary (v5.4.2-07, tu.sql 19184) is keyed on a customer, not a
--     premise; which premise's zone applies is a decision for that area.
--     premise_time_zone_as_of is the lookup it will use.
-- R6. LIMITED-PURPOSE AREAS (inventory P4). Whether one counts as "within
--     the municipality" for Texas gas-rate jurisdiction is unresolved; the
--     place kind exists, the law's answer is a later rule row.
-- R7. CUSTOMER COUNTS AND SIZE THRESHOLDS (inventory A3). A law's threshold
--     is a terms parameter; the utility's count is derived from its records by
--     the core, reproducibly (it records its inputs), not stored here.
-- R8. MARKET ROLE (inventory A7, Georgia's distributor/marketer split) and
--     boundary geometry are out of scope. A membership records what was
--     determined and on what evidence, not how.
-- R9. PLATFORM ROWS RACE ONLY PLATFORM ROWS. A place's facts and child places
--     are written by reviewed migrations, which run one at a time (a deploy
--     discipline, not a lock); a close reads them as committed (as
--     v5.4.2-13's R12). Memberships, profiles and jurisdiction pointers,
--     written at run time, take the place lock.
-- R10. THE PREMISE'S STATE IS NOT VALIDATED ON WRITE. v5.4.2-12 reads it
--     normalised and its battery keeps dirty values (' tx ', 'Texas') on
--     purpose; this patch reads it the same way, an unrecognised value makes
--     every lookup refuse, and the state cannot change under memberships.
--     Validating it on write (and settling -12's fixtures) belongs to address
--     intake.
-- R11. THE ENFORCING BODY (inventory A5) is an attribute of each law row's
--     rule set (the commission, a city council, the utility's own board as an
--     appeal forum, a human-services agency), carried in its terms and
--     citation when that law area is rebuilt — not a place fact.
-- R12. CUSTOMER AND METER ATTRIBUTES (inventory A6): residential use per
--     meter per period, heating source, master metering, service-member and
--     family-violence status. Existing customer and meter facts are mapped to
--     each law area's needs when it is rebuilt.
-- R13. ADVISORY LOCKS ARE COOPERATIVE (review r1 S11). Any session may take
--     pg_advisory_lock on a place's key and stall its writers; the same holds
--     for every advisory protocol here (-15's rate lock). Statement timeouts
--     bound it; revoking the advisory-lock functions from tally_app is a
--     platform-wide decision, not this patch's.
-- R14. A CLOSE MAY BE BACKDATED (review r1 S12). Nothing cites a membership
--     or profile yet. When law decisions do, they record their inputs, and a
--     close floor follows (the v5.4.2-13 pattern).
-- R15. COMMISSION JURISDICTION THAT DEPENDS ON THE PREMISE (review r1 S13;
--     Kansas 66-104f: more than three miles outside the city) is a law row's
--     predicate over a membership's relation and distance, written when law
--     rows key on applicability.

-- R16. AN OUTSIDE RELATION IS TO A PLACE OF THE PREMISE'S STATE (review r2
--     N2). A city owning service across a state line cannot record a premise
--     there as outside the city with a distance: the distance laws in hand
--     (Kansas 66-104f, New Mexico 3-25-3) measure from a city of the same
--     state. A cross-state measure is added when a source needs one.
-- R17. ONE CODE PER PLACE (review r2 S-i). A county's code is its FIPS code,
--     not tied here to its state's prefix; reviewed migrations load from
--     Census. A second publisher's code (the Comptroller's) becomes a keyed
--     place fact when a loader needs it.
-- R18. A DEADLOCK CAN END A WRITER (review r2 S-j). A transaction that records
--     a membership (share-locking the premise) and then changes the premise's
--     state, run against another doing the same, deadlocks; PostgreSQL aborts
--     one, which retries. So can two migrations closing two places in
--     opposite orders, or one closing an owning place and its state in one
--     transaction against a profile insert (which locks the state, then the
--     owning place): migrations close in that order (review r5).
-- R19. A STATE PLACE IS NOT SUCCEEDED UNDER ITS PROFILES (review r3). A
--     profile lies within one state place, and that place cannot close while
--     a profile it governs runs past the close; so a state place is replaced
--     only once its profiles are closed. No source has a state's identity
--     change; if one does, coverage by the union of state rows replaces
--     containment in one.
-- R20. A FACT KEY'S SPELLING IS THE LOADER'S (review r4). The check fixes a
--     key's shape, not its canonical form: "16 TAC 7.45" and "16 tac 7.45"
--     are two keys. Loaders write a law's citation code as its publisher
--     prints it, with an ASCII hyphen for a range (never an en dash), no
--     space after §, ASCII letters and digits only (the check's classes admit
--     Unicode look-alikes and a doubled or trailing §).
-- R21. WHICH SYSTEM SERVES A PREMISE IS NOT YET RECORDED (Ryan, 2026-10-07).
--     A profile is per system kind, and the lookup takes the system kind;
--     the caller names it. A premise's link to the system serving it is a
--     service-point fact, added when service points are modelled; until then
--     a utility with one system per service and state names that one.
-- R22. OWNERS NOT YET TYPED (review r5). One owning place is recorded, even
--     where several cities own a system jointly. A system a city only
--     operates, or leases to a nonprofit (Arkansas 23-4-201(b)); a New Mexico
--     natural gas association (NMSA 3-28); an Illinois public institution of
--     higher education (3-105(b)(1)); a Kansas township (12-808c) — each
--     becomes a vocabulary row (owner type or place kind), additively, when a
--     customer has one.

-- ----------------------------------------------------------------------------
-- 11. The AC-32 tail
-- ----------------------------------------------------------------------------
-- Two new tenant tables. The assertion raises if either lacks RLS, FORCE, or
-- the single canonical policy. The six platform tables carry no tenant_id and
-- are read-only to tally_app.

SELECT public.assert_tenant_isolation_invariants();

-- ============================================================================
-- END PATCH v5.4.2-16
-- ============================================================================
