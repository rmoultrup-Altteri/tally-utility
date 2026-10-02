-- ============================================================================
-- PATCH v5.4.2-15 — deposits at parity: the deposit law leaves the database,
--                    the records stay and keep their integrity
-- ============================================================================
-- Authority:   Ryan, 2026-09-28: the schema REPRESENTS rules and the C# core
--              EVALUATES them; "a Texas-only launch does not mean a Texas-only
--              architecture". Texas-only audit (application/texas-only-
--              architecture-audit-2026-09-28.md) §3.4 and §6 ("the worst
--              landed patch").
--              Design: application/deposits-parity-rescope-2026-09-30.md, with
--              Ryan's R-D1 (interest rates, 2026-09-30), R-D2 (the return-due
--              record, 2026-10-01) and R-D3 (numbering, 2026-10-01).
--              What the core must do — every rule v5.4.2-06 enforced, with its
--              source, -06 line range and boundary cases:
--              application/deposits-rules-for-the-core.md.
--              Statutory basis of the Texas rows: 16 TAC §7.45; 11 U.S.C. §366.
--
-- NUMBERING.   This is v5.4.2-15 (R-D3). The delivery patch — the one that
--              makes a frozen backbilling correction post — is called "the
--              delivery patch" and takes a number when drafted. Read "-14" in
--              v5.4.2-13 and "-15" in v5.4.2-14 (and its tu.sql banner) as
--              "the delivery patch".
--
-- ----------------------------------------------------------------------------
-- What changes
-- ----------------------------------------------------------------------------
--
--   v5.4.2-06 built 16 TAC §7.45 almost line for line as refusals: a Texas
--   tenant's residential cash deposit needed a cap; any waiver blocked any
--   §7.45 basis; interest was cash-only, nothing before day 31, retroactive to
--   day 1, simple, actual/365, at the rate a per-tenant lookup chose; a refund
--   required interest accrued to a horizon and credited in full; and a view
--   decided which deposits were owed a refund (twelve clean bills, two late,
--   or a closed account). All of that is law, and it leaves the database:
--
--     * The law becomes PLATFORM ROWS, per state, service, customer class and
--       basis, dated, cited, closed and never edited (the v5.4.2-13 pattern):
--       deposit_rules, with the vocabularies deposit_bases, deposit_triggers,
--       deposit_customer_classes, deposit_waiver_classes and
--       deposit_return_reasons. Texas gas is seeded once, from what -06
--       enforced. A second state is rows, not DDL (the battery's group Z).
--     * A deposit RECORDS the jurisdiction, class and rule row it was decided
--       under, its cap and the cap's basis, and the core version (decided_by).
--     * An accrual RECORDS the rate row and rule row it used and the core
--       version (calculated_by). The rate is the UTILITY's (R-D1): its rate
--       rows now say which state and service they are for. The platform keeps
--       each state's published legal rate as a REFERENCE only
--       (deposit_interest_rate_law) and a report compares the two
--       (deposit_interest_rate_discrepancies).
--     * When a mandatory return falls due, the core RECORDS it
--       (deposit_return_due), with the bills or the closure it rests on
--       (deposit_return_due_evidence). A due row found wrong is withdrawn by
--       a separate record (deposit_return_due_withdrawals), never edited. The
--       operators' "refunds owed" list (deposits_return_owed) reads those
--       records; it computes no law (R-D2).
--
--   Dropped: deposit_accrual_amount() (the Texas formula),
--   deposit_interest_rate_as_of() (rate selection), deposit_refund_trigger_
--   state() and the view deposits_refund_due (the refund law), the columns
--   deposits.refund_eligibility_on (a competing informational date) and
--   deposits.cap_basis_annual_billing (replaced by cap_basis_kind /
--   cap_basis_amount), and the CHECK lists for bases, triggers and waiver
--   classes (now vocabulary rows).
--
-- ----------------------------------------------------------------------------
-- What the database still refuses — record integrity only
-- ----------------------------------------------------------------------------
--
--   From -06, unchanged: a deposit's identity changing after insert; status
--   / refunded_on / released_on written other than by the events; a deposit
--   born other than held; a basis that is not insertable (legacy_unknown);
--   a source payment of another customer or not flagged is_deposit; any
--   event after refunded or released; an event dated before posting; a
--   ledger link to another customer; the posted event written by anyone but
--   the database; an application above the remainder, or while a refund is
--   pending, or into an accrued period; overlapping accrual periods; credit
--   above accrued − credited; a second pending refund; a refund or release
--   of other than the remainder; cash released or non-cash refunded; a
--   legacy deposit with no accruals refunded without a reason; a backdated
--   rate under a settled accrual; closing a customer with an open deposit;
--   the projections written directly.
--
--   New: a deposit that cites no rule row, or a rule row for another state,
--   service, class or basis, or not in force on its posting date; a cap
--   recorded under a rule with none, or missing under a rule with one, or
--   whose basis kind is not the rule's; an accrual that cites another
--   deposit's rule, or a rate row of another tenant, state or service, or one
--   not yet effective, or at a rate other than the row's; an accrual before
--   posting or recorded before its period ends; a refund or release that
--   leaves accrued interest uncredited (the deposit's last event, so the
--   ledger must be square: see DIVERGENCE below); a waiver
--   determination whose class requires a certification and carries none; a
--   return-due row on a deposit whose rule does not make the return
--   mandatory for its instrument, or on a refunded or released deposit, or
--   while another due row for it is live, or without evidence, or with
--   evidence of another customer, from before posting, of the wrong kind for
--   its reason, or added after its own transaction; a withdrawal of a row
--   already withdrawn; a refund citing a withdrawn due row or another
--   deposit's; any application write to the law tables; any edit of a law
--   or vocabulary row other than a stamped close not on or before a date it
--   is cited for.
--
--   It does NOT decide whether a deposit may be required, how large it may
--   be, what interest is owed, or when a refund falls due. The core does,
--   and the records say which rule row it used.
--
-- DIVERGENCE FROM THE DESIGN (for Ryan). Design §2 lists "credited in full
--   before the refund" among the dropped law. This patch keeps the narrower
--   arithmetic half: a refund or release is the deposit's last event (no
--   events follow it), so interest already ACCRUED on the record must be
--   CREDITED by then, or the ledger closes owing money it can never pay.
--   Whether interest is owed at all, and to which date, stays the core's.
--
-- PRECONDITION. Nothing is live (Ryan, 2026-09-28): no deposit, waiver or
--   rate exists outside a test. The patch refuses to run over any non-legacy
--   deposit, any waiver determination or any utility rate row, rather than
--   invent the rule citation, state or service the core never recorded.
--   -06's legacy_unknown deposits are carried unchanged (they cite no rule).
--
-- APPLICATION CONTRACT (AC-34). A caller that read deposits_refund_due,
--   deposit_refund_trigger_state(), deposit_accrual_amount() or
--   deposit_interest_rate_as_of(), or wrote cap_basis_annual_billing or
--   refund_eligibility_on, uses the records above instead. No application
--   code exists yet (Ryan, 2026-09-28), so nothing breaks.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 1. Precondition
-- ----------------------------------------------------------------------------
DO $$
DECLARE
    v_dep bigint;
    v_wvr bigint;
    v_rate bigint;
BEGIN
    IF to_regclass('public.deposit_rules') IS NOT NULL THEN
        RETURN;   -- re-run of this patch: the tables below are already in place
    END IF;
    SELECT count(*) INTO v_dep FROM public.deposits d WHERE d.basis <> 'legacy_unknown';
    SELECT count(*) INTO v_wvr FROM public.deposit_waiver_determinations;
    SELECT count(*) INTO v_rate FROM public.deposit_interest_rates;
    IF v_dep + v_wvr + v_rate > 0 THEN
        RAISE EXCEPTION USING
            MESSAGE = format('v5.4.2-15: %s deposit(s), %s waiver determination(s) and %s utility rate row(s) exist; this patch records the rule row, state and service each was decided under, and will not invent them', v_dep, v_wvr, v_rate),
            ERRCODE = 'object_not_in_prerequisite_state',
            HINT = 'Nothing is live (2026-09-28). A database with real deposits needs a backfill that the core performs, citing rule rows — write it before applying.';
    END IF;
END;
$$;


