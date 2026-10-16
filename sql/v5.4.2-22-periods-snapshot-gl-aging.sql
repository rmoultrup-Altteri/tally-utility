-- ============================================================================
-- PATCH v5.4.2-22 — wave 2, part 1: accounting periods as freeze boundaries,
--                    the close snapshot, GL code mapping, receivables aging,
--                    write-off recovery
-- ============================================================================
-- Authority:   Ryan, 2026-10-15: "yes, start wave 2"; Kyle's D-2 and D-3
--              (GBM kyle-decisions-2026-08-18-coda-items.md Parts 2 and 3);
--              R-02 (2026-10-15) for the recovery's lineage and cap.
-- Spec:        application/wave2-build-2026-10-15/source-inventory-wave2.md
--              (requirements P, S, G, W). Additive: no existing meaning
--              changes, except that money dated in a closed period is now
--              refused.
--
-- Revision r2 (review round 1: Opus, Fable, Codex all "not yet";
--   tests/v5.4.2-22/review/review-findings-22-r1.md): reversal chains
--   never loop, and aging raises rather than drop an entry (Fable B1,
--   Codex B3); the aging edges are validated everywhere they are recorded,
--   and a snapshot is reproduced with its own stored edges (Opus B1, Codex
--   B1/S1, Fable S1); a row that names a write_off is its recovery, so the
--   cap counts every reversal of it (Opus B2, Fable S2); the close refuses
--   while a row it would freeze is recorded after its instant (Codex B4,
--   Opus S1, Fable S4); a row moved between tenants is checked against both
--   tenants' books (Codex B2); GL precedence is stated and mappings are
--   recorded at the statement's clock (Opus S2, Codex S2); the latest open
--   period may be withdrawn, by status, never deleted (Opus S5, Fable S3); the write-off threshold
--   setting (Codex S4); the invariant pins the constraints and the ledger's
--   immutability (Opus S3, Codex S3, Fable S5).
--
-- Revision r3 (review round 2: Opus and Codex "not yet", Fable "ready";
--   tests/v5.4.2-22/review/review-findings-22-r2.md): the write-off rule
--   runs after the insert, so a row naming a write-off listed later in the
--   same statement is caught (Codex B1, Opus B1a), and the cap is on the net
--   of the write-off's whole same-customer tree, between 0 and the amount
--   written off, so a row naming a recovery is counted and a reversed
--   recovery frees the cap again (Opus B1b, Fable S1); the lineage walk
--   fails closed past 1000 entries (Codex B2); the close takes its aging
--   edges from the tenant's row, not the app-written history (Opus S1); a
--   withdrawal names its user (Opus S2); the invariant pins the history's
--   known-key CHECK and the ledger's lineage constraints (Codex S2, Fable N3,
--   Opus N4); comments and messages corrected (Codex S1, Opus N2/N3, Fable
--   N1/N7). Before the freeze, a mutation run showed the cap's two walks
--   could scan the customer's ledger at every step (the planner chose the
--   tenant or customer index over the id and reversal links on an unanalyzed
--   table): each step now joins on the link alone and tests the customer
--   apart from it, so a 400-deep tree in one statement takes about 2 s, not
--   minutes.
--
-- Revision r4 (review round 3: Opus and Codex "not yet", Fable "ready";
--   tests/v5.4.2-22/review/review-findings-22-r3.md): the cap holds at every
--   date of the tree, and a row under a write-off is dated on or after the
--   entry it names, so a later-dated reversal makes no room for an earlier
--   recovery (Opus B1); a row recorded before a row already in its tree is
--   refused for retry, so the cap holds at every recorded instant too; a
--   change of the aging edges takes the close head FOR SHARE, so the close
--   ages by the edges in force at its instant (Codex B1, Opus N2); the cap's
--   walk picks the write-offs from the walk itself, and both walks run with
--   sequential scans, hash and merge joins off, since on a ledger the
--   planner believed empty they scanned it at every step (Opus S1; a
--   battery run took 30 s at R10g); the lock-order paragraph states the
--   deadlock between writers under two write-offs (Fable S1, Codex S1,
--   Opus N1).
--
-- Revision r5 (review round 4: Opus and Fable "ready", Codex "not yet";
--   tests/v5.4.2-22/review/review-findings-22-r4.md): a row in a
--   write-off's tree, the write-off included, is recorded at a finite time
--   already reached, so an owner's history row recorded in the future
--   cannot strand the tree behind the retry (Codex B1); the invariant pins
--   the walks' plan settings (Fable S2, Opus); the lock-order paragraph
--   states the deadlock between the close's snapshot keys and an edges
--   change that holds the tenant row (Opus S1, Fable S1); history loads
--   under a write-off post one statement per recorded instant (Codex S1,
--   R12).
--
-- Revision r6 (review round 5: Opus, Fable and Codex all "ready";
--   tests/v5.4.2-22/review/review-findings-22-r5.md): the lock-order
--   paragraph states every lock the close takes and every deadlock they can
--   make — the closing user's row beside the tenant row, any write that
--   takes the head as the other side, and a transaction that posts and then
--   closes (Opus S1, Fable S1/S2, Codex S1); a row with a chosen recorded
--   time before a row already in its tree is refused for good (23514), not
--   for a retry that cannot succeed (Opus N1); messages and the function's
--   comment name the non-finite case and the write-off itself (Opus N2,
--   Fable N1, Codex S2).
--
-- Revision r7 (review round 6: Opus and Fable "ready", Codex not run (usage
--   limit); tests/v5.4.2-22/review/review-findings-22-r6.md): the lock-order
--   paragraph states the rule the close's deadlocks follow (its four rows
--   in order; holding a later one and asking for an earlier one), instead
--   of a list that both reviewers showed incomplete — the period row locked
--   then a write, the tenant row then the closing user's row, either then a
--   withdrawal (Opus S1, Fable S1); R12 says a row stamped at its start can
--   still meet a row its own transaction recorded later (Opus S2).
--
-- Revision r8 (review round 7: Opus and Fable "ready", Codex waived by Ryan;
--   tests/v5.4.2-22/review/review-findings-22-r7.md): comments only. The
--   rule counts waits through other transactions, promises no list of
--   shapes complete, and says every writer retries 40P01 (Opus S2, Fable
--   N1); the head and the period can be locked by a bare SELECT ... FOR
--   UPDATE (Fable S1, Opus N); one UPDATE of tenants that changes the edges
--   and names slug can deadlock by itself (Opus S1).
--
-- ----------------------------------------------------------------------------
-- What changes
-- ----------------------------------------------------------------------------
--   Periods (P; D-2 "the period is a freeze boundary, not a reporting grain")
--   * accounting_periods: a tenant's periods, first and last day, open or
--     closed. No overlaps (EXCLUDE) and no gaps: a new period starts the day
--     after the tenant's latest (P1). Every status value is producible:
--     every period is born open; close_accounting_period() closes it; nothing
--     reopens it. closed_at and closed_by are the database's. The tenant's
--     latest period, while open, may be withdrawn (a mistyped one, r2): it
--     stays on record, status withdrawn, and its dates are free again.
--   * accounting_close_heads: one row per tenant, "the books are closed
--     through" a date. Created for every tenant (backfill, and on tenant
--     INSERT), moved forward only by the close.
--   * The freeze (P2): a row of account_ledger, payments or customer_credits
--     dated on or before the tenant's closed-through date is refused, at
--     INSERT and when its date is changed (to or from such a date), and a
--     row moved between tenants is checked against each tenant's (r2). Since
--     periods close in order and without gaps, that is "inside a closed
--     period, or before the first period once it is closed": onboarding
--     history is loaded before the first close. GL mappings obey the same
--     date (G4 below).
--   * The close (P3): close_accounting_period(period, unbilled revenue,
--     basis) checks the period is open, has ended everywhere (its last day
--     is over at UTC-12), and is the next in order; writes the snapshot;
--     moves the head; closes the period. A supervisor's act: closing is
--     irreversible (memory "guard the act").
--
--   The close snapshot (S)
--   * accounting_period_snapshots (one per closed period) and
--     accounting_period_snapshot_lines (activity by ledger type; aging by
--     bucket), append-only, written only by the close. The figures are
--     computed by the close from the ledger at one recorded instant
--     (recorded_at), not passed in: opening balance, activity, closing
--     balance, entry count, aging at the period's last day by the edges on
--     the tenant's row at that instant (r3), stored with it.
--   * Reproducible: receivables_aging_as_of(tenant, period_end, recorded_at,
--     aging_bucket_days) and the ledger sums at (dates, recorded_at) return
--     the snapshot's figures afterwards, because nothing dated on or before
--     period_end can be written once the close holds the head (lock order
--     below), and the close refuses while such a row is recorded after its
--     instant (r2).
--   * Unbilled revenue is a reported figure on the snapshot, never a ledger
--     row (D-2 clarification 1). It is the core's estimate, supplied to the
--     close with its basis, or absent.
--
--   GL code mapping (G; CI-048, Appendix A-10)
--   * gl_account_mappings: tenant configuration, dated (effective_from,
--     effective_to) and recorded (created_at, closed_at). The key is the
--     charge (source and code), customer class, service territory place and
--     tax jurisdiction place; each part NULL is a wildcard. The values are
--     the GL account, subaccount, USOA code and cost centre.
--   * Never edited: the only change is a stamped close (effective_to set
--     once). A row may not start, nor be closed, on or before the tenant's
--     closed-through date: a closed period's mapping never changes (G4).
--   * gl_mapping_as_of(...): the row of highest precedence in force at the
--     date as recorded at the instant — charge, then customer class, then
--     territory, then tax jurisdiction (r2); no row is NULL. There is no
--     posting table: the export (the core) refuses a line with no mapping
--     (D-2: not a GL). A mapping is recorded at its statement's clock.
--
--   Receivables aging and write-off recovery (W; D-3, CI-076)
--   * receivables_aging_as_of(tenant, on, recorded): per customer, the open
--     balance by age bucket, with the customer's status (D-3) and the
--     location of its last located ledger entry. Each original entry is
--     netted with its customer's reversals that name it (R-02 lineage); a
--     reversal chain never loops (r2); what is left of
--     the balance is aged newest first, which is the oldest-first rule of
--     payment (K-05) seen from the debt's side. A credit balance is one row
--     with no bucket.
--   * tenants.receivables_aging_bucket_days (default 30, 60, 90, 120): the
--     bucket edges in days, recorded in tenant_configuration_history (every
--     recorded value validated, r2) and read as of the recorded instant, or
--     passed explicitly.
--   * tenants.write_off_threshold_days (r2; W3): recorded, NULL when unset.
--   * account_ledger.transaction_type gains write_off_recovery: it names the
--     write_off it recovers (same tenant and customer), with a reason, and
--     has the opposite sign. Any row that names a write_off is a
--     write_off_recovery (r2). R-02's cap (r3): everything aging nets into a
--     write-off — its whole same-customer tree, any depth and type — nets
--     to between 0 and the amount written off; checked after the statement's
--     rows are all in, serialised on the write-off, READ COMMITTED only.
--     r4: at every date of the tree (rows dated on or before it), as aging
--     and the close net it; a row under a write-off is dated on or after
--     the entry it names, and is not recorded before a row already in the
--     tree (the writer retries, 40001).
--
--   The seal
--   * tally_close owns close_accounting_period(): NOLOGIN, no BYPASSRLS, no
--     members, an exact grant list (memory "seal pattern").
--     assert_seal_role_invariants() is re-issued with the third role, and
--     tally_void gains SELECT and the lock column on accounting_close_heads
--     (the freeze locks the head when the void posts its reversal).
--   * assert_periods_guard_invariants(): every -22 guard and the ledger's
--     immutability triggers exist exactly as defined and ENABLE ALWAYS, and
--     the -22 constraints exactly as defined (r2).
--
-- ----------------------------------------------------------------------------
-- Lock order and isolation
-- ----------------------------------------------------------------------------
--   A money write takes FOR SHARE on its tenant's head; the close takes the
--   head FOR UPDATE, then the period FOR UPDATE, then reads the ledger. A
--   write in flight therefore finishes before the close reads; a write that
--   arrives later waits for the close and is then refused (READ COMMITTED
--   re-reads the head; an older snapshot fails with a serialisation error).
--   No isolation pin on writers. The close itself runs at READ COMMITTED
--   only (it must see what the writers it waited for committed).
--   A row moved between tenants takes both heads FOR SHARE in tenant id
--   order. A period INSERT or withdrawal and a recovery run at READ
--   COMMITTED only, behind an advisory lock (tenant's period chain; the
--   recovered write-off).
--   Shared locks on one row per tenant: writers do not wait for each other
--   at the head (r6: they may at the advisory locks below).
--   A row under a write-off takes the advisory lock of each write-off above
--   it, in id order, after its tenant's head (r3). The order holds within
--   one row only: rows fire in row order, and a transaction keeps the locks
--   of its earlier statements. Two transactions posting under the same two
--   write-offs in opposite orders can deadlock; PostgreSQL aborts one and
--   nothing is written by it (Fable S1, Codex S1, Opus N1, r4). Writers
--   retry a deadlock (40P01) and a recorded-order refusal (40001).
--   A change of the aging edges takes its tenant's head FOR SHARE, as a
--   money write and a GL mapping write do (r4).
--   The close's rows (r6; r7, Opus S1 and Fable S1, round 6: a list of
--   cycles proved incomplete twice, so this is the rule they follow). The
--   close takes, in this order:
--     1. the head, FOR UPDATE;
--     2. the period, FOR UPDATE;
--     3. the closing user's users row, FOR KEY SHARE (closed_by on the
--        period and the snapshot);
--     4. when it writes snapshot lines, the tenant row, FOR KEY SHARE (their
--        tenant key).
--   A transaction that holds one of these rows in a mode that conflicts
--   with the close's, and then waits — directly, or through other
--   transactions it waits on — for a row the close takes earlier, or holds
--   the head FOR SHARE and then closes, asking for it FOR UPDATE, can
--   deadlock with a close. PostgreSQL aborts one side, which may be a third
--   transaction that did nothing named here, and nothing is written by it.
--   r8 (Opus S2, Fable N1, round 7): no list of shapes is promised
--   complete; every writer retries 40P01. What takes the rows:
--   - the head: FOR SHARE by every money write, GL mapping write and edges
--     change; FOR UPDATE by a close, and by a bare SELECT ... FOR UPDATE or
--     FOR NO KEY UPDATE from tally_app or tally_void (a column UPDATE grant
--     is enough);
--   - the period: FOR UPDATE by a withdrawal; any SELECT ... FOR mode from
--     tally_app (it has UPDATE on status);
--   - a users or tenant row FOR UPDATE: SELECT ... FOR UPDATE, a DELETE, or
--     an UPDATE whose SET names a column under a unique index, changed or
--     not (users: id, tenant_id, cognito_sub; tenants: id, slug).
--   Shapes, each executed in review: a write then a close (CR16); the tenant
--   row then a money write (CR17); the closing user's row then a GL mapping
--   write (CR18); the period row FOR SHARE then a money write (CR19); the
--   tenant row then the closing user's row (CR20); a withdrawal then a write
--   (Opus N1, r3); the tenant or the user's row then a withdrawal. The
--   reverse orders wait for the close and do not deadlock (the users row,
--   then the tenant row; a write, then a key change: both executed). One
--   statement can deadlock by itself: an UPDATE of tenants that changes the
--   edges and names a unique column (an ORM full-row save, slug unchanged)
--   holds the tenant row FOR UPDATE, then takes the head (Opus S1, r8).
--   So close, withdraw, and change tenant and user rows each in a
--   transaction of its own, and change the edges in an UPDATE that names
--   no unique column.
--   The close takes no advisory lock and no customer, GL mapping or other
--   period row; a period insert never takes the head. Other cycles come
--   from two transactions taking the writers' advisory locks (a
--   write-off's, a tenant's period chain) in opposite orders: writers under
--   two write-offs (above), or a period insert or withdrawal and a posting
--   under a write-off. Each in a transaction of its own avoids them too.
--
-- ----------------------------------------------------------------------------
-- Residuals (left on purpose)
-- ----------------------------------------------------------------------------
--   R1. The freeze covers the ledger, payments and customer credits by their
--       date. Other dated money rows (adhoc charges, deposits' events) reach
--       the books through the ledger and are frozen there.
--   R2. A payment whose status moves (pending to posted) without a change of
--       date is not refused in a closed period: a status move writes its own
--       ledger row, dated when it happens. -23 binds status moves to rows.
--   R3. Aging is customer-level, balance-forward over the ledger. Per-bill
--       and per-charge aging follows the applications -23 adds.
--   R4. The customer's status on the aging is as recorded at the recorded
--       instant: customer status has transaction time only.
--   R5. "Last service location" is the location of the customer's latest
--       located ledger entry: location_occupancies (D-3) is not built.
--   R6. The charge vocabularies in gl_account_mappings' CHECK repeat the
--       three source tables' CHECKs; a new charge type is added to both.
--   R7. A GL mapping's places are not checked for their kind (a territory
--       place could be any place).
--   R8. The general reversal rules (every reversal names its entry,
--       opposite sign, capped) are -23's (X); -22 caps the net of a
--       write-off's tree at every date and recorded instant (r4) and orders
--       its dates, and forbids loops and chains past 1000 entries for every
--       reversal. Rows outside a write-off's tree may still be dated before
--       the entry they name.
--   R9. A tenant with no aging setting recorded at the instant cannot be
--       aged (raises); tenants that existed before -22 get theirs at the
--       patch's time, so aging recorded before it is unknowable.
--  R10. The configuration history accepts 'manual' and 'backfill' rows with
--       a chosen effective_from (the base design, every key). The
--       three-argument aging and receivables_aging_bucket_days_as_of() read
--       that history, so such a row changes what they return for an earlier
--       instant. The close does not read it (r3), and a snapshot is
--       reproduced with its stored edges. A change of the edges that waited
--       for a close is recorded with its own transaction's start, which can
--       precede the close's instant (r4): the history then dates it before a
--       close that did not use it. The snapshot's stored edges are the record.
--  R11. The walks' plans are pinned by the function's settings, not proved
--       for every size: measured, a 300-deep tree in one statement in about
--       1.3 s, and 5,000 reversals after 200,000 rows loaded in the same
--       transaction in 0.8 s (r4).
--  R12. A history load under a write-off posts one statement per recorded
--       instant, in recorded order: rows of one statement see each other,
--       so a row recorded before a sibling already in the tree is refused
--       though the load is valid (Codex S1, r5). A row with a chosen
--       recorded time (not its transaction's start) before a row already in
--       the tree is refused for good, 23514: no retry can change its time
--       (Opus N1, r6). Only a row stamped at its transaction's start gets
--       40001, and its retry is stamped later — unless the later row is one
--       its own transaction recorded at a chosen time (the owner only: an
--       app writer's rows are all stamped at its start); then the retry
--       meets it again (Opus S2, r7).
--
-- Tests. battery-22 (one row per requirement), races/close-22.sh,
--   mutations-22.py.
--   assert_periods_guard_invariants() and assert_seal_role_invariants() run
--   in the tail and in CI.
--
-- PRECONDITION. v5.4.2-21 applied (tu.sql). Applied by a superuser, under
--   READ COMMITTED. A second run finds accounting_periods and skips the whole
--   patch (psql's \if): apply it with psql.
-- ============================================================================

SELECT to_regclass('public.accounting_periods') IS NOT NULL AS already \gset
\if :already
DO $$ BEGIN RAISE NOTICE 'v5.4.2-22: already applied (accounting_periods exists); nothing to do'; END $$;
\else
BEGIN;


-- ----------------------------------------------------------------------------
-- 1. The close role
-- ----------------------------------------------------------------------------
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = 'tally_close') THEN
        CREATE ROLE tally_close NOLOGIN NOSUPERUSER NOBYPASSRLS NOCREATEROLE NOCREATEDB NOREPLICATION;
    END IF;
    EXECUTE format('REVOKE TEMP ON DATABASE %I FROM PUBLIC', pg_catalog.current_database());
END $$;
REVOKE ALL ON SCHEMA public FROM tally_close;
GRANT USAGE ON SCHEMA public TO tally_close;
GRANT EXECUTE ON FUNCTION public.get_user_tenant_id(), public.is_platform_admin() TO tally_close;


-- ----------------------------------------------------------------------------
-- 2. The head: the books are closed through a date (P2, P3)
-- ----------------------------------------------------------------------------
CREATE TABLE public.accounting_close_heads (
    tenant_id       uuid NOT NULL,
    closed_through  date,
    updated_at      timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT accounting_close_heads_pkey PRIMARY KEY (tenant_id),
    CONSTRAINT accounting_close_heads_tenant_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id)
);
ALTER TABLE public.accounting_close_heads ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.accounting_close_heads FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON public.accounting_close_heads USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));
COMMENT ON TABLE public.accounting_close_heads IS
    'v5.4.2-22 (D-2, P2/P3). One row per tenant: the books are closed through closed_through (NULL: nothing closed). Born NULL with the tenant; moved forward only by close_accounting_period() (tally_close). Every money write takes this row FOR SHARE, the close takes it FOR UPDATE: the lock that keeps a write from landing in a period while it closes. updated_at is the column the writers'' lock needs a privilege on; no one but the close may change it.';

