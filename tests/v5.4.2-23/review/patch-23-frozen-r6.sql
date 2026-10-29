-- ============================================================================
-- PATCH v5.4.2-23 — wave 2, part 2: cash. Reversals under one rule, the
--                    counters derived, payment application per bill line,
--                    credits from overpayment
-- ============================================================================
-- Authority:   Ryan, 2026-10-16: "split it, go with the default" (cash is
--              -23, M X A C; -24 is U L). Kyle's rulings R-02, R-05, R-06,
--              K-05, K-07 (GBM kyle-decisions-2026-10-15-…), D7-1, D7-2
--              (wu5-wu6-kyle-decisions-2026-07-10.md); Q1 (a) (Ryan,
--              2026-10-15: a status stays a column, moves forward only, and
--              each move names the add-only row behind it).
-- Spec:        application/wave2-build-2026-10-15/v5.4.2-23-design.md and
--              source-inventory-wave2.md (M, X, A, C; "-23 triage").
--              MEANING-CHANGING: the cash tables' counters become derived
--              positions, applications move to bill lines, and a status no
--              longer changes without its row. The cash tables are empty
--              wherever this has been applied; a database that holds cash
--              rows or bill lines stops at the precondition, before anything
--              is written.
--
-- ----------------------------------------------------------------------------
-- What changes
-- ----------------------------------------------------------------------------
--   Reversals (X; R-02, CI-017)
--   * A ledger row is a reversal if and only if it names an entry. void_
--     reversal, nsf and write_off_recovery must name one; an adjustment (a
--     partial reversal) and a write_off (-22's nested write-off) may; no other
--     type names one (r2: a payment row does not undo a charge) (X1). A row
--     naming an entry is dated no later than today.
--   * r3 (Kyle, K-10 1 = A): a refund is its own movement of money, not an
--     undo of the payment it returns. Its row names nothing and is more than
--     0 (money paid out). R-02's cap counts reversals only, so the bank's
--     full return of a refunded payment fits, and the customer owes what was
--     refunded (50 paid, 30 refunded, 50 returned: 30 owed).
--   * r3: one arrival entry per source (a payment's posting row, a credit's
--     credit_issued row; unique indexes), checked at its write: under one
--     label, of its own kind, at minus its amount, on its own account; an
--     overpayment credit posts none. r4: written only for a payment still
--     pending or a credit still active, under its lock; its money counts
--     from the entry's own date (an ACH payment settles after its date).
--   * A reversal names an entry of its own tenant and customer (the FK, X1b):
--     money moved between customers is a transfer.
--   * -22's write-off rule, made general (X2): a reversal has the opposite
--     sign of its entry, neither zero; it is dated on or after it; and for
--     every entry on the path up to the root, the net of that entry's tree
--     lies between 0 and minus the entry, at every date. One advisory lock
--     per tree, on its root; READ COMMITTED only; a row is not recorded
--     before a row already in its tree (40001 retry; 23514 for a chosen
--     time); every ledger row is recorded at a finite time already reached.
--     A recovery still names a write_off, and only a recovery names one.
--   * A reversal tree stays at most 1000 deep, as in -22 (R1).
--   * void_invoice() reverses what is left of the bill's charge, under the
--     head and the tree's lock; nothing left, no row (X3). -21's one void
--     per entry stays (X4).
--
--   Add-only money (M; R-05, CI-013, Q1 (a))
--   * The counters go: payments.applied_amount / unapplied_amount /
--     deposit_status, customer_credits.applied_amount / remaining_amount,
--     invoices.amount_paid / balance. Read instead through
--     payment_position_as_of, customer_credit_position_as_of,
--     invoice_line_position_as_of and invoice_position_as_of (a money date
--     and a recorded instant, both required). credit_aging_statistics is
--     rebuilt on the derived remainder.
--   * customer_credits.status loses fully_applied (a counter in disguise);
--     r3 (Ryan, 2026-10-21): payments and credits lose refunded, and credits
--     donated, for the same reason. As final labels they left a refund check
--     that bounced, or a donation keyed in error, with no record; read from
--     the positions, a failed refund or an undone donation frees the money.
--     Payments: pending, posted, nsf, reversed, voided. Credits: active,
--     escheated, voided.
--   * Payments, customer credits and one-off charges are fixed from insert
--     (amount, identity, lineage, designation, restriction, class); a
--     reference that arrives later is written once.
--   * A payment is born pending and a credit active, with no cause (r2).
--     A status moves forward only and names its row in status_cause_id: a
--     payment's posting entry (of its own kind, with nothing under it), the
--     nsf row or other reversal that leaves nothing of that entry; a credit's
--     reversal that leaves nothing of its credit_issued entry (an
--     overpayment credit's void names nothing) or its escheated_to_state
--     event. Each move is stamped
--     status_recorded_at by the database and runs at READ COMMITTED. Money
--     that bounced, was reversed or never arrived is not still applied or
--     held as a credit; escheated means nothing is left
--     (guard the act).
--   * A source gives money only once it is on the ledger (a payment's
--     posting entry, a credit's credit_issued entry), and the ledger row
--     that would undo it waits until nothing draws on it (r2) and (r3, K-10
--     2) no refund of the payment is waiting to go out: an operator cancels
--     the refund first; nothing cancels it automatically.
--   * r3 (Kyle, K-10): positions read what stands on the ledger (received,
--     issued): the arrival entry less what was taken back under it.
--   * r4 (Opus B3, Fable B1; K-10): a payment holds one live overpayment
--     credit. Its bounce waits only while the credit is applied or has a
--     refund pending; what the credit paid out stands, and what it still
--     held goes with the payment (the credit's issued is its amount less
--     what was taken back under the payment's posting entry).
--   * r4: a row taking money away under a posting or credit_issued entry
--     waits while the source is drawn on; a row giving money back does not,
--     but nothing is given back to a source that has ended (a bounced payment,
--     a voided or escheated credit; a re-presented check is a new payment).
--   * r4 (Ryan, 2026-10-21): nothing comes back to an escheated credit. It is
--     not escheated while a refund of it is pending; a donation is not undone
--     onto it; a refund of it that comes back after the escheat goes, in the
--     same transaction, into a new credit (origin refund_reissue, naming the
--     refund), checked at commit. A reissue posts no ledger row, draws on its
--     credit, and is not voided back onto an escheated one.
--   * r4 (Codex B1): a row under a donation of a credit is a draw (capped)
--     when it takes money again, an undo when it gives it back.
--   * r5 (Opus B1, Fable B1, Codex S1; K-10): one split of what is taken
--     back under a payment's posting entry between the payment and its
--     overpayment credit (overpayment_split), read by both positions, both
--     caps and the escheat check: a take-back comes first out of what the
--     credit still held at its instant, then out of the payment's own part;
--     what neither held falls on the credit up to its amount, then on the
--     payment; a take-back recorded before the credit is the payment's; a
--     give-back goes to the credit first. A draw on either is also capped by
--     the two together (the payment less what was taken back: Kyle's refund
--     cap), and a draw on the credit takes the payment's lock first.
--   * r5 (Opus B2, Fable S1, Codex B1): nothing more goes under a refund's
--     posting row once the refund is nsf or reversed (a re-sent refund is a
--     new refund); r5 (Fable B2, Codex B2): no give-back under a payment
--     whose overpayment credit is escheated.
--   * r5 (Codex B3, B4; Opus S1): a reissue carries what is left on its
--     credit, at most the refund, dated on or after the refund's return; the
--     commit check requires nothing positive left; a status time is never in
--     the future or infinite, for any role.
--   * r6 (Opus B1, Codex B2; K-10): which side carries a shortfall is
--     decided when a position is read: the split fixes what each side held
--     when a take-back was recorded; if one side then reads a deficit while
--     the other holds money, the side holding money covers it as far as it
--     can (overpayment_absorbed_as_of). Each position then equals what its
--     cap admits (its own side, with the cap on the two together), and the
--     two add up to the ledger. A draw uses only its own side's money.
--   * r6 (Opus B2, Fable B1): a row under a payment's posting entry is not
--     recorded before a draw already counted on the payment or its credits,
--     the credit itself, or a draw that has since left (check_cash_order,
--     the draws' own rule: 40001, 23514 for a chosen time).
--   * r6 (Codex B3): rows of one instant are split in the tree's order, a
--     row before the rows under it.
--   * r6 (Codex B4): a status time changes only with its status, for every
--     role; a history load's chosen move is not before a row already
--     recorded on the source's lineage (cash_lineage_recorded).
--   * r6 (Codex B1): a refund_reissue credit descended from an overpayment
--     credit holds its payment's money (overpayment_root, overpayment_family):
--     its draws take the payment's lock and are held with the payment and
--     its credit; it holds up the bounce and the move to nsf while applied or
--     with a refund pending; a take-back takes a share of what it holds
--     (overpayment_shares: the overpayment credit first, then each reissue
--     in recorded order; a give-back restores the latest share first), and
--     its own cap counts that share.
--   * r6 (Opus S2, Fable S2): a give-back under a payment whose credit is
--     escheated is refused only as far as the credit would then hold money.
--   * Payments and customer credits are stamped created_at by the database
--     (a superuser's history load keeps its own), as the ledger is. r6
--     (Opus S1): a superuser's own created_at on a payment, credit,
--     application or remittance is a finite time already reached.
--
--   Payment application (A; R-06, K-05, D7-1, CI-049, CI-050)
--   * invoice_applications is per bill line, add-only, from a payment or a
--     credit (typed FKs, one of them), of the bill's customer. A mistake is
--     undone by a negative row naming it (basis undo, reason, user), at most
--     its amount; an undo is never undone.
--   * Every bill line carries its regulated/unregulated class, checked at
--     issue against its one-off charge or its rate item's version (A1b).
--   * Caps, after the statement's rows are in: a payment's applications,
--     overpayment credits and refunds, with what was taken back on the
--     ledger under its posting entry (r3, Kyle's K-10 refund cap), never
--     exceed it; a credit's applications, refunds, donations (net of their
--     undos, r3) and remittances, with what was withdrawn, never exceed it; a
--     line's applications never exceed it; at every date; not recorded
--     before the source reached the ledger (r3), a row already counted, or a
--     draw that has since left it (r3).
--     Only a positive line of an issued, unvoided bill takes money, from a
--     posted non-deposit payment or an active credit, on or after both.
--   * basis: oldest_first, restriction, floor_over_restriction (each citing
--     the tariff row in force), operator_override (reason, user), undo.
--   * The restriction an agency payment carries (payer_class, restricted_to_
--     invoice_id, restricted_to_line_item_id) (A6): a restricted payment's
--     row says restriction for its target, floor_over_restriction for a
--     regulated line ahead of an unregulated target, or operator_override.
--     Which of restriction and floor wins is Kyle's to rule; the record
--     carries either.
--   * The within-bill order is a rule-terms tariff (payment_allocation_
--     tariffs, kind payment_allocation_tariff v1): two lists of bill-line
--     charge types, regulated first by the shape, every type exactly once.
--     Its law table (payment_allocation_rules, kind payment_allocation v1)
--     holds two Texas gas rows, both delegating (K-05: no statewide order;
--     a city is outside GURA). No default tariff row (K-07).
--   * tenants.payment_allocation_strategy is dropped (K-05 leaves one value).
--
--   Credits from overpayment (C; R-06)
--   * customer_credit_approvals: the payment, the amount, the approving user,
--     the database's time; append-only. A credit of origin overpayment names
--     its approval and equals its payment and amount (FK on all five); one
--     approval, one credit (C1).
--   * overpayment_handling loses apply_to_specific_invoices (C2).
--
--   The freeze and the invariants
--   * An application is dated applied_on and frozen by the close (-22 P2);
--     r3 (Codex B6): so is an escheat remittance, by its UTC day.
--   * r3 (Fable S5): a donation or remittance is on its credit's own account.
--   * assert_cash_guard_invariants(); assert_periods_guard_invariants() and
--     assert_seal_role_invariants() re-issued for the changes above.
--
-- ----------------------------------------------------------------------------
-- Lock order and isolation (a rule, in -22's form)
-- ----------------------------------------------------------------------------
--   A money write takes, in this order:
--     1. its tenant's close head, FOR SHARE (the freeze; the void takes it
--        explicitly before its charge's tree);
--     2. for a reversal, its tree's advisory lock (the root's), then, if it
--        undoes a payment's posting entry or a credit's credit_issued entry,
--        that source's lock; for an application, the cited tariff row's lock
--        (shared, rule_row_cite), then its source's lock (the payment or
--        credit), then its line's; for an overpayment credit, a refund, a
--        donation or an escheat, its source's lock;
--     3. nothing else.
--   The void takes its own invoice row (FOR UPDATE) before the head. A
--   status move takes its own row (the UPDATE) and then its source's lock;
--   r3: a refund that leaves (voided, nsf, reversed) then takes the lock of
--   the payment or credit it returns, so a draw on that source sees the money
--   freed. r4: a source is locked before what draws on it: the credit's void
--   takes its payment, then itself; a reissue's void takes the credit its
--   refund came from, then itself. A posting or credit_issued row takes its
--   source's lock (after the head) to read its status. r5: a draw on an
--   overpayment credit takes its payment's lock, then the credit's (so the
--   bounce guard and the move to nsf, holding the payment's, see it); a
--   give-back under a payment takes the payment's, then its credit's; a row
--   under a refund's posting row takes the tree's, then the refund's.
--   An approval and a status move take no head: they move no money, and the
--   rows that do take it. The close's rule (-22) is unchanged: head, period,
--   the closing user's row, the tenant row.
--   A transaction that holds a later lock and waits — directly, or through
--   other transactions — for an earlier one can deadlock; so can two
--   writers taking locks of one rank in opposite orders (two trees, two
--   sources, two lines, a multi-row statement). PostgreSQL aborts one, which
--   writes nothing. No list of shapes is promised complete: every writer
--   retries 40P01 and 40001. Post each act in a transaction of its own: the
--   order above holds for one act per transaction (r3, Opus N4); a donation
--   and then a withdrawal of the same credit in one transaction take the
--   source before the tree and can deadlock with a writer doing the reverse.
--   Every draw, application, reversal and status move runs at READ
--   COMMITTED (25000 otherwise): it must see every row committed while it
--   waited; r5 (Fable B3): so does every arrival row and donation. Each
--   reads its source after taking the source's lock.
--   r6 (Fable S1): a refund of a credit holding a payment's money that
--   leaves takes the payment's lock, then the credit's (the return, the
--   move and the reissue in one transaction: payment, then credit); a draw
--   on a reissue holding a payment's money takes the payment's lock first,
--   as a draw on the overpayment credit does.
--
-- ----------------------------------------------------------------------------
-- Residuals (left on purpose)
-- ----------------------------------------------------------------------------
--   R1. The depth bound stays 1000. The cap nets every entry on a new
--       row's path at every date: one row appended at depth d costs about
--       d squared (measured: 2 ms at 64, 70-170 ms at 500, 0.3-0.8 s at
--       1000), and a whole chain posted in one statement about d cubed
--       (200 deep about 2 s, 300 deep about 7 s). A deeper
--       correction is a new entry.
--   R2. Closed in r2: a position reads a refund's and a credit's status at
--       its recorded instant (status_recorded_at). A position at (d, R) is
--       fixed once R is older than every open transaction (-22's model).
--   R3. Invoice status paid / partial stays app-written lifecycle (CI-012)
--       and can disagree with invoice_position_as_of.
--   R4. A void leaves the bill's applications in place; the core undoes them
--       and applies the money to the rebill.
--   R5. payment_allocation_order_gap() repeats invoice_line_items' charge
--       type list; a new type is added to both.
--   R6. A tax or other line without a source is classed by the core; the
--       database checks only lines with a one-off charge or a rate item.
--   R7. Allocation itself (choosing bills and lines, the floor, notifying a
--       payer whose restriction was not honoured) is the core's.
--   R8. The -22 tests that assumed a cross-customer reversal (R10f, R12o,
--       W13), a same-sign row under a recovery (R10, R12n), a reversal dated
--       before its entry (W14) and a ledger row recorded in the future (W8,
--       C19) are rewritten for X1b, X2 and the time rule; -19's payment
--       moves (P9c-P9g, races C8/C9) for M2. r2: -19 and -21 post their
--       payments and credits on the ledger (born pending; money stands on
--       the ledger); -22 R12n keeps its nested write-off.
--   R9. The tariff an application cites is not matched to the line's
--       service and system: the bill carries neither; choosing it is the
--       core's (R7).
--   R10. Several deposit refund credits against one deposit: -15's events
--       cap the deposit, not this patch.
--   R11. A long chain posted in one statement holds the tree and the head
--       for minutes: tally_app's statement_timeout (DEPLOY-VERIFICATION).
--   R12. r3: a refund whose posting row is undone counts as refunded until
--       it moves to nsf or reversed (its status is the record of the
--       failure); the move names the undo, so the app writes both together.
--   R13. r3 (K-10 2): the bounce screen shows a pending refund with a
--       one-click cancel; that is the app's, not the database's.
--   R14. r3 (K-10 3): a hold on refunds from a payment still inside its
--       return window is each utility's policy, a tenant setting off by
--       default, read by the app or core; nothing here. Where the setting is
--       stored is additive later.
--   R15. r3: a payment's posting entry or a credit's credit_issued entry is
--       not taken back, even in part, while it is applied or a refund of it
--       is pending; for a payment, also while its overpayment credit is
--       applied or has a refund pending (r4, K-10: what the credit holds or
--       paid out does not hold the bounce up; r5, Fable S2). A credit's
--       entry also waits on its refunds, donations and remittances. Only a
--       row taking money away waits; a withdrawal comes first, then the draws
--       on what is left.
--   R16. r4: an overpayment credit's standing is read from its payment's
--       posting entry, which is why a payment holds one live credit; holding
--       an overpayment in two credits would need an order between them. r5
--       (Opus N1): so a second hold from a payment whose first credit was
--       drawn on is refused, and the first cannot be voided while drawn on;
--       the payment's own remainder is applied or refunded directly instead.
--   R17. r5, r6 (Opus B2, Fable N1): the split reads rows by their recorded
--       instant, and a row under a payment's posting entry is not recorded
--       before a draw already counted on the payment or its credits (r6), so
--       across transactions it follows the order the rows were made in.
--       Within one instant (one transaction) it reads that instant's draws as
--       already made, so a draw in the same transaction can move a share,
--       and the per-side caps are then the cap on the two together. K-10's
--       refund cap holds for any reading. Post each act in a transaction of
--       its own.
--   R18. r6 (Fable N3): a refund's return keyed in error (the check had
--       cleared) has no correction once the refund is nsf: the status is
--       terminal and nothing more goes under its posting row. A new refund
--       records the money going out again; the record then shows two refunds.
--   R19. r6 (Fable N4): the app passes no status_recorded_at; the database
--       stamps it. A value the app passes is checked (one in the future is
--       refused) before the stamp replaces it.
--   R20. r6 (Codex B1): how a take-back is shared among an overpayment
--       credit and its reissues (the overpayment credit first, then each
--       reissue in recorded order; a give-back the latest share first) is an
--       attribution, not a ruling: the money is held whole by the cap on the
--       payment and its credits together.
--   R21. r6 (Opus N6): overpayment_shares walks the payment's tree once per
--       read, and each take-back reads what each credit had given at its
--       instant. Measured 2026-10-29 (one at a time, history loads): a
--       payment with its credit, 2 reissues and 4 rows under its posting
--       entry reads a position in 2-4 ms and takes a draw in about 5 ms (up
--       to 90 ms on a session's first call, while plans are made); with 10
--       reissues and 50 rows, 10-25 ms and 20-100 ms.
--
-- ----------------------------------------------------------------------------
-- Kyle's K-10 (2026-10-21; gas-billing-memory kyle-decisions-2026-10-21-
-- refund-then-bounce.md)
-- ----------------------------------------------------------------------------
--   1 = A: a refund is its own movement of money (X1, the caps above).
--   2: a pending refund blocks the bounce until an operator cancels it.
--   3: a return-window hold is tenant policy, not schema (R14).
--   Still Kyle's: restriction against the floor (A6), and the floor once its
--   target is paid; the record carries either answer.
--
-- Tests. battery-23 (344 checks), races/cash-23.sh (CR1-CR24, 38 results),
--   mutations-23.py (210 mutations; r5 retired N145, a lock made
--   redundant). assert_cash_guard_invariants() runs
--   in the tail and in CI.
--
-- PRECONDITION. v5.4.2-22 applied (tu.sql). No payments, customer credits,
--   applications or bill lines, and no tenant with overpayment_handling =
--   apply_to_specific_invoices. Applied by a superuser, under READ COMMITTED.
--   A second run finds customer_credit_approvals and skips the whole patch
--   (psql's \if): apply it with psql.
-- ============================================================================

SELECT to_regclass('public.customer_credit_approvals') IS NOT NULL AS already \gset
\if :already
DO $$ BEGIN RAISE NOTICE 'v5.4.2-23: already applied (customer_credit_approvals exists); nothing to do'; END $$;
\else
BEGIN;

-- The cash tables are empty where this patch has been applied so far (nothing
-- is live). The counters and the retired values below are dropped, not
-- migrated: a database holding cash rows stops here and says so, so the
-- operator decides, rather than the patch guessing (memory "design permanent").
DO $$
DECLARE
    v_n bigint;
BEGIN
    SELECT (SELECT count(*) FROM public.payments) + (SELECT count(*) FROM public.customer_credits)
         + (SELECT count(*) FROM public.invoice_applications)
      INTO v_n;
    IF v_n > 0 THEN
        RAISE EXCEPTION USING
            MESSAGE = format('v5.4.2-23 changes what the cash tables mean (the counters become derived positions, applications move to bill lines): this database holds %s payments, customer credits or applications. Migrate them first (DEPLOY-VERIFICATION -23)', v_n),
            ERRCODE = 'object_not_in_prerequisite_state';
    END IF;
    IF EXISTS (SELECT 1 FROM public.tenants WHERE overpayment_handling = 'apply_to_specific_invoices') THEN
        RAISE EXCEPTION USING
            MESSAGE = 'v5.4.2-23 retires overpayment_handling = apply_to_specific_invoices (K-05: a payment designates a deposit or a bill, never a bill of its choosing): a tenant holds it; choose hold_as_credit or refund_automatically first',
            ERRCODE = 'object_not_in_prerequisite_state';
    END IF;
    IF EXISTS (SELECT 1 FROM public.invoice_line_items) THEN
        RAISE EXCEPTION USING
            MESSAGE = 'v5.4.2-23 adds invoice_line_items.regulatory_class, NOT NULL: this database holds bill lines; classify them first (DEPLOY-VERIFICATION -23)',
            ERRCODE = 'object_not_in_prerequisite_state';
    END IF;
END $$;


-- ----------------------------------------------------------------------------
-- 1. Reversals (X; R-02, CI-017)
-- ----------------------------------------------------------------------------
-- X1. The reversal types by nature name their entry; an adjustment (a
-- partial reversal) and a write-off may.
ALTER TABLE public.account_ledger
    ADD CONSTRAINT account_ledger_reversal_types_name_check
        CHECK (transaction_type NOT IN ('void_reversal', 'nsf', 'write_off_recovery')
               OR reverses_ledger_entry_id IS NOT NULL);
-- r2 (Fable S7): only an undo names an entry, and a write-off (-22's nested
-- write-off: part of a recovery that came back is written off under it). A
-- payment, a charge, a transfer or a donation is new money or a move of
-- money, not an undo: a payment row naming a charge would zero it for the
-- void. A donation or escheat points at
-- its credit through reference_id and is capped as a draw (section 7).
-- r3 (Kyle, K-10 1 = A): a refund is its own movement of money, not an undo
-- of the payment it returns. Its row names nothing; it points at its refund
-- through reference_id, and is capped as a draw on the refunded payment or
-- credit (section 7). The bank's return of a refunded payment is then the
-- whole payment (R-02's cap counts reversals only).
ALTER TABLE public.account_ledger
    ADD CONSTRAINT account_ledger_reversal_types_only_check
        CHECK (reverses_ledger_entry_id IS NULL
               OR transaction_type IN ('void_reversal', 'nsf', 'write_off_recovery', 'adjustment', 'write_off'));
-- r3 (Opus K1-A1): naming nothing, a refund row has no sign from X2. It is
-- money paid out to the customer: more than 0.
ALTER TABLE public.account_ledger
    ADD CONSTRAINT account_ledger_refund_sign_check
        CHECK (transaction_type <> 'refund' OR amount > 0);

-- X1b. A reversal names an entry of its own tenant and customer: aging and
-- the close net a reversal only within its customer (-22), and money moved
-- between customers is a transfer, not a reversal.
ALTER TABLE public.account_ledger
    ADD CONSTRAINT account_ledger_id_tenant_customer_key UNIQUE (id, tenant_id, customer_id);
ALTER TABLE public.account_ledger DROP CONSTRAINT account_ledger_reverses_ledger_entry_fkey;
ALTER TABLE public.account_ledger
    ADD CONSTRAINT account_ledger_reverses_ledger_entry_fkey
        FOREIGN KEY (reverses_ledger_entry_id, tenant_id, customer_id) REFERENCES public.account_ledger (id, tenant_id, customer_id);

-- r3 (Opus S1, Codex B3, Fable S2): one arrival entry per source. A payment
-- reaches the ledger by one posting row, a credit by one credit_issued row:
-- a second would credit the customer twice, and a void reversing one would
-- leave the other standing. enforce_ledger_reversal checks the row itself
-- (its label, kind, amount and account).
CREATE UNIQUE INDEX account_ledger_payment_arrival_key ON public.account_ledger (reference_id)
    WHERE reference_type = 'payment' AND transaction_type IN ('payment', 'deposit', 'refund');
CREATE UNIQUE INDEX account_ledger_credit_arrival_key ON public.account_ledger (reference_id)
    WHERE reference_type = 'customer_credit' AND transaction_type = 'credit_issued';

-- X2. -22's write-off rule, made general: every entry is the root of its tree.
-- The trigger fires on every insert: a row that names nothing may still
-- become a root, so its recorded time is checked too.
DROP TRIGGER enforce_write_off_recovery ON public.account_ledger;
DROP FUNCTION public.enforce_write_off_recovery();

-- The depth bound stays -22's 1000 (R1), and -22's lineage walk is unchanged;
-- its comment named the recovery trigger dropped above.
COMMENT ON FUNCTION public.enforce_ledger_lineage_acyclic() IS
    'v5.4.2-22 r2, r3; v5.4.2-23 (comment only). AFTER INSERT on account_ledger, for a row naming an entry: walks the chain of reverses_ledger_entry_id up from the new row and refuses it if the chain comes back to it (rows of one statement naming each other), or (r3) does not reach an original within 1000 entries — a longer chain, or one entering a loop. A cycle has no original, so aging could not place its amount. Fires before enforce_ledger_reversal (trigger name order).';

CREATE OR REPLACE FUNCTION public.ledger_tree_ids(p_root uuid) RETURNS uuid[]
    LANGUAGE sql STABLE
    SET search_path = public, pg_temp
    SET enable_seqscan = off
    SET enable_hashjoin = off
    SET enable_mergejoin = off
    AS $$
    -- Every row under p_root, at any depth (p_root excluded). Each step is
    -- found by the reversal link alone (memory "recursive walks: pin the
    -- plan"); the FK keeps the tree within one customer.
    WITH RECURSIVE down(id) AS (
        SELECT l.id FROM public.account_ledger l WHERE l.reverses_ledger_entry_id = p_root
        UNION
        SELECT l.id FROM down d JOIN public.account_ledger l ON l.reverses_ledger_entry_id = d.id
    )
    SELECT coalesce(array_agg(d.id), '{}') FROM down d
$$;
COMMENT ON FUNCTION public.ledger_tree_ids(uuid) IS
    'v5.4.2-23 (X2). The ids of every account_ledger row under p_root at any depth, p_root excluded. Walks the reversal link only, with sequential scans, hash and merge joins off (the -22 walks'' lesson). Within one customer by the reversal FK. Termination: lineage is acyclic (enforce_ledger_lineage_acyclic).';
REVOKE ALL ON FUNCTION public.ledger_tree_ids(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ledger_tree_ids(uuid) TO tally_app, tally_core, tally_void;

CREATE OR REPLACE FUNCTION public.ledger_entry_remaining(p_entry uuid) RETURNS numeric
    LANGUAGE sql STABLE
    SET search_path = public, pg_temp
    SET enable_seqscan = off
    SET enable_hashjoin = off
    SET enable_mergejoin = off
    AS $$
    -- What is left of an entry after everything under it: its amount plus the
    -- net of its tree. Live (every row visible to the caller): the void reads
    -- it under the tree's lock (X3).
    SELECT e.amount + coalesce((SELECT sum(l.amount) FROM public.account_ledger l
                                 WHERE l.id = ANY (public.ledger_tree_ids(e.id))), 0)
      FROM public.account_ledger e WHERE e.id = p_entry
$$;
COMMENT ON FUNCTION public.ledger_entry_remaining(uuid) IS
    'v5.4.2-23 (X3). What is left of a ledger entry: its amount plus the net of its whole tree. Live, not as-of: void_invoice() reads it while holding the tree''s lock, so nothing can join the tree between the read and its reversal. NULL for an unknown or invisible entry.';
REVOKE ALL ON FUNCTION public.ledger_entry_remaining(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ledger_entry_remaining(uuid) TO tally_app, tally_core, tally_void;

CREATE OR REPLACE FUNCTION public.ledger_tree_root(p_entry uuid) RETURNS uuid
    LANGUAGE sql STABLE
    SET search_path = public, pg_temp
    SET enable_seqscan = off
    SET enable_hashjoin = off
    SET enable_mergejoin = off
    AS $$
    -- The root of p_entry's tree: follow the reversal link up until an entry
    -- names nothing. Bounded as the lineage walk is (1000).
    WITH RECURSIVE up(id, next_id, depth) AS (
        SELECT l.id, l.reverses_ledger_entry_id, 1 FROM public.account_ledger l WHERE l.id = p_entry
        UNION ALL
        SELECT l.id, l.reverses_ledger_entry_id, u.depth + 1
          FROM up u JOIN public.account_ledger l ON l.id = u.next_id
         WHERE u.depth < 1000
    )
    SELECT u.id FROM up u WHERE u.next_id IS NULL
$$;
COMMENT ON FUNCTION public.ledger_tree_root(uuid) IS
    'v5.4.2-23 (X2, X3). The root of a ledger entry''s tree (the entry itself when it names nothing). NULL for an unknown or invisible entry, or a chain past 1000 (which the lineage walk refuses at insert). void_invoice() locks the root of the charge it reverses, found by this walk rather than assumed: the lock is the tree''s (r3, Codex S3: a charge names no entry under X1, and the walk does not rely on it).';
REVOKE ALL ON FUNCTION public.ledger_tree_root(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ledger_tree_root(uuid) TO tally_app, tally_core, tally_void;

CREATE OR REPLACE FUNCTION public.ledger_tree_lock_key(p_root uuid) RETURNS bigint
    LANGUAGE sql IMMUTABLE
    SET search_path = public, pg_temp
    AS $$ SELECT pg_catalog.hashtextextended('ledger_tree:' || p_root::text, 0) $$;
COMMENT ON FUNCTION public.ledger_tree_lock_key(uuid) IS
    'v5.4.2-23 (X2). The advisory lock key of the ledger tree rooted at p_root. A reversal takes it (after its tenant''s close head); void_invoice() takes it before reading what is left of the charge.';
REVOKE ALL ON FUNCTION public.ledger_tree_lock_key(uuid) FROM PUBLIC;
-- r2 (Fable N5): a read-only role takes no lock.
GRANT EXECUTE ON FUNCTION public.ledger_tree_lock_key(uuid) TO tally_app, tally_void;

CREATE OR REPLACE FUNCTION public.enforce_ledger_reversal() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    SET enable_seqscan = off
    SET enable_hashjoin = off
    SET enable_mergejoin = off
    AS $$
DECLARE
    v_parent   public.account_ledger%ROWTYPE;
    v_root     public.account_ledger%ROWTYPE;
    v_anc      public.account_ledger%ROWTYPE;
    v_down     uuid[];
    v_down_amt numeric[];
    v_j        integer;
    v_path     uuid[];
    v_net      numeric;
    v_on       date;
    v_later_id uuid;
    v_later_at timestamptz;
    v_src      uuid;
    v_pay      public.payments%ROWTYPE;
    v_credit   public.customer_credits%ROWTYPE;
    v_kind     text;
    c_max      CONSTANT integer := 1000;
BEGIN
    -- -22 r5, made general: every row is recorded at a finite time already
    -- reached. A root recorded in the future would make every later row of
    -- its tree "recorded before" it, and the retry below could never succeed.
    IF NOT pg_catalog.isfinite(NEW.created_at) OR NEW.created_at > pg_catalog.clock_timestamp() THEN
        RAISE EXCEPTION USING
            MESSAGE = format('account_ledger %s is recorded at a non-finite or future time (%s): every ledger row is recorded at a time already reached (R-02, v5.4.2-23)', NEW.id, NEW.created_at),
            ERRCODE = 'check_violation';
    END IF;
    -- r5 (Fable B3): every row read under a source's or a tree's lock (an
    -- arrival row, a donation, a reversal) is written at READ COMMITTED: under
    -- REPEATABLE READ the read after the lock comes from a snapshot taken
    -- before it, and misses a move or a row committed while it waited.
    IF (NEW.reverses_ledger_entry_id IS NOT NULL
        OR (NEW.transaction_type IN ('payment', 'deposit', 'refund') AND NEW.reference_type IN ('payment', 'refund'))
        OR (NEW.transaction_type IN ('credit_issued', 'donation') AND NEW.reference_type = 'customer_credit'))
       AND pg_catalog.current_setting('transaction_isolation') <> 'read committed' THEN
        RAISE EXCEPTION USING
            MESSAGE = format('account_ledger %s is read against its source or tree under a lock, so it is posted at READ COMMITTED (this transaction is %s): it must see every row committed while it waited (R-02, v5.4.2-23)', NEW.id, pg_catalog.current_setting('transaction_isolation')),
            ERRCODE = 'invalid_transaction_state';
    END IF;
    -- r3 (Opus B1, S1; Codex B2, B3; Fable S1, S2): a source's arrival entry
    -- is its own. A posting row (payment, deposit or refund) that references
    -- a payment names it under one label, payment, on the payment's own
    -- account, of the payment's kind, at minus its amount. A credit_issued
    -- row that references a credit is on the credit's account at minus its
    -- amount, and an overpayment credit posts none (its money is its
    -- payment's). One per source: the unique indexes below.
    IF NEW.transaction_type IN ('payment', 'deposit', 'refund') AND NEW.reference_type IN ('payment', 'refund') THEN
        -- r4 (Opus B2, Fable S1): read under the payment's lock (its moves
        -- take it), so a payment voided or posted meanwhile is seen.
        PERFORM pg_catalog.pg_advisory_xact_lock(public.cash_source_lock_key('payment', NEW.reference_id));
        SELECT * INTO v_pay FROM public.payments p WHERE p.id = NEW.reference_id;
        IF NOT FOUND OR v_pay.tenant_id <> NEW.tenant_id OR v_pay.customer_id <> NEW.customer_id THEN
            RAISE EXCEPTION USING
                MESSAGE = format('account_ledger %s posts payment %s: a posting row is on the account of its payment, of its own customer (R-05, v5.4.2-23)', NEW.id, NEW.reference_id),
                ERRCODE = 'foreign_key_violation';
        END IF;
        v_kind := CASE WHEN v_pay.refunds_payment_id IS NOT NULL OR v_pay.refunds_customer_credit_id IS NOT NULL THEN 'refund'
                       WHEN v_pay.is_deposit THEN 'deposit' ELSE 'payment' END;
        IF NEW.reference_type <> 'payment' OR NEW.transaction_type <> v_kind OR NEW.amount <> -v_pay.amount THEN
            RAISE EXCEPTION USING
                MESSAGE = format('account_ledger %s (%s, %s, %s) posts payment %s: a posting row names its payment under reference_type payment, is of its own kind (payment, deposit or refund), at minus its amount (%s) (R-05, v5.4.2-23)',
                                 NEW.id, NEW.transaction_type, NEW.reference_type, NEW.amount, v_pay.payment_number, -v_pay.amount),
                ERRCODE = 'check_violation';
        END IF;
        -- r4: only for a payment still pending (a voided payment's money never
        -- arrived; a cancelled refund was never paid out).
        IF v_pay.status <> 'pending' THEN
            RAISE EXCEPTION USING
                MESSAGE = format('account_ledger %s posts payment %s, which is %s: a posting row is written for a payment still pending, before its move to posted (R-05, v5.4.2-23)', NEW.id, v_pay.payment_number, v_pay.status),
                ERRCODE = 'check_violation';
        END IF;
    ELSIF NEW.transaction_type = 'credit_issued' AND NEW.reference_type = 'customer_credit' THEN
        PERFORM pg_catalog.pg_advisory_xact_lock(public.cash_source_lock_key('credit', NEW.reference_id));
        SELECT * INTO v_credit FROM public.customer_credits c WHERE c.id = NEW.reference_id;
        IF NOT FOUND OR v_credit.tenant_id <> NEW.tenant_id OR v_credit.customer_id <> NEW.customer_id THEN
            RAISE EXCEPTION USING
                MESSAGE = format('account_ledger %s issues credit %s: a credit_issued row is on the account of its credit, of its own customer (R-05, v5.4.2-23)', NEW.id, NEW.reference_id),
                ERRCODE = 'foreign_key_violation';
        END IF;
        IF v_credit.origin_type IN ('overpayment', 'refund_reissue') THEN
            RAISE EXCEPTION USING
                MESSAGE = format('account_ledger %s issues %s credit %s: an overpayment or refund_reissue credit posts no ledger row — its money is its payment''s or its returned refund''s, already on the ledger (R-06, v5.4.2-23)', NEW.id, v_credit.origin_type, NEW.reference_id),
                ERRCODE = 'check_violation';
        END IF;
        -- r4 (Fable S3): only for a credit still active (a voided credit was
        -- never issued, or withdrawn).
        IF v_credit.status <> 'active' THEN
            RAISE EXCEPTION USING
                MESSAGE = format('account_ledger %s issues credit %s, which is %s: a credit_issued row is written for a credit still active (R-05, v5.4.2-23)', NEW.id, NEW.reference_id, v_credit.status),
                ERRCODE = 'check_violation';
        END IF;
        IF NEW.amount <> -v_credit.original_amount THEN
            RAISE EXCEPTION USING
                MESSAGE = format('account_ledger %s issues credit %s at %s: a credit_issued row is at minus its amount (%s) (R-05, v5.4.2-23)', NEW.id, NEW.reference_id, NEW.amount, -v_credit.original_amount),
                ERRCODE = 'check_violation';
        END IF;
    END IF;
    -- r2 (Codex B1): a credit's donation is a draw on it, capped with its
    -- applications and refunds, under its lock. r3 (Fable S5): from the
    -- credit's own account.
    IF NEW.transaction_type = 'donation' AND NEW.reference_type = 'customer_credit' THEN
        IF NEW.amount <= 0 THEN
            RAISE EXCEPTION USING
                MESSAGE = format('account_ledger %s donates credit %s: a donation of a credit is the amount given up, more than 0 (R-06, v5.4.2-23)', NEW.id, NEW.reference_id),
                ERRCODE = 'check_violation';
        END IF;
        IF NOT EXISTS (SELECT 1 FROM public.customer_credits c
                        WHERE c.id = NEW.reference_id AND c.tenant_id = NEW.tenant_id AND c.customer_id = NEW.customer_id) THEN
            RAISE EXCEPTION USING
                MESSAGE = format('account_ledger %s donates credit %s: a donation is on the account of its credit, of its own customer (R-06, v5.4.2-23)', NEW.id, NEW.reference_id),
                ERRCODE = 'foreign_key_violation';
        END IF;
        PERFORM public.check_cash_source('credit', NEW.reference_id, NEW.created_at, 'donation', NEW.transaction_date);
    END IF;
    IF NEW.reverses_ledger_entry_id IS NULL THEN
        RETURN NULL;
    END IF;
    -- The FK (tenant and customer) is checked before this trigger (its
    -- internal trigger sorts first); a parent this session cannot see is not
    -- one it may reverse.
    SELECT * INTO v_parent FROM public.account_ledger l WHERE l.id = NEW.reverses_ledger_entry_id;
    IF NOT FOUND OR v_parent.tenant_id <> NEW.tenant_id OR v_parent.customer_id <> NEW.customer_id THEN
        RAISE EXCEPTION USING
            MESSAGE = format('account_ledger %s names %s: a reversal names an entry of its own tenant and customer (R-02, v5.4.2-23)', NEW.id, NEW.reverses_ledger_entry_id),
            ERRCODE = 'foreign_key_violation';
    END IF;
    -- -22's recovery rules stay: a recovery names a write-off, and only a
    -- recovery names a write-off directly.
    IF NEW.transaction_type = 'write_off_recovery' AND v_parent.transaction_type <> 'write_off' THEN
        RAISE EXCEPTION USING
            MESSAGE = format('a write-off recovery names a write_off entry of its own customer; %s is a %s (R-02, v5.4.2-22)', v_parent.id, v_parent.transaction_type),
            ERRCODE = 'foreign_key_violation';
    END IF;
    IF v_parent.transaction_type = 'write_off' AND NEW.transaction_type <> 'write_off_recovery' THEN
        RAISE EXCEPTION USING
            MESSAGE = format('a row of type %s names write-off %s: only a write_off_recovery names a write-off (R-02, v5.4.2-22)', NEW.transaction_type, v_parent.id),
            ERRCODE = 'check_violation';
    END IF;
    -- X2: the opposite sign. A zero has no sign: it reverses nothing.
    IF NOT ((NEW.amount > 0 AND v_parent.amount < 0) OR (NEW.amount < 0 AND v_parent.amount > 0)) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('account_ledger %s (%s) reverses %s (%s): a reversal has the opposite sign of the entry it names, and neither is zero (R-02, v5.4.2-23)', NEW.id, NEW.amount, v_parent.id, v_parent.amount),
            ERRCODE = 'check_violation';
    END IF;
    -- -22 r4, made general: a row is dated on or after the entry it names, so
    -- every path down a tree is in date order and aging can net it by date.
    IF NEW.transaction_date < v_parent.transaction_date THEN
        RAISE EXCEPTION USING
            MESSAGE = format('account_ledger %s is dated %s, before %s, the date of the entry it names (%s): a reversal is dated on or after the entry it names (R-02, v5.4.2-23)', NEW.id, NEW.transaction_date, v_parent.transaction_date, v_parent.id),
            ERRCODE = 'check_violation';
    END IF;
    -- r2 (Opus S2): an undo is of something that happened, dated no later
    -- than today. A row dated ahead would put the tree over its cap at that
    -- date for a void posted today.
    IF NEW.transaction_date > CURRENT_DATE THEN
        RAISE EXCEPTION USING
            MESSAGE = format('account_ledger %s is dated %s, after today: a reversal is dated on or before the day it is posted (R-02, v5.4.2-23)', NEW.id, NEW.transaction_date),
            ERRCODE = 'check_violation';
    END IF;
    -- The path up to the root: the parent, its parent, ... The lineage walk
    -- (which fires first, by name) has refused a loop or a chain past c_max.
    WITH RECURSIVE up(id, next_id, depth) AS (
        SELECT l.id, l.reverses_ledger_entry_id, 1 FROM public.account_ledger l WHERE l.id = v_parent.id
        UNION ALL
        SELECT l.id, l.reverses_ledger_entry_id, u.depth + 1
          FROM up u JOIN public.account_ledger l ON l.id = u.next_id
         WHERE u.depth < c_max
    )
    SELECT array_agg(u.id ORDER BY u.depth) INTO v_path FROM up u;
    -- One lock per tree, on its root (the last on the path). Taken after the
    -- tenant's close head, which the freeze locked before the row went in.
    SELECT * INTO v_root FROM public.account_ledger l WHERE l.id = v_path[cardinality(v_path)];
    -- Fail closed: a walk that stopped at its bound has not found the root,
    -- and a cap and lock taken on the wrong entry would hold nothing.
    IF v_root.reverses_ledger_entry_id IS NOT NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('account_ledger %s: its reversal chain does not reach an original within %s entries (R-02, v5.4.2-23)', NEW.id, c_max),
            ERRCODE = 'check_violation';
    END IF;
    PERFORM pg_catalog.pg_advisory_xact_lock(public.ledger_tree_lock_key(v_root.id));
    -- The root's whole tree, walked once: each row with the entries above it
    -- (the root included). Each step is found by the reversal link alone.
    -- -22 r4/r6, made general: a row is not recorded before a row already in
    -- its tree. A row stamped at its transaction's start retries (40001); a
    -- row whose time was chosen keeps it on any retry, so it is refused for
    -- good (23514).
    WITH RECURSIVE t(id, created_at, depth) AS (
        SELECT l.id, l.created_at, 1 FROM public.account_ledger l WHERE l.reverses_ledger_entry_id = v_root.id
        UNION ALL
        SELECT l.id, l.created_at, t.depth + 1
          FROM t JOIN public.account_ledger l ON l.reverses_ledger_entry_id = t.id
         WHERE t.depth < c_max
    )
    SELECT x.id, x.created_at INTO v_later_id, v_later_at
      FROM (SELECT t.id, t.created_at FROM t UNION ALL SELECT v_root.id, v_root.created_at) x
     WHERE x.created_at > NEW.created_at
     ORDER BY x.created_at DESC LIMIT 1;
    IF FOUND AND NEW.created_at <> pg_catalog.now() THEN
        RAISE EXCEPTION USING
            MESSAGE = format('ledger tree %s: %s is recorded at %s, a time chosen for it, before %s (recorded at %s) already in the tree — a history row is recorded after every row already in its tree (R-02, v5.4.2-23)', v_root.id, NEW.id, NEW.created_at, v_later_id, v_later_at),
            ERRCODE = 'check_violation';
    END IF;
    IF FOUND THEN
        RAISE EXCEPTION USING
            MESSAGE = format('ledger tree %s: %s is recorded at %s, before %s (recorded at %s) already in the tree — a transaction that began earlier is posting later; retry it (R-02, v5.4.2-23)', v_root.id, NEW.id, NEW.created_at, v_later_id, v_later_at),
            ERRCODE = 'serialization_failure';
    END IF;
    -- X2's cap, at every entry on the path: the net of the entry's tree (the
    -- entry excluded) lies between 0 and minus its amount, at every date
    -- (rows of one date net together). One walk down from the root carries,
    -- for each row, m: how many entries of the path (root first) are above
    -- it, found by index, so a row's path ancestors are v_down[1..m]. The
    -- pairs (path ancestor j, row) are netted per j by date.
    SELECT array_agg(u.x ORDER BY u.ord DESC) INTO v_down FROM unnest(v_path) WITH ORDINALITY AS u(x, ord);
    SELECT array_agg(e.amount ORDER BY u.ord) INTO v_down_amt
      FROM unnest(v_down) WITH ORDINALITY AS u(x, ord) JOIN public.account_ledger e ON e.id = u.x;
    WITH RECURSIVE t(id, amount, on_date, depth, m, onpath) AS (
        SELECT l.id, l.amount, l.transaction_date, 1, 1, l.id = v_down[2]
          FROM public.account_ledger l WHERE l.reverses_ledger_entry_id = v_root.id
        UNION ALL
        SELECT l.id, l.amount, l.transaction_date, t.depth + 1,
               CASE WHEN t.onpath THEN t.depth + 1 ELSE t.m END,
               t.onpath AND l.id = v_down[t.depth + 2]
          FROM t JOIN public.account_ledger l ON l.reverses_ledger_entry_id = t.id
         WHERE t.depth < c_max
    ), nets AS (
        SELECT j.j, t.on_date, sum(t.amount) OVER (PARTITION BY j.j ORDER BY t.on_date) AS net
          FROM t CROSS JOIN LATERAL generate_series(1, t.m) AS j(j)
    )
    SELECT n.j, n.on_date, n.net INTO v_j, v_on, v_net
      FROM nets n
     WHERE n.net < least(0, -v_down_amt[n.j]) OR n.net > greatest(0, -v_down_amt[n.j])
     ORDER BY n.on_date, n.j DESC LIMIT 1;
    IF FOUND THEN
        SELECT * INTO v_anc FROM public.account_ledger e WHERE e.id = v_down[v_j];
    END IF;
    IF FOUND THEN
        RAISE EXCEPTION USING
            MESSAGE = format('entry %s (%s, %s): on %s the rows netted against it would come to %s, outside 0 to %s — reversals of an entry total at most the entry, with the opposite sign (R-02 cap, v5.4.2-23)', v_anc.id, v_anc.transaction_type, v_anc.amount, v_on, v_net, -v_anc.amount),
            ERRCODE = 'check_violation';
    END IF;
    -- r2 (Opus B2 O2, O6; guard the act): money is not undone on the ledger
    -- while it is still drawn on. The root is a payment's posting entry or a
    -- credit's credit_issued entry; this row waits until the payment's
    -- applications are undone and its overpayment credits voided, or until
    -- nothing of the credit is drawn. Its source's lock, after the tree's;
    -- nothing takes them the other way. The void (tally_void, which reads no
    -- cash table) reverses a charge, so it never reaches the reads below.
    -- r3 (Kyle, K-10): a refund is not an undo, so no row is exempt; a posted
    -- refund stands at the bounce (the money really went out), and a refund
    -- still waiting to go out blocks it until an operator cancels the refund
    -- (2: no automatic cancel, it may already be in a check run or ACH batch).
    -- r4 (Fable S2): keyed on the act. A row taking money away (more than 0
    -- under a posting or credit_issued entry, which is less than 0) waits; a
    -- row giving it back does not, but only to a source that has not ended
    -- (a bounced payment or a voided or escheated credit gets nothing back;
    -- a re-presented check is a new payment).
    IF v_root.reference_type = 'payment' AND v_root.transaction_type IN ('payment', 'deposit') THEN
        SELECT p.id INTO v_src FROM public.payments p WHERE p.id = v_root.reference_id AND v_root.amount = -p.amount;
    END IF;
    IF v_src IS NOT NULL THEN
        PERFORM pg_catalog.pg_advisory_xact_lock(public.cash_source_lock_key('payment', v_src));
        -- r6 (Opus B2, Fable B1): the split reads this row at its recorded
        -- instant against the draws on the payment and its overpayment
        -- credits, so it is not recorded before one already counted, a draw
        -- that has since left, or the credit itself (a draw on the payment):
        -- 40001 for a row stamped at its transaction's start, 23514 for a
        -- chosen time. Every draw on the credits takes the payment's lock
        -- first (check_cash_source; r6 S1: so does a credit's refund that
        -- leaves), so the payment's lock, held here, orders them all. The
        -- rows of the tree are ordered among themselves above.
        PERFORM public.check_cash_order('payment', v_src, NEW.created_at, NULL, 'a row under its posting entry');
        PERFORM public.check_cash_order('credit', f.id, NEW.created_at, NULL, 'a row under its payment''s posting entry')
           FROM public.customer_credits k CROSS JOIN LATERAL public.overpayment_family(k.id) f
          WHERE k.source_payment_id = v_src AND k.status <> 'voided';
        IF NEW.amount < 0 THEN
            IF NOT EXISTS (SELECT 1 FROM public.payments p WHERE p.id = v_src AND p.status IN ('pending', 'posted')) THEN
                RAISE EXCEPTION USING
                    MESSAGE = format('account_ledger %s gives money back to payment %s, which has ended: post a new payment (guard the act; CI-013, v5.4.2-23)', NEW.id, v_src),
                    ERRCODE = 'restrict_violation';
            END IF;
            -- r5 (Fable B2, Codex B2; Ryan, 2026-10-21): money given back
            -- under the payment goes back to its overpayment credit first
            -- (overpayment_split), and nothing comes back to an escheated
            -- credit. r6 (Opus S2, Fable S2): refused as far as the credit
            -- would then hold money, not merely because it is escheated: a
            -- give-back that only cancels a deficit (the take-back keyed in
            -- error after the credit was remitted, or one that fell on the
            -- payment) removes a debt and gives nothing back. Read after the
            -- row, under the locks of the credits that could be escheated
            -- (after the payment's), so an escheat move waits for it or is
            -- seen.
            PERFORM pg_catalog.pg_advisory_xact_lock(public.cash_source_lock_key('credit', c.id))
               FROM (SELECT f.id FROM public.customer_credits k CROSS JOIN LATERAL public.overpayment_family(k.id) f
                      JOIN public.customer_credits c ON c.id = f.id
                     WHERE k.source_payment_id = v_src AND k.status <> 'voided' AND c.status <> 'voided' ORDER BY f.id) c;
            SELECT c.id, x.remaining INTO v_later_id, v_net
              FROM public.customer_credits k CROSS JOIN LATERAL public.overpayment_family(k.id) f
              JOIN public.customer_credits c ON c.id = f.id
              CROSS JOIN LATERAL public.customer_credit_position_as_of(c.id, DATE '9999-12-31', pg_catalog.clock_timestamp()) x
             WHERE k.source_payment_id = v_src AND k.status <> 'voided' AND c.status = 'escheated' AND x.remaining > 0
             LIMIT 1;
            IF FOUND THEN
                RAISE EXCEPTION USING
                    MESSAGE = format('account_ledger %s gives money back under payment %s, and %s of it would come back to credit %s, which is escheated: nothing comes back to an escheated credit — post a new payment (Ryan, 2026-10-21; v5.4.2-23)', NEW.id, v_src, v_net, v_later_id),
                    ERRCODE = 'restrict_violation';
            END IF;
        ELSE
            -- r4 (Opus B3, Fable B1; K-10): an overpayment credit of the
            -- payment holds the bounce only while it is applied or has a
            -- refund pending; what it paid out stands, and what it still holds
            -- goes with the payment (check_cash_source). r5: every draw on
            -- the credit takes the payment's lock first (check_cash_source),
            -- so the payment's lock, held here, already orders them; r4's
            -- credit lock here was never the one that waited (mutation N145).
            -- r6 (Codex B1): so does every reissue descended from the credit:
            -- it holds the payment's money too.
            IF coalesce((SELECT sum(a.amount) FROM public.invoice_applications a WHERE a.payment_id = v_src), 0) <> 0
               OR EXISTS (SELECT 1 FROM public.payments r WHERE r.refunds_payment_id = v_src AND r.status = 'pending')
               OR EXISTS (SELECT 1 FROM public.customer_credits k CROSS JOIN LATERAL public.overpayment_family(k.id) f
                           JOIN public.customer_credits c ON c.id = f.id
                           WHERE k.source_payment_id = v_src AND k.status <> 'voided' AND c.status <> 'voided'
                             AND (coalesce((SELECT sum(a.amount) FROM public.invoice_applications a WHERE a.customer_credit_id = c.id), 0) <> 0
                                  OR EXISTS (SELECT 1 FROM public.payments r WHERE r.refunds_customer_credit_id = c.id AND r.status = 'pending'))) THEN
                RAISE EXCEPTION USING
                    MESSAGE = format('account_ledger %s undoes payment %s''s posting entry %s while the payment is applied to bills (or its overpayment credit is), or a refund of either is waiting to go out: undo the applications and cancel the refund first (guard the act; K-10; CI-013, v5.4.2-23)', NEW.id, v_src, v_root.id),
                    ERRCODE = 'restrict_violation';
            END IF;
        END IF;
    END IF;
    -- r5 (Opus B2, Fable S1, Codex B1): a refund's posting row is money paid
    -- out. A row under it (the bounce of the refund check, a partial return,
    -- its correction) is written only while the refund is pending or posted,
    -- under the refund's lock (its moves take it): once the refund is nsf or
    -- reversed its money is back, read from its status (and, for a credit's
    -- refund after the escheat, carried into a refund_reissue credit), so
    -- nothing more goes under it. A re-sent refund is a new refund.
    v_src := NULL;
    IF v_root.reference_type = 'payment' AND v_root.transaction_type = 'refund' THEN
        SELECT p.id INTO v_src FROM public.payments p WHERE p.id = v_root.reference_id AND v_root.amount = -p.amount;
    END IF;
    IF v_src IS NOT NULL THEN
        PERFORM pg_catalog.pg_advisory_xact_lock(public.cash_source_lock_key('payment', v_src));
        SELECT p.status INTO v_kind FROM public.payments p WHERE p.id = v_src;
        IF v_kind NOT IN ('pending', 'posted') THEN
            RAISE EXCEPTION USING
                MESSAGE = format('account_ledger %s is under refund %s''s posting row, and the refund is %s: nothing more goes under it — a re-sent refund is a new refund (guard the act; CI-013, v5.4.2-23)', NEW.id, v_src, v_kind),
                ERRCODE = 'restrict_violation';
        END IF;
    END IF;
    v_src := NULL;
    IF v_root.reference_type = 'customer_credit' AND v_root.transaction_type = 'credit_issued' THEN
        SELECT c.id INTO v_src FROM public.customer_credits c WHERE c.id = v_root.reference_id AND c.origin_type NOT IN ('overpayment', 'refund_reissue');
    END IF;
    IF v_src IS NOT NULL THEN
        PERFORM pg_catalog.pg_advisory_xact_lock(public.cash_source_lock_key('credit', v_src));
        IF NEW.amount < 0 THEN
            IF NOT EXISTS (SELECT 1 FROM public.customer_credits c WHERE c.id = v_src AND c.status = 'active') THEN
                RAISE EXCEPTION USING
                    MESSAGE = format('account_ledger %s gives money back to credit %s, which has ended: issue a new credit (guard the act; CI-013, v5.4.2-23)', NEW.id, v_src),
                    ERRCODE = 'restrict_violation';
            END IF;
        ELSIF EXISTS (SELECT 1 FROM public.cash_source_draws('credit', v_src) d HAVING coalesce(sum(d.amount), 0) <> 0) THEN
            RAISE EXCEPTION USING
                MESSAGE = format('account_ledger %s undoes credit %s''s credit_issued entry %s while the credit is drawn on (applied, refunded, donated or escheated): undo those first (guard the act; CI-013, v5.4.2-23)', NEW.id, v_src, v_root.id),
                ERRCODE = 'restrict_violation';
        END IF;
    END IF;
    -- r4 (Codex B1): a row under a donation of a credit changes what the
    -- credit gave up. One taking money from the credit again (a reversal of
    -- the donation's undo) is a draw, capped; one giving it back is an undo:
    -- only to a credit not yet ended, and in recorded order. The credit's
    -- lock, after the tree's (check_cash_source takes it).
    IF v_root.transaction_type = 'donation' AND v_root.reference_type = 'customer_credit' THEN
        PERFORM public.check_cash_source('credit', v_root.reference_id, NEW.created_at,
                                         CASE WHEN NEW.amount > 0 THEN 'donation' ELSE 'undo' END, NEW.transaction_date);
    END IF;
    RETURN NULL;
END;
$$;
COMMENT ON FUNCTION public.enforce_ledger_reversal() IS
    'v5.4.2-23 (X; R-02), replacing -22''s enforce_write_off_recovery. AFTER INSERT on account_ledger, every row, after the lineage walk (trigger name order). Every row is recorded at a finite time already reached (23514). r3: a posting row referencing a payment names it under reference_type payment, on its account, of its kind, at minus its amount; a credit_issued row referencing a credit is on its account at minus its amount, and an overpayment credit posts none; a donation of a credit is more than 0, on its account, and a draw on it (check_cash_source). A row undoing a payment''s posting entry waits while the payment is applied, held as a credit or has a refund pending (K-10; r6: or a reissue of its credit is applied or has a refund pending); one undoing a credit''s credit_issued entry while the credit is drawn on. r6: a row under a payment''s posting entry is not recorded before a draw already counted on the payment or its credits (check_cash_order); a give-back under it is refused as far as it would leave an escheated credit holding money. A row naming an entry: the entry is of its tenant and customer; a write_off_recovery names a write_off, and only a recovery names a write_off; the opposite sign, neither zero; dated on or after the entry. Then, at READ COMMITTED behind the advisory lock of the tree''s root: not recorded before a row already in the tree (40001; 23514 for a chosen time); and for every entry on the path up to the root, the net of that entry''s tree stays between 0 and minus its amount at every date. The walks run with sequential scans, hash and merge joins off.';
CREATE TRIGGER enforce_ledger_reversal AFTER INSERT ON public.account_ledger
    FOR EACH ROW EXECUTE FUNCTION public.enforce_ledger_reversal();
ALTER TABLE public.account_ledger ENABLE ALWAYS TRIGGER enforce_ledger_reversal;


-- ----------------------------------------------------------------------------
-- 2. The void reverses what is left (X3)
-- ----------------------------------------------------------------------------
-- CREATE OR REPLACE keeps the owner (tally_void) and the grants. Changed from
-- -21: Step 2.5 locks the head and the charge's tree and reads what is left;
-- Step 4 posts that, or nothing.
CREATE OR REPLACE FUNCTION public.void_invoice(p_invoice_id uuid, p_voided_by uuid DEFAULT NULL::uuid, p_void_reason_code text DEFAULT NULL::text, p_void_reason_notes text DEFAULT NULL::text, p_rebill_expected boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
    v_invoice                    public.invoices%ROWTYPE;
    v_reads_released             INTEGER := 0;
    v_charges_auto_reverted      INTEGER := 0;
    v_charges_pending_review     INTEGER := 0;
    v_reversal_amount            DECIMAL(12,2);
    v_ledger_entry_id            UUID;
    v_original_ledger_entry_id   UUID;
    v_had_payment                BOOLEAN := false;
    v_new_running_bal            DECIMAL(12,2);
    v_description                TEXT;
    v_duplicate_no_match_warning BOOLEAN := false;
    v_invoice_status_at_void     TEXT;
    v_auto_revert_codes          TEXT[] := ARRAY[
        'wrong_read', 'wrong_rate', 'service_date_error', 'system_error'
    ];
BEGIN
    -- -------------------------------------------------------------------------
    -- Step 1: Load and validate the invoice
    -- -------------------------------------------------------------------------
    -- v5.4.2-20 (C-B6): the invoice is locked before its status is read, so
    -- a second void waits here and then sees 'void'; a write attaching a
    -- read or a charge to it takes FOR SHARE on it and waits too
    -- (enforce_attach_to_live_invoice). Lock order: the invoice, then its
    -- reads and charges. The owner, tally_void, is subject to RLS: another
    -- tenant's invoice is not found.
    -- r2 (F2): only at READ COMMITTED. Under an older snapshot the release
    -- of reads and charges below would miss one attached while this waited
    -- for the lock, and the bill would be void with it still attached.
    IF pg_catalog.current_setting('transaction_isolation') <> 'read committed' THEN
        RAISE EXCEPTION USING
            MESSAGE = format('void_invoice() runs at READ COMMITTED (this transaction is %s): a void under an older snapshot misses what was attached to the bill while it waited for the lock (v5.4.2-20)', pg_catalog.current_setting('transaction_isolation')),
            ERRCODE = 'invalid_transaction_state';
    END IF;
    SELECT * INTO v_invoice
    FROM public.invoices
    WHERE id = p_invoice_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION USING
            MESSAGE = format('Invoice not found: %s', p_invoice_id),
            ERRCODE = 'no_data_found';
    END IF;

    -- -------------------------------------------------------------------------
    -- Step 1.1: the tenant. v5.4.2-20: row-level security is the check. The
    -- owner, tally_void, does not bypass it (assert_seal_role_invariants), so
    -- the SELECT above finds only what the caller's policy admits: its own
    -- tenant's invoices, every tenant's for a platform admin, none for a
    -- caller with no user or one naming no user. The v5.2.1 comparison it
    -- replaces (`tenant_id != get_user_tenant_id()`) was NULL for such a
    -- caller, so it never refused, and the then-superuser owner voided any
    -- tenant's bill (Opus B1); its refusal also named the other tenant's
    -- invoice number (Opus S6). A not-found names only the caller's id.
    -- -------------------------------------------------------------------------

    -- -------------------------------------------------------------------------
    -- Step 1.2: Voidability and reason validation
    -- -------------------------------------------------------------------------
    IF v_invoice.status NOT IN ('pending','sent','overdue','partial','paid','held') THEN
        RAISE EXCEPTION
            'Invoice % is not voidable. Current status: %. '
            'Voidable statuses: pending, sent, overdue, partial, paid, held.',
            v_invoice.invoice_number, v_invoice.status;
    END IF;

    IF p_void_reason_code IS NULL THEN
        RAISE EXCEPTION 'void_reason_code is required.';
    END IF;

    IF p_void_reason_code = 'other'
       AND (p_void_reason_notes IS NULL OR trim(p_void_reason_notes) = '')
    THEN
        RAISE EXCEPTION
            'void_reason_notes is required when void_reason_code = ''other''.';
    END IF;

    -- Snapshot status before any changes (for invoice_events audit record)
    v_invoice_status_at_void := v_invoice.status;
    v_had_payment := v_invoice.status IN ('paid','partial');

    -- -------------------------------------------------------------------------
    -- Step 1.5: Duplicate-warning check (Fix #4: filter by invoice_type)
    -- -------------------------------------------------------------------------
    -- The v5.2 check matched ANY non-void invoice for the same location and
    -- billing period. That gave false negatives when a single location had
    -- multiple service types (water + gas + electric) for the same period —
    -- it would find the unrelated water invoice and suppress the warning for
    -- the gas duplicate.
    --
    -- v5.2.1: also require matching invoice_type. A regular gas duplicate
    -- will only match other regular invoices for the same location/period,
    -- not water/electric or correction/final invoices.
    -- -------------------------------------------------------------------------
    IF p_void_reason_code = 'duplicate' THEN
        SELECT NOT EXISTS (
            SELECT 1 FROM public.invoices
            WHERE location_id    = v_invoice.location_id
              AND billing_period = v_invoice.billing_period
              AND invoice_type   = v_invoice.invoice_type       -- Fix #4
              AND status         NOT IN ('void','draft')
              AND id             != p_invoice_id
        ) INTO v_duplicate_no_match_warning;
    END IF;

    -- -------------------------------------------------------------------------
    -- Step 2 (v5.4.2-20): no carve-out to arm. The read, charge and invoice
    -- guards admit the writes below because they run as this function's
    -- owner, tally_void (current_user inside a SECURITY DEFINER function, and
    -- in every trigger its statements fire). No caller can become that role,
    -- and the admission ends when this function returns.
    -- -------------------------------------------------------------------------

    -- -------------------------------------------------------------------------
    -- Step 2.5 (v5.4.2-21, CI-017; Ryan 2026-10-14): the charge this void
    -- reverses. A posted bill (first_issued_at, stamped by the database on
    -- the first move into an issued status) was charged to the account, and
    -- its reversal names that charge: if the charge entry is missing the void
    -- is refused, before anything is written. A bill never posted (voided
    -- straight from held) was never charged: the void writes no ledger entry.
    -- -------------------------------------------------------------------------
    IF v_invoice.first_issued_at IS NOT NULL THEN
        -- v5.4.2-23 (X3): the lock order of a money write — the tenant's
        -- close head FOR SHARE (as the freeze takes it when the reversal goes
        -- in), then the charge's tree — so what is left of the charge is read
        -- with nothing able to join its tree before the reversal does.
        PERFORM 1 FROM public.accounting_close_heads h WHERE h.tenant_id = v_invoice.tenant_id FOR SHARE;
        SELECT l.id INTO v_original_ledger_entry_id
          FROM public.account_ledger l
         WHERE l.tenant_id        = v_invoice.tenant_id
           AND l.customer_id      = v_invoice.customer_id   -- r2 (Opus S1)
           AND l.reference_type   = 'invoice'
           AND l.reference_id     = p_invoice_id
           AND l.transaction_type = 'charge'
         ORDER BY l.created_at, l.id
         LIMIT 1;
        IF NOT FOUND THEN
            RAISE EXCEPTION USING
                MESSAGE = format('invoice %s was posted but has no charge entry on account_ledger (reference_type = invoice, transaction_type = charge): its void must reverse that charge and name it (CI-017, v5.4.2-21) — post the missing charge first', v_invoice.invoice_number),
                ERRCODE = 'no_data_found';
        END IF;
        PERFORM pg_catalog.pg_advisory_xact_lock(public.ledger_tree_lock_key(public.ledger_tree_root(v_original_ledger_entry_id)));
        -- v5.4.2-23 (X3; R-02's cap): the void reverses what is left of the
        -- charge after the reversals already under it, not -(amount_due). A
        -- charge already fully reversed voids with no ledger row.
        v_reversal_amount := -public.ledger_entry_remaining(v_original_ledger_entry_id);
        IF v_reversal_amount = 0 THEN
            v_reversal_amount := NULL;
        END IF;
    END IF;

    -- -------------------------------------------------------------------------
    -- Step 3: Release locked meter reads
    -- -------------------------------------------------------------------------
    UPDATE public.meter_readings
    SET
        voided_from_invoice_id = locked_by_invoice_id,
        locked_by_invoice_id   = NULL,
        validation_status      = 'void_released'
    WHERE locked_by_invoice_id = p_invoice_id
      AND validation_status    = 'locked';

    GET DIAGNOSTICS v_reads_released = ROW_COUNT;

    -- -------------------------------------------------------------------------
    -- Step 3.5: Adhoc charge disposition
    -- -------------------------------------------------------------------------
    IF p_void_reason_code = ANY(v_auto_revert_codes) THEN
        UPDATE public.adhoc_charges
        SET
            status                 = 'pending',
            voided_from_invoice_id = billed_on_invoice_id,
            billed_on_invoice_id   = NULL,
            billed_on_line_item_id = NULL,
            billed_at              = NULL,
            target_billing_period  = v_invoice.billing_period,
            updated_at             = now()
        WHERE billed_on_invoice_id = p_invoice_id
          AND status               = 'billed';

        GET DIAGNOSTICS v_charges_auto_reverted = ROW_COUNT;
        v_charges_pending_review := 0;
    ELSE
        UPDATE public.adhoc_charges
        SET
            status                 = 'void_pending_rebill',
            voided_from_invoice_id = billed_on_invoice_id,
            billed_on_invoice_id   = NULL,
            billed_on_line_item_id = NULL,
            billed_at              = NULL,
            updated_at             = now()
        WHERE billed_on_invoice_id = p_invoice_id
          AND status               = 'billed';

        GET DIAGNOSTICS v_charges_pending_review = ROW_COUNT;
        v_charges_auto_reverted := 0;
    END IF;

    -- -------------------------------------------------------------------------
    -- Step 4: Post void_reversal ledger entry
    -- -------------------------------------------------------------------------
    -- v5.4.2-21: a posted bill only (Step 2.5); a never-posted bill has no
    -- charge to reverse, and the reversal amount stays NULL.
    -- v5.4.2-23 (X3): what is left of the charge (Step 2.5); nothing left,
    -- no row.
    IF v_reversal_amount IS NOT NULL THEN
        v_description := format(
            'Void reversal — Invoice %s (%s). Reason: %s%s',
            v_invoice.invoice_number,
            v_invoice.billing_period,
            p_void_reason_code,
            CASE WHEN p_void_reason_notes IS NOT NULL
                 THEN '. Notes: ' || p_void_reason_notes
                 ELSE ''
            END
        );

        INSERT INTO public.account_ledger (
            tenant_id,
            customer_id,
            location_id,
            transaction_date,
            transaction_type,
            description,
            amount,
            reference_type,
            reference_id,
            created_by,
            reverses_ledger_entry_id,
            reversal_reason
        )
        VALUES (
            v_invoice.tenant_id,
            v_invoice.customer_id,
            v_invoice.location_id,
            CURRENT_DATE,
            'void_reversal',
            v_description,
            v_reversal_amount,
            'invoice_void',
            p_invoice_id,
            p_voided_by,
            v_original_ledger_entry_id,
            p_void_reason_code || CASE WHEN p_void_reason_notes IS NOT NULL
                                        THEN ': ' || p_void_reason_notes
                                        ELSE ''
                                   END
        )
        RETURNING id INTO v_ledger_entry_id;
    END IF;

    -- -------------------------------------------------------------------------
    -- Step 5: Stamp void metadata on invoice
    -- -------------------------------------------------------------------------
    UPDATE public.invoices
    SET
        status               = 'void',
        voided_at            = now(),
        voided_by            = p_voided_by,
        void_reason_code     = p_void_reason_code,
        void_reason_notes    = p_void_reason_notes,
        void_rebill_expected = p_rebill_expected,
        updated_at           = now()
    WHERE id = p_invoice_id;

    -- -------------------------------------------------------------------------
    -- Step 5.5: Log the voided event
    -- -------------------------------------------------------------------------
    -- tenant_id will be overwritten by the sync trigger from Fix #6, but we
    -- still pass it for explicitness and to satisfy NOT NULL.
    -- -------------------------------------------------------------------------
    INSERT INTO public.invoice_events (
        tenant_id,
        invoice_id,
        event_type,
        operator_id,
        occurred_at,
        metadata
    )
    VALUES (
        v_invoice.tenant_id,
        p_invoice_id,
        'voided',
        p_voided_by,
        now(),
        jsonb_build_object(
            'void_reason_code',       p_void_reason_code,
            'void_reason_notes',      p_void_reason_notes,
            'rebill_expected',        p_rebill_expected,
            'reads_released',         v_reads_released,
            'charges_auto_reverted',  v_charges_auto_reverted,
            'charges_pending_review', v_charges_pending_review,
            'reversal_amount',        v_reversal_amount,
            'had_payment',            v_had_payment,
            'invoice_amount_due',     v_invoice.amount_due,
            'invoice_status_at_void', v_invoice_status_at_void,
            'invoice_number',         v_invoice.invoice_number,
            'billing_period',         v_invoice.billing_period
        )
    );

    -- -------------------------------------------------------------------------
    -- Step 6: Retrieve updated running balance
    -- -------------------------------------------------------------------------
    -- v5.4.2-19: the balance is the sum of the customer's ledger rows (the
    -- stored running balance column is dropped). The sum names the tenant as
    -- well as the customer (RLS scopes it too, since v5.4.2-20).
    SELECT coalesce(sum(l.amount), 0) INTO v_new_running_bal
      FROM public.account_ledger l
     WHERE l.tenant_id = v_invoice.tenant_id
       AND l.customer_id = v_invoice.customer_id;

    -- -------------------------------------------------------------------------
    -- Step 7: Return payload
    RETURN jsonb_build_object(
        'invoice_id',                  p_invoice_id,
        'invoice_number',              v_invoice.invoice_number,
        'void_reason_code',            p_void_reason_code,
        'rebill_expected',             p_rebill_expected,
        'duplicate_no_match_warning',  v_duplicate_no_match_warning,
        'reads_released',              v_reads_released,
        'charges_auto_reverted',       v_charges_auto_reverted,
        'charges_pending_review',      v_charges_pending_review,
        'reversal_amount',             v_reversal_amount,
        'ledger_entry_id',             v_ledger_entry_id,
        'reverses_ledger_entry_id',    v_original_ledger_entry_id,
        'had_payment',                 v_had_payment,
        'credit_balance',              v_new_running_bal
    );

END;
$fn$;
COMMENT ON FUNCTION public.void_invoice(uuid, uuid, text, text, boolean) IS
    'Atomically voids an invoice — the ONLY way to set invoices.status = ''void'' outside a superuser''s history load. Locks the invoice, releases its locked reads, disposes of its billed ad-hoc charges and logs the event. A posted bill (first_issued_at set) must have its charge entry on account_ledger, of the bill''s tenant and customer (refused, P0002, before anything is written, if missing). v5.4.2-23 (X3): it takes the tenant''s close head FOR SHARE and the charge''s ledger-tree lock, and posts the void_reversal naming the charge for what is left of it (its amount plus the net of the reversals already under it) — not -(amount_due); with nothing left it posts no row and returns reversal_amount NULL. A bill never posted (voided from held) gets no ledger entry. Runs as tally_void (since v5.4.2-20), a role subject to RLS that no caller can become. Returns the customer''s summed ledger balance as credit_balance.';


-- ----------------------------------------------------------------------------
-- 3. The shapes: bill lines' class, applications per line, the restriction,
--    the overpayment approval, the status cause (A1, A1b, A2, A4, A6, C1, M3)
-- ----------------------------------------------------------------------------
-- A1b. Each bill line carries its own regulated/unregulated class (D7-2;
-- CI-050). Checked against the line's source when the bill is issued
-- (section 6), frozen with the bill (CI-012: lines are immutable once issued).
ALTER TABLE public.invoice_line_items ADD COLUMN regulatory_class text NOT NULL;
ALTER TABLE public.invoice_line_items
    ADD CONSTRAINT invoice_line_items_regulatory_class_check
        CHECK (regulatory_class = ANY (ARRAY['regulated'::text, 'unregulated'::text]));
COMMENT ON COLUMN public.invoice_line_items.regulatory_class IS
    'v5.4.2-23 (D7-2, CI-050; A1b). Whether this bill line is a regulated or an unregulated charge, as billed. A line from a one-off charge carries that charge''s class, a line from a rate item the class of the rate item''s version at the bill''s calculation snapshot (checked at issue); a tax or other line without a source is classed by the core when it builds the bill. Frozen with the bill. The regulated-first floor of payment application reads it.';
ALTER TABLE public.invoice_line_items
    ADD CONSTRAINT invoice_line_items_id_invoice_tenant_key UNIQUE (id, invoice_id, tenant_id);
ALTER TABLE public.invoices
    ADD CONSTRAINT invoices_id_tenant_customer_key UNIQUE (id, tenant_id, customer_id);

-- A1, A2. Applications per bill line, add-only.
DROP TRIGGER enforce_invoice_application_immutable ON public.invoice_applications;
DROP FUNCTION public.enforce_invoice_application_immutable();
DROP INDEX public.idx_invoice_apps_active;
DROP INDEX public.idx_invoice_apps_source;
ALTER TABLE public.invoice_applications
    DROP CONSTRAINT invoice_applications_amount_check,
    DROP CONSTRAINT invoice_applications_source_type_check,
    DROP CONSTRAINT invoice_applications_invoice_id_fkey,
    DROP CONSTRAINT invoice_applications_tenant_id_fkey,
    DROP CONSTRAINT invoice_applications_reversed_by_fkey,
    DROP COLUMN source_type,
    DROP COLUMN source_id,
    DROP COLUMN applied_at,
    DROP COLUMN reversed_at,
    DROP COLUMN reversed_by,
    DROP COLUMN reversed_reason,
    DROP COLUMN notes,
    ADD COLUMN customer_id uuid NOT NULL,
    ADD COLUMN invoice_line_item_id uuid NOT NULL,
    ADD COLUMN payment_id uuid,
    ADD COLUMN customer_credit_id uuid,
    ADD COLUMN applied_on date NOT NULL,
    ADD COLUMN basis text NOT NULL,
    ADD COLUMN reason text,
    ADD COLUMN undoes_application_id uuid,
    ADD COLUMN allocation_tariff_id uuid;
ALTER TABLE public.invoice_applications
    ADD CONSTRAINT invoice_applications_tenant_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants (id),
    ADD CONSTRAINT invoice_applications_invoice_fkey
        FOREIGN KEY (invoice_id, tenant_id, customer_id) REFERENCES public.invoices (id, tenant_id, customer_id),
    ADD CONSTRAINT invoice_applications_line_fkey
        FOREIGN KEY (invoice_line_item_id, invoice_id, tenant_id) REFERENCES public.invoice_line_items (id, invoice_id, tenant_id),
    ADD CONSTRAINT invoice_applications_payment_fkey
        FOREIGN KEY (payment_id, tenant_id, customer_id) REFERENCES public.payments (id, tenant_id, customer_id),
    ADD CONSTRAINT invoice_applications_credit_fkey
        FOREIGN KEY (customer_credit_id, tenant_id, customer_id) REFERENCES public.customer_credits (id, tenant_id, customer_id),
    ADD CONSTRAINT invoice_applications_id_tenant_line_key UNIQUE (id, tenant_id, invoice_line_item_id),
    ADD CONSTRAINT invoice_applications_undoes_fkey
        FOREIGN KEY (undoes_application_id, tenant_id, invoice_line_item_id) REFERENCES public.invoice_applications (id, tenant_id, invoice_line_item_id),
    ADD CONSTRAINT invoice_applications_one_source_check
        CHECK (num_nonnulls(payment_id, customer_credit_id) = 1),
    ADD CONSTRAINT invoice_applications_basis_check
        CHECK (basis = ANY (ARRAY['oldest_first'::text, 'operator_override'::text, 'restriction'::text, 'floor_over_restriction'::text, 'undo'::text])),
    -- An undo, and only an undo, is negative and names the application it undoes.
    ADD CONSTRAINT invoice_applications_sign_check
        CHECK (amount <> 0
               AND (amount < 0) = (basis = 'undo')
               AND (basis = 'undo') = (undoes_application_id IS NOT NULL)),
    ADD CONSTRAINT invoice_applications_not_self_check CHECK (undoes_application_id IS DISTINCT FROM id),
    -- CI-049: an operator's choice and an undo say why, and who.
    ADD CONSTRAINT invoice_applications_operator_check
        CHECK (basis NOT IN ('operator_override', 'undo')
               OR (applied_by IS NOT NULL AND coalesce(reason ~ '[[:alnum:]]', false))),
    -- A rule-chosen application names the tariff row whose order it followed.
    ADD CONSTRAINT invoice_applications_tariff_check
        CHECK ((allocation_tariff_id IS NOT NULL) = (basis IN ('oldest_first', 'restriction', 'floor_over_restriction')));
CREATE INDEX idx_invoice_apps_line ON public.invoice_applications (invoice_line_item_id);
CREATE INDEX idx_invoice_apps_payment ON public.invoice_applications (payment_id) WHERE payment_id IS NOT NULL;
CREATE INDEX idx_invoice_apps_credit ON public.invoice_applications (customer_credit_id) WHERE customer_credit_id IS NOT NULL;
CREATE INDEX idx_invoice_apps_undoes ON public.invoice_applications (undoes_application_id) WHERE undoes_application_id IS NOT NULL;
CREATE TRIGGER append_only BEFORE DELETE OR UPDATE ON public.invoice_applications
    FOR EACH ROW EXECUTE FUNCTION public.enforce_append_only();
ALTER TABLE public.invoice_applications ENABLE ALWAYS TRIGGER append_only;
CREATE TRIGGER a_stamp_created_at BEFORE INSERT ON public.invoice_applications
    FOR EACH ROW EXECUTE FUNCTION public.stamp_log_created_at();
ALTER TABLE public.invoice_applications ENABLE ALWAYS TRIGGER a_stamp_created_at;
COMMENT ON TABLE public.invoice_applications IS
    'v5.4.2-23 (R-06, CI-049, CI-050; A1-A4). Money applied to a bill line: from a payment or a customer credit of the bill''s customer, to one positive line of an issued bill. Add-only: a mistaken application is undone by a negative row naming it (basis undo), never edited. created_at is the database''s (the recorded instant the positions read); applied_on is the money date (frozen by the close). basis records how the line was chosen: oldest_first, restriction or floor_over_restriction by the tariff row named in allocation_tariff_id; operator_override or undo with a reason and the user. Capped (section 7): a source''s money, a line''s amount, an application''s undos.';
COMMENT ON COLUMN public.invoice_applications.basis IS
    'v5.4.2-23 (CI-049; D7-1; A4). oldest_first: the bill came by K-05''s order and the line by the tariff''s within-bill order. restriction: an agency payment''s restricted target. floor_over_restriction: a regulated line taken ahead of an agency payment''s unregulated target (CI-050''s floor; whether the floor beats the restriction is Kyle''s to rule, the record carries either). operator_override: the operator changed the line (reason, user). undo: the negative row taking back an application (reason, user).';

-- A6 (D7-1 b). The restriction an agency payment carries, write-once from
-- insert (section 6). -24's pledges point at it.
ALTER TABLE public.payments
    ADD COLUMN payer_class text DEFAULT 'customer'::text NOT NULL,
    ADD COLUMN restricted_to_invoice_id uuid,
    ADD COLUMN restricted_to_line_item_id uuid,
    ADD COLUMN status_cause_id uuid,
    ADD COLUMN status_recorded_at timestamp with time zone;
-- r2 (Fable B3, S3; Opus B2 O1): a payment is born pending, and posted only
-- by the move that names its posting entry.
ALTER TABLE public.payments ALTER COLUMN status SET DEFAULT 'pending'::text;
ALTER TABLE public.payments
    ADD CONSTRAINT payments_payer_class_check CHECK (payer_class = ANY (ARRAY['customer'::text, 'agency'::text])),
    ADD CONSTRAINT payments_restriction_agency_check
        CHECK ((restricted_to_invoice_id IS NULL OR payer_class = 'agency')
               AND (restricted_to_line_item_id IS NULL OR restricted_to_invoice_id IS NOT NULL)),
    ADD CONSTRAINT payments_restricted_invoice_fkey
        FOREIGN KEY (restricted_to_invoice_id, tenant_id, customer_id) REFERENCES public.invoices (id, tenant_id, customer_id),
    ADD CONSTRAINT payments_restricted_line_fkey
        FOREIGN KEY (restricted_to_line_item_id, restricted_to_invoice_id, tenant_id) REFERENCES public.invoice_line_items (id, invoice_id, tenant_id);
COMMENT ON COLUMN public.payments.payer_class IS
    'v5.4.2-23 (D7-1; A6). Who paid: the customer, or an agency (energy assistance, a pledge). Only an agency payment may carry a restriction. Write-once from insert.';
COMMENT ON COLUMN public.payments.restricted_to_invoice_id IS
    'v5.4.2-23 (D7-1 b; A6). The bill an agency payment is restricted to (with restricted_to_line_item_id, one line of it). The restriction is stored on the payment and wins over the posting order; an application elsewhere says floor_over_restriction (the regulated-first floor). Write-once from insert.';
COMMENT ON COLUMN public.payments.status_recorded_at IS
    'v5.4.2-23 r2 (Codex B3). The database''s time of the latest status move (NULL until the first): stamped by the move, never written by a caller (a superuser''s history load keeps its own). Moves are forward only and the statuses a position counts (pending, posted) come before the ones it does not, so a refund counts at a recorded instant R when it was recorded by R and is still counted, or left after R.';
COMMENT ON COLUMN public.payments.status_cause_id IS
    'v5.4.2-23 (Q1 (a); M3), r3. The row behind the latest status move: posted — the posting ledger entry, of the payment''s kind (payment, deposit or refund), under reference_type payment, with nothing under it; nsf — an nsf row reversing it, after which nothing of it is left; reversed — another reversal of it (not nsf), likewise; voided (from pending) — none. r3: refunded is not a status (read from the position). A payment is born pending with none. Written in the same UPDATE as the status; checked against the table the status names (section 6).';

-- C1 (R-06). The customer's approval to hold an overpayment as a credit.
CREATE TABLE public.customer_credit_approvals (
    id           uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id    uuid NOT NULL,
    customer_id  uuid NOT NULL,
    payment_id   uuid NOT NULL,
    amount       numeric(12,2) NOT NULL,
    approved_by  uuid NOT NULL,
    created_at   timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT customer_credit_approvals_pkey PRIMARY KEY (id),
    CONSTRAINT customer_credit_approvals_amount_check CHECK (amount > 0),
    CONSTRAINT customer_credit_approvals_payment_fkey
        FOREIGN KEY (payment_id, tenant_id, customer_id) REFERENCES public.payments (id, tenant_id, customer_id),
    -- r2 (Opus S4): signed by a user of the approval's own tenant.
    CONSTRAINT customer_credit_approvals_approved_by_fkey FOREIGN KEY (approved_by, tenant_id) REFERENCES public.users (id, tenant_id),
    CONSTRAINT customer_credit_approvals_credit_key UNIQUE (id, tenant_id, customer_id, payment_id, amount)
);
ALTER TABLE public.customer_credit_approvals ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customer_credit_approvals FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON public.customer_credit_approvals USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));
CREATE INDEX idx_credit_approvals_payment ON public.customer_credit_approvals (payment_id);
CREATE TRIGGER a_stamp_created_at BEFORE INSERT ON public.customer_credit_approvals
    FOR EACH ROW EXECUTE FUNCTION public.stamp_log_created_at();
ALTER TABLE public.customer_credit_approvals ENABLE ALWAYS TRIGGER a_stamp_created_at;
CREATE TRIGGER append_only BEFORE DELETE OR UPDATE ON public.customer_credit_approvals
    FOR EACH ROW EXECUTE FUNCTION public.enforce_append_only();
ALTER TABLE public.customer_credit_approvals ENABLE ALWAYS TRIGGER append_only;
CREATE TRIGGER no_truncate BEFORE TRUNCATE ON public.customer_credit_approvals
    FOR EACH STATEMENT EXECUTE FUNCTION public.enforce_no_hard_delete();
ALTER TABLE public.customer_credit_approvals ENABLE ALWAYS TRIGGER no_truncate;
COMMENT ON TABLE public.customer_credit_approvals IS
    'v5.4.2-23 (R-06; C1). The customer''s approval, at the time of payment, to hold what is left of a payment as a credit for future bills: the payment, the approved amount, the user who took it, and the database''s time. Append-only. A credit of origin overpayment names exactly one approval and equals its amount and payment (FK on all five); an approval is used by one credit at most.';

ALTER TABLE public.customer_credits
    ADD COLUMN approval_id uuid,
    ADD COLUMN status_cause_id uuid,
    ADD COLUMN status_recorded_at timestamp with time zone;
ALTER TABLE public.customer_credits
    ADD CONSTRAINT customer_credits_approval_fkey
        FOREIGN KEY (approval_id, tenant_id, customer_id, source_payment_id, original_amount)
        REFERENCES public.customer_credit_approvals (id, tenant_id, customer_id, payment_id, amount),
    ADD CONSTRAINT customer_credits_overpayment_approved_check
        CHECK ((origin_type = 'overpayment') = (approval_id IS NOT NULL)
               AND (approval_id IS NULL OR source_payment_id IS NOT NULL)),
    -- r2 (Fable B1): only an overpayment credit names a payment, so every
    -- credit naming one is drawn on it and approved (guard the act, not the
    -- label). A deposit refund credit names its deposit (-15).
    ADD CONSTRAINT customer_credits_payment_overpayment_check
        CHECK (source_payment_id IS NULL OR origin_type = 'overpayment');
CREATE UNIQUE INDEX customer_credits_one_per_approval ON public.customer_credits (approval_id) WHERE approval_id IS NOT NULL;
-- r4 (Opus B3, Fable B1; K-10): a payment holds one live overpayment credit.
-- The bank's return of the payment takes back first what the credit still
-- holds (what it paid out stands, as a posted refund of the payment does), so
-- the credit's standing is read from its payment's posting entry; with one
-- live credit per payment that reading is unambiguous.
CREATE UNIQUE INDEX customer_credits_one_live_per_payment ON public.customer_credits (source_payment_id)
    WHERE source_payment_id IS NOT NULL AND status <> 'voided';
-- r4 (Ryan, 2026-10-21, option 1): a refund of a credit that comes back after
-- the credit was escheated goes into a new credit for the customer, origin
-- refund_reissue, naming the returned refund. Its money is the returned
-- refund's, already back on the ledger by the refund's undo, so it posts no
-- ledger row; it draws on the credit the refund came from (section 7), so
-- that credit stays at nothing left. One per returned refund.
ALTER TABLE public.customer_credits
    ADD COLUMN reissues_refund_id uuid,
    ADD CONSTRAINT customer_credits_reissue_refund_fkey
        FOREIGN KEY (reissues_refund_id, tenant_id, customer_id) REFERENCES public.payments (id, tenant_id, customer_id),
    ADD CONSTRAINT customer_credits_reissue_check
        CHECK ((origin_type = 'refund_reissue') = (reissues_refund_id IS NOT NULL));
CREATE UNIQUE INDEX customer_credits_one_per_reissued_refund ON public.customer_credits (reissues_refund_id) WHERE reissues_refund_id IS NOT NULL;
COMMENT ON COLUMN public.customer_credits.reissues_refund_id IS
    'v5.4.2-23 r4 (Ryan, 2026-10-21). For a credit of origin refund_reissue, and only for one: the refund of a credit that came back (nsf or reversed) whose money it carries. Its amount is the refund''s; it draws on the credit the refund came from and posts no ledger row. Fixed from insert.';
COMMENT ON COLUMN public.customer_credits.approval_id IS
    'v5.4.2-23 (R-06; C1). For a credit of origin overpayment, and only for one, the customer''s approval it was created under; the credit''s payment and amount are the approval''s (FK).';
COMMENT ON COLUMN public.customer_credits.status_recorded_at IS
    'v5.4.2-23 r2 (Codex B3; Fable S1). The database''s time of the latest status move (NULL until the first), as payments.status_recorded_at: a voided overpayment credit stops drawing on its payment from that instant.';
COMMENT ON COLUMN public.customer_credits.status_cause_id IS
    'v5.4.2-23 (Q1 (a); M3), r3. The row behind the latest status move: voided — the reversal of its credit_issued entry, after which nothing of it is left (an overpayment credit, which posts no ledger row: none); escheated — its escheated_to_state event, after which nothing of it is left. r3: refunded and donated are not statuses (read from the position). A credit is born active with none. Written in the same UPDATE as the status (section 6).';


-- ----------------------------------------------------------------------------
-- 4. Positions: the counters, derived (M1)
-- ----------------------------------------------------------------------------
-- The recorded instant a position reads is the database's: payments and
-- customer credits are stamped at insert as the ledger is (a superuser's
-- history load keeps its own), so a caller cannot choose where its row falls.
CREATE TRIGGER a_stamp_created_at BEFORE INSERT ON public.payments
    FOR EACH ROW EXECUTE FUNCTION public.stamp_log_created_at();
ALTER TABLE public.payments ENABLE ALWAYS TRIGGER a_stamp_created_at;
CREATE TRIGGER a_stamp_created_at BEFORE INSERT ON public.customer_credits
    FOR EACH ROW EXECUTE FUNCTION public.stamp_log_created_at();
ALTER TABLE public.customer_credits ENABLE ALWAYS TRIGGER a_stamp_created_at;

-- Required coordinates; NULL raises; no fallback onto a live column (memory
-- "temporal helper: no live fallback").
CREATE OR REPLACE FUNCTION public.cash_coordinates_required(p_what text, p_on date, p_recorded_at timestamp with time zone) RETURNS void
    LANGUAGE plpgsql IMMUTABLE
    SET search_path = public, pg_temp
    AS $$
BEGIN
    IF p_on IS NULL OR p_recorded_at IS NULL OR NOT pg_catalog.isfinite(p_on) OR NOT pg_catalog.isfinite(p_recorded_at) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('%s: a position is read at a finite money date and recorded instant, both given (on %s, recorded %s) (v5.4.2-23)', p_what, p_on, p_recorded_at),
            ERRCODE = 'null_value_not_allowed';
    END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.cash_coordinates_required(text, date, timestamp with time zone) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.cash_coordinates_required(text, date, timestamp with time zone) TO tally_app, tally_core;

-- r5 (Opus B1, Fable B1, Codex S1; Kyle, K-10): what a payment or a credit
-- had given at a recorded instant, by the statuses its rows had then: its
-- applications, its refunds pending or posted, and for a credit its
-- refund_reissue credits not voided, its donations net of their undos and
-- its remittances. A payment's overpayment credit is not counted here:
-- overpayment_split reads it.
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
         WHERE p_kind = 'credit' AND e.event_type = 'escheated_to_state' AND e.customer_credit_id = p_id AND e.created_at <= p_at) x
$$;
COMMENT ON FUNCTION public.cash_drawn_at(text, uuid, timestamp with time zone) IS
    'v5.4.2-23 r5. What a payment (p_kind payment) or a customer credit (p_kind credit) had given at a recorded instant, by the statuses its rows had then: applications (net of undos), refunds pending or posted, and for a credit its refund_reissue credits not voided, its donation rows net of their undos and its escheated_to_state events; all dates. A payment''s overpayment credits are not counted (overpayment_split reads them).';
REVOKE ALL ON FUNCTION public.cash_drawn_at(text, uuid, timestamp with time zone) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.cash_drawn_at(text, uuid, timestamp with time zone) TO tally_app, tally_core;

-- r6 (Codex B1): a refund_reissue credit carries money of the credit its
-- refund came from, so one descended (through any number of reissues) from
-- an overpayment credit carries its payment's money. The overpayment credit
-- at the root of that line: the credit itself for an overpayment credit,
-- NULL for a credit whose line starts anywhere else.
CREATE OR REPLACE FUNCTION public.overpayment_root(p_credit_id uuid) RETURNS uuid
    LANGUAGE sql STABLE
    SET search_path = public, pg_temp
    AS $$
    WITH RECURSIVE up(id, origin_type, reissues_refund_id, depth) AS (
        SELECT c.id, c.origin_type, c.reissues_refund_id, 1 FROM public.customer_credits c WHERE c.id = p_credit_id
        UNION ALL
        SELECT c.id, c.origin_type, c.reissues_refund_id, u.depth + 1
          FROM up u JOIN public.payments r ON r.id = u.reissues_refund_id
          JOIN public.customer_credits c ON c.id = r.refunds_customer_credit_id
         WHERE u.origin_type = 'refund_reissue' AND u.depth < 1000
    )
    SELECT u.id FROM up u WHERE u.origin_type = 'overpayment'
$$;
COMMENT ON FUNCTION public.overpayment_root(uuid) IS
    'v5.4.2-23 r6 (Codex B1). The overpayment credit at the root of a credit''s reissue line: the credit itself if it is an overpayment credit; for a refund_reissue credit, the root of the credit its refund came from; NULL otherwise. Walks at most 1000 reissues.';
REVOKE ALL ON FUNCTION public.overpayment_root(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.overpayment_root(uuid) TO tally_app, tally_core;

-- r6 (Codex B1): an overpayment credit and every refund_reissue credit
-- descended from it, whatever their status: the credits holding the
-- payment's money. Empty for a credit that is not an overpayment credit.
CREATE OR REPLACE FUNCTION public.overpayment_family(p_credit_id uuid)
    RETURNS TABLE (id uuid, created_at timestamp with time zone)
    LANGUAGE sql STABLE
    SET search_path = public, pg_temp
    AS $$
    WITH RECURSIVE down(id, depth) AS (
        SELECT c.id, 0 FROM public.customer_credits c WHERE c.id = p_credit_id AND c.origin_type = 'overpayment'
        UNION ALL
        SELECT k.id, d.depth + 1
          FROM down d JOIN public.payments r ON r.refunds_customer_credit_id = d.id
          JOIN public.customer_credits k ON k.reissues_refund_id = r.id
         WHERE d.depth < 1000
    )
    SELECT c.id, c.created_at FROM down d JOIN public.customer_credits c ON c.id = d.id
$$;
COMMENT ON FUNCTION public.overpayment_family(uuid) IS
    'v5.4.2-23 r6 (Codex B1). An overpayment credit and every refund_reissue credit descended from it (any status), with their recorded instants: the credits that hold its payment''s money. Empty for any other credit.';
REVOKE ALL ON FUNCTION public.overpayment_family(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.overpayment_family(uuid) TO tally_app, tally_core;

-- r6: what a payment holds at the coordinates before its overpayment credit
-- (received, applied, refunded), and what a credit gave (applied, refunded,
-- given up, carried). The positions and the cover between a payment and its
-- credits (overpayment_absorbed_as_of) read the same figures.
CREATE OR REPLACE FUNCTION public.payment_draws_as_of(p_payment_id uuid, p_on date, p_recorded_at timestamp with time zone)
    RETURNS TABLE (received numeric, applied numeric, refunded numeric)
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
                   WHERE a.payment_id = p_payment_id AND a.applied_on <= p_on AND a.created_at <= p_recorded_at), 0),
        coalesce((SELECT -sum(r.amount) FROM public.payments r
                   WHERE r.refunds_payment_id = p_payment_id AND r.payment_date <= p_on AND r.created_at <= p_recorded_at
                     AND (r.status IN ('pending', 'posted') OR r.status_recorded_at > p_recorded_at)), 0)
$$;
COMMENT ON FUNCTION public.payment_draws_as_of(uuid, date, timestamp with time zone) IS
    'v5.4.2-23 r6. A payment at a money date and a recorded instant, before its overpayment credit: received (its posting entry less what was taken back under it), applied (net of undos), refunded (its refunds pending or posted at the instant). Read by payment_position_as_of and overpayment_absorbed_as_of. No coordinate checks: the callers make them.';
REVOKE ALL ON FUNCTION public.payment_draws_as_of(uuid, date, timestamp with time zone) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.payment_draws_as_of(uuid, date, timestamp with time zone) TO tally_app, tally_core;

CREATE OR REPLACE FUNCTION public.customer_credit_draws_as_of(p_credit_id uuid, p_on date, p_recorded_at timestamp with time zone)
    RETURNS TABLE (applied numeric, refunded numeric, given_up numeric, carried numeric)
    LANGUAGE sql STABLE
    SET search_path = public, pg_temp
    AS $$
    SELECT
        coalesce((SELECT sum(a.amount) FROM public.invoice_applications a
                   WHERE a.customer_credit_id = p_credit_id AND a.applied_on <= p_on AND a.created_at <= p_recorded_at), 0),
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
$$;
COMMENT ON FUNCTION public.customer_credit_draws_as_of(uuid, date, timestamp with time zone) IS
    'v5.4.2-23 r6. What a credit gave at a money date and a recorded instant: applied (net of undos), refunded (its refunds pending or posted at the instant), given_up (its donation rows net of their undos, and its escheated_to_state events by their UTC day), carried (into refund_reissue credits not voided at the instant). Read by customer_credit_position_as_of and overpayment_absorbed_as_of. No coordinate checks: the callers make them.';
REVOKE ALL ON FUNCTION public.customer_credit_draws_as_of(uuid, date, timestamp with time zone) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.customer_credit_draws_as_of(uuid, date, timestamp with time zone) TO tally_app, tally_core;

-- r5 (Opus B1, Fable B1, Codex S1; Kyle, K-10): one split of what is taken
-- back under a payment's posting entry between the payment and its
-- overpayment credit, read by both positions and all the caps. r6 (Codex
-- B1): the credit's reissues hold its payment's money too, so the split is
-- between the payment and each credit of the family (overpayment_family).
-- Each row of the entry's tree, in recorded order, is shared out as it was
-- when it was recorded:
--   * a row recorded before the credit: to none (the credit was sized after
--     it);
--   * a row taking money back: first out of what the credits held at the
--     row's instant (the overpayment credit first, then each reissue in
--     recorded order), then out of what the payment's own part held; what
--     none held (K-10: what was paid out stands) falls on the overpayment
--     credit as far as its amount, then on the payment;
--   * a row giving money back: to the credits first, as far as they
--     absorbed, the latest share first.
-- Held means the amount less what was absorbed and what was given at that
-- instant (cash_drawn_at; a credit's reissues are given by it, as carried).
-- r6 (Codex B3): rows of one instant (one transaction) in the tree's own
-- order, a row before the rows under it, so a give-back never comes before
-- its take-back; the draws of that instant count as already made
-- (cash_drawn_at reads up to the instant). r6 (Opus B2, Fable B1): a row is
-- not recorded before a draw already counted on the payment or its credits
-- (enforce_ledger_reversal), so the recorded order is the order the rows
-- were made in. Each share is fixed once recorded; only which side carries a
-- shortfall is decided when a position is read (overpayment_absorbed_as_of).
-- One row per row of the tree and credit that took a share.
CREATE OR REPLACE FUNCTION public.overpayment_shares(p_credit_id uuid)
    RETURNS TABLE (id uuid, credit_id uuid, on_date date, created_at timestamp with time zone, absorbed numeric)
    LANGUAGE plpgsql STABLE
    SET search_path = public, pg_temp
    SET enable_seqscan = off
    SET enable_hashjoin = off
    SET enable_mergejoin = off
    AS $$
DECLARE
    c        public.customer_credits%ROWTYPE;
    v_pay    numeric;
    v_entry  uuid;
    v_ids    uuid[];
    v_amt    numeric[];
    v_at     timestamptz[];
    v_end    timestamptz[];
    v_abs    numeric[];
    v_hold   numeric[];
    v_tot    numeric := 0;
    v_tb     numeric := 0;
    v_held   numeric;
    v_hold_p numeric;
    v_take   numeric;
    v_short  numeric;
    v_left   numeric;
    v_part   numeric;
    i        integer;
    r        record;
BEGIN
    SELECT * INTO c FROM public.customer_credits k WHERE k.id = p_credit_id AND k.origin_type = 'overpayment';
    IF NOT FOUND THEN
        RETURN;
    END IF;
    SELECT p.amount INTO v_pay FROM public.payments p WHERE p.id = c.source_payment_id;
    v_entry := public.cash_arrival_entry('payment', c.source_payment_id);
    -- The family, the overpayment credit first, then by recorded order; each
    -- with when it ended (voided), if it did.
    SELECT array_agg(k.id ORDER BY k.id <> c.id, k.created_at, k.id),
           array_agg(k.original_amount ORDER BY k.id <> c.id, k.created_at, k.id),
           array_agg(k.created_at ORDER BY k.id <> c.id, k.created_at, k.id),
           array_agg(CASE WHEN k.status = 'voided' THEN k.status_recorded_at END ORDER BY k.id <> c.id, k.created_at, k.id)
      INTO v_ids, v_amt, v_at, v_end
      FROM public.overpayment_family(c.id) f JOIN public.customer_credits k ON k.id = f.id;
    v_abs := array_fill(0::numeric, ARRAY[cardinality(v_ids)]);
    v_hold := array_fill(0::numeric, ARRAY[cardinality(v_ids)]);
    -- The tree walked by its link alone (memory "recursive walks: pin the
    -- plan"), each row with its depth.
    FOR r IN WITH RECURSIVE t(id, depth) AS (
                 SELECT l.id, 1 FROM public.account_ledger l WHERE l.reverses_ledger_entry_id = v_entry
                 UNION ALL
                 SELECT l.id, t.depth + 1 FROM t JOIN public.account_ledger l ON l.reverses_ledger_entry_id = t.id
                  WHERE t.depth < 1000)
             SELECT l.id, l.transaction_date, l.amount, l.created_at FROM t JOIN public.account_ledger l ON l.id = t.id
              ORDER BY l.created_at, t.depth, l.id LOOP
        IF r.amount > 0 THEN
            -- What each credit held at the row's instant: a credit not yet
            -- recorded (so none, for a row recorded before the overpayment
            -- credit: it was sized after the row), or voided by then, holds
            -- nothing.
            v_held := 0;
            FOR i IN 1 .. cardinality(v_ids) LOOP
                v_hold[i] := CASE WHEN v_at[i] <= r.created_at AND (v_end[i] IS NULL OR v_end[i] > r.created_at)
                                  THEN greatest(v_amt[i] - v_abs[i] - public.cash_drawn_at('credit', v_ids[i], r.created_at), 0) ELSE 0 END;
                v_held := v_held + v_hold[i];
            END LOOP;
            v_hold_p := v_pay - c.original_amount - (v_tb - v_tot) - public.cash_drawn_at('payment', c.source_payment_id, r.created_at);
            v_take := least(r.amount, v_held);
            v_short := r.amount - v_take - least(r.amount - v_take, greatest(v_hold_p, 0));
            v_short := least(v_short, greatest(c.original_amount - v_tot - v_take, 0));
            v_left := v_take;
            FOR i IN 1 .. cardinality(v_ids) LOOP
                v_part := least(v_left, v_hold[i]) + CASE WHEN i = 1 THEN v_short ELSE 0 END;
                v_left := v_left - least(v_left, v_hold[i]);
                IF v_part <> 0 THEN
                    v_abs[i] := v_abs[i] + v_part;
                    v_tot := v_tot + v_part;
                    id := r.id; credit_id := v_ids[i]; on_date := r.transaction_date; created_at := r.created_at; absorbed := v_part;
                    RETURN NEXT;
                END IF;
            END LOOP;
        ELSE
            -- Given back to the credits as far as they absorbed, the latest
            -- share first (nothing, before any share was taken).
            v_left := least(-r.amount, v_tot);
            FOR i IN REVERSE cardinality(v_ids) .. 1 LOOP
                v_part := least(v_left, v_abs[i]);
                v_left := v_left - v_part;
                IF v_part <> 0 THEN
                    v_abs[i] := v_abs[i] - v_part;
                    v_tot := v_tot - v_part;
                    id := r.id; credit_id := v_ids[i]; on_date := r.transaction_date; created_at := r.created_at; absorbed := -v_part;
                    RETURN NEXT;
                END IF;
            END LOOP;
        END IF;
        v_tb := v_tb + r.amount;
    END LOOP;
END;
$$;
COMMENT ON FUNCTION public.overpayment_shares(uuid) IS
    'v5.4.2-23 r6 (Opus B2, Fable B1; Codex B1, B3; K-10). For an overpayment credit: the share of each row under its payment''s posting entry that each credit of its family (the credit and its refund_reissue descendants) absorbed, as recorded. Rows in recorded order (within one instant a row before the rows under it, then by id); none for a row recorded before the credit; a take-back comes first out of what the credits held at its instant (the overpayment credit first, then each reissue in recorded order), then out of the payment''s own part, and what none held falls on the overpayment credit as far as its amount, then on the payment; a give-back goes to the credits as far as they absorbed, the latest share first. One row per tree row and credit with a share. Read by overpayment_split, overpayment_absorbed_as_of and check_cash_source''s caps. Empty for any other credit.';
REVOKE ALL ON FUNCTION public.overpayment_shares(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.overpayment_shares(uuid) TO tally_app, tally_core;

-- Every row under the payment's posting entry with the part its overpayment
-- credit's family absorbed in all (overpayment_shares).
CREATE OR REPLACE FUNCTION public.overpayment_split(p_credit_id uuid)
    RETURNS TABLE (id uuid, on_date date, amount numeric, absorbed numeric, created_at timestamp with time zone)
    LANGUAGE plpgsql STABLE
    SET search_path = public, pg_temp
    AS $$
BEGIN
    RETURN QUERY
    SELECT l.id, l.transaction_date, l.amount, coalesce((SELECT sum(s.absorbed) FROM public.overpayment_shares(c.id) s WHERE s.id = l.id), 0), l.created_at
      FROM public.customer_credits c
      JOIN public.account_ledger l ON l.id = ANY (public.ledger_tree_ids(public.cash_arrival_entry('payment', c.source_payment_id)))
     WHERE c.id = p_credit_id AND c.origin_type = 'overpayment';
END;
$$;
COMMENT ON FUNCTION public.overpayment_split(uuid) IS
    'v5.4.2-23 r5 (Opus B1, Fable B1, Codex S1; K-10), r6. For an overpayment credit: every row under its payment''s posting entry, with the part the credit and its reissues absorbed in all (overpayment_shares, as recorded). Read by check_cash_source''s payment-side cap. Empty for any other credit.';
REVOKE ALL ON FUNCTION public.overpayment_split(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.overpayment_split(uuid) TO tally_app, tally_core;

-- r6 (Opus B1, Codex B2; K-10): which side carries a shortfall is decided
-- when a position is read, not when the take-back was recorded. The shares
-- say what each credit absorbed, as recorded; if the payment's own part then
-- reads a deficit while its credits hold money, or the credits a deficit
-- while the payment holds money, the side holding money covers the other as
-- far as it can: a credit in deficit is covered first, the overpayment
-- credit first; a payment in deficit is covered from the credits, the
-- overpayment credit first. A position then equals what its cap admits (its
-- own side, with the cap on the two together), and the two add up to the
-- ledger. Only what neither holds stays as K-10's debt. Without the cover
-- (p_cover false), the shares as recorded. One row per credit of the family
-- that exists at the coordinates.
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
BEGIN
    SELECT * INTO k FROM public.customer_credits c
     WHERE c.id = p_credit_id AND c.origin_type = 'overpayment'
       AND c.issued_date <= p_on AND c.created_at <= p_recorded_at
       AND (c.status <> 'voided' OR c.status_recorded_at > p_recorded_at);
    IF NOT FOUND THEN
        RETURN;
    END IF;
    -- The family at the coordinates, the overpayment credit first: each with
    -- its share as recorded, and what it holds after it.
    SELECT array_agg(c.id ORDER BY c.id <> k.id, c.created_at, c.id),
           array_agg(coalesce(s.absorbed, 0) ORDER BY c.id <> k.id, c.created_at, c.id),
           array_agg(c.original_amount - coalesce(s.absorbed, 0) - d.applied - d.refunded - d.given_up - d.carried ORDER BY c.id <> k.id, c.created_at, c.id)
      INTO v_ids, v_abs, v_own
      FROM public.overpayment_family(k.id) f
      JOIN public.customer_credits c ON c.id = f.id
      CROSS JOIN LATERAL public.customer_credit_draws_as_of(c.id, p_on, p_recorded_at) d
      LEFT JOIN LATERAL (SELECT sum(x.absorbed) AS absorbed FROM public.overpayment_shares(k.id) x
                          WHERE x.credit_id = c.id AND x.on_date <= p_on AND x.created_at <= p_recorded_at) s ON true
     WHERE c.issued_date <= p_on AND c.created_at <= p_recorded_at
       AND (c.status <> 'voided' OR c.status_recorded_at > p_recorded_at);
    IF p_cover THEN
        -- The payment's own part, with the shares as recorded.
        SELECT d.received - d.applied - d.refunded - (k.original_amount - (SELECT sum(x) FROM unnest(v_abs) x)) INTO v_p
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
    'v5.4.2-23 r6 (Opus B1, Codex B1, B2; K-10). For an overpayment credit at a money date and a recorded instant: what each credit of its family (the credit and its refund_reissue descendants, overpayment_family) absorbed of what was taken back under its payment''s posting entry. Starts from the shares as recorded (overpayment_shares); if the payment''s own part then reads a deficit while the credits hold money, or the credits a deficit while the payment holds money, the side holding money covers the other as far as it can (a credit in deficit, or the credit drawn on to cover the payment, the overpayment credit first). Read by both positions; with p_cover false, the shares as recorded. Empty for any other credit, or before the credit exists at the coordinates.';
REVOKE ALL ON FUNCTION public.overpayment_absorbed_as_of(uuid, date, timestamp with time zone, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.overpayment_absorbed_as_of(uuid, date, timestamp with time zone, boolean) TO tally_app, tally_core;

-- r2 (Codex B3; Opus B3, S1; Fable N2): a position at (a money date, a
-- recorded instant) reads the statuses the rows had at that instant
-- (status_recorded_at), and a bill line has none before its bill was issued.
-- It is fixed once the instant is older than every open transaction: a
-- transaction that began before it can still commit a row stamped earlier
-- (-22's model). Read an instant already past every writer for a figure that
-- will not move.
CREATE OR REPLACE FUNCTION public.payment_position_as_of(p_payment_id uuid, p_on date, p_recorded_at timestamp with time zone)
    RETURNS TABLE (amount numeric, received numeric, applied numeric, credited numeric, refunded numeric, remaining numeric)
    LANGUAGE plpgsql STABLE
    SET search_path = public, pg_temp
    AS $$
BEGIN
    PERFORM public.cash_coordinates_required('payment_position_as_of', p_on, p_recorded_at);
    -- received, applied and refunded: payment_draws_as_of. A bounced payment
    -- has received nothing, and if it was refunded first, remaining is
    -- negative: the customer owes what was paid out (Kyle's example).
    RETURN QUERY
    SELECT p.amount, d.received, d.applied, x.credited, d.refunded, d.received - d.applied - x.credited - d.refunded
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
    'v5.4.2-23 (M1; replaces payments.applied_amount / unapplied_amount), r3. A payment at a money date and a recorded instant: its amount; received (r3: what of it stands on the ledger, its posting entry less what was taken back under it, at the coordinates, read from the posting row whatever the status, r5); applied (net of its applications, undos included); credited (its credits not voided at the instant; r5: less what each absorbed of what was taken back under its posting entry; r6: the family''s share, with a shortfall placed at this reading, overpayment_absorbed_as_of); refunded (its refunds pending or posted at the instant, by status_recorded_at); remaining = received less the three (negative when it was refunded and then came back: the customer owes it, K-10). No row before the payment exists at the coordinates. NULL or infinite coordinates raise. Fixed once the instant is older than every open transaction (-22''s model).';
REVOKE ALL ON FUNCTION public.payment_position_as_of(uuid, date, timestamp with time zone) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.payment_position_as_of(uuid, date, timestamp with time zone) TO tally_app, tally_core;

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
                 WHEN c.origin_type = 'refund_reissue' THEN c.original_amount
                 ELSE coalesce((SELECT -sum(l.amount) FROM public.account_ledger e
                                  CROSS JOIN LATERAL unnest(public.ledger_tree_ids(e.id) || e.id) AS t(id)
                                  JOIN public.account_ledger l ON l.id = t.id
                                 WHERE e.reference_type = 'customer_credit' AND e.transaction_type = 'credit_issued' AND e.reference_id = c.id
                                   AND l.transaction_date <= p_on AND l.created_at <= p_recorded_at), 0) END AS issued) x
     WHERE c.id = p_credit_id AND c.issued_date <= p_on AND c.created_at <= p_recorded_at;
END;
$$;
COMMENT ON FUNCTION public.customer_credit_position_as_of(uuid, date, timestamp with time zone) IS
    'v5.4.2-23 (M1; replaces customer_credits.applied_amount / remaining_amount), r3. A credit at a money date and a recorded instant: its amount; issued (r3: what of it stands on the ledger, its credit_issued entry less what was withdrawn under it; an overpayment credit''s amount, its money being its payment''s); applied (net of its applications); refunded (its refunds pending or posted at the instant, by status_recorded_at); given_up (its donation ledger rows net of their undos, r3, and its escheated_to_state events, by their UTC day); carried (r4: its refunds that came back, carried into refund_reissue credits not voided at the instant); remaining = issued less the four. r5, r6: an overpayment credit''s issued, and a refund_reissue credit''s descended from one, is its amount less its share of what was taken back under the payment''s posting entry, with a shortfall placed at this reading (overpayment_absorbed_as_of); any other refund_reissue credit''s is its amount. No row before the credit exists at the coordinates. NULL or infinite coordinates raise. Fixed once the instant is older than every open transaction (-22''s model).';
REVOKE ALL ON FUNCTION public.customer_credit_position_as_of(uuid, date, timestamp with time zone) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.customer_credit_position_as_of(uuid, date, timestamp with time zone) TO tally_app, tally_core;

CREATE OR REPLACE FUNCTION public.invoice_line_position_as_of(p_line_id uuid, p_on date, p_recorded_at timestamp with time zone)
    RETURNS TABLE (amount numeric, applied numeric, open numeric)
    LANGUAGE plpgsql STABLE
    SET search_path = public, pg_temp
    AS $$
BEGIN
    PERFORM public.cash_coordinates_required('invoice_line_position_as_of', p_on, p_recorded_at);
    RETURN QUERY
    SELECT l.amount, x.applied, greatest(l.amount, 0) - x.applied
      FROM public.invoice_line_items l
      JOIN public.invoices i ON i.id = l.invoice_id
      CROSS JOIN LATERAL (SELECT
            coalesce((SELECT sum(a.amount) FROM public.invoice_applications a
                       WHERE a.invoice_line_item_id = l.id AND a.applied_on <= p_on AND a.created_at <= p_recorded_at), 0) AS applied) x
     WHERE l.id = p_line_id AND i.invoice_date <= p_on AND i.first_issued_at <= p_recorded_at;
END;
$$;
COMMENT ON FUNCTION public.invoice_line_position_as_of(uuid, date, timestamp with time zone) IS
    'v5.4.2-23 (M1, A1), r2. A bill line at a money date and a recorded instant: its amount; applied (net of its applications); open (what is left of a positive line; a credit or adjustment line takes no application and is never open). No row before the bill''s invoice_date, or before it was issued (first_issued_at, the database''s stamp): a draft bill''s lines have no position. NULL or infinite coordinates raise. Fixed once the instant is older than every open transaction (-22''s model; r3, Opus N3).';
REVOKE ALL ON FUNCTION public.invoice_line_position_as_of(uuid, date, timestamp with time zone) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.invoice_line_position_as_of(uuid, date, timestamp with time zone) TO tally_app, tally_core;

CREATE OR REPLACE FUNCTION public.invoice_position_as_of(p_invoice_id uuid, p_on date, p_recorded_at timestamp with time zone)
    RETURNS TABLE (lines_total numeric, applied numeric, open numeric)
    LANGUAGE plpgsql STABLE
    SET search_path = public, pg_temp
    AS $$
BEGIN
    PERFORM public.cash_coordinates_required('invoice_position_as_of', p_on, p_recorded_at);
    RETURN QUERY
    SELECT x.lines_total, x.applied, x.open
      FROM public.invoices i
      CROSS JOIN LATERAL (SELECT coalesce(sum(lp.amount), 0) AS lines_total, coalesce(sum(lp.applied), 0) AS applied,
                                 coalesce(sum(lp.open), 0) AS open
                            FROM public.invoice_line_items l
                            CROSS JOIN LATERAL public.invoice_line_position_as_of(l.id, p_on, p_recorded_at) lp
                           WHERE l.invoice_id = i.id) x
     WHERE i.id = p_invoice_id AND i.invoice_date <= p_on AND i.first_issued_at <= p_recorded_at;
END;
$$;
COMMENT ON FUNCTION public.invoice_position_as_of(uuid, date, timestamp with time zone) IS
    'v5.4.2-23 (M1; replaces invoices.amount_paid / balance). A bill at a money date and a recorded instant, from its lines: the lines'' total, what is applied to them, and what is open on its positive lines. The bill''s previous balance is not here: it is owed on the earlier bills'' lines, where oldest-first applies it. r2: no row before the bill''s invoice_date or before it was issued (first_issued_at). A voided bill keeps its applications until the core undoes them (R4), so its position still shows them. NULL or infinite coordinates raise. Fixed once the instant is older than every open transaction (-22''s model; r3, Opus N3).';
REVOKE ALL ON FUNCTION public.invoice_position_as_of(uuid, date, timestamp with time zone) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.invoice_position_as_of(uuid, date, timestamp with time zone) TO tally_app, tally_core;


-- ----------------------------------------------------------------------------
-- 5. The counters go (M1, M1b, M4)
-- ----------------------------------------------------------------------------
DROP MATERIALIZED VIEW public.credit_aging_statistics;
DROP INDEX public.idx_credits_active_balance;
DROP INDEX public.idx_credits_escheat_active;
DROP INDEX public.idx_payments_unapplied;
DROP INDEX public.idx_payments_deposits;
ALTER TABLE public.customer_credits
    DROP CONSTRAINT customer_credits_check,
    DROP CONSTRAINT customer_credits_applied_amount_check,
    DROP CONSTRAINT customer_credits_remaining_amount_check,
    DROP COLUMN applied_amount,
    DROP COLUMN remaining_amount;
-- r3 (Ryan, 2026-10-21): refunded and donated are not statuses either. They
-- said only that nothing was left, because of refunds or a donation: the
-- positions read that from the rows. As labels they were final, so a refund
-- check that bounced or was never cashed, or a donation keyed in error, had
-- no record (statuses move forward only). Without them, a failed refund or
-- an undone donation frees the money again. escheated stays: a remittance to
-- the state is not undone on our side.
ALTER TABLE public.customer_credits DROP CONSTRAINT customer_credits_status_check;
ALTER TABLE public.customer_credits ADD CONSTRAINT customer_credits_status_check
    CHECK ((status = ANY (ARRAY['active'::text, 'escheated'::text, 'voided'::text])));
ALTER TABLE public.payments DROP CONSTRAINT payments_status_check;
ALTER TABLE public.payments ADD CONSTRAINT payments_status_check
    CHECK ((status = ANY (ARRAY['pending'::text, 'posted'::text, 'nsf'::text, 'reversed'::text, 'voided'::text])));
ALTER TABLE public.payments
    DROP CONSTRAINT payments_deposit_status_check,
    DROP CONSTRAINT payments_deposit_status_consistent_check,
    DROP COLUMN applied_amount,
    DROP COLUMN unapplied_amount,
    DROP COLUMN deposit_status;
ALTER TABLE public.invoices
    DROP COLUMN amount_paid,
    DROP COLUMN balance;
CREATE INDEX idx_payments_deposits ON public.payments USING btree (customer_id) WHERE is_deposit;
CREATE INDEX idx_credits_active ON public.customer_credits USING btree (customer_id) WHERE status = 'active';
CREATE INDEX idx_credits_escheat_active ON public.customer_credits USING btree (tenant_id, last_activity_date)
    WHERE escheat_status = ANY (ARRAY['active'::text, 'dormancy_approaching'::text]);

-- The escheat view, rebuilt on the derived remainder (the money date and the
-- recorded instant of the refresh).
CREATE MATERIALIZED VIEW public.credit_aging_statistics AS
 SELECT cc.tenant_id,
    cc.id AS credit_id,
    cc.customer_id,
    cc.origin_type,
    cc.original_amount,
    pos.remaining AS remaining_amount,
    cc.issued_date,
    cc.last_activity_date,
    cc.escheat_status,
    cc.due_diligence_sent_at,
    (CURRENT_DATE - cc.last_activity_date) AS days_since_activity,
        CASE
            WHEN (cc.escheat_status = 'escheated'::text) THEN 'already_escheated'::text
            WHEN ((cc.escheat_status = 'due_diligence_sent'::text) AND (cc.due_diligence_sent_at < (now() - '60 days'::interval))) THEN 'escheat_overdue'::text
            WHEN ((CURRENT_DATE - cc.last_activity_date) >= 1095) THEN 'escheat_due'::text
            WHEN ((CURRENT_DATE - cc.last_activity_date) >= 1005) THEN 'dormancy_approaching'::text
            WHEN ((CURRENT_DATE - cc.last_activity_date) >= 365) THEN 'stale'::text
            ELSE 'active'::text
        END AS aging_bucket,
        CASE
            WHEN ((cc.origin_type = 'deposit_refund'::text) AND (pos.remaining > (0)::numeric) AND ((CURRENT_DATE - cc.issued_date) > 60)) THEN true
            ELSE false
        END AS deposit_refund_overdue,
    (pos.remaining >= (250)::numeric) AS above_due_diligence_threshold
   FROM public.customer_credits cc
   CROSS JOIN LATERAL public.customer_credit_position_as_of(cc.id, CURRENT_DATE, now()) pos
  WHERE ((cc.status = 'active'::text) AND (pos.remaining > (0)::numeric))
  WITH NO DATA;
COMMENT ON MATERIALIZED VIEW public.credit_aging_statistics IS
    'Escheat dormancy for active credits with something left. v5.4.2-23: remaining_amount is the derived remainder (customer_credit_position_as_of at the refresh''s date and instant), not a stored counter. Born WITH NO DATA: REFRESH it before reading.';
CREATE INDEX idx_credit_aging_bucket ON public.credit_aging_statistics USING btree (tenant_id, aging_bucket);
CREATE UNIQUE INDEX idx_credit_aging_credit ON public.credit_aging_statistics USING btree (credit_id);
CREATE INDEX idx_credit_aging_customer ON public.credit_aging_statistics USING btree (customer_id);
CREATE INDEX idx_credit_aging_deposit_overdue ON public.credit_aging_statistics USING btree (tenant_id) WHERE (deposit_refund_overdue = true);
CREATE INDEX idx_credit_aging_tenant ON public.credit_aging_statistics USING btree (tenant_id);
-- A matview carries no RLS: no role but its owner reads it (the tenant
-- isolation invariant).
REVOKE ALL ON public.credit_aging_statistics FROM PUBLIC, tally_app, tally_core;


-- ----------------------------------------------------------------------------
-- 6. Write-once from insert, and status moves that name their row (M2, M3)
-- ----------------------------------------------------------------------------
-- The advisory lock of a payment or a credit as a source of money: an
-- application, an overpayment credit and a refund drawing on it take it, and
-- so does a status move that ends it. Whichever comes second sees the first.
CREATE OR REPLACE FUNCTION public.cash_source_lock_key(p_kind text, p_id uuid) RETURNS bigint
    LANGUAGE sql IMMUTABLE
    SET search_path = public, pg_temp
    AS $$ SELECT pg_catalog.hashtextextended('cash_source:' || p_kind || ':' || p_id::text, 0) $$;
COMMENT ON FUNCTION public.cash_source_lock_key(text, uuid) IS
    'v5.4.2-23 (A3, M3). The advisory lock key of a payment (p_kind payment) or a customer credit (p_kind credit) as a source of money, or of a bill line (p_kind line) as a target. Lock order: the tenant''s close head, then the source, then the line.';
REVOKE ALL ON FUNCTION public.cash_source_lock_key(text, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.cash_source_lock_key(text, uuid) TO tally_app, tally_core;

CREATE OR REPLACE FUNCTION public.enforce_payment_immutable()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
    v_changed text[] := '{}';
    v_col     text;
    v_old     jsonb := to_jsonb(OLD);
    v_new     jsonb := to_jsonb(NEW);
    v_ok      boolean;
    v_at      timestamptz;
    v_super   boolean := (SELECT r.rolsuper FROM pg_catalog.pg_roles r WHERE r.rolname = current_user);
    v_kind    text := CASE WHEN OLD.refunds_payment_id IS NOT NULL OR OLD.refunds_customer_credit_id IS NOT NULL THEN 'refund'
                           WHEN OLD.is_deposit THEN 'deposit' ELSE 'payment' END;
    -- M2: fixed from insert. R-05: a correction is a reversal plus a new row.
    c_fixed CONSTANT text[] := ARRAY['id', 'tenant_id', 'payment_number', 'customer_id', 'payment_date', 'amount',
        'payment_method', 'channel', 'source_system', 'is_deposit', 'payer_class', 'restricted_to_invoice_id',
        'restricted_to_line_item_id', 'nsf_original_payment_id', 'refunds_payment_id', 'refunds_customer_credit_id', 'created_at'];
    -- Write-once: a reference that arrives later (a settlement's code, the
    -- returned item's reason) is written once and never changed.
    c_once CONSTANT text[] := ARRAY['payment_method_id', 'reference_number', 'provider_transaction_id',
        'provider_authorization_code', 'check_number', 'check_date', 'check_bank_name', 'received_by',
        'nsf_date', 'nsf_reason', 'nsf_fee_charge_id', 'refund_reason', 'reversed_at', 'reversed_by', 'reversed_reason'];
BEGIN
    FOREACH v_col IN ARRAY c_fixed LOOP
        IF v_new -> v_col IS DISTINCT FROM v_old -> v_col THEN v_changed := v_changed || v_col; END IF;
    END LOOP;
    FOREACH v_col IN ARRAY c_once LOOP
        IF v_old -> v_col <> 'null'::jsonb AND v_new -> v_col IS DISTINCT FROM v_old -> v_col THEN v_changed := v_changed || v_col; END IF;
    END LOOP;
    IF cardinality(v_changed) > 0 THEN
        RAISE EXCEPTION USING
            MESSAGE = format('payment %s: %s is written once, at insert or when first recorded (R-05, CI-013; v5.4.2-23) — reverse the payment and post a new one', OLD.payment_number, array_to_string(v_changed, ', ')),
            ERRCODE = 'restrict_violation';
    END IF;

    -- r5 (Codex B4): a status is recorded at a time already reached, for
    -- any role: a history load chooses a past time; a future one would hide
    -- the move from every reader (and the commit-time check) until it came.
    IF NEW.status_recorded_at IS DISTINCT FROM OLD.status_recorded_at
       AND (NOT pg_catalog.isfinite(NEW.status_recorded_at) OR NEW.status_recorded_at > pg_catalog.clock_timestamp()) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('payment %s: status_recorded_at %s is not a time already reached — a status is recorded at a finite time already reached (Q1 (a), v5.4.2-23)', OLD.payment_number, NEW.status_recorded_at),
            ERRCODE = 'check_violation';
    END IF;
    -- r6 (Codex B4): for every role. The split and the positions read a
    -- refund's status time, so moving it later with the status unchanged
    -- would rewrite which side held what, with no lock and no check.
    IF NEW.status IS NOT DISTINCT FROM OLD.status THEN
        IF NEW.status_cause_id IS DISTINCT FROM OLD.status_cause_id
           OR NEW.status_recorded_at IS DISTINCT FROM OLD.status_recorded_at THEN
            RAISE EXCEPTION USING
                MESSAGE = format('payment %s: status_cause_id and status_recorded_at change only with the status they explain (Q1 (a), v5.4.2-23)', OLD.payment_number),
                ERRCODE = 'restrict_violation';
        END IF;
        RETURN NEW;
    END IF;
    -- r2 (Codex B2): a move that ends a source reads what draws on it; under
    -- REPEATABLE READ its snapshot would hide a draw committed while it
    -- waited for the lock.
    IF pg_catalog.current_setting('transaction_isolation') <> 'read committed' THEN
        RAISE EXCEPTION USING
            MESSAGE = format('payment %s: a status move is written at READ COMMITTED (this transaction is %s): it must see every draw committed while it waited (CI-013, v5.4.2-23)', OLD.payment_number, pg_catalog.current_setting('transaction_isolation')),
            ERRCODE = 'invalid_transaction_state';
    END IF;
    -- r2 (Codex B3): the database's time of the move, so a position at a
    -- recorded instant reads the status the row had then (a superuser's
    -- history load keeps its own).
    IF NOT v_super OR NEW.status_recorded_at IS NOT DISTINCT FROM OLD.status_recorded_at THEN
        NEW.status_recorded_at := pg_catalog.now();
    END IF;
    -- Forward only: pending to posted or voided; posted to nsf or reversed;
    -- nothing leaves nsf, reversed or voided. r3 (Ryan, 2026-10-21): refunded
    -- is not a status; a payment refunded in full reads nothing left.
    IF NOT ((OLD.status = 'pending' AND NEW.status IN ('posted', 'voided'))
            OR (OLD.status = 'posted' AND NEW.status IN ('nsf', 'reversed'))) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('payment %s cannot move from %s to %s (CI-013; v5.4.2-23): pending moves to posted or voided, posted to nsf or reversed, and the rest are terminal — post a new payment (a refund is read from the position, not a status)', OLD.payment_number, OLD.status, NEW.status),
            ERRCODE = 'restrict_violation';
    END IF;
    -- The move and anything drawing on the payment serialise on its lock.
    PERFORM pg_catalog.pg_advisory_xact_lock(public.cash_source_lock_key('payment', OLD.id));

    -- Q1 (a): the move names the row behind it.
    v_ok := CASE NEW.status
        -- r2 (Codex B4): the posting entry is of the payment's own kind. r3
        -- (Opus B1, N1): under the one label the ledger admits, and with
        -- nothing under it yet (an entry already undone posts no money).
        WHEN 'posted' THEN EXISTS (
            SELECT 1 FROM public.account_ledger l
             WHERE l.id = NEW.status_cause_id AND l.tenant_id = NEW.tenant_id AND l.customer_id = NEW.customer_id
               AND l.transaction_type = v_kind
               AND l.reference_type = 'payment' AND l.reference_id = NEW.id AND l.amount = -NEW.amount
               AND cardinality(public.ledger_tree_ids(l.id)) = 0)
        -- r2 (Opus B2 O3): and the posting entry is then wholly undone; a
        -- 1.00 row does not end a 30.00 payment.
        WHEN 'nsf' THEN EXISTS (
            SELECT 1 FROM public.account_ledger l JOIN public.account_ledger o ON o.id = l.reverses_ledger_entry_id
             WHERE l.id = NEW.status_cause_id AND l.transaction_type = 'nsf' AND l.customer_id = NEW.customer_id
               AND o.id = OLD.status_cause_id AND public.ledger_entry_remaining(o.id) = 0)
        WHEN 'reversed' THEN EXISTS (
            SELECT 1 FROM public.account_ledger l JOIN public.account_ledger o ON o.id = l.reverses_ledger_entry_id
             WHERE l.id = NEW.status_cause_id AND l.transaction_type <> 'nsf' AND l.customer_id = NEW.customer_id
               AND o.id = OLD.status_cause_id AND public.ledger_entry_remaining(o.id) = 0)
        WHEN 'voided' THEN NEW.status_cause_id IS NULL
    END;
    IF NOT v_ok THEN
        RAISE EXCEPTION USING
            MESSAGE = format('payment %s: the move to %s names the row behind it in status_cause_id (%s) — %s (Q1 (a), v5.4.2-23)', OLD.payment_number, NEW.status, coalesce(NEW.status_cause_id::text, 'none'),
                             CASE NEW.status
                                 WHEN 'posted' THEN format('its posting ledger entry (of type %s, referencing this payment, at minus its amount, with nothing under it)', v_kind)
                                 WHEN 'nsf' THEN 'an nsf ledger row reversing its posting entry, which then has nothing left'
                                 WHEN 'reversed' THEN 'a ledger row (not nsf) reversing its posting entry, which then has nothing left'
                                 ELSE 'none: a pending payment moved no money' END),
            ERRCODE = 'foreign_key_violation';
    END IF;
    IF NEW.status = 'voided' AND EXISTS (SELECT 1 FROM public.account_ledger l WHERE l.reference_type IN ('payment', 'refund') AND l.reference_id = NEW.id) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('payment %s is on the ledger: it is reversed, not voided (CI-013, v5.4.2-23)', OLD.payment_number),
            ERRCODE = 'restrict_violation';
    END IF;
    -- Guard the act: money that bounced, was reversed or never arrived is not
    -- still paying a bill or held as a credit.
    -- r4 (Opus B3, Fable B1; K-10): an overpayment credit holds it only while
    -- the credit is applied or has a refund pending; what the credit paid out
    -- stands. r5: a draw on the credit takes the payment's lock first, so
    -- the payment's lock (taken above) orders it.
    -- r6 (Codex B1): and while a reissue descended from that credit is
    -- applied or has a refund pending: it holds the payment's money too.
    IF NEW.status IN ('nsf', 'reversed', 'voided') THEN
        IF coalesce((SELECT sum(a.amount) FROM public.invoice_applications a WHERE a.payment_id = NEW.id), 0) <> 0
           OR EXISTS (SELECT 1 FROM public.customer_credits k CROSS JOIN LATERAL public.overpayment_family(k.id) f
                       JOIN public.customer_credits c ON c.id = f.id
                       WHERE k.source_payment_id = NEW.id AND k.status <> 'voided' AND c.status <> 'voided'
                         AND (coalesce((SELECT sum(a.amount) FROM public.invoice_applications a WHERE a.customer_credit_id = c.id), 0) <> 0
                              OR EXISTS (SELECT 1 FROM public.payments r WHERE r.refunds_customer_credit_id = c.id AND r.status = 'pending'))) THEN
            RAISE EXCEPTION USING
                MESSAGE = format('payment %s cannot move to %s while it is applied to bills (or its overpayment credit or a reissue of it is), or a refund of the credit is waiting to go out: undo the applications and cancel the refund first (CI-013, v5.4.2-23)', OLD.payment_number, NEW.status),
                ERRCODE = 'restrict_violation';
        END IF;
    END IF;
    -- r3: a refund that leaves (cancelled while pending, or its posting row
    -- undone and the refund returned) gives its money back to its source.
    -- The move takes the source's lock, so the next draw on the source waits
    -- for it and sees it, and a draw begun before it is retried
    -- (check_cash_source's recorded order): a position is never read with
    -- both counted. r6 (Fable S1): a credit's refund takes the lock of the
    -- payment whose money the credit holds first (overpayment_root), then
    -- the credit's, as every other writer on the two does: the return, the
    -- move and the reissue in one transaction then take payment, then credit.
    IF v_kind = 'refund' AND NEW.status IN ('voided', 'nsf', 'reversed') THEN
        IF OLD.refunds_payment_id IS NOT NULL THEN
            PERFORM pg_catalog.pg_advisory_xact_lock(public.cash_source_lock_key('payment', OLD.refunds_payment_id));
        ELSE
            PERFORM pg_catalog.pg_advisory_xact_lock(public.cash_source_lock_key('payment', k.source_payment_id))
               FROM public.customer_credits k WHERE k.id = public.overpayment_root(OLD.refunds_customer_credit_id);
            PERFORM pg_catalog.pg_advisory_xact_lock(public.cash_source_lock_key('credit', OLD.refunds_customer_credit_id));
        END IF;
    END IF;
    -- r6 (Codex B4): a history load's chosen status time is not before a row
    -- already recorded on the payment's lineage (or, for a refund, on its
    -- source's): the split and the positions would read the move as made
    -- before something that had already happened. Under the locks above.
    IF v_super AND NEW.status_recorded_at <> pg_catalog.now() THEN
        v_at := greatest(public.cash_lineage_recorded('payment', OLD.id),
                         CASE WHEN OLD.refunds_payment_id IS NOT NULL THEN public.cash_lineage_recorded('payment', OLD.refunds_payment_id)
                              WHEN OLD.refunds_customer_credit_id IS NOT NULL THEN public.cash_lineage_recorded('credit', OLD.refunds_customer_credit_id) END);
        IF NEW.status_recorded_at < v_at THEN
            RAISE EXCEPTION USING
                MESSAGE = format('payment %s moves to %s at %s, a time chosen for it, before a row already recorded on its lineage (at %s) — a history load records a move after every row it follows (Q1 (a), v5.4.2-23)', OLD.payment_number, NEW.status, NEW.status_recorded_at, v_at),
                ERRCODE = 'check_violation';
        END IF;
    END IF;
    RETURN NEW;
END;
$fn$;
COMMENT ON FUNCTION public.enforce_payment_immutable() IS
    'CI-013 guard for payments (v5.4.2-01), rewritten in v5.4.2-23 (R-05; Q1 (a)). Identity, amount, designation, payer class, restriction and lineage are fixed from insert; the references that arrive later are write-once. Status moves forward only (pending to posted or voided; posted to nsf or reversed; r3: refunded is not a status), under the payment''s source lock, and names its row in status_cause_id: posted its posting ledger entry (with nothing under it), nsf the nsf row reversing it, reversed a ledger reversal of it, voided nothing (and no ledger row references it). nsf, reversed and voided require its applications, and its overpayment credit''s, to net to 0 and no refund of the credit pending (r4: what the credit paid out stands). A refund that leaves (voided, nsf, reversed) takes its source''s lock (r3; r6, Fable S1: a credit''s refund takes the lock of the payment whose money the credit holds first). r6 (Codex B1, B4): nsf, reversed and voided also wait on a reissue descended from the overpayment credit; status_cause_id and status_recorded_at change only with the status, for every role; a superuser''s chosen status time is not before a row already recorded on the lineage (cash_lineage_recorded).';

CREATE OR REPLACE FUNCTION public.enforce_customer_credit_immutable()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
    v_changed text[] := '{}';
    v_col     text;
    v_old     jsonb := to_jsonb(OLD);
    v_new     jsonb := to_jsonb(NEW);
    v_ok      boolean;
    v_left    numeric;
    v_from    uuid;
    v_at      timestamptz;
    v_super   boolean := (SELECT r.rolsuper FROM pg_catalog.pg_roles r WHERE r.rolname = current_user);
    c_fixed CONSTANT text[] := ARRAY['id', 'tenant_id', 'customer_id', 'origin_type', 'origin_notes', 'source_payment_id',
        'source_adhoc_charge_id', 'source_invoice_id', 'source_reference', 'original_amount', 'issued_date', 'issued_by',
        'deposit_id', 'approval_id', 'reissues_refund_id', 'created_at'];
BEGIN
    FOREACH v_col IN ARRAY c_fixed LOOP
        IF v_new -> v_col IS DISTINCT FROM v_old -> v_col THEN v_changed := v_changed || v_col; END IF;
    END LOOP;
    IF OLD.escheated_at IS NOT NULL AND NEW.escheated_at IS DISTINCT FROM OLD.escheated_at THEN v_changed := v_changed || 'escheated_at'::text; END IF;
    IF cardinality(v_changed) > 0 THEN
        RAISE EXCEPTION USING
            MESSAGE = format('customer credit %s: %s is fixed from insert (R-05, CI-013; v5.4.2-23) — void it and issue a new credit', OLD.id, array_to_string(v_changed, ', ')),
            ERRCODE = 'restrict_violation';
    END IF;

    -- r5 (Codex B4): a status is recorded at a time already reached, for
    -- any role: a history load chooses a past time; a future one would hide
    -- the move from every reader (and the commit-time check) until it came.
    IF NEW.status_recorded_at IS DISTINCT FROM OLD.status_recorded_at
       AND (NOT pg_catalog.isfinite(NEW.status_recorded_at) OR NEW.status_recorded_at > pg_catalog.clock_timestamp()) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('customer credit %s: status_recorded_at %s is not a time already reached — a status is recorded at a finite time already reached (Q1 (a), v5.4.2-23)', OLD.id, NEW.status_recorded_at),
            ERRCODE = 'check_violation';
    END IF;
    -- r6 (Codex B4): for every role, as for a payment.
    IF NEW.status IS NOT DISTINCT FROM OLD.status THEN
        IF NEW.status_cause_id IS DISTINCT FROM OLD.status_cause_id
           OR NEW.status_recorded_at IS DISTINCT FROM OLD.status_recorded_at THEN
            RAISE EXCEPTION USING
                MESSAGE = format('customer credit %s: status_cause_id and status_recorded_at change only with the status they explain (Q1 (a), v5.4.2-23)', OLD.id),
                ERRCODE = 'restrict_violation';
        END IF;
        RETURN NEW;
    END IF;
    -- r2 (Codex B2): READ COMMITTED, as for a payment.
    IF pg_catalog.current_setting('transaction_isolation') <> 'read committed' THEN
        RAISE EXCEPTION USING
            MESSAGE = format('customer credit %s: a status move is written at READ COMMITTED (this transaction is %s): it must see every draw committed while it waited (CI-013, v5.4.2-23)', OLD.id, pg_catalog.current_setting('transaction_isolation')),
            ERRCODE = 'invalid_transaction_state';
    END IF;
    -- r2 (Codex B3): the database's time of the move.
    IF NOT v_super OR NEW.status_recorded_at IS NOT DISTINCT FROM OLD.status_recorded_at THEN
        NEW.status_recorded_at := pg_catalog.now();
    END IF;
    -- r3 (Ryan, 2026-10-21): refunded and donated are not statuses; a credit
    -- refunded or donated in full reads nothing left.
    IF NOT (OLD.status = 'active' AND NEW.status IN ('escheated', 'voided')) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('customer credit %s cannot move from %s to %s (CI-013; v5.4.2-23): an active credit ends escheated or voided, and those are terminal — issue a new credit (a refund or donation is read from the position, not a status)', OLD.id, OLD.status, NEW.status),
            ERRCODE = 'restrict_violation';
    END IF;
    -- r3 (Codex B7): an overpayment credit's void gives its money back to its
    -- payment, so it takes the payment's lock too, and a draw on the payment
    -- begun before it is retried (check_cash_source's recorded order). r4: the
    -- source's lock first, then the credit's (as the bounce guard takes them:
    -- payment, then credit). A refund_reissue credit's void gives its money
    -- back to the credit its refund came from: likewise, and only to a credit
    -- still active (Ryan, 2026-10-21: nothing comes back to an escheated one).
    IF NEW.status = 'voided' AND OLD.source_payment_id IS NOT NULL THEN
        PERFORM pg_catalog.pg_advisory_xact_lock(public.cash_source_lock_key('payment', OLD.source_payment_id));
    END IF;
    IF NEW.status = 'voided' AND OLD.reissues_refund_id IS NOT NULL THEN
        SELECT r.refunds_customer_credit_id INTO v_from FROM public.payments r WHERE r.id = OLD.reissues_refund_id;
        PERFORM pg_catalog.pg_advisory_xact_lock(public.cash_source_lock_key('credit', v_from));
        IF NOT EXISTS (SELECT 1 FROM public.customer_credits c WHERE c.id = v_from AND c.status = 'active') THEN
            RAISE EXCEPTION USING
                MESSAGE = format('customer credit %s cannot be voided: its money would go back to credit %s, which is escheated or voided (Ryan, 2026-10-21; v5.4.2-23)', OLD.id, v_from),
                ERRCODE = 'restrict_violation';
        END IF;
    END IF;
    PERFORM pg_catalog.pg_advisory_xact_lock(public.cash_source_lock_key('credit', OLD.id));
    v_ok := CASE NEW.status
        -- r2: an overpayment credit's money is its payment's and posts no
        -- ledger row (a credit_issued row would count it twice), so its void
        -- names nothing. Any other credit's names the reversal of its
        -- credit_issued entry, which then has nothing left. r4: so does a
        -- refund_reissue credit's, and (Fable S3) a credit never issued on
        -- the ledger.
        WHEN 'voided' THEN CASE WHEN OLD.origin_type IN ('overpayment', 'refund_reissue') OR public.cash_arrival_entry('credit', OLD.id) IS NULL
                                THEN NEW.status_cause_id IS NULL ELSE EXISTS (
            SELECT 1 FROM public.account_ledger l JOIN public.account_ledger o ON o.id = l.reverses_ledger_entry_id
             WHERE l.id = NEW.status_cause_id AND l.customer_id = NEW.customer_id
               AND o.transaction_type = 'credit_issued' AND o.reference_type = 'customer_credit' AND o.reference_id = NEW.id
               AND public.ledger_entry_remaining(o.id) = 0) END
        -- r2 (Codex B4): the remittance, not a row merely about the credit.
        WHEN 'escheated' THEN EXISTS (
            SELECT 1 FROM public.escheatment_events e WHERE e.id = NEW.status_cause_id AND e.customer_credit_id = NEW.id
               AND e.event_type = 'escheated_to_state')
    END;
    IF NOT v_ok THEN
        RAISE EXCEPTION USING
            MESSAGE = format('customer credit %s: the move to %s names the row behind it in status_cause_id (%s) — %s (Q1 (a), v5.4.2-23)', OLD.id, NEW.status, coalesce(NEW.status_cause_id::text, 'none'),
                             CASE NEW.status
                                 WHEN 'voided' THEN CASE WHEN OLD.origin_type IN ('overpayment', 'refund_reissue') OR public.cash_arrival_entry('credit', OLD.id) IS NULL THEN 'none: it has no credit_issued entry'
                                                         ELSE 'the ledger row reversing its credit_issued entry, which then has nothing left' END
                                 ELSE 'its escheated_to_state escheatment event' END),
            ERRCODE = 'foreign_key_violation';
    END IF;
    -- Guard the act (r2: every draw, donation and escheat included): an
    -- escheated credit has nothing left (r3: of what stands on the ledger,
    -- less any withdrawal); a voided one is not drawn on at all (undo its
    -- applications, refunds and donations first).
    -- r4 (Codex B2; K-10 2 by analogy): not escheated while a refund of it
    -- is waiting to go out; the operator posts or cancels it first.
    IF NEW.status = 'escheated' AND EXISTS (SELECT 1 FROM public.payments r WHERE r.refunds_customer_credit_id = NEW.id AND r.status = 'pending') THEN
        RAISE EXCEPTION USING
            MESSAGE = format('customer credit %s is not escheated while a refund of it is waiting to go out: post or cancel the refund first (v5.4.2-23)', OLD.id),
            ERRCODE = 'restrict_violation';
    END IF;
    SELECT coalesce(sum(d.amount), 0) INTO v_left FROM public.cash_source_draws('credit', NEW.id) d;
    IF NEW.status = 'escheated' THEN
        -- What stands of it, less what it gave: its position at the last date
        -- and now. r6 (Opus B1, Codex B1, B2): for a credit holding a
        -- payment's money, with the take-backs placed between the payment and
        -- its credits at this reading (overpayment_absorbed_as_of).
        SELECT x.remaining INTO v_left
          FROM public.customer_credit_position_as_of(NEW.id, DATE '9999-12-31', pg_catalog.clock_timestamp()) x;
        IF v_left <> 0 THEN
            RAISE EXCEPTION USING
                MESSAGE = format('customer credit %s moves to escheated only when nothing of it is left: %s remains (CI-013, v5.4.2-23)', OLD.id, v_left),
                ERRCODE = 'restrict_violation';
        END IF;
    END IF;
    IF NEW.status = 'voided' AND v_left <> 0 THEN
        RAISE EXCEPTION USING
            MESSAGE = format('customer credit %s cannot be voided while %s of it is drawn on (applied, refunded, donated or escheated): undo those first (CI-013, v5.4.2-23)', OLD.id, v_left),
            ERRCODE = 'restrict_violation';
    END IF;
    -- r6 (Codex B4): a history load's chosen status time is not before a row
    -- already recorded on the credit's lineage.
    IF v_super AND NEW.status_recorded_at <> pg_catalog.now() THEN
        v_at := public.cash_lineage_recorded('credit', OLD.id);
        IF NEW.status_recorded_at < v_at THEN
            RAISE EXCEPTION USING
                MESSAGE = format('customer credit %s moves to %s at %s, a time chosen for it, before a row already recorded on its lineage (at %s) — a history load records a move after every row it follows (Q1 (a), v5.4.2-23)', OLD.id, NEW.status, NEW.status_recorded_at, v_at),
                ERRCODE = 'check_violation';
        END IF;
    END IF;
    RETURN NEW;
END;
$fn$;
COMMENT ON FUNCTION public.enforce_customer_credit_immutable() IS
    'CI-013 guard for customer credits (v5.4.2-01), rewritten in v5.4.2-23 (R-05; Q1 (a)). Origin, amount, dates, lineage and approval are fixed from insert; escheated_at is write-once. Status moves from active to escheated or voided (r3: refunded and donated are not statuses), and no further, under the credit''s source lock (an overpayment credit''s void also under its payment''s, r3), naming its row in status_cause_id: voided a ledger reversal of its issuing entry (an overpayment credit: none) and nothing drawn on it, escheated its escheatment event and nothing left of what stands on the ledger (r6: its position at the last date and now, with a shortfall placed at that reading). r6 (Codex B4): status_cause_id and status_recorded_at change only with the status, for every role; a superuser''s chosen status time is not before a row already recorded on the lineage (cash_lineage_recorded).';


-- r2 (Fable S3; Opus B2 O1): births. A payment is born pending and a credit
-- active, naming no cause: every other status is reached by a move that
-- names its row. A superuser's history load keeps its own (as created_at).
-- r5 (Fable N1): a payment's posting row is written only while it is
-- pending, so a history load inserts it pending, writes the row, then moves
-- it with a chosen status_recorded_at, a time already reached (Codex B4).
CREATE OR REPLACE FUNCTION public.enforce_cash_birth() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
BEGIN
    -- r6 (Opus S1): so is its recorded instant, for any role (a superuser's
    -- history load keeps its own created_at; the app's is stamped after this
    -- trigger, by a_stamp_created_at, with the transaction's time). One in
    -- the future would hide the row from every position until it came, while
    -- the caps count it, and turn every later draw on the source into a
    -- retry that cannot succeed (as the ledger's, -22 r5).
    IF NEW.created_at IS NOT NULL AND (SELECT r.rolsuper FROM pg_catalog.pg_roles r WHERE r.rolname = current_user)
       AND (NOT pg_catalog.isfinite(NEW.created_at) OR NEW.created_at > pg_catalog.clock_timestamp()) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('%s %s is recorded at %s, not a time already reached — every money row is recorded at a finite time already reached (v5.4.2-23)', TG_TABLE_NAME, NEW.id, NEW.created_at),
            ERRCODE = 'check_violation';
    END IF;
    -- r5 (Codex B4): a history load's status time is one already reached.
    IF NEW.status_recorded_at IS NOT NULL
       AND (NOT pg_catalog.isfinite(NEW.status_recorded_at) OR NEW.status_recorded_at > pg_catalog.clock_timestamp()) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('%s %s is born with status_recorded_at %s, not a time already reached — a status is recorded at a finite time already reached (Q1 (a), v5.4.2-23)', TG_TABLE_NAME, NEW.id, NEW.status_recorded_at),
            ERRCODE = 'check_violation';
    END IF;
    IF (SELECT r.rolsuper FROM pg_catalog.pg_roles r WHERE r.rolname = current_user) THEN
        RETURN NEW;
    END IF;
    IF NEW.status IS DISTINCT FROM (CASE TG_TABLE_NAME WHEN 'payments' THEN 'pending' ELSE 'active' END)
       OR NEW.status_cause_id IS NOT NULL OR NEW.status_recorded_at IS NOT NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('%s %s is born %s, naming %s: a %s is born %s with no cause, and reaches any other status by a move that names its row (Q1 (a), CI-013; v5.4.2-23)', TG_TABLE_NAME, NEW.id, NEW.status, coalesce(NEW.status_cause_id::text, 'none'),
                             CASE TG_TABLE_NAME WHEN 'payments' THEN 'payment' ELSE 'credit' END, CASE TG_TABLE_NAME WHEN 'payments' THEN 'pending' ELSE 'active' END),
            ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$;
COMMENT ON FUNCTION public.enforce_cash_birth() IS
    'v5.4.2-23 r2 (Q1 (a); Fable S3, Opus B2). BEFORE INSERT on payments and customer_credits: a payment is born pending, a credit active, with no status_cause_id and no status_recorded_at. A superuser''s history load keeps its own (N1: a payment then moves to posted after its posting row, which is written only while it is pending); r5: its status_recorded_at, if any, is a finite time already reached.';
CREATE TRIGGER a_enforce_cash_birth BEFORE INSERT ON public.payments
    FOR EACH ROW EXECUTE FUNCTION public.enforce_cash_birth();
ALTER TABLE public.payments ENABLE ALWAYS TRIGGER a_enforce_cash_birth;
CREATE TRIGGER a_enforce_cash_birth BEFORE INSERT ON public.customer_credits
    FOR EACH ROW EXECUTE FUNCTION public.enforce_cash_birth();
ALTER TABLE public.customer_credits ENABLE ALWAYS TRIGGER a_enforce_cash_birth;

-- M2 for one-off charges: identity fixed from insert (it was frozen once the
-- charge left pending). The rest is -20's body unchanged.
CREATE OR REPLACE FUNCTION public.enforce_adhoc_charge_immutable()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
    v_changed text[] := '{}';
    -- v5.4.2-20: the void is the write made as tally_void (void_invoice()'s
    -- owner, current_user only while it runs), not a caller-settable setting.
    v_void_op boolean := current_user = 'tally_void';
    v_void_disposition boolean;
BEGIN
    IF OLD.status IN ('void', 'waived') AND NEW.status IS DISTINCT FROM OLD.status THEN
        RAISE EXCEPTION USING
            MESSAGE = format('adhoc charge %s is %s — a terminal state (CI-013): create a new charge instead', OLD.charge_number, OLD.status),
            ERRCODE = 'restrict_violation';
    END IF;

    -- A billed charge is part of an issued bill; it leaves 'billed' only
    -- through void_invoice(), and only to the two states that function writes.
    IF OLD.status = 'billed' AND NEW.status IS DISTINCT FROM OLD.status
       AND NOT (v_void_op AND NEW.status IN ('pending', 'void_pending_rebill')) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('adhoc charge %s is billed on invoice %s (CI-012/CI-013): it is undone only by voiding that invoice (void_invoice()), not by changing the charge', OLD.charge_number, OLD.billed_on_invoice_id),
            ERRCODE = 'restrict_violation';
    END IF;

    -- v5.4.2-20 (C-B2): the void's disposition, exactly. Leaving billed as
    -- tally_void clears the three billing pointers and records the bill it
    -- leaves in voided_from_invoice_id. (The run that billed it, and the
    -- charge's identity, are outside tally_void's column grants.) Anything
    -- else the role writes falls to the rules below.
    v_void_disposition := v_void_op AND OLD.status = 'billed'
                          AND NEW.status IN ('pending', 'void_pending_rebill');
    IF v_void_disposition
       AND NOT (OLD.billed_on_invoice_id IS NOT NULL
                AND NEW.billed_on_invoice_id IS NULL
                AND NEW.billed_on_line_item_id IS NULL
                AND NEW.billed_at IS NULL
                AND NEW.voided_from_invoice_id IS NOT DISTINCT FROM OLD.billed_on_invoice_id) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('adhoc charge %s: a void clears billed_on_invoice_id, billed_on_line_item_id and billed_at and sets voided_from_invoice_id to the bill it leaves (CI-013, v5.4.2-20)', OLD.charge_number),
            ERRCODE = 'restrict_violation';
    END IF;
    -- voided_from_invoice_id is written by a void and by nothing else.
    IF NEW.voided_from_invoice_id IS DISTINCT FROM OLD.voided_from_invoice_id AND NOT v_void_disposition THEN
        RAISE EXCEPTION USING
            MESSAGE = format('adhoc charge %s: voided_from_invoice_id is written only by void_invoice() (CI-013, v5.4.2-20)', OLD.charge_number),
            ERRCODE = 'restrict_violation';
    END IF;

    -- While billed, the billing pointers are part of the issued bill; only
    -- void_invoice()'s disposition (checked above) may touch them.
    IF OLD.status = 'billed' AND NOT v_void_disposition THEN
        IF NEW.billed_on_invoice_id    IS DISTINCT FROM OLD.billed_on_invoice_id    THEN v_changed := v_changed || ARRAY['billed_on_invoice_id']; END IF;
        IF NEW.billed_on_line_item_id  IS DISTINCT FROM OLD.billed_on_line_item_id  THEN v_changed := v_changed || ARRAY['billed_on_line_item_id']; END IF;
        IF NEW.billed_at               IS DISTINCT FROM OLD.billed_at               THEN v_changed := v_changed || ARRAY['billed_at']; END IF;
        IF NEW.billed_by_billing_run_id IS DISTINCT FROM OLD.billed_by_billing_run_id THEN v_changed := v_changed || ARRAY['billed_by_billing_run_id']; END IF;
    END IF;

    -- v5.4.2-23 (M2; R-05): fixed from insert, not from billing; the class
    -- (D7-2) with it.
    BEGIN
        IF NEW.regulatory_class IS DISTINCT FROM OLD.regulatory_class THEN v_changed := v_changed || ARRAY['regulatory_class']; END IF;
        IF NEW.id             IS DISTINCT FROM OLD.id             THEN v_changed := v_changed || ARRAY['id']; END IF;
        IF NEW.tenant_id      IS DISTINCT FROM OLD.tenant_id      THEN v_changed := v_changed || ARRAY['tenant_id']; END IF;
        IF NEW.description    IS DISTINCT FROM OLD.description    THEN v_changed := v_changed || ARRAY['description']; END IF;
        IF NEW.charge_number  IS DISTINCT FROM OLD.charge_number  THEN v_changed := v_changed || ARRAY['charge_number']; END IF;
        IF NEW.customer_id    IS DISTINCT FROM OLD.customer_id    THEN v_changed := v_changed || ARRAY['customer_id']; END IF;
        IF NEW.location_id    IS DISTINCT FROM OLD.location_id    THEN v_changed := v_changed || ARRAY['location_id']; END IF;
        IF NEW.meter_id       IS DISTINCT FROM OLD.meter_id       THEN v_changed := v_changed || ARRAY['meter_id']; END IF;
        IF NEW.charge_type    IS DISTINCT FROM OLD.charge_type    THEN v_changed := v_changed || ARRAY['charge_type']; END IF;
        IF NEW.amount         IS DISTINCT FROM OLD.amount         THEN v_changed := v_changed || ARRAY['amount']; END IF;
        IF NEW.is_taxable     IS DISTINCT FROM OLD.is_taxable     THEN v_changed := v_changed || ARRAY['is_taxable']; END IF;
        IF NEW.service_type   IS DISTINCT FROM OLD.service_type   THEN v_changed := v_changed || ARRAY['service_type']; END IF;
        IF NEW.effective_date IS DISTINCT FROM OLD.effective_date THEN v_changed := v_changed || ARRAY['effective_date']; END IF;
        IF NEW.source         IS DISTINCT FROM OLD.source         THEN v_changed := v_changed || ARRAY['source']; END IF;
        IF NEW.created_by     IS DISTINCT FROM OLD.created_by     THEN v_changed := v_changed || ARRAY['created_by']; END IF;
        IF NEW.created_at     IS DISTINCT FROM OLD.created_at     THEN v_changed := v_changed || ARRAY['created_at']; END IF;
    END;

    IF cardinality(v_changed) > 0 THEN
        RAISE EXCEPTION USING
            MESSAGE = format('adhoc charge %s: its identity is fixed from insert (R-05, CI-013; v5.4.2-23): attempted change to %s — void or waive it and create a new charge', OLD.charge_number, array_to_string(v_changed, ', ')),
            ERRCODE = 'restrict_violation';
    END IF;
    RETURN NEW;
END;
$fn$;
COMMENT ON FUNCTION public.enforce_adhoc_charge_immutable() IS
    'CI-013 guard for adhoc_charges (v5.4.2-01, -20), v5.4.2-23 (R-05; M2): the identity (number, customer, location, meter, type, description, amount, taxability, service, effective date, source, creator, created_at) and the regulatory class are fixed from insert. void and waived are terminal; billed is left only through void_invoice() (tally_void), to pending or void_pending_rebill, clearing the billing pointers and recording the bill left in voided_from_invoice_id; the billing pointers are frozen while billed.';
ALTER TABLE public.adhoc_charges
    ADD CONSTRAINT adhoc_charges_void_reason_check CHECK (status <> 'void' OR coalesce(void_reason ~ '[[:alnum:]]', false)),
    ADD CONSTRAINT adhoc_charges_waive_reason_check CHECK (status <> 'waived' OR coalesce(waive_reason ~ '[[:alnum:]]', false));

-- A1b at issue: a line's class matches its source. Gated as -21's line
-- arithmetic: the move into an issued status, not a void; the bill's
-- snapshot date under current knowledge.
CREATE OR REPLACE FUNCTION public.invoice_line_class_gap(p_line public.invoice_line_items, p_valid_at date, p_recorded_at timestamp with time zone)
    RETURNS text
    LANGUAGE plpgsql STABLE
    SET search_path TO 'public', 'pg_temp'
    AS $fn$
DECLARE
    v_class text;
BEGIN
    IF p_line.adhoc_charge_id IS NOT NULL THEN
        SELECT c.regulatory_class INTO v_class FROM public.adhoc_charges c WHERE c.id = p_line.adhoc_charge_id;
        IF v_class IS NULL THEN
            RETURN format('its one-off charge %s is not visible', p_line.adhoc_charge_id);
        END IF;
        IF v_class <> p_line.regulatory_class THEN
            RETURN format('it is %s, its one-off charge %s is %s', p_line.regulatory_class, p_line.adhoc_charge_id, v_class);
        END IF;
    END IF;
    IF p_line.rate_item_id IS NOT NULL THEN
        SELECT v.regulatory_class INTO v_class FROM public.rate_item_as_of(p_line.rate_item_id, p_valid_at, p_recorded_at) v;
        IF v_class IS NULL THEN
            RETURN format('rate item %s has no version visible at (%s, %s)', p_line.rate_item_id, p_valid_at, p_recorded_at);
        END IF;
        IF v_class <> p_line.regulatory_class THEN
            RETURN format('it is %s, its rate item %s is %s at (%s, %s)', p_line.regulatory_class, p_line.rate_item_id, v_class, p_valid_at, p_recorded_at);
        END IF;
    END IF;
    RETURN NULL;
END;
$fn$;
COMMENT ON FUNCTION public.invoice_line_class_gap(public.invoice_line_items, date, timestamp with time zone) IS
    'v5.4.2-23 (D7-2, CI-050; A1b). Why a bill line''s regulatory_class does not match its source, or NULL: a line from a one-off charge carries the charge''s class; a line from a rate item the class of the rate item''s version at (p_valid_at, p_recorded_at). A line with neither (a tax, a line the core composes) is the core''s to class. Invoker rights: RLS decides what is visible.';
REVOKE ALL ON FUNCTION public.invoice_line_class_gap(public.invoice_line_items, date, timestamp with time zone) FROM PUBLIC, tally_core;
GRANT EXECUTE ON FUNCTION public.invoice_line_class_gap(public.invoice_line_items, date, timestamp with time zone) TO tally_app;

CREATE OR REPLACE FUNCTION public.enforce_invoice_line_class() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public', 'pg_temp'
    AS $fn$
DECLARE
    v_line public.invoice_line_items%ROWTYPE;
    v_gap  text;
    v_snap public.invoice_calculation_snapshots%ROWTYPE;
BEGIN
    IF NOT public.is_invoice_issued(NEW.status) THEN
        RETURN NULL;
    END IF;
    IF TG_OP = 'UPDATE' AND public.is_invoice_issued(OLD.status) THEN
        RETURN NULL;
    END IF;
    IF TG_OP = 'UPDATE' AND NEW.status = 'void' THEN
        RETURN NULL;
    END IF;
    SELECT * INTO v_snap FROM public.invoice_calculation_snapshots s WHERE s.invoice_id = NEW.id;
    IF NOT FOUND THEN
        RETURN NULL;
    END IF;
    PERFORM 1 FROM public.invoice_line_items l WHERE l.invoice_id = NEW.id FOR SHARE;
    FOR v_line IN SELECT l.* FROM public.invoice_line_items l WHERE l.invoice_id = NEW.id ORDER BY l.line_order, l.id LOOP
        v_gap := public.invoice_line_class_gap(v_line, v_snap.valid_at, now());
        IF v_gap IS NOT NULL THEN
            RAISE EXCEPTION USING
                MESSAGE = format('invoice %s cannot be issued: line %s (%s, %s) is classed against its source wrongly — %s (D7-2, CI-050; v5.4.2-23)', NEW.invoice_number, v_line.line_order, v_line.charge_type, v_line.description, v_gap),
                ERRCODE = 'check_violation';
        END IF;
    END LOOP;
    RETURN NULL;
END;
$fn$;
COMMENT ON FUNCTION public.enforce_invoice_line_class() IS
    'v5.4.2-23 (A1b). Deferred AFTER INSERT OR UPDATE on invoices, gated as enforce_invoice_line_arithmetic (the move into an issued status, not a void; a superuser''s load of a bill born issued too): every line''s regulatory_class matches its source (invoice_line_class_gap at the snapshot''s valid_at under now()). Without a snapshot it defers to enforce_invoice_has_snapshot. Locks the lines FOR SHARE.';
REVOKE ALL ON FUNCTION public.enforce_invoice_line_class() FROM PUBLIC, tally_app, tally_core;
CREATE CONSTRAINT TRIGGER enforce_invoice_line_class AFTER INSERT OR UPDATE ON public.invoices
    DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.enforce_invoice_line_class();
ALTER TABLE public.invoices ENABLE ALWAYS TRIGGER enforce_invoice_line_class;


-- ----------------------------------------------------------------------------
-- 7. The caps (A3; R-06): a source's money, a line, an undo
-- ----------------------------------------------------------------------------
-- An application is money dated by a day: the close freezes it (-22 P2).
CREATE TRIGGER a_enforce_accounting_freeze BEFORE INSERT ON public.invoice_applications
    FOR EACH ROW EXECUTE FUNCTION public.enforce_accounting_freeze('applied_on');
ALTER TABLE public.invoice_applications ENABLE ALWAYS TRIGGER a_enforce_accounting_freeze;

-- The rows drawing on a payment or a credit, with their money date and
-- recorded instant: applications (net, undos included), overpayment credits
-- not voided, refunds while pending or posted, and (a credit) its donation
-- and its escheat. r2 (Fable B1, S1; Codex B1): every way money leaves a
-- source is here, keyed on the row that names the source, not on a label.
CREATE OR REPLACE FUNCTION public.cash_source_draws(p_kind text, p_id uuid)
    RETURNS TABLE (id uuid, on_date date, amount numeric, created_at timestamp with time zone)
    LANGUAGE sql STABLE
    SET search_path = public, pg_temp
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
    -- r3 (Codex B5): a donation and every row under it (its undo gives the
    -- money back to the credit).
    SELECT l.id, l.transaction_date, l.amount, l.created_at FROM public.account_ledger d
      CROSS JOIN LATERAL unnest(public.ledger_tree_ids(d.id) || d.id) AS t(id)
      JOIN public.account_ledger l ON l.id = t.id
     WHERE p_kind = 'credit' AND d.transaction_type = 'donation' AND d.reference_type = 'customer_credit' AND d.reference_id = p_id
    UNION ALL
    SELECT e.id, (e.event_date AT TIME ZONE 'UTC')::date, e.amount_related, e.created_at FROM public.escheatment_events e
     WHERE p_kind = 'credit' AND e.event_type = 'escheated_to_state' AND e.customer_credit_id = p_id
$$;
COMMENT ON FUNCTION public.cash_source_draws(text, uuid) IS
    'v5.4.2-23 (A3), r3. Every row drawing on a payment (p_kind payment) or a customer credit (p_kind credit), live: its applications (an undo negative); a payment''s credits (a credit names a payment only as an overpayment credit) unless voided; its refunds while pending or posted; a credit''s refund_reissue credits not voided (r4), its donation ledger rows and every row under them (r3: an undone donation gives the money back), and its escheated_to_state events (dated by their UTC day). Each with its money date and recorded instant. The cap reads this set with what was taken back under the source''s arrival entry (check_cash_source).';
REVOKE ALL ON FUNCTION public.cash_source_draws(text, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.cash_source_draws(text, uuid) TO tally_app, tally_core;

-- r2 (Opus B2): a source's money is on the ledger. A payment's is its posting
-- entry; a credit's, unless it came from an overpayment (whose money is the
-- payment's), its credit_issued entry. r3 (Kyle, K-10): one per source (the
-- unique indexes), found by its reference, whatever the source's status. What
-- stands of it is the entry less what was taken back under it (a bounce, a
-- reversal, a withdrawal): check_cash_source caps every draw by that, at every
-- date, so a partial reversal leaves the rest to draw on and a full one
-- leaves nothing (r2's yes/no, cash_arrival_stands, refused any draw once
-- anything was taken back).
CREATE OR REPLACE FUNCTION public.cash_arrival_entry(p_kind text, p_id uuid) RETURNS uuid
    LANGUAGE sql STABLE
    SET search_path = public, pg_temp
    AS $$
    SELECT CASE p_kind
        WHEN 'payment' THEN (SELECT l.id FROM public.account_ledger l
                              WHERE l.reference_type = 'payment' AND l.transaction_type IN ('payment', 'deposit', 'refund') AND l.reference_id = p_id)
        WHEN 'credit' THEN (SELECT l.id FROM public.account_ledger l
                             WHERE l.reference_type = 'customer_credit' AND l.transaction_type = 'credit_issued' AND l.reference_id = p_id)
    END
$$;
COMMENT ON FUNCTION public.cash_arrival_entry(text, uuid) IS
    'v5.4.2-23 r3 (Opus B2; Kyle, K-10). The ledger entry by which a payment (its posting row: payment, deposit or refund, under reference_type payment) or a credit (its credit_issued row) reached the ledger; one per source by the unique indexes. NULL when it has none: a pending payment, an overpayment credit (its money is its payment''s), a credit not yet issued on the ledger. Live.';
REVOKE ALL ON FUNCTION public.cash_arrival_entry(text, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.cash_arrival_entry(text, uuid) TO tally_app, tally_core;

-- -22's recorded-order rule for a source of money: a row read with the
-- source's draws is not recorded before a row already drawing on it, a draw
-- that has since left it, or (given p_entry) a row under its arrival entry.
-- 40001 for a row stamped at its transaction's start (the writer retries and
-- lands after), 23514 for a time chosen for it (a history load keeps its
-- time on any retry). The caller holds the source's lock: every row it
-- checks against takes that lock too. r6 (Opus B2, Fable B1): shared by a
-- draw (check_cash_source) and by a row under a payment's posting entry,
-- checked against the payment and its overpayment credits
-- (enforce_ledger_reversal), with one retry contract.
CREATE OR REPLACE FUNCTION public.check_cash_order(p_kind text, p_id uuid, p_row_created_at timestamp with time zone, p_entry uuid, p_what text)
    RETURNS void
    LANGUAGE plpgsql STABLE
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_later_id uuid;
    v_later_at timestamptz;
BEGIN
    SELECT d.id, d.created_at INTO v_later_id, v_later_at
      FROM public.cash_source_draws(p_kind, p_id) d
     WHERE d.created_at > p_row_created_at
     ORDER BY d.created_at DESC LIMIT 1;
    IF FOUND AND p_row_created_at <> pg_catalog.now() THEN
        RAISE EXCEPTION USING
            MESSAGE = format('%s %s: %s is recorded at %s, a time chosen for it, before %s (recorded at %s) already counted — a history row is recorded after every row already drawing on its source (R-06, v5.4.2-23)', p_kind, p_id, p_what, p_row_created_at, v_later_id, v_later_at),
            ERRCODE = 'check_violation';
    END IF;
    IF FOUND THEN
        RAISE EXCEPTION USING
            MESSAGE = format('%s %s: %s is recorded at %s, before %s (recorded at %s) already counted — a transaction that began earlier is writing later; retry it (R-06, v5.4.2-23)', p_kind, p_id, p_what, p_row_created_at, v_later_id, v_later_at),
            ERRCODE = 'serialization_failure';
    END IF;
    -- r3: nor before a draw that has since left (a refund cancelled or
    -- returned, an overpayment or reissued credit voided), whose leaving freed
    -- the money this row may be using: at an instant between the two, both
    -- would count. The leaving move takes this source's lock, so it is seen
    -- here.
    SELECT x.id, x.at INTO v_later_id, v_later_at
      FROM (SELECT r.id, r.status_recorded_at AS at FROM public.payments r
             WHERE r.status NOT IN ('pending', 'posted')
               AND ((p_kind = 'payment' AND r.refunds_payment_id = p_id) OR (p_kind = 'credit' AND r.refunds_customer_credit_id = p_id))
            UNION ALL
            SELECT c.id, c.status_recorded_at FROM public.customer_credits c
             WHERE p_kind = 'payment' AND c.source_payment_id = p_id AND c.status = 'voided'
            UNION ALL
            SELECT c.id, c.status_recorded_at FROM public.customer_credits c JOIN public.payments r ON r.id = c.reissues_refund_id
             WHERE p_kind = 'credit' AND r.refunds_customer_credit_id = p_id AND c.status = 'voided') x
     WHERE x.at > p_row_created_at
     ORDER BY x.at DESC LIMIT 1;
    IF FOUND AND p_row_created_at <> pg_catalog.now() THEN
        RAISE EXCEPTION USING
            MESSAGE = format('%s %s: %s is recorded at %s, a time chosen for it, before %s left it (at %s) — a history row is recorded after every move on its source (R-06, v5.4.2-23)', p_kind, p_id, p_what, p_row_created_at, v_later_id, v_later_at),
            ERRCODE = 'check_violation';
    END IF;
    IF FOUND THEN
        RAISE EXCEPTION USING
            MESSAGE = format('%s %s: %s is recorded at %s, before %s left it (at %s) — a transaction that began earlier is writing later; retry it (R-06, v5.4.2-23)', p_kind, p_id, p_what, p_row_created_at, v_later_id, v_later_at),
            ERRCODE = 'serialization_failure';
    END IF;
    -- r4 (Opus S1): nor before a row under its arrival entry (money taken
    -- back or given back): the cap reads them with the draws. Such a row
    -- takes this source's lock (enforce_ledger_reversal), so it is seen here.
    IF p_entry IS NOT NULL THEN
        SELECT l.id, l.created_at INTO v_later_id, v_later_at
          FROM public.account_ledger l
         WHERE l.id = ANY (public.ledger_tree_ids(p_entry)) AND l.created_at > p_row_created_at
         ORDER BY l.created_at DESC LIMIT 1;
        IF FOUND AND p_row_created_at <> pg_catalog.now() THEN
            RAISE EXCEPTION USING
                MESSAGE = format('%s %s: %s is recorded at %s, a time chosen for it, before %s was recorded under its arrival entry (money taken back or given back, at %s) (R-06, v5.4.2-23)', p_kind, p_id, p_what, p_row_created_at, v_later_id, v_later_at),
                ERRCODE = 'check_violation';
        END IF;
        IF FOUND THEN
            RAISE EXCEPTION USING
                MESSAGE = format('%s %s: %s is recorded at %s, before %s was recorded under its arrival entry (money taken back or given back, at %s) — a transaction that began earlier is writing later; retry it (R-06, v5.4.2-23)', p_kind, p_id, p_what, p_row_created_at, v_later_id, v_later_at),
                ERRCODE = 'serialization_failure';
        END IF;
    END IF;
END;
$$;
COMMENT ON FUNCTION public.check_cash_order(text, uuid, timestamp with time zone, uuid, text) IS
    'v5.4.2-23 r6 (Opus B2, Fable B1; -22''s recorded order). Refuses a row recorded before a row already drawing on a payment or credit (cash_source_draws), before a draw that has since left it (a refund no longer pending or posted, an overpayment or reissued credit voided: by its status_recorded_at), or, given p_entry, before a row under the source''s arrival entry: 40001 for a row stamped at its transaction''s start, 23514 for a chosen time. The caller holds the source''s lock. Called by check_cash_source for every draw and by enforce_ledger_reversal for a row under a payment''s posting entry (the payment and each credit of its overpayment family).';
REVOKE ALL ON FUNCTION public.check_cash_order(text, uuid, timestamp with time zone, uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.check_cash_order(text, uuid, timestamp with time zone, uuid, text) TO tally_app;

-- r6 (Codex B4): the last instant recorded on a source's lineage: the source
-- itself, its arrival entry and every row under it, every row drawing on it
-- and every move by which a draw left it. A payment with a live overpayment
-- credit, and a credit holding a payment's money (overpayment_root), share a
-- lineage: the payment and every credit of the family. A status move with a
-- chosen time (a history load) is not recorded before it.
CREATE OR REPLACE FUNCTION public.cash_lineage_recorded(p_kind text, p_id uuid) RETURNS timestamp with time zone
    LANGUAGE plpgsql STABLE
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_pay  uuid;
    v_root uuid;
    v_at   timestamptz;
BEGIN
    IF p_kind = 'payment' THEN
        v_pay := p_id;
        SELECT c.id INTO v_root FROM public.customer_credits c WHERE c.source_payment_id = p_id AND c.status <> 'voided';
    ELSE
        v_root := public.overpayment_root(p_id);
        SELECT c.source_payment_id INTO v_pay FROM public.customer_credits c WHERE c.id = v_root;
    END IF;
    WITH s(kind, id) AS (
        SELECT p_kind, p_id
        UNION SELECT 'payment', v_pay WHERE v_pay IS NOT NULL
        UNION SELECT 'credit', f.id FROM public.overpayment_family(v_root) f
    )
    SELECT max(x.at) INTO v_at
      FROM s CROSS JOIN LATERAL (
            SELECT p.created_at AS at FROM public.payments p WHERE s.kind = 'payment' AND p.id = s.id
            UNION ALL
            SELECT c.created_at FROM public.customer_credits c WHERE s.kind = 'credit' AND c.id = s.id
            UNION ALL
            SELECT l.created_at FROM public.account_ledger l
             WHERE l.id = ANY (public.ledger_tree_ids(public.cash_arrival_entry(s.kind, s.id)) || public.cash_arrival_entry(s.kind, s.id))
            UNION ALL
            SELECT d.created_at FROM public.cash_source_draws(s.kind, s.id) d
            UNION ALL
            SELECT r.status_recorded_at FROM public.payments r
             WHERE r.status NOT IN ('pending', 'posted')
               AND ((s.kind = 'payment' AND r.refunds_payment_id = s.id) OR (s.kind = 'credit' AND r.refunds_customer_credit_id = s.id))
            UNION ALL
            SELECT c.status_recorded_at FROM public.customer_credits c
             WHERE s.kind = 'payment' AND c.source_payment_id = s.id AND c.status = 'voided'
            UNION ALL
            SELECT c.status_recorded_at FROM public.customer_credits c JOIN public.payments r ON r.id = c.reissues_refund_id
             WHERE s.kind = 'credit' AND r.refunds_customer_credit_id = s.id AND c.status = 'voided') x;
    RETURN v_at;
END;
$$;
COMMENT ON FUNCTION public.cash_lineage_recorded(text, uuid) IS
    'v5.4.2-23 r6 (Codex B4). The last recorded instant on a payment''s or credit''s lineage: the source, its arrival entry and the rows under it, the rows drawing on it (cash_source_draws) and the moves by which draws left it; for a payment with a live overpayment credit or a credit holding a payment''s money (overpayment_root), over the payment and every credit of the family. A status move at a chosen time is not recorded before it (enforce_payment_immutable, enforce_customer_credit_immutable).';
REVOKE ALL ON FUNCTION public.cash_lineage_recorded(text, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.cash_lineage_recorded(text, uuid) TO tally_app;

-- Under the source's lock (after the head): the source is read and judged
-- (r2: after the lock, so a move that ended it while this row waited is
-- seen; Opus B1, Fable B2, Codex B2); the rows drawing on it are not recorded
-- before the source reached the ledger or one already counted (-22's
-- recorded-order rule: 40001 for a row stamped at its transaction's start,
-- 23514 for a chosen time); and at no date do they, with what was taken back
-- under its arrival entry, exceed it (r3, Kyle's K-10 caps). Called by every
-- row that draws on a source, after the row is in. p_purpose: application,
-- undo, overpayment_credit, refund, donation, escheat.
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
        WHEN 'application' THEN v_status IN ('posted', 'active') AND NOT v_deposit AND v_amount > 0
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
    IF p_purpose <> 'undo' AND p_on < v_date THEN
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
    IF p_purpose <> 'undo' AND v_entry IS NULL AND v_origin IS DISTINCT FROM 'refund_reissue' THEN
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
    IF p_purpose <> 'undo' THEN
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
        IF v_pool_pay IS NOT NULL THEN
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
END;
$$;
COMMENT ON FUNCTION public.check_cash_source(text, uuid, timestamp with time zone, text, date) IS
    'v5.4.2-23 (A3; R-06), r3. READ COMMITTED only. Takes the source''s advisory lock (after the tenant''s close head, which the row''s freeze took), then reads the source: unknown or invisible raises; by purpose, an application from a posted bill payment or an active credit, an overpayment credit from a posted bill payment, a refund from a posted payment or an active credit, a donation or escheat from an active credit, each dated on or after the source and only once its money is on the ledger (cash_arrival_entry; an overpayment credit''s is its payment''s); an undo only while the source has not ended. Then refuses a row recorded before the source reached the ledger (r3: a payment''s move to posted, a credit''s credit_issued entry) or before a row already drawing on it (40001; 23514 for a chosen time). Then (not for an undo) refuses any date at which the draws (cash_source_draws) and what was taken back under the arrival entry exceed the payment or credit (r3, Kyle''s K-10 refund cap, applied to every draw); r6: a credit holding a payment''s money (an overpayment credit or a reissue descended from one) counts its own share of what was taken back (overpayment_shares), the payment the rest, and a payment and its credits together never give more than the payment less what was taken back. The recorded-order legs are check_cash_order''s.';
REVOKE ALL ON FUNCTION public.check_cash_source(text, uuid, timestamp with time zone, text, date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.check_cash_source(text, uuid, timestamp with time zone, text, date) TO tally_app;

CREATE OR REPLACE FUNCTION public.enforce_invoice_application() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_line       public.invoice_line_items%ROWTYPE;
    v_inv        public.invoices%ROWTYPE;
    v_pay        public.payments%ROWTYPE;
    v_undone     public.invoice_applications%ROWTYPE;
    v_kind       text := CASE WHEN NEW.payment_id IS NOT NULL THEN 'payment' ELSE 'credit' END;
    v_src_id     uuid := coalesce(NEW.payment_id, NEW.customer_credit_id);
    v_restricted boolean := false;
    v_in_target  boolean := false;
    v_on         date;
    v_net        numeric;
    v_later_id   uuid;
    v_later_at   timestamptz;
BEGIN
    -- r6 (Opus S1): recorded at a time already reached, for any role (a
    -- superuser's history load keeps its own; see enforce_cash_birth).
    IF NOT pg_catalog.isfinite(NEW.created_at) OR NEW.created_at > pg_catalog.clock_timestamp() THEN
        RAISE EXCEPTION USING
            MESSAGE = format('application %s is recorded at %s, not a time already reached — every money row is recorded at a finite time already reached (v5.4.2-23)', NEW.id, NEW.created_at),
            ERRCODE = 'check_violation';
    END IF;
    SELECT * INTO v_line FROM public.invoice_line_items l WHERE l.id = NEW.invoice_line_item_id;
    SELECT * INTO v_inv FROM public.invoices i WHERE i.id = NEW.invoice_id;
    -- The source's restriction is fixed from insert, so it is read here; its
    -- status and money are read under its lock (check_cash_source, r2).
    IF v_kind = 'payment' THEN
        SELECT * INTO v_pay FROM public.payments p WHERE p.id = v_src_id;
    END IF;

    IF NEW.basis = 'undo' THEN
        SELECT * INTO v_undone FROM public.invoice_applications a WHERE a.id = NEW.undoes_application_id;
        IF v_undone.basis = 'undo'
           OR v_undone.payment_id IS DISTINCT FROM NEW.payment_id
           OR v_undone.customer_credit_id IS DISTINCT FROM NEW.customer_credit_id THEN
            RAISE EXCEPTION USING
                MESSAGE = format('application %s undoes %s: an undo names an application (not an undo) of the same source and line (A2, v5.4.2-23)', NEW.id, NEW.undoes_application_id),
                ERRCODE = 'check_violation';
        END IF;
        IF NEW.applied_on < v_undone.applied_on THEN
            RAISE EXCEPTION USING
                MESSAGE = format('application %s is dated %s, before the application it undoes (%s, %s): an undo is dated on or after it (A2, v5.4.2-23)', NEW.id, NEW.applied_on, v_undone.id, v_undone.applied_on),
                ERRCODE = 'check_violation';
        END IF;
    ELSE
        -- A new application: to a positive line of an issued, unvoided bill,
        -- on or after it (the source is judged under its lock, below).
        IF NOT public.is_invoice_issued(v_inv.status) OR v_inv.status = 'void' THEN
            RAISE EXCEPTION USING
                MESSAGE = format('application %s: invoice %s is %s — money is applied to an issued, unvoided bill (A3, v5.4.2-23)', NEW.id, v_inv.invoice_number, v_inv.status),
                ERRCODE = 'check_violation';
        END IF;
        IF v_line.amount <= 0 THEN
            RAISE EXCEPTION USING
                MESSAGE = format('application %s: line %s of invoice %s is %s — only a positive line takes money; a credit or adjustment line is the bill''s own netting (A3, v5.4.2-23)', NEW.id, v_line.line_order, v_inv.invoice_number, v_line.amount),
                ERRCODE = 'check_violation';
        END IF;
        IF NEW.applied_on < v_inv.invoice_date THEN
            RAISE EXCEPTION USING
                MESSAGE = format('application %s is dated %s, before its bill (%s): money is applied on or after it (A3, v5.4.2-23)', NEW.id, NEW.applied_on, v_inv.invoice_date),
                ERRCODE = 'check_violation';
        END IF;
        -- A6 (D7-1 b): a restricted payment goes to its target, or to a
        -- regulated line ahead of an unregulated target (the floor), or by an
        -- operator's recorded choice; nothing else says restriction or floor.
        IF v_kind = 'payment' AND v_pay.restricted_to_invoice_id IS NOT NULL THEN
            v_restricted := true;
            v_in_target := v_line.invoice_id = v_pay.restricted_to_invoice_id
                           AND (v_pay.restricted_to_line_item_id IS NULL OR v_line.id = v_pay.restricted_to_line_item_id);
        END IF;
        IF (NEW.basis = 'restriction' AND NOT v_in_target)
           OR (NEW.basis = 'oldest_first' AND v_restricted)
           OR (NEW.basis = 'floor_over_restriction'
               AND NOT (v_restricted AND NOT v_in_target AND v_line.regulatory_class = 'regulated'
                        AND EXISTS (SELECT 1 FROM public.invoice_line_items t
                                     WHERE t.invoice_id = v_pay.restricted_to_invoice_id
                                       AND (v_pay.restricted_to_line_item_id IS NULL OR t.id = v_pay.restricted_to_line_item_id)
                                       AND t.regulatory_class = 'unregulated' AND t.amount > 0))) THEN
            RAISE EXCEPTION USING
                MESSAGE = format('application %s says %s: restriction is a restricted payment''s own target; floor_over_restriction a regulated line taken ahead of an unregulated target; oldest_first an unrestricted source (D7-1, CI-050; v5.4.2-23)', NEW.id, NEW.basis),
                ERRCODE = 'check_violation';
        END IF;
        -- A5: a rule-chosen application cites its tenant's tariff row in
        -- force on its date (rule_row_cite: the row's lock shared, after the
        -- head and before the source; RLS keeps another tenant's row unseen).
        IF NEW.allocation_tariff_id IS NOT NULL THEN
            PERFORM public.rule_row_cite('public.payment_allocation_tariffs'::regclass, NEW.allocation_tariff_id, NEW.applied_on);
            IF NOT EXISTS (SELECT 1 FROM public.payment_allocation_tariffs t WHERE t.id = NEW.allocation_tariff_id AND t.tenant_id = NEW.tenant_id) THEN
                RAISE EXCEPTION USING
                    MESSAGE = format('application %s names allocation tariff %s of another tenant (K-05, CI-049; v5.4.2-23)', NEW.id, NEW.allocation_tariff_id),
                    ERRCODE = 'foreign_key_violation';
            END IF;
        END IF;
    END IF;

    -- The source, under its lock (after the head the freeze took): read and
    -- judged there, so a move that ended it while this row waited is seen.
    PERFORM public.check_cash_source(v_kind, v_src_id, NEW.created_at,
                                     CASE WHEN NEW.basis = 'undo' THEN 'undo' ELSE 'application' END, NEW.applied_on);
    -- Then the line, under its lock: not recorded before an application
    -- already on it; never more than the line at any date; an undo never more
    -- than what it undoes.
    PERFORM pg_catalog.pg_advisory_xact_lock(public.cash_source_lock_key('line', NEW.invoice_line_item_id));
    -- r2 (Opus S3): nor before its bill was issued (first_issued_at, the
    -- database's stamp): a line has no position before then.
    IF NEW.created_at < v_inv.first_issued_at THEN
        IF NEW.created_at <> pg_catalog.now() THEN
            RAISE EXCEPTION USING
                MESSAGE = format('application %s is recorded at %s, a time chosen for it, before invoice %s was issued (%s) (A3, v5.4.2-23)', NEW.id, NEW.created_at, v_inv.invoice_number, v_inv.first_issued_at),
                ERRCODE = 'check_violation';
        END IF;
        RAISE EXCEPTION USING
            MESSAGE = format('application %s is recorded at %s, before invoice %s was issued (%s) — a transaction that began earlier is writing later; retry it (A3, v5.4.2-23)', NEW.id, NEW.created_at, v_inv.invoice_number, v_inv.first_issued_at),
            ERRCODE = 'serialization_failure';
    END IF;
    SELECT a.id, a.created_at INTO v_later_id, v_later_at
      FROM public.invoice_applications a
     WHERE a.invoice_line_item_id = NEW.invoice_line_item_id AND a.created_at > NEW.created_at
     ORDER BY a.created_at DESC LIMIT 1;
    IF FOUND AND NEW.created_at <> pg_catalog.now() THEN
        RAISE EXCEPTION USING
            MESSAGE = format('line %s: application %s is recorded at %s, a time chosen for it, before %s (recorded at %s) already on the line (A3, v5.4.2-23)', NEW.invoice_line_item_id, NEW.id, NEW.created_at, v_later_id, v_later_at),
            ERRCODE = 'check_violation';
    END IF;
    IF FOUND THEN
        RAISE EXCEPTION USING
            MESSAGE = format('line %s: application %s is recorded at %s, before %s (recorded at %s) already on the line — a transaction that began earlier is writing later; retry it (A3, v5.4.2-23)', NEW.invoice_line_item_id, NEW.id, NEW.created_at, v_later_id, v_later_at),
            ERRCODE = 'serialization_failure';
    END IF;
    SELECT x.on_date, x.net INTO v_on, v_net
      FROM (SELECT a.applied_on AS on_date, sum(a.amount) OVER (ORDER BY a.applied_on) AS net
              FROM public.invoice_applications a WHERE a.invoice_line_item_id = NEW.invoice_line_item_id) x
     WHERE x.net > greatest(v_line.amount, 0)
     ORDER BY x.on_date LIMIT 1;
    IF FOUND THEN
        RAISE EXCEPTION USING
            MESSAGE = format('line %s of invoice %s: on %s its applications would come to %s, more than the line''s %s (R-06 cap, v5.4.2-23)', v_line.line_order, v_inv.invoice_number, v_on, v_net, v_line.amount),
            ERRCODE = 'check_violation';
    END IF;
    IF NEW.basis = 'undo' THEN
        SELECT v_undone.amount + coalesce(sum(a.amount), 0) INTO v_net
          FROM public.invoice_applications a WHERE a.undoes_application_id = v_undone.id;
        IF v_net < 0 THEN
            RAISE EXCEPTION USING
                MESSAGE = format('application %s: its undos would come to %s, more than its %s (A2 cap, v5.4.2-23)', v_undone.id, v_undone.amount - v_net, v_undone.amount),
                ERRCODE = 'check_violation';
        END IF;
    END IF;
    RETURN NULL;
END;
$$;
COMMENT ON FUNCTION public.enforce_invoice_application() IS
    'v5.4.2-23 (A1-A6; R-06, K-05, D7-1, CI-049, CI-050). AFTER INSERT on invoice_applications. A new application goes to a positive line of an issued, unvoided bill, from a posted non-deposit payment or an active credit, dated on or after both; a restricted payment''s row says restriction for its target, floor_over_restriction for a regulated line ahead of an unregulated target, or operator_override; an unrestricted source never says either; a rule-chosen row names its tenant''s tariff in force. An undo names an application (not an undo) of the same source and line, dated on or after it. Then, at READ COMMITTED: the source''s lock and cap (check_cash_source), the line''s lock (after the source), not recorded before an application already on the line (40001; 23514 for a chosen time), the line never over-applied at any date, an application never over-undone.';
CREATE TRIGGER enforce_invoice_application AFTER INSERT ON public.invoice_applications
    FOR EACH ROW EXECUTE FUNCTION public.enforce_invoice_application();
ALTER TABLE public.invoice_applications ENABLE ALWAYS TRIGGER enforce_invoice_application;

-- The other draws on a source: a credit naming a payment (an overpayment
-- credit) draws on it, a refund on the payment or credit it returns, an
-- escheat remittance on its credit (a donation, a ledger row, is drawn in
-- enforce_ledger_reversal). r2: the source is judged under its lock, in
-- check_cash_source; the trigger fires on the row naming the source (Fable
-- B1), not on a label.
CREATE OR REPLACE FUNCTION public.enforce_cash_draw() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_refund public.payments%ROWTYPE;
    v_left   numeric;
BEGIN
    -- (Nested: NEW of another table has no reissues_refund_id.)
    IF TG_TABLE_NAME = 'customer_credits' THEN
      IF NEW.reissues_refund_id IS NOT NULL THEN
        -- r4 (Ryan, 2026-10-21): a reissue carries a credit's refund that came
        -- back, exactly, and draws on that credit (active or escheated).
        SELECT * INTO v_refund FROM public.payments r WHERE r.id = NEW.reissues_refund_id;
        IF v_refund.refunds_customer_credit_id IS NULL OR v_refund.status NOT IN ('nsf', 'reversed') THEN
            RAISE EXCEPTION USING
                MESSAGE = format('credit %s reissues %s: a refund_reissue credit carries a refund of a credit that came back (nsf or reversed); %s is %s', NEW.id, v_refund.payment_number, v_refund.payment_number,
                                 CASE WHEN v_refund.refunds_customer_credit_id IS NULL THEN 'not a credit''s refund' ELSE v_refund.status END),
                ERRCODE = 'check_violation';
        END IF;
        -- r5 (Opus S1): dated on or after the row by which the refund came
        -- back (its status_cause_id): its money is not there before.
        IF NEW.issued_date < (SELECT l.transaction_date FROM public.account_ledger l WHERE l.id = v_refund.status_cause_id) THEN
            RAISE EXCEPTION USING
                MESSAGE = format('credit %s reissues %s, dated %s: a reissue is dated on or after the row by which its refund came back (%s) (Ryan, 2026-10-21; v5.4.2-23)', NEW.id, v_refund.payment_number, NEW.issued_date,
                                 (SELECT l.transaction_date FROM public.account_ledger l WHERE l.id = v_refund.status_cause_id)),
                ERRCODE = 'check_violation';
        END IF;
        -- r5 (Codex B3; Ryan's option 1, K-10): it carries what came back as
        -- far as it is left on the credit: the credit's positive remainder
        -- before it, at most the refund. Where the credit's payment was also
        -- taken back, the returned refund offsets money that never arrived,
        -- and the customer owes the rest. Read under the locks the cap takes
        -- (the payment whose money the credit holds, if any, then the
        -- credit); the position counts this credit as carried. r6 (Codex B1):
        -- a reissue holding a payment's money takes its share of what was
        -- taken back under the payment, so what was left before it is the
        -- credit's remainder and what the reissue itself now holds of its
        -- amount (its issued; its amount for any other reissue).
        PERFORM pg_catalog.pg_advisory_xact_lock(public.cash_source_lock_key('payment', c.source_payment_id))
           FROM public.customer_credits c WHERE c.id = public.overpayment_root(v_refund.refunds_customer_credit_id);
        PERFORM pg_catalog.pg_advisory_xact_lock(public.cash_source_lock_key('credit', v_refund.refunds_customer_credit_id));
        SELECT x.remaining + y.issued INTO v_left
          FROM public.customer_credit_position_as_of(v_refund.refunds_customer_credit_id, DATE '9999-12-31', pg_catalog.clock_timestamp()) x,
               public.customer_credit_position_as_of(NEW.id, DATE '9999-12-31', pg_catalog.clock_timestamp()) y;
        IF NEW.original_amount <> least(-v_refund.amount, v_left) THEN
            RAISE EXCEPTION USING
                MESSAGE = format('credit %s reissues %s for %s: it carries what came back (%s) as far as it is what is left on the credit (%s before it) (Ryan, 2026-10-21; K-10; v5.4.2-23)', NEW.id, v_refund.payment_number, NEW.original_amount, -v_refund.amount, v_left),
                ERRCODE = 'check_violation';
        END IF;
        PERFORM public.check_cash_source('credit', v_refund.refunds_customer_credit_id, NEW.created_at, 'reissue', NEW.issued_date);
      ELSE
        PERFORM public.check_cash_source('payment', NEW.source_payment_id, NEW.created_at, 'overpayment_credit', NEW.issued_date);
      END IF;
    ELSIF TG_TABLE_NAME = 'escheatment_events' THEN
        -- r6 (Opus S1): a remittance is recorded at a time already reached, for
        -- any role (a superuser's history load keeps its own time): one in
        -- the future would be hidden from the credit's position and would
        -- turn every later draw on it into a retry that cannot succeed.
        IF NOT pg_catalog.isfinite(NEW.created_at) OR NEW.created_at > pg_catalog.clock_timestamp() THEN
            RAISE EXCEPTION USING
                MESSAGE = format('escheatment event %s is recorded at %s, not a time already reached — every money row is recorded at a finite time already reached (v5.4.2-23)', NEW.id, NEW.created_at),
                ERRCODE = 'check_violation';
        END IF;
        IF NOT coalesce(NEW.amount_related > 0, false) THEN
            RAISE EXCEPTION USING
                MESSAGE = format('escheatment event %s remits credit %s: an escheated_to_state event carries the amount remitted, more than 0 (R-06, v5.4.2-23)', NEW.id, NEW.customer_credit_id),
                ERRCODE = 'check_violation';
        END IF;
        PERFORM public.check_cash_source('credit', NEW.customer_credit_id, NEW.created_at, 'escheat', (NEW.event_date AT TIME ZONE 'UTC')::date);
    ELSIF NEW.refunds_payment_id IS NOT NULL THEN
        PERFORM public.check_cash_source('payment', NEW.refunds_payment_id, NEW.created_at, 'refund', NEW.payment_date);
    ELSE
        PERFORM public.check_cash_source('credit', NEW.refunds_customer_credit_id, NEW.created_at, 'refund', NEW.payment_date);
    END IF;
    RETURN NULL;
END;
$$;
COMMENT ON FUNCTION public.enforce_cash_draw() IS
    'v5.4.2-23 (A3, C1; R-06), r4. AFTER INSERT on customer_credits (a credit naming a payment, which only an overpayment credit may: a draw on the payment; r4, a refund_reissue credit: it carries exactly a credit''s refund that came back, and draws on that credit), on payments (a refund: a draw on its payment or credit) and on escheatment_events (an escheated_to_state event, its amount more than 0: a draw on its credit). The source is read and judged under its lock, and capped, by check_cash_source.';
CREATE TRIGGER enforce_cash_draw AFTER INSERT ON public.customer_credits
    FOR EACH ROW WHEN (NEW.source_payment_id IS NOT NULL OR NEW.reissues_refund_id IS NOT NULL) EXECUTE FUNCTION public.enforce_cash_draw();
ALTER TABLE public.customer_credits ENABLE ALWAYS TRIGGER enforce_cash_draw;
CREATE TRIGGER enforce_cash_draw AFTER INSERT ON public.payments
    FOR EACH ROW WHEN (NEW.refunds_payment_id IS NOT NULL OR NEW.refunds_customer_credit_id IS NOT NULL) EXECUTE FUNCTION public.enforce_cash_draw();
ALTER TABLE public.payments ENABLE ALWAYS TRIGGER enforce_cash_draw;
CREATE TRIGGER enforce_cash_draw AFTER INSERT ON public.escheatment_events
    FOR EACH ROW WHEN (NEW.event_type = 'escheated_to_state') EXECUTE FUNCTION public.enforce_cash_draw();
ALTER TABLE public.escheatment_events ENABLE ALWAYS TRIGGER enforce_cash_draw;

-- r4 (Ryan, 2026-10-21, option 1): a refund of an escheated credit that comes
-- back (its posting row undone, the refund moved to nsf or reversed) leaves
-- the money on a credit that has ended. It goes into a new credit for the
-- customer (origin refund_reissue, naming the refund) in the same
-- transaction, after the move (a reissue names a refund already nsf or
-- reversed, Fable S3), and is checked at commit. r5 (Codex B3): nothing
-- positive is left on the credit; where its payment was also taken back,
-- what came back may offset money that never arrived (K-10), and nothing is
-- carried. The status time the check reads is never in the future (B4).
CREATE OR REPLACE FUNCTION public.enforce_escheated_credit_settled() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_status text;
    v_left   numeric;
BEGIN
    SELECT c.status INTO v_status FROM public.customer_credits c WHERE c.id = NEW.refunds_customer_credit_id;
    IF v_status IS DISTINCT FROM 'escheated' THEN
        RETURN NULL;
    END IF;
    SELECT x.remaining INTO v_left
      FROM public.customer_credit_position_as_of(NEW.refunds_customer_credit_id, DATE '9999-12-31', pg_catalog.clock_timestamp()) x;
    IF v_left > 0 THEN
        RAISE EXCEPTION USING
            MESSAGE = format('refund %s of credit %s came back (%s): %s is left on a credit that was escheated — carry it to a new credit (origin refund_reissue, naming the refund) in the same transaction (Ryan, 2026-10-21; v5.4.2-23)', NEW.payment_number, NEW.refunds_customer_credit_id, NEW.status, v_left),
            ERRCODE = 'check_violation';
    END IF;
    RETURN NULL;
END;
$$;
COMMENT ON FUNCTION public.enforce_escheated_credit_settled() IS
    'v5.4.2-23 r4 (Ryan, 2026-10-21). Deferred to commit, after a refund of a credit moves to nsf, reversed or voided: if the credit is escheated, nothing positive may be left on it (customer_credit_position_as_of; r5: where its payment was also taken back, what came back may offset money that never arrived), what is left carried to a refund_reissue credit naming the refund.';
CREATE CONSTRAINT TRIGGER enforce_escheated_credit_settled AFTER UPDATE OF status ON public.payments
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW WHEN (NEW.refunds_customer_credit_id IS NOT NULL AND NEW.status IN ('nsf', 'reversed', 'voided'))
    EXECUTE FUNCTION public.enforce_escheated_credit_settled();
ALTER TABLE public.payments ENABLE ALWAYS TRIGGER enforce_escheated_credit_settled;

-- r3 (Fable S5): an escheat event names its credit's own customer, as a
-- donation does (enforce_ledger_reversal): a remittance on another account
-- would end one customer's credit from another's record.
ALTER TABLE public.escheatment_events
    ADD CONSTRAINT escheatment_events_credit_customer_fkey
        FOREIGN KEY (customer_credit_id, tenant_id, customer_id) REFERENCES public.customer_credits (id, tenant_id, customer_id);

-- r3 (Codex B6): a remittance is money leaving a credit, so the close freezes
-- it like every other money row, by its UTC day (the day the draw and the
-- position date it by). enforce_accounting_freeze reads a date column, and
-- event_date is a timestamp, so the remittance has its own trigger: the
-- tenant's close head, FOR SHARE, before the credit's lock (the lock order).
CREATE OR REPLACE FUNCTION public.enforce_escheat_freeze() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_on      date := (NEW.event_date AT TIME ZONE 'UTC')::date;
    v_through date;
BEGIN
    SELECT h.closed_through INTO v_through
      FROM public.accounting_close_heads h
     WHERE h.tenant_id = NEW.tenant_id
       FOR SHARE;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING
            MESSAGE = format('escheatment_events: tenant %s has no close head visible to this session (v5.4.2-23)', NEW.tenant_id),
            ERRCODE = 'insufficient_privilege';
    END IF;
    IF v_on <= v_through THEN
        RAISE EXCEPTION USING
            MESSAGE = format('escheatment_events: a remittance dated %s (UTC), on or before %s, the end of the tenant''s last closed accounting period — a closed period is frozen; post the correction into an open period (D-2, v5.4.2-23)', v_on, v_through),
            ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$;
COMMENT ON FUNCTION public.enforce_escheat_freeze() IS
    'v5.4.2-23 r3 (Codex B6; D-2). BEFORE INSERT on escheatment_events, for an escheated_to_state event (a remittance, a draw on its credit): takes the tenant''s close head FOR SHARE and refuses a remittance whose UTC day is on or before closed_through. Events are append-only, so an insert is the only write.';
CREATE TRIGGER a_enforce_accounting_freeze BEFORE INSERT ON public.escheatment_events
    FOR EACH ROW WHEN (NEW.event_type = 'escheated_to_state') EXECUTE FUNCTION public.enforce_escheat_freeze();
ALTER TABLE public.escheatment_events ENABLE ALWAYS TRIGGER a_enforce_accounting_freeze;


-- ----------------------------------------------------------------------------
-- 8. The within-bill order: law and tariff rows (A5; K-05, K-07, CI-050)
-- ----------------------------------------------------------------------------
-- The kinds, in one DO block (a kind is registered in its own transaction's
-- block, as -15 did). The schema texts are the committed files, embedded
-- verbatim; CI compares them (lawfiles W4).
DO $kinds$
BEGIN
    INSERT INTO public.rule_term_schemas (terms_kind, terms_version, rule_role, json_schema, introduced_on, description, source_note)
    VALUES ('payment_allocation', 1, 'law', $schema${
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://tally-utility/law/payment_allocation/payment_allocation.v1.schema.json",
  "title": "Payment allocation rule, version 1",
  "description": "What a state's law says about the order in which a payment is applied to the charges within one bill (K-05: within-bill allocation order is jurisdiction rule data). A law that rules an order gives it as two lists of bill-line charge types, the regulated ones first: CI-050's regulated-before-unregulated floor is the shape, so no document can put an unregulated charge first. Every law kind also admits the document 'the law leaves this to the utility'. The order across bills (oldest first, K-05) is not here: it is the same everywhere.",
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
    "charge_type": {
      "type": "string",
      "enum": [
        "base_charge",
        "usage_charge",
        "surcharge",
        "tax",
        "late_fee",
        "deposit",
        "credit",
        "adjustment",
        "penalty",
        "adhoc",
        "minimum_bill_adjustment",
        "consolidated_summary",
        "misc"
      ]
    },
    "charge_types": {
      "type": "array",
      "items": {
        "$ref": "#/$defs/charge_type"
      },
      "uniqueItems": true,
      "maxItems": 13
    },
    "order": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "strategy",
        "version",
        "regulated",
        "unregulated"
      ],
      "properties": {
        "strategy": {
          "type": "string",
          "const": "charge_type_order"
        },
        "version": {
          "type": "integer",
          "minimum": 1,
          "maximum": 1
        },
        "regulated": {
          "$ref": "#/$defs/charge_types"
        },
        "unregulated": {
          "$ref": "#/$defs/charge_types"
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
          "type": "string",
          "pattern": "[A-Za-z0-9]"
        },
        "note": {
          "type": "string",
          "pattern": "[A-Za-z0-9]"
        }
      }
    },
    "law": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "governs",
        "citation",
        "within_bill"
      ],
      "properties": {
        "governs": {
          "type": "string",
          "const": "law"
        },
        "citation": {
          "$ref": "#/$defs/citation"
        },
        "within_bill": {
          "$ref": "#/$defs/order"
        }
      }
    }
  }
}$schema$::jsonb, DATE '2026-10-16',
            'Payment allocation rule: the order in which a state''s law has a payment applied to the charges within one bill, regulated charges first — or the law leaving it to the utility',
            'law/payment_allocation/payment_allocation.v1.schema.json');
    INSERT INTO public.rule_term_schemas (terms_kind, terms_version, rule_role, json_schema, introduced_on, description, source_note)
    VALUES ('payment_allocation_tariff', 1, 'tariff', $schema${
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://tally-utility/law/payment_allocation/payment_allocation_tariff.v1.schema.json",
  "title": "Payment allocation tariff, version 1",
  "description": "A utility's own order for applying a payment to the charges within one bill, from its tariff, confirmed at setup (K-05, K-07: no assumed default). Two lists of bill-line charge types, the regulated ones first (CI-050's floor is the shape). Every charge type appears exactly once across the two lists (the insert check), so the core always has a place for a line.",
  "type": "object",
  "additionalProperties": false,
  "required": [
    "citation",
    "within_bill"
  ],
  "properties": {
    "citation": {
      "$ref": "#/$defs/citation"
    },
    "within_bill": {
      "$ref": "#/$defs/order"
    }
  },
  "$defs": {
    "citation": {
      "type": "string",
      "pattern": "[A-Za-z0-9]"
    },
    "charge_type": {
      "type": "string",
      "enum": [
        "base_charge",
        "usage_charge",
        "surcharge",
        "tax",
        "late_fee",
        "deposit",
        "credit",
        "adjustment",
        "penalty",
        "adhoc",
        "minimum_bill_adjustment",
        "consolidated_summary",
        "misc"
      ]
    },
    "charge_types": {
      "type": "array",
      "items": {
        "$ref": "#/$defs/charge_type"
      },
      "uniqueItems": true,
      "maxItems": 13
    },
    "order": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "strategy",
        "version",
        "regulated",
        "unregulated"
      ],
      "properties": {
        "strategy": {
          "type": "string",
          "const": "charge_type_order"
        },
        "version": {
          "type": "integer",
          "minimum": 1,
          "maximum": 1
        },
        "regulated": {
          "$ref": "#/$defs/charge_types"
        },
        "unregulated": {
          "$ref": "#/$defs/charge_types"
        }
      }
    }
  }
}$schema$::jsonb, DATE '2026-10-16',
            'Payment allocation tariff: a utility''s own order for applying a payment to the charges within one bill, from its tariff, regulated charges first',
            'law/payment_allocation/payment_allocation_tariff.v1.schema.json');
END
$kinds$;

-- Every bill-line charge type exactly once across the two lists: the core
-- always has a place for a line. NULL when complete, else what is wrong.
CREATE OR REPLACE FUNCTION public.payment_allocation_order_gap(p_order jsonb) RETURNS text
    LANGUAGE sql IMMUTABLE
    SET search_path = public, pg_temp
    AS $$
    WITH listed AS (
        SELECT x AS charge_type FROM jsonb_array_elements_text(p_order -> 'regulated') x
        UNION ALL
        SELECT x FROM jsonb_array_elements_text(p_order -> 'unregulated') x
    ), every_type(charge_type) AS (
        SELECT unnest(ARRAY['base_charge', 'usage_charge', 'surcharge', 'tax', 'late_fee', 'deposit', 'credit', 'adjustment',
                            'penalty', 'adhoc', 'minimum_bill_adjustment', 'consolidated_summary', 'misc'])
    )
    SELECT nullif(concat_ws('; ',
        (SELECT 'missing ' || string_agg(e.charge_type, ', ' ORDER BY e.charge_type) FROM every_type e
          WHERE NOT EXISTS (SELECT 1 FROM listed l WHERE l.charge_type = e.charge_type)),
        (SELECT 'listed twice ' || string_agg(DISTINCT l.charge_type, ', ' ORDER BY l.charge_type) FROM listed l
          GROUP BY () HAVING count(*) > count(DISTINCT l.charge_type))), '')
$$;
COMMENT ON FUNCTION public.payment_allocation_order_gap(jsonb) IS
    'v5.4.2-23 (A5). For a within-bill order (regulated and unregulated lists of bill-line charge types): what keeps it from naming every charge type exactly once, or NULL. The list of types repeats invoice_line_items'' charge_type CHECK (residual R5).';
REVOKE ALL ON FUNCTION public.payment_allocation_order_gap(jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.payment_allocation_order_gap(jsonb) TO tally_app, tally_core;

CREATE TABLE public.payment_allocation_rules (
    id                      uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    state_code              text NOT NULL,
    service_type            text NOT NULL,
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
    created_at              timestamp with time zone DEFAULT now() NOT NULL,
    recorded_txid           bigint,
    closed_at               timestamp with time zone,
    closed_by               text,
    CONSTRAINT payment_allocation_rules_pkey PRIMARY KEY (id)
);

CREATE OR REPLACE FUNCTION public.payment_allocation_rule_insert_check(p_row jsonb) RETURNS void
    LANGUAGE plpgsql STABLE
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_gap text;
BEGIN
    IF p_row -> 'terms' ->> 'governs' = 'law' THEN
        v_gap := public.payment_allocation_order_gap(p_row -> 'terms' -> 'within_bill');
        IF v_gap IS NOT NULL THEN
            RAISE EXCEPTION USING
                MESSAGE = format('payment allocation rule (%s %s): the within-bill order names every bill-line charge type exactly once — %s (v5.4.2-23)', p_row ->> 'state_code', p_row ->> 'service_type', v_gap),
                ERRCODE = 'check_violation';
        END IF;
    END IF;
END;
$$;
COMMENT ON FUNCTION public.payment_allocation_rule_insert_check(jsonb) IS
    'v5.4.2-23. The area predicate of payment_allocation_rules (rule_tables.insert_check): a law that rules the within-bill order names every bill-line charge type exactly once. Raises.';

DO $register$
BEGIN
    PERFORM public.rule_table_register('public.payment_allocation_rules', 'law', 'payment_allocation', ARRAY[]::text[], ARRAY[]::text[],
                                       NULL, 'public.payment_allocation_rule_insert_check(jsonb)');
END
$register$;
REVOKE ALL ON FUNCTION public.payment_allocation_rule_insert_check(jsonb) FROM PUBLIC, tally_app, tally_core;
COMMENT ON TABLE public.payment_allocation_rules IS
    'v5.4.2-23 (A5; K-05), on the rule-terms convention. What a state''s law says about the order in which a payment is applied within one bill, per (state, service, owner types, system kinds, dates): one LAW row of the kind payment_allocation, platform-held, never edited. A law that rules the order gives two lists of bill-line charge types, regulated first (CI-050''s floor is the shape); Texas rules none (K-05), so its rows delegate to the utility''s tariff (payment_allocation_tariffs). Another state or service finds no row: unknown law is not permission. Seeded from law/payment_allocation/payment_allocation_rules.yaml.';

CREATE TABLE public.payment_allocation_tariffs (
    id               uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id        uuid NOT NULL,
    state_code       text NOT NULL,
    service_type     text NOT NULL,
    system_kind      text NOT NULL,
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
    CONSTRAINT payment_allocation_tariffs_pkey PRIMARY KEY (id)
);

CREATE OR REPLACE FUNCTION public.payment_allocation_tariff_close_floor(p_tariff_id uuid) RETURNS date
    LANGUAGE plpgsql STABLE
    SET search_path = public, pg_temp
    AS $$
BEGIN
    RETURN (SELECT max(a.applied_on) FROM public.invoice_applications a WHERE a.allocation_tariff_id = p_tariff_id);
END;
$$;
COMMENT ON FUNCTION public.payment_allocation_tariff_close_floor(uuid) IS
    'v5.4.2-23. The close floor of a payment_allocation_tariffs row: the latest money date of an application citing it, or NULL.';

CREATE OR REPLACE FUNCTION public.payment_allocation_tariff_insert_check(p_row jsonb) RETURNS void
    LANGUAGE plpgsql STABLE
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_gap text;
BEGIN
    IF NOT public.is_platform_admin() AND (p_row ->> 'tenant_id')::uuid IS DISTINCT FROM public.get_user_tenant_id()
       AND NOT coalesce((SELECT r.rolsuper OR r.rolbypassrls FROM pg_roles r WHERE r.rolname = current_user), false) THEN
        RAISE EXCEPTION USING
            MESSAGE = 'new row violates row-level security policy for table "payment_allocation_tariffs": a utility writes its own tariff only (v5.4.2-23)',
            ERRCODE = 'insufficient_privilege';
    END IF;
    v_gap := public.payment_allocation_order_gap(p_row -> 'terms' -> 'within_bill');
    IF v_gap IS NOT NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('payment allocation tariff (%s %s): the within-bill order names every bill-line charge type exactly once — %s (K-07: no assumed default; v5.4.2-23)', p_row ->> 'state_code', p_row ->> 'service_type', v_gap),
            ERRCODE = 'check_violation';
    END IF;
END;
$$;
COMMENT ON FUNCTION public.payment_allocation_tariff_insert_check(jsonb) IS
    'v5.4.2-23. The area predicate of payment_allocation_tariffs (rule_tables.insert_check): the writer is the row''s own utility; the within-bill order names every bill-line charge type exactly once. Raises.';

CREATE OR REPLACE FUNCTION public.payment_allocation_tariff_compare(p_tariff jsonb, p_law jsonb) RETURNS text[]
    LANGUAGE plpgsql STABLE
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_problem text[] := '{}';
    v_row     jsonb;
    v_mine    jsonb := p_tariff -> 'terms' -> 'within_bill';
BEGIN
    -- A law that rules the order binds it exactly: the same two lists in the
    -- same order. A delegation compares nothing.
    FOR v_row IN SELECT x FROM jsonb_array_elements(p_law) x LOOP
        IF v_row -> 'terms' ->> 'governs' = 'law'
           AND (v_row -> 'terms' -> 'within_bill' -> 'regulated' IS DISTINCT FROM v_mine -> 'regulated'
                OR v_row -> 'terms' -> 'within_bill' -> 'unregulated' IS DISTINCT FROM v_mine -> 'unregulated') THEN
            v_problem := v_problem || format('law row %s (%s) rules the within-bill order %s / %s; the tariff says %s / %s',
                                             v_row ->> 'id', v_row -> 'terms' ->> 'citation',
                                             v_row -> 'terms' -> 'within_bill' -> 'regulated', v_row -> 'terms' -> 'within_bill' -> 'unregulated',
                                             v_mine -> 'regulated', v_mine -> 'unregulated');
        END IF;
    END LOOP;
    RETURN v_problem;
END;
$$;
COMMENT ON FUNCTION public.payment_allocation_tariff_compare(jsonb, jsonb) IS
    'v5.4.2-23. rule_tables.compare_function of payment_allocation_tariffs: a law row in force that rules the within-bill order binds the tariff to exactly its two lists; a delegation (Texas, K-05) compares nothing.';

DO $register$
BEGIN
    PERFORM public.rule_table_register('public.payment_allocation_tariffs', 'tariff', 'payment_allocation_tariff', ARRAY[]::text[], ARRAY[]::text[],
                                       'public.payment_allocation_tariff_close_floor(uuid)', 'public.payment_allocation_tariff_insert_check(jsonb)',
                                       'public.payment_allocation_rules', 'public.payment_allocation_tariff_compare(jsonb,jsonb)');
END
$register$;
REVOKE ALL ON FUNCTION public.payment_allocation_tariff_close_floor(uuid), public.payment_allocation_tariff_insert_check(jsonb), public.payment_allocation_tariff_compare(jsonb, jsonb)
    FROM PUBLIC, tally_core;
GRANT EXECUTE ON FUNCTION public.payment_allocation_tariff_close_floor(uuid), public.payment_allocation_tariff_insert_check(jsonb), public.payment_allocation_tariff_compare(jsonb, jsonb) TO tally_app;
COMMENT ON TABLE public.payment_allocation_tariffs IS
    'v5.4.2-23 (A5; K-05, K-07), on the rule-terms convention. The utility''s own within-bill order, from its tariff, per (tenant, state, service, system, dates): one row of the kind payment_allocation_tariff, never edited — the one change is a stamped close above the close floor (the latest application citing it). Two lists of bill-line charge types, regulated first; every type exactly once. Measured against payment_allocation_rules when written. No default row: the tenant enters its own at setup (K-07). An application chosen by rule cites the row in force (invoice_applications.allocation_tariff_id).';

ALTER TABLE public.invoice_applications
    ADD CONSTRAINT invoice_applications_tariff_fkey FOREIGN KEY (allocation_tariff_id) REFERENCES public.payment_allocation_tariffs (id);
CREATE INDEX idx_invoice_apps_tariff ON public.invoice_applications (allocation_tariff_id) WHERE allocation_tariff_id IS NOT NULL;

-- The Texas rows (law/payment_allocation/payment_allocation_rules.seed.sql,
-- embedded verbatim).
-- Generated by tools/law/lawc.py emit — do not edit; edit the law file and re-emit.
-- Each call inserts its law row, or finds it unchanged, or raises (public.rule_row_seed, v5.4.2-17).
-- source: law/payment_allocation/payment_allocation_rules.yaml sha256 c94cb8f8504abeed77eff0e57173a9f1044a37eaa1f478945332619614297620
SELECT public.rule_row_seed('public.payment_allocation_rules', $law${"commission_jurisdiction":null,"effective_from":"2004-07-12","effective_to":null,"owner_types":["cooperative","investor_owned"],"service_type":"gas","source_note":"K-05 (Kyle, 2026-10-15): no statewide Texas rule dictates the within-bill order; 16 TAC 7.45 covers service standards, deferred payment plans and disconnection. The utility's tariff sets the order.","state_code":"TX","system_kinds":["distribution"],"terms_kind":"payment_allocation","terms_source":"{\"citation\":\"16 TAC 7.45\",\"governs\":\"delegated_to_utility\",\"note\":\"Sets no order across charge types within a bill (K-05); the utility's tariff does.\"}","terms_version":1}$law$::jsonb);  -- tx_gas_iou_coop
SELECT public.rule_row_seed('public.payment_allocation_rules', $law${"commission_jurisdiction":null,"effective_from":"2004-07-12","effective_to":null,"owner_types":["municipal"],"service_type":"gas","source_note":"Tex. Util. Code 101.003(7): a municipal corporation is not a gas utility; a city-owned system sets its own payment rules in its tariff (K-05, K-07).","state_code":"TX","system_kinds":["distribution"],"terms_kind":"payment_allocation","terms_source":"{\"citation\":\"Tex. Util. Code 101.003(7)\",\"governs\":\"delegated_to_utility\",\"note\":\"A municipal corporation is not a gas utility under GURA; its own tariff sets the order.\"}","terms_version":1}$law$::jsonb);  -- tx_gas_municipal


-- ----------------------------------------------------------------------------
-- 9. Tenant settings K-05 retires (A4, C2)
-- ----------------------------------------------------------------------------
-- K-05: a bill payment goes oldest first. Of payment_allocation_strategy's
-- four values only oldest_first survives, so the column says nothing and goes.
-- overpayment_handling loses apply_to_specific_invoices (no designation of a
-- bill). The history keeps the rows it holds (its known-key CHECK keeps the
-- key: a recorded value is never deleted).
ALTER TABLE public.tenants DROP CONSTRAINT tenants_payment_allocation_strategy_check;
ALTER TABLE public.tenants DROP COLUMN payment_allocation_strategy;
ALTER TABLE public.tenants DROP CONSTRAINT tenants_overpayment_handling_check;
ALTER TABLE public.tenants ADD CONSTRAINT tenants_overpayment_handling_check
    CHECK ((overpayment_handling = ANY (ARRAY['hold_as_credit'::text, 'refund_automatically'::text])));

CREATE OR REPLACE FUNCTION public.record_tenant_configuration_change()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    -- v5.4.2-23: payment_allocation_strategy is no longer a column (K-05).
    c_policy_keys CONSTANT text[] := ARRAY[
        'default_partial_period_policy',
        'overpayment_handling', 'credit_application_timing',
        'minimum_refund_amount', 'below_threshold_action',
        'donation_program_name', 'auto_approve_clean_reads',
        'unreviewed_read_billing_policy', 'meter_redeployment_policy',
        'default_import_error_policy', 'void_only_unbilled_disposition',
        'void_rebill_threshold', 'cutover_date',
        'regulatory_class_mode', 'backbilling_adverse_limit_months',
        'receivables_aging_bucket_days', 'write_off_threshold_days'
    ];
    v_new     jsonb := to_jsonb(NEW);
    v_old     jsonb := CASE WHEN TG_OP = 'UPDATE' THEN to_jsonb(OLD) ELSE NULL END;
    v_source  text  := CASE WHEN TG_OP = 'INSERT' THEN 'onboarding' ELSE 'trigger' END;
    v_user    uuid;
    v_key     text;
    v_old_val jsonb;
    v_new_val jsonb;
BEGIN
    -- Actor from the RLS session context, if any. Tolerate a missing or
    -- malformed GUC rather than failing the tenant write.
    BEGIN
        v_user := NULLIF(current_setting('app.user_id', true), '')::uuid;
    EXCEPTION WHEN OTHERS THEN
        v_user := NULL;
    END;

    -- Typed policy columns.
    FOREACH v_key IN ARRAY c_policy_keys LOOP
        v_new_val := v_new -> v_key;
        v_old_val := CASE WHEN v_old IS NULL THEN NULL ELSE v_old -> v_key END;
        IF TG_OP = 'INSERT' OR v_old_val IS DISTINCT FROM v_new_val THEN
            INSERT INTO public.tenant_configuration_history
                (tenant_id, config_key, old_value, new_value, changed_by, change_source)
            VALUES
                (NEW.id, v_key, v_old_val, v_new_val, v_user, v_source);
        END IF;
    END LOOP;

    -- Top-level settings sub-objects (union of old and new keys).
    FOR v_key IN
        SELECT DISTINCT k FROM (
            SELECT jsonb_object_keys(COALESCE(NEW.settings, '{}'::jsonb)) AS k
            UNION
            SELECT jsonb_object_keys(COALESCE(CASE WHEN TG_OP = 'UPDATE' THEN OLD.settings END, '{}'::jsonb))
        ) keys
    LOOP
        v_new_val := NEW.settings -> v_key;
        v_old_val := CASE WHEN TG_OP = 'UPDATE' THEN OLD.settings -> v_key ELSE NULL END;
        IF TG_OP = 'INSERT' OR v_old_val IS DISTINCT FROM v_new_val THEN
            INSERT INTO public.tenant_configuration_history
                (tenant_id, config_key, old_value, new_value, changed_by, change_source)
            VALUES
                (NEW.id, 'settings.' || v_key, v_old_val, v_new_val, v_user, v_source);
        END IF;
    END LOOP;

    RETURN NEW;
END;
$function$;


-- ----------------------------------------------------------------------------
-- 10. Grants
-- ----------------------------------------------------------------------------
REVOKE UPDATE, DELETE, TRUNCATE ON public.invoice_applications FROM tally_app;
REVOKE ALL ON public.customer_credit_approvals FROM PUBLIC, tally_app, tally_core;
GRANT SELECT, INSERT ON public.customer_credit_approvals TO tally_app;
GRANT SELECT ON public.customer_credit_approvals TO tally_core;



-- ----------------------------------------------------------------------------
-- 11. The invariants
-- ----------------------------------------------------------------------------
-- The seal invariants: -22's body with tally_void's four helper grants.
CREATE OR REPLACE FUNCTION public.assert_seal_role_invariants()
 RETURNS void
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
    v_bad    text;
    r        text;
    v_have   text[];
    v_want   text[];
    -- Exactly what each role owns (r2 F5: exact identities, not names).
    c_owns   CONSTANT jsonb := jsonb_build_object(
        'tally_seal', jsonb_build_array('public.assert_reference_version(text,uuid,integer)'::regprocedure::oid,
                                        'public.reference_version_receipt_held(text,uuid)'::regprocedure::oid),
        'tally_void', jsonb_build_array('public.void_invoice(uuid,uuid,text,text,boolean)'::regprocedure::oid),
        'tally_close', jsonb_build_array('public.close_accounting_period(uuid,numeric,text)'::regprocedure::oid));
    -- Exactly what each role is granted (r2 F5/F6): anything more or less raises.
    c_grants CONSTANT jsonb := jsonb_build_object(
        'tally_seal', '["column public.rate_items.updated_at UPDATE", "column public.rate_items.version UPDATE", "column public.rate_schedules.updated_at UPDATE", "column public.rate_schedules.version UPDATE", "column public.wna_zones.updated_at UPDATE", "column public.wna_zones.version UPDATE", "function public.get_user_tenant_id() EXECUTE", "function public.is_platform_admin() EXECUTE", "schema public USAGE", "table public.rate_items SELECT", "table public.rate_schedules SELECT", "table public.reference_version_receipts INSERT", "table public.reference_version_receipts SELECT", "table public.wna_zones SELECT"]'::jsonb,
        'tally_void', '["column public.accounting_close_heads.updated_at UPDATE", "column public.adhoc_charges.billed_at UPDATE", "column public.adhoc_charges.billed_on_invoice_id UPDATE", "column public.adhoc_charges.billed_on_line_item_id UPDATE", "column public.adhoc_charges.status UPDATE", "column public.adhoc_charges.target_billing_period UPDATE", "column public.adhoc_charges.updated_at UPDATE", "column public.adhoc_charges.voided_from_invoice_id UPDATE", "column public.invoices.status UPDATE", "column public.invoices.updated_at UPDATE", "column public.invoices.void_reason_code UPDATE", "column public.invoices.void_reason_notes UPDATE", "column public.invoices.void_rebill_expected UPDATE", "column public.invoices.voided_at UPDATE", "column public.invoices.voided_by UPDATE", "column public.meter_readings.locked_by_invoice_id UPDATE", "column public.meter_readings.validation_status UPDATE", "column public.meter_readings.voided_from_invoice_id UPDATE", "function public.get_user_tenant_id() EXECUTE", "function public.is_platform_admin() EXECUTE", "function public.ledger_entry_remaining(p_entry uuid) EXECUTE", "function public.ledger_tree_ids(p_root uuid) EXECUTE", "function public.ledger_tree_lock_key(p_root uuid) EXECUTE", "function public.ledger_tree_root(p_entry uuid) EXECUTE", "schema public USAGE", "table public.account_ledger INSERT", "table public.account_ledger SELECT", "table public.accounting_close_heads SELECT", "table public.adhoc_charges SELECT", "table public.invoice_events INSERT", "table public.invoices SELECT", "table public.meter_readings SELECT"]'::jsonb,
        'tally_close', '["column public.accounting_close_heads.closed_through UPDATE", "column public.accounting_close_heads.updated_at UPDATE", "column public.accounting_periods.closed_at UPDATE", "column public.accounting_periods.closed_by UPDATE", "column public.accounting_periods.status UPDATE", "column public.customers.customer_number SELECT", "column public.customers.id SELECT", "column public.tenants.id SELECT", "column public.tenants.receivables_aging_bucket_days SELECT", "column public.users.id SELECT", "column public.users.role SELECT", "column public.users.tenant_id SELECT", "function public.aging_bucket_days_valid(p_days integer[]) EXECUTE", "function public.get_user_tenant_id() EXECUTE", "function public.is_platform_admin() EXECUTE", "function public.receivables_aging_as_of(p_tenant_id uuid, p_on date, p_recorded_at timestamp with time zone, p_bucket_days integer[]) EXECUTE", "function public.session_is_supervisor() EXECUTE", "schema public USAGE", "table public.account_ledger SELECT", "table public.accounting_close_heads SELECT", "table public.accounting_period_snapshot_lines INSERT", "table public.accounting_period_snapshots INSERT", "table public.accounting_periods SELECT", "table public.customer_state_events SELECT"]'::jsonb);
    -- Every guard of the three seals, by its exact definition, enabled
    -- ALWAYS (D-2026-08-20-27: a replication apply does not skip it). r3
    -- (Opus S2): with the version tables' bitemporal guards, which freeze a
    -- version row's entity (the receipt guard reads NEW's entity on that
    -- basis).
    -- v5.4.2-21 (-20 note): these strings are PostgreSQL 16's rendering by
    -- pg_get_triggerdef. A major upgrade may render them differently: re-
    -- capture them from the upgraded catalog (after checking each trigger is
    -- unchanged) before trusting a failure here.
    -- v5.4.2-22: the close's guards are in assert_periods_guard_invariants().
    c_triggers CONSTANT text[] := ARRAY['CREATE TRIGGER a0_enforce_reference_version_receipt BEFORE INSERT OR UPDATE ON public.rate_item_versions FOR EACH ROW EXECUTE FUNCTION enforce_reference_version_receipt(''rate_items'', ''rate_item_id'')',
        'CREATE TRIGGER a0_enforce_reference_version_receipt BEFORE INSERT OR UPDATE ON public.rate_schedule_versions FOR EACH ROW EXECUTE FUNCTION enforce_reference_version_receipt(''rate_schedules'', ''rate_schedule_id'')',
        'CREATE TRIGGER a0_enforce_reference_version_receipt BEFORE INSERT OR UPDATE ON public.wna_zone_versions FOR EACH ROW EXECUTE FUNCTION enforce_reference_version_receipt(''wna_zones'', ''wna_zone_id'')',
        'CREATE TRIGGER a_enforce_attach_to_live_invoice BEFORE INSERT OR UPDATE OF billed_on_invoice_id ON public.adhoc_charges FOR EACH ROW EXECUTE FUNCTION enforce_attach_to_live_invoice(''billed_on_invoice_id'')',
        'CREATE TRIGGER a_enforce_attach_to_live_invoice BEFORE INSERT OR UPDATE OF locked_by_invoice_id ON public.meter_readings FOR EACH ROW EXECUTE FUNCTION enforce_attach_to_live_invoice(''locked_by_invoice_id'')',
        'CREATE TRIGGER a_enforce_bitemporal_assertion BEFORE INSERT OR DELETE OR UPDATE ON public.rate_item_versions FOR EACH ROW EXECUTE FUNCTION enforce_bitemporal_assertion('''', ''rate_item_id'', ''rate_items'')',
        'CREATE TRIGGER a_enforce_bitemporal_assertion BEFORE INSERT OR DELETE OR UPDATE ON public.rate_schedule_versions FOR EACH ROW EXECUTE FUNCTION enforce_bitemporal_assertion('''', ''rate_schedule_id'', ''rate_schedules'')',
        'CREATE TRIGGER a_enforce_bitemporal_assertion BEFORE INSERT OR DELETE OR UPDATE ON public.wna_zone_versions FOR EACH ROW EXECUTE FUNCTION enforce_bitemporal_assertion('''', ''wna_zone_id'', ''wna_zones'')',
        'CREATE TRIGGER a_stamp_reference_version_receipt BEFORE INSERT OR UPDATE ON public.reference_version_receipts FOR EACH ROW EXECUTE FUNCTION stamp_reference_version_receipt()',
        'CREATE TRIGGER enforce_adhoc_charge_immutable BEFORE UPDATE ON public.adhoc_charges FOR EACH ROW EXECUTE FUNCTION enforce_adhoc_charge_immutable()',
        'CREATE TRIGGER enforce_invoice_immutable BEFORE INSERT OR DELETE OR UPDATE ON public.invoices FOR EACH ROW EXECUTE FUNCTION enforce_invoice_immutable()',
        'CREATE TRIGGER enforce_reference_header BEFORE DELETE OR UPDATE ON public.rate_items FOR EACH ROW EXECUTE FUNCTION enforce_reference_header(''item_code'', ''rate_item_versions'', ''rate_item_id'')',
        'CREATE TRIGGER enforce_reference_header BEFORE DELETE OR UPDATE ON public.rate_schedules FOR EACH ROW EXECUTE FUNCTION enforce_reference_header(''code'', ''rate_schedule_versions'', ''rate_schedule_id'')',
        'CREATE TRIGGER enforce_reference_header BEFORE DELETE OR UPDATE ON public.wna_zones FOR EACH ROW EXECUTE FUNCTION enforce_reference_header(''zone_code'', ''wna_zone_versions'', ''wna_zone_id'')',
        'CREATE TRIGGER enforce_reference_header_birth BEFORE INSERT ON public.rate_items FOR EACH ROW EXECUTE FUNCTION enforce_reference_header_birth()',
        'CREATE TRIGGER enforce_reference_header_birth BEFORE INSERT ON public.rate_schedules FOR EACH ROW EXECUTE FUNCTION enforce_reference_header_birth()',
        'CREATE TRIGGER enforce_reference_header_birth BEFORE INSERT ON public.wna_zones FOR EACH ROW EXECUTE FUNCTION enforce_reference_header_birth()',
        'CREATE TRIGGER no_hard_delete BEFORE DELETE ON public.reference_version_receipts FOR EACH ROW EXECUTE FUNCTION enforce_no_hard_delete()',
        'CREATE TRIGGER no_truncate BEFORE TRUNCATE ON public.reference_version_receipts FOR EACH STATEMENT EXECUTE FUNCTION enforce_no_hard_delete()',
        'CREATE TRIGGER trg_enforce_reading_validation_workflow BEFORE UPDATE ON public.meter_readings FOR EACH ROW EXECUTE FUNCTION enforce_reading_validation_workflow()'];
BEGIN
    FOREACH r IN ARRAY ARRAY['tally_seal', 'tally_void', 'tally_close'] LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = r) THEN
            RAISE EXCEPTION USING MESSAGE = format('%s does not exist (v5.4.2-20)', r), ERRCODE = 'invalid_grant_operation';
        END IF;
        IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = r
                      AND (rolsuper OR rolbypassrls OR rolcreaterole OR rolcreatedb OR rolcanlogin OR rolreplication)) THEN
            RAISE EXCEPTION USING
                MESSAGE = format('%s is NOLOGIN and holds no SUPERUSER, BYPASSRLS, CREATEROLE, CREATEDB or REPLICATION (v5.4.2-20)', r),
                ERRCODE = 'invalid_grant_operation';
        END IF;
        -- No members: a member could SET ROLE to it and write as the seal.
        SELECT string_agg(m.member::regrole::text, ', ' ORDER BY 1) INTO v_bad
          FROM pg_auth_members m WHERE m.roleid = r::regrole;
        IF v_bad IS NOT NULL THEN
            RAISE EXCEPTION USING
                MESSAGE = format('%s has members (%s): no role may become it (v5.4.2-20)', r, v_bad),
                ERRCODE = 'invalid_grant_operation';
        END IF;
        SELECT string_agg(m.roleid::regrole::text, ', ' ORDER BY 1) INTO v_bad
          FROM pg_auth_members m WHERE m.member = r::regrole;
        IF v_bad IS NOT NULL THEN
            RAISE EXCEPTION USING
                MESSAGE = format('%s is a member of %s: it belongs to no role (v5.4.2-20)', r, v_bad),
                ERRCODE = 'invalid_grant_operation';
        END IF;
        IF EXISTS (SELECT 1 FROM pg_default_acl d WHERE d.defaclrole = r::regrole)
           OR EXISTS (SELECT 1 FROM pg_default_acl d, aclexplode(d.defaclacl) a WHERE a.grantee = r::regrole) THEN
            RAISE EXCEPTION USING
                MESSAGE = format('%s holds or sets a default privilege: its grants are explicit (v5.4.2-20)', r),
                ERRCODE = 'invalid_grant_operation';
        END IF;
        -- No code of its own: effective privileges, through PUBLIC as well.
        SELECT string_agg(n.nspname, ', ' ORDER BY 1) INTO v_bad
          FROM pg_namespace n
         WHERE has_schema_privilege(r, n.oid, 'CREATE');
        IF has_database_privilege(r, current_database(), 'TEMP') OR has_database_privilege(r, current_database(), 'CREATE')
           OR v_bad IS NOT NULL THEN
            RAISE EXCEPTION USING
                MESSAGE = format('%s can define code (TEMP, CREATE on the database, or CREATE on schema %s) — after a TEMPLATE clone, revoke TEMP from PUBLIC (v5.4.2-20)', r, coalesce(v_bad, 'none')),
                ERRCODE = 'invalid_grant_operation';
        END IF;
        -- It owns exactly its functions, each a definer pinned to public, pg_temp, and no relation or type.
        SELECT string_agg(p.oid::regprocedure::text, ', ' ORDER BY 1) INTO v_bad
          FROM pg_proc p
         WHERE p.proowner = r::regrole
           AND NOT ((c_owns -> r) ? p.oid::text
                    AND p.prosecdef
                    AND coalesce(p.proconfig @> ARRAY['search_path=public, pg_temp'], false));
        IF v_bad IS NOT NULL THEN
            RAISE EXCEPTION USING
                MESSAGE = format('%s owns %s, which is not one of its pinned SECURITY DEFINER functions (v5.4.2-20)', r, v_bad),
                ERRCODE = 'invalid_grant_operation';
        END IF;
        SELECT string_agg(f::oid::regprocedure::text, ', ' ORDER BY 1) INTO v_bad
          FROM jsonb_array_elements_text(c_owns -> r) f
         WHERE NOT EXISTS (SELECT 1 FROM pg_proc p WHERE p.oid = f::oid AND p.proowner = r::regrole);
        IF v_bad IS NOT NULL THEN
            RAISE EXCEPTION USING
                MESSAGE = format('%s no longer owns %s: a DROP and CREATE reverts the owner to its creator — ALTER FUNCTION ... OWNER TO %s (v5.4.2-20)', r, v_bad, r),
                ERRCODE = 'invalid_grant_operation';
        END IF;
        IF EXISTS (SELECT 1 FROM pg_class c WHERE c.relowner = r::regrole)
           OR EXISTS (SELECT 1 FROM pg_type y WHERE y.typowner = r::regrole)
           OR EXISTS (SELECT 1 FROM pg_namespace n WHERE n.nspowner = r::regrole) THEN
            RAISE EXCEPTION USING MESSAGE = format('%s owns a relation, type or schema (v5.4.2-20)', r), ERRCODE = 'invalid_grant_operation';
        END IF;
        -- Exactly its grants (this also keeps tally_seal and tally_void off
        -- users, R6; tally_close reads three columns of it for the supervisor
        -- check).
        v_have := public.seal_role_privileges(r);
        SELECT coalesce(array_agg(x ORDER BY x), '{}') INTO v_want FROM jsonb_array_elements_text(c_grants -> r) x;
        IF EXISTS (SELECT 1 FROM unnest(v_have) x WHERE x <> ALL (v_want))
           OR EXISTS (SELECT 1 FROM unnest(v_want) x WHERE x <> ALL (v_have)) THEN
            RAISE EXCEPTION USING
                MESSAGE = format('%s holds other privileges than it is granted (v5.4.2-20): extra %s; missing %s', r,
                                 (SELECT coalesce(string_agg(x, '; '), 'none') FROM unnest(v_have) x WHERE x <> ALL (v_want)),
                                 (SELECT coalesce(string_agg(x, '; '), 'none') FROM unnest(v_want) x WHERE x <> ALL (v_have))),
                ERRCODE = 'invalid_grant_operation';
        END IF;
    END LOOP;

    -- R5: the core executes no definer but the two RLS helpers (O-B4, C-B4).
    SELECT string_agg(p.oid::regprocedure::text, ', ' ORDER BY 1) INTO v_bad
      FROM pg_proc p
     WHERE p.prosecdef
       AND p.oid NOT IN ('public.get_user_tenant_id()'::regprocedure, 'public.is_platform_admin()'::regprocedure)
       AND has_function_privilege('tally_core', p.oid, 'EXECUTE');
    IF v_bad IS NOT NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('tally_core can execute SECURITY DEFINER %s: a read-only core writes through no definer (v5.4.2-20)', v_bad),
            ERRCODE = 'invalid_grant_operation';
    END IF;

    -- O5: nothing around the check. No privilege at all on the receipts for
    -- the application, the core or PUBLIC, column grants included.
    SELECT string_agg(g || ' ' || p, ', ' ORDER BY 1) INTO v_bad
      FROM unnest(ARRAY['tally_app', 'tally_core', 'public']) g,
           unnest(ARRAY['SELECT', 'INSERT', 'UPDATE', 'REFERENCES']) p
     WHERE has_any_column_privilege(g, 'public.reference_version_receipts', p);
    IF v_bad IS NOT NULL
       OR has_table_privilege('tally_app', 'public.reference_version_receipts', 'DELETE, TRUNCATE')
       OR has_table_privilege('tally_core', 'public.reference_version_receipts', 'DELETE, TRUNCATE')
       OR has_table_privilege('public', 'public.reference_version_receipts', 'DELETE, TRUNCATE') THEN
        RAISE EXCEPTION USING
            MESSAGE = format('reference_version_receipts is reachable by tally_app, tally_core or PUBLIC (%s) (v5.4.2-20)', coalesce(v_bad, 'DELETE or TRUNCATE')),
            ERRCODE = 'invalid_grant_operation';
    END IF;
    SELECT string_agg(t, ', ' ORDER BY t) INTO v_bad
      FROM unnest(ARRAY['rate_schedules', 'rate_items', 'wna_zones']) t
     WHERE has_column_privilege('tally_app', ('public.' || t)::regclass, 'version', 'UPDATE')
        OR has_column_privilege('tally_core', ('public.' || t)::regclass, 'version', 'UPDATE')
        OR has_column_privilege('public', ('public.' || t)::regclass, 'version', 'UPDATE');
    IF v_bad IS NOT NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('the version column of %s is writable outside assert_reference_version() (v5.4.2-20)', v_bad),
            ERRCODE = 'invalid_grant_operation';
    END IF;
    -- v5.4.2-22: the snapshots are the close's alone, and the head moves
    -- only through it.
    SELECT string_agg(g || ' ' || p || ' ' || t, ', ' ORDER BY 1) INTO v_bad
      FROM unnest(ARRAY['tally_app', 'tally_core', 'tally_void', 'public']) g,
           unnest(ARRAY['INSERT', 'UPDATE']) p,
           unnest(ARRAY['accounting_period_snapshots', 'accounting_period_snapshot_lines']) t
     WHERE has_any_column_privilege(g, ('public.' || t)::regclass, p);
    IF v_bad IS NOT NULL
       OR has_column_privilege('tally_app', 'public.accounting_close_heads', 'closed_through', 'UPDATE')
       OR has_column_privilege('tally_core', 'public.accounting_close_heads', 'closed_through', 'UPDATE')
       OR has_column_privilege('tally_void', 'public.accounting_close_heads', 'closed_through', 'UPDATE')
       OR has_column_privilege('tally_app', 'public.accounting_periods', 'closed_at', 'UPDATE')
       OR has_column_privilege('tally_app', 'public.accounting_periods', 'closed_by', 'UPDATE')
       OR has_column_privilege('tally_core', 'public.accounting_periods', 'status', 'UPDATE') THEN
        RAISE EXCEPTION USING
            MESSAGE = format('the close''s tables are writable outside close_accounting_period() (%s) (v5.4.2-22)', coalesce(v_bad, 'closed_through or status')),
            ERRCODE = 'invalid_grant_operation';
    END IF;

    -- O4, lexically: no function in public names the caller-settable void
    -- setting of v5.4.2-01 (a constructed name would pass; the guards key on
    -- the role, so such a function would change nothing they admit).
    SELECT string_agg(p.oid::regprocedure::text, ', ' ORDER BY 1) INTO v_bad
      FROM pg_proc p
     WHERE p.pronamespace = 'public'::regnamespace
       AND strpos(p.prosrc, 'app.' || 'void_operation') > 0;
    IF v_bad IS NOT NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('%s reads the caller-settable void setting; the void is the write made as tally_void (v5.4.2-20)', v_bad),
            ERRCODE = 'invalid_grant_operation';
    END IF;

    -- r3 (Codex S1): PUBLIC, which every role inherits, holds no privilege on
    -- any relation in public (table, view, sequence, or a column of one), so
    -- the seal roles' privileges are exactly their own lists above. A
    -- world-readable lookup is granted to named roles, never to PUBLIC.
    SELECT string_agg(DISTINCT c.relname, ', ') INTO v_bad
      FROM pg_class c
     WHERE c.relnamespace = 'public'::regnamespace
       AND (EXISTS (SELECT 1 FROM aclexplode(c.relacl) a WHERE a.grantee = 0)
            OR EXISTS (SELECT 1 FROM pg_attribute t, aclexplode(t.attacl) a
                        WHERE t.attrelid = c.oid AND NOT t.attisdropped AND a.grantee = 0));
    IF v_bad IS NOT NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('PUBLIC holds a privilege on relation %s (or a column of it): every role, the seal roles included, would inherit it (v5.4.2-20)', v_bad),
            ERRCODE = 'invalid_grant_operation';
    END IF;

    -- r3 (Opus S1, Codex S2): the CHECK that keeps a billed charge on its bill.
    IF NOT EXISTS (SELECT 1 FROM pg_constraint k
                    WHERE k.conrelid = 'public.adhoc_charges'::regclass
                      AND k.conname = 'adhoc_charges_billed_names_its_bill'
                      AND k.contype = 'c' AND k.convalidated
                      AND pg_get_constraintdef(k.oid) = 'CHECK (((status = ''billed''::text) = (billed_on_invoice_id IS NOT NULL)))') THEN
        RAISE EXCEPTION USING
            MESSAGE = 'adhoc_charges_billed_names_its_bill is missing, changed or not validated (v5.4.2-20)',
            ERRCODE = 'invalid_grant_operation';
    END IF;

    -- Every guard, exactly as defined, enabled ALWAYS.
    SELECT string_agg(d, E'\n  ' ORDER BY d) INTO v_bad
      FROM unnest(c_triggers) d
     WHERE NOT EXISTS (SELECT 1 FROM pg_trigger g
                        WHERE NOT g.tgisinternal AND g.tgenabled = 'A'
                          AND pg_get_triggerdef(g.oid) = d);
    IF v_bad IS NOT NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format(E'a seal guard is missing, changed, or not ENABLE ALWAYS (v5.4.2-20):\n  %s', v_bad),
            ERRCODE = 'invalid_grant_operation';
    END IF;
END;
$fn$;
COMMENT ON FUNCTION public.assert_seal_role_invariants() IS
    'v5.4.2-20 (r3), v5.4.2-21, v5.4.2-22, v5.4.2-23 (tally_void executes the four ledger-tree helpers that its void and the reversal rule call). Raises unless: tally_seal, tally_void and tally_close exist, are NOLOGIN without SUPERUSER, BYPASSRLS, CREATEROLE, CREATEDB or REPLICATION, have no members and are members of nothing, hold and set no default privilege, can define no code, own exactly their pinned SECURITY DEFINER functions (by identity) and no relation, type or schema, and hold exactly their granted privileges, grant options included (seal_role_privileges); tally_core executes no definer but the two RLS helpers (by identity); tally_app, tally_core and PUBLIC hold no privilege on the receipts and no UPDATE on a header version; only tally_close writes the snapshots, the closed-through date and a period''s close (closed_at, closed_by; the application withdraws an open period by status); no public function names the old void setting (a lexical test); every guard of the seals exists exactly as defined (PostgreSQL 16''s rendering) and ENABLE ALWAYS; PUBLIC holds no privilege on any relation in public; and adhoc_charges_billed_names_its_bill is present and validated. Run in the patch tail and in CI.';
REVOKE ALL ON FUNCTION public.assert_seal_role_invariants() FROM PUBLIC, tally_app, tally_core;

-- The periods invariants: -22's body with the reversal trigger, the FK and
-- the plan settings -23 changes.
CREATE OR REPLACE FUNCTION public.assert_periods_guard_invariants() RETURNS void
    LANGUAGE plpgsql STABLE
    SET search_path = public, pg_temp
    AS $fn$
DECLARE
    v_bad text;
    -- PostgreSQL 16's rendering by pg_get_triggerdef (see the seal
    -- invariants): the -22 guards, and the ledger's immutability, on which
    -- an INSERT-only freeze rests (r2, Fable S5).
    c_triggers CONSTANT text[] := ARRAY[
        'CREATE TRIGGER a_enforce_accounting_freeze BEFORE INSERT ON public.account_ledger FOR EACH ROW EXECUTE FUNCTION enforce_accounting_freeze(''transaction_date'')',
        'CREATE TRIGGER a_enforce_accounting_freeze BEFORE INSERT OR UPDATE OF issued_date, tenant_id ON public.customer_credits FOR EACH ROW EXECUTE FUNCTION enforce_accounting_freeze(''issued_date'')',
        'CREATE TRIGGER a_enforce_accounting_freeze BEFORE INSERT OR UPDATE OF payment_date, tenant_id ON public.payments FOR EACH ROW EXECUTE FUNCTION enforce_accounting_freeze(''payment_date'')',
        'CREATE TRIGGER create_accounting_close_head AFTER INSERT ON public.tenants FOR EACH ROW EXECUTE FUNCTION create_accounting_close_head()',
        'CREATE TRIGGER enforce_aging_edges_close_order BEFORE UPDATE OF receivables_aging_bucket_days ON public.tenants FOR EACH ROW EXECUTE FUNCTION enforce_aging_edges_close_order()',
        'CREATE TRIGGER enforce_accounting_close_head BEFORE INSERT OR DELETE OR UPDATE ON public.accounting_close_heads FOR EACH ROW EXECUTE FUNCTION enforce_accounting_close_head()',
        'CREATE TRIGGER enforce_accounting_period BEFORE INSERT OR DELETE OR UPDATE ON public.accounting_periods FOR EACH ROW EXECUTE FUNCTION enforce_accounting_period()',
        'CREATE TRIGGER enforce_accounting_snapshot_write BEFORE INSERT OR DELETE OR UPDATE ON public.accounting_period_snapshot_lines FOR EACH ROW EXECUTE FUNCTION enforce_accounting_snapshot_write()',
        'CREATE TRIGGER enforce_accounting_snapshot_write BEFORE INSERT OR DELETE OR UPDATE ON public.accounting_period_snapshots FOR EACH ROW EXECUTE FUNCTION enforce_accounting_snapshot_write()',
        'CREATE TRIGGER enforce_account_ledger_immutable BEFORE UPDATE ON public.account_ledger FOR EACH ROW EXECUTE FUNCTION enforce_account_ledger_immutable()',
        'CREATE TRIGGER enforce_gl_account_mapping BEFORE INSERT OR DELETE OR UPDATE ON public.gl_account_mappings FOR EACH ROW EXECUTE FUNCTION enforce_gl_account_mapping()',
        'CREATE TRIGGER enforce_ledger_lineage_acyclic AFTER INSERT ON public.account_ledger FOR EACH ROW WHEN ((new.reverses_ledger_entry_id IS NOT NULL)) EXECUTE FUNCTION enforce_ledger_lineage_acyclic()',
        -- v5.4.2-23: the recovery rule, made general (X2).
        'CREATE TRIGGER enforce_ledger_reversal AFTER INSERT ON public.account_ledger FOR EACH ROW EXECUTE FUNCTION enforce_ledger_reversal()',
        'CREATE TRIGGER no_hard_delete BEFORE DELETE ON public.account_ledger FOR EACH ROW EXECUTE FUNCTION enforce_no_hard_delete()',
        'CREATE TRIGGER no_truncate BEFORE TRUNCATE ON public.accounting_close_heads FOR EACH STATEMENT EXECUTE FUNCTION enforce_accounting_close_head()',
        'CREATE TRIGGER no_truncate BEFORE TRUNCATE ON public.accounting_periods FOR EACH STATEMENT EXECUTE FUNCTION enforce_accounting_period()',
        'CREATE TRIGGER no_truncate BEFORE TRUNCATE ON public.accounting_period_snapshot_lines FOR EACH STATEMENT EXECUTE FUNCTION enforce_accounting_snapshot_write()',
        'CREATE TRIGGER no_truncate BEFORE TRUNCATE ON public.accounting_period_snapshots FOR EACH STATEMENT EXECUTE FUNCTION enforce_accounting_snapshot_write()',
        'CREATE TRIGGER no_truncate BEFORE TRUNCATE ON public.account_ledger FOR EACH STATEMENT EXECUTE FUNCTION enforce_no_hard_delete()',
        'CREATE TRIGGER no_truncate BEFORE TRUNCATE ON public.gl_account_mappings FOR EACH STATEMENT EXECUTE FUNCTION enforce_gl_account_mapping()'];
    -- r2 (Opus S3, Codex S3): the -22 constraints, by exact definition;
    -- r3 (Codex S2, Fable N3, Opus N4): the history's known-key CHECK -22
    -- re-issues, and the ledger's lineage constraints the walk and cap rest on.
    c_constraints CONSTANT text[] := ARRAY[
        'account_ledger account_ledger_recovery_lineage_check CHECK (((transaction_type <> ''write_off_recovery''::text) OR ((reverses_ledger_entry_id IS NOT NULL) AND COALESCE((reversal_reason ~ ''[[:alnum:]]''::text), false))))',
        'account_ledger account_ledger_reversal_not_self_check CHECK ((reverses_ledger_entry_id IS DISTINCT FROM id))',
        -- v5.4.2-23 (X1b): within the customer.
        'account_ledger account_ledger_reverses_ledger_entry_fkey FOREIGN KEY (reverses_ledger_entry_id, tenant_id, customer_id) REFERENCES account_ledger(id, tenant_id, customer_id)',
        'account_ledger account_ledger_transaction_type_check CHECK ((transaction_type = ANY (ARRAY[''charge''::text, ''payment''::text, ''adjustment''::text, ''credit_issued''::text, ''credit_applied''::text, ''late_fee''::text, ''deposit''::text, ''refund''::text, ''write_off''::text, ''transfer''::text, ''nsf''::text, ''escheat''::text, ''donation''::text, ''void_reversal''::text, ''deposit_interest''::text, ''write_off_recovery''::text])))',
        'accounting_period_snapshot_lines accounting_period_snapshot_lines_section_check CHECK ((section = ANY (ARRAY[''activity''::text, ''aging''::text])))',
        'accounting_period_snapshots accounting_period_snapshots_unbilled_check CHECK ((((unbilled_revenue IS NULL) AND (unbilled_revenue_basis IS NULL)) OR ((unbilled_revenue IS NOT NULL) AND COALESCE((unbilled_revenue_basis ~ ''[[:alnum:]]''::text), false))))',
        'accounting_periods accounting_periods_closed_stamp_check CHECK (((status = ''closed''::text) = (closed_at IS NOT NULL)))',
        'accounting_periods accounting_periods_no_overlap EXCLUDE USING gist (tenant_id WITH =, daterange(period_start, period_end, ''[]''::text) WITH &&) WHERE ((status <> ''withdrawn''::text))',
        'accounting_periods accounting_periods_range_check CHECK ((period_end >= period_start))',
        'accounting_periods accounting_periods_status_check CHECK ((status = ANY (ARRAY[''open''::text, ''closed''::text, ''withdrawn''::text])))',
        'accounting_periods accounting_periods_withdrawn_stamp_check CHECK (((status = ''withdrawn''::text) = (withdrawn_at IS NOT NULL)))',
        'gl_account_mappings gl_account_mappings_account_check CHECK ((gl_account ~ ''[[:alnum:]]''::text))',
        'gl_account_mappings gl_account_mappings_charge_check CHECK (((charge_source IS NULL) OR ((charge_source = ''bill_line''::text) AND (charge_code = ANY (ARRAY[''base_charge''::text, ''usage_charge''::text, ''surcharge''::text, ''tax''::text, ''late_fee''::text, ''deposit''::text, ''credit''::text, ''adjustment''::text, ''penalty''::text, ''adhoc''::text, ''minimum_bill_adjustment''::text, ''consolidated_summary''::text, ''misc''::text]))) OR ((charge_source = ''adhoc_charge''::text) AND (charge_code = ANY (ARRAY[''tap_fee''::text, ''reconnection_fee''::text, ''disconnection_fee''::text, ''after_hours_fee''::text, ''meter_test_fee''::text, ''meter_install_fee''::text, ''damage_fee''::text, ''returned_payment_fee''::text, ''late_fee''::text, ''penalty''::text, ''deposit''::text, ''deposit_refund''::text, ''credit''::text, ''adjustment''::text, ''backflow_test_fee''::text, ''hydrant_meter_rental''::text, ''miscellaneous''::text]))) OR ((charge_source = ''ledger_entry''::text) AND (charge_code = ANY (ARRAY[''charge''::text, ''payment''::text, ''adjustment''::text, ''credit_issued''::text, ''credit_applied''::text, ''late_fee''::text, ''deposit''::text, ''refund''::text, ''write_off''::text, ''transfer''::text, ''nsf''::text, ''escheat''::text, ''donation''::text, ''void_reversal''::text, ''deposit_interest''::text, ''write_off_recovery''::text])))))',
        'gl_account_mappings gl_account_mappings_charge_pair_check CHECK (((charge_source IS NULL) = (charge_code IS NULL)))',
        'gl_account_mappings gl_account_mappings_customer_class_check CHECK (((customer_class IS NULL) OR (customer_class = ANY (ARRAY[''residential''::text, ''commercial''::text, ''small_commercial''::text, ''large_commercial''::text, ''industrial''::text, ''government''::text, ''wholesale''::text]))))',
        'gl_account_mappings gl_account_mappings_no_overlap EXCLUDE USING gist (tenant_id WITH =, COALESCE(charge_source, ''''::text) WITH =, COALESCE(charge_code, ''''::text) WITH =, COALESCE(customer_class, ''''::text) WITH =, COALESCE(territory_place_id, ''00000000-0000-0000-0000-000000000000''::uuid) WITH =, COALESCE(tax_jurisdiction_place_id, ''00000000-0000-0000-0000-000000000000''::uuid) WITH =, daterange(effective_from, effective_to, ''[)''::text) WITH &&)',
        'gl_account_mappings gl_account_mappings_range_check CHECK (((effective_to IS NULL) OR (effective_to > effective_from)))',
        'tenant_configuration_history tenant_configuration_history_aging_days_check CHECK (((config_key <> ''receivables_aging_bucket_days''::text) OR aging_bucket_days_json_valid(new_value)))',
        'tenant_configuration_history tenant_configuration_history_key_known_check CHECK (((config_key ~~ ''settings.%''::text) OR (config_key = ANY (ARRAY[''default_partial_period_policy''::text, ''payment_allocation_strategy''::text, ''overpayment_handling''::text, ''credit_application_timing''::text, ''minimum_refund_amount''::text, ''below_threshold_action''::text, ''donation_program_name''::text, ''auto_approve_clean_reads''::text, ''unreviewed_read_billing_policy''::text, ''meter_redeployment_policy''::text, ''default_import_error_policy''::text, ''void_only_unbilled_disposition''::text, ''void_rebill_threshold''::text, ''cutover_date''::text, ''regulatory_class_mode''::text, ''backbilling_adverse_limit_months''::text, ''receivables_aging_bucket_days''::text, ''write_off_threshold_days''::text]))))',
        'tenants tenants_receivables_aging_bucket_days_check CHECK (aging_bucket_days_valid(receivables_aging_bucket_days))',
        'tenants tenants_write_off_threshold_days_check CHECK (((write_off_threshold_days IS NULL) OR (write_off_threshold_days > 0)))'];
BEGIN
    SELECT string_agg(d, E'\n  ' ORDER BY d) INTO v_bad
      FROM unnest(c_triggers) d
     WHERE NOT EXISTS (SELECT 1 FROM pg_catalog.pg_trigger g
                        WHERE NOT g.tgisinternal AND g.tgenabled = 'A'
                          AND pg_catalog.pg_get_triggerdef(g.oid) = d);
    IF v_bad IS NOT NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format(E'a v5.4.2-22 guard is missing, changed, or not ENABLE ALWAYS:\n  %s', v_bad),
            ERRCODE = 'invalid_grant_operation';
    END IF;
    SELECT string_agg(d, E'\n  ' ORDER BY d) INTO v_bad
      FROM unnest(c_constraints) d
     WHERE NOT EXISTS (SELECT 1 FROM pg_catalog.pg_constraint k
                        WHERE k.convalidated
                          AND k.conrelid::regclass::text || ' ' || k.conname || ' ' || pg_catalog.pg_get_constraintdef(k.oid) = d);
    IF v_bad IS NOT NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format(E'a v5.4.2-22 constraint is missing, changed or not validated:\n  %s', v_bad),
            ERRCODE = 'invalid_grant_operation';
    END IF;
    -- r5 (Fable S2): the walks' plan settings (R11) are part of the guard.
    SELECT string_agg(f, ', ' ORDER BY f) INTO v_bad
      FROM unnest(ARRAY['public.enforce_ledger_reversal()', 'public.enforce_ledger_lineage_acyclic()', 'public.ledger_tree_ids(uuid)', 'public.ledger_tree_root(uuid)', 'public.ledger_entry_remaining(uuid)']) f
     WHERE (SELECT p.proconfig FROM pg_catalog.pg_proc p WHERE p.oid = f::regprocedure)
           IS DISTINCT FROM ARRAY['search_path=public, pg_temp', 'enable_seqscan=off', 'enable_hashjoin=off', 'enable_mergejoin=off'];
    IF v_bad IS NOT NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('a v5.4.2-22 walk has lost its plan settings (search_path, enable_seqscan, enable_hashjoin, enable_mergejoin): %s', v_bad),
            ERRCODE = 'invalid_grant_operation';
    END IF;
    -- Every tenant has its close head (the freeze requires it).
    SELECT string_agg(t.id::text, ', ') INTO v_bad
      FROM public.tenants t
     WHERE NOT EXISTS (SELECT 1 FROM public.accounting_close_heads h WHERE h.tenant_id = t.id);
    IF v_bad IS NOT NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('tenants without a close head: %s (v5.4.2-22)', v_bad),
            ERRCODE = 'invalid_grant_operation';
    END IF;
END;
$fn$;
COMMENT ON FUNCTION public.assert_periods_guard_invariants() IS
    'v5.4.2-22 (r2, r3, r5); v5.4.2-23 (the recovery trigger replaced by the general reversal rule, enforce_ledger_reversal; the reversal FK within the customer; the plan settings of its walks and helpers). Raises unless every guard of v5.4.2-22 — the close head, the periods, the freeze on the ledger, payments and customer credits, the recovery and the lineage walk, the snapshot tables, the GL mappings, the head''s creation with each tenant — and the ledger''s immutability triggers exist exactly as defined (PostgreSQL 16''s rendering) and ENABLE ALWAYS; the constraints named here (the periods'' and mappings'' EXCLUDE and CHECKs, the ledger''s type list, recovery lineage, not-self CHECK and reversal FK, the tenants'' and history''s setting CHECKs and the history''s known-key CHECK) exist exactly as defined and validated — not every key and FK of the new tables (the snapshot tables'' keys are not pinned); the two walks'' plan settings (r5); and every tenant has a close head (run as the owner, which sees every tenant). Checks definitions, not the bodies of the functions they call. Run in the patch tail and in CI.';
REVOKE ALL ON FUNCTION public.assert_periods_guard_invariants() FROM PUBLIC, tally_app, tally_core;

CREATE OR REPLACE FUNCTION public.assert_cash_guard_invariants() RETURNS void
    LANGUAGE plpgsql STABLE
    SET search_path = public, pg_temp
    AS $fn$
DECLARE
    v_bad text;
    -- PostgreSQL 16's rendering by pg_get_triggerdef: the -23 guards, and the
    -- money tables' retention and immutability triggers they rest on.
    c_triggers CONSTANT text[] := ARRAY[
        'CREATE CONSTRAINT TRIGGER enforce_invoice_line_class AFTER INSERT OR UPDATE ON public.invoices DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION enforce_invoice_line_class()',
        'CREATE TRIGGER a_enforce_accounting_freeze BEFORE INSERT ON public.account_ledger FOR EACH ROW EXECUTE FUNCTION enforce_accounting_freeze(''transaction_date'')',
        'CREATE TRIGGER a_enforce_accounting_freeze BEFORE INSERT ON public.invoice_applications FOR EACH ROW EXECUTE FUNCTION enforce_accounting_freeze(''applied_on'')',
        'CREATE TRIGGER a_enforce_accounting_freeze BEFORE INSERT OR UPDATE OF issued_date, tenant_id ON public.customer_credits FOR EACH ROW EXECUTE FUNCTION enforce_accounting_freeze(''issued_date'')',
        'CREATE TRIGGER a_enforce_accounting_freeze BEFORE INSERT OR UPDATE OF payment_date, tenant_id ON public.payments FOR EACH ROW EXECUTE FUNCTION enforce_accounting_freeze(''payment_date'')',
        -- r3 (Codex B6; Fable S6): the remittance's freeze and stamp.
        'CREATE TRIGGER a_enforce_accounting_freeze BEFORE INSERT ON public.escheatment_events FOR EACH ROW WHEN ((new.event_type = ''escheated_to_state''::text)) EXECUTE FUNCTION enforce_escheat_freeze()',
        'CREATE TRIGGER a_stamp_created_at BEFORE INSERT ON public.escheatment_events FOR EACH ROW EXECUTE FUNCTION stamp_log_created_at()',
        'CREATE TRIGGER append_only BEFORE DELETE OR UPDATE ON public.customer_credit_approvals FOR EACH ROW EXECUTE FUNCTION enforce_append_only()',
        'CREATE TRIGGER append_only BEFORE DELETE OR UPDATE ON public.invoice_applications FOR EACH ROW EXECUTE FUNCTION enforce_append_only()',
        'CREATE TRIGGER a_stamp_created_at BEFORE INSERT ON public.account_ledger FOR EACH ROW EXECUTE FUNCTION stamp_log_created_at()',
        'CREATE TRIGGER a_stamp_created_at BEFORE INSERT ON public.customer_credit_approvals FOR EACH ROW EXECUTE FUNCTION stamp_log_created_at()',
        'CREATE TRIGGER a_stamp_created_at BEFORE INSERT ON public.customer_credits FOR EACH ROW EXECUTE FUNCTION stamp_log_created_at()',
        'CREATE TRIGGER a_stamp_created_at BEFORE INSERT ON public.invoice_applications FOR EACH ROW EXECUTE FUNCTION stamp_log_created_at()',
        'CREATE TRIGGER a_stamp_created_at BEFORE INSERT ON public.payments FOR EACH ROW EXECUTE FUNCTION stamp_log_created_at()',
        'CREATE TRIGGER a_enforce_cash_birth BEFORE INSERT ON public.customer_credits FOR EACH ROW EXECUTE FUNCTION enforce_cash_birth()',
        'CREATE TRIGGER a_enforce_cash_birth BEFORE INSERT ON public.payments FOR EACH ROW EXECUTE FUNCTION enforce_cash_birth()',
        'CREATE TRIGGER append_only BEFORE DELETE OR UPDATE ON public.escheatment_events FOR EACH ROW EXECUTE FUNCTION enforce_append_only()',
        'CREATE TRIGGER enforce_cash_draw AFTER INSERT ON public.customer_credits FOR EACH ROW WHEN (((new.source_payment_id IS NOT NULL) OR (new.reissues_refund_id IS NOT NULL))) EXECUTE FUNCTION enforce_cash_draw()',
        -- r4 (Ryan, 2026-10-21): a returned refund of an escheated credit is carried.
        'CREATE CONSTRAINT TRIGGER enforce_escheated_credit_settled AFTER UPDATE OF status ON public.payments DEFERRABLE INITIALLY DEFERRED FOR EACH ROW WHEN (((new.refunds_customer_credit_id IS NOT NULL) AND (new.status = ANY (ARRAY[''nsf''::text, ''reversed''::text, ''voided''::text])))) EXECUTE FUNCTION enforce_escheated_credit_settled()',
        'CREATE TRIGGER enforce_cash_draw AFTER INSERT ON public.escheatment_events FOR EACH ROW WHEN ((new.event_type = ''escheated_to_state''::text)) EXECUTE FUNCTION enforce_cash_draw()',
        'CREATE TRIGGER enforce_cash_draw AFTER INSERT ON public.payments FOR EACH ROW WHEN (((new.refunds_payment_id IS NOT NULL) OR (new.refunds_customer_credit_id IS NOT NULL))) EXECUTE FUNCTION enforce_cash_draw()',
        'CREATE TRIGGER enforce_customer_credit_immutable BEFORE UPDATE ON public.customer_credits FOR EACH ROW EXECUTE FUNCTION enforce_customer_credit_immutable()',
        'CREATE TRIGGER enforce_invoice_application AFTER INSERT ON public.invoice_applications FOR EACH ROW EXECUTE FUNCTION enforce_invoice_application()',
        'CREATE TRIGGER enforce_ledger_reversal AFTER INSERT ON public.account_ledger FOR EACH ROW EXECUTE FUNCTION enforce_ledger_reversal()',
        'CREATE TRIGGER enforce_payment_immutable BEFORE UPDATE ON public.payments FOR EACH ROW EXECUTE FUNCTION enforce_payment_immutable()',
        'CREATE TRIGGER no_hard_delete BEFORE DELETE ON public.account_ledger FOR EACH ROW EXECUTE FUNCTION enforce_no_hard_delete()',
        'CREATE TRIGGER no_hard_delete BEFORE DELETE ON public.customer_credits FOR EACH ROW EXECUTE FUNCTION enforce_no_hard_delete()',
        'CREATE TRIGGER no_hard_delete BEFORE DELETE ON public.invoice_applications FOR EACH ROW EXECUTE FUNCTION enforce_no_hard_delete()',
        'CREATE TRIGGER no_hard_delete BEFORE DELETE ON public.payments FOR EACH ROW EXECUTE FUNCTION enforce_no_hard_delete()',
        'CREATE TRIGGER no_truncate BEFORE TRUNCATE ON public.account_ledger FOR EACH STATEMENT EXECUTE FUNCTION enforce_no_hard_delete()',
        'CREATE TRIGGER no_truncate BEFORE TRUNCATE ON public.customer_credit_approvals FOR EACH STATEMENT EXECUTE FUNCTION enforce_no_hard_delete()',
        'CREATE TRIGGER no_truncate BEFORE TRUNCATE ON public.customer_credits FOR EACH STATEMENT EXECUTE FUNCTION enforce_no_hard_delete()',
        'CREATE TRIGGER no_truncate BEFORE TRUNCATE ON public.invoice_applications FOR EACH STATEMENT EXECUTE FUNCTION enforce_no_hard_delete()',
        'CREATE TRIGGER no_truncate BEFORE TRUNCATE ON public.invoices FOR EACH STATEMENT EXECUTE FUNCTION enforce_no_hard_delete()',
        'CREATE TRIGGER no_truncate BEFORE TRUNCATE ON public.payments FOR EACH STATEMENT EXECUTE FUNCTION enforce_no_hard_delete()'];
    c_constraints CONSTANT text[] := ARRAY[
        'account_ledger account_ledger_id_tenant_customer_key UNIQUE (id, tenant_id, customer_id)',
        'account_ledger account_ledger_reversal_types_only_check CHECK (((reverses_ledger_entry_id IS NULL) OR (transaction_type = ANY (ARRAY[''void_reversal''::text, ''nsf''::text, ''write_off_recovery''::text, ''adjustment''::text, ''write_off''::text]))))',
        'account_ledger account_ledger_reversal_types_name_check CHECK (((transaction_type <> ALL (ARRAY[''void_reversal''::text, ''nsf''::text, ''write_off_recovery''::text])) OR (reverses_ledger_entry_id IS NOT NULL)))',
        'account_ledger account_ledger_refund_sign_check CHECK (((transaction_type <> ''refund''::text) OR (amount > (0)::numeric)))',
        'account_ledger account_ledger_reverses_ledger_entry_fkey FOREIGN KEY (reverses_ledger_entry_id, tenant_id, customer_id) REFERENCES account_ledger(id, tenant_id, customer_id)',
        'adhoc_charges adhoc_charges_void_reason_check CHECK (((status <> ''void''::text) OR COALESCE((void_reason ~ ''[[:alnum:]]''::text), false)))',
        'adhoc_charges adhoc_charges_waive_reason_check CHECK (((status <> ''waived''::text) OR COALESCE((waive_reason ~ ''[[:alnum:]]''::text), false)))',
        'customer_credit_approvals customer_credit_approvals_amount_check CHECK ((amount > (0)::numeric))',
        'customer_credit_approvals customer_credit_approvals_approved_by_fkey FOREIGN KEY (approved_by, tenant_id) REFERENCES users(id, tenant_id)',
        'customer_credit_approvals customer_credit_approvals_credit_key UNIQUE (id, tenant_id, customer_id, payment_id, amount)',
        'customer_credit_approvals customer_credit_approvals_payment_fkey FOREIGN KEY (payment_id, tenant_id, customer_id) REFERENCES payments(id, tenant_id, customer_id)',
        -- r3 (Fable S6): the cap's ceiling, and the sign the draw set reads.
        'customer_credits customer_credits_original_amount_check CHECK ((original_amount > (0)::numeric))',
        'customer_credits customer_credits_reissue_refund_fkey FOREIGN KEY (reissues_refund_id, tenant_id, customer_id) REFERENCES payments(id, tenant_id, customer_id)',
        'customer_credits customer_credits_reissue_check CHECK (((origin_type = ''refund_reissue''::text) = (reissues_refund_id IS NOT NULL)))',
        'customer_credits customer_credits_approval_fkey FOREIGN KEY (approval_id, tenant_id, customer_id, source_payment_id, original_amount) REFERENCES customer_credit_approvals(id, tenant_id, customer_id, payment_id, amount)',
        'customer_credits customer_credits_overpayment_approved_check CHECK ((((origin_type = ''overpayment''::text) = (approval_id IS NOT NULL)) AND ((approval_id IS NULL) OR (source_payment_id IS NOT NULL))))',
        'customer_credits customer_credits_payment_overpayment_check CHECK (((source_payment_id IS NULL) OR (origin_type = ''overpayment''::text)))',
        'customer_credits customer_credits_status_check CHECK ((status = ANY (ARRAY[''active''::text, ''escheated''::text, ''voided''::text])))',
        'payments payments_status_check CHECK ((status = ANY (ARRAY[''pending''::text, ''posted''::text, ''nsf''::text, ''reversed''::text, ''voided''::text])))',
        'escheatment_events escheatment_events_credit_customer_fkey FOREIGN KEY (customer_credit_id, tenant_id, customer_id) REFERENCES customer_credits(id, tenant_id, customer_id)',
        'invoice_applications invoice_applications_basis_check CHECK ((basis = ANY (ARRAY[''oldest_first''::text, ''operator_override''::text, ''restriction''::text, ''floor_over_restriction''::text, ''undo''::text])))',
        'invoice_applications invoice_applications_credit_fkey FOREIGN KEY (customer_credit_id, tenant_id, customer_id) REFERENCES customer_credits(id, tenant_id, customer_id)',
        'invoice_applications invoice_applications_id_tenant_line_key UNIQUE (id, tenant_id, invoice_line_item_id)',
        'invoice_applications invoice_applications_invoice_fkey FOREIGN KEY (invoice_id, tenant_id, customer_id) REFERENCES invoices(id, tenant_id, customer_id)',
        'invoice_applications invoice_applications_line_fkey FOREIGN KEY (invoice_line_item_id, invoice_id, tenant_id) REFERENCES invoice_line_items(id, invoice_id, tenant_id)',
        'invoice_applications invoice_applications_not_self_check CHECK ((undoes_application_id IS DISTINCT FROM id))',
        'invoice_applications invoice_applications_one_source_check CHECK ((num_nonnulls(payment_id, customer_credit_id) = 1))',
        'invoice_applications invoice_applications_operator_check CHECK (((basis <> ALL (ARRAY[''operator_override''::text, ''undo''::text])) OR ((applied_by IS NOT NULL) AND COALESCE((reason ~ ''[[:alnum:]]''::text), false))))',
        'invoice_applications invoice_applications_payment_fkey FOREIGN KEY (payment_id, tenant_id, customer_id) REFERENCES payments(id, tenant_id, customer_id)',
        'invoice_applications invoice_applications_sign_check CHECK (((amount <> (0)::numeric) AND ((amount < (0)::numeric) = (basis = ''undo''::text)) AND ((basis = ''undo''::text) = (undoes_application_id IS NOT NULL))))',
        'invoice_applications invoice_applications_tariff_check CHECK (((allocation_tariff_id IS NOT NULL) = (basis = ANY (ARRAY[''oldest_first''::text, ''restriction''::text, ''floor_over_restriction''::text]))))',
        'invoice_applications invoice_applications_tariff_fkey FOREIGN KEY (allocation_tariff_id) REFERENCES payment_allocation_tariffs(id)',
        'invoice_applications invoice_applications_tenant_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id)',
        'invoice_applications invoice_applications_undoes_fkey FOREIGN KEY (undoes_application_id, tenant_id, invoice_line_item_id) REFERENCES invoice_applications(id, tenant_id, invoice_line_item_id)',
        'invoice_line_items invoice_line_items_id_invoice_tenant_key UNIQUE (id, invoice_id, tenant_id)',
        'invoice_line_items invoice_line_items_regulatory_class_check CHECK ((regulatory_class = ANY (ARRAY[''regulated''::text, ''unregulated''::text])))',
        'invoices invoices_id_tenant_customer_key UNIQUE (id, tenant_id, customer_id)',
        'payments payments_payer_class_check CHECK ((payer_class = ANY (ARRAY[''customer''::text, ''agency''::text])))',
        'payments payments_refund_is_refund_check CHECK ((((refunds_payment_id IS NULL) AND (refunds_customer_credit_id IS NULL)) OR ((payment_method = ''refund''::text) AND (amount < (0)::numeric))))',
        'payments payments_restricted_invoice_fkey FOREIGN KEY (restricted_to_invoice_id, tenant_id, customer_id) REFERENCES invoices(id, tenant_id, customer_id)',
        'payments payments_restricted_line_fkey FOREIGN KEY (restricted_to_line_item_id, restricted_to_invoice_id, tenant_id) REFERENCES invoice_line_items(id, invoice_id, tenant_id)',
        'payments payments_restriction_agency_check CHECK ((((restricted_to_invoice_id IS NULL) OR (payer_class = ''agency''::text)) AND ((restricted_to_line_item_id IS NULL) OR (restricted_to_invoice_id IS NOT NULL))))',
        'tenants tenants_overpayment_handling_check CHECK ((overpayment_handling = ANY (ARRAY[''hold_as_credit''::text, ''refund_automatically''::text])))'];
BEGIN
    SELECT string_agg(d, E'\n  ' ORDER BY d) INTO v_bad
      FROM unnest(c_triggers) d
     WHERE NOT EXISTS (SELECT 1 FROM pg_catalog.pg_trigger g
                        WHERE NOT g.tgisinternal AND g.tgenabled = 'A'
                          AND pg_catalog.pg_get_triggerdef(g.oid) = d);
    IF v_bad IS NOT NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format(E'a v5.4.2-23 guard is missing, changed, or not ENABLE ALWAYS:\n  %s', v_bad),
            ERRCODE = 'invalid_grant_operation';
    END IF;
    SELECT string_agg(d, E'\n  ' ORDER BY d) INTO v_bad
      FROM unnest(c_constraints) d
     WHERE NOT EXISTS (SELECT 1 FROM pg_catalog.pg_constraint k
                        WHERE k.convalidated
                          AND k.conrelid::regclass::text || ' ' || k.conname || ' ' || pg_catalog.pg_get_constraintdef(k.oid) = d);
    IF v_bad IS NOT NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format(E'a v5.4.2-23 constraint is missing, changed or not validated:\n  %s', v_bad),
            ERRCODE = 'invalid_grant_operation';
    END IF;
    -- One credit per approval; r3 (Opus S1, Codex B3, Fable S2): one arrival
    -- entry per source.
    SELECT string_agg(d, E'\n  ' ORDER BY d) INTO v_bad
      FROM unnest(ARRAY[
        'CREATE UNIQUE INDEX customer_credits_one_per_approval ON public.customer_credits USING btree (approval_id) WHERE (approval_id IS NOT NULL)',
        'CREATE UNIQUE INDEX customer_credits_one_live_per_payment ON public.customer_credits USING btree (source_payment_id) WHERE ((source_payment_id IS NOT NULL) AND (status <> ''voided''::text))',
        'CREATE UNIQUE INDEX customer_credits_one_per_reissued_refund ON public.customer_credits USING btree (reissues_refund_id) WHERE (reissues_refund_id IS NOT NULL)',
        'CREATE UNIQUE INDEX account_ledger_payment_arrival_key ON public.account_ledger USING btree (reference_id) WHERE ((reference_type = ''payment''::text) AND (transaction_type = ANY (ARRAY[''payment''::text, ''deposit''::text, ''refund''::text])))',
        'CREATE UNIQUE INDEX account_ledger_credit_arrival_key ON public.account_ledger USING btree (reference_id) WHERE ((reference_type = ''customer_credit''::text) AND (transaction_type = ''credit_issued''::text))']) d
     WHERE NOT EXISTS (SELECT 1 FROM pg_catalog.pg_indexes x JOIN pg_catalog.pg_class i ON i.relname = x.indexname AND i.relnamespace = 'public'::regnamespace
                         JOIN pg_catalog.pg_index k ON k.indexrelid = i.oid
                        WHERE x.schemaname = 'public' AND x.indexdef = d AND k.indisvalid);
    IF v_bad IS NOT NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format(E'a v5.4.2-23 unique index is missing, changed or not valid (one credit per approval, one arrival entry per source):\n  %s', v_bad),
            ERRCODE = 'invalid_grant_operation';
    END IF;
    -- M1: the counters stay gone (a stored copy of the money beside the rows).
    SELECT string_agg(c.table_name || '.' || c.column_name, ', ' ORDER BY 1) INTO v_bad
      FROM information_schema.columns c
     WHERE c.table_schema = 'public'
       AND (c.table_name, c.column_name) IN (('payments', 'applied_amount'), ('payments', 'unapplied_amount'), ('payments', 'deposit_status'),
                                             ('customer_credits', 'applied_amount'), ('customer_credits', 'remaining_amount'),
                                             ('invoices', 'amount_paid'), ('invoices', 'balance'), ('tenants', 'payment_allocation_strategy'));
    IF v_bad IS NOT NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('a counter -23 derives is a column again: %s (M1, v5.4.2-23)', v_bad),
            ERRCODE = 'invalid_grant_operation';
    END IF;
    -- The walks' plan settings, and the application role's reach: no UPDATE
    -- or DELETE on applications or approvals.
    SELECT string_agg(f, ', ' ORDER BY f) INTO v_bad
      FROM unnest(ARRAY['public.ledger_tree_ids(uuid)', 'public.ledger_tree_root(uuid)', 'public.ledger_entry_remaining(uuid)', 'public.enforce_ledger_reversal()']) f
     WHERE (SELECT p.proconfig FROM pg_catalog.pg_proc p WHERE p.oid = f::regprocedure)
           IS DISTINCT FROM ARRAY['search_path=public, pg_temp', 'enable_seqscan=off', 'enable_hashjoin=off', 'enable_mergejoin=off'];
    IF v_bad IS NOT NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('a v5.4.2-23 walk has lost its plan settings: %s', v_bad),
            ERRCODE = 'invalid_grant_operation';
    END IF;
    -- r2 (all three reviewers): a column grant is reach too.
    IF has_table_privilege('tally_app', 'public.invoice_applications', 'UPDATE, DELETE, TRUNCATE')
       OR has_table_privilege('tally_app', 'public.customer_credit_approvals', 'UPDATE, DELETE, TRUNCATE')
       OR has_any_column_privilege('tally_app', 'public.invoice_applications', 'UPDATE')
       OR has_any_column_privilege('tally_app', 'public.customer_credit_approvals', 'UPDATE') THEN
        RAISE EXCEPTION USING
            MESSAGE = 'tally_app can UPDATE (a table or any column), DELETE or TRUNCATE invoice_applications or customer_credit_approvals: both are add-only (R-05, v5.4.2-23)',
            ERRCODE = 'invalid_grant_operation';
    END IF;
    -- r2 (Fable N9): a payment is born pending; the approvals keep their
    -- tenant policy; the cap's entry point is the application role's alone.
    IF (SELECT c.column_default FROM information_schema.columns c
         WHERE c.table_schema = 'public' AND c.table_name = 'payments' AND c.column_name = 'status') IS DISTINCT FROM '''pending''::text' THEN
        RAISE EXCEPTION USING
            MESSAGE = 'payments.status no longer defaults to pending: a payment is born pending (Q1 (a), v5.4.2-23)',
            ERRCODE = 'invalid_grant_operation';
    END IF;
    -- r3 (Codex S2): and no other policy beside it (a second permissive one
    -- would widen it).
    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_policies p
                    WHERE p.schemaname = 'public' AND p.tablename = 'customer_credit_approvals' AND p.policyname = 'tenant_isolation'
                      AND p.cmd = 'ALL' AND p.permissive = 'PERMISSIVE' AND p.roles = '{public}'
                      AND p.qual = '(is_platform_admin() OR (tenant_id = get_user_tenant_id()))' AND p.with_check IS NULL)
       OR (SELECT count(*) FROM pg_catalog.pg_policies p WHERE p.schemaname = 'public' AND p.tablename = 'customer_credit_approvals') <> 1
       OR NOT (SELECT c.relrowsecurity AND c.relforcerowsecurity FROM pg_catalog.pg_class c WHERE c.oid = 'public.customer_credit_approvals'::regclass) THEN
        RAISE EXCEPTION USING
            MESSAGE = 'customer_credit_approvals has lost its tenant_isolation policy or forced row security, or has another policy beside it (v5.4.2-23)',
            ERRCODE = 'invalid_grant_operation';
    END IF;
    -- r3 (Codex S2): and tally_app keeps it (every draw calls it as tally_app).
    IF has_function_privilege('public', 'public.check_cash_source(text, uuid, timestamp with time zone, text, date)', 'EXECUTE')
       OR has_function_privilege('tally_core', 'public.check_cash_source(text, uuid, timestamp with time zone, text, date)', 'EXECUTE')
       OR NOT has_function_privilege('tally_app', 'public.check_cash_source(text, uuid, timestamp with time zone, text, date)', 'EXECUTE') THEN
        RAISE EXCEPTION USING
            MESSAGE = 'check_cash_source is executable beyond tally_app, or not by tally_app (v5.4.2-23)',
            ERRCODE = 'invalid_grant_operation';
    END IF;
END;
$fn$;
COMMENT ON FUNCTION public.assert_cash_guard_invariants() IS
    'v5.4.2-23. Raises unless every guard of v5.4.2-23 — the reversal rule, the application and draw caps, the line-class check at issue, the append-only and stamp triggers of applications and approvals, the freeze on applications, the rewritten payment and credit guards, and the money tables'' retention triggers — exists exactly as defined (PostgreSQL 16''s rendering) and ENABLE ALWAYS; its constraints, the one-credit-per-approval index and (r3) the one-arrival-entry-per-source indexes exist exactly as defined and validated (r3: with the remittance''s freeze and stamp, the refund sign, the credit''s positive amount and the refund''s sign on payments); the counters it derives are not columns; the walks keep their plan settings; tally_app cannot UPDATE (a table or any column), DELETE or TRUNCATE applications or approvals (r2); payments.status defaults to pending; the approvals keep their tenant policy, alone, and forced row security; check_cash_source is tally_app''s alone, and tally_app''s (r3). Checks definitions, not the bodies of the functions they call. Run in the patch tail and in CI.';
REVOKE ALL ON FUNCTION public.assert_cash_guard_invariants() FROM PUBLIC, tally_app, tally_core;

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
-- END PATCH v5.4.2-23
-- ============================================================================

COMMIT;
\endif