-- ----------------------------------------------------------------------------
-- 2. Vocabularies — platform-held, never edited
-- ----------------------------------------------------------------------------
-- The v5.4.2-13 pattern: no tenant_id, tally_app reads and cannot write, a
-- new value is a row (and, where the core must act on it, a core change). A
-- vocabulary row is never edited or deleted (section 3's immutability guard).

CREATE TABLE IF NOT EXISTS public.deposit_bases (
    basis_code      text NOT NULL,
    is_federal      boolean NOT NULL,
    insertable      boolean NOT NULL,
    description     text NOT NULL,
    created_at      timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT deposit_bases_pkey PRIMARY KEY (basis_code),
    CONSTRAINT deposit_bases_code_check CHECK ((basis_code ~ '^[a-z][a-z0-9_]*$'::text)),
    CONSTRAINT deposit_bases_description_check CHECK ((description ~ '[[:alnum:]]'::text))
);
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.deposit_bases FROM tally_app;
GRANT SELECT ON public.deposit_bases TO tally_app;
COMMENT ON TABLE public.deposit_bases IS
    'v5.4.2-15 (deposits at parity). Why a deposit was taken — the basis decides which rule governs it. is_federal: a federal basis (11 U.S.C. §366 adequate assurance), not a state deposit rule. insertable: false for a basis that exists only for carried history (legacy_unknown, -06''s backfill); no new deposit may take it. What a basis DOES in a state is on its deposit_rules row. Platform-held vocabulary; a new basis is a row plus a core change.';

INSERT INTO public.deposit_bases (basis_code, is_federal, insertable, description)
SELECT v.code, v.fed, v.ins, v.description
  FROM (VALUES
    ('credit_evaluation',      false, true,  'Required on the customer''s credit evaluation (new service).'),
    ('additional_trigger',     false, true,  'An additional deposit after a triggering event (NSF, disconnection history, a broken payment arrangement): see deposit_triggers.'),
    ('tariff',                 false, true,  'Required by the utility''s filed tariff.'),
    ('adequate_assurance_366', true,  true,  'Adequate assurance of payment demanded of a debtor in bankruptcy (11 U.S.C. §366).'),
    ('legacy_unknown',         false, false, 'Carried from customers.deposit_* by v5.4.2-06; the basis was never recorded. Not insertable.')
  ) AS v(code, fed, ins, description)
 WHERE NOT EXISTS (SELECT 1 FROM public.deposit_bases b WHERE b.basis_code = v.code);


CREATE TABLE IF NOT EXISTS public.deposit_triggers (
    trigger_code    text NOT NULL,
    description     text NOT NULL,
    created_at      timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT deposit_triggers_pkey PRIMARY KEY (trigger_code),
    CONSTRAINT deposit_triggers_code_check CHECK ((trigger_code ~ '^[a-z][a-z0-9_]*$'::text)),
    CONSTRAINT deposit_triggers_description_check CHECK ((description ~ '[[:alnum:]]'::text))
);
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.deposit_triggers FROM tally_app;
GRANT SELECT ON public.deposit_triggers TO tally_app;
COMMENT ON TABLE public.deposit_triggers IS
    'v5.4.2-15. The events that may give rise to an additional deposit (decision table #55 rules 5-7). Whether one does, and at what threshold, is the core''s. Platform-held vocabulary.';

INSERT INTO public.deposit_triggers (trigger_code, description)
SELECT v.code, v.description
  FROM (VALUES
    ('nsf',                'Payments returned unpaid (NSF).'),
    ('disconnect_history', 'Disconnection for nonpayment in the customer''s history.'),
    ('broken_dpa',         'A broken deferred payment arrangement.')
  ) AS v(code, description)
 WHERE NOT EXISTS (SELECT 1 FROM public.deposit_triggers t WHERE t.trigger_code = v.code);


CREATE TABLE IF NOT EXISTS public.deposit_customer_classes (
    state_code      text NOT NULL,
    service_type    text NOT NULL,
    class_code      text NOT NULL,
    description     text NOT NULL,
    source_note     text NOT NULL,
    created_at      timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT deposit_customer_classes_pkey PRIMARY KEY (state_code, service_type, class_code),
    CONSTRAINT deposit_customer_classes_state_code_check CHECK ((state_code ~ '^[A-Z]{2}$'::text)),
    CONSTRAINT deposit_customer_classes_service_type_check
        CHECK ((service_type = ANY (ARRAY['water'::text, 'sewer'::text, 'electric'::text, 'gas'::text, 'stormwater'::text, 'trash'::text, 'reclaimed_water'::text]))),
    CONSTRAINT deposit_customer_classes_code_check CHECK ((class_code ~ '^[a-z][a-z0-9_]*$'::text)),
    CONSTRAINT deposit_customer_classes_description_check CHECK ((description ~ '[[:alnum:]]'::text)),
    CONSTRAINT deposit_customer_classes_source_note_check CHECK ((source_note ~ '[[:alnum:]]'::text))
);
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.deposit_customer_classes FROM tally_app;
GRANT SELECT ON public.deposit_customer_classes TO tally_app;
COMMENT ON TABLE public.deposit_customer_classes IS
    'v5.4.2-15. The customer classes a state''s deposit rules distinguish, per service type. Law, platform-held. Which class an account is in is the core''s call, from the utility''s tariff; the deposit records the answer (deposits.customer_class).';

INSERT INTO public.deposit_customer_classes (state_code, service_type, class_code, description, source_note)
SELECT v.s, v.svc, v.code, v.description, v.source_note
  FROM (VALUES
    ('TX', 'gas', 'residential',     'Residential customers.',
     '16 TAC 7.45 deposit provisions; the cap of one-sixth of estimated annual billing applies to residential deposits (-06 D-41; decision table #53 rank 8). Which classes the other provisions reach is Kyle question K1.'),
    ('TX', 'gas', 'non_residential', 'Every other customer.',
     '16 TAC 7.45; -06 applied the waiver, interest and refund provisions to every class and the cap to residential only (Kyle question K1).')
  ) AS v(s, svc, code, description, source_note)
 WHERE NOT EXISTS (SELECT 1 FROM public.deposit_customer_classes c
                    WHERE c.state_code = v.s AND c.service_type = v.svc AND c.class_code = v.code);


CREATE TABLE IF NOT EXISTS public.deposit_waiver_classes (
    state_code              text NOT NULL,
    service_type            text NOT NULL,
    class_code              text NOT NULL,
    requires_certification  boolean NOT NULL,
    description             text NOT NULL,
    source_note             text NOT NULL,
    created_at              timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT deposit_waiver_classes_pkey PRIMARY KEY (state_code, service_type, class_code),
    CONSTRAINT deposit_waiver_classes_state_code_check CHECK ((state_code ~ '^[A-Z]{2}$'::text)),
    CONSTRAINT deposit_waiver_classes_service_type_check
        CHECK ((service_type = ANY (ARRAY['water'::text, 'sewer'::text, 'electric'::text, 'gas'::text, 'stormwater'::text, 'trash'::text, 'reclaimed_water'::text]))),
    CONSTRAINT deposit_waiver_classes_code_check CHECK ((class_code ~ '^[a-z][a-z0-9_]*$'::text)),
    CONSTRAINT deposit_waiver_classes_description_check CHECK ((description ~ '[[:alnum:]]'::text)),
    CONSTRAINT deposit_waiver_classes_source_note_check CHECK ((source_note ~ '[[:alnum:]]'::text))
);
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.deposit_waiver_classes FROM tally_app;
GRANT SELECT ON public.deposit_waiver_classes TO tally_app;
COMMENT ON TABLE public.deposit_waiver_classes IS
    'v5.4.2-15. The grounds on which a state''s law (or a utility''s tariff, where the law lets it extend them) waives a deposit, per state and service. requires_certification: a determination of this class must carry the certification''s reference (Texas: family violence, Texas Council on Family Violence). Which bases a waiver reaches is the rule row''s (deposit_rules.waivable); whether a customer qualifies is recorded in deposit_waiver_determinations; whether a deposit is waived is the core''s. Platform-held.';

INSERT INTO public.deposit_waiver_classes (state_code, service_type, class_code, requires_certification, description, source_note)
SELECT v.s, v.svc, v.code, v.cert, v.description, v.source_note
  FROM (VALUES
    ('TX', 'gas', 'family_violence_certified', true,  'Certified victim of family violence.',
     '16 TAC 7.45(5)(C) (Kyle research Q-6): a mandatory deposit waiver, certification-backed; decision table #53 rank 0.'),
    ('TX', 'gas', 'age_65_no_balance',         false, 'Aged 65 or older with no outstanding balance for the same service.',
     '16 TAC 7.45; decision table #53 rank 1. Mandatory or tariff-by-tariff is Kyle question K3.'),
    ('TX', 'gas', 'good_payment_history',      false, 'Good payment history with a utility.',
     '16 TAC 7.45; decision table #53 rank 2.'),
    ('TX', 'gas', 'tariff',                    false, 'A waiver class in the utility''s filed tariff.',
     'Decision table #53 rank 3: a tariff may extend the statutory waivers, never narrow them.')
  ) AS v(s, svc, code, cert, description, source_note)
 WHERE NOT EXISTS (SELECT 1 FROM public.deposit_waiver_classes w
                    WHERE w.state_code = v.s AND w.service_type = v.svc AND w.class_code = v.code);


CREATE TABLE IF NOT EXISTS public.deposit_return_reasons (
    reason_code     text NOT NULL,
    evidence_kind   text NOT NULL,
    description     text NOT NULL,
    created_at      timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT deposit_return_reasons_pkey PRIMARY KEY (reason_code),
    CONSTRAINT deposit_return_reasons_code_check CHECK ((reason_code ~ '^[a-z][a-z0-9_]*$'::text)),
    -- What a due row's evidence for this reason cites: bills, or the
    -- customer's state change.
    CONSTRAINT deposit_return_reasons_evidence_kind_check
        CHECK ((evidence_kind = ANY (ARRAY['invoice'::text, 'state_event'::text]))),
    CONSTRAINT deposit_return_reasons_description_check CHECK ((description ~ '[[:alnum:]]'::text))
);
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.deposit_return_reasons FROM tally_app;
GRANT SELECT ON public.deposit_return_reasons TO tally_app;
COMMENT ON TABLE public.deposit_return_reasons IS
    'v5.4.2-15 (R-D2). Why a deposit''s mandatory return fell due, and what kind of record the reason rests on (evidence_kind: invoice — the bills the core judged; state_event — the customer''s state change). A state with another trigger adds a row. Disconnection as a trigger (decision table #54 rule 1; rules-for-the-core DG1) waits for a recorded disconnect reason. Platform-held vocabulary.';

INSERT INTO public.deposit_return_reasons (reason_code, evidence_kind, description)
SELECT v.code, v.kind, v.description
  FROM (VALUES
    ('clean_bill_history', 'invoice',     'The customer''s bill history met the rule''s refund measure (Texas: twelve bills, no more than two delinquencies, not currently delinquent).'),
    ('account_closed',     'state_event', 'The customer''s account closed or final-billed.')
  ) AS v(code, kind, description)
 WHERE NOT EXISTS (SELECT 1 FROM public.deposit_return_reasons r WHERE r.reason_code = v.code);


-- ----------------------------------------------------------------------------
-- 3. deposit_rules — the law per (state, service, class, basis), dated
-- ----------------------------------------------------------------------------
-- What a state's deposit law requires, as ATTRIBUTES the core reads. Dated
-- with no overlap per key; cited; a key with no row in force means no rule is
-- known — the core refuses, never falls back. Never edited: closed (stamped,
-- once, never on or before a date it is cited for) and superseded, because
-- deposits, accruals and return-due rows cite it.

CREATE TABLE IF NOT EXISTS public.deposit_rules (
    id                              uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    state_code                      text NOT NULL,
    service_type                    text NOT NULL,
    customer_class                  text NOT NULL,
    basis                           text NOT NULL,
    waivable                        boolean NOT NULL,
    cap_kind                        text NOT NULL,
    cap_divisor                     integer,
    cap_months                      numeric(6,2),
    cap_amount_fixed                numeric(12,2),
    cap_scope                       text,
    interest_bearing_instruments    text[] NOT NULL,
    interest_min_hold_days          integer,
    interest_retroactive            boolean,
    interest_method                 text,
    interest_day_count              text,
    interest_credit_cadence         text,
    refund_mandatory                boolean NOT NULL,
    refund_after_count              integer,
    refund_measure                  text,
    refund_max_delinquencies        integer,
    refund_disqualify_on_disconnect boolean,
    refund_on_account_close         boolean,
    refund_obligation_vests         boolean,
    return_mandatory_instruments    text[],
    effective_from                  date NOT NULL,
    effective_to                    date,
    source_note                     text NOT NULL,
    created_at                      timestamp with time zone DEFAULT now() NOT NULL,
    closed_at                       timestamp with time zone,
    closed_by                       text,
    CONSTRAINT deposit_rules_pkey PRIMARY KEY (id),
    CONSTRAINT deposit_rules_class_fkey
        FOREIGN KEY (state_code, service_type, customer_class)
        REFERENCES public.deposit_customer_classes(state_code, service_type, class_code),
    CONSTRAINT deposit_rules_basis_fkey
        FOREIGN KEY (basis) REFERENCES public.deposit_bases(basis_code),
    -- Every comparison below on a nullable column is paired with IS NOT
    -- NULL: a CHECK passes on NULL, so `x > 0` alone admits a missing x.
    -- The cap: none, a fraction of estimated annual billing (divisor), a
    -- number of months of estimated billing, or a fixed amount — exactly the
    -- figure its kind needs, and a scope exactly when there is a cap.
    CONSTRAINT deposit_rules_cap_check
        CHECK ((((cap_kind = 'none'::text) AND (cap_divisor IS NULL) AND (cap_months IS NULL) AND (cap_amount_fixed IS NULL) AND (cap_scope IS NULL))
             OR ((cap_kind = 'fraction_of_annual_billing'::text) AND (cap_divisor IS NOT NULL) AND (cap_divisor > 0) AND (cap_months IS NULL) AND (cap_amount_fixed IS NULL) AND (cap_scope IS NOT NULL))
             OR ((cap_kind = 'months_of_billing'::text) AND (cap_months IS NOT NULL) AND (cap_months > (0)::numeric) AND (cap_divisor IS NULL) AND (cap_amount_fixed IS NULL) AND (cap_scope IS NOT NULL))
             OR ((cap_kind = 'fixed_amount'::text) AND (cap_amount_fixed IS NOT NULL) AND (cap_amount_fixed > (0)::numeric) AND (cap_divisor IS NULL) AND (cap_months IS NULL) AND (cap_scope IS NOT NULL)))),
    CONSTRAINT deposit_rules_cap_scope_check
        CHECK (((cap_scope IS NULL) OR (cap_scope = ANY (ARRAY['per_deposit'::text, 'combined'::text])))),
    -- Interest: the instruments that earn it (possibly none); when any do,
    -- the method, day count and cadence; a minimum hold and whether interest
    -- then runs from posting appear together or not at all.
    CONSTRAINT deposit_rules_interest_instruments_check
        CHECK ((interest_bearing_instruments <@ ARRAY['cash'::text, 'letter_of_credit'::text, 'certificate_of_deposit'::text, 'surety_bond'::text, 'prepayment'::text, 'guarantor'::text, 'other_agreed'::text])),
    CONSTRAINT deposit_rules_interest_check
        CHECK ((((cardinality(interest_bearing_instruments) = 0)
                 AND (interest_min_hold_days IS NULL) AND (interest_retroactive IS NULL)
                 AND (interest_method IS NULL) AND (interest_day_count IS NULL) AND (interest_credit_cadence IS NULL))
             OR ((cardinality(interest_bearing_instruments) > 0)
                 AND (interest_method IS NOT NULL) AND (interest_day_count IS NOT NULL) AND (interest_credit_cadence IS NOT NULL)
                 AND ((interest_min_hold_days IS NULL) = (interest_retroactive IS NULL))
                 AND ((interest_min_hold_days IS NULL) OR (interest_min_hold_days > 0))))),
    CONSTRAINT deposit_rules_interest_method_check
        CHECK (((interest_method IS NULL) OR (interest_method = ANY (ARRAY['simple'::text, 'compound_annual'::text])))),
    CONSTRAINT deposit_rules_interest_day_count_check
        CHECK (((interest_day_count IS NULL) OR (interest_day_count = ANY (ARRAY['actual_365'::text, 'actual_actual'::text])))),
    CONSTRAINT deposit_rules_interest_cadence_check
        CHECK (((interest_credit_cadence IS NULL) OR (interest_credit_cadence = ANY (ARRAY['at_refund'::text, 'annual'::text, 'on_bill'::text])))),
    -- The mandatory return: when there is one, whether account close
    -- triggers it, which instruments it covers, and optionally a count-based
    -- trigger given whole; when there is none, nothing about it.
    -- refund_obligation_vests NULL under a mandatory return = unruled (K6).
    CONSTRAINT deposit_rules_return_instruments_check
        CHECK (((return_mandatory_instruments IS NULL)
             OR (return_mandatory_instruments <@ ARRAY['cash'::text, 'letter_of_credit'::text, 'certificate_of_deposit'::text, 'surety_bond'::text, 'prepayment'::text, 'guarantor'::text, 'other_agreed'::text]))),
    CONSTRAINT deposit_rules_refund_check
        CHECK ((((NOT refund_mandatory)
                 AND (refund_after_count IS NULL) AND (refund_measure IS NULL) AND (refund_max_delinquencies IS NULL)
                 AND (refund_disqualify_on_disconnect IS NULL) AND (refund_on_account_close IS NULL)
                 AND (refund_obligation_vests IS NULL) AND (return_mandatory_instruments IS NULL))
             OR (refund_mandatory
                 AND (refund_on_account_close IS NOT NULL)
                 AND (return_mandatory_instruments IS NOT NULL) AND (cardinality(return_mandatory_instruments) > 0)
                 AND (((refund_after_count IS NULL) AND (refund_measure IS NULL) AND (refund_max_delinquencies IS NULL) AND (refund_disqualify_on_disconnect IS NULL))
                   OR ((refund_after_count IS NOT NULL) AND (refund_after_count > 0) AND (refund_measure IS NOT NULL)
                       AND (refund_max_delinquencies IS NOT NULL) AND (refund_max_delinquencies >= 0) AND (refund_disqualify_on_disconnect IS NOT NULL)))))),
    CONSTRAINT deposit_rules_refund_measure_check
        CHECK (((refund_measure IS NULL) OR (refund_measure = ANY (ARRAY['bills'::text, 'months'::text])))),
    CONSTRAINT deposit_rules_range_check
        CHECK (((effective_to IS NULL) OR (effective_to > effective_from))),
    CONSTRAINT deposit_rules_source_note_check
        CHECK ((source_note ~ '[[:alnum:]]'::text)),
    CONSTRAINT deposit_rules_no_overlap
        EXCLUDE USING gist (state_code WITH =, service_type WITH =, customer_class WITH =, basis WITH =,
                            daterange(effective_from, effective_to, '[)'::text) WITH &&)
);

CREATE INDEX IF NOT EXISTS idx_deposit_rules_key ON public.deposit_rules USING btree (state_code, service_type, customer_class, basis, effective_from);

REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.deposit_rules FROM tally_app;
GRANT SELECT ON public.deposit_rules TO tally_app;

COMMENT ON TABLE public.deposit_rules IS
    'v5.4.2-15 (deposits at parity). What a state''s deposit law requires, per (state, service type, customer class, basis, effective range), as ATTRIBUTES the calculation core reads: whether a waiver reaches it; the cap (kind, figure, scope); which instruments earn interest and how (minimum hold, retroactivity, method, day count, credit cadence); whether the deposit must be returned unasked, on what history and on account close, which instruments that covers, and whether it stays owed once due. Platform-held (tally_app reads only), cited (source_note), no overlap per key. Never edited — closed (effective_to set once, stamped closed_at / closed_by, never on or before a date it is cited for) and superseded, because deposits, accruals and return-due rows cite it. A key with no row in force means no rule is known: the core refuses, never falls back. How the core applies each attribute: application/deposits-rules-for-the-core.md.';
COMMENT ON COLUMN public.deposit_rules.waivable IS
    'An in-force waiver determination reaches a deposit of this basis: none may be required (Texas §7.45 bases: true; §366: false, -06 D-40 — Kyle question K2).';
COMMENT ON COLUMN public.deposit_rules.cap_kind IS
    'none; fraction_of_annual_billing (cap = estimated annual billing ÷ cap_divisor — Texas residential: 6); months_of_billing (cap_months of estimated billing); fixed_amount (cap_amount_fixed). The deposit records the cap and its basis; computing them is the core''s (the estimate for a new applicant is undefined, decision table #53 OQ5).';
COMMENT ON COLUMN public.deposit_rules.cap_scope IS
    'per_deposit: each deposit within the cap (-06). combined: the total held within it (decision table #55 rule 9). Kyle question K4.';
COMMENT ON COLUMN public.deposit_rules.interest_min_hold_days IS
    'No interest unless the deposit is held MORE than this many days (Texas: 30 — the day-30/31 cliff, CI-130). NULL: from day 1.';
COMMENT ON COLUMN public.deposit_rules.interest_retroactive IS
    'Past the minimum hold, interest runs from the posting date (Texas: true — from day 1, not day 31) rather than from the end of the hold. NULL exactly when there is no minimum hold.';
COMMENT ON COLUMN public.deposit_rules.refund_obligation_vests IS
    'Once the return falls due, it stays owed even if the customer falls behind before it is made. NULL under a mandatory return = unruled (Kyle question K6).';
COMMENT ON COLUMN public.deposit_rules.return_mandatory_instruments IS
    'The instruments the mandatory return covers: cash is refunded, non-cash released. Texas: {cash}, as -06 (residential non-cash is Kyle question K5).';

-- A rule row's record: stamped, born unclosed.
CREATE OR REPLACE FUNCTION public.enforce_deposit_rule_record() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
BEGIN
    NEW.created_at := now();
    NEW.closed_at  := NULL;
    NEW.closed_by  := NULL;
    RETURN NEW;
END;
$$;
COMMENT ON FUNCTION public.enforce_deposit_rule_record() IS
    'v5.4.2-15. BEFORE INSERT on deposit_rules, every role: created_at stamped; closed_at / closed_by start empty.';
DROP TRIGGER IF EXISTS a_enforce_deposit_rule_record ON public.deposit_rules;
CREATE TRIGGER a_enforce_deposit_rule_record BEFORE INSERT ON public.deposit_rules
    FOR EACH ROW EXECUTE FUNCTION public.enforce_deposit_rule_record();
ALTER TABLE public.deposit_rules ENABLE ALWAYS TRIGGER a_enforce_deposit_rule_record;

-- A rule row's history: the only edit is a close, stamped, never on or
-- before the latest date a citation used it — a deposit's posting date, an
-- accrual's period end, a return-due date (the v5.4.2-13 floor).
CREATE OR REPLACE FUNCTION public.enforce_deposit_rule_history() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    c_close_cols CONSTANT text[] := ARRAY['effective_to', 'closed_at', 'closed_by'];
    v_sees_all boolean;
    v_latest date;
BEGIN
    IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION USING
            MESSAGE = format('deposit rule %s: law rows are never deleted — close the row (effective_to) and add its successor (v5.4.2-15)', OLD.id),
            ERRCODE = 'restrict_violation';
    END IF;
    IF OLD.effective_to IS NOT NULL OR NEW.effective_to IS NULL
       OR (to_jsonb(NEW) - c_close_cols) <> (to_jsonb(OLD) - c_close_cols) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('deposit rule %s: law rows are never edited — deposits, accruals and return-due rows cite them; close the row (effective_to, once, nothing else) and add its successor (v5.4.2-15)', OLD.id),
            ERRCODE = 'restrict_violation';
    END IF;
    SELECT r.rolsuper OR r.rolbypassrls INTO v_sees_all FROM pg_catalog.pg_roles r WHERE r.rolname = current_user;
    IF v_sees_all IS NOT TRUE THEN
        RAISE EXCEPTION USING
            MESSAGE = format('deposit rule %s: closing a law row needs a role that sees every tenant''s citations of it (superuser or BYPASSRLS); %s does not (v5.4.2-15)', OLD.id, current_user),
            ERRCODE = 'insufficient_privilege';
    END IF;
    SELECT max(c.d) INTO v_latest FROM (
        SELECT d.posted_on AS d FROM public.deposits d WHERE d.rule_id = OLD.id
        UNION ALL
        SELECT e.period_end FROM public.deposit_events e WHERE e.rule_id = OLD.id
        UNION ALL
        SELECT r.due_on FROM public.deposit_return_due r WHERE r.rule_id = OLD.id
    ) c;
    IF v_latest IS NOT NULL AND NEW.effective_to <= v_latest THEN
        RAISE EXCEPTION USING
            MESSAGE = format('deposit rule %s: it is cited for %s; a close effective %s would put that citation outside the rule''s range (v5.4.2-15)', OLD.id, v_latest, NEW.effective_to),
            ERRCODE = 'restrict_violation',
            HINT = 'Close it after the latest date it is cited for. A row wrong from its first day is a reviewed platform repair (residual R4).';
    END IF;
    NEW.closed_at := now();
    NEW.closed_by := session_user;
    RETURN NEW;
END;
$$;
COMMENT ON FUNCTION public.enforce_deposit_rule_history() IS
    'v5.4.2-15. BEFORE UPDATE OR DELETE on deposit_rules, every role: never deleted; the only edit is a close (effective_to NULL → a date, nothing else), stamped with closed_at and the session role; refused on or before the latest date a deposit (posted_on), an accrual (period_end) or a return-due row (due_on) cites the row for; refused to a role row-level security narrows.';
DROP TRIGGER IF EXISTS a_enforce_deposit_rule_history ON public.deposit_rules;
CREATE TRIGGER a_enforce_deposit_rule_history BEFORE UPDATE OR DELETE ON public.deposit_rules
    FOR EACH ROW EXECUTE FUNCTION public.enforce_deposit_rule_history();
ALTER TABLE public.deposit_rules ENABLE ALWAYS TRIGGER a_enforce_deposit_rule_history;

-- The five vocabularies never change and are never deleted.
CREATE OR REPLACE FUNCTION public.enforce_deposit_law_immutable() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
BEGIN
    RAISE EXCEPTION USING
        MESSAGE = format('%s: law and vocabulary rows are never edited or deleted — deposits, rules and records cite them (v5.4.2-15)', TG_TABLE_NAME),
        ERRCODE = 'restrict_violation',
        HINT = 'A changed rule is a new deposit_rules row. A vocabulary row wrong from its first day is a reviewed platform repair (residual R4).';
END;
$$;
COMMENT ON FUNCTION public.enforce_deposit_law_immutable() IS
    'v5.4.2-15. BEFORE UPDATE OR DELETE, every role, on deposit_bases, deposit_triggers, deposit_customer_classes, deposit_waiver_classes and deposit_return_reasons: refused.';
DO $$
DECLARE t text;
BEGIN
    FOREACH t IN ARRAY ARRAY['deposit_bases', 'deposit_triggers', 'deposit_customer_classes', 'deposit_waiver_classes', 'deposit_return_reasons'] LOOP
        EXECUTE format('DROP TRIGGER IF EXISTS a_enforce_deposit_law_immutable ON public.%I', t);
        EXECUTE format('CREATE TRIGGER a_enforce_deposit_law_immutable BEFORE UPDATE OR DELETE ON public.%I FOR EACH ROW EXECUTE FUNCTION public.enforce_deposit_law_immutable()', t);
        EXECUTE format('ALTER TABLE public.%I ENABLE ALWAYS TRIGGER a_enforce_deposit_law_immutable', t);
    END LOOP;
END;
$$;

-- The Texas gas rows, seeded ONCE from what v5.4.2-06 enforced, effective
-- 2004-07-12 (the §7.45 text Kyle read; v5.4.2-13 uses the same date).
--   §7.45 bases (credit_evaluation, additional_trigger, tariff): waivable;
--     residential capped at 1/6 of estimated annual billing, per deposit
--     (-06; #55 rule 9 says combined — K4); cash earns interest after a
--     30-day minimum hold, retroactively to posting, simple, actual/365,
--     credited at refund; the return is mandatory on twelve bills with no
--     more than two delinquencies and a disqualifying disconnection, and on
--     account close, for cash (K5); whether it stays owed is unruled (K6).
--   §366: not waivable (K2), no cap, cash interest as above (-06 accrued on
--     every cash deposit), never a mandatory return (#54 rule 3).
--   legacy_unknown: deliberately no row — the core refuses to decide one.
DO $$
DECLARE
    r record;
    c_from CONSTANT date := DATE '2004-07-12';
BEGIN
    FOR r IN
        SELECT cls.code AS customer_class, b.code AS basis
          FROM (VALUES ('residential'), ('non_residential')) AS cls(code)
         CROSS JOIN (VALUES ('credit_evaluation'), ('additional_trigger'), ('tariff'), ('adequate_assurance_366')) AS b(code)
    LOOP
        IF EXISTS (SELECT 1 FROM public.deposit_rules x
                    WHERE x.state_code = 'TX' AND x.service_type = 'gas' AND x.customer_class = r.customer_class
                      AND x.basis = r.basis AND x.effective_from = c_from) THEN
            CONTINUE;
        END IF;
        IF r.basis = 'adequate_assurance_366' THEN
            INSERT INTO public.deposit_rules
                (state_code, service_type, customer_class, basis, waivable, cap_kind,
                 interest_bearing_instruments, interest_min_hold_days, interest_retroactive,
                 interest_method, interest_day_count, interest_credit_cadence,
                 refund_mandatory, effective_from, source_note)
            VALUES ('TX', 'gas', r.customer_class, r.basis, false, 'none',
                    ARRAY['cash'], 30, true, 'simple', 'actual_365', 'at_refund',
                    false, c_from,
                    '11 U.S.C. 366 adequate assurance: a federal permission, not a 16 TAC 7.45 deposit — no 7.45 cap, never refunded on 7.45''s triggers (decision table #54 rule 3); not reached by a 7.45 waiver per -06 D-40 (decision table #53 rank 0 says the family-violence waiver outranks it: Kyle question K2). Interest as on any cash deposit the utility holds (16 TAC 7.45; -06 accrued on every cash deposit).');
        ELSE
            INSERT INTO public.deposit_rules
                (state_code, service_type, customer_class, basis, waivable, cap_kind, cap_divisor, cap_scope,
                 interest_bearing_instruments, interest_min_hold_days, interest_retroactive,
                 interest_method, interest_day_count, interest_credit_cadence,
                 refund_mandatory, refund_after_count, refund_measure, refund_max_delinquencies,
                 refund_disqualify_on_disconnect, refund_on_account_close, refund_obligation_vests,
                 return_mandatory_instruments, effective_from, source_note)
            VALUES ('TX', 'gas', r.customer_class, r.basis, true,
                    CASE WHEN r.customer_class = 'residential' THEN 'fraction_of_annual_billing' ELSE 'none' END,
                    CASE WHEN r.customer_class = 'residential' THEN 6 END,
                    CASE WHEN r.customer_class = 'residential' THEN 'per_deposit' END,
                    ARRAY['cash'], 30, true, 'simple', 'actual_365', 'at_refund',
                    true, 12, 'bills', 2, true, true, NULL,
                    ARRAY['cash'], c_from,
                    '16 TAC 7.45 (CI-129 to CI-131): mandatory waivers (family violence 7.45(5)(C), age 65 with no balance, good payment history; a tariff may extend them) reach this basis (decision table #53 ranks 0-3, #55 rule 8); '
                    || CASE WHEN r.customer_class = 'residential' THEN 'the deposit may not exceed one-sixth of estimated annual billing (#53 rank 8; per deposit as -06 — #55 rule 9 says combined, Kyle question K4); ' ELSE 'no cap for this class (-06; Kyle question K1); ' END
                    || 'interest on cash: none if held 30 days or less, otherwise from the posting date (day 1, not day 31) at the rate in force, simple, actual/365, paid at refund (CI-130; #54 rules 5-7); refunded unasked after twelve bills paid with no more than two delinquencies, no disconnection for nonpayment and none currently delinquent, or on account close (CI-131; #54 rules 1-2); whether the refund stays owed if the customer falls behind before it is made is Kyle question K6.');
        END IF;
    END LOOP;
END;
$$;


-- ----------------------------------------------------------------------------
-- 4. Interest rates (R-D1): the utility's rate applied, the law's a reference
-- ----------------------------------------------------------------------------
-- The utility answers to the commission for the interest it pays, so the rate
-- it applies is its own row, and every accrual cites that row (section 8). A
-- utility in two states keeps a rate per state and service. The platform
-- keeps the published legal rate per state as a reference that nothing
-- reads to decide an accrual; a report lists where the two differ.

ALTER TABLE public.deposit_interest_rates
    ADD COLUMN IF NOT EXISTS state_code   text,
    ADD COLUMN IF NOT EXISTS service_type text;
-- Section 1 proved the table empty.
ALTER TABLE public.deposit_interest_rates ALTER COLUMN state_code SET NOT NULL;
ALTER TABLE public.deposit_interest_rates ALTER COLUMN service_type SET NOT NULL;
ALTER TABLE public.deposit_interest_rates DROP CONSTRAINT IF EXISTS deposit_interest_rates_state_code_check;
ALTER TABLE public.deposit_interest_rates ADD CONSTRAINT deposit_interest_rates_state_code_check
    CHECK ((state_code ~ '^[A-Z]{2}$'::text));
ALTER TABLE public.deposit_interest_rates DROP CONSTRAINT IF EXISTS deposit_interest_rates_service_type_check;
ALTER TABLE public.deposit_interest_rates ADD CONSTRAINT deposit_interest_rates_service_type_check
    CHECK ((service_type = ANY (ARRAY['water'::text, 'sewer'::text, 'electric'::text, 'gas'::text, 'stormwater'::text, 'trash'::text, 'reclaimed_water'::text])));
ALTER TABLE public.deposit_interest_rates DROP CONSTRAINT IF EXISTS deposit_interest_rates_tenant_effective_key;
ALTER TABLE public.deposit_interest_rates DROP CONSTRAINT IF EXISTS deposit_interest_rates_key;
ALTER TABLE public.deposit_interest_rates ADD CONSTRAINT deposit_interest_rates_key
    UNIQUE (tenant_id, state_code, service_type, effective_date);
-- Accruals cite a rate row with a composite key (section 8); added once, as
-- that foreign key depends on it.
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_constraint WHERE conname = 'deposit_interest_rates_id_tenant_id_key'
                    AND conrelid = 'public.deposit_interest_rates'::regclass) THEN
        ALTER TABLE public.deposit_interest_rates ADD CONSTRAINT deposit_interest_rates_id_tenant_id_key UNIQUE (id, tenant_id);
    END IF;
END;
$$;

-- The backdating guard, per (tenant, state, service): a rate can't be moved
-- under an accrual that has settled through its date at the rates then cited.
CREATE OR REPLACE FUNCTION public.enforce_deposit_interest_rate() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE v_settled date;
BEGIN
    PERFORM public.assert_same_tenant_user(NEW.created_by, NEW.tenant_id, 'created_by');
    NEW.created_at := now();
    SELECT max(e.period_end) INTO v_settled
      FROM public.deposit_events e
      JOIN public.deposit_interest_rates r ON r.id = e.rate_id
     WHERE e.event_type = 'interest_accrued' AND r.tenant_id = NEW.tenant_id
       AND r.state_code = NEW.state_code AND r.service_type = NEW.service_type;
    IF v_settled IS NOT NULL AND NEW.effective_date <= v_settled THEN
        RAISE EXCEPTION USING
            MESSAGE = format('deposit interest rate %s %s effective %s rejected: interest has already been accrued through %s at the rates it cites; a settled accrual is never re-rated (CI-125 / CI-130) — a correction is a new accrual period at the new rate from %s', NEW.state_code, NEW.service_type, NEW.effective_date, v_settled, v_settled + 1),
            ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$;
COMMENT ON FUNCTION public.enforce_deposit_interest_rate() IS
    'v5.4.2-06, re-issued by v5.4.2-15. BEFORE INSERT on deposit_interest_rates: created_by of the tenant; created_at stamped; refused on or before the latest period end of any accrual citing a rate row of the same tenant, state and service.';

COMMENT ON TABLE public.deposit_interest_rates IS
    'CI-125 / CI-130 (v5.4.2-06; v5.4.2-15, R-D1). The deposit interest rate THIS UTILITY applies, per state and service type, effective-dated (annual, as a fraction — 0.0287 = 2.87%). The utility is the regulated party and answers for it; every accrual cites the row it used (deposit_events.rate_id). Which row applies to a period is the core''s. The state''s published legal rate is a separate reference (deposit_interest_rate_law); deposit_interest_rate_discrepancies compares them. A new rate is a new row; rows are never edited or deleted; one backdated under a settled accrual is refused.';

CREATE TABLE IF NOT EXISTS public.deposit_interest_rate_law (
    id              uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    state_code      text NOT NULL,
    service_type    text NOT NULL,
    effective_from  date NOT NULL,
    effective_to    date,
    annual_rate     numeric(8,6) NOT NULL,
    source_note     text NOT NULL,
    created_at      timestamp with time zone DEFAULT now() NOT NULL,
    closed_at       timestamp with time zone,
    closed_by       text,
    CONSTRAINT deposit_interest_rate_law_pkey PRIMARY KEY (id),
    CONSTRAINT deposit_interest_rate_law_state_code_check CHECK ((state_code ~ '^[A-Z]{2}$'::text)),
    CONSTRAINT deposit_interest_rate_law_service_type_check
        CHECK ((service_type = ANY (ARRAY['water'::text, 'sewer'::text, 'electric'::text, 'gas'::text, 'stormwater'::text, 'trash'::text, 'reclaimed_water'::text]))),
    CONSTRAINT deposit_interest_rate_law_rate_check CHECK (((annual_rate >= (0)::numeric) AND (annual_rate <= (1)::numeric))),
    CONSTRAINT deposit_interest_rate_law_range_check CHECK (((effective_to IS NULL) OR (effective_to > effective_from))),
    CONSTRAINT deposit_interest_rate_law_source_note_check CHECK ((source_note ~ '[[:alnum:]]'::text)),
    CONSTRAINT deposit_interest_rate_law_no_overlap
        EXCLUDE USING gist (state_code WITH =, service_type WITH =, daterange(effective_from, effective_to, '[)'::text) WITH &&)
);
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.deposit_interest_rate_law FROM tally_app;
GRANT SELECT ON public.deposit_interest_rate_law TO tally_app;
COMMENT ON TABLE public.deposit_interest_rate_law IS
    'v5.4.2-15 (R-D1). Each state''s published legal deposit interest rate, per service type, dated and cited (Texas: one statewide rate a year, set by the PUCT, Utilities Code §183.003). A REFERENCE only: nothing reads it to decide an accrual — the rate applied is the utility''s (deposit_interest_rates). deposit_interest_rate_discrepancies compares the two. Platform-held; no overlap per state and service; never edited — closed once (stamped) and superseded. No rows are seeded: each is entered from its publication.';

CREATE OR REPLACE FUNCTION public.enforce_deposit_interest_rate_law_record() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    c_close_cols CONSTANT text[] := ARRAY['effective_to', 'closed_at', 'closed_by'];
BEGIN
    IF TG_OP = 'INSERT' THEN
        NEW.created_at := now();
        NEW.closed_at  := NULL;
        NEW.closed_by  := NULL;
        RETURN NEW;
    END IF;
    IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION USING
            MESSAGE = format('deposit_interest_rate_law %s: published rates are never deleted — close the row and add its successor (v5.4.2-15)', OLD.id),
            ERRCODE = 'restrict_violation';
    END IF;
    IF OLD.effective_to IS NOT NULL OR NEW.effective_to IS NULL
       OR (to_jsonb(NEW) - c_close_cols) <> (to_jsonb(OLD) - c_close_cols) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('deposit_interest_rate_law %s: published rates are never edited — close the row (effective_to, once, nothing else) and add its successor (v5.4.2-15)', OLD.id),
            ERRCODE = 'restrict_violation';
    END IF;
    NEW.closed_at := now();
    NEW.closed_by := session_user;
    RETURN NEW;
END;
$$;
COMMENT ON FUNCTION public.enforce_deposit_interest_rate_law_record() IS
    'v5.4.2-15. BEFORE INSERT OR UPDATE OR DELETE on deposit_interest_rate_law, every role: created_at stamped and born unclosed; never deleted; the only edit is a close, stamped.';
DROP TRIGGER IF EXISTS a_enforce_deposit_interest_rate_law_record ON public.deposit_interest_rate_law;
CREATE TRIGGER a_enforce_deposit_interest_rate_law_record BEFORE INSERT OR UPDATE OR DELETE ON public.deposit_interest_rate_law
    FOR EACH ROW EXECUTE FUNCTION public.enforce_deposit_interest_rate_law_record();
ALTER TABLE public.deposit_interest_rate_law ENABLE ALWAYS TRIGGER a_enforce_deposit_interest_rate_law_record;

-- ----------------------------------------------------------------------------
-- 5. deposits — what it was decided under; the Texas branches go
-- ----------------------------------------------------------------------------
-- A deposit records the jurisdiction (from the PREMISE, never the utility),
-- the customer class and the rule row the core decided it under, the cap and
-- the cap's basis whatever the state's kind, and the core version. -06's
-- legacy_unknown rows carry none of them: they cite no rule.

ALTER TABLE public.deposits
    ADD COLUMN IF NOT EXISTS state_code       text,
    ADD COLUMN IF NOT EXISTS service_type     text,
    ADD COLUMN IF NOT EXISTS customer_class   text,
    ADD COLUMN IF NOT EXISTS rule_id          uuid,
    ADD COLUMN IF NOT EXISTS cap_basis_kind   text,
    ADD COLUMN IF NOT EXISTS cap_basis_amount numeric(12,2),
    ADD COLUMN IF NOT EXISTS decided_by       text;

ALTER TABLE public.deposits DROP CONSTRAINT IF EXISTS deposits_class_fkey;
ALTER TABLE public.deposits ADD CONSTRAINT deposits_class_fkey
    FOREIGN KEY (state_code, service_type, customer_class)
    REFERENCES public.deposit_customer_classes(state_code, service_type, class_code);
ALTER TABLE public.deposits DROP CONSTRAINT IF EXISTS deposits_rule_fkey;
ALTER TABLE public.deposits ADD CONSTRAINT deposits_rule_fkey
    FOREIGN KEY (rule_id) REFERENCES public.deposit_rules(id);
-- The jurisdiction, class, rule and core version come together or not at all
-- (not at all = a carried legacy row; a new deposit must cite a rule, below).
ALTER TABLE public.deposits DROP CONSTRAINT IF EXISTS deposits_decision_check;
ALTER TABLE public.deposits ADD CONSTRAINT deposits_decision_check
    CHECK ((((rule_id IS NULL) AND (state_code IS NULL) AND (service_type IS NULL) AND (customer_class IS NULL) AND (decided_by IS NULL))
         OR ((rule_id IS NOT NULL) AND (state_code IS NOT NULL) AND (service_type IS NOT NULL) AND (customer_class IS NOT NULL)
             AND (decided_by IS NOT NULL) AND (decided_by ~ '[[:alnum:]]'::text))));
ALTER TABLE public.deposits DROP CONSTRAINT IF EXISTS deposits_cap_basis_kind_check;
ALTER TABLE public.deposits ADD CONSTRAINT deposits_cap_basis_kind_check
    CHECK (((cap_basis_kind IS NULL) OR (cap_basis_kind = ANY (ARRAY['fraction_of_annual_billing'::text, 'months_of_billing'::text, 'fixed_amount'::text]))));
ALTER TABLE public.deposits DROP CONSTRAINT IF EXISTS deposits_cap_basis_amount_check;
ALTER TABLE public.deposits ADD CONSTRAINT deposits_cap_basis_amount_check
    CHECK (((cap_basis_amount IS NULL) OR (cap_basis_amount > (0)::numeric)));

-- basis and trigger_basis become vocabulary rows.
ALTER TABLE public.deposits DROP CONSTRAINT IF EXISTS deposits_basis_check;
ALTER TABLE public.deposits DROP CONSTRAINT IF EXISTS deposits_basis_fkey;
ALTER TABLE public.deposits ADD CONSTRAINT deposits_basis_fkey
    FOREIGN KEY (basis) REFERENCES public.deposit_bases(basis_code);
ALTER TABLE public.deposits DROP CONSTRAINT IF EXISTS deposits_trigger_basis_check;
ALTER TABLE public.deposits DROP CONSTRAINT IF EXISTS deposits_trigger_basis_fkey;
ALTER TABLE public.deposits ADD CONSTRAINT deposits_trigger_basis_fkey
    FOREIGN KEY (trigger_basis) REFERENCES public.deposit_triggers(trigger_code);

CREATE OR REPLACE FUNCTION public.enforce_deposit() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_cust public.customers%ROWTYPE;
    v_insertable boolean;
    v_rule public.deposit_rules%ROWTYPE;
BEGIN
    IF TG_OP = 'INSERT' THEN
        SELECT * INTO v_cust FROM public.customers c WHERE c.id = NEW.customer_id;
        IF NOT FOUND THEN
            RAISE EXCEPTION USING MESSAGE = format('deposit rejected: customer %s not found (or not visible)', NEW.customer_id), ERRCODE = 'foreign_key_violation';
        END IF;
        SELECT b.insertable INTO v_insertable FROM public.deposit_bases b WHERE b.basis_code = NEW.basis;
        IF v_insertable IS NOT TRUE THEN
            RAISE EXCEPTION USING MESSAGE = format('deposit rejected: basis %s exists only for carried history — record the basis that governs this deposit', NEW.basis), ERRCODE = 'check_violation';
        END IF;
        IF NEW.status <> 'held' OR NEW.refunded_on IS NOT NULL OR NEW.released_on IS NOT NULL THEN
            RAISE EXCEPTION USING MESSAGE = 'deposit rejected: a deposit is born held; status / refunded_on / released_on are projected from deposit_events', ERRCODE = 'check_violation';
        END IF;
        PERFORM public.assert_same_tenant_user(NEW.created_by, NEW.tenant_id, 'created_by');
        IF NEW.source_payment_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.payments p WHERE p.id = NEW.source_payment_id AND p.customer_id = NEW.customer_id AND coalesce(p.is_deposit, false)) THEN
            RAISE EXCEPTION USING MESSAGE = 'deposit rejected: source_payment_id must be a payment of the same customer flagged is_deposit', ERRCODE = 'check_violation';
        END IF;
        -- The rule the core decided it under: one for this deposit's state,
        -- service, class and basis, in force on its posting date.
        IF NEW.rule_id IS NULL THEN
            RAISE EXCEPTION USING
                MESSAGE = 'deposit rejected: a deposit records the deposit_rules row it was decided under (rule_id), with its state, service type, customer class and the core version (decided_by) — v5.4.2-15',
                ERRCODE = 'check_violation';
        END IF;
        SELECT * INTO v_rule FROM public.deposit_rules r WHERE r.id = NEW.rule_id;
        IF v_rule.state_code IS DISTINCT FROM NEW.state_code OR v_rule.service_type IS DISTINCT FROM NEW.service_type
           OR v_rule.customer_class IS DISTINCT FROM NEW.customer_class OR v_rule.basis IS DISTINCT FROM NEW.basis THEN
            RAISE EXCEPTION USING
                MESSAGE = format('deposit rejected: rule %s is for %s %s, class %s, basis %s — not this deposit''s %s %s, %s, %s (v5.4.2-15)', NEW.rule_id, v_rule.state_code, v_rule.service_type, v_rule.customer_class, v_rule.basis, NEW.state_code, NEW.service_type, NEW.customer_class, NEW.basis),
                ERRCODE = 'check_violation';
        END IF;
        IF NOT (daterange(v_rule.effective_from, v_rule.effective_to, '[)') @> NEW.posted_on) THEN
            RAISE EXCEPTION USING
                MESSAGE = format('deposit rejected: rule %s is in force %s to %s, not on the posting date %s (v5.4.2-15)', NEW.rule_id, v_rule.effective_from, coalesce(v_rule.effective_to::text, 'open'), NEW.posted_on),
                ERRCODE = 'check_violation';
        END IF;
        -- The cap is recorded exactly when the rule has one, with its basis
        -- of the rule's kind (a fixed amount needs no basis figure).
        IF v_rule.cap_kind = 'none' THEN
            IF NEW.cap_amount IS NOT NULL OR NEW.cap_basis_kind IS NOT NULL OR NEW.cap_basis_amount IS NOT NULL OR NEW.cap_binding THEN
                RAISE EXCEPTION USING
                    MESSAGE = format('deposit rejected: rule %s sets no cap; the deposit records none (v5.4.2-15)', NEW.rule_id),
                    ERRCODE = 'check_violation';
            END IF;
        ELSIF NEW.cap_amount IS NULL OR NEW.cap_basis_kind IS DISTINCT FROM v_rule.cap_kind
              OR ((NEW.cap_basis_amount IS NULL) <> (v_rule.cap_kind = 'fixed_amount')) THEN
            RAISE EXCEPTION USING
                MESSAGE = format('deposit rejected: rule %s caps the deposit (%s); record cap_amount, cap_basis_kind = %s and the basis figure it was computed from (cap_basis_amount; none for a fixed amount) — v5.4.2-15', NEW.rule_id, v_rule.cap_kind, v_rule.cap_kind),
                ERRCODE = 'check_violation';
        END IF;
        RETURN NEW;
    END IF;

    -- UPDATE: identity frozen; projection columns only from inside the events trigger.
    IF OLD.id <> NEW.id OR OLD.tenant_id <> NEW.tenant_id OR OLD.customer_id <> NEW.customer_id OR OLD.basis <> NEW.basis
       OR OLD.trigger_basis IS DISTINCT FROM NEW.trigger_basis OR OLD.instrument <> NEW.instrument OR OLD.principal <> NEW.principal
       OR OLD.posted_on <> NEW.posted_on OR OLD.source_payment_id IS DISTINCT FROM NEW.source_payment_id
       OR OLD.cap_amount IS DISTINCT FROM NEW.cap_amount OR OLD.cap_basis_kind IS DISTINCT FROM NEW.cap_basis_kind
       OR OLD.cap_basis_amount IS DISTINCT FROM NEW.cap_basis_amount
       OR OLD.cap_binding <> NEW.cap_binding OR OLD.legacy_interest_earned IS DISTINCT FROM NEW.legacy_interest_earned
       OR OLD.state_code IS DISTINCT FROM NEW.state_code OR OLD.service_type IS DISTINCT FROM NEW.service_type
       OR OLD.customer_class IS DISTINCT FROM NEW.customer_class OR OLD.rule_id IS DISTINCT FROM NEW.rule_id
       OR OLD.decided_by IS DISTINCT FROM NEW.decided_by
       OR OLD.created_by IS DISTINCT FROM NEW.created_by OR OLD.created_at <> NEW.created_at THEN
        RAISE EXCEPTION USING
            MESSAGE = format('deposit %s: identity (customer, basis, instrument, principal, posted_on, cap, source, jurisdiction, class, rule, core version) is frozen — a wrong deposit is refunded/released and re-posted', OLD.id),
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
    'v5.4.2-06, re-issued by v5.4.2-15 (deposits at parity). BEFORE INSERT OR UPDATE on deposits. INSERT: the customer is visible; the basis is insertable (deposit_bases); born held; created_by of the tenant; a source payment of the same customer flagged is_deposit; the deposit cites the deposit_rules row it was decided under — one for its state, service, class and basis, in force on its posting date; the cap is recorded exactly when that rule has one, with the rule''s kind. UPDATE: identity frozen; status columns only from the events. Decides nothing the law decides: waivers, the cap''s size and who may be charged are the core''s.';

ALTER TABLE public.deposits DROP COLUMN IF EXISTS refund_eligibility_on;
ALTER TABLE public.deposits DROP COLUMN IF EXISTS cap_basis_annual_billing;

COMMENT ON TABLE public.deposits IS
    'A-21 (v5.4.2-06; v5.4.2-15 at parity): one record per deposit. basis (a deposit_bases row: why it was taken), trigger_basis for an additional deposit, instrument (cash, or a §366(c)(1)(A) form or guarantor; non-cash carries issuer/reference/expiry), principal, posted_on, and what it was decided under: state_code / service_type (from the premise), customer_class, the deposit_rules row (rule_id) and the core version (decided_by). Its cap as recorded at the decision (cap_amount, cap_basis_kind, cap_basis_amount, cap_binding), exactly when the rule has one. Identity is frozen after insert. status / refunded_on / released_on are a PROJECTION of deposit_events: held → partial_applied / applied → refund_pending → refunded; non-cash → released. A legacy_unknown row (carried by -06) cites no rule; the core refuses to decide one. Whether a deposit may be required, how large, and what it earns are the core''s (application/deposits-rules-for-the-core.md).';
COMMENT ON COLUMN public.deposits.cap_amount IS
    'The cap as computed at the deposit decision, recorded exactly when the cited rule has one (deposit_rules.cap_kind); principal ≤ cap_amount (CHECK); cap_binding when it reduced the amount — the customer is entitled to know (decision table #53). The computation is the core''s.';
COMMENT ON COLUMN public.deposits.cap_basis_kind IS
    'The kind of cap the rule set (= deposit_rules.cap_kind), recorded with the deposit so the basis reads the same whatever the state.';
COMMENT ON COLUMN public.deposits.cap_basis_amount IS
    'The figure the cap was computed from: estimated annual billing (fraction_of_annual_billing), estimated monthly billing (months_of_billing); NULL for a fixed amount.';
COMMENT ON COLUMN public.deposits.state_code IS
    'The state whose law the deposit was decided under — the premise''s, never the utility''s home state. NULL only on a carried legacy row.';
COMMENT ON COLUMN public.deposits.rule_id IS
    'The deposit_rules row the core decided this deposit under: for its state, service, class and basis, in force on posted_on. Rule rows never change, so the citation stays true.';
COMMENT ON COLUMN public.deposits.decided_by IS
    'The calculation core''s version that decided the deposit.';


-- The rate report (section 4's, here because it reads deposits.state_code).
-- A utility rate row is in force from its date to the next row
-- of the same tenant, state and service. rate_differs: it overlaps a
-- published rate it does not equal. no_utility_rate: a published rate covers
-- days before the utility's first row, for a tenant that keeps rates or holds
-- deposits in that state and service. Whether a difference is lawful (a
-- tariff paying more) is the utility's and the core's call.
CREATE OR REPLACE VIEW public.deposit_interest_rate_discrepancies WITH (security_invoker = true) AS
    WITH u AS (
        SELECT r.id, r.tenant_id, r.state_code, r.service_type, r.effective_date, r.annual_rate,
               lead(r.effective_date) OVER (PARTITION BY r.tenant_id, r.state_code, r.service_type ORDER BY r.effective_date) AS next_date
          FROM public.deposit_interest_rates r
    ),
    scope AS (
        SELECT DISTINCT r.tenant_id, r.state_code, r.service_type FROM public.deposit_interest_rates r
        UNION
        SELECT DISTINCT d.tenant_id, d.state_code, d.service_type FROM public.deposits d WHERE d.state_code IS NOT NULL
    ),
    first_rate AS (
        SELECT s.tenant_id, s.state_code, s.service_type,
               (SELECT min(r.effective_date) FROM public.deposit_interest_rates r
                 WHERE r.tenant_id = s.tenant_id AND r.state_code = s.state_code AND r.service_type = s.service_type) AS first_date
          FROM scope s
    )
    SELECT 'rate_differs'::text AS discrepancy, u.tenant_id, u.state_code, u.service_type,
           u.id AS rate_id, l.id AS law_rate_id,
           greatest(u.effective_date, l.effective_from) AS from_date,
           CASE WHEN u.next_date IS NULL THEN l.effective_to
                WHEN l.effective_to IS NULL THEN u.next_date
                ELSE least(u.next_date, l.effective_to) END AS to_date_exclusive,
           u.annual_rate AS utility_rate, l.annual_rate AS law_rate
      FROM u
      JOIN public.deposit_interest_rate_law l
        ON l.state_code = u.state_code AND l.service_type = u.service_type
       AND daterange(u.effective_date, u.next_date, '[)') && daterange(l.effective_from, l.effective_to, '[)')
       AND u.annual_rate <> l.annual_rate
    UNION ALL
    SELECT 'no_utility_rate'::text, f.tenant_id, f.state_code, f.service_type,
           NULL::uuid, l.id,
           l.effective_from,
           CASE WHEN f.first_date IS NULL THEN l.effective_to
                WHEN l.effective_to IS NULL THEN f.first_date
                ELSE least(f.first_date, l.effective_to) END,
           NULL::numeric, l.annual_rate
      FROM first_rate f
      JOIN public.deposit_interest_rate_law l
        ON l.state_code = f.state_code AND l.service_type = f.service_type
       AND (f.first_date IS NULL OR l.effective_from < f.first_date);
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.deposit_interest_rate_discrepancies FROM tally_app;
GRANT SELECT ON public.deposit_interest_rate_discrepancies TO tally_app;
COMMENT ON VIEW public.deposit_interest_rate_discrepancies IS
    'v5.4.2-15 (R-D1). Where the rate a utility applies differs from its state''s published legal rate (rate_differs: the overlapping span, both rates), and where a published rate covers days before the utility''s first rate row for a state and service it keeps rates or deposits in (no_utility_rate). A read over two records, not a refusal: whether a difference is lawful is the utility''s and the core''s call. Invoker rights: a tenant sees its own rows.';


-- ----------------------------------------------------------------------------
-- 6. Waiver determinations: the class is a law row
-- ----------------------------------------------------------------------------
ALTER TABLE public.deposit_waiver_determinations
    ADD COLUMN IF NOT EXISTS state_code   text,
    ADD COLUMN IF NOT EXISTS service_type text;
-- Section 1 proved the table empty.
ALTER TABLE public.deposit_waiver_determinations ALTER COLUMN state_code SET NOT NULL;
ALTER TABLE public.deposit_waiver_determinations ALTER COLUMN service_type SET NOT NULL;
ALTER TABLE public.deposit_waiver_determinations DROP CONSTRAINT IF EXISTS deposit_waiver_determinations_class_check;
ALTER TABLE public.deposit_waiver_determinations DROP CONSTRAINT IF EXISTS deposit_waiver_determinations_certification_check;
ALTER TABLE public.deposit_waiver_determinations DROP CONSTRAINT IF EXISTS deposit_waiver_determinations_class_fkey;
ALTER TABLE public.deposit_waiver_determinations ADD CONSTRAINT deposit_waiver_determinations_class_fkey
    FOREIGN KEY (state_code, service_type, waiver_class)
    REFERENCES public.deposit_waiver_classes(state_code, service_type, class_code);

CREATE OR REPLACE FUNCTION public.enforce_deposit_waiver_determination() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_cert boolean;
BEGIN
    PERFORM public.assert_same_tenant_user(NEW.determined_by, NEW.tenant_id, 'determined_by');
    SELECT w.requires_certification INTO v_cert FROM public.deposit_waiver_classes w
     WHERE w.state_code = NEW.state_code AND w.service_type = NEW.service_type AND w.class_code = NEW.waiver_class;
    IF v_cert AND (NEW.certification_reference IS NULL OR NEW.certification_reference !~ '[[:alnum:]]') THEN
        RAISE EXCEPTION USING
            MESSAGE = format('deposit waiver determination rejected: a %s %s %s determination rests on a certification — record its reference (v5.4.2-15)', NEW.state_code, NEW.service_type, NEW.waiver_class),
            ERRCODE = 'check_violation';
    END IF;
    NEW.created_at := now();
    RETURN NEW;
END;
$$;
COMMENT ON FUNCTION public.enforce_deposit_waiver_determination() IS
    'v5.4.2-15. BEFORE INSERT on deposit_waiver_determinations: determined_by of the tenant; a class whose deposit_waiver_classes row requires a certification carries its reference; created_at stamped.';
DROP TRIGGER IF EXISTS a_enforce_deposit_waiver_determination ON public.deposit_waiver_determinations;
CREATE TRIGGER a_enforce_deposit_waiver_determination BEFORE INSERT ON public.deposit_waiver_determinations
    FOR EACH ROW EXECUTE FUNCTION public.enforce_deposit_waiver_determination();
ALTER TABLE public.deposit_waiver_determinations ENABLE ALWAYS TRIGGER a_enforce_deposit_waiver_determination;

COMMENT ON TABLE public.deposit_waiver_determinations IS
    'CI-129 (v5.4.2-06; v5.4.2-15 at parity): a recorded deposit-waiver determination — that a customer qualified, under which state''s class (deposit_waiver_classes: state, service, class), on which date, with the certification''s reference and expiry where the class rests on one. A point-in-time act, not a re-derivation: a lapse later does not reopen a deposit lawfully waived. Whether a waiver in force blocks a deposit is the core''s, from the rule row (deposit_rules.waivable). Append-only. SENSITIVE: the family-violence class is among the most sensitive data the platform holds; RLS applies, no column-level control exists (flagged).';


-- ----------------------------------------------------------------------------
-- 7. The return-due record (R-D2)
-- ----------------------------------------------------------------------------
-- WRITTEN BY THE CORE when a deposit's mandatory return falls due — once,
-- when the answer changes, never per check. The due row cites the rule and
-- the core version; its evidence rows say why (a reason per row) and on what
-- (the bills the core judged, with its classification of each, or the
-- customer's state change), written in the due row's own transaction. A due
-- row found wrong — a reversed payment, a corrected bill, a core bug — is
-- withdrawn by a separate row; a corrected answer is a new due row that
-- names the one it supersedes. A customer falling behind after qualifying is
-- NOT a withdrawal: whether the return stays owed is law
-- (deposit_rules.refund_obligation_vests, K6), the core's.
--
-- WHAT THE DATABASE KEEPS TRUE: the cited rule is the deposit's own and makes
-- the return mandatory for its instrument (a stored attribute, not an
-- evaluation); the deposit is not refunded or released; at most one live
-- (unwithdrawn) due row per deposit, serialised on the deposit row (the lock
-- every deposit event takes); every due row has evidence; evidence is of the
-- deposit's customer, from on or after posting, of its reason's kind, and
-- only in its due row's transaction; withdrawals once each; stamps.

CREATE SEQUENCE IF NOT EXISTS public.deposit_return_due_seq;
GRANT USAGE, SELECT ON SEQUENCE public.deposit_return_due_seq TO tally_app;

CREATE TABLE IF NOT EXISTS public.deposit_return_due (
    id                  uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id           uuid NOT NULL,
    deposit_id          uuid NOT NULL,
    rule_id             uuid NOT NULL,
    due_on              date NOT NULL,
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
    CONSTRAINT deposit_return_due_calculated_by_check CHECK ((calculated_by ~ '[[:alnum:]]'::text))
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
    invoice_id               uuid,
    classification           text,
    customer_state_event_id  uuid,
    CONSTRAINT deposit_return_due_evidence_pkey PRIMARY KEY (id),
    CONSTRAINT deposit_return_due_evidence_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id),
    CONSTRAINT deposit_return_due_evidence_due_fkey FOREIGN KEY (due_id, tenant_id) REFERENCES public.deposit_return_due(id, tenant_id),
    CONSTRAINT deposit_return_due_evidence_reason_fkey FOREIGN KEY (reason_code) REFERENCES public.deposit_return_reasons(reason_code),
    CONSTRAINT deposit_return_due_evidence_invoice_fkey FOREIGN KEY (invoice_id, tenant_id) REFERENCES public.invoices(id, tenant_id),
    CONSTRAINT deposit_return_due_evidence_state_event_fkey FOREIGN KEY (customer_state_event_id) REFERENCES public.customer_state_events(id),
    -- One record per row: a bill with the core's classification of it, or a
    -- state change with none.
    CONSTRAINT deposit_return_due_evidence_subject_check
        CHECK ((((invoice_id IS NOT NULL) AND (customer_state_event_id IS NULL) AND (classification IS NOT NULL))
             OR ((invoice_id IS NULL) AND (customer_state_event_id IS NOT NULL) AND (classification IS NULL)))),
    CONSTRAINT deposit_return_due_evidence_classification_check
        CHECK (((classification IS NULL) OR (classification = ANY (ARRAY['clean'::text, 'delinquent'::text, 'not_counted'::text])))),
    CONSTRAINT deposit_return_due_evidence_key
        UNIQUE NULLS NOT DISTINCT (due_id, reason_code, invoice_id, customer_state_event_id)
);
CREATE INDEX IF NOT EXISTS idx_deposit_return_due_evidence_tenant ON public.deposit_return_due_evidence USING btree (tenant_id);
CREATE INDEX IF NOT EXISTS idx_deposit_return_due_evidence_due ON public.deposit_return_due_evidence USING btree (due_id);
ALTER TABLE public.deposit_return_due_evidence ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.deposit_return_due_evidence FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_isolation ON public.deposit_return_due_evidence;
CREATE POLICY tenant_isolation ON public.deposit_return_due_evidence USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));
REVOKE UPDATE, DELETE, TRUNCATE ON public.deposit_return_due_evidence FROM tally_app;