CREATE OR REPLACE FUNCTION public.enforce_accounting_close_head() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
BEGIN
    IF TG_OP IN ('DELETE', 'TRUNCATE') THEN
        RAISE EXCEPTION USING
            MESSAGE = 'accounting_close_heads rows are never deleted: the closed-through date is the freeze every money write reads (v5.4.2-22)',
            ERRCODE = 'restrict_violation';
    END IF;
    IF TG_OP = 'INSERT' THEN
        IF NEW.closed_through IS NOT NULL THEN
            RAISE EXCEPTION USING
                MESSAGE = format('tenant %s: a close head is born with nothing closed; only close_accounting_period() moves it (v5.4.2-22)', NEW.tenant_id),
                ERRCODE = 'check_violation';
        END IF;
        NEW.updated_at := now();
        RETURN NEW;
    END IF;
    IF current_user <> 'tally_close'
       OR NEW.tenant_id IS DISTINCT FROM OLD.tenant_id
       OR NEW.closed_through IS NULL
       OR (OLD.closed_through IS NOT NULL AND NEW.closed_through <= OLD.closed_through) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('tenant %s: the closed-through date moves only forward, and only through close_accounting_period() (v5.4.2-22)', OLD.tenant_id),
            ERRCODE = 'restrict_violation';
    END IF;
    RETURN NEW;
END;
$$;
COMMENT ON FUNCTION public.enforce_accounting_close_head() IS
    'v5.4.2-22. accounting_close_heads: born with closed_through NULL; changed only by tally_close (the owner of the running close_accounting_period()), only forward; never deleted or truncated.';
CREATE TRIGGER enforce_accounting_close_head BEFORE INSERT OR DELETE OR UPDATE ON public.accounting_close_heads
    FOR EACH ROW EXECUTE FUNCTION public.enforce_accounting_close_head();
ALTER TABLE public.accounting_close_heads ENABLE ALWAYS TRIGGER enforce_accounting_close_head;
CREATE TRIGGER no_truncate BEFORE TRUNCATE ON public.accounting_close_heads
    FOR EACH STATEMENT EXECUTE FUNCTION public.enforce_accounting_close_head();
ALTER TABLE public.accounting_close_heads ENABLE ALWAYS TRIGGER no_truncate;

-- Every tenant has its head: those that exist now, and each new one.
INSERT INTO public.accounting_close_heads (tenant_id) SELECT t.id FROM public.tenants t;

CREATE OR REPLACE FUNCTION public.create_accounting_close_head() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
BEGIN
    INSERT INTO public.accounting_close_heads (tenant_id) VALUES (NEW.id);
    RETURN NULL;
END;
$$;
COMMENT ON FUNCTION public.create_accounting_close_head() IS
    'v5.4.2-22. AFTER INSERT on tenants: the new tenant''s close head, nothing closed. A tenant without a head could take no money write (the freeze requires it).';
CREATE TRIGGER create_accounting_close_head AFTER INSERT ON public.tenants
    FOR EACH ROW EXECUTE FUNCTION public.create_accounting_close_head();
ALTER TABLE public.tenants ENABLE ALWAYS TRIGGER create_accounting_close_head;

REVOKE ALL ON public.accounting_close_heads FROM PUBLIC, tally_app, tally_core;
GRANT SELECT, INSERT ON public.accounting_close_heads TO tally_app;
GRANT UPDATE (updated_at) ON public.accounting_close_heads TO tally_app, tally_void;
GRANT SELECT ON public.accounting_close_heads TO tally_void, tally_core, tally_close;
GRANT UPDATE (closed_through, updated_at) ON public.accounting_close_heads TO tally_close;


-- ----------------------------------------------------------------------------
-- 3. Accounting periods (P1)
-- ----------------------------------------------------------------------------
CREATE TABLE public.accounting_periods (
    id            uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id     uuid NOT NULL,
    period_start  date NOT NULL,
    period_end    date NOT NULL,
    status        text DEFAULT 'open'::text NOT NULL,
    created_at    timestamp with time zone DEFAULT now() NOT NULL,
    created_by    uuid,
    closed_at     timestamp with time zone,
    closed_by     uuid,
    withdrawn_at  timestamp with time zone,
    withdrawn_by  uuid,
    CONSTRAINT accounting_periods_pkey PRIMARY KEY (id),
    CONSTRAINT accounting_periods_id_tenant_key UNIQUE (id, tenant_id),
    CONSTRAINT accounting_periods_tenant_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id),
    CONSTRAINT accounting_periods_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id),
    CONSTRAINT accounting_periods_closed_by_fkey FOREIGN KEY (closed_by) REFERENCES public.users(id),
    CONSTRAINT accounting_periods_withdrawn_by_fkey FOREIGN KEY (withdrawn_by) REFERENCES public.users(id),
    CONSTRAINT accounting_periods_status_check CHECK (status = ANY (ARRAY['open'::text, 'closed'::text, 'withdrawn'::text])),
    CONSTRAINT accounting_periods_withdrawn_stamp_check CHECK ((status = 'withdrawn'::text) = (withdrawn_at IS NOT NULL)),
    CONSTRAINT accounting_periods_range_check CHECK (period_end >= period_start),
    CONSTRAINT accounting_periods_closed_stamp_check CHECK ((status = 'closed'::text) = (closed_at IS NOT NULL)),
    CONSTRAINT accounting_periods_no_overlap
        EXCLUDE USING gist (tenant_id WITH =, daterange(period_start, period_end, '[]'::text) WITH &&)
        WHERE (status <> 'withdrawn'::text)
);
CREATE INDEX idx_accounting_periods_tenant_start ON public.accounting_periods USING btree (tenant_id, period_start);
ALTER TABLE public.accounting_periods ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.accounting_periods FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON public.accounting_periods USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));
COMMENT ON TABLE public.accounting_periods IS
    'v5.4.2-22 (D-2, P1). A tenant''s accounting periods: freeze boundaries, not a reporting grain (reports run on transaction_date over any window). First and last day inclusive; no overlap (EXCLUDE) and no gap (a new period starts the day after the tenant''s latest). Born open; closed only by close_accounting_period(), which stamps closed_at and closed_by and writes the snapshot; a closed period never reopens — a correction posts into an open period. The tenant''s latest period, while open, may be withdrawn (a mistyped one, r2): status withdrawn, stamped, kept on record, its dates free for a correct period. Never deleted.';
