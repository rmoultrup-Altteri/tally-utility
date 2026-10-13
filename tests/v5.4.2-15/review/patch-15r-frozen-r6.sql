-- ============================================================================
-- PATCH v5.4.2-15 — deposits at the rule-terms convention: the law is a document,
--                    the platform keeps it, the core evaluates it
-- ============================================================================
-- Authority:   Ryan, 2026-09-28 ("nothing is live"; the database no longer
--              decides deposit law) and 2026-10-12 (the rewrite's five
--              decisions, below). This REPLACES the first draft of -15 (typed
--              columns and child tables, never mirrored) with the same
--              intent on the convention -17 laid down and -18 proved.
-- Spec:        application/deposits-terms-v1-design-2026-10-12.md; the tests
--              tests/v5.4.2-15/battery-15r.sql and migration-15r.py.
--
-- ----------------------------------------------------------------------------
-- What changes
-- ----------------------------------------------------------------------------
--   * Two KINDS. `deposit` v1 (law): what a state's law says about a deposit
--     for one customer class and one basis — the cap, the triggers for an
--     additional deposit, the waivers, the interest, the return rules and the
--     instalment schedule — as a document validated against
--     law/deposit/deposit.v1.schema.json (embedded here, compared by CI).
--     `deposit_tariff` v1 (tariff): the utility's own deposit record for one of
--     its own categories — the amount, its triggers, its waivers (grounds in
--     its own name), its instalments — law/deposit/deposit_tariff.v1.schema.json.
--   * FOUR FACETS of `deposit` (trigger_codes, waiver_classes, return_reasons,
--     cap_part_ids), checked against the vocabularies where the rule is written.
--   * deposit_rules is a REGISTERED LAW TABLE keyed by (customer_class, basis):
--     eight rows for the investor-owned and cooperative Texas gas utilities
--     (16 TAC 7.45 and 11 U.S.C. 366, exactly what -06 enforced) and eight
--     delegations for a city-owned system (7.45 does not bind it: its deposit
--     policy is its tariff).
--   * deposit_utility_categories: the utility names its own deposit categories
--     (owner, renter, small commercial …), each mapped to exactly one law class.
--     deposit_tariffs is a REGISTERED TARIFF TABLE keyed by that category and
--     measured against the law by deposit_tariff_compare.
--   * A published value, tx_deposit_interest_rate; the utility's own rate table
--     gains state, service and an optional category, and a rate below a floor
--     the law sets is refused where it is written (decision 4).
--   * deposits, deposit_events, the return-due record: every record cites the
--     LAW ROW it was decided under (and the tariff row when one applied), the
--     component of the document that governed, and the core version.
--   * The -06 Texas law leaves the database (the functions and the refund-due
--     view); the first draft's vocabularies are re-issued narrower.
--
-- Ryan's five decisions of 2026-10-12: (1) customer type stays on the
--   utility's own interest rate; (2) the utility's deposit rules are one
--   tariff record per utility, state, service and category; (3) version 1
--   holds vocabulary additions, a flexible condition tree and an interest
--   method union, with six shapes refused on purpose; (4) a state-set interest
--   rate is a floor the utility's own rate may not go below; (5) a utility
--   defines its own deposit categories, each mapped to one law class.
--
-- PRECONDITION. Nothing is live (Ryan, 2026-09-28): no deposit, waiver or rate
--   exists outside a test. The patch refuses to run over any non-legacy
--   deposit, any waiver determination or any utility rate row, rather than
--   invent the law row, state and service the core never recorded. -06's
--   legacy_unknown deposits are carried unchanged: they cite no law row.
--   A second run finds the tables there, says so, and skips the whole patch. The
--   skip is psql's (\gset / \if): apply this file with psql, not a runner that
--   sends it as one statement, and not concatenated into a script that cannot
--   run psql meta-commands.
--   Applied by a role that sees every tenant (superuser or BYPASSRLS), under
--   READ COMMITTED.
-- ============================================================================

