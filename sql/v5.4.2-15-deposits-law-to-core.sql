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
--       deposit_rules, with its parts deposit_rule_waiver_reach (which
--       waivers relieve it, per trigger, with what effect) and
--       deposit_rule_refund_disqualifiers, and the vocabularies
--       deposit_bases, deposit_triggers, deposit_customer_classes,
--       deposit_waiver_classes, deposit_return_reasons and
--       deposit_refund_disqualifiers. Texas gas is seeded once, from what -06
--       enforced. A second state is rows, not DDL (the battery's group Z).
--     * A deposit RECORDS the jurisdiction, class and rule row it was decided
--       under, the cap that applied and where it came from — the statute or
--       the utility's tariff — with its basis and, under a combined cap,
--       what else was held, and the core version (decided_by).
--     * An accrual RECORDS the rate row and rule row it used and the core
--       version (calculated_by). The rate is the UTILITY's (R-D1): its rate
--       rows say which state, service and (optionally) customer class they
--       are for. The platform keeps each state's published legal rate as a
--       REFERENCE only (deposit_interest_rate_law) and a report compares the
--       two (deposit_interest_rate_discrepancies).
--     * A waiver the utility's own tariff adds is the utility's row
--       (deposit_tariff_waiver_grounds), with its own scope and effect; the
--       law holds only the permission (a tariff_defined waiver class).
--     * When a mandatory return falls due, the core RECORDS it
--       (deposit_return_due), with the bills, the closure or the deposit
--       itself it rests on (deposit_return_due_evidence). A due row found
--       wrong is withdrawn by a separate record (deposit_return_due_
--       withdrawals), never edited. The operators' "refunds owed" list
--       (deposits_return_owed) reads those records; it computes no law
--       (R-D2).
--     * Part of a deposit can go back while the rest is held
--       (principal_returned).
--
--   Dropped: deposit_accrual_amount() (the Texas formula),
--   deposit_interest_rate_as_of() (rate selection), deposit_refund_trigger_
--   state() and the view deposits_refund_due (the refund law), the columns
--   deposits.refund_eligibility_on (a competing informational date) and
--   deposits.cap_basis_annual_billing (replaced by cap_basis_kind /
--   cap_basis_amount), and every CHECK that named a basis, trigger or
--   waiver class (now vocabulary rows and their attributes).
--
-- REVIEW ROUND 1 (frozen 4f9468eb; Opus, Fable, Codex: all "not yet"; record:
--   tests/v5.4.2-15/review/review-findings-15-r1.md). Folded here, with
--   Ryan's decisions of 2026-10-02:
--     B1 a later accrual, return or due row may cite the deposit's own rule
--        or a rule of its key in force over its dates (deposit_rule_citable);
--     B2 the cap records its source (statute or tariff);
--     B3 waiver reach per (rule, waiver class, trigger) with an effect,
--        replacing deposit_rules.waivable; the utility's tariff waivers are
--        its own rows (reviewed by Opus, Fable and Codex before building);
--     A1-A15 as in the findings record (the row-version mutex, the rate-race
--        lock, no basis-name CHECKs, closure evidence, stamps, chronology,
--        class-specific rates, combined caps, partial returns, refund
--        lookback and disqualifiers, time-held evidence, reasons tied to the
--        rule, the clone ACL in the tests).
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
--   New:
--   * Deposits: no rule row, or one of another state, service, class or
--     basis, or not in force on posting; no recorded cap under a rule with a
--     statutory one; a statutory cap not of the rule's kind, or recording
--     what else was held other than under combined scope; a tariff cap
--     without its provision; a cap without its kind or basis; principal
--     above the cap less what else was held; a trigger named other than
--     exactly by a basis that requires one; legacy interest on a new deposit;
--     a caller-supplied created_at (stamped).
--   * Events: a rule that is neither the deposit's nor one of its key in
--     force over the event's dates; an accrual on a legacy deposit, or
--     citing a rate row of another tenant, state, service or class, or one
--     not yet effective, or at another rate; an accrual before posting,
--     recorded before its period ends, starting after the principal was used
--     up, or on more than the principal; a return dated inside an accrued
--     period; a partial return of all or more than the remainder; a refund
--     or release that leaves accrued interest uncredited (see DIVERGENCE); a
--     rate inserted outside READ COMMITTED (the rate-race lock).
--   * Waivers: a certification-backed class without its reference; a
--     tariff-defined class without the utility's ground (of its state and
--     service, in force on the date), or any other class with one; a tariff
--     ground where the state's law permits none, or scoped to an unknown
--     basis, class or trigger, or edited other than closed.
--   * Return-due rows: a rule that is neither the deposit's nor one of its
--     key in force on the due date, or that does not make the return
--     mandatory for the instrument; a deposit whose return has started; a
--     second live row (a row-version mutex on the deposit row, so this holds
--     under REPEATABLE READ too); no evidence; evidence of another customer,
--     from before posting, of the wrong kind, for a reason the rule does not
--     enable, of a state change to a non-qualifying status, or after its own
--     transaction; superseding a live or another deposit's row, or the same
--     row twice; a withdrawal twice; a return citing a withdrawn or another
--     deposit's row.
--   * Law: any application write to the law tables; any edit of a law,
--     part or vocabulary row other than a stamped close not on or before a
--     date it is cited for; a rule part added after its rule's transaction;
--     a reach row of another state or service than its rule (composite key),
--     or naming a trigger for a basis without one; a disqualifier on a rule
--     without a count-based trigger.
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
    requires_trigger boolean NOT NULL,
    description     text NOT NULL,
    created_at      timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT deposit_bases_pkey PRIMARY KEY (basis_code),
    CONSTRAINT deposit_bases_code_check CHECK ((basis_code ~ '^[a-z][a-z0-9_]*$'::text)),
    CONSTRAINT deposit_bases_description_check CHECK ((description ~ '[[:alnum:]]'::text))
);
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.deposit_bases FROM tally_app;
GRANT SELECT ON public.deposit_bases TO tally_app;
COMMENT ON TABLE public.deposit_bases IS
    'v5.4.2-15 (deposits at parity). Why a deposit was taken — the basis decides which rule governs it. is_federal: a federal basis (11 U.S.C. §366 adequate assurance), not a state deposit rule. insertable: false for a basis that exists only for carried history (legacy_unknown, -06''s backfill); no new deposit may take it, and a deposit of such a basis is carried history (its posted event is a backfill, it may carry legacy_interest_earned). requires_trigger: a deposit of this basis names the event that gave rise to it (deposits.trigger_basis), and only such a deposit names one (review r1 A3: was a CHECK naming the basis). What a basis DOES in a state is on its deposit_rules row. Platform-held vocabulary; a new basis is a row plus a core change.';

INSERT INTO public.deposit_bases (basis_code, is_federal, insertable, requires_trigger, description)
SELECT v.code, v.fed, v.ins, v.trg, v.description
  FROM (VALUES
    ('credit_evaluation',      false, true,  false, 'Required on the customer''s credit evaluation (new service).'),
    ('additional_trigger',     false, true,  true,  'An additional deposit after a triggering event (NSF, disconnection history, a broken payment arrangement): see deposit_triggers.'),
    ('tariff',                 false, true,  false, 'Required by the utility''s filed tariff.'),
    ('adequate_assurance_366', true,  true,  false, 'Adequate assurance of payment demanded of a debtor in bankruptcy (11 U.S.C. §366).'),
    ('legacy_unknown',         false, false, false, 'Carried from customers.deposit_* by v5.4.2-06; the basis was never recorded. Not insertable.')
  ) AS v(code, fed, ins, trg, description)
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
    tariff_defined          boolean NOT NULL,
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
    'v5.4.2-15. The grounds on which a state''s law waives a deposit, per state and service. requires_certification: a determination of this class carries the certification''s reference (Texas: family violence, Texas Council on Family Violence). tariff_defined: the class is the law''s PERMISSION for a utility''s tariff to add waivers; the waivers themselves are the utility''s (deposit_tariff_waiver_grounds, R-D1) and a determination of this class cites one (review r1 B3). Which rules a class reaches, for which trigger, with which effect, is deposit_rule_waiver_reach; whether a customer qualifies is deposit_waiver_determinations; whether a deposit is waived is the core''s. Platform-held.';

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
     'Decision table #53 rank 3: a tariff may extend the statutory waivers, never narrow them. The waivers are the utility''s own (deposit_tariff_waiver_grounds).')
  ) AS v(s, svc, code, cert, trf, description, source_note)
 WHERE NOT EXISTS (SELECT 1 FROM public.deposit_waiver_classes w
                    WHERE w.state_code = v.s AND w.service_type = v.svc AND w.class_code = v.code);


CREATE TABLE IF NOT EXISTS public.deposit_return_reasons (
    reason_code         text NOT NULL,
    evidence_kind       text NOT NULL,
    qualifying_statuses text[],
    enabled_by          text NOT NULL,
    description         text NOT NULL,
    created_at          timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT deposit_return_reasons_pkey PRIMARY KEY (reason_code),
    CONSTRAINT deposit_return_reasons_code_check CHECK ((reason_code ~ '^[a-z][a-z0-9_]*$'::text)),
    -- What a due row's evidence for this reason cites: bills, the customer's
    -- state change, or the deposit itself (a return due on time held).
    CONSTRAINT deposit_return_reasons_evidence_kind_check
        CHECK ((evidence_kind = ANY (ARRAY['invoice'::text, 'state_event'::text, 'deposit'::text]))),
    -- The account statuses a cited state change may move to: given exactly
    -- for a state-change reason (review r1 A4).
    CONSTRAINT deposit_return_reasons_statuses_check
        CHECK ((((evidence_kind = 'state_event'::text) AND (qualifying_statuses IS NOT NULL) AND (cardinality(qualifying_statuses) > 0)
                 AND (qualifying_statuses <@ ARRAY['active'::text, 'inactive'::text, 'final_billed'::text, 'collections'::text, 'closed'::text]))
             OR ((evidence_kind <> 'state_event'::text) AND (qualifying_statuses IS NULL)))),
    -- Which attribute of a rule makes this reason a trigger (review r1 A14):
    -- history_trigger = the rule's count-based trigger (refund_after_count);
    -- account_close = refund_on_account_close.
    CONSTRAINT deposit_return_reasons_enabled_by_check
        CHECK ((enabled_by = ANY (ARRAY['history_trigger'::text, 'account_close'::text]))),
    CONSTRAINT deposit_return_reasons_description_check CHECK ((description ~ '[[:alnum:]]'::text))
);
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.deposit_return_reasons FROM tally_app;
GRANT SELECT ON public.deposit_return_reasons TO tally_app;
COMMENT ON TABLE public.deposit_return_reasons IS
    'v5.4.2-15 (R-D2). Why a deposit''s mandatory return fell due, and what kind of record the reason rests on (evidence_kind: invoice — the bills the core judged; state_event — the customer''s state change, to one of qualifying_statuses; deposit — the deposit itself, for a return due on time held). enabled_by names the rule attribute that makes the reason a trigger: a due row may give a reason only if its rule enables it. A state with another trigger adds a row. Disconnection as a trigger (decision table #54 rule 1; rules-for-the-core DG1) waits for a recorded disconnect reason. Platform-held vocabulary.';

-- account_closed qualifies on closed, final_billed or inactive, as -06's view
-- did; whether inactive belongs is Kyle question K8.
INSERT INTO public.deposit_return_reasons (reason_code, evidence_kind, qualifying_statuses, enabled_by, description)
SELECT v.code, v.kind, v.st, v.en, v.description
  FROM (VALUES
    ('clean_bill_history', 'invoice',     NULL::text[], 'history_trigger', 'The customer''s bill history met the rule''s refund measure (Texas: twelve bills, no more than two delinquencies, not currently delinquent).'),
    ('account_closed',     'state_event', ARRAY['closed', 'final_billed', 'inactive'], 'account_close', 'The customer''s account closed, final-billed or went inactive.'),
    ('hold_term_elapsed',  'deposit',     NULL::text[], 'history_trigger', 'The deposit has been held for the rule''s refund measure, which turns on time held rather than on bills.')
  ) AS v(code, kind, st, en, description)
 WHERE NOT EXISTS (SELECT 1 FROM public.deposit_return_reasons r WHERE r.reason_code = v.code);