CREATE OR REPLACE FUNCTION public.enforce_deposit_return_due_record() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    d public.deposits%ROWTYPE;
    v_rule public.deposit_rules%ROWTYPE;
    v_live uuid;
BEGIN
    -- The deposit row is the mutex: every deposit event locks it the same way,
    -- so a due row and a refund, or two due rows, cannot cross.
    SELECT * INTO d FROM public.deposits x WHERE x.id = NEW.deposit_id AND x.tenant_id = NEW.tenant_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING MESSAGE = format('deposit return due: deposit %s not found (or not visible)', NEW.deposit_id), ERRCODE = 'foreign_key_violation';
    END IF;
    IF d.rule_id IS DISTINCT FROM NEW.rule_id THEN
        RAISE EXCEPTION USING
            MESSAGE = format('deposit return due: it cites rule %s; deposit %s was decided under %s (v5.4.2-15)', NEW.rule_id, d.id, coalesce(d.rule_id::text, 'no rule — a carried legacy deposit')),
            ERRCODE = 'check_violation';
    END IF;
    SELECT * INTO v_rule FROM public.deposit_rules r WHERE r.id = NEW.rule_id;
    IF v_rule.refund_mandatory IS NOT TRUE
       OR NOT coalesce(d.instrument = ANY (v_rule.return_mandatory_instruments), false) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('deposit return due: rule %s makes no mandatory return of a %s deposit (refund_mandatory, return_mandatory_instruments) — v5.4.2-15', NEW.rule_id, d.instrument),
            ERRCODE = 'check_violation';
    END IF;
    IF d.status IN ('refunded', 'released') THEN
        RAISE EXCEPTION USING
            MESSAGE = format('deposit return due: deposit %s is already %s (v5.4.2-15)', d.id, d.status),
            ERRCODE = 'check_violation';
    END IF;
    IF NEW.due_on < d.posted_on THEN
        RAISE EXCEPTION USING
            MESSAGE = format('deposit return due: due_on %s precedes the posting date %s (v5.4.2-15)', NEW.due_on, d.posted_on),
            ERRCODE = 'check_violation';
    END IF;
    SELECT r.id INTO v_live FROM public.deposit_return_due r
     WHERE r.deposit_id = d.id
       AND NOT EXISTS (SELECT 1 FROM public.deposit_return_due_withdrawals w WHERE w.due_id = r.id)
     LIMIT 1;
    IF v_live IS NOT NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('deposit return due: deposit %s already has a live due row (%s); the answer has not changed — withdraw that row first if it was wrong (v5.4.2-15)', d.id, v_live),
            ERRCODE = 'unique_violation';
    END IF;
    IF NEW.supersedes_due_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM public.deposit_return_due r
          JOIN public.deposit_return_due_withdrawals w ON w.due_id = r.id
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
    'v5.4.2-15 (R-D2). BEFORE INSERT on deposit_return_due: locks the deposit row (the same lock every deposit event takes); the cited rule is the deposit''s own and its stored attributes make the return mandatory for the deposit''s instrument; the deposit is not refunded or released; due_on is on or after posting; no live (unwithdrawn) due row exists for the deposit; a superseded row is a withdrawn row of the same deposit; stamps created_at, created_by (session user), due_seq and recorded_txid (the transaction its evidence must be written in). Judges nothing the core computed.';
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
    'v5.4.2-15. Deferred constraint trigger, AFTER INSERT on deposit_return_due: at commit the due row has at least one evidence row (its reason and what it rests on).';
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
    v_due record;
    v_kind text;