-- A second application finds the tables there and skips the whole patch (psql's \if): nothing is re-installed, so a
-- later patch's version of a function is never overwritten by this one.
SELECT to_regclass('public.deposit_rules') IS NOT NULL AND to_regclass('public.deposit_tariffs') IS NOT NULL AS already \gset
\if :already
DO $$ BEGIN RAISE NOTICE 'v5.4.2-15: deposit_rules is already on the rule-terms convention; nothing to do'; END $$;
\else
BEGIN;

-- ----------------------------------------------------------------------------
-- 1. Precondition
-- ----------------------------------------------------------------------------
DO $$
DECLARE
    v_dep  bigint;
    v_wvr  bigint;
    v_rate bigint;
    v_acc  bigint;
BEGIN
    IF to_regclass('public.rule_tables') IS NULL OR to_regprocedure('public.rule_table_register(regclass,text,text,text[],text[],regprocedure,regprocedure,regclass,regprocedure,regprocedure)') IS NULL THEN
        RAISE EXCEPTION 'v5.4.2-15 needs the rule-terms template of v5.4.2-17 and -18 applied first'
            USING ERRCODE = 'object_not_in_prerequisite_state';
    END IF;
    -- The counts below are only true for a role that sees every tenant.
    IF NOT coalesce((SELECT r.rolsuper OR r.rolbypassrls FROM pg_roles r WHERE r.rolname = current_user), false) THEN
        RAISE EXCEPTION 'v5.4.2-15 is applied by a role that sees every tenant (superuser or BYPASSRLS): its precondition counts rows under row security otherwise'
            USING ERRCODE = 'insufficient_privilege';
    END IF;
    SELECT count(*) INTO v_dep FROM public.deposits d WHERE d.basis <> 'legacy_unknown';
    SELECT count(*) INTO v_wvr FROM public.deposit_waiver_determinations;
    SELECT count(*) INTO v_rate FROM public.deposit_interest_rates;
    SELECT count(*) INTO v_acc FROM public.deposit_events e WHERE e.event_type = 'interest_accrued';
    IF v_dep + v_wvr + v_rate + v_acc > 0 THEN
        RAISE EXCEPTION USING
            MESSAGE = format('v5.4.2-15: %s deposit(s), %s waiver determination(s), %s utility rate row(s) and %s interest accrual(s) exist; this patch records the law row, state and service each was decided under, and will not invent them', v_dep, v_wvr, v_rate, v_acc),
            ERRCODE = 'object_not_in_prerequisite_state',
            HINT = 'Nothing is live (2026-09-28). A database with real deposits needs a backfill that the core performs, citing law rows — write it before applying.';
    END IF;
END;
$$;


-- ----------------------------------------------------------------------------
-- 2. Vocabularies — platform-held, never edited
-- ----------------------------------------------------------------------------
-- The v5.4.2-13 pattern: no tenant_id, tally_app and tally_core read and cannot
-- write, a new value is a row (and, where the core must act on it, a core
-- change). Never edited or deleted (the template's vocabulary guard).

CREATE TABLE IF NOT EXISTS public.deposit_bases (
    basis_code       text NOT NULL,
    is_federal       boolean NOT NULL,
    insertable       boolean NOT NULL,
    requires_trigger boolean NOT NULL,
    description      text NOT NULL,
    created_at       timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT deposit_bases_pkey PRIMARY KEY (basis_code),
    CONSTRAINT deposit_bases_code_check CHECK ((basis_code ~ '^[a-z][a-z0-9_]*$'::text)),
    CONSTRAINT deposit_bases_description_check CHECK ((description ~ '[[:alnum:]]'::text))
);
COMMENT ON TABLE public.deposit_bases IS
    'v5.4.2-15. Why a deposit was taken — the basis decides which law row governs it. is_federal: a federal basis (11 U.S.C. 366 adequate assurance), not a state rule. insertable: false for a basis that exists only for carried history (legacy_unknown, -06''s backfill): no new deposit may take it. requires_trigger: a deposit of this basis names the event that gave rise to it (deposits.trigger_basis), and only such a deposit names one. What a basis DOES in a state is its law row. Platform-held vocabulary; a new basis is a row plus a core change.';
INSERT INTO public.deposit_bases (basis_code, is_federal, insertable, requires_trigger, description)
SELECT v.code, v.fed, v.ins, v.trg, v.description
  FROM (VALUES
    ('credit_evaluation',      false, true,  false, 'Required on the customer''s credit evaluation (new service).'),
    ('additional_trigger',     false, true,  true,  'An additional deposit after a triggering event (usage, NSF, disconnection history, a broken payment arrangement): see deposit_triggers.'),
    ('tariff',                 false, true,  false, 'Required by the utility''s filed tariff.'),
    ('adequate_assurance_366', true,  true,  false, 'Adequate assurance of payment demanded of a debtor in bankruptcy (11 U.S.C. 366).'),
    ('legacy_unknown',         false, false, false, 'Carried from customers.deposit_* by v5.4.2-06; the basis was never recorded. Not insertable.')
  ) AS v(code, fed, ins, trg, description)
 WHERE NOT EXISTS (SELECT 1 FROM public.deposit_bases b WHERE b.basis_code = v.code);

CREATE TABLE IF NOT EXISTS public.deposit_triggers (
    trigger_code text NOT NULL,
    description  text NOT NULL,
    created_at   timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT deposit_triggers_pkey PRIMARY KEY (trigger_code),
    CONSTRAINT deposit_triggers_code_check CHECK ((trigger_code ~ '^[a-z][a-z0-9_]*$'::text)),
    CONSTRAINT deposit_triggers_description_check CHECK ((description ~ '[[:alnum:]]'::text))
);
COMMENT ON TABLE public.deposit_triggers IS
    'v5.4.2-15. The events that may give rise to an additional deposit. A law row''s (or a tariff''s) trigger names one by code and says, as a condition, when it fires; whether it fires is the core''s. Platform-held vocabulary.';
INSERT INTO public.deposit_triggers (trigger_code, description)
SELECT v.code, v.description
  FROM (VALUES
    ('nsf',                'Payments returned unpaid (NSF).'),
    ('disconnect_history', 'Disconnection for nonpayment in the customer''s history.'),
    ('broken_dpa',         'A broken deferred payment arrangement.'),
    ('usage_doubled',      'Actual use at least the rule''s multiple of the estimated billing the deposit was based on (16 TAC 7.45(5)(C)(ii): twice; Kyle question K9 — why decision table #55 omits it).')
  ) AS v(code, description)
 WHERE NOT EXISTS (SELECT 1 FROM public.deposit_triggers t WHERE t.trigger_code = v.code);

CREATE TABLE IF NOT EXISTS public.deposit_customer_classes (
    state_code   text NOT NULL,
    service_type text NOT NULL,
    class_code   text NOT NULL,
    description  text NOT NULL,
    source_note  text NOT NULL,
    created_at   timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT deposit_customer_classes_pkey PRIMARY KEY (state_code, service_type, class_code),
    CONSTRAINT deposit_customer_classes_state_code_check CHECK ((state_code ~ '^[A-Z]{2}$'::text)),
    CONSTRAINT deposit_customer_classes_service_type_check
        CHECK ((service_type = ANY (ARRAY['water'::text, 'sewer'::text, 'electric'::text, 'gas'::text, 'stormwater'::text, 'trash'::text, 'reclaimed_water'::text]))),
    CONSTRAINT deposit_customer_classes_code_check CHECK ((class_code ~ '^[a-z][a-z0-9_]*$'::text)),
    CONSTRAINT deposit_customer_classes_description_check CHECK ((description ~ '[[:alnum:]]'::text)),
    CONSTRAINT deposit_customer_classes_source_note_check CHECK ((source_note ~ '[[:alnum:]]'::text))
);
COMMENT ON TABLE public.deposit_customer_classes IS
    'v5.4.2-15. The customer classes a state''s deposit law distinguishes, per service type. A law row is for one; a utility''s own deposit category maps to exactly one (deposit_utility_categories.law_class). Law, platform-held. Which class an account is in is the core''s call from the utility''s category; the deposit records the answer.';
INSERT INTO public.deposit_customer_classes (state_code, service_type, class_code, description, source_note)
SELECT v.s, v.svc, v.code, v.description, v.source_note
  FROM (VALUES
    ('TX', 'gas', 'residential',     'Residential customers.',
     '16 TAC 7.45 deposit provisions; the cap of one-sixth of estimated annual billing applies to residential deposits (-06 D-41; decision table #53 rank 8). Which classes the other provisions reach is Kyle question K1.'),
    ('TX', 'gas', 'non_residential', 'Every other customer.',
     '16 TAC 7.45; -06 applied the waiver, interest and refund provisions to every class and the cap to residential only (Kyle question K1).')
  ) AS v(s, svc, code, description, source_note)
 WHERE NOT EXISTS (SELECT 1 FROM public.deposit_customer_classes c WHERE c.state_code = v.s AND c.service_type = v.svc AND c.class_code = v.code);

CREATE TABLE IF NOT EXISTS public.deposit_waiver_classes (
    state_code             text NOT NULL,
    service_type           text NOT NULL,
    class_code             text NOT NULL,
    requires_certification boolean NOT NULL,
    tariff_defined         boolean NOT NULL,
    description            text NOT NULL,
    source_note            text NOT NULL,
    created_at             timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT deposit_waiver_classes_pkey PRIMARY KEY (state_code, service_type, class_code),
    CONSTRAINT deposit_waiver_classes_state_code_check CHECK ((state_code ~ '^[A-Z]{2}$'::text)),
    CONSTRAINT deposit_waiver_classes_service_type_check
        CHECK ((service_type = ANY (ARRAY['water'::text, 'sewer'::text, 'electric'::text, 'gas'::text, 'stormwater'::text, 'trash'::text, 'reclaimed_water'::text]))),
    CONSTRAINT deposit_waiver_classes_code_check CHECK ((class_code ~ '^[a-z][a-z0-9_]*$'::text)),
    CONSTRAINT deposit_waiver_classes_description_check CHECK ((description ~ '[[:alnum:]]'::text)),
    CONSTRAINT deposit_waiver_classes_source_note_check CHECK ((source_note ~ '[[:alnum:]]'::text))
);
COMMENT ON TABLE public.deposit_waiver_classes IS
    'v5.4.2-15. The grounds on which a state''s law waives a deposit, per state and service. requires_certification: a determination of this class carries the certification''s reference (Texas: family violence). tariff_defined: the class is the law''s PERMISSION for a utility''s tariff to add waivers; the waivers themselves are the utility''s own, in the tariff document. A law row''s waiver names one by class; which rules a class reaches, for which trigger, with which effect, is the document; whether a customer qualifies and whether a deposit is waived are the core''s. Platform-held.';
INSERT INTO public.deposit_waiver_classes (state_code, service_type, class_code, requires_certification, tariff_defined, description, source_note)
SELECT v.s, v.svc, v.code, v.cert, v.trf, v.description, v.source_note
  FROM (VALUES
    ('TX', 'gas', 'family_violence_certified', true,  false, 'Certified victim of family violence.',
     '16 TAC 7.45(5)(C) (Kyle research Q-6): a mandatory deposit waiver, certification-backed; decision table #53 rank 0.'),
    ('TX', 'gas', 'age_65_no_balance',         false, false, 'Aged 65 or older with no outstanding balance for the same service.',
     '16 TAC 7.45; decision table #53 rank 1. Mandatory or tariff-by-tariff is Kyle question K3.'),
    ('TX', 'gas', 'good_payment_history',      false, false, 'Good payment history with a utility.',
     '16 TAC 7.45; decision table #53 rank 2.'),
    ('TX', 'gas', 'tariff',                    false, true,  'A waiver the utility''s filed tariff adds.',
     'Decision table #53 rank 3: a tariff may extend the statutory waivers, never narrow them. The waivers are the utility''s own (the tariff document).')
  ) AS v(s, svc, code, cert, trf, description, source_note)
 WHERE NOT EXISTS (SELECT 1 FROM public.deposit_waiver_classes w WHERE w.state_code = v.s AND w.service_type = v.svc AND w.class_code = v.code);

CREATE TABLE IF NOT EXISTS public.deposit_return_reasons (
    reason_code         text NOT NULL,
    evidence_kind       text NOT NULL,
    qualifying_statuses text[],
    partial             boolean NOT NULL,
    description         text NOT NULL,
    created_at          timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT deposit_return_reasons_pkey PRIMARY KEY (reason_code),
    CONSTRAINT deposit_return_reasons_code_check CHECK ((reason_code ~ '^[a-z][a-z0-9_]*$'::text)),
    -- What a due row's evidence for this reason cites: bills, the customer's
    -- state change, or the deposit itself (a return due on time held, on the
    -- customer's demand, an excess over the cap).
    CONSTRAINT deposit_return_reasons_evidence_kind_check
        CHECK ((evidence_kind = ANY (ARRAY['invoice'::text, 'state_event'::text, 'deposit'::text]))),
    CONSTRAINT deposit_return_reasons_statuses_check
        CHECK ((((evidence_kind = 'state_event'::text) AND (qualifying_statuses IS NOT NULL) AND (cardinality(qualifying_statuses) > 0)
                 AND (qualifying_statuses <@ ARRAY['active'::text, 'inactive'::text, 'final_billed'::text, 'collections'::text, 'closed'::text]))
             OR ((evidence_kind <> 'state_event'::text) AND (qualifying_statuses IS NULL)))),
    CONSTRAINT deposit_return_reasons_description_check CHECK ((description ~ '[[:alnum:]]'::text))
);
COMMENT ON TABLE public.deposit_return_reasons IS
    'v5.4.2-15 (R-D2). Why a deposit''s mandatory return fell due, and what kind of record the reason rests on (evidence_kind: invoice — the bills the core judged; state_event — the customer''s state change, to one of qualifying_statuses; deposit — the deposit itself). partial: the reason returns part of the deposit (its due row carries the amount and principal_returned settles it). A law row''s return rule names a reason in its "when"; which reasons a due row may carry, and for which instruments, come from the cited document''s return rules. A state with another trigger adds a row. Platform-held vocabulary.';
INSERT INTO public.deposit_return_reasons (reason_code, evidence_kind, qualifying_statuses, partial, description)
SELECT v.code, v.kind, v.st, v.pt, v.description
  FROM (VALUES
    ('clean_bill_history',       'invoice',     NULL::text[], false, 'The customer''s bill history met the rule''s measure (Texas: twelve bills, no more than two delinquencies).'),
    ('account_closed',           'state_event', ARRAY['closed', 'final_billed', 'inactive'], false, 'The customer''s account closed, was final-billed or went inactive (whether inactive belongs is Kyle question K8).'),
    ('hold_term_elapsed',        'deposit',     NULL::text[], false, 'The deposit has been held for the rule''s term.'),
    ('customer_demand',          'deposit',     NULL::text[], false, 'The customer asks for it back and the rule allows it.'),
    ('days_after_disconnection', 'deposit',     NULL::text[], false, 'The rule''s number of days after a disconnection for nonpayment.'),
    ('entered_waiver_class',     'deposit',     NULL::text[], false, 'The customer entered a waiver class the rule returns a deposit on (Illinois: low-income certification).'),
    ('excess_over_cap',          'deposit',     NULL::text[], true,  'The deposit held is above the cap that now applies; the excess is returned while the rest stays held.'),
    ('excess_over_current_bill', 'deposit',     NULL::text[], true,  'The amount above the current bill, on the customer''s request; the rest stays held.')
  ) AS v(code, kind, st, pt, description)
 WHERE NOT EXISTS (SELECT 1 FROM public.deposit_return_reasons r WHERE r.reason_code = v.code);

CREATE TABLE IF NOT EXISTS public.deposit_refund_disqualifiers (
    disqualifier_code text NOT NULL,
    description       text NOT NULL,
    created_at        timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT deposit_refund_disqualifiers_pkey PRIMARY KEY (disqualifier_code),
    CONSTRAINT deposit_refund_disqualifiers_code_check CHECK ((disqualifier_code ~ '^[a-z][a-z0-9_]*$'::text)),
    CONSTRAINT deposit_refund_disqualifiers_description_check CHECK ((description ~ '[[:alnum:]]'::text))
);
COMMENT ON TABLE public.deposit_refund_disqualifiers IS
    'v5.4.2-15. Events in the customer''s history that stop a count-based return: a clean-history return rule names the ones that apply to it. Evaluated by the core. Platform-held vocabulary.';
INSERT INTO public.deposit_refund_disqualifiers (disqualifier_code, description)
SELECT v.code, v.description
  FROM (VALUES
    ('disconnect_nonpayment', 'Service disconnected for nonpayment within the lookback.'),
    ('returned_payment',      'A payment returned unpaid (NSF) within the lookback.')
  ) AS v(code, description)
 WHERE NOT EXISTS (SELECT 1 FROM public.deposit_refund_disqualifiers x WHERE x.disqualifier_code = v.code);

-- Immutability and grants of the six vocabularies.
DO $$
DECLARE
    t text;
BEGIN
    FOREACH t IN ARRAY ARRAY['deposit_bases', 'deposit_triggers', 'deposit_customer_classes', 'deposit_waiver_classes',
                             'deposit_return_reasons', 'deposit_refund_disqualifiers'] LOOP
        EXECUTE format('REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.%I FROM tally_app, tally_core', t);
        EXECUTE format('GRANT SELECT ON public.%I TO tally_app, tally_core', t);
        EXECUTE format('DROP TRIGGER IF EXISTS vocabulary_guard ON public.%I', t);
        EXECUTE format('CREATE TRIGGER vocabulary_guard BEFORE INSERT OR UPDATE OR DELETE ON public.%I FOR EACH ROW EXECUTE FUNCTION public.enforce_rule_vocabulary_immutable()', t);
        EXECUTE format('ALTER TABLE public.%I ENABLE ALWAYS TRIGGER vocabulary_guard', t);
        EXECUTE format('DROP TRIGGER IF EXISTS no_truncate ON public.%I', t);
        EXECUTE format('CREATE TRIGGER no_truncate BEFORE TRUNCATE ON public.%I FOR EACH STATEMENT EXECUTE FUNCTION public.enforce_rule_registry_no_truncate()', t);
        EXECUTE format('ALTER TABLE public.%I ENABLE ALWAYS TRIGGER no_truncate', t);
    END LOOP;
END;
$$;



-- ----------------------------------------------------------------------------
-- 3. The kinds, their facets, and the published value
-- ----------------------------------------------------------------------------
-- One transaction with the facets (a facet is declared in its schema's own
-- transaction), so the kinds go in one DO block. The schema texts are the
-- committed files, embedded verbatim; CI compares them.
DO $kinds$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.rule_term_schemas WHERE terms_kind = 'deposit' AND terms_version = 1) THEN
        INSERT INTO public.rule_term_schemas (terms_kind, terms_version, rule_role, json_schema, introduced_on, description, source_note)
        VALUES ('deposit', 1, 'law', $schema${
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://tally-utility/law/deposit/deposit.v1.schema.json",
  "title": "Deposit rule, version 1",
  "description": "What a state's law says about customer security deposits for one customer class and one basis: the cap, the triggers for an additional deposit, which waivers reach it, whether and how the deposit earns interest, how it comes back, and any instalment schedule. Replaces the typed columns and child tables of the v5.4.2-15 draft. Every law kind also admits the document 'the law leaves this to the utility'. Out of version 1 on purpose, each refused rather than dropped: periodic recalculation of a deposit, instalments tied to bills, a sum cap or a cap add-on, guarantor caps, and municipal deposit funds (application/deposits-terms-v1-design-2026-10-12.md, section 4).",
  "oneOf": [
    {
      "$ref": "#/$defs/law"
    },
    {
      "$ref": "#/$defs/delegated"
    }
  ],
  "$defs": {
    "citation": {
      "type": "string",
      "pattern": "[A-Za-z0-9]"
    },
    "code": {
      "type": "string",
      "pattern": "^[a-z][a-z0-9_]*$"
    },
    "id": {
      "type": "string",
      "pattern": "^[a-z][a-z0-9_]*$"
    },
    "window": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "unit",
        "size"
      ],
      "properties": {
        "unit": {
          "type": "string",
          "enum": [
            "months",
            "bills"
          ]
        },
        "size": {
          "type": "integer",
          "minimum": 1
        }
      },
      "description": "A span counted in calendar months or in bills."
    },
    "instrument": {
      "type": "string",
      "enum": [
        "cash",
        "letter_of_credit",
        "certificate_of_deposit",
        "surety_bond",
        "prepayment",
        "guarantor",
        "other_agreed"
      ]
    },
    "instruments": {
      "type": "array",
      "items": {
        "$ref": "#/$defs/instrument"
      },
      "minItems": 1,
      "maxItems": 7,
      "uniqueItems": true
    },
    "delegated": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "governs",
        "citation"
      ],
      "properties": {
        "governs": {
          "type": "string",
          "const": "delegated_to_utility"
        },
        "citation": {
          "type": "string",
          "pattern": "[A-Za-z0-9]"
        },
        "note": {
          "type": "string",
          "pattern": "[A-Za-z0-9]"
        }
      }
    },
    "cap_none": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "strategy",
        "version"
      ],
      "properties": {
        "strategy": {
          "type": "string",
          "const": "none"
        },
        "version": {
          "type": "integer",
          "minimum": 1,
          "maximum": 1
        }
      },
      "description": "The law sets no cap."
    },
    "cap_unruled": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "strategy",
        "version"
      ],
      "properties": {
        "strategy": {
          "type": "string",
          "const": "unruled"
        },
        "version": {
          "type": "integer",
          "minimum": 1,
          "maximum": 1
        }
      },
      "description": "The law may set a cap, but it is not known. Not the same as none: unknown law is not permission."
    },
    "cap_parts": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "strategy",
        "version",
        "combinator",
        "scope",
        "parts"
      ],
      "properties": {
        "strategy": {
          "type": "string",
          "const": "parts"
        },
        "version": {
          "type": "integer",
          "minimum": 1,
          "maximum": 1
        },
        "combinator": {
          "type": "string",
          "enum": [
            "single",
            "lesser_of",
            "greater_of"
          ]
        },
        "scope": {
          "type": "string",
          "enum": [
            "per_deposit",
            "combined"
          ]
        },
        "parts": {
          "type": "array",
          "items": {
            "$ref": "#/$defs/cap_part"
          },
          "minItems": 1,
          "maxItems": 4
        }
      },
      "description": "The cap is built from one or more parts. single: exactly one part. lesser_of / greater_of: two or more. per_deposit: each deposit within the cap; combined: the total held within it. That each kind appears at most once is the area's insert check."
    },
    "cap": {
      "oneOf": [
        {
          "$ref": "#/$defs/cap_none"
        },
        {
          "$ref": "#/$defs/cap_unruled"
        },
        {
          "$ref": "#/$defs/cap_parts"
        }
      ]
    },
    "cap_part": {
      "oneOf": [
        {
          "$ref": "#/$defs/part_fraction"
        },
        {
          "$ref": "#/$defs/part_months"
        },
        {
          "$ref": "#/$defs/part_fixed"
        },
        {
          "$ref": "#/$defs/part_highest"
        },
        {
          "$ref": "#/$defs/part_seasonal"
        }
      ]
    },
    "part_fraction": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "kind",
        "id",
        "divisor"
      ],
      "properties": {
        "kind": {
          "type": "string",
          "const": "fraction_of_annual_billing"
        },
        "id": {
          "$ref": "#/$defs/id"
        },
        "divisor": {
          "type": "integer",
          "minimum": 1
        }
      },
      "description": "Estimated annual billing divided by the divisor (Texas residential gas: 6)."
    },
    "part_months": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "kind",
        "id",
        "months"
      ],
      "properties": {
        "kind": {
          "type": "string",
          "const": "months_of_billing"
        },
        "id": {
          "$ref": "#/$defs/id"
        },
        "months": {
          "type": "number",
          "exclusiveMinimum": 0
        }
      },
      "description": "This many months of estimated billing."
    },
    "part_fixed": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "kind",
        "id",
        "amount"
      ],
      "properties": {
        "kind": {
          "type": "string",
          "const": "fixed_amount"
        },
        "id": {
          "$ref": "#/$defs/id"
        },
        "amount": {
          "type": "number",
          "exclusiveMinimum": 0
        }
      },
      "description": "A fixed amount."
    },
    "part_highest": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "kind",
        "id",
        "count",
        "window_months"
      ],
      "properties": {
        "kind": {
          "type": "string",
          "const": "highest_bills"
        },
        "id": {
          "$ref": "#/$defs/id"
        },
        "count": {
          "type": "integer",
          "minimum": 1
        },
        "window_months": {
          "type": "integer",
          "minimum": 1
        }
      },
      "description": "The total of the customer's highest N bills over the window (Arkansas: the 2 highest in 12 months)."
    },
    "part_seasonal": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "kind",
        "id",
        "multiple",
        "season"
      ],
      "properties": {
        "kind": {
          "type": "string",
          "const": "seasonal_average"
        },
        "id": {
          "$ref": "#/$defs/id"
        },
        "multiple": {
          "type": "number",
          "exclusiveMinimum": 0
        },
        "season": {
          "$ref": "#/$defs/code"
        }
      },
      "description": "A multiple of the average monthly bill for a season (New York: twice the heating-season average)."
    },
    "condition": {
      "oneOf": [
        {
          "$ref": "#/$defs/cond_count"
        },
        {
          "$ref": "#/$defs/cond_ratio"
        },
        {
          "$ref": "#/$defs/cond_all"
        },
        {
          "$ref": "#/$defs/cond_any"
        }
      ]
    },
    "cond_count": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "kind",
        "event",
        "at_least",
        "window",
        "consecutive",
        "exclude_disputed"
      ],
      "properties": {
        "kind": {
          "type": "string",
          "const": "count"
        },
        "event": {
          "$ref": "#/$defs/code"
        },
        "at_least": {
          "type": "integer",
          "minimum": 1
        },
        "window": {
          "$ref": "#/$defs/window"
        },
        "consecutive": {
          "type": "boolean"
        },
        "exclude_disputed": {
          "type": "boolean"
        }
      },
      "description": "At least N of an event in a window. consecutive: the N must be in a row. exclude_disputed: disputed bills do not count. A delinquency definition is an event in the vocabulary (for example past_due_over_30_days)."
    },
    "cond_ratio": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "kind",
        "measure",
        "op",
        "value"
      ],
      "properties": {
        "kind": {
          "type": "string",
          "const": "ratio"
        },
        "measure": {
          "type": "string",
          "enum": [
            "usage_to_estimate",
            "final_bill_to_class_average"
          ]
        },
        "op": {
          "type": "string",
          "enum": [
            "at_least",
            "greater_than"
          ]
        },
        "value": {
          "type": "number",
          "exclusiveMinimum": 0
        }
      },
      "description": "A measured ratio compared with a value. The core supplies the measure."
    },
    "cond_all": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "kind",
        "of"
      ],
      "properties": {
        "kind": {
          "type": "string",
          "const": "all_of"
        },
        "of": {
          "type": "array",
          "items": {
            "$ref": "#/$defs/condition"
          },
          "minItems": 2,
          "maxItems": 6
        }
      },
      "description": "Every one of the conditions holds."
    },
    "cond_any": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "kind",
        "of"
      ],
      "properties": {
        "kind": {
          "type": "string",
          "const": "any_of"
        },
        "of": {
          "type": "array",
          "items": {
            "$ref": "#/$defs/condition"
          },
          "minItems": 2,
          "maxItems": 6
        }
      },
      "description": "At least one of the conditions holds."
    },
    "guard": {
      "oneOf": [
        {
          "$ref": "#/$defs/g_pay"
        },
        {
          "$ref": "#/$defs/g_age"
        },
        {
          "$ref": "#/$defs/g_move"
        },
        {
          "$ref": "#/$defs/g_assess"
        },
        {
          "$ref": "#/$defs/g_notice"
        },
        {
          "$ref": "#/$defs/g_cure"
        },
        {
          "$ref": "#/$defs/g_since"
        }
      ]
    },
    "g_pay": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "kind",
        "days"
      ],
      "properties": {
        "kind": {
          "type": "string",
          "const": "payment_due_days"
        },
        "days": {
          "type": "integer",
          "minimum": 1
        }
      },
      "description": "Days the customer has to pay once required (Texas usage deposit: 2)."
    },
    "g_age": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "kind",
        "months"
      ],
      "properties": {
        "kind": {
          "type": "string",
          "const": "not_after_service_months"
        },
        "months": {
          "type": "integer",
          "minimum": 1
        }
      },
      "description": "The trigger cannot be used after this many months of service (Arkansas usage trigger: 12)."
    },
    "g_move": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "kind",
        "days"
      ],
      "properties": {
        "kind": {
          "type": "string",
          "const": "not_if_moved_within_days"
        },
        "days": {
          "type": "integer",
          "minimum": 1
        }
      },
      "description": "No re-assessment when service moves to a new location within this many days."
    },
    "g_assess": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "kind",
        "days"
      ],
      "properties": {
        "kind": {
          "type": "string",
          "const": "assess_within_days"
        },
        "days": {
          "type": "integer",
          "minimum": 1
        }
      },
      "description": "The deposit must be assessed within this many days of the event."
    },
    "g_notice": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "kind",
        "days"
      ],
      "properties": {
        "kind": {
          "type": "string",
          "const": "notice_days"
        },
        "days": {
          "type": "integer",
          "minimum": 1
        }
      },
      "description": "Written notice this many days before assessment."
    },
    "g_cure": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "kind",
        "cure_code"
      ],
      "properties": {
        "kind": {
          "type": "string",
          "const": "cured_by"
        },
        "cure_code": {
          "$ref": "#/$defs/code"
        }
      },
      "description": "A customer action entered before assessment cancels the trigger (a kept payment arrangement)."
    },
    "g_since": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "kind",
        "event",
        "years"
      ],
      "properties": {
        "kind": {
          "type": "string",
          "const": "not_after_cumulative_service_years_since"
        },
        "event": {
          "$ref": "#/$defs/code"
        },
        "years": {
          "type": "integer",
          "minimum": 1
        }
      },
      "description": "The trigger lapses after this many years of cumulative service since the event."
    },
    "trigger": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "id",
        "trigger_code",
        "condition",
        "guards"
      ],
      "properties": {
        "id": {
          "$ref": "#/$defs/id"
        },
        "trigger_code": {
          "$ref": "#/$defs/code"
        },
        "condition": {
          "$ref": "#/$defs/condition"
        },
        "guards": {
          "type": "array",
          "items": {
            "$ref": "#/$defs/guard"
          },
          "maxItems": 6
        }
      },
      "description": "An additional-deposit trigger the law allows: when the condition holds (and no guard stops it), a deposit may be required."
    },
    "applies_any": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "kind"
      ],
      "properties": {
        "kind": {
          "type": "string",
          "const": "any_trigger"
        }
      },
      "description": "Reaches a deposit under any trigger."
    },
    "applies_trigger": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "kind",
        "trigger_code"
      ],
      "properties": {
        "kind": {
          "type": "string",
          "const": "trigger"
        },
        "trigger_code": {
          "$ref": "#/$defs/code"
        }
      },
      "description": "Reaches a deposit under this trigger only."
    },
    "applies_to": {
      "oneOf": [
        {
          "$ref": "#/$defs/applies_any"
        },
        {
          "$ref": "#/$defs/applies_trigger"
        }
      ]
    },
    "effect_excuse": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "kind"
      ],
      "properties": {
        "kind": {
          "type": "string",
          "const": "excuse"
        }
      },
      "description": "The deposit is not required."
    },
    "effect_reduce": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "kind",
        "fraction"
      ],
      "properties": {
        "kind": {
          "type": "string",
          "const": "reduce"
        },
        "fraction": {
          "type": "number",
          "exclusiveMinimum": 0,
          "exclusiveMaximum": 1
        }
      },
      "description": "The deposit is reduced by this fraction."
    },
    "effect_defer": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "kind",
        "days"
      ],
      "properties": {
        "kind": {
          "type": "string",
          "const": "defer"
        },
        "days": {
          "type": "integer",
          "minimum": 1
        }
      },
      "description": "The deposit is deferred by this many days."
    },
    "effect": {
      "oneOf": [
        {
          "$ref": "#/$defs/effect_excuse"
        },
        {
          "$ref": "#/$defs/effect_reduce"
        },
        {
          "$ref": "#/$defs/effect_defer"
        }
      ]
    },
    "disq_none": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "kind"
      ],
      "properties": {
        "kind": {
          "type": "string",
          "const": "none"
        }
      },
      "description": "The waiver has no disqualifier of its own."
    },
    "disq_condition": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "kind",
        "condition"
      ],
      "properties": {
        "kind": {
          "type": "string",
          "const": "condition"
        },
        "condition": {
          "$ref": "#/$defs/condition"
        }
      },
      "description": "The waiver is lost while this condition holds (New York: terminated for nonpayment in the past six months)."
    },
    "disqualified_by": {
      "oneOf": [
        {
          "$ref": "#/$defs/disq_none"
        },
        {
          "$ref": "#/$defs/disq_condition"
        }
      ]
    },
    "waiver": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "id",
        "waiver_class",
        "applies_to",
        "effect",
        "also_releases_held",
        "disqualified_by"
      ],
      "properties": {
        "id": {
          "$ref": "#/$defs/id"
        },
        "waiver_class": {
          "$ref": "#/$defs/code"
        },
        "applies_to": {
          "$ref": "#/$defs/applies_to"
        },
        "effect": {
          "$ref": "#/$defs/effect"
        },
        "also_releases_held": {
          "type": "boolean"
        },
        "disqualified_by": {
          "$ref": "#/$defs/disqualified_by"
        }
      },
      "description": "A waiver class that relieves a deposit under this rule. also_releases_held: a deposit already held is released too (New York: 'demand or hold')."
    },
    "interest_none": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "strategy",
        "version"
      ],
      "properties": {
        "strategy": {
          "type": "string",
          "const": "none"
        },
        "version": {
          "type": "integer",
          "minimum": 1,
          "maximum": 1
        }
      },
      "description": "Deposits under this rule earn no interest."
    },
    "rate_published": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "kind",
        "name",
        "binding",
        "by_hold"
      ],
      "properties": {
        "kind": {
          "type": "string",
          "const": "published"
        },
        "name": {
          "$ref": "#/$defs/code"
        },
        "binding": {
          "type": "string",
          "enum": [
            "minimum",
            "reference"
          ]
        },
        "by_hold": {
          "type": "array",
          "items": {
            "type": "object",
            "additionalProperties": false,
            "required": [
              "up_to_months",
              "name"
            ],
            "properties": {
              "up_to_months": {
                "type": "integer",
                "minimum": 1
              },
              "name": {
                "$ref": "#/$defs/code"
              }
            }
          },
          "maxItems": 4
        }
      },
      "description": "The rate is a named published value. by_hold: while the deposit has been held up to N months, use that named value instead. binding minimum: the utility's own rate may not go below it (decision 4); reference: it is only compared."
    },
    "rate_fixed": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "kind",
        "rate",
        "binding"
      ],
      "properties": {
        "kind": {
          "type": "string",
          "const": "fixed"
        },
        "rate": {
          "type": "number",
          "minimum": 0,
          "maximum": 1
        },
        "binding": {
          "type": "string",
          "enum": [
            "minimum",
            "reference"
          ]
        }
      },
      "description": "A rate the law states itself (Louisiana: 0.05)."
    },
    "rate_utility": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "kind"
      ],
      "properties": {
        "kind": {
          "type": "string",
          "const": "utility_sets"
        }
      },
      "description": "The law leaves the rate to the utility."
    },
    "rate": {
      "oneOf": [
        {
          "$ref": "#/$defs/rate_published"
        },
        {
          "$ref": "#/$defs/rate_fixed"
        },
        {
          "$ref": "#/$defs/rate_utility"
        }
      ]
    },
    "method_simple": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "kind"
      ],
      "properties": {
        "kind": {
          "type": "string",
          "const": "simple"
        }
      }
    },
    "method_compound": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "kind",
        "period"
      ],
      "properties": {
        "kind": {
          "type": "string",
          "const": "compound"
        },
        "period": {
          "type": "string",
          "enum": [
            "monthly",
            "annual"
          ]
        }
      },
      "description": "Compounded at the end of each period (PG&E: monthly)."
    },
    "method": {
      "oneOf": [
        {
          "$ref": "#/$defs/method_simple"
        },
        {
          "$ref": "#/$defs/method_compound"
        }
      ]
    },
    "hold_none": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "kind"
      ],
      "properties": {
        "kind": {
          "type": "string",
          "const": "none"
        }
      },
      "description": "Interest runs from the posting date, however long the deposit is held."
    },
    "hold_minimum": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "kind",
        "days",
        "retroactive"
      ],
      "properties": {
        "kind": {
          "type": "string",
          "const": "minimum"
        },
        "days": {
          "type": "integer",
          "minimum": 1
        },
        "retroactive": {
          "type": "boolean"
        }
      },
      "description": "No interest unless the deposit is held more than this many days. retroactive: past that, interest runs from posting (Texas: 30 days, retroactive)."
    },
    "hold": {
      "oneOf": [
        {
          "$ref": "#/$defs/hold_none"
        },
        {
          "$ref": "#/$defs/hold_minimum"
        }
      ]
    },
    "credit_refund": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "kind"
      ],
      "properties": {
        "kind": {
          "type": "string",
          "const": "at_refund"
        }
      }
    },
    "credit_annual": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "kind"
      ],
      "properties": {
        "kind": {
          "type": "string",
          "const": "annual"
        }
      }
    },
    "credit_bill": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "kind"
      ],
      "properties": {
        "kind": {
          "type": "string",
          "const": "on_bill"
        }
      }
    },
    "credit_date": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "kind",
        "month",
        "day",
        "customer_may_elect_cash"
      ],
      "properties": {
        "kind": {
          "type": "string",
          "const": "calendar_date"
        },
        "month": {
          "type": "integer",
          "minimum": 1,
          "maximum": 12
        },
        "day": {
          "type": "integer",
          "minimum": 1,
          "maximum": 31
        },
        "customer_may_elect_cash": {
          "type": "boolean"
        }
      },
      "description": "Interest is credited on this calendar date (Kansas: January 1), and the customer may ask for cash instead."
    },
    "credit_unruled": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "kind"
      ],
      "properties": {
        "kind": {
          "type": "string",
          "const": "unruled"
        }
      },
      "description": "The law does not say when interest is credited."
    },
    "credit": {
      "oneOf": [
        {
          "$ref": "#/$defs/credit_refund"
        },
        {
          "$ref": "#/$defs/credit_annual"
        },
        {
          "$ref": "#/$defs/credit_bill"
        },
        {
          "$ref": "#/$defs/credit_date"
        },
        {
          "$ref": "#/$defs/credit_unruled"
        }
      ]
    },
    "penalty_none": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "kind"
      ],
      "properties": {
        "kind": {
          "type": "string",
          "const": "none"
        }
      }
    },
    "penalty_demand": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "kind",
        "rate"
      ],
      "properties": {
        "kind": {
          "type": "string",
          "const": "after_refused_demand"
        },
        "rate": {
          "type": "number",
          "exclusiveMinimum": 0,
          "maximum": 1
        }
      },
      "description": "A penalty rate on what is kept after the customer demands it back (Louisiana: 0.1)."
    },
    "penalty": {
      "oneOf": [
        {
          "$ref": "#/$defs/penalty_none"
        },
        {
          "$ref": "#/$defs/penalty_demand"
        }
      ]
    },
    "rounding_none": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "kind"
      ],
      "properties": {
        "kind": {
          "type": "string",
          "const": "none"
        }
      }
    },
    "rounding_nearest": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "kind",
        "fraction"
      ],
      "properties": {
        "kind": {
          "type": "string",
          "const": "nearest"
        },
        "fraction": {
          "type": "number",
          "exclusiveMinimum": 0,
          "maximum": 1
        }
      },
      "description": "The rate is rounded to the nearest fraction (Illinois: 0.005, a half percent)."
    },
    "rounding": {
      "oneOf": [
        {
          "$ref": "#/$defs/rounding_none"
        },
        {
          "$ref": "#/$defs/rounding_nearest"
        }
      ]
    },
    "interest_bearing": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "strategy",
        "version",
        "instruments",
        "rate",
        "method",
        "day_count",
        "hold",
        "credit",
        "stops_on",
        "forfeited_on",
        "penalty",
        "rounding"
      ],
      "properties": {
        "strategy": {
          "type": "string",
          "const": "bearing"
        },
        "version": {
          "type": "integer",
          "minimum": 1,
          "maximum": 1
        },
        "instruments": {
          "$ref": "#/$defs/instruments"
        },
        "rate": {
          "$ref": "#/$defs/rate"
        },
        "method": {
          "$ref": "#/$defs/method"
        },
        "day_count": {
          "type": "string",
          "enum": [
            "actual_365",
            "actual_actual",
            "thirty_360",
            "unruled"
          ]
        },
        "hold": {
          "$ref": "#/$defs/hold"
        },
        "credit": {
          "$ref": "#/$defs/credit"
        },
        "stops_on": {
          "type": "array",
          "items": {
            "type": "string",
            "enum": [
              "refund",
              "service_terminated",
              "service_discontinued",
              "good_faith_return_attempt"
            ]
          },
          "maxItems": 4,
          "uniqueItems": true
        },
        "forfeited_on": {
          "type": "array",
          "items": {
            "type": "string",
            "enum": [
              "disconnect_nonpayment"
            ]
          },
          "maxItems": 1,
          "uniqueItems": true
        },
        "penalty": {
          "$ref": "#/$defs/penalty"
        },
        "rounding": {
          "$ref": "#/$defs/rounding"
        }
      },
      "description": "Deposits of the listed instruments earn interest. Every part is written, so nothing is defaulted."
    },
    "interest": {
      "oneOf": [
        {
          "$ref": "#/$defs/interest_none"
        },
        {
          "$ref": "#/$defs/interest_bearing"
        }
      ]
    },
    "when_clean": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "reason",
        "count",
        "measure",
        "max_delinquencies",
        "lookback",
        "disqualifiers",
        "exclude_disputed"
      ],
      "properties": {
        "reason": {
          "type": "string",
          "const": "clean_bill_history"
        },
        "count": {
          "type": "integer",
          "minimum": 1
        },
        "measure": {
          "type": "string",
          "enum": [
            "bills",
            "months"
          ]
        },
        "max_delinquencies": {
          "type": "integer",
          "minimum": 0
        },
        "lookback": {
          "$ref": "#/$defs/lookback"
        },
        "disqualifiers": {
          "type": "array",
          "items": {
            "$ref": "#/$defs/code"
          },
          "maxItems": 6,
          "uniqueItems": true
        },
        "exclude_disputed": {
          "type": "boolean"
        }
      },
      "description": "After this many bills or months, with no more than the stated delinquencies, the deposit is returned."
    },
    "lookback_whole": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "kind"
      ],
      "properties": {
        "kind": {
          "type": "string",
          "const": "whole_hold"
        }
      },
      "description": "Delinquencies are counted over the whole time the deposit was held."
    },
    "lookback_window": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "kind",
        "unit",
        "size"
      ],
      "properties": {
        "kind": {
          "type": "string",
          "const": "window"
        },
        "unit": {
          "type": "string",
          "enum": [
            "months",
            "bills"
          ]
        },
        "size": {
          "type": "integer",
          "minimum": 1
        }
      },
      "description": "Delinquencies are counted over this window."
    },
    "lookback": {
      "oneOf": [
        {
          "$ref": "#/$defs/lookback_whole"
        },
        {
          "$ref": "#/$defs/lookback_window"
        }
      ]
    },
    "when_closed": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "reason"
      ],
      "properties": {
        "reason": {
          "type": "string",
          "const": "account_closed"
        }
      },
      "description": "The account closed, was final-billed or went inactive."
    },
    "when_held": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "reason",
        "months"
      ],
      "properties": {
        "reason": {
          "type": "string",
          "const": "hold_term_elapsed"
        },
        "months": {
          "type": "integer",
          "minimum": 1
        }
      },
      "description": "The deposit has been held this many months."
    },
    "when_demand": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "reason"
      ],
      "properties": {
        "reason": {
          "type": "string",
          "const": "customer_demand"
        }
      },
      "description": "The customer asks for it back."
    },
    "when_disc": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "reason",
        "days"
      ],
      "properties": {
        "reason": {
          "type": "string",
          "const": "days_after_disconnection"
        },
        "days": {
          "type": "integer",
          "minimum": 1
        }
      },
      "description": "This many days after a disconnection for nonpayment."
    },
    "when_class": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "reason",
        "waiver_class"
      ],
      "properties": {
        "reason": {
          "type": "string",
          "const": "entered_waiver_class"
        },
        "waiver_class": {
          "$ref": "#/$defs/code"
        }
      },
      "description": "The customer entered a waiver class (Illinois: low-income certification)."
    },
    "when_excess_cap": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "reason"
      ],
      "properties": {
        "reason": {
          "type": "string",
          "const": "excess_over_cap"
        }
      },
      "description": "Part of the deposit: the amount held above the cap now applying."
    },
    "when_excess_bill": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "reason"
      ],
      "properties": {
        "reason": {
          "type": "string",
          "const": "excess_over_current_bill"
        }
      },
      "description": "Part of the deposit: the amount above the current bill, on the customer's request."
    },
    "return_when": {
      "oneOf": [
        {
          "$ref": "#/$defs/when_clean"
        },
        {
          "$ref": "#/$defs/when_closed"
        },
        {
          "$ref": "#/$defs/when_held"
        },
        {
          "$ref": "#/$defs/when_demand"
        },
        {
          "$ref": "#/$defs/when_disc"
        },
        {
          "$ref": "#/$defs/when_class"
        },
        {
          "$ref": "#/$defs/when_excess_cap"
        },
        {
          "$ref": "#/$defs/when_excess_bill"
        }
      ]
    },
    "rcond_amount": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "kind",
        "amount"
      ],
      "properties": {
        "kind": {
          "type": "string",
          "const": "deposit_below_amount"
        },
        "amount": {
          "type": "number",
          "exclusiveMinimum": 0
        }
      },
      "description": "Only a deposit below this amount (Oklahoma: 20000)."
    },
    "rcond_years": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "kind",
        "years"
      ],
      "properties": {
        "kind": {
          "type": "string",
          "const": "service_years_at_least"
        },
        "years": {
          "type": "integer",
          "minimum": 1
        }
      },
      "description": "Only after this many years of continuous service at the location."
    },
    "return_condition": {
      "oneOf": [
        {
          "$ref": "#/$defs/rcond_amount"
        },
        {
          "$ref": "#/$defs/rcond_years"
        }
      ]
    },
    "min_none": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "kind"
      ],
      "properties": {
        "kind": {
          "type": "string",
          "const": "none"
        }
      }
    },
    "min_amount": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "kind",
        "amount"
      ],
      "properties": {
        "kind": {
          "type": "string",
          "const": "amount"
        },
        "amount": {
          "type": "number",
          "exclusiveMinimum": 0
        }
      },
      "description": "No refund below this amount."
    },
    "minimum_amount": {
      "oneOf": [
        {
          "$ref": "#/$defs/min_none"
        },
        {
          "$ref": "#/$defs/min_amount"
        }
      ]
    },
    "dead_none": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "kind"
      ],
      "properties": {
        "kind": {
          "type": "string",
          "const": "none"
        }
      }
    },
    "dead_days": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "kind",
        "days"
      ],
      "properties": {
        "kind": {
          "type": "string",
          "const": "days"
        },
        "days": {
          "type": "integer",
          "minimum": 1
        }
      },
      "description": "The refund is due within this many days of the qualifying event."
    },
    "deadline": {
      "oneOf": [
        {
          "$ref": "#/$defs/dead_none"
        },
        {
          "$ref": "#/$defs/dead_days"
        }
      ]
    },
    "return_rule": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "id",
        "when",
        "instruments",
        "conditions",
        "minimum_amount",
        "deadline",
        "hold_while",
        "vests"
      ],
      "properties": {
        "id": {
          "$ref": "#/$defs/id"
        },
        "when": {
          "$ref": "#/$defs/return_when"
        },
        "instruments": {
          "$ref": "#/$defs/instruments"
        },
        "conditions": {
          "type": "array",
          "items": {
            "$ref": "#/$defs/return_condition"
          },
          "maxItems": 4
        },
        "minimum_amount": {
          "$ref": "#/$defs/minimum_amount"
        },
        "deadline": {
          "$ref": "#/$defs/deadline"
        },
        "hold_while": {
          "type": "array",
          "items": {
            "type": "string",
            "enum": [
              "dispute_pending"
            ]
          },
          "maxItems": 1,
          "uniqueItems": true
        },
        "vests": {
          "type": "string",
          "enum": [
            "yes",
            "no",
            "unruled"
          ]
        }
      },
      "description": "A way the deposit comes back. vests: once due, it stays owed even if the customer falls behind (unruled when the law does not say)."
    },
    "instalment": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "id",
        "fraction",
        "days_after"
      ],
      "properties": {
        "id": {
          "$ref": "#/$defs/id"
        },
        "fraction": {
          "type": "number",
          "exclusiveMinimum": 0,
          "exclusiveMaximum": 1
        },
        "days_after": {
          "type": "integer",
          "minimum": 0
        }
      },
      "description": "A fixed-schedule instalment: this fraction of the deposit, this many days after the determination. The fractions summing to 1 is the area's insert check. Instalments tied to bills are not in version 1."
    },
    "law": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "governs",
        "citation",
        "cap",
        "triggers",
        "waivers",
        "interest",
        "return",
        "instalments"
      ],
      "properties": {
        "governs": {
          "type": "string",
          "const": "law"
        },
        "citation": {
          "$ref": "#/$defs/citation"
        },
        "cap": {
          "$ref": "#/$defs/cap"
        },
        "triggers": {
          "type": "array",
          "items": {
            "$ref": "#/$defs/trigger"
          },
          "maxItems": 16
        },
        "waivers": {
          "type": "array",
          "items": {
            "$ref": "#/$defs/waiver"
          },
          "maxItems": 16
        },
        "interest": {
          "$ref": "#/$defs/interest"
        },
        "return": {
          "type": "array",
          "items": {
            "$ref": "#/$defs/return_rule"
          },
          "maxItems": 16
        },
        "instalments": {
          "type": "array",
          "items": {
            "$ref": "#/$defs/instalment"
          },
          "maxItems": 12
        }
      }
    }
  }
}$schema$::jsonb, DATE '2026-10-12',
                'Deposit rule: what a state''s law says about a deposit for one customer class and one basis — the cap, the triggers for an additional deposit, the waivers, the interest, the return rules and the instalment schedule',
                'law/deposit/deposit.v1.schema.json');
        INSERT INTO public.rule_term_facets (terms_kind, terms_version, facet_name, facet_type, json_path, vocabulary_table, vocabulary_column, vocabulary_scope, description) VALUES
            ('deposit', 1, 'trigger_codes',  'text[]', '$.triggers[*].trigger_code', 'public.deposit_triggers',       'trigger_code', NULL,
             'The trigger codes the document names: each a deposit_triggers row. A deposit on an additional-deposit basis cites one of them.'),
            ('deposit', 1, 'waiver_classes', 'text[]', '$.waivers[*].waiver_class', 'public.deposit_waiver_classes',  'class_code',
             '{"state_code": "state_code", "service_type": "service_type"}'::jsonb,
             'The waiver classes the document names: each a class of the row''s own state and service.'),
            ('deposit', 1, 'return_reasons', 'text[]', '$.return[*].when.reason', 'public.deposit_return_reasons',   'reason_code', NULL,
             'The reasons a deposit may fall due for return under the document: each a deposit_return_reasons row. A return-due record cites one.'),
            ('deposit', 1, 'cap_part_ids',  'text[]', '$.cap.parts[*].id', NULL, NULL, NULL,
             'The ids of the cap''s parts. Not a vocabulary: a deposit names the part that governed its cap by id.');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.rule_term_schemas WHERE terms_kind = 'deposit_tariff' AND terms_version = 1) THEN
        INSERT INTO public.rule_term_schemas (terms_kind, terms_version, rule_role, json_schema, introduced_on, description, source_note)
        VALUES ('deposit_tariff', 1, 'tariff', $schema${
  "type": "object",
  "additionalProperties": false,
  "required": [
    "citation",
    "amount",
    "triggers",
    "waivers",
    "instalments"
  ],
  "properties": {
    "citation": {
      "$ref": "#/$defs/citation"
    },
    "amount": {
      "$ref": "#/$defs/amount"
    },
    "triggers": {
      "type": "array",
      "items": {
        "$ref": "#/$defs/trigger"
      },
      "maxItems": 16
    },
    "waivers": {
      "type": "array",
      "items": {
        "$ref": "#/$defs/tariff_waiver"
      },
      "maxItems": 16
    },
    "instalments": {
      "type": "array",
      "items": {
        "$ref": "#/$defs/instalment"
      },
      "maxItems": 12
    }
  },
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://tally-utility/law/deposit/deposit_tariff.v1.schema.json",
  "title": "Deposit tariff, version 1",
  "description": "A utility's own deposit policy for one of its customer categories: the amount it requires, the triggers it adds, the grounds on which it waives, and any instalment schedule. Compared with the law by the area's comparator on every write (never looser than the law); for a city-owned system whose law row delegates, there is nothing to compare. Not in version 1: recalculation, bill-anchored instalments, guarantor limits, deposit funds (application/deposits-terms-v1-design-2026-10-12.md, section 4).",
  "$defs": {
    "citation": {
      "type": "string",
      "pattern": "[A-Za-z0-9]"
    },
    "code": {
      "type": "string",
      "pattern": "^[a-z][a-z0-9_]*$"
    },
    "id": {
      "type": "string",
      "pattern": "^[a-z][a-z0-9_]*$"
    },
    "condition": {
      "oneOf": [
        {
          "$ref": "#/$defs/cond_count"
        },
        {
          "$ref": "#/$defs/cond_ratio"
        },
        {
          "$ref": "#/$defs/cond_all"
        },
        {
          "$ref": "#/$defs/cond_any"
        }
      ]
    },
    "cond_count": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "kind",
        "event",
        "at_least",
        "window",
        "consecutive",
        "exclude_disputed"
      ],
      "properties": {
        "kind": {
          "type": "string",
          "const": "count"
        },
        "event": {
          "$ref": "#/$defs/code"
        },
        "at_least": {
          "type": "integer",
          "minimum": 1
        },
        "window": {
          "$ref": "#/$defs/window"
        },
        "consecutive": {
          "type": "boolean"
        },
        "exclude_disputed": {
          "type": "boolean"
        }
      },
      "description": "At least N of an event in a window. consecutive: the N must be in a row. exclude_disputed: disputed bills do not count. A delinquency definition is an event in the vocabulary (for example past_due_over_30_days)."
    },
    "cond_ratio": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "kind",
        "measure",
        "op",
        "value"
      ],
      "properties": {
        "kind": {
          "type": "string",
          "const": "ratio"
        },
        "measure": {
          "type": "string",
          "enum": [
            "usage_to_estimate",
            "final_bill_to_class_average"
          ]
        },
        "op": {
          "type": "string",
          "enum": [
            "at_least",
            "greater_than"
          ]
        },
        "value": {
          "type": "number",
          "exclusiveMinimum": 0
        }
      },
      "description": "A measured ratio compared with a value. The core supplies the measure."
    },
    "cond_all": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "kind",
        "of"
      ],
      "properties": {
        "kind": {
          "type": "string",
          "const": "all_of"
        },
        "of": {
          "type": "array",
          "items": {
            "$ref": "#/$defs/condition"
          },
          "minItems": 2,
          "maxItems": 6
        }
      },
      "description": "Every one of the conditions holds."
    },
    "cond_any": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "kind",
        "of"
      ],
      "properties": {
        "kind": {
          "type": "string",
          "const": "any_of"
        },
        "of": {
          "type": "array",
          "items": {
            "$ref": "#/$defs/condition"
          },
          "minItems": 2,
          "maxItems": 6
        }
      },
      "description": "At least one of the conditions holds."
    },
    "window": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "unit",
        "size"
      ],
      "properties": {
        "unit": {
          "type": "string",
          "enum": [
            "months",
            "bills"
          ]
        },
        "size": {
          "type": "integer",
          "minimum": 1
        }
      },
      "description": "A span counted in calendar months or in bills."
    },
    "guard": {
      "oneOf": [
        {
          "$ref": "#/$defs/g_pay"
        },
        {
          "$ref": "#/$defs/g_age"
        },
        {
          "$ref": "#/$defs/g_move"
        },
        {
          "$ref": "#/$defs/g_assess"
        },
        {
          "$ref": "#/$defs/g_notice"
        },
        {
          "$ref": "#/$defs/g_cure"
        },
        {
          "$ref": "#/$defs/g_since"
        }
      ]
    },
    "g_pay": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "kind",
        "days"
      ],
      "properties": {
        "kind": {
          "type": "string",
          "const": "payment_due_days"
        },
        "days": {
          "type": "integer",
          "minimum": 1
        }
      },
      "description": "Days the customer has to pay once required (Texas usage deposit: 2)."
    },
    "g_age": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "kind",
        "months"
      ],
      "properties": {
        "kind": {
          "type": "string",
          "const": "not_after_service_months"
        },
        "months": {
          "type": "integer",
          "minimum": 1
        }
      },
      "description": "The trigger cannot be used after this many months of service (Arkansas usage trigger: 12)."
    },
    "g_move": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "kind",
        "days"
      ],
      "properties": {
        "kind": {
          "type": "string",
          "const": "not_if_moved_within_days"
        },
        "days": {
          "type": "integer",
          "minimum": 1
        }
      },
      "description": "No re-assessment when service moves to a new location within this many days."
    },
    "g_assess": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "kind",
        "days"
      ],
      "properties": {
        "kind": {
          "type": "string",
          "const": "assess_within_days"
        },
        "days": {
          "type": "integer",
          "minimum": 1
        }
      },
      "description": "The deposit must be assessed within this many days of the event."
    },
    "g_notice": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "kind",
        "days"
      ],
      "properties": {
        "kind": {
          "type": "string",
          "const": "notice_days"
        },
        "days": {
          "type": "integer",
          "minimum": 1
        }
      },
      "description": "Written notice this many days before assessment."
    },
    "g_cure": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "kind",
        "cure_code"
      ],
      "properties": {
        "kind": {
          "type": "string",
          "const": "cured_by"
        },
        "cure_code": {
          "$ref": "#/$defs/code"
        }
      },
      "description": "A customer action entered before assessment cancels the trigger (a kept payment arrangement)."
    },
    "g_since": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "kind",
        "event",
        "years"
      ],
      "properties": {
        "kind": {
          "type": "string",
          "const": "not_after_cumulative_service_years_since"
        },
        "event": {
          "$ref": "#/$defs/code"
        },
        "years": {
          "type": "integer",
          "minimum": 1
        }
      },
      "description": "The trigger lapses after this many years of cumulative service since the event."
    },
    "trigger": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "id",
        "trigger_code",
        "condition",
        "guards"
      ],
      "properties": {
        "id": {
          "$ref": "#/$defs/id"
        },
        "trigger_code": {
          "$ref": "#/$defs/code"
        },
        "condition": {
          "$ref": "#/$defs/condition"
        },
        "guards": {
          "type": "array",
          "items": {
            "$ref": "#/$defs/guard"
          },
          "maxItems": 6
        }
      },
      "description": "An additional-deposit trigger the law allows: when the condition holds (and no guard stops it), a deposit may be required."
    },
    "applies_to": {
      "oneOf": [
        {
          "$ref": "#/$defs/applies_any"
        },
        {
          "$ref": "#/$defs/applies_trigger"
        }
      ]
    },
    "applies_any": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "kind"
      ],
      "properties": {
        "kind": {
          "type": "string",
          "const": "any_trigger"
        }
      },
      "description": "Reaches a deposit under any trigger."
    },
    "applies_trigger": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "kind",
        "trigger_code"
      ],
      "properties": {
        "kind": {
          "type": "string",
          "const": "trigger"
        },
        "trigger_code": {
          "$ref": "#/$defs/code"
        }
      },
      "description": "Reaches a deposit under this trigger only."
    },
    "effect": {
      "oneOf": [
        {
          "$ref": "#/$defs/effect_excuse"
        },
        {
          "$ref": "#/$defs/effect_reduce"
        },
        {
          "$ref": "#/$defs/effect_defer"
        }
      ]
    },
    "effect_excuse": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "kind"
      ],
      "properties": {
        "kind": {
          "type": "string",
          "const": "excuse"
        }
      },
      "description": "The deposit is not required."
    },
    "effect_reduce": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "kind",
        "fraction"
      ],
      "properties": {
        "kind": {
          "type": "string",
          "const": "reduce"
        },
        "fraction": {
          "type": "number",
          "exclusiveMinimum": 0,
          "exclusiveMaximum": 1
        }
      },
      "description": "The deposit is reduced by this fraction."
    },
    "effect_defer": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "kind",
        "days"
      ],
      "properties": {
        "kind": {
          "type": "string",
          "const": "defer"
        },
        "days": {
          "type": "integer",
          "minimum": 1
        }
      },
      "description": "The deposit is deferred by this many days."
    },
    "disqualified_by": {
      "oneOf": [
        {
          "$ref": "#/$defs/disq_none"
        },
        {
          "$ref": "#/$defs/disq_condition"
        }
      ]
    },
    "disq_none": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "kind"
      ],
      "properties": {
        "kind": {
          "type": "string",
          "const": "none"
        }
      },
      "description": "The waiver has no disqualifier of its own."
    },
    "disq_condition": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "kind",
        "condition"
      ],
      "properties": {
        "kind": {
          "type": "string",
          "const": "condition"
        },
        "condition": {
          "$ref": "#/$defs/condition"
        }
      },
      "description": "The waiver is lost while this condition holds (New York: terminated for nonpayment in the past six months)."
    },
    "instalment": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "id",
        "fraction",
        "days_after"
      ],
      "properties": {
        "id": {
          "$ref": "#/$defs/id"
        },
        "fraction": {
          "type": "number",
          "exclusiveMinimum": 0,
          "exclusiveMaximum": 1
        },
        "days_after": {
          "type": "integer",
          "minimum": 0
        }
      },
      "description": "A fixed-schedule instalment: this fraction of the deposit, this many days after the determination. The fractions summing to 1 is the area's insert check. Instalments tied to bills are not in version 1."
    },
    "amount_none": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "strategy",
        "version"
      ],
      "properties": {
        "strategy": {
          "type": "string",
          "const": "none"
        },
        "version": {
          "type": "integer",
          "minimum": 1,
          "maximum": 1
        }
      },
      "description": "The tariff states no required amount of its own: the law's cap, or the core's decision, governs."
    },
    "amount_fixed": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "strategy",
        "version",
        "amount"
      ],
      "properties": {
        "strategy": {
          "type": "string",
          "const": "fixed"
        },
        "version": {
          "type": "integer",
          "minimum": 1,
          "maximum": 1
        },
        "amount": {
          "type": "number",
          "exclusiveMinimum": 0
        }
      },
      "description": "A flat deposit (Brenham: homeowner 150, renter 250, landlord 300)."
    },
    "amount_months": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "strategy",
        "version",
        "months",
        "of",
        "minimum_amount"
      ],
      "properties": {
        "strategy": {
          "type": "string",
          "const": "months_of_billing"
        },
        "version": {
          "type": "integer",
          "minimum": 1,
          "maximum": 1
        },
        "months": {
          "type": "number",
          "exclusiveMinimum": 0
        },
        "of": {
          "type": "string",
          "enum": [
            "average",
            "highest"
          ]
        },
        "minimum_amount": {
          "$ref": "#/$defs/minimum_amount"
        }
      },
      "description": "This many months of the customer's average or highest monthly bill, not less than the minimum (Brenham commercial: twice the highest monthly bill, minimum 300)."
    },
    "amount_case": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "strategy",
        "version"
      ],
      "properties": {
        "strategy": {
          "type": "string",
          "const": "case_by_case"
        },
        "version": {
          "type": "integer",
          "minimum": 1,
          "maximum": 1
        }
      },
      "description": "The utility sets the amount for each customer from the customer's history (Winona commercial)."
    },
    "amount": {
      "oneOf": [
        {
          "$ref": "#/$defs/amount_none"
        },
        {
          "$ref": "#/$defs/amount_fixed"
        },
        {
          "$ref": "#/$defs/amount_months"
        },
        {
          "$ref": "#/$defs/amount_case"
        }
      ]
    },
    "min_none": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "kind"
      ],
      "properties": {
        "kind": {
          "type": "string",
          "const": "none"
        }
      }
    },
    "min_amount": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "kind",
        "amount"
      ],
      "properties": {
        "kind": {
          "type": "string",
          "const": "amount"
        },
        "amount": {
          "type": "number",
          "exclusiveMinimum": 0
        }
      },
      "description": "No refund below this amount."
    },
    "minimum_amount": {
      "oneOf": [
        {
          "$ref": "#/$defs/min_none"
        },
        {
          "$ref": "#/$defs/min_amount"
        }
      ]
    },
    "tariff_waiver": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "id",
        "ground",
        "applies_to",
        "effect",
        "also_releases_held",
        "disqualified_by"
      ],
      "properties": {
        "id": {
          "$ref": "#/$defs/id"
        },
        "ground": {
          "$ref": "#/$defs/code"
        },
        "applies_to": {
          "$ref": "#/$defs/applies_to"
        },
        "effect": {
          "$ref": "#/$defs/effect"
        },
        "also_releases_held": {
          "type": "boolean"
        },
        "disqualified_by": {
          "$ref": "#/$defs/disqualified_by"
        }
      },
      "description": "A ground on which the utility's own tariff waives a deposit, in the utility's own name for it. The law only grants the permission (a waiver class that is tariff-defined)."
    }
  }
}$schema$::jsonb, DATE '2026-10-12',
                'Deposit tariff: a utility''s own deposit record for one of its categories — the amount it asks, its triggers, its waiver grounds, its instalments',
                'law/deposit/deposit_tariff.v1.schema.json');
    END IF;