CREATE TABLE IF NOT EXISTS public.deposit_refund_disqualifiers (
    disqualifier_code   text NOT NULL,
    description         text NOT NULL,
    created_at          timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT deposit_refund_disqualifiers_pkey PRIMARY KEY (disqualifier_code),
    CONSTRAINT deposit_refund_disqualifiers_code_check CHECK ((disqualifier_code ~ '^[a-z][a-z0-9_]*$'::text)),
    CONSTRAINT deposit_refund_disqualifiers_description_check CHECK ((description ~ '[[:alnum:]]'::text))
);
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.deposit_refund_disqualifiers FROM tally_app;
GRANT SELECT ON public.deposit_refund_disqualifiers TO tally_app;
COMMENT ON TABLE public.deposit_refund_disqualifiers IS
    'v5.4.2-15 (review r1 A12). Events in the customer''s history that stop a count-based mandatory return (deposit_rule_refund_disqualifiers lists which apply under a rule). Evaluated by the core. Platform-held vocabulary.';

INSERT INTO public.deposit_refund_disqualifiers (disqualifier_code, description)
SELECT v.code, v.description
  FROM (VALUES
    ('disconnect_nonpayment', 'Service disconnected for nonpayment within the lookback.'),
    ('returned_payment',      'A payment returned unpaid (NSF) within the lookback.')
  ) AS v(code, description)
 WHERE NOT EXISTS (SELECT 1 FROM public.deposit_refund_disqualifiers x WHERE x.disqualifier_code = v.code);


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
    refund_lookback_quantity        integer,
    refund_lookback_unit            text,
    refund_on_account_close         boolean,
    refund_obligation_vests         boolean,
    return_mandatory_instruments    text[],
    effective_from                  date NOT NULL,
    effective_to                    date,
    source_note                     text NOT NULL,
    created_at                      timestamp with time zone DEFAULT now() NOT NULL,
    recorded_txid                   bigint DEFAULT txid_current() NOT NULL,
    closed_at                       timestamp with time zone,
    closed_by                       text,
    CONSTRAINT deposit_rules_pkey PRIMARY KEY (id),
    -- The target of the reach table's composite key: a reach row's state and
    -- service are its rule's, declaratively (review B3, all three reviewers).
    CONSTRAINT deposit_rules_id_state_service_key UNIQUE (id, state_code, service_type),
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
    -- trigger given whole (count, measure, delinquency limit, and a lookback
    -- for that limit or none = the whole hold); when there is none, nothing
    -- about it. What disqualifies the count-based trigger is
    -- deposit_rule_refund_disqualifiers. refund_obligation_vests NULL under a
    -- mandatory return = unruled (K6).
    CONSTRAINT deposit_rules_return_instruments_check
        CHECK (((return_mandatory_instruments IS NULL)
             OR (return_mandatory_instruments <@ ARRAY['cash'::text, 'letter_of_credit'::text, 'certificate_of_deposit'::text, 'surety_bond'::text, 'prepayment'::text, 'guarantor'::text, 'other_agreed'::text]))),
    CONSTRAINT deposit_rules_refund_check
        CHECK ((((NOT refund_mandatory)
                 AND (refund_after_count IS NULL) AND (refund_measure IS NULL) AND (refund_max_delinquencies IS NULL)
                 AND (refund_lookback_quantity IS NULL) AND (refund_lookback_unit IS NULL) AND (refund_on_account_close IS NULL)
                 AND (refund_obligation_vests IS NULL) AND (return_mandatory_instruments IS NULL))
             OR (refund_mandatory
                 AND (refund_on_account_close IS NOT NULL)
                 AND (return_mandatory_instruments IS NOT NULL) AND (cardinality(return_mandatory_instruments) > 0)
                 AND (((refund_after_count IS NULL) AND (refund_measure IS NULL) AND (refund_max_delinquencies IS NULL)
                        AND (refund_lookback_quantity IS NULL) AND (refund_lookback_unit IS NULL))
                   OR ((refund_after_count IS NOT NULL) AND (refund_after_count > 0) AND (refund_measure IS NOT NULL)
                       AND (refund_max_delinquencies IS NOT NULL) AND (refund_max_delinquencies >= 0)
                       AND ((refund_lookback_quantity IS NULL) = (refund_lookback_unit IS NULL))
                       AND ((refund_lookback_quantity IS NULL) OR (refund_lookback_quantity > 0))))))),
    CONSTRAINT deposit_rules_refund_measure_check
        CHECK (((refund_measure IS NULL) OR (refund_measure = ANY (ARRAY['bills'::text, 'months'::text])))),
    CONSTRAINT deposit_rules_refund_lookback_unit_check
        CHECK (((refund_lookback_unit IS NULL) OR (refund_lookback_unit = ANY (ARRAY['bills'::text, 'months'::text])))),
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
    'v5.4.2-15 (deposits at parity). What a state''s deposit law requires, per (state, service type, customer class, basis, effective range), as ATTRIBUTES the calculation core reads: the cap (kind, figure, scope); which instruments earn interest and how (minimum hold, retroactivity, method, day count, credit cadence); whether the deposit must be returned unasked — on what history (count, measure, delinquency limit and its lookback) and on account close, which instruments that covers, and whether it stays owed once due. Which waivers reach it is deposit_rule_waiver_reach; what disqualifies its history trigger is deposit_rule_refund_disqualifiers — both written in the rule''s own transaction (recorded_txid). Platform-held (tally_app reads only), cited (source_note), no overlap per key. Never edited — closed (effective_to set once, stamped closed_at / closed_by, never on or before a date it is cited for) and superseded, because deposits, accruals and return-due rows cite it. A key with no row in force means no rule is known: the core refuses, never falls back. How the core applies each attribute: application/deposits-rules-for-the-core.md.';
COMMENT ON COLUMN public.deposit_rules.cap_kind IS
    'none; fraction_of_annual_billing (cap = estimated annual billing ÷ cap_divisor — Texas residential: 6); months_of_billing (cap_months of estimated billing); fixed_amount (cap_amount_fixed). The statutory cap. The deposit records the cap that applied and whether it was the statute''s or the utility''s tariff''s (deposits.cap_source); computing it is the core''s (the estimate for a new applicant is undefined, decision table #53 OQ5).';
COMMENT ON COLUMN public.deposit_rules.cap_scope IS
    'per_deposit: each deposit within the cap (-06). combined: the total held within it (decision table #55 rule 9; the deposit records what else was held, deposits.cap_other_held). Kyle question K4.';
COMMENT ON COLUMN public.deposit_rules.interest_min_hold_days IS
    'No interest unless the deposit is held MORE than this many days (Texas: 30 — the day-30/31 cliff, CI-130). NULL: from day 1.';
COMMENT ON COLUMN public.deposit_rules.interest_retroactive IS
    'Past the minimum hold, interest runs from the posting date (Texas: true — from day 1, not day 31) rather than from the end of the hold. NULL exactly when there is no minimum hold.';
COMMENT ON COLUMN public.deposit_rules.refund_lookback_quantity IS
    'The window over which refund_max_delinquencies is counted, with refund_lookback_unit (bills or months). NULL = the whole hold, as -06 counted (rules-for-the-core DG4; Kyle question K7).';
COMMENT ON COLUMN public.deposit_rules.refund_obligation_vests IS
    'Once the return falls due, it stays owed even if the customer falls behind before it is made. NULL under a mandatory return = unruled (Kyle question K6).';
COMMENT ON COLUMN public.deposit_rules.return_mandatory_instruments IS
    'The instruments the mandatory return covers: cash is refunded, non-cash released. Texas: {cash}, as -06 (residential non-cash is Kyle question K5).';


-- Which waivers reach a rule (review r1 B3; Ryan, 2026-10-02; reviewed by
-- Opus, Fable and Codex). A row means: a waiver of this class, in force,
-- relieves a deposit governed by this rule — for this additional-deposit
-- trigger (NULL = any), with this effect: excuse it, reduce it by a
-- fraction, or defer it by a number of days. A rule with no rows is reached
-- by no waiver. There is no ranking: the core finds the customer's
-- in-force determinations on the rule's list and applies them (rules-for-
-- the-core §2.1). Law, so platform-held, written with its rule, never
-- edited: a change in reach is a close of the rule and a successor.
CREATE TABLE IF NOT EXISTS public.deposit_rule_waiver_reach (
    id              uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    rule_id         uuid NOT NULL,
    state_code      text NOT NULL,
    service_type    text NOT NULL,
    waiver_class    text NOT NULL,
    trigger_code    text,
    effect          text NOT NULL,
    reduce_fraction numeric(5,4),
    defer_days      integer,
    created_at      timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT deposit_rule_waiver_reach_pkey PRIMARY KEY (id),
    CONSTRAINT deposit_rule_waiver_reach_key UNIQUE NULLS NOT DISTINCT (rule_id, waiver_class, trigger_code),
    CONSTRAINT deposit_rule_waiver_reach_rule_fkey
        FOREIGN KEY (rule_id, state_code, service_type)
        REFERENCES public.deposit_rules(id, state_code, service_type),
    CONSTRAINT deposit_rule_waiver_reach_class_fkey
        FOREIGN KEY (state_code, service_type, waiver_class)
        REFERENCES public.deposit_waiver_classes(state_code, service_type, class_code),
    CONSTRAINT deposit_rule_waiver_reach_trigger_fkey
        FOREIGN KEY (trigger_code) REFERENCES public.deposit_triggers(trigger_code),
    -- An effect with exactly the figure it needs.
    CONSTRAINT deposit_rule_waiver_reach_effect_check
        CHECK ((((effect = 'excuse'::text) AND (reduce_fraction IS NULL) AND (defer_days IS NULL))
             OR ((effect = 'reduce'::text) AND (reduce_fraction IS NOT NULL) AND (reduce_fraction > (0)::numeric) AND (reduce_fraction < (1)::numeric) AND (defer_days IS NULL))
             OR ((effect = 'defer'::text) AND (defer_days IS NOT NULL) AND (defer_days > 0) AND (reduce_fraction IS NULL))))
);
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.deposit_rule_waiver_reach FROM tally_app;
GRANT SELECT ON public.deposit_rule_waiver_reach TO tally_app;
COMMENT ON TABLE public.deposit_rule_waiver_reach IS
    'v5.4.2-15 (review r1 B3). Which waiver classes relieve a deposit under a rule: per (rule, waiver class, trigger — NULL = any), with the effect (excuse; reduce by reduce_fraction; defer by defer_days). Replaces a single waivable flag, which could not say "class X reaches this rule, class Y does not" (decision table #53 rank 0 vs §366, Kyle question K2). State and service are the rule''s, by composite key. A trigger is named only on a rule whose basis requires one. Platform-held, written in its rule''s transaction, never edited. Whether a customer''s waiver relieves a deposit is the core''s.';

CREATE TABLE IF NOT EXISTS public.deposit_rule_refund_disqualifiers (
    rule_id             uuid NOT NULL,
    disqualifier_code   text NOT NULL,
    created_at          timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT deposit_rule_refund_disqualifiers_pkey PRIMARY KEY (rule_id, disqualifier_code),
    CONSTRAINT deposit_rule_refund_disqualifiers_rule_fkey FOREIGN KEY (rule_id) REFERENCES public.deposit_rules(id),
    CONSTRAINT deposit_rule_refund_disqualifiers_code_fkey
        FOREIGN KEY (disqualifier_code) REFERENCES public.deposit_refund_disqualifiers(disqualifier_code)
);
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.deposit_rule_refund_disqualifiers FROM tally_app;
GRANT SELECT ON public.deposit_rule_refund_disqualifiers TO tally_app;
COMMENT ON TABLE public.deposit_rule_refund_disqualifiers IS
    'v5.4.2-15 (review r1 A12). What in the customer''s history stops a rule''s count-based mandatory return (Texas: disconnection for nonpayment; another state might add a returned payment). Only on a rule with a count-based trigger. Platform-held, written in its rule''s transaction, never edited.';