COMMENT ON COLUMN public.accounting_periods.withdrawn_at IS 'v5.4.2-22 r2. When a mistyped open period was withdrawn (the database''s time); withdrawn_by the session''s user. A withdrawn period takes part in neither the no-gap nor the no-overlap rule.';
COMMENT ON COLUMN public.accounting_periods.period_end IS 'The period''s last day, inclusive.';
COMMENT ON COLUMN public.accounting_periods.closed_at IS 'The close''s recorded instant (the snapshot''s recorded_at). Written only by the close.';

CREATE OR REPLACE FUNCTION public.enforce_accounting_period() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_last     date;
    c_close    CONSTANT text[] := ARRAY['status', 'closed_at', 'closed_by'];
    c_withdraw CONSTANT text[] := ARRAY['status', 'withdrawn_at', 'withdrawn_by'];
BEGIN
    IF TG_OP IN ('DELETE', 'TRUNCATE') THEN
        RAISE EXCEPTION USING
            MESSAGE = 'accounting_periods rows are never deleted: a snapshot and the freeze stand on them; a mistyped open period is withdrawn (v5.4.2-22)',
            ERRCODE = 'restrict_violation';
    END IF;
    IF TG_OP = 'INSERT' THEN
        IF pg_catalog.current_setting('transaction_isolation') <> 'read committed' THEN
            RAISE EXCEPTION USING
                MESSAGE = format('an accounting period is created at READ COMMITTED (this transaction is %s): the no-gap check must see the latest period committed while it waited (v5.4.2-22)', pg_catalog.current_setting('transaction_isolation')),
                ERRCODE = 'invalid_transaction_state';
        END IF;
        PERFORM pg_advisory_xact_lock(hashtextextended('accounting_periods:' || NEW.tenant_id::text, 0));
        IF NEW.status IS DISTINCT FROM 'open' OR NEW.closed_at IS NOT NULL OR NEW.closed_by IS NOT NULL
           OR NEW.withdrawn_at IS NOT NULL OR NEW.withdrawn_by IS NOT NULL THEN
            RAISE EXCEPTION USING
                MESSAGE = format('tenant %s: an accounting period is born open; only close_accounting_period() closes it (v5.4.2-22)', NEW.tenant_id),
                ERRCODE = 'check_violation';
        END IF;
        SELECT max(p.period_end) INTO v_last FROM public.accounting_periods p WHERE p.tenant_id = NEW.tenant_id AND p.status <> 'withdrawn';
        IF v_last IS NOT NULL AND NEW.period_start IS DISTINCT FROM v_last + 1 THEN
            RAISE EXCEPTION USING
                MESSAGE = format('tenant %s: the next accounting period starts on %s, the day after the latest ends — not %s (no gaps, v5.4.2-22)', NEW.tenant_id, v_last + 1, NEW.period_start),
                ERRCODE = 'check_violation';
        END IF;
        NEW.created_at := now();
        NEW.created_by := nullif(pg_catalog.current_setting('app.user_id', true), '')::uuid;
        RETURN NEW;
    END IF;
    -- The one change: the close, made by tally_close inside the close.
    IF current_user = 'tally_close'
       AND OLD.status = 'open' AND NEW.status = 'closed' AND NEW.closed_at IS NOT NULL AND NEW.closed_by IS NOT NULL
       AND (to_jsonb(NEW) - c_close) = (to_jsonb(OLD) - c_close) THEN
        RETURN NEW;
    END IF;
    -- r2 (Opus S5, Fable S3): a mistyped period is withdrawn while it is the
    -- tenant's latest and still open. It stays on record; its dates are free.
    IF OLD.status = 'open' AND NEW.status = 'withdrawn'
       AND (to_jsonb(NEW) - c_withdraw) = (to_jsonb(OLD) - c_withdraw) THEN
        IF pg_catalog.current_setting('transaction_isolation') <> 'read committed' THEN
            RAISE EXCEPTION USING
                MESSAGE = format('an accounting period is withdrawn at READ COMMITTED (this transaction is %s) (v5.4.2-22)', pg_catalog.current_setting('transaction_isolation')),
                ERRCODE = 'invalid_transaction_state';
        END IF;
        PERFORM pg_advisory_xact_lock(hashtextextended('accounting_periods:' || OLD.tenant_id::text, 0));
        IF EXISTS (SELECT 1 FROM public.accounting_periods p
                    WHERE p.tenant_id = OLD.tenant_id AND p.status <> 'withdrawn' AND p.period_start > OLD.period_start) THEN
            RAISE EXCEPTION USING
                MESSAGE = format('accounting period %s: only the tenant''s latest period, while open, may be withdrawn (v5.4.2-22)', OLD.id),
                ERRCODE = 'restrict_violation';
        END IF;
        NEW.withdrawn_at := pg_catalog.clock_timestamp();
        NEW.withdrawn_by := nullif(pg_catalog.current_setting('app.user_id', true), '')::uuid;
        -- r3 (Opus S2): a withdrawal names who made it.
        IF NEW.withdrawn_by IS NULL THEN
            RAISE EXCEPTION USING
                MESSAGE = format('accounting period %s: a withdrawal names its user (app.user_id) (v5.4.2-22)', OLD.id),
                ERRCODE = 'not_null_violation';
        END IF;
        RETURN NEW;
    END IF;
    RAISE EXCEPTION USING
        MESSAGE = format('accounting period %s: a period is never edited; it closes only through close_accounting_period(), never reopens, and only the latest open one may be withdrawn (v5.4.2-22)', OLD.id),
        ERRCODE = 'restrict_violation';
END;
$$;
COMMENT ON FUNCTION public.enforce_accounting_period() IS
    'v5.4.2-22 (P1). INSERT: at READ COMMITTED, behind the tenant''s period-chain advisory lock; born open; starts the day after the tenant''s latest period (no gaps; EXCLUDE refuses overlaps); created_at and created_by stamped. UPDATE: only the close (status open -> closed with closed_at and closed_by, nothing else) by tally_close; or a withdrawal (r2): status open -> withdrawn, nothing else, of the tenant''s latest non-withdrawn period, at READ COMMITTED behind the same lock, withdrawn_at and withdrawn_by stamped (app.user_id required, r3). Never deleted or truncated.';
CREATE TRIGGER enforce_accounting_period BEFORE INSERT OR DELETE OR UPDATE ON public.accounting_periods
    FOR EACH ROW EXECUTE FUNCTION public.enforce_accounting_period();
ALTER TABLE public.accounting_periods ENABLE ALWAYS TRIGGER enforce_accounting_period;
CREATE TRIGGER no_truncate BEFORE TRUNCATE ON public.accounting_periods
    FOR EACH STATEMENT EXECUTE FUNCTION public.enforce_accounting_period();
ALTER TABLE public.accounting_periods ENABLE ALWAYS TRIGGER no_truncate;

REVOKE ALL ON public.accounting_periods FROM PUBLIC, tally_app, tally_core;
GRANT SELECT, INSERT ON public.accounting_periods TO tally_app;
GRANT UPDATE (status, withdrawn_at, withdrawn_by) ON public.accounting_periods TO tally_app;
GRANT SELECT ON public.accounting_periods TO tally_core, tally_close;
GRANT UPDATE (status, closed_at, closed_by) ON public.accounting_periods TO tally_close;


-- ----------------------------------------------------------------------------
-- 4. The freeze (P2)
-- ----------------------------------------------------------------------------
-- TG_ARGV[0]: the row's date column. Invoker rights: the writer locks its own
-- tenant's head, so tally_app and tally_void hold SELECT and UPDATE on the
-- lock column (FOR SHARE needs an UPDATE privilege); the head's guard refuses
-- the update itself.
CREATE OR REPLACE FUNCTION public.enforce_accounting_freeze() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_new         date := (to_jsonb(NEW) ->> TG_ARGV[0])::date;
    v_old         date;
    v_through     date;
    v_old_through date;
BEGIN
    IF TG_OP = 'UPDATE' THEN
        v_old := (to_jsonb(OLD) ->> TG_ARGV[0])::date;
        IF v_new IS NOT DISTINCT FROM v_old AND NEW.tenant_id IS NOT DISTINCT FROM OLD.tenant_id THEN
            RETURN NEW;
        END IF;
        -- r2 (Codex B2): a row moved between tenants leaves the old tenant's
        -- books; both heads are locked, in id order, and the old date is
        -- checked against the old tenant's.
        IF OLD.tenant_id IS DISTINCT FROM NEW.tenant_id THEN
            PERFORM 1 FROM public.accounting_close_heads h
              WHERE h.tenant_id IN (OLD.tenant_id, NEW.tenant_id) ORDER BY h.tenant_id FOR SHARE;
            SELECT h.closed_through INTO v_old_through FROM public.accounting_close_heads h WHERE h.tenant_id = OLD.tenant_id;
            IF NOT FOUND THEN
                RAISE EXCEPTION USING
                    MESSAGE = format('%s: tenant %s has no close head visible to this session (v5.4.2-22)', TG_TABLE_NAME, OLD.tenant_id),
                    ERRCODE = 'insufficient_privilege';
            END IF;
        END IF;
    END IF;
    SELECT h.closed_through INTO v_through
      FROM public.accounting_close_heads h
     WHERE h.tenant_id = NEW.tenant_id
       FOR SHARE;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING
            MESSAGE = format('%s: tenant %s has no close head visible to this session (v5.4.2-22)', TG_TABLE_NAME, NEW.tenant_id),
            ERRCODE = 'insufficient_privilege';
    END IF;
    IF TG_OP = 'UPDATE' AND OLD.tenant_id IS NOT DISTINCT FROM NEW.tenant_id THEN
        v_old_through := v_through;
    END IF;
    IF v_new <= v_through OR v_old <= v_old_through THEN
        RAISE EXCEPTION USING
            MESSAGE = format('%s: dated %s, on or before %s, the end of the tenant''s last closed accounting period — a closed period is frozen; post the correction into an open period (D-2, v5.4.2-22)',
                             TG_TABLE_NAME, CASE WHEN v_new <= v_through THEN v_new ELSE v_old END,
                             CASE WHEN v_new <= v_through THEN v_through ELSE v_old_through END),
            ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$;
COMMENT ON FUNCTION public.enforce_accounting_freeze() IS
    'v5.4.2-22 (D-2, P2). BEFORE INSERT (and UPDATE of the date or tenant) on account_ledger, payments and customer_credits: takes the tenant''s close head FOR SHARE and refuses a row dated on or before closed_through, or moved from or to such a date; a row moved between tenants locks both heads in id order and is checked against each (r2). The share lock is what the close waits on.';

CREATE TRIGGER a_enforce_accounting_freeze BEFORE INSERT ON public.account_ledger
    FOR EACH ROW EXECUTE FUNCTION public.enforce_accounting_freeze('transaction_date');
ALTER TABLE public.account_ledger ENABLE ALWAYS TRIGGER a_enforce_accounting_freeze;
CREATE TRIGGER a_enforce_accounting_freeze BEFORE INSERT OR UPDATE OF payment_date, tenant_id ON public.payments
    FOR EACH ROW EXECUTE FUNCTION public.enforce_accounting_freeze('payment_date');
ALTER TABLE public.payments ENABLE ALWAYS TRIGGER a_enforce_accounting_freeze;
CREATE TRIGGER a_enforce_accounting_freeze BEFORE INSERT OR UPDATE OF issued_date, tenant_id ON public.customer_credits
    FOR EACH ROW EXECUTE FUNCTION public.enforce_accounting_freeze('issued_date');
ALTER TABLE public.customer_credits ENABLE ALWAYS TRIGGER a_enforce_accounting_freeze;


-- ----------------------------------------------------------------------------
-- 5. Write-off recovery (W3)
-- ----------------------------------------------------------------------------
ALTER TABLE public.account_ledger DROP CONSTRAINT account_ledger_transaction_type_check;
ALTER TABLE public.account_ledger ADD CONSTRAINT account_ledger_transaction_type_check
    CHECK ((transaction_type = ANY (ARRAY['charge'::text, 'payment'::text, 'adjustment'::text, 'credit_issued'::text, 'credit_applied'::text,
    'late_fee'::text, 'deposit'::text, 'refund'::text, 'write_off'::text, 'transfer'::text, 'nsf'::text, 'escheat'::text, 'donation'::text,
    'void_reversal'::text, 'deposit_interest'::text, 'write_off_recovery'::text])));
ALTER TABLE public.account_ledger ADD CONSTRAINT account_ledger_recovery_lineage_check
    CHECK (transaction_type <> 'write_off_recovery'::text
           OR (reverses_ledger_entry_id IS NOT NULL AND COALESCE(reversal_reason ~ '[[:alnum:]]'::text, false)));

