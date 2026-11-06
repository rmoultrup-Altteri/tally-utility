-- ============================================================================
-- PATCH v5.4.2-27 — a credit applied to a bounced payment's shortfall
--                    (AC-44's netting, recorded)
-- ============================================================================
-- Authority:   Kyle, 2026-10-30: all of a customer's credits are one pot
--              (GBM kyle-decisions-2026-10-30-credit-shortfall-after-
--              bounce.md). Ryan, 2026-11-02: the netting is recorded as a new
--              kind of application pointed at the payment's shortfall, its
--              own patch, never a billed charge (K-10); -27 next after -23.
--              Ryan, 2026-11-05 (option 1): a refund that comes back after
--              its shortfall was repaid waits until the repayment is undone.
--              Ryan, 2026-11-05 (r1 review, option 1): an undo whose credit
--              was since escheated carries the money into a new credit.
-- Spec:        application/wave2-build-2026-10-15/v5.4.2-27-design.md;
--              DECISION-LOG 2026-11-02 (-23 r8), 2026-11-05 (-27 design) and
--              2026-11-05 (-27 r1); v5.4.2-27-r2-plan.md, -r3-plan.md.
--              ADDITIVE: a new table and new terms in -23's readers; no
--              existing column changes meaning (payment_position_as_of gains
--              a last column, repaid).
--
-- ----------------------------------------------------------------------------
-- What changes
-- ----------------------------------------------------------------------------
--   * shortfall_applications: money of a customer (a posted non-deposit
--     payment's or an active credit's, typed FKs, one of them) applied to
--     what a payment of the same customer left owed when it bounced or was
--     reversed (target_payment_id). Add-only; a mistake is undone by a
--     negative row naming it (basis undo, reason, user), at most its amount;
--     an undo is never undone. basis: customer_pot (the core's netting under
--     Kyle's one-pot ruling), operator_override (reason, user), undo. Every
--     key carries the tenant; RLS and FORCE RLS. No ledger row: the ledger is
--     per customer and its balance is already right; the row records whose
--     money paid the debt (as a bill application posts none).
--   * The source: the draw counts in its applied (customer_credit_draws_as_
--     of, payment_draws_as_of), its caps and its recorded order (cash_source_
--     draws): purpose shortfall in check_cash_source, from the
--     sources a bill application takes. A credit holding the target's own
--     money (an overpayment credit of the target or a reissue descended from
--     one) applies with purpose shortfall_within_family: R24's closing act.
--     It is not held to the cap on the payment and its credits together: the
--     repayment comes back into that sum (as r9's reissue).
--   * The target: repaid, a new term of payment_draws_as_of and a new last
--     column of payment_position_as_of (remaining = received - applied -
--     credited - refunded + repaid); on the payment's own part in
--     overpayment_absorbed_as_of, so the cover places it as any money of the
--     payment. In cash_source_draws as a negative draw on the target.
--   * The target's cap (check_shortfall_repaid): the payment and its
--     overpayment family together never hold money, outside R5's interval
--     (r3, Codex N5): a payment that has ended holds none (-23), so a
--     shortfall is repaid down to 0, never past it. A repayment is checked from its own date on. A move that gives the
--     family money back afterwards is checked from the first repayment's
--     date on (r2, Codex B1, Opus B1: r1 read from the latest row's date, and
--     a later repayment hid an earlier one), with an undo counted from the
--     date of the row it undoes, which it corrects: the operator's undo,
--     dated when it is recorded, settles the repayment from its own date.
--     The moves: a refund of the payment or of a family credit that leaves
--     (voided, nsf, reversed), an undo of an application, a donation or a
--     repayment on a family credit (Ryan, 2026-11-05, option 1: the operator
--     undoes the repayment first, in the same transaction). r3 (Opus B1):
--     such a move is also read from today on, every row at its own date, so
--     an undo dated after today does not settle it (R5 stays in the past).
--   * The target is a bill payment (r2, Opus S1, S2): a refund is refused
--     with its own message, and a deposit, which is kept out of the pot
--     (K-05).
--   * The carry (r2; Ryan, 2026-11-05, option 1; Opus B2, Fable S1): the
--     undo of a credit's repayment is admitted after the credit was
--     escheated (purpose shortfall_undo), and what it gives back goes, in
--     the same transaction, into a new credit naming the undo: origin
--     shortfall_reissue, customer_credits.reissues_shortfall_application_id,
--     as -23's refund_reissue (Ryan, 2026-10-21). It draws on the escheated
--     credit, posts no ledger row, carries what the undo gave back as far as
--     it is left on the credit, is dated on or after the undo, is never
--     voided, and is checked at commit (enforce_shortfall_undo_carried). r3:
--     it is born active for every role, a history load's too (Codex B1), and
--     the undo it names was recorded at or after the credit's escheat (Opus
--     S1: one recorded before left nothing to carry). It
--     is in the escheated credit's overpayment line where that has one: the
--     three walks of the line follow it (reissue_generation, overpayment_
--     root, overpayment_family), and its issued is its amount, or its
--     amount less its share, as a refund_reissue's (customer_credit_
--     position_as_of). Its key is fixed. As a source it has no arrival
--     entry, as a refund_reissue (check_cash_source).
--   * A repayment goes to a payment that bounced or was reversed (nsf or
--     reversed), is recorded after its move (40001; 23514 for a chosen time),
--     and after every row already drawing on it or its family, a draw that
--     has left them, or a row under its posting entry (check_cash_order).
--   * A source applied to a shortfall holds up its own bounce as a bill
--     application does (R15): its posting entry is not taken back, and it
--     does not move to nsf, reversed or voided, while its shortfall
--     applications (or its overpayment family's) net to more than 0. A
--     credit's credit_issued entry already waits on every draw
--     (cash_source_draws).
--   * The close freezes a row by applied_on (-22 P2).
--   * cash_drawn_at (what a source had given at an instant; the shares read
--     it at a take-back's instant): r2 counts the shortfall rows, the
--     repaid term and the carry, as cash_source_draws does. r1 left it
--     unchanged (a take-back waits while its source is applied), but a carry
--     draws on an escheated credit, and leaving it out would read that
--     credit as holding money.
--   * assert_shortfall_guard_invariants().
--
-- ----------------------------------------------------------------------------
-- Lock order (-23's rule, extended)
-- ----------------------------------------------------------------------------
--   A shortfall application takes its tenant's close head (the freeze), then
--   the target payment's lock, then its source's (check_cash_source: the
--   payment whose money a credit holds, then the credit). Within one family
--   the target is that payment, so the order is -23's: the payment, then its
--   credits. Two applications between two families in opposite directions
--   can deadlock; every writer retries 40P01 and 40001. READ COMMITTED only.
--
-- ----------------------------------------------------------------------------
-- Residuals (left on purpose)
-- ----------------------------------------------------------------------------
--   R1. Which shortfall and which credit go first, and when to net (before
--       a refund, Kyle), are the core's (AC-44). A database refusal of a
--       refund while the customer owes a shortfall stays a later tightening
--       (DECISION-LOG 2026-11-01).
--   R2. Netting across payments before an escheat report is a per-state
--       rule the core reads (AC-44; Ryan, 2026-11-02). A credit whose money
--       was applied reads nothing and has nothing to report.
--   R3. Only a payment that ended (nsf or reversed) is a target. A posted
--       payment left short by a partial reversal after a refund still takes
--       money back under its posting entry, so it is not one; its shortfall
--       is collected as -23 left it.
--   R4. -23's R23 (the netting's record) and R24 (a credit at 0 that never
--       closes) are closed by this row; the core still nets the pot in what
--       it shows (one net balance, AC-44).
--   R5. (r2, Fable N3.) The positions read an undo at its own date. Between
--       a repayment and the undo that corrects it after a refund came back,
--       the ended payment reads the money it was repaid; the cap admits it,
--       since the undo corrects from the repayment's date and a closed
--       period cannot be written into. The core reads an undo as correcting
--       its row (AC-44). r3 (Opus B1): only before today. "Today" is the
--       latest date anywhere (UTC+14), so in a zone behind it an undo dated
--       the next local day is admitted: the interval reaches at most that
--       day ahead.
--
-- Tests. battery-27 (135 checks), races/shortfall-27.sh (SR1-SR9, 16 results),
--   mutations-27.py (67 mutations). -23's battery (409) and races (51) pass
--   with -27 applied. assert_shortfall_guard_invariants() runs in the tail
--   and in CI.
--
-- PRECONDITION. v5.4.2-23 applied. Applied by a superuser, under READ
--   COMMITTED. A second run finds shortfall_applications and skips the whole
--   patch (psql's \if): apply it with psql.
-- ============================================================================

SELECT to_regclass('public.customer_credit_approvals') IS NULL AS no_cash \gset
\if :no_cash
DO $$ BEGIN RAISE EXCEPTION 'v5.4.2-27 needs v5.4.2-23 (customer_credit_approvals is missing)'; END $$;
\endif
SELECT to_regclass('public.shortfall_applications') IS NOT NULL AS already \gset
\if :already
DO $$ BEGIN RAISE NOTICE 'v5.4.2-27: already applied (shortfall_applications exists); nothing to do'; END $$;
\else
BEGIN;

-- ----------------------------------------------------------------------------
-- 1. The table
-- ----------------------------------------------------------------------------
CREATE TABLE public.shortfall_applications (
    id                              uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id                       uuid NOT NULL,
    customer_id                     uuid NOT NULL,
    target_payment_id               uuid NOT NULL,
    payment_id                      uuid,
    customer_credit_id              uuid,
    amount                          numeric(12,2) NOT NULL,
    applied_on                      date NOT NULL,
    basis                           text NOT NULL,
    applied_by                      uuid,
    reason                          text,
    undoes_shortfall_application_id uuid,
    created_at                      timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT shortfall_applications_pkey PRIMARY KEY (id),
    CONSTRAINT shortfall_applications_tenant_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants (id),
    -- Every key carries the tenant (and the customer): a single-column key
    -- skips row-level security (rates' board note, 2026-11-04).
    CONSTRAINT shortfall_applications_target_fkey
        FOREIGN KEY (target_payment_id, tenant_id, customer_id) REFERENCES public.payments (id, tenant_id, customer_id),
    CONSTRAINT shortfall_applications_payment_fkey
        FOREIGN KEY (payment_id, tenant_id, customer_id) REFERENCES public.payments (id, tenant_id, customer_id),
    CONSTRAINT shortfall_applications_credit_fkey
        FOREIGN KEY (customer_credit_id, tenant_id, customer_id) REFERENCES public.customer_credits (id, tenant_id, customer_id),
    CONSTRAINT shortfall_applications_applied_by_fkey FOREIGN KEY (applied_by, tenant_id) REFERENCES public.users (id, tenant_id),
    CONSTRAINT shortfall_applications_id_tenant_target_key UNIQUE (id, tenant_id, target_payment_id),
    -- r2: the key a shortfall_reissue credit names (its tenant and customer).
    CONSTRAINT shortfall_applications_id_tenant_customer_key UNIQUE (id, tenant_id, customer_id),
    CONSTRAINT shortfall_applications_undoes_fkey
        FOREIGN KEY (undoes_shortfall_application_id, tenant_id, target_payment_id)
        REFERENCES public.shortfall_applications (id, tenant_id, target_payment_id),
    CONSTRAINT shortfall_applications_one_source_check
        CHECK (num_nonnulls(payment_id, customer_credit_id) = 1),
    CONSTRAINT shortfall_applications_not_own_check CHECK (payment_id IS DISTINCT FROM target_payment_id),
    CONSTRAINT shortfall_applications_basis_check
        CHECK (basis = ANY (ARRAY['customer_pot'::text, 'operator_override'::text, 'undo'::text])),
    -- An undo, and only an undo, is negative and names the row it undoes.
    CONSTRAINT shortfall_applications_sign_check
        CHECK (amount <> 0
               AND (amount < 0) = (basis = 'undo')
               AND (basis = 'undo') = (undoes_shortfall_application_id IS NOT NULL)),
    CONSTRAINT shortfall_applications_not_self_check CHECK (undoes_shortfall_application_id IS DISTINCT FROM id),
    -- CI-049's rule: an operator's choice and an undo say why, and who.
    CONSTRAINT shortfall_applications_operator_check
        CHECK (basis NOT IN ('operator_override', 'undo')
               OR (applied_by IS NOT NULL AND coalesce(reason ~ '[[:alnum:]]', false)))
);
ALTER TABLE public.shortfall_applications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.shortfall_applications FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON public.shortfall_applications USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));
CREATE INDEX idx_shortfall_apps_target ON public.shortfall_applications (target_payment_id);
CREATE INDEX idx_shortfall_apps_payment ON public.shortfall_applications (payment_id) WHERE payment_id IS NOT NULL;
CREATE INDEX idx_shortfall_apps_credit ON public.shortfall_applications (customer_credit_id) WHERE customer_credit_id IS NOT NULL;
CREATE INDEX idx_shortfall_apps_undoes ON public.shortfall_applications (undoes_shortfall_application_id) WHERE undoes_shortfall_application_id IS NOT NULL;
CREATE TRIGGER a_stamp_created_at BEFORE INSERT ON public.shortfall_applications
    FOR EACH ROW EXECUTE FUNCTION public.stamp_log_created_at();
ALTER TABLE public.shortfall_applications ENABLE ALWAYS TRIGGER a_stamp_created_at;
-- Money dated by a day: the close freezes it (-22 P2); the freeze takes the
-- tenant's close head, first in the lock order.
CREATE TRIGGER a_enforce_accounting_freeze BEFORE INSERT ON public.shortfall_applications
    FOR EACH ROW EXECUTE FUNCTION public.enforce_accounting_freeze('applied_on');
ALTER TABLE public.shortfall_applications ENABLE ALWAYS TRIGGER a_enforce_accounting_freeze;
CREATE TRIGGER append_only BEFORE DELETE OR UPDATE ON public.shortfall_applications
    FOR EACH ROW EXECUTE FUNCTION public.enforce_append_only();
ALTER TABLE public.shortfall_applications ENABLE ALWAYS TRIGGER append_only;
CREATE TRIGGER no_hard_delete BEFORE DELETE ON public.shortfall_applications
    FOR EACH ROW EXECUTE FUNCTION public.enforce_no_hard_delete();
ALTER TABLE public.shortfall_applications ENABLE ALWAYS TRIGGER no_hard_delete;
CREATE TRIGGER no_truncate BEFORE TRUNCATE ON public.shortfall_applications
    FOR EACH STATEMENT EXECUTE FUNCTION public.enforce_no_hard_delete();
ALTER TABLE public.shortfall_applications ENABLE ALWAYS TRIGGER no_truncate;
COMMENT ON TABLE public.shortfall_applications IS
    'v5.4.2-27 (AC-44; Kyle, 2026-10-30; Ryan, 2026-11-02). Money of a customer applied to what one of the customer''s payments left owed when it bounced or was reversed: from a posted non-deposit payment or an active credit (one of payment_id, customer_credit_id), to target_payment_id (nsf or reversed). Never a billed charge (K-10). Add-only: a mistake is undone by a negative row naming it (basis undo), never edited. created_at is the database''s (the recorded instant the positions read); applied_on is the money date (frozen by the close). No ledger row: the customer''s balance is already right; the row records whose money paid the debt. The source counts it in applied; the target in repaid (payment_position_as_of). From the first repayment''s date on, the target and its overpayment family never hold money (check_shortfall_repaid), outside the interval between a repayment and an undo, dated no later than today, that corrects it after a refund came back (residual R5; r3).';
COMMENT ON COLUMN public.shortfall_applications.basis IS
    'v5.4.2-27. customer_pot: the core netted the customer''s credits against the shortfall under Kyle''s one-pot ruling (AC-44). operator_override: an operator chose it (reason, user). undo: the negative row taking back a shortfall application (reason, user).';
COMMENT ON COLUMN public.shortfall_applications.target_payment_id IS
    'v5.4.2-27. The payment whose shortfall is repaid: one that bounced or was reversed (nsf or reversed), of the same tenant and customer as the source.';

-- ----------------------------------------------------------------------------
-- 1b. The carry (r2; Ryan, 2026-11-05, option 1; Opus B2, Fable S1)
-- ----------------------------------------------------------------------------
-- A credit that paid part of a shortfall can be escheated for the rest. If
-- the bounced payment's refund then comes back, the repayment is undone
-- (option 1), and the undo gives money back to a credit that has ended.
-- As -23's refund_reissue (Ryan, 2026-10-21), it goes into a new credit for
-- the customer, naming the undo, in the same transaction.
ALTER TABLE public.customer_credits DROP CONSTRAINT customer_credits_origin_type_check;
ALTER TABLE public.customer_credits ADD CONSTRAINT customer_credits_origin_type_check
    CHECK ((origin_type = ANY (ARRAY['overpayment'::text, 'goodwill'::text, 'dispute_resolution'::text, 'deposit_refund'::text, 'transfer'::text, 'adjustment'::text, 'refund_reissue'::text, 'regulatory_rebate'::text, 'promotion'::text, 'other'::text, 'shortfall_reissue'::text])));
ALTER TABLE public.customer_credits
    ADD COLUMN reissues_shortfall_application_id uuid,
    ADD CONSTRAINT customer_credits_reissue_shortfall_fkey
        FOREIGN KEY (reissues_shortfall_application_id, tenant_id, customer_id) REFERENCES public.shortfall_applications (id, tenant_id, customer_id),
    ADD CONSTRAINT customer_credits_shortfall_reissue_check
        CHECK ((origin_type = 'shortfall_reissue') = (reissues_shortfall_application_id IS NOT NULL));
CREATE UNIQUE INDEX customer_credits_one_per_shortfall_undo ON public.customer_credits (reissues_shortfall_application_id)
    WHERE reissues_shortfall_application_id IS NOT NULL;
COMMENT ON COLUMN public.customer_credits.reissues_shortfall_application_id IS
    'v5.4.2-27 r2 (Ryan, 2026-11-05). For a credit of origin shortfall_reissue, and only for one: the undo of a shortfall application from a credit since escheated, whose money it carries. Its amount is what the undo gave back, as far as it is left on that credit before it; it draws on that credit and posts no ledger row. Fixed from insert.';

-- The three walks of a reissue line, the drawn-at reading and the credit's
-- position, re-issued from -23 with the shortfall_reissue branch only.
CREATE OR REPLACE FUNCTION public.reissue_generation(p_credit_id uuid) RETURNS integer
    LANGUAGE plpgsql STABLE
    SET search_path = public, pg_temp
    SET enable_seqscan = off
    SET enable_hashjoin = off
    SET enable_mergejoin = off
    AS $$
DECLARE
    v_gen  integer;
    v_more boolean;
BEGIN
    -- v5.4.2-27 (Ryan, 2026-11-05): a shortfall_reissue credit carries
    -- money of the credit its undo gave back to, as a refund_reissue carries
    -- its refund's credit's: the line goes up through either.
    WITH RECURSIVE up(id, origin_type, reissues_refund_id, reissues_shortfall_application_id, gen) AS (
        SELECT c.id, c.origin_type, c.reissues_refund_id, c.reissues_shortfall_application_id, 0 FROM public.customer_credits c WHERE c.id = p_credit_id
        UNION ALL
        SELECT c.id, c.origin_type, c.reissues_refund_id, c.reissues_shortfall_application_id, u.gen + 1
          FROM up u LEFT JOIN public.payments r ON r.id = u.reissues_refund_id
          LEFT JOIN public.shortfall_applications s ON s.id = u.reissues_shortfall_application_id
          JOIN public.customer_credits c ON c.id = coalesce(r.refunds_customer_credit_id, s.customer_credit_id)
         WHERE u.origin_type IN ('refund_reissue', 'shortfall_reissue') AND u.gen <= public.reissue_line_bound()
    )
    SELECT max(u.gen), bool_or(u.gen > public.reissue_line_bound()) INTO v_gen, v_more FROM up u;
    IF v_more THEN
        RAISE EXCEPTION USING
            MESSAGE = format('credit %s: its reissue line is more than %s reissues deep, past what any walk of it reads (Codex B2; v5.4.2-23)', p_credit_id, public.reissue_line_bound()),
            ERRCODE = 'data_exception';
    END IF;
    RETURN v_gen;
END;
$$;
COMMENT ON FUNCTION public.reissue_generation(uuid) IS
    'v5.4.2-23 r7 (Codex B2), r8. A credit''s place in its reissue line: 0 for a credit that reissues no refund, n for the nth reissue. Raises (22000) for a line deeper than reissue_line_bound(). r8 (Fable S1): the plan pinned (sequential scans, hash and merge joins off), as every walk of -23. v5.4.2-27 (Ryan, 2026-11-05): a shortfall_reissue credit is a reissue too, of the credit its undo gave back to.';
REVOKE ALL ON FUNCTION public.reissue_generation(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.reissue_generation(uuid) TO tally_app, tally_core;

CREATE OR REPLACE FUNCTION public.overpayment_root(p_credit_id uuid) RETURNS uuid
    LANGUAGE plpgsql STABLE
    SET search_path = public, pg_temp
    SET enable_seqscan = off
    SET enable_hashjoin = off
    SET enable_mergejoin = off
    AS $$
DECLARE
    v_root uuid;
    v_more boolean;
BEGIN
    -- v5.4.2-27 (Ryan, 2026-11-05): a shortfall_reissue credit carries
    -- money of the credit its undo gave back to, as a refund_reissue carries
    -- its refund's credit's: the line goes up through either.
    WITH RECURSIVE up(id, origin_type, reissues_refund_id, reissues_shortfall_application_id, gen) AS (
        SELECT c.id, c.origin_type, c.reissues_refund_id, c.reissues_shortfall_application_id, 0 FROM public.customer_credits c WHERE c.id = p_credit_id
        UNION ALL
        SELECT c.id, c.origin_type, c.reissues_refund_id, c.reissues_shortfall_application_id, u.gen + 1
          FROM up u LEFT JOIN public.payments r ON r.id = u.reissues_refund_id
          LEFT JOIN public.shortfall_applications s ON s.id = u.reissues_shortfall_application_id
          JOIN public.customer_credits c ON c.id = coalesce(r.refunds_customer_credit_id, s.customer_credit_id)
         WHERE u.origin_type IN ('refund_reissue', 'shortfall_reissue') AND u.gen <= public.reissue_line_bound()
    )
    SELECT (SELECT u.id FROM up u WHERE u.origin_type = 'overpayment'), bool_or(u.gen > public.reissue_line_bound())
      INTO v_root, v_more FROM up u;
    -- r7 (Codex B2): a line deeper than the bound is not read as one that
    -- starts somewhere else.
    IF v_more THEN
        RAISE EXCEPTION USING
            MESSAGE = format('credit %s: its reissue line is more than %s reissues deep, past what any walk of it reads (Codex B2; v5.4.2-23)', p_credit_id, public.reissue_line_bound()),
            ERRCODE = 'data_exception';
    END IF;
    RETURN v_root;
END;
$$;
COMMENT ON FUNCTION public.overpayment_root(uuid) IS
    'v5.4.2-23 r6 (Codex B1), r7, r8. The overpayment credit at the root of a credit''s reissue line: the credit itself if it is an overpayment credit; for a refund_reissue credit, the root of the credit its refund came from; NULL otherwise. r7 (Codex B2): raises (22000) for a line deeper than reissue_line_bound(), never NULL for it. r8 (Fable S1): the plan pinned (sequential scans, hash and merge joins off), as every walk of -23. v5.4.2-27 (Ryan, 2026-11-05): and for a shortfall_reissue credit, the root of the credit its undo gave back to.';
REVOKE ALL ON FUNCTION public.overpayment_root(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.overpayment_root(uuid) TO tally_app, tally_core;

CREATE OR REPLACE FUNCTION public.overpayment_family(p_credit_id uuid)
    RETURNS TABLE (id uuid, created_at timestamp with time zone)
    LANGUAGE plpgsql STABLE
    SET search_path = public, pg_temp
    SET enable_seqscan = off
    SET enable_hashjoin = off
    SET enable_mergejoin = off
    AS $$
DECLARE
    v_ids  uuid[];
    v_more boolean;
BEGIN
    WITH RECURSIVE down(id, gen) AS (
        SELECT c.id, 0 FROM public.customer_credits c WHERE c.id = p_credit_id AND c.origin_type = 'overpayment'
        UNION ALL
        SELECT k.id, d.gen + 1
          -- v5.4.2-27 (Ryan, 2026-11-05): and down through a shortfall
          -- reissue, which carries what an undo gave back to the credit.
          FROM down d CROSS JOIN LATERAL (
               SELECT k.id FROM public.payments r JOIN public.customer_credits k ON k.reissues_refund_id = r.id
                WHERE r.refunds_customer_credit_id = d.id
               UNION ALL
               SELECT k.id FROM public.shortfall_applications s JOIN public.customer_credits k ON k.reissues_shortfall_application_id = s.id
                WHERE s.customer_credit_id = d.id) k
         WHERE d.gen <= public.reissue_line_bound()
    )
    SELECT array_agg(d.id) FILTER (WHERE d.gen <= public.reissue_line_bound()), bool_or(d.gen > public.reissue_line_bound())
      INTO v_ids, v_more FROM down d;
    -- r7 (Codex B2): as overpayment_root.
    IF v_more THEN
        RAISE EXCEPTION USING
            MESSAGE = format('credit %s: its reissue line is more than %s reissues deep, past what any walk of it reads (Codex B2; v5.4.2-23)', p_credit_id, public.reissue_line_bound()),
            ERRCODE = 'data_exception';
    END IF;
    RETURN QUERY SELECT c.id, c.created_at FROM public.customer_credits c WHERE c.id = ANY (v_ids);
END;
$$;
COMMENT ON FUNCTION public.overpayment_family(uuid) IS
    'v5.4.2-23 r6 (Codex B1), r7, r8. An overpayment credit and every refund_reissue credit descended from it (any status), with their recorded instants: the credits that hold its payment''s money. Empty for any other credit. r7 (Codex B2): raises (22000) for a line deeper than reissue_line_bound(). r8 (Fable S1): the plan pinned (sequential scans, hash and merge joins off), as every walk of -23. v5.4.2-27 (Ryan, 2026-11-05): and every shortfall_reissue credit descended from one of them.';
REVOKE ALL ON FUNCTION public.overpayment_family(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.overpayment_family(uuid) TO tally_app, tally_core;

CREATE OR REPLACE FUNCTION public.cash_drawn_at(p_kind text, p_id uuid, p_at timestamp with time zone) RETURNS numeric
    LANGUAGE sql STABLE
    SET search_path = public, pg_temp
    AS $$
    SELECT coalesce(sum(x.amount), 0) FROM (
        SELECT a.amount FROM public.invoice_applications a
         WHERE ((p_kind = 'payment' AND a.payment_id = p_id) OR (p_kind = 'credit' AND a.customer_credit_id = p_id)) AND a.created_at <= p_at
        UNION ALL
        SELECT -r.amount FROM public.payments r
         WHERE ((p_kind = 'payment' AND r.refunds_payment_id = p_id) OR (p_kind = 'credit' AND r.refunds_customer_credit_id = p_id))
           AND r.created_at <= p_at AND (r.status IN ('pending', 'posted') OR r.status_recorded_at > p_at)
        UNION ALL
        SELECT k.original_amount FROM public.customer_credits k JOIN public.payments r ON r.id = k.reissues_refund_id
         WHERE p_kind = 'credit' AND r.refunds_customer_credit_id = p_id AND k.created_at <= p_at
           AND (k.status <> 'voided' OR k.status_recorded_at > p_at)
        UNION ALL
        SELECT l.amount FROM public.account_ledger d
          CROSS JOIN LATERAL unnest(public.ledger_tree_ids(d.id) || d.id) AS t(id)
          JOIN public.account_ledger l ON l.id = t.id
         WHERE p_kind = 'credit' AND d.transaction_type = 'donation' AND d.reference_type = 'customer_credit' AND d.reference_id = p_id
           AND l.created_at <= p_at
        UNION ALL
        SELECT e.amount_related FROM public.escheatment_events e
         WHERE p_kind = 'credit' AND e.event_type = 'escheated_to_state' AND e.customer_credit_id = p_id AND e.created_at <= p_at
        -- v5.4.2-27: its money applied to a bounced payment's shortfall (an
        -- undo negative); for a payment that bounced, what was repaid to it
        -- (negative); and for a credit, what an undo gave back to it that was
        -- carried into a shortfall_reissue credit (Ryan, 2026-11-05), as
        -- cash_source_draws reads them. r3 (Codex S1): the first two read 0
        -- at every instant overpayment_shares asks (a take-back's): a
        -- take-back waits while the source's shortfall applications net to
        -- more than 0 (R15), and a payment is repaid only after it ended,
        -- when nothing more is taken back under its entry. They are kept so
        -- this lists what cash_source_draws lists; no test can observe them.
        UNION ALL
        SELECT s.amount FROM public.shortfall_applications s
         WHERE ((p_kind = 'payment' AND s.payment_id = p_id) OR (p_kind = 'credit' AND s.customer_credit_id = p_id)) AND s.created_at <= p_at
        UNION ALL
        SELECT -s.amount FROM public.shortfall_applications s
         WHERE p_kind = 'payment' AND s.target_payment_id = p_id AND s.created_at <= p_at
        UNION ALL
        SELECT k.original_amount FROM public.customer_credits k JOIN public.shortfall_applications s ON s.id = k.reissues_shortfall_application_id
         WHERE p_kind = 'credit' AND s.customer_credit_id = p_id AND k.created_at <= p_at
           AND (k.status <> 'voided' OR k.status_recorded_at > p_at)) x
$$;
COMMENT ON FUNCTION public.cash_drawn_at(text, uuid, timestamp with time zone) IS
    'v5.4.2-23 r5. What a payment (p_kind payment) or a customer credit (p_kind credit) had given at a recorded instant, by the statuses its rows had then: applications (net of undos), refunds pending or posted, and for a credit its refund_reissue credits not voided, its donation rows net of their undos and its escheated_to_state events; v5.4.2-27: its shortfall applications (an undo negative), for a payment what was repaid to it (negative), and for a credit its shortfall_reissue credits not voided; all dates. A payment''s overpayment credits are not counted (overpayment_split reads them).';
REVOKE ALL ON FUNCTION public.cash_drawn_at(text, uuid, timestamp with time zone) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.cash_drawn_at(text, uuid, timestamp with time zone) TO tally_app, tally_core;

CREATE OR REPLACE FUNCTION public.customer_credit_position_as_of(p_credit_id uuid, p_on date, p_recorded_at timestamp with time zone)
    RETURNS TABLE (amount numeric, issued numeric, applied numeric, refunded numeric, given_up numeric, carried numeric, remaining numeric)
    LANGUAGE plpgsql STABLE
    SET search_path = public, pg_temp
    AS $$
BEGIN
    PERFORM public.cash_coordinates_required('customer_credit_position_as_of', p_on, p_recorded_at);
    -- r3: issued is what of the credit stands on the ledger (its credit_issued
    -- entry less what was withdrawn under it); an overpayment credit's money
    -- is its payment's and posts no row, so it is the credit's amount. A
    -- donation is given up net of its undo (Codex B5).
    RETURN QUERY
    SELECT c.original_amount, x.issued, d.applied, d.refunded, d.given_up, d.carried, x.issued - d.applied - d.refunded - d.given_up - d.carried
      FROM public.customer_credits c
      CROSS JOIN LATERAL public.customer_credit_draws_as_of(c.id, p_on, p_recorded_at) d
      CROSS JOIN LATERAL (SELECT public.overpayment_root(c.id) AS root) o
      CROSS JOIN LATERAL (SELECT
            -- r5 (K-10): an overpayment credit's is its amount less what it
            -- absorbed of what was taken back under its payment's posting
            -- entry; r6 (Codex B1): so is a reissue's descended from one,
            -- and (Opus B1, Codex B2) with a shortfall placed at this reading
            -- (overpayment_absorbed_as_of). Any other reissue: its amount.
            CASE WHEN o.root IS NOT NULL THEN c.original_amount - coalesce((
                     SELECT s.absorbed FROM public.overpayment_absorbed_as_of(o.root, p_on, p_recorded_at) s WHERE s.credit_id = c.id), 0)
                 -- v5.4.2-27: and a shortfall reissue (Ryan, 2026-11-05).
                 WHEN c.origin_type IN ('refund_reissue', 'shortfall_reissue') THEN c.original_amount
                 ELSE coalesce((SELECT -sum(l.amount) FROM public.account_ledger e
                                  CROSS JOIN LATERAL unnest(public.ledger_tree_ids(e.id) || e.id) AS t(id)
                                  JOIN public.account_ledger l ON l.id = t.id
                                 WHERE e.reference_type = 'customer_credit' AND e.transaction_type = 'credit_issued' AND e.reference_id = c.id
                                   AND l.transaction_date <= p_on AND l.created_at <= p_recorded_at), 0) END AS issued) x
     WHERE c.id = p_credit_id AND c.issued_date <= p_on AND c.created_at <= p_recorded_at;
END;
$$;
COMMENT ON FUNCTION public.customer_credit_position_as_of(uuid, date, timestamp with time zone) IS
    'v5.4.2-23 (M1; replaces customer_credits.applied_amount / remaining_amount), r3. A credit at a money date and a recorded instant: its amount; issued (r3: what of it stands on the ledger, its credit_issued entry less what was withdrawn under it; an overpayment credit''s amount, its money being its payment''s); applied (net of its applications); refunded (its refunds pending or posted at the instant, by status_recorded_at); given_up (its donation ledger rows net of their undos, r3, and its escheated_to_state events, by their UTC day); carried (r4: its refunds that came back, carried into refund_reissue credits not voided at the instant); remaining = issued less the four. r5, r6: an overpayment credit''s issued, and a refund_reissue credit''s descended from one, is its amount less its share of what was taken back under the payment''s posting entry, with a shortfall placed at this reading (overpayment_absorbed_as_of); any other refund_reissue credit''s is its amount. No row before the credit exists at the coordinates. NULL or infinite coordinates raise. Fixed once the instant is older than every open transaction (-22''s model). v5.4.2-27 (Ryan, 2026-11-05): a shortfall_reissue credit''s issued is as a refund_reissue''s.';
REVOKE ALL ON FUNCTION public.customer_credit_position_as_of(uuid, date, timestamp with time zone) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.customer_credit_position_as_of(uuid, date, timestamp with time zone) TO tally_app, tally_core;

-- ----------------------------------------------------------------------------
-- 2. The readers: the source counts it in applied, the target in repaid
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.cash_source_draws(p_kind text, p_id uuid)
    RETURNS TABLE (id uuid, on_date date, amount numeric, created_at timestamp with time zone)
    LANGUAGE sql STABLE
    SET search_path = public, pg_temp
    SET enable_seqscan = off
    SET enable_hashjoin = off
    SET enable_mergejoin = off
    AS $$
    SELECT a.id, a.applied_on, a.amount, a.created_at FROM public.invoice_applications a
     WHERE (p_kind = 'payment' AND a.payment_id = p_id) OR (p_kind = 'credit' AND a.customer_credit_id = p_id)
    UNION ALL
    SELECT c.id, c.issued_date, c.original_amount, c.created_at FROM public.customer_credits c
     WHERE p_kind = 'payment' AND c.source_payment_id = p_id AND c.status <> 'voided'
    UNION ALL
    SELECT r.id, r.payment_date, -r.amount, r.created_at FROM public.payments r
     WHERE r.status IN ('pending', 'posted')
       AND ((p_kind = 'payment' AND r.refunds_payment_id = p_id) OR (p_kind = 'credit' AND r.refunds_customer_credit_id = p_id))
    UNION ALL
    -- r4 (Ryan, 2026-10-21): a refund_reissue credit carrying a refund of the
    -- credit that came back, unless voided.
    SELECT c.id, c.issued_date, c.original_amount, c.created_at FROM public.customer_credits c
      JOIN public.payments r ON r.id = c.reissues_refund_id
     WHERE p_kind = 'credit' AND r.refunds_customer_credit_id = p_id AND c.status <> 'voided'
    UNION ALL
    -- v5.4.2-27 r2 (Ryan, 2026-11-05): a shortfall_reissue credit carrying
    -- what an undo gave back to the credit after its escheat.
    SELECT c.id, c.issued_date, c.original_amount, c.created_at FROM public.customer_credits c
      JOIN public.shortfall_applications s ON s.id = c.reissues_shortfall_application_id
     WHERE p_kind = 'credit' AND s.customer_credit_id = p_id AND c.status <> 'voided'
    UNION ALL
    -- r3 (Codex B5): a donation and every row under it (its undo gives the
    -- money back to the credit).
    SELECT l.id, l.transaction_date, l.amount, l.created_at FROM public.account_ledger d
      CROSS JOIN LATERAL unnest(public.ledger_tree_ids(d.id) || d.id) AS t(id)
      JOIN public.account_ledger l ON l.id = t.id
     WHERE p_kind = 'credit' AND d.transaction_type = 'donation' AND d.reference_type = 'customer_credit' AND d.reference_id = p_id
    UNION ALL
    SELECT e.id, (e.event_date AT TIME ZONE 'UTC')::date, e.amount_related, e.created_at FROM public.escheatment_events e
     WHERE p_kind = 'credit' AND e.event_type = 'escheated_to_state' AND e.customer_credit_id = p_id
    UNION ALL
    -- v5.4.2-27 (AC-44, R23, R24): a source's money applied to a bounced
    -- payment's shortfall (an undo negative), and on that payment, what was
    -- repaid to it (a repayment gives it money: negative).
    SELECT s.id, s.applied_on, s.amount, s.created_at FROM public.shortfall_applications s
     WHERE (p_kind = 'payment' AND s.payment_id = p_id) OR (p_kind = 'credit' AND s.customer_credit_id = p_id)
    UNION ALL
    SELECT s.id, s.applied_on, -s.amount, s.created_at FROM public.shortfall_applications s
     WHERE p_kind = 'payment' AND s.target_payment_id = p_id
$$;
COMMENT ON FUNCTION public.cash_source_draws(text, uuid) IS
    'v5.4.2-23 (A3), r3. Every row drawing on a payment (p_kind payment) or a customer credit (p_kind credit), live: its applications (an undo negative); a payment''s credits (a credit names a payment only as an overpayment credit) unless voided; its refunds while pending or posted; a credit''s refund_reissue credits not voided (r4), its donation ledger rows and every row under them (r3: an undone donation gives the money back), and its escheated_to_state events (dated by their UTC day); v5.4.2-27: its money applied to a bounced payment''s shortfall (shortfall_applications, an undo negative), and for a payment that bounced, what was repaid to it (negative); r2, a credit''s shortfall_reissue credits not voided. Each with its money date and recorded instant. The cap reads this set with what was taken back under the source''s arrival entry (check_cash_source). r8 (Fable S1): the plan pinned, as every walk of -23: the pool cap reads it once per credit of a family.';
REVOKE ALL ON FUNCTION public.cash_source_draws(text, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.cash_source_draws(text, uuid) TO tally_app, tally_core;

DROP FUNCTION public.payment_draws_as_of(uuid, date, timestamp with time zone);
CREATE OR REPLACE FUNCTION public.payment_draws_as_of(p_payment_id uuid, p_on date, p_recorded_at timestamp with time zone)
    RETURNS TABLE (received numeric, applied numeric, refunded numeric, repaid numeric)
    LANGUAGE sql STABLE
    SET search_path = public, pg_temp
    AS $$
    SELECT
        -- r3 (Fable S7; Kyle, K-10): received is what of the payment stands
        -- on the ledger at the coordinates: its posting entry less what was
        -- taken back under it (a bounce, a reversal). r5 (Codex S3): it
        -- reads the posting row, whatever the status: a payment is posted by
        -- writing the row and the move together, so a pending payment has
        -- none (a history load that writes the row first reads it while the
        -- payment is still pending).
        coalesce((SELECT -sum(l.amount) FROM public.account_ledger e
                    CROSS JOIN LATERAL unnest(public.ledger_tree_ids(e.id) || e.id) AS t(id)
                    JOIN public.account_ledger l ON l.id = t.id
                   WHERE e.reference_type = 'payment' AND e.transaction_type IN ('payment', 'deposit', 'refund') AND e.reference_id = p_payment_id
                     AND l.transaction_date <= p_on AND l.created_at <= p_recorded_at), 0),
        coalesce((SELECT sum(a.amount) FROM public.invoice_applications a
                   WHERE a.payment_id = p_payment_id AND a.applied_on <= p_on AND a.created_at <= p_recorded_at), 0)
        -- v5.4.2-27: and to a bounced payment's shortfall (an application of
        -- the payment's money that names no bill).
      + coalesce((SELECT sum(s.amount) FROM public.shortfall_applications s
                   WHERE s.payment_id = p_payment_id AND s.applied_on <= p_on AND s.created_at <= p_recorded_at), 0),
        coalesce((SELECT -sum(r.amount) FROM public.payments r
                   WHERE r.refunds_payment_id = p_payment_id AND r.payment_date <= p_on AND r.created_at <= p_recorded_at
                     AND (r.status IN ('pending', 'posted') OR r.status_recorded_at > p_recorded_at)), 0),
        -- v5.4.2-27: for a payment that bounced, what the customer's other
        -- money repaid of what it left owed (net of undos).
        -- r3 (Fable N6): nothing repaid prints 0.00, as every amount.
        coalesce((SELECT sum(s.amount) FROM public.shortfall_applications s
                   WHERE s.target_payment_id = p_payment_id AND s.applied_on <= p_on AND s.created_at <= p_recorded_at), 0.00)
$$;
COMMENT ON FUNCTION public.payment_draws_as_of(uuid, date, timestamp with time zone) IS
    'v5.4.2-23 r6. A payment at a money date and a recorded instant, before its overpayment credit: received (its posting entry less what was taken back under it), applied (net of undos; v5.4.2-27: to bill lines and to bounced payments'' shortfalls), refunded (its refunds pending or posted at the instant), repaid (v5.4.2-27: for a payment that bounced, what was applied to its shortfall, net of undos). Read by payment_position_as_of and overpayment_absorbed_as_of. No coordinate checks: the callers make them.';
REVOKE ALL ON FUNCTION public.payment_draws_as_of(uuid, date, timestamp with time zone) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.payment_draws_as_of(uuid, date, timestamp with time zone) TO tally_app, tally_core;

CREATE OR REPLACE FUNCTION public.customer_credit_draws_as_of(p_credit_id uuid, p_on date, p_recorded_at timestamp with time zone)
    RETURNS TABLE (applied numeric, refunded numeric, given_up numeric, carried numeric)
    LANGUAGE sql STABLE
    SET search_path = public, pg_temp
    AS $$
    SELECT
        coalesce((SELECT sum(a.amount) FROM public.invoice_applications a
                   WHERE a.customer_credit_id = p_credit_id AND a.applied_on <= p_on AND a.created_at <= p_recorded_at), 0)
        -- v5.4.2-27: and to a bounced payment's shortfall.
      + coalesce((SELECT sum(s.amount) FROM public.shortfall_applications s
                   WHERE s.customer_credit_id = p_credit_id AND s.applied_on <= p_on AND s.created_at <= p_recorded_at), 0),
        coalesce((SELECT -sum(r.amount) FROM public.payments r
                   WHERE r.refunds_customer_credit_id = p_credit_id AND r.payment_date <= p_on AND r.created_at <= p_recorded_at
                     AND (r.status IN ('pending', 'posted') OR r.status_recorded_at > p_recorded_at)), 0),
        -- A donation is given up net of its undo (Codex B5).
        coalesce((SELECT sum(l.amount) FROM public.account_ledger d
                    CROSS JOIN LATERAL unnest(public.ledger_tree_ids(d.id) || d.id) AS t(id)
                    JOIN public.account_ledger l ON l.id = t.id
                   WHERE d.transaction_type = 'donation' AND d.reference_type = 'customer_credit' AND d.reference_id = p_credit_id
                     AND l.transaction_date <= p_on AND l.created_at <= p_recorded_at), 0)
      + coalesce((SELECT sum(e.amount_related) FROM public.escheatment_events e
                   WHERE e.event_type = 'escheated_to_state' AND e.customer_credit_id = p_credit_id
                     AND (e.event_date AT TIME ZONE 'UTC')::date <= p_on AND e.created_at <= p_recorded_at), 0),
        -- r4 (Ryan, 2026-10-21): carried into refund_reissue credits.
        coalesce((SELECT sum(k.original_amount) FROM public.customer_credits k JOIN public.payments r ON r.id = k.reissues_refund_id
                   WHERE r.refunds_customer_credit_id = p_credit_id AND k.issued_date <= p_on AND k.created_at <= p_recorded_at
                     AND (k.status <> 'voided' OR k.status_recorded_at > p_recorded_at)), 0)
        -- v5.4.2-27 r2 (Ryan, 2026-11-05): and into shortfall_reissue credits.
      + coalesce((SELECT sum(k.original_amount) FROM public.customer_credits k JOIN public.shortfall_applications s ON s.id = k.reissues_shortfall_application_id
                   WHERE s.customer_credit_id = p_credit_id AND k.issued_date <= p_on AND k.created_at <= p_recorded_at
                     AND (k.status <> 'voided' OR k.status_recorded_at > p_recorded_at)), 0)
$$;
COMMENT ON FUNCTION public.customer_credit_draws_as_of(uuid, date, timestamp with time zone) IS
    'v5.4.2-23 r6. What a credit gave at a money date and a recorded instant: applied (net of undos; v5.4.2-27: to bill lines and to bounced payments'' shortfalls), refunded (its refunds pending or posted at the instant), given_up (its donation rows net of their undos, and its escheated_to_state events by their UTC day), carried (into refund_reissue credits not voided at the instant; v5.4.2-27 r2, and shortfall_reissue credits). Read by customer_credit_position_as_of and overpayment_absorbed_as_of. No coordinate checks: the callers make them.';
REVOKE ALL ON FUNCTION public.customer_credit_draws_as_of(uuid, date, timestamp with time zone) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.customer_credit_draws_as_of(uuid, date, timestamp with time zone) TO tally_app, tally_core;

CREATE OR REPLACE FUNCTION public.overpayment_absorbed_as_of(p_credit_id uuid, p_on date, p_recorded_at timestamp with time zone, p_cover boolean DEFAULT true)
    RETURNS TABLE (credit_id uuid, absorbed numeric)
    LANGUAGE plpgsql STABLE
    SET search_path = public, pg_temp
    AS $$
DECLARE
    k       public.customer_credits%ROWTYPE;
    v_p     numeric;
    v_f     numeric;
    v_x     numeric;
    v_d     numeric;
    v_ids   uuid[];
    v_abs   numeric[];
    v_own   numeric[];
    i       integer;
    j       integer;
BEGIN
    SELECT * INTO k FROM public.customer_credits c
     WHERE c.id = p_credit_id AND c.origin_type = 'overpayment'
       AND c.issued_date <= p_on AND c.created_at <= p_recorded_at
       AND (c.status <> 'voided' OR c.status_recorded_at > p_recorded_at);
    IF NOT FOUND THEN
        RETURN;
    END IF;
    -- The family at the coordinates, the overpayment credit first: each with
    -- its share as recorded, and what it holds after it. r7: the shares read
    -- once, not once per credit.
    WITH s AS MATERIALIZED (
        SELECT x.credit_id, sum(x.absorbed) AS absorbed FROM public.overpayment_shares(k.id) x
         WHERE x.on_date <= p_on AND x.created_at <= p_recorded_at GROUP BY x.credit_id)
    SELECT array_agg(c.id ORDER BY c.id <> k.id, c.created_at, c.id),
           array_agg(coalesce(s.absorbed, 0) ORDER BY c.id <> k.id, c.created_at, c.id),
           array_agg(c.original_amount - coalesce(s.absorbed, 0) - d.applied - d.refunded - d.given_up - d.carried ORDER BY c.id <> k.id, c.created_at, c.id)
      INTO v_ids, v_abs, v_own
      FROM public.overpayment_family(k.id) f
      JOIN public.customer_credits c ON c.id = f.id
      CROSS JOIN LATERAL public.customer_credit_draws_as_of(c.id, p_on, p_recorded_at) d
      LEFT JOIN s ON s.credit_id = c.id
     WHERE c.issued_date <= p_on AND c.created_at <= p_recorded_at
       AND (c.status <> 'voided' OR c.status_recorded_at > p_recorded_at);
    IF p_cover THEN
        -- r7 (Fable B1, Opus B2, Codex B1): first within the family. A credit
        -- in deficit (the overpayment credit first, then each reissue in
        -- recorded order) is covered by the others holding money, the latest
        -- first, as a give-back restores the latest share first. After it,
        -- the family's credits all read money or all a deficit, and the
        -- cover with the payment below settles the rest.
        FOR i IN 1 .. cardinality(v_ids) LOOP
            CONTINUE WHEN v_own[i] >= 0;
            FOR j IN REVERSE cardinality(v_ids) .. 1 LOOP
                EXIT WHEN v_own[i] >= 0;
                CONTINUE WHEN j = i OR v_own[j] <= 0;
                v_d := least(-v_own[i], v_own[j]);
                v_abs[i] := v_abs[i] - v_d;
                v_own[i] := v_own[i] + v_d;
                v_abs[j] := v_abs[j] + v_d;
                v_own[j] := v_own[j] - v_d;
            END LOOP;
        END LOOP;
        -- The payment's own part, with the shares as recorded. v5.4.2-27:
        -- what was repaid to a payment that bounced is on its own part, and
        -- covers a deficit on the credits as any money of the payment does.
        SELECT d.received - d.applied - d.refunded + d.repaid - (k.original_amount - (SELECT sum(x) FROM unnest(v_abs) x)) INTO v_p
          FROM public.payment_draws_as_of(k.source_payment_id, p_on, p_recorded_at) d;
        SELECT sum(x) INTO v_f FROM unnest(v_own) x;
        IF v_f < 0 AND v_p > 0 THEN
            v_x := least(-v_f, v_p);
            FOR i IN 1 .. cardinality(v_ids) LOOP
                v_d := least(v_x, greatest(-v_own[i], 0));
                v_abs[i] := v_abs[i] - v_d;
                v_x := v_x - v_d;
            END LOOP;
        ELSIF v_p < 0 AND v_f > 0 THEN
            v_x := least(-v_p, v_f);
            FOR i IN 1 .. cardinality(v_ids) LOOP
                v_d := least(v_x, greatest(v_own[i], 0));
                v_abs[i] := v_abs[i] + v_d;
                v_x := v_x - v_d;
            END LOOP;
        END IF;
    END IF;
    RETURN QUERY SELECT u.id, u.a FROM unnest(v_ids, v_abs) AS u(id, a);
END;
$$;
COMMENT ON FUNCTION public.overpayment_absorbed_as_of(uuid, date, timestamp with time zone, boolean) IS
    'v5.4.2-23 r6 (Opus B1, Codex B1, B2; K-10). For an overpayment credit at a money date and a recorded instant: what each credit of its family (the credit and its refund_reissue descendants, overpayment_family) absorbed of what was taken back under its payment''s posting entry. Starts from the shares as recorded (overpayment_shares); if the payment''s own part then reads a deficit while the credits hold money, or the credits a deficit while the payment holds money, the side holding money covers the other as far as it can (a credit in deficit, or the credit drawn on to cover the payment, the overpayment credit first). r7: a credit in deficit is covered first by the family''s other credits holding money, the latest first, then by the payment. v5.4.2-27: what was repaid to the payment after a bounce (its shortfall applications) is on the payment''s own part. Read by both positions; with p_cover false, the shares as recorded. Empty for any other credit, or before the credit exists at the coordinates.';
REVOKE ALL ON FUNCTION public.overpayment_absorbed_as_of(uuid, date, timestamp with time zone, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.overpayment_absorbed_as_of(uuid, date, timestamp with time zone, boolean) TO tally_app, tally_core;

DROP FUNCTION public.payment_position_as_of(uuid, date, timestamp with time zone);
CREATE OR REPLACE FUNCTION public.payment_position_as_of(p_payment_id uuid, p_on date, p_recorded_at timestamp with time zone)
    RETURNS TABLE (amount numeric, received numeric, applied numeric, credited numeric, refunded numeric, remaining numeric, repaid numeric)
    LANGUAGE plpgsql STABLE
    SET search_path = public, pg_temp
    AS $$
BEGIN
    PERFORM public.cash_coordinates_required('payment_position_as_of', p_on, p_recorded_at);
    -- received, applied and refunded: payment_draws_as_of. A bounced payment
    -- has received nothing, and if it was refunded first, remaining is
    -- negative: the customer owes what was paid out (Kyle's example).
    -- v5.4.2-27: repaid, what the customer's other money paid of that
    -- (shortfall_applications), brings remaining back toward 0; applied
    -- counts this payment's own money applied to another's shortfall.
    RETURN QUERY
    SELECT p.amount, d.received, d.applied, x.credited, d.refunded, d.received - d.applied - x.credited - d.refunded + d.repaid, d.repaid
      FROM public.payments p
      CROSS JOIN LATERAL public.payment_draws_as_of(p.id, p_on, p_recorded_at) d
      CROSS JOIN LATERAL (SELECT
            -- r5 (K-10): less what the overpayment credit absorbed of what
            -- was taken back (one live credit per payment); r6: its family's
            -- share, with a shortfall placed at this reading
            -- (overpayment_absorbed_as_of).
            coalesce((SELECT sum(c.original_amount - coalesce((
                                SELECT sum(s.absorbed) FROM public.overpayment_absorbed_as_of(c.id, p_on, p_recorded_at) s), 0))
                        FROM public.customer_credits c
                       WHERE c.source_payment_id = p.id AND c.issued_date <= p_on AND c.created_at <= p_recorded_at
                         AND (c.status <> 'voided' OR c.status_recorded_at > p_recorded_at)), 0) AS credited) x
     WHERE p.id = p_payment_id AND p.payment_date <= p_on AND p.created_at <= p_recorded_at;
END;
$$;
COMMENT ON FUNCTION public.payment_position_as_of(uuid, date, timestamp with time zone) IS
    'v5.4.2-23 (M1; replaces payments.applied_amount / unapplied_amount), r3. A payment at a money date and a recorded instant: its amount; received (r3: what of it stands on the ledger, its posting entry less what was taken back under it, at the coordinates, read from the posting row whatever the status, r5); applied (net of its applications, undos included); credited (its credits not voided at the instant; r5: less what each absorbed of what was taken back under its posting entry; r6: the family''s share, with a shortfall placed at this reading, overpayment_absorbed_as_of); refunded (its refunds pending or posted at the instant, by status_recorded_at); remaining = received less the three, plus repaid (negative when it was refunded and then came back: the customer owes it, K-10). v5.4.2-27: applied counts the payment''s money applied to another payment''s shortfall; repaid (a new last column) is what was applied to this payment''s shortfall after it bounced, net of undos. No row before the payment exists at the coordinates. NULL or infinite coordinates raise. Fixed once the instant is older than every open transaction (-22''s model).';
REVOKE ALL ON FUNCTION public.payment_position_as_of(uuid, date, timestamp with time zone) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.payment_position_as_of(uuid, date, timestamp with time zone) TO tally_app, tally_core;

-- ----------------------------------------------------------------------------
-- 3. The target's cap: a payment that has ended holds no money
-- ----------------------------------------------------------------------------
-- From a date on (p_from), a payment that bounced and its overpayment
-- family together never hold money (outside R5's interval, r3): what they
-- gave (the payment's draws, its family credits' draws outside the family)
-- and what
-- was taken back under its posting entry come to at least the payment, less
-- what was repaid (a negative draw on it, cash_source_draws). The same sum
-- as check_cash_source's cap on a payment and its credits together, read the
-- other way. Called by a repayment, and by every move that gives the family
-- money back afterwards (Ryan, 2026-11-05, option 1): the caller holds the
-- payment's lock, which every writer on the family takes. A repayment is
-- checked from its own date on (-23's rule: a row changes nothing before
-- it), every row at its own date. A move giving money back (NULL p_from)
-- is checked from the target's first repayment's date on: a refund that
-- leaves stops counting at every date (-23 reads it by status), so every
-- repayment since may now be past what is owed. r2 (Codex B1, Opus B1): r1
-- read from the latest row's date, and a later repayment hid an earlier
-- one. There an undo counts from the date of the row it undoes: it
-- corrects that row, and the operator's undo, dated when it is recorded
-- (the repayment's period may be closed), settles it from its own date
-- (residual R5: the positions read the undo at its own date). r3 (Opus B1):
-- and from today on, every row at its own date: an undo dated after today
-- would leave the money on the payment until then, so R5's interval stays
-- in the past.
CREATE OR REPLACE FUNCTION public.check_shortfall_repaid(p_payment_id uuid, p_from date) RETURNS void
    LANGUAGE plpgsql STABLE
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_first  date;
    v_today  date;
    v_from   date;
    v_retro  boolean;
    v_pass   integer;
    v_on     date;
    v_used   numeric;
    v_amount numeric;
BEGIN
    IF p_payment_id IS NULL THEN
        RETURN;
    END IF;
    SELECT min(s.applied_on) INTO v_first FROM public.shortfall_applications s WHERE s.target_payment_id = p_payment_id AND s.basis <> 'undo';
    IF v_first IS NULL THEN
        RETURN;
    END IF;
    -- r3 (Opus B1): today is the latest date anywhere (UTC+14), as -22's
    -- close reads a period's end at UTC-12: an undo the utility dates today
    -- in its own zone is never later than it.
    v_today := (pg_catalog.now() AT TIME ZONE 'Etc/GMT-14')::date;
    -- A repayment (p_from given): one reading, from its own date, every row
    -- at its own date. A move giving money back (NULL): two. First from the
    -- first repayment's date, an undo at the date of the row it undoes (r2);
    -- then (r3) from today on, every row at its own date, so an undo dated
    -- after today does not settle it: the positions would read the ended
    -- payment holding the money until the undo's date, and an undo is never
    -- undone. R5's interval stays before today.
    FOR v_pass IN 1 .. CASE WHEN p_from IS NULL THEN 2 ELSE 1 END LOOP
        v_retro := p_from IS NULL AND v_pass = 1;
        v_from := CASE WHEN p_from IS NOT NULL THEN p_from WHEN v_pass = 1 THEN v_first ELSE v_today END;
        SELECT x.on_date, x.used, pp.amount INTO v_on, v_used, v_amount
          FROM public.payments pp
          CROSS JOIN LATERAL (
               SELECT u.on_date, sum(u.amount) OVER (ORDER BY u.on_date) AS used
                 FROM (SELECT d.on_date, d.amount FROM public.cash_source_draws('payment', pp.id) d
                        WHERE d.id NOT IN (SELECT c.id FROM public.customer_credits c WHERE c.source_payment_id = pp.id)
                          AND d.id NOT IN (SELECT s.id FROM public.shortfall_applications s WHERE s.target_payment_id = pp.id)
                       UNION ALL
                       -- What was repaid to it (a negative draw); in the
                       -- first reading of a move giving money back, an undo
                       -- from its row's date (r2).
                       SELECT CASE WHEN v_retro THEN coalesce(u.applied_on, s.applied_on) ELSE s.applied_on END, -s.amount
                         FROM public.shortfall_applications s LEFT JOIN public.shortfall_applications u ON u.id = s.undoes_shortfall_application_id
                        WHERE s.target_payment_id = pp.id
                       UNION ALL
                       SELECT d.on_date, d.amount FROM public.customer_credits k
                         CROSS JOIN LATERAL public.overpayment_family(k.id) f
                         JOIN public.customer_credits c ON c.id = f.id
                         CROSS JOIN LATERAL public.cash_source_draws('credit', c.id) d
                        WHERE k.source_payment_id = pp.id AND k.status <> 'voided' AND c.status <> 'voided'
                          AND d.id NOT IN (SELECT g.id FROM public.overpayment_family(k.id) g)
                       UNION ALL
                       SELECT l.transaction_date, l.amount FROM public.account_ledger l
                        WHERE l.id = ANY (public.ledger_tree_ids(public.cash_arrival_entry('payment', pp.id)))
                       UNION ALL
                       SELECT '-infinity'::date, pp.amount
                       UNION ALL
                       SELECT l.transaction_date, l.amount FROM public.account_ledger l
                        WHERE l.id = public.cash_arrival_entry('payment', pp.id)
                       UNION ALL
                       -- r3: the reading's first date is read too, though no
                       -- row is dated on it (today, with an undo dated later).
                       SELECT v_from, 0) u) x
         WHERE pp.id = p_payment_id AND x.used < pp.amount AND x.on_date >= v_from
         ORDER BY x.on_date LIMIT 1;
        IF FOUND THEN
            RAISE EXCEPTION USING
                MESSAGE = format('payment %s: on %s what was applied to its shortfall would leave it and its overpayment credits holding %s, and a payment that has ended holds no money — undo the shortfall application first, in the same transaction%s (Ryan, 2026-11-05; AC-44, v5.4.2-27)', p_payment_id, v_on, v_amount - v_used,
                                 CASE WHEN p_from IS NULL AND v_pass = 2 THEN format(', dated no later than today (%s): an undo dated after it leaves the money on the payment until then', v_today) ELSE '' END),
                ERRCODE = 'check_violation';
        END IF;
    END LOOP;
END;
$$;
COMMENT ON FUNCTION public.check_shortfall_repaid(uuid, date) IS
    'v5.4.2-27 (AC-44; Ryan, 2026-11-05, option 1). For a payment with shortfall applications naming it: refuses (23514) any date from p_from on (a repayment passes its own date, every row read at its own date; r2, NULL, for a move giving money back: from its first repayment''s date, an undo read from the date of the row it undoes; r3, Opus B1: and also from today, the latest date anywhere, every row at its own date, so an undo dated after today does not settle it) at which it and its overpayment family would hold money, that is, at which what they gave and what was taken back under its posting entry, less what was repaid, come to less than the payment. Returns at once for NULL or a payment nothing was repaid to. Called by enforce_shortfall_application, by check_cash_source after an undo, and by enforce_shortfall_source_moves when a refund of the family leaves. The caller holds the payment''s lock.';
REVOKE ALL ON FUNCTION public.check_shortfall_repaid(uuid, date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.check_shortfall_repaid(uuid, date) TO tally_app;

-- ----------------------------------------------------------------------------
-- 4. The source: check_cash_source, with the two new purposes
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.check_cash_source(p_kind text, p_id uuid, p_row_created_at timestamp with time zone, p_purpose text, p_on date)
    RETURNS void
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_amount   numeric;
    v_date     date;
    v_status   text;
    v_deposit  boolean := false;
    v_origin   text;
    v_src_pay  uuid;
    v_src_at   timestamptz;
    v_entry    uuid;
    v_ok       boolean;
    v_on       date;
    v_drawn    numeric;
    v_split    uuid;
    v_pool_pay uuid;
    v_family   boolean;
BEGIN
    IF pg_catalog.current_setting('transaction_isolation') <> 'read committed' THEN
        RAISE EXCEPTION USING
            MESSAGE = format('a row drawing on %s %s is written at READ COMMITTED (this transaction is %s): its cap must see every row committed while it waited (R-06, v5.4.2-23)', p_kind, p_id, pg_catalog.current_setting('transaction_isolation')),
            ERRCODE = 'invalid_transaction_state';
    END IF;
    -- r5: an overpayment credit's money is its payment's, and the cap below
    -- holds the two together: a draw on the credit takes the payment's lock
    -- first (payment, then credit, as everywhere), so a draw on either sees
    -- the other's. source_payment_id is fixed from insert. r6 (Codex B1): so
    -- does a draw on a reissue descended from it (overpayment_root; the
    -- line is fixed from insert too).
    IF p_kind = 'credit' THEN
        SELECT c.source_payment_id INTO v_pool_pay FROM public.customer_credits c WHERE c.id = public.overpayment_root(p_id);
        IF v_pool_pay IS NOT NULL THEN
            PERFORM pg_catalog.pg_advisory_xact_lock(public.cash_source_lock_key('payment', v_pool_pay));
        END IF;
    END IF;
    PERFORM pg_catalog.pg_advisory_xact_lock(public.cash_source_lock_key(p_kind, p_id));
    -- r3 (Fable S4): the source is drawable from when its money reached the
    -- ledger: a payment from its move to posted, a credit from its
    -- credit_issued entry (or its own insert, for an overpayment credit).
    IF p_kind = 'payment' THEN
        SELECT p.amount, p.payment_date, p.status, p.is_deposit, greatest(p.created_at, p.status_recorded_at)
          INTO v_amount, v_date, v_status, v_deposit, v_src_at FROM public.payments p WHERE p.id = p_id;
    ELSE
        SELECT c.original_amount, c.issued_date, c.status, c.origin_type, c.source_payment_id, c.created_at
          INTO v_amount, v_date, v_status, v_origin, v_src_pay, v_src_at FROM public.customer_credits c WHERE c.id = p_id;
    END IF;
    -- Fail closed (Fable S5): a source this session cannot see is not one it
    -- may draw on.
    IF NOT FOUND THEN
        RAISE EXCEPTION USING
            MESSAGE = format('a row drawing on %s %s: no such %s is visible (R-06, v5.4.2-23)', p_kind, p_id, p_kind),
            ERRCODE = 'foreign_key_violation';
    END IF;
    -- Which source may give money for what. An undo gives money back, so it
    -- needs only a source not yet ended (Opus B3: an undo on an ended source
    -- would leave it ended with money on it).
    v_ok := CASE p_purpose
        WHEN 'undo' THEN v_status IN ('posted', 'active')
        -- v5.4.2-27 r2 (Ryan, 2026-11-05, option 1): an undo of a credit's
        -- repayment also after the credit was escheated; what it gives back
        -- is carried into a shortfall_reissue credit at commit
        -- (enforce_shortfall_undo_carried).
        WHEN 'shortfall_undo' THEN v_status IN ('posted', 'active') OR (p_kind = 'credit' AND v_status = 'escheated')
        WHEN 'application' THEN v_status IN ('posted', 'active') AND NOT v_deposit AND v_amount > 0
        -- v5.4.2-27 (AC-44): money applied to a bounced payment's shortfall
        -- comes from the sources a bill application does; within_family when
        -- the shortfall is the source's own payment's (R24's closing act).
        WHEN 'shortfall' THEN v_status IN ('posted', 'active') AND NOT v_deposit AND v_amount > 0
        WHEN 'shortfall_within_family' THEN p_kind = 'credit' AND v_status = 'active' AND v_amount > 0
        WHEN 'overpayment_credit' THEN p_kind = 'payment' AND v_status = 'posted' AND NOT v_deposit AND v_amount > 0
        WHEN 'refund' THEN v_status IN ('posted', 'active') AND v_amount > 0
        WHEN 'donation' THEN p_kind = 'credit' AND v_status = 'active'
        WHEN 'escheat' THEN p_kind = 'credit' AND v_status = 'active'
        -- r4 (Ryan, 2026-10-21): a refund that came back is carried into a
        -- new credit from its credit, active or escheated.
        WHEN 'reissue' THEN p_kind = 'credit' AND v_status IN ('active', 'escheated')
        ELSE false END;
    IF NOT v_ok THEN
        RAISE EXCEPTION USING
            MESSAGE = format('a row drawing on %s %s (%s%s) for %s: money is drawn from a posted payment (a bill payment, unless it is a refund) or an active credit, and an undo only while its source has not ended (A3, R-06, K-05; v5.4.2-23)', p_kind, p_id, v_status, CASE WHEN v_deposit THEN ', a deposit' ELSE '' END, p_purpose),
            ERRCODE = 'check_violation';
    END IF;
    IF p_purpose NOT IN ('undo', 'shortfall_undo') AND p_on < v_date THEN
        RAISE EXCEPTION USING
            MESSAGE = format('a row drawing on %s %s is dated %s, before the %s (%s): money is drawn on or after it arrives (A3, R-06; v5.4.2-23)', p_kind, p_id, p_on, p_kind, v_date),
            ERRCODE = 'check_violation';
    END IF;
    -- r2 (Opus B2): a source gives money only once it is on the ledger. r3:
    -- what stands of it is capped below, with the draws. r4 (Opus B3, Fable
    -- B1): an overpayment credit's money is its payment's, so what is taken
    -- back under the payment's posting entry is taken from what the credit
    -- still holds (one live credit per payment); a refund_reissue credit's is
    -- the returned refund's, already back on the ledger.
    -- r6 (Codex B1): so is a reissue's descended from an overpayment
    -- credit (v_pool_pay, its payment).
    v_entry := CASE WHEN p_kind = 'credit' AND v_pool_pay IS NOT NULL THEN public.cash_arrival_entry('payment', v_pool_pay)
                    ELSE public.cash_arrival_entry(p_kind, p_id) END;
    -- v5.4.2-27 r2: a shortfall_reissue credit's money is the undo's, as a
    -- refund_reissue's is its returned refund's.
    IF p_purpose NOT IN ('undo', 'shortfall_undo') AND v_entry IS NULL AND coalesce(v_origin, '') NOT IN ('refund_reissue', 'shortfall_reissue') THEN
        RAISE EXCEPTION USING
            MESSAGE = format('a row drawing on %s %s: its money is not on the ledger (no %s) — it gives no money (guard the act; A3, R-06; v5.4.2-23)', p_kind, p_id,
                             CASE p_kind WHEN 'payment' THEN 'posting entry' ELSE 'credit_issued entry' END),
            ERRCODE = 'check_violation';
    END IF;
    v_src_at := greatest(v_src_at, (SELECT l.created_at FROM public.account_ledger l WHERE l.id = v_entry));
    -- r2 (Opus S3): recorded order covers the source itself.
    IF p_row_created_at < v_src_at THEN
        IF p_row_created_at <> pg_catalog.now() THEN
            RAISE EXCEPTION USING
                MESSAGE = format('%s %s: a row drawing on it is recorded at %s, a time chosen for it, before the %s (recorded at %s) (R-06, v5.4.2-23)', p_kind, p_id, p_row_created_at,
                                 CASE p_kind WHEN 'payment' THEN 'payment was posted' ELSE 'credit was issued' END, v_src_at),
                ERRCODE = 'check_violation';
        END IF;
        RAISE EXCEPTION USING
            MESSAGE = format('%s %s: a row drawing on it is recorded at %s, before the %s (recorded at %s) — a transaction that began earlier is writing later; retry it (R-06, v5.4.2-23)', p_kind, p_id, p_row_created_at,
                             CASE p_kind WHEN 'payment' THEN 'payment was posted' ELSE 'credit was issued' END, v_src_at),
            ERRCODE = 'serialization_failure';
    END IF;
    -- The rows already drawing on it, the draws that have left it and the
    -- rows under its arrival entry (check_cash_order).
    PERFORM public.check_cash_order(p_kind, p_id, p_row_created_at, v_entry, 'a row drawing on it');
    -- r3 (Kyle, K-10): the cap. At every date, what the source gave (its
    -- draws) and what was taken back under its arrival entry total at most
    -- the source: a refund is capped by the payment less earlier refunds and
    -- reversals, and so is every other draw on the same money. An undo only
    -- gives money back, so it is not capped here. (A bounce is capped by
    -- R-02's tree cap alone: a posted refund does not shrink it.)
    -- r4 (Codex B3): a source with its own arrival entry has money from that
    -- entry's date (an ACH payment dated the 5th may settle on the 8th), so
    -- the entry counts from its date: at a date before it, nothing is there
    -- to draw. An overpayment or reissued credit has the amount it was
    -- created for (its money already on the ledger).
    -- r5 (Opus B1, Fable B1, Codex S1): what is taken back under a payment's
    -- posting entry is split with its live overpayment credit
    -- (overpayment_split): the credit's cap counts what it absorbed, the
    -- payment's the rest. r6 (Codex B1): each credit of the family (the
    -- overpayment credit and its reissues) counts its own share as recorded
    -- (overpayment_shares), without the cover between the sides that a
    -- position reads: a draw uses only its own side's money.
    v_family := p_kind = 'credit' AND v_pool_pay IS NOT NULL;
    IF v_family THEN
        v_split := public.overpayment_root(p_id);
    ELSIF p_kind = 'payment' THEN
        SELECT c.id INTO v_split FROM public.customer_credits c WHERE c.source_payment_id = p_id AND c.status <> 'voided';
        v_pool_pay := CASE WHEN v_split IS NOT NULL THEN p_id END;
    END IF;
    IF p_purpose NOT IN ('undo', 'shortfall_undo') THEN
        SELECT x.on_date, x.used INTO v_on, v_drawn
          FROM (SELECT u.on_date, sum(u.amount) OVER (ORDER BY u.on_date) AS used
                  FROM (SELECT d.on_date, d.amount FROM public.cash_source_draws(p_kind, p_id) d
                        UNION ALL
                        SELECT s.on_date, s.absorbed FROM public.overpayment_shares(v_split) s
                         WHERE v_family AND s.credit_id = p_id
                        UNION ALL
                        SELECT l.transaction_date, l.amount - coalesce(x.absorbed, 0)
                          FROM public.account_ledger l LEFT JOIN public.overpayment_split(v_split) x ON x.id = l.id
                         WHERE NOT v_family AND l.id = ANY (public.ledger_tree_ids(v_entry))
                        UNION ALL
                        -- missing until its arrival entry's date, then there
                        SELECT '-infinity'::date, v_amount WHERE v_entry IS NOT NULL AND NOT v_family
                        UNION ALL
                        SELECT l.transaction_date, l.amount FROM public.account_ledger l
                         WHERE l.id = v_entry AND NOT v_family) u) x
         WHERE x.used > v_amount
           -- r4 (Codex S1): from this row's date on; a row changes nothing
           -- before it, and a deficit K-10 allowed earlier is not this row's.
           AND x.on_date >= p_on
         ORDER BY x.on_date LIMIT 1;
        IF FOUND THEN
            RAISE EXCEPTION USING
                MESSAGE = format('%s %s: on %s what it gave (applications, credits, refunds, donations, escheat) and what was taken back on the ledger would come to %s, more than its %s (R-06 cap, K-10; v5.4.2-23)', p_kind, p_id, v_on, v_drawn, v_amount),
                ERRCODE = 'check_violation';
        END IF;
        -- r5 (Opus B1; K-10's refund cap): a payment and its overpayment
        -- credit together give at most the payment, less what was taken back
        -- under its posting entry, at every date from this row's on. The two
        -- caps above split that money; this one holds it whole, whatever the
        -- split read for rows of one instant. r6 (Codex B1): the credit's
        -- reissues are in it, by their own draws, not their amounts (a
        -- reissue moves the money within the family).
        -- r9 (Codex B1; Ryan, 2026-11-04, option 1): not for the two moves
        -- within the family, a reissue and an overpayment credit. The sum
        -- leaves both out, so neither changes it; but a family can be over
        -- its payment by what was already paid out (K-10), and then the
        -- reissue a returned refund must be carried to (Ryan, 2026-10-21)
        -- would be refused though it moves nothing out. Every other check
        -- on them stays.
        -- v5.4.2-27: nor for a credit's money applied to its own payment's
        -- shortfall: the payment's repayment comes back into the same sum,
        -- so the move changes nothing in it, and a family that bounced is
        -- over its payment by the shortfall itself. The target's own check
        -- (check_shortfall_repaid) holds the family at or under what it owes.
        IF v_pool_pay IS NOT NULL AND p_purpose NOT IN ('reissue', 'overpayment_credit', 'shortfall_within_family') THEN
            SELECT x.on_date, x.used, pp.amount INTO v_on, v_drawn, v_amount
              FROM public.payments pp
              CROSS JOIN LATERAL (
                   SELECT u.on_date, sum(u.amount) OVER (ORDER BY u.on_date) AS used
                     FROM (SELECT d.on_date, d.amount FROM public.cash_source_draws('payment', pp.id) d
                            WHERE d.id NOT IN (SELECT c.id FROM public.customer_credits c WHERE c.source_payment_id = pp.id)
                           UNION ALL
                           SELECT d.on_date, d.amount FROM public.customer_credits k
                             CROSS JOIN LATERAL public.overpayment_family(k.id) f
                             JOIN public.customer_credits c ON c.id = f.id
                             CROSS JOIN LATERAL public.cash_source_draws('credit', c.id) d
                            WHERE k.source_payment_id = pp.id AND k.status <> 'voided' AND c.status <> 'voided'
                              AND d.id NOT IN (SELECT g.id FROM public.overpayment_family(k.id) g)
                           UNION ALL
                           SELECT l.transaction_date, l.amount FROM public.account_ledger l
                            WHERE l.id = ANY (public.ledger_tree_ids(public.cash_arrival_entry('payment', pp.id)))
                           UNION ALL
                           SELECT '-infinity'::date, pp.amount
                           UNION ALL
                           SELECT l.transaction_date, l.amount FROM public.account_ledger l
                            WHERE l.id = public.cash_arrival_entry('payment', pp.id)) u) x
             WHERE pp.id = v_pool_pay AND x.used > pp.amount AND x.on_date >= p_on
             ORDER BY x.on_date LIMIT 1;
            IF FOUND THEN
                RAISE EXCEPTION USING
                    MESSAGE = format('payment %s and its overpayment credit: on %s what they gave and what was taken back on the ledger would come to %s, more than the payment''s %s (R-06 cap, K-10; v5.4.2-23)', v_pool_pay, v_on, v_drawn, v_amount),
                    ERRCODE = 'check_violation';
            END IF;
        END IF;
    END IF;
    -- v5.4.2-27 (Ryan, 2026-11-05, option 1): an undo gives money back to
    -- its source. Where the source holds a payment's money and that payment
    -- bounced and had its shortfall repaid, the money would sit on a payment
    -- that has ended: refused until the repayment is undone. Under the
    -- payment's lock (taken above).
    IF p_purpose IN ('undo', 'shortfall_undo') THEN
        PERFORM public.check_shortfall_repaid(CASE WHEN p_kind = 'payment' THEN p_id ELSE v_pool_pay END, NULL);
    END IF;
END;
$$;
COMMENT ON FUNCTION public.check_cash_source(text, uuid, timestamp with time zone, text, date) IS
    'v5.4.2-23 (A3; R-06), r3. READ COMMITTED only. Takes the source''s advisory lock (after the tenant''s close head, which the row''s freeze took), then reads the source: unknown or invisible raises; by purpose, an application from a posted bill payment or an active credit, an overpayment credit from a posted bill payment, a refund from a posted payment or an active credit, a donation or escheat from an active credit, each dated on or after the source and only once its money is on the ledger (cash_arrival_entry; an overpayment credit''s is its payment''s); an undo only while the source has not ended. Then refuses a row recorded before the source reached the ledger (r3: a payment''s move to posted, a credit''s credit_issued entry) or before a row already drawing on it (40001; 23514 for a chosen time). Then (not for an undo) refuses any date at which the draws (cash_source_draws) and what was taken back under the arrival entry exceed the payment or credit (r3, Kyle''s K-10 refund cap, applied to every draw); r6: a credit holding a payment''s money (an overpayment credit or a reissue descended from one) counts its own share of what was taken back (overpayment_shares), the payment the rest, and a payment and its credits together never give more than the payment less what was taken back. The recorded-order legs are check_cash_order''s. v5.4.2-27: purpose shortfall (a payment''s or credit''s money applied to a bounced payment''s shortfall, from the sources an application takes) and shortfall_within_family (a credit''s money applied to its own payment''s shortfall: not held to the family cap, as a reissue); after an undo, check_shortfall_repaid on the source''s payment. r2 (Ryan, 2026-11-05): purpose shortfall_undo, an undo of a shortfall application, also from an escheated credit (carried at commit); a shortfall_reissue credit, as a refund_reissue, has no arrival entry.';
REVOKE ALL ON FUNCTION public.check_cash_source(text, uuid, timestamp with time zone, text, date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.check_cash_source(text, uuid, timestamp with time zone, text, date) TO tally_app;

-- ----------------------------------------------------------------------------
-- 5. A shortfall application
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.enforce_shortfall_application() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_target public.payments%ROWTYPE;
    v_undone public.shortfall_applications%ROWTYPE;
    v_kind   text := CASE WHEN NEW.payment_id IS NOT NULL THEN 'payment' ELSE 'credit' END;
    v_src    uuid := coalesce(NEW.payment_id, NEW.customer_credit_id);
    v_within boolean := false;
    v_net    numeric;
BEGIN
    -- Recorded at a time already reached, for any role (-23 r6).
    IF NOT pg_catalog.isfinite(NEW.created_at) OR NEW.created_at > pg_catalog.clock_timestamp() THEN
        RAISE EXCEPTION USING
            MESSAGE = format('shortfall application %s is recorded at %s, not a time already reached — every money row is recorded at a finite time already reached (v5.4.2-27)', NEW.id, NEW.created_at),
            ERRCODE = 'check_violation';
    END IF;
    -- The target, under its lock (after the head the freeze took, before the
    -- source's): read there, so a move that ended it while this row waited
    -- is seen.
    PERFORM pg_catalog.pg_advisory_xact_lock(public.cash_source_lock_key('payment', NEW.target_payment_id));
    SELECT * INTO v_target FROM public.payments p WHERE p.id = NEW.target_payment_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING
            MESSAGE = format('shortfall application %s: no payment %s is visible (v5.4.2-27)', NEW.id, NEW.target_payment_id),
            ERRCODE = 'foreign_key_violation';
    END IF;
    -- r2 (Opus S2): a refund is money paid out, not money that bounced: a
    -- refund that came back gives its source its money back (-23).
    IF v_target.refunds_payment_id IS NOT NULL OR v_target.refunds_customer_credit_id IS NOT NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('shortfall application %s: payment %s is a refund — a refund that came back gives its money back to what it refunded; it leaves no shortfall (AC-44, v5.4.2-27)', NEW.id, v_target.payment_number),
            ERRCODE = 'check_violation';
    END IF;
    -- r2 (Opus S1): a deposit is kept out of the customer's pot (K-05), and
    -- so is what a bounced deposit left owed.
    IF v_target.is_deposit THEN
        RAISE EXCEPTION USING
            MESSAGE = format('shortfall application %s: payment %s is a deposit — a deposit is kept out of the customer''s pot, and so is what a bounced one left owed (K-05; AC-44, v5.4.2-27)', NEW.id, v_target.payment_number),
            ERRCODE = 'check_violation';
    END IF;
    IF v_target.status NOT IN ('nsf', 'reversed') THEN
        RAISE EXCEPTION USING
            MESSAGE = format('shortfall application %s: payment %s is %s — a shortfall is repaid on a payment that bounced or was reversed (nsf or reversed); money owed on a bill goes to the bill (AC-44, v5.4.2-27)', NEW.id, v_target.payment_number, v_target.status),
            ERRCODE = 'check_violation';
    END IF;
    -- Recorded after the target's move (its shortfall is not there before).
    IF NEW.created_at < v_target.status_recorded_at THEN
        IF NEW.created_at <> pg_catalog.now() THEN
            RAISE EXCEPTION USING
                MESSAGE = format('shortfall application %s is recorded at %s, a time chosen for it, before payment %s moved to %s (%s) (v5.4.2-27)', NEW.id, NEW.created_at, v_target.payment_number, v_target.status, v_target.status_recorded_at),
                ERRCODE = 'check_violation';
        END IF;
        RAISE EXCEPTION USING
            MESSAGE = format('shortfall application %s is recorded at %s, before payment %s moved to %s (%s) — a transaction that began earlier is writing later; retry it (v5.4.2-27)', NEW.id, NEW.created_at, v_target.payment_number, v_target.status, v_target.status_recorded_at),
            ERRCODE = 'serialization_failure';
    END IF;
    -- -23's recorded order on the target and its family: not before a row
    -- already drawing on them, a draw that has left them, or a row under the
    -- payment's posting entry (the cover reads them all at one instant).
    PERFORM public.check_cash_order('payment', NEW.target_payment_id, NEW.created_at,
                                    public.cash_arrival_entry('payment', NEW.target_payment_id), 'a repayment of its shortfall');
    PERFORM public.check_cash_order('credit', f.id, NEW.created_at, NULL, 'a repayment of its payment''s shortfall')
       FROM public.customer_credits k CROSS JOIN LATERAL public.overpayment_family(k.id) f
      WHERE k.source_payment_id = NEW.target_payment_id AND k.status <> 'voided';
    IF NEW.basis = 'undo' THEN
        SELECT * INTO v_undone FROM public.shortfall_applications s WHERE s.id = NEW.undoes_shortfall_application_id;
        IF v_undone.basis = 'undo'
           OR v_undone.payment_id IS DISTINCT FROM NEW.payment_id
           OR v_undone.customer_credit_id IS DISTINCT FROM NEW.customer_credit_id THEN
            RAISE EXCEPTION USING
                MESSAGE = format('shortfall application %s undoes %s: an undo names a shortfall application (not an undo) of the same source and payment (v5.4.2-27)', NEW.id, NEW.undoes_shortfall_application_id),
                ERRCODE = 'check_violation';
        END IF;
        IF NEW.applied_on < v_undone.applied_on THEN
            RAISE EXCEPTION USING
                MESSAGE = format('shortfall application %s is dated %s, before the one it undoes (%s, %s): an undo is dated on or after it (v5.4.2-27)', NEW.id, NEW.applied_on, v_undone.id, v_undone.applied_on),
                ERRCODE = 'check_violation';
        END IF;
    END IF;
    -- The source, under its lock and caps (check_cash_source). A credit
    -- holding the target's own money applies within its family (R24).
    IF v_kind = 'credit' THEN
        v_within := EXISTS (SELECT 1 FROM public.customer_credits k
                             WHERE k.id = public.overpayment_root(v_src) AND k.source_payment_id = NEW.target_payment_id);
    END IF;
    PERFORM public.check_cash_source(v_kind, v_src, NEW.created_at,
                                     CASE WHEN NEW.basis = 'undo' THEN 'shortfall_undo' WHEN v_within THEN 'shortfall_within_family' ELSE 'shortfall' END,
                                     NEW.applied_on);
    IF NEW.basis = 'undo' THEN
        SELECT v_undone.amount + coalesce(sum(s.amount), 0) INTO v_net
          FROM public.shortfall_applications s WHERE s.undoes_shortfall_application_id = v_undone.id;
        IF v_net < 0 THEN
            RAISE EXCEPTION USING
                MESSAGE = format('shortfall application %s: its undos would come to %s, more than its %s (v5.4.2-27)', v_undone.id, v_undone.amount - v_net, v_undone.amount),
                ERRCODE = 'check_violation';
        END IF;
    ELSE
        -- The target's cap: repaid down to 0, never past it.
        PERFORM public.check_shortfall_repaid(NEW.target_payment_id, NEW.applied_on);
    END IF;
    RETURN NULL;
END;
$$;
COMMENT ON FUNCTION public.enforce_shortfall_application() IS
    'v5.4.2-27 (AC-44; Kyle, 2026-10-30; Ryan, 2026-11-02). AFTER INSERT on shortfall_applications, recorded at a time already reached; READ COMMITTED only (check_cash_source refuses any other level before anything is written). Takes the target payment''s lock (after the head the freeze took) and reads it there: a bill payment (r2: not a refund, not a deposit) that bounced or was reversed (nsf or reversed); the row is recorded after its move (40001; 23514 for a chosen time) and after every row already drawing on it or its overpayment family, a draw that left them, or a row under its posting entry (check_cash_order). An undo names a shortfall application (not an undo) of the same source and target, dated on or after it, and the undos never exceed it. The source under its lock and caps (check_cash_source: purpose shortfall, shortfall_within_family for a credit holding the target''s own money, or shortfall_undo, r2: from an escheated credit too, carried at commit). Then, for a repayment, the target''s cap (check_shortfall_repaid).';
CREATE TRIGGER enforce_shortfall_application AFTER INSERT ON public.shortfall_applications
    FOR EACH ROW EXECUTE FUNCTION public.enforce_shortfall_application();
ALTER TABLE public.shortfall_applications ENABLE ALWAYS TRIGGER enforce_shortfall_application;

-- ----------------------------------------------------------------------------
-- 6. The source's own bounce, and money leaving a repaid family
-- ----------------------------------------------------------------------------
-- R15's rule for a source applied to a shortfall: its money is not taken
-- back, and it does not end, while it (or a credit of its overpayment family)
-- is applied to one. And a refund of a repaid family that leaves gives money
-- back to a payment that has ended: refused until the repayment is undone
-- (Ryan, 2026-11-05, option 1). AFTER the row or the move, under the payment's
-- lock (enforce_ledger_reversal and enforce_payment_immutable took it).
CREATE OR REPLACE FUNCTION public.shortfall_applied_from(p_payment_id uuid) RETURNS boolean
    LANGUAGE sql STABLE
    SET search_path = public, pg_temp
    AS $$
    SELECT coalesce((SELECT sum(s.amount) FROM public.shortfall_applications s WHERE s.payment_id = p_payment_id), 0) <> 0
        OR EXISTS (SELECT 1 FROM public.customer_credits k CROSS JOIN LATERAL public.overpayment_family(k.id) f
                     JOIN public.customer_credits c ON c.id = f.id
                    WHERE k.source_payment_id = p_payment_id AND k.status <> 'voided' AND c.status <> 'voided'
                      AND coalesce((SELECT sum(s.amount) FROM public.shortfall_applications s WHERE s.customer_credit_id = c.id), 0) <> 0)
$$;
COMMENT ON FUNCTION public.shortfall_applied_from(uuid) IS
    'v5.4.2-27. Whether a payment''s money, or a credit of its overpayment family''s, is applied to a bounced payment''s shortfall (its shortfall applications net to more than 0). Live. Read by the payment''s own bounce guards (enforce_shortfall_source_moves, enforce_ledger_shortfall_source).';
REVOKE ALL ON FUNCTION public.shortfall_applied_from(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.shortfall_applied_from(uuid) TO tally_app, tally_core;

CREATE OR REPLACE FUNCTION public.enforce_ledger_shortfall_source() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_root public.account_ledger%ROWTYPE;
    v_pay  uuid;
BEGIN
    SELECT * INTO v_root FROM public.account_ledger l WHERE l.id = public.ledger_tree_root(NEW.id);
    IF v_root.reference_type = 'payment' AND v_root.transaction_type IN ('payment', 'deposit') THEN
        SELECT p.id INTO v_pay FROM public.payments p WHERE p.id = v_root.reference_id AND v_root.amount = -p.amount;
    END IF;
    IF v_pay IS NULL THEN
        RETURN NULL;
    END IF;
    PERFORM pg_catalog.pg_advisory_xact_lock(public.cash_source_lock_key('payment', v_pay));
    IF public.shortfall_applied_from(v_pay) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('account_ledger %s takes back payment %s''s money while it (or its overpayment credit) is applied to a bounced payment''s shortfall: undo that first (guard the act; R15, v5.4.2-27)', NEW.id, v_pay),
            ERRCODE = 'restrict_violation';
    END IF;
    RETURN NULL;
END;
$$;
COMMENT ON FUNCTION public.enforce_ledger_shortfall_source() IS
    'v5.4.2-27 (R15''s rule). AFTER INSERT on account_ledger, for a row taking money away under an entry (more than 0, naming one): when its tree''s root is a payment''s posting entry, takes the payment''s lock (after the tree''s, which enforce_ledger_reversal took) and refuses the row while the payment or a credit of its overpayment family is applied to a bounced payment''s shortfall (shortfall_applied_from).';
CREATE TRIGGER enforce_ledger_shortfall_source AFTER INSERT ON public.account_ledger
    FOR EACH ROW WHEN (NEW.reverses_ledger_entry_id IS NOT NULL AND NEW.amount > 0) EXECUTE FUNCTION public.enforce_ledger_shortfall_source();
ALTER TABLE public.account_ledger ENABLE ALWAYS TRIGGER enforce_ledger_shortfall_source;

CREATE OR REPLACE FUNCTION public.enforce_shortfall_source_moves() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
BEGIN
    IF public.shortfall_applied_from(NEW.id) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('payment %s cannot move to %s while it (or its overpayment credit) is applied to a bounced payment''s shortfall: undo that first (R15, v5.4.2-27)', NEW.payment_number, NEW.status),
            ERRCODE = 'restrict_violation';
    END IF;
    -- A refund that leaves gives its money back to its source's family.
    IF NEW.refunds_payment_id IS NOT NULL OR NEW.refunds_customer_credit_id IS NOT NULL THEN
        PERFORM public.check_shortfall_repaid(coalesce(NEW.refunds_payment_id,
            (SELECT k.source_payment_id FROM public.customer_credits k WHERE k.id = public.overpayment_root(NEW.refunds_customer_credit_id))), NULL);
    END IF;
    RETURN NULL;
END;
$$;
COMMENT ON FUNCTION public.enforce_shortfall_source_moves() IS
    'v5.4.2-27. AFTER UPDATE OF status on payments, for a move to nsf, reversed or voided (enforce_payment_immutable took the payment''s lock and, for a refund, its source''s). Refuses the move while the payment or a credit of its overpayment family is applied to a bounced payment''s shortfall (R15''s rule); for a refund that leaves, the target''s cap on the family its money goes back to (check_shortfall_repaid: Ryan, 2026-11-05, option 1, the repayment is undone first).';
CREATE TRIGGER enforce_shortfall_source_moves AFTER UPDATE OF status ON public.payments
    FOR EACH ROW WHEN (OLD.status IS DISTINCT FROM NEW.status AND NEW.status IN ('nsf', 'reversed', 'voided'))
    EXECUTE FUNCTION public.enforce_shortfall_source_moves();
ALTER TABLE public.payments ENABLE ALWAYS TRIGGER enforce_shortfall_source_moves;

-- ----------------------------------------------------------------------------
-- 6b. The carry (r2; Ryan, 2026-11-05, option 1)
-- ----------------------------------------------------------------------------
-- A shortfall_reissue credit carries what an undo gave back to a credit
-- since escheated: it names an undo of that credit's repayment, is dated on
-- or after it, and carries what the undo gave back as far as it is left on
-- the credit (-23 r5's size for a refund_reissue), not deeper than every walk
-- of the line reads (-23 r7). It draws on the escheated credit (purpose
-- reissue) under its locks: the payment whose money the credit holds, if
-- any, then the credit.
CREATE OR REPLACE FUNCTION public.enforce_shortfall_reissue() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_undo   public.shortfall_applications%ROWTYPE;
    v_from   text;
    v_ended  timestamptz;
    v_left   numeric;
BEGIN
    -- r3 (Codex B1): born active, for every role. A superuser's history load
    -- keeps any status elsewhere (-23's enforce_cash_birth returns early for
    -- it), but a carry born ended would hold the money the undo gave back
    -- where nothing can reach it; its endings are -23's checked moves.
    IF NEW.status IS DISTINCT FROM 'active' THEN
        RAISE EXCEPTION USING
            MESSAGE = format('credit %s reissues shortfall application %s and is born %s: a shortfall_reissue credit is born active, for every role (a history load''s too), and ends only by a checked move (Codex B1; v5.4.2-27)', NEW.id, NEW.reissues_shortfall_application_id, NEW.status),
            ERRCODE = 'check_violation';
    END IF;
    SELECT * INTO v_undo FROM public.shortfall_applications s WHERE s.id = NEW.reissues_shortfall_application_id;
    SELECT c.status, c.status_recorded_at INTO v_from, v_ended FROM public.customer_credits c WHERE c.id = v_undo.customer_credit_id;
    IF v_undo.basis IS DISTINCT FROM 'undo' OR v_undo.customer_credit_id IS NULL OR v_from IS DISTINCT FROM 'escheated' THEN
        RAISE EXCEPTION USING
            MESSAGE = format('credit %s reissues shortfall application %s: a shortfall_reissue credit carries what an undo of a credit''s repayment gave back after the credit was escheated; %s', NEW.id, NEW.reissues_shortfall_application_id,
                             CASE WHEN v_undo.basis IS DISTINCT FROM 'undo' THEN 'it is not an undo' WHEN v_undo.customer_credit_id IS NULL THEN 'its source is a payment' ELSE 'its credit is ' || v_from END)
                      || ' (Ryan, 2026-11-05; v5.4.2-27)',
            ERRCODE = 'check_violation';
    END IF;
    -- r3 (Opus S1): the undo was recorded at or after the escheat (the
    -- database's time of the credit's move, status_recorded_at). An undo
    -- recorded while the credit was active left its money there, the escheat
    -- sent it to the state, and there is nothing of that undo's to carry; its
    -- name would label other money.
    IF v_undo.created_at < v_ended THEN
        RAISE EXCEPTION USING
            MESSAGE = format('credit %s reissues shortfall application %s, recorded at %s, before credit %s was escheated (%s): an undo recorded while the credit was active left its money there for the escheat, and gives nothing to carry; a carry names an undo recorded at or after the escheat (Opus S1; v5.4.2-27)', NEW.id, v_undo.id, v_undo.created_at, v_undo.customer_credit_id, v_ended),
            ERRCODE = 'check_violation';
    END IF;
    IF public.reissue_generation(v_undo.customer_credit_id) + 1 > public.reissue_line_bound() THEN
        RAISE EXCEPTION USING
            MESSAGE = format('credit %s reissues shortfall application %s: its line would be more than %s reissues deep, past what any walk of it reads (Codex B2; v5.4.2-23, v5.4.2-27)', NEW.id, v_undo.id, public.reissue_line_bound()),
            ERRCODE = 'check_violation';
    END IF;
    IF NEW.issued_date < v_undo.applied_on THEN
        RAISE EXCEPTION USING
            MESSAGE = format('credit %s reissues shortfall application %s, dated %s: it is dated on or after the undo (%s), whose money it carries (Ryan, 2026-11-05; v5.4.2-27)', NEW.id, v_undo.id, NEW.issued_date, v_undo.applied_on),
            ERRCODE = 'check_violation';
    END IF;
    PERFORM pg_catalog.pg_advisory_xact_lock(public.cash_source_lock_key('payment', c.source_payment_id))
       FROM public.customer_credits c WHERE c.id = public.overpayment_root(v_undo.customer_credit_id);
    PERFORM pg_catalog.pg_advisory_xact_lock(public.cash_source_lock_key('credit', v_undo.customer_credit_id));
    -- As -23 r9 sizes a refund_reissue: the credit's own remainder with this
    -- credit counted as carried, plus what this one was issued with.
    v_left := public.customer_credit_own_remaining_as_of(v_undo.customer_credit_id, DATE '9999-12-31', pg_catalog.clock_timestamp())
            + NEW.original_amount
            - coalesce((SELECT s.absorbed FROM public.overpayment_absorbed_as_of(public.overpayment_root(NEW.id), DATE '9999-12-31', pg_catalog.clock_timestamp(), false) s
                         WHERE s.credit_id = NEW.id), 0);
    IF NEW.original_amount <> least(-v_undo.amount, v_left) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('credit %s reissues shortfall application %s for %s: it carries what the undo gave back (%s) as far as it is left on credit %s (%s before it) (Ryan, 2026-11-05; v5.4.2-27)', NEW.id, v_undo.id, NEW.original_amount, -v_undo.amount, v_undo.customer_credit_id, v_left),
            ERRCODE = 'check_violation';
    END IF;
    PERFORM public.check_cash_source('credit', v_undo.customer_credit_id, NEW.created_at, 'reissue', NEW.issued_date);
    RETURN NULL;
END;
$$;
COMMENT ON FUNCTION public.enforce_shortfall_reissue() IS
    'v5.4.2-27 r2 (Ryan, 2026-11-05, option 1; Opus B2, Fable S1). AFTER INSERT on customer_credits naming a shortfall application: r3, born active for every role (Codex B1); it is an undo of a credit''s repayment, the credit is escheated, r3, the undo recorded at or after the escheat (status_recorded_at; Opus S1), the line no deeper than reissue_line_bound(), dated on or after the undo; sized as -23''s refund_reissue (what the undo gave back, as far as it is left on the credit before it); then a draw on the credit (check_cash_source, purpose reissue) under the locks the cap takes.';
CREATE TRIGGER enforce_shortfall_reissue AFTER INSERT ON public.customer_credits
    FOR EACH ROW WHEN (NEW.reissues_shortfall_application_id IS NOT NULL) EXECUTE FUNCTION public.enforce_shortfall_reissue();
ALTER TABLE public.customer_credits ENABLE ALWAYS TRIGGER enforce_shortfall_reissue;

-- At commit, an undo that gave money back to an escheated credit has left
-- nothing on it of its own: the rest is carried (as -23's
-- enforce_escheated_credit_settled for a refund that came back).
CREATE OR REPLACE FUNCTION public.enforce_shortfall_undo_carried() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_left numeric;
BEGIN
    IF (SELECT c.status FROM public.customer_credits c WHERE c.id = NEW.customer_credit_id) IS DISTINCT FROM 'escheated' THEN
        RETURN NULL;
    END IF;
    v_left := public.customer_credit_own_remaining_as_of(NEW.customer_credit_id, DATE '9999-12-31', pg_catalog.clock_timestamp());
    IF v_left > 0 THEN
        RAISE EXCEPTION USING
            MESSAGE = format('shortfall application %s gives %s back to credit %s, which was escheated — carry it to a new credit (origin shortfall_reissue, naming this undo) in the same transaction (Ryan, 2026-11-05; v5.4.2-27)', NEW.id, v_left, NEW.customer_credit_id),
            ERRCODE = 'check_violation';
    END IF;
    RETURN NULL;
END;
$$;
COMMENT ON FUNCTION public.enforce_shortfall_undo_carried() IS
    'v5.4.2-27 r2 (Ryan, 2026-11-05, option 1). Deferred to commit, after the undo of a credit''s shortfall application: if the credit is escheated, nothing positive is left on it of its own (customer_credit_own_remaining_as_of), what the undo gave back carried to a shortfall_reissue credit naming the undo.';
CREATE CONSTRAINT TRIGGER enforce_shortfall_undo_carried AFTER INSERT ON public.shortfall_applications
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW WHEN (NEW.basis = 'undo' AND NEW.customer_credit_id IS NOT NULL)
    EXECUTE FUNCTION public.enforce_shortfall_undo_carried();
ALTER TABLE public.shortfall_applications ENABLE ALWAYS TRIGGER enforce_shortfall_undo_carried;

-- A shortfall_reissue credit's money is already on the ledger (the undo
-- moved it between two records of the customer's money), so it posts no
-- credit_issued row; its key is fixed; and it is never voided: its money
-- would go back to a credit that was escheated (Ryan, 2026-10-21).
CREATE OR REPLACE FUNCTION public.enforce_shortfall_reissue_rows() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
BEGIN
    IF TG_TABLE_NAME = 'account_ledger' THEN
        IF EXISTS (SELECT 1 FROM public.customer_credits c WHERE c.id = NEW.reference_id AND c.origin_type = 'shortfall_reissue') THEN
            RAISE EXCEPTION USING
                MESSAGE = format('account_ledger %s issues shortfall_reissue credit %s: it posts no ledger row — its money is what an undo gave back, already on the ledger (Ryan, 2026-11-05; v5.4.2-27)', NEW.id, NEW.reference_id),
                ERRCODE = 'check_violation';
        END IF;
    ELSIF NEW.reissues_shortfall_application_id IS DISTINCT FROM OLD.reissues_shortfall_application_id THEN
        RAISE EXCEPTION USING
            MESSAGE = format('customer credit %s: reissues_shortfall_application_id is fixed from insert (R-05; v5.4.2-27)', OLD.id),
            ERRCODE = 'restrict_violation';
    ELSIF OLD.origin_type = 'shortfall_reissue' AND NEW.status = 'voided' THEN
        RAISE EXCEPTION USING
            MESSAGE = format('customer credit %s cannot be voided: it carries money an undo gave back to a credit that was escheated, and nothing goes back to that credit (Ryan, 2026-10-21, 2026-11-05; v5.4.2-27)', OLD.id),
            ERRCODE = 'restrict_violation';
    END IF;
    RETURN NULL;
END;
$$;
COMMENT ON FUNCTION public.enforce_shortfall_reissue_rows() IS
    'v5.4.2-27 r2 (Ryan, 2026-11-05). AFTER INSERT on account_ledger, for a credit_issued row: refused for a shortfall_reissue credit (its money is already on the ledger). AFTER UPDATE on customer_credits: reissues_shortfall_application_id is fixed, and a shortfall_reissue credit is never voided.';
CREATE TRIGGER enforce_shortfall_reissue_rows AFTER INSERT ON public.account_ledger
    FOR EACH ROW WHEN (NEW.transaction_type = 'credit_issued' AND NEW.reference_type = 'customer_credit')
    EXECUTE FUNCTION public.enforce_shortfall_reissue_rows();
ALTER TABLE public.account_ledger ENABLE ALWAYS TRIGGER enforce_shortfall_reissue_rows;
CREATE TRIGGER enforce_shortfall_reissue_rows AFTER UPDATE ON public.customer_credits
    FOR EACH ROW WHEN (OLD.reissues_shortfall_application_id IS DISTINCT FROM NEW.reissues_shortfall_application_id
                       OR (OLD.origin_type = 'shortfall_reissue' AND NEW.status = 'voided' AND OLD.status <> 'voided'))
    EXECUTE FUNCTION public.enforce_shortfall_reissue_rows();
ALTER TABLE public.customer_credits ENABLE ALWAYS TRIGGER enforce_shortfall_reissue_rows;

-- ----------------------------------------------------------------------------
-- 7. Grants
-- ----------------------------------------------------------------------------
REVOKE ALL ON public.shortfall_applications FROM PUBLIC, tally_app, tally_core;
GRANT SELECT, INSERT ON public.shortfall_applications TO tally_app;
GRANT SELECT ON public.shortfall_applications TO tally_core;

-- ----------------------------------------------------------------------------
-- 8. The invariants
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.assert_shortfall_guard_invariants() RETURNS void
    LANGUAGE plpgsql STABLE
    SET search_path = public, pg_temp
    AS $fn$
DECLARE
    v_bad text;
    -- PostgreSQL 16's rendering by pg_get_triggerdef and pg_get_constraintdef.
    c_triggers CONSTANT text[] := ARRAY[
        'CREATE TRIGGER a_enforce_accounting_freeze BEFORE INSERT ON public.shortfall_applications FOR EACH ROW EXECUTE FUNCTION enforce_accounting_freeze(''applied_on'')',
        'CREATE TRIGGER append_only BEFORE DELETE OR UPDATE ON public.shortfall_applications FOR EACH ROW EXECUTE FUNCTION enforce_append_only()',
        'CREATE TRIGGER a_stamp_created_at BEFORE INSERT ON public.shortfall_applications FOR EACH ROW EXECUTE FUNCTION stamp_log_created_at()',
        'CREATE TRIGGER enforce_ledger_shortfall_source AFTER INSERT ON public.account_ledger FOR EACH ROW WHEN (((new.reverses_ledger_entry_id IS NOT NULL) AND (new.amount > (0)::numeric))) EXECUTE FUNCTION enforce_ledger_shortfall_source()',
        'CREATE TRIGGER enforce_shortfall_application AFTER INSERT ON public.shortfall_applications FOR EACH ROW EXECUTE FUNCTION enforce_shortfall_application()',
        'CREATE TRIGGER enforce_shortfall_source_moves AFTER UPDATE OF status ON public.payments FOR EACH ROW WHEN (((old.status IS DISTINCT FROM new.status) AND (new.status = ANY (ARRAY[''nsf''::text, ''reversed''::text, ''voided''::text])))) EXECUTE FUNCTION enforce_shortfall_source_moves()',
        'CREATE TRIGGER no_hard_delete BEFORE DELETE ON public.shortfall_applications FOR EACH ROW EXECUTE FUNCTION enforce_no_hard_delete()',
        'CREATE TRIGGER no_truncate BEFORE TRUNCATE ON public.shortfall_applications FOR EACH STATEMENT EXECUTE FUNCTION enforce_no_hard_delete()',
        'CREATE CONSTRAINT TRIGGER enforce_shortfall_undo_carried AFTER INSERT ON public.shortfall_applications DEFERRABLE INITIALLY DEFERRED FOR EACH ROW WHEN (((new.basis = ''undo''::text) AND (new.customer_credit_id IS NOT NULL))) EXECUTE FUNCTION enforce_shortfall_undo_carried()',
        'CREATE TRIGGER enforce_shortfall_reissue AFTER INSERT ON public.customer_credits FOR EACH ROW WHEN ((new.reissues_shortfall_application_id IS NOT NULL)) EXECUTE FUNCTION enforce_shortfall_reissue()',
        'CREATE TRIGGER enforce_shortfall_reissue_rows AFTER INSERT ON public.account_ledger FOR EACH ROW WHEN (((new.transaction_type = ''credit_issued''::text) AND (new.reference_type = ''customer_credit''::text))) EXECUTE FUNCTION enforce_shortfall_reissue_rows()',
        'CREATE TRIGGER enforce_shortfall_reissue_rows AFTER UPDATE ON public.customer_credits FOR EACH ROW WHEN (((old.reissues_shortfall_application_id IS DISTINCT FROM new.reissues_shortfall_application_id) OR ((old.origin_type = ''shortfall_reissue''::text) AND (new.status = ''voided''::text) AND (old.status <> ''voided''::text)))) EXECUTE FUNCTION enforce_shortfall_reissue_rows()'];
    c_constraints CONSTANT text[] := ARRAY[
        'shortfall_applications shortfall_applications_applied_by_fkey FOREIGN KEY (applied_by, tenant_id) REFERENCES users(id, tenant_id)',
        'shortfall_applications shortfall_applications_basis_check CHECK ((basis = ANY (ARRAY[''customer_pot''::text, ''operator_override''::text, ''undo''::text])))',
        'shortfall_applications shortfall_applications_credit_fkey FOREIGN KEY (customer_credit_id, tenant_id, customer_id) REFERENCES customer_credits(id, tenant_id, customer_id)',
        'shortfall_applications shortfall_applications_id_tenant_target_key UNIQUE (id, tenant_id, target_payment_id)',
        'shortfall_applications shortfall_applications_not_own_check CHECK ((payment_id IS DISTINCT FROM target_payment_id))',
        'shortfall_applications shortfall_applications_not_self_check CHECK ((undoes_shortfall_application_id IS DISTINCT FROM id))',
        'shortfall_applications shortfall_applications_one_source_check CHECK ((num_nonnulls(payment_id, customer_credit_id) = 1))',
        'shortfall_applications shortfall_applications_operator_check CHECK (((basis <> ALL (ARRAY[''operator_override''::text, ''undo''::text])) OR ((applied_by IS NOT NULL) AND COALESCE((reason ~ ''[[:alnum:]]''::text), false))))',
        'shortfall_applications shortfall_applications_payment_fkey FOREIGN KEY (payment_id, tenant_id, customer_id) REFERENCES payments(id, tenant_id, customer_id)',
        'shortfall_applications shortfall_applications_pkey PRIMARY KEY (id)',
        'shortfall_applications shortfall_applications_sign_check CHECK (((amount <> (0)::numeric) AND ((amount < (0)::numeric) = (basis = ''undo''::text)) AND ((basis = ''undo''::text) = (undoes_shortfall_application_id IS NOT NULL))))',
        'shortfall_applications shortfall_applications_target_fkey FOREIGN KEY (target_payment_id, tenant_id, customer_id) REFERENCES payments(id, tenant_id, customer_id)',
        'shortfall_applications shortfall_applications_tenant_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id)',
        'shortfall_applications shortfall_applications_undoes_fkey FOREIGN KEY (undoes_shortfall_application_id, tenant_id, target_payment_id) REFERENCES shortfall_applications(id, tenant_id, target_payment_id)',
        'shortfall_applications shortfall_applications_id_tenant_customer_key UNIQUE (id, tenant_id, customer_id)',
        'customer_credits customer_credits_origin_type_check CHECK ((origin_type = ANY (ARRAY[''overpayment''::text, ''goodwill''::text, ''dispute_resolution''::text, ''deposit_refund''::text, ''transfer''::text, ''adjustment''::text, ''refund_reissue''::text, ''regulatory_rebate''::text, ''promotion''::text, ''other''::text, ''shortfall_reissue''::text])))',
        'customer_credits customer_credits_reissue_shortfall_fkey FOREIGN KEY (reissues_shortfall_application_id, tenant_id, customer_id) REFERENCES shortfall_applications(id, tenant_id, customer_id)',
        'customer_credits customer_credits_shortfall_reissue_check CHECK (((origin_type = ''shortfall_reissue''::text) = (reissues_shortfall_application_id IS NOT NULL)))'];
BEGIN
    SELECT string_agg(d, E'\n  ' ORDER BY d) INTO v_bad
      FROM unnest(c_triggers) d
     WHERE NOT EXISTS (SELECT 1 FROM pg_catalog.pg_trigger g
                        WHERE NOT g.tgisinternal AND g.tgenabled = 'A'
                          AND pg_catalog.pg_get_triggerdef(g.oid) = d);
    IF v_bad IS NOT NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format(E'a v5.4.2-27 guard is missing, changed, or not ENABLE ALWAYS:\n  %s', v_bad),
            ERRCODE = 'invalid_grant_operation';
    END IF;
    SELECT string_agg(d, E'\n  ' ORDER BY d) INTO v_bad
      FROM unnest(c_constraints) d
     WHERE NOT EXISTS (SELECT 1 FROM pg_catalog.pg_constraint k
                        WHERE k.convalidated
                          AND k.conrelid::regclass::text || ' ' || k.conname || ' ' || pg_catalog.pg_get_constraintdef(k.oid) = d);
    IF v_bad IS NOT NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format(E'a v5.4.2-27 constraint is missing, changed or not validated:\n  %s', v_bad),
            ERRCODE = 'invalid_grant_operation';
    END IF;
    -- Add-only: tally_app inserts and reads, nothing else (a column grant is
    -- reach too); tally_core reads it and nothing else; PUBLIC nothing. r2
    -- (Codex S1): has_table_privilege with a list is true when any one is
    -- held, so each required privilege is asked alone.
    IF has_table_privilege('tally_app', 'public.shortfall_applications', 'UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER')
       OR has_any_column_privilege('tally_app', 'public.shortfall_applications', 'UPDATE, REFERENCES')
       OR NOT has_table_privilege('tally_app', 'public.shortfall_applications', 'SELECT')
       OR NOT has_table_privilege('tally_app', 'public.shortfall_applications', 'INSERT')
       OR has_table_privilege('tally_core', 'public.shortfall_applications', 'INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER')
       OR has_any_column_privilege('tally_core', 'public.shortfall_applications', 'INSERT, UPDATE, REFERENCES')
       OR NOT has_table_privilege('tally_core', 'public.shortfall_applications', 'SELECT')
       OR has_table_privilege('public', 'public.shortfall_applications', 'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER')
       OR has_any_column_privilege('public', 'public.shortfall_applications', 'SELECT, INSERT, UPDATE, REFERENCES') THEN
        RAISE EXCEPTION USING
            MESSAGE = 'shortfall_applications: tally_app may only SELECT and INSERT it, tally_core only read it, PUBLIC nothing (add-only; v5.4.2-27)',
            ERRCODE = 'invalid_grant_operation';
    END IF;
    -- Its tenant policy, alone, and forced row security.
    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_policies p
                    WHERE p.schemaname = 'public' AND p.tablename = 'shortfall_applications' AND p.policyname = 'tenant_isolation'
                      AND p.cmd = 'ALL' AND p.permissive = 'PERMISSIVE' AND p.roles = '{public}'
                      AND p.qual = '(is_platform_admin() OR (tenant_id = get_user_tenant_id()))' AND p.with_check IS NULL)
       OR (SELECT count(*) FROM pg_catalog.pg_policies p WHERE p.schemaname = 'public' AND p.tablename = 'shortfall_applications') <> 1
       OR NOT (SELECT c.relrowsecurity AND c.relforcerowsecurity FROM pg_catalog.pg_class c WHERE c.oid = 'public.shortfall_applications'::regclass) THEN
        RAISE EXCEPTION USING
            MESSAGE = 'shortfall_applications has lost its tenant_isolation policy or forced row security, or has another policy beside it (v5.4.2-27)',
            ERRCODE = 'invalid_grant_operation';
    END IF;
    -- r2: one carry per undo.
    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_indexes x JOIN pg_catalog.pg_class i ON i.relname = x.indexname AND i.relnamespace = 'public'::regnamespace
                     JOIN pg_catalog.pg_index k ON k.indexrelid = i.oid
                    WHERE x.schemaname = 'public' AND k.indisvalid
                      AND x.indexdef = 'CREATE UNIQUE INDEX customer_credits_one_per_shortfall_undo ON public.customer_credits USING btree (reissues_shortfall_application_id) WHERE (reissues_shortfall_application_id IS NOT NULL)') THEN
        RAISE EXCEPTION USING
            MESSAGE = 'customer_credits_one_per_shortfall_undo is missing, changed or not valid (one shortfall_reissue credit per undo; v5.4.2-27)',
            ERRCODE = 'invalid_grant_operation';
    END IF;
    -- The target's cap is tally_app's alone, and tally_app's.
    IF has_function_privilege('public', 'public.check_shortfall_repaid(uuid, date)', 'EXECUTE')
       OR has_function_privilege('tally_core', 'public.check_shortfall_repaid(uuid, date)', 'EXECUTE')
       OR NOT has_function_privilege('tally_app', 'public.check_shortfall_repaid(uuid, date)', 'EXECUTE') THEN
        RAISE EXCEPTION USING
            MESSAGE = 'check_shortfall_repaid is executable beyond tally_app, or not by tally_app (v5.4.2-27)',
            ERRCODE = 'invalid_grant_operation';
    END IF;
END;
$fn$;
COMMENT ON FUNCTION public.assert_shortfall_guard_invariants() IS
    'v5.4.2-27. Raises unless every guard of v5.4.2-27 (the shortfall application''s freeze, stamp, append-only, retention and enforcement triggers; the source''s bounce guards on account_ledger and payments) exists exactly as defined (PostgreSQL 16''s rendering) and ENABLE ALWAYS; its constraints exist exactly as defined and validated; tally_app may only SELECT and INSERT shortfall_applications, tally_core only read it, PUBLIC nothing; it keeps its tenant policy, alone, and forced row security; check_shortfall_repaid is tally_app''s alone. r2: the carry''s triggers, constraints and unique index; each privilege asked alone (Codex S1), tally_core''s SELECT required and REFERENCES and TRIGGER refused. Checks definitions, not the bodies of the functions they call (-23''s assert_cash_guard_invariants checks check_cash_source and cash_source_draws). Run in the patch tail and in CI.';
REVOKE ALL ON FUNCTION public.assert_shortfall_guard_invariants() FROM PUBLIC, tally_app, tally_core;

DO $$ BEGIN
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
-- END PATCH v5.4.2-27
-- ============================================================================

COMMIT;
\endif