-- A rule row's record: stamped, born unclosed; its transaction recorded, as
-- its reach and disqualifier rows must be written in it.
CREATE OR REPLACE FUNCTION public.enforce_deposit_rule_record() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
BEGIN
    NEW.created_at    := now();
    NEW.recorded_txid := txid_current();
    NEW.closed_at     := NULL;
    NEW.closed_by     := NULL;
    RETURN NEW;
END;
$$;
COMMENT ON FUNCTION public.enforce_deposit_rule_record() IS
    'v5.4.2-15. BEFORE INSERT on deposit_rules, every role: created_at and recorded_txid stamped (the rule''s reach and disqualifier rows may be added only in that transaction); closed_at / closed_by start empty.';
DROP TRIGGER IF EXISTS a_enforce_deposit_rule_record ON public.deposit_rules;
CREATE TRIGGER a_enforce_deposit_rule_record BEFORE INSERT ON public.deposit_rules
    FOR EACH ROW EXECUTE FUNCTION public.enforce_deposit_rule_record();
ALTER TABLE public.deposit_rules ENABLE ALWAYS TRIGGER a_enforce_deposit_rule_record;

-- A rule's reach and disqualifier rows are part of the rule: written in its
-- own transaction (a row added later would change the law every existing
-- citation of the rule was decided under — the -13 window-term rule).
CREATE OR REPLACE FUNCTION public.enforce_deposit_rule_part_record() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_rule record;
    v_requires_trigger boolean;
BEGIN
    SELECT r.recorded_txid, r.basis, r.refund_after_count INTO v_rule FROM public.deposit_rules r WHERE r.id = NEW.rule_id;
    IF v_rule.recorded_txid IS DISTINCT FROM txid_current() THEN
        RAISE EXCEPTION USING
            MESSAGE = format('%s: rule %s was recorded in an earlier transaction; its parts are complete — a part added later would change the law its citations were decided under (v5.4.2-15)', TG_TABLE_NAME, NEW.rule_id),
            ERRCODE = 'restrict_violation',
            HINT = 'Close the rule and add a successor with the new parts, in one transaction.';
    END IF;
    IF TG_TABLE_NAME = 'deposit_rule_waiver_reach' THEN
        IF NEW.trigger_code IS NOT NULL THEN
            SELECT b.requires_trigger INTO v_requires_trigger FROM public.deposit_bases b WHERE b.basis_code = v_rule.basis;
            IF v_requires_trigger IS NOT TRUE THEN
                RAISE EXCEPTION USING
                    MESSAGE = format('deposit_rule_waiver_reach: rule %s is for basis %s, which names no trigger; a reach row for it names none (v5.4.2-15)', NEW.rule_id, v_rule.basis),
                    ERRCODE = 'check_violation';
            END IF;
        END IF;
    ELSIF v_rule.refund_after_count IS NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('deposit_rule_refund_disqualifiers: rule %s has no count-based return trigger to disqualify (v5.4.2-15)', NEW.rule_id),
            ERRCODE = 'check_violation';
    END IF;
    NEW.created_at := now();
    RETURN NEW;
END;
$$;
COMMENT ON FUNCTION public.enforce_deposit_rule_part_record() IS
    'v5.4.2-15. BEFORE INSERT on deposit_rule_waiver_reach and deposit_rule_refund_disqualifiers, every role: only in the transaction that recorded the rule (deposit_rules.recorded_txid); a reach row names a trigger only for a basis that requires one (deposit_bases.requires_trigger); a disqualifier only on a rule with a count-based trigger; created_at stamped.';
DO $$
DECLARE t text;
BEGIN
    FOREACH t IN ARRAY ARRAY['deposit_rule_waiver_reach', 'deposit_rule_refund_disqualifiers'] LOOP
        EXECUTE format('DROP TRIGGER IF EXISTS a_enforce_deposit_rule_part_record ON public.%I', t);
        EXECUTE format('CREATE TRIGGER a_enforce_deposit_rule_part_record BEFORE INSERT ON public.%I FOR EACH ROW EXECUTE FUNCTION public.enforce_deposit_rule_part_record()', t);
        EXECUTE format('ALTER TABLE public.%I ENABLE ALWAYS TRIGGER a_enforce_deposit_rule_part_record', t);
    END LOOP;
END;
$$;

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

-- The six vocabularies and a rule's parts never change and are never deleted.
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
    'v5.4.2-15. BEFORE UPDATE OR DELETE, every role, on deposit_bases, deposit_triggers, deposit_customer_classes, deposit_waiver_classes, deposit_return_reasons, deposit_refund_disqualifiers, deposit_rule_waiver_reach and deposit_rule_refund_disqualifiers: refused.';
DO $$
DECLARE t text;
BEGIN
    FOREACH t IN ARRAY ARRAY['deposit_bases', 'deposit_triggers', 'deposit_customer_classes', 'deposit_waiver_classes', 'deposit_return_reasons',
                             'deposit_refund_disqualifiers', 'deposit_rule_waiver_reach', 'deposit_rule_refund_disqualifiers'] LOOP
        EXECUTE format('DROP TRIGGER IF EXISTS a_enforce_deposit_law_immutable ON public.%I', t);
        EXECUTE format('CREATE TRIGGER a_enforce_deposit_law_immutable BEFORE UPDATE OR DELETE ON public.%I FOR EACH ROW EXECUTE FUNCTION public.enforce_deposit_law_immutable()', t);
        EXECUTE format('ALTER TABLE public.%I ENABLE ALWAYS TRIGGER a_enforce_deposit_law_immutable', t);
    END LOOP;
END;
$$;

