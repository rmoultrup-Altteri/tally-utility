-- ============================================================================
-- PATCH v5.4.2-25 — wave 3, part 1: disputes. The dispute rule family (law
--                    and the utility's own tariff) and the dispute record
-- ============================================================================
-- Authority:   Ryan, 2026-10-18: "start the wave-3 inventory"; wave-3 Q1 "go
--              with the rule entries" (dispute policies are rule-terms rows,
--              one law table and one tariff table); "go ahead with the tests";
--              "go ahead with the patch". Rulings K-07 (a city's rules per
--              utility, no default), K-CCK (fail toward protection), K-A2
--              (7.45(6)(D)(ii) shelter), R-05 (add-only). Invariants CI-074,
--              CI-054 (the dispute side).
-- Spec:        application/wave3-build-2026-10-18/v5.4.2-25-design.md (L, D,
--              T; "Tests as written") and source-inventory-wave3.md (D, Q1).
-- Builds on:   v5.4.2-23 (invoices' (id, tenant_id, customer_id) key,
--              cash_coordinates_required) and v5.4.2-17 (the rule-terms
--              template). Mirrors only after -23.
-- Migration:   additive, plus two meaning changes (T1, T2) on rows that are
--              empty everywhere; a database holding them stops at the
--              precondition, naming the row, before anything is written.
--
-- ----------------------------------------------------------------------------
-- What changes
-- ----------------------------------------------------------------------------
--   The dispute law family (L1-L7; Q1)
--   * Vocabularies, platform-held: dispute_customer_classes (Texas gas:
--     protected, unprotected — 16 TAC 7.45's reach), dispute_subjects,
--     dispute_blocks, dispute_duties.
--   * dispute_rules: a law table, kind dispute v1, key customer_class; five
--     facets (subject_codes, excluded_subject_codes, block_codes, stage_ids,
--     must_pay_ids). The document: subjects, shelter_earned, must_pay (a
--     strategy with a component id), shelter_ends, stages, blocks, duties,
--     each with its citation; absent never means none. Seeded from
--     law/dispute/dispute_rules.yaml: Texas gas investor-owned and
--     cooperative, protected (7.45(6)(D)) and unprotected (no shelter,
--     written down); city-owned, a delegation per class (K-07).
--   * dispute_tariffs: the utility's own policy, kind dispute_tariff v1,
--     key [] (one per utility, state, service, system and dates), the same
--     sections; never looser than the law in force when written (L6). No
--     default row (K-07).
--   * Insert checks on both: a subject both listed and excluded [L2a], a
--     code listed twice [L2b], a filing deadline from a prior decision on
--     the first stage [L2c], a final stage that is not the last [L2d], a
--     duty or class not in its vocabulary (23503).
--
--   The dispute record (D1-D6)
--   * disputes: tenant, customer, an issued bill (composite FK) or a reading
--     at the customer's location, or both; subject, received_on, channel.
--     Born open; the database moves the status (open -> resolved |
--     withdrawn) from the resolution or withdrawal event, naming it
--     (status_cause_id) at its stamp (status_recorded_at). Identity is
--     write-once; the application inserts only.
--   * dispute_amounts (add-only): the amount, who determined it, from when;
--     optional dispute_amount_lines on the dispute's own bill, each at most
--     its line's charge, summing to the amount at commit. A revision is a
--     new row.
--   * dispute_determinations (add-only): the core's reading of the shelter,
--     written by tally_app with calculated_by when the answer changes. The
--     database checks the record, not the evaluation: the law row is the one
--     in force for the utility, the class and the received date [D4a]; the
--     tariff is the utility's own [D4f], in force [D4c]; a delegation
--     shelters only under a tariff [D4d], and says "no terms" only when none
--     is in force [D4e]; outcome shapes [D4n]; the component [D4g] and blocks
--     [D4h] are the cited document's; amounts [D4i]; one live row per
--     dispute [D4m]; none after the resolution [D4k].
--   * dispute_events (add-only): opened (the database's, with the dispute),
--     stage_entered and decided (a stage of the live determination's
--     document, its decider), escalated, resolved (sustained | adjusted |
--     waived; adjusted names one correction of the customer's), withdrawn.
--     One resolution or withdrawal per dispute.
--   * Readers dispute_shelter_as_of(invoice, on, recorded) and
--     dispute_line_shelter_as_of(line, on, recorded); both coordinates
--     required. The shelter ends at the resolution or withdrawal date and
--     after shelter_ends_on: nothing has to be reset (CI-074).
--
--   The two meaning changes (T1, T2)
--   * pending_dispute stops protecting the account and takes no new
--     enrollment: a dispute is a disputes row.
--   * meter_readings.dispute_* (six columns) go. A reading's status
--     'disputed' needs an open dispute naming it, and stays while one does.
--
-- ----------------------------------------------------------------------------
-- Lock order and isolation (a rule)
-- ----------------------------------------------------------------------------
--   A dispute's records share one mutex, the dispute's advisory lock
--   (dispute_lock). A write takes, in this order:
--     1. its dispute's lock (an amount, a determination, an event other than
--        the database's opened; a reading's move into or out of 'disputed'
--        takes the lock of every dispute naming the reading, in id order);
--     2. for a determination, the cited law row's lock, then the cited
--        tariff row's (both shared, rule_row_cite);
--     3. nothing else.
--   A rule row's close takes its own lock exclusive (-17) and reads the
--   citations after it, so a close and a citation cannot cross. Every write
--   that takes a dispute's lock runs at READ COMMITTED (25000 otherwise): it
--   must see what the writer it waited for committed. Writers retry 40P01.
--
-- ----------------------------------------------------------------------------
-- Residuals (left on purpose)
-- ----------------------------------------------------------------------------
--   R1. Gov't Code 2251 (governmental payers): no governmental class yet;
--       its document is a test fixture only.
--   R2. PA 56.22(c) (no late fee on a disputed estimated bill) is
--       conditional and not expressible in v1; out of scope shapes are
--       refused by the schema.
--   R3. What the core decides: the customer's class, whether a dispute
--       earned the shelter, the amounts, the figures behind them, and
--       whether a city with no policy still owes Craft due process (a
--       no_terms determination shelters nothing in the record).
--   R4. A stage event's decider is checked against the stage's decider
--       category, not the user's own role.
--   R5. A reading-only dispute has no reader: its shelter is read from its
--       determinations directly until a bill names it.
--   R6. "No terms" is checked against the tariff in force when it is
--       written; a tariff written later for the same date (a back-dated
--       policy) is the core's audit finding.
--   R7. The status move is a SECURITY DEFINER trigger function owned by the
--       migration's role: tally_app holds no UPDATE on disputes, and the
--       move it makes is checked against its event (enforce_dispute_update).
--       A trigger function cannot be called directly.
--
-- Tests. battery-25 (201 checks), races/disputes-25.sh (DR1-DR9, 12 results),
--   terms-25.py, migration-25.py (P0-P4), mutations-25.py (110 of 110 caught).
--
-- PRECONDITION. v5.4.2-23 applied. No meter reading carries the old dispute
--   notes or status 'disputed', and no customer is enrolled in
--   pending_dispute. Applied by a superuser, under READ COMMITTED. A second
--   run finds disputes and skips the whole patch (psql's \if).
-- ============================================================================

SELECT to_regclass('public.disputes') IS NOT NULL AS already \gset
\if :already
DO $$ BEGIN RAISE NOTICE 'v5.4.2-25: already applied (disputes exists); nothing to do'; END $$;
\else
BEGIN;

-- The old dispute state is not converted (Ryan 2026-09-28: nothing is live):
-- a database holding it stops here, naming the row, so the operator decides.
DO $$
DECLARE
    v_id uuid;
BEGIN
    SELECT r.id INTO v_id FROM public.meter_readings r
     WHERE r.dispute_reason IS NOT NULL OR r.dispute_raised_by IS NOT NULL OR r.dispute_raised_at IS NOT NULL
        OR r.dispute_resolved_by IS NOT NULL OR r.dispute_resolved_at IS NOT NULL OR r.dispute_resolution_notes IS NOT NULL
     ORDER BY r.id LIMIT 1;
    IF v_id IS NOT NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('v5.4.2-25 drops meter_readings.dispute_* (a dispute is a disputes row): reading %s carries dispute notes. Record them as a dispute first (DEPLOY-VERIFICATION -25)', v_id),
            ERRCODE = 'object_not_in_prerequisite_state';
    END IF;
    SELECT r.id INTO v_id FROM public.meter_readings r WHERE r.status = 'disputed' ORDER BY r.id LIMIT 1;
    IF v_id IS NOT NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('v5.4.2-25: a disputed reading needs an open disputes row naming it, which this patch will not invent: reading %s is in status disputed. Record its dispute first (DEPLOY-VERIFICATION -25)', v_id),
            ERRCODE = 'object_not_in_prerequisite_state';
    END IF;
    SELECT e.id INTO v_id FROM public.customer_program_enrollments e WHERE e.program_type = 'pending_dispute' ORDER BY e.id LIMIT 1;
    IF v_id IS NOT NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('v5.4.2-25 makes pending_dispute non-protective (a dispute is a disputes row): enrollment %s would silently lose its protection. Record its dispute first (DEPLOY-VERIFICATION -25)', v_id),
            ERRCODE = 'object_not_in_prerequisite_state';
    END IF;
END $$;


-- ----------------------------------------------------------------------------
-- 1. The vocabularies (L2, L3)
-- ----------------------------------------------------------------------------
-- The classes a state's dispute law distinguishes (Texas gas: 16 TAC 7.45's
-- reach, as backbilling_customer_classes). Which class a customer is in is
-- the core's to decide; a determination records it.
CREATE TABLE public.dispute_customer_classes (
    state_code      text NOT NULL,
    service_type    text NOT NULL,
    class_code      text NOT NULL,
    description     text NOT NULL,
    source_note     text NOT NULL,
    created_at      timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT dispute_customer_classes_pkey PRIMARY KEY (state_code, service_type, class_code),
    CONSTRAINT dispute_customer_classes_state_code_check CHECK (state_code ~ '^[A-Z]{2}$'),
    CONSTRAINT dispute_customer_classes_service_type_check
        CHECK (service_type = ANY (ARRAY['water', 'sewer', 'electric', 'gas', 'stormwater', 'trash', 'reclaimed_water'])),
    CONSTRAINT dispute_customer_classes_code_check CHECK (class_code ~ '^[a-z][a-z0-9_]*$'),
    CONSTRAINT dispute_customer_classes_description_check CHECK (description ~ '[[:alnum:]]'),
    CONSTRAINT dispute_customer_classes_source_note_check CHECK (source_note ~ '[[:alnum:]]')
);
INSERT INTO public.dispute_customer_classes (state_code, service_type, class_code, description, source_note) VALUES
    ('TX', 'gas', 'protected',   'Residential and small commercial customers: the customers the dispute shelter of 16 TAC 7.45(6)(D) protects',
     '16 TAC 7.45(1), 7.45(6)(D)'),
    ('TX', 'gas', 'unprotected', 'Every other customer (large commercial, industrial): 16 TAC 7.45''s dispute shelter does not reach them',
     '16 TAC 7.45(1)');
COMMENT ON TABLE public.dispute_customer_classes IS
    'v5.4.2-25 (L1). The customer classes a state''s dispute law distinguishes, per (state, service): dispute_rules is keyed by them, and a determination records the class the core placed the customer in. Texas gas: protected (residential and small commercial, 16 TAC 7.45(6)(D)) and unprotected. Platform-held; never edited or deleted.';

CREATE TABLE public.dispute_subjects (
    subject_code    text NOT NULL,
    description     text NOT NULL,
    created_at      timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT dispute_subjects_pkey PRIMARY KEY (subject_code),
    CONSTRAINT dispute_subjects_code_check CHECK (subject_code ~ '^[a-z][a-z0-9_]*$'),
    CONSTRAINT dispute_subjects_description_check CHECK (description ~ '[[:alnum:]]')
);
INSERT INTO public.dispute_subjects (subject_code, description) VALUES
    ('meter_accuracy',                'The meter registered wrongly'),
    ('rate_application',              'The wrong rate or schedule was applied'),
    ('calculation',                   'The bill was calculated wrongly'),
    ('service_not_rendered',          'The service billed was not rendered'),
    ('identity_theft',                'The account was opened or used in the customer''s name without consent'),
    ('responsible_party',             'Someone else is responsible for the charges'),
    ('deposit',                       'A deposit demanded or held'),
    ('credit',                        'A credit decision or credit reporting'),
    ('ability_to_pay',                'The customer cannot pay (not a dispute of the bill itself)'),
    ('tamper_finding',                'A finding of tampering or theft of service'),
    ('consumption_on_accurate_meter', 'High consumption on a meter that tested accurate'),
    ('other',                         'Any other subject');
COMMENT ON TABLE public.dispute_subjects IS
    'v5.4.2-25 (L2). What a dispute may be about: the grounds a dispute names (disputes.subject) and the subjects a rule lists or excludes (the facets subject_codes, excluded_subject_codes). Platform-held; never edited or deleted.';

CREATE TABLE public.dispute_blocks (
    block_code      text NOT NULL,
    description     text NOT NULL,
    created_at      timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT dispute_blocks_pkey PRIMARY KEY (block_code),
    CONSTRAINT dispute_blocks_code_check CHECK (block_code ~ '^[a-z][a-z0-9_]*$'),
    CONSTRAINT dispute_blocks_description_check CHECK (description ~ '[[:alnum:]]')
);
INSERT INTO public.dispute_blocks (block_code, description) VALUES
    ('notice_issue',         'No disconnection notice is issued for the sheltered amount'),
    ('disconnect_order',     'No disconnection is ordered for the sheltered amount'),
    ('disconnect_execute',   'No disconnection is carried out for the sheltered amount'),
    ('late_fee',             'No late fee accrues on the sheltered amount'),
    ('collections_referral', 'The sheltered amount is not referred to collections'),
    ('credit_reporting',     'The sheltered amount is not reported to a credit bureau');
COMMENT ON TABLE public.dispute_blocks IS
    'v5.4.2-25 (L2). What a dispute''s shelter stops (the facet block_codes; a determination''s blocks). Platform-held; never edited or deleted.';

CREATE TABLE public.dispute_duties (
    duty_code       text NOT NULL,
    description     text NOT NULL,
    created_at      timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT dispute_duties_pkey PRIMARY KEY (duty_code),
    CONSTRAINT dispute_duties_code_check CHECK (duty_code ~ '^[a-z][a-z0-9_]*$'),
    CONSTRAINT dispute_duties_description_check CHECK (description ~ '[[:alnum:]]')
);
INSERT INTO public.dispute_duties (duty_code, description) VALUES
    ('investigate',               'The utility investigates the dispute'),
    ('report_result',             'The utility reports the result to the customer'),
    ('inform_complaint_route',    'The utility tells the customer how to complain to the regulator'),
    ('offer_payment_arrangement', 'The utility offers a payment arrangement');
COMMENT ON TABLE public.dispute_duties IS
    'v5.4.2-25 (L2). What the utility must do on a dispute (a document''s duties, checked by the insert checks). Platform-held; never edited or deleted.';

DO $$
DECLARE
    t text;
BEGIN
    FOREACH t IN ARRAY ARRAY['dispute_customer_classes', 'dispute_subjects', 'dispute_blocks', 'dispute_duties'] LOOP
        EXECUTE format('CREATE TRIGGER append_only BEFORE DELETE OR UPDATE ON public.%I FOR EACH ROW EXECUTE FUNCTION public.enforce_append_only()', t);
        EXECUTE format('ALTER TABLE public.%I ENABLE ALWAYS TRIGGER append_only', t);
        EXECUTE format('CREATE TRIGGER no_truncate BEFORE TRUNCATE ON public.%I FOR EACH STATEMENT EXECUTE FUNCTION public.enforce_no_hard_delete()', t);
        EXECUTE format('ALTER TABLE public.%I ENABLE ALWAYS TRIGGER no_truncate', t);
        EXECUTE format('REVOKE ALL ON public.%I FROM PUBLIC, tally_app, tally_core', t);
        EXECUTE format('GRANT SELECT ON public.%I TO tally_app, tally_core', t);
    END LOOP;
END $$;


-- ----------------------------------------------------------------------------
-- 2. The kinds (L2, L3, L5)
-- ----------------------------------------------------------------------------
-- In one DO block: a kind's facets are declared in its own transaction's
-- block, as -15 and -23 did. The schema texts are the committed files,
-- embedded verbatim; CI compares them (lawfiles W4).
DO $kinds$
BEGIN
    INSERT INTO public.rule_term_schemas (terms_kind, terms_version, rule_role, json_schema, introduced_on, description, source_note)
    VALUES ('dispute', 1, 'law', $schema${
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://tally-utility/law/dispute/dispute.v1.schema.json",
  "title": "Dispute rule, version 1",
  "description": "What a state's law says about a customer's dispute of a bill or a reading, for one customer class: what may be disputed, when a dispute earns protection, what the customer must still pay while protected, when the protection ends, the review stages, what the protection stops and the utility's duties. Every section is written: absent never means none, so an empty list or an explicit unruled is written, each with its citation. Every law kind also admits the document 'the law leaves this to the utility'. The core evaluates the document; the database stores it and checks the records that cite it.",
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
    "codes": {
      "type": "array",
      "items": {
        "$ref": "#/$defs/code"
      },
      "maxItems": 32
    },
    "id": {
      "type": "string",
      "pattern": "^[a-z][a-z0-9_]*$"
    },
    "version": {
      "type": "integer",
      "minimum": 1,
      "maximum": 1
    },
    "days": {
      "type": "integer",
      "minimum": 1,
      "maximum": 3650
    },
    "subjects": {
      "oneOf": [
        {
          "$ref": "#/$defs/subjects_any"
        },
        {
          "$ref": "#/$defs/subjects_listed"
        }
      ]
    },
    "subjects_any": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "kind",
        "excluded",
        "citation"
      ],
      "properties": {
        "kind": {
          "type": "string",
          "const": "any"
        },
        "excluded": {
          "$ref": "#/$defs/codes"
        },
        "citation": {
          "$ref": "#/$defs/citation"
        }
      }
    },
    "subjects_listed": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "kind",
        "codes",
        "excluded",
        "citation"
      ],
      "properties": {
        "kind": {
          "type": "string",
          "const": "listed"
        },
        "codes": {
          "type": "array",
          "items": {
            "$ref": "#/$defs/code"
          },
          "minItems": 1,
          "maxItems": 32
        },
        "excluded": {
          "$ref": "#/$defs/codes"
        },
        "citation": {
          "$ref": "#/$defs/citation"
        }
      }
    },
    "shelter_earned": {
      "oneOf": [
        {
          "$ref": "#/$defs/earned_any_time"
        },
        {
          "$ref": "#/$defs/earned_before_termination"
        },
        {
          "$ref": "#/$defs/earned_before_delinquency"
        },
        {
          "$ref": "#/$defs/earned_within_days"
        },
        {
          "$ref": "#/$defs/earned_on_regulator_complaint"
        },
        {
          "$ref": "#/$defs/earned_unruled"
        }
      ]
    },
    "earned_any_time": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "kind",
        "citation"
      ],
      "properties": {
        "kind": {
          "type": "string",
          "const": "any_time"
        },
        "citation": {
          "$ref": "#/$defs/citation"
        }
      }
    },
    "earned_before_termination": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "kind",
        "citation"
      ],
      "properties": {
        "kind": {
          "type": "string",
          "const": "before_termination"
        },
        "citation": {
          "$ref": "#/$defs/citation"
        }
      }
    },
    "earned_before_delinquency": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "kind",
        "citation"
      ],
      "properties": {
        "kind": {
          "type": "string",
          "const": "before_delinquency"
        },
        "citation": {
          "$ref": "#/$defs/citation"
        }
      }
    },
    "earned_within_days": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "kind",
        "days",
        "from",
        "citation"
      ],
      "properties": {
        "kind": {
          "type": "string",
          "const": "within_days"
        },
        "days": {
          "$ref": "#/$defs/days"
        },
        "from": {
          "type": "string",
          "enum": [
            "issue",
            "receipt"
          ]
        },
        "citation": {
          "$ref": "#/$defs/citation"
        }
      }
    },
    "earned_on_regulator_complaint": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "kind",
        "citation"
      ],
      "properties": {
        "kind": {
          "type": "string",
          "const": "on_regulator_complaint"
        },
        "citation": {
          "$ref": "#/$defs/citation"
        }
      }
    },
    "earned_unruled": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "kind"
      ],
      "properties": {
        "kind": {
          "type": "string",
          "const": "unruled"
        },
        "citation": {
          "$ref": "#/$defs/citation"
        }
      }
    },
    "must_pay": {
      "oneOf": [
        {
          "$ref": "#/$defs/pay_undisputed_charges"
        },
        {
          "$ref": "#/$defs/pay_average_usage_cap"
        },
        {
          "$ref": "#/$defs/pay_full_bill"
        },
        {
          "$ref": "#/$defs/pay_withhold_cap"
        },
        {
          "$ref": "#/$defs/pay_unruled"
        }
      ]
    },
    "pay_undisputed_charges": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "strategy",
        "version",
        "id",
        "citation"
      ],
      "properties": {
        "strategy": {
          "type": "string",
          "const": "undisputed_charges"
        },
        "version": {
          "$ref": "#/$defs/version"
        },
        "id": {
          "$ref": "#/$defs/id"
        },
        "citation": {
          "$ref": "#/$defs/citation"
        }
      }
    },
    "pay_average_usage_cap": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "strategy",
        "version",
        "id",
        "history_years",
        "no_history",
        "citation"
      ],
      "properties": {
        "strategy": {
          "type": "string",
          "const": "average_usage_cap"
        },
        "version": {
          "$ref": "#/$defs/version"
        },
        "id": {
          "$ref": "#/$defs/id"
        },
        "history_years": {
          "type": "integer",
          "minimum": 1,
          "maximum": 10
        },
        "no_history": {
          "type": "string",
          "enum": [
            "similar_customers"
          ]
        },
        "citation": {
          "$ref": "#/$defs/citation"
        }
      }
    },
    "pay_full_bill": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "strategy",
        "version",
        "id",
        "citation"
      ],
      "properties": {
        "strategy": {
          "type": "string",
          "const": "full_bill"
        },
        "version": {
          "$ref": "#/$defs/version"
        },
        "id": {
          "$ref": "#/$defs/id"
        },
        "citation": {
          "$ref": "#/$defs/citation"
        }
      }
    },
    "pay_withhold_cap": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "strategy",
        "version",
        "id",
        "fraction",
        "citation"
      ],
      "properties": {
        "strategy": {
          "type": "string",
          "const": "withhold_cap"
        },
        "version": {
          "$ref": "#/$defs/version"
        },
        "id": {
          "$ref": "#/$defs/id"
        },
        "fraction": {
          "type": "number",
          "exclusiveMinimum": 0,
          "maximum": 10
        },
        "citation": {
          "$ref": "#/$defs/citation"
        }
      }
    },
    "pay_unruled": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "strategy",
        "version",
        "id"
      ],
      "properties": {
        "strategy": {
          "type": "string",
          "const": "unruled"
        },
        "version": {
          "$ref": "#/$defs/version"
        },
        "id": {
          "$ref": "#/$defs/id"
        },
        "citation": {
          "$ref": "#/$defs/citation"
        }
      }
    },
    "shelter_ends": {
      "oneOf": [
        {
          "$ref": "#/$defs/ends_resolution"
        },
        {
          "$ref": "#/$defs/ends_earlier_of_resolution_and_days"
        },
        {
          "$ref": "#/$defs/ends_through_regulator_close"
        },
        {
          "$ref": "#/$defs/ends_unruled"
        }
      ]
    },
    "ends_resolution": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "kind",
        "citation"
      ],
      "properties": {
        "kind": {
          "type": "string",
          "const": "resolution"
        },
        "citation": {
          "$ref": "#/$defs/citation"
        }
      }
    },
    "ends_earlier_of_resolution_and_days": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "kind",
        "days",
        "from",
        "citation"
      ],
      "properties": {
        "kind": {
          "type": "string",
          "const": "earlier_of_resolution_and_days"
        },
        "days": {
          "$ref": "#/$defs/days"
        },
        "from": {
          "type": "string",
          "const": "issue"
        },
        "citation": {
          "$ref": "#/$defs/citation"
        }
      }
    },
    "ends_through_regulator_close": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "kind",
        "citation"
      ],
      "properties": {
        "kind": {
          "type": "string",
          "const": "through_regulator_close"
        },
        "citation": {
          "$ref": "#/$defs/citation"
        }
      }
    },
    "ends_unruled": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "kind"
      ],
      "properties": {
        "kind": {
          "type": "string",
          "const": "unruled"
        },
        "citation": {
          "$ref": "#/$defs/citation"
        }
      }
    },
    "within_none": {
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
    "file_within": {
      "oneOf": [
        {
          "$ref": "#/$defs/within_none"
        },
        {
          "$ref": "#/$defs/file_within_days"
        }
      ]
    },
    "file_within_days": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "kind",
        "days",
        "from"
      ],
      "properties": {
        "kind": {
          "type": "string",
          "const": "days"
        },
        "days": {
          "$ref": "#/$defs/days"
        },
        "from": {
          "type": "string",
          "enum": [
            "prior_decision",
            "issue",
            "receipt"
          ]
        }
      }
    },
    "decide_within": {
      "oneOf": [
        {
          "$ref": "#/$defs/within_none"
        },
        {
          "$ref": "#/$defs/decide_within_days"
        }
      ]
    },
    "decide_within_days": {
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
          "$ref": "#/$defs/days"
        }
      }
    },
    "stage": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "id",
        "decider",
        "file_within",
        "decide_within",
        "final",
        "citation"
      ],
      "properties": {
        "id": {
          "$ref": "#/$defs/id"
        },
        "decider": {
          "type": "string",
          "enum": [
            "designated_employee",
            "supervisor",
            "manager",
            "executive",
            "governing_body",
            "regulator"
          ]
        },
        "file_within": {
          "$ref": "#/$defs/file_within"
        },
        "decide_within": {
          "$ref": "#/$defs/decide_within"
        },
        "final": {
          "type": "boolean"
        },
        "citation": {
          "$ref": "#/$defs/citation"
        }
      }
    },
    "code_list": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "codes",
        "citation"
      ],
      "properties": {
        "codes": {
          "$ref": "#/$defs/codes"
        },
        "citation": {
          "$ref": "#/$defs/citation"
        }
      }
    },
    "law": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "governs",
        "citation",
        "subjects",
        "shelter_earned",
        "must_pay",
        "shelter_ends",
        "stages",
        "blocks",
        "duties"
      ],
      "properties": {
        "governs": {
          "type": "string",
          "const": "law"
        },
        "citation": {
          "$ref": "#/$defs/citation"
        },
        "subjects": {
          "$ref": "#/$defs/subjects"
        },
        "shelter_earned": {
          "$ref": "#/$defs/shelter_earned"
        },
        "must_pay": {
          "$ref": "#/$defs/must_pay"
        },
        "shelter_ends": {
          "$ref": "#/$defs/shelter_ends"
        },
        "stages": {
          "type": "array",
          "items": {
            "$ref": "#/$defs/stage"
          },
          "maxItems": 8
        },
        "blocks": {
          "$ref": "#/$defs/code_list"
        },
        "duties": {
          "$ref": "#/$defs/code_list"
        }
      }
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
          "$ref": "#/$defs/citation"
        },
        "note": {
          "type": "string",
          "pattern": "[A-Za-z0-9]"
        }
      }
    }
  }
}$schema$::jsonb, DATE '2026-10-18',
            'Dispute rule: what a state''s law says about a customer''s dispute for one customer class — what may be disputed, when a dispute earns shelter, what must still be paid, when the shelter ends, the review stages, what the shelter stops and the utility''s duties — or the law leaving it to the utility',
            'law/dispute/dispute.v1.schema.json');
    INSERT INTO public.rule_term_facets (terms_kind, terms_version, facet_name, facet_type, json_path, vocabulary_table, vocabulary_column, vocabulary_scope, description) VALUES
        ('dispute', 1, 'subject_codes',          'text[]', '$.subjects.codes[*]',    'public.dispute_subjects', 'subject_code', NULL,
         'The subjects a listed document admits: each a dispute_subjects row. Empty when it admits any subject.'),
        ('dispute', 1, 'excluded_subject_codes', 'text[]', '$.subjects.excluded[*]', 'public.dispute_subjects', 'subject_code', NULL,
         'The subjects the document excludes from dispute: each a dispute_subjects row.'),
        ('dispute', 1, 'block_codes',            'text[]', '$.blocks.codes[*]',      'public.dispute_blocks',   'block_code',   NULL,
         'What the shelter stops: each a dispute_blocks row. A sheltered determination records exactly these.'),
        ('dispute', 1, 'stage_ids',              'text[]', '$.stages[*].id',         NULL, NULL, NULL,
         'The ids of the review stages. Not a vocabulary: a stage event names its stage by id.'),
        ('dispute', 1, 'must_pay_ids',           'text[]', '$.must_pay.id',          NULL, NULL, NULL,
         'The id of the must-pay component. Not a vocabulary: a determination names the component that governed by id.');

    INSERT INTO public.rule_term_schemas (terms_kind, terms_version, rule_role, json_schema, introduced_on, description, source_note)
    VALUES ('dispute_tariff', 1, 'tariff', $schema${
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://tally-utility/law/dispute/dispute_tariff.v1.schema.json",
  "title": "Dispute tariff, version 1",
  "description": "A utility's own dispute policy, from its tariff, confirmed at setup (K-07: no assumed default): the same sections as the dispute law, so the two compare like with like. A tariff is the utility's policy, not law: it carries one citation (the tariff provision), no governs key, and no unruled section — a utility's own policy says what it does. Measured against the law in force when written (never looser).",
  "type": "object",
  "additionalProperties": false,
  "required": [
    "citation",
    "subjects",
    "shelter_earned",
    "must_pay",
    "shelter_ends",
    "stages",
    "blocks",
    "duties"
  ],
  "properties": {
    "citation": {
      "$ref": "#/$defs/citation"
    },
    "subjects": {
      "$ref": "#/$defs/subjects"
    },
    "shelter_earned": {
      "$ref": "#/$defs/shelter_earned"
    },
    "must_pay": {
      "$ref": "#/$defs/must_pay"
    },
    "shelter_ends": {
      "$ref": "#/$defs/shelter_ends"
    },
    "stages": {
      "type": "array",
      "items": {
        "$ref": "#/$defs/stage"
      },
      "maxItems": 8
    },
    "blocks": {
      "$ref": "#/$defs/code_list"
    },
    "duties": {
      "$ref": "#/$defs/code_list"
    }
  },
  "$defs": {
    "citation": {
      "type": "string",
      "pattern": "[A-Za-z0-9]"
    },
    "code": {
      "type": "string",
      "pattern": "^[a-z][a-z0-9_]*$"
    },
    "codes": {
      "type": "array",
      "items": {
        "$ref": "#/$defs/code"
      },
      "maxItems": 32
    },
    "id": {
      "type": "string",
      "pattern": "^[a-z][a-z0-9_]*$"
    },
    "version": {
      "type": "integer",
      "minimum": 1,
      "maximum": 1
    },
    "days": {
      "type": "integer",
      "minimum": 1,
      "maximum": 3650
    },
    "subjects": {
      "oneOf": [
        {
          "$ref": "#/$defs/subjects_any"
        },
        {
          "$ref": "#/$defs/subjects_listed"
        }
      ]
    },
    "subjects_any": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "kind",
        "excluded"
      ],
      "properties": {
        "kind": {
          "type": "string",
          "const": "any"
        },
        "excluded": {
          "$ref": "#/$defs/codes"
        }
      }
    },
    "subjects_listed": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "kind",
        "codes",
        "excluded"
      ],
      "properties": {
        "kind": {
          "type": "string",
          "const": "listed"
        },
        "codes": {
          "type": "array",
          "items": {
            "$ref": "#/$defs/code"
          },
          "minItems": 1,
          "maxItems": 32
        },
        "excluded": {
          "$ref": "#/$defs/codes"
        }
      }
    },
    "shelter_earned": {
      "oneOf": [
        {
          "$ref": "#/$defs/earned_any_time"
        },
        {
          "$ref": "#/$defs/earned_before_termination"
        },
        {
          "$ref": "#/$defs/earned_before_delinquency"
        },
        {
          "$ref": "#/$defs/earned_within_days"
        },
        {
          "$ref": "#/$defs/earned_on_regulator_complaint"
        }
      ]
    },
    "earned_any_time": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "kind"
      ],
      "properties": {
        "kind": {
          "type": "string",
          "const": "any_time"
        }
      }
    },
    "earned_before_termination": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "kind"
      ],
      "properties": {
        "kind": {
          "type": "string",
          "const": "before_termination"
        }
      }
    },
    "earned_before_delinquency": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "kind"
      ],
      "properties": {
        "kind": {
          "type": "string",
          "const": "before_delinquency"
        }
      }
    },
    "earned_within_days": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "kind",
        "days",
        "from"
      ],
      "properties": {
        "kind": {
          "type": "string",
          "const": "within_days"
        },
        "days": {
          "$ref": "#/$defs/days"
        },
        "from": {
          "type": "string",
          "enum": [
            "issue",
            "receipt"
          ]
        }
      }
    },
    "earned_on_regulator_complaint": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "kind"
      ],
      "properties": {
        "kind": {
          "type": "string",
          "const": "on_regulator_complaint"
        }
      }
    },
    "must_pay": {
      "oneOf": [
        {
          "$ref": "#/$defs/pay_undisputed_charges"
        },
        {
          "$ref": "#/$defs/pay_average_usage_cap"
        },
        {
          "$ref": "#/$defs/pay_full_bill"
        },
        {
          "$ref": "#/$defs/pay_withhold_cap"
        }
      ]
    },
    "pay_undisputed_charges": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "strategy",
        "version",
        "id"
      ],
      "properties": {
        "strategy": {
          "type": "string",
          "const": "undisputed_charges"
        },
        "version": {
          "$ref": "#/$defs/version"
        },
        "id": {
          "$ref": "#/$defs/id"
        }
      }
    },
    "pay_average_usage_cap": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "strategy",
        "version",
        "id",
        "history_years",
        "no_history"
      ],
      "properties": {
        "strategy": {
          "type": "string",
          "const": "average_usage_cap"
        },
        "version": {
          "$ref": "#/$defs/version"
        },
        "id": {
          "$ref": "#/$defs/id"
        },
        "history_years": {
          "type": "integer",
          "minimum": 1,
          "maximum": 10
        },
        "no_history": {
          "type": "string",
          "enum": [
            "similar_customers"
          ]
        }
      }
    },
    "pay_full_bill": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "strategy",
        "version",
        "id"
      ],
      "properties": {
        "strategy": {
          "type": "string",
          "const": "full_bill"
        },
        "version": {
          "$ref": "#/$defs/version"
        },
        "id": {
          "$ref": "#/$defs/id"
        }
      }
    },
    "pay_withhold_cap": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "strategy",
        "version",
        "id",
        "fraction"
      ],
      "properties": {
        "strategy": {
          "type": "string",
          "const": "withhold_cap"
        },
        "version": {
          "$ref": "#/$defs/version"
        },
        "id": {
          "$ref": "#/$defs/id"
        },
        "fraction": {
          "type": "number",
          "exclusiveMinimum": 0,
          "maximum": 10
        }
      }
    },
    "shelter_ends": {
      "oneOf": [
        {
          "$ref": "#/$defs/ends_resolution"
        },
        {
          "$ref": "#/$defs/ends_earlier_of_resolution_and_days"
        },
        {
          "$ref": "#/$defs/ends_through_regulator_close"
        }
      ]
    },
    "ends_resolution": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "kind"
      ],
      "properties": {
        "kind": {
          "type": "string",
          "const": "resolution"
        }
      }
    },
    "ends_earlier_of_resolution_and_days": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "kind",
        "days",
        "from"
      ],
      "properties": {
        "kind": {
          "type": "string",
          "const": "earlier_of_resolution_and_days"
        },
        "days": {
          "$ref": "#/$defs/days"
        },
        "from": {
          "type": "string",
          "const": "issue"
        }
      }
    },
    "ends_through_regulator_close": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "kind"
      ],
      "properties": {
        "kind": {
          "type": "string",
          "const": "through_regulator_close"
        }
      }
    },
    "within_none": {
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
    "file_within": {
      "oneOf": [
        {
          "$ref": "#/$defs/within_none"
        },
        {
          "$ref": "#/$defs/file_within_days"
        }
      ]
    },
    "file_within_days": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "kind",
        "days",
        "from"
      ],
      "properties": {
        "kind": {
          "type": "string",
          "const": "days"
        },
        "days": {
          "$ref": "#/$defs/days"
        },
        "from": {
          "type": "string",
          "enum": [
            "prior_decision",
            "issue",
            "receipt"
          ]
        }
      }
    },
    "decide_within": {
      "oneOf": [
        {
          "$ref": "#/$defs/within_none"
        },
        {
          "$ref": "#/$defs/decide_within_days"
        }
      ]
    },
    "decide_within_days": {
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
          "$ref": "#/$defs/days"
        }
      }
    },
    "stage": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "id",
        "decider",
        "file_within",
        "decide_within",
        "final"
      ],
      "properties": {
        "id": {
          "$ref": "#/$defs/id"
        },
        "decider": {
          "type": "string",
          "enum": [
            "designated_employee",
            "supervisor",
            "manager",
            "executive",
            "governing_body",
            "regulator"
          ]
        },
        "file_within": {
          "$ref": "#/$defs/file_within"
        },
        "decide_within": {
          "$ref": "#/$defs/decide_within"
        },
        "final": {
          "type": "boolean"
        }
      }
    },
    "code_list": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "codes"
      ],
      "properties": {
        "codes": {
          "$ref": "#/$defs/codes"
        }
      }
    }
  }
}$schema$::jsonb, DATE '2026-10-18',
            'Dispute tariff: a utility''s own dispute policy, from its tariff, in the dispute law''s sections — never looser than the law in force',
            'law/dispute/dispute_tariff.v1.schema.json');
    INSERT INTO public.rule_term_facets (terms_kind, terms_version, facet_name, facet_type, json_path, vocabulary_table, vocabulary_column, vocabulary_scope, description) VALUES
        ('dispute_tariff', 1, 'subject_codes',          'text[]', '$.subjects.codes[*]',    'public.dispute_subjects', 'subject_code', NULL,
         'The subjects a listed policy admits: each a dispute_subjects row. Empty when it admits any subject.'),
        ('dispute_tariff', 1, 'excluded_subject_codes', 'text[]', '$.subjects.excluded[*]', 'public.dispute_subjects', 'subject_code', NULL,
         'The subjects the policy excludes from dispute: each a dispute_subjects row.'),
        ('dispute_tariff', 1, 'block_codes',            'text[]', '$.blocks.codes[*]',      'public.dispute_blocks',   'block_code',   NULL,
         'What the shelter stops: each a dispute_blocks row. A sheltered determination citing the tariff records exactly these.'),
        ('dispute_tariff', 1, 'stage_ids',              'text[]', '$.stages[*].id',         NULL, NULL, NULL,
         'The ids of the review stages. Not a vocabulary: a stage event names its stage by id.'),
        ('dispute_tariff', 1, 'must_pay_ids',           'text[]', '$.must_pay.id',          NULL, NULL, NULL,
         'The id of the must-pay component. Not a vocabulary: a determination names the component that governed by id.');