-- r3 (Codex B1, Opus B1, Fable S1): the rule runs AFTER INSERT, so it sees
-- every row of the statement whatever their order (a row naming a write-off
-- listed after it), and the cap is on the net of everything aging nets into
-- the write-off — its whole same-customer tree, at any depth, any type —
-- not on the recoveries alone.
CREATE OR REPLACE FUNCTION public.enforce_write_off_recovery() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    SET enable_seqscan = off
    SET enable_hashjoin = off
    SET enable_mergejoin = off
    AS $$
DECLARE
    v_parent   public.account_ledger%ROWTYPE;
    v_wo       public.account_ledger%ROWTYPE;
    v_wo_id    uuid;
    v_tree     uuid[];
    v_net      numeric;
    v_on       date;
    v_later_id uuid;
    v_later_at timestamptz;
    v_future   boolean;
    c_max      CONSTANT integer := 1000;
BEGIN
    -- r5 (Codex B1): a row in a write-off's tree — the write-off itself, or
    -- any row under it — is recorded at a finite time already reached. The
    -- owner's created_at is kept for history loads; one recorded in the
    -- future would make every later row of the tree "recorded before" it,
    -- and the retry below could never succeed.
    v_future := NOT pg_catalog.isfinite(NEW.created_at) OR NEW.created_at > pg_catalog.clock_timestamp();
    IF NEW.transaction_type = 'write_off' AND v_future THEN
        RAISE EXCEPTION USING
            MESSAGE = format('write-off %s is recorded at a non-finite or future time (%s): a row in a write-off''s tree is recorded at a time already reached (R-02, v5.4.2-22)', NEW.id, NEW.created_at),
            ERRCODE = 'check_violation';
    END IF;
    IF NEW.reverses_ledger_entry_id IS NULL THEN
        RETURN NULL;
    END IF;
    SELECT * INTO v_parent FROM public.account_ledger l WHERE l.id = NEW.reverses_ledger_entry_id;
    IF NEW.transaction_type = 'write_off_recovery' THEN
        IF NOT FOUND OR v_parent.transaction_type <> 'write_off'
           OR v_parent.tenant_id <> NEW.tenant_id OR v_parent.customer_id <> NEW.customer_id THEN
            RAISE EXCEPTION USING
                MESSAGE = format('a write-off recovery names a write_off entry of its own customer; %s is not one (R-02, v5.4.2-22)', NEW.reverses_ledger_entry_id),
                ERRCODE = 'foreign_key_violation';
        END IF;
        IF NOT (v_parent.amount < 0 AND NEW.amount > 0) THEN
            RAISE EXCEPTION USING
                MESSAGE = format('a write-off recovery has the opposite sign of its write-off: %s against %s (R-02, v5.4.2-22)', NEW.amount, v_parent.amount),
                ERRCODE = 'check_violation';
        END IF;
    ELSIF FOUND AND v_parent.transaction_type = 'write_off' THEN
        -- r2 (Opus B2, Fable S2): only a recovery names a write-off directly.
        RAISE EXCEPTION USING
            MESSAGE = format('a row of type %s names write-off %s: only a write_off_recovery names a write-off, so the cap counts it (R-02, v5.4.2-22)', NEW.transaction_type, NEW.reverses_ledger_entry_id),
            ERRCODE = 'check_violation';
    END IF;
    -- The cap, for every write-off above the new row within its customer
    -- (aging nets a reversal only within its customer), locked in id order.
    -- r4: the walks step by index, whatever the statistics say. On a ledger the
    -- planner believes empty (a fresh tenant; after autovacuum resets the
    -- estimate) it hash-joined a sequential scan of the whole ledger at every
    -- step, with the RLS functions on every row: R10g took 30 s and more, run
    -- to run (with only that turned off, it merge-joined a full index scan).
    -- The function runs with sequential scans, hash and merge joins off: each
    -- step is a nested loop over the id or reversal index, which always exist.
    -- r4 (Opus S1): the walk carries each entry's type and customer, so the
    -- write-offs are chosen from the walk itself; no step or final join reads
    -- the ledger by anything but its id. Leaving the customer ends the walk.
    FOR v_wo_id IN
        WITH RECURSIVE up(id, next_id, transaction_type, mine, depth) AS (
            SELECT l.id, l.reverses_ledger_entry_id, l.transaction_type,
                   (l.tenant_id = NEW.tenant_id AND l.customer_id = NEW.customer_id), 1
              FROM public.account_ledger l WHERE l.id = NEW.reverses_ledger_entry_id
            UNION ALL
            SELECT l.id, l.reverses_ledger_entry_id, l.transaction_type,
                   (l.tenant_id = NEW.tenant_id AND l.customer_id = NEW.customer_id), u.depth + 1
              FROM up u JOIN public.account_ledger l ON l.id = u.next_id
             WHERE u.mine AND u.depth < c_max
        )
        SELECT u.id FROM up u WHERE u.mine AND u.transaction_type = 'write_off' ORDER BY u.id
    LOOP
        IF pg_catalog.current_setting('transaction_isolation') <> 'read committed' THEN
            RAISE EXCEPTION USING
                MESSAGE = format('a row under write-off %s is posted at READ COMMITTED (this transaction is %s): the cap must see every row committed while it waited (R-02, v5.4.2-22)', v_wo_id, pg_catalog.current_setting('transaction_isolation')),
                ERRCODE = 'invalid_transaction_state';
        END IF;
        PERFORM pg_advisory_xact_lock(hashtextextended('write_off_recovery:' || v_wo_id::text, 0));
        SELECT * INTO v_wo FROM public.account_ledger l WHERE l.id = v_wo_id;
        IF v_future THEN
            RAISE EXCEPTION USING
                MESSAGE = format('a row under write-off %s is recorded at a non-finite or future time (%s): a row in a write-off''s tree is recorded at a time already reached (R-02, v5.4.2-22)', v_wo.id, NEW.created_at),
                ERRCODE = 'check_violation';
        END IF;
        -- r4 (Opus B1): aging nets the tree date by date, so the tree is
        -- ordered by date: a row is dated on or after the entry it names (by
        -- induction, every path down from the write-off is in date order).
        IF NEW.transaction_date < v_parent.transaction_date THEN
            RAISE EXCEPTION USING
                MESSAGE = format('a row under write-off %s is dated on or after the entry it names: %s is dated %s, before %s (R-02, v5.4.2-22)', v_wo.id, NEW.id, NEW.transaction_date, v_parent.transaction_date),
                ERRCODE = 'check_violation';
        END IF;
        -- Each step is found by the reversal link alone (as above, the
        -- customer in the join lets the planner scan the customer's ledger per
        -- step); a row of another customer is flagged, not counted, and its
        -- descendants are not walked.
        WITH RECURSIVE down(id, mine) AS (
            SELECT l.id, (l.tenant_id = v_wo.tenant_id AND l.customer_id = v_wo.customer_id)
              FROM public.account_ledger l
             WHERE l.reverses_ledger_entry_id = v_wo.id
            UNION
            SELECT l.id, (l.tenant_id = v_wo.tenant_id AND l.customer_id = v_wo.customer_id)
              FROM down d JOIN public.account_ledger l ON l.reverses_ledger_entry_id = d.id
             WHERE d.mine
        )
        SELECT array_agg(d.id) INTO v_tree FROM down d WHERE d.mine;
        -- r4: aging also nets the tree as recorded at an instant, by
        -- created_at, the transaction's start. A row recorded before a row
        -- already in the tree (a transaction that began earlier, posting
        -- later) would let an earlier instant see it without that row; the
        -- writer retries. Recorded order then follows the order checked here.
        -- r6 (Opus N1): a row whose recorded time was chosen (the owner's
        -- history load: not its transaction's start) keeps that time on any
        -- retry, so it is refused for good.
        SELECT l.id, l.created_at INTO v_later_id, v_later_at
          FROM public.account_ledger l
         WHERE (l.id = v_wo.id OR l.id = ANY (v_tree)) AND l.created_at > NEW.created_at
         ORDER BY l.created_at DESC LIMIT 1;
        IF FOUND AND NEW.created_at <> pg_catalog.now() THEN
            RAISE EXCEPTION USING
                MESSAGE = format('write-off %s: %s is recorded at %s, a time chosen for it, before %s (recorded at %s) already in its tree — a history row is recorded after every row already in its tree (R-02, R12, v5.4.2-22)', v_wo.id, NEW.id, NEW.created_at, v_later_id, v_later_at),
                ERRCODE = 'check_violation';
        END IF;
        IF FOUND THEN
            RAISE EXCEPTION USING
                MESSAGE = format('write-off %s: %s is recorded at %s, before %s (recorded at %s) already in its tree — a transaction that began earlier is posting later; retry it (R-02, v5.4.2-22)', v_wo.id, NEW.id, NEW.created_at, v_later_id, v_later_at),
                ERRCODE = 'serialization_failure';
        END IF;
        -- r4 (Opus B1): the cap holds at every date of the tree, as aging and
        -- the close net it (rows dated on or before the date), not only at the
        -- end: a later-dated reversal makes no room for an earlier recovery.
        SELECT x.on_date, x.net INTO v_on, v_net
          FROM (SELECT l.transaction_date AS on_date,
                       sum(l.amount) OVER (ORDER BY l.transaction_date) AS net
                  FROM public.account_ledger l WHERE l.id = ANY (v_tree)) x
         WHERE x.net < 0 OR x.net > -v_wo.amount
         ORDER BY x.on_date LIMIT 1;
        IF FOUND THEN
            RAISE EXCEPTION USING
                MESSAGE = format('write-off %s: on %s the rows netted against it would come to %s, outside 0 to the %s written off (R-02 cap, v5.4.2-22)', v_wo.id, v_on, v_net, -v_wo.amount),
                ERRCODE = 'check_violation';
        END IF;
    END LOOP;
    RETURN NULL;
END;
$$;
COMMENT ON FUNCTION public.enforce_write_off_recovery() IS
    'v5.4.2-22 (W3; R-02), r3. AFTER INSERT on account_ledger, for a row naming an entry or a write_off (r5), after the lineage walk: every row of the statement is visible. r5: a write_off, and a row under one, is recorded at a finite time already reached (23514). A row naming a write_off directly is a write_off_recovery; a write_off_recovery names a write_off of its own tenant and customer, positive against a negative write-off. For every write_off above the new row within its customer, at READ COMMITTED behind an advisory lock on that write-off (taken in id order), the net of its whole same-customer tree stays between 0 and the amount written off. r4: at every date of the tree; a row under a write-off is dated on or after the entry it names and is not recorded before a row already in the tree (40001, retry; r6: 23514 for a recorded time chosen for it, which no retry changes); the walks run with sequential scans, hash and merge joins off.';
CREATE TRIGGER enforce_write_off_recovery AFTER INSERT ON public.account_ledger
    FOR EACH ROW WHEN (NEW.reverses_ledger_entry_id IS NOT NULL OR NEW.transaction_type = 'write_off') EXECUTE FUNCTION public.enforce_write_off_recovery();
ALTER TABLE public.account_ledger ENABLE ALWAYS TRIGGER enforce_write_off_recovery;

-- r2 (Fable B1, Codex B3): lineage never loops. Two rows of one statement
-- may name each other (the FK is checked at the statement's end); the walk
-- runs after the row is in, so it sees its siblings. r3 (Codex B2): the walk
-- fails closed — a chain that has not reached its original within the bound
-- (longer, or entering a loop the new row is not on) is refused.
-- AFTER triggers on one event fire by name: this walk precedes the cap.
CREATE OR REPLACE FUNCTION public.enforce_ledger_lineage_acyclic() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    SET enable_seqscan = off
    SET enable_hashjoin = off
    SET enable_mergejoin = off
    AS $$
DECLARE
    c_max  CONSTANT integer := 1000;
    v_loop boolean;
    v_long boolean;
BEGIN
    WITH RECURSIVE up(id, depth) AS (
        SELECT NEW.reverses_ledger_entry_id, 1
        UNION ALL
        SELECT l.reverses_ledger_entry_id, u.depth + 1
          FROM up u JOIN public.account_ledger l ON l.id = u.id
         WHERE u.id <> NEW.id AND u.depth < c_max
    )
    SELECT coalesce(bool_or(up.id = NEW.id), false),
           coalesce(bool_or(up.depth = c_max AND up.id IS NOT NULL AND up.id <> NEW.id), false)
      INTO v_loop, v_long
      FROM up;
    IF v_loop THEN
        RAISE EXCEPTION USING
            MESSAGE = format('account_ledger %s: its reversal chain returns to itself; a reversal names an earlier entry (R-02, v5.4.2-22)', NEW.id),
            ERRCODE = 'check_violation';
    END IF;
    IF v_long THEN
        RAISE EXCEPTION USING
            MESSAGE = format('account_ledger %s: its reversal chain does not reach an original within %s entries (too long, or a loop); a reversal names an earlier entry (R-02, v5.4.2-22)', NEW.id, c_max),
            ERRCODE = 'check_violation';
    END IF;
    RETURN NULL;
END;
$$;
COMMENT ON FUNCTION public.enforce_ledger_lineage_acyclic() IS
    'v5.4.2-22 r2, r3. AFTER INSERT on account_ledger, for a row naming an entry: walks the chain of reverses_ledger_entry_id up from the new row and refuses it if the chain comes back to it (rows of one statement naming each other), or (r3) does not reach an original within 1000 entries — a longer chain, or one entering a loop. A cycle has no original, so aging could not place its amount. Fires before enforce_write_off_recovery (trigger name order).';
CREATE TRIGGER enforce_ledger_lineage_acyclic AFTER INSERT ON public.account_ledger
    FOR EACH ROW WHEN (NEW.reverses_ledger_entry_id IS NOT NULL) EXECUTE FUNCTION public.enforce_ledger_lineage_acyclic();
ALTER TABLE public.account_ledger ENABLE ALWAYS TRIGGER enforce_ledger_lineage_acyclic;


-- ----------------------------------------------------------------------------
-- 6. The aging bucket setting (W2)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.aging_bucket_days_valid(p_days integer[]) RETURNS boolean
    LANGUAGE sql IMMUTABLE
    SET search_path = pg_catalog, pg_temp
    AS $$
    -- r2 (Opus B1, Codex S1): one-based, and never NULL (a CHECK passes NULL).
    SELECT coalesce(
           p_days IS NOT NULL
       AND array_ndims(p_days) = 1
       AND array_lower(p_days, 1) = 1
       AND cardinality(p_days) BETWEEN 1 AND 12
       AND array_position(p_days, NULL) IS NULL
       AND p_days[1] > 0
       AND NOT EXISTS (SELECT 1 FROM generate_subscripts(p_days, 1) i WHERE i > 1 AND p_days[i] <= p_days[i - 1]), false)
$$;
COMMENT ON FUNCTION public.aging_bucket_days_valid(integer[]) IS
    'v5.4.2-22 (W2). True for a one-dimensional, one-based list of 1 to 12 positive day counts, strictly increasing, no NULL; false (never NULL) otherwise.';

CREATE OR REPLACE FUNCTION public.aging_bucket_days_json_valid(p_value jsonb) RETURNS boolean
    LANGUAGE sql IMMUTABLE
    SET search_path = pg_catalog, pg_temp
    AS $$
    SELECT CASE
        WHEN jsonb_typeof(p_value) IS DISTINCT FROM 'array' THEN false
        WHEN EXISTS (SELECT 1 FROM jsonb_array_elements(p_value) e
                      WHERE jsonb_typeof(e) <> 'number' OR (e #>> '{}') !~ '^[0-9]{1,6}$') THEN false
        ELSE public.aging_bucket_days_valid(ARRAY(SELECT (x.e #>> '{}')::integer
                                                    FROM jsonb_array_elements(p_value) WITH ORDINALITY AS x(e, n) ORDER BY x.n))
    END
$$;
COMMENT ON FUNCTION public.aging_bucket_days_json_valid(jsonb) IS
    'v5.4.2-22 r2 (W2). True for a JSON array of whole day counts that aging_bucket_days_valid() accepts; false otherwise, never NULL. The CHECK on every configuration-history row of the aging key.';

ALTER TABLE public.tenants ADD COLUMN receivables_aging_bucket_days integer[] DEFAULT '{30,60,90,120}'::integer[] NOT NULL;
ALTER TABLE public.tenants ADD CONSTRAINT tenants_receivables_aging_bucket_days_check
    CHECK (public.aging_bucket_days_valid(receivables_aging_bucket_days));
COMMENT ON COLUMN public.tenants.receivables_aging_bucket_days IS
    'v5.4.2-22 (W2). The upper edges, in days since the entry''s date, of the receivables aging buckets: {30,60,90,120} gives 0-30, 31-60, 61-90, 91-120 and over 120. Recorded in tenant_configuration_history; aging reads it as of its recorded instant.';

-- r4 (Codex B1, Opus N2): the close reads the edges at its instant. A change
-- of the edges takes the tenant's close head FOR SHARE, as a money write does:
-- a change in flight finishes before the close takes its instant, and one
-- that arrives later waits for the close. Invoker rights: tally_app holds the
-- head's lock column (see the freeze).
CREATE OR REPLACE FUNCTION public.enforce_aging_edges_close_order() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
BEGIN
    IF NEW.receivables_aging_bucket_days IS DISTINCT FROM OLD.receivables_aging_bucket_days THEN
        PERFORM 1 FROM public.accounting_close_heads h WHERE h.tenant_id = NEW.id FOR SHARE;
        IF NOT FOUND THEN
            RAISE EXCEPTION USING
                MESSAGE = format('tenants: tenant %s has no close head visible to this session; the aging edges change behind it (v5.4.2-22)', NEW.id),
                ERRCODE = 'insufficient_privilege';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;
COMMENT ON FUNCTION public.enforce_aging_edges_close_order() IS
    'v5.4.2-22 r4 (W2). BEFORE UPDATE OF receivables_aging_bucket_days on tenants: a change of the edges takes the tenant''s close head FOR SHARE, so it is ordered with the close (which takes the head FOR UPDATE before its instant): the close ages by the edges in force at its instant.';
CREATE TRIGGER enforce_aging_edges_close_order BEFORE UPDATE OF receivables_aging_bucket_days ON public.tenants
    FOR EACH ROW EXECUTE FUNCTION public.enforce_aging_edges_close_order();
ALTER TABLE public.tenants ENABLE ALWAYS TRIGGER enforce_aging_edges_close_order;

-- r2 (Codex S4): the write-off threshold W3 names. The schema records the
-- setting; proposing a write-off is the core's. NULL: not set, so the core
-- proposes none (K-07: no assumed default).
ALTER TABLE public.tenants ADD COLUMN write_off_threshold_days integer;
ALTER TABLE public.tenants ADD CONSTRAINT tenants_write_off_threshold_days_check
    CHECK (write_off_threshold_days IS NULL OR write_off_threshold_days > 0);
COMMENT ON COLUMN public.tenants.write_off_threshold_days IS
    'v5.4.2-22 r2 (W3, CI-076). The age in days at which the core proposes writing off a receivable; NULL: not set, so none is proposed (no assumed default, K-07). Recorded in tenant_configuration_history. The write-off itself is a ledger row the core or an operator writes.';

-- The recorder with the new key; the known-key CHECK with it. The body is
-- -12's with the key list extended (the two lists move together).
ALTER TABLE public.tenant_configuration_history DROP CONSTRAINT IF EXISTS tenant_configuration_history_key_known_check;
ALTER TABLE public.tenant_configuration_history ADD CONSTRAINT tenant_configuration_history_key_known_check
    CHECK (((config_key ~~ 'settings.%'::text) OR (config_key = ANY (ARRAY['default_partial_period_policy'::text, 'payment_allocation_strategy'::text, 'overpayment_handling'::text, 'credit_application_timing'::text, 'minimum_refund_amount'::text, 'below_threshold_action'::text, 'donation_program_name'::text, 'auto_approve_clean_reads'::text, 'unreviewed_read_billing_policy'::text, 'meter_redeployment_policy'::text, 'default_import_error_policy'::text, 'void_only_unbilled_disposition'::text, 'void_rebill_threshold'::text, 'cutover_date'::text, 'regulatory_class_mode'::text, 'backbilling_adverse_limit_months'::text, 'receivables_aging_bucket_days'::text, 'write_off_threshold_days'::text]))));
-- r2 (Opus B1): every recorded value of the aging key is a valid list, a
-- direct (manual or backfill) row included.
ALTER TABLE public.tenant_configuration_history ADD CONSTRAINT tenant_configuration_history_aging_days_check
    CHECK (config_key <> 'receivables_aging_bucket_days'::text OR public.aging_bucket_days_json_valid(new_value));

CREATE OR REPLACE FUNCTION public.record_tenant_configuration_change() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    c_policy_keys CONSTANT text[] := ARRAY[
        'default_partial_period_policy', 'payment_allocation_strategy',
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
$$;

-- Tenants that exist now: the default, from now. Aging recorded before this
-- patch has no setting and raises (R9): the setting did not exist then.
INSERT INTO public.tenant_configuration_history
    (tenant_id, config_key, old_value, new_value, effective_from, change_source, change_reason)
SELECT t.id, 'receivables_aging_bucket_days', NULL, to_jsonb(t.receivables_aging_bucket_days), now(), 'backfill',
       'v5.4.2-22: the aging bucket setting is created with its default; no earlier value existed'
  FROM public.tenants t;
INSERT INTO public.tenant_configuration_history
    (tenant_id, config_key, old_value, new_value, effective_from, change_source, change_reason)
SELECT t.id, 'write_off_threshold_days', NULL, 'null'::jsonb, now(), 'backfill',
       'v5.4.2-22: the write-off threshold setting is created unset; no earlier value existed'
  FROM public.tenants t;

CREATE OR REPLACE FUNCTION public.receivables_aging_bucket_days_as_of(p_tenant_id uuid, p_at timestamp with time zone) RETURNS integer[]
    LANGUAGE plpgsql STABLE
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_val jsonb;
BEGIN
    IF p_tenant_id IS NULL OR p_at IS NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = 'receivables_aging_bucket_days_as_of: tenant and instant are both required; never default to now (v5.4.2-22)',
            ERRCODE = 'null_value_not_allowed';
    END IF;
    SELECT h.new_value INTO v_val
      FROM public.tenant_configuration_history h
     WHERE h.tenant_id = p_tenant_id AND h.config_key = 'receivables_aging_bucket_days' AND h.effective_from <= p_at
     ORDER BY h.effective_from DESC, h.seq DESC
     LIMIT 1;
    IF v_val IS NULL OR jsonb_typeof(v_val) <> 'array' THEN
        RETURN NULL;
    END IF;
    RETURN ARRAY(SELECT e::integer FROM jsonb_array_elements_text(v_val) WITH ORDINALITY AS x(e, n) ORDER BY n);
END;
$$;
COMMENT ON FUNCTION public.receivables_aging_bucket_days_as_of(uuid, timestamp with time zone) IS
    'v5.4.2-22 (W2). The tenant''s aging bucket edges as recorded at p_at (tenant_configuration_history); NULL before the setting''s history or for a tenant not visible. Both coordinates required.';


-- ----------------------------------------------------------------------------
-- 7. Receivables aging (W1; D-3)
-- ----------------------------------------------------------------------------
-- r2 (Opus B1, Codex B1, Fable S1): the edges are an argument. A snapshot
-- is reproduced with its own stored edges; the three-argument form reads the
-- tenant's setting as recorded.
CREATE OR REPLACE FUNCTION public.receivables_aging_as_of(p_tenant_id uuid, p_on date, p_recorded_at timestamp with time zone,
                                                         p_bucket_days integer[])
    RETURNS TABLE (customer_id uuid, customer_number text, customer_status text, last_location_id uuid, balance numeric,
                   bucket_index integer, bucket_from_days integer, bucket_to_days integer, amount numeric)
    LANGUAGE plpgsql STABLE
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_edges     integer[] := p_bucket_days;
    v_uncovered integer;
BEGIN
    IF p_tenant_id IS NULL OR p_on IS NULL OR p_recorded_at IS NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = 'receivables_aging_as_of: tenant, date and recorded-at coordinate are all required; never default to today (v5.4.2-22)',
            ERRCODE = 'null_value_not_allowed';
    END IF;
    IF NOT public.aging_bucket_days_valid(v_edges) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('receivables_aging_as_of: %s is not a list of bucket edges (one-based, 1 to 12 positive days, increasing) (v5.4.2-22)', v_edges),
            ERRCODE = 'invalid_parameter_value';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.accounting_close_heads h WHERE h.tenant_id = p_tenant_id) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('receivables_aging_as_of: tenant %s is not visible in this session (v5.4.2-22)', p_tenant_id),
            ERRCODE = 'no_data_found';
    END IF;
    -- r2: every entry must reach an original (no lineage loop), or its
    -- amount would drop out of the aging silently.
    WITH RECURSIVE
    l AS (
        SELECT x.id, x.customer_id, x.reverses_ledger_entry_id
          FROM public.account_ledger x
         WHERE x.tenant_id = p_tenant_id AND x.transaction_date <= p_on AND x.created_at <= p_recorded_at
    ),
    tree AS (
        SELECT r.id, r.customer_id FROM l r
         WHERE NOT EXISTS (SELECT 1 FROM l p WHERE p.id = r.reverses_ledger_entry_id AND p.customer_id = r.customer_id)
        UNION ALL
        SELECT c.id, c.customer_id FROM l c JOIN tree t ON c.reverses_ledger_entry_id = t.id AND c.customer_id = t.customer_id
    )
    SELECT (SELECT count(*) FROM l) - (SELECT count(*) FROM tree) INTO v_uncovered;
    IF v_uncovered <> 0 THEN
        RAISE EXCEPTION USING
            MESSAGE = format('receivables_aging_as_of: %s ledger entries of tenant %s reach no original (a reversal loop); aging would omit them (v5.4.2-22)', v_uncovered, p_tenant_id),
            ERRCODE = 'data_exception';
    END IF;
    RETURN QUERY
    WITH RECURSIVE
    l AS (
        SELECT x.id, x.customer_id, x.location_id, x.transaction_date, x.created_at, x.amount, x.reverses_ledger_entry_id
          FROM public.account_ledger x
         WHERE x.tenant_id = p_tenant_id AND x.transaction_date <= p_on AND x.created_at <= p_recorded_at
    ),
    -- Each entry belongs to the tree of the original it (transitively)
    -- reverses, within its own customer; an entry whose original is outside
    -- the window, or another customer's, is its own.
    tree AS (
        SELECT r.id, r.id AS root, r.customer_id
          FROM l r
         WHERE NOT EXISTS (SELECT 1 FROM l p WHERE p.id = r.reverses_ledger_entry_id AND p.customer_id = r.customer_id)
        UNION ALL
        SELECT c.id, t.root, c.customer_id
          FROM l c JOIN tree t ON c.reverses_ledger_entry_id = t.id AND c.customer_id = t.customer_id
    ),
    nets AS (
        SELECT t.root, sum(e.amount) AS net FROM tree t JOIN l e ON e.id = t.id GROUP BY t.root
    ),
    bal AS (
        SELECT e.customer_id, sum(e.amount) AS b FROM l e GROUP BY e.customer_id
    ),
    debits AS (
        SELECT o.customer_id, o.transaction_date, n.net, bb.b,
               sum(n.net) OVER (PARTITION BY o.customer_id
                                ORDER BY o.transaction_date DESC, o.created_at DESC, o.id DESC
                                ROWS UNBOUNDED PRECEDING) AS cum
          FROM nets n JOIN l o ON o.id = n.root JOIN bal bb ON bb.customer_id = o.customer_id
         WHERE n.net > 0 AND bb.b > 0
    ),
    open_parts AS (
        SELECT d.customer_id, d.transaction_date, least(d.net, d.b - (d.cum - d.net)) AS open_amount
          FROM debits d
         WHERE d.cum - d.net < d.b
    ),
    bucketed AS (
        SELECT o.customer_id,
               (SELECT count(*)::integer FROM unnest(v_edges) e WHERE e < (p_on - o.transaction_date)) AS idx,
               o.open_amount
          FROM open_parts o
    ),
    rows_out AS (
        SELECT bk.customer_id, bk.idx, sum(bk.open_amount) AS amt FROM bucketed bk GROUP BY bk.customer_id, bk.idx
        UNION ALL
        SELECT bb.customer_id, NULL::integer, bb.b FROM bal bb WHERE bb.b < 0
    )
    SELECT ro.customer_id, c.customer_number,
           (SELECT e.to_status FROM public.customer_state_events e
             WHERE e.customer_id = ro.customer_id AND e.effective_at <= p_recorded_at
             ORDER BY e.effective_at DESC, e.seq DESC LIMIT 1),
           (SELECT x.location_id FROM l x
             WHERE x.customer_id = ro.customer_id AND x.location_id IS NOT NULL
             ORDER BY x.transaction_date DESC, x.created_at DESC, x.id DESC LIMIT 1),
           bb.b,
           ro.idx,
           CASE WHEN ro.idx IS NULL THEN NULL WHEN ro.idx = 0 THEN 0 ELSE v_edges[ro.idx] + 1 END,
           CASE WHEN ro.idx IS NULL THEN NULL ELSE v_edges[ro.idx + 1] END,
           ro.amt
      FROM rows_out ro
      JOIN bal bb ON bb.customer_id = ro.customer_id
      JOIN public.customers c ON c.id = ro.customer_id
     ORDER BY c.customer_number, ro.idx NULLS FIRST;
END;
$$;
CREATE OR REPLACE FUNCTION public.receivables_aging_as_of(p_tenant_id uuid, p_on date, p_recorded_at timestamp with time zone)
    RETURNS TABLE (customer_id uuid, customer_number text, customer_status text, last_location_id uuid, balance numeric,
                   bucket_index integer, bucket_from_days integer, bucket_to_days integer, amount numeric)
    LANGUAGE plpgsql STABLE
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_edges integer[];
BEGIN
    IF p_tenant_id IS NULL OR p_on IS NULL OR p_recorded_at IS NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = 'receivables_aging_as_of: tenant, date and recorded-at coordinate are all required; never default to today (v5.4.2-22)',
            ERRCODE = 'null_value_not_allowed';
    END IF;
    v_edges := public.receivables_aging_bucket_days_as_of(p_tenant_id, p_recorded_at);
    IF v_edges IS NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('receivables_aging_as_of: tenant %s has no aging bucket setting recorded at %s, or is not visible in this session (v5.4.2-22)', p_tenant_id, p_recorded_at),
            ERRCODE = 'no_data_found';
    END IF;
    RETURN QUERY SELECT * FROM public.receivables_aging_as_of(p_tenant_id, p_on, p_recorded_at, v_edges);
END;
$$;
COMMENT ON FUNCTION public.receivables_aging_as_of(uuid, date, timestamp with time zone) IS
    'v5.4.2-22 (W1, W2). receivables_aging_as_of(tenant, on, recorded, edges) with the tenant''s bucket edges as recorded at p_recorded_at; raises when none is recorded then, or the tenant is not visible. All coordinates required.';
COMMENT ON FUNCTION public.receivables_aging_as_of(uuid, date, timestamp with time zone, integer[]) IS
    'v5.4.2-22 (D-2, D-3; W1). The tenant''s receivables aging on p_on as recorded at p_recorded_at (ledger rows dated on or before p_on, created by p_recorded_at). Per customer: its balance, its status as recorded at p_recorded_at (customer_state_events; D-3: a former occupant reads as one), the location of its latest located entry, and one row per bucket holding an open amount. Each original entry is netted with the entries of the same customer that (transitively) reverse it; the balance is aged newest first (oldest debt is paid first, K-05); age is p_on minus the entry''s date; bucket_index 0 is 0..edge1 days, the last is over the last edge (bucket_to_days NULL). A credit balance is one row with bucket_index NULL. Zero balances are omitted. All coordinates required; the edges must be valid; a tenant not visible raises; an entry that reaches no original (a lineage loop) raises rather than drop out. A snapshot is reproduced with its stored aging_bucket_days. Invoker rights: RLS applies.';


-- ----------------------------------------------------------------------------
-- 8. The close snapshot (S)
-- ----------------------------------------------------------------------------
CREATE TABLE public.accounting_period_snapshots (
    period_id               uuid NOT NULL,
    tenant_id               uuid NOT NULL,
    period_start            date NOT NULL,
    period_end              date NOT NULL,
    recorded_at             timestamp with time zone NOT NULL,
    opening_balance         numeric(14,2) NOT NULL,
    closing_balance         numeric(14,2) NOT NULL,
    ledger_entry_count      integer NOT NULL,
    aging_bucket_days       integer[] NOT NULL,
    unbilled_revenue        numeric(14,2),
    unbilled_revenue_basis  text,
    closed_by               uuid NOT NULL,
    created_at              timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT accounting_period_snapshots_pkey PRIMARY KEY (period_id),
    CONSTRAINT accounting_period_snapshots_period_fkey FOREIGN KEY (period_id, tenant_id) REFERENCES public.accounting_periods(id, tenant_id),
    CONSTRAINT accounting_period_snapshots_closed_by_fkey FOREIGN KEY (closed_by) REFERENCES public.users(id),
    CONSTRAINT accounting_period_snapshots_unbilled_check
        CHECK ((unbilled_revenue IS NULL AND unbilled_revenue_basis IS NULL)
               OR (unbilled_revenue IS NOT NULL AND COALESCE(unbilled_revenue_basis ~ '[[:alnum:]]'::text, false)))
);
CREATE TABLE public.accounting_period_snapshot_lines (
    period_id     uuid NOT NULL,
    tenant_id     uuid NOT NULL,
    section       text NOT NULL,
    code          text NOT NULL,
    amount        numeric(14,2) NOT NULL,
    entry_count   integer,
    CONSTRAINT accounting_period_snapshot_lines_pkey PRIMARY KEY (period_id, section, code),
    CONSTRAINT accounting_period_snapshot_lines_snapshot_fkey FOREIGN KEY (period_id) REFERENCES public.accounting_period_snapshots(period_id),
    CONSTRAINT accounting_period_snapshot_lines_tenant_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id),
    CONSTRAINT accounting_period_snapshot_lines_section_check CHECK (section = ANY (ARRAY['activity'::text, 'aging'::text]))
);
DO $$
DECLARE t text;
BEGIN
    FOREACH t IN ARRAY ARRAY['accounting_period_snapshots', 'accounting_period_snapshot_lines'] LOOP
        EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);
        EXECUTE format('ALTER TABLE public.%I FORCE ROW LEVEL SECURITY', t);
        EXECUTE format('CREATE POLICY tenant_isolation ON public.%I USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())))', t);
        EXECUTE format('REVOKE ALL ON public.%I FROM PUBLIC, tally_app, tally_core', t);
        EXECUTE format('GRANT SELECT ON public.%I TO tally_app, tally_core', t);
        EXECUTE format('GRANT INSERT ON public.%I TO tally_close', t);
    END LOOP;
END $$;
COMMENT ON TABLE public.accounting_period_snapshots IS
    'v5.4.2-22 (D-2, S1). The figures of a closed period as reported at its close, so a prior period''s number never changes. Written only by close_accounting_period(), append-only. recorded_at is the close''s instant: the ledger dated in the period and created by recorded_at is the period, and receivables_aging_as_of(tenant, period_end, recorded_at, aging_bucket_days) — with the snapshot''s own stored edges (r3) — reproduces the aging lines. closing_balance = opening_balance + the activity lines. unbilled_revenue is the core''s estimate with its basis, a reported figure and never a ledger row (D-2 clarification 1); NULL when none was reported.';
COMMENT ON TABLE public.accounting_period_snapshot_lines IS
    'v5.4.2-22 (S1). A snapshot''s lines. activity: one per ledger transaction_type dated in the period (amount, entry_count). aging: the tenant''s receivables on period_end by bucket — code ''0-30'', ''31-60'', ..., ''121+'' (from the snapshot''s aging_bucket_days), and ''credit_balance'' for customers owed money (entry_count = customers). Append-only, written only by the close.';

CREATE OR REPLACE FUNCTION public.enforce_accounting_snapshot_write() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
BEGIN
    IF TG_OP = 'INSERT' AND current_user = 'tally_close' THEN
        IF TG_TABLE_NAME = 'accounting_period_snapshots' THEN
            NEW.created_at := now();
        END IF;
        RETURN NEW;
    END IF;
    RAISE EXCEPTION USING
        MESSAGE = format('%s is written only by close_accounting_period(), once, and never edited or deleted (D-2, v5.4.2-22)', TG_TABLE_NAME),
        ERRCODE = 'restrict_violation';
END;
$$;
COMMENT ON FUNCTION public.enforce_accounting_snapshot_write() IS
    'v5.4.2-22 (S1). The snapshot tables: INSERT only as tally_close (inside the close); no UPDATE, DELETE or TRUNCATE by anyone.';
DO $$
DECLARE t text;
BEGIN
    FOREACH t IN ARRAY ARRAY['accounting_period_snapshots', 'accounting_period_snapshot_lines'] LOOP
        EXECUTE format('CREATE TRIGGER enforce_accounting_snapshot_write BEFORE INSERT OR DELETE OR UPDATE ON public.%I FOR EACH ROW EXECUTE FUNCTION public.enforce_accounting_snapshot_write()', t);
        EXECUTE format('ALTER TABLE public.%I ENABLE ALWAYS TRIGGER enforce_accounting_snapshot_write', t);
        EXECUTE format('CREATE TRIGGER no_truncate BEFORE TRUNCATE ON public.%I FOR EACH STATEMENT EXECUTE FUNCTION public.enforce_accounting_snapshot_write()', t);
        EXECUTE format('ALTER TABLE public.%I ENABLE ALWAYS TRIGGER no_truncate', t);
    END LOOP;
END $$;


-- ----------------------------------------------------------------------------
-- 9. The close (P3, S2)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.close_accounting_period(p_period_id uuid, p_unbilled_revenue numeric DEFAULT NULL,
                                                         p_unbilled_revenue_basis text DEFAULT NULL)
    RETURNS timestamp with time zone
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_user     uuid;
    v_tenant   uuid;
    v_through  date;
    v_p        public.accounting_periods%ROWTYPE;
    v_at       timestamp with time zone;
    v_edges    integer[];
    v_opening  numeric;
    v_activity numeric;
    v_count    integer;
BEGIN
    IF pg_catalog.current_setting('transaction_isolation') <> 'read committed' THEN
        RAISE EXCEPTION USING
            MESSAGE = format('close_accounting_period() runs at READ COMMITTED (this transaction is %s): the close must read what the writers it waited for committed (v5.4.2-22)', pg_catalog.current_setting('transaction_isolation')),
            ERRCODE = 'invalid_transaction_state';
    END IF;
    v_user := nullif(pg_catalog.current_setting('app.user_id', true), '')::uuid;
    IF v_user IS NULL OR NOT public.session_is_supervisor() THEN
        RAISE EXCEPTION USING
            MESSAGE = 'close_accounting_period(): closing a period is irreversible and is a supervisor''s act (app.user_id must name a tenant administrator or a platform administrator) (v5.4.2-22)',
            ERRCODE = 'insufficient_privilege';
    END IF;
    IF (p_unbilled_revenue IS NULL) <> (p_unbilled_revenue_basis IS NULL)
       OR (p_unbilled_revenue_basis IS NOT NULL AND p_unbilled_revenue_basis !~ '[[:alnum:]]') THEN
        RAISE EXCEPTION USING
            MESSAGE = 'close_accounting_period(): an unbilled-revenue figure is reported with its basis, or neither is given (D-2, v5.4.2-22)',
            ERRCODE = 'invalid_parameter_value';
    END IF;

    SELECT p.tenant_id INTO v_tenant FROM public.accounting_periods p WHERE p.id = p_period_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING MESSAGE = format('Accounting period %s not found', p_period_id), ERRCODE = 'no_data_found';
    END IF;
    -- Lock order: the head, then the period.
    SELECT h.closed_through INTO v_through FROM public.accounting_close_heads h WHERE h.tenant_id = v_tenant FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING MESSAGE = format('tenant %s has no close head (v5.4.2-22)', v_tenant), ERRCODE = 'no_data_found';
    END IF;
    SELECT * INTO v_p FROM public.accounting_periods p WHERE p.id = p_period_id FOR UPDATE;
    IF v_p.status = 'withdrawn' THEN
        RAISE EXCEPTION USING
            MESSAGE = format('accounting period %s (%s to %s) is withdrawn; a withdrawn period never closes or returns (v5.4.2-22)', v_p.id, v_p.period_start, v_p.period_end),
            ERRCODE = 'check_violation';
    END IF;
    IF v_p.status <> 'open' THEN
        RAISE EXCEPTION USING
            MESSAGE = format('accounting period %s (%s to %s) is already closed; a closed period never reopens (v5.4.2-22)', v_p.id, v_p.period_start, v_p.period_end),
            ERRCODE = 'check_violation';
    END IF;
    -- Ended everywhere: its last day is over even at UTC-12.
    IF v_p.period_end >= (pg_catalog.now() AT TIME ZONE 'Etc/GMT+12')::date THEN
        RAISE EXCEPTION USING
            MESSAGE = format('accounting period %s ends on %s, which has not ended everywhere yet; a period closes after its last day (v5.4.2-22)', v_p.id, v_p.period_end),
            ERRCODE = 'check_violation';
    END IF;
    IF (v_through IS NULL AND EXISTS (SELECT 1 FROM public.accounting_periods p
                                       WHERE p.tenant_id = v_tenant AND p.status <> 'withdrawn' AND p.period_start < v_p.period_start))
       OR (v_through IS NOT NULL AND v_through <> v_p.period_start - 1) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('accounting period %s starts on %s; the books are closed through %s — periods close in order, the earlier first (v5.4.2-22)', v_p.id, v_p.period_start, coalesce(v_through::text, 'nothing')),
            ERRCODE = 'check_violation';
    END IF;

    -- The recorded instant: after the head lock, so every write that could
    -- be dated on or before period_end has committed (or waits, and will be
    -- refused).
    v_at := pg_catalog.clock_timestamp();
    -- r3 (Opus S1): the tenant's setting itself, at the close's instant —
    -- not the configuration history, which the application writes and may
    -- date. The snapshot stores the edges it used. r4 (Codex B1): a change
    -- of the edges takes the head FOR SHARE (enforce_aging_edges_close_order),
    -- so none commits between the head lock and this read.
    SELECT t.receivables_aging_bucket_days INTO v_edges FROM public.tenants t WHERE t.id = v_tenant;
    IF v_edges IS NULL THEN
        RAISE EXCEPTION USING MESSAGE = format('tenant %s has no aging bucket setting (v5.4.2-22)', v_tenant), ERRCODE = 'no_data_found';
    END IF;

    -- r2 (Codex B4, Opus S1, Fable S4): a row dated in the books being
    -- closed but recorded after the instant (a superuser's chosen
    -- created_at) would be frozen uncounted.
    IF EXISTS (SELECT 1 FROM public.account_ledger l
                WHERE l.tenant_id = v_tenant AND l.transaction_date <= v_p.period_end AND l.created_at > v_at) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('accounting period %s: ledger rows dated on or before %s are recorded after the close''s instant %s; a close counts everything it freezes (v5.4.2-22)', v_p.id, v_p.period_end, v_at),
            ERRCODE = 'check_violation';
    END IF;

    SELECT coalesce(sum(l.amount), 0) INTO v_opening
      FROM public.account_ledger l
     WHERE l.tenant_id = v_tenant AND l.transaction_date < v_p.period_start AND l.created_at <= v_at;
    SELECT coalesce(sum(l.amount), 0), count(*) INTO v_activity, v_count
      FROM public.account_ledger l
     WHERE l.tenant_id = v_tenant AND l.transaction_date BETWEEN v_p.period_start AND v_p.period_end AND l.created_at <= v_at;

    UPDATE public.accounting_close_heads SET closed_through = v_p.period_end, updated_at = v_at WHERE tenant_id = v_tenant;
    UPDATE public.accounting_periods SET status = 'closed', closed_at = v_at, closed_by = v_user WHERE id = v_p.id;

    INSERT INTO public.accounting_period_snapshots
        (period_id, tenant_id, period_start, period_end, recorded_at, opening_balance, closing_balance, ledger_entry_count,
         aging_bucket_days, unbilled_revenue, unbilled_revenue_basis, closed_by)
    VALUES (v_p.id, v_tenant, v_p.period_start, v_p.period_end, v_at, v_opening, v_opening + v_activity, v_count,
            v_edges, p_unbilled_revenue, p_unbilled_revenue_basis, v_user);

    INSERT INTO public.accounting_period_snapshot_lines (period_id, tenant_id, section, code, amount, entry_count)
    SELECT v_p.id, v_tenant, 'activity', l.transaction_type, sum(l.amount), count(*)
      FROM public.account_ledger l
     WHERE l.tenant_id = v_tenant AND l.transaction_date BETWEEN v_p.period_start AND v_p.period_end AND l.created_at <= v_at
     GROUP BY l.transaction_type;

    INSERT INTO public.accounting_period_snapshot_lines (period_id, tenant_id, section, code, amount, entry_count)
    SELECT v_p.id, v_tenant, 'aging',
           CASE WHEN a.bucket_index IS NULL THEN 'credit_balance'
                WHEN a.bucket_to_days IS NULL THEN a.bucket_from_days::text || '+'
                ELSE a.bucket_from_days::text || '-' || a.bucket_to_days::text END,
           sum(a.amount), count(DISTINCT a.customer_id)
      FROM public.receivables_aging_as_of(v_tenant, v_p.period_end, v_at, v_edges) a
     GROUP BY a.bucket_index, a.bucket_from_days, a.bucket_to_days;

    RETURN v_at;
END;
$$;
COMMENT ON FUNCTION public.close_accounting_period(uuid, numeric, text) IS
    'v5.4.2-22 (D-2; P3, S2). Closes an accounting period — the only way. At READ COMMITTED, by a supervisor (app.user_id): locks the tenant''s close head, then the period; refuses a closed period, one whose last day has not ended everywhere (UTC-12), and one that is not next in order. At one recorded instant taken after the lock it writes the snapshot (opening and closing balance, entry count, activity by ledger type, aging on period_end by the tenant''s buckets as its row holds them at that instant (r3), the unbilled-revenue figure and basis if reported), moves closed_through to period_end and closes the period with closed_at = that instant. Refuses while a row dated on or before period_end is recorded after the instant (r2). Returns the instant. Runs as tally_close (SECURITY DEFINER, subject to RLS): a period the caller cannot see is "not found". r6: after the head and the period it takes the tenant row and the closing user''s row FOR KEY SHARE (the snapshot''s keys); call it in a transaction of its own (r7: the header''s lock order states the rule its deadlocks follow).';
ALTER FUNCTION public.close_accounting_period(uuid, numeric, text) OWNER TO tally_close;
REVOKE ALL ON FUNCTION public.close_accounting_period(uuid, numeric, text) FROM PUBLIC, tally_core;
GRANT EXECUTE ON FUNCTION public.close_accounting_period(uuid, numeric, text) TO tally_app;

-- What the close reads, and nothing more.
GRANT SELECT ON public.account_ledger, public.customer_state_events TO tally_close;
GRANT SELECT (id, receivables_aging_bucket_days) ON public.tenants TO tally_close;
GRANT SELECT (id, customer_number) ON public.customers TO tally_close;
GRANT SELECT (id, tenant_id, role) ON public.users TO tally_close;
GRANT EXECUTE ON FUNCTION public.session_is_supervisor(), public.receivables_aging_as_of(uuid, date, timestamp with time zone, integer[]),
    public.aging_bucket_days_valid(integer[]) TO tally_close;


-- ----------------------------------------------------------------------------
-- 10. GL code mapping (G)
-- ----------------------------------------------------------------------------
CREATE TABLE public.gl_account_mappings (
    id                         uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id                  uuid NOT NULL,
    charge_source              text,
    charge_code                text,
    customer_class             text,
    territory_place_id         uuid,
    tax_jurisdiction_place_id  uuid,
    gl_account                 text NOT NULL,
    gl_subaccount              text,
    usoa_code                  text,
    cost_center                text,
    effective_from             date NOT NULL,
    effective_to               date,
    notes                      text,
    created_at                 timestamp with time zone DEFAULT now() NOT NULL,
    created_by                 uuid,
    closed_at                  timestamp with time zone,
    closed_by                  uuid,
    CONSTRAINT gl_account_mappings_pkey PRIMARY KEY (id),
    CONSTRAINT gl_account_mappings_tenant_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id),
    CONSTRAINT gl_account_mappings_territory_fkey FOREIGN KEY (territory_place_id) REFERENCES public.places(id),
    CONSTRAINT gl_account_mappings_tax_place_fkey FOREIGN KEY (tax_jurisdiction_place_id) REFERENCES public.places(id),
    CONSTRAINT gl_account_mappings_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id),
    CONSTRAINT gl_account_mappings_closed_by_fkey FOREIGN KEY (closed_by) REFERENCES public.users(id),
    CONSTRAINT gl_account_mappings_range_check CHECK (effective_to IS NULL OR effective_to > effective_from),
    CONSTRAINT gl_account_mappings_account_check CHECK (gl_account ~ '[[:alnum:]]'::text),
    CONSTRAINT gl_account_mappings_charge_pair_check CHECK ((charge_source IS NULL) = (charge_code IS NULL)),
    -- R6: the three vocabularies, as their tables' CHECKs state them.
    CONSTRAINT gl_account_mappings_charge_check CHECK (
        charge_source IS NULL
        OR (charge_source = 'bill_line' AND charge_code = ANY (ARRAY['base_charge'::text, 'usage_charge'::text, 'surcharge'::text, 'tax'::text,
            'late_fee'::text, 'deposit'::text, 'credit'::text, 'adjustment'::text, 'penalty'::text, 'adhoc'::text, 'minimum_bill_adjustment'::text,
            'consolidated_summary'::text, 'misc'::text]))
        OR (charge_source = 'adhoc_charge' AND charge_code = ANY (ARRAY['tap_fee'::text, 'reconnection_fee'::text, 'disconnection_fee'::text,
            'after_hours_fee'::text, 'meter_test_fee'::text, 'meter_install_fee'::text, 'damage_fee'::text, 'returned_payment_fee'::text,
            'late_fee'::text, 'penalty'::text, 'deposit'::text, 'deposit_refund'::text, 'credit'::text, 'adjustment'::text,
            'backflow_test_fee'::text, 'hydrant_meter_rental'::text, 'miscellaneous'::text]))
        OR (charge_source = 'ledger_entry' AND charge_code = ANY (ARRAY['charge'::text, 'payment'::text, 'adjustment'::text,
            'credit_issued'::text, 'credit_applied'::text, 'late_fee'::text, 'deposit'::text, 'refund'::text, 'write_off'::text,
            'transfer'::text, 'nsf'::text, 'escheat'::text, 'donation'::text, 'void_reversal'::text, 'deposit_interest'::text,
            'write_off_recovery'::text]))),
    CONSTRAINT gl_account_mappings_customer_class_check CHECK (customer_class IS NULL OR customer_class = ANY (ARRAY['residential'::text,
        'commercial'::text, 'small_commercial'::text, 'large_commercial'::text, 'industrial'::text, 'government'::text, 'wholesale'::text])),
    CONSTRAINT gl_account_mappings_no_overlap
        EXCLUDE USING gist (tenant_id WITH =, (coalesce(charge_source, ''::text)) WITH =, (coalesce(charge_code, ''::text)) WITH =,
                            (coalesce(customer_class, ''::text)) WITH =,
                            (coalesce(territory_place_id, '00000000-0000-0000-0000-000000000000'::uuid)) WITH =,
                            (coalesce(tax_jurisdiction_place_id, '00000000-0000-0000-0000-000000000000'::uuid)) WITH =,
                            daterange(effective_from, effective_to, '[)'::text) WITH &&)
);
CREATE INDEX idx_gl_account_mappings_lookup ON public.gl_account_mappings USING btree (tenant_id, charge_source, charge_code);
ALTER TABLE public.gl_account_mappings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.gl_account_mappings FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON public.gl_account_mappings USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));
COMMENT ON TABLE public.gl_account_mappings IS
    'v5.4.2-22 (D-2; CI-048, A-10). The tenant''s chart-of-accounts mapping for the export: tenant configuration, not a GL (there is no posting table). Key: the charge (charge_source bill_line | adhoc_charge | ledger_entry, and its code), customer_class, territory_place_id, tax_jurisdiction_place_id — each part NULL is a wildcard; the same key never overlaps in effective dates. Values: gl_account (required), gl_subaccount, usoa_code, cost_center. Bitemporal: effective_from/effective_to (valid time, [from, to)) and created_at/closed_at (recorded). Never edited: the only change is a close (effective_to set once, stamped); a successor row carries the new values. No row starts, and no close takes effect, on or before the tenant''s closed-through date. gl_mapping_as_of() resolves a line; the core refuses to export a line with no mapping.';