-- The Texas gas rows, seeded ONCE from what v5.4.2-06 enforced, effective
-- 2004-07-12 (the §7.45 text Kyle read; v5.4.2-13 uses the same date).
--   §7.45 bases (credit_evaluation, additional_trigger, tariff): every TX
--     waiver class excuses them, for any trigger (-06: any waiver blocked any
--     §7.45 basis; #55 rule 8); residential capped at 1/6 of estimated
--     annual billing, per deposit (-06; #55 rule 9 says combined — K4); cash
--     earns interest after a 30-day minimum hold, retroactively to posting,
--     simple, actual/365, credited at refund; the return is mandatory on
--     twelve bills with no more than two delinquencies counted over the
--     whole hold (-06; K7), disqualified by disconnection for nonpayment,
--     and on account close, for cash (K5); whether it stays owed is unruled
--     (K6).
--   §366: no waiver reaches it (-06 D-40; decision table #53 rank 0 says
--     family violence outranks a §366 demand, and whether the other classes
--     do is not stated — Kyle question K2: his answer is reach rows on these
--     two rules, by a close and a successor); no cap; cash interest as above
--     (-06 accrued on every cash deposit); never a mandatory return (#54
--     rule 3).
--   legacy_unknown: deliberately no row — the core refuses to decide one.
-- One DO block: each rule's parts are written in its own transaction.
DO $$
DECLARE
    r record;
    v_rule uuid;
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
                (state_code, service_type, customer_class, basis, cap_kind,
                 interest_bearing_instruments, interest_min_hold_days, interest_retroactive,
                 interest_method, interest_day_count, interest_credit_cadence,
                 refund_mandatory, effective_from, source_note)
            VALUES ('TX', 'gas', r.customer_class, r.basis, 'none',
                    ARRAY['cash'], 30, true, 'simple', 'actual_365', 'at_refund',
                    false, c_from,
                    '11 U.S.C. 366 adequate assurance: a federal permission, not a 16 TAC 7.45 deposit — no 7.45 cap, never refunded on 7.45''s triggers (decision table #54 rule 3); no waiver reaches it per -06 D-40 (decision table #53 rank 0 puts the family-violence waiver above a 366 demand: Kyle question K2). Interest as on any cash deposit the utility holds (16 TAC 7.45; -06 accrued on every cash deposit).');
        ELSE
            INSERT INTO public.deposit_rules
                (state_code, service_type, customer_class, basis, cap_kind, cap_divisor, cap_scope,
                 interest_bearing_instruments, interest_min_hold_days, interest_retroactive,
                 interest_method, interest_day_count, interest_credit_cadence,
                 refund_mandatory, refund_after_count, refund_measure, refund_max_delinquencies,
                 refund_on_account_close, refund_obligation_vests,
                 return_mandatory_instruments, effective_from, source_note)
            VALUES ('TX', 'gas', r.customer_class, r.basis,
                    CASE WHEN r.customer_class = 'residential' THEN 'fraction_of_annual_billing' ELSE 'none' END,
                    CASE WHEN r.customer_class = 'residential' THEN 6 END,
                    CASE WHEN r.customer_class = 'residential' THEN 'per_deposit' END,
                    ARRAY['cash'], 30, true, 'simple', 'actual_365', 'at_refund',
                    true, 12, 'bills', 2, true, NULL,
                    ARRAY['cash'], c_from,
                    '16 TAC 7.45 (CI-129 to CI-131): mandatory waivers (family violence 7.45(5)(C), age 65 with no balance, good payment history; a tariff may extend them) excuse this deposit (decision table #53 ranks 0-3, #55 rule 8); '
                    || CASE WHEN r.customer_class = 'residential' THEN 'the deposit may not exceed one-sixth of estimated annual billing (#53 rank 8; per deposit as -06 — #55 rule 9 says combined, Kyle question K4); ' ELSE 'no statutory cap for this class (-06; Kyle question K1); ' END
                    || 'interest on cash: none if held 30 days or less, otherwise from the posting date (day 1, not day 31) at the rate in force, simple, actual/365, paid at refund (CI-130; #54 rules 5-7); refunded unasked after twelve bills paid with no more than two delinquencies (counted over the whole hold as -06: Kyle question K7), no disconnection for nonpayment and none currently delinquent, or on account close (CI-131; #54 rules 1-2); whether the refund stays owed if the customer falls behind before it is made is Kyle question K6.')
            RETURNING id INTO v_rule;
            INSERT INTO public.deposit_rule_waiver_reach (rule_id, state_code, service_type, waiver_class, effect)
            SELECT v_rule, 'TX', 'gas', w.class_code, 'excuse'
              FROM public.deposit_waiver_classes w
             WHERE w.state_code = 'TX' AND w.service_type = 'gas';
            INSERT INTO public.deposit_rule_refund_disqualifiers (rule_id, disqualifier_code)
            VALUES (v_rule, 'disconnect_nonpayment');
        END IF;
    END LOOP;
END;
$$;


-- ----------------------------------------------------------------------------
-- 4. Interest rates (R-D1): the utility's rate applied, the law's a reference
-- ----------------------------------------------------------------------------
-- The utility answers to the commission for the interest it pays, so the rate
-- it applies is its own row, and every accrual cites that row (section 8). A
-- utility in two states keeps a rate per state and service, and a rate may
-- be for one customer class (NULL = every class; review r1 A9). The platform
-- keeps the published legal rate per state as a reference that nothing
-- reads to decide an accrual; a report lists where the two differ.

ALTER TABLE public.deposit_interest_rates
    ADD COLUMN IF NOT EXISTS state_code     text,
    ADD COLUMN IF NOT EXISTS service_type   text,
    ADD COLUMN IF NOT EXISTS customer_class text;
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
    UNIQUE NULLS NOT DISTINCT (tenant_id, state_code, service_type, customer_class, effective_date);
ALTER TABLE public.deposit_interest_rates DROP CONSTRAINT IF EXISTS deposit_interest_rates_class_fkey;
ALTER TABLE public.deposit_interest_rates ADD CONSTRAINT deposit_interest_rates_class_fkey
    FOREIGN KEY (state_code, service_type, customer_class)
    REFERENCES public.deposit_customer_classes(state_code, service_type, class_code);
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

-- The backdating guard: a rate can't be moved under an accrual that has
-- settled through its date at a rate row covering the same tenant, state,
-- service and class (a NULL class covers every class).
--
-- It races the accrual job (review r1 A2, Fable): the count reads committed
-- accruals only. Both sides take a transaction-scoped advisory lock on
-- (tenant, state, service) — the rate insert exclusive, each accrual shared
-- (section 8) — and the rate insert runs only under READ COMMITTED, so its
-- count, taken after the lock, sees every accrual that held the lock before
-- it. Advisory, because tally_app holds no UPDATE on the append-only rate
-- rows and so cannot row-lock them. Lock order: an accrual takes the
-- deposit row, then this lock; a rate insert takes only this lock.
CREATE OR REPLACE FUNCTION public.deposit_rate_lock_key(p_tenant_id uuid, p_state_code text, p_service_type text) RETURNS bigint
    LANGUAGE sql IMMUTABLE
    SET search_path = public, pg_temp
    AS $$
    SELECT hashtextextended('deposit_interest_rates/' || p_tenant_id::text || '/' || p_state_code || '/' || p_service_type, 0)
$$;
COMMENT ON FUNCTION public.deposit_rate_lock_key(uuid, text, text) IS
    'v5.4.2-15 (review r1 A2). The advisory-lock key a rate insert (exclusive) and an accrual (shared) take for a tenant''s rates in one state and service.';

CREATE OR REPLACE FUNCTION public.enforce_deposit_interest_rate() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE v_settled date;
BEGIN
    IF current_setting('transaction_isolation') <> 'read committed' THEN
        RAISE EXCEPTION USING
            MESSAGE = format('deposit interest rate rejected: a rate is recorded only under READ COMMITTED — under %s the settled-accrual check could miss an accrual committed while it waited (v5.4.2-15)', current_setting('transaction_isolation')),
            ERRCODE = 'serialization_failure';
    END IF;
    PERFORM pg_advisory_xact_lock(public.deposit_rate_lock_key(NEW.tenant_id, NEW.state_code, NEW.service_type));
    PERFORM public.assert_same_tenant_user(NEW.created_by, NEW.tenant_id, 'created_by');
    NEW.created_at := now();
    SELECT max(e.period_end) INTO v_settled
      FROM public.deposit_events e
      JOIN public.deposit_interest_rates r ON r.id = e.rate_id
     WHERE e.event_type = 'interest_accrued' AND r.tenant_id = NEW.tenant_id
       AND r.state_code = NEW.state_code AND r.service_type = NEW.service_type
       AND (r.customer_class IS NULL OR NEW.customer_class IS NULL OR r.customer_class = NEW.customer_class);
    IF v_settled IS NOT NULL AND NEW.effective_date <= v_settled THEN
        RAISE EXCEPTION USING
            MESSAGE = format('deposit interest rate %s %s%s effective %s rejected: interest has already been accrued through %s at the rates it cites; a settled accrual is never re-rated (CI-125 / CI-130) — a correction is a new accrual period at the new rate from %s', NEW.state_code, NEW.service_type, coalesce(' ' || NEW.customer_class, ''), NEW.effective_date, v_settled, v_settled + 1),
            ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$;
COMMENT ON FUNCTION public.enforce_deposit_interest_rate() IS
    'v5.4.2-06, re-issued by v5.4.2-15. BEFORE INSERT on deposit_interest_rates: READ COMMITTED only; takes the exclusive advisory lock for (tenant, state, service) that accruals take shared; created_by of the tenant; created_at stamped; refused on or before the latest period end of any accrual citing a rate row of the same tenant, state and service whose class overlaps (NULL = every class).';

COMMENT ON TABLE public.deposit_interest_rates IS
    'CI-125 / CI-130 (v5.4.2-06; v5.4.2-15, R-D1). The deposit interest rate THIS UTILITY applies, per state and service type and optionally per customer class (NULL = every class), effective-dated (annual, as a fraction — 0.0287 = 2.87%). The utility is the regulated party and answers for it; every accrual cites the row it used (deposit_events.rate_id). Which row applies to a period is the core''s. The state''s published legal rate is a separate reference (deposit_interest_rate_law); deposit_interest_rate_discrepancies compares them. A new rate is a new row; rows are never edited or deleted; one backdated under a settled accrual is refused.';

CREATE TABLE IF NOT EXISTS public.deposit_interest_rate_law (
    id              uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    state_code      text NOT NULL,
    service_type    text NOT NULL,
    customer_class  text,
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
    CONSTRAINT deposit_interest_rate_law_class_fkey
        FOREIGN KEY (state_code, service_type, customer_class)
        REFERENCES public.deposit_customer_classes(state_code, service_type, class_code),
    CONSTRAINT deposit_interest_rate_law_no_overlap
        EXCLUDE USING gist (state_code WITH =, service_type WITH =, (coalesce(customer_class, ''::text)) WITH =,
                            daterange(effective_from, effective_to, '[)'::text) WITH &&)
);
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.deposit_interest_rate_law FROM tally_app;
GRANT SELECT ON public.deposit_interest_rate_law TO tally_app;
COMMENT ON TABLE public.deposit_interest_rate_law IS
    'v5.4.2-15 (R-D1). Each state''s published legal deposit interest rate, per service type and optionally per customer class (NULL = every class), dated and cited (Texas: one statewide rate a year, set by the PUCT, Utilities Code §183.003). A REFERENCE only: nothing reads it to decide an accrual — the rate applied is the utility''s (deposit_interest_rates). deposit_interest_rate_discrepancies compares the two. Platform-held; no overlap per state and service; never edited — closed once (stamped) and superseded. No rows are seeded: each is entered from its publication.';

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
-- the customer class and the rule row the core decided it under, the cap that
-- applied — the statute's or the utility's tariff's (cap_source, Ryan
-- 2026-10-02, review r1 B2) — its basis whatever the kind, what else was held
-- under a combined cap, and the core version. -06's legacy_unknown rows carry
-- none of them: they cite no rule.

ALTER TABLE public.deposits
    ADD COLUMN IF NOT EXISTS state_code       text,
    ADD COLUMN IF NOT EXISTS service_type     text,
    ADD COLUMN IF NOT EXISTS customer_class   text,
    ADD COLUMN IF NOT EXISTS rule_id          uuid,
    ADD COLUMN IF NOT EXISTS cap_basis_kind   text,
    ADD COLUMN IF NOT EXISTS cap_basis_amount numeric(12,2),
    ADD COLUMN IF NOT EXISTS cap_source       text,
    ADD COLUMN IF NOT EXISTS cap_tariff_reference text,
    ADD COLUMN IF NOT EXISTS cap_other_held   numeric(12,2),
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
-- A cap says where it came from: the statute (the cited rule's cap) or the
-- utility's tariff, which names its provision (review r1 B2).
ALTER TABLE public.deposits DROP CONSTRAINT IF EXISTS deposits_cap_source_check;
ALTER TABLE public.deposits ADD CONSTRAINT deposits_cap_source_check
    CHECK ((((cap_amount IS NULL) AND (cap_source IS NULL) AND (cap_tariff_reference IS NULL) AND (cap_other_held IS NULL))
         OR ((cap_amount IS NOT NULL) AND (cap_source IS NOT NULL) AND (cap_source = 'statute'::text) AND (cap_tariff_reference IS NULL))
         OR ((cap_amount IS NOT NULL) AND (cap_source IS NOT NULL) AND (cap_source = 'tariff'::text)
             AND (cap_tariff_reference IS NOT NULL) AND (cap_tariff_reference ~ '[[:alnum:]]'::text))));
-- Under a combined cap, what else the customer already held counts against
-- it (review r1 A10): the deposit stays within, and binds at, the room left.
ALTER TABLE public.deposits DROP CONSTRAINT IF EXISTS deposits_cap_other_held_check;
ALTER TABLE public.deposits ADD CONSTRAINT deposits_cap_other_held_check
    CHECK (((cap_other_held IS NULL) OR ((cap_other_held >= (0)::numeric) AND (cap_other_held < cap_amount))));
ALTER TABLE public.deposits DROP CONSTRAINT IF EXISTS deposits_cap_check;
ALTER TABLE public.deposits ADD CONSTRAINT deposits_cap_check
    CHECK (((cap_amount IS NULL) OR ((cap_amount > (0)::numeric) AND (principal <= (cap_amount - coalesce(cap_other_held, (0)::numeric))))));
ALTER TABLE public.deposits DROP CONSTRAINT IF EXISTS deposits_cap_binding_check;
ALTER TABLE public.deposits ADD CONSTRAINT deposits_cap_binding_check
    CHECK (((NOT cap_binding) OR ((cap_amount IS NOT NULL) AND (principal = (cap_amount - coalesce(cap_other_held, (0)::numeric))))));
-- -06's CHECKs that named a basis go (review r1 A3): whether a basis names a
-- trigger, and which bases are carried history, are vocabulary attributes,
-- read by the guard below.
ALTER TABLE public.deposits DROP CONSTRAINT IF EXISTS deposits_trigger_basis_required_check;
ALTER TABLE public.deposits DROP CONSTRAINT IF EXISTS deposits_legacy_interest_check;

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
    v_basis public.deposit_bases%ROWTYPE;
    v_rule public.deposit_rules%ROWTYPE;
BEGIN
    IF TG_OP = 'INSERT' THEN
        NEW.created_at := now();
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
        -- legacy_interest_earned is carried history; a new deposit has none.
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
        -- The cap that applied (review r1 B2): a rule with a statutory cap
        -- requires one to be recorded — the statute's, or a tighter one from
        -- the utility's tariff; under a rule with none, only a tariff cap.
        -- A statutory cap is of the rule's kind, and under combined scope
        -- records what else was held. Any cap records its kind, and the
        -- basis figure unless it is a fixed amount.
        IF v_rule.cap_kind <> 'none' AND NEW.cap_amount IS NULL THEN
            RAISE EXCEPTION USING
                MESSAGE = format('deposit rejected: rule %s caps the deposit (%s); record the cap that applied — the statute''s or the utility''s tariff''s (cap_source) — v5.4.2-15', NEW.rule_id, v_rule.cap_kind),
                ERRCODE = 'check_violation';
        END IF;
        IF NEW.cap_source = 'statute' AND (v_rule.cap_kind = 'none' OR NEW.cap_basis_kind IS DISTINCT FROM v_rule.cap_kind
                                           OR ((NEW.cap_other_held IS NOT NULL) <> (v_rule.cap_scope = 'combined'))) THEN
            RAISE EXCEPTION USING
                MESSAGE = format('deposit rejected: a statutory cap is the cited rule''s — rule %s sets %s%s; record cap_basis_kind = the rule''s kind, and cap_other_held exactly under a combined cap (v5.4.2-15)', NEW.rule_id, v_rule.cap_kind, coalesce(' (' || v_rule.cap_scope || ')', '')),
                ERRCODE = 'check_violation';
        END IF;
        IF NEW.cap_amount IS NOT NULL
           AND (NEW.cap_basis_kind IS NULL OR ((NEW.cap_basis_amount IS NULL) <> (NEW.cap_basis_kind = 'fixed_amount'))) THEN
            RAISE EXCEPTION USING
                MESSAGE = 'deposit rejected: a cap records its kind (cap_basis_kind) and the figure it was computed from (cap_basis_amount; none for a fixed amount) — v5.4.2-15',
                ERRCODE = 'check_violation';
        END IF;
        IF NEW.cap_amount IS NULL AND (NEW.cap_basis_kind IS NOT NULL OR NEW.cap_basis_amount IS NOT NULL) THEN
            RAISE EXCEPTION USING MESSAGE = 'deposit rejected: no cap is recorded, so no cap basis either (v5.4.2-15)', ERRCODE = 'check_violation';
        END IF;
        RETURN NEW;
    END IF;

    -- UPDATE: identity frozen; projection columns only from inside the events trigger.
    IF OLD.id <> NEW.id OR OLD.tenant_id <> NEW.tenant_id OR OLD.customer_id <> NEW.customer_id OR OLD.basis <> NEW.basis
       OR OLD.trigger_basis IS DISTINCT FROM NEW.trigger_basis OR OLD.instrument <> NEW.instrument OR OLD.principal <> NEW.principal
       OR OLD.posted_on <> NEW.posted_on OR OLD.source_payment_id IS DISTINCT FROM NEW.source_payment_id
       OR OLD.cap_amount IS DISTINCT FROM NEW.cap_amount OR OLD.cap_basis_kind IS DISTINCT FROM NEW.cap_basis_kind
       OR OLD.cap_basis_amount IS DISTINCT FROM NEW.cap_basis_amount
       OR OLD.cap_source IS DISTINCT FROM NEW.cap_source OR OLD.cap_tariff_reference IS DISTINCT FROM NEW.cap_tariff_reference
       OR OLD.cap_other_held IS DISTINCT FROM NEW.cap_other_held
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
    'v5.4.2-06, re-issued by v5.4.2-15 (deposits at parity). BEFORE INSERT OR UPDATE on deposits. INSERT: created_at stamped; the customer is visible; the basis is insertable, and names a trigger exactly when it requires one (deposit_bases); no legacy interest; born held; created_by of the tenant; a source payment of the same customer flagged is_deposit; the deposit cites the deposit_rules row it was decided under — one for its state, service, class and basis, in force on its posting date; a rule with a statutory cap requires a recorded cap; a statutory cap is of the rule''s kind and records what else was held exactly under combined scope; a tariff cap names its provision; any cap records its kind and basis. UPDATE: identity frozen; status columns only from the events. Decides nothing the law decides: waivers, the cap''s size and who may be charged are the core''s.';

-- The database writes the posted event (-06); a deposit of a basis that is
-- carried history is a backfill — read from the vocabulary, not a basis name
-- (review r1 A3).
CREATE OR REPLACE FUNCTION public.post_deposit_event() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
BEGIN
    INSERT INTO public.deposit_events (tenant_id, deposit_id, event_type, amount, effective_on, created_by, source)
    VALUES (NEW.tenant_id, NEW.id, 'posted', NEW.principal, NEW.posted_on, NEW.created_by,
            CASE WHEN (SELECT b.insertable FROM public.deposit_bases b WHERE b.basis_code = NEW.basis) THEN 'system' ELSE 'backfill' END);
    RETURN NULL;
END;
$$;
COMMENT ON FUNCTION public.post_deposit_event() IS
    'v5.4.2-06, re-issued by v5.4.2-15. AFTER INSERT on deposits: writes the posted event — source system, or backfill for a basis the vocabulary marks carried history (deposit_bases.insertable = false).';

ALTER TABLE public.deposits DROP COLUMN IF EXISTS refund_eligibility_on;
ALTER TABLE public.deposits DROP COLUMN IF EXISTS cap_basis_annual_billing;

COMMENT ON TABLE public.deposits IS
    'A-21 (v5.4.2-06; v5.4.2-15 at parity): one record per deposit. basis (a deposit_bases row: why it was taken), trigger_basis for an additional deposit, instrument (cash, or a §366(c)(1)(A) form or guarantor; non-cash carries issuer/reference/expiry), principal, posted_on, and what it was decided under: state_code / service_type (from the premise), customer_class, the deposit_rules row (rule_id) and the core version (decided_by). The cap that applied (cap_amount, cap_basis_kind, cap_basis_amount, cap_binding), where it came from (cap_source: statute, or the utility''s tariff with cap_tariff_reference) and, under a combined cap, what else was held (cap_other_held); required when the rule has a statutory cap. Identity is frozen after insert. status / refunded_on / released_on are a PROJECTION of deposit_events: held → partial_applied / applied → refund_pending → refunded; non-cash → released. A legacy_unknown row (carried by -06) cites no rule; the core refuses to decide one. Whether a deposit may be required, how large, and what it earns are the core''s (application/deposits-rules-for-the-core.md).';
COMMENT ON COLUMN public.deposits.cap_amount IS
    'The cap that applied at the deposit decision — the statute''s (the cited rule''s) or a tighter or additional one from the utility''s tariff (cap_source); required when the rule has a statutory cap. principal ≤ cap_amount − cap_other_held (CHECK); cap_binding when it reduced the amount — the customer is entitled to know (decision table #53). The computation is the core''s.';
COMMENT ON COLUMN public.deposits.cap_basis_kind IS
    'The kind of the cap that applied (for a statutory cap, = deposit_rules.cap_kind), recorded with the deposit so the basis reads the same whatever the state or tariff.';
COMMENT ON COLUMN public.deposits.cap_source IS
    'Where the cap came from: statute (the cited deposit_rules row) or tariff (the utility''s own filed tariff, named in cap_tariff_reference — R-D1: a value the utility answers for stays its own). Ryan, 2026-10-02 (review r1 B2).';
COMMENT ON COLUMN public.deposits.cap_other_held IS
    'Under a combined cap (deposit_rules.cap_scope = combined, decision table #55 rule 9), the deposits the customer already held, which count against the cap: principal ≤ cap_amount − cap_other_held, and cap_binding means principal = cap_amount − cap_other_held.';
COMMENT ON COLUMN public.deposits.cap_basis_amount IS
    'The figure the cap was computed from: estimated annual billing (fraction_of_annual_billing), estimated monthly billing (months_of_billing); NULL for a fixed amount.';
COMMENT ON COLUMN public.deposits.state_code IS
    'The state whose law the deposit was decided under — the premise''s, never the utility''s home state. NULL only on a carried legacy row.';
COMMENT ON COLUMN public.deposits.rule_id IS
    'The deposit_rules row the core decided this deposit under: for its state, service, class and basis, in force on posted_on. Rule rows never change, so the citation stays true.';
COMMENT ON COLUMN public.deposits.decided_by IS
    'The calculation core''s version that decided the deposit.';


-- The rate report (section 4's, here because it reads deposits.state_code).
-- A utility rate row is in force from its date to the next row of the same
-- tenant, state, service and class. Rows cover each other when their classes
-- overlap (a NULL class covers every class). rate_differs: a utility row
-- overlaps a published rate it does not equal. no_utility_rate: a published
-- rate covers days before the first utility row covering its class, for a
-- tenant that keeps rates or holds deposits in that state and service.
-- Whether a difference is lawful (a tariff paying more) is the utility's and
-- the core's call.
CREATE OR REPLACE VIEW public.deposit_interest_rate_discrepancies WITH (security_invoker = true) AS
    WITH u AS (
        SELECT r.id, r.tenant_id, r.state_code, r.service_type, r.customer_class, r.effective_date, r.annual_rate,
               lead(r.effective_date) OVER (PARTITION BY r.tenant_id, r.state_code, r.service_type, r.customer_class ORDER BY r.effective_date) AS next_date
          FROM public.deposit_interest_rates r
    ),
    scope AS (
        SELECT DISTINCT r.tenant_id, r.state_code, r.service_type FROM public.deposit_interest_rates r
        UNION
        SELECT DISTINCT d.tenant_id, d.state_code, d.service_type FROM public.deposits d WHERE d.state_code IS NOT NULL
    ),
    first_rate AS (
        SELECT s.tenant_id, l.id AS law_rate_id,
               (SELECT min(r.effective_date) FROM public.deposit_interest_rates r
                 WHERE r.tenant_id = s.tenant_id AND r.state_code = l.state_code AND r.service_type = l.service_type
                   AND (r.customer_class IS NULL OR l.customer_class IS NULL OR r.customer_class = l.customer_class)) AS first_date
          FROM scope s
          JOIN public.deposit_interest_rate_law l ON l.state_code = s.state_code AND l.service_type = s.service_type
    )
    SELECT 'rate_differs'::text AS discrepancy, u.tenant_id, u.state_code, u.service_type,
           coalesce(u.customer_class, l.customer_class) AS customer_class,
           u.id AS rate_id, l.id AS law_rate_id,
           greatest(u.effective_date, l.effective_from) AS from_date,
           CASE WHEN u.next_date IS NULL THEN l.effective_to
                WHEN l.effective_to IS NULL THEN u.next_date
                ELSE least(u.next_date, l.effective_to) END AS to_date_exclusive,
           u.annual_rate AS utility_rate, l.annual_rate AS law_rate
      FROM u
      JOIN public.deposit_interest_rate_law l
        ON l.state_code = u.state_code AND l.service_type = u.service_type
       AND (u.customer_class IS NULL OR l.customer_class IS NULL OR u.customer_class = l.customer_class)
       AND daterange(u.effective_date, u.next_date, '[)') && daterange(l.effective_from, l.effective_to, '[)')
       AND u.annual_rate <> l.annual_rate
    UNION ALL
    SELECT 'no_utility_rate'::text, f.tenant_id, l.state_code, l.service_type, l.customer_class,
           NULL::uuid, l.id,
           l.effective_from,
           CASE WHEN f.first_date IS NULL THEN l.effective_to
                WHEN l.effective_to IS NULL THEN f.first_date
                ELSE least(f.first_date, l.effective_to) END,
           NULL::numeric, l.annual_rate
      FROM first_rate f
      JOIN public.deposit_interest_rate_law l ON l.id = f.law_rate_id
     WHERE f.first_date IS NULL OR l.effective_from < f.first_date;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.deposit_interest_rate_discrepancies FROM tally_app;
GRANT SELECT ON public.deposit_interest_rate_discrepancies TO tally_app;
COMMENT ON VIEW public.deposit_interest_rate_discrepancies IS
    'v5.4.2-15 (R-D1). Where the rate a utility applies differs from its state''s published legal rate for an overlapping customer class (rate_differs: the overlapping span, both rates), and where a published rate covers days before the utility''s first rate row covering its class, for a state and service it keeps rates or deposits in (no_utility_rate). A read over two records, not a refusal: whether a difference is lawful is the utility''s and the core''s call. Invoker rights: a tenant sees its own rows.';


-- ----------------------------------------------------------------------------
-- 6. Waiver determinations, and the utility's own tariff waivers
-- ----------------------------------------------------------------------------
-- The law's waiver classes are platform rows (section 2). A class marked
-- tariff_defined is the law's PERMISSION for a utility's tariff to add
-- waivers; the waivers themselves are the utility's (R-D1: a value the
-- utility answers for stays its own) — deposit_tariff_waiver_grounds, dated
-- and cited to its tariff, with their own scope and effect. A determination
-- of a tariff_defined class names the ground it rests on (review r1 B3:
-- Opus, Fable and Codex). Whether a ground relieves a deposit is the core's:
-- only where the law's tariff class reaches the rule (deposit_rule_waiver_
-- reach), and only within the ground's own scope.

CREATE TABLE IF NOT EXISTS public.deposit_tariff_waiver_grounds (
    id                          uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id                   uuid NOT NULL,
    state_code                  text NOT NULL,
    service_type                text NOT NULL,
    ground_code                 text NOT NULL,
    description                 text NOT NULL,
    tariff_reference            text NOT NULL,
    reaches_bases               text[],
    reaches_customer_classes    text[],
    reaches_triggers            text[],
    effect                      text NOT NULL,
    reduce_fraction             numeric(5,4),
    defer_days                  integer,
    effective_from              date NOT NULL,
    effective_to                date,
    created_at                  timestamp with time zone DEFAULT now() NOT NULL,
    created_by                  uuid,
    closed_at                   timestamp with time zone,
    closed_by                   uuid,
    CONSTRAINT deposit_tariff_waiver_grounds_pkey PRIMARY KEY (id),
    CONSTRAINT deposit_tariff_waiver_grounds_id_tenant_id_key UNIQUE (id, tenant_id),
    CONSTRAINT deposit_tariff_waiver_grounds_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id),
    CONSTRAINT deposit_tariff_waiver_grounds_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id),
    CONSTRAINT deposit_tariff_waiver_grounds_closed_by_fkey FOREIGN KEY (closed_by) REFERENCES public.users(id),
    CONSTRAINT deposit_tariff_waiver_grounds_state_code_check CHECK ((state_code ~ '^[A-Z]{2}$'::text)),
    CONSTRAINT deposit_tariff_waiver_grounds_service_type_check
        CHECK ((service_type = ANY (ARRAY['water'::text, 'sewer'::text, 'electric'::text, 'gas'::text, 'stormwater'::text, 'trash'::text, 'reclaimed_water'::text]))),
    CONSTRAINT deposit_tariff_waiver_grounds_code_check CHECK ((ground_code ~ '^[a-z][a-z0-9_]*$'::text)),
    CONSTRAINT deposit_tariff_waiver_grounds_text_check
        CHECK (((description ~ '[[:alnum:]]'::text) AND (tariff_reference ~ '[[:alnum:]]'::text))),
    -- A scope list, when given, is non-empty (NULL = no limit).
    CONSTRAINT deposit_tariff_waiver_grounds_scope_check
        CHECK ((((reaches_bases IS NULL) OR (cardinality(reaches_bases) > 0))
            AND ((reaches_customer_classes IS NULL) OR (cardinality(reaches_customer_classes) > 0))
            AND ((reaches_triggers IS NULL) OR (cardinality(reaches_triggers) > 0)))),
    CONSTRAINT deposit_tariff_waiver_grounds_effect_check
        CHECK ((((effect = 'excuse'::text) AND (reduce_fraction IS NULL) AND (defer_days IS NULL))
             OR ((effect = 'reduce'::text) AND (reduce_fraction IS NOT NULL) AND (reduce_fraction > (0)::numeric) AND (reduce_fraction < (1)::numeric) AND (defer_days IS NULL))
             OR ((effect = 'defer'::text) AND (defer_days IS NOT NULL) AND (defer_days > 0) AND (reduce_fraction IS NULL)))),
    CONSTRAINT deposit_tariff_waiver_grounds_range_check CHECK (((effective_to IS NULL) OR (effective_to > effective_from))),
    CONSTRAINT deposit_tariff_waiver_grounds_no_overlap
        EXCLUDE USING gist (tenant_id WITH =, state_code WITH =, service_type WITH =, ground_code WITH =,
                            daterange(effective_from, effective_to, '[)'::text) WITH &&)
);
CREATE INDEX IF NOT EXISTS idx_deposit_tariff_waiver_grounds_tenant ON public.deposit_tariff_waiver_grounds USING btree (tenant_id);
ALTER TABLE public.deposit_tariff_waiver_grounds ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.deposit_tariff_waiver_grounds FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_isolation ON public.deposit_tariff_waiver_grounds;
CREATE POLICY tenant_isolation ON public.deposit_tariff_waiver_grounds USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));
REVOKE DELETE, TRUNCATE ON public.deposit_tariff_waiver_grounds FROM tally_app;
COMMENT ON TABLE public.deposit_tariff_waiver_grounds IS
    'v5.4.2-15 (review r1 B3; R-D1). A waiver the UTILITY''s filed tariff adds, under the law''s permission (a deposit_waiver_classes row marked tariff_defined): its code, description and tariff provision (tariff_reference), its scope — the bases, customer classes and additional-deposit triggers it reaches (NULL = every one) — and its effect (excuse; reduce by reduce_fraction; defer by defer_days), dated. A determination of a tariff_defined class names the ground it rests on. Written by the utility (RLS); never deleted; the only edit is a close (effective_to, once, stamped), never on or before a date a determination cites it for. Whether it relieves a deposit is the core''s: where the law''s tariff class reaches the rule (#53 rank 3: a tariff may extend the statutory waivers, never narrow them).';