END
$kinds$;

-- The Texas deposit interest rate is a published value, in the unit the law states it in. Its values are entered from
-- each publication by a reviewed migration; none is seeded (an invented rate would be law the database made up).
INSERT INTO public.rule_parameters (parameter_name, unit, scoped_by, value_min, value_max, description, source_note)
SELECT 'tx_deposit_interest_rate', 'annual_rate_fraction', ARRAY['state_code'], 0, 1,
       'The annual rate of interest on customer deposits in Texas, set once a year by the Public Utility Commission (Utilities Code 183.003): a fraction, 0.0287 is 2.87% a year.',
       'Texas Utilities Code 183.003; 16 TAC 7.45 (interest on deposits)'
 WHERE NOT EXISTS (SELECT 1 FROM public.rule_parameters WHERE parameter_name = 'tx_deposit_interest_rate');


-- ----------------------------------------------------------------------------
-- 4. The law table's hooks (read by the template; none writes)
-- ----------------------------------------------------------------------------
-- The latest day a citing record needs a law row in force: a deposit's posting
-- day, an accrual's period end, a return-due row's day, and the day of any
-- other event that names the row. A close must end after it. Called by the
-- template's history trigger under the closing role, which sees every tenant.
CREATE OR REPLACE FUNCTION public.deposit_rule_close_floor(p_rule_id uuid) RETURNS date
    LANGUAGE plpgsql STABLE
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_floor date;
BEGIN
    SELECT max(c.d) INTO v_floor FROM (
        SELECT d.posted_on AS d FROM public.deposits d WHERE d.rule_id = p_rule_id
        UNION ALL
        SELECT coalesce(e.period_end, e.effective_on) FROM public.deposit_events e WHERE e.rule_id = p_rule_id
        UNION ALL
        SELECT r.due_on FROM public.deposit_return_due r WHERE r.rule_id = p_rule_id
    ) c;
    RETURN v_floor;
END;
$$;
COMMENT ON FUNCTION public.deposit_rule_close_floor(uuid) IS
    'v5.4.2-15. The close floor of a deposit_rules row (rule_tables.close_floor): the latest date any record cites the row for — a deposit''s posting day, an accrual''s period end, a return-due row''s day, another event''s day — or NULL. Which row governs a later record is the core''s (it may cite a successor), so every citation counts. A close must end after it.';

-- What only the area can say about a new law row (the template does the rest):
-- the basis may be taken; the cap, the instalments, the triggers, the waivers
-- and the return rules agree with themselves; every published rate named is a
-- registered one. A delegated document has nothing to cross-check but the basis.
CREATE OR REPLACE FUNCTION public.deposit_rule_insert_check(p_row jsonb) RETURNS void
    LANGUAGE plpgsql STABLE
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_t     jsonb := p_row -> 'terms';
    v_who   text := format('deposit rule (%s %s %s %s)', p_row ->> 'state_code', p_row ->> 'service_type', p_row ->> 'customer_class', p_row ->> 'basis');
    v_n     integer;
    v_comb  text;
    v_dup   text;
    v_sum   numeric;
    v_name  text;
    v_bad   text;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.deposit_bases b WHERE b.basis_code = p_row ->> 'basis' AND b.insertable) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('%s: the basis %s exists only for carried history; the core refuses to decide one, so no law row is written for it (v5.4.2-15)', v_who, p_row ->> 'basis'),
            ERRCODE = 'check_violation';
    END IF;
    IF v_t ->> 'governs' IS DISTINCT FROM 'law' THEN
        RETURN;
    END IF;

    -- The cap.
    IF v_t #>> '{cap,strategy}' = 'parts' THEN
        v_n := jsonb_array_length(v_t #> '{cap,parts}');
        v_comb := v_t #>> '{cap,combinator}';
        IF v_comb = 'single' AND v_n <> 1 THEN
            RAISE EXCEPTION USING
                MESSAGE = format('%s: a single cap has exactly one part; this one has %s (v5.4.2-15)', v_who, v_n), ERRCODE = 'check_violation';
        END IF;
        IF v_comb <> 'single' AND v_n < 2 THEN
            RAISE EXCEPTION USING
                MESSAGE = format('%s: a %s cap needs two or more parts; this one has %s (v5.4.2-15)', v_who, v_comb, v_n), ERRCODE = 'check_violation';
        END IF;
        SELECT p ->> 'kind' INTO v_dup FROM jsonb_array_elements(v_t #> '{cap,parts}') p
         GROUP BY p ->> 'kind' HAVING count(*) > 1 ORDER BY 1 LIMIT 1;
        IF v_dup IS NOT NULL THEN
            RAISE EXCEPTION USING
                MESSAGE = format('%s: the cap names the cap part kind %s twice — a deposit names the part that governed its cap by kind and id, one part of each kind (v5.4.2-15)', v_who, v_dup),
                ERRCODE = 'check_violation';
        END IF;
        IF v_comb <> 'single' AND (SELECT count(*) FROM jsonb_array_elements(v_t #> '{cap,parts}') p WHERE p ->> 'kind' <> 'fixed_amount') > 1 THEN
            RAISE EXCEPTION USING
                MESSAGE = format('%s: a %s cap with two parts that need different billing figures (annual, monthly, the highest bills …) cannot be recorded on one basis figure; version 1 allows one such part and any fixed amounts (v5.4.2-15)', v_who, v_comb),
                ERRCODE = 'check_violation';
        END IF;
        IF (SELECT array_agg(p ->> 'kind' ORDER BY o) IS DISTINCT FROM array_agg(p ->> 'kind' ORDER BY p ->> 'kind' COLLATE "C")
              FROM jsonb_array_elements(v_t #> '{cap,parts}') WITH ORDINALITY AS e(p, o)) THEN
            RAISE EXCEPTION USING
                MESSAGE = format('%s: the cap lists its parts out of order — by kind, in byte order, so one law has one document (v5.4.2-15)', v_who), ERRCODE = 'check_violation';
        END IF;
    END IF;

    -- The instalments: the fractions add up to the whole, in order of days.
    IF jsonb_array_length(v_t -> 'instalments') > 0 THEN
        SELECT sum((i ->> 'fraction')::numeric) INTO v_sum FROM jsonb_array_elements(v_t -> 'instalments') i;
        IF v_sum IS DISTINCT FROM 1 THEN
            RAISE EXCEPTION USING
                MESSAGE = format('%s: the instalment fractions add up to %s; they must add up to exactly 1 (v5.4.2-15)', v_who, v_sum), ERRCODE = 'check_violation';
        END IF;
        IF EXISTS (SELECT 1 FROM (SELECT (i ->> 'days_after')::integer AS d, lag((i ->> 'days_after')::integer) OVER (ORDER BY o) AS prev
                                    FROM jsonb_array_elements(v_t -> 'instalments') WITH ORDINALITY AS e(i, o)) x
                    WHERE x.prev IS NOT NULL AND x.d <= x.prev) THEN
            RAISE EXCEPTION USING
                MESSAGE = format('%s: the instalments are out of order — strictly ascending in days after the determination (v5.4.2-15)', v_who), ERRCODE = 'check_violation';
        END IF;
    END IF;

    -- Triggers: one per code. A waiver may reach only a trigger the document has.
    SELECT t ->> 'trigger_code' INTO v_dup FROM jsonb_array_elements(v_t -> 'triggers') t
     GROUP BY t ->> 'trigger_code' HAVING count(*) > 1 ORDER BY 1 LIMIT 1;
    IF v_dup IS NOT NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('%s: the document names the trigger code %s in two triggers — a deposit cites the trigger it was decided on by code (v5.4.2-15)', v_who, v_dup), ERRCODE = 'check_violation';
    END IF;
    SELECT w ->> 'id' || ' (' || (w #>> '{applies_to,trigger_code}') || ')' INTO v_bad FROM jsonb_array_elements(v_t -> 'waivers') w
     WHERE w #>> '{applies_to,kind}' = 'trigger'
       AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_t -> 'triggers') t WHERE t ->> 'trigger_code' = w #>> '{applies_to,trigger_code}')
     ORDER BY w ->> 'id' LIMIT 1;
    IF v_bad IS NOT NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('%s: waiver %s reaches the trigger, which the document has no trigger for (v5.4.2-15)', v_who, v_bad), ERRCODE = 'check_violation';
    END IF;

    -- Return rules: one per reason; a return on entering a waiver class needs that waiver.
    SELECT r #>> '{when,reason}' INTO v_dup FROM jsonb_array_elements(v_t -> 'return') r
     GROUP BY r #>> '{when,reason}' HAVING count(*) > 1 ORDER BY 1 LIMIT 1;
    IF v_dup IS NOT NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('%s: the document names the return reason %s in two return rules — a return-due record cites the rule it rests on, one rule per reason (v5.4.2-15)', v_who, v_dup), ERRCODE = 'check_violation';
    END IF;
    IF v_t #>> '{cap,strategy}' IS DISTINCT FROM 'parts' AND EXISTS (SELECT 1 FROM jsonb_array_elements(v_t -> 'return') r WHERE r #>> '{when,reason}' = 'excess_over_cap') THEN
        RAISE EXCEPTION USING
            MESSAGE = format('%s: a return of the excess over the cap needs a cap; this document sets none (v5.4.2-15)', v_who), ERRCODE = 'check_violation';
    END IF;
    SELECT t ->> 'id' || ' (' || (g ->> 'kind') || ')' INTO v_bad FROM jsonb_array_elements(v_t -> 'triggers') t, jsonb_array_elements(t -> 'guards') g
     GROUP BY t ->> 'id', g ->> 'kind' HAVING count(*) > 1 ORDER BY 1 LIMIT 1;
    IF v_bad IS NOT NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('%s: trigger %s has two guards of one kind — one guard per kind, so the days to pay and the like are one number (v5.4.2-15)', v_who, v_bad), ERRCODE = 'check_violation';
    END IF;
    SELECT r ->> 'id' || ' (' || (r #>> '{when,waiver_class}') || ')' INTO v_bad FROM jsonb_array_elements(v_t -> 'return') r
     WHERE r #>> '{when,reason}' = 'entered_waiver_class'
       AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_t -> 'waivers') w WHERE w ->> 'waiver_class' = r #>> '{when,waiver_class}')
     ORDER BY r ->> 'id' LIMIT 1;
    IF v_bad IS NOT NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('%s: return rule %s on entering the waiver class — the document has no waiver of that class (v5.4.2-15)', v_who, v_bad), ERRCODE = 'check_violation';
    END IF;
    SELECT string_agg(DISTINCT d, ', ' ORDER BY d) INTO v_bad
      FROM jsonb_array_elements(v_t -> 'return') r, jsonb_array_elements_text(coalesce(r #> '{when,disqualifiers}', '[]'::jsonb)) d
     WHERE NOT EXISTS (SELECT 1 FROM public.deposit_refund_disqualifiers q WHERE q.disqualifier_code = d);
    IF v_bad IS NOT NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('%s: a return rule names the disqualifier %s, not in deposit_refund_disqualifiers (v5.4.2-15)', v_who, v_bad), ERRCODE = 'foreign_key_violation';
    END IF;

    -- Interest: every published rate named is registered; by_hold thresholds ascend.
    IF v_t #>> '{interest,strategy}' = 'bearing' AND v_t #>> '{interest,rate,kind}' = 'published' THEN
        SELECT string_agg(DISTINCT n, ', ' ORDER BY n) INTO v_bad FROM (
            SELECT v_t #>> '{interest,rate,name}' AS n
            UNION ALL
            SELECT h ->> 'name' FROM jsonb_array_elements(v_t #> '{interest,rate,by_hold}') h) x
         WHERE NOT EXISTS (SELECT 1 FROM public.rule_parameters p WHERE p.parameter_name = x.n);
        IF v_bad IS NOT NULL THEN
            RAISE EXCEPTION USING
                MESSAGE = format('%s: the interest rate names the published value %s, which is not a registered parameter (rule_parameters) (v5.4.2-15)', v_who, v_bad),
                ERRCODE = 'check_violation';
        END IF;
        IF EXISTS (SELECT 1 FROM (SELECT (h ->> 'up_to_months')::integer AS m, lag((h ->> 'up_to_months')::integer) OVER (ORDER BY o) AS prev
                                    FROM jsonb_array_elements(v_t #> '{interest,rate,by_hold}') WITH ORDINALITY AS e(h, o)) x
                    WHERE x.prev IS NOT NULL AND x.m <= x.prev) THEN
            RAISE EXCEPTION USING
                MESSAGE = format('%s: the rate''s by_hold thresholds (up_to_months) are not strictly ascending (v5.4.2-15)', v_who), ERRCODE = 'check_violation';
        END IF;
    END IF;
END;
$$;
COMMENT ON FUNCTION public.deposit_rule_insert_check(jsonb) IS
    'v5.4.2-15. The area predicate of deposit_rules (rule_tables.insert_check), over the new row with its document: the basis may be taken (not carried history); a single cap has exactly one part and a lesser-of or greater-of two or more, each kind once, in byte order; the instalment fractions add up to exactly 1 in strictly ascending days; one trigger per code and a waiver reaches only a trigger the document has; one return rule per reason, a return on entering a waiver class needs that waiver, and a disqualifier is in its vocabulary; every published rate the interest names is a registered parameter and by_hold thresholds ascend. Raises check_violation. A delegated document has only the basis to check.';


-- ----------------------------------------------------------------------------
-- 5. deposit_rules — the law per (customer class, basis), dated
-- ----------------------------------------------------------------------------
-- A law table on the template: platform-held, never edited — the one change is
-- a stamped close above the close floor — and cited by every record by id.
-- A key with no row in force means no rule is known: the core refuses, never
-- falls back. The content is the document; trigger_codes, waiver_classes,
-- return_reasons and cap_part_ids are its facets.
CREATE TABLE IF NOT EXISTS public.deposit_rules (
    id                      uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    state_code              text NOT NULL,
    service_type            text NOT NULL,
    customer_class          text NOT NULL,
    basis                   text NOT NULL,
    owner_types             text[],
    system_kinds            text[],
    commission_jurisdiction boolean,
    owner_span              int4multirange NOT NULL,
    system_span             int4multirange NOT NULL,
    jurisdiction_span       int4range NOT NULL,
    effective_from          date NOT NULL,
    effective_to            date,
    source_note             text NOT NULL,
    terms_kind              text NOT NULL,
    terms_version           integer NOT NULL,
    terms_source            text NOT NULL,
    terms                   jsonb NOT NULL,
    trigger_codes           text[] NOT NULL,
    waiver_classes          text[] NOT NULL,
    return_reasons          text[] NOT NULL,
    cap_part_ids            text[] NOT NULL,
    created_at              timestamp with time zone DEFAULT now() NOT NULL,
    recorded_txid           bigint,
    closed_at               timestamp with time zone,
    closed_by               text,
    CONSTRAINT deposit_rules_pkey PRIMARY KEY (id),
    CONSTRAINT deposit_rules_class_fkey FOREIGN KEY (state_code, service_type, customer_class)
        REFERENCES public.deposit_customer_classes(state_code, service_type, class_code),
    CONSTRAINT deposit_rules_basis_fkey FOREIGN KEY (basis) REFERENCES public.deposit_bases(basis_code)
);
CREATE INDEX IF NOT EXISTS idx_deposit_rules_key ON public.deposit_rules USING btree (state_code, service_type, customer_class, basis);

DO $register$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.rule_tables WHERE table_name = 'public.deposit_rules'::regclass) THEN
        PERFORM public.rule_table_register('public.deposit_rules', 'law', 'deposit', ARRAY['customer_class', 'basis'],
                                           ARRAY['cap_part_ids', 'return_reasons', 'trigger_codes', 'waiver_classes'],
                                           'public.deposit_rule_close_floor(uuid)', 'public.deposit_rule_insert_check(jsonb)');
    END IF;
END
$register$;

COMMENT ON TABLE public.deposit_rules IS
    'v5.4.2-15, on the rule-terms convention. What a state''s law requires of a deposit, per (state, service, owner types, customer class, basis, dates): one LAW row of the kind deposit, platform-held, never edited — the one change is a stamped close above the close floor — and cited by deposits, accruals and return-due rows by id. The content is the row''s document (terms, validated against deposit v1): the cap, the triggers for an additional deposit, the waivers, the interest, the return rules, the instalments. trigger_codes, waiver_classes, return_reasons and cap_part_ids are facets of the document. The eight investor-owned and cooperative Texas gas rows say what 16 TAC 7.45 and 11 U.S.C. 366 said and -06 enforced; a city-owned system finds a delegation: 16 TAC 7.45 does not bind it, so its policy is its tariff (deposit_tariffs). Another state or service finds no row: unknown law is not permission. The database evaluates none of it: the core does.';
COMMENT ON COLUMN public.deposit_rules.cap_part_ids IS 'A facet (terms.cap.parts[*].id): the ids of the cap''s parts. A deposit under a statutory cap names the part that governed by id.';
COMMENT ON COLUMN public.deposit_rules.return_reasons IS 'A facet (terms.return[*].when.reason): the reasons a deposit may fall due for return under the document.';
COMMENT ON COLUMN public.deposit_rules.trigger_codes IS 'A facet (terms.triggers[*].trigger_code): the triggers of an additional deposit the document names.';
COMMENT ON COLUMN public.deposit_rules.waiver_classes IS 'A facet (terms.waivers[*].waiver_class): the waiver classes the document names, of the row''s own state and service.';
REVOKE ALL ON FUNCTION public.deposit_rule_close_floor(uuid), public.deposit_rule_insert_check(jsonb) FROM PUBLIC, tally_app, tally_core;



-- ----------------------------------------------------------------------------
-- 5b. The Texas law rows, and a city's delegations
-- ----------------------------------------------------------------------------
-- What -06 enforced, as documents: 16 TAC 7.45 (credit evaluation, tariff and
-- additional-deposit bases; a residential cap of one-sixth of annual billing;
-- the usage trigger at twice the estimate, payable in two days; four waivers;
-- interest on cash from the 30th day, retroactively, at the published rate;
-- a return after twelve clean bills or when the account closes) and 11 U.S.C.
-- 366 (adequate assurance: no cap, no waiver, no return on 7.45's triggers,
-- cash interest as -06 accrued it). They bind investor-owned and cooperative
-- owners, distribution systems, either jurisdiction status, from 2004-07-12
-- (Utilities Code 101.003(7) excludes a municipal corporation: a city's rows
-- delegate to its own tariff). Seeded through the template's strict seed: a
-- re-run that finds the same row is silent, a row that differs raises.
DO $seed$
DECLARE
    v_interest  constant jsonb := '{"strategy": "bearing", "version": 1, "instruments": ["cash"],
        "rate": {"kind": "published", "name": "tx_deposit_interest_rate", "binding": "minimum", "by_hold": []},
        "method": {"kind": "simple"}, "day_count": "actual_365", "hold": {"kind": "minimum", "days": 30, "retroactive": true},
        "credit": {"kind": "at_refund"}, "stops_on": ["refund"], "forfeited_on": [],
        "penalty": {"kind": "none"}, "rounding": {"kind": "none"}}'::jsonb;
    v_return    constant jsonb := '[{"id": "r1", "instruments": ["cash"], "conditions": [], "minimum_amount": {"kind": "none"}, "deadline": {"kind": "none"},
                   "hold_while": [], "vests": "unruled",
                   "when": {"reason": "clean_bill_history", "count": 12, "measure": "bills", "max_delinquencies": 2, "lookback": {"kind": "whole_hold"},
                            "disqualifiers": ["disconnect_nonpayment"], "exclude_disputed": false}},
                  {"id": "r2", "instruments": ["cash"], "conditions": [], "minimum_amount": {"kind": "none"}, "deadline": {"kind": "none"},
                   "hold_while": [], "vests": "unruled", "when": {"reason": "account_closed"}}]'::jsonb;
    v_waivers   constant jsonb := (SELECT jsonb_agg(jsonb_build_object('id', 'w' || n, 'waiver_class', w, 'applies_to', '{"kind": "any_trigger"}'::jsonb,
                                         'effect', '{"kind": "excuse"}'::jsonb, 'also_releases_held', false, 'disqualified_by', '{"kind": "none"}'::jsonb) ORDER BY n)
                                     FROM unnest(ARRAY['family_violence_certified', 'age_65_no_balance', 'good_payment_history', 'tariff']) WITH ORDINALITY AS x(w, n));
    v_usage     constant jsonb := '[{"id": "t1", "trigger_code": "usage_doubled", "condition": {"kind": "ratio", "measure": "usage_to_estimate", "op": "at_least", "value": 2},
                          "guards": [{"kind": "payment_due_days", "days": 2}]}]'::jsonb;
    v_cap       constant jsonb := '{"strategy": "parts", "version": 1, "combinator": "single", "scope": "per_deposit",
                         "parts": [{"id": "c1", "kind": "fraction_of_annual_billing", "divisor": 6}]}'::jsonb;
    v_doc       jsonb;
    v_class     text;
    v_basis     text;
BEGIN
    FOREACH v_class IN ARRAY ARRAY['residential', 'non_residential'] LOOP
        FOREACH v_basis IN ARRAY ARRAY['credit_evaluation', 'additional_trigger', 'tariff', 'adequate_assurance_366'] LOOP
            IF v_basis = 'adequate_assurance_366' THEN
                v_doc := jsonb_build_object('governs', 'law', 'citation', '11 U.S.C. 366', 'cap', '{"strategy": "none", "version": 1}'::jsonb,
                                            'triggers', '[]'::jsonb, 'waivers', '[]'::jsonb, 'interest', v_interest, 'return', '[]'::jsonb, 'instalments', '[]'::jsonb);
            ELSE
                v_doc := jsonb_build_object('governs', 'law', 'citation', '16 TAC 7.45',
                                            'cap', CASE WHEN v_class = 'residential' THEN v_cap ELSE '{"strategy": "none", "version": 1}'::jsonb END,
                                            'triggers', CASE WHEN v_basis = 'additional_trigger' THEN v_usage ELSE '[]'::jsonb END,
                                            'waivers', v_waivers, 'interest', v_interest, 'return', v_return, 'instalments', '[]'::jsonb);
            END IF;
            PERFORM public.rule_row_seed('public.deposit_rules', jsonb_build_object(
                'state_code', 'TX', 'service_type', 'gas', 'customer_class', v_class, 'basis', v_basis,
                'owner_types', ARRAY['investor_owned', 'cooperative'], 'system_kinds', ARRAY['distribution'], 'commission_jurisdiction', NULL,
                'effective_from', DATE '2004-07-12', 'effective_to', NULL,
                'source_note', CASE WHEN v_basis = 'adequate_assurance_366'
                                    THEN '11 U.S.C. 366(c): adequate assurance of payment for a debtor in bankruptcy; no 16 TAC 7.45 cap, waiver or return applies (-06)'
                                    ELSE '16 TAC 7.45 (deposits), as -06 enforced it (decision tables #53-#55); ' ||
                                         CASE WHEN v_class = 'residential' THEN 'the cap of one-sixth of estimated annual billing applies' ELSE 'no cap is stated for a non-residential deposit (Kyle question K1)' END END,
                'terms_kind', 'deposit', 'terms_version', 1, 'terms_source', v_doc::text));
            -- a city-owned system: the law leaves the deposit to its tariff
            PERFORM public.rule_row_seed('public.deposit_rules', jsonb_build_object(
                'state_code', 'TX', 'service_type', 'gas', 'customer_class', v_class, 'basis', v_basis,
                'owner_types', ARRAY['municipal'], 'system_kinds', ARRAY['distribution'], 'commission_jurisdiction', NULL,
                'effective_from', DATE '2004-07-12', 'effective_to', NULL,
                'source_note', '16 TAC 7.45 does not bind a municipal corporation (Utilities Code 101.003(7)(A) excludes it from "gas utility"); a city''s deposit policy is its own tariff',
                'terms_kind', 'deposit', 'terms_version', 1,
                'terms_source', jsonb_build_object('governs', 'delegated_to_utility', 'citation', 'Tex. Util. Code 101.003(7)',
                                                   'note', 'The city sets its own deposit policy in its tariff')::text));
        END LOOP;
    END LOOP;
END
$seed$;



-- ----------------------------------------------------------------------------
-- 6. The utility's own deposit categories (Ryan, decision 5)
-- ----------------------------------------------------------------------------
-- A utility names its own deposit categories — owner, renter, landlord, small
-- commercial — each mapped to exactly one law class. Its tariff is keyed on the
-- category; the comparator reads the mapping to choose the law rows. Tenant-
-- owned under row security; a category is never edited or deleted (tariffs and
-- deposits cite it, and a different class would change what they mean).
CREATE TABLE IF NOT EXISTS public.deposit_utility_categories (
    id            uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id     uuid NOT NULL,
    state_code    text NOT NULL,
    service_type  text NOT NULL,
    category_code text NOT NULL,
    law_class     text NOT NULL,
    description   text NOT NULL,
    created_at    timestamp with time zone DEFAULT now() NOT NULL,
    created_by    uuid,
    CONSTRAINT deposit_utility_categories_pkey PRIMARY KEY (id),
    CONSTRAINT deposit_utility_categories_key UNIQUE (tenant_id, state_code, service_type, category_code),
    CONSTRAINT deposit_utility_categories_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id),
    CONSTRAINT deposit_utility_categories_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id),
    CONSTRAINT deposit_utility_categories_law_class_fkey FOREIGN KEY (state_code, service_type, law_class)
        REFERENCES public.deposit_customer_classes(state_code, service_type, class_code),
    CONSTRAINT deposit_utility_categories_code_check CHECK ((category_code ~ '^[a-z][a-z0-9_]*$'::text)),
    CONSTRAINT deposit_utility_categories_state_check CHECK ((state_code ~ '^[A-Z]{2}$'::text)),
    CONSTRAINT deposit_utility_categories_service_check
        CHECK ((service_type = ANY (ARRAY['water'::text, 'sewer'::text, 'electric'::text, 'gas'::text, 'stormwater'::text, 'trash'::text, 'reclaimed_water'::text]))),
    CONSTRAINT deposit_utility_categories_description_check CHECK ((description ~ '[[:alnum:]]'::text))
);
CREATE INDEX IF NOT EXISTS idx_deposit_utility_categories_tenant ON public.deposit_utility_categories USING btree (tenant_id);
ALTER TABLE public.deposit_utility_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.deposit_utility_categories FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_isolation ON public.deposit_utility_categories;
CREATE POLICY tenant_isolation ON public.deposit_utility_categories USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));
REVOKE TRUNCATE ON public.deposit_utility_categories FROM tally_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.deposit_utility_categories TO tally_app;

CREATE OR REPLACE FUNCTION public.enforce_deposit_utility_category() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
BEGIN
    IF TG_OP = 'UPDATE' THEN
        RAISE EXCEPTION USING
            MESSAGE = format('deposit category %s is never edited: tariffs and deposits cite it, and a different law class would change what they mean — add a new category (v5.4.2-15)', OLD.category_code),
            ERRCODE = 'restrict_violation';
    ELSIF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION USING
            MESSAGE = format('deposit category %s is never deleted: tariffs and deposits cite it (v5.4.2-15)', OLD.category_code),
            ERRCODE = 'restrict_violation';
    END IF;
    NEW.created_at := now();
    BEGIN
        NEW.created_by := nullif(current_setting('app.user_id', true), '')::uuid;
    EXCEPTION WHEN OTHERS THEN
        NEW.created_by := NULL;
    END;
    RETURN NEW;
END;
$$;
COMMENT ON FUNCTION public.enforce_deposit_utility_category() IS
    'v5.4.2-15. BEFORE INSERT OR UPDATE OR DELETE on deposit_utility_categories (ENABLE ALWAYS): never edited, never deleted; created_at and created_by (the session user) stamped.';
DROP TRIGGER IF EXISTS a_enforce_deposit_utility_category ON public.deposit_utility_categories;
CREATE TRIGGER a_enforce_deposit_utility_category BEFORE INSERT OR UPDATE OR DELETE ON public.deposit_utility_categories
    FOR EACH ROW EXECUTE FUNCTION public.enforce_deposit_utility_category();
ALTER TABLE public.deposit_utility_categories ENABLE ALWAYS TRIGGER a_enforce_deposit_utility_category;
DROP TRIGGER IF EXISTS no_truncate ON public.deposit_utility_categories;
CREATE TRIGGER no_truncate BEFORE TRUNCATE ON public.deposit_utility_categories FOR EACH STATEMENT EXECUTE FUNCTION public.enforce_no_hard_delete();
ALTER TABLE public.deposit_utility_categories ENABLE ALWAYS TRIGGER no_truncate;
COMMENT ON TABLE public.deposit_utility_categories IS
    'v5.4.2-15 (Ryan, decision 5). The deposit categories a utility defines for itself, per state and service — owner, renter, landlord, small commercial — each mapped to exactly one law class (law_class). The utility''s tariff is keyed on the category (deposit_tariffs.tariff_category); a deposit records both its category and the law class it falls under, and the two must agree. Tenant-owned under row security; never edited or deleted.';


-- ----------------------------------------------------------------------------
-- 7. The utility's tariff record, and the comparison with the law
-- ----------------------------------------------------------------------------
-- ONE tariff record per utility, state, service and category (Ryan, decision
-- 2): the amount it asks, its triggers, its waiver grounds in its own name,
-- its instalments, so the comparator sees amount, triggers and waivers
-- together and a deposit cites one row. Never looser than the law.

-- The latest day a deposit cites the tariff row for.
CREATE OR REPLACE FUNCTION public.deposit_tariff_close_floor(p_tariff_id uuid) RETURNS date
    LANGUAGE plpgsql STABLE
    SET search_path = public, pg_temp
    AS $$
BEGIN
    RETURN (SELECT max(d.posted_on) FROM public.deposits d WHERE d.tariff_id = p_tariff_id);
END;
$$;
COMMENT ON FUNCTION public.deposit_tariff_close_floor(uuid) IS
    'v5.4.2-15. The close floor of a deposit_tariffs row: the latest posting day of a deposit citing it, or NULL (the caller sees its own deposits only, and a tariff row is cited only by its own utility''s).';

-- What only the area can say about a new tariff row. The writer's own utility
-- (the check runs before row-level security would, so it says what that would; a role
-- that bypasses row security, a reviewed migration's, writes for any utility);
-- the category is one of the writer's own for the state and service; the
-- trigger codes are in the vocabulary; the instalments add up.
CREATE OR REPLACE FUNCTION public.deposit_tariff_insert_check(p_row jsonb) RETURNS void
    LANGUAGE plpgsql STABLE
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_t    jsonb := p_row -> 'terms';
    v_who  text := format('deposit tariff (%s %s %s)', p_row ->> 'state_code', p_row ->> 'service_type', p_row ->> 'tariff_category');
    v_bad  text;
    v_sum  numeric;
BEGIN
    IF NOT public.is_platform_admin() AND (p_row ->> 'tenant_id')::uuid IS DISTINCT FROM public.get_user_tenant_id()
       AND NOT coalesce((SELECT r.rolsuper OR r.rolbypassrls FROM pg_roles r WHERE r.rolname = current_user), false) THEN
        RAISE EXCEPTION USING
            MESSAGE = 'new row violates row-level security policy for table "deposit_tariffs": a utility writes its own tariff only (v5.4.2-15)',
            ERRCODE = 'insufficient_privilege';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.deposit_utility_categories c
                    WHERE c.tenant_id = (p_row ->> 'tenant_id')::uuid AND c.state_code = p_row ->> 'state_code'
                      AND c.service_type = p_row ->> 'service_type' AND c.category_code = p_row ->> 'tariff_category') THEN
        RAISE EXCEPTION USING
            MESSAGE = format('%s: %s is not one of this utility''s deposit categories for %s %s — define it first (deposit_utility_categories) (v5.4.2-15)',
                             v_who, p_row ->> 'tariff_category', p_row ->> 'state_code', p_row ->> 'service_type'),
            ERRCODE = 'check_violation';
    END IF;
    SELECT string_agg(DISTINCT t ->> 'trigger_code', ', ' ORDER BY t ->> 'trigger_code') INTO v_bad
      FROM jsonb_array_elements(v_t -> 'triggers') t
     WHERE NOT EXISTS (SELECT 1 FROM public.deposit_triggers x WHERE x.trigger_code = t ->> 'trigger_code');
    IF v_bad IS NOT NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('%s: the trigger code %s is not in deposit_triggers — the platform''s vocabulary of triggers (v5.4.2-15)', v_who, v_bad),
            ERRCODE = 'foreign_key_violation';
    END IF;
    SELECT t ->> 'id' || ' (' || (g ->> 'kind') || ')' INTO v_bad FROM jsonb_array_elements(v_t -> 'triggers') t, jsonb_array_elements(t -> 'guards') g
     GROUP BY t ->> 'id', g ->> 'kind' HAVING count(*) > 1 ORDER BY 1 LIMIT 1;
    IF v_bad IS NOT NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('%s: trigger %s has two guards of one kind — one guard per kind (v5.4.2-15)', v_who, v_bad), ERRCODE = 'check_violation';
    END IF;
    IF jsonb_array_length(v_t -> 'instalments') > 0 THEN
        SELECT sum((i ->> 'fraction')::numeric) INTO v_sum FROM jsonb_array_elements(v_t -> 'instalments') i;
        IF v_sum IS DISTINCT FROM 1 THEN
            RAISE EXCEPTION USING
                MESSAGE = format('%s: the instalment fractions add up to %s; they must add up to exactly 1 (v5.4.2-15)', v_who, v_sum), ERRCODE = 'check_violation';
        END IF;
    END IF;
END;
$$;
COMMENT ON FUNCTION public.deposit_tariff_insert_check(jsonb) IS
    'v5.4.2-15. The area predicate of deposit_tariffs (rule_tables.insert_check), over the new row with its document: the writer is the row''s own utility; the category is one of that utility''s own for the state and service; every trigger code is in the vocabulary; the instalment fractions add up to 1. Raises.';

-- The tariff against the law (rule_tariff_check calls it with every law row in force over the tariff's dates that binds the
-- utility). It chooses the rows of the law class the category maps to, and returns the reasons the tariff is LOOSER, or cannot
-- be shown to be no looser (unknown law is not permission):
--   * no law row is known for the class at all;
--   * a deposit of N months of billing where the law caps at fewer — the law's cap converted to months (a fraction of annual
--     billing is 12 divided by the divisor; the lesser of several is the least of those that convert, the greater of several the
--     greatest, only when every part converts). Months of the HIGHEST bill, or a minimum amount, cannot be shown to fit a cap
--     stated on average billing, and are refused where such a cap exists;
--   * the law has not ruled on the cap, and the tariff names an amount;
--   * a trigger the law also names that fires sooner: a ratio of the same measure at a lower threshold (or the same, inclusive
--     where the law is strict); a count of the same event over the same unit with a lower count, a longer window, or without the
--     law's consecutive / disputed-bill protection; days to pay fewer than the law's (none given counts as none). A trigger of
--     the same code whose condition cannot be compared with the law's (another measure, another unit, a combined condition that
--     is not the law's own) is refused: it cannot be shown to fire no sooner.
-- Not compared, and said so: a flat amount against a fixed-dollar cap or any cap not stated in months, waivers, instalments.
-- The law's guards other than days to pay (service age, a recent move, notice,
-- a cure) are carried identically or refused. A trigger or waiver ground the law has no word on is the utility's own. A delegation compares
-- nothing about content. A flat amount is held at each deposit by its recorded cap check.
-- The simple conditions (a usage ratio, an event count) a condition is made of, through any all_of / any_of.
CREATE OR REPLACE FUNCTION public.deposit_condition_leaves(p_cond jsonb) RETURNS SETOF jsonb
    LANGUAGE plpgsql IMMUTABLE
    SET search_path = public, pg_temp
    AS $$
