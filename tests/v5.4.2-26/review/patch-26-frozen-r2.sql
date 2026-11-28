-- ============================================================================
-- PATCH v5.4.2-26 — wave 3, part 2: collections decisions and field
--                    verification
-- ============================================================================
-- Authority:   Ryan, 2026-10-19: "go ahead with -26". Rulings K-CCK (fail
--              toward protection; CCK-7 grain), D9-1 (a no-photo disconnect
--              needs a supervisor's approval with a reason code), D3A-1 (the
--              field tool is external), R-38 attachment 2 (lifting a
--              protection needs a supervisor and an evidence reference), K-07
--              (no assumed defaults). Invariants CI-067, CI-069, CI-071,
--              CI-075, and CI-070's link to the decision.
-- Spec:        application/wave3-build-2026-10-18/v5.4.2-26-design.md (C, E,
--              F; lock order; "Tests as written") and source-inventory-
--              wave3.md (E, F). r2: v5.4.2-26-r2-plan.md (round 1's findings,
--              Opus, Fable and Codex; Ryan 2026-11-22: a penalty every month
--              a bill stays unpaid; 2026-11-05 R-12; 2026-11-07 the Tally
--              User).
-- Builds on:   v5.4.2-25 (pending_dispute no longer protective), v5.4.2-23
--              (invoices' (id, tenant_id, customer_id) key), v5.4.2-13
--              (session_is_supervisor), meter_deployments. Mirrors only after
--              -23 and -25.
-- Migration:   additive, plus four tightenings (dunning_events, service_orders,
--              the invoices projections, customers.do_not_disconnect) on rows
--              that are empty everywhere; a database holding collections
--              history stops at the precondition, naming the row, before
--              anything is written.
--
-- ----------------------------------------------------------------------------
-- What changes
-- ----------------------------------------------------------------------------
--   The decision record (C1-C6)
--   * collections_conditions: the conditions a decision can name — the
--     protections, the bars on an act, and the missing rule (no_rule_in_force).
--     Which count for which act where is wave 7's rule data.
--   * collections_decisions (add-only): the core's decision on one act
--     (notice, late_fee, disconnect_order, disconnect_execute,
--     collections_referral) for one subject (CCK-7: a notice names its bill
--     and the service it threatens; a late fee and a referral, the bill; a
--     disconnect, the location and optionally the meter), on an evaluation
--     date: eligible, blocked or unevaluable, every active and unevaluable
--     condition and the one credited, the last day an eligible decision
--     holds, the inputs, their fingerprint and the core version. Written by
--     tally_app with calculated_by. The database checks the record, never the
--     evaluation: the subject's shape [C3a]; the bill issued [C3b] and the
--     customer's (FK); the location the customer's [C3c] and, for a notice,
--     the bill's own [C3d]; a meter deployed there on the date [C3e]; the
--     outcome's shape [C3f]; conditions from the vocabulary, no repeats
--     [C3g]; an execute decision for its own day only [C3h]; no future date
--     [C3j]; one live decision per act and subject, a successor naming it
--     [C4a], no earlier [C4b]; a re-run on the live decision's date and facts
--     refused [C5].
--
--   Acts cite their decision (C7)
--   * dunning_events, adhoc_charges and service_orders gain
--     collections_decision_id; service_order_field_visits carries one. An
--     act needs one exactly when it is gated [A1]: an eligible [A3] decision
--     for its act [A2] and subject [A5] whose window covers the act's date
--     [A6]; the act is the live decision's [A4] — except a dunning line that
--     logs an act with its own record (late_fee_applied, shutoff_scheduled,
--     disconnected), which needs that record instead [A8]. One act per
--     decision (unique indexes). A late fee's decision and bill are written
--     once [A9].
--
--   Hardening (E1-E4)
--   * dunning_events: the bill, tenant and customer by one composite key;
--     the decision by another. The database fills previous_stage and
--     new_stage from a fixed mapping (a caller's that disagree are refused
--     [E2b]) and moves invoices.dunning_stage; a direct write of the stage is
--     refused [E2a].
--   * invoices.late_fee_assessed and late_fee_amount go: a bill's late fees
--     are its late_fee charges.
--   * customers.do_not_disconnect is written only by the enrollment trigger
--     (recompute_do_not_disconnect) [E4].
--
--   Field verification (F1-F4)
--   * service_order_field_visits (add-only): a visit to a disconnect order
--     [F1a] that is open [F1b]: arrival, the captured serial and service
--     point, what the database expected (the order's meter, or the one meter
--     deployed at the location that day) and whether they match; executed or
--     aborted with a reason; evidence references, none blank [F1e]. An
--     execution captures both values [F2e], cites its execute decision, and
--     needs a match or a supervisor's mismatch approval [F2b], evidence or a
--     supervisor's no-evidence approval [F2c], each of its own order and
--     kind [F3d]; under a mismatch approval it captures what the approved
--     visit saw [F3c]. One execution per order.
--   * service_order_field_approvals (add-only): by a tenant_admin of the
--     order's own utility [F3a] (r2: never a platform administrator as
--     themselves), stamped approved_by; for a disconnect order, a mismatch approval
--     naming its aborted unmatched visit with an evidence reference, a
--     no-evidence approval naming none [F3b].
--   * A disconnect order: born citing its order decision, never completed
--     [F4e]; type, customer, location, meter and decision written once [F4a];
--     completed only with an executed visit [F4b], and then for good [F4c];
--     once executed, only completed [F4d].
--
--   r2 (round 1's findings; plan items 1-15)
--   * An act is refused while any live decision for the same act at its
--     location that covers it — the location-wide one, or its meter's — is
--     blocked or unevaluable [A10]; a bill act's bill is not void [A11], nor a
--     decision's [C3b].
--   * An execution cites a decision for its order's customer [A5]; is dated
--     no earlier than its order and decision were recorded, nor in the future
--     [F2f]; captures values with an alphanumeric character [F2e]; names no
--     approval it does not need [F3e].
--   * A disconnect order's status changes only under READ COMMITTED [F4f].
--   * The stage a step moves from is the bill's latest stage-moving event's
--     (record_seq), not the projection, so one statement may record several;
--     escalation steps move a bill only forward (a repeat late fee or a
--     reminder leaves a bill further along where it is; settled by rule).
--   * A late fee is gated under either charge type (late_fee, penalty), and
--     reaches a bill only as the line of its gated charge; a log line needs
--     a standing charge.
--   * One dunning step per decision and bill (a disconnection is logged on
--     each bill of its customer).
--   * The approver is an active tenant_admin of the order's own utility —
--     Tally staff through its Tally User, never as themselves; created_by and
--     approved_by are keyed with tenant_id.
--   * enrollment_recompute_dnd runs ALWAYS (a replica-mode load recomputes).
--   * assert_collections_guard_invariants(), and every earlier patch's.
--
-- ----------------------------------------------------------------------------
-- Lock order and isolation (a rule)
-- ----------------------------------------------------------------------------
--   A write takes, in this order:
--     1. the subject's advisory lock (collections_subject_lock), keyed by
--        (tenant, act, customer, bill, location) — not the meter: a
--        location's subjects share one lock (r2) — a decision takes its
--        own; an act citing a decision takes that decision's (read from the
--        decision, which is written once);
--     2. a dunning event, its bill's row (FOR NO KEY UPDATE); a visit, its
--        order's row (FOR SHARE: an order's status update waits for it);
--     3. nothing else.
--   An order's status update takes only its own row. Every write that takes
--   a subject's lock runs at READ COMMITTED (25000 otherwise). Writers retry
--   40P01.
--
-- ----------------------------------------------------------------------------
-- Residuals (left on purpose)
-- ----------------------------------------------------------------------------
--   R1. Act dates are UTC dates (as -23 reads escheatment_events.event_date):
--       an act late on a Texas evening falls on the next day's date, and
--       (r2, Fable S7) an execute decision written on a Texas evening is for
--       the next UTC day, so it covers the next working day's visits on the
--       evening's facts. No utility time zone is held for every tenant; the
--       core writes an execute decision on the utility's local day of the
--       visit, after that day's weather check (a contract at the mirror).
--       adhoc_charges.effective_date defaults to the session's day.
--   R2. Rule citations wait for wave 7's collections rule tables; until then
--       a decision records the rule versions it read in its inputs, under
--       its fingerprint and calculated_by.
--   R3. reconnected and payment_plan_broken move no dunning stage.
--   R4. What the core decides: which conditions are active, whether a city
--       owes Craft due process, the window an eligible decision holds.
--   R5. The do_not_disconnect and dunning_stage fences are trigger-depth
--       fences: they hold while tally_app can define no code (TEMP revoked).
--   R6. (r2) A bill's stage follows the order steps are recorded in, not
--       their event dates; and ungated steps (payment plan, written off,
--       resolved) move it on the core's word, with no record behind them.
--   R7. (r2, Opus N2-N5) What the database does not judge: an eligible
--       disconnect for a customer whose do_not_disconnect is set (not every
--       protective program is absolute: the core's); the length of an
--       eligible window (only an execute decision is bounded, to its day);
--       ending an enrollment, which lifts the protection, is an operator's
--       act on the enrollment table (R-38's supervisor rule there is a later
--       patch's); credit reporting has no table yet, so no gate.
--
-- Tests. battery-26 (249 checks), races/collections-26.sh (CR1-CR8c, 13
--   results), migration-26.py (P0-P7), mutations-26.py (152 mutations),
--   fill-manifest.py (the invariant's lists). battery-21's late-fee line
--   now bills a gated charge.
--
-- PRECONDITION. v5.4.2-25 applied. No dunning event, no bill past stage
--   current or with a late fee recorded on it, no late-fee or penalty charge
--   or bill line, no disconnect order, and no customer whose do_not_disconnect disagrees with
--   their enrollments. Applied by a superuser, under READ COMMITTED. A second
--   run finds collections_decisions and skips the whole patch (psql's \if).
-- ============================================================================

SELECT to_regclass('public.collections_decisions') IS NOT NULL AS already \gset
\if :already
DO $$ BEGIN RAISE NOTICE 'v5.4.2-26: already applied (collections_decisions exists); nothing to do'; END $$;
\else
BEGIN;

-- Collections history is not reinterpreted (Ryan 2026-09-28: nothing is
-- live): a database holding it stops here, naming the row.
DO $$
DECLARE
    v_id uuid;
BEGIN
    SELECT e.id INTO v_id FROM public.dunning_events e ORDER BY e.id LIMIT 1;
    IF v_id IS NOT NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('v5.4.2-26: dunning event %s predates the decision record — its stage and, for a gated act, its decision would have to be invented. Settle it first (DEPLOY-VERIFICATION -26)', v_id),
            ERRCODE = 'object_not_in_prerequisite_state';
    END IF;
    SELECT i.id INTO v_id FROM public.invoices i WHERE i.dunning_stage <> 'current' ORDER BY i.id LIMIT 1;
    IF v_id IS NOT NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('v5.4.2-26: bill %s is past dunning stage current with no event the database could move it from. Settle it first (DEPLOY-VERIFICATION -26)', v_id),
            ERRCODE = 'object_not_in_prerequisite_state';
    END IF;
    SELECT i.id INTO v_id FROM public.invoices i WHERE i.late_fee_assessed OR coalesce(i.late_fee_amount, 0) <> 0 ORDER BY i.id LIMIT 1;
    IF v_id IS NOT NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('v5.4.2-26 drops invoices.late_fee_assessed and late_fee_amount (a bill''s late fees are its late_fee charges): bill %s records a late fee. Record it as a charge first (DEPLOY-VERIFICATION -26)', v_id),
            ERRCODE = 'object_not_in_prerequisite_state';
    END IF;
    SELECT c.id INTO v_id FROM public.adhoc_charges c WHERE c.charge_type IN ('late_fee', 'penalty') ORDER BY c.id LIMIT 1;
    IF v_id IS NOT NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('v5.4.2-26: late-fee or penalty charge %s cites no collections decision. Settle it first (DEPLOY-VERIFICATION -26)', v_id),
            ERRCODE = 'object_not_in_prerequisite_state';
    END IF;
    SELECT l.id INTO v_id FROM public.invoice_line_items l WHERE l.charge_type IN ('late_fee', 'penalty') ORDER BY l.id LIMIT 1;
    IF v_id IS NOT NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('v5.4.2-26: bill line %s is a late fee or penalty that bills no gated charge. Settle it first (DEPLOY-VERIFICATION -26)', v_id),
            ERRCODE = 'object_not_in_prerequisite_state';
    END IF;
    SELECT o.id INTO v_id FROM public.service_orders o WHERE o.order_type = 'disconnect' ORDER BY o.id LIMIT 1;
    IF v_id IS NOT NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('v5.4.2-26: disconnect order %s cites no collections decision. Settle it first (DEPLOY-VERIFICATION -26)', v_id),
            ERRCODE = 'object_not_in_prerequisite_state';
    END IF;
    SELECT c.id INTO v_id FROM public.customers c
     WHERE c.do_not_disconnect IS DISTINCT FROM EXISTS (
               SELECT 1 FROM public.customer_program_enrollments e JOIN public.program_types pt ON pt.code = e.program_type
                WHERE e.customer_id = c.id AND e.status = 'active' AND pt.is_disconnect_protective)
     ORDER BY c.id LIMIT 1;
    IF v_id IS NOT NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = format('v5.4.2-26 makes do_not_disconnect the enrollments'' alone: customer %s disagrees with their enrollments. Enroll them or clear it first (DEPLOY-VERIFICATION -26)', v_id),
            ERRCODE = 'object_not_in_prerequisite_state';
    END IF;
END $$;


-- ----------------------------------------------------------------------------
-- 1. The conditions (C1)
-- ----------------------------------------------------------------------------
CREATE TABLE public.collections_conditions (
    condition_code  text NOT NULL,
    kind            text NOT NULL,
    description     text NOT NULL,
    created_at      timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT collections_conditions_pkey PRIMARY KEY (condition_code),
    CONSTRAINT collections_conditions_code_check CHECK (condition_code ~ '^[a-z][a-z0-9_]*$'),
    CONSTRAINT collections_conditions_kind_check CHECK (kind = ANY (ARRAY['protection', 'bar', 'rule'])),
    CONSTRAINT collections_conditions_description_check CHECK (description ~ '[[:alnum:]]')
);
INSERT INTO public.collections_conditions (condition_code, kind, description) VALUES
    ('dispute',                    'protection', 'A dispute shelters the amount the act would rest on (CI-074; dispute_shelter_as_of)'),
    ('payment_arrangement',        'protection', 'A deferred payment arrangement in good standing'),
    ('agency_pledge',              'protection', 'An energy-assistance agency''s pledge in its commitment window'),
    ('medical_hold',               'protection', 'A medical (seriously ill) hold'),
    ('military_scra',              'protection', 'Servicemembers Civil Relief Act protection'),
    ('weather_moratorium',         'protection', 'An extreme-weather emergency or weather moratorium'),
    ('regulatory_moratorium',      'protection', 'A moratorium ordered by a regulator or governing body'),
    ('bankruptcy_stay',            'protection', 'A bankruptcy automatic stay'),
    ('deceased_hold',              'protection', 'The hold on a deceased customer''s account'),
    ('protected_status',           'protection', 'A protected-status flag (senior, disabled) where the rule counts it'),
    ('tariff_protection',          'protection', 'A protection the utility''s own tariff adds'),
    ('payment_pending',            'bar',        'A payment pending clearance, or unapplied, that would cure'),
    ('aged_suspense',              'bar',        'Money in suspense past its service level'),
    ('third_party_notice_pending', 'bar',        'A required third-party notice not yet delivered'),
    ('notice_sequence_incomplete', 'bar',        'The required notices and their waiting periods are not complete'),
    ('arrears_below_floor',        'bar',        'The arrears are below the floor the rule sets'),
    ('closed_day',                 'bar',        'The day is one the utility may not act on (its closed days)'),
    ('elderly_due_date_delay',     'bar',        'An elderly customer''s delayed due date has not passed'),
    ('non_disconnectable_debt',    'bar',        'The debt the act rests on cannot drive it (unregulated, a meter-error correction, a carve-out)'),
    ('no_rule_in_force',           'rule',       'No rule is entered for the act where the customer is served (K-07: no assumed default)');
COMMENT ON TABLE public.collections_conditions IS
    'v5.4.2-26 (C1; CI-069). The conditions a collections decision can name: protections, bars on an act, and the missing rule. A decision lists every condition active (active_conditions), the one credited (governing_condition, for attribution only), and every condition the core could not evaluate (unevaluable_conditions). Which count for which act where is wave 7''s rule data. A design rule, not law: an unevaluable condition blocks — only an eligible decision authorizes an act (fail toward protection; K-CCK, R-26, R-30). Platform-held; never edited or deleted.';
CREATE TRIGGER append_only BEFORE DELETE OR UPDATE ON public.collections_conditions FOR EACH ROW EXECUTE FUNCTION public.enforce_append_only();
ALTER TABLE public.collections_conditions ENABLE ALWAYS TRIGGER append_only;
CREATE TRIGGER no_truncate BEFORE TRUNCATE ON public.collections_conditions FOR EACH STATEMENT EXECUTE FUNCTION public.enforce_no_hard_delete();
ALTER TABLE public.collections_conditions ENABLE ALWAYS TRIGGER no_truncate;
REVOKE ALL ON public.collections_conditions FROM PUBLIC, tally_app, tally_core;
GRANT SELECT ON public.collections_conditions TO tally_app, tally_core;


-- ----------------------------------------------------------------------------
-- 2. The decision record (C2)
-- ----------------------------------------------------------------------------
-- One sequence orders the decisions and visits in recording order.
CREATE SEQUENCE public.collections_record_seq;

CREATE TABLE public.collections_decisions (
    id                      uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id               uuid NOT NULL,
    customer_id             uuid NOT NULL,
    act                     text NOT NULL,
    invoice_id              uuid,
    location_id             uuid,
    meter_id                uuid,
    evaluation_date         date NOT NULL,
    outcome                 text NOT NULL,
    active_conditions       text[] DEFAULT '{}' NOT NULL,
    unevaluable_conditions  text[] DEFAULT '{}' NOT NULL,
    governing_condition     text,
    valid_until             date,
    supersedes_id           uuid,
    inputs                  jsonb NOT NULL,
    inputs_fingerprint      text NOT NULL,
    calculated_by           text NOT NULL,
    record_seq              bigint,
    recorded_txid           bigint,
    created_at              timestamp with time zone DEFAULT now() NOT NULL,
    created_by              uuid,
    CONSTRAINT collections_decisions_pkey PRIMARY KEY (id),
    CONSTRAINT collections_decisions_id_tenant_id_key UNIQUE (id, tenant_id),
    CONSTRAINT collections_decisions_id_tenant_customer_key UNIQUE (id, tenant_id, customer_id),
    CONSTRAINT collections_decisions_customer_fkey FOREIGN KEY (customer_id, tenant_id) REFERENCES public.customers (id, tenant_id),
    CONSTRAINT collections_decisions_invoice_fkey FOREIGN KEY (invoice_id, tenant_id, customer_id) REFERENCES public.invoices (id, tenant_id, customer_id),
    CONSTRAINT collections_decisions_location_fkey FOREIGN KEY (location_id, tenant_id) REFERENCES public.service_locations (id, tenant_id),
    CONSTRAINT collections_decisions_meter_fkey FOREIGN KEY (meter_id, tenant_id) REFERENCES public.meters (id, tenant_id),
    CONSTRAINT collections_decisions_supersedes_fkey FOREIGN KEY (supersedes_id, tenant_id, customer_id)
        REFERENCES public.collections_decisions (id, tenant_id, customer_id),
    CONSTRAINT collections_decisions_created_by_fkey FOREIGN KEY (created_by, tenant_id) REFERENCES public.users (id, tenant_id),
    CONSTRAINT collections_decisions_act_check
        CHECK (act = ANY (ARRAY['notice', 'late_fee', 'disconnect_order', 'disconnect_execute', 'collections_referral'])),
    CONSTRAINT collections_decisions_outcome_check CHECK (outcome = ANY (ARRAY['eligible', 'blocked', 'unevaluable'])),
    CONSTRAINT collections_decisions_inputs_check CHECK (jsonb_typeof(inputs) = 'object' AND inputs_fingerprint ~ '[[:alnum:]]'),
    CONSTRAINT collections_decisions_calculated_by_check CHECK (calculated_by ~ '[[:alnum:]]')
);
CREATE INDEX idx_collections_decisions_subject ON public.collections_decisions (tenant_id, act, customer_id, record_seq);
CREATE INDEX idx_collections_decisions_supersedes ON public.collections_decisions (supersedes_id) WHERE supersedes_id IS NOT NULL;
CREATE INDEX idx_collections_decisions_invoice ON public.collections_decisions (invoice_id) WHERE invoice_id IS NOT NULL;
CREATE INDEX idx_collections_decisions_location ON public.collections_decisions (location_id) WHERE location_id IS NOT NULL;
COMMENT ON TABLE public.collections_decisions IS
    'v5.4.2-26 (C2-C6; CI-067, CI-069, CI-075). The core''s decision whether one collections act may happen: the act (notice, late_fee, disconnect_order, disconnect_execute, collections_referral), its subject at Kyle''s grain (CCK-7: a notice names its bill and the service location it threatens; a late fee and a referral, the bill; a disconnect, the location and optionally the meter), the evaluation date (the caller''s, never the database''s clock), the outcome (eligible, blocked, or unevaluable — which blocks: fail toward protection), every active condition and the one credited, every condition the core could not evaluate, the last day an eligible decision authorizes an act (valid_until, inclusive; an execute decision holds for its own day only), and its record: inputs, their fingerprint, the core version (calculated_by). Written by tally_app when the answer changes: one live decision per act and subject, a later one naming the one it supersedes; a re-run on the live decision''s date and facts is refused (idempotent, CI-075). The core evaluates; the database checks the record, never the rule (enforce_collections_decision). A blocked decision is the trace of the bypass that stopped an act. Add-only.';

DO $$ BEGIN
    ALTER TABLE public.collections_decisions ENABLE ROW LEVEL SECURITY;
    ALTER TABLE public.collections_decisions FORCE ROW LEVEL SECURITY;
    CREATE POLICY tenant_isolation ON public.collections_decisions USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())));
    CREATE TRIGGER a_stamp_created_at BEFORE INSERT ON public.collections_decisions FOR EACH ROW EXECUTE FUNCTION public.stamp_log_created_at();
    ALTER TABLE public.collections_decisions ENABLE ALWAYS TRIGGER a_stamp_created_at;
    CREATE TRIGGER append_only BEFORE DELETE OR UPDATE ON public.collections_decisions FOR EACH ROW EXECUTE FUNCTION public.enforce_append_only();
    ALTER TABLE public.collections_decisions ENABLE ALWAYS TRIGGER append_only;
    CREATE TRIGGER no_truncate BEFORE TRUNCATE ON public.collections_decisions FOR EACH STATEMENT EXECUTE FUNCTION public.enforce_no_hard_delete();
    ALTER TABLE public.collections_decisions ENABLE ALWAYS TRIGGER no_truncate;
    REVOKE ALL ON public.collections_decisions FROM PUBLIC, tally_app, tally_core;
    GRANT SELECT, INSERT ON public.collections_decisions TO tally_app;
    GRANT SELECT ON public.collections_decisions TO tally_core;
END $$;
REVOKE ALL ON SEQUENCE public.collections_record_seq FROM PUBLIC, tally_app, tally_core;
GRANT USAGE ON SEQUENCE public.collections_record_seq TO tally_app;


-- ----------------------------------------------------------------------------
-- 3. The helpers: tenancy, the subject's lock, the live decision, the act check
-- ----------------------------------------------------------------------------
-- The policy's own check comes after BEFORE triggers; a guard that reads
-- first would answer for a row the policy refuses. Another tenant's write is
-- refused as row security, before a guard reads anything for it.
CREATE OR REPLACE FUNCTION public.collections_tenant_check(p_table text, p_tenant_id uuid) RETURNS void
    LANGUAGE plpgsql STABLE
    SET search_path = public, pg_temp
    AS $$
BEGIN
    IF p_tenant_id IS NOT NULL AND NOT public.is_platform_admin() AND p_tenant_id IS DISTINCT FROM public.get_user_tenant_id()
       AND NOT coalesce((SELECT r.rolsuper OR r.rolbypassrls FROM pg_roles r WHERE r.rolname = current_user), false) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('new row violates row-level security policy for table "%s": a utility writes its own collections records only (v5.4.2-26)', p_table),
            ERRCODE = 'insufficient_privilege';
    END IF;
END;
$$;
COMMENT ON FUNCTION public.collections_tenant_check(text, uuid) IS
    'v5.4.2-26. Refuses (42501, as row security would) a field visit of another tenant than the session''s, before its guard reads the order (which the session could not see: the guard would answer "not found"). Decisions and approvals need none: nothing in their guards answers before the policy does. A platform admin, a superuser and a BYPASSRLS role pass.';
REVOKE ALL ON FUNCTION public.collections_tenant_check(text, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.collections_tenant_check(text, uuid) TO tally_app;

CREATE OR REPLACE FUNCTION public.collections_subject_lock(p_tenant_id uuid, p_act text, p_customer_id uuid, p_invoice_id uuid,
                                                           p_location_id uuid, p_meter_id uuid, p_what text) RETURNS void
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
BEGIN
    IF current_setting('transaction_isolation') <> 'read committed' THEN
        RAISE EXCEPTION USING
            MESSAGE = format('%s runs only under READ COMMITTED: the subject''s lock serializes its decisions and acts, and only READ COMMITTED reads what a writer it waited for committed (v5.4.2-26)', p_what),
            ERRCODE = 'invalid_transaction_state';
    END IF;
    -- r2 (Opus B2): the meter is not in the key. Every subject at one
    -- location (the location-wide one and each meter's) shares one lock, so an
    -- act reads all their live decisions with none in flight.
    PERFORM pg_advisory_xact_lock(hashtextextended(concat_ws('/', 'collections', p_tenant_id, p_act, p_customer_id,
                                                             coalesce(p_invoice_id::text, '-'), coalesce(p_location_id::text, '-')), 0));
END;
$$;
COMMENT ON FUNCTION public.collections_subject_lock(uuid, text, uuid, uuid, uuid, uuid, text) IS
    'v5.4.2-26. Refuses outside READ COMMITTED (25000); takes the advisory lock of a collections subject (tenant, act, customer, bill, location), held to commit: the mutex its decisions and the acts citing them share. The meter is not in the key: a location''s subjects, with and without a meter, share one lock (p_meter_id is accepted and ignored).';
REVOKE ALL ON FUNCTION public.collections_subject_lock(uuid, text, uuid, uuid, uuid, uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.collections_subject_lock(uuid, text, uuid, uuid, uuid, uuid, text) TO tally_app;

-- The live decision of a subject: the one no other supersedes.
CREATE OR REPLACE FUNCTION public.collections_live_decision(p_tenant_id uuid, p_act text, p_customer_id uuid, p_invoice_id uuid,
                                                            p_location_id uuid, p_meter_id uuid) RETURNS public.collections_decisions
    LANGUAGE sql STABLE
    SET search_path = public, pg_temp
    AS $$
    SELECT d.* FROM public.collections_decisions d
     WHERE d.tenant_id = p_tenant_id AND d.act = p_act AND d.customer_id = p_customer_id
       AND d.invoice_id IS NOT DISTINCT FROM p_invoice_id AND d.location_id IS NOT DISTINCT FROM p_location_id
       AND d.meter_id IS NOT DISTINCT FROM p_meter_id
     ORDER BY d.record_seq DESC LIMIT 1
$$;
COMMENT ON FUNCTION public.collections_live_decision(uuid, text, uuid, uuid, uuid, uuid) IS
    'v5.4.2-26. The live decision of a collections subject (act, customer, bill, location, meter), or NULL: the latest recorded, since each decision after the first supersedes the live one under the subject''s lock (C4). Invoker rights.';
REVOKE ALL ON FUNCTION public.collections_live_decision(uuid, text, uuid, uuid, uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.collections_live_decision(uuid, text, uuid, uuid, uuid, uuid) TO tally_app, tally_core;

-- C7. An act citing a decision: under the decision's subject lock, the
-- decision is for this act [A2], eligible [A3], live when the act is the
-- record itself [A4], for this subject [A5], and covers the act's date [A6].
-- p_invoice_id is compared for a bill act; p_location_id (and the meter, when
-- the decision names one) for a disconnect act when it is given — a dunning
-- line logging a disconnect act gives neither (its act's own record answers).
CREATE OR REPLACE FUNCTION public.collections_act_check(p_decision_id uuid, p_act text, p_invoice_id uuid, p_location_id uuid,
                                                        p_meter_id uuid, p_on date, p_live boolean, p_what text)
    RETURNS public.collections_decisions
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    d       public.collections_decisions%ROWTYPE;
    v_meter uuid;
    v_bad   text;
BEGIN
    SELECT * INTO d FROM public.collections_decisions x WHERE x.id = p_decision_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING
            MESSAGE = format('%s: collections decision %s not found (or not visible) (v5.4.2-26)', p_what, p_decision_id),
            ERRCODE = 'foreign_key_violation';
    END IF;
    PERFORM public.collections_subject_lock(d.tenant_id, d.act, d.customer_id, d.invoice_id, d.location_id, d.meter_id, p_what);
    IF d.act <> p_act THEN
        RAISE EXCEPTION USING
            MESSAGE = format('%s: decision %s decides %s, not %s [A2] (v5.4.2-26)', p_what, d.id, d.act, p_act),
            ERRCODE = 'check_violation';
    END IF;
    IF d.outcome <> 'eligible' THEN
        RAISE EXCEPTION USING
            MESSAGE = format('%s: decision %s is %s — only an eligible decision authorizes an act (an unevaluable one blocks) [A3] (v5.4.2-26)', p_what, d.id, d.outcome),
            ERRCODE = 'check_violation';
    END IF;
    IF p_live AND EXISTS (SELECT 1 FROM public.collections_decisions s WHERE s.supersedes_id = d.id) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('%s: decision %s is superseded — the act cites the live decision for its subject [A4] (v5.4.2-26)', p_what, d.id),
            ERRCODE = 'check_violation';
    END IF;
    IF d.act IN ('notice', 'late_fee', 'collections_referral') THEN
        IF p_invoice_id IS DISTINCT FROM d.invoice_id THEN
            RAISE EXCEPTION USING
                MESSAGE = format('%s: decision %s is about bill %s, not %s [A5] (v5.4.2-26)', p_what, d.id, d.invoice_id, coalesce(p_invoice_id::text, 'no bill')),
                ERRCODE = 'check_violation';
        END IF;
    ELSIF p_location_id IS NOT NULL THEN
        IF p_location_id IS DISTINCT FROM d.location_id OR (d.meter_id IS NOT NULL AND p_meter_id IS DISTINCT FROM d.meter_id) THEN
            RAISE EXCEPTION USING
                MESSAGE = format('%s: decision %s is about location %s%s, not location %s%s [A5] (v5.4.2-26)', p_what, d.id, d.location_id,
                                 coalesce(' meter ' || d.meter_id, ''), p_location_id, coalesce(' meter ' || p_meter_id, '')),
                ERRCODE = 'check_violation';
        END IF;
    END IF;
    IF p_on < d.evaluation_date OR p_on > d.valid_until THEN
        RAISE EXCEPTION USING
            MESSAGE = format('%s: dated %s, outside decision %s''s window %s to %s [A6] (v5.4.2-26)', p_what, p_on, d.id, d.evaluation_date, d.valid_until),
            ERRCODE = 'check_violation';
    END IF;
    IF p_live THEN
        -- A10 (r2, Opus B2; fail toward protection): no live decision at the
        -- location that covers this act — the location-wide one, or one for
        -- the act's meter — is blocked or unevaluable. All share the lock taken.
        IF d.location_id IS NOT NULL THEN
            v_meter := coalesce(p_meter_id, d.meter_id);
            SELECT string_agg(format('%s (%s%s)', l.id, l.outcome, coalesce(', meter ' || l.meter_id, ', the whole location')), '; ' ORDER BY l.id) INTO v_bad
              FROM (SELECT DISTINCT ON (x.meter_id) x.* FROM public.collections_decisions x
                     WHERE x.tenant_id = d.tenant_id AND x.act = d.act AND x.customer_id = d.customer_id
                       AND x.invoice_id IS NOT DISTINCT FROM d.invoice_id AND x.location_id = d.location_id
                     ORDER BY x.meter_id, x.record_seq DESC) l
             WHERE l.outcome <> 'eligible' AND (l.meter_id IS NULL OR v_meter IS NULL OR l.meter_id = v_meter);
            IF v_bad IS NOT NULL THEN
                RAISE EXCEPTION USING
                    MESSAGE = format('%s: decision %s is eligible, but the live decision for the same act at location %s covering it is not: %s — a block at the location binds every meter there [A10] (v5.4.2-26)',
                                     p_what, d.id, d.location_id, v_bad),
                    ERRCODE = 'check_violation';
            END IF;
        END IF;
        -- A11 (r2, Opus S6): a bill act's bill is not void.
        IF d.invoice_id IS NOT NULL AND EXISTS (SELECT 1 FROM public.invoices i WHERE i.id = d.invoice_id AND i.status = 'void') THEN
            RAISE EXCEPTION USING
                MESSAGE = format('%s: bill %s is void — no collections act rests on it [A11] (v5.4.2-26)', p_what, d.invoice_id),
                ERRCODE = 'check_violation';
        END IF;
    END IF;
    RETURN d;
END;
$$;
COMMENT ON FUNCTION public.collections_act_check(uuid, text, uuid, uuid, uuid, date, boolean, text) IS
    'v5.4.2-26 (C7). For an act citing a decision: reads the decision, takes its subject''s lock (READ COMMITTED; one lock per location, every meter''s subject included), then refuses unless it decides this act [A2], is eligible [A3], is live when p_live [A4], is about this bill (a bill act) or this location and meter (a disconnect act, when given) [A5], and its window covers p_on [A6]; when p_live (the act itself, not a log line), also unless every live decision for the same act at the location that covers the act (the location-wide one, and the one for its meter) is eligible [A10], and a bill act''s bill is not void [A11]. Returns the decision. The customer is the caller''s to compare where its row''s keys do not bind it (a field visit).';
REVOKE ALL ON FUNCTION public.collections_act_check(uuid, text, uuid, uuid, uuid, date, boolean, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.collections_act_check(uuid, text, uuid, uuid, uuid, date, boolean, text) TO tally_app;


-- ----------------------------------------------------------------------------
-- 4. The decision's guard (C3-C5)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.enforce_collections_decision() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_bill_act  boolean := NEW.act IN ('notice', 'late_fee', 'collections_referral');
    v_status    text;
    v_bill_loc  uuid;
    v_loc_cust  uuid;
    v_found     boolean;
    v_all       text[] := NEW.active_conditions || NEW.unevaluable_conditions;
    v_bad       text;
    live        public.collections_decisions%ROWTYPE;
BEGIN
    -- Another tenant's decision is row security's to refuse: nothing below
    -- answers for a row the session cannot see before the policy does.
    -- C3a the subject's shape (CCK-7).
    IF (v_bill_act AND NEW.invoice_id IS NULL)
       OR (NOT v_bill_act AND NEW.invoice_id IS NOT NULL)
       OR (NEW.act = 'notice' AND NEW.location_id IS NULL)
       OR (NEW.act IN ('late_fee', 'collections_referral') AND (NEW.location_id IS NOT NULL OR NEW.meter_id IS NOT NULL))
       OR (NOT v_bill_act AND NEW.location_id IS NULL) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('collections decision: a %s names %s [C3a] (v5.4.2-26)', NEW.act,
                             CASE NEW.act WHEN 'notice' THEN 'its bill and the service location it threatens (a meter optional)'
                                          WHEN 'late_fee' THEN 'its bill only' WHEN 'collections_referral' THEN 'its bill only'
                                          ELSE 'its service location (a meter optional) and no bill' END),
            ERRCODE = 'check_violation';
    END IF;
    PERFORM public.collections_subject_lock(NEW.tenant_id, NEW.act, NEW.customer_id, NEW.invoice_id, NEW.location_id, NEW.meter_id, 'a collections decision');

    -- C3b-C3e the subject's facts. Rows another tenant's or another
    -- customer's are the composite keys' to refuse.
    IF NEW.invoice_id IS NOT NULL THEN
        SELECT i.status, i.location_id INTO v_status, v_bill_loc FROM public.invoices i WHERE i.id = NEW.invoice_id;
        IF FOUND AND (NOT public.is_invoice_issued(v_status) OR v_status = 'void') THEN
            RAISE EXCEPTION USING
                MESSAGE = format('collections decision: bill %s is %s — collections decides on issued bills only, never a void one [C3b] (v5.4.2-26)', NEW.invoice_id, v_status),
                ERRCODE = 'check_violation';
        END IF;
    END IF;
    IF NEW.location_id IS NOT NULL THEN
        SELECT l.customer_id INTO v_loc_cust FROM public.service_locations l WHERE l.id = NEW.location_id;
        v_found := FOUND;
        IF v_found AND v_loc_cust IS DISTINCT FROM NEW.customer_id THEN
            RAISE EXCEPTION USING
                MESSAGE = format('collections decision: location %s is not customer %s''s [C3c] (v5.4.2-26)', NEW.location_id, NEW.customer_id),
                ERRCODE = 'check_violation';
        END IF;
        IF NEW.act = 'notice' AND v_bill_loc <> NEW.location_id THEN
            RAISE EXCEPTION USING
                MESSAGE = format('collections decision: a notice for bill %s threatens its own location %s, not %s [C3d] (v5.4.2-26)', NEW.invoice_id, v_bill_loc, NEW.location_id),
                ERRCODE = 'check_violation';
        END IF;
    END IF;
    IF NEW.meter_id IS NOT NULL AND NOT EXISTS (
           SELECT 1 FROM public.meter_deployments m
            WHERE m.meter_id = NEW.meter_id AND m.location_id = NEW.location_id
              AND daterange(m.install_date, m.removal_date, '[)') @> NEW.evaluation_date) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('collections decision: meter %s is not deployed at location %s on %s [C3e] (v5.4.2-26)', NEW.meter_id, NEW.location_id, NEW.evaluation_date),
            ERRCODE = 'check_violation';
    END IF;

    -- C3f the outcome's shape.
    IF (NEW.outcome = 'eligible' AND (cardinality(v_all) > 0 OR NEW.governing_condition IS NOT NULL
                                      OR NEW.valid_until IS NULL OR NEW.valid_until < NEW.evaluation_date))
       OR (NEW.outcome = 'blocked' AND (NEW.valid_until IS NOT NULL
                                        OR NOT coalesce(NEW.governing_condition = ANY (NEW.active_conditions), false)))
       OR (NEW.outcome = 'unevaluable' AND (cardinality(NEW.active_conditions) > 0 OR cardinality(NEW.unevaluable_conditions) = 0
                                            OR NEW.governing_condition IS NOT NULL OR NEW.valid_until IS NOT NULL)) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('collections decision: %s with active %s, unevaluable %s, credited %s, until %s — eligible names no condition and a last day from its evaluation date; blocked names an active condition and credits one of them; unevaluable names only what it could not evaluate; a non-eligible decision holds until the next [C3f] (v5.4.2-26)',
                             NEW.outcome, NEW.active_conditions, NEW.unevaluable_conditions, coalesce(NEW.governing_condition, 'none'), coalesce(NEW.valid_until::text, 'none')),
            ERRCODE = 'check_violation';
    END IF;
    -- C3g the vocabulary, no repeats (within either list).
    SELECT string_agg(c, ', ') INTO v_bad FROM unnest(v_all) c
     WHERE NOT EXISTS (SELECT 1 FROM public.collections_conditions k WHERE k.condition_code = c);
    IF v_bad IS NOT NULL
       OR cardinality(NEW.active_conditions) <> (SELECT count(DISTINCT c) FROM unnest(NEW.active_conditions) c)
       OR cardinality(NEW.unevaluable_conditions) <> (SELECT count(DISTINCT c) FROM unnest(NEW.unevaluable_conditions) c) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('collections decision: conditions come from collections_conditions, each once (%s) [C3g] (v5.4.2-26)', coalesce('unknown: ' || v_bad, 'one named twice')),
            ERRCODE = 'check_violation';
    END IF;
    -- C3h an execute decision holds for its own day (EWE is daily; no relying
    -- on an older evaluation at execution).
    IF NEW.act = 'disconnect_execute' AND NEW.outcome = 'eligible' AND NEW.valid_until <> NEW.evaluation_date THEN
        RAISE EXCEPTION USING
            MESSAGE = format('collections decision: an execute decision holds for its own day only (%s, not until %s) [C3h] (v5.4.2-26)', NEW.evaluation_date, NEW.valid_until),
            ERRCODE = 'check_violation';
    END IF;
    -- C3j no evaluation for a day that has not come.
    IF NEW.evaluation_date > (pg_catalog.now() AT TIME ZONE 'UTC')::date THEN
        RAISE EXCEPTION USING
            MESSAGE = format('collections decision: evaluated for %s, a day that has not come [C3j] (v5.4.2-26)', NEW.evaluation_date),
            ERRCODE = 'check_violation';
    END IF;

    -- C4, C5 one live decision per act and subject; idempotent against it.
    live := public.collections_live_decision(NEW.tenant_id, NEW.act, NEW.customer_id, NEW.invoice_id, NEW.location_id, NEW.meter_id);
    IF (NEW.supersedes_id IS NULL AND live.id IS NOT NULL)
       OR (NEW.supersedes_id IS NOT NULL AND live.id IS DISTINCT FROM NEW.supersedes_id) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('collections decision: the live decision for this %s is %s; a new decision names it as the one it supersedes [C4a] (v5.4.2-26)',
                             NEW.act, coalesce(live.id::text, 'none')),
            ERRCODE = 'check_violation';
    END IF;
    IF live.id IS NOT NULL AND NEW.evaluation_date < live.evaluation_date THEN
        RAISE EXCEPTION USING
            MESSAGE = format('collections decision: evaluated %s, before the live decision''s %s [C4b] (v5.4.2-26)', NEW.evaluation_date, live.evaluation_date),
            ERRCODE = 'check_violation';
    END IF;
    IF live.id IS NOT NULL AND NEW.evaluation_date = live.evaluation_date AND NEW.inputs_fingerprint = live.inputs_fingerprint THEN
        RAISE EXCEPTION USING
            MESSAGE = format('collections decision: decision %s already decided this on %s from the same facts (%s) — a re-run changes nothing [C5] (v5.4.2-26)',
                             live.id, live.evaluation_date, live.inputs_fingerprint),
            ERRCODE = 'check_violation';
    END IF;

    NEW.recorded_txid := txid_current();
    NEW.record_seq    := nextval('public.collections_record_seq');
    BEGIN
        NEW.created_by := NULLIF(current_setting('app.user_id', true), '')::uuid;
    EXCEPTION WHEN OTHERS THEN
        NEW.created_by := NULL;
    END;
    RETURN NEW;
END;
$$;
COMMENT ON FUNCTION public.enforce_collections_decision() IS
    'v5.4.2-26 (C3-C5). BEFORE INSERT on collections_decisions — record integrity, not evaluation (the core''s): the subject''s shape [C3a]; under the subject''s lock (READ COMMITTED): the bill issued [C3b], the location the customer''s [C3c] and a notice''s the bill''s own [C3d], a meter deployed there on the evaluation date [C3e]; the outcome''s shape [C3f]; conditions from the vocabulary, each once [C3g]; an eligible execute decision for its own day [C3h]; no future evaluation date (UTC) [C3j]; one live decision per subject — a first names nothing, a successor names the live one [C4a] and is evaluated no earlier [C4b]; the live decision''s date and fingerprint again is refused [C5]. Stamps created_by, recorded_txid and record_seq.';
REVOKE ALL ON FUNCTION public.enforce_collections_decision() FROM PUBLIC, tally_app, tally_core;
CREATE TRIGGER b_enforce_collections_decision BEFORE INSERT ON public.collections_decisions FOR EACH ROW EXECUTE FUNCTION public.enforce_collections_decision();
ALTER TABLE public.collections_decisions ENABLE ALWAYS TRIGGER b_enforce_collections_decision;


-- ----------------------------------------------------------------------------
-- 5. Field visits and approvals: tables (F1, F3)
-- ----------------------------------------------------------------------------
CREATE TABLE public.service_order_field_visits (
    id                          uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id                   uuid NOT NULL,
    service_order_id            uuid NOT NULL,
    arrived_at                  timestamp with time zone NOT NULL,
    captured_meter_serial       text,
    captured_location_number    text,
    expected_location_id        uuid,
    expected_location_number    text,
    expected_meter_id           uuid,
    expected_meter_serial       text,
    matched                     boolean DEFAULT false NOT NULL,
    outcome                     text NOT NULL,
    abort_reason                text,
    collections_decision_id     uuid,
    mismatch_approval_id        uuid,
    no_evidence_approval_id     uuid,
    evidence_refs               text[] DEFAULT '{}' NOT NULL,
    notes                       text,
    record_seq                  bigint,
    created_at                  timestamp with time zone DEFAULT now() NOT NULL,
    created_by                  uuid,
    CONSTRAINT service_order_field_visits_pkey PRIMARY KEY (id),
    CONSTRAINT service_order_field_visits_id_tenant_id_key UNIQUE (id, tenant_id),
    CONSTRAINT service_order_field_visits_order_fkey FOREIGN KEY (service_order_id, tenant_id) REFERENCES public.service_orders (id, tenant_id),
    CONSTRAINT service_order_field_visits_decision_fkey FOREIGN KEY (collections_decision_id, tenant_id) REFERENCES public.collections_decisions (id, tenant_id),
    CONSTRAINT service_order_field_visits_created_by_fkey FOREIGN KEY (created_by, tenant_id) REFERENCES public.users (id, tenant_id),
    CONSTRAINT service_order_field_visits_outcome_check
        CHECK (outcome = ANY (ARRAY['executed', 'aborted'])
               AND (outcome = 'aborted') = (abort_reason IS NOT NULL)
               AND (abort_reason IS NULL OR abort_reason = ANY (ARRAY['meter_mismatch', 'payment_shown', 'medical_evidence', 'dispute_pending',
                                                                       'no_access', 'safety', 'other']))
               AND (outcome = 'executed' OR (collections_decision_id IS NULL AND mismatch_approval_id IS NULL AND no_evidence_approval_id IS NULL)))
);
CREATE UNIQUE INDEX service_order_field_visits_one_executed ON public.service_order_field_visits (service_order_id) WHERE outcome = 'executed';
CREATE UNIQUE INDEX service_order_field_visits_one_per_decision ON public.service_order_field_visits (collections_decision_id) WHERE collections_decision_id IS NOT NULL;
CREATE INDEX idx_field_visits_order ON public.service_order_field_visits (service_order_id, record_seq);
CREATE INDEX idx_field_visits_tenant ON public.service_order_field_visits (tenant_id);
COMMENT ON TABLE public.service_order_field_visits IS
    'v5.4.2-26 (F1, F2; CI-071, D9-1, D3A-1). A visit to a disconnect order, add-only, written by the field tool through the same API as any third-party tool: when the tech arrived (the caller''s fact), the meter serial and service point captured on site (as observed), what the database expected — the order''s location and its number, the order''s meter or else the one meter deployed at the location on the arrival date — and whether they match (case and surrounding blanks aside, and the expected meter deployed there that day: the address matching while the meter drifted is a mismatch). Outcome executed, or aborted with a reason (PA 56.94''s reasons; tariff options for a Texas city). An execution captures both values, cites its execute decision (eligible, live, the order''s location, that day), and needs a match or a supervisor''s mismatch approval, and evidence or a supervisor''s no-evidence approval — each of its own order and kind; under a mismatch approval it captures what the approved visit saw. One execution per order and per decision.';

CREATE TABLE public.service_order_field_approvals (
    id                  uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tenant_id           uuid NOT NULL,
    service_order_id    uuid NOT NULL,
    kind                text NOT NULL,
    visit_id            uuid,
    reason_code         text NOT NULL,
    evidence_ref        text,
    approved_by         uuid NOT NULL,
    created_at          timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT service_order_field_approvals_pkey PRIMARY KEY (id),
    CONSTRAINT service_order_field_approvals_id_tenant_id_key UNIQUE (id, tenant_id),
    CONSTRAINT service_order_field_approvals_order_fkey FOREIGN KEY (service_order_id, tenant_id) REFERENCES public.service_orders (id, tenant_id),
    CONSTRAINT service_order_field_approvals_visit_fkey FOREIGN KEY (visit_id, tenant_id) REFERENCES public.service_order_field_visits (id, tenant_id),
    CONSTRAINT service_order_field_approvals_approved_by_fkey FOREIGN KEY (approved_by, tenant_id) REFERENCES public.users (id, tenant_id),
    CONSTRAINT service_order_field_approvals_kind_check CHECK (kind = ANY (ARRAY['meter_mismatch', 'no_evidence'])),
    CONSTRAINT service_order_field_approvals_reason_code_check CHECK (reason_code ~ '^[a-z][a-z0-9_]*$')
);
CREATE INDEX idx_field_approvals_order ON public.service_order_field_approvals (service_order_id);
CREATE INDEX idx_field_approvals_tenant ON public.service_order_field_approvals (tenant_id);
COMMENT ON TABLE public.service_order_field_approvals IS
    'v5.4.2-26 (F3; D9-1, CI-071, R-38 attachment 2). A supervisor''s approval to execute a disconnect order despite a meter mismatch or without photo evidence, add-only: the order (a disconnect), the kind, a reason code, and the approver — stamped by the database from the session, which must be a supervisor (session_is_supervisor: a tenant_admin or a platform admin). A mismatch approval names the aborted, unmatched visit whose mismatch it approves and an evidence reference (lifting a protection needs evidence); a no-evidence approval names no visit. Each belongs to one order, and an order has one execution, so an approval is used once.';

ALTER TABLE public.service_order_field_visits
    ADD CONSTRAINT service_order_field_visits_mismatch_approval_fkey
        FOREIGN KEY (mismatch_approval_id, tenant_id) REFERENCES public.service_order_field_approvals (id, tenant_id),
    ADD CONSTRAINT service_order_field_visits_no_evidence_approval_fkey
        FOREIGN KEY (no_evidence_approval_id, tenant_id) REFERENCES public.service_order_field_approvals (id, tenant_id);

DO $$
DECLARE
    t text;
BEGIN
    FOREACH t IN ARRAY ARRAY['service_order_field_visits', 'service_order_field_approvals'] LOOP
        EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);
        EXECUTE format('ALTER TABLE public.%I FORCE ROW LEVEL SECURITY', t);
        EXECUTE format('CREATE POLICY tenant_isolation ON public.%I USING ((public.is_platform_admin() OR (tenant_id = public.get_user_tenant_id())))', t);
        EXECUTE format('CREATE TRIGGER a_stamp_created_at BEFORE INSERT ON public.%I FOR EACH ROW EXECUTE FUNCTION public.stamp_log_created_at()', t);
        EXECUTE format('ALTER TABLE public.%I ENABLE ALWAYS TRIGGER a_stamp_created_at', t);
        EXECUTE format('CREATE TRIGGER append_only BEFORE DELETE OR UPDATE ON public.%I FOR EACH ROW EXECUTE FUNCTION public.enforce_append_only()', t);
        EXECUTE format('ALTER TABLE public.%I ENABLE ALWAYS TRIGGER append_only', t);
        EXECUTE format('CREATE TRIGGER no_truncate BEFORE TRUNCATE ON public.%I FOR EACH STATEMENT EXECUTE FUNCTION public.enforce_no_hard_delete()', t);
        EXECUTE format('ALTER TABLE public.%I ENABLE ALWAYS TRIGGER no_truncate', t);
        EXECUTE format('REVOKE ALL ON public.%I FROM PUBLIC, tally_app, tally_core', t);
        EXECUTE format('GRANT SELECT, INSERT ON public.%I TO tally_app', t);
        EXECUTE format('GRANT SELECT ON public.%I TO tally_core', t);
    END LOOP;
END $$;


-- ----------------------------------------------------------------------------
-- 6. The acts' columns and keys (C7, E1)
-- ----------------------------------------------------------------------------
ALTER TABLE public.dunning_events ADD COLUMN collections_decision_id uuid;
-- r2 (Codex B2): the recording order of a bill's events, by the database.
ALTER TABLE public.dunning_events ADD COLUMN record_seq bigint;
-- One composite key binds the bill, its tenant and its customer (E1); the
-- name is kept (-19's check reads it: no cascade).
ALTER TABLE public.dunning_events DROP CONSTRAINT dunning_events_invoice_id_fkey;
ALTER TABLE public.dunning_events
    ADD CONSTRAINT dunning_events_invoice_id_fkey FOREIGN KEY (invoice_id, tenant_id, customer_id) REFERENCES public.invoices (id, tenant_id, customer_id),
    ADD CONSTRAINT dunning_events_decision_fkey FOREIGN KEY (collections_decision_id, tenant_id, customer_id)
        REFERENCES public.collections_decisions (id, tenant_id, customer_id);
-- r2 (Fable S2): one step per decision and bill — a disconnection reaches
-- every bill of its customer that it rests on; a notice, a late fee and a
-- referral have one bill each.
CREATE UNIQUE INDEX dunning_events_one_per_decision ON public.dunning_events (collections_decision_id, invoice_id) WHERE collections_decision_id IS NOT NULL;
CREATE INDEX idx_dunning_events_bill_seq ON public.dunning_events (invoice_id, record_seq);
COMMENT ON COLUMN public.dunning_events.collections_decision_id IS
    'v5.4.2-26 (C7). The decision a gated step cites — shutoff_notice_sent (notice), late_fee_applied (late_fee), shutoff_scheduled (disconnect_order), disconnected (disconnect_execute), sent_to_collections (collections_referral) — and only those. A notice or a referral is the act: the live decision. A late fee, a scheduled shutoff and a disconnection are logged here after their own record (the charge, the order, the executed visit) cites the decision. One step per decision and bill (a disconnection is logged on each bill of its customer it rests on).';

ALTER TABLE public.adhoc_charges ADD COLUMN collections_decision_id uuid;
ALTER TABLE public.adhoc_charges
    ADD CONSTRAINT adhoc_charges_decision_fkey FOREIGN KEY (collections_decision_id, tenant_id, customer_id)
        REFERENCES public.collections_decisions (id, tenant_id, customer_id);
CREATE UNIQUE INDEX adhoc_charges_one_per_decision ON public.adhoc_charges (collections_decision_id) WHERE collections_decision_id IS NOT NULL;
COMMENT ON COLUMN public.adhoc_charges.collections_decision_id IS
    'v5.4.2-26 (C7). A late fee''s decision: the live, eligible late_fee decision for the bill it names (triggered_by_invoice_id), whose window covers its effective date. Required for a late fee, absent otherwise; written once, as is the late fee''s bill. One charge per decision.';

ALTER TABLE public.service_orders ADD COLUMN collections_decision_id uuid;
ALTER TABLE public.service_orders
    ADD CONSTRAINT service_orders_decision_fkey FOREIGN KEY (collections_decision_id, tenant_id, customer_id)
        REFERENCES public.collections_decisions (id, tenant_id, customer_id);
CREATE UNIQUE INDEX service_orders_one_per_decision ON public.service_orders (collections_decision_id) WHERE collections_decision_id IS NOT NULL;
COMMENT ON COLUMN public.service_orders.collections_decision_id IS
    'v5.4.2-26 (C7, F4). A disconnect order''s decision: the live, eligible disconnect_order decision for its location (and meter, when the decision names one) whose window covers the day the order is recorded. Required for a disconnect, absent otherwise; written once. One order per decision.';


-- ----------------------------------------------------------------------------
-- 7. The dunning guard and the stage (C7, E2)
-- ----------------------------------------------------------------------------
-- The act a dunning step is, when it is gated.
CREATE OR REPLACE FUNCTION public.collections_dunning_act(p_event_type text) RETURNS text
    LANGUAGE sql IMMUTABLE
    SET search_path = public, pg_temp
    AS $$
    SELECT CASE p_event_type WHEN 'shutoff_notice_sent' THEN 'notice' WHEN 'late_fee_applied' THEN 'late_fee'
                             WHEN 'shutoff_scheduled' THEN 'disconnect_order' WHEN 'disconnected' THEN 'disconnect_execute'
                             WHEN 'sent_to_collections' THEN 'collections_referral' END
$$;
COMMENT ON FUNCTION public.collections_dunning_act(text) IS
    'v5.4.2-26 (C7). The collections act a dunning step is, or NULL when the step is not gated (reminder_sent, reconnected, payment_plan_created, payment_plan_broken, written_off, resolved).';
REVOKE ALL ON FUNCTION public.collections_dunning_act(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.collections_dunning_act(text) TO tally_app, tally_core;

-- The stage a dunning step moves its bill to from the stage it is at (E2);
-- NULL moves nothing. r2 (Opus S1, Fable S1, Codex N2; settled by rule, plan
-- r2 item 6): the escalation steps move a bill only forward along the
-- ladder current -> reminder_sent -> late_fee_assessed -> shutoff_warning ->
-- shutoff_scheduled -> disconnected -> collections, so a repeat late fee
-- (a monthly penalty, Ryan 2026-11-22) or a later reminder leaves a bill
-- further along where it is. From a stage off the ladder (payment_plan,
-- resolved, written_off) an escalation step moves it to the step's stage:
-- collections resumed. A plan, a write-off and a resolution move as named.
CREATE OR REPLACE FUNCTION public.collections_dunning_stage(p_event_type text, p_from text) RETURNS text
    LANGUAGE sql IMMUTABLE
    SET search_path = public, pg_temp
    AS $$
    WITH t AS (
        SELECT CASE p_event_type WHEN 'reminder_sent' THEN 'reminder_sent' WHEN 'late_fee_applied' THEN 'late_fee_assessed'
                                 WHEN 'shutoff_notice_sent' THEN 'shutoff_warning' WHEN 'shutoff_scheduled' THEN 'shutoff_scheduled'
                                 WHEN 'disconnected' THEN 'disconnected' WHEN 'payment_plan_created' THEN 'payment_plan'
                                 WHEN 'sent_to_collections' THEN 'collections' WHEN 'written_off' THEN 'written_off'
                                 WHEN 'resolved' THEN 'resolved' END AS target,
               p_event_type IN ('reminder_sent', 'late_fee_applied', 'shutoff_notice_sent', 'shutoff_scheduled', 'disconnected', 'sent_to_collections') AS escalation,
               ARRAY['current', 'reminder_sent', 'late_fee_assessed', 'shutoff_warning', 'shutoff_scheduled', 'disconnected', 'collections'] AS ladder)
    SELECT CASE WHEN t.target IS NULL THEN NULL
                WHEN t.escalation AND array_position(t.ladder, p_from) >= array_position(t.ladder, t.target) THEN p_from
                ELSE t.target END
      FROM t
$$;
COMMENT ON FUNCTION public.collections_dunning_stage(text, text) IS
    'v5.4.2-26 (E2). The dunning stage a step moves its bill to from p_from: an escalation step (reminder, late fee, shutoff notice, shutoff scheduled, disconnected, referral) moves only forward along current -> reminder_sent -> late_fee_assessed -> shutoff_warning -> shutoff_scheduled -> disconnected -> collections (a repeat step on a bill further along leaves it there); from payment_plan, resolved or written_off it moves to the step''s stage; payment_plan_created, written_off and resolved move as named; reconnected and payment_plan_broken move none (no source says which stage follows them; residual R3).';
REVOKE ALL ON FUNCTION public.collections_dunning_stage(text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.collections_dunning_stage(text, text) TO tally_app, tally_core;

CREATE OR REPLACE FUNCTION public.enforce_dunning_event() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_act   text := public.collections_dunning_act(NEW.event_type);
    v_new   text;
    v_prev  text;
    v_log   boolean := NEW.event_type IN ('late_fee_applied', 'shutoff_scheduled', 'disconnected');
    d       public.collections_decisions%ROWTYPE;
BEGIN
    IF (v_act IS NULL) <> (NEW.collections_decision_id IS NULL) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('dunning event: %s %s [A1] (v5.4.2-26)', NEW.event_type,
                             CASE WHEN v_act IS NULL THEN 'is not a gated act and cites no decision' ELSE 'is a collections act and cites its decision (act ' || v_act || ')' END),
            ERRCODE = 'check_violation';
    END IF;
    IF v_act IS NOT NULL THEN
        d := public.collections_act_check(NEW.collections_decision_id, v_act, NEW.invoice_id, NULL, NULL,
                                          (NEW.event_date AT TIME ZONE 'UTC')::date, NOT v_log, 'dunning event ' || NEW.event_type);
        -- A8 a log line needs the act's own record.
        IF (NEW.event_type = 'late_fee_applied'
              AND NOT EXISTS (SELECT 1 FROM public.adhoc_charges c WHERE c.collections_decision_id = d.id AND c.status NOT IN ('void', 'waived', 'void_pending_rebill')))
           OR (NEW.event_type = 'shutoff_scheduled'
              AND NOT EXISTS (SELECT 1 FROM public.service_orders o WHERE o.collections_decision_id = d.id))
           OR (NEW.event_type = 'disconnected'
              AND NOT EXISTS (SELECT 1 FROM public.service_order_field_visits v WHERE v.collections_decision_id = d.id)) THEN
            RAISE EXCEPTION USING
                MESSAGE = format('dunning event: %s logs an act, and no %s cites decision %s [A8] (v5.4.2-26)', NEW.event_type,
                                 CASE NEW.event_type WHEN 'late_fee_applied' THEN 'standing (not void or waived) late-fee charge' WHEN 'shutoff_scheduled' THEN 'disconnect order'
                                                     ELSE 'executed field visit' END, d.id),
                ERRCODE = 'check_violation';
        END IF;
    END IF;

    -- E2 the stage: the bill's row is the stage's lock. The stage it is at is
    -- the latest stage-moving event's, read from the events (r2, Codex B2):
    -- the projection on the bill moves in an AFTER trigger, which an earlier
    -- row of the same statement has not yet run; the events it has inserted
    -- are visible here.
    PERFORM 1 FROM public.invoices i WHERE i.id = NEW.invoice_id FOR NO KEY UPDATE;
    SELECT e.new_stage INTO v_prev FROM public.dunning_events e
     WHERE e.invoice_id = NEW.invoice_id AND e.new_stage IS NOT NULL
     ORDER BY e.record_seq DESC LIMIT 1;
    v_prev := coalesce(v_prev, 'current');
    v_new  := public.collections_dunning_stage(NEW.event_type, v_prev);
    NEW.record_seq := nextval('public.collections_record_seq');
    IF v_new IS NULL THEN
        IF NEW.new_stage IS NOT NULL OR NEW.previous_stage IS NOT NULL THEN
            RAISE EXCEPTION USING
                MESSAGE = format('dunning event: %s moves no stage and names none [E2b] (v5.4.2-26)', NEW.event_type),
                ERRCODE = 'check_violation';
        END IF;
    ELSE
        IF NEW.new_stage IS DISTINCT FROM v_new AND NEW.new_stage IS NOT NULL
           OR NEW.previous_stage IS DISTINCT FROM v_prev AND NEW.previous_stage IS NOT NULL THEN
            RAISE EXCEPTION USING
                MESSAGE = format('dunning event: %s moves the bill from %s to %s, not from %s to %s [E2b] (v5.4.2-26)', NEW.event_type, v_prev, v_new,
                                 coalesce(NEW.previous_stage, '(any)'), coalesce(NEW.new_stage, '(any)')),
                ERRCODE = 'check_violation';
        END IF;
        NEW.previous_stage := v_prev;
        NEW.new_stage      := v_new;
    END IF;
    RETURN NEW;
END;
$$;
COMMENT ON FUNCTION public.enforce_dunning_event() IS
    'v5.4.2-26 (C7, E2). BEFORE INSERT on dunning_events: a gated step cites a decision and no other does [A1]; the decision is checked by collections_act_check on the event''s UTC date — live for a notice or a referral, which are the act; for late_fee_applied, shutoff_scheduled and disconnected, which log an act with its own record, that record (the late-fee charge, the disconnect order, the executed visit) cites the decision [A8]. Then, under the bill''s row lock, fills previous_stage and new_stage from collections_dunning_stage, refusing a caller''s that disagree [E2b]; z_dunning_move_stage moves the bill.';
REVOKE ALL ON FUNCTION public.enforce_dunning_event() FROM PUBLIC, tally_app, tally_core;
CREATE TRIGGER b_enforce_dunning_event BEFORE INSERT ON public.dunning_events FOR EACH ROW EXECUTE FUNCTION public.enforce_dunning_event();
ALTER TABLE public.dunning_events ENABLE ALWAYS TRIGGER b_enforce_dunning_event;

CREATE OR REPLACE FUNCTION public.dunning_move_stage() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
BEGIN
    IF NEW.new_stage IS NOT NULL THEN
        UPDATE public.invoices SET dunning_stage = NEW.new_stage WHERE id = NEW.invoice_id;
    END IF;
    RETURN NULL;
END;
$$;
COMMENT ON FUNCTION public.dunning_move_stage() IS
    'v5.4.2-26 (E2). AFTER INSERT on dunning_events: moves the bill''s dunning_stage to the event''s new_stage (the guard filled it). The only writer of invoices.dunning_stage (enforce_dunning_stage_projection fences every other).';
REVOKE ALL ON FUNCTION public.dunning_move_stage() FROM PUBLIC, tally_app, tally_core;
CREATE TRIGGER z_dunning_move_stage AFTER INSERT ON public.dunning_events FOR EACH ROW EXECUTE FUNCTION public.dunning_move_stage();
ALTER TABLE public.dunning_events ENABLE ALWAYS TRIGGER z_dunning_move_stage;

-- E2 the stage is written only by the move (a trigger at depth 1 updating
-- the bill: depth 2 here; memory trigger-depth-fence-inside-guard).
CREATE OR REPLACE FUNCTION public.enforce_dunning_stage_projection() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
BEGIN
    IF pg_trigger_depth() < 2
       AND ((TG_OP = 'INSERT' AND NEW.dunning_stage IS DISTINCT FROM 'current')
            OR (TG_OP = 'UPDATE' AND NEW.dunning_stage IS DISTINCT FROM OLD.dunning_stage)) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('bill %s: dunning_stage is the database''s — it moves when a dunning event is recorded; a bill is born at current [E2a] (v5.4.2-26)', NEW.id),
            ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$;
COMMENT ON FUNCTION public.enforce_dunning_stage_projection() IS
    'v5.4.2-26 (E2). BEFORE INSERT OR UPDATE OF dunning_stage on invoices, for every role: a bill is born at current, and its stage changes only from dunning_move_stage (trigger depth 2) [E2a]. A trigger-depth fence: it holds while tally_app can define no code (residual R5).';
REVOKE ALL ON FUNCTION public.enforce_dunning_stage_projection() FROM PUBLIC, tally_app, tally_core;
CREATE TRIGGER a_enforce_dunning_stage_projection BEFORE INSERT OR UPDATE OF dunning_stage ON public.invoices
    FOR EACH ROW EXECUTE FUNCTION public.enforce_dunning_stage_projection();
ALTER TABLE public.invoices ENABLE ALWAYS TRIGGER a_enforce_dunning_stage_projection;
COMMENT ON COLUMN public.invoices.dunning_stage IS
    'Collections stage. v5.4.2-26: the database''s — the stage of the latest stage-moving dunning event (collections_dunning_stage), moved by dunning_move_stage; a bill is born at current and no one writes it directly.';

-- E3 the late-fee counters go: a bill''s late fees are its late_fee charges.
ALTER TABLE public.invoices DROP COLUMN late_fee_assessed, DROP COLUMN late_fee_amount;


-- ----------------------------------------------------------------------------
-- 8. Late-fee charges (C7)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.enforce_adhoc_charge_decision() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
BEGIN
    IF TG_OP = 'UPDATE' THEN
        IF NEW.collections_decision_id IS DISTINCT FROM OLD.collections_decision_id
           OR (OLD.collections_decision_id IS NOT NULL AND NEW.triggered_by_invoice_id IS DISTINCT FROM OLD.triggered_by_invoice_id)
           OR (NEW.charge_type IN ('late_fee', 'penalty')) <> (OLD.charge_type IN ('late_fee', 'penalty')) THEN
            RAISE EXCEPTION USING
                MESSAGE = format('charge %s: a late fee''s decision and bill are written once, and no charge becomes or stops being a late fee [A9] (v5.4.2-26)', NEW.id),
                ERRCODE = 'check_violation';
        END IF;
        RETURN NEW;
    END IF;
    -- r2 (Opus S2, guard-the-act-not-the-label): a late fee is gated under
    -- either name a charge can carry for it.
    IF (NEW.charge_type IN ('late_fee', 'penalty')) <> (NEW.collections_decision_id IS NOT NULL) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('charge %s: %s [A1] (v5.4.2-26)', NEW.charge_number,
                             CASE WHEN NEW.charge_type IN ('late_fee', 'penalty') THEN 'a late fee or penalty cites its late_fee decision' ELSE 'only a late fee or penalty cites a collections decision' END),
            ERRCODE = 'check_violation';
    END IF;
    IF NEW.collections_decision_id IS NOT NULL THEN
        PERFORM public.collections_act_check(NEW.collections_decision_id, 'late_fee', NEW.triggered_by_invoice_id, NULL, NULL,
                                             NEW.effective_date, true, 'late-fee charge ' || NEW.charge_number);
    END IF;
    RETURN NEW;
END;
$$;
COMMENT ON FUNCTION public.enforce_adhoc_charge_decision() IS
    'v5.4.2-26 (C7). BEFORE INSERT OR UPDATE OF collections_decision_id, triggered_by_invoice_id on adhoc_charges: a late fee or penalty (charge_type late_fee or penalty) cites its decision and no other charge does [A1]; the decision is the live, eligible late_fee decision for the bill the charge names, covering its effective date (collections_act_check); once cited, the decision and the bill are written once [A9].';
REVOKE ALL ON FUNCTION public.enforce_adhoc_charge_decision() FROM PUBLIC, tally_app, tally_core;
CREATE TRIGGER a_enforce_adhoc_charge_decision BEFORE INSERT OR UPDATE OF collections_decision_id, triggered_by_invoice_id, charge_type ON public.adhoc_charges
    FOR EACH ROW EXECUTE FUNCTION public.enforce_adhoc_charge_decision();
ALTER TABLE public.adhoc_charges ENABLE ALWAYS TRIGGER a_enforce_adhoc_charge_decision;

-- r2 (Opus S2, Fable note): a late fee reaches a bill only as the line of
-- its late-fee charge, never as a bare line.
CREATE OR REPLACE FUNCTION public.enforce_late_fee_line() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
BEGIN
    IF NEW.charge_type IN ('late_fee', 'penalty') AND NOT EXISTS (
           SELECT 1 FROM public.adhoc_charges c JOIN public.invoices i ON i.id = NEW.invoice_id
            WHERE c.id = NEW.adhoc_charge_id AND c.collections_decision_id IS NOT NULL
              AND c.tenant_id = NEW.tenant_id AND c.customer_id = i.customer_id) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('bill line on bill %s: a %s line bills its late-fee charge (adhoc_charge_id), which cites its late_fee decision; %s does not [A1] (v5.4.2-26)',
                             NEW.invoice_id, NEW.charge_type, coalesce(NEW.adhoc_charge_id::text, 'no charge')),
            ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$;
COMMENT ON FUNCTION public.enforce_late_fee_line() IS
    'v5.4.2-26 (C7, r2). BEFORE INSERT OR UPDATE OF charge_type, adhoc_charge_id, invoice_id on invoice_line_items: a late_fee or penalty line names its late-fee charge (adhoc_charge_id), one of the bill''s customer that cites a late_fee decision [A1]. A late fee reaches a bill only through its gated charge.';
REVOKE ALL ON FUNCTION public.enforce_late_fee_line() FROM PUBLIC, tally_app, tally_core;
CREATE TRIGGER a_enforce_late_fee_line BEFORE INSERT OR UPDATE OF charge_type, adhoc_charge_id, invoice_id ON public.invoice_line_items
    FOR EACH ROW EXECUTE FUNCTION public.enforce_late_fee_line();
ALTER TABLE public.invoice_line_items ENABLE ALWAYS TRIGGER a_enforce_late_fee_line;


-- ----------------------------------------------------------------------------
-- 9. Disconnect orders (C7, F4)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.enforce_disconnect_order() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_executed boolean;
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF (NEW.order_type = 'disconnect') <> (NEW.collections_decision_id IS NOT NULL) THEN
            RAISE EXCEPTION USING
                MESSAGE = format('service order %s: %s [A1] (v5.4.2-26)', NEW.order_number,
                                 CASE WHEN NEW.order_type = 'disconnect' THEN 'a disconnect order cites its disconnect_order decision' ELSE 'only a disconnect order cites a collections decision' END),
                ERRCODE = 'check_violation';
        END IF;
        IF NEW.order_type = 'disconnect' THEN
            IF NEW.status = 'completed' THEN
                RAISE EXCEPTION USING
                    MESSAGE = format('service order %s: a disconnect order is completed only by an executed field visit, never born completed [F4e] (v5.4.2-26)', NEW.order_number),
                    ERRCODE = 'check_violation';
            END IF;
            PERFORM public.collections_act_check(NEW.collections_decision_id, 'disconnect_order', NULL, NEW.location_id, NEW.meter_id,
                                                 (pg_catalog.now() AT TIME ZONE 'UTC')::date, true, 'disconnect order ' || NEW.order_number);
        END IF;
        RETURN NEW;
    END IF;

    -- UPDATE
    IF NEW.collections_decision_id IS DISTINCT FROM OLD.collections_decision_id
       OR ((OLD.order_type = 'disconnect' OR NEW.order_type = 'disconnect')
           AND (NEW.order_type, NEW.customer_id, NEW.location_id, NEW.meter_id, NEW.tenant_id)
               IS DISTINCT FROM (OLD.order_type, OLD.customer_id, OLD.location_id, OLD.meter_id, OLD.tenant_id)) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('service order %s: a disconnect order''s type, customer, location, meter and decision are written once, and no order becomes or stops being one [F4a] (v5.4.2-26)', NEW.order_number),
            ERRCODE = 'check_violation';
    END IF;
    IF NEW.order_type = 'disconnect' AND NEW.status IS DISTINCT FROM OLD.status THEN
        -- r2 (Fable B1, Opus B3, Codex B3): the check for an executed visit
        -- below must read what a visit it waited for committed — only READ
        -- COMMITTED does. A visit holds the order FOR SHARE until it commits.
        IF current_setting('transaction_isolation') <> 'read committed' THEN
            RAISE EXCEPTION USING
                MESSAGE = format('service order %s: a disconnect order''s status changes only under READ COMMITTED, so it reads a field visit that just executed it [F4f] (v5.4.2-26)', NEW.order_number),
                ERRCODE = 'invalid_transaction_state';
        END IF;
        IF OLD.status = 'completed' THEN
            RAISE EXCEPTION USING
                MESSAGE = format('service order %s: a completed disconnect order stays completed [F4c] (v5.4.2-26)', NEW.order_number),
                ERRCODE = 'check_violation';
        END IF;
        v_executed := EXISTS (SELECT 1 FROM public.service_order_field_visits v WHERE v.service_order_id = NEW.id AND v.outcome = 'executed');
        IF v_executed AND NEW.status <> 'completed' THEN
            RAISE EXCEPTION USING
                MESSAGE = format('service order %s: a field visit executed it — it can only be completed, not %s [F4d] (v5.4.2-26)', NEW.order_number, NEW.status),
                ERRCODE = 'check_violation';
        END IF;
        IF NOT v_executed AND NEW.status = 'completed' THEN
            RAISE EXCEPTION USING
                MESSAGE = format('service order %s: a disconnect order is completed only by an executed field visit [F4b] (v5.4.2-26)', NEW.order_number),
                ERRCODE = 'check_violation';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;
COMMENT ON FUNCTION public.enforce_disconnect_order() IS
    'v5.4.2-26 (C7, F4). BEFORE INSERT OR UPDATE on service_orders. Insert: a disconnect order cites its decision and no other order does [A1]; it is never born completed [F4e]; the decision is the live, eligible disconnect_order decision for its location (and meter, when the decision names one), covering the day it is recorded (collections_act_check). Update: the decision is written once, and a disconnect order''s type, customer, location and meter too — no order becomes or stops being one [F4a]; a completed disconnect order stays completed [F4c]; once a field visit executed it, it can only be completed [F4d]; it is completed only with an executed visit [F4b]; a status change runs under READ COMMITTED (25000) [F4f]. Dispatch moves before execution are free.';
REVOKE ALL ON FUNCTION public.enforce_disconnect_order() FROM PUBLIC, tally_app, tally_core;
CREATE TRIGGER a_enforce_disconnect_order BEFORE INSERT OR UPDATE ON public.service_orders
    FOR EACH ROW EXECUTE FUNCTION public.enforce_disconnect_order();
ALTER TABLE public.service_orders ENABLE ALWAYS TRIGGER a_enforce_disconnect_order;


-- ----------------------------------------------------------------------------
-- 10. Field visits and approvals: guards (F1-F3)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.enforce_field_visit() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    o           public.service_orders%ROWTYPE;
    d           public.collections_decisions%ROWTYPE;
    a           public.service_order_field_approvals%ROWTYPE;
    av          public.service_order_field_visits%ROWTYPE;
    v_on        date := (NEW.arrived_at AT TIME ZONE 'UTC')::date;
    v_meter     uuid;
    v_ids       uuid[];
BEGIN
    PERFORM public.collections_tenant_check('service_order_field_visits', NEW.tenant_id);
    SELECT * INTO o FROM public.service_orders x WHERE x.id = NEW.service_order_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING
            MESSAGE = format('field visit: service order %s not found (or not visible) (v5.4.2-26)', NEW.service_order_id),
            ERRCODE = 'foreign_key_violation';
    END IF;
    IF o.order_type <> 'disconnect' THEN
        RAISE EXCEPTION USING
            MESSAGE = format('field visit: order %s is a %s — field verification records visits to disconnect orders [F1a] (v5.4.2-26)', o.order_number, o.order_type),
            ERRCODE = 'check_violation';
    END IF;
    IF NEW.outcome = 'executed' THEN
        IF NEW.collections_decision_id IS NULL THEN
            RAISE EXCEPTION USING
                MESSAGE = format('field visit: an execution of order %s cites its disconnect_execute decision [A1] (v5.4.2-26)', o.order_number),
                ERRCODE = 'check_violation';
        END IF;
        d := public.collections_act_check(NEW.collections_decision_id, 'disconnect_execute', NULL, o.location_id, o.meter_id,
                                          v_on, true, 'execution of order ' || o.order_number);
        -- r2 (Opus B1, Codex B1): the decision is for the order's customer.
        -- The visit's keys bind the order and the decision to the tenant
        -- only, and a location can change customer.
        IF d.customer_id IS DISTINCT FROM o.customer_id THEN
            RAISE EXCEPTION USING
                MESSAGE = format('execution of order %s: decision %s is customer %s''s, the order customer %s''s [A5] (v5.4.2-26)', o.order_number, d.id, d.customer_id, o.customer_id),
                ERRCODE = 'check_violation';
        END IF;
        -- r2 (Opus S3): an execution is not dated before its order or its
        -- decision was recorded, nor in the future.
        IF NEW.arrived_at < o.created_at OR NEW.arrived_at < d.created_at OR NEW.arrived_at > pg_catalog.now() THEN
            RAISE EXCEPTION USING
                MESSAGE = format('execution of order %s: arrived %s, before the order (%s) or its decision (%s) was recorded, or in the future [F2f] (v5.4.2-26)',
                                 o.order_number, NEW.arrived_at, o.created_at, d.created_at),
                ERRCODE = 'check_violation';
        END IF;
    END IF;
    -- The order's row (FOR SHARE: a status update of the order waits for this
    -- visit, and this visit for it), then its status.
    SELECT * INTO o FROM public.service_orders x WHERE x.id = NEW.service_order_id FOR SHARE;
    IF o.status IN ('completed', 'cancelled', 'superseded') THEN
        RAISE EXCEPTION USING
            MESSAGE = format('field visit: order %s is %s [F1b] (v5.4.2-26)', o.order_number, o.status),
            ERRCODE = 'check_violation';
    END IF;

    -- F1 what was expected, and whether it matches: the database's.
    IF o.meter_id IS NOT NULL THEN
        v_meter := o.meter_id;
    ELSE
        SELECT array_agg(m.meter_id) INTO v_ids FROM public.meter_deployments m
         WHERE m.location_id = o.location_id AND daterange(m.install_date, m.removal_date, '[)') @> v_on;
        v_meter := CASE WHEN cardinality(v_ids) = 1 THEN v_ids[1] END;
    END IF;
    NEW.expected_location_id     := o.location_id;
    NEW.expected_location_number := (SELECT l.location_number FROM public.service_locations l WHERE l.id = o.location_id);
    NEW.expected_meter_id        := v_meter;
    NEW.expected_meter_serial    := (SELECT m.serial_number FROM public.meters m WHERE m.id = v_meter);
    NEW.matched := coalesce(v_meter IS NOT NULL
                            AND EXISTS (SELECT 1 FROM public.meter_deployments m
                                         WHERE m.meter_id = v_meter AND m.location_id = o.location_id
                                           AND daterange(m.install_date, m.removal_date, '[)') @> v_on)
                            AND upper(btrim(NEW.captured_meter_serial)) = upper(btrim(NEW.expected_meter_serial))
                            AND upper(btrim(NEW.captured_location_number)) = upper(btrim(NEW.expected_location_number)), false);
    IF EXISTS (SELECT 1 FROM unnest(NEW.evidence_refs) r WHERE r IS NULL OR r !~ '[[:alnum:]]') THEN
        RAISE EXCEPTION USING
            MESSAGE = 'field visit: an evidence reference is blank [F1e] (v5.4.2-26)',
            ERRCODE = 'check_violation';
    END IF;

    -- F2, F3 an execution's needs.
    IF NEW.outcome = 'executed' THEN
        -- r2 (Fable S3): a captured value has an alphanumeric character.
        IF NOT coalesce(NEW.captured_meter_serial ~ '[[:alnum:]]' AND NEW.captured_location_number ~ '[[:alnum:]]', false) THEN
            RAISE EXCEPTION USING
                MESSAGE = format('field visit: an execution of order %s records the serial and service point captured on site (CI-071) [F2e] (v5.4.2-26)', o.order_number),
                ERRCODE = 'check_violation';
        END IF;
        -- r2 (Codex S1, Fable S6): an approval is named only where needed.
        IF (NEW.matched AND NEW.mismatch_approval_id IS NOT NULL)
           OR (cardinality(NEW.evidence_refs) > 0 AND NEW.no_evidence_approval_id IS NOT NULL) THEN
            RAISE EXCEPTION USING
                MESSAGE = format('field visit: an execution of order %s names an approval it does not need (a mismatch approval on a match, or a no-evidence approval with evidence) [F3e] (v5.4.2-26)', o.order_number),
                ERRCODE = 'check_violation';
        END IF;
        IF NOT NEW.matched THEN
            IF NEW.mismatch_approval_id IS NULL THEN
                RAISE EXCEPTION USING
                    MESSAGE = format('field visit: %s / %s captured, %s / %s expected — a mismatch halts the disconnect unless a supervisor approves it [F2b] (v5.4.2-26)',
                                     NEW.captured_meter_serial, NEW.captured_location_number, coalesce(NEW.expected_meter_serial, 'no single meter'), NEW.expected_location_number),
                    ERRCODE = 'check_violation';
            END IF;
            SELECT * INTO a FROM public.service_order_field_approvals x WHERE x.id = NEW.mismatch_approval_id;
            IF NOT FOUND OR a.service_order_id <> o.id OR a.kind <> 'meter_mismatch' THEN
                RAISE EXCEPTION USING
                    MESSAGE = format('field visit: approval %s is not a mismatch approval of order %s [F3d] (v5.4.2-26)', NEW.mismatch_approval_id, o.order_number),
                    ERRCODE = 'check_violation';
            END IF;
            SELECT * INTO av FROM public.service_order_field_visits x WHERE x.id = a.visit_id;
            IF upper(btrim(av.captured_meter_serial)) IS DISTINCT FROM upper(btrim(NEW.captured_meter_serial))
               OR upper(btrim(av.captured_location_number)) IS DISTINCT FROM upper(btrim(NEW.captured_location_number)) THEN
                RAISE EXCEPTION USING
                    MESSAGE = format('field visit: approval %s approved executing against %s / %s, not %s / %s [F3c] (v5.4.2-26)', a.id,
                                     av.captured_meter_serial, av.captured_location_number, NEW.captured_meter_serial, NEW.captured_location_number),
                    ERRCODE = 'check_violation';
            END IF;
        END IF;
        IF cardinality(NEW.evidence_refs) = 0 THEN
            IF NEW.no_evidence_approval_id IS NULL THEN
                RAISE EXCEPTION USING
                    MESSAGE = format('field visit: an execution of order %s with no evidence needs a supervisor''s approval (D9-1) [F2c] (v5.4.2-26)', o.order_number),
                    ERRCODE = 'check_violation';
            END IF;
            SELECT * INTO a FROM public.service_order_field_approvals x WHERE x.id = NEW.no_evidence_approval_id;
            IF NOT FOUND OR a.service_order_id <> o.id OR a.kind <> 'no_evidence' THEN
                RAISE EXCEPTION USING
                    MESSAGE = format('field visit: approval %s is not a no-evidence approval of order %s [F3d] (v5.4.2-26)', NEW.no_evidence_approval_id, o.order_number),
                    ERRCODE = 'check_violation';
            END IF;
        END IF;
    END IF;

    NEW.record_seq := nextval('public.collections_record_seq');
    BEGIN
        NEW.created_by := NULLIF(current_setting('app.user_id', true), '')::uuid;
    EXCEPTION WHEN OTHERS THEN
        NEW.created_by := NULL;
    END;
    RETURN NEW;
END;
$$;
COMMENT ON FUNCTION public.enforce_field_visit() IS
    'v5.4.2-26 (F1-F3; C7). BEFORE INSERT on service_order_field_visits: the writer''s own tenant; a disconnect order [F1a]; an execution cites its decision [A1], checked by collections_act_check against the order''s location and meter on the arrival''s UTC date (live, eligible, that day); then under the order''s row (FOR SHARE) the order is open [F1b]. Fills the expectation (the order''s location and number; its meter, or the one meter deployed there that day) and the match (both captured values, case and blanks aside, and the expected meter deployed there that day), overwriting any the caller gave; no blank evidence reference [F1e]. An execution captures both values, each with an alphanumeric character [F2e], cites a decision for the order''s customer [A5], and is dated no earlier than its order and its decision were recorded and not in the future [F2f]; on a mismatch it names a mismatch approval [F2b] of its order [F3d] and captures what the approved visit saw [F3c]; with no evidence, a no-evidence approval [F2c] of its order [F3d]; it names no approval it does not need [F3e]. Stamps created_by and record_seq.';
REVOKE ALL ON FUNCTION public.enforce_field_visit() FROM PUBLIC, tally_app, tally_core;
CREATE TRIGGER b_enforce_field_visit BEFORE INSERT ON public.service_order_field_visits FOR EACH ROW EXECUTE FUNCTION public.enforce_field_visit();
ALTER TABLE public.service_order_field_visits ENABLE ALWAYS TRIGGER b_enforce_field_visit;

CREATE OR REPLACE FUNCTION public.enforce_field_approval() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
DECLARE
    o       public.service_orders%ROWTYPE;
    v       public.service_order_field_visits%ROWTYPE;
    v_user  uuid;
BEGIN
    -- Another tenant's approval is row security's to refuse.
    -- r2 (Opus B4, Fable S4, Codex S2; R-12, the Tally User ruling of
    -- 2026-11-07): the approver is a tenant_admin of the order's own utility —
    -- Tally staff act through that utility's Tally User, never as themselves.
    BEGIN
        v_user := NULLIF(current_setting('app.user_id', true), '')::uuid;
    EXCEPTION WHEN OTHERS THEN
        v_user := NULL;
    END;
    IF NOT EXISTS (SELECT 1 FROM public.users u WHERE u.id = v_user AND u.tenant_id = NEW.tenant_id AND u.role = 'tenant_admin' AND u.is_active) THEN
        RAISE EXCEPTION USING
            MESSAGE = 'field approval: only a supervisor of the order''s own utility (its tenant_admin, Tally staff through its Tally User) approves a disconnect on a mismatch or without evidence (D9-1) [F3a] (v5.4.2-26)',
            ERRCODE = 'insufficient_privilege';
    END IF;
    SELECT * INTO o FROM public.service_orders x WHERE x.id = NEW.service_order_id;
    IF FOUND AND o.order_type <> 'disconnect' THEN
        RAISE EXCEPTION USING
            MESSAGE = format('field approval: order %s is a %s, not a disconnect [F3b] (v5.4.2-26)', o.order_number, o.order_type),
            ERRCODE = 'check_violation';
    END IF;
    IF NEW.kind = 'meter_mismatch' THEN
        SELECT * INTO v FROM public.service_order_field_visits x WHERE x.id = NEW.visit_id;
        IF NOT FOUND OR v.service_order_id IS DISTINCT FROM NEW.service_order_id OR v.outcome <> 'aborted' OR v.matched
           OR NOT coalesce(NEW.evidence_ref ~ '[[:alnum:]]', false) THEN
            RAISE EXCEPTION USING
                MESSAGE = format('field approval: a mismatch approval names the aborted, unmatched visit of order %s whose mismatch it approves, and an evidence reference (R-38) [F3b] (v5.4.2-26)', o.order_number),
                ERRCODE = 'check_violation';
        END IF;
    ELSIF NEW.visit_id IS NOT NULL THEN
        RAISE EXCEPTION USING
            MESSAGE = 'field approval: a no-evidence approval names no visit [F3b] (v5.4.2-26)',
            ERRCODE = 'check_violation';
    END IF;
    NEW.approved_by := v_user;
    RETURN NEW;
END;
$$;
COMMENT ON FUNCTION public.enforce_field_approval() IS
    'v5.4.2-26 (F3). BEFORE INSERT on service_order_field_approvals: the session''s user (app.user_id) is an active tenant_admin of the order''s own utility [F3a] — a platform administrator acts through the utility''s Tally User (Ryan 2026-11-07), never as themselves; the order is a disconnect; a mismatch approval names the aborted, unmatched visit of its order and an evidence reference; a no-evidence approval names no visit [F3b]. Stamps approved_by from the session (the caller''s value is overwritten).';
REVOKE ALL ON FUNCTION public.enforce_field_approval() FROM PUBLIC, tally_app, tally_core;
CREATE TRIGGER b_enforce_field_approval BEFORE INSERT ON public.service_order_field_approvals FOR EACH ROW EXECUTE FUNCTION public.enforce_field_approval();
ALTER TABLE public.service_order_field_approvals ENABLE ALWAYS TRIGGER b_enforce_field_approval;


-- ----------------------------------------------------------------------------
-- 11. do_not_disconnect follows the enrollments (E4)
-- ----------------------------------------------------------------------------
-- recompute_do_not_disconnect (AFTER on enrollments, depth 1) updates the
-- customer: depth 2 here. Anything at depth 1 is a direct write.
CREATE OR REPLACE FUNCTION public.enforce_do_not_disconnect_projection() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
BEGIN
    IF pg_trigger_depth() < 2
       AND ((TG_OP = 'INSERT' AND NEW.do_not_disconnect)
            OR (TG_OP = 'UPDATE' AND NEW.do_not_disconnect IS DISTINCT FROM OLD.do_not_disconnect)) THEN
        RAISE EXCEPTION USING
            MESSAGE = format('customer %s: do_not_disconnect follows the customer''s protective program enrollments — enroll or end one; it is never written directly [E4] (v5.4.2-26)', NEW.id),
            ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$;
COMMENT ON FUNCTION public.enforce_do_not_disconnect_projection() IS
    'v5.4.2-26 (E4). BEFORE INSERT OR UPDATE OF do_not_disconnect on customers, for every role: a customer is born unprotected, and the flag changes only from recompute_do_not_disconnect (trigger depth 2) [E4]. A trigger-depth fence: it holds while tally_app can define no code (residual R5).';
REVOKE ALL ON FUNCTION public.enforce_do_not_disconnect_projection() FROM PUBLIC, tally_app, tally_core;
CREATE TRIGGER a_enforce_do_not_disconnect_projection BEFORE INSERT OR UPDATE OF do_not_disconnect ON public.customers
    FOR EACH ROW EXECUTE FUNCTION public.enforce_do_not_disconnect_projection();
ALTER TABLE public.customers ENABLE ALWAYS TRIGGER a_enforce_do_not_disconnect_projection;
-- r2 (Opus S4, Fable S5, Codex S4): the recompute runs on every load path,
-- a replica-mode history load included, as the fence does; otherwise a load
-- leaves the flag behind its enrollments and nothing may repair it.
ALTER TABLE public.customer_program_enrollments ENABLE ALWAYS TRIGGER enrollment_recompute_dnd;
COMMENT ON COLUMN public.customers.do_not_disconnect IS
    'Whether an active protective program enrollment covers the customer. v5.4.2-26: written only by recompute_do_not_disconnect from customer_program_enrollments; a direct write is refused. A collections decision cites it among its inputs; it is not itself an authorization.';


-- ----------------------------------------------------------------------------
-- 12. The invariants
-- ----------------------------------------------------------------------------
-- r2 (Opus S5): -26's own. Each list is the catalogue's own text of what
-- -26 built (tests/v5.4.2-26/fill-manifest.py writes it); a later patch that
-- drops, disables, loosens or regrants any of it fails here at apply.
CREATE OR REPLACE FUNCTION public.assert_collections_guard_invariants() RETURNS void
    LANGUAGE plpgsql STABLE
    SET search_path = public, pg_temp
    AS $fn$
DECLARE
    v_bad text;
    c_triggers CONSTANT text[] := ARRAY[
        -- @@TRIGGERS@@
        'CREATE TRIGGER a_enforce_adhoc_charge_decision BEFORE INSERT OR UPDATE OF collections_decision_id, triggered_by_invoice_id, charge_type ON public.adhoc_charges FOR EACH ROW EXECUTE FUNCTION enforce_adhoc_charge_decision()',
        'CREATE TRIGGER a_enforce_disconnect_order BEFORE INSERT OR UPDATE ON public.service_orders FOR EACH ROW EXECUTE FUNCTION enforce_disconnect_order()',
        'CREATE TRIGGER a_enforce_do_not_disconnect_projection BEFORE INSERT OR UPDATE OF do_not_disconnect ON public.customers FOR EACH ROW EXECUTE FUNCTION enforce_do_not_disconnect_projection()',
        'CREATE TRIGGER a_enforce_dunning_stage_projection BEFORE INSERT OR UPDATE OF dunning_stage ON public.invoices FOR EACH ROW EXECUTE FUNCTION enforce_dunning_stage_projection()',
        'CREATE TRIGGER a_enforce_late_fee_line BEFORE INSERT OR UPDATE OF charge_type, adhoc_charge_id, invoice_id ON public.invoice_line_items FOR EACH ROW EXECUTE FUNCTION enforce_late_fee_line()',
        'CREATE TRIGGER append_only BEFORE DELETE OR UPDATE ON public.collections_conditions FOR EACH ROW EXECUTE FUNCTION enforce_append_only()',
        'CREATE TRIGGER append_only BEFORE DELETE OR UPDATE ON public.collections_decisions FOR EACH ROW EXECUTE FUNCTION enforce_append_only()',
        'CREATE TRIGGER append_only BEFORE DELETE OR UPDATE ON public.service_order_field_approvals FOR EACH ROW EXECUTE FUNCTION enforce_append_only()',
        'CREATE TRIGGER append_only BEFORE DELETE OR UPDATE ON public.service_order_field_visits FOR EACH ROW EXECUTE FUNCTION enforce_append_only()',
        'CREATE TRIGGER a_stamp_created_at BEFORE INSERT ON public.collections_decisions FOR EACH ROW EXECUTE FUNCTION stamp_log_created_at()',
        'CREATE TRIGGER a_stamp_created_at BEFORE INSERT ON public.service_order_field_approvals FOR EACH ROW EXECUTE FUNCTION stamp_log_created_at()',
        'CREATE TRIGGER a_stamp_created_at BEFORE INSERT ON public.service_order_field_visits FOR EACH ROW EXECUTE FUNCTION stamp_log_created_at()',
        'CREATE TRIGGER b_enforce_collections_decision BEFORE INSERT ON public.collections_decisions FOR EACH ROW EXECUTE FUNCTION enforce_collections_decision()',
        'CREATE TRIGGER b_enforce_dunning_event BEFORE INSERT ON public.dunning_events FOR EACH ROW EXECUTE FUNCTION enforce_dunning_event()',
        'CREATE TRIGGER b_enforce_field_approval BEFORE INSERT ON public.service_order_field_approvals FOR EACH ROW EXECUTE FUNCTION enforce_field_approval()',
        'CREATE TRIGGER b_enforce_field_visit BEFORE INSERT ON public.service_order_field_visits FOR EACH ROW EXECUTE FUNCTION enforce_field_visit()',
        'CREATE TRIGGER enrollment_recompute_dnd AFTER INSERT OR DELETE OR UPDATE ON public.customer_program_enrollments FOR EACH ROW EXECUTE FUNCTION recompute_do_not_disconnect()',
        'CREATE TRIGGER no_truncate BEFORE TRUNCATE ON public.collections_conditions FOR EACH STATEMENT EXECUTE FUNCTION enforce_no_hard_delete()',
        'CREATE TRIGGER no_truncate BEFORE TRUNCATE ON public.collections_decisions FOR EACH STATEMENT EXECUTE FUNCTION enforce_no_hard_delete()',
        'CREATE TRIGGER no_truncate BEFORE TRUNCATE ON public.service_order_field_approvals FOR EACH STATEMENT EXECUTE FUNCTION enforce_no_hard_delete()',
        'CREATE TRIGGER no_truncate BEFORE TRUNCATE ON public.service_order_field_visits FOR EACH STATEMENT EXECUTE FUNCTION enforce_no_hard_delete()',
        'CREATE TRIGGER z_dunning_move_stage AFTER INSERT ON public.dunning_events FOR EACH ROW EXECUTE FUNCTION dunning_move_stage()'
    ];
    c_constraints CONSTANT text[] := ARRAY[
        -- @@CONSTRAINTS@@
        'adhoc_charges adhoc_charges_decision_fkey FOREIGN KEY (collections_decision_id, tenant_id, customer_id) REFERENCES collections_decisions(id, tenant_id, customer_id)',
        'collections_conditions collections_conditions_code_check CHECK ((condition_code ~ ''^[a-z][a-z0-9_]*$''::text))',
        'collections_conditions collections_conditions_description_check CHECK ((description ~ ''[[:alnum:]]''::text))',
        'collections_conditions collections_conditions_kind_check CHECK ((kind = ANY (ARRAY[''protection''::text, ''bar''::text, ''rule''::text])))',
        'collections_conditions collections_conditions_pkey PRIMARY KEY (condition_code)',
        'collections_decisions collections_decisions_act_check CHECK ((act = ANY (ARRAY[''notice''::text, ''late_fee''::text, ''disconnect_order''::text, ''disconnect_execute''::text, ''collections_referral''::text])))',
        'collections_decisions collections_decisions_calculated_by_check CHECK ((calculated_by ~ ''[[:alnum:]]''::text))',
        'collections_decisions collections_decisions_created_by_fkey FOREIGN KEY (created_by, tenant_id) REFERENCES users(id, tenant_id)',
        'collections_decisions collections_decisions_customer_fkey FOREIGN KEY (customer_id, tenant_id) REFERENCES customers(id, tenant_id)',
        'collections_decisions collections_decisions_id_tenant_customer_key UNIQUE (id, tenant_id, customer_id)',
        'collections_decisions collections_decisions_id_tenant_id_key UNIQUE (id, tenant_id)',
        'collections_decisions collections_decisions_inputs_check CHECK (((jsonb_typeof(inputs) = ''object''::text) AND (inputs_fingerprint ~ ''[[:alnum:]]''::text)))',
        'collections_decisions collections_decisions_invoice_fkey FOREIGN KEY (invoice_id, tenant_id, customer_id) REFERENCES invoices(id, tenant_id, customer_id)',
        'collections_decisions collections_decisions_location_fkey FOREIGN KEY (location_id, tenant_id) REFERENCES service_locations(id, tenant_id)',
        'collections_decisions collections_decisions_meter_fkey FOREIGN KEY (meter_id, tenant_id) REFERENCES meters(id, tenant_id)',
        'collections_decisions collections_decisions_outcome_check CHECK ((outcome = ANY (ARRAY[''eligible''::text, ''blocked''::text, ''unevaluable''::text])))',
        'collections_decisions collections_decisions_pkey PRIMARY KEY (id)',
        'collections_decisions collections_decisions_supersedes_fkey FOREIGN KEY (supersedes_id, tenant_id, customer_id) REFERENCES collections_decisions(id, tenant_id, customer_id)',
        'dunning_events dunning_events_decision_fkey FOREIGN KEY (collections_decision_id, tenant_id, customer_id) REFERENCES collections_decisions(id, tenant_id, customer_id)',
        'dunning_events dunning_events_invoice_id_fkey FOREIGN KEY (invoice_id, tenant_id, customer_id) REFERENCES invoices(id, tenant_id, customer_id)',
        'service_order_field_approvals service_order_field_approvals_approved_by_fkey FOREIGN KEY (approved_by, tenant_id) REFERENCES users(id, tenant_id)',
        'service_order_field_approvals service_order_field_approvals_id_tenant_id_key UNIQUE (id, tenant_id)',
        'service_order_field_approvals service_order_field_approvals_kind_check CHECK ((kind = ANY (ARRAY[''meter_mismatch''::text, ''no_evidence''::text])))',
        'service_order_field_approvals service_order_field_approvals_order_fkey FOREIGN KEY (service_order_id, tenant_id) REFERENCES service_orders(id, tenant_id)',
        'service_order_field_approvals service_order_field_approvals_pkey PRIMARY KEY (id)',
        'service_order_field_approvals service_order_field_approvals_reason_code_check CHECK ((reason_code ~ ''^[a-z][a-z0-9_]*$''::text))',
        'service_order_field_approvals service_order_field_approvals_visit_fkey FOREIGN KEY (visit_id, tenant_id) REFERENCES service_order_field_visits(id, tenant_id)',
        'service_order_field_visits service_order_field_visits_created_by_fkey FOREIGN KEY (created_by, tenant_id) REFERENCES users(id, tenant_id)',
        'service_order_field_visits service_order_field_visits_decision_fkey FOREIGN KEY (collections_decision_id, tenant_id) REFERENCES collections_decisions(id, tenant_id)',
        'service_order_field_visits service_order_field_visits_id_tenant_id_key UNIQUE (id, tenant_id)',
        'service_order_field_visits service_order_field_visits_mismatch_approval_fkey FOREIGN KEY (mismatch_approval_id, tenant_id) REFERENCES service_order_field_approvals(id, tenant_id)',
        'service_order_field_visits service_order_field_visits_no_evidence_approval_fkey FOREIGN KEY (no_evidence_approval_id, tenant_id) REFERENCES service_order_field_approvals(id, tenant_id)',
        'service_order_field_visits service_order_field_visits_order_fkey FOREIGN KEY (service_order_id, tenant_id) REFERENCES service_orders(id, tenant_id)',
        'service_order_field_visits service_order_field_visits_outcome_check CHECK (((outcome = ANY (ARRAY[''executed''::text, ''aborted''::text])) AND ((outcome = ''aborted''::text) = (abort_reason IS NOT NULL)) AND ((abort_reason IS NULL) OR (abort_reason = ANY (ARRAY[''meter_mismatch''::text, ''payment_shown''::text, ''medical_evidence''::text, ''dispute_pending''::text, ''no_access''::text, ''safety''::text, ''other''::text]))) AND ((outcome = ''executed''::text) OR ((collections_decision_id IS NULL) AND (mismatch_approval_id IS NULL) AND (no_evidence_approval_id IS NULL)))))',
        'service_order_field_visits service_order_field_visits_pkey PRIMARY KEY (id)',
        'service_orders service_orders_decision_fkey FOREIGN KEY (collections_decision_id, tenant_id, customer_id) REFERENCES collections_decisions(id, tenant_id, customer_id)'
    ];
    c_indexes CONSTANT text[] := ARRAY[
        -- @@INDEXES@@
        'CREATE UNIQUE INDEX adhoc_charges_one_per_decision ON public.adhoc_charges USING btree (collections_decision_id) WHERE (collections_decision_id IS NOT NULL)',
        'CREATE UNIQUE INDEX dunning_events_one_per_decision ON public.dunning_events USING btree (collections_decision_id, invoice_id) WHERE (collections_decision_id IS NOT NULL)',
        'CREATE UNIQUE INDEX service_order_field_visits_one_executed ON public.service_order_field_visits USING btree (service_order_id) WHERE (outcome = ''executed''::text)',
        'CREATE UNIQUE INDEX service_order_field_visits_one_per_decision ON public.service_order_field_visits USING btree (collections_decision_id) WHERE (collections_decision_id IS NOT NULL)',
        'CREATE UNIQUE INDEX service_orders_one_per_decision ON public.service_orders USING btree (collections_decision_id) WHERE (collections_decision_id IS NOT NULL)'
    ];
    c_tables CONSTANT text[] := ARRAY[
        -- @@TABLES@@
        'collections_conditions | {tally=arwdDxt/tally,tally_app=r/tally,tally_core=r/tally} | false | false',
        'collections_decisions | {tally=arwdDxt/tally,tally_app=ar/tally,tally_core=r/tally} | true | true',
        'collections_record_seq | {tally=rwU/tally,tally_app=U/tally} | false | false',
        'service_order_field_approvals | {tally=arwdDxt/tally,tally_app=ar/tally,tally_core=r/tally} | true | true',
        'service_order_field_visits | {tally=arwdDxt/tally,tally_app=ar/tally,tally_core=r/tally} | true | true'
    ];
    c_funcs CONSTANT text[] := ARRAY[
        -- @@FUNCS@@
        'collections_act_check(uuid,text,uuid,uuid,uuid,date,boolean,text) | false | search_path=public, pg_temp | {tally=X/tally,tally_app=X/tally} | fa5d0d32798278c4992a4fe6a068f730',
        'collections_dunning_act(text) | false | search_path=public, pg_temp | {tally=X/tally,tally_app=X/tally,tally_core=X/tally} | d0b1c60d4468467c60f3e1267a768cb5',
        'collections_dunning_stage(text,text) | false | search_path=public, pg_temp | {tally=X/tally,tally_app=X/tally,tally_core=X/tally} | 4a84b68dd65f7bf2e8ef666f16c695c4',
        'collections_live_decision(uuid,text,uuid,uuid,uuid,uuid) | false | search_path=public, pg_temp | {tally=X/tally,tally_app=X/tally,tally_core=X/tally} | 5664aca156e9333ca55bc3f1b7687092',
        'collections_subject_lock(uuid,text,uuid,uuid,uuid,uuid,text) | false | search_path=public, pg_temp | {tally=X/tally,tally_app=X/tally} | 989726561d9a07397fcd5366645c3762',
        'collections_tenant_check(text,uuid) | false | search_path=public, pg_temp | {tally=X/tally,tally_app=X/tally} | 34b48e32230558f03f17bc0e9c0dd94b',
        'dunning_move_stage() | false | search_path=public, pg_temp | {tally=X/tally} | 91d923786cbc7d8f1356907daf693862',
        'enforce_adhoc_charge_decision() | false | search_path=public, pg_temp | {tally=X/tally} | 3c3e8502b1adfa3d1021ccb05cf9c674',
        'enforce_collections_decision() | false | search_path=public, pg_temp | {tally=X/tally} | a251d2aa966a5aa08cbd9757b495283c',
        'enforce_disconnect_order() | false | search_path=public, pg_temp | {tally=X/tally} | a33d09b7d044f26c98ad978eabc9e300',
        'enforce_do_not_disconnect_projection() | false | search_path=public, pg_temp | {tally=X/tally} | a24841f9cbd29ed54831ad5d322a73b8',
        'enforce_dunning_event() | false | search_path=public, pg_temp | {tally=X/tally} | 762cca7a062aea0732fb7855276387a5',
        'enforce_dunning_stage_projection() | false | search_path=public, pg_temp | {tally=X/tally} | aa535ee6ca418d9d92d23e83ea207a13',
        'enforce_field_approval() | false | search_path=public, pg_temp | {tally=X/tally} | 84da1f4fb9c30a4c995bd941b7641d58',
        'enforce_field_visit() | false | search_path=public, pg_temp | {tally=X/tally} | e7ac61aff23909e17833293c271bddb9',
        'enforce_late_fee_line() | false | search_path=public, pg_temp | {tally=X/tally} | f886a51d9e071ec03103f52f85168e66'
    ];
BEGIN
    SELECT string_agg(d, E'\n  ' ORDER BY d) INTO v_bad FROM unnest(c_triggers) d
     WHERE NOT EXISTS (SELECT 1 FROM pg_catalog.pg_trigger t
                        WHERE NOT t.tgisinternal AND t.tgenabled = 'A' AND pg_catalog.pg_get_triggerdef(t.oid) = d);
    IF v_bad IS NOT NULL THEN
        RAISE EXCEPTION USING MESSAGE = format(E'a v5.4.2-26 trigger is missing, changed, or not ENABLE ALWAYS:\n  %s', v_bad), ERRCODE = 'invalid_grant_operation';
    END IF;
    SELECT string_agg(d, E'\n  ' ORDER BY d) INTO v_bad FROM unnest(c_constraints) d
     WHERE NOT EXISTS (SELECT 1 FROM pg_catalog.pg_constraint k
                        WHERE k.convalidated AND k.conrelid::regclass::text || ' ' || k.conname || ' ' || pg_catalog.pg_get_constraintdef(k.oid) = d);
    IF v_bad IS NOT NULL THEN
        RAISE EXCEPTION USING MESSAGE = format(E'a v5.4.2-26 constraint is missing, changed or not validated:\n  %s', v_bad), ERRCODE = 'invalid_grant_operation';
    END IF;
    SELECT string_agg(d, E'\n  ' ORDER BY d) INTO v_bad FROM unnest(c_indexes) d
     WHERE NOT EXISTS (SELECT 1 FROM pg_catalog.pg_indexes x
                         JOIN pg_catalog.pg_class i ON i.relname = x.indexname AND i.relnamespace = 'public'::regnamespace
                         JOIN pg_catalog.pg_index n ON n.indexrelid = i.oid
                        WHERE x.schemaname = 'public' AND n.indisvalid AND x.indexdef = d);
    IF v_bad IS NOT NULL THEN
        RAISE EXCEPTION USING MESSAGE = format(E'a v5.4.2-26 unique index is missing, changed or not valid:\n  %s', v_bad), ERRCODE = 'invalid_grant_operation';
    END IF;
    SELECT string_agg(d, E'\n  ' ORDER BY d) INTO v_bad FROM unnest(c_tables) d
     WHERE NOT EXISTS (SELECT 1 FROM pg_catalog.pg_class c
                        WHERE c.oid = pg_catalog.to_regclass('public.' || split_part(d, ' | ', 1))
                          AND split_part(d, ' | ', 1) || ' | ' || coalesce(c.relacl::text, '-') || ' | ' || c.relrowsecurity::text || ' | ' || c.relforcerowsecurity::text = d);
    IF v_bad IS NOT NULL THEN
        RAISE EXCEPTION USING MESSAGE = format(E'a v5.4.2-26 table''s grants or row security have changed:\n  %s', v_bad), ERRCODE = 'invalid_grant_operation';
    END IF;
    SELECT string_agg(d, E'\n  ' ORDER BY d) INTO v_bad FROM unnest(c_funcs) d
     WHERE NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc f
                        WHERE f.oid = pg_catalog.to_regprocedure('public.' || split_part(d, ' | ', 1))
                          AND split_part(d, ' | ', 1) || ' | ' || f.prosecdef::text || ' | ' || coalesce(array_to_string(f.proconfig, ';'), '-')
                              || ' | ' || coalesce(f.proacl::text, '-') || ' | ' || pg_catalog.md5(f.prosrc) = d);
    IF v_bad IS NOT NULL THEN
        RAISE EXCEPTION USING MESSAGE = format(E'a v5.4.2-26 function is missing, or its body, security, settings or grants have changed:\n  %s', v_bad), ERRCODE = 'invalid_grant_operation';
    END IF;
END;
$fn$;
COMMENT ON FUNCTION public.assert_collections_guard_invariants() IS
    'v5.4.2-26 (r2). Raises invalid_grant_operation (0LP01) unless every -26 trigger is present and ENABLE ALWAYS, every -26 constraint and unique index is present and valid, the -26 tables'' grants and row security are as built, and every -26 function''s body, security, settings and grants are as built. The lists are the catalogue''s own text (tests/v5.4.2-26/fill-manifest.py).';
REVOKE ALL ON FUNCTION public.assert_collections_guard_invariants() FROM PUBLIC;

DO $$ BEGIN
    PERFORM public.assert_collections_guard_invariants();
    PERFORM public.assert_dispute_guard_invariants();
    PERFORM public.assert_shortfall_guard_invariants();
    PERFORM public.assert_suspense_pledge_guard_invariants();
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
-- END PATCH v5.4.2-26
-- ============================================================================

COMMIT;
\endif