CREATE OR REPLACE FUNCTION public.enforce_deposit_tariff_waiver_ground() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    c_close_cols CONSTANT text[] := ARRAY['effective_to', 'closed_at', 'closed_by'];
    v_latest date;
BEGIN
    IF TG_OP = 'INSERT' THEN
        PERFORM public.assert_same_tenant_user(NEW.created_by, NEW.tenant_id, 'created_by');
        -- The law must permit a tariff waiver in this state and service.
        IF NOT EXISTS (SELECT 1 FROM public.deposit_waiver_classes w
                        WHERE w.state_code = NEW.state_code AND w.service_type = NEW.service_type AND w.tariff_defined) THEN
            RAISE EXCEPTION USING
                MESSAGE = format('deposit tariff waiver ground rejected: %s %s law has no tariff-defined waiver class (deposit_waiver_classes.tariff_defined) — v5.4.2-15', NEW.state_code, NEW.service_type),
                ERRCODE = 'check_violation';
        END IF;
        -- Its scope names known bases, this state's classes, known triggers.
        IF (NEW.reaches_bases IS NOT NULL AND EXISTS (SELECT 1 FROM unnest(NEW.reaches_bases) x(v)
                 WHERE NOT EXISTS (SELECT 1 FROM public.deposit_bases b WHERE b.basis_code = x.v)))
           OR (NEW.reaches_customer_classes IS NOT NULL AND EXISTS (SELECT 1 FROM unnest(NEW.reaches_customer_classes) x(v)
                 WHERE NOT EXISTS (SELECT 1 FROM public.deposit_customer_classes c
                                    WHERE c.state_code = NEW.state_code AND c.service_type = NEW.service_type AND c.class_code = x.v)))
           OR (NEW.reaches_triggers IS NOT NULL AND EXISTS (SELECT 1 FROM unnest(NEW.reaches_triggers) x(v)
                 WHERE NOT EXISTS (SELECT 1 FROM public.deposit_triggers t WHERE t.trigger_code = x.v))) THEN
            RAISE EXCEPTION USING
                MESSAGE = 'deposit tariff waiver ground rejected: its scope names a basis, customer class (of its state and service) or trigger that does not exist (v5.4.2-15)',
                ERRCODE = 'foreign_key_violation';
        END IF;
        NEW.created_at := now();
        NEW.closed_at  := NULL;
        NEW.closed_by  := NULL;
        RETURN NEW;
    END IF;
    IF OLD.effective_to IS NOT NULL OR NEW.effective_to IS NULL
       OR (to_jsonb(NEW) - c_close_cols) <> (to_jsonb(OLD) - c_close_cols) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('deposit tariff waiver ground %s: never edited — close it (effective_to, once, nothing else) and add its successor (v5.4.2-15)', OLD.id),
            ERRCODE = 'restrict_violation';
    END IF;
    SELECT max(d.determined_on) INTO v_latest FROM public.deposit_waiver_determinations d WHERE d.tariff_ground_id = OLD.id;
    IF v_latest IS NOT NULL AND NEW.effective_to <= v_latest THEN
        RAISE EXCEPTION USING
            MESSAGE = format('deposit tariff waiver ground %s: a determination cites it for %s; a close effective %s would put that outside its range (v5.4.2-15)', OLD.id, v_latest, NEW.effective_to),
            ERRCODE = 'restrict_violation';
    END IF;
    NEW.closed_at := now();
    BEGIN
        NEW.closed_by := NULLIF(current_setting('app.user_id', true), '')::uuid;
    EXCEPTION WHEN OTHERS THEN
        NEW.closed_by := NULL;
    END;
    RETURN NEW;