DECLARE
    x jsonb;
BEGIN
    IF p_cond ->> 'kind' IN ('ratio', 'count') THEN
        RETURN NEXT p_cond;
    ELSE
        FOR x IN SELECT e FROM jsonb_array_elements(coalesce(p_cond -> 'of', '[]'::jsonb)) e LOOP
            RETURN QUERY SELECT * FROM public.deposit_condition_leaves(x);
        END LOOP;
    END IF;
    RETURN;
END;
$$;
COMMENT ON FUNCTION public.deposit_condition_leaves(jsonb) IS
    'v5.4.2-15. The simple conditions a trigger condition is made of: a ratio or a count itself, or the ratios and counts under its all_of / any_of. The comparator matches a tariff trigger with a law trigger when they share a leaf measure (a usage ratio of the same measure, a count of the same event) whatever their codes.';

CREATE OR REPLACE FUNCTION public.deposit_tariff_compare(p_tariff jsonb, p_law jsonb) RETURNS text[]
    LANGUAGE plpgsql STABLE
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_class   text;
    v_t       jsonb := p_tariff -> 'terms';
    v_problem text[] := '{}';
    v_row     jsonb;
    v_months  numeric;
    v_allowed numeric;
    v_part    jsonb;
    v_pm      numeric;
    v_pms     numeric[];
    v_comb    text;
    v_tt      jsonb;
    v_lt      jsonb;
    v_tc      jsonb;
    v_lc      jsonb;
    v_tg      integer;
    v_lg      integer;
    v_range   daterange;
    v_cov     datemultirange;
    v_miss    datemultirange;
    v_seg     daterange;
    v_prof    public.utility_service_profiles%ROWTYPE;
    v_related boolean;
    v_samecode boolean;
    v_g       jsonb;