BEGIN
    SELECT r.recorded_txid, d.customer_id, d.posted_on INTO v_due
      FROM public.deposit_return_due r JOIN public.deposits d ON d.id = r.deposit_id
     WHERE r.id = NEW.due_id;
    IF v_due.recorded_txid IS DISTINCT FROM txid_current() THEN
        RAISE EXCEPTION USING
            MESSAGE = format('deposit return due evidence: due row %s was recorded in an earlier transaction; its evidence is complete (v5.4.2-15)', NEW.due_id),
            ERRCODE = 'restrict_violation',
            HINT = 'Withdraw the row and record a new one, with its evidence, in one transaction.';
    END IF;
    SELECT x.evidence_kind INTO v_kind FROM public.deposit_return_reasons x WHERE x.reason_code = NEW.reason_code;
    IF (v_kind = 'invoice') <> (NEW.invoice_id IS NOT NULL) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('deposit return due evidence: reason %s rests on %s records (v5.4.2-15)', NEW.reason_code, CASE v_kind WHEN 'invoice' THEN 'invoice' ELSE 'customer state event' END),
            ERRCODE = 'check_violation';
    END IF;
    IF NEW.invoice_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM public.invoices i WHERE i.id = NEW.invoice_id AND i.customer_id = v_due.customer_id AND i.invoice_date >= v_due.posted_on) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('deposit return due evidence: invoice %s is not a bill of the deposit''s customer dated on or after its posting (v5.4.2-15)', NEW.invoice_id),
            ERRCODE = 'check_violation';
    END IF;
    IF NEW.customer_state_event_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM public.customer_state_events s WHERE s.id = NEW.customer_state_event_id AND s.customer_id = v_due.customer_id) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('deposit return due evidence: state event %s is not the deposit''s customer''s (v5.4.2-15)', NEW.customer_state_event_id),
            ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$;