END;
$$;
COMMENT ON FUNCTION public.enforce_deposit_tariff_waiver_ground() IS
    'v5.4.2-15. BEFORE INSERT OR UPDATE on deposit_tariff_waiver_grounds. INSERT: created_by of the tenant; the state''s law has a tariff_defined waiver class; the scope names existing bases, the state''s customer classes and existing triggers; stamps. UPDATE: only a close (effective_to once, stamped), not on or before a date a determination cites the ground for.';
DROP TRIGGER IF EXISTS a_enforce_deposit_tariff_waiver_ground ON public.deposit_tariff_waiver_grounds;
CREATE TRIGGER a_enforce_deposit_tariff_waiver_ground BEFORE INSERT OR UPDATE ON public.deposit_tariff_waiver_grounds
    FOR EACH ROW EXECUTE FUNCTION public.enforce_deposit_tariff_waiver_ground();
DROP TRIGGER IF EXISTS no_hard_delete ON public.deposit_tariff_waiver_grounds;
CREATE TRIGGER no_hard_delete BEFORE DELETE ON public.deposit_tariff_waiver_grounds
    FOR EACH ROW EXECUTE FUNCTION public.enforce_no_hard_delete();
DROP TRIGGER IF EXISTS no_truncate ON public.deposit_tariff_waiver_grounds;
CREATE TRIGGER no_truncate BEFORE TRUNCATE ON public.deposit_tariff_waiver_grounds
    FOR EACH STATEMENT EXECUTE FUNCTION public.enforce_no_hard_delete();
ALTER TABLE public.deposit_tariff_waiver_grounds ENABLE ALWAYS TRIGGER a_enforce_deposit_tariff_waiver_ground;
ALTER TABLE public.deposit_tariff_waiver_grounds ENABLE ALWAYS TRIGGER no_hard_delete;
ALTER TABLE public.deposit_tariff_waiver_grounds ENABLE ALWAYS TRIGGER no_truncate;

ALTER TABLE public.deposit_waiver_determinations
    ADD COLUMN IF NOT EXISTS state_code       text,
    ADD COLUMN IF NOT EXISTS service_type     text,
    ADD COLUMN IF NOT EXISTS tariff_ground_id uuid;
-- Section 1 proved the table empty.
ALTER TABLE public.deposit_waiver_determinations ALTER COLUMN state_code SET NOT NULL;
ALTER TABLE public.deposit_waiver_determinations ALTER COLUMN service_type SET NOT NULL;
ALTER TABLE public.deposit_waiver_determinations DROP CONSTRAINT IF EXISTS deposit_waiver_determinations_class_check;
ALTER TABLE public.deposit_waiver_determinations DROP CONSTRAINT IF EXISTS deposit_waiver_determinations_certification_check;
ALTER TABLE public.deposit_waiver_determinations DROP CONSTRAINT IF EXISTS deposit_waiver_determinations_class_fkey;
ALTER TABLE public.deposit_waiver_determinations ADD CONSTRAINT deposit_waiver_determinations_class_fkey
    FOREIGN KEY (state_code, service_type, waiver_class)
    REFERENCES public.deposit_waiver_classes(state_code, service_type, class_code);
ALTER TABLE public.deposit_waiver_determinations DROP CONSTRAINT IF EXISTS deposit_waiver_determinations_tariff_ground_fkey;
ALTER TABLE public.deposit_waiver_determinations ADD CONSTRAINT deposit_waiver_determinations_tariff_ground_fkey
    FOREIGN KEY (tariff_ground_id, tenant_id) REFERENCES public.deposit_tariff_waiver_grounds(id, tenant_id);

CREATE OR REPLACE FUNCTION public.enforce_deposit_waiver_determination() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_class public.deposit_waiver_classes%ROWTYPE;
    v_ground public.deposit_tariff_waiver_grounds%ROWTYPE;