BEGIN
    SELECT c.law_class INTO v_class FROM public.deposit_utility_categories c
     WHERE c.tenant_id = (p_tariff ->> 'tenant_id')::uuid AND c.state_code = p_tariff ->> 'state_code'
       AND c.service_type = p_tariff ->> 'service_type' AND c.category_code = p_tariff ->> 'tariff_category';
    IF v_class IS NULL THEN
        RETURN v_problem;     -- the insert check has already refused an unknown category
    END IF;
    -- The class's own law rows cover the whole range of the tariff (the template's coverage counts every class's rows).
    v_range := daterange((p_tariff ->> 'effective_from')::date, (p_tariff ->> 'effective_to')::date, '[)');
    -- Per segment of the utility's profile (its owner type, system kind and jurisdiction status can change within the range), only
    -- the class's law rows that bind that segment count.
    v_miss := '{}'::datemultirange;
    FOR v_prof IN SELECT * FROM public.utility_service_profiles u
                   WHERE u.tenant_id = (p_tariff ->> 'tenant_id')::uuid AND u.service_type = p_tariff ->> 'service_type'
                     AND u.system_kind = p_tariff ->> 'system_kind' AND u.state_code = p_tariff ->> 'state_code'
                     AND u.voided_at IS NULL AND daterange(u.effective_from, u.effective_to, '[)') && v_range LOOP
        v_seg := daterange(v_prof.effective_from, v_prof.effective_to, '[)') * v_range;
        SELECT coalesce(range_agg(daterange((r ->> 'effective_from')::date, (r ->> 'effective_to')::date, '[)')), '{}'::datemultirange) INTO v_cov
          FROM jsonb_array_elements(p_law) r
         WHERE r ->> 'customer_class' = v_class
           AND (r ->> 'owner_span')::int4multirange @> public.rule_applicability_ordinal('owner_type', v_prof.owner_type)
           AND (r ->> 'system_span')::int4multirange @> public.rule_applicability_ordinal('system_kind', v_prof.system_kind)
           AND (r ->> 'jurisdiction_span')::int4range @> (CASE WHEN v_prof.commission_jurisdiction THEN 1 ELSE 0 END);
        v_miss := v_miss + (datemultirange(v_seg) - v_cov);
    END LOOP;
    IF v_miss <> '{}'::datemultirange THEN
        RETURN ARRAY[format('no law is known for the class %s this category maps to over %s — unknown law is not permission', v_class, v_miss)];
    END IF;
    FOR v_row IN SELECT r FROM jsonb_array_elements(p_law) r
                  WHERE r ->> 'customer_class' = v_class AND r #>> '{terms,governs}' = 'law' LOOP
        -- the amount, against the cap of the bases that set the initial deposit
        IF (v_row ->> 'basis') IN ('credit_evaluation', 'tariff') AND v_t #>> '{amount,strategy}' IN ('fixed', 'months_of_billing')
           AND v_row #>> '{terms,cap,strategy}' = 'unruled' THEN
            v_problem := v_problem || format('the law has not ruled on the cap for %s (%s), so an amount cannot be shown to be within it', v_class, v_row ->> 'basis');
        END IF;
        IF v_t #>> '{amount,strategy}' = 'months_of_billing' AND (v_row ->> 'basis') IN ('credit_evaluation', 'tariff')
           AND v_row #>> '{terms,cap,strategy}' = 'parts' THEN
            v_months := (v_t #>> '{amount,months}')::numeric;
            v_comb := v_row #>> '{terms,cap,combinator}';
            v_pms := '{}';
            FOR v_part IN SELECT p FROM jsonb_array_elements(v_row #> '{terms,cap,parts}') p LOOP
                v_pm := CASE v_part ->> 'kind'
                            WHEN 'fraction_of_annual_billing' THEN 12 / (v_part ->> 'divisor')::numeric
                            WHEN 'months_of_billing' THEN (v_part ->> 'months')::numeric
                        END;
                v_pms := v_pms || v_pm;       -- NULL when the part is not stated in months
            END LOOP;
            v_allowed := CASE
                WHEN v_comb = 'single' OR v_comb = 'lesser_of' THEN (SELECT min(x) FROM unnest(v_pms) x)
                WHEN v_comb = 'greater_of' AND NOT EXISTS (SELECT 1 FROM unnest(v_pms) x WHERE x IS NULL) THEN (SELECT max(x) FROM unnest(v_pms) x)
            END;
            IF v_comb = 'single' AND EXISTS (SELECT 1 FROM unnest(v_pms) x WHERE x IS NULL) THEN
                v_allowed := NULL;
            END IF;
            IF v_allowed IS NOT NULL THEN
                IF v_t #>> '{amount,of}' = 'highest' THEN
                    v_problem := v_problem || format('months of the highest bill cannot be shown to fit the law''s cap for %s (%s), which is stated on average billing', v_class, v_row ->> 'basis');
                ELSIF v_t #>> '{amount,minimum_amount,kind}' = 'amount' THEN
                    v_problem := v_problem || format('a minimum amount cannot be shown to fit the law''s cap for %s (%s)', v_class, v_row ->> 'basis');
                ELSIF v_months > v_allowed THEN
                    v_problem := v_problem || format('%s months of billing, where the law''s cap for %s (%s) is %s months',
                                                     trim_scale(v_months), v_class, v_row ->> 'basis', trim_scale(round(v_allowed, 4)));
                END IF;
            END IF;
        END IF;
        -- the triggers the law names: matched by code, and by what they measure (another code for the same usage ratio or the same
        -- event count is still that trigger)
        IF (v_row ->> 'basis') = 'additional_trigger' THEN
            FOR v_tt IN SELECT t FROM jsonb_array_elements(v_t -> 'triggers') t LOOP
                v_tc := v_tt -> 'condition';
                FOR v_lt IN SELECT t FROM jsonb_array_elements(v_row #> '{terms,triggers}') t LOOP
                    v_lc := v_lt -> 'condition';
                    v_samecode := v_lt ->> 'trigger_code' = v_tt ->> 'trigger_code';
                    v_related := v_samecode OR EXISTS (
                        SELECT 1 FROM public.deposit_condition_leaves(v_tc) a, public.deposit_condition_leaves(v_lc) b
                         WHERE (a ->> 'kind' = 'ratio' AND b ->> 'kind' = 'ratio' AND a ->> 'measure' = b ->> 'measure')
                            OR (a ->> 'kind' = 'count' AND b ->> 'kind' = 'count' AND a ->> 'event' = b ->> 'event'));
                    CONTINUE WHEN NOT v_related;
                    IF v_tc = v_lc THEN
                        NULL;
                    ELSIF v_tc ->> 'kind' = 'ratio' AND v_lc ->> 'kind' = 'ratio' AND v_tc ->> 'measure' = v_lc ->> 'measure' THEN
                        -- fires sooner: a lower threshold, or the same one inclusive where the law is strict
                        IF (v_tc ->> 'value')::numeric < (v_lc ->> 'value')::numeric
                           OR ((v_tc ->> 'value')::numeric = (v_lc ->> 'value')::numeric AND v_tc ->> 'op' = 'at_least' AND v_lc ->> 'op' = 'greater_than') THEN
                            v_problem := v_problem || format('the %s trigger fires at %s of %s, where the law waits for %s', v_tt ->> 'trigger_code',
                                                             trim_scale((v_tc ->> 'value')::numeric), v_tc ->> 'measure', trim_scale((v_lc ->> 'value')::numeric));
                        END IF;
                    ELSIF v_tc ->> 'kind' = 'count' AND v_lc ->> 'kind' = 'count' AND v_tc ->> 'event' = v_lc ->> 'event'
                          AND v_tc #>> '{window,unit}' = v_lc #>> '{window,unit}' THEN
                        IF (v_tc ->> 'at_least')::numeric < (v_lc ->> 'at_least')::numeric THEN
                            v_problem := v_problem || format('the %s trigger fires at %s %s events, where the law waits for %s', v_tt ->> 'trigger_code',
                                                             v_tc ->> 'at_least', v_tc ->> 'event', v_lc ->> 'at_least');
                        END IF;
                        IF (v_tc #>> '{window,size}')::numeric > (v_lc #>> '{window,size}')::numeric THEN
                            v_problem := v_problem || format('the %s trigger counts over %s %s, where the law counts over %s', v_tt ->> 'trigger_code',
                                                             v_tc #>> '{window,size}', v_tc #>> '{window,unit}', v_lc #>> '{window,size}');
                        END IF;
                        IF (v_lc ->> 'consecutive')::boolean AND NOT (v_tc ->> 'consecutive')::boolean THEN
                            v_problem := v_problem || format('the %s trigger does not require the events to be consecutive, where the law does', v_tt ->> 'trigger_code');
                        END IF;
                        IF (v_lc ->> 'exclude_disputed')::boolean AND NOT (v_tc ->> 'exclude_disputed')::boolean THEN
                            v_problem := v_problem || format('the %s trigger counts disputed bills, where the law excludes them', v_tt ->> 'trigger_code');
                        END IF;
                    ELSE
                        v_problem := v_problem || format('the %s trigger''s condition cannot be compared with the law''s %s trigger (%s against %s) and so cannot be shown to fire no sooner',
                                                         v_tt ->> 'trigger_code', v_lt ->> 'trigger_code', v_tc ->> 'kind', v_lc ->> 'kind');
                    END IF;
                    -- the days the customer has to pay: the tariff may give more, never fewer
                    v_lg := NULL;
                    v_tg := NULL;
                    SELECT (g ->> 'days')::integer INTO v_lg FROM jsonb_array_elements(v_lt -> 'guards') g WHERE g ->> 'kind' = 'payment_due_days';
                    IF v_lg IS NOT NULL THEN
                        SELECT (g ->> 'days')::integer INTO v_tg FROM jsonb_array_elements(v_tt -> 'guards') g WHERE g ->> 'kind' = 'payment_due_days';
                        IF coalesce(v_tg, 0) < v_lg THEN
                            v_problem := v_problem || format('the %s trigger gives %s days to pay, where the law gives %s', v_tt ->> 'trigger_code', coalesce(v_tg::text, 'no'), v_lg);
                        END IF;
                    END IF;
                    -- the law's other guards (service age, a recent move, notice, a cure) are the customer's protections: carried exactly or refused
                    FOR v_g IN SELECT g FROM jsonb_array_elements(v_lt -> 'guards') g WHERE g ->> 'kind' <> 'payment_due_days' LOOP
                        IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_tt -> 'guards') x WHERE x = v_g) THEN
                            v_problem := v_problem || format('the %s trigger does not carry the law''s guard %s', v_tt ->> 'trigger_code', v_g);
                        END IF;
                    END LOOP;
                END LOOP;
            END LOOP;
        END IF;
    END LOOP;
    RETURN coalesce((SELECT array_agg(DISTINCT x ORDER BY x) FROM unnest(v_problem) x), '{}');
END;
$$;
COMMENT ON FUNCTION public.deposit_tariff_compare(jsonb, jsonb) IS
    'v5.4.2-15. rule_tables.compare_function of deposit_tariffs: given the new tariff row and the law rows in force over its dates that bind the utility, the reasons the tariff is looser than the law of its category''s class, or cannot be shown to be no looser: no law known for the class; months of billing above the law''s cap (a fraction of annual billing converted to months; a lesser-of the least of the parts that convert, a greater-of the greatest, only when all convert); months of the highest bill or a minimum amount where a cap in average months exists; an amount where the law has not ruled on the cap; a trigger the law also names that fires sooner (a lower ratio, a lower or longer-window count, without the law''s consecutive or disputed-bill protection) or gives fewer days to pay, and one whose condition cannot be compared. Not compared: a flat amount against a fixed-dollar cap (each deposit''s recorded cap holds it), waivers, instalments. The law''s guards other than days to pay (service age, a recent move, notice, a cure) are not compared but required to be carried identically — a tariff trigger that omits one is refused. A trigger or waiver ground the law has no word on is the utility''s own; a delegation compares nothing about content. A LATER change in the law that makes a tariff looser is a core audit finding, never a refusal of the law.';

CREATE TABLE IF NOT EXISTS public.deposit_tariffs (
    id               uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id        uuid NOT NULL,
    state_code       text NOT NULL,
    service_type     text NOT NULL,
    system_kind      text NOT NULL,
    tariff_category  text NOT NULL,
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
    CONSTRAINT deposit_tariffs_pkey PRIMARY KEY (id),
    CONSTRAINT deposit_tariffs_category_fkey FOREIGN KEY (tenant_id, state_code, service_type, tariff_category)
        REFERENCES public.deposit_utility_categories(tenant_id, state_code, service_type, category_code)
);
DO $register$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.rule_tables WHERE table_name = 'public.deposit_tariffs'::regclass) THEN
        PERFORM public.rule_table_register('public.deposit_tariffs', 'tariff', 'deposit_tariff', ARRAY['tariff_category'], ARRAY[]::text[],
                                           'public.deposit_tariff_close_floor(uuid)', 'public.deposit_tariff_insert_check(jsonb)',
                                           'public.deposit_rules', 'public.deposit_tariff_compare(jsonb,jsonb)');
    END IF;
END
$register$;
REVOKE ALL ON FUNCTION public.deposit_tariff_close_floor(uuid), public.deposit_tariff_insert_check(jsonb), public.deposit_tariff_compare(jsonb, jsonb)
    FROM PUBLIC, tally_core;
GRANT EXECUTE ON FUNCTION public.deposit_tariff_close_floor(uuid), public.deposit_tariff_insert_check(jsonb), public.deposit_tariff_compare(jsonb, jsonb) TO tally_app;
COMMENT ON TABLE public.deposit_tariffs IS
    'v5.4.2-15 (Ryan, decision 2). The utility''s own deposit record for one of its categories, per (tenant, state, service, system, category, dates): one row of the kind deposit_tariff, never edited — the one change is a stamped close above the close floor. The amount it asks (none, fixed, months of average or highest billing with a minimum, or case by case), its triggers, its waiver grounds in its own name, its instalments. Measured against deposit_rules when written: never looser than the law of the class its category maps to. Where the law delegates (a city-owned system) it is the policy; a deposit cites the row that applied.';



-- ----------------------------------------------------------------------------
-- 8. Interest rates (R-D1): the utility's own rate; the state's is a floor
-- ----------------------------------------------------------------------------
-- The utility answers to the commission for the interest it pays, so the rate
-- it applies is its own row, and every accrual cites that row. A utility in two
-- states keeps a rate per state and service, and a rate may be for one of its
-- own deposit categories (NULL = every category; Ryan, decision 1: the
-- customer type stays here, on the utility's rate, not on the published one).
-- A state-set rate is a FLOOR the utility's own may not go below (decision 4):
-- refused where the row is written, from the published value in force on the
-- row's own date; nothing is refused when a published value later rises — that
-- is a core audit finding, never a refusal of the law.
ALTER TABLE public.deposit_interest_rates
    ADD COLUMN IF NOT EXISTS state_code      text,
    ADD COLUMN IF NOT EXISTS service_type    text,
    ADD COLUMN IF NOT EXISTS tariff_category text;
-- The precondition proved the table empty.
ALTER TABLE public.deposit_interest_rates ALTER COLUMN state_code SET NOT NULL;
ALTER TABLE public.deposit_interest_rates ALTER COLUMN service_type SET NOT NULL;
ALTER TABLE public.deposit_interest_rates DROP CONSTRAINT IF EXISTS deposit_interest_rates_state_code_check;
ALTER TABLE public.deposit_interest_rates ADD CONSTRAINT deposit_interest_rates_state_code_check CHECK ((state_code ~ '^[A-Z]{2}$'::text));
ALTER TABLE public.deposit_interest_rates DROP CONSTRAINT IF EXISTS deposit_interest_rates_service_type_check;
ALTER TABLE public.deposit_interest_rates ADD CONSTRAINT deposit_interest_rates_service_type_check
    CHECK ((service_type = ANY (ARRAY['water'::text, 'sewer'::text, 'electric'::text, 'gas'::text, 'stormwater'::text, 'trash'::text, 'reclaimed_water'::text])));
ALTER TABLE public.deposit_interest_rates DROP CONSTRAINT IF EXISTS deposit_interest_rates_tenant_effective_key;
ALTER TABLE public.deposit_interest_rates DROP CONSTRAINT IF EXISTS deposit_interest_rates_key;
ALTER TABLE public.deposit_interest_rates ADD CONSTRAINT deposit_interest_rates_key
    UNIQUE NULLS NOT DISTINCT (tenant_id, state_code, service_type, tariff_category, effective_date);
ALTER TABLE public.deposit_interest_rates DROP CONSTRAINT IF EXISTS deposit_interest_rates_category_fkey;
ALTER TABLE public.deposit_interest_rates ADD CONSTRAINT deposit_interest_rates_category_fkey
    FOREIGN KEY (tenant_id, state_code, service_type, tariff_category)
    REFERENCES public.deposit_utility_categories(tenant_id, state_code, service_type, category_code);
-- Accruals cite a rate row with a composite key (section 11).
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_constraint WHERE conname = 'deposit_interest_rates_id_tenant_id_key'
                    AND conrelid = 'public.deposit_interest_rates'::regclass) THEN
        ALTER TABLE public.deposit_interest_rates ADD CONSTRAINT deposit_interest_rates_id_tenant_id_key UNIQUE (id, tenant_id);
    END IF;
END;
$$;

-- The published value a rate name stands for on a date, in exactly the scope
-- its parameter is published in; refuses when none is recorded (unknown law is
-- not permission, and never falls back).
CREATE OR REPLACE FUNCTION public.deposit_published_rate(p_name text, p_state_code text, p_service_type text, p_on date) RETURNS numeric
    LANGUAGE plpgsql STABLE
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_p public.rule_parameters%ROWTYPE;
    v   public.rule_parameter_values%ROWTYPE;
BEGIN
    SELECT * INTO v_p FROM public.rule_parameters WHERE parameter_name = p_name;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING MESSAGE = format('%s is not a published parameter (v5.4.2-15)', p_name), ERRCODE = 'foreign_key_violation';
    END IF;
    SELECT * INTO v FROM public.rule_parameter_values x
     WHERE x.parameter_name = p_name
       AND x.state_code IS NOT DISTINCT FROM (CASE WHEN 'state_code' = ANY (v_p.scoped_by) THEN p_state_code END)
       AND x.service_type IS NOT DISTINCT FROM (CASE WHEN 'service_type' = ANY (v_p.scoped_by) THEN p_service_type END)
       AND daterange(x.effective_from, x.effective_to, '[)') @> p_on;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING
            MESSAGE = format('there is no published value of %s in force for %s %s on %s, so the floor it sets cannot be known — unknown law is not permission (v5.4.2-15)', p_name, p_state_code, p_service_type, p_on),
            ERRCODE = 'check_violation';
    END IF;
    RETURN v.value;
END;
$$;
COMMENT ON FUNCTION public.deposit_published_rate(text, text, text, date) IS
    'v5.4.2-15. The value of a published parameter in force on a date, in the scope the parameter is published in (state, or state and service, or national); refuses (check_violation, "no published value") when none is recorded.';

-- The highest floor the law sets for a utility's rate in a state and service,
-- on a date, for the classes the rate reaches: the rate's own category's class,
-- or — for a rate for every category — every class of the state and service (so it is refused while any class has no law row in force
-- for the utility's owner type, though the utility serves no such customer: the floor of a class the law is silent on is not known). The floor
-- of a law row is its rate when the rate is a minimum: a fixed rate, or the
-- highest of the published values it names (the main one and any by_hold).
-- A rate the law names only as a reference, a law that leaves the rate to the
-- utility, and a city the law does not bind set no floor. NULL: no floor.
CREATE OR REPLACE FUNCTION public.deposit_rate_floor(p_tenant_id uuid, p_state_code text, p_service_type text, p_category text, p_on date) RETURNS numeric
    LANGUAGE plpgsql STABLE
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_classes text[];
    v_floor   numeric;
    v_profile public.utility_service_profiles%ROWTYPE;
    v_seen    boolean := false;
    v_missing text;
    v_row     record;
    v_name    text;
    v_val     numeric;
BEGIN
    IF p_category IS NOT NULL THEN
        SELECT array_agg(c.law_class) INTO v_classes FROM public.deposit_utility_categories c
         WHERE c.tenant_id = p_tenant_id AND c.state_code = p_state_code AND c.service_type = p_service_type AND c.category_code = p_category;
    ELSE
        -- A rate for every category serves any category the utility defines later, so it clears every class of the state
        -- and service, not only those its categories map to today — and each of those classes needs a law row in force
        -- (a class with none leaves the floor unknown; a class the law delegates, or names only as a reference, sets none).
        SELECT array_agg(c.class_code) INTO v_classes FROM public.deposit_customer_classes c
         WHERE c.state_code = p_state_code AND c.service_type = p_service_type;
    END IF;
    FOR v_profile IN SELECT * FROM public.utility_service_profiles u
                      WHERE u.tenant_id = p_tenant_id AND u.service_type = p_service_type AND u.state_code = p_state_code
                        AND u.voided_at IS NULL AND daterange(u.effective_from, u.effective_to, '[)') @> p_on LOOP
        v_seen := true;
        -- Every class the rate reaches needs a law row in force (a law, a delegation or a reference rate): a class with none leaves
        -- the floor unknown, and unknown law is not permission — for a rate for one category, and for one for every category.
        SELECT string_agg(c, ', ' ORDER BY c) INTO v_missing FROM unnest(coalesce(v_classes, '{}')) c
         WHERE NOT EXISTS (
            SELECT 1 FROM public.deposit_rules r
             WHERE r.state_code = p_state_code AND r.service_type = p_service_type AND r.customer_class = c
               AND r.owner_span @> public.rule_applicability_ordinal('owner_type', v_profile.owner_type)
               AND r.system_span @> public.rule_applicability_ordinal('system_kind', v_profile.system_kind)
               AND r.jurisdiction_span @> (CASE WHEN v_profile.commission_jurisdiction THEN 1 ELSE 0 END)
               AND daterange(r.effective_from, r.effective_to, '[)') @> p_on);
        IF v_missing IS NOT NULL THEN
            RAISE EXCEPTION USING
                MESSAGE = format('no law is known for the class(es) %s of %s %s on %s, so the floor on this rate cannot be known — unknown law is not permission (v5.4.2-15)', v_missing, p_state_code, p_service_type, p_on),
                ERRCODE = 'check_violation';
        END IF;
        FOR v_row IN SELECT r.terms FROM public.deposit_rules r
                      WHERE r.state_code = p_state_code AND r.service_type = p_service_type AND r.customer_class = ANY (coalesce(v_classes, '{}'))
                        AND r.owner_span @> public.rule_applicability_ordinal('owner_type', v_profile.owner_type)
                        AND r.system_span @> public.rule_applicability_ordinal('system_kind', v_profile.system_kind)
                        AND r.jurisdiction_span @> (CASE WHEN v_profile.commission_jurisdiction THEN 1 ELSE 0 END)
                        AND daterange(r.effective_from, r.effective_to, '[)') @> p_on
                        AND r.terms ->> 'governs' = 'law' AND r.terms #>> '{interest,strategy}' = 'bearing'
                        AND r.terms #>> '{interest,rate,binding}' = 'minimum' LOOP
            IF v_row.terms #>> '{interest,rate,kind}' = 'fixed' THEN
                v_val := (v_row.terms #>> '{interest,rate,rate}')::numeric;
                v_floor := greatest(v_floor, v_val);
            ELSIF v_row.terms #>> '{interest,rate,kind}' = 'published' THEN
                FOR v_name IN SELECT v_row.terms #>> '{interest,rate,name}'
                              UNION SELECT h ->> 'name' FROM jsonb_array_elements(v_row.terms #> '{interest,rate,by_hold}') h LOOP
                    v_val := public.deposit_published_rate(v_name, p_state_code, p_service_type, p_on);
                    v_floor := greatest(v_floor, v_val);
                END LOOP;
            END IF;
        END LOOP;
    END LOOP;
    IF NOT v_seen THEN
        RAISE EXCEPTION USING
            MESSAGE = format('the utility has no service profile for %s %s on %s, so which law binds its rate cannot be known (v5.4.2-15)', p_state_code, p_service_type, p_on),
            ERRCODE = 'check_violation';
    END IF;
    RETURN v_floor;
END;
$$;
COMMENT ON FUNCTION public.deposit_rate_floor(uuid, text, text, text, date) IS
    'v5.4.2-15 (Ryan, decision 4). The floor the law sets for a utility''s own interest rate on a date: the highest binding minimum among the law rows (of the classes the rate reaches) that bind the utility''s owner type, system kind and jurisdiction status — a fixed rate, or the highest published value the rate names, read as of the date. NULL when nothing binds (a reference rate, a delegation). Refuses when a mapped class has no law row in force. Refuses when a published value the floor needs is not recorded, or the utility has no profile.';

CREATE OR REPLACE FUNCTION public.deposit_rate_lock_key(p_tenant_id uuid, p_state_code text, p_service_type text) RETURNS bigint
    LANGUAGE sql IMMUTABLE
    SET search_path = public, pg_temp
    AS $$
    SELECT hashtextextended('deposit_interest_rates/' || p_tenant_id::text || '/' || p_state_code || '/' || p_service_type, 0)
$$;
COMMENT ON FUNCTION public.deposit_rate_lock_key(uuid, text, text) IS
    'v5.4.2-15. The advisory-lock key a rate insert (exclusive) and an accrual (shared) take for a tenant''s rates in one state and service.';

CREATE OR REPLACE FUNCTION public.enforce_deposit_interest_rate() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_settled date;
    v_floor   numeric;
BEGIN
    IF current_setting('transaction_isolation') <> 'read committed' THEN
        RAISE EXCEPTION USING
            MESSAGE = format('deposit interest rate rejected: a rate is recorded only under READ COMMITTED — under %s the settled-accrual check could miss an accrual committed while it waited (v5.4.2-15)', current_setting('transaction_isolation')),
            ERRCODE = 'serialization_failure';
    END IF;
    PERFORM pg_advisory_xact_lock(public.deposit_rate_lock_key(NEW.tenant_id, NEW.state_code, NEW.service_type));
    PERFORM public.assert_same_tenant_user(NEW.created_by, NEW.tenant_id, 'created_by');
    NEW.created_at := now();
    IF NEW.tariff_category IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM public.deposit_utility_categories c
         WHERE c.tenant_id = NEW.tenant_id AND c.state_code = NEW.state_code AND c.service_type = NEW.service_type AND c.category_code = NEW.tariff_category) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('deposit interest rate rejected: %s is not one of this utility''s deposit categories for %s %s — define it first (v5.4.2-15)', NEW.tariff_category, NEW.state_code, NEW.service_type),
            ERRCODE = 'check_violation';
    END IF;
    -- A settled accrual is never re-rated (CI-125 / CI-130): refused on or before the latest period end of any accrual
    -- citing a rate row of the same tenant, state and service whose category scope overlaps (NULL = every category).
    SELECT max(e.period_end) INTO v_settled
      FROM public.deposit_events e
      JOIN public.deposit_interest_rates r ON r.id = e.rate_id
     WHERE e.event_type = 'interest_accrued' AND r.tenant_id = NEW.tenant_id
       AND r.state_code = NEW.state_code AND r.service_type = NEW.service_type
       AND (r.tariff_category IS NULL OR NEW.tariff_category IS NULL OR r.tariff_category = NEW.tariff_category);
    IF v_settled IS NOT NULL AND NEW.effective_date <= v_settled THEN
        RAISE EXCEPTION USING
            MESSAGE = format('deposit interest rate %s %s%s effective %s rejected: interest has already been accrued through %s at the rates it cites; a settled accrual is never re-rated (CI-125 / CI-130) — a correction is a new accrual period at the new rate from %s', NEW.state_code, NEW.service_type, coalesce(' ' || NEW.tariff_category, ''), NEW.effective_date, v_settled, v_settled + 1),
            ERRCODE = 'check_violation';
    END IF;
    -- The floor the law sets (decision 4).
    v_floor := public.deposit_rate_floor(NEW.tenant_id, NEW.state_code, NEW.service_type, NEW.tariff_category, NEW.effective_date);
    IF v_floor IS NOT NULL AND NEW.annual_rate < v_floor THEN
        RAISE EXCEPTION USING
            MESSAGE = format('deposit interest rate %s %s%s effective %s rejected: %s is below the floor the law sets for it (%s, a minimum, as of that date) (v5.4.2-15)', NEW.state_code, NEW.service_type, coalesce(' ' || NEW.tariff_category, ''), NEW.effective_date, NEW.annual_rate, v_floor),
            ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$;
COMMENT ON FUNCTION public.enforce_deposit_interest_rate() IS
    'v5.4.2-06, re-issued by v5.4.2-15. BEFORE INSERT on deposit_interest_rates: READ COMMITTED only; takes the exclusive advisory lock for (tenant, state, service) that accruals take shared; created_by of the tenant; created_at stamped; a category is one of the utility''s own; refused on or before the latest period end of any accrual citing a rate row of the same tenant, state and service whose category scope overlaps; refused below the floor the law sets (deposit_rate_floor: the published value in force on the row''s own date, a fixed rate, the highest of a by-hold list; none for a reference rate or a city the law does not bind; none known refuses).';

-- The utility's rate row in force for a category on a date: the category's own,
-- else the one for every category — never the latest of the wrong scope.
CREATE OR REPLACE FUNCTION public.deposit_interest_rate_row_as_of(p_tenant_id uuid, p_state_code text, p_service_type text, p_category text, p_on date) RETURNS uuid
    LANGUAGE plpgsql STABLE
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_id uuid;
BEGIN
    IF p_category IS NOT NULL THEN
        SELECT r.id INTO v_id FROM public.deposit_interest_rates r
         WHERE r.tenant_id = p_tenant_id AND r.state_code = p_state_code AND r.service_type = p_service_type
           AND r.tariff_category = p_category AND r.effective_date <= p_on
         ORDER BY r.effective_date DESC LIMIT 1;
    END IF;
    IF v_id IS NULL THEN
        SELECT r.id INTO v_id FROM public.deposit_interest_rates r
         WHERE r.tenant_id = p_tenant_id AND r.state_code = p_state_code AND r.service_type = p_service_type
           AND r.tariff_category IS NULL AND r.effective_date <= p_on
         ORDER BY r.effective_date DESC LIMIT 1;
    END IF;
    IF v_id IS NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('no deposit interest rate is recorded for %s %s%s on %s — the utility records the rate it applies (v5.4.2-15)', p_state_code, p_service_type, coalesce(' ' || p_category, ''), p_on),
            ERRCODE = 'no_data_found';
    END IF;
    RETURN v_id;
END;
$$;
COMMENT ON FUNCTION public.deposit_interest_rate_row_as_of(uuid, text, text, text, date) IS
    'v5.4.2-15. The id of the utility''s own interest rate row in force for a category on a date: the category''s own row if it has one by then, else the row for every category; refuses (no_data_found) when neither exists. Invoker rights: a utility sees its own rows. Which row applies to a period is the core''s; this is the lookup it uses.';

COMMENT ON TABLE public.deposit_interest_rates IS
    'CI-125 / CI-130 (v5.4.2-06; v5.4.2-15, R-D1). The deposit interest rate THIS UTILITY applies, per state and service type and optionally per one of its own deposit categories (NULL = every category; Ryan, decision 1), effective-dated (annual, as a fraction — 0.0287 = 2.87%). The utility is the regulated party and answers for it; every accrual cites the row it used (deposit_events.rate_id). A rate below a floor the law sets (the published value, or a fixed rate, in force on the row''s date) is refused where it is written. A new rate is a new row; rows are never edited or deleted; one backdated under a settled accrual is refused.';



-- ----------------------------------------------------------------------------
-- 9. The citing side: which law row may a record cite
-- ----------------------------------------------------------------------------
-- A record covering p_from..p_to (an accrual's period, a return's day) cites a
-- law row of the deposit's own key — the row the deposit was decided under, or
-- a row of the same state, service, class and basis, binding the same owners,
-- systems and jurisdiction, in force over the whole span (a later law that
-- reaches deposits already held; Ryan, B1, 2026-10-02). A carried legacy
-- deposit cites none.
CREATE OR REPLACE FUNCTION public.deposit_rule_citable(p_deposit_id uuid, p_rule_id uuid, p_from date, p_to date) RETURNS boolean
    LANGUAGE plpgsql STABLE
    SET search_path = public, pg_temp
    AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1
          FROM public.deposits d
          JOIN public.deposit_rules own ON own.id = d.rule_id
          JOIN public.deposit_rules r ON r.id = p_rule_id
         WHERE d.id = p_deposit_id
           AND (r.id = own.id
                OR (r.state_code = own.state_code AND r.service_type = own.service_type AND r.customer_class = own.customer_class AND r.basis = own.basis
                    AND r.owner_span = own.owner_span AND r.system_span = own.system_span AND r.jurisdiction_span = own.jurisdiction_span
                    AND daterange(r.effective_from, r.effective_to, '[)') @> daterange(p_from, p_to, '[]'))));
END;
$$;
COMMENT ON FUNCTION public.deposit_rule_citable(uuid, uuid, date, date) IS
    'v5.4.2-15 (Ryan, B1). Whether a later record of a deposit covering p_from..p_to may cite p_rule_id: the deposit''s own law row (the law it was decided under, even after a close: it stays the law that governed), or a row of the same state, service, class and basis binding the same owners, systems and jurisdiction in force over the whole span. A carried legacy deposit cites none.';

-- A record's citation of a law row for a span: the row is cited by the deposit's
-- key (citable), and locked shared so a close waits: the deposit's own row for
-- its lock only (it governs even after its close); a successor also in force at
-- both ends of the span.
CREATE OR REPLACE FUNCTION public.deposit_cite_rule(p_what text, p_deposit_id uuid, p_rule_id uuid, p_from date, p_to date) RETURNS void
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_own uuid;
BEGIN
    SELECT d.rule_id INTO v_own FROM public.deposits d WHERE d.id = p_deposit_id;
    IF NOT public.deposit_rule_citable(p_deposit_id, p_rule_id, p_from, p_to) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('%s: law row %s is neither the rule the deposit was decided under (%s) nor a rule of its key in force over %s..%s (v5.4.2-15)',
                             p_what, p_rule_id, coalesce(v_own::text, 'none — a carried legacy deposit'), p_from, p_to),
            ERRCODE = 'check_violation';
    END IF;
    IF p_rule_id = v_own THEN
        PERFORM pg_advisory_xact_lock_shared(public.rule_row_lock_key('public.deposit_rules'::regclass, p_rule_id));
    ELSE
        PERFORM public.rule_row_cite('public.deposit_rules'::regclass, p_rule_id, p_from);
        PERFORM public.rule_row_cite('public.deposit_rules'::regclass, p_rule_id, p_to);
    END IF;
END;
$$;
COMMENT ON FUNCTION public.deposit_cite_rule(text, uuid, uuid, date, date) IS
    'v5.4.2-15. Used by the guards on a deposit''s events and return-due rows: the cited law row is citable by the deposit (deposit_rule_citable), and locked shared until commit so a close of it waits (the template''s handshake): the deposit''s own row only locked, a successor also in force at both ends of the span.';


-- ----------------------------------------------------------------------------
-- 10. deposits — what it was decided under; the Texas branches go
-- ----------------------------------------------------------------------------
-- A deposit records the jurisdiction (from the PREMISE, never the utility), the
-- system, the law class and the utility's own category, the LAW ROW it was
-- decided under (a city's delegation row, for a city), the utility's TARIFF
-- row when one applied, the cap that applied — the statute's or the utility's
-- (cap_source) — and the part of the document that governed it, the trigger it
-- was decided on (the document's, or the tariff's) and the measure observed,
-- what else was held under a combined cap, and the core version.
-- -06's legacy_unknown rows carry none of them.
ALTER TABLE public.deposits
    ADD COLUMN IF NOT EXISTS state_code          text,
    ADD COLUMN IF NOT EXISTS service_type        text,
    ADD COLUMN IF NOT EXISTS system_kind         text,
    ADD COLUMN IF NOT EXISTS customer_class      text,
    ADD COLUMN IF NOT EXISTS tariff_category     text,
    ADD COLUMN IF NOT EXISTS rule_id             uuid,
    ADD COLUMN IF NOT EXISTS tariff_id           uuid,
    ADD COLUMN IF NOT EXISTS decided_by          text,
    ADD COLUMN IF NOT EXISTS cap_basis_amount    numeric(12,2),
    ADD COLUMN IF NOT EXISTS cap_source          text,
    ADD COLUMN IF NOT EXISTS cap_component       text,
    ADD COLUMN IF NOT EXISTS cap_other_held      numeric(12,2),
    ADD COLUMN IF NOT EXISTS trigger_source      text,
    ADD COLUMN IF NOT EXISTS trigger_component   text,
    ADD COLUMN IF NOT EXISTS trigger_observed    numeric(12,3),
    ADD COLUMN IF NOT EXISTS received_at_posting numeric(12,2),
    ADD COLUMN IF NOT EXISTS recorded_txid       bigint;

ALTER TABLE public.deposits DROP CONSTRAINT IF EXISTS deposits_class_fkey;
ALTER TABLE public.deposits ADD CONSTRAINT deposits_class_fkey
    FOREIGN KEY (state_code, service_type, customer_class) REFERENCES public.deposit_customer_classes(state_code, service_type, class_code);
ALTER TABLE public.deposits DROP CONSTRAINT IF EXISTS deposits_category_fkey;
ALTER TABLE public.deposits ADD CONSTRAINT deposits_category_fkey
    FOREIGN KEY (tenant_id, state_code, service_type, tariff_category)
    REFERENCES public.deposit_utility_categories(tenant_id, state_code, service_type, category_code);
ALTER TABLE public.deposits DROP CONSTRAINT IF EXISTS deposits_system_kind_fkey;
ALTER TABLE public.deposits ADD CONSTRAINT deposits_system_kind_fkey FOREIGN KEY (system_kind) REFERENCES public.utility_system_kinds(system_kind);
ALTER TABLE public.deposits DROP CONSTRAINT IF EXISTS deposits_rule_fkey;
ALTER TABLE public.deposits ADD CONSTRAINT deposits_rule_fkey FOREIGN KEY (rule_id) REFERENCES public.deposit_rules(id);
ALTER TABLE public.deposits DROP CONSTRAINT IF EXISTS deposits_tariff_fkey;
ALTER TABLE public.deposits ADD CONSTRAINT deposits_tariff_fkey FOREIGN KEY (tariff_id) REFERENCES public.deposit_tariffs(id);
-- The jurisdiction, system, class, law row and core version come together or not at all
-- (not at all = a carried legacy row; a new deposit must cite a law row, below).
ALTER TABLE public.deposits DROP CONSTRAINT IF EXISTS deposits_decision_check;
ALTER TABLE public.deposits ADD CONSTRAINT deposits_decision_check
    CHECK ((((rule_id IS NULL) AND (state_code IS NULL) AND (service_type IS NULL) AND (system_kind IS NULL) AND (customer_class IS NULL) AND (decided_by IS NULL))
         OR ((rule_id IS NOT NULL) AND (state_code IS NOT NULL) AND (service_type IS NOT NULL) AND (system_kind IS NOT NULL) AND (customer_class IS NOT NULL)
             AND (decided_by IS NOT NULL) AND (decided_by ~ '[[:alnum:]]'::text))));
ALTER TABLE public.deposits DROP CONSTRAINT IF EXISTS deposits_tariff_category_check;
ALTER TABLE public.deposits ADD CONSTRAINT deposits_tariff_category_check CHECK (((tariff_id IS NULL) OR (tariff_category IS NOT NULL)));
ALTER TABLE public.deposits DROP CONSTRAINT IF EXISTS deposits_cap_basis_amount_check;
ALTER TABLE public.deposits ADD CONSTRAINT deposits_cap_basis_amount_check CHECK (((cap_basis_amount IS NULL) OR (cap_basis_amount > (0)::numeric)));
-- A cap says where it came from: the statute (the cited document's cap, and the part that governed it) or the
-- utility's tariff (the cited tariff row).
ALTER TABLE public.deposits DROP CONSTRAINT IF EXISTS deposits_cap_source_check;
ALTER TABLE public.deposits ADD CONSTRAINT deposits_cap_source_check
    CHECK ((((cap_amount IS NULL) AND (cap_source IS NULL) AND (cap_component IS NULL) AND (cap_basis_amount IS NULL) AND (cap_other_held IS NULL))
         OR ((cap_amount IS NOT NULL) AND (cap_source IS NOT NULL) AND (((cap_source = 'statute'::text) AND (cap_component IS NOT NULL)) OR (cap_source = 'tariff'::text)))));
ALTER TABLE public.deposits DROP CONSTRAINT IF EXISTS deposits_cap_other_held_check;
ALTER TABLE public.deposits ADD CONSTRAINT deposits_cap_other_held_check
    CHECK (((cap_other_held IS NULL) OR ((cap_other_held >= (0)::numeric) AND (cap_other_held < cap_amount))));
ALTER TABLE public.deposits DROP CONSTRAINT IF EXISTS deposits_cap_check;
ALTER TABLE public.deposits ADD CONSTRAINT deposits_cap_check
    CHECK (((cap_amount IS NULL) OR ((cap_amount > (0)::numeric) AND (principal <= (cap_amount - coalesce(cap_other_held, (0)::numeric))))));
ALTER TABLE public.deposits DROP CONSTRAINT IF EXISTS deposits_cap_binding_check;
ALTER TABLE public.deposits ADD CONSTRAINT deposits_cap_binding_check
    CHECK (((NOT cap_binding) OR ((cap_amount IS NOT NULL) AND (principal = (cap_amount - coalesce(cap_other_held, (0)::numeric))))));
-- The trigger an additional deposit was decided on: the document's own, or the utility's tariff's, by component id,
-- with the measure the core observed.
ALTER TABLE public.deposits DROP CONSTRAINT IF EXISTS deposits_trigger_source_check;
ALTER TABLE public.deposits ADD CONSTRAINT deposits_trigger_source_check
    CHECK ((((trigger_source IS NULL) AND (trigger_component IS NULL) AND (trigger_observed IS NULL))
         OR ((trigger_source = ANY (ARRAY['statute'::text, 'tariff'::text])) AND (trigger_component IS NOT NULL) AND (trigger_basis IS NOT NULL)
             AND (trigger_observed IS NOT NULL) AND (trigger_observed >= (0)::numeric))));
-- Taken in instalments: principal is the deposit required; received_at_posting is what was paid at posting, less than
-- it; the rest is the schedule (deposit_instalments), received by instalment_received events.
ALTER TABLE public.deposits DROP CONSTRAINT IF EXISTS deposits_received_at_posting_check;
ALTER TABLE public.deposits ADD CONSTRAINT deposits_received_at_posting_check
    CHECK (((received_at_posting IS NULL) OR ((received_at_posting > (0)::numeric) AND (received_at_posting < principal))));
-- -06's CHECKs that named a basis go: whether a basis names a trigger, and which bases are carried history, are
-- vocabulary attributes, read by the guard below.
ALTER TABLE public.deposits DROP CONSTRAINT IF EXISTS deposits_trigger_basis_required_check;
ALTER TABLE public.deposits DROP CONSTRAINT IF EXISTS deposits_legacy_interest_check;
ALTER TABLE public.deposits DROP CONSTRAINT IF EXISTS deposits_basis_check;
ALTER TABLE public.deposits DROP CONSTRAINT IF EXISTS deposits_basis_fkey;
ALTER TABLE public.deposits ADD CONSTRAINT deposits_basis_fkey FOREIGN KEY (basis) REFERENCES public.deposit_bases(basis_code);
ALTER TABLE public.deposits DROP CONSTRAINT IF EXISTS deposits_trigger_basis_check;
ALTER TABLE public.deposits DROP CONSTRAINT IF EXISTS deposits_trigger_basis_fkey;
ALTER TABLE public.deposits ADD CONSTRAINT deposits_trigger_basis_fkey FOREIGN KEY (trigger_basis) REFERENCES public.deposit_triggers(trigger_code);
CREATE INDEX IF NOT EXISTS idx_deposits_rule ON public.deposits USING btree (rule_id);
CREATE INDEX IF NOT EXISTS idx_deposits_tariff ON public.deposits USING btree (tariff_id);

-- The figure a cap part gives from the basis figure the deposit records: a fraction of annual billing (the basis is annual billing), months of
-- billing (monthly billing), a fixed amount (none), the N highest bills (their total), a seasonal average (the average, times its multiple).
CREATE OR REPLACE FUNCTION public.deposit_cap_part_figure(p_part jsonb, p_basis numeric) RETURNS numeric
    LANGUAGE sql IMMUTABLE
    SET search_path = public, pg_temp
    AS $$
    SELECT CASE p_part ->> 'kind'
               WHEN 'fraction_of_annual_billing' THEN p_basis / (p_part ->> 'divisor')::numeric
               WHEN 'months_of_billing' THEN p_basis * (p_part ->> 'months')::numeric
               WHEN 'fixed_amount' THEN (p_part ->> 'amount')::numeric
               WHEN 'highest_bills' THEN p_basis
               WHEN 'seasonal_average' THEN p_basis * (p_part ->> 'multiple')::numeric
           END
$$;
COMMENT ON FUNCTION public.deposit_cap_part_figure(jsonb, numeric) IS
    'v5.4.2-15. The figure a cap part of a deposit document gives from the one basis figure a deposit records (cap_basis_amount): annual billing for a fraction of annual billing, monthly billing for months of billing, nothing for a fixed amount, the total of the N highest bills for highest_bills, the seasonal average for seasonal_average (times its multiple). Arithmetic on recorded figures; the core computes the basis.';

CREATE OR REPLACE FUNCTION public.enforce_deposit() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_cust   public.customers%ROWTYPE;
    v_basis  public.deposit_bases%ROWTYPE;
    v_rule   public.deposit_rules%ROWTYPE;
    v_cat    public.deposit_utility_categories%ROWTYPE;
    v_tariff public.deposit_tariffs%ROWTYPE;
    v_expect uuid;
    v_part   jsonb;
    v_trig   jsonb;
    v_src    jsonb;
    v_doc    jsonb;
    v_cond   jsonb;
    v_met    boolean;
    v_stat   numeric;
    v_least  numeric;
    v_tamt   numeric;
BEGIN
    IF TG_OP = 'INSERT' THEN
        NEW.created_at    := now();
        NEW.recorded_txid := txid_current();
        SELECT * INTO v_cust FROM public.customers c WHERE c.id = NEW.customer_id;
        IF NOT FOUND THEN
            RAISE EXCEPTION USING MESSAGE = format('deposit rejected: customer %s not found (or not visible)', NEW.customer_id), ERRCODE = 'foreign_key_violation';
        END IF;
        SELECT * INTO v_basis FROM public.deposit_bases b WHERE b.basis_code = NEW.basis;
        IF v_basis.insertable IS NOT TRUE THEN
            RAISE EXCEPTION USING MESSAGE = format('deposit rejected: basis %s exists only for carried history — record the basis that governs this deposit', NEW.basis), ERRCODE = 'check_violation';
        END IF;
        -- A basis that requires a trigger names one; no other basis does.
        IF v_basis.requires_trigger <> (NEW.trigger_basis IS NOT NULL) THEN
            RAISE EXCEPTION USING
                MESSAGE = format('deposit rejected: basis %s %s (deposit_bases.requires_trigger) — v5.4.2-15', NEW.basis, CASE WHEN v_basis.requires_trigger THEN 'names the event that gave rise to it (trigger_basis)' ELSE 'names no trigger' END),
                ERRCODE = 'check_violation';
        END IF;
        IF NEW.legacy_interest_earned IS NOT NULL THEN
            RAISE EXCEPTION USING MESSAGE = 'deposit rejected: legacy_interest_earned is carried history (v5.4.2-06); a new deposit''s interest is its accrual events', ERRCODE = 'check_violation';
        END IF;
        IF NEW.status <> 'held' OR NEW.refunded_on IS NOT NULL OR NEW.released_on IS NOT NULL THEN
            RAISE EXCEPTION USING MESSAGE = 'deposit rejected: a deposit is born held; status / refunded_on / released_on are projected from deposit_events', ERRCODE = 'check_violation';
        END IF;
        PERFORM public.assert_same_tenant_user(NEW.created_by, NEW.tenant_id, 'created_by');
        IF NEW.source_payment_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.payments p WHERE p.id = NEW.source_payment_id AND p.customer_id = NEW.customer_id AND coalesce(p.is_deposit, false)) THEN
            RAISE EXCEPTION USING MESSAGE = 'deposit rejected: source_payment_id must be a payment of the same customer flagged is_deposit', ERRCODE = 'check_violation';
        END IF;
        -- The law row the core decided it under.
        IF NEW.rule_id IS NULL THEN
            RAISE EXCEPTION USING
                MESSAGE = 'deposit rejected: a deposit records the deposit_rules row it was decided under (rule_id), with its state, service type, system kind, customer class and the core version (decided_by) — v5.4.2-15',
                ERRCODE = 'check_violation';
        END IF;
        SELECT * INTO v_rule FROM public.deposit_rules r WHERE r.id = NEW.rule_id;
        IF NOT FOUND THEN
            RAISE EXCEPTION USING MESSAGE = format('deposit rejected: the law row %s does not exist (deposit_rules) — v5.4.2-15', NEW.rule_id), ERRCODE = 'check_violation';
        END IF;
        -- The row the utility's profile, the premise's state and service, the class and the basis resolve to on the
        -- posting date, in force, locked shared against a close.
        PERFORM public.rule_law_row_cite('public.deposit_rules'::regclass, NEW.rule_id, NEW.tenant_id, NEW.service_type, NEW.system_kind, NEW.state_code,
                                         jsonb_build_object('customer_class', NEW.customer_class, 'basis', NEW.basis), NEW.posted_on);
        v_doc := v_rule.terms;
        -- The utility's own category: one it defined, that falls under this deposit's law class.
        IF NEW.tariff_category IS NOT NULL THEN
            SELECT * INTO v_cat FROM public.deposit_utility_categories c
             WHERE c.tenant_id = NEW.tenant_id AND c.state_code = NEW.state_code AND c.service_type = NEW.service_type AND c.category_code = NEW.tariff_category;
            IF NOT FOUND THEN
                RAISE EXCEPTION USING
                    MESSAGE = format('deposit rejected: the category %s is not one this utility defined for %s %s (deposit_utility_categories) — v5.4.2-15', NEW.tariff_category, NEW.state_code, NEW.service_type),
                    ERRCODE = 'check_violation';
            END IF;
            IF v_cat.law_class <> NEW.customer_class THEN
                RAISE EXCEPTION USING
                    MESSAGE = format('deposit rejected: the category %s maps to the law class %s, not %s (v5.4.2-15)', NEW.tariff_category, v_cat.law_class, NEW.customer_class),
                    ERRCODE = 'check_violation';
            END IF;
        END IF;
        -- The utility's tariff row, where one applied: the row in force for its category on the posting date. A tariff row in force
        -- for the deposit's category applies, so the deposit cites it (leaving it out would skip the utility's own stricter policy).
        -- Where the law delegates the matter, the tariff is the policy and the deposit cites it (no policy recorded is refused).
        IF NEW.tariff_id IS NULL AND NEW.tariff_category IS NOT NULL THEN
            v_expect := public.rule_tariff_row_as_of('public.deposit_tariffs'::regclass, NEW.tenant_id, NEW.service_type, NEW.system_kind, NEW.state_code,
                                                     jsonb_build_object('tariff_category', NEW.tariff_category), NEW.posted_on);
            IF v_expect IS NOT NULL THEN
                RAISE EXCEPTION USING
                    MESSAGE = format('deposit rejected: the tariff row %s is in force for category %s on %s; the deposit cites it (tariff_id) — v5.4.2-15', v_expect, NEW.tariff_category, NEW.posted_on),
                    ERRCODE = 'check_violation';
            END IF;
        END IF;
        IF NEW.tariff_id IS NOT NULL THEN
            SELECT * INTO v_tariff FROM public.deposit_tariffs t WHERE t.id = NEW.tariff_id;
            IF NOT FOUND THEN
                RAISE EXCEPTION USING
                    MESSAGE = format('deposit rejected: the tariff row %s does not exist or is not this utility''s (deposit_tariffs) — v5.4.2-15', NEW.tariff_id),
                    ERRCODE = 'check_violation';
            END IF;
            PERFORM public.rule_row_cite('public.deposit_tariffs'::regclass, NEW.tariff_id, NEW.posted_on);
            v_expect := public.rule_tariff_row_as_of('public.deposit_tariffs'::regclass, NEW.tenant_id, NEW.service_type, NEW.system_kind, NEW.state_code,
                                                     jsonb_build_object('tariff_category', NEW.tariff_category), NEW.posted_on);
            IF v_expect IS DISTINCT FROM NEW.tariff_id THEN
                RAISE EXCEPTION USING
                    MESSAGE = format('deposit rejected: the tariff row %s is not this utility''s tariff row for category %s on %s (that is %s) — v5.4.2-15', NEW.tariff_id, NEW.tariff_category, NEW.posted_on, coalesce(v_expect::text, 'none')),
                    ERRCODE = 'check_violation';
            END IF;
        ELSIF v_doc ->> 'governs' = 'delegated_to_utility' THEN
            RAISE EXCEPTION USING
                MESSAGE = format('deposit rejected: the law row %s leaves the matter to the utility, so the deposit cites the utility''s own tariff row (tariff_id, with its category) — no policy recorded is refused — v5.4.2-15', NEW.rule_id),
                ERRCODE = 'check_violation';
        END IF;
        -- The cap that applied. A cap said to come from the tariff cites the tariff row. Where the cited document caps the
        -- deposit, the statutory cap is ALWAYS recorded — the part that governed it, by id, and the figure it was computed from
        -- — and the cap that applied is no more than the statute's (a tariff's may be tighter): the record carries the law's
        -- figure whichever source set the cap.
        IF NEW.cap_source = 'tariff' AND NEW.tariff_id IS NULL THEN
            RAISE EXCEPTION USING
                MESSAGE = 'deposit rejected: a cap said to come from the tariff cites no tariff row (tariff_id) — v5.4.2-15', ERRCODE = 'check_violation';
        END IF;
        IF v_doc #>> '{cap,strategy}' = 'parts' THEN
            IF NEW.cap_amount IS NULL THEN
                RAISE EXCEPTION USING
                    MESSAGE = format('deposit rejected: law row %s caps the deposit; record the cap that applied — the statute''s or the utility''s tariff''s (cap_source) — v5.4.2-15', NEW.rule_id),
                    ERRCODE = 'check_violation';
            END IF;
            SELECT p INTO v_part FROM jsonb_array_elements(v_doc #> '{cap,parts}') p WHERE p ->> 'id' = NEW.cap_component;
            IF v_part IS NULL THEN
                RAISE EXCEPTION USING
                    MESSAGE = format('deposit rejected: the cited document sets a cap — law row %s has no cap part %L; record the id of the part that governed, whichever source set the cap (cap_component) — v5.4.2-15', NEW.rule_id, NEW.cap_component),
                    ERRCODE = 'check_violation';
            END IF;
            IF (NEW.cap_other_held IS NOT NULL) <> ((v_doc #>> '{cap,scope}') = 'combined') THEN
                RAISE EXCEPTION USING
                    MESSAGE = 'deposit rejected: a combined cap records what else the customer held (cap_other_held), and only a combined cap does (v5.4.2-15)',
                    ERRCODE = 'check_violation';
            END IF;
            IF (NEW.cap_basis_amount IS NULL) <> ((v_part ->> 'kind') = 'fixed_amount') THEN
                RAISE EXCEPTION USING
                    MESSAGE = 'deposit rejected: a cap records the figure it was computed from (cap_basis_amount), except a fixed amount, which has none (v5.4.2-15)',
                    ERRCODE = 'check_violation';
            END IF;
            v_stat := public.deposit_cap_part_figure(v_part, NEW.cap_basis_amount);
            -- Under a lesser-of cap the cap is no more than the least part that can be computed from the one basis figure recorded
            -- (a fixed amount, and the parts of the same kind as the one named): naming the larger part does not lift it.
            IF v_doc #>> '{cap,combinator}' = 'lesser_of' THEN
                SELECT min(public.deposit_cap_part_figure(p, NEW.cap_basis_amount)) INTO v_least
                  FROM jsonb_array_elements(v_doc #> '{cap,parts}') p
                 WHERE p ->> 'kind' = 'fixed_amount' OR p ->> 'kind' = v_part ->> 'kind';
                v_stat := least(v_stat, v_least);
            END IF;
            IF v_stat IS NOT NULL AND NEW.cap_amount > v_stat + 0.005 THEN
                RAISE EXCEPTION USING
                    MESSAGE = format('deposit rejected: the cap that applied (%s) is above the statutory cap of part %s (%s, from %s) — a tariff''s cap may be tighter, never looser (v5.4.2-15)',
                                     NEW.cap_amount, NEW.cap_component, trim_scale(round(v_stat, 4)), NEW.cap_basis_amount),
                    ERRCODE = 'check_violation';
            END IF;
        ELSIF NEW.cap_source = 'statute' THEN
            RAISE EXCEPTION USING
                MESSAGE = format('deposit rejected: a statutory cap is the cited document''s — law row %s sets none (v5.4.2-15)', NEW.rule_id), ERRCODE = 'check_violation';
        ELSIF NEW.cap_component IS NOT NULL THEN
            RAISE EXCEPTION USING
                MESSAGE = format('deposit rejected: law row %s sets no cap, so there is no cap part %L to name (v5.4.2-15)', NEW.rule_id, NEW.cap_component), ERRCODE = 'check_violation';
        END IF;
        -- The cited tariff's own figure holds whatever source set the cap that applied (not under a law cap in highest bills or a
        -- seasonal average: nothing converts). A fixed amount; or months of billing, from
        -- the figure recorded (the named part's, where the document caps; the monthly billing, where it sets no cap). A tariff that
        -- states no amount (none, case by case) holds nothing, and a minimum amount is the core's. Where the document sets no cap
        -- and the tariff states an amount, the cap that applied is recorded: the tariff is the policy.
        IF NEW.tariff_id IS NOT NULL THEN
            IF v_doc #>> '{cap,strategy}' IS DISTINCT FROM 'parts' THEN
                IF v_tariff.terms #>> '{amount,strategy}' IN ('fixed', 'months_of_billing') AND NEW.cap_amount IS NULL THEN
                    RAISE EXCEPTION USING
                        MESSAGE = 'deposit rejected: the cited tariff states an amount and the law sets no cap, so the cap that applied is recorded (cap_amount, cap_source tariff) — v5.4.2-15',
                        ERRCODE = 'check_violation';
                END IF;
                IF (NEW.cap_basis_amount IS NULL) <> (v_tariff.terms #>> '{amount,strategy}' IS DISTINCT FROM 'months_of_billing') THEN
                    RAISE EXCEPTION USING
                        MESSAGE = 'deposit rejected: with no cap in the document, a tariff cap records the monthly billing figure (cap_basis_amount) exactly when the tariff states its amount in months of billing (v5.4.2-15)',
                        ERRCODE = 'check_violation';
                END IF;
            END IF;
            v_tamt := CASE v_tariff.terms #>> '{amount,strategy}'
                          WHEN 'fixed' THEN (v_tariff.terms #>> '{amount,amount}')::numeric
                          WHEN 'months_of_billing' THEN
                              CASE WHEN v_doc #>> '{cap,strategy}' = 'parts' THEN
                                        CASE v_part ->> 'kind'
                                            WHEN 'fraction_of_annual_billing' THEN NEW.cap_basis_amount / 12 * (v_tariff.terms #>> '{amount,months}')::numeric
                                            WHEN 'months_of_billing' THEN NEW.cap_basis_amount * (v_tariff.terms #>> '{amount,months}')::numeric
                                        END
                                   ELSE NEW.cap_basis_amount * (v_tariff.terms #>> '{amount,months}')::numeric END
                      END;
            IF v_tamt IS NOT NULL AND NEW.cap_amount IS NOT NULL AND NEW.cap_amount > v_tamt + 0.005 THEN
                RAISE EXCEPTION USING
                    MESSAGE = format('deposit rejected: the cap that applied (%s) is above the cited tariff''s own amount (%s) — v5.4.2-15', NEW.cap_amount, trim_scale(round(v_tamt, 4))),
                    ERRCODE = 'check_violation';
            END IF;
        END IF;
        -- The trigger an additional deposit was decided on: a trigger of the cited document (or of the tariff row), for the
        -- trigger code the deposit names, whose condition the measure the core observed meets.
        IF NEW.trigger_basis IS NOT NULL THEN
            IF NEW.trigger_source IS NULL THEN
                RAISE EXCEPTION USING
                    MESSAGE = format('deposit rejected: an additional deposit records the trigger it was decided on — the document''s or the tariff''s (trigger_source, trigger_component) and the measure observed — v5.4.2-15'),
                    ERRCODE = 'check_violation';
            END IF;
            IF NEW.trigger_source = 'statute' THEN
                v_src := v_doc;
            ELSE
                IF NEW.tariff_id IS NULL THEN
                    RAISE EXCEPTION USING MESSAGE = 'deposit rejected: a trigger said to come from the tariff cites no tariff row (tariff_id) — v5.4.2-15', ERRCODE = 'check_violation';
                END IF;
                v_src := v_tariff.terms;
            END IF;
            SELECT t INTO v_trig FROM jsonb_array_elements(coalesce(v_src -> 'triggers', '[]'::jsonb)) t WHERE t ->> 'id' = NEW.trigger_component;
            IF v_trig IS NULL OR v_trig ->> 'trigger_code' IS DISTINCT FROM NEW.trigger_basis THEN
                RAISE EXCEPTION USING
                    MESSAGE = format('deposit rejected: the cited %s has no trigger %L for the trigger code %s (%s) — v5.4.2-15',
                                     CASE WHEN NEW.trigger_source = 'statute' THEN 'law row' ELSE 'tariff row' END, NEW.trigger_component, NEW.trigger_basis,
                                     coalesce('its trigger ' || NEW.trigger_component || ' is ' || (v_trig ->> 'trigger_code'), 'it has none by that id')),
                    ERRCODE = 'check_violation';
            END IF;
            v_cond := v_trig -> 'condition';
            v_met := CASE v_cond ->> 'kind'
                        WHEN 'ratio' THEN CASE v_cond ->> 'op' WHEN 'at_least' THEN NEW.trigger_observed >= (v_cond ->> 'value')::numeric
                                                              ELSE NEW.trigger_observed > (v_cond ->> 'value')::numeric END
                        WHEN 'count' THEN NEW.trigger_observed >= (v_cond ->> 'at_least')::numeric AND NEW.trigger_observed = trunc(NEW.trigger_observed)
                        ELSE true      -- a combined condition is the core's to judge
                     END;
            IF NOT v_met THEN
                RAISE EXCEPTION USING
                    MESSAGE = format('deposit rejected: the observed measure %s does not meet the threshold of trigger %s (%s) — v5.4.2-15', NEW.trigger_observed, NEW.trigger_component, v_cond),
                    ERRCODE = 'check_violation';
            END IF;
        END IF;
        -- A deposit taken in instalments is checked at commit against its document's schedule.
        RETURN NEW;
    END IF;

    -- UPDATE: identity frozen; projection columns only from inside the events trigger.
    IF OLD.id <> NEW.id OR OLD.tenant_id <> NEW.tenant_id OR OLD.customer_id <> NEW.customer_id OR OLD.basis <> NEW.basis
       OR OLD.trigger_basis IS DISTINCT FROM NEW.trigger_basis OR OLD.instrument <> NEW.instrument OR OLD.principal <> NEW.principal
       OR OLD.posted_on <> NEW.posted_on OR OLD.source_payment_id IS DISTINCT FROM NEW.source_payment_id
       OR OLD.cap_amount IS DISTINCT FROM NEW.cap_amount OR OLD.cap_source IS DISTINCT FROM NEW.cap_source
       OR OLD.cap_component IS DISTINCT FROM NEW.cap_component OR OLD.cap_basis_amount IS DISTINCT FROM NEW.cap_basis_amount
       OR OLD.cap_other_held IS DISTINCT FROM NEW.cap_other_held
       OR OLD.cap_binding <> NEW.cap_binding OR OLD.legacy_interest_earned IS DISTINCT FROM NEW.legacy_interest_earned
       OR OLD.state_code IS DISTINCT FROM NEW.state_code OR OLD.service_type IS DISTINCT FROM NEW.service_type
       OR OLD.system_kind IS DISTINCT FROM NEW.system_kind OR OLD.customer_class IS DISTINCT FROM NEW.customer_class
       OR OLD.tariff_category IS DISTINCT FROM NEW.tariff_category OR OLD.rule_id IS DISTINCT FROM NEW.rule_id
       OR OLD.tariff_id IS DISTINCT FROM NEW.tariff_id OR OLD.decided_by IS DISTINCT FROM NEW.decided_by
       OR OLD.trigger_source IS DISTINCT FROM NEW.trigger_source OR OLD.trigger_component IS DISTINCT FROM NEW.trigger_component
       OR OLD.trigger_observed IS DISTINCT FROM NEW.trigger_observed
       OR OLD.received_at_posting IS DISTINCT FROM NEW.received_at_posting
       OR OLD.recorded_txid IS DISTINCT FROM NEW.recorded_txid
       OR OLD.created_by IS DISTINCT FROM NEW.created_by OR OLD.created_at <> NEW.created_at THEN
        RAISE EXCEPTION USING
            MESSAGE = format('deposit %s: identity (customer, basis, instrument, principal, posted_on, cap, source, jurisdiction, class, law row, tariff row, core version) is frozen — a wrong deposit is refunded/released and re-posted', OLD.id),
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
COMMENT ON FUNCTION public.enforce_deposit() IS
    'v5.4.2-06, re-issued by v5.4.2-15 (deposits at the rule-terms convention). BEFORE INSERT OR UPDATE on deposits. INSERT: created_at stamped; the customer is visible; the basis is insertable, and names a trigger exactly when it requires one (deposit_bases); no legacy interest; born held; created_by of the tenant; the deposit cites the law row it was decided under — the row the utility''s profile, the premise''s state and service, the class and the basis resolve to on the posting date (rule_law_row_cite: in force, locked); a category is one the utility defined and falls under the deposit''s class; a tariff row, where cited, is the one in force for the category on the posting date, and is required where the law delegates; a document with a cap requires the cap that applied recorded, a statutory cap names the cap part that governed by id and records its basis figure (and, under a combined cap, what else was held); a tariff cap cites the tariff row; an additional deposit cites the trigger it was decided on (the document''s or the tariff''s) by id and code, and the measure observed meets its threshold (a count whole). UPDATE: identity frozen; status columns only from the events. Decides nothing the law decides: waivers, the cap''s size and who may be charged are the core''s.';

-- The database writes the posted event; a deposit of a basis that is carried history is a backfill.
CREATE OR REPLACE FUNCTION public.post_deposit_event() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
BEGIN
    INSERT INTO public.deposit_events (tenant_id, deposit_id, event_type, amount, effective_on, created_by, source)
    VALUES (NEW.tenant_id, NEW.id, 'posted', coalesce(NEW.received_at_posting, NEW.principal), NEW.posted_on, NEW.created_by,
            CASE WHEN (SELECT b.insertable FROM public.deposit_bases b WHERE b.basis_code = NEW.basis) THEN 'system' ELSE 'backfill' END);
    RETURN NULL;
END;
$$;
COMMENT ON FUNCTION public.post_deposit_event() IS
    'v5.4.2-06, re-issued by v5.4.2-15. AFTER INSERT on deposits: writes the posted event for what was received at posting (the principal, or received_at_posting for a deposit taken in instalments) — source system, or backfill for a basis the vocabulary marks carried history.';

-- The instalments still to come on a deposit taken in instalments: numbered from 2 (the first is received at
-- posting), each an amount and a due date, written in the deposit's own transaction. At commit their number matches
-- the cited document's schedule and they sum with what was received to the principal.
CREATE TABLE IF NOT EXISTS public.deposit_instalments (
    id            uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id     uuid NOT NULL,
    deposit_id    uuid NOT NULL,
    instalment_no smallint NOT NULL,
    amount        numeric(12,2) NOT NULL,
    due_on        date NOT NULL,
    created_at    timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT deposit_instalments_pkey PRIMARY KEY (id),
    CONSTRAINT deposit_instalments_key UNIQUE (deposit_id, instalment_no),
    CONSTRAINT deposit_instalments_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id),
    CONSTRAINT deposit_instalments_deposit_fkey FOREIGN KEY (deposit_id, tenant_id) REFERENCES public.deposits(id, tenant_id),
    CONSTRAINT deposit_instalments_check CHECK (((instalment_no >= 2) AND (amount > (0)::numeric)))
);
CREATE INDEX IF NOT EXISTS idx_deposit_instalments_tenant ON public.deposit_instalments USING btree (tenant_id);
ALTER TABLE public.deposit_instalments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.deposit_instalments FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_isolation ON public.deposit_instalments;
CREATE POLICY tenant_isolation ON public.deposit_instalments USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));
REVOKE UPDATE, DELETE, TRUNCATE ON public.deposit_instalments FROM tally_app;
COMMENT ON TABLE public.deposit_instalments IS
    'v5.4.2-15 (52 Pa. Code 56.42). The instalments still due on a deposit taken in instalments: number (from 2 — the first is deposits.received_at_posting), amount and due date, as the core computed them from the cited document''s schedule (instalments); rounding is the core''s. Written in the deposit''s own transaction; at commit their number matches the document''s schedule and received_at_posting plus their amounts equals the principal. A receipt is an instalment_received event. Append-only.';

CREATE OR REPLACE FUNCTION public.enforce_deposit_instalment() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    d public.deposits%ROWTYPE;
BEGIN
    SELECT * INTO d FROM public.deposits x WHERE x.id = NEW.deposit_id AND x.tenant_id = NEW.tenant_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING MESSAGE = format('deposit instalment: deposit %s not found (or not visible)', NEW.deposit_id), ERRCODE = 'foreign_key_violation';
    END IF;
    IF d.recorded_txid IS DISTINCT FROM txid_current() THEN
        RAISE EXCEPTION USING
            MESSAGE = format('deposit instalment: deposit %s was recorded in an earlier transaction; its schedule is complete (v5.4.2-15)', d.id),
            ERRCODE = 'restrict_violation';
    END IF;
    IF d.received_at_posting IS NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('deposit instalment: deposit %s was received whole at posting (received_at_posting is empty) — v5.4.2-15', d.id),
            ERRCODE = 'check_violation';
    END IF;
    IF NEW.due_on < d.posted_on THEN
        RAISE EXCEPTION USING
            MESSAGE = format('deposit instalment: due %s, before the deposit was posted (%s) — v5.4.2-15', NEW.due_on, d.posted_on),
            ERRCODE = 'check_violation';
    END IF;
    NEW.created_at := now();
    RETURN NEW;
END;
$$;
COMMENT ON FUNCTION public.enforce_deposit_instalment() IS
    'v5.4.2-15. BEFORE INSERT on deposit_instalments: the deposit is visible, was recorded in this transaction and was taken in instalments (received_at_posting); due on or after posting; created_at stamped.';
DROP TRIGGER IF EXISTS a_enforce_deposit_instalment ON public.deposit_instalments;
CREATE TRIGGER a_enforce_deposit_instalment BEFORE INSERT ON public.deposit_instalments
    FOR EACH ROW EXECUTE FUNCTION public.enforce_deposit_instalment();
ALTER TABLE public.deposit_instalments ENABLE ALWAYS TRIGGER a_enforce_deposit_instalment;
DROP TRIGGER IF EXISTS append_only ON public.deposit_instalments;
CREATE TRIGGER append_only BEFORE UPDATE OR DELETE ON public.deposit_instalments FOR EACH ROW EXECUTE FUNCTION public.enforce_append_only();
DROP TRIGGER IF EXISTS no_truncate ON public.deposit_instalments;
CREATE TRIGGER no_truncate BEFORE TRUNCATE ON public.deposit_instalments FOR EACH STATEMENT EXECUTE FUNCTION public.enforce_no_hard_delete();
ALTER TABLE public.deposit_instalments ENABLE ALWAYS TRIGGER append_only;
ALTER TABLE public.deposit_instalments ENABLE ALWAYS TRIGGER no_truncate;

CREATE OR REPLACE FUNCTION public.deposit_instalments_check(p_deposit_id uuid) RETURNS void
    LANGUAGE plpgsql STABLE
    SET search_path = public, pg_temp
    AS $$
DECLARE
    d        public.deposits%ROWTYPE;
    v_n      integer;
    v_sum    numeric;
    v_doc_n  integer;
BEGIN
    SELECT * INTO d FROM public.deposits x WHERE x.id = p_deposit_id;
    IF NOT FOUND OR d.received_at_posting IS NULL THEN
        RETURN;
    END IF;
    SELECT count(*), coalesce(sum(i.amount), 0) INTO v_n, v_sum FROM public.deposit_instalments i WHERE i.deposit_id = d.id;
    SELECT coalesce(nullif(jsonb_array_length(r.terms -> 'instalments'), 0),
                    (SELECT jsonb_array_length(t.terms -> 'instalments') FROM public.deposit_tariffs t WHERE t.id = d.tariff_id), 0)
      INTO v_doc_n FROM public.deposit_rules r WHERE r.id = d.rule_id;
    IF v_n + 1 <> v_doc_n OR d.received_at_posting + v_sum <> d.principal THEN
        RAISE EXCEPTION USING
            MESSAGE = format('deposit %s: taken in instalments, it records %s instalment(s) summing with the %s received at posting to %s; its schedule (the law row''s, or where the law gives none the cited tariff''s) has %s and the principal is %s (v5.4.2-15)', d.id, v_n + 1, d.received_at_posting, d.received_at_posting + v_sum, v_doc_n, d.principal),
            ERRCODE = 'check_violation';
    END IF;
END;
$$;
COMMENT ON FUNCTION public.deposit_instalments_check(uuid) IS
    'v5.4.2-15. A deposit taken in instalments has as many instalments (the one at posting plus deposit_instalments) as its schedule — the law row''s, or where the law gives none the cited tariff''s — and they sum with what was received at posting to the principal. Raises check_violation.';
CREATE OR REPLACE FUNCTION public.enforce_deposit_instalments_complete() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
BEGIN
    IF TG_TABLE_NAME = 'deposits' THEN
        PERFORM public.deposit_instalments_check(NEW.id);
    ELSE
        PERFORM public.deposit_instalments_check(NEW.deposit_id);
    END IF;
    RETURN NULL;
END;
$$;
COMMENT ON FUNCTION public.enforce_deposit_instalments_complete() IS
    'v5.4.2-15. Deferred constraint trigger, AFTER INSERT on deposits and on deposit_instalments: at commit — and again after any constraint flush that a later instalment follows — a deposit taken in instalments has its schedule exactly (deposit_instalments_check).';
DROP TRIGGER IF EXISTS z_enforce_deposit_instalments_complete ON public.deposits;
CREATE CONSTRAINT TRIGGER z_enforce_deposit_instalments_complete AFTER INSERT ON public.deposits
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION public.enforce_deposit_instalments_complete();
ALTER TABLE public.deposits ENABLE ALWAYS TRIGGER z_enforce_deposit_instalments_complete;
DROP TRIGGER IF EXISTS z_enforce_deposit_instalments_complete ON public.deposit_instalments;
CREATE CONSTRAINT TRIGGER z_enforce_deposit_instalments_complete AFTER INSERT ON public.deposit_instalments
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION public.enforce_deposit_instalments_complete();
ALTER TABLE public.deposit_instalments ENABLE ALWAYS TRIGGER z_enforce_deposit_instalments_complete;

ALTER TABLE public.deposits DROP COLUMN IF EXISTS refund_eligibility_on;
ALTER TABLE public.deposits DROP COLUMN IF EXISTS cap_basis_annual_billing;

COMMENT ON TABLE public.deposits IS
    'A-21 (v5.4.2-06; v5.4.2-15 at the rule-terms convention): one record per deposit. basis (a deposit_bases row: why it was taken), trigger_basis for an additional deposit, instrument, principal, posted_on, and what it was decided under: state_code / service_type (from the premise), system_kind, customer_class (the law class) and the utility''s own tariff_category, the deposit_rules row (rule_id: always — a city''s delegation row for a city), the deposit_tariffs row that applied (tariff_id), and the core version (decided_by). The cap that applied (cap_amount, cap_binding), where it came from (cap_source: statute, naming the document''s cap part that governed by id in cap_component, with the figure it was computed from in cap_basis_amount; or tariff, citing the tariff row) and, under a combined cap, what else was held (cap_other_held). For an additional deposit, the trigger it was decided on (trigger_source statute or tariff, trigger_component the trigger''s id) and the measure observed (trigger_observed). principal is the deposit required; a deposit taken in instalments records what was received at posting (received_at_posting) and its remaining instalments, and holds what has been received. Identity is frozen after insert. status / refunded_on / released_on are a PROJECTION of deposit_events: held → partial_applied / applied → refund_pending → refunded; non-cash → released. A legacy_unknown row (carried by -06) cites no law row; the core refuses to decide one. Whether a deposit may be required, how large, and what it earns are the core''s.';
COMMENT ON COLUMN public.deposits.cap_amount IS
    'The cap that applied at the deposit decision — the statute''s (the cited document''s) or the utility''s tariff''s (cap_source); required when the cited document caps the deposit. principal ≤ cap_amount − cap_other_held (CHECK); cap_binding when it reduced the amount — the customer is entitled to know (decision table #53). The computation is the core''s.';
COMMENT ON COLUMN public.deposits.cap_component IS
    'The id of the cap part of the cited document that governed the statutory cap (under lesser-of or greater-of, the part that won), recorded whichever source set the cap that applied; NULL only where the document sets no cap. cap_basis_amount is the figure that part is computed from: annual billing (fraction of annual billing), monthly billing (months of billing), the total of the N highest bills (highest_bills), the seasonal average (seasonal_average); none for a fixed amount. Under a delegation it is the monthly billing a months-of-billing tariff is computed from.';
COMMENT ON COLUMN public.deposits.rule_id IS
    'The deposit_rules row the core decided this deposit under: the row its utility''s profile, its premise''s state and service, its class and its basis resolve to on posted_on. Law rows never change, so the citation stays true.';
COMMENT ON COLUMN public.deposits.tariff_id IS
    'The utility''s own deposit_tariffs row that applied, in force for tariff_category on posted_on. Required where the law row delegates to the utility, and wherever a deposit has a tariff_category and a tariff row is in force for that category on posted_on (a deposit with no category may skip every tariff; the statutory cap still holds).';
COMMENT ON COLUMN public.deposits.decided_by IS 'The calculation core''s version that decided the deposit.';



-- ----------------------------------------------------------------------------
-- 11. The return-due record (R-D2)
-- ----------------------------------------------------------------------------
-- WRITTEN BY THE CORE when a deposit's mandatory return falls due — once, when
-- the answer changes, never per check. The due row cites the law row and the
-- core version; its evidence rows say why (a reason per row, naming the return
-- rule of the document it rests on) and on what (the bills the core judged,
-- with its classification of each, the customer's state change, or the deposit
-- itself), written in the due row's own transaction. A due row found wrong — a
-- reversed payment, a corrected bill, a core bug — is withdrawn by a separate
-- row; a corrected answer is a new due row that names the one it supersedes. A
-- customer falling behind after qualifying is NOT a withdrawal: whether the
-- return stays owed is law (the return rule's `vests`), the core's.
--
-- WHAT THE DATABASE KEEPS TRUE: the cited law row is the deposit's own (or one
-- of its key in force) and has a return rule for the deposit's instrument — for
-- a due row with an amount, one with a partial reason; no return has started;
-- at most one live (unwithdrawn) due row per deposit, serialised by a ROW-
-- VERSION mutex on the deposit row; every due row has evidence; each evidence
-- row names a return rule of the document, its reason, resting on a record of
-- its kind (a bill of the deposit's customer from posting to the due date; a
-- change of the customer's state to a status the reason names, by the UTC day;
-- the deposit itself), and only in its due row's transaction; withdrawals once
-- each; stamps.

CREATE SEQUENCE IF NOT EXISTS public.deposit_return_due_seq;
GRANT USAGE, SELECT ON SEQUENCE public.deposit_return_due_seq TO tally_app;

CREATE TABLE IF NOT EXISTS public.deposit_return_due (
    id                  uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id           uuid NOT NULL,
    deposit_id          uuid NOT NULL,
    rule_id             uuid NOT NULL,
    due_on              date NOT NULL,
    amount              numeric(12,2),
    supersedes_due_id   uuid,
    inputs              jsonb NOT NULL,
    inputs_fingerprint  text NOT NULL,
    calculated_by       text NOT NULL,
    due_seq             bigint DEFAULT nextval('public.deposit_return_due_seq') NOT NULL,
    recorded_txid       bigint DEFAULT txid_current() NOT NULL,
    created_at          timestamp with time zone DEFAULT now() NOT NULL,
    created_by          uuid,
    CONSTRAINT deposit_return_due_pkey PRIMARY KEY (id),
    CONSTRAINT deposit_return_due_id_tenant_id_key UNIQUE (id, tenant_id),
    CONSTRAINT deposit_return_due_supersedes_key UNIQUE (supersedes_due_id),
    CONSTRAINT deposit_return_due_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id),
    CONSTRAINT deposit_return_due_deposit_fkey FOREIGN KEY (deposit_id, tenant_id) REFERENCES public.deposits(id, tenant_id),
    CONSTRAINT deposit_return_due_rule_fkey FOREIGN KEY (rule_id) REFERENCES public.deposit_rules(id),
    CONSTRAINT deposit_return_due_supersedes_fkey FOREIGN KEY (supersedes_due_id, tenant_id) REFERENCES public.deposit_return_due(id, tenant_id),
    CONSTRAINT deposit_return_due_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id),
    CONSTRAINT deposit_return_due_inputs_check
        CHECK (((jsonb_typeof(inputs) = 'object'::text) AND (inputs_fingerprint ~ '[[:alnum:]]'::text))),
    CONSTRAINT deposit_return_due_calculated_by_check CHECK ((calculated_by ~ '[[:alnum:]]'::text)),
    -- A partial return due: the amount to return; NULL = the whole remainder.
    CONSTRAINT deposit_return_due_amount_check CHECK (((amount IS NULL) OR (amount > (0)::numeric)))
);
CREATE INDEX IF NOT EXISTS idx_deposit_return_due_tenant ON public.deposit_return_due USING btree (tenant_id);
CREATE INDEX IF NOT EXISTS idx_deposit_return_due_deposit ON public.deposit_return_due USING btree (deposit_id, due_seq);
CREATE INDEX IF NOT EXISTS idx_deposit_return_due_rule ON public.deposit_return_due USING btree (rule_id);
ALTER TABLE public.deposit_return_due ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.deposit_return_due FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_isolation ON public.deposit_return_due;
CREATE POLICY tenant_isolation ON public.deposit_return_due USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));
REVOKE UPDATE, DELETE, TRUNCATE ON public.deposit_return_due FROM tally_app;

CREATE TABLE IF NOT EXISTS public.deposit_return_due_withdrawals (
    id              uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id       uuid NOT NULL,
    due_id          uuid NOT NULL,
    reason          text NOT NULL,
    calculated_by   text,
    created_at      timestamp with time zone DEFAULT now() NOT NULL,
    created_by      uuid,
    CONSTRAINT deposit_return_due_withdrawals_pkey PRIMARY KEY (id),
    CONSTRAINT deposit_return_due_withdrawals_due_key UNIQUE (due_id),
    CONSTRAINT deposit_return_due_withdrawals_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id),
    CONSTRAINT deposit_return_due_withdrawals_due_fkey FOREIGN KEY (due_id, tenant_id) REFERENCES public.deposit_return_due(id, tenant_id),
    CONSTRAINT deposit_return_due_withdrawals_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id),
    CONSTRAINT deposit_return_due_withdrawals_reason_check CHECK ((reason ~ '[[:alnum:]]'::text)),
    CONSTRAINT deposit_return_due_withdrawals_calculated_by_check CHECK (((calculated_by IS NULL) OR (calculated_by ~ '[[:alnum:]]'::text)))
);
CREATE INDEX IF NOT EXISTS idx_deposit_return_due_withdrawals_tenant ON public.deposit_return_due_withdrawals USING btree (tenant_id);
ALTER TABLE public.deposit_return_due_withdrawals ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.deposit_return_due_withdrawals FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_isolation ON public.deposit_return_due_withdrawals;
CREATE POLICY tenant_isolation ON public.deposit_return_due_withdrawals USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));
REVOKE UPDATE, DELETE, TRUNCATE ON public.deposit_return_due_withdrawals FROM tally_app;