COMMENT ON FUNCTION public.enforce_deposit_return_due_evidence() IS
    'v5.4.2-15. BEFORE INSERT on deposit_return_due_evidence: only in its due row''s transaction (deposit_return_due.recorded_txid); a bill exactly when its reason rests on bills (deposit_return_reasons.evidence_kind); the bill is the deposit''s customer''s and dated on or after posting; a state event is the deposit''s customer''s. Which bills count and how is the core''s.';
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
    -- The same mutex as a new due row.
    PERFORM 1 FROM public.deposits d WHERE d.id = v_deposit FOR UPDATE;
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
    'v5.4.2-15. BEFORE INSERT on deposit_return_due_withdrawals: the due row is visible; locks its deposit row (the due-row mutex); stamps created_at and created_by. A withdrawal says the due row was wrong; it moves no money (a return already made is corrected through deposit_events).';
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
    'v5.4.2-15 (R-D2). The core''s record that a deposit''s mandatory return fell due: the deposit, the date, the rule row (the deposit''s own), the inputs and their fingerprint, the core version, stamped. Written when the answer changes, never per check; the core checks on the events that can change it (payment, bill past due, status change, reversal, correction). Its reasons and what they rest on are deposit_return_due_evidence, in the same transaction. A row found wrong is withdrawn (deposit_return_due_withdrawals) and a corrected answer is a new row naming it (supersedes_due_id). At most one live row per deposit. Append-only.';