CREATE OR REPLACE FUNCTION public.enforce_gl_account_mapping() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_through date;
    c_close   CONSTANT text[] := ARRAY['effective_to', 'closed_at', 'closed_by'];
BEGIN
    IF TG_OP IN ('DELETE', 'TRUNCATE') THEN
        RAISE EXCEPTION USING
            MESSAGE = 'gl_account_mappings rows are never deleted: a past export must stay answerable (v5.4.2-22)',
            ERRCODE = 'restrict_violation';
    END IF;
    SELECT h.closed_through INTO v_through
      FROM public.accounting_close_heads h WHERE h.tenant_id = NEW.tenant_id FOR SHARE;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING
            MESSAGE = format('gl_account_mappings: tenant %s has no close head visible to this session (v5.4.2-22)', NEW.tenant_id),
            ERRCODE = 'insufficient_privilege';
    END IF;
    IF TG_OP = 'INSERT' THEN
        IF NEW.closed_at IS NOT NULL OR NEW.closed_by IS NOT NULL THEN
            RAISE EXCEPTION USING
                MESSAGE = 'gl_account_mappings: closed_at and closed_by are the database''s (v5.4.2-22)',
                ERRCODE = 'check_violation';
        END IF;
        IF v_through IS NOT NULL AND (NEW.effective_from <= v_through OR NEW.effective_to <= v_through) THEN
            RAISE EXCEPTION USING
                MESSAGE = format('gl_account_mappings: a mapping in force on or before %s, the end of the last closed period, would change a closed period''s export (D-2, v5.4.2-22)', v_through),
                ERRCODE = 'check_violation';
        END IF;
        -- r2 (Codex S2): recorded when the statement runs, so a lookup at an
        -- instant inside this transaction never changes afterwards.
        NEW.created_at := pg_catalog.clock_timestamp();
        NEW.created_by := nullif(pg_catalog.current_setting('app.user_id', true), '')::uuid;
        RETURN NEW;
    END IF;
    -- The one change: a close, effective_to set once.
    IF OLD.effective_to IS NULL AND NEW.effective_to IS NOT NULL
       AND (to_jsonb(NEW) - c_close) = (to_jsonb(OLD) - c_close) THEN
        IF v_through IS NOT NULL AND NEW.effective_to <= v_through THEN
            RAISE EXCEPTION USING
                MESSAGE = format('gl_account_mappings %s: a close on %s would end the mapping inside a closed period (closed through %s) (D-2, v5.4.2-22)', OLD.id, NEW.effective_to, v_through),
                ERRCODE = 'check_violation';
        END IF;
        NEW.closed_at := pg_catalog.clock_timestamp();
        NEW.closed_by := nullif(pg_catalog.current_setting('app.user_id', true), '')::uuid;
        RETURN NEW;
    END IF;
    RAISE EXCEPTION USING
        MESSAGE = format('gl_account_mappings %s is never edited: a change is a close (effective_to, once) and a successor row (v5.4.2-22)', OLD.id),
        ERRCODE = 'restrict_violation';