BEGIN
    PERFORM public.assert_same_tenant_user(NEW.determined_by, NEW.tenant_id, 'determined_by');
    SELECT * INTO v_class FROM public.deposit_waiver_classes w
     WHERE w.state_code = NEW.state_code AND w.service_type = NEW.service_type AND w.class_code = NEW.waiver_class;
    IF v_class.requires_certification AND (NEW.certification_reference IS NULL OR NEW.certification_reference !~ '[[:alnum:]]') THEN
        RAISE EXCEPTION USING
            MESSAGE = format('deposit waiver determination rejected: a %s %s %s determination rests on a certification — record its reference (v5.4.2-15)', NEW.state_code, NEW.service_type, NEW.waiver_class),
            ERRCODE = 'check_violation';
    END IF;
    -- A tariff-defined class names the utility's ground, of the same state
    -- and service, in force on the determination date; no other class does.
    IF coalesce(v_class.tariff_defined, false) <> (NEW.tariff_ground_id IS NOT NULL) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('deposit waiver determination rejected: class %s %s (deposit_waiver_classes.tariff_defined) — v5.4.2-15', NEW.waiver_class,
                             CASE WHEN v_class.tariff_defined THEN 'is the utility''s tariff waiver: name the ground (tariff_ground_id)' ELSE 'names no tariff ground' END),
            ERRCODE = 'check_violation';
    END IF;
    IF NEW.tariff_ground_id IS NOT NULL THEN
        SELECT * INTO v_ground FROM public.deposit_tariff_waiver_grounds g WHERE g.id = NEW.tariff_ground_id AND g.tenant_id = NEW.tenant_id;
        IF v_ground.state_code IS DISTINCT FROM NEW.state_code OR v_ground.service_type IS DISTINCT FROM NEW.service_type
           OR NOT coalesce(daterange(v_ground.effective_from, v_ground.effective_to, '[)') @> NEW.determined_on, false) THEN
            RAISE EXCEPTION USING
                MESSAGE = format('deposit waiver determination rejected: tariff ground %s is not this utility''s %s %s ground in force on %s (v5.4.2-15)', NEW.tariff_ground_id, NEW.state_code, NEW.service_type, NEW.determined_on),
                ERRCODE = 'check_violation';
        END IF;
    END IF;
    NEW.created_at := now();
    RETURN NEW;
END;
$$;
COMMENT ON FUNCTION public.enforce_deposit_waiver_determination() IS
    'v5.4.2-15. BEFORE INSERT on deposit_waiver_determinations: determined_by of the tenant; a class whose deposit_waiver_classes row requires a certification carries its reference; a tariff_defined class names the utility''s ground (same tenant, state and service, in force on the determination date), and no other class names one; created_at stamped.';
DROP TRIGGER IF EXISTS a_enforce_deposit_waiver_determination ON public.deposit_waiver_determinations;
CREATE TRIGGER a_enforce_deposit_waiver_determination BEFORE INSERT ON public.deposit_waiver_determinations
    FOR EACH ROW EXECUTE FUNCTION public.enforce_deposit_waiver_determination();
ALTER TABLE public.deposit_waiver_determinations ENABLE ALWAYS TRIGGER a_enforce_deposit_waiver_determination;

COMMENT ON TABLE public.deposit_waiver_determinations IS
    'CI-129 (v5.4.2-06; v5.4.2-15 at parity): a recorded deposit-waiver determination — that a customer qualified, under which state''s class (deposit_waiver_classes: state, service, class), on which date, with the certification''s reference and expiry where the class rests on one, and for a tariff-defined class the utility''s ground (tariff_ground_id). A point-in-time act, not a re-derivation: a lapse later does not reopen a deposit lawfully waived. Whether a waiver in force relieves a deposit is the core''s, from the rule''s reach (deposit_rule_waiver_reach) and, for a tariff ground, the ground''s own scope and effect. Append-only. SENSITIVE: the family-violence class is among the most sensitive data the platform holds; RLS applies, no column-level control exists (flagged).';


-- ----------------------------------------------------------------------------
-- 6b. Which rule a later record of a deposit may cite (review r1 B1)
-- ----------------------------------------------------------------------------
-- Ryan, 2026-10-02: when a state changes its deposit law, an amendment may
-- spare deposits already held (the old law governs them) or reach them (the
-- new law does). So an accrual, a return or a due row may cite either the
-- rule the deposit was decided under, or a rule of the same key (state,
-- service, class, basis) in force over the dates the record covers. Which one
-- applied is the core's; the citation records it.
CREATE OR REPLACE FUNCTION public.deposit_rule_citable(p_deposit_id uuid, p_rule_id uuid, p_from date, p_to date) RETURNS boolean
    LANGUAGE sql STABLE
    SET search_path = public, pg_temp
    AS $$
    SELECT EXISTS (
        SELECT 1
          FROM public.deposits d
          JOIN public.deposit_rules r ON r.id = p_rule_id
         WHERE d.id = p_deposit_id AND d.rule_id IS NOT NULL
           AND (r.id = d.rule_id
                OR (r.state_code = d.state_code AND r.service_type = d.service_type
                    AND r.customer_class = d.customer_class AND r.basis = d.basis
                    AND daterange(r.effective_from, r.effective_to, '[)') @> daterange(p_from, p_to, '[]'))))
$$;
COMMENT ON FUNCTION public.deposit_rule_citable(uuid, uuid, date, date) IS
    'v5.4.2-15 (review r1 B1; Ryan, 2026-10-02). Whether a later record of a deposit covering p_from..p_to may cite p_rule_id: the deposit''s own rule (the law it was decided under), or a rule of the same state, service, class and basis in force over the whole span (a later law that reaches deposits already held). A carried legacy deposit cites none.';


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
-- evaluation); no return has started; at most one live (unwithdrawn) due
-- row per deposit, serialised by a ROW-VERSION mutex on the deposit row — a
-- due row and a withdrawal write a version of it, as every deposit event
-- does through its projection, so a REPEATABLE READ racer fails on the
-- version instead of counting from a stale snapshot (review r1 A1, Opus and
-- Fable; the -10/-13 rule); every due row has evidence; each reason is one
-- its rule enables; evidence is of the deposit's customer, from on or after
-- posting, of its reason's kind (a closure to a qualifying status), and only
-- in its due row's transaction; withdrawals once each; stamps.

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
    rests_on_deposit         boolean DEFAULT false NOT NULL,
    CONSTRAINT deposit_return_due_evidence_pkey PRIMARY KEY (id),
    CONSTRAINT deposit_return_due_evidence_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id),
    CONSTRAINT deposit_return_due_evidence_due_fkey FOREIGN KEY (due_id, tenant_id) REFERENCES public.deposit_return_due(id, tenant_id),
    CONSTRAINT deposit_return_due_evidence_reason_fkey FOREIGN KEY (reason_code) REFERENCES public.deposit_return_reasons(reason_code),
    CONSTRAINT deposit_return_due_evidence_invoice_fkey FOREIGN KEY (invoice_id, tenant_id) REFERENCES public.invoices(id, tenant_id),
    CONSTRAINT deposit_return_due_evidence_state_event_fkey FOREIGN KEY (customer_state_event_id) REFERENCES public.customer_state_events(id),
    -- One subject per row: a bill with the core's classification of it, a
    -- state change, or the deposit itself (a return due on time held).
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
    -- Write a version of the deposit row: a concurrent REPEATABLE READ
    -- transaction that also takes the mutex then fails to serialise, rather
    -- than counting live rows from its old snapshot.
    UPDATE public.deposits x SET status = x.status WHERE x.id = d.id;
    IF NOT public.deposit_rule_citable(d.id, NEW.rule_id, NEW.due_on, NEW.due_on) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('deposit return due: it cites rule %s, which is neither the rule deposit %s was decided under (%s) nor a rule of its key in force on %s (v5.4.2-15)', NEW.rule_id, d.id, coalesce(d.rule_id::text, 'none — a carried legacy deposit'), NEW.due_on),
            ERRCODE = 'check_violation';
    END IF;
    SELECT * INTO v_rule FROM public.deposit_rules r WHERE r.id = NEW.rule_id;
    IF v_rule.refund_mandatory IS NOT TRUE
       OR NOT coalesce(d.instrument = ANY (v_rule.return_mandatory_instruments), false) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('deposit return due: rule %s makes no mandatory return of a %s deposit (refund_mandatory, return_mandatory_instruments) — v5.4.2-15', NEW.rule_id, d.instrument),
            ERRCODE = 'check_violation';
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
    'v5.4.2-15 (R-D2). BEFORE INSERT on deposit_return_due: locks the deposit row and writes a version of it (the row-version mutex every deposit event shares); the cited rule is the deposit''s own or one of its key in force on due_on (deposit_rule_citable, B1), and its stored attributes make the return mandatory for the deposit''s instrument; no return has started (refund_pending, refunded, released); due_on is on or after posting; no live (unwithdrawn) due row exists for the deposit; a superseded row is a withdrawn row of the same deposit; stamps created_at, created_by (session user), due_seq and recorded_txid (the transaction its evidence must be written in). Judges nothing the core computed.';
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
    v_reason public.deposit_return_reasons%ROWTYPE;
BEGIN
    SELECT r.recorded_txid, d.customer_id, d.posted_on, rl.refund_after_count, rl.refund_on_account_close INTO v_due
      FROM public.deposit_return_due r
      JOIN public.deposits d ON d.id = r.deposit_id
      JOIN public.deposit_rules rl ON rl.id = r.rule_id
     WHERE r.id = NEW.due_id;
    IF v_due.recorded_txid IS DISTINCT FROM txid_current() THEN
        RAISE EXCEPTION USING
            MESSAGE = format('deposit return due evidence: due row %s was recorded in an earlier transaction; its evidence is complete (v5.4.2-15)', NEW.due_id),
            ERRCODE = 'restrict_violation',
            HINT = 'Withdraw the row and record a new one, with its evidence, in one transaction.';
    END IF;
    SELECT * INTO v_reason FROM public.deposit_return_reasons x WHERE x.reason_code = NEW.reason_code;
    IF v_reason.evidence_kind IS DISTINCT FROM (CASE WHEN NEW.invoice_id IS NOT NULL THEN 'invoice'
                                                     WHEN NEW.customer_state_event_id IS NOT NULL THEN 'state_event'
                                                     ELSE 'deposit' END) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('deposit return due evidence: reason %s rests on %s records (v5.4.2-15)', NEW.reason_code, coalesce(v_reason.evidence_kind, '(unknown reason)')),
            ERRCODE = 'check_violation';
    END IF;
    -- The reason is one the due row's rule makes a trigger (review r1 A14).
    IF NOT coalesce((CASE v_reason.enabled_by
                         WHEN 'history_trigger' THEN v_due.refund_after_count IS NOT NULL
                         WHEN 'account_close'   THEN v_due.refund_on_account_close
                     END), false) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('deposit return due evidence: reason %s is a trigger only under a rule with %s; this due row''s rule has none (v5.4.2-15)', NEW.reason_code,
                             CASE v_reason.enabled_by WHEN 'history_trigger' THEN 'a count-based trigger (refund_after_count)' ELSE 'refund_on_account_close' END),
            ERRCODE = 'check_violation';
    END IF;
    IF NEW.invoice_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM public.invoices i WHERE i.id = NEW.invoice_id AND i.customer_id = v_due.customer_id AND i.invoice_date >= v_due.posted_on) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('deposit return due evidence: invoice %s is not a bill of the deposit''s customer dated on or after its posting (v5.4.2-15)', NEW.invoice_id),
            ERRCODE = 'check_violation';
    END IF;
    IF NEW.customer_state_event_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM public.customer_state_events s
         WHERE s.id = NEW.customer_state_event_id AND s.customer_id = v_due.customer_id
           AND s.to_status = ANY (v_reason.qualifying_statuses) AND s.effective_at::date >= v_due.posted_on) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('deposit return due evidence: state event %s is not a change of the deposit''s customer to %s on or after its posting (review r1 A4; v5.4.2-15)', NEW.customer_state_event_id, array_to_string(v_reason.qualifying_statuses, ' / ')),
            ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$;