COMMENT ON TABLE public.deposit_return_due_evidence IS
    'v5.4.2-15 (R-D2). Why a return fell due and on what: one row per reason and record — a bill with the core''s classification of it (clean, delinquent, not_counted), or the customer''s state change. Written in its due row''s transaction; append-only. The counts are derived from these rows.';
COMMENT ON TABLE public.deposit_return_due_withdrawals IS
    'v5.4.2-15 (R-D2). A due row found wrong (a reversed payment, a corrected bill, a core bug), withdrawn once with the reason, by a person or the core (calculated_by when the core). It moves no money. A customer falling behind after qualifying is not a withdrawal: whether the return stays owed is deposit_rules.refund_obligation_vests (K6). Append-only.';

-- The operators' list: recorded answers, not computed law.
CREATE OR REPLACE VIEW public.deposits_return_owed WITH (security_invoker = true) AS
    SELECT r.id AS due_id, r.tenant_id, d.customer_id, r.deposit_id, r.due_on, r.rule_id,
           (SELECT array_agg(DISTINCT e.reason_code ORDER BY e.reason_code)
              FROM public.deposit_return_due_evidence e WHERE e.due_id = r.id) AS reasons,
           d.instrument, d.status AS deposit_status, b.remainder,
           b.interest_accrued - b.interest_credited AS interest_uncredited,
           r.calculated_by
      FROM public.deposit_return_due r
      JOIN public.deposits d ON d.id = r.deposit_id
     CROSS JOIN LATERAL public.deposit_balance(d.id) b
     WHERE NOT EXISTS (SELECT 1 FROM public.deposit_return_due_withdrawals w WHERE w.due_id = r.id)
       AND d.status IN ('held', 'partial_applied', 'applied');
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.deposits_return_owed FROM tally_app;
GRANT SELECT ON public.deposits_return_owed TO tally_app;
COMMENT ON VIEW public.deposits_return_owed IS
    'v5.4.2-15 (R-D2; Kyle #54). Deposit returns owed and not started: live (unwithdrawn) return-due rows on deposits with no refund or release begun. A fully applied deposit stays listed until its zero refund is recorded — interest may still be owed at refund. Reads recorded answers; computes no law. Invoker rights.';