END;
$$;
COMMENT ON FUNCTION public.enforce_gl_account_mapping() IS
    'v5.4.2-22 (G1, G4). gl_account_mappings: takes the tenant''s close head FOR SHARE. INSERT: closed_* empty; in force only after the closed-through date (effective_from after it); created_at (clock_timestamp(), r2) and created_by stamped. UPDATE: only a close (effective_to NULL -> a date after the closed-through date, nothing else), stamping closed_at (clock_timestamp()) and closed_by. Never deleted or truncated.';
CREATE TRIGGER enforce_gl_account_mapping BEFORE INSERT OR DELETE OR UPDATE ON public.gl_account_mappings
    FOR EACH ROW EXECUTE FUNCTION public.enforce_gl_account_mapping();
ALTER TABLE public.gl_account_mappings ENABLE ALWAYS TRIGGER enforce_gl_account_mapping;
CREATE TRIGGER no_truncate BEFORE TRUNCATE ON public.gl_account_mappings
    FOR EACH STATEMENT EXECUTE FUNCTION public.enforce_gl_account_mapping();
ALTER TABLE public.gl_account_mappings ENABLE ALWAYS TRIGGER no_truncate;

REVOKE ALL ON public.gl_account_mappings FROM PUBLIC, tally_app, tally_core;
GRANT SELECT, INSERT, UPDATE ON public.gl_account_mappings TO tally_app;
GRANT SELECT ON public.gl_account_mappings TO tally_core;