CREATE TABLE IF NOT EXISTS public.deposit_return_due_evidence (
    id                       uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id                uuid NOT NULL,
    due_id                   uuid NOT NULL,
    reason_code              text NOT NULL,
    return_component         text NOT NULL,
    invoice_id               uuid,
    classification           text,
    customer_state_event_id  uuid,
    rests_on_deposit         boolean DEFAULT false NOT NULL,
    CONSTRAINT deposit_return_due_evidence_pkey PRIMARY KEY (id),
    CONSTRAINT deposit_return_due_evidence_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id),
    CONSTRAINT deposit_return_due_evidence_due_fkey FOREIGN KEY (due_id, tenant_id) REFERENCES public.deposit_return_due(id, tenant_id),
    CONSTRAINT deposit_return_due_evidence_reason_fkey FOREIGN KEY (reason_code) REFERENCES public.deposit_return_reasons(reason_code),
    CONSTRAINT deposit_return_due_evidence_invoice_fkey FOREIGN KEY (invoice_id, tenant_id) REFERENCES public.invoices(id, tenant_id),
    CONSTRAINT deposit_return_due_evidence_state_event_fkey FOREIGN KEY (customer_state_event_id) REFERENCES public.customer_state_events(id),
    CONSTRAINT deposit_return_due_evidence_component_check CHECK ((return_component ~ '^[a-z][a-z0-9_]*$'::text)),
    -- One subject per row: a bill with the core's classification of it, a state change, or the deposit itself.
    CONSTRAINT deposit_return_due_evidence_subject_check
        CHECK ((((invoice_id IS NOT NULL) AND (customer_state_event_id IS NULL) AND (NOT rests_on_deposit) AND (classification IS NOT NULL))
             OR ((invoice_id IS NULL) AND (customer_state_event_id IS NOT NULL) AND (NOT rests_on_deposit) AND (classification IS NULL))
             OR ((invoice_id IS NULL) AND (customer_state_event_id IS NULL) AND rests_on_deposit AND (classification IS NULL)))),
    CONSTRAINT deposit_return_due_evidence_classification_check
        CHECK (((classification IS NULL) OR (classification = ANY (ARRAY['clean'::text, 'delinquent'::text, 'not_counted'::text])))),
    CONSTRAINT deposit_return_due_evidence_key
        UNIQUE NULLS NOT DISTINCT (due_id, reason_code, invoice_id, customer_state_event_id, rests_on_deposit)
);
CREATE INDEX IF NOT EXISTS idx_deposit_return_due_evidence_tenant ON public.deposit_return_due_evidence USING btree (tenant_id);
CREATE INDEX IF NOT EXISTS idx_deposit_return_due_evidence_due ON public.deposit_return_due_evidence USING btree (due_id);
ALTER TABLE public.deposit_return_due_evidence ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.deposit_return_due_evidence FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_isolation ON public.deposit_return_due_evidence;
CREATE POLICY tenant_isolation ON public.deposit_return_due_evidence USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));
REVOKE UPDATE, DELETE, TRUNCATE ON public.deposit_return_due_evidence FROM tally_app;