COMMENT ON FUNCTION public.enforce_deposit_return_due_evidence() IS
    'v5.4.2-15. BEFORE INSERT on deposit_return_due_evidence: only in its due row''s transaction (deposit_return_due.recorded_txid); the subject is of the reason''s evidence kind (bill, state change, the deposit itself); the reason is one the due row''s rule enables (deposit_return_reasons.enabled_by); a bill is the deposit''s customer''s and dated on or after posting; a state change is the deposit''s customer''s, to one of the reason''s qualifying statuses, on or after posting. Which bills count and how is the core''s.';
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
    'v5.4.2-15 (R-D2). The core''s record that a deposit''s mandatory return fell due: the deposit, the date, the rule row (the deposit''s own), the inputs and their fingerprint, the core version, stamped. Written when the answer changes, never per check; the core checks on the events that can change it (payment, bill past due, status change, reversal, correction). Its reasons and what they rest on are deposit_return_due_evidence, in the same transaction. A row found wrong is withdrawn (deposit_return_due_withdrawals) and a corrected answer is a new row naming it (supersedes_due_id). At most one live row per deposit. Append-only.';
COMMENT ON TABLE public.deposit_return_due_evidence IS
    'v5.4.2-15 (R-D2). Why a return fell due and on what: one row per reason and record — a bill with the core''s classification of it (clean, delinquent, not_counted), the customer''s state change, or the deposit itself (rests_on_deposit: a return due on time held). Written in its due row''s transaction; append-only. The counts are derived from these rows.';
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
-- A partial return of principal (review r1 A11): part of what is held goes
-- back to the customer while the rest stays held — the excess over a cap, an
-- annual review. A full return is a refund or a release.
ALTER TABLE public.deposit_events DROP CONSTRAINT IF EXISTS deposit_events_type_check;
ALTER TABLE public.deposit_events ADD CONSTRAINT deposit_events_type_check
    CHECK ((event_type = ANY (ARRAY['posted'::text, 'applied_to_balance'::text, 'interest_accrued'::text, 'interest_credited'::text,
                                    'principal_returned'::text, 'refund_initiated'::text, 'refunded'::text, 'released'::text])));
-- An accrual carries its period, rate, principal basis, the rate row and rule
-- row it used, and the core version. A return (refund_initiated, refunded,
-- released, principal_returned) may name the rule and core version that
-- decided it (review r1 A8: "no interest is owed" is a decision too). Nothing
-- else carries any of them.
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
    CHECK (((return_due_id IS NULL) OR (event_type = ANY (ARRAY['refund_initiated'::text, 'refunded'::text, 'released'::text]))));

-- The balance reads (-06), re-issued so a partial return leaves the
-- remainder and the principal in force (review r1 A11). Signatures and
-- columns unchanged: `applied` is still applications to balance only.
CREATE OR REPLACE FUNCTION public.deposit_balance(p_deposit_id uuid)
    RETURNS TABLE (principal numeric, applied numeric, remainder numeric, interest_accrued numeric, interest_credited numeric, days_held integer, accrued_through date, exhausted_on date)
    LANGUAGE sql STABLE
    SET search_path = public, pg_temp
    AS $$
    SELECT d.principal,
           coalesce((SELECT sum(e.amount) FROM public.deposit_events e WHERE e.deposit_id = d.id AND e.event_type = 'applied_to_balance'), 0),
           d.principal - coalesce((SELECT sum(e.amount) FROM public.deposit_events e WHERE e.deposit_id = d.id AND e.event_type IN ('applied_to_balance', 'principal_returned')), 0),
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
COMMENT ON FUNCTION public.deposit_balance(uuid) IS 'Derived from deposit_events (never stored): principal, applied to balance, remainder (less applications and partial returns), interest accrued, interest credited, days held (to refund/release/today), accrued-through date, exhausted_on (the day applications and returns together reached the principal). v5.4.2-06; re-issued by v5.4.2-15.';

CREATE OR REPLACE FUNCTION public.deposit_principal_in_force(p_deposit_id uuid, p_on date) RETURNS numeric
    LANGUAGE sql STABLE
    SET search_path = public, pg_temp
    AS $$
    SELECT d.principal - coalesce((SELECT sum(e.amount) FROM public.deposit_events e WHERE e.deposit_id = d.id AND e.event_type IN ('applied_to_balance', 'principal_returned') AND e.effective_on <= p_on), 0)
    FROM public.deposits d WHERE d.id = p_deposit_id
$$;
COMMENT ON FUNCTION public.deposit_principal_in_force(uuid, date) IS 'Principal held on p_on: principal less applications and partial returns effective on or before that day (a plain read; which principal interest is owed on is the core''s). v5.4.2-06; re-issued by v5.4.2-15.';

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
    -- A rule an event names is the deposit's own, or one of its key in force
    -- over the dates the event covers (B1): an accrual's period, a return's day.
    IF NEW.rule_id IS NOT NULL
       AND NOT public.deposit_rule_citable(d.id, NEW.rule_id, coalesce(NEW.period_start, NEW.effective_on), coalesce(NEW.period_end, NEW.effective_on)) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('deposit %s: rule %s is neither the rule the deposit was decided under (%s) nor a rule of its key in force over %s..%s (v5.4.2-15)', d.id, NEW.rule_id, coalesce(d.rule_id::text, 'none — a carried legacy deposit'), coalesce(NEW.period_start, NEW.effective_on), coalesce(NEW.period_end, NEW.effective_on)),
            ERRCODE = 'check_violation';
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
    -- Arithmetic, not law (review r1 A7): money handed back on a day cannot
    -- have earned interest after that day.
    IF NEW.event_type IN ('principal_returned', 'refund_initiated', 'refunded', 'released')
       AND b.accrued_through IS NOT NULL AND NEW.effective_on <= b.accrued_through THEN
        RAISE EXCEPTION USING
            MESSAGE = format('deposit %s: interest is recorded as earned through %s; a %s effective %s would say the money left while still earning (v5.4.2-15)', d.id, b.accrued_through, NEW.event_type, NEW.effective_on),
            ERRCODE = 'check_violation';
    END IF;

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
        IF d.rule_id IS NULL THEN
            RAISE EXCEPTION USING
                MESSAGE = format('deposit %s is a carried legacy deposit: it cites no rule and accrues nothing here (v5.4.2-15)', d.id),
                ERRCODE = 'check_violation';
        END IF;
        SELECT * INTO v_rate FROM public.deposit_interest_rates r WHERE r.id = NEW.rate_id;
        IF v_rate.tenant_id IS DISTINCT FROM d.tenant_id OR v_rate.state_code IS DISTINCT FROM d.state_code
           OR v_rate.service_type IS DISTINCT FROM d.service_type
           OR NOT coalesce(v_rate.customer_class IS NULL OR v_rate.customer_class = d.customer_class, false) THEN
            RAISE EXCEPTION USING
                MESSAGE = format('deposit %s: rate row %s is not this utility''s rate for %s %s %s (v5.4.2-15)', d.id, NEW.rate_id, d.state_code, d.service_type, d.customer_class),
                ERRCODE = 'check_violation';
        END IF;
        -- Shared with the rate side's exclusive lock (section 4, review r1 A2):
        -- a rate insert for this tenant, state and service waits for this
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
        IF NEW.period_start < d.posted_on THEN
            RAISE EXCEPTION USING
                MESSAGE = format('deposit %s: an accrual period cannot start (%s) before the deposit was posted (%s)', d.id, NEW.period_start, d.posted_on),
                ERRCODE = 'check_violation';
        END IF;
        IF NEW.period_end >= NEW.effective_on THEN
            RAISE EXCEPTION USING MESSAGE = format('deposit %s: an accrual is recorded after the period it covers (period_end %s, effective_on %s)', d.id, NEW.period_end, NEW.effective_on), ERRCODE = 'check_violation';
        END IF;
        -- Arithmetic, not law (review r1 A7): nothing earns after it was used
        -- up, and no more is earned on than was ever held.
        IF b.exhausted_on IS NOT NULL AND NEW.period_start >= b.exhausted_on THEN
            RAISE EXCEPTION USING
                MESSAGE = format('deposit %s: the principal was used up on %s; nothing is held from then to accrue on (period from %s) — v5.4.2-15', d.id, b.exhausted_on, NEW.period_start),
                ERRCODE = 'check_violation';
        END IF;
        IF NEW.principal_basis > d.principal THEN
            RAISE EXCEPTION USING
                MESSAGE = format('deposit %s: principal_basis %s exceeds the principal %s (v5.4.2-15)', d.id, NEW.principal_basis, d.principal),
                ERRCODE = 'check_violation';
        END IF;
    WHEN 'interest_credited' THEN
        IF NEW.amount <= 0 OR NEW.amount > b.interest_accrued - b.interest_credited THEN
            RAISE EXCEPTION USING MESSAGE = format('deposit %s: interest_credited must be > 0 and ≤ accrued − credited (%s)', d.id, b.interest_accrued - b.interest_credited), ERRCODE = 'check_violation';
        END IF;
    WHEN 'principal_returned' THEN
        -- Part of the principal goes back; the rest stays held (review r1 A11).
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
    'v5.4.2-06, re-issued by v5.4.2-15 (deposits at parity). The deposit sub-ledger''s integrity: locks the deposit row (so events, due rows and withdrawals serialise); tenant, actor, dates, ledger link; nothing after refunded / released; the posted event is the database''s; a rule an event names is the deposit''s own or one of its key in force over the event''s dates (B1); applications within the remainder, not while a refund is pending, not into an accrued period; an accrual cites a rate row of its tenant, state, service and (or every) class in effect by the period''s start, at that rate, takes the shared rate lock, lies within the deposit''s life and before the principal was used up, on no more than the principal, recorded after the period; credits within accrued − credited; a partial return below the remainder; no return dated inside an accrued period; one pending refund; full returns of exactly the remainder, cash refunded and non-cash released, leaving nothing accrued uncredited; a legacy return without accruals states how its interest was settled; a cited return-due row is live and the deposit''s. Decides no law: whether interest is owed, at which rate row, over which periods and in what amount are the core''s.';

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
--
-- R8. THE PREMISE IS NOT RECORDED (review r1 C1). A deposit records the
--     state it was decided under, not the service location that state came
--     from. It waits for the places table (as v5.4.2-13's R2 and R13).
--
-- R9. UNDATED VOCABULARIES, CHECK-LIST ENUMERATIONS (review r1 C2). Waiver
--     and customer classes have no dates; a rule's cap kind, interest
--     method, day count, credit cadence, refund measure and lookback unit,
--     the instrument lists, the evidence kinds and the waiver effects are
--     CHECK lists, as v5.4.2-13's are. A new value is a reviewed migration
--     plus a core change either way.
--
-- R10. A RECORDED CAP IS NOT CHECKED AGAINST ITS BASIS (review r1 C3).
--     cap_amount = cap_basis_amount ÷ divisor (or × months) is the formula,
--     and its rounding is the core's; recording both makes a mismatch
--     visible.
--
-- R11. A SETTLED DUE ROW CAN STILL BE WITHDRAWN (review r1 C4). By design
--     (R-D2): a withdrawal says the answer was wrong and moves no money; the
--     correction is the deposit's own events.
--
-- R12. OPEN WITH RYAN (B3 review, 2026-10-02), each its own decision:
--     a record of a deposit NOT taken (a waived decision leaves no row today);
--     an explicit "no waiver reaches this rule" flag (an empty reach list
--     could be an omission); missing waiver input — fail open or closed — as
--     a dated rule setting (Texas: #53 rank 4, fail open); which waiver the
--     core records when two are in force; and whether a waiver determined
--     after a deposit is held returns it.

-- ----------------------------------------------------------------------------
-- 11. The AC-32 tail
-- ----------------------------------------------------------------------------
-- Four new tenant tables and two new views, each born leaky by the default
-- grants. The assertion raises if any lacks RLS, FORCE, the single canonical
-- policy, or invoker rights. The ten law tables carry no tenant_id and are
-- read-only to tally_app.

SELECT public.assert_tenant_isolation_invariants();

-- ============================================================================
-- END PATCH v5.4.2-15
-- ============================================================================