CREATE OR REPLACE FUNCTION public.gl_mapping_as_of(p_tenant_id uuid, p_charge_source text, p_charge_code text, p_customer_class text,
                                                  p_territory_place_id uuid, p_tax_jurisdiction_place_id uuid,
                                                  p_on date, p_recorded_at timestamp with time zone)
    RETURNS uuid
    LANGUAGE plpgsql STABLE
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_ids uuid[];
BEGIN
    IF p_tenant_id IS NULL OR p_charge_source IS NULL OR p_charge_code IS NULL OR p_on IS NULL OR p_recorded_at IS NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = 'gl_mapping_as_of: tenant, charge source and code, date and recorded-at coordinate are required; never default to today (v5.4.2-22)',
            ERRCODE = 'null_value_not_allowed';
    END IF;
    WITH c AS (
        SELECT m.id,
               -- r2 (Opus S2): the stated precedence. The charge outranks the
               -- class, the class the territory, the territory the tax
               -- jurisdiction; two different keys never weigh the same.
               8 * (m.charge_code IS NOT NULL)::integer + 4 * (m.customer_class IS NOT NULL)::integer
             + 2 * (m.territory_place_id IS NOT NULL)::integer + (m.tax_jurisdiction_place_id IS NOT NULL)::integer AS specificity
          FROM public.gl_account_mappings m
         WHERE m.tenant_id = p_tenant_id
           AND m.created_at <= p_recorded_at
           AND (m.charge_source IS NULL OR (m.charge_source = p_charge_source AND m.charge_code = p_charge_code))
           AND (m.customer_class IS NULL OR m.customer_class = p_customer_class)
           AND (m.territory_place_id IS NULL OR m.territory_place_id = p_territory_place_id)
           AND (m.tax_jurisdiction_place_id IS NULL OR m.tax_jurisdiction_place_id = p_tax_jurisdiction_place_id)
           AND m.effective_from <= p_on
           -- The end as known at p_recorded_at: a close recorded later is not
           -- yet known (an end given at insert is known from the start).
           AND (m.effective_to IS NULL OR p_on < m.effective_to
                OR (m.closed_at IS NOT NULL AND m.closed_at > p_recorded_at))
    )
    SELECT array_agg(c.id ORDER BY c.id) INTO v_ids
      FROM c WHERE c.specificity = (SELECT max(c2.specificity) FROM c c2);
    IF cardinality(v_ids) > 1 THEN
        RAISE EXCEPTION USING
            MESSAGE = format('gl_mapping_as_of: %s mappings of the same key match (%s %s, class %s) on %s: %s (v5.4.2-22)',
                             cardinality(v_ids), p_charge_source, p_charge_code, coalesce(p_customer_class, '-'), p_on, v_ids),
            ERRCODE = 'cardinality_violation';
    END IF;
    RETURN v_ids[1];