-- Live: not withdrawn, and — for a partial return — not yet settled by the principal_returned that cites it. A full
-- return settles by a refund or release, after which the deposit takes no more rows.
CREATE OR REPLACE FUNCTION public.deposit_return_due_is_live(p_due_id uuid) RETURNS boolean
    LANGUAGE plpgsql STABLE
    SET search_path = public, pg_temp
    AS $$
BEGIN
    RETURN NOT EXISTS (SELECT 1 FROM public.deposit_return_due_withdrawals w WHERE w.due_id = p_due_id)
       AND NOT EXISTS (SELECT 1 FROM public.deposit_events e WHERE e.return_due_id = p_due_id AND e.event_type = 'principal_returned');
END;
$$;
COMMENT ON FUNCTION public.deposit_return_due_is_live(uuid) IS
    'v5.4.2-15 (R-D2). A return-due row is live while it is not withdrawn and, for a partial return, not settled by the principal_returned event citing it.';

CREATE OR REPLACE FUNCTION public.enforce_deposit_return_due_record() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    d       public.deposits%ROWTYPE;
    v_doc   jsonb;
    v_live  uuid;
BEGIN
    -- The deposit row is the mutex: every deposit event locks it the same way, so a due row and a refund, or two due
    -- rows, cannot cross.
    SELECT * INTO d FROM public.deposits x WHERE x.id = NEW.deposit_id AND x.tenant_id = NEW.tenant_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING MESSAGE = format('deposit return due: deposit %s not found (or not visible)', NEW.deposit_id), ERRCODE = 'foreign_key_violation';
    END IF;
    -- Write a version of the deposit row: a concurrent REPEATABLE READ transaction that also takes the mutex then fails
    -- to serialise, rather than counting live rows from its old snapshot.
    UPDATE public.deposits x SET status = x.status WHERE x.id = d.id;
    PERFORM public.deposit_cite_rule('deposit return due', d.id, NEW.rule_id, NEW.due_on, NEW.due_on);
    SELECT r.terms INTO v_doc FROM public.deposit_rules r WHERE r.id = NEW.rule_id;
    IF NEW.amount IS NULL AND NOT EXISTS (
        SELECT 1 FROM jsonb_array_elements(coalesce(v_doc -> 'return', '[]'::jsonb)) r WHERE (r -> 'instruments') ? d.instrument) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('deposit return due: law row %s has no return rule for a %s deposit — nothing makes its return mandatory (v5.4.2-15)', NEW.rule_id, d.instrument),
            ERRCODE = 'check_violation';
    END IF;
    -- A partial return due: the document returns an excess over the cap (a rule whose reason is a partial one), and the
    -- amount leaves something held (all of it is a return of the whole).
    IF NEW.amount IS NOT NULL THEN
        IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(coalesce(v_doc -> 'return', '[]'::jsonb)) r
                        JOIN public.deposit_return_reasons x ON x.reason_code = r #>> '{when,reason}'
                       WHERE x.partial AND (r -> 'instruments') ? d.instrument) THEN
            RAISE EXCEPTION USING
                MESSAGE = format('deposit return due: law row %s returns no excess over the cap (no return rule with a partial reason for a %s deposit); a due row with an amount is a partial return (v5.4.2-15)', NEW.rule_id, d.instrument),
                ERRCODE = 'check_violation';
        END IF;
        IF NEW.amount >= (SELECT b.remainder FROM public.deposit_balance(d.id) b) THEN
            RAISE EXCEPTION USING
                MESSAGE = format('deposit return due: a partial return of %s leaves nothing held; returning the whole remainder is a due row without an amount (v5.4.2-15)', NEW.amount),
                ERRCODE = 'check_violation';
        END IF;
    END IF;
    IF d.status IN ('refund_pending', 'refunded', 'released') THEN
        RAISE EXCEPTION USING
            MESSAGE = format('deposit return due: deposit %s is already %s — its return has started (v5.4.2-15)', d.id, d.status),
            ERRCODE = 'check_violation';
    END IF;
    IF NEW.due_on < d.posted_on THEN
        RAISE EXCEPTION USING
            MESSAGE = format('deposit return due: due_on %s precedes the posting date %s (v5.4.2-15)', NEW.due_on, d.posted_on),
            ERRCODE = 'check_violation';
    END IF;
    SELECT r.id INTO v_live FROM public.deposit_return_due r WHERE r.deposit_id = d.id AND public.deposit_return_due_is_live(r.id) LIMIT 1;
    IF v_live IS NOT NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('deposit return due: deposit %s already has a live due row (%s); the answer has not changed — withdraw that row first if it was wrong (v5.4.2-15)', d.id, v_live),
            ERRCODE = 'unique_violation';
    END IF;
    IF NEW.supersedes_due_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM public.deposit_return_due r JOIN public.deposit_return_due_withdrawals w ON w.due_id = r.id
         WHERE r.id = NEW.supersedes_due_id AND r.deposit_id = d.id) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('deposit return due: it may supersede only a withdrawn due row of the same deposit; %s is not one (v5.4.2-15)', NEW.supersedes_due_id),
            ERRCODE = 'check_violation';
    END IF;
    NEW.created_at    := now();
    NEW.recorded_txid := txid_current();
    NEW.due_seq       := nextval('public.deposit_return_due_seq');
    BEGIN
        NEW.created_by := NULLIF(current_setting('app.user_id', true), '')::uuid;
    EXCEPTION WHEN OTHERS THEN
        NEW.created_by := NULL;
    END;
    RETURN NEW;
END;
$$;
COMMENT ON FUNCTION public.enforce_deposit_return_due_record() IS
    'v5.4.2-15 (R-D2). BEFORE INSERT on deposit_return_due: locks the deposit row and writes a version of it (the row-version mutex every deposit event shares); the cited law row is the deposit''s own or one of its key in force on due_on (deposit_cite_rule), and its document has a return rule for the deposit''s instrument — or, for a due row with an amount, one whose reason is a partial one, the amount leaving something held; no return has started; due_on is on or after posting; no live due row exists for the deposit; a superseded row is a withdrawn row of the same deposit; stamps created_at, created_by (session user), due_seq and recorded_txid (the transaction its evidence must be written in). Judges nothing the core computed.';
DROP TRIGGER IF EXISTS a_enforce_deposit_return_due_record ON public.deposit_return_due;
CREATE TRIGGER a_enforce_deposit_return_due_record BEFORE INSERT ON public.deposit_return_due
    FOR EACH ROW EXECUTE FUNCTION public.enforce_deposit_return_due_record();
ALTER TABLE public.deposit_return_due ENABLE ALWAYS TRIGGER a_enforce_deposit_return_due_record;

-- Every due row says why: at commit it has evidence.
CREATE OR REPLACE FUNCTION public.enforce_deposit_return_due_has_evidence() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.deposit_return_due_evidence e WHERE e.due_id = NEW.id) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('deposit return due %s: it records no evidence — write its reasons and what they rest on (deposit_return_due_evidence) in the same transaction (v5.4.2-15)', NEW.id),
            ERRCODE = 'check_violation';
    END IF;
    RETURN NULL;
END;
$$;
COMMENT ON FUNCTION public.enforce_deposit_return_due_has_evidence() IS
    'v5.4.2-15. Deferred constraint trigger, AFTER INSERT on deposit_return_due: at commit the due row has at least one evidence row.';
DROP TRIGGER IF EXISTS z_enforce_deposit_return_due_has_evidence ON public.deposit_return_due;
CREATE CONSTRAINT TRIGGER z_enforce_deposit_return_due_has_evidence AFTER INSERT ON public.deposit_return_due
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION public.enforce_deposit_return_due_has_evidence();
ALTER TABLE public.deposit_return_due ENABLE ALWAYS TRIGGER z_enforce_deposit_return_due_has_evidence;

CREATE OR REPLACE FUNCTION public.enforce_deposit_return_due_evidence() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_due    record;
    v_reason public.deposit_return_reasons%ROWTYPE;
    v_rule   jsonb;
BEGIN
    SELECT r.recorded_txid, r.due_on, r.amount, d.customer_id, d.posted_on, d.instrument, l.terms INTO v_due
      FROM public.deposit_return_due r
      JOIN public.deposits d ON d.id = r.deposit_id
      JOIN public.deposit_rules l ON l.id = r.rule_id
     WHERE r.id = NEW.due_id;
    IF v_due.recorded_txid IS DISTINCT FROM txid_current() THEN
        RAISE EXCEPTION USING
            MESSAGE = format('deposit return due evidence: due row %s was recorded in an earlier transaction; its evidence is complete (v5.4.2-15)', NEW.due_id),
            ERRCODE = 'restrict_violation',
            HINT = 'Withdraw the row and record a new one, with its evidence, in one transaction.';
    END IF;
    -- The return rule of the cited document this evidence rests on, and its reason.
    SELECT r INTO v_rule FROM jsonb_array_elements(coalesce(v_due.terms -> 'return', '[]'::jsonb)) r WHERE r ->> 'id' = NEW.return_component;
    IF v_rule IS NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('deposit return due evidence: the cited law row has no return rule %L (v5.4.2-15)', NEW.return_component),
            ERRCODE = 'check_violation';
    END IF;
    IF v_rule #>> '{when,reason}' IS DISTINCT FROM NEW.reason_code THEN
        RAISE EXCEPTION USING
            MESSAGE = format('deposit return due evidence: reason %s is not the reason of return rule %s (%s) (v5.4.2-15)', NEW.reason_code, NEW.return_component, v_rule #>> '{when,reason}'),
            ERRCODE = 'check_violation';
    END IF;
    IF NOT ((v_rule -> 'instruments') ? v_due.instrument) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('deposit return due evidence: return rule %s does not reach a %s deposit (v5.4.2-15)', NEW.return_component, v_due.instrument),
            ERRCODE = 'check_violation';
    END IF;
    SELECT * INTO v_reason FROM public.deposit_return_reasons x WHERE x.reason_code = NEW.reason_code;
    IF v_reason.evidence_kind IS DISTINCT FROM (CASE WHEN NEW.invoice_id IS NOT NULL THEN 'invoice'
                                                     WHEN NEW.customer_state_event_id IS NOT NULL THEN 'state_event'
                                                     ELSE 'deposit' END) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('deposit return due evidence: reason %s rests on %s records (v5.4.2-15)', NEW.reason_code, coalesce(v_reason.evidence_kind, '(unknown reason)')),
            ERRCODE = 'check_violation';
    END IF;
    -- A partial reason exactly on a due row with an amount.
    IF v_reason.partial IS DISTINCT FROM (v_due.amount IS NOT NULL) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('deposit return due evidence: reason %s %s; this due row %s (v5.4.2-15)', NEW.reason_code,
                             CASE WHEN v_reason.partial THEN 'returns part of a deposit' ELSE 'returns the whole deposit' END,
                             CASE WHEN v_due.amount IS NULL THEN 'returns the whole remainder' ELSE format('returns %s', v_due.amount) END),
            ERRCODE = 'check_violation';
    END IF;
    IF NEW.invoice_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM public.invoices i WHERE i.id = NEW.invoice_id AND i.customer_id = v_due.customer_id
           AND i.invoice_date >= v_due.posted_on AND i.invoice_date <= v_due.due_on) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('deposit return due evidence: invoice %s is not a bill of the deposit''s customer dated from its posting to the due date %s (v5.4.2-15)', NEW.invoice_id, v_due.due_on),
            ERRCODE = 'check_violation';
    END IF;
    IF NEW.customer_state_event_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM public.customer_state_events s
         WHERE s.id = NEW.customer_state_event_id AND s.customer_id = v_due.customer_id
           AND s.to_status = ANY (v_reason.qualifying_statuses)
           -- the day in UTC, which no session setting changes
           AND (s.effective_at AT TIME ZONE 'UTC')::date BETWEEN v_due.posted_on AND v_due.due_on) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('deposit return due evidence: state event %s is not a change of the deposit''s customer to %s from its posting to the due date %s, by the UTC date (v5.4.2-15)', NEW.customer_state_event_id, array_to_string(v_reason.qualifying_statuses, ' / '), v_due.due_on),
            ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$;
COMMENT ON FUNCTION public.enforce_deposit_return_due_evidence() IS
    'v5.4.2-15. BEFORE INSERT on deposit_return_due_evidence: only in its due row''s transaction (deposit_return_due.recorded_txid); it names a return rule of the cited document (return_component) whose reason it is and which reaches the deposit''s instrument; the subject is of the reason''s evidence kind (bill, state change, the deposit itself); a partial reason exactly on a due row with an amount; a bill is the deposit''s customer''s, dated from posting to the due date; a state change is the deposit''s customer''s, to one of the reason''s qualifying statuses, from posting to the due date by the UTC date. Which bills count and how is the core''s.';
DROP TRIGGER IF EXISTS a_enforce_deposit_return_due_evidence ON public.deposit_return_due_evidence;
CREATE TRIGGER a_enforce_deposit_return_due_evidence BEFORE INSERT ON public.deposit_return_due_evidence
    FOR EACH ROW EXECUTE FUNCTION public.enforce_deposit_return_due_evidence();
ALTER TABLE public.deposit_return_due_evidence ENABLE ALWAYS TRIGGER a_enforce_deposit_return_due_evidence;

CREATE OR REPLACE FUNCTION public.enforce_deposit_return_due_withdrawal() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_deposit uuid;
BEGIN
    SELECT r.deposit_id INTO v_deposit FROM public.deposit_return_due r WHERE r.id = NEW.due_id AND r.tenant_id = NEW.tenant_id;
    IF v_deposit IS NULL THEN
        RAISE EXCEPTION USING MESSAGE = format('deposit return due withdrawal: due row %s not found (or not visible)', NEW.due_id), ERRCODE = 'foreign_key_violation';
    END IF;
    -- The same row-version mutex as a new due row.
    PERFORM 1 FROM public.deposits d WHERE d.id = v_deposit FOR UPDATE;
    UPDATE public.deposits d SET status = d.status WHERE d.id = v_deposit;
    NEW.created_at := now();
    BEGIN
        NEW.created_by := NULLIF(current_setting('app.user_id', true), '')::uuid;
    EXCEPTION WHEN OTHERS THEN
        NEW.created_by := NULL;
    END;
    RETURN NEW;
END;
$$;
COMMENT ON FUNCTION public.enforce_deposit_return_due_withdrawal() IS
    'v5.4.2-15. BEFORE INSERT on deposit_return_due_withdrawals: the due row is visible; locks its deposit row and writes a version of it (the due-row mutex); stamps created_at and created_by. A withdrawal says the due row was wrong; it moves no money (a return already made is corrected through deposit_events).';
DROP TRIGGER IF EXISTS a_enforce_deposit_return_due_withdrawal ON public.deposit_return_due_withdrawals;
CREATE TRIGGER a_enforce_deposit_return_due_withdrawal BEFORE INSERT ON public.deposit_return_due_withdrawals
    FOR EACH ROW EXECUTE FUNCTION public.enforce_deposit_return_due_withdrawal();
ALTER TABLE public.deposit_return_due_withdrawals ENABLE ALWAYS TRIGGER a_enforce_deposit_return_due_withdrawal;

DO $$
DECLARE t text;
BEGIN
    FOREACH t IN ARRAY ARRAY['deposit_return_due', 'deposit_return_due_evidence', 'deposit_return_due_withdrawals'] LOOP
        EXECUTE format('DROP TRIGGER IF EXISTS append_only ON public.%I', t);
        EXECUTE format('CREATE TRIGGER append_only BEFORE UPDATE OR DELETE ON public.%I FOR EACH ROW EXECUTE FUNCTION public.enforce_append_only()', t);
        EXECUTE format('DROP TRIGGER IF EXISTS no_truncate ON public.%I', t);
        EXECUTE format('CREATE TRIGGER no_truncate BEFORE TRUNCATE ON public.%I FOR EACH STATEMENT EXECUTE FUNCTION public.enforce_no_hard_delete()', t);
        EXECUTE format('ALTER TABLE public.%I ENABLE ALWAYS TRIGGER append_only', t);
        EXECUTE format('ALTER TABLE public.%I ENABLE ALWAYS TRIGGER no_truncate', t);
    END LOOP;
END;
$$;

COMMENT ON TABLE public.deposit_return_due IS
    'v5.4.2-15 (R-D2). The core''s record that a deposit''s mandatory return fell due: the deposit, the date, the amount for a partial return (an excess over the cap; NULL = the whole remainder), the law row, the inputs and their fingerprint, the core version, stamped. Written when the answer changes, never per check. Its reasons and what they rest on are deposit_return_due_evidence, in the same transaction. A row found wrong is withdrawn (deposit_return_due_withdrawals) and a corrected answer is a new row naming it (supersedes_due_id). At most one live row per deposit (live: unwithdrawn, and a partial one not yet settled by its principal_returned). Append-only.';
COMMENT ON TABLE public.deposit_return_due_evidence IS
    'v5.4.2-15 (R-D2). Why a return fell due and on what: one row per reason and record, naming the return rule of the cited document it rests on (return_component) — a bill with the core''s classification of it (clean, delinquent, not_counted), the customer''s state change, or the deposit itself (rests_on_deposit). Written in its due row''s transaction; append-only. The counts are derived from these rows.';
COMMENT ON TABLE public.deposit_return_due_withdrawals IS
    'v5.4.2-15 (R-D2). A due row found wrong (a reversed payment, a corrected bill, a core bug), withdrawn once with the reason, by a person or the core (calculated_by when the core). It moves no money. A customer falling behind after qualifying is not a withdrawal: whether the return stays owed is the return rule''s vests, the core''s. Append-only.';

-- The operators' list: recorded answers, not computed law.
CREATE OR REPLACE VIEW public.deposits_return_owed WITH (security_invoker = true) AS
    SELECT r.id AS due_id, r.tenant_id, d.customer_id, r.deposit_id, r.due_on, r.amount AS amount_due, r.rule_id,
           (SELECT array_agg(DISTINCT e.reason_code ORDER BY e.reason_code)
              FROM public.deposit_return_due_evidence e WHERE e.due_id = r.id) AS reasons,
           d.instrument, d.status AS deposit_status, b.remainder,
           b.interest_accrued - b.interest_credited AS interest_uncredited,
           r.calculated_by
      FROM public.deposit_return_due r
      JOIN public.deposits d ON d.id = r.deposit_id
     CROSS JOIN LATERAL public.deposit_balance(d.id) b
     WHERE public.deposit_return_due_is_live(r.id)
       AND d.status IN ('held', 'partial_applied', 'applied');
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.deposits_return_owed FROM tally_app;
GRANT SELECT ON public.deposits_return_owed TO tally_app;
COMMENT ON VIEW public.deposits_return_owed IS
    'v5.4.2-15 (R-D2; Kyle #54). Deposit returns owed and not started: live return-due rows (unwithdrawn; a partial one unsettled) on deposits with no refund or release begun; amount_due is a partial return''s amount (NULL = the whole remainder). A fully applied deposit stays listed until its zero refund is recorded — interest may still be owed at refund. Reads recorded answers; computes no law. Invoker rights.';


-- ----------------------------------------------------------------------------
-- 12. deposit_events — the arithmetic stays, the law goes
-- ----------------------------------------------------------------------------
ALTER TABLE public.deposit_events
    ADD COLUMN IF NOT EXISTS rate_id        uuid,
    ADD COLUMN IF NOT EXISTS rule_id        uuid,
    ADD COLUMN IF NOT EXISTS calculated_by  text,
    ADD COLUMN IF NOT EXISTS return_due_id  uuid;

ALTER TABLE public.deposit_events DROP CONSTRAINT IF EXISTS deposit_events_rate_fkey;
ALTER TABLE public.deposit_events ADD CONSTRAINT deposit_events_rate_fkey FOREIGN KEY (rate_id, tenant_id) REFERENCES public.deposit_interest_rates(id, tenant_id);
ALTER TABLE public.deposit_events DROP CONSTRAINT IF EXISTS deposit_events_rule_fkey;
ALTER TABLE public.deposit_events ADD CONSTRAINT deposit_events_rule_fkey FOREIGN KEY (rule_id) REFERENCES public.deposit_rules(id);
ALTER TABLE public.deposit_events DROP CONSTRAINT IF EXISTS deposit_events_return_due_fkey;
ALTER TABLE public.deposit_events ADD CONSTRAINT deposit_events_return_due_fkey FOREIGN KEY (return_due_id, tenant_id) REFERENCES public.deposit_return_due(id, tenant_id);
CREATE INDEX IF NOT EXISTS idx_deposit_events_rule ON public.deposit_events USING btree (rule_id) WHERE rule_id IS NOT NULL;
-- A partial return of principal: part of what is held goes back to the customer while the rest stays held — the excess
-- over a cap. A full return is a refund or a release. An instalment received adds to what is held, up to the principal.
ALTER TABLE public.deposit_events DROP CONSTRAINT IF EXISTS deposit_events_type_check;
ALTER TABLE public.deposit_events ADD CONSTRAINT deposit_events_type_check
    CHECK ((event_type = ANY (ARRAY['posted'::text, 'instalment_received'::text, 'applied_to_balance'::text, 'interest_accrued'::text, 'interest_credited'::text,
                                    'principal_returned'::text, 'refund_initiated'::text, 'refunded'::text, 'released'::text])));