END
$kinds$;

-- The checks a dispute document (law or tariff) carries beyond its schema:
-- consistency the schema cannot state, and the duties vocabulary. Raises.
CREATE OR REPLACE FUNCTION public.dispute_terms_check(p_what text, p_doc jsonb) RETURNS void
    LANGUAGE plpgsql STABLE
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_bad    text;
    v_path   text[];
    v_stages jsonb := coalesce(p_doc -> 'stages', '[]'::jsonb);
    v_n      integer := jsonb_array_length(coalesce(p_doc -> 'stages', '[]'::jsonb));
BEGIN
    SELECT string_agg(c, ', ' ORDER BY c) INTO v_bad
      FROM jsonb_array_elements_text(coalesce(p_doc #> '{subjects,codes}', '[]'::jsonb)) c
     WHERE coalesce(p_doc #> '{subjects,excluded}', '[]'::jsonb) ? c;
    IF v_bad IS NOT NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('%s: subject %s is both listed and excluded [L2a] (v5.4.2-25)', p_what, v_bad),
            ERRCODE = 'check_violation';
    END IF;
    FOREACH v_path SLICE 1 IN ARRAY ARRAY[ARRAY['blocks', 'codes'], ARRAY['duties', 'codes'], ARRAY['subjects', 'codes'], ARRAY['subjects', 'excluded']] LOOP
        SELECT string_agg(DISTINCT c, ', ' ORDER BY c) INTO v_bad
          FROM (SELECT c FROM jsonb_array_elements_text(coalesce(p_doc #> v_path, '[]'::jsonb)) c GROUP BY c HAVING count(*) > 1) x;
        IF v_bad IS NOT NULL THEN
            RAISE EXCEPTION USING
                MESSAGE = format('%s: %s lists %s more than once [L2b] (v5.4.2-25)', p_what, array_to_string(v_path, '.'), v_bad),
                ERRCODE = 'check_violation';
        END IF;
    END LOOP;
    SELECT string_agg(c, ', ' ORDER BY c) INTO v_bad
      FROM jsonb_array_elements_text(coalesce(p_doc #> '{duties,codes}', '[]'::jsonb)) c
     WHERE NOT EXISTS (SELECT 1 FROM public.dispute_duties d WHERE d.duty_code = c);
    IF v_bad IS NOT NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('%s: its duties names %s, not in dispute_duties (v5.4.2-25)', p_what, v_bad),
            ERRCODE = 'foreign_key_violation';
    END IF;
    IF v_n > 0 AND v_stages #>> '{0,file_within,from}' = 'prior_decision' THEN
        RAISE EXCEPTION USING
            MESSAGE = format('%s: stage %s is filed within days of the prior decision, but it is the first stage [L2c] (v5.4.2-25)', p_what, v_stages #>> '{0,id}'),
            ERRCODE = 'check_violation';
    END IF;
    SELECT string_agg(s ->> 'id', ', ') INTO v_bad
      FROM jsonb_array_elements(v_stages) WITH ORDINALITY x(s, i)
     WHERE (s -> 'final') = 'true'::jsonb AND i < v_n;
    IF v_bad IS NOT NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('%s: stage %s is final but not the last [L2d] (v5.4.2-25)', p_what, v_bad),
            ERRCODE = 'check_violation';
    END IF;
END;
$$;
COMMENT ON FUNCTION public.dispute_terms_check(text, jsonb) IS
    'v5.4.2-25 (L2). What a dispute document (law or tariff) must also satisfy beyond its schema: no subject both listed and excluded [L2a]; no code listed twice in blocks, duties or subjects [L2b] (a facet would silently drop the repeat); the first stage is not filed from a prior decision [L2c]; only the last stage may be final [L2d]; every duty is a dispute_duties row (23503). Raises. Called by both tables'' insert checks.';
REVOKE ALL ON FUNCTION public.dispute_terms_check(text, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.dispute_terms_check(text, jsonb) TO tally_app;


-- ----------------------------------------------------------------------------
-- 3. The law (L1, L3, L4)
-- ----------------------------------------------------------------------------
CREATE TABLE public.dispute_rules (
    id                      uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    state_code              text NOT NULL,
    service_type            text NOT NULL,
    owner_types             text[],
    system_kinds            text[],
    commission_jurisdiction boolean,
    owner_span              int4multirange NOT NULL,
    system_span             int4multirange NOT NULL,
    jurisdiction_span       int4range NOT NULL,
    customer_class          text NOT NULL,
    effective_from          date NOT NULL,
    effective_to            date,
    source_note             text NOT NULL,
    terms_kind              text NOT NULL,
    terms_version           integer NOT NULL,
    terms_source            text NOT NULL,
    terms                   jsonb NOT NULL,
    subject_codes           text[] NOT NULL,
    excluded_subject_codes  text[] NOT NULL,
    block_codes             text[] NOT NULL,
    stage_ids               text[] NOT NULL,
    must_pay_ids            text[] NOT NULL,
    created_at              timestamp with time zone DEFAULT now() NOT NULL,
    recorded_txid           bigint,
    closed_at               timestamp with time zone,
    closed_by               text,
    CONSTRAINT dispute_rules_pkey PRIMARY KEY (id),
    CONSTRAINT dispute_rules_customer_class_fkey FOREIGN KEY (state_code, service_type, customer_class)
        REFERENCES public.dispute_customer_classes (state_code, service_type, class_code)
);

CREATE OR REPLACE FUNCTION public.dispute_rule_insert_check(p_row jsonb) RETURNS void
    LANGUAGE plpgsql STABLE
    SET search_path = public, pg_temp
    AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.dispute_customer_classes c
                    WHERE c.state_code = p_row ->> 'state_code' AND c.service_type = p_row ->> 'service_type'
                      AND c.class_code = p_row ->> 'customer_class') THEN
        RAISE EXCEPTION USING
            MESSAGE = format('dispute rule: customer class %s is not one of dispute_customer_classes for %s %s (v5.4.2-25)',
                             p_row ->> 'customer_class', p_row ->> 'state_code', p_row ->> 'service_type'),
            ERRCODE = 'foreign_key_violation';
    END IF;
    IF p_row -> 'terms' ->> 'governs' = 'law' THEN
        PERFORM public.dispute_terms_check(format('dispute rule (%s %s, %s)', p_row ->> 'state_code', p_row ->> 'service_type', p_row ->> 'customer_class'),
                                           p_row -> 'terms');
    END IF;
END;
$$;
COMMENT ON FUNCTION public.dispute_rule_insert_check(jsonb) IS
    'v5.4.2-25. The area predicate of dispute_rules (rule_tables.insert_check): the customer class is one of its state''s and service''s dispute classes; a law document passes dispute_terms_check. Raises.';

-- The latest date a determination needs the row in force: the received date
-- of the latest dispute citing it (a determination cites the law in force on
-- the day the dispute was received).
CREATE OR REPLACE FUNCTION public.dispute_rule_close_floor(p_rule_id uuid) RETURNS date
    LANGUAGE plpgsql STABLE
    SET search_path = public, pg_temp
    AS $$
BEGIN
    RETURN (SELECT max(d.received_on) FROM public.dispute_determinations x JOIN public.disputes d ON d.id = x.dispute_id
             WHERE x.rule_id = p_rule_id);
END;
$$;
COMMENT ON FUNCTION public.dispute_rule_close_floor(uuid) IS
    'v5.4.2-25. The close floor of a dispute_rules row: the latest received date of a dispute whose determination cites it, or NULL.';

DO $register$
BEGIN
    PERFORM public.rule_table_register('public.dispute_rules', 'law', 'dispute', ARRAY['customer_class'],
                                       ARRAY['block_codes', 'excluded_subject_codes', 'must_pay_ids', 'stage_ids', 'subject_codes'],
                                       'public.dispute_rule_close_floor(uuid)', 'public.dispute_rule_insert_check(jsonb)');
END
$register$;
REVOKE ALL ON FUNCTION public.dispute_rule_insert_check(jsonb), public.dispute_rule_close_floor(uuid) FROM PUBLIC, tally_app, tally_core;
COMMENT ON TABLE public.dispute_rules IS
    'v5.4.2-25 (L1-L4; wave-3 Q1), on the rule-terms convention. What a state''s law says about a customer''s dispute, per (state, service, owner types, system kinds, jurisdiction, customer class, dates): one LAW row of the kind dispute, platform-held, never edited — the one change is a stamped close above the close floor (the latest received date of a dispute whose determination cites it). The document says what may be disputed, when a dispute earns shelter, what must still be paid (a strategy the core runs), when the shelter ends, the review stages, what the shelter stops and the utility''s duties; a class the law gives no shelter has a row saying so. The core evaluates it; the database stores it and checks the records citing it. A city-owned Texas system''s rows delegate to its tariff (K-07). Another state or service finds no row: unknown law is not permission. Seeded from law/dispute/dispute_rules.yaml.';


-- ----------------------------------------------------------------------------
-- 4. The utility's own policy (L5, L6)
-- ----------------------------------------------------------------------------
CREATE TABLE public.dispute_tariffs (
    id                      uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id               uuid NOT NULL,
    state_code              text NOT NULL,
    service_type            text NOT NULL,
    system_kind             text NOT NULL,
    effective_from          date NOT NULL,
    effective_to            date,
    tariff_reference        text NOT NULL,
    terms_kind              text NOT NULL,
    terms_version           integer NOT NULL,
    terms_source            text NOT NULL,
    terms                   jsonb NOT NULL,
    subject_codes           text[] NOT NULL,
    excluded_subject_codes  text[] NOT NULL,
    block_codes             text[] NOT NULL,
    stage_ids               text[] NOT NULL,
    must_pay_ids            text[] NOT NULL,
    created_at              timestamp with time zone DEFAULT now() NOT NULL,
    recorded_txid           bigint,
    created_by              uuid,
    closed_at               timestamp with time zone,
    closed_by               uuid,
    CONSTRAINT dispute_tariffs_pkey PRIMARY KEY (id)
);

CREATE OR REPLACE FUNCTION public.dispute_tariff_insert_check(p_row jsonb) RETURNS void
    LANGUAGE plpgsql STABLE
    SET search_path = public, pg_temp
    AS $$
BEGIN
    IF NOT public.is_platform_admin() AND (p_row ->> 'tenant_id')::uuid IS DISTINCT FROM public.get_user_tenant_id()
       AND NOT coalesce((SELECT r.rolsuper OR r.rolbypassrls FROM pg_roles r WHERE r.rolname = current_user), false) THEN
        RAISE EXCEPTION USING
            MESSAGE = 'new row violates row-level security policy for table "dispute_tariffs": a utility writes its own policy only (v5.4.2-25)',
            ERRCODE = 'insufficient_privilege';
    END IF;
    PERFORM public.dispute_terms_check(format('dispute tariff (%s %s %s)', p_row ->> 'state_code', p_row ->> 'service_type', p_row ->> 'system_kind'),
                                       p_row -> 'terms');
END;
$$;
COMMENT ON FUNCTION public.dispute_tariff_insert_check(jsonb) IS
    'v5.4.2-25. The area predicate of dispute_tariffs (rule_tables.insert_check): the writer is the row''s own utility; the document passes dispute_terms_check. Raises.';

CREATE OR REPLACE FUNCTION public.dispute_tariff_close_floor(p_tariff_id uuid) RETURNS date
    LANGUAGE plpgsql STABLE
    SET search_path = public, pg_temp
    AS $$
BEGIN
    RETURN (SELECT max(d.received_on) FROM public.dispute_determinations x JOIN public.disputes d ON d.id = x.dispute_id
             WHERE x.tariff_id = p_tariff_id);
END;
$$;
COMMENT ON FUNCTION public.dispute_tariff_close_floor(uuid) IS
    'v5.4.2-25. The close floor of a dispute_tariffs row: the latest received date of a dispute whose determination cites it, or NULL.';

-- The subjects a document admits: every subject (kind any) or its list,
-- less its exclusions.
CREATE OR REPLACE FUNCTION public.dispute_subjects_admitted(p_subjects jsonb) RETURNS text[]
    LANGUAGE sql STABLE
    SET search_path = public, pg_temp
    AS $$
    SELECT coalesce(array_agg(s.subject_code ORDER BY s.subject_code), '{}')
      FROM public.dispute_subjects s
     WHERE (p_subjects ->> 'kind' = 'any' OR coalesce(p_subjects -> 'codes', '[]'::jsonb) ? s.subject_code)
       AND NOT coalesce(p_subjects -> 'excluded', '[]'::jsonb) ? s.subject_code
$$;
COMMENT ON FUNCTION public.dispute_subjects_admitted(jsonb) IS
    'v5.4.2-25 (L6). The subject codes a document''s subjects section admits: every dispute_subjects code (kind any) or the listed ones, less the excluded.';
REVOKE ALL ON FUNCTION public.dispute_subjects_admitted(jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.dispute_subjects_admitted(jsonb) TO tally_app, tally_core;

CREATE OR REPLACE FUNCTION public.dispute_tariff_compare(p_tariff jsonb, p_law jsonb) RETURNS text[]
    LANGUAGE plpgsql STABLE
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_problem text[] := '{}';
    v_row     jsonb;
    v_l       jsonb;
    v_t       jsonb := p_tariff -> 'terms';
    v_law     text;
    v_bad     text;
    v_le      jsonb;
    v_te      jsonb;
    v_lp      jsonb;
    v_tp      jsonb;
    -- shelter_earned kinds in one order of breadth (wider first); the rest
    -- compare only with their own kind.
    c_rank    CONSTANT jsonb := '{"any_time": 4, "before_termination": 3, "before_delinquency": 2}';
BEGIN
    FOR v_row IN SELECT x FROM jsonb_array_elements(p_law) x LOOP
        v_l := v_row -> 'terms';
        CONTINUE WHEN v_l ->> 'governs' IS DISTINCT FROM 'law';    -- a delegation compares nothing
        v_law := format('law row %s (%s, %s)', v_row ->> 'id', v_row ->> 'customer_class', v_l ->> 'citation');

        -- blocks: every block of the law's
        SELECT string_agg(c, ', ' ORDER BY c) INTO v_bad
          FROM jsonb_array_elements_text(v_l #> '{blocks,codes}') c
         WHERE NOT (v_t #> '{blocks,codes}') ? c;
        IF v_bad IS NOT NULL THEN
            v_problem := v_problem || format('blocks: %s blocks %s; the tariff does not', v_law, v_bad);
        END IF;

        -- subjects: every subject the law admits
        SELECT string_agg(c, ', ' ORDER BY c) INTO v_bad
          FROM unnest(public.dispute_subjects_admitted(v_l -> 'subjects')) c
         WHERE NOT c = ANY (public.dispute_subjects_admitted(v_t -> 'subjects'));
        IF v_bad IS NOT NULL THEN
            v_problem := v_problem || format('subjects: %s admits %s; the tariff does not', v_law, v_bad);
        END IF;

        -- shelter_earned: no narrower; a pair outside one order is not
        -- comparable and refused (fail toward protection)
        v_le := v_l -> 'shelter_earned';
        v_te := v_t -> 'shelter_earned';
        IF v_le ->> 'kind' = 'unruled' THEN
            NULL;
        ELSIF v_te ->> 'kind' = v_le ->> 'kind' AND v_le ->> 'kind' = 'within_days' THEN
            IF (v_te ->> 'days')::integer < (v_le ->> 'days')::integer OR v_te ->> 'from' <> v_le ->> 'from' THEN
                v_problem := v_problem || format('shelter_earned: %s shelters a dispute within %s days of %s; the tariff''s %s days of %s is narrower or not comparable',
                                                 v_law, v_le ->> 'days', v_le ->> 'from', v_te ->> 'days', v_te ->> 'from');
            END IF;
        ELSIF v_te ->> 'kind' = v_le ->> 'kind' THEN
            NULL;
        ELSIF NOT (c_rank ? (v_te ->> 'kind') AND c_rank ? (v_le ->> 'kind')
                   AND (c_rank ->> (v_te ->> 'kind'))::integer >= (c_rank ->> (v_le ->> 'kind'))::integer) THEN
            v_problem := v_problem || format('shelter_earned: %s shelters a dispute %s; the tariff''s %s is narrower or not comparable (fail toward protection)',
                                             v_law, v_le ->> 'kind', v_te ->> 'kind');
        END IF;

        -- shelter_ends: no sooner
        v_le := v_l -> 'shelter_ends';
        v_te := v_t -> 'shelter_ends';
        IF v_le ->> 'kind' = 'unruled' THEN
            NULL;
        ELSIF v_te ->> 'kind' = v_le ->> 'kind' THEN
            IF v_le ->> 'kind' = 'earlier_of_resolution_and_days' AND (v_te ->> 'days')::integer < (v_le ->> 'days')::integer THEN
                v_problem := v_problem || format('shelter_ends: %s ends the shelter %s days from issue at the earliest; the tariff ends it after %s',
                                                 v_law, v_le ->> 'days', v_te ->> 'days');
            END IF;
        ELSIF NOT (v_te ->> 'kind' = 'resolution' AND v_le ->> 'kind' = 'earlier_of_resolution_and_days') THEN
            v_problem := v_problem || format('shelter_ends: %s ends the shelter at %s; the tariff''s %s is sooner or not comparable (fail toward protection)',
                                             v_law, v_le ->> 'kind', v_te ->> 'kind');
        END IF;

        -- must_pay: asks no more. undisputed_charges asks no more than any
        -- strategy, full_bill no less; equal strategies compare their figures.
        v_lp := v_l -> 'must_pay';
        v_tp := v_t -> 'must_pay';
        IF v_lp ->> 'strategy' IN ('unruled', 'full_bill') OR v_tp ->> 'strategy' = 'undisputed_charges' THEN
            NULL;
        ELSIF v_tp ->> 'strategy' = v_lp ->> 'strategy' AND v_lp ->> 'strategy' = 'withhold_cap' THEN
            IF (v_tp ->> 'fraction')::numeric < (v_lp ->> 'fraction')::numeric THEN
                v_problem := v_problem || format('must_pay: %s lets the customer withhold %s of the disputed amount; the tariff only %s',
                                                 v_law, v_lp ->> 'fraction', v_tp ->> 'fraction');
            END IF;
        ELSIF v_tp ->> 'strategy' = v_lp ->> 'strategy' AND v_lp ->> 'strategy' = 'average_usage_cap'
              AND (v_tp -> 'history_years') = (v_lp -> 'history_years') AND (v_tp -> 'no_history') = (v_lp -> 'no_history') THEN
            NULL;
        ELSE
            v_problem := v_problem || format('must_pay: %s asks for %s; the tariff''s %s asks more or is not comparable (fail toward protection)',
                                             v_law, v_lp - ARRAY['id', 'version', 'citation'], v_tp - ARRAY['id', 'version']);
        END IF;
    END LOOP;
    RETURN v_problem;
END;
$$;
COMMENT ON FUNCTION public.dispute_tariff_compare(jsonb, jsonb) IS
    'v5.4.2-25 (L6). rule_tables.compare_function of dispute_tariffs: against every law row in force that rules (governs law) for the utility — every class, so the most protective binds — the tariff is refused when its blocks lack one of the law''s; it admits fewer subjects; its shelter starts narrower (any_time, before_termination, before_delinquency in that order; within_days against its own kind only, the same anchor and at least the days; any other pair not comparable); its shelter ends sooner (resolution beats earlier-of-resolution-and-days; days against days; any other pair not comparable); or its must-pay asks more (undisputed_charges asks no more than any strategy, a law of full_bill or unruled is never exceeded, equal strategies compare figures — withholding by fraction, the average cap only when equal — and any other pair is not comparable). Not comparable is refused (fail toward protection). A delegation compares nothing. Stages and duties are not compared.';

DO $register$
BEGIN
    PERFORM public.rule_table_register('public.dispute_tariffs', 'tariff', 'dispute_tariff', ARRAY[]::text[],
                                       ARRAY['block_codes', 'excluded_subject_codes', 'must_pay_ids', 'stage_ids', 'subject_codes'],
                                       'public.dispute_tariff_close_floor(uuid)', 'public.dispute_tariff_insert_check(jsonb)',
                                       'public.dispute_rules', 'public.dispute_tariff_compare(jsonb,jsonb)');
END
$register$;
REVOKE ALL ON FUNCTION public.dispute_tariff_close_floor(uuid), public.dispute_tariff_insert_check(jsonb), public.dispute_tariff_compare(jsonb, jsonb)
    FROM PUBLIC, tally_core;
GRANT EXECUTE ON FUNCTION public.dispute_tariff_close_floor(uuid), public.dispute_tariff_insert_check(jsonb), public.dispute_tariff_compare(jsonb, jsonb) TO tally_app;
COMMENT ON TABLE public.dispute_tariffs IS
    'v5.4.2-25 (L5, L6; K-07), on the rule-terms convention. The utility''s own dispute policy, from its tariff, per (tenant, state, service, system, dates): one row of the kind dispute_tariff, in the dispute law''s sections, never edited — the one change is a stamped close above the close floor (the latest received date of a dispute whose determination cites it). Measured against dispute_rules when written: never looser than any law row in force for the utility (dispute_tariff_compare). No default row: the tenant enters its own at setup (K-07). The core evaluates it; a determination cites it.';

-- The Texas rows (law/dispute/dispute_rules.seed.sql, embedded verbatim).
-- Generated by tools/law/lawc.py emit — do not edit; edit the law file and re-emit.
-- Each call inserts its law row, or finds it unchanged, or raises (public.rule_row_seed, v5.4.2-17).
-- source: law/dispute/dispute_rules.yaml sha256 b67ab557a0564c46507db24f0f483e70c0bbb3606625bcfad3145254f1c200d8
SELECT public.rule_row_seed('public.dispute_rules', $law${"commission_jurisdiction":null,"customer_class":"protected","effective_from":"2004-07-12","effective_to":null,"owner_types":["cooperative","investor_owned"],"service_type":"gas","source_note":"16 TAC 7.45(6)(D): the disputed portion above average usage need not be paid until the earlier of resolution or 60 days from issue, for a dispute made before the bill went delinquent. late_fee in blocks is our reading (fail toward protection, K-CCK): the text says 'not required to pay' and is silent on a late fee.","state_code":"TX","system_kinds":["distribution"],"terms_kind":"dispute","terms_source":"{\"blocks\":{\"citation\":\"16 TAC 7.45(6)(D)(ii)\",\"codes\":[\"disconnect_order\",\"disconnect_execute\",\"late_fee\"]},\"citation\":\"16 TAC 7.45(6)(D)\",\"duties\":{\"citation\":\"16 TAC 7.45(6)(D)(i)\",\"codes\":[\"investigate\",\"report_result\",\"inform_complaint_route\"]},\"governs\":\"law\",\"must_pay\":{\"citation\":\"16 TAC 7.45(6)(D)(ii)\",\"history_years\":2,\"id\":\"m1\",\"no_history\":\"similar_customers\",\"strategy\":\"average_usage_cap\",\"version\":1},\"shelter_earned\":{\"citation\":\"16 TAC 7.45(6)(D)(i)\",\"kind\":\"before_delinquency\"},\"shelter_ends\":{\"citation\":\"16 TAC 7.45(6)(D)(ii)\",\"days\":60,\"from\":\"issue\",\"kind\":\"earlier_of_resolution_and_days\"},\"stages\":[{\"citation\":\"16 TAC 7.45(6)(D)(i)\",\"decide_within\":{\"kind\":\"none\"},\"decider\":\"designated_employee\",\"file_within\":{\"kind\":\"none\"},\"final\":false,\"id\":\"s1\"},{\"citation\":\"16 TAC 7.45(2)(C)\",\"decide_within\":{\"days\":15,\"kind\":\"days\"},\"decider\":\"regulator\",\"file_within\":{\"kind\":\"none\"},\"final\":true,\"id\":\"s2\"}],\"subjects\":{\"citation\":\"16 TAC 7.45(6)(D)(i)\",\"excluded\":[],\"kind\":\"any\"}}","terms_version":1}$law$::jsonb);  -- tx_gas_iou_coop_protected
SELECT public.rule_row_seed('public.dispute_rules', $law${"commission_jurisdiction":null,"customer_class":"unprotected","effective_from":"2004-07-12","effective_to":null,"owner_types":["cooperative","investor_owned"],"service_type":"gas","source_note":"16 TAC 7.45(1): the dispute shelter of 7.45(6)(D) reaches residential and small commercial customers only; a large commercial or industrial customer's dispute earns no shelter from it.","state_code":"TX","system_kinds":["distribution"],"terms_kind":"dispute","terms_source":"{\"blocks\":{\"citation\":\"16 TAC 7.45(1)\",\"codes\":[]},\"citation\":\"16 TAC 7.45(1)\",\"duties\":{\"citation\":\"16 TAC 7.45(1)\",\"codes\":[]},\"governs\":\"law\",\"must_pay\":{\"citation\":\"16 TAC 7.45(1)\",\"id\":\"m1\",\"strategy\":\"full_bill\",\"version\":1},\"shelter_earned\":{\"kind\":\"unruled\"},\"shelter_ends\":{\"kind\":\"unruled\"},\"stages\":[],\"subjects\":{\"citation\":\"16 TAC 7.45(1)\",\"excluded\":[],\"kind\":\"any\"}}","terms_version":1}$law$::jsonb);  -- tx_gas_iou_coop_unprotected
SELECT public.rule_row_seed('public.dispute_rules', $law${"commission_jurisdiction":null,"customer_class":"protected","effective_from":"2004-07-12","effective_to":null,"owner_types":["municipal"],"service_type":"gas","source_note":"Tex. Util. Code 101.003(7): a municipal corporation is not a gas utility; a city-owned system sets its own dispute policy in its tariff (K-07).","state_code":"TX","system_kinds":["distribution"],"terms_kind":"dispute","terms_source":"{\"citation\":\"Tex. Util. Code 101.003(7)\",\"governs\":\"delegated_to_utility\",\"note\":\"A municipal corporation is not a gas utility under GURA; its own tariff sets its dispute policy.\"}","terms_version":1}$law$::jsonb);  -- tx_gas_municipal_protected
SELECT public.rule_row_seed('public.dispute_rules', $law${"commission_jurisdiction":null,"customer_class":"unprotected","effective_from":"2004-07-12","effective_to":null,"owner_types":["municipal"],"service_type":"gas","source_note":"Tex. Util. Code 101.003(7): a municipal corporation is not a gas utility; a city-owned system sets its own dispute policy in its tariff (K-07).","state_code":"TX","system_kinds":["distribution"],"terms_kind":"dispute","terms_source":"{\"citation\":\"Tex. Util. Code 101.003(7)\",\"governs\":\"delegated_to_utility\",\"note\":\"A municipal corporation is not a gas utility under GURA; its own tariff sets its dispute policy.\"}","terms_version":1}$law$::jsonb);  -- tx_gas_municipal_unprotected


-- ----------------------------------------------------------------------------
-- 5. The dispute record: tables (D1, D2, D3, D5)
-- ----------------------------------------------------------------------------
-- One sequence orders every dispute record in recording order.
CREATE SEQUENCE public.dispute_record_seq;

CREATE TABLE public.disputes (
    id                  uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id           uuid NOT NULL,
    customer_id         uuid NOT NULL,
    invoice_id          uuid,
    reading_id          uuid,
    subject             text NOT NULL,
    received_on         date NOT NULL,
    channel             text NOT NULL,
    status              text DEFAULT 'open' NOT NULL,
    status_cause_id     uuid,
    status_recorded_at  timestamp with time zone,
    created_at          timestamp with time zone DEFAULT now() NOT NULL,
    created_by          uuid,
    recorded_txid       bigint,
    CONSTRAINT disputes_pkey PRIMARY KEY (id),
    CONSTRAINT disputes_id_tenant_id_key UNIQUE (id, tenant_id),
    CONSTRAINT disputes_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants (id),
    CONSTRAINT disputes_customer_fkey FOREIGN KEY (customer_id, tenant_id) REFERENCES public.customers (id, tenant_id),
    CONSTRAINT disputes_invoice_fkey FOREIGN KEY (invoice_id, tenant_id, customer_id) REFERENCES public.invoices (id, tenant_id, customer_id),
    CONSTRAINT disputes_reading_fkey FOREIGN KEY (reading_id, tenant_id) REFERENCES public.meter_readings (id, tenant_id),
    CONSTRAINT disputes_subject_fkey FOREIGN KEY (subject) REFERENCES public.dispute_subjects (subject_code),
    CONSTRAINT disputes_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users (id),
    CONSTRAINT disputes_target_check CHECK (invoice_id IS NOT NULL OR reading_id IS NOT NULL),
    CONSTRAINT disputes_channel_check CHECK (channel = ANY (ARRAY['written', 'oral', 'portal', 'regulator_referral'])),
    CONSTRAINT disputes_status_check CHECK (status = ANY (ARRAY['open', 'resolved', 'withdrawn'])),
    CONSTRAINT disputes_status_cause_check
        CHECK ((status = 'open') = (status_cause_id IS NULL) AND (status_cause_id IS NULL) = (status_recorded_at IS NULL))
);
CREATE INDEX idx_disputes_tenant ON public.disputes (tenant_id);
CREATE INDEX idx_disputes_invoice ON public.disputes (invoice_id) WHERE invoice_id IS NOT NULL;
CREATE INDEX idx_disputes_reading ON public.disputes (reading_id) WHERE reading_id IS NOT NULL;
CREATE INDEX idx_disputes_customer ON public.disputes (tenant_id, customer_id);
COMMENT ON TABLE public.disputes IS
    'v5.4.2-25 (D1; CI-074, CI-054). A customer''s dispute: of an issued bill (its invoice, tenant and customer by composite FK), of a reading at the customer''s location, or both; its subject, the date the customer gave or sent it (received_on, the caller''s fact) and how (channel). created_at is the database''s (the recorded instant the readers read). Born open; the database moves the status to resolved or withdrawn when that event is recorded, naming it (status_cause_id) at its stamp (status_recorded_at) — the application cannot write the status. Identity is written once; the application inserts only. A reopened matter is a new dispute.';

CREATE TABLE public.dispute_amounts (
    id              uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id       uuid NOT NULL,
    dispute_id      uuid NOT NULL,
    amount          numeric(12,2) NOT NULL,
    determined_by   text NOT NULL,
    effective_on    date NOT NULL,
    created_at      timestamp with time zone DEFAULT now() NOT NULL,
    created_by      uuid,
    recorded_txid   bigint,
    record_seq      bigint,
    CONSTRAINT dispute_amounts_pkey PRIMARY KEY (id),
    CONSTRAINT dispute_amounts_id_tenant_id_key UNIQUE (id, tenant_id),
    CONSTRAINT dispute_amounts_id_dispute_id_key UNIQUE (id, dispute_id),
    CONSTRAINT dispute_amounts_dispute_fkey FOREIGN KEY (dispute_id, tenant_id) REFERENCES public.disputes (id, tenant_id),
    CONSTRAINT dispute_amounts_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users (id),
    CONSTRAINT dispute_amounts_amount_check CHECK (amount > 0),
    CONSTRAINT dispute_amounts_determined_by_check
        CHECK (determined_by = ANY (ARRAY['customer_claim', 'agreed', 'utility', 'regulator_interim']))
);
CREATE INDEX idx_dispute_amounts_dispute ON public.dispute_amounts (dispute_id, effective_on);
CREATE INDEX idx_dispute_amounts_tenant ON public.dispute_amounts (tenant_id);
COMMENT ON TABLE public.dispute_amounts IS
    'v5.4.2-25 (D2). The amount in dispute, add-only: who determined it (the customer''s claim, an agreement, the utility, a regulator''s interim estimate) and from when (effective_on, on or after the dispute was received). A revision is a new row; the amount in force is the latest by effective_on, then recording order. Optional dispute_amount_lines name the bill lines it falls on.';

-- A bill line is named with its bill: (id, invoice_id) identifies a line of
-- that bill (dispute_amount_lines).
ALTER TABLE public.invoice_line_items ADD CONSTRAINT invoice_line_items_id_invoice_id_key UNIQUE (id, invoice_id);

CREATE TABLE public.dispute_amount_lines (
    id                      uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id               uuid NOT NULL,
    dispute_amount_id       uuid NOT NULL,
    invoice_id              uuid,
    invoice_line_item_id    uuid NOT NULL,
    amount                  numeric(12,2) NOT NULL,
    created_at              timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT dispute_amount_lines_pkey PRIMARY KEY (id),
    CONSTRAINT dispute_amount_lines_one_per_line UNIQUE (dispute_amount_id, invoice_line_item_id),
    CONSTRAINT dispute_amount_lines_amount_fkey FOREIGN KEY (dispute_amount_id, tenant_id) REFERENCES public.dispute_amounts (id, tenant_id),
    CONSTRAINT dispute_amount_lines_line_fkey FOREIGN KEY (invoice_line_item_id, invoice_id) REFERENCES public.invoice_line_items (id, invoice_id),
    CONSTRAINT dispute_amount_lines_amount_check CHECK (amount > 0)
);
CREATE INDEX idx_dispute_amount_lines_line ON public.dispute_amount_lines (invoice_line_item_id);
CREATE INDEX idx_dispute_amount_lines_tenant ON public.dispute_amount_lines (tenant_id);
COMMENT ON TABLE public.dispute_amount_lines IS
    'v5.4.2-25 (D2). The bill lines a disputed amount falls on: each a positive line of the dispute''s own bill (invoice_id is the database''s, from the dispute), at most the line''s charge, written in the amount row''s own transaction; the lines of an amount sum to it at commit. Add-only.';

CREATE TABLE public.dispute_determinations (
    id                  uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id           uuid NOT NULL,
    dispute_id          uuid NOT NULL,
    dispute_amount_id   uuid NOT NULL,
    state_code          text NOT NULL,
    service_type        text NOT NULL,
    system_kind         text NOT NULL,
    customer_class      text NOT NULL,
    rule_id             uuid NOT NULL,
    tariff_id           uuid,
    outcome             text NOT NULL,
    sheltered_amount    numeric(12,2) NOT NULL,
    must_pay_amount     numeric(12,2),
    must_pay_component  text,
    shelter_ends_on     date,
    blocks              text[] NOT NULL,
    supersedes_id       uuid,
    inputs              jsonb NOT NULL,
    inputs_fingerprint  text NOT NULL,
    calculated_by       text NOT NULL,
    record_seq          bigint,
    recorded_txid       bigint,
    created_at          timestamp with time zone DEFAULT now() NOT NULL,
    created_by          uuid,
    CONSTRAINT dispute_determinations_pkey PRIMARY KEY (id),
    CONSTRAINT dispute_determinations_id_tenant_id_key UNIQUE (id, tenant_id),
    CONSTRAINT dispute_determinations_id_dispute_id_key UNIQUE (id, dispute_id),
    CONSTRAINT dispute_determinations_supersedes_key UNIQUE (supersedes_id),
    CONSTRAINT dispute_determinations_dispute_fkey FOREIGN KEY (dispute_id, tenant_id) REFERENCES public.disputes (id, tenant_id),
    CONSTRAINT dispute_determinations_amount_fkey FOREIGN KEY (dispute_amount_id, dispute_id) REFERENCES public.dispute_amounts (id, dispute_id),
    CONSTRAINT dispute_determinations_rule_fkey FOREIGN KEY (rule_id) REFERENCES public.dispute_rules (id),
    CONSTRAINT dispute_determinations_tariff_fkey FOREIGN KEY (tariff_id) REFERENCES public.dispute_tariffs (id),
    CONSTRAINT dispute_determinations_class_fkey FOREIGN KEY (state_code, service_type, customer_class)
        REFERENCES public.dispute_customer_classes (state_code, service_type, class_code),
    CONSTRAINT dispute_determinations_system_fkey FOREIGN KEY (system_kind) REFERENCES public.utility_system_kinds (system_kind),
    CONSTRAINT dispute_determinations_supersedes_fkey FOREIGN KEY (supersedes_id, dispute_id) REFERENCES public.dispute_determinations (id, dispute_id),
    CONSTRAINT dispute_determinations_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users (id),
    CONSTRAINT dispute_determinations_outcome_check CHECK (outcome = ANY (ARRAY['sheltered', 'not_sheltered', 'no_terms'])),
    CONSTRAINT dispute_determinations_amounts_check CHECK (sheltered_amount >= 0 AND (must_pay_amount IS NULL OR must_pay_amount >= 0)),
    CONSTRAINT dispute_determinations_inputs_check CHECK (jsonb_typeof(inputs) = 'object' AND inputs_fingerprint ~ '[[:alnum:]]'),
    CONSTRAINT dispute_determinations_calculated_by_check CHECK (calculated_by ~ '[[:alnum:]]')
);
CREATE INDEX idx_dispute_determinations_dispute ON public.dispute_determinations (dispute_id, record_seq);
CREATE INDEX idx_dispute_determinations_rule ON public.dispute_determinations (rule_id);
CREATE INDEX idx_dispute_determinations_tariff ON public.dispute_determinations (tariff_id) WHERE tariff_id IS NOT NULL;
CREATE INDEX idx_dispute_determinations_tenant ON public.dispute_determinations (tenant_id);
COMMENT ON TABLE public.dispute_determinations IS
    'v5.4.2-25 (D3, D4). The core''s reading of a dispute''s shelter, written by tally_app with calculated_by naming the core version, only when the answer changes (memory: design permanent, record on change), as deposit_return_due is. It cites the law row in force for the utility, the class and the received date (a city''s delegation included), the utility''s tariff when one applied (required for a shelter under a delegation), and the amount row it read; it records the outcome (sheltered, not_sheltered, or no_terms — a city with no policy in force), the amounts, the must-pay component of the cited document that governed, the last sheltered day (shelter_ends_on, inclusive; NULL when only resolution ends it) and the cited document''s blocks. The core evaluates; the database checks that the record agrees with the rule it cites (enforce_dispute_determination). A later row names the row it supersedes; one live row per dispute, under the dispute''s lock. Add-only.';

CREATE TABLE public.dispute_events (
    id                          uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id                   uuid NOT NULL,
    dispute_id                  uuid NOT NULL,
    event_type                  text NOT NULL,
    occurred_on                 date NOT NULL,
    stage_id                    text,
    decider_user_id             uuid,
    decider_role                text,
    escalated_to                text,
    outcome                     text,
    correction_ledger_entry_id  uuid,
    correction_credit_id        uuid,
    correction_invoice_id       uuid,
    record_seq                  bigint,
    created_at                  timestamp with time zone DEFAULT now() NOT NULL,
    created_by                  uuid,
    CONSTRAINT dispute_events_pkey PRIMARY KEY (id),
    CONSTRAINT dispute_events_id_dispute_id_key UNIQUE (id, dispute_id),
    CONSTRAINT dispute_events_dispute_fkey FOREIGN KEY (dispute_id, tenant_id) REFERENCES public.disputes (id, tenant_id),
    CONSTRAINT dispute_events_decider_fkey FOREIGN KEY (decider_user_id, tenant_id) REFERENCES public.users (id, tenant_id),
    CONSTRAINT dispute_events_ledger_fkey FOREIGN KEY (correction_ledger_entry_id) REFERENCES public.account_ledger (id),
    CONSTRAINT dispute_events_credit_fkey FOREIGN KEY (correction_credit_id) REFERENCES public.customer_credits (id),
    CONSTRAINT dispute_events_invoice_fkey FOREIGN KEY (correction_invoice_id) REFERENCES public.invoices (id),
    CONSTRAINT dispute_events_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users (id),
    CONSTRAINT dispute_events_type_check
        CHECK (event_type = ANY (ARRAY['opened', 'stage_entered', 'escalated', 'decided', 'resolved', 'withdrawn'])),
    CONSTRAINT dispute_events_escalated_to_check
        CHECK ((event_type = 'escalated') = (escalated_to IS NOT NULL)
               AND (escalated_to IS NULL OR escalated_to = ANY (ARRAY['regulator', 'governing_body']))),
    CONSTRAINT dispute_events_outcome_check
        CHECK ((event_type = 'resolved') = (outcome IS NOT NULL) AND (outcome IS NULL OR outcome = ANY (ARRAY['sustained', 'adjusted', 'waived']))),
    CONSTRAINT dispute_events_decider_role_check
        CHECK (decider_role IS NULL OR decider_role = ANY (ARRAY['designated_employee', 'supervisor', 'manager', 'executive', 'governing_body', 'regulator']))
);
CREATE UNIQUE INDEX dispute_events_one_opened ON public.dispute_events (dispute_id) WHERE event_type = 'opened';
CREATE UNIQUE INDEX dispute_events_one_closing ON public.dispute_events (dispute_id) WHERE event_type IN ('resolved', 'withdrawn');
CREATE INDEX idx_dispute_events_dispute ON public.dispute_events (dispute_id, record_seq);
CREATE INDEX idx_dispute_events_tenant ON public.dispute_events (tenant_id);
COMMENT ON TABLE public.dispute_events IS
    'v5.4.2-25 (D5). What happened on a dispute, add-only: opened (exactly one, first — the database writes it with the dispute), stage_entered and decided (a stage of the live determination''s document, before its decider, by a user of the tenant), escalated (to the regulator or the governing body), resolved (sustained, adjusted or waived; adjusted names the one correction it produced — an adjustment entry, a dispute_resolution credit or a correction bill of the dispute''s customer) and withdrawn. One resolution or withdrawal per dispute: it moves the dispute''s status, and nothing is recorded on the dispute after it. occurred_on is the caller''s fact; created_at the database''s.';

ALTER TABLE public.disputes
    ADD CONSTRAINT disputes_status_cause_fkey FOREIGN KEY (status_cause_id, id) REFERENCES public.dispute_events (id, dispute_id);

DO $$
DECLARE
    t text;
BEGIN
    FOREACH t IN ARRAY ARRAY['disputes', 'dispute_amounts', 'dispute_amount_lines', 'dispute_determinations', 'dispute_events'] LOOP
        EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);
        EXECUTE format('ALTER TABLE public.%I FORCE ROW LEVEL SECURITY', t);
        EXECUTE format('CREATE POLICY tenant_isolation ON public.%I USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())))', t);
        EXECUTE format('CREATE TRIGGER a_stamp_created_at BEFORE INSERT ON public.%I FOR EACH ROW EXECUTE FUNCTION public.stamp_log_created_at()', t);
        EXECUTE format('ALTER TABLE public.%I ENABLE ALWAYS TRIGGER a_stamp_created_at', t);
        EXECUTE format('CREATE TRIGGER no_truncate BEFORE TRUNCATE ON public.%I FOR EACH STATEMENT EXECUTE FUNCTION public.enforce_no_hard_delete()', t);
        EXECUTE format('ALTER TABLE public.%I ENABLE ALWAYS TRIGGER no_truncate', t);
        IF t = 'disputes' THEN
            EXECUTE format('CREATE TRIGGER no_hard_delete BEFORE DELETE ON public.%I FOR EACH ROW EXECUTE FUNCTION public.enforce_no_hard_delete()', t);
            EXECUTE format('ALTER TABLE public.%I ENABLE ALWAYS TRIGGER no_hard_delete', t);
        ELSE
            EXECUTE format('CREATE TRIGGER append_only BEFORE DELETE OR UPDATE ON public.%I FOR EACH ROW EXECUTE FUNCTION public.enforce_append_only()', t);
            EXECUTE format('ALTER TABLE public.%I ENABLE ALWAYS TRIGGER append_only', t);
        END IF;
        EXECUTE format('REVOKE ALL ON public.%I FROM PUBLIC, tally_app, tally_core', t);
        EXECUTE format('GRANT SELECT, INSERT ON public.%I TO tally_app', t);
        EXECUTE format('GRANT SELECT ON public.%I TO tally_core', t);
    END LOOP;
END $$;
REVOKE ALL ON SEQUENCE public.dispute_record_seq FROM PUBLIC, tally_app, tally_core;
GRANT USAGE ON SEQUENCE public.dispute_record_seq TO tally_app;


-- ----------------------------------------------------------------------------
-- 6. The guards (D1-D5)
-- ----------------------------------------------------------------------------
-- The policy's own check comes after BEFORE triggers; a guard that reads the
-- dispute first would answer for a row the policy refuses ("not found").
-- The guards of the records under a dispute ask this first, so another
-- utility's write is refused as row security.
CREATE OR REPLACE FUNCTION public.dispute_tenant_check(p_table text, p_tenant_id uuid) RETURNS void
    LANGUAGE plpgsql STABLE
    SET search_path = public, pg_temp
    AS $$
BEGIN
    IF p_tenant_id IS NOT NULL AND NOT public.is_platform_admin() AND p_tenant_id IS DISTINCT FROM public.get_user_tenant_id()
       AND NOT coalesce((SELECT r.rolsuper OR r.rolbypassrls FROM pg_roles r WHERE r.rolname = current_user), false) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('new row violates row-level security policy for table "%s": a utility writes its own dispute records only (v5.4.2-25)', p_table),
            ERRCODE = 'insufficient_privilege';
    END IF;
END;
$$;
COMMENT ON FUNCTION public.dispute_tenant_check(text, uuid) IS
    'v5.4.2-25. Refuses (42501, as row security would) a dispute record of another tenant than the session''s, before a guard reads anything for it. A platform admin, a superuser and a BYPASSRLS role pass.';
REVOKE ALL ON FUNCTION public.dispute_tenant_check(text, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.dispute_tenant_check(text, uuid) TO tally_app;

CREATE OR REPLACE FUNCTION public.dispute_lock_key(p_dispute_id uuid) RETURNS bigint
    LANGUAGE sql IMMUTABLE
    SET search_path = public, pg_temp
    AS $$
    SELECT hashtextextended('dispute/' || p_dispute_id::text, 0)
$$;
COMMENT ON FUNCTION public.dispute_lock_key(uuid) IS
    'v5.4.2-25. The advisory-lock key of a dispute: the mutex its amounts, determinations and events (other than the database''s opened) share. tally_app holds no UPDATE on disputes, so it cannot row-lock one.';
REVOKE ALL ON FUNCTION public.dispute_lock_key(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.dispute_lock_key(uuid) TO tally_app;

-- Under READ COMMITTED: take the dispute's lock, then read it (a status move
-- committed while this waited is seen).
CREATE OR REPLACE FUNCTION public.dispute_lock(p_dispute_id uuid, p_what text) RETURNS public.disputes
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    d public.disputes%ROWTYPE;
BEGIN
    IF current_setting('transaction_isolation') <> 'read committed' THEN
        RAISE EXCEPTION USING
            MESSAGE = format('%s runs only under READ COMMITTED: the dispute is its records'' mutex, and only READ COMMITTED reads what a writer it waited for committed (v5.4.2-25)', p_what),
            ERRCODE = 'invalid_transaction_state';
    END IF;
    PERFORM pg_advisory_xact_lock(public.dispute_lock_key(p_dispute_id));
    SELECT * INTO d FROM public.disputes x WHERE x.id = p_dispute_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING
            MESSAGE = format('%s: dispute %s not found (or not visible) (v5.4.2-25)', p_what, p_dispute_id),
            ERRCODE = 'foreign_key_violation';
    END IF;
    RETURN d;
END;
$$;
COMMENT ON FUNCTION public.dispute_lock(uuid, text) IS
    'v5.4.2-25. Refuses outside READ COMMITTED (25000); takes the dispute''s advisory lock (held to commit), then reads the dispute and returns it — raising when it is not found or not visible.';
REVOKE ALL ON FUNCTION public.dispute_lock(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.dispute_lock(uuid, text) TO tally_app;

-- D1. A dispute at insert.
CREATE OR REPLACE FUNCTION public.enforce_dispute_insert() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_date      date;
    v_issued    timestamp with time zone;
    v_holder    uuid;
BEGIN
    -- Another tenant's dispute is row security's to refuse: the bill and the
    -- reading of another tenant are not visible here, so nothing below
    -- answers for them first.
    IF NOT EXISTS (SELECT 1 FROM public.dispute_subjects s WHERE s.subject_code = NEW.subject) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('dispute: subject %s is not one of dispute_subjects (v5.4.2-25)', NEW.subject),
            ERRCODE = 'foreign_key_violation';
    END IF;
    IF NEW.invoice_id IS NULL AND NEW.reading_id IS NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = 'dispute: it names a bill, a reading, or both [D1a] (v5.4.2-25)',
            ERRCODE = 'check_violation';
    END IF;
    IF NEW.status IS DISTINCT FROM 'open' OR NEW.status_cause_id IS NOT NULL OR NEW.status_recorded_at IS NOT NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = 'dispute: a dispute is born open, naming no cause; it is resolved or withdrawn by its event [D1h] (v5.4.2-25)',
            ERRCODE = 'check_violation';
    END IF;
    -- A bill another customer's or tenant's is the composite FK's to refuse.
    IF NEW.invoice_id IS NOT NULL THEN
        SELECT i.invoice_date, i.first_issued_at INTO v_date, v_issued FROM public.invoices i WHERE i.id = NEW.invoice_id;
        IF FOUND THEN
            IF v_issued IS NULL THEN
                RAISE EXCEPTION USING
                    MESSAGE = format('dispute: bill %s was never issued — a draft is corrected, not disputed [D1b] (v5.4.2-25)', NEW.invoice_id),
                    ERRCODE = 'check_violation';
            END IF;
            IF NEW.received_on < v_date THEN
                RAISE EXCEPTION USING
                    MESSAGE = format('dispute: received %s, before the bill''s date %s [D1d] (v5.4.2-25)', NEW.received_on, v_date),
                    ERRCODE = 'check_violation';
            END IF;
        END IF;
    END IF;
    IF NEW.reading_id IS NOT NULL THEN
        SELECT r.reading_date, l.customer_id INTO v_date, v_holder
          FROM public.meter_readings r
          JOIN public.meters m ON m.id = r.meter_id
          JOIN public.service_locations l ON l.id = m.location_id
         WHERE r.id = NEW.reading_id;
        IF FOUND THEN
            IF v_holder IS DISTINCT FROM NEW.customer_id THEN
                RAISE EXCEPTION USING
                    MESSAGE = format('dispute: reading %s is at a location of another customer [D1c] (v5.4.2-25)', NEW.reading_id),
                    ERRCODE = 'check_violation';
            END IF;
            IF NEW.received_on < v_date THEN
                RAISE EXCEPTION USING
                    MESSAGE = format('dispute: received %s, before the reading was taken on %s [D1d] (v5.4.2-25)', NEW.received_on, v_date),
                    ERRCODE = 'check_violation';
            END IF;
        END IF;
    END IF;
    IF NEW.received_on > current_date THEN
        RAISE EXCEPTION USING
            MESSAGE = format('dispute: received %s, a date not yet come [D1e] (v5.4.2-25)', NEW.received_on),
            ERRCODE = 'check_violation';
    END IF;
    NEW.recorded_txid := txid_current();
    BEGIN
        NEW.created_by := NULLIF(current_setting('app.user_id', true), '')::uuid;
    EXCEPTION WHEN OTHERS THEN
        NEW.created_by := NULL;
    END;
    RETURN NEW;
END;
$$;
COMMENT ON FUNCTION public.enforce_dispute_insert() IS
    'v5.4.2-25 (D1). BEFORE INSERT on disputes: the subject is a dispute_subjects row (23503); a bill or a reading named [D1a]; born open with no cause [D1h]; the bill issued (first_issued_at) [D1b]; the reading at a location of the dispute''s customer [D1c]; received on or after the bill''s date and the reading''s [D1d] and not after today [D1e]; stamps created_by and recorded_txid (created_at is a_stamp_created_at''s). The bill''s tenant and customer are the composite FK''s.';
REVOKE ALL ON FUNCTION public.enforce_dispute_insert() FROM PUBLIC, tally_app, tally_core;
CREATE TRIGGER b_enforce_dispute_insert BEFORE INSERT ON public.disputes FOR EACH ROW EXECUTE FUNCTION public.enforce_dispute_insert();
ALTER TABLE public.disputes ENABLE ALWAYS TRIGGER b_enforce_dispute_insert;

-- D5. The database writes the opened event with the dispute.
CREATE OR REPLACE FUNCTION public.dispute_opened_event() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
BEGIN
    INSERT INTO public.dispute_events (tenant_id, dispute_id, event_type, occurred_on, created_at)
    VALUES (NEW.tenant_id, NEW.id, 'opened', NEW.received_on, NEW.created_at);
    RETURN NULL;
END;
$$;
COMMENT ON FUNCTION public.dispute_opened_event() IS
    'v5.4.2-25 (D5). AFTER INSERT on disputes: writes the dispute''s opened event, on its received date, at its recorded instant. The only path that writes one (enforce_dispute_event).';
REVOKE ALL ON FUNCTION public.dispute_opened_event() FROM PUBLIC, tally_app, tally_core;
CREATE TRIGGER z_dispute_opened_event AFTER INSERT ON public.disputes FOR EACH ROW EXECUTE FUNCTION public.dispute_opened_event();
ALTER TABLE public.disputes ENABLE ALWAYS TRIGGER z_dispute_opened_event;

-- D1. A dispute is written once; only the status move from its event
-- changes it.
CREATE OR REPLACE FUNCTION public.enforce_dispute_update() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    c_moved CONSTANT text[] := ARRAY['status', 'status_cause_id', 'status_recorded_at'];
BEGIN
    IF (to_jsonb(NEW) - c_moved) IS DISTINCT FROM (to_jsonb(OLD) - c_moved) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('dispute %s: its identity is written once, at insert [D1f] (v5.4.2-25)', OLD.id),
            ERRCODE = 'check_violation';
    END IF;
    IF NEW.status IS NOT DISTINCT FROM OLD.status AND NEW.status_cause_id IS NOT DISTINCT FROM OLD.status_cause_id
       AND NEW.status_recorded_at IS NOT DISTINCT FROM OLD.status_recorded_at THEN
        RETURN NEW;
    END IF;
    -- The move is the event's: to the type of a resolution or withdrawal of
    -- this dispute, naming it at its stamp. There is at most one such event
    -- (dispute_events_one_closing), and it is written only while the dispute
    -- is open (enforce_dispute_event), so this also keeps the move forward.
    IF NOT EXISTS (SELECT 1 FROM public.dispute_events e
                    WHERE e.id = NEW.status_cause_id AND e.dispute_id = NEW.id AND e.event_type = NEW.status
                      AND e.event_type IN ('resolved', 'withdrawn') AND e.created_at = NEW.status_recorded_at) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('dispute %s: its status moves only when its resolution or withdrawal is recorded, from open, naming that event [D1g] (v5.4.2-25)', OLD.id),
            ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$;
COMMENT ON FUNCTION public.enforce_dispute_update() IS
    'v5.4.2-25 (D1). BEFORE UPDATE on disputes: nothing but the status, its cause and its stamp changes [D1f]; and those only to the type of the dispute''s resolution or withdrawal event, naming it at its created_at — the move dispute_move_status makes when that event is recorded; never otherwise, the owner included [D1g].';
REVOKE ALL ON FUNCTION public.enforce_dispute_update() FROM PUBLIC, tally_app, tally_core;
CREATE TRIGGER b_enforce_dispute_update BEFORE UPDATE ON public.disputes FOR EACH ROW EXECUTE FUNCTION public.enforce_dispute_update();
ALTER TABLE public.disputes ENABLE ALWAYS TRIGGER b_enforce_dispute_update;

-- D2. A disputed amount.
CREATE OR REPLACE FUNCTION public.enforce_dispute_amount() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    d public.disputes%ROWTYPE;
BEGIN
    PERFORM public.dispute_tenant_check('dispute_amounts', NEW.tenant_id);
    d := public.dispute_lock(NEW.dispute_id, 'a disputed amount');
    IF d.status <> 'open' THEN
        RAISE EXCEPTION USING
            MESSAGE = format('disputed amount: dispute %s is %s — nothing is recorded on it after [D2e] (v5.4.2-25)', d.id, d.status),
            ERRCODE = 'check_violation';
    END IF;
    IF NEW.effective_on < d.received_on OR NEW.effective_on > current_date OR NEW.created_at < d.created_at THEN
        RAISE EXCEPTION USING
            MESSAGE = format('disputed amount: effective %s, outside the dispute''s received date %s and today, or recorded before the dispute [D2d] (v5.4.2-25)',
                             NEW.effective_on, d.received_on),
            ERRCODE = 'check_violation';
    END IF;
    NEW.recorded_txid := txid_current();
    NEW.record_seq    := nextval('public.dispute_record_seq');
    BEGIN
        NEW.created_by := NULLIF(current_setting('app.user_id', true), '')::uuid;
    EXCEPTION WHEN OTHERS THEN
        NEW.created_by := NULL;
    END;
    RETURN NEW;
END;
$$;
COMMENT ON FUNCTION public.enforce_dispute_amount() IS
    'v5.4.2-25 (D2). BEFORE INSERT on dispute_amounts: the writer''s own tenant; under the dispute''s lock (READ COMMITTED), the dispute is open [D2e]; effective on or after it was received and not after today, recorded no earlier than the dispute [D2d]; stamps created_by, recorded_txid (its lines are written in this transaction) and record_seq.';
REVOKE ALL ON FUNCTION public.enforce_dispute_amount() FROM PUBLIC, tally_app, tally_core;
CREATE TRIGGER b_enforce_dispute_amount BEFORE INSERT ON public.dispute_amounts FOR EACH ROW EXECUTE FUNCTION public.enforce_dispute_amount();
ALTER TABLE public.dispute_amounts ENABLE ALWAYS TRIGGER b_enforce_dispute_amount;

CREATE OR REPLACE FUNCTION public.enforce_dispute_amount_line() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_txid      bigint;
    v_invoice   uuid;
    v_charge    numeric;
BEGIN
    PERFORM public.dispute_tenant_check('dispute_amount_lines', NEW.tenant_id);
    SELECT a.recorded_txid, d.invoice_id INTO v_txid, v_invoice
      FROM public.dispute_amounts a JOIN public.disputes d ON d.id = a.dispute_id
     WHERE a.id = NEW.dispute_amount_id AND a.tenant_id = NEW.tenant_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING
            MESSAGE = format('dispute_amount_lines: amount row %s not found (or not visible) (v5.4.2-25)', NEW.dispute_amount_id),
            ERRCODE = 'foreign_key_violation';
    END IF;
    IF v_invoice IS NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('dispute_amount_lines: amount row %s is of a dispute that names no bill — a reading dispute has no bill lines to name (v5.4.2-25)', NEW.dispute_amount_id),
            ERRCODE = 'foreign_key_violation';
    END IF;
    IF v_txid IS DISTINCT FROM txid_current() THEN
        RAISE EXCEPTION USING
            MESSAGE = format('disputed amount %s: its lines are written with it, in its own transaction — a revision is a new amount row [D2f] (v5.4.2-25)', NEW.dispute_amount_id),
            ERRCODE = 'check_violation';
    END IF;
    -- The bill is the dispute's, not the caller's: a line of another bill
    -- fails the (line, bill) foreign key.
    NEW.invoice_id := v_invoice;
    SELECT l.amount INTO v_charge FROM public.invoice_line_items l WHERE l.id = NEW.invoice_line_item_id AND l.invoice_id = v_invoice;
    IF FOUND AND (v_charge <= 0 OR NEW.amount > v_charge) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('disputed amount %s: %s on line %s, which charges %s — only a charge is disputed, and at most what it charges [D2c] (v5.4.2-25)',
                             NEW.dispute_amount_id, NEW.amount, NEW.invoice_line_item_id, v_charge),
            ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$;
COMMENT ON FUNCTION public.enforce_dispute_amount_line() IS
    'v5.4.2-25 (D2). BEFORE INSERT on dispute_amount_lines: the writer''s own tenant; the amount row''s dispute names a bill (23503 otherwise); the line is written in the amount row''s transaction [D2f]; invoice_id is set to the dispute''s bill (the (line, bill) FK then refuses a line of another bill); the line is a charge and the amount at most what it charges [D2c].';
REVOKE ALL ON FUNCTION public.enforce_dispute_amount_line() FROM PUBLIC, tally_app, tally_core;
CREATE TRIGGER b_enforce_dispute_amount_line BEFORE INSERT ON public.dispute_amount_lines FOR EACH ROW EXECUTE FUNCTION public.enforce_dispute_amount_line();
ALTER TABLE public.dispute_amount_lines ENABLE ALWAYS TRIGGER b_enforce_dispute_amount_line;

CREATE OR REPLACE FUNCTION public.enforce_dispute_amount_lines_sum() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_amount numeric;
    v_sum    numeric;
BEGIN
    SELECT a.amount, (SELECT sum(l.amount) FROM public.dispute_amount_lines l WHERE l.dispute_amount_id = a.id)
      INTO v_amount, v_sum
      FROM public.dispute_amounts a WHERE a.id = NEW.dispute_amount_id;
    IF v_sum IS DISTINCT FROM v_amount THEN
        RAISE EXCEPTION USING
            MESSAGE = format('disputed amount %s is %s; its lines add up to %s [D2a] (v5.4.2-25)', NEW.dispute_amount_id, v_amount, v_sum),
            ERRCODE = 'check_violation';
    END IF;
    RETURN NULL;
END;
$$;
COMMENT ON FUNCTION public.enforce_dispute_amount_lines_sum() IS
    'v5.4.2-25 (D2). Deferred constraint trigger, AFTER INSERT on dispute_amount_lines: at commit an amount with lines equals their sum [D2a].';
REVOKE ALL ON FUNCTION public.enforce_dispute_amount_lines_sum() FROM PUBLIC, tally_app, tally_core;
CREATE CONSTRAINT TRIGGER z_enforce_dispute_amount_lines_sum AFTER INSERT ON public.dispute_amount_lines
    DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.enforce_dispute_amount_lines_sum();
ALTER TABLE public.dispute_amount_lines ENABLE ALWAYS TRIGGER z_enforce_dispute_amount_lines_sum;

-- The document a determination cites: its tariff's when one applied, else
-- its law row's.
CREATE OR REPLACE FUNCTION public.dispute_determination_terms(p_rule_id uuid, p_tariff_id uuid) RETURNS jsonb
    LANGUAGE sql STABLE
    SET search_path = public, pg_temp
    AS $$
    SELECT CASE WHEN p_tariff_id IS NOT NULL
                THEN (SELECT t.terms FROM public.dispute_tariffs t WHERE t.id = p_tariff_id)
                ELSE (SELECT r.terms FROM public.dispute_rules r WHERE r.id = p_rule_id) END
$$;
COMMENT ON FUNCTION public.dispute_determination_terms(uuid, uuid) IS
    'v5.4.2-25 (D4). The document a determination cites: the tariff''s when it names one (the policy that applied), else the law row''s. Invoker rights: RLS applies to the tariff.';
REVOKE ALL ON FUNCTION public.dispute_determination_terms(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.dispute_determination_terms(uuid, uuid) TO tally_app, tally_core;

-- D3, D4. A determination: the record agrees with the rule it cites.
CREATE OR REPLACE FUNCTION public.enforce_dispute_determination() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    d           public.disputes%ROWTYPE;
    a           public.dispute_amounts%ROWTYPE;
    r           public.dispute_rules%ROWTYPE;
    t           public.dispute_tariffs%ROWTYPE;
    p           public.dispute_determinations%ROWTYPE;
    v_expected  uuid;
    v_msg       text;
    v_doc       jsonb;
    v_blocks    text[];
BEGIN
    -- An outcome outside the three is the CHECK's to refuse: each check
    -- below names the outcome it applies to.
    PERFORM public.dispute_tenant_check('dispute_determinations', NEW.tenant_id);
    d := public.dispute_lock(NEW.dispute_id, 'a dispute determination');
    IF d.status <> 'open' THEN
        RAISE EXCEPTION USING
            MESSAGE = format('dispute determination: dispute %s is %s — nothing is determined after it [D4k] (v5.4.2-25)', d.id, d.status),
            ERRCODE = 'check_violation';
    END IF;
    SELECT * INTO a FROM public.dispute_amounts x WHERE x.id = NEW.dispute_amount_id;
    IF NOT FOUND OR a.dispute_id <> d.id OR a.created_at > NEW.created_at THEN
        RAISE EXCEPTION USING
            MESSAGE = format('dispute determination: amount row %s is not an amount of dispute %s recorded before it [D4j] (v5.4.2-25)', NEW.dispute_amount_id, d.id),
            ERRCODE = 'check_violation';
    END IF;
    -- One live row: a first row where the dispute has none, else a successor
    -- of the live row, recorded no earlier than it.
    IF NEW.supersedes_id IS NULL THEN
        IF EXISTS (SELECT 1 FROM public.dispute_determinations x WHERE x.dispute_id = d.id) THEN
            RAISE EXCEPTION USING
                MESSAGE = format('dispute determination: dispute %s already has a determination; a new answer names the live row it supersedes [D4m] (v5.4.2-25)', d.id),
                ERRCODE = 'check_violation';
        END IF;
    ELSE
        SELECT * INTO p FROM public.dispute_determinations x WHERE x.id = NEW.supersedes_id;
        IF NOT FOUND OR p.dispute_id <> d.id OR p.created_at > NEW.created_at
           OR EXISTS (SELECT 1 FROM public.dispute_determinations x WHERE x.supersedes_id = p.id) THEN
            RAISE EXCEPTION USING
                MESSAGE = format('dispute determination: it may supersede only the live determination of dispute %s; %s is not it [D4m] (v5.4.2-25)', d.id, NEW.supersedes_id),
                ERRCODE = 'check_violation';
        END IF;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.dispute_customer_classes c
                    WHERE c.state_code = NEW.state_code AND c.service_type = NEW.service_type AND c.class_code = NEW.customer_class) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('dispute determination: class %s is not one of dispute_customer_classes for %s %s (v5.4.2-25)', NEW.customer_class, NEW.state_code, NEW.service_type),
            ERRCODE = 'foreign_key_violation';
    END IF;

    -- The law row: the one in force for this utility (its profile for the
    -- recorded state, service and system: owner type and jurisdiction), the
    -- recorded class and the received date.
    BEGIN
        v_expected := public.rule_law_row_as_of('public.dispute_rules', NEW.tenant_id, NEW.service_type, NEW.system_kind, NEW.state_code,
                                                jsonb_build_object('customer_class', NEW.customer_class), d.received_on);
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
        RAISE EXCEPTION USING
            MESSAGE = format('dispute determination: no law row is in force for this utility on %s: %s [D4a] (v5.4.2-25)', d.received_on, v_msg),
            ERRCODE = 'check_violation';
    END;
    IF v_expected IS DISTINCT FROM NEW.rule_id THEN
        RAISE EXCEPTION USING
            MESSAGE = format('dispute determination: law row %s is not the law for this utility''s owner type and system on %s; its law row is %s [D4a] (v5.4.2-25)',
                             NEW.rule_id, d.received_on, v_expected),
            ERRCODE = 'check_violation';
    END IF;
    PERFORM public.rule_law_row_cite('public.dispute_rules', NEW.rule_id, NEW.tenant_id, NEW.service_type, NEW.system_kind, NEW.state_code,
                                     jsonb_build_object('customer_class', NEW.customer_class), d.received_on);
    SELECT * INTO r FROM public.dispute_rules x WHERE x.id = NEW.rule_id;

    -- The tariff: the utility's own, of its state, service and system, in
    -- force on the received date.
    IF NEW.tariff_id IS NOT NULL THEN
        SELECT * INTO t FROM public.dispute_tariffs x WHERE x.id = NEW.tariff_id;
        IF NOT FOUND OR t.tenant_id <> NEW.tenant_id OR t.state_code <> NEW.state_code OR t.service_type <> NEW.service_type
           OR t.system_kind <> NEW.system_kind THEN
            RAISE EXCEPTION USING
                MESSAGE = format('dispute determination: tariff %s is not this utility''s policy for %s %s (%s) [D4f] (v5.4.2-25)',
                                 NEW.tariff_id, NEW.state_code, NEW.service_type, NEW.system_kind),
                ERRCODE = 'check_violation';
        END IF;
        IF NOT daterange(t.effective_from, t.effective_to, '[)') @> d.received_on THEN
            RAISE EXCEPTION USING
                MESSAGE = format('dispute determination: tariff %s is not in force on %s, the day the dispute was received [D4c] (v5.4.2-25)', NEW.tariff_id, d.received_on),
                ERRCODE = 'check_violation';
        END IF;
        PERFORM public.rule_row_cite('public.dispute_tariffs', NEW.tariff_id, d.received_on);
    END IF;

    -- A delegation shelters only under the utility's policy (K-07), and says
    -- "no terms" only when it has none in force. Only a delegation says it.
    IF r.terms ->> 'governs' = 'delegated_to_utility' AND NEW.tariff_id IS NULL THEN
        IF NEW.outcome <> 'no_terms' THEN
            RAISE EXCEPTION USING
                MESSAGE = format('dispute determination: law row %s leaves the dispute to the utility, and no tariff is cited — a city''s shelter is its own policy (K-07: no assumed default) [D4d] (v5.4.2-25)', NEW.rule_id),
                ERRCODE = 'check_violation';
        END IF;
        IF public.rule_tariff_row_as_of('public.dispute_tariffs', NEW.tenant_id, NEW.service_type, NEW.system_kind, NEW.state_code, '{}'::jsonb, d.received_on) IS NOT NULL THEN
            RAISE EXCEPTION USING
                MESSAGE = format('dispute determination: "no terms", but the utility has a dispute policy in force on %s — cite it [D4e] (v5.4.2-25)', d.received_on),
                ERRCODE = 'check_violation';
        END IF;
    END IF;

    -- The outcome's shape (contract 5).
    IF NEW.outcome = 'no_terms' AND (NEW.sheltered_amount <> 0 OR NEW.must_pay_amount IS NOT NULL OR NEW.must_pay_component IS NOT NULL
                                     OR NEW.shelter_ends_on IS NOT NULL OR cardinality(NEW.blocks) > 0 OR NEW.tariff_id IS NOT NULL
                                     OR r.terms ->> 'governs' <> 'delegated_to_utility') THEN
        RAISE EXCEPTION USING
            MESSAGE = 'dispute determination: "no terms" is a delegation with no policy in force: it cites no tariff, shelters nothing, blocks nothing and names no must-pay [D4n] (v5.4.2-25)',
            ERRCODE = 'check_violation';
    END IF;
    IF NEW.outcome = 'not_sheltered' AND (NEW.sheltered_amount <> 0 OR cardinality(NEW.blocks) > 0 OR NEW.shelter_ends_on IS NOT NULL
                                          OR NEW.must_pay_amount IS NULL OR NEW.must_pay_component IS NULL) THEN
        RAISE EXCEPTION USING
            MESSAGE = 'dispute determination: "not sheltered" shelters nothing and blocks nothing, and names the must-pay component that governed and its amount [D4n] (v5.4.2-25)',
            ERRCODE = 'check_violation';
    END IF;
    IF NEW.outcome = 'sheltered' AND (NEW.must_pay_amount IS NULL OR NEW.must_pay_component IS NULL) THEN
        RAISE EXCEPTION USING
            MESSAGE = 'dispute determination: "sheltered" names the must-pay component that governed and its amount [D4n] (v5.4.2-25)',
            ERRCODE = 'check_violation';
    END IF;

    IF NEW.outcome <> 'no_terms' THEN
        v_doc := public.dispute_determination_terms(NEW.rule_id, NEW.tariff_id);
        IF NOT coalesce(v_doc #>> '{must_pay,id}' = NEW.must_pay_component, false) THEN
            RAISE EXCEPTION USING
                MESSAGE = format('dispute determination: must-pay component %s is not the cited document''s (%s) [D4g] (v5.4.2-25)', NEW.must_pay_component, v_doc #>> '{must_pay,id}'),
                ERRCODE = 'check_violation';
        END IF;
        IF NEW.outcome = 'sheltered' THEN
            SELECT coalesce(array_agg(c ORDER BY c), '{}') INTO v_blocks FROM jsonb_array_elements_text(v_doc #> '{blocks,codes}') c;
            IF (SELECT coalesce(array_agg(DISTINCT b ORDER BY b), '{}') FROM unnest(NEW.blocks) b) IS DISTINCT FROM v_blocks
               OR cardinality(NEW.blocks) <> cardinality(v_blocks) THEN
                RAISE EXCEPTION USING
                    MESSAGE = format('dispute determination: it records the blocks %s; the cited document''s are %s — a record claims no other shelter than its rule [D4h] (v5.4.2-25)', NEW.blocks, v_blocks),
                    ERRCODE = 'check_violation';
            END IF;
        END IF;
    END IF;
    IF NEW.sheltered_amount < 0 OR NEW.sheltered_amount > a.amount OR NEW.must_pay_amount < 0 THEN
        RAISE EXCEPTION USING
            MESSAGE = format('dispute determination: %s sheltered of the %s in dispute, %s to pay — sheltered is between 0 and the amount, to pay at least 0 [D4i] (v5.4.2-25)',
                             NEW.sheltered_amount, a.amount, NEW.must_pay_amount),
            ERRCODE = 'check_violation';
    END IF;
    IF NEW.shelter_ends_on < d.received_on THEN
        RAISE EXCEPTION USING
            MESSAGE = format('dispute determination: the shelter ends on %s, before the dispute was received on %s [D4o] (v5.4.2-25)', NEW.shelter_ends_on, d.received_on),
            ERRCODE = 'check_violation';
    END IF;

    NEW.recorded_txid := txid_current();
    NEW.record_seq    := nextval('public.dispute_record_seq');
    BEGIN
        NEW.created_by := NULLIF(current_setting('app.user_id', true), '')::uuid;
    EXCEPTION WHEN OTHERS THEN
        NEW.created_by := NULL;
    END;
    RETURN NEW;
END;
$$;
COMMENT ON FUNCTION public.enforce_dispute_determination() IS
    'v5.4.2-25 (D3, D4). BEFORE INSERT on dispute_determinations — record integrity, not evaluation (the core''s): the writer''s own tenant; under the dispute''s lock (READ COMMITTED) the dispute is open [D4k]; the amount row is the dispute''s, recorded before [D4j]; one live row — a first row, or a successor of the live row [D4m]; the class is the state''s (23503); the law row is the one in force for the utility''s profile in the recorded state, service and system, for the recorded class, on the received date (rule_law_row_cite) [D4a]; a tariff is the utility''s own policy for that state, service and system [D4f] and in force on the received date (rule_row_cite) [D4c]; under a delegation with no tariff, only "no terms" [D4d], and only when no policy is in force [D4e]; the outcome''s shape [D4n]; the must-pay component [D4g] and, for a shelter, the blocks [D4h] are the cited document''s (the tariff''s when one applied); sheltered between 0 and the amount, to pay at least 0 [D4i]; the shelter ends no earlier than the received date [D4o]. Stamps created_by, recorded_txid and record_seq.';
REVOKE ALL ON FUNCTION public.enforce_dispute_determination() FROM PUBLIC, tally_app, tally_core;
CREATE TRIGGER b_enforce_dispute_determination BEFORE INSERT ON public.dispute_determinations FOR EACH ROW EXECUTE FUNCTION public.enforce_dispute_determination();
ALTER TABLE public.dispute_determinations ENABLE ALWAYS TRIGGER b_enforce_dispute_determination;

-- The live determination of a dispute (none superseding it).
CREATE OR REPLACE FUNCTION public.dispute_live_determination(p_dispute_id uuid) RETURNS public.dispute_determinations
    LANGUAGE sql STABLE
    SET search_path = public, pg_temp
    AS $$
    SELECT x.* FROM public.dispute_determinations x
     WHERE x.dispute_id = p_dispute_id
       AND NOT EXISTS (SELECT 1 FROM public.dispute_determinations y WHERE y.supersedes_id = x.id)
     ORDER BY x.record_seq DESC LIMIT 1
$$;
COMMENT ON FUNCTION public.dispute_live_determination(uuid) IS
    'v5.4.2-25. A dispute''s live determination: the one no other supersedes, or NULL. Invoker rights.';
REVOKE ALL ON FUNCTION public.dispute_live_determination(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.dispute_live_determination(uuid) TO tally_app, tally_core;

-- D5. An event.
CREATE OR REPLACE FUNCTION public.enforce_dispute_event() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    d       public.disputes%ROWTYPE;
    x       public.dispute_determinations%ROWTYPE;
    v_stage jsonb;
    v_cust  uuid;
    v_kind  text;
    v_n     integer;
BEGIN
    PERFORM public.dispute_tenant_check('dispute_events', NEW.tenant_id);
    -- The opened event is the database's, written in the dispute's own
    -- statement (dispute_opened_event): first, on the received date. Any
    -- later one finds it there.
    IF NEW.event_type = 'opened' THEN
        SELECT * INTO d FROM public.disputes y WHERE y.id = NEW.dispute_id;
        IF NOT FOUND OR NEW.occurred_on IS DISTINCT FROM d.received_on
           OR EXISTS (SELECT 1 FROM public.dispute_events e WHERE e.dispute_id = NEW.dispute_id) THEN
            RAISE EXCEPTION USING
                MESSAGE = 'dispute event: the opened event is the database''s, written with the dispute [D5a] (v5.4.2-25)',
                ERRCODE = 'check_violation';
        END IF;
        NEW.record_seq := nextval('public.dispute_record_seq');
        RETURN NEW;
    END IF;
    d := public.dispute_lock(NEW.dispute_id, 'a dispute event');
    IF d.status <> 'open' THEN
        RAISE EXCEPTION USING
            MESSAGE = format('dispute event: dispute %s is %s (event %s) — one resolution or withdrawal, and nothing after it [D5f] (v5.4.2-25)', d.id, d.status, d.status_cause_id),
            ERRCODE = 'check_violation';
    END IF;
    IF NEW.occurred_on < d.received_on OR NEW.occurred_on > current_date OR NEW.created_at < d.created_at THEN
        RAISE EXCEPTION USING
            MESSAGE = format('dispute event: %s on %s, outside the dispute''s received date %s and today, or recorded before the dispute [D5g] (v5.4.2-25)',
                             NEW.event_type, NEW.occurred_on, d.received_on),
            ERRCODE = 'check_violation';
    END IF;

    -- Outcomes and corrections: a resolution has an outcome; adjusted names
    -- exactly one correction; nothing else names one.
    v_n := (NEW.correction_ledger_entry_id IS NOT NULL)::integer + (NEW.correction_credit_id IS NOT NULL)::integer
         + (NEW.correction_invoice_id IS NOT NULL)::integer;
    IF (NEW.event_type = 'resolved') <> (NEW.outcome IS NOT NULL)
       OR (NEW.outcome = 'adjusted' AND v_n <> 1)
       OR (NEW.outcome IS DISTINCT FROM 'adjusted' AND v_n <> 0) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('dispute event: a resolution carries its outcome (sustained, adjusted or waived), an adjusted one names the one correction it produced, and nothing else names one (%s, outcome %s, %s corrections) [D5d] (v5.4.2-25)',
                             NEW.event_type, NEW.outcome, v_n),
            ERRCODE = 'check_violation';
    END IF;
    IF NEW.correction_ledger_entry_id IS NOT NULL THEN
        SELECT g.customer_id, g.transaction_type INTO v_cust, v_kind FROM public.account_ledger g WHERE g.id = NEW.correction_ledger_entry_id;
        IF v_cust IS DISTINCT FROM d.customer_id OR v_kind IS DISTINCT FROM 'adjustment' THEN
            RAISE EXCEPTION USING
                MESSAGE = format('dispute event: ledger entry %s is not an adjustment of the dispute''s customer [D5e] (v5.4.2-25)', NEW.correction_ledger_entry_id),
                ERRCODE = 'check_violation';
        END IF;
    ELSIF NEW.correction_credit_id IS NOT NULL THEN
        SELECT c.customer_id, c.origin_type INTO v_cust, v_kind FROM public.customer_credits c WHERE c.id = NEW.correction_credit_id;
        IF v_cust IS DISTINCT FROM d.customer_id OR v_kind IS DISTINCT FROM 'dispute_resolution' THEN
            RAISE EXCEPTION USING
                MESSAGE = format('dispute event: credit %s is not a dispute_resolution credit of the dispute''s customer [D5e] (v5.4.2-25)', NEW.correction_credit_id),
                ERRCODE = 'check_violation';
        END IF;
    ELSIF NEW.correction_invoice_id IS NOT NULL THEN
        SELECT i.customer_id INTO v_cust FROM public.invoices i WHERE i.id = NEW.correction_invoice_id;
        IF v_cust IS DISTINCT FROM d.customer_id THEN
            RAISE EXCEPTION USING
                MESSAGE = format('dispute event: bill %s is not a bill of the dispute''s customer [D5e] (v5.4.2-25)', NEW.correction_invoice_id),
                ERRCODE = 'check_violation';
        END IF;
    END IF;

    -- Stages: a stage of the live determination's document, before its
    -- decider, by a user; no other event names one.
    IF NEW.event_type IN ('stage_entered', 'decided') THEN
        x := public.dispute_live_determination(d.id);
        IF x.id IS NULL THEN
            RAISE EXCEPTION USING
                MESSAGE = format('dispute event: %s names a stage, and dispute %s has no determination whose document has stages [D5c] (v5.4.2-25)', NEW.event_type, d.id),
                ERRCODE = 'check_violation';
        END IF;
        SELECT s INTO v_stage FROM jsonb_array_elements(coalesce(public.dispute_determination_terms(x.rule_id, x.tariff_id) -> 'stages', '[]'::jsonb)) s
         WHERE s ->> 'id' = NEW.stage_id;
        IF v_stage IS NULL OR NEW.decider_role IS DISTINCT FROM v_stage ->> 'decider' OR NEW.decider_user_id IS NULL THEN
            RAISE EXCEPTION USING
                MESSAGE = format('dispute event: stage %s before %s is not a stage of the live determination''s document, before its decider, by a user (its stage is %s) [D5b] (v5.4.2-25)',
                                 NEW.stage_id, NEW.decider_role, v_stage),
                ERRCODE = 'check_violation';
        END IF;
    ELSIF NEW.stage_id IS NOT NULL OR NEW.decider_role IS NOT NULL OR NEW.decider_user_id IS NOT NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('dispute event: only a stage event names a stage and its decider (%s) [D5b] (v5.4.2-25)', NEW.event_type),
            ERRCODE = 'check_violation';
    END IF;

    NEW.record_seq := nextval('public.dispute_record_seq');
    BEGIN
        NEW.created_by := NULLIF(current_setting('app.user_id', true), '')::uuid;
    EXCEPTION WHEN OTHERS THEN
        NEW.created_by := NULL;
    END;
    RETURN NEW;
END;
$$;
COMMENT ON FUNCTION public.enforce_dispute_event() IS
    'v5.4.2-25 (D5). BEFORE INSERT on dispute_events: the writer''s own tenant; an opened event only from dispute_opened_event, first, on the received date [D5a]; otherwise under the dispute''s lock (READ COMMITTED) the dispute is open [D5f]; dated between the received date and today, recorded no earlier than the dispute [D5g]; a resolution carries its outcome, an adjusted one names exactly one correction and nothing else names one [D5d]; the correction is an adjustment entry, a dispute_resolution credit or a bill of the dispute''s customer [D5e]; a stage event needs a live determination [D5c] and names a stage of its document before that stage''s decider, by a user, and no other event names one [D5b]. Stamps created_by and record_seq.';
REVOKE ALL ON FUNCTION public.enforce_dispute_event() FROM PUBLIC, tally_app, tally_core;
CREATE TRIGGER b_enforce_dispute_event BEFORE INSERT ON public.dispute_events FOR EACH ROW EXECUTE FUNCTION public.enforce_dispute_event();
ALTER TABLE public.dispute_events ENABLE ALWAYS TRIGGER b_enforce_dispute_event;

-- D1. The status move: the database's, from the resolution or withdrawal
-- event (residual R7: SECURITY DEFINER, as tally_app holds no UPDATE on
-- disputes; enforce_dispute_update checks the move against the event).
CREATE OR REPLACE FUNCTION public.dispute_move_status() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $$
BEGIN
    UPDATE public.disputes SET status = NEW.event_type, status_cause_id = NEW.id, status_recorded_at = NEW.created_at
     WHERE id = NEW.dispute_id AND tenant_id = NEW.tenant_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING
            MESSAGE = format('dispute event %s: its dispute %s was not found to move (v5.4.2-25)', NEW.id, NEW.dispute_id),
            ERRCODE = 'foreign_key_violation';
    END IF;
    RETURN NULL;
END;
$$;
COMMENT ON FUNCTION public.dispute_move_status() IS
    'v5.4.2-25 (D1; memory: guards must act). AFTER INSERT on dispute_events, for a resolved or withdrawn event: moves its dispute''s status to the event''s type, naming the event (status_cause_id) at its created_at (status_recorded_at). SECURITY DEFINER because tally_app holds no UPDATE on disputes; a trigger function, so no caller can run it directly, and enforce_dispute_update admits only this move.';
REVOKE ALL ON FUNCTION public.dispute_move_status() FROM PUBLIC, tally_app, tally_core;
CREATE TRIGGER z_dispute_move_status AFTER INSERT ON public.dispute_events FOR EACH ROW
    WHEN (NEW.event_type = ANY (ARRAY['resolved'::text, 'withdrawn'::text])) EXECUTE FUNCTION public.dispute_move_status();
ALTER TABLE public.dispute_events ENABLE ALWAYS TRIGGER z_dispute_move_status;


-- ----------------------------------------------------------------------------
-- 7. The readers (D6)
-- ----------------------------------------------------------------------------
-- Required coordinates; NULL raises; no fallback onto a live column (memory
-- "temporal helper: no live fallback").
CREATE OR REPLACE FUNCTION public.dispute_shelter_as_of(p_invoice_id uuid, p_on date, p_recorded_at timestamp with time zone)
    RETURNS TABLE (dispute_id uuid, determination_id uuid, outcome text, sheltered_amount numeric, must_pay_amount numeric,
                   shelter_ends_on date, blocks text[])
    LANGUAGE plpgsql STABLE
    SET search_path = public, pg_temp
    AS $$
BEGIN
    PERFORM public.cash_coordinates_required('dispute_shelter_as_of', p_on, p_recorded_at);
    RETURN QUERY
    SELECT d.id, x.id, x.outcome,
           CASE WHEN x.id IS NULL OR x.shelter_ends_on < p_on THEN 0::numeric ELSE x.sheltered_amount END,
           x.must_pay_amount, x.shelter_ends_on,
           CASE WHEN x.id IS NULL OR x.shelter_ends_on < p_on THEN '{}'::text[] ELSE x.blocks END
      FROM public.disputes d
      LEFT JOIN LATERAL (
            SELECT y.* FROM public.dispute_determinations y
             WHERE y.dispute_id = d.id AND y.created_at <= p_recorded_at
               AND NOT EXISTS (SELECT 1 FROM public.dispute_determinations z WHERE z.supersedes_id = y.id AND z.created_at <= p_recorded_at)
             ORDER BY y.record_seq DESC LIMIT 1) x ON true
     WHERE d.invoice_id = p_invoice_id AND d.created_at <= p_recorded_at AND d.received_on <= p_on
       AND NOT EXISTS (SELECT 1 FROM public.dispute_events e
                        WHERE e.dispute_id = d.id AND e.event_type IN ('resolved', 'withdrawn')
                          AND e.created_at <= p_recorded_at AND e.occurred_on <= p_on)
     ORDER BY d.received_on, d.id;
END;
$$;
COMMENT ON FUNCTION public.dispute_shelter_as_of(uuid, date, timestamp with time zone) IS
    'v5.4.2-25 (D6; CI-074). For a bill, at a date (p_on) and a recorded instant (p_recorded_at), both required (22004 otherwise): one row per dispute of the bill received by p_on, recorded by p_recorded_at, and not resolved or withdrawn by p_on as recorded by p_recorded_at — with its determination live as of p_recorded_at (NULL when none yet: nothing sheltered, nothing blocked), the sheltered amount and blocks (none once p_on is past shelter_ends_on, the last sheltered day), the amount to pay and the last sheltered day. A resolved dispute has no row from its resolution date: the shelter ends by construction, nothing to reset. Invoker rights: RLS applies.';
REVOKE ALL ON FUNCTION public.dispute_shelter_as_of(uuid, date, timestamp with time zone) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.dispute_shelter_as_of(uuid, date, timestamp with time zone) TO tally_app, tally_core;

CREATE OR REPLACE FUNCTION public.dispute_line_shelter_as_of(p_line_id uuid, p_on date, p_recorded_at timestamp with time zone)
    RETURNS TABLE (dispute_id uuid, determination_id uuid, sheltered_amount numeric, basis text)
    LANGUAGE plpgsql STABLE
    SET search_path = public, pg_temp
    AS $$
BEGIN
    PERFORM public.cash_coordinates_required('dispute_line_shelter_as_of', p_on, p_recorded_at);
    RETURN QUERY
    WITH line AS (
        SELECT l.id, l.invoice_id FROM public.invoice_line_items l WHERE l.id = p_line_id
    ), shelter AS (
        SELECT s.dispute_id, s.determination_id, s.sheltered_amount, x.dispute_amount_id,
               EXISTS (SELECT 1 FROM public.dispute_amount_lines al WHERE al.dispute_amount_id = x.dispute_amount_id) AS has_lines
          FROM line, public.dispute_shelter_as_of(line.invoice_id, p_on, p_recorded_at) s
          JOIN public.dispute_determinations x ON x.id = s.determination_id
         WHERE s.sheltered_amount > 0
    ), weights AS (
        -- the lines the shelter is spread over, and each one's weight: the
        -- amount's own lines, else the bill's positive lines
        SELECT sh.dispute_id, sh.determination_id, sh.sheltered_amount, sh.has_lines, w.line_id, w.weight, w.ord
          FROM shelter sh
          CROSS JOIN line
          CROSS JOIN LATERAL (
                SELECT al.invoice_line_item_id AS line_id, al.amount AS weight, row_number() OVER (ORDER BY il.line_order NULLS LAST, il.id) AS ord
                  FROM public.dispute_amount_lines al JOIN public.invoice_line_items il ON il.id = al.invoice_line_item_id
                 WHERE sh.has_lines AND al.dispute_amount_id = sh.dispute_amount_id
                UNION ALL
                SELECT il.id, il.amount, row_number() OVER (ORDER BY il.line_order NULLS LAST, il.id)
                  FROM public.invoice_line_items il
                 WHERE NOT sh.has_lines AND il.invoice_id = line.invoice_id AND il.amount > 0) w
    ), shares AS (
        -- cumulative rounding: the shares add up to the sheltered amount exactly
        SELECT w.dispute_id, w.determination_id, w.has_lines, w.line_id,
               round(w.sheltered_amount * sum(w.weight) OVER (PARTITION BY w.dispute_id ORDER BY w.ord) / sum(w.weight) OVER (PARTITION BY w.dispute_id), 2)
             - round(w.sheltered_amount * coalesce(sum(w.weight) OVER (PARTITION BY w.dispute_id ORDER BY w.ord ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING), 0)
                     / sum(w.weight) OVER (PARTITION BY w.dispute_id), 2) AS share
          FROM weights w
    )
    SELECT sh.dispute_id, sh.determination_id,
           coalesce((SELECT s.share FROM shares s WHERE s.dispute_id = sh.dispute_id AND s.line_id = p_line_id), 0::numeric),
           CASE WHEN sh.has_lines THEN 'lines' ELSE 'pro_rata' END
      FROM shelter sh
     ORDER BY sh.dispute_id;
END;
$$;
COMMENT ON FUNCTION public.dispute_line_shelter_as_of(uuid, date, timestamp with time zone) IS
    'v5.4.2-25 (D6; contract 8). For a bill line, at a date and a recorded instant (both required, 22004 otherwise): one row per sheltering dispute of its bill (dispute_shelter_as_of), with the part of the sheltered amount on this line — spread over the disputed amount''s own lines in proportion (basis lines), or, when the amount names none, over the bill''s positive lines in proportion to their charges (basis pro_rata; a credit line takes none). Cumulative rounding to the cent, in line order, so the parts add up to the sheltered amount. Invoker rights.';
REVOKE ALL ON FUNCTION public.dispute_line_shelter_as_of(uuid, date, timestamp with time zone) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.dispute_line_shelter_as_of(uuid, date, timestamp with time zone) TO tally_app, tally_core;


-- ----------------------------------------------------------------------------
-- 8. The two meaning changes (T1, T2)
-- ----------------------------------------------------------------------------
-- T1 (CI-074, A-15 outrank A-11's seed): a pending dispute is a disputes
-- row, whose shelter the readers give; the program type no longer protects
-- the account, and takes no new enrollment. recompute_do_not_disconnect reads
-- the flag, unchanged.
UPDATE public.program_types
   SET is_disconnect_protective = false,
       description = 'Retired by v5.4.2-25: a dispute is a disputes row, and its shelter is read from its determination (dispute_shelter_as_of). Not protective; no new enrollment. Kept for history.'
 WHERE code = 'pending_dispute';

CREATE OR REPLACE FUNCTION public.enforce_enrollment_not_pending_dispute() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
BEGIN
    IF NEW.program_type = 'pending_dispute' AND (TG_OP = 'INSERT' OR OLD.program_type IS DISTINCT FROM NEW.program_type) THEN
        RAISE EXCEPTION USING
            MESSAGE = 'program enrollment: pending_dispute is retired — a dispute is a disputes row, whose shelter its determination records [T1] (v5.4.2-25)',
            ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$;
COMMENT ON FUNCTION public.enforce_enrollment_not_pending_dispute() IS
    'v5.4.2-25 (T1). BEFORE INSERT OR UPDATE on customer_program_enrollments: no enrollment enters pending_dispute.';
REVOKE ALL ON FUNCTION public.enforce_enrollment_not_pending_dispute() FROM PUBLIC, tally_app, tally_core;
CREATE TRIGGER a_enforce_enrollment_not_pending_dispute BEFORE INSERT OR UPDATE ON public.customer_program_enrollments
    FOR EACH ROW EXECUTE FUNCTION public.enforce_enrollment_not_pending_dispute();
ALTER TABLE public.customer_program_enrollments ENABLE ALWAYS TRIGGER a_enforce_enrollment_not_pending_dispute;

-- T2 (R-05): a dispute is a record, not notes on the reading.
ALTER TABLE public.meter_readings
    DROP COLUMN dispute_reason,
    DROP COLUMN dispute_raised_by,
    DROP COLUMN dispute_raised_at,
    DROP COLUMN dispute_resolved_by,
    DROP COLUMN dispute_resolved_at,
    DROP COLUMN dispute_resolution_notes;

-- -19's body (as re-issued by -20), less the six dropped columns in Block 2's
-- whitelist and the hint. Re-created whole.
CREATE OR REPLACE FUNCTION public.enforce_reading_validation_workflow()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_changed           text[] := '{}';
    v_is_void_operation boolean;
    v_void_transition   boolean;
    v_relock            boolean;
    v_super             boolean := (SELECT r.rolsuper FROM pg_catalog.pg_roles r WHERE r.rolname = current_user);
BEGIN
    -- v5.4.2-20: the void is the write made as tally_void, the owner of
    -- void_invoice() — current_user here only while that function runs, a
    -- role no caller can become (assert_seal_role_invariants). It replaces
    -- the caller-settable session setting of v5.4.2-01 (AC-12, A-23 item 1).
    -- The carve-out below still admits only what void_invoice() writes, and
    -- only for a read that names the bill it held (C-B2).
    v_is_void_operation := current_user = 'tally_void';
    v_void_transition := v_is_void_operation
                         AND OLD.validation_status = 'locked'
                         AND NEW.validation_status = 'void_released'
                         AND OLD.locked_by_invoice_id IS NOT NULL;

    -- -------------------------------------------------------------------------
    -- BLOCK 1: validation_status transitions
    -- -------------------------------------------------------------------------
    IF OLD.validation_status IS DISTINCT FROM NEW.validation_status THEN

        IF OLD.validation_status = 'locked' THEN
            IF NOT v_void_transition THEN
                RAISE EXCEPTION
                    'Cannot change validation_status from locked. '
                    'Locked readings are terminal — corrections must create a NEW reading '
                    'via the dispute/correction workflow (insert replacement with '
                    'replaces_read_id pointing here). '
                    'To void the invoice that locked this read, use void_invoice(). '
                    'Reading: %', OLD.id;
            END IF;

        ELSIF NOT (
               (OLD.validation_status = 'pending_review'
                    AND NEW.validation_status IN ('reviewed_clean','reviewed_with_exception','approved','excluded'))
            OR (OLD.validation_status = 'reviewed_clean'
                    AND NEW.validation_status IN ('approved','excluded'))
            OR (OLD.validation_status = 'reviewed_with_exception'
                    AND NEW.validation_status IN ('approved','excluded','pending_review'))
            OR (OLD.validation_status = 'approved'
                    AND NEW.validation_status IN ('released_to_billing','excluded','pending_review'))
            OR (OLD.validation_status = 'released_to_billing'
                    AND NEW.validation_status = 'locked')
            OR (OLD.validation_status = 'excluded'
                    AND NEW.validation_status = 'pending_review')
            OR (OLD.validation_status = 'void_released'
                    AND NEW.validation_status = 'released_to_billing') -- correction run re-locks
        ) THEN
            RAISE EXCEPTION
                'Invalid validation_status transition: % -> %. Reading: %',
                OLD.validation_status, NEW.validation_status, OLD.id;
        END IF;

        -- Locking guard: transitioning TO locked requires billing metadata;
        -- the lock time is the database's (v5.4.2-19), a superuser's kept.
        IF NEW.validation_status = 'locked' THEN
            IF NEW.billing_period_locked IS DISTINCT FROM true THEN
                RAISE EXCEPTION
                    'validation_status=locked requires billing_period_locked=true. Reading: %', OLD.id;
            END IF;
            IF NEW.locked_by_billing_run_id IS NULL THEN
                RAISE EXCEPTION
                    'validation_status=locked requires locked_by_billing_run_id. Reading: %', OLD.id;
            END IF;
            IF NOT v_super OR NEW.locked_at IS NULL THEN
                NEW.locked_at := now();
            END IF;
        END IF;

    END IF;

    -- -------------------------------------------------------------------------
    -- The lock flag is set only by the move to locked (a flag set on a read no
    -- run consumed would freeze it with a false "consumed" record).
    -- -------------------------------------------------------------------------
    IF NOT OLD.billing_period_locked AND NEW.billing_period_locked AND NEW.validation_status IS DISTINCT FROM 'locked' THEN
        RAISE EXCEPTION USING
            MESSAGE = format('meter reading %s: billing_period_locked is set only by the move to locked, by a billing run (CI-031, v5.4.2-19)', OLD.id),
            ERRCODE = 'check_violation';
    END IF;

    -- r3 (Fable S1): nor is the rest of the lock record written on a read no
    -- run has consumed. The lock time, run and bill come only with the move
    -- to locked; voided_from_invoice_id only from a void (Block 3).
    IF NOT OLD.billing_period_locked THEN
        IF NEW.voided_from_invoice_id IS DISTINCT FROM OLD.voided_from_invoice_id
           OR (NEW.validation_status IS DISTINCT FROM 'locked'
               AND (NEW.locked_at IS DISTINCT FROM OLD.locked_at
                    OR NEW.locked_by_billing_run_id IS DISTINCT FROM OLD.locked_by_billing_run_id
                    OR NEW.locked_by_invoice_id IS DISTINCT FROM OLD.locked_by_invoice_id)) THEN
            RAISE EXCEPTION USING
                MESSAGE = format('meter reading %s: the lock record (locked_at, locked_by_*, voided_from_invoice_id) of a read no billing run has consumed is written only by the move to locked (CI-031, v5.4.2-19)', OLD.id),
                ERRCODE = 'check_violation';
        END IF;
    END IF;

    -- -------------------------------------------------------------------------
    -- BLOCK 2: a read a billing run consumed keeps its record (v5.4.2-19,
    -- CI-025 / CI-031). Keyed on billing_period_locked, which stays true after
    -- void_released: the read a voided bill released is the evidence the
    -- correction run rebills from, and is frozen like a locked one. EVERY
    -- column is frozen except the follow-up fields named here (r2: a
    -- whitelist, so a column added later is frozen by default) and the lock
    -- fields Block 3 governs.
    -- -------------------------------------------------------------------------
    IF OLD.billing_period_locked THEN
        SELECT coalesce(array_agg(o.key ORDER BY o.key), '{}') INTO v_changed
          FROM jsonb_each(to_jsonb(OLD)) o
         WHERE o.key <> ALL (ARRAY[
                   -- follow-up work on a consumed read
                   'notes', 'tamper_investigated', 'tamper_investigation_notes',
                   'status', 'requires_followup', 'followup_priority', 'followup_notes',
                   'assigned_to_user_id', 'replaced_by_reading_id', 'triggers_correction_workflow',
                   -- governed by Block 1 and Block 3
                   'validation_status', 'locked_at', 'locked_by_billing_run_id',
                   'locked_by_invoice_id', 'voided_from_invoice_id'])
           AND o.value IS DISTINCT FROM (to_jsonb(NEW) -> o.key);
    END IF;

    -- -------------------------------------------------------------------------
    -- BLOCK 3: the lock pointers of a consumed read (locked or void_released).
    -- Two writes may move them: void_invoice()'s (locked -> void_released:
    -- locked_by_invoice_id cleared, voided_from_invoice_id := the bill it
    -- held, run and lock time unchanged) and a correction run's re-lock
    -- (released_to_billing -> locked: its own run, a bill where there was
    -- none, the lock time stamped by Block 1). voided_from_invoice_id is
    -- written by a void and by nothing else.
    -- -------------------------------------------------------------------------
    IF OLD.billing_period_locked THEN
        v_relock := OLD.validation_status = 'released_to_billing' AND NEW.validation_status = 'locked';
        IF v_void_transition THEN
            IF NEW.locked_by_invoice_id IS NOT NULL THEN v_changed := v_changed || 'locked_by_invoice_id (void must clear it)'::text; END IF;
            IF NEW.voided_from_invoice_id IS DISTINCT FROM OLD.locked_by_invoice_id THEN v_changed := v_changed || 'voided_from_invoice_id (void sets it to the bill it held)'::text; END IF;
        ELSE
            IF NEW.voided_from_invoice_id IS DISTINCT FROM OLD.voided_from_invoice_id THEN v_changed := v_changed || 'voided_from_invoice_id'::text; END IF;
            IF NEW.locked_by_invoice_id IS DISTINCT FROM OLD.locked_by_invoice_id
               AND NOT (v_relock AND OLD.locked_by_invoice_id IS NULL) THEN
                v_changed := v_changed || 'locked_by_invoice_id'::text;
            END IF;
        END IF;
        IF NOT v_relock THEN
            IF NEW.locked_by_billing_run_id IS DISTINCT FROM OLD.locked_by_billing_run_id THEN v_changed := v_changed || 'locked_by_billing_run_id'::text; END IF;
            IF NEW.locked_at                IS DISTINCT FROM OLD.locked_at                THEN v_changed := v_changed || 'locked_at'::text; END IF;
        END IF;
    END IF;

    IF cardinality(v_changed) > 0 THEN
        RAISE EXCEPTION USING
            MESSAGE = format('meter reading %s was consumed by a billing run (validation_status %s, billing_period_locked) and its billing fields are frozen (CI-025 / CI-031, v5.4.2-19): attempted change to %s',
                             OLD.id, OLD.validation_status, array_to_string(v_changed, ', ')),
            HINT = 'To correct a read, insert a NEW reading with replaces_read_id pointing here. To undo the bill, use void_invoice(). Editable on such reads: notes, tamper_investigated, tamper_investigation_notes, status, requires_followup, followup_*, assigned_to_user_id, replaced_by_reading_id, triggers_correction_workflow.',
            ERRCODE = 'restrict_violation';
    END IF;

    RETURN NEW;
END;
$function$;
COMMENT ON FUNCTION public.enforce_reading_validation_workflow() IS
    'BEFORE UPDATE on meter_readings. Block 1: the validation_status transition matrix; locked -> void_released only by void_invoice() (current_user tally_void, v5.4.2-20); a move to locked needs billing_period_locked and locked_by_billing_run_id, and locked_at is stamped by the database (a superuser''s value kept). billing_period_locked is set only by the move to locked. Block 2 (v5.4.2-19, CI-025/CI-031): once billing_period_locked is true — locked AND void_released — every column is frozen except the follow-up fields (notes, tamper investigation, status, follow-up, assignee, replaced_by_reading_id, triggers_correction_workflow) and the lock fields of Block 3. Block 3: the lock pointers move only by void_invoice()''s exact write (locked_by_invoice_id -> NULL, voided_from_invoice_id := the bill it held) or a correction run''s re-lock (released_to_billing -> locked: its run, a bill where there was none, the stamped time). v5.4.2-25: the dispute_* notes are gone (a dispute is a disputes row); a reading''s move into or out of status disputed is enforce_reading_dispute_status''s.';

-- The status 'disputed' stays a status, tied to the record: entered only
-- under an open dispute naming the reading, left only once none is open.
CREATE OR REPLACE FUNCTION public.enforce_reading_dispute_status() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_id   uuid;
    v_open boolean;
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF NEW.status = 'disputed' THEN
            RAISE EXCEPTION USING
                MESSAGE = format('meter reading %s: a reading is marked disputed under an open dispute naming it, which a new reading cannot have [T2] (v5.4.2-25)', NEW.id),
                ERRCODE = 'check_violation';
        END IF;
        RETURN NEW;
    END IF;
    IF NEW.status IS NOT DISTINCT FROM OLD.status OR (NEW.status <> 'disputed' AND OLD.status <> 'disputed') THEN
        RETURN NEW;
    END IF;
    -- Under the lock of every dispute naming the reading, in id order.
    FOR v_id IN SELECT x.id FROM public.disputes x WHERE x.reading_id = NEW.id ORDER BY x.id LOOP
        PERFORM public.dispute_lock(v_id, 'a reading''s move into or out of disputed');
    END LOOP;
    v_open := EXISTS (SELECT 1 FROM public.disputes x WHERE x.reading_id = NEW.id AND x.status = 'open');
    IF NEW.status = 'disputed' AND NOT v_open THEN
        RAISE EXCEPTION USING
            MESSAGE = format('meter reading %s: marked disputed with no open dispute naming it — record the dispute first [T2] (v5.4.2-25)', NEW.id),
            ERRCODE = 'check_violation';
    END IF;
    IF OLD.status = 'disputed' AND v_open THEN
        RAISE EXCEPTION USING
            MESSAGE = format('meter reading %s: an open dispute names it; it stays disputed until that dispute is resolved or withdrawn [T2] (v5.4.2-25)', NEW.id),
            ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$;
COMMENT ON FUNCTION public.enforce_reading_dispute_status() IS
    'v5.4.2-25 (T2). BEFORE INSERT OR UPDATE OF status on meter_readings: a reading is born not disputed; it enters status disputed only while an open dispute names it, and leaves it only when none does — read under the lock of every dispute naming it (READ COMMITTED).';
REVOKE ALL ON FUNCTION public.enforce_reading_dispute_status() FROM PUBLIC, tally_app, tally_core;
CREATE TRIGGER a_enforce_reading_dispute_status BEFORE INSERT OR UPDATE OF status ON public.meter_readings
    FOR EACH ROW EXECUTE FUNCTION public.enforce_reading_dispute_status();
ALTER TABLE public.meter_readings ENABLE ALWAYS TRIGGER a_enforce_reading_dispute_status;
COMMENT ON INDEX public.idx_readings_disputed IS
    'Readings in status disputed or under_review. v5.4.2-25: on the status alone (the dispute notes are gone; a disputed reading names its open dispute through disputes.reading_id).';


-- ----------------------------------------------------------------------------
-- 9. The invariants
-- ----------------------------------------------------------------------------
DO $$ BEGIN
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
-- END PATCH v5.4.2-25
-- ============================================================================

COMMIT;
\endif