END;
$$;
COMMENT ON FUNCTION public.gl_mapping_as_of(uuid, text, text, text, uuid, uuid, date, timestamp with time zone) IS
    'v5.4.2-22 (G1, G2). The gl_account_mappings row for an export line: rows recorded by p_recorded_at, in force on p_on as then known (a close recorded after p_recorded_at does not end the row), whose every key part is a wildcard or equal to the line''s; the highest precedence wins — charge (8), customer class (4), territory (2), tax jurisdiction (1), summed over the parts set (r2); two rows of one key at once raise (cardinality_violation; EXCLUDE prevents it); none is NULL — the core then refuses to export the line (CI-048). The line''s class and places may be NULL (it has none): only wildcards match them. Invoker rights: RLS applies.';


-- ----------------------------------------------------------------------------
-- 11. Grants for the core and the application
-- ----------------------------------------------------------------------------
DO $$
DECLARE f text;
BEGIN
    FOREACH f IN ARRAY ARRAY['public.receivables_aging_as_of(uuid, date, timestamp with time zone)',
                             'public.receivables_aging_bucket_days_as_of(uuid, timestamp with time zone)',
                             'public.gl_mapping_as_of(uuid, text, text, text, uuid, uuid, date, timestamp with time zone)',
                             'public.receivables_aging_as_of(uuid, date, timestamp with time zone, integer[])',
                             'public.aging_bucket_days_valid(integer[])', 'public.aging_bucket_days_json_valid(jsonb)'] LOOP
        EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC', f);
        EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO tally_app, tally_core', f);
    END LOOP;
    FOREACH f IN ARRAY ARRAY['public.enforce_accounting_close_head()', 'public.create_accounting_close_head()',
                             'public.enforce_accounting_period()', 'public.enforce_accounting_freeze()',
                             'public.enforce_write_off_recovery()', 'public.enforce_accounting_snapshot_write()',
                             'public.enforce_gl_account_mapping()', 'public.enforce_ledger_lineage_acyclic()'] LOOP
        EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC, tally_app, tally_core', f);
    END LOOP;
END $$;


-- ----------------------------------------------------------------------------
-- 12. The invariants
-- ----------------------------------------------------------------------------
-- The seal invariants, with tally_close, and tally_void's lock on the head.
-- The body is -21's with the third role added (c_owns, c_grants, the role
-- loop, the guard list).
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
        'tally_void', '["column public.accounting_close_heads.updated_at UPDATE", "column public.adhoc_charges.billed_at UPDATE", "column public.adhoc_charges.billed_on_invoice_id UPDATE", "column public.adhoc_charges.billed_on_line_item_id UPDATE", "column public.adhoc_charges.status UPDATE", "column public.adhoc_charges.target_billing_period UPDATE", "column public.adhoc_charges.updated_at UPDATE", "column public.adhoc_charges.voided_from_invoice_id UPDATE", "column public.invoices.status UPDATE", "column public.invoices.updated_at UPDATE", "column public.invoices.void_reason_code UPDATE", "column public.invoices.void_reason_notes UPDATE", "column public.invoices.void_rebill_expected UPDATE", "column public.invoices.voided_at UPDATE", "column public.invoices.voided_by UPDATE", "column public.meter_readings.locked_by_invoice_id UPDATE", "column public.meter_readings.validation_status UPDATE", "column public.meter_readings.voided_from_invoice_id UPDATE", "function public.get_user_tenant_id() EXECUTE", "function public.is_platform_admin() EXECUTE", "schema public USAGE", "table public.account_ledger INSERT", "table public.account_ledger SELECT", "table public.accounting_close_heads SELECT", "table public.adhoc_charges SELECT", "table public.invoice_events INSERT", "table public.invoices SELECT", "table public.meter_readings SELECT"]'::jsonb,
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
    'v5.4.2-20 (r3), v5.4.2-21, v5.4.2-22. Raises unless: tally_seal, tally_void and tally_close exist, are NOLOGIN without SUPERUSER, BYPASSRLS, CREATEROLE, CREATEDB or REPLICATION, have no members and are members of nothing, hold and set no default privilege, can define no code, own exactly their pinned SECURITY DEFINER functions (by identity) and no relation, type or schema, and hold exactly their granted privileges, grant options included (seal_role_privileges); tally_core executes no definer but the two RLS helpers (by identity); tally_app, tally_core and PUBLIC hold no privilege on the receipts and no UPDATE on a header version; only tally_close writes the snapshots, the closed-through date and a period''s close (closed_at, closed_by; the application withdraws an open period by status); no public function names the old void setting (a lexical test); every guard of the seals exists exactly as defined (PostgreSQL 16''s rendering) and ENABLE ALWAYS; PUBLIC holds no privilege on any relation in public; and adhoc_charges_billed_names_its_bill is present and validated. Run in the patch tail and in CI.';
REVOKE ALL ON FUNCTION public.assert_seal_role_invariants() FROM PUBLIC, tally_app, tally_core;

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
        'CREATE TRIGGER enforce_write_off_recovery AFTER INSERT ON public.account_ledger FOR EACH ROW WHEN (((new.reverses_ledger_entry_id IS NOT NULL) OR (new.transaction_type = ''write_off''::text))) EXECUTE FUNCTION enforce_write_off_recovery()',
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
        'account_ledger account_ledger_reverses_ledger_entry_fkey FOREIGN KEY (reverses_ledger_entry_id, tenant_id) REFERENCES account_ledger(id, tenant_id)',
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
      FROM unnest(ARRAY['public.enforce_write_off_recovery()', 'public.enforce_ledger_lineage_acyclic()']) f
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
    'v5.4.2-22 (r2, r3, r5). Raises unless every guard of v5.4.2-22 — the close head, the periods, the freeze on the ledger, payments and customer credits, the recovery and the lineage walk, the snapshot tables, the GL mappings, the head''s creation with each tenant — and the ledger''s immutability triggers exist exactly as defined (PostgreSQL 16''s rendering) and ENABLE ALWAYS; the constraints named here (the periods'' and mappings'' EXCLUDE and CHECKs, the ledger''s type list, recovery lineage, not-self CHECK and reversal FK, the tenants'' and history''s setting CHECKs and the history''s known-key CHECK) exist exactly as defined and validated — not every key and FK of the new tables (the snapshot tables'' keys are not pinned); the two walks'' plan settings (r5); and every tenant has a close head (run as the owner, which sees every tenant). Checks definitions, not the bodies of the functions they call. Run in the patch tail and in CI.';
REVOKE ALL ON FUNCTION public.assert_periods_guard_invariants() FROM PUBLIC, tally_app, tally_core;

DO $$ BEGIN
    PERFORM public.assert_periods_guard_invariants();
    PERFORM public.assert_seal_role_invariants();
    PERFORM public.assert_core_role_invariants();
    PERFORM public.assert_tenant_isolation_invariants();
END $$;

-- ============================================================================
-- END PATCH v5.4.2-22
-- ============================================================================

COMMIT;
\endif