-- ----------------------------------------------------------------------------
-- 8. deposit_events — the arithmetic stays, the law goes
-- ----------------------------------------------------------------------------
ALTER TABLE public.deposit_events
    ADD COLUMN IF NOT EXISTS rate_id        uuid,
    ADD COLUMN IF NOT EXISTS rule_id        uuid,
    ADD COLUMN IF NOT EXISTS calculated_by  text,
    ADD COLUMN IF NOT EXISTS return_due_id  uuid;

ALTER TABLE public.deposit_events DROP CONSTRAINT IF EXISTS deposit_events_rate_fkey;
ALTER TABLE public.deposit_events ADD CONSTRAINT deposit_events_rate_fkey
    FOREIGN KEY (rate_id, tenant_id) REFERENCES public.deposit_interest_rates(id, tenant_id);
ALTER TABLE public.deposit_events DROP CONSTRAINT IF EXISTS deposit_events_rule_fkey;
ALTER TABLE public.deposit_events ADD CONSTRAINT deposit_events_rule_fkey
    FOREIGN KEY (rule_id) REFERENCES public.deposit_rules(id);
ALTER TABLE public.deposit_events DROP CONSTRAINT IF EXISTS deposit_events_return_due_fkey;
ALTER TABLE public.deposit_events ADD CONSTRAINT deposit_events_return_due_fkey
    FOREIGN KEY (return_due_id, tenant_id) REFERENCES public.deposit_return_due(id, tenant_id);