-- An accrual carries its period, rate, principal basis, the rate row and law row it used, and the core version. A return
-- may name the law row and core version that decided it ("no interest is owed" is a decision too). Nothing else carries any.
ALTER TABLE public.deposit_events DROP CONSTRAINT IF EXISTS deposit_events_accrual_fields_check;
ALTER TABLE public.deposit_events ADD CONSTRAINT deposit_events_accrual_fields_check
    CHECK ((((event_type = 'interest_accrued'::text) AND (period_start IS NOT NULL) AND (period_end IS NOT NULL) AND (period_end >= period_start)
             AND (rate_applied IS NOT NULL) AND (principal_basis IS NOT NULL) AND (principal_basis > (0)::numeric)
             AND (rate_id IS NOT NULL) AND (rule_id IS NOT NULL) AND (calculated_by IS NOT NULL) AND (calculated_by ~ '[[:alnum:]]'::text))
         OR ((event_type = ANY (ARRAY['refund_initiated'::text, 'refunded'::text, 'released'::text, 'principal_returned'::text]))
             AND (period_start IS NULL) AND (period_end IS NULL) AND (rate_applied IS NULL) AND (principal_basis IS NULL) AND (rate_id IS NULL)
             AND ((calculated_by IS NULL) OR (calculated_by ~ '[[:alnum:]]'::text)))
         OR ((event_type <> ALL (ARRAY['interest_accrued'::text, 'refund_initiated'::text, 'refunded'::text, 'released'::text, 'principal_returned'::text]))
             AND (period_start IS NULL) AND (period_end IS NULL) AND (rate_applied IS NULL)
             AND (principal_basis IS NULL) AND (rate_id IS NULL) AND (rule_id IS NULL) AND (calculated_by IS NULL))));
ALTER TABLE public.deposit_events DROP CONSTRAINT IF EXISTS deposit_events_return_due_check;
ALTER TABLE public.deposit_events ADD CONSTRAINT deposit_events_return_due_check
    CHECK (((return_due_id IS NULL) OR (event_type = ANY (ARRAY['principal_returned'::text, 'refund_initiated'::text, 'refunded'::text, 'released'::text]))));

-- The balance reads (-06), re-issued so a partial return leaves the remainder and the principal in force, and so what
-- is held is what was RECEIVED — the posted event and any instalments; for a deposit received whole that is the principal.
CREATE OR REPLACE FUNCTION public.deposit_balance(p_deposit_id uuid)
    RETURNS TABLE (principal numeric, applied numeric, remainder numeric, interest_accrued numeric, interest_credited numeric, days_held integer, accrued_through date, exhausted_on date)
    LANGUAGE sql STABLE
    SET search_path = public, pg_temp
    AS $$
    SELECT d.principal,
           coalesce((SELECT sum(e.amount) FROM public.deposit_events e WHERE e.deposit_id = d.id AND e.event_type = 'applied_to_balance'), 0),
           coalesce((SELECT sum(e.amount) FROM public.deposit_events e WHERE e.deposit_id = d.id AND e.event_type IN ('posted', 'instalment_received')), 0)
             - coalesce((SELECT sum(e.amount) FROM public.deposit_events e WHERE e.deposit_id = d.id AND e.event_type IN ('applied_to_balance', 'principal_returned')), 0),
           coalesce((SELECT sum(e.amount) FROM public.deposit_events e WHERE e.deposit_id = d.id AND e.event_type = 'interest_accrued'), 0),
           coalesce((SELECT sum(e.amount) FROM public.deposit_events e WHERE e.deposit_id = d.id AND e.event_type = 'interest_credited'), 0),
           (coalesce(d.refunded_on, d.released_on, CURRENT_DATE) - d.posted_on)::integer,
           (SELECT max(e.period_end) FROM public.deposit_events e WHERE e.deposit_id = d.id AND e.event_type = 'interest_accrued'),
           -- the first day on which what was applied or returned reached the principal (NULL while any remains)
           (SELECT min(x.effective_on) FROM (
                SELECT e.effective_on, sum(e.amount) OVER (ORDER BY e.effective_on, e.created_at, e.id) AS cum
                  FROM public.deposit_events e WHERE e.deposit_id = d.id AND e.event_type IN ('applied_to_balance', 'principal_returned')) x
             WHERE x.cum >= d.principal)
    FROM public.deposits d WHERE d.id = p_deposit_id
$$;
COMMENT ON FUNCTION public.deposit_balance(uuid) IS 'Derived from deposit_events (never stored): principal (the deposit required), applied to balance, remainder (received — at posting and by instalment — less applications and partial returns), interest accrued, interest credited, days held (to refund/release/today), accrued-through date, exhausted_on (the day applications and returns together reached the principal). v5.4.2-06; re-issued by v5.4.2-15.';

CREATE OR REPLACE FUNCTION public.deposit_principal_in_force(p_deposit_id uuid, p_on date) RETURNS numeric
    LANGUAGE sql STABLE
    SET search_path = public, pg_temp
    AS $$
    SELECT coalesce(sum(CASE WHEN e.event_type IN ('posted', 'instalment_received') THEN e.amount
                             WHEN e.event_type IN ('applied_to_balance', 'principal_returned') THEN -e.amount
                             ELSE 0 END), 0)
      FROM public.deposit_events e WHERE e.deposit_id = p_deposit_id AND e.effective_on <= p_on
$$;
COMMENT ON FUNCTION public.deposit_principal_in_force(uuid, date) IS 'Principal held on p_on: what was received (at posting and by instalment) less applications and partial returns, effective on or before that day (a plain read; which principal interest is owed on is the core''s). v5.4.2-06; re-issued by v5.4.2-15.';

CREATE OR REPLACE FUNCTION public.enforce_deposit_event() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    d public.deposits%ROWTYPE;
    b record;
    v_rate public.deposit_interest_rates%ROWTYPE;
    v_due record;
    v_held numeric;
    v_last_return date;
    v_last_type text;
    v_earned numeric;
    v_least numeric;
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
    -- A law row an event names is the deposit's own, or one of its key in force over the dates the event covers (B1): an
    -- accrual's period, a return's day. Locked shared, so a close of it waits.
    IF NEW.rule_id IS NOT NULL THEN
        PERFORM public.deposit_cite_rule(format('deposit %s', d.id), d.id, NEW.rule_id, coalesce(NEW.period_start, NEW.effective_on), coalesce(NEW.period_end, NEW.effective_on));
    END IF;
    -- A return that cites the due row it settles cites a live one of this deposit, of its kind — a partial return settles a
    -- due row with that amount, a refund or release one without — dated on or after it fell due.
    IF NEW.return_due_id IS NOT NULL THEN
        SELECT r.due_on, r.amount, r.deposit_id, EXISTS (SELECT 1 FROM public.deposit_return_due_withdrawals w WHERE w.due_id = r.id) AS withdrawn INTO v_due
          FROM public.deposit_return_due r WHERE r.id = NEW.return_due_id;
        IF NOT FOUND OR v_due.deposit_id <> d.id THEN
            RAISE EXCEPTION USING
                MESSAGE = format('deposit event rejected: return_due_id %s is not a due row of this deposit — an event cites its own deposit''s due row only (v5.4.2-15)', NEW.return_due_id),
                ERRCODE = 'check_violation';
        END IF;
        IF v_due.withdrawn THEN
            RAISE EXCEPTION USING
                MESSAGE = format('deposit event rejected: due row %s was withdrawn; a return cannot settle it (v5.4.2-15)', NEW.return_due_id),
                ERRCODE = 'check_violation';
        END IF;
        IF NOT public.deposit_return_due_is_live(NEW.return_due_id) THEN
            RAISE EXCEPTION USING
                MESSAGE = format('deposit event rejected: due row %s has already been settled by a partial return (v5.4.2-15)', NEW.return_due_id),
                ERRCODE = 'check_violation';
        END IF;
        IF (NEW.event_type = 'principal_returned') <> (v_due.amount IS NOT NULL)
           OR (NEW.event_type = 'principal_returned' AND NEW.amount <> v_due.amount) THEN
            RAISE EXCEPTION USING
                MESSAGE = format('deposit event rejected: due row %s is %s; a %s of %s does not settle it — the amount of a partial return is exactly the row''s, and a whole-remainder row is settled by a refund or a release (v5.4.2-15)', NEW.return_due_id,
                                 CASE WHEN v_due.amount IS NULL THEN 'a return of the whole remainder' ELSE format('a partial return of %s', v_due.amount) END,
                                 NEW.event_type, NEW.amount),
                ERRCODE = 'check_violation';
        END IF;
        IF NEW.effective_on < v_due.due_on THEN
            RAISE EXCEPTION USING
                MESSAGE = format('deposit event rejected: due row %s fell due %s; a %s settling it is dated %s, before then (v5.4.2-15)', NEW.return_due_id, v_due.due_on, NEW.event_type, NEW.effective_on),
                ERRCODE = 'check_violation';
        END IF;
    END IF;
    SELECT * INTO b FROM public.deposit_balance(d.id);
    -- Arithmetic, not law: money handed back on a day cannot have earned interest after that day.
    IF NEW.event_type IN ('principal_returned', 'refund_initiated', 'refunded', 'released')
       AND b.accrued_through IS NOT NULL AND NEW.effective_on <= b.accrued_through THEN
        RAISE EXCEPTION USING
            MESSAGE = format('deposit %s: interest is accrued through %s; a %s effective %s would say the money left while still earning (v5.4.2-15)', d.id, b.accrued_through, NEW.event_type, NEW.effective_on),
            ERRCODE = 'check_violation';
    END IF;

    CASE NEW.event_type
    WHEN 'posted' THEN
        IF pg_trigger_depth() < 2 THEN
            RAISE EXCEPTION USING MESSAGE = 'deposit event rejected: the posted event is written by the database when the deposit is inserted', ERRCODE = 'check_violation';
        END IF;
    WHEN 'instalment_received' THEN
        IF d.status = 'refund_pending' THEN
            RAISE EXCEPTION USING MESSAGE = format('deposit %s: a refund is pending — nothing more is received (v5.4.2-15)', d.id), ERRCODE = 'check_violation';
        END IF;
        IF NEW.amount <= 0 OR NEW.amount > d.principal - coalesce((SELECT sum(e.amount) FROM public.deposit_events e
                                                                     WHERE e.deposit_id = d.id AND e.event_type IN ('posted', 'instalment_received')), 0) THEN
            RAISE EXCEPTION USING
                MESSAGE = format('deposit %s: instalment_received must be > 0 and no more than the principal %s less what was already received (v5.4.2-15)', d.id, d.principal),
                ERRCODE = 'check_violation';
        END IF;
    WHEN 'applied_to_balance' THEN
        IF d.status = 'refund_pending' THEN
            RAISE EXCEPTION USING MESSAGE = format('deposit %s: a refund is pending — the remainder is committed to the customer; record the refund (or a new deposit)', d.id), ERRCODE = 'check_violation';
        END IF;
        IF NEW.amount <= 0 OR NEW.amount > b.remainder THEN
            RAISE EXCEPTION USING MESSAGE = format('deposit %s: applied_to_balance must be > 0 and ≤ the remainder %s', d.id, b.remainder), ERRCODE = 'check_violation';
        END IF;
        IF b.accrued_through IS NOT NULL AND NEW.effective_on <= b.accrued_through THEN
            RAISE EXCEPTION USING MESSAGE = format('deposit %s: interest has already accrued through %s on the principal then held; an application effective %s would change a settled period — apply it from %s', d.id, b.accrued_through, NEW.effective_on, b.accrued_through + 1), ERRCODE = 'check_violation';
        END IF;
    WHEN 'interest_accrued' THEN
        -- The record of the core's computation must be coherent: a law row of the deposit's key, a rate row of its tenant,
        -- state and service (and its category, or every category) in effect by the period's start, at that row's rate,
        -- inside the deposit's life and recorded after the period ends. WHICH rate row, whether interest is owed and how
        -- much are the core's.
        IF d.rule_id IS NULL THEN
            RAISE EXCEPTION USING
                MESSAGE = format('deposit %s is a carried legacy deposit: it cites no law row and accrues nothing here (v5.4.2-15)', d.id),
                ERRCODE = 'check_violation';
        END IF;
        SELECT * INTO v_rate FROM public.deposit_interest_rates r WHERE r.id = NEW.rate_id;
        IF v_rate.tenant_id IS DISTINCT FROM d.tenant_id OR v_rate.state_code IS DISTINCT FROM d.state_code
           OR v_rate.service_type IS DISTINCT FROM d.service_type
           OR NOT coalesce(v_rate.tariff_category IS NULL OR v_rate.tariff_category = d.tariff_category, false) THEN
            RAISE EXCEPTION USING
                MESSAGE = format('deposit %s: rate row %s is not this utility''s rate row for %s %s%s (v5.4.2-15)', d.id, NEW.rate_id, d.state_code, d.service_type, coalesce(' ' || d.tariff_category, ' (no category)')),
                ERRCODE = 'check_violation';
        END IF;
        -- Shared with the rate side's exclusive lock: a rate insert for this tenant, state and service waits for this
        -- accrual, then counts it.
        PERFORM pg_advisory_xact_lock_shared(public.deposit_rate_lock_key(v_rate.tenant_id, v_rate.state_code, v_rate.service_type));
        IF v_rate.effective_date > NEW.period_start THEN
            RAISE EXCEPTION USING
                MESSAGE = format('deposit %s: rate row %s takes effect %s, after the period starts (%s) (v5.4.2-15)', d.id, NEW.rate_id, v_rate.effective_date, NEW.period_start),
                ERRCODE = 'check_violation';
        END IF;
        IF NEW.rate_applied <> v_rate.annual_rate THEN
            RAISE EXCEPTION USING
                MESSAGE = format('deposit %s: rate_applied %s is not the cited row''s rate %s (v5.4.2-15)', d.id, NEW.rate_applied, v_rate.annual_rate),
                ERRCODE = 'check_violation';
        END IF;
        IF NEW.period_end >= NEW.effective_on THEN
            RAISE EXCEPTION USING MESSAGE = format('deposit %s: an accrual is recorded after the period it covers (period_end %s, effective_on %s)', d.id, NEW.period_end, NEW.effective_on), ERRCODE = 'check_violation';
        END IF;
        -- A period that has ended: today by the UTC date, which no session setting changes.
        IF NEW.period_end >= (now() AT TIME ZONE 'UTC')::date THEN
            RAISE EXCEPTION USING
                MESSAGE = format('deposit %s: an accrual period must have ended — period_end %s is not before today (UTC) (v5.4.2-15)', d.id, NEW.period_end),
                ERRCODE = 'check_violation';
        END IF;
        -- Arithmetic, not law, whichever is written first: no period spans a partial return or ends on or after a full
        -- one; no more is earned on than was held throughout the period — which also means nothing earns before posting
        -- or from the day the principal was used up, when nothing is held.
        SELECT e.effective_on, e.event_type INTO v_last_return, v_last_type FROM public.deposit_events e
         WHERE e.deposit_id = d.id
           AND ((e.event_type IN ('refund_initiated', 'refunded', 'released') AND e.effective_on <= NEW.period_end)
             OR (e.event_type = 'principal_returned' AND e.effective_on BETWEEN NEW.period_start AND NEW.period_end))
         ORDER BY e.effective_on DESC LIMIT 1;
        IF v_last_return IS NOT NULL THEN
            RAISE EXCEPTION USING
                MESSAGE = format('deposit %s: money was returned (%s) on %s; an accrual for %s..%s would say it earned while it was leaving (v5.4.2-15)', d.id, v_last_type, v_last_return, NEW.period_start, NEW.period_end),
                ERRCODE = 'check_violation';
        END IF;
        SELECT min(public.deposit_principal_in_force(d.id, x.day)) INTO v_held
          FROM (SELECT NEW.period_start AS day
                UNION SELECT e.effective_on FROM public.deposit_events e
                 WHERE e.deposit_id = d.id AND e.effective_on BETWEEN NEW.period_start AND NEW.period_end) x;
        IF NEW.principal_basis > v_held THEN
            RAISE EXCEPTION USING
                MESSAGE = format('deposit %s: principal_basis %s exceeds the least held over %s..%s (%s) (v5.4.2-15)', d.id, NEW.principal_basis, NEW.period_start, NEW.period_end, v_held),
                ERRCODE = 'check_violation';
        END IF;
    WHEN 'interest_credited' THEN
        -- Only interest already earned: accrued for periods ending before the credit's date, less what was credited.
        SELECT coalesce(sum(e.amount), 0) INTO v_earned FROM public.deposit_events e
         WHERE e.deposit_id = d.id AND e.event_type = 'interest_accrued' AND e.period_end < NEW.effective_on;
        IF NEW.amount <= 0 OR NEW.amount > v_earned - b.interest_credited THEN
            RAISE EXCEPTION USING MESSAGE = format('deposit %s: interest_credited must be > 0 and ≤ the interest earned (accrued for periods ending before %s), less credited: %s', d.id, NEW.effective_on, v_earned - b.interest_credited), ERRCODE = 'check_violation';
        END IF;
    WHEN 'principal_returned' THEN
        -- Part of the principal goes back; the rest stays held.
        IF d.status = 'refund_pending' THEN
            RAISE EXCEPTION USING MESSAGE = format('deposit %s: a refund is pending — the remainder is committed to the customer', d.id), ERRCODE = 'check_violation';
        END IF;
        IF NEW.amount <= 0 OR NEW.amount >= b.remainder THEN
            RAISE EXCEPTION USING
                MESSAGE = format('deposit %s: principal_returned must be > 0 and < the remainder %s — returning all of it is a refund or a release (v5.4.2-15)', d.id, b.remainder),
                ERRCODE = 'check_violation';
        END IF;
    WHEN 'refund_initiated' THEN
        IF d.status = 'refund_pending' THEN
            RAISE EXCEPTION USING MESSAGE = format('deposit %s: a refund is already pending', d.id), ERRCODE = 'check_violation';
        END IF;
        IF NEW.amount <> b.remainder THEN
            RAISE EXCEPTION USING MESSAGE = format('deposit %s: refund_initiated amount must be the remainder %s (interest is credited separately and disclosed separately — table #54 rule 7)', d.id, b.remainder), ERRCODE = 'check_violation';
        END IF;
    WHEN 'refunded', 'released' THEN
        IF NEW.event_type = 'refunded' AND d.instrument <> 'cash' THEN
            RAISE EXCEPTION USING MESSAGE = format('deposit %s is a %s: a non-cash instrument is released, not refunded', d.id, d.instrument), ERRCODE = 'check_violation';
        END IF;
        IF NEW.event_type = 'released' AND d.instrument = 'cash' THEN
            RAISE EXCEPTION USING MESSAGE = format('deposit %s is cash: cash is refunded, not released', d.id), ERRCODE = 'check_violation';
        END IF;
        IF NEW.amount <> b.remainder THEN
            RAISE EXCEPTION USING MESSAGE = format('deposit %s: the %s amount must be the remainder %s (apply to balance first; interest is a separate movement; a fully applied deposit is settled by a zero refund)', d.id, NEW.event_type, b.remainder), ERRCODE = 'check_violation';
        END IF;
        -- The last event closes the ledger: nothing accrued may be left uncredited, since no event can follow.
        IF b.interest_credited <> b.interest_accrued THEN
            RAISE EXCEPTION USING
                MESSAGE = format('deposit %s: %s of accrued interest is uncredited; credit it before the %s event, which is the deposit''s last (v5.4.2-15)', d.id, b.interest_accrued - b.interest_credited, NEW.event_type),
                ERRCODE = 'check_violation';
        END IF;
        -- A carried legacy deposit's interest is settled outside this ledger (legacy_interest_earned); its return says how.
        IF d.rule_id IS NULL AND b.interest_accrued = 0 AND (NEW.reason IS NULL OR NEW.reason !~ '[[:alnum:]]') THEN
            RAISE EXCEPTION USING
                MESSAGE = format('deposit %s is a legacy deposit with no accrual history: its return requires a reason stating how its interest was settled (legacy_interest_earned = %s)', d.id, coalesce(d.legacy_interest_earned, 0)),
                ERRCODE = 'check_violation';
        END IF;
    END CASE;
    -- Arithmetic, not law, on the effective-date timeline: money cannot leave before it arrived. An application or a partial
    -- return leaves the principal held non-negative on its own day and on every later day an event is recorded for (the
    -- undated remainder above would let a later instalment fund an earlier return); a refund, release or refund notice
    -- is dated on or after every receipt and every application or return already recorded.
    IF NEW.event_type IN ('applied_to_balance', 'principal_returned') THEN
        SELECT min(public.deposit_principal_in_force(d.id, x.day)) INTO v_least
          FROM (SELECT NEW.effective_on AS day
                UNION SELECT e.effective_on FROM public.deposit_events e
                 WHERE e.deposit_id = d.id AND e.effective_on > NEW.effective_on) x;
        IF NEW.amount > v_least THEN
            RAISE EXCEPTION USING
                MESSAGE = format('deposit %s: a %s of %s effective %s would leave a negative principal held on some day from then (least held %s) — money cannot leave before it was received (v5.4.2-15)', d.id, NEW.event_type, NEW.amount, NEW.effective_on, v_least),
                ERRCODE = 'check_violation';
        END IF;
    ELSIF NEW.event_type IN ('refund_initiated', 'refunded', 'released') THEN
        IF EXISTS (SELECT 1 FROM public.deposit_events e
                    WHERE e.deposit_id = d.id AND e.effective_on > NEW.effective_on
                      AND e.event_type IN ('posted', 'instalment_received', 'applied_to_balance', 'principal_returned')) THEN
            RAISE EXCEPTION USING
                MESSAGE = format('deposit %s: a %s effective %s precedes a receipt, application or return already recorded — the whole remainder goes back on or after the last of them (v5.4.2-15)', d.id, NEW.event_type, NEW.effective_on),
                ERRCODE = 'check_violation';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;
COMMENT ON FUNCTION public.enforce_deposit_event() IS
    'v5.4.2-06, re-issued by v5.4.2-15. The deposit sub-ledger''s integrity: locks the deposit row (so events, due rows and withdrawals serialise); tenant, actor, dates, ledger link; nothing after refunded / released; the posted event is the database''s; a law row an event names is the deposit''s own or one of its key in force over the event''s dates, locked shared (deposit_cite_rule); an instalment received not while a refund is pending and within the principal less what was received; applications within the remainder, not while a refund is pending, not into an accrued period; an accrual cites a rate row of its tenant, state and service and (or every) category in effect by the period''s start, at that rate, takes the shared rate lock, ends before today (UTC) and before any full return, spans no partial return, on no more than the least held over the period, recorded after the period; credits within interest earned (accrued for periods ending before the credit) less credited; a partial return below the remainder; no return dated inside an accrued period; one pending refund; full returns of exactly the remainder, cash refunded and non-cash released, leaving nothing accrued uncredited; a legacy return without accruals states how its interest was settled; a cited return-due row is a live one of this deposit, of the event''s kind (a partial return settles a due row with exactly its amount), and the event is dated on or after it fell due. Decides no law: whether interest is owed, at which rate row, over which periods and in what amount are the core''s.';

COMMENT ON TABLE public.deposit_events IS
    'CI-125 / CI-130 / CI-131 (v5.4.2-06; v5.4.2-15): the append-only deposit sub-ledger. posted (written by the database at deposit insert, for what was received then), instalment_received, applied_to_balance, interest_accrued (period, rate, principal basis and amount as the core computed them, citing the utility rate row (rate_id), the deposit''s law row (rule_id) and the core version (calculated_by); periods never overlap), interest_credited (≤ accrued for periods ended − credited), principal_returned (part of what is held; may settle a partial return-due row), refund_initiated, refunded (cash) / released (non-cash) — of the remainder, leaving nothing accrued uncredited, optionally citing the return-due row they settle (return_due_id). deposits.status is projected from these. Optional link to the account_ledger row that moved the money.';

-- The status projection (-06), re-issued: an instalment received after the remainder was applied to nothing leaves a
-- remainder again, so an applied deposit is partially applied once more.
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
                        WHEN 'instalment_received' THEN CASE WHEN d.status = 'applied' THEN 'partial_applied' ELSE d.status END
                        ELSE d.status END,
           refunded_on = CASE WHEN NEW.event_type = 'refunded' THEN NEW.effective_on ELSE d.refunded_on END,
           released_on = CASE WHEN NEW.event_type = 'released' THEN NEW.effective_on ELSE d.released_on END
     WHERE d.id = NEW.deposit_id;
    RETURN NULL;
END;
$$;
COMMENT ON FUNCTION public.project_deposit_status() IS
    'v5.4.2-06, re-issued by v5.4.2-15. AFTER INSERT on deposit_events: projects deposits.status, refunded_on and released_on from the event — an instalment received turns an applied deposit back to partially applied.';


-- ----------------------------------------------------------------------------
-- 13. The -06 Texas law and the refund-due view leave
-- ----------------------------------------------------------------------------
DROP VIEW IF EXISTS public.deposits_refund_due;
DROP FUNCTION IF EXISTS public.deposit_refund_trigger_state(uuid);
DROP FUNCTION IF EXISTS public.deposit_accrual_amount(numeric, numeric, date, date);
DROP FUNCTION IF EXISTS public.deposit_interest_rate_as_of(uuid, date);



-- ----------------------------------------------------------------------------
-- 14. Words, and the tail
-- ----------------------------------------------------------------------------
COMMENT ON COLUMN public.deposit_waiver_determinations.waiver_class IS
    'A waiver class of a state and service (deposit_waiver_classes); empty of rows at v5.4.2-15 (the precondition) and untouched by it. A determination that cites a utility''s own tariff ground waits for the tariff document''s waivers (residual R6).';

DO $$
BEGIN
    PERFORM public.assert_core_role_invariants();
    PERFORM public.assert_rule_table_invariants();
    PERFORM public.assert_tenant_isolation_invariants();
    RAISE NOTICE 'v5.4.2-15: deposit_rules (% rows) and deposit_tariffs are registered; the table-level invariants hold.', (SELECT count(*) FROM public.deposit_rules);
END
$$;


-- ----------------------------------------------------------------------------
-- 15. Residuals, stated
-- ----------------------------------------------------------------------------
-- R1. THE DATABASE NO LONGER DECIDES DEPOSIT LAW. An application that takes a
--     deposit a waiver forbids, sets a cap the document does not support,
--     accrues the wrong interest or never records a due return is not refused
--     here — by design (Ryan, 2026-09-28). The records show it: every deposit,
--     accrual and due row cites its law row and core version. The core's rules
--     and their boundary cases: application/deposits-rules-for-the-core.md.
--
-- R2. ONLY TEXAS GAS IS SEEDED. A premise in another state, or another service,
--     has no law row; the core must refuse, never fall back. No published
--     deposit interest rate is seeded (tx_deposit_interest_rate has no values):
--     each is entered from its publication by a reviewed migration, and until
--     one is in force on a date a utility's own rate row for that date is
--     refused (unknown law is not permission).
--
-- R3. A LAW ROW IS NEVER EDITED — for the owner too. A row wrong from its first
--     day is repaired by a reviewed platform migration that disables the guard
--     for that statement.
--
-- R4. A CLOSE RACING A NEW CITATION. The template's handshake holds: a citing
--     record takes the law row's lock shared (deposit_cite_rule) and a close
--     takes it exclusive before reading the floor. A deposit's own row is
--     locked but not required in force after its close: the old law stays the law
--     that GOVERNS a deposit decided under it (Ryan, B1, 2026-10-02: "grandfathered"),
--     while a successor reaches deposits already held only for the dates it is in
--     force. A close floor can therefore rise above the row's own end; that is the
--     citations, not a defect.
--
-- R11. A PARTIAL RETURN NEEDS NO DUE ROW. principal_returned may be recorded without
--     one, as a voluntary refund may: part of a held deposit goes back by agreement or
--     correction. When it cites a due row it must be exactly that row's amount.
--
-- R5. WHO WRITES THE RECORD TABLES. The tests write deposits, events and due
--     rows as tally_app. The grant pattern says core-only later; this patch
--     leaves the existing grants as they were.
--
-- R6. WAIVER DETERMINATIONS. deposit_waiver_determinations is untouched: empty
--     by the precondition, with no state or service columns and no link to the
--     utility's own tariff waiver grounds, which are now in the tariff document.
--     Its rewrite waits for a core that records determinations.
--
-- R7. THE COMPARATOR'S LIMITS. deposit_tariff_compare compares months of billing
--     with the law's cap converted to months, and a trigger the law also names
--     (a ratio or a count of the same measure, the days to pay). A flat amount,
--     a cap of fixed dollars, highest bills or seasonal averages, a combined
--     condition, waivers and instalments are not compared when written (months of the
--     highest bill, a minimum amount and a cap the law has not ruled on are refused
--     rather than passed). Of the law's guards on a trigger it names, days to pay is
--     compared as a number and the others (service age, a recent move, notice, a
--     cure) must be carried identically; waivers and instalments are not compared. A
--     trigger is matched by code and by what it measures (a usage ratio, an event
--     count), so another code does not hide it. A flat amount is held at each deposit:
--     the statutory cap's part and the figure it came from are recorded, and the cap
--     that applied may not exceed the part's figure (a lesser-of cap, the least figure
--     computable from the one basis recorded); under a delegation the cap may not
--     exceed the tariff's own amount (a flat amount, or months of the monthly billing
--     recorded). Under a law cap in highest bills or in a seasonal average, nothing
--     converts: a months tariff is neither compared when written nor held at the deposit.
--     A tariff condition combining the law's measure with another (an all-of that is
--     in fact stricter) is refused as incomparable, and so is a longer notice than the
--     law's: version 1 fails toward refusal where it cannot show a tariff no looser. A
--     later change in the law that makes a tariff looser is a core audit finding, never
--     a refusal of the law.
--
-- R8. EVIDENCE IS REQUIRED, NOT COMPLETE. The database checks that a due row has
--     evidence and that each row is of the right customer, kind and period. Whether
--     the core cited every bill it counted is the core's. A clean bill history
--     that counts months rather than bills rests on bills, as one that counts
--     bills does; the document's `measure` is the core's.
--
-- R9. THE PREMISE IS NOT RECORDED. A deposit records the state it was decided
--     under, not the service location that state came from. It waits for the
--     places table.
--
-- R10. SIX SHAPES ARE REFUSED ON PURPOSE (design doc §4): a cap add-on and a sum
--     cap, bill-anchored instalments, guarantor caps, municipal funds,
--     post-discharge recalculation, periodic two-way recalculation. The schema
--     refuses them rather than dropping them.
-- R12. THE APPLICATION CONTRACTS FOLLOW THE MIRROR. application/APPLICATION-CONTRACTS.md
--     AC-24 and AC-25 describe the -06 database (deposit_refund_trigger_state,
--     deposit_interest_rate_as_of, deposit_accrual_amount, deposits_refund_due), which
--     this patch drops. They describe what the mirrored database does today, so they are
--     rewritten in the commit that mirrors this patch into tu.sql, not before.
-- ============================================================================
-- END PATCH v5.4.2-15
-- ============================================================================

COMMIT;
\endif