-- An accrual carries its period, rate, principal basis, the rate row and rule
-- row it used, and the core version; nothing else does.
ALTER TABLE public.deposit_events DROP CONSTRAINT IF EXISTS deposit_events_accrual_fields_check;
ALTER TABLE public.deposit_events ADD CONSTRAINT deposit_events_accrual_fields_check
    CHECK ((((event_type = 'interest_accrued'::text) AND (period_start IS NOT NULL) AND (period_end IS NOT NULL) AND (period_end >= period_start)
             AND (rate_applied IS NOT NULL) AND (principal_basis IS NOT NULL) AND (principal_basis > (0)::numeric)
             AND (rate_id IS NOT NULL) AND (rule_id IS NOT NULL) AND (calculated_by IS NOT NULL) AND (calculated_by ~ '[[:alnum:]]'::text))
         OR ((event_type <> 'interest_accrued'::text) AND (period_start IS NULL) AND (period_end IS NULL) AND (rate_applied IS NULL)
             AND (principal_basis IS NULL) AND (rate_id IS NULL) AND (rule_id IS NULL) AND (calculated_by IS NULL))));
ALTER TABLE public.deposit_events DROP CONSTRAINT IF EXISTS deposit_events_return_due_check;
ALTER TABLE public.deposit_events ADD CONSTRAINT deposit_events_return_due_check
    CHECK (((return_due_id IS NULL) OR (event_type = ANY (ARRAY['refund_initiated'::text, 'refunded'::text, 'released'::text]))));

CREATE OR REPLACE FUNCTION public.enforce_deposit_event() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    d public.deposits%ROWTYPE;
    b record;
    v_rate public.deposit_interest_rates%ROWTYPE;
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
    -- A return that cites the due row it settles cites a live one of this deposit.
    IF NEW.return_due_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM public.deposit_return_due r
         WHERE r.id = NEW.return_due_id AND r.deposit_id = d.id
           AND NOT EXISTS (SELECT 1 FROM public.deposit_return_due_withdrawals w WHERE w.due_id = r.id)) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('deposit event rejected: return_due_id %s is not a live (unwithdrawn) due row of deposit %s (v5.4.2-15)', NEW.return_due_id, d.id),
            ERRCODE = 'check_violation';
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
            RAISE EXCEPTION USING MESSAGE = format('deposit %s: interest has already accrued through %s on the principal then held; an application effective %s would change a settled period — apply it from %s', d.id, b.accrued_through, NEW.effective_on, b.accrued_through + 1), ERRCODE = 'check_violation';
        END IF;
    WHEN 'interest_accrued' THEN
        -- The record of the core's computation must be coherent: its own
        -- deposit's rule, a rate row of its tenant, state and service that is
        -- in effect by the period's start, at that row's rate, inside the
        -- deposit's life and recorded after the period ends. WHICH rate row,
        -- whether interest is owed and how much are the core's.
        IF d.rule_id IS NULL OR NEW.rule_id IS DISTINCT FROM d.rule_id THEN
            RAISE EXCEPTION USING
                MESSAGE = format('deposit %s: an accrual cites the rule the deposit was decided under (%s), not %s (v5.4.2-15)', d.id, coalesce(d.rule_id::text, 'none — a carried legacy deposit accrues nothing here'), NEW.rule_id),
                ERRCODE = 'check_violation';
        END IF;
        SELECT * INTO v_rate FROM public.deposit_interest_rates r WHERE r.id = NEW.rate_id;
        IF v_rate.tenant_id IS DISTINCT FROM d.tenant_id OR v_rate.state_code IS DISTINCT FROM d.state_code
           OR v_rate.service_type IS DISTINCT FROM d.service_type THEN
            RAISE EXCEPTION USING
                MESSAGE = format('deposit %s: rate row %s is not this utility''s rate for %s %s (v5.4.2-15)', d.id, NEW.rate_id, d.state_code, d.service_type),
                ERRCODE = 'check_violation';
        END IF;
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
        IF NEW.period_start < d.posted_on THEN
            RAISE EXCEPTION USING
                MESSAGE = format('deposit %s: an accrual period cannot start (%s) before the deposit was posted (%s)', d.id, NEW.period_start, d.posted_on),
                ERRCODE = 'check_violation';
        END IF;
        IF NEW.period_end >= NEW.effective_on THEN
            RAISE EXCEPTION USING MESSAGE = format('deposit %s: an accrual is recorded after the period it covers (period_end %s, effective_on %s)', d.id, NEW.period_end, NEW.effective_on), ERRCODE = 'check_violation';
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
        -- The last event closes the ledger: nothing accrued may be left
        -- uncredited, since no event can follow (whether interest is owed,
        -- and through which day, is the core's — see the header).
        IF b.interest_credited <> b.interest_accrued THEN
            RAISE EXCEPTION USING
                MESSAGE = format('deposit %s: %s of accrued interest is uncredited; credit it before the %s event, which is the deposit''s last (v5.4.2-15)', d.id, b.interest_accrued - b.interest_credited, NEW.event_type),
                ERRCODE = 'check_violation';
        END IF;
        -- A carried legacy deposit's interest is settled outside this ledger
        -- (legacy_interest_earned); its return says how (-06 D-42).
        IF d.rule_id IS NULL AND b.interest_accrued = 0 AND (NEW.reason IS NULL OR NEW.reason !~ '[[:alnum:]]') THEN
            RAISE EXCEPTION USING
                MESSAGE = format('deposit %s is a legacy deposit with no accrual history: its return requires a reason stating how its interest was settled (legacy_interest_earned = %s)', d.id, coalesce(d.legacy_interest_earned, 0)),
                ERRCODE = 'check_violation';
        END IF;
    END CASE;
    RETURN NEW;
END;
$$;
COMMENT ON FUNCTION public.enforce_deposit_event() IS
    'v5.4.2-06, re-issued by v5.4.2-15 (deposits at parity). The deposit sub-ledger''s integrity: locks the deposit row (so events, due rows and withdrawals serialise); tenant, actor, dates, ledger link; nothing after refunded / released; the posted event is the database''s; applications within the remainder, not while a refund is pending, not into an accrued period; an accrual cites the deposit''s rule and a rate row of its tenant, state and service in effect by the period''s start, at that rate, within the deposit''s life, recorded after the period; credits within accrued − credited; one pending refund; returns of exactly the remainder, cash refunded and non-cash released, leaving nothing accrued uncredited; a legacy return without accruals states how its interest was settled; a cited return-due row is live and the deposit''s. Decides no law: whether interest is owed, at which rate row, over which periods and in what amount are the core''s.';

COMMENT ON TABLE public.deposit_events IS
    'CI-125 / CI-130 / CI-131 (v5.4.2-06; v5.4.2-15 at parity): the append-only deposit sub-ledger. posted (written by the database at deposit insert), applied_to_balance, interest_accrued (period, rate, principal basis and amount as the core computed them, citing the utility rate row (rate_id), the deposit''s rule row (rule_id) and the core version (calculated_by); periods never overlap), interest_credited (≤ accrued − credited), refund_initiated, refunded (cash) / released (non-cash) — of the remainder, leaving nothing accrued uncredited, optionally citing the return-due row they settle (return_due_id). deposits.status is projected from these. Optional link to the account_ledger row that moved the money.';


-- ----------------------------------------------------------------------------
-- 9. The law functions and the refund-due view leave
-- ----------------------------------------------------------------------------
DROP VIEW IF EXISTS public.deposits_refund_due;
DROP FUNCTION IF EXISTS public.deposit_refund_trigger_state(uuid);
DROP FUNCTION IF EXISTS public.deposit_accrual_amount(numeric, numeric, date, date);
DROP FUNCTION IF EXISTS public.deposit_interest_rate_as_of(uuid, date);


-- ----------------------------------------------------------------------------
-- 10. Residuals, stated
-- ----------------------------------------------------------------------------
-- R1. THE DATABASE NO LONGER DECIDES DEPOSIT LAW. An application that takes a
--     deposit a waiver forbids, sets a cap the rule does not support, accrues
--     the wrong interest or never records a due return is not refused here —
--     by design (Ryan, 2026-09-28). The records show it: every deposit,
--     accrual and due row cites its rule row and core version. The core's
--     rules and their boundary cases: application/deposits-rules-for-the-
--     core.md, which also lists nine places -06 disagreed with its sources
--     (DG1-DG9) and Kyle questions K1-K8.
--
-- R2. ONLY TEXAS GAS IS SEEDED. A premise in another state, or another
--     service, has no rule row; the core must refuse, never fall back. No
--     legal interest rate is seeded (deposit_interest_rate_law): each is
--     entered from its publication.
--
-- R3. DISCONNECTION AS A RETURN TRIGGER (decision table #54 rule 1; DG1)
--     waits for a recorded disconnect reason (3K-collections). It is then a
--     deposit_return_reasons row and an evidence kind.
--
-- R4. A LAW ROW IS NEVER EDITED — for the owner too. A rule or vocabulary
--     row wrong from its first day is repaired by a reviewed platform
--     migration that disables the guard for that statement.
--
-- R5. A CLOSE RACING A NEW CITATION. The close floor reads the citations
--     committed when it runs (as v5.4.2-13's R12). Closing is a reviewed
--     owner migration, run with no deposit decisions in flight.
--
-- R6. EVIDENCE IS REQUIRED, NOT COMPLETE. The database checks that a due row
--     has evidence and that each row is of the right customer, kind and
--     period. Whether the core cited every bill it counted is the core's,
--     like v5.4.2-13's per-period evidence.
--
-- R7. A WAIVER DETERMINATION NAMES ONE STATE AND SERVICE. A customer served
--     in two states holds one determination per state's class.

-- ----------------------------------------------------------------------------
-- 11. The AC-32 tail
-- ----------------------------------------------------------------------------
-- Three new tenant tables and two new views, each born leaky by the default
-- grants. The assertion raises if any lacks RLS, FORCE, the single canonical
-- policy, or invoker rights. The seven law tables carry no tenant_id and are
-- read-only to tally_app.

SELECT public.assert_tenant_isolation_invariants();

-- ============================================================================
-- END PATCH v5.4.2-15
-- ============================================================================
